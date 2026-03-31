local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter =
	require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))

local player = Players.LocalPlayer

local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 1
local WARN_COOLDOWN = 4
local ENABLE_ATTRIBUTE = "UseSafeAnimateRuntime"
local TRANSITION_FADE_TIME = 0.12

local syntheticAnimationsById = {}
local activeState

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("AnimateRuntimeGuard:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[ANIMATE RUNTIME] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("AnimateRuntimeGuard:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[ANIMATE RUNTIME][WARN] " .. message, ...))
end

local function isEnabled()
	local attributeValue = ReplicatedStorage:GetAttribute(ENABLE_ATTRIBUTE)
	if attributeValue == nil then
		return true
	end

	return attributeValue == true
end

local function getSyntheticAnimation(animationId, name)
	local resolvedId = tostring(animationId or "")
	if resolvedId == "" then
		return nil
	end

	local animation = syntheticAnimationsById[resolvedId]
	if animation and animation.Parent == nil then
		return animation
	end

	animation = Instance.new("Animation")
	animation.Name = tostring(name or resolvedId)
	animation.AnimationId = resolvedId
	syntheticAnimationsById[resolvedId] = animation
	return animation
end

local function getAnimateScript(character)
	local animate = character and character:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		return animate
	end

	local ok, waitedAnimate = pcall(function()
		return character and character:WaitForChild("Animate", 2)
	end)
	if ok and waitedAnimate and waitedAnimate:IsA("LocalScript") then
		return waitedAnimate
	end

	return nil
end

local function disableAnimateScript(animate, character, reason)
	if typeof(animate) ~= "Instance" or not animate:IsA("LocalScript") then
		return false
	end

	if animate.Disabled ~= true then
		animate.Disabled = true
	end

	logInfo(
		"disabled stock Animate character=%s reason=%s",
		tostring(character and character.Name or animate.Parent and animate.Parent.Name or "<unknown>"),
		tostring(reason or "safe_runtime_guard")
	)
	return true
end

local function collectAnimationIds(folder)
	local animationIds = {}
	if typeof(folder) ~= "Instance" then
		return animationIds
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Animation") then
			local animationId = tostring(descendant.AnimationId or "")
			if animationId ~= "" then
				animationIds[#animationIds + 1] = animationId
			end
		end
	end

	return animationIds
end

local function buildAnimationCatalog(character)
	local animate = getAnimateScript(character)
	return {
		Animate = animate,
		Idle = collectAnimationIds(animate and animate:FindFirstChild("idle")),
		Walk = collectAnimationIds(animate and animate:FindFirstChild("walk")),
		Run = collectAnimationIds(animate and animate:FindFirstChild("run")),
		Jump = collectAnimationIds(animate and animate:FindFirstChild("jump")),
		Fall = collectAnimationIds(animate and animate:FindFirstChild("fall")),
		Climb = collectAnimationIds(animate and animate:FindFirstChild("climb")),
		Swim = collectAnimationIds(animate and animate:FindFirstChild("swim")),
		SwimIdle = collectAnimationIds(animate and animate:FindFirstChild("swimidle")),
		Sit = collectAnimationIds(animate and animate:FindFirstChild("sit")),
	}
end

local function hasAnyAnimations(animationCatalog)
	for key, value in pairs(animationCatalog) do
		if key ~= "Animate" and type(value) == "table" and #value > 0 then
			return true
		end
	end

	return false
end

local function stopTrack(track)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return
	end

	pcall(function()
		track:Stop(TRANSITION_FADE_TIME)
	end)
end

local function destroyRuntimeState(state)
	if type(state) ~= "table" then
		return
	end

	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end

	for _, track in pairs(state.Tracks or {}) do
		stopTrack(track)
	end

	state.Tracks = {}
	state.Destroyed = true
end

local function getAnimator(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")
	if animator and animator:IsA("Animator") then
		return humanoid, animator
	end

	local ok, waitedAnimator = pcall(function()
		return humanoid:WaitForChild("Animator", 2)
	end)
	if ok and waitedAnimator and waitedAnimator:IsA("Animator") then
		return humanoid, waitedAnimator
	end

	return humanoid, nil
end

local function getAnimationIdsForState(state, key)
	local animationIds = state.AnimationCatalog[key]
	if type(animationIds) == "table" and #animationIds > 0 then
		return animationIds
	end

	if key == "Run" then
		return getAnimationIdsForState(state, "Walk")
	end

	if key == "SwimIdle" then
		return getAnimationIdsForState(state, "Swim")
	end

	return {}
end

local function getTrackPriority(key)
	if key == "Idle" then
		return Enum.AnimationPriority.Idle
	end

	if key == "Sit" then
		return Enum.AnimationPriority.Core
	end

	return Enum.AnimationPriority.Movement
end

local function shouldLoopTrack(key)
	return key ~= "Jump"
end

local function loadTrackForState(state, key)
	local existingTrack = state.Tracks[key]
	if existingTrack and existingTrack.Parent then
		return existingTrack
	end

	for _, animationId in ipairs(getAnimationIdsForState(state, key)) do
		local animation = getSyntheticAnimation(animationId, "SafeAnimate_" .. key)
		if animation then
			local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
				state.Animator,
				animation,
				"StarterPlayer.StarterPlayerScripts.AnimateRuntimeGuard"
			)
			if track then
				track.Priority = getTrackPriority(key)
				track.Looped = shouldLoopTrack(key)
				state.Tracks[key] = track
				return track
			end

			logWarn("state=%s asset=%s detail=%s", tostring(key), tostring(animationId), tostring(loadFailure))
		end
	end

	return nil
end

local function resolveMovementState(state)
	local humanoid = state.Humanoid
	local rootPart = state.RootPart
	if not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart.Parent then
		return nil, 1
	end

	local planarVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z).Magnitude
	local humanoidState = humanoid:GetState()

	if humanoid.Sit then
		return "Sit", 1
	end

	if humanoidState == Enum.HumanoidStateType.Swimming then
		if planarVelocity > 1 then
			return "Swim", math.max(0.7, planarVelocity / 10)
		end
		return "SwimIdle", 1
	end

	if humanoidState == Enum.HumanoidStateType.Climbing then
		return "Climb", math.max(0.8, planarVelocity / 8)
	end

	if humanoidState == Enum.HumanoidStateType.Jumping then
		return "Jump", 1
	end

	if humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.FallingDown then
		return "Fall", 1
	end

	if planarVelocity > 10 then
		return "Run", math.max(0.8, planarVelocity / 16)
	end

	if planarVelocity > 0.5 then
		return "Walk", math.max(0.7, planarVelocity / 10)
	end

	return "Idle", 1
end

local function playResolvedState(state, key, speed)
	if state.CurrentKey == key then
		local currentTrack = state.CurrentTrack
		if currentTrack then
			if currentTrack.IsPlaying then
				pcall(function()
					currentTrack:AdjustSpeed(speed)
				end)
			else
				currentTrack:Play(TRANSITION_FADE_TIME, 1, speed)
			end
		end
		return
	end

	stopTrack(state.CurrentTrack)
	state.CurrentTrack = nil
	state.CurrentKey = nil

	local track = loadTrackForState(state, key)
	if not track then
		return
	end

	state.CurrentTrack = track
	state.CurrentKey = key
	track:Play(TRANSITION_FADE_TIME, 1, speed)
	logInfo("character=%s state=%s", state.Character.Name, key)
end

local function startRuntimeAnimate(character)
	if not isEnabled() then
		return
	end

	destroyRuntimeState(activeState)
	activeState = nil

	local humanoid, animator = getAnimator(character)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not animator or not rootPart then
		logWarn("startup skipped character=%s detail=missing_runtime_parts", tostring(character))
		return
	end

	local animationCatalog = buildAnimationCatalog(character)
	local animate = animationCatalog.Animate
	if animate then
		disableAnimateScript(animate, character, "safe_runtime_enabled")
	end

	if not hasAnyAnimations(animationCatalog) then
		logWarn(
			"startup skipped character=%s detail=empty_animation_catalog stockAnimateDisabled=%s",
			character.Name,
			tostring(animate ~= nil)
		)
		return
	end

	local state = {
		Character = character,
		Humanoid = humanoid,
		Animator = animator,
		RootPart = rootPart,
		AnimationCatalog = animationCatalog,
		Tracks = {},
		CurrentTrack = nil,
		CurrentKey = nil,
		Destroyed = false,
	}
	activeState = state

	state.Connection = RunService.Heartbeat:Connect(function()
		if activeState ~= state or state.Destroyed then
			return
		end

		if not character.Parent or humanoid.Health <= 0 or not rootPart.Parent then
			destroyRuntimeState(state)
			if activeState == state then
				activeState = nil
			end
			return
		end

		local nextKey, nextSpeed = resolveMovementState(state)
		if not nextKey then
			return
		end

		playResolvedState(state, nextKey, nextSpeed)
	end)
end

local function handleCharacter(character)
	if typeof(character) ~= "Instance" then
		return
	end

	task.defer(startRuntimeAnimate, character)
end

if player.Character then
	handleCharacter(player.Character)
end

player.CharacterAdded:Connect(handleCharacter)
player.CharacterRemoving:Connect(function(character)
	if activeState and activeState.Character == character then
		destroyRuntimeState(activeState)
		activeState = nil
	end
end)
