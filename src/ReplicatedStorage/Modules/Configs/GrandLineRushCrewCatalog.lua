local CrewCatalog = {
	Starter = {
		Name = "Deckhand Rookie",
		Rarity = "Common",
	},

	ByRarity = {
		Common = {
			"Deckhand Rookie",
			"Galley Hand",
			"Cabin Runner",
			"Mast Climber",
		},
		Uncommon = {
			"Navigator Scout",
			"Sailmaker",
			"Powder Keeper",
		},
		Rare = {
			"Storm Helmsman",
			"Harpoon Officer",
			"Wave Chaser",
		},
		Epic = {
			"Tempest Cook",
			"Star Reader",
			"Deepwater Raider",
		},
		Legendary = {
			"Grand Navigator",
			"Sea King Hunter",
			"Thunder Captain",
		},
		Mythical = {
			"Sunlit Corsair",
			"Phoenix Quartermaster",
		},
		Celestial = {
			"Celestial Wayfinder",
			"Starlight Admiral",
		},
		Godly = {
			"Godwave Monarch",
			"Horizon Sovereign",
		},
		Secret = {
			"Secret Tidebreaker",
			"Void Corsair",
		},
	},
}

function CrewCatalog.GetNamesForRarity(rarity)
	return CrewCatalog.ByRarity[rarity] or {}
end

function CrewCatalog.GetRandomNameForRarity(rarity, randomObject)
	local names = CrewCatalog.GetNamesForRarity(rarity)
	if #names == 0 then
		return string.format("%s Crew", tostring(rarity or "Unknown"))
	end

	local rng = randomObject or Random.new()
	return names[rng:NextInteger(1, #names)]
end

return CrewCatalog
