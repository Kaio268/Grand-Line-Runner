local DevilFruits = {
	None = "",
	GripDefaults = {
		RuntimeGrip = CFrame.new(0, -0.08, -0.95),
		Models = {
			R6G = {
				RuntimeGrip = CFrame.new(),
			},
		},
		Contexts = {
			Eat = {
				RuntimeGrip = CFrame.new(0.12, 0.42, -0.58),
			},
		},
	},
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
					DashDistance = 116,
					DashDuration = 0.28,
					InstantDashFraction = 0.34,
					MaxInstantDashDistance = 12,
					DistanceSpeedBonusFactor = 0.18,
					MaxDistanceSpeedBonus = 32,
					BaseDashSpeed = 330,
					DashSpeedMultiplier = 4.8,
					EndDashSpeedMultiplier = 2.8,
					RequiredSpeedMultiplier = 1.08,
					MaxDashSpeed = 580,
					EndCarrySpeedFactor = 0.9,
					MinEndCarrySpeed = 76,
					CompletionTolerance = 3,
					RuntimeGrace = 0.28,
					ClientCorrectionSnapDistance = 12,
					ClientDistanceTolerance = 6,
					FinalSnapTolerance = 4,
					RequestPayloadSchema = {
						MaxKeys = 2,
						MaxHintDistance = 200,
						Fields = {
							DashTargetPosition = "Vector3",
							VisualDirection = "DirectionVector3",
						},
					},
					Animation = {
						AssetName = "Flame Dash",
						FadeTime = 0.04,
						StopFadeTime = 0.08,
						PlaybackSpeed = 1.12,
					},
				},
				FireBurst = {
					KeyCode = Enum.KeyCode.E,
					Cooldown = 14,
					Radius = 30,
					Duration = 0.6,
					VisualBaseRadius = 10,
					Animation = {
						AssetName = "Flame burst",
						ReleaseMarker = "Release",
						ReleaseFallbackTime = 0.22,
						FadeTime = 0.06,
						StopFadeTime = 0.1,
						PlaybackSpeed = 1,
					},
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
					Animation = {
						AssetName = "IceBlast",
						ReleaseMarker = "IceBlast",
						ReleaseFallbackTime = 0.22,
						FadeTime = 0.08,
						StopFadeTime = 0.08,
					},
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
					Animation = {
						AssetName = "IceBoost",
						FadeTime = 0.08,
						StopFadeTime = 0.12,
						Looped = true,
					},
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
			GripProfiles = {
				Models = {
					R6G = {
						RuntimeGrip = CFrame.new(),
					},
					ModelSwap = {
						RuntimeGrip = CFrame.new(),
					},
				},
			},
			Aliases = { "gomu", "gomu gomu" },
			Abilities = {
				RubberLaunch = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 8,
					LaunchDistance = 20,
					LaunchDuration = 0.35,
					Animation = {
						AssetName = "Rocket",
						FadeTime = 0.04,
						StopFadeTime = 0.08,
						PlaybackSpeed = 1,
					},
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
		Mogu = {
			Id = "MoguMoguNoMi",
			FruitKey = "Mogu",
			DisplayName = "Mogu Mogu no Mi",
			AssetFolder = "Mogu",
			AbilityModule = "Mogu",
			Rarity = "Common",
			ToolGripBias = Vector3.new(0.72, -0.12, 0.18),
			Aliases = { "mogu", "mogu mogu", "mole", "mole fruit" },
			Abilities = {
				Burrow = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 14,
					CooldownStartsOn = "Resolve",
					ServerRequestThrottle = 0.18,
					BurrowDuration = 5,
					MoveSpeed = 24,
					HazardProtectionRadius = 12,
					GroundProbeHeight = 6,
					GroundProbeDepth = 18,
					RootGroundClearance = 3.2,
					SurfaceResolveGrace = 0.45,
					TrailInterval = 0.16,
					TrailWidth = 2.6,
					TrailHeight = 0.32,
					EntryBurstRadius = 3.2,
					ResolveBurstRadius = 4.2,
					ConcealTransparency = 1,
					Animation = {
						Start = {
							AssetName = "Dive",
							FadeTime = 0.05,
							StopFadeTime = 0.08,
							PlaybackSpeed = 1,
							ConcealDelay = 0.18,
						},
						Resolve = {
							AssetName = "Exit",
							FadeTime = 0.05,
							StopFadeTime = 0.1,
							PlaybackSpeed = 1,
						},
					},
					Vfx = {
						RootSegments = { "Assets", "VFX", "Mogu" },
						Entry = {
							AssetName = "Dig",
							EmitCount = 10,
							ActiveTime = 0.16,
							CleanupBuffer = 0.7,
						},
						Trail = {
							UseAuthoredAsset = false,
							AssetName = "Burrow Trail",
							EmitCount = 5,
							CleanupBuffer = 0.85,
						},
						Resolve = {
							AssetName = "Jump",
							EmitCount = 12,
							ActiveTime = 0.18,
							CleanupBuffer = 0.8,
						},
					},
					RequestPayloadSchema = {
						MaxKeys = 1,
						Fields = {
							Direction = "DirectionVector3",
						},
					},
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
				PhoenixRebirth = {
					RestoreDelay = 0.45,
					ImmunityDuration = 1,
					RestoreHealthPercent = 1,
				},
			},
			Abilities = {
				PhoenixFlight = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 13,
					Duration = 4.5,
					TakeoffDuration = 0.4,
					InitialLift = 22,
					MaxRiseHeight = 132,
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
