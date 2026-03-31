local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local DevilFruitLogger = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local MeraAnimationResolver = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Mera"):WaitForChild("Shared"):WaitForChild("MeraAnimationResolver")
)

local MeraAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3
local ANIMATION_FAILURE_RETRY_COOLDOWN = 10

local animationFailureStateByKey = {}

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
	local failureKey = buildAnimationFailureKey(moveName, assetName, defaultAssetName)
	local cachedFailure = getCachedAnimationFailure(failureKey)
	if cachedFailure then
		logInfo(
			"move=%s animation load skipped path=%s detail=cached_failure:%s",
			tostring(moveName),
			tostring(cachedFailure.Path),
			tostring(cachedFailure.Detail)
		)
		return nil
	end

	local animator = getAnimator(character)
	if not animator then
		local animationPath = MeraAnimationResolver.BuildAnimationPath(assetName)
		logWarn("animation missing or failed to load move=%s path=%s detail=animator_missing", tostring(moveName), tostring(animationPath))
		logAnimPipeline("WARN", "server animator missing fruit=%s move=%s path=%s", "Mera Mera no Mi", tostring(moveName), tostring(animationPath))
		return nil
	end
	logAnimPipeline("INFO", "server animator ready fruit=%s move=%s asset=%s", "Mera Mera no Mi", tostring(moveName), tostring(assetName))

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
			"ServerScriptService.Modules.DevilFruits.MeraAnimationController"
		)
		if track then
			selectedTrack = track
			selectedCandidate = candidate
			break
		end

		lastFailure = loadFailure or lastFailure
		if AnimationLoadDiagnostics.IsPermissionFailure(loadFailure) then
			rejectedPermissionCandidate = rejectedPermissionCandidate or candidate
			logWarn(
				"animation candidate rejected move=%s path=%s id=%s source=%s detail=%s",
				tostring(moveName),
				tostring(candidate.Path),
				tostring(candidate.AnimationId),
				tostring(candidate.Source),
				tostring(loadFailure)
			)
		else
			rejectedLoadCandidate = rejectedLoadCandidate or candidate
			logInfo(
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
		local animationPath = rejectedCandidate and rejectedCandidate.Path
			or MeraAnimationResolver.BuildAnimationPath((candidateNames and candidateNames[1]) or assetName)
		local detail = lastFailure
		if rejectedPermissionCandidate then
			detail = string.format("permission_denied:%s", tostring(rejectedPermissionCandidate.AnimationId))
		end

		logWarn(
			"animation missing or failed to load move=%s path=%s detail=%s",
			tostring(moveName),
			tostring(animationPath),
			tostring(detail)
		)
		logAnimPipeline("WARN", "server animation load failed fruit=%s move=%s path=%s detail=%s", "Mera Mera no Mi", tostring(moveName), tostring(animationPath), tostring(detail))
		rememberAnimationFailure(failureKey, animationPath, detail)
		return nil
	end
	logAnimPipeline(
		"INFO",
		"server animation track created fruit=%s move=%s path=%s id=%s source=%s",
		"Mera Mera no Mi",
		tostring(moveName),
		tostring(selectedCandidate and selectedCandidate.Path),
		tostring(selectedCandidate and selectedCandidate.AnimationId),
		tostring(selectedCandidate and selectedCandidate.Source)
	)

	local fadeTime = math.max(0, tonumber(resolvedConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(resolvedConfig.PlaybackSpeed) or 1
	selectedTrack.Priority = Enum.AnimationPriority.Action
	selectedTrack.Looped = resolvedConfig.Looped == true
	local playOk, playError = pcall(function()
		selectedTrack:Play(fadeTime, 1, playbackSpeed)
	end)
	if not playOk then
		stopTrack(selectedTrack, resolvedConfig.StopFadeTime)
		logWarn(
			"animation missing or failed to load move=%s path=%s detail=play_failed:%s",
			tostring(moveName),
			tostring(selectedCandidate and selectedCandidate.Path),
			tostring(playError)
		)
		logAnimPipeline(
			"WARN",
			"server animation load failed fruit=%s move=%s path=%s detail=%s",
			"Mera Mera no Mi",
			tostring(moveName),
			tostring(selectedCandidate and selectedCandidate.Path),
			string.format("play_failed:%s", tostring(playError))
		)
		rememberAnimationFailure(
			failureKey,
			selectedCandidate and selectedCandidate.Path,
			string.format("play_failed:%s", tostring(playError))
		)
		return nil
	end
	logAnimPipeline("INFO", "server animation play reached fruit=%s move=%s path=%s", "Mera Mera no Mi", tostring(moveName), tostring(selectedCandidate and selectedCandidate.Path))
	logInfo(
		"move=%s animation selected path=%s id=%s source=%s",
		tostring(moveName),
		tostring(selectedCandidate and selectedCandidate.Path),
		tostring(selectedCandidate and selectedCandidate.AnimationId),
		tostring(selectedCandidate and selectedCandidate.Source)
	)
	clearAnimationFailure(failureKey)

	return {
		MoveName = moveName,
		AssetName = assetName,
		AnimationPath = selectedCandidate and selectedCandidate.Path,
		AnimationId = selectedCandidate and selectedCandidate.AnimationId,
		AnimationSource = selectedCandidate and selectedCandidate.Source,
		Track = selectedTrack,
		SupportsReleaseMarker = selectedCandidate == nil or selectedCandidate.SupportsReleaseMarker ~= false,
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

	if animationState.SupportsReleaseMarker == false then
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
	return playAnimation(character, "FlameDash", animationConfig, "Flame Dash")
end

function MeraAnimationController.PlayFireBurstAnimation(character, animationConfig)
	return playAnimation(character, "FireBurst", animationConfig, "Flame burst")
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
