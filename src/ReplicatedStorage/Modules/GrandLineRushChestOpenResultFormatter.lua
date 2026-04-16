local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local DevilFruits = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))

local ChestOpenResultFormatter = {}

local FOOD_ORDER = { "Apple", "Rice", "Meat", "SeaBeastMeat" }
local RARITY_COLORS = {
	Common = Color3.fromRGB(201, 206, 215),
	Rare = Color3.fromRGB(98, 184, 255),
	Legendary = Color3.fromRGB(255, 197, 94),
	Mythic = Color3.fromRGB(118, 244, 214),
	DevilFruit = Color3.fromRGB(116, 245, 183),
	Reward = Color3.fromRGB(116, 245, 183),
	Duplicate = Color3.fromRGB(255, 179, 92),
}

local function appendLine(lines, text)
	if typeof(text) ~= "string" or text == "" then
		return
	end

	lines[#lines + 1] = text
end

local function fruitDisplayName(fruitKey)
	local fruit = DevilFruits.GetFruit(fruitKey)
	if fruit and fruit.DisplayName then
		return tostring(fruit.DisplayName), tostring(fruit.Rarity or "")
	end

	return tostring(fruitKey or "Unknown Devil Fruit"), ""
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
			appendLine(lines, string.format("+%d %s", amount, displayName))
			addedAny = true
		end
	end

	local seenMaterials = {}
	for _, materialKey in ipairs(PlotUpgradeConfig.MaterialOrder or {}) do
		seenMaterials[materialKey] = true
		local amount = math.max(0, tonumber(materialRewards[materialKey]) or 0)
		if amount > 0 then
			local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
			appendLine(lines, string.format("+%d %s", amount, displayName))
			addedAny = true
		end
	end

	for materialKey, amountValue in pairs(materialRewards) do
		if seenMaterials[materialKey] ~= true then
			local amount = math.max(0, tonumber(amountValue) or 0)
			if amount > 0 then
				local displayName = tostring((PlotUpgradeConfig.MaterialDisplayNames or {})[materialKey] or materialKey)
				appendLine(lines, string.format("+%d %s", amount, displayName))
				addedAny = true
			end
		end
	end

	local doubloons = math.max(0, tonumber(grantedResources.doubloons) or 0)
	if doubloons > 0 then
		appendLine(lines, string.format("+%d Doubloons", doubloons))
		addedAny = true
	end

	return addedAny
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

function ChestOpenResultFormatter.BuildAcknowledgementOptions(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}

	local accentText, accentColor = resolveAccent(openResult)
	local lines = {}
	local hadResources = addGrantedResourceLines(lines, openResult.GrantedResources)

	if openResult.GrantedFruit then
		local displayName, rarityName = fruitDisplayName(openResult.GrantedFruit)
		if hadResources then
			appendLine(lines, "")
		end
		appendLine(lines, "Fruit obtained:")
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
			appendLine(lines, string.format("Reward: +%d %s", amount, tostring(openResult.ConversionRewardDisplayName or "Mythic Key")))
			local progress = openResult.MythicKeyProgress or {}
			appendLine(
				lines,
				string.format(
					"Progress: %d/%d",
					math.max(0, tonumber(progress.current) or 0),
					math.max(0, tonumber(progress.threshold) or 0)
				)
			)
			if openResult.AutoConvertedMythicChest == true and typeof(openResult.GrantedChest) == "table" then
				appendLine(lines, string.format("Auto-converted: %s", tostring(openResult.GrantedChest.displayName or "Mythic Devil Fruit Chest")))
			end
		elseif openResult.ConversionRewardType == "Doubloons" then
			appendLine(
				lines,
				string.format(
					"Converted to: +%d %s",
					math.max(0, tonumber(openResult.ConversionRewardAmount) or 0),
					tostring(openResult.ConversionRewardDisplayName or "Doubloons")
				)
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
		Lines = lines,
	}
end

function ChestOpenResultFormatter.GetCelebrationCount(openResult)
	openResult = if typeof(openResult) == "table" then openResult else {}

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
