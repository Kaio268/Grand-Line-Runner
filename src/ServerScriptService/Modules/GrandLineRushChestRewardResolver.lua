local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local DevilFruitInventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitInventoryService"))

local ChestRewardResolver = {}
local PLAYER_LUCK_MULTIPLIER = 1.25

local function chooseWeightedKey(randomObject, weightTable, orderedKeys)
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

local function normalizeMaterialKey(materialKey)
	local key = tostring(materialKey or "")
	if key == "CommonShipMaterial" then
		return "Timber"
	elseif key == "RareShipMaterial" then
		return "Iron"
	end

	return key
end

local function clampRewardAmount(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function getStaticRewardAmount(amountSpec)
	if typeof(amountSpec) == "number" then
		return clampRewardAmount(amountSpec)
	end

	if typeof(amountSpec) ~= "table" then
		return 0
	end

	if amountSpec.Amount ~= nil then
		return getStaticRewardAmount(amountSpec.Amount)
	end
	if amountSpec.Value ~= nil then
		return getStaticRewardAmount(amountSpec.Value)
	end

	local minAmount = tonumber(amountSpec.Min or amountSpec.min)
	local maxAmount = tonumber(amountSpec.Max or amountSpec.max)
	if minAmount ~= nil and maxAmount ~= nil then
		return clampRewardAmount(math.min(minAmount, maxAmount))
	end
	if minAmount ~= nil then
		return clampRewardAmount(minAmount)
	end
	if maxAmount ~= nil then
		return clampRewardAmount(maxAmount)
	end

	return 0
end

local function rollRewardAmount(randomObject, amountSpec)
	if typeof(amountSpec) == "number" then
		return clampRewardAmount(amountSpec)
	end

	if typeof(amountSpec) ~= "table" then
		return 0
	end

	if amountSpec.Amount ~= nil then
		return rollRewardAmount(randomObject, amountSpec.Amount)
	end
	if amountSpec.Value ~= nil then
		return rollRewardAmount(randomObject, amountSpec.Value)
	end

	local minAmount = tonumber(amountSpec.Min or amountSpec.min)
	local maxAmount = tonumber(amountSpec.Max or amountSpec.max)
	if minAmount == nil and maxAmount == nil then
		return 0
	end

	minAmount = clampRewardAmount(minAmount or maxAmount)
	maxAmount = clampRewardAmount(maxAmount or minAmount)
	if maxAmount < minAmount then
		minAmount, maxAmount = maxAmount, minAmount
	end

	if maxAmount == minAmount then
		return minAmount
	end

	return randomObject:NextInteger(minAmount, maxAmount)
end

local function getTierRewards(tierName)
	local tierConfig = (Economy.Chests.Tiers or {})[tostring(tierName or "")]
	return (tierConfig and tierConfig.Rewards) or {}
end

local function getBeliRewardSpec(rewardBundle)
	if typeof(rewardBundle) ~= "table" then
		return nil
	end

	return rewardBundle.Beli or rewardBundle.Doubloons
end

local function getFruitConversionBeliSpec(rewards)
	if typeof(rewards) ~= "table" then
		return nil
	end

	return rewards.FruitConversionBeli or rewards.FruitConversionDoubloons or getBeliRewardSpec(rewards)
end

local function getScaledBeliReward(tierName)
	local rewards = getTierRewards(tierName)
	return getStaticRewardAmount(getFruitConversionBeliSpec(rewards))
end

local function shouldGrantBaseRewards(chestData)
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit then
		return ChestRewards.DevilFruitChestGrantsBaseRewards == true
	end

	return true
end

local function ensureFoodInventory(dataRoot)
	if typeof(dataRoot.FoodInventory) ~= "table" then
		dataRoot.FoodInventory = {}
	end

	return dataRoot.FoodInventory
end

local function ensureMaterials(dataRoot)
	if typeof(dataRoot.Materials) ~= "table" then
		dataRoot.Materials = {}
	end

	local materials = dataRoot.Materials
	materials.Timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0)
	materials.Iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0)
	materials.AncientTimber = math.max(0, tonumber(materials.AncientTimber) or 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron

	return materials
end

local function ensureLeaderstats(dataRoot)
	if typeof(dataRoot.leaderstats) ~= "table" then
		dataRoot.leaderstats = {}
	end

	return dataRoot.leaderstats
end

local function ensureTotalStats(dataRoot)
	if typeof(dataRoot.TotalStats) ~= "table" then
		dataRoot.TotalStats = {}
	end

	return dataRoot.TotalStats
end

local function ensureDevilFruitInventory(dataRoot)
	if typeof(dataRoot.Inventory) ~= "table" then
		dataRoot.Inventory = {}
	end

	local inventory = dataRoot.Inventory
	if typeof(inventory.DevilFruits) ~= "table" then
		inventory.DevilFruits = {}
	end

	return inventory.DevilFruits
end

local function ensureIndexCollection(dataRoot)
	if typeof(dataRoot.IndexCollection) ~= "table" then
		dataRoot.IndexCollection = {}
	end

	local indexCollection = dataRoot.IndexCollection
	if typeof(indexCollection.DevilFruits) ~= "table" then
		indexCollection.DevilFruits = {}
	end

	return indexCollection.DevilFruits
end

local function ensureChestRewardsState(dataRoot)
	if typeof(dataRoot.ChestRewards) ~= "table" then
		dataRoot.ChestRewards = {}
	end

	dataRoot.ChestRewards.MythicKeys = math.max(0, tonumber(dataRoot.ChestRewards.MythicKeys) or 0)
	return dataRoot.ChestRewards
end

local function buildOpenResult(dataRoot, openedChest)
	return {
		OpenedChest = openedChest,
		GrantedResources = {
			food = {},
			materials = {},
			beli = 0,
			-- Legacy payload alias kept during the currency transition.
			doubloons = 0,
		},
		GrantedFruit = nil,
		GrantedFruitRarity = nil,
		WasDuplicate = false,
		ConversionRewardType = nil,
		ConversionRewardRarity = nil,
		ConversionRewardAmount = nil,
		ConversionRewardDisplayName = nil,
		MythicKeyProgress = {
			current = ensureChestRewardsState(dataRoot).MythicKeys,
			threshold = ChestRewards.MythicKey.Threshold,
		},
		AutoConvertedMythicChest = false,
		GrantedChest = nil,
		Message = nil,
	}
end

local function grantFruit(dataRoot, fruitKey)
	local devilFruits = ensureDevilFruitInventory(dataRoot)
	local entry = devilFruits[fruitKey]
	if typeof(entry) ~= "table" then
		entry = { Quantity = 0 }
		devilFruits[fruitKey] = entry
	end

	entry.Quantity = math.max(0, tonumber(entry.Quantity) or 0) + 1
	ensureIndexCollection(dataRoot)[fruitKey] = true
end

local function addBeli(dataRoot, amount)
	local increment = math.max(0, tonumber(amount) or 0)
	if increment <= 0 then
		return 0
	end

	local leaderstats = ensureLeaderstats(dataRoot)
	local totalStats = ensureTotalStats(dataRoot)
	local primary = CurrencyUtil.getConfig()

	leaderstats[primary.Key] = math.max(0, tonumber(leaderstats[primary.Key]) or 0) + increment
	totalStats[primary.TotalKey] = math.max(0, tonumber(totalStats[primary.TotalKey]) or 0) + increment
	local legacy = if typeof(dataRoot.CurrencyLegacy) == "table" then dataRoot.CurrencyLegacy else {}
	dataRoot.CurrencyLegacy = legacy
	legacy.CurrentBeli = leaderstats[primary.Key]
	legacy.Doubloons = leaderstats[primary.Key]
	legacy.Money = leaderstats[primary.Key]
	legacy.Moeny = leaderstats[primary.Key]
	legacy.CurrentTotalBeli = totalStats[primary.TotalKey]
	legacy.TotalDoubloons = totalStats[primary.TotalKey]
	legacy.TotalMoney = totalStats[primary.TotalKey]

	return increment
end

local function addGrantedAmount(target, key, amount)
	local increment = clampRewardAmount(amount)
	if increment <= 0 then
		return 0
	end

	target[key] = math.max(0, tonumber(target[key]) or 0) + increment
	return increment
end

local function grantFoodRewards(randomObject, foodInventory, grantedFood, foodRewards)
	for foodKey, amountSpec in pairs(foodRewards or {}) do
		local increment = rollRewardAmount(randomObject, amountSpec)
		if increment > 0 then
			foodInventory[foodKey] = math.max(0, tonumber(foodInventory[foodKey]) or 0) + increment
			addGrantedAmount(grantedFood, foodKey, increment)
		end
	end
end

local function grantMaterialRewards(randomObject, materials, grantedMaterials, materialRewards)
	for materialKey, amountSpec in pairs(materialRewards or {}) do
		local normalizedMaterialKey = normalizeMaterialKey(materialKey)
		local increment = rollRewardAmount(randomObject, amountSpec)
		if increment > 0 then
			materials[normalizedMaterialKey] = math.max(0, tonumber(materials[normalizedMaterialKey]) or 0) + increment
			addGrantedAmount(grantedMaterials, normalizedMaterialKey, increment)
		end
	end
end

local function grantRewardBundle(randomObject, dataRoot, grantedResources, rewardBundle)
	rewardBundle = if typeof(rewardBundle) == "table" then rewardBundle else {}

	local foodInventory = ensureFoodInventory(dataRoot)
	local materials = ensureMaterials(dataRoot)

	grantFoodRewards(randomObject, foodInventory, grantedResources.food, rewardBundle.Food)
	grantMaterialRewards(randomObject, materials, grantedResources.materials, rewardBundle.Materials)

	materials.Timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0)
	materials.Iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron

	local beliReward = addBeli(dataRoot, rollRewardAmount(randomObject, getBeliRewardSpec(rewardBundle)))
	grantedResources.beli += beliReward
	grantedResources.doubloons = grantedResources.beli
end

local function normalizeChance(rawChance)
	local chance = tonumber(rawChance) or 0
	if chance > 1 then
		chance /= 100
	end

	return math.clamp(chance, 0, 1)
end

local function grantBonusRewards(randomObject, dataRoot, grantedResources, bonusRollConfig)
	if typeof(bonusRollConfig) ~= "table" then
		return
	end

	local chance = normalizeChance(bonusRollConfig.Chance)
	local pool = if typeof(bonusRollConfig.Pool) == "table" then bonusRollConfig.Pool else {}
	if chance <= 0 or #pool <= 0 then
		return
	end

	local rolls = math.max(1, math.floor(tonumber(bonusRollConfig.Rolls) or 1))
	for _ = 1, rolls do
		if randomObject:NextNumber() <= chance then
			local selectedReward = pool[randomObject:NextInteger(1, #pool)]
			grantRewardBundle(randomObject, dataRoot, grantedResources, selectedReward)
		end
	end
end

local function grantBaseRewards(randomObject, dataRoot, chestData, changedRoots)
	local rewards = getTierRewards(chestData.Tier)
	local grantedResources = {
		food = {},
		materials = {},
		beli = 0,
		doubloons = 0,
	}

	grantRewardBundle(randomObject, dataRoot, grantedResources, rewards)
	grantBonusRewards(randomObject, dataRoot, grantedResources, rewards.BonusRoll)

	changedRoots.FoodInventory = true
	changedRoots.Materials = true
	changedRoots.Leaderstats = true
	changedRoots.TotalStats = true

	return grantedResources
end

local function getFruitPoolsByRarity()
	local pools = {}
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		pools[rarityName] = {}
	end

	for _, fruit in ipairs(DevilFruitConfig.GetAllFruits()) do
		local rarityName = tostring(fruit.Rarity or "Common")
		if pools[rarityName] then
			pools[rarityName][#pools[rarityName] + 1] = fruit
		end
	end

	return pools
end

local function resolveEffectiveRarity(requestedRarity, pools)
	local requestedIndex = nil
	for index, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		if rarityName == requestedRarity then
			requestedIndex = index
			break
		end
	end

	if requestedIndex == nil then
		return nil
	end

	for index = requestedIndex, 1, -1 do
		local rarityName = ChestRewards.FruitRarityOrder[index]
		local pool = pools[rarityName]
		if pool and #pool > 0 then
			return rarityName, pool
		end
	end

	return nil, nil
end

local function buildUnownedFruitPool(player, pool)
	local unownedPool = {}

	for _, fruit in ipairs(pool or {}) do
		if not DevilFruitInventoryService.IsOwned(player, fruit.FruitKey) then
			unownedPool[#unownedPool + 1] = fruit
		end
	end

	return unownedPool
end

local function getPlayerLuckMultiplier(player)
	local potions = player and player:FindFirstChild("Potions")
	local luckTime = potions and potions:FindFirstChild("xLuckTime")
	if luckTime and luckTime:IsA("NumberValue") and luckTime.Value > 0 then
		return PLAYER_LUCK_MULTIPLIER
	end
	return 1
end

local function buildLuckAdjustedFruitWeights(player)
	local multiplier = getPlayerLuckMultiplier(player)
	if multiplier <= 1 then
		return ChestRewards.FruitRarityWeights
	end

	local adjusted = {}
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local weight = math.max(0, tonumber(ChestRewards.FruitRarityWeights[rarityName]) or 0)
		if rarityName ~= "Common" then
			weight *= multiplier
		end
		adjusted[rarityName] = weight
	end
	return adjusted
end

local function chooseRequestedRarity(randomObject, chestData, player)
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit and chestData.FruitRarity ~= nil then
		return chestData.FruitRarity
	end

	return chooseWeightedKey(randomObject, buildLuckAdjustedFruitWeights(player), ChestRewards.FruitRarityOrder)
end

local function applyFallbackBeli(dataRoot, chestData, openResult, changedRoots)
	local fallbackReward = 0
	if ChestRewards.FallbackReward.ScaleByTier == true then
		fallbackReward = getScaledBeliReward(chestData.Tier)
	else
		fallbackReward = math.max(0, tonumber(ChestRewards.FallbackReward.Amount) or 0)
	end

	local grantedAmount = addBeli(dataRoot, fallbackReward)
	if grantedAmount > 0 then
		changedRoots.Leaderstats = true
		changedRoots.TotalStats = true
	end

	openResult.Message = string.format("No fruit pool was available - granted %s instead", CurrencyUtil.formatAmount(grantedAmount))
	return string.format("%s (fruit fallback)", CurrencyUtil.formatAmount(grantedAmount))
end

local function handleDuplicateConversion(params, chestData, fruit, openResult, changedRoots)
	local conversion = ChestRewards.DuplicateConversion[fruit.Rarity]
	if typeof(conversion) ~= "table" then
		openResult.Message = "Already owned - no conversion reward configured"
		return "No duplicate conversion reward"
	end

	if conversion.Type == "Beli" or conversion.Type == "Doubloons" then
		local amount = if conversion.ScaleByTier == true
			then getScaledBeliReward(chestData.Tier)
			else math.max(0, tonumber(conversion.Amount) or 0)

		local grantedAmount = addBeli(params.DataRoot, amount)
		if grantedAmount > 0 then
			changedRoots.Leaderstats = true
			changedRoots.TotalStats = true
		end

		openResult.ConversionRewardType = "Beli"
		openResult.ConversionRewardAmount = grantedAmount
		openResult.ConversionRewardDisplayName = CurrencyUtil.getDisplayName()
		openResult.Message = string.format("Already owned - converted to %s", CurrencyUtil.formatAmount(grantedAmount))
		return string.format("%s (duplicate)", CurrencyUtil.formatAmount(grantedAmount))
	end

	if conversion.Type == "Chest" then
		local grantedChestData = ChestUtils.BuildChestData({
			ChestKind = ChestRewards.ChestKinds.DevilFruit,
			FruitRarity = conversion.FruitRarity,
			DepthBand = chestData.DepthBand,
			Source = chestData.Source,
			RewardProfile = chestData.RewardProfile,
		})
		local grantedChestId = params.AddChestEntry(grantedChestData)
		if grantedChestId then
			changedRoots.UnopenedChests = true
		end

		local chestInventoryName = ChestUtils.GetInventoryName(grantedChestData)
		openResult.ConversionRewardType = "Chest"
		openResult.ConversionRewardRarity = conversion.FruitRarity
		openResult.ConversionRewardDisplayName = ChestUtils.GetDisplayName(grantedChestData)
		openResult.GrantedChest = {
			chestId = grantedChestId,
			kind = grantedChestData.ChestKind,
			tier = grantedChestData.Tier,
			fruitRarity = grantedChestData.FruitRarity,
			inventoryName = chestInventoryName,
			displayName = ChestUtils.GetDisplayName(grantedChestData),
		}
		openResult.Message = string.format("Already owned - converted to %s", ChestUtils.GetDisplayName(grantedChestData))
		return ChestUtils.GetDisplayName(grantedChestData)
	end

	if conversion.Type == "MythicKey" then
		local chestRewardsState = ensureChestRewardsState(params.DataRoot)
		local increment = math.max(1, math.floor(tonumber(conversion.Amount) or 1))
		chestRewardsState.MythicKeys += increment
		changedRoots.ChestRewards = true

		openResult.ConversionRewardType = "MythicKey"
		openResult.ConversionRewardRarity = "Mythic"
		openResult.ConversionRewardAmount = increment
		openResult.ConversionRewardDisplayName = "Mythic Key"

		local threshold = ChestRewards.MythicKey.Threshold
		local autoConverted = false
		local grantedChestData = nil
		local grantedChestId = nil
		if ChestRewards.MythicKey.AutoConvert == true and chestRewardsState.MythicKeys >= threshold then
			chestRewardsState.MythicKeys -= threshold
			grantedChestData = ChestUtils.BuildChestData({
				ChestKind = ChestRewards.ChestKinds.DevilFruit,
				FruitRarity = "Mythic",
				DepthBand = chestData.DepthBand,
				Source = chestData.Source,
				RewardProfile = chestData.RewardProfile,
			})
			grantedChestId = params.AddChestEntry(grantedChestData)
			autoConverted = grantedChestId ~= nil
			if grantedChestId ~= nil then
				changedRoots.UnopenedChests = true
			end
		end

		openResult.AutoConvertedMythicChest = autoConverted
		if grantedChestData then
			openResult.GrantedChest = {
				chestId = grantedChestId,
				kind = grantedChestData.ChestKind,
				tier = grantedChestData.Tier,
				fruitRarity = grantedChestData.FruitRarity,
				inventoryName = ChestUtils.GetInventoryName(grantedChestData),
				displayName = ChestUtils.GetDisplayName(grantedChestData),
			}
		end

		openResult.MythicKeyProgress = {
			current = chestRewardsState.MythicKeys,
			threshold = threshold,
		}

		if autoConverted then
			openResult.Message = "Mythic Keys complete - Mythic Devil Fruit Chest granted"
			return "Mythic Devil Fruit Chest"
		end

		openResult.Message = string.format("Mythic Key +1 (%d/%d)", chestRewardsState.MythicKeys, threshold)
		return string.format("Mythic Key (%d/%d)", chestRewardsState.MythicKeys, threshold)
	end

	openResult.Message = "Already owned - unsupported duplicate conversion"
	return "Unsupported duplicate conversion"
end

function ChestRewardResolver.Resolve(params)
	assert(typeof(params) == "table", "ChestRewardResolver.Resolve expects params")
	assert(typeof(params.Player) == "Instance", "ChestRewardResolver.Resolve missing Player")
	assert(typeof(params.DataRoot) == "table", "ChestRewardResolver.Resolve missing DataRoot")
	assert(typeof(params.AddChestEntry) == "function", "ChestRewardResolver.Resolve missing AddChestEntry callback")

	local randomObject = params.Random or Random.new()
	local chestData = ChestUtils.BuildChestData(params.ChestData)
	local changedRoots = {}
	local openResult = buildOpenResult(params.DataRoot, {
		kind = chestData.ChestKind,
		tier = chestData.Tier,
		fruitRarity = chestData.FruitRarity,
		inventoryName = ChestUtils.GetInventoryName(chestData),
		displayName = ChestUtils.GetDisplayName(chestData),
	})

	if shouldGrantBaseRewards(chestData) then
		openResult.GrantedResources = grantBaseRewards(randomObject, params.DataRoot, chestData, changedRoots)
	end

	local gateChance = if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit
		then 1
		else math.max(0, tonumber(ChestRewards.FruitGateChanceByTier[chestData.Tier]) or 0)

	if gateChance <= 0 then
		return {
			OpenResult = openResult,
			ChangedRoots = changedRoots,
			RewardText = nil,
		}
	end

	if randomObject:NextNumber() > gateChance then
		return {
			OpenResult = openResult,
			ChangedRoots = changedRoots,
			RewardText = nil,
		}
	end

	local requestedRarity = chooseRequestedRarity(randomObject, chestData, params.Player)
	local effectiveRarity, pool = resolveEffectiveRarity(requestedRarity, getFruitPoolsByRarity())
	if effectiveRarity == nil or pool == nil or #pool <= 0 then
		return {
			OpenResult = openResult,
			ChangedRoots = changedRoots,
			RewardText = applyFallbackBeli(params.DataRoot, chestData, openResult, changedRoots),
		}
	end

	local selectionPool = pool
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit then
		local unownedPool = buildUnownedFruitPool(params.Player, pool)
		if #unownedPool > 0 then
			selectionPool = unownedPool
		end
	end

	local fruit = selectionPool[randomObject:NextInteger(1, #selectionPool)]
	openResult.GrantedFruitRarity = effectiveRarity

	if DevilFruitInventoryService.IsOwned(params.Player, fruit.FruitKey) then
		openResult.WasDuplicate = true
		openResult.GrantedFruit = nil
		openResult.GrantedFruitRarity = nil
		return {
			OpenResult = openResult,
			ChangedRoots = changedRoots,
			RewardText = handleDuplicateConversion(params, chestData, fruit, openResult, changedRoots),
		}
	end

	grantFruit(params.DataRoot, fruit.FruitKey)
	changedRoots.InventoryDevilFruits = true
	changedRoots.IndexCollectionDevilFruits = true
	openResult.GrantedFruit = fruit.FruitKey
	openResult.Message = string.format("Obtained: %s (%s)", tostring(fruit.DisplayName), tostring(effectiveRarity))

	return {
		OpenResult = openResult,
		ChangedRoots = changedRoots,
		RewardText = string.format("%s (%s)", tostring(fruit.DisplayName), tostring(effectiveRarity)),
	}
end

function ChestRewardResolver.ResolveSpecificFruit(params)
	assert(typeof(params) == "table", "ChestRewardResolver.ResolveSpecificFruit expects params")
	assert(typeof(params.Player) == "Instance", "ChestRewardResolver.ResolveSpecificFruit missing Player")
	assert(typeof(params.DataRoot) == "table", "ChestRewardResolver.ResolveSpecificFruit missing DataRoot")
	assert(typeof(params.AddChestEntry) == "function", "ChestRewardResolver.ResolveSpecificFruit missing AddChestEntry callback")

	local fruit = DevilFruitConfig.GetFruit(params.FruitIdentifier)
	assert(fruit ~= nil, "ChestRewardResolver.ResolveSpecificFruit missing valid fruit")

	local chestData = ChestUtils.BuildChestData({
		ChestKind = ChestRewards.ChestKinds.DevilFruit,
		FruitRarity = fruit.Rarity,
		DepthBand = params.DepthBand,
		Source = params.Source,
		RewardProfile = params.RewardProfile,
	})
	local changedRoots = {}
	local openResult = buildOpenResult(params.DataRoot, {
		kind = tostring(params.SourceKind or "DirectFruitReward"),
		tier = chestData.Tier,
		fruitRarity = tostring(fruit.Rarity or ""),
		inventoryName = tostring(params.SourceInventoryName or "Direct Fruit Reward"),
		displayName = tostring(params.SourceDisplayName or "Direct Fruit Reward"),
	})
	openResult.GrantedFruitRarity = tostring(fruit.Rarity or "")

	if DevilFruitInventoryService.IsOwned(params.Player, fruit.FruitKey) then
		openResult.WasDuplicate = true
		openResult.GrantedFruit = nil
		openResult.GrantedFruitRarity = nil
		return {
			OpenResult = openResult,
			ChangedRoots = changedRoots,
			RewardText = handleDuplicateConversion(params, chestData, fruit, openResult, changedRoots),
		}
	end

	grantFruit(params.DataRoot, fruit.FruitKey)
	changedRoots.InventoryDevilFruits = true
	changedRoots.IndexCollectionDevilFruits = true
	openResult.GrantedFruit = fruit.FruitKey
	openResult.Message = string.format("Obtained: %s (%s)", tostring(fruit.DisplayName), tostring(fruit.Rarity or "Unknown"))

	return {
		OpenResult = openResult,
		ChangedRoots = changedRoots,
		RewardText = string.format("%s (%s)", tostring(fruit.DisplayName), tostring(fruit.Rarity or "Unknown")),
	}
end

return ChestRewardResolver
