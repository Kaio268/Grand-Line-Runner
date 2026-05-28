local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(Modules:WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local IndexDiscovery = require(Modules:WaitForChild("Crew"):WaitForChild("IndexDiscovery"))
local CrewMembers = require(Modules:WaitForChild("Crew"):WaitForChild("CrewMembers"))
local CrewPreviewImages = require(Modules:WaitForChild("Crew"):WaitForChild("CrewPreviewImages"))
local CrewVariantConfig = CrewCatalog.GetVariantConfig()
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

local function getVariantInfo(variantKey)
	return (CrewVariantConfig.Versions or {})[variantKey]
		or (CrewVariantConfig.Versions or {}).Normal
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

local function getCrewInfo(itemId)
	return CrewCatalog.GetInfoById(itemId)
end

local function getIndexDisplayMetadata(metadataById, itemId)
	if typeof(metadataById) ~= "table" then
		return nil
	end

	local metadata = metadataById[tostring(itemId or "")]
	if typeof(metadata) == "table" then
		return metadata
	end

	return nil
end

local function readMetadataText(metadata, key)
	if typeof(metadata) ~= "table" then
		return nil
	end

	local value = metadata[key]
	if value == nil then
		return nil
	end

	local text = tostring(value)
	if text == "" then
		return nil
	end

	return text
end

local function getCanonicalIndexModelPreview(metadata)
	if typeof(metadata) ~= "table" or typeof(metadata.ModelPreview) ~= "table" then
		return nil
	end

	local descriptor = metadata.ModelPreview
	if descriptor.IsPreviewOnly ~= true or descriptor.UsedCanonical ~= true then
		return nil
	end

	local modelName = tostring(descriptor.ModelName or "")
	if modelName == "" then
		return nil
	end

	return descriptor
end

local function getCatalogCrewModelPreview(info)
	if type(info) ~= "table" then
		return nil
	end

	local modelName = tostring(info.ModelName or "")
	if modelName == "" then
		return nil
	end

	return {
		ModelName = modelName,
		IsPreviewOnly = true,
		UsedCanonical = true,
		Source = "CrewCatalog",
	}
end

local function getCrewRenderImage(render, renderStatus)
	if tostring(renderStatus or "") == "NeedsCanonicalPortrait" then
		return ""
	end

	return tostring(render or "")
end

local function markDiscoveredFruit(discovered, fruitIdentifier)
	local fruit = DevilFruits.GetFruit(fruitIdentifier)
	if fruit then
		discovered[fruit.FruitKey] = true
	end
end

local function mergeDiscoveredFruitsFromFolder(discovered, folder)
	if not folder then
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BoolValue") then
			if child.Value == true then
				markDiscoveredFruit(discovered, child.Name)
			end
		elseif child:IsA("StringValue") then
			markDiscoveredFruit(discovered, child.Value)
		elseif child:IsA("NumberValue") or child:IsA("IntValue") then
			if tonumber(child.Value) and child.Value > 0 then
				markDiscoveredFruit(discovered, child.Name)
			end
		elseif child:IsA("Folder") then
			markDiscoveredFruit(discovered, child.Name)
			markDiscoveredFruit(discovered, readStringField(child, "FruitKey"))
			markDiscoveredFruit(discovered, readStringField(child, "Name"))
			markDiscoveredFruit(discovered, readStringField(child, "DisplayName"))
		end
	end
end

local function buildDiscoveredCrewMemberSet(indexCollection, crewMemberInventory)
	return IndexDiscovery.BuildDiscoveredSetFromFolders(indexCollection, crewMemberInventory)
end

local function buildDiscoveredFruitSet(indexCollection, inventory, equippedFruitIdentifier)
	local discovered = {}
	local lifetimeFolder = indexCollection and indexCollection:FindFirstChild("DevilFruits")
	if lifetimeFolder then
		mergeDiscoveredFruitsFromFolder(discovered, lifetimeFolder)
	end

	-- Also merge live fruit ownership so recently claimed or equipped fruits reveal immediately.
	local devilFruitsFolder = inventory and inventory:FindFirstChild("DevilFruits")
	if devilFruitsFolder then
		for _, child in ipairs(devilFruitsFolder:GetChildren()) do
			markDiscoveredFruit(discovered, child.Name)
			markDiscoveredFruit(discovered, readStringField(child, "FruitKey"))
			markDiscoveredFruit(discovered, readStringField(child, "Name"))
			markDiscoveredFruit(discovered, readStringField(child, "DisplayName"))
		end
	end
	markDiscoveredFruit(discovered, equippedFruitIdentifier)

	return discovered
end

local function getSortedBaseEntries()
	local entries = {}

	for _, entry in ipairs(CrewMembers.GetEntries()) do
		if type(entry) == "table" then
			local crewMemberId = tostring(entry.CrewMemberId or "")
			local info = CrewCatalog.GetInfoById(crewMemberId) or entry
			entries[#entries + 1] = {
				name = crewMemberId,
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
local BELI_ICON = "rbxassetid://76300573750363"
local LUCK_BOOST_ICON = "rbxassetid://99305009492305"

local function formatBeliPerSecond(value)
	local numeric = math.max(0, math.floor((tonumber(value) or 0) + 0.5))
	return string.format("%s Beli/s", CurrencyUtil.formatCompactNumber(numeric))
end

local function formatIncomeRange(rarity, variantKey)
	local minIncome, maxIncome = CrewIncomeBalance.GetRangeDisplayIncome(rarity, variantKey)
	if minIncome == maxIncome then
		return formatBeliPerSecond(minIncome)
	end

	return string.format(
		"%s–%s Beli/s",
		CurrencyUtil.formatCompactNumber(minIncome),
		CurrencyUtil.formatCompactNumber(maxIncome)
	)
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
		return "Beli Boost"
	end
	if pathValue:find("x2MoneyTime", 1, true) then
		return "2x Beli"
	end
	if pathValue:find("WalkSpeed", 1, true) then
		return "Speed Boost"
	end

	local parts = string.split(pathValue, ".")
	local label = humanizeToken(parts[#parts] or pathValue)
	label = label:gsub("Money", "Beli")
	label = label:gsub("Income", "Beli")
	return label
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

	return CurrencyUtil.formatCount(numeric)
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
	local crewMemberInventory = options.crewMemberInventory
	local claimedRewardOverrides = options.claimedRewardOverrides
	local equippedDevilFruit = options.equippedDevilFruit
	local indexRewardsFolder = options.indexRewardsFolder
	local indexDisplayMetadata = options.indexDisplayMetadata
	local previewMode = options.previewMode == true

	local units = {}
	local unitsByCategory = {}
	local categoryProgress = {}
	local discoveredCrewMemberIds = buildDiscoveredCrewMemberSet(indexCollection, crewMemberInventory)
	local discoveredFruitKeys = buildDiscoveredFruitSet(indexCollection, inventory, equippedDevilFruit)
	local hasLiveCrewMemberState = indexCollection ~= nil or crewMemberInventory ~= nil
	local hasLiveFruitState = indexCollection ~= nil or inventory ~= nil or DevilFruits.GetFruit(equippedDevilFruit) ~= nil

	for _, template in pairs(CATEGORY_TEMPLATES) do
		unitsByCategory[template.id] = {}
		categoryProgress[template.id] = {
			total = 0,
			collected = 0,
		}
	end

	for orderIndex, entry in ipairs(SORTED_BASE_ENTRIES) do
		for _, variantKey in ipairs(CrewVariantConfig.Order or { "Normal", "Golden", "Diamond" }) do
			local template = CATEGORY_TEMPLATES[variantKey]
			if template then
				local itemId = getVariantItemId(variantKey, entry.name)
				local itemInfo = getCrewInfo(itemId) or entry.info
				local discovered = false

				if hasLiveCrewMemberState then
					discovered = discoveredCrewMemberIds[itemId] == true
				else
					discovered = isPreviewDiscovered(previewMode, template.id, orderIndex)
				end

				categoryProgress[template.id].total += 1
				if discovered then
					categoryProgress[template.id].collected += 1
				end

				local displayMetadata = getIndexDisplayMetadata(indexDisplayMetadata, itemId)
				local displayName = readMetadataText(displayMetadata, "DisplayName")
					or tostring(itemInfo.DisplayName or itemInfo.Name or entry.name)
				local rarity = readMetadataText(displayMetadata, "Rarity")
					or tostring(itemInfo.Rarity or entry.info.Rarity or "Common")
				local render = readMetadataText(displayMetadata, "Render")
					or tostring(itemInfo.Render or entry.info.Render or "")
				local renderStatus = readMetadataText(displayMetadata, "RenderStatus")
					or tostring(itemInfo.RenderStatus or entry.info.RenderStatus or "")
				local crewModelName = tostring(itemInfo.ModelName or entry.info.ModelName or "")
				local modelPreview = getCanonicalIndexModelPreview(displayMetadata)
					or getCatalogCrewModelPreview(itemInfo)
					or getCatalogCrewModelPreview(entry.info)
				local staticPreviewImage = CrewPreviewImages.Resolve({
					CrewMemberId = itemId,
					BaseCrewMemberId = entry.name,
					DisplayName = displayName,
					ModelPreview = modelPreview,
					Metadata = displayMetadata,
					RealCharacterName = itemInfo.RealCharacterName or entry.info.RealCharacterName,
					ModelName = itemInfo.ModelName or entry.info.ModelName,
				})

				local rawIncome = CrewIncomeBalance.GetBaseIncomeRangeMidpoint(rarity)
					* CrewIncomeBalance.GetVariantIncomeMultiplier(variantKey)
				local unit = {
					id = itemId,
					baseName = entry.name,
					name = entry.name,
					displayName = displayName,
					rarity = rarity,
					production = formatIncomeRange(rarity, variantKey),
					hiddenProduction = "??? Beli/s",
					rawIncome = rawIncome,
					discovered = discovered,
					image = if modelPreview then "" else getCrewRenderImage(render, renderStatus),
					staticPreviewImage = staticPreviewImage,
					previewKind = if modelPreview then "CrewMember" else nil,
					previewName = if modelPreview then tostring(modelPreview.ModelName or "") else nil,
					crewModelName = if crewModelName ~= "" then crewModelName else nil,
					previewCrewMemberId = if modelPreview then itemId else nil,
					category = template.id,
					categoryLabel = template.label,
					canonicalDisplayUsed = displayMetadata and displayMetadata.CanonicalDisplayUsed == true,
					canonicalModelPreviewUsed = modelPreview ~= nil,
					displayFallbackReason = displayMetadata and displayMetadata.FallbackReason or nil,
					modelPreviewFallbackReason = displayMetadata
						and typeof(displayMetadata.ModelPreview) == "table"
						and displayMetadata.ModelPreview.FallbackReason
						or nil,
					displayMetadataSource = displayMetadata and displayMetadata.Source or "CrewCatalog",
					themeKey = template.themeKey,
					order = orderIndex,
				}
				units[#units + 1] = unit
				unitsByCategory[template.id][#unitsByCategory[template.id] + 1] = unit
			end
		end
	end

	local categories = {}
	local collectedTotal = 0
	local totalCount = 0

	for _, variantKey in ipairs(CrewVariantConfig.Order or { "Normal", "Golden", "Diamond" }) do
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
			local pathText = tostring(path or "")
			local rewardIcon = reward and reward.Icon or ""
			if pathText:find("MoneyMult", 1, true) then
				rewardIcon = LUCK_BOOST_ICON
			elseif pathText:find("Doubloons", 1, true) then
				rewardIcon = BELI_ICON
			end

			rewardItems[#rewardItems + 1] = {
				id = tostring(path),
				icon = rewardIcon,
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
		unitsByCategory = unitsByCategory,
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

