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
		BurstTopLevelPivotCorrections = {
			A = {
				LocalOffset = Vector3.zero,
				PreserveY = true,
				PreserveZ = true,
			},
		},
		EffectCandidates = FlameBurstEffectCandidates,
		StartupChildCandidates = FlameBurstStartupChildCandidates,
		BurstChildCandidates = FlameBurstBurstChildCandidates,
		EffectName = FlameBurstEffectCandidates[1] or "Flame burst",
		StartupChildName = FlameBurstStartupChildCandidates[1] or "Start up",
		BurstChildName = FlameBurstBurstChildCandidates[1] or "Burst",
	},
	FlameDash = {
		EffectCandidates = FlameDashEffectCandidates,
		StartupChildCandidates = FlameDashStartupChildCandidates,
		HeadAssetCandidates = FlameDashHeadAssetCandidates,
		PartAssetCandidates = FlameDashPartAssetCandidates,
		TrailAssetCandidates = FlameDashTrailAssetCandidates,
		EffectName = FlameDashEffectCandidates[1] or "Flame Dash",
		StartupChildName = FlameDashStartupChildCandidates[1] or "Startup",
		PrimaryChildName = FlameDashHeadAssetCandidates[1] or "Dash",
		-- ParticleEmitter names to force off under every Flame Dash effect root (startup FX, body/head FX, trail FX2, trail bursts). Case-insensitive.
		-- Explorer: `wind` lives on FX under `left wind` / `right wind` attachments; trail FX2 uses `shockwave`, `fire`, etc.
		DisabledTrailEmitterNames = {
			wind = true,
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
