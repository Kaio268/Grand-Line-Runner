local RubberLaunchMath = {}

local DEFAULT_BASE_DISTANCE = 0
local DEFAULT_SPEED_SCALE_REFERENCE = 70

function RubberLaunchMath.GetPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

function RubberLaunchMath.GetPlanarSpeed(rootPart)
	if not rootPart then
		return 0
	end

	return RubberLaunchMath.GetPlanarVector(rootPart.AssemblyLinearVelocity).Magnitude
end

function RubberLaunchMath.GetSpeedScaledLaunchDistance(abilityConfig, rootPart, options)
	local resolvedConfig = type(abilityConfig) == "table" and abilityConfig or {}
	local resolvedOptions = type(options) == "table" and options or {}
	local baseDistanceFallback = tonumber(resolvedOptions.BaseDistanceFallback) or DEFAULT_BASE_DISTANCE
	local speedScaleReferenceFallback =
		tonumber(resolvedOptions.SpeedScaleReferenceFallback) or DEFAULT_SPEED_SCALE_REFERENCE
	local baseDistance = math.max(0, tonumber(resolvedConfig.LaunchDistance) or baseDistanceFallback)
	local speedDistanceBonus = math.max(0, tonumber(resolvedConfig.SpeedLaunchDistanceBonus) or 0)
	if speedDistanceBonus <= 0 then
		return baseDistance
	end

	local referenceSpeed = math.max(1, tonumber(resolvedConfig.SpeedScaleReference) or speedScaleReferenceFallback)
	local speedAlpha = math.clamp(RubberLaunchMath.GetPlanarSpeed(rootPart) / referenceSpeed, 0, 1)
	return baseDistance + (speedDistanceBonus * speedAlpha)
end

return RubberLaunchMath
