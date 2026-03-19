local Economy = {
	Version = "v1",

	Currency = {
		Primary = {
			Key = "Doubloons",
			Path = "leaderstats.Doubloons",
			TotalKey = "TotalDoubloons",
			TotalPath = "TotalStats.TotalDoubloons",
			DisplayName = "Doubloons",
			ShortLabel = "D",
			LegacyKeys = {
				Leaderstat = "Money",
				LeaderstatTypo = "Moeny",
				Total = "TotalMoney",
			},
		},
	},

	PathAliases = {
		["leaderstats.Doubloons"] = {
			"leaderstats.Money",
			"leaderstats.Moeny",
		},
		["TotalStats.TotalDoubloons"] = {
			"TotalStats.TotalMoney",
		},
		["HiddenLeaderstats.PlotUpgrade"] = {
			"HiddenLeadderstats.PlotUpgrade",
		},
		["Materials.Timber"] = {
			"Materials.CommonShipMaterial",
		},
		["Materials.Iron"] = {
			"Materials.RareShipMaterial",
		},
	},

	Rules = {
		PrimaryCurrencyReplacesMoney = true,
		GlobalChefSlots = 1,
		MajorRewardCarryLimit = 1,
		ChestsAreExtractedThenOpenedAtBase = true,
		ChestsCanDropCrew = false,
		CrewLevelsArePerInstance = true,
		CrewMaxLevel = 50,
		DuplicateCrewHandling = "StoreAsSeparateInstances",
		MaxShipSlots = 24,
		LoseUnextractedRewardsOnRunFailure = true,
	},

	Tutorial = {
		StartingDoubloons = 200,
	},

	VerticalSlice = {
		Enabled = true,
		DeveloperPanelEnabled = false,
		DeveloperPanelStudioOnly = true,
		DefaultDepthBand = "Mid",
		DepthBands = {
			"Shallow",
			"Mid",
			"Deep",
			"Abyssal",
		},
		ChestStageByDepthBand = {
			Shallow = "Early",
			Mid = "Mid",
			Deep = "Strong",
			Abyssal = "Elite",
		},
		StarterCrew = {
			Enabled = true,
			Name = "Deckhand Rookie",
			Rarity = "Common",
		},
		Remotes = {
			RequestName = "GrandLineRushSliceRequest",
			StateEventName = "GrandLineRushSliceState",
		},
		WorldRun = {
			Enabled = true,
			StartDepthBand = "Deep",
			PromptHoldDuration = 0.25,
			PromptMaxDistance = 14,
			RewardHeightOffset = 3.5,
			DebugChestSpawnAlphaOverride = 0.12,
			RewardAlphaByDepthBand = {
				Shallow = 0.25,
				Mid = 0.5,
				Deep = 0.76,
				Abyssal = 0.9,
			},
			RewardLaneSpacing = 5,
			RewardMaxLaneOffset = 10,
			ExtractionZoneSize = Vector3.new(20, 8, 20),
			StartHubSize = Vector3.new(16, 1, 16),
			SharedChests = {
				Enabled = true,
				MaxActive = 3,
				RespawnCheckInterval = 5,
				RespawnDelay = 10,
				SpawnTierToDepthBand = {
					[1] = "Shallow",
					[2] = "Shallow",
					[3] = "Mid",
					[4] = "Mid",
					[5] = "Deep",
					[6] = "Deep",
					[7] = "Abyssal",
					[8] = "Abyssal",
					[9] = "Abyssal",
				},
			},
		},
	},

	PlaceholderBaseUI = {
		Enabled = false,
		ToggleButtonText = "Ship Meta",
	},

	Food = {
		Apple = {
			DisplayName = "Apple",
			XP = 5,
		},
		Rice = {
			DisplayName = "Rice",
			XP = 15,
		},
		Meat = {
			DisplayName = "Meat",
			XP = 50,
		},
		SeaBeastMeat = {
			DisplayName = "Sea Beast Meat",
			XP = 175,
		},
	},

	Brainrots = {
		MaxLevel = 50,
		FoodAutoFeedPriority = {
			"Apple",
			"Rice",
			"Meat",
			"SeaBeastMeat",
		},
		BaseXPPerLevelBand = {
			{ MinLevel = 1, MaxLevel = 10, XPPerLevel = 40 },
			{ MinLevel = 11, MaxLevel = 20, XPPerLevel = 70 },
			{ MinLevel = 21, MaxLevel = 30, XPPerLevel = 120 },
			{ MinLevel = 31, MaxLevel = 40, XPPerLevel = 210 },
			{ MinLevel = 41, MaxLevel = 50, XPPerLevel = 360 },
		},
		TotalXPMultiplierByRarity = {
			Common = 1.00,
			Uncommon = 1.20,
			Rare = 1.50,
			Epic = 1.90,
			Legendary = 2.40,
			Mythical = 3.10,
			Celestial = 4.00,
			Godly = 5.20,
			Secret = 6.80,
		},
	},

	Chests = {
		Tiers = {
			Wooden = {
				DepthBand = "Early",
				AverageFoodXP = 35,
				Rewards = {
					Food = {
						Apple = 4,
						Rice = 1,
					},
					Doubloons = 15,
					Materials = {
						CommonShipMaterial = 1,
					},
				},
			},
			Iron = {
				DepthBand = "EarlyMid",
				AverageFoodXP = 60,
				Rewards = {
					Food = {
						Apple = 6,
						Rice = 2,
					},
					Doubloons = 30,
					Materials = {
						CommonShipMaterial = 2,
					},
				},
			},
			Gold = {
				DepthBand = "MidDeep",
				AverageFoodXP = 130,
				Rewards = {
					Food = {
						Rice = 2,
						Meat = 2,
					},
					Doubloons = 60,
					Materials = {
						RareShipMaterial = 1,
						CommonShipMaterial = 1,
					},
				},
			},
			Legendary = {
				DepthBand = "Deep",
				AverageFoodXP = 275,
				Rewards = {
					Food = {
						Meat = 2,
						SeaBeastMeat = 1,
					},
					Doubloons = 120,
					Materials = {
						RareShipMaterial = 2,
					},
					DevilFruitChance = 0.10,
				},
			},
		},

		ExpectedTierDistributionByStage = {
			Early = {
				Wooden = 60,
				Iron = 30,
				Gold = 10,
				Legendary = 0,
			},
			Mid = {
				Wooden = 25,
				Iron = 45,
				Gold = 25,
				Legendary = 5,
			},
			Strong = {
				Wooden = 10,
				Iron = 30,
				Gold = 40,
				Legendary = 20,
			},
			Elite = {
				Wooden = 5,
				Iron = 15,
				Gold = 35,
				Legendary = 45,
			},
		},
	},

	Chef = {
		BankCapHours = 12,
		XPPerHourByRarity = {
			Common = 12,
			Uncommon = 20,
			Rare = 32,
			Epic = 50,
			Legendary = 80,
			Mythical = 120,
			Celestial = 180,
			Godly = 260,
			Secret = 420,
		},
	},

	Crew = {
		RarityOrder = {
			"Common",
			"Uncommon",
			"Rare",
			"Epic",
			"Legendary",
			"Mythical",
			"Celestial",
			"Godly",
			"Secret",
		},

		BaseXPPerLevelBand = {
			{ MinLevel = 1, MaxLevel = 10, XPPerLevel = 40 },
			{ MinLevel = 11, MaxLevel = 20, XPPerLevel = 70 },
			{ MinLevel = 21, MaxLevel = 30, XPPerLevel = 120 },
			{ MinLevel = 31, MaxLevel = 40, XPPerLevel = 210 },
			{ MinLevel = 41, MaxLevel = 50, XPPerLevel = 360 },
		},

		TotalXPMultiplierByRarity = {
			Common = 1.00,
			Uncommon = 1.20,
			Rare = 1.50,
			Epic = 1.90,
			Legendary = 2.40,
			Mythical = 3.10,
			Celestial = 4.00,
			Godly = 5.20,
			Secret = 6.80,
		},

		ShipIncomePerHourByRarity = {
			Common = 20,
			Uncommon = 35,
			Rare = 60,
			Epic = 100,
			Legendary = 170,
			Mythical = 280,
			Celestial = 450,
			Godly = 700,
			Secret = 1100,
		},

		ShipIncomeMultiplierByLevelBand = {
			{ MinLevel = 1, MaxLevel = 10, Multiplier = 1.00 },
			{ MinLevel = 11, MaxLevel = 20, Multiplier = 1.10 },
			{ MinLevel = 21, MaxLevel = 30, Multiplier = 1.25 },
			{ MinLevel = 31, MaxLevel = 40, Multiplier = 1.45 },
			{ MinLevel = 41, MaxLevel = 50, Multiplier = 1.70 },
		},

		RewardOddsByDepthBand = {
			Shallow = {
				Common = 6000,
				Uncommon = 2500,
				Rare = 1000,
				Epic = 400,
				Legendary = 100,
			},
			Mid = {
				Common = 3500,
				Uncommon = 2800,
				Rare = 1800,
				Epic = 1000,
				Legendary = 600,
				Mythical = 250,
				Celestial = 50,
			},
			Deep = {
				Common = 1500,
				Uncommon = 2000,
				Rare = 2500,
				Epic = 1800,
				Legendary = 1100,
				Mythical = 600,
				Celestial = 300,
				Godly = 150,
				Secret = 50,
			},
			Abyssal = {
				Common = 500,
				Uncommon = 1200,
				Rare = 1800,
				Epic = 2000,
				Legendary = 1800,
				Mythical = 1200,
				Celestial = 800,
				Godly = 500,
				Secret = 200,
			},
		},
	},
}

return Economy
