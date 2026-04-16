local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))

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
			Description = "Short contracts that refresh every day.",
		},
		Weekly = {
			Id = "Weekly",
			Label = "Weekly",
			ResetMode = "Weekly",
			PeriodSeconds = WEEK_SECONDS,
			Description = "Longer goals for the current week.",
		},
		Special = {
			Id = "Special",
			Label = "Special",
			ResetMode = "Lifetime",
			Description = "Milestones that stay until claimed.",
		},
	},
	CategoryOrder = {
		"Daily",
		"Weekly",
		"Special",
	},
	ActiveQuestIds = {
		Daily = {
			"daily_extract_crew",
			"daily_open_chests",
			"daily_collect_doubloons",
			"daily_reach_mid",
		},
		Weekly = {
			"weekly_extract_crew",
			"weekly_open_chests",
			"weekly_reach_deep",
			"weekly_train_crew",
		},
		Special = {
			"special_first_crew",
			"special_chest_starter",
			"special_deep_explorer",
			"special_crew_training",
		},
	},
}

local function define(questId, definition)
	Quests.Definitions[questId] = definition
end

define("daily_extract_crew", {
	Category = "Daily",
	Name = "Fresh Recruits",
	Description = "Extract 1 crew member from a corridor run.",
	Objective = { Type = "ExtractCrew", Target = 1 },
	Rewards = {
		{ Type = "Currency", Amount = 180 },
		{ Type = "Food", Key = "Apple", Amount = 3 },
	},
})

define("daily_open_chests", {
	Category = "Daily",
	Name = "Treasure Check",
	Description = "Open 2 treasure chests at base.",
	Objective = { Type = "OpenChest", Target = 2 },
	Rewards = {
		{ Type = "Food", Key = "Rice", Amount = 2 },
		{ Type = "Material", Key = "Timber", Amount = 2 },
	},
})

define("daily_collect_doubloons", {
	Category = "Daily",
	Name = "Ship Fund",
	Description = "Collect 300 Doubloons from support systems.",
	Objective = { Type = "EarnDoubloons", Target = 300 },
	Rewards = {
		{ Type = "Currency", Amount = 120 },
		{ Type = "Food", Key = "Apple", Amount = 4 },
	},
})

define("daily_reach_mid", {
	Category = "Daily",
	Name = "Hold the Route",
	Description = "Extract a reward from Mid depth or deeper.",
	Objective = { Type = "ReachDepth", Target = 1, DepthBand = "Mid" },
	Rewards = {
		{ Type = "Food", Key = "Rice", Amount = 2 },
		{ Type = "Material", Key = "Timber", Amount = 1 },
	},
})

define("weekly_extract_crew", {
	Category = "Weekly",
	Name = "Crew Drive",
	Description = "Extract 8 crew members from corridor runs.",
	Objective = { Type = "ExtractCrew", Target = 8 },
	Rewards = {
		{ Type = "Currency", Amount = 1000 },
		{ Type = "Food", Key = "Meat", Amount = 4 },
		{ Type = "Material", Key = "Iron", Amount = 2 },
	},
})

define("weekly_open_chests", {
	Category = "Weekly",
	Name = "Cargo Audit",
	Description = "Open 12 treasure chests.",
	Objective = { Type = "OpenChest", Target = 12 },
	Rewards = {
		{ Type = "Currency", Amount = 700 },
		{ Type = "Food", Key = "Rice", Amount = 6 },
		{ Type = "Material", Key = "Timber", Amount = 12 },
	},
})

define("weekly_reach_deep", {
	Category = "Weekly",
	Name = "Deep Water Run",
	Description = "Extract 3 rewards from Deep depth or deeper.",
	Objective = { Type = "ReachDepth", Target = 3, DepthBand = "Deep" },
	Rewards = {
		{ Type = "Material", Key = "Iron", Amount = 5 },
		{ Type = "Food", Key = "SeaBeastMeat", Amount = 1 },
	},
})

define("weekly_train_crew", {
	Category = "Weekly",
	Name = "Crew Drills",
	Description = "Gain 5 crew levels by feeding crew members.",
	Objective = { Type = "UpgradeCrew", Target = 5 },
	Rewards = {
		{ Type = "Currency", Amount = 800 },
		{ Type = "Food", Key = "Meat", Amount = 3 },
	},
})

define("special_first_crew", {
	Category = "Special",
	Name = "First Mate",
	Description = "Extract your first crew member.",
	Objective = { Type = "ExtractCrew", Target = 1 },
	Rewards = {
		{
			Type = "Chest",
			ChestKind = ChestRewards.ChestKinds.DevilFruit,
			Tier = "Wooden",
			FruitRarity = "Common",
			Amount = 1,
		},
	},
})

define("special_chest_starter", {
	Category = "Special",
	Name = "Locked Supply",
	Description = "Open 10 treasure chests.",
	Objective = { Type = "OpenChest", Target = 10 },
	Rewards = {
		{
			Type = "Chest",
			ChestKind = ChestRewards.ChestKinds.DevilFruit,
			Tier = "Wooden",
			FruitRarity = "Common",
			Amount = 1,
		},
	},
})

define("special_deep_explorer", {
	Category = "Special",
	Name = "Deep Route",
	Description = "Extract 5 rewards from Deep depth or deeper.",
	Objective = { Type = "ReachDepth", Target = 5, DepthBand = "Deep" },
	Rewards = {
		{
			Type = "Chest",
			ChestKind = ChestRewards.ChestKinds.DevilFruit,
			Tier = "Iron",
			FruitRarity = "Common",
			Amount = 1,
		},
	},
})

define("special_crew_training", {
	Category = "Special",
	Name = "Reliable Hands",
	Description = "Gain 15 crew levels by feeding crew members.",
	Objective = { Type = "UpgradeCrew", Target = 15 },
	Rewards = {
		{
			Type = "Chest",
			ChestKind = ChestRewards.ChestKinds.DevilFruit,
			Tier = "Iron",
			FruitRarity = "Common",
			Amount = 1,
		},
	},
})

local function formatInteger(value)
	local number = math.floor(tonumber(value) or 0)
	local sign = if number < 0 then "-" else ""
	local digits = tostring(math.abs(number))

	while true do
		local updated, count = digits:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		digits = updated
		if count == 0 then
			break
		end
	end

	return sign .. digits
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
	return Quests.ActiveQuestIds[tostring(categoryId or "")] or {}
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
		return string.format("%s %s", formatInteger(amount), Economy.Currency.Primary.DisplayName)
	elseif rewardType == "Food" then
		return string.format("%dx %s", amount, getFoodDisplayName(tostring(reward.Key or "")))
	elseif rewardType == "Material" then
		return string.format("%dx %s", amount, getMaterialDisplayName(tostring(reward.Key or "")))
	elseif rewardType == "Chest" then
		if reward.ChestKind == ChestRewards.ChestKinds.DevilFruit then
			return string.format("%dx %s Devil Fruit Chest", amount, tostring(reward.FruitRarity or "Common"))
		end
		return string.format("%dx %s Chest", amount, tostring(reward.Tier or "Wooden"))
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
