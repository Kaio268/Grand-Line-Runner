local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ProfileTemplate = require(script.Parent:WaitForChild("ProfileTemplate"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))
local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local IndexDiscovery = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("IndexDiscovery"))
local TutorialConfigs = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Tutorials"))
local VariantCfg = CrewCatalog.GetVariantConfig()

local ProfileMigrations = {}

local primaryCurrency = Economy.Currency.Primary
local CREW_MEMBER_INVENTORY_SCHEMA_VERSION = 2
local CREW_MEMBER_QUICK_SLOT_SCHEMA_VERSION = 2
local ECONOMY_INFLATION_VERSION = Economy.GetInflationVersion()
local ECONOMY_INFLATION_MULTIPLIER = Economy.GetInflationMultiplier()
local LEGACY_BELI_INFLATION_THRESHOLD = 1_000_000

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

local function trim(value)
	local text = tostring(value or "")
	return text:match("^%s*(.-)%s*$") or ""
end

local function normalizeRedeemedCodeKey(code)
	local normalized = string.upper(trim(code))
	if normalized == "" or #normalized > 32 then
		return nil
	end
	if normalized:match("^[A-Z0-9_%-]+$") == nil then
		return nil
	end
	return normalized
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

local function buildIncomeRollFields(rarity, variant, instanceData, sourceEconomyVersion)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local normalizedVariant = CrewIncomeBalance.NormalizeVariant(variant)
	local baseIncomeRoll = typeof(instanceData) == "table" and instanceData.BaseIncomeRoll or nil
	local incomeRollVersion = typeof(instanceData) == "table" and instanceData.IncomeRollVersion or nil
	local sourceRollVersion = math.floor(tonumber(incomeRollVersion) or 1)
	local currentRollVersion = CrewIncomeBalance.GetIncomeRollVersion()
	if
		(tonumber(sourceEconomyVersion) or 0) < ECONOMY_INFLATION_VERSION
		and sourceRollVersion >= currentRollVersion
		and tonumber(baseIncomeRoll) ~= nil
	then
		baseIncomeRoll = Economy.ScaleAmount(baseIncomeRoll)
		incomeRollVersion = currentRollVersion
	end

	local migratedBaseIncomeRoll, migratedIncomeRollVersion = CrewIncomeBalance.GetOrMigrateBaseIncome(
		normalizedRarity,
		baseIncomeRoll,
		incomeRollVersion
	)

	return {
		Rarity = normalizedRarity,
		Variant = normalizedVariant,
		BaseIncomeRoll = migratedBaseIncomeRoll,
		IncomeRollVersion = migratedIncomeRollVersion,
		Income = CrewIncomeBalance.ComputeIncome(
			migratedBaseIncomeRoll,
			normalizedVariant,
			typeof(instanceData) == "table" and instanceData.Level or nil,
			normalizedRarity
		),
	}
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

local function normalizeCrewMemberSourceInstance(instanceId, instanceData, fallbackStorageName, sourceEconomyVersion)
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
	local incomeFields = buildIncomeRollFields(instanceData.Rarity or "Common", variantKey, instanceData, sourceEconomyVersion)

	return {
		InstanceId = tostring(instanceId),
		StorageName = storageName,
		BaseName = baseName,
		Variant = incomeFields.Variant,
		Rarity = incomeFields.Rarity,
		BaseIncomeRoll = incomeFields.BaseIncomeRoll,
		IncomeRollVersion = incomeFields.IncomeRollVersion,
		Income = incomeFields.Income,
		Render = tostring(instanceData.Render or ""),
		GoldenRender = tostring(instanceData.GoldenRender or instanceData.Render or ""),
		DiamondRender = tostring(instanceData.DiamondRender or instanceData.Render or ""),
		Level = CrewIncomeBalance.NormalizeLevel(instanceData.Level),
		CurrentXP = math.max(0, coerceNumber(instanceData.CurrentXP, 0)),
		AssignedStand = tostring(instanceData.AssignedStand or ""),
		AcquiredAt = coerceNumber(instanceData.AcquiredAt, 0),
		LastReleasedAt = coerceNumber(instanceData.LastReleasedAt, 0),
		TutorialReward = instanceData.TutorialReward == true,
		TutorialToken = tostring(instanceData.TutorialToken or ""),
		Overflow = instanceData.Overflow == true,
		OverflowSource = tostring(instanceData.OverflowSource or ""),
		OverflowedAt = coerceNumber(instanceData.OverflowedAt, 0),
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

local function normalizeCrewMemberInstance(instanceId, instanceData, fallbackStorageName, projectionSource, sourceEconomyVersion)
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
		BaseIncomeRoll = instanceData.BaseIncomeRoll,
		IncomeRollVersion = instanceData.IncomeRollVersion,
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
		Overflow = instanceData.Overflow,
		OverflowSource = instanceData.OverflowSource,
		OverflowedAt = instanceData.OverflowedAt,
	}, crewMemberId, sourceEconomyVersion)
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
		BaseIncomeRoll = legacyInstance.BaseIncomeRoll,
		IncomeRollVersion = legacyInstance.IncomeRollVersion,
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
		Overflow = legacyInstance.Overflow == true,
		OverflowSource = tostring(legacyInstance.OverflowSource or ""),
		OverflowedAt = coerceNumber(legacyInstance.OverflowedAt, 0),
		ProjectionSource = tostring(instanceData.ProjectionSource or projectionSource or "ProfileMigrations"),
	}
end

local function ensureCrewMemberInventoryShape(crewMemberInventory)
	if typeof(crewMemberInventory) ~= "table" then
		crewMemberInventory = {}
	end

	crewMemberInventory.SchemaVersion = CREW_MEMBER_INVENTORY_SCHEMA_VERSION
	crewMemberInventory.NextInstanceId = math.max(1, coerceNumber(crewMemberInventory.NextInstanceId, 1))
	crewMemberInventory.ById = ensureTable(crewMemberInventory, "ById")
	crewMemberInventory.Order = ensureTable(crewMemberInventory, "Order")

	return crewMemberInventory
end

local function normalizeCrewMemberInventory(crewMemberInventory, sourceEconomyVersion)
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
		local normalized = normalizeCrewMemberInstance(instanceId, instanceData, nil, source, sourceEconomyVersion)
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

local function coerceNumberish(value, fallback)
	local numeric = tonumber(value)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return fallback
	end
	return numeric
end

local function normalizeLegacySlotKey(value)
	local numeric = tonumber(value)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return nil
	end

	numeric = math.floor(numeric)
	if numeric < 1 then
		return nil
	end

	return tostring(numeric)
end

local function normalizeQuickSlotAssignments(assignments, crewMemberInventory)
	local normalized = {}
	local seen = {}
	local maxSlots = math.max(0, tonumber(CrewQuickSlotConfig.MaxSlots) or 0)
	local byId = if typeof(crewMemberInventory) == "table" and typeof(crewMemberInventory.ById) == "table"
		then crewMemberInventory.ById
		else {}

	if typeof(assignments) ~= "table" then
		return normalized
	end

	for rawSlotKey, rawInstanceId in pairs(assignments) do
		local slotKey = normalizeLegacySlotKey(rawSlotKey)
		local slotIndex = tonumber(slotKey)
		local instanceId = tostring(rawInstanceId or "")
		local instanceData = byId[instanceId]
		if
			slotIndex ~= nil
			and slotIndex <= maxSlots
			and instanceId ~= ""
			and seen[instanceId] ~= true
			and typeof(instanceData) == "table"
			and tostring(instanceData.AssignedStand or "") == ""
			and instanceData.Overflow ~= true
		then
			normalized[tostring(slotIndex)] = instanceId
			seen[instanceId] = true
		end
	end

	return normalized
end

local function hasCrewSlotAssignment(row)
	if typeof(row) ~= "table" then
		return false
	end

	return firstNonEmpty(
		row.CrewMemberName,
		row.CrewMemberId,
		row.StorageName,
		row.LegacyStorageName,
		row.CrewMemberInstanceId,
		row.InstanceId,
		row.CrewInstanceId
	) ~= ""
end

local function buildCrewSlotIncomeRow(row)
	if typeof(row) ~= "table" then
		return nil
	end

	local crewMemberName = firstNonEmpty(
		row.CrewMemberName,
		row.CrewMemberId,
		row.StorageName,
		row.Name,
		row.LegacyStorageName,
		row.BrainrotName,
		row.Brainrot,
		row.ItemName
	)
	local instanceId = firstNonEmpty(row.CrewMemberInstanceId, row.InstanceId, row.CrewInstanceId)
	if crewMemberName == "" and instanceId == "" then
		return nil
	end

	return {
		CrewMemberName = crewMemberName,
		LegacyStorageName = firstNonEmpty(row.LegacyStorageName, row.StorageName, row.Name, row.BrainrotName),
		CrewMemberInstanceId = instanceId,
		IncomeToCollect = coerceNumberish(row.IncomeToCollect or row.Income or row.Money or row.Cash, 0),
		LastAccruedAtUnix = math.max(0, math.floor(coerceNumber(row.LastAccruedAtUnix, os.time()))),
		StandLevel = CrewIncomeBalance.NormalizeLevel(row.StandLevel or row.Level),
	}
end

local function migrateLegacyCrewSlotRows(data, sourceRows)
	if typeof(sourceRows) ~= "table" then
		return 0
	end

	local crewMemberIncome = ensureTable(data, "CrewMemberIncome")
	local migrated = 0

	for rawSlotName, row in pairs(sourceRows) do
		local slotKey = normalizeLegacySlotKey(rawSlotName)
		if slotKey == nil then
			continue
		end

		local existing = crewMemberIncome[slotKey]
		if hasCrewSlotAssignment(existing) then
			continue
		end

		local migratedRow = buildCrewSlotIncomeRow(row)
		if migratedRow then
			crewMemberIncome[slotKey] = migratedRow
			migrated += 1
		end
	end

	return migrated
end

local function migrateLegacyStandLevels(data, sourceLevels)
	if typeof(sourceLevels) ~= "table" then
		return 0
	end

	local crewMemberIncome = ensureTable(data, "CrewMemberIncome")
	local migrated = 0

	for rawSlotName, levelValue in pairs(sourceLevels) do
		local slotKey = normalizeLegacySlotKey(rawSlotName)
		if slotKey == nil then
			continue
		end

		local row = crewMemberIncome[slotKey]
		if typeof(row) ~= "table" then
			continue
		end

		local rawLevel = if typeof(levelValue) == "table"
			then levelValue.StandLevel or levelValue.Level or levelValue.Value
			else levelValue
		local level = CrewIncomeBalance.NormalizeLevel(coerceNumberish(rawLevel, tonumber(row.StandLevel) or 1))
		if tonumber(row.StandLevel) ~= level then
			row.StandLevel = level
			migrated += 1
		end
	end

	return migrated
end

local function mirrorPrimaryCurrency(data)
	local leaderstats = ensureTable(data, "leaderstats")
	local totalStats = ensureTable(data, "TotalStats")
	local currencyLegacy = ensureTable(data, "CurrencyLegacy")
	local current = coerceNumber(leaderstats[primaryCurrency.Key], 0)
	local total = coerceNumber(totalStats[primaryCurrency.TotalKey], 0)

	currencyLegacy.CurrentBeli = current
	currencyLegacy.Doubloons = current
	currencyLegacy.Money = current
	currencyLegacy.Moeny = current
	currencyLegacy.CurrentTotalBeli = total
	currencyLegacy.TotalDoubloons = total
	currencyLegacy.TotalMoney = total
end

local function applyStudioLegacyBeliReset(data, previousVersion)
	if not RunService:IsStudio() then
		return false
	end
	if math.floor(tonumber(previousVersion) or 0) >= ECONOMY_INFLATION_VERSION then
		return false
	end

	local leaderstats = ensureTable(data, "leaderstats")
	local totalStats = ensureTable(data, "TotalStats")
	local hiddenLeaderstats = ensureTable(data, "HiddenLeaderstats")
	local currentBeli = coerceNumber(leaderstats[primaryCurrency.Key], 0)
	local totalBeli = coerceNumber(totalStats[primaryCurrency.TotalKey], 0)
	if currentBeli < LEGACY_BELI_INFLATION_THRESHOLD and totalBeli < LEGACY_BELI_INFLATION_THRESHOLD then
		return false
	end

	leaderstats[primaryCurrency.Key] = 0
	totalStats[primaryCurrency.TotalKey] = 0
	hiddenLeaderstats.TutorialStarterBeliGranted = false

	local crewMemberIncome = ensureTable(data, "CrewMemberIncome")
	for _, row in pairs(crewMemberIncome) do
		if typeof(row) == "table" then
			row.IncomeToCollect = 0
		end
	end

	local ship = ensureTable(data, "Ship")
	local captainSlot = ensureTable(ship, "CaptainSlot")
	captainSlot.IncomeToCollect = 0

	local afk = ensureTable(data, "AFK")
	local afkSession = ensureTable(afk, "Session")
	afkSession.BeliRemainder = 0
	afkSession.EarnedBeliThisSession = 0

	mirrorPrimaryCurrency(data)
	warn(string.format(
		"[EconomyBeliScaleRemoval] Studio reset legacy inflated Beli balance economyVersion=%d->%d current=%s total=%s",
		math.floor(tonumber(previousVersion) or 0),
		ECONOMY_INFLATION_VERSION,
		tostring(currentBeli),
		tostring(totalBeli)
	))
	return true
end

local function applyEconomyInflationMigration(data, previousVersion)
	local oldVersion = math.floor(tonumber(previousVersion) or 0)
	if oldVersion >= ECONOMY_INFLATION_VERSION then
		data.EconomyVersion = math.max(oldVersion, ECONOMY_INFLATION_VERSION)
		return false
	end

	local resetInflatedStudioBeli = applyStudioLegacyBeliReset(data, oldVersion)
	data.EconomyVersion = ECONOMY_INFLATION_VERSION
	warn(string.format(
		"[EconomyBeliScaleRemoval] migrated profile economyVersion=%d->%d legacyMultiplier=%s studioReset=%s",
		oldVersion,
		ECONOMY_INFLATION_VERSION,
		tostring(ECONOMY_INFLATION_MULTIPLIER),
		tostring(resetInflatedStudioBeli)
	))
	return true
end

function ProfileMigrations.Apply(data)
	if typeof(data) ~= "table" then
		return
	end

	local economyVersionBeforeMigration = math.floor(tonumber(data.EconomyVersion) or 0)
	mergeDefaults(data, ProfileTemplate)

	local leaderstats = ensureTable(data, "leaderstats")
	local currencyLegacy = ensureTable(data, "CurrencyLegacy")
	local existingCurrentBeli = coerceNumber(currencyLegacy.CurrentBeli, 0)
	local existingCurrentDoubloons = coerceNumber(currencyLegacy.Doubloons, 0)
	local existingCurrentMoney = coerceNumber(currencyLegacy.Money, 0)
	local existingCurrentTypo = coerceNumber(currencyLegacy.Moeny, 0)
	local existingLegacyDoubloons = coerceNumber(currencyLegacy.LeaderstatDoubloons, 0)
	local existingLegacyMoney = coerceNumber(currencyLegacy.LeaderstatMoney, 0)
	local existingLegacyTypo = coerceNumber(currencyLegacy.LeaderstatTypo, 0)
	local legacyDoubloons = coerceNumber(leaderstats[primaryCurrency.LegacyKeys.Leaderstat], existingLegacyDoubloons)
	local legacyMoney = coerceNumber(leaderstats[primaryCurrency.LegacyKeys.LeaderstatMoney], existingLegacyMoney)
	local typoMoney = coerceNumber(leaderstats[primaryCurrency.LegacyKeys.LeaderstatTypo], existingLegacyTypo)
	local resolvedMoney = math.max(
		coerceNumber(leaderstats[primaryCurrency.Key], 0),
		existingCurrentBeli,
		existingCurrentDoubloons,
		existingCurrentMoney,
		existingCurrentTypo,
		legacyDoubloons,
		legacyMoney,
		typoMoney
	)

	leaderstats[primaryCurrency.Key] = resolvedMoney
	leaderstats.Bounty = math.max(0, coerceNumber(leaderstats.Bounty, 0))
	currencyLegacy.LeaderstatDoubloons = legacyDoubloons
	currencyLegacy.LeaderstatMoney = legacyMoney
	currencyLegacy.LeaderstatTypo = typoMoney
	currencyLegacy.CurrentBeli = resolvedMoney
	currencyLegacy.Doubloons = resolvedMoney
	currencyLegacy.Money = resolvedMoney
	currencyLegacy.Moeny = resolvedMoney
	-- Old currency leaderstat keys are removed from the visible leaderstats folder after
	-- their values are copied into Beli. DataManager path aliases keep old code working.
	leaderstats[primaryCurrency.LegacyKeys.Leaderstat] = nil
	leaderstats[primaryCurrency.LegacyKeys.LeaderstatMoney] = nil
	leaderstats[primaryCurrency.LegacyKeys.LeaderstatTypo] = nil

	local totalStats = ensureTable(data, "TotalStats")
	local existingLegacyTotal = coerceNumber(currencyLegacy.LegacyTotalDoubloons, 0)
	local existingLegacyTotalMoney = coerceNumber(currencyLegacy.LegacyTotalMoney, 0)
	local legacyTotal = coerceNumber(totalStats[primaryCurrency.LegacyKeys.Total], existingLegacyTotal)
	local legacyTotalMoney = coerceNumber(totalStats[primaryCurrency.LegacyKeys.TotalMoney], existingLegacyTotalMoney)
	local resolvedTotal = math.max(coerceNumber(totalStats[primaryCurrency.TotalKey], 0), legacyTotal, legacyTotalMoney)
	totalStats[primaryCurrency.TotalKey] = resolvedTotal
	currencyLegacy.LegacyTotalDoubloons = legacyTotal
	currencyLegacy.LegacyTotalMoney = legacyTotalMoney
	currencyLegacy.CurrentTotalBeli = resolvedTotal
	currencyLegacy.TotalDoubloons = resolvedTotal
	currencyLegacy.TotalMoney = resolvedTotal
	totalStats[primaryCurrency.LegacyKeys.Total] = nil
	totalStats[primaryCurrency.LegacyKeys.TotalMoney] = nil

	local bounty = ensureTable(data, "Bounty")
	bounty.LifetimeExtraction = math.max(0, coerceNumber(bounty.LifetimeExtraction, 0))
	bounty.Crew = math.max(0, coerceNumber(bounty.Crew, 0))
	bounty.Total = math.max(0, coerceNumber(bounty.Total, leaderstats.Bounty))
	leaderstats.Bounty = math.max(leaderstats.Bounty, bounty.Total)

	local titles = ensureTable(data, "Titles")
	titles.Unlocked = ensureTable(titles, "Unlocked")
	titles.Progress = ensureTable(titles, "Progress")
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
	local defaultSpeed = math.max(1, tonumber(ProfileTemplate.HiddenLeaderstats.Speed) or 1)
	local function sanitizeSpeed(value, fallback)
		local numeric = tonumber(value)
		if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
			return fallback
		end
		return math.max(defaultSpeed, numeric)
	end

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
		hiddenLeaderstats.Speed = math.max(
			sanitizeSpeed(hiddenLeaderstats.Speed, defaultSpeed),
			sanitizeSpeed(legacyHiddenLeadderstats.Speed, defaultSpeed)
		)
		data.HiddenLeadderstats = nil
	end

	hiddenLeaderstats.PlotUpgrade = math.clamp(coerceNumber(hiddenLeaderstats.PlotUpgrade, 0), 0, PlotUpgradeConfig.MaxLevel)
	hiddenLeaderstats.Speed = sanitizeSpeed(hiddenLeaderstats.Speed, defaultSpeed)
	hiddenLeaderstats.Tutorial = coerceBoolean(hiddenLeaderstats.Tutorial, false)
	hiddenLeaderstats.TutorialCrewMemberGranted = coerceBoolean(
		hiddenLeaderstats.TutorialCrewMemberGranted or hiddenLeaderstats.TutorialBrainrotGranted,
		false
	)
	hiddenLeaderstats.TutorialBrainrotGranted = nil
	hiddenLeaderstats.TutorialSpeedTopUpGranted = coerceBoolean(hiddenLeaderstats.TutorialSpeedTopUpGranted, false)
	hiddenLeaderstats.TutorialStarterBeliGranted = coerceBoolean(
		hiddenLeaderstats.TutorialStarterBeliGranted or hiddenLeaderstats.TutorialStarterDoubloonsGranted,
		false
	)
	hiddenLeaderstats.TutorialStarterDoubloonsGranted = nil
	if hiddenLeaderstats.Tutorial == true then
		hiddenLeaderstats.TutorialCrewMemberGranted = true
		hiddenLeaderstats.TutorialSpeedTopUpGranted = true
	elseif coerceNumber(hiddenLeaderstats.Speed, 1) <= 1 then
		hiddenLeaderstats.TutorialSpeedTopUpGranted = false
	end

	local socialRewards = ensureTable(data, "SocialRewards")
	local groupLikeLuffyReward = ensureTable(socialRewards, "GroupLikeLuffy")
	groupLikeLuffyReward.Claimed = coerceBoolean(groupLikeLuffyReward.Claimed, false)
	groupLikeLuffyReward.ClaimedAtUnix = math.max(0, math.floor(coerceNumber(groupLikeLuffyReward.ClaimedAtUnix, 0)))

	local codes = ensureTable(data, "Codes")
	local redeemedCodes = ensureTable(codes, "Redeemed")
	for rawCode, rawState in pairs(redeemedCodes) do
		local code = normalizeRedeemedCodeKey(rawCode)
		if code == nil then
			redeemedCodes[rawCode] = nil
			continue
		end

		local nextState
		if typeof(rawState) == "table" then
			nextState = rawState
			nextState.RedeemedAtUnix = math.max(0, math.floor(coerceNumber(nextState.RedeemedAtUnix, 0)))
			if nextState.CodeVersion ~= nil and typeof(nextState.CodeVersion) ~= "string" then
				nextState.CodeVersion = tostring(nextState.CodeVersion)
			end
			if nextState.DisplayName ~= nil and typeof(nextState.DisplayName) ~= "string" then
				nextState.DisplayName = tostring(nextState.DisplayName)
			end
		elseif rawState == true then
			nextState = {
				RedeemedAtUnix = 0,
			}
		end

		if nextState == nil then
			redeemedCodes[rawCode] = nil
		elseif code ~= rawCode then
			redeemedCodes[rawCode] = nil
			redeemedCodes[code] = nextState
		else
			redeemedCodes[code] = nextState
		end
	end

	local tutorials = ensureTable(data, "Tutorials")
	tutorials.SchemaVersion = math.max(
		1,
		math.floor(coerceNumber(tutorials.SchemaVersion, 1)),
		math.floor(coerceNumber(TutorialConfigs.SchemaVersion, 1))
	)
	local completedTutorials = ensureTable(tutorials, "Completed")
	for tutorialId, completed in pairs(completedTutorials) do
		if typeof(tutorialId) ~= "string" or tutorialId == "" or typeof(completed) ~= "boolean" then
			completedTutorials[tutorialId] = nil
		end
	end
	local tutorialQueue = ensureTable(tutorials, "Queue")
	local sanitizedQueue = {}
	for _, entry in ipairs(tutorialQueue) do
		if typeof(entry) == "table" then
			local tutorialId = tostring(entry.Id or entry.TutorialId or "")
			local definition = TutorialConfigs.GetDefinition(tutorialId)
			if tutorialId ~= "" and definition ~= nil and definition.Enabled == true then
				local context = {}
				if typeof(entry.Context) == "table" then
					for key, value in pairs(entry.Context) do
						local keyText = tostring(key or "")
						if keyText ~= "" then
							local valueType = typeof(value)
							if valueType == "string" or valueType == "number" or valueType == "boolean" then
								context[keyText] = value
							end
						end
					end
				end

				table.insert(sanitizedQueue, {
					Id = tutorialId,
					EnqueuedAtUnix = math.max(0, math.floor(coerceNumber(entry.EnqueuedAtUnix, os.time()))),
					EligibleAtUnix = math.max(0, math.floor(coerceNumber(entry.EligibleAtUnix, os.time()))),
					Context = context,
				})
			end
		end
	end
	tutorials.Queue = sanitizedQueue
	if hiddenLeaderstats.Tutorial == true then
		if completedTutorials.FirstRun == nil then
			completedTutorials.FirstRun = true
		end
		for _, tutorialId in ipairs(TutorialConfigs.GetLegacyFirstRunBackfillIds()) do
			if completedTutorials[tutorialId] == nil then
				completedTutorials[tutorialId] = true
			end
		end
	end

	local settings = ensureTable(data, "Settings")
	local earnedMaxSpeed = math.max(1, math.floor((tonumber(hiddenLeaderstats.Speed) or defaultSpeed) + 0.5))
	settings.SpeedAutoMax = coerceBoolean(settings.SpeedAutoMax, true)
	settings.PremiumStealProtectionEnabled = coerceBoolean(settings.PremiumStealProtectionEnabled, true)
	if settings.SpeedAutoMax == true then
		settings.SelectedSpeed = earnedMaxSpeed
	else
		local selectedSpeed = tonumber(settings.SelectedSpeed)
		if selectedSpeed == nil or selectedSpeed ~= selectedSpeed or selectedSpeed == math.huge or selectedSpeed == -math.huge then
			selectedSpeed = earnedMaxSpeed
		end
		settings.SelectedSpeed = math.clamp(math.floor(selectedSpeed + 0.5), 1, earnedMaxSpeed)
	end

	local premiumCrewStealProtection = ensureTable(data, "PremiumCrewStealProtection")
	premiumCrewStealProtection.NewPlayerRemoved = coerceBoolean(
		premiumCrewStealProtection.NewPlayerRemoved,
		false
	)
	premiumCrewStealProtection.RemovedAt = math.max(0, coerceNumber(premiumCrewStealProtection.RemovedAt, 0))
	if typeof(premiumCrewStealProtection.RemovedReason) ~= "string" then
		premiumCrewStealProtection.RemovedReason = ""
	end

	local raidShield = ensureTable(data, "RaidShield")
	raidShield.SchemaVersion = math.max(1, math.floor(coerceNumber(raidShield.SchemaVersion, 1)))
	raidShield.Enabled = coerceBoolean(raidShield.Enabled, settings.PremiumStealProtectionEnabled == true)
	raidShield.SuppressionUntil = math.max(0, coerceNumber(raidShield.SuppressionUntil, 0))
	raidShield.NewPlayerGrantSeeded = coerceBoolean(raidShield.NewPlayerGrantSeeded, false)
	if typeof(raidShield.LastRaidPenaltyReceiptId) ~= "string" then
		raidShield.LastRaidPenaltyReceiptId = ""
	end
	raidShield.LastRaidPenaltyAt = math.max(0, coerceNumber(raidShield.LastRaidPenaltyAt, 0))
	if typeof(raidShield.LastRaidPenaltyReason) ~= "string" then
		raidShield.LastRaidPenaltyReason = ""
	end
	local raidShieldGrants = ensureTable(raidShield, "Grants")
	local timePlayed = math.max(0, coerceNumber(totalStats.TimePlayed, 0))
	local newPlayerDuration = 28800
	if raidShield.NewPlayerGrantSeeded ~= true then
		raidShield.Enabled = settings.PremiumStealProtectionEnabled == true
		raidShield.NewPlayerGrantSeeded = true
		if premiumCrewStealProtection.NewPlayerRemoved == true then
			raidShield.Enabled = false
		elseif timePlayed < newPlayerDuration and typeof(raidShieldGrants.new_player) ~= "table" then
			local migrationTime = os.time()
			local remaining = math.max(1, newPlayerDuration - math.floor(timePlayed))
			raidShieldGrants.new_player = {
				Source = "new_player",
				GrantedAt = migrationTime,
				StartsAt = migrationTime,
				ExpiresAt = migrationTime + remaining,
				DurationSeconds = remaining,
				RevokedAt = 0,
				RevokedReason = "",
			}
		end
	end

	local tutorialStartAmount = coerceNumber(Economy.Tutorial and Economy.Tutorial.StartingBeli, 0)
	if hiddenLeaderstats.TutorialStarterBeliGranted ~= true then
		if hiddenLeaderstats.Tutorial == true then
			hiddenLeaderstats.TutorialStarterBeliGranted = true
		elseif tutorialStartAmount > 0 then
			local currentBalance = coerceNumber(leaderstats[primaryCurrency.Key], 0)
			local shortfall = math.max(0, tutorialStartAmount - currentBalance)
			if shortfall > 0 then
				leaderstats[primaryCurrency.Key] = currentBalance + shortfall
				totalStats[primaryCurrency.TotalKey] = coerceNumber(totalStats[primaryCurrency.TotalKey], 0) + shortfall
				currencyLegacy.CurrentBeli = leaderstats[primaryCurrency.Key]
				currencyLegacy.CurrentTotalBeli = totalStats[primaryCurrency.TotalKey]
				currencyLegacy.Doubloons = leaderstats[primaryCurrency.Key]
				currencyLegacy.Money = leaderstats[primaryCurrency.Key]
				currencyLegacy.Moeny = leaderstats[primaryCurrency.Key]
				currencyLegacy.TotalDoubloons = totalStats[primaryCurrency.TotalKey]
				currencyLegacy.TotalMoney = totalStats[primaryCurrency.TotalKey]
			end
			hiddenLeaderstats.TutorialStarterBeliGranted = true
		end
	end

	local ship = ensureTable(data, "Ship")
	ship.Slots = ensureTable(ship, "Slots")
	ship.CaptainSlot = ensureTable(ship, "CaptainSlot")
	ship.CaptainSlot.IncomeToCollect = coerceNumber(ship.CaptainSlot.IncomeToCollect, 0)
	ship.CaptainSlot.LastAccruedAtUnix = math.max(0, math.floor(coerceNumber(ship.CaptainSlot.LastAccruedAtUnix, os.time())))
	ship.MaxSlots = Economy.Rules.MaxShipSlots
	migrateLegacyCrewSlotRows(data, ship.Slots)
	migrateLegacyCrewSlotRows(data, data.IncomeBrainrots)
	migrateLegacyStandLevels(data, data.StandsLevels)
	local crewMemberIncome = ensureTable(data, "CrewMemberIncome")
	local migrationTimestamp = os.time()
	for _, row in pairs(crewMemberIncome) do
		if typeof(row) == "table" then
			row.IncomeToCollect = coerceNumber(row.IncomeToCollect, 0)
			row.LastAccruedAtUnix = math.max(0, math.floor(coerceNumber(row.LastAccruedAtUnix, migrationTimestamp)))
			row.StandLevel = CrewIncomeBalance.NormalizeLevel(row.StandLevel)
		end
	end

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
	crewMemberQuickSlots.SchemaVersion = CREW_MEMBER_QUICK_SLOT_SCHEMA_VERSION
	crewMemberQuickSlots.UnlockedSlots = canonicalUnlockedSlots
	crewMemberQuickSlots.MaxSlots = CrewQuickSlotConfig.MaxSlots
	crewMemberQuickSlots.Assignments = if typeof(crewMemberQuickSlots.Assignments) == "table"
		then crewMemberQuickSlots.Assignments
		else {}

	local unopenedChests = ensureTable(data, "UnopenedChests")
	unopenedChests.NextChestId = math.max(1, coerceNumber(unopenedChests.NextChestId, 1))
	unopenedChests.ById = ensureTable(unopenedChests, "ById")
	unopenedChests.Order = ensureTable(unopenedChests, "Order")
	unopenedChests.Stacks = ensureTable(unopenedChests, "Stacks")
	for _, tierName in ipairs(ChestRewards.StandardTierOrder) do
		unopenedChests.Stacks[tierName] = math.max(0, math.floor(coerceNumber(tonumber(unopenedChests.Stacks[tierName]), 0)))
	end
	unopenedChests.StackSchemaVersion = 1

	local compactedStackableCount = 0
	local seenOrderedChestIds = {}
	local normalizedOrder = {}

	local function normalizeLegacyChestEntry(chestId, chestEntry)
		local safeChestEntry = if typeof(chestEntry) == "table" then chestEntry else {}
		local normalized = ChestUtils.BuildChestData(safeChestEntry)
		local normalizedChestId = tostring(chestId)
		normalized.ChestId = tostring(safeChestEntry.ChestId or normalizedChestId)
		normalized.DepthBand = tostring(safeChestEntry.DepthBand or "")
		normalized.CreatedAt = math.max(0, coerceNumber(safeChestEntry.CreatedAt, normalized.CreatedAt))

		if normalized.ChestKind == ChestRewards.ChestKinds.DevilFruit and normalized.FruitRarity == nil then
			normalized.Tier = ChestUtils.GetDefaultTierForDevilFruitChest(nil)
		end

		return normalizedChestId, normalized
	end

	local function migrateLegacyChest(chestId, chestEntry)
		local normalizedChestId, normalized = normalizeLegacyChestEntry(chestId, chestEntry)
		local stackKey = ChestUtils.GetStackKey(normalized)
		if stackKey ~= nil then
			unopenedChests.Stacks[stackKey] = math.max(0, tonumber(unopenedChests.Stacks[stackKey]) or 0) + 1
			unopenedChests.ById[normalizedChestId] = nil
			compactedStackableCount += 1
			return
		end

		unopenedChests.ById[normalizedChestId] = normalized
		normalizedOrder[#normalizedOrder + 1] = normalizedChestId
	end

	for _, rawChestId in ipairs(unopenedChests.Order) do
		local chestId = tostring(rawChestId)
		if chestId ~= "" and seenOrderedChestIds[chestId] ~= true then
			seenOrderedChestIds[chestId] = true
			local chestEntry = unopenedChests.ById[chestId]
			if chestEntry ~= nil then
				migrateLegacyChest(chestId, chestEntry)
			end
		end
	end

	local unorderedLegacyChests = {}
	for chestId, chestEntry in pairs(unopenedChests.ById) do
		local normalizedChestId = tostring(chestId)
		if seenOrderedChestIds[normalizedChestId] ~= true then
			unorderedLegacyChests[#unorderedLegacyChests + 1] = {
				ChestId = normalizedChestId,
				Entry = chestEntry,
			}
		end
	end
	for _, record in ipairs(unorderedLegacyChests) do
		migrateLegacyChest(record.ChestId, record.Entry)
	end

	unopenedChests.Order = normalizedOrder
	local unopenedStackCount = 0
	for _, amount in pairs(unopenedChests.Stacks) do
		unopenedStackCount += math.max(0, math.floor(tonumber(amount) or 0))
	end
	unopenedChests.NextChestId = math.max(unopenedChests.NextChestId, unopenedStackCount + #normalizedOrder + 1)
	unopenedChests.CompactedStackableLegacyCount =
		math.max(0, coerceNumber(tonumber(unopenedChests.CompactedStackableLegacyCount), 0)) + compactedStackableCount

	local chestRewards = ensureTable(data, "ChestRewards")
	chestRewards.MythicKeys = math.max(0, coerceNumber(chestRewards.MythicKeys, 0))
	local afkGoldChests = ensureTable(chestRewards, "AFKGoldChests")
	if typeof(afkGoldChests.DayKey) ~= "string" then
		afkGoldChests.DayKey = ""
	end
	afkGoldChests.EarnedToday = math.max(0, math.floor(coerceNumber(afkGoldChests.EarnedToday, 0)))
	afkGoldChests.ProgressSeconds = math.max(0, coerceNumber(afkGoldChests.ProgressSeconds, 0))
	ChestRewards.EnsureFruitPityState(chestRewards)

	local afk = ensureTable(data, "AFK")
	afk.SchemaVersion = 1
	local afkSession = ensureTable(afk, "Session")
	afkSession.Active = afkSession.Active == true
	if typeof(afkSession.SessionId) ~= "string" then
		afkSession.SessionId = ""
	end
	afkSession.StartedAtUnix = math.max(0, math.floor(coerceNumber(afkSession.StartedAtUnix, 0)))
	afkSession.LastAccruedAtUnix = math.max(0, math.floor(coerceNumber(afkSession.LastAccruedAtUnix, 0)))
	afkSession.ClaimedThroughUnix = math.max(0, math.floor(coerceNumber(afkSession.ClaimedThroughUnix, 0)))
	afkSession.LastRewardSettledAtUnix =
		math.max(0, math.floor(coerceNumber(afkSession.LastRewardSettledAtUnix, afkSession.ClaimedThroughUnix)))
	afkSession.AwardedChestIntervals = math.max(0, math.floor(coerceNumber(afkSession.AwardedChestIntervals, 0)))
	afkSession.BeliRemainder = math.max(0, coerceNumber(afkSession.BeliRemainder, 0))
	afkSession.EarnedChestsThisSession =
		math.max(0, math.floor(coerceNumber(afkSession.EarnedChestsThisSession, 0)))
	afkSession.EarnedBeliThisSession =
		math.max(0, math.floor(coerceNumber(afkSession.EarnedBeliThisSession, 0)))
	afkSession.RefreshCount = math.max(0, math.floor(coerceNumber(afkSession.RefreshCount, 0)))
	afkSession.PendingReturn = afkSession.PendingReturn == true
	if typeof(afkSession.Source) ~= "string" then
		afkSession.Source = ""
	end
	if typeof(afkSession.LastClaimId) ~= "string" then
		afkSession.LastClaimId = ""
	end
	afkSession.LastKnownPlaceId = math.max(0, math.floor(coerceNumber(afkSession.LastKnownPlaceId, 0)))
	afkSession.LastTeleportAtUnix = math.max(0, math.floor(coerceNumber(afkSession.LastTeleportAtUnix, 0)))

	local afkDaily = ensureTable(afk, "Daily")
	if typeof(afkDaily.DayKey) ~= "string" then
		afkDaily.DayKey = ""
	end
	afkDaily.ClaimedSeconds = math.max(0, math.floor(coerceNumber(afkDaily.ClaimedSeconds, 0)))

	local afkTotals = ensureTable(afk, "Totals")
	afkTotals.ClaimedSeconds = math.max(0, math.floor(coerceNumber(afkTotals.ClaimedSeconds, 0)))
	afkTotals.Claims = math.max(0, math.floor(coerceNumber(afkTotals.Claims, 0)))

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

	normalizeCrewMemberInventory(crewMemberInventory, economyVersionBeforeMigration)
	crewMemberQuickSlots.Assignments = normalizeQuickSlotAssignments(crewMemberQuickSlots.Assignments, crewMemberInventory)

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

	local potions = ensureTable(data, "Potions")
	potions.x2Money = math.max(0, coerceNumber(potions.x2Money, 0))
	potions.x2MoneyTime = math.max(0, coerceNumber(potions.x2MoneyTime, 0))
	potions.x15WalkSpeed = math.max(0, coerceNumber(potions.x15WalkSpeed, 0))
	potions.x15WalkSpeedTime = math.max(0, coerceNumber(potions.x15WalkSpeedTime, 0))
	potions.xLuck = math.max(0, coerceNumber(potions.xLuck, 0))
	potions.xLuckTime = math.max(0, coerceNumber(potions.xLuckTime, 0))

	local gamepasses = ensureTable(data, "Gamepasses")
	gamepasses.x2MoneyValue = coerceNumber(gamepasses.x2MoneyValue, 1)

	local multipliers = ensureTable(data, "Multipliers")
	multipliers.MoneyMult = math.max(0, coerceNumber(multipliers.MoneyMult, 0))

	local dailyClaims = ensureTable(data, "DailyClaims")
	local captainSupply = ensureTable(dailyClaims, "CaptainSupply")
	if typeof(captainSupply.LastClaimDate) ~= "string" then
		captainSupply.LastClaimDate = ""
	end

	local packs = ensureTable(data, "Packs")
	packs.StarterPack = packs.StarterPack == true

	local crewProtection = ensureTable(data, "CrewProtection")
	crewProtection.SchemaVersion = 1
	crewProtection.ShieldTokens = math.max(0, math.floor(coerceNumber(crewProtection.ShieldTokens, 0)))
	crewProtection.FleetShieldTokens = math.max(0, math.floor(coerceNumber(crewProtection.FleetShieldTokens, 0)))
	local crewShields = ensureTable(crewProtection, "CrewShields")
	crewShields.ByInstanceId = ensureTable(crewShields, "ByInstanceId")
	local fleetShield = ensureTable(crewProtection, "FleetShield")
	fleetShield.Enabled = fleetShield.Enabled ~= false
	fleetShield.ExpiresAtPlayTime = math.max(0, coerceNumber(fleetShield.ExpiresAtPlayTime, 0))
	fleetShield.PausedRemainingSeconds = math.max(0, math.floor(coerceNumber(fleetShield.PausedRemainingSeconds, 0)))
	fleetShield.LastGrantedAt = math.max(0, coerceNumber(fleetShield.LastGrantedAt, 0))
	if typeof(fleetShield.Source) ~= "string" then
		fleetShield.Source = ""
	end
	crewProtection.PermanentSlotsOwned = math.max(0, math.floor(coerceNumber(crewProtection.PermanentSlotsOwned, 0)))
	crewProtection.PermanentAssignments = ensureTable(crewProtection, "PermanentAssignments")

	applyEconomyInflationMigration(data, economyVersionBeforeMigration)
end

return ProfileMigrations
