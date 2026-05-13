local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local BrainrotsCfg = CrewCatalog.GetLegacyConfig()
local VariantCfg = CrewCatalog.GetVariantConfig()
local CrewQuickSlotService = require(script.Parent:WaitForChild("CrewQuickSlotService"))
local CrewStandIncomeAuthority = require(script.Parent:WaitForChild("CrewStandIncomeAuthority"))
local IndexCollectionService = require(script.Parent:WaitForChild("IndexCollectionService"))

local Module = {}
local DataManagerModule
local CrewStorageModule
local CrewMemberShadowWriterModule
local inventorySavedCallbacks = {}
local TUTORIAL_COMPLETION_PATH = "HiddenLeaderstats.Tutorial"
local CANONICAL_INVENTORY_PATH = "CrewMemberInventory"
local INVENTORY_AUTHORITY_AUDIT_PATH = "CrewMemberInventoryAuthorityAudit"
local PROGRESSION_AUTHORITY_AUDIT_PATH = "CrewMemberProgressionAuthorityAudit"
local INVENTORY_AUTHORITY_SNAPSHOT_VERSION = 1
-- Function names still carry legacy terms for callers, but normal gameplay now
-- reads and writes CrewMemberInventory. Legacy inventory roots are repair mirrors.

local CREW_PICKUP_DEBUG = true

local function crewPickupDebug(message, ...)
	if CREW_PICKUP_DEBUG ~= true then
		return
	end

	local prefix = "[CrewPickupDebug] "
	if select("#", ...) == 0 then
		warn(prefix .. tostring(message))
		return
	end

	local ok, formatted = pcall(string.format, prefix .. tostring(message), ...)
	warn(ok and formatted or (prefix .. tostring(message)))
end

local function formatCrewPickupDebugFields(fields)
	local parts = {}
	for _, field in ipairs(fields or {}) do
		parts[#parts + 1] = tostring(field[1]) .. "=" .. tostring(field[2])
	end
	return table.concat(parts, " ")
end

local function ensureTable(parent, key)
	if typeof(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

local function coerceNumber(value, fallback)
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

local function getDataManager()
	if not DataManagerModule then
		DataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return DataManagerModule
end

local function getCrewStorage()
	if not CrewStorageModule then
		CrewStorageModule = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewStorage"))
	end
	return CrewStorageModule
end

local function getCrewMemberShadowWriter()
	if not CrewMemberShadowWriterModule then
		CrewMemberShadowWriterModule = require(
			ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewMemberShadowWriter")
		)
	end
	return CrewMemberShadowWriterModule
end

local function runCrewMemberShadowRefresh(player, reason, writerMethodName)
	local flags = getCrewStorage().GetShadowFlags()
	if flags.CrewMemberShadowWriteEnabled ~= true then
		return nil
	end

	local dataManager = getDataManager()
	local profile = dataManager.TryGetProfile and dataManager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return nil
	end

	local ok, result = pcall(function()
		local writer = getCrewMemberShadowWriter()
		local method = writer[writerMethodName]
		return method(profile.Data, reason, {
			Player = player,
			Flags = flags,
		})
	end)

	if not ok then
		warn(string.format(
			"[CrewInstanceService] CrewMember shadow refresh failed player=%s reason=%s error=%s",
			player and player.Name or "unknown",
			tostring(reason),
			tostring(result)
		))
	elseif result and result.StrictFailure == true then
		warn(string.format(
			"[CrewInstanceService] CrewMember shadow refresh strict failure player=%s reason=%s",
			player and player.Name or "unknown",
			tostring(reason)
		))
	end

	return result
end

local function refreshCrewMemberShadow(_player, _reason)
	-- Normal inventory/stand flows write CrewMember roots directly now. Legacy
	-- projection stays available through migration and destructive repair tools.
	return nil
end

local function refreshCrewMemberShadowAfterDestructiveReset(player, reason)
	return runCrewMemberShadowRefresh(player, reason, "RefreshAfterDestructiveLegacyReset")
end

function Module.RefreshCrewMemberShadow(player, reason)
	return refreshCrewMemberShadow(player, reason)
end

function Module.RefreshCrewMemberShadowAfterDestructiveLegacyReset(player, reason)
	return refreshCrewMemberShadowAfterDestructiveReset(player, reason)
end

local function isTutorialIncomplete(player)
	return getDataManager():GetValue(player, TUTORIAL_COMPLETION_PATH) ~= true
end

local function isProtectedTutorialReward(player, instanceData)
	return typeof(instanceData) == "table" and instanceData.TutorialReward == true and isTutorialIncomplete(player)
end

local function notifyInventorySaved(player, brainrotInventory)
	for callback in pairs(inventorySavedCallbacks) do
		local ok, err = pcall(callback, player, brainrotInventory)
		if not ok then
			warn(string.format("[CrewInstanceService] Inventory save callback failed: %s", tostring(err)))
		end
	end
end

local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName or "")

	for _, variantKey in ipairs(VariantCfg.Order or {}) do
		if variantKey ~= "Normal" then
			local variantData = (VariantCfg.Versions or {})[variantKey]
			local prefix = tostring((variantData and variantData.Prefix) or (variantKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				return variantKey, fullName:sub(#prefix + 1)
			end
		end
	end

	return "Normal", fullName
end

local function isBrainrotInventoryEntry(key, entry)
	if key == "Feed" or key == "DevilFruits" then
		return false
	end
	if typeof(entry) ~= "table" then
		return false
	end
	return entry.Quantity ~= nil
		or entry.BaseName ~= nil
		or entry.Variant ~= nil
		or entry.Rarity ~= nil
		or entry.Level ~= nil
		or entry.CurrentXP ~= nil
end

local function buildMetadata(storageName, entry)
	entry = entry or {}

	local variantKey = tostring(entry.Variant or "")
	local baseName = tostring(entry.BaseName or "")
	if baseName == "" then
		variantKey, baseName = getVariantAndBaseName(storageName)
	end
	if variantKey == "" then
		variantKey = "Normal"
	end

	local info = CrewCatalog.GetInfoById(storageName) or CrewCatalog.GetInfoById(baseName) or BrainrotsCfg[storageName] or BrainrotsCfg[baseName] or {}
	local baseInfo = CrewCatalog.GetInfoById(baseName) or BrainrotsCfg[baseName] or info

	local render = tostring(entry.Render or info.Render or "")
	local goldenRender = tostring(entry.GoldenRender or baseInfo.GoldenRender or baseInfo.Render or render)
	local diamondRender = tostring(entry.DiamondRender or baseInfo.DiamondRender or baseInfo.Render or render)

	return {
		StorageName = tostring(storageName),
		BaseName = baseName,
		Variant = variantKey,
		Rarity = tostring(entry.Rarity or info.Rarity or "Common"),
		Income = tonumber(entry.Income or info.Income) or 0,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
		DisplayName = tostring(info.DisplayName or info.Name or storageName),
		CrewMemberId = tostring(info.CrewMemberId or storageName),
		RealCharacterName = tostring(info.RealCharacterName or ""),
		Arc = tostring(info.Arc or ""),
		ModelName = tostring(info.ModelName or baseName),
	}
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneValue(child)
	end
	return copy
end

local function isInventoryWriteAuthorityEnabled(flags)
	flags = if typeof(flags) == "table" then flags else getCrewStorage().GetShadowFlags()
	return flags.CrewMemberInventoryWriteAuthorityEnabled == true, flags
end

local function isProgressionWriteAuthorityEnabled(flags)
	flags = if typeof(flags) == "table" then flags else getCrewStorage().GetShadowFlags()
	return flags.CrewMemberProgressionWriteAuthorityEnabled == true, flags
end

local function isKnownCrewStorageName(storageName)
	storageName = tostring(storageName or "")
	if storageName == "" then
		return false
	end

	local _, baseName = getVariantAndBaseName(storageName)
	return CrewCatalog.GetInfoById(storageName) ~= nil
		or CrewCatalog.GetInfoById(baseName) ~= nil
		or BrainrotsCfg[storageName] ~= nil
		or BrainrotsCfg[baseName] ~= nil
end

local function ensureBrainrotInventoryShape(brainrotInventory)
	if typeof(brainrotInventory) ~= "table" then
		brainrotInventory = {}
	end

	brainrotInventory.NextInstanceId = math.max(1, coerceNumber(brainrotInventory.NextInstanceId, 1))
	brainrotInventory.ById = ensureTable(brainrotInventory, "ById")
	brainrotInventory.Order = ensureTable(brainrotInventory, "Order")

	return brainrotInventory
end

local function normalizeInstanceData(instanceId, instanceData, fallbackStorageName, options)
	instanceData = typeof(instanceData) == "table" and instanceData or {}
	options = if typeof(options) == "table" then options else {}

	local storageName = tostring(
		instanceData.LegacyStorageName
			or instanceData.StorageName
			or fallbackStorageName
			or instanceData.BrainrotName
			or ""
	)
	if storageName == "" then
		return nil
	end

	local metadata = buildMetadata(storageName, instanceData)

	local normalized = {
		InstanceId = tostring(instanceId),
		StorageName = metadata.StorageName,
		BaseName = metadata.BaseName,
		Variant = metadata.Variant,
		Rarity = tostring(instanceData.Rarity or metadata.Rarity or "Common"),
		Income = tonumber(instanceData.Income or metadata.Income) or 0,
		Render = tostring(instanceData.Render or metadata.Render or ""),
		GoldenRender = tostring(instanceData.GoldenRender or metadata.GoldenRender or metadata.Render or ""),
		DiamondRender = tostring(instanceData.DiamondRender or metadata.DiamondRender or metadata.Render or ""),
		Level = math.max(1, math.floor(coerceNumber(instanceData.Level, 1))),
		CurrentXP = math.max(0, math.floor(coerceNumber(instanceData.CurrentXP, 0))),
		TotalXP = math.max(0, math.floor(coerceNumber(instanceData.TotalXP, 0))),
		AssignedStand = tostring(instanceData.AssignedStand or ""),
		AcquiredAt = coerceNumber(instanceData.AcquiredAt, os.time()),
		LastReleasedAt = coerceNumber(instanceData.LastReleasedAt, 0),
		Source = tostring(instanceData.Source or ""),
		DepthBand = tostring(instanceData.DepthBand or ""),
		TutorialReward = instanceData.TutorialReward == true,
		TutorialToken = tostring(instanceData.TutorialToken or ""),
		GrandLineRushStarter = instanceData.GrandLineRushStarter == true,
	}
	if options.Canonical == true then
		normalized.CrewMemberId = tostring(instanceData.CrewMemberId or metadata.CrewMemberId or metadata.StorageName)
		normalized.DisplayName = tostring(instanceData.DisplayName or metadata.DisplayName or metadata.StorageName)
		normalized.LegacyStorageName = metadata.StorageName
		normalized.ProjectionSource = tostring(instanceData.ProjectionSource or "CrewInstanceService")
	end
	return normalized
end

local syncAvailableCounts
local inspectInventoryRoot

local function normalizeInventoryData(rawInventory, options)
	options = if typeof(options) == "table" then options else {}
	local inventory = ensureBrainrotInventoryShape(rawInventory)
	local changed = false
	if options.Canonical == true then
		local schemaVersion = math.max(1, math.floor(coerceNumber(inventory.SchemaVersion, 1)))
		if inventory.SchemaVersion ~= schemaVersion then
			inventory.SchemaVersion = schemaVersion
			changed = true
		end
	elseif inventory.SchemaVersion ~= nil then
		inventory.SchemaVersion = nil
		changed = true
	end

	local normalizedOrder = {}
	local seen = {}
	local maxInstanceNumber = inventory.NextInstanceId - 1
	for _, rawInstanceId in ipairs(inventory.Order) do
		local instanceId = tostring(rawInstanceId)
		maxInstanceNumber = math.max(maxInstanceNumber, tonumber(instanceId) or 0)
		local normalized = normalizeInstanceData(instanceId, inventory.ById[instanceId], nil, {
			Canonical = options.Canonical == true,
		})
		if normalized then
			inventory.ById[instanceId] = normalized
			if not seen[instanceId] then
				seen[instanceId] = true
				table.insert(normalizedOrder, instanceId)
			else
				changed = true
			end
		else
			inventory.ById[instanceId] = nil
			changed = true
		end
	end

	for instanceId, instanceData in pairs(inventory.ById) do
		instanceId = tostring(instanceId)
		maxInstanceNumber = math.max(maxInstanceNumber, tonumber(instanceId) or 0)
		if not seen[instanceId] then
			local normalized = normalizeInstanceData(instanceId, instanceData, nil, {
				Canonical = options.Canonical == true,
			})
			if normalized then
				inventory.ById[instanceId] = normalized
				table.insert(normalizedOrder, instanceId)
				seen[instanceId] = true
				changed = true
			else
				inventory.ById[instanceId] = nil
				changed = true
			end
		end
	end

	if #normalizedOrder ~= #inventory.Order then
		changed = true
	end
	inventory.Order = normalizedOrder
	if inventory.NextInstanceId <= maxInstanceNumber then
		inventory.NextInstanceId = maxInstanceNumber + 1
		changed = true
	end

	return inventory, changed
end

local function getAvailableCountsFromInventory(inventory)
	local counts = {}
	if typeof(inventory) ~= "table" or typeof(inventory.Order) ~= "table" or typeof(inventory.ById) ~= "table" then
		return counts
	end

	for _, instanceId in ipairs(inventory.Order) do
		local instanceData = inventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == "" then
			local storageName = tostring(instanceData.StorageName or "")
			if storageName ~= "" then
				counts[storageName] = (counts[storageName] or 0) + 1
			end
		end
	end
	return counts
end

local function buildInventoryAuthoritySnapshot(player, sourcePath)
	return {
		Kind = "inventory_write_authority",
		Version = INVENTORY_AUTHORITY_SNAPSHOT_VERSION,
		PlayerUserId = player and player.UserId or 0,
		PlaceId = game.PlaceId,
		GameId = game.GameId,
		SourcePath = tostring(sourcePath or ""),
		CreatedAt = os.time(),
		Canonical = cloneValue(getDataManager():GetValue(player, CANONICAL_INVENTORY_PATH)),
	}
end

local function writeProfileRoot(player, path, value)
	local ok, reason = getDataManager():TrySetValue(player, path, value)
	return ok == true, tostring(reason or "")
end

local function updateInventoryAuthorityAudit(player, updates)
	local audit = getDataManager():GetValue(player, INVENTORY_AUTHORITY_AUDIT_PATH)
	if typeof(audit) ~= "table" then
		audit = {}
	else
		audit = cloneValue(audit)
	end

	for key, value in pairs(if typeof(updates) == "table" then updates else {}) do
		if key ~= "ClearKeys" then
			audit[key] = value
		end
	end
	for _, key in ipairs(if typeof(updates) == "table" and typeof(updates.ClearKeys) == "table" then updates.ClearKeys else {}) do
		audit[tostring(key)] = nil
	end
	audit.UpdatedAt = os.time()

	getDataManager():TrySetValue(player, INVENTORY_AUTHORITY_AUDIT_PATH, audit)
	return audit
end

local function updateProgressionAuthorityAudit(player, updates)
	local audit = getDataManager():GetValue(player, PROGRESSION_AUTHORITY_AUDIT_PATH)
	if typeof(audit) ~= "table" then
		audit = {}
	else
		audit = cloneValue(audit)
	end

	for key, value in pairs(if typeof(updates) == "table" then updates else {}) do
		audit[key] = value
	end
	audit.UpdatedAt = os.time()

	getDataManager():TrySetValue(player, PROGRESSION_AUTHORITY_AUDIT_PATH, audit)
	return audit
end

local function restoreInventoryAuthoritySnapshot(player, snapshot, reason)
	if typeof(snapshot) ~= "table" then
		return false, "snapshot_missing"
	end
	if snapshot.Kind ~= "inventory_write_authority" then
		return false, "snapshot_kind_mismatch"
	end
	if tonumber(snapshot.PlayerUserId) ~= (player and player.UserId or 0) then
		return false, "snapshot_user_mismatch"
	end
	if tonumber(snapshot.PlaceId) ~= game.PlaceId or tonumber(snapshot.GameId) ~= game.GameId then
		return false, "snapshot_environment_mismatch"
	end
	local canonicalShape = inspectInventoryRoot("CrewMemberInventory", snapshot.Canonical)
	if #canonicalShape.Issues > 0 then
		return false, "snapshot_root_invalid:CrewMemberInventory:" .. table.concat(canonicalShape.Issues, ",")
	end

	local writes = {}
	local canonicalOk, canonicalReason = writeProfileRoot(player, CANONICAL_INVENTORY_PATH, cloneValue(snapshot.Canonical) or {})
	writes.CrewMemberInventory = canonicalOk
	if not canonicalOk then
		return false, "rollback_write_failed:CrewMemberInventory:" .. canonicalReason
	end

	updateInventoryAuthorityAudit(player, {
		LastRollback = {
			Reason = tostring(reason or ""),
			SourcePath = tostring(snapshot.SourcePath or ""),
			Writes = writes,
			CompletedAt = os.time(),
		},
	})

	return true, nil
end

inspectInventoryRoot = function(rootName, inventory)
	local issues = {}
	local counts = {}
	local normalized = nil
	local instanceCount = 0

	if typeof(inventory) ~= "table" then
		return {
			RootName = rootName,
			Issues = { rootName .. "_missing" },
			Counts = counts,
			InstanceCount = instanceCount,
		}
	end

	normalized = normalizeInventoryData(cloneValue(inventory), {
		Canonical = rootName == "CrewMemberInventory",
	})

	if typeof(inventory.ById) ~= "table" then
		issues[#issues + 1] = rootName .. "_byid_missing"
	end
	if typeof(inventory.Order) ~= "table" then
		issues[#issues + 1] = rootName .. "_order_missing"
	end
	if math.floor(coerceNumber(inventory.NextInstanceId, 0)) < 1 then
		issues[#issues + 1] = rootName .. "_next_instance_id_invalid"
	end

	local seen = {}
	local maxInstanceNumber = 0
	for _, rawInstanceId in ipairs(if typeof(inventory.Order) == "table" then inventory.Order else {}) do
		local instanceId = tostring(rawInstanceId)
		if seen[instanceId] == true then
			issues[#issues + 1] = rootName .. "_duplicate_order_id:" .. instanceId
		end
		seen[instanceId] = true
		maxInstanceNumber = math.max(maxInstanceNumber, tonumber(instanceId) or 0)
	end

	for instanceId, rawInstanceData in pairs(if typeof(inventory.ById) == "table" then inventory.ById else {}) do
		instanceId = tostring(instanceId)
		maxInstanceNumber = math.max(maxInstanceNumber, tonumber(instanceId) or 0)
		if seen[instanceId] ~= true then
			issues[#issues + 1] = rootName .. "_byid_missing_from_order:" .. instanceId
		end
		local instanceData = normalizeInstanceData(instanceId, rawInstanceData, nil, {
			Canonical = rootName == "CrewMemberInventory",
		})
		if instanceData == nil then
			issues[#issues + 1] = rootName .. "_invalid_instance:" .. instanceId
		else
			instanceCount += 1
			if not isKnownCrewStorageName(instanceData.StorageName) then
				issues[#issues + 1] = rootName .. "_unknown_crew_id:" .. tostring(instanceData.StorageName)
			end
			if tostring(instanceData.AssignedStand or "") == "" then
				counts[instanceData.StorageName] = (counts[instanceData.StorageName] or 0) + 1
			end
		end
	end

	if (tonumber(inventory.NextInstanceId) or 0) <= maxInstanceNumber then
		issues[#issues + 1] = rootName .. "_next_instance_id_not_sane"
	end

	return {
		RootName = rootName,
		Issues = issues,
		Counts = counts,
		Inventory = normalized,
		InstanceCount = instanceCount,
	}
end

local function validateInventoryMirrors(player)
	local canonicalRaw = getDataManager():GetValue(player, CANONICAL_INVENTORY_PATH)
	local canonical = inspectInventoryRoot("CrewMemberInventory", canonicalRaw)
	local issues = {}

	for _, issue in ipairs(canonical.Issues) do
		issues[#issues + 1] = issue
	end

	local canonicalInventory = canonical.Inventory
	local expectedCounts = getAvailableCountsFromInventory(canonicalInventory)

	local status = {
		Passed = #issues == 0,
		MirrorMatch = #issues == 0,
		RootsMatch = #issues == 0,
		BrainrotInventoryRetired = true,
		InventoryCrewMirrorsRetired = true,
		BlockingCount = #issues,
		UnclassifiedCount = 0,
		Issues = issues,
		Canonical = {
			NextInstanceId = if canonicalInventory then canonicalInventory.NextInstanceId else nil,
			InstanceCount = canonical.InstanceCount,
			Counts = expectedCounts,
		},
		BrainrotInventory = {
			Retired = true,
		},
	}
	updateInventoryAuthorityAudit(player, {
		LastValidation = {
			Passed = status.Passed,
			MirrorMatch = status.MirrorMatch,
			BlockingCount = status.BlockingCount,
			UnclassifiedCount = status.UnclassifiedCount,
			Issues = cloneValue(issues),
			CheckedAt = os.time(),
		},
	})
	return status
end

local function ensureInventoryAuthorityReady(player, sourcePath)
	local enabled, flags = isInventoryWriteAuthorityEnabled()
	if enabled ~= true then
		return true, nil
	end

	local blockingFlag = nil
	if flags.CrewMemberCanonicalReadEnabled == true then
		blockingFlag = "canonical_read_enabled"
	elseif flags.CrewMemberCanaryGameplayReadsEnabled == true then
		blockingFlag = "gameplay_reads_enabled"
	elseif flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		blockingFlag = "profile_migration_write_enabled"
	elseif flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		blockingFlag = "broad_write_authority_enabled"
	elseif flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		blockingFlag = "quick_slots_write_authority_enabled"
	elseif flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true then
		blockingFlag = "product_quick_slot_write_authority_enabled"
	end
	if blockingFlag ~= nil then
		updateInventoryAuthorityAudit(player, {
			LastFailClosedReason = blockingFlag,
			LastFailClosedSourcePath = tostring(sourcePath or ""),
		})
		return false, blockingFlag
	end

	local status = validateInventoryMirrors(player)
	if status.Passed ~= true then
		local reason = "inventory_mirror_validation_failed"
		updateInventoryAuthorityAudit(player, {
			LastFailClosedReason = reason,
			LastFailClosedSourcePath = tostring(sourcePath or ""),
			LastFailClosedIssues = cloneValue(status.Issues),
		})
		return false, reason
	end

	return true, nil
end

local function ensureProgressionAuthorityReady(player, sourcePath)
	local enabled, flags = isProgressionWriteAuthorityEnabled()
	if enabled ~= true then
		return true, nil
	end

	local blockingFlag = nil
	if flags.CrewMemberCanonicalReadEnabled == true then
		blockingFlag = "canonical_read_enabled"
	elseif flags.CrewMemberCanaryGameplayReadsEnabled == true then
		blockingFlag = "gameplay_reads_enabled"
	elseif flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		blockingFlag = "profile_migration_write_enabled"
	elseif flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true then
		blockingFlag = "profile_migration_dry_run_enabled"
	elseif flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		blockingFlag = "broad_write_authority_enabled"
	elseif flags.CrewMemberCanaryReadAuthorityEnabled == true then
		blockingFlag = "read_authority_enabled"
	elseif flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		blockingFlag = "quick_slots_write_authority_enabled"
	elseif flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true then
		blockingFlag = "product_quick_slot_write_authority_enabled"
	end
	if blockingFlag ~= nil then
		updateProgressionAuthorityAudit(player, {
			LastFailClosedReason = blockingFlag,
			LastFailClosedSourcePath = tostring(sourcePath or ""),
		})
		return false, blockingFlag
	end

	local status = validateInventoryMirrors(player)
	if status.Passed ~= true then
		local reason = "inventory_mirror_validation_failed"
		updateProgressionAuthorityAudit(player, {
			LastFailClosedReason = reason,
			LastFailClosedSourcePath = tostring(sourcePath or ""),
			LastFailClosedIssues = cloneValue(status.Issues),
		})
		return false, reason
	end

	return true, nil
end

local function saveCrewInventoryAndMirrors(player, crewInventory, options)
	options = if typeof(options) == "table" then options else {}
	local sourcePath = tostring(options.SourcePath or "unknown")
	local snapshot = buildInventoryAuthoritySnapshot(player, sourcePath)
	local canonicalInventory = normalizeInventoryData(cloneValue(crewInventory), {
		Canonical = true,
	})
	local writes = {}

	updateInventoryAuthorityAudit(player, {
		LastRollbackSnapshot = snapshot,
		LastMutation = {
			SourcePath = sourcePath,
			StartedAt = os.time(),
			BeforeCounts = getAvailableCountsFromInventory(snapshot.Canonical),
			AfterCounts = getAvailableCountsFromInventory(canonicalInventory),
			ReconciliationUsed = options.ReconciliationUsed == true,
		},
	})

	local canonicalOk, canonicalReason = writeProfileRoot(player, CANONICAL_INVENTORY_PATH, canonicalInventory)
	writes.CrewMemberInventory = canonicalOk
	if not canonicalOk then
		restoreInventoryAuthoritySnapshot(player, snapshot, "canonical_write_failed")
		updateInventoryAuthorityAudit(player, {
			LastFailClosedReason = "inventory_write_failed:CrewMemberInventory:" .. canonicalReason,
		})
		return false, "inventory_write_failed:CrewMemberInventory:" .. canonicalReason
	end

	notifyInventorySaved(player, canonicalInventory)

	local status = validateInventoryMirrors(player)
	if status.Passed ~= true then
		local restoreOk, restoreReason = restoreInventoryAuthoritySnapshot(player, snapshot, "post_validation_failed")
		updateInventoryAuthorityAudit(player, {
			LastFailClosedReason = "inventory_post_validation_failed",
			LastFailClosedIssues = cloneValue(status.Issues),
			LastRollbackRestoreOk = restoreOk,
			LastRollbackRestoreReason = restoreReason,
		})
		return false, "inventory_post_validation_failed"
	end

	updateInventoryAuthorityAudit(player, {
		LastMutation = {
			SourcePath = sourcePath,
			CompletedAt = os.time(),
			BeforeCounts = getAvailableCountsFromInventory(snapshot.Canonical),
			AfterCounts = getAvailableCountsFromInventory(canonicalInventory),
			Writes = writes,
			MirrorMatch = status.MirrorMatch,
			BlockingCount = status.BlockingCount,
			UnclassifiedCount = status.UnclassifiedCount,
			ReconciliationUsed = options.ReconciliationUsed == true,
		},
		LastFailClosedReason = nil,
	})

	return true, nil, status
end

local function saveBrainrotInventory(player, brainrotInventory, _options)
	local canonicalInventory = normalizeInventoryData(cloneValue(brainrotInventory), {
		Canonical = true,
	})
	local ok, reason = writeProfileRoot(player, CANONICAL_INVENTORY_PATH, canonicalInventory)
	if ok ~= true then
		return false, "inventory_write_failed:CrewMemberInventory:" .. tostring(reason or "")
	end
	notifyInventorySaved(player, canonicalInventory)
	return true, nil
end

local function getBrainrotInventory(player)
	local rawInventory = getDataManager():GetValue(player, CANONICAL_INVENTORY_PATH)
	local missingCanonical = typeof(rawInventory) ~= "table"
	local inventory, changed = normalizeInventoryData(rawInventory, {
		Canonical = true,
	})

	if changed and not missingCanonical then
		saveBrainrotInventory(player, inventory, {
			SourcePath = "inventory_normalize",
		})
	elseif missingCanonical then
		updateInventoryAuthorityAudit(player, {
			LastFailClosedReason = "canonical_inventory_missing",
			LastFailClosedSourcePath = "getCrewInventory",
		})
	end

	return inventory
end

local function setInstanceData(player, brainrotInventory, instanceId, instanceData)
	brainrotInventory.ById[tostring(instanceId)] = normalizeInstanceData(instanceId, instanceData)
	return saveBrainrotInventory(player, brainrotInventory, {
		SourcePath = "inventory_set_instance_data",
	})
end

syncAvailableCounts = function(player, brainrotInventory, options)
	local _ = player
	_ = brainrotInventory
	_ = options
	return true
end

local function moveInstanceToFront(brainrotInventory, instanceId)
	instanceId = tostring(instanceId)
	for index = #brainrotInventory.Order, 1, -1 do
		if tostring(brainrotInventory.Order[index]) == instanceId then
			table.remove(brainrotInventory.Order, index)
			break
		end
	end
	table.insert(brainrotInventory.Order, 1, instanceId)
end

local function clearShipSlotAssignment(player, standName)
	standName = tostring(standName or "")
	if standName == "" then
		return
	end

	local shipSlots = getDataManager():GetValue(player, "Ship.Slots")
	if typeof(shipSlots) ~= "table" then
		return
	end

	shipSlots[standName] = nil
	getDataManager():SetValue(player, "Ship.Slots", shipSlots)
end

local function getStandData(player, standName)
	local standData, standMeta = CrewStandIncomeAuthority.GetStandData(player, standName)
	return standData, standMeta
end

local function setStandData(player, standName, standData, sourcePath)
	return CrewStandIncomeAuthority.SetStandData(player, standName, standData, sourcePath)
end

local function updateStandData(player, standName, updates, sourcePath)
	return CrewStandIncomeAuthority.UpdateStandData(player, standName, updates, sourcePath)
end

local function clearStandData(player, standName, sourcePath)
	return CrewStandIncomeAuthority.ClearStandData(player, standName, sourcePath)
end

local function ensureInventoryMetadata(player, storageName, metadata)
	local _ = player
	return metadata or buildMetadata(storageName)
end

local function createInstanceInternal(player, brainrotInventory, storageName, overrides)
	local metadata = buildMetadata(storageName, overrides)

	local instanceId = tostring(brainrotInventory.NextInstanceId)
	brainrotInventory.NextInstanceId += 1
	brainrotInventory.ById[instanceId] = normalizeInstanceData(instanceId, {
		StorageName = storageName,
		BaseName = overrides and overrides.BaseName or metadata.BaseName,
		Variant = overrides and overrides.Variant or metadata.Variant,
		Rarity = overrides and overrides.Rarity or metadata.Rarity,
		Income = overrides and overrides.Income or metadata.Income,
		Render = overrides and overrides.Render or metadata.Render,
		GoldenRender = overrides and overrides.GoldenRender or metadata.GoldenRender,
		DiamondRender = overrides and overrides.DiamondRender or metadata.DiamondRender,
		Level = overrides and overrides.Level or 1,
		CurrentXP = overrides and overrides.CurrentXP or 0,
		TotalXP = overrides and overrides.TotalXP or 0,
		AssignedStand = overrides and overrides.AssignedStand or "",
		AcquiredAt = overrides and overrides.AcquiredAt or os.time(),
		LastReleasedAt = overrides and overrides.LastReleasedAt or 0,
		Source = overrides and overrides.Source or "",
		DepthBand = overrides and overrides.DepthBand or "",
		TutorialReward = overrides and overrides.TutorialReward == true,
		TutorialToken = overrides and overrides.TutorialToken or "",
		GrandLineRushStarter = overrides and overrides.GrandLineRushStarter == true,
	})
	if overrides and overrides.TutorialReward == true then
		table.insert(brainrotInventory.Order, 1, instanceId)
	else
		table.insert(brainrotInventory.Order, instanceId)
	end
	IndexCollectionService.MarkCrewMemberDiscovered(
		player,
		storageName,
		overrides and overrides.BaseName or metadata.BaseName,
		overrides and overrides.Variant or metadata.Variant,
		{
			DeferShadowRefresh = overrides and overrides.DeferIndexShadowRefresh == true,
		}
	)

	return instanceId, brainrotInventory.ById[instanceId]
end

local function getStoredLegacyProgress(player, storageName)
	local brainrotInventory = getBrainrotInventory(player)
	for _, instanceId in ipairs(brainrotInventory.Order) do
		local instanceData = brainrotInventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" and tostring(instanceData.StorageName or "") == tostring(storageName or "") then
			return math.max(1, math.floor(coerceNumber(instanceData.Level, 1))),
				math.max(0, math.floor(coerceNumber(instanceData.CurrentXP, 0)))
		end
	end
	return 1, 0
end

function Module.IsBrainrotInventoryEntry(key, entry)
	return isBrainrotInventoryEntry(key, entry)
end

function Module.EnsureInventory(player)
	return getBrainrotInventory(player)
end

function Module.IsInventoryWriteAuthorityEnabled()
	local enabled = isInventoryWriteAuthorityEnabled()
	return enabled == true
end

function Module.ValidateInventoryMirrors(player)
	return validateInventoryMirrors(player)
end

function Module.BuildInventoryAuthorityStatus(player)
	local flags = getCrewStorage().GetShadowFlags()
	local status = validateInventoryMirrors(player)
	local audit = getDataManager():GetValue(player, INVENTORY_AUTHORITY_AUDIT_PATH)
	status.Flags = {
		InventoryWriteAuthority = flags.CrewMemberInventoryWriteAuthorityEnabled == true,
		WriteAuthority = flags.CrewMemberCanaryWriteAuthorityEnabled == true,
		QuickSlotsWriteAuthority = flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true,
		ProductQuickSlotWriteAuthority = flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true,
		ProgressionWriteAuthority = flags.CrewMemberProgressionWriteAuthorityEnabled == true,
		CanonicalRead = flags.CrewMemberCanonicalReadEnabled == true,
		GameplayReads = flags.CrewMemberCanaryGameplayReadsEnabled == true,
		ProfileMigrationWrite = flags.CrewMemberCanaryProfileMigrationWriteEnabled == true,
		DryRun = flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true,
		MigrationKillSwitch = flags.CrewMemberMigrationKillSwitchEnabled == true,
	}
	status.Audit = if typeof(audit) == "table" then cloneValue(audit) else {}
	return status
end

function Module.PrintInventoryAuthorityStatus(status)
	status = if typeof(status) == "table" then status else {}
	local canonical = status.Canonical or {}
	local legacy = status.BrainrotInventory or {}
	local flags = status.Flags or {}
	print(string.format(
		"[CrewInventoryAuthority] status rootsMatch=%s mirrorMatch=%s canonicalInstances=%s legacyInstances=%s canonicalNext=%s legacyNext=%s blocking=%d unclassified=%d inventoryAuthority=%s writeAuthority=%s quickSlotsWriteAuthority=%s productQuickSlotWriteAuthority=%s canonicalRead=%s gameplayReads=%s profileMigrationWrite=%s dryRun=%s migrationKillSwitch=%s issues=%s",
		tostring(status.RootsMatch == true),
		tostring(status.MirrorMatch == true),
		tostring(canonical.InstanceCount or 0),
		tostring(legacy.InstanceCount or 0),
		tostring(canonical.NextInstanceId),
		tostring(legacy.NextInstanceId),
		tonumber(status.BlockingCount) or 0,
		tonumber(status.UnclassifiedCount) or 0,
		tostring(flags.InventoryWriteAuthority == true),
		tostring(flags.WriteAuthority == true),
		tostring(flags.QuickSlotsWriteAuthority == true),
		tostring(flags.ProductQuickSlotWriteAuthority == true),
		tostring(flags.CanonicalRead == true),
		tostring(flags.GameplayReads == true),
		tostring(flags.ProfileMigrationWrite == true),
		tostring(flags.DryRun == true),
		tostring(flags.MigrationKillSwitch == true),
		if typeof(status.Issues) == "table" and #status.Issues > 0 then table.concat(status.Issues, ",") else "none"
	))
end

function Module.ReconcileLegacyInventoryMirrorFromCrew(player, options)
	options = if typeof(options) == "table" then options else {}
	local enabled = isInventoryWriteAuthorityEnabled()
	if enabled ~= true and options.AllowWhenDisabled ~= true then
		return false, "inventory_write_authority_disabled"
	end

	local ready, readyReason = ensureInventoryAuthorityReady(player, "inventory_reconcile_legacy_mirror")
	if ready ~= true and options.AllowDirtyReconcile ~= true then
		return false, tostring(readyReason or "inventory_authority_not_ready")
	end

	local crewInventory = normalizeInventoryData(getDataManager():GetValue(player, CANONICAL_INVENTORY_PATH), {
		Canonical = true,
	})
	local saved, saveReason, status = saveCrewInventoryAndMirrors(player, crewInventory, {
		SourcePath = "inventory_reconcile_legacy_mirror",
		ReconciliationUsed = true,
	})
	if saved ~= true then
		return false, saveReason
	end
	return true, nil, status
end

function Module.RegisterInventorySavedCallback(callback)
	if typeof(callback) ~= "function" then
		error("[CrewInstanceService] RegisterInventorySavedCallback expects a function")
	end

	inventorySavedCallbacks[callback] = true

	return function()
		inventorySavedCallbacks[callback] = nil
	end
end

function Module.SyncAvailableCounts(player, options)
	return syncAvailableCounts(player, nil, options)
end

function Module.SaveCrewInventory(player, crewInventory, options)
	return saveBrainrotInventory(player, crewInventory, options)
end

function Module.IsTutorialRewardProtected(player, instanceData)
	return isProtectedTutorialReward(player, instanceData)
end

local function getTutorialRewardFilters(filters)
	if typeof(filters) == "string" then
		return {
			StorageName = filters,
		}
	end

	return if typeof(filters) == "table" then filters else {}
end

local function tutorialRewardMatchesFilters(instanceData, filters)
	if typeof(instanceData) ~= "table" or instanceData.TutorialReward ~= true then
		return false
	end

	local storageName = tostring(filters.StorageName or "")
	if storageName ~= "" and tostring(instanceData.StorageName or "") ~= storageName then
		return false
	end

	local tutorialToken = tostring(filters.TutorialToken or "")
	if tutorialToken ~= "" and tostring(instanceData.TutorialToken or "") ~= tutorialToken then
		return false
	end

	local assignedStand = tostring(instanceData.AssignedStand or "")
	if filters.RequireAvailable == true and assignedStand ~= "" then
		return false
	end
	if filters.RequireAssigned == true and assignedStand == "" then
		return false
	end

	return true
end

function Module.FindTutorialRewardInstance(player, filters)
	filters = getTutorialRewardFilters(filters)
	local brainrotInventory = getBrainrotInventory(player)
	local requestedInstanceId = tostring(filters.InstanceId or "")

	if requestedInstanceId ~= "" then
		local instanceData = brainrotInventory.ById[requestedInstanceId]
		if tutorialRewardMatchesFilters(instanceData, filters) then
			return requestedInstanceId, instanceData, brainrotInventory
		end
	end

	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local instanceId = tostring(orderedInstanceId)
		local instanceData = brainrotInventory.ById[instanceId]
		if tutorialRewardMatchesFilters(instanceData, filters) then
			return instanceId, instanceData, brainrotInventory
		end
	end

	return nil, nil, brainrotInventory
end

function Module.HasUsableTutorialReward(player, storageName, tutorialToken)
	local instanceId, instanceData = Module.FindTutorialRewardInstance(player, {
		StorageName = tostring(storageName or ""),
		TutorialToken = tostring(tutorialToken or ""),
		RequireAvailable = true,
	})
	return instanceData ~= nil, instanceId, instanceData
end

local function getStandOccupancy(player, standName, brainrotInventory)
	standName = tostring(standName or "")
	if standName == "" then
		return true, "invalid_stand"
	end

	local standData = getStandData(player, standName)
	if tostring(standData.BrainrotName or "") ~= "" or tostring(standData.BrainrotInstanceId or "") ~= "" then
		return true, "stand_occupied", tostring(standData.BrainrotInstanceId or ""), tostring(standData.BrainrotName or "")
	end

	brainrotInventory = brainrotInventory or getBrainrotInventory(player)
	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local instanceId = tostring(orderedInstanceId)
		local instanceData = brainrotInventory.ById[instanceId]
		if instanceData and tostring(instanceData.AssignedStand or "") == standName then
			return true, "stand_assigned_elsewhere", instanceId, tostring(instanceData.StorageName or "")
		end
	end

	return false, nil
end

function Module.AssignTutorialRewardInstanceToStand(player, standName, filters)
	filters = getTutorialRewardFilters(filters)
	filters.RequireAvailable = true
	local clearTutorialMetadataAfterAssign = filters.ClearTutorialMetadataAfterAssign == true

	local instanceId, instanceData, brainrotInventory = Module.FindTutorialRewardInstance(player, filters)
	if not instanceData then
		return nil, nil, "instance_unavailable"
	end

	local occupied, occupancyReason = getStandOccupancy(player, standName, brainrotInventory)
	if occupied then
		return nil, nil, occupancyReason
	end

	instanceData.AssignedStand = tostring(standName)
	setInstanceData(player, brainrotInventory, instanceId, instanceData)
	updateStandData(player, standName, {
		BrainrotName = instanceData.StorageName,
		BrainrotInstanceId = tostring(instanceId),
	}, "stand_place_tutorial_reward")

	if clearTutorialMetadataAfterAssign then
		local assignedInstanceData = brainrotInventory.ById[tostring(instanceId)]
		if assignedInstanceData then
			assignedInstanceData.TutorialReward = false
			assignedInstanceData.TutorialToken = ""
			assignedInstanceData.TutorialOwnerUserId = nil
			assignedInstanceData.TutorialBrainrot = nil
			assignedInstanceData.TutorialRewardName = nil
			setInstanceData(player, brainrotInventory, instanceId, assignedInstanceData)
		end
	end

	syncAvailableCounts(player, brainrotInventory)
	refreshCrewMemberShadow(player, "stand_place")

	return tostring(instanceId), brainrotInventory.ById[tostring(instanceId)]
end

function Module.EnsureInventoryMetadata(player, storageName, metadata)
	return ensureInventoryMetadata(player, storageName, metadata)
end

function Module.CreateInstances(player, storageName, count, overrides)
	local safeCount = math.max(0, math.floor(coerceNumber(count, 0)))
	if safeCount <= 0 then
		return {}
	end

	local assignedStand = tostring(overrides and overrides.AssignedStand or "")
	local capacityReserved = overrides and overrides._QuickSlotCapacityReserved == true
	if assignedStand == "" and not capacityReserved then
		if not CrewQuickSlotService.CanGainOrNotify(player, safeCount, "CreateInstances:" .. tostring(storageName)) then
			return {}
		end
	end

	local ready, readyReason = ensureInventoryAuthorityReady(player, "inventory_grant")
	if ready ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority grant failed closed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(storageName),
			tostring(readyReason or "unknown")
		))
		return {}
	end

	local brainrotInventory = getBrainrotInventory(player)

	local createdIds = {}
	for _ = 1, safeCount do
		local instanceOverrides = if typeof(overrides) == "table" then table.clone(overrides) else {}
		instanceOverrides.DeferIndexShadowRefresh = true
		local instanceId = createInstanceInternal(player, brainrotInventory, storageName, instanceOverrides)
		table.insert(createdIds, instanceId)
	end

	local saved, saveReason = saveBrainrotInventory(player, brainrotInventory, {
		SourcePath = "inventory_grant",
	})
	if saved ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority grant save failed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(storageName),
			tostring(saveReason or "unknown")
		))
		return {}
	end
	syncAvailableCounts(player, brainrotInventory)
	refreshCrewMemberShadow(player, "inventory_grant")
	return createdIds
end

function Module.EnsureAvailableInstancesForStorage(player, storageName, minimumAvailable, options)
	local ready, readyReason = ensureInventoryAuthorityReady(player, "inventory_ensure_available")
	if ready ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority ensure available failed closed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(storageName),
			tostring(readyReason or "unknown")
		))
		return 0
	end

	local brainrotInventory = getBrainrotInventory(player)
	local availableCount = 0
	for _, instanceId in ipairs(brainrotInventory.Order) do
		local instanceData = brainrotInventory.ById[tostring(instanceId)]
		if instanceData and instanceData.StorageName == storageName and instanceData.AssignedStand == "" then
			availableCount += 1
		end
	end

	local requestedMinimum = math.max(0, math.floor(coerceNumber(minimumAvailable, 0)))
	local targetCount = requestedMinimum
	if availableCount >= targetCount then
		return availableCount
	end

	local level, currentXP = getStoredLegacyProgress(player, storageName)
	for _ = 1, (targetCount - availableCount) do
		createInstanceInternal(player, brainrotInventory, storageName, {
			Level = level,
			CurrentXP = currentXP,
		})
	end

	local saved, saveReason = saveBrainrotInventory(player, brainrotInventory, {
		SourcePath = "inventory_ensure_available",
	})
	if saved ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority ensure available save failed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(storageName),
			tostring(saveReason or "unknown")
		))
		return availableCount
	end
	syncAvailableCounts(player, brainrotInventory)
	if not (typeof(options) == "table" and options.DeferShadowRefresh == true) then
		refreshCrewMemberShadow(player, "data_repair_available_instances")
	end
	return targetCount
end

function Module.GetInstance(player, instanceRef)
	local brainrotInventory = getBrainrotInventory(player)
	local instanceId = nil

	if typeof(instanceRef) == "table" then
		instanceId = tostring(instanceRef.InstanceId or "")
	else
		instanceId = tostring(instanceRef or "")
	end

	local instanceData = brainrotInventory.ById[instanceId]
	if instanceData then
		return instanceId, instanceData, brainrotInventory
	end

	return nil, nil, brainrotInventory
end

function Module.ResolveProgressTarget(player, reference)
	local instanceId, instanceData, brainrotInventory = Module.GetInstance(player, reference)
	if instanceData then
		return instanceId, instanceData, brainrotInventory
	end

	local storageName = tostring(reference or "")
	if storageName == "" then
		return nil, nil, brainrotInventory
	end

	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local candidate = brainrotInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.StorageName == storageName then
			return tostring(orderedInstanceId), candidate, brainrotInventory
		end
	end

	Module.EnsureAvailableInstancesForStorage(player, storageName, 1)
	brainrotInventory = getBrainrotInventory(player)

	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local candidate = brainrotInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.StorageName == storageName then
			return tostring(orderedInstanceId), candidate, brainrotInventory
		end
	end

	return nil, nil, brainrotInventory
end

function Module.UpdateProgress(player, instanceId, level, currentXP, options)
	options = if typeof(options) == "table" then options else {}
	local progressionAuthorityEnabled = isProgressionWriteAuthorityEnabled()
	if progressionAuthorityEnabled == true then
		local ready, readyReason = ensureProgressionAuthorityReady(player, "progression_update")
		if ready ~= true then
			warn(string.format(
				"[CrewInstanceService] CrewMember progression authority update failed closed player=%s instance=%s reason=%s",
				player and player.Name or "unknown",
				tostring(instanceId),
				tostring(readyReason or "unknown")
			))
			return nil
		end
	end

	local resolvedInstanceId, instanceData, brainrotInventory = Module.GetInstance(player, instanceId)
	if not instanceData then
		return nil
	end

	local snapshot = nil
	if progressionAuthorityEnabled == true then
		snapshot = buildInventoryAuthoritySnapshot(player, "progression_update")
		updateProgressionAuthorityAudit(player, {
			LastRollbackSnapshot = snapshot,
			LastMutation = {
				SourcePath = "progression_update",
				InstanceId = tostring(resolvedInstanceId),
				LevelBefore = tonumber(instanceData.Level) or 1,
				CurrentXPBefore = tonumber(instanceData.CurrentXP) or 0,
				StartedAt = os.time(),
			},
		})
	end

	instanceData.Level = math.max(1, math.floor(coerceNumber(level, instanceData.Level or 1)))
	instanceData.CurrentXP = math.max(0, math.floor(coerceNumber(currentXP, instanceData.CurrentXP or 0)))
	if options.TotalXP ~= nil then
		instanceData.TotalXP = math.max(0, math.floor(coerceNumber(options.TotalXP, instanceData.TotalXP or 0)))
	end
	if options.Source ~= nil then
		instanceData.Source = tostring(options.Source or "")
	end
	if options.DepthBand ~= nil then
		instanceData.DepthBand = tostring(options.DepthBand or "")
	end
	if options.GrandLineRushStarter ~= nil then
		instanceData.GrandLineRushStarter = options.GrandLineRushStarter == true
	end
	local saveOk, saveReason = setInstanceData(player, brainrotInventory, resolvedInstanceId, instanceData)
	if saveOk ~= true then
		if progressionAuthorityEnabled == true then
			local restoreOk, restoreReason = restoreInventoryAuthoritySnapshot(player, snapshot, "progression_save_failed")
			updateProgressionAuthorityAudit(player, {
				LastFailClosedReason = "progression_save_failed:" .. tostring(saveReason or "unknown"),
				LastRollbackRestoreOk = restoreOk,
				LastRollbackRestoreReason = restoreReason,
			})
		end
		return nil
	end

	local updated = brainrotInventory.ById[resolvedInstanceId]

	if progressionAuthorityEnabled == true then
		local shadowResult = refreshCrewMemberShadow(player, "progression_update")
		local shadowValidation = shadowResult and shadowResult.Validation
		if shadowValidation == nil or shadowValidation.BlockingIssueCount ~= 0 then
			local restoreOk, restoreReason = restoreInventoryAuthoritySnapshot(
				player,
				snapshot,
				"progression_shadow_projection_failed"
			)
			updateProgressionAuthorityAudit(player, {
				LastFailClosedReason = "progression_shadow_projection_failed",
				LastFailClosedIssues = cloneValue(shadowValidation),
				LastRollbackRestoreOk = restoreOk,
				LastRollbackRestoreReason = restoreReason,
			})
			return nil
		end

		local savedCanonical = getDataManager():GetValue(
			player,
			CANONICAL_INVENTORY_PATH .. ".ById." .. tostring(resolvedInstanceId)
		)
		local progressionWriteOk = typeof(savedCanonical) == "table"
			and updated ~= nil
			and tonumber(savedCanonical.Level) == tonumber(updated.Level)
			and tonumber(savedCanonical.CurrentXP) == tonumber(updated.CurrentXP)
		if progressionWriteOk ~= true then
			local restoreOk, restoreReason = restoreInventoryAuthoritySnapshot(player, snapshot, "progression_post_validation_failed")
			updateProgressionAuthorityAudit(player, {
				LastFailClosedReason = "progression_post_validation_failed",
				LastFailClosedIssues = {
					"progression_canonical_mismatch:" .. tostring(resolvedInstanceId),
				},
				LastRollbackRestoreOk = restoreOk,
				LastRollbackRestoreReason = restoreReason,
			})
			return nil
		end

		updateProgressionAuthorityAudit(player, {
			LastMutation = {
				SourcePath = "progression_update",
				InstanceId = tostring(resolvedInstanceId),
				LevelAfter = updated and updated.Level or nil,
				CurrentXPAfter = updated and updated.CurrentXP or nil,
				CompletedAt = os.time(),
				MirrorMatch = true,
				BlockingCount = shadowValidation.BlockingIssueCount,
				UnclassifiedCount = 0,
			},
			ClearKeys = {
				"LastFailClosedReason",
				"LastFailClosedIssues",
				"LastRollbackRestoreOk",
				"LastRollbackRestoreReason",
			},
		})
	end

	return updated
end

function Module.GetStandInstanceId(player, standName)
	local standData = getStandData(player, standName)
	local rawInstanceId = tostring(standData.BrainrotInstanceId or "")
	if rawInstanceId == "" then
		return ""
	end

	local instanceId, instanceData = Module.GetInstance(player, rawInstanceId)
	if not instanceData then
		return ""
	end

	if instanceData.AssignedStand ~= tostring(standName) then
		instanceData.AssignedStand = tostring(standName)
		local _, _, brainrotInventory = Module.GetInstance(player, instanceId)
		setInstanceData(player, brainrotInventory, instanceId, instanceData)
		refreshCrewMemberShadow(player, "data_repair_stand_assignment")
	end

	return instanceId
end

function Module.EnsureStandInstance(player, standName, fallbackStorageName)
	local standData = getStandData(player, standName)
	local standStorageName = tostring(standData.BrainrotName or fallbackStorageName or "")
	if standStorageName == "" then
		if standData.BrainrotInstanceId ~= "" then
			updateStandData(player, standName, {
				BrainrotInstanceId = "",
			}, "data_repair_stand_instance")
			refreshCrewMemberShadow(player, "data_repair_stand_instance")
		end
		return nil, nil
	end

	local instanceId = tostring(standData.BrainrotInstanceId or "")
	local brainrotInventory = getBrainrotInventory(player)
	local instanceData = brainrotInventory.ById[instanceId]
	if instanceData then
		local repaired = false
		if instanceData.AssignedStand ~= tostring(standName) then
			instanceData.AssignedStand = tostring(standName)
			setInstanceData(player, brainrotInventory, instanceId, instanceData)
			repaired = true
		end
		if standData.BrainrotName ~= instanceData.StorageName then
			updateStandData(player, standName, {
				BrainrotName = instanceData.StorageName,
			}, "data_repair_stand_instance")
			repaired = true
		end
		if repaired then
			refreshCrewMemberShadow(player, "data_repair_stand_instance")
		end
		return instanceId, instanceData
	end

	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local candidate = brainrotInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.AssignedStand == tostring(standName) then
			local repaired = false
			updateStandData(player, standName, {
				BrainrotInstanceId = tostring(orderedInstanceId),
			}, "data_repair_stand_instance")
			repaired = true
			if standData.BrainrotName ~= candidate.StorageName then
				updateStandData(player, standName, {
					BrainrotName = candidate.StorageName,
				}, "data_repair_stand_instance")
				repaired = true
			end
			if repaired then
				refreshCrewMemberShadow(player, "data_repair_stand_instance")
			end
			return tostring(orderedInstanceId), candidate
		end
	end

	Module.EnsureAvailableInstancesForStorage(player, standStorageName, 1, {
		DeferShadowRefresh = true,
	})
	brainrotInventory = getBrainrotInventory(player)
	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local candidate = brainrotInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.StorageName == standStorageName and candidate.AssignedStand == "" then
			candidate.AssignedStand = tostring(standName)
			setInstanceData(player, brainrotInventory, orderedInstanceId, candidate)
			updateStandData(player, standName, {
				BrainrotInstanceId = tostring(orderedInstanceId),
			}, "data_repair_stand_instance")
			if standData.BrainrotName ~= candidate.StorageName then
				updateStandData(player, standName, {
					BrainrotName = candidate.StorageName,
				}, "data_repair_stand_instance")
			end
			syncAvailableCounts(player)
			refreshCrewMemberShadow(player, "data_repair_stand_instance")
			return tostring(orderedInstanceId), candidate
		end
	end

	local level, currentXP = getStoredLegacyProgress(player, standStorageName)
	local createdId = createInstanceInternal(player, brainrotInventory, standStorageName, {
		AssignedStand = tostring(standName),
		Level = level,
		CurrentXP = currentXP,
	})
	saveBrainrotInventory(player, brainrotInventory)
	updateStandData(player, standName, {
		BrainrotName = standStorageName,
		BrainrotInstanceId = tostring(createdId),
	}, "data_repair_stand_instance")
	syncAvailableCounts(player, brainrotInventory)
	refreshCrewMemberShadow(player, "data_repair_stand_instance")
	return tostring(createdId), brainrotInventory.ById[tostring(createdId)]
end

function Module.FindAvailableInstance(player, storageName)
	Module.EnsureAvailableInstancesForStorage(player, storageName, 1)
	local brainrotInventory = getBrainrotInventory(player)
	for _, instanceId in ipairs(brainrotInventory.Order) do
		local instanceData = brainrotInventory.ById[tostring(instanceId)]
		if instanceData and instanceData.StorageName == tostring(storageName) and instanceData.AssignedStand == "" then
			return tostring(instanceId), instanceData, brainrotInventory
		end
	end
	return nil, nil, brainrotInventory
end

function Module.AssignAvailableInstanceToStand(player, storageName, standName)
	local instanceId, instanceData, brainrotInventory = Module.FindAvailableInstance(player, storageName)
	if not instanceData then
		return nil, nil, "instance_unavailable"
	end

	local occupied, occupancyReason = getStandOccupancy(player, standName, brainrotInventory)
	if occupied then
		return nil, nil, occupancyReason
	end

	instanceData.AssignedStand = tostring(standName)
	setInstanceData(player, brainrotInventory, instanceId, instanceData)
	updateStandData(player, standName, {
		BrainrotName = instanceData.StorageName,
		BrainrotInstanceId = tostring(instanceId),
	}, "stand_place")
	syncAvailableCounts(player, brainrotInventory)
	refreshCrewMemberShadow(player, "stand_place")

	return tostring(instanceId), brainrotInventory.ById[tostring(instanceId)]
end

function Module.ReleaseStandInstance(player, standName, options)
	options = if typeof(options) == "table" then options else {}
	standName = tostring(standName or "")

	local standDataBefore, standMetaBefore = getStandData(player, standName)
	local canonicalBefore = if typeof(standMetaBefore) == "table" then standMetaBefore.CanonicalRow else nil
	local debugInfo = {
		PlayerName = player and player.Name or "unknown",
		UserId = player and player.UserId or 0,
		StandName = standName,
		AssignedBrainrotName = tostring(standDataBefore and standDataBefore.BrainrotName or ""),
		BrainrotInstanceId = tostring(standDataBefore and standDataBefore.BrainrotInstanceId or ""),
		CrewMemberInstanceId = tostring((canonicalBefore and canonicalBefore.CrewMemberInstanceId) or (standDataBefore and standDataBefore.BrainrotInstanceId) or ""),
		LegacyStorageName = tostring((canonicalBefore and canonicalBefore.LegacyStorageName) or (standDataBefore and standDataBefore.BrainrotName) or ""),
		IncomeBefore = tonumber(standDataBefore and standDataBefore.IncomeToCollect) or 0,
	}

	local instanceId, instanceData = Module.EnsureStandInstance(player, standName)
	debugInfo.EnsureInstanceId = tostring(instanceId or "")
	debugInfo.InstanceExistsInCrewInventory = instanceData ~= nil
	debugInfo.PlayerOwnsInstance = instanceData ~= nil
	debugInfo.InstanceStorageName = instanceData and tostring(instanceData.StorageName or "") or ""
	debugInfo.InstanceAssignedStand = instanceData and tostring(instanceData.AssignedStand or "") or ""

	local brainrotInventory = getBrainrotInventory(player)
	local assignedStandRefs = {}
	if typeof(brainrotInventory) == "table" and typeof(brainrotInventory.ById) == "table" then
		for ownedInstanceId, ownedInstanceData in pairs(brainrotInventory.ById) do
			if typeof(ownedInstanceData) == "table" and tostring(ownedInstanceData.AssignedStand or "") == standName then
				assignedStandRefs[#assignedStandRefs + 1] = string.format(
					"%s:%s",
					tostring(ownedInstanceId),
					tostring(ownedInstanceData.StorageName or "")
				)
			end
		end
	end
	table.sort(assignedStandRefs)
	debugInfo.AssignedStandRefs = table.concat(assignedStandRefs, ",")
	debugInfo.InstanceExistsInPlacedTracking = #assignedStandRefs > 0

	if not instanceData then
		crewPickupDebug(formatCrewPickupDebugFields({
			{ "event", "release_failed" },
			{ "reason", "no_instance_available" },
			{ "player", debugInfo.PlayerName },
			{ "userId", debugInfo.UserId },
			{ "stand", standName },
			{ "assignedName", debugInfo.AssignedBrainrotName },
			{ "brainrotInstanceId", debugInfo.BrainrotInstanceId },
			{ "crewMemberInstanceId", debugInfo.CrewMemberInstanceId },
			{ "legacyStorageName", debugInfo.LegacyStorageName },
			{ "incomeBefore", debugInfo.IncomeBefore },
			{ "instanceExists", debugInfo.InstanceExistsInCrewInventory },
			{ "placedTrackingRefs", debugInfo.AssignedStandRefs },
		}))
		return nil, nil, "no_instance_available", debugInfo
	end

	local canGain, occupiedSlots, unlockedSlots, maxSlots = CrewQuickSlotService.CanGainOrNotify(
		player,
		1,
		"ReleaseStandInstance:" .. standName
	)
	debugInfo.QuickSlotCanGain = canGain == true
	debugInfo.QuickSlotOccupied = tonumber(occupiedSlots) or 0
	debugInfo.QuickSlotUnlocked = tonumber(unlockedSlots) or 0
	debugInfo.QuickSlotMax = tonumber(maxSlots) or 0
	if not canGain then
		local source = tostring(options.Source or "")
		local expectedInstanceId = tostring(options.ExpectedInstanceId or "")
		local allowCapacityBypass = options.AllowCapacityBypass == true
			and source ~= ""
			and expectedInstanceId ~= ""
			and expectedInstanceId == tostring(instanceId)
		debugInfo.AllowCapacityBypass = allowCapacityBypass == true
		debugInfo.ExpectedInstanceId = expectedInstanceId
		debugInfo.Source = source
		if not allowCapacityBypass then
			crewPickupDebug(formatCrewPickupDebugFields({
				{ "event", "release_failed" },
				{ "reason", "quick_slot_capacity" },
				{ "player", debugInfo.PlayerName },
				{ "userId", debugInfo.UserId },
				{ "stand", standName },
				{ "assignedName", debugInfo.AssignedBrainrotName },
				{ "instanceId", tostring(instanceId) },
				{ "brainrotInstanceId", debugInfo.BrainrotInstanceId },
				{ "crewMemberInstanceId", debugInfo.CrewMemberInstanceId },
				{ "legacyStorageName", debugInfo.LegacyStorageName },
				{ "incomeBefore", debugInfo.IncomeBefore },
				{ "quickOccupied", debugInfo.QuickSlotOccupied },
				{ "quickUnlocked", debugInfo.QuickSlotUnlocked },
				{ "quickMax", debugInfo.QuickSlotMax },
				{ "instanceExists", debugInfo.InstanceExistsInCrewInventory },
				{ "playerOwnsInstance", debugInfo.PlayerOwnsInstance },
				{ "placedTrackingRefs", debugInfo.AssignedStandRefs },
			}))
			return nil, nil, "quick_slot_capacity", debugInfo
		end
	end

	local _, _, releaseInventory = Module.GetInstance(player, instanceId)
	if releaseInventory ~= nil then
		brainrotInventory = releaseInventory
	end

	instanceData.AssignedStand = ""
	instanceData.LastReleasedAt = os.time()
	brainrotInventory.ById[tostring(instanceId)] = instanceData
	moveInstanceToFront(brainrotInventory, instanceId)
	local saveOk, saveReason = saveBrainrotInventory(player, brainrotInventory)
	debugInfo.InventorySaveOk = saveOk == true
	debugInfo.InventorySaveReason = tostring(saveReason or "")
	if saveOk ~= true then
		crewPickupDebug(formatCrewPickupDebugFields({
			{ "event", "release_failed" },
			{ "reason", "inventory_write_failed" },
			{ "player", debugInfo.PlayerName },
			{ "userId", debugInfo.UserId },
			{ "stand", standName },
			{ "assignedName", debugInfo.AssignedBrainrotName },
			{ "releasedInstanceId", tostring(instanceId) },
			{ "releasedStorage", tostring(instanceData.StorageName or "") },
			{ "inventorySaveOk", debugInfo.InventorySaveOk },
			{ "inventorySaveReason", debugInfo.InventorySaveReason },
			{ "standClearOk", "" },
			{ "standClearReason", "" },
		}))
		return nil, nil, "inventory_write_failed", debugInfo
	end

	local clearOk, clearReason = clearStandData(player, standName, "stand_release")
	debugInfo.StandClearOk = clearOk == true
	debugInfo.StandClearReason = tostring(clearReason or "")
	if clearOk ~= true then
		instanceData.AssignedStand = standName
		brainrotInventory.ById[tostring(instanceId)] = instanceData
		local rollbackOk, rollbackReason = saveBrainrotInventory(player, brainrotInventory)
		debugInfo.InventoryRollbackOk = rollbackOk == true
		debugInfo.InventoryRollbackReason = tostring(rollbackReason or "")
		crewPickupDebug(formatCrewPickupDebugFields({
			{ "event", "release_failed" },
			{ "reason", "stand_clear_failed" },
			{ "player", debugInfo.PlayerName },
			{ "userId", debugInfo.UserId },
			{ "stand", standName },
			{ "assignedName", debugInfo.AssignedBrainrotName },
			{ "releasedInstanceId", tostring(instanceId) },
			{ "releasedStorage", tostring(instanceData.StorageName or "") },
			{ "brainrotInstanceId", debugInfo.BrainrotInstanceId },
			{ "crewMemberInstanceId", debugInfo.CrewMemberInstanceId },
			{ "legacyStorageName", debugInfo.LegacyStorageName },
			{ "incomeBefore", debugInfo.IncomeBefore },
			{ "quickOccupied", debugInfo.QuickSlotOccupied },
			{ "quickUnlocked", debugInfo.QuickSlotUnlocked },
			{ "quickMax", debugInfo.QuickSlotMax },
			{ "inventorySaveOk", debugInfo.InventorySaveOk },
			{ "inventorySaveReason", debugInfo.InventorySaveReason },
			{ "standClearOk", debugInfo.StandClearOk },
			{ "standClearReason", debugInfo.StandClearReason },
			{ "inventoryRollbackOk", debugInfo.InventoryRollbackOk },
			{ "inventoryRollbackReason", debugInfo.InventoryRollbackReason },
			{ "placedTrackingRefs", debugInfo.AssignedStandRefs },
		}))
		syncAvailableCounts(player, brainrotInventory)
		refreshCrewMemberShadow(player, "stand_release_failed")
		return nil, nil, "stand_clear_failed", debugInfo
	end

	syncAvailableCounts(player, brainrotInventory)
	refreshCrewMemberShadow(player, "stand_release")

	crewPickupDebug(formatCrewPickupDebugFields({
		{ "event", "release_success" },
		{ "reason", "none" },
		{ "player", debugInfo.PlayerName },
		{ "userId", debugInfo.UserId },
		{ "stand", standName },
		{ "assignedName", debugInfo.AssignedBrainrotName },
		{ "releasedInstanceId", tostring(instanceId) },
		{ "releasedStorage", tostring(instanceData.StorageName or "") },
		{ "brainrotInstanceId", debugInfo.BrainrotInstanceId },
		{ "crewMemberInstanceId", debugInfo.CrewMemberInstanceId },
		{ "legacyStorageName", debugInfo.LegacyStorageName },
		{ "incomeBefore", debugInfo.IncomeBefore },
		{ "quickOccupied", debugInfo.QuickSlotOccupied },
		{ "quickUnlocked", debugInfo.QuickSlotUnlocked },
		{ "quickMax", debugInfo.QuickSlotMax },
		{ "inventorySaveOk", debugInfo.InventorySaveOk },
		{ "inventorySaveReason", debugInfo.InventorySaveReason },
		{ "standClearOk", debugInfo.StandClearOk },
		{ "standClearReason", debugInfo.StandClearReason },
		{ "placedTrackingRefs", debugInfo.AssignedStandRefs },
	}))

	return tostring(instanceId), brainrotInventory.ById[tostring(instanceId)], nil, debugInfo
end

function Module.RemoveAvailableInstance(player, storageName)
	local ready, readyReason = ensureInventoryAuthorityReady(player, "inventory_remove")
	if ready ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority remove failed closed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(storageName),
			tostring(readyReason or "unknown")
		))
		return nil, nil, tostring(readyReason or "inventory_authority_not_ready")
	end

	Module.EnsureAvailableInstancesForStorage(player, storageName, 1)
	local brainrotInventory = getBrainrotInventory(player)
	local instanceId = nil
	local instanceData = nil

	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local candidate = brainrotInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.StorageName == tostring(storageName) and candidate.AssignedStand == "" then
			if not isProtectedTutorialReward(player, candidate) then
				instanceId = tostring(orderedInstanceId)
				instanceData = candidate
				break
			end
		end
	end

	if not instanceData then
		return nil, nil
	end

	brainrotInventory.ById[tostring(instanceId)] = nil
	for index = #brainrotInventory.Order, 1, -1 do
		if tostring(brainrotInventory.Order[index]) == tostring(instanceId) then
			table.remove(brainrotInventory.Order, index)
			break
		end
	end

	local saved, saveReason = saveBrainrotInventory(player, brainrotInventory, {
		SourcePath = "inventory_remove",
	})
	if saved ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority remove save failed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(storageName),
			tostring(saveReason or "unknown")
		))
		return nil, nil, tostring(saveReason or "inventory_authority_save_failed")
	end
	syncAvailableCounts(player, brainrotInventory)
	refreshCrewMemberShadow(player, "inventory_remove")
	return tostring(instanceId), instanceData
end

function Module.RemoveTutorialRewardInstances(player, options)
	options = if typeof(options) == "table" then options else {}
	local ready, readyReason = ensureInventoryAuthorityReady(player, "tutorial_reward_cleanup")
	if ready ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority tutorial cleanup failed closed player=%s reason=%s",
			player and player.Name or "unknown",
			tostring(readyReason or "unknown")
		))
		return {
			RemovedCount = 0,
			RemovedInstanceIds = {},
			RemovedStorageNames = {},
			TutorialStorageNames = {},
			ClearedStands = {},
			FailedReason = tostring(readyReason or "inventory_authority_not_ready"),
		}
	end

	local tutorialStorageNameSet = {}
	local tutorialStorageNames = {}
	local removedStorageNameSet = {}
	local removedStorageNames = {}

	local function addTutorialStorageName(storageName)
		storageName = tostring(storageName or "")
		if storageName == "" or tutorialStorageNameSet[storageName] == true then
			return
		end

		tutorialStorageNameSet[storageName] = true
		table.insert(tutorialStorageNames, storageName)
	end

	local function addRemovedStorageName(storageName)
		storageName = tostring(storageName or "")
		if storageName == "" or removedStorageNameSet[storageName] == true then
			return
		end

		removedStorageNameSet[storageName] = true
		table.insert(removedStorageNames, storageName)
	end

	local configuredStorageNames = options.StorageNames
	if typeof(configuredStorageNames) == "table" then
		for _, storageName in ipairs(configuredStorageNames) do
			addTutorialStorageName(storageName)
		end
	elseif typeof(configuredStorageNames) == "string" then
		addTutorialStorageName(configuredStorageNames)
	end

	local brainrotInventory = getBrainrotInventory(player)
	local removedById = {}
	local removedIds = {}
	local clearedStandMap = {}

	for instanceId, instanceData in pairs(brainrotInventory.ById) do
		if typeof(instanceData) == "table" and instanceData.TutorialReward == true then
			local normalizedId = tostring(instanceId)
			local storageName = tostring(instanceData.StorageName or "")
			addTutorialStorageName(storageName)
			addRemovedStorageName(storageName)
			local assignedStand = tostring(instanceData.AssignedStand or "")
			if assignedStand ~= "" then
				clearedStandMap[assignedStand] = true
			end
			removedById[normalizedId] = instanceData
			table.insert(removedIds, normalizedId)
			brainrotInventory.ById[normalizedId] = nil
		end
	end

	table.sort(removedIds, function(left, right)
		return (tonumber(left) or math.huge) < (tonumber(right) or math.huge)
	end)
	table.sort(removedStorageNames)

	for index = #brainrotInventory.Order, 1, -1 do
		if removedById[tostring(brainrotInventory.Order[index])] ~= nil then
			table.remove(brainrotInventory.Order, index)
		end
	end

	for standName, standData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		if typeof(standData) == "table" then
			local standInstanceId = tostring(standData.BrainrotInstanceId or "")
			local standBrainrotName = tostring(standData.BrainrotName or "")
			local clearByRemovedId = removedById[standInstanceId] ~= nil
			local clearByRemovedAssignedStand = clearedStandMap[tostring(standName)] == true
			local clearByStaleTutorialName = false
			if options.ClearStaleStorageAssignments == true and tutorialStorageNameSet[standBrainrotName] == true then
				local existingInstance = if standInstanceId ~= "" then brainrotInventory.ById[standInstanceId] else nil
				clearByStaleTutorialName = standInstanceId == "" or existingInstance == nil or existingInstance.TutorialReward == true
			end

			if clearByRemovedId or clearByRemovedAssignedStand or clearByStaleTutorialName then
				setStandData(player, standName, {
					BrainrotName = "",
					BrainrotInstanceId = "",
					IncomeToCollect = 0,
					StandLevel = 1,
				}, "tutorial_reward_cleanup")
				clearedStandMap[tostring(standName)] = true
			end
		end
	end

	local clearedStands = {}
	for standName in pairs(clearedStandMap) do
		table.insert(clearedStands, standName)
		clearShipSlotAssignment(player, standName)
		CrewStandIncomeAuthority.SetStandLevel(player, standName, 1, "tutorial_reward_cleanup")
	end
	table.sort(clearedStands, function(left, right)
		return (tonumber(left) or math.huge) < (tonumber(right) or math.huge)
	end)

	if #removedIds > 0 then
		local saved, saveReason = saveBrainrotInventory(player, brainrotInventory, {
			SourcePath = "tutorial_reward_cleanup",
		})
		if saved ~= true then
			return {
				RemovedCount = 0,
				RemovedInstanceIds = {},
				RemovedStorageNames = {},
				TutorialStorageNames = tutorialStorageNames,
				ClearedStands = {},
				FailedReason = tostring(saveReason or "inventory_authority_save_failed"),
			}
		end
		syncAvailableCounts(player, brainrotInventory)
	end

	if #removedIds > 0 or #clearedStands > 0 then
		refreshCrewMemberShadow(player, "tutorial_reward_cleanup")
	end

	return {
		RemovedCount = #removedIds,
		RemovedInstanceIds = removedIds,
		RemovedStorageNames = removedStorageNames,
		TutorialStorageNames = tutorialStorageNames,
		ClearedStands = clearedStands,
	}
end

function Module.TransferStandInstance(ownerPlayer, buyerPlayer, standName)
	local instanceId, instanceData = Module.EnsureStandInstance(ownerPlayer, standName)
	if not instanceData then
		return nil, nil
	end
	if isProtectedTutorialReward(ownerPlayer, instanceData) then
		return nil, nil
	end

	if not CrewQuickSlotService.CanGainOrNotify(buyerPlayer, 1, "TransferStandInstance:" .. tostring(standName)) then
		return nil, nil
	end

	local buyerInventory = getBrainrotInventory(buyerPlayer)

	local _, _, ownerInventory = Module.GetInstance(ownerPlayer, instanceId)
	ownerInventory.ById[tostring(instanceId)] = nil
	for index = #ownerInventory.Order, 1, -1 do
		if tostring(ownerInventory.Order[index]) == tostring(instanceId) then
			table.remove(ownerInventory.Order, index)
			break
		end
	end
	saveBrainrotInventory(ownerPlayer, ownerInventory)
	updateStandData(ownerPlayer, standName, {
		BrainrotName = "",
		BrainrotInstanceId = "",
		IncomeToCollect = 0,
	}, "product_reward_transfer_out")
	syncAvailableCounts(ownerPlayer, ownerInventory)
	refreshCrewMemberShadow(ownerPlayer, "product_reward_transfer_out")

	ensureInventoryMetadata(buyerPlayer, instanceData.StorageName, instanceData)
	local buyerInstanceId = tostring(buyerInventory.NextInstanceId)
	buyerInventory.NextInstanceId += 1
	buyerInventory.ById[buyerInstanceId] = normalizeInstanceData(buyerInstanceId, {
		StorageName = instanceData.StorageName,
		BaseName = instanceData.BaseName,
		Variant = instanceData.Variant,
		Rarity = instanceData.Rarity,
		Income = instanceData.Income,
		Render = instanceData.Render,
		GoldenRender = instanceData.GoldenRender,
		DiamondRender = instanceData.DiamondRender,
		Level = instanceData.Level,
		CurrentXP = instanceData.CurrentXP,
		AssignedStand = "",
		AcquiredAt = instanceData.AcquiredAt,
		LastReleasedAt = os.time(),
	})
	table.insert(buyerInventory.Order, 1, buyerInstanceId)
	IndexCollectionService.MarkCrewMemberDiscovered(
		buyerPlayer,
		instanceData.StorageName,
		instanceData.BaseName,
		instanceData.Variant,
		{
			DeferShadowRefresh = true,
		}
	)
	saveBrainrotInventory(buyerPlayer, buyerInventory)
	syncAvailableCounts(buyerPlayer, buyerInventory)
	refreshCrewMemberShadow(buyerPlayer, "product_reward_transfer_in")

	return buyerInstanceId, buyerInventory.ById[buyerInstanceId]
end

Module.IsCrewInventoryEntry = Module.IsBrainrotInventoryEntry
Module.EnsureCrewInventory = Module.EnsureInventory
Module.GetCrewInventory = Module.EnsureInventory
Module.RegisterCrewInventorySavedCallback = Module.RegisterInventorySavedCallback
Module.SyncCrewAvailableCounts = Module.SyncAvailableCounts
Module.EnsureCrewInventoryMetadata = Module.EnsureInventoryMetadata
Module.CreateCrewInstances = Module.CreateInstances
Module.EnsureAvailableCrewMembersForStorage = Module.EnsureAvailableInstancesForStorage
Module.GetCrewInstance = Module.GetInstance
Module.GetCrewStandInstanceId = Module.GetStandInstanceId
Module.EnsureStandCrewMemberInstance = Module.EnsureStandInstance
Module.FindAvailableCrewMemberInstance = Module.FindAvailableInstance
Module.AssignAvailableCrewMemberToStand = Module.AssignAvailableInstanceToStand
Module.ReleaseStandCrewMember = Module.ReleaseStandInstance
Module.RemoveAvailableCrewMember = Module.RemoveAvailableInstance
Module.TransferStandCrewMember = Module.TransferStandInstance

return Module
