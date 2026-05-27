local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig")
)

local Pricing = {}

local function rarityTextMatches(text, rarityKey)
	local lowered = string.lower(tostring(text or ""))
	local rarity = string.lower(tostring(rarityKey or ""))
	return lowered == rarity or string.find(lowered, rarity, 1, true) ~= nil
end

local function normalizeRarity(rarity)
	local text = tostring(rarity or "")
	if text == "" then
		return "Common"
	end

	local lowered = string.lower(text)
	for aliasKey, rarityKey in pairs(Config.RarityAliases or {}) do
		if rarityTextMatches(lowered, aliasKey) then
			return tostring(rarityKey)
		end
	end

	for unsupportedKey, unsupported in pairs(Config.UnsupportedRarities or {}) do
		if unsupported == true and rarityTextMatches(lowered, unsupportedKey) then
			return nil, "unsupported_rarity"
		end
	end

	for _, rarityKey in ipairs(Config.RarityPriority or {}) do
		if string.find(lowered, string.lower(rarityKey), 1, true) then
			return rarityKey
		end
	end

	return nil, "unsupported_rarity"
end

local function normalizeVariant(variant)
	local text = tostring(variant or "")
	if text == "" then
		return "Normal"
	end

	for variantKey in pairs(Config.VariantMultipliers or {}) do
		if string.lower(text) == string.lower(variantKey) then
			return variantKey
		end
	end

	return "Normal"
end

local function getLevelMultiplier(level)
	local safeLevel = math.max(1, math.floor(tonumber(level) or 1))
	for _, bracket in ipairs(Config.LevelMultipliers or {}) do
		local minLevel = math.max(1, math.floor(tonumber(bracket.MinLevel) or 1))
		local maxLevel = tonumber(bracket.MaxLevel) or math.huge
		if safeLevel >= minLevel and safeLevel <= maxLevel then
			return tonumber(bracket.Multiplier) or 1
		end
	end

	return 1
end

function Pricing.NormalizeRarity(rarity)
	return normalizeRarity(rarity)
end

function Pricing.NormalizeVariant(variant)
	return normalizeVariant(variant)
end

function Pricing.GetLevelMultiplier(level)
	return getLevelMultiplier(level)
end

function Pricing.ComputeDesiredPrice(snapshot)
	snapshot = if typeof(snapshot) == "table" then snapshot else {}

	local rarity, rarityReason = normalizeRarity(snapshot.Rarity)
	if not rarity then
		return nil, {
			Reason = rarityReason or "unsupported_rarity",
			RawRarity = snapshot.Rarity,
		}
	end

	local variant = normalizeVariant(snapshot.Variant)
	local level = math.max(1, math.floor(tonumber(snapshot.Level) or 1))

	local rarityBase = tonumber((Config.RarityBasePrices or {})[rarity])
	if not rarityBase then
		return nil, {
			Reason = "unsupported_rarity",
			RawRarity = snapshot.Rarity,
			Rarity = rarity,
		}
	end

	local levelMultiplier = getLevelMultiplier(level)
	local variantMultiplier = tonumber((Config.VariantMultipliers or {})[variant]) or 1
	local rawPrice = rarityBase * levelMultiplier * variantMultiplier
	local cappedPrice = math.min(rawPrice, tonumber(Config.MaxPriceRobux) or 2999)

	return math.max(1, math.floor(cappedPrice + 0.5)), {
		Rarity = rarity,
		Variant = variant,
		Level = level,
		RarityBase = rarityBase,
		LevelMultiplier = levelMultiplier,
		VariantMultiplier = variantMultiplier,
		RawPrice = rawPrice,
	}
end

function Pricing.GetBucket(snapshot)
	local desiredPrice, detail = Pricing.ComputeDesiredPrice(snapshot)
	if desiredPrice == nil then
		return nil, nil, detail
	end

	local bucket = Config.GetBucketForPrice(desiredPrice)
	return bucket, desiredPrice, detail
end

return Pricing
