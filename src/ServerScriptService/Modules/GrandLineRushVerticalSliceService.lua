local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BountyService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushBountyService"))
local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local GrandLineRushCrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushCrewCatalog"))
local CanonicalCrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewInteraction = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Server"):WaitForChild("Crew"):WaitForChild("Interaction"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ChestRewardResolver = require(ServerScriptService.Modules:WaitForChild("GrandLineRushChestRewardResolver"))
local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))
local AddCrewMember = require(ServerScriptService.Modules:WaitForChild("AddCrewMember"))
local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))

local Service = {}

local randomObject = Random.new()
local requestRemote
local stateRemote
local stateChangedEvent = Instance.new("BindableEvent")
local started = false
local runtimeByPlayer = {}
local deathConnections = {}
local CHEST_DEBUG = false
local DEBUG_TRACE = RunService:IsStudio() and game:GetAttribute("VerticalSliceDebugTrace") == true

local CARRY_TOOL_NAME = "GrandLineRushMajorReward"
local CHEST_TIER_ORDER = { "Wooden", "Iron", "Gold", "Legendary" }
local FORCED_DROP_PROTECTION_ATTRIBUTE = "GrandLineRushCarryDropProtectedUntil"
local FORCED_DROP_PROTECTION_DURATION = 0.9
local HORO_PROJECTION_CARRY_ATTRIBUTE = "HoroProjectionCarryProjectionId"
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local LEGACY_CARRIED_BRAINROT_ATTRIBUTE = "CarriedBrainrot"
local HORO_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local HORO_GHOSTS_FOLDER_NAME = "HoroGhosts"
local STARTER_CREW_SOURCE = "GrandLineRushStarter"
local CANONICAL_CREW_RARITY_ALIASES = {
	Mythical = "Mythic",
	Celestial = "Godly",
}
local canonicalCrewRewardPoolsByRarity = nil
local canonicalCrewRewardPool = nil

local function chestDebug(message, ...)
	if CHEST_DEBUG ~= true then
		return
	end

	warn(string.format("[GLR ChestDebug][Slice] " .. tostring(message), ...))
end

local function runTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[RUN TRACE] " .. message, ...))
end

local function hasCarriedCrewMember(player)
	local carried = player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE)
	if typeof(carried) == "string" and carried ~= "" then
		return true
	end

	carried = player:GetAttribute(LEGACY_CARRIED_BRAINROT_ATTRIBUTE)
	return typeof(carried) == "string" and carried ~= ""
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	return remotes
end

local function getOrCreateRemote(parent, className, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote.ClassName == className then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemotes()
	local remotesFolder = getOrCreateRemotesFolder()
	local remoteConfig = Economy.VerticalSlice.Remotes

	requestRemote = getOrCreateRemote(remotesFolder, "RemoteFunction", remoteConfig.RequestName)
	stateRemote = getOrCreateRemote(remotesFolder, "RemoteEvent", remoteConfig.StateEventName)
end

local function getRuntime(player)
	local runtime = runtimeByPlayer[player]
	if runtime then
		return runtime
	end

	runtime = {
		InRun = false,
		DepthBand = Economy.VerticalSlice.DefaultDepthBand,
		SpawnedReward = nil,
		CarriedReward = nil,
		ResolutionText = "Start a corridor run and bring a reward back to extract it.",
		RunSequence = 0,
	}
	runtimeByPlayer[player] = runtime
	return runtime
end

local function waitForDataReady(player, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 10)
	while os.clock() <= deadline do
		if DataManager:IsReady(player) then
			return true
		end
		task.wait(0.1)
	end

	return DataManager:IsReady(player)
end

local function getProfileAndReplica(player)
	if not waitForDataReady(player, 10) then
		return nil, nil
	end

	return DataManager:GetProfile(player), DataManager:GetReplica(player)
end

local function syncPaths(player, replica, changedPaths)
	if replica then
		for _, entry in ipairs(changedPaths) do
			replica:Set(entry.Path, entry.Value)
		end
	end

	DataManager:UpdateData(player)
end

local function buildRewardChangedPaths(dataRoot, changedRoots, options)
	local changedPaths = {}
	local settings = if typeof(options) == "table" then options else {}

	if changedRoots.FoodInventory then
		changedPaths[#changedPaths + 1] = { Path = { "FoodInventory" }, Value = dataRoot.FoodInventory }
	end
	if changedRoots.Materials then
		changedPaths[#changedPaths + 1] = { Path = { "Materials" }, Value = dataRoot.Materials }
	end
	if changedRoots.Leaderstats then
		changedPaths[#changedPaths + 1] = { Path = { "leaderstats", "Doubloons" }, Value = dataRoot.leaderstats.Doubloons }
	end
	if changedRoots.TotalStats then
		changedPaths[#changedPaths + 1] = { Path = { "TotalStats", "TotalDoubloons" }, Value = dataRoot.TotalStats.TotalDoubloons }
	end
	if changedRoots.InventoryDevilFruits then
		changedPaths[#changedPaths + 1] = { Path = { "Inventory", "DevilFruits" }, Value = ((dataRoot.Inventory or {}).DevilFruits) or {} }
	end
	if changedRoots.IndexCollectionDevilFruits then
		changedPaths[#changedPaths + 1] = { Path = { "IndexCollection", "DevilFruits" }, Value = ((dataRoot.IndexCollection or {}).DevilFruits) or {} }
	end
	if changedRoots.ChestRewards then
		changedPaths[#changedPaths + 1] = { Path = { "ChestRewards" }, Value = dataRoot.ChestRewards }
	end
	if changedRoots.UnopenedChests then
		changedPaths[#changedPaths + 1] = {
			Path = { "UnopenedChests" },
			Value = settings.UnopenedChests or dataRoot.UnopenedChests,
		}
	end

	return changedPaths
end

local function normalizeMaterialsTable(materials)
	if typeof(materials) ~= "table" then
		materials = {}
	end

	materials.Timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0)
	materials.Iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0)
	materials.AncientTimber = math.max(0, tonumber(materials.AncientTimber) or 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron

	return materials
end

local function getShipIncomeMultiplier(level)
	for _, band in ipairs(Economy.Crew.ShipIncomeMultiplierByLevelBand) do
		if level >= band.MinLevel and level <= band.MaxLevel then
			return band.Multiplier
		end
	end

	return 1
end

local function getCrewShipIncomePerHour(rarity, level)
	local baseIncome = Economy.Crew.ShipIncomePerHourByRarity[rarity] or 0
	return math.floor((baseIncome * getShipIncomeMultiplier(level)) + 0.5)
end

local function getCrewXPRequiredForLevel(rarity, level)
	if level >= Economy.Rules.CrewMaxLevel then
		return 0
	end

	local multiplier = Economy.Crew.TotalXPMultiplierByRarity[rarity] or 1
	for _, band in ipairs(Economy.Crew.BaseXPPerLevelBand) do
		if level >= band.MinLevel and level <= band.MaxLevel then
			return math.max(1, math.floor((band.XPPerLevel * multiplier) + 0.5))
		end
	end

	return math.max(1, math.floor(40 * multiplier))
end

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		if value ~= nil then
			local text = tostring(value)
			if text ~= "" then
				return text
			end
		end
	end
	return ""
end

local function getCrewSummaryStorageName(crewData, mirrorData)
	crewData = if typeof(crewData) == "table" then crewData else {}
	mirrorData = if typeof(mirrorData) == "table" then mirrorData else {}

	return firstNonEmpty(
		crewData.StorageName,
		crewData.LegacyStorageName,
		crewData.BrainrotName,
		mirrorData.StorageName,
		mirrorData.LegacyStorageName,
		mirrorData.BrainrotName,
		crewData.CrewMemberId,
		mirrorData.CrewMemberId,
		crewData.Name,
		mirrorData.Name
	)
end

local function getCrewSummaryDisplayName(crewData, mirrorData, storageName)
	crewData = if typeof(crewData) == "table" then crewData else {}
	mirrorData = if typeof(mirrorData) == "table" then mirrorData else {}

	local info = CanonicalCrewCatalog.GetInfoById(storageName)
	return firstNonEmpty(
		crewData.DisplayName,
		crewData.Name,
		mirrorData.DisplayName,
		mirrorData.Name,
		info and info.DisplayName,
		info and info.CrewMemberName,
		info and info.Name,
		storageName,
		"Unnamed Crew"
	)
end

local function getCrewSummaryNumber(primaryValue, mirrorValue, fallback)
	local value = tonumber(primaryValue)
	if value ~= nil then
		return value
	end

	value = tonumber(mirrorValue)
	if value ~= nil then
		return value
	end

	return fallback
end

local function getCrewSummarySource(crewData, mirrorData, isStarter, _preferCanonicalStarterSource)
	local source = firstNonEmpty(crewData.Source, mirrorData and mirrorData.Source)
	if source == "" and isStarter then
		return STARTER_CREW_SOURCE
	end
	return if source ~= "" then source else "Unknown"
end

local function isCrewSummaryStarter(crewData, mirrorData)
	crewData = if typeof(crewData) == "table" then crewData else {}
	mirrorData = if typeof(mirrorData) == "table" then mirrorData else {}

	local source = firstNonEmpty(crewData.Source, mirrorData.Source)
	return crewData.GrandLineRushStarter == true
		or mirrorData.GrandLineRushStarter == true
		or source == STARTER_CREW_SOURCE
end

local function buildCrewSummary(instanceId, crewData, mirrorData, options)
	options = if typeof(options) == "table" then options else {}
	crewData = if typeof(crewData) == "table" then crewData else {}
	mirrorData = if typeof(mirrorData) == "table" then mirrorData else {}

	local storageName = getCrewSummaryStorageName(crewData, mirrorData)
	local displayName = getCrewSummaryDisplayName(crewData, mirrorData, storageName)
	local isStarter = isCrewSummaryStarter(crewData, mirrorData)
	local source = getCrewSummarySource(crewData, mirrorData, isStarter, options.Canonical == true)
	local depthBand = firstNonEmpty(crewData.DepthBand, mirrorData.DepthBand)
	local level = math.max(1, math.floor(getCrewSummaryNumber(crewData.Level, mirrorData.Level, 1)))
	local currentXP = math.max(0, math.floor(getCrewSummaryNumber(crewData.CurrentXP, mirrorData.CurrentXP, 0)))
	local totalXP = math.max(0, math.floor(getCrewSummaryNumber(crewData.TotalXP, mirrorData.TotalXP, 0)))
	local rarity = firstNonEmpty(crewData.Rarity, mirrorData.Rarity, "Common")
	local canonicalInstanceId = firstNonEmpty(options.CanonicalInstanceId, crewData.CanonicalInstanceId)
	local legacyInstanceId = firstNonEmpty(options.LegacyInstanceId)

	return {
		InstanceId = tostring(instanceId),
		CanonicalInstanceId = canonicalInstanceId,
		LegacyInstanceId = legacyInstanceId,
		Name = displayName,
		DisplayName = displayName,
		StorageName = storageName,
		CrewMemberId = firstNonEmpty(crewData.CrewMemberId, mirrorData.CrewMemberId, storageName),
		Rarity = rarity,
		Level = level,
		CurrentXP = currentXP,
		TotalXP = totalXP,
		NextLevelXP = getCrewXPRequiredForLevel(rarity, level),
		ShipIncomePerHour = getCrewShipIncomePerHour(rarity, level),
		Source = source,
		DepthBand = depthBand,
		GrandLineRushStarter = isStarter,
	}
end

local function getCrewStateRecords(crewInventory)
	local records = {}
	if typeof(crewInventory) ~= "table" or typeof(crewInventory.ById) ~= "table" then
		return records
	end

	local seen = {}
	if typeof(crewInventory.Order) == "table" then
		for _, rawInstanceId in ipairs(crewInventory.Order) do
			local instanceId = tostring(rawInstanceId)
			local entry = crewInventory.ById[instanceId]
			if typeof(entry) == "table" then
				records[#records + 1] = {
					InstanceId = instanceId,
					Entry = entry,
				}
				seen[instanceId] = true
			end
		end
	end

	for rawInstanceId, entry in pairs(crewInventory.ById) do
		local instanceId = tostring(rawInstanceId)
		if seen[instanceId] ~= true and typeof(entry) == "table" then
			records[#records + 1] = {
				InstanceId = instanceId,
				Entry = entry,
			}
		end
	end

	return records
end

local function buildCrewStateSummaries(dataRoot)
	local canonicalRecords = getCrewStateRecords(dataRoot.CrewMemberInventory)
	local summaries = {}

	for _, record in ipairs(canonicalRecords) do
		summaries[#summaries + 1] = buildCrewSummary(record.InstanceId, record.Entry, nil, {
			CanonicalInstanceId = record.InstanceId,
			Canonical = true,
		})
	end

	return summaries
end

local function clearCarryTool(player)
	local backpack = player:FindFirstChild("Backpack")
	local character = player.Character

	for _, container in ipairs({ backpack, character }) do
		local tool = container and container:FindFirstChild(CARRY_TOOL_NAME)
		if tool and tool:IsA("Tool") then
			tool:Destroy()
		end
	end

	player:SetAttribute("CarriedMajorRewardType", nil)
	player:SetAttribute("CarriedMajorRewardDisplayName", nil)
	player:SetAttribute(FORCED_DROP_PROTECTION_ATTRIBUTE, nil)
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)
end

local function getRewardToolDisplay(reward)
	if reward.RewardType == "Chest" then
		return ChestUtils.GetDisplayName(reward)
	end

	return tostring(reward.CrewDisplayName or reward.DisplayName or reward.CrewName or "Crew Contract")
end

local function createCarryTool(player, reward)
	clearCarryTool(player)
	player:SetAttribute("CarriedMajorRewardType", reward.RewardType)
	player:SetAttribute("CarriedMajorRewardDisplayName", getRewardToolDisplay(reward))
	player:SetAttribute(FORCED_DROP_PROTECTION_ATTRIBUTE, os.clock() + FORCED_DROP_PROTECTION_DURATION)
end

local function cloneRewardData(reward)
	if not reward then
		return nil
	end

	local data = {
		RewardType = reward.RewardType,
		DepthBand = reward.DepthBand,
		DisplayName = reward.DisplayName,
		Source = reward.Source,
	}

	if reward.RewardType == "Chest" then
		data.ChestKind = reward.ChestKind
		data.Tier = reward.Tier
		data.FruitRarity = reward.FruitRarity
	else
		data.Rarity = reward.Rarity
		data.CanonicalRarity = reward.CanonicalRarity
		data.CrewName = reward.CrewName
		data.CrewDisplayName = reward.CrewDisplayName
		data.CrewStorageName = reward.CrewStorageName
		data.CrewMemberId = reward.CrewMemberId
	end

	if typeof(reward.WorldDropPosition) == "Vector3" then
		data.WorldDropPosition = reward.WorldDropPosition
	end

	return data
end

local function sanitizeReward(reward)
	local data = cloneRewardData(reward)
	if not data then
		return nil
	end

	data.DisplayName = getRewardToolDisplay(reward)
	return data
end

local function getBountyBreakdown(player)
	return BountyService.GetBreakdown(player)
end

local function chooseWeightedKey(weightTable, orderedKeys)
	local totalWeight = 0
	for _, key in ipairs(orderedKeys) do
		totalWeight += math.max(0, tonumber(weightTable[key]) or 0)
	end

	if totalWeight <= 0 then
		return orderedKeys[1]
	end

	local roll = randomObject:NextNumber(0, totalWeight)
	local cursor = 0
	for _, key in ipairs(orderedKeys) do
		cursor += math.max(0, tonumber(weightTable[key]) or 0)
		if roll <= cursor then
			return key
		end
	end

	return orderedKeys[#orderedKeys]
end

local function chooseChestTier(depthBand)
	local stage = Economy.VerticalSlice.ChestStageByDepthBand[depthBand] or Economy.VerticalSlice.ChestStageByDepthBand[Economy.VerticalSlice.DefaultDepthBand]
	local distribution = Economy.Chests.ExpectedTierDistributionByStage[stage] or Economy.Chests.ExpectedTierDistributionByStage.Mid
	return chooseWeightedKey(distribution, CHEST_TIER_ORDER)
end

local function buildCanonicalCrewRewardEntry(storageName, info)
	storageName = tostring(storageName or "")
	if storageName == "" or typeof(info) ~= "table" then
		return nil
	end

	local displayName = tostring(info.DisplayName or info.CrewMemberName or info.Name or info.CrewMemberId or storageName)
	return {
		StorageName = storageName,
		CrewMemberId = tostring(info.CrewMemberId or storageName),
		DisplayName = displayName,
		CanonicalRarity = tostring(info.Rarity or "Common"),
	}
end

local function getCanonicalCrewRewardPools()
	if canonicalCrewRewardPoolsByRarity ~= nil and canonicalCrewRewardPool ~= nil then
		return canonicalCrewRewardPoolsByRarity, canonicalCrewRewardPool
	end

	local poolsByRarity = {}
	local allEntries = {}
	for _, entry in ipairs(CanonicalCrewCatalog.GetBaseEntries()) do
		local rewardEntry = buildCanonicalCrewRewardEntry(entry.Id, entry.Info)
		if rewardEntry then
			local canonicalRarity = rewardEntry.CanonicalRarity
			poolsByRarity[canonicalRarity] = poolsByRarity[canonicalRarity] or {}
			table.insert(poolsByRarity[canonicalRarity], rewardEntry)
			table.insert(allEntries, rewardEntry)
		end
	end

	canonicalCrewRewardPoolsByRarity = poolsByRarity
	canonicalCrewRewardPool = allEntries
	return canonicalCrewRewardPoolsByRarity, canonicalCrewRewardPool
end

local function chooseCanonicalCrewRewardForRarity(rewardRarity)
	local requestedRarity = tostring(rewardRarity or "Common")
	local canonicalRarity = CANONICAL_CREW_RARITY_ALIASES[requestedRarity] or requestedRarity
	local poolsByRarity, allEntries = getCanonicalCrewRewardPools()
	local pool = poolsByRarity[canonicalRarity]
	if pool == nil or #pool == 0 then
		pool = allEntries
	end
	if pool == nil or #pool == 0 then
		return nil
	end

	local entry = pool[randomObject:NextInteger(1, #pool)]
	return {
		Rarity = requestedRarity,
		CanonicalRarity = entry.CanonicalRarity,
		Name = entry.DisplayName,
		DisplayName = entry.DisplayName,
		StorageName = entry.StorageName,
		CrewStorageName = entry.StorageName,
		CrewMemberId = entry.CrewMemberId,
	}
end

local function chooseCrewReward(depthBand)
	local distribution = Economy.Crew.RewardOddsByDepthBand[depthBand] or Economy.Crew.RewardOddsByDepthBand.Mid
	local rarity = chooseWeightedKey(distribution, Economy.Crew.RarityOrder)
	local canonicalReward = chooseCanonicalCrewRewardForRarity(rarity)
	if canonicalReward then
		return canonicalReward
	end

	return {
		Rarity = rarity,
		Name = GrandLineRushCrewCatalog.GetRandomNameForRarity(rarity, randomObject),
	}
end

local function ensureChestRewardsState(dataRoot)
	if typeof(dataRoot.ChestRewards) ~= "table" then
		dataRoot.ChestRewards = {}
	end

	dataRoot.ChestRewards.MythicKeys = math.max(0, tonumber(dataRoot.ChestRewards.MythicKeys) or 0)
	return dataRoot.ChestRewards
end

local function buildStoredChestEntry(chestData)
	local normalizedChest = ChestUtils.BuildChestData(chestData)
	return {
		ChestKind = normalizedChest.ChestKind,
		Tier = normalizedChest.Tier,
		FruitRarity = normalizedChest.FruitRarity,
		DepthBand = tostring(normalizedChest.DepthBand or ""),
		Source = tostring(normalizedChest.Source or ChestRewards.DefaultChestSource),
		RewardProfile = tostring(normalizedChest.RewardProfile or ChestRewards.DefaultRewardProfile),
		CreatedAt = math.max(0, tonumber(normalizedChest.CreatedAt) or os.time()),
	}
end

local function addUnopenedChestToCollection(unopenedChests, chestData)
	unopenedChests.Order = unopenedChests.Order or {}
	unopenedChests.ById = unopenedChests.ById or {}
	unopenedChests.NextChestId = math.max(1, tonumber(unopenedChests.NextChestId) or 1)

	local chestId = tostring(unopenedChests.NextChestId)
	unopenedChests.NextChestId += 1

	local storedChest = buildStoredChestEntry(chestData)
	storedChest.ChestId = chestId
	unopenedChests.ById[chestId] = storedChest
	table.insert(unopenedChests.Order, chestId)

	return chestId, storedChest
end

local function countUnopenedChestsByInventoryName(unopenedChests, chestData)
	local inventoryName = ChestUtils.GetInventoryName(chestData)
	local count = 0

	for _, existingChestId in ipairs(unopenedChests.Order or {}) do
		local entry = unopenedChests.ById and unopenedChests.ById[tostring(existingChestId)]
		if entry and ChestUtils.GetInventoryName(entry) == inventoryName then
			count += 1
		end
	end

	return count
end

local ensureStarterCrew

local function resolveCanonicalCrewGrantData(rewardData, options)
	rewardData = if typeof(rewardData) == "table" then rewardData else {}
	options = if typeof(options) == "table" then options else {}

	local storageName = tostring(rewardData.StorageName or rewardData.CrewStorageName or "")
	local displayName = tostring(rewardData.CrewDisplayName or rewardData.DisplayName or rewardData.Name or storageName)
	local crewMemberId = tostring(rewardData.CrewMemberId or "")
	local info = nil

	if storageName ~= "" then
		info = CanonicalCrewCatalog.GetInfoById(storageName)
	end
	if not info and crewMemberId ~= "" then
		info = CanonicalCrewCatalog.GetInfoById(crewMemberId)
	end
	if not info and displayName ~= "" then
		info = CanonicalCrewCatalog.GetInfoById(displayName)
	end

	if info then
		storageName = tostring(info.LegacyId or storageName)
	elseif options.AllowFallback ~= false then
		local fallback = chooseCanonicalCrewRewardForRarity(rewardData.Rarity)
		if fallback then
			storageName = fallback.StorageName
			displayName = fallback.DisplayName
			crewMemberId = fallback.CrewMemberId
			info = CanonicalCrewCatalog.GetInfoById(storageName)
		end
	end

	if not info or storageName == "" then
		return nil
	end

	if displayName == "" then
		displayName = tostring(info.DisplayName or info.CrewMemberName or info.Name or crewMemberId or storageName)
	end
	if crewMemberId == "" then
		crewMemberId = tostring(info.CrewMemberId or storageName)
	end

	return {
		StorageName = storageName,
		DisplayName = displayName,
		CrewMemberId = crewMemberId,
		CanonicalRarity = tostring(info.Rarity or "Common"),
	}
end

local function countCanonicalCrewEntries(player)
	local inventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return 0
	end

	local count = 0
	for _, instanceData in pairs(inventory.ById) do
		if typeof(instanceData) == "table" then
			count += 1
		end
	end
	return count
end

local function findCanonicalStarterCrewInstance(player)
	local inventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return nil, nil
	end

	for _, rawInstanceId in ipairs(inventory.Order or {}) do
		local instanceId = tostring(rawInstanceId)
		local instanceData = inventory.ById[instanceId]
		if typeof(instanceData) == "table"
			and (
				instanceData.GrandLineRushStarter == true
				or tostring(instanceData.Source or "") == STARTER_CREW_SOURCE
			)
		then
			return instanceId, instanceData
		end
	end

	for instanceId, instanceData in pairs(inventory.ById) do
		if typeof(instanceData) == "table"
			and (
				instanceData.GrandLineRushStarter == true
				or tostring(instanceData.Source or "") == STARTER_CREW_SOURCE
			)
		then
			return tostring(instanceId), instanceData
		end
	end

	return nil, nil
end

local function stampCanonicalStarterMetadata(player, canonicalInstanceId, legacyEntry)
	canonicalInstanceId = tostring(canonicalInstanceId or "")
	if canonicalInstanceId == "" then
		return nil, nil
	end

	local resolvedInstanceId, canonicalEntry, canonicalInventory = CrewInstanceService.GetInstance(player, canonicalInstanceId)
	if typeof(canonicalEntry) ~= "table" or typeof(canonicalInventory) ~= "table" then
		return nil, nil
	end

	legacyEntry = if typeof(legacyEntry) == "table" then legacyEntry else {}
	local changed = false
	if tostring(canonicalEntry.Source or "") ~= STARTER_CREW_SOURCE then
		canonicalEntry.Source = STARTER_CREW_SOURCE
		changed = true
	end
	if canonicalEntry.GrandLineRushStarter ~= true then
		canonicalEntry.GrandLineRushStarter = true
		changed = true
	end
	if canonicalEntry.TotalXP == nil and legacyEntry.TotalXP ~= nil then
		canonicalEntry.TotalXP = math.max(0, math.floor(tonumber(legacyEntry.TotalXP) or 0))
		changed = true
	end
	if tostring(canonicalEntry.DepthBand or "") == "" and tostring(legacyEntry.DepthBand or "") ~= "" then
		canonicalEntry.DepthBand = tostring(legacyEntry.DepthBand)
		changed = true
	end

	if changed then
		local saveOk, saveReason = CrewInstanceService.SaveCrewInventory(player, canonicalInventory, {
			SourcePath = "grand_line_rush_starter_metadata_stamp",
		})
		if saveOk ~= true then
			warn(string.format(
				"[GrandLineRush] Starter metadata stamp failed player=%s canonicalId=%s reason=%s",
				player and player.Name or "unknown",
				tostring(resolvedInstanceId),
				tostring(saveReason or "unknown")
			))
		else
			local updatedInstanceId, updatedEntry = CrewInstanceService.GetInstance(player, resolvedInstanceId)
			return updatedInstanceId, updatedEntry
		end
	end

	return resolvedInstanceId, canonicalEntry
end

local function buildGrantDataFromCanonical(instanceData)
	if typeof(instanceData) ~= "table" then
		return nil
	end

	local storageName = tostring(instanceData.StorageName or instanceData.LegacyStorageName or "")
	if storageName == "" then
		return nil
	end

	local info = CanonicalCrewCatalog.GetInfoById(storageName)
	local displayName = tostring(
		instanceData.DisplayName
			or (info and (info.DisplayName or info.CrewMemberName or info.Name))
			or storageName
	)
	return {
		StorageName = storageName,
		DisplayName = displayName,
		CrewMemberId = tostring(instanceData.CrewMemberId or (info and info.CrewMemberId) or storageName),
		CanonicalRarity = tostring(instanceData.Rarity or (info and info.Rarity) or "Common"),
	}
end

local function grantCanonicalCrewMember(player, rewardData, source, options)
	options = if typeof(options) == "table" then options else {}
	rewardData = if typeof(rewardData) == "table" then rewardData else {}

	local grantData = resolveCanonicalCrewGrantData(rewardData)
	if grantData == nil then
		return nil, nil, nil
	end

	local ok, createdIds = AddCrewMember:AddCrewMember(player, grantData.StorageName, 1, {
		Source = source or tostring(rewardData.Source or "GrandLineRush"),
		DepthBand = tostring(rewardData.DepthBand or ""),
		TotalXP = math.max(0, math.floor(tonumber(rewardData.TotalXP) or 0)),
		GrandLineRushStarter = options.GrandLineRushStarter == true or rewardData.GrandLineRushStarter == true,
		_QuickSlotCapacityReserved = options.BypassCapacity == true,
	})
	if ok ~= true then
		return nil, nil, grantData
	end

	local canonicalInstanceId = if typeof(createdIds) == "table" then tostring(createdIds[1] or "") else ""
	if canonicalInstanceId == "" then
		return nil, nil, grantData
	end

	local canonicalInventory = CrewInstanceService.GetCrewInventory(player)
	return canonicalInstanceId, canonicalInventory.ById[canonicalInstanceId], grantData
end

local function addCrewInstance(player, rewardData, source)
	local profile = getProfileAndReplica(player)
	if not profile then
		return nil
	end

	local grantSource = source or "GrandLineRush"
	local canonicalInstanceId = grantCanonicalCrewMember(player, rewardData, grantSource)
	if canonicalInstanceId == nil then
		return nil
	end

	return canonicalInstanceId
end

ensureStarterCrew = function(player)
	local profile = getProfileAndReplica(player)
	if not profile then
		return
	end

	local starterConfig = Economy.VerticalSlice.StarterCrew or {}
	if starterConfig.Enabled ~= true then
		return
	end

	local canonicalStarterId, canonicalStarterEntry = findCanonicalStarterCrewInstance(player)
	if canonicalStarterId and canonicalStarterEntry then
		stampCanonicalStarterMetadata(player, canonicalStarterId, canonicalStarterEntry)
		return
	end

	if countCanonicalCrewEntries(player) > 0 then
		return
	end

	local rewardData = {
		Name = starterConfig.Name,
		DisplayName = starterConfig.Name,
		Rarity = starterConfig.Rarity or "Common",
		Source = STARTER_CREW_SOURCE,
		GrandLineRushStarter = true,
	}
	local canonicalInstanceId, canonicalEntry, grantData = grantCanonicalCrewMember(player, rewardData, STARTER_CREW_SOURCE, {
		BypassCapacity = true,
		GrandLineRushStarter = true,
	})
	if canonicalInstanceId == nil or grantData == nil then
		warn(string.format(
			"[GrandLineRush] Starter crew grant failed player=%s starter=%s",
			player and player.Name or "unknown",
			tostring(starterConfig.Name or "")
		))
		return
	end
	stampCanonicalStarterMetadata(player, canonicalInstanceId, canonicalEntry)
end

local function addUnopenedChest(player, chestInfoOrTier, depthBand)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		chestDebug("addUnopenedChest skipped for %s because profile/replica missing.", player and player.Name or "unknown")
		return nil
	end

	local unopenedChests = profile.Data.UnopenedChests
	local normalizedChest = if typeof(chestInfoOrTier) == "table"
		then ChestUtils.BuildChestData(chestInfoOrTier)
		else ChestUtils.BuildChestData({
			ChestKind = ChestRewards.ChestKinds.Standard,
			Tier = chestInfoOrTier,
			DepthBand = depthBand,
			Source = "Run",
		})

	local chestId, storedChest = addUnopenedChestToCollection(unopenedChests, normalizedChest)
	local inventoryQuantity = countUnopenedChestsByInventoryName(unopenedChests, storedChest)

	chestDebug(
		"addUnopenedChest player=%s inventoryName=%s tier=%s fruitRarity=%s depth=%s newChestId=%s quantity=%d totalOrder=%d",
		player.Name,
		ChestUtils.GetInventoryName(storedChest),
		tostring(storedChest.Tier),
		tostring(storedChest.FruitRarity),
		tostring(storedChest.DepthBand),
		tostring(chestId),
		inventoryQuantity,
		#unopenedChests.Order
	)

	syncPaths(player, replica, {
		{ Path = { "UnopenedChests" }, Value = unopenedChests },
	})

	return chestId
end

local function buildState(player)
	local profile, _ = getProfileAndReplica(player)
	local runtime = getRuntime(player)

	if not profile then
		return {
			Run = {
				InRun = runtime.InRun,
				DepthBand = runtime.DepthBand,
				SpawnedReward = sanitizeReward(runtime.SpawnedReward),
				CarriedReward = sanitizeReward(runtime.CarriedReward),
				ResolutionText = runtime.ResolutionText,
			},
		}
	end

	local dataRoot = profile.Data
	local unopenedChests = dataRoot.UnopenedChests or {}
	local chestRewardsState = ensureChestRewardsState(dataRoot)
	local foodInventory = dataRoot.FoodInventory or {}
	local materials = normalizeMaterialsTable(dataRoot.Materials)
	local leaderstats = dataRoot.leaderstats or {}
	local devilFruits = ((dataRoot.Inventory or {}).DevilFruits) or {}

	local chestSummaries = {}
	for _, chestId in ipairs(unopenedChests.Order or {}) do
		local entry = unopenedChests.ById and unopenedChests.ById[tostring(chestId)]
		if entry then
			local normalizedChest = ChestUtils.BuildChestData(entry)
			chestSummaries[#chestSummaries + 1] = {
				ChestId = tostring(chestId),
				ChestKind = normalizedChest.ChestKind,
				Tier = normalizedChest.Tier,
				FruitRarity = normalizedChest.FruitRarity,
				DepthBand = tostring(entry.DepthBand or ""),
				Source = tostring(entry.Source or ChestRewards.DefaultChestSource),
				RewardProfile = tostring(entry.RewardProfile or ChestRewards.DefaultRewardProfile),
				CreatedAt = math.max(0, tonumber(entry.CreatedAt) or 0),
				InventoryName = ChestUtils.GetInventoryName(normalizedChest),
				DisplayName = ChestUtils.GetDisplayName(normalizedChest),
			}
		end
	end

	local crewSummaries = buildCrewStateSummaries(dataRoot)

	local devilFruitCount = 0
	for _, fruitEntry in pairs(devilFruits) do
		if typeof(fruitEntry) == "table" then
			devilFruitCount += math.max(0, tonumber(fruitEntry.Quantity) or 0)
		end
	end

	return {
		Doubloons = tonumber(leaderstats.Doubloons) or 0,
		Bounty = getBountyBreakdown(player),
		Run = {
			InRun = runtime.InRun,
			DepthBand = runtime.DepthBand,
			SpawnedReward = sanitizeReward(runtime.SpawnedReward),
			CarriedReward = sanitizeReward(runtime.CarriedReward),
			ResolutionText = runtime.ResolutionText,
		},
		UnopenedChests = chestSummaries,
		UnopenedChestCount = #chestSummaries,
		MythicKeyProgress = {
			current = chestRewardsState.MythicKeys,
			threshold = ChestRewards.MythicKey.Threshold,
		},
		FoodInventory = {
			Apple = tonumber(foodInventory.Apple) or 0,
			Rice = tonumber(foodInventory.Rice) or 0,
			Meat = tonumber(foodInventory.Meat) or 0,
			SeaBeastMeat = tonumber(foodInventory.SeaBeastMeat) or 0,
		},
		Materials = {
			Timber = tonumber(materials.Timber) or 0,
			Iron = tonumber(materials.Iron) or 0,
			AncientTimber = tonumber(materials.AncientTimber) or 0,
			CommonShipMaterial = tonumber(materials.Timber) or 0,
			RareShipMaterial = tonumber(materials.Iron) or 0,
		},
		DevilFruitCount = devilFruitCount,
		Crews = crewSummaries,
	}
end

local function pushState(player)
	local state = buildState(player)
	if stateRemote and player.Parent == Players then
		stateRemote:FireClient(player, state)
	end
	stateChangedEvent:Fire(player, state)
end

local function resolveActionResponse(player, ok, message, errorCode)
	local state = buildState(player)
	if stateRemote and player.Parent == Players then
		stateRemote:FireClient(player, state)
	end
	stateChangedEvent:Fire(player, state)

	return {
		ok = ok,
		message = message,
		error = errorCode,
		state = state,
	}
end

local function preparePlayerState(player)
	if not waitForDataReady(player, 10) then
		return false, resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	ensureStarterCrew(player)
	return true
end

function Service.FailRun(player, reason)
	local runtime = getRuntime(player)
	if runtime.InRun ~= true and runtime.CarriedReward == nil and runtime.SpawnedReward == nil then
		return resolveActionResponse(player, false, nil, "not_in_run")
	end

	runtime.InRun = false
	runtime.SpawnedReward = nil
	runtime.CarriedReward = nil
	runtime.ResolutionText = reason or "Run failed. Unextracted rewards were lost."
	clearCarryTool(player)

	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function startRun(player, rewardType, depthBand)
	local runtime = getRuntime(player)
	if runtime.InRun then
		return resolveActionResponse(player, false, nil, "run_already_active")
	end
	if runtime.CarriedReward ~= nil then
		return resolveActionResponse(player, false, "Extract or lose your carried reward before starting a new run.", "already_carrying_reward")
	end
	if runtime.SpawnedReward ~= nil then
		return resolveActionResponse(player, false, "Recover or lose your dropped reward before starting a new run.", "unresolved_spawned_reward")
	end

	if tostring(rewardType or "Chest") == "Chest" then
		return resolveActionResponse(player, false, "Chests are shared corridor rewards and no longer start as private runs.", "chests_are_shared_world_rewards")
	end

	runtime.InRun = true
	runtime.DepthBand = depthBand or Economy.VerticalSlice.DefaultDepthBand
	runtime.CarriedReward = nil
	runtime.RunSequence += 1

	if rewardType == "Crew" then
		local crewReward = chooseCrewReward(runtime.DepthBand)
		runtime.SpawnedReward = {
			RewardType = "Crew",
			CrewName = crewReward.Name,
			CrewDisplayName = crewReward.DisplayName,
			CrewStorageName = crewReward.CrewStorageName or crewReward.StorageName,
			CrewMemberId = crewReward.CrewMemberId,
			Rarity = crewReward.Rarity,
			CanonicalRarity = crewReward.CanonicalRarity,
			DepthBand = runtime.DepthBand,
		}
	else
		runtime.SpawnedReward = {
			RewardType = "Chest",
			Tier = chooseChestTier(runtime.DepthBand),
			DepthBand = runtime.DepthBand,
		}
	end

	runtime.ResolutionText = string.format(
		"%s reward spawned for the run. Pick it up, then extract it at base.",
		getRewardToolDisplay(runtime.SpawnedReward)
	)
	clearCarryTool(player)

	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function claimSpawnedReward(player)
	local runtime = getRuntime(player)
	if runtime.SpawnedReward == nil then
		if runtime.InRun ~= true then
			return resolveActionResponse(player, false, nil, "not_in_run")
		end
		return resolveActionResponse(player, false, nil, "no_spawned_reward")
	end
	if runtime.CarriedReward ~= nil then
		return resolveActionResponse(player, false, nil, "already_carrying_reward")
	end

	runtime.CarriedReward = cloneRewardData(runtime.SpawnedReward)
	runtime.CarriedReward.WorldDropPosition = nil
	runtime.SpawnedReward = nil
	runtime.ResolutionText = string.format(
		"Carrying %s. Extract successfully to secure it.",
		getRewardToolDisplay(runtime.CarriedReward)
	)

	createCarryTool(player, runtime.CarriedReward)
	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function extractRun(player)
	local runtime = getRuntime(player)
	if runtime.CarriedReward == nil then
		if runtime.InRun ~= true then
			return resolveActionResponse(player, false, nil, "not_in_run")
		end
		return resolveActionResponse(player, false, nil, "no_carried_reward")
	end

	local carriedReward = runtime.CarriedReward
	local message
	runTrace(
		"sliceExtractBegin player=%s carriedType=%s tier=%s crew=%s inRun=%s",
		player.Name,
		tostring(carriedReward and carriedReward.RewardType),
		tostring(carriedReward and carriedReward.Tier),
		tostring(carriedReward and carriedReward.CrewName),
		tostring(runtime.InRun)
	)
	chestDebug(
		"extractRun success path player=%s carriedType=%s inRun=%s",
		player.Name,
		tostring(carriedReward and carriedReward.RewardType),
		tostring(runtime.InRun)
	)

	if carriedReward.RewardType == "Chest" then
		chestDebug(
			"extractRun calling addUnopenedChest player=%s tier=%s depth=%s",
			player.Name,
			tostring(carriedReward.Tier),
			tostring(carriedReward.DepthBand)
		)
		local chestId = addUnopenedChest(player, carriedReward.Tier, carriedReward.DepthBand)
		if chestId == nil then
			runTrace(
				"sliceExtractFailed player=%s reason=persist_chest_failed carriedType=%s tier=%s",
				player.Name,
				tostring(carriedReward.RewardType),
				tostring(carriedReward.Tier)
			)
			return resolveActionResponse(player, false, nil, "persist_chest_failed")
		end
		runTrace(
			"sliceExtractPersistedChest player=%s tier=%s chestId=%s depth=%s action=add_to_inventory_state",
			player.Name,
			tostring(carriedReward.Tier),
			tostring(chestId),
			tostring(carriedReward.DepthBand)
		)
		message = string.format(
			"Extracted %s and stored it in Treasure as chest #%s.",
			getRewardToolDisplay(carriedReward),
			tostring(chestId or "?")
		)
	else
		local instanceId = addCrewInstance(player, {
			Name = carriedReward.CrewName,
			DisplayName = carriedReward.CrewDisplayName or carriedReward.CrewName,
			StorageName = carriedReward.CrewStorageName,
			CrewMemberId = carriedReward.CrewMemberId,
			Rarity = carriedReward.Rarity,
			CanonicalRarity = carriedReward.CanonicalRarity,
			DepthBand = carriedReward.DepthBand,
		}, "GrandLineRush")
		if instanceId == nil then
			runTrace(
				"sliceExtractFailed player=%s reason=persist_crew_failed carriedType=%s crew=%s",
				player.Name,
				tostring(carriedReward.RewardType),
				tostring(carriedReward.CrewName)
			)
			return resolveActionResponse(player, false, nil, "persist_crew_failed")
		end
		runTrace(
			"sliceExtractPersistedCrew player=%s crew=%s rarity=%s instanceId=%s",
			player.Name,
			tostring(carriedReward.CrewName),
			tostring(carriedReward.Rarity),
			tostring(instanceId)
		)
		message = string.format("Extracted crew reward and recruited %s (%s) as crew #%s.", tostring(carriedReward.CrewName), tostring(carriedReward.Rarity), tostring(instanceId or "?"))
	end

	QuestSignals.Record(player, "ReachDepth", 1, {
		DepthBand = tostring(carriedReward.DepthBand or ""),
		RewardType = tostring(carriedReward.RewardType or ""),
	})
	if carriedReward.RewardType == "Crew" then
		QuestSignals.Record(player, "ExtractCrew", 1, {
			DepthBand = tostring(carriedReward.DepthBand or ""),
			Rarity = tostring(carriedReward.Rarity or ""),
			CrewName = tostring(carriedReward.CrewName or ""),
		})
	end

	local extractionBounty, _ = BountyService.AwardExtractionBountyForReward(player, carriedReward)
	if extractionBounty > 0 then
		message = string.format(
			"%s (+%s Bounty)",
			message,
			BountyService.FormatNumber(extractionBounty)
		)
	elseif carriedReward.RewardType == "Chest" or carriedReward.RewardType == "Crew" then
		warn(string.format(
			"[GrandLineRushBounty] Extracted reward granted no bounty player=%s type=%s tier=%s rarity=%s",
			player.Name,
			tostring(carriedReward.RewardType),
			tostring(carriedReward.Tier),
			tostring(carriedReward.Rarity)
		))
	end

	runtime.InRun = false
	runtime.SpawnedReward = nil
	runtime.CarriedReward = nil
	runtime.ResolutionText = message
	clearCarryTool(player)
	runTrace(
		"sliceExtractComplete player=%s message=%s inRun=%s carriedAfter=%s",
		player.Name,
		tostring(message),
		tostring(runtime.InRun),
		tostring(runtime.CarriedReward ~= nil)
	)

	return resolveActionResponse(player, true, message)
end

local function claimWorldChest(player, rewardData)
	local runtime = getRuntime(player)
	if runtime.InRun == true then
		return resolveActionResponse(player, false, "Finish your current run before claiming a shared chest.", "run_already_active")
	end
	if runtime.SpawnedReward ~= nil then
		return resolveActionResponse(player, false, "Recover or lose your dropped reward before claiming another chest.", "unresolved_spawned_reward")
	end
	if runtime.CarriedReward ~= nil then
		return resolveActionResponse(player, false, nil, "already_carrying_reward")
	end
	if hasCarriedCrewMember(player) then
		return resolveActionResponse(player, false, "You cannot pick up a chest while carrying a Crewmate.", "carrying_brainrot")
	end

	local tierName = tostring(rewardData and rewardData.Tier or "Wooden")
	if Economy.Chests.Tiers[tierName] == nil then
		return resolveActionResponse(player, false, nil, "invalid_chest_tier")
	end

	local depthBand = tostring(rewardData and rewardData.DepthBand or Economy.VerticalSlice.DefaultDepthBand)
	runtime.DepthBand = depthBand
	runtime.SpawnedReward = nil
	runtime.CarriedReward = {
		RewardType = "Chest",
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = tierName,
		DepthBand = depthBand,
		Source = "SharedWorld",
	}
	runtime.ResolutionText = string.format(
		"Carrying %s. Extract successfully to secure it.",
		getRewardToolDisplay(runtime.CarriedReward)
	)

	createCarryTool(player, runtime.CarriedReward)
	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function canForceCarryDrop(player, runtime, options)
	runtime = runtime or getRuntime(player)
	if runtime.CarriedReward == nil then
		return false, "no_carried_reward"
	end

	local settings = if typeof(options) == "table" then options else {}
	local protectedUntil = player:GetAttribute(FORCED_DROP_PROTECTION_ATTRIBUTE)
	if settings.IgnoreProtection ~= true and typeof(protectedUntil) == "number" and protectedUntil > os.clock() then
		return false, "carry_drop_protected"
	end

	return true, nil
end

local function getActiveHoroDropRootPart(player)
	if not player or player.Parent ~= Players then
		return nil
	end
	if player:GetAttribute("HoroProjectionActive") ~= true then
		return nil
	end

	local projectionId = player:GetAttribute("HoroProjectionId")
	if typeof(projectionId) ~= "string" or projectionId == "" then
		return nil
	end

	local effectsFolder = Workspace:FindFirstChild(HORO_EFFECTS_FOLDER_NAME)
	local ghostsFolder = effectsFolder and effectsFolder:FindFirstChild(HORO_GHOSTS_FOLDER_NAME)
	if not ghostsFolder then
		return nil
	end

	for _, ghostModel in ipairs(ghostsFolder:GetChildren()) do
		if ghostModel:IsA("Model")
			and ghostModel:GetAttribute("ProjectionId") == projectionId
			and tonumber(ghostModel:GetAttribute("OwnerUserId")) == player.UserId
		then
			local rootPart = ghostModel:FindFirstChild("HumanoidRootPart")
				or ghostModel.PrimaryPart
				or ghostModel:FindFirstChild("Head", true)
				or ghostModel:FindFirstChild("UpperTorso", true)
				or ghostModel:FindFirstChild("Torso", true)
				or ghostModel:FindFirstChildWhichIsA("BasePart", true)
			if rootPart and rootPart:IsA("BasePart") and rootPart.Parent then
				return rootPart
			end
		end
	end

	return nil
end

local function getCharacterDropRootPart(player)
	local character = player and player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
		or character.PrimaryPart
		or character:FindFirstChild("Head")
end

local function getManualDropPosition(player)
	local rootPart = getActiveHoroDropRootPart(player) or getCharacterDropRootPart(player)
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil
	end

	local lookVector = rootPart.CFrame.LookVector
	local flatDirection = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatDirection.Magnitude < 1e-4 then
		flatDirection = Vector3.new(0, 0, -1)
	else
		flatDirection = flatDirection.Unit
	end

	return rootPart.Position + (flatDirection * 5)
end

local function dropCarriedReward(player, options)
	local runtime = getRuntime(player)
	options = if typeof(options) == "table" then options else {}
	local canDrop, reason = canForceCarryDrop(player, runtime, options)
	if not canDrop then
		return resolveActionResponse(player, false, nil, reason)
	end

	local droppedReward = cloneRewardData(runtime.CarriedReward)
	if not droppedReward then
		return resolveActionResponse(player, false, nil, "missing_carried_reward")
	end

	local dropPosition = options.DropPosition
	if typeof(dropPosition) == "Vector3" then
		droppedReward.WorldDropPosition = dropPosition
	end

	runtime.SpawnedReward = droppedReward
	runtime.CarriedReward = nil
	runtime.ResolutionText = string.format(
		"%s was dropped. Recover it before extracting.",
		getRewardToolDisplay(droppedReward)
	)
	clearCarryTool(player)

	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function dropCarriedCrewMember(player, dropPosition)
	local ok, result = CrewInteraction.DropHeldAtPosition(CrewInteraction.GetActiveContext(), player, nil, dropPosition)
	if ok then
		return resolveActionResponse(player, true, "Crewmate dropped.")
	end

	return resolveActionResponse(player, false, nil, tostring(result or "no_held_brainrot"))
end

local function openChest(player, requestedChestId)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local dataRoot = profile.Data
	local unopenedChests = dataRoot.UnopenedChests
	unopenedChests.Order = unopenedChests.Order or {}
	unopenedChests.ById = unopenedChests.ById or {}

	local chestId = requestedChestId and tostring(requestedChestId) or tostring(unopenedChests.Order[1] or "")
	if chestId == "" then
		return resolveActionResponse(player, false, nil, "no_chests_available")
	end

	local chestData = unopenedChests.ById[chestId]
	if typeof(chestData) ~= "table" then
		return resolveActionResponse(player, false, nil, "missing_chest")
	end

	local normalizedChestData = ChestUtils.BuildChestData(chestData)
	local tierName = normalizedChestData.Tier
	local tierConfig = Economy.Chests.Tiers[tierName]
	if not tierConfig then
		return resolveActionResponse(player, false, nil, "invalid_chest_tier")
	end

	local resolution = ChestRewardResolver.Resolve({
		Player = player,
		DataRoot = dataRoot,
		ChestData = normalizedChestData,
		Random = randomObject,
		AddChestEntry = function(grantedChestData)
			local grantedChestId = addUnopenedChestToCollection(unopenedChests, grantedChestData)
			return grantedChestId
		end,
	})

	unopenedChests.ById[chestId] = nil
	for index = #unopenedChests.Order, 1, -1 do
		if tostring(unopenedChests.Order[index]) == chestId then
			table.remove(unopenedChests.Order, index)
			break
		end
	end
	local changedRoots = resolution.ChangedRoots or {}
	changedRoots.UnopenedChests = true

	local changedPaths = buildRewardChangedPaths(dataRoot, changedRoots, {
		UnopenedChests = unopenedChests,
	})

	syncPaths(player, replica, changedPaths)

	local rewardParts = {}
	local grantedResources = (resolution.OpenResult and resolution.OpenResult.GrantedResources) or {}
	QuestSignals.Record(player, "OpenChest", 1, {
		Tier = tostring(tierName or ""),
		ChestKind = tostring(normalizedChestData.ChestKind or ""),
		FruitRarity = tostring(normalizedChestData.FruitRarity or ""),
	})
	if math.max(0, tonumber(grantedResources.doubloons) or 0) > 0 then
		QuestSignals.Record(player, "EarnDoubloons", grantedResources.doubloons, {
			Source = "Chest",
			Tier = tostring(tierName or ""),
		})
	end
	for foodKey, amount in pairs(grantedResources.food or {}) do
		local normalizedAmount = math.max(0, tonumber(amount) or 0)
		if normalizedAmount > 0 then
			QuestSignals.Record(player, "CollectFood", normalizedAmount, {
				Key = tostring(foodKey),
				FoodKey = tostring(foodKey),
				Source = "Chest",
			})
		end
	end
	for materialKey, amount in pairs(grantedResources.materials or {}) do
		local normalizedAmount = math.max(0, tonumber(amount) or 0)
		if normalizedAmount > 0 then
			QuestSignals.Record(player, "CollectMaterial", normalizedAmount, {
				Key = tostring(materialKey),
				MaterialKey = tostring(materialKey),
				Source = "Chest",
			})
		end
	end

	for foodKey, amount in pairs(grantedResources.food or {}) do
		rewardParts[#rewardParts + 1] = string.format("%dx %s", amount, Economy.Food[foodKey].DisplayName)
	end
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder) do
		local amount = math.max(0, tonumber((grantedResources.materials or {})[materialKey]) or 0)
		if amount > 0 then
			rewardParts[#rewardParts + 1] = string.format(
				"%dx %s",
				amount,
				tostring(PlotUpgradeConfig.MaterialDisplayNames[materialKey] or materialKey)
			)
		end
	end
	if math.max(0, tonumber(grantedResources.doubloons) or 0) > 0 then
		rewardParts[#rewardParts + 1] = string.format("%d Doubloons", grantedResources.doubloons)
	end
	if resolution.RewardText then
		rewardParts[#rewardParts + 1] = tostring(resolution.RewardText)
	end

	local chestDisplayName = ChestUtils.GetDisplayName(normalizedChestData)
	local message = if #rewardParts > 0
		then string.format("Opened %s and received %s.", chestDisplayName, table.concat(rewardParts, ", "))
		else string.format("Opened %s.", chestDisplayName)

	local response = resolveActionResponse(player, true, message)
	response.openResult = resolution.OpenResult
	return response
end

local function grantSpecificFruitReward(player, fruitIdentifier, sourceOptions)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
	if not fruit then
		return resolveActionResponse(player, false, nil, "invalid_fruit")
	end

	local dataRoot = profile.Data
	if typeof(dataRoot.UnopenedChests) ~= "table" then
		dataRoot.UnopenedChests = {}
	end

	local unopenedChests = dataRoot.UnopenedChests
	unopenedChests.Order = unopenedChests.Order or {}
	unopenedChests.ById = unopenedChests.ById or {}
	unopenedChests.NextChestId = math.max(1, tonumber(unopenedChests.NextChestId) or 1)

	local options = if typeof(sourceOptions) == "table" then sourceOptions else {}
	local resolution = ChestRewardResolver.ResolveSpecificFruit({
		Player = player,
		DataRoot = dataRoot,
		FruitIdentifier = fruit.FruitKey,
		AddChestEntry = function(grantedChestData)
			local grantedChestId = addUnopenedChestToCollection(unopenedChests, grantedChestData)
			return grantedChestId
		end,
		DepthBand = tostring(options.DepthBand or Economy.VerticalSlice.DefaultDepthBand),
		Source = tostring(options.Source or "Admin"),
		RewardProfile = tostring(options.RewardProfile or ChestRewards.DefaultRewardProfile),
		SourceKind = tostring(options.Kind or "DirectFruitReward"),
		SourceInventoryName = tostring(options.InventoryName or "Direct Fruit Reward"),
		SourceDisplayName = tostring(options.DisplayName or "Direct Fruit Reward"),
	})

	local changedRoots = resolution.ChangedRoots or {}
	local changedPaths = buildRewardChangedPaths(dataRoot, changedRoots, {
		UnopenedChests = unopenedChests,
	})
	syncPaths(player, replica, changedPaths)

	local message = if resolution.OpenResult and resolution.OpenResult.WasDuplicate
		then string.format(
			"Duplicate %s converted to %s.",
			tostring(fruit.DisplayName),
			tostring(
				resolution.OpenResult.ConversionRewardDisplayName
					or ((resolution.OpenResult.GrantedChest or {}).displayName)
					or resolution.RewardText
					or "a duplicate reward"
			)
		)
		else string.format("Granted %s.", tostring(fruit.DisplayName))

	local response = resolveActionResponse(player, true, message)
	response.openResult = resolution.OpenResult
	return response
end

local function feedCrew(player, crewInstanceId, foodKey)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local foodConfig = Economy.Food[foodKey]
	if not foodConfig then
		return resolveActionResponse(player, false, nil, "invalid_food")
	end

	local dataRoot = profile.Data
	local canonicalInstanceId, canonicalEntry = CrewInstanceService.GetInstance(player, tostring(crewInstanceId or ""))
	if typeof(canonicalEntry) ~= "table" or tostring(canonicalInstanceId or "") == "" then
		warn(string.format(
			"[GrandLineRush] Feed failed to resolve canonical crew player=%s canonicalId=%s",
			player and player.Name or "unknown",
			tostring(crewInstanceId or "")
		))
		return resolveActionResponse(player, false, nil, "missing_canonical_crew")
	end

	local foodInventory = dataRoot.FoodInventory
	if (tonumber(foodInventory[foodKey]) or 0) <= 0 then
		return resolveActionResponse(player, false, nil, "not_enough_food")
	end

	local rarity = tostring(canonicalEntry.Rarity or "Common")
	local level = math.max(1, tonumber(canonicalEntry.Level) or 1)
	if level >= Economy.Rules.CrewMaxLevel then
		return resolveActionResponse(player, false, nil, "crew_max_level")
	end

	local xpToAdd = math.max(1, tonumber(foodConfig.XP) or 0)

	local currentXP = math.max(0, tonumber(canonicalEntry.CurrentXP) or 0)
	local totalXP = math.max(0, tonumber(canonicalEntry.TotalXP) or 0)
	local levelUps = 0

	while xpToAdd > 0 and level < Economy.Rules.CrewMaxLevel do
		local neededXP = getCrewXPRequiredForLevel(rarity, level)
		local remainingToLevel = math.max(0, neededXP - currentXP)
		local appliedXP = math.min(xpToAdd, remainingToLevel)

		currentXP += appliedXP
		totalXP += appliedXP
		xpToAdd -= appliedXP

		if currentXP >= neededXP then
			level += 1
			levelUps += 1
			currentXP = 0
		end
	end

	if level >= Economy.Rules.CrewMaxLevel then
		currentXP = 0
	end

	local canonicalSource = tostring(canonicalEntry.Source or "")
	if canonicalSource == "" then
		canonicalSource = "GrandLineRush"
	end
	local updatedCanonical = CrewInstanceService.UpdateProgress(player, canonicalInstanceId, level, currentXP, {
		TotalXP = totalXP,
		Source = canonicalSource,
		DepthBand = tostring(canonicalEntry.DepthBand or ""),
		GrandLineRushStarter = canonicalSource == STARTER_CREW_SOURCE,
	})
	if typeof(updatedCanonical) ~= "table" then
		warn(string.format(
			"[GrandLineRush] Feed canonical progression update failed player=%s canonicalId=%s",
			player and player.Name or "unknown",
			tostring(canonicalInstanceId)
		))
		return resolveActionResponse(player, false, nil, "canonical_progression_failed")
	end

	foodInventory[foodKey] -= 1

	local grantData = buildGrantDataFromCanonical(updatedCanonical)
	if grantData == nil then
		return resolveActionResponse(player, false, nil, "invalid_canonical_crew")
	end

	syncPaths(player, replica, {
		{ Path = { "FoodInventory" }, Value = foodInventory },
	})

	if levelUps > 0 then
		QuestSignals.Record(player, "UpgradeCrew", levelUps, {
			CrewInstanceId = tostring(canonicalInstanceId or crewInstanceId or ""),
			CrewName = tostring(grantData.DisplayName or updatedCanonical.DisplayName or updatedCanonical.StorageName or ""),
			Rarity = tostring(rarity or ""),
			FoodKey = tostring(foodKey or ""),
			Level = level,
		})
	end

	local message = string.format(
		"Fed %s to %s. Level %d%s.",
		tostring(foodConfig.DisplayName),
		tostring(grantData.DisplayName or updatedCanonical.DisplayName or updatedCanonical.StorageName or "Crewmate"),
		level,
		if levelUps > 0 then string.format(" (+%d level)", levelUps) else ""
	)

	return resolveActionResponse(player, true, message)
end

local function handleRequest(player, actionName, payload)
	if typeof(actionName) ~= "string" then
		return resolveActionResponse(player, false, nil, "invalid_action")
	end

	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	if actionName == "GetState" then
		return resolveActionResponse(player, true)
	elseif actionName == "OpenChest" then
		return openChest(player, payload and payload.ChestId)
	elseif actionName == "DropCarriedReward" then
		local dropPosition = getManualDropPosition(player)
		if typeof(dropPosition) ~= "Vector3" then
			return resolveActionResponse(player, false, nil, "missing_drop_position")
		end

		local runtime = getRuntime(player)
		if runtime.CarriedReward ~= nil then
			return dropCarriedReward(player, {
				Reason = "PlayerDrop",
				DropPosition = dropPosition,
				IgnoreProtection = true,
			})
		end

		local crewMemberContext = CrewInteraction.GetActiveContext()
		if hasCarriedCrewMember(player) or CrewInteraction.HasHeld(crewMemberContext, player) then
			return dropCarriedCrewMember(player, dropPosition)
		end

		return resolveActionResponse(player, false, nil, "no_carried_item")
	elseif actionName == "FeedCrew" then
		return feedCrew(player, payload and payload.CrewInstanceId, payload and payload.FoodKey)
	end

	return resolveActionResponse(player, false, nil, "unknown_action")
end

local function bindCharacter(player, character)
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end

	if character:GetAttribute("HoroProjectionGhost") == true then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return
	end

	deathConnections[player] = humanoid.Died:Connect(function()
		local runtime = getRuntime(player)
		if runtime.InRun or runtime.CarriedReward ~= nil or runtime.SpawnedReward ~= nil then
			Service.FailRun(player, "Defeated before securing the reward. Unextracted rewards were lost.")
		end
	end)
end

local function onPlayerAdded(player)
	task.spawn(function()
		if waitForDataReady(player, 15) then
			ensureStarterCrew(player)
			pushState(player)
		end
	end)

	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)

	if player.Character then
		task.defer(bindCharacter, player, player.Character)
	end
end

local function onPlayerRemoving(player)
	clearCarryTool(player)

	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end

	runtimeByPlayer[player] = nil
end

function Service.Start()
	if started then
		return
	end
	if Economy.VerticalSlice.Enabled ~= true then
		return
	end

	started = true
	ensureRemotes()

	requestRemote.OnServerInvoke = function(player, actionName, payload)
		return handleRequest(player, actionName, payload)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

Service.StateChanged = stateChangedEvent.Event

function Service.GetState(player)
	return buildState(player)
end

function Service.PushState(player)
	pushState(player)
end

function Service.StartRun(player, rewardType, depthBand)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return startRun(player, rewardType, depthBand)
end

function Service.CreateChestRewardData(depthBand)
	local normalizedDepthBand = tostring(depthBand or Economy.VerticalSlice.DefaultDepthBand)
	return {
		RewardType = "Chest",
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = chooseChestTier(normalizedDepthBand),
		DepthBand = normalizedDepthBand,
	}
end

function Service.ClaimSpawnedReward(player)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return claimSpawnedReward(player)
end

function Service.ClaimWorldChest(player, rewardData)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return claimWorldChest(player, rewardData)
end

function Service.CanForceCarryDrop(player)
	return canForceCarryDrop(player)
end

function Service.DropCarriedReward(player, options)
	return dropCarriedReward(player, options)
end

function Service.ExtractRun(player)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return extractRun(player)
end

function Service.GrantChest(player, tierName, amount, depthBand)
	if not waitForDataReady(player, 10) then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local normalizedTier = tostring(tierName or "")
	if Economy.Chests.Tiers[normalizedTier] == nil then
		return resolveActionResponse(player, false, nil, "invalid_chest_tier")
	end

	local count = math.max(1, math.floor(tonumber(amount) or 1))
	local normalizedDepthBand = tostring(depthBand or Economy.VerticalSlice.DefaultDepthBand)
	local grantedCount = 0

	for _ = 1, count do
		local chestId = addUnopenedChest(player, normalizedTier, normalizedDepthBand)
		if chestId ~= nil then
			grantedCount += 1
		end
	end

	if grantedCount <= 0 then
		return resolveActionResponse(player, false, nil, "grant_failed")
	end

	local message = string.format(
		"Granted %d %s%s.",
		grantedCount,
		normalizedTier,
		grantedCount == 1 and " Chest" or " Chests"
	)
	return resolveActionResponse(player, true, message)
end

function Service.OpenChest(player, chestId)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return openChest(player, chestId)
end

function Service.GrantSpecificFruitReward(player, fruitIdentifier, sourceOptions)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return grantSpecificFruitReward(player, fruitIdentifier, sourceOptions)
end

function Service.FeedCrew(player, crewInstanceId, foodKey)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return feedCrew(player, crewInstanceId, foodKey)
end

return Service
