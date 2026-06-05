local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local Economy = require(Configs:WaitForChild("GrandLineRushEconomy"))
local CrewVariants = require(Configs:WaitForChild("CrewVariants"))

local CrewIncomeBalance = {}

local DEFAULT_RARITY = "Common"
local DEFAULT_VARIANT = "Normal"
local DEFAULT_MAX_LEVEL = 50
local DEFAULT_MAX_LEVEL_INCOME_MULTIPLIER = 100
local CLAIM_EPSILON = 1e-7
local baseIncomeRangeCache = {}
local baseIncomeRangeMidpointCache = {}
local baseIncomePercentileCache = {}
local variantIncomeRangeCache = {}
local variantBandMappedIncomeCache = {}
local computeIncomeCache = {}

local BASE_INCOME_ROLL_RANGES_BY_VERSION = {
	[1] = {
		Common = { Min = 4, Max = 8 },
		Uncommon = { Min = 16, Max = 26 },
		Rare = { Min = 45, Max = 70 },
		Epic = { Min = 100, Max = 145 },
		Legendary = { Min = 210, Max = 290 },
		Mythic = { Min = 450, Max = 650 },
		Mythical = { Min = 450, Max = 650 },
		Godly = { Min = 1350, Max = 1750 },
		Secret = { Min = 4600, Max = 6000 },
	},
	[2] = {
		Common = { Min = 2, Max = 10 },
		Uncommon = { Min = 17, Max = 55 },
		Rare = { Min = 100, Max = 250 },
		Epic = { Min = 360, Max = 800 },
		Legendary = { Min = 1000, Max = 4000 },
		Mythic = { Min = 2500, Max = 9000 },
		Mythical = { Min = 2500, Max = 9000 },
		Godly = { Min = 6000, Max = 18000 },
		Secret = { Min = 16000, Max = 30000 },
	},
}

local RARITY_ALIASES = {
	common = "Common",
	uncommon = "Uncommon",
	rare = "Rare",
	epic = "Epic",
	legendary = "Legendary",
	mythic = "Mythic",
	mythical = "Mythic",
	godly = "Godly",
	secret = "Secret",
}
local VARIANT_ALIASES = {
	normal = "Normal",
	golden = "Golden",
	diamond = "Diamond",
}

local function getCrewConfig()
	return Economy.CrewMembers or {}
end

local function getIncomeRollConfig()
	return getCrewConfig().BaseIncomeRollByRarity or {}
end

local function getVariantBandConfig()
	return getCrewConfig().VariantIncomeBandsByRarity or {}
end

local function roundWhole(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function getConfiguredRangeFromTable(rangeConfig, rarity)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local range = rangeConfig[normalizedRarity]
	if typeof(range) ~= "table" then
		range = rangeConfig[DEFAULT_RARITY]
	end

	local minValue = roundWhole(range and range.Min or 1)
	local maxValue = roundWhole(range and range.Max or minValue)
	if maxValue < minValue then
		maxValue = minValue
	end

	return minValue, maxValue, normalizedRarity
end

local function sanitizeNonNegativeNumber(value)
	local numeric = tonumber(value) or 0
	if numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return 0
	end

	return math.max(0, numeric)
end

local function multiplyExtraMultipliers(extraMultipliers)
	if typeof(extraMultipliers) == "number" then
		return sanitizeNonNegativeNumber(extraMultipliers)
	end
	if typeof(extraMultipliers) ~= "table" then
		return 1
	end

	local multiplier = 1
	for _, value in ipairs(extraMultipliers) do
		multiplier *= sanitizeNonNegativeNumber(value)
	end
	return multiplier
end

local function cacheKey(...)
	local parts = table.create(select("#", ...))
	for index = 1, select("#", ...) do
		parts[index] = tostring(select(index, ...))
	end
	return table.concat(parts, "|")
end

function CrewIncomeBalance.ClearMemoizedCaches()
	table.clear(baseIncomeRangeCache)
	table.clear(baseIncomeRangeMidpointCache)
	table.clear(baseIncomePercentileCache)
	table.clear(variantIncomeRangeCache)
	table.clear(variantBandMappedIncomeCache)
	table.clear(computeIncomeCache)
end

function CrewIncomeBalance.NormalizeRarity(rarity)
	local raw = tostring(rarity or "")
	local normalized = RARITY_ALIASES[string.lower(raw)]
	if normalized then
		return normalized
	end

	if getIncomeRollConfig()[raw] ~= nil then
		return raw
	end

	return DEFAULT_RARITY
end

function CrewIncomeBalance.NormalizeVariant(variant)
	local raw = tostring(variant or "")
	for _, variantKey in ipairs(CrewVariants.Order or {}) do
		if raw == variantKey then
			return variantKey
		end
	end

	local alias = VARIANT_ALIASES[string.lower(raw)]
	if alias then
		return alias
	end

	return DEFAULT_VARIANT
end

function CrewIncomeBalance.GetIncomeRollVersion()
	return math.max(1, math.floor(tonumber(getCrewConfig().IncomeRollVersion) or 1))
end

function CrewIncomeBalance.GetMaxLevel()
	local crewConfig = getCrewConfig()
	local rules = Economy.Rules or {}
	local configuredMaxLevel = tonumber(crewConfig.MaxCrewLevel)
		or tonumber(crewConfig.MaxLevel)
		or tonumber(rules.CrewMaxLevel)
		or DEFAULT_MAX_LEVEL
	return math.max(
		1,
		math.floor(configuredMaxLevel)
	)
end

function CrewIncomeBalance.GetMaxLevelIncomeMultiplier()
	local configured = tonumber(getCrewConfig().MaxLevelIncomeMultiplier)
	if configured == nil or configured ~= configured or configured == math.huge or configured == -math.huge then
		return DEFAULT_MAX_LEVEL_INCOME_MULTIPLIER
	end

	return math.max(1, configured)
end

function CrewIncomeBalance.NormalizeLevel(level)
	local numeric = tonumber(level)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return 1
	end

	return math.clamp(math.floor(numeric), 1, CrewIncomeBalance.GetMaxLevel())
end

function CrewIncomeBalance.GetLevelIncomeMultiplier(level)
	local maxLevel = CrewIncomeBalance.GetMaxLevel()
	local progress = (CrewIncomeBalance.NormalizeLevel(level) - 1) / math.max(1, maxLevel - 1)
	return CrewIncomeBalance.GetMaxLevelIncomeMultiplier() ^ progress
end

function CrewIncomeBalance.GetBaseIncomeRange(rarity)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local cached = baseIncomeRangeCache[normalizedRarity]
	if cached then
		return cached.Min, cached.Max, normalizedRarity
	end

	local minValue, maxValue = getConfiguredRangeFromTable(getIncomeRollConfig(), normalizedRarity)
	baseIncomeRangeCache[normalizedRarity] = {
		Min = minValue,
		Max = maxValue,
	}
	return minValue, maxValue, normalizedRarity
end

function CrewIncomeBalance.GetBaseIncomeRangeMidpoint(rarity)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local cached = baseIncomeRangeMidpointCache[normalizedRarity]
	if cached ~= nil then
		return cached
	end

	local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(normalizedRarity)
	local midpoint = roundWhole((minValue + maxValue) / 2)
	baseIncomeRangeMidpointCache[normalizedRarity] = midpoint
	return midpoint
end

function CrewIncomeBalance.GetBaseIncomePercentile(rarity, baseIncomeRoll)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local normalizedRoll = CrewIncomeBalance.NormalizeBaseIncomeRoll(normalizedRarity, baseIncomeRoll)
	if normalizedRoll == nil then
		normalizedRoll = CrewIncomeBalance.GetBaseIncomeRangeMidpoint(normalizedRarity)
	end
	local key = cacheKey(normalizedRarity, normalizedRoll)
	local cached = baseIncomePercentileCache[key]
	if cached ~= nil then
		return cached
	end

	local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(normalizedRarity)
	if maxValue <= minValue then
		baseIncomePercentileCache[key] = 0
		return 0
	end

	local percentile = math.clamp((normalizedRoll - minValue) / (maxValue - minValue), 0, 1)
	baseIncomePercentileCache[key] = percentile
	return percentile
end

function CrewIncomeBalance.GetVariantIncomeRange(rarity, variant)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local variantKey = CrewIncomeBalance.NormalizeVariant(variant)
	local cacheId = cacheKey(normalizedRarity, variantKey)
	local cached = variantIncomeRangeCache[cacheId]
	if cached then
		return cached.Min, cached.Max, normalizedRarity, variantKey
	end

	local rarityBands = getVariantBandConfig()[normalizedRarity]
	local range = if typeof(rarityBands) == "table" then rarityBands[variantKey] else nil
	if typeof(range) ~= "table" then
		local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(normalizedRarity)
		variantIncomeRangeCache[cacheId] = {
			Min = minValue,
			Max = maxValue,
		}
		return minValue, maxValue, normalizedRarity, variantKey
	end

	local minValue = roundWhole(range.Min or 1)
	local maxValue = roundWhole(range.Max or minValue)
	if maxValue < minValue then
		maxValue = minValue
	end

	variantIncomeRangeCache[cacheId] = {
		Min = minValue,
		Max = maxValue,
	}
	return minValue, maxValue, normalizedRarity, variantKey
end

function CrewIncomeBalance.GetVariantBandMappedIncome(rarity, baseIncomeRoll, variant)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local variantKey = CrewIncomeBalance.NormalizeVariant(variant)
	local normalizedRoll = CrewIncomeBalance.NormalizeBaseIncomeRoll(normalizedRarity, baseIncomeRoll)
		or CrewIncomeBalance.GetBaseIncomeRangeMidpoint(normalizedRarity)
	local key = cacheKey(normalizedRarity, variantKey, normalizedRoll)
	local cached = variantBandMappedIncomeCache[key]
	if cached ~= nil then
		return cached
	end

	local percentile = CrewIncomeBalance.GetBaseIncomePercentile(normalizedRarity, normalizedRoll)
	local minValue, maxValue = CrewIncomeBalance.GetVariantIncomeRange(normalizedRarity, variantKey)
	local mapped = roundWhole(minValue + ((maxValue - minValue) * percentile))
	variantBandMappedIncomeCache[key] = mapped
	return mapped
end

function CrewIncomeBalance.RollBaseIncome(rarity, randomObject)
	local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(rarity)
	if maxValue <= minValue then
		return minValue
	end

	if typeof(randomObject) == "Random" then
		return randomObject:NextInteger(minValue, maxValue)
	end

	return math.random(minValue, maxValue)
end

function CrewIncomeBalance.NormalizeBaseIncomeRoll(rarity, value)
	local numeric = tonumber(value)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return nil
	end

	local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(rarity)
	return math.clamp(roundWhole(numeric), minValue, maxValue)
end

function CrewIncomeBalance.GetBaseIncomeRangeForVersion(rarity, version)
	local numericVersion = math.floor(tonumber(version) or CrewIncomeBalance.GetIncomeRollVersion())
	local versionConfig = BASE_INCOME_ROLL_RANGES_BY_VERSION[numericVersion]
	if typeof(versionConfig) == "table" then
		return getConfiguredRangeFromTable(versionConfig, rarity)
	end

	return CrewIncomeBalance.GetBaseIncomeRange(rarity)
end

function CrewIncomeBalance.NormalizeBaseIncomeRollForVersion(rarity, value, sourceVersion)
	local numeric = tonumber(value)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return nil
	end

	local currentVersion = CrewIncomeBalance.GetIncomeRollVersion()
	local numericSourceVersion = math.floor(tonumber(sourceVersion) or 1)
	local targetMin, targetMax = CrewIncomeBalance.GetBaseIncomeRange(rarity)
	if numericSourceVersion >= currentVersion then
		return math.clamp(roundWhole(numeric), targetMin, targetMax)
	end

	local sourceMin, sourceMax = CrewIncomeBalance.GetBaseIncomeRangeForVersion(rarity, numericSourceVersion)
	local percentile = 0
	if sourceMax > sourceMin then
		percentile = math.clamp((numeric - sourceMin) / (sourceMax - sourceMin), 0, 1)
	end

	return math.clamp(roundWhole(targetMin + ((targetMax - targetMin) * percentile)), targetMin, targetMax)
end

function CrewIncomeBalance.GetOrMigrateBaseIncome(rarity, value, sourceVersion, randomObject)
	local normalized = CrewIncomeBalance.NormalizeBaseIncomeRollForVersion(rarity, value, sourceVersion)
	if normalized ~= nil then
		return normalized, CrewIncomeBalance.GetIncomeRollVersion()
	end

	return CrewIncomeBalance.RollBaseIncome(rarity, randomObject), CrewIncomeBalance.GetIncomeRollVersion()
end

function CrewIncomeBalance.GetOrRollBaseIncome(rarity, value, randomObject)
	local numeric = tonumber(value)
	if numeric ~= nil and numeric == numeric and numeric ~= math.huge and numeric ~= -math.huge and numeric > 0 then
		return roundWhole(numeric)
	end

	return CrewIncomeBalance.RollBaseIncome(rarity, randomObject)
end

function CrewIncomeBalance.GetVariantIncomeMultiplier(variant)
	local variantKey = CrewIncomeBalance.NormalizeVariant(variant)
	local variantInfo = (CrewVariants.Versions or {})[variantKey]
	return math.max(0, tonumber(variantInfo and variantInfo.IncomeMult) or 1)
end

function CrewIncomeBalance.GetBaseVariantIncome(baseIncomeRoll, variant, rarity)
	local mappedIncome = CrewIncomeBalance.GetVariantBandMappedIncome(rarity, baseIncomeRoll, variant)
	-- Variant bands and variant multipliers are intentionally stacked so
	-- Golden and Diamond crewmates feel meaningfully more rewarding.
	return roundWhole(mappedIncome * CrewIncomeBalance.GetVariantIncomeMultiplier(variant))
end

function CrewIncomeBalance.GetFinalCrewIncome(baseIncomeRoll, variant, level, rarity)
	return CrewIncomeBalance.GetBaseVariantIncome(baseIncomeRoll, variant, rarity)
		* CrewIncomeBalance.GetLevelIncomeMultiplier(level)
end

function CrewIncomeBalance.ComputeIncome(baseIncomeRoll, variant, level, rarity)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local variantKey = CrewIncomeBalance.NormalizeVariant(variant)
	local normalizedRoll = CrewIncomeBalance.NormalizeBaseIncomeRoll(normalizedRarity, baseIncomeRoll)
		or CrewIncomeBalance.GetBaseIncomeRangeMidpoint(normalizedRarity)
	local normalizedLevel = CrewIncomeBalance.NormalizeLevel(level)
	local key = cacheKey(normalizedRarity, variantKey, normalizedLevel, normalizedRoll)
	local cached = computeIncomeCache[key]
	if cached ~= nil then
		return cached
	end

	local income = roundWhole(CrewIncomeBalance.GetFinalCrewIncome(normalizedRoll, variantKey, normalizedLevel, normalizedRarity))
	computeIncomeCache[key] = income
	return income
end

function CrewIncomeBalance.GetRawBankIncomePerSecond(instanceData)
	if typeof(instanceData) ~= "table" then
		return 0
	end

	local rarity = CrewIncomeBalance.NormalizeRarity(instanceData.Rarity)
	local variant = CrewIncomeBalance.NormalizeVariant(instanceData.Variant)
	local baseIncomeRoll = tonumber(instanceData.BaseIncomeRoll)
	if
		baseIncomeRoll == nil
		or baseIncomeRoll ~= baseIncomeRoll
		or baseIncomeRoll == math.huge
		or baseIncomeRoll == -math.huge
		or baseIncomeRoll <= 0
	then
		baseIncomeRoll = CrewIncomeBalance.GetBaseIncomeRangeMidpoint(rarity)
	else
		baseIncomeRoll = roundWhole(baseIncomeRoll)
	end

	return CrewIncomeBalance.GetBaseVariantIncome(baseIncomeRoll, variant, rarity)
end

function CrewIncomeBalance.GetClaimMultiplier(level, extraMultipliers)
	return CrewIncomeBalance.GetLevelIncomeMultiplier(level) * multiplyExtraMultipliers(extraMultipliers)
end

function CrewIncomeBalance.GetClaimableFromRaw(rawIncome, claimMultiplier)
	local raw = sanitizeNonNegativeNumber(rawIncome)
	local multiplier = sanitizeNonNegativeNumber(claimMultiplier)
	local exactAmount = raw * multiplier
	if exactAmount <= 0 then
		return 0, 0
	end

	return math.max(0, math.floor(exactAmount + CLAIM_EPSILON)), exactAmount
end

function CrewIncomeBalance.GetRawRemainderAfterClaim(rawIncome, claimMultiplier, claimedAmount)
	local raw = sanitizeNonNegativeNumber(rawIncome)
	local multiplier = sanitizeNonNegativeNumber(claimMultiplier)
	if raw <= 0 or multiplier <= 0 then
		return 0, 0
	end

	local claimed = math.max(0, math.floor(sanitizeNonNegativeNumber(claimedAmount)))
	local exactAmount = raw * multiplier
	local remainingExactAmount = exactAmount - claimed
	if remainingExactAmount <= CLAIM_EPSILON then
		return 0, 0
	end

	return remainingExactAmount / multiplier, remainingExactAmount
end

function CrewIncomeBalance.GetVariantUpgradeCostMultiplier(variant)
	local variantKey = CrewIncomeBalance.NormalizeVariant(variant)
	local configured = getCrewConfig().VariantUpgradeCostMultiplier or {}
	return math.max(0.01, tonumber(configured[variantKey]) or 1)
end

function CrewIncomeBalance.GetRangeDisplayIncome(rarity, variant, level)
	local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(rarity)
	return CrewIncomeBalance.ComputeIncome(minValue, variant, level, rarity), CrewIncomeBalance.ComputeIncome(maxValue, variant, level, rarity)
end

return CrewIncomeBalance
