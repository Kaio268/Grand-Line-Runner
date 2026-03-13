local DevilFruits = {
	None = "",
	Fruits = {},
	FruitsByKey = {
		Mera = {
			Id = "MeraMeraNoMi",
			FruitKey = "Mera",
			DisplayName = "Mera Mera no Mi",
			AssetFolder = "Mera",
			AbilityModule = "Mera",
			Rarity = "Legendary",
			Abilities = {
				FlameDash = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 5,
					DashDistance = 42,
					DashDuration = 0.14,
					InstantDashFraction = 0.58,
					DistanceSpeedBonusFactor = 0.06,
					MaxDistanceSpeedBonus = 14,
					BaseDashSpeed = 150,
					DashSpeedMultiplier = 3.1,
					EndDashSpeedMultiplier = 1.35,
					MaxDashSpeed = 260,
				},
				FireBurst = {
					KeyCode = Enum.KeyCode.E,
					Cooldown = 14,
					Radius = 10,
					Duration = 0.6,
				},
			},
		},
	},
}

local function normalizeIdentifier(value)
	if typeof(value) ~= "string" then
		return nil
	end

	local normalized = value:match("^%s*(.-)%s*$")
	if normalized == "" then
		return nil
	end

	return normalized
end

for fruitKey, fruit in pairs(DevilFruits.FruitsByKey) do
	fruit.FruitKey = fruit.FruitKey or fruitKey
	fruit.AssetFolder = fruit.AssetFolder or fruit.FruitKey
	fruit.AbilityModule = fruit.AbilityModule or fruit.FruitKey
	DevilFruits.Fruits[fruit.DisplayName] = fruit
end

function DevilFruits.GetFruit(identifier)
	local normalized = normalizeIdentifier(identifier)
	if not normalized then
		return nil
	end

	return DevilFruits.Fruits[normalized] or DevilFruits.FruitsByKey[normalized]
end

function DevilFruits.GetFruitByKey(fruitKey)
	local normalized = normalizeIdentifier(fruitKey)
	if not normalized then
		return nil
	end

	return DevilFruits.FruitsByKey[normalized]
end

function DevilFruits.ResolveFruitName(identifier)
	if identifier == DevilFruits.None then
		return DevilFruits.None
	end

	local fruit = DevilFruits.GetFruit(identifier)
	return fruit and fruit.DisplayName or nil
end

function DevilFruits.GetFruitKey(identifier)
	local fruit = DevilFruits.GetFruit(identifier)
	return fruit and fruit.FruitKey or nil
end

function DevilFruits.GetAbility(fruitIdentifier, abilityName)
	local fruit = DevilFruits.GetFruit(fruitIdentifier)
	if not fruit or typeof(abilityName) ~= "string" then
		return nil
	end

	return fruit.Abilities and fruit.Abilities[abilityName] or nil
end

return DevilFruits
