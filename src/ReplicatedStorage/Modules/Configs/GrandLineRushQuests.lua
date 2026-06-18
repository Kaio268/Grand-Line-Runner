local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local DAY_SECONDS = 24 * 60 * 60
local WEEK_SECONDS = 7 * DAY_SECONDS

local Quests = {
	Version = "v1",
	Definitions = {},
	DepthRank = {
		Shallow = 1,
		Mid = 2,
		Deep = 3,
		Abyssal = 4,
	},
	LowTierFruitChestTiers = {
		Wooden = true,
		Iron = true,
	},
	Categories = {
		Daily = {
			Id = "Daily",
			Label = "Daily",
			ResetMode = "Daily",
			PeriodSeconds = DAY_SECONDS,
			ActiveCount = 5,
			Description = "Short contracts that refresh every day.",
		},
		Weekly = {
			Id = "Weekly",
			Label = "Weekly",
			ResetMode = "Weekly",
			PeriodSeconds = WEEK_SECONDS,
			ActiveCount = 4,
			Description = "Longer goals for the current week.",
		},
		Special = {
			Id = "Special",
			Label = "Special",
			ResetMode = "Lifetime",
			ActiveCount = 10,
			Description = "Milestones that stay until claimed.",
		},
	},
	CategoryOrder = {
		"Daily",
		"Weekly",
		"Special",
	},
	ActiveQuestIds = {
		Daily = {},
		Weekly = {},
		Special = {},
	},
}

local function registerQuest(questDefinition)
	if typeof(questDefinition) ~= "table" then
		return
	end

	local questId = tostring(questDefinition.Id or "")
	local categoryId = tostring(questDefinition.Category or "")
	if questId == "" or not Quests.Categories[categoryId] then
		warn(string.format("[GrandLineRushQuests] Skipping invalid quest definition %s.", questId))
		return
	end

	local storedDefinition = table.clone(questDefinition)
	storedDefinition.Id = nil
	if typeof(storedDefinition.Objective) == "table" then
		local objective = table.clone(storedDefinition.Objective)
		if tostring(objective.Type or "") == "EarnBeli" or tostring(objective.Type or "") == "EarnDoubloons" then
			objective.Target = Economy.ScaleAmount(objective.Target)
		end
		storedDefinition.Objective = objective
	end
	if typeof(storedDefinition.Rewards) == "table" then
		local rewards = {}
		for index, reward in ipairs(storedDefinition.Rewards) do
			local nextReward = if typeof(reward) == "table" then table.clone(reward) else reward
			if typeof(nextReward) == "table" then
				nextReward.Amount = Economy.ScaleRewardAmount(nextReward.Type, nextReward.Amount)
			end
			rewards[index] = nextReward
		end
		storedDefinition.Rewards = rewards
	end
	Quests.Definitions[questId] = storedDefinition
	table.insert(Quests.ActiveQuestIds[categoryId], questId)
end

local definitionsFolder = script.Parent:WaitForChild("GrandLineRushQuestDefinitions")
for _, categoryId in ipairs(Quests.CategoryOrder) do
	local categoryDefinitions = require(definitionsFolder:WaitForChild(categoryId))
	for _, questDefinition in ipairs(categoryDefinitions) do
		registerQuest(questDefinition)
	end
end

local function getFoodDisplayName(foodKey)
	local food = Economy.Food and Economy.Food[foodKey]
	return tostring((food and food.DisplayName) or foodKey)
end

local function getMaterialDisplayName(materialKey)
	if materialKey == "Timber" or materialKey == "CommonShipMaterial" then
		return "Timber"
	elseif materialKey == "Iron" or materialKey == "RareShipMaterial" then
		return "Iron"
	elseif materialKey == "AncientTimber" then
		return "Ancient Timber"
	end

	return tostring(materialKey)
end

function Quests.GetCategory(categoryId)
	return Quests.Categories[tostring(categoryId or "")]
end

function Quests.GetQuestDefinition(questId)
	return Quests.Definitions[tostring(questId or "")]
end

function Quests.GetActiveQuestIds(categoryId, _cycleId)
	local ids = Quests.ActiveQuestIds[tostring(categoryId or "")] or {}
	local category = Quests.GetCategory(categoryId)
	local activeCount = math.floor(tonumber(category and category.ActiveCount) or 0)
	if activeCount <= 0 or activeCount >= #ids then
		return ids
	end

	local seedText = string.format("%s:%s", tostring(categoryId or ""), tostring(_cycleId or ""))
	local seed = 0
	for index = 1, #seedText do
		seed = (seed * 33 + string.byte(seedText, index)) % 2147483647
	end

	local rng = Random.new(seed)
	local shuffled = table.clone(ids)
	for index = #shuffled, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		shuffled[index], shuffled[swapIndex] = shuffled[swapIndex], shuffled[index]
	end

	local activeIds = {}
	for index = 1, activeCount do
		activeIds[index] = shuffled[index]
	end

	return activeIds
end

function Quests.GetCycleId(categoryId, now)
	local category = Quests.GetCategory(categoryId)
	if not category or category.ResetMode == "Lifetime" then
		return "Lifetime"
	end

	local period = math.max(1, tonumber(category.PeriodSeconds) or DAY_SECONDS)
	local cycleNumber = math.floor((tonumber(now) or os.time()) / period)
	return string.format("%s:%d", tostring(category.Id), cycleNumber)
end

function Quests.GetResetAt(categoryId, now)
	local category = Quests.GetCategory(categoryId)
	if not category or category.ResetMode == "Lifetime" then
		return nil
	end

	local period = math.max(1, tonumber(category.PeriodSeconds) or DAY_SECONDS)
	local cycleNumber = math.floor((tonumber(now) or os.time()) / period)
	return (cycleNumber + 1) * period
end

function Quests.GetObjectiveTarget(definition)
	local objective = definition and definition.Objective
	return math.max(1, math.floor(tonumber(objective and objective.Target) or 1))
end

function Quests.GetDepthRank(depthBand)
	return Quests.DepthRank[tostring(depthBand or "")] or 0
end

function Quests.EventMatchesObjective(definition, objectiveType, context)
	local objective = definition and definition.Objective
	if typeof(objective) ~= "table" or tostring(objective.Type or "") ~= tostring(objectiveType or "") then
		return false
	end

	local eventContext = if typeof(context) == "table" then context else {}
	if objective.DepthBand and Quests.GetDepthRank(eventContext.DepthBand) < Quests.GetDepthRank(objective.DepthBand) then
		return false
	end
	if objective.Key and tostring(eventContext.Key or "") ~= tostring(objective.Key) then
		return false
	end
	if objective.FoodKey and tostring(eventContext.FoodKey or "") ~= tostring(objective.FoodKey) then
		return false
	end
	if objective.MaterialKey and tostring(eventContext.MaterialKey or "") ~= tostring(objective.MaterialKey) then
		return false
	end
	if objective.ChestKind and tostring(eventContext.ChestKind or "") ~= tostring(objective.ChestKind) then
		return false
	end
	if objective.Tier and tostring(eventContext.Tier or "") ~= tostring(objective.Tier) then
		return false
	end

	return true
end

function Quests.GetProgressDelta(definition, amount)
	local objective = definition and definition.Objective
	if objective and objective.Type == "ReachDepth" then
		return 1
	end

	return math.max(1, math.floor(tonumber(amount) or 1))
end

function Quests.FormatReward(reward)
	if typeof(reward) ~= "table" then
		return ""
	end

	local amount = math.max(1, math.floor(tonumber(reward.Amount) or 1))
	local rewardType = tostring(reward.Type or "")

	if rewardType == "Currency" then
		return string.format("%s %s", CurrencyUtil.formatCompactNumber(amount), Economy.Currency.Primary.DisplayName)
	elseif rewardType == "Food" then
		return string.format("%sx %s", CurrencyUtil.formatCompactNumber(amount), getFoodDisplayName(tostring(reward.Key or "")))
	elseif rewardType == "Material" then
		return string.format("%sx %s", CurrencyUtil.formatCompactNumber(amount), getMaterialDisplayName(tostring(reward.Key or "")))
	elseif rewardType == "Chest" then
		if reward.ChestKind == ChestRewards.ChestKinds.DevilFruit then
			return string.format("%dx %s Devil Fruit Chest", amount, tostring(reward.FruitRarity or "Common"))
		end
		return string.format("%dx %s Chest", amount, tostring(reward.Tier or "Wooden"))
	elseif rewardType == "Crew" then
		return string.format("%dx %s Crewmate", amount, tostring(reward.DisplayName or reward.CrewMemberId or "Crewmate"))
	end

	return tostring(rewardType)
end

function Quests.FormatRewards(rewards)
	local parts = {}
	for _, reward in ipairs(rewards or {}) do
		local text = Quests.FormatReward(reward)
		if text ~= "" then
			parts[#parts + 1] = text
		end
	end

	return table.concat(parts, ", ")
end

return Quests
