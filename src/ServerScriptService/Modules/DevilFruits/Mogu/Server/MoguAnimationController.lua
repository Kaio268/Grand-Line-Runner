local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AnimationLoadDiagnostics = require(Modules:WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local CommonAnimation = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("CommonAnimation"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local AnimationResolver = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AnimationResolver"))

local MoguAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 4
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local SOURCE_LABEL = "ServerScriptService.Modules.DevilFruits.Mogu.Server.MoguAnimationController"
local STAGE_START = "Start"
local STAGE_RESOLVE = "Resolve"
local DEFAULT_ANIMATION_KEY_BY_STAGE = {
	[STAGE_START] = "Mogu.MoleDigStart",
	[STAGE_RESOLVE] = "Mogu.MoleDigEnd",
}

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU ANIM][WARN] " .. message, ...))
end

local function getStageAnimationConfig(stageKey, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and animationConfig[stageKey] or {}
end

local function resolveAnimationAsset(stageKey, stageConfig)
	local animationKey = type(stageConfig) == "table" and stageConfig.AnimationKey or nil
	animationKey = animationKey or DEFAULT_ANIMATION_KEY_BY_STAGE[stageKey]
	if typeof(animationKey) ~= "string" or animationKey == "" then
		logWarn("missing animation key stage=%s", tostring(stageKey))
		return nil, nil, nil
	end

	local animation, descriptor = AnimationResolver.GetAnimation(animationKey, {
		Context = string.format("Mogu.%s", tostring(stageKey)),
	})
	if animation then
		logInfo("resolved stage=%s key=%s id=%s", tostring(stageKey), tostring(animationKey), tostring(descriptor and descriptor.AnimationId))
		return animation, descriptor, animationKey
	end

	logWarn("missing animation stage=%s key=%s", tostring(stageKey), tostring(animationKey))
	return nil, descriptor, animationKey
end

local function getStageStopAfter(stageConfig)
	local stopAfter = tonumber(stageConfig.StopAfter)
		or tonumber(stageConfig.ReturnToMovementAfter)
		or tonumber(stageConfig.CutShortAfter)
		or tonumber(stageConfig.MaxDuration)
	if not stopAfter or stopAfter <= 0 then
		return nil
	end

	return stopAfter
end

local function scheduleStopAfter(track, stopAfter, stopFadeTime, stageKey)
	if not track or not stopAfter then
		return
	end

	task.delay(stopAfter, function()
		if track.IsPlaying then
			CommonAnimation.StopTrack(track, stopFadeTime)
			logInfo("auto stop stage=%s after=%.3f", tostring(stageKey), stopAfter)
		end
	end)
end

local function playAnimation(character, stageKey, abilityConfig)
	local stageConfig = getStageAnimationConfig(stageKey, abilityConfig)
	local animation, descriptor, animationKey = resolveAnimationAsset(stageKey, stageConfig)
	if not animation then
		return nil
	end

	local animator = CommonAnimation.GetAnimatorFromCharacter(character, 0.25)
	if not animator then
		logWarn("animator missing stage=%s character=%s", tostring(stageKey), tostring(character and character.Name))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		SOURCE_LABEL
	)
	if not track then
		logWarn("animation failed stage=%s detail=%s", tostring(stageKey), tostring(loadFailure))
		return nil
	end

	local fadeTime = math.max(0, tonumber(stageConfig.FadeTime) or DEFAULT_FADE_TIME)
	local stopFadeTime = math.max(0, tonumber(stageConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME)
	local stopAfter = getStageStopAfter(stageConfig)
	local playbackSpeed = tonumber(stageConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = stageConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)
	scheduleStopAfter(track, stopAfter, stopFadeTime, stageKey)
	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		string.format("Mogu.%s", tostring(stageKey)),
		descriptor and descriptor.AnimationId,
		string.format(
			"key=%s fade=%.3f speed=%.3f looped=%s",
			tostring(animationKey),
			fadeTime,
			playbackSpeed,
			tostring(track.Looped)
		)
	)

	logInfo("play stage=%s asset=%s", tostring(stageKey), tostring(descriptor and descriptor.Path or animationKey))

	return {
		Stage = stageKey,
		AnimationKey = animationKey,
		AnimationId = descriptor and descriptor.AnimationId,
		Track = track,
		StopFadeTime = stopFadeTime,
		StopAfter = stopAfter,
	}
end

function MoguAnimationController.PlayBurrowStartAnimation(character, abilityConfig)
	return playAnimation(character, STAGE_START, abilityConfig)
end

function MoguAnimationController.PlayBurrowResolveAnimation(character, abilityConfig)
	return playAnimation(character, STAGE_RESOLVE, abilityConfig)
end

function MoguAnimationController.StopAnimation(animationState, reason)
	if type(animationState) ~= "table" then
		return false
	end

	CommonAnimation.StopTrack(animationState.Track, animationState.StopFadeTime)
	logInfo("stop stage=%s reason=%s", tostring(animationState.Stage), tostring(reason))
	return true
end

return MoguAnimationController
