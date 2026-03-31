local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
local PREVIOUS_FIRE_BURST_RADIUS = 50
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
local FLAME_DASH_ACTIVE_MARKERS = { "Jump", "DashStart", "DashActive", "DashLoop", "Dash", "Swipe" }
local FLAME_DASH_END_MARKERS = { "DashEnd", "End", "Launch", "Complete", "Stop" }
local ANIMATION_FAILURE_RETRY_COOLDOWN = 10

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

function MeraPresentationClient.new(config)
	local self = setmetatable({}, MeraPresentationClient)
	self.player = config and config.player or Players.LocalPlayer
	self.activeTracksByPlayer = setmetatable({}, { __mode = "k" })
	self.activeFlameDashVfxByPlayer = setmetatable({}, { __mode = "k" })
	self.activeFireBurstStartupByPlayer = setmetatable({}, { __mode = "k" })
	return self
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
		logMove("move=FlameDash phase=Start received player=%s source=%s", targetPlayer.Name, stageSource)
		state.StartupState = MeraVfx.PlayFlameDashStartup({
			RootPart = rootPart,
			Direction = state.Direction,
		})
		logMove("move=FlameDash stage=startup player=%s source=%s", targetPlayer.Name, stageSource)
		return true
	end

	if normalizedStage == "dashactive" or normalizedStage == "active" or normalizedStage == "dashloop" then
		if state.ActiveStageStarted then
			return false
		end

		state.ActiveStageStarted = true
		logMove("move=FlameDash phase=DashActive received player=%s source=%s", targetPlayer.Name, stageSource)
		state.PartState = MeraVfx.StartFlameDashPart({
			RootPart = rootPart,
			Direction = state.Direction,
		})

		state.HeadState = MeraVfx.StartFlameDashHead({
			RootPart = rootPart,
			Direction = state.Direction,
		})

		logMove(
			"move=FlameDash stage=active player=%s source=%s part=%s dash=%s",
			targetPlayer.Name,
			stageSource,
			tostring(state.PartState ~= nil),
			tostring(state.HeadState ~= nil)
		)
		return true
	end

	if normalizedStage == "dashend" or normalizedStage == "end" then
		if state.EndStageSeen then
			return false
		end

		state.EndStageSeen = true
		logMove("move=FlameDash phase=Resolve received player=%s source=%s", targetPlayer.Name, stageSource)
		logMove("move=FlameDash stage=end player=%s source=%s", targetPlayer.Name, stageSource)
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

function MeraPresentationClient:StopFireBurstStartup(targetPlayer, reason)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local state = self.activeFireBurstStartupByPlayer[targetPlayer]
	if not state then
		return false
	end

	self.activeFireBurstStartupByPlayer[targetPlayer] = nil
	MeraVfx.StopRuntimeState(state, {
		FadeTime = 0.1,
	})
	logMove("move=FlameBurst startup stop player=%s reason=%s", targetPlayer.Name, tostring(reason))
	return true
end

function MeraPresentationClient:PlayFireBurstStartup(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	self:StopFireBurstStartup(targetPlayer, "restart")

	logMove("move=FlameBurst phase=Start received player=%s", targetPlayer.Name)
	local state = MeraVfx.PlayFireBurstStartup({
		RootPart = rootPart,
		Direction = rootPart.CFrame.LookVector,
		Lifetime = math.max(0.25, tonumber(type(payload) == "table" and payload.StartupLifetime) or 0.45),
		FollowDuration = math.max(0, tonumber(type(payload) == "table" and payload.StartupFollowDuration) or 0.18),
	})
	if state then
		self.activeFireBurstStartupByPlayer[targetPlayer] = state
	end

	logMove("move=FlameBurst startup player=%s", targetPlayer.Name)
	return state ~= nil
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
	request.Direction = resolveDashDirection(state.RootPart, direction or state.Direction)
	request.RequestedAt = now
	if typeof(finalPosition) == "Vector3" then
		request.RequestedFinalPosition = finalPosition
	end

	state.PendingFinalize = request
	return true
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

	local resolvedDirection = resolveDashDirection(state.RootPart, direction or state.Direction)
	local resolvedFinalPosition = typeof(finalPosition) == "Vector3"
		and finalPosition
		or (typeof(state.LastRootPosition) == "Vector3" and state.LastRootPosition or (state.RootPart and state.RootPart.Position))
	if typeof(resolvedFinalPosition) ~= "Vector3" and typeof(finalizeData and finalizeData.RequestedFinalPosition) == "Vector3" then
		resolvedFinalPosition = finalizeData.RequestedFinalPosition
	end

	state.Direction = resolvedDirection
	state.LastRootPosition = resolvedFinalPosition or state.LastRootPosition

	logMove(
		"move=FlameDash final stop position=%s player=%s reason=%s",
		formatVector3(resolvedFinalPosition),
		targetPlayer.Name,
		tostring(finalizeData and finalizeData.Reason or "complete")
	)

	stopTrack(state.Track, self:GetAnimationConfig("FlameDash") and self:GetAnimationConfig("FlameDash").StopFadeTime)
	MeraVfx.StopFlameDashPart(state.PartState, {
		FadeTime = 0.12,
	})
	MeraVfx.StopFlameDashHead(state.HeadState, {
		FadeTime = 0.12,
	})
	MeraVfx.StopRuntimeState(state.StartupState, {
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

	local resolvedDirection = resolveDashDirection(state.RootPart, direction or state.Direction)
	stopTrack(state.Track, self:GetAnimationConfig("FlameDash") and self:GetAnimationConfig("FlameDash").StopFadeTime)
	MeraVfx.StopFlameDashPart(state.PartState, {
		ImmediateCleanup = true,
	})
	MeraVfx.StopFlameDashHead(state.HeadState, {
		ImmediateCleanup = true,
	})
	MeraVfx.StopRuntimeState(state.StartupState, {
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
	local resolvedDirection = resolveDashDirection(rootPart, preferredDirection)
	local state = {
		RootPart = rootPart,
		Character = character,
		Direction = resolvedDirection,
		LastRootPosition = rootPart.Position,
		StartedAt = os.clock(),
		ActiveDelay = computeFlameDashActiveDelay(self:GetAbilityConfig("FlameDash")),
		TrackPhaseConnections = {},
		ActiveStageStarted = false,
		EndStageSeen = false,
		StartupState = nil,
		PartState = nil,
		HeadState = nil,
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
		local currentDirection = resolveDashDirection(rootPart, state.Direction)
		state.Direction = currentDirection
		state.LastRootPosition = currentPosition

		if not state.ActiveStageStarted and now - state.StartedAt >= state.ActiveDelay then
			self:PlayFlameDashStage(targetPlayer, state, "DashActive", "timed_start")
		end

		if state.HeadState and not MeraVfx.UpdateFlameDashHead(state.HeadState, {
			Direction = currentDirection,
		}) then
			MeraVfx.StopFlameDashHead(state.HeadState, {
				ImmediateCleanup = true,
			})
			state.HeadState = nil
		end

		if state.PartState and not MeraVfx.UpdateFlameDashPart(state.PartState, {
			Direction = currentDirection,
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

function MeraPresentationClient:PlayAnimation(targetPlayer, moveName, defaultAssetName, options)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	options = type(options) == "table" and options or {}

	local animationConfig = self:GetAnimationConfig(moveName)
	local assetName = (animationConfig and animationConfig.AssetName) or defaultAssetName
	local failureKey = buildAnimationFailureKey(moveName, assetName, defaultAssetName)
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
		local animationPath = MeraAnimationResolver.BuildAnimationPath(assetName)
		logAnimWarn("animation missing or failed to load move=%s path=%s detail=animator_missing", tostring(moveName), tostring(animationPath))
		return nil, animationPath, "animator_missing", nil
	end

	local animationCandidates, candidateNames = MeraAnimationResolver.CollectAnimationCandidates(moveName, assetName, defaultAssetName)
	local selectedTrack
	local selectedCandidate
	local lastFailure = "missing_animation"
	local rejectedPermissionCandidate
	local rejectedLoadCandidate

	for _, candidate in ipairs(animationCandidates) do
		local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
			animator,
			candidate.Animation,
			"ReplicatedStorage.Modules.DevilFruits.MeraPresentationClient"
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
			or MeraAnimationResolver.BuildAnimationPath((candidateNames and candidateNames[1]) or assetName)
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
	local track, animationPath, loadFailure, selectedCandidate = self:PlayAnimation(targetPlayer, "FlameDash", "Flame Dash", {
		DeferPlay = true,
	})
	local state = self:StartFlameDashVfx(targetPlayer, _payload or {}, track)
	if not state then
		return false
	end

	self:PlayFlameDashStage(targetPlayer, state, "Startup", "fresh_start")

	if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		self:ConnectFlameDashTrackPhases(targetPlayer, state, track)
		local fadeTime = math.max(0, tonumber(animationConfig and animationConfig.FadeTime) or DEFAULT_FADE_TIME)
		local playbackSpeed = tonumber(animationConfig and animationConfig.PlaybackSpeed) or 1
		local ok, err = pcall(function()
			track:Play(fadeTime, 1, playbackSpeed)
		end)
		if ok then
			logMove(
				"move=FlameDash animation player=%s path=%s source=%s",
				targetPlayer.Name,
				tostring(animationPath),
				tostring(selectedCandidate and selectedCandidate.Source or "resolved_track")
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
	state.PredictedDirection = resolveDashDirection(state.RootPart, direction or state.Direction)
	return true
end

function MeraPresentationClient:StopFlameDashTrail(targetPlayer, reason, finalPosition, direction)
	self:StopFlameDashVfx(targetPlayer, reason, finalPosition, direction)
	return true
end

function MeraPresentationClient:HandleFireBurstEffect(targetPlayer, payload)
	local phase = type(payload) == "table" and payload.Phase or nil
	logMove("move=FlameBurst entry=phase player=%s phase=%s", targetPlayer and targetPlayer.Name or "<nil>", tostring(phase or "Release"))
	if phase == "Start" then
		return self:PlayFireBurstStartup(targetPlayer, payload)
	end

	self:StopFireBurstStartup(targetPlayer, phase or "release")
	return self:PlayFireBurstRelease(targetPlayer, payload)
end

function MeraPresentationClient:PlayFireBurstRelease(targetPlayer, payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	self:StopFireBurstStartup(targetPlayer, "release")

	local duration = math.max(0, tonumber(type(payload) == "table" and payload.Duration) or 0)
	local radius = math.max(0, tonumber(type(payload) == "table" and payload.Radius) or 0)
	logMove("move=FlameBurst phase=Release received player=%s", targetPlayer.Name)
	logMove("move=FlameBurst radius old=%s new=%s", tostring(PREVIOUS_FIRE_BURST_RADIUS), tostring(radius))
	MeraVfx.PlayFireBurst({
		RootPart = rootPart,
		Direction = rootPart.CFrame.LookVector,
		Duration = duration,
		Radius = radius,
	})

	logMove("move=FlameBurst release player=%s", targetPlayer.Name)
	if duration > 0 then
		task.delay(duration, function()
			if targetPlayer.Parent ~= nil then
				logMove("move=FlameBurst complete player=%s", targetPlayer.Name)
			end
		end)
	else
		logMove("move=FlameBurst complete player=%s", targetPlayer.Name)
	end

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

	self:StopFireBurstStartup(player, "character_removing")
	self:StopFlameDashVfx(player)
end

function MeraPresentationClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer and leavingPlayer:IsA("Player") then
		self:HandleCharacterRemoving(leavingPlayer)
	end
end

return MeraPresentationClient
