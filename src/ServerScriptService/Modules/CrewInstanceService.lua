local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(Modules:WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local VariantCfg = CrewCatalog.GetVariantConfig()
local CrewInventoryDerivedCache = require(script.Parent:WaitForChild("CrewInventoryDerivedCache"))
local CrewQuickSlotService = require(script.Parent:WaitForChild("CrewQuickSlotService"))
local CrewStandIncomeAuthority = require(script.Parent:WaitForChild("CrewStandIncomeAuthority"))
local GTRActionDiagnostics = require(script.Parent:WaitForChild("GTRActionDiagnostics"))
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
local CREW_MEMBER_INVENTORY_SCHEMA_VERSION = 2
local INVENTORY_AUTHORITY_SNAPSHOT_VERSION = 1
local CAPTAIN_SLOT_KEY = "Captain"
local HOTBAR_STORAGE_FULL_REASON = "crew_hotbar_and_storage_full"
-- Function names still carry legacy terms for callers, but normal gameplay now
-- reads and writes CrewMemberInventory. Legacy inventory roots are repair mirrors.

local CREW_PICKUP_DEBUG = false
local invalidCrewIdentityWarnings = {}

local function crewPickupDebug(message, ...)
	if CREW_PICKUP_DEBUG ~= true and game:GetAttribute("CrewPickupDebug") ~= true then
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

local function notifyInventorySaved(player, crewInventory, metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	local counters = metadata.Counters
	if typeof(counters) == "table" then
		counters.InventoryNotifyCount = (tonumber(counters.InventoryNotifyCount) or 0) + 1
	end

	CrewInventoryDerivedCache.MarkSaved(player, crewInventory, tostring(metadata.Reason or "inventory_saved"))
	for callback in pairs(inventorySavedCallbacks) do
		local ok, err = pcall(callback, player, crewInventory, metadata)
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

	local displayInfo = CrewCatalog.GetDisplayInfo(canonicalId, entry)
	local variantKey = tostring(displayInfo.Variant or "Normal")
	local baseName = tostring(displayInfo.BaseId or "")
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
		Rarity = tostring(entry.Rarity or info.Rarity or "Common"),
		Income = tonumber(info.Income or entry.Income) or 0,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
		DisplayName = firstNonEmpty(displayInfo.DisplayName, info.DisplayName, info.Name, entry.DisplayName, canonicalId, requestedStorageName),
		CrewMemberId = firstNonEmpty(info.CrewMemberId, canonicalId, requestedStorageName),
		RealCharacterName = firstNonEmpty(info.RealCharacterName),
		Arc = firstNonEmpty(info.Arc),
		ModelName = firstNonEmpty(info.ModelName, entry.ModelName, baseName),
	}
end

local function buildIncomeRollFields(rarity, variant, instanceData)
	local baseIncomeRoll, incomeRollVersion = CrewIncomeBalance.GetOrMigrateBaseIncome(
		rarity,
		typeof(instanceData) == "table" and instanceData.BaseIncomeRoll or nil,
		typeof(instanceData) == "table" and instanceData.IncomeRollVersion or nil
	)
	local income = CrewIncomeBalance.ComputeIncome(
		baseIncomeRoll,
		variant,
		typeof(instanceData) == "table" and instanceData.Level or nil,
		rarity
	)

	return baseIncomeRoll, income, incomeRollVersion
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

local PERF_THRESHOLD_SECONDS = 0.025

local function logPerf(player, phase, target, durationSeconds, result, extra)
	extra = if typeof(extra) == "table" then extra else {}
	if game:GetAttribute("GTRPerformanceDebug") ~= true and durationSeconds < PERF_THRESHOLD_SECONDS then
		return
	end

	print(string.format(
		"[GTR_PERF] phase=%s player=%s userId=%s target=%s durationMs=%.3f replicaWriteCount=%s result=%s reason=%s",
		tostring(phase or ""),
		player and player.Name or "unknown",
		tostring(player and player.UserId or 0),
		tostring(target or ""),
		durationSeconds * 1000,
		tostring(extra.ReplicaWriteCount or ""),
		tostring(result or "ok"),
		tostring(extra.Reason or "none")
	))
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

	local rarity = CrewIncomeBalance.NormalizeRarity(instanceData.Rarity or metadata.Rarity)
	local variant = CrewIncomeBalance.NormalizeVariant(metadata.Variant or instanceData.Variant)
	local baseIncomeRoll, income, incomeRollVersion = buildIncomeRollFields(rarity, variant, instanceData)
	local normalized = {
		InstanceId = tostring(instanceId),
		StorageName = metadata.StorageName,
		LegacyStorageName = metadata.LegacyStorageName,
		BaseName = metadata.BaseName,
		Variant = variant,
		Rarity = rarity,
		BaseIncomeRoll = baseIncomeRoll,
		IncomeRollVersion = incomeRollVersion,
		Income = income,
		Render = firstNonEmpty(metadata.Render, instanceData.Render),
		GoldenRender = firstNonEmpty(metadata.GoldenRender, instanceData.GoldenRender, metadata.Render),
		DiamondRender = firstNonEmpty(metadata.DiamondRender, instanceData.DiamondRender, metadata.Render),
		Level = CrewIncomeBalance.NormalizeLevel(instanceData.Level),
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
		Overflow = instanceData.Overflow == true,
		OverflowSource = tostring(instanceData.OverflowSource or ""),
		OverflowedAt = coerceNumber(instanceData.OverflowedAt, 0),
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
		local schemaVersion = CREW_MEMBER_INVENTORY_SCHEMA_VERSION
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

local function saveCrewMemberInventory(player, crewMemberInventory, options)
	options = if typeof(options) == "table" then options else {}
	local canonicalInventory = normalizeInventoryData(cloneValue(crewMemberInventory), {
		Canonical = true,
	})
	local ok, reason = writeProfileRoot(player, CANONICAL_INVENTORY_PATH, canonicalInventory)
	if ok ~= true then
		return false, "inventory_write_failed:CrewMemberInventory:" .. tostring(reason or "")
	end
	notifyInventorySaved(player, canonicalInventory, options.InventorySavedMetadata)
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

local function getCrewMemberInventoryReadOnly(player, inventoryOverride)
	if typeof(inventoryOverride) == "table" then
		return inventoryOverride
	end

	local dataManager = getDataManager()
	if typeof(dataManager.TryGetValue) == "function" then
		local rawInventory = dataManager:TryGetValue(player, CANONICAL_INVENTORY_PATH)
		if typeof(rawInventory) == "table" then
			return rawInventory
		end
	end

	if typeof(dataManager.TryGetProfile) == "function" then
		local profile = dataManager:TryGetProfile(player)
		if profile and typeof(profile.Data) == "table" and typeof(profile.Data[CANONICAL_INVENTORY_PATH]) == "table" then
			return profile.Data[CANONICAL_INVENTORY_PATH]
		end
	end

	return nil
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
		return false, "invalid_stand"
	end

	local shipSlots = getDataManager():GetValue(player, "Ship.Slots")
	if typeof(shipSlots) ~= "table" then
		return true, "missing_ship_slots"
	end

	shipSlots[standName] = nil
	local ok = getDataManager():SetValue(player, "Ship.Slots", shipSlots)
	return ok == true, if ok == true then nil else "ship_slots_write_failed"
end

local function restoreShipSlots(player, shipSlotsSnapshot)
	local nextSlots = if typeof(shipSlotsSnapshot) == "table" then cloneValue(shipSlotsSnapshot) else {}
	local ok = getDataManager():SetValue(player, "Ship.Slots", nextSlots)
	return ok == true, if ok == true then nil else "ship_slots_restore_failed"
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
		BaseIncomeRoll = overrides and overrides.BaseIncomeRoll or nil,
		IncomeRollVersion = overrides and overrides.IncomeRollVersion or nil,
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
	if not (overrides and overrides.DeferIndexDiscovery == true) then
		IndexCollectionService.MarkCrewMemberDiscovered(
			player,
			metadata.CrewMemberId,
			overrides and overrides.BaseName or metadata.BaseName,
			overrides and overrides.Variant or metadata.Variant,
			{
				DeferShadowRefresh = overrides and overrides.DeferIndexShadowRefresh == true,
			}
		)
	end

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
			return CrewIncomeBalance.NormalizeLevel(instanceData.Level),
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

local function failCrewSwitch(debugInfo, reason)
	reason = tostring(reason or "swap_commit_failed")
	debugInfo = if typeof(debugInfo) == "table" then debugInfo else {}
	debugInfo.Reason = reason
	if debugInfo.ActionTrace and typeof(debugInfo.ActionTrace.finish) == "function" then
		debugInfo.ActionTrace:finish("failed", {
			Target = tostring(debugInfo.StandName or ""),
			Reason = reason,
		})
		debugInfo.ActionTrace = nil
	end
	crewPickupDebug(formatCrewPickupDebugFields({
		{ "event", "switch_failed" },
		{ "reason", reason },
		{ "player", debugInfo.PlayerName or "" },
		{ "userId", debugInfo.UserId or "" },
		{ "stand", debugInfo.StandName or "" },
		{ "incomingInstanceId", debugInfo.IncomingInstanceId or "" },
		{ "incomingStorage", debugInfo.IncomingStorageName or "" },
		{ "incomingAssignedStand", debugInfo.IncomingAssignedStand or "" },
		{ "outgoingInstanceId", debugInfo.OutgoingInstanceId or "" },
		{ "outgoingStorage", debugInfo.OutgoingStorageName or "" },
		{ "outgoingAssignedStand", debugInfo.OutgoingAssignedStand or "" },
		{ "quickOccupied", debugInfo.QuickSlotOccupied or "" },
		{ "quickUnlocked", debugInfo.QuickSlotUnlocked or "" },
		{ "quickMax", debugInfo.QuickSlotMax or "" },
		{ "commitSaveOk", debugInfo.CommitSaveOk or "" },
		{ "standWriteOk", debugInfo.StandWriteOk or "" },
		{ "rollbackOk", debugInfo.RollbackOk or "" },
	}))
	return nil, nil, nil, nil, reason, debugInfo
end

local function findExistingStandInstance(crewMemberInventory, standName, standData)
	standName = tostring(standName or "")
	standData = if typeof(standData) == "table" then standData else {}

	local standInstanceId = tostring(standData.CrewMemberInstanceId or "")
	if standInstanceId ~= "" then
		local instanceData = crewMemberInventory.ById[standInstanceId]
		if typeof(instanceData) == "table" then
			if tostring(instanceData.AssignedStand or "") == standName then
				return standInstanceId, instanceData
			end
			return nil, nil, "ownership_mismatch"
		end
	end

	for _, orderedInstanceId in ipairs(crewMemberInventory.Order) do
		local instanceId = tostring(orderedInstanceId)
		local instanceData = crewMemberInventory.ById[instanceId]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == standName then
			return instanceId, instanceData
		end
	end

	if tostring(standData.CrewMemberName or "") ~= "" or standInstanceId ~= "" then
		return nil, nil, "outgoing_instance_missing"
	end

	return nil, nil, "outgoing_instance_missing"
end

local function getExpectedStorageName(options)
	options = if typeof(options) == "table" then options else {}
	local expected = tostring(options.ExpectedIncomingStorageName or options.StorageName or "")
	if expected == "" then
		return ""
	end

	local canonicalStorageName, info = resolveCanonicalCrewMemberId(expected)
	if not info then
		return ""
	end
	return canonicalStorageName
end

local function applyTutorialMetadataClear(instanceData)
	instanceData.TutorialReward = false
	instanceData.TutorialToken = ""
	instanceData.TutorialOwnerUserId = nil
	instanceData.TutorialCrewMember = nil
	instanceData.TutorialRewardName = nil
end

local function buildStandAssignmentRow(instanceId, instanceData)
	return {
		CrewMemberName = getInstanceCrewKey(instanceData),
		CrewMemberInstanceId = tostring(instanceId),
		IncomeToCollect = 0,
		LastAccruedAtUnix = os.time(),
		StandLevel = CrewIncomeBalance.NormalizeLevel(instanceData.Level),
	}
end

local function applyInventoryAndStandBatch(player, crewMemberInventory, standName, standUpdates, sourcePath)
	local canonicalInventory = normalizeInventoryData(cloneValue(crewMemberInventory), {
		Canonical = true,
	})
	local operations = {
		{
			Kind = "Set",
			Path = CANONICAL_INVENTORY_PATH,
			Value = canonicalInventory,
		},
		CrewStandIncomeAuthority.BuildStandSetOperation(player, standName, standUpdates),
	}
	local ok, result = getDataManager():TryApplyBatch(player, operations, {
		PerfContext = {
			Target = tostring(sourcePath or "crew_stand_batch"),
		},
	})
	if ok ~= true then
		return false, tostring(result and result.Reason or "batch_failed"), result
	end

	notifyInventorySaved(player, canonicalInventory)
	CrewStandIncomeAuthority.RecordExternalIncomeWrite(1)
	return true, nil, result
end

local function notifyHotbarAndStorageFull(player)
	if typeof(CrewQuickSlotService.NotifyHotbarAndStorageFull) == "function" then
		CrewQuickSlotService.NotifyHotbarAndStorageFull(player)
	else
		CrewQuickSlotService.NotifyFull(player)
	end
end

local function chooseReleasedCrewDestination(player, crewMemberInventory, storageAmount, quickSlotOptions)
	local quickSlotIndex, quickSlotResult = nil, nil
	if typeof(CrewQuickSlotService.GetFirstAvailableSlot) == "function" then
		quickSlotIndex, quickSlotResult = CrewQuickSlotService.GetFirstAvailableSlot(player, quickSlotOptions)
	end

	local storageOk, occupiedInstances, storageSlots, maxSlots, storageReason =
		CrewQuickSlotService.CanStoreInstances(player, crewMemberInventory, storageAmount)
	local unlockedSlots = CrewQuickSlotService.GetUnlockedSlots(player)
	local result = {
		QuickSlotIndex = quickSlotIndex,
		QuickSlotReason = tostring(quickSlotResult and quickSlotResult.Reason or ""),
		QuickSlotUnlocked = tonumber(quickSlotResult and quickSlotResult.UnlockedSlots) or unlockedSlots,
		QuickSlotMax = tonumber(quickSlotResult and quickSlotResult.MaxSlots) or CrewQuickSlotService.GetMaxSlots(player),
		StorageCanFit = storageOk == true,
		StorageOccupied = tonumber(occupiedInstances) or 0,
		StorageSlots = tonumber(storageSlots) or 0,
		StorageMax = tonumber(maxSlots) or 0,
		StorageReason = tostring(storageReason or ""),
	}

	if quickSlotIndex ~= nil then
		result.Destination = "Hotbar"
		result.Reason = "ok"
	elseif storageOk == true then
		result.Destination = "Stored"
		result.Reason = "ok"
	else
		result.Destination = "Blocked"
		result.Reason = HOTBAR_STORAGE_FULL_REASON
	end

	return result
end

local function applyReleasedCrewDestinationDebug(debugInfo, destination)
	if typeof(debugInfo) ~= "table" or typeof(destination) ~= "table" then
		return
	end

	debugInfo.ReleaseDestination = tostring(destination.Destination or "")
	debugInfo.ReleaseDestinationReason = tostring(destination.Reason or "")
	debugInfo.ReleaseQuickSlotIndex = tonumber(destination.QuickSlotIndex)
	debugInfo.QuickSlotOccupied = tonumber(destination.StorageOccupied) or 0
	debugInfo.QuickSlotUnlocked = tonumber(destination.QuickSlotUnlocked) or 0
	debugInfo.QuickSlotMax = tonumber(destination.QuickSlotMax) or 0
	debugInfo.StorageCanFit = destination.StorageCanFit == true
	debugInfo.StorageSlots = tonumber(destination.StorageSlots) or 0
	debugInfo.StorageReason = tostring(destination.StorageReason or "")
end

function Module.AssignTutorialRewardInstanceToStand(player, standName, filters)
	standName = tostring(standName or "")
	if standName == CAPTAIN_SLOT_KEY then
		return nil, nil, "captain_slot_not_numeric_stand"
	end

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
		StandLevel = CrewIncomeBalance.NormalizeLevel(instanceData.Level),
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

function Module.GetInstanceReadOnly(player, instanceRef, inventoryOverride)
	local crewMemberInventory = getCrewMemberInventoryReadOnly(player, inventoryOverride)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return nil, nil, crewMemberInventory
	end

	local instanceId = nil
	if typeof(instanceRef) == "table" then
		instanceId = tostring(instanceRef.InstanceId or "")
	else
		instanceId = tostring(instanceRef or "")
	end
	if instanceId == "" then
		return nil, nil, crewMemberInventory
	end

	local instanceData = crewMemberInventory.ById[instanceId]
	if typeof(instanceData) == "table" then
		return instanceId, instanceData, crewMemberInventory
	end

	return nil, nil, crewMemberInventory
end

function Module.GetInstanceState(player, instanceRef)
	local instanceId, instanceData, crewMemberInventory = Module.GetInstance(player, instanceRef)
	if not instanceData then
		return "Missing", nil, nil, crewMemberInventory
	end

	local assignedStand = tostring(instanceData.AssignedStand or "")
	if assignedStand ~= "" then
		return "Placed", instanceId, instanceData, crewMemberInventory, assignedStand
	end

	local assignedSlot = if typeof(CrewQuickSlotService.GetInstanceSlot) == "function"
		then CrewQuickSlotService.GetInstanceSlot(player, instanceId)
		else nil
	if assignedSlot ~= nil then
		return "Equipped", instanceId, instanceData, crewMemberInventory, assignedSlot
	end

	if instanceData.Overflow == true then
		return "Overflow", instanceId, instanceData, crewMemberInventory
	end

	return "Stored", instanceId, instanceData, crewMemberInventory
end

function Module.CountStoredInstances(player, crewMemberInventory)
	return CrewQuickSlotService.CountStoredInstances(player, crewMemberInventory or getCrewMemberInventory(player))
end

function Module.CanStoreInstances(player, crewMemberInventory, amount)
	return CrewQuickSlotService.CanStoreInstances(player, crewMemberInventory or getCrewMemberInventory(player), amount)
end

function Module.RemoveStoredInstanceById(player, instanceRef, options)
	options = if typeof(options) == "table" then options else {}
	local ready, readyReason = ensureInventoryAuthorityReady(player, "inventory_remove_exact")
	if ready ~= true then
		return nil, nil, tostring(readyReason or "inventory_authority_not_ready")
	end

	local state, instanceId, instanceData, crewMemberInventory = Module.GetInstanceState(player, instanceRef)
	if state == "Missing" then
		return nil, nil, "instance_missing"
	end
	if state ~= "Stored" then
		return nil, nil, "instance_not_stored:" .. tostring(state)
	end
	if options.AllowProtectedTutorialReward ~= true and isProtectedTutorialReward(player, instanceData) then
		return nil, nil, "protected_tutorial_reward"
	end

	crewMemberInventory.ById[tostring(instanceId)] = nil
	for index = #crewMemberInventory.Order, 1, -1 do
		if tostring(crewMemberInventory.Order[index]) == tostring(instanceId) then
			table.remove(crewMemberInventory.Order, index)
			break
		end
	end

	local saved, saveReason = saveCrewMemberInventory(player, crewMemberInventory, {
		SourcePath = tostring(options.SourcePath or "inventory_remove_exact"),
	})
	if saved ~= true then
		return nil, nil, tostring(saveReason or "inventory_authority_save_failed")
	end

	syncAvailableCounts(player, crewMemberInventory)
	refreshCrewMemberShadow(player, "inventory_remove_exact")
	return tostring(instanceId), instanceData
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

function Module.BuildProgressUpdate(player, instanceId, level, currentXP, options)
	options = if typeof(options) == "table" then options else {}
	local startedAt = os.clock()
	local progressionAuthorityEnabled = isProgressionWriteAuthorityEnabled()
	if progressionAuthorityEnabled == true then
		local ready, readyReason = ensureProgressionAuthorityReady(player, "progression_update")
		if ready ~= true then
			logPerf(player, "CrewInstanceService.UpdateProgress", instanceId, os.clock() - startedAt, "failed", {
				Reason = tostring(readyReason or "progression_authority_not_ready"),
			})
			return nil, nil, tostring(readyReason or "progression_authority_not_ready")
		end
	end

	local resolvedInstanceId, instanceData, crewMemberInventory = Module.GetInstance(player, instanceId)
	if not instanceData then
		logPerf(player, "CrewInstanceService.UpdateProgress", instanceId, os.clock() - startedAt, "failed", {
			Reason = "missing_instance",
		})
		return nil, nil, "missing_instance"
	end

	local nextInventory = cloneValue(crewMemberInventory)
	local nextData = cloneValue(instanceData)
	nextData.Level = CrewIncomeBalance.NormalizeLevel(coerceNumber(level, nextData.Level or 1))
	nextData.CurrentXP = math.max(0, math.floor(coerceNumber(currentXP, nextData.CurrentXP or 0)))
	local baseIncomeRoll, incomeRollVersion = CrewIncomeBalance.GetOrMigrateBaseIncome(
		nextData.Rarity,
		nextData.BaseIncomeRoll,
		nextData.IncomeRollVersion
	)
	nextData.BaseIncomeRoll = baseIncomeRoll
	nextData.Income = CrewIncomeBalance.ComputeIncome(
		baseIncomeRoll,
		nextData.Variant,
		nextData.Level,
		nextData.Rarity
	)
	nextData.IncomeRollVersion = incomeRollVersion
	if options.TotalXP ~= nil then
		nextData.TotalXP = math.max(0, math.floor(coerceNumber(options.TotalXP, nextData.TotalXP or 0)))
	end
	if options.Source ~= nil then
		nextData.Source = tostring(options.Source or "")
	end
	if options.DepthBand ~= nil then
		nextData.DepthBand = tostring(options.DepthBand or "")
	end
	if options.GrandLineRushStarter ~= nil then
		nextData.GrandLineRushStarter = options.GrandLineRushStarter == true
	end

	local normalizedData = normalizeInstanceData(resolvedInstanceId, nextData, nil, {
		Canonical = true,
	})
	if normalizedData == nil then
		logPerf(player, "CrewInstanceService.UpdateProgress", resolvedInstanceId, os.clock() - startedAt, "failed", {
			Reason = "unknown_crew_member_id",
		})
		return nil, nil, "unknown_crew_member_id"
	end

	nextInventory.ById[tostring(resolvedInstanceId)] = normalizedData
	nextInventory = normalizeInventoryData(nextInventory, {
		Canonical = true,
	})
	logPerf(player, "CrewInstanceService.UpdateProgress", resolvedInstanceId, os.clock() - startedAt, "ok")
	return normalizedData, nextInventory, nil, tostring(resolvedInstanceId)
end

function Module.NotifyInventorySaved(player, crewMemberInventory)
	notifyInventorySaved(player, crewMemberInventory)
end

function Module.UpdateProgress(player, instanceId, level, currentXP, options)
	options = if typeof(options) == "table" then options else {}
	local startedAt = os.clock()
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
			logPerf(player, "CrewInstanceService.UpdateProgress", instanceId, os.clock() - startedAt, "failed", {
				Reason = tostring(readyReason or "progression_authority_not_ready"),
			})
			return nil
		end
	end

	local resolvedInstanceId, instanceData, crewMemberInventory = Module.GetInstance(player, instanceId)
	if not instanceData then
		logPerf(player, "CrewInstanceService.UpdateProgress", instanceId, os.clock() - startedAt, "failed", {
			Reason = "missing_instance",
		})
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

	instanceData.Level = CrewIncomeBalance.NormalizeLevel(coerceNumber(level, instanceData.Level or 1))
	instanceData.CurrentXP = math.max(0, math.floor(coerceNumber(currentXP, instanceData.CurrentXP or 0)))
	local baseIncomeRoll, incomeRollVersion = CrewIncomeBalance.GetOrMigrateBaseIncome(
		instanceData.Rarity,
		instanceData.BaseIncomeRoll,
		instanceData.IncomeRollVersion
	)
	instanceData.BaseIncomeRoll = baseIncomeRoll
	instanceData.Income = CrewIncomeBalance.ComputeIncome(
		baseIncomeRoll,
		instanceData.Variant,
		instanceData.Level,
		instanceData.Rarity
	)
	instanceData.IncomeRollVersion = incomeRollVersion
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
		logPerf(player, "CrewInstanceService.UpdateProgress", resolvedInstanceId, os.clock() - startedAt, "failed", {
			Reason = tostring(saveReason or "progression_save_failed"),
		})
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
			logPerf(player, "CrewInstanceService.UpdateProgress", resolvedInstanceId, os.clock() - startedAt, "failed", {
				Reason = "progression_shadow_projection_failed",
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
			logPerf(player, "CrewInstanceService.UpdateProgress", resolvedInstanceId, os.clock() - startedAt, "failed", {
				Reason = "progression_post_validation_failed",
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

	logPerf(player, "CrewInstanceService.UpdateProgress", resolvedInstanceId, os.clock() - startedAt, "ok")
	return updated
end

function Module.GetStandInstanceId(player, standName)
	standName = tostring(standName or "")
	if standName == CAPTAIN_SLOT_KEY then
		return ""
	end

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

function Module.GetStandInstanceIdReadOnly(player, standName, inventoryOverride)
	standName = tostring(standName or "")
	if standName == "" or standName == CAPTAIN_SLOT_KEY then
		return ""
	end

	local standData = getStandData(player, standName)
	local rawInstanceId = tostring(standData and standData.CrewMemberInstanceId or "")
	if rawInstanceId == "" then
		return ""
	end

	local instanceId, instanceData = Module.GetInstanceReadOnly(player, rawInstanceId, inventoryOverride)
	if typeof(instanceData) ~= "table" then
		return ""
	end

	return tostring(instanceId or rawInstanceId)
end

function Module.EnsureStandInstance(player, standName, fallbackStorageName)
	standName = tostring(standName or "")
	if standName == CAPTAIN_SLOT_KEY then
		return nil, nil
	end

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
			StandLevel = CrewIncomeBalance.NormalizeLevel(standData.StandLevel),
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
	if standName == CAPTAIN_SLOT_KEY then
		return false, "captain_slot_not_numeric_stand"
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
			StandLevel = CrewIncomeBalance.NormalizeLevel(assignedInstanceData.Level),
		}, "stand_identity_repair")
		refreshCrewMemberShadow(player, "stand_identity_repair")
	end

	if standCrewMemberName == canonicalCrewMemberId and standInstanceId == assignedInstanceId then
		return true, "in_sync", assignedInstanceId, assignedInstanceData
	end

	local standOk, standReason = updateStandData(player, standName, {
		CrewMemberName = canonicalCrewMemberId,
		CrewMemberInstanceId = assignedInstanceId,
		StandLevel = CrewIncomeBalance.NormalizeLevel(assignedInstanceData.Level),
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
			if assignedStand ~= "" and assignedStand ~= CAPTAIN_SLOT_KEY then
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
	warn(string.format(
		"[CrewInstanceService] rejected legacy name-based crew lookup player=%s storage=%s",
		player and player.Name or "unknown",
		tostring(storageName)
	))
	return nil, nil, getCrewMemberInventory(player)
end

function Module.AssignAvailableInstanceToStand(_player, _storageName, _standName)
	return nil, nil, "exact_instance_required"
end

function Module.AssignInstanceToStand(player, instanceRef, standName, options)
	options = if typeof(options) == "table" then options else {}
	standName = tostring(standName or "")
	local actionTrace = GTRActionDiagnostics.Start("CrewPlace", player, {
		Target = standName,
	})
	local function fail(reason)
		actionTrace:finish("failed", {
			Target = standName,
			Reason = tostring(reason or "unknown"),
		})
		return nil, nil, tostring(reason or "unknown")
	end
	if standName == "" then
		return fail("invalid_stand")
	end
	if standName == CAPTAIN_SLOT_KEY then
		return fail("captain_slot_not_numeric_stand")
	end

	local ready, readyReason = ensureInventoryAuthorityReady(player, "stand_place_exact")
	if ready ~= true then
		return fail(tostring(readyReason or "inventory_authority_not_ready"))
	end

	local instanceId, instanceData, crewMemberInventory = Module.GetInstance(player, instanceRef)
	if not instanceData then
		return fail("incoming_instance_missing")
	end

	local expectedStorageName = getExpectedStorageName(options)
	if expectedStorageName ~= "" and getInstanceCrewKey(instanceData) ~= expectedStorageName then
		return fail("ownership_mismatch")
	end

	if tostring(instanceData.AssignedStand or "") ~= "" then
		return fail("incoming_already_assigned")
	end
	if instanceData.Overflow == true then
		return fail("incoming_instance_overflow")
	end

	local occupied, occupancyReason = getStandOccupancy(player, standName, crewMemberInventory)
	if occupied then
		return fail(occupancyReason)
	end

	local previousQuickSlot = if typeof(CrewQuickSlotService.GetInstanceSlot) == "function"
		then CrewQuickSlotService.GetInstanceSlot(player, instanceId)
		else nil
	if previousQuickSlot ~= nil and typeof(CrewQuickSlotService.ClearAssignmentsForInstance) == "function" then
		local clearOk, clearResult = CrewQuickSlotService.ClearAssignmentsForInstance(player, instanceId)
		if clearOk ~= true then
			return fail(tostring(clearResult and clearResult.Reason or "quick_slot_clear_failed"))
		end
	end

	local originalInstanceData = cloneValue(instanceData)
	local committedInstanceData = cloneValue(instanceData)
	committedInstanceData.AssignedStand = standName
	if options.ClearTutorialMetadataAfterAssign == true then
		applyTutorialMetadataClear(committedInstanceData)
	end
	crewMemberInventory.ById[tostring(instanceId)] = committedInstanceData

	local batchOk, batchReason, batchResult = applyInventoryAndStandBatch(
		player,
		crewMemberInventory,
		standName,
		buildStandAssignmentRow(instanceId, committedInstanceData),
		"stand_place_exact"
	)
	actionTrace:phase("mutate", {
		Target = standName,
		WriteCount = batchResult and batchResult.WriteCount or batchResult and batchResult.ReplicaWriteCount or 0,
		Result = if batchOk then "ok" else "failed",
		Reason = batchReason,
	})
	if batchOk ~= true then
		crewMemberInventory.ById[tostring(instanceId)] = originalInstanceData
		if previousQuickSlot ~= nil and typeof(CrewQuickSlotService.AssignInstanceToSlot) == "function" then
			CrewQuickSlotService.AssignInstanceToSlot(player, instanceId, previousQuickSlot)
		end
		return fail(tostring(batchReason or "assignment_batch_failed"))
	end

	syncAvailableCounts(player, crewMemberInventory)
	refreshCrewMemberShadow(player, "stand_place_exact")
	actionTrace:finish("ok", {
		Target = standName,
		WriteCount = batchResult and batchResult.WriteCount or batchResult and batchResult.ReplicaWriteCount or 0,
	})

	return tostring(instanceId), crewMemberInventory.ById[tostring(instanceId)]
end

function Module.SwapStandInstance(player, standName, incomingInstanceRef, options)
	options = if typeof(options) == "table" then options else {}
	standName = tostring(standName or "")
	local debugInfo = {
		PlayerName = player and player.Name or "unknown",
		UserId = player and player.UserId or 0,
		StandName = standName,
		IncomingInstanceId = if typeof(incomingInstanceRef) == "table"
			then tostring(incomingInstanceRef.InstanceId or "")
			else tostring(incomingInstanceRef or ""),
	}
	debugInfo.ActionTrace = GTRActionDiagnostics.Start("CrewSwap", player, {
		Target = standName,
	})

	if standName == "" then
		return failCrewSwitch(debugInfo, "invalid_stand")
	end
	if standName == CAPTAIN_SLOT_KEY then
		return failCrewSwitch(debugInfo, "captain_slot_not_numeric_stand")
	end
	if debugInfo.IncomingInstanceId == "" then
		return failCrewSwitch(debugInfo, "incoming_instance_missing")
	end

	local ready, readyReason = ensureInventoryAuthorityReady(player, "stand_swap")
	if ready ~= true then
		return failCrewSwitch(debugInfo, tostring(readyReason or "swap_commit_failed"))
	end

	local standData = getStandData(player, standName)
	if tostring(standData.CrewMemberName or "") == "" and tostring(standData.CrewMemberInstanceId or "") == "" then
		return failCrewSwitch(debugInfo, "outgoing_instance_missing")
	end

	local incomingInstanceId, incomingInstanceData, crewMemberInventory = Module.GetInstance(player, debugInfo.IncomingInstanceId)
	if not incomingInstanceData then
		return failCrewSwitch(debugInfo, "incoming_instance_missing")
	end

	debugInfo.IncomingInstanceId = tostring(incomingInstanceId)
	debugInfo.IncomingStorageName = getInstanceCrewKey(incomingInstanceData)
	debugInfo.IncomingAssignedStand = tostring(incomingInstanceData.AssignedStand or "")

	local expectedStorageName = getExpectedStorageName(options)
	if expectedStorageName ~= "" and debugInfo.IncomingStorageName ~= expectedStorageName then
		return failCrewSwitch(debugInfo, "ownership_mismatch")
	end

	if tostring(incomingInstanceData.AssignedStand or "") ~= "" then
		return failCrewSwitch(debugInfo, "incoming_already_assigned")
	end
	if incomingInstanceData.Overflow == true then
		return failCrewSwitch(debugInfo, "incoming_instance_overflow")
	end

	local outgoingInstanceId, outgoingInstanceData, outgoingReason =
		findExistingStandInstance(crewMemberInventory, standName, standData)
	if not outgoingInstanceData then
		return failCrewSwitch(debugInfo, outgoingReason or "outgoing_instance_missing")
	end

	debugInfo.OutgoingInstanceId = tostring(outgoingInstanceId)
	debugInfo.OutgoingStorageName = getInstanceCrewKey(outgoingInstanceData)
	debugInfo.OutgoingAssignedStand = tostring(outgoingInstanceData.AssignedStand or "")

	if tostring(outgoingInstanceId) == tostring(incomingInstanceId) then
		return failCrewSwitch(debugInfo, "incoming_already_assigned")
	end

	local previousQuickSlot = if typeof(CrewQuickSlotService.GetInstanceSlot) == "function"
		then CrewQuickSlotService.GetInstanceSlot(player, incomingInstanceId)
		else nil
	if previousQuickSlot ~= nil and typeof(CrewQuickSlotService.ClearAssignmentsForInstance) == "function" then
		local clearOk, clearResult = CrewQuickSlotService.ClearAssignmentsForInstance(player, incomingInstanceId)
		if clearOk ~= true then
			return failCrewSwitch(debugInfo, tostring(clearResult and clearResult.Reason or "quick_slot_clear_failed"))
		end
	end
	local function restoreIncomingQuickSlot()
		if previousQuickSlot ~= nil and typeof(CrewQuickSlotService.AssignInstanceToSlot) == "function" then
			CrewQuickSlotService.AssignInstanceToSlot(player, incomingInstanceId, previousQuickSlot)
		end
	end

	local finalInventory = cloneValue(crewMemberInventory)
	local finalIncoming = cloneValue(incomingInstanceData)
	local finalOutgoing = cloneValue(outgoingInstanceData)
	finalIncoming.AssignedStand = standName
	if options.ClearIncomingTutorialMetadataAfterAssign == true then
		applyTutorialMetadataClear(finalIncoming)
	end
	finalOutgoing.AssignedStand = ""
	finalOutgoing.LastReleasedAt = os.time()
	finalInventory.ById[tostring(incomingInstanceId)] = finalIncoming
	finalInventory.ById[tostring(outgoingInstanceId)] = finalOutgoing
	moveInstanceToFront(finalInventory, outgoingInstanceId)

	local outgoingDestination = chooseReleasedCrewDestination(player, finalInventory, 0, {
		IgnoreInstanceId = incomingInstanceId,
	})
	applyReleasedCrewDestinationDebug(debugInfo, outgoingDestination)
	debugInfo.OutgoingDestination = tostring(outgoingDestination.Destination or "")
	debugInfo.OutgoingQuickSlotIndex = tonumber(outgoingDestination.QuickSlotIndex)
	if outgoingDestination.Destination == "Blocked" then
		notifyHotbarAndStorageFull(player)
		restoreIncomingQuickSlot()
		return failCrewSwitch(debugInfo, HOTBAR_STORAGE_FULL_REASON)
	end

	local saveOk, saveReason = saveCrewMemberInventory(player, finalInventory, {
		SourcePath = "stand_swap",
	})
	debugInfo.CommitSaveOk = saveOk == true
	debugInfo.CommitSaveReason = tostring(saveReason or "")
	if saveOk ~= true then
		restoreIncomingQuickSlot()
		return failCrewSwitch(debugInfo, "swap_commit_failed")
	end

	if outgoingDestination.Destination == "Hotbar" then
		local assignOk, assignResult =
			CrewQuickSlotService.AssignInstanceToSlot(player, outgoingInstanceId, outgoingDestination.QuickSlotIndex)
		debugInfo.OutgoingQuickSlotAssignOk = assignOk == true
		debugInfo.OutgoingQuickSlotAssignReason = tostring(assignResult and assignResult.Reason or "")
		debugInfo.OutgoingQuickSlotIndex = tonumber(assignResult and assignResult.SlotIndex)
			or tonumber(outgoingDestination.QuickSlotIndex)
		if assignOk ~= true then
			local rollbackOk, rollbackReason = saveCrewMemberInventory(player, crewMemberInventory, {
				SourcePath = "stand_swap_quick_slot_rollback",
			})
			debugInfo.RollbackOk = rollbackOk == true
			debugInfo.RollbackReason = tostring(rollbackReason or "")
			CrewQuickSlotService.ClearAssignmentsForInstance(player, outgoingInstanceId)
			restoreIncomingQuickSlot()
			syncAvailableCounts(player, crewMemberInventory)
			refreshCrewMemberShadow(player, "stand_swap_quick_slot_failed")
			return failCrewSwitch(debugInfo, "quick_slot_assign_failed")
		end
	else
		debugInfo.OutgoingQuickSlotAssignOk = false
	end

	local standOk, standReason = updateStandData(
		player,
		standName,
		buildStandAssignmentRow(incomingInstanceId, finalIncoming),
		"stand_swap"
	)
	debugInfo.StandWriteOk = standOk == true
	debugInfo.StandWriteReason = tostring(standReason or "")
	if standOk ~= true then
		local rollbackOk, rollbackReason = saveCrewMemberInventory(player, crewMemberInventory, {
			SourcePath = "stand_swap_rollback",
		})
		debugInfo.RollbackOk = rollbackOk == true
		debugInfo.RollbackReason = tostring(rollbackReason or "")
		if outgoingDestination.Destination == "Hotbar" then
			CrewQuickSlotService.ClearAssignmentsForInstance(player, outgoingInstanceId)
		end
		local standRestoreOk, standRestoreReason = updateStandData(
			player,
			standName,
			buildStandAssignmentRow(outgoingInstanceId, outgoingInstanceData),
			"stand_swap_rollback"
		)
		debugInfo.StandRestoreOk = standRestoreOk == true
		debugInfo.StandRestoreReason = tostring(standRestoreReason or "")
		restoreIncomingQuickSlot()
		return failCrewSwitch(debugInfo, "swap_commit_failed")
	end

	syncAvailableCounts(player, finalInventory)
	refreshCrewMemberShadow(player, "stand_swap")

	crewPickupDebug(formatCrewPickupDebugFields({
		{ "event", "switch_success" },
		{ "player", debugInfo.PlayerName },
		{ "userId", debugInfo.UserId },
		{ "stand", standName },
		{ "incomingInstanceId", tostring(incomingInstanceId) },
		{ "incomingStorage", getInstanceCrewKey(finalIncoming) },
		{ "outgoingInstanceId", tostring(outgoingInstanceId) },
		{ "outgoingStorage", getInstanceCrewKey(finalOutgoing) },
		{ "outgoingDestination", debugInfo.OutgoingDestination },
		{ "outgoingQuickSlot", debugInfo.OutgoingQuickSlotIndex or "" },
		{ "quickOccupied", debugInfo.QuickSlotOccupied },
		{ "quickUnlocked", debugInfo.QuickSlotUnlocked },
	}))
	if debugInfo.ActionTrace then
		debugInfo.ActionTrace:finish("ok", {
			Target = standName,
		})
		debugInfo.ActionTrace = nil
	end

	return tostring(incomingInstanceId),
		finalInventory.ById[tostring(incomingInstanceId)],
		tostring(outgoingInstanceId),
		finalInventory.ById[tostring(outgoingInstanceId)],
		nil,
		debugInfo
end

local function removeInstanceFromInventory(crewMemberInventory, instanceId)
	instanceId = tostring(instanceId or "")
	if instanceId == "" or typeof(crewMemberInventory) ~= "table" then
		return
	end

	if typeof(crewMemberInventory.ById) == "table" then
		crewMemberInventory.ById[instanceId] = nil
	end
	if typeof(crewMemberInventory.Order) == "table" then
		for index = #crewMemberInventory.Order, 1, -1 do
			if tostring(crewMemberInventory.Order[index]) == instanceId then
				table.remove(crewMemberInventory.Order, index)
				break
			end
		end
	end
end

local function incrementCounter(counters, key, amount)
	if typeof(counters) ~= "table" then
		return
	end
	counters[key] = (tonumber(counters[key]) or 0) + (tonumber(amount) or 1)
end

local function countStoredInstancesWithAssignments(crewMemberInventory, assignments)
	if typeof(crewMemberInventory) ~= "table" or typeof(crewMemberInventory.ById) ~= "table" then
		return 0
	end

	local assignedSet = {}
	for _, instanceId in pairs(if typeof(assignments) == "table" then assignments else {}) do
		local normalized = tostring(instanceId or "")
		if normalized ~= "" then
			assignedSet[normalized] = true
		end
	end

	local count = 0
	for rawInstanceId, instanceData in pairs(crewMemberInventory.ById) do
		local instanceId = tostring(instanceData and instanceData.InstanceId or rawInstanceId or "")
		if
			instanceId ~= ""
			and typeof(instanceData) == "table"
			and tostring(instanceData.AssignedStand or "") == ""
			and instanceData.Overflow ~= true
			and assignedSet[instanceId] ~= true
		then
			count += 1
		end
	end
	return count
end

local function buildIndexDiscoveryOperation(player, instanceData, seenPaths)
	if typeof(instanceData) ~= "table" then
		return nil
	end

	local itemId = IndexCollectionService.ResolveCrewMemberItemId(
		getInstanceCrewKey(instanceData),
		tostring(instanceData.BaseName or ""),
		tostring(instanceData.Variant or "Normal")
	)
	if not itemId then
		return nil
	end

	local path = "IndexCollection.CrewMembers." .. tostring(itemId)
	if seenPaths[path] == true then
		return nil
	end
	seenPaths[path] = true

	local currentValue = getDataManager():TryGetValue(player, path)
	if currentValue == true then
		return nil
	end

	return {
		Kind = "Set",
		Path = path,
		Value = true,
	}
end

local ADMIN_FILL_SHIP_INVENTORY_READ_TIMEOUT_SECONDS = 3
local ADMIN_FILL_SHIP_INVENTORY_READ_RETRY_SECONDS = 0.1

local function getAdminFillShipBulkPlayerLabel(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return "unknown(0)"
	end
	return string.format("%s(%d)", player.Name, player.UserId)
end

local function isAdminFillShipBulkCancelled(cancelToken)
	return typeof(cancelToken) == "table" and cancelToken.Cancelled == true
end

local function readAdminFillShipBulkInventory(player, timeoutSeconds)
	local dataManager = getDataManager()
	local startedAt = os.clock()
	local timeout = math.max(0.1, tonumber(timeoutSeconds) or ADMIN_FILL_SHIP_INVENTORY_READ_TIMEOUT_SECONDS)
	local deadline = startedAt + timeout
	local lastReason = nil

	while os.clock() <= deadline do
		if typeof(dataManager.TryGetValue) == "function" then
			local value, reason = dataManager:TryGetValue(player, CANONICAL_INVENTORY_PATH)
			if typeof(value) == "table" then
				return value, nil, os.clock() - startedAt
			end
			lastReason = tostring(reason or "inventory_missing")
		elseif typeof(dataManager.IsReady) ~= "function" then
			lastReason = "try_get_value_unavailable"
		elseif dataManager:IsReady(player) ~= true then
			lastReason = "data_manager_not_ready"
		else
			local ok, valueOrErr = pcall(function()
				return dataManager:GetValue(player, CANONICAL_INVENTORY_PATH)
			end)
			if ok and typeof(valueOrErr) == "table" then
				return valueOrErr, nil, os.clock() - startedAt
			end
			lastReason = if ok then "inventory_missing" else tostring(valueOrErr)
		end

		local remaining = deadline - os.clock()
		if remaining <= 0 then
			break
		end
		task.wait(math.min(ADMIN_FILL_SHIP_INVENTORY_READ_RETRY_SECONDS, remaining))
	end

	return nil, tostring(lastReason or "inventory_read_timeout"), os.clock() - startedAt
end

function Module.ApplyAdminFillShipBulk(player, requests, options)
	options = if typeof(options) == "table" then options else {}
	requests = if typeof(requests) == "table" then requests else {}
	local counters = if typeof(options.Counters) == "table" then options.Counters else {}
	local sourcePath = tostring(options.SourcePath or "admin_fill_ship_bulk")
	local cancelToken = if typeof(options.CancelToken) == "table" then options.CancelToken else nil

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {
			Success = false,
			Changed = false,
			Reason = "invalid_player",
			Counters = counters,
		}
	end
	if #requests <= 0 then
		return {
			Success = true,
			Changed = false,
			Reason = "no_requests",
			Counters = counters,
			Created = {},
			Failures = {},
			Skipped = {},
		}
	end

	if isAdminFillShipBulkCancelled(cancelToken) then
		return {
			Success = false,
			Changed = false,
			Reason = "cancelled",
			Counters = counters,
			Created = {},
			Failures = { "cancelled:before_inventory_read" },
			Skipped = {},
		}
	end

	local ready, readyReason = ensureInventoryAuthorityReady(player, sourcePath)
	if ready ~= true then
		return {
			Success = false,
			Changed = false,
			Reason = tostring(readyReason or "inventory_authority_not_ready"),
			Counters = counters,
		}
	end

	local rawInventory, readReason, readDuration =
		readAdminFillShipBulkInventory(player, options.InventoryReadTimeoutSeconds)
	local readDurationMs = math.floor((tonumber(readDuration) or 0) * 1000 + 0.5)
	if typeof(rawInventory) ~= "table" then
		warn(string.format(
			"[AdminFillShip] inventory_read_failed target=%s source=%s reason=%s durationMs=%d timeoutSeconds=%s",
			getAdminFillShipBulkPlayerLabel(player),
			sourcePath,
			tostring(readReason or "unknown"),
			readDurationMs,
			tostring(options.InventoryReadTimeoutSeconds or ADMIN_FILL_SHIP_INVENTORY_READ_TIMEOUT_SECONDS)
		))
		return {
			Success = false,
			Changed = false,
			Reason = "inventory_read_failed:" .. tostring(readReason or "unknown"),
			Counters = counters,
			Created = {},
			Failures = { "inventory_read:" .. tostring(readReason or "unknown") },
			Skipped = {},
		}
	end
	print(string.format(
		"[AdminFillShip] inventory_read_ok target=%s source=%s durationMs=%d",
		getAdminFillShipBulkPlayerLabel(player),
		sourcePath,
		readDurationMs
	))

	local finalInventory = normalizeInventoryData(cloneValue(rawInventory), {
		Canonical = true,
	})
	local createdRecords = {}
	local standRows = {}
	local failures = {}
	local skipped = {}
	local filled = 0
	local replaced = 0
	local now = os.time()
	local quickAssignments = if typeof(CrewQuickSlotService.GetAssignments) == "function"
		then CrewQuickSlotService.GetAssignments(player)
		else {}
	local quickUnlockedSlots = if typeof(CrewQuickSlotService.GetUnlockedSlots) == "function"
		then CrewQuickSlotService.GetUnlockedSlots(player)
		else 0
	local quickAssignmentsChanged = false

	local function clearQuickAssignment(instanceId)
		instanceId = tostring(instanceId or "")
		if instanceId == "" then
			return
		end
		for slotKey, assignedInstanceId in pairs(quickAssignments) do
			if tostring(assignedInstanceId or "") == instanceId then
				quickAssignments[slotKey] = nil
				quickAssignmentsChanged = true
			end
		end
	end

	local function assignReleasedToQuickSlot(instanceId)
		instanceId = tostring(instanceId or "")
		if instanceId == "" then
			return false
		end

		clearQuickAssignment(instanceId)
		for index = 1, quickUnlockedSlots do
			local slotKey = tostring(index)
			if tostring(quickAssignments[slotKey] or "") == "" then
				quickAssignments[slotKey] = instanceId
				quickAssignmentsChanged = true
				return true
			end
		end
		return false
	end

	for _, request in ipairs(requests) do
		if typeof(request) ~= "table" then
			failures[#failures + 1] = "invalid_request"
			continue
		end

		local slotName = tostring(request.SlotName or request.StandName or "")
		if slotName == "" then
			failures[#failures + 1] = "?:invalid_stand"
			continue
		end
		if slotName == CAPTAIN_SLOT_KEY then
			failures[#failures + 1] = slotName .. ":captain_slot_not_numeric_stand"
			continue
		end

		local fillMode = tostring(request.FillMode or options.FillMode or "EmptyOnly")
		local occupied = getStandOccupancy(player, slotName, finalInventory)
		if fillMode ~= "ReplaceAll" and occupied then
			skipped[#skipped + 1] = slotName .. ":occupied"
			continue
		end

		local descriptor = if typeof(request.Descriptor) == "table" then request.Descriptor else {}
		local overrides = if typeof(descriptor.InstanceOverrides) == "table"
			then cloneValue(descriptor.InstanceOverrides)
			elseif typeof(request.InstanceOverrides) == "table" then cloneValue(request.InstanceOverrides)
			else {}
		overrides.DeferIndexShadowRefresh = true
		overrides.DeferIndexDiscovery = true

		local storageName = tostring(descriptor.CrewMemberName or request.CrewMemberName or overrides.StorageName or "")
		if storageName == "" then
			failures[#failures + 1] = slotName .. ":missing_crew_member"
			continue
		end

		local expectedStorageName = getExpectedStorageName({
			ExpectedIncomingStorageName = request.ExpectedIncomingStorageName or descriptor.CrewMemberName or storageName,
		})
		local incomingId, incomingData, createReason =
			createInstanceInternal(player, finalInventory, storageName, overrides)
		if not incomingData then
			failures[#failures + 1] = slotName .. ":" .. tostring(createReason or "create_instance_failed")
			continue
		end

		if expectedStorageName ~= "" and getInstanceCrewKey(incomingData) ~= expectedStorageName then
			removeInstanceFromInventory(finalInventory, incomingId)
			failures[#failures + 1] = slotName .. ":ownership_mismatch"
			continue
		end

		if fillMode == "ReplaceAll" and occupied then
			local standData = getStandData(player, slotName)
			local outgoingId, outgoingData, outgoingReason =
				findExistingStandInstance(finalInventory, slotName, standData)
			if not outgoingData then
				removeInstanceFromInventory(finalInventory, incomingId)
				failures[#failures + 1] = slotName .. ":" .. tostring(outgoingReason or "outgoing_instance_missing")
				continue
			end
			if tostring(outgoingId) == tostring(incomingId) then
				removeInstanceFromInventory(finalInventory, incomingId)
				failures[#failures + 1] = slotName .. ":incoming_already_assigned"
				continue
			end

			local finalOutgoing = cloneValue(outgoingData)
			finalOutgoing.AssignedStand = ""
			finalOutgoing.LastReleasedAt = now
			finalInventory.ById[tostring(outgoingId)] = finalOutgoing
			moveInstanceToFront(finalInventory, outgoingId)
			assignReleasedToQuickSlot(outgoingId)
			replaced += 1
		elseif occupied then
			removeInstanceFromInventory(finalInventory, incomingId)
			failures[#failures + 1] = slotName .. ":stand_occupied"
			continue
		end

		incomingData.AssignedStand = slotName
		finalInventory.ById[tostring(incomingId)] = incomingData
		standRows[#standRows + 1] = {
			SlotName = slotName,
			Updates = buildStandAssignmentRow(incomingId, incomingData),
		}
		createdRecords[#createdRecords + 1] = {
			InstanceId = tostring(incomingId),
			SlotName = slotName,
			CrewMemberName = getInstanceCrewKey(incomingData),
			Rarity = tostring(incomingData.Rarity or ""),
			Variant = tostring(incomingData.Variant or ""),
			BaseName = tostring(incomingData.BaseName or ""),
		}
		filled += 1
	end

	if filled <= 0 then
		return {
			Success = #failures == 0,
			Changed = false,
			Reason = if #failures == 0 then "no_slots_filled" else "no_slots_filled_with_failures",
			Counters = counters,
			Created = createdRecords,
			Failures = failures,
			Skipped = skipped,
			Filled = filled,
			Replaced = replaced,
		}
	end

	local occupiedInstances = countStoredInstancesWithAssignments(finalInventory, quickAssignments)
	local storageSlots = if typeof(CrewQuickSlotService.GetInventoryStorageSlots) == "function"
		then CrewQuickSlotService.GetInventoryStorageSlots(player)
		else 0
	local canFit = occupiedInstances <= storageSlots
	local storageReason = if canFit then "ok" else "crew_inventory_full"
	if canFit ~= true then
		return {
			Success = false,
			Changed = false,
			Reason = tostring(storageReason or "crew_inventory_full"),
			Counters = counters,
			Created = {},
			Failures = {
				string.format(
					"capacity:%s occupied=%s storageSlots=%s maxSlots=%s",
					tostring(storageReason or "crew_inventory_full"),
					tostring(occupiedInstances),
					tostring(storageSlots),
					tostring(storageSlots)
				),
			},
			Skipped = skipped,
			Filled = 0,
			Replaced = 0,
		}
	end

	local canonicalInventory = normalizeInventoryData(cloneValue(finalInventory), {
		Canonical = true,
	})
	local operations = {
		{
			Kind = "Set",
			Path = CANONICAL_INVENTORY_PATH,
			Value = canonicalInventory,
		},
	}
	local seenPaths = {
		[CANONICAL_INVENTORY_PATH] = true,
	}
	for _, standRow in ipairs(standRows) do
		local operation = CrewStandIncomeAuthority.BuildStandSetOperation(player, standRow.SlotName, standRow.Updates)
		if seenPaths[operation.Path] ~= true then
			seenPaths[operation.Path] = true
			operations[#operations + 1] = operation
		end
	end
	if quickAssignmentsChanged == true then
		local quickSlotPath = "CrewMemberQuickSlots.Assignments"
		seenPaths[quickSlotPath] = true
		operations[#operations + 1] = {
			Kind = "Set",
			Path = quickSlotPath,
			Value = quickAssignments,
		}
	end
	for _, createdRecord in ipairs(createdRecords) do
		local instanceData = canonicalInventory.ById[tostring(createdRecord.InstanceId)]
		local operation = buildIndexDiscoveryOperation(player, instanceData, seenPaths)
		if operation then
			operations[#operations + 1] = operation
		end
	end

	if isAdminFillShipBulkCancelled(cancelToken) then
		warn(string.format(
			"[AdminFillShip] bulk_commit_cancelled target=%s source=%s filled=%d replaced=%d",
			getAdminFillShipBulkPlayerLabel(player),
			sourcePath,
			filled,
			replaced
		))
		return {
			Success = false,
			Changed = false,
			Reason = "cancelled",
			Counters = counters,
			Created = {},
			Failures = { "cancelled:before_bulk_commit" },
			Skipped = skipped,
			Filled = 0,
			Replaced = 0,
		}
	end

	print(string.format(
		"[AdminFillShip] bulk_commit_begin target=%s source=%s operations=%d filled=%d replaced=%d created=%d",
		getAdminFillShipBulkPlayerLabel(player),
		sourcePath,
		#operations,
		filled,
		replaced,
		#createdRecords
	))
	local ok, batchResult = getDataManager():TryApplyBatch(player, operations, {
		PerfContext = {
			Target = sourcePath,
		},
	})
	if ok ~= true then
		warn(string.format(
			"[AdminFillShip] bulk_commit_failed target=%s source=%s operations=%d reason=%s",
			getAdminFillShipBulkPlayerLabel(player),
			sourcePath,
			#operations,
			tostring(batchResult and batchResult.Reason or "batch_failed")
		))
		return {
			Success = false,
			Changed = false,
			Reason = tostring(batchResult and batchResult.Reason or "batch_failed"),
			Counters = counters,
			Created = {},
			Failures = {
				"batch:" .. tostring(batchResult and batchResult.Reason or "batch_failed"),
			},
			Skipped = skipped,
			Filled = 0,
			Replaced = 0,
			BatchResult = batchResult,
		}
	end
	print(string.format(
		"[AdminFillShip] bulk_commit_ok target=%s source=%s operations=%d replicaWriteCount=%s",
		getAdminFillShipBulkPlayerLabel(player),
		sourcePath,
		#operations,
		tostring(batchResult and batchResult.ReplicaWriteCount or "unknown")
	))

	print(string.format(
		"[AdminFillShip] inventory_notify_begin target=%s source=%s",
		getAdminFillShipBulkPlayerLabel(player),
		sourcePath
	))
	notifyInventorySaved(player, canonicalInventory, {
		Source = "AdminFillShipBulk",
		Reason = "admin_fill_ship_bulk",
		SkipStandRuntimeRefresh = true,
		Counters = counters,
	})
	print(string.format(
		"[AdminFillShip] inventory_notify_ok target=%s source=%s inventoryNotifyCount=%d",
		getAdminFillShipBulkPlayerLabel(player),
		sourcePath,
		tonumber(counters.InventoryNotifyCount) or 0
	))
	incrementCounter(counters, "StandIncomeWriteCount", #standRows)
	CrewStandIncomeAuthority.RecordExternalIncomeWrite(#standRows)
	syncAvailableCounts(player, canonicalInventory)
	refreshCrewMemberShadow(player, "admin_fill_ship_bulk")
	updateInventoryAuthorityAudit(player, {
		LastAdminFillShipBulk = {
			CompletedAt = os.time(),
			Filled = filled,
			Replaced = replaced,
			Created = #createdRecords,
			OperationCount = #operations,
			ReplicaWriteCount = batchResult and batchResult.ReplicaWriteCount or nil,
		},
		ClearKeys = {
			"LastFailClosedReason",
			"LastFailClosedIssues",
		},
	})

	return {
		Success = true,
		Changed = true,
		Reason = "ok",
		Counters = counters,
		Created = createdRecords,
		Failures = failures,
		Skipped = skipped,
		Filled = filled,
		Replaced = replaced,
		BatchResult = batchResult,
		OperationCount = #operations,
		StandWriteCount = #standRows,
	}
end

function Module.ReleaseStandInstance(player, standName, options)
	options = if typeof(options) == "table" then options else {}
	standName = tostring(standName or "")
	if standName == CAPTAIN_SLOT_KEY then
		return nil, nil, "captain_slot_not_numeric_stand", {
			PlayerName = player and player.Name or "unknown",
			UserId = player and player.UserId or 0,
			StandName = standName,
		}
	end

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
	local actionTrace = GTRActionDiagnostics.Start("CrewRelease", player, {
		Target = standName,
	})
	local function finishRelease(result, reason)
		actionTrace:finish(result, {
			Target = standName,
			Reason = if result == "ok" then nil else tostring(reason or "unknown"),
		})
	end

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
		finishRelease("failed", "no_instance_available")
		return nil, nil, "no_instance_available", debugInfo
	end

	local _, _, releaseInventory = Module.GetInstance(player, instanceId)
	if releaseInventory ~= nil then
		crewMemberInventory = releaseInventory
	end

	local destination = chooseReleasedCrewDestination(player, crewMemberInventory, 1)
	applyReleasedCrewDestinationDebug(debugInfo, destination)
	if destination.Destination == "Blocked" then
		notifyHotbarAndStorageFull(player)
		crewPickupDebug(formatCrewPickupDebugFields({
			{ "event", "release_failed" },
			{ "reason", HOTBAR_STORAGE_FULL_REASON },
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
			{ "storageSlots", debugInfo.StorageSlots },
			{ "instanceExists", debugInfo.InstanceExistsInCrewInventory },
			{ "playerOwnsInstance", debugInfo.PlayerOwnsInstance },
			{ "placedTrackingRefs", debugInfo.AssignedStandRefs },
		}))
		finishRelease("failed", HOTBAR_STORAGE_FULL_REASON)
		return nil, nil, HOTBAR_STORAGE_FULL_REASON, debugInfo
	end

	local originalInstanceData = cloneValue(instanceData)
	local releasedInstanceData = cloneValue(instanceData)
	releasedInstanceData.AssignedStand = ""
	releasedInstanceData.LastReleasedAt = os.time()
	crewMemberInventory.ById[tostring(instanceId)] = releasedInstanceData
	moveInstanceToFront(crewMemberInventory, instanceId)
	local batchOk, batchReason, batchResult = applyInventoryAndStandBatch(player, crewMemberInventory, standName, {
		CrewMemberName = "",
		CrewMemberInstanceId = "",
		IncomeToCollect = 0,
		LastAccruedAtUnix = os.time(),
		StandLevel = 1,
	}, "stand_release")
	debugInfo.InventorySaveOk = batchOk == true
	debugInfo.InventorySaveReason = tostring(batchReason or "")
	debugInfo.StandClearOk = batchOk == true
	debugInfo.StandClearReason = tostring(batchReason or "")
	actionTrace:phase("mutate", {
		Target = standName,
		WriteCount = batchResult and batchResult.WriteCount or batchResult and batchResult.ReplicaWriteCount or 0,
		Result = if batchOk then "ok" else "failed",
		Reason = batchReason,
	})
	if batchOk ~= true then
		crewMemberInventory.ById[tostring(instanceId)] = originalInstanceData
		crewPickupDebug(formatCrewPickupDebugFields({
			{ "event", "release_failed" },
			{ "reason", "release_batch_failed" },
			{ "player", debugInfo.PlayerName },
			{ "userId", debugInfo.UserId },
			{ "stand", standName },
			{ "assignedName", debugInfo.AssignedCrewMemberName },
			{ "releasedInstanceId", tostring(instanceId) },
			{ "releasedStorage", tostring(releasedInstanceData.StorageName or "") },
			{ "inventorySaveOk", debugInfo.InventorySaveOk },
			{ "inventorySaveReason", debugInfo.InventorySaveReason },
			{ "standClearOk", "" },
			{ "standClearReason", "" },
		}))
		syncAvailableCounts(player, crewMemberInventory)
		refreshCrewMemberShadow(player, "stand_release_failed")
		finishRelease("failed", tostring(batchReason or "release_batch_failed"))
		return nil, nil, tostring(batchReason or "release_batch_failed"), debugInfo
	end

	if destination.Destination == "Hotbar" then
		local assignOk, assignResult =
			CrewQuickSlotService.AssignInstanceToSlot(player, instanceId, destination.QuickSlotIndex)
		debugInfo.ReleaseQuickSlotAssignOk = assignOk == true
		debugInfo.ReleaseQuickSlotAssignReason = tostring(assignResult and assignResult.Reason or "")
		debugInfo.ReleaseQuickSlotIndex = tonumber(assignResult and assignResult.SlotIndex)
			or tonumber(destination.QuickSlotIndex)
		if assignOk ~= true then
			CrewQuickSlotService.ClearAssignmentsForInstance(player, instanceId)
			crewMemberInventory.ById[tostring(instanceId)] = originalInstanceData
			local rollbackOk, rollbackReason = saveCrewMemberInventory(player, crewMemberInventory)
			debugInfo.InventoryRollbackOk = rollbackOk == true
			debugInfo.InventoryRollbackReason = tostring(rollbackReason or "")
			local standRestoreOk, standRestoreReason = updateStandData(
				player,
				standName,
				buildStandAssignmentRow(instanceId, originalInstanceData),
				"stand_release_quick_slot_rollback"
			)
			debugInfo.StandRestoreOk = standRestoreOk == true
			debugInfo.StandRestoreReason = tostring(standRestoreReason or "")
			crewPickupDebug(formatCrewPickupDebugFields({
				{ "event", "release_failed" },
				{ "reason", "quick_slot_assign_failed" },
				{ "player", debugInfo.PlayerName },
				{ "userId", debugInfo.UserId },
				{ "stand", standName },
				{ "assignedName", debugInfo.AssignedCrewMemberName },
				{ "releasedInstanceId", tostring(instanceId) },
				{ "releasedStorage", tostring(releasedInstanceData.StorageName or "") },
				{ "crewMemberInstanceId", debugInfo.CrewMemberInstanceId },
				{ "legacyStorageName", debugInfo.LegacyStorageName },
				{ "incomeBefore", debugInfo.IncomeBefore },
				{ "quickSlotIndex", debugInfo.ReleaseQuickSlotIndex or "" },
				{ "quickAssignReason", debugInfo.ReleaseQuickSlotAssignReason },
				{ "inventoryRollbackOk", debugInfo.InventoryRollbackOk },
				{ "standRestoreOk", debugInfo.StandRestoreOk },
			}))
			syncAvailableCounts(player, crewMemberInventory)
			refreshCrewMemberShadow(player, "stand_release_quick_slot_failed")
			finishRelease("failed", "quick_slot_assign_failed")
			return nil, nil, "quick_slot_assign_failed", debugInfo
		end
	else
		debugInfo.ReleaseQuickSlotAssignOk = false
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
		{ "releasedStorage", tostring(releasedInstanceData.StorageName or "") },
		{ "crewMemberInstanceId", debugInfo.CrewMemberInstanceId },
		{ "legacyStorageName", debugInfo.LegacyStorageName },
		{ "incomeBefore", debugInfo.IncomeBefore },
		{ "destination", debugInfo.ReleaseDestination },
		{ "quickSlotIndex", debugInfo.ReleaseQuickSlotIndex or "" },
		{ "quickOccupied", debugInfo.QuickSlotOccupied },
		{ "quickUnlocked", debugInfo.QuickSlotUnlocked },
		{ "quickMax", debugInfo.QuickSlotMax },
		{ "inventorySaveOk", debugInfo.InventorySaveOk },
		{ "inventorySaveReason", debugInfo.InventorySaveReason },
		{ "standClearOk", debugInfo.StandClearOk },
		{ "standClearReason", debugInfo.StandClearReason },
		{ "placedTrackingRefs", debugInfo.AssignedStandRefs },
	}))
	finishRelease("ok")

	return tostring(instanceId), crewMemberInventory.ById[tostring(instanceId)], nil, debugInfo
end

function Module.RemoveAvailableInstance(player, storageName)
	warn(string.format(
		"[CrewInstanceService] rejected legacy name-based crew remove player=%s storage=%s",
		player and player.Name or "unknown",
		tostring(storageName)
	))
	return nil, nil, "exact_instance_required"
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

function Module.TransferStandInstance(ownerPlayer, buyerPlayer, standName, options)
	options = if typeof(options) == "table" then options else {}
	standName = tostring(standName or "")
	local debugInfo = {
		OwnerName = ownerPlayer and ownerPlayer.Name or "unknown",
		OwnerUserId = ownerPlayer and ownerPlayer.UserId or 0,
		BuyerName = buyerPlayer and buyerPlayer.Name or "unknown",
		BuyerUserId = buyerPlayer and buyerPlayer.UserId or 0,
		StandName = standName,
		ExpectedInstanceId = tostring(options.ExpectedInstanceId or ""),
	}

	local instanceId, instanceData = Module.EnsureStandInstance(ownerPlayer, standName)
	debugInfo.SourceInstanceId = tostring(instanceId or "")
	if not instanceData then
		return nil, nil, "no_instance_available", debugInfo
	end
	if debugInfo.ExpectedInstanceId ~= "" and tostring(instanceId) ~= debugInfo.ExpectedInstanceId then
		return nil, nil, "instance_mismatch", debugInfo
	end
	if isProtectedTutorialReward(ownerPlayer, instanceData) then
		return nil, nil, "protected_tutorial_reward", debugInfo
	end

	if not CrewQuickSlotService.CanGainOrNotify(
		buyerPlayer,
		getInstanceCrewKey(instanceData),
		1,
		"TransferStandInstance:" .. tostring(standName)
	) then
		return nil, nil, "quick_slot_capacity", debugInfo
	end

	local _, _, ownerInventory = Module.GetInstance(ownerPlayer, instanceId)
	if typeof(ownerInventory) ~= "table" or typeof(ownerInventory.ById) ~= "table" then
		return nil, nil, "owner_inventory_missing", debugInfo
	end

	local standDataBefore = getStandData(ownerPlayer, standName)
	local ownerShipSlotsBefore = cloneValue(getDataManager():GetValue(ownerPlayer, "Ship.Slots"))
	local ownerInventoryBefore = cloneValue(ownerInventory)
	local buyerInventoryBefore = getCrewMemberInventory(buyerPlayer)
	local buyerInventory = cloneValue(buyerInventoryBefore)

	local buyerInstanceId = tostring(buyerInventory.NextInstanceId)
	buyerInventory.NextInstanceId += 1
	local buyerInstanceData = cloneValue(instanceData)
	buyerInstanceData.AssignedStand = ""
	buyerInstanceData.LastReleasedAt = os.time()
	buyerInstanceData = normalizeInstanceData(buyerInstanceId, buyerInstanceData, instanceData.StorageName)
	if buyerInstanceData == nil then
		return nil, nil, "buyer_instance_normalize_failed", debugInfo
	end
	buyerInventory.ById[buyerInstanceId] = buyerInstanceData
	table.insert(buyerInventory.Order, 1, buyerInstanceId)

	local finalOwnerInventory = cloneValue(ownerInventory)
	finalOwnerInventory.ById[tostring(instanceId)] = nil
	for index = #finalOwnerInventory.Order, 1, -1 do
		if tostring(finalOwnerInventory.Order[index]) == tostring(instanceId) then
			table.remove(finalOwnerInventory.Order, index)
			break
		end
	end

	local function rollbackOwnerState(reason)
		local rollbackInventoryOk, rollbackInventoryReason = saveCrewMemberInventory(ownerPlayer, ownerInventoryBefore, {
			SourcePath = "premium_crew_steal_transfer_out_rollback",
		})
		local rollbackStandOk, rollbackStandReason = setStandData(
			ownerPlayer,
			standName,
			standDataBefore,
			"premium_crew_steal_transfer_out_rollback"
		)
		local rollbackShipOk, rollbackShipReason = restoreShipSlots(ownerPlayer, ownerShipSlotsBefore)
		debugInfo.RollbackInventoryOk = rollbackInventoryOk == true
		debugInfo.RollbackInventoryReason = tostring(rollbackInventoryReason or "")
		debugInfo.RollbackStandOk = rollbackStandOk == true
		debugInfo.RollbackStandReason = tostring(rollbackStandReason or "")
		debugInfo.RollbackShipSlotsOk = rollbackShipOk == true
		debugInfo.RollbackShipSlotsReason = tostring(rollbackShipReason or "")
		return nil, nil, reason, debugInfo
	end

	local ownerSaveOk, ownerSaveReason = saveCrewMemberInventory(ownerPlayer, finalOwnerInventory, {
		SourcePath = "premium_crew_steal_transfer_out",
	})
	debugInfo.OwnerInventorySaveOk = ownerSaveOk == true
	debugInfo.OwnerInventorySaveReason = tostring(ownerSaveReason or "")
	if ownerSaveOk ~= true then
		return nil, nil, tostring(ownerSaveReason or "owner_inventory_write_failed"), debugInfo
	end

	local clearOk, clearReason = clearStandData(ownerPlayer, standName, "premium_crew_steal_transfer_out")
	debugInfo.OwnerStandClearOk = clearOk == true
	debugInfo.OwnerStandClearReason = tostring(clearReason or "")
	if clearOk ~= true then
		return rollbackOwnerState(tostring(clearReason or "stand_clear_failed"))
	end

	local shipClearOk, shipClearReason = clearShipSlotAssignment(ownerPlayer, standName)
	debugInfo.OwnerShipSlotClearOk = shipClearOk == true
	debugInfo.OwnerShipSlotClearReason = tostring(shipClearReason or "")
	if shipClearOk ~= true then
		return rollbackOwnerState(tostring(shipClearReason or "ship_slot_clear_failed"))
	end

	local buyerSaveOk, buyerSaveReason = saveCrewMemberInventory(buyerPlayer, buyerInventory, {
		SourcePath = "premium_crew_steal_transfer_in",
	})
	debugInfo.BuyerInventorySaveOk = buyerSaveOk == true
	debugInfo.BuyerInventorySaveReason = tostring(buyerSaveReason or "")
	if buyerSaveOk ~= true then
		return rollbackOwnerState(tostring(buyerSaveReason or "buyer_inventory_write_failed"))
	end

	syncAvailableCounts(ownerPlayer, finalOwnerInventory)
	refreshCrewMemberShadow(ownerPlayer, "product_reward_transfer_out")
	ensureInventoryMetadata(buyerPlayer, instanceData.StorageName, instanceData)
	IndexCollectionService.MarkCrewMemberDiscovered(
		buyerPlayer,
		instanceData.StorageName,
		instanceData.BaseName,
		instanceData.Variant,
		{
			DeferShadowRefresh = true,
		}
	)
	syncAvailableCounts(buyerPlayer, buyerInventory)
	refreshCrewMemberShadow(buyerPlayer, "product_reward_transfer_in")

	return buyerInstanceId, buyerInventory.ById[buyerInstanceId], nil, debugInfo
end

function Module.VerifyStandEmpty(player, standName, options)
	options = if typeof(options) == "table" then options else {}
	standName = tostring(standName or "")
	local expectedSourceInstanceId = tostring(options.SourceInstanceId or "")
	local standData = getStandData(player, standName)
	local shipSlots = getDataManager():GetValue(player, "Ship.Slots")
	local crewMemberInventory = getCrewMemberInventory(player)
	local assignedStandRefs = {}

	if typeof(crewMemberInventory) == "table" and typeof(crewMemberInventory.ById) == "table" then
		for ownedInstanceId, ownedInstanceData in pairs(crewMemberInventory.ById) do
			if typeof(ownedInstanceData) == "table" and tostring(ownedInstanceData.AssignedStand or "") == standName then
				table.insert(assignedStandRefs, tostring(ownedInstanceId))
			end
		end
	end
	table.sort(assignedStandRefs)

	local sourceInstanceStillOwned = expectedSourceInstanceId ~= ""
		and typeof(crewMemberInventory) == "table"
		and typeof(crewMemberInventory.ById) == "table"
		and crewMemberInventory.ById[expectedSourceInstanceId] ~= nil
	local crewMemberName = tostring(standData and standData.CrewMemberName or "")
	local crewMemberInstanceId = tostring(standData and standData.CrewMemberInstanceId or "")
	local shipSlotEmpty = typeof(shipSlots) ~= "table" or shipSlots[standName] == nil
	local detail = {
		StandName = standName,
		CrewMemberName = crewMemberName,
		CrewMemberInstanceId = crewMemberInstanceId,
		ShipSlotEmpty = shipSlotEmpty,
		SourceInstanceId = expectedSourceInstanceId,
		SourceInstanceStillOwned = sourceInstanceStillOwned == true,
		AssignedStandRefs = assignedStandRefs,
	}

	local isEmpty = crewMemberName == ""
		and crewMemberInstanceId == ""
		and shipSlotEmpty == true
		and sourceInstanceStillOwned ~= true
		and #assignedStandRefs == 0
	return isEmpty, if isEmpty then nil else "victim_stand_not_cleared", detail
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
Module.AssignCrewMemberInstanceToStand = Module.AssignInstanceToStand
Module.SwapCrewMemberStandInstance = Module.SwapStandInstance
Module.ReleaseStandCrewMember = Module.ReleaseStandInstance
Module.RemoveAvailableCrewMember = Module.RemoveAvailableInstance
Module.RepairCanonicalCrewMemberState = Module.RepairCanonicalCrewState

return Module
