local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))

local primaryCurrency = Economy.Currency.Primary

local ProfileTemplate = {
	EconomyVersion = Economy.GetInflationVersion and Economy.GetInflationVersion() or 3,

	leaderstats = {
		[primaryCurrency.Key] = 0,
		Rebirths = 0,
		Bounty = 0,
	},

	HiddenLeaderstats = {
		Speed = 1,
		Tutorial = false,
		TutorialCrewMemberGranted = false,
		TutorialSpeedTopUpGranted = false,
		TutorialStarterBeliGranted = false,
		TutorialFinalRewardsClaimed = false,
		ClaimedTolilola = false,
		LimitedReward = false,
		Group = false,
		PlotUpgrade = 0,
		Comets = 0,
	},

	Tutorials = {
		SchemaVersion = 2,
		Completed = {},
		Queue = {},
	},

	SocialRewards = {
		GroupLikeLuffy = {
			Claimed = false,
			ClaimedAtUnix = 0,
		},
	},

	Codes = {
		Redeemed = {},
	},

	TotalStats = {
		[primaryCurrency.TotalKey] = 0,
		TotalSpeed = 0,
		TotalPower = 0,
		TotalWins = 0,
		TimePlayed = 0,
		RobuxSpent = 0,
	},

	CurrencyLegacy = {
		CurrentBeli = 0,
		CurrentTotalBeli = 0,
		Doubloons = 0,
		Money = 0,
		Moeny = 0,
		TotalDoubloons = 0,
		TotalMoney = 0,
	},

	Inventory = {
		Feed = {},
		DevilFruits = {},
	},

	UnopenedChests = {
		NextChestId = 1,
		ById = {},
		Order = {},
		StackSchemaVersion = 1,
		Stacks = {
			Wooden = 0,
			Iron = 0,
			Gold = 0,
		},
	},

	ChestRewards = {
		MythicKeys = 0,
		AFKGoldChests = {
			DayKey = "",
			EarnedToday = 0,
			ProgressSeconds = 0,
		},
		FruitPity = {
			Common = {
				FailedOpens = 0,
			},
			Rare = {
				FailedOpens = 0,
			},
			Legendary = {
				FailedOpens = 0,
			},
			Mythic = {
				FailedOpens = 0,
			},
		},
	},

	AFK = {
		SchemaVersion = 1,
		Session = {
			Active = false,
			SessionId = "",
			StartedAtUnix = 0,
			LastAccruedAtUnix = 0,
			ClaimedThroughUnix = 0,
			LastRewardSettledAtUnix = 0,
			AwardedChestIntervals = 0,
			BeliRemainder = 0,
			EarnedChestsThisSession = 0,
			EarnedBeliThisSession = 0,
			RefreshCount = 0,
			PendingReturn = false,
			Source = "",
			LastClaimId = "",
			LastKnownPlaceId = 0,
			LastTeleportAtUnix = 0,
		},
		Daily = {
			DayKey = "",
			ClaimedSeconds = 0,
		},
		Totals = {
			ClaimedSeconds = 0,
			Claims = 0,
		},
	},

	Bounty = {
		LifetimeExtraction = 0,
		Crew = 0,
		Total = 0,
	},

	Titles = {
		Unlocked = {},
		Equipped = "",
		Progress = {},
	},

	FoodInventory = {
		Apple = 0,
		Rice = 0,
		Meat = 0,
		SeaBeastMeat = 0,
	},

	CrewMemberInventory = {
		SchemaVersion = 2,
		NextInstanceId = 1,
		ById = {},
		Order = {},
	},
	CrewMemberInventoryAuthorityAudit = {},
	CrewMemberQuickSlots = {
		SchemaVersion = 2,
		UnlockedSlots = CrewQuickSlotConfig.DefaultUnlockedSlots,
		MaxSlots = CrewQuickSlotConfig.MaxSlots,
		Assignments = {},
	},
	CrewMemberIncome = {},
	CrewQuickSlotProductAuthorityAudit = {},

	Ship = {
		MaxSlots = Economy.Rules.MaxShipSlots,
		Slots = {},
		CaptainSlot = {
			IncomeToCollect = 0,
			LastAccruedAtUnix = 0,
		},
	},

	Chef = {
		ActiveCrewInstanceId = "",
		Bank = {
			FoodXP = 0,
			StoredFood = {},
			LastUpdatedAt = 0,
			LastClaimedAt = 0,
		},
	},

	Materials = {
		Timber = 0,
		Iron = 0,
		AncientTimber = 0,
		CommonShipMaterial = 0,
		RareShipMaterial = 0,
		Inventory = {},
	},

	DevilFruit = {
		Equipped = DevilFruitConfig.None,
	},

	IndexCollection = {
		CrewMembers = {},
		DevilFruits = {},
	},

	TimeRewards = {
		CycleStartPlayTime = 0,
		ClaimedRewards = {},
		LastClaimPlayTime = 0,
	},

	Quests = {
		Daily = {
			CycleId = "",
			ProfileBackfillApplied = false,
			Progress = {},
			Claimed = {},
		},
		Weekly = {
			CycleId = "",
			ProfileBackfillApplied = false,
			Progress = {},
			Claimed = {},
		},
		Special = {
			CycleId = "Lifetime",
			ProfileBackfillApplied = false,
			Progress = {},
			Claimed = {},
		},
	},

	Gears = {},
	Passes = {},
	Gamepasses = {
		x2MoneyValue = 1,
	},
	Active = {
		x2Money = 1,
		x15WalkSpeed = 1,
	},
	Multipliers = {
		MoneyMult = 0,
	},
	Potions = {
		x2Money = 0,
		x2MoneyTime = 0,
		x15WalkSpeed = 0,
		x15WalkSpeedTime = 0,
		xLuck = 0,
		xLuckTime = 0,
	},
	Settings = {
		SelectedSpeed = 1,
		SpeedAutoMax = true,
		PremiumStealProtectionEnabled = true,
		HasFavoritedGamePromptCompleted = false,
		FavoriteGamePromptCompletedAtUnix = 0,
		FavoriteGamePromptAttemptCount = 0,
		FavoriteGamePromptLastAttemptAtUnix = 0,
	},
	Packs = {},
	DailyClaims = {
		CaptainSupply = {
			LastClaimDate = "",
		},
	},
	CrewProtection = {
		SchemaVersion = 1,
		ShieldTokens = 0,
		FleetShieldTokens = 0,
		CrewShields = {
			ByInstanceId = {},
		},
		FleetShield = {
			Enabled = true,
			ExpiresAtPlayTime = 0,
			PausedRemainingSeconds = 0,
			LastGrantedAt = 0,
			Source = "",
		},
		PermanentSlotsOwned = 0,
		PermanentAssignments = {},
	},
	CometMerchant = {},
	PremiumCrewStealProtection = {
		NewPlayerRemoved = false,
		RemovedAt = 0,
		RemovedReason = "",
	},
	RaidShield = {
		SchemaVersion = 1,
		Enabled = true,
		SuppressionUntil = 0,
		NewPlayerGrantSeeded = false,
		LastRaidPenaltyReceiptId = "",
		LastRaidPenaltyAt = 0,
		LastRaidPenaltyReason = "",
		Grants = {},
	},
	PremiumCrewStealReceiptFallbacks = {},
	PremiumCrewStealSuccessfulReceipts = {},
	PaidRandomItemReceiptFallbacks = {},
	PurchaseIdCache = {},
	__Attributes = {},
}

return ProfileTemplate
