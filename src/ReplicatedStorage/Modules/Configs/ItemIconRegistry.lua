local ItemIconRegistry = {}

local FALLBACK_KEY = "FallbackReward"

local ITEMS = {
	Apple = {
		DisplayName = "Apple",
		Icon = "rbxassetid://118396195037795",
		Category = "Food",
		Aliases = {},
	},
	Rice = {
		DisplayName = "Rice",
		Icon = "rbxassetid://74514867648873",
		Category = "Food",
		Aliases = {},
	},
	Meat = {
		DisplayName = "Meat",
		Icon = "rbxassetid://124481273265386",
		Category = "Food",
		Aliases = {},
	},
	SeaBeastMeat = {
		DisplayName = "Sea Beast Meat",
		Icon = "rbxassetid://121493489346123",
		Category = "Food",
		Aliases = { "Sea Beast Meat", "SeaBeast Meat", "Sea BeastMeat" },
	},
	Timber = {
		DisplayName = "Timber",
		Icon = "rbxassetid://91391946631719",
		Category = "Material",
		Aliases = { "CommonShipMaterial", "Common Ship Material", "Wood" },
	},
	Iron = {
		DisplayName = "Iron",
		Icon = "rbxassetid://99719499783899",
		Category = "Material",
		Aliases = { "RareShipMaterial", "Rare Ship Material" },
	},
	AncientTimber = {
		DisplayName = "Ancient Timber",
		Icon = "rbxassetid://116942818922796",
		Category = "Material",
		Aliases = { "Ancient Timber", "Ancient Wood", "LegendaryShipMaterial", "Legendary Ship Material" },
	},
	Beli = {
		DisplayName = "Beli",
		Icon = "rbxassetid://86551660159840",
		Category = "Currency",
		Aliases = { "Doubloons", "Money", "Moeny", "$" },
	},
	Rebirth = {
		DisplayName = "Rebirth",
		Icon = "rbxassetid://116163404622119",
		Category = "Progression",
		Aliases = { "Rebirths" },
	},
	Chest = {
		DisplayName = "Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = { "Chests", "Reward Chest", "Rewards" },
	},
	WoodenChest = {
		DisplayName = "Wooden Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = { "Wooden Chest", "Wooden Chests", "Wood Chest", "Wood Chests", "WoodChest", "Supply Chest" },
	},
	IronChest = {
		DisplayName = "Iron Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = { "Iron Chest", "Iron Chests" },
	},
	GoldChest = {
		DisplayName = "Gold Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = { "Gold Chest", "Gold Chests", "GoldenChest", "Golden Chest", "Golden Chests" },
	},
	DevilFruit = {
		DisplayName = "Devil Fruit",
		Icon = "rbxassetid://122583196938184",
		Category = "DevilFruit",
		Aliases = { "Devil Fruit" },
	},
	DevilFruitChest = {
		DisplayName = "Devil Fruit Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = {
			"Devil Fruit Chest",
			"Devil Fruit Chests",
		},
	},
	CommonDevilFruitChest = {
		DisplayName = "Common Devil Fruit Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = {
			"CommonDevilFruitChest",
			"Common Devil Fruit Chest",
			"Common Devil Fruit Chests",
		},
	},
	RareDevilFruitChest = {
		DisplayName = "Rare Devil Fruit Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = {
			"RareDevilFruitChest",
			"Rare Devil Fruit Chest",
			"Rare Devil Fruit Chests",
		},
	},
	LegendaryDevilFruitChest = {
		DisplayName = "Legendary Devil Fruit Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = {
			"LegendaryDevilFruitChest",
			"Legendary Devil Fruit Chest",
			"Legendary Devil Fruit Chests",
		},
	},
	MythicDevilFruitChest = {
		DisplayName = "Mythic Devil Fruit Chest",
		Icon = "rbxassetid://88825249018556",
		Category = "Chest",
		Aliases = {
			"MythicDevilFruitChest",
			"Mythic Devil Fruit Chest",
			"Mythic Devil Fruit Chests",
		},
	},
	MoneyBoost = {
		DisplayName = "Money Boost",
		Icon = "rbxassetid://123727379614328",
		Category = "Boost",
		Aliases = {
			"Beli Boost",
			"2x Beli Boost",
			"x2Money",
			"x2MoneyTime",
			"Potions.x2MoneyTime",
			"Multipliers.MoneyMult",
			"MoneyMult",
		},
	},
	SpeedBoost = {
		DisplayName = "Speed Boost",
		Icon = "rbxassetid://96331945137652",
		Category = "Boost",
		Aliases = {
			"Walk Speed Boost",
			"Walkspeed Boost",
			"x1.5 Speed Boost",
			"x1.5 Walk Speed Boost",
			"x15WalkSpeed",
			"x15WalkSpeedTime",
			"Potions.x15WalkSpeedTime",
		},
	},
	LuckBoost = {
		DisplayName = "Luck Boost",
		Icon = "rbxassetid://99305009492305",
		Category = "Boost",
		Aliases = {
			"Server Luck",
			"xLuck",
			"xLuckTime",
			"Potions.xLuckTime",
		},
	},
	MythicKey = {
		DisplayName = "Mythic Key",
		Icon = "rbxassetid://122583196938184",
		Category = "Special",
		Aliases = { "Mythic Key", "Duplicate Refund - Mythic Key" },
	},
	FallbackReward = {
		DisplayName = "Reward",
		Icon = "rbxassetid://88825249018556",
		Category = "Reward",
		Aliases = { "Fallback", "Fallback Reward", "UnknownReward", "Unknown Reward" },
	},
}

local aliasToKey = {}

local function normalizeIdentifier(identifier)
	local value = tostring(identifier or "")
	value = string.gsub(value, "%s+", "")
	value = string.gsub(value, "[_%-]", "")
	return string.lower(value)
end

local function registerAlias(alias, key)
	local normalized = normalizeIdentifier(alias)
	if normalized ~= "" then
		aliasToKey[normalized] = key
	end
end

for key, record in pairs(ITEMS) do
	registerAlias(key, key)
	registerAlias(record.DisplayName, key)
	for _, alias in ipairs(record.Aliases or {}) do
		registerAlias(alias, key)
	end
end

local function resolveKey(identifier)
	local normalized = normalizeIdentifier(identifier)
	if normalized == "" then
		return nil
	end
	return aliasToKey[normalized]
end

local function copyRecord(key, record)
	return {
		Key = key,
		DisplayName = record.DisplayName,
		Icon = record.Icon,
		Category = record.Category,
	}
end

function ItemIconRegistry.Resolve(identifier)
	local key = resolveKey(identifier) or FALLBACK_KEY
	return copyRecord(key, ITEMS[key])
end

function ItemIconRegistry.GetIcon(identifier, fallbackIcon)
	local key = resolveKey(identifier)
	local record = if key then ITEMS[key] else nil
	if record and typeof(record.Icon) == "string" and record.Icon ~= "" then
		return record.Icon
	end
	if fallbackIcon ~= nil then
		return tostring(fallbackIcon or "")
	end
	return ITEMS[FALLBACK_KEY].Icon
end

function ItemIconRegistry.GetDisplayName(identifier, fallbackName)
	local key = resolveKey(identifier)
	local record = if key then ITEMS[key] else nil
	if record and typeof(record.DisplayName) == "string" and record.DisplayName ~= "" then
		return record.DisplayName
	end
	if fallbackName ~= nil and tostring(fallbackName) ~= "" then
		return tostring(fallbackName)
	end
	return tostring(identifier or ITEMS[FALLBACK_KEY].DisplayName)
end

function ItemIconRegistry.GetCategory(identifier)
	local key = resolveKey(identifier)
	local record = if key then ITEMS[key] else nil
	if record and typeof(record.Category) == "string" and record.Category ~= "" then
		return record.Category
	end
	return ITEMS[FALLBACK_KEY].Category
end

return ItemIconRegistry
