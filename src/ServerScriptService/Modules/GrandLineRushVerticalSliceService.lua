local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BountyService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushBountyService"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushCrewCatalog"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))

local Service = {}

local randomObject = Random.new()
local requestRemote
local stateRemote
local stateChangedEvent = Instance.new("BindableEvent")
local started = false
local runtimeByPlayer = {}
local deathConnections = {}
local CHEST_DEBUG = true
local DEBUG_TRACE = RunService:IsStudio()

local CARRY_TOOL_NAME = "GrandLineRushMajorReward"
local CHEST_TIER_ORDER = { "Wooden", "Iron", "Gold", "Legendary" }
local FORCED_DROP_PROTECTION_ATTRIBUTE = "GrandLineRushCarryDropProtectedUntil"
local FORCED_DROP_PROTECTION_DURATION = 0.9

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

local function normalizeSegments(pathOrSegments)
	if typeof(pathOrSegments) == "table" then
		return pathOrSegments
	end

	local segments = string.split(tostring(pathOrSegments), ".")
	if segments[1] == "Data" then
		table.remove(segments, 1)
	end
	return segments
end

local function getNested(dataRoot, pathOrSegments, createMissing)
	local segments = normalizeSegments(pathOrSegments)
	local pointer = dataRoot

	for index = 1, #segments - 1 do
		local segment = segments[index]
		if typeof(pointer[segment]) ~= "table" then
			if not createMissing then
				return nil, nil, segments
			end
			pointer[segment] = {}
		end
		pointer = pointer[segment]
	end

	return pointer[segments[#segments]], pointer, segments
end

local function setNested(dataRoot, pathOrSegments, value)
	local _, parent, segments = getNested(dataRoot, pathOrSegments, true)
	parent[segments[#segments]] = value
	return segments
end

local function syncPaths(player, replica, changedPaths)
	if replica then
		for _, entry in ipairs(changedPaths) do
			replica:Set(entry.Path, entry.Value)
		end
	end

	DataManager:UpdateData(player)
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

local function buildCrewSummary(instanceId, crewData)
	local level = tonumber(crewData.Level) or 1
	local rarity = tostring(crewData.Rarity or "Common")

	return {
		InstanceId = tostring(instanceId),
		Name = tostring(crewData.Name or "Unnamed Crew"),
		Rarity = rarity,
		Level = level,
		CurrentXP = tonumber(crewData.CurrentXP) or 0,
		NextLevelXP = getCrewXPRequiredForLevel(rarity, level),
		ShipIncomePerHour = getCrewShipIncomePerHour(rarity, level),
		Source = tostring(crewData.Source or "Unknown"),
	}
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
end

local function getRewardToolDisplay(reward)
	if reward.RewardType == "Chest" then
		return string.format("%s Chest", tostring(reward.Tier or "Wooden"))
	end

	return tostring(reward.CrewName or "Crew Contract")
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
		data.Tier = reward.Tier
	else
		data.Rarity = reward.Rarity
		data.CrewName = reward.CrewName
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

local function chooseCrewReward(depthBand)
	local distribution = Economy.Crew.RewardOddsByDepthBand[depthBand] or Economy.Crew.RewardOddsByDepthBand.Mid
	local rarity = chooseWeightedKey(distribution, Economy.Crew.RarityOrder)
	return {
		Rarity = rarity,
		Name = CrewCatalog.GetRandomNameForRarity(rarity, randomObject),
	}
end

local function ensureDevilFruitEntry(dataRoot, fruitKey)
	local inventory = dataRoot.Inventory or {}
	dataRoot.Inventory = inventory

	local devilFruits = inventory.DevilFruits or {}
	inventory.DevilFruits = devilFruits

	local entry = devilFruits[fruitKey]
	if typeof(entry) ~= "table" then
		entry = { Quantity = 0 }
		devilFruits[fruitKey] = entry
	end

	entry.Quantity = tonumber(entry.Quantity) or 0
	return entry
end

local function ensureStarterCrew(player)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return
	end

	if Economy.VerticalSlice.StarterCrew.Enabled ~= true then
		return
	end

	local dataRoot = profile.Data
	local crewInventory = dataRoot.CrewInventory
	if typeof(crewInventory) ~= "table" then
		return
	end

	crewInventory.Order = crewInventory.Order or {}
	crewInventory.ById = crewInventory.ById or {}
	crewInventory.NextInstanceId = math.max(1, tonumber(crewInventory.NextInstanceId) or 1)

	if #crewInventory.Order > 0 then
		return
	end

	local instanceId = tostring(crewInventory.NextInstanceId)
	crewInventory.NextInstanceId += 1
	crewInventory.ById[instanceId] = {
		Name = Economy.VerticalSlice.StarterCrew.Name,
		Rarity = Economy.VerticalSlice.StarterCrew.Rarity,
		Level = 1,
		CurrentXP = 0,
		TotalXP = 0,
		Source = "Starter",
		AcquiredAt = os.time(),
	}
	table.insert(crewInventory.Order, instanceId)

	syncPaths(player, replica, {
		{ Path = { "CrewInventory" }, Value = crewInventory },
	})
end

local function addCrewInstance(player, rewardData, source)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return nil
	end

	local crewInventory = profile.Data.CrewInventory
	crewInventory.Order = crewInventory.Order or {}
	crewInventory.ById = crewInventory.ById or {}
	crewInventory.NextInstanceId = math.max(1, tonumber(crewInventory.NextInstanceId) or 1)

	local instanceId = tostring(crewInventory.NextInstanceId)
	crewInventory.NextInstanceId += 1
	crewInventory.ById[instanceId] = {
		Name = rewardData.Name,
		Rarity = rewardData.Rarity,
		Level = 1,
		CurrentXP = 0,
		TotalXP = 0,
		Source = source or "RunReward",
		AcquiredAt = os.time(),
	}
	table.insert(crewInventory.Order, instanceId)

	syncPaths(player, replica, {
		{ Path = { "CrewInventory" }, Value = crewInventory },
	})

	return instanceId
end

local function addUnopenedChest(player, tierName, depthBand)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		chestDebug("addUnopenedChest skipped for %s because profile/replica missing.", player and player.Name or "unknown")
		return nil
	end

	local unopenedChests = profile.Data.UnopenedChests
	unopenedChests.Order = unopenedChests.Order or {}
	unopenedChests.ById = unopenedChests.ById or {}
	unopenedChests.NextChestId = math.max(1, tonumber(unopenedChests.NextChestId) or 1)

	local chestId = tostring(unopenedChests.NextChestId)
	unopenedChests.NextChestId += 1
	unopenedChests.ById[chestId] = {
		ChestId = chestId,
		Tier = tierName,
		DepthBand = depthBand,
		CreatedAt = os.time(),
	}
	table.insert(unopenedChests.Order, chestId)

	local tierQuantity = 0
	for _, existingChestId in ipairs(unopenedChests.Order) do
		local entry = unopenedChests.ById[tostring(existingChestId)]
		if entry and tostring(entry.Tier) == tostring(tierName) then
			tierQuantity += 1
		end
	end

	chestDebug(
		"addUnopenedChest player=%s tier=%s depth=%s newChestId=%s tierQuantity=%d totalOrder=%d",
		player.Name,
		tostring(tierName),
		tostring(depthBand),
		tostring(chestId),
		tierQuantity,
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
	local crewInventory = dataRoot.CrewInventory or {}
	local foodInventory = dataRoot.FoodInventory or {}
	local materials = normalizeMaterialsTable(dataRoot.Materials)
	local leaderstats = dataRoot.leaderstats or {}
	local devilFruits = ((dataRoot.Inventory or {}).DevilFruits) or {}

	local chestSummaries = {}
	for _, chestId in ipairs(unopenedChests.Order or {}) do
		local entry = unopenedChests.ById and unopenedChests.ById[tostring(chestId)]
		if entry then
			chestSummaries[#chestSummaries + 1] = {
				ChestId = tostring(chestId),
				Tier = tostring(entry.Tier or "Wooden"),
				DepthBand = tostring(entry.DepthBand or ""),
			}
		end
	end

	local crewSummaries = {}
	for _, instanceId in ipairs(crewInventory.Order or {}) do
		local crewData = crewInventory.ById and crewInventory.ById[tostring(instanceId)]
		if crewData then
			crewSummaries[#crewSummaries + 1] = buildCrewSummary(instanceId, crewData)
		end
	end

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

local function setResolution(player, text)
	local runtime = getRuntime(player)
	runtime.ResolutionText = text
	pushState(player)
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
			Rarity = crewReward.Rarity,
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
			"sliceExtractPersistedChest player=%s tier=%s chestId=%s depth=%s action=add_to_hotbar_state",
			player.Name,
			tostring(carriedReward.Tier),
			tostring(chestId),
			tostring(carriedReward.DepthBand)
		)
		message = string.format("Extracted %s and added it to your hotbar as chest #%s.", getRewardToolDisplay(carriedReward), tostring(chestId or "?"))
	else
		local instanceId = addCrewInstance(player, {
			Name = carriedReward.CrewName,
			Rarity = carriedReward.Rarity,
		}, "RunReward")
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
	if player:GetAttribute("CarriedBrainrot") ~= nil then
		return resolveActionResponse(player, false, "You cannot pick up a chest while carrying a brainrot.", "carrying_brainrot")
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

local function canForceCarryDrop(player, runtime)
	runtime = runtime or getRuntime(player)
	if runtime.CarriedReward == nil then
		return false, "no_carried_reward"
	end

	local protectedUntil = player:GetAttribute(FORCED_DROP_PROTECTION_ATTRIBUTE)
	if typeof(protectedUntil) == "number" and protectedUntil > os.clock() then
		return false, "carry_drop_protected"
	end

	return true, nil
end

local function dropCarriedReward(player, options)
	local runtime = getRuntime(player)
	local canDrop, reason = canForceCarryDrop(player, runtime)
	if not canDrop then
		return resolveActionResponse(player, false, nil, reason)
	end

	options = if typeof(options) == "table" then options else {}
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

	local tierName = tostring(chestData.Tier or "Wooden")
	local tierConfig = Economy.Chests.Tiers[tierName]
	if not tierConfig then
		return resolveActionResponse(player, false, nil, "invalid_chest_tier")
	end

	local rewards = tierConfig.Rewards or {}
	local foodRewards = rewards.Food or {}
	local materialRewards = rewards.Materials or {}
	local foodInventory = dataRoot.FoodInventory
	local materials = normalizeMaterialsTable(dataRoot.Materials)
	dataRoot.Materials = materials
	local leaderstats = dataRoot.leaderstats
	local totalStats = dataRoot.TotalStats
	local changedPaths = {}

	for foodKey, amount in pairs(foodRewards) do
		foodInventory[foodKey] = math.max(0, tonumber(foodInventory[foodKey]) or 0) + math.max(0, tonumber(amount) or 0)
	end
	changedPaths[#changedPaths + 1] = { Path = { "FoodInventory" }, Value = foodInventory }

	for materialKey, amount in pairs(materialRewards) do
		materials[materialKey] = math.max(0, tonumber(materials[materialKey]) or 0) + math.max(0, tonumber(amount) or 0)
	end
	normalizeMaterialsTable(materials)
	changedPaths[#changedPaths + 1] = { Path = { "Materials" }, Value = materials }

	local doubloonReward = math.max(0, tonumber(rewards.Doubloons) or 0)
	leaderstats.Doubloons = math.max(0, tonumber(leaderstats.Doubloons) or 0) + doubloonReward
	totalStats.TotalDoubloons = math.max(0, tonumber(totalStats.TotalDoubloons) or 0) + doubloonReward
	changedPaths[#changedPaths + 1] = { Path = { "leaderstats", "Doubloons" }, Value = leaderstats.Doubloons }
	changedPaths[#changedPaths + 1] = { Path = { "TotalStats", "TotalDoubloons" }, Value = totalStats.TotalDoubloons }

	local fruitMessage = nil
	local devilFruitChance = tonumber(rewards.DevilFruitChance) or 0
	if devilFruitChance > 0 and randomObject:NextNumber() <= devilFruitChance then
		local fruits = DevilFruitConfig.GetAllFruits()
		if #fruits > 0 then
			local fruit = fruits[randomObject:NextInteger(1, #fruits)]
			local entry = ensureDevilFruitEntry(dataRoot, fruit.FruitKey)
			entry.Quantity += 1
			fruitMessage = fruit.DisplayName
			changedPaths[#changedPaths + 1] = { Path = { "Inventory", "DevilFruits" }, Value = dataRoot.Inventory.DevilFruits }
		end
	end

	unopenedChests.ById[chestId] = nil
	for index = #unopenedChests.Order, 1, -1 do
		if tostring(unopenedChests.Order[index]) == chestId then
			table.remove(unopenedChests.Order, index)
			break
		end
	end
	changedPaths[#changedPaths + 1] = { Path = { "UnopenedChests" }, Value = unopenedChests }

	syncPaths(player, replica, changedPaths)

	local rewardParts = {}
	for foodKey, amount in pairs(foodRewards) do
		rewardParts[#rewardParts + 1] = string.format("%dx %s", amount, Economy.Food[foodKey].DisplayName)
	end
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder) do
		local amount = math.max(0, tonumber(materialRewards[materialKey]) or 0)
		if amount > 0 then
			rewardParts[#rewardParts + 1] = string.format(
				"%dx %s",
				amount,
				tostring(PlotUpgradeConfig.MaterialDisplayNames[materialKey] or materialKey)
			)
		end
	end
	if doubloonReward > 0 then
		rewardParts[#rewardParts + 1] = string.format("%d Doubloons", doubloonReward)
	end
	if fruitMessage then
		rewardParts[#rewardParts + 1] = string.format("Devil Fruit: %s", fruitMessage)
	end

	return resolveActionResponse(player, true, string.format("Opened %s chest and received %s.", tierName, table.concat(rewardParts, ", ")))
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
	local crewInventory = dataRoot.CrewInventory
	local crewEntry = crewInventory.ById and crewInventory.ById[tostring(crewInstanceId)]
	if typeof(crewEntry) ~= "table" then
		return resolveActionResponse(player, false, nil, "missing_crew")
	end

	local foodInventory = dataRoot.FoodInventory
	if (tonumber(foodInventory[foodKey]) or 0) <= 0 then
		return resolveActionResponse(player, false, nil, "not_enough_food")
	end

	local rarity = tostring(crewEntry.Rarity or "Common")
	local level = math.max(1, tonumber(crewEntry.Level) or 1)
	if level >= Economy.Rules.CrewMaxLevel then
		return resolveActionResponse(player, false, nil, "crew_max_level")
	end

	local xpToAdd = math.max(1, tonumber(foodConfig.XP) or 0)
	foodInventory[foodKey] -= 1

	local currentXP = math.max(0, tonumber(crewEntry.CurrentXP) or 0)
	local totalXP = math.max(0, tonumber(crewEntry.TotalXP) or 0)
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

	crewEntry.Level = level
	crewEntry.CurrentXP = currentXP
	crewEntry.TotalXP = totalXP

	syncPaths(player, replica, {
		{ Path = { "FoodInventory" }, Value = foodInventory },
		{ Path = { "CrewInventory" }, Value = crewInventory },
	})

	local message = string.format(
		"Fed %s to %s. Level %d%s.",
		tostring(foodConfig.DisplayName),
		tostring(crewEntry.Name),
		level,
		if levelUps > 0 then string.format(" (+%d level)", levelUps) else ""
	)

	return resolveActionResponse(player, true, message)
end

local function handleRequest(player, actionName, payload)
	if typeof(actionName) ~= "string" then
		return resolveActionResponse(player, false, nil, "invalid_action")
	end

	if not waitForDataReady(player, 10) then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	ensureStarterCrew(player)

	if actionName == "GetState" then
		return resolveActionResponse(player, true)
	elseif actionName == "StartRun" then
		local rewardType = payload and payload.RewardType or "Chest"
		local depthBand = payload and payload.DepthBand or Economy.VerticalSlice.DefaultDepthBand
		return startRun(player, rewardType, depthBand)
	elseif actionName == "ClaimReward" then
		return claimSpawnedReward(player)
	elseif actionName == "ExtractRun" then
		return extractRun(player)
	elseif actionName == "FailRun" then
		return Service.FailRun(player, "Run failed. Unextracted rewards were lost.")
	elseif actionName == "OpenChest" then
		return openChest(player, payload and payload.ChestId)
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
	return handleRequest(player, "StartRun", {
		RewardType = rewardType,
		DepthBand = depthBand,
	})
end

function Service.CreateChestRewardData(depthBand)
	local normalizedDepthBand = tostring(depthBand or Economy.VerticalSlice.DefaultDepthBand)
	return {
		RewardType = "Chest",
		Tier = chooseChestTier(normalizedDepthBand),
		DepthBand = normalizedDepthBand,
	}
end

function Service.ClaimSpawnedReward(player)
	return handleRequest(player, "ClaimReward")
end

function Service.ClaimWorldChest(player, rewardData)
	if not waitForDataReady(player, 10) then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end
	ensureStarterCrew(player)
	return claimWorldChest(player, rewardData)
end

function Service.CanForceCarryDrop(player)
	return canForceCarryDrop(player)
end

function Service.DropCarriedReward(player, options)
	return dropCarriedReward(player, options)
end

function Service.ExtractRun(player)
	return handleRequest(player, "ExtractRun")
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

	local message = string.format("Granted %d %s chest%s.", grantedCount, normalizedTier, grantedCount == 1 and "" or "s")
	return resolveActionResponse(player, true, message)
end

function Service.OpenChest(player, chestId)
	return handleRequest(player, "OpenChest", {
		ChestId = chestId,
	})
end

function Service.FeedCrew(player, crewInstanceId, foodKey)
	return handleRequest(player, "FeedCrew", {
		CrewInstanceId = crewInstanceId,
		FoodKey = foodKey,
	})
end

return Service
