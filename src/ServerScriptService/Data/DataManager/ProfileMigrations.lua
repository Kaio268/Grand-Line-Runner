local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ProfileTemplate = require(script.Parent:WaitForChild("ProfileTemplate"))
local VariantCfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))

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

local function isBrainrotInventoryEntry(key, entry)
	if key == "Feed" or key == "DevilFruits" then
		return false
	end
	if typeof(entry) ~= "table" then
		return false
	end
	return entry.Quantity ~= nil
		or entry.BaseName ~= nil
		or entry.Variant ~= nil
		or entry.Rarity ~= nil
		or entry.Level ~= nil
		or entry.CurrentXP ~= nil
end

local function normalizeBrainrotInstance(instanceId, instanceData, fallbackStorageName)
	if typeof(instanceData) ~= "table" then
		instanceData = {}
	end

	local storageName = tostring(instanceData.StorageName or fallbackStorageName or instanceData.BrainrotName or "")
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
	}
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

	local devilFruit = ensureTable(data, "DevilFruit")
	if typeof(devilFruit.Equipped) ~= "string" then
		devilFruit.Equipped = ProfileTemplate.DevilFruit.Equipped
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
	hiddenLeaderstats.TutorialStarterDoubloonsGranted = coerceBoolean(hiddenLeaderstats.TutorialStarterDoubloonsGranted, false)

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

	local crewInventory = ensureTable(data, "CrewInventory")
	crewInventory.NextInstanceId = math.max(1, coerceNumber(crewInventory.NextInstanceId, 1))
	crewInventory.ById = ensureTable(crewInventory, "ById")
	crewInventory.Order = ensureTable(crewInventory, "Order")

	local brainrotInventory = ensureTable(data, "BrainrotInventory")
	brainrotInventory.NextInstanceId = math.max(1, coerceNumber(brainrotInventory.NextInstanceId, 1))
	brainrotInventory.ById = ensureTable(brainrotInventory, "ById")
	brainrotInventory.Order = ensureTable(brainrotInventory, "Order")

	local unopenedChests = ensureTable(data, "UnopenedChests")
	unopenedChests.NextChestId = math.max(1, coerceNumber(unopenedChests.NextChestId, 1))
	unopenedChests.ById = ensureTable(unopenedChests, "ById")
	unopenedChests.Order = ensureTable(unopenedChests, "Order")

	local foodInventory = ensureTable(data, "FoodInventory")
	local inventory = ensureTable(data, "Inventory")
	local legacyFeed = ensureTable(inventory, "Feed")
	for foodKey, defaultAmount in pairs(ProfileTemplate.FoodInventory) do
		local currentAmount = coerceNumber(foodInventory[foodKey], defaultAmount)
		local legacyAmount = coerceNumber(legacyFeed[foodKey], 0)
		foodInventory[foodKey] = math.max(currentAmount, legacyAmount)
	end

	for inventoryKey, inventoryEntry in pairs(inventory) do
		if inventoryKey ~= "Feed" and inventoryKey ~= "DevilFruits" and typeof(inventoryEntry) == "table" then
			local hasBrainrotFields = inventoryEntry.Quantity ~= nil
				or inventoryEntry.Rarity ~= nil
				or inventoryEntry.Level ~= nil
				or inventoryEntry.BaseName ~= nil
			if hasBrainrotFields then
				inventoryEntry.Level = math.max(1, coerceNumber(inventoryEntry.Level, 1))
				inventoryEntry.CurrentXP = math.max(0, coerceNumber(inventoryEntry.CurrentXP, 0))
			end
		end
	end

	local incomeBrainrots = ensureTable(data, "IncomeBrainrots")
	for standName, standData in pairs(incomeBrainrots) do
		if typeof(standData) == "table" then
			if typeof(standData.BrainrotName) ~= "string" then
				standData.BrainrotName = ""
			end
			if typeof(standData.BrainrotInstanceId) ~= "string" then
				standData.BrainrotInstanceId = ""
			end
			if typeof(standData.IncomeToCollect) ~= "number" then
				standData.IncomeToCollect = 0
			end
			incomeBrainrots[standName] = standData
		end
	end

	local normalizedOrder = {}
	local seenInstanceIds = {}
	local maxBrainrotInstanceId = brainrotInventory.NextInstanceId - 1
	for _, rawInstanceId in ipairs(brainrotInventory.Order) do
		local instanceId = tostring(rawInstanceId)
		maxBrainrotInstanceId = math.max(maxBrainrotInstanceId, coerceNumber(tonumber(instanceId), 0))
		local normalized = normalizeBrainrotInstance(instanceId, brainrotInventory.ById[instanceId])
		if normalized and not seenInstanceIds[instanceId] then
			brainrotInventory.ById[instanceId] = normalized
			table.insert(normalizedOrder, instanceId)
			seenInstanceIds[instanceId] = true
		else
			brainrotInventory.ById[instanceId] = nil
		end
	end

	for rawInstanceId, instanceData in pairs(brainrotInventory.ById) do
		local instanceId = tostring(rawInstanceId)
		maxBrainrotInstanceId = math.max(maxBrainrotInstanceId, coerceNumber(tonumber(instanceId), 0))
		if not seenInstanceIds[instanceId] then
			local normalized = normalizeBrainrotInstance(instanceId, instanceData)
			if normalized then
				brainrotInventory.ById[instanceId] = normalized
				table.insert(normalizedOrder, instanceId)
				seenInstanceIds[instanceId] = true
			else
				brainrotInventory.ById[instanceId] = nil
			end
		end
	end
	brainrotInventory.Order = normalizedOrder
	if brainrotInventory.NextInstanceId <= maxBrainrotInstanceId then
		brainrotInventory.NextInstanceId = maxBrainrotInstanceId + 1
	end

	local function createBrainrotInstance(storageName, entry, assignedStand)
		local instanceId = tostring(brainrotInventory.NextInstanceId)
		brainrotInventory.NextInstanceId += 1

		local normalized = normalizeBrainrotInstance(instanceId, {
			StorageName = storageName,
			BaseName = entry and entry.BaseName or nil,
			Variant = entry and entry.Variant or nil,
			Rarity = entry and entry.Rarity or nil,
			Income = entry and entry.Income or nil,
			Render = entry and entry.Render or nil,
			GoldenRender = entry and entry.GoldenRender or nil,
			DiamondRender = entry and entry.DiamondRender or nil,
			Level = entry and entry.Level or 1,
			CurrentXP = entry and entry.CurrentXP or 0,
			AssignedStand = assignedStand or "",
		}, storageName)

		brainrotInventory.ById[instanceId] = normalized
		table.insert(brainrotInventory.Order, instanceId)
		return instanceId
	end

	if #brainrotInventory.Order == 0 then
		local placedByStorage = {}
		local standNamesByStorage = {}
		for standName, standData in pairs(incomeBrainrots) do
			local storageName = tostring(standData.BrainrotName or "")
			if storageName ~= "" then
				placedByStorage[storageName] = (placedByStorage[storageName] or 0) + 1
				standNamesByStorage[storageName] = standNamesByStorage[storageName] or {}
				table.insert(standNamesByStorage[storageName], tostring(standName))
			end
		end

		for inventoryKey, inventoryEntry in pairs(inventory) do
			if isBrainrotInventoryEntry(inventoryKey, inventoryEntry) then
				local availableQuantity = math.max(0, coerceNumber(inventoryEntry.Quantity, 0))
				local standNames = standNamesByStorage[inventoryKey] or {}
				local totalInstances = availableQuantity + #standNames

				for index = 1, totalInstances do
					local assignedStand = standNames[index]
					local instanceId = createBrainrotInstance(inventoryKey, inventoryEntry, assignedStand)
					if assignedStand then
						incomeBrainrots[assignedStand] = incomeBrainrots[assignedStand] or {}
						incomeBrainrots[assignedStand].BrainrotName = inventoryKey
						incomeBrainrots[assignedStand].BrainrotInstanceId = instanceId
					end
				end
			end
		end
	end

	local availableCounts = {}
	for _, rawInstanceId in ipairs(brainrotInventory.Order) do
		local instanceData = brainrotInventory.ById[tostring(rawInstanceId)]
		if instanceData then
			if instanceData.AssignedStand ~= "" then
				incomeBrainrots[instanceData.AssignedStand] = incomeBrainrots[instanceData.AssignedStand] or {}
				incomeBrainrots[instanceData.AssignedStand].BrainrotName = instanceData.StorageName
				incomeBrainrots[instanceData.AssignedStand].BrainrotInstanceId = tostring(rawInstanceId)
			else
				availableCounts[instanceData.StorageName] = (availableCounts[instanceData.StorageName] or 0) + 1
			end
		end
	end

	for inventoryKey, inventoryEntry in pairs(inventory) do
		if isBrainrotInventoryEntry(inventoryKey, inventoryEntry) then
			inventoryEntry.Quantity = availableCounts[inventoryKey] or 0
		end
	end

	local materials = ensureTable(data, "Materials")
	materials.Inventory = ensureTable(materials, "Inventory")
	materials.Timber = math.max(coerceNumber(materials.Timber, 0), coerceNumber(materials.CommonShipMaterial, 0))
	materials.Iron = math.max(coerceNumber(materials.Iron, 0), coerceNumber(materials.RareShipMaterial, 0))
	materials.AncientTimber = coerceNumber(materials.AncientTimber, 0)
	materials.CommonShipMaterial = materials.Timber
	materials.RareShipMaterial = materials.Iron

	local active = ensureTable(data, "Active")
	active.x2Money = coerceNumber(active.x2Money, 1)
	active.x15WalkSpeed = coerceNumber(active.x15WalkSpeed, 1)

	local gamepasses = ensureTable(data, "Gamepasses")
	gamepasses.x2MoneyValue = coerceNumber(gamepasses.x2MoneyValue, 1)
end

return ProfileMigrations
