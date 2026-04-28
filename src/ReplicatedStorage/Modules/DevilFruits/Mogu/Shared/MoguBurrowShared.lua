local Workspace = game:GetService("Workspace")

local MoguBurrowShared = {}

local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_BURROW_DURATION = 5
local DEFAULT_MOVE_SPEED = 24
local DEFAULT_GROUND_PROBE_HEIGHT = 6
local DEFAULT_GROUND_PROBE_DEPTH = 18
local DEFAULT_ROOT_GROUND_CLEARANCE = 3
local DEFAULT_TRAIL_INTERVAL = 0.16
local DEFAULT_CONCEAL_TRANSPARENCY = 1
local DEFAULT_ENTRY_BURST_RADIUS = 3.2
local DEFAULT_RESOLVE_BURST_RADIUS = 4.2
local DEFAULT_SURFACE_RESOLVE_GRACE = 0.45
local MIN_BURROW_DURATION = 0.5
local MIN_TRAIL_INTERVAL = 0.05
local MIN_BURST_RADIUS = 0.5
local MIN_PROBE_HEIGHT = 1
local MIN_PROBE_DEPTH = 4
local MIN_ROOT_GROUND_CLEARANCE = 1.5

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function createCharacterRaycastParams(character)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = character and { character } or {}
	params.IgnoreWater = false
	return params
end

function MoguBurrowShared.GetPlanarVector(vector)
	return getPlanarVector(vector)
end

function MoguBurrowShared.GetBurrowDuration(abilityConfig)
	return math.max(MIN_BURROW_DURATION, tonumber(abilityConfig and abilityConfig.BurrowDuration) or DEFAULT_BURROW_DURATION)
end

function MoguBurrowShared.GetMoveSpeed(abilityConfig)
	return math.max(0, tonumber(abilityConfig and abilityConfig.MoveSpeed) or DEFAULT_MOVE_SPEED)
end

function MoguBurrowShared.GetTrailInterval(abilityConfig)
	return math.max(MIN_TRAIL_INTERVAL, tonumber(abilityConfig and abilityConfig.TrailInterval) or DEFAULT_TRAIL_INTERVAL)
end

function MoguBurrowShared.GetConcealTransparency(abilityConfig)
	return math.clamp(
		tonumber(abilityConfig and abilityConfig.ConcealTransparency) or DEFAULT_CONCEAL_TRANSPARENCY,
		0,
		1
	)
end

function MoguBurrowShared.GetEntryBurstRadius(abilityConfig)
	return math.max(MIN_BURST_RADIUS, tonumber(abilityConfig and abilityConfig.EntryBurstRadius) or DEFAULT_ENTRY_BURST_RADIUS)
end

function MoguBurrowShared.GetResolveBurstRadius(abilityConfig)
	return math.max(MIN_BURST_RADIUS, tonumber(abilityConfig and abilityConfig.ResolveBurstRadius) or DEFAULT_RESOLVE_BURST_RADIUS)
end

function MoguBurrowShared.GetSurfaceResolveGrace(abilityConfig)
	return math.max(0, tonumber(abilityConfig and abilityConfig.SurfaceResolveGrace) or DEFAULT_SURFACE_RESOLVE_GRACE)
end

function MoguBurrowShared.ResolveDirection(humanoid, rootPart, requestPayload)
	local payloadDirection = type(requestPayload) == "table" and requestPayload.Direction or nil
	local planarPayloadDirection = typeof(payloadDirection) == "Vector3" and getPlanarVector(payloadDirection) or nil
	if planarPayloadDirection and planarPayloadDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarPayloadDirection.Unit, "request"
	end

	local moveDirection = humanoid and humanoid.MoveDirection or nil
	local planarMoveDirection = typeof(moveDirection) == "Vector3" and getPlanarVector(moveDirection) or nil
	if planarMoveDirection and planarMoveDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarMoveDirection.Unit, "move_direction"
	end

	local lookDirection = rootPart and getPlanarVector(rootPart.CFrame.LookVector) or nil
	if lookDirection and lookDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return lookDirection.Unit, "look_vector"
	end

	return DEFAULT_DIRECTION, "fallback"
end

function MoguBurrowShared.GetRootGroundClearance(character, rootPart, abilityConfig)
	local probeHeight = math.max(MIN_PROBE_HEIGHT, tonumber(abilityConfig and abilityConfig.GroundProbeHeight) or DEFAULT_GROUND_PROBE_HEIGHT)
	local probeDepth = math.max(MIN_PROBE_DEPTH, tonumber(abilityConfig and abilityConfig.GroundProbeDepth) or DEFAULT_GROUND_PROBE_DEPTH)
	local origin = rootPart.Position + Vector3.new(0, probeHeight, 0)
	local cast = Vector3.new(0, -(probeHeight + probeDepth), 0)
	local result = Workspace:Raycast(origin, cast, createCharacterRaycastParams(character))
	if result then
		return math.max(rootPart.Position.Y - result.Position.Y, MIN_ROOT_GROUND_CLEARANCE), result
	end

	return math.max(
		MIN_ROOT_GROUND_CLEARANCE,
		tonumber(abilityConfig and abilityConfig.RootGroundClearance) or DEFAULT_ROOT_GROUND_CLEARANCE
	), nil
end

function MoguBurrowShared.ResolveSurfaceRootPosition(character, rootPart, planarRootPosition, abilityConfig)
	local rootGroundClearance = MoguBurrowShared.GetRootGroundClearance(character, rootPart, abilityConfig)
	local probeHeight = math.max(MIN_PROBE_HEIGHT, tonumber(abilityConfig and abilityConfig.GroundProbeHeight) or DEFAULT_GROUND_PROBE_HEIGHT)
	local probeDepth = math.max(MIN_PROBE_DEPTH, tonumber(abilityConfig and abilityConfig.GroundProbeDepth) or DEFAULT_GROUND_PROBE_DEPTH)
	local origin = Vector3.new(planarRootPosition.X, rootPart.Position.Y + probeHeight, planarRootPosition.Z)
	local cast = Vector3.new(0, -(probeHeight + probeDepth), 0)
	local result = Workspace:Raycast(origin, cast, createCharacterRaycastParams(character))
	if result then
		return Vector3.new(planarRootPosition.X, result.Position.Y + rootGroundClearance, planarRootPosition.Z), true, result
	end

	return Vector3.new(planarRootPosition.X, rootPart.Position.Y, planarRootPosition.Z), false, nil
end

return MoguBurrowShared
