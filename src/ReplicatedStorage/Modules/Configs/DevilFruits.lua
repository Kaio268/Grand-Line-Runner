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
			ToolGripBias = Vector3.new(0.72, -0.12, 0.18),
			Abilities = {
				FlameDash = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 5,
					DashDistance = 56,
					DashDuration = 0.2,
					InstantDashFraction = 0.18,
					DistanceSpeedBonusFactor = 0.08,
					MaxDistanceSpeedBonus = 18,
					BaseDashSpeed = 175,
					DashSpeedMultiplier = 3.35,
					EndDashSpeedMultiplier = 1.75,
					MaxDashSpeed = 320,
				},
				FireBurst = {
					KeyCode = Enum.KeyCode.E,
					Cooldown = 14,
					Radius = 10,
					Duration = 0.6,
				},
			},
		},
		Hie = {
			Id = "HieHieNoMi",
			FruitKey = "Hie",
			DisplayName = "Hie Hie no Mi",
			AssetFolder = "Hie",
			AbilityModule = "Hie",
			Rarity = "Legendary",
			ToolGripBias = Vector3.new(0.72, -0.12, 0.18),
			Abilities = {
				FreezeShot = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 8,
					Range = 120,
					ProjectileSpeed = 170,
					ProjectileRadius = 1.2,
					FreezeDuration = 3,
				},
				IceBoost = {
					KeyCode = Enum.KeyCode.E,
					Cooldown = 18,
					Duration = 4,
					SpeedMultiplier = 2,
				},
			},
		},
		Gomu = {
			Id = "GomuGomuNoMi",
			FruitKey = "Gomu",
			DisplayName = "Gomu Gomu no Mi",
			AssetFolder = "Gomu",
			AbilityModule = "Gomu",
			Rarity = "Rare",
			ToolGripBias = Vector3.new(0.72, -0.12, 0.18),
			Abilities = {
				RubberLaunch = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 8,
					LaunchDistance = 20,
					LaunchDuration = 0.35,
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
