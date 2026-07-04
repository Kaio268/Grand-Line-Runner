local Economy = {
	Version = "v2",

	Inflation = {
		-- Version 4 removes the legacy Beli x1,000,000 scale. The multiplier is
		-- retained for non-Beli legacy resource paths that still depend on it.
		Version = 4,
		Multiplier = 1_000_000,
		BeliMultiplier = 1,
	},

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
		CrewMaxLevel = 200,
		DuplicateCrewHandling = "StoreAsSeparateInstances",
		MaxShipSlots = 38,
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
					Base = 34,
					SecondsRemovedPerExtraPlayer = 4,
					Min = 18,
					Max = 34,
				},
				RespawnDelay = 75, -- Legacy fallback for older shared chest code.
				MaxActiveByPlayerCount = {
					[1] = 14,
					[2] = 16,
					[3] = 18,
					[4] = 20,
					[5] = 22,
					[6] = 24,
					[7] = 26,
					[8] = 26,
				},
				MinActiveByDepthBand = {
					Shallow = 3,
					Mid = 3,
					Deep = 2,
					Abyssal = 2,
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
					MaxActiveMultiplier = 2.0,
					SpawnIntervalMultiplier = 0.65,
					MinSpawnIntervalSeconds = 12,
					MaxActiveCap = 48,
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

	AFKTeleport = {
		Enabled = true,
		MainPlaceId = 128382161567643,
		AFKPlaceId = 84534597236418,
		PlacePairsByEnvironment = {
			Production = {
				MainPlaceId = 128382161567643,
				AFKPlaceId = 84534597236418,
			},
			Staging = {
				MainPlaceId = 110640828025742,
				AFKPlaceId = 122987301330026,
			},
		},
		ManualEnabled = true,
		AutoEnabled = true,
		InactivitySeconds = 1080,
		ActivityPingCooldownSeconds = 15,
		ScanIntervalSeconds = 30,
		RefreshSeconds = 960,
		RefreshRetrySeconds = 30,
		RewardSettlementSeconds = 30,
		Remotes = {
			StateEventName = "AFKTeleportState",
			StateRequestName = "AFKTeleportStateRequest",
			EntryRequestName = "AFKTeleportEntryRequest",
			ReturnRequestName = "AFKTeleportReturnRequest",
			ActivityPingEventName = "AFKActivityPing",
		},
		Rewards = {
			BeliRateMultiplier = 0.30,
			ChestTier = "Gold",
			ChestSource = "AFK",
			Standard = {
				ChestIntervalSeconds = 3600,
				ChestsPerInterval = 1,
			},
			VIP = {
				ChestIntervalSeconds = 5400,
				ChestsPerInterval = 2,
			},
		},
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
		MaxLevel = 200,
		MaxCrewLevel = 200,
		LevelIncomeMultiplierPerLevel = 1.25,
		IncomeRollVersion = 3,
		-- Single active crew income authority. Values are level-1 Beli/sec and
		-- are intentionally not passed through the global economy inflation scale.
		IncomeByRarityVariant = {
			Common = { Normal = 150, Golden = 750, Diamond = 3750 },
			Uncommon = { Normal = 750, Golden = 3750, Diamond = 18750 },
			Rare = { Normal = 5000, Golden = 25000, Diamond = 125000 },
			Epic = { Normal = 45000, Golden = 225000, Diamond = 1125000 },
			Legendary = { Normal = 220000, Golden = 1100000, Diamond = 5500000 },
			Mythic = { Normal = 750000, Golden = 3750000, Diamond = 18750000 },
			Mythical = { Normal = 750000, Golden = 3750000, Diamond = 18750000 },
			Godly = { Normal = 5000000, Golden = 25000000, Diamond = 125000000 },
			Secret = { Normal = 20000000, Golden = 100000000, Diamond = 500000000 },
		},
		BaseIncomeRollByRarity = {
			Common = { Min = 2, Max = 10 },
			Uncommon = { Min = 17, Max = 55 },
			Rare = { Min = 100, Max = 250 },
			Epic = { Min = 360, Max = 800 },
			Legendary = { Min = 1000, Max = 4000 },
			Mythic = { Min = 2500, Max = 9000 },
			Mythical = { Min = 2500, Max = 9000 },
			Godly = { Min = 6000, Max = 18000 },
			Secret = { Min = 16000, Max = 30000 },
		},
		VariantIncomeBandsByRarity = {
			Common = {
				Normal = { Min = 2, Max = 10 },
				Golden = { Min = 11, Max = 20 },
				Diamond = { Min = 21, Max = 50 },
			},
			Uncommon = {
				Normal = { Min = 17, Max = 55 },
				Golden = { Min = 56, Max = 110 },
				Diamond = { Min = 111, Max = 275 },
			},
			Rare = {
				Normal = { Min = 100, Max = 250 },
				Golden = { Min = 251, Max = 500 },
				Diamond = { Min = 501, Max = 1250 },
			},
			Epic = {
				Normal = { Min = 360, Max = 800 },
				Golden = { Min = 801, Max = 1600 },
				Diamond = { Min = 1800, Max = 4000 },
			},
			Legendary = {
				Normal = { Min = 1000, Max = 4000 },
				Golden = { Min = 4001, Max = 8000 },
				Diamond = { Min = 8001, Max = 20000 },
			},
			Mythic = {
				Normal = { Min = 2500, Max = 9000 },
				Golden = { Min = 9001, Max = 18000 },
				Diamond = { Min = 18001, Max = 45000 },
			},
			Mythical = {
				Normal = { Min = 2500, Max = 9000 },
				Golden = { Min = 9001, Max = 18000 },
				Diamond = { Min = 18001, Max = 45000 },
			},
			Godly = {
				Normal = { Min = 6000, Max = 18000 },
				Golden = { Min = 18001, Max = 36000 },
				Diamond = { Min = 36001, Max = 90000 },
			},
			Secret = {
				Normal = { Min = 16000, Max = 30000 },
				Golden = { Min = 32000, Max = 60000 },
				Diamond = { Min = 80000, Max = 150000 },
			},
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
		AFKGoldRewards = {
			Enabled = true,
			RewardTier = "Gold",
			Source = "AFK",
			Normal = {
				IntervalSeconds = 3600,
				DailyCap = 8,
			},
			Premium = {
				IntervalSeconds = 1800,
				DailyCap = 16,
			},
			Remotes = {
				StateEventName = "AFKGoldChestState",
				StateRequestName = "AFKGoldChestStateRequest",
				EntryRequestName = "AFKGoldChestEntryRequest",
				ExitRequestName = "AFKGoldChestExitRequest",
				UiHeartbeatEventName = "AFKGoldChestUiHeartbeat",
			},
			Timing = {
				TickSeconds = 1,
				HeartbeatIntervalSeconds = 5,
				HeartbeatTimeoutSeconds = 15,
				HeartbeatMinIntervalSeconds = 1,
				ShipSpawnCacheSeconds = 2,
			},
			Entry = {
				MaxDistance = 18,
				ShipAfkRadius = 34,
			},
		},

		Tiers = {
			Wooden = {
				DepthBand = "Early",
				AverageFoodXP = 66,
				Rewards = {
					Food = {
						Apple = { Min = 4, Max = 8 },
						Rice = { Min = 2, Max = 4 },
					},
					Beli = { Min = 50000, Max = 250000 },
					FruitConversionBeli = 50000,
					Materials = {
						Timber = { Min = 14, Max = 24 },
						Iron = { Min = 1, Max = 2 },
					},
					BonusRoll = {
						Chance = 0.25,
						Rolls = 1,
						Pool = {
							{ Materials = { Iron = 1 } },
							{ Food = { Apple = 4 } },
							{ Food = { Rice = 3 } },
							{ Beli = 125000 },
						},
					},
				},
			},
			Iron = {
				DepthBand = "EarlyMid",
				AverageFoodXP = 169,
				Rewards = {
					Food = {
						Rice = { Min = 4, Max = 7 },
						Meat = { Min = 2, Max = 3 },
					},
					Beli = { Min = 500000, Max = 2500000 },
					FruitConversionBeli = 500000,
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
							{ Food = { Meat = 3 } },
							{ Beli = 1250000 },
						},
					},
				},
			},
			Gold = {
				DepthBand = "Deep",
				AverageFoodXP = 579,
				Rewards = {
					Food = {
						Meat = { Min = 4, Max = 7 },
						SeaBeastMeat = { Min = 2, Max = 3 },
					},
					Beli = { Min = 5000000, Max = 25000000 },
					FruitConversionBeli = 5000000,
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
							{ Food = { SeaBeastMeat = 3 } },
							{ Beli = 12500000 },
						},
					},
				},
			},
		},

		ExpectedTierDistributionByStage = {
			Shallow = {
				Wooden = 74,
				Iron = 21,
				Gold = 5,
			},
			Mid = {
				Wooden = 41,
				Iron = 47,
				Gold = 12,
			},
			Deep = {
				Wooden = 0,
				Iron = 73,
				Gold = 27,
			},
			Abyssal = {
				Wooden = 0,
				Iron = 58,
				Gold = 42,
			},
			-- Legacy stage aliases kept for compatibility with older callers.
			Early = {
				Wooden = 74,
				Iron = 21,
				Gold = 5,
			},
			Strong = {
				Wooden = 0,
				Iron = 73,
				Gold = 27,
			},
			Elite = {
				Wooden = 0,
				Iron = 58,
				Gold = 42,
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

local function scaleWholeAmount(value)
	local numeric = tonumber(value)
	if numeric == nil then
		return value
	end

	return math.floor((numeric * Economy.Inflation.Multiplier) + 0.5)
end

local function scaleBeliAmount(value)
	local numeric = tonumber(value)
	if numeric == nil then
		return value
	end

	return math.floor((numeric * (Economy.Inflation.BeliMultiplier or 1)) + 0.5)
end

local function scaleRangeSpec(spec)
	if typeof(spec) == "number" then
		return scaleWholeAmount(spec)
	end
	if typeof(spec) ~= "table" then
		return spec
	end

	if spec.Amount ~= nil then
		spec.Amount = scaleRangeSpec(spec.Amount)
	end
	if spec.Value ~= nil then
		spec.Value = scaleRangeSpec(spec.Value)
	end
	if spec.Min ~= nil then
		spec.Min = scaleWholeAmount(spec.Min)
	end
	if spec.Max ~= nil then
		spec.Max = scaleWholeAmount(spec.Max)
	end
	if spec.min ~= nil then
		spec.min = scaleWholeAmount(spec.min)
	end
	if spec.max ~= nil then
		spec.max = scaleWholeAmount(spec.max)
	end

	return spec
end

local function scaleFlatAmountMap(map)
	if typeof(map) ~= "table" then
		return
	end

	for key, value in pairs(map) do
		if typeof(value) == "number" then
			map[key] = scaleWholeAmount(value)
		else
			scaleRangeSpec(value)
		end
	end
end

local function scaleRewardBundle(bundle)
	if typeof(bundle) ~= "table" then
		return
	end

	-- Chest Beli is authored in final economy units; do not apply the legacy
	-- global inflation multiplier to Beli, duplicate conversion, or bonus Beli.

	scaleFlatAmountMap(bundle.Materials)

	local bonusRoll = bundle.BonusRoll
	local pool = bonusRoll and bonusRoll.Pool
	if typeof(pool) == "table" then
		for _, reward in ipairs(pool) do
			scaleRewardBundle(reward)
		end
	end
end

function Economy.ScaleAmount(value)
	return scaleWholeAmount(value)
end

function Economy.ScaleBeliAmount(value)
	return scaleBeliAmount(value)
end

function Economy.ScaleRangeSpec(spec)
	return scaleRangeSpec(spec)
end

function Economy.ScaleRewardAmount(rewardType, value)
	local normalizedType = tostring(rewardType or "")
	if normalizedType == "Currency" or normalizedType == "Beli" or normalizedType == "Doubloons" then
		return scaleBeliAmount(value)
	elseif normalizedType == "Material" or normalizedType == "Resource" then
		return scaleWholeAmount(value)
	end

	return value
end

function Economy.GetInflationVersion()
	return Economy.Inflation.Version
end

function Economy.GetInflationMultiplier()
	return Economy.Inflation.Multiplier
end

Economy.Tutorial.StartingBeli = scaleBeliAmount(Economy.Tutorial.StartingBeli)

for _, tierConfig in pairs(Economy.Chests.Tiers or {}) do
	scaleRewardBundle(tierConfig.Rewards)
end

for rarityName, amount in pairs(Economy.Crew.ShipIncomePerHourByRarity or {}) do
	Economy.Crew.ShipIncomePerHourByRarity[rarityName] = scaleWholeAmount(amount)
end

return Economy
