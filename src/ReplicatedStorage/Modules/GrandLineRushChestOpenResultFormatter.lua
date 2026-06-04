local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local DevilFruits = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ItemIconRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ItemIconRegistry"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local RewardIconResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RewardIconResolver"))

local ChestOpenResultFormatter = {}

local FOOD_ORDER = { "Apple", "Rice", "Meat", "SeaBeastMeat" }
local REWARD_TYPE_DEVIL_FRUIT = "DevilFruit"
local DEFAULT_CHEST_ICON = ItemIconRegistry.GetIcon("Chest")
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

local function normalizeLookupKey(value)
	local key = tostring(value or "")
	key = key:gsub("%s+", "")
	key = key:gsub("[_%-]", "")
	return string.lower(key)
end

local function appendIconCandidate(candidates, value)
	local candidate = tostring(value or "")
	if candidate ~= "" then
		candidates[#candidates + 1] = candidate
	end
end

local function resolveChestIconCandidate(candidate)
	local resolved = RewardIconResolver.Resolve(candidate, "")
	if tostring(resolved.category or resolved.Category or "") ~= "Chest" then
		return nil
	end

	local icon = tostring(resolved.icon or resolved.Icon or "")
	if icon ~= "" then
		return icon
	end

	return nil
end

local function isDevilFruitChestKind(kind)
	return normalizeLookupKey(kind):find("devilfruit", 1, true) ~= nil
end

local function resolveOpenedChestIcon(openedChest)
	if typeof(openedChest) ~= "table" then
		return DEFAULT_CHEST_ICON
	end

	local candidates = {}
	appendIconCandidate(candidates, openedChest.inventoryName)
	appendIconCandidate(candidates, openedChest.InventoryName)
	appendIconCandidate(candidates, openedChest.displayName)
	appendIconCandidate(candidates, openedChest.DisplayName)

	local kind = tostring(openedChest.kind or openedChest.ChestKind or "")
	local fruitRarity = tostring(openedChest.fruitRarity or openedChest.FruitRarity or "")
	if fruitRarity ~= "" and isDevilFruitChestKind(kind) then
		appendIconCandidate(candidates, fruitRarity .. " Devil Fruit Chest")
		appendIconCandidate(candidates, fruitRarity .. "DevilFruitChest")
	end

	local tier = tostring(openedChest.tier or openedChest.Tier or "")
	if tier ~= "" then
		appendIconCandidate(candidates, tier .. " Chest")
		appendIconCandidate(candidates, tier .. "Chest")
	end

	for _, candidate in ipairs(candidates) do
		local icon = resolveChestIconCandidate(candidate)
		if icon ~= nil then
			return icon
		end
	end

	return DEFAULT_CHEST_ICON
end

local function appendLine(lines, text)
	if typeof(text) ~= "string" or text == "" then
		return
	end

	lines[#lines + 1] = text
end

local function getRewardIcon(name, fallback)
	return RewardIconResolver.GetIcon(name, fallback)
end

local function resolveRewardRowIcon(name, icon)
	local explicitIcon = if typeof(icon) == "string" then icon else ""
	if explicitIcon ~= "" then
		return getRewardIcon(name, explicitIcon)
	end

	local resolved = RewardIconResolver.Resolve(name, "")
	if tostring(resolved.category or resolved.Category or "") == "Chest" then
		return tostring(resolved.icon or resolved.Icon or "")
	end

	return ""
end

local function appendRewardRow(rows, name, amount, icon)
	local normalizedAmount = math.max(0, tonumber(amount) or 0)
	if tostring(name or "") == "" or normalizedAmount <= 0 then
		return
	end
	local displayName = tostring(name)

	rows[#rows + 1] = {
		Name = displayName,
		Amount = normalizedAmount,
		Icon = resolveRewardRowIcon(displayName, icon),
	}
end

local function formatCount(amount)
	return CurrencyUtil.formatCount(math.max(0, math.floor(tonumber(amount) or 0)))
end

local function formatWholeCommaNumber(amount)
	local number = tonumber(amount) or 0
	local sign = if number < 0 then "-" else ""
	local roundedText = tostring(math.floor(math.abs(number) + 0.5))
	local reversed = string.reverse(roundedText)
	local grouped = string.reverse((string.gsub(reversed, "(%d%d%d)", "%1,")))

	grouped = string.gsub(grouped, "^,", "")
	return sign .. grouped
end

local function getPityAccentColor(rarityName)
	return RARITY_COLORS[tostring(rarityName or "")] or RARITY_COLORS.Reward
end

local function collectTriggeredPityTexts(openResult)
	local triggeredByRarity = {}
	local function addTrigger(trigger)
		if typeof(trigger) ~= "table" then
			return
		end

		local rarityName = tostring(trigger.Rarity or "")
		if rarityName ~= "" then
			triggeredByRarity[rarityName] = true
		end
	end

	addTrigger(openResult.FruitPityTriggered)
	for _, trigger in ipairs(openResult.FruitPityTriggers or {}) do
		addTrigger(trigger)
	end

	local activationTexts = {}
	local accentColor = nil
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		if triggeredByRarity[rarityName] == true then
			activationTexts[#activationTexts + 1] = string.format("%s PITY ACTIVATED!", string.upper(rarityName))
			accentColor = getPityAccentColor(rarityName)
		end
	end

	return activationTexts, accentColor
end

local function buildFruitPityStatus(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}
	local fruitPityProgress = openResult.FruitPityProgress
	if typeof(fruitPityProgress) ~= "table" then
		return nil
	end

	local progressParts = {}
	local accentColor = nil
	for _, rarityName in ipairs(ChestRewards.FruitRarityOrder) do
		local entry = fruitPityProgress[rarityName]
		if typeof(entry) == "table" then
			local failedOpens = math.max(0, math.floor(tonumber(entry.FailedOpens) or 0))
			local hardPity = math.max(1, math.floor(tonumber(entry.HardPity) or 1))
			progressParts[#progressParts + 1] = string.format(
				"%s PITY: %s/%s",
				string.upper(rarityName),
				formatWholeCommaNumber(failedOpens),
				formatWholeCommaNumber(hardPity)
			)
			accentColor = getPityAccentColor(rarityName)
		end
	end

	if #progressParts <= 0 then
		return nil
	end

	local activationTexts, activationAccent = collectTriggeredPityTexts(openResult)
	return {
		activationTexts = activationTexts,
		progressText = table.concat(progressParts, "  |  "),
		accentColor = activationAccent or accentColor or RARITY_COLORS.Reward,
	}
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

local function joinNonEmptyTexts(values)
	local parts = {}
	for _, value in ipairs(values or {}) do
		local normalized = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if normalized ~= "" then
			parts[#parts + 1] = normalized
		end
	end
	return table.concat(parts, "  ")
end

local function getPityTitleText(pityStatus)
	if typeof(pityStatus) ~= "table" then
		return ""
	end
	return joinNonEmptyTexts(pityStatus.activationTexts)
end

local function normalizeFruitRewardContext(rawContext)
	if typeof(rawContext) ~= "table" then
		return nil
	end

	local fruitKey = tostring(rawContext.FruitKey or rawContext.fruitKey or "")
	local displayName = tostring(rawContext.DisplayName or rawContext.displayName or "")
	local rarity = tostring(rawContext.Rarity or rawContext.rarity or rawContext.FruitRarity or rawContext.fruitRarity or "")
	if displayName == "" and fruitKey ~= "" then
		local resolvedName, resolvedRarity = fruitDisplayName(fruitKey)
		displayName = resolvedName
		if rarity == "" then
			rarity = resolvedRarity
		end
	end

	local source = tostring(rawContext.Source or rawContext.source or "")
	if source == "" then
		source = "standard_chest"
	elseif source ~= "standard_chest" then
		return nil
	end

	if rawContext.HasDevilFruitReward ~= true and fruitKey == "" and displayName == "" then
		return nil
	end

	return {
		HasDevilFruitReward = true,
		Source = source,
		FruitKey = fruitKey,
		DisplayName = if displayName ~= "" then displayName else "Devil Fruit",
		Rarity = rarity,
		WasDuplicate = rawContext.WasDuplicate == true or rawContext.wasDuplicate == true,
	}
end

local function collectFruitRewardContexts(openResult)
	local contexts = {}

	for _, rawContext in ipairs(openResult.FruitRewardContexts or {}) do
		local context = normalizeFruitRewardContext(rawContext)
		if context then
			contexts[#contexts + 1] = context
		end
	end

	local singleContext = normalizeFruitRewardContext(openResult.FruitRewardContext)
	if singleContext then
		contexts[#contexts + 1] = singleContext
	end

	if #contexts > 0 then
		return contexts
	end

	if typeof(openResult.GrantedFruit) == "string" and openResult.GrantedFruit ~= "" then
		local displayName, rarityName = fruitDisplayName(openResult.GrantedFruit)
		contexts[#contexts + 1] = {
			HasDevilFruitReward = true,
			Source = "standard_chest",
			FruitKey = openResult.GrantedFruit,
			DisplayName = displayName,
			Rarity = tostring(openResult.GrantedFruitRarity or rarityName or ""),
			WasDuplicate = openResult.WasDuplicate == true,
		}
	end

	for _, fruitEntry in ipairs(openResult.GrantedFruits or {}) do
		local fruitKey = tostring(fruitEntry.FruitKey or "")
		if fruitKey ~= "" then
			local displayName, rarityName = fruitDisplayName(fruitKey)
			contexts[#contexts + 1] = {
				HasDevilFruitReward = true,
				Source = "standard_chest",
				FruitKey = fruitKey,
				DisplayName = displayName,
				Rarity = tostring(fruitEntry.Rarity or rarityName or ""),
				WasDuplicate = false,
			}
		end
	end

	return contexts
end

local function getBestFruitAccentColor(contexts, fallbackColor)
	local bestRank = -1
	local bestColor = fallbackColor
	for _, context in ipairs(contexts or {}) do
		local rarity = tostring(context.Rarity or "")
		local rank = RARITY_RANK[rarity] or 0
		if rank > bestRank and RARITY_COLORS[rarity] then
			bestRank = rank
			bestColor = RARITY_COLORS[rarity]
		end
	end
	return bestColor or RARITY_COLORS.Reward
end

local function buildFruitRewardBody(contexts)
	local totalCount = #contexts
	if totalCount <= 0 then
		return ""
	end

	local duplicateCount = 0
	for _, context in ipairs(contexts) do
		if context.WasDuplicate == true then
			duplicateCount += 1
		end
	end

	if totalCount > 1 then
		local body = string.format("%s Devil Fruit drop%s from standard chests.", formatCount(totalCount), totalCount == 1 and "" or "s")
		if duplicateCount > 0 then
			body ..= string.format(" %s duplicate%s converted.", formatCount(duplicateCount), duplicateCount == 1 and "" or "s")
		end
		return body
	end

	local context = contexts[1]
	if context.WasDuplicate == true then
		return "A Devil Fruit dropped from this chest. Duplicate fruit rolled; conversion reward applied."
	end

	return "A Devil Fruit dropped from this chest."
end

local function buildChestInfoBanner(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}
	local pityStatus = buildFruitPityStatus(openResult)
	local pityTitle = getPityTitleText(pityStatus)
	local pityBody = if typeof(pityStatus) == "table" then tostring(pityStatus.progressText or "") else ""
	if pityBody == "" then
		return nil
	end

	local contexts = collectFruitRewardContexts(openResult)

	if #contexts <= 0 then
		return {
			titleText = pityTitle,
			bodyText = pityBody,
			activationTexts = if typeof(pityStatus.activationTexts) == "table" then pityStatus.activationTexts else {},
			progressText = pityBody,
			accentColor = pityStatus.accentColor or RARITY_COLORS.Reward,
		}
	end

	local titleText = pityTitle
	if titleText == "" then
		if #contexts > 1 then
			titleText = "DEVIL FRUIT DROPS"
		elseif contexts[1].WasDuplicate == true then
			titleText = "DEVIL FRUIT ROLLED"
		else
			titleText = "FRUIT OBTAINED"
		end
	end

	local bodyParts = {}
	local fruitBody = buildFruitRewardBody(contexts)
	if fruitBody ~= "" then
		bodyParts[#bodyParts + 1] = fruitBody
	end
	if pityBody ~= "" then
		bodyParts[#bodyParts + 1] = pityBody
	end
	local bodyText = table.concat(bodyParts, " ")

	return {
		titleText = titleText,
		bodyText = bodyText,
		activationTexts = if titleText ~= "" then { titleText } else {},
		progressText = bodyText,
		accentColor = if typeof(pityStatus) == "table" and pityTitle ~= ""
			then (pityStatus.accentColor or RARITY_COLORS.Reward)
			else getBestFruitAccentColor(contexts, if typeof(pityStatus) == "table" then pityStatus.accentColor else nil),
	}
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
		local fallbackName = tostring(((Economy.Food or {})[foodKey] or {}).DisplayName or foodKey)
		local displayName = ItemIconRegistry.GetDisplayName(foodKey, fallbackName)
		appendResultCard(cards, displayName, foodRewards[foodKey], getRewardIcon(foodKey))
	end

	local seenMaterials = {}
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
		seenMaterials[materialKey] = true
		local fallbackName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
		local displayName = ItemIconRegistry.GetDisplayName(materialKey, fallbackName)
		appendResultCard(cards, displayName, materialRewards[materialKey], getRewardIcon(materialKey))
	end

	for materialKey, amount in pairs(materialRewards) do
		if seenMaterials[materialKey] ~= true then
			local fallbackName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
			local displayName = ItemIconRegistry.GetDisplayName(materialKey, fallbackName)
			appendResultCard(cards, displayName, amount, getRewardIcon(materialKey))
		end
	end

	appendResultCard(cards, CurrencyUtil.getDisplayName(), getGrantedBeli(grantedResources), getRewardIcon("Beli"))
end

local function makeFeaturedReward(name, amount, icon, rarity, metadata)
	local normalizedAmount = math.max(1, tonumber(amount) or 1)
	local reward = {
		name = tostring(name or "Special Reward"),
		amount = normalizedAmount,
		amountText = "+" .. formatCount(normalizedAmount),
		icon = getRewardIcon(name, icon or getRewardIcon("DevilFruit")),
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
			featured = makeFeaturedReward(record.name, record.amount, getRewardIcon("DevilFruit"), record.rarity, metadata)
		else
			appendResultCard(cards, record.name, record.amount, getRewardIcon("DevilFruit"), record.rarity, metadata)
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
			getRewardIcon("MythicKey"),
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
		local fallbackName = tostring(((Economy.Food or {})[foodKey] or {}).DisplayName or foodKey)
		local displayName = ItemIconRegistry.GetDisplayName(foodKey, fallbackName)
		appendRewardRow(rows, displayName, foodRewards[foodKey], getRewardIcon(foodKey))
	end

	local seenMaterials = {}
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
		seenMaterials[materialKey] = true
		local fallbackName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
		local displayName = ItemIconRegistry.GetDisplayName(materialKey, fallbackName)
		appendRewardRow(rows, displayName, materialRewards[materialKey], getRewardIcon(materialKey))
	end

	for materialKey, amount in pairs(materialRewards) do
		if seenMaterials[materialKey] ~= true then
			local fallbackName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
			local displayName = ItemIconRegistry.GetDisplayName(materialKey, fallbackName)
			appendRewardRow(rows, displayName, amount, getRewardIcon(materialKey))
		end
	end

	appendRewardRow(rows, CurrencyUtil.getDisplayName(), getGrantedBeli(grantedResources), getRewardIcon("Beli"))
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
	local chestInfoBanner = buildChestInfoBanner(openResult)
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
		appendRewardRow(rewardRows, "Duplicate Refund - Mythic Key", mythicKeyCount, getRewardIcon("MythicKey"))
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
		ChestInfoBanner = chestInfoBanner,
		PityStatus = chestInfoBanner,
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
	local chestInfoBanner = buildChestInfoBanner(openResult)

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
		ChestInfoBanner = chestInfoBanner,
		PityStatus = chestInfoBanner,
	}
end

function ChestOpenResultFormatter.BuildResultsScreenModel(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}

	local openedCount = math.max(1, math.floor(tonumber(openResult.OpenedCount) or 1))
	local openedChest = if typeof(openResult.OpenedChest) == "table" then openResult.OpenedChest else {}
	local openedChestDisplayName = tostring(openedChest.displayName or "Chest")
	local displayChestName = pluralizeChestDisplay(openedChestDisplayName, openedCount)
	local rewardCards = {}
	local chestInfoBanner = buildChestInfoBanner(openResult)

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
		appendResultCard(rewardCards, CurrencyUtil.getDisplayName(), conversionBeli, getRewardIcon("Beli"), "Duplicate")

		local mythicKeyCount = math.max(0, tonumber(openResult.MythicKeyCount) or 0)
		appendResultCard(
			rewardCards,
			"Duplicate Refund - Mythic Key",
			mythicKeyCount,
			getRewardIcon("MythicKey"),
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
				getRewardIcon("Beli"),
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
		chestImage = resolveOpenedChestIcon(openedChest),
		chestVisualKey = nil,
		featuredReward = featuredReward,
		rewardCards = rewardCards,
		chestInfoBanner = chestInfoBanner,
		pityStatus = chestInfoBanner,
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
