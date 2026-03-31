local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local MeraAssetCatalog = require(script.Parent:WaitForChild("MeraAssetCatalog"))

local FlameBurstEffectCandidates = MeraAssetCatalog.GetVfxEffectCandidates("FireBurst")
local FlameBurstStartupChildCandidates = MeraAssetCatalog.GetVfxChildCandidates("FireBurstStartup")
local FlameBurstBurstChildCandidates = MeraAssetCatalog.GetVfxChildCandidates("FireBurstBurst")

local FlameDashEffectCandidates = MeraAssetCatalog.GetVfxEffectCandidates("FlameDash")
local FlameDashStartupChildCandidates = MeraAssetCatalog.GetVfxChildCandidates("FlameDashStartup")
local FlameDashHeadAssetCandidates = MeraAssetCatalog.GetVfxChildCandidates("FlameDashBody")
local FlameDashPartAssetCandidates = MeraAssetCatalog.GetVfxChildCandidates("FlameDashTrail")
local FlameDashTrailAssetCandidates = FlameDashPartAssetCandidates

local Config = {
	FruitKey = "Mera",
	FruitName = "Mera Mera no Mi",
	Debug = {
		EnableInfoLogsInStudio = true,
		EnableVerboseDebugLogs = false,
		EnableClientVerificationLogs = false,
		FlameDashLingerEnabled = false,
		FlameDashLingerTime = 2.5,
		UseWorkspaceFlameDashDebugSource = false,
		StripSavBlessings = true,
		DashClientLogsEnabled = false,
		DashClientReconciliationLogsEnabled = false,
		DashClientMoveLogsEnabled = false,
	},
	Logging = {
		InfoCooldown = 0.2,
		WarnCooldown = 3,
		DashClientCooldown = 0.2,
	},
	Shared = {
		RootSegments = { "Assets", "VFX", "Mera" },
		DefaultEmitCount = 20,
		RuntimeStopFadeTime = 0.12,
		WorkspaceFlameDashDebugSegments = { "Mera", "Flame Dash" },
	},
	FlameBurst = {
		LegacyRadius = 10,
		PreviousVisualRadius = 50,
		DisperseBuffer = 0.15,
		DisperseMinLifetime = 0.35,
		FadeTime = 0.22,
		BurstMeshEmitCulpritPattern = "meshslamimpackmesh",
		BurstMeshEmitMinForwardOffset = -0.35,
		EffectCandidates = FlameBurstEffectCandidates,
		StartupChildCandidates = FlameBurstStartupChildCandidates,
		BurstChildCandidates = FlameBurstBurstChildCandidates,
		EffectName = FlameBurstEffectCandidates[1] or "Flame burst",
		StartupChildName = FlameBurstStartupChildCandidates[1] or "Start up",
		BurstChildName = FlameBurstBurstChildCandidates[1] or "Burst",
	},
	FlameDash = {
		DefaultStageLifetime = 0.4,
		HeadRole = "head",
		PartRole = "part",
		TrailRole = "trail",
		EffectCandidates = FlameDashEffectCandidates,
		StartupChildCandidates = FlameDashStartupChildCandidates,
		HeadAssetCandidates = FlameDashHeadAssetCandidates,
		PartAssetCandidates = FlameDashPartAssetCandidates,
		TrailAssetCandidates = FlameDashTrailAssetCandidates,
		EffectName = FlameDashEffectCandidates[1] or "Flame Dash",
		StartupChildName = FlameDashStartupChildCandidates[1] or "Startup",
		PrimaryChildName = FlameDashHeadAssetCandidates[1] or "Dash",
		HeadProceduralPath = "procedural://Mera/FlameDash/HeadLockedFlame",
		PartProceduralPath = "procedural://Mera/FlameDash/PartSupportFlame",
		TrailProceduralPath = "procedural://Mera/FlameDash/PartSupportFlame",
		SplitMountAttribute = "EnableMeraFlameDashSplitMount",
		StartupRotationYDegrees = 180,
		StartupRotationCorrection = CFrame.Angles(0, math.rad(180), 0),
		DashPositionOffset = Vector3.new(0, -0.9, -1.1),
		DashRotationOffset = CFrame.Angles(math.rad(-90), math.rad(180), 0),
		DashMountLogInterval = 0.2,
		MimicPartRotation = CFrame.Angles(math.rad(-90), math.rad(180), 0),
		DebugSubgroupNames = {
			"Wind",
			"lines",
			"Ground",
			"Run",
			"Shockwave",
			"Spinning",
			"moving",
			"DashFx",
			"Particle Long Large",
		},
		ManualSubgroupOrder = {
			"Wind",
			"Shockwave",
			"Spinning",
			"moving",
		},
		ManualSubgroupConfigs = {
			Wind = {
				Behavior = "wind_shear",
				PartTransparency = 0.92,
				DecalTransparency = 0.2,
				TextureTransparency = 0.2,
				BaseScale = Vector3.new(0.96, 0.92, 1),
				ScaleAmplitude = Vector3.new(0.12, 0.08, 0.28),
				PositionScale = Vector3.new(1.04, 1, 1.16),
				PulseSpeed = 7,
				ForwardOffset = 0.55,
				SideOffset = 0.16,
				VerticalOffset = 0.14,
				RollAmplitude = math.rad(16),
				YawAmplitude = math.rad(7),
			},
			Shockwave = {
				Behavior = "shockwave_ring",
				PartTransparency = 0.9,
				DecalTransparency = 0.08,
				TextureTransparency = 0.08,
				BaseScale = Vector3.new(0.72, 1, 0.72),
				ScaleAmplitude = Vector3.new(1.1, 0, 1.1),
				PositionScale = Vector3.new(1.4, 1, 1.4),
				PulseSpeed = 2.6,
				ForwardOffset = -0.08,
				VerticalOffset = -0.02,
				YawAmplitude = math.rad(10),
			},
			Spinning = {
				Behavior = "spinning_orbit",
				PartTransparency = 0.88,
				DecalTransparency = 0.12,
				TextureTransparency = 0.12,
				BaseScale = Vector3.new(0.94, 0.94, 0.94),
				ScaleAmplitude = Vector3.new(0.16, 0.08, 0.16),
				PositionScale = Vector3.new(1.08, 1, 1.08),
				PulseSpeed = 5.5,
				SpinSpeed = math.rad(360),
				VerticalOffset = 0.08,
				RollAmplitude = math.rad(10),
			},
			moving = {
				Behavior = "moving_streak",
				PartTransparency = 0.72,
				DecalTransparency = 0.18,
				TextureTransparency = 0.18,
				BaseScale = Vector3.new(0.9, 0.9, 0.96),
				ScaleAmplitude = Vector3.new(0.14, 0.08, 0.3),
				PositionScale = Vector3.new(1.08, 1, 1.22),
				PulseSpeed = 4.8,
				ForwardTravel = 1.15,
				SideOffset = 0.14,
				VerticalOffset = 0.1,
				YawAmplitude = math.rad(5),
			},
		},
		Head = {
			ForwardOffset = 0,
			UpOffset = 0,
			TargetWidthRatio = 0.9,
			TargetDepthRatio = 0.75,
			ReferenceWidth = 1.8,
			ReferenceHeight = 5.2,
			MinTargetWidth = 0.85,
			MaxTargetWidth = 1.8,
			MinTargetDepth = 0.65,
			MaxTargetDepth = 1.6,
			HeightRatio = 1.05,
			MinHeight = 3.8,
			MaxHeight = 6.2,
			CenterUpRatio = 0.06,
			MinCenterUpOffset = 0.1,
			MaxCenterUpOffset = 0.35,
		},
		Trail = {
			BackOffset = 1.7,
			UpOffset = -2.35,
			StampLifetime = 0.28,
			PostStopHoldDuration = 0.65,
			OrderedFadeDuration = 0.09,
			OrderedFadeStepInterval = 0.04,
		},
	},
}

function Config.GetFruitConfig()
	return DevilFruitConfig.GetFruit(Config.FruitName)
end

function Config.GetAbilityConfig(abilityName)
	return DevilFruitConfig.GetAbility(Config.FruitName, abilityName)
end

return Config
