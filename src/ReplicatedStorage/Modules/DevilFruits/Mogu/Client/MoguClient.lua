local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
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
local SURFACE_REASON_STARTUP_FAILED = "startup_failed"
local MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE = "MoguMovementLockUntil"
local STATE_STARTUP_SURFACE = "StartupSurface"
local STATE_BURIED_ACTIVE = "BuriedActive"
local STATE_RESOLVE_IN_PROGRESS = "ResolveInProgress"
local STATE_FINISHED = "Finished"
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local TRAIL_COLOR = Color3.fromRGB(122, 95, 63)
local TRAIL_ACCENT_COLOR = Color3.fromRGB(166, 136, 97)
local BURST_COLOR = Color3.fromRGB(214, 194, 159)
local FLAT_RING_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local DEFAULT_ENTRY_CUE_FALLBACK_TIME = 0.24
local DEFAULT_MOVEMENT_CUE_FALLBACK_TIME = 0.42
local DEFAULT_VISUAL_SINK_DURATION = 0.24
local DEFAULT_VISUAL_SINK_EASING_STYLE = Enum.EasingStyle.Sine
local DEFAULT_VISUAL_SINK_EASING_DIRECTION = Enum.EasingDirection.InOut
local DEFAULT_CAMERA_STABILIZATION_MODE = "SmoothOffset"
local DEFAULT_CAMERA_STABILIZATION_SMOOTH_TIME = 0.08
local DEFAULT_CAMERA_STABILIZATION_RESTORE_TIME = 0.14
local DEFAULT_BURROW_START_SINK_DELAY = 0.4
local DEFAULT_HIGH_SPEED_SERVER_CONFIRMED_START_SPEED = 96
local DEFAULT_BURROW_GROUND_CONTACT_TOLERANCE = 0.6
local DEFAULT_STARTUP_ACTIVATION_TIMEOUT = 1.6
local DEFAULT_VISUAL_RISE_DURATION = 0.18
local DEFAULT_RESOLVE_REVEAL_DELAY = 0.08
local DEFAULT_RESOLVE_SURFACE_LOCK_DURATION = 0.28
local DEFAULT_ENTRY_VFX_FORWARD_OFFSET = 1.15
local DEFAULT_RESOLVE_ANIMATION_BACK_OFFSET = 0.85
local DEFAULT_RESOLVE_BACK_JERK_DISTANCE = 0.45
local DEFAULT_RESOLVE_BACK_JERK_DURATION = 0.08
local DEFAULT_RESOLVE_VFX_FORWARD_OFFSET = 0
local DEFAULT_RESOLVE_FACING_LOCK_DURATION = 0.6
local DEFAULT_FALLBACK_WALK_SPEED = 16
local USE_VISUAL_ONLY_BURROW_ROOT = true
local SURFACE_PROBE_INTERVAL = 1 / 24
local SURFACE_REPROBE_DISTANCE = 0.75
local MIN_TARGET_PROBE_DISTANCE = 0.035
local CONCEAL_REPAIR_INTERVAL = 0.25
local MIN_PIVOT_POSITION_DELTA = 0.03
local MIN_PIVOT_DIRECTION_DOT = 0.9995
local ZERO_VELOCITY_EPSILON = 0.025
local PENDING_START_FEEDBACK_TIMEOUT = 2
local GROUND_REQUIRED_FEEDBACK_COOLDOWN = 0.85
local GROUND_REQUIRED_MESSAGE = "You need to be on the ground to burrow."
local TRAIL_PULSE_POOL_LIMIT = 48
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.5
local WARN_COOLDOWN = 3
local NIL_DIAGNOSTIC_ATTRIBUTE_VALUE = {}
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
local VISUAL_SINK_EASING_STYLES = {
	back = Enum.EasingStyle.Back,
	bounce = Enum.EasingStyle.Bounce,
	circular = Enum.EasingStyle.Circular,
	cubic = Enum.EasingStyle.Cubic,
	elastic = Enum.EasingStyle.Elastic,
	exponential = Enum.EasingStyle.Exponential,
	linear = Enum.EasingStyle.Linear,
	quad = Enum.EasingStyle.Quad,
	quadratic = Enum.EasingStyle.Quad,
	quart = Enum.EasingStyle.Quart,
	quartic = Enum.EasingStyle.Quart,
	quint = Enum.EasingStyle.Quint,
	quintic = Enum.EasingStyle.Quint,
	sine = Enum.EasingStyle.Sine,
}
local VISUAL_SINK_EASING_DIRECTIONS = {
	["in"] = Enum.EasingDirection.In,
	inout = Enum.EasingDirection.InOut,
	out = Enum.EasingDirection.Out,
}
local CAMERA_STABILIZATION_MODES = {
	none = "None",
	off = "None",
	falsevalue = "None",
	instant = "Instant",
	preserve = "Instant",
	preserveworld = "Instant",
	smooth = "SmoothOffset",
	smoothoffset = "SmoothOffset",
}

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguClient:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU CLIENT][WARN] " .. message, ...))
end

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguClient:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU CLIENT] " .. message, ...))
end

local function getAbilityConfig()
	return DevilFruitConfig.GetAbility(FRUIT_NAME, ABILITY_NAME) or {}
end

local function getAnimationStageConfig(stageKey, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and animationConfig[stageKey] or {}
end

local function normalizeConfigKey(value)
	if typeof(value) ~= "string" then
		return nil
	end

	return string.lower((string.gsub(value, "[^%w]", "")))
end

local function getConfiguredEnumItem(configuredValue, lookup, fallback)
	if typeof(configuredValue) == "EnumItem" then
		return configuredValue
	end

	local key = normalizeConfigKey(configuredValue)
	if key and lookup[key] then
		return lookup[key]
	end

	return fallback
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

local function getBuriedRootDepth(abilityConfig)
	return math.max(
		0,
		tonumber(abilityConfig and abilityConfig.BuriedRootDepth)
			or tonumber(abilityConfig and abilityConfig.BurrowRootDepth)
			or getVisualSinkDepth(abilityConfig)
	)
end

local function getBuriedRootPosition(surfaceRootPosition, abilityConfig)
	if typeof(surfaceRootPosition) ~= "Vector3" then
		return nil
	end

	local buriedDepth = getBuriedRootDepth(abilityConfig)
	if buriedDepth <= 0 then
		return surfaceRootPosition
	end

	return surfaceRootPosition - Vector3.new(0, buriedDepth, 0)
end

local function shouldUseVisualOnlyBurrowRoot(burrowState)
	return USE_VISUAL_ONLY_BURROW_ROOT and type(burrowState) == "table"
end

local function shouldUseTrueBurrowRoot(_burrowState)
	return false
end

local function getGameplayRootPosition(burrowState, surfaceRootPosition, abilityConfig)
	if shouldUseVisualOnlyBurrowRoot(burrowState) then
		return surfaceRootPosition
	end

	return getBuriedRootPosition(surfaceRootPosition, abilityConfig)
end

local function getBurrowStatePhase(burrowState)
	return type(burrowState) == "table" and burrowState.StatePhase or "<nil>"
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

local function getStartupActivationTimeout(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	local configured = startConfig.StartupActivationTimeout
	if configured == nil then
		configured = startConfig.BurrowStartupTimeout
	end
	if configured == nil and type(abilityConfig) == "table" then
		configured = abilityConfig.StartupActivationTimeout
	end
	if configured == false then
		return 0
	end

	local fallbackTime = getMovementCueFallbackTime(startConfig) + getVisualSinkDuration(abilityConfig) + 0.5
	return math.max(
		0,
		tonumber(configured) or math.max(DEFAULT_STARTUP_ACTIVATION_TIMEOUT, fallbackTime)
	)
end

local function getVisualSinkEasingStyle(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return getConfiguredEnumItem(
		startConfig.VisualSinkEasingStyle or startConfig.SinkEasingStyle or abilityConfig and abilityConfig.VisualSinkEasingStyle,
		VISUAL_SINK_EASING_STYLES,
		DEFAULT_VISUAL_SINK_EASING_STYLE
	)
end

local function getVisualSinkEasingDirection(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return getConfiguredEnumItem(
		startConfig.VisualSinkEasingDirection
			or startConfig.VisualSinkEaseDirection
			or startConfig.SinkEasingDirection
			or abilityConfig and abilityConfig.VisualSinkEasingDirection,
		VISUAL_SINK_EASING_DIRECTIONS,
		DEFAULT_VISUAL_SINK_EASING_DIRECTION
	)
end

local function getBurrowStartSinkDelay(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return math.max(
		0,
		tonumber(startConfig.BurrowStartSinkDelay)
			or tonumber(startConfig.BurrowSinkDelay)
			or tonumber(abilityConfig and abilityConfig.BurrowStartSinkDelay)
			or tonumber(abilityConfig and abilityConfig.BurrowSinkDelay)
			or DEFAULT_BURROW_START_SINK_DELAY
	)
end

local function shouldStabilizeCameraDuringSink(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	local configured = startConfig.StabilizeCameraDuringSink
	if configured == nil and type(abilityConfig) == "table" then
		configured = abilityConfig.StabilizeCameraDuringSink
	end
	if configured == nil then
		return true
	end
	return configured ~= false
end

local function getCameraStabilizationMode(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	local configured = startConfig.CameraStabilizationMode
	if configured == nil and type(abilityConfig) == "table" then
		configured = abilityConfig.CameraStabilizationMode
	end
	if configured == false then
		return nil
	end
	local mode = getConfiguredEnumItem(configured, CAMERA_STABILIZATION_MODES, DEFAULT_CAMERA_STABILIZATION_MODE)
	if mode == "None" then
		return nil
	end
	return mode
end

local function getCameraStabilizationSmoothTime(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return math.max(
		0,
		tonumber(startConfig.CameraStabilizationSmoothTime)
			or tonumber(startConfig.CameraStabilizationTweenTime)
			or tonumber(abilityConfig and abilityConfig.CameraStabilizationSmoothTime)
			or DEFAULT_CAMERA_STABILIZATION_SMOOTH_TIME
	)
end

local function getCameraStabilizationRestoreTime(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return math.max(
		0,
		tonumber(startConfig.CameraStabilizationRestoreTime)
			or tonumber(startConfig.CameraRestoreTime)
			or tonumber(abilityConfig and abilityConfig.CameraStabilizationRestoreTime)
			or DEFAULT_CAMERA_STABILIZATION_RESTORE_TIME
	)
end

local function shouldRequireGroundedBurrowStart(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	local configured = startConfig.RequireGroundedStart
	if configured == nil and type(abilityConfig) == "table" then
		configured = abilityConfig.RequireGroundedStart
	end
	if configured == nil then
		configured = startConfig.ForceFallBeforeBurrow
	end
	if configured == nil and type(abilityConfig) == "table" then
		configured = abilityConfig.ForceFallBeforeBurrow
	end
	return configured == true
end

local function getHighSpeedServerConfirmedStartSpeed(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	local configured = startConfig.HighSpeedServerConfirmedStartSpeed
	if configured == nil then
		configured = startConfig.ServerConfirmedStartSpeed
	end
	if configured == nil and type(abilityConfig) == "table" then
		configured = abilityConfig.HighSpeedServerConfirmedStartSpeed or abilityConfig.ServerConfirmedStartSpeed
	end
	if configured == false then
		return math.huge
	end

	return math.max(0, tonumber(configured) or DEFAULT_HIGH_SPEED_SERVER_CONFIRMED_START_SPEED)
end

local function getBurrowGroundContactTolerance(abilityConfig)
	local startConfig = getAnimationStageConfig("Start", abilityConfig)
	return math.max(
		0,
		tonumber(startConfig.BurrowGroundContactTolerance)
			or tonumber(startConfig.BurrowGroundContactDistance)
			or tonumber(abilityConfig and abilityConfig.BurrowGroundContactTolerance)
			or tonumber(abilityConfig and abilityConfig.BurrowGroundContactDistance)
			or DEFAULT_BURROW_GROUND_CONTACT_TOLERANCE
	)
end

local function getBurrowStartSinkRemaining(burrowState, abilityConfig)
	local sinkDelay = getBurrowStartSinkDelay(abilityConfig)
	if sinkDelay <= 0 then
		return 0
	end

	local localStartAt = type(burrowState) == "table" and tonumber(burrowState.LocalStartFeedbackAt) or nil
	if localStartAt then
		return math.max(0, sinkDelay - (os.clock() - localStartAt))
	end

	local startedAt = type(burrowState) == "table" and tonumber(burrowState.StartedAt) or nil
	if startedAt then
		return math.max(0, sinkDelay - (Workspace:GetServerTimeNow() - startedAt))
	end

	return sinkDelay
end

local function getBurrowSinkCompleteRemaining(burrowState, abilityConfig)
	local sinkStartRemaining = getBurrowStartSinkRemaining(burrowState, abilityConfig)
	local sinkDuration = getVisualSinkDuration(abilityConfig)
	if sinkStartRemaining > 0 then
		return sinkStartRemaining + sinkDuration
	end

	if type(burrowState) ~= "table" then
		return 0
	end

	if burrowState.StartupVisualSinkAttempted ~= true then
		return sinkDuration
	end

	if burrowState.StartupVisualSinkSucceeded ~= true then
		return 0
	end

	local startedAt = tonumber(burrowState.StartupVisualSinkStartedAt)
	if not startedAt then
		return 0
	end

	return math.max(0, sinkDuration - (os.clock() - startedAt))
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

local function getResolveRevealDelay(abilityConfig)
	local resolveConfig = getAnimationStageConfig("Resolve", abilityConfig)
	return math.max(
		0,
		tonumber(resolveConfig.RevealDelay)
			or tonumber(resolveConfig.JumpOutDelay)
			or tonumber(resolveConfig.ResolveRevealDelay)
			or tonumber(abilityConfig and abilityConfig.ResolveRevealDelay)
			or DEFAULT_RESOLVE_REVEAL_DELAY
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
	burrowState.EntryCueDelayToken = nil
	disconnectConnections(burrowState.EntryCueConnections)
	burrowState.EntryCueConnections = nil
end

local function clearMovementCueState(burrowState)
	if type(burrowState) ~= "table" then
		return
	end

	burrowState.MovementCueToken = nil
	burrowState.MovementCueWaitingForEntry = nil
	disconnectConnections(burrowState.MovementCueConnections)
	burrowState.MovementCueConnections = nil
end

local function clearBurrowCueState(burrowState)
	if type(burrowState) == "table" then
		burrowState.StartupVisualSinkToken = nil
		burrowState.RootTransitionDelayToken = nil
		burrowState.StartupWatchdogToken = nil
	end
	clearEntryCueState(burrowState)
	clearMovementCueState(burrowState)
end

local function clearBurrowLifecycleState(burrowState)
	if type(burrowState) ~= "table" then
		return
	end

	disconnectConnections(burrowState.CharacterConnections)
	burrowState.CharacterConnections = nil
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getRootPlanarSpeed(rootPart)
	if not rootPart then
		return 0
	end

	return getPlanarVector(rootPart.AssemblyLinearVelocity).Magnitude
end

local function shouldUseServerConfirmedBurrowStartup(rootPart, humanoid, abilityConfig)
	local threshold = getHighSpeedServerConfirmedStartSpeed(abilityConfig)
	local planarSpeed = getRootPlanarSpeed(rootPart)
	local walkSpeed = if humanoid then math.abs(tonumber(humanoid.WalkSpeed) or 0) else 0
	local effectiveSpeed = math.max(planarSpeed, walkSpeed)

	if threshold == math.huge then
		return false, effectiveSpeed, threshold, planarSpeed, walkSpeed
	end
	if threshold <= 0 then
		return true, effectiveSpeed, threshold, planarSpeed, walkSpeed
	end

	return effectiveSpeed >= threshold, effectiveSpeed, threshold, planarSpeed, walkSpeed
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

local function shouldSkipPivot(pivotState, rootPart, targetRootCFrame)
	if type(pivotState) ~= "table" or not rootPart or typeof(targetRootCFrame) ~= "CFrame" then
		return false
	end

	local lastRootCFrame = pivotState.LastPivotRootCFrame
	if typeof(lastRootCFrame) ~= "CFrame" then
		return false
	end

	local currentRootCFrame = rootPart.CFrame
	if
		(currentRootCFrame.Position - targetRootCFrame.Position).Magnitude > MIN_PIVOT_POSITION_DELTA
		or currentRootCFrame.LookVector:Dot(targetRootCFrame.LookVector) < MIN_PIVOT_DIRECTION_DOT
	then
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
	if shouldSkipPivot(pivotState, rootPart, targetRootCFrame) then
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

local function getHumanoidGroundState(humanoid)
	if not humanoid then
		return false, false, nil, nil
	end

	local state = humanoid:GetState()
	if state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.FallingDown
	then
		return true, true, state, humanoid.FloorMaterial
	end

	local floorMaterial = humanoid.FloorMaterial
	return false, floorMaterial == Enum.Material.Air, state, floorMaterial
end

local function isMoguMovementLockActive(player)
	if not player then
		return false
	end

	local movementLockUntil = player:GetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE)
	return typeof(movementLockUntil) == "number" and movementLockUntil > os.clock()
end

local function getFallbackWalkSpeed(player, humanoid)
	local hiddenStats = player and player:FindFirstChild("HiddenLeaderstats") or nil
	local speedValue = hiddenStats and hiddenStats:FindFirstChild("Speed") or nil
	local purchasedSpeed = speedValue and tonumber(speedValue.Value) or nil
	if purchasedSpeed then
		return math.max(DEFAULT_FALLBACK_WALK_SPEED, DEFAULT_FALLBACK_WALK_SPEED + purchasedSpeed)
	end

	local currentWalkSpeed = humanoid and tonumber(humanoid.WalkSpeed) or nil
	if currentWalkSpeed and currentWalkSpeed > 0 then
		return currentWalkSpeed
	end

	return DEFAULT_FALLBACK_WALK_SPEED
end

local function restorePositiveWalkSpeed(player, humanoid, originalWalkSpeed, reason)
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	if typeof(originalWalkSpeed) == "number" and originalWalkSpeed > 0 then
		humanoid.WalkSpeed = originalWalkSpeed
		return true
	end

	if typeof(originalWalkSpeed) == "number" then
		logWarn(
			"skipped zero walk speed restore player=%s reason=%s original=%.2f current=%.2f",
			player and player.Name or "<nil>",
			tostring(reason or "unknown"),
			originalWalkSpeed,
			humanoid.WalkSpeed
		)
	end

	local fallbackWalkSpeed = getFallbackWalkSpeed(player, humanoid)
	local function applyFallbackIfUnlocked(delayReason)
		if not humanoid.Parent or humanoid.Health <= 0 then
			return false
		end
		if humanoid.WalkSpeed > 0 or isMoguMovementLockActive(player) then
			return false
		end

		humanoid.WalkSpeed = fallbackWalkSpeed
		logWarn(
			"fallback walk speed restored player=%s reason=%s fallback=%.2f currentReason=%s",
			player and player.Name or "<nil>",
			tostring(reason or "unknown"),
			fallbackWalkSpeed,
			tostring(delayReason or "immediate")
		)
		return true
	end

	if applyFallbackIfUnlocked("immediate") then
		return true
	end

	task.delay(0.2, function()
		applyFallbackIfUnlocked("delayed")
	end)

	return false
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
	self.isAbilityLocallyReady = type(config.IsAbilityLocallyReady) == "function" and config.IsAbilityLocallyReady or function()
		return true
	end
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
	self.cameraRestoreTweens = setmetatable({}, { __mode = "k" })
	self.pendingBurrowFeedback = nil
	self.pendingServerConfirmedBurrowStart = nil
	self.lastGroundedRequiredFeedbackAt = 0
	self.diagnosticAttributeValues = {}
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

	local cachedValue = if value == nil then NIL_DIAGNOSTIC_ATTRIBUTE_VALUE else value
	local diagnosticAttributeValues = self.diagnosticAttributeValues
	if diagnosticAttributeValues and diagnosticAttributeValues[name] == cachedValue then
		return
	end
	if player:GetAttribute(name) == value then
		if diagnosticAttributeValues then
			diagnosticAttributeValues[name] = cachedValue
		end
		return
	end

	player:SetAttribute(name, value)
	if diagnosticAttributeValues then
		diagnosticAttributeValues[name] = cachedValue
	end
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

function MoguClient:SetBurrowStatePhase(targetPlayer, burrowState, phase, reason)
	if type(burrowState) ~= "table" or typeof(phase) ~= "string" or phase == "" then
		return false
	end

	local previousPhase = burrowState.StatePhase
	if previousPhase == phase then
		return false
	end

	burrowState.StatePhase = phase
	logInfo(
		"state transition player=%s %s -> %s reason=%s",
		targetPlayer and targetPlayer.Name or "<nil>",
		tostring(previousPhase or "<nil>"),
		phase,
		tostring(reason or "unspecified")
	)
	return true
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

function MoguClient:HasVisualBurrowOffset(targetPlayer)
	local visualState = self.visualBurrowStates[targetPlayer]
	if not visualState then
		return false
	end

	local motor = visualState.Motor
	local propertyName = visualState.PropertyName
	return motor ~= nil and motor.Parent ~= nil and typeof(propertyName) == "string"
end

function MoguClient:ApplyVisualBurrowOffset(targetPlayer, abilityConfig, options)
	local character = getCharacter(targetPlayer)
	local rootPart = getRootPart(targetPlayer)
	local motor, propertyName = findRootVisualMotor(character, rootPart)
	if not motor or typeof(propertyName) ~= "string" then
		logWarn(
			"visual motor missing player=%s hasCharacter=%s hasRoot=%s",
			targetPlayer and targetPlayer.Name or "<nil>",
			tostring(character ~= nil),
			tostring(rootPart ~= nil)
		)
		return false
	end

	self:ClearVisualBurrowOffset(targetPlayer, false)

	local originalCFrame = motor[propertyName]
	local depth = if type(options) == "table" and typeof(options.Depth) == "number"
		then math.max(0, options.Depth)
		else getVisualSinkDepth(abilityConfig)
	if depth <= 0 then
		logWarn("visual sink failed player=%s reason=invalid_depth depth=%s", targetPlayer.Name, tostring(depth))
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
		Completed = false,
		StartedAt = os.clock(),
		CompletedAt = nil,
	}
	self.visualBurrowStates[targetPlayer] = visualState

	local sinkDuration = if type(options) == "table" and typeof(options.Duration) == "number"
		then math.max(0, options.Duration)
		else getVisualSinkDuration(abilityConfig)
	if sinkDuration > 0 then
		local easingStyle = if type(options) == "table" and typeof(options.EasingStyle) == "EnumItem"
			then options.EasingStyle
			else getVisualSinkEasingStyle(abilityConfig)
		local easingDirection = if type(options) == "table" and typeof(options.EasingDirection) == "EnumItem"
			then options.EasingDirection
			else getVisualSinkEasingDirection(abilityConfig)
		local tween = TweenService:Create(
			motor,
			TweenInfo.new(sinkDuration, easingStyle, easingDirection),
			{ [propertyName] = targetCFrame }
		)
		visualState.Tween = tween
		local sinkToken = visualState.Token
		tween.Completed:Connect(function(playbackState)
			if self.visualBurrowStates[targetPlayer] ~= visualState or visualState.Token ~= sinkToken then
				return
			end

			visualState.Tween = nil
			if playbackState == Enum.PlaybackState.Completed then
				visualState.Completed = true
				visualState.CompletedAt = os.clock()
			end
		end)
		tween:Play()
	else
		motor[propertyName] = targetCFrame
		visualState.Completed = true
		visualState.CompletedAt = os.clock()
	end

	return true
end

function MoguClient:ApplyStartupVisualSink(targetPlayer, abilityConfig)
	local depth = getVisualSinkDepth(abilityConfig)
	local duration = getVisualSinkDuration(abilityConfig)
	if depth <= 0 then
		return false
	end

	local didStart = self:ApplyVisualBurrowOffset(targetPlayer, abilityConfig, {
		Depth = depth,
		Duration = duration,
	})
	logInfo(
		"startup visual sink started player=%s depth=%.2f duration=%.2f success=%s",
		targetPlayer.Name,
		depth,
		duration,
		tostring(didStart)
	)
	return didStart
end

function MoguClient:ScheduleStartupVisualSink(targetPlayer, burrowState, abilityConfig)
	if not targetPlayer or type(burrowState) ~= "table" or burrowState.StartupVisualSinkSucceeded == true then
		return false
	end

	local token = {}
	burrowState.StartupVisualSinkToken = token

	local function apply()
		local isPendingLocal = targetPlayer == self.player and self.pendingBurrowFeedback == burrowState
		local isActive = self.burrowStates[targetPlayer] == burrowState
		if not isPendingLocal and not isActive then
			return
		end
		if burrowState.StartupVisualSinkToken ~= token then
			return
		end

		burrowState.StartupVisualSinkToken = nil
		burrowState.StartupVisualSinkAttempted = true
		local didStart = self:ApplyStartupVisualSink(targetPlayer, abilityConfig)
		burrowState.StartupVisualSinkStartedAt = if didStart then os.clock() else nil
		burrowState.StartupVisualSinkSucceeded = didStart
	end

	local remainingDelay = getBurrowStartSinkRemaining(burrowState, abilityConfig)
	if remainingDelay > 0 then
		task.delay(remainingDelay, apply)
	else
		apply()
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
		visualState.Completed = true
		visualState.CompletedAt = os.clock()
		return true
	end

	return false
end

local function concealDescendant(descendant, concealState, transparency)
	if type(concealState) ~= "table" or concealState.VisualRestored == true then
		return false
	end

	local didWrite = false
	if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
		if concealState.PreviousByPart[descendant] == nil then
			concealState.PreviousByPart[descendant] = descendant.LocalTransparencyModifier
		end
		if concealState.PreviousCanCollideByPart[descendant] == nil then
			concealState.PreviousCanCollideByPart[descendant] = descendant.CanCollide
		end
		local targetTransparency = math.max(descendant.LocalTransparencyModifier, transparency)
		if descendant.LocalTransparencyModifier ~= targetTransparency then
			descendant.LocalTransparencyModifier = targetTransparency
			didWrite = true
		end
		if descendant.CanCollide then
			descendant.CanCollide = false
			didWrite = true
		end
	elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
		if concealState.PreviousBySurfaceVisual[descendant] == nil then
			concealState.PreviousBySurfaceVisual[descendant] = descendant.Transparency
		end
		local targetTransparency = math.max(descendant.Transparency, transparency)
		if descendant.Transparency ~= targetTransparency then
			descendant.Transparency = targetTransparency
			didWrite = true
		end
	elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
		if concealState.PreviousGuiEnabled[descendant] == nil then
			concealState.PreviousGuiEnabled[descendant] = descendant.Enabled
		end
		if descendant.Enabled then
			descendant.Enabled = false
			didWrite = true
		end
	elseif descendant:IsA("Humanoid") then
		if concealState.PreviousHumanoidDisplay[descendant] == nil then
			concealState.PreviousHumanoidDisplay[descendant] = descendant.DisplayDistanceType
		end
		if descendant.DisplayDistanceType ~= Enum.HumanoidDisplayDistanceType.None then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			didWrite = true
		end
	end

	return didWrite
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
	local concealState = {
		PreviousByPart = previousByPart,
		PreviousCanCollideByPart = previousCanCollideByPart,
		PreviousBySurfaceVisual = previousBySurfaceVisual,
		PreviousGuiEnabled = previousGuiEnabled,
		PreviousHumanoidDisplay = previousHumanoidDisplay,
		Transparency = transparency,
	}
	for _, descendant in ipairs(character:GetDescendants()) do
		concealDescendant(descendant, concealState, transparency)
	end
	concealState.DescendantAddedConnection = character.DescendantAdded:Connect(function(descendant)
		task.defer(function()
			if self.concealStates[targetPlayer] ~= concealState then
				return
			end

			if concealDescendant(descendant, concealState, transparency) then
				logInfo("active conceal repaired new descendant player=%s descendant=%s", targetPlayer.Name, descendant.Name)
			end
		end)
	end)

	self.concealStates[targetPlayer] = concealState
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

function MoguClient:CancelCameraRestoreTween(humanoid)
	if not humanoid or type(self.cameraRestoreTweens) ~= "table" then
		return false
	end

	local restoreTween = self.cameraRestoreTweens[humanoid]
	if restoreTween then
		restoreTween:Cancel()
		self.cameraRestoreTweens[humanoid] = nil
		return true
	end
	return false
end

function MoguClient:ApplyBurrowCameraStabilization(ownerState, humanoid, surfacePosition, buriedPosition, abilityConfig)
	if type(ownerState) ~= "table" or not humanoid or not shouldStabilizeCameraDuringSink(abilityConfig) then
		return false
	end
	local stabilizationMode = getCameraStabilizationMode(abilityConfig)
	if not stabilizationMode then
		return false
	end
	if typeof(surfacePosition) ~= "Vector3" or typeof(buriedPosition) ~= "Vector3" then
		return false
	end

	local compensation = math.max(0, surfacePosition.Y - buriedPosition.Y)
	if compensation <= 0 then
		return false
	end

	self:CancelCameraRestoreTween(humanoid)
	local cameraState = ownerState.CameraStabilizationState
	if type(cameraState) ~= "table" or cameraState.Humanoid ~= humanoid then
		if type(cameraState) == "table" and cameraState.Tween then
			cameraState.Tween:Cancel()
		end
		cameraState = {
			Humanoid = humanoid,
			BaseOffset = humanoid.CameraOffset,
			AppliedOffset = Vector3.zero,
			TargetOffset = Vector3.zero,
		}
		ownerState.CameraStabilizationState = cameraState
	end

	local baseOffset = if typeof(cameraState.BaseOffset) == "Vector3"
		then cameraState.BaseOffset
		else humanoid.CameraOffset - (
			if typeof(cameraState.AppliedOffset) == "Vector3" then cameraState.AppliedOffset else Vector3.zero
		)
	cameraState.BaseOffset = baseOffset

	local previousTargetOffset = if typeof(cameraState.TargetOffset) == "Vector3"
		then cameraState.TargetOffset
		else Vector3.zero
	local targetOffset = Vector3.new(0, compensation, 0)
	if cameraState.Active == true
		and (previousTargetOffset - targetOffset).Magnitude <= 0.01
	then
		return true
	end

	if cameraState.Tween then
		cameraState.Tween:Cancel()
		cameraState.Tween = nil
	end

	local smoothTime = getCameraStabilizationSmoothTime(abilityConfig)
	local targetCameraOffset = baseOffset + targetOffset
	local shouldLog = cameraState.Active ~= true or math.abs(previousTargetOffset.Y - compensation) > 0.05
	if stabilizationMode == "SmoothOffset" and smoothTime > 0 then
		local tween = TweenService:Create(
			humanoid,
			TweenInfo.new(smoothTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ CameraOffset = targetCameraOffset }
		)
		cameraState.Tween = tween
		tween.Completed:Connect(function()
			if ownerState.CameraStabilizationState == cameraState then
				cameraState.Tween = nil
			end
		end)
		tween:Play()
	else
		humanoid.CameraOffset = targetCameraOffset
	end

	cameraState.AppliedOffset = targetOffset
	cameraState.TargetOffset = targetOffset
	cameraState.Active = true
	cameraState.RestoreTime = getCameraStabilizationRestoreTime(abilityConfig)
	if shouldLog then
		logInfo(
			"camera stabilization applied player=%s offsetY=%.2f mode=%s smooth=%.2f",
			self.player.Name,
			compensation,
			stabilizationMode,
			smoothTime
		)
	end
	return true
end

function MoguClient:RestoreBurrowCameraStabilization(ownerState, reason)
	if type(ownerState) ~= "table" then
		return false
	end

	local cameraState = ownerState.CameraStabilizationState
	if type(cameraState) ~= "table" or cameraState.Active ~= true then
		return false
	end

	cameraState.Active = false
	ownerState.CameraStabilizationState = nil
	if cameraState.Tween then
		cameraState.Tween:Cancel()
		cameraState.Tween = nil
	end
	local humanoid = cameraState.Humanoid
	if humanoid and humanoid.Parent then
		self:CancelCameraRestoreTween(humanoid)
		local baseOffset = if typeof(cameraState.BaseOffset) == "Vector3"
			then cameraState.BaseOffset
			else humanoid.CameraOffset - (
				if typeof(cameraState.AppliedOffset) == "Vector3" then cameraState.AppliedOffset else Vector3.zero
			)
		local restoreTime = math.max(0, tonumber(cameraState.RestoreTime) or DEFAULT_CAMERA_STABILIZATION_RESTORE_TIME)
		if restoreTime > 0 then
			local restoreTween = TweenService:Create(
				humanoid,
				TweenInfo.new(restoreTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ CameraOffset = baseOffset }
			)
			if type(self.cameraRestoreTweens) == "table" then
				self.cameraRestoreTweens[humanoid] = restoreTween
			end
			restoreTween.Completed:Connect(function()
				if type(self.cameraRestoreTweens) == "table" and self.cameraRestoreTweens[humanoid] == restoreTween then
					self.cameraRestoreTweens[humanoid] = nil
				end
			end)
			restoreTween:Play()
		else
			humanoid.CameraOffset = baseOffset
		end
	end
	logInfo("camera stabilization restored player=%s reason=%s", self.player.Name, tostring(reason or "unknown"))
	return true
end

function MoguClient:PlayBurrowEntryVfx(targetPlayer, burrowState, startPosition, abilityConfig, reason)
	if not targetPlayer or type(burrowState) ~= "table" or burrowState.EntryVfxTriggered == true then
		return false
	end

	local rootPart = getRootPart(targetPlayer)
	local entryPosition = if burrowState.IsLocal and typeof(burrowState.SurfaceRootPosition) == "Vector3"
		then burrowState.SurfaceRootPosition
		else rootPart and rootPart.Position or startPosition
	if typeof(entryPosition) == "Vector3" then
		local entryDirection = resolvePlanarDirection(burrowState.Direction, rootPart and rootPart.CFrame.LookVector or nil)
		entryPosition += entryDirection * getEntryVfxForwardOffset(abilityConfig)
	end

	burrowState.EntryVfxTriggered = true
	burrowState.EntryVfxTriggeredAt = os.clock()
	if not self.vfxController:PlayEntry(entryPosition, burrowState.Direction, abilityConfig) then
		createBurst(entryPosition, burrowState.EntryBurstRadius, false)
	end
	logInfo(
		"entry vfx triggered player=%s reason=%s position=%s",
		targetPlayer.Name,
		tostring(reason or "entry_cue"),
		tostring(entryPosition)
	)
	return true
end

function MoguClient:CompleteBurrowRootTransition(targetPlayer, burrowState, startPosition, abilityConfig, reason)
	if not targetPlayer or self.burrowStates[targetPlayer] ~= burrowState then
		return false
	end

	if burrowState.BuriedRootActive == true then
		return false
	end

	if not shouldUseTrueBurrowRoot(burrowState) then
		if not self:HasVisualBurrowOffset(targetPlayer) then
			local visualSinkSucceeded = self:ApplyVisualBurrowOffset(targetPlayer, abilityConfig)
			burrowState.VisualSinkSucceeded = visualSinkSucceeded
			if not visualSinkSucceeded then
				logWarn("visual sink failed player=%s phase=entry", targetPlayer.Name)
			end
		else
			burrowState.VisualSinkSucceeded = true
		end
		local surfacePosition = if typeof(burrowState.SurfaceRootPosition) == "Vector3"
			then burrowState.SurfaceRootPosition
			else startPosition
		if typeof(surfacePosition) == "Vector3" then
			burrowState.SurfaceRootPosition = surfacePosition
			burrowState.BuriedRootPosition = getBuriedRootPosition(surfacePosition, abilityConfig)
		end
		burrowState.BuriedRootActive = true
		burrowState.RootTransitionDelayToken = nil
		self:SetBurrowStatePhase(targetPlayer, burrowState, STATE_BURIED_ACTIVE, reason or "visual_burrow_ready")
		return true
	end

	local character = getCharacter(targetPlayer)
	local rootPart = getRootPart(targetPlayer)
	local humanoid = self.getHumanoid()
	local surfacePosition = if typeof(burrowState.SurfaceRootPosition) == "Vector3"
		then burrowState.SurfaceRootPosition
		else startPosition
	local buriedPosition = burrowState.BuriedRootPosition or getBuriedRootPosition(surfacePosition, abilityConfig)
	if typeof(surfacePosition) == "Vector3" then
		burrowState.SurfaceRootPosition = surfacePosition
	end
	if character and rootPart and typeof(buriedPosition) == "Vector3" then
		local hadStartupSink = self:HasVisualBurrowOffset(targetPlayer)
		local snappedStartupSink = if hadStartupSink then self:SnapVisualBurrowOffset(targetPlayer) else false
		if humanoid then
			self:ApplyBurrowCameraStabilization(burrowState, humanoid, surfacePosition, buriedPosition, abilityConfig)
			self:ApplyBurrowPhysicsState(burrowState, character, humanoid)
		end
		burrowState.BuriedRootPosition = buriedPosition
		burrowState.BuriedRootActive = true
		burrowState.RootTransitionDelayToken = nil
		self:SetBurrowStatePhase(targetPlayer, burrowState, STATE_BURIED_ACTIVE, reason or "entry_cue")
		local didPivot = pivotCharacterToRootPosition(character, rootPart, buriedPosition, burrowState.Direction, burrowState)
		self:RecordPivotWrite(didPivot)
		if hadStartupSink then
			self:ClearVisualBurrowOffset(targetPlayer, false)
			logInfo(
				"startup visual sink cleared player=%s hadSink=%s snapped=%s pivoted=%s",
				targetPlayer.Name,
				tostring(hadStartupSink),
				tostring(snappedStartupSink),
				tostring(didPivot)
			)
		end
		zeroRootVelocity(rootPart, true)
		local buriedDepth = if typeof(surfacePosition) == "Vector3"
			then math.max(0, surfacePosition.Y - buriedPosition.Y)
			else getBuriedRootDepth(abilityConfig)
		local entryElapsed = math.max(
			0,
			Workspace:GetServerTimeNow() - (tonumber(burrowState.StartedAt) or Workspace:GetServerTimeNow())
		)
		logInfo(
			"root transition complete player=%s elapsed=%.2f buriedDepth=%.2f reason=%s surface=%s buried=%s",
			targetPlayer.Name,
			entryElapsed,
			buriedDepth,
			tostring(reason or "entry_cue"),
			tostring(burrowState.SurfaceRootPosition),
			tostring(buriedPosition)
		)
	else
		logWarn(
			"root transition failed player=%s hasCharacter=%s hasRoot=%s surface=%s buried=%s",
			targetPlayer.Name,
			tostring(character ~= nil),
			tostring(rootPart ~= nil),
			tostring(surfacePosition),
			tostring(buriedPosition)
		)
	end
	burrowState.VisualSinkSkipped = true
	burrowState.VisualSinkSucceeded = true
	logInfo("true burrow root transition complete player=%s phase=entry", targetPlayer.Name)
	if burrowState.BuriedRootActive and not burrowState.ConcealApplied then
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		burrowState.ConcealApplied = true
		logInfo("conceal timing player=%s phase=root_transition", targetPlayer.Name)
	end
	if burrowState.MovementCueWaitingForEntry == true then
		burrowState.MovementCueWaitingForEntry = nil
		task.defer(function()
			if self.burrowStates[targetPlayer] == burrowState then
				self:TriggerBurrowMovementCue(targetPlayer, burrowState, startPosition, abilityConfig)
			end
		end)
	end

	return burrowState.BuriedRootActive == true
end

function MoguClient:ScheduleBurrowRootTransition(targetPlayer, burrowState, startPosition, abilityConfig)
	if not targetPlayer or self.burrowStates[targetPlayer] ~= burrowState then
		return false
	end

	if not shouldUseTrueBurrowRoot(burrowState) then
		return self:CompleteBurrowRootTransition(targetPlayer, burrowState, startPosition, abilityConfig, "entry_cue")
	end

	if burrowState.BuriedRootActive == true then
		return true
	end

	local remainingSinkDelay = getBurrowSinkCompleteRemaining(burrowState, abilityConfig)
	if remainingSinkDelay > 0 then
		if not burrowState.RootTransitionDelayToken then
			local delayToken = {}
			burrowState.RootTransitionDelayToken = delayToken
			logInfo(
				"root transition delayed player=%s delay=%.2f",
				targetPlayer.Name,
				remainingSinkDelay
			)
			task.delay(remainingSinkDelay, function()
				if self.burrowStates[targetPlayer] ~= burrowState
					or burrowState.RootTransitionDelayToken ~= delayToken
				then
					return
				end

				burrowState.RootTransitionDelayToken = nil
				self:CompleteBurrowRootTransition(
					targetPlayer,
					burrowState,
					startPosition,
					abilityConfig,
					"sink_complete"
				)
			end)
		end
		return false
	end

	return self:CompleteBurrowRootTransition(targetPlayer, burrowState, startPosition, abilityConfig, "entry_cue")
end

function MoguClient:TriggerBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
	if not targetPlayer or self.burrowStates[targetPlayer] ~= burrowState then
		return false
	end

	if burrowState.EntryCueTriggered then
		return false
	end

	burrowState.EntryCueTriggered = true
	burrowState.EntryCueDelayToken = nil
	clearEntryCueState(burrowState)

	if shouldUseTrueBurrowRoot(burrowState) and burrowState.StartupVisualSinkAttempted ~= true then
		self:ScheduleStartupVisualSink(targetPlayer, burrowState, abilityConfig)
	elseif not shouldUseTrueBurrowRoot(burrowState) and not self:HasVisualBurrowOffset(targetPlayer) then
		self:ApplyVisualBurrowOffset(targetPlayer, abilityConfig)
	end

	self:PlayBurrowEntryVfx(targetPlayer, burrowState, startPosition, abilityConfig, "entry_cue")
	self:ScheduleBurrowRootTransition(targetPlayer, burrowState, startPosition, abilityConfig)

	if burrowState.MovementCueWaitingForEntry == true then
		if not shouldUseTrueBurrowRoot(burrowState) or burrowState.BuriedRootActive == true then
			burrowState.MovementCueWaitingForEntry = nil
			task.defer(function()
				if self.burrowStates[targetPlayer] == burrowState then
					self:TriggerBurrowMovementCue(targetPlayer, burrowState, startPosition, abilityConfig)
				end
			end)
		end
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
		if not self:TriggerBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig) then
			burrowState.MovementCueWaitingForEntry = true
			return false
		end
	end
	if shouldUseTrueBurrowRoot(burrowState) and burrowState.BuriedRootActive ~= true then
		burrowState.MovementCueWaitingForEntry = true
		logInfo(
			"movement cue waiting for root transition player=%s phase=%s",
			targetPlayer.Name,
			getBurrowStatePhase(burrowState)
		)
		return false
	end

	burrowState.MovementCueTriggered = true
	if targetPlayer == self.player then
		self:ReleaseStartupMovementLock(burrowState, "movement_cue")
	end
	clearMovementCueState(burrowState)
	burrowState.LastTrailAt = Workspace:GetServerTimeNow()
	if shouldUseTrueBurrowRoot(burrowState) then
		if not burrowState.BuriedRootActive and not burrowState.EntryCueTriggered then
			if not self:TriggerBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig) then
				burrowState.MovementCueWaitingForEntry = true
				return false
			end
		end
		burrowState.VisualSinkSkipped = true
		burrowState.VisualSinkSucceeded = true
	elseif not self:HasVisualBurrowOffset(targetPlayer) then
		local visualSinkSucceeded = self:ApplyVisualBurrowOffset(targetPlayer, abilityConfig)
		burrowState.VisualSinkSucceeded = visualSinkSucceeded
		if not visualSinkSucceeded then
			logWarn("visual sink failed player=%s phase=movement_retry", targetPlayer.Name)
		end
	end
	if not shouldUseTrueBurrowRoot(burrowState) and not self:SnapVisualBurrowOffset(targetPlayer) then
		logWarn("visual sink failed player=%s phase=movement_snap", targetPlayer.Name)
	end
	if not burrowState.ConcealApplied then
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		burrowState.ConcealApplied = true
	end

	return true
end

function MoguClient:ApplyBurrowPhysicsState(ownerState, character, humanoid)
	if type(ownerState) ~= "table" or not character or not humanoid then
		return false
	end

	if type(ownerState.BurrowPhysicsState) == "table" and ownerState.BurrowPhysicsState.Applied == true then
		return true
	end

	local physicsState = {
		Applied = true,
		PreviousState = humanoid:GetState(),
		PreviousCanCollideByPart = {},
	}
	pcall(function()
		physicsState.PreviousUseJumpPower = humanoid.UseJumpPower
	end)
	pcall(function()
		physicsState.PreviousJumpPower = humanoid.JumpPower
	end)
	pcall(function()
		physicsState.PreviousJumpHeight = humanoid.JumpHeight
	end)

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			physicsState.PreviousCanCollideByPart[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end

	humanoid.Jump = false
	pcall(function()
		humanoid.JumpPower = 0
	end)
	pcall(function()
		humanoid.JumpHeight = 0
	end)
	pcall(function()
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end)

	ownerState.BurrowPhysicsState = physicsState
	logInfo("burrow physics applied player=%s", self.player.Name)
	return true
end

function MoguClient:RestoreBurrowPhysicsState(ownerState, reason)
	if type(ownerState) ~= "table" then
		return false
	end

	local physicsState = ownerState.BurrowPhysicsState
	if type(physicsState) ~= "table" or physicsState.Restored == true then
		return false
	end

	physicsState.Restored = true
	for part, previousCanCollide in pairs(physicsState.PreviousCanCollideByPart or {}) do
		if part and part.Parent then
			part.CanCollide = previousCanCollide
		end
	end

	local humanoid = self.getHumanoid()
	if humanoid then
		if typeof(physicsState.PreviousUseJumpPower) == "boolean" then
			pcall(function()
				humanoid.UseJumpPower = physicsState.PreviousUseJumpPower
			end)
		end
		if typeof(physicsState.PreviousJumpPower) == "number" then
			pcall(function()
				humanoid.JumpPower = physicsState.PreviousJumpPower
			end)
		end
		if typeof(physicsState.PreviousJumpHeight) == "number" then
			pcall(function()
				humanoid.JumpHeight = physicsState.PreviousJumpHeight
			end)
		end
		local restoreState = physicsState.PreviousState
		if reason == "resolve_complete" then
			restoreState = Enum.HumanoidStateType.Running
		end
		if typeof(restoreState) == "EnumItem" and humanoid.Health > 0 then
			pcall(function()
				humanoid:ChangeState(restoreState)
			end)
		end
	end

	logInfo(
		"burrow physics restored player=%s reason=%s",
		self.player.Name,
		tostring(reason or "unknown")
	)
	return true
end

function MoguClient:StabilizeBurrowStartup(character, rootPart, direction, abilityConfig)
	if not character or not rootPart then
		return nil
	end

	local humanoid = self.getHumanoid()
	local originalAutoRotate = nil
	local originalWalkSpeed = nil
	if humanoid then
		originalAutoRotate = humanoid.AutoRotate
		originalWalkSpeed = humanoid.WalkSpeed
		humanoid.AutoRotate = false
		humanoid.WalkSpeed = 0
	end

	local rootSpeedBeforeHardStop = rootPart.AssemblyLinearVelocity.Magnitude
	local rootAngularSpeedBeforeHardStop = rootPart.AssemblyAngularVelocity.Magnitude
	local startPosition = rootPart.Position
	zeroRootVelocity(rootPart, true)

	local surfacePosition, hasSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
		character,
		rootPart,
		startPosition,
		abilityConfig,
		startPosition,
		{
			FastSample = true,
			AllowActivationDrop = true,
		}
	)
	local stabilizedPosition = surfacePosition or startPosition
	local buriedPosition = getBuriedRootPosition(stabilizedPosition, abilityConfig) or stabilizedPosition
	local stabilization = {
		OriginalAutoRotate = originalAutoRotate,
		OriginalWalkSpeed = originalWalkSpeed,
		RootSpeedBeforeHardStop = rootSpeedBeforeHardStop,
		RootAngularSpeedBeforeHardStop = rootAngularSpeedBeforeHardStop,
		StartPosition = startPosition,
		SurfaceRootPosition = stabilizedPosition,
		BuriedRootPosition = buriedPosition,
		HasSurface = hasSurface == true,
	}
	local didPivot = pivotCharacterToRootPosition(character, rootPart, stabilizedPosition, direction)
	self:RecordPivotWrite(didPivot)
	zeroRootVelocity(rootPart, true)
	stabilization.DidPivot = didPivot

	local activationDrop = startPosition.Y - stabilizedPosition.Y
	if hasSurface and activationDrop > MoguBurrowShared.GetMaxSurfaceDrop(abilityConfig) then
		logInfo(
			"activation ground found from air player=%s drop=%.2f",
			self.player.Name,
			activationDrop
		)
	end

	logInfo(
		"surface startup held player=%s surface=%s buried=%s",
		self.player.Name,
		tostring(stabilizedPosition),
		tostring(buriedPosition)
	)
	logInfo(
		"startup stabilization applied player=%s speed=%.2f angular=%.2f hasSurface=%s pivot=%s surface=%s buried=%s",
		self.player.Name,
		rootSpeedBeforeHardStop,
		rootAngularSpeedBeforeHardStop,
		tostring(hasSurface == true),
		tostring(didPivot),
		tostring(stabilizedPosition),
		tostring(buriedPosition)
	)

	return stabilization
end

function MoguClient:RestoreStartupStabilization(pending, reason)
	if type(pending) ~= "table" or pending.StartupRestored == true then
		return false
	end

	pending.StartupRestored = true
	local restored = false
	local humanoid = self.getHumanoid()
	if humanoid then
		if typeof(pending.OriginalAutoRotate) == "boolean" then
			humanoid.AutoRotate = pending.OriginalAutoRotate
			restored = true
		end
		restored = restorePositiveWalkSpeed(self.player, humanoid, pending.OriginalWalkSpeed, reason) or restored
	end

	logInfo(
		"startup restoration after denial/cancel player=%s reason=%s restored=%s",
		self.player.Name,
		tostring(reason or "unknown"),
		tostring(restored)
	)

	return restored
end

function MoguClient:ApplyStartupMovementLock(ownerState, character, rootPart, humanoid, lockPosition, direction, reason)
	if type(ownerState) ~= "table" or not character or not rootPart or not humanoid then
		return false
	end
	if typeof(lockPosition) ~= "Vector3" then
		return false
	end

	ownerState.StartupMovementLockActive = true
	ownerState.StartupMovementLockPosition = ownerState.StartupMovementLockPosition or lockPosition
	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.Jump = false
	self:RecordPivotWrite(
		pivotCharacterToRootPosition(
			character,
			rootPart,
			ownerState.StartupMovementLockPosition,
			direction,
			ownerState
		)
	)
	zeroRootVelocity(rootPart, true)
	if ownerState.StartupMovementLockLogged ~= true then
		ownerState.StartupMovementLockLogged = true
		logInfo(
			"startup movement locked player=%s reason=%s position=%s",
			self.player.Name,
			tostring(reason or "startup"),
			tostring(ownerState.StartupMovementLockPosition)
		)
	end
	return true
end

function MoguClient:ReleaseStartupMovementLock(ownerState, reason)
	if type(ownerState) ~= "table" or ownerState.StartupMovementLockReleased == true then
		return false
	end
	if ownerState.StartupMovementLockActive ~= true and typeof(ownerState.StartupMovementLockPosition) ~= "Vector3" then
		ownerState.StartupMovementLockReleased = true
		return false
	end

	ownerState.StartupMovementLockReleased = true
	ownerState.StartupMovementLockActive = false
	logInfo(
		"startup movement lock released player=%s reason=%s",
		self.player.Name,
		tostring(reason or "movement_cue")
	)
	return true
end

function MoguClient:ResolveGroundedActivationSurface(character, rootPart, abilityConfig)
	if not character or not rootPart then
		return nil, false, math.huge
	end

	local surfacePosition, hasSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
		character,
		rootPart,
		rootPart.Position,
		abilityConfig,
		rootPart.Position,
		{
			FastSample = true,
			AllowActivationDrop = false,
		}
	)
	if not hasSurface or typeof(surfacePosition) ~= "Vector3" then
		return nil, false, math.huge
	end

	local dropDistance = math.max(0, rootPart.Position.Y - surfacePosition.Y)
	return surfacePosition, true, dropDistance
end

function MoguClient:ShowGroundedRequiredFeedback(reason)
	local now = os.clock()
	if now - (tonumber(self.lastGroundedRequiredFeedbackAt) or 0) < GROUND_REQUIRED_FEEDBACK_COOLDOWN then
		return false
	end

	self.lastGroundedRequiredFeedbackAt = now
	self:SetDiagnosticAttribute("MoguGroundedOnlyMessage", GROUND_REQUIRED_MESSAGE)
	self:SetDiagnosticAttribute("MoguGroundedOnlyMessageReason", tostring(reason or "NotGrounded"))
	self:SetDiagnosticAttribute("MoguGroundedOnlyMessageAt", now)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Mogu",
			Text = GROUND_REQUIRED_MESSAGE,
			Duration = 1.4,
		})
	end)
	return true
end

function MoguClient:ClearLegacyAirborneQueueDiagnostics()
	self:SetDiagnosticAttribute("MoguAirborneQueueState", nil)
	self:SetDiagnosticAttribute("MoguAirborneQueueReason", nil)
	self:SetDiagnosticAttribute("MoguAirborneQueueDropDistance", nil)
end

function MoguClient:RejectGroundedOnlyBurrow(reason, dropDistance, shouldShowFeedback)
	local resolvedReason = tostring(reason or "NotGrounded")
	local resolvedDropDistance = tonumber(dropDistance) or 0
	self:SetDiagnosticAttribute("MoguGroundedOnlyState", "Rejected")
	self:SetDiagnosticAttribute("MoguGroundedOnlyReason", resolvedReason)
	self:SetDiagnosticAttribute("MoguGroundedOnlyDropDistance", resolvedDropDistance)
	self:ClearLegacyAirborneQueueDiagnostics()
	if shouldShowFeedback ~= false then
		self:ShowGroundedRequiredFeedback(resolvedReason)
	end
	logInfo(
		"grounded-only burrow rejected player=%s reason=%s drop=%.2f",
		self.player.Name,
		resolvedReason,
		resolvedDropDistance
	)
	return true
end

function MoguClient:ValidateGroundedOnlyBurrowStart(shouldShowFeedback)
	if self.pendingBurrowFeedback or self.pendingServerConfirmedBurrowStart or self:GetLocalBurrowState() then
		return true
	end

	local abilityConfig = getAbilityConfig()
	if not shouldRequireGroundedBurrowStart(abilityConfig) then
		return true
	end

	local character = getCharacter(self.player)
	local rootPart = self.getLocalRootPart()
	local humanoid = self.getHumanoid()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
		self:RejectGroundedOnlyBurrow("CharacterUnavailable", 0, false)
		return false
	end

	local surfacePosition, hasSurface, dropDistance =
		self:ResolveGroundedActivationSurface(character, rootPart, abilityConfig)
	local hardAirborne, floorMaterialAir, humanoidState, floorMaterial = getHumanoidGroundState(humanoid)
	self:SetDiagnosticAttribute("MoguGroundedOnlyHumanoidState", humanoidState and humanoidState.Name or nil)
	self:SetDiagnosticAttribute("MoguGroundedOnlyFloorMaterial", floorMaterial and floorMaterial.Name or nil)
	self:SetDiagnosticAttribute("MoguGroundedOnlyRaycastConfirmed", hasSurface == true)
	if not hasSurface then
		self:RejectGroundedOnlyBurrow("NoGround", dropDistance, shouldShowFeedback and (hardAirborne or floorMaterialAir))
		return false
	end

	local contactTolerance = getBurrowGroundContactTolerance(abilityConfig)
	if hardAirborne then
		self:RejectGroundedOnlyBurrow("Airborne", dropDistance, shouldShowFeedback)
		return false
	end

	if dropDistance > contactTolerance then
		self:RejectGroundedOnlyBurrow("NotGrounded", dropDistance, shouldShowFeedback and floorMaterialAir)
		return false
	end

	if floorMaterialAir then
		logInfo(
			"grounded-only burrow tolerated floor air player=%s drop=%.2f tolerance=%.2f humanoidState=%s floor=%s",
			self.player.Name,
			dropDistance,
			contactTolerance,
			tostring(humanoidState and humanoidState.Name or "<nil>"),
			tostring(floorMaterial and floorMaterial.Name or "<nil>")
		)
	end

	self:SetDiagnosticAttribute("MoguGroundedOnlyState", "Grounded")
	self:SetDiagnosticAttribute("MoguGroundedOnlyReason", "Accepted")
	self:SetDiagnosticAttribute("MoguGroundedOnlyDropDistance", dropDistance)
	self:ClearLegacyAirborneQueueDiagnostics()
	return true, surfacePosition
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
	local stabilization = self:StabilizeBurrowStartup(character, rootPart, resolvedDirection, abilityConfig)
	if not stabilization then
		return nil
	end
	local surfacePosition = stabilization.SurfaceRootPosition

	local animationState = self.animationController:PlayStart(self.player, abilityConfig)
	logInfo(
		"client-owned start animation player=%s track=%s",
		self.player.Name,
		tostring(animationState and animationState.Track ~= nil)
	)
	logInfo("startup visual sink scheduled player=%s phase=prediction", self.player.Name)

	local token = {}
	local pending = {
		Token = token,
		RequestedAt = requestedAt,
		LocalStartFeedbackAt = requestedAt,
		Direction = resolvedDirection,
		SurfaceRootPosition = surfacePosition,
		BuriedRootPosition = stabilization.BuriedRootPosition,
		AnimationState = animationState,
		EntryCueTriggered = false,
		VisualSinkSucceeded = false,
		VisualSinkSkipped = true,
		StartupVisualSinkAttempted = false,
		StartupVisualSinkSucceeded = false,
		StartupVisualSinkStartedAt = nil,
		StartupMovementLockActive = true,
		StartupMovementLockReleased = false,
		StartupMovementLockPosition = surfacePosition,
		StartupStabilized = true,
		BuriedRootActive = false,
		StatePhase = STATE_STARTUP_SURFACE,
		BurrowPhysicsState = stabilization.BurrowPhysicsState,
		OriginalAutoRotate = stabilization.OriginalAutoRotate,
		OriginalWalkSpeed = stabilization.OriginalWalkSpeed,
		RootSpeedBeforeHardStop = stabilization.RootSpeedBeforeHardStop,
		RootAngularSpeedBeforeHardStop = stabilization.RootAngularSpeedBeforeHardStop,
		StartupHasSurface = stabilization.HasSurface,
	}
	self.pendingBurrowFeedback = pending
	local humanoid = self.getHumanoid()
	if humanoid then
		self:ApplyStartupMovementLock(pending, character, rootPart, humanoid, surfacePosition, resolvedDirection, "prediction")
	end
	self:ScheduleStartupVisualSink(self.player, pending, abilityConfig)
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
	pending.StartupVisualSinkToken = nil
	self:ReleaseStartupMovementLock(pending, reason or "prediction_cancelled")
	self:RestoreBurrowCameraStabilization(pending, reason or "prediction_cancelled")
	self.animationController:StopAnimation(pending.AnimationState, reason or "prediction_cancelled")
	local character = getCharacter(self.player)
	local rootPart = self.getLocalRootPart()
	local restorePosition = if typeof(pending.SurfaceRootPosition) == "Vector3"
		then pending.SurfaceRootPosition
		else pending.StartPosition
	if character and rootPart and typeof(restorePosition) == "Vector3" then
		self:RecordPivotWrite(pivotCharacterToRootPosition(character, rootPart, restorePosition, pending.Direction))
		zeroRootVelocity(rootPart, true)
		logInfo(
			"restore path used player=%s reason=%s position=%s",
			self.player.Name,
			tostring(reason or "prediction_cancelled"),
			tostring(restorePosition)
		)
	end
	self:RestoreStartupStabilization(pending, reason or "prediction_cancelled")
	self:ClearVisualBurrowOffset(self.player, true, DEFAULT_VISUAL_RISE_DURATION)
	self:ClearConceal(self.player)
	self:RestoreBurrowPhysicsState(pending, reason or "prediction_cancelled")
	self:RecordCleanup()
	self:PublishDiagnostics(true)
	return true
end

function MoguClient:CancelServerConfirmedBurrowStart(reason)
	local pending = self.pendingServerConfirmedBurrowStart
	if not pending then
		return false
	end

	self.pendingServerConfirmedBurrowStart = nil
	pending.Token = nil
	logInfo(
		"server-confirmed startup snapshot cleared player=%s reason=%s",
		self.player.Name,
		tostring(reason or "unknown")
	)
	return true
end

function MoguClient:UpdatePendingLocalStartFeedback()
	local pending = self.pendingBurrowFeedback
	if not pending then
		return false
	end

	local character = getCharacter(self.player)
	local rootPart = self.getLocalRootPart()
	local humanoid = self.getHumanoid()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
		self:CancelLocalStartFeedback("character_unavailable")
		return true
	end

	local lockPosition = pending.StartupMovementLockPosition
	if typeof(lockPosition) ~= "Vector3" then
		lockPosition = pending.SurfaceRootPosition
	end
	if typeof(lockPosition) ~= "Vector3" then
		lockPosition = pending.StartPosition
	end
	if typeof(lockPosition) ~= "Vector3" then
		return false
	end

	self:ApplyStartupMovementLock(pending, character, rootPart, humanoid, lockPosition, pending.Direction, "prediction_update")
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

function MoguClient:ScheduleBurrowStartupWatchdog(targetPlayer, burrowState, abilityConfig)
	if targetPlayer ~= self.player or type(burrowState) ~= "table" then
		return false
	end

	local timeout = getStartupActivationTimeout(abilityConfig)
	if timeout <= 0 then
		return false
	end

	local token = {}
	burrowState.StartupWatchdogToken = token
	task.delay(timeout, function()
		if self.burrowStates[targetPlayer] ~= burrowState or burrowState.StartupWatchdogToken ~= token then
			return
		end
		if burrowState.ResolveInProgress == true then
			return
		end
		if burrowState.BuriedRootActive == true and burrowState.MovementCueTriggered == true then
			burrowState.StartupWatchdogToken = nil
			return
		end

		burrowState.StartupWatchdogToken = nil
		logWarn(
			"startup watchdog resolving player=%s phase=%s buried=%s movement=%s",
			targetPlayer.Name,
			getBurrowStatePhase(burrowState),
			tostring(burrowState.BuriedRootActive == true),
			tostring(burrowState.MovementCueTriggered == true)
		)
		self:RequestSurface(SURFACE_REASON_STARTUP_FAILED)
	end)

	return true
end

function MoguClient:ClearConceal(targetPlayer)
	local concealState = self.concealStates[targetPlayer]
	if not concealState then
		return
	end

	self.concealStates[targetPlayer] = nil
	if typeof(concealState.DescendantAddedConnection) == "RBXScriptConnection" then
		concealState.DescendantAddedConnection:Disconnect()
		concealState.DescendantAddedConnection = nil
	end
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

function MoguClient:RevealConcealedCharacter(targetPlayer)
	local concealState = self.concealStates[targetPlayer]
	if not concealState or concealState.VisualRestored == true then
		return false
	end

	concealState.VisualRestored = true
	for part, previousTransparency in pairs(concealState.PreviousByPart) do
		if part and part.Parent then
			part.LocalTransparencyModifier = previousTransparency
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

	logInfo("conceal cleared/reveal cue fired player=%s", targetPlayer.Name)
	return true
end

function MoguClient:RepairActiveConceal(targetPlayer, burrowState, now)
	if
		not targetPlayer
		or type(burrowState) ~= "table"
		or burrowState.BuriedRootActive ~= true
		or burrowState.ResolveInProgress == true
		or burrowState.ConcealApplied ~= true
	then
		return false
	end

	local nextRepairAt = tonumber(burrowState.NextConcealRepairAt) or 0
	if (tonumber(now) or 0) < nextRepairAt then
		return false
	end
	burrowState.NextConcealRepairAt = (tonumber(now) or 0) + CONCEAL_REPAIR_INTERVAL

	local character = getCharacter(targetPlayer)
	if not character then
		return false
	end

	local concealState = self.concealStates[targetPlayer]
	if not concealState then
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		logWarn("active conceal repaired missing state player=%s", targetPlayer.Name)
		return true
	end

	local repairedCount = 0
	local transparency = tonumber(concealState.Transparency) or burrowState.ConcealTransparency or 1
	for _, descendant in ipairs(character:GetDescendants()) do
		if concealDescendant(descendant, concealState, transparency) then
			repairedCount += 1
		end
	end
	if repairedCount > 0 then
		logInfo("active conceal repaired player=%s count=%d", targetPlayer.Name, repairedCount)
		return true
	end

	return false
end

function MoguClient:GetLocalBurrowState()
	return self.burrowStates[self.player]
end

function MoguClient:AttachBurrowLifecycleCleanup(targetPlayer, burrowState)
	if not targetPlayer or type(burrowState) ~= "table" then
		return false
	end

	clearBurrowLifecycleState(burrowState)
	local connections = {}
	burrowState.CharacterConnections = connections
	local character = getCharacter(targetPlayer)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	burrowState.Character = character

	if humanoid then
		connections[#connections + 1] = humanoid.Died:Connect(function()
			if self.burrowStates[targetPlayer] == burrowState then
				self:FinishResolve(targetPlayer, burrowState, "humanoid_died")
			end
		end)
	end

	connections[#connections + 1] = targetPlayer.CharacterRemoving:Connect(function(characterRemoving)
		if self.burrowStates[targetPlayer] ~= burrowState then
			return
		end
		if burrowState.Character and characterRemoving ~= burrowState.Character then
			return
		end

		self:FinishResolve(targetPlayer, burrowState, "character_removing")
	end)

	return true
end

function MoguClient:RequestSurface(reason)
	local burrowState = self:GetLocalBurrowState()
	if not burrowState then
		logInfo("Q ignored player=%s reason=no_active_burrow request=%s", self.player.Name, tostring(reason or "unknown"))
		return false
	end
	if burrowState.ResolveInProgress then
		logInfo(
			"duplicate resolve prevented player=%s reason=resolve_in_progress request=%s phase=%s",
			self.player.Name,
			tostring(reason or "unknown"),
			getBurrowStatePhase(burrowState)
		)
		return false
	end
	if burrowState.SurfaceRequested then
		logInfo(
			"duplicate resolve prevented player=%s reason=request_pending request=%s phase=%s",
			self.player.Name,
			tostring(reason or "unknown"),
			getBurrowStatePhase(burrowState)
		)
		return false
	end
	if
		reason == SURFACE_REASON_MANUAL_TOGGLE
		and (burrowState.BuriedRootActive ~= true or burrowState.MovementCueTriggered ~= true)
	then
		logInfo(
			"Q ignored player=%s reason=startup_not_fully_underground phase=%s buried=%s movement=%s",
			self.player.Name,
			getBurrowStatePhase(burrowState),
			tostring(burrowState.BuriedRootActive == true),
			tostring(burrowState.MovementCueTriggered == true)
		)
		return false
	end
	if typeof(self.requestAbility) ~= "function" then
		return false
	end
	if typeof(burrowState.SessionId) ~= "string" or burrowState.SessionId == "" then
		logWarn("resolve request blocked player=%s reason=missing_session", self.player.Name)
		return false
	end

	local rootPart = self.getLocalRootPart()
	burrowState.Direction = self:GetBurrowSurfaceDirection(rootPart, burrowState.Direction)
	burrowState.SurfaceRequested = true
	burrowState.ResolveRequestReason = reason or "unknown"
	logInfo(
		"%s resolve fired player=%s phase=%s",
		reason == SURFACE_REASON_DURATION_ELAPSED and "timer" or "manual",
		self.player.Name,
		getBurrowStatePhase(burrowState)
	)
	self.requestAbility(ABILITY_NAME, {
		Direction = burrowState.Direction,
		CurrentSurfacePosition = burrowState.SurfaceRootPosition,
		SessionId = burrowState.SessionId,
	})
	return true
end

function MoguClient:StartBurrow(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local abilityConfig = getAbilityConfig()
	local sessionId = typeof(payload.SessionId) == "string" and payload.SessionId or nil
	if not sessionId then
		logWarn("start ignored player=%s reason=missing_session", targetPlayer.Name)
		return false
	end
	local serverConfirmedStart = if targetPlayer == self.player then self.pendingServerConfirmedBurrowStart else nil
	if serverConfirmedStart then
		self.pendingServerConfirmedBurrowStart = nil
		serverConfirmedStart.Token = nil
		if self.diagnostics and tonumber(serverConfirmedStart.RequestedAt) then
			self.diagnostics.LastStartInputToAuthorizedMs = (os.clock() - serverConfirmedStart.RequestedAt) * 1000
		end
		logInfo("server-confirmed startup authorized player=%s reason=start_effect", self.player.Name)
	end
	local pendingFeedback = if targetPlayer == self.player then self.pendingBurrowFeedback else nil
	local predictedEntryCueTriggered = pendingFeedback and pendingFeedback.EntryCueTriggered == true or false
	local predictedVisualSinkSucceeded = pendingFeedback
		and pendingFeedback.VisualSinkSucceeded == true
		and self:HasVisualBurrowOffset(targetPlayer)
		or false
	local predictedStartDistance = nil
	if pendingFeedback and typeof(pendingFeedback.SurfaceRootPosition) == "Vector3" and typeof(payload.StartPosition) == "Vector3" then
		predictedStartDistance = (pendingFeedback.SurfaceRootPosition - payload.StartPosition).Magnitude
		self:SetDiagnosticAttribute("MoguPredictedStartDistance", predictedStartDistance)
		logInfo(
			"predicted vs authoritative start player=%s distance=%.2f",
			targetPlayer.Name,
			predictedStartDistance
		)
	end
	if pendingFeedback then
		self.pendingBurrowFeedback = nil
		pendingFeedback.StartupVisualSinkToken = nil
		if self.diagnostics then
			self.diagnostics.LastStartInputToAuthorizedMs = (os.clock() - pendingFeedback.RequestedAt) * 1000
		end
	end

	local existingBurrowState = self.burrowStates[targetPlayer]
	if existingBurrowState then
		if existingBurrowState.SessionId == sessionId then
			logInfo(
				"duplicate start ignored player=%s session=%s phase=%s",
				targetPlayer.Name,
				tostring(sessionId),
				getBurrowStatePhase(existingBurrowState)
			)
			return true
		end

		self:FinishResolve(targetPlayer, existingBurrowState, "replaced_by_new_session")
	end

	local duration = math.max(0.5, tonumber(payload.Duration) or MoguBurrowShared.GetBurrowDuration(abilityConfig))
	local startedAt = tonumber(payload.StartedAt) or Workspace:GetServerTimeNow()
	local burrowState = {
		SessionId = sessionId,
		ServerState = typeof(payload.ServerState) == "string" and payload.ServerState or nil,
		UndergroundAt = tonumber(payload.UndergroundAt),
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
		LocalStartFeedbackAt = pendingFeedback and pendingFeedback.LocalStartFeedbackAt
			or serverConfirmedStart and serverConfirmedStart.RequestedAt
			or nil,
		EntryCueTriggered = predictedEntryCueTriggered and predictedVisualSinkSucceeded,
		EntryVfxTriggered = (pendingFeedback and pendingFeedback.EntryVfxTriggered == true)
			or false,
		EntryVfxTriggeredAt = pendingFeedback and pendingFeedback.EntryVfxTriggeredAt
			or nil,
		VisualSinkSucceeded = predictedVisualSinkSucceeded,
		VisualSinkSkipped = (pendingFeedback and pendingFeedback.VisualSinkSkipped == true)
			or false,
		StartupVisualSinkAttempted = pendingFeedback and pendingFeedback.StartupVisualSinkAttempted == true or false,
		StartupVisualSinkSucceeded = (pendingFeedback and pendingFeedback.StartupVisualSinkSucceeded == true)
			or false,
		StartupVisualSinkStartedAt = pendingFeedback and pendingFeedback.StartupVisualSinkStartedAt or nil,
		StartupMovementLockActive = targetPlayer == self.player,
		StartupMovementLockReleased = false,
		StartupMovementLockPosition = pendingFeedback and pendingFeedback.StartupMovementLockPosition or nil,
		StartupStabilized = pendingFeedback and pendingFeedback.StartupStabilized == true or false,
		StartupPredictedStartDistance = predictedStartDistance,
		BurrowPhysicsState = pendingFeedback and pendingFeedback.BurrowPhysicsState or nil,
		BuriedRootActive = pendingFeedback and pendingFeedback.BuriedRootActive == true or false,
		StatePhase = if pendingFeedback and pendingFeedback.BuriedRootActive == true
			then STATE_BURIED_ACTIVE
			else STATE_STARTUP_SURFACE,
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
				{
					FastSample = true,
					AllowActivationDrop = true,
				}
			)
			burrowState.SurfaceRootPosition = resolvedSurfacePosition
				or (pendingFeedback and pendingFeedback.SurfaceRootPosition)
				or (serverConfirmedStart and serverConfirmedStart.SurfaceRootPosition)
				or (typeof(startPosition) == "Vector3" and startPosition)
			if typeof(burrowState.SurfaceRootPosition) == "Vector3" then
				burrowState.StartupMovementLockPosition = burrowState.StartupMovementLockPosition
					or burrowState.SurfaceRootPosition
				burrowState.BuriedRootPosition = getBuriedRootPosition(burrowState.SurfaceRootPosition, abilityConfig)
			elseif pendingFeedback and typeof(pendingFeedback.BuriedRootPosition) == "Vector3" then
				burrowState.BuriedRootPosition = pendingFeedback.BuriedRootPosition
			end
			burrowState.LastSurfaceProbeAt = os.clock()
			burrowState.LastSurfaceProbePosition = burrowState.SurfaceRootPosition
			burrowState.LastSurfaceProbeHadSurface = hasSurface
			if not hasSurface and typeof(burrowState.SurfaceRootPosition) ~= "Vector3" then
				shouldRequestSurfaceImmediately = true
			end
		end
	elseif typeof(startPosition) == "Vector3" then
		burrowState.SurfaceRootPosition = startPosition
		burrowState.StartupMovementLockPosition = burrowState.StartupMovementLockPosition or startPosition
		burrowState.BuriedRootPosition = getBuriedRootPosition(startPosition, abilityConfig)
	end

	if burrowState.IsLocal then
		local humanoid = self.getHumanoid()
		if humanoid then
			if pendingFeedback and typeof(pendingFeedback.OriginalAutoRotate) == "boolean" then
				burrowState.OriginalAutoRotate = pendingFeedback.OriginalAutoRotate
			elseif serverConfirmedStart and typeof(serverConfirmedStart.OriginalAutoRotate) == "boolean" then
				burrowState.OriginalAutoRotate = serverConfirmedStart.OriginalAutoRotate
			else
				burrowState.OriginalAutoRotate = humanoid.AutoRotate
			end
			if pendingFeedback and typeof(pendingFeedback.OriginalWalkSpeed) == "number" then
				burrowState.OriginalWalkSpeed = pendingFeedback.OriginalWalkSpeed
			elseif serverConfirmedStart and typeof(serverConfirmedStart.OriginalWalkSpeed) == "number" then
				burrowState.OriginalWalkSpeed = serverConfirmedStart.OriginalWalkSpeed
			else
				local currentWalkSpeed = humanoid.WalkSpeed
				if currentWalkSpeed > 0 or not isMoguMovementLockActive(self.player) then
					burrowState.OriginalWalkSpeed = currentWalkSpeed
				end
			end
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = 0
		end
	end

	self.burrowStates[targetPlayer] = burrowState
	self:AttachBurrowLifecycleCleanup(targetPlayer, burrowState)
	logInfo(
		"state transition player=%s <nil> -> %s reason=start_authorized",
		targetPlayer.Name,
		getBurrowStatePhase(burrowState)
	)
	if shouldRequestSurfaceImmediately then
		self:RequestSurface(SURFACE_REASON_SURFACE_LOST)
	end

	if burrowState.IsLocal then
		local character = getCharacter(self.player)
		local rootPart = self.getLocalRootPart()
		local humanoid = self.getHumanoid()
		local pivotPosition = nil
		if burrowState.BuriedRootActive then
			pivotPosition = getGameplayRootPosition(
				burrowState,
				burrowState.SurfaceRootPosition or startPosition,
				abilityConfig
			)
		else
			pivotPosition = burrowState.StartupMovementLockPosition or burrowState.SurfaceRootPosition or startPosition
		end
		pivotPosition = pivotPosition or (rootPart and rootPart.Position)
		if character and rootPart and typeof(pivotPosition) == "Vector3" then
			if humanoid and burrowState.BuriedRootActive ~= true then
				self:ApplyStartupMovementLock(
					burrowState,
					character,
					rootPart,
					humanoid,
					pivotPosition,
					burrowState.Direction,
					"start_authorized"
				)
			else
				self:RecordPivotWrite(
					pivotCharacterToRootPosition(character, rootPart, pivotPosition, burrowState.Direction, burrowState)
				)
				zeroRootVelocity(rootPart, true)
			end
			logInfo(
				"surface startup held player=%s surface=%s buried=%s active=%s",
				self.player.Name,
				tostring(burrowState.SurfaceRootPosition),
				tostring(burrowState.BuriedRootPosition),
				tostring(burrowState.BuriedRootActive)
			)
		end
	end

	burrowState.AnimationState = pendingFeedback and pendingFeedback.AnimationState or nil
	if not burrowState.AnimationState then
		burrowState.AnimationState = self.animationController:PlayStart(targetPlayer, abilityConfig)
		logInfo(
			"client-owned start animation player=%s track=%s",
			targetPlayer.Name,
			tostring(burrowState.AnimationState and burrowState.AnimationState.Track ~= nil)
		)
	end
	if burrowState.IsLocal and burrowState.StartupVisualSinkSucceeded ~= true then
		self:ScheduleStartupVisualSink(targetPlayer, burrowState, abilityConfig)
	end

	if not burrowState.EntryCueTriggered then
		if predictedEntryCueTriggered then
			logWarn(
				"prediction retried on confirmed start player=%s predictedSink=%s hasVisualState=%s",
				targetPlayer.Name,
				tostring(pendingFeedback and pendingFeedback.VisualSinkSucceeded == true),
				tostring(self:HasVisualBurrowOffset(targetPlayer))
			)
			self:TriggerBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
		else
			self:ScheduleBurrowEntryCue(targetPlayer, burrowState, startPosition, abilityConfig)
		end
	end
	self:ScheduleBurrowMovementCue(targetPlayer, burrowState, startPosition, abilityConfig)
	self:ScheduleBurrowStartupWatchdog(targetPlayer, burrowState, abilityConfig)
	return true
end

function MoguClient:FinishResolve(targetPlayer, burrowState, reason)
	if not targetPlayer or type(burrowState) ~= "table" then
		return false
	end

	if self.burrowStates[targetPlayer] == burrowState then
		self.burrowStates[targetPlayer] = nil
	end
	clearBurrowCueState(burrowState)
	clearBurrowLifecycleState(burrowState)
	self:SetBurrowStatePhase(targetPlayer, burrowState, STATE_FINISHED, reason or "resolve_cleanup")
	self:ClearConceal(targetPlayer)
	if targetPlayer == self.player then
		self:ReleaseStartupMovementLock(burrowState, reason or "resolve_cleanup")
		self:RestoreBurrowCameraStabilization(burrowState, reason or "resolve_cleanup")
		self:RestoreBurrowPhysicsState(burrowState, "resolve_complete")
		local humanoid = self.getHumanoid()
		if humanoid and humanoid.Health > 0 then
			restorePositiveWalkSpeed(targetPlayer, humanoid, burrowState.OriginalWalkSpeed, reason or "resolve_cleanup")
			if typeof(burrowState.OriginalAutoRotate) == "boolean" then
				humanoid.AutoRotate = burrowState.OriginalAutoRotate
			end
		end
		logInfo("final cleanup restored physics player=%s reason=%s", targetPlayer.Name, tostring(reason or "resolve_cleanup"))
	end
	self:RecordCleanup()
	self:PublishDiagnostics(true)
	logInfo(
		"resolve cleanup finished player=%s reason=%s",
		targetPlayer.Name,
		tostring(reason or "resolve_cleanup")
	)
	return true
end

function MoguClient:StopBurrow(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	payload = payload or {}
	local burrowState = self.burrowStates[targetPlayer]
	if not burrowState then
		logWarn(
			"duplicate resolve prevented player=%s reason=no_active_state payloadReason=%s",
			targetPlayer.Name,
			tostring(payload.ResolveReason)
		)
		return false
	end
	if
		typeof(payload.SessionId) == "string"
		and typeof(burrowState.SessionId) == "string"
		and payload.SessionId ~= burrowState.SessionId
	then
		logWarn(
			"stale resolve ignored player=%s payloadSession=%s activeSession=%s",
			targetPlayer.Name,
			tostring(payload.SessionId),
			tostring(burrowState.SessionId)
		)
		return false
	end
	if burrowState.ResolveInProgress then
		logWarn(
			"duplicate resolve prevented player=%s reason=already_resolving payloadReason=%s phase=%s",
			targetPlayer.Name,
			tostring(payload.ResolveReason),
			getBurrowStatePhase(burrowState)
		)
		return false
	end

	local abilityConfig = getAbilityConfig()
	local visualRiseDuration = getVisualRiseDuration(abilityConfig)
	local revealDelay = getResolveRevealDelay(abilityConfig)
	local backJerkDistance = getResolveBackJerkDistance(abilityConfig)
	local backJerkDuration = if backJerkDistance > 0 then getResolveBackJerkDuration(abilityConfig) else 0
	local surfaceLockDuration = math.max(getResolveSurfaceLockDuration(abilityConfig), visualRiseDuration, backJerkDuration)
	local facingLockDuration = getResolveFacingLockDuration(abilityConfig)
	local resolveCleanupDelay = math.max(surfaceLockDuration, visualRiseDuration, facingLockDuration)
	revealDelay = math.min(revealDelay, resolveCleanupDelay)
	local fallbackRootPart = getRootPart(targetPlayer)
	local resolveDirection = resolvePlanarDirection(
		payload.Direction,
		(burrowState and burrowState.Direction) or (fallbackRootPart and fallbackRootPart.CFrame.LookVector or nil)
	)
	local localHumanoid = nil
	local revealCharacter = nil
	local revealRootPart = nil
	local resolveAnimationPosition = nil
	if targetPlayer == self.player and self.diagnostics then
		self.diagnostics.LastResolveCorrectionDistance = math.max(0, tonumber(payload.ResolveCorrectionDistance) or 0)
	end

	burrowState.ResolveInProgress = true
	burrowState.SurfaceRequested = true
	burrowState.ResolveReason = payload.ResolveReason or burrowState.ResolveRequestReason or "unknown"
	self:SetBurrowStatePhase(targetPlayer, burrowState, STATE_RESOLVE_IN_PROGRESS, burrowState.ResolveReason)
	clearBurrowCueState(burrowState)
	self.animationController:StopAnimation(burrowState and burrowState.AnimationState, "resolve_transition")

	if targetPlayer == self.player and burrowState.BuriedRootActive ~= true then
		logWarn(
			"resolve before buried canceled player=%s payloadReason=%s phase=%s",
			targetPlayer.Name,
			tostring(payload.ResolveReason),
			getBurrowStatePhase(burrowState)
		)
		self:ClearVisualBurrowOffset(targetPlayer, true, visualRiseDuration)
		self:RestoreBurrowCameraStabilization(burrowState, "resolve_before_buried")
		self:FinishResolve(targetPlayer, burrowState, "resolve_before_buried")
		return false
	end

	local clampedResolvePosition = nil
	local resolveVfxPosition = nil
	if targetPlayer == self.player then
		local humanoid = self.getHumanoid()
		if humanoid and burrowState then
			localHumanoid = humanoid
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = 0
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
				resolveAnimationPosition =
					getResolveAnimationPosition(resolvedSurfacePosition, resolveDirection, rootPart, abilityConfig)
				resolveVfxPosition =
					getResolveVfxPosition(resolveAnimationPosition, resolveDirection, rootPart, abilityConfig)
			else
				resolveAnimationPosition = rootPart.Position
				resolveVfxPosition = getResolveVfxPosition(rootPart.Position, resolveDirection, rootPart, abilityConfig)
			end
			revealCharacter = character
			revealRootPart = rootPart
			zeroRootVelocity(rootPart, true)
		end
	else
		local character = getCharacter(targetPlayer)
		local rootPart = fallbackRootPart
		if character and rootPart then
			local surfacePosition = if typeof(payload.ActualEndPosition) == "Vector3"
				then payload.ActualEndPosition
				else rootPart.Position
			resolveAnimationPosition = getResolveAnimationPosition(surfacePosition, resolveDirection, rootPart, abilityConfig)
			resolveVfxPosition = getResolveVfxPosition(resolveAnimationPosition, resolveDirection, rootPart, abilityConfig)
			revealCharacter = character
			revealRootPart = rootPart
			zeroRootVelocity(rootPart, true, false)
		end
	end

	burrowState.ResolveRevealPending = true
	burrowState.ResolveRevealDelay = revealDelay
	burrowState.ResolveAnimationPosition = resolveAnimationPosition
	burrowState.ResolveVfxPosition = resolveVfxPosition
	burrowState.ResolveAnimationState = self.animationController:PlayResolve(targetPlayer, abilityConfig)
	logInfo(
		"resolve animation started player=%s revealDelay=%.2f track=%s",
		targetPlayer.Name,
		revealDelay,
		tostring(burrowState.ResolveAnimationState and burrowState.ResolveAnimationState.Track ~= nil)
	)
	if targetPlayer == self.player and localHumanoid then
		localHumanoid.AutoRotate = false
	end

	local resolveToken = {}
	burrowState.ResolveCleanupToken = resolveToken

	local function playResolveVfx()
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

	local function fireResolveReveal()
		if self.burrowStates[targetPlayer] ~= burrowState or burrowState.ResolveCleanupToken ~= resolveToken then
			return
		end

		burrowState.ResolveRevealPending = false
		burrowState.ResolveRevealed = true
		local visualRestored = self:RevealConcealedCharacter(targetPlayer)
		self:SnapVisualBurrowOffset(targetPlayer)
		self:ClearVisualBurrowOffset(targetPlayer, true, visualRiseDuration)
		logInfo(
			"resolve reveal cue fired player=%s delay=%.2f concealRestored=%s",
			targetPlayer.Name,
			revealDelay,
			tostring(visualRestored)
		)

		local remainingResolveLockDuration = math.max(0, resolveCleanupDelay - revealDelay)
		if revealCharacter and revealRootPart and typeof(resolveAnimationPosition) == "Vector3" then
			local didPivot = pivotCharacterToRootPosition(
				revealCharacter,
				revealRootPart,
				resolveAnimationPosition,
				resolveDirection,
				burrowState
			)
			if targetPlayer == self.player then
				self:RecordPivotWrite(didPivot)
				self:RestoreBurrowCameraStabilization(burrowState, "resolve_reveal")
				lockCharacterToSurface(
					revealCharacter,
					revealRootPart,
					resolveAnimationPosition,
					resolveDirection,
					abilityConfig,
					remainingResolveLockDuration,
					backJerkDistance,
					backJerkDuration,
					burrowState,
					function()
						self:RecordPivotWrite(true)
					end
				)
			else
				keepFacingDuringResolve(revealCharacter, revealRootPart, resolveDirection, remainingResolveLockDuration)
			end
			zeroRootVelocity(revealRootPart, true, targetPlayer == self.player)
			logInfo(
				"pivoted to surface player=%s position=%s wrote=%s",
				targetPlayer.Name,
				tostring(resolveAnimationPosition),
				tostring(didPivot)
			)
		end

		playResolveVfx()
	end

	if revealDelay <= 0 then
		fireResolveReveal()
	else
		task.delay(revealDelay, fireResolveReveal)
	end

	task.delay(resolveCleanupDelay, function()
		if self.burrowStates[targetPlayer] ~= burrowState or burrowState.ResolveCleanupToken ~= resolveToken then
			return
		end

		self:FinishResolve(targetPlayer, burrowState, "resolve_complete")
	end)
	return true
end

function MoguClient:HandleInputBegan(input, gameProcessed)
	if input and input.KeyCode == Enum.KeyCode.Q and not gameProcessed then
		if self.pendingServerConfirmedBurrowStart then
			logInfo("Q ignored player=%s reason=server_confirmed_start_pending", self.player.Name)
			return true
		end
		if self.pendingBurrowFeedback then
			logInfo("Q ignored player=%s reason=start_request_pending", self.player.Name)
			return true
		end

		local burrowState = self:GetLocalBurrowState()
		if burrowState then
			self:RequestSurface(SURFACE_REASON_MANUAL_TOGGLE)
			return true
		end

		if self.isAbilityLocallyReady(ABILITY_NAME) ~= false and not self:ValidateGroundedOnlyBurrowStart(true) then
			return true
		end
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

	if self.pendingServerConfirmedBurrowStart then
		logInfo("Q ignored player=%s reason=server_confirmed_start_pending", self.player.Name)
		return nil
	end

	local burrowState = self:GetLocalBurrowState()
	if burrowState then
		logInfo(
			"Q ignored player=%s reason=active_state phase=%s resolve=%s",
			self.player.Name,
			getBurrowStatePhase(burrowState),
			tostring(burrowState.ResolveInProgress == true)
		)
		return nil
	end
	if self.pendingBurrowFeedback then
		logInfo("Q ignored player=%s reason=start_request_pending", self.player.Name)
		return nil
	end

	local direction = self:GetBurrowActivationDirection(rootPart)
	if not self:ValidateGroundedOnlyBurrowStart(true) then
		return false
	end

	local abilityConfig = getAbilityConfig()
	local humanoid = self.getHumanoid()
	local serverConfirmedStart, effectiveSpeed, threshold, planarSpeed, walkSpeed =
		shouldUseServerConfirmedBurrowStartup(rootPart, humanoid, abilityConfig)
	if serverConfirmedStart then
		local payload = {
			Direction = direction,
		}
		local character = getCharacter(self.player)
		local surfacePosition, hasSurface = nil, false
		if character then
			surfacePosition, hasSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
				character,
				rootPart,
				rootPart.Position,
				abilityConfig,
				rootPart.Position,
				{
					FastSample = true,
					AllowActivationDrop = true,
				}
			)
		end
		if hasSurface and typeof(surfacePosition) == "Vector3" then
			payload.PredictedStartPosition = surfacePosition
		end
		local token = {}
		local requestedAt = os.clock()
		local pending = {
			Token = token,
			RequestedAt = requestedAt,
			Direction = direction,
			SurfaceRootPosition = if hasSurface and typeof(surfacePosition) == "Vector3" then surfacePosition else nil,
			OriginalAutoRotate = humanoid and humanoid.AutoRotate or nil,
			OriginalWalkSpeed = humanoid and humanoid.WalkSpeed or nil,
			RootSpeedBeforeHardStop = rootPart.AssemblyLinearVelocity.Magnitude,
			StartupHasSurface = hasSurface == true,
			StatePhase = STATE_STARTUP_SURFACE,
		}
		self.pendingServerConfirmedBurrowStart = pending
		task.delay(PENDING_START_FEEDBACK_TIMEOUT, function()
			if self.pendingServerConfirmedBurrowStart == pending and pending.Token == token then
				self:CancelServerConfirmedBurrowStart("timeout")
			end
		end)
		self:SetDiagnosticAttribute("MoguHighSpeedStartupMode", "ServerConfirmed")
		self:SetDiagnosticAttribute("MoguHighSpeedStartupSpeed", effectiveSpeed)
		self:SetDiagnosticAttribute("MoguHighSpeedStartupThreshold", threshold)
		self:SetDiagnosticAttribute("MoguHighSpeedStartupPlanarSpeed", planarSpeed)
		self:SetDiagnosticAttribute("MoguHighSpeedStartupWalkSpeed", walkSpeed)
		logWarn(
			"high-speed burrow startup deferred player=%s speed=%.2f planar=%.2f walk=%.2f threshold=%.2f hasSurface=%s",
			self.player.Name,
			effectiveSpeed,
			planarSpeed,
			walkSpeed,
			threshold,
			tostring(hasSurface == true)
		)
		return payload
	end

	self:SetDiagnosticAttribute("MoguHighSpeedStartupMode", "Predicted")
	self:SetDiagnosticAttribute("MoguHighSpeedStartupSpeed", effectiveSpeed)
	self:SetDiagnosticAttribute("MoguHighSpeedStartupThreshold", threshold)
	self:SetDiagnosticAttribute("MoguHighSpeedStartupPlanarSpeed", planarSpeed)
	self:SetDiagnosticAttribute("MoguHighSpeedStartupWalkSpeed", walkSpeed)

	local pending = self:BeginLocalStartFeedback(direction)
	local payload = {
		Direction = direction,
	}
	if pending and typeof(pending.SurfaceRootPosition) == "Vector3" then
		payload.PredictedStartPosition = pending.SurfaceRootPosition
	end
	return payload
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

function MoguClient:UpdateLocalBurrowState(burrowState, dt, now, abilityConfig)
	local character = getCharacter(self.player)
	local rootPart = self.getLocalRootPart()
	local humanoid = self.getHumanoid()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end
	abilityConfig = abilityConfig or getAbilityConfig()

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.Jump = false
	if
		not shouldUseVisualOnlyBurrowRoot(burrowState)
		and (burrowState.BuriedRootActive == true or burrowState.ResolveInProgress == true)
	then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		end)
	end

	if burrowState.ResolveInProgress then
		local holdPosition = getGameplayRootPosition(
			burrowState,
			burrowState.SurfaceRootPosition or rootPart.Position,
			abilityConfig
		)
		if burrowState.ResolveRevealed ~= true and typeof(holdPosition) == "Vector3" then
			self:RecordPivotWrite(
				pivotCharacterToRootPosition(character, rootPart, holdPosition, burrowState.Direction, burrowState)
			)
		end
		zeroRootVelocity(rootPart, true)
		return
	end

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
		zeroRootVelocity(rootPart, true)
		return
	end
	if not burrowState.MovementCueTriggered then
		if typeof(burrowState.StartupMovementLockPosition) == "Vector3" then
			currentSurfacePosition = burrowState.StartupMovementLockPosition
		else
			burrowState.StartupMovementLockPosition = currentSurfacePosition
		end
	end
	burrowState.SurfaceRootPosition = currentSurfacePosition
	burrowState.BuriedRootPosition = getBuriedRootPosition(currentSurfacePosition, abilityConfig)
	if
		not shouldUseVisualOnlyBurrowRoot(burrowState)
		and burrowState.BuriedRootActive == true
		and typeof(burrowState.BuriedRootPosition) == "Vector3"
	then
		self:ApplyBurrowCameraStabilization(
			burrowState,
			humanoid,
			currentSurfacePosition,
			burrowState.BuriedRootPosition,
			abilityConfig
		)
	end

	if now >= burrowState.EndTime and not burrowState.SurfaceRequested then
		logInfo(
			"timer resolve fired player=%s phase=%s buried=%s",
			self.player.Name,
			getBurrowStatePhase(burrowState),
			tostring(burrowState.BuriedRootActive == true)
		)
		self:RequestSurface(SURFACE_REASON_DURATION_ELAPSED)
	end

	if burrowState.BuriedRootActive ~= true then
		self:ApplyStartupMovementLock(
			burrowState,
			character,
			rootPart,
			humanoid,
			currentSurfacePosition,
			burrowState.Direction,
			"startup_update"
		)
		if not burrowState.SurfaceStartupHoldLogged then
			burrowState.SurfaceStartupHoldLogged = true
			logInfo(
				"surface startup held player=%s surface=%s buried=%s",
				self.player.Name,
				tostring(currentSurfacePosition),
				tostring(burrowState.BuriedRootPosition)
			)
		end
		return
	end

	if not burrowState.BuriedEnforcementLogged then
		burrowState.BuriedEnforcementLogged = true
		logInfo(
			"buried enforcement active player=%s surface=%s buried=%s",
			self.player.Name,
			tostring(currentSurfacePosition),
			tostring(burrowState.BuriedRootPosition)
		)
	end
	self:RepairActiveConceal(self.player, burrowState, localNow)

	if burrowState.SurfaceRequested then
		local holdPosition = getGameplayRootPosition(burrowState, currentSurfacePosition, abilityConfig) or currentSurfacePosition
		self:RecordPivotWrite(pivotCharacterToRootPosition(character, rootPart, holdPosition, burrowState.Direction, burrowState))
		zeroRootVelocity(rootPart, true)
		return
	end

	if not burrowState.MovementCueTriggered then
		local holdPosition = getGameplayRootPosition(burrowState, currentSurfacePosition, abilityConfig) or currentSurfacePosition
		self:RecordPivotWrite(pivotCharacterToRootPosition(character, rootPart, holdPosition, burrowState.Direction, burrowState))
		zeroRootVelocity(rootPart, true)
		return
	end

	local desiredDirection = self:GetCameraRelativeBurrowDirection(rootPart)
	local targetPlanarPosition = currentSurfacePosition
	local movementDistance = 0
	if desiredDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		movementDistance = burrowState.MoveSpeed * math.max(0, dt or 0)
		targetPlanarPosition = currentSurfacePosition + (desiredDirection.Unit * movementDistance)
	end

	local movementBlocked = false
	local blockResult = nil
	local blockInfo = nil
	if movementDistance > MIN_TARGET_PROBE_DISTANCE then
		targetPlanarPosition, movementBlocked, blockResult, blockInfo = MoguBurrowShared.ResolvePlanarMovement(
			character,
			rootPart,
			currentSurfacePosition,
			targetPlanarPosition,
			abilityConfig
		)
		movementDistance = (targetPlanarPosition - currentSurfacePosition).Magnitude
		if movementBlocked then
			zeroRootVelocity(rootPart, true)
			if localNow >= ((burrowState.LastWallBlockLogAt or 0) + 0.5) then
				burrowState.LastWallBlockLogAt = localNow
				logInfo(
					"movement blocked player=%s hit=%s reason=%s distance=%.2f accepted=%.2f",
					self.player.Name,
					tostring(blockResult and blockResult.Instance),
					tostring(blockInfo and blockInfo.Reason),
					tonumber(blockInfo and blockInfo.Distance) or 0,
					tonumber(blockInfo and blockInfo.AcceptedDistance) or 0
				)
			end
		end
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
		local surfaceResult = nil
		local surfaceInfo = nil
		resolvedSurfacePosition, hasTargetSurface, surfaceResult, surfaceInfo = MoguBurrowShared.ResolveSurfaceRootPosition(
			character,
			rootPart,
			targetPlanarPosition,
			abilityConfig,
			currentSurfacePosition,
			{
				FastSample = true,
				ActiveBurrowSurface = true,
			}
		)
		burrowState.LastSurfaceProbeAt = localNow
		burrowState.LastSurfaceProbePosition = targetPlanarPosition
		burrowState.LastSurfaceProbeHadSurface = hasTargetSurface
		if hasTargetSurface
			and typeof(resolvedSurfacePosition) == "Vector3"
			and surfaceInfo
			and surfaceInfo.Trusted ~= true
		then
			local upwardDelta = resolvedSurfacePosition.Y - currentSurfacePosition.Y
			local maxUntrustedRise = MoguBurrowShared.GetActiveMaxUntrustedSurfaceRise(abilityConfig)
			if upwardDelta > maxUntrustedRise then
				logWarn(
					"suspicious surface rejected player=%s deltaY=%.2f limit=%.2f hit=%s reason=%s",
					self.player.Name,
					upwardDelta,
					maxUntrustedRise,
					tostring(surfaceResult and surfaceResult.Instance),
					tostring(surfaceInfo.Reason)
				)
				resolvedSurfacePosition = currentSurfacePosition
				hasTargetSurface = false
				burrowState.LastSurfaceProbeHadSurface = false
			end
		end
		if not resolvedSurfacePosition then
			self:RequestSurface(SURFACE_REASON_SURFACE_LOST)
			zeroRootVelocity(rootPart, true)
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
	burrowState.BuriedRootPosition = getBuriedRootPosition(burrowState.SurfaceRootPosition, abilityConfig)
	if not shouldUseVisualOnlyBurrowRoot(burrowState)
		and typeof(burrowState.BuriedRootPosition) == "Vector3"
		and rootPart.Position.Y > burrowState.BuriedRootPosition.Y + 0.5
	then
		logWarn(
			"unexpected upward correction player=%s rootY=%.2f buriedY=%.2f",
			self.player.Name,
			rootPart.Position.Y,
			burrowState.BuriedRootPosition.Y
		)
	end
	local gameplayRootPosition = getGameplayRootPosition(burrowState, burrowState.SurfaceRootPosition, abilityConfig)
	self:RecordPivotWrite(
		pivotCharacterToRootPosition(character, rootPart, gameplayRootPosition, burrowState.Direction, burrowState)
	)
	zeroRootVelocity(rootPart, true)
end

function MoguClient:UpdateTrailState(targetPlayer, burrowState, now, abilityConfig)
	if
		not burrowState
		or burrowState.ResolveInProgress
		or not burrowState.MovementCueTriggered
		or now < burrowState.LastTrailAt + burrowState.TrailInterval
	then
		return
	end

	local rootPart = getRootPart(targetPlayer)
	if not rootPart then
		return
	end

	abilityConfig = abilityConfig or getAbilityConfig()
	burrowState.LastTrailAt = now
	local trailPosition = if typeof(burrowState.SurfaceRootPosition) == "Vector3"
		then burrowState.SurfaceRootPosition
		else rootPart.Position
	if not self.vfxController:PlayTrail(trailPosition, burrowState.Direction, abilityConfig) then
		if createTrailPulse(trailPosition, tonumber(abilityConfig.TrailWidth) or 2.6) and self.diagnostics then
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
		if self:StartBurrow(targetPlayer, payload) then
			self.playOptionalEffect(targetPlayer, FRUIT_NAME, abilityName, payload)
		end
		return true
	end

	if phase == PHASE_RESOLVE then
		if self:StopBurrow(targetPlayer, payload) then
			self.playOptionalEffect(targetPlayer, FRUIT_NAME, abilityName, payload)
		end
		return true
	end

	return false
end

function MoguClient:HandleStateEvent(eventName, abilityName, value)
	if abilityName ~= ABILITY_NAME then
		return false
	end

	if eventName == "Activated" then
		return true
	end

	if eventName == "Denied" then
		if value == "ResolveNotReady" then
			local burrowState = self:GetLocalBurrowState()
			if burrowState and not burrowState.ResolveInProgress then
				burrowState.SurfaceRequested = false
				burrowState.ResolveRequestReason = nil
			end
			logInfo("Q ignored player=%s reason=server_resolve_not_ready", self.player.Name)
			return true
		end
		local burrowState = self:GetLocalBurrowState()
		if burrowState and burrowState.SurfaceRequested and not burrowState.ResolveInProgress then
			burrowState.SurfaceRequested = false
			burrowState.ResolveRequestReason = nil
			logWarn(
				"resolve request denied player=%s reason=%s phase=%s",
				self.player.Name,
				tostring(value or "unknown"),
				getBurrowStatePhase(burrowState)
			)
			return true
		end
		if value == "Airborne" or value == "NotGrounded" or value == "NoGround" then
			local shouldShowGroundFeedback = true
			if value == "NotGrounded" or value == "NoGround" then
				local humanoid = self.getHumanoid()
				local hardAirborne, floorMaterialAir = getHumanoidGroundState(humanoid)
				shouldShowGroundFeedback = hardAirborne or floorMaterialAir
			end
			self:RejectGroundedOnlyBurrow(tostring(value), 0, shouldShowGroundFeedback)
		end
		self:CancelServerConfirmedBurrowStart("server_denied")
		self:CancelLocalStartFeedback("server_denied")
		return true
	end

	return false
end

function MoguClient:Update(dt)
	self:UpdatePendingLocalStartFeedback()

	local now = Workspace:GetServerTimeNow()
	local abilityConfig = getAbilityConfig()
	for targetPlayer, burrowState in pairs(self.burrowStates) do
		if burrowState.ResolveInProgress then
			self:UpdateTrailState(targetPlayer, burrowState, now, abilityConfig)
		elseif now > (burrowState.EndTime + MoguBurrowShared.GetSurfaceResolveGrace(abilityConfig)) and not burrowState.IsLocal then
			self:StopBurrow(targetPlayer, {
				ActualEndPosition = getRootPart(targetPlayer) and getRootPart(targetPlayer).Position or nil,
				ResolveBurstRadius = burrowState.ResolveBurstRadius,
			})
		else
			self:UpdateTrailState(targetPlayer, burrowState, now, abilityConfig)
			if burrowState.IsLocal then
				self:UpdateLocalBurrowState(burrowState, dt or 0, now, abilityConfig)
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
	self:CancelServerConfirmedBurrowStart("character_removing")
	self:CancelLocalStartFeedback("character_removing")
	local localBurrowState = self.burrowStates[self.player]
	if localBurrowState then
		local humanoid = self.getHumanoid()
		if humanoid then
			humanoid.AutoRotate = localBurrowState.OriginalAutoRotate ~= false
			restorePositiveWalkSpeed(self.player, humanoid, localBurrowState.OriginalWalkSpeed, "character_removing")
		end
	end

	for targetPlayer in pairs(self.burrowStates) do
		clearBurrowCueState(self.burrowStates[targetPlayer])
		clearBurrowLifecycleState(self.burrowStates[targetPlayer])
		self.animationController:StopAnimation(self.burrowStates[targetPlayer].AnimationState, "character_removing")
		self.burrowStates[targetPlayer] = nil
		self:ClearVisualBurrowOffset(targetPlayer, false)
		self:ClearConceal(targetPlayer)
		if targetPlayer == self.player then
			self:ReleaseStartupMovementLock(localBurrowState, "character_removing")
			self:RestoreBurrowCameraStabilization(localBurrowState, "character_removing")
			self:RestoreBurrowPhysicsState(localBurrowState, "character_removing")
		end
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
		self:CancelServerConfirmedBurrowStart("player_removing")
		self:CancelLocalStartFeedback("player_removing")
		self:ReleaseStartupMovementLock(self.burrowStates[leavingPlayer], "player_removing")
		self:RestoreBurrowCameraStabilization(self.burrowStates[leavingPlayer], "player_removing")
	end
	clearBurrowCueState(self.burrowStates[leavingPlayer])
	clearBurrowLifecycleState(self.burrowStates[leavingPlayer])
	self.animationController:StopAnimation(self.burrowStates[leavingPlayer] and self.burrowStates[leavingPlayer].AnimationState, "player_removing")
	self.burrowStates[leavingPlayer] = nil
	self:ClearVisualBurrowOffset(leavingPlayer, false)
	self:ClearConceal(leavingPlayer)
	self.vfxController:HandlePlayerRemoving(leavingPlayer)
	self:RecordCleanup()
	self:PublishDiagnostics(true)
end

return MoguClient
