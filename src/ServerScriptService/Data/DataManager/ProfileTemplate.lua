local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))

local primaryCurrency = Economy.Currency.Primary

local ProfileTemplate = {
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
		ClaimedTolilola = false,
		LimitedReward = false,
		Group = false,
		PlotUpgrade = 0,
		Comets = 0,
	},

	Tutorials = {
		SchemaVersion = 1,
		Completed = {},
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
	},

	Bounty = {
		LifetimeExtraction = 0,
		Crew = 0,
		Total = 0,
	},

	Titles = {
		Unlocked = {},
		Equipped = "",
	},

	FoodInventory = {
		Apple = 0,
		Rice = 0,
		Meat = 0,
		SeaBeastMeat = 0,
	},

	CrewMemberInventory = {
		SchemaVersion = 1,
		NextInstanceId = 1,
		ById = {},
		Order = {},
	},
	CrewMemberInventoryAuthorityAudit = {},
	CrewMemberQuickSlots = {
		SchemaVersion = 1,
		UnlockedSlots = CrewQuickSlotConfig.DefaultUnlockedSlots,
		MaxSlots = CrewQuickSlotConfig.MaxSlots,
	},
	CrewMemberIncome = {},
	CrewQuickSlotProductAuthorityAudit = {},

	Ship = {
		MaxSlots = Economy.Rules.MaxShipSlots,
		Slots = {},
		CaptainSlot = {
			IncomeToCollect = 0,
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
	Potions = {
		x2Money = 0,
		x2MoneyTime = 0,
		x15WalkSpeed = 0,
		x15WalkSpeedTime = 0,
	},
	Settings = {
		SelectedSpeed = 1,
		SpeedAutoMax = true,
		PremiumStealProtectionEnabled = true,
	},
	Packs = {},
	CometMerchant = {},
	PremiumCrewStealProtection = {
		NewPlayerRemoved = false,
		RemovedAt = 0,
		RemovedReason = "",
	},
	PremiumCrewStealReceiptFallbacks = {},
	PremiumCrewStealSuccessfulReceipts = {},
	PaidRandomItemReceiptFallbacks = {},
	PurchaseIdCache = {},
	__Attributes = {},
}

return ProfileTemplate
