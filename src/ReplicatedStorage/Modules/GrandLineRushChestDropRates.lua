local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ChestRewards = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local DevilFruits = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestUtils = require(Modules:WaitForChild("GrandLineRushChestUtils"))

local ChestDropRates = {}

local FOOD_DISPLAY_NAMES = {}
for foodKey, config in pairs(Economy.Food or {}) do
	FOOD_DISPLAY_NAMES[foodKey] = tostring(config.DisplayName or foodKey)
end

local MATERIAL_DISPLAY_NAMES = {
	Timber = "Timber",
	Iron = "Iron",
	AncientTimber = "Ancient Timber",
	CommonShipMaterial = "Timber",
	RareShipMaterial = "Iron",
}

local function normalizeChance(rawChance)
	local chance = tonumber(rawChance) or 0
	if chance > 1 then
		chance /= 100
	end

	return math.clamp(chance, 0, 1)
end

local function getRangeText(amountSpec)
	if typeof(amountSpec) == "number" then
		return tostring(math.max(0, math.floor(amountSpec + 0.5)))
	end
	if typeof(amountSpec) ~= "table" then
		return nil
	end

	if amountSpec.Amount ~= nil then
		return getRangeText(amountSpec.Amount)
	end
	if amountSpec.Value ~= nil then
		return getRangeText(amountSpec.Value)
	end

	local minAmount = tonumber(amountSpec.Min or amountSpec.min)
	local maxAmount = tonumber(amountSpec.Max or amountSpec.max)
	if minAmount == nil and maxAmount == nil then
		return nil
	end

	minAmount = math.max(0, math.floor((minAmount or maxAmount or 0) + 0.5))
	maxAmount = math.max(0, math.floor((maxAmount or minAmount) + 0.5))
	if maxAmount < minAmount then
		minAmount, maxAmount = maxAmount, minAmount
	end
	if minAmount == maxAmount then
		return tostring(minAmount)
	end

	return string.format("%d-%d", minAmount, maxAmount)
end

local function appendBundleRows(rows, rewardBundle, chance, sourceLabel)
	for foodKey, amountSpec in pairs((rewardBundle and rewardBundle.Food) or {}) do
		rows[#rows + 1] = {
			name = FOOD_DISPLAY_NAMES[foodKey] or tostring(foodKey),
			amountText = getRangeText(amountSpec),
			chance = chance,
			sourceLabel = sourceLabel,
		}
	end
	for materialKey, amountSpec in pairs((rewardBundle and rewardBundle.Materials) or {}) do
		rows[#rows + 1] = {
			name = MATERIAL_DISPLAY_NAMES[materialKey] or tostring(materialKey),
			amountText = getRangeText(amountSpec),
			chance = chance,
			sourceLabel = sourceLabel,
		}
	end
	local beliReward = rewardBundle and (rewardBundle.Beli or rewardBundle.Doubloons)
	if beliReward ~= nil then
		rows[#rows + 1] = {
			name = "Beli",
			amountText = getRangeText(beliReward),
			chance = chance,
			sourceLabel = sourceLabel,
		}
	end
end

local function sortByName(rows)
	table.sort(rows, function(a, b)
		return tostring(a.name) < tostring(b.name)
	end)
end

local function getFruitPools()
	local pools = {}
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		pools[rarityName] = {}
	end

	for _, fruit in ipairs(DevilFruits.GetAllFruits()) do
		local rarityName = tostring(fruit.Rarity or "Common")
		if pools[rarityName] then
			pools[rarityName][#pools[rarityName] + 1] = fruit
		end
	end

	return pools
end

local function buildGuaranteedRewardsSection(chestData)
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit
		and ChestRewards.DevilFruitChestGrantsBaseRewards ~= true
	then
		return nil
	end

	local tierConfig = (Economy.Chests.Tiers or {})[chestData.Tier]
	local rewards = tierConfig and tierConfig.Rewards
	if typeof(rewards) ~= "table" then
		return nil
	end

	local rows = {}
	appendBundleRows(rows, rewards, 1, "Guaranteed")
	sortByName(rows)
	if #rows <= 0 then
		return nil
	end

	return {
		title = "Guaranteed Rewards",
		note = "Every chest grants these rewards. Amounts show the possible range.",
		rows = rows,
	}
end

local function buildBonusRewardsSection(chestData)
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit
		and ChestRewards.DevilFruitChestGrantsBaseRewards ~= true
	then
		return nil
	end

	local tierConfig = (Economy.Chests.Tiers or {})[chestData.Tier]
	local bonusRoll = tierConfig and tierConfig.Rewards and tierConfig.Rewards.BonusRoll
	if typeof(bonusRoll) ~= "table" then
		return nil
	end

	local pool = if typeof(bonusRoll.Pool) == "table" then bonusRoll.Pool else {}
	local chance = normalizeChance(bonusRoll.Chance)
	if chance <= 0 or #pool <= 0 then
		return nil
	end

	local rows = {}
	for _, rewardBundle in ipairs(pool) do
		appendBundleRows(rows, rewardBundle, chance / #pool, "Bonus roll")
	end
	sortByName(rows)

	return {
		title = "Bonus Rewards",
		note = "One bonus reward may roll. Percentages are the final chance per chest.",
		rows = rows,
	}
end

local function buildFruitRaritySection(chestData)
	local rows = {}
	if chestData.ChestKind ~= ChestRewards.ChestKinds.DevilFruit then
		for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
			local chance = ChestRewards.GetStandardFruitChance(chestData.Tier, rarityName)
			if chance > 0 then
				rows[#rows + 1] = {
					name = rarityName,
					chance = chance,
					rarity = rarityName,
				}
			end
		end

		if #rows <= 0 then
			return nil
		end

		return {
			title = "Devil Fruit Rates",
			note = "Percentages are direct final chances for this chest tier.",
			rows = rows,
		}
	end

	if chestData.FruitRarity then
		return nil
	end

	local totalWeight = 0
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		totalWeight += math.max(0, tonumber(ChestRewards.FruitRarityWeights[rarityName]) or 0)
	end
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local rarityWeight = math.max(0, tonumber(ChestRewards.FruitRarityWeights[rarityName]) or 0)
		if rarityWeight > 0 and totalWeight > 0 then
			rows[#rows + 1] = {
				name = rarityName,
				chance = rarityWeight / totalWeight,
				rarity = rarityName,
			}
		end
	end

	return {
		title = "Devil Fruit Rates",
		note = "Devil Fruit chests are guaranteed to roll a fruit.",
		rows = rows,
	}
end

local function buildFruitPitySection(chestData, chestRewardsState)
	if chestData.ChestKind ~= ChestRewards.ChestKinds.Standard then
		return nil
	end

	local eligibleRarities = ChestRewards.GetStandardFruitRaritiesForTier(chestData.Tier)
	if #eligibleRarities <= 0 then
		return nil
	end

	local progress = ChestRewards.GetFruitPityProgress(chestRewardsState, chestData.Tier)
	local rows = {}
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local entry = progress[rarityName]
		if typeof(entry) == "table" then
			local failedOpens = math.max(0, math.floor(tonumber(entry.FailedOpens) or 0))
			local hardPity = math.max(1, math.floor(tonumber(entry.HardPity) or 1))
			rows[#rows + 1] = {
				name = string.format("%s Fruit Pity: %d/%d", rarityName, failedOpens, hardPity),
				rarity = rarityName,
			}
		end
	end

	if #rows <= 0 then
		return nil
	end

	return {
		title = "Fruit Pity",
		note = "Hard pity progress for this chest tier.",
		rows = rows,
	}
end

local function buildPossibleFruitsSection(chestData)
	local pools = getFruitPools()
	local rows = {}
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local eligible = false
		if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit then
			eligible = chestData.FruitRarity == nil or chestData.FruitRarity == rarityName
		else
			eligible = ChestRewards.IsStandardFruitRarityEligible(chestData.Tier, rarityName)
		end

		if eligible then
			for _, fruit in ipairs(pools[rarityName] or {}) do
				rows[#rows + 1] = {
					name = tostring(fruit.DisplayName or fruit.FruitKey),
					rarity = rarityName,
				}
			end
		end
	end
	if #rows <= 0 then
		return nil
	end

	return {
		title = "Possible Devil Fruits",
		note = "Fruit names show the eligible pool. Exact per-fruit odds are not fixed because unowned fruits are preferred.",
		rows = rows,
	}
end

function ChestDropRates.GetPreview(chestDataOrName, chestRewardsState)
	local chestData = if typeof(chestDataOrName) == "string"
		then ChestUtils.ParseInventoryName(chestDataOrName)
		else ChestUtils.BuildChestData(chestDataOrName)
	local sections = {}

	local guaranteedSection = buildGuaranteedRewardsSection(chestData)
	if guaranteedSection then
		sections[#sections + 1] = guaranteedSection
	end

	local bonusSection = buildBonusRewardsSection(chestData)
	if bonusSection then
		sections[#sections + 1] = bonusSection
	end

	local fruitRateSection = buildFruitRaritySection(chestData)
	if fruitRateSection then
		sections[#sections + 1] = fruitRateSection
	end

	local fruitPitySection = buildFruitPitySection(chestData, chestRewardsState)
	if fruitPitySection then
		sections[#sections + 1] = fruitPitySection
	end

	local possibleFruitsSection = buildPossibleFruitsSection(chestData)
	if possibleFruitsSection then
		sections[#sections + 1] = possibleFruitsSection
	end

	return {
		chestName = ChestUtils.GetDisplayName(chestData),
		sections = sections,
	}
end

return ChestDropRates
