local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))

local MeraAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MeraAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MERA ANIM][WARN] " .. message, ...))
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

local function buildAnimationPath(assetName)
	return string.format("ReplicatedStorage/Assets/Animations/Mera/%s", tostring(assetName or ""))
end

local function getAnimationAsset(moveName, assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		logWarn("animation missing or failed to load move=%s detail=invalid_asset_name", tostring(moveName))
		return nil, nil
	end

	local meraFolder = getAnimationFolder()
	local animationPath = buildAnimationPath(assetName)
	if not meraFolder then
		logWarn("animation missing or failed to load move=%s path=ReplicatedStorage/Assets/Animations/Mera detail=missing_folder", tostring(moveName))
		return nil, animationPath
	end

	local animation = meraFolder:FindFirstChild(assetName)
	if animation and animation:IsA("Animation") then
		logInfo("move=%s animation selected=%s", tostring(moveName), animationPath)
		return animation, animationPath
	end

	logWarn("animation missing or failed to load move=%s path=%s detail=missing_animation", tostring(moveName), animationPath)
	return nil, animationPath
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

local function stopTrack(track, fadeTime)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return
	end

	pcall(function()
		track:Stop(math.max(0, tonumber(fadeTime) or DEFAULT_STOP_FADE_TIME))
	end)
end

local function playAnimation(character, moveName, animationConfig, defaultAssetName)
	local resolvedConfig = type(animationConfig) == "table" and animationConfig or {}
	local assetName = resolvedConfig.AssetName or defaultAssetName
	local animation, animationPath = getAnimationAsset(moveName, assetName)
	if not animation then
		return nil
	end

	local animator = getAnimator(character)
	if not animator then
		logWarn("animation missing or failed to load move=%s path=%s detail=animator_missing", tostring(moveName), tostring(animationPath))
		return nil
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		"ServerScriptService.Modules.DevilFruits.MeraAnimationController"
	)
	if not track then
		logWarn(
			"animation missing or failed to load move=%s path=%s detail=%s",
			tostring(moveName),
			tostring(animationPath),
			tostring(loadFailure)
		)
		return nil
	end

	local fadeTime = math.max(0, tonumber(resolvedConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(resolvedConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = resolvedConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)

	return {
		MoveName = moveName,
		AssetName = assetName,
		AnimationPath = animationPath,
		Track = track,
		MarkerName = resolvedConfig.ReleaseMarker,
		ReleaseFallbackTime = math.max(0, tonumber(resolvedConfig.ReleaseFallbackTime) or 0),
		StopFadeTime = math.max(0, tonumber(resolvedConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

local function waitForRelease(moveName, animationState, animationConfig)
	local resolvedConfig = type(animationConfig) == "table" and animationConfig or {}
	local fallbackTime = math.max(
		0,
		tonumber((type(animationState) == "table" and animationState.ReleaseFallbackTime) or resolvedConfig.ReleaseFallbackTime) or 0
	)
	local markerName = type(animationState) == "table" and animationState.MarkerName or resolvedConfig.ReleaseMarker

	if type(animationState) ~= "table" or typeof(animationState.Track) ~= "Instance" then
		if fallbackTime > 0 then
			task.wait(fallbackTime)
		end
		return false
	end

	if typeof(markerName) ~= "string" or markerName == "" then
		if fallbackTime > 0 then
			task.wait(fallbackTime)
		end
		return false
	end

	local markerReached = false
	local connection
	local ok, err = pcall(function()
		connection = animationState.Track:GetMarkerReachedSignal(markerName):Connect(function()
			markerReached = true
		end)
	end)
	if not ok then
		logWarn(
			"animation missing or failed to load move=%s path=%s detail=marker_connect_failed:%s",
			tostring(moveName),
			tostring(animationState.AnimationPath),
			tostring(err)
		)
		if fallbackTime > 0 then
			task.wait(fallbackTime)
		end
		return false
	end

	local timeoutAt = os.clock() + math.max(fallbackTime, 0.01)
	while not markerReached and animationState.Track.IsPlaying and os.clock() < timeoutAt do
		task.wait()
	end

	if connection then
		connection:Disconnect()
	end

	if not markerReached and fallbackTime > 0 then
		logWarn(
			"animation missing or failed to load move=%s path=%s detail=marker_timeout:%s",
			tostring(moveName),
			tostring(animationState.AnimationPath),
			tostring(markerName)
		)
	end

	return markerReached
end

function MeraAnimationController.PlayFlameDashAnimation(character, animationConfig)
	return playAnimation(character, "FlameDash", animationConfig, "FlameDash")
end

function MeraAnimationController.PlayFireBurstAnimation(character, animationConfig)
	return playAnimation(character, "FireBurst", animationConfig, "FlameBurst")
end

function MeraAnimationController.WaitForFireBurstRelease(animationState, animationConfig)
	return waitForRelease("FireBurst", animationState, animationConfig)
end

function MeraAnimationController.StopAnimation(animationState, reason)
	if type(animationState) ~= "table" then
		return false
	end

	stopTrack(animationState.Track, animationState.StopFadeTime)
	logInfo("move=%s animation stop reason=%s", tostring(animationState.MoveName), tostring(reason))
	return true
end

return MeraAnimationController
