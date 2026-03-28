local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))

local HieAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local DEFAULT_FADE_TIME = 0.08
local DEFAULT_STOP_FADE_TIME = 0.1
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 3

local activeIceBoostStates = setmetatable({}, { __mode = "k" })

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

local function getHieAnimationFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local animationsFolder = assetsFolder and assetsFolder:FindFirstChild("Animations")
	return animationsFolder and animationsFolder:FindFirstChild("Hie") or nil
end

local function getAnimationAsset(assetName)
	if typeof(assetName) ~= "string" or assetName == "" then
		return nil
	end

	local hieFolder = getHieAnimationFolder()
	if not hieFolder then
		logWarn("animation folder missing path=ReplicatedStorage/Assets/Animations/Hie")
		return nil
	end

	local animation = hieFolder:FindFirstChild(assetName)
	if animation and animation:IsA("Animation") then
		return animation
	end

	logWarn("animation asset missing path=ReplicatedStorage/Assets/Animations/Hie/%s", assetName)
	return nil
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

local function playAnimation(character, animationConfig, defaultAssetName)
	local resolvedConfig = type(animationConfig) == "table" and animationConfig or {}
	local assetName = resolvedConfig.AssetName or defaultAssetName
	local animation = getAnimationAsset(assetName)
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
		"ServerScriptService.Modules.DevilFruits.HieAnimationController"
	)
	if not track then
		logWarn("%s animation failed to load detail=%s", tostring(assetName), tostring(loadFailure))
		return nil
	end

	logInfo("%s animation loaded", assetName)

	local fadeTime = math.max(0, tonumber(resolvedConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(resolvedConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = resolvedConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)
	logInfo("%s play", assetName)

	return {
		AssetName = assetName,
		Track = track,
		MarkerName = resolvedConfig.ReleaseMarker,
		ReleaseFallbackTime = math.max(0, tonumber(resolvedConfig.ReleaseFallbackTime) or 0),
		StopFadeTime = math.max(0, tonumber(resolvedConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function HieAnimationController.PlayFreezeShotAnimation(character, animationConfig)
	return playAnimation(character, animationConfig, "IceBlast")
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

	local animationState = playAnimation(character, animationConfig, "IceBoost")
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
