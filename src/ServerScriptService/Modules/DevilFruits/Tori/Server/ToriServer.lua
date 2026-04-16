local ToriServer = {}

local function clampPositiveNumber(value, fallback)
	local numericValue = tonumber(value)
	if not numericValue or numericValue <= 0 then
		return fallback
	end

	return numericValue
end

function ToriServer.PhoenixFlight(context)
	local abilityConfig = context.AbilityConfig

	return {
		Duration = clampPositiveNumber(abilityConfig.Duration, 4.5),
		TakeoffDuration = clampPositiveNumber(abilityConfig.TakeoffDuration, 0.4),
		InitialLift = clampPositiveNumber(abilityConfig.InitialLift, 22),
		MaxRiseHeight = clampPositiveNumber(abilityConfig.MaxRiseHeight, 132),
		FlightSpeed = clampPositiveNumber(abilityConfig.FlightSpeed, 80),
		VerticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, 90),
		MaxDescendSpeed = clampPositiveNumber(abilityConfig.MaxDescendSpeed, 72),
		HorizontalResponsiveness = clampPositiveNumber(abilityConfig.HorizontalResponsiveness, 14),
	}
end

function ToriServer.PhoenixFlameShield(context)
	local abilityConfig = context.AbilityConfig

	return {
		Radius = clampPositiveNumber(abilityConfig.Radius, 13),
		Duration = clampPositiveNumber(abilityConfig.Duration, 2.75),
	}
end

function ToriServer.GetLegacyHandler()
	return ToriServer
end

return ToriServer
