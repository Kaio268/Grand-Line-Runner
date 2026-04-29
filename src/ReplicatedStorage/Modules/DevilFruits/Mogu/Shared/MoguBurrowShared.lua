local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))

local MoguBurrowShared = {}

local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_BURROW_DURATION = 5
local DEFAULT_MOVE_SPEED = 24
local DEFAULT_GROUND_PROBE_HEIGHT = 6
local DEFAULT_GROUND_PROBE_DEPTH = 18
local DEFAULT_ROOT_GROUND_CLEARANCE = 3
local DEFAULT_MAX_SURFACE_DROP = 1.25
local DEFAULT_MAX_SURFACE_RISE = 3.5
local DEFAULT_MIN_SURFACE_NORMAL_Y = 0.55
local DEFAULT_SURFACE_PROBE_RADIUS = 1.6
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
local HAZARD_RAYCAST_IGNORE_CACHE_SECONDS = 0.25

local SURFACE_SAMPLE_DIRECTIONS = {
	Vector3.new(0, 0, 0),
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	Vector3.new(0.707, 0, 0.707),
	Vector3.new(0.707, 0, -0.707),
	Vector3.new(-0.707, 0, 0.707),
	Vector3.new(-0.707, 0, -0.707),
}

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function appendRaycastIgnore(ignoreList, instance)
	if typeof(instance) ~= "Instance" then
		return
	end

	ignoreList[#ignoreList + 1] = instance
end

local cachedHazardRaycastIgnores = nil
local cachedHazardRaycastIgnoresAt = 0

local function getHazardRaycastIgnores()
	local now = os.clock()
	if cachedHazardRaycastIgnores and now - cachedHazardRaycastIgnoresAt <= HAZARD_RAYCAST_IGNORE_CACHE_SECONDS then
		return cachedHazardRaycastIgnores
	end

	local refs = MapResolver.GetRefs()
	local waveFolder = refs and refs.WaveFolder
	local sharedHazardsFolder = waveFolder and waveFolder:FindFirstChild("Hazards")
	local ignoreList = {}

	appendRaycastIgnore(ignoreList, sharedHazardsFolder)
	appendRaycastIgnore(ignoreList, refs and refs.ClientWaves)
	cachedHazardRaycastIgnores = ignoreList
	cachedHazardRaycastIgnoresAt = now

	return ignoreList
end

local function appendHazardRaycastIgnores(ignoreList)
	for _, instance in ipairs(getHazardRaycastIgnores()) do
		appendRaycastIgnore(ignoreList, instance)
	end
end

local function createSurfaceRaycastParams(character, abilityConfig)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList = {}
	appendRaycastIgnore(ignoreList, character)
	if not (abilityConfig and abilityConfig.IgnoreHazardsInSurfaceRaycasts == false) then
		appendHazardRaycastIgnores(ignoreList)
	end
	params.FilterDescendantsInstances = ignoreList
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

function MoguBurrowShared.GetMaxSurfaceDrop(abilityConfig)
	return math.max(0, tonumber(abilityConfig and abilityConfig.MaxSurfaceDrop) or DEFAULT_MAX_SURFACE_DROP)
end

function MoguBurrowShared.GetMaxSurfaceRise(abilityConfig)
	return math.max(0, tonumber(abilityConfig and abilityConfig.MaxSurfaceRise) or DEFAULT_MAX_SURFACE_RISE)
end

function MoguBurrowShared.GetMinSurfaceNormalY(abilityConfig)
	return math.clamp(
		tonumber(abilityConfig and abilityConfig.MinSurfaceNormalY) or DEFAULT_MIN_SURFACE_NORMAL_Y,
		0,
		1
	)
end

function MoguBurrowShared.GetSurfaceProbeRadius(rootPart, abilityConfig)
	local configuredRadius = tonumber(abilityConfig and abilityConfig.SurfaceProbeRadius)
	if configuredRadius then
		return math.max(0, configuredRadius)
	end

	if rootPart then
		return math.max(DEFAULT_SURFACE_PROBE_RADIUS, math.max(rootPart.Size.X, rootPart.Size.Z) * 0.45)
	end

	return DEFAULT_SURFACE_PROBE_RADIUS
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
	local configuredClearance = math.max(
		MIN_ROOT_GROUND_CLEARANCE,
		tonumber(abilityConfig and abilityConfig.RootGroundClearance) or DEFAULT_ROOT_GROUND_CLEARANCE
	)
	if not rootPart then
		return configuredClearance, nil
	end

	if abilityConfig and abilityConfig.UseConfiguredRootGroundClearance == true then
		return configuredClearance, nil
	end

	local probeHeight = math.max(MIN_PROBE_HEIGHT, tonumber(abilityConfig and abilityConfig.GroundProbeHeight) or DEFAULT_GROUND_PROBE_HEIGHT)
	local probeDepth = math.max(MIN_PROBE_DEPTH, tonumber(abilityConfig and abilityConfig.GroundProbeDepth) or DEFAULT_GROUND_PROBE_DEPTH)
	local origin = rootPart.Position + Vector3.new(0, probeHeight, 0)
	local cast = Vector3.new(0, -(probeHeight + probeDepth), 0)
	local result = Workspace:Raycast(origin, cast, createSurfaceRaycastParams(character, abilityConfig))
	if result then
		return math.max(rootPart.Position.Y - result.Position.Y, MIN_ROOT_GROUND_CLEARANCE), result
	end

	return configuredClearance, nil
end

local function isSurfaceNormalValid(result, abilityConfig)
	return result and result.Normal.Y >= MoguBurrowShared.GetMinSurfaceNormalY(abilityConfig)
end

local function isResolvedRootHeightSafe(resolvedRootY, guardRootY, abilityConfig)
	if typeof(guardRootY) ~= "number" then
		return true
	end

	return resolvedRootY >= guardRootY - MoguBurrowShared.GetMaxSurfaceDrop(abilityConfig)
		and resolvedRootY <= guardRootY + MoguBurrowShared.GetMaxSurfaceRise(abilityConfig)
end

function MoguBurrowShared.ResolveSurfaceRootPosition(character, rootPart, planarRootPosition, abilityConfig, lastSafeSurfaceRootPosition)
	local rootGroundClearance = MoguBurrowShared.GetRootGroundClearance(character, rootPart, abilityConfig)
	local probeHeight = math.max(MIN_PROBE_HEIGHT, tonumber(abilityConfig and abilityConfig.GroundProbeHeight) or DEFAULT_GROUND_PROBE_HEIGHT)
	local probeDepth = math.max(MIN_PROBE_DEPTH, tonumber(abilityConfig and abilityConfig.GroundProbeDepth) or DEFAULT_GROUND_PROBE_DEPTH)
	local requestedPosition = typeof(planarRootPosition) == "Vector3" and planarRootPosition or nil
	local fallbackPosition = typeof(lastSafeSurfaceRootPosition) == "Vector3" and lastSafeSurfaceRootPosition or nil
	if not requestedPosition then
		requestedPosition = fallbackPosition or (rootPart and rootPart.Position)
	end

	if not requestedPosition then
		return nil, false, nil
	end

	local castBaseY = requestedPosition.Y
	if rootPart then
		castBaseY = math.max(castBaseY, rootPart.Position.Y)
	end
	if fallbackPosition then
		castBaseY = math.max(castBaseY, fallbackPosition.Y)
	end

	local raycastParams = createSurfaceRaycastParams(character, abilityConfig)
	local cast = Vector3.new(0, -(probeHeight + probeDepth), 0)
	local guardRootY = fallbackPosition and fallbackPosition.Y or (rootPart and rootPart.Position.Y)
	local sampleRadius = MoguBurrowShared.GetSurfaceProbeRadius(rootPart, abilityConfig)
	local bestResult = nil
	local bestResolvedRootY = nil

	for _, sampleDirection in ipairs(SURFACE_SAMPLE_DIRECTIONS) do
		local sampleOffset = sampleDirection * sampleRadius
		local origin = Vector3.new(
			requestedPosition.X + sampleOffset.X,
			castBaseY + probeHeight,
			requestedPosition.Z + sampleOffset.Z
		)
		local result = Workspace:Raycast(origin, cast, raycastParams)
		if isSurfaceNormalValid(result, abilityConfig) then
			local resolvedRootY = result.Position.Y + rootGroundClearance
			if isResolvedRootHeightSafe(resolvedRootY, guardRootY, abilityConfig)
				and (bestResolvedRootY == nil or resolvedRootY > bestResolvedRootY)
			then
				bestResult = result
				bestResolvedRootY = resolvedRootY
			end
		end
	end

	if bestResult and bestResolvedRootY then
		return Vector3.new(requestedPosition.X, bestResolvedRootY, requestedPosition.Z), true, bestResult
	end

	return fallbackPosition, false, nil
end

return MoguBurrowShared
