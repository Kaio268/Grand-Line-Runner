local Tori = {}

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

function Tori.PhoenixFlight(context)
	local abilityConfig = context.AbilityConfig

	return {
		Duration = clampPositiveNumber(abilityConfig.Duration, 4.5),
		StartupDuration = clampNonNegativeNumber(abilityConfig.FlightStartupDuration, 0.85),
		TakeoffDuration = clampPositiveNumber(abilityConfig.TakeoffDuration, 0.4),
		InitialLift = clampPositiveNumber(abilityConfig.InitialLift, 22),
		MaxRiseHeight = clampPositiveNumber(abilityConfig.MaxRiseHeight, 56),
		FlightSpeed = clampPositiveNumber(abilityConfig.FlightSpeed, 80),
		FlightSpeedScaleReference = clampPositiveNumber(abilityConfig.FlightSpeedScaleReference, 17),
		FlightSpeedScaleStrength = clampNonNegativeNumber(abilityConfig.FlightSpeedScaleStrength, 0.5),
		VerticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, 90),
		MaxDescendSpeed = clampPositiveNumber(abilityConfig.MaxDescendSpeed, 72),
		HorizontalResponsiveness = clampPositiveNumber(abilityConfig.HorizontalResponsiveness, 14),
		TrailPartNames = copyStringArray(abilityConfig.FlightTrailPartNames),
		TrailOffset = typeof(abilityConfig.FlightTrailOffset) == "CFrame" and abilityConfig.FlightTrailOffset or nil,
	}
end

function Tori.PhoenixFlameShield(context)
	local abilityConfig = context.AbilityConfig

	return {
		Radius = clampPositiveNumber(abilityConfig.Radius, 13),
		Duration = clampPositiveNumber(abilityConfig.Duration, 2.75),
	}
end

return Tori
