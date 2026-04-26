--[[
	MeraPresentationClient is the client-side presentation orchestrator for Mera moves.

	It owns:
	- animation playback selection for visual-only presentation
	- client-side VFX sequencing for FlameDash and FireBurst
	- runtime state tables that keep startup/body/trail/burst cleanup coordinated
	- local prediction/reconciliation handoff for FlameDash VFX continuity

	It does not own:
	- gameplay hit detection
	- server authority for move start/finish
	- raw per-asset VFX behavior (that lives in `Shared/Vfx`)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local AnimationLoadDiagnostics = require(Modules:WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local MeraFolder = DevilFruits:WaitForChild("Mera")
local MeraShared = MeraFolder:WaitForChild("Shared")
local MeraAnimationResolver = require(MeraShared:WaitForChild("MeraAnimationResolver"))
local MeraVfx = require(MeraShared:WaitForChild("Vfx"))

local MeraPresentationClient = {}
MeraPresentationClient.__index = MeraPresentationClient

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3
local DEFAULT_FADE_TIME = 0.05
local DEFAULT_STOP_FADE_TIME = 0.08
local FIRE_BURST_DEFAULT_DURATION = 0.6
local FIRE_BURST_CLEANUP_GRACE = 0.12
local FLAME_DASH_DEFAULT_DURATION = 0.15
local FLAME_DASH_ACTIVE_DELAY_RATIO = 0.18
local FLAME_DASH_MIN_ACTIVE_DELAY = 0.02
local FLAME_DASH_MAX_ACTIVE_DELAY = 0.05
local FLAME_DASH_FALLBACK_ACTIVE_DELAY = 0.03
local FLAME_DASH_STOP_SPEED_THRESHOLD = 3
local FLAME_DASH_FINAL_POSITION_TOLERANCE = 1.25
local FLAME_DASH_FINALIZE_SETTLE_TIME = 0.05
local FLAME_DASH_FINALIZE_MAX_WAIT = 0.35
local FLAME_DASH_PREDICTED_FINALIZE_TIMEOUT = 0.75
local FLAME_DASH_END_HINT_DISTANCE_TOLERANCE = 2.5
local FLAME_DASH_ACTIVE_MARKERS = { "Jump", "DashStart", "DashActive", "DashLoop", "Dash", "Swipe" }
local FLAME_DASH_END_MARKERS = { "DashEnd", "End", "Launch", "Complete", "Stop" }
local ANIMATION_FAILURE_RETRY_COOLDOWN = 10
local SOURCE_LABEL = "ReplicatedStorage.Modules.DevilFruits.MeraPresentationClient"

local animationFailureStateByKey = {}

local function logMove(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraPresentationClient:MOVE", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA MOVE] " .. message, ...))
end

local function logFireBurst(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraPresentationClient:FIREBURST", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA FIREBURST][CLIENT] " .. message, ...))
end

local function logAnimInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraPresentationClient:ANIM", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA ANIM] " .. message, ...))
end

local function logAnimWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MeraPresentationClient:ANIM_WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MERA ANIM][WARN] " .. message, ...))
end

local function buildAnimationFailureKey(moveName, assetName, defaultAssetName)
	return string.format("%s::%s", tostring(moveName or "<unknown>"), tostring(assetName or defaultAssetName or ""))
end

local function getCachedAnimationFailure(failureKey)
	local state = animationFailureStateByKey[failureKey]
	if type(state) ~= "table" then
		return nil
	end

	if (tonumber(state.RetryAt) or 0) <= os.clock() then
		animationFailureStateByKey[failureKey] = nil
		return nil
	end

	return state
end

local function rememberAnimationFailure(failureKey, animationPath, detail)
	animationFailureStateByKey[failureKey] = {
		Path = tostring(animationPath or ""),
		Detail = tostring(detail or "missing_animation"),
		RetryAt = os.clock() + ANIMATION_FAILURE_RETRY_COOLDOWN,
	}
end

local function clearAnimationFailure(failureKey)
	animationFailureStateByKey[failureKey] = nil
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatNumber(value)
	if type(value) ~= "number" then
		return tostring(value)
	end

	return string.format("%.2f", value)
end

local function getPlanarDirection(vector, fallbackDirection)
	local planarVector = typeof(vector) == "Vector3" and Vector3.new(vector.X, 0, vector.Z) or nil
	if planarVector and planarVector.Magnitude > 0.01 then
		return planarVector.Unit
	end

	local fallback = typeof(fallbackDirection) == "Vector3"
			and Vector3.new(fallbackDirection.X, 0, fallbackDirection.Z)
		or Vector3.new(0, 0, -1)
	if fallback.Magnitude <= 0.01 then
		fallback = Vector3.new(0, 0, -1)
	end

	return fallback.Unit
end

local function getPlanarMagnitude(vector)
	if typeof(vector) ~= "Vector3" then
		return 0
	end

	return Vector3.new(vector.X, 0, vector.Z).Magnitude
end

local function getPlanarDistance(fromPosition, toPosition)
	if typeof(fromPosition) ~= "Vector3" or typeof(toPosition) ~= "Vector3" then
		return math.huge
	end

	return Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z).Magnitude
end

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function getDistanceAlongDirection(fromPosition, toPosition, direction)
	if typeof(fromPosition) ~= "Vector3" or typeof(toPosition) ~= "Vector3" then
		return 0
	end

	local planarDirection = getPlanarDirection(direction, Vector3.new(0, 0, -1))
	local planarDelta = Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
	return planarDelta:Dot(planarDirection)
end

local function logFlameDashTiming(targetPlayer, state, stageName, source, rootPosition)
	if not targetPlayer or not targetPlayer:IsA("Player") or type(state) ~= "table" then
		return
	end

	local resolvedRootPosition = typeof(rootPosition) == "Vector3"
		and rootPosition
		or (state.RootPart and state.RootPart.Parent and state.RootPart.Position)
		or state.LastRootPosition
	local startPosition = typeof(state.ServerStartPosition) == "Vector3" and state.ServerStartPosition or state.StartPosition
	local expectedEndPosition = typeof(state.ExpectedEndPosition) == "Vector3" and state.ExpectedEndPosition or nil
	local direction = typeof(state.Direction) == "Vector3" and state.Direction or state.CurrentFollowDirection
	local alongDistance = getDistanceAlongDirection(startPosition, resolvedRootPosition, direction)
	local plannedDistance = tonumber(state.PlannedDistance)
	if type(plannedDistance) ~= "number" and typeof(startPosition) == "Vector3" and typeof(expectedEndPosition) == "Vector3" then
		plannedDistance = getDistanceAlongDirection(startPosition, expectedEndPosition, direction)
	end

	local remainingDistance = type(plannedDistance) == "number" and (plannedDistance - alongDistance) or nil
	local localElapsedMs = tonumber(state.StartedAt) and math.max(0, (os.clock() - state.StartedAt) * 1000) or nil
	local serverElapsedMs = tonumber(state.ServerStartedAt) and math.max(0, (getSharedTimestamp() - state.ServerStartedAt) * 1000) or nil
	local planarSpeed = getPlanarMagnitude(state.RootPart and state.RootPart.AssemblyLinearVelocity or nil)

	logMove(
		"move=FlameDash timing stage=%s player=%s source=%s root=%s along=%.2f planned=%s remaining=%s localElapsedMs=%s serverElapsedMs=%s speed=%.2f activeDelay=%.3f duration=%s instant=%s start=%s expectedEnd=%s",
		tostring(stageName),
		targetPlayer.Name,
		tostring(source or "unknown"),
		formatVector3(resolvedRootPosition),
		alongDistance,
		formatNumber(plannedDistance),
		formatNumber(remainingDistance),
		formatNumber(localElapsedMs),
		formatNumber(serverElapsedMs),
		planarSpeed,
		tonumber(state.ActiveDelay) or 0,
		formatNumber(tonumber(state.PlannedDuration)),
		formatNumber(tonumber(state.PlannedInstantDistance)),
		formatVector3(startPosition),
		formatVector3(expectedEndPosition)
	)
end

local function resolveDashDirection(rootPart, preferredDirection)
	if not rootPart or not rootPart.Parent then
		return getPlanarDirection(preferredDirection, Vector3.new(0, 0, -1))
	end

	local velocityDirection = getPlanarDirection(rootPart.AssemblyLinearVelocity, nil)
	if velocityDirection then
		local planarVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
		if planarVelocity.Magnitude > 8 then
			return velocityDirection
		end
	end

	return getPlanarDirection(preferredDirection, rootPart.CFrame.LookVector)
end

local function resolveFacingDirection(rootPart, preferredDirection)
	if not rootPart or not rootPart.Parent then
		return getPlanarDirection(preferredDirection, Vector3.new(0, 0, -1))
	end

	return getPlanarDirection(preferredDirection, rootPart.CFrame.LookVector)
end

local function getLatchedFlameDashDirection(state, rootPart, preferredDirection)
	if type(state) == "table" and typeof(state.Direction) == "Vector3" then
		return state.Direction
	end

	return resolveDashDirection(rootPart, preferredDirection)
end

local function getLatchedFlameDashVisualDirection(state, rootPart, preferredDirection)
	if type(state) == "table" and typeof(state.VisualDirection) == "Vector3" then
		return state.VisualDirection
	end

	return resolveFacingDirection(rootPart, preferredDirection)
end

local function getLatchedFlameDashVfxDirection(state, rootPart, preferredDirection)
	local dashDirection = preferredDirection
	if typeof(dashDirection) ~= "Vector3" and type(state) == "table" then
		dashDirection = state.CurrentFollowDirection or state.Direction or state.VisualDirection
	end

	return resolveDashDirection(rootPart, dashDirection)
end

local function getPayloadVisualDirection(payload)
	if type(payload) ~= "table" then
		return nil
	end

	if typeof(payload.VisualDirection) == "Vector3" then
		return payload.VisualDirection
	end

	if typeof(payload.Direction) == "Vector3" then
		return payload.Direction
	end

	return nil
end

local function computeFlameDashActiveDelay(abilityConfig)
	local duration = math.max(
		0,
		tonumber(type(abilityConfig) == "table" and abilityConfig.DashDuration) or FLAME_DASH_DEFAULT_DURATION
	)
	if duration <= 0 then
		return FLAME_DASH_FALLBACK_ACTIVE_DELAY
	end

	return math.clamp(duration * FLAME_DASH_ACTIVE_DELAY_RATIO, FLAME_DASH_MIN_ACTIVE_DELAY, FLAME_DASH_MAX_ACTIVE_DELAY)
end

local function getFlameDashStartToken(payload)
	if type(payload) ~= "table" then
		return nil
	end

	local startedAt = tonumber(payload.StartedAt)
	if not startedAt or startedAt <= 0 then
		return nil
	end

	return startedAt
end

local function getFlameDashPathStartPosition(state)
	if type(state) ~= "table" then
		return nil
	end

	if typeof(state.ServerStartPosition) == "Vector3" then
		return state.ServerStartPosition
	end
	if typeof(state.StartPosition) == "Vector3" then
		return state.StartPosition
	end
	if typeof(state.LastVfxPosition) == "Vector3" then
		return state.LastVfxPosition
	end
	if typeof(state.LastRootPosition) == "Vector3" then
		return state.LastRootPosition
	end

	local rootPart = state.RootPart
	if rootPart and rootPart.Parent then
		return rootPart.Position
	end

	return nil
end

local function getFlameDashPlannedDistance(state)
	if type(state) ~= "table" then
		return 0
	end

	local plannedDistance = tonumber(state.PlannedDistance)
	if type(plannedDistance) == "number" then
		return math.max(plannedDistance, 0)
	end

	local startPosition = getFlameDashPathStartPosition(state)
	local expectedEndPosition = typeof(state.ExpectedEndPosition) == "Vector3" and state.ExpectedEndPosition or nil
	local direction = typeof(state.Direction) == "Vector3" and state.Direction or state.CurrentFollowDirection
	if typeof(startPosition) == "Vector3" and typeof(expectedEndPosition) == "Vector3" then
		return math.max(getDistanceAlongDirection(startPosition, expectedEndPosition, direction), 0)
	end

	return 0
end

local function getLiveFlameDashVfxProgressDistance(state, position, direction)
	local startPosition = getFlameDashPathStartPosition(state)
	if typeof(startPosition) ~= "Vector3" or typeof(position) ~= "Vector3" then
		return 0
	end

	local resolvedDirection = typeof(direction) == "Vector3"
		and direction
		or (type(state) == "table" and state.Direction)
	return math.max(0, getDistanceAlongDirection(startPosition, position, resolvedDirection))
end

local function updateFlameDashVfxSnapshot(state, position, progressDistance)
	if type(state) ~= "table" then
		return
	end

	if typeof(position) == "Vector3" then
		state.LastVfxPosition = position
	end
	if type(progressDistance) == "number" then
		state.LastVfxProgressDistance = progressDistance
	end
end

local function isAuthoritativeFlameDashEndSource(stageSource)
	return tostring(stageSource) == "server_resolve"
end

local function shouldAcceptFlameDashEndHint(state, progressDistance)
	local plannedDistance = getFlameDashPlannedDistance(state)
	if plannedDistance <= 0 then
		return true
	end

	local resolvedProgressDistance = tonumber(progressDistance)
	if type(resolvedProgressDistance) ~= "number" then
		resolvedProgressDistance = tonumber(state and state.LastVfxProgressDistance) or 0
	end

	local remainingDistance = math.max(plannedDistance - resolvedProgressDistance, 0)
	return remainingDistance <= FLAME_DASH_END_HINT_DISTANCE_TOLERANCE
end

local function getAnimator(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	if not character then
		logAnimWarn("animation missing or failed to load move=<unknown> detail=character_missing player=%s", tostring(targetPlayer))
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		logAnimWarn("animation missing or failed to load move=<unknown> detail=humanoid_missing player=%s", tostring(targetPlayer))
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")
	if animator and animator:IsA("Animator") then
		return animator
	end

	local ok, waitedAnimator = pcall(function()
		return humanoid:WaitForChild("Animator", 0.25)
	end)
	if ok and waitedAnimator and waitedAnimator:IsA("Animator") then
		return waitedAnimator
	end

	logAnimWarn("animation missing or failed to load move=<unknown> detail=animator_missing player=%s", tostring(targetPlayer))
	return nil
end

local function stopTrack(track, fadeTime)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return
	end

	pcall(function()
		track:Stop(math.max(0, tonumber(fadeTime) or DEFAULT_STOP_FADE_TIME))
	end)
end

local function clearTrackBucket(bucket, fadeTime)
	if type(bucket) ~= "table" then
		return
	end

	for moveName, track in pairs(bucket) do
		stopTrack(track, fadeTime)
		bucket[moveName] = nil
	end
end

local function disconnectConnections(connections)
	if type(connections) ~= "table" then
		return
	end

	for index, connection in ipairs(connections) do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
		connections[index] = nil
	end
end

local function cancelTask(taskHandle)
	if taskHandle == nil then
		return
	end

	pcall(task.cancel, taskHandle)
end

local function getFireBurstCastId(targetPlayer, payload)
	if type(payload) == "table" then
		local castId = payload.CastId
		if typeof(castId) == "string" and castId ~= "" then
			return castId
		end

		local startedAt = tonumber(payload.StartedAt)
		if startedAt and startedAt > 0 then
			return string.format("%s:%.6f", tostring(targetPlayer and targetPlayer.UserId or 0), startedAt)
		end
	end

	return nil
end

function MeraPresentationClient.new(config)
	local self = setmetatable({}, MeraPresentationClient)
	self.player = config and config.player or Players.LocalPlayer
	self.createEffectVisual = config and config.createEffectVisual
	self.activeTracksByPlayer = setmetatable({}, { __mode = "k" })
	-- FlameDash keeps a multi-phase runtime state because startup/body/trail are
	-- separate visuals that must hand off smoothly.
	self.activeFlameDashVfxByPlayer = setmetatable({}, { __mode = "k" })
	-- FireBurst keeps one runtime state per player/cast so startup and burst stay in
	-- one exactly-once presentation sequence.
	self.activeFireBurstByPlayer = setmetatable({}, { __mode = "k" })
	return self
end

function MeraPresentationClient:EmitFallbackFlameDashVisual(state, payload, isPredicted)
	if typeof(self.createEffectVisual) ~= "function" or type(state) ~= "table" then
		return false
	end

	local startPosition = typeof(state.StartPosition) == "Vector3" and state.StartPosition or nil
	local endPosition = typeof(state.ExpectedEndPosition) == "Vector3" and state.ExpectedEndPosition or nil
	local direction = typeof(state.VisualDirection) == "Vector3" and state.VisualDirection
		or (typeof(state.Direction) == "Vector3" and state.Direction or nil)

	if typeof(payload) == "table" then
		if typeof(payload.StartPosition) == "Vector3" then
			startPosition = payload.StartPosition
		end
		if typeof(payload.EndPosition) == "Vector3" then
			endPosition = payload.EndPosition
		elseif typeof(payload.DashTargetPosition) == "Vector3" then
			endPosition = payload.DashTargetPosition
		end
		if typeof(payload.VisualDirection) == "Vector3" then
			direction = payload.VisualDirection
		elseif typeof(payload.Direction) == "Vector3" then
			direction = payload.Direction
		end
	end

	if typeof(startPosition) ~= "Vector3" then
		return false
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.01 then
		direction = Vector3.new(0, 0, -1)
	end

	if typeof(endPosition) ~= "Vector3" then
		endPosition = startPosition + direction.Unit * 14
	end

	local ok, err = pcall(self.createEffectVisual, startPosition, endPosition, direction, isPredicted == true)
	if not ok then
		logMove("move=FlameDash fallback visual failed player=%s detail=%s", self.player and self.player.Name or "<nil>", tostring(err))
		return false
	end

	logMove(
		"move=FlameDash fallback visual emitted player=%s start=%s final=%s direction=%s predicted=%s",
		self.player and self.player.Name or "<nil>",
		formatVector3(startPosition),
		formatVector3(endPosition),
		formatVector3(direction),
		tostring(isPredicted == true)
	)
	return true
end

local function hasLiveFlameDashStageState(stageState)
	return type(stageState) == "table" and stageState.Destroyed ~= true
end

function MeraPresentationClient:EnsureFallbackFlameDashVisual(state, reason)
	if type(state) ~= "table" or state.FallbackVisualEmitted == true then
		return false
	end

	local payload = type(state.StartPayload) == "table" and state.StartPayload or {}
	local emitted = self:EmitFallbackFlameDashVisual(state, payload, state.IsPredicted == true)
	if emitted then
		state.FallbackVisualEmitted = true
		state.FallbackVisualReason = tostring(reason or "unknown")
		logMove(
			"move=FlameDash fallback visual engaged player=%s reason=%s",
			self.player and self.player.Name or "<nil>",
			tostring(state.FallbackVisualReason)
		)
	end

	return emitted
end

function MeraPresentationClient:GetAnimationConfig(moveName)
	local abilityConfig = DevilFruitConfig.GetAbility("Mera Mera no Mi", moveName)
	return type(abilityConfig) == "table" and type(abilityConfig.Animation) == "table" and abilityConfig.Animation or nil
end

function MeraPresentationClient:GetAbilityConfig(moveName)
	local abilityConfig = DevilFruitConfig.GetAbility("Mera Mera no Mi", moveName)
	return type(abilityConfig) == "table" and abilityConfig or nil
end

function MeraPresentationClient:GetTrackBucket(targetPlayer)
	local bucket = self.activeTracksByPlayer[targetPlayer]
	if bucket then
		return bucket
	end

	bucket = {}
	self.activeTracksByPlayer[targetPlayer] = bucket
	return bucket
end

function MeraPresentationClient:DisconnectFlameDashTrackPhases(state)
	if type(state) ~= "table" then
		return
	end

	disconnectConnections(state.TrackPhaseConnections)
	state.TrackPhaseConnections = nil
end

-- ============================================================================
-- FlameDash Presentation State
-- ============================================================================
-- FlameDash is handled as one explicit cast state: startup -> active -> resolve.
-- This simplified version intentionally avoids state reuse or overlap tricks.

function MeraPresentationClient:RefreshFlameDashState(state, payload, rootPart)
	if type(state) ~= "table" then
		return
	end

	local resolvedRootPart = rootPart or state.RootPart
	if resolvedRootPart and resolvedRootPart.Parent then
		local preferredDirection = typeof(payload) == "table" and payload.Direction or state.Direction
		local preferredVisualDirection = getPayloadVisualDirection(payload) or state.VisualDirection
		state.Direction = getLatchedFlameDashDirection(state, resolvedRootPart, preferredDirection)
		state.VisualDirection = resolveFacingDirection(resolvedRootPart, preferredVisualDirection)
		state.LiveDirection = resolveDashDirection(resolvedRootPart, state.Direction)
		state.CurrentFollowDirection = state.Direction
		state.LastRootPosition = resolvedRootPart.Position
	end

	local startPosition = typeof(payload) == "table" and payload.StartPosition or nil
	if typeof(startPosition) == "Vector3" then
		state.StartPosition = startPosition
		state.ServerStartPosition = startPosition
	end

	local startToken = getFlameDashStartToken(payload)
	if startToken then
		state.ServerStartedAt = startToken
	end

	if typeof(payload) == "table" then
		if typeof(payload.EndPosition) == "Vector3" then
			state.ExpectedEndPosition = payload.EndPosition
		end
		if typeof(payload.ActualEndPosition) == "Vector3" then
			state.ActualEndPosition = payload.ActualEndPosition
		end
		if type(payload.ResolveReason) == "string" and payload.ResolveReason ~= "" then
			state.ResolveReason = payload.ResolveReason
		end
		if tonumber(payload.Distance) then
			state.PlannedDistance = tonumber(payload.Distance)
		end
		if tonumber(payload.Duration) then
			state.PlannedDuration = tonumber(payload.Duration)
		end
		if tonumber(payload.InstantDistance) then
			state.PlannedInstantDistance = tonumber(payload.InstantDistance)
		end
		if tonumber(payload.RemainingDistance) then
			state.PlannedRemainingDistance = tonumber(payload.RemainingDistance)
		end
		if tonumber(payload.ActualDuration) then
			state.ActualDuration = tonumber(payload.ActualDuration)
		end
	end
end

-- Stage transitions are explicit so the code reads in move phases rather than a pile
-- of independent reactions. Startup is stopped when DashActive begins, while the body
-- and trail are started together so the dash feels like one visual action.
function MeraPresentationClient:PlayFlameDashStage(targetPlayer, state, stageName, source)
	if not targetPlayer or not targetPlayer:IsA("Player") or type(state) ~= "table" then
		return false
	end

	local rootPart = state.RootPart
	if not rootPart or not rootPart.Parent then
		return false
	end

	local normalizedStage = string.lower(tostring(stageName or ""))
	local stageSource = tostring(source or "unknown")
	if normalizedStage == "startup" then
		if state.StartupPlayed then
			return false
		end

		state.StartupPlayed = true
		local startupPosition = (typeof(state.StartPosition) == "Vector3" and state.StartPosition)
			or (typeof(state.ServerStartPosition) == "Vector3" and state.ServerStartPosition)
			or rootPart.Position
		local startupDirection = state.StartDirection or rootPart.CFrame.LookVector
		local startupProgressDistance = getLiveFlameDashVfxProgressDistance(
			state,
			startupPosition,
			startupDirection
		)
		logMove("move=FlameDash phase=Start received player=%s source=%s", targetPlayer.Name, stageSource)
		state.StartupState = MeraVfx.PlayFlameDashStartup({
			RootPart = rootPart,
			Direction = startupDirection or getLatchedFlameDashVfxDirection(state, rootPart, state.StartDirection),
			Position = startupPosition
				or (typeof(state.StartPosition) == "Vector3" and state.StartPosition)
				or (typeof(state.ServerStartPosition) == "Vector3" and state.ServerStartPosition)
				or rootPart.Position,
		})
		state.RuntimeState = state.StartupState
		updateFlameDashVfxSnapshot(state, startupPosition, startupProgressDistance)
		logMove("move=FlameDash stage=startup player=%s source=%s", targetPlayer.Name, stageSource)
		logFlameDashTiming(targetPlayer, state, "startup", stageSource, startupPosition or rootPart.Position)
		if not hasLiveFlameDashStageState(state.StartupState) then
			self:EnsureFallbackFlameDashVisual(state, "startup_missing")
		end
		return true
	end

	if normalizedStage == "dashactive" or normalizedStage == "active" or normalizedStage == "dashloop" then
		if state.ActiveStageStarted then
			return false
		end

		state.ActiveStageStarted = true
		state.ActiveStartedAt = os.clock()
		local activePosition = rootPart.Position
		local activeDirection = rootPart.CFrame.LookVector
		local activeProgressDistance = getLiveFlameDashVfxProgressDistance(state, activePosition, activeDirection)
		logMove("move=FlameDash phase=DashActive received player=%s source=%s", targetPlayer.Name, stageSource)
		state.PartState = MeraVfx.StartFlameDashPart({
			RootPart = rootPart,
			Direction = activeDirection or getLatchedFlameDashVfxDirection(state, rootPart, nil),
			Position = activePosition,
			RuntimeState = state.RuntimeState or state.StartupState or state.HeadState or state.PartState,
		})

		state.HeadState = MeraVfx.StartFlameDashHead({
			RootPart = rootPart,
			Direction = activeDirection or getLatchedFlameDashVfxDirection(state, rootPart, nil),
			Position = activePosition,
			RuntimeState = state.RuntimeState or state.StartupState or state.HeadState or state.PartState,
		})
		state.RuntimeState = state.HeadState or state.PartState or state.RuntimeState

		updateFlameDashVfxSnapshot(state, activePosition, activeProgressDistance)
		logMove(
			"move=FlameDash stage=active player=%s source=%s part=%s dash=%s",
			targetPlayer.Name,
			stageSource,
			tostring(state.PartState ~= nil),
			tostring(state.HeadState ~= nil)
		)
		logFlameDashTiming(targetPlayer, state, "active", stageSource, activePosition or rootPart.Position)
		if not hasLiveFlameDashStageState(state.PartState) and not hasLiveFlameDashStageState(state.HeadState) then
			self:EnsureFallbackFlameDashVisual(state, "active_missing")
		end
		return true
	end

	if normalizedStage == "dashend" or normalizedStage == "end" then
		local endMarkerPosition = rootPart.Position
		local endMarkerProgressDistance = getLiveFlameDashVfxProgressDistance(
			state,
			endMarkerPosition,
			rootPart.CFrame.LookVector
		)
		if not isAuthoritativeFlameDashEndSource(stageSource) then
			if not shouldAcceptFlameDashEndHint(state, endMarkerProgressDistance) then
				return false
			end

			if state.EndHintSeen then
				return false
			end

			state.EndHintSeen = true
			updateFlameDashVfxSnapshot(state, endMarkerPosition, endMarkerProgressDistance)
			logMove("move=FlameDash phase=Resolve hint player=%s source=%s", targetPlayer.Name, stageSource)
			logFlameDashTiming(targetPlayer, state, "end_hint", stageSource, endMarkerPosition or rootPart.Position)
			return true
		end

		if state.EndStageSeen then
			return false
		end

		state.EndStageSeen = true
		updateFlameDashVfxSnapshot(state, endMarkerPosition, endMarkerProgressDistance)
		logMove("move=FlameDash phase=Resolve received player=%s source=%s", targetPlayer.Name, stageSource)
		logMove("move=FlameDash stage=end player=%s source=%s", targetPlayer.Name, stageSource)
		logFlameDashTiming(targetPlayer, state, "end_marker", stageSource, endMarkerPosition or rootPart.Position)
		return true
	end

	return false
end

function MeraPresentationClient:ConnectFlameDashTrackPhases(targetPlayer, state, track)
	if not targetPlayer or not targetPlayer:IsA("Player") or type(state) ~= "table" then
		return false
	end

	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return false
	end

	self:DisconnectFlameDashTrackPhases(state)
	state.Track = track
	state.TrackPhaseConnections = {}
	for _, markerName in ipairs(FLAME_DASH_ACTIVE_MARKERS) do
		local ok, connection = pcall(function()
			return track:GetMarkerReachedSignal(markerName):Connect(function()
				if self.activeFlameDashVfxByPlayer[targetPlayer] ~= state then
					return
				end

				self:PlayFlameDashStage(targetPlayer, state, "DashActive", "marker:" .. markerName)
			end)
		end)
		if ok and typeof(connection) == "RBXScriptConnection" then
			table.insert(state.TrackPhaseConnections, connection)
		end
	end
	for _, markerName in ipairs(FLAME_DASH_END_MARKERS) do
		local ok, connection = pcall(function()
			return track:GetMarkerReachedSignal(markerName):Connect(function()
				if self.activeFlameDashVfxByPlayer[targetPlayer] ~= state then
					return
				end

				self:PlayFlameDashStage(targetPlayer, state, "DashEnd", "marker:" .. markerName)
			end)
		end)
		if ok and typeof(connection) == "RBXScriptConnection" then
			table.insert(state.TrackPhaseConnections, connection)
		end
	end
	table.insert(state.TrackPhaseConnections, track.Stopped:Connect(function()
		if self.activeFlameDashVfxByPlayer[targetPlayer] ~= state then
			return
		end

		self:PlayFlameDashStage(targetPlayer, state, "DashEnd", "track_stopped")
	end))

	return true
end

-- ============================================================================
-- FireBurst Presentation State
-- ============================================================================
-- FireBurst is intentionally modeled as one explicit runtime sequence:
-- startup/charge begins once
-- release triggers once
-- cleanup tears down startup, burst, animation, and tasks together
-- This keeps the move understandable and prevents duplicate playback.

function MeraPresentationClient:CreateFireBurstState(targetPlayer, payload, rootPart)
	return {
		TargetPlayer = targetPlayer,
		CastId = getFireBurstCastId(targetPlayer, payload)
			or string.format("fallback:%s:%.6f", tostring(targetPlayer and targetPlayer.UserId or 0), os.clock()),
		RootPart = rootPart,
		-- Sequence flags make it obvious whether this cast has only started, already
		-- released, or has fully completed cleanup.
		Started = false,
		ReleaseTriggered = false,
		Completed = false,
		-- These states come back from `Shared/Vfx` and represent the two visual phases.
		StartupVfxState = nil,
		BurstVfxState = nil,
		-- Animation is tracked here because presentation, not the VFX module, owns the
		-- high-level handoff between charge and release.
		AnimationTrack = nil,
		AnimationPath = nil,
		AnimationFailure = nil,
		CleanupConnections = {},
		CleanupTask = nil,
		ReleaseFallbackTask = nil,
		StartPayload = type(payload) == "table" and payload or {},
		ReleasePayload = nil,
		StartedAt = os.clock(),
		LastPhase = nil,
	}
end

function MeraPresentationClient:StopFireBurstStartupVfx(state, reason, options)
	if type(state) ~= "table" or not state.StartupVfxState then
		return false
	end

	-- Startup cleanup is separated from full cast cleanup because release needs to hand
	-- off cleanly into burst without necessarily finalizing the whole move immediately.
	local startupState = state.StartupVfxState
	state.StartupVfxState = nil
	MeraVfx.StopFireBurstStartup(startupState, options or {
		FadeTime = 0.08,
	})
	logFireBurst(
		"startup vfx stop player=%s cast=%s reason=%s",
		state.TargetPlayer and state.TargetPlayer.Name or "<nil>",
		tostring(state.CastId),
		tostring(reason)
	)
	return true
end

function MeraPresentationClient:FinalizeFireBurstState(targetPlayer, state, reason, options)
	if type(state) ~= "table" or state.Completed then
		return false
	end

	-- Finalization is the single coordinated cleanup path for FireBurst. If someone
	-- needs the move gone, they should come through here instead of stopping pieces
	-- ad hoc.
	state.Completed = true
	if self.activeFireBurstByPlayer[targetPlayer] == state then
		self.activeFireBurstByPlayer[targetPlayer] = nil
	end

	disconnectConnections(state.CleanupConnections)
	cancelTask(state.CleanupTask)
	cancelTask(state.ReleaseFallbackTask)
	state.CleanupTask = nil
	state.ReleaseFallbackTask = nil

	self:StopFireBurstStartupVfx(state, reason, {
		FadeTime = 0.08,
		ImmediateCleanup = options and options.ImmediateCleanup,
	})

	if state.BurstVfxState then
		MeraVfx.StopFireBurst(state.BurstVfxState, {
			FadeTime = 0.12,
			ImmediateCleanup = options and options.ImmediateCleanup,
		})
		state.BurstVfxState = nil
	end

	stopTrack(state.AnimationTrack, self:GetAnimationConfig("FireBurst") and self:GetAnimationConfig("FireBurst").StopFadeTime)
	state.AnimationTrack = nil

	logFireBurst(
		"cleanup complete player=%s cast=%s reason=%s immediate=%s",
		targetPlayer and targetPlayer.Name or "<nil>",
		tostring(state.CastId),
		tostring(reason),
		tostring(options and options.ImmediateCleanup == true)
	)
	return true
end

function MeraPresentationClient:QueueFireBurstCleanup(targetPlayer, state, delaySeconds, reason)
	if type(state) ~= "table" or state.Completed then
		return false
	end

	cancelTask(state.CleanupTask)
	state.CleanupTask = task.delay(math.max(0.05, tonumber(delaySeconds) or 0), function()
		if self.activeFireBurstByPlayer[targetPlayer] ~= state then
			return
		end

		self:FinalizeFireBurstState(targetPlayer, state, reason or "duration_complete")
	end)
	return true
end

function MeraPresentationClient:EnsureFireBurstAnimation(state)
	if type(state) ~= "table" or typeof(state.AnimationTrack) == "Instance" then
		return state and state.AnimationTrack or nil
	end

	local targetPlayer = state.TargetPlayer
	local track, animationPath, loadFailure, selectedCandidate = self:PlayAnimation(targetPlayer, "FireBurst", "Flame burst", "Mera.FlameBurstR6")
	state.AnimationTrack = track
	state.AnimationPath = animationPath
	state.AnimationFailure = loadFailure

	if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		table.insert(state.CleanupConnections, track.Stopped:Connect(function()
			if self.activeFireBurstByPlayer[targetPlayer] ~= state then
				return
			end

			state.AnimationTrack = nil
		end))
		logFireBurst(
			"animation started player=%s cast=%s path=%s id=%s key=%s source=%s trackId=%s",
			targetPlayer and targetPlayer.Name or "<nil>",
			tostring(state.CastId),
			tostring(animationPath),
			tostring(selectedCandidate and selectedCandidate.AnimationId),
			tostring(selectedCandidate and selectedCandidate.LogicalKey),
			tostring(selectedCandidate and selectedCandidate.Source or "resolved_track"),
			tostring(AnimationLoadDiagnostics.GetTrackAnimationId(track) or "<unavailable>")
		)
		return track
	end

	logFireBurst(
		"animation missing player=%s cast=%s path=%s detail=%s",
		targetPlayer and targetPlayer.Name or "<nil>",
		tostring(state.CastId),
		tostring(animationPath),
		tostring(loadFailure or "track_missing")
	)
	return nil
end

function MeraPresentationClient:StopFireBurstStartup(targetPlayer, reason)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local state = self.activeFireBurstByPlayer[targetPlayer]
	if not state then
		return false
	end

	return self:FinalizeFireBurstState(targetPlayer, state, reason or "stop")
end

-- The Start phase is idempotent by design. If predicted/replicated flow delivers the
-- same cast twice, the guard rails below reuse the existing runtime state instead of
-- replaying the charge visual.
function MeraPresentationClient:PlayFireBurstStartup(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	local castId = getFireBurstCastId(targetPlayer, payload)
	local state = self.activeFireBurstByPlayer[targetPlayer]
	if state and (castId == nil or state.CastId ~= castId) then
		self:FinalizeFireBurstState(targetPlayer, state, "restart", {
			ImmediateCleanup = true,
		})
		state = nil
	end

	if not state then
		state = self:CreateFireBurstState(targetPlayer, payload, rootPart)
		self.activeFireBurstByPlayer[targetPlayer] = state
	end

	state.RootPart = rootPart
	state.StartPayload = type(payload) == "table" and payload or {}
	state.LastPhase = "Start"

	if state.ReleaseTriggered then
		logFireBurst("late start ignored player=%s cast=%s", targetPlayer.Name, tostring(state.CastId))
		return true
	end

	if state.Started then
		logFireBurst("start ignored duplicate player=%s cast=%s", targetPlayer.Name, tostring(state.CastId))
		return true
	end

	state.Started = true
	logFireBurst("start received player=%s cast=%s", targetPlayer.Name, tostring(state.CastId))
	self:EnsureFireBurstAnimation(state)

	local abilityConfig = self:GetAbilityConfig("FireBurst")
	local payloadTable = type(payload) == "table" and payload or {}
	state.StartupVfxState = MeraVfx.PlayFireBurstStartup({
		RootPart = rootPart,
		Direction = resolveFacingDirection(rootPart, nil),
		Radius = tonumber(payloadTable.Radius) or tonumber(type(abilityConfig) == "table" and abilityConfig.Radius),
		VisualRadius = payloadTable.VisualRadius,
		VisualBaseRadius = payloadTable.VisualBaseRadius,
		VisualRadiusScale = payloadTable.VisualRadiusScale,
		AutoScaleVisualToHitbox = payloadTable.AutoScaleVisualToHitbox,
	})

	logFireBurst(
		"startup vfx begin player=%s cast=%s success=%s",
		targetPlayer.Name,
		tostring(state.CastId),
		tostring(state.StartupVfxState ~= nil)
	)
	return true
end

function MeraPresentationClient:RequestFlameDashFinalization(targetPlayer, reason, finalPosition, direction, source)
	local state = self.activeFlameDashVfxByPlayer[targetPlayer]
	if not state then
		return false
	end

	local now = os.clock()
	local requestSource = tostring(source or "authoritative")
	local request = state.PendingFinalize or {}
	request.Reason = reason
	request.Source = requestSource
	request.Direction = getLatchedFlameDashDirection(state, state.RootPart, direction or state.Direction)
	request.RequestedAt = now
	if typeof(finalPosition) == "Vector3" then
		request.RequestedFinalPosition = finalPosition
	end

	state.PendingFinalize = request
	return true
end

local function getAuthoritativeFlameDashFinalPosition(state, finalizeData)
	if type(state) ~= "table" then
		return nil
	end

	if typeof(state.ActualEndPosition) == "Vector3" then
		return state.ActualEndPosition
	end
	if typeof(finalizeData and finalizeData.RequestedFinalPosition) == "Vector3" then
		return finalizeData.RequestedFinalPosition
	end
	if typeof(state.ExpectedEndPosition) == "Vector3" then
		return state.ExpectedEndPosition
	end

	return nil
end

function MeraPresentationClient:FinalizeFlameDashVfx(targetPlayer, state, finalizeData, finalPosition, direction)
	if not state or state.Finalized then
		return false
	end

	state.Finalized = true
	self.activeFlameDashVfxByPlayer[targetPlayer] = nil
	self:DisconnectFlameDashTrackPhases(state)

	if typeof(state.UpdateConnection) == "RBXScriptConnection" then
		state.UpdateConnection:Disconnect()
		state.UpdateConnection = nil
	end

	local resolvedDirection = getLatchedFlameDashDirection(state, state.RootPart, direction or state.Direction)
	local resolvedVfxDirection = getLatchedFlameDashVfxDirection(state, state.RootPart, direction or state.Direction)
	local resolvedVisualDirection = getLatchedFlameDashVisualDirection(state, state.RootPart, nil)
	local authoritativeFinalPosition = getAuthoritativeFlameDashFinalPosition(state, finalizeData)
	local resolvedFinalPosition = typeof(authoritativeFinalPosition) == "Vector3"
		and authoritativeFinalPosition
		or (typeof(finalPosition) == "Vector3" and finalPosition)
		or (typeof(state.LastRootPosition) == "Vector3" and state.LastRootPosition or (state.RootPart and state.RootPart.Position))

	state.Direction = resolvedDirection
	state.VisualDirection = resolvedVisualDirection
	state.CurrentFollowDirection = state.CurrentFollowDirection or resolvedDirection
	state.ResolveDirection = resolvedVfxDirection
	state.LastRootPosition = resolvedFinalPosition or state.LastRootPosition
	state.LastVfxPosition = resolvedFinalPosition or state.LastVfxPosition
	if typeof(finalizeData and finalizeData.RequestedFinalPosition) == "Vector3" then
		state.ExpectedEndPosition = finalizeData.RequestedFinalPosition
	end
	if typeof(resolvedFinalPosition) == "Vector3" then
		state.ActualEndPosition = resolvedFinalPosition
	end
	if type(finalizeData and finalizeData.Reason) == "string" and finalizeData.Reason ~= "" then
		state.ResolveReason = finalizeData.Reason
	end

	logMove(
		"move=FlameDash final stop position=%s player=%s reason=%s",
		formatVector3(resolvedFinalPosition),
		targetPlayer.Name,
		tostring(finalizeData and finalizeData.Reason or "complete")
	)
	logFlameDashTiming(targetPlayer, state, "finalize", finalizeData and finalizeData.Source or "unknown", resolvedFinalPosition)

	stopTrack(state.Track, self:GetAnimationConfig("FlameDash") and self:GetAnimationConfig("FlameDash").StopFadeTime)
	state.Track = nil

	MeraVfx.StopFlameDashPart(state.PartState, {
		FadeTime = 0.12,
		FinalPosition = resolvedFinalPosition,
		Direction = resolvedVfxDirection,
	})
	MeraVfx.StopFlameDashHead(state.HeadState, {
		FadeTime = 0.12,
	})
	MeraVfx.StopFlameDashStartup(state.StartupState, {
		FadeTime = 0.08,
	})
	MeraVfx.LogFlameDashCleanup({
		Startup = state.StartupState ~= nil,
		Part = state.PartState ~= nil,
		Dash = state.HeadState ~= nil,
	})

	return true
end

function MeraPresentationClient:TryFinalizeFlameDashVfx(targetPlayer, state, currentPosition, currentDirection)
	local finalizeData = state and state.PendingFinalize
	if not finalizeData then
		return false
	end

	local now = os.clock()
	local elapsed = math.max(0, now - (tonumber(finalizeData.RequestedAt) or now))
	local authoritativeFinalPosition = getAuthoritativeFlameDashFinalPosition(state, finalizeData)
	local trackPlaying = typeof(state.Track) == "Instance"
		and state.Track:IsA("AnimationTrack")
		and state.Track.IsPlaying == true
	if finalizeData.Source == "authoritative" and typeof(authoritativeFinalPosition) == "Vector3" then
		if trackPlaying and elapsed < FLAME_DASH_FINALIZE_MAX_WAIT then
			return false
		end

		return self:FinalizeFlameDashVfx(
			targetPlayer,
			state,
			finalizeData,
			authoritativeFinalPosition,
			finalizeData.Direction or currentDirection
		)
	end

	local planarSpeed = getPlanarMagnitude(state.RootPart and state.RootPart.AssemblyLinearVelocity or nil)
	local requestedFinalPosition = finalizeData.RequestedFinalPosition
	local atRequestedStop = typeof(requestedFinalPosition) ~= "Vector3"
		or getPlanarDistance(currentPosition, requestedFinalPosition) <= FLAME_DASH_FINAL_POSITION_TOLERANCE
	local speedSettled = elapsed >= FLAME_DASH_FINALIZE_SETTLE_TIME and planarSpeed <= FLAME_DASH_STOP_SPEED_THRESHOLD
	local timedOut = elapsed >= FLAME_DASH_FINALIZE_MAX_WAIT

	if not ((speedSettled and atRequestedStop) or timedOut) then
		return false
	end

	return self:FinalizeFlameDashVfx(targetPlayer, state, finalizeData, currentPosition, currentDirection)
end

function MeraPresentationClient:StopFlameDashVfx(targetPlayer, reason, finalPosition, direction)
	local state = self.activeFlameDashVfxByPlayer[targetPlayer]
	if not state then
		return false
	end

	self.activeFlameDashVfxByPlayer[targetPlayer] = nil
	self:DisconnectFlameDashTrackPhases(state)

	if typeof(state.UpdateConnection) == "RBXScriptConnection" then
		state.UpdateConnection:Disconnect()
		state.UpdateConnection = nil
	end

	local resolvedDirection = getLatchedFlameDashDirection(state, state.RootPart, direction or state.Direction)
	stopTrack(state.Track, self:GetAnimationConfig("FlameDash") and self:GetAnimationConfig("FlameDash").StopFadeTime)
	MeraVfx.StopFlameDashPart(state.PartState, {
		ImmediateCleanup = true,
	})
	MeraVfx.StopFlameDashHead(state.HeadState, {
		ImmediateCleanup = true,
	})
	MeraVfx.StopFlameDashStartup(state.StartupState, {
		ImmediateCleanup = true,
	})
	logMove(
		"move=FlameDash attached stop player=%s reason=%s finalPosition=%s direction=%s",
		targetPlayer.Name,
		tostring(reason),
		formatVector3(finalPosition or state.LastRootPosition),
		formatVector3(resolvedDirection)
	)
	MeraVfx.LogFlameDashCleanup({
		Startup = state.StartupState ~= nil,
		Part = state.PartState ~= nil,
		Dash = state.HeadState ~= nil,
	})

	return true
end

function MeraPresentationClient:StartFlameDashVfx(targetPlayer, payload, _track)
	local rootPart = getPlayerRootPart(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	if not rootPart or not character then
		return false
	end

	self:StopFlameDashVfx(targetPlayer, "restart", rootPart.Position, rootPart.CFrame.LookVector)

	local startPosition = typeof(payload) == "table" and payload.StartPosition or nil
	if typeof(startPosition) ~= "Vector3" then
		startPosition = rootPart.Position
	end

	local preferredDirection = typeof(payload) == "table" and payload.Direction or nil
	local preferredVisualDirection = getPayloadVisualDirection(payload)
	local resolvedDirection = resolveDashDirection(rootPart, preferredDirection)
	local resolvedVisualDirection = resolveFacingDirection(rootPart, preferredVisualDirection)
	local state = {
		RootPart = rootPart,
		Character = character,
		StartPosition = startPosition,
		ServerStartPosition = startPosition,
		Direction = resolvedDirection,
		VisualDirection = resolvedVisualDirection,
		StartDirection = resolvedDirection,
		CurrentFollowDirection = resolvedDirection,
		LiveDirection = resolvedDirection,
		ResolveDirection = nil,
		LastRootPosition = rootPart.Position,
		StartedAt = os.clock(),
		ServerStartedAt = getFlameDashStartToken(payload),
		ExpectedEndPosition = typeof(payload) == "table" and payload.EndPosition or nil,
		ActualEndPosition = nil,
		PlannedDistance = tonumber(type(payload) == "table" and payload.Distance) or nil,
		PlannedDuration = tonumber(type(payload) == "table" and payload.Duration) or nil,
		PlannedInstantDistance = tonumber(type(payload) == "table" and payload.InstantDistance) or nil,
		PlannedRemainingDistance = tonumber(type(payload) == "table" and payload.RemainingDistance) or nil,
		ActualDuration = nil,
		ResolveReason = nil,
		StartPayload = typeof(payload) == "table" and payload or nil,
		IsPredicted = false,
		ActiveDelay = computeFlameDashActiveDelay(self:GetAbilityConfig("FlameDash")),
		ActiveStartedAt = nil,
		TrackPhaseConnections = {},
		ActiveStageStarted = false,
		EndHintSeen = false,
		EndStageSeen = false,
		FallbackVisualEmitted = false,
		FallbackVisualReason = nil,
		RuntimeState = nil,
		StartupState = nil,
		PartState = nil,
		HeadState = nil,
		LastVfxPosition = startPosition,
		LastVfxProgressDistance = 0,
	}
	self.activeFlameDashVfxByPlayer[targetPlayer] = state

	logMove(
		"move=FlameDash start player=%s direction=%s startPosition=%s",
		targetPlayer.Name,
		formatVector3(resolvedDirection),
		formatVector3(startPosition)
	)

	state.UpdateConnection = RunService.Heartbeat:Connect(function()
		if self.activeFlameDashVfxByPlayer[targetPlayer] ~= state then
			return
		end

		if not rootPart.Parent or not character.Parent then
			self:StopFlameDashVfx(targetPlayer, "invalid_state", state.LastRootPosition, state.Direction)
			return
		end

		local now = os.clock()
		local currentPosition = rootPart.Position
		local currentDirection = getLatchedFlameDashDirection(state, rootPart, state.Direction)
		state.LiveDirection = resolveDashDirection(rootPart, currentDirection)
		state.CurrentFollowDirection = currentDirection
		state.LastRootPosition = currentPosition

		if not state.ActiveStageStarted and now - state.StartedAt >= state.ActiveDelay then
			self:PlayFlameDashStage(targetPlayer, state, "DashActive", "timed_start")
		end

		local currentVfxPosition = nil
		local currentVfxDirection = nil
		local currentVfxProgressDistance = nil
		if state.ActiveStageStarted then
			currentVfxPosition = rootPart.Position
			currentVfxDirection = rootPart.CFrame.LookVector
			currentVfxProgressDistance = getLiveFlameDashVfxProgressDistance(
				state,
				currentVfxPosition,
				currentVfxDirection
			)
			updateFlameDashVfxSnapshot(state, currentVfxPosition, currentVfxProgressDistance)
		end

		if state.HeadState and not MeraVfx.UpdateFlameDashHead(state.HeadState, {
			Direction = currentVfxDirection or getLatchedFlameDashVfxDirection(state, rootPart, currentDirection),
			Position = currentVfxPosition,
		}) then
			MeraVfx.StopFlameDashHead(state.HeadState, {
				ImmediateCleanup = true,
			})
			state.HeadState = nil
		end

		if state.PartState and not MeraVfx.UpdateFlameDashPart(state.PartState, {
			Direction = currentVfxDirection or getLatchedFlameDashVfxDirection(state, rootPart, currentDirection),
			Position = currentVfxPosition,
		}) then
			MeraVfx.StopFlameDashPart(state.PartState, {
				ImmediateCleanup = true,
			})
			state.PartState = nil
		end

		if not state.PendingFinalize and state.PredictedCompleteAt then
			local predictedElapsed = math.max(0, now - state.PredictedCompleteAt)
			if predictedElapsed >= FLAME_DASH_PREDICTED_FINALIZE_TIMEOUT then
				self:RequestFlameDashFinalization(
					targetPlayer,
					"predicted_timeout_" .. tostring(state.PredictedCompleteReason or "complete"),
					state.PredictedFinalPosition,
					state.PredictedDirection,
					"predicted_fallback"
				)
			end
		end

		if self:TryFinalizeFlameDashVfx(targetPlayer, state, currentPosition, currentDirection) then
			return
		end
	end)

	return state
end

function MeraPresentationClient:PlayAnimation(targetPlayer, moveName, defaultAssetName, defaultAnimationKey, options)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	options = type(options) == "table" and options or {}

	local animationConfig = self:GetAnimationConfig(moveName)
	local legacyAssetName = (animationConfig and animationConfig.AssetName) or defaultAssetName
	local animationKey = (animationConfig and animationConfig.AnimationKey) or defaultAnimationKey
	local failureKey = buildAnimationFailureKey(moveName, animationKey or legacyAssetName, defaultAnimationKey or defaultAssetName)
	local cachedFailure = getCachedAnimationFailure(failureKey)
	if cachedFailure then
		logAnimInfo(
			"move=%s animation load skipped path=%s detail=cached_failure:%s",
			tostring(moveName),
			tostring(cachedFailure.Path),
			tostring(cachedFailure.Detail)
		)
		return nil, cachedFailure.Path, cachedFailure.Detail, nil
	end

	local animator = getAnimator(targetPlayer)
	if not animator then
		local animationPath = MeraAnimationResolver.BuildAnimationPath(animationKey or legacyAssetName)
		logAnimWarn("animation missing or failed to load move=%s path=%s detail=animator_missing", tostring(moveName), tostring(animationPath))
		return nil, animationPath, "animator_missing", nil
	end

	local animationCandidates, candidateNames = MeraAnimationResolver.CollectAnimationCandidates(moveName, legacyAssetName, defaultAssetName, animationKey)
	if #animationCandidates == 0 then
		logAnimWarn(
			"animation candidate catalog empty move=%s path=%s names=%s detail=no_animation_candidates",
			tostring(moveName),
			tostring(MeraAnimationResolver.BuildAnimationPath((candidateNames and candidateNames[1]) or legacyAssetName or animationKey)),
			table.concat(candidateNames or {}, "|")
		)
	end
	local selectedTrack
	local selectedCandidate
	local lastFailure = "missing_animation"
	local rejectedPermissionCandidate
	local rejectedLoadCandidate

	for _, candidate in ipairs(animationCandidates) do
		local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
			animator,
			candidate.Animation,
			SOURCE_LABEL
		)
		if track then
			selectedTrack = track
			selectedCandidate = candidate
			break
		end

		lastFailure = loadFailure or lastFailure
		if AnimationLoadDiagnostics.IsPermissionFailure(loadFailure) then
			rejectedPermissionCandidate = rejectedPermissionCandidate or candidate
			logAnimWarn(
				"animation candidate rejected move=%s path=%s id=%s source=%s detail=%s",
				tostring(moveName),
				tostring(candidate.Path),
				tostring(candidate.AnimationId),
				tostring(candidate.Source),
				tostring(loadFailure)
			)
		else
			rejectedLoadCandidate = rejectedLoadCandidate or candidate
			logAnimInfo(
				"move=%s animation candidate rejected path=%s id=%s source=%s detail=%s",
				tostring(moveName),
				tostring(candidate.Path),
				tostring(candidate.AnimationId),
				tostring(candidate.Source),
				tostring(loadFailure)
			)
		end
	end

	if not selectedTrack then
		local rejectedCandidate = rejectedPermissionCandidate or rejectedLoadCandidate
		local primaryPath = rejectedCandidate and rejectedCandidate.Path
			or MeraAnimationResolver.BuildAnimationPath((candidateNames and candidateNames[1]) or legacyAssetName or animationKey)
		local detail = lastFailure
		if rejectedPermissionCandidate then
			detail = string.format("permission_denied:%s", tostring(rejectedPermissionCandidate.AnimationId))
		end

		logAnimWarn(
			"animation missing or failed to load move=%s path=%s detail=%s",
			tostring(moveName),
			tostring(primaryPath),
			tostring(detail)
		)
		rememberAnimationFailure(failureKey, primaryPath, detail)
		return nil, primaryPath, detail, rejectedCandidate
	end

	local bucket = self:GetTrackBucket(targetPlayer)
	stopTrack(bucket[moveName], animationConfig and animationConfig.StopFadeTime)
	bucket[moveName] = selectedTrack

	local fadeTime = math.max(0, tonumber(animationConfig and animationConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(animationConfig and animationConfig.PlaybackSpeed) or 1

	selectedTrack.Priority = Enum.AnimationPriority.Action
	selectedTrack.Looped = animationConfig and animationConfig.Looped == true or false
	if options.DeferPlay ~= true then
		local ok, err = pcall(function()
			selectedTrack:Play(fadeTime, 1, playbackSpeed)
		end)
		if not ok then
			if bucket[moveName] == selectedTrack then
				bucket[moveName] = nil
			end
			stopTrack(selectedTrack, animationConfig and animationConfig.StopFadeTime)
			logAnimWarn(
				"animation missing or failed to load move=%s path=%s detail=play_failed:%s",
				tostring(moveName),
				tostring(selectedCandidate and selectedCandidate.Path),
				tostring(err)
			)
			rememberAnimationFailure(
				failureKey,
				selectedCandidate and selectedCandidate.Path,
				string.format("play_failed:%s", tostring(err))
			)
			return nil, selectedCandidate and selectedCandidate.Path, tostring(err), selectedCandidate
		end
		AnimationLoadDiagnostics.LogTrackPlay(
			selectedTrack,
			SOURCE_LABEL,
			string.format("Mera.%s", tostring(moveName)),
			selectedCandidate and selectedCandidate.AnimationId,
			string.format(
				"key=%s path=%s source=%s fade=%.3f speed=%.3f looped=%s deferred=false",
				tostring(selectedCandidate and selectedCandidate.LogicalKey or animationKey or "<legacy>"),
				tostring(selectedCandidate and selectedCandidate.Path),
				tostring(selectedCandidate and selectedCandidate.Source),
				fadeTime,
				playbackSpeed,
				tostring(selectedTrack.Looped)
			)
		)
	end
	selectedTrack.Stopped:Connect(function()
		if bucket[moveName] == selectedTrack then
			bucket[moveName] = nil
		end
	end)
	logAnimInfo(
		"move=%s animation selected path=%s id=%s source=%s",
		tostring(moveName),
		tostring(selectedCandidate and selectedCandidate.Path),
		tostring(selectedCandidate and selectedCandidate.AnimationId),
		tostring(selectedCandidate and selectedCandidate.Source)
	)
	clearAnimationFailure(failureKey)

	return selectedTrack, selectedCandidate and selectedCandidate.Path, nil, selectedCandidate
end

function MeraPresentationClient:PlayFlameDashStartup(targetPlayer, _payload, _isPredicted)
	logMove("move=FlameDash entry=start player=%s", targetPlayer and targetPlayer.Name or "<nil>")
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	local animationConfig = self:GetAnimationConfig("FlameDash")
	local track, animationPath, loadFailure, selectedCandidate = self:PlayAnimation(targetPlayer, "FlameDash", "Flame Dash", "Mera.FlameDash", {
		DeferPlay = true,
	})
	local state = self:StartFlameDashVfx(targetPlayer, _payload or {}, track)
	if not state then
		return false
	end

	state.IsPredicted = _isPredicted == true
	self:PlayFlameDashStage(targetPlayer, state, "Startup", "fresh_start")

	if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		self:ConnectFlameDashTrackPhases(targetPlayer, state, track)
		local fadeTime = math.max(0, tonumber(animationConfig and animationConfig.FadeTime) or DEFAULT_FADE_TIME)
		local playbackSpeed = tonumber(animationConfig and animationConfig.PlaybackSpeed) or 1
		local ok, err = pcall(function()
			track:Play(fadeTime, 1, playbackSpeed)
		end)
		if ok then
			AnimationLoadDiagnostics.LogTrackPlay(
				track,
				SOURCE_LABEL,
				"Mera.FlameDash",
				selectedCandidate and selectedCandidate.AnimationId,
				string.format(
					"key=%s path=%s source=%s fade=%.3f speed=%.3f looped=%s deferred=true",
					tostring(selectedCandidate and selectedCandidate.LogicalKey or "Mera.FlameDash"),
					tostring(animationPath),
					tostring(selectedCandidate and selectedCandidate.Source),
					fadeTime,
					playbackSpeed,
					tostring(track.Looped)
				)
			)
			logMove(
				"move=FlameDash animation player=%s path=%s id=%s key=%s source=%s trackId=%s",
				targetPlayer.Name,
				tostring(animationPath),
				tostring(selectedCandidate and selectedCandidate.AnimationId),
				tostring(selectedCandidate and selectedCandidate.LogicalKey),
				tostring(selectedCandidate and selectedCandidate.Source or "resolved_track"),
				tostring(AnimationLoadDiagnostics.GetTrackAnimationId(track) or "<unavailable>")
			)
		else
			logAnimWarn(
				"animation missing or failed to load move=%s path=%s detail=play_failed:%s",
				"FlameDash",
				tostring(animationPath),
				tostring(err)
			)
			logMove(
				"move=FlameDash animation player=%s path=%s source=vfx_only_last_resort detail=play_failed:%s",
				targetPlayer.Name,
				tostring(animationPath),
				tostring(err)
			)
		end
	else
		logMove(
			"move=FlameDash animation player=%s path=%s source=vfx_only_last_resort detail=%s",
			targetPlayer.Name,
			tostring(animationPath),
			tostring(loadFailure or "track_missing")
		)
	end

	return true
end

function MeraPresentationClient:PlayFlameDashComplete(targetPlayer, payload)
	logMove("move=FlameDash entry=resolve player=%s", targetPlayer and targetPlayer.Name or "<nil>")
	local finalPosition = type(payload) == "table" and (payload.ActualEndPosition or payload.EndPosition) or nil
	local finalDirection = type(payload) == "table" and payload.Direction or nil
	local reason = type(payload) == "table" and payload.ResolveReason or "server_resolve"
	local state = self.activeFlameDashVfxByPlayer[targetPlayer]
	if state then
		self:RefreshFlameDashState(state, payload, state.RootPart)
		self:PlayFlameDashStage(targetPlayer, state, "DashEnd", "server_resolve")
	end
	self:RequestFlameDashFinalization(targetPlayer, reason, finalPosition, finalDirection, "authoritative")
	return true
end

function MeraPresentationClient:MarkFlameDashTrailPredictedComplete(targetPlayer, reason, finalPosition, direction)
	local state = self.activeFlameDashVfxByPlayer[targetPlayer]
	if not state then
		return false
	end

	state.PredictedCompleteAt = os.clock()
	state.PredictedCompleteReason = reason
	state.PredictedFinalPosition = typeof(finalPosition) == "Vector3" and finalPosition or state.LastRootPosition
	state.PredictedDirection = getLatchedFlameDashDirection(state, state.RootPart, direction or state.Direction)
	return true
end

function MeraPresentationClient:StopFlameDashTrail(targetPlayer, reason, finalPosition, direction)
	self:StopFlameDashVfx(targetPlayer, reason, finalPosition, direction)
	return true
end

function MeraPresentationClient:HandleFireBurstEffect(targetPlayer, payload)
	local phase = type(payload) == "table" and payload.Phase or nil
	logFireBurst(
		"effect received player=%s cast=%s phase=%s",
		targetPlayer and targetPlayer.Name or "<nil>",
		tostring(getFireBurstCastId(targetPlayer, payload)),
		tostring(phase or "Release")
	)
	if phase == "Start" then
		return self:PlayFireBurstStartup(targetPlayer, payload)
	end

	return self:PlayFireBurstRelease(targetPlayer, payload)
end

-- Release is exactly-once for a given cast. By the time this runs, the server has
-- already decided whether the animation marker or fallback timing won.
function MeraPresentationClient:PlayFireBurstRelease(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	local castId = getFireBurstCastId(targetPlayer, payload)
	local state = self.activeFireBurstByPlayer[targetPlayer]
	if state and castId and state.CastId ~= castId then
		self:FinalizeFireBurstState(targetPlayer, state, "replaced_before_release", {
			ImmediateCleanup = true,
		})
		state = nil
	end

	if not state then
		state = self:CreateFireBurstState(targetPlayer, payload, rootPart)
		self.activeFireBurstByPlayer[targetPlayer] = state
	end

	if state.ReleaseTriggered then
		logFireBurst("release ignored duplicate player=%s cast=%s", targetPlayer.Name, tostring(state.CastId))
		return true
	end

	state.RootPart = rootPart
	state.ReleaseTriggered = true
	state.ReleasePayload = type(payload) == "table" and payload or {}
	state.LastPhase = "Release"

	local abilityConfig = self:GetAbilityConfig("FireBurst")
	local payloadTable = type(payload) == "table" and payload or {}
	local duration = math.max(
		0.05,
		tonumber(payloadTable.Duration)
			or tonumber(type(abilityConfig) == "table" and abilityConfig.Duration)
			or FIRE_BURST_DEFAULT_DURATION
	)
	local radius = math.max(0, tonumber(payloadTable.Radius) or tonumber(type(abilityConfig) == "table" and abilityConfig.Radius) or 0)
	local releaseSource = payloadTable.ReleaseSource

	local startupRuntimeState = state.StartupVfxState
	state.StartupVfxState = nil

	state.BurstVfxState = MeraVfx.PlayFireBurst({
		ExistingState = startupRuntimeState,
		RootPart = rootPart,
		Direction = resolveFacingDirection(rootPart, nil),
		Duration = duration,
		Radius = radius,
		VisualRadius = payloadTable.VisualRadius,
		VisualBaseRadius = payloadTable.VisualBaseRadius,
		VisualRadiusScale = payloadTable.VisualRadiusScale,
		AutoScaleVisualToHitbox = payloadTable.AutoScaleVisualToHitbox,
	})

	if not state.BurstVfxState then
		state.StartupVfxState = startupRuntimeState
	end

	logFireBurst(
		"release triggered player=%s cast=%s source=%s radius=%.2f duration=%.2f burst=%s",
		targetPlayer.Name,
		tostring(state.CastId),
		tostring(releaseSource or "unknown"),
		radius,
		duration,
		tostring(state.BurstVfxState ~= nil)
	)
	self:QueueFireBurstCleanup(targetPlayer, state, duration + FIRE_BURST_CLEANUP_GRACE, "duration_complete")
	return true
end

function MeraPresentationClient:HandleCharacterRemoving(targetPlayer)
	local player = targetPlayer
	if not player or not player:IsA("Player") then
		player = self.player
	end

	local bucket = player and self.activeTracksByPlayer[player]
	if bucket then
		clearTrackBucket(bucket)
		self.activeTracksByPlayer[player] = nil
	end

	local fireBurstState = player and self.activeFireBurstByPlayer[player]
	if fireBurstState then
		self:FinalizeFireBurstState(player, fireBurstState, "character_removing", {
			ImmediateCleanup = true,
		})
	end
	self:StopFlameDashVfx(player)
end

function MeraPresentationClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer and leavingPlayer:IsA("Player") then
		self:HandleCharacterRemoving(leavingPlayer)
	end
end

return MeraPresentationClient
