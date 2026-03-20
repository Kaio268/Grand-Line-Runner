local Config = {
	Crew = {
		MinimumBaseBounty = 100,
		LevelMultiplierPerLevel = 0.07,
		RarityBaseByRarity = {
			Common = 120,
			Uncommon = 360,
			Rare = 820,
			Epic = 1500,
			Legendary = 2600,
			Mythical = 4200,
			Celestial = 6800,
			Godly = 10500,
			Secret = 16500,
		},
		IncomeWeightByRarity = {
			Common = 18,
			Uncommon = 22,
			Rare = 28,
			Epic = 36,
			Legendary = 46,
			Mythical = 58,
			Celestial = 72,
			Godly = 88,
			Secret = 110,
		},
		TypeBaseByStorageName = {},
	},
	Extraction = {
		ChestBountyByTier = {
			Wooden = 250,
			Iron = 650,
			Gold = 1600,
			Legendary = 4200,
		},
		CrewBountyByRarity = {
			Common = 180,
			Uncommon = 320,
			Rare = 600,
			Epic = 950,
			Legendary = 1500,
			Mythical = 2400,
			Celestial = 3600,
			Godly = 5400,
			Secret = 8200,
		},
	},
	Display = {
		LeaderstatKey = "Bounty",
		PopupDuration = 3,
	},
}

return Config
