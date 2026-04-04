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
local CATALOG_DISCOVERY_TIMEOUT = 4
local CATALOG_RETRY_INTERVAL = 0.2
local CATALOG_STATE_ORDER = { "Idle", "Walk", "Run", "Jump", "Fall", "Climb", "Swim", "SwimIdle", "Sit" }
local REQUIRED_LOCOMOTION_KEYS = { "Idle", "Walk", "Jump", "Fall" }
local CATALOG_FOLDER_NAMES = {
	Idle = "idle",
	Walk = "walk",
	Run = "run",
	Jump = "jump",
	Fall = "fall",
	Climb = "climb",
	Swim = "swim",
	SwimIdle = "swimidle",
	Sit = "sit",
}

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
	return ReplicatedStorage:GetAttribute(ENABLE_ATTRIBUTE) == true
end

local function isRequiredState(key)
	for _, requiredKey in ipairs(REQUIRED_LOCOMOTION_KEYS) do
		if requiredKey == key then
			return true
		end
	end

	return false
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
		return false, false
	end

	local disabledByRuntime = animate.Disabled ~= true
	if disabledByRuntime then
		animate.Disabled = true
	end

	logInfo(
		"disabled stock Animate character=%s reason=%s",
		tostring(character and character.Name or animate.Parent and animate.Parent.Name or "<unknown>"),
		tostring(reason or "safe_runtime_guard")
	)
	return true, disabledByRuntime
end

local function restoreAnimateScript(animate, character, reason, disabledByRuntime)
	if disabledByRuntime ~= true then
		return false
	end

	if typeof(animate) ~= "Instance" or not animate:IsA("LocalScript") or animate.Parent == nil then
		return false
	end

	if animate.Disabled then
		animate.Disabled = false
	end

	logInfo(
		"re-enabled stock Animate character=%s reason=%s",
		tostring(character and character.Name or animate.Parent and animate.Parent.Name or "<unknown>"),
		tostring(reason or "runtime_stopped")
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
	local animationCatalog = {
		Animate = animate,
		Source = animate and animate:GetFullName() or "Character.Animate",
	}

	for _, key in ipairs(CATALOG_STATE_ORDER) do
		animationCatalog[key] = collectAnimationIds(animate and animate:FindFirstChild(CATALOG_FOLDER_NAMES[key]))
	end

	return animationCatalog
end

local function getCatalogAnimationIds(animationCatalog, key)
	local animationIds = animationCatalog[key]
	if type(animationIds) == "table" and #animationIds > 0 then
		return animationIds, key
	end

	if key == "Run" then
		return getCatalogAnimationIds(animationCatalog, "Walk")
	end

	if key == "SwimIdle" then
		return getCatalogAnimationIds(animationCatalog, "Swim")
	end

	return {}, key
end

local function formatAnimationIds(animationIds)
	if type(animationIds) ~= "table" or #animationIds == 0 then
		return "<none>"
	end

	return table.concat(animationIds, "|")
end

local function buildCatalogEntrySummary(animationCatalog)
	local parts = {}
	for _, key in ipairs(CATALOG_STATE_ORDER) do
		local animationIds = animationCatalog[key]
		parts[#parts + 1] = string.format("%s=%d", key, type(animationIds) == "table" and #animationIds or 0)
	end

	return table.concat(parts, ",")
end

local function buildMappedStates(animationCatalog)
	local mappedStates = {}
	for _, key in ipairs(CATALOG_STATE_ORDER) do
		local animationIds = animationCatalog[key]
		if type(animationIds) == "table" and #animationIds > 0 then
			mappedStates[#mappedStates + 1] = key
		end
	end

	return mappedStates
end

local function buildMissingRequiredStates(animationCatalog)
	local missingStates = {}
	for _, key in ipairs(REQUIRED_LOCOMOTION_KEYS) do
		local animationIds = animationCatalog[key]
		if type(animationIds) ~= "table" or #animationIds == 0 then
			missingStates[#missingStates + 1] = key
		end
	end

	return missingStates
end

local function hasRequiredAnimations(animationCatalog)
	return #buildMissingRequiredStates(animationCatalog) == 0
end

local function waitForAnimationCatalog(character)
	local animationCatalog = buildAnimationCatalog(character)
	local deadline = os.clock() + CATALOG_DISCOVERY_TIMEOUT

	while os.clock() < deadline do
		if hasRequiredAnimations(animationCatalog) then
			return animationCatalog, nil
		end

		local animate = animationCatalog.Animate or getAnimateScript(character)
		if animate then
			for _, key in ipairs(REQUIRED_LOCOMOTION_KEYS) do
				local animationIds = animationCatalog[key]
				if type(animationIds) ~= "table" or #animationIds == 0 then
					pcall(function()
						animate:WaitForChild(CATALOG_FOLDER_NAMES[key], CATALOG_RETRY_INTERVAL)
					end)
				end
			end
		end

		task.wait(CATALOG_RETRY_INTERVAL)
		animationCatalog = buildAnimationCatalog(character)
	end

	return animationCatalog, "missing_required_locomotion_states"
end

local function stopTrack(track)
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return
	end

	pcall(function()
		track:Stop(TRANSITION_FADE_TIME)
	end)
end

local function stopTrackCollection(trackCollection)
	if type(trackCollection) ~= "table" then
		return
	end

	local stopped = {}
	for _, track in pairs(trackCollection) do
		if stopped[track] then
			continue
		end

		stopped[track] = true
		stopTrack(track)
	end
end

local function destroyRuntimeState(state, reason)
	if type(state) ~= "table" then
		return
	end

	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end

	stopTrackCollection(state.Tracks)
	state.Tracks = {}
	restoreAnimateScript(state.Animate, state.Character, reason, state.DisabledStockAnimate)
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

local function getRootPart(character)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	local ok, waitedRootPart = pcall(function()
		return character and character:WaitForChild("HumanoidRootPart", 2)
	end)
	if ok and waitedRootPart and waitedRootPart:IsA("BasePart") then
		return waitedRootPart
	end

	return nil
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

local function probeCatalogTrack(animator, animationCatalog, key)
	local animationIds, sourceKey = getCatalogAnimationIds(animationCatalog, key)
	local attempts = {}

	for _, animationId in ipairs(animationIds) do
		local animation = getSyntheticAnimation(animationId, "SafeAnimate_" .. key)
		if animation then
			local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(
				animator,
				animation,
				"StarterPlayer.StarterPlayerScripts.AnimateRuntimeGuard"
			)
			attempts[#attempts + 1] = {
				AnimationId = animationId,
				Detail = loadFailure,
			}
			if track then
				track.Priority = getTrackPriority(key)
				track.Looped = shouldLoopTrack(key)
				return track, attempts, sourceKey, animationId
			end
		else
			attempts[#attempts + 1] = {
				AnimationId = animationId,
				Detail = "invalid_animation_id",
			}
		end
	end

	return nil, attempts, sourceKey, nil
end

local function validateAnimationCatalog(animator, animationCatalog)
	local validation = {
		Ready = false,
		Tracks = {},
		Reports = {},
		MissingRequired = {},
		InaccessibleRequired = {},
	}

	for _, key in ipairs(CATALOG_STATE_ORDER) do
		local candidateIds, sourceKey = getCatalogAnimationIds(animationCatalog, key)
		local report = {
			Key = key,
			SourceKey = sourceKey,
			CandidateIds = candidateIds,
			Accessible = false,
			SelectedAnimationId = nil,
			LastFailure = (#candidateIds == 0) and "missing_animation" or "load_failed",
		}

		local sharedTrack = sourceKey ~= key and validation.Tracks[sourceKey]
		local sharedReport = sourceKey ~= key and validation.Reports[sourceKey] or nil
		if sharedTrack and sharedReport and sharedReport.Accessible then
			report.Accessible = true
			report.SelectedAnimationId = sharedReport.SelectedAnimationId
			report.LastFailure = nil
			validation.Tracks[key] = sharedTrack
		else
			local track, attempts, resolvedSourceKey, selectedAnimationId = probeCatalogTrack(animator, animationCatalog, key)
			report.SourceKey = resolvedSourceKey
			report.Attempts = attempts
			if track then
				report.Accessible = true
				report.SelectedAnimationId = selectedAnimationId
				report.LastFailure = nil
				validation.Tracks[key] = track
			elseif type(attempts) == "table" and #attempts > 0 then
				local lastAttempt = attempts[#attempts]
				report.LastFailure = tostring(lastAttempt and lastAttempt.Detail or report.LastFailure)
			end
		end

		validation.Reports[key] = report
		if isRequiredState(key) then
			if #candidateIds == 0 then
				validation.MissingRequired[#validation.MissingRequired + 1] = key
			elseif not report.Accessible then
				validation.InaccessibleRequired[#validation.InaccessibleRequired + 1] = key
			end
		end
	end

	validation.Ready = #validation.MissingRequired == 0 and #validation.InaccessibleRequired == 0
	return validation
end

local function logCatalogDiagnostics(character, animationCatalog, validation)
	local mappedStates = buildMappedStates(animationCatalog)
	logInfo(
		"catalog loaded character=%s source=%s entries=%s mappedStates=%s",
		tostring(character and character.Name or "<nil>"),
		tostring(animationCatalog.Source),
		buildCatalogEntrySummary(animationCatalog),
		#mappedStates > 0 and table.concat(mappedStates, ",") or "<none>"
	)

	for _, key in ipairs(CATALOG_STATE_ORDER) do
		local report = validation and validation.Reports[key] or nil
		local candidateIds, sourceKey = getCatalogAnimationIds(animationCatalog, key)
		local detail = report and report.LastFailure or (#candidateIds == 0 and "missing_animation" or "unvalidated")
		local message = "state=%s source=%s ids=%s accessible=%s detail=%s"
		if report and report.Accessible then
			logInfo(
				message,
				tostring(key),
				tostring(sourceKey),
				formatAnimationIds(candidateIds),
				"true",
				tostring(report.SelectedAnimationId)
			)
		elseif isRequiredState(key) then
			logWarn(
				message,
				tostring(key),
				tostring(sourceKey),
				formatAnimationIds(candidateIds),
				"false",
				tostring(detail)
			)
		else
			logInfo(
				message,
				tostring(key),
				tostring(sourceKey),
				formatAnimationIds(candidateIds),
				"false",
				tostring(detail)
			)
		end
	end
end

local function buildFallbackDetail(animationCatalog, catalogFailure, validation)
	local details = {}
	if catalogFailure then
		details[#details + 1] = tostring(catalogFailure)
	end

	local missingStates = buildMissingRequiredStates(animationCatalog)
	if #missingStates > 0 then
		details[#details + 1] = "missing_required:" .. table.concat(missingStates, ",")
	end

	if validation and #validation.InaccessibleRequired > 0 then
		details[#details + 1] = "inaccessible_required:" .. table.concat(validation.InaccessibleRequired, ",")
	end

	if #details == 0 then
		details[#details + 1] = "catalog_invalid"
	end

	return table.concat(details, ";")
end

local function loadTrackForState(state, key)
	local existingTrack = state.Tracks[key]
	if existingTrack and existingTrack.Parent then
		return existingTrack
	end

	local animationIds = getCatalogAnimationIds(state.AnimationCatalog, key)
	for _, animationId in ipairs(animationIds) do
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
	destroyRuntimeState(activeState, "startup_reset")
	activeState = nil

	if not isEnabled() then
		logInfo("retained stock Animate character=%s reason=safe_runtime_disabled", tostring(character and character.Name or "<nil>"))
		return
	end

	local humanoid, animator = getAnimator(character)
	local rootPart = getRootPart(character)
	if not humanoid or not animator or not rootPart then
		logWarn(
			"startup fallback character=%s detail=missing_runtime_parts stockAnimateRetained=true",
			tostring(character and character.Name or "<nil>")
		)
		return
	end

	local animationCatalog, catalogFailure = waitForAnimationCatalog(character)
	local animate = animationCatalog.Animate
	local validation = validateAnimationCatalog(animator, animationCatalog)
	logCatalogDiagnostics(character, animationCatalog, validation)

	if not validation.Ready then
		stopTrackCollection(validation.Tracks)
		logWarn(
			"startup fallback character=%s detail=%s stockAnimateRetained=true",
			tostring(character and character.Name or "<nil>"),
			buildFallbackDetail(animationCatalog, catalogFailure, validation)
		)
		return
	end

	local disabledAnimate, disabledByRuntime = disableAnimateScript(animate, character, "safe_runtime_enabled")
	if not disabledAnimate then
		stopTrackCollection(validation.Tracks)
		logWarn(
			"startup fallback character=%s detail=animate_missing_after_validation stockAnimateRetained=true",
			tostring(character and character.Name or "<nil>")
		)
		return
	end

	local state = {
		Character = character,
		Humanoid = humanoid,
		Animator = animator,
		RootPart = rootPart,
		Animate = animate,
		DisabledStockAnimate = disabledByRuntime,
		AnimationCatalog = animationCatalog,
		Tracks = validation.Tracks,
		CurrentTrack = nil,
		CurrentKey = nil,
		Destroyed = false,
	}
	activeState = state

	logInfo(
		"runtime initialized character=%s source=%s mappedStates=%s",
		character.Name,
		tostring(animationCatalog.Source),
		table.concat(buildMappedStates(animationCatalog), ",")
	)

	state.Connection = RunService.Heartbeat:Connect(function()
		if activeState ~= state or state.Destroyed then
			return
		end

		if not character.Parent or humanoid.Health <= 0 or not rootPart.Parent then
			destroyRuntimeState(state, "character_invalid")
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
		destroyRuntimeState(activeState, "character_removing")
		activeState = nil
	end
end)
