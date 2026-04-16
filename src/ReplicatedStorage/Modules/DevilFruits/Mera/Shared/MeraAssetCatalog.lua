local MeraAssetCatalog = {}

MeraAssetCatalog.AnimationCandidates = {
	FlameDash = { "Flame Dash", "FlameDash", "Dash" },
	FireBurst = { "Flame burst", "Flame Burst", "FlameBurst" },
}

-- Ability animation fallbacks must stay fruit-specific. Reusing an unrelated slap
-- animation here produces misleading permission errors and incorrect playback.
MeraAssetCatalog.RuntimeAnimationFallbacks = {
	FlameDash = {},
	FireBurst = {},
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
