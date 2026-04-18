local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DiagnosticLogLimiter = require(script.Parent:WaitForChild("DiagnosticLogLimiter"))

local AnimationLoadDiagnostics = {}

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.5
local WARN_COOLDOWN = 3
local PERMISSION_DENIED_COOLDOWN = 300
local LOAD_FAILURE_COOLDOWN = 15

local cachedFailureByAssetKey = {}

local function shouldLogInfo()
	return DEBUG_INFO or ReplicatedStorage:GetAttribute("DebugAnimationRegistry") == true
end

local function logInfo(message, ...)
	if not shouldLogInfo() then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("AnimationLoadDiagnostics:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[ANIM LOAD] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("AnimationLoadDiagnostics:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[ANIM LOAD][WARN] " .. message, ...))
end

local function getAnimationId(animation)
	if typeof(animation) == "Instance" and animation:IsA("Animation") then
		return tostring(animation.AnimationId or "")
	end

	return tostring(animation or "")
end

function AnimationLoadDiagnostics.BuildAssetKey(animation)
	local animationId = getAnimationId(animation)
	if animationId ~= "" and animationId ~= "<nil>" then
		return animationId
	end

	return AnimationLoadDiagnostics.DescribeAnimation(animation)
end

function AnimationLoadDiagnostics.IsPermissionFailure(detail)
	local loweredDetail = string.lower(tostring(detail or ""))
	return loweredDetail == "permission_denied"
		or string.find(loweredDetail, "permission_denied", 1, true) ~= nil
		or AnimationLoadDiagnostics.IsPermissionError(detail)
end

function AnimationLoadDiagnostics.GetCachedFailure(animation)
	local assetKey = AnimationLoadDiagnostics.BuildAssetKey(animation)
	local state = cachedFailureByAssetKey[assetKey]
	if type(state) ~= "table" then
		return nil
	end

	if (tonumber(state.RetryAt) or 0) <= os.clock() then
		cachedFailureByAssetKey[assetKey] = nil
		return nil
	end

	return state
end

function AnimationLoadDiagnostics.RememberFailure(animation, detail)
	local assetKey = AnimationLoadDiagnostics.BuildAssetKey(animation)
	local failureDetail = tostring(detail or "load_failed")
	local cooldown = AnimationLoadDiagnostics.IsPermissionFailure(failureDetail)
		and PERMISSION_DENIED_COOLDOWN
		or LOAD_FAILURE_COOLDOWN
	cachedFailureByAssetKey[assetKey] = {
		Detail = failureDetail,
		RetryAt = os.clock() + cooldown,
	}
end

function AnimationLoadDiagnostics.ClearFailure(animation)
	local assetKey = AnimationLoadDiagnostics.BuildAssetKey(animation)
	cachedFailureByAssetKey[assetKey] = nil
end

function AnimationLoadDiagnostics.DescribeAnimation(animation)
	if typeof(animation) ~= "Instance" then
		return tostring(animation)
	end

	if animation:IsA("Animation") then
		if animation.Parent then
			return string.format("%s id=%s", animation:GetFullName(), tostring(animation.AnimationId or ""))
		end

		return tostring(animation.AnimationId or "")
	end

	return animation:GetFullName()
end

function AnimationLoadDiagnostics.GetTrackAnimationId(track)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return nil
	end

	local okAnimation, animation = pcall(function()
		return track.Animation
	end)
	if okAnimation and typeof(animation) == "Instance" and animation:IsA("Animation") then
		local animationId = tostring(animation.AnimationId or "")
		if animationId ~= "" then
			return animationId
		end
	end

	local okAnimationId, animationId = pcall(function()
		return track.AnimationId
	end)
	if okAnimationId then
		local resolvedAnimationId = tostring(animationId or "")
		if resolvedAnimationId ~= "" then
			return resolvedAnimationId
		end
	end

	return nil
end

function AnimationLoadDiagnostics.LogTrackPlay(track, sourceLabel, contextLabel, requestedAnimationId, detail)
	local resolvedSource = tostring(sourceLabel or "unknown")
	local resolvedContext = tostring(contextLabel or "unknown")
	local resolvedRequestedId = tostring(requestedAnimationId or "<unknown>")
	local trackAnimationId = AnimationLoadDiagnostics.GetTrackAnimationId(track) or "<unavailable>"
	logInfo(
		"track play reached context=%s source=%s requestedId=%s trackId=%s detail=%s",
		resolvedContext,
		resolvedSource,
		resolvedRequestedId,
		trackAnimationId,
		tostring(detail or "")
	)
end

function AnimationLoadDiagnostics.IsPermissionError(message)
	local loweredMessage = string.lower(tostring(message or ""))
	return string.find(loweredMessage, "access permission", 1, true) ~= nil
		or string.find(loweredMessage, "permission", 1, true) ~= nil
		or string.find(loweredMessage, "403", 1, true) ~= nil
end

function AnimationLoadDiagnostics.LoadTrack(animator, animation, sourceLabel)
	local assetDescription = AnimationLoadDiagnostics.DescribeAnimation(animation)
	local resolvedSource = tostring(sourceLabel or "unknown")
	logInfo("requested asset=%s source=%s", assetDescription, resolvedSource)

	if typeof(animator) ~= "Instance" or not animator:IsA("Animator") then
		logWarn("failed to load asset=%s source=%s detail=animator_missing", assetDescription, resolvedSource)
		return nil, "animator_missing"
	end

	if typeof(animation) ~= "Instance" or not animation:IsA("Animation") then
		logWarn("failed to load asset=%s source=%s detail=invalid_animation_instance", assetDescription, resolvedSource)
		return nil, "invalid_animation_instance"
	end

	local cachedFailure = AnimationLoadDiagnostics.GetCachedFailure(animation)
	if cachedFailure then
		logInfo(
			"skipped cached asset=%s source=%s detail=%s",
			assetDescription,
			resolvedSource,
			tostring(cachedFailure.Detail)
		)
		return nil, cachedFailure.Detail
	end

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and trackOrError then
		AnimationLoadDiagnostics.ClearFailure(animation)
		logInfo(
			"track created asset=%s source=%s requestedId=%s trackId=%s",
			assetDescription,
			resolvedSource,
			getAnimationId(animation),
			tostring(AnimationLoadDiagnostics.GetTrackAnimationId(trackOrError) or "<unavailable>")
		)
		return trackOrError, nil
	end

	local errorMessage = tostring(trackOrError)
	if AnimationLoadDiagnostics.IsPermissionError(errorMessage) then
		AnimationLoadDiagnostics.RememberFailure(animation, "permission_denied")
		logWarn("permission denied asset=%s source=%s detail=%s", assetDescription, resolvedSource, errorMessage)
		return nil, "permission_denied"
	end

	AnimationLoadDiagnostics.RememberFailure(animation, errorMessage)
	logWarn("failed to load asset=%s source=%s detail=%s", assetDescription, resolvedSource, errorMessage)
	return nil, errorMessage
end

return AnimationLoadDiagnostics
