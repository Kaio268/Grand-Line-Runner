local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BrainrotsCfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local VariantCfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))

local Module = {}
local DataManagerModule

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
	}
end

local function saveBrainrotInventory(player, brainrotInventory)
	getDataManager():SetValue(player, "BrainrotInventory", brainrotInventory)
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
	local basePath = "Inventory." .. tostring(storageName)
	local dataManager = getDataManager()
	dataManager:SetValue(player, basePath .. ".Variant", metadata.Variant)
	dataManager:SetValue(player, basePath .. ".BaseName", metadata.BaseName)
	dataManager:SetValue(player, basePath .. ".Render", metadata.Render)
	dataManager:SetValue(player, basePath .. ".GoldenRender", metadata.GoldenRender)
	dataManager:SetValue(player, basePath .. ".DiamondRender", metadata.DiamondRender)
	dataManager:SetValue(player, basePath .. ".Income", metadata.Income)
	dataManager:SetValue(player, basePath .. ".Rarity", metadata.Rarity)

	if dataManager:GetValue(player, basePath .. ".Equipped") == nil then
		dataManager:SetValue(player, basePath .. ".Equipped", 0)
	end
	if dataManager:GetValue(player, basePath .. ".Quantity") == nil then
		dataManager:SetValue(player, basePath .. ".Quantity", 0)
	end
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
	})
	table.insert(brainrotInventory.Order, instanceId)

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

function Module.SyncAvailableCounts(player)
	return syncAvailableCounts(player)
end

function Module.EnsureInventoryMetadata(player, storageName, metadata)
	return ensureInventoryMetadata(player, storageName, metadata)
end

function Module.CreateInstances(player, storageName, count, overrides)
	local safeCount = math.max(0, math.floor(coerceNumber(count, 0)))
	if safeCount <= 0 then
		return {}
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
	local instanceId, instanceData, brainrotInventory = Module.FindAvailableInstance(player, storageName)
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

function Module.TransferStandInstance(ownerPlayer, buyerPlayer, standName)
	local instanceId, instanceData = Module.EnsureStandInstance(ownerPlayer, standName)
	if not instanceData then
		return nil, nil
	end

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

	local buyerInventory = getBrainrotInventory(buyerPlayer)
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
	saveBrainrotInventory(buyerPlayer, buyerInventory)
	syncAvailableCounts(buyerPlayer, buyerInventory)

	return buyerInstanceId, buyerInventory.ById[buyerInstanceId]
end

return Module
