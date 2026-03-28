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
			Aliases = { "mera", "mera mera" },
			Abilities = {
				FlameDash = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 5,
					ServerRequestThrottle = 0.18,
					DashDistance = 74,
					DashDuration = 0.15,
					InstantDashFraction = 0.34,
					MaxInstantDashDistance = 12,
					DistanceSpeedBonusFactor = 0.14,
					MaxDistanceSpeedBonus = 22,
					BaseDashSpeed = 300,
					DashSpeedMultiplier = 4.4,
					EndDashSpeedMultiplier = 2.4,
					RequiredSpeedMultiplier = 1.08,
					MaxDashSpeed = 460,
					EndCarrySpeedFactor = 0.88,
					MinEndCarrySpeed = 64,
					RequestPayloadSchema = {
						MaxKeys = 1,
						MaxHintDistance = 200,
						Fields = {
							DashTargetPosition = "Vector3",
						},
					},
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
			Aliases = { "hie", "hie hie" },
			Abilities = {
				FreezeShot = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 8,
					ServerRequestThrottle = 0.35,
					Range = 180,
					AimRayDistance = 700,
					MinimumAimDistance = 6,
					AllowVerticalAim = true,
					TurnThresholdDegrees = 28,
					ProjectileSpeed = 240,
					ProjectileRadius = 1.2,
					ImpactBurstRadius = 6,
					FreezeDuration = 3,
					MovementInheritanceFactor = 0.85,
					MaxInheritedSpeed = 140,
					SpawnLeadTime = 0.08,
					MaxSpawnLead = 8,
					RequestPayloadSchema = {
						MaxKeys = 1,
						MaxHintDistance = 700,
						Fields = {
							AimPosition = "Vector3",
						},
					},
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
			Aliases = { "gomu", "gomu gomu" },
			Abilities = {
				RubberLaunch = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 8,
					LaunchDistance = 20,
					LaunchDuration = 0.35,
					RequestPayloadSchema = {
						MaxKeys = 2,
						MaxHintDistance = 600,
						Fields = {
							AimPosition = "Vector3",
							TargetPlayerUserId = "UserId",
						},
					},
				},
			},
		},
		Bomu = {
			Id = "BomuBomuNoMi",
			FruitKey = "Bomu",
			DisplayName = "Bomu Bomu no Mi",
			AssetFolder = "Bomu",
			AbilityModule = "Bomu",
			Rarity = "Rare",
			ToolGripBias = Vector3.new(0.72, -0.12, 0.18),
			Aliases = { "bomu", "bomu bomu", "bomb", "bomb fruit" },
			Abilities = {
				LandMine = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 15,
					CooldownStartsOn = "Resolve",
					ServerRequestThrottle = 0.35,
					PlacementDistance = 4,
					MineLifetime = 60,
					Radius = 8,
					KnockdownDuration = 0.75,
					KnockbackHorizontal = 34,
					KnockbackVertical = 10,
					OwnerLaunchRadius = 8,
					OwnerLaunchHorizontal = 8,
					OwnerLaunchVertical = 62,
				},
			},
		},
		Tori = {
			Id = "ToriToriNoMiModelPhoenix",
			FruitKey = "Tori",
			DisplayName = "Tori Tori no Mi",
			AssetFolder = "Tori",
			AbilityModule = "Tori",
			Rarity = "Mythic",
			ToolGripBias = Vector3.new(0.72, -0.12, 0.18),
			Aliases = {
				"tori",
				"tori tori",
				"phoenix",
				"phoenix fruit",
				"tori phoenix",
			},
			Passives = {
				PhoenixGlide = {
					JumpHeightMultiplier = 1.2,
					FallSpeed = 18,
					ForwardSpeed = 28,
					Responsiveness = 8,
					ActivateMaxVerticalSpeed = 6,
				},
			},
			Abilities = {
				PhoenixFlight = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 13,
					Duration = 4.5,
					TakeoffDuration = 0.4,
					InitialLift = 22,
					MaxRiseHeight = 56,
					FlightSpeed = 80,
					VerticalSpeed = 90,
					MaxDescendSpeed = 72,
					HorizontalResponsiveness = 14,
				},
				PhoenixFlameShield = {
					KeyCode = Enum.KeyCode.E,
					Cooldown = 20,
					Radius = 13,
					Duration = 2.75,
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

	return string.lower(normalized)
end

local lookupByIdentifier = {}

local function registerIdentifier(identifier, fruit)
	local normalized = normalizeIdentifier(identifier)
	if not normalized then
		return
	end

	lookupByIdentifier[normalized] = fruit
end

for fruitKey, fruit in pairs(DevilFruits.FruitsByKey) do
	fruit.FruitKey = fruit.FruitKey or fruitKey
	fruit.AssetFolder = fruit.AssetFolder or fruit.FruitKey
	fruit.AbilityModule = fruit.AbilityModule or fruit.FruitKey
	fruit.Aliases = fruit.Aliases or {}
	DevilFruits.Fruits[fruit.DisplayName] = fruit

	registerIdentifier(fruit.FruitKey, fruit)
	registerIdentifier(fruit.DisplayName, fruit)
	registerIdentifier(fruit.Id, fruit)

	for _, alias in ipairs(fruit.Aliases) do
		registerIdentifier(alias, fruit)
	end
end

function DevilFruits.GetFruit(identifier)
	local normalized = normalizeIdentifier(identifier)
	if not normalized then
		return nil
	end

	return lookupByIdentifier[normalized]
end

function DevilFruits.GetFruitByKey(fruitKey)
	local fruit = DevilFruits.GetFruit(fruitKey)
	if fruit then
		return fruit
	end

	return nil
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

function DevilFruits.GetAllFruits()
	local fruits = {}
	for _, fruit in pairs(DevilFruits.FruitsByKey) do
		fruits[#fruits + 1] = fruit
	end

	table.sort(fruits, function(a, b)
		return a.DisplayName < b.DisplayName
	end)

	return fruits
end

return DevilFruits
