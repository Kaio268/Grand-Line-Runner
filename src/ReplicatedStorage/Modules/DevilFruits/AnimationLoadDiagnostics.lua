local RunService = game:GetService("RunService")

local DiagnosticLogLimiter = require(script.Parent:WaitForChild("DiagnosticLogLimiter"))

local AnimationLoadDiagnostics = {}

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.5
local WARN_COOLDOWN = 3

local function logInfo(message, ...)
	if not DEBUG_INFO then
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

	local ok, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)
	if ok and trackOrError then
		return trackOrError, nil
	end

	local errorMessage = tostring(trackOrError)
	if AnimationLoadDiagnostics.IsPermissionError(errorMessage) then
		logWarn("permission denied asset=%s source=%s detail=%s", assetDescription, resolvedSource, errorMessage)
		return nil, "permission_denied"
	end

	logWarn("failed to load asset=%s source=%s detail=%s", assetDescription, resolvedSource, errorMessage)
	return nil, errorMessage
end

return AnimationLoadDiagnostics
