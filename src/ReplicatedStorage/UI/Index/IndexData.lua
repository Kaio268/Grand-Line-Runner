local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")
local Brainrots = require(Configs:WaitForChild("Brainrots"))
local BrainrotVariants = require(Configs:WaitForChild("BrainrotVariants"))
local DevilFruits = require(Configs:WaitForChild("DevilFruits"))
local IndexConfig = require(Configs:WaitForChild("Index"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local Shorten = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Shorten"))
local Theme = require(script.Parent:WaitForChild("Theme"))

local IndexData = {}

local CATEGORY_TEMPLATES = {
	Normal = {
		id = "normal",
		label = "Normal",
		eyebrow = "Base Units",
		iconText = "N",
		themeKey = "Slate",
		fillColor = Color3.fromRGB(186, 205, 255),
	},
	Golden = {
		id = "golden",
		label = "Golden",
		eyebrow = "Shiny Variant",
		iconText = "G",
		themeKey = "Gold",
		fillColor = Color3.fromRGB(255, 198, 85),
	},
	Diamond = {
		id = "diamond",
		label = "Diamond",
		eyebrow = "Rare Variant",
		iconText = "D",
		themeKey = "Cyan",
		fillColor = Color3.fromRGB(119, 230, 255),
	},
}

IndexData.Tabs = {
	{ id = "index", label = "Index", eyebrow = "Collection" },
	{ id = "fruits", label = "Fruits", eyebrow = "Devil Fruits" },
	{ id = "rewards", label = "Rewards", eyebrow = "Milestones" },
}

IndexData.RarityConfig = Theme.RarityStyles

local RARITY_SORT_ORDER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Godly = 7,
	Secret = 8,
	Omega = 9,
}

local VALID_BRAINROT_ITEM_IDS = {}

for itemId, info in pairs(Brainrots) do
	if type(info) == "table" then
		VALID_BRAINROT_ITEM_IDS[tostring(itemId)] = true
	end
end

local function getVariantInfo(variantKey)
	return (BrainrotVariants.Versions or {})[variantKey]
		or (BrainrotVariants.Versions or {}).Normal
		or { Prefix = "", IncomeMult = 1 }
end

local function getVariantItemId(variantKey, baseName)
	if variantKey == "Normal" then
		return baseName
	end

	local variantInfo = getVariantInfo(variantKey)
	local prefix = tostring(variantInfo.Prefix or (variantKey .. " "))
	return prefix .. baseName
end

local function readStringValue(container, childName)
	if not container then
		return nil
	end

	local child = container:FindFirstChild(childName)
	if child and child:IsA("StringValue") then
		local value = tostring(child.Value or "")
		if value ~= "" then
			return value
		end
	end

	return nil
end

local function readStringField(container, childName)
	local value = readStringValue(container, childName)
	if value ~= nil then
		return value
	end

	if not container then
		return nil
	end

	local attributeValue = container:GetAttribute(childName)
	if attributeValue == nil then
		return nil
	end

	local text = tostring(attributeValue)
	if text == "" then
		return nil
	end

	return text
end

local function normalizeVariantKey(variantKey)
	local candidate = tostring(variantKey or "")
	for _, supportedVariant in ipairs(BrainrotVariants.Order or { "Normal", "Golden", "Diamond" }) do
		if candidate == supportedVariant then
			return supportedVariant
		end
	end

	return "Normal"
end

local function parseVariantAndBaseName(fullName)
	local value = tostring(fullName or "")
	if value == "" then
		return "Normal", ""
	end

	for _, variantKey in ipairs(BrainrotVariants.Order or { "Normal", "Golden", "Diamond" }) do
		if variantKey ~= "Normal" then
			local variantInfo = getVariantInfo(variantKey)
			local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
			if value:sub(1, #prefix) == prefix then
				return variantKey, value:sub(#prefix + 1)
			end
		end
	end

	return "Normal", value
end

local function resolveBrainrotItemId(storageName, baseName, variantKey)
	local storageNameValue = tostring(storageName or "")
	local baseNameValue = tostring(baseName or "")
	local normalizedVariant = normalizeVariantKey(variantKey)
	if baseNameValue == "" and storageNameValue ~= "" then
		local parsedVariant, parsedBaseName = parseVariantAndBaseName(storageNameValue)
		normalizedVariant = normalizeVariantKey(parsedVariant)
		baseNameValue = parsedBaseName
	end

	if baseNameValue == "" then
		return nil
	end

	local itemId = getVariantItemId(normalizedVariant, baseNameValue)
	if itemId and VALID_BRAINROT_ITEM_IDS[itemId] then
		return itemId
	end

	if storageNameValue ~= "" and VALID_BRAINROT_ITEM_IDS[storageNameValue] then
		return storageNameValue
	end

	return nil
end

local function markDiscoveredBrainrot(discovered, storageName, baseName, variantKey)
	local itemId = resolveBrainrotItemId(storageName, baseName, variantKey)
	if itemId then
		discovered[itemId] = true
	end
end

local function mergeDiscoveredFromBoolFolder(discovered, folder)
	if not folder then
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BoolValue") and child.Value == true then
			discovered[tostring(child.Name)] = true
		end
	end
end

local function buildDiscoveredBrainrotSet(indexCollection, inventory, brainrotInventory)
	local discovered = {}
	mergeDiscoveredFromBoolFolder(discovered, indexCollection and indexCollection:FindFirstChild("Brainrots"))

	local byIdFolder = brainrotInventory and brainrotInventory:FindFirstChild("ById")
	if byIdFolder then
		for _, child in ipairs(byIdFolder:GetChildren()) do
			if child:IsA("Folder") then
				markDiscoveredBrainrot(
					discovered,
					readStringField(child, "StorageName"),
					readStringField(child, "BaseName"),
					readStringField(child, "Variant")
				)
			end
		end
	end

	if inventory then
		for _, child in ipairs(inventory:GetChildren()) do
			if child:IsA("Folder") and child.Name ~= "DevilFruits" then
				markDiscoveredBrainrot(
					discovered,
					child.Name,
					readStringField(child, "BaseName"),
					readStringField(child, "Variant")
				)
			end
		end
	end

	return discovered
end

local function buildDiscoveredFruitSet(indexCollection, inventory, equippedFruitIdentifier)
	local discovered = {}
	mergeDiscoveredFromBoolFolder(discovered, indexCollection and indexCollection:FindFirstChild("DevilFruits"))
	local devilFruitsFolder = inventory and inventory:FindFirstChild("DevilFruits")
	if devilFruitsFolder then
		for _, child in ipairs(devilFruitsFolder:GetChildren()) do
			if child:IsA("Folder") then
				local identifier = readStringField(child, "FruitKey") or child.Name
				local fruit = DevilFruits.GetFruit(identifier)
				if fruit then
					discovered[fruit.FruitKey] = true
				end
			end
		end
	end

	local equippedFruit = DevilFruits.GetFruit(equippedFruitIdentifier)
	if equippedFruit then
		discovered[equippedFruit.FruitKey] = true
	end

	return discovered
end

local function getSortedBaseEntries()
	local entries = {}

	for name, info in pairs(Brainrots) do
		if type(info) == "table" and not info.IsVariant and not info.Variant then
			entries[#entries + 1] = {
				name = name,
				info = info,
			}
		end
	end

	table.sort(entries, function(a, b)
		local aChance = tonumber(a.info.Chance) or 0
		local bChance = tonumber(b.info.Chance) or 0
		if aChance ~= bChance then
			return aChance > bChance
		end

		local aIncome = tonumber(a.info.Income) or 0
		local bIncome = tonumber(b.info.Income) or 0
		if aIncome ~= bIncome then
			return aIncome < bIncome
		end

		return tostring(a.name) < tostring(b.name)
	end)

	return entries
end

local SORTED_BASE_ENTRIES = getSortedBaseEntries()

local function getSortedFruits()
	local fruits = DevilFruits.GetAllFruits()

	table.sort(fruits, function(a, b)
		local aRank = RARITY_SORT_ORDER[tostring(a.Rarity)] or 0
		local bRank = RARITY_SORT_ORDER[tostring(b.Rarity)] or 0
		if aRank ~= bRank then
			return aRank > bRank
		end

		return tostring(a.DisplayName) < tostring(b.DisplayName)
	end)

	return fruits
end

local SORTED_FRUITS = getSortedFruits()

local function formatIncome(value)
	local numeric = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	return Shorten.withCommas(numeric) .. CurrencyUtil.getPerSecondSuffix()
end

local function isClaimed(indexRewardsFolder, threshold, claimedRewardOverrides)
	if claimedRewardOverrides and claimedRewardOverrides[tostring(threshold)] == true then
		return true
	end

	if not indexRewardsFolder or indexRewardsFolder.Parent == nil then
		return false
	end

	local value = indexRewardsFolder:FindFirstChild(tostring(threshold))
	return value ~= nil and value:IsA("BoolValue") and value.Value == true
end

local function humanizeToken(token)
	local value = tostring(token or "")
	value = value:gsub("(%l)(%u)", "%1 %2")
	value = value:gsub("(%a)(%d)", "%1 %2")
	value = value:gsub("(%d)(%a)", "%1 %2")
	value = value:gsub("_", " ")
	return value
end

local function formatRewardLabel(path)
	local pathValue = tostring(path or "")
	if pathValue:find("MoneyMult", 1, true) then
		return "Ship Income"
	end
	if pathValue:find("x2MoneyTime", 1, true) then
		return "x2 Money"
	end
	if pathValue:find("WalkSpeed", 1, true) then
		return "Speed Boost"
	end

	local parts = string.split(pathValue, ".")
	return humanizeToken(parts[#parts] or pathValue)
end

local function formatRewardAmount(path, amount)
	local numeric = tonumber(amount)
	if numeric == nil then
		return tostring(amount or "")
	end

	if tostring(path or ""):find("Mult", 1, true) then
		return ("+%d%%"):format(math.floor((numeric * 100) + 0.5))
	end

	if tostring(path or ""):find("Time", 1, true) then
		return Shorten.timeSuffix3(math.floor(numeric + 0.5))
	end

	return Shorten.withCommas(math.floor(numeric + 0.5))
end

local function isPreviewDiscovered(previewMode, categoryId, orderIndex)
	if previewMode ~= true then
		return false
	end

	if categoryId == "normal" then
		return orderIndex <= 10
	end

	return orderIndex <= 4
end

local function isPreviewFruitDiscovered(previewMode, orderIndex)
	return previewMode == true and orderIndex <= 2
end

function IndexData.buildViewModel(options)
	options = options or {}

	local inventory = options.inventory
	local indexCollection = options.indexCollection
	local brainrotInventory = options.brainrotInventory
	local claimedRewardOverrides = options.claimedRewardOverrides
	local equippedDevilFruit = options.equippedDevilFruit
	local indexRewardsFolder = options.indexRewardsFolder
	local previewMode = options.previewMode == true

	local units = {}
	local categoryProgress = {}
	local discoveredBrainrotIds = buildDiscoveredBrainrotSet(indexCollection, inventory, brainrotInventory)
	local discoveredFruitKeys = buildDiscoveredFruitSet(indexCollection, inventory, equippedDevilFruit)
	local hasLiveBrainrotState = indexCollection ~= nil or inventory ~= nil or brainrotInventory ~= nil
	local hasLiveFruitState = indexCollection ~= nil or inventory ~= nil or DevilFruits.GetFruit(equippedDevilFruit) ~= nil

	for _, template in pairs(CATEGORY_TEMPLATES) do
		categoryProgress[template.id] = {
			total = 0,
			collected = 0,
		}
	end

	for orderIndex, entry in ipairs(SORTED_BASE_ENTRIES) do
		for _, variantKey in ipairs(BrainrotVariants.Order or { "Normal", "Golden", "Diamond" }) do
			local template = CATEGORY_TEMPLATES[variantKey]
			if template then
				local itemId = getVariantItemId(variantKey, entry.name)
				local itemInfo = Brainrots[itemId] or entry.info
				local discovered = false

				if hasLiveBrainrotState then
					discovered = discoveredBrainrotIds[itemId] == true
				else
					discovered = isPreviewDiscovered(previewMode, template.id, orderIndex)
				end

				categoryProgress[template.id].total += 1
				if discovered then
					categoryProgress[template.id].collected += 1
				end

				units[#units + 1] = {
					id = itemId,
					baseName = entry.name,
					name = entry.name,
					displayName = entry.name,
					rarity = tostring(itemInfo.Rarity or entry.info.Rarity or "Common"),
					production = formatIncome(itemInfo.Income or entry.info.Income or 0),
					rawIncome = tonumber(itemInfo.Income or entry.info.Income) or 0,
					discovered = discovered,
					image = tostring(itemInfo.Render or entry.info.Render or ""),
					category = template.id,
					categoryLabel = template.label,
					themeKey = template.themeKey,
					order = orderIndex,
				}
			end
		end
	end

	local categories = {}
	local collectedTotal = 0
	local totalCount = 0

	for _, variantKey in ipairs(BrainrotVariants.Order or { "Normal", "Golden", "Diamond" }) do
		local template = CATEGORY_TEMPLATES[variantKey]
		if template then
			local progress = categoryProgress[template.id]
			collectedTotal += progress.collected
			totalCount += progress.total

			categories[#categories + 1] = {
				id = template.id,
				label = template.label,
				eyebrow = template.eyebrow,
				iconText = template.iconText,
				fillColor = template.fillColor,
				themeKey = template.themeKey,
				collected = progress.collected,
				total = progress.total,
			}
		end
	end

	local rewardThresholds = {}
	for threshold in pairs(IndexConfig) do
		if typeof(threshold) == "number" then
			rewardThresholds[#rewardThresholds + 1] = threshold
		end
	end
	table.sort(rewardThresholds)

	local rewards = {}
	local claimableCount = 0

	for _, threshold in ipairs(rewardThresholds) do
		local config = IndexConfig[threshold]
		local claimed = isClaimed(indexRewardsFolder, threshold, claimedRewardOverrides)
		local claimable = (not claimed) and collectedTotal >= threshold
		if claimable then
			claimableCount += 1
		end

		local rewardItems = {}
		for path, reward in pairs((config and config.Rewards) or {}) do
			rewardItems[#rewardItems + 1] = {
				id = tostring(path),
				icon = reward and reward.Icon or "",
				label = formatRewardLabel(path),
				amount = formatRewardAmount(path, reward and reward.Amount),
			}
		end

		table.sort(rewardItems, function(a, b)
			return tostring(a.id) < tostring(b.id)
		end)

		rewards[#rewards + 1] = {
			id = threshold,
			threshold = threshold,
			icon = config and config.Icon or "",
			accentColor = config and config.BgColor or Color3.fromRGB(255, 162, 83),
			claimed = claimed,
			claimable = claimable,
			remaining = math.max(0, threshold - collectedTotal),
			rewards = rewardItems,
		}
	end

	local devilFruitUnits = {}
	local devilFruitCollected = 0
	local devilFruitTotal = 0

	for fruitIndex, fruit in ipairs(SORTED_FRUITS) do
		local discovered = false
		if hasLiveFruitState then
			discovered = discoveredFruitKeys[fruit.FruitKey] == true
		else
			discovered = isPreviewFruitDiscovered(previewMode, fruitIndex)
		end

		devilFruitTotal += 1
		if discovered then
			devilFruitCollected += 1
		end

		devilFruitUnits[#devilFruitUnits + 1] = {
			id = "DevilFruit:" .. tostring(fruit.FruitKey),
			itemKind = "DevilFruit",
			name = fruit.FruitKey,
			displayName = tostring(fruit.DisplayName or fruit.FruitKey or "Devil Fruit"),
			rarity = tostring(fruit.Rarity or "Rare"),
			discovered = discovered,
			category = "fruits",
			categoryLabel = "Devil Fruits",
			previewKind = "DevilFruit",
			previewName = fruit.FruitKey,
			themeKey = "Rose",
		}
	end

	return {
		tabs = IndexData.Tabs,
		categories = categories,
		units = units,
		collectionStats = {
			collected = collectedTotal,
			total = totalCount,
			claimableCount = claimableCount,
		},
		devilFruitCollection = {
			label = "Devil Fruits",
			units = devilFruitUnits,
			collectionStats = {
				collected = devilFruitCollected,
				total = devilFruitTotal,
			},
		},
		rewards = rewards,
		claimableCount = claimableCount,
	}
end

function IndexData.getDefaultViewModel()
	return IndexData.buildViewModel({
		previewMode = true,
	})
end

return IndexData
