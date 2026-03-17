local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))

local primaryCurrency = Economy.Currency.Primary

local ProfileTemplate = {
	leaderstats = {
		[primaryCurrency.Key] = 0,
		Rebirths = 0,
	},

	HiddenLeaderstats = {
		Speed = 1,
		Tutorial = false,
		TutorialStarterDoubloonsGranted = false,
		ClaimedTolilola = false,
		LimitedReward = false,
		Group = false,
		PlotUpgrade = 0,
		Comets = 0,
	},

	HiddenLeadderstats = {
		PlotUpgrade = 0,
	},

	TotalStats = {
		[primaryCurrency.TotalKey] = 0,
		TotalSpeed = 0,
		TotalPower = 0,
		TotalWins = 0,
		TimePlayed = 0,
		RobuxSpent = 0,
	},

	Inventory = {
		Feed = {},
		DevilFruits = {},
	},

	UnopenedChests = {
		NextChestId = 1,
		ById = {},
		Order = {},
	},

	FoodInventory = {
		Apple = 0,
		Rice = 0,
		Meat = 0,
		SeaBeastMeat = 0,
	},

	CrewInventory = {
		NextInstanceId = 1,
		ById = {},
		Order = {},
	},

	BrainrotInventory = {
		NextInstanceId = 1,
		ById = {},
		Order = {},
	},

	Ship = {
		MaxSlots = Economy.Rules.MaxShipSlots,
		Slots = {},
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
		CommonShipMaterial = 0,
		RareShipMaterial = 0,
		Inventory = {},
	},

	DevilFruit = {
		Equipped = DevilFruitConfig.None,
	},

	IncomeBrainrots = {},
	StandsLevels = {},
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
	Settings = {},
	Packs = {},
	CometMerchant = {},
	PurchaseIdCache = {},
	__Attributes = {},
}

return ProfileTemplate
