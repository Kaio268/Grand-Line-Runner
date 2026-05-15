local Economy = {
	Version = "v1",

	Currency = {
		Primary = {
			Key = "Doubloons",
			Path = "leaderstats.Doubloons",
			TotalKey = "TotalDoubloons",
			TotalPath = "TotalStats.TotalDoubloons",
			DisplayName = "Beli",
			ShortLabel = "Beli",
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

	CrewMembers = {
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
				AverageFoodXP = 53,
				Rewards = {
					Food = {
						Apple = { Min = 3, Max = 6 },
						Rice = { Min = 1, Max = 3 },
					},
					Doubloons = { Min = 250, Max = 600 },
					FruitConversionDoubloons = 15,
					Materials = {
						Timber = { Min = 12, Max = 20 },
					},
					BonusRoll = {
						Chance = 0.25,
						Rolls = 1,
						Pool = {
							{ Materials = { Iron = 1 } },
							{ Food = { Apple = 3 } },
							{ Food = { Rice = 2 } },
							{ Doubloons = 300 },
						},
					},
				},
			},
			Iron = {
				DepthBand = "EarlyMid",
				AverageFoodXP = 135,
				Rewards = {
					Food = {
						Rice = { Min = 3, Max = 5 },
						Meat = { Min = 1, Max = 2 },
					},
					Doubloons = { Min = 1000, Max = 2500 },
					FruitConversionDoubloons = 30,
					Materials = {
						Timber = { Min = 35, Max = 55 },
						Iron = { Min = 4, Max = 8 },
					},
					BonusRoll = {
						Chance = 0.35,
						Rolls = 1,
						Pool = {
							{ Materials = { Iron = 3 } },
							{ Materials = { AncientTimber = 1 } },
							{ Food = { Meat = 2 } },
							{ Doubloons = 1500 },
						},
					},
				},
			},
			Gold = {
				DepthBand = "Deep",
				AverageFoodXP = 463,
				Rewards = {
					Food = {
						Meat = { Min = 3, Max = 5 },
						SeaBeastMeat = { Min = 1, Max = 2 },
					},
					Doubloons = { Min = 4000, Max = 8000 },
					FruitConversionDoubloons = 120,
					Materials = {
						Timber = { Min = 80, Max = 140 },
						Iron = { Min = 12, Max = 20 },
						AncientTimber = { Min = 1, Max = 3 },
					},
					BonusRoll = {
						Chance = 0.50,
						Rolls = 1,
						Pool = {
							{ Materials = { AncientTimber = 2 } },
							{ Food = { SeaBeastMeat = 2 } },
							{ Doubloons = 5000 },
						},
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
			},
			Mid = {
				Wooden = 25,
				Iron = 45,
				Gold = 30,
			},
			Strong = {
				Wooden = 10,
				Iron = 30,
				Gold = 60,
			},
			Elite = {
				Wooden = 5,
				Iron = 15,
				Gold = 80,
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
