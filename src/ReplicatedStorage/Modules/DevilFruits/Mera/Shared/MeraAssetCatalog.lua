local MeraAssetCatalog = {}

MeraAssetCatalog.AnimationCandidates = {
	FlameDash = { "Flame Dash", "FlameDash", "Dash" },
	FireBurst = { "Flame burst", "Flame Burst", "FlameBurst" },
}

MeraAssetCatalog.RuntimeAnimationFallbacks = {
	FlameDash = {
		{
			Type = "animation_id",
			Name = "ProjectSlapDashFallback",
			AnimationId = "rbxassetid://119351181413931",
			Path = "ReplicatedStorage/Gears/Slap/Client.client.lua",
			Source = "project_runtime_primary_slap_dash",
			SupportsReleaseMarker = false,
		},
	},
	FireBurst = {
		{
			Type = "animation_id",
			Name = "ProjectSlapBurstFallback",
			AnimationId = "rbxassetid://119351181413931",
			Path = "ReplicatedStorage/Gears/Slap/Client.client.lua",
			Source = "project_runtime_primary_slap_burst",
			SupportsReleaseMarker = false,
		},
	},
}

MeraAssetCatalog.VfxEffectCandidates = {
	FlameDash = { "Flame Dash" },
	FireBurst = { "Flame burst", "Flame Burst" },
}

MeraAssetCatalog.VfxChildCandidates = {
	FlameDashStartup = { "Startup", "Start up", "FX" },
	FlameDashBody = { "Dash", "FX" },
	FlameDashTrail = { "Part", "FX2", "Trail" },
	FireBurstStartup = { "Start up", "Startup" },
	FireBurstBurst = { "Burst", "FX" },
}

local function appendUnique(target, seen, value)
	if typeof(value) ~= "string" or value == "" or seen[value] then
		return
	end

	seen[value] = true
	target[#target + 1] = value
end

function MeraAssetCatalog.BuildCandidateList(primaryName, fallbackNames)
	local candidates = {}
	local seen = {}

	appendUnique(candidates, seen, primaryName)

	for _, candidate in ipairs(fallbackNames or {}) do
		appendUnique(candidates, seen, candidate)
	end

	return candidates
end

function MeraAssetCatalog.GetAnimationCandidates(moveName, configuredAssetName, defaultAssetName)
	return MeraAssetCatalog.BuildCandidateList(
		configuredAssetName or defaultAssetName,
		MeraAssetCatalog.AnimationCandidates[moveName]
	)
end

function MeraAssetCatalog.GetRuntimeAnimationFallbacks(moveName)
	return MeraAssetCatalog.RuntimeAnimationFallbacks[moveName] or {}
end

function MeraAssetCatalog.GetVfxEffectCandidates(moveName)
	return MeraAssetCatalog.VfxEffectCandidates[moveName] or {}
end

function MeraAssetCatalog.GetVfxChildCandidates(stageName)
	return MeraAssetCatalog.VfxChildCandidates[stageName] or {}
end

return MeraAssetCatalog
