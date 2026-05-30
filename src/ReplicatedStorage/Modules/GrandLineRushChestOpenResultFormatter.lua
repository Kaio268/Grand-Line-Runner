local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruits = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local ChestOpenResultFormatter = {}

local FOOD_ORDER = { "Apple", "Rice", "Meat", "SeaBeastMeat" }
local REWARD_TYPE_DEVIL_FRUIT = "DevilFruit"
local DEFAULT_CHEST_IMAGE = "rbxassetid://104345752533382"
local DEFAULT_CHEST_ICON = "rbxassetid://88825249018556"
local REWARD_ICONS = {
	["Ancient Timber"] = "rbxassetid://104684352334133",
	Apple = "rbxassetid://130525653161326",
	Beli = "rbxassetid://86551660159840",
	["Devil Fruit"] = "rbxassetid://122583196938184",
	Iron = "rbxassetid://109691838211287",
	Meat = "rbxassetid://98603088450093",
	["Mythic Key"] = "rbxassetid://122583196938184",
	Rice = "rbxassetid://128596106748016",
	Timber = "rbxassetid://108977229097543",
}
local RARITY_RANK = {
	Common = 1,
	Rare = 2,
	Legendary = 3,
	Mythic = 4,
}
local RARITY_COLORS = {
	Common = Color3.fromRGB(201, 206, 215),
	Rare = Color3.fromRGB(98, 184, 255),
	Legendary = Color3.fromRGB(255, 197, 94),
	Mythic = Color3.fromRGB(118, 244, 214),
	DevilFruit = Color3.fromRGB(116, 245, 183),
	Reward = Color3.fromRGB(116, 245, 183),
	Duplicate = Color3.fromRGB(255, 179, 92),
}
local SUPPORTED_CHEST_VISUAL_KEYS = {
	wood = true,
	wooden = true,
	woodenchest = true,
	iron = true,
	ironchest = true,
	gold = true,
	golden = true,
	goldchest = true,
	goldenchest = true,
	devilfruit = true,
	commondevilfruit = true,
	raredevilfruit = true,
	legendarydevilfruit = true,
	mythicdevilfruit = true,
}

local function normalizeChestVisualKey(value)
	local key = tostring(value or "")
	key = key:gsub("%s+", "")
	key = key:gsub("[_%-]", "")
	return string.lower(key)
end

local function sanitizeChestVisualKey(candidate)
	if tostring(candidate or "") == "" then
		return nil
	end

	local parsed = ChestUtils.ParseInventoryName(candidate)
	local styleName = ChestUtils.GetVisualStyleName(parsed)
	if SUPPORTED_CHEST_VISUAL_KEYS[normalizeChestVisualKey(styleName)] then
		return styleName
	end

	if SUPPORTED_CHEST_VISUAL_KEYS[normalizeChestVisualKey(candidate)] then
		return tostring(candidate)
	end

	return nil
end

local function stripChestDisplaySuffix(displayName)
	local value = tostring(displayName or "")
	value = value:gsub("%s+[Cc]hests$", "")
	value = value:gsub("%s+[Cc]hest$", "")
	return value
end

local function resolveOpenedChestVisualKey(openedChest)
	if typeof(openedChest) ~= "table" then
		return nil
	end

	local inventoryName = sanitizeChestVisualKey(openedChest.inventoryName)
	if inventoryName then
		return inventoryName
	end

	local tierName = tostring(openedChest.tier or "")
	if tierName ~= "" then
		if tostring(openedChest.kind or "") == "DevilFruit" then
			local fruitRarity = tostring(openedChest.fruitRarity or "")
			if fruitRarity ~= "" then
				return sanitizeChestVisualKey(fruitRarity .. " Devil Fruit")
			end

			return sanitizeChestVisualKey("Devil Fruit")
		end

		return sanitizeChestVisualKey(tierName)
	end

	return sanitizeChestVisualKey(stripChestDisplaySuffix(openedChest.displayName))
end

local function appendLine(lines, text)
	if typeof(text) ~= "string" or text == "" then
		return
	end

	lines[#lines + 1] = text
end

local function appendRewardRow(rows, name, amount, icon)
	local normalizedAmount = math.max(0, tonumber(amount) or 0)
	if tostring(name or "") == "" or normalizedAmount <= 0 then
		return
	end

	rows[#rows + 1] = {
		Name = tostring(name),
		Amount = normalizedAmount,
		Icon = if typeof(icon) == "string" then icon else "",
	}
end

local function formatCount(amount)
	return CurrencyUtil.formatCount(math.max(0, math.floor(tonumber(amount) or 0)))
end

local function getGrantedBeli(grantedResources)
	grantedResources = if typeof(grantedResources) == "table" then grantedResources else {}
	return math.max(0, tonumber(grantedResources.beli) or tonumber(grantedResources.doubloons) or 0)
end

local function fruitDisplayName(fruitKey)
	local fruit = DevilFruits.GetFruit(fruitKey)
	if fruit and fruit.DisplayName then
		return tostring(fruit.DisplayName), tostring(fruit.Rarity or "")
	end

	return tostring(fruitKey or "Unknown Devil Fruit"), ""
end

local function pluralizeChestDisplay(name, count)
	local displayName = tostring(name or "Chest")
	if count == 1 then
		return displayName
	end
	if displayName:sub(-1) == "s" then
		return displayName
	end
	return displayName .. "s"
end

local function getRewardIcon(name, fallback)
	local displayName = tostring(name or "")
	return REWARD_ICONS[displayName] or fallback or ""
end

local function applyRewardMetadata(card, metadata)
	if typeof(metadata) ~= "table" then
		return
	end

	for key, value in pairs(metadata) do
		card[key] = value
	end
end

local function getDevilFruitRewardMetadata(fruitKey)
	local normalizedFruitKey = tostring(fruitKey or "")
	if normalizedFruitKey == "" then
		return nil
	end

	return {
		rewardType = REWARD_TYPE_DEVIL_FRUIT,
		fruitKey = normalizedFruitKey,
	}
end

local function appendResultCard(cards, name, amount, icon, rarity, metadata)
	local normalizedAmount = math.max(0, tonumber(amount) or 0)
	if tostring(name or "") == "" or normalizedAmount <= 0 then
		return
	end
	local displayName = tostring(name)
	local displayIcon = getRewardIcon(displayName, icon)

	for _, existing in ipairs(cards) do
		if existing.name == displayName and existing.icon == displayIcon then
			existing.amount = math.max(0, tonumber(existing.amount) or 0) + normalizedAmount
			existing.amountText = "+" .. formatCount(existing.amount)
			applyRewardMetadata(existing, metadata)
			return
		end
	end

	local card = {
		name = displayName,
		amount = normalizedAmount,
		amountText = "+" .. formatCount(normalizedAmount),
		icon = displayIcon,
		rarity = tostring(rarity or ""),
	}
	applyRewardMetadata(card, metadata)
	cards[#cards + 1] = card
end

local function addGrantedResourceCards(cards, grantedResources)
	grantedResources = if typeof(grantedResources) == "table" then grantedResources else {}
	local foodRewards = if typeof(grantedResources.food) == "table" then grantedResources.food else {}
	local materialRewards = if typeof(grantedResources.materials) == "table" then grantedResources.materials else {}

	for _, foodKey in ipairs(FOOD_ORDER) do
		local displayName = tostring(((Economy.Food or {})[foodKey] or {}).DisplayName or foodKey)
		appendResultCard(cards, displayName, foodRewards[foodKey], getRewardIcon(displayName))
	end

	local seenMaterials = {}
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
		seenMaterials[materialKey] = true
		local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
		appendResultCard(cards, displayName, materialRewards[materialKey], getRewardIcon(displayName))
	end

	for materialKey, amount in pairs(materialRewards) do
		if seenMaterials[materialKey] ~= true then
			local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
			appendResultCard(cards, displayName, amount, getRewardIcon(displayName))
		end
	end

	appendResultCard(cards, CurrencyUtil.getDisplayName(), getGrantedBeli(grantedResources), getRewardIcon(CurrencyUtil.getDisplayName()))
end

local function makeFeaturedReward(name, amount, icon, rarity, metadata)
	local normalizedAmount = math.max(1, tonumber(amount) or 1)
	local reward = {
		name = tostring(name or "Special Reward"),
		amount = normalizedAmount,
		amountText = "+" .. formatCount(normalizedAmount),
		icon = getRewardIcon(name, icon or REWARD_ICONS["Devil Fruit"]),
		rarity = tostring(rarity or "Reward"),
		isFeatured = true,
	}
	applyRewardMetadata(reward, metadata)
	return reward
end

local function collectFruitResultCards(openResult, cards)
	local fruitRecordsByKey = {}
	if typeof(openResult.GrantedFruit) == "string" and openResult.GrantedFruit ~= "" then
		local displayName, rarityName = fruitDisplayName(openResult.GrantedFruit)
		fruitRecordsByKey[openResult.GrantedFruit] = {
			key = openResult.GrantedFruit,
			name = displayName,
			rarity = tostring(openResult.GrantedFruitRarity or rarityName or ""),
			amount = 1,
		}
	end

	for _, fruitEntry in ipairs(openResult.GrantedFruits or {}) do
		local fruitKey = tostring(fruitEntry.FruitKey or "")
		if fruitKey ~= "" then
			local displayName, rarityName = fruitDisplayName(fruitKey)
			local record = fruitRecordsByKey[fruitKey]
			if not record then
				record = {
					key = fruitKey,
					name = displayName,
					rarity = tostring(fruitEntry.Rarity or rarityName or ""),
					amount = 0,
				}
				fruitRecordsByKey[fruitKey] = record
			end
			record.amount += 1
		end
	end

	local fruitRecords = {}
	for _, record in pairs(fruitRecordsByKey) do
		fruitRecords[#fruitRecords + 1] = record
	end
	table.sort(fruitRecords, function(a, b)
		local aRank = RARITY_RANK[a.rarity] or 0
		local bRank = RARITY_RANK[b.rarity] or 0
		if aRank ~= bRank then
			return aRank > bRank
		end
		return tostring(a.name) < tostring(b.name)
	end)

	local featured = nil
	for index, record in ipairs(fruitRecords) do
		local metadata = getDevilFruitRewardMetadata(record.key)
		if index == 1 then
			featured = makeFeaturedReward(record.name, record.amount, REWARD_ICONS["Devil Fruit"], record.rarity, metadata)
		else
			appendResultCard(cards, record.name, record.amount, REWARD_ICONS["Devil Fruit"], record.rarity, metadata)
		end
	end

	return featured
end

local function resolveConversionFeatured(openResult)
	if openResult.ConversionRewardType == "Chest" then
		local convertedName = tostring(
			openResult.ConversionRewardDisplayName
				or ((openResult.GrantedChest or {}).displayName)
				or "Devil Fruit Chest"
		)
		return makeFeaturedReward(convertedName, 1, DEFAULT_CHEST_ICON, openResult.ConversionRewardRarity)
	elseif openResult.ConversionRewardType == "MythicKey" then
		return makeFeaturedReward(
			tostring(openResult.ConversionRewardDisplayName or "Mythic Key"),
			math.max(1, tonumber(openResult.ConversionRewardAmount) or 1),
			REWARD_ICONS["Mythic Key"],
			"Mythic"
		)
	end

	return nil
end

local function addGrantedResourceLines(lines, grantedResources)
	grantedResources = if typeof(grantedResources) == "table" then grantedResources else {}
	local foodRewards = if typeof(grantedResources.food) == "table" then grantedResources.food else {}
	local materialRewards = if typeof(grantedResources.materials) == "table" then grantedResources.materials else {}
	local addedAny = false

	for _, foodKey in ipairs(FOOD_ORDER) do
		local amount = math.max(0, tonumber(foodRewards[foodKey]) or 0)
		if amount > 0 then
			local displayName = tostring(((Economy.Food or {})[foodKey] or {}).DisplayName or foodKey)
			appendLine(lines, string.format("+%s %s", formatCount(amount), displayName))
			addedAny = true
		end
	end

	local seenMaterials = {}
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
		seenMaterials[materialKey] = true
		local amount = math.max(0, tonumber(materialRewards[materialKey]) or 0)
		if amount > 0 then
			local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
			appendLine(lines, string.format("+%s %s", formatCount(amount), displayName))
			addedAny = true
		end
	end

	for materialKey, amountValue in pairs(materialRewards) do
		if seenMaterials[materialKey] ~= true then
			local amount = math.max(0, tonumber(amountValue) or 0)
			if amount > 0 then
				local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
				appendLine(lines, string.format("+%s %s", formatCount(amount), displayName))
				addedAny = true
			end
		end
	end

	local beli = getGrantedBeli(grantedResources)
	if beli > 0 then
		appendLine(lines, "+" .. CurrencyUtil.formatAmount(beli))
		addedAny = true
	end

	return addedAny
end

local function addGrantedResourceRows(rows, grantedResources)
	grantedResources = if typeof(grantedResources) == "table" then grantedResources else {}
	local foodRewards = if typeof(grantedResources.food) == "table" then grantedResources.food else {}
	local materialRewards = if typeof(grantedResources.materials) == "table" then grantedResources.materials else {}

	for _, foodKey in ipairs(FOOD_ORDER) do
		local displayName = tostring(((Economy.Food or {})[foodKey] or {}).DisplayName or foodKey)
		appendRewardRow(rows, displayName, foodRewards[foodKey])
	end

	local seenMaterials = {}
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
		seenMaterials[materialKey] = true
		local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
		appendRewardRow(rows, displayName, materialRewards[materialKey])
	end

	for materialKey, amount in pairs(materialRewards) do
		if seenMaterials[materialKey] ~= true then
			local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
			appendRewardRow(rows, displayName, amount)
		end
	end

	appendRewardRow(rows, CurrencyUtil.getDisplayName(), getGrantedBeli(grantedResources))
end

local function resolveAccent(openResult)
	if openResult.GrantedFruitRarity and RARITY_COLORS[openResult.GrantedFruitRarity] then
		return tostring(openResult.GrantedFruitRarity):upper(), RARITY_COLORS[openResult.GrantedFruitRarity]
	end

	if openResult.ConversionRewardType == "Chest" and openResult.ConversionRewardRarity and RARITY_COLORS[openResult.ConversionRewardRarity] then
		return "DUPLICATE", RARITY_COLORS[openResult.ConversionRewardRarity]
	end

	if openResult.ConversionRewardType == "MythicKey" then
		return "MYTHIC KEY", RARITY_COLORS.Mythic
	end

	if openResult.WasDuplicate then
		return "DUPLICATE", RARITY_COLORS.Duplicate
	end

	return "REWARD", RARITY_COLORS.Reward
end

local function buildTitle(openResult)
	local openedChestDisplay = tostring(((openResult.OpenedChest or {}).displayName) or "Chest")

	if openResult.GrantedFruit then
		return "Devil Fruit Obtained"
	end

	if openResult.ConversionRewardType == "Chest" then
		return "Duplicate Converted"
	end

	if openResult.ConversionRewardType == "MythicKey" then
		return "Mythic Key Progress"
	end

	return string.format("Opened %s", openedChestDisplay)
end

local function buildBatchAcknowledgement(openResult)
	local openedCount = math.max(1, tonumber(openResult.OpenedCount) or 1)
	local openedChestDisplay = tostring(((openResult.OpenedChest or {}).displayName) or "Chests")
	local lines = {}
	local rewardRows = {}
	addGrantedResourceLines(lines, openResult.GrantedResources)
	addGrantedResourceRows(rewardRows, openResult.GrantedResources)

	local fruitCounts = {}
	for _, fruitEntry in ipairs(openResult.GrantedFruits or {}) do
		local fruitKey = tostring(fruitEntry.FruitKey or "")
		if fruitKey ~= "" then
			local displayName = fruitDisplayName(fruitKey)
			fruitCounts[displayName] = math.max(0, tonumber(fruitCounts[displayName]) or 0) + 1
		end
	end
	for displayName, amount in pairs(fruitCounts) do
		appendLine(lines, string.format("+%s %s", formatCount(amount), displayName))
		appendRewardRow(rewardRows, displayName, amount)
	end

	local duplicateCount = math.max(0, tonumber(openResult.DuplicateCount) or 0)
	if duplicateCount > 0 then
		appendLine(lines, string.format("%s duplicate%s converted", formatCount(duplicateCount), duplicateCount == 1 and "" or "s"))
	end

	local convertedChestCount = math.max(0, tonumber(openResult.ConvertedChestCount) or 0)
	if convertedChestCount > 0 then
		appendLine(lines, string.format(
			"%s duplicate%s refunded as Devil Fruit Chest%s",
			formatCount(convertedChestCount),
			convertedChestCount == 1 and "" or "s",
			convertedChestCount == 1 and "" or "s"
		))
	end
	for _, convertedChest in ipairs(openResult.ConvertedChests or {}) do
		appendRewardRow(rewardRows, string.format("Duplicate Refund - %s", tostring(convertedChest.DisplayName)), convertedChest.Amount)
	end

	local conversionBeli = math.max(0, tonumber(openResult.ConversionBeli) or tonumber(openResult.ConversionDoubloons) or 0)
	if conversionBeli > 0 then
		appendLine(lines, "+" .. CurrencyUtil.formatAmount(conversionBeli) .. " duplicate conversion")
		appendRewardRow(rewardRows, CurrencyUtil.getDisplayName(), conversionBeli)
	end

	local mythicKeyCount = math.max(0, tonumber(openResult.MythicKeyCount) or 0)
	if mythicKeyCount > 0 then
		appendLine(lines, string.format("+%s Mythic Key%s", formatCount(mythicKeyCount), mythicKeyCount == 1 and "" or "s"))
		appendRewardRow(rewardRows, "Duplicate Refund - Mythic Key", mythicKeyCount, REWARD_ICONS["Mythic Key"])
	end

	local autoConvertedChestCount = math.max(0, tonumber(openResult.AutoConvertedChestCount) or 0)
	if autoConvertedChestCount > 0 then
		appendLine(lines, string.format(
			"+%s Mythic Devil Fruit Chest%s auto-converted",
			formatCount(autoConvertedChestCount),
			autoConvertedChestCount == 1 and "" or "s"
		))
	end
	for _, autoConvertedChest in ipairs(openResult.AutoConvertedChests or {}) do
		appendRewardRow(
			rewardRows,
			string.format("Auto Converted - %s", tostring(autoConvertedChest.DisplayName or "Mythic Devil Fruit Chest")),
			autoConvertedChest.Amount,
			DEFAULT_CHEST_ICON
		)
	end

	if #lines == 0 then
		appendLine(lines, "No rewards were granted.")
	end

	return {
		Title = string.format("Opened %s %s%s", formatCount(openedCount), openedChestDisplay, openedCount == 1 and "" or "s"),
		AccentText = "BATCH OPEN",
		AccentColor = RARITY_COLORS.Reward,
		ButtonText = "Close",
		ButtonColor = RARITY_COLORS.Reward,
		Lines = lines,
		RewardRows = rewardRows,
	}
end

function ChestOpenResultFormatter.BuildAcknowledgementOptions(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}
	if openResult.IsBatch == true then
		return buildBatchAcknowledgement(openResult)
	end

	local accentText, accentColor = resolveAccent(openResult)
	local lines = {}
	local hadResources = addGrantedResourceLines(lines, openResult.GrantedResources)
	local bodyRawText = nil
	local bodyMode = nil

	if openResult.GrantedFruit then
		local displayName, rarityName = fruitDisplayName(openResult.GrantedFruit)
		bodyRawText = displayName
		bodyMode = "FruitFocus"
		if hadResources then
			appendLine(lines, "")
		end
		appendLine(lines, displayName)
		appendLine(lines, string.format("Rarity: %s", tostring(openResult.GrantedFruitRarity or rarityName or "Unknown")))
	elseif openResult.WasDuplicate then
		if hadResources then
			appendLine(lines, "")
		end
		appendLine(lines, "Duplicate detected.")

		if openResult.ConversionRewardType == "Chest" then
			local convertedName = tostring(
				openResult.ConversionRewardDisplayName
					or ((openResult.GrantedChest or {}).displayName)
					or "Devil Fruit Chest"
			)
			appendLine(lines, string.format("Converted to: %s", convertedName))
		elseif openResult.ConversionRewardType == "MythicKey" then
			local amount = math.max(1, tonumber(openResult.ConversionRewardAmount) or 1)
			appendLine(lines, string.format("Reward: +%s %s", formatCount(amount), tostring(openResult.ConversionRewardDisplayName or "Mythic Key")))
			local progress = openResult.MythicKeyProgress or {}
			appendLine(
				lines,
				string.format(
					"Progress: %s/%s",
					formatCount(progress.current),
					formatCount(progress.threshold)
				)
			)
			if openResult.AutoConvertedMythicChest == true and typeof(openResult.GrantedChest) == "table" then
				appendLine(lines, string.format("Auto-converted: %s", tostring(openResult.GrantedChest.displayName or "Mythic Devil Fruit Chest")))
			end
		elseif openResult.ConversionRewardType == "Beli" or openResult.ConversionRewardType == "Doubloons" then
			appendLine(
				lines,
				"Converted to: +" .. CurrencyUtil.formatAmount(math.max(0, tonumber(openResult.ConversionRewardAmount) or 0))
			)
		elseif typeof(openResult.Message) == "string" and openResult.Message ~= "" then
			appendLine(lines, openResult.Message)
		end
	elseif typeof(openResult.Message) == "string" and openResult.Message ~= "" then
		if hadResources then
			appendLine(lines, "")
		end
		appendLine(lines, openResult.Message)
	end

	if #lines == 0 then
		appendLine(lines, "The chest opened successfully.")
	end

	return {
		Title = buildTitle(openResult),
		AccentText = accentText,
		AccentColor = accentColor,
		ButtonText = "Close",
		ButtonColor = accentColor,
		BodyRawText = bodyRawText,
		BodyMode = bodyMode,
		Lines = lines,
		PreviewFruitKey = if typeof(openResult.GrantedFruit) == "string" then openResult.GrantedFruit else nil,
	}
end

function ChestOpenResultFormatter.BuildResultsScreenModel(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}

	local openedCount = math.max(1, math.floor(tonumber(openResult.OpenedCount) or 1))
	local openedChest = if typeof(openResult.OpenedChest) == "table" then openResult.OpenedChest else {}
	local openedChestDisplayName = tostring(openedChest.displayName or "Chest")
	local displayChestName = pluralizeChestDisplay(openedChestDisplayName, openedCount)
	local rewardCards = {}

	addGrantedResourceCards(rewardCards, openResult.GrantedResources)
	local featuredReward = collectFruitResultCards(openResult, rewardCards)

	if featuredReward == nil then
		featuredReward = resolveConversionFeatured(openResult)
	end

	if openResult.IsBatch == true then
		local convertedChests = openResult.ConvertedChests or {}
		for _, convertedChest in ipairs(convertedChests) do
			appendResultCard(
				rewardCards,
				string.format("Duplicate Refund - %s", tostring(convertedChest.DisplayName or "Chest")),
				convertedChest.Amount,
				DEFAULT_CHEST_ICON,
				"Reward"
			)
		end

		local conversionBeli = math.max(0, tonumber(openResult.ConversionBeli) or tonumber(openResult.ConversionDoubloons) or 0)
		appendResultCard(rewardCards, CurrencyUtil.getDisplayName(), conversionBeli, REWARD_ICONS.Beli, "Duplicate")

		local mythicKeyCount = math.max(0, tonumber(openResult.MythicKeyCount) or 0)
		appendResultCard(
			rewardCards,
			"Duplicate Refund - Mythic Key",
			mythicKeyCount,
			REWARD_ICONS["Mythic Key"],
			"Mythic"
		)

		for _, autoConvertedChest in ipairs(openResult.AutoConvertedChests or {}) do
			appendResultCard(
				rewardCards,
				string.format("Auto Converted - %s", tostring(autoConvertedChest.DisplayName or "Mythic Devil Fruit Chest")),
				autoConvertedChest.Amount,
				DEFAULT_CHEST_ICON,
				tostring(autoConvertedChest.Rarity or autoConvertedChest.FruitRarity or "Mythic")
			)
		end
	else
		if typeof(openResult.GrantedChest) == "table" and openResult.AutoConvertedMythicChest == true then
			appendResultCard(
				rewardCards,
				tostring(openResult.GrantedChest.displayName or "Mythic Devil Fruit Chest"),
				1,
				DEFAULT_CHEST_ICON,
				"Mythic"
			)
		end

		if openResult.ConversionRewardType == "Beli" or openResult.ConversionRewardType == "Doubloons" then
			appendResultCard(
				rewardCards,
				CurrencyUtil.getDisplayName(),
				math.max(0, tonumber(openResult.ConversionRewardAmount) or 0),
				REWARD_ICONS.Beli,
				"Duplicate"
			)
		end
	end

	if featuredReward == nil and #rewardCards == 0 then
		rewardCards[#rewardCards + 1] = {
			name = "Rewards Claimed",
			amount = 1,
			amountText = "+1",
			icon = DEFAULT_CHEST_ICON,
			rarity = "Reward",
		}
	end

	return {
		openedCount = openedCount,
		openedChestDisplayName = openedChestDisplayName,
		subtitle = string.format("You opened %s %s", formatCount(openedCount), displayChestName),
		chestImage = DEFAULT_CHEST_IMAGE,
		chestVisualKey = resolveOpenedChestVisualKey(openedChest),
		featuredReward = featuredReward,
		rewardCards = rewardCards,
	}
end

function ChestOpenResultFormatter.GetCelebrationCount(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}
	if openResult.IsBatch == true then
		return math.min(36, math.max(0, #(openResult.GrantedFruits or {}) * 6))
	end

	if openResult.AutoConvertedMythicChest == true then
		return 36
	end

	if tostring(openResult.GrantedFruitRarity) == "Mythic" then
		return 28
	end

	if openResult.GrantedFruit ~= nil then
		return 22
	end

	if openResult.ConversionRewardType == "Chest" and tostring(openResult.ConversionRewardRarity) == "Legendary" then
		return 16
	end

	return 0
end

return ChestOpenResultFormatter
