local BiomeAreas = {}

BiomeAreas.ActiveBiomeAttribute = "ActiveBiomeLightingBiome"

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

BiomeAreas.Biomes = {
	[1] = {
		BiomeName = "Biome 1",
		AreaName = "Foosha Village",
		Rarity = "Common",
		Tier = 1,
	},
	[2] = {
		BiomeName = "Biome 2",
		AreaName = "Arlong Park",
		Rarity = "Uncommon",
		Tier = 2,
	},
	[3] = {
		BiomeName = "Biome 3",
		AreaName = "Drum Island",
		Rarity = "Rare",
		Tier = 3,
	},
	[4] = {
		BiomeName = "Biome 4",
		AreaName = "Alabasta",
		Rarity = "Epic",
		Tier = 4,
	},
	[5] = {
		BiomeName = "Biome 5",
		AreaName = "Water 7",
		Rarity = "Legendary",
		Tier = 5,
	},
	[6] = {
		BiomeName = "Biome 6",
		AreaName = "Thriller Bark",
		Rarity = "Mythic",
		Tier = 6,
	},
	[7] = {
		BiomeName = "Biome 7",
		AreaName = "Sabaody",
		Rarity = "Godly",
		Tier = 7,
	},
	[8] = {
		BiomeName = "Biome 8",
		AreaName = "Dresserosa",
		Rarity = "Secret",
		Tier = 8,
	},
}

function BiomeAreas.GetBiome(index)
	return BiomeAreas.Biomes[tonumber(index)]
end

function BiomeAreas.GetRarityStyle(rarity)
	return BiomeAreas.RarityStyles[tostring(rarity or "")] or BiomeAreas.RarityStyles.Common
end

function BiomeAreas.GetSubtitle(entry)
	if not entry then
		return ""
	end

	return string.format("%s  /  TIER %d", string.upper(tostring(entry.Rarity or "Common")), tonumber(entry.Tier) or 1)
end

return BiomeAreas
