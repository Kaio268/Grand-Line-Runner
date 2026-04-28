local Workspace = game:GetService("Workspace")

local SukeServer = {}

local DEFAULT_DURATION = 3
local DEFAULT_FADE_OUT_TIME = 0.22
local DEFAULT_FADE_IN_TIME = 0.28
local DEFAULT_LOCAL_BODY_TRANSPARENCY = 0.68
local DEFAULT_LOCAL_DECAL_TRANSPARENCY = 0.72
local DEFAULT_OBSERVER_BODY_TRANSPARENCY = 1
local DEFAULT_OBSERVER_DECAL_TRANSPARENCY = 1
local DEFAULT_SHIMMER_COLOR = Color3.fromRGB(193, 255, 245)
local DEFAULT_SHIMMER_ACCENT_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_HIGHLIGHT_FILL_TRANSPARENCY = 0.88
local DEFAULT_HIGHLIGHT_OUTLINE_TRANSPARENCY = 0.36
local DEFAULT_PARTICLE_RATE = 14
local DEFAULT_PARTICLE_TRANSPARENCY = 0.7
local DEFAULT_PARTICLE_LIFETIME = 0.65
local DEFAULT_PULSE_PERIOD = 0.7

local function clampNumber(value, fallback, minValue, maxValue)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return fallback
	end

	return math.clamp(numericValue, minValue, maxValue)
end

local function resolveColor(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

function SukeServer.Fade(context)
	local abilityConfig = context.AbilityConfig or {}
	local vfxConfig = type(abilityConfig.Vfx) == "table" and abilityConfig.Vfx or {}
	local duration = clampNumber(abilityConfig.Duration, DEFAULT_DURATION, 0.1, 10)
	local startedAt = Workspace:GetServerTimeNow()

	return {
		Phase = "Start",
		StartedAt = startedAt,
		EndTime = startedAt + duration,
		Duration = duration,
		FadeOutTime = clampNumber(abilityConfig.FadeOutTime, DEFAULT_FADE_OUT_TIME, 0, 1),
		FadeInTime = clampNumber(abilityConfig.FadeInTime, DEFAULT_FADE_IN_TIME, 0, 1),
		LocalBodyTransparency = clampNumber(
			abilityConfig.LocalBodyTransparency or abilityConfig.BodyTransparency,
			DEFAULT_LOCAL_BODY_TRANSPARENCY,
			0,
			0.95
		),
		LocalDecalTransparency = clampNumber(
			abilityConfig.LocalDecalTransparency or abilityConfig.DecalTransparency,
			DEFAULT_LOCAL_DECAL_TRANSPARENCY,
			0,
			0.98
		),
		ObserverBodyTransparency = clampNumber(
			abilityConfig.ObserverBodyTransparency,
			DEFAULT_OBSERVER_BODY_TRANSPARENCY,
			0,
			1
		),
		ObserverDecalTransparency = clampNumber(
			abilityConfig.ObserverDecalTransparency,
			DEFAULT_OBSERVER_DECAL_TRANSPARENCY,
			0,
			1
		),
		ShimmerColor = resolveColor(vfxConfig.ShimmerColor, DEFAULT_SHIMMER_COLOR),
		ShimmerAccentColor = resolveColor(vfxConfig.ShimmerAccentColor, DEFAULT_SHIMMER_ACCENT_COLOR),
		HighlightFillTransparency = clampNumber(vfxConfig.HighlightFillTransparency, DEFAULT_HIGHLIGHT_FILL_TRANSPARENCY, 0, 1),
		HighlightOutlineTransparency = clampNumber(vfxConfig.HighlightOutlineTransparency, DEFAULT_HIGHLIGHT_OUTLINE_TRANSPARENCY, 0, 1),
		ParticleRate = clampNumber(vfxConfig.ParticleRate, DEFAULT_PARTICLE_RATE, 0, 80),
		ParticleTransparency = clampNumber(vfxConfig.ParticleTransparency, DEFAULT_PARTICLE_TRANSPARENCY, 0, 1),
		ParticleLifetime = clampNumber(vfxConfig.ParticleLifetime, DEFAULT_PARTICLE_LIFETIME, 0.1, 2),
		PulsePeriod = clampNumber(vfxConfig.PulsePeriod, DEFAULT_PULSE_PERIOD, 0.2, 3),
	}
end

function SukeServer.ClearRuntimeState(_player)
	-- Fade stores no server runtime state; client visuals clean themselves up.
end

function SukeServer.GetLegacyHandler()
	return SukeServer
end

return SukeServer
