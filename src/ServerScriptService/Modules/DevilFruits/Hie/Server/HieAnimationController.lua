local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local DevilFruitLogger = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local AnimationResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AnimationResolver"))

local HieAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local DEFAULT_FADE_TIME = 0.08
local DEFAULT_STOP_FADE_TIME = 0.1
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 3

local activeIceBoostStates = setmetatable({}, { __mode = "k" })
local SOURCE_LABEL = "ServerScriptService.Modules.DevilFruits.HieAnimationController"

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("HieAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[HIE ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("HieAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[HIE ANIM][WARN] " .. message, ...))
end

local function logAnimPipeline(level, message, ...)
	if not DEBUG_INFO and level ~= "WARN" then
		return
	end

	if level == "WARN" then
		DevilFruitLogger.Warn("ANIM", message, ...)
		return
	end

	DevilFruitLogger.Info("ANIM", message, ...)
end

local function getAnimationAsset(animationKey, character, moveName)
	if typeof(animationKey) ~= "string" or animationKey == "" then
		logWarn("animation key missing move=%s", tostring(moveName))
		return nil, nil
	end

	local humanoid = typeof(character) == "Instance" and character:FindFirstChildOfClass("Humanoid") or nil
	local animation, descriptor = AnimationResolver.GetRigAwareAnimation(animationKey, nil, character, humanoid, {
		Context = string.format("Hie.%s", tostring(moveName or animationKey)),
		FallbackVariant = "Default",
		R6GAsDefault = true,
	})
	if animation then
		return animation, descriptor
	end

	logWarn(
		"animation asset missing key=%s variant=%s detail=%s",
		tostring(animationKey),
		tostring(descriptor and descriptor.Variant or "<nil>"),
		tostring(descriptor and descriptor.Source or "missing_registry_animation")
	)
	return nil, descriptor
end

local function getAnimator(character)
	if typeof(character) ~= "Instance" then
		logWarn("animator missing character=nil")
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		logWarn("animator missing character=%s humanoid=nil", character.Name)
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

	logWarn("animator missing character=%s humanoid=%s", character.Name, humanoid.Name)
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

local function playAnimation(character, animationConfig, defaultAnimationKey, moveName)
	local resolvedConfig = type(animationConfig) == "table" and animationConfig or {}
	local animationKey = resolvedConfig.AnimationKey or defaultAnimationKey
	local resolvedMoveName = moveName or defaultAnimationKey
	local animation, descriptor = getAnimationAsset(animationKey, character, resolvedMoveName)
	if not animation then
		return nil
	end

	local animator = getAnimator(character)
	if not animator then
		logAnimPipeline("WARN", "server animator missing fruit=%s move=%s asset=%s", "Hie Hie no Mi", tostring(resolvedMoveName), tostring(animationKey))
		return nil
	end
	logAnimPipeline("INFO", "server animator ready fruit=%s move=%s asset=%s", "Hie Hie no Mi", tostring(resolvedMoveName), tostring(animationKey))

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		SOURCE_LABEL
	)
	if not track then
		logWarn("%s animation failed to load detail=%s", tostring(animationKey), tostring(loadFailure))
		logAnimPipeline("WARN", "server animation load failed fruit=%s move=%s asset=%s detail=%s", "Hie Hie no Mi", tostring(resolvedMoveName), tostring(animationKey), tostring(loadFailure))
		return nil
	end

	logInfo("%s animation loaded id=%s variant=%s", tostring(animationKey), tostring(descriptor and descriptor.AnimationId), tostring(descriptor and descriptor.Variant))
	logAnimPipeline("INFO", "server animation track created fruit=%s move=%s asset=%s", "Hie Hie no Mi", tostring(resolvedMoveName), tostring(animationKey))

	local fadeTime = math.max(0, tonumber(resolvedConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(resolvedConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = resolvedConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)
	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		string.format("Hie.%s", tostring(resolvedMoveName)),
		descriptor and descriptor.AnimationId,
		string.format(
			"key=%s variant=%s fade=%.3f speed=%.3f looped=%s",
			tostring(animationKey),
			tostring(descriptor and descriptor.Variant or "<none>"),
			fadeTime,
			playbackSpeed,
			tostring(track.Looped)
		)
	)
	logInfo("%s play", animationKey)
	logAnimPipeline("INFO", "server animation play reached fruit=%s move=%s asset=%s", "Hie Hie no Mi", tostring(resolvedMoveName), tostring(animationKey))

	return {
		AssetName = animationKey,
		AnimationKey = animationKey,
		AnimationId = descriptor and descriptor.AnimationId,
		Variant = descriptor and descriptor.Variant,
		Track = track,
		MarkerName = resolvedConfig.ReleaseMarker,
		ReleaseFallbackTime = math.max(0, tonumber(resolvedConfig.ReleaseFallbackTime) or 0),
		StopFadeTime = math.max(0, tonumber(resolvedConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function HieAnimationController.PlayFreezeShotAnimation(character, animationConfig)
	return playAnimation(character, animationConfig, "Hie.IceBlast", "IceBlast")
end

function HieAnimationController.WaitForFreezeShotRelease(animationState)
	if type(animationState) ~= "table" or typeof(animationState.Track) ~= "Instance" then
		return false
	end

	local markerName = animationState.MarkerName
	if typeof(markerName) ~= "string" or markerName == "" then
		return false
	end

	local markerReached = false
	local connection
	local ok, err = pcall(function()
		connection = animationState.Track:GetMarkerReachedSignal(markerName):Connect(function()
			if markerReached then
				return
			end

			markerReached = true
			logInfo("%s marker reached: %s", tostring(animationState.AssetName), markerName)
		end)
	end)
	if not ok then
		logWarn("%s marker connect failed marker=%s detail=%s", tostring(animationState.AssetName), markerName, tostring(err))
		return false
	end

	local timeoutAt = os.clock() + math.max(0, tonumber(animationState.ReleaseFallbackTime) or 0)
	while not markerReached and animationState.Track.IsPlaying and os.clock() < timeoutAt do
		task.wait()
	end

	if connection then
		connection:Disconnect()
	end

	if not markerReached and timeoutAt > 0 then
		logWarn("%s marker timeout marker=%s fallbackRelease=true", tostring(animationState.AssetName), markerName)
	end

	return markerReached
end

function HieAnimationController.PlayIceBoostAnimation(player, character, animationConfig, token)
	if not player then
		return nil
	end

	HieAnimationController.StopIceBoostAnimation(player, nil, "replace")

	local animationState = playAnimation(character, animationConfig, "Hie.IceBoost", "IceBoost")
	if not animationState then
		return nil
	end

	activeIceBoostStates[player] = {
		Token = token,
		AnimationState = animationState,
	}
	return animationState
end

function HieAnimationController.StopIceBoostAnimation(player, token, reason)
	local activeState = player and activeIceBoostStates[player] or nil
	if not activeState then
		return false
	end

	if token ~= nil and activeState.Token ~= token then
		return false
	end

	activeIceBoostStates[player] = nil
	stopTrack(activeState.AnimationState and activeState.AnimationState.Track, activeState.AnimationState and activeState.AnimationState.StopFadeTime)
	logInfo("%s stop", tostring(activeState.AnimationState and activeState.AnimationState.AssetName or "IceBoost"))
	return true
end

return HieAnimationController
