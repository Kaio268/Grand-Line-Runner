local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local Economy = require(Configs:WaitForChild("GrandLineRushEconomy"))
local CrewVariants = require(Configs:WaitForChild("CrewVariants"))

local CrewIncomeBalance = {}

local DEFAULT_RARITY = "Common"
local DEFAULT_VARIANT = "Normal"
local DEFAULT_MAX_LEVEL = 50
local LEVEL_INCOME_BASE = 1.2
local CLAIM_EPSILON = 1e-7

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

local function roundWhole(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
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
	return math.max(1, math.floor(tonumber(crewConfig.MaxLevel) or tonumber(rules.CrewMaxLevel) or DEFAULT_MAX_LEVEL))
end

function CrewIncomeBalance.NormalizeLevel(level)
	local numeric = tonumber(level)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return 1
	end

	return math.clamp(math.floor(numeric), 1, CrewIncomeBalance.GetMaxLevel())
end

function CrewIncomeBalance.GetLevelIncomeMultiplier(level)
	return LEVEL_INCOME_BASE ^ (CrewIncomeBalance.NormalizeLevel(level) - 1)
end

function CrewIncomeBalance.GetBaseIncomeRange(rarity)
	local normalizedRarity = CrewIncomeBalance.NormalizeRarity(rarity)
	local range = getIncomeRollConfig()[normalizedRarity]
	if typeof(range) ~= "table" then
		range = getIncomeRollConfig()[DEFAULT_RARITY]
	end

	local minValue = roundWhole(range and range.Min or 1)
	local maxValue = roundWhole(range and range.Max or minValue)
	if maxValue < minValue then
		maxValue = minValue
	end

	return minValue, maxValue, normalizedRarity
end

function CrewIncomeBalance.GetBaseIncomeRangeMidpoint(rarity)
	local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(rarity)
	return roundWhole((minValue + maxValue) / 2)
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

function CrewIncomeBalance.GetBaseVariantIncome(baseIncomeRoll, variant)
	return roundWhole((tonumber(baseIncomeRoll) or 0) * CrewIncomeBalance.GetVariantIncomeMultiplier(variant))
end

function CrewIncomeBalance.GetFinalCrewIncome(baseIncomeRoll, variant, level)
	return CrewIncomeBalance.GetBaseVariantIncome(baseIncomeRoll, variant)
		* CrewIncomeBalance.GetLevelIncomeMultiplier(level)
end

function CrewIncomeBalance.ComputeIncome(baseIncomeRoll, variant, level)
	return roundWhole(CrewIncomeBalance.GetFinalCrewIncome(baseIncomeRoll, variant, level))
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

	return CrewIncomeBalance.GetBaseVariantIncome(baseIncomeRoll, variant)
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
	return CrewIncomeBalance.ComputeIncome(minValue, variant, level), CrewIncomeBalance.ComputeIncome(maxValue, variant, level)
end

return CrewIncomeBalance
