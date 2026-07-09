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
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local CarriedDropNotice = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CarriedDropNotice"))
local GrandLineRushCrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushCrewCatalog"))
local CanonicalCrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local CrewInteraction = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Server"):WaitForChild("Crew"):WaitForChild("Interaction"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ChestRewardResolver = require(ServerScriptService.Modules:WaitForChild("GrandLineRushChestRewardResolver"))
local QuestSignals = require(ServerScriptService.Modules:WaitForChild("GrandLineRushQuestSignals"))
local AddCrewMember = require(ServerScriptService.Modules:WaitForChild("AddCrewMember"))
local CrewInventoryDerivedCache = require(ServerScriptService.Modules:WaitForChild("CrewInventoryDerivedCache"))
local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(ServerScriptService.Modules:WaitForChild("CrewQuickSlotService"))
local CrewStandIncomeAuthority = require(ServerScriptService.Modules:WaitForChild("CrewStandIncomeAuthority"))
local GTRActionDiagnostics = require(ServerScriptService.Modules:WaitForChild("GTRActionDiagnostics"))
local PaidRandomItemPolicy = require(ServerScriptService.Modules:WaitForChild("PaidRandomItemPolicy"))
local RemoteGuard = require(ServerScriptService.Modules:WaitForChild("RemoteGuard"))
local ServerRestartService = require(ServerScriptService.Modules:WaitForChild("ServerRestartService"))
local TitleProgressService = require(ServerScriptService.Modules:WaitForChild("TitleProgressService"))

local Service = {}

local randomObject = Random.new()
local requestRemote
local stateRemote
local crewMemberInventoryChangedRemote
local stateChangedEvent = Instance.new("BindableEvent")
local droppedChestWorldHandler = nil
local started = false
local runtimeByPlayer = {}
local deathConnections = {}
local REQUEST_ACTION_ALLOWLIST = {
	GetState = true,
	OpenChest = true,
	OpenChests = true,
	DropCarriedReward = true,
	FeedCrew = true,
}
local MAX_BATCH_CHEST_OPEN_COUNT = 50
local CHEST_DEBUG = false
local DEBUG_TRACE = RunService:IsStudio() and game:GetAttribute("VerticalSliceDebugTrace") == true

local CARRY_TOOL_NAME = "GrandLineRushMajorReward"
local CHEST_TIER_ORDER = ChestRewards.StandardTierOrder
local FORCED_DROP_PROTECTION_ATTRIBUTE = "GrandLineRushCarryDropProtectedUntil"
local FORCED_DROP_PROTECTION_DURATION = 0.9
local HORO_PROJECTION_CARRY_ATTRIBUTE = "HoroProjectionCarryProjectionId"
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE = "CarriedCrewMemberImage"
local DEFAULT_MAX_CARRY_SLOTS = 3
local DEFAULT_UNLOCKED_CARRY_SLOTS = 1
local HORO_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local HORO_GHOSTS_FOLDER_NAME = "HoroGhosts"
local STARTER_CREW_SOURCE = "GrandLineRushStarter"
local CREW_INVENTORY_CHANGED_REMOTE_NAME = "CrewMemberInventoryChanged"
local CREW_EXTRACTION_QUICK_SLOT_ASSIGN_REASON = "crew_extraction_quick_slot_assign"
local CRITICAL_CARRY_DROP_REASONS = {
	AFKTeleport = true,
	PlayerDeath = true,
}
local CANONICAL_CREW_RARITY_ALIASES = {
	Mythical = "Mythic",
	Celestial = "Godly",
}
local canonicalCrewRewardPoolsByRarity = nil
local canonicalCrewRewardPool = nil
local contextualTutorialTriggerService = nil
local tutorialService = nil
local carryDropTransactionSequence = 0

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

local function carryDropTrace(message, ...)
	runTrace("[CarryDrop] " .. tostring(message), ...)
end

local function notifyCarryDrop(player, reasonCode, info)
	info = if typeof(info) == "table" then info else {}
	return CarriedDropNotice.Notify(player, {
		ReasonCode = reasonCode,
		Count = tonumber(info.Count) or 1,
		Source = info.Source or "GrandLineRushVerticalSliceService",
		Action = info.Action,
		ItemType = info.ItemType,
		DisplayName = info.DisplayName,
		CarryId = info.CarryId,
		SlotIndex = info.SlotIndex,
		Context = info.Context,
		SuppressToast = info.SuppressToast == true,
	})
end

local function getContextualTutorialTriggerService()
	if contextualTutorialTriggerService ~= nil then
		return contextualTutorialTriggerService
	end

	local module = ServerScriptService.Modules:FindFirstChild("ContextualTutorialTriggerService")
	if not module then
		return nil
	end

	local ok, service = pcall(require, module)
	if ok then
		contextualTutorialTriggerService = service
	end
	return contextualTutorialTriggerService
end

local function getTutorialService()
	if tutorialService ~= nil then
		return tutorialService
	end

	local module = ServerScriptService.Modules:FindFirstChild("TutorialService")
	if not module then
		return nil
	end

	local ok, service = pcall(require, module)
	if ok then
		tutorialService = service
	end
	return tutorialService
end

local function completeContextualTutorial(player, tutorialId, context)
	local service = getTutorialService()
	if typeof(service) ~= "table" or typeof(service.Complete) ~= "function" then
		return false, "tutorial_service_unavailable"
	end

	local ok, success, reason = pcall(service.Complete, player, tutorialId, context)
	if not ok then
		return false, "tutorial_complete_failed"
	end
	return success == true, reason
end

local function triggerResourceTutorialsAfterGrant(player, source, grantedResources)
	local service = getContextualTutorialTriggerService()
	if typeof(service) ~= "table" then
		return
	end

	grantedResources = if typeof(grantedResources) == "table" then grantedResources else {}
	if typeof(service.OnFoodGranted) == "function" then
		service.OnFoodGranted(player, source, grantedResources.food)
	end
	if typeof(service.CheckShipUpgradeAffordable) == "function" then
		service.CheckShipUpgradeAffordable(player, source)
	end
end

local function hasCarriedCrewMember(player)
	local carried = player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE)
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

local function getCrewMemberInventoryChangedRemote()
	if crewMemberInventoryChangedRemote == nil or crewMemberInventoryChangedRemote.Parent ~= ReplicatedStorage then
		crewMemberInventoryChangedRemote =
			getOrCreateRemote(ReplicatedStorage, "RemoteEvent", CREW_INVENTORY_CHANGED_REMOTE_NAME)
	end
	return crewMemberInventoryChangedRemote
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
		CarrySlots = nil,
		CarrySequence = 0,
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

local function getProfileAndReplicaNonBlocking(player)
	if not DataManager:IsReady(player) then
		return nil, nil
	end

	return DataManager:GetProfile(player), DataManager:GetReplica(player)
end

local function buildDataPath(path)
	if typeof(path) == "table" then
		local parts = {}
		for _, segment in ipairs(path) do
			parts[#parts + 1] = tostring(segment)
		end
		return table.concat(parts, ".")
	end

	return tostring(path or "")
end

local function syncPaths(player, _replica, changedPaths, perfContext)
	local operations = {}
	for _, entry in ipairs(if typeof(changedPaths) == "table" then changedPaths else {}) do
		if typeof(entry) == "table" and entry.Value ~= nil then
			operations[#operations + 1] = {
				Kind = "Set",
				Path = buildDataPath(entry.Path),
				Value = entry.Value,
			}
		end
	end

	if #operations <= 0 then
		return true, {
			Reason = "empty",
			WriteCount = 0,
			ReplicaWriteCount = 0,
			ChangedPaths = {},
		}
	end

	local ok, result = DataManager:TryApplyBatch(player, operations, {
		PerfContext = perfContext,
	})
	if ok ~= true then
		warn(string.format(
			"[GrandLineRush] targeted sync failed player=%s reason=%s",
			player and player.Name or "unknown",
			tostring(result and result.Reason or "unknown")
		))
	end
	return ok == true, result
end

local function buildRewardChangedPaths(dataRoot, changedRoots, options)
	local changedPaths = {}
	local settings = if typeof(options) == "table" then options else {}
	local primaryCurrency = CurrencyUtil.getConfig()

	if changedRoots.FoodInventory then
		changedPaths[#changedPaths + 1] = { Path = { "FoodInventory" }, Value = dataRoot.FoodInventory }
	end
	if changedRoots.Materials then
		changedPaths[#changedPaths + 1] = { Path = { "Materials" }, Value = dataRoot.Materials }
	end
	if changedRoots.Leaderstats then
		changedPaths[#changedPaths + 1] = { Path = { "leaderstats", primaryCurrency.Key }, Value = dataRoot.leaderstats[primaryCurrency.Key] }
	end
	if changedRoots.TotalStats then
		changedPaths[#changedPaths + 1] = { Path = { "TotalStats", primaryCurrency.TotalKey }, Value = dataRoot.TotalStats[primaryCurrency.TotalKey] }
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

local function getGrantedBeli(grantedResources)
	grantedResources = if typeof(grantedResources) == "table" then grantedResources else {}
	return math.max(0, tonumber(grantedResources.beli) or tonumber(grantedResources.doubloons) or 0)
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

local function getCrewSummaryIncomePerSecond(crewData, mirrorData, level)
	crewData = if typeof(crewData) == "table" then crewData else {}
	mirrorData = if typeof(mirrorData) == "table" then mirrorData else {}

	local baseIncomeRoll = tonumber(crewData.BaseIncomeRoll)
	if baseIncomeRoll == nil then
		baseIncomeRoll = tonumber(mirrorData.BaseIncomeRoll)
	end
	if baseIncomeRoll ~= nil and baseIncomeRoll > 0 then
		return CrewIncomeBalance.ComputeIncome(
			baseIncomeRoll,
			crewData.Variant or mirrorData.Variant,
			level,
			crewData.Rarity or mirrorData.Rarity
		)
	end

	local income = tonumber(crewData.Income)
	if income == nil then
		income = tonumber(mirrorData.Income)
	end

	return math.max(0, income or 0)
end

local function getCrewSummaryIncomePerHour(crewData, mirrorData, level)
	local incomePerSecond = getCrewSummaryIncomePerSecond(crewData, mirrorData, level)
	return math.floor((incomePerSecond * 3600) + 0.5)
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
		crewData.CrewMemberId,
		mirrorData.StorageName,
		mirrorData.CrewMemberId,
		crewData.Name,
		mirrorData.Name
	)
end

local function getCrewSummaryDisplayName(crewData, mirrorData, storageName)
	crewData = if typeof(crewData) == "table" then crewData else {}
	mirrorData = if typeof(mirrorData) == "table" then mirrorData else {}

	local displayInfo = CanonicalCrewCatalog.GetDisplayInfo(storageName, crewData)
	local info = CanonicalCrewCatalog.GetInfoById(storageName)
	return firstNonEmpty(
		displayInfo.DisplayName,
		info and info.DisplayName,
		info and info.CrewMemberName,
		info and info.Name,
		crewData.DisplayName,
		crewData.Name,
		mirrorData.DisplayName,
		mirrorData.Name,
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
	local variant = firstNonEmpty(crewData.Variant, mirrorData.Variant, "Normal")
	local baseIncomeRoll = math.max(0, math.floor(getCrewSummaryNumber(crewData.BaseIncomeRoll, mirrorData.BaseIncomeRoll, 0)))
	local income = getCrewSummaryIncomePerSecond(crewData, mirrorData, level)
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
		Variant = variant,
		Level = level,
		CurrentXP = currentXP,
		TotalXP = totalXP,
		NextLevelXP = getCrewXPRequiredForLevel(rarity, level),
		BaseIncomeRoll = baseIncomeRoll,
		Income = income,
		ShipIncomePerHour = getCrewSummaryIncomePerHour(crewData, mirrorData, level),
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
	player:SetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE, nil)
	player:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, nil)
	player:SetAttribute(FORCED_DROP_PROTECTION_ATTRIBUTE, nil)
	player:SetAttribute(HORO_PROJECTION_CARRY_ATTRIBUTE, nil)
end

local function getRewardToolDisplay(reward)
	if reward.RewardType == "Chest" then
		return ChestUtils.GetDisplayName(reward)
	end

	local displayInfo = CanonicalCrewCatalog.GetDisplayInfo(
		reward.CrewMemberId or reward.CrewStorageName or reward.CrewName,
		reward
	)
	return tostring(displayInfo.DisplayName or reward.CrewDisplayName or reward.DisplayName or reward.CrewName or "Crew Contract")
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
		CarryId = reward.CarryId,
		CarryOrder = reward.CarryOrder,
		SlotIndex = reward.SlotIndex,
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
		data.Variant = reward.Variant
	end

	if typeof(reward.WorldDropPosition) == "Vector3" then
		data.WorldDropPosition = reward.WorldDropPosition
	end

	return data
end

local function createDroppedWorldChest(player, reward)
	if typeof(droppedChestWorldHandler) ~= "function" then
		return false, "dropped_chest_handler_missing"
	end

	local data = cloneRewardData(reward)
	if typeof(data) ~= "table" then
		return false, "missing_dropped_chest_data"
	end

	data.RewardType = "Chest"
	data.Source = if typeof(data.Source) == "string" and data.Source ~= "" then data.Source else "DroppedWorld"

	local ok, result, resultReason = pcall(droppedChestWorldHandler, player, data)
	if not ok then
		warn(string.format("[GrandLineRush] Dropped chest world handler failed: %s", tostring(result)))
		return false, "dropped_chest_handler_failed"
	end

	if result == false then
		return false, tostring(resultReason or "dropped_chest_create_failed")
	end

	if typeof(result) == "table" and result.ok == false then
		return false, tostring(result.reason or result.error or "dropped_chest_create_failed")
	end

	if result == nil then
		return false, "dropped_chest_create_failed"
	end

	return true, nil
end

local function sanitizeReward(reward)
	local data = cloneRewardData(reward)
	if not data then
		return nil
	end

	data.DisplayName = getRewardToolDisplay(reward)
	return data
end

local function getCarrySlotConfig()
	local config = Economy.VerticalSlice.CarrySlots
	return if typeof(config) == "table" then config else {}
end

local function getMaxCarrySlots()
	local configuredMax = math.floor(tonumber(getCarrySlotConfig().MaxSlots) or DEFAULT_MAX_CARRY_SLOTS)
	return math.clamp(configuredMax, 1, DEFAULT_MAX_CARRY_SLOTS)
end

local function getUnlockedCarrySlotCount(player, runtime)
	local maxSlots = getMaxCarrySlots()
	local config = getCarrySlotConfig()
	local unlocked = math.floor(tonumber(config.DefaultUnlocked) or DEFAULT_UNLOCKED_CARRY_SLOTS)
	local temporaryUnlocked = tonumber(config.TemporaryUnlockedForTesting)
	if temporaryUnlocked ~= nil then
		unlocked = math.floor(temporaryUnlocked)
	end
	local testAttribute = tostring(config.TestUnlockedAttribute or "")
	if player and testAttribute ~= "" then
		local override = player:GetAttribute(testAttribute)
		if typeof(override) == "number" then
			unlocked = math.floor(override)
		end
	end
	if runtime and typeof(runtime.UnlockedCarrySlotCount) == "number" then
		unlocked = math.floor(runtime.UnlockedCarrySlotCount)
	end

	return math.clamp(unlocked, 1, maxSlots)
end

local function ensureCarrySlots(runtime)
	if not runtime then
		return {}
	end

	local maxSlots = getMaxCarrySlots()
	if typeof(runtime.CarrySlots) ~= "table" then
		runtime.CarrySlots = {}
	end

	for slotIndex = 1, maxSlots do
		local slot = runtime.CarrySlots[slotIndex]
		if typeof(slot) ~= "table" then
			slot = {}
			runtime.CarrySlots[slotIndex] = slot
		end
		slot.SlotIndex = slotIndex
	end

	for slotIndex = maxSlots + 1, #runtime.CarrySlots do
		runtime.CarrySlots[slotIndex] = nil
	end

	return runtime.CarrySlots
end

local function getCarrySlots(runtime)
	return ensureCarrySlots(runtime)
end

local function getCarryItemDisplayName(itemData)
	if typeof(itemData) ~= "table" then
		return "Carried Item"
	end

	local data = if typeof(itemData.Data) == "table" then itemData.Data else itemData
	if itemData.ItemType == "Chest" or data.RewardType == "Chest" then
		return ChestUtils.GetDisplayName(data)
	end

	local displayInfo = CanonicalCrewCatalog.GetDisplayInfo(
		data.CrewMemberId or data.CrewStorageName or data.CrewName,
		data
	)
	local displayName = displayInfo.DisplayName
		or itemData.DisplayName
		or data.DisplayName
		or data.CrewDisplayName
		or data.CrewName
		or data.CrewMemberId
	if typeof(displayName) == "string" and displayName ~= "" then
		return displayName
	end

	return "Crewmate"
end

local function cloneCarryData(data)
	local cloned = {}
	if typeof(data) ~= "table" then
		return cloned
	end

	for key, value in pairs(data) do
		if typeof(value) ~= "Instance" and typeof(value) ~= "function" then
			cloned[key] = value
		end
	end

	return cloned
end

local function buildLegacyRewardFromCarrySlot(slot)
	if typeof(slot) ~= "table" or typeof(slot.CarryId) ~= "string" or slot.CarryId == "" then
		return nil
	end

	local data = cloneCarryData(slot.Data)
	data.CarryId = slot.CarryId
	data.CarryOrder = slot.CarryOrder
	data.SlotIndex = slot.SlotIndex
	data.DisplayName = slot.DisplayName

	if slot.ItemType == "Chest" then
		data.RewardType = "Chest"
		data.ChestKind = data.ChestKind or ChestRewards.ChestKinds.Standard
		data.Tier = ChestUtils.NormalizeTier(data.Tier)
		return data
	end

	data.RewardType = data.RewardType or "Crew"
	data.CrewName = data.CrewName or data.DisplayName or data.CrewDisplayName or data.CrewMemberId
	data.CrewDisplayName = data.CrewDisplayName or data.DisplayName or data.CrewName
	data.CrewStorageName = data.CrewStorageName or data.CrewMemberId or data.CrewName
	return data
end

local function getFirstOccupiedCarrySlot(runtime)
	for _, slot in ipairs(getCarrySlots(runtime)) do
		if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
			return slot
		end
	end

	return nil
end

local function findCarrySlotByCarryId(runtime, carryId)
	if typeof(carryId) ~= "string" or carryId == "" then
		return nil
	end

	for _, slot in ipairs(getCarrySlots(runtime)) do
		if slot.CarryId == carryId then
			return slot
		end
	end

	return nil
end

local function findCarrySlot(runtime, slotIndexOrCarryId)
	for _, slot in ipairs(getCarrySlots(runtime)) do
		if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
			if typeof(slotIndexOrCarryId) == "number" and slot.SlotIndex == slotIndexOrCarryId then
				return slot
			end
			if typeof(slotIndexOrCarryId) == "string"
				and (slot.CarryId == slotIndexOrCarryId or tostring(slot.SlotIndex) == slotIndexOrCarryId)
			then
				return slot
			end
		end
	end

	if slotIndexOrCarryId == nil then
		return getFirstOccupiedCarrySlot(runtime)
	end

	return nil
end

local function validateSelectedCarrySlot(runtime, options)
	options = if typeof(options) == "table" then options else {}
	local carryId = options.CarryId
	if typeof(carryId) ~= "string" or carryId == "" then
		return nil, "missing_selected_carry_id"
	end

	local selectedSlotIndex = tonumber(options.SlotIndex)
	if selectedSlotIndex == nil then
		return nil, "missing_selected_carry_slot"
	end
	selectedSlotIndex = math.floor(selectedSlotIndex)

	local slot = findCarrySlotByCarryId(runtime, carryId)
	if not slot then
		return nil, "stale_selected_carry_item"
	end

	if tonumber(slot.SlotIndex) ~= selectedSlotIndex then
		return nil, "selected_carry_slot_mismatch"
	end

	return slot, nil
end

local function mirrorLegacyCarryState(player, runtime)
	local slot = getCarrySlots(runtime)[1]
	local legacyReward = buildLegacyRewardFromCarrySlot(slot)
	runtime.CarriedReward = legacyReward

	if not player then
		return legacyReward
	end

	if legacyReward == nil then
		player:SetAttribute("CarriedMajorRewardType", nil)
		player:SetAttribute("CarriedMajorRewardDisplayName", nil)
		player:SetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE, nil)
		player:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, nil)
		return nil
	end

	player:SetAttribute("CarriedMajorRewardType", legacyReward.RewardType)
	player:SetAttribute("CarriedMajorRewardDisplayName", getRewardToolDisplay(legacyReward))

	if slot.ItemType == "CrewMember" then
		player:SetAttribute(
			CARRIED_CREW_MEMBER_ATTRIBUTE,
			tostring(legacyReward.CrewDisplayName or legacyReward.DisplayName or legacyReward.CrewMemberId or legacyReward.CrewName)
		)
		local image = legacyReward.Image or legacyReward.CrewMemberImage
		player:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, if typeof(image) == "string" and image ~= "" then image else nil)
	else
		player:SetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE, nil)
		player:SetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE, nil)
	end

	return legacyReward
end

local function syncCarrySlotsToClient(player, runtime)
	mirrorLegacyCarryState(player, runtime)
end

local function findFirstEmptyUnlockedCarrySlot(player, runtime)
	local unlockedSlots = getUnlockedCarrySlotCount(player, runtime)
	for slotIndex, slot in ipairs(getCarrySlots(runtime)) do
		if slotIndex <= unlockedSlots and (typeof(slot.CarryId) ~= "string" or slot.CarryId == "") then
			return slot
		end
	end

	return nil
end

local function canCarryMore(player, runtime)
	return findFirstEmptyUnlockedCarrySlot(player, runtime) ~= nil
end

local function nextCarryId(player, runtime)
	runtime.CarrySequence = math.max(0, math.floor(tonumber(runtime.CarrySequence) or 0)) + 1
	return string.format("%d:%d:%d", player.UserId, math.max(0, tonumber(runtime.RunSequence) or 0), runtime.CarrySequence)
end

local function refreshHeldCarryVisualLayout(player)
	if CrewInteraction and typeof(CrewInteraction.RefreshHeldCarryLayout) == "function" then
		CrewInteraction.RefreshHeldCarryLayout(CrewInteraction.GetActiveContext(), player)
	end
end

local function addCarryItem(player, runtime, itemData)
	if typeof(itemData) ~= "table" then
		return nil, "invalid_carry_item"
	end

	local slot = findFirstEmptyUnlockedCarrySlot(player, runtime)
	if not slot then
		return nil, "carry_slots_full"
	end

	local itemType = tostring(itemData.ItemType or itemData.RewardType or "")
	if itemType == "Crew" or itemType == "Crewmate" then
		itemType = "CrewMember"
	elseif itemType ~= "Chest" and itemType ~= "CrewMember" then
		return nil, "invalid_carry_item_type"
	end

	local data = cloneCarryData(if typeof(itemData.Data) == "table" then itemData.Data else itemData)
	local carryOrder = tonumber(itemData.CarryOrder)
	local carryId = itemData.CarryId
	if carryId ~= nil then
		carryId = tostring(carryId)
		if carryOrder == nil then
			runtime.CarrySequence = math.max(0, math.floor(tonumber(runtime.CarrySequence) or 0)) + 1
			carryOrder = runtime.CarrySequence
		else
			runtime.CarrySequence = math.max(math.max(0, math.floor(tonumber(runtime.CarrySequence) or 0)), math.floor(carryOrder))
		end
	else
		carryId = nextCarryId(player, runtime)
		carryOrder = runtime.CarrySequence
	end
	slot.CarryId = carryId
	slot.CarryOrder = carryOrder
	slot.ItemType = itemType
	slot.DisplayName = getCarryItemDisplayName({
		ItemType = itemType,
		DisplayName = itemData.DisplayName,
		Data = data,
	})
	slot.Data = data

	player:SetAttribute(FORCED_DROP_PROTECTION_ATTRIBUTE, os.clock() + FORCED_DROP_PROTECTION_DURATION)
	syncCarrySlotsToClient(player, runtime)
	refreshHeldCarryVisualLayout(player)
	return slot, nil
end

local function removeCarryItem(player, runtime, slotIndexOrCarryId)
	local slot = findCarrySlot(runtime, slotIndexOrCarryId)
	if not slot then
		return nil, "no_carried_reward"
	end

	local removed = {
		SlotIndex = slot.SlotIndex,
		CarryId = slot.CarryId,
		CarryOrder = slot.CarryOrder,
		ItemType = slot.ItemType,
		DisplayName = slot.DisplayName,
		Data = cloneCarryData(slot.Data),
	}

	slot.CarryId = nil
	slot.CarryOrder = nil
	slot.ItemType = nil
	slot.DisplayName = nil
	slot.Data = nil
	slot.DropInProgress = nil

	syncCarrySlotsToClient(player, runtime)
	refreshHeldCarryVisualLayout(player)
	return removed, nil
end

local function restoreRemovedCarryItem(player, runtime, removed)
	if typeof(removed) ~= "table" then
		return false, "invalid_removed_carry_item"
	end

	local slotIndex = math.floor(tonumber(removed.SlotIndex) or 0)
	local slot = getCarrySlots(runtime)[slotIndex]
	if not slot then
		return false, "missing_carry_slot"
	end
	if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
		return false, "carry_slot_occupied"
	end

	slot.CarryId = removed.CarryId
	slot.CarryOrder = removed.CarryOrder
	slot.ItemType = removed.ItemType
	slot.DisplayName = removed.DisplayName
	slot.Data = cloneCarryData(removed.Data)
	slot.DropInProgress = nil

	syncCarrySlotsToClient(player, runtime)
	refreshHeldCarryVisualLayout(player)
	return true, nil
end

local function clearAllCarryItems(player, runtime, reason)
	local clearedCount = 0
	local firstCleared = nil
	for _, slot in ipairs(getCarrySlots(runtime)) do
		if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
			clearedCount += 1
			if firstCleared == nil then
				firstCleared = {
					SlotIndex = slot.SlotIndex,
					CarryId = slot.CarryId,
					ItemType = slot.ItemType,
					DisplayName = slot.DisplayName,
				}
			end
		end
	end

	if player and CrewInteraction and typeof(CrewInteraction.CollectAllHeld) == "function" then
		CrewInteraction.CollectAllHeld(CrewInteraction.GetActiveContext(), player, nil, {
			Reason = reason or "Unknown",
			SkipCarrySlotRemove = true,
			SuppressDropNotice = true,
		})
	end

	for _, slot in ipairs(getCarrySlots(runtime)) do
		slot.CarryId = nil
		slot.CarryOrder = nil
		slot.ItemType = nil
		slot.DisplayName = nil
		slot.Data = nil
		slot.DropInProgress = nil
	end

	runtime.CarriedReward = nil
	runtime.CarryDropTransaction = nil
	clearCarryTool(player)
	syncCarrySlotsToClient(player, runtime)
	if clearedCount > 0 then
		notifyCarryDrop(player, reason or "Unknown", {
			Count = clearedCount,
			Action = "ClearAllCarryItems",
			ItemType = firstCleared and firstCleared.ItemType or nil,
			DisplayName = firstCleared and firstCleared.DisplayName or nil,
			CarryId = firstCleared and firstCleared.CarryId or nil,
			SlotIndex = firstCleared and firstCleared.SlotIndex or nil,
		})
	end
end

local function hasCarryItems(runtime)
	return getFirstOccupiedCarrySlot(runtime) ~= nil
end

local function sanitizeCarrySlot(player, runtime, slot)
	local unlockedSlots = getUnlockedCarrySlotCount(player, runtime)
	local occupied = typeof(slot.CarryId) == "string" and slot.CarryId ~= ""
	local output = {
		SlotIndex = slot.SlotIndex,
		Locked = slot.SlotIndex > unlockedSlots,
		Unlocked = slot.SlotIndex <= unlockedSlots,
		Occupied = occupied,
	}

	if occupied then
		output.CarryId = slot.CarryId
		output.CarryOrder = slot.CarryOrder
		output.ItemType = slot.ItemType
		output.DisplayName = slot.DisplayName
		output.Data = cloneCarryData(slot.Data)
	end

	return output
end

local function sanitizeCarrySlots(player, runtime)
	local slots = {}
	for _, slot in ipairs(getCarrySlots(runtime)) do
		slots[#slots + 1] = sanitizeCarrySlot(player, runtime, slot)
	end
	return slots
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

local function getSharedChestConfig()
	local verticalSlice = Economy.VerticalSlice
	local worldRun = typeof(verticalSlice) == "table" and verticalSlice.WorldRun or nil
	return if typeof(worldRun) == "table" and typeof(worldRun.SharedChests) == "table" then worldRun.SharedChests else {}
end

local function getDistributionTotal(weightTable)
	local totalWeight = 0
	for _, key in ipairs(CHEST_TIER_ORDER) do
		totalWeight += math.max(0, tonumber(weightTable[key]) or 0)
	end
	return totalWeight
end

local function copyChestDistribution(weightTable)
	local copy = {}
	for _, key in ipairs(CHEST_TIER_ORDER) do
		copy[key] = math.max(0, tonumber(weightTable[key]) or 0)
	end
	return copy
end

local function getPopulationGoldBonusWeight(weightTable, activePlayerCount)
	local sharedConfig = getSharedChestConfig()
	local perExtraPlayer = math.max(0, tonumber(sharedConfig.PopulationGoldBonusPerExtraPlayer) or 0)
	local bonusCap = math.max(0, tonumber(sharedConfig.PopulationGoldBonusCap) or 0)
	local extraPlayers = math.max(0, math.floor(tonumber(activePlayerCount) or 1) - 1)
	if perExtraPlayer <= 0 or bonusCap <= 0 or extraPlayers <= 0 then
		return 0
	end

	local bonus = math.min(bonusCap, perExtraPlayer * extraPlayers)
	local totalWeight = getDistributionTotal(weightTable)
	if totalWeight <= 0 then
		return 0
	end

	-- Config values <= 1 are treated as chance fractions, so 0.01 is +1 percentage point.
	if perExtraPlayer <= 1 and bonusCap <= 1 then
		return bonus * totalWeight
	end

	return bonus
end

local function applySharedChestPopulationBonus(weightTable, activePlayerCount)
	local adjusted = copyChestDistribution(weightTable)
	local bonusWeight = getPopulationGoldBonusWeight(adjusted, activePlayerCount)
	if bonusWeight <= 0 then
		return adjusted
	end

	local remaining = bonusWeight
	local transferred = 0
	for _, sourceKey in ipairs({ "Wooden", "Iron" }) do
		local available = math.max(0, tonumber(adjusted[sourceKey]) or 0)
		local taken = math.min(available, remaining)
		adjusted[sourceKey] = available - taken
		transferred += taken
		remaining -= taken
		if remaining <= 0 then
			break
		end
	end
	adjusted.Gold = math.max(0, tonumber(adjusted.Gold) or 0) + transferred

	return adjusted
end

local function chooseChestTier(depthBand, options)
	options = if typeof(options) == "table" then options else {}
	if options.ForceGold == true and Economy.Chests.Tiers.Gold ~= nil then
		return "Gold"
	end

	local forceTier = tostring(options.ForceTier or "")
	if forceTier ~= "" and Economy.Chests.Tiers[forceTier] ~= nil then
		return forceTier
	end

	local stage = Economy.VerticalSlice.ChestStageByDepthBand[depthBand] or Economy.VerticalSlice.ChestStageByDepthBand[Economy.VerticalSlice.DefaultDepthBand]
	local distribution = Economy.Chests.ExpectedTierDistributionByStage[stage] or Economy.Chests.ExpectedTierDistributionByStage.Mid
	if options.SharedWorldChest == true then
		distribution = applySharedChestPopulationBonus(distribution, options.ActivePlayerCount)
	end
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
	for _, entry in ipairs(CanonicalCrewCatalog.GetReleasedBaseEntries()) do
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
	ChestRewards.EnsureFruitPityState(dataRoot.ChestRewards)
	return dataRoot.ChestRewards
end

local function buildStoredChestEntry(chestData)
	local normalizedChest = ChestUtils.BuildChestData(chestData)
	local storedChest = {
		ChestKind = normalizedChest.ChestKind,
		Tier = normalizedChest.Tier,
		FruitRarity = normalizedChest.FruitRarity,
		DepthBand = tostring(normalizedChest.DepthBand or ""),
		Source = tostring(normalizedChest.Source or ChestRewards.DefaultChestSource),
		RewardProfile = tostring(normalizedChest.RewardProfile or ChestRewards.DefaultRewardProfile),
		CreatedAt = math.max(0, tonumber(normalizedChest.CreatedAt) or os.time()),
	}

	if normalizedChest.PaidRandomItem == true then
		storedChest.PaidRandomItem = true
		storedChest.PaidRandomProductId = tonumber(normalizedChest.PaidRandomProductId)
		storedChest.PaidRandomPurchaseId = normalizedChest.PaidRandomPurchaseId
	end

	return storedChest
end

local function normalizeStackCount(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function ensureUnopenedChestCollection(dataRoot)
	if typeof(dataRoot.UnopenedChests) ~= "table" then
		dataRoot.UnopenedChests = {}
	end

	local unopenedChests = dataRoot.UnopenedChests
	unopenedChests.Order = unopenedChests.Order or {}
	unopenedChests.ById = unopenedChests.ById or {}
	unopenedChests.Stacks = unopenedChests.Stacks or {}
	unopenedChests.NextChestId = math.max(1, tonumber(unopenedChests.NextChestId) or 1)
	unopenedChests.StackSchemaVersion = 1

	for _, stackKey in ipairs(ChestUtils.GetStackKeys()) do
		unopenedChests.Stacks[stackKey] = normalizeStackCount(unopenedChests.Stacks[stackKey])
	end

	local seenOrderedChestIds = {}
	local normalizedOrder = {}
	local compactedStackableCount = 0

	local function keepLegacyChest(chestId, entry)
		local storedChest = buildStoredChestEntry(entry)
		storedChest.ChestId = tostring(entry.ChestId or chestId)
		unopenedChests.ById[chestId] = storedChest
		normalizedOrder[#normalizedOrder + 1] = chestId
	end

	local function compactOrKeepLegacyChest(rawChestId, entry)
		local chestId = tostring(rawChestId or "")
		if chestId == "" or typeof(entry) ~= "table" then
			if chestId ~= "" then
				unopenedChests.ById[chestId] = nil
			end
			return
		end

		local stackKey = ChestUtils.GetStackKey(entry)
		if stackKey ~= nil then
			unopenedChests.Stacks[stackKey] = normalizeStackCount(unopenedChests.Stacks[stackKey]) + 1
			unopenedChests.ById[chestId] = nil
			compactedStackableCount += 1
			return
		end

		keepLegacyChest(chestId, entry)
	end

	for _, rawChestId in ipairs(unopenedChests.Order) do
		local chestId = tostring(rawChestId or "")
		if chestId ~= "" and seenOrderedChestIds[chestId] ~= true then
			seenOrderedChestIds[chestId] = true
			local entry = unopenedChests.ById[chestId]
			if entry ~= nil then
				compactOrKeepLegacyChest(chestId, entry)
			end
		end
	end

	local unorderedLegacyChests = {}
	for rawChestId, entry in pairs(unopenedChests.ById) do
		local chestId = tostring(rawChestId or "")
		if chestId ~= "" and seenOrderedChestIds[chestId] ~= true then
			unorderedLegacyChests[#unorderedLegacyChests + 1] = {
				ChestId = chestId,
				Entry = entry,
			}
		end
	end
	for _, record in ipairs(unorderedLegacyChests) do
		compactOrKeepLegacyChest(record.ChestId, record.Entry)
	end

	unopenedChests.Order = normalizedOrder
	local unopenedStackCount = 0
	for _, amount in pairs(unopenedChests.Stacks) do
		unopenedStackCount += normalizeStackCount(amount)
	end
	unopenedChests.NextChestId = math.max(unopenedChests.NextChestId, unopenedStackCount + #normalizedOrder + 1)
	if compactedStackableCount > 0 then
		unopenedChests.CompactedStackableLegacyCount =
			normalizeStackCount(unopenedChests.CompactedStackableLegacyCount) + compactedStackableCount
	end

	return unopenedChests
end

local function addLegacyUnopenedChestToCollection(unopenedChests, chestData)
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

local function addUnopenedChestToCollection(unopenedChests, chestData, amount)
	local stackKey = ChestUtils.GetStackKey(chestData)
	if stackKey ~= nil then
		unopenedChests.Stacks = unopenedChests.Stacks or {}
		unopenedChests.NextChestId = math.max(1, tonumber(unopenedChests.NextChestId) or 1)
		local increment = math.max(1, math.floor(tonumber(amount) or 1))
		unopenedChests.Stacks[stackKey] = normalizeStackCount(unopenedChests.Stacks[stackKey]) + increment
		unopenedChests.NextChestId += increment
		return "stack:" .. stackKey, buildStoredChestEntry(chestData), increment
	end

	return addLegacyUnopenedChestToCollection(unopenedChests, chestData)
end

local function buildChestSummary(chestId, chestData, quantity)
	local normalizedChest = ChestUtils.BuildChestData(chestData)
	local safeQuantity = math.max(1, math.floor(tonumber(quantity) or 1))
	local inventoryName = ChestUtils.GetInventoryName(normalizedChest)
	local summary = {
		ChestId = chestId and tostring(chestId) or nil,
		ChestKind = normalizedChest.ChestKind,
		Tier = normalizedChest.Tier,
		FruitRarity = normalizedChest.FruitRarity,
		DepthBand = tostring(chestData.DepthBand or ""),
		Source = tostring(chestData.Source or ChestRewards.DefaultChestSource),
		RewardProfile = tostring(chestData.RewardProfile or ChestRewards.DefaultRewardProfile),
		CreatedAt = math.max(0, tonumber(chestData.CreatedAt) or 0),
		PaidRandomItem = normalizedChest.PaidRandomItem == true,
		PaidRandomProductId = tonumber(normalizedChest.PaidRandomProductId),
		InventoryName = inventoryName,
		DisplayName = ChestUtils.GetDisplayName(normalizedChest),
		Quantity = safeQuantity,
	}

	local stackKey = ChestUtils.GetStackKey(normalizedChest)
	if stackKey ~= nil and safeQuantity > 1 then
		summary.StackKey = stackKey
		summary.IsStack = true
	end

	return summary
end

local function collectUnopenedChestCounts(unopenedChests)
	local counts = {}
	local totalCount = 0

	for stackKey, amount in pairs(unopenedChests.Stacks or {}) do
		local count = normalizeStackCount(amount)
		if count > 0 then
			counts[stackKey] = normalizeStackCount(counts[stackKey]) + count
			totalCount += count
		end
	end

	for _, existingChestId in ipairs(unopenedChests.Order or {}) do
		local entry = unopenedChests.ById and unopenedChests.ById[tostring(existingChestId)]
		if entry then
			local inventoryName = ChestUtils.GetInventoryName(entry)
			counts[inventoryName] = normalizeStackCount(counts[inventoryName]) + 1
			totalCount += 1
		end
	end

	return counts, totalCount
end

local function resolveStackKeyFromName(name)
	local candidate = tostring(name or "")
	if candidate:sub(1, 6) == "stack:" then
		candidate = candidate:sub(7)
	end

	return ChestUtils.ResolveStandardTier(candidate)
end

local function countUnopenedChestsByInventoryName(unopenedChests, chestData)
	local inventoryName = ChestUtils.GetInventoryName(chestData)
	local counts = collectUnopenedChestCounts(unopenedChests)
	local count = normalizeStackCount(counts[inventoryName])

	return count
end

local function isPaidRandomChestData(chestData)
	local normalizedChest = ChestUtils.BuildChestData(chestData)
	return normalizedChest.PaidRandomItem == true
end

local function canOpenPaidRandomChest(player, chestData, context)
	if not isPaidRandomChestData(chestData) then
		return true, nil
	end

	local allowed, policyState = PaidRandomItemPolicy.CanUsePaidRandomItems(player)
	if allowed == true then
		return true, policyState
	end

	local normalizedChest = ChestUtils.BuildChestData(chestData)
	warn(string.format(
		"[GrandLineRush] Blocked paid random chest open player=%s context=%s chest=%s source=%s productId=%s policyStatus=%s reason=%s",
		player and player.Name or "<unknown>",
		tostring(context or "OpenChest"),
		tostring(ChestUtils.GetInventoryName(normalizedChest)),
		tostring(normalizedChest.Source),
		tostring(normalizedChest.PaidRandomProductId),
		tostring(policyState and policyState.Status or "unknown"),
		tostring(policyState and policyState.Reason or "policy_unknown")
	))

	return false, policyState
end

local function resolveCanonicalCrewGrantData(rewardData, options)
	rewardData = if typeof(rewardData) == "table" then rewardData else {}
	options = if typeof(options) == "table" then options else {}

	local storageName = tostring(rewardData.StorageName or "")
	if storageName == "" then
		storageName = tostring(rewardData.CrewStorageName or "")
	end
	local displayName = tostring(rewardData.CrewDisplayName or "")
	if displayName == "" then
		displayName = tostring(rewardData.DisplayName or rewardData.Name or storageName)
	end
	local crewMemberId = tostring(rewardData.CrewMemberId or "")
	local info = nil

	if storageName ~= "" then
		local resolvedStorageName
		resolvedStorageName, info = CanonicalCrewCatalog.ResolveCrewMemberId(storageName)
		if info then
			storageName = resolvedStorageName
		end
	end
	if not info and crewMemberId ~= "" then
		local resolvedCrewMemberId
		resolvedCrewMemberId, info = CanonicalCrewCatalog.ResolveCrewMemberId(crewMemberId)
		if info then
			storageName = resolvedCrewMemberId
			crewMemberId = resolvedCrewMemberId
		end
	end
	if not info and displayName ~= "" then
		local resolvedDisplayName
		resolvedDisplayName, info = CanonicalCrewCatalog.ResolveCrewMemberId(displayName)
		if info then
			storageName = resolvedDisplayName
		end
	end

	if info then
		storageName = tostring(info.CrewMemberId or storageName)
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

	local legacyStorageName = tostring(info.LegacyId or rewardData.LegacyStorageName or "")
	if legacyStorageName == storageName then
		legacyStorageName = ""
	end

	return {
		StorageName = storageName,
		LegacyStorageName = legacyStorageName,
		DisplayName = displayName,
		CrewMemberId = crewMemberId,
		ModelName = tostring(info.ModelName or ""),
		Render = tostring(info.Render or ""),
		Rarity = tostring(info.Rarity or "Common"),
		Income = tonumber(info.Income) or 0,
		CanonicalRarity = tostring(info.Rarity or "Common"),
	}
end

local function buildGrantDataFromCanonical(instanceData)
	if typeof(instanceData) ~= "table" then
		return nil
	end

	local storageName = tostring(instanceData.CrewMemberId or "")
	if storageName == "" then
		storageName = tostring(instanceData.StorageName or "")
	end
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

	local tutorialReward = options.TutorialReward == true
		or rewardData.TutorialReward == true
		or rewardData.TutorialCrewMember == true

	local ok, createdIds = AddCrewMember:AddCrewMember(player, grantData.StorageName, 1, {
		LegacyStorageName = grantData.LegacyStorageName,
		Source = source or tostring(rewardData.Source or "GrandLineRush"),
		DepthBand = tostring(rewardData.DepthBand or ""),
		TotalXP = math.max(0, math.floor(tonumber(rewardData.TotalXP) or 0)),
		TutorialReward = tutorialReward,
		TutorialToken = tostring(options.TutorialToken or rewardData.TutorialToken or ""),
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

local function tryAssignExtractedCrewToFirstEmptyQuickSlot(player, instanceId)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, {
			Reason = "invalid_player",
		}
	end

	local normalizedInstanceId = tostring(instanceId or "")
	if normalizedInstanceId == "" then
		return false, {
			Reason = "invalid_instance_id",
		}
	end

	local assignCallOk, assignOk, assignResult = pcall(function()
		return CrewQuickSlotService.AssignInstanceToSlot(player, normalizedInstanceId, 0)
	end)
	if assignCallOk ~= true then
		warn(string.format(
			"[GrandLineRush] Extracted crew quick-slot assignment errored player=%s instanceId=%s error=%s",
			player.Name,
			normalizedInstanceId,
			tostring(assignOk)
		))
		return false, {
			Reason = "quick_slot_assign_error",
		}
	end

	if assignOk == true then
		CrewInventoryDerivedCache.MarkDirty(player, CREW_EXTRACTION_QUICK_SLOT_ASSIGN_REASON)
		getCrewMemberInventoryChangedRemote():FireClient(player, {
			Reason = CREW_EXTRACTION_QUICK_SLOT_ASSIGN_REASON,
			UpdatedAt = os.clock(),
		})
		return true, assignResult
	end

	local reason = tostring(assignResult and assignResult.Reason or "")
	if reason ~= "quick_slot_unavailable" then
		warn(string.format(
			"[GrandLineRush] Extracted crew quick-slot assignment failed player=%s instanceId=%s reason=%s",
			player.Name,
			normalizedInstanceId,
			if reason ~= "" then reason else "unknown"
		))
	end

	return false, assignResult
end

local function removeDeprecatedStarterCrew(player)
	local profile = getProfileAndReplica(player)
	if not profile then
		return
	end

	local inventory = CrewInstanceService.GetCrewInventory(player)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return
	end

	local removedById = {}
	local removedCount = 0
	local clearedStands = {}
	for rawInstanceId, instanceData in pairs(inventory.ById) do
		if typeof(instanceData) == "table" and tostring(instanceData.Source or "") == STARTER_CREW_SOURCE then
			local instanceId = tostring(rawInstanceId)
			removedById[instanceId] = true
			removedCount += 1
			inventory.ById[instanceId] = nil

			CrewQuickSlotService.ClearAssignmentsForInstance(player, instanceId)

			local assignedStand = tostring(instanceData.AssignedStand or "")
			if assignedStand ~= "" then
				CrewStandIncomeAuthority.ClearStandData(player, assignedStand, "deprecated_starter_crew_cleanup")
				clearedStands[assignedStand] = true
			end
		end
	end

	if removedCount <= 0 then
		return
	end

	for index = #inventory.Order, 1, -1 do
		if removedById[tostring(inventory.Order[index])] then
			table.remove(inventory.Order, index)
		end
	end

	for standName, standData in pairs(CrewStandIncomeAuthority.GetAllStandData(player)) do
		if typeof(standData) == "table" then
			local standInstanceId = tostring(standData.CrewMemberInstanceId or "")
			if removedById[standInstanceId] and clearedStands[tostring(standName)] ~= true then
				CrewStandIncomeAuthority.ClearStandData(player, standName, "deprecated_starter_crew_cleanup")
			end
		end
	end

	local saveOk, saveReason = CrewInstanceService.SaveCrewInventory(player, inventory, {
		SourcePath = "deprecated_starter_crew_cleanup",
	})
	if saveOk ~= true then
		warn(string.format(
			"[GrandLineRush] Deprecated starter crew cleanup failed player=%s reason=%s",
			player and player.Name or "unknown",
			tostring(saveReason or "unknown")
		))
		return
	end

	CrewInventoryDerivedCache.MarkDirty(player, "deprecated_starter_crew_cleanup")
	getCrewMemberInventoryChangedRemote():FireClient(player, {
		Reason = "deprecated_starter_crew_cleanup",
		UpdatedAt = os.clock(),
	})
end

local function addUnopenedChest(player, chestInfoOrTier, depthBand)
	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		chestDebug("addUnopenedChest skipped for %s because profile/replica missing.", player and player.Name or "unknown")
		return nil
	end

	local unopenedChests = ensureUnopenedChestCollection(profile.Data)
	local normalizedChest = if typeof(chestInfoOrTier) == "table"
		then ChestUtils.BuildChestData(chestInfoOrTier)
		else ChestUtils.BuildChestData({
			ChestKind = ChestRewards.ChestKinds.Standard,
			Tier = chestInfoOrTier,
			DepthBand = depthBand,
			Source = "Run",
		})

	local chestId, storedChest, addedCount = addUnopenedChestToCollection(unopenedChests, normalizedChest)
	local inventoryQuantity = countUnopenedChestsByInventoryName(unopenedChests, storedChest)

	chestDebug(
		"addUnopenedChest player=%s inventoryName=%s tier=%s fruitRarity=%s depth=%s ref=%s added=%d quantity=%d legacyOrder=%d",
		player.Name,
		ChestUtils.GetInventoryName(storedChest),
		tostring(storedChest.Tier),
		tostring(storedChest.FruitRarity),
		tostring(storedChest.DepthBand),
		tostring(chestId),
		tonumber(addedCount) or 1,
		inventoryQuantity,
		#unopenedChests.Order
	)

	syncPaths(player, replica, {
		{ Path = { "UnopenedChests" }, Value = unopenedChests },
	}, {
		Target = "glr_add_unopened_chest",
	})

	return chestId
end

local function buildState(player, options)
	options = if typeof(options) == "table" then options else {}
	local profile, _
	if options.WaitForData == false then
		profile, _ = getProfileAndReplicaNonBlocking(player)
	else
		profile, _ = getProfileAndReplica(player)
	end
	local runtime = getRuntime(player)
	syncCarrySlotsToClient(player, runtime)

	if not profile then
		return {
			DataReady = false,
			Loading = true,
			Run = {
				InRun = runtime.InRun,
				DepthBand = runtime.DepthBand,
				SpawnedReward = sanitizeReward(runtime.SpawnedReward),
				CarriedReward = sanitizeReward(runtime.CarriedReward),
				CarrySlots = sanitizeCarrySlots(player, runtime),
				UnlockedCarrySlotCount = getUnlockedCarrySlotCount(player, runtime),
				MaxCarrySlots = getMaxCarrySlots(),
				ResolutionText = runtime.ResolutionText,
			},
		}
	end

	local dataRoot = profile.Data
	local unopenedChests = ensureUnopenedChestCollection(dataRoot)
	local chestRewardsState = ensureChestRewardsState(dataRoot)
	local foodInventory = dataRoot.FoodInventory or {}
	local materials = normalizeMaterialsTable(dataRoot.Materials)
	local leaderstats = dataRoot.leaderstats or {}
	local devilFruits = ((dataRoot.Inventory or {}).DevilFruits) or {}

	local chestSummaries = {}
	local chestCounts, unopenedChestCount = collectUnopenedChestCounts(unopenedChests)
	for _, stackKey in ipairs(ChestUtils.GetStackKeys()) do
		local stackCount = normalizeStackCount((unopenedChests.Stacks or {})[stackKey])
		if stackCount > 0 then
			chestSummaries[#chestSummaries + 1] = buildChestSummary("stack:" .. stackKey, {
				ChestKind = ChestRewards.ChestKinds.Standard,
				Tier = stackKey,
				Source = "Stack",
			}, stackCount)
		end
	end
	for _, chestId in ipairs(unopenedChests.Order or {}) do
		local entry = unopenedChests.ById and unopenedChests.ById[tostring(chestId)]
		if entry then
			chestSummaries[#chestSummaries + 1] = buildChestSummary(tostring(chestId), entry, 1)
		end
	end

	local crewSummaries = if options.IncludeCrews == true then buildCrewStateSummaries(dataRoot) else nil

	local devilFruitCount = 0
	for _, fruitEntry in pairs(devilFruits) do
		if typeof(fruitEntry) == "table" then
			devilFruitCount += math.max(0, tonumber(fruitEntry.Quantity) or 0)
		end
	end

	return {
		DataReady = true,
		Loading = false,
		Beli = CurrencyUtil.getAmountFromTable(leaderstats),
		-- Legacy payload alias kept while older clients finish moving to Beli.
		Doubloons = CurrencyUtil.getAmountFromTable(leaderstats),
		Bounty = getBountyBreakdown(player),
		Run = {
			InRun = runtime.InRun,
			DepthBand = runtime.DepthBand,
			SpawnedReward = sanitizeReward(runtime.SpawnedReward),
			CarriedReward = sanitizeReward(runtime.CarriedReward),
			CarrySlots = sanitizeCarrySlots(player, runtime),
			UnlockedCarrySlotCount = getUnlockedCarrySlotCount(player, runtime),
			MaxCarrySlots = getMaxCarrySlots(),
			ResolutionText = runtime.ResolutionText,
		},
		UnopenedChests = chestSummaries,
		UnopenedChestCounts = chestCounts,
		UnopenedChestStacks = unopenedChests.Stacks or {},
		UnopenedChestCount = unopenedChestCount,
		MythicKeyProgress = {
			current = chestRewardsState.MythicKeys,
			threshold = ChestRewards.MythicKey.Threshold,
		},
		ChestRewards = chestRewardsState,
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

local function pushState(player, options)
	local state = buildState(player, options)
	if stateRemote and player.Parent == Players then
		stateRemote:FireClient(player, state)
	end
	stateChangedEvent:Fire(player, state)
end

local function resolveActionResponse(player, ok, message, errorCode, stateOptions)
	local state = buildState(player, stateOptions)
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

local function resolveRestartLockedResponse(player, actionName)
	local blocked, message = ServerRestartService.RejectIfFinalMinuteLocked(player, actionName)
	if blocked ~= true then
		return nil
	end

	return resolveActionResponse(player, false, message, "server_restart_final_minute")
end

local carrySlotAdapterInstalled = false
local function installCarrySlotAdapter()
	if carrySlotAdapterInstalled then
		return
	end
	carrySlotAdapterInstalled = true

	if typeof(CrewInteraction.SetCarrySlotAdapter) ~= "function" then
		return
	end

	CrewInteraction.SetCarrySlotAdapter({
		CanCarryMore = function(player)
			return canCarryMore(player, getRuntime(player))
		end,
		GetCarrySlots = function(player)
			local slots = {}
			for _, slot in ipairs(getCarrySlots(getRuntime(player))) do
				if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
					slots[#slots + 1] = {
						SlotIndex = slot.SlotIndex,
						CarryId = slot.CarryId,
						CarryOrder = slot.CarryOrder,
						Occupied = true,
					}
				end
			end
			return slots
		end,
		AddCrewMember = function(player, crewData)
			crewData = if typeof(crewData) == "table" then crewData else {}
			local tutorialCrewMember = crewData.TutorialCrewMember == true
			local tutorialReward = crewData.TutorialReward == true or tutorialCrewMember
			local slot, reason = addCarryItem(player, getRuntime(player), {
				ItemType = "CrewMember",
				DisplayName = crewData.DisplayName or crewData.CrewName or crewData.CrewMemberId,
				Data = {
					RewardType = "Crew",
					CrewName = crewData.CrewName or crewData.DisplayName or crewData.CrewMemberId,
					CrewDisplayName = crewData.DisplayName or crewData.CrewName or crewData.CrewMemberId,
					CrewStorageName = crewData.CrewStorageName or crewData.CrewName or crewData.CrewMemberId,
					CrewMemberId = crewData.CrewMemberId,
					Rarity = crewData.Rarity,
					CanonicalRarity = crewData.CanonicalRarity,
					Variant = crewData.Variant,
					Image = crewData.Image,
					Physical = crewData.Physical == true,
					TutorialCrewMember = tutorialCrewMember,
					TutorialReward = tutorialReward,
					TutorialToken = if tutorialReward then tostring(crewData.TutorialToken or "") else nil,
					TutorialRewardName = if tutorialReward then tostring(crewData.TutorialRewardName or "") else nil,
					TutorialOwnerUserId = if tutorialReward then tonumber(crewData.TutorialOwnerUserId) else nil,
				},
			})
			if slot then
				pushState(player)
			end
			return slot, reason
		end,
		RemoveCarryItem = function(player, slotIndexOrCarryId)
			local removed = removeCarryItem(player, getRuntime(player), slotIndexOrCarryId)
			if removed then
				pushState(player)
			end
			return removed
		end,
	})
end

local function preparePlayerState(player)
	if not waitForDataReady(player, 10) then
		return false, resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	removeDeprecatedStarterCrew(player)
	return true
end

function Service.FailRun(player, reason)
	local runtime = getRuntime(player)
	if runtime.InRun ~= true and not hasCarryItems(runtime) and runtime.SpawnedReward == nil then
		return resolveActionResponse(player, false, nil, "not_in_run")
	end

	runtime.InRun = false
	runtime.SpawnedReward = nil
	local cleanupReason = "Unknown"
	local reasonText = tostring(reason or "")
	if string.find(reasonText, "AFK", 1, true) then
		cleanupReason = "AFKTeleport"
	elseif string.find(reasonText, "Defeated", 1, true) then
		cleanupReason = "PlayerDeath"
	end
	clearAllCarryItems(player, runtime, cleanupReason)
	runtime.ResolutionText = reason or "Run failed. Unextracted rewards were lost."

	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function startRun(player, rewardType, depthBand, options)
	options = if typeof(options) == "table" then options else {}
	local restartLocked = resolveRestartLockedResponse(player, "starting a run")
	if restartLocked ~= nil then
		return restartLocked
	end

	local runtime = getRuntime(player)
	if runtime.InRun then
		return resolveActionResponse(player, false, nil, "run_already_active")
	end
	if not canCarryMore(player, runtime) then
		return resolveActionResponse(player, false, "Extract or drop a carried reward before starting another run.", "carry_slots_full")
	end
	if runtime.SpawnedReward ~= nil then
		return resolveActionResponse(player, false, "Recover or lose your dropped reward before starting a new run.", "unresolved_spawned_reward")
	end

	if tostring(rewardType or "Chest") == "Chest" then
		return resolveActionResponse(player, false, "Chests are shared corridor rewards and no longer start as private runs.", "chests_are_shared_world_rewards")
	end

	runtime.InRun = true
	runtime.DepthBand = depthBand or Economy.VerticalSlice.DefaultDepthBand
	runtime.RunSequence += 1
	local spawnSource = tostring(options.SpawnSource or options.Source or "PrivateRun")
	local spawnedByUserId = tonumber(options.SpawnedByUserId)
	local spawnedByName = tostring(options.SpawnedByName or "")

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
			Source = spawnSource,
			SpawnSource = spawnSource,
			SpawnedByUserId = spawnedByUserId,
			SpawnedByName = spawnedByName,
		}
	else
		runtime.SpawnedReward = {
			RewardType = "Chest",
			Tier = chooseChestTier(runtime.DepthBand),
			DepthBand = runtime.DepthBand,
			Source = spawnSource,
			SpawnSource = spawnSource,
			SpawnedByUserId = spawnedByUserId,
			SpawnedByName = spawnedByName,
		}
	end

	runtime.ResolutionText = string.format(
		"%s reward spawned for the run. Pick it up, then extract it at base.",
		getRewardToolDisplay(runtime.SpawnedReward)
	)
	syncCarrySlotsToClient(player, runtime)

	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function claimSpawnedReward(player)
	local restartLocked = resolveRestartLockedResponse(player, "claiming a reward")
	if restartLocked ~= nil then
		return restartLocked
	end

	local runtime = getRuntime(player)
	if runtime.SpawnedReward == nil then
		if runtime.InRun ~= true then
			return resolveActionResponse(player, false, nil, "not_in_run")
		end
		return resolveActionResponse(player, false, nil, "no_spawned_reward")
	end
	if not canCarryMore(player, runtime) then
		return resolveActionResponse(player, false, nil, "carry_slots_full")
	end

	local rewardData = cloneRewardData(runtime.SpawnedReward)
	rewardData.WorldDropPosition = nil
	local slot, addReason = addCarryItem(player, runtime, {
		ItemType = if rewardData.RewardType == "Chest" then "Chest" else "CrewMember",
		DisplayName = getRewardToolDisplay(rewardData),
		Data = rewardData,
	})
	if not slot then
		return resolveActionResponse(player, false, nil, addReason or "carry_slots_full")
	end

	runtime.SpawnedReward = nil
	runtime.ResolutionText = string.format(
		"Carrying %s in slot %d. Extract successfully to secure it.",
		slot.DisplayName,
		slot.SlotIndex
	)

	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function grantCarrySlotReward(player, slot)
	local carriedReward = buildLegacyRewardFromCarrySlot(slot)
	if carriedReward == nil then
		return false, nil, "missing_carried_reward"
	end

	local message
	if carriedReward.RewardType == "Chest" then
		local chestId = addUnopenedChest(player, carriedReward, carriedReward.DepthBand)
		if chestId == nil then
			return false, nil, "persist_chest_failed"
		end
		message = string.format(
			"Extracted %s and stored it in Treasure.",
			getRewardToolDisplay(carriedReward)
		)
	else
		local instanceId = addCrewInstance(player, {
			Name = carriedReward.CrewName,
			DisplayName = carriedReward.CrewDisplayName or carriedReward.DisplayName or carriedReward.CrewName,
			StorageName = carriedReward.CrewStorageName,
			CrewMemberId = carriedReward.CrewMemberId,
			Variant = carriedReward.Variant,
			Rarity = carriedReward.Rarity,
			CanonicalRarity = carriedReward.CanonicalRarity,
			DepthBand = carriedReward.DepthBand,
			TutorialCrewMember = carriedReward.TutorialCrewMember == true,
			TutorialReward = carriedReward.TutorialReward == true or carriedReward.TutorialCrewMember == true,
			TutorialToken = tostring(carriedReward.TutorialToken or ""),
			TutorialRewardName = tostring(carriedReward.TutorialRewardName or ""),
		}, "GrandLineRush")
		if instanceId == nil then
			return false, nil, "persist_crew_failed"
		end
		tryAssignExtractedCrewToFirstEmptyQuickSlot(player, instanceId)
		message = string.format(
			"Recruited %s (%s) as crew #%s.",
			tostring(carriedReward.CrewDisplayName or carriedReward.CrewName or carriedReward.DisplayName),
			tostring(carriedReward.Rarity or "Common"),
			tostring(instanceId or "?")
		)
	end

	QuestSignals.Record(player, "ReachDepth", 1, {
		DepthBand = tostring(carriedReward.DepthBand or ""),
		RewardType = tostring(carriedReward.RewardType or ""),
	})
	TitleProgressService.RecordRewardExtracted(player, carriedReward)
	if carriedReward.RewardType == "Crew" then
		local extractContext = {
			Source = "GrandLineRush",
			DepthBand = tostring(carriedReward.DepthBand or ""),
			Rarity = tostring(carriedReward.Rarity or ""),
			CrewName = tostring(carriedReward.CrewName or carriedReward.DisplayName or ""),
			CrewMemberId = tostring(carriedReward.CrewMemberId or ""),
			CrewStorageName = tostring(carriedReward.CrewStorageName or ""),
		}

		if carriedReward.TutorialCrewMember == true or carriedReward.TutorialReward == true then
			extractContext.TutorialCrewMember = true
			extractContext.TutorialToken = tostring(carriedReward.TutorialToken or "")
			extractContext.TutorialRewardName = tostring(carriedReward.TutorialRewardName or "")
		end

		QuestSignals.Record(player, "ExtractCrew", 1, extractContext)
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

	return true, message, nil
end

local function storeHeldCrewMember(player, options)
	options = if typeof(options) == "table" then options else {}
	local runtime = getRuntime(player)
	local slot = findCarrySlot(runtime, options.CarryId or options.SlotIndex)
	if slot == nil then
		return false, {
			Reason = "no_carried_reward",
		}
	end
	if slot.ItemType ~= "CrewMember" then
		return false, {
			Reason = "held_item_not_crewmate",
		}
	end

	local carryId = tostring(slot.CarryId or "")
	local slotIndex = tonumber(slot.SlotIndex)
	local ok, message, reason = grantCarrySlotReward(player, slot)
	if ok ~= true then
		return false, {
			Reason = tostring(reason or "store_held_failed"),
		}
	end

	if slot.Data and slot.Data.Physical == true then
		CrewInteraction.ForgetHeldCarryItem(CrewInteraction.GetActiveContext(), player, nil, carryId, {
			Reason = "ExtractionCleanup",
			SuppressDropNotice = true,
		})
	end
	local removed = removeCarryItem(player, runtime, carryId)
	if removed then
		notifyCarryDrop(player, "ExtractionCleanup", {
			Action = "StoreHeldCrewMember",
			ItemType = removed.ItemType,
			DisplayName = removed.DisplayName,
			CarryId = removed.CarryId,
			SlotIndex = removed.SlotIndex,
		})
	end

	return true, {
		Action = "StoreHeld",
		Message = message,
		CarryId = carryId,
		SlotIndex = slotIndex,
	}
end

local function extractRun(player)
	local runtime = getRuntime(player)
	if not hasCarryItems(runtime) then
		if runtime.InRun ~= true then
			return resolveActionResponse(player, false, nil, "not_in_run")
		end
		return resolveActionResponse(player, false, nil, "no_carried_reward")
	end

	local messages = {}
	local extractedCount = 0
	local failedReason = nil
	local slotsToExtract = {}
	for _, slot in ipairs(getCarrySlots(runtime)) do
		if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
			slotsToExtract[#slotsToExtract + 1] = slot
		end
	end
	local maxExtractableCarry = getUnlockedCarrySlotCount(player, runtime)
	local extractedMaxCarry = #slotsToExtract >= maxExtractableCarry

	runTrace(
		"sliceExtractBegin player=%s carriedCount=%d inRun=%s",
		player.Name,
		#slotsToExtract,
		tostring(runtime.InRun)
	)

	for _, slot in ipairs(slotsToExtract) do
		local ok, message, reason = grantCarrySlotReward(player, slot)
		if not ok then
			failedReason = reason or "extract_failed"
			break
		end

		extractedCount += 1
		messages[#messages + 1] = message
		if slot.ItemType == "CrewMember" and slot.Data and slot.Data.Physical == true then
			CrewInteraction.ForgetHeldCarryItem(CrewInteraction.GetActiveContext(), player, nil, slot.CarryId, {
				Reason = "ExtractionCleanup",
				SuppressDropNotice = true,
			})
		end
		local removed = removeCarryItem(player, runtime, slot.CarryId)
		if removed then
			notifyCarryDrop(player, "ExtractionCleanup", {
				Action = "ExtractRun",
				ItemType = removed.ItemType,
				DisplayName = removed.DisplayName,
				CarryId = removed.CarryId,
				SlotIndex = removed.SlotIndex,
			})
		end
	end

	if extractedCount <= 0 then
		return resolveActionResponse(player, false, nil, failedReason or "extract_failed")
	end
	if extractedMaxCarry and extractedCount >= maxExtractableCarry then
		TitleProgressService.RecordMaxCarryExtraction(player)
	end

	local message = table.concat(messages, " ")
	if failedReason ~= nil then
		runtime.ResolutionText = string.format("%s Some carried rewards could not be extracted yet.", message)
		return resolveActionResponse(player, true, runtime.ResolutionText, failedReason)
	end

	runtime.InRun = false
	runtime.SpawnedReward = nil
	runtime.ResolutionText = message
	syncCarrySlotsToClient(player, runtime)
	runTrace(
		"sliceExtractComplete player=%s message=%s inRun=%s carriedAfter=%s",
		player.Name,
		tostring(message),
		tostring(runtime.InRun),
		tostring(hasCarryItems(runtime))
	)

	return resolveActionResponse(player, true, message)
end

local function claimWorldChest(player, rewardData)
	local restartLocked = resolveRestartLockedResponse(player, "claiming a shared chest")
	if restartLocked ~= nil then
		return restartLocked
	end

	local runtime = getRuntime(player)
	if runtime.InRun == true then
		return resolveActionResponse(player, false, "Finish your current run before claiming a shared chest.", "run_already_active")
	end
	if runtime.SpawnedReward ~= nil then
		return resolveActionResponse(player, false, "Recover or lose your dropped reward before claiming another chest.", "unresolved_spawned_reward")
	end
	if not canCarryMore(player, runtime) then
		return resolveActionResponse(player, false, nil, "carry_slots_full")
	end

	local reward = ChestUtils.BuildChestData(if typeof(rewardData) == "table" then rewardData else {
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = "Wooden",
		DepthBand = Economy.VerticalSlice.DefaultDepthBand,
		Source = "SharedWorld",
	})
	local tierName = tostring(reward.Tier or "Wooden")
	if Economy.Chests.Tiers[tierName] == nil then
		return resolveActionResponse(player, false, nil, "invalid_chest_tier")
	end

	local depthBand = tostring(reward.DepthBand or Economy.VerticalSlice.DefaultDepthBand)
	runtime.DepthBand = depthBand
	runtime.SpawnedReward = nil
	reward.RewardType = "Chest"
	reward.DepthBand = depthBand
	reward.Source = reward.Source or "SharedWorld"
	local slot, addReason = addCarryItem(player, runtime, {
		ItemType = "Chest",
		DisplayName = getRewardToolDisplay(reward),
		Data = reward,
	})
	if not slot then
		return resolveActionResponse(player, false, nil, addReason or "carry_slots_full")
	end

	runtime.ResolutionText = string.format(
		"Carrying %s in slot %d. Extract successfully to secure it.",
		slot.DisplayName,
		slot.SlotIndex
	)

	return resolveActionResponse(player, true, runtime.ResolutionText)
end

local function canForceCarryDrop(player, runtime, options)
	runtime = runtime or getRuntime(player)
	if not hasCarryItems(runtime) then
		return false, "no_carried_reward"
	end

	local settings = if typeof(options) == "table" then options else {}
	local protectedUntil = player:GetAttribute(FORCED_DROP_PROTECTION_ATTRIBUTE)
	if settings.IgnoreProtection ~= true and typeof(protectedUntil) == "number" and protectedUntil > os.clock() then
		return false, "carry_drop_protected"
	end

	return true, nil
end

local function getCarryDropReason(options)
	if typeof(options) ~= "table" then
		return "Unknown"
	end

	local reason = tostring(options.Reason or "")
	if reason == "" then
		return "Unknown"
	end
	return reason
end

local function isCriticalCarryDropReason(reason)
	return CRITICAL_CARRY_DROP_REASONS[tostring(reason or "")] == true
end

local function beginCarryDropTransaction(player, runtime, options, mode)
	options = if typeof(options) == "table" then options else {}
	if options.SkipDropTransaction == true then
		return nil, nil
	end

	local reason = getCarryDropReason(options)
	local active = runtime.CarryDropTransaction
	if typeof(active) == "table" then
		if not isCriticalCarryDropReason(reason) then
			carryDropTrace(
				"blocked player=%s mode=%s reason=%s activeMode=%s activeReason=%s activeId=%s",
				player and player.Name or "<nil>",
				tostring(mode),
				tostring(reason),
				tostring(active.Mode),
				tostring(active.Reason),
				tostring(active.Id)
			)
			return nil, "carry_drop_busy"
		end

		carryDropTrace(
			"preempt player=%s mode=%s reason=%s activeMode=%s activeReason=%s activeId=%s",
			player and player.Name or "<nil>",
			tostring(mode),
			tostring(reason),
			tostring(active.Mode),
			tostring(active.Reason),
			tostring(active.Id)
		)
	end

	carryDropTransactionSequence += 1
	local transaction = {
		Id = carryDropTransactionSequence,
		Mode = tostring(mode or "single"),
		Reason = reason,
		StartedAt = os.clock(),
	}
	runtime.CarryDropTransaction = transaction
	carryDropTrace(
		"begin player=%s mode=%s reason=%s id=%s",
		player and player.Name or "<nil>",
		transaction.Mode,
		transaction.Reason,
		tostring(transaction.Id)
	)
	return transaction, nil
end

local function finishCarryDropTransaction(player, runtime, transaction, response)
	if transaction == nil then
		return
	end

	local ok = typeof(response) == "table" and response.ok == true
	local errorCode = if typeof(response) == "table" then response.error else nil
	carryDropTrace(
		"end player=%s mode=%s reason=%s id=%s ok=%s error=%s elapsed=%.3f",
		player and player.Name or "<nil>",
		tostring(transaction.Mode),
		tostring(transaction.Reason),
		tostring(transaction.Id),
		tostring(ok),
		tostring(errorCode),
		os.clock() - (tonumber(transaction.StartedAt) or os.clock())
	)

	if runtime.CarryDropTransaction == transaction then
		runtime.CarryDropTransaction = nil
	end
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
	local dropReasonCode = getCarryDropReason(options)
	local transaction, transactionReason = beginCarryDropTransaction(player, runtime, options, "single")
	if transactionReason ~= nil then
		return resolveActionResponse(player, false, nil, transactionReason)
	end
	local function finishDrop(response)
		finishCarryDropTransaction(player, runtime, transaction, response)
		return response
	end

	local canDrop, reason = canForceCarryDrop(player, runtime, options)
	if not canDrop then
		return finishDrop(resolveActionResponse(player, false, nil, reason))
	end

	local slotKey = options.CarryId or options.SlotIndex
	local slot, slotReason
	if options.RequireSelectedSlot == true then
		slot, slotReason = validateSelectedCarrySlot(runtime, options)
	else
		slot = findCarrySlot(runtime, slotKey)
	end
	local droppedReward = buildLegacyRewardFromCarrySlot(slot)
	if not droppedReward then
		if options.RequireSelectedSlot == true then
			notifyCarryDrop(player, "StaleCarryState", {
				Action = "DropCarriedRewardRejected",
				Context = slotReason,
			})
		end
		return finishDrop(resolveActionResponse(player, false, nil, slotReason or "missing_carried_reward"))
	end

	slotKey = droppedReward.CarryId
	if slot.DropInProgress == true then
		return finishDrop(resolveActionResponse(player, false, nil, "drop_in_progress"))
	end

	local dropPosition = options.DropPosition
	if typeof(dropPosition) == "Vector3" then
		droppedReward.WorldDropPosition = dropPosition
	end

	slot.DropInProgress = true
	carryDropTrace(
		"single player=%s reason=%s slot=%s carryId=%s itemType=%s selected=%s",
		player and player.Name or "<nil>",
		dropReasonCode,
		tostring(droppedReward.SlotIndex),
		tostring(droppedReward.CarryId),
		tostring(slot.ItemType),
		tostring(options.RequireSelectedSlot == true)
	)

	if slot.ItemType == "Chest" then
		local removed, removeReason = removeCarryItem(player, runtime, slotKey)
		if not removed then
			slot.DropInProgress = nil
			return finishDrop(resolveActionResponse(
				player,
				false,
				nil,
				tostring(removeReason or "remove_carried_reward_failed")
			))
		end

		local dropped, dropReason = createDroppedWorldChest(player, droppedReward)
		if not dropped then
			local restored, restoreReason = restoreRemovedCarryItem(player, runtime, removed)
			if restored ~= true then
				warn(string.format(
					"[GrandLineRush] Failed to restore chest carry slot after dropped world chest failure player=%s carryId=%s reason=%s",
					player and player.Name or "unknown",
					tostring(removed.CarryId or ""),
					tostring(restoreReason or "unknown")
				))
			end
			return finishDrop(resolveActionResponse(
				player,
				false,
				nil,
				tostring(dropReason or "dropped_chest_create_failed")
			))
		end

		notifyCarryDrop(player, dropReasonCode, {
			Action = "DropCarriedChest",
			ItemType = removed.ItemType,
			DisplayName = removed.DisplayName,
			CarryId = removed.CarryId,
			SlotIndex = removed.SlotIndex,
		})
	elseif slot.ItemType == "CrewMember" and slot.Data and slot.Data.Physical == true then
		local droppedPhysical, dropReason = CrewInteraction.DropHeldAtPosition(
			CrewInteraction.GetActiveContext(),
			player,
			nil,
			dropPosition,
			droppedReward.CarryId,
			{
				Reason = dropReasonCode,
				SkipCarrySlotRemove = true,
			}
		)
		if not droppedPhysical then
			slot.DropInProgress = nil
			notifyCarryDrop(player, "StaleCarryState", {
				Action = "PhysicalCrewDropRejected",
				ItemType = slot.ItemType,
				DisplayName = slot.DisplayName,
				CarryId = droppedReward.CarryId,
				SlotIndex = droppedReward.SlotIndex,
				Context = dropReason,
			})
			return finishDrop(resolveActionResponse(player, false, nil, tostring(dropReason or "no_held_crew_member")))
		end
		local removed, removeReason = removeCarryItem(player, runtime, slotKey)
		if not removed then
			slot.DropInProgress = nil
			return finishDrop(resolveActionResponse(
				player,
				false,
				nil,
				tostring(removeReason or "remove_carried_reward_failed")
			))
		end
	else
		if runtime.SpawnedReward ~= nil then
			slot.DropInProgress = nil
			return finishDrop(resolveActionResponse(player, false, nil, "unresolved_spawned_reward"))
		end
		runtime.SpawnedReward = droppedReward
		local removed, removeReason = removeCarryItem(player, runtime, slotKey)
		if not removed then
			slot.DropInProgress = nil
			runtime.SpawnedReward = nil
			return finishDrop(resolveActionResponse(
				player,
				false,
				nil,
				tostring(removeReason or "remove_carried_reward_failed")
			))
		end
		notifyCarryDrop(player, dropReasonCode, {
			Action = "DropCarriedReward",
			ItemType = removed.ItemType,
			DisplayName = removed.DisplayName,
			CarryId = removed.CarryId,
			SlotIndex = removed.SlotIndex,
		})
	end

	if droppedReward.RewardType == "Chest" then
		runtime.ResolutionText = string.format("%s was dropped back into the world.", getRewardToolDisplay(droppedReward))
	else
		runtime.ResolutionText = string.format(
			"%s was dropped. Recover it before extracting.",
			getRewardToolDisplay(droppedReward)
		)
	end
	syncCarrySlotsToClient(player, runtime)

	return finishDrop(resolveActionResponse(player, true, runtime.ResolutionText))
end

local function dropAllCarriedRewards(player, options)
	local runtime = getRuntime(player)
	options = if typeof(options) == "table" then options else {}
	local transaction, transactionReason = beginCarryDropTransaction(player, runtime, options, "all")
	if transactionReason ~= nil then
		return resolveActionResponse(player, false, nil, transactionReason)
	end
	local function finishDrop(response)
		finishCarryDropTransaction(player, runtime, transaction, response)
		return response
	end

	local canDrop, reason = canForceCarryDrop(player, runtime, options)
	if not canDrop then
		return finishDrop(resolveActionResponse(player, false, nil, reason))
	end

	local occupiedSlots = {}
	for _, slot in ipairs(getCarrySlots(runtime)) do
		if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
			occupiedSlots[#occupiedSlots + 1] = {
				SlotIndex = slot.SlotIndex,
				CarryId = slot.CarryId,
			}
		end
	end

	if #occupiedSlots <= 0 then
		return finishDrop(resolveActionResponse(player, false, nil, "no_carried_reward"))
	end

	carryDropTrace(
		"all player=%s reason=%s count=%d",
		player and player.Name or "<nil>",
		getCarryDropReason(options),
		#occupiedSlots
	)

	local droppedCount = 0
	local firstError = nil
	for _, slotRef in ipairs(occupiedSlots) do
		local dropOptions = table.clone(options)
		dropOptions.SlotIndex = slotRef.SlotIndex
		dropOptions.CarryId = slotRef.CarryId
		dropOptions.SkipDropTransaction = true
		local response = dropCarriedReward(player, dropOptions)
		if response and response.ok == true then
			droppedCount += 1
		else
			firstError = firstError or (response and response.error) or "drop_failed"
			if firstError == "unresolved_spawned_reward" then
				break
			end
		end
	end

	if droppedCount <= 0 then
		return finishDrop(resolveActionResponse(player, false, nil, firstError or "drop_failed"))
	end

	local message = if droppedCount == 1
		then "Dropped carried item."
		else string.format("Dropped %d carried items.", droppedCount)
	return finishDrop(resolveActionResponse(player, true, message, firstError))
end

local function dropCarriedChestRewardsForDeath(player, runtime)
	runtime = runtime or getRuntime(player)
	local rootPart = getCharacterDropRootPart(player)
	local dropPosition = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil
	local chestSlots = {}

	for _, slot in ipairs(getCarrySlots(runtime)) do
		if slot.ItemType == "Chest" and typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
			chestSlots[#chestSlots + 1] = {
				CarryId = slot.CarryId,
				SlotIndex = slot.SlotIndex,
			}
		end
	end

	local droppedCount = 0
	local firstError = nil
	for _, slotRef in ipairs(chestSlots) do
		local response = dropCarriedReward(player, {
			Reason = "PlayerDeath",
			DropPosition = dropPosition,
			IgnoreProtection = true,
			SlotIndex = slotRef.SlotIndex,
			CarryId = slotRef.CarryId,
		})
		if response and response.ok == true then
			droppedCount += 1
		else
			firstError = firstError or (response and response.error) or "death_chest_drop_failed"
		end
	end

	return droppedCount, #chestSlots, firstError
end

local function dropCarriedCrewMember(player, dropPosition)
	carryDropTrace("legacyCrew player=%s reason=PlayerDrop", player and player.Name or "<nil>")
	local ok, result = CrewInteraction.DropHeldAtPosition(
		CrewInteraction.GetActiveContext(),
		player,
		nil,
		dropPosition,
		nil,
		{
			Reason = "PlayerDrop",
		}
	)
	if ok then
		return resolveActionResponse(player, true, "Crewmate dropped.")
	end

	return resolveActionResponse(player, false, nil, tostring(result or "no_held_crew_member"))
end

local function openChest(player, requestedChestId)
	local restartLocked = resolveRestartLockedResponse(player, "opening chests")
	if restartLocked ~= nil then
		return restartLocked
	end

	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local dataRoot = profile.Data
	local unopenedChests = ensureUnopenedChestCollection(dataRoot)

	local chestId = requestedChestId and tostring(requestedChestId) or ""
	local stackKey = nil
	local chestData = nil
	if chestId ~= "" then
		chestData = unopenedChests.ById[chestId]
		if typeof(chestData) ~= "table" then
			local requestedStackKey = resolveStackKeyFromName(chestId)
			if requestedStackKey ~= nil and normalizeStackCount(unopenedChests.Stacks[requestedStackKey]) > 0 then
				stackKey = requestedStackKey
				chestData = ChestUtils.BuildChestData({
					ChestKind = ChestRewards.ChestKinds.Standard,
					Tier = stackKey,
					Source = "Stack",
				})
			end
		end
	else
		for _, candidateStackKey in ipairs(ChestUtils.GetStackKeys()) do
			if normalizeStackCount(unopenedChests.Stacks[candidateStackKey]) > 0 then
				stackKey = candidateStackKey
				chestData = ChestUtils.BuildChestData({
					ChestKind = ChestRewards.ChestKinds.Standard,
					Tier = stackKey,
					Source = "Stack",
				})
				break
			end
		end
		if chestData == nil then
			local blockedPaidChest = false
			for _, candidateChestId in ipairs(unopenedChests.Order or {}) do
				local candidateId = tostring(candidateChestId)
				local candidateChestData = unopenedChests.ById[candidateId]
				if typeof(candidateChestData) == "table" then
					local canOpenCandidate = canOpenPaidRandomChest(player, candidateChestData, "OpenChest")
					if canOpenCandidate then
						chestId = candidateId
						chestData = candidateChestData
						break
					end
					blockedPaidChest = true
				end
			end
			if chestData == nil and blockedPaidChest then
				return resolveActionResponse(player, false, MonetizationConfig.PaidRandomItemUnavailableMessage, "paid_random_items_restricted")
			end
		end
	end

	if chestId == "" and stackKey == nil then
		return resolveActionResponse(player, false, nil, "no_chests_available")
	end

	if typeof(chestData) ~= "table" then
		return resolveActionResponse(player, false, nil, "missing_chest")
	end

	local canOpenPaidChest = canOpenPaidRandomChest(player, chestData, "OpenChest")
	if canOpenPaidChest ~= true then
		return resolveActionResponse(player, false, MonetizationConfig.PaidRandomItemUnavailableMessage, "paid_random_items_restricted")
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

	if stackKey ~= nil then
		unopenedChests.Stacks[stackKey] = math.max(0, normalizeStackCount(unopenedChests.Stacks[stackKey]) - 1)
	else
		unopenedChests.ById[chestId] = nil
		for index = #unopenedChests.Order, 1, -1 do
			if tostring(unopenedChests.Order[index]) == chestId then
				table.remove(unopenedChests.Order, index)
				break
			end
		end
	end
	local changedRoots = resolution.ChangedRoots or {}
	changedRoots.UnopenedChests = true

	local changedPaths = buildRewardChangedPaths(dataRoot, changedRoots, {
		UnopenedChests = unopenedChests,
	})

	syncPaths(player, replica, changedPaths, {
		Target = "glr_open_chest",
	})

	local rewardParts = {}
	local grantedResources = (resolution.OpenResult and resolution.OpenResult.GrantedResources) or {}
	TitleProgressService.RecordChestOpened(player, normalizedChestData, resolution.OpenResult)
	QuestSignals.Record(player, "OpenChest", 1, {
		Tier = tostring(tierName or ""),
		ChestKind = tostring(normalizedChestData.ChestKind or ""),
		FruitRarity = tostring(normalizedChestData.FruitRarity or ""),
	})
	local grantedBeli = getGrantedBeli(grantedResources)
	if grantedBeli > 0 then
		QuestSignals.Record(player, "EarnBeli", grantedBeli, {
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
	triggerResourceTutorialsAfterGrant(player, "chest_open", grantedResources)

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
	if grantedBeli > 0 then
		rewardParts[#rewardParts + 1] = CurrencyUtil.formatAmount(grantedBeli)
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

local function mergeGrantedResources(target, source)
	target = if typeof(target) == "table" then target else {}
	source = if typeof(source) == "table" then source else {}
	target.food = if typeof(target.food) == "table" then target.food else {}
	target.materials = if typeof(target.materials) == "table" then target.materials else {}

	for foodKey, amount in pairs(source.food or {}) do
		target.food[foodKey] = math.max(0, tonumber(target.food[foodKey]) or 0) + math.max(0, tonumber(amount) or 0)
	end
	for materialKey, amount in pairs(source.materials or {}) do
		target.materials[materialKey] = math.max(0, tonumber(target.materials[materialKey]) or 0) + math.max(0, tonumber(amount) or 0)
	end
	target.beli = math.max(0, tonumber(target.beli) or 0) + getGrantedBeli(source)
	target.doubloons = target.beli

	return target
end

local function mergeChangedRoots(target, source)
	for key, value in pairs(source or {}) do
		if value == true then
			target[key] = true
		end
	end
end

local function recordChestRewardQuestSignals(player, normalizedChestData, grantedResources)
	local tierName = normalizedChestData.Tier
	QuestSignals.Record(player, "OpenChest", 1, {
		Tier = tostring(tierName or ""),
		ChestKind = tostring(normalizedChestData.ChestKind or ""),
		FruitRarity = tostring(normalizedChestData.FruitRarity or ""),
	})
	local grantedBeli = getGrantedBeli(grantedResources)
	if grantedBeli > 0 then
		QuestSignals.Record(player, "EarnBeli", grantedBeli, {
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
end

local function buildBatchOpenResult(openedChestName, openedCount, aggregateResources, batchResults)
	local grantedFruits = {}
	local duplicateCount = 0
	local convertedChestCount = 0
	local convertedChestCounts = {}
	local autoConvertedChestCount = 0
	local autoConvertedChestCounts = {}
	local conversionBeli = 0
	local mythicKeyCount = 0
	local fruitPityProgress = nil
	local fruitPityTriggers = {}
	local fruitRewardContexts = {}

	for _, result in ipairs(batchResults) do
		if typeof(result.FruitPityProgress) == "table" then
			fruitPityProgress = result.FruitPityProgress
		end
		if typeof(result.FruitPityTriggered) == "table" then
			fruitPityTriggers[#fruitPityTriggers + 1] = result.FruitPityTriggered
		end
		if typeof(result.FruitRewardContext) == "table" then
			fruitRewardContexts[#fruitRewardContexts + 1] = result.FruitRewardContext
		end
		if result.GrantedFruit then
			grantedFruits[#grantedFruits + 1] = {
				FruitKey = result.GrantedFruit,
				Rarity = result.GrantedFruitRarity,
			}
		end
		if result.WasDuplicate == true then
			duplicateCount += 1
		end
		if result.ConversionRewardType == "Chest" then
			convertedChestCount += 1
			local convertedChestName = tostring(
				result.ConversionRewardDisplayName
					or ((result.GrantedChest or {}).displayName)
					or "Devil Fruit Chest"
			)
			convertedChestCounts[convertedChestName] = math.max(0, tonumber(convertedChestCounts[convertedChestName]) or 0) + 1
		elseif result.ConversionRewardType == "Beli" or result.ConversionRewardType == "Doubloons" then
			conversionBeli += math.max(0, tonumber(result.ConversionRewardAmount) or 0)
		elseif result.ConversionRewardType == "MythicKey" then
			mythicKeyCount += math.max(0, tonumber(result.ConversionRewardAmount) or 0)
		end

		if result.AutoConvertedMythicChest == true and typeof(result.GrantedChest) == "table" then
			local grantedChest = result.GrantedChest
			local displayName = tostring(grantedChest.displayName or "Mythic Devil Fruit Chest")
			local inventoryName = tostring(grantedChest.inventoryName or displayName)
			local chestKind = tostring(grantedChest.kind or "")
			local tierName = tostring(grantedChest.tier or "")
			local fruitRarity = tostring(grantedChest.fruitRarity or "")
			local stableKey = table.concat({
				chestKind,
				inventoryName,
				fruitRarity,
				tierName,
				displayName,
			}, "|")
			local autoConvertedEntry = autoConvertedChestCounts[stableKey]
			if autoConvertedEntry == nil then
				autoConvertedEntry = {
					DisplayName = displayName,
					InventoryName = inventoryName,
					ChestKind = chestKind,
					Tier = tierName,
					FruitRarity = fruitRarity,
					Rarity = if fruitRarity ~= "" then fruitRarity else tierName,
					Amount = 0,
				}
				autoConvertedChestCounts[stableKey] = autoConvertedEntry
			end

			autoConvertedEntry.Amount += 1
			autoConvertedChestCount += 1
		end
	end

	local convertedChests = {}
	for displayName, amount in pairs(convertedChestCounts) do
		convertedChests[#convertedChests + 1] = {
			DisplayName = displayName,
			Amount = amount,
		}
	end
	table.sort(convertedChests, function(a, b)
		return tostring(a.DisplayName) < tostring(b.DisplayName)
	end)

	local autoConvertedChests = {}
	for _, entry in pairs(autoConvertedChestCounts) do
		autoConvertedChests[#autoConvertedChests + 1] = entry
	end
	table.sort(autoConvertedChests, function(a, b)
		if tostring(a.DisplayName) == tostring(b.DisplayName) then
			return tostring(a.InventoryName) < tostring(b.InventoryName)
		end
		return tostring(a.DisplayName) < tostring(b.DisplayName)
	end)

	return {
		IsBatch = true,
		OpenedCount = openedCount,
		OpenedChest = {
			displayName = ChestUtils.GetDisplayName(openedChestName),
		},
		GrantedResources = aggregateResources,
		GrantedFruits = grantedFruits,
		DuplicateCount = duplicateCount,
		ConvertedChestCount = convertedChestCount,
		ConvertedChests = convertedChests,
		AutoConvertedChestCount = autoConvertedChestCount,
		AutoConvertedChests = autoConvertedChests,
		ConversionBeli = conversionBeli,
		-- Legacy payload alias kept while older clients finish moving to Beli.
		ConversionDoubloons = conversionBeli,
		MythicKeyCount = mythicKeyCount,
		FruitPityProgress = fruitPityProgress,
		FruitPityTriggers = fruitPityTriggers,
		FruitRewardContexts = fruitRewardContexts,
	}
end

local function openChests(player, inventoryName, requestedAmount)
	local restartLocked = resolveRestartLockedResponse(player, "opening chests")
	if restartLocked ~= nil then
		return restartLocked
	end

	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local targetInventoryName = tostring(inventoryName or "")
	if targetInventoryName == "" then
		return resolveActionResponse(player, false, nil, "invalid_chest_name")
	end

	local requestedCount = math.clamp(math.floor(tonumber(requestedAmount) or 1), 1, MAX_BATCH_CHEST_OPEN_COUNT)
	local dataRoot = profile.Data
	local unopenedChests = ensureUnopenedChestCollection(dataRoot)

	local targetStackKey = resolveStackKeyFromName(targetInventoryName)
	local stackOpenCount = 0
	if targetStackKey ~= nil then
		stackOpenCount = math.min(requestedCount, normalizeStackCount(unopenedChests.Stacks[targetStackKey]))
	end

	local legacyNeededCount = requestedCount - stackOpenCount
	local chestIds = {}
	local skippedPaidChest = false
	if legacyNeededCount > 0 then
		for _, chestId in ipairs(unopenedChests.Order) do
			local chestData = unopenedChests.ById[tostring(chestId)]
			if chestData and ChestUtils.GetInventoryName(chestData) == targetInventoryName then
				local canOpenCandidate = canOpenPaidRandomChest(player, chestData, "OpenChests")
				if canOpenCandidate then
					chestIds[#chestIds + 1] = tostring(chestId)
					if #chestIds >= legacyNeededCount then
						break
					end
				else
					skippedPaidChest = true
				end
			end
		end
	end

	if stackOpenCount + #chestIds <= 0 then
		if skippedPaidChest then
			return resolveActionResponse(player, false, MonetizationConfig.PaidRandomItemUnavailableMessage, "paid_random_items_restricted")
		end
		return resolveActionResponse(player, false, nil, "no_chests_available")
	end

	local changedRoots = { UnopenedChests = true }
	local aggregateResources = {
		food = {},
		materials = {},
		beli = 0,
		doubloons = 0,
	}
	local batchResults = {}
	local openedCount = 0

	if targetStackKey ~= nil and stackOpenCount > 0 then
		for _ = 1, stackOpenCount do
			if normalizeStackCount(unopenedChests.Stacks[targetStackKey]) <= 0 then
				break
			end

			local normalizedChestData = ChestUtils.BuildChestData({
				ChestKind = ChestRewards.ChestKinds.Standard,
				Tier = targetStackKey,
				Source = "Stack",
			})
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

			unopenedChests.Stacks[targetStackKey] = math.max(
				0,
				normalizeStackCount(unopenedChests.Stacks[targetStackKey]) - 1
			)
			openedCount += 1
			local openResult = resolution.OpenResult or {}
			batchResults[#batchResults + 1] = openResult
			mergeChangedRoots(changedRoots, resolution.ChangedRoots)
			mergeGrantedResources(aggregateResources, openResult.GrantedResources)
			recordChestRewardQuestSignals(player, normalizedChestData, openResult.GrantedResources or {})
			TitleProgressService.RecordChestOpened(player, normalizedChestData, openResult)
		end
	end

	for _, chestId in ipairs(chestIds) do
		local chestData = unopenedChests.ById[chestId]
		if typeof(chestData) == "table" then
			local normalizedChestData = ChestUtils.BuildChestData(chestData)
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
			openedCount += 1
			local openResult = resolution.OpenResult or {}
			batchResults[#batchResults + 1] = openResult
			mergeChangedRoots(changedRoots, resolution.ChangedRoots)
			mergeGrantedResources(aggregateResources, openResult.GrantedResources)
			recordChestRewardQuestSignals(player, normalizedChestData, openResult.GrantedResources or {})
			TitleProgressService.RecordChestOpened(player, normalizedChestData, openResult)
		end
	end

	if openedCount <= 0 then
		return resolveActionResponse(player, false, nil, "no_chests_available")
	end

	local removedChestIds = {}
	for _, chestId in ipairs(chestIds) do
		removedChestIds[tostring(chestId)] = true
	end
	for index = #unopenedChests.Order, 1, -1 do
		if removedChestIds[tostring(unopenedChests.Order[index])] == true then
			table.remove(unopenedChests.Order, index)
		end
	end

	local changedPaths = buildRewardChangedPaths(dataRoot, changedRoots, {
		UnopenedChests = unopenedChests,
	})
	syncPaths(player, replica, changedPaths, {
		Target = "glr_open_chests",
	})
	triggerResourceTutorialsAfterGrant(player, "chest_batch_open", aggregateResources)

	local response = resolveActionResponse(player, true, string.format("Opened %d chests.", openedCount))
	response.openResult = buildBatchOpenResult(targetInventoryName, openedCount, aggregateResources, batchResults)
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
	local unopenedChests = ensureUnopenedChestCollection(dataRoot)

	local options = if typeof(sourceOptions) == "table" then sourceOptions else {}
	if options.PaidRandomItem == true
		or options.RequiresPaidRandomItemPolicy == true
		or tostring(options.Source or "") == "Purchase"
	then
		local allowed, policyState = PaidRandomItemPolicy.CanUsePaidRandomItems(player)
		if allowed ~= true then
			warn(string.format(
				"[GrandLineRush] Blocked paid random direct fruit reward player=%s fruit=%s source=%s policyStatus=%s reason=%s",
				player and player.Name or "<unknown>",
				tostring(fruitIdentifier),
				tostring(options.Source or ""),
				tostring(policyState and policyState.Status or "unknown"),
				tostring(policyState and policyState.Reason or "policy_unknown")
			))
			return resolveActionResponse(player, false, MonetizationConfig.PaidRandomItemUnavailableMessage, "paid_random_items_restricted")
		end
	end

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
	syncPaths(player, replica, changedPaths, {
		Target = "glr_grant_specific_fruit",
	})

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
	local restartLocked = resolveRestartLockedResponse(player, "feeding crewmates")
	if restartLocked ~= nil then
		return restartLocked
	end

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
	}, {
		Target = "glr_feed_crew",
	})

	completeContextualTutorial(player, "FeedCrewmates", {
		Source = "vertical_slice_feed_crew",
		CrewInstanceId = tostring(canonicalInstanceId or crewInstanceId or ""),
		FoodKey = tostring(foodKey or ""),
		Level = level,
		LevelUps = levelUps,
	})

	if levelUps > 0 then
		QuestSignals.Record(player, "UpgradeCrew", levelUps, {
			CrewInstanceId = tostring(canonicalInstanceId or crewInstanceId or ""),
			CrewName = tostring(grantData.DisplayName or updatedCanonical.DisplayName or updatedCanonical.StorageName or ""),
			Rarity = tostring(rarity or ""),
			FoodKey = tostring(foodKey or ""),
			Level = level,
		})
		TitleProgressService.RecordCrewLevelsGained(player, levelUps)
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
	local actionLabel = "GrandLineRush." .. tostring(actionName or "unknown")
	local actionTrace = GTRActionDiagnostics.Start(actionLabel, player, {
		Target = tostring(actionName or ""),
	})
	local function finish(response)
		local okResult = typeof(response) == "table" and response.ok == true
		actionTrace:finish(if okResult then "ok" else "failed", {
			Target = tostring(actionName or ""),
			Reason = if typeof(response) == "table" then response.error else "invalid_response",
		})
		return response
	end

	-- Security: shared guard rejects malformed/spammed action calls before run/chest state can mutate.
	if not RemoteGuard.Check(player, "GrandLineRushSliceRequest", { actionName, payload }, {
		Cooldown = 0.05,
		ActionIndex = 1,
		ActionAllowlist = REQUEST_ACTION_ALLOWLIST,
		Args = {
			{ Type = "string", MaxLength = 40 },
			{ Type = "table", AllowNil = true },
		},
	}) then
		actionTrace:phase("guard", {
			Result = "failed",
			Reason = "remote_guard_rejected",
		})
		return finish(resolveActionResponse(player, false, nil, "remote_guard_rejected", {
			WaitForData = false,
		}))
	end
	actionTrace:phase("guard", {
		Result = "ok",
	})

	if typeof(actionName) ~= "string" then
		return finish(resolveActionResponse(player, false, nil, "invalid_action", {
			WaitForData = false,
		}))
	end

	if actionName == "GetState" then
		local dataReady = DataManager:IsReady(player)
		actionTrace:phase("ready_check", {
			Result = if dataReady then "ok" else "loading",
			Reason = if dataReady then nil else "data_not_ready",
		})
		local response = resolveActionResponse(player, true, nil, nil, {
			IncludeCrews = typeof(payload) == "table" and payload.IncludeCrews == true,
			WaitForData = false,
		})
		if not dataReady then
			response.loading = true
			response.partial = true
			response.reason = "data_not_ready"
			if typeof(response.state) == "table" then
				response.state.Loading = true
				response.state.Partial = true
				response.state.Reason = "data_not_ready"
			end
			actionTrace:phase("partial_state", {
				Result = "loading",
				Reason = "data_not_ready",
			})
		else
			actionTrace:phase("full_state_build", {
				Result = "ok",
			})
		end
		return finish(response)
	end

	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return finish(errorResponse)
	end

	if actionName == "OpenChest" then
		return finish(openChest(player, payload and payload.ChestId))
	elseif actionName == "OpenChests" then
		return finish(openChests(player, payload and payload.InventoryName, payload and payload.Amount))
	elseif actionName == "DropCarriedReward" then
		local dropPosition = getManualDropPosition(player)
		if typeof(dropPosition) ~= "Vector3" then
			return finish(resolveActionResponse(player, false, nil, "missing_drop_position"))
		end

		local runtime = getRuntime(player)
		if hasCarryItems(runtime) then
			return finish(dropCarriedReward(player, {
				Reason = "PlayerDrop",
				DropPosition = dropPosition,
				IgnoreProtection = true,
				RequireSelectedSlot = true,
				SlotIndex = payload and payload.SlotIndex,
				CarryId = payload and payload.CarryId,
			}))
		end

		local crewMemberContext = CrewInteraction.GetActiveContext()
		if hasCarriedCrewMember(player) or CrewInteraction.HasHeld(crewMemberContext, player) then
			return finish(dropCarriedCrewMember(player, dropPosition))
		end

		return finish(resolveActionResponse(player, false, nil, "no_carried_item"))
	elseif actionName == "FeedCrew" then
		return finish(feedCrew(player, payload and payload.CrewInstanceId, payload and payload.FoodKey))
	end

	return finish(resolveActionResponse(player, false, nil, "unknown_action"))
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
		if runtime.InRun or hasCarryItems(runtime) or runtime.SpawnedReward ~= nil then
			local droppedChestCount = 0
			if hasCarryItems(runtime) then
				droppedChestCount = dropCarriedChestRewardsForDeath(player, runtime)
			end

			if runtime.InRun or hasCarryItems(runtime) or runtime.SpawnedReward ~= nil then
				local message = if droppedChestCount > 0
					then "Defeated. Carried chests were dropped into the world; other unextracted rewards were lost."
					else "Defeated before securing the reward. Unextracted rewards were lost."
				Service.FailRun(player, message)
			elseif droppedChestCount > 0 then
				runtime.ResolutionText = if droppedChestCount == 1
					then "Defeated. Carried chest was dropped into the world."
					else string.format("Defeated. %d carried chests were dropped into the world.", droppedChestCount)
				syncCarrySlotsToClient(player, runtime)
			end
		end
	end)
end

local function onPlayerAdded(player)
	task.spawn(function()
		if waitForDataReady(player, 15) then
			removeDeprecatedStarterCrew(player)
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
	installCarrySlotAdapter()

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

function Service.SetDroppedChestWorldHandler(handler)
	droppedChestWorldHandler = if typeof(handler) == "function" then handler else nil
end

function Service.GetState(player, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	if options.WaitForData == nil then
		options.WaitForData = false
	end
	return buildState(player, options)
end

function Service.GetCorridorRuntimeSnapshot(options)
	options = if typeof(options) == "table" then options else {}
	local maxDetails = math.max(0, math.floor(tonumber(options.MaxDetails) or 60))
	local snapshot = {
		PlayersWithRuntime = 0,
		WorldAvailableCount = 0,
		Spawned = {
			Total = 0,
			Chests = 0,
			Crewmates = 0,
			ByType = {},
			ByTier = {},
			ByRarity = {},
			ByVariant = {},
			BySource = {},
		},
		Carried = {
			Total = 0,
			Chests = 0,
			Crewmates = 0,
			ByType = {},
			ByTier = {},
			ByRarity = {},
			ByVariant = {},
			BySource = {},
		},
		Details = {},
	}

	local function incrementCount(counts, key, amount)
		local normalizedKey = tostring(key or "")
		if normalizedKey == "" then
			normalizedKey = "Unknown"
		end
		counts[normalizedKey] = (tonumber(counts[normalizedKey]) or 0) + (amount or 1)
	end

	local function appendDetail(detail)
		if #snapshot.Details >= maxDetails then
			return
		end
		snapshot.Details[#snapshot.Details + 1] = detail
	end

	local function countReward(bucket, reward)
		local rewardType = tostring(reward and reward.RewardType or "")
		if rewardType == "" then
			rewardType = "Unknown"
		elseif rewardType == "CrewMember" then
			rewardType = "Crew"
		end

		bucket.Total += 1
		incrementCount(bucket.ByType, rewardType)
		if rewardType == "Chest" then
			bucket.Chests += 1
			incrementCount(bucket.ByTier, reward and reward.Tier or "Unknown")
		elseif rewardType == "Crew" then
			bucket.Crewmates += 1
			incrementCount(bucket.ByRarity, reward and reward.Rarity or "Unknown")
			incrementCount(bucket.ByVariant, reward and reward.Variant or "Normal")
		end
		incrementCount(bucket.BySource, reward and (reward.SpawnSource or reward.Source) or "Unknown")
	end

	for player, runtime in pairs(runtimeByPlayer) do
		if player and player.Parent == Players and typeof(runtime) == "table" then
			snapshot.PlayersWithRuntime += 1

			local spawnedReward = sanitizeReward(runtime.SpawnedReward)
			if spawnedReward then
				snapshot.WorldAvailableCount += 1
				countReward(snapshot.Spawned, spawnedReward)
				appendDetail({
					Kind = "LegacyRunReward",
					RewardType = tostring(spawnedReward.RewardType or "Unknown"),
					Status = "Spawned",
					Source = tostring(spawnedReward.SpawnSource or spawnedReward.Source or "PrivateRun"),
					DisplayName = tostring(spawnedReward.DisplayName or "Reward"),
					Tier = tostring(spawnedReward.Tier or ""),
					DepthBand = tostring(spawnedReward.DepthBand or ""),
					Rarity = tostring(spawnedReward.Rarity or ""),
					Variant = tostring(spawnedReward.Variant or ""),
					CrewMemberId = tostring(spawnedReward.CrewMemberId or ""),
					OwnerUserId = player.UserId,
					OwnerName = player.Name,
					SpawnedByUserId = tonumber(spawnedReward.SpawnedByUserId) or 0,
					SpawnedByName = tostring(spawnedReward.SpawnedByName or ""),
				})
			end

			for _, slot in ipairs(getCarrySlots(runtime)) do
				if typeof(slot.CarryId) == "string" and slot.CarryId ~= "" then
					local carriedReward = buildLegacyRewardFromCarrySlot(slot)
					if carriedReward then
						countReward(snapshot.Carried, carriedReward)
						appendDetail({
							Kind = "CarrySlot",
							RewardType = tostring(carriedReward.RewardType or "Unknown"),
							Status = "Carried",
							Source = tostring(carriedReward.SpawnSource or carriedReward.Source or "Carried"),
							DisplayName = tostring(carriedReward.DisplayName or slot.DisplayName or "Carried Reward"),
							Tier = tostring(carriedReward.Tier or ""),
							DepthBand = tostring(carriedReward.DepthBand or ""),
							Rarity = tostring(carriedReward.Rarity or ""),
							Variant = tostring(carriedReward.Variant or ""),
							CrewMemberId = tostring(carriedReward.CrewMemberId or ""),
							OwnerUserId = player.UserId,
							OwnerName = player.Name,
							CarryId = tostring(slot.CarryId or ""),
							SlotIndex = tonumber(slot.SlotIndex) or 0,
						})
					end
				end
			end
		end
	end

	return snapshot
end

function Service.PushState(player, options)
	pushState(player, options)
end

function Service.StartRun(player, rewardType, depthBand, options)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return startRun(player, rewardType, depthBand, options)
end

function Service.CreateChestRewardData(depthBand, options)
	local normalizedDepthBand = tostring(depthBand or Economy.VerticalSlice.DefaultDepthBand)
	return {
		RewardType = "Chest",
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = chooseChestTier(normalizedDepthBand, options),
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

function Service.CanCarryMore(player)
	return canCarryMore(player, getRuntime(player))
end

function Service.HasCarryItems(player)
	return hasCarryItems(getRuntime(player))
end

function Service.AddCarryItem(player, itemData)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return nil, errorResponse and errorResponse.error or "profile_not_ready"
	end

	return addCarryItem(player, getRuntime(player), itemData)
end

function Service.RemoveCarryItem(player, slotIndexOrCarryId)
	return removeCarryItem(player, getRuntime(player), slotIndexOrCarryId)
end

function Service.StoreHeldCrewMember(player, options)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return false, {
			Reason = errorResponse and errorResponse.error or "profile_not_ready",
		}
	end

	return storeHeldCrewMember(player, options)
end

function Service.ClearAllCarryItems(player, reason)
	clearAllCarryItems(player, getRuntime(player), reason)
	return resolveActionResponse(player, true)
end

function Service.DropCarriedReward(player, options)
	return dropCarriedReward(player, options)
end

function Service.DropAllCarriedRewards(player, options)
	return dropAllCarriedRewards(player, options)
end

function Service.ExtractRun(player)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return extractRun(player)
end

function Service._NormalizeGrantDataPath(path)
	local segments = {}
	if typeof(path) == "table" then
		for _, segment in ipairs(path) do
			local text = tostring(segment or "")
			if text ~= "" and text ~= "Data" then
				segments[#segments + 1] = text
			end
		end
	else
		local text = tostring(path or "")
		text = string.gsub(text, "^Data%.", "")
		for segment in string.gmatch(text, "[^%.]+") do
			if segment ~= "" and segment ~= "Data" then
				segments[#segments + 1] = segment
			end
		end
	end
	return segments
end

function Service._ReadGrantDataPath(dataRoot, path)
	local segments = Service._NormalizeGrantDataPath(path)
	local cursor = dataRoot
	for _, segment in ipairs(segments) do
		if typeof(cursor) ~= "table" then
			return nil
		end
		cursor = cursor[segment]
	end
	return cursor
end

function Service._WriteGrantDataPath(dataRoot, path, value)
	local segments = Service._NormalizeGrantDataPath(path)
	if #segments <= 0 or typeof(dataRoot) ~= "table" then
		return nil
	end

	local cursor = dataRoot
	for index = 1, #segments - 1 do
		local segment = segments[index]
		local nextValue = cursor[segment]
		if typeof(nextValue) ~= "table" then
			nextValue = {}
			cursor[segment] = nextValue
		end
		cursor = nextValue
	end

	cursor[segments[#segments]] = value
	return segments
end

function Service.ApplyChestStackGrantToDataRoot(dataRoot, tierName, amount, options)
	if typeof(dataRoot) ~= "table" then
		return {
			ok = false,
			error = "invalid_data_root",
		}
	end

	local normalizedTier = ChestUtils.ResolveStandardTier(tierName)
	if normalizedTier == nil or Economy.Chests.Tiers[normalizedTier] == nil then
		return {
			ok = false,
			error = "invalid_chest_tier",
		}
	end

	local count = math.max(1, math.floor(tonumber(amount) or 1))
	options = if typeof(options) == "table" then options else {}
	if options.PaidRandomItem == true or options.RequiresPaidRandomItemPolicy == true then
		return {
			ok = false,
			error = "paid_random_not_supported",
		}
	end

	local unopenedChests = ensureUnopenedChestCollection(dataRoot)
	local chestData = ChestUtils.BuildChestData({
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = normalizedTier,
		DepthBand = tostring(options.DepthBand or Economy.VerticalSlice.DefaultDepthBand),
		Source = tostring(options.Source or "Admin"),
	})
	local chestRef, storedChest, addedCount = addUnopenedChestToCollection(unopenedChests, chestData, count)
	local grantedCount = math.max(0, tonumber(addedCount) or (chestRef ~= nil and 1 or 0))
	if grantedCount <= 0 then
		return {
			ok = false,
			error = "grant_failed",
		}
	end

	return {
		ok = true,
		Tier = normalizedTier,
		Amount = grantedCount,
		ChestRef = chestRef,
		DisplayName = ChestUtils.GetDisplayName(storedChest or chestData),
		UnopenedChests = unopenedChests,
		Summary = buildChestSummary(chestRef, chestData, grantedCount),
	}
end

function Service._GrantChestInternal(player, tierName, amount, depthBand, options)
	if not waitForDataReady(player, 10) then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local profile, replica = getProfileAndReplica(player)
	if not profile or not replica then
		return resolveActionResponse(player, false, nil, "profile_not_ready")
	end

	local normalizedTier = ChestUtils.ResolveStandardTier(tierName)
	if normalizedTier == nil or Economy.Chests.Tiers[normalizedTier] == nil then
		return resolveActionResponse(player, false, nil, "invalid_chest_tier")
	end

	local count = math.max(1, math.floor(tonumber(amount) or 1))
	local normalizedDepthBand = tostring(depthBand or Economy.VerticalSlice.DefaultDepthBand)
	options = if typeof(options) == "table" then options else {}
	if options.PaidRandomItem == true
		or options.RequiresPaidRandomItemPolicy == true
		or tostring(options.Source or "") == "Purchase"
	then
		local allowed, policyState = PaidRandomItemPolicy.CanUsePaidRandomItems(player)
		if allowed ~= true then
			warn(string.format(
				"[GrandLineRush] Blocked paid random chest grant player=%s tier=%s source=%s productId=%s policyStatus=%s reason=%s",
				player and player.Name or "<unknown>",
				tostring(tierName),
				tostring(options.Source or ""),
				tostring(options.ProductId or options.PaidRandomProductId),
				tostring(policyState and policyState.Status or "unknown"),
				tostring(policyState and policyState.Reason or "policy_unknown")
			))
			return resolveActionResponse(player, false, MonetizationConfig.PaidRandomItemUnavailableMessage, "paid_random_items_restricted")
		end
	end

	local dataRoot = profile.Data
	local claimPath = if typeof(options) == "table" then (options.ClaimPath or options.OnceClaimPath) else nil
	if claimPath ~= nil and #Service._NormalizeGrantDataPath(claimPath) <= 0 then
		return resolveActionResponse(player, false, nil, "missing_claim_path")
	end
	if claimPath ~= nil and Service._ReadGrantDataPath(dataRoot, claimPath) == true then
		local response = resolveActionResponse(
			player,
			false,
			tostring(options.AlreadyClaimedMessage or "Reward already claimed."),
			"already_claimed"
		)
		response.claimed = true
		return response
	end

	local unopenedChests = ensureUnopenedChestCollection(dataRoot)
	local chestData = ChestUtils.BuildChestData({
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = normalizedTier,
		DepthBand = normalizedDepthBand,
		Source = tostring(options.Source or (if options.PaidRandomItem == true then "Purchase" else "Admin")),
		PaidRandomItem = options.PaidRandomItem == true or options.RequiresPaidRandomItemPolicy == true,
		ProductId = options.ProductId or options.PaidRandomProductId,
		PurchaseId = options.PurchaseId or options.PaidRandomPurchaseId,
	})
	local chestRef, _, addedCount = addUnopenedChestToCollection(unopenedChests, chestData, count)
	local grantedCount = math.max(0, tonumber(addedCount) or (chestRef ~= nil and 1 or 0))

	if grantedCount <= 0 then
		return resolveActionResponse(player, false, nil, "grant_failed")
	end

	local changedPaths = {
		{ Path = { "UnopenedChests" }, Value = unopenedChests },
	}
	if claimPath ~= nil then
		local claimPathSegments = Service._WriteGrantDataPath(dataRoot, claimPath, true)
		if claimPathSegments then
			changedPaths[#changedPaths + 1] = { Path = claimPathSegments, Value = true }
		end

		if options.ClaimedAtPath ~= nil then
			local claimedAtUnix = math.max(0, math.floor(tonumber(options.ClaimedAtUnix) or os.time()))
			local claimedAtPathSegments = Service._WriteGrantDataPath(dataRoot, options.ClaimedAtPath, claimedAtUnix)
			if claimedAtPathSegments then
				changedPaths[#changedPaths + 1] = { Path = claimedAtPathSegments, Value = claimedAtUnix }
			end
		end
	end

	syncPaths(player, replica, changedPaths, {
		Target = "glr_grant_chest_reward",
	})

	local message = string.format(
		"Granted %d %s%s.",
		grantedCount,
		normalizedTier,
		grantedCount == 1 and " Chest" or " Chests"
	)
	return resolveActionResponse(player, true, message)
end

function Service.GrantChest(player, tierName, amount, depthBand, options)
	return Service._GrantChestInternal(player, tierName, amount, depthBand, options)
end

function Service.GrantChestOnce(player, tierName, amount, depthBand, options)
	options = if typeof(options) == "table" then options else {}
	if options.ClaimPath == nil and options.OnceClaimPath == nil then
		return resolveActionResponse(player, false, nil, "missing_claim_path")
	end
	return Service._GrantChestInternal(player, tierName, amount, depthBand, options)
end

function Service.OpenChest(player, chestId)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return openChest(player, chestId)
end

function Service.OpenChests(player, inventoryName, amount)
	local ready, errorResponse = preparePlayerState(player)
	if not ready then
		return errorResponse
	end

	return openChests(player, inventoryName, amount)
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
