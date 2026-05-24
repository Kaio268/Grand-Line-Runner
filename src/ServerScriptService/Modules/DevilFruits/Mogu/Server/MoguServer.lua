local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local MoguBurrowShared = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguBurrowShared")
)
local MoguAnimationController = require(script.Parent:WaitForChild("MoguAnimationController"))
local DamageProtection = require(script.Parent.Parent.Parent:WaitForChild("Server"):WaitForChild("DamageProtection"))

local MoguServer = {}
local BURROW_PROTECTED_UNTIL_ATTRIBUTE = "MoguBurrowProtectedUntil"
local MOGU_STARTUP_INVINCIBLE_FROM_ATTRIBUTE = "MoguStartupInvincibleFrom"
local MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE = "MoguStartupInvincibleUntil"
local MOGU_STARTUP_INVINCIBLE_SECONDS_ATTRIBUTE = "MoguStartupInvincibleSeconds"
local MOGU_STARTUP_INVINCIBLE_START_OFFSET_SECONDS_ATTRIBUTE = "MoguStartupInvincibleStartOffsetSeconds"
local MOGU_STARTUP_INVINCIBLE_SESSION_ID_ATTRIBUTE = "MoguStartupInvincibleSessionId"
local MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE = "MoguMovementLockUntil"
local MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE = "MoguMovementLockSpeedMultiplier"
local BURROW_SESSION_ID_ATTRIBUTE = "MoguBurrowSessionId"
local BURROW_SESSION_STATE_ATTRIBUTE = "MoguBurrowSessionState"
local PROTECTION_GUARD_REASON_ATTRIBUTE = "MoguProtectionGuardReason"
local PROTECTION_GUARD_COUNT_ATTRIBUTE = "MoguProtectionGuardCount"
local PROTECTION_GUARD_LAST_AT_ATTRIBUTE = "MoguProtectionGuardLastAt"
local WORKSPACE_ANIMATION_RIG_NAME = "Mogu"
local ABILITY_NAME = "Burrow"
local PHASE_START = "Start"
local PHASE_RESOLVE = "Resolve"
local SESSION_STATE_STARTUP = "Startup"
local SESSION_STATE_UNDERGROUND = "Underground"
local SESSION_STATE_RESOLVING = "Resolving"
local SESSION_STATE_CLEANUP = "Cleanup"
local RESOLVE_REASON_DURATION_ELAPSED = "duration_elapsed"
local RESOLVE_REASON_MANUAL_SURFACE = "manual_surface"
local CLEAR_REASON_EXPIRED = "expired"
local CLEAR_REASON_RESOLVE = "resolve"
local CLEAR_REASON_RUNTIME_RESET = "runtime_reset"
local CLEAR_REASON_CHARACTER_REMOVING = "character_removing"
local CLEAR_REASON_HUMANOID_DIED = "humanoid_died"
local CLEAR_REASON_PLAYER_REMOVING = "player_removing"
local RESOLVE_VALIDATION_DISTANCE_PADDING = 8
local START_POSITION_VALIDATION_DISTANCE = 8
local ZERO_VELOCITY_EPSILON = 0.025
local DEFAULT_MIN_MANUAL_RESOLVE_DELAY = 0.5
local PROTECTION_GUARD_SWEEP_INTERVAL = 0.1
local PROTECTION_EXPIRY_GRACE = 0.35
local MOVEMENT_LOCK_APPLY_GRACE = 0.25
local LOCKED_WALKSPEED_EPSILON = 0.1
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.5
local WARN_COOLDOWN = 3
local PROTECTION_REASON_WITHOUT_SESSION = "protection_without_session"
local PROTECTION_REASON_STALE_SESSION = "protection_stale_session"
local PROTECTION_REASON_INVALID_STATE = "protection_invalid_state"
local PROTECTION_REASON_EXPIRED = "protection_expired"
local PROTECTION_REASON_CHARACTER_MISMATCH = "protection_character_mismatch"
local PROTECTION_REASON_NORMAL_MOVEMENT = "protection_normal_movement"
local PROTECTION_REASON_REJECTED_START = "protection_rejected_start"
local PROTECTION_REASON_AIRBORNE_REJECT = "protection_airborne_reject"
local PROTECTION_REASON_RESOLVE_CLEANUP = "protection_resolve_cleanup"
local PROTECTION_REASON_TIMEOUT_CLEANUP = "protection_timeout_cleanup"
local PROTECTION_REASON_RUNTIME_RESET = "protection_runtime_reset"
local PROTECTION_REASON_DEATH_CLEANUP = "protection_death_cleanup"
local PROTECTION_REASON_PLAYER_REMOVING = "protection_player_removing"

local activeBurrowsByPlayer = setmetatable({}, { __mode = "k" })
local nextSessionSerial = 0
local protectionGuardAccumulator = 0
local IMMUNE_ELIGIBLE_SESSION_STATES = {
	[SESSION_STATE_STARTUP] = true,
	[SESSION_STATE_UNDERGROUND] = true,
	[SESSION_STATE_RESOLVING] = true,
}

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguServer:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU SERVER][WARN] " .. message, ...))
end

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguServer:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU SERVER] " .. message, ...))
end

local function getStartAnimationConfig(abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and type(animationConfig.Start) == "table" and animationConfig.Start or {}
end

local function getMinimumManualResolveDelay(abilityConfig)
	local startConfig = getStartAnimationConfig(abilityConfig)
	return math.max(
		0,
		tonumber(abilityConfig and abilityConfig.MinManualResolveDelay)
			or tonumber(startConfig.MinManualResolveDelay)
			or tonumber(startConfig.EntryCueFallbackTime)
			or DEFAULT_MIN_MANUAL_RESOLVE_DELAY
	)
end

local function shouldRequireGroundedBurrowStart(abilityConfig)
	local startConfig = getStartAnimationConfig(abilityConfig)
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

local function getBurrowGroundContactTolerance(abilityConfig)
	local startConfig = getStartAnimationConfig(abilityConfig)
	return math.max(
		0,
		tonumber(startConfig.BurrowGroundContactTolerance)
			or tonumber(startConfig.BurrowGroundContactDistance)
			or tonumber(abilityConfig and abilityConfig.BurrowGroundContactTolerance)
			or tonumber(abilityConfig and abilityConfig.BurrowGroundContactDistance)
			or 0.6
	)
end

local function getHumanoidGroundState(humanoid)
	if not humanoid then
		return true, true, nil, nil
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

local function setGroundedStartDiagnostics(player, state, reason, dropDistance)
	if not player or not player:IsA("Player") then
		return
	end

	player:SetAttribute("MoguGroundedServerState", state)
	player:SetAttribute("MoguGroundedServerReason", reason)
	player:SetAttribute("MoguGroundedServerDropDistance", dropDistance)
	player:SetAttribute("MoguAirborneServerState", nil)
	player:SetAttribute("MoguAirborneServerReason", nil)
	player:SetAttribute("MoguAirborneServerDropDistance", nil)
end

local function getPlanarDirection(direction)
	if typeof(direction) ~= "Vector3" then
		return nil
	end

	local planarDirection = Vector3.new(direction.X, 0, direction.Z)
	if planarDirection.Magnitude <= 0.01 then
		return nil
	end

	return planarDirection.Unit
end

local function zeroRootVelocity(rootPart)
	if not rootPart then
		return false
	end

	local wrote = false
	if rootPart.AssemblyLinearVelocity.Magnitude > ZERO_VELOCITY_EPSILON then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		wrote = true
	end
	if rootPart.AssemblyAngularVelocity.Magnitude > ZERO_VELOCITY_EPSILON then
		rootPart.AssemblyAngularVelocity = Vector3.zero
		wrote = true
	end
	return wrote
end

local function getTrustedPredictedStartPosition(requestPayload, rootPart, player)
	if type(requestPayload) ~= "table" or not rootPart then
		return nil, nil
	end

	local predictedStartPosition = requestPayload.PredictedStartPosition
	if typeof(predictedStartPosition) ~= "Vector3" then
		return nil, nil
	end

	local distance = (predictedStartPosition - rootPart.Position).Magnitude
	if distance <= START_POSITION_VALIDATION_DISTANCE then
		return predictedStartPosition, distance
	end

	logWarn(
		"predicted start rejected player=%s distance=%.2f limit=%.2f",
		player and player.Name or "<nil>",
		distance,
		START_POSITION_VALIDATION_DISTANCE
	)
	return nil, distance
end

local function getRequestedResolveEndPosition(requestPayload)
	if type(requestPayload) ~= "table" then
		return nil, nil
	end

	local currentSurfacePosition = requestPayload.CurrentSurfacePosition
	if typeof(currentSurfacePosition) == "Vector3" then
		return currentSurfacePosition, "CurrentSurfacePosition"
	end

	local predictedEndPosition = requestPayload.PredictedEndPosition
	if typeof(predictedEndPosition) == "Vector3" then
		return predictedEndPosition, "PredictedEndPosition"
	end

	local surfaceRootPosition = requestPayload.SurfaceRootPosition
	if typeof(surfaceRootPosition) == "Vector3" then
		return surfaceRootPosition, "SurfaceRootPosition"
	end

	return nil, nil
end

local function getRequestedSessionId(requestPayload)
	if type(requestPayload) ~= "table" then
		return nil
	end

	local sessionId = requestPayload.SessionId
	if typeof(sessionId) == "string" and sessionId ~= "" then
		return sessionId
	end

	return nil
end

local function createSessionId(player)
	nextSessionSerial += 1
	return string.format(
		"%d:%d:%.3f",
		player and player.UserId or 0,
		nextSessionSerial,
		Workspace:GetServerTimeNow()
	)
end

local function faceCharacterAlongDirection(character, rootPart, direction)
	local planarDirection = getPlanarDirection(direction)
	if not character or not rootPart or not planarDirection then
		return
	end

	local rootPosition = rootPart.Position
	local targetRootCFrame = CFrame.lookAt(rootPosition, rootPosition + planarDirection, Vector3.yAxis)
	local pivotToRoot = character:GetPivot():ToObjectSpace(rootPart.CFrame)
	character:PivotTo(targetRootCFrame * pivotToRoot:Inverse())
	zeroRootVelocity(rootPart)
end

local function getPlanarDelta(fromPosition, toPosition)
	if typeof(fromPosition) ~= "Vector3" or typeof(toPosition) ~= "Vector3" then
		return nil
	end

	return Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
end

local function clampResolvePositionToAuthorizedDistance(burrowState, requestedEndPosition, endedAt)
	local startPosition = burrowState and burrowState.StartPosition
	if typeof(startPosition) ~= "Vector3" or typeof(requestedEndPosition) ~= "Vector3" then
		return requestedEndPosition, 0
	end

	local planarDelta = getPlanarDelta(startPosition, requestedEndPosition)
	if not planarDelta or planarDelta.Magnitude <= 0.01 then
		return requestedEndPosition, 0
	end

	local elapsed = math.clamp(
		(tonumber(endedAt) or tonumber(burrowState.StartedAt) or 0)
			- (tonumber(burrowState.StartedAt) or tonumber(endedAt) or 0),
		0,
		math.max(0, tonumber(burrowState.Duration) or 0) + MoguBurrowShared.GetSurfaceResolveGrace(burrowState.AbilityConfig)
	)
	local maxTravelDistance = (
		math.max(0, tonumber(burrowState.MoveSpeed) or MoguBurrowShared.GetMoveSpeed(burrowState.AbilityConfig))
			* elapsed
	)
		+ RESOLVE_VALIDATION_DISTANCE_PADDING
	local planarDistance = planarDelta.Magnitude
	if planarDistance <= maxTravelDistance then
		return requestedEndPosition, 0
	end

	local clampedPlanarDelta = planarDelta.Unit * maxTravelDistance
	return Vector3.new(
		startPosition.X + clampedPlanarDelta.X,
		requestedEndPosition.Y,
		startPosition.Z + clampedPlanarDelta.Z
	), planarDistance - maxTravelDistance
end

local function clampResolvePositionToWallSafeSide(context, burrowState, requestedEndPosition)
	if type(context) ~= "table" or type(burrowState) ~= "table" then
		return requestedEndPosition, false, nil, nil, 0
	end
	if typeof(requestedEndPosition) ~= "Vector3" then
		return requestedEndPosition, false, nil, nil, 0
	end

	local character = context.Character
	local rootPart = context.RootPart
	if not character or not rootPart then
		return requestedEndPosition, false, nil, nil, 0
	end

	local lastSafePosition = burrowState.LastSafeSurfaceRootPosition or burrowState.StartPosition
	if typeof(lastSafePosition) ~= "Vector3" then
		return requestedEndPosition, false, nil, nil, 0
	end

	local wallSafePosition, blocked, blockResult, blockInfo = MoguBurrowShared.ResolvePlanarMovement(
		character,
		rootPart,
		lastSafePosition,
		requestedEndPosition,
		context.AbilityConfig or burrowState.AbilityConfig
	)
	if not blocked or typeof(wallSafePosition) ~= "Vector3" then
		return requestedEndPosition, false, blockResult, blockInfo, 0
	end

	local correctionDelta = getPlanarDelta(wallSafePosition, requestedEndPosition)
	local correctionDistance = correctionDelta and correctionDelta.Magnitude or 0
	return wallSafePosition, true, blockResult, blockInfo, correctionDistance
end

local function hideWorkspaceAnimationRig(instance)
	if not instance or instance.Name ~= WORKSPACE_ANIMATION_RIG_NAME or not instance:FindFirstChild("AnimSaves") then
		return
	end

	instance:SetAttribute("MoguRuntimeHidden", true)
	local humanoids = {}
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoids[#humanoids + 1] = descendant
		end
	end

	for _, humanoid in ipairs(humanoids) do
		humanoid:Destroy()
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

hideWorkspaceAnimationRig(Workspace:FindFirstChild(WORKSPACE_ANIMATION_RIG_NAME))
Workspace.ChildAdded:Connect(hideWorkspaceAnimationRig)

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function normalizeProtectionClearReason(reason)
	if reason == CLEAR_REASON_RESOLVE then
		return PROTECTION_REASON_RESOLVE_CLEANUP
	elseif reason == CLEAR_REASON_EXPIRED then
		return PROTECTION_REASON_TIMEOUT_CLEANUP
	elseif reason == CLEAR_REASON_RUNTIME_RESET then
		return PROTECTION_REASON_RUNTIME_RESET
	elseif reason == CLEAR_REASON_HUMANOID_DIED then
		return PROTECTION_REASON_DEATH_CLEANUP
	elseif reason == CLEAR_REASON_CHARACTER_REMOVING then
		return PROTECTION_REASON_CHARACTER_MISMATCH
	elseif reason == CLEAR_REASON_PLAYER_REMOVING then
		return PROTECTION_REASON_PLAYER_REMOVING
	elseif reason == "Airborne" then
		return PROTECTION_REASON_AIRBORNE_REJECT
	elseif reason == "NotGrounded" or reason == "NoGround" then
		return PROTECTION_REASON_REJECTED_START
	elseif typeof(reason) == "string" and reason ~= "" then
		return reason
	end

	return PROTECTION_REASON_WITHOUT_SESSION
end

local function clearStartupInvincibilityState(player)
	if not player or not player:IsA("Player") then
		return
	end

	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_FROM_ATTRIBUTE, nil)
	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE, nil)
	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_SECONDS_ATTRIBUTE, nil)
	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_START_OFFSET_SECONDS_ATTRIBUTE, nil)
	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_SESSION_ID_ATTRIBUTE, nil)
end

local function clearProtectionState(player)
	if not player or not player:IsA("Player") then
		return
	end

	player:SetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE, nil)
	clearStartupInvincibilityState(player)
end

local function clearSessionAttributes(player)
	if not player or not player:IsA("Player") then
		return
	end

	player:SetAttribute(BURROW_SESSION_ID_ATTRIBUTE, nil)
	player:SetAttribute(BURROW_SESSION_STATE_ATTRIBUTE, nil)
end

local function setSessionAttributes(player, burrowState)
	if not player or not player:IsA("Player") or type(burrowState) ~= "table" then
		return
	end

	player:SetAttribute(BURROW_SESSION_ID_ATTRIBUTE, burrowState.SessionId)
	player:SetAttribute(BURROW_SESSION_STATE_ATTRIBUTE, burrowState.State)
end

local function setSessionState(player, burrowState, state, reason)
	if type(burrowState) ~= "table" or typeof(state) ~= "string" or state == "" then
		return false
	end

	if burrowState.State == state then
		return false
	end

	local previousState = burrowState.State
	burrowState.State = state
	setSessionAttributes(player, burrowState)
	logInfo(
		"session state player=%s session=%s %s -> %s reason=%s",
		player and player.Name or "<nil>",
		tostring(burrowState.SessionId),
		tostring(previousState or "<nil>"),
		state,
		tostring(reason or "unspecified")
	)
	return true
end

local function setStartupInvincibilityState(player, burrowState)
	if not player or not player:IsA("Player") or type(burrowState) ~= "table" then
		return
	end

	local invincibleUntil = tonumber(burrowState.StartupInvincibilityUntil)
	if not invincibleUntil or invincibleUntil <= getSharedTimestamp() then
		clearStartupInvincibilityState(player)
		return
	end

	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_FROM_ATTRIBUTE, tonumber(burrowState.StartupInvincibilityFrom) or nil)
	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE, invincibleUntil)
	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_SECONDS_ATTRIBUTE, tonumber(burrowState.StartupInvincibilityMaxSeconds) or 0)
	player:SetAttribute(
		MOGU_STARTUP_INVINCIBLE_START_OFFSET_SECONDS_ATTRIBUTE,
		tonumber(burrowState.StartupInvincibilityStartOffsetSeconds) or 0
	)
	player:SetAttribute(MOGU_STARTUP_INVINCIBLE_SESSION_ID_ATTRIBUTE, burrowState.SessionId)
	DamageProtection.TraceMoguStartupDamage(player, {
		Path = "MoguServer.setStartupInvincibilityState",
		Source = "MoguServer",
	})
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

local function clearMovementLockState(player)
	if not player or not player:IsA("Player") then
		return
	end

	player:SetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE, nil)
	player:SetAttribute(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE, nil)
end

local function hasMoguRuntimeProtection(player)
	if not player or not player:IsA("Player") then
		return false
	end

	return typeof(player:GetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE)) == "number"
		or typeof(player:GetAttribute(MOGU_STARTUP_INVINCIBLE_UNTIL_ATTRIBUTE)) == "number"
		or typeof(player:GetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE)) == "number"
		or player:GetAttribute(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE) ~= nil
end

local function hasMoguRuntimeState(player)
	if not player or not player:IsA("Player") then
		return false
	end

	return hasMoguRuntimeProtection(player)
		or player:GetAttribute(BURROW_SESSION_ID_ATTRIBUTE) ~= nil
		or player:GetAttribute(BURROW_SESSION_STATE_ATTRIBUTE) ~= nil
end

local function getProtectionDiagnosticSnapshot(player, burrowState)
	local session = if type(burrowState) == "table" then burrowState else activeBurrowsByPlayer[player]
	local character = player and player.Character or nil
	local sessionCharacter = type(session) == "table" and session.Character or nil
	local humanoid = if sessionCharacter then sessionCharacter:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid and character then
		humanoid = character:FindFirstChildOfClass("Humanoid")
	end
	local rootPart = if sessionCharacter then sessionCharacter:FindFirstChild("HumanoidRootPart") else nil
	if not rootPart and character then
		rootPart = character:FindFirstChild("HumanoidRootPart")
	end
	local movementLockUntil = player and player:GetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE) or nil
	local movementLockSpeedMultiplier = player and player:GetAttribute(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE) or nil
	local protectedUntil = player and player:GetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE) or nil
	local movementLockActive = typeof(movementLockUntil) == "number"
		and movementLockUntil > os.clock()
		and typeof(movementLockSpeedMultiplier) == "number"
		and movementLockSpeedMultiplier <= 0

	return {
		HasSession = type(session) == "table",
		SessionId = type(session) == "table" and session.SessionId or player and player:GetAttribute(BURROW_SESSION_ID_ATTRIBUTE),
		State = type(session) == "table" and session.State or player and player:GetAttribute(BURROW_SESSION_STATE_ATTRIBUTE),
		CharacterMatches = type(session) == "table" and sessionCharacter ~= nil and character == sessionCharacter or false,
		MovementLockActive = movementLockActive,
		MovementLockUntil = movementLockUntil,
		MovementLockSpeedMultiplier = movementLockSpeedMultiplier,
		ProtectedUntil = protectedUntil,
		WalkSpeed = humanoid and humanoid.WalkSpeed or nil,
		HumanoidState = humanoid and humanoid:GetState().Name or nil,
		RootPlanarSpeed = rootPart and Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude or nil,
	}
end

local function setProtectionGuardDiagnostics(player, reason, burrowState, snapshot)
	if not player or not player:IsA("Player") then
		return
	end

	snapshot = snapshot or getProtectionDiagnosticSnapshot(player, burrowState)
	local resolvedReason = normalizeProtectionClearReason(reason)
	player:SetAttribute(PROTECTION_GUARD_REASON_ATTRIBUTE, resolvedReason)
	player:SetAttribute(PROTECTION_GUARD_LAST_AT_ATTRIBUTE, getSharedTimestamp())
	player:SetAttribute(PROTECTION_GUARD_COUNT_ATTRIBUTE, (tonumber(player:GetAttribute(PROTECTION_GUARD_COUNT_ATTRIBUTE)) or 0) + 1)
	player:SetAttribute("MoguProtectionGuardSessionId", snapshot.SessionId)
	player:SetAttribute("MoguProtectionGuardState", snapshot.State)
	player:SetAttribute("MoguProtectionGuardHasSession", snapshot.HasSession)
	player:SetAttribute("MoguProtectionGuardCharacterMatches", snapshot.CharacterMatches)
	player:SetAttribute("MoguProtectionGuardMovementLockActive", snapshot.MovementLockActive)
	player:SetAttribute("MoguProtectionGuardMovementLockUntil", snapshot.MovementLockUntil)
	player:SetAttribute("MoguProtectionGuardMovementLockSpeedMultiplier", snapshot.MovementLockSpeedMultiplier)
	player:SetAttribute("MoguProtectionGuardProtectedUntil", snapshot.ProtectedUntil)
	player:SetAttribute("MoguProtectionGuardWalkSpeed", snapshot.WalkSpeed)
	player:SetAttribute("MoguProtectionGuardHumanoidState", snapshot.HumanoidState)
	player:SetAttribute("MoguProtectionGuardRootPlanarSpeed", snapshot.RootPlanarSpeed)
end

local function clearInvalidProtection(player, reason, options)
	if not player or not player:IsA("Player") then
		return false
	end

	options = type(options) == "table" and options or {}
	local burrowState = if type(options.BurrowState) == "table" then options.BurrowState else activeBurrowsByPlayer[player]
	local snapshot = getProtectionDiagnosticSnapshot(player, burrowState)
	local resolvedReason = normalizeProtectionClearReason(reason)
	local hadRuntimeProtection = hasMoguRuntimeProtection(player)
	clearProtectionState(player)
	clearMovementLockState(player)
	if options.ClearSessionAttributes == true then
		clearSessionAttributes(player)
	end

	if hadRuntimeProtection or options.ForceDiagnostic == true then
		setProtectionGuardDiagnostics(player, resolvedReason, burrowState, snapshot)
		logWarn(
			"mogu protection cleared player=%s reason=%s session=%s state=%s hasSession=%s characterMatches=%s movementLockActive=%s protectedUntil=%s movementLockUntil=%s movementLockSpeed=%s walkSpeed=%s rootPlanarSpeed=%s hadRuntimeProtection=%s",
			player.Name,
			resolvedReason,
			tostring(snapshot.SessionId),
			tostring(snapshot.State),
			tostring(snapshot.HasSession),
			tostring(snapshot.CharacterMatches),
			tostring(snapshot.MovementLockActive),
			tostring(snapshot.ProtectedUntil),
			tostring(snapshot.MovementLockUntil),
			tostring(snapshot.MovementLockSpeedMultiplier),
			tostring(snapshot.WalkSpeed),
			tostring(snapshot.RootPlanarSpeed),
			tostring(hadRuntimeProtection)
		)
	end

	return hadRuntimeProtection
end

local function getMovementLockIneligibleReason(player, burrowState)
	if not player or not player:IsA("Player") then
		return PROTECTION_REASON_WITHOUT_SESSION
	end

	local movementLockUntil = player:GetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE)
	if typeof(movementLockUntil) ~= "number" then
		return PROTECTION_REASON_INVALID_STATE
	end

	local movementLockSpeedMultiplier = player:GetAttribute(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE)
	if typeof(movementLockSpeedMultiplier) ~= "number" or movementLockSpeedMultiplier > 0 then
		return PROTECTION_REASON_INVALID_STATE
	end

	if movementLockUntil <= os.clock() then
		return PROTECTION_REASON_EXPIRED
	end

	local elapsed = getSharedTimestamp() - (tonumber(burrowState and burrowState.StartedAt) or getSharedTimestamp())
	if elapsed <= MOVEMENT_LOCK_APPLY_GRACE then
		return nil
	end

	local humanoid = burrowState and burrowState.Humanoid
	if not humanoid and player.Character then
		humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	end
	if humanoid and humanoid.WalkSpeed > LOCKED_WALKSPEED_EPSILON then
		return PROTECTION_REASON_NORMAL_MOVEMENT
	end

	return nil
end

local function getProtectionExpiryIneligibleReason(player, burrowState)
	local protectedUntil = player and player:GetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE) or nil
	if typeof(protectedUntil) ~= "number" then
		return PROTECTION_REASON_INVALID_STATE
	end
	if protectedUntil <= getSharedTimestamp() then
		return PROTECTION_REASON_EXPIRED
	end

	local maxProtectionUntil = (tonumber(burrowState and burrowState.StartedAt) or getSharedTimestamp())
		+ math.max(0, tonumber(burrowState and burrowState.Duration) or 0)
		+ MoguBurrowShared.GetSurfaceResolveGrace(burrowState and burrowState.AbilityConfig)
		+ PROTECTION_EXPIRY_GRACE
	if protectedUntil > maxProtectionUntil then
		return PROTECTION_REASON_EXPIRED
	end

	return nil
end

local function getProtectionIneligibleReason(player, burrowState)
	if type(burrowState) ~= "table" then
		return PROTECTION_REASON_WITHOUT_SESSION
	end
	if player and activeBurrowsByPlayer[player] ~= burrowState then
		return PROTECTION_REASON_WITHOUT_SESSION
	end
	if not player or not player:IsA("Player") then
		return PROTECTION_REASON_WITHOUT_SESSION
	end

	if burrowState.Character == nil or burrowState.Character.Parent == nil or player.Character ~= burrowState.Character then
		return PROTECTION_REASON_CHARACTER_MISMATCH
	end

	local sessionId = player:GetAttribute(BURROW_SESSION_ID_ATTRIBUTE)
	if typeof(burrowState.SessionId) ~= "string" or burrowState.SessionId == "" or sessionId ~= burrowState.SessionId then
		return PROTECTION_REASON_STALE_SESSION
	end

	local sessionState = player:GetAttribute(BURROW_SESSION_STATE_ATTRIBUTE)
	if IMMUNE_ELIGIBLE_SESSION_STATES[burrowState.State] ~= true then
		return PROTECTION_REASON_INVALID_STATE
	end
	if sessionState ~= burrowState.State then
		return PROTECTION_REASON_STALE_SESSION
	end

	local expiryReason = getProtectionExpiryIneligibleReason(player, burrowState)
	if expiryReason then
		return expiryReason
	end

	local movementLockReason = getMovementLockIneligibleReason(player, burrowState)
	if movementLockReason then
		return movementLockReason
	end

	return nil
end

local function setProtectionState(player, untilTimestamp)
	if not player or not player:IsA("Player") then
		return
	end

	if typeof(untilTimestamp) ~= "number" or untilTimestamp <= getSharedTimestamp() then
		clearProtectionState(player)
		return
	end

	player:SetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE, untilTimestamp)
end

local function setMovementLockState(player, untilTimestamp)
	if not player or not player:IsA("Player") then
		return
	end

	local remainingDuration = if typeof(untilTimestamp) == "number" then untilTimestamp - getSharedTimestamp() else 0
	if remainingDuration <= 0 then
		clearMovementLockState(player)
		return
	end

	player:SetAttribute(MOGU_MOVEMENT_LOCK_UNTIL_ATTRIBUTE, os.clock() + remainingDuration)
	player:SetAttribute(MOGU_MOVEMENT_LOCK_SPEED_ATTRIBUTE, 0)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.WalkSpeed > LOCKED_WALKSPEED_EPSILON then
		humanoid.WalkSpeed = 0
	end
end

local function clearActiveBurrow(player, reason)
	if not player or not player:IsA("Player") then
		return nil
	end

	local burrowState = activeBurrowsByPlayer[player]
	activeBurrowsByPlayer[player] = nil
	clearInvalidProtection(player, normalizeProtectionClearReason(reason), {
		BurrowState = burrowState,
		ClearSessionAttributes = true,
		ForceDiagnostic = burrowState ~= nil,
	})

	if not burrowState then
		return nil
	end

	burrowState.State = SESSION_STATE_CLEANUP
	burrowState.CleanupReason = reason
	disconnectConnections(burrowState.Connections)
	burrowState.Connections = nil
	burrowState.TimeoutToken = nil
	burrowState.StateToken = nil
	MoguAnimationController.StopAnimation(burrowState.AnimationState, reason)
	return burrowState
end

local function getActiveBurrow(player)
	local burrowState = activeBurrowsByPlayer[player]
	if not burrowState then
		return nil
	end

	if burrowState.State == SESSION_STATE_CLEANUP then
		clearActiveBurrow(player, CLEAR_REASON_RUNTIME_RESET)
		return nil
	end

	local character = burrowState.Character
	local humanoid = burrowState.Humanoid
	if not character or character.Parent == nil or player.Character ~= character then
		clearActiveBurrow(player, CLEAR_REASON_CHARACTER_REMOVING)
		return nil
	end
	if humanoid and humanoid.Health <= 0 then
		clearActiveBurrow(player, CLEAR_REASON_HUMANOID_DIED)
		return nil
	end

	if getSharedTimestamp() > (burrowState.EndTime + MoguBurrowShared.GetSurfaceResolveGrace(burrowState.AbilityConfig)) then
		clearActiveBurrow(player, CLEAR_REASON_EXPIRED)
		return nil
	end

	local ineligibleReason = getProtectionIneligibleReason(player, burrowState)
	if ineligibleReason then
		clearActiveBurrow(player, ineligibleReason)
		return nil
	end

	return burrowState
end

local function isBurrowStateUnderground(burrowState)
	if type(burrowState) ~= "table" or burrowState.State ~= SESSION_STATE_UNDERGROUND then
		return false
	end

	local now = getSharedTimestamp()
	local undergroundAt = tonumber(burrowState.UndergroundAt)
	if undergroundAt and now < undergroundAt then
		return false
	end

	local endTime = tonumber(burrowState.EndTime)
	if endTime and now >= endTime then
		return false
	end

	return true
end

local function isStartupInvincibilityActive(player, burrowState, now)
	if type(burrowState) ~= "table" or burrowState.State ~= SESSION_STATE_STARTUP then
		return false
	end

	if not player or not player:IsA("Player") then
		return false
	end

	local sessionId = player:GetAttribute(BURROW_SESSION_ID_ATTRIBUTE)
	if typeof(burrowState.SessionId) ~= "string" or burrowState.SessionId == "" or sessionId ~= burrowState.SessionId then
		return false
	end

	local invincibleFrom = tonumber(burrowState.StartupInvincibilityFrom)
	if invincibleFrom and now < invincibleFrom then
		return false
	end

	local invincibleUntil = tonumber(burrowState.StartupInvincibilityUntil)
	if not invincibleUntil or invincibleUntil <= now then
		return false
	end

	local endTime = tonumber(burrowState.EndTime)
	if endTime and now >= endTime then
		return false
	end

	return true
end

local function buildStartPayload(context, burrowState, startedAt, endsAt, direction, directionSource, startPosition)
	local abilityConfig = context.AbilityConfig or {}
	local resolvedStartPosition = startPosition or context.RootPart.Position
	local hazardProtectionRadius = math.max(0, tonumber(abilityConfig.HazardProtectionRadius) or 0)

	return {
		Phase = PHASE_START,
		SessionId = burrowState and burrowState.SessionId or nil,
		ServerState = burrowState and burrowState.State or SESSION_STATE_STARTUP,
		UndergroundAt = burrowState and burrowState.UndergroundAt or nil,
		StartedAt = startedAt,
		EndTime = endsAt,
		Duration = endsAt - startedAt,
		MoveSpeed = MoguBurrowShared.GetMoveSpeed(abilityConfig),
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = resolvedStartPosition,
		EntryBurstRadius = MoguBurrowShared.GetEntryBurstRadius(abilityConfig),
		ResolveBurstRadius = MoguBurrowShared.GetResolveBurstRadius(abilityConfig),
		HazardProtectionRadius = hazardProtectionRadius,
		HitboxDebugMode = "FollowTargetRoot",
		HitboxDebugRadius = hazardProtectionRadius,
		HitboxVisualDuration = endsAt - startedAt,
		ConcealTransparency = MoguBurrowShared.GetConcealTransparency(abilityConfig),
		TrailInterval = MoguBurrowShared.GetTrailInterval(abilityConfig),
	}
end

local function buildResolvePayload(context, burrowState, endedAt, resolveReason)
	local abilityConfig = context.AbilityConfig or {}
	local rootPart = context.RootPart
	local character = context.Character
	local requestedEndPosition, requestedEndSource = getRequestedResolveEndPosition(context.RequestPayload)
	local fallbackEndPosition = burrowState.LastSafeSurfaceRootPosition or burrowState.StartPosition
	local actualEndPosition = requestedEndPosition or (rootPart and rootPart.Position) or burrowState.StartPosition
	local resolveCorrectionDistance = 0
	if requestedEndPosition then
		logInfo(
			"resolve requested end player=%s source=%s requested=%s serverRoot=%s",
			context.Player and context.Player.Name or "<nil>",
			tostring(requestedEndSource),
			tostring(requestedEndPosition),
			tostring(rootPart and rootPart.Position or nil)
		)
	end
	actualEndPosition, resolveCorrectionDistance =
		clampResolvePositionToAuthorizedDistance(burrowState, actualEndPosition, endedAt)
	local wallBlocked = false
	local wallBlockInfo = nil
	if character and rootPart and typeof(actualEndPosition) == "Vector3" then
		local wallSafePosition, didWallBlock, blockResult, blockInfo, wallCorrectionDistance =
			clampResolvePositionToWallSafeSide(context, burrowState, actualEndPosition)
		if didWallBlock and typeof(wallSafePosition) == "Vector3" then
			wallBlocked = true
			wallBlockInfo = blockInfo
			resolveCorrectionDistance += wallCorrectionDistance
			logWarn(
				"resolve wall clamp player=%s requested=%s accepted=%s hit=%s reason=%s distance=%.2f acceptedDistance=%.2f correction=%.2f",
				context.Player and context.Player.Name or "<nil>",
				tostring(actualEndPosition),
				tostring(wallSafePosition),
				tostring(blockResult and blockResult.Instance),
				tostring(blockInfo and blockInfo.Reason),
				tonumber(blockInfo and blockInfo.Distance) or 0,
				tonumber(blockInfo and blockInfo.AcceptedDistance) or 0,
				wallCorrectionDistance
			)
			actualEndPosition = wallSafePosition
		end
	end
	if character and rootPart then
		local resolveSurfaceOptions = if requestedEndPosition and typeof(actualEndPosition) == "Vector3"
			then {
				GuardRootY = actualEndPosition.Y,
				IgnoreFallbackHeightForCast = true,
			}
			else nil
		local resolvedEndPosition, hasEndSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
			character,
			rootPart,
			actualEndPosition,
			abilityConfig,
			burrowState.LastSafeSurfaceRootPosition or burrowState.StartPosition,
			resolveSurfaceOptions
		)
		actualEndPosition = if hasEndSurface and typeof(resolvedEndPosition) == "Vector3"
			then resolvedEndPosition
			else fallbackEndPosition or actualEndPosition
		if hasEndSurface then
			burrowState.LastSafeSurfaceRootPosition = actualEndPosition
		end
	end
	if context.Player then
		context.Player:SetAttribute("MoguResolveCorrectionDistance", resolveCorrectionDistance)
		context.Player:SetAttribute("MoguResolveWallBlocked", wallBlocked)
		context.Player:SetAttribute("MoguResolveWallBlockReason", wallBlocked and wallBlockInfo and wallBlockInfo.Reason or nil)
	end

	return {
		Phase = PHASE_RESOLVE,
		SessionId = burrowState.SessionId,
		ServerState = SESSION_STATE_RESOLVING,
		StartedAt = burrowState.StartedAt,
		EndedAt = endedAt,
		Duration = burrowState.Duration,
		Direction = burrowState.Direction,
		StartPosition = burrowState.StartPosition,
		ActualEndPosition = actualEndPosition,
		ResolveReason = resolveReason,
		ResolveBurstRadius = MoguBurrowShared.GetResolveBurstRadius(abilityConfig),
		ResolveCorrectionDistance = resolveCorrectionDistance,
		ResolveWallBlocked = wallBlocked,
		EndedEarly = resolveReason ~= RESOLVE_REASON_DURATION_ELAPSED,
	}
end

local function buildSessionContext(player, burrowState, requestPayload)
	local character = player and player.Character or nil
	if character ~= burrowState.Character then
		character = burrowState.Character
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or burrowState.Humanoid
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") or burrowState.RootPart
	return {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		AbilityConfig = burrowState.AbilityConfig,
		RequestPayload = requestPayload or {},
	}
end

local function resolveActiveBurrow(player, burrowState, resolveReason, requestPayload, options)
	if not player or activeBurrowsByPlayer[player] ~= burrowState then
		return nil
	end

	options = type(options) == "table" and options or {}
	local endedAt = getSharedTimestamp()
	setSessionState(player, burrowState, SESSION_STATE_RESOLVING, resolveReason)
	local context = buildSessionContext(player, burrowState, requestPayload)
	local resolveDirection, resolveDirectionSource =
		MoguBurrowShared.ResolveDirection(context.Humanoid, context.RootPart, requestPayload)
	burrowState.Direction = resolveDirection
	burrowState.DirectionSource = resolveDirectionSource
	if context.Character and context.RootPart then
		faceCharacterAlongDirection(context.Character, context.RootPart, burrowState.Direction)
	end

	local payload = buildResolvePayload(context, burrowState, endedAt, resolveReason)
	clearActiveBurrow(player, options.ClearReason or CLEAR_REASON_RESOLVE)

	if options.ApplyCooldown == true and burrowState.CooldownApplied ~= true then
		burrowState.CooldownApplied = true
		if typeof(burrowState.StartAbilityCooldown) == "function" then
			burrowState.StartAbilityCooldown(tonumber(burrowState.AbilityConfig and burrowState.AbilityConfig.Cooldown) or 0, payload)
		end
	end

	if options.EmitEffect == true and typeof(burrowState.EmitEffect) == "function" then
		burrowState.EmitEffect(ABILITY_NAME, payload, player)
	end

	return payload
end

local function scheduleSessionTransitions(player, burrowState)
	local undergroundDelay = math.max(0, (tonumber(burrowState.UndergroundAt) or burrowState.StartedAt) - getSharedTimestamp())
	local stateToken = {}
	burrowState.StateToken = stateToken
	task.delay(undergroundDelay, function()
		if activeBurrowsByPlayer[player] ~= burrowState or burrowState.StateToken ~= stateToken then
			return
		end

		setSessionState(player, burrowState, SESSION_STATE_UNDERGROUND, "startup_elapsed")
		clearStartupInvincibilityState(player)
	end)

	local timeoutToken = {}
	burrowState.TimeoutToken = timeoutToken
	task.delay(math.max(0, burrowState.EndTime - getSharedTimestamp()), function()
		if activeBurrowsByPlayer[player] ~= burrowState or burrowState.TimeoutToken ~= timeoutToken then
			return
		end

		resolveActiveBurrow(player, burrowState, RESOLVE_REASON_DURATION_ELAPSED, {}, {
			ApplyCooldown = true,
			EmitEffect = true,
			ClearReason = CLEAR_REASON_EXPIRED,
		})
	end)
end

local function hookSessionCleanup(player, burrowState)
	local connections = {}
	burrowState.Connections = connections
	local humanoid = burrowState.Humanoid
	if humanoid then
		connections[#connections + 1] = humanoid.Died:Connect(function()
			DamageProtection.TraceMoguStartupDamage(player, {
				TargetContext = {
					Player = player,
					Character = burrowState.Character,
					Humanoid = humanoid,
					RootPart = burrowState.RootPart,
				},
				Position = burrowState.RootPart and burrowState.RootPart.Position or nil,
				Path = "MoguServer.HumanoidDied",
				Source = "Humanoid.Died",
			})
			if activeBurrowsByPlayer[player] == burrowState then
				clearActiveBurrow(player, CLEAR_REASON_HUMANOID_DIED)
			end
		end)
	end

	local character = burrowState.Character
	if character then
		connections[#connections + 1] = character.AncestryChanged:Connect(function(_, parent)
			if parent == nil and activeBurrowsByPlayer[player] == burrowState then
				clearActiveBurrow(player, CLEAR_REASON_CHARACTER_REMOVING)
			end
		end)
	end
end

function MoguServer.Burrow(context)
	local player = context.Player
	local abilityConfig = context.AbilityConfig or {}
	local requestedSessionId = getRequestedSessionId(context.RequestPayload)
	local activeBurrow = getActiveBurrow(player)
	if activeBurrow then
		if not requestedSessionId then
			return nil, {
				ApplyCooldown = false,
				DenyReason = "MissingSession",
			}
		end
		if requestedSessionId ~= activeBurrow.SessionId then
			logWarn(
				"stale resolve rejected player=%s requestedSession=%s activeSession=%s",
				player and player.Name or "<nil>",
				tostring(requestedSessionId),
				tostring(activeBurrow.SessionId)
			)
			return nil, {
				ApplyCooldown = false,
				DenyReason = "StaleSession",
			}
		end

		local endedAt = getSharedTimestamp()
		local minResolveDelay = getMinimumManualResolveDelay(activeBurrow.AbilityConfig or abilityConfig)
		local resolveReadyAt = (tonumber(activeBurrow.StartedAt) or endedAt) + minResolveDelay
		if endedAt < resolveReadyAt then
			logInfo(
				"resolve ignored player=%s reason=resolve_not_ready elapsed=%.2f readyIn=%.2f",
				player and player.Name or "<nil>",
				endedAt - (tonumber(activeBurrow.StartedAt) or endedAt),
				resolveReadyAt - endedAt
			)
			return nil, {
				ApplyCooldown = false,
				DenyReason = "ResolveNotReady",
			}
		end

		logInfo(
			"server resolve animation suppressed player=%s reason=client_visual_path",
			player and player.Name or "<nil>"
		)

		local resolveReason = endedAt >= activeBurrow.EndTime and RESOLVE_REASON_DURATION_ELAPSED or RESOLVE_REASON_MANUAL_SURFACE
		return resolveActiveBurrow(player, activeBurrow, resolveReason, context.RequestPayload, {
			ClearReason = CLEAR_REASON_RESOLVE,
		}), {
			ApplyCooldown = true,
			CooldownDuration = tonumber(abilityConfig.Cooldown) or 0,
		}
	end

	if requestedSessionId then
		clearInvalidProtection(player, PROTECTION_REASON_STALE_SESSION, {
			ClearSessionAttributes = true,
			ForceDiagnostic = true,
		})
		return nil, {
			ApplyCooldown = false,
			DenyReason = "StaleSession",
		}
	end

	local rootSpeedBeforeHardStop = context.RootPart.AssemblyLinearVelocity.Magnitude
	local rootAngularSpeedBeforeHardStop = context.RootPart.AssemblyAngularVelocity.Magnitude

	local startedAt = getSharedTimestamp()
	local duration = MoguBurrowShared.GetBurrowDuration(abilityConfig)
	local endsAt = startedAt + duration
	local undergroundAt = startedAt + getMinimumManualResolveDelay(abilityConfig)
	local startupInvincibilityMaxSeconds = MoguBurrowShared.GetStartupInvincibilityMaxSeconds(abilityConfig)
	local startupInvincibilityStartOffsetSeconds =
		MoguBurrowShared.GetStartupInvincibilityStartOffsetSeconds(abilityConfig)
	local startupInvincibilityFrom = startedAt + startupInvincibilityStartOffsetSeconds
	local startupInvincibilityUntil = nil
	if startupInvincibilityMaxSeconds > 0 then
		startupInvincibilityUntil = math.min(startedAt + startupInvincibilityMaxSeconds, endsAt)
		if startupInvincibilityUntil <= startupInvincibilityFrom then
			startupInvincibilityUntil = nil
		end
	end
	local direction, directionSource =
		MoguBurrowShared.ResolveDirection(context.Humanoid, context.RootPart, context.RequestPayload)
	local predictedStartPosition, predictedStartDistance =
		getTrustedPredictedStartPosition(context.RequestPayload, context.RootPart, player)
	if predictedStartDistance then
		logInfo(
			"predicted vs authoritative start player=%s distance=%.2f trusted=%s",
			player and player.Name or "<nil>",
			predictedStartDistance,
			tostring(predictedStartPosition ~= nil)
		)
	end
	local requestedStartPosition = predictedStartPosition or context.RootPart.Position
	local startSurfacePosition, hasStartSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
		context.Character,
		context.RootPart,
		requestedStartPosition,
		abilityConfig,
		context.RootPart.Position,
		{
			AllowActivationDrop = true,
		}
	)
	if (not hasStartSurface or not startSurfacePosition) and predictedStartPosition then
		logWarn(
			"predicted start surface probe failed player=%s retrying server root",
			player and player.Name or "<nil>"
		)
		startSurfacePosition, hasStartSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
			context.Character,
			context.RootPart,
			context.RootPart.Position,
			abilityConfig,
			context.RootPart.Position,
			{
				AllowActivationDrop = true,
			}
		)
	end
	if not hasStartSurface or not startSurfacePosition then
		logWarn(
			"server ground probe failed player=%s rootPosition=%s hasStartSurface=%s",
			player and player.Name or "<nil>",
			tostring(context.RootPart and context.RootPart.Position or nil),
			tostring(hasStartSurface)
		)
		if player then
			setGroundedStartDiagnostics(player, "Denied", "NoGround", nil)
			clearInvalidProtection(player, PROTECTION_REASON_REJECTED_START, {
				ClearSessionAttributes = true,
				ForceDiagnostic = true,
			})
		end
		return nil, {
			ApplyCooldown = false,
			DenyReason = "NoGround",
		}
	end
	local activationDropDistance = 0
	if shouldRequireGroundedBurrowStart(abilityConfig) then
		local rootPosition = context.RootPart and context.RootPart.Position or nil
		local dropDistance = if typeof(rootPosition) == "Vector3"
			then math.max(0, rootPosition.Y - startSurfacePosition.Y)
			else 0
		activationDropDistance = dropDistance
		local hardAirborne, floorMaterialAir, humanoidState, floorMaterial = getHumanoidGroundState(context.Humanoid)
		local contactTolerance = getBurrowGroundContactTolerance(abilityConfig)
		if hardAirborne or dropDistance > contactTolerance then
			local denyReason = if hardAirborne then "Airborne" else "NotGrounded"
			logWarn(
				"server burrow denied before ground contact player=%s reason=%s drop=%.2f tolerance=%.2f humanoidState=%s floor=%s",
				player and player.Name or "<nil>",
				denyReason,
				dropDistance,
				contactTolerance,
				tostring(humanoidState and humanoidState.Name or "<nil>"),
				tostring(floorMaterial and floorMaterial.Name or "<nil>")
			)
			if player then
				setGroundedStartDiagnostics(player, "Denied", denyReason, dropDistance)
				clearInvalidProtection(player, normalizeProtectionClearReason(denyReason), {
					ClearSessionAttributes = true,
					ForceDiagnostic = true,
				})
			end
			return nil, {
				ApplyCooldown = false,
				DenyReason = denyReason,
			}
		end
		if floorMaterialAir then
			logInfo(
				"server burrow tolerated floor air player=%s drop=%.2f tolerance=%.2f humanoidState=%s floor=%s",
				player and player.Name or "<nil>",
				dropDistance,
				contactTolerance,
				tostring(humanoidState and humanoidState.Name or "<nil>"),
				tostring(floorMaterial and floorMaterial.Name or "<nil>")
			)
		end
	end
	if player then
		setGroundedStartDiagnostics(player, "GroundedStart", "Accepted", activationDropDistance)
	end

	zeroRootVelocity(context.RootPart)
	logInfo(
		"startup stabilization applied player=%s speed=%.2f angular=%.2f",
		player and player.Name or "<nil>",
		rootSpeedBeforeHardStop,
		rootAngularSpeedBeforeHardStop
	)

	faceCharacterAlongDirection(context.Character, context.RootPart, direction)
	logInfo(
		"server start animation suppressed player=%s reason=client_visual_path",
		player and player.Name or "<nil>"
	)

	local burrowState = {
		SessionId = createSessionId(player),
		State = SESSION_STATE_STARTUP,
		StartedAt = startedAt,
		UndergroundAt = undergroundAt,
		StartupInvincibilityMaxSeconds = startupInvincibilityMaxSeconds,
		StartupInvincibilityStartOffsetSeconds = startupInvincibilityStartOffsetSeconds,
		StartupInvincibilityFrom = startupInvincibilityFrom,
		StartupInvincibilityUntil = startupInvincibilityUntil,
		EndTime = endsAt,
		Duration = duration,
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = startSurfacePosition,
		LastSafeSurfaceRootPosition = startSurfacePosition,
		AbilityConfig = abilityConfig,
		MoveSpeed = MoguBurrowShared.GetMoveSpeed(abilityConfig),
		Player = player,
		Character = context.Character,
		Humanoid = context.Humanoid,
		RootPart = context.RootPart,
		EmitEffect = context.EmitEffect,
		StartAbilityCooldown = context.StartAbilityCooldown,
		CooldownApplied = false,
	}
	local protectedUntil = endsAt + MoguBurrowShared.GetSurfaceResolveGrace(abilityConfig)
	setSessionAttributes(player, burrowState)
	setStartupInvincibilityState(player, burrowState)
	setProtectionState(player, protectedUntil)
	setMovementLockState(player, protectedUntil)
	DamageProtection.TraceMoguStartupDamage(player, {
		TargetContext = {
			Player = player,
			Character = context.Character,
			Humanoid = context.Humanoid,
			RootPart = context.RootPart,
		},
		Position = startSurfacePosition,
		Path = "MoguServer.BurrowAccepted",
		Source = "MoguServer",
	})
	activeBurrowsByPlayer[player] = burrowState
	hookSessionCleanup(player, burrowState)
	scheduleSessionTransitions(player, burrowState)
	player:SetAttribute("MoguResolveCorrectionDistance", 0)

	return buildStartPayload(context, burrowState, startedAt, endsAt, direction, directionSource, startSurfacePosition), {
		ApplyCooldown = false,
	}
end

function MoguServer.IsPlayerUnderground(player)
	if not player or not player:IsA("Player") then
		return false
	end

	local activeBurrow = getActiveBurrow(player)
	return isBurrowStateUnderground(activeBurrow)
end

function MoguServer.IsMoguBurrowed(player)
	return MoguServer.IsPlayerUnderground(player)
end

function MoguServer.IsStartupInvincible(player)
	local activeBurrow = getActiveBurrow(player)
	if not activeBurrow then
		return false
	end

	if isStartupInvincibilityActive(player, activeBurrow, getSharedTimestamp()) then
		return true, "mogu_startup_invincible", {
			Protected = true,
			Source = "MoguBurrow",
			Reason = "mogu_startup_invincible",
			Player = player,
			SessionId = activeBurrow.SessionId,
			State = activeBurrow.State,
			From = activeBurrow.StartupInvincibilityFrom,
			Until = activeBurrow.StartupInvincibilityUntil,
		}
	end

	return false
end

function MoguServer.GetProtection(player, position, _options)
	if not player or not player:IsA("Player") then
		return nil
	end

	local activeBurrow = getActiveBurrow(player)
	if not activeBurrow then
		return nil
	end

	if isBurrowStateUnderground(activeBurrow) then
		return {
			Protected = true,
			Source = "MoguBurrow",
			Reason = "mogu_underground",
			Player = player,
			Position = position,
			SessionId = activeBurrow.SessionId,
			State = activeBurrow.State,
		}
	end

	if isStartupInvincibilityActive(player, activeBurrow, getSharedTimestamp()) then
		return {
			Protected = true,
			Source = "MoguBurrow",
			Reason = "mogu_startup_invincible",
			Player = player,
			Position = position,
			SessionId = activeBurrow.SessionId,
			State = activeBurrow.State,
			From = activeBurrow.StartupInvincibilityFrom,
			Until = activeBurrow.StartupInvincibilityUntil,
		}
	end

	return nil
end

function MoguServer.IsProtected(player)
	local protection = MoguServer.GetProtection(player)
	if protection then
		return true, protection.Reason, protection
	end

	if not getActiveBurrow(player) then
		clearInvalidProtection(player, PROTECTION_REASON_WITHOUT_SESSION, {
			ClearSessionAttributes = true,
		})
	end
	return false
end

function MoguServer.ClearRuntimeState(player)
	-- Runtime cleanup should not emit a Resolve payload or start cooldown.
	clearActiveBurrow(player, CLEAR_REASON_RUNTIME_RESET)
end

function MoguServer.GetLegacyHandler()
	return MoguServer
end

local function enforceProtectionIntegrity(player, reason)
	if not player or not player:IsA("Player") then
		return false
	end

	if activeBurrowsByPlayer[player] == nil and not hasMoguRuntimeState(player) then
		return false
	end

	local activeBurrow = getActiveBurrow(player)
	if activeBurrow then
		return true
	end

	if activeBurrowsByPlayer[player] == nil and not hasMoguRuntimeState(player) then
		return false
	end

	return clearInvalidProtection(player, reason or PROTECTION_REASON_WITHOUT_SESSION, {
		ClearSessionAttributes = true,
	})
end

function MoguServer.EnforceProtectionIntegrity(player, reason)
	return enforceProtectionIntegrity(player, reason or PROTECTION_REASON_WITHOUT_SESSION)
end

RunService.Heartbeat:Connect(function(dt)
	protectionGuardAccumulator += dt
	if protectionGuardAccumulator < PROTECTION_GUARD_SWEEP_INTERVAL then
		return
	end

	protectionGuardAccumulator = 0
	for _, player in ipairs(Players:GetPlayers()) do
		enforceProtectionIntegrity(player, PROTECTION_REASON_WITHOUT_SESSION)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	clearActiveBurrow(player, CLEAR_REASON_PLAYER_REMOVING)
end)

return MoguServer
