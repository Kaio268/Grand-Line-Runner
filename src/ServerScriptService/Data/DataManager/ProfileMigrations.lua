local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ProfileTemplate = require(script.Parent:WaitForChild("ProfileTemplate"))

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
	leaderstats[primaryCurrency.LegacyKeys.Leaderstat] = nil
	leaderstats[primaryCurrency.LegacyKeys.LeaderstatTypo] = nil

	local totalStats = ensureTable(data, "TotalStats")
	local legacyTotal = coerceNumber(totalStats[primaryCurrency.LegacyKeys.Total], 0)
	totalStats[primaryCurrency.TotalKey] = coerceNumber(totalStats[primaryCurrency.TotalKey], legacyTotal)
	totalStats[primaryCurrency.LegacyKeys.Total] = nil

	local hiddenLeaderstats = ensureTable(data, "HiddenLeaderstats")
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

	local materials = ensureTable(data, "Materials")
	materials.Inventory = ensureTable(materials, "Inventory")
	materials.CommonShipMaterial = coerceNumber(materials.CommonShipMaterial, 0)
	materials.RareShipMaterial = coerceNumber(materials.RareShipMaterial, 0)

	local active = ensureTable(data, "Active")
	active.x2Money = coerceNumber(active.x2Money, 1)
	active.x15WalkSpeed = coerceNumber(active.x15WalkSpeed, 1)

	local gamepasses = ensureTable(data, "Gamepasses")
	gamepasses.x2MoneyValue = coerceNumber(gamepasses.x2MoneyValue, 1)
end

return ProfileMigrations
