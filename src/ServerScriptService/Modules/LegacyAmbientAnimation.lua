local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))

local LegacyAmbientAnimation = {}

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 2
local WARN_COOLDOWN = 5
local ENABLE_ATTRIBUTE = "EnableLegacyMapAmbientAnimations"

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("LegacyAmbientAnimation:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[LEGACY AMBIENT] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("LegacyAmbientAnimation:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[LEGACY AMBIENT][WARN] " .. message, ...))
end

local function isEnabled(target)
	if typeof(target) == "Instance" then
		local localSetting = target:GetAttribute(ENABLE_ATTRIBUTE)
		if localSetting ~= nil then
			return localSetting == true
		end
	end

	return ReplicatedStorage:GetAttribute(ENABLE_ATTRIBUTE) == true
end

local function getAnimationController(target)
	if typeof(target) ~= "Instance" then
		return nil
	end

	local controller = target:FindFirstChild("AnimationController") or target:FindFirstChildWhichIsA("AnimationController", true)
	if controller and controller:IsA("AnimationController") then
		return controller
	end

	controller = Instance.new("AnimationController")
	controller.Name = "AnimationController"
	controller.Parent = target
	return controller
end

local function getAnimator(controller)
	if typeof(controller) ~= "Instance" or not controller:IsA("AnimationController") then
		return nil
	end

	local animator = controller:FindFirstChild("Animator") or controller:FindFirstChildWhichIsA("Animator")
	if animator and animator:IsA("Animator") then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = controller
	return animator
end

function LegacyAmbientAnimation.PlayLoop(target, animationId, sourceLabel)
	if not isEnabled(target) then
		return nil, "disabled"
	end

	local controller = getAnimationController(target)
	local animator = getAnimator(controller)
	if not animator then
		logWarn("play failed source=%s detail=animator_missing", tostring(sourceLabel or target))
		return nil, "animator_missing"
	end

	local animation = Instance.new("Animation")
	animation.Name = "LegacyAmbientAnimation"
	animation.AnimationId = tostring(animationId or "")

	local track, loadFailure =
		AnimationLoadDiagnostics.LoadTrack(animator, animation, tostring(sourceLabel or "LegacyAmbientAnimation"))
	if not track then
		logWarn(
			"play failed source=%s animationId=%s detail=%s",
			tostring(sourceLabel or target),
			tostring(animationId),
			tostring(loadFailure)
		)
		return nil, loadFailure
	end

	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true
	track:Play(0.1, 1, 1)
	logInfo("play started source=%s animationId=%s", tostring(sourceLabel or target), tostring(animationId))
	return track, nil
end

return LegacyAmbientAnimation
