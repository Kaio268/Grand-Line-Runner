local SpawnParts = {
	DefaultLuckMult = 1,

	LuckMult = {
		Common = 100,
		Uncommon = 50,
		Rare = 20,
		Epic = 4,
		Legendary = .2,
		Mythic = .02,
		Mythical = .004,
		Godly = .0008,
		Secret = .0004,
		Omega = .00008,
	},

	RarityTier = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,

		Mythic = 6,
		Mythical = 6,  

		Godly = 7,
		Secret = 8,
		Omega = 9,
	},

	Placement = {
		PartName = "Platform",
		RarityAttribute = "PlacementRarity",
		TierAttribute = "PlacementTier",
		BiomeRarityField = "PlacementRarity",
		BiomeFallbackRarityField = "Rarity",
		DefaultRarity = "Common",
	},
}

function SpawnParts.GetPlacementPartName()
	return tostring((SpawnParts.Placement and SpawnParts.Placement.PartName) or "Platform")
end

function SpawnParts.GetPlacementSurfaceNames()
	return { SpawnParts.GetPlacementPartName() }
end

function SpawnParts.IsPlacementPart(instance)
	return instance
		and instance:IsA("BasePart")
		and instance.Name == SpawnParts.GetPlacementPartName()
end

function SpawnParts.GetPlacementRarityForBiome(biomeIndex, biomeAreas)
	local placement = SpawnParts.Placement or {}
	local biomeEntry = biomeAreas and biomeAreas.GetBiome and biomeAreas.GetBiome(biomeIndex) or nil
	if type(biomeEntry) == "table" then
		local rarity = biomeEntry[tostring(placement.BiomeRarityField or "PlacementRarity")]
		if rarity == nil or rarity == "" then
			rarity = biomeEntry[tostring(placement.BiomeFallbackRarityField or "Rarity")]
		end
		if rarity ~= nil and tostring(rarity) ~= "" then
			return tostring(rarity)
		end
	end

	return tostring(placement.DefaultRarity or "Common")
end

function SpawnParts.GetPlacementRarityForPart(part, biomeIndex, biomeAreas)
	local placement = SpawnParts.Placement or {}
	local attributeName = tostring(placement.RarityAttribute or "PlacementRarity")
	local attributeRarity = part and part:GetAttribute(attributeName) or nil
	if attributeRarity ~= nil and tostring(attributeRarity) ~= "" then
		return tostring(attributeRarity)
	end

	return SpawnParts.GetPlacementRarityForBiome(biomeIndex, biomeAreas)
end

function SpawnParts.GetPlacementTierForPart(part, biomeIndex, biomeAreas)
	local placement = SpawnParts.Placement or {}
	local tierAttributeName = tostring(placement.TierAttribute or "PlacementTier")
	local attributeTier = tonumber(part and part:GetAttribute(tierAttributeName))
	if attributeTier ~= nil then
		return attributeTier
	end

	local rarity = SpawnParts.GetPlacementRarityForPart(part, biomeIndex, biomeAreas)
	return tonumber(SpawnParts.RarityTier[rarity]) or tonumber(SpawnParts.RarityTier[placement.DefaultRarity]) or 1
end

return SpawnParts
