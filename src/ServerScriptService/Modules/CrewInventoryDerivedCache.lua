local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewInventoryStacks = require(Modules:WaitForChild("Crew"):WaitForChild("CrewInventoryStacks"))

local CrewInventoryDerivedCache = {}

local cacheByPlayer = setmetatable({}, { __mode = "k" })
local crewInstanceServiceModule = nil

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

local function buildMetadata(stack)
	local representative = stack.Representative
	local crewMemberId, info = resolveInfo(stack.CrewMemberId, representative)
	local metadata = {
		CrewMemberId = crewMemberId,
		InstanceId = tostring(stack.RepresentativeInstanceId or ""),
		DisplayName = firstNonEmpty(
			representative and representative.DisplayName,
			info and (info.DisplayName or info.CrewMemberName or info.Name),
			crewMemberId
		),
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

local function buildSnapshot(inventory)
	local stacks = CrewInventoryStacks.BuildAvailableStacks(inventory)
	local counts = {}
	local representatives = {}

	for _, stack in ipairs(stacks) do
		local metadata, info = buildMetadata(stack)
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
		return buildSnapshot(nil)
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

	local snapshot = buildSnapshot(inventory)
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
