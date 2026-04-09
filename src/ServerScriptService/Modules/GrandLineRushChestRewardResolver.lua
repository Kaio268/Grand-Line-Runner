local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local DevilFruitInventoryService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitInventoryService"))

local ChestRewardResolver = {}

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

local function cloneShallow(source)
	local copy = {}
	for key, value in pairs(source or {}) do
		copy[key] = value
	end
	return copy
end

local function getTierRewards(tierName)
	local tierConfig = (Economy.Chests.Tiers or {})[tostring(tierName or "")]
	return (tierConfig and tierConfig.Rewards) or {}
end

local function getScaledDoubloonReward(tierName)
	local rewards = getTierRewards(tierName)
	return math.max(0, tonumber(rewards.Doubloons) or 0)
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

local function addDoubloons(dataRoot, amount)
	local increment = math.max(0, tonumber(amount) or 0)
	if increment <= 0 then
		return 0
	end

	local leaderstats = ensureLeaderstats(dataRoot)
	local totalStats = ensureTotalStats(dataRoot)

	leaderstats.Doubloons = math.max(0, tonumber(leaderstats.Doubloons) or 0) + increment
	totalStats.TotalDoubloons = math.max(0, tonumber(totalStats.TotalDoubloons) or 0) + increment

	return increment
end

local function grantBaseRewards(dataRoot, chestData, changedRoots)
	local rewards = getTierRewards(chestData.Tier)
	local foodRewards = cloneShallow(rewards.Food or {})
	local materialRewards = cloneShallow(rewards.Materials or {})
	local foodInventory = ensureFoodInventory(dataRoot)
	local materials = ensureMaterials(dataRoot)

	for foodKey, amount in pairs(foodRewards) do
		foodInventory[foodKey] = math.max(0, tonumber(foodInventory[foodKey]) or 0) + math.max(0, tonumber(amount) or 0)
	end

	for materialKey, amount in pairs(materialRewards) do
		materials[materialKey] = math.max(0, tonumber(materials[materialKey]) or 0) + math.max(0, tonumber(amount) or 0)
	end

	materials.Timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0)
	materials.Iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron

	local doubloonReward = addDoubloons(dataRoot, rewards.Doubloons)

	changedRoots.FoodInventory = true
	changedRoots.Materials = true
	changedRoots.Leaderstats = true
	changedRoots.TotalStats = true

	return {
		food = foodRewards,
		materials = materialRewards,
		doubloons = doubloonReward,
	}
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

local function chooseRequestedRarity(randomObject, chestData)
	if chestData.ChestKind == ChestRewards.ChestKinds.DevilFruit and chestData.FruitRarity ~= nil then
		return chestData.FruitRarity
	end

	return chooseWeightedKey(randomObject, ChestRewards.FruitRarityWeights, ChestRewards.FruitRarityOrder)
end

local function applyFallbackDoubloons(dataRoot, chestData, openResult, changedRoots)
	local fallbackReward = 0
	if ChestRewards.FallbackReward.ScaleByTier == true then
		fallbackReward = getScaledDoubloonReward(chestData.Tier)
	else
		fallbackReward = math.max(0, tonumber(ChestRewards.FallbackReward.Amount) or 0)
	end

	local grantedAmount = addDoubloons(dataRoot, fallbackReward)
	if grantedAmount > 0 then
		changedRoots.Leaderstats = true
		changedRoots.TotalStats = true
	end

	openResult.Message = string.format("No fruit pool was available - granted %d Doubloons instead", grantedAmount)
	return string.format("%d Doubloons (fruit fallback)", grantedAmount)
end

local function handleDuplicateConversion(params, chestData, fruit, openResult, changedRoots)
	local conversion = ChestRewards.DuplicateConversion[fruit.Rarity]
	if typeof(conversion) ~= "table" then
		openResult.Message = "Already owned - no conversion reward configured"
		return "No duplicate conversion reward"
	end

	if conversion.Type == "Doubloons" then
		local amount = if conversion.ScaleByTier == true
			then getScaledDoubloonReward(chestData.Tier)
			else math.max(0, tonumber(conversion.Amount) or 0)

		local grantedAmount = addDoubloons(params.DataRoot, amount)
		if grantedAmount > 0 then
			changedRoots.Leaderstats = true
			changedRoots.TotalStats = true
		end

		openResult.ConversionRewardType = "Doubloons"
		openResult.ConversionRewardAmount = grantedAmount
		openResult.ConversionRewardDisplayName = "Doubloons"
		openResult.Message = string.format("Already owned - converted to %d Doubloons", grantedAmount)
		return string.format("%d Doubloons (duplicate)", grantedAmount)
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
		openResult.GrantedResources = grantBaseRewards(params.DataRoot, chestData, changedRoots)
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

	local requestedRarity = chooseRequestedRarity(randomObject, chestData)
	local effectiveRarity, pool = resolveEffectiveRarity(requestedRarity, getFruitPoolsByRarity())
	if effectiveRarity == nil or pool == nil or #pool <= 0 then
		return {
			OpenResult = openResult,
			ChangedRoots = changedRoots,
			RewardText = applyFallbackDoubloons(params.DataRoot, chestData, openResult, changedRoots),
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
