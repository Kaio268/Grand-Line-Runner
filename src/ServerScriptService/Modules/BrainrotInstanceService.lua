local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BrainrotsCfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local VariantCfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))
local BrainrotQuickSlotService = require(script.Parent:WaitForChild("BrainrotQuickSlotService"))
local IndexCollectionService = require(script.Parent:WaitForChild("IndexCollectionService"))

local Module = {}
local DataManagerModule
local inventorySavedCallbacks = {}
local TUTORIAL_COMPLETION_PATH = "HiddenLeaderstats.Tutorial"

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
			warn(string.format("[BrainrotInstanceService] Inventory save callback failed: %s", tostring(err)))
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

local function getInventoryEntry(player, storageName)
	local entry = getDataManager():GetValue(player, "Inventory." .. tostring(storageName))
	if typeof(entry) == "table" then
		return entry
	end
	return nil
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

	local info = BrainrotsCfg[storageName] or BrainrotsCfg[baseName] or {}
	local baseInfo = BrainrotsCfg[baseName] or info

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
	}
end

local function copyTableShallow(source)
	local copy = {}
	if typeof(source) ~= "table" then
		return copy
	end

	for key, value in pairs(source) do
		copy[key] = value
	end

	return copy
end

local function buildLegacyInventoryEntry(storageName, entry, metadata)
	metadata = metadata or buildMetadata(storageName, entry)

	local normalized = copyTableShallow(entry)
	local render = tostring(normalized.Render or metadata.Render or "")

	normalized.Equipped = math.max(0, math.floor(coerceNumber(normalized.Equipped, 0)))
	normalized.Quantity = math.max(0, math.floor(coerceNumber(normalized.Quantity, 0)))
	normalized.Variant = tostring(normalized.Variant or metadata.Variant or "Normal")
	normalized.BaseName = tostring(normalized.BaseName or metadata.BaseName or storageName)
	normalized.Render = render
	normalized.GoldenRender = tostring(normalized.GoldenRender or metadata.GoldenRender or render)
	normalized.DiamondRender = tostring(normalized.DiamondRender or metadata.DiamondRender or render)
	normalized.Income = tonumber(normalized.Income or metadata.Income) or 0
	normalized.Rarity = tostring(normalized.Rarity or metadata.Rarity or "Common")
	normalized.Level = math.max(1, math.floor(coerceNumber(normalized.Level, 1)))
	normalized.CurrentXP = math.max(0, math.floor(coerceNumber(normalized.CurrentXP, 0)))

	return normalized
end

local function ensureLegacyInventoryEntry(player, storageName, metadata)
	local dataManager = getDataManager()
	local entry = buildLegacyInventoryEntry(storageName, getInventoryEntry(player, storageName), metadata)

	dataManager:SetValue(player, "Inventory." .. tostring(storageName), entry)
	return entry
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

local function normalizeInstanceData(instanceId, instanceData, fallbackStorageName)
	instanceData = typeof(instanceData) == "table" and instanceData or {}

	local storageName = tostring(instanceData.StorageName or fallbackStorageName or instanceData.BrainrotName or "")
	if storageName == "" then
		return nil
	end

	local metadata = buildMetadata(storageName, instanceData)

	return {
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
		AssignedStand = tostring(instanceData.AssignedStand or ""),
		AcquiredAt = coerceNumber(instanceData.AcquiredAt, os.time()),
		LastReleasedAt = coerceNumber(instanceData.LastReleasedAt, 0),
		TutorialReward = instanceData.TutorialReward == true,
		TutorialToken = tostring(instanceData.TutorialToken or ""),
	}
end

local function saveBrainrotInventory(player, brainrotInventory)
	getDataManager():SetValue(player, "BrainrotInventory", brainrotInventory)
	notifyInventorySaved(player, brainrotInventory)
end

local function getBrainrotInventory(player)
	local brainrotInventory = ensureBrainrotInventoryShape(getDataManager():GetValue(player, "BrainrotInventory"))
	local changed = false

	local normalizedOrder = {}
	local seen = {}
	local maxInstanceNumber = brainrotInventory.NextInstanceId - 1
	for _, rawInstanceId in ipairs(brainrotInventory.Order) do
		local instanceId = tostring(rawInstanceId)
		maxInstanceNumber = math.max(maxInstanceNumber, tonumber(instanceId) or 0)
		local normalized = normalizeInstanceData(instanceId, brainrotInventory.ById[instanceId])
		if normalized then
			brainrotInventory.ById[instanceId] = normalized
			if not seen[instanceId] then
				seen[instanceId] = true
				table.insert(normalizedOrder, instanceId)
			end
		else
			brainrotInventory.ById[instanceId] = nil
			changed = true
		end
	end

	for instanceId, instanceData in pairs(brainrotInventory.ById) do
		instanceId = tostring(instanceId)
		maxInstanceNumber = math.max(maxInstanceNumber, tonumber(instanceId) or 0)
		if not seen[instanceId] then
			local normalized = normalizeInstanceData(instanceId, instanceData)
			if normalized then
				brainrotInventory.ById[instanceId] = normalized
				table.insert(normalizedOrder, instanceId)
				seen[instanceId] = true
				changed = true
			else
				brainrotInventory.ById[instanceId] = nil
				changed = true
			end
		end
	end

	if #normalizedOrder ~= #brainrotInventory.Order then
		changed = true
	end
	brainrotInventory.Order = normalizedOrder
	if brainrotInventory.NextInstanceId <= maxInstanceNumber then
		brainrotInventory.NextInstanceId = maxInstanceNumber + 1
		changed = true
	end

	if changed then
		saveBrainrotInventory(player, brainrotInventory)
	end

	return brainrotInventory
end

local function setInstanceData(player, brainrotInventory, instanceId, instanceData)
	brainrotInventory.ById[tostring(instanceId)] = normalizeInstanceData(instanceId, instanceData)
	saveBrainrotInventory(player, brainrotInventory)
end

local function syncQuantityValue(player, storageName, quantity)
	if getInventoryEntry(player, storageName) == nil then
		ensureLegacyInventoryEntry(player, storageName)
	end

	getDataManager():SetValue(player, "Inventory." .. tostring(storageName) .. ".Quantity", math.max(0, math.floor(coerceNumber(quantity, 0))))
end

local function syncAvailableCounts(player, brainrotInventory)
	brainrotInventory = brainrotInventory or getBrainrotInventory(player)

	local counts = {}
	for _, instanceId in ipairs(brainrotInventory.Order) do
		local instanceData = brainrotInventory.ById[tostring(instanceId)]
		if instanceData and instanceData.AssignedStand == "" then
			counts[instanceData.StorageName] = (counts[instanceData.StorageName] or 0) + 1
		end
	end

	local inventory = getDataManager():GetValue(player, "Inventory")
	if typeof(inventory) == "table" then
		for key, entry in pairs(inventory) do
			if isBrainrotInventoryEntry(key, entry) then
				syncQuantityValue(player, key, counts[key] or 0)
			end
		end
	end

	for storageName, count in pairs(counts) do
		syncQuantityValue(player, storageName, count)
	end
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
	local standData = getDataManager():GetValue(player, "IncomeBrainrots." .. tostring(standName))
	if typeof(standData) ~= "table" then
		standData = {
			BrainrotName = "",
			BrainrotInstanceId = "",
			IncomeToCollect = 0,
		}
	end

	local changed = false
	if typeof(standData.BrainrotName) ~= "string" then
		standData.BrainrotName = ""
		changed = true
	end
	if typeof(standData.BrainrotInstanceId) ~= "string" then
		standData.BrainrotInstanceId = ""
		changed = true
	end
	if typeof(standData.IncomeToCollect) ~= "number" then
		standData.IncomeToCollect = 0
		changed = true
	end
	if changed then
		getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName), standData)
	end

	return standData
end

local function ensureInventoryMetadata(player, storageName, metadata)
	metadata = metadata or buildMetadata(storageName, getInventoryEntry(player, storageName))
	return ensureLegacyInventoryEntry(player, storageName, metadata)
end

local function createInstanceInternal(player, brainrotInventory, storageName, overrides)
	local entry = getInventoryEntry(player, storageName)
	local metadata = buildMetadata(storageName, entry)
	ensureInventoryMetadata(player, storageName, metadata)

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
		AssignedStand = overrides and overrides.AssignedStand or "",
		AcquiredAt = overrides and overrides.AcquiredAt or os.time(),
		LastReleasedAt = overrides and overrides.LastReleasedAt or 0,
		TutorialReward = overrides and overrides.TutorialReward == true,
		TutorialToken = overrides and overrides.TutorialToken or "",
	})
	if overrides and overrides.TutorialReward == true then
		table.insert(brainrotInventory.Order, 1, instanceId)
	else
		table.insert(brainrotInventory.Order, instanceId)
	end
	IndexCollectionService.MarkBrainrotDiscovered(
		player,
		storageName,
		overrides and overrides.BaseName or metadata.BaseName,
		overrides and overrides.Variant or metadata.Variant
	)

	return instanceId, brainrotInventory.ById[instanceId]
end

local function getStoredLegacyProgress(player, storageName)
	local entry = getInventoryEntry(player, storageName) or {}
	return math.max(1, math.floor(coerceNumber(entry.Level, 1))), math.max(0, math.floor(coerceNumber(entry.CurrentXP, 0)))
end

function Module.IsBrainrotInventoryEntry(key, entry)
	return isBrainrotInventoryEntry(key, entry)
end

function Module.EnsureInventory(player)
	return getBrainrotInventory(player)
end

function Module.RegisterInventorySavedCallback(callback)
	if typeof(callback) ~= "function" then
		error("[BrainrotInstanceService] RegisterInventorySavedCallback expects a function")
	end

	inventorySavedCallbacks[callback] = true

	return function()
		inventorySavedCallbacks[callback] = nil
	end
end

function Module.SyncAvailableCounts(player)
	return syncAvailableCounts(player)
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

function Module.AssignTutorialRewardInstanceToStand(player, standName, filters)
	filters = getTutorialRewardFilters(filters)
	filters.RequireAvailable = true
	local clearTutorialMetadataAfterAssign = filters.ClearTutorialMetadataAfterAssign == true

	local instanceId, instanceData, brainrotInventory = Module.FindTutorialRewardInstance(player, filters)
	if not instanceData then
		return nil, nil
	end

	instanceData.AssignedStand = tostring(standName)
	setInstanceData(player, brainrotInventory, instanceId, instanceData)
	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", instanceData.StorageName)
	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", tostring(instanceId))

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
		if not BrainrotQuickSlotService.CanGainOrNotify(player, safeCount, "CreateInstances:" .. tostring(storageName)) then
			return {}
		end
	end

	local brainrotInventory = getBrainrotInventory(player)

	local createdIds = {}
	for _ = 1, safeCount do
		local instanceId = createInstanceInternal(player, brainrotInventory, storageName, overrides)
		table.insert(createdIds, instanceId)
	end

	saveBrainrotInventory(player, brainrotInventory)
	syncAvailableCounts(player, brainrotInventory)
	return createdIds
end

function Module.EnsureAvailableInstancesForStorage(player, storageName, minimumAvailable)
	local brainrotInventory = getBrainrotInventory(player)
	local availableCount = 0
	for _, instanceId in ipairs(brainrotInventory.Order) do
		local instanceData = brainrotInventory.ById[tostring(instanceId)]
		if instanceData and instanceData.StorageName == storageName and instanceData.AssignedStand == "" then
			availableCount += 1
		end
	end

	local requestedMinimum = math.max(0, math.floor(coerceNumber(minimumAvailable, 0)))
	local legacyQuantity = math.max(0, math.floor(coerceNumber(getDataManager():GetValue(player, "Inventory." .. tostring(storageName) .. ".Quantity"), 0)))
	local targetCount = math.max(requestedMinimum, legacyQuantity)
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

	saveBrainrotInventory(player, brainrotInventory)
	syncAvailableCounts(player, brainrotInventory)
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

function Module.UpdateProgress(player, instanceId, level, currentXP)
	local resolvedInstanceId, instanceData, brainrotInventory = Module.GetInstance(player, instanceId)
	if not instanceData then
		return nil
	end

	instanceData.Level = math.max(1, math.floor(coerceNumber(level, instanceData.Level or 1)))
	instanceData.CurrentXP = math.max(0, math.floor(coerceNumber(currentXP, instanceData.CurrentXP or 0)))
	setInstanceData(player, brainrotInventory, resolvedInstanceId, instanceData)
	return brainrotInventory.ById[resolvedInstanceId]
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
	end

	return instanceId
end

function Module.EnsureStandInstance(player, standName, fallbackStorageName)
	local standData = getStandData(player, standName)
	local standStorageName = tostring(standData.BrainrotName or fallbackStorageName or "")
	if standStorageName == "" then
		if standData.BrainrotInstanceId ~= "" then
			getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", "")
		end
		return nil, nil
	end

	local instanceId = tostring(standData.BrainrotInstanceId or "")
	local brainrotInventory = getBrainrotInventory(player)
	local instanceData = brainrotInventory.ById[instanceId]
	if instanceData then
		if instanceData.AssignedStand ~= tostring(standName) then
			instanceData.AssignedStand = tostring(standName)
			setInstanceData(player, brainrotInventory, instanceId, instanceData)
		end
		if standData.BrainrotName ~= instanceData.StorageName then
			getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", instanceData.StorageName)
		end
		return instanceId, instanceData
	end

	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local candidate = brainrotInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.AssignedStand == tostring(standName) then
			getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", tostring(orderedInstanceId))
			if standData.BrainrotName ~= candidate.StorageName then
				getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", candidate.StorageName)
			end
			return tostring(orderedInstanceId), candidate
		end
	end

	Module.EnsureAvailableInstancesForStorage(player, standStorageName, 1)
	brainrotInventory = getBrainrotInventory(player)
	for _, orderedInstanceId in ipairs(brainrotInventory.Order) do
		local candidate = brainrotInventory.ById[tostring(orderedInstanceId)]
		if candidate and candidate.StorageName == standStorageName and candidate.AssignedStand == "" then
			candidate.AssignedStand = tostring(standName)
			setInstanceData(player, brainrotInventory, orderedInstanceId, candidate)
			getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", tostring(orderedInstanceId))
			if standData.BrainrotName ~= candidate.StorageName then
				getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", candidate.StorageName)
			end
			syncAvailableCounts(player)
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
	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", tostring(createdId))
	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", standStorageName)
	syncAvailableCounts(player, brainrotInventory)
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
		return nil, nil
	end

	instanceData.AssignedStand = tostring(standName)
	setInstanceData(player, brainrotInventory, instanceId, instanceData)
	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", instanceData.StorageName)
	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", tostring(instanceId))
	syncAvailableCounts(player, brainrotInventory)

	return tostring(instanceId), brainrotInventory.ById[tostring(instanceId)]
end

function Module.ReleaseStandInstance(player, standName)
	local instanceId, instanceData = Module.EnsureStandInstance(player, standName)
	if not instanceData then
		getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", "")
		getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", "")
		return nil, nil
	end

	if not BrainrotQuickSlotService.CanGainOrNotify(player, 1, "ReleaseStandInstance:" .. tostring(standName)) then
		return nil, nil
	end

	local _, _, brainrotInventory = Module.GetInstance(player, instanceId)

	instanceData.AssignedStand = ""
	instanceData.LastReleasedAt = os.time()
	brainrotInventory.ById[tostring(instanceId)] = instanceData
	moveInstanceToFront(brainrotInventory, instanceId)
	saveBrainrotInventory(player, brainrotInventory)

	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", "")
	getDataManager():SetValue(player, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", "")
	syncAvailableCounts(player, brainrotInventory)

	return tostring(instanceId), brainrotInventory.ById[tostring(instanceId)]
end

function Module.RemoveAvailableInstance(player, storageName)
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

	saveBrainrotInventory(player, brainrotInventory)
	syncAvailableCounts(player, brainrotInventory)
	return tostring(instanceId), instanceData
end

function Module.RemoveTutorialRewardInstances(player, options)
	options = if typeof(options) == "table" then options else {}

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

	local incomeBrainrots = getDataManager():GetValue(player, "IncomeBrainrots")
	if typeof(incomeBrainrots) == "table" then
		local incomeChanged = false
		for standName, standData in pairs(incomeBrainrots) do
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
					standData.BrainrotName = ""
					standData.BrainrotInstanceId = ""
					standData.IncomeToCollect = 0
					incomeBrainrots[standName] = standData
					clearedStandMap[tostring(standName)] = true
					incomeChanged = true
				end
			end
		end

		if incomeChanged then
			getDataManager():SetValue(player, "IncomeBrainrots", incomeBrainrots)
		end
	end

	local clearedStands = {}
	for standName in pairs(clearedStandMap) do
		table.insert(clearedStands, standName)
		clearShipSlotAssignment(player, standName)
		getDataManager():SetValue(player, "StandsLevels." .. standName, 1)
	end
	table.sort(clearedStands, function(left, right)
		return (tonumber(left) or math.huge) < (tonumber(right) or math.huge)
	end)

	if options.ClearStaleStorageAssignments == true and #removedIds <= 0 then
		for _, storageName in ipairs(tutorialStorageNames) do
			local availableCount = 0
			for _, instanceData in pairs(brainrotInventory.ById) do
				if
					typeof(instanceData) == "table"
					and tostring(instanceData.StorageName or "") == storageName
					and tostring(instanceData.AssignedStand or "") == ""
				then
					availableCount += 1
				end
			end
			if availableCount > 0 or getInventoryEntry(player, storageName) ~= nil then
				syncQuantityValue(player, storageName, availableCount)
			end
		end
	end

	if #removedIds > 0 then
		saveBrainrotInventory(player, brainrotInventory)
		syncAvailableCounts(player, brainrotInventory)
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

	if not BrainrotQuickSlotService.CanGainOrNotify(buyerPlayer, 1, "TransferStandInstance:" .. tostring(standName)) then
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
	getDataManager():SetValue(ownerPlayer, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotName", "")
	getDataManager():SetValue(ownerPlayer, "IncomeBrainrots." .. tostring(standName) .. ".BrainrotInstanceId", "")
	syncAvailableCounts(ownerPlayer, ownerInventory)

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
	IndexCollectionService.MarkBrainrotDiscovered(
		buyerPlayer,
		instanceData.StorageName,
		instanceData.BaseName,
		instanceData.Variant
	)
	saveBrainrotInventory(buyerPlayer, buyerInventory)
	syncAvailableCounts(buyerPlayer, buyerInventory)

	return buyerInstanceId, buyerInventory.ById[buyerInstanceId]
end

return Module
