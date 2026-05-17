local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))

local CrewStacking = {}

CrewStacking.DefaultMaxStack = 5

CrewStacking.MaxStackByRarity = {
	Common = 10,
	Uncommon = 8,
	Rare = 6,
	Epic = 5,
	Legendary = 3,
	Mythic = 2,
	Mythical = 2,
	Godly = 1,
	Secret = 1,
}

local RARITY_BY_LOWER = {
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

local function trim(value)
	return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function CrewStacking.NormalizeRarity(rarity)
	local value = trim(rarity)
	if value == "" then
		return "Common"
	end

	return RARITY_BY_LOWER[string.lower(value)] or value
end

function CrewStacking.GetMaxStackForRarity(rarity)
	local normalized = CrewStacking.NormalizeRarity(rarity)
	local maxStack = tonumber(CrewStacking.MaxStackByRarity[normalized]) or CrewStacking.DefaultMaxStack
	return math.max(1, math.floor(maxStack))
end

function CrewStacking.GetMaxStackForCrewMemberId(crewMemberId)
	local _, info = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	return CrewStacking.GetMaxStackForRarity(info and info.Rarity or nil)
end

return CrewStacking
