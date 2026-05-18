local CollectionService = game:GetService("CollectionService")
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
local DEFAULT_ACTIVATION_GROUND_PROBE_DEPTH = 48
local DEFAULT_ACTIVATION_MAX_SURFACE_DROP = 48
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
local FAST_SAMPLE_MAX_HEIGHT_DELTA = 0.45
local DEFAULT_ACTIVE_MAX_UNTRUSTED_SURFACE_RISE = 0.65
local DEFAULT_WALL_PROBE_RADIUS = 1.35
local DEFAULT_WALL_BLOCKER_SKIN = 0.35
local MAX_SURFACE_RAYCAST_ATTEMPTS = 8
local MAX_MOVEMENT_BLOCKER_RAYCAST_ATTEMPTS = 8
local SURFACE_RECAST_EPSILON = 0.05
local FORCE_GROUND_TAG = "MoguBurrowGround"
local FORCE_IGNORE_TAG = "MoguBurrowIgnoreSurface"
local FORCE_GROUND_ATTRIBUTE = "MoguBurrowGround"
local FORCE_IGNORE_ATTRIBUTE = "MoguBurrowIgnoreSurface"
local FORCE_PASS_THROUGH_TAG = "MoguBurrowPassThrough"
local FORCE_BLOCKER_TAG = "MoguBurrowBlocker"
local FORCE_PASS_THROUGH_ATTRIBUTE = "MoguBurrowPassThrough"
local FORCE_BLOCKER_ATTRIBUTE = "MoguBurrowBlocker"

local TRUSTED_SURFACE_NAME_PATTERNS = {
	"floor",
	"ground",
	"terrain",
	"baseplate",
	"path",
	"road",
	"corridor",
	"lane",
	"track",
	"bridge",
}

local IGNORED_SURFACE_NAME_PATTERNS = {
	"rail",
	"fence",
	"prop",
	"reward",
	"chest",
	"crew",
	"hazard",
	"wave",
	"effect",
	"vfx",
	"indicator",
	"billboard",
	"prompt",
	"barrier",
	"door",
	"sign",
	"post",
	"pillar",
	"wall",
	"decor",
	"decoration",
}

local PASS_THROUGH_BLOCKER_NAME_PATTERNS = {
	"hazard",
	"wave",
	"effect",
	"vfx",
	"indicator",
	"billboard",
	"prompt",
	"reward",
	"pickup",
	"chest",
	"crew",
	"coin",
	"orb",
	"trail",
	"particle",
}

local HARD_BLOCKER_NAME_PATTERNS = {
	"wall",
	"barrier",
	"boundary",
	"fence",
	"rail",
	"gate",
	"door",
	"blocker",
	"collision",
	"collider",
	"prop",
	"post",
	"pillar",
	"rock",
	"crate",
	"box",
}

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

local MOVEMENT_BLOCKER_HEIGHT_OFFSETS = {
	0,
	-1.25,
	1.25,
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

local function matchesAnyNamePattern(instance, patterns)
	if typeof(instance) ~= "Instance" or type(patterns) ~= "table" then
		return false
	end

	local current = instance
	while current do
		local lowerName = string.lower(current.Name)
		for _, pattern in ipairs(patterns) do
			if string.find(lowerName, pattern, 1, true) then
				return true
			end
		end
		current = current.Parent
	end

	return false
end

local function hasTagOrAttribute(instance, tagName, attributeName)
	local current = instance
	while current do
		if CollectionService:HasTag(current, tagName) or current:GetAttribute(attributeName) == true then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isInCharacterModel(instance)
	local current = instance
	while current do
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isWithin(instance, ancestor)
	return typeof(instance) == "Instance" and typeof(ancestor) == "Instance" and instance:IsDescendantOf(ancestor)
end

local function hasHazardMetadata(instance)
	local current = instance
	while current do
		if current:GetAttribute("HazardClass") ~= nil or current:GetAttribute("HazardType") ~= nil then
			return true
		end
		if current.Name == "Hazards" or current.Name == "ClientWaves" then
			return true
		end
		current = current.Parent
	end

	return false
end

local function isHazardLike(instance, refs)
	local waveFolder = refs and refs.WaveFolder
	local sharedHazardsFolder = waveFolder and waveFolder:FindFirstChild("Hazards")
	return isWithin(instance, refs and refs.ClientWaves)
		or isWithin(instance, sharedHazardsFolder)
		or hasHazardMetadata(instance)
end

local cachedHazardRaycastIgnores = nil
local cachedHazardRaycastIgnoresAt = 0
local cachedHazardRaycastIgnoresVersion = 0
local surfaceRaycastParamsByCharacter = setmetatable({}, { __mode = "k" })
local nilCharacterSurfaceRaycastParams = nil
local diagnostics = {
	RaycastCount = 0,
	SurfaceProbeCount = 0,
	SurfaceProbeTimeMs = 0,
	RejectedSurfaceHitCount = 0,
	PassThroughMovementHitCount = 0,
	BlockedMovementCount = 0,
}

local isSurfaceNormalValid

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
	cachedHazardRaycastIgnoresVersion += 1

	return ignoreList
end

local function appendHazardRaycastIgnores(ignoreList)
	for _, instance in ipairs(getHazardRaycastIgnores()) do
		appendRaycastIgnore(ignoreList, instance)
	end
end

local function getSurfaceRaycastParamsCache(character)
	if typeof(character) == "Instance" then
		local cache = surfaceRaycastParamsByCharacter[character]
		if not cache then
			cache = {
				Params = RaycastParams.new(),
			}
			surfaceRaycastParamsByCharacter[character] = cache
		end
		return cache
	end

	if not nilCharacterSurfaceRaycastParams then
		nilCharacterSurfaceRaycastParams = {
			Params = RaycastParams.new(),
		}
	end

	return nilCharacterSurfaceRaycastParams
end

local function createSurfaceRaycastParams(character, abilityConfig)
	local shouldIgnoreHazards = not (abilityConfig and abilityConfig.IgnoreHazardsInSurfaceRaycasts == false)
	local hazardVersion = cachedHazardRaycastIgnoresVersion
	if shouldIgnoreHazards then
		getHazardRaycastIgnores()
		hazardVersion = cachedHazardRaycastIgnoresVersion
	end
	local cache = getSurfaceRaycastParamsCache(character)
	local params = cache.Params
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false

	if cache.Character ~= character
		or cache.ShouldIgnoreHazards ~= shouldIgnoreHazards
		or cache.HazardVersion ~= hazardVersion
	then
		local ignoreList = {}
		appendRaycastIgnore(ignoreList, character)
		if shouldIgnoreHazards then
			appendHazardRaycastIgnores(ignoreList)
		end
		params.FilterDescendantsInstances = ignoreList
		cache.IgnoreList = ignoreList
		cache.Character = character
		cache.ShouldIgnoreHazards = shouldIgnoreHazards
		cache.HazardVersion = hazardVersion
	end

	return params, cache.IgnoreList or {}
end

local function buildSurfaceRaycastParams(baseIgnoreList, extraIgnoreList)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = false

	local ignoreList = {}
	if type(baseIgnoreList) == "table" then
		for _, instance in ipairs(baseIgnoreList) do
			appendRaycastIgnore(ignoreList, instance)
		end
	end
	if type(extraIgnoreList) == "table" then
		for _, instance in ipairs(extraIgnoreList) do
			appendRaycastIgnore(ignoreList, instance)
		end
	end
	params.FilterDescendantsInstances = ignoreList
	return params
end

local function surfaceRaycast(origin, direction, raycastParams)
	diagnostics.RaycastCount += 1
	return Workspace:Raycast(origin, direction, raycastParams)
end

local function classifySurfaceResult(result, refs)
	local instance = result and result.Instance
	if not instance then
		return {
			Valid = false,
			Trusted = false,
			Reason = "no_result",
		}
	end

	if hasTagOrAttribute(instance, FORCE_IGNORE_TAG, FORCE_IGNORE_ATTRIBUTE) then
		return {
			Valid = false,
			Trusted = false,
			Reason = "force_ignore",
		}
	end

	if hasTagOrAttribute(instance, FORCE_GROUND_TAG, FORCE_GROUND_ATTRIBUTE) then
		return {
			Valid = true,
			Trusted = true,
			Reason = "force_ground",
		}
	end

	if instance == Workspace.Terrain then
		return {
			Valid = true,
			Trusted = true,
			Reason = "terrain",
		}
	end

	if isInCharacterModel(instance) then
		return {
			Valid = false,
			Trusted = false,
			Reason = "character",
		}
	end

	if isHazardLike(instance, refs) then
		return {
			Valid = false,
			Trusted = false,
			Reason = "wave_or_hazard",
		}
	end

	if matchesAnyNamePattern(instance, IGNORED_SURFACE_NAME_PATTERNS) then
		return {
			Valid = false,
			Trusted = false,
			Reason = "ignored_name",
		}
	end

	if matchesAnyNamePattern(instance, TRUSTED_SURFACE_NAME_PATTERNS) then
		return {
			Valid = true,
			Trusted = true,
			Reason = "trusted_name",
		}
	end

	return {
		Valid = true,
		Trusted = false,
		Reason = "untrusted_map_part",
	}
end

local function classifyMovementBlockerResult(result, refs, abilityConfig)
	local instance = result and result.Instance
	if not instance then
		return {
			Blocks = false,
			Reason = "no_result",
		}
	end

	if hasTagOrAttribute(instance, FORCE_PASS_THROUGH_TAG, FORCE_PASS_THROUGH_ATTRIBUTE) then
		return {
			Blocks = false,
			Reason = "force_pass_through",
		}
	end

	if hasTagOrAttribute(instance, FORCE_BLOCKER_TAG, FORCE_BLOCKER_ATTRIBUTE) then
		return {
			Blocks = true,
			Reason = "force_blocker",
		}
	end

	if isInCharacterModel(instance) then
		return {
			Blocks = false,
			Reason = "character",
		}
	end

	if isHazardLike(instance, refs) then
		return {
			Blocks = false,
			Reason = "hazard_pass_through",
		}
	end

	if matchesAnyNamePattern(instance, PASS_THROUGH_BLOCKER_NAME_PATTERNS) then
		return {
			Blocks = false,
			Reason = "pass_through_name",
		}
	end

	if isSurfaceNormalValid(result, abilityConfig) then
		return {
			Blocks = false,
			Reason = "floor_or_slope_normal",
		}
	end

	if matchesAnyNamePattern(instance, HARD_BLOCKER_NAME_PATTERNS) then
		return {
			Blocks = true,
			Reason = "hard_blocker_name",
		}
	end

	if instance:IsA("BasePart") and instance.CanCollide == false then
		return {
			Blocks = false,
			Reason = "non_collidable",
		}
	end

	return {
		Blocks = true,
		Reason = "solid_geometry",
	}
end

local function surfaceRaycastFirstUsable(origin, direction, baseIgnoreList, abilityConfig, refs)
	local extraIgnoreList = {}
	local remainingDirection = direction
	local currentOrigin = origin
	local skipped = nil

	for _ = 1, MAX_SURFACE_RAYCAST_ATTEMPTS do
		if remainingDirection.Magnitude <= SURFACE_RECAST_EPSILON then
			break
		end

		local params = buildSurfaceRaycastParams(baseIgnoreList, extraIgnoreList)
		local result = surfaceRaycast(currentOrigin, remainingDirection, params)
		if not result then
			return nil, skipped
		end

		local classification = classifySurfaceResult(result, refs)
		if isSurfaceNormalValid(result, abilityConfig) and classification.Valid then
			classification.Instance = result.Instance
			return result, classification
		end

		diagnostics.RejectedSurfaceHitCount += 1
		skipped = classification
		appendRaycastIgnore(extraIgnoreList, result.Instance)
	end

	return nil, skipped
end

local function movementRaycastFirstBlocker(origin, direction, baseIgnoreList, abilityConfig, refs)
	local extraIgnoreList = {}
	local skipped = nil

	for _ = 1, MAX_MOVEMENT_BLOCKER_RAYCAST_ATTEMPTS do
		if direction.Magnitude <= SURFACE_RECAST_EPSILON then
			break
		end

		local params = buildSurfaceRaycastParams(baseIgnoreList, extraIgnoreList)
		local result = surfaceRaycast(origin, direction, params)
		if not result then
			return nil, skipped
		end

		local classification = classifyMovementBlockerResult(result, refs, abilityConfig)
		if classification.Blocks == true then
			classification.Instance = result.Instance
			return result, classification
		end

		diagnostics.PassThroughMovementHitCount += 1
		skipped = classification
		appendRaycastIgnore(extraIgnoreList, result.Instance)
	end

	return nil, skipped
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

function MoguBurrowShared.GetActivationGroundProbeDepth(abilityConfig)
	return math.max(
		MIN_PROBE_DEPTH,
		tonumber(abilityConfig and abilityConfig.ActivationGroundProbeDepth) or DEFAULT_ACTIVATION_GROUND_PROBE_DEPTH
	)
end

function MoguBurrowShared.GetActivationMaxSurfaceDrop(abilityConfig)
	return math.max(
		0,
		tonumber(abilityConfig and abilityConfig.ActivationMaxSurfaceDrop) or DEFAULT_ACTIVATION_MAX_SURFACE_DROP
	)
end

function MoguBurrowShared.GetMaxSurfaceDrop(abilityConfig)
	return math.max(0, tonumber(abilityConfig and abilityConfig.MaxSurfaceDrop) or DEFAULT_MAX_SURFACE_DROP)
end

function MoguBurrowShared.GetMaxSurfaceRise(abilityConfig)
	return math.max(0, tonumber(abilityConfig and abilityConfig.MaxSurfaceRise) or DEFAULT_MAX_SURFACE_RISE)
end

function MoguBurrowShared.GetActiveMaxUntrustedSurfaceRise(abilityConfig)
	return math.max(
		0,
		tonumber(abilityConfig and abilityConfig.ActiveMaxUntrustedSurfaceRise)
			or DEFAULT_ACTIVE_MAX_UNTRUSTED_SURFACE_RISE
	)
end

function MoguBurrowShared.GetWallProbeRadius(rootPart, abilityConfig)
	local configuredRadius = tonumber(abilityConfig and abilityConfig.WallProbeRadius)
	if configuredRadius then
		return math.max(0, configuredRadius)
	end

	if rootPart then
		return math.max(DEFAULT_WALL_PROBE_RADIUS, math.max(rootPart.Size.X, rootPart.Size.Z) * 0.55)
	end

	return DEFAULT_WALL_PROBE_RADIUS
end

function MoguBurrowShared.GetWallBlockerSkin(abilityConfig)
	return math.max(0, tonumber(abilityConfig and abilityConfig.WallBlockerSkin) or DEFAULT_WALL_BLOCKER_SKIN)
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
	local result = surfaceRaycast(origin, cast, createSurfaceRaycastParams(character, abilityConfig))
	if result then
		return math.max(rootPart.Position.Y - result.Position.Y, MIN_ROOT_GROUND_CLEARANCE), result
	end

	return configuredClearance, nil
end

isSurfaceNormalValid = function(result, abilityConfig)
	return result and result.Normal.Y >= MoguBurrowShared.GetMinSurfaceNormalY(abilityConfig)
end

local function isResolvedRootHeightSafe(resolvedRootY, guardRootY, abilityConfig, options)
	if typeof(guardRootY) ~= "number" then
		return true
	end

	local maxDrop = MoguBurrowShared.GetMaxSurfaceDrop(abilityConfig)
	if type(options) == "table" and options.AllowActivationDrop == true then
		maxDrop = math.max(maxDrop, MoguBurrowShared.GetActivationMaxSurfaceDrop(abilityConfig))
	end

	return resolvedRootY >= guardRootY - maxDrop
		and resolvedRootY <= guardRootY + MoguBurrowShared.GetMaxSurfaceRise(abilityConfig)
end

local function isFastSampleAcceptable(resolvedRootY, guardRootY)
	return typeof(guardRootY) ~= "number" or math.abs(resolvedRootY - guardRootY) <= FAST_SAMPLE_MAX_HEIGHT_DELTA
end

function MoguBurrowShared.ResolvePlanarMovement(
	character,
	rootPart,
	currentSurfaceRootPosition,
	targetSurfaceRootPosition,
	abilityConfig
)
	if typeof(currentSurfaceRootPosition) ~= "Vector3" or typeof(targetSurfaceRootPosition) ~= "Vector3" then
		return targetSurfaceRootPosition, false, nil, nil
	end

	local planarDelta = getPlanarVector(targetSurfaceRootPosition - currentSurfaceRootPosition)
	local planarDistance = planarDelta.Magnitude
	if planarDistance <= SURFACE_RECAST_EPSILON then
		return targetSurfaceRootPosition, false, nil, nil
	end

	local direction = planarDelta.Unit
	local perpendicular = Vector3.new(-direction.Z, 0, direction.X)
	local wallProbeRadius = MoguBurrowShared.GetWallProbeRadius(rootPart, abilityConfig)
	local _, baseIgnoreList = createSurfaceRaycastParams(character, abilityConfig)
	local refs = MapResolver.GetRefs()
	local closestResult = nil
	local closestClassification = nil
	local closestDistance = nil
	local cast = direction * planarDistance

	for _, heightOffset in ipairs(MOVEMENT_BLOCKER_HEIGHT_OFFSETS) do
		local origin = currentSurfaceRootPosition + Vector3.new(0, heightOffset, 0)
		local result, classification = movementRaycastFirstBlocker(origin, cast, baseIgnoreList, abilityConfig, refs)
		if result and (not closestDistance or result.Distance < closestDistance) then
			closestResult = result
			closestClassification = classification
			closestDistance = result.Distance
		end
	end

	if wallProbeRadius > 0 then
		for _, side in ipairs({ -1, 1 }) do
			local origin = currentSurfaceRootPosition + (perpendicular * wallProbeRadius * side)
			local result, classification = movementRaycastFirstBlocker(origin, cast, baseIgnoreList, abilityConfig, refs)
			if result and (not closestDistance or result.Distance < closestDistance) then
				closestResult = result
				closestClassification = classification
				closestDistance = result.Distance
			end
		end
	end

	if not closestResult or not closestDistance then
		return targetSurfaceRootPosition, false, nil, nil
	end

	local acceptedDistance = math.max(0, closestDistance - MoguBurrowShared.GetWallBlockerSkin(abilityConfig))
	local acceptedPosition = currentSurfaceRootPosition + direction * math.min(planarDistance, acceptedDistance)
	diagnostics.BlockedMovementCount += 1

	if closestClassification then
		closestClassification.Distance = closestDistance
		closestClassification.AcceptedDistance = acceptedDistance
	end

	return acceptedPosition, true, closestResult, closestClassification
end

function MoguBurrowShared.ResolveSurfaceRootPosition(
	character,
	rootPart,
	planarRootPosition,
	abilityConfig,
	lastSafeSurfaceRootPosition,
	options
)
	local probeStartedAt = os.clock()
	diagnostics.SurfaceProbeCount += 1

	local rootGroundClearance = MoguBurrowShared.GetRootGroundClearance(character, rootPart, abilityConfig)
	local allowActivationDrop = type(options) == "table" and options.AllowActivationDrop == true
	local probeHeight = math.max(MIN_PROBE_HEIGHT, tonumber(abilityConfig and abilityConfig.GroundProbeHeight) or DEFAULT_GROUND_PROBE_HEIGHT)
	local probeDepth = math.max(MIN_PROBE_DEPTH, tonumber(abilityConfig and abilityConfig.GroundProbeDepth) or DEFAULT_GROUND_PROBE_DEPTH)
	if allowActivationDrop then
		probeDepth = math.max(probeDepth, MoguBurrowShared.GetActivationGroundProbeDepth(abilityConfig))
	end
	local requestedPosition = typeof(planarRootPosition) == "Vector3" and planarRootPosition or nil
	local fallbackPosition = typeof(lastSafeSurfaceRootPosition) == "Vector3" and lastSafeSurfaceRootPosition or nil
	if not requestedPosition then
		requestedPosition = fallbackPosition or (rootPart and rootPart.Position)
	end

	if not requestedPosition then
		diagnostics.SurfaceProbeTimeMs += (os.clock() - probeStartedAt) * 1000
		return nil, false, nil
	end

	local castBaseY = requestedPosition.Y
	if rootPart then
		castBaseY = math.max(castBaseY, rootPart.Position.Y)
	end
	local ignoreFallbackHeightForCast = type(options) == "table" and options.IgnoreFallbackHeightForCast == true
	if fallbackPosition and not ignoreFallbackHeightForCast then
		castBaseY = math.max(castBaseY, fallbackPosition.Y)
	end

	local _, baseIgnoreList = createSurfaceRaycastParams(character, abilityConfig)
	local cast = Vector3.new(0, -(probeHeight + probeDepth), 0)
	local explicitGuardRootY = type(options) == "table" and tonumber(options.GuardRootY) or nil
	local guardRootY = if explicitGuardRootY and explicitGuardRootY == explicitGuardRootY
		then explicitGuardRootY
		else fallbackPosition and fallbackPosition.Y or (rootPart and rootPart.Position.Y)
	local sampleRadius = MoguBurrowShared.GetSurfaceProbeRadius(rootPart, abilityConfig)
	local bestResult = nil
	local bestResolvedRootY = nil
	local bestClassification = nil
	local bestScore = nil
	local fastSample = type(options) == "table" and options.FastSample == true
	local activeSurface = type(options) == "table" and options.ActiveBurrowSurface == true
	local activeMaxUntrustedSurfaceRise = MoguBurrowShared.GetActiveMaxUntrustedSurfaceRise(abilityConfig)
	local refs = MapResolver.GetRefs()

	for index, sampleDirection in ipairs(SURFACE_SAMPLE_DIRECTIONS) do
		local sampleOffset = sampleDirection * sampleRadius
		local origin = Vector3.new(
			requestedPosition.X + sampleOffset.X,
			castBaseY + probeHeight,
			requestedPosition.Z + sampleOffset.Z
		)
		local result, classification = surfaceRaycastFirstUsable(origin, cast, baseIgnoreList, abilityConfig, refs)
		if isSurfaceNormalValid(result, abilityConfig) then
			local resolvedRootY = result.Position.Y + rootGroundClearance
			local heightDelta = if typeof(guardRootY) == "number" then resolvedRootY - guardRootY else 0
			local suspiciousActiveRise = activeSurface
				and classification
				and classification.Trusted ~= true
				and heightDelta > activeMaxUntrustedSurfaceRise
			if isResolvedRootHeightSafe(resolvedRootY, guardRootY, abilityConfig, options) and not suspiciousActiveRise then
				local candidateScore = if activeSurface and typeof(guardRootY) == "number"
					then math.abs(heightDelta)
					else -resolvedRootY
				local shouldUseCandidate = bestResult == nil
				if not shouldUseCandidate and classification and bestClassification then
					shouldUseCandidate = classification.Trusted == true and bestClassification.Trusted ~= true
				end
				if not shouldUseCandidate and candidateScore ~= nil and bestScore ~= nil then
					shouldUseCandidate = candidateScore < bestScore
				end
				if shouldUseCandidate then
					bestResult = result
					bestResolvedRootY = resolvedRootY
					bestClassification = classification
					bestScore = candidateScore
				end
			elseif suspiciousActiveRise then
				diagnostics.RejectedSurfaceHitCount += 1
			end

			if index == 1
				and fastSample
				and not suspiciousActiveRise
				and isFastSampleAcceptable(resolvedRootY, guardRootY)
			then
				diagnostics.SurfaceProbeTimeMs += (os.clock() - probeStartedAt) * 1000
				return Vector3.new(requestedPosition.X, resolvedRootY, requestedPosition.Z), true, result, classification
			end
		end
	end

	if bestResult and bestResolvedRootY then
		diagnostics.SurfaceProbeTimeMs += (os.clock() - probeStartedAt) * 1000
		return Vector3.new(requestedPosition.X, bestResolvedRootY, requestedPosition.Z), true, bestResult, bestClassification
	end

	diagnostics.SurfaceProbeTimeMs += (os.clock() - probeStartedAt) * 1000
	return fallbackPosition, false, nil
end

function MoguBurrowShared.ConsumeDiagnostics()
	local snapshot = {
		RaycastCount = diagnostics.RaycastCount,
		SurfaceProbeCount = diagnostics.SurfaceProbeCount,
		SurfaceProbeTimeMs = diagnostics.SurfaceProbeTimeMs,
		RejectedSurfaceHitCount = diagnostics.RejectedSurfaceHitCount,
		PassThroughMovementHitCount = diagnostics.PassThroughMovementHitCount,
		BlockedMovementCount = diagnostics.BlockedMovementCount,
	}
	diagnostics.RaycastCount = 0
	diagnostics.SurfaceProbeCount = 0
	diagnostics.SurfaceProbeTimeMs = 0
	diagnostics.RejectedSurfaceHitCount = 0
	diagnostics.PassThroughMovementHitCount = 0
	diagnostics.BlockedMovementCount = 0
	return snapshot
end

return MoguBurrowShared
