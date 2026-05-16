local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ProfileTemplate = require(script.Parent:WaitForChild("ProfileTemplate"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local IndexDiscovery = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("IndexDiscovery"))
local VariantCfg = CrewCatalog.GetVariantConfig()

local ProfileMigrations = {}

local primaryCurrency = Economy.Currency.Primary

local function ensureTable(parent, key)
	if typeof(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

local function mergeDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if typeof(value) == "table" then
			if typeof(target[key]) ~= "table" then
				target[key] = {}
			end
			mergeDefaults(target[key], value)
		elseif target[key] == nil then
			target[key] = value
		end
	end
end

local function coerceNumber(value, fallback)
	if typeof(value) == "number" then
		return value
	end
	return fallback
end

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or "")
		if value ~= "" then
			return value
		end
	end
	return ""
end

local function coerceBoolean(value, fallback)
	if typeof(value) == "boolean" then
		return value
	end
	return fallback
end

local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName or "")

	for _, variantKey in ipairs(VariantCfg.Order or {}) do
		if variantKey ~= "Normal" then
			local variantData = (VariantCfg.Versions or {})[variantKey]
			local prefix = tostring((variantData and variantData.Prefix) or (variantKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				return variantKey, fullName:sub(#prefix + 1)
			end
		end
	end

	return "Normal", fullName
end

local function getVariantInfo(variantKey)
	if variantKey == "Normal" or not variantKey then
		return (VariantCfg.Versions or {}).Normal or { Prefix = "", IncomeMult = 1 }
	end

	return (VariantCfg.Versions or {})[variantKey]
end

local function getVariantItemId(variantKey, baseName)
	if typeof(baseName) ~= "string" or baseName == "" then
		return nil
	end

	if variantKey == "Normal" or not variantKey then
		return baseName
	end

	local variantInfo = getVariantInfo(variantKey)
	local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
	return prefix .. baseName
end

local function normalizeVariantKey(variantKey)
	local candidate = tostring(variantKey or "")
	for _, supportedVariant in ipairs(VariantCfg.Order or { "Normal", "Golden", "Diamond" }) do
		if candidate == supportedVariant then
			return supportedVariant
		end
	end

	return "Normal"
end

local function resolveCrewMemberItemId(storageName, baseName, variantKey)
	local storageNameValue = tostring(storageName or "")
	local baseNameValue = tostring(baseName or "")
	local normalizedVariant = normalizeVariantKey(variantKey)

	if baseNameValue == "" and storageNameValue ~= "" then
		local parsedVariant, parsedBaseName = getVariantAndBaseName(storageNameValue)
		normalizedVariant = normalizeVariantKey(parsedVariant)
		baseNameValue = parsedBaseName
	end

	if baseNameValue ~= "" then
		local itemId = getVariantItemId(normalizedVariant, baseNameValue)
		if itemId then
			local crewMemberId, info = CrewCatalog.ResolveCrewMemberId(itemId)
			if info then
				return crewMemberId
			end
		end
	end

	if storageNameValue ~= "" then
		local crewMemberId, info = CrewCatalog.ResolveCrewMemberId(storageNameValue)
		if info then
			return crewMemberId
		end
	end

	return nil
end

local function normalizeCrewMemberSourceInstance(instanceId, instanceData, fallbackStorageName)
	if typeof(instanceData) ~= "table" then
		instanceData = {}
	end

	local storageName = tostring(instanceData.CrewMemberId or instanceData.StorageName or fallbackStorageName or "")
	if storageName == "" then
		return nil
	end

	local variantKey = tostring(instanceData.Variant or "")
	local baseName = tostring(instanceData.BaseName or "")
	if baseName == "" then
		variantKey, baseName = getVariantAndBaseName(storageName)
	end
	if variantKey == "" then
		variantKey = "Normal"
	end

	return {
		InstanceId = tostring(instanceId),
		StorageName = storageName,
		BaseName = baseName,
		Variant = variantKey,
		Rarity = tostring(instanceData.Rarity or "Common"),
		Income = coerceNumber(instanceData.Income, 0),
		Render = tostring(instanceData.Render or ""),
		GoldenRender = tostring(instanceData.GoldenRender or instanceData.Render or ""),
		DiamondRender = tostring(instanceData.DiamondRender or instanceData.Render or ""),
		Level = math.max(1, coerceNumber(instanceData.Level, 1)),
		CurrentXP = math.max(0, coerceNumber(instanceData.CurrentXP, 0)),
		AssignedStand = tostring(instanceData.AssignedStand or ""),
		AcquiredAt = coerceNumber(instanceData.AcquiredAt, 0),
		LastReleasedAt = coerceNumber(instanceData.LastReleasedAt, 0),
		TutorialReward = instanceData.TutorialReward == true,
		TutorialToken = tostring(instanceData.TutorialToken or ""),
	}
end

local function resolveLegacyCrewStorageName(storageName, baseName, variantKey)
	local resolved = resolveCrewMemberItemId(storageName, baseName, variantKey)
	if resolved then
		return resolved
	end

	local info = CrewCatalog.GetInfoById(storageName)
	if info and tostring(info.LegacyId or "") ~= "" then
		return tostring(info.LegacyId)
	end

	if tostring(baseName or "") ~= "" then
		info = CrewCatalog.GetInfoById(baseName)
		if info and tostring(info.LegacyId or "") ~= "" then
			local resolvedFromBase = resolveCrewMemberItemId(info.LegacyId, info.LegacyId, variantKey)
			return resolvedFromBase or tostring(info.LegacyId)
		end
	end

	return tostring(storageName or "")
end

local function normalizeCrewMemberInstance(instanceId, instanceData, fallbackStorageName, projectionSource)
	if typeof(instanceData) ~= "table" then
		instanceData = {}
	end

	local rawStorageName = firstNonEmpty(
		instanceData.CrewMemberId,
		instanceData.StorageName,
		instanceData.Name,
		fallbackStorageName
	)
	local rawBaseName = tostring(instanceData.BaseName or rawStorageName)
	local rawVariant = tostring(instanceData.Variant or "")
	local crewMemberId, info, resolvedLegacyStorageName = CrewCatalog.ResolveCrewMemberId(rawStorageName)
	if not info and rawBaseName ~= rawStorageName then
		crewMemberId, info, resolvedLegacyStorageName = CrewCatalog.ResolveCrewMemberId(rawBaseName)
	end
	if crewMemberId == "" then
		return nil
	end
	local legacyStorageName = firstNonEmpty(instanceData.LegacyStorageName, resolvedLegacyStorageName)
	if legacyStorageName == "" and rawStorageName ~= crewMemberId then
		legacyStorageName = resolveLegacyCrewStorageName(rawStorageName, rawBaseName, rawVariant)
	end
	if legacyStorageName == crewMemberId then
		legacyStorageName = ""
	end
	local variantKey, baseName = getVariantAndBaseName(crewMemberId)

	local legacyInstance = normalizeCrewMemberSourceInstance(instanceId, {
		StorageName = crewMemberId,
		BaseName = baseName,
		Variant = variantKey,
		Rarity = info and info.Rarity or instanceData.Rarity,
		Income = info and info.Income or instanceData.Income,
		Render = info and info.Render or instanceData.Render,
		GoldenRender = info and info.GoldenRender or instanceData.GoldenRender,
		DiamondRender = info and info.DiamondRender or instanceData.DiamondRender,
		Level = instanceData.Level,
		CurrentXP = instanceData.CurrentXP,
		TotalXP = instanceData.TotalXP,
		AssignedStand = instanceData.AssignedStand,
		AcquiredAt = instanceData.AcquiredAt,
		LastReleasedAt = instanceData.LastReleasedAt,
		Source = instanceData.Source,
		DepthBand = instanceData.DepthBand,
		TutorialReward = instanceData.TutorialReward,
		TutorialToken = instanceData.TutorialToken,
		GrandLineRushStarter = instanceData.GrandLineRushStarter,
	}, crewMemberId)
	if not legacyInstance then
		return nil
	end

	local displayName = tostring(
		(info and (info.DisplayName or info.CrewMemberName or info.Name))
			or instanceData.DisplayName
			or legacyInstance.StorageName
	)

	return {
		InstanceId = legacyInstance.InstanceId,
		CrewMemberId = crewMemberId,
		DisplayName = displayName,
		LegacyStorageName = legacyStorageName,
		StorageName = crewMemberId,
		BaseName = legacyInstance.BaseName,
		Variant = legacyInstance.Variant,
		Rarity = legacyInstance.Rarity,
		Income = legacyInstance.Income,
		Render = legacyInstance.Render,
		GoldenRender = legacyInstance.GoldenRender,
		DiamondRender = legacyInstance.DiamondRender,
		ModelName = tostring(info and info.ModelName or instanceData.ModelName or legacyInstance.BaseName),
		Level = legacyInstance.Level,
		CurrentXP = legacyInstance.CurrentXP,
		TotalXP = math.max(0, coerceNumber(instanceData.TotalXP or legacyInstance.TotalXP, 0)),
		AssignedStand = legacyInstance.AssignedStand,
		AcquiredAt = legacyInstance.AcquiredAt,
		LastReleasedAt = legacyInstance.LastReleasedAt,
		Source = tostring(instanceData.Source or legacyInstance.Source or ""),
		DepthBand = tostring(instanceData.DepthBand or legacyInstance.DepthBand or ""),
		TutorialReward = legacyInstance.TutorialReward,
		TutorialToken = legacyInstance.TutorialToken,
		GrandLineRushStarter = instanceData.GrandLineRushStarter == true or legacyInstance.GrandLineRushStarter == true,
		ProjectionSource = tostring(instanceData.ProjectionSource or projectionSource or "ProfileMigrations"),
	}
end

local function ensureCrewMemberInventoryShape(crewMemberInventory)
	if typeof(crewMemberInventory) ~= "table" then
		crewMemberInventory = {}
	end

	crewMemberInventory.SchemaVersion = 1
	crewMemberInventory.NextInstanceId = math.max(1, coerceNumber(crewMemberInventory.NextInstanceId, 1))
	crewMemberInventory.ById = ensureTable(crewMemberInventory, "ById")
	crewMemberInventory.Order = ensureTable(crewMemberInventory, "Order")

	return crewMemberInventory
end

local function normalizeCrewMemberInventory(crewMemberInventory)
	crewMemberInventory = ensureCrewMemberInventoryShape(crewMemberInventory)

	local originalById = crewMemberInventory.ById
	local originalOrder = crewMemberInventory.Order
	local normalizedById = {}
	local normalizedOrder = {}
	local seenInstanceIds = {}
	local maxInstanceId = crewMemberInventory.NextInstanceId - 1

	local function appendInstance(rawInstanceId, instanceData, source)
		local instanceId = tostring(rawInstanceId or "")
		if instanceId == "" or seenInstanceIds[instanceId] then
			return
		end

		maxInstanceId = math.max(maxInstanceId, coerceNumber(tonumber(instanceId), 0))
		local normalized = normalizeCrewMemberInstance(instanceId, instanceData, nil, source)
		if normalized then
			normalizedById[instanceId] = normalized
			table.insert(normalizedOrder, instanceId)
			seenInstanceIds[instanceId] = true
		end
	end

	for _, rawInstanceId in ipairs(originalOrder) do
		local instanceId = tostring(rawInstanceId)
		appendInstance(instanceId, originalById[instanceId], "ProfileMigrations:CrewMemberInventory")
	end

	local unorderedIds = {}
	for rawInstanceId in pairs(originalById) do
		local instanceId = tostring(rawInstanceId)
		if not seenInstanceIds[instanceId] then
			table.insert(unorderedIds, instanceId)
		end
	end
	table.sort(unorderedIds, function(left, right)
		local leftNumber = tonumber(left)
		local rightNumber = tonumber(right)
		if leftNumber and rightNumber then
			return leftNumber < rightNumber
		end
		return left < right
	end)

	for _, instanceId in ipairs(unorderedIds) do
		appendInstance(instanceId, originalById[instanceId], "ProfileMigrations:CrewMemberInventoryUnordered")
	end

	crewMemberInventory.ById = normalizedById
	crewMemberInventory.Order = normalizedOrder
	if crewMemberInventory.NextInstanceId <= maxInstanceId then
		crewMemberInventory.NextInstanceId = maxInstanceId + 1
	end

	return #normalizedOrder
end

function ProfileMigrations.Apply(data)
	if typeof(data) ~= "table" then
		return
	end

	mergeDefaults(data, ProfileTemplate)

	local leaderstats = ensureTable(data, "leaderstats")
	local legacyMoney = coerceNumber(leaderstats[primaryCurrency.LegacyKeys.Leaderstat], 0)
	local typoMoney = coerceNumber(leaderstats[primaryCurrency.LegacyKeys.LeaderstatTypo], 0)
	local resolvedMoney = math.max(legacyMoney, typoMoney)

	leaderstats[primaryCurrency.Key] = coerceNumber(leaderstats[primaryCurrency.Key], resolvedMoney)
	leaderstats.Bounty = math.max(0, coerceNumber(leaderstats.Bounty, 0))
	leaderstats[primaryCurrency.LegacyKeys.Leaderstat] = nil
	leaderstats[primaryCurrency.LegacyKeys.LeaderstatTypo] = nil

	local totalStats = ensureTable(data, "TotalStats")
	local legacyTotal = coerceNumber(totalStats[primaryCurrency.LegacyKeys.Total], 0)
	totalStats[primaryCurrency.TotalKey] = coerceNumber(totalStats[primaryCurrency.TotalKey], legacyTotal)
	totalStats[primaryCurrency.LegacyKeys.Total] = nil

	local bounty = ensureTable(data, "Bounty")
	bounty.LifetimeExtraction = math.max(0, coerceNumber(bounty.LifetimeExtraction, 0))
	bounty.Crew = math.max(0, coerceNumber(bounty.Crew, 0))
	bounty.Total = math.max(0, coerceNumber(bounty.Total, leaderstats.Bounty))
	leaderstats.Bounty = math.max(leaderstats.Bounty, bounty.Total)

	local titles = ensureTable(data, "Titles")
	titles.Unlocked = ensureTable(titles, "Unlocked")
	if typeof(titles.Equipped) ~= "string" then
		titles.Equipped = ""
	end

	local devilFruit = ensureTable(data, "DevilFruit")
	if typeof(devilFruit.Equipped) ~= "string" then
		devilFruit.Equipped = ProfileTemplate.DevilFruit.Equipped
	end

	local indexCollection = ensureTable(data, "IndexCollection")
	indexCollection.Brainrots = nil
	local repairedCrewMembers = IndexDiscovery.CanonicalizeIndexCollectionMap(ensureTable(indexCollection, "CrewMembers"))
	indexCollection.CrewMembers = repairedCrewMembers
	local legacyDiscoveredDevilFruits = ensureTable(indexCollection, "DevilFruits")
	local discoveredDevilFruits = {}

	local function recordDevilFruitDiscovered(fruitIdentifier)
		local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
		if fruit then
			discoveredDevilFruits[fruit.FruitKey] = true
		end
	end

	local function recordDevilFruitTableCandidates(entry)
		recordDevilFruitDiscovered(entry.FruitKey)
		recordDevilFruitDiscovered(entry.Key)
		recordDevilFruitDiscovered(entry.Id)
		recordDevilFruitDiscovered(entry.Name)
		recordDevilFruitDiscovered(entry.DisplayName)
		recordDevilFruitDiscovered(entry.FruitName)

		for _, value in pairs(entry) do
			if typeof(value) == "string" then
				recordDevilFruitDiscovered(value)
			elseif typeof(value) == "table" then
				recordDevilFruitDiscovered(value.FruitKey)
				recordDevilFruitDiscovered(value.Key)
				recordDevilFruitDiscovered(value.Id)
				recordDevilFruitDiscovered(value.Name)
				recordDevilFruitDiscovered(value.DisplayName)
				recordDevilFruitDiscovered(value.FruitName)
			end
		end
	end

	local function isExplicitlyUndiscovered(entry)
		if entry == false then
			return true
		end

		if typeof(entry) ~= "table" then
			return false
		end

		return entry.Discovered == false or entry.Unlocked == false or entry.Collected == false or entry.Value == false
	end

	local function shouldRecordLifetimeDevilFruitEntry(entry)
		if isExplicitlyUndiscovered(entry) then
			return false
		end

		local entryType = typeof(entry)
		if entryType == "boolean" then
			return entry == true
		elseif entryType == "number" then
			return entry > 0
		elseif entryType == "string" then
			return entry ~= ""
		elseif entryType == "table" then
			return true
		end

		return false
	end

	local function recordDevilFruitEntryDiscovered(fruitIdentifier, entry, requireLifetimeMarker)
		if requireLifetimeMarker == true and not shouldRecordLifetimeDevilFruitEntry(entry) then
			return
		end

		recordDevilFruitDiscovered(fruitIdentifier)

		if typeof(entry) == "table" then
			recordDevilFruitTableCandidates(entry)
		elseif typeof(entry) == "string" then
			recordDevilFruitDiscovered(entry)
		end
	end

	for fruitIdentifier, entry in pairs(legacyDiscoveredDevilFruits) do
		recordDevilFruitEntryDiscovered(fruitIdentifier, entry, true)
	end

	local hiddenLeaderstats = ensureTable(data, "HiddenLeaderstats")
	local legacyHiddenLeadderstats = data.HiddenLeadderstats
	if typeof(legacyHiddenLeadderstats) == "table" then
		for key, value in pairs(legacyHiddenLeadderstats) do
			if hiddenLeaderstats[key] == nil then
				hiddenLeaderstats[key] = value
			end
		end

		hiddenLeaderstats.PlotUpgrade = math.min(
			PlotUpgradeConfig.MaxLevel,
			math.max(
				coerceNumber(hiddenLeaderstats.PlotUpgrade, 0),
				coerceNumber(legacyHiddenLeadderstats.PlotUpgrade, 0)
			)
		)
		data.HiddenLeadderstats = nil
	end

	hiddenLeaderstats.PlotUpgrade = math.clamp(coerceNumber(hiddenLeaderstats.PlotUpgrade, 0), 0, PlotUpgradeConfig.MaxLevel)
	hiddenLeaderstats.Tutorial = coerceBoolean(hiddenLeaderstats.Tutorial, false)
	hiddenLeaderstats.TutorialCrewMemberGranted = coerceBoolean(
		hiddenLeaderstats.TutorialCrewMemberGranted or hiddenLeaderstats.TutorialBrainrotGranted,
		false
	)
	hiddenLeaderstats.TutorialBrainrotGranted = nil
	hiddenLeaderstats.TutorialSpeedTopUpGranted = coerceBoolean(hiddenLeaderstats.TutorialSpeedTopUpGranted, false)
	hiddenLeaderstats.TutorialStarterDoubloonsGranted = coerceBoolean(hiddenLeaderstats.TutorialStarterDoubloonsGranted, false)
	if hiddenLeaderstats.Tutorial == true then
		hiddenLeaderstats.TutorialCrewMemberGranted = true
		hiddenLeaderstats.TutorialSpeedTopUpGranted = true
	elseif coerceNumber(hiddenLeaderstats.Speed, 1) <= 1 then
		hiddenLeaderstats.TutorialSpeedTopUpGranted = false
	end

	local tutorialStartAmount = coerceNumber(Economy.Tutorial and Economy.Tutorial.StartingDoubloons, 0)
	if hiddenLeaderstats.TutorialStarterDoubloonsGranted ~= true then
		if hiddenLeaderstats.Tutorial == true then
			hiddenLeaderstats.TutorialStarterDoubloonsGranted = true
		elseif tutorialStartAmount > 0 then
			local currentBalance = coerceNumber(leaderstats[primaryCurrency.Key], 0)
			local shortfall = math.max(0, tutorialStartAmount - currentBalance)
			if shortfall > 0 then
				leaderstats[primaryCurrency.Key] = currentBalance + shortfall
				totalStats[primaryCurrency.TotalKey] = coerceNumber(totalStats[primaryCurrency.TotalKey], 0) + shortfall
			end
			hiddenLeaderstats.TutorialStarterDoubloonsGranted = true
		end
	end

	local ship = ensureTable(data, "Ship")
	ship.MaxSlots = Economy.Rules.MaxShipSlots

	local chef = ensureTable(data, "Chef")
	local bank = ensureTable(chef, "Bank")
	bank.FoodXP = coerceNumber(bank.FoodXP, 0)
	bank.LastUpdatedAt = coerceNumber(bank.LastUpdatedAt, 0)
	bank.LastClaimedAt = coerceNumber(bank.LastClaimedAt, 0)
	bank.StoredFood = ensureTable(bank, "StoredFood")

	local crewMemberInventory = ensureCrewMemberInventoryShape(ensureTable(data, "CrewMemberInventory"))
	data.CrewInventory = nil
	data.BrainrotInventory = nil
	data.BrainrotQuickSlots = nil
	data.IncomeBrainrots = nil
	data.StandsLevels = nil

	local crewMemberQuickSlots = ensureTable(data, "CrewMemberQuickSlots")
	local canonicalUnlockedSlots = CrewQuickSlotConfig.ClampUnlockedSlots(crewMemberQuickSlots.UnlockedSlots)
	crewMemberQuickSlots.SchemaVersion = 1
	crewMemberQuickSlots.UnlockedSlots = canonicalUnlockedSlots
	crewMemberQuickSlots.MaxSlots = CrewQuickSlotConfig.MaxSlots

	local unopenedChests = ensureTable(data, "UnopenedChests")
	unopenedChests.NextChestId = math.max(1, coerceNumber(unopenedChests.NextChestId, 1))
	unopenedChests.ById = ensureTable(unopenedChests, "ById")
	unopenedChests.Order = ensureTable(unopenedChests, "Order")
	for chestId, chestEntry in pairs(unopenedChests.ById) do
		local safeChestEntry = if typeof(chestEntry) == "table" then chestEntry else {}
		local normalized = ChestUtils.BuildChestData(safeChestEntry)
		local normalizedChestId = tostring(chestId)
		normalized.ChestId = tostring(safeChestEntry.ChestId or normalizedChestId)
		normalized.DepthBand = tostring(safeChestEntry.DepthBand or "")
		normalized.CreatedAt = math.max(0, coerceNumber(safeChestEntry.CreatedAt, normalized.CreatedAt))

		if normalized.ChestKind == ChestRewards.ChestKinds.DevilFruit and normalized.FruitRarity == nil then
			normalized.Tier = ChestUtils.GetDefaultTierForDevilFruitChest(nil)
		end

		unopenedChests.ById[normalizedChestId] = normalized
	end

	local chestRewards = ensureTable(data, "ChestRewards")
	chestRewards.MythicKeys = math.max(0, coerceNumber(chestRewards.MythicKeys, 0))

	local foodInventory = ensureTable(data, "FoodInventory")
	local inventory = ensureTable(data, "Inventory")
	local legacyFeed = ensureTable(inventory, "Feed")
	local inventoryDevilFruits = ensureTable(inventory, "DevilFruits")
	for foodKey, defaultAmount in pairs(ProfileTemplate.FoodInventory) do
		local currentAmount = coerceNumber(foodInventory[foodKey], defaultAmount)
		local legacyAmount = coerceNumber(legacyFeed[foodKey], 0)
		foodInventory[foodKey] = math.max(currentAmount, legacyAmount)
	end

	for inventoryKey, inventoryEntry in pairs(inventory) do
		if inventoryKey ~= "Feed" and inventoryKey ~= "DevilFruits" and typeof(inventoryEntry) == "table" then
			local hasRetiredCrewFields = inventoryEntry.Quantity ~= nil
				or inventoryEntry.Rarity ~= nil
				or inventoryEntry.Level ~= nil
				or inventoryEntry.BaseName ~= nil
			if hasRetiredCrewFields then
				inventory[inventoryKey] = nil
			end
		end
	end

	for fruitKey, fruitEntry in pairs(inventoryDevilFruits) do
		recordDevilFruitEntryDiscovered(fruitKey, fruitEntry)
	end

	if typeof(devilFruit.Equipped) == "string" and devilFruit.Equipped ~= ProfileTemplate.DevilFruit.Equipped then
		recordDevilFruitDiscovered(devilFruit.Equipped)
	end
	indexCollection.DevilFruits = discoveredDevilFruits

	normalizeCrewMemberInventory(crewMemberInventory)

	local materials = ensureTable(data, "Materials")
	materials.Inventory = ensureTable(materials, "Inventory")
	materials.Timber = math.max(coerceNumber(materials.Timber, 0), coerceNumber(materials.CommonShipMaterial, 0))
	materials.Iron = math.max(coerceNumber(materials.Iron, 0), coerceNumber(materials.RareShipMaterial, 0))
	materials.AncientTimber = coerceNumber(materials.AncientTimber, 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron

	local quests = ensureTable(data, "Quests")
	for _, categoryId in ipairs({ "Daily", "Weekly", "Special" }) do
		local categoryState = ensureTable(quests, categoryId)
		categoryState.Progress = ensureTable(categoryState, "Progress")
		categoryState.Claimed = ensureTable(categoryState, "Claimed")
		if typeof(categoryState.CycleId) ~= "string" then
			categoryState.CycleId = if categoryId == "Special" then "Lifetime" else ""
		end
		if typeof(categoryState.ProfileBackfillApplied) ~= "boolean" then
			categoryState.ProfileBackfillApplied = false
		end

		for questId, value in pairs(categoryState.Progress) do
			categoryState.Progress[questId] = math.max(0, coerceNumber(value, 0))
		end
		for questId, value in pairs(categoryState.Claimed) do
			if value ~= true then
				categoryState.Claimed[questId] = nil
			end
		end
	end

	local active = ensureTable(data, "Active")
	active.x2Money = coerceNumber(active.x2Money, 1)
	active.x15WalkSpeed = coerceNumber(active.x15WalkSpeed, 1)

	local gamepasses = ensureTable(data, "Gamepasses")
	gamepasses.x2MoneyValue = coerceNumber(gamepasses.x2MoneyValue, 1)
end

return ProfileMigrations
