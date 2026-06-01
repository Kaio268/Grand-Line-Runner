local TitlePerks = {}

TitlePerks.Order = {
	"SpeedPercent",
	"BeliPercent",
	"BountyPercent",
}

TitlePerks.Definitions = {
	SpeedPercent = {
		Key = "SpeedPercent",
		DisplayName = "Speed",
		Description = "Increases base movement speed for the equipped title.",
		EffectName = "SpeedMultiplier",
		EffectType = "PercentMultiplier",
	},
	BeliPercent = {
		Key = "BeliPercent",
		DisplayName = "Beli",
		Description = "Increases money earned from captains, crew income, and other Beli sources.",
		EffectName = "BeliMultiplier",
		EffectType = "PercentMultiplier",
	},
	BountyPercent = {
		Key = "BountyPercent",
		DisplayName = "Bounty",
		Description = "Increases bounty totals from extraction and crew contributions.",
		EffectName = "BountyMultiplier",
		EffectType = "PercentMultiplier",
	},
}

local function cloneTable(value)
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, item in pairs(value) do
		result[key] = item
	end

	return result
end

local function normalizePerks(perks)
	if typeof(perks) ~= "table" then
		return {}
	end

	local normalized = {}
	for _, key in ipairs(TitlePerks.Order) do
		normalized[key] = perks[key]
	end
	return normalized
end

local function toNumber(value)
	return math.max(0, tonumber(value) or 0)
end

function TitlePerks.GetDefinition(perkKey)
	return TitlePerks.Definitions[perkKey]
end

function TitlePerks.GetDefinitions()
	local results = {}
	for _, key in ipairs(TitlePerks.Order) do
		local definition = TitlePerks.Definitions[key]
		if definition then
			results[#results + 1] = cloneTable(definition)
		end
	end
	return results
end

function TitlePerks.GetPerkValue(perks, perkKey)
	if typeof(perks) ~= "table" then
		return 0
	end

	return toNumber(perks[perkKey])
end

function TitlePerks.FormatPerkLabel(perkKey, value)
	local definition = TitlePerks.GetDefinition(perkKey)
	value = toNumber(value)
	if not definition then
		return string.format("%s %d%%", tostring(perkKey), value)
	end

	return string.format("%s +%d%%", definition.DisplayName, value)
end

function TitlePerks.GetDisplayLabels(perks)
	local labels = {}
	for _, key in ipairs(TitlePerks.Order) do
		local value = TitlePerks.GetPerkValue(perks, key)
		if value > 0 then
			labels[#labels + 1] = TitlePerks.FormatPerkLabel(key, value)
		end
	end
	return labels
end

function TitlePerks.GetPercentMultiplier(value)
	return 1 + (toNumber(value) / 100)
end

function TitlePerks.GetEffectMultipliers(perks)
	perks = normalizePerks(perks)

	return {
		SpeedMultiplier = TitlePerks.GetPercentMultiplier(perks.SpeedPercent),
		BeliMultiplier = TitlePerks.GetPercentMultiplier(perks.BeliPercent),
		BountyMultiplier = TitlePerks.GetPercentMultiplier(perks.BountyPercent),
	}
end

function TitlePerks.GetEffectNames()
	local names = {}
	for _, definition in ipairs(TitlePerks.GetDefinitions()) do
		names[#names + 1] = definition.EffectName
	end
	return names
end

return TitlePerks
