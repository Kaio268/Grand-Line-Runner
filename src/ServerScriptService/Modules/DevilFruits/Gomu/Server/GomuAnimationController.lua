local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimationLoadDiagnostics = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("AnimationLoadDiagnostics"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local AnimationResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AnimationResolver"))

local GomuAnimationController = {}

local DEBUG_INFO = RunService:IsStudio()
local DEFAULT_FADE_TIME = 0.06
local DEFAULT_STOP_FADE_TIME = 0.1
local DEFAULT_RELEASE_FALLBACK_TIME = 0
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3
local SOURCE_LABEL = "ServerScriptService.Modules.DevilFruits.Gomu.Server.GomuAnimationController"
local RUBBER_LAUNCH_MOVE_NAME = "RubberLaunch"
local RUBBER_LAUNCH_DEFAULT_ANIMATION_KEY = "Gomu.Rocket"
local DEFAULT_ARM_STRETCH_MARKERS = { "Stretch", "StretchArms" }
local DEFAULT_ARM_RESTORE_MARKERS = { "Unstretch", "RestoreArms" }
local DEFAULT_ARM_STRETCH_SIZE = Vector3.new(1, 27.066, 1)
local DEFAULT_ARM_RESTORE_FALLBACK_TIME = 0.85

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("GomuAnimationController:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[GOMU ANIM] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("GomuAnimationController:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[GOMU ANIM][WARN] " .. message, ...))
end

local function getAnimationAsset(moveName, animationKey)
	if typeof(animationKey) ~= "string" or animationKey == "" then
		logWarn("animation missing or failed to load move=%s detail=invalid_animation_key", tostring(moveName))
		return nil, nil
	end

	local animation, descriptor = AnimationResolver.GetAnimation(animationKey, {
		Context = string.format("Gomu.%s", tostring(moveName)),
	})
	if animation then
		return animation, descriptor
	end

	logWarn(
		"animation missing or failed to load move=%s key=%s detail=%s",
		tostring(moveName),
		tostring(animationKey),
		tostring(descriptor and descriptor.Source or "missing_registry_animation")
	)
	return nil, descriptor
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

local function normalizeMarkerNames(value, fallback)
	local names = {}
	local seen = {}

	local function append(markerName)
		if typeof(markerName) ~= "string" or markerName == "" or seen[markerName] then
			return
		end

		seen[markerName] = true
		table.insert(names, markerName)
	end

	if typeof(value) == "string" then
		append(value)
	elseif type(value) == "table" then
		for _, markerName in ipairs(value) do
			append(markerName)
		end
	end

	if #names == 0 and type(fallback) == "table" then
		for _, markerName in ipairs(fallback) do
			append(markerName)
		end
	end

	return names
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

local function connectMarkerSignals(track, markerNames, callback)
	local connections = {}
	if typeof(track) ~= "Instance" or type(markerNames) ~= "table" or typeof(callback) ~= "function" then
		return connections
	end

	for _, markerName in ipairs(markerNames) do
		local ok, connectionOrError = pcall(function()
			return track:GetMarkerReachedSignal(markerName):Connect(function()
				callback(markerName)
			end)
		end)
		if ok and connectionOrError then
			table.insert(connections, connectionOrError)
		else
			logWarn(
				"marker connect failed move=%s marker=%s detail=%s",
				RUBBER_LAUNCH_MOVE_NAME,
				tostring(markerName),
				tostring(connectionOrError)
			)
		end
	end

	return connections
end

local function playAnimation(character, moveName, animationConfig, defaultAnimationKey)
	local resolvedConfig = type(animationConfig) == "table" and animationConfig or {}
	local animationKey = resolvedConfig.AnimationKey or defaultAnimationKey
	local animation, descriptor = getAnimationAsset(moveName, animationKey)
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
		SOURCE_LABEL
	)
	if not track then
		logWarn(
			"animation missing or failed to load move=%s detail=%s",
			tostring(moveName),
			tostring(loadFailure)
		)
		return nil
	end

	local fadeTime = math.max(0, tonumber(resolvedConfig.FadeTime) or DEFAULT_FADE_TIME)
	local playbackSpeed = tonumber(resolvedConfig.PlaybackSpeed) or 1
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = resolvedConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)
	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		string.format("Gomu.%s", tostring(moveName)),
		descriptor and descriptor.AnimationId,
		string.format(
			"key=%s fade=%.3f speed=%.3f looped=%s",
			tostring(animationKey),
			fadeTime,
			playbackSpeed,
			tostring(track.Looped)
		)
	)

	logInfo("move=%s animation play asset=%s", tostring(moveName), tostring(animationKey))

	return {
		MoveName = moveName,
		AssetName = animationKey,
		AnimationKey = animationKey,
		AnimationId = descriptor and descriptor.AnimationId,
		MarkerName = resolvedConfig.ReleaseMarker,
		ReleaseMarkers = normalizeMarkerNames(resolvedConfig.ReleaseMarkers or resolvedConfig.ReleaseMarker),
		ReleaseTime = tonumber(resolvedConfig.ReleaseTime),
		ReleaseFallbackTime = math.max(
			0,
			tonumber(resolvedConfig.ReleaseFallbackTime) or DEFAULT_RELEASE_FALLBACK_TIME
		),
		ArmStretchMarkers = normalizeMarkerNames(resolvedConfig.ArmStretchMarkers, DEFAULT_ARM_STRETCH_MARKERS),
		ArmRestoreMarkers = normalizeMarkerNames(resolvedConfig.ArmRestoreMarkers, DEFAULT_ARM_RESTORE_MARKERS),
		ArmStretchSize = resolvedConfig.ArmStretchSize or DEFAULT_ARM_STRETCH_SIZE,
		ArmRestoreFallbackTime = math.max(
			0,
			tonumber(resolvedConfig.ArmRestoreFallbackTime) or DEFAULT_ARM_RESTORE_FALLBACK_TIME
		),
		Track = track,
		StopFadeTime = math.max(0, tonumber(resolvedConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME),
	}
end

function GomuAnimationController.PlayRubberLaunchAnimation(character, animationConfig)
	return playAnimation(character, RUBBER_LAUNCH_MOVE_NAME, animationConfig, RUBBER_LAUNCH_DEFAULT_ANIMATION_KEY)
end

function GomuAnimationController.BindRubberLaunchArmEvents(animationState, callbacks)
	if type(animationState) ~= "table" or typeof(animationState.Track) ~= "Instance" then
		return function() end
	end

	callbacks = type(callbacks) == "table" and callbacks or {}
	local track = animationState.Track
	local connections = {}
	local stretched = false
	local restored = false

	local function emitRestore(reason, markerName)
		if restored then
			return
		end

		restored = true
		if typeof(callbacks.OnRestore) == "function" then
			callbacks.OnRestore({
				Reason = reason,
				MarkerName = markerName,
				ArmStretchSize = animationState.ArmStretchSize,
			})
		end
		disconnectAll(connections)
	end

	local function emitStretch(markerName)
		if stretched or restored then
			return
		end

		stretched = true
		logInfo("move=%s arm stretch marker=%s", tostring(animationState.MoveName), tostring(markerName))
		if typeof(callbacks.OnStretch) == "function" then
			callbacks.OnStretch({
				MarkerName = markerName,
				ArmStretchSize = animationState.ArmStretchSize,
				ArmRestoreFallbackTime = animationState.ArmRestoreFallbackTime,
			})
		end

		local fallbackTime = math.max(0, tonumber(animationState.ArmRestoreFallbackTime) or DEFAULT_ARM_RESTORE_FALLBACK_TIME)
		if fallbackTime > 0 then
			task.delay(fallbackTime, function()
				if stretched and not restored then
					emitRestore("timeout")
				end
			end)
		end
	end

	for _, connection in ipairs(connectMarkerSignals(track, animationState.ArmStretchMarkers, emitStretch)) do
		table.insert(connections, connection)
	end
	for _, connection in ipairs(connectMarkerSignals(track, animationState.ArmRestoreMarkers, function(markerName)
		logInfo("move=%s arm restore marker=%s", tostring(animationState.MoveName), tostring(markerName))
		emitRestore("marker", markerName)
	end)) do
		table.insert(connections, connection)
	end
	table.insert(connections, track.Stopped:Connect(function()
		emitRestore("animation_stopped")
	end))

	return function()
		emitRestore("cleanup")
	end
end

function GomuAnimationController.WaitForRubberLaunchRelease(animationState)
	if type(animationState) ~= "table" or typeof(animationState.Track) ~= "Instance" then
		return false
	end

	local track = animationState.Track
	local releaseTime = tonumber(animationState.ReleaseTime)
	if releaseTime then
		local timeoutAt = os.clock() + math.max(0, releaseTime)
		while track.IsPlaying and os.clock() < timeoutAt do
			task.wait()
		end
		return false
	end

	local fallbackTime = math.max(0, tonumber(animationState.ReleaseFallbackTime) or DEFAULT_RELEASE_FALLBACK_TIME)
	local markerNames = type(animationState.ReleaseMarkers) == "table" and animationState.ReleaseMarkers or {}
	if #markerNames == 0 and typeof(animationState.MarkerName) == "string" and animationState.MarkerName ~= "" then
		markerNames = { animationState.MarkerName }
	end

	if #markerNames == 0 then
		local timeoutAt = os.clock() + fallbackTime
		while track.IsPlaying and os.clock() < timeoutAt do
			task.wait()
		end
		return false
	end

	local markerReached = false
	local connections = {}
	for _, markerName in ipairs(markerNames) do
		local ok, err = pcall(function()
			local connection = track:GetMarkerReachedSignal(markerName):Connect(function()
				if markerReached then
					return
				end

				markerReached = true
				logInfo("move=%s marker reached marker=%s", tostring(animationState.MoveName), markerName)
			end)
			table.insert(connections, connection)
		end)
		if not ok then
			logWarn(
				"marker connect failed move=%s marker=%s detail=%s",
				tostring(animationState.MoveName),
				tostring(markerName),
				tostring(err)
			)
		end
	end

	local timeoutAt = os.clock() + fallbackTime
	while not markerReached and track.IsPlaying and os.clock() < timeoutAt do
		task.wait()
	end

	disconnectAll(connections)

	if not markerReached and fallbackTime > 0 then
		logInfo(
			"move=%s marker fallback markers=%s delay=%.3f",
			tostring(animationState.MoveName),
			table.concat(markerNames, ","),
			fallbackTime
		)
	end

	return markerReached
end

function GomuAnimationController.StopAnimation(animationState, reason)
	if type(animationState) ~= "table" or typeof(animationState.Track) ~= "Instance" then
		return false
	end

	pcall(function()
		animationState.Track:Stop(animationState.StopFadeTime)
	end)
	logInfo("move=%s animation stop reason=%s", tostring(animationState.MoveName), tostring(reason))
	return true
end

return GomuAnimationController
