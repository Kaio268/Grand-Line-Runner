local ToriServer = {}

local DEFAULT_PHOENIX_FLAME_SHIELD_RADIUS = 18
local DEFAULT_PHOENIX_FLIGHT_DURATION = 4.5
local DEFAULT_PHOENIX_FLIGHT_STARTUP_DURATION = 0.85
local DEFAULT_PHOENIX_TAKEOFF_DURATION = 0.4
local DEFAULT_PHOENIX_INITIAL_LIFT = 22
local DEFAULT_PHOENIX_MAX_RISE_HEIGHT = 132
local DEFAULT_PHOENIX_VERTICAL_SPEED = 90
local DEFAULT_PHOENIX_FLIGHT_SPEED = 80
local DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_REFERENCE = 17
local DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_STRENGTH = 0.5
local DEFAULT_PHOENIX_MAX_DESCEND_SPEED = 72
local DEFAULT_PHOENIX_HORIZONTAL_RESPONSIVENESS = 14
local DEFAULT_PHOENIX_SHIELD_DURATION = 5
local DEFAULT_PHOENIX_SHIELD_ANIMATION_LOCK_DURATION = 1.6666667

local cachedToriPassiveService = nil

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
	local verticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, DEFAULT_PHOENIX_VERTICAL_SPEED)

	return math.max(takeoffDuration, resolvedMaxRiseHeight / verticalSpeed)
end

local function getToriPassiveService()
	if cachedToriPassiveService then
		return cachedToriPassiveService
	end

	cachedToriPassiveService = require(script.Parent:WaitForChild("ToriPassiveService"))
	return cachedToriPassiveService
end

function ToriServer.PhoenixFlight(context)
	local abilityConfig = context.AbilityConfig
	local duration = clampPositiveNumber(abilityConfig.Duration, DEFAULT_PHOENIX_FLIGHT_DURATION)
	local startupDuration = clampNonNegativeNumber(abilityConfig.FlightStartupDuration, DEFAULT_PHOENIX_FLIGHT_STARTUP_DURATION)
	local takeoffDuration = clampPositiveNumber(abilityConfig.TakeoffDuration, DEFAULT_PHOENIX_TAKEOFF_DURATION)
	local initialLift = clampPositiveNumber(abilityConfig.InitialLift, DEFAULT_PHOENIX_INITIAL_LIFT)
	local maxRiseHeight = clampPositiveNumber(abilityConfig.MaxRiseHeight, DEFAULT_PHOENIX_MAX_RISE_HEIGHT)
	local verticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, DEFAULT_PHOENIX_VERTICAL_SPEED)
	local heightDelay = estimatePhoenixFlightHeightDelay(abilityConfig, initialLift, maxRiseHeight, takeoffDuration)

	return {
		Duration = duration,
		StartupDuration = startupDuration,
		TakeoffDuration = takeoffDuration,
		InitialLift = initialLift,
		MaxRiseHeight = maxRiseHeight,
		FlightSpeed = clampPositiveNumber(abilityConfig.FlightSpeed, DEFAULT_PHOENIX_FLIGHT_SPEED),
		FlightSpeedScaleReference = clampPositiveNumber(
			abilityConfig.FlightSpeedScaleReference,
			DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_REFERENCE
		),
		FlightSpeedScaleStrength = clampNonNegativeNumber(
			abilityConfig.FlightSpeedScaleStrength,
			DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_STRENGTH
		),
		VerticalSpeed = verticalSpeed,
		MaxDescendSpeed = clampPositiveNumber(abilityConfig.MaxDescendSpeed, DEFAULT_PHOENIX_MAX_DESCEND_SPEED),
		HorizontalResponsiveness = clampPositiveNumber(
			abilityConfig.HorizontalResponsiveness,
			DEFAULT_PHOENIX_HORIZONTAL_RESPONSIVENESS
		),
		TrailPartNames = copyStringArray(abilityConfig.FlightTrailPartNames),
		TrailOffset = typeof(abilityConfig.FlightTrailOffset) == "CFrame" and abilityConfig.FlightTrailOffset or nil,
	}, {
		CooldownDelay = startupDuration + heightDelay + duration,
	}
end

function ToriServer.PhoenixFlameShield(context)
	local abilityConfig = context.AbilityConfig
	local duration = clampPositiveNumber(abilityConfig.Duration, DEFAULT_PHOENIX_SHIELD_DURATION)

	return {
		Radius = resolvePhoenixShieldRadius(abilityConfig),
		Duration = duration,
		AnimationLockDuration = clampPositiveNumber(
			abilityConfig.AnimationLockDuration,
			DEFAULT_PHOENIX_SHIELD_ANIMATION_LOCK_DURATION
		),
	}, {
		CooldownDelay = duration,
	}
end

function ToriServer.ClearRuntimeState(player)
	local passiveService = getToriPassiveService()
	if not passiveService or typeof(passiveService.ClearRuntimeState) ~= "function" then
		return false
	end

	return passiveService.ClearRuntimeState(player)
end

function ToriServer.GetLegacyHandler()
	return ToriServer
end

return ToriServer
