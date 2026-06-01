local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewInventoryStacks = require(Modules:WaitForChild("Crew"):WaitForChild("CrewInventoryStacks"))

local CrewInventoryDerivedCache = {}
local SELL_TIME_SECONDS = 15

local cacheByPlayer = setmetatable({}, { __mode = "k" })
local crewInstanceServiceModule = nil
local dataManagerModule = nil

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or "")
		if value ~= "" then
			return value
		end
	end
	return ""
end

local function cloneArray(values)
	local copy = {}
	if typeof(values) ~= "table" then
		return copy
	end

	for index, value in ipairs(values) do
		copy[index] = value
	end
	return copy
end

local function getInstanceVariant(instanceData)
	if typeof(instanceData) ~= "table" then
		return ""
	end
	return firstNonEmpty(instanceData.Variant, instanceData.VariantKey)
end

local function getInstanceLevel(instanceData)
	if typeof(instanceData) ~= "table" then
		return nil
	end
	local level = tonumber(instanceData.Level)
	return if level ~= nil then math.max(1, math.floor(level)) else nil
end

local function getInstanceIncome(instanceData, info)
	if typeof(instanceData) ~= "table" then
		return tonumber(info and info.Income)
	end
	return tonumber(instanceData.Income or (info and info.Income))
end

local function getSellValue(instanceData, info)
	if typeof(info) ~= "table" then
		return 0
	end
	if info.SellPrice ~= nil then
		return math.max(0, math.floor(tonumber(info.SellPrice) or 0))
	end

	local income = getInstanceIncome(instanceData, info)
	if income == nil then
		return 0
	end
	return math.max(0, math.floor(income * SELL_TIME_SECONDS))
end

local function valuesDiffer(firstValue, nextValue)
	if firstValue == nil and nextValue == nil then
		return false
	end
	return tostring(firstValue or "") ~= tostring(nextValue or "")
end

local function getCache(player)
	local cache = cacheByPlayer[player]
	if cache == nil then
		cache = {
			Dirty = true,
			Version = 0,
			Inventory = nil,
			Snapshot = nil,
		}
		cacheByPlayer[player] = cache
	end
	return cache
end

local function readCrewInventory(player)
	if crewInstanceServiceModule == false then
		return nil
	end

	if crewInstanceServiceModule == nil then
		local ok, module = pcall(function()
			return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))
		end)
		if not ok or typeof(module) ~= "table" then
			crewInstanceServiceModule = false
			return nil
		end
		crewInstanceServiceModule = module
	end

	if typeof(crewInstanceServiceModule.GetCrewInventory) ~= "function" then
		return nil
	end

	local ok, inventory = pcall(function()
		return crewInstanceServiceModule.GetCrewInventory(player)
	end)
	if ok and typeof(inventory) == "table" and typeof(inventory.ById) == "table" then
		return inventory
	end
	return nil
end

local function getDataManager()
	if dataManagerModule == nil then
		local ok, module = pcall(function()
			return require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
		end)
		dataManagerModule = if ok then module else false
	end
	return if dataManagerModule == false then nil else dataManagerModule
end

local function readQuickSlotAssignments(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {}
	end

	local dataManager = getDataManager()
	if dataManager == nil then
		return {}
	end

	local ok, quickSlots = pcall(function()
		return dataManager:GetValue(player, "CrewMemberQuickSlots")
	end)
	if not ok or typeof(quickSlots) ~= "table" or typeof(quickSlots.Assignments) ~= "table" then
		return {}
	end
	return quickSlots.Assignments
end

local function resolveInfo(crewMemberId, representative)
	local canonicalId, info = CrewCatalog.ResolveCrewMemberId(crewMemberId)
	if info then
		return canonicalId, info
	end

	if typeof(representative) == "table" then
		canonicalId, info = CrewCatalog.ResolveCrewMemberId(representative.CrewMemberId or representative.StorageName)
		if info then
			return canonicalId, info
		end
	end

	return tostring(crewMemberId or ""), nil
end

local function buildCrewDetails(instanceId, instanceData, info, state, stack, inventory)
	instanceData = if typeof(instanceData) == "table" then instanceData else {}
	state = tostring(state or "Stored")
	local displayInfo = CrewCatalog.GetDisplayInfo(instanceData.CrewMemberId or instanceData.StorageName, instanceData)

	local details = {
		DisplayName = firstNonEmpty(displayInfo.DisplayName, info and (info.DisplayName or info.CrewMemberName or info.Name), instanceData.CrewMemberId, instanceData.StorageName),
		BaseDisplayName = firstNonEmpty(displayInfo.BaseDisplayName, displayInfo.DisplayName),
		Rarity = firstNonEmpty(instanceData.Rarity, info and info.Rarity),
		Variant = firstNonEmpty(displayInfo.Variant, getInstanceVariant(instanceData)),
		VariantTag = firstNonEmpty(displayInfo.VariantTag),
		VariantDisplayName = firstNonEmpty(displayInfo.VariantDisplayName),
		ShowVariantTag = displayInfo.ShowVariantTag == true,
		Level = getInstanceLevel(instanceData),
		Income = getInstanceIncome(instanceData, info),
		SellValue = getSellValue(instanceData, info),
		State = state,
	}

	if typeof(stack) == "table" then
		details.StackQuantity = math.max(1, math.floor(tonumber(stack.Quantity) or 1))
		details.StackRepresentative = true
		details.StackMaxQuantity = math.max(1, math.floor(tonumber(stack.MaxQuantity) or details.StackQuantity))

		local representativeVariant = getInstanceVariant(instanceData)
		local representativeLevel = getInstanceLevel(instanceData)
		local representativeIncome = getInstanceIncome(instanceData, info)
		local byId = typeof(inventory) == "table" and typeof(inventory.ById) == "table" and inventory.ById or {}

		for _, rawStackInstanceId in ipairs(stack.InstanceIds or {}) do
			local stackInstanceId = tostring(rawStackInstanceId or "")
			if stackInstanceId ~= "" and stackInstanceId ~= tostring(instanceId or "") then
				local stackInstanceData = byId[stackInstanceId]
				if typeof(stackInstanceData) == "table" then
					if valuesDiffer(representativeVariant, getInstanceVariant(stackInstanceData)) then
						details.MixedVariant = true
					end
					if valuesDiffer(representativeLevel, getInstanceLevel(stackInstanceData)) then
						details.MixedLevel = true
					end
					if valuesDiffer(representativeIncome, getInstanceIncome(stackInstanceData, info)) then
						details.MixedIncome = true
					end
				end
			end
		end
	end

	if state == "Equipped" then
		details.QuickSlotIndex = tonumber(instanceData.QuickSlotIndex)
	elseif state == "Placed" then
		details.AssignedStand = firstNonEmpty(instanceData.AssignedStand)
	elseif state == "Overflow" then
		details.OverflowReason = firstNonEmpty(instanceData.OverflowSource, "Protected overflow")
	end

	return details
end

local function buildMetadata(stack, inventory)
	local representative = stack.Representative
	local crewMemberId, info = resolveInfo(stack.CrewMemberId, representative)
	local displayInfo = CrewCatalog.GetDisplayInfo(crewMemberId, representative)
	local metadata = {
		CrewMemberId = crewMemberId,
		InstanceId = tostring(stack.RepresentativeInstanceId or ""),
		DisplayName = firstNonEmpty(displayInfo.DisplayName, info and (info.DisplayName or info.CrewMemberName or info.Name), crewMemberId),
		BaseDisplayName = firstNonEmpty(displayInfo.BaseDisplayName, displayInfo.DisplayName),
		Variant = firstNonEmpty(displayInfo.Variant, representative and representative.Variant),
		VariantTag = firstNonEmpty(displayInfo.VariantTag),
		VariantDisplayName = firstNonEmpty(displayInfo.VariantDisplayName),
		ShowVariantTag = displayInfo.ShowVariantTag == true,
		Rarity = firstNonEmpty(stack.Rarity, representative and representative.Rarity, info and info.Rarity),
		Render = firstNonEmpty(representative and representative.Render, info and info.Render),
		ModelName = firstNonEmpty(representative and representative.ModelName, info and info.ModelName),
		LegacyStorageName = firstNonEmpty(representative and representative.LegacyStorageName, info and info.LegacyId),
		ProductionName = firstNonEmpty(info and info.ProductionName),
		RealCharacterName = firstNonEmpty(info and info.RealCharacterName),
	}

	if metadata.InstanceId == "" and typeof(representative) == "table" then
		metadata.InstanceId = tostring(representative.InstanceId or "")
	end
	metadata.CrewDetails = buildCrewDetails(metadata.InstanceId, representative, info, "Stored", stack, inventory)

	return metadata, info
end

local function buildModelPreviewDescriptor(stack, metadata, info)
	local modelName = tostring(metadata.ModelName or "")
	if modelName == "" then
		return nil
	end

	if typeof(info) == "table" then
		if info.MissingCrewModel == true or info.ModelNameVerified ~= true then
			return nil
		end
	end

	return {
		ModelName = modelName,
		UsedCanonical = true,
		IsPreviewOnly = true,
		LegacyIdentity = tostring(stack.CrewMemberId or ""),
		Source = "CrewCatalog",
	}
end

local function buildSnapshot(player, inventory)
	local assignments = readQuickSlotAssignments(player)
	local stacks = CrewInventoryStacks.BuildAvailableStacks(inventory, {
		Assignments = assignments,
	})
	local counts = {}
	local representatives = {}

	for _, stack in ipairs(stacks) do
		local metadata, info = buildMetadata(stack, inventory)
		local modelPreview = buildModelPreviewDescriptor(stack, metadata, info)

		stack.Metadata = metadata
		stack.ModelPreview = modelPreview
		stack.InstanceIds = cloneArray(stack.InstanceIds)

		counts[stack.CrewMemberId] = (counts[stack.CrewMemberId] or 0) + stack.Quantity
		if representatives[stack.CrewMemberId] == nil then
			representatives[stack.CrewMemberId] = stack.Representative
		end
	end

	return {
		Inventory = inventory,
		QuickSlotAssignments = assignments,
		Stacks = stacks,
		Counts = counts,
		Representatives = representatives,
		BuiltAt = os.clock(),
	}
end

function CrewInventoryDerivedCache.MarkDirty(player, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local cache = getCache(player)
	cache.Dirty = true
	cache.Reason = tostring(reason or "dirty")
	cache.Version += 1
	cache.Snapshot = nil
end

function CrewInventoryDerivedCache.MarkSaved(player, inventory, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local cache = getCache(player)
	cache.Dirty = true
	cache.Inventory = inventory
	cache.Reason = tostring(reason or "inventory_saved")
	cache.Version += 1
	cache.Snapshot = nil
end

function CrewInventoryDerivedCache.Clear(player)
	cacheByPlayer[player] = nil
end

function CrewInventoryDerivedCache.Get(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return buildSnapshot(player, nil)
	end

	options = if typeof(options) == "table" then options else {}
	local cache = getCache(player)
	local inventory = options.Inventory
	if typeof(inventory) == "table" and typeof(inventory.ById) == "table" then
		if cache.Inventory ~= inventory then
			cache.Dirty = true
		end
		cache.Inventory = inventory
	end

	if cache.Dirty ~= true and cache.Snapshot ~= nil then
		return cache.Snapshot
	end

	inventory = if typeof(cache.Inventory) == "table" and typeof(cache.Inventory.ById) == "table"
		then cache.Inventory
		else readCrewInventory(player)

	local snapshot = buildSnapshot(player, inventory)
	snapshot.Version = cache.Version
	snapshot.Reason = cache.Reason
	cache.Inventory = inventory
	cache.Snapshot = snapshot
	cache.Dirty = false
	return snapshot
end

function CrewInventoryDerivedCache.GetStacks(player, options)
	return CrewInventoryDerivedCache.Get(player, options).Stacks
end

function CrewInventoryDerivedCache.GetCounts(player, options)
	local snapshot = CrewInventoryDerivedCache.Get(player, options)
	return snapshot.Counts, snapshot.Representatives
end

Players.PlayerRemoving:Connect(function(player)
	CrewInventoryDerivedCache.Clear(player)
end)

return CrewInventoryDerivedCache
