local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local AnimationLoadDiagnostics = require(Modules:WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local CommonAnimation = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("CommonAnimation"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local AnimationResolver = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AnimationResolver"))

local MoguAnimationController = {}
MoguAnimationController.__index = MoguAnimationController

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 4
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local SOURCE_LABEL = "ReplicatedStorage.Modules.DevilFruits.Mogu.Client.MoguAnimationController"
local STAGE_START = "Start"
local STAGE_RESOLVE = "Resolve"
local DEFAULT_ANIMATION_KEY_BY_STAGE = {
	[STAGE_START] = "Mogu.Dive",
	[STAGE_RESOLVE] = "Mogu.Exit",
}

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguClientAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU CLIENT ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguClientAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU CLIENT ANIM][WARN] " .. message, ...))
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
		Context = string.format("Mogu.Client.%s", tostring(stageKey)),
	})
	if animation then
		logInfo("resolved stage=%s key=%s id=%s", tostring(stageKey), tostring(animationKey), tostring(descriptor and descriptor.AnimationId))
		return animation, descriptor, animationKey
	end

	logWarn("missing animation stage=%s key=%s", tostring(stageKey), tostring(animationKey))
	return nil, descriptor, animationKey
end

local function playAnimationForPlayer(targetPlayer, stageKey, abilityConfig)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local stageConfig = getStageAnimationConfig(stageKey, abilityConfig)
	local animation, descriptor, animationKey = resolveAnimationAsset(stageKey, stageConfig)
	if not animation then
		return nil
	end

	local character = targetPlayer.Character
	local animator = CommonAnimation.GetAnimatorFromCharacter(character, 0.25)
	if not animator then
		logWarn("animator missing stage=%s player=%s", tostring(stageKey), tostring(targetPlayer.Name))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		SOURCE_LABEL
	)
	if not track then
		logWarn("animation failed stage=%s player=%s detail=%s", tostring(stageKey), tostring(targetPlayer.Name), tostring(loadFailure))
		return nil
	end

	local fadeTime = math.max(0, tonumber(stageConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(stageConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = stageConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)
	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		string.format("Mogu.Client.%s", tostring(stageKey)),
		descriptor and descriptor.AnimationId,
		string.format(
			"key=%s fade=%.3f speed=%.3f looped=%s",
			tostring(animationKey),
			fadeTime,
			playbackSpeed,
			tostring(track.Looped)
		)
	)

	return {
		Stage = stageKey,
		AnimationKey = animationKey,
		AnimationId = descriptor and descriptor.AnimationId,
		Track = track,
		StopFadeTime = math.max(0, tonumber(stageConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function MoguAnimationController.new()
	return setmetatable({}, MoguAnimationController)
end

function MoguAnimationController:PlayStart(targetPlayer, abilityConfig)
	return playAnimationForPlayer(targetPlayer, STAGE_START, abilityConfig)
end

function MoguAnimationController:PlayResolve(targetPlayer, abilityConfig)
	return playAnimationForPlayer(targetPlayer, STAGE_RESOLVE, abilityConfig)
end

function MoguAnimationController:StopAnimation(animationState, reason)
	if type(animationState) ~= "table" then
		return false
	end

	CommonAnimation.StopTrack(animationState.Track, animationState.StopFadeTime)
	logInfo("stop stage=%s reason=%s", tostring(animationState.Stage), tostring(reason))
	return true
end

return MoguAnimationController
