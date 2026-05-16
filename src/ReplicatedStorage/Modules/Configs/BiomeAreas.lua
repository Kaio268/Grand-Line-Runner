local BiomeAreas = {}

BiomeAreas.ActiveBiomeAttribute = "ActiveBiomeLightingBiome"
BiomeAreas.ActiveAreaAttribute = "ActiveBiomeLightingArea"
BiomeAreas.StartingAreaKey = "StartingArea"

local function getBiomeAreaKey(index)
	local biomeIndex = tonumber(index)
	if not biomeIndex then
		return nil
	end

	return "Biome" .. tostring(biomeIndex)
end

BiomeAreas.Ui = {
	DisplayOrder = 122,
	TopOffset = 106,
	WidthScale = 0.82,
	Height = 84,
	MinWidth = 280,
	MaxWidth = 500,
}

BiomeAreas.Animation = {
	FadeInTime = 0.28,
	HoldTime = 2,
	FadeOutTime = 0.42,
	SlideOffset = 18,
}

BiomeAreas.RarityStyles = {
	Common = {
		AccentColor = Color3.fromRGB(204, 213, 224),
		GlowColor = Color3.fromRGB(172, 205, 232),
	},
	Uncommon = {
		AccentColor = Color3.fromRGB(91, 226, 137),
		GlowColor = Color3.fromRGB(62, 205, 137),
	},
	Rare = {
		AccentColor = Color3.fromRGB(88, 177, 255),
		GlowColor = Color3.fromRGB(63, 167, 255),
	},
	Epic = {
		AccentColor = Color3.fromRGB(190, 113, 255),
		GlowColor = Color3.fromRGB(180, 89, 255),
	},
	Legendary = {
		AccentColor = Color3.fromRGB(255, 199, 82),
		GlowColor = Color3.fromRGB(255, 184, 58),
	},
	Mythic = {
		AccentColor = Color3.fromRGB(255, 99, 170),
		GlowColor = Color3.fromRGB(255, 73, 159),
	},
	Godly = {
		AccentColor = Color3.fromRGB(105, 246, 255),
		GlowColor = Color3.fromRGB(71, 232, 255),
	},
	Secret = {
		AccentColor = Color3.fromRGB(255, 86, 100),
		GlowColor = Color3.fromRGB(255, 55, 76),
	},
}

BiomeAreas.StartingArea = {
	AreaKey = BiomeAreas.StartingAreaKey,
	BiomeName = "Starting Area",
	AreaName = "Starting Area",
}

BiomeAreas.Biomes = {
	[1] = {
		AreaKey = getBiomeAreaKey(1),
		BiomeName = "Biome 1",
		AreaName = "Foosha Village",
		ProgressColor = Color3.fromRGB(102, 166, 111),
		Rarity = "Common",
		Tier = 1,
	},
	[2] = {
		AreaKey = getBiomeAreaKey(2),
		BiomeName = "Biome 2",
		AreaName = "Arlong Park",
		ProgressColor = Color3.fromRGB(70, 173, 176),
		Rarity = "Uncommon",
		Tier = 2,
	},
	[3] = {
		AreaKey = getBiomeAreaKey(3),
		BiomeName = "Biome 3",
		AreaName = "Drum Island",
		ProgressColor = Color3.fromRGB(126, 184, 226),
		Rarity = "Rare",
		Tier = 3,
	},
	[4] = {
		AreaKey = getBiomeAreaKey(4),
		BiomeName = "Biome 4",
		AreaName = "Alabasta",
		ProgressColor = Color3.fromRGB(211, 162, 91),
		Rarity = "Epic",
		Tier = 4,
	},
	[5] = {
		AreaKey = getBiomeAreaKey(5),
		BiomeName = "Biome 5",
		AreaName = "Water 7",
		ProgressColor = Color3.fromRGB(89, 151, 214),
		Rarity = "Legendary",
		Tier = 5,
	},
	[6] = {
		AreaKey = getBiomeAreaKey(6),
		BiomeName = "Biome 6",
		AreaName = "Thriller Bark",
		ProgressColor = Color3.fromRGB(143, 107, 171),
		Rarity = "Mythic",
		Tier = 6,
	},
	[7] = {
		AreaKey = getBiomeAreaKey(7),
		BiomeName = "Biome 7",
		AreaName = "Sabaody",
		ProgressColor = Color3.fromRGB(93, 190, 199),
		Rarity = "Godly",
		Tier = 7,
	},
	[8] = {
		AreaKey = getBiomeAreaKey(8),
		BiomeName = "Biome 8",
		AreaName = "Dressrosa",
		ProgressColor = Color3.fromRGB(196, 98, 118),
		Rarity = "Secret",
		Tier = 8,
	},
}

BiomeAreas.Areas = {
	[BiomeAreas.StartingAreaKey] = BiomeAreas.StartingArea,
}

for index, entry in pairs(BiomeAreas.Biomes) do
	local areaKey = entry.AreaKey or getBiomeAreaKey(index)
	entry.AreaKey = areaKey
	BiomeAreas.Areas[areaKey] = entry
end

function BiomeAreas.GetBiomeAreaKey(index)
	return getBiomeAreaKey(index)
end

function BiomeAreas.GetBiome(index)
	return BiomeAreas.Biomes[tonumber(index)]
end

function BiomeAreas.GetArea(areaKey)
	if type(areaKey) == "number" then
		return BiomeAreas.GetBiome(areaKey)
	end

	local key = tostring(areaKey or "")
	if key == "" then
		return nil
	end

	local direct = BiomeAreas.Areas[key]
	if direct then
		return direct
	end

	local biomeIndex = key:match("^Biome(%d+)$")
	if biomeIndex then
		return BiomeAreas.GetBiome(biomeIndex)
	end

	return nil
end

function BiomeAreas.GetRarityStyle(rarity)
	return BiomeAreas.RarityStyles[tostring(rarity or "")] or BiomeAreas.RarityStyles.Common
end

function BiomeAreas.GetSubtitle(entry)
	if not entry then
		return ""
	end

	if entry.Rarity == nil and entry.Tier == nil then
		return ""
	end

	return string.format("%s  /  TIER %d", string.upper(tostring(entry.Rarity or "Common")), tonumber(entry.Tier) or 1)
end

return BiomeAreas
