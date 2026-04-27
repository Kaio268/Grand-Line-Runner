local ToriServer = {}

local DEFAULT_PHOENIX_FLAME_SHIELD_RADIUS = 18

local function clampPositiveNumber(value, fallback)
	local numericValue = tonumber(value)
	if not numericValue or numericValue <= 0 then
		return fallback
	end

	return numericValue
end

local function clampNonNegativeNumber(value, fallback)
	local numericValue = tonumber(value)
	if not numericValue or numericValue < 0 then
		return fallback
	end

	return numericValue
end

local function copyStringArray(value)
	if type(value) ~= "table" then
		return nil
	end

	local result = {}
	for _, item in ipairs(value) do
		if typeof(item) == "string" and item ~= "" then
			result[#result + 1] = item
		end
	end

	return if #result > 0 then result else nil
end

local function resolvePhoenixShieldRadius(abilityConfig)
	local configuredRadius = abilityConfig.ShieldRadius
	if configuredRadius == nil then
		configuredRadius = abilityConfig.Radius
	end

	return clampPositiveNumber(configuredRadius, DEFAULT_PHOENIX_FLAME_SHIELD_RADIUS)
end

local function estimatePhoenixFlightHeightDelay(abilityConfig, initialLift, maxRiseHeight, takeoffDuration)
	local resolvedInitialLift = math.max(0, initialLift)
	local resolvedMaxRiseHeight = math.max(resolvedInitialLift, maxRiseHeight)
	local verticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, 90)

	return math.max(takeoffDuration, resolvedMaxRiseHeight / verticalSpeed)
end

function ToriServer.PhoenixFlight(context)
	local abilityConfig = context.AbilityConfig
	local duration = clampPositiveNumber(abilityConfig.Duration, 4.5)
	local startupDuration = clampNonNegativeNumber(abilityConfig.FlightStartupDuration, 0.85)
	local takeoffDuration = clampPositiveNumber(abilityConfig.TakeoffDuration, 0.4)
	local initialLift = clampPositiveNumber(abilityConfig.InitialLift, 22)
	local maxRiseHeight = clampPositiveNumber(abilityConfig.MaxRiseHeight, 132)
	local verticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, 90)
	local heightDelay = estimatePhoenixFlightHeightDelay(abilityConfig, initialLift, maxRiseHeight, takeoffDuration)

	return {
		Duration = duration,
		StartupDuration = startupDuration,
		TakeoffDuration = takeoffDuration,
		InitialLift = initialLift,
		MaxRiseHeight = maxRiseHeight,
		FlightSpeed = clampPositiveNumber(abilityConfig.FlightSpeed, 80),
		FlightSpeedScaleReference = clampPositiveNumber(abilityConfig.FlightSpeedScaleReference, 17),
		FlightSpeedScaleStrength = clampNonNegativeNumber(abilityConfig.FlightSpeedScaleStrength, 0.5),
		VerticalSpeed = verticalSpeed,
		MaxDescendSpeed = clampPositiveNumber(abilityConfig.MaxDescendSpeed, 72),
		HorizontalResponsiveness = clampPositiveNumber(abilityConfig.HorizontalResponsiveness, 14),
		TrailPartNames = copyStringArray(abilityConfig.FlightTrailPartNames),
		TrailOffset = typeof(abilityConfig.FlightTrailOffset) == "CFrame" and abilityConfig.FlightTrailOffset or nil,
	}, {
		CooldownDelay = startupDuration + heightDelay + duration,
	}
end

function ToriServer.PhoenixFlameShield(context)
	local abilityConfig = context.AbilityConfig
	local duration = clampPositiveNumber(abilityConfig.Duration, 5)

	return {
		Radius = resolvePhoenixShieldRadius(abilityConfig),
		Duration = duration,
		AnimationLockDuration = clampPositiveNumber(abilityConfig.AnimationLockDuration, 1.6666667),
	}, {
		CooldownDelay = duration,
	}
end

function ToriServer.GetLegacyHandler()
	return ToriServer
end

return ToriServer
