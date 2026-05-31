local ChestRewards = {
	ChestKinds = {
		Standard = "Standard",
		DevilFruit = "DevilFruit",
	},

	StandardTierOrder = {
		"Wooden",
		"Iron",
		"Gold",
	},

	DeprecatedStandardTierAliases = {
		Legendary = "Gold",
	},

	FruitRarityOrder = {
		"Common",
		"Rare",
		"Legendary",
		"Mythic",
	},

	StandardFruitChanceByTier = {
		Wooden = {},
		Iron = {
			Common = 0.25,
			Rare = 0.04,
		},
		Gold = {
			Legendary = 0.01,
			Mythic = 0.0001,
		},
	},

	StandardFruitRollPriorityByTier = {
		Wooden = {},
		Iron = {
			"Rare",
			"Common",
		},
		Gold = {
			"Mythic",
			"Legendary",
		},
	},

	FruitPityConfig = {
		Common = {
			ChestTier = "Iron",
			HardPity = 8,
			ResetOn = {
				Common = true,
				Rare = true,
			},
		},
		Rare = {
			ChestTier = "Iron",
			HardPity = 60,
			ResetOn = {
				Rare = true,
			},
		},
		Legendary = {
			ChestTier = "Gold",
			HardPity = 250,
			ResetOn = {
				Legendary = true,
				Mythic = true,
			},
		},
		Mythic = {
			ChestTier = "Gold",
			HardPity = 1500,
			ResetOn = {
				Mythic = true,
			},
		},
	},

	FruitRarityWeights = {
		Common = 0.60,
		Rare = 0.30,
		Legendary = 0.09,
		Mythic = 0.01,
	},

	DevilFruitChestBaseTierByRarity = {
		Rare = "Gold",
		Legendary = "Gold",
		Mythic = "Gold",
	},

	DevilFruitChestGrantsBaseRewards = false,

	DuplicateConversion = {
		Common = { Type = "Beli", ScaleByTier = true },
		Rare = { Type = "Chest", FruitRarity = "Rare" },
		Legendary = { Type = "Chest", FruitRarity = "Legendary" },
		Mythic = { Type = "MythicKey", Amount = 1 },
	},

	MythicKey = {
		Threshold = 3,
		AutoConvert = true,
	},

	FallbackReward = {
		Type = "Beli",
		ScaleByTier = true,
	},

	DefaultRewardProfile = "Default",
	DefaultChestSource = "Run",
}

local function normalizeChance(rawChance)
	local chance = tonumber(rawChance) or 0
	if chance > 1 then
		chance /= 100
	end

	return math.clamp(chance, 0, 1)
end

local function cloneArray(source)
	return table.clone(source or {})
end

local function getFruitPityTable(chestRewardsState)
	if typeof(chestRewardsState) ~= "table" then
		return nil
	end
	if typeof(chestRewardsState.FruitPity) == "table" then
		return chestRewardsState.FruitPity
	end
	return chestRewardsState
end

function ChestRewards.GetStandardFruitRaritiesForTier(tierName)
	return cloneArray(ChestRewards.StandardFruitRollPriorityByTier[tostring(tierName or "")])
end

function ChestRewards.GetStandardFruitChance(tierName, rarityName)
	local tierChances = ChestRewards.StandardFruitChanceByTier[tostring(tierName or "")]
	if typeof(tierChances) ~= "table" then
		return 0
	end

	return normalizeChance(tierChances[tostring(rarityName or "")])
end

function ChestRewards.GetStandardFruitDropRates(tierName)
	local tier = tostring(tierName or "")
	local rows = {}
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local chance = ChestRewards.GetStandardFruitChance(tier, rarityName)
		if chance > 0 then
			rows[#rows + 1] = {
				Rarity = rarityName,
				Chance = chance,
			}
		end
	end
	return rows
end

function ChestRewards.GetStandardFruitTotalChance(tierName)
	local totalChance = 0
	for _, row in ipairs(ChestRewards.GetStandardFruitDropRates(tierName)) do
		totalChance += normalizeChance(row.Chance)
	end
	return math.clamp(totalChance, 0, 1)
end

function ChestRewards.IsStandardFruitRarityEligible(tierName, rarityName)
	return ChestRewards.GetStandardFruitChance(tierName, rarityName) > 0
end

function ChestRewards.GetFruitPityConfig(rarityName)
	local config = ChestRewards.FruitPityConfig[tostring(rarityName or "")]
	return if typeof(config) == "table" then config else nil
end

function ChestRewards.GetDefaultFruitPityState()
	local fruitPity = {}
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		fruitPity[rarityName] = {
			FailedOpens = 0,
		}
	end
	return fruitPity
end

function ChestRewards.EnsureFruitPityState(chestRewardsState)
	if typeof(chestRewardsState) ~= "table" then
		return ChestRewards.GetDefaultFruitPityState()
	end

	if typeof(chestRewardsState.FruitPity) ~= "table" then
		chestRewardsState.FruitPity = {}
	end

	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local entry = chestRewardsState.FruitPity[rarityName]
		if typeof(entry) ~= "table" then
			entry = {}
			chestRewardsState.FruitPity[rarityName] = entry
		end

		local config = ChestRewards.GetFruitPityConfig(rarityName)
		local hardPity = math.max(1, math.floor(tonumber(config and config.HardPity) or 1))
		entry.FailedOpens = math.clamp(math.floor(tonumber(entry.FailedOpens) or 0), 0, hardPity)
	end

	return chestRewardsState.FruitPity
end

function ChestRewards.GetFruitPityProgress(chestRewardsState, tierName)
	local fruitPity = getFruitPityTable(chestRewardsState) or {}
	local tierFilter = if tierName ~= nil then tostring(tierName) else nil
	local progress = {}

	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local config = ChestRewards.GetFruitPityConfig(rarityName)
		if config ~= nil and (tierFilter == nil or tostring(config.ChestTier) == tierFilter) then
			local entry = if typeof(fruitPity[rarityName]) == "table" then fruitPity[rarityName] else {}
			local hardPity = math.max(1, math.floor(tonumber(config.HardPity) or 1))
			progress[rarityName] = {
				FailedOpens = math.clamp(math.floor(tonumber(entry.FailedOpens) or 0), 0, hardPity),
				HardPity = hardPity,
				ChestTier = tostring(config.ChestTier or ""),
			}
		end
	end

	return progress
end

return ChestRewards
