local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local BuffDisplayFormatter = require(Modules:WaitForChild("BuffDisplayFormatter"))
local GamepassesConfig = require(Configs:WaitForChild("Gamepasses"))
local MonetizationConfig = require(Configs:WaitForChild("Monetization"))
local MovementSpeedConfig = require(Configs:WaitForChild("MovementSpeed"))

local Catalog = {}

local VIP_GAMEPASS_ID =
	assert(tonumber(GamepassesConfig.VIP and GamepassesConfig.VIP.ID), "VIP gamepass ID is not configured")
local VIP_ICON = tostring(GamepassesConfig.VIP and GamepassesConfig.VIP.Icon or "")

local function formatRobux(price)
	local numericPrice = tonumber(price)
	if numericPrice and numericPrice > 0 then
		return tostring(numericPrice)
	end
	return "Soon"
end

local function formatSpeedBoostSubtitle()
	local multiplier = tonumber(MovementSpeedConfig.PotionSpeedBoostMultiplier) or 1.5
	return BuffDisplayFormatter.formatMultiplierLabel(multiplier, "Speed")
end

local function gamepassPurchase(gamepassKey)
	if gamepassKey == "VIP" then
		return {
			kind = "gamepass",
			id = VIP_GAMEPASS_ID,
			ownedKey = "VIP",
		}
	end

	local config = MonetizationConfig.ShopGamepasses[gamepassKey]
	local id = tonumber(config and config.Id)
	if id and id > 0 then
		return {
			kind = "gamepass",
			id = id,
			ownedPath = config.OwnedPath,
			grantKey = config.GrantKey,
		}
	end

	return {
		kind = "stub",
	}
end

local function productPurchase(productKey)
	local config = MonetizationConfig.ShopDeveloperProducts[productKey]
	local id = tonumber(config and config.Id)
	if id and id > 0 then
		return {
			kind = "product",
			id = id,
			grantKey = config.GrantKey,
			durationSeconds = config.DurationSeconds,
			oneTime = config.OneTime == true,
			ownedPath = config.OwnedPath,
			OneTime = config.OneTime == true,
			OwnedPath = config.OwnedPath,
			RequiresPaidRandomItemPolicy = config.RequiresPaidRandomItemPolicy == true,
			PaidRandomItem = config.PaidRandomItem == true,
			RandomRewardGenerator = config.RandomRewardGenerator == true,
		}
	end

	return {
		kind = "stub",
	}
end

local function item(config)
	config.priceText = config.priceText or "Soon"
	config.callToAction = config.callToAction or "Purchase"
	config.purchase = config.purchase or {
		kind = "stub",
	}
	return config
end

local function boostVariant(configKey, id, label)
	local config = MonetizationConfig.ShopDeveloperProducts[configKey] or {}
	local purchase = productPurchase(configKey)

	return {
		id = id,
		label = label,
		durationSeconds = tonumber(config.DurationSeconds) or 0,
		priceText = formatRobux(config.PriceRobux),
		callToAction = "Buy",
		purchase = purchase,
	}
end

local items = {
	starterPack = item({
		id = "starter-pack",
		sectionKey = "featured",
		title = "Starter Pack",
		subtitle = "Best deal for new players",
		description = "Start strong with a Golden crewmate, lots of Beli, food, materials, boosts, and protection.",
		includes = {
			"Golden Bloom Scholar",
			"250K Beli",
			"250 Timber",
			"40 Iron",
			"20 Apples",
			"15 Rice",
			"10 Meat",
			"3 Beast Meat",
			"1 Hour Money Boost",
			"1 Hour Speed Boost",
			"1 Hour Luck Boost",
			"3 Crew Shields",
		},
		tags = { "Bundle", "New", "Value" },
		priceText = "499",
		callToAction = "Buy",
		themeKey = "Gold",
		iconText = "SP",
		purchase = productPurchase("StarterPack"),
	}),
	captainPass = item({
		id = "captain-pass",
		sectionKey = "featured",
		title = "Captain Pass",
		subtitle = "Permanent VIP perks",
		description = "Get a gold name, Captain title, extra Beli, and a Supply Chest added to your inventory every day.",
		includes = {
			"Gold Name",
			"Captain Title",
			"+10% Beli",
			"Supply Chest every day",
		},
		detailGroups = {
			{
				title = "Supply Chest",
				items = {
					"1 Wooden Chest",
					"Added to normal chest inventory",
					"Available once per day",
				},
			},
		},
		tags = { "VIP", "Permanent" },
		priceText = "499",
		callToAction = "Unlock",
		themeKey = "Emerald",
		iconText = "VIP",
		iconImage = VIP_ICON,
		purchase = gamepassPurchase("VIP"),
	}),
	mythicFruitChest = item({
		id = "mythic-fruit-chest",
		sectionKey = "featured",
		title = "Mythic Fruit Chest",
		subtitle = "Guaranteed Mythic Fruit",
		description = "Opens into one Mythical Devil Fruit. No lower rarities.",
		tags = { "Chest", "Mythic" },
		priceText = "3000",
		callToAction = "Buy",
		themeKey = "Violet",
		iconText = "MF",
		RequiresPaidRandomItemPolicy = true,
		PaidRandomItem = true,
		purchase = productPurchase("MythicFruitChest"),
	}),
	moneyBoost = item({
		id = "money-boost",
		sectionKey = "boosts-chests",
		title = "Money Boost",
		subtitle = "2x Beli",
		description = "Earn double Beli for a limited time.",
		tags = { "Boost", "Beli" },
		themeKey = "Gold",
		iconText = "2X",
		variants = {
			boostVariant("MoneyBoost15", "money-boost-15", "15 min"),
			boostVariant("MoneyBoost30", "money-boost-30", "30 min"),
			boostVariant("MoneyBoost60", "money-boost-60", "60 min"),
		},
	}),
	luckBoost = item({
		id = "luck-boost",
		sectionKey = "boosts-chests",
		title = "Luck Boost",
		subtitle = "Better rare drops",
		description = "Increases your chance of getting rare drops, including fruits.",
		tags = { "Boost", "Luck" },
		themeKey = "Violet",
		iconText = "LK",
		variants = {
			boostVariant("LuckBoost15", "luck-boost-15", "15 min"),
			boostVariant("LuckBoost30", "luck-boost-30", "30 min"),
			boostVariant("LuckBoost60", "luck-boost-60", "60 min"),
		},
	}),
	speedBoost = item({
		id = "speed-boost",
		sectionKey = "boosts-chests",
		title = "Speed Boost",
		subtitle = formatSpeedBoostSubtitle(),
		description = "Run faster for a limited time.",
		tags = { "Boost", "Speed" },
		themeKey = "Cyan",
		iconText = "SP",
		variants = {
			boostVariant("SpeedBoost15", "speed-boost-15", "15 min"),
			boostVariant("SpeedBoost30", "speed-boost-30", "30 min"),
		},
	}),
	crewShield = item({
		id = "crew-shield",
		sectionKey = "crew-protection",
		title = "Crew Shield",
		subtitle = "Protect 1 crewmate",
		description = "Protects 1 crewmate from being stolen for 24 playable hours.",
		tags = { "Shield", "Crew" },
		priceText = "99",
		callToAction = "Buy",
		themeKey = "Emerald",
		iconText = "CS",
		purchase = productPurchase("CrewShield"),
	}),
	fleetShield = item({
		id = "fleet-shield",
		sectionKey = "crew-protection",
		title = "Fleet Shield",
		subtitle = "Protect all crewmates",
		description = "Protects your whole crew from being stolen for 24 playable hours.",
		tags = { "Shield", "Fleet" },
		priceText = "499",
		callToAction = "Buy",
		themeKey = "Cyan",
		iconText = "FS",
		purchase = productPurchase("FleetShield"),
	}),
	permanentShieldSlot = item({
		id = "permanent-shield-slot",
		sectionKey = "crew-protection",
		title = "Permanent Shield Slot",
		subtitle = "Protect 1 crewmate forever",
		description = "Adds 1 permanent protection slot for your favorite crewmate.",
		tags = { "Permanent", "Shield" },
		priceText = "999",
		callToAction = "Buy",
		themeKey = "Slate",
		iconText = "PS",
		purchase = productPurchase("PermanentShieldSlot"),
	}),
}

Catalog.title = "Robux Shop"
Catalog.featuredSections = {}

Catalog.sections = {
	{
		key = "featured",
		title = "Featured",
		themeKey = "Gold",
		items = {
			items.starterPack,
			items.captainPass,
			items.mythicFruitChest,
		},
	},
	{
		key = "boosts-chests",
		title = "Boosts & Chests",
		themeKey = "Violet",
		items = {
			items.moneyBoost,
			items.luckBoost,
			items.speedBoost,
		},
	},
	{
		key = "crew-protection",
		title = "Crew Protection",
		themeKey = "Emerald",
		items = {
			items.crewShield,
			items.fleetShield,
			items.permanentShieldSlot,
		},
	},
}

return Catalog
