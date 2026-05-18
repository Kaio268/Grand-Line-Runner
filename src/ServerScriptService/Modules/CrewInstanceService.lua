local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local VariantCfg = CrewCatalog.GetVariantConfig()
local CrewInventoryDerivedCache = require(script.Parent:WaitForChild("CrewInventoryDerivedCache"))
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
local invalidCrewIdentityWarnings = {}

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

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or "")
		if value ~= "" then
			return value
		end
	end
	return ""
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

local function notifyInventorySaved(player, crewInventory)
	CrewInventoryDerivedCache.MarkSaved(player, crewInventory, "inventory_saved")
	for callback in pairs(inventorySavedCallbacks) do
		local ok, err = pcall(callback, player, crewInventory)
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

local function warnInvalidCrewIdentity(source, identity, player)
	local key = tostring(source or "unknown") .. ":" .. tostring(identity or "")
	if invalidCrewIdentityWarnings[key] then
		return
	end
	invalidCrewIdentityWarnings[key] = true
	warn(string.format(
		"[CrewInstanceService] Rejected unknown CrewMember identity source=%s player=%s identity=%s",
		tostring(source or "unknown"),
		player and player.Name or "unknown",
		tostring(identity or "")
	))
end

local function resolveCanonicalCrewMemberId(identity)
	return CrewCatalog.ResolveCanonicalCrewMemberId(identity)
end

local function isCrewInventoryEntry(key, entry)
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

	local requestedStorageName = tostring(storageName or "")
	local requestedCrewMemberId = tostring(entry.CrewMemberId or "")
	local lookupName = if requestedCrewMemberId ~= "" then requestedCrewMemberId else requestedStorageName
	local canonicalId, info, resolvedLegacyStorageName = resolveCanonicalCrewMemberId(lookupName)
	if not info and requestedStorageName ~= "" and requestedStorageName ~= lookupName then
		canonicalId, info, resolvedLegacyStorageName = resolveCanonicalCrewMemberId(requestedStorageName)
	end

	if not info then
		return nil
	end

	local variantKey, baseName = getVariantAndBaseName(canonicalId)
	if variantKey == "" then
		variantKey = "Normal"
	end

	if baseName == "" then
		baseName = tostring(entry.BaseName or requestedStorageName)
	end

	local baseInfo = CrewCatalog.GetInfoById(baseName) or info
	local entryStorageName = tostring(entry.StorageName or "")
	local legacyStorageName = firstNonEmpty(entry.LegacyStorageName, resolvedLegacyStorageName)
	if legacyStorageName == "" and entryStorageName ~= "" and entryStorageName ~= tostring(canonicalId or "") then
		legacyStorageName = entryStorageName
	end
	if legacyStorageName == "" and requestedStorageName ~= "" and requestedStorageName ~= tostring(canonicalId or "") then
		legacyStorageName = requestedStorageName
	end

	local render = firstNonEmpty(info.Render, entry.Render)
	local goldenRender = firstNonEmpty(baseInfo.GoldenRender, baseInfo.Render, entry.GoldenRender, render)
	local diamondRender = firstNonEmpty(baseInfo.DiamondRender, baseInfo.Render, entry.DiamondRender, render)

	return {
		StorageName = tostring(canonicalId or requestedStorageName),
		LegacyStorageName = legacyStorageName,
		BaseName = baseName,
		Variant = variantKey,
		Rarity = tostring(info.Rarity or entry.Rarity or "Common"),
		Income = tonumber(info.Income or entry.Income) or 0,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
		DisplayName = firstNonEmpty(info.DisplayName, info.Name, entry.DisplayName, canonicalId, requestedStorageName),
		CrewMemberId = firstNonEmpty(info.CrewMemberId, canonicalId, requestedStorageName),
		RealCharacterName = firstNonEmpty(info.RealCharacterName),
		Arc = firstNonEmpty(info.Arc),
		ModelName = firstNonEmpty(info.ModelName, entry.ModelName, baseName),
	}
end

local function getInstanceCrewKey(instanceData)
	if typeof(instanceData) ~= "table" then
		return ""
	end
	return firstNonEmpty(instanceData.CrewMemberId, instanceData.StorageName)
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

local function valuesEqual(left, right)
	if typeof(left) ~= typeof(right) then
		return false
	end
	if typeof(left) ~= "table" then
		return left == right
	end

	for key, leftValue in pairs(left) do
		if not valuesEqual(leftValue, right[key]) then
			return false
		end
	end
	for key in pairs(right) do
		if left[key] == nil then
			return false
		end
	end
	return true
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
		or select(2, resolveCanonicalCrewMemberId(storageName)) ~= nil
end

local function ensureCrewInventoryShape(crewInventory)
	if typeof(crewInventory) ~= "table" then
		crewInventory = {}
	end

	crewInventory.NextInstanceId = math.max(1, coerceNumber(crewInventory.NextInstanceId, 1))
	crewInventory.ById = ensureTable(crewInventory, "ById")
	crewInventory.Order = ensureTable(crewInventory, "Order")

	return crewInventory
end

local function normalizeInstanceData(instanceId, instanceData, fallbackStorageName, options)
	instanceData = typeof(instanceData) == "table" and instanceData or {}
	options = if typeof(options) == "table" then options else {}

	local storageName = firstNonEmpty(instanceData.CrewMemberId, instanceData.StorageName, fallbackStorageName)
	if storageName == "" then
		return nil
	end

	local metadata = buildMetadata(storageName, instanceData)
	if metadata == nil then
		return nil
	end

	local normalized = {
		InstanceId = tostring(instanceId),
		StorageName = metadata.StorageName,
		LegacyStorageName = metadata.LegacyStorageName,
		BaseName = metadata.BaseName,
		Variant = metadata.Variant,
		Rarity = tostring(metadata.Rarity or instanceData.Rarity or "Common"),
		Income = tonumber(metadata.Income or instanceData.Income) or 0,
		Render = firstNonEmpty(metadata.Render, instanceData.Render),
		GoldenRender = firstNonEmpty(metadata.GoldenRender, instanceData.GoldenRender, metadata.Render),
		DiamondRender = firstNonEmpty(metadata.DiamondRender, instanceData.DiamondRender, metadata.Render),
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
		CrewMemberId = metadata.CrewMemberId,
		DisplayName = metadata.DisplayName,
		ModelName = metadata.ModelName,
		RealCharacterName = metadata.RealCharacterName,
		Arc = metadata.Arc,
	}
	if options.Canonical == true then
		normalized.ProjectionSource = tostring(instanceData.ProjectionSource or "CrewInstanceService")
	end
	return normalized
end

local syncAvailableCounts
local inspectInventoryRoot
local clearShipSlotAssignment
local clearStandData

local function normalizeInventoryData(rawInventory, options)
	options = if typeof(options) == "table" then options else {}
	local inventory = ensureCrewInventoryShape(rawInventory)
	local changed = false
	local quarantine = {
		RemovedInstances = {},
		ClearedStands = {},
	}
	local function recordQuarantinedInstance(instanceId, instanceData)
		local rawIdentity = firstNonEmpty(
			typeof(instanceData) == "table" and instanceData.CrewMemberId or "",
			typeof(instanceData) == "table" and instanceData.StorageName or "",
			typeof(instanceData) == "table" and instanceData.LegacyStorageName or ""
		)
		quarantine.RemovedInstances[#quarantine.RemovedInstances + 1] = {
			InstanceId = tostring(instanceId or ""),
			Identity = rawIdentity,
			AssignedStand = typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") or "",
		}
		local assignedStand = typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") or ""
		if assignedStand ~= "" then
			quarantine.ClearedStands[assignedStand] = true
		end
	end
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
		local existing = inventory.ById[instanceId]
		local normalized = normalizeInstanceData(instanceId, existing, nil, {
			Canonical = options.Canonical == true,
		})
		if normalized then
			if not valuesEqual(existing, normalized) then
				changed = true
			end
			inventory.ById[instanceId] = normalized
			if not seen[instanceId] then
				seen[instanceId] = true
				table.insert(normalizedOrder, instanceId)
			else
				changed = true
			end
		else
			recordQuarantinedInstance(instanceId, existing)
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
				if not valuesEqual(instanceData, normalized) then
					changed = true
				end
				inventory.ById[instanceId] = normalized
				table.insert(normalizedOrder, instanceId)
				seen[instanceId] = true
				changed = true
			else
				recordQuarantinedInstance(instanceId, instanceData)
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

	return inventory, changed, quarantine
end

local function getAvailableCountsFromInventory(inventory)
	local counts = {}
	if typeof(inventory) ~= "table" or typeof(inventory.Order) ~= "table" or typeof(inventory.ById) ~= "table" then
		return counts
	end

	for _, instanceId in ipairs(inventory.Order) do
		local instanceData = inventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == "" then
			local storageName = getInstanceCrewKey(instanceData)
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
		CrewMemberInventoryRetired = true,
		InventoryCrewMirrorsRetired = true,
		BlockingCount = #issues,
		UnclassifiedCount = 0,
		Issues = issues,
		Canonical = {
			NextInstanceId = if canonicalInventory then canonicalInventory.NextInstanceId else nil,
			InstanceCount = canonical.InstanceCount,
			Counts = expectedCounts,
		},
		CrewMemberInventory = {
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

local function saveCrewMemberInventory(player, crewMemberInventory, _options)
	local canonicalInventory = normalizeInventoryData(cloneValue(crewMemberInventory), {
		Canonical = true,
	})
	local ok, reason = writeProfileRoot(player, CANONICAL_INVENTORY_PATH, canonicalInventory)
	if ok ~= true then
		return false, "inventory_write_failed:CrewMemberInventory:" .. tostring(reason or "")
	end
	notifyInventorySaved(player, canonicalInventory)
	return true, nil
end

local function getCrewMemberInventory(player)
	local rawInventory = getDataManager():GetValue(player, CANONICAL_INVENTORY_PATH)
	local missingCanonical = typeof(rawInventory) ~= "table"
	local inventory, changed, quarantine = normalizeInventoryData(rawInventory, {
		Canonical = true,
	})

	if changed and not missingCanonical then
		saveCrewMemberInventory(player, inventory, {
			SourcePath = "inventory_normalize",
		})
		if typeof(quarantine) == "table" then
			for _, entry in ipairs(quarantine.RemovedInstances or {}) do
				warnInvalidCrewIdentity("inventory_normalize", entry.Identity, player)
			end
			for standName in pairs(quarantine.ClearedStands or {}) do
				clearStandData(player, standName, "invalid_inventory_identity_quarantine")
				if clearShipSlotAssignment ~= nil then
					clearShipSlotAssignment(player, standName)
				end
			end
		end
	elseif missingCanonical then
		updateInventoryAuthorityAudit(player, {
			LastFailClosedReason = "canonical_inventory_missing",
			LastFailClosedSourcePath = "getCrewInventory",
		})
	end

	return inventory
end

local function setInstanceData(player, crewMemberInventory, instanceId, instanceData)
	local normalized = normalizeInstanceData(instanceId, instanceData, nil, {
		Canonical = true,
	})
	if normalized == nil then
		local rawIdentity = ""
		if typeof(instanceData) == "table" then
			rawIdentity = firstNonEmpty(instanceData.CrewMemberId, instanceData.StorageName, instanceData.LegacyStorageName)
		end
		warnInvalidCrewIdentity(
			"inventory_set_instance_data",
			rawIdentity,
			player
		)
		return false, "unknown_crew_member_id"
	end
	crewMemberInventory.ById[tostring(instanceId)] = normalized
	return saveCrewMemberInventory(player, crewMemberInventory, {
		SourcePath = "inventory_set_instance_data",
	})
end

syncAvailableCounts = function(player, crewMemberInventory, options)
	local _ = player
	_ = crewMemberInventory
	_ = options
	return true
end

local function moveInstanceToFront(crewMemberInventory, instanceId)
	instanceId = tostring(instanceId)
	for index = #crewMemberInventory.Order, 1, -1 do
		if tostring(crewMemberInventory.Order[index]) == instanceId then
			table.remove(crewMemberInventory.Order, index)
			break
		end
	end
	table.insert(crewMemberInventory.Order, 1, instanceId)
end

clearShipSlotAssignment = function(player, standName)
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

clearStandData = function(player, standName, sourcePath)
	return CrewStandIncomeAuthority.ClearStandData(player, standName, sourcePath)
end

local function ensureInventoryMetadata(player, storageName, metadata)
	local _ = player
	return metadata or buildMetadata(storageName)
end

local function createInstanceInternal(player, crewMemberInventory, storageName, overrides)
	local metadata = buildMetadata(storageName, overrides)
	if metadata == nil then
		warnInvalidCrewIdentity("inventory_create_instance", storageName, player)
		return nil, nil, "unknown_crew_member_id"
	end

	local instanceId = tostring(crewMemberInventory.NextInstanceId)
	crewMemberInventory.NextInstanceId += 1
	crewMemberInventory.ById[instanceId] = normalizeInstanceData(instanceId, {
		StorageName = metadata.StorageName,
		LegacyStorageName = metadata.LegacyStorageName,
		CrewMemberId = metadata.CrewMemberId,
		DisplayName = metadata.DisplayName,
		ModelName = metadata.ModelName,
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
		RealCharacterName = metadata.RealCharacterName,
		Arc = metadata.Arc,
	}, nil, {
		Canonical = true,
	})
	if overrides and overrides.TutorialReward == true then
		table.insert(crewMemberInventory.Order, 1, instanceId)
	else
		table.insert(crewMemberInventory.Order, instanceId)
	end
	IndexCollectionService.MarkCrewMemberDiscovered(
		player,
		metadata.CrewMemberId,
		overrides and overrides.BaseName or metadata.BaseName,
		overrides and overrides.Variant or metadata.Variant,
		{
			DeferShadowRefresh = overrides and overrides.DeferIndexShadowRefresh == true,
		}
	)

	return instanceId, crewMemberInventory.ById[instanceId]
end

local function getStoredLegacyProgress(player, storageName)
	local crewMemberInventory = getCrewMemberInventory(player)
	local requestedId = tostring((resolveCanonicalCrewMemberId(storageName)))
	for _, instanceId in ipairs(crewMemberInventory.Order) do
		local instanceData = crewMemberInventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table"
			and (
				getInstanceCrewKey(instanceData) == requestedId
				or tostring(instanceData.LegacyStorageName or "") == tostring(storageName or "")
			)
		then
			return math.max(1, math.floor(coerceNumber(instanceData.Level, 1))),
				math.max(0, math.floor(coerceNumber(instanceData.CurrentXP, 0)))
		end
	end
	return 1, 0
end

function Module.IsCrewMemberInventoryEntry(key, entry)
	return isCrewInventoryEntry(key, entry)
end

function Module.IsCrewInventoryEntry(key, entry)
	return isCrewInventoryEntry(key, entry)
end

function Module.EnsureInventory(player)
	return getCrewMemberInventory(player)
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
	local legacy = status.CrewMemberInventory or {}
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
	return saveCrewMemberInventory(player, crewInventory, options)
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
	local canonicalStorageName = tostring((resolveCanonicalCrewMemberId(storageName)))
	if storageName ~= "" and canonicalStorageName == "" then
		return false
	end
	if storageName ~= ""
		and canonicalStorageName ~= ""
		and getInstanceCrewKey(instanceData) ~= canonicalStorageName
		and tostring(instanceData.LegacyStorageName or "") ~= storageName
	then
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
	local crewMemberInventory = getCrewMemberInventory(player)
	local requestedInstanceId = tostring(filters.InstanceId or "")

	if requestedInstanceId ~= "" then
		local instanceData = crewMemberInventory.ById[requestedInstanceId]
		if tutorialRewardMatchesFilters(instanceData, filters) then
			return requestedInstanceId, instanceData, crewMemberInventory
		end
	end

	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local instanceId = tostring(orderedInstanceId)
		local instanceData = crewMemberInventory.ById[instanceId]
		if tutorialRewardMatchesFilters(instanceData, filters) then
			return instanceId, instanceData, crewMemberInventory
		end
	end

	return nil, nil, crewMemberInventory
end

function Module.HasUsableTutorialReward(player, storageName, tutorialToken)
	local instanceId, instanceData = Module.FindTutorialRewardInstance(player, {
		StorageName = tostring(storageName or ""),
		TutorialToken = tostring(tutorialToken or ""),
		RequireAvailable = true,
	})
	return instanceData ~= nil, instanceId, instanceData
end

local function getStandOccupancy(player, standName, crewMemberInventory)
	standName = tostring(standName or "")
	if standName == "" then
		return true, "invalid_stand"
	end

	local standData = getStandData(player, standName)
	if tostring(standData.CrewMemberName or "") ~= "" or tostring(standData.CrewMemberInstanceId or "") ~= "" then
		return true, "stand_occupied", tostring(standData.CrewMemberInstanceId or ""), tostring(standData.CrewMemberName or "")
	end

	crewMemberInventory = crewMemberInventory or getCrewMemberInventory(player)
	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local instanceId = tostring(orderedInstanceId)
		local instanceData = crewMemberInventory.ById[instanceId]
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

	local instanceId, instanceData, crewMemberInventory = Module.FindTutorialRewardInstance(player, filters)
	if not instanceData then
		return nil, nil, "instance_unavailable"
	end

	local occupied, occupancyReason = getStandOccupancy(player, standName, crewMemberInventory)
	if occupied then
		return nil, nil, occupancyReason
	end

	instanceData.AssignedStand = tostring(standName)
	local saveOk, saveReason = setInstanceData(player, crewMemberInventory, instanceId, instanceData)
	if saveOk ~= true then
		return nil, nil, tostring(saveReason or "assignment_save_failed")
	end

	local standOk, standReason = updateStandData(player, standName, {
		CrewMemberName = getInstanceCrewKey(instanceData),
		CrewMemberInstanceId = tostring(instanceId),
		StandLevel = math.max(1, math.floor(coerceNumber(instanceData.Level, 1))),
	}, "stand_place_tutorial_reward")
	if standOk ~= true then
		instanceData.AssignedStand = ""
		setInstanceData(player, crewMemberInventory, instanceId, instanceData)
		return nil, nil, tostring(standReason or "stand_income_write_failed")
	end

	if clearTutorialMetadataAfterAssign then
		local assignedInstanceData = crewMemberInventory.ById[tostring(instanceId)]
		if assignedInstanceData then
			assignedInstanceData.TutorialReward = false
			assignedInstanceData.TutorialToken = ""
			assignedInstanceData.TutorialOwnerUserId = nil
			assignedInstanceData.TutorialCrewMember = nil
			assignedInstanceData.TutorialRewardName = nil
			setInstanceData(player, crewMemberInventory, instanceId, assignedInstanceData)
		end
	end

	syncAvailableCounts(player, crewMemberInventory)
	refreshCrewMemberShadow(player, "stand_place")

	return tostring(instanceId), crewMemberInventory.ById[tostring(instanceId)]
end

function Module.EnsureInventoryMetadata(player, storageName, metadata)
	return ensureInventoryMetadata(player, storageName, metadata)
end

function Module.CreateInstances(player, storageName, count, overrides)
	local safeCount = math.max(0, math.floor(coerceNumber(count, 0)))
	if safeCount <= 0 then
		return {}, "non_positive_count"
	end
	local canonicalStorageName, info = resolveCanonicalCrewMemberId(storageName)
	if not info then
		warnInvalidCrewIdentity("inventory_grant", storageName, player)
		return {}, "unknown_crew_member_id"
	end

	local assignedStand = tostring(overrides and overrides.AssignedStand or "")
	local capacityReserved = overrides and overrides._QuickSlotCapacityReserved == true
	if assignedStand == "" and not capacityReserved then
		local canGain, _, _, _, capacityReason =
			CrewQuickSlotService.CanGainOrNotify(player, canonicalStorageName, safeCount, "CreateInstances:" .. tostring(canonicalStorageName))
		if not canGain then
			return {}, tostring(capacityReason or "crew_stack_capacity_full")
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
		return {}, tostring(readyReason or "inventory_authority_not_ready")
	end

	local crewMemberInventory = getCrewMemberInventory(player)

	local createdIds = {}
	for _ = 1, safeCount do
		local instanceOverrides = if typeof(overrides) == "table" then table.clone(overrides) else {}
		instanceOverrides.DeferIndexShadowRefresh = true
		local instanceId, _, createReason = createInstanceInternal(player, crewMemberInventory, canonicalStorageName, instanceOverrides)
		if instanceId == nil then
			return {}, tostring(createReason or "create_instance_failed")
		end
		table.insert(createdIds, instanceId)
	end

	local saved, saveReason = saveCrewMemberInventory(player, crewMemberInventory, {
		SourcePath = "inventory_grant",
	})
	if saved ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority grant save failed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(storageName),
			tostring(saveReason or "unknown")
		))
		return {}, tostring(saveReason or "inventory_save_failed")
	end
	syncAvailableCounts(player, crewMemberInventory)
	refreshCrewMemberShadow(player, "inventory_grant")
	return createdIds
end

function Module.EnsureAvailableInstancesForStorage(player, storageName, minimumAvailable, options)
	local requestedStorageName = tostring(storageName or "")
	local canonicalStorageName, info = resolveCanonicalCrewMemberId(storageName)
	if not info then
		warnInvalidCrewIdentity("inventory_ensure_available", storageName, player)
		return 0
	end

	local ready, readyReason = ensureInventoryAuthorityReady(player, "inventory_ensure_available")
	if ready ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority ensure available failed closed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(canonicalStorageName),
			tostring(readyReason or "unknown")
		))
		return 0
	end

	local crewMemberInventory = getCrewMemberInventory(player)
	local availableCount = 0
	for _, instanceId in ipairs(crewMemberInventory.Order) do
		local instanceData = crewMemberInventory.ById[tostring(instanceId)]
		if instanceData and getInstanceCrewKey(instanceData) == canonicalStorageName and instanceData.AssignedStand == "" then
			availableCount += 1
		end
	end

	local requestedMinimum = math.max(0, math.floor(coerceNumber(minimumAvailable, 0)))
	local targetCount = requestedMinimum
	if availableCount >= targetCount then
		return availableCount
	end

	local level, currentXP = getStoredLegacyProgress(player, canonicalStorageName)
	for _ = 1, (targetCount - availableCount) do
		local createdId = createInstanceInternal(player, crewMemberInventory, if requestedStorageName ~= "" then requestedStorageName else canonicalStorageName, {
			Level = level,
			CurrentXP = currentXP,
		})
		if createdId == nil then
			return availableCount
		end
	end

	local saved, saveReason = saveCrewMemberInventory(player, crewMemberInventory, {
		SourcePath = "inventory_ensure_available",
	})
	if saved ~= true then
		warn(string.format(
			"[CrewInstanceService] CrewMember inventory authority ensure available save failed player=%s storage=%s reason=%s",
			player and player.Name or "unknown",
			tostring(canonicalStorageName),
			tostring(saveReason or "unknown")
		))
		return availableCount
	end
	syncAvailableCounts(player, crewMemberInventory)
	if not (typeof(options) == "table" and options.DeferShadowRefresh == true) then
		refreshCrewMemberShadow(player, "data_repair_available_instances")
	end
	return targetCount
end

function Module.GetInstance(player, instanceRef)
	local crewMemberInventory = getCrewMemberInventory(player)
	local instanceId = nil

	if typeof(instanceRef) == "table" then
		instanceId = tostring(instanceRef.InstanceId or "")
	else
		instanceId = tostring(instanceRef or "")
	end

	local instanceData = crewMemberInventory.ById[instanceId]
	if instanceData then
		return instanceId, instanceData, crewMemberInventory
	end

	return nil, nil, crewMemberInventory
end

function Module.ResolveProgressTarget(player, reference)
	local instanceId, instanceData, crewMemberInventory = Module.GetInstance(player, reference)
	if instanceData then
		return instanceId, instanceData, crewMemberInventory
	end

	local storageName = tostring(reference or "")
	if storageName == "" then
		return nil, nil, crewMemberInventory
	end
	local canonicalStorageName, info = resolveCanonicalCrewMemberId(storageName)
	if not info then
		warnInvalidCrewIdentity("progress_target", storageName, player)
		return nil, nil, crewMemberInventory
	end

	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local candidate = crewMemberInventory.ById[tostring(orderedInstanceId)]
		if candidate and getInstanceCrewKey(candidate) == canonicalStorageName then
			return tostring(orderedInstanceId), candidate, crewMemberInventory
		end
	end

	Module.EnsureAvailableInstancesForStorage(player, canonicalStorageName, 1)
	crewMemberInventory = getCrewMemberInventory(player)

	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local candidate = crewMemberInventory.ById[tostring(orderedInstanceId)]
		if candidate and getInstanceCrewKey(candidate) == canonicalStorageName then
			return tostring(orderedInstanceId), candidate, crewMemberInventory
		end
	end

	return nil, nil, crewMemberInventory
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

	local resolvedInstanceId, instanceData, crewMemberInventory = Module.GetInstance(player, instanceId)
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
	local saveOk, saveReason = setInstanceData(player, crewMemberInventory, resolvedInstanceId, instanceData)
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

	local updated = crewMemberInventory.ById[resolvedInstanceId]

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
	local rawInstanceId = tostring(standData.CrewMemberInstanceId or "")
	if rawInstanceId == "" then
		return ""
	end

	local instanceId, instanceData = Module.GetInstance(player, rawInstanceId)
	if not instanceData then
		return ""
	end

	if instanceData.AssignedStand ~= tostring(standName) then
		instanceData.AssignedStand = tostring(standName)
		local _, _, crewMemberInventory = Module.GetInstance(player, instanceId)
		setInstanceData(player, crewMemberInventory, instanceId, instanceData)
		refreshCrewMemberShadow(player, "data_repair_stand_assignment")
	end

	return instanceId
end

function Module.EnsureStandInstance(player, standName, fallbackStorageName)
	local standData = getStandData(player, standName)
	local standStorageName = firstNonEmpty(standData.CrewMemberName, fallbackStorageName)
	if standStorageName == "" then
		if standData.CrewMemberInstanceId ~= "" then
			updateStandData(player, standName, {
				CrewMemberInstanceId = "",
			}, "data_repair_stand_instance")
			refreshCrewMemberShadow(player, "data_repair_stand_instance")
		end
		return nil, nil
	end
	local canonicalStandStorageName, standInfo = resolveCanonicalCrewMemberId(standStorageName)
	if not standInfo then
		warnInvalidCrewIdentity("stand_instance", standStorageName, player)
		clearStandData(player, standName, "invalid_stand_identity_quarantine")
		clearShipSlotAssignment(player, standName)
		return nil, nil
	end
	standStorageName = canonicalStandStorageName
	if standData.NeedsCanonicalRepair == true or standData.CrewMemberName ~= standStorageName then
		updateStandData(player, standName, {
			CrewMemberName = standStorageName,
			CrewMemberInstanceId = tostring(standData.CrewMemberInstanceId or ""),
			StandLevel = math.max(1, math.floor(coerceNumber(standData.StandLevel, 1))),
		}, "stand_identity_repair")
	end

	local instanceId = tostring(standData.CrewMemberInstanceId or "")
	local crewMemberInventory = getCrewMemberInventory(player)
	local instanceData = crewMemberInventory.ById[instanceId]
	if instanceData then
		local repaired = false
		if instanceData.AssignedStand ~= tostring(standName) then
			instanceData.AssignedStand = tostring(standName)
			setInstanceData(player, crewMemberInventory, instanceId, instanceData)
			repaired = true
		end
		if standData.CrewMemberName ~= getInstanceCrewKey(instanceData) then
			updateStandData(player, standName, {
				CrewMemberName = getInstanceCrewKey(instanceData),
				CrewMemberInstanceId = tostring(instanceId),
			}, "data_repair_stand_instance")
			repaired = true
		end
		if repaired then
			refreshCrewMemberShadow(player, "data_repair_stand_instance")
		end
		return instanceId, instanceData
	end

	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local candidate = crewMemberInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.AssignedStand == tostring(standName) then
			local repaired = false
			updateStandData(player, standName, {
				CrewMemberInstanceId = tostring(orderedInstanceId),
			}, "data_repair_stand_instance")
			repaired = true
			if standData.CrewMemberName ~= getInstanceCrewKey(candidate) then
				updateStandData(player, standName, {
					CrewMemberName = getInstanceCrewKey(candidate),
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
	crewMemberInventory = getCrewMemberInventory(player)
	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local candidate = crewMemberInventory.ById[tostring(orderedInstanceId)]
		if candidate and getInstanceCrewKey(candidate) == standStorageName and candidate.AssignedStand == "" then
			candidate.AssignedStand = tostring(standName)
			setInstanceData(player, crewMemberInventory, orderedInstanceId, candidate)
			updateStandData(player, standName, {
				CrewMemberInstanceId = tostring(orderedInstanceId),
			}, "data_repair_stand_instance")
			if standData.CrewMemberName ~= getInstanceCrewKey(candidate) then
				updateStandData(player, standName, {
					CrewMemberName = getInstanceCrewKey(candidate),
				}, "data_repair_stand_instance")
			end
			syncAvailableCounts(player)
			refreshCrewMemberShadow(player, "data_repair_stand_instance")
			return tostring(orderedInstanceId), candidate
		end
	end

	local level, currentXP = getStoredLegacyProgress(player, standStorageName)
	local createdId = createInstanceInternal(player, crewMemberInventory, standStorageName, {
		AssignedStand = tostring(standName),
		Level = level,
		CurrentXP = currentXP,
	})
	if createdId == nil then
		clearStandData(player, standName, "invalid_stand_identity_quarantine")
		clearShipSlotAssignment(player, standName)
		return nil, nil
	end
	saveCrewMemberInventory(player, crewMemberInventory)
	updateStandData(player, standName, {
		CrewMemberName = getInstanceCrewKey(crewMemberInventory.ById[tostring(createdId)]) or standStorageName,
		CrewMemberInstanceId = tostring(createdId),
	}, "data_repair_stand_instance")
	syncAvailableCounts(player, crewMemberInventory)
	refreshCrewMemberShadow(player, "data_repair_stand_instance")
	return tostring(createdId), crewMemberInventory.ById[tostring(createdId)]
end

function Module.ReconcileStandAssignment(player, standName)
	standName = tostring(standName or "")
	if standName == "" then
		return false, "invalid_stand"
	end

	local standData = getStandData(player, standName)
	local standCrewMemberName = tostring(standData.CrewMemberName or "")
	local standInstanceId = tostring(standData.CrewMemberInstanceId or "")
	if standData.HasInvalidCrewMember == true then
		warnInvalidCrewIdentity("stand_assignment_reconcile", standData.QuarantinedCrewMemberName, player)
		clearStandData(player, standName, "invalid_stand_identity_quarantine")
		clearShipSlotAssignment(player, standName)
		return true, "invalid_stand_identity_quarantined"
	end
	local crewMemberInventory = getCrewMemberInventory(player)
	local assignedInstanceId = ""
	local assignedInstanceData = nil

	if standInstanceId ~= "" and typeof(crewMemberInventory.ById[standInstanceId]) == "table" then
		assignedInstanceId = standInstanceId
		assignedInstanceData = crewMemberInventory.ById[standInstanceId]
	end

	if assignedInstanceData == nil then
		for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
			local candidate = crewMemberInventory.ById[tostring(orderedInstanceId)]
			if typeof(candidate) == "table" and tostring(candidate.AssignedStand or "") == standName then
				assignedInstanceId = tostring(orderedInstanceId)
				assignedInstanceData = candidate
				break
			end
		end
	end

	if assignedInstanceData == nil then
		if standCrewMemberName ~= "" or standInstanceId ~= "" then
			local ensuredInstanceId, ensuredInstanceData = Module.EnsureStandInstance(player, standName, standCrewMemberName)
			if ensuredInstanceData then
				return true, "ensured_from_stand_income", ensuredInstanceId, ensuredInstanceData
			end
		end
		return true, "no_assignment"
	end

	local canonicalCrewMemberId = getInstanceCrewKey(assignedInstanceData)
	if canonicalCrewMemberId == "" then
		assignedInstanceData.AssignedStand = ""
		setInstanceData(player, crewMemberInventory, assignedInstanceId, assignedInstanceData)
		return false, "missing_canonical_crew_member_id"
	end

	if tostring(assignedInstanceData.AssignedStand or "") ~= standName then
		assignedInstanceData.AssignedStand = standName
		setInstanceData(player, crewMemberInventory, assignedInstanceId, assignedInstanceData)
	end

	if standData.NeedsCanonicalRepair == true then
		updateStandData(player, standName, {
			CrewMemberName = canonicalCrewMemberId,
			CrewMemberInstanceId = assignedInstanceId,
			StandLevel = math.max(1, math.floor(coerceNumber(assignedInstanceData.Level, 1))),
		}, "stand_identity_repair")
		refreshCrewMemberShadow(player, "stand_identity_repair")
	end

	if standCrewMemberName == canonicalCrewMemberId and standInstanceId == assignedInstanceId then
		return true, "in_sync", assignedInstanceId, assignedInstanceData
	end

	local standOk, standReason = updateStandData(player, standName, {
		CrewMemberName = canonicalCrewMemberId,
		CrewMemberInstanceId = assignedInstanceId,
		StandLevel = math.max(1, math.floor(coerceNumber(assignedInstanceData.Level, 1))),
	}, "stand_assignment_reconcile")
	if standOk ~= true then
		assignedInstanceData.AssignedStand = ""
		setInstanceData(player, crewMemberInventory, assignedInstanceId, assignedInstanceData)
		return false, tostring(standReason or "stand_income_write_failed")
	end

	refreshCrewMemberShadow(player, "stand_assignment_reconcile")
	return true, "rebuilt_income_row", assignedInstanceId, assignedInstanceData
end

function Module.RepairCanonicalCrewState(player)
	local crewMemberInventory = getCrewMemberInventory(player)
	local standNames = {}

	for _, instanceData in pairs(crewMemberInventory.ById) do
		if typeof(instanceData) == "table" then
			local assignedStand = tostring(instanceData.AssignedStand or "")
			if assignedStand ~= "" then
				standNames[assignedStand] = true
			end
		end
	end

	for standName, standData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		standNames[tostring(standName)] = true
		if typeof(standData) == "table" and standData.HasInvalidCrewMember == true then
			warnInvalidCrewIdentity("stand_income_repair", standData.QuarantinedCrewMemberName, player)
			clearStandData(player, standName, "invalid_stand_identity_quarantine")
			clearShipSlotAssignment(player, standName)
			standNames[tostring(standName)] = nil
		end
	end

	for standName in pairs(standNames) do
		Module.ReconcileStandAssignment(player, standName)
	end

	return true
end

function Module.FindAvailableInstance(player, storageName)
	local canonicalStorageName, info = resolveCanonicalCrewMemberId(storageName)
	if not info then
		warnInvalidCrewIdentity("find_available_instance", storageName, player)
		return nil, nil, getCrewMemberInventory(player)
	end
	Module.EnsureAvailableInstancesForStorage(player, storageName, 1)
	local crewMemberInventory = getCrewMemberInventory(player)
	for _, instanceId in ipairs(crewMemberInventory.Order) do
		local instanceData = crewMemberInventory.ById[tostring(instanceId)]
		if instanceData and getInstanceCrewKey(instanceData) == canonicalStorageName and instanceData.AssignedStand == "" then
			return tostring(instanceId), instanceData, crewMemberInventory
		end
	end
	return nil, nil, crewMemberInventory
end

function Module.AssignAvailableInstanceToStand(player, storageName, standName)
	local instanceId, instanceData, crewMemberInventory = Module.FindAvailableInstance(player, storageName)
	if not instanceData then
		return nil, nil, "instance_unavailable"
	end

	local occupied, occupancyReason = getStandOccupancy(player, standName, crewMemberInventory)
	if occupied then
		return nil, nil, occupancyReason
	end

	instanceData.AssignedStand = tostring(standName)
	local saveOk, saveReason = setInstanceData(player, crewMemberInventory, instanceId, instanceData)
	if saveOk ~= true then
		return nil, nil, tostring(saveReason or "assignment_save_failed")
	end

	local standOk, standReason = updateStandData(player, standName, {
		CrewMemberName = getInstanceCrewKey(instanceData),
		CrewMemberInstanceId = tostring(instanceId),
		StandLevel = math.max(1, math.floor(coerceNumber(instanceData.Level, 1))),
	}, "stand_place")
	if standOk ~= true then
		instanceData.AssignedStand = ""
		setInstanceData(player, crewMemberInventory, instanceId, instanceData)
		return nil, nil, tostring(standReason or "stand_income_write_failed")
	end
	syncAvailableCounts(player, crewMemberInventory)
	refreshCrewMemberShadow(player, "stand_place")

	return tostring(instanceId), crewMemberInventory.ById[tostring(instanceId)]
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
		AssignedCrewMemberName = tostring(standDataBefore and standDataBefore.CrewMemberName or ""),
		CrewMemberInstanceId = tostring((canonicalBefore and canonicalBefore.CrewMemberInstanceId) or (standDataBefore and standDataBefore.CrewMemberInstanceId) or ""),
		LegacyStorageName = tostring((canonicalBefore and canonicalBefore.LegacyStorageName) or (standDataBefore and standDataBefore.CrewMemberName) or ""),
		IncomeBefore = tonumber(standDataBefore and standDataBefore.IncomeToCollect) or 0,
	}

	local instanceId, instanceData = Module.EnsureStandInstance(player, standName)
	debugInfo.EnsureInstanceId = tostring(instanceId or "")
	debugInfo.InstanceExistsInCrewInventory = instanceData ~= nil
	debugInfo.PlayerOwnsInstance = instanceData ~= nil
	debugInfo.InstanceStorageName = instanceData and tostring(instanceData.StorageName or "") or ""
	debugInfo.InstanceAssignedStand = instanceData and tostring(instanceData.AssignedStand or "") or ""

	local crewMemberInventory = getCrewMemberInventory(player)
	local assignedStandRefs = {}
	if typeof(crewMemberInventory) == "table" and typeof(crewMemberInventory.ById) == "table" then
		for ownedInstanceId, ownedInstanceData in pairs(crewMemberInventory.ById) do
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
			{ "assignedName", debugInfo.AssignedCrewMemberName },
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
		getInstanceCrewKey(instanceData),
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
				{ "assignedName", debugInfo.AssignedCrewMemberName },
				{ "instanceId", tostring(instanceId) },
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
		crewMemberInventory = releaseInventory
	end

	instanceData.AssignedStand = ""
	instanceData.LastReleasedAt = os.time()
	crewMemberInventory.ById[tostring(instanceId)] = instanceData
	moveInstanceToFront(crewMemberInventory, instanceId)
	local saveOk, saveReason = saveCrewMemberInventory(player, crewMemberInventory)
	debugInfo.InventorySaveOk = saveOk == true
	debugInfo.InventorySaveReason = tostring(saveReason or "")
	if saveOk ~= true then
		crewPickupDebug(formatCrewPickupDebugFields({
			{ "event", "release_failed" },
			{ "reason", "inventory_write_failed" },
			{ "player", debugInfo.PlayerName },
			{ "userId", debugInfo.UserId },
			{ "stand", standName },
			{ "assignedName", debugInfo.AssignedCrewMemberName },
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
		crewMemberInventory.ById[tostring(instanceId)] = instanceData
		local rollbackOk, rollbackReason = saveCrewMemberInventory(player, crewMemberInventory)
		debugInfo.InventoryRollbackOk = rollbackOk == true
		debugInfo.InventoryRollbackReason = tostring(rollbackReason or "")
		crewPickupDebug(formatCrewPickupDebugFields({
			{ "event", "release_failed" },
			{ "reason", "stand_clear_failed" },
			{ "player", debugInfo.PlayerName },
			{ "userId", debugInfo.UserId },
			{ "stand", standName },
			{ "assignedName", debugInfo.AssignedCrewMemberName },
			{ "releasedInstanceId", tostring(instanceId) },
			{ "releasedStorage", tostring(instanceData.StorageName or "") },
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
		syncAvailableCounts(player, crewMemberInventory)
		refreshCrewMemberShadow(player, "stand_release_failed")
		return nil, nil, "stand_clear_failed", debugInfo
	end

	syncAvailableCounts(player, crewMemberInventory)
	refreshCrewMemberShadow(player, "stand_release")

	crewPickupDebug(formatCrewPickupDebugFields({
		{ "event", "release_success" },
		{ "reason", "none" },
		{ "player", debugInfo.PlayerName },
		{ "userId", debugInfo.UserId },
		{ "stand", standName },
		{ "assignedName", debugInfo.AssignedCrewMemberName },
		{ "releasedInstanceId", tostring(instanceId) },
		{ "releasedStorage", tostring(instanceData.StorageName or "") },
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

	return tostring(instanceId), crewMemberInventory.ById[tostring(instanceId)], nil, debugInfo
end

function Module.RemoveAvailableInstance(player, storageName)
	local canonicalStorageName, info = resolveCanonicalCrewMemberId(storageName)
	if not info then
		warnInvalidCrewIdentity("inventory_remove", storageName, player)
		return nil, nil, "unknown_crew_member_id"
	end
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
	local crewMemberInventory = getCrewMemberInventory(player)
	local instanceId = nil
	local instanceData = nil

	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local candidate = crewMemberInventory.ById[tostring(orderedInstanceId)]
		if candidate and getInstanceCrewKey(candidate) == canonicalStorageName and candidate.AssignedStand == "" then
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

	crewMemberInventory.ById[tostring(instanceId)] = nil
	for index = #crewMemberInventory.Order, 1, -1 do
		if tostring(crewMemberInventory.Order[index]) == tostring(instanceId) then
			table.remove(crewMemberInventory.Order, index)
			break
		end
	end

	local saved, saveReason = saveCrewMemberInventory(player, crewMemberInventory, {
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
	syncAvailableCounts(player, crewMemberInventory)
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

	local crewMemberInventory = getCrewMemberInventory(player)
	local removedById = {}
	local removedIds = {}
	local clearedStandMap = {}

	for instanceId, instanceData in pairs(crewMemberInventory.ById) do
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
			crewMemberInventory.ById[normalizedId] = nil
		end
	end

	table.sort(removedIds, function(left, right)
		return (tonumber(left) or math.huge) < (tonumber(right) or math.huge)
	end)
	table.sort(removedStorageNames)

	for index = #crewMemberInventory.Order, 1, -1 do
		if removedById[tostring(crewMemberInventory.Order[index])] ~= nil then
			table.remove(crewMemberInventory.Order, index)
		end
	end

	for standName, standData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		if typeof(standData) == "table" then
			local standInstanceId = tostring(standData.CrewMemberInstanceId or "")
			local standCrewMemberName = tostring(standData.CrewMemberName or "")
			local clearByRemovedId = removedById[standInstanceId] ~= nil
			local clearByRemovedAssignedStand = clearedStandMap[tostring(standName)] == true
			local clearByStaleTutorialName = false
			if options.ClearStaleStorageAssignments == true and tutorialStorageNameSet[standCrewMemberName] == true then
				local existingInstance = if standInstanceId ~= "" then crewMemberInventory.ById[standInstanceId] else nil
				clearByStaleTutorialName = standInstanceId == "" or existingInstance == nil or existingInstance.TutorialReward == true
			end

			if clearByRemovedId or clearByRemovedAssignedStand or clearByStaleTutorialName then
				setStandData(player, standName, {
					CrewMemberName = "",
					CrewMemberInstanceId = "",
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
		local saved, saveReason = saveCrewMemberInventory(player, crewMemberInventory, {
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
		syncAvailableCounts(player, crewMemberInventory)
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

	if not CrewQuickSlotService.CanGainOrNotify(
		buyerPlayer,
		getInstanceCrewKey(instanceData),
		1,
		"TransferStandInstance:" .. tostring(standName)
	) then
		return nil, nil
	end

	local buyerInventory = getCrewMemberInventory(buyerPlayer)

	local _, _, ownerInventory = Module.GetInstance(ownerPlayer, instanceId)
	ownerInventory.ById[tostring(instanceId)] = nil
	for index = #ownerInventory.Order, 1, -1 do
		if tostring(ownerInventory.Order[index]) == tostring(instanceId) then
			table.remove(ownerInventory.Order, index)
			break
		end
	end
	saveCrewMemberInventory(ownerPlayer, ownerInventory)
	updateStandData(ownerPlayer, standName, {
		CrewMemberName = "",
		CrewMemberInstanceId = "",
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
	saveCrewMemberInventory(buyerPlayer, buyerInventory)
	syncAvailableCounts(buyerPlayer, buyerInventory)
	refreshCrewMemberShadow(buyerPlayer, "product_reward_transfer_in")

	return buyerInstanceId, buyerInventory.ById[buyerInstanceId]
end

Module.IsCrewInventoryEntry = Module.IsCrewMemberInventoryEntry
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
Module.RepairCanonicalCrewMemberState = Module.RepairCanonicalCrewState

return Module
