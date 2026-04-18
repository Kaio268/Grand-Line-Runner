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
local SOURCE_LABEL = "ServerScriptService.Modules.DevilFruits.MeraAnimationController"

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

local function playAnimation(character, moveName, animationConfig, defaultAssetName, defaultAnimationKey)
	local resolvedConfig = type(animationConfig) == "table" and animationConfig or {}
	local legacyAssetName = resolvedConfig.AssetName or defaultAssetName
	local animationKey = resolvedConfig.AnimationKey or defaultAnimationKey
	local failureKey = buildAnimationFailureKey(moveName, animationKey or legacyAssetName, defaultAnimationKey or defaultAssetName)
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
		local animationPath = MeraAnimationResolver.BuildAnimationPath(animationKey or legacyAssetName)
		logWarn("animation missing or failed to load move=%s path=%s detail=animator_missing", tostring(moveName), tostring(animationPath))
		logAnimPipeline("WARN", "server animator missing fruit=%s move=%s path=%s", "Mera Mera no Mi", tostring(moveName), tostring(animationPath))
		return nil
	end
	logAnimPipeline("INFO", "server animator ready fruit=%s move=%s asset=%s", "Mera Mera no Mi", tostring(moveName), tostring(animationKey or legacyAssetName))

	local animationCandidates, candidateNames = MeraAnimationResolver.CollectAnimationCandidates(moveName, legacyAssetName, defaultAssetName, animationKey)
	if #animationCandidates == 0 then
		logWarn(
			"animation candidate catalog empty move=%s path=%s names=%s detail=no_animation_candidates",
			tostring(moveName),
			tostring(MeraAnimationResolver.BuildAnimationPath((candidateNames and candidateNames[1]) or legacyAssetName or animationKey)),
			table.concat(candidateNames or {}, "|")
		)
	end
	local selectedTrack
	local selectedCandidate
	local lastFailure = "missing_animation"
	local rejectedPermissionCandidate
	local rejectedLoadCandidate

	for _, candidate in ipairs(animationCandidates) do
		local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
			animator,
			candidate.Animation,
			SOURCE_LABEL
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
			or MeraAnimationResolver.BuildAnimationPath((candidateNames and candidateNames[1]) or legacyAssetName or animationKey)
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
	AnimationLoadDiagnostics.LogTrackPlay(
		selectedTrack,
		SOURCE_LABEL,
		string.format("Mera.%s", tostring(moveName)),
		selectedCandidate and selectedCandidate.AnimationId,
		string.format(
			"key=%s path=%s source=%s fade=%.3f speed=%.3f looped=%s",
			tostring(animationKey or "<legacy>"),
			tostring(selectedCandidate and selectedCandidate.Path),
			tostring(selectedCandidate and selectedCandidate.Source),
			fadeTime,
			playbackSpeed,
			tostring(selectedTrack.Looped)
		)
	)
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
		AssetName = legacyAssetName,
		AnimationKey = animationKey,
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
		return false, fallbackTime > 0 and "fallback" or "immediate"
	end

	if animationState.SupportsReleaseMarker == false then
		if fallbackTime > 0 then
			task.wait(fallbackTime)
		end
		return false, fallbackTime > 0 and "fallback" or "immediate"
	end

	if typeof(markerName) ~= "string" or markerName == "" then
		if fallbackTime > 0 then
			task.wait(fallbackTime)
		end
		return false, fallbackTime > 0 and "fallback" or "immediate"
	end

	local markerReached = false
	local releaseSource = fallbackTime > 0 and "fallback" or "track_stop"
	local resolved = false
	local connection
	local stoppedConnection
	local releaseSignal = Instance.new("BindableEvent")
	local function complete(source, reachedMarker)
		if resolved then
			return
		end

		resolved = true
		markerReached = reachedMarker == true
		releaseSource = source
		releaseSignal:Fire()
	end
	local ok, err = pcall(function()
		connection = animationState.Track:GetMarkerReachedSignal(markerName):Connect(function()
			complete("marker", true)
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
		releaseSignal:Destroy()
		return false, fallbackTime > 0 and "fallback" or "immediate"
	end

	stoppedConnection = animationState.Track.Stopped:Connect(function()
		if fallbackTime <= 0 then
			complete("track_stop", false)
		end
	end)

	if fallbackTime > 0 then
		task.delay(fallbackTime, function()
			complete("fallback", false)
		end)
	elseif not animationState.Track.IsPlaying then
		complete("track_stop", false)
	end

	if not resolved then
		releaseSignal.Event:Wait()
	end

	releaseSignal:Destroy()
	if connection then
		connection:Disconnect()
	end
	if stoppedConnection then
		stoppedConnection:Disconnect()
	end

	if not markerReached and releaseSource == "fallback" then
		logWarn(
			"animation missing or failed to load move=%s path=%s detail=marker_timeout:%s",
			tostring(moveName),
			tostring(animationState.AnimationPath),
			tostring(markerName)
		)
	end

	return markerReached, releaseSource
end

function MeraAnimationController.PlayFlameDashAnimation(character, animationConfig)
	return playAnimation(character, "FlameDash", animationConfig, "Flame Dash", "Mera.FlameDash")
end

function MeraAnimationController.PlayFireBurstAnimation(character, animationConfig)
	return playAnimation(character, "FireBurst", animationConfig, "Flame burst", "Mera.FlameBurstR6")
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
