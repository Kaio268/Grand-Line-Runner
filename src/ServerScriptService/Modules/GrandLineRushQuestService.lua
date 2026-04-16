local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local QuestConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushQuests"))
local QuestSignals = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushQuestSignals"))

local QuestService = {}

local QUEST_REQUEST_NAME = "GrandLineRushQuestRequest"
local QUEST_STATE_NAME = "GrandLineRushQuestState"
local LOW_TIER_FRUIT_CHEST_SOURCE = "Quest"
local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local started = false
local requestRemote
local stateRemote
local claimLocks = {}
local progressLocks = {}
local cachedChestToolService

local MATERIAL_ALIASES = {
	CommonShipMaterial = "Timber",
	RareShipMaterial = "Iron",
}

local BACKFILL_APPLIED_KEY = "ProfileBackfillApplied"

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
	local remotes = getOrCreateRemotesFolder()
	requestRemote = getOrCreateRemote(remotes, "RemoteFunction", QUEST_REQUEST_NAME)
	stateRemote = getOrCreateRemote(remotes, "RemoteEvent", QUEST_STATE_NAME)
end

local function waitForDataReady(player, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 10)
	while player.Parent == Players and os.clock() <= deadline do
		if DataManager:IsReady(player) then
			return true
		end
		task.wait(0.1)
	end

	return DataManager:IsReady(player)
end

local function getProfileAndReplica(player)
	if not DataManager:IsReady(player) then
		return nil, nil
	end

	return DataManager:TryGetProfile(player), DataManager:TryGetReplica(player)
end

local function normalizeClaimedTable(claimed)
	if typeof(claimed) ~= "table" then
		return {}
	end

	for questId, value in pairs(claimed) do
		if value ~= true then
			claimed[questId] = nil
		end
	end

	return claimed
end

local function normalizeProgressTable(progress)
	if typeof(progress) ~= "table" then
		return {}
	end

	for questId, value in pairs(progress) do
		progress[questId] = math.max(0, math.floor(tonumber(value) or 0))
	end

	return progress
end

local function countMapEntries(map)
	local count = 0
	if typeof(map) ~= "table" then
		return count
	end

	for _ in pairs(map) do
		count += 1
	end

	return count
end

local function countUnopenedChests(unopenedChests)
	if typeof(unopenedChests) ~= "table" then
		return 0
	end

	if typeof(unopenedChests.Order) == "table" and #unopenedChests.Order > 0 then
		return #unopenedChests.Order
	end

	return countMapEntries(unopenedChests.ById)
end

local function getChestEntries(unopenedChests)
	local entries = {}
	if typeof(unopenedChests) ~= "table" or typeof(unopenedChests.ById) ~= "table" then
		return entries
	end

	local seen = {}
	if typeof(unopenedChests.Order) == "table" then
		for _, chestId in ipairs(unopenedChests.Order) do
			local key = tostring(chestId)
			local entry = unopenedChests.ById[key]
			if typeof(entry) == "table" then
				entries[#entries + 1] = entry
				seen[key] = true
			end
		end
	end

	for chestId, entry in pairs(unopenedChests.ById) do
		if not seen[tostring(chestId)] and typeof(entry) == "table" then
			entries[#entries + 1] = entry
		end
	end

	return entries
end

local function getCrewEntries(crewInventory)
	local entries = {}
	if typeof(crewInventory) ~= "table" or typeof(crewInventory.ById) ~= "table" then
		return entries
	end

	local seen = {}
	if typeof(crewInventory.Order) == "table" then
		for _, instanceId in ipairs(crewInventory.Order) do
			local key = tostring(instanceId)
			local entry = crewInventory.ById[key]
			if typeof(entry) == "table" then
				entries[#entries + 1] = entry
				seen[key] = true
			end
		end
	end

	for instanceId, entry in pairs(crewInventory.ById) do
		if not seen[tostring(instanceId)] and typeof(entry) == "table" then
			entries[#entries + 1] = entry
		end
	end

	return entries
end

local function countExtractedCrew(dataRoot)
	local count = 0
	for _, crewEntry in ipairs(getCrewEntries(dataRoot.CrewInventory)) do
		if tostring(crewEntry.Source or "") ~= "Starter" then
			count += 1
		end
	end

	return count
end

local function countOpenedChests(dataRoot)
	local unopenedChests = dataRoot.UnopenedChests
	if typeof(unopenedChests) ~= "table" then
		return 0
	end

	local nextChestId = math.max(1, math.floor(tonumber(unopenedChests.NextChestId) or 1))
	local createdChestCount = math.max(0, nextChestId - 1)
	return math.max(0, createdChestCount - countUnopenedChests(unopenedChests))
end

local function getTotalDoubloons(dataRoot)
	local totalStats = if typeof(dataRoot.TotalStats) == "table" then dataRoot.TotalStats else {}
	local leaderstats = if typeof(dataRoot.leaderstats) == "table" then dataRoot.leaderstats else {}
	return math.max(
		0,
		math.floor(tonumber(totalStats[Economy.Currency.Primary.TotalKey]) or tonumber(leaderstats[Economy.Currency.Primary.Key]) or 0)
	)
end

local function countExtractedRewardsAtDepth(dataRoot, minimumDepthBand)
	local minimumRank = QuestConfig.GetDepthRank(minimumDepthBand)
	local count = 0

	for _, chestEntry in ipairs(getChestEntries(dataRoot.UnopenedChests)) do
		if QuestConfig.GetDepthRank(chestEntry.DepthBand) >= minimumRank then
			count += 1
		end
	end

	for _, crewEntry in ipairs(getCrewEntries(dataRoot.CrewInventory)) do
		if tostring(crewEntry.Source or "") ~= "Starter" and QuestConfig.GetDepthRank(crewEntry.DepthBand) >= minimumRank then
			count += 1
		end
	end

	local lifetimeExtractionBounty = 0
	if typeof(dataRoot.Bounty) == "table" then
		lifetimeExtractionBounty = math.max(0, tonumber(dataRoot.Bounty.LifetimeExtraction) or 0)
	end
	if count == 0 and minimumRank <= QuestConfig.GetDepthRank("Mid") and lifetimeExtractionBounty > 0 then
		count = 1
	end

	return count
end

local function countCrewLevelsGained(dataRoot)
	local count = 0
	for _, crewEntry in ipairs(getCrewEntries(dataRoot.CrewInventory)) do
		if tostring(crewEntry.Source or "") ~= "Starter" then
			count += math.max(0, math.floor(tonumber(crewEntry.Level) or 1) - 1)
		end
	end

	return count
end

local function getProfileBackfillProgress(dataRoot, definition)
	local objective = definition and definition.Objective
	if typeof(objective) ~= "table" then
		return 0
	end

	local objectiveType = tostring(objective.Type or "")
	if objectiveType == "ExtractCrew" then
		return countExtractedCrew(dataRoot)
	elseif objectiveType == "OpenChest" then
		return countOpenedChests(dataRoot)
	elseif objectiveType == "EarnDoubloons" then
		return getTotalDoubloons(dataRoot)
	elseif objectiveType == "ReachDepth" then
		return countExtractedRewardsAtDepth(dataRoot, objective.DepthBand)
	elseif objectiveType == "UpgradeCrew" then
		return countCrewLevelsGained(dataRoot)
	end

	return 0
end

local function applyProfileBackfill(dataRoot, categoryId, categoryState)
	local changed = false
	categoryState.Progress = if typeof(categoryState.Progress) == "table" then categoryState.Progress else {}

	for _, questId in ipairs(QuestConfig.GetActiveQuestIds(categoryId, categoryState.CycleId)) do
		local definition = QuestConfig.GetQuestDefinition(questId)
		if definition then
			local target = QuestConfig.GetObjectiveTarget(definition)
			local current = math.max(0, math.floor(tonumber(categoryState.Progress[questId]) or 0))
			local backfill = math.clamp(getProfileBackfillProgress(dataRoot, definition), 0, target)
			if backfill > current then
				categoryState.Progress[questId] = backfill
				changed = true
			end
		end
	end

	categoryState[BACKFILL_APPLIED_KEY] = true
	return changed
end

local function normalizeQuestState(dataRoot, now)
	local changed = false
	if typeof(dataRoot.Quests) ~= "table" then
		dataRoot.Quests = {}
		changed = true
	end

	for _, categoryId in ipairs(QuestConfig.CategoryOrder) do
		local categoryConfig = QuestConfig.GetCategory(categoryId)
		local categoryState = dataRoot.Quests[categoryId]
		if typeof(categoryState) ~= "table" then
			categoryState = {}
			dataRoot.Quests[categoryId] = categoryState
			changed = true
		end

		local expectedCycleId = QuestConfig.GetCycleId(categoryId, now)
		if categoryConfig and categoryConfig.ResetMode ~= "Lifetime" then
			local previousCycleId = tostring(categoryState.CycleId or "")
			if tostring(categoryState.CycleId or "") ~= expectedCycleId then
				categoryState.CycleId = expectedCycleId
				categoryState.Progress = {}
				categoryState.Claimed = {}
				categoryState[BACKFILL_APPLIED_KEY] = previousCycleId ~= ""
				changed = true
			end
		elseif tostring(categoryState.CycleId or "") ~= "Lifetime" then
			categoryState.CycleId = "Lifetime"
			categoryState[BACKFILL_APPLIED_KEY] = false
			changed = true
		end

		local normalizedProgress = normalizeProgressTable(categoryState.Progress)
		if normalizedProgress ~= categoryState.Progress then
			categoryState.Progress = normalizedProgress
			changed = true
		end

		local normalizedClaimed = normalizeClaimedTable(categoryState.Claimed)
		if normalizedClaimed ~= categoryState.Claimed then
			categoryState.Claimed = normalizedClaimed
			changed = true
		end

		if categoryState[BACKFILL_APPLIED_KEY] ~= true then
			if applyProfileBackfill(dataRoot, categoryId, categoryState) then
				changed = true
			end
			changed = true
		end
	end

	return dataRoot.Quests, changed
end

local function ensureQuestState(player)
	local profile, replica = getProfileAndReplica(player)
	if not (profile and replica) then
		return nil, nil, nil
	end

	local quests, changed = normalizeQuestState(profile.Data, os.time())
	if changed then
		replica:Set({ "Quests" }, quests)
		DataManager:UpdateData(player)
	end

	return quests, profile, replica
end

local function formatTimeRemaining(seconds)
	local totalSeconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local days = math.floor(totalSeconds / 86400)
	local hours = math.floor((totalSeconds % 86400) / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	end

	return string.format("%dm", math.max(1, minutes))
end

local function buildClientQuest(definition, questId, categoryState)
	local target = QuestConfig.GetObjectiveTarget(definition)
	local progress = math.clamp(math.floor(tonumber(categoryState.Progress[questId]) or 0), 0, target)
	local claimed = categoryState.Claimed[questId] == true
	local completed = progress >= target

	return {
		id = questId,
		category = definition.Category,
		name = definition.Name,
		description = definition.Description,
		progress = progress,
		target = target,
		completed = completed,
		claimed = claimed,
		claimable = completed and not claimed,
		rewardText = QuestConfig.FormatRewards(definition.Rewards),
		rewards = definition.Rewards or {},
		objectiveType = definition.Objective and definition.Objective.Type or "",
	}
end

local function buildClientState(player)
	local quests = ensureQuestState(player)
	if not quests then
		return nil
	end

	local now = os.time()
	local state = {
		version = QuestConfig.Version,
		serverTime = now,
		categoryOrder = QuestConfig.CategoryOrder,
		categories = {},
		claimableCount = 0,
	}

	for _, categoryId in ipairs(QuestConfig.CategoryOrder) do
		local categoryConfig = QuestConfig.GetCategory(categoryId)
		local categoryState = quests[categoryId] or {}
		local categoryView = {
			id = categoryId,
			label = categoryConfig and categoryConfig.Label or categoryId,
			description = categoryConfig and categoryConfig.Description or "",
			resetMode = categoryConfig and categoryConfig.ResetMode or "Lifetime",
			cycleId = categoryState.CycleId or "",
			quests = {},
			completedCount = 0,
			claimableCount = 0,
			totalCount = 0,
			resetAt = QuestConfig.GetResetAt(categoryId, now),
			resetText = "",
		}

		categoryView.resetText = if categoryView.resetAt
			then "Refreshes in " .. formatTimeRemaining(categoryView.resetAt - now)
			else "No reset"

		for _, questId in ipairs(QuestConfig.GetActiveQuestIds(categoryId, categoryState.CycleId)) do
			local definition = QuestConfig.GetQuestDefinition(questId)
			if definition then
				local questView = buildClientQuest(definition, questId, categoryState)
				categoryView.quests[#categoryView.quests + 1] = questView
				categoryView.totalCount += 1
				if questView.completed then
					categoryView.completedCount += 1
				end
				if questView.claimable then
					categoryView.claimableCount += 1
					state.claimableCount += 1
				end
			end
		end

		state.categories[#state.categories + 1] = categoryView
	end

	return state
end

local function pushState(player)
	if stateRemote and player.Parent == Players then
		local state = buildClientState(player)
		if state then
			stateRemote:FireClient(player, state)
		end
	end
end

local function sendPopup(player, text, isError)
	if player.Parent ~= Players then
		return
	end

	PopUpModule:Server_SendPopUp(
		player,
		text,
		if isError then ERROR_COLOR else SUCCESS_COLOR,
		STROKE_COLOR,
		3,
		isError == true
	)
end

local function addChangedPath(changedPaths, path, value)
	changedPaths[#changedPaths + 1] = {
		Path = path,
		Value = value,
	}
end

local function canonicalMaterialKey(materialKey)
	return MATERIAL_ALIASES[tostring(materialKey or "")] or tostring(materialKey or "")
end

local function ensureMaterialsTable(dataRoot)
	if typeof(dataRoot.Materials) ~= "table" then
		dataRoot.Materials = {}
	end

	local materials = dataRoot.Materials
	materials.Timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0)
	materials.Iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0)
	materials.AncientTimber = math.max(0, tonumber(materials.AncientTimber) or 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron
	materials.Inventory = if typeof(materials.Inventory) == "table" then materials.Inventory else {}

	return materials
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

	return chestId
end

local function validateQuestReward(reward)
	if typeof(reward) ~= "table" then
		return false, "invalid_reward"
	end

	local rewardType = tostring(reward.Type or "")
	if rewardType == "Currency" or rewardType == "Food" or rewardType == "Material" then
		return true
	end
	if rewardType ~= "Chest" then
		return false, "unsupported_reward"
	end

	local normalizedChest = ChestUtils.BuildChestData(reward)
	if normalizedChest.ChestKind ~= ChestRewards.ChestKinds.DevilFruit then
		return false, "unsupported_chest_reward"
	elseif normalizedChest.FruitRarity ~= "Common" then
		return false, "unsupported_fruit_rarity"
	elseif QuestConfig.LowTierFruitChestTiers[normalizedChest.Tier] ~= true then
		return false, "unsupported_chest_tier"
	end

	return true
end

local function validateQuestRewards(rewards)
	for _, reward in ipairs(rewards or {}) do
		local ok, reason = validateQuestReward(reward)
		if not ok then
			return false, reason
		end
	end

	return true
end

local function addRewardPopup(rewardPopup, reward)
	local text = QuestConfig.FormatReward(reward)
	if text ~= "" then
		rewardPopup[#rewardPopup + 1] = { text, "" }
	end
end

local function grantQuestRewardToData(dataRoot, reward, changedRoots, rewardPopup)
	local rewardType = tostring(reward.Type or "")
	local amount = math.max(1, math.floor(tonumber(reward.Amount) or 1))

	if rewardType == "Currency" then
		dataRoot.leaderstats = if typeof(dataRoot.leaderstats) == "table" then dataRoot.leaderstats else {}
		dataRoot.TotalStats = if typeof(dataRoot.TotalStats) == "table" then dataRoot.TotalStats else {}

		local primary = Economy.Currency.Primary
		dataRoot.leaderstats[primary.Key] = math.max(0, tonumber(dataRoot.leaderstats[primary.Key]) or 0) + amount
		dataRoot.TotalStats[primary.TotalKey] = math.max(0, tonumber(dataRoot.TotalStats[primary.TotalKey]) or 0) + amount
		changedRoots.Leaderstats = true
		changedRoots.TotalStats = true
	elseif rewardType == "Food" then
		dataRoot.FoodInventory = if typeof(dataRoot.FoodInventory) == "table" then dataRoot.FoodInventory else {}
		local foodKey = tostring(reward.Key or "")
		dataRoot.FoodInventory[foodKey] = math.max(0, tonumber(dataRoot.FoodInventory[foodKey]) or 0) + amount
		changedRoots.FoodInventory = true
	elseif rewardType == "Material" then
		local materials = ensureMaterialsTable(dataRoot)
		local materialKey = canonicalMaterialKey(reward.Key)
		materials[materialKey] = math.max(0, tonumber(materials[materialKey]) or 0) + amount
		materials.CommonShipMaterial = math.max(0, tonumber(materials.Timber) or 0)
		materials.RareShipMaterial = math.max(0, tonumber(materials.Iron) or 0)
		changedRoots.Materials = true
	elseif rewardType == "Chest" then
		dataRoot.UnopenedChests = if typeof(dataRoot.UnopenedChests) == "table" then dataRoot.UnopenedChests else {}
		local normalizedChest = ChestUtils.BuildChestData({
			ChestKind = ChestRewards.ChestKinds.DevilFruit,
			Tier = reward.Tier,
			FruitRarity = "Common",
			DepthBand = "Quest",
			Source = LOW_TIER_FRUIT_CHEST_SOURCE,
			RewardProfile = ChestRewards.DefaultRewardProfile,
		})

		for _ = 1, amount do
			addUnopenedChestToCollection(dataRoot.UnopenedChests, normalizedChest)
		end
		changedRoots.UnopenedChests = true
	end

	addRewardPopup(rewardPopup, reward)
end

local function syncChestTools(player)
	if not cachedChestToolService then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushChestToolService"))
		end)
		if ok then
			cachedChestToolService = result
		end
	end

	if cachedChestToolService and cachedChestToolService.SyncPlayer then
		pcall(function()
			cachedChestToolService.SyncPlayer(player)
		end)
	end
end

local function syncClaimMutation(player, replica, dataRoot, changedRoots)
	local changedPaths = {}
	addChangedPath(changedPaths, { "Quests" }, dataRoot.Quests)

	if changedRoots.Leaderstats then
		addChangedPath(changedPaths, { "leaderstats", Economy.Currency.Primary.Key }, dataRoot.leaderstats[Economy.Currency.Primary.Key])
	end
	if changedRoots.TotalStats then
		addChangedPath(changedPaths, { "TotalStats", Economy.Currency.Primary.TotalKey }, dataRoot.TotalStats[Economy.Currency.Primary.TotalKey])
	end
	if changedRoots.FoodInventory then
		addChangedPath(changedPaths, { "FoodInventory" }, dataRoot.FoodInventory)
	end
	if changedRoots.Materials then
		addChangedPath(changedPaths, { "Materials" }, dataRoot.Materials)
	end
	if changedRoots.UnopenedChests then
		addChangedPath(changedPaths, { "UnopenedChests" }, dataRoot.UnopenedChests)
	end

	for _, entry in ipairs(changedPaths) do
		replica:Set(entry.Path, entry.Value)
	end

	DataManager:UpdateData(player)

	if changedRoots.UnopenedChests then
		syncChestTools(player)
	end
end

local function makeResponse(player, ok, message, errorCode)
	return {
		ok = ok == true,
		message = message,
		error = errorCode,
		state = buildClientState(player),
	}
end

local function claimQuestInternal(player, payload)
	local categoryId = tostring(payload and (payload.Category or payload.category) or "")
	local questId = tostring(payload and (payload.QuestId or payload.questId) or "")
	if categoryId == "" or questId == "" then
		return makeResponse(player, false, "Quest not found.", "invalid_request")
	end

	local quests, profile, replica = ensureQuestState(player)
	if not (quests and profile and replica) then
		return makeResponse(player, false, "Quest data is still loading.", "profile_not_ready")
	end

	local categoryState = quests[categoryId]
	local definition = QuestConfig.GetQuestDefinition(questId)
	if typeof(categoryState) ~= "table" or not definition or definition.Category ~= categoryId then
		return makeResponse(player, false, "Quest not found.", "missing_quest")
	end

	local isActiveQuest = false
	for _, activeQuestId in ipairs(QuestConfig.GetActiveQuestIds(categoryId, categoryState.CycleId)) do
		if activeQuestId == questId then
			isActiveQuest = true
			break
		end
	end
	if not isActiveQuest then
		return makeResponse(player, false, "That quest is not active right now.", "inactive_quest")
	end

	if categoryState.Claimed[questId] == true then
		return makeResponse(player, false, "That quest reward is already claimed.", "already_claimed")
	end

	local target = QuestConfig.GetObjectiveTarget(definition)
	local progress = math.max(0, tonumber(categoryState.Progress[questId]) or 0)
	if progress < target then
		return makeResponse(player, false, "Finish the quest before claiming.", "not_complete")
	end

	local rewardsOk, rewardReason = validateQuestRewards(definition.Rewards)
	if not rewardsOk then
		warn(string.format("[GrandLineRushQuestService] Invalid reward for quest %s: %s", questId, tostring(rewardReason)))
		return makeResponse(player, false, "That reward is not available right now.", rewardReason)
	end

	local dataRoot = profile.Data
	local changedRoots = {}
	local rewardPopup = {}
	categoryState.Claimed[questId] = true

	for _, reward in ipairs(definition.Rewards or {}) do
		grantQuestRewardToData(dataRoot, reward, changedRoots, rewardPopup)
	end

	syncClaimMutation(player, replica, dataRoot, changedRoots)
	sendPopup(player, "Quest reward claimed!", false)
	if #rewardPopup > 0 then
		PopUpModule:Server_ShowReward(player, rewardPopup)
	end
	pushState(player)

	return makeResponse(player, true, "Quest reward claimed.", nil)
end

local function claimQuest(player, payload)
	if claimLocks[player] == true then
		return makeResponse(player, false, "Quest claim is already processing.", "busy")
	end

	claimLocks[player] = true
	local ok, response = pcall(claimQuestInternal, player, payload)
	claimLocks[player] = nil

	if ok then
		return response
	end

	warn(string.format("[GrandLineRushQuestService] Claim failed for %s: %s", player.Name, tostring(response)))
	return makeResponse(player, false, "Couldn't claim that quest right now.", "claim_failed")
end

local function recordObjective(player, eventData)
	if progressLocks[player] == true then
		task.defer(recordObjective, player, eventData)
		return
	end

	progressLocks[player] = true
	local ok, err = pcall(function()
		local quests, _profile, replica = ensureQuestState(player)
		if not (quests and replica) then
			return
		end

		local objectiveType = tostring(eventData and eventData.Type or "")
		if objectiveType == "" then
			return
		end

		local amount = math.max(1, math.floor(tonumber(eventData and eventData.Amount) or 1))
		local context = if typeof(eventData and eventData.Context) == "table" then eventData.Context else {}
		local changed = false

		for _, categoryId in ipairs(QuestConfig.CategoryOrder) do
			local categoryState = quests[categoryId]
			if typeof(categoryState) ~= "table" then
				continue
			end

			for _, questId in ipairs(QuestConfig.GetActiveQuestIds(categoryId, categoryState.CycleId)) do
				if categoryState.Claimed[questId] == true then
					continue
				end

				local definition = QuestConfig.GetQuestDefinition(questId)
				if not QuestConfig.EventMatchesObjective(definition, objectiveType, context) then
					continue
				end

				local target = QuestConfig.GetObjectiveTarget(definition)
				local current = math.max(0, tonumber(categoryState.Progress[questId]) or 0)
				if current >= target then
					continue
				end

				local delta = QuestConfig.GetProgressDelta(definition, amount)
				categoryState.Progress[questId] = math.min(target, current + delta)
				changed = true
			end
		end

		if changed then
			replica:Set({ "Quests" }, quests)
			DataManager:UpdateData(player)
			pushState(player)
		end
	end)
	progressLocks[player] = nil

	if not ok then
		warn(string.format("[GrandLineRushQuestService] Progress update failed for %s: %s", player.Name, tostring(err)))
	end
end

local function handleRequest(player, actionName, payload)
	if actionName == "GetState" then
		return makeResponse(player, true, nil, nil)
	elseif actionName == "ClaimQuest" then
		return claimQuest(player, payload)
	end

	return makeResponse(player, false, "Unknown quest action.", "unknown_action")
end

local function preparePlayer(player)
	task.spawn(function()
		if not waitForDataReady(player, 12) then
			return
		end
		ensureQuestState(player)
		pushState(player)
	end)
end

function QuestService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()
	requestRemote.OnServerInvoke = function(player, actionName, payload)
		return handleRequest(player, actionName, payload)
	end

	QuestSignals.ObjectiveRecorded:Connect(function(player, eventData)
		if player and player.Parent == Players then
			recordObjective(player, eventData)
		end
	end)

	Players.PlayerAdded:Connect(preparePlayer)
	Players.PlayerRemoving:Connect(function(player)
		claimLocks[player] = nil
		progressLocks[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		preparePlayer(player)
	end
end

return QuestService
