local Workspace = game:GetService("Workspace")

local MeraDashShared = {}

local WALL_PADDING = 2
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_MIN_END_CARRY_SPEED = 52
local DEFAULT_END_CARRY_SPEED_FACTOR = 0.82

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getDirectionFromTarget(rootPart, dashTargetPosition)
	if typeof(dashTargetPosition) ~= "Vector3" then
		return nil
	end

	local delta = getPlanarVector(dashTargetPosition - rootPart.Position)
	if delta.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil
	end

	return delta.Unit
end

local function createCharacterRaycastParams(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true
	return params
end

function MeraDashShared.GetPlanarVector(vector)
	return getPlanarVector(vector)
end

function MeraDashShared.GetPlanarMagnitude(vector)
	return getPlanarVector(vector).Magnitude
end

function MeraDashShared.GetTravelDistance(startPosition, currentPosition, direction)
	local delta = getPlanarVector(currentPosition - startPosition)
	return math.max(delta:Dot(direction), 0)
end

function MeraDashShared.GetCurrentPlanarSpeed(humanoid, rootPart)
	return math.max(humanoid.WalkSpeed, MeraDashShared.GetPlanarMagnitude(rootPart.AssemblyLinearVelocity))
end

function MeraDashShared.ResolveDirection(humanoid, rootPart, dashTargetPosition)
	local hintedDirection = getDirectionFromTarget(rootPart, dashTargetPosition)
	if hintedDirection then
		return hintedDirection, "request_hint"
	end

	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return getPlanarVector(moveDirection).Unit, "move_direction"
	end

	local look = getPlanarVector(rootPart.CFrame.LookVector)
	if look.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return look.Unit, "look_vector"
	end

	return DEFAULT_DIRECTION, "fallback"
end

function MeraDashShared.GetMaxDashDistance(humanoid, rootPart, abilityConfig)
	local baseDashDistance = tonumber(abilityConfig.DashDistance) or 42
	local distanceSpeedBonusFactor = tonumber(abilityConfig.DistanceSpeedBonusFactor) or 0
	local maxDistanceSpeedBonus = tonumber(abilityConfig.MaxDistanceSpeedBonus) or 0
	local currentPlanarSpeed = MeraDashShared.GetCurrentPlanarSpeed(humanoid, rootPart)
	local bonusDistance = math.min(currentPlanarSpeed * distanceSpeedBonusFactor, maxDistanceSpeedBonus)

	return baseDashDistance + bonusDistance
end

function MeraDashShared.GetRequestedDistance(rootPart, maxDashDistance, dashTargetPosition)
	if typeof(dashTargetPosition) ~= "Vector3" then
		return maxDashDistance
	end

	local requestedDistance = getPlanarVector(dashTargetPosition - rootPart.Position).Magnitude
	if requestedDistance <= MIN_DIRECTION_MAGNITUDE then
		return maxDashDistance
	end

	return math.min(requestedDistance, maxDashDistance)
end

function MeraDashShared.GetDashSpeeds(humanoid, rootPart, abilityConfig, requiredBurstSpeed)
	local currentPlanarSpeed = MeraDashShared.GetCurrentPlanarSpeed(humanoid, rootPart)
	local baseDashSpeed = tonumber(abilityConfig.BaseDashSpeed) or 120
	local dashSpeedMultiplier = tonumber(abilityConfig.DashSpeedMultiplier) or 2.8
	local endDashSpeedMultiplier = tonumber(abilityConfig.EndDashSpeedMultiplier) or 1.1
	local requiredSpeedMultiplier = tonumber(abilityConfig.RequiredSpeedMultiplier) or 1
	local maxDashSpeed = tonumber(abilityConfig.MaxDashSpeed)

	local startDashSpeed = math.max(
		baseDashSpeed,
		currentPlanarSpeed * dashSpeedMultiplier,
		math.max(requiredBurstSpeed, 0) * requiredSpeedMultiplier
	)
	if maxDashSpeed then
		startDashSpeed = math.min(startDashSpeed, maxDashSpeed)
	end

	local endDashSpeed = math.max(
		humanoid.WalkSpeed,
		currentPlanarSpeed * endDashSpeedMultiplier,
		math.max(requiredBurstSpeed, 0) * 0.72
	)
	endDashSpeed = math.min(endDashSpeed, startDashSpeed)

	return {
		CurrentPlanarSpeed = currentPlanarSpeed,
		StartDashSpeed = startDashSpeed,
		EndDashSpeed = endDashSpeed,
	}
end

function MeraDashShared.GetInstantDashDistance(dashDistance, abilityConfig)
	local instantDashFraction = math.clamp(tonumber(abilityConfig.InstantDashFraction) or 0.25, 0, 1)
	local maxInstantDashDistance = tonumber(abilityConfig.MaxInstantDashDistance)
	local instantDistance = dashDistance * instantDashFraction
	if maxInstantDashDistance then
		instantDistance = math.min(instantDistance, math.max(maxInstantDashDistance, 0))
	end

	return math.max(instantDistance, 0)
end

function MeraDashShared.GetDashDistance(character, rootPart, direction, requestedDistance)
	local params = createCharacterRaycastParams(character)
	local result = Workspace:Raycast(rootPart.Position, direction * requestedDistance, params)
	if not result then
		return requestedDistance, false, nil
	end

	local distance = math.max(result.Distance - WALL_PADDING, 0)
	local clampedDistance = math.min(distance, requestedDistance)
	return clampedDistance, clampedDistance + 0.05 < requestedDistance, result
end

function MeraDashShared.GetLookAheadDistance(dashSpeed, dt)
	return math.max((dashSpeed * dt) + WALL_PADDING, WALL_PADDING + 1)
end

function MeraDashShared.ShouldStopForWall(character, rootPart, direction, lookAheadDistance)
	local params = createCharacterRaycastParams(character)
	local result = Workspace:Raycast(rootPart.Position, direction * lookAheadDistance, params)
	return result ~= nil
end

function MeraDashShared.GetDirectionDeltaDegrees(a, b)
	local planarA = getPlanarVector(a)
	local planarB = getPlanarVector(b)
	if planarA.Magnitude <= MIN_DIRECTION_MAGNITUDE or planarB.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return 0
	end

	local dot = math.clamp(planarA.Unit:Dot(planarB.Unit), -1, 1)
	return math.deg(math.acos(dot))
end

function MeraDashShared.Smoothstep(alpha)
	return alpha * alpha * (3 - (2 * alpha))
end

function MeraDashShared.BuildDashPlan(character, humanoid, rootPart, abilityConfig, dashTargetPosition)
	local direction, directionSource = MeraDashShared.ResolveDirection(humanoid, rootPart, dashTargetPosition)
	local maxDashDistance = MeraDashShared.GetMaxDashDistance(humanoid, rootPart, abilityConfig)
	local requestedDistance = MeraDashShared.GetRequestedDistance(rootPart, maxDashDistance, dashTargetPosition)
	local dashDistance, wallShortened, hitResult = MeraDashShared.GetDashDistance(character, rootPart, direction, requestedDistance)
	local dashDuration = tonumber(abilityConfig.DashDuration) or 0.18
	local instantDistance = MeraDashShared.GetInstantDashDistance(dashDistance, abilityConfig)
	local remainingDistance = math.max(dashDistance - instantDistance, 0)
	local requiredBurstSpeed = remainingDistance / math.max(dashDuration, 0.05)
	local speeds = MeraDashShared.GetDashSpeeds(humanoid, rootPart, abilityConfig, requiredBurstSpeed)
	local endCarrySpeedFactor = tonumber(abilityConfig.EndCarrySpeedFactor) or DEFAULT_END_CARRY_SPEED_FACTOR
	local minEndCarrySpeed = tonumber(abilityConfig.MinEndCarrySpeed) or DEFAULT_MIN_END_CARRY_SPEED
	local endCarrySpeed = math.max(
		humanoid.WalkSpeed,
		speeds.EndDashSpeed * endCarrySpeedFactor,
		minEndCarrySpeed
	)

	return {
		Direction = direction,
		DirectionSource = directionSource,
		MaxDistance = maxDashDistance,
		RequestedDistance = requestedDistance,
		Distance = dashDistance,
		WallShortened = wallShortened,
		HitResult = hitResult,
		Duration = dashDuration,
		CurrentPlanarSpeed = speeds.CurrentPlanarSpeed,
		StartDashSpeed = speeds.StartDashSpeed,
		EndDashSpeed = speeds.EndDashSpeed,
		EndCarrySpeed = endCarrySpeed,
		InstantDistance = instantDistance,
		RemainingDistance = remainingDistance,
		RequiredBurstSpeed = requiredBurstSpeed,
	}
end

return MeraDashShared
