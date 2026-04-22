local HELD_FRUIT_GRIP_BIAS = Vector3.new(0.96, -0.06, 0.12)
local HELD_FRUIT_RUNTIME_GRIP = CFrame.new(0.18, -0.9, -1.35) * CFrame.Angles(math.rad(-4), math.rad(10), math.rad(-8))
local DEFAULT_EQUIPPED_HOLD_OFFSET_POSITION = Vector3.new(0, 0, 0)
local DEFAULT_EQUIPPED_HOLD_OFFSET_ROTATION = Vector3.new(0, 180, 0)
local HELD_FRUIT_R6_HAND_TARGET_LOCAL = Vector3.new(1, 0.12, -5.5)
local HELD_FRUIT_R6G_HAND_TARGET_LOCAL = Vector3.new(1, 0.12, -5.5)
local HELD_FRUIT_R6_ARM_TARGET_REACH_SCALE = 1
local HELD_FRUIT_R6_ARM_TARGET_REACH_OFFSET = 0
local HELD_FRUIT_R6_ARM_TARGET_OFFSET_LOCAL = Vector3.zero
local HELD_FRUIT_R6G_ARM_TARGET_REACH_SCALE = 1
local HELD_FRUIT_R6G_ARM_TARGET_REACH_OFFSET = 0
local HELD_FRUIT_R6G_ARM_TARGET_OFFSET_LOCAL = Vector3.new(0, -0.25, 0)
local HELD_FRUIT_R6G_EQUIPPED_HOLD_OFFSET_POSITION = Vector3.new(0, 0, 0)
local HELD_FRUIT_R6G_EQUIPPED_HOLD_OFFSET_ROTATION = Vector3.new(-90, 180, 0)
local HELD_FRUIT_R6_SHOULDER_POSE = CFrame.Angles(math.rad(10), math.rad(10), math.rad(40))
local HELD_FRUIT_R6G_SHOULDER_POSE = CFrame.Angles(math.rad(10), math.rad(10), math.rad(36))
local HELD_FRUIT_R6G_ELBOW_POSE = CFrame.Angles(math.rad(-8), 0, 0)
local HELD_FRUIT_R15_SHOULDER_POSE = CFrame.Angles(math.rad(-34), math.rad(-6), math.rad(18))
local HELD_FRUIT_R15_ELBOW_POSE = CFrame.Angles(math.rad(-8), 0, 0)
local HELD_FRUIT_R15_WRIST_POSE = CFrame.Angles(math.rad(0), math.rad(0), math.rad(-8))

local DevilFruits = {
	None = "",
	GripDefaults = {
		RuntimeGrip = HELD_FRUIT_RUNTIME_GRIP,
		EquippedHoldOffset = {
			Position = DEFAULT_EQUIPPED_HOLD_OFFSET_POSITION,
			RotationDegrees = DEFAULT_EQUIPPED_HOLD_OFFSET_ROTATION,
		},
		EquippedPresentation = {
			Enabled = true,
			DebugAttribute = "DebugFruitHoldPresentation",
			FadeSpeed = 14,
			DisableContexts = {
				Eat = true,
			},
			R6 = {
				Mode = "ArmTarget",
				BlendMode = "Replace",
				HandTargetLocal = HELD_FRUIT_R6_HAND_TARGET_LOCAL,
				ArmTargetReachScale = HELD_FRUIT_R6_ARM_TARGET_REACH_SCALE,
				ArmTargetReachOffset = HELD_FRUIT_R6_ARM_TARGET_REACH_OFFSET,
				ArmTargetOffsetLocal = HELD_FRUIT_R6_ARM_TARGET_OFFSET_LOCAL,
				Joints = {
					["Right Shoulder"] = HELD_FRUIT_R6_SHOULDER_POSE,
				},
			},
			R15 = {
				Joints = {
					RightShoulder = HELD_FRUIT_R15_SHOULDER_POSE,
					RightElbow = HELD_FRUIT_R15_ELBOW_POSE,
					RightWrist = HELD_FRUIT_R15_WRIST_POSE,
				},
			},
			R6G = {
				Mode = "ArmTarget",
				BlendMode = "Replace",
				HandTargetLocal = HELD_FRUIT_R6G_HAND_TARGET_LOCAL,
				ArmTargetReachScale = HELD_FRUIT_R6G_ARM_TARGET_REACH_SCALE,
				ArmTargetReachOffset = HELD_FRUIT_R6G_ARM_TARGET_REACH_OFFSET,
				ArmTargetOffsetLocal = HELD_FRUIT_R6G_ARM_TARGET_OFFSET_LOCAL,
				Joints = {
					RightShoulder = HELD_FRUIT_R6G_SHOULDER_POSE,
					RightElbow = HELD_FRUIT_R6G_ELBOW_POSE,
				},
			},
		},
		Models = {
			R6G = {
				EquippedHoldOffset = {
					Position = HELD_FRUIT_R6G_EQUIPPED_HOLD_OFFSET_POSITION,
					RotationDegrees = HELD_FRUIT_R6G_EQUIPPED_HOLD_OFFSET_ROTATION,
				},
			},
		},
		Contexts = {
			Eat = {
				ApplyEquippedHoldOffset = true,
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
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
			Aliases = { "mera", "mera mera" },
			Abilities = {
				FlameDash = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 5,
					ServerRequestThrottle = 0.18,
					DashDistance = 168,
					DashDuration = 0.1,
					InstantDashFraction = 0.4,
					MaxInstantDashDistance = 28,
					WallShortenedInstantThreshold = 28,
					SideWallNormalDotThreshold = 0.45,
					WallSlideMinDistanceGain = 8,
					SpeedScalingBaseline = 16,
					DistanceSpeedBonusFactor = 1.25,
					MaxDistanceSpeedBonus = 140,
					BaseDashSpeed = 420,
					DashSpeedMultiplier = 5.2,
					DashSpeedBonusFactor = 3.5,
					MaxDashSpeedBonus = 180,
					EndDashSpeedMultiplier = 2.8,
					RequiredSpeedMultiplier = 1.08,
					MaxDashSpeed = 760,
					EndCarrySpeedFactor = 0.9,
					EndCarryDuration = 0.1,
					EndCarryMaxDistance = 2.5,
					MinEndCarrySpeed = 76,
					CompletionTolerance = 3,
					RuntimeGrace = 0.28,
					ClientCorrectionSnapDistance = 12,
					ClientDistanceTolerance = 6,
					FinalSnapTolerance = 4,
					RequestPayloadSchema = {
						MaxKeys = 2,
						MaxHintDistance = 320,
						Fields = {
							DashTargetPosition = "Vector3",
							VisualDirection = "DirectionVector3",
						},
					},
					Animation = {
						AnimationKey = "Mera.FlameDash",
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
						AnimationKey = "Mera.FlameBurstR6",
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
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
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
						AnimationKey = "Hie.IceBlast",
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
						AnimationKey = "Hie.IceBoost",
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
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
			GripProfiles = {
				Models = {
					ModelSwap = {
						RuntimeGrip = HELD_FRUIT_RUNTIME_GRIP,
					},
				},
			},
			Aliases = { "gomu", "gomu gomu" },
			Abilities = {
				RubberLaunch = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 20,
					LaunchDistance = 38,
					LaunchDuration = 0.5,
					SpeedScaleReference = 70,
					SpeedLaunchDistanceBonus = 32,
					Animation = {
						AnimationKey = "Gomu.Rocket",
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
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
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
					VisualBaseRadius = 8,
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
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
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
							AnimationKey = "Mogu.Dive",
							FadeTime = 0.05,
							StopFadeTime = 0.08,
							PlaybackSpeed = 1,
							EntryCueMarkers = { "EnterGround", "EntryVfx", "DigImpact", "Dig" },
							EntryCueFallbackTime = 0.24,
							MovementCueMarkers = { "FullyUnderground", "Underground", "BurrowMove", "MovementStart" },
							MovementCueFallbackTime = 0.42,
							ConcealDelay = 0.24,
						},
						Resolve = {
							AnimationKey = "Mogu.Exit",
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
		Suke = {
			Id = "SukeSukeNoMi",
			FruitKey = "Suke",
			DisplayName = "Suke Suke no Mi",
			AssetFolder = "Suke",
			AbilityModule = "Suke",
			Rarity = "Common",
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
			Aliases = { "suke", "suke suke", "invisible", "invisibility fruit" },
			Abilities = {
				Fade = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 14,
					ServerRequestThrottle = 0.18,
					Duration = 3,
					FadeOutTime = 0.22,
					FadeInTime = 0.28,
					LocalBodyTransparency = 0.68,
					LocalDecalTransparency = 0.72,
					ObserverBodyTransparency = 1,
					ObserverDecalTransparency = 1,
					Vfx = {
						ShimmerColor = Color3.fromRGB(193, 255, 245),
						ShimmerAccentColor = Color3.fromRGB(255, 255, 255),
						HighlightFillTransparency = 0.88,
						HighlightOutlineTransparency = 0.36,
						ParticleRate = 14,
						ParticleTransparency = 0.7,
						ParticleLifetime = 0.65,
						PulsePeriod = 0.7,
					},
				},
			},
		},
		Horo = {
			Id = "HoroHoroNoMi",
			FruitKey = "Horo",
			DisplayName = "Horo Horo no Mi",
			AssetFolder = "Horo",
			AbilityModule = "Horo",
			Rarity = "Common",
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
			Aliases = { "horo", "horo horo", "ghost", "ghost fruit", "projection fruit" },
			Abilities = {
				GhostProjection = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 18,
					ServerRequestThrottle = 0.25,
					Duration = 5,
					GhostSpeed = 15,
					CarrySpeed = 8,
					GhostJumpPower = 0,
					GhostJumpHeight = 0,
					MaxDistanceFromBody = 68,
					RewardInteractRadius = 12,
					HazardProbeRadius = 3.4,
					ServerHazardProbeInterval = 0.08,
					ClientHazardReportThrottle = 0.12,
					PickupThrottle = 0.18,
					BodyWalkSpeed = 0,
					BodyJumpPower = 0,
					BodyHighlightFillTransparency = 0.82,
					BodyHighlightOutlineTransparency = 0.16,
					GhostTransparency = 0.42,
					GhostLocalTransparency = 0.2,
					Vfx = {
						GhostColor = Color3.fromRGB(198, 238, 255),
						GhostAccentColor = Color3.fromRGB(255, 255, 255),
						BodyHighlightColor = Color3.fromRGB(105, 167, 206),
						ParticleRate = 18,
						ParticleLifetime = 0.8,
						PulsePeriod = 0.75,
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
			ToolGripBias = HELD_FRUIT_GRIP_BIAS,
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
