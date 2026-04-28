local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruits = Modules:WaitForChild("DevilFruits")
local AnimationLoadDiagnostics = require(DevilFruits:WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(DevilFruits:WaitForChild("DiagnosticLogLimiter"))
local AnimationResolver = require(DevilFruits:WaitForChild("Shared"):WaitForChild("AnimationResolver"))

local HoroAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 4
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.12
local DEFAULT_PROJECTED_IDLE_DELAY = 1
local SOURCE_LABEL = "ServerScriptService.Modules.DevilFruits.Horo.Server.HoroAnimationController"
local STAGE_PROJECTION = "Projection"
local STAGE_PROJECTED = "Projected"
local DEFAULT_ANIMATION_KEY_BY_STAGE = {
	[STAGE_PROJECTION] = "Horo.HoroProjection",
	[STAGE_PROJECTED] = "Horo.HoroProjected",
}
local DEFAULT_LOOPED_BY_STAGE = {
	[STAGE_PROJECTION] = false,
	[STAGE_PROJECTED] = true,
}
local DEFAULT_PRIORITY_BY_STAGE = {
	[STAGE_PROJECTION] = Enum.AnimationPriority.Action,
	[STAGE_PROJECTED] = Enum.AnimationPriority.Action,
}

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("HoroAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[HORO ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("HoroAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[HORO ANIM][WARN] " .. message, ...))
end

local function getStageAnimationConfig(stageKey, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	if type(animationConfig) == "table" and type(animationConfig[stageKey]) == "table" then
		return animationConfig[stageKey]
	end

	return {}
end

local function getAnimator(character, humanoid)
	if typeof(character) ~= "Instance" or typeof(humanoid) ~= "Instance" then
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

	logWarn("animator missing stage=<unknown> character=%s", tostring(character.Name))
	return nil
end

local function resolvePriority(priority, fallback)
	return if typeof(priority) == "EnumItem" then priority else fallback
end

local function resolveAnimation(stageKey, player, character, humanoid, stageConfig)
	local animationKey = stageConfig.AnimationKey or DEFAULT_ANIMATION_KEY_BY_STAGE[stageKey]
	if typeof(animationKey) ~= "string" or animationKey == "" then
		logWarn("missing animation key stage=%s", tostring(stageKey))
		return nil, nil, nil
	end

	local animation, descriptor = AnimationResolver.GetRigAwareAnimation(animationKey, player, character, humanoid, {
		Context = string.format("Horo.%s", tostring(stageKey)),
		FallbackVariant = "Default",
	})
	if animation then
		return animation, descriptor, animationKey
	end

	logWarn("missing animation stage=%s key=%s", tostring(stageKey), tostring(animationKey))
	return nil, descriptor, animationKey
end

local function playBodyAnimation(player, character, humanoid, abilityConfig, stageKey)
	local stageConfig = getStageAnimationConfig(stageKey, abilityConfig)
	local animation, descriptor, animationKey = resolveAnimation(stageKey, player, character, humanoid, stageConfig)
	if not animation then
		return nil
	end

	local animator = getAnimator(character, humanoid)
	if not animator then
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(animator, animation, SOURCE_LABEL)
	if not track then
		logWarn("animation failed stage=%s key=%s detail=%s", tostring(stageKey), tostring(animationKey), tostring(loadFailure))
		return nil
	end

	local fadeTime = math.max(0, tonumber(stageConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = math.max(0.01, tonumber(stageConfig.PlaybackSpeed) or 1)
	track.Priority = resolvePriority(stageConfig.Priority, DEFAULT_PRIORITY_BY_STAGE[stageKey])
	track.Looped = if typeof(stageConfig.Looped) == "boolean" then stageConfig.Looped else DEFAULT_LOOPED_BY_STAGE[stageKey]
	track:Play(fadeTime, 1, playbackSpeed)
	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		string.format("Horo.%s", tostring(stageKey)),
		descriptor and descriptor.AnimationId,
		string.format(
			"key=%s fade=%.3f speed=%.3f looped=%s",
			tostring(animationKey),
			fadeTime,
			playbackSpeed,
			tostring(track.Looped)
		)
	)
	logInfo("play stage=%s key=%s", tostring(stageKey), tostring(animationKey))

	return {
		Stage = stageKey,
		AnimationKey = animationKey,
		AnimationId = descriptor and descriptor.AnimationId,
		Track = track,
		StopFadeTime = math.max(0, tonumber(stageConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function HoroAnimationController.PlayProjectionAnimation(player, character, humanoid, abilityConfig)
	return playBodyAnimation(player, character, humanoid, abilityConfig, STAGE_PROJECTION)
end

function HoroAnimationController.PlayProjectedIdleAnimation(player, character, humanoid, abilityConfig)
	return playBodyAnimation(player, character, humanoid, abilityConfig, STAGE_PROJECTED)
end

function HoroAnimationController.GetProjectedIdleDelay(abilityConfig, projectionAnimationState)
	local projectionTrack = type(projectionAnimationState) == "table" and projectionAnimationState.Track or nil
	local trackLength = nil
	if typeof(projectionTrack) == "Instance" and projectionTrack:IsA("AnimationTrack") then
		trackLength = tonumber(projectionTrack.Length)
	end
	if trackLength and trackLength > 0 then
		return trackLength
	end

	local projectionConfig = getStageAnimationConfig(STAGE_PROJECTION, abilityConfig)
	return math.max(0, tonumber(projectionConfig.ProjectedIdleDelay) or DEFAULT_PROJECTED_IDLE_DELAY)
end

function HoroAnimationController.StopAnimation(animationState, reason)
	if type(animationState) ~= "table" or typeof(animationState.Track) ~= "Instance" then
		return false
	end

	pcall(function()
		animationState.Track:Stop(animationState.StopFadeTime)
	end)
	logInfo("stop stage=%s reason=%s", tostring(animationState.Stage), tostring(reason))
	return true
end

return HoroAnimationController
