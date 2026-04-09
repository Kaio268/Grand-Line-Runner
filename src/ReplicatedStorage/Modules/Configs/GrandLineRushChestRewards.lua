local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))

local ChestRewards = {
	ChestKinds = {
		Standard = "Standard",
		DevilFruit = "DevilFruit",
	},

	StandardTierOrder = {
		"Wooden",
		"Iron",
		"Gold",
		"Legendary",
	},

	FruitRarityOrder = {
		"Common",
		"Rare",
		"Legendary",
		"Mythic",
	},

	FruitGateChanceByTier = {},

	FruitRarityWeights = {
		Common = 0.60,
		Rare = 0.30,
		Legendary = 0.09,
		Mythic = 0.01,
	},

	DevilFruitChestBaseTierByRarity = {
		Rare = "Gold",
		Legendary = "Legendary",
		Mythic = "Legendary",
	},

	DevilFruitChestGrantsBaseRewards = false,

	DuplicateConversion = {
		Common = { Type = "Doubloons", ScaleByTier = true },
		Rare = { Type = "Chest", FruitRarity = "Rare" },
		Legendary = { Type = "Chest", FruitRarity = "Legendary" },
		Mythic = { Type = "MythicKey", Amount = 1 },
	},

	MythicKey = {
		Threshold = 3,
		AutoConvert = true,
	},

	FallbackReward = {
		Type = "Doubloons",
		ScaleByTier = true,
	},

	DefaultRewardProfile = "Default",
	DefaultChestSource = "Run",
}

for tierName in pairs(Economy.Chests.Tiers or {}) do
	local rewards = (Economy.Chests.Tiers[tierName] or {}).Rewards or {}
	ChestRewards.FruitGateChanceByTier[tierName] = math.max(0, tonumber(rewards.DevilFruitChance) or 0)
end

return ChestRewards
