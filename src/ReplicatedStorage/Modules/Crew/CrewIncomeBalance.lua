local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local Economy = require(Configs:WaitForChild("GrandLineRushEconomy"))
local CrewVariants = require(Configs:WaitForChild("CrewVariants"))

local CrewIncomeBalance = {}

local DEFAULT_RARITY = "Common"
local DEFAULT_VARIANT = "Normal"

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
	local normalized = CrewIncomeBalance.NormalizeBaseIncomeRoll(rarity, value)
	if normalized ~= nil then
		return normalized
	end

	return CrewIncomeBalance.RollBaseIncome(rarity, randomObject)
end

function CrewIncomeBalance.GetVariantIncomeMultiplier(variant)
	local variantKey = CrewIncomeBalance.NormalizeVariant(variant)
	local variantInfo = (CrewVariants.Versions or {})[variantKey]
	return math.max(0, tonumber(variantInfo and variantInfo.IncomeMult) or 1)
end

function CrewIncomeBalance.ComputeIncome(baseIncomeRoll, variant)
	return roundWhole((tonumber(baseIncomeRoll) or 0) * CrewIncomeBalance.GetVariantIncomeMultiplier(variant))
end

function CrewIncomeBalance.GetVariantUpgradeCostMultiplier(variant)
	local variantKey = CrewIncomeBalance.NormalizeVariant(variant)
	local configured = getCrewConfig().VariantUpgradeCostMultiplier or {}
	return math.max(0.01, tonumber(configured[variantKey]) or 1)
end

function CrewIncomeBalance.GetRangeDisplayIncome(rarity, variant)
	local minValue, maxValue = CrewIncomeBalance.GetBaseIncomeRange(rarity)
	local mult = CrewIncomeBalance.GetVariantIncomeMultiplier(variant)
	return roundWhole(minValue * mult), roundWhole(maxValue * mult)
end

return CrewIncomeBalance
