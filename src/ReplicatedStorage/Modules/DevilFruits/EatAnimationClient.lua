local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local FruitGripController = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("FruitGripController"))
local AnimationResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AnimationResolver"))

local EatAnimationClient = {}

local RIG_FOLDER_R6 = "R6"
local RIG_FOLDER_R6G = "R6G"
local RIG_ATTRIBUTE_NAMES = {
	"EatAnimationRig",
	"RigAnimationVariant",
	"RigVariant",
	"RigTypeName",
	"RigName",
}
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.35
local WARN_COOLDOWN = 3
local ANIMATE_WARN_COOLDOWN = 4
local MIN_VISIBLE_PLAY_TIME = 0.85
local POST_PLAY_BUFFER = 0.1
local SOURCE_LABEL = "ReplicatedStorage.Modules.DevilFruits.EatAnimationClient"
local HOLD_PRESENTATION_SUPPRESS_ATTRIBUTE = "FruitEatAnimationActive"
local OWN_DIAGNOSTIC_PREFIXES = {
	"[ANIMATE][WARN]",
	"[ANIMATE]",
	"[EAT ANIM]",
	"[ANIM LOAD]",
	"[ANIM LOAD][WARN]",
}
local animateDiagnosticsHooked = false
local animateErrorObserved = false
local animateDiagnosticEmitting = false
local activePlaybackInfo = nil

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("EatAnimationClient:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[EAT ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("EatAnimationClient:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[EAT ANIM][WARN] " .. message, ...))
end

local function logAnimateWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("EatAnimationClient:ANIMATEWARN", DiagnosticLogLimiter.BuildKey(message, ...), ANIMATE_WARN_COOLDOWN) then
		return
	end

	warn(string.format("[ANIMATE][WARN] " .. message, ...))
end

local function formatTrackState(track)
	if typeof(track) ~= "Instance" then
		return "track=<nil>"
	end

	return string.format(
		"isPlaying=%s length=%.3f timePosition=%.3f speed=%.2f weight=%.2f",
		tostring(track.IsPlaying),
		tonumber(track.Length) or 0,
		tonumber(track.TimePosition) or 0,
		tonumber(track.Speed) or 0,
		tonumber(track.WeightCurrent) or 0
	)
end

local function describeAnimationAsset(animation)
	if not animation then
		return "<nil>"
	end

	if animation.Parent then
		return animation:GetFullName()
	end

	return tostring(animation.AnimationId)
end

local function getAnimator(character)
	if typeof(character) ~= "Instance" then
		logWarn("animator missing character=nil")
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		logWarn("animator missing character=%s humanoid=nil_or_dead", character.Name)
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local ok, waitedAnimator = pcall(function()
		return humanoid:WaitForChild("Animator", 2)
	end)
	if ok and waitedAnimator and waitedAnimator:IsA("Animator") then
		return waitedAnimator
	end

	logWarn("animator missing character=%s humanoid=%s", character.Name, humanoid.Name)
	return nil
end

local function getActiveFruitTool(character, fruitKey)
	if typeof(character) ~= "Instance" then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and (fruitKey == nil or child:GetAttribute("FruitKey") == fruitKey) then
			return child
		end
	end

	return nil
end

local function setHoldPresentationSuppressed(tool, isSuppressed)
	if not (tool and tool:IsA("Tool")) then
		return
	end

	tool:SetAttribute(HOLD_PRESENTATION_SUPPRESS_ATTRIBUTE, isSuppressed == true)
end

local function getAnimateScript(character)
	if typeof(character) ~= "Instance" then
		return nil
	end

	local animate = character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		return animate
	end

	return nil
end

local function applyAnimateGuard(character, reason)
	local animate = getAnimateScript(character)
	if not animate then
		return nil
	end

	local guardState = {
		Animate = animate,
		WasDisabled = animate.Disabled == true,
		Reason = tostring(reason or "unknown"),
	}

	if not guardState.WasDisabled then
		animate.Disabled = true
		if DEBUG_INFO and DiagnosticLogLimiter.ShouldEmit("EatAnimationClient:ANIMATEGUARD", guardState.Reason, 2) then
			print(string.format("[ANIMATE] guard applied for missing move state reason=%s", guardState.Reason))
		end
	end

	return guardState
end

local function restoreAnimateGuard(guardState)
	if type(guardState) ~= "table" then
		return
	end

	local animate = guardState.Animate
	if typeof(animate) ~= "Instance" or not animate.Parent then
		return
	end

	if not guardState.WasDisabled then
		animate.Disabled = false
	end
end

local function ensureAnimateDiagnosticsHook()
	if animateDiagnosticsHooked then
		return
	end

	animateDiagnosticsHooked = true
	LogService.MessageOut:Connect(function(message)
		if animateDiagnosticEmitting or DiagnosticLogLimiter.StartsWithAny(message, OWN_DIAGNOSTIC_PREFIXES) then
			return
		end

		local loweredMessage = string.lower(tostring(message))
		if string.find(message, "Animate:333", 1, true)
			and string.find(loweredMessage, "attempt to perform arithmetic", 1, true)
			and string.find(loweredMessage, "nil and number", 1, true)
		then
			animateErrorObserved = true
			if activePlaybackInfo then
				if not activePlaybackInfo.AnimateDiagnosticLogged then
					activePlaybackInfo.AnimateDiagnosticLogged = true
					animateDiagnosticEmitting = true
					logAnimateWarn(
						"move state nil at line 333 value=<runtime_local_unavailable> message=%s activeEatAnimation=%s state=%s",
						tostring(message),
						tostring(activePlaybackInfo.AnimationDescription),
						formatTrackState(activePlaybackInfo.Track)
					)
					animateDiagnosticEmitting = false
				end
				return
			end

			animateDiagnosticEmitting = true
			logAnimateWarn("move state nil at line 333 value=<runtime_local_unavailable> message=%s", tostring(message))
			animateDiagnosticEmitting = false
		end
	end)
end

local function normalizeRigFolderName(value)
	if typeof(value) ~= "string" then
		return nil
	end

	local normalized = string.upper(value)
	if normalized == RIG_FOLDER_R6 then
		return RIG_FOLDER_R6
	end

	if normalized == RIG_FOLDER_R6G then
		return RIG_FOLDER_R6G
	end

	return nil
end

local function detectRigFromModelAsset(target)
	if not target then
		return nil
	end

	local currentModelAsset = normalizeRigFolderName(target:GetAttribute("CurrentModelAsset"))
	if currentModelAsset then
		return currentModelAsset
	end

	return nil
end

local function detectRigFolderName(player, character, humanoid)
	local attributeTargets = { character, humanoid, player }
	for _, target in ipairs(attributeTargets) do
		if target then
			for _, attributeName in ipairs(RIG_ATTRIBUTE_NAMES) do
				local normalized = normalizeRigFolderName(target:GetAttribute(attributeName))
				if normalized then
					logInfo("rig detected: %s source=%s", normalized, attributeName)
					return normalized
				end
			end

			local modelAssetRig = detectRigFromModelAsset(target)
			if modelAssetRig then
				logInfo("rig detected: %s source=CurrentModelAsset", modelAssetRig)
				return modelAssetRig
			end
		end
	end

	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
		logInfo("rig detected: %s source=Humanoid.RigType", RIG_FOLDER_R6)
		return RIG_FOLDER_R6
	end

	logWarn("rig mismatch for EatFruit animation humanoidRigType=%s", humanoid and humanoid.RigType.Name or "<nil>")
	return nil
end

local function loadEatAnimationTrack(player, character, humanoid, animator)
	local rigFolderName = detectRigFolderName(player, character, humanoid)
	if not rigFolderName then
		logWarn("no valid EatFruit registry animation found reason=unsupported_rig")
		return nil, nil, nil
	end

	local animation, descriptor = AnimationResolver.GetAnimation("EatFruit", {
		Variant = rigFolderName,
		Context = "EatFruit",
	})
	if not animation then
		logWarn(
			"no valid EatFruit registry animation found rig=%s detail=%s",
			tostring(rigFolderName),
			tostring(descriptor and descriptor.Source or "missing_registry_animation")
		)
		return nil, nil, rigFolderName
	end

	local assetDescription = descriptor and descriptor.Path or describeAnimationAsset(animation)
	logInfo("eat pose animation selected: %s", assetDescription)
	logInfo("asset resolved: %s id=%s", assetDescription, tostring(descriptor and descriptor.AnimationId))

	local trackOrError, loadFailure = AnimationLoadDiagnostics.LoadTrack(
		animator,
		animation,
		SOURCE_LABEL
	)
	if trackOrError then
		logInfo("selected registry animation: %s", assetDescription)
		logInfo("load success state=%s", formatTrackState(trackOrError))
		return trackOrError, animation, rigFolderName
	end

	local errorMessage = tostring(loadFailure)
	logWarn("load failed asset=%s detail=%s", assetDescription, errorMessage)
	if AnimationLoadDiagnostics.IsPermissionError(errorMessage) or errorMessage == "permission_denied" then
		logWarn("experience lacks permission for asset asset=%s", assetDescription)
	end

	return nil, nil, rigFolderName
end

function EatAnimationClient.Play(player, fruitKey)
	local character = player and player.Character
	if not character then
		return false
	end

	ensureAnimateDiagnosticsHook()

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = getAnimator(character)
	if not animator then
		return false
	end

	local track, selectedAnimation, rigFolderName = loadEatAnimationTrack(player, character, humanoid, animator)
	if not track then
		return false
	end

	local tool = getActiveFruitTool(character, fruitKey)
	if tool then
		setHoldPresentationSuppressed(tool, true)
		FruitGripController.PushContext(tool, fruitKey, "Eat", {
			Tool = tool,
			Player = player,
			Character = character,
		})
	end

	local animateGuardState = applyAnimateGuard(
		character,
		animateErrorObserved and "eat_pose_active_after_error" or "eat_pose_isolation"
	)

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	local selectedDescription = describeAnimationAsset(selectedAnimation)
	logInfo("play attempted asset=%s rig=%s", selectedDescription, tostring(rigFolderName or "<unknown>"))
	activePlaybackInfo = {
		AnimationDescription = selectedDescription,
		Track = track,
		StartedAt = os.clock(),
	}
	track:Play(0.1, 1, 1)
	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		"EatFruit",
		selectedAnimation and selectedAnimation.AnimationId,
		string.format("rig=%s fade=0.100 speed=1.000 looped=%s", tostring(rigFolderName or "<unknown>"), tostring(track.Looped))
	)
	task.wait()
	local playConfirmed = track.IsPlaying or (tonumber(track.TimePosition) or 0) > 0
	if playConfirmed then
		logInfo("play confirmed asset=%s state=%s", selectedDescription, formatTrackState(track))
		logInfo("hold pose started")
	else
		logWarn("play not confirmed asset=%s state=%s", selectedDescription, formatTrackState(track))
	end

	local completed = false
	local connection = track.Stopped:Connect(function()
		completed = true
	end)

	local timeoutAt = os.clock() + math.max(0.75, (tonumber(track.Length) or 0) + 0.35)
	while not completed and os.clock() < timeoutAt do
		task.wait()
	end

	local visiblePlayDeadline = activePlaybackInfo.StartedAt + MIN_VISIBLE_PLAY_TIME
	while os.clock() < visiblePlayDeadline do
		task.wait()
	end

	if playConfirmed and POST_PLAY_BUFFER > 0 then
		task.wait(POST_PLAY_BUFFER)
	end

	if connection then
		connection:Disconnect()
	end

	if tool then
		FruitGripController.PopContext(tool, fruitKey, "Eat", {
			Tool = tool,
			Player = player,
			Character = character,
		})
		setHoldPresentationSuppressed(tool, false)
	end

	restoreAnimateGuard(animateGuardState)
	activePlaybackInfo = nil
	logInfo("eat sequence completed")
	return true
end

return EatAnimationClient
