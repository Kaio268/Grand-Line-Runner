local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))

local GomuAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("GomuAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[GOMU ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("GomuAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[GOMU ANIM][WARN] " .. message, ...))
end

local function getAnimationFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local animationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	return animationsFolder and animationsFolder:FindFirstChild("Gomu") or nil
end

local function getAnimationAsset(moveName, assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		logWarn("animation missing or failed to load move=%s detail=invalid_asset_name", tostring(moveName))
		return nil
	end

	local gomuFolder = getAnimationFolder()
	if not gomuFolder then
		logWarn("animation missing or failed to load move=%s path=ReplicatedStorage/Assets/Animations/Gomu detail=missing_folder", tostring(moveName))
		return nil
	end

	local animation = gomuFolder:FindFirstChild(assetName)
	if animation and animation:IsA("Animation") then
		return animation
	end

	logWarn(
		"animation missing or failed to load move=%s path=ReplicatedStorage/Assets/Animations/Gomu/%s detail=missing_animation",
		tostring(moveName),
		tostring(assetName)
	)
	return nil
end

local function getAnimator(character)
	if typeof(character) ~= "Instance" then
		logWarn("animation missing or failed to load move=<unknown> detail=character_nil")
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		logWarn("animation missing or failed to load move=<unknown> detail=humanoid_missing character=%s", character.Name)
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

	logWarn("animation missing or failed to load move=<unknown> detail=animator_missing character=%s", character.Name)
	return nil
end

local function playAnimation(character, moveName, animationConfig, defaultAssetName)
	local resolvedConfig = type(animationConfig) == "table" and animationConfig or {}
	local assetName = resolvedConfig.AssetName or defaultAssetName
	local animation = getAnimationAsset(moveName, assetName)
	if not animation then
		return nil
	end

	local animator = getAnimator(character)
	if not animator then
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		"ServerScriptService.Modules.DevilFruits.Gomu.Server.GomuAnimationController"
	)
	if not track then
		logWarn(
			"animation missing or failed to load move=%s detail=%s",
			tostring(moveName),
			tostring(loadFailure)
		)
		return nil
	end

	local fadeTime = math.max(0, tonumber(resolvedConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(resolvedConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = resolvedConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)

	logInfo("move=%s animation play asset=%s", tostring(moveName), tostring(assetName))

	return {
		MoveName = moveName,
		AssetName = assetName,
		Track = track,
		StopFadeTime = math.max(0, tonumber(resolvedConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function GomuAnimationController.PlayRubberLaunchAnimation(character, animationConfig)
	return playAnimation(character, "RubberLaunch", animationConfig, "Rocket")
end

function GomuAnimationController.StopAnimation(animationState, reason)
	if type(animationState) ~= "table" or typeof(animationState.Track) ~= "Instance" then
		return false
	end

	pcall(function()
		animationState.Track:Stop(animationState.StopFadeTime)
	end)
	logInfo("move=%s animation stop reason=%s", tostring(animationState.MoveName), tostring(reason))
	return true
end

return GomuAnimationController
