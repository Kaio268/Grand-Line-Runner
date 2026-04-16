local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))

local ChestUtils = {}

local STANDARD_TIER_SET = {}
local STANDARD_TIER_RANK = {}
for index, tierName in ipairs(ChestRewards.StandardTierOrder) do
	STANDARD_TIER_SET[tierName] = true
	STANDARD_TIER_RANK[tierName] = index
end

local FRUIT_RARITY_SET = {}
local FRUIT_RARITY_RANK = {}
for index, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
	FRUIT_RARITY_SET[rarityName] = true
	FRUIT_RARITY_RANK[rarityName] = index
end

local function normalizeSource(source)
	if typeof(source) == "string" and source ~= "" then
		return source
	end

	return ChestRewards.DefaultChestSource
end

local function normalizeRewardProfile(rewardProfile)
	if typeof(rewardProfile) == "string" and rewardProfile ~= "" then
		return rewardProfile
	end

	return ChestRewards.DefaultRewardProfile
end

function ChestUtils.NormalizeChestKind(chestKind)
	if tostring(chestKind) == ChestRewards.ChestKinds.DevilFruit then
		return ChestRewards.ChestKinds.DevilFruit
	end

	return ChestRewards.ChestKinds.Standard
end

function ChestUtils.NormalizeTier(tierName)
	local candidate = tostring(tierName or "")
	if STANDARD_TIER_SET[candidate] then
		return candidate
	end

	return ChestRewards.StandardTierOrder[1]
end

function ChestUtils.NormalizeFruitRarity(rarityName)
	local candidate = tostring(rarityName or "")
	if FRUIT_RARITY_SET[candidate] then
		return candidate
	end

	return nil
end

function ChestUtils.GetDefaultTierForDevilFruitChest(fruitRarity)
	local normalizedRarity = ChestUtils.NormalizeFruitRarity(fruitRarity)
	if normalizedRarity then
		return ChestRewards.DevilFruitChestBaseTierByRarity[normalizedRarity]
			or ChestRewards.DevilFruitChestBaseTierByRarity.Legendary
			or "Legendary"
	end

	return "Legendary"
end

function ChestUtils.BuildChestData(options)
	options = if typeof(options) == "table" then options else {}

	local chestKind = ChestUtils.NormalizeChestKind(options.ChestKind)
	local fruitRarity = ChestUtils.NormalizeFruitRarity(options.FruitRarity)
	local tierName = ChestUtils.NormalizeTier(options.Tier)

	if chestKind == ChestRewards.ChestKinds.DevilFruit then
		if options.Tier == nil or STANDARD_TIER_SET[tostring(options.Tier)] ~= true then
			tierName = ChestUtils.GetDefaultTierForDevilFruitChest(fruitRarity)
		end
	else
		fruitRarity = nil
	end

	return {
		ChestKind = chestKind,
		Tier = tierName,
		FruitRarity = fruitRarity,
		Source = normalizeSource(options.Source),
		RewardProfile = normalizeRewardProfile(options.RewardProfile),
		DepthBand = tostring(options.DepthBand or ""),
		CreatedAt = math.max(0, tonumber(options.CreatedAt) or os.time()),
	}
end

function ChestUtils.ParseInventoryName(inventoryName)
	local candidate = tostring(inventoryName or "")
	if STANDARD_TIER_SET[candidate] then
		return ChestUtils.BuildChestData({
			ChestKind = ChestRewards.ChestKinds.Standard,
			Tier = candidate,
		})
	end

	if candidate == "Devil Fruit" then
		return ChestUtils.BuildChestData({
			ChestKind = ChestRewards.ChestKinds.DevilFruit,
		})
	end

	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		if candidate == string.format("%s Devil Fruit", rarityName) then
			return ChestUtils.BuildChestData({
				ChestKind = ChestRewards.ChestKinds.DevilFruit,
				FruitRarity = rarityName,
			})
		end
	end

	return ChestUtils.BuildChestData({
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = candidate,
	})
end

function ChestUtils.GetInventoryName(chestDataOrName)
	if typeof(chestDataOrName) == "string" then
		return ChestUtils.GetInventoryName(ChestUtils.ParseInventoryName(chestDataOrName))
	end

	local chestData = ChestUtils.BuildChestData(chestDataOrName)
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit then
		if chestData.FruitRarity then
			return string.format("%s Devil Fruit", chestData.FruitRarity)
		end

		return "Devil Fruit"
	end

	return chestData.Tier
end

function ChestUtils.GetDisplayName(chestDataOrName)
	return string.format("%s Chest", ChestUtils.GetInventoryName(chestDataOrName))
end

function ChestUtils.GetRarityLabel(chestDataOrName)
	local chestData = if typeof(chestDataOrName) == "string"
		then ChestUtils.ParseInventoryName(chestDataOrName)
		else ChestUtils.BuildChestData(chestDataOrName)

	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit then
		return tostring(chestData.FruitRarity or "Devil Fruit")
	end

	return chestData.Tier
end

function ChestUtils.GetSortRank(chestDataOrName)
	local chestData = if typeof(chestDataOrName) == "string"
		then ChestUtils.ParseInventoryName(chestDataOrName)
		else ChestUtils.BuildChestData(chestDataOrName)

	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit then
		return #ChestRewards.StandardTierOrder + (FRUIT_RARITY_RANK[chestData.FruitRarity or "Common"] or 0)
	end

	return STANDARD_TIER_RANK[chestData.Tier] or 0
end

function ChestUtils.GetVisualStyleName(chestDataOrName)
	if typeof(chestDataOrName) == "string" then
		local parsed = ChestUtils.ParseInventoryName(chestDataOrName)
		if parsed.ChestKind == ChestRewards.ChestKinds.DevilFruit then
			return ChestUtils.GetInventoryName(parsed)
		end

		return parsed.Tier
	end

	local chestData = ChestUtils.BuildChestData(chestDataOrName)
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit then
		return ChestUtils.GetInventoryName(chestData)
	end

	return chestData.Tier
end

return ChestUtils
