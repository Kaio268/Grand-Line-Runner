local Economy = {
	Version = "v2",

	Currency = {
		Primary = {
			Key = "Beli",
			Path = "leaderstats.Beli",
			TotalKey = "TotalBeli",
			TotalPath = "TotalStats.TotalBeli",
			DisplayName = "Beli",
			ShortLabel = "Beli",
			-- Legacy keys are intentionally preserved for old saves, aliases, receipts,
			-- admin commands, and transitional reads. Player-facing text should use Beli.
			LegacyKeys = {
				Leaderstat = "Doubloons",
				LeaderstatMoney = "Money",
				LeaderstatTypo = "Moeny",
				Total = "TotalDoubloons",
				TotalMoney = "TotalMoney",
			},
		},
	},

	PathAliases = {
		["leaderstats.Beli"] = {
			"leaderstats.Doubloons",
			"leaderstats.Money",
			"leaderstats.Moeny",
		},
		["TotalStats.TotalBeli"] = {
			"TotalStats.TotalDoubloons",
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

	Leaderstats = {
		-- Roblox's People list is sensitive to child order. Keep this order stable
		-- whenever DataManager creates or repairs the leaderstats folder.
		DisplayOrder = {
			"Bounty",
			"Rebirths",
			"Beli",
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
		StartingBeli = 200,
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
			Shallow = "Shallow",
			Mid = "Mid",
			Deep = "Deep",
			Abyssal = "Abyssal",
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
		CarrySlots = {
			MaxSlots = 3,
			DefaultUnlocked = 1,
			TemporaryUnlockedForTesting = 3,
			TestUnlockedAttribute = "GrandLineRushUnlockedCarrySlots",
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
				SpawnCheckInterval = 5,
				RespawnCheckInterval = 5, -- Legacy alias; prefer SpawnCheckInterval.
				SpawnIntervalSeconds = {
					Base = 42,
					SecondsRemovedPerExtraPlayer = 5,
					Min = 22,
					Max = 42,
				},
				RespawnDelay = 75, -- Legacy fallback for older shared chest code.
				MaxActiveByPlayerCount = {
					[1] = 4,
					[2] = 6,
					[3] = 7,
					[4] = 8,
					[5] = 9,
					[6] = 10,
					[7] = 10,
					[8] = 10,
				},
				MaxActive = {
					Base = 4,
					PlayersPerExtra = 1,
					Min = 4,
					Max = 10,
				},
				RandomSpawnYawEnabled = true,
				SpawnYawStepDegrees = 0,
				ChestDespawnSeconds = 120,
				DroppedChestDespawnSeconds = 60,
				UnclaimedDespawnSeconds = 120,
				GoldPityAfterNonGoldSpawns = 5,
				PopulationGoldBonusPerExtraPlayer = 0.0125,
				PopulationGoldBonusCap = 0.06,
				ChestRush = {
					Enabled = true,
					StartsEveryMinutes = 60,
					DurationMinutes = 10,
					MaxActiveMultiplier = 2,
					SpawnIntervalMultiplier = 0.65,
					MinSpawnIntervalSeconds = 12,
					MaxActiveCap = 20,
					GoldChanceMultiplier = 1.0,
				},
				DebugBeaconEnabled = false,
				SpawnPartCacheRefreshSeconds = 60,
				MaxActivePerSpawnPart = 1,
				SpawnPartEligibleAttribute = "SharedChestSpawnEligible",
				SpawnPartDisabledAttribute = "SharedChestSpawnDisabled",
				SpawnPartDepthBandAttribute = "SharedChestDepthBand",
				SpawnPartWeightAttribute = "SharedChestSpawnWeight",
				SpawnWeightByDepthBand = {
					Shallow = 1,
					Mid = 1,
					Deep = 1,
					Abyssal = 1,
				},
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
		IncomeRollVersion = 1,
		BaseIncomeRollByRarity = {
			Common = { Min = 4, Max = 8 },
			Uncommon = { Min = 16, Max = 26 },
			Rare = { Min = 45, Max = 70 },
			Epic = { Min = 100, Max = 145 },
			Legendary = { Min = 210, Max = 290 },
			Mythic = { Min = 450, Max = 650 },
			Mythical = { Min = 450, Max = 650 },
			Godly = { Min = 1350, Max = 1750 },
			Secret = { Min = 4600, Max = 6000 },
		},
		VariantUpgradeCostMultiplier = {
			Normal = 1,
			Golden = 1.5,
			Diamond = 2.5,
		},
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
			Mythic = 3.10,
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
					Beli = { Min = 250, Max = 600 },
					FruitConversionBeli = 15,
					Materials = {
						Timber = { Min = 14, Max = 24 },
						Iron = { Min = 1, Max = 2 },
					},
					BonusRoll = {
						Chance = 0.25,
						Rolls = 1,
						Pool = {
							{ Materials = { Iron = 1 } },
							{ Food = { Apple = 3 } },
							{ Food = { Rice = 2 } },
							{ Beli = 300 },
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
					Beli = { Min = 1000, Max = 2500 },
					FruitConversionBeli = 30,
					Materials = {
						Timber = { Min = 45, Max = 70 },
						Iron = { Min = 10, Max = 16 },
					},
					BonusRoll = {
						Chance = 0.45,
						Rolls = 1,
						Pool = {
							{ Materials = { Iron = 6 } },
							{ Materials = { AncientTimber = 1 } },
							{ Food = { Meat = 2 } },
							{ Beli = 1500 },
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
					Beli = { Min = 4000, Max = 8000 },
					FruitConversionBeli = 120,
					Materials = {
						Timber = { Min = 80, Max = 140 },
						Iron = { Min = 24, Max = 36 },
						AncientTimber = { Min = 2, Max = 4 },
					},
					BonusRoll = {
						Chance = 0.50,
						Rolls = 1,
						Pool = {
							{ Materials = { Iron = 10 } },
							{ Materials = { AncientTimber = 2 } },
							{ Food = { SeaBeastMeat = 2 } },
							{ Beli = 5000 },
						},
					},
					DevilFruitChance = 0.10,
				},
			},
		},

		ExpectedTierDistributionByStage = {
			Shallow = {
				Wooden = 76,
				Iron = 21,
				Gold = 3,
			},
			Mid = {
				Wooden = 45,
				Iron = 47,
				Gold = 8,
			},
			Deep = {
				Wooden = 0,
				Iron = 82,
				Gold = 18,
			},
			Abyssal = {
				Wooden = 0,
				Iron = 72,
				Gold = 28,
			},
			-- Legacy stage aliases kept for compatibility with older callers.
			Early = {
				Wooden = 76,
				Iron = 21,
				Gold = 3,
			},
			Strong = {
				Wooden = 0,
				Iron = 82,
				Gold = 18,
			},
			Elite = {
				Wooden = 0,
				Iron = 72,
				Gold = 28,
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
			Mythic = 3.10,
			Mythical = 3.10,
			Celestial = 4.00,
			Godly = 5.20,
			Secret = 6.80,
		},

		ShipIncomePerHourByRarity = {
			Common = 21_600,
			Uncommon = 70_200,
			Rare = 198_000,
			Epic = 409_500,
			Legendary = 819_000,
			Mythic = 1_777_500,
			Mythical = 1_777_500,
			Celestial = 3_000_000,
			Godly = 5_580_000,
			Secret = 18_450_000,
		},

		ShipIncomeMultiplierByLevelBand = {
			{ MinLevel = 1, MaxLevel = 10, Multiplier = 1.18 },
			{ MinLevel = 11, MaxLevel = 20, Multiplier = 1.58 },
			{ MinLevel = 21, MaxLevel = 30, Multiplier = 1.98 },
			{ MinLevel = 31, MaxLevel = 40, Multiplier = 2.38 },
			{ MinLevel = 41, MaxLevel = 50, Multiplier = 2.78 },
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
