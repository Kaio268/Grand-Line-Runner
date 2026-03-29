local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local AnimationLoadDiagnostics = require(Modules:WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local MeraVfx = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraVfx"))

local MeraPresentationClient = {}
MeraPresentationClient.__index = MeraPresentationClient

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3
local DEFAULT_FADE_TIME = 0.05
local DEFAULT_STOP_FADE_TIME = 0.08
local PREVIOUS_FIRE_BURST_RADIUS = 50
local FLAME_DASH_TRAIL_SPACING = 2.8
local FLAME_DASH_STOP_SPEED_THRESHOLD = 3
local FLAME_DASH_FINAL_POSITION_TOLERANCE = 1.25
local FLAME_DASH_FINALIZE_SETTLE_TIME = 0.05
local FLAME_DASH_FINALIZE_MAX_WAIT = 0.35
local FLAME_DASH_PREDICTED_FINALIZE_TIMEOUT = 0.75
local FLAME_DASH_TRAIL_POST_STOP_HOLD_DURATION = 0.65
local FLAME_DASH_TRAIL_ORDERED_FADE_DURATION = 0.09
local FLAME_DASH_TRAIL_ORDERED_FADE_STEP_INTERVAL = 0.04
local FLAME_DASH_FINAL_STAMP_EPSILON = 0.05

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

local function buildAnimationPath(assetName)
	return string.format("ReplicatedStorage/Assets/Animations/Mera/%s", tostring(assetName or ""))
end

local function getAnimationFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local animationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	local meraFolder = animationsFolder and animationsFolder:FindFirstChild("Mera")
	if meraFolder then
		return meraFolder
	end

	return nil
end

local function getAnimationAsset(moveName, assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		logAnimWarn("animation missing or failed to load move=%s detail=invalid_asset_name", tostring(moveName))
		return nil, nil
	end

	local animationPath = buildAnimationPath(assetName)
	local meraFolder = getAnimationFolder()
	if not meraFolder then
		logAnimWarn("animation missing or failed to load move=%s path=ReplicatedStorage/Assets/Animations/Mera detail=missing_folder", tostring(moveName))
		return nil, animationPath
	end

	local animation = meraFolder:FindFirstChild(assetName)
	if animation and animation:IsA("Animation") then
		logAnimInfo("move=%s animation selected=%s", tostring(moveName), animationPath)
		return animation, animationPath
	end

	logAnimWarn("animation missing or failed to load move=%s path=%s detail=missing_animation", tostring(moveName), animationPath)
	return nil, animationPath
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

function MeraPresentationClient.new(config)
	local self = setmetatable({}, MeraPresentationClient)
	self.player = config and config.player or Players.LocalPlayer
	self.activeTracksByPlayer = setmetatable({}, { __mode = "k" })
	self.activeFlameDashVfxByPlayer = setmetatable({}, { __mode = "k" })
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

function MeraPresentationClient:FillFlameDashTrailToFinalStop(state, finalPosition, direction)
	if not state or not state.TrailState or typeof(finalPosition) ~= "Vector3" then
		return 0
	end

	local sampledPosition = typeof(state.LastTrailSamplePosition) == "Vector3" and state.LastTrailSamplePosition or finalPosition
	local segment = finalPosition - sampledPosition
	local planarSegment = Vector3.new(segment.X, 0, segment.Z)
	local segmentDistance = planarSegment.Magnitude
	local segmentDirection = getPlanarDirection(planarSegment, direction or state.Direction)
	local addedStamps = 0

	while segmentDistance >= FLAME_DASH_TRAIL_SPACING do
		sampledPosition = sampledPosition + (segmentDirection * FLAME_DASH_TRAIL_SPACING)
		sampledPosition = Vector3.new(sampledPosition.X, finalPosition.Y, sampledPosition.Z)
		if MeraVfx.UpdateFlameDashTrail(state.TrailState, {
			Position = sampledPosition,
			Direction = segmentDirection,
		}) then
			addedStamps += 1
		end
		segmentDistance -= FLAME_DASH_TRAIL_SPACING
	end

	if getPlanarDistance(sampledPosition, finalPosition) > FLAME_DASH_FINAL_STAMP_EPSILON
		or math.abs(sampledPosition.Y - finalPosition.Y) > FLAME_DASH_FINAL_STAMP_EPSILON then
		if MeraVfx.UpdateFlameDashTrail(state.TrailState, {
			Position = finalPosition,
			Direction = segmentDirection,
		}) then
			addedStamps += 1
		end
	end

	state.LastTrailSamplePosition = finalPosition
	return addedStamps
end

function MeraPresentationClient:FinalizeFlameDashVfx(targetPlayer, state, finalizeData, finalPosition, direction)
	if not state or state.Finalized then
		return false
	end

	state.Finalized = true
	self.activeFlameDashVfxByPlayer[targetPlayer] = nil

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

	self:FillFlameDashTrailToFinalStop(state, resolvedFinalPosition, resolvedDirection)

	MeraVfx.StopFlameDashTrail(state.TrailState, {
		Direction = resolvedDirection,
		HoldDuration = FLAME_DASH_TRAIL_POST_STOP_HOLD_DURATION,
		OrderedFadeDuration = FLAME_DASH_TRAIL_ORDERED_FADE_DURATION,
		OrderedFadeStepInterval = FLAME_DASH_TRAIL_ORDERED_FADE_STEP_INTERVAL,
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

	if typeof(state.UpdateConnection) == "RBXScriptConnection" then
		state.UpdateConnection:Disconnect()
	end

	local resolvedDirection = resolveDashDirection(state.RootPart, direction or state.Direction)
	MeraVfx.StopFlameDashTrail(state.TrailState, {
		Direction = resolvedDirection,
		ImmediateCleanup = true,
	})
	logMove(
		"move=FlameDash trail stop player=%s reason=%s finalPosition=%s direction=%s stamps=%d",
		targetPlayer.Name,
		tostring(reason),
		formatVector3(finalPosition or state.LastRootPosition),
		formatVector3(resolvedDirection),
		tonumber(state.TrailState and state.TrailState.StampCount) or 0
	)

	return true
end

function MeraPresentationClient:EmitFlameDashTrail(targetPlayer, position, direction)
	local state = self.activeFlameDashVfxByPlayer[targetPlayer]
	if not state or not state.TrailState then
		return false
	end

	MeraVfx.UpdateFlameDashTrail(state.TrailState, {
		Position = position,
		Direction = direction,
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
		LastTrailSamplePosition = startPosition,
	}

	state.TrailState = MeraVfx.StartFlameDashTrail({
		RootPart = rootPart,
		Direction = resolvedDirection,
	})
	self.activeFlameDashVfxByPlayer[targetPlayer] = state

	logMove(
		"move=FlameDash start player=%s direction=%s startPosition=%s",
		targetPlayer.Name,
		formatVector3(resolvedDirection),
		formatVector3(startPosition)
	)
	logMove(
		"move=FlameDash trail start player=%s startPosition=%s spacing=%.2f direction=%s",
		targetPlayer.Name,
		formatVector3(startPosition),
		FLAME_DASH_TRAIL_SPACING,
		formatVector3(resolvedDirection)
	)
	self:EmitFlameDashTrail(targetPlayer, startPosition, resolvedDirection)

	state.UpdateConnection = RunService.Heartbeat:Connect(function()
		if self.activeFlameDashVfxByPlayer[targetPlayer] ~= state then
			return
		end

		if not rootPart.Parent or not character.Parent then
			self:StopFlameDashVfx(targetPlayer, "invalid_state", state.LastRootPosition, state.Direction)
			return
		end

		local currentPosition = rootPart.Position
		local currentDirection = resolveDashDirection(rootPart, state.Direction)
		state.Direction = currentDirection
		state.LastRootPosition = currentPosition

		local segment = currentPosition - state.LastTrailSamplePosition
		local planarSegment = Vector3.new(segment.X, 0, segment.Z)
		local segmentDistance = planarSegment.Magnitude
		local now = os.clock()
		if segmentDistance >= FLAME_DASH_TRAIL_SPACING then
			local segmentDirection = getPlanarDirection(planarSegment, currentDirection)
			local sampledPosition = state.LastTrailSamplePosition
			while segmentDistance >= FLAME_DASH_TRAIL_SPACING do
				sampledPosition = sampledPosition + (segmentDirection * FLAME_DASH_TRAIL_SPACING)
				sampledPosition = Vector3.new(sampledPosition.X, currentPosition.Y, sampledPosition.Z)
				self:EmitFlameDashTrail(targetPlayer, sampledPosition, segmentDirection)
				segmentDistance = segmentDistance - FLAME_DASH_TRAIL_SPACING
			end

			state.LastTrailSamplePosition = sampledPosition
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

	return true
end

function MeraPresentationClient:PlayAnimation(targetPlayer, moveName, defaultAssetName, options)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	options = type(options) == "table" and options or {}

	local animationConfig = self:GetAnimationConfig(moveName)
	local assetName = (animationConfig and animationConfig.AssetName) or defaultAssetName
	local animation, animationPath = getAnimationAsset(moveName, assetName)
	if not animation then
		return nil
	end

	local animator = getAnimator(targetPlayer)
	if not animator then
		logAnimWarn("animation missing or failed to load move=%s path=%s detail=animator_missing", tostring(moveName), tostring(animationPath))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		"ReplicatedStorage.Modules.DevilFruits.MeraPresentationClient"
	)
	if not track then
		logAnimWarn(
			"animation missing or failed to load move=%s path=%s detail=%s",
			tostring(moveName),
			tostring(animationPath),
			tostring(loadFailure)
		)
		return nil
	end

	local bucket = self:GetTrackBucket(targetPlayer)
	stopTrack(bucket[moveName], animationConfig and animationConfig.StopFadeTime)
	bucket[moveName] = track

	local fadeTime = math.max(0, tonumber(animationConfig and animationConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(animationConfig and animationConfig.PlaybackSpeed) or 1

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = animationConfig and animationConfig.Looped == true or false
	if options.DeferPlay ~= true then
		track:Play(fadeTime, 1, playbackSpeed)
	end
	track.Stopped:Connect(function()
		if bucket[moveName] == track then
			bucket[moveName] = nil
		end
	end)

	return track
end

function MeraPresentationClient:PlayFlameDashStartup(targetPlayer, _payload, _isPredicted)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	local animationConfig = self:GetAnimationConfig("FlameDash")
	local track = self:PlayAnimation(targetPlayer, "FlameDash", "FlameDash", {
		DeferPlay = true,
	})
	self:StartFlameDashVfx(targetPlayer, _payload or {}, track)

	if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		local fadeTime = math.max(0, tonumber(animationConfig and animationConfig.FadeTime) or DEFAULT_FADE_TIME)
		local playbackSpeed = tonumber(animationConfig and animationConfig.PlaybackSpeed) or 1
		track:Play(fadeTime, 1, playbackSpeed)
	end

	return true
end

function MeraPresentationClient:PlayFlameDashComplete(targetPlayer, payload)
	local finalPosition = type(payload) == "table" and (payload.ActualEndPosition or payload.EndPosition) or nil
	local finalDirection = type(payload) == "table" and payload.Direction or nil
	local reason = type(payload) == "table" and payload.ResolveReason or "server_resolve"
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

function MeraPresentationClient:PlayFireBurstRelease(targetPlayer, payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	local duration = math.max(0, tonumber(type(payload) == "table" and payload.Duration) or 0)
	local radius = math.max(0, tonumber(type(payload) == "table" and payload.Radius) or 0)
	logMove("move=FlameBurst startup player=%s", targetPlayer.Name)
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

	self:StopFlameDashVfx(player)
end

function MeraPresentationClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer and leavingPlayer:IsA("Player") then
		self:HandleCharacterRemoving(leavingPlayer)
	end
end

return MeraPresentationClient
