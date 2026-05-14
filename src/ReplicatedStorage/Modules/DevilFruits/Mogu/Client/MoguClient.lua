local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local MoguAnimationController = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Client"):WaitForChild("MoguAnimationController")
)
local MoguVfxController = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Client"):WaitForChild("MoguVfxController")
)
local MoguBurrowShared = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguBurrowShared")
)

local MoguClient = {}
MoguClient.__index = MoguClient

local FRUIT_NAME = "Mogu Mogu no Mi"
local ABILITY_NAME = "Burrow"
local PHASE_START = "Start"
local PHASE_RESOLVE = "Resolve"
local SURFACE_REASON_MANUAL_TOGGLE = "manual_toggle"
local SURFACE_REASON_DURATION_ELAPSED = "duration_elapsed"
local SURFACE_REASON_SURFACE_LOST = "surface_lost"
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local TRAIL_COLOR = Color3.fromRGB(122, 95, 63)
local TRAIL_ACCENT_COLOR = Color3.fromRGB(166, 136, 97)
local BURST_COLOR = Color3.fromRGB(214, 194, 159)
local FLAT_RING_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local DEFAULT_ENTRY_CUE_FALLBACK_TIME = 0.24
local DEFAULT_MOVEMENT_CUE_FALLBACK_TIME = 0.42
local DEFAULT_VISUAL_SINK_DURATION = 0.24
local DEFAULT_VISUAL_RISE_DURATION = 0.18
local DEFAULT_RESOLVE_SURFACE_LOCK_DURATION = 0.28
local DEFAULT_ENTRY_VFX_FORWARD_OFFSET = 1.15
local DEFAULT_RESOLVE_ANIMATION_BACK_OFFSET = 0.85
local DEFAULT_RESOLVE_BACK_JERK_DISTANCE = 0.45
local DEFAULT_RESOLVE_BACK_JERK_DURATION = 0.08
local DEFAULT_RESOLVE_VFX_FORWARD_OFFSET = 0
local DEFAULT_RESOLVE_FACING_LOCK_DURATION = 0.6
local SURFACE_PROBE_INTERVAL = 1 / 24
local SURFACE_REPROBE_DISTANCE = 0.75
local MIN_TARGET_PROBE_DISTANCE = 0.035
local MIN_PIVOT_POSITION_DELTA = 0.03
local MIN_PIVOT_DIRECTION_DOT = 0.9995
local ZERO_VELOCITY_EPSILON = 0.025
local PENDING_START_FEEDBACK_TIMEOUT = 2
local TRAIL_PULSE_POOL_LIMIT = 48
local DEFAULT_ENTRY_CUE_MARKERS = {
	"EnterGround",
	"EntryVfx",
	"EntryVFX",
	"BurrowEntry",
	"DigImpact",
	"Dig",
}
local DEFAULT_MOVEMENT_CUE_MARKERS = {
	"FullyUnderground",
	"Underground",
	"BurrowMove",
	"MovementStart",
	"StartMoving",
}

local function getAbilityConfig()
	return DevilFruitConfig.GetAbility(FRUIT_NAME, ABILITY_NAME) or {}
end

local function getAnimationStageConfig(stageKey, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and animationConfig[stageKey] or {}
end

local function appendMarkerName(markerNames, seenMarkers, markerName)
	if typeof(markerName) ~= "string" or markerName == "" or seenMarkers[markerName] then
		return
	end

	seenMarkers[markerName] = true
	markerNames[#markerNames + 1] = markerName
end

local function appendMarkerNames(markerNames, seenMarkers, configuredMarkers)
	if type(configuredMarkers) ~= "table" then
		return
	end

	for _, markerName in ipairs(configuredMarkers) do
		appendMarkerName(markerNames, seenMarkers, markerName)
	end
end

local function getEntryCueMarkerNames(stageConfig)
	local markerNames = {}
	local seenMarkers = {}

	appendMarkerName(markerNames, seenMarkers, stageConfig.EntryCueMarker)
	appendMarkerName(markerNames, seenMarkers, stageConfig.EntryVfxMarker)
	appendMarkerName(markerNames, seenMarkers, stageConfig.VfxMarker)
	appendMarkerNames(markerNames, seenMarkers, stageConfig.EntryCueMarkers)
	appendMarkerNames(markerNames, seenMarkers, stageConfig.EntryVfxMarkers)
	appendMarkerNames(markerNames, seenMarkers, stageConfig.VfxMarkers)
	appendMarkerNames(markerNames, seenMarkers, DEFAULT_ENTRY_CUE_MARKERS)

	return markerNames
end

local function getMovementCueMarkerNames(stageConfig)
	local markerNames = {}
	local seenMarkers = {}

	appendMarkerName(markerNames, seenMarkers, stageConfig.MovementCueMarker)
	appendMarkerName(markerNames, seenMarkers, stageConfig.BurrowMoveMarker)
	appendMarkerName(markerNames, seenMarkers, stageConfig.UndergroundMarker)
	appendMarkerNames(markerNames, seenMarkers, stageConfig.MovementCueMarkers)
	appendMarkerNames(markerNames, seenMarkers, stageConfig.BurrowMoveMarkers)
	appendMarkerNames(markerNames, seenMarkers, stageConfig.UndergroundMarkers)
	appendMarkerNames(markerNames, seenMarkers, DEFAULT_MOVEMENT_CUE_MARKERS)

	return markerNames
end

local function getEntryCueFallbackTime(stageConfig)
	return math.max(
		0,
		tonumber(stageConfig.EntryCueFallbackTime)
			or tonumber(stageConfig.EntryVfxDelay)
			or tonumber(stageConfig.ConcealDelay)
			or DEFAULT_ENTRY_CUE_FALLBACK_TIME
	)
end

local function getMovementCueFallbackTime(stageConfig)
	return math.max(
		0,
		tonumber(stageConfig.MovementCueFallbackTime)
			or tonumber(stageConfig.BurrowMoveDelay)
			or tonumber(stageConfig.MovementStartDelay)
			or DEFAULT_MOVEMENT_CUE_FALLBACK_TIME
	)
end

local function getVisualSinkDepth(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return math.max(
		0,
		tonumber(startConfig.VisualSinkDepth)
			or tonumber(startConfig.SinkDepth)
			or tonumber(abilityConfig and abilityConfig.VisualSinkDepth)
			or tonumber(abilityConfig and abilityConfig.RootGroundClearance)
			or 3.2
	)
end

local function getVisualSinkDuration(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return math.max(
		0,
		tonumber(startConfig.VisualSinkDuration)
			or tonumber(startConfig.SinkDuration)
			or tonumber(abilityConfig and abilityConfig.VisualSinkDuration)
			or DEFAULT_VISUAL_SINK_DURATION
	)
end

local function getVisualRiseDuration(abilityConfig)
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return math.max(
		0,
		tonumber(resolveConfig.VisualRiseDuration)
			or tonumber(resolveConfig.RiseDuration)
			or tonumber(abilityConfig and abilityConfig.VisualRiseDuration)
			or DEFAULT_VISUAL_RISE_DURATION
	)
end

local function getResolveSurfaceLockDuration(abilityConfig)
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return math.max(
		0,
		tonumber(resolveConfig.SurfaceLockDuration)
			or tonumber(abilityConfig and abilityConfig.ResolveSurfaceLockDuration)
			or DEFAULT_RESOLVE_SURFACE_LOCK_DURATION
	)
end

local function getResolveFacingLockDuration(abilityConfig)
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return math.max(
		0,
		tonumber(resolveConfig.FacingLockDuration)
			or tonumber(resolveConfig.AutoRotateLockDuration)
			or tonumber(abilityConfig and abilityConfig.ResolveFacingLockDuration)
			or DEFAULT_RESOLVE_FACING_LOCK_DURATION
	)
end

local function getEntryVfxForwardOffset(abilityConfig)
	local vfxConfig = type(abilityConfig) == "table" and abilityConfig.Vfx or nil
	local entryConfig = type(vfxConfig) == "table" and vfxConfig.Entry or nil
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return math.max(
		0,
		tonumber(entryConfig and entryConfig.ForwardOffset)
			or tonumber(entryConfig and entryConfig.PositionForwardOffset)
			or tonumber(startConfig.EntryVfxForwardOffset)
			or tonumber(startConfig.EntryForwardOffset)
			or tonumber(abilityConfig and abilityConfig.EntryVfxForwardOffset)
			or DEFAULT_ENTRY_VFX_FORWARD_OFFSET
	)
end

local function getResolveAnimationBackOffset(abilityConfig)
	local vfxConfig = type(abilityConfig) == "table" and abilityConfig.Vfx or nil
	local resolveVfxConfig = type(vfxConfig) == "table" and vfxConfig.Resolve or nil
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return math.max(
		0,
		tonumber(resolveConfig.AnimationBackOffset)
			or tonumber(resolveConfig.BackOffset)
			or tonumber(resolveVfxConfig and resolveVfxConfig.AnimationBackOffset)
			or tonumber(abilityConfig and abilityConfig.ResolveAnimationBackOffset)
			or DEFAULT_RESOLVE_ANIMATION_BACK_OFFSET
	)
end

local function getResolveVfxForwardOffset(abilityConfig)
	local vfxConfig = type(abilityConfig) == "table" and abilityConfig.Vfx or nil
	local resolveVfxConfig = type(vfxConfig) == "table" and vfxConfig.Resolve or nil
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return tonumber(resolveVfxConfig and resolveVfxConfig.ForwardOffset)
		or tonumber(resolveVfxConfig and resolveVfxConfig.PositionForwardOffset)
		or tonumber(resolveConfig.ResolveVfxForwardOffset)
		or tonumber(resolveConfig.VfxForwardOffset)
		or tonumber(abilityConfig and abilityConfig.ResolveVfxForwardOffset)
		or DEFAULT_RESOLVE_VFX_FORWARD_OFFSET
end

local function getResolveBackJerkDistance(abilityConfig)
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return math.max(
		0,
		tonumber(resolveConfig.BackJerkDistance)
			or tonumber(resolveConfig.ResolveBackJerkDistance)
			or tonumber(abilityConfig and abilityConfig.ResolveBackJerkDistance)
			or DEFAULT_RESOLVE_BACK_JERK_DISTANCE
	)
end

local function getResolveBackJerkDuration(abilityConfig)
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return math.max(
		0,
		tonumber(resolveConfig.BackJerkDuration)
			or tonumber(resolveConfig.ResolveBackJerkDuration)
			or tonumber(abilityConfig and abilityConfig.ResolveBackJerkDuration)
			or DEFAULT_RESOLVE_BACK_JERK_DURATION
	)
end

local function disconnectConnections(connections)
	if type(connections) ~= "table" then
		return
	end

	for _, connection in ipairs(connections) do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
end

local function clearEntryCueState(burrowState)
	if type(burrowState) ~= "table" then
		return
	end

	burrowState.EntryCueToken = nil
	disconnectConnections(burrowState.EntryCueConnections)
	burrowState.EntryCueConnections = nil
end

local function clearMovementCueState(burrowState)
	if type(burrowState) ~= "table" then
		return
	end

	burrowState.MovementCueToken = nil
	disconnectConnections(burrowState.MovementCueConnections)
	burrowState.MovementCueConnections = nil
end

local function clearBurrowCueState(burrowState)
	clearEntryCueState(burrowState)
	clearMovementCueState(burrowState)
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getPerpendicularPlanarRightVector(forwardVector)
	return Vector3.new(-forwardVector.Z, 0, forwardVector.X)
end

local function resolvePlanarDirection(direction, fallback)
	local planarDirection = typeof(direction) == "Vector3" and getPlanarVector(direction) or nil
	if planarDirection and planarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarDirection.Unit
	end

	local planarFallback = typeof(fallback) == "Vector3" and getPlanarVector(fallback) or nil
	if planarFallback and planarFallback.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarFallback.Unit
	end

	return DEFAULT_DIRECTION
end

local function getHumanoidMoveDirection(humanoid)
	local moveDirection = humanoid and humanoid.MoveDirection or nil
	local planarMoveDirection = typeof(moveDirection) == "Vector3" and getPlanarVector(moveDirection) or nil
	if planarMoveDirection and planarMoveDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarMoveDirection.Unit
	end

	return nil
end

local function getResolveAnimationPosition(surfacePosition, direction, rootPart, abilityConfig)
	if typeof(surfacePosition) ~= "Vector3" then
		return surfacePosition
	end

	local backOffset = getResolveAnimationBackOffset(abilityConfig)
	if backOffset <= 0 then
		return surfacePosition
	end

	local resolveDirection = resolvePlanarDirection(direction, rootPart and rootPart.CFrame.LookVector or nil)
	return surfacePosition - (resolveDirection * backOffset)
end

local function getResolveVfxPosition(resolveAnimationPosition, direction, rootPart, abilityConfig)
	if typeof(resolveAnimationPosition) ~= "Vector3" then
		return resolveAnimationPosition
	end

	local forwardOffset = getResolveVfxForwardOffset(abilityConfig)
	if forwardOffset == 0 then
		return resolveAnimationPosition
	end

	local resolveDirection = resolvePlanarDirection(direction, rootPart and rootPart.CFrame.LookVector or nil)
	return resolveAnimationPosition + (resolveDirection * forwardOffset)
end

local function getResolveBackJerkPosition(startPosition, direction, rootPart, elapsedTime, jerkDistance, jerkDuration)
	if typeof(startPosition) ~= "Vector3" or jerkDistance <= 0 or jerkDuration <= 0 then
		return startPosition
	end

	local alpha = math.clamp(elapsedTime / jerkDuration, 0, 1)
	local easedAlpha = 1 - ((1 - alpha) * (1 - alpha))
	local resolveDirection = resolvePlanarDirection(direction, rootPart and rootPart.CFrame.LookVector or nil)
	return startPosition - (resolveDirection * jerkDistance * easedAlpha)
end

local function getCharacter(player)
	return player and player.Character or nil
end

local function getHumanoid(player)
	local character = getCharacter(player)
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRootPart(player)
	local character = getCharacter(player)
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getGroundEffectPosition(position)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	return position - Vector3.new(0, math.max(1.5, tonumber(getAbilityConfig().RootGroundClearance) or 3.2) - 0.15, 0)
end

local function tweenAndDestroy(instance, duration, tweenGoals)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		tweenGoals
	)
	tween:Play()
	tween.Completed:Connect(function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

local function createEffectPart(name, size, color, cframe, material, transparency, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Ground
	part.Transparency = transparency or 0
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Shape = shape or Enum.PartType.Block
	part.Parent = Workspace
	return part
end

local trailPulsePool = {
	Pulse = {},
	Accent = {},
	Active = {},
}

local function setupEffectPart(part, name, size, color, cframe, material, transparency, shape)
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Ground
	part.Transparency = transparency or 0
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Shape = shape or Enum.PartType.Block
end

local function acquireTrailEffectPart(poolName, name, size, color, cframe, material, transparency, shape)
	local pool = trailPulsePool[poolName]
	local part = pool and table.remove(pool) or nil
	if not part then
		part = Instance.new("Part")
	end

	setupEffectPart(part, name, size, color, cframe, material, transparency, shape)
	trailPulsePool.Active[part] = poolName
	part.Parent = Workspace
	return part
end

local function releaseTrailEffectPart(part)
	if not part then
		return
	end

	local poolName = trailPulsePool.Active[part]
	trailPulsePool.Active[part] = nil
	part.Parent = nil
	local pool = trailPulsePool[poolName]
	if pool and #pool < TRAIL_PULSE_POOL_LIMIT then
		pool[#pool + 1] = part
	else
		part:Destroy()
	end
end

local function tweenAndReleaseTrailPart(part, duration, tweenGoals)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		tweenGoals
	)
	tween:Play()
	tween.Completed:Connect(function()
		releaseTrailEffectPart(part)
	end)
end

local function cleanupTrailPulsePool()
	for part in pairs(trailPulsePool.Active) do
		if part then
			part:Destroy()
		end
		trailPulsePool.Active[part] = nil
	end

	for _, poolName in ipairs({ "Pulse", "Accent" }) do
		local pool = trailPulsePool[poolName]
		for index = #pool, 1, -1 do
			local part = pool[index]
			pool[index] = nil
			if part then
				part:Destroy()
			end
		end
	end
end

local function createBurst(position, radius, isResolve)
	local groundPosition = getGroundEffectPosition(position)
	if not groundPosition then
		return
	end

	local burstRadius = math.max(1, tonumber(radius) or 3)
	local ring = createEffectPart(
		isResolve and "MoguResolveRing" or "MoguEntryRing",
		Vector3.new(0.16, burstRadius * 1.5, burstRadius * 1.5),
		TRAIL_ACCENT_COLOR,
		CFrame.new(groundPosition) * FLAT_RING_ROTATION,
		Enum.Material.SmoothPlastic,
		0.18,
		Enum.PartType.Cylinder
	)
	tweenAndDestroy(ring, isResolve and 0.28 or 0.22, {
		Transparency = 1,
		Size = Vector3.new(0.16, burstRadius * 2.35, burstRadius * 2.35),
	})

	local pulse = createEffectPart(
		isResolve and "MoguResolveBurst" or "MoguEntryBurst",
		Vector3.new(burstRadius, burstRadius * 0.65, burstRadius),
		isResolve and BURST_COLOR or TRAIL_COLOR,
		CFrame.new(groundPosition + Vector3.new(0, burstRadius * 0.08, 0)),
		Enum.Material.Ground,
		0.12,
		Enum.PartType.Ball
	)
	tweenAndDestroy(pulse, isResolve and 0.24 or 0.2, {
		Transparency = 1,
		Size = pulse.Size * 1.7,
	})
end

local function createTrailPulse(position, radius)
	local groundPosition = getGroundEffectPosition(position)
	if not groundPosition then
		return false
	end

	local pulseRadius = math.max(0.7, tonumber(radius) or 1.3)
	local pulse = acquireTrailEffectPart(
		"Pulse",
		"MoguBurrowPulse",
		Vector3.new(pulseRadius, pulseRadius * 0.42, pulseRadius),
		TRAIL_COLOR,
		CFrame.new(groundPosition + Vector3.new(0, pulseRadius * 0.04, 0)),
		Enum.Material.Ground,
		0.26,
		Enum.PartType.Ball
	)
	tweenAndReleaseTrailPart(pulse, 0.18, {
		Transparency = 1,
		Size = pulse.Size * 1.35,
	})

	local accent = acquireTrailEffectPart(
		"Accent",
		"MoguBurrowPulseAccent",
		Vector3.new(0.12, pulseRadius * 1.15, pulseRadius * 1.15),
		TRAIL_ACCENT_COLOR,
		CFrame.new(groundPosition) * FLAT_RING_ROTATION,
		Enum.Material.SmoothPlastic,
		0.36,
		Enum.PartType.Cylinder
	)
	tweenAndReleaseTrailPart(accent, 0.16, {
		Transparency = 1,
		Size = Vector3.new(0.12, pulseRadius * 1.65, pulseRadius * 1.65),
	})
	return true
end

local function shouldSkipPivot(pivotState, targetRootCFrame)
	if type(pivotState) ~= "table" or typeof(targetRootCFrame) ~= "CFrame" then
		return false
	end

	local lastRootCFrame = pivotState.LastPivotRootCFrame
	if typeof(lastRootCFrame) ~= "CFrame" then
		return false
	end

	return (lastRootCFrame.Position - targetRootCFrame.Position).Magnitude <= MIN_PIVOT_POSITION_DELTA
		and lastRootCFrame.LookVector:Dot(targetRootCFrame.LookVector) >= MIN_PIVOT_DIRECTION_DOT
end

local function pivotCharacterToRootPosition(character, rootPart, targetRootPosition, direction, pivotState)
	if not character or not rootPart or typeof(targetRootPosition) ~= "Vector3" then
		return false
	end

	local facingDirection = resolvePlanarDirection(direction, rootPart.CFrame.LookVector)
	local targetRootCFrame = CFrame.lookAt(targetRootPosition, targetRootPosition + facingDirection, Vector3.yAxis)
	if shouldSkipPivot(pivotState, targetRootCFrame) then
		return false
	end

	local pivotToRoot = character:GetPivot():ToObjectSpace(rootPart.CFrame)
	character:PivotTo(targetRootCFrame * pivotToRoot:Inverse())
	if type(pivotState) == "table" then
		pivotState.LastPivotRootCFrame = targetRootCFrame
	end
	return true
end

local function zeroRootVelocity(rootPart, includeAngular, includeLinear)
	if not rootPart then
		return false
	end

	local wrote = false
	if includeLinear ~= false and rootPart.AssemblyLinearVelocity.Magnitude > ZERO_VELOCITY_EPSILON then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		wrote = true
	end
	if includeAngular ~= false and rootPart.AssemblyAngularVelocity.Magnitude > ZERO_VELOCITY_EPSILON then
		rootPart.AssemblyAngularVelocity = Vector3.zero
		wrote = true
	end
	return wrote
end

local function lockCharacterToSurface(
	character,
	rootPart,
	targetRootPosition,
	direction,
	abilityConfig,
	duration,
	jerkDistance,
	jerkDuration,
	pivotState,
	onPivotWrite
)
	if not character or not rootPart or typeof(targetRootPosition) ~= "Vector3" then
		return
	end

	local startedAt = os.clock()
	local endsAt = startedAt + math.max(0, tonumber(duration) or 0)
	local resolvedJerkDistance = math.max(0, tonumber(jerkDistance) or 0)
	local resolvedJerkDuration = math.max(0, tonumber(jerkDuration) or 0)
	task.spawn(function()
		while true do
			local now = os.clock()
			if now > endsAt then
				return
			end

			if not character.Parent or not rootPart.Parent then
				return
			end

			local lockedRootPosition = getResolveBackJerkPosition(
				targetRootPosition,
				direction,
				rootPart,
				now - startedAt,
				resolvedJerkDistance,
				resolvedJerkDuration
			)
			local resolvedPosition = select(
				1,
				MoguBurrowShared.ResolveSurfaceRootPosition(
					character,
					rootPart,
					lockedRootPosition,
					abilityConfig,
					lockedRootPosition
				)
			) or lockedRootPosition

			local didPivot = pivotCharacterToRootPosition(character, rootPart, resolvedPosition, direction, pivotState)
			if didPivot and typeof(onPivotWrite) == "function" then
				onPivotWrite()
			end
			zeroRootVelocity(rootPart, true)
			RunService.Heartbeat:Wait()
		end
	end)
end

local function restoreAutoRotateAfterResolve(humanoid, originalAutoRotate, animationState, fallbackDuration)
	if not humanoid then
		return
	end

	local restored = false
	local connection = nil
	local function restore()
		if restored then
			return
		end

		restored = true
		if connection then
			connection:Disconnect()
			connection = nil
		end

		if humanoid.Parent then
			humanoid.AutoRotate = originalAutoRotate ~= false
		end
	end

	local track = type(animationState) == "table" and animationState.Track or nil
	if track and track.Stopped then
		connection = track.Stopped:Connect(restore)
	end

	task.delay(math.max(0.05, tonumber(fallbackDuration) or 0), restore)
end

local function keepFacingDuringResolve(character, rootPart, direction, duration, startDelay, pivotState, onPivotWrite)
	if not character or not rootPart then
		return
	end

	local resolvedStartDelay = math.max(0, tonumber(startDelay) or 0)
	local resolvedDuration = math.max(0, tonumber(duration) or 0)
	if resolvedDuration <= 0 then
		return
	end

	task.spawn(function()
		if resolvedStartDelay > 0 then
			task.wait(resolvedStartDelay)
		end

		local endsAt = os.clock() + resolvedDuration
		while os.clock() <= endsAt do
			if not character.Parent or not rootPart.Parent then
				return
			end

			local didPivot = pivotCharacterToRootPosition(character, rootPart, rootPart.Position, direction, pivotState)
			if didPivot and typeof(onPivotWrite) == "function" then
				onPivotWrite()
			end
			zeroRootVelocity(rootPart, true, false)
			RunService.Heartbeat:Wait()
		end
	end)
end

local function findRootVisualMotor(character, rootPart)
	if not character or not rootPart then
		return nil, nil
	end

	local fallbackMotor = nil
	local fallbackPropertyName = nil
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			local propertyName = nil
			if descendant.Part0 == rootPart and descendant.Part1 and descendant.Part1 ~= rootPart then
				propertyName = "C0"
			elseif descendant.Part1 == rootPart and descendant.Part0 and descendant.Part0 ~= rootPart then
				propertyName = "C1"
			end

			if propertyName then
				if descendant.Name == "RootJoint" or descendant.Name == "Root" then
					return descendant, propertyName
				end
				fallbackMotor = fallbackMotor or descendant
				fallbackPropertyName = fallbackPropertyName or propertyName
			end
		end
	end

	return fallbackMotor, fallbackPropertyName
end

function MoguClient.Create(config)
	config = config or {}

	local self = setmetatable({}, MoguClient)
	self.player = config.player or Players.LocalPlayer
	self.getCurrentCamera = type(config.GetCurrentCamera) == "function" and config.GetCurrentCamera or function()
		return Workspace.CurrentCamera
	end
	self.getHumanoid = type(config.GetHumanoid) == "function" and config.GetHumanoid or function()
		return getHumanoid(self.player)
	end
	self.getLocalRootPart = type(config.GetLocalRootPart) == "function" and config.GetLocalRootPart or function()
		return getRootPart(self.player)
	end
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or function() end
	self.requestAbility = type(config.RequestAbility) == "function" and config.RequestAbility or nil
	self.animationController = MoguAnimationController.new()
	self.vfxController = MoguVfxController.new()
	self.burrowInputState = {
		Forward = false,
		Backward = false,
		Left = false,
		Right = false,
	}
	self.burrowStates = {}
	self.visualBurrowStates = {}
	self.concealStates = {}
	self.pendingBurrowFeedback = nil
	self.diagnostics = {
		LastFlushAt = os.clock(),
		PivotWrites = 0,
		TrailPulseCount = 0,
		CleanupCount = 0,
		LastSurfaceProbeTimeMs = 0,
		LastRaycastsPerSecond = 0,
		LastPivotWritesPerSecond = 0,
		LastStartInputToFeedbackMs = 0,
		LastStartInputToAuthorizedMs = 0,
		LastResolveCorrectionDistance = 0,
	}
	return self
end

function MoguClient:SetDiagnosticAttribute(name, value)
	local player = self.player
	if not player or typeof(name) ~= "string" then
		return
	end

	player:SetAttribute(name, value)
end

function MoguClient:RecordPivotWrite(didWrite)
	if didWrite and self.diagnostics then
		self.diagnostics.PivotWrites += 1
	end
end

function MoguClient:RecordCleanup()
	if self.diagnostics then
		self.diagnostics.CleanupCount += 1
	end
end

function MoguClient:PublishDiagnostics(force)
	local diagnostics = self.diagnostics
	if not diagnostics then
		return
	end

	local now = os.clock()
	local elapsed = math.max(0.001, now - (diagnostics.LastFlushAt or now))
	if not force and elapsed < 1 then
		return
	end

	local sharedDiagnostics = MoguBurrowShared.ConsumeDiagnostics()
	local raycastsPerSecond = math.floor(((sharedDiagnostics.RaycastCount or 0) / elapsed) + 0.5)
	local pivotWritesPerSecond = math.floor(((diagnostics.PivotWrites or 0) / elapsed) + 0.5)
	local activeLocalBurrowCount = self:GetLocalBurrowState() and 1 or 0

	diagnostics.LastFlushAt = now
	diagnostics.LastRaycastsPerSecond = raycastsPerSecond
	diagnostics.LastPivotWritesPerSecond = pivotWritesPerSecond
	diagnostics.LastSurfaceProbeTimeMs = sharedDiagnostics.SurfaceProbeTimeMs or 0
	diagnostics.PivotWrites = 0

	self:SetDiagnosticAttribute("MoguRaycastsPerSecond", raycastsPerSecond)
	self:SetDiagnosticAttribute("MoguSurfaceProbeTimeMs", diagnostics.LastSurfaceProbeTimeMs)
	self:SetDiagnosticAttribute("MoguPivotToWritesPerSecond", pivotWritesPerSecond)
	self:SetDiagnosticAttribute("MoguTrailPulseCount", diagnostics.TrailPulseCount or 0)
	self:SetDiagnosticAttribute("MoguActiveLocalBurrowCount", activeLocalBurrowCount)
	self:SetDiagnosticAttribute("MoguStartInputToFeedbackMs", diagnostics.LastStartInputToFeedbackMs or 0)
	self:SetDiagnosticAttribute("MoguStartInputToAuthorizedMs", diagnostics.LastStartInputToAuthorizedMs or 0)
	self:SetDiagnosticAttribute("MoguResolveCorrectionDistance", diagnostics.LastResolveCorrectionDistance or 0)
	self:SetDiagnosticAttribute("MoguCleanupCount", diagnostics.CleanupCount or 0)
end

function MoguClient:SetBurrowInputKeyState(keyCode, isPressed)
	if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
		self.burrowInputState.Forward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
		self.burrowInputState.Backward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
		self.burrowInputState.Left = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
		self.burrowInputState.Right = isPressed
		return true
	end

	return false
end

function MoguClient:GetBurrowInputAxes()
	local forwardAxis = 0
	local rightAxis = 0

	if self.burrowInputState.Forward then
		forwardAxis += 1
	end
	if self.burrowInputState.Backward then
		forwardAxis -= 1
	end
	if self.burrowInputState.Right then
		rightAxis += 1
	end
	if self.burrowInputState.Left then
		rightAxis -= 1
	end

	return forwardAxis, rightAxis
end

function MoguClient:GetCameraRelativeBurrowDirection(rootPart)
	local forwardAxis, rightAxis = self:GetBurrowInputAxes()
	if forwardAxis == 0 and rightAxis == 0 then
		return Vector3.zero
	end

	local camera = self.getCurrentCamera()
	local forwardVector = resolvePlanarDirection(
		camera and camera.CFrame.LookVector or (rootPart and rootPart.CFrame.LookVector),
		rootPart and rootPart.CFrame.LookVector or nil
	)
	local rawRightVector = camera and camera.CFrame.RightVector or (rootPart and rootPart.CFrame.RightVector) or nil
	local rightVector = getPlanarVector(rawRightVector)
	if rightVector.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		rightVector = getPerpendicularPlanarRightVector(forwardVector)
	else
		rightVector = rightVector.Unit
	end

	local direction = (forwardVector * forwardAxis) + (rightVector * rightAxis)
	local magnitude = direction.Magnitude
	if magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector3.zero
	end

	return direction.Unit * math.min(math.sqrt((forwardAxis * forwardAxis) + (rightAxis * rightAxis)), 1)
end

function MoguClient:GetBurrowActivationDirection(rootPart)
	local moveDirection = getHumanoidMoveDirection(self.getHumanoid())
	if moveDirection then
		return moveDirection
	end

	local inputDirection = self:GetCameraRelativeBurrowDirection(rootPart)
	if inputDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return inputDirection.Unit
	end

	return resolvePlanarDirection(rootPart and rootPart.CFrame.LookVector or nil, nil)
end

function MoguClient:GetBurrowSurfaceDirection(rootPart, fallbackDirection)
	local inputDirection = self:GetCameraRelativeBurrowDirection(rootPart)
	if inputDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return inputDirection.Unit
	end

	local moveDirection = getHumanoidMoveDirection(self.getHumanoid())
	if moveDirection then
		return moveDirection
	end

	return resolvePlanarDirection(fallbackDirection, rootPart and rootPart.CFrame.LookVector or nil)
end

function MoguClient:ClearVisualBurrowOffset(targetPlayer, shouldTween, duration, onComplete)
	local visualState = self.visualBurrowStates[targetPlayer]
	if not visualState then
		if typeof(onComplete) == "function" then
			onComplete()
		end
		return
	end

	if visualState.Tween then
		visualState.Tween:Cancel()
		visualState.Tween = nil
	end

	local motor = visualState.Motor
	local propertyName = visualState.PropertyName
	if not motor or not motor.Parent or typeof(propertyName) ~= "string" then
		self.visualBurrowStates[targetPlayer] = nil
		if typeof(onComplete) == "function" then
			onComplete()
		end
		return
	end

	local originalCFrame = visualState.OriginalCFrame
	if typeof(originalCFrame) ~= "CFrame" then
		self.visualBurrowStates[targetPlayer] = nil
		if typeof(onComplete) == "function" then
			onComplete()
		end
		return
	end

	local tweenDuration = math.max(0, tonumber(duration) or 0)
	if shouldTween and tweenDuration > 0 then
		local token = {}
		visualState.Token = token
		local tween = TweenService:Create(
			motor,
			TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ [propertyName] = originalCFrame }
		)
		visualState.Tween = tween
		tween.Completed:Connect(function()
			if self.visualBurrowStates[targetPlayer] ~= visualState or visualState.Token ~= token then
				return
			end

			visualState.Tween = nil
			self.visualBurrowStates[targetPlayer] = nil
			if typeof(onComplete) == "function" then
				onComplete()
			end
		end)
		tween:Play()
	else
		visualState.Token = nil
		motor[propertyName] = originalCFrame
		self.visualBurrowStates[targetPlayer] = nil
		if typeof(onComplete) == "function" then
			onComplete()
		end
	end
end

function MoguClient:ApplyVisualBurrowOffset(targetPlayer, abilityConfig)
	local character = getCharacter(targetPlayer)
	local rootPart = getRootPart(targetPlayer)
	local motor, propertyName = findRootVisualMotor(character, rootPart)
	if not motor or typeof(propertyName) ~= "string" then
		return false
	end

	self:ClearVisualBurrowOffset(targetPlayer, false)

	local originalCFrame = motor[propertyName]
	local depth = getVisualSinkDepth(abilityConfig)
	if depth <= 0 then
		return false
	end

	local targetCFrame = CFrame.new(0, -depth, 0) * originalCFrame
	local visualState = {
		Motor = motor,
		PropertyName = propertyName,
		OriginalCFrame = originalCFrame,
		TargetCFrame = targetCFrame,
		Token = {},
		Tween = nil,
	}
	self.visualBurrowStates[targetPlayer] = visualState

	local sinkDuration = getVisualSinkDuration(abilityConfig)
	if sinkDuration > 0 then
		local tween = TweenService:Create(
			motor,
			TweenInfo.new(sinkDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ [propertyName] = targetCFrame }
		)
		visualState.Tween = tween
		tween:Play()
	else
		motor[propertyName] = targetCFrame
	end

	return true
end

function MoguClient:SnapVisualBurrowOffset(targetPlayer)
	local visualState = self.visualBurrowStates[targetPlayer]
	if not visualState then
		return false
	end

	if visualState.Tween then
		visualState.Tween:Cancel()
		visualState.Tween = nil
	end

	local motor = visualState.Motor
	local propertyName = visualState.PropertyName
	if not motor or not motor.Parent or typeof(propertyName) ~= "string" then
		return false
	end

	if typeof(visualState.TargetCFrame) == "CFrame" then
		motor[propertyName] = visualState.TargetCFrame
		return true
	end

	return false
end

function MoguClient:ApplyConceal(targetPlayer, transparency)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	self:ClearConceal(targetPlayer)

	local character = getCharacter(targetPlayer)
	if not character then
		return
	end

	local previousByPart = {}
	local previousCanCollideByPart = {}
	local previousBySurfaceVisual = {}
	local previousGuiEnabled = {}
	local previousHumanoidDisplay = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			previousByPart[descendant] = descendant.LocalTransparencyModifier
			previousCanCollideByPart[descendant] = descendant.CanCollide
			descendant.LocalTransparencyModifier = math.max(descendant.LocalTransparencyModifier, transparency)
			descendant.CanCollide = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			previousBySurfaceVisual[descendant] = descendant.Transparency
			descendant.Transparency = math.max(descendant.Transparency, transparency)
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			previousGuiEnabled[descendant] = descendant.Enabled
			descendant.Enabled = false
		elseif descendant:IsA("Humanoid") then
			previousHumanoidDisplay[descendant] = descendant.DisplayDistanceType
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		end
	end

	self.concealStates[targetPlayer] = {
		PreviousByPart = previousByPart,
		PreviousCanCollideByPart = previousCanCollideByPart,
		PreviousBySurfaceVisual = previousBySurfaceVisual,
		PreviousGuiEnabled = previousGuiEnabled,
		PreviousHumanoidDisplay = previousHumanoidDisplay,
	}
end

function MoguClient:ApplyConcealWhenReady(targetPlayer, burrowState)
	if not targetPlayer or not burrowState then
		return
	end

	local concealDelay = math.max(
		0,
		tonumber(burrowState.ConcealDelay) or tonumber(getAnimationStageConfig("Start", getAbilityConfig()).ConcealDelay) or 0
	)
	if concealDelay <= 0 then
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		burrowState.ConcealApplied = true
		return
	end

	local concealToken = {}
	burrowState.PendingConcealToken = concealToken
	task.delay(math.min(concealDelay, burrowState.Duration), function()
		local activeBurrowState = self.burrowStates[targetPlayer]
		if activeBurrowState ~= burrowState or activeBurrowState.PendingConcealToken ~= concealToken then
			return
		end

		activeBurrowState.PendingConcealToken = nil
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		activeBurrowState.ConcealApplied = true
	end)
end

function MoguClient:TriggerBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
	if not targetPlayer or self.burrowStates[targetPlayer] ~= burrowState then
		return false
	end

	if burrowState.EntryCueTriggered then
		return false
	end

	burrowState.EntryCueTriggered = true
	clearEntryCueState(burrowState)

	if not self.visualBurrowStates[targetPlayer] then
		self:ApplyVisualBurrowOffset(targetPlayer, abilityConfig)
	end

	local rootPart = getRootPart(targetPlayer)
	local entryPosition = if burrowState.IsLocal and typeof(burrowState.SurfaceRootPosition) == "Vector3"
		then burrowState.SurfaceRootPosition
		else rootPart and rootPart.Position or startPosition
	if typeof(entryPosition) == "Vector3" then
		local entryDirection = resolvePlanarDirection(burrowState.Direction, rootPart and rootPart.CFrame.LookVector or nil)
		entryPosition += entryDirection * getEntryVfxForwardOffset(abilityConfig)
	end

	if not self.vfxController:PlayEntry(entryPosition, burrowState.Direction, abilityConfig) then
		createBurst(entryPosition, burrowState.EntryBurstRadius, false)
	end

	return true
end

function MoguClient:TriggerBurrowMovementCue(targetPlayer, burrowState, startPosition, abilityConfig)
	if not targetPlayer or self.burrowStates[targetPlayer] ~= burrowState then
		return false
	end

	if burrowState.MovementCueTriggered then
		return false
	end

	if not burrowState.EntryCueTriggered then
		self:TriggerBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
	end

	burrowState.MovementCueTriggered = true
	clearMovementCueState(burrowState)
	burrowState.LastTrailAt = Workspace:GetServerTimeNow()
	self:SnapVisualBurrowOffset(targetPlayer)
	if not burrowState.ConcealApplied then
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		burrowState.ConcealApplied = true
	end

	return true
end

function MoguClient:BeginLocalStartFeedback(direction)
	if self.pendingBurrowFeedback or self:GetLocalBurrowState() then
		return nil
	end

	local character = getCharacter(self.player)
	local rootPart = self.getLocalRootPart()
	if not character or not rootPart then
		return nil
	end

	local requestedAt = os.clock()
	local abilityConfig = getAbilityConfig()
	local resolvedDirection = resolvePlanarDirection(direction, rootPart.CFrame.LookVector)
	local startPosition = rootPart.Position
	local surfacePosition = select(
		1,
		MoguBurrowShared.ResolveSurfaceRootPosition(
			character,
			rootPart,
			startPosition,
			abilityConfig,
			startPosition,
			{ FastSample = true }
		)
	) or startPosition

	local animationState = self.animationController:PlayStart(self.player, abilityConfig)
	self:ApplyVisualBurrowOffset(self.player, abilityConfig)

	local entryPosition = surfacePosition + (resolvedDirection * getEntryVfxForwardOffset(abilityConfig))
	if not self.vfxController:PlayEntry(entryPosition, resolvedDirection, abilityConfig) then
		createBurst(entryPosition, MoguBurrowShared.GetEntryBurstRadius(abilityConfig), false)
	end

	local token = {}
	local pending = {
		Token = token,
		RequestedAt = requestedAt,
		Direction = resolvedDirection,
		SurfaceRootPosition = surfacePosition,
		AnimationState = animationState,
		EntryCueTriggered = true,
	}
	self.pendingBurrowFeedback = pending
	if self.diagnostics then
		self.diagnostics.LastStartInputToFeedbackMs = (os.clock() - requestedAt) * 1000
	end

	task.delay(PENDING_START_FEEDBACK_TIMEOUT, function()
		if self.pendingBurrowFeedback == pending and pending.Token == token then
			self:CancelLocalStartFeedback("timeout")
		end
	end)

	return pending
end

function MoguClient:CancelLocalStartFeedback(reason)
	local pending = self.pendingBurrowFeedback
	if not pending then
		return false
	end

	self.pendingBurrowFeedback = nil
	self.animationController:StopAnimation(pending.AnimationState, reason or "prediction_cancelled")
	self:ClearVisualBurrowOffset(self.player, true, DEFAULT_VISUAL_RISE_DURATION)
	self:ClearConceal(self.player)
	self:RecordCleanup()
	self:PublishDiagnostics(true)
	return true
end

function MoguClient:ScheduleBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
	local stageConfig = getAnimationStageConfig("Start", abilityConfig)
	local fallbackTime = getEntryCueFallbackTime(stageConfig)
	local token = {}
	local connections = {}

	burrowState.EntryCueToken = token
	burrowState.EntryCueConnections = connections

	local function trigger()
		if self.burrowStates[targetPlayer] ~= burrowState or burrowState.EntryCueToken ~= token then
			return
		end

		self:TriggerBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
	end

	local animationState = burrowState.AnimationState
	local track = type(animationState) == "table" and animationState.Track or nil
	if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		local markerNames = getEntryCueMarkerNames(stageConfig)
		for _, markerName in ipairs(markerNames) do
			local ok, connection = pcall(function()
				return track:GetMarkerReachedSignal(markerName):Connect(trigger)
			end)
			if ok and typeof(connection) == "RBXScriptConnection" then
				connections[#connections + 1] = connection
			end
		end

		connections[#connections + 1] = track.KeyframeReached:Connect(function(keyframeName)
			for _, markerName in ipairs(markerNames) do
				if keyframeName == markerName then
					trigger()
					return
				end
			end
		end)

		connections[#connections + 1] = track.Stopped:Connect(function()
			if fallbackTime <= 0 then
				trigger()
			end
		end)

		if fallbackTime > 0 then
			task.delay(math.max(0, fallbackTime - track.TimePosition), trigger)
		elseif not track.IsPlaying then
			trigger()
		end
		return
	end

	if fallbackTime > 0 then
		task.delay(fallbackTime, trigger)
	else
		trigger()
	end
end

function MoguClient:ScheduleBurrowMovementCue(targetPlayer, burrowState, startPosition, abilityConfig)
	local stageConfig = getAnimationStageConfig("Start", abilityConfig)
	local fallbackTime = getMovementCueFallbackTime(stageConfig)
	local token = {}
	local connections = {}

	burrowState.MovementCueToken = token
	burrowState.MovementCueConnections = connections

	local function trigger()
		if self.burrowStates[targetPlayer] ~= burrowState or burrowState.MovementCueToken ~= token then
			return
		end

		self:TriggerBurrowMovementCue(targetPlayer, burrowState, startPosition, abilityConfig)
	end

	local animationState = burrowState.AnimationState
	local track = type(animationState) == "table" and animationState.Track or nil
	if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		local markerNames = getMovementCueMarkerNames(stageConfig)
		for _, markerName in ipairs(markerNames) do
			local ok, connection = pcall(function()
				return track:GetMarkerReachedSignal(markerName):Connect(trigger)
			end)
			if ok and typeof(connection) == "RBXScriptConnection" then
				connections[#connections + 1] = connection
			end
		end

		connections[#connections + 1] = track.KeyframeReached:Connect(function(keyframeName)
			for _, markerName in ipairs(markerNames) do
				if keyframeName == markerName then
					trigger()
					return
				end
			end
		end)

		connections[#connections + 1] = track.Stopped:Connect(trigger)

		if fallbackTime > 0 then
			task.delay(math.max(0, fallbackTime - track.TimePosition), trigger)
		elseif not track.IsPlaying then
			trigger()
		end
		return
	end

	if fallbackTime > 0 then
		task.delay(fallbackTime, trigger)
	else
		trigger()
	end
end

function MoguClient:ClearConceal(targetPlayer)
	local concealState = self.concealStates[targetPlayer]
	if not concealState then
		return
	end

	self.concealStates[targetPlayer] = nil
	for part, previousTransparency in pairs(concealState.PreviousByPart) do
		if part and part.Parent then
			part.LocalTransparencyModifier = previousTransparency
		end
	end
	for part, previousCanCollide in pairs(concealState.PreviousCanCollideByPart or {}) do
		if part and part.Parent then
			part.CanCollide = previousCanCollide
		end
	end
	for surfaceVisual, previousTransparency in pairs(concealState.PreviousBySurfaceVisual or {}) do
		if surfaceVisual and surfaceVisual.Parent then
			surfaceVisual.Transparency = previousTransparency
		end
	end
	for gui, previousEnabled in pairs(concealState.PreviousGuiEnabled or {}) do
		if gui and gui.Parent then
			gui.Enabled = previousEnabled
		end
	end
	for humanoid, previousDisplayDistanceType in pairs(concealState.PreviousHumanoidDisplay or {}) do
		if humanoid and humanoid.Parent then
			humanoid.DisplayDistanceType = previousDisplayDistanceType
		end
	end
end

function MoguClient:GetLocalBurrowState()
	return self.burrowStates[self.player]
end

function MoguClient:RequestSurface(_reason)
	local burrowState = self:GetLocalBurrowState()
	if not burrowState or burrowState.SurfaceRequested or typeof(self.requestAbility) ~= "function" then
		return false
	end

	local rootPart = self.getLocalRootPart()
	burrowState.Direction = self:GetBurrowSurfaceDirection(rootPart, burrowState.Direction)
	burrowState.SurfaceRequested = true
	self.requestAbility(ABILITY_NAME, {
		Direction = burrowState.Direction,
	})
	return true
end

function MoguClient:StartBurrow(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	local abilityConfig = getAbilityConfig()
	local pendingFeedback = if targetPlayer == self.player then self.pendingBurrowFeedback else nil
	if pendingFeedback then
		self.pendingBurrowFeedback = nil
		if self.diagnostics then
			self.diagnostics.LastStartInputToAuthorizedMs = (os.clock() - pendingFeedback.RequestedAt) * 1000
		end
	end

	local duration = math.max(0.5, tonumber(payload.Duration) or MoguBurrowShared.GetBurrowDuration(abilityConfig))
	local startedAt = tonumber(payload.StartedAt) or Workspace:GetServerTimeNow()
	local burrowState = {
		StartedAt = startedAt,
		EndTime = tonumber(payload.EndTime) or (startedAt + duration),
		Duration = duration,
		MoveSpeed = math.max(0, tonumber(payload.MoveSpeed) or MoguBurrowShared.GetMoveSpeed(abilityConfig)),
		TrailInterval = math.max(0.05, tonumber(payload.TrailInterval) or MoguBurrowShared.GetTrailInterval(abilityConfig)),
		LastTrailAt = 0,
		Direction = resolvePlanarDirection(payload.Direction, getRootPart(targetPlayer) and getRootPart(targetPlayer).CFrame.LookVector or nil),
		SurfaceRequested = false,
		EntryBurstRadius = math.max(0.5, tonumber(payload.EntryBurstRadius) or MoguBurrowShared.GetEntryBurstRadius(abilityConfig)),
		ResolveBurstRadius = math.max(0.5, tonumber(payload.ResolveBurstRadius) or MoguBurrowShared.GetResolveBurstRadius(abilityConfig)),
		ConcealTransparency = math.clamp(
			tonumber(payload.ConcealTransparency) or MoguBurrowShared.GetConcealTransparency(abilityConfig),
			0,
			1
		),
		ConcealDelay = math.max(0, tonumber(getAnimationStageConfig("Start", abilityConfig).ConcealDelay) or 0),
		IsLocal = targetPlayer == self.player,
		EntryCueTriggered = pendingFeedback and pendingFeedback.EntryCueTriggered == true or false,
	}

	local startPosition = payload.StartPosition or (getRootPart(targetPlayer) and getRootPart(targetPlayer).Position)
	local shouldRequestSurfaceImmediately = false
	if burrowState.IsLocal then
		local character = getCharacter(self.player)
		local rootPart = self.getLocalRootPart()
		if character and rootPart then
			local resolvedSurfacePosition, hasSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
				character,
				rootPart,
				startPosition or rootPart.Position,
				abilityConfig,
				typeof(startPosition) == "Vector3" and startPosition or nil,
				{ FastSample = true }
			)
			burrowState.SurfaceRootPosition = resolvedSurfacePosition
				or (pendingFeedback and pendingFeedback.SurfaceRootPosition)
			burrowState.LastSurfaceProbeAt = os.clock()
			burrowState.LastSurfaceProbePosition = burrowState.SurfaceRootPosition
			burrowState.LastSurfaceProbeHadSurface = hasSurface
			if not hasSurface and typeof(burrowState.SurfaceRootPosition) ~= "Vector3" then
				shouldRequestSurfaceImmediately = true
			end
		end
	end

	if burrowState.IsLocal then
		local humanoid = self.getHumanoid()
		if humanoid then
			burrowState.OriginalAutoRotate = humanoid.AutoRotate
			burrowState.OriginalWalkSpeed = humanoid.WalkSpeed
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = 0
		end
	end

	self.burrowStates[targetPlayer] = burrowState
	if shouldRequestSurfaceImmediately then
		self:RequestSurface(SURFACE_REASON_SURFACE_LOST)
	end

	if burrowState.IsLocal then
		local character = getCharacter(self.player)
		local rootPart = self.getLocalRootPart()
		local pivotPosition = burrowState.SurfaceRootPosition
			or (typeof(startPosition) == "Vector3" and startPosition)
			or (rootPart and rootPart.Position)
		if character and rootPart and typeof(pivotPosition) == "Vector3" then
			self:RecordPivotWrite(pivotCharacterToRootPosition(character, rootPart, pivotPosition, burrowState.Direction, burrowState))
			zeroRootVelocity(rootPart, true)
		end
	end

	burrowState.AnimationState = pendingFeedback and pendingFeedback.AnimationState
		or self.animationController:PlayStart(targetPlayer, abilityConfig)

	if not burrowState.EntryCueTriggered then
		self:ScheduleBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
	end
	self:ScheduleBurrowMovementCue(targetPlayer, burrowState, startPosition, abilityConfig)
end

function MoguClient:StopBurrow(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	payload = payload or {}
	local burrowState = self.burrowStates[targetPlayer]
	local abilityConfig = getAbilityConfig()
	local visualRiseDuration = getVisualRiseDuration(abilityConfig)
	local backJerkDistance = getResolveBackJerkDistance(abilityConfig)
	local backJerkDuration = if backJerkDistance > 0 then getResolveBackJerkDuration(abilityConfig) else 0
	local surfaceLockDuration = math.max(getResolveSurfaceLockDuration(abilityConfig), visualRiseDuration, backJerkDuration)
	local facingLockDuration = getResolveFacingLockDuration(abilityConfig)
	local fallbackRootPart = getRootPart(targetPlayer)
	local resolveDirection = resolvePlanarDirection(
		payload.Direction,
		(burrowState and burrowState.Direction) or (fallbackRootPart and fallbackRootPart.CFrame.LookVector or nil)
	)
	local localHumanoid = nil
	local originalAutoRotate = nil
	if targetPlayer == self.player and self.diagnostics then
		self.diagnostics.LastResolveCorrectionDistance = math.max(0, tonumber(payload.ResolveCorrectionDistance) or 0)
	end
	self.burrowStates[targetPlayer] = nil
	clearBurrowCueState(burrowState)
	self.animationController:StopAnimation(burrowState and burrowState.AnimationState, "resolve_transition")

	local clampedResolvePosition = nil
	local resolveVfxPosition = nil
	if targetPlayer == self.player then
		local humanoid = self.getHumanoid()
		if humanoid and burrowState then
			localHumanoid = humanoid
			originalAutoRotate = burrowState.OriginalAutoRotate
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = burrowState.OriginalWalkSpeed or humanoid.WalkSpeed
		end

		local character = getCharacter(self.player)
		local rootPart = self.getLocalRootPart()
		if character and rootPart then
			local payloadSurfacePosition = typeof(payload.ActualEndPosition) == "Vector3" and payload.ActualEndPosition
				or nil
			local surfacePosition = payloadSurfacePosition or rootPart.Position
			local fallbackSurfacePosition = (burrowState and burrowState.SurfaceRootPosition) or payloadSurfacePosition
			local resolvedSurfacePosition = select(
				1,
				MoguBurrowShared.ResolveSurfaceRootPosition(
					character,
					rootPart,
					surfacePosition,
					abilityConfig,
					fallbackSurfacePosition
				)
			)
			if resolvedSurfacePosition then
				clampedResolvePosition = resolvedSurfacePosition
				local resolveAnimationPosition =
					getResolveAnimationPosition(resolvedSurfacePosition, resolveDirection, rootPart, abilityConfig)
				resolveVfxPosition =
					getResolveVfxPosition(resolveAnimationPosition, resolveDirection, rootPart, abilityConfig)
				self:RecordPivotWrite(
					pivotCharacterToRootPosition(
						character,
						rootPart,
						resolveAnimationPosition,
						resolveDirection,
						burrowState
					)
				)
				lockCharacterToSurface(
					character,
					rootPart,
					resolveAnimationPosition,
					resolveDirection,
					abilityConfig,
					surfaceLockDuration,
					backJerkDistance,
					backJerkDuration,
					burrowState,
					function()
						self:RecordPivotWrite(true)
					end
				)
				keepFacingDuringResolve(
					character,
					rootPart,
					resolveDirection,
					math.max(0, facingLockDuration - surfaceLockDuration),
					surfaceLockDuration,
					burrowState,
					function()
						self:RecordPivotWrite(true)
					end
				)
			else
				resolveVfxPosition = getResolveVfxPosition(rootPart.Position, resolveDirection, rootPart, abilityConfig)
				self:RecordPivotWrite(pivotCharacterToRootPosition(character, rootPart, rootPart.Position, resolveDirection, burrowState))
				keepFacingDuringResolve(
					character,
					rootPart,
					resolveDirection,
					facingLockDuration,
					0,
					burrowState,
					function()
						self:RecordPivotWrite(true)
					end
				)
			end
			zeroRootVelocity(rootPart, true)
		end
	else
		local character = getCharacter(targetPlayer)
		local rootPart = fallbackRootPart
		if character and rootPart then
			local surfacePosition = if typeof(payload.ActualEndPosition) == "Vector3"
				then payload.ActualEndPosition
				else rootPart.Position
			local resolveAnimationPosition =
				getResolveAnimationPosition(surfacePosition, resolveDirection, rootPart, abilityConfig)
			resolveVfxPosition = getResolveVfxPosition(resolveAnimationPosition, resolveDirection, rootPart, abilityConfig)
			pivotCharacterToRootPosition(character, rootPart, resolveAnimationPosition, resolveDirection)
			keepFacingDuringResolve(character, rootPart, resolveDirection, facingLockDuration)
			zeroRootVelocity(rootPart, true, false)
		end
	end

	local resolveAnimationState = self.animationController:PlayResolve(targetPlayer, abilityConfig)
	if targetPlayer == self.player and localHumanoid then
		restoreAutoRotateAfterResolve(localHumanoid, originalAutoRotate, resolveAnimationState, facingLockDuration)
	end

	self:SnapVisualBurrowOffset(targetPlayer)
	self:ClearVisualBurrowOffset(targetPlayer, true, visualRiseDuration, function()
		self:ClearConceal(targetPlayer)
	end)

	local resolvePosition = resolveVfxPosition
		or clampedResolvePosition
		or (typeof(payload.ActualEndPosition) == "Vector3" and payload.ActualEndPosition)
		or (getRootPart(targetPlayer) and getRootPart(targetPlayer).Position)
	if not self.vfxController:PlayResolve(resolvePosition, resolveDirection, abilityConfig) then
		createBurst(
			resolvePosition,
			(burrowState and burrowState.ResolveBurstRadius)
				or payload.ResolveBurstRadius
				or MoguBurrowShared.GetResolveBurstRadius(abilityConfig),
			true
		)
	end
end

function MoguClient:HandleInputBegan(input, gameProcessed)
	local burrowState = self:GetLocalBurrowState()
	if burrowState and input and input.KeyCode == Enum.KeyCode.Q and not gameProcessed then
		self:RequestSurface(SURFACE_REASON_MANUAL_TOGGLE)
		return true
	end

	return self:SetBurrowInputKeyState(input and input.KeyCode, true)
end

function MoguClient:HandleInputEnded(input)
	return self:SetBurrowInputKeyState(input and input.KeyCode, false)
end

function MoguClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName ~= ABILITY_NAME then
		if typeof(fallbackBuilder) == "function" then
			return fallbackBuilder()
		end
		return nil
	end

	local rootPart = self.getLocalRootPart()
	if not rootPart then
		return nil
	end

	local burrowState = self:GetLocalBurrowState()
	if burrowState then
		return nil
	end

	local direction = self:GetBurrowActivationDirection(rootPart)
	self:BeginLocalStartFeedback(direction)
	return {
		Direction = direction,
	}
end

function MoguClient:BuildRequestPayload(abilityName, _abilityEntry, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return self:BeginPredictedRequest(abilityName)
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function MoguClient:UpdateLocalBurrowState(burrowState, dt, now)
	local character = getCharacter(self.player)
	local rootPart = self.getLocalRootPart()
	local humanoid = self.getHumanoid()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.Jump = false

	local abilityConfig = getAbilityConfig()
	local localNow = os.clock()
	local currentSurfacePosition = burrowState.SurfaceRootPosition
	if typeof(currentSurfacePosition) ~= "Vector3" then
		local resolvedSurfacePosition, hasSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
			character,
			rootPart,
			rootPart.Position,
			abilityConfig,
			rootPart.Position,
			{ FastSample = true }
		)
		currentSurfacePosition = resolvedSurfacePosition
		burrowState.LastSurfaceProbeAt = localNow
		burrowState.LastSurfaceProbePosition = resolvedSurfacePosition or rootPart.Position
		burrowState.LastSurfaceProbeHadSurface = hasSurface
	end
	if typeof(currentSurfacePosition) ~= "Vector3" then
		self:RequestSurface(SURFACE_REASON_SURFACE_LOST)
		zeroRootVelocity(rootPart, false)
		return
	end
	burrowState.SurfaceRootPosition = currentSurfacePosition

	if now >= burrowState.EndTime and not burrowState.SurfaceRequested then
		self:RequestSurface(SURFACE_REASON_DURATION_ELAPSED)
	end

	if burrowState.SurfaceRequested then
		self:RecordPivotWrite(pivotCharacterToRootPosition(character, rootPart, currentSurfacePosition, burrowState.Direction, burrowState))
		zeroRootVelocity(rootPart, false)
		return
	end

	if not burrowState.MovementCueTriggered then
		self:RecordPivotWrite(pivotCharacterToRootPosition(character, rootPart, currentSurfacePosition, burrowState.Direction, burrowState))
		zeroRootVelocity(rootPart, false)
		return
	end

	local desiredDirection = self:GetCameraRelativeBurrowDirection(rootPart)
	local targetPlanarPosition = currentSurfacePosition
	local movementDistance = 0
	if desiredDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		movementDistance = burrowState.MoveSpeed * math.max(0, dt or 0)
		targetPlanarPosition = currentSurfacePosition + (desiredDirection.Unit * movementDistance)
	end

	local resolvedSurfacePosition = targetPlanarPosition
	local hasTargetSurface = false
	local shouldProbeTarget = movementDistance > MIN_TARGET_PROBE_DISTANCE
	if shouldProbeTarget then
		local lastProbePosition = burrowState.LastSurfaceProbePosition
		local distanceFromLastProbe = if typeof(lastProbePosition) == "Vector3"
			then (targetPlanarPosition - lastProbePosition).Magnitude
			else math.huge
		shouldProbeTarget = localNow >= ((burrowState.LastSurfaceProbeAt or 0) + SURFACE_PROBE_INTERVAL)
			or distanceFromLastProbe >= SURFACE_REPROBE_DISTANCE
			or burrowState.LastSurfaceProbeHadSurface ~= true
	end

	if shouldProbeTarget then
		resolvedSurfacePosition, hasTargetSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
			character,
			rootPart,
			targetPlanarPosition,
			abilityConfig,
			currentSurfacePosition,
			{ FastSample = true }
		)
		burrowState.LastSurfaceProbeAt = localNow
		burrowState.LastSurfaceProbePosition = targetPlanarPosition
		burrowState.LastSurfaceProbeHadSurface = hasTargetSurface
		if not resolvedSurfacePosition then
			self:RequestSurface(SURFACE_REASON_SURFACE_LOST)
			zeroRootVelocity(rootPart, false)
			return
		end
	elseif movementDistance > MIN_TARGET_PROBE_DISTANCE then
		resolvedSurfacePosition = Vector3.new(targetPlanarPosition.X, currentSurfacePosition.Y, targetPlanarPosition.Z)
		hasTargetSurface = true
	else
		resolvedSurfacePosition = currentSurfacePosition
		hasTargetSurface = burrowState.LastSurfaceProbeHadSurface == true
	end
	if desiredDirection.Magnitude > MIN_DIRECTION_MAGNITUDE and hasTargetSurface then
		burrowState.Direction = desiredDirection.Unit
	end

	burrowState.SurfaceRootPosition = if hasTargetSurface then resolvedSurfacePosition else currentSurfacePosition
	self:RecordPivotWrite(
		pivotCharacterToRootPosition(character, rootPart, burrowState.SurfaceRootPosition, burrowState.Direction, burrowState)
	)
	zeroRootVelocity(rootPart, false)
end

function MoguClient:UpdateTrailState(targetPlayer, burrowState, now)
	if not burrowState or not burrowState.MovementCueTriggered or now < burrowState.LastTrailAt + burrowState.TrailInterval then
		return
	end

	local rootPart = getRootPart(targetPlayer)
	if not rootPart then
		return
	end

	burrowState.LastTrailAt = now
	if not self.vfxController:PlayTrail(rootPart.Position, burrowState.Direction, getAbilityConfig()) then
		if createTrailPulse(rootPart.Position, tonumber(getAbilityConfig().TrailWidth) or 2.6) and self.diagnostics then
			self.diagnostics.TrailPulseCount += 1
		end
	end
end

function MoguClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= ABILITY_NAME then
		return false
	end

	payload = payload or {}
	local phase = typeof(payload.Phase) == "string" and payload.Phase or PHASE_START
	if phase == PHASE_START then
		self.playOptionalEffect(targetPlayer, FRUIT_NAME, abilityName, payload)
		self:StartBurrow(targetPlayer, payload)
		return true
	end

	if phase == PHASE_RESOLVE then
		self.playOptionalEffect(targetPlayer, FRUIT_NAME, abilityName, payload)
		self:StopBurrow(targetPlayer, payload)
		return true
	end

	return false
end

function MoguClient:HandleStateEvent(eventName, abilityName)
	if abilityName == ABILITY_NAME and eventName == "Denied" then
		self:CancelLocalStartFeedback("server_denied")
		return true
	end

	return false
end

function MoguClient:Update(dt)
	local now = Workspace:GetServerTimeNow()
	for targetPlayer, burrowState in pairs(self.burrowStates) do
		if now > (burrowState.EndTime + MoguBurrowShared.GetSurfaceResolveGrace(getAbilityConfig())) and not burrowState.IsLocal then
			self:StopBurrow(targetPlayer, {
				ActualEndPosition = getRootPart(targetPlayer) and getRootPart(targetPlayer).Position or nil,
				ResolveBurstRadius = burrowState.ResolveBurstRadius,
			})
		else
			self:UpdateTrailState(targetPlayer, burrowState, now)
			if burrowState.IsLocal then
				self:UpdateLocalBurrowState(burrowState, dt or 0, now)
			end
		end
	end
	self:PublishDiagnostics(false)
end

function MoguClient:HandleEquipped()
	return false
end

function MoguClient:HandleUnequipped()
	self:HandleCharacterRemoving()
	return false
end

function MoguClient:HandleCharacterRemoving()
	self:CancelLocalStartFeedback("character_removing")
	local localBurrowState = self.burrowStates[self.player]
	if localBurrowState then
		local humanoid = self.getHumanoid()
		if humanoid then
			humanoid.AutoRotate = localBurrowState.OriginalAutoRotate ~= false
			humanoid.WalkSpeed = localBurrowState.OriginalWalkSpeed or humanoid.WalkSpeed
		end
	end

	for targetPlayer in pairs(self.burrowStates) do
		clearBurrowCueState(self.burrowStates[targetPlayer])
		self.animationController:StopAnimation(self.burrowStates[targetPlayer].AnimationState, "character_removing")
		self.burrowStates[targetPlayer] = nil
		self:ClearVisualBurrowOffset(targetPlayer, false)
		self:ClearConceal(targetPlayer)
	end
	for targetPlayer in pairs(self.visualBurrowStates) do
		self:ClearVisualBurrowOffset(targetPlayer, false)
	end
	self.vfxController:HandleCharacterRemoving()
	cleanupTrailPulsePool()
	self:RecordCleanup()
	self:PublishDiagnostics(true)

	self.burrowInputState.Forward = false
	self.burrowInputState.Backward = false
	self.burrowInputState.Left = false
	self.burrowInputState.Right = false
end

function MoguClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer == self.player then
		self:CancelLocalStartFeedback("player_removing")
	end
	clearBurrowCueState(self.burrowStates[leavingPlayer])
	self.animationController:StopAnimation(self.burrowStates[leavingPlayer] and self.burrowStates[leavingPlayer].AnimationState, "player_removing")
	self.burrowStates[leavingPlayer] = nil
	self:ClearVisualBurrowOffset(leavingPlayer, false)
	self:ClearConceal(leavingPlayer)
	self.vfxController:HandlePlayerRemoving(leavingPlayer)
	self:RecordCleanup()
	self:PublishDiagnostics(true)
end

return MoguClient
