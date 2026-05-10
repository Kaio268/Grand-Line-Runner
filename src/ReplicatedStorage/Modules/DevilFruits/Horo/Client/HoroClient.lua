local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local SettingsAudioController = require(Modules:WaitForChild("SettingsAudioController"))
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))

local HoroClient = {}
HoroClient.__index = HoroClient

local FRUIT_NAME = "Horo Horo no Mi"
local ABILITY_NAME = "GhostProjection"
local REMOTE_NAME = "HoroProjectionAction"
local WORLD_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local GHOSTS_FOLDER_NAME = "HoroGhosts"
local DEFAULT_DURATION = 5
local DEFAULT_GHOST_SPEED = 15
local DEFAULT_CARRY_SPEED = 8
local DEFAULT_MAX_DISTANCE_FROM_BODY = 68
local DEFAULT_REWARD_INTERACT_RADIUS = 12
local DEFAULT_HAZARD_PROBE_RADIUS = 3.4
local DEFAULT_CLIENT_HAZARD_REPORT_THROTTLE = 0.12
local PICKUP_INPUT_THROTTLE = 0.18
local MAX_PROJECTION_MOVE_SPEED = 200
local DEFAULT_FLIGHT_HORIZONTAL_RESPONSE = 10
local DEFAULT_FLIGHT_VERTICAL_HOLD_RESPONSE = 12
local DEFAULT_FLIGHT_DT = 1 / 60
local MIN_FLIGHT_DT = 1 / 240
local MAX_FLIGHT_DT = 1 / 15
local HOVER_HEIGHT_SNAP_TOLERANCE = 0.2
local REMOTE_WAIT_TIMEOUT = 2
local GHOST_LOOKUP_TIMEOUT = 2
local GHOST_LOOKUP_POLL_INTERVAL = 0.05
local GAMEPAD_THUMBSTICK_DEADZONE = 0.12
local MIN_CAMERA_AXIS_MAGNITUDE = 0.001
local MIN_MOVE_INPUT_MAGNITUDE = 0.01
local SERVER_RESOLVE_GRACE_DURATION = 0.45
local MIN_PROJECTION_DURATION = 0.5
local MAX_PROJECTION_DURATION = 12
local MIN_GHOST_SPEED = 2
local MIN_CARRY_SPEED = 1
local MIN_MAX_DISTANCE_FROM_BODY = 8
local MAX_MAX_DISTANCE_FROM_BODY = 180
local MIN_REWARD_INTERACT_RADIUS = 3
local MAX_REWARD_INTERACT_RADIUS = 24
local MIN_HAZARD_PROBE_RADIUS = 1
local MAX_HAZARD_PROBE_RADIUS = 10
local MIN_REMOTE_THROTTLE = 0.05
local MAX_REMOTE_THROTTLE = 1
local ACTION_TRY_PICKUP = "TryPickup"
local ACTION_INTERRUPT = "Interrupt"
local ACTION_BODY_HAZARD = "BodyHazard"
local SOUND_ACTIVATE = "Activate"
local SOUND_MOVE_LOOP = "MoveLoop"
local SOUND_RETURN = "Return"
local SOUND_CLEANUP_FALLBACK_SECONDS = 8
local DEBUG_SOUND = true
local DEBUG_TRACE = RunService:IsStudio()
local HORO_HINT_SIZE = UDim2.fromOffset(150, 30)
local HORO_HINT_HEAD_OFFSET = Vector3.new(0, 2.25, 0)
local HORO_HINT_ROOT_OFFSET = Vector3.new(0, 4.9, 0)

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function horoClientTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[HORO CLIENT TRACE] " .. tostring(message), ...))
end

local function horoSoundLog(message, ...)
	if not DEBUG_SOUND then
		return
	end

	print(string.format("[HORO SOUND] " .. tostring(message), ...))
end

local function horoSoundWarn(message, ...)
	if not DEBUG_SOUND then
		return
	end

	warn(string.format("[HORO SOUND] " .. tostring(message), ...))
end

local function getSoundPlayingState(sound)
	if not sound then
		return "<nil>"
	end

	local ok, isPlaying = pcall(function()
		return sound.IsPlaying
	end)
	if ok then
		return tostring(isPlaying)
	end

	return "<unreadable>"
end

local function logSoundDiagnostics(stage, soundName, sound)
	if not DEBUG_SOUND then
		return
	end
	if not sound then
		horoSoundWarn("%s sound=%s missing_instance", tostring(stage), tostring(soundName))
		return
	end

	local soundId = tostring(sound.SoundId or "")
	local volume = tonumber(sound.Volume) or 0
	if soundId == "" then
		horoSoundWarn("%s sound=%s path=%s issue=missing_sound_id", tostring(stage), tostring(soundName), formatInstancePath(sound))
	end
	if volume <= 0 then
		horoSoundWarn(
			"%s sound=%s path=%s issue=zero_or_negative_volume volume=%.3f",
			tostring(stage),
			tostring(soundName),
			formatInstancePath(sound),
			volume
		)
	end
	if not sound.Parent then
		horoSoundWarn("%s sound=%s path=%s issue=nil_parent", tostring(stage), tostring(soundName), formatInstancePath(sound))
	end

	horoSoundLog(
		"%s sound=%s path=%s parent=%s soundId=%s volume=%.3f looped=%s timeLength=%.3f isPlaying=%s",
		tostring(stage),
		tostring(soundName),
		formatInstancePath(sound),
		formatInstancePath(sound.Parent),
		soundId,
		volume,
		tostring(sound.Looped),
		tonumber(sound.TimeLength) or 0,
		getSoundPlayingState(sound)
	)
end

local function getPlayerCarrySummary(player)
	if not player then
		return "player=<nil>"
	end

	return string.format(
		"attrMajor=%s attrMajorName=%s attrBrainrot=%s horoActive=%s horoProjectionId=%s horoCarrying=%s",
		tostring(player:GetAttribute("CarriedMajorRewardType")),
		tostring(player:GetAttribute("CarriedMajorRewardDisplayName")),
		tostring(player:GetAttribute("CarriedBrainrot")),
		tostring(player:GetAttribute("HoroProjectionActive")),
		tostring(player:GetAttribute("HoroProjectionId")),
		tostring(player:GetAttribute("HoroProjectionCarryingReward"))
	)
end

local function clampNumber(value, fallback, minValue, maxValue)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return fallback
	end

	return math.clamp(numericValue, minValue, maxValue)
end

local function getAbilityConfig()
	return DevilFruitConfig.GetAbility(FRUIT_NAME, ABILITY_NAME) or {}
end

local function getActionRemote()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
		or ReplicatedStorage:WaitForChild("Remotes", REMOTE_WAIT_TIMEOUT)
	if not remotesFolder then
		return nil
	end

	return remotesFolder:FindFirstChild(REMOTE_NAME) or remotesFolder:WaitForChild(REMOTE_NAME, REMOTE_WAIT_TIMEOUT)
end

local function getGhostRoot(ghostModel)
	if not ghostModel then
		return nil
	end

	return ghostModel:FindFirstChild("HumanoidRootPart") or ghostModel.PrimaryPart or ghostModel:FindFirstChildWhichIsA("BasePart", true)
end

local function getCharacterHumanoid(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getCharacterRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function resolveGhostProjectionSoundFolder()
	local node = ReplicatedStorage
	for _, segment in ipairs({ "Assets", "Sounds", "DevilFruits", "Horo", "GhostProjection" }) do
		if not node then
			horoSoundWarn("path_segment_skipped segment=%s issue=parent_nil", tostring(segment))
			return nil
		end

		local child = node:FindFirstChild(segment)
		if not child then
			horoSoundWarn(
				"path_segment_missing segment=%s parent=%s",
				tostring(segment),
				formatInstancePath(node)
			)
			return nil
		end

		horoSoundLog("path_segment_found segment=%s path=%s", tostring(segment), formatInstancePath(child))
		node = child
	end

	return node
end

local function getGhostProjectionSoundTemplate(soundName)
	local soundFolder = resolveGhostProjectionSoundFolder()
	horoSoundLog("resolve_folder sound=%s folder=%s", tostring(soundName), formatInstancePath(soundFolder))
	if not soundFolder then
		horoSoundWarn(
			"resolve_folder_failed sound=%s issue=ghost_projection_sound_folder_missing expected=ReplicatedStorage.Assets.Sounds.DevilFruits.Horo.GhostProjection",
			tostring(soundName)
		)
		return nil
	end

	local soundTemplate = soundFolder and soundFolder:FindFirstChild(soundName)
	if soundTemplate and soundTemplate:IsA("Sound") then
		logSoundDiagnostics("template_found", soundName, soundTemplate)
		return soundTemplate
	end

	if soundTemplate then
		horoSoundWarn(
			"template_invalid sound=%s path=%s class=%s",
			tostring(soundName),
			formatInstancePath(soundTemplate),
			tostring(soundTemplate.ClassName)
		)
	else
		horoSoundWarn(
			"template_missing sound=%s folder=%s childCount=%d",
			tostring(soundName),
			formatInstancePath(soundFolder),
			#soundFolder:GetChildren()
		)
	end

	return nil
end

local function getSoundCleanupDelay(sound)
	local timeLength = tonumber(sound and sound.TimeLength) or 0
	if timeLength > 0 then
		return timeLength + 1
	end

	return SOUND_CLEANUP_FALLBACK_SECONDS
end

local function playProjectionOneShot(soundName, parent)
	if not (parent and parent.Parent) then
		horoSoundWarn(
			"one_shot_skipped sound=%s issue=invalid_parent parent=%s",
			tostring(soundName),
			formatInstancePath(parent)
		)
		return nil
	end

	local soundTemplate = getGhostProjectionSoundTemplate(soundName)
	if not soundTemplate then
		horoSoundWarn("one_shot_skipped sound=%s issue=template_missing", tostring(soundName))
		return nil
	end

	horoSoundLog("one_shot_clone_begin sound=%s parent=%s", tostring(soundName), formatInstancePath(parent))
	local sound = soundTemplate:Clone()
	sound.Looped = false
	sound.Parent = parent
	logSoundDiagnostics("one_shot_parented", soundName, sound)
	SettingsAudioController.TrackSound(sound)
	logSoundDiagnostics("one_shot_tracked", soundName, sound)
	sound:Play()
	logSoundDiagnostics("one_shot_play_called", soundName, sound)

	task.delay(0.1, function()
		if sound.Parent then
			logSoundDiagnostics("one_shot_post_play_0_1s", soundName, sound)
		else
			horoSoundWarn("one_shot_post_play_0_1s sound=%s issue=sound_destroyed_or_unparented", tostring(soundName))
		end
	end)

	local endedConnection
	endedConnection = sound.Ended:Connect(function()
		if endedConnection then
			endedConnection:Disconnect()
			endedConnection = nil
		end
		if sound.Parent then
			sound:Destroy()
		end
	end)

	Debris:AddItem(sound, getSoundCleanupDelay(sound))
	return sound
end

local function startProjectionMoveLoop(state)
	if not (state and state.GhostRoot and state.GhostRoot.Parent) then
		horoSoundWarn(
			"move_loop_skipped issue=invalid_ghost_root projectionId=%s ghostRoot=%s",
			tostring(state and state.ProjectionId),
			formatInstancePath(state and state.GhostRoot)
		)
		return nil
	end

	local soundTemplate = getGhostProjectionSoundTemplate(SOUND_MOVE_LOOP)
	if not soundTemplate then
		horoSoundWarn("move_loop_skipped issue=template_missing projectionId=%s", tostring(state.ProjectionId))
		return nil
	end

	horoSoundLog(
		"move_loop_clone_begin projectionId=%s parent=%s",
		tostring(state.ProjectionId),
		formatInstancePath(state.GhostRoot)
	)
	local sound = soundTemplate:Clone()
	sound.Looped = true
	sound.Parent = state.GhostRoot
	logSoundDiagnostics("move_loop_parented", SOUND_MOVE_LOOP, sound)
	SettingsAudioController.TrackSound(sound)
	logSoundDiagnostics("move_loop_tracked", SOUND_MOVE_LOOP, sound)
	sound:Play()
	state.MoveLoopSound = sound
	horoSoundLog(
		"move_loop_stored projectionId=%s sound=%s forcedLooped=%s",
		tostring(state.ProjectionId),
		formatInstancePath(sound),
		tostring(sound.Looped)
	)
	logSoundDiagnostics("move_loop_play_called", SOUND_MOVE_LOOP, sound)

	task.delay(0.1, function()
		if state.MoveLoopSound == sound and sound.Parent then
			logSoundDiagnostics("move_loop_post_play_0_1s", SOUND_MOVE_LOOP, sound)
		else
			horoSoundWarn(
				"move_loop_post_play_0_1s projectionId=%s issue=sound_no_longer_active parent=%s stored=%s",
				tostring(state.ProjectionId),
				formatInstancePath(sound.Parent),
				tostring(state.MoveLoopSound == sound)
			)
		end
	end)
	return sound
end

local function stopProjectionMoveLoop(state)
	local sound = state and state.MoveLoopSound
	if state then
		state.MoveLoopSound = nil
	end
	if not sound then
		horoSoundLog("move_loop_stop_skipped projectionId=%s issue=no_sound_reference", tostring(state and state.ProjectionId))
		return
	end

	if sound.Parent then
		logSoundDiagnostics("move_loop_stop_begin", SOUND_MOVE_LOOP, sound)
		pcall(function()
			sound:Stop()
		end)
		logSoundDiagnostics("move_loop_stopped", SOUND_MOVE_LOOP, sound)
		sound:Destroy()
		horoSoundLog("move_loop_destroyed projectionId=%s", tostring(state and state.ProjectionId))
	else
		horoSoundWarn("move_loop_stop_skipped projectionId=%s issue=sound_parent_missing", tostring(state and state.ProjectionId))
	end
end

local function getProjectionReturnSoundParent(player, state)
	if state and state.GhostRoot and state.GhostRoot.Parent then
		return state.GhostRoot
	end

	return getCharacterRoot(player) or (state and state.BodyRoot and state.BodyRoot.Parent and state.BodyRoot) or nil
end

local function shouldPlayReturnSound(payload)
	local phase = payload and payload.Phase
	return phase == "Resolve" or phase == "Interrupted"
end

local function findGhostModel(payload)
	local projectionId = payload and payload.ProjectionId
	local effectsFolder = Workspace:FindFirstChild(WORLD_EFFECTS_FOLDER_NAME)
		or Workspace:WaitForChild(WORLD_EFFECTS_FOLDER_NAME, GHOST_LOOKUP_TIMEOUT)
	local ghostsFolder = effectsFolder
		and (effectsFolder:FindFirstChild(GHOSTS_FOLDER_NAME)
			or effectsFolder:WaitForChild(GHOSTS_FOLDER_NAME, GHOST_LOOKUP_TIMEOUT))
	if not ghostsFolder then
		return nil
	end

	if typeof(projectionId) == "string" and projectionId ~= "" then
		local deadline = os.clock() + GHOST_LOOKUP_TIMEOUT
		while os.clock() <= deadline do
			for _, child in ipairs(ghostsFolder:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("ProjectionId") == projectionId then
					return child
				end
			end
			task.wait(GHOST_LOOKUP_POLL_INTERVAL)
		end
		return nil
	end

	local ghostName = payload and payload.GhostName
	if typeof(ghostName) ~= "string" or ghostName == "" then
		return nil
	end

	return ghostsFolder
		and (ghostsFolder:FindFirstChild(ghostName) or ghostsFolder:WaitForChild(ghostName, REMOTE_WAIT_TIMEOUT))
		or nil
end

local function findProjectionBody(payload)
	local projectionId = payload and payload.ProjectionId
	if typeof(projectionId) ~= "string" or projectionId == "" then
		return nil
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("HoroProjectionBody") == true
			and descendant:GetAttribute("ProjectionId") == projectionId
		then
			return descendant
		end
	end

	return nil
end

local function buildOverlapParams(exclusions)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions or {}
	return params
end

local function isDangerousHazardPart(part, state)
	if not part or not part:IsA("BasePart") then
		return false
	end
	if state and state.GhostModel and part:IsDescendantOf(state.GhostModel) then
		return false
	end
	if state and state.BodyCharacter and part:IsDescendantOf(state.BodyCharacter) then
		return false
	end

	local hazardRoot = HazardUtils.GetHazardInfo(part)
	if hazardRoot ~= nil then
		return true
	end

	local refs = MapResolver.GetRefs()
	local clientWaves = refs and refs.ClientWaves
	return clientWaves ~= nil and part:IsDescendantOf(clientWaves)
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections or {}) do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
end

local function getGhostHintAnchor(rootPart, ghostModel)
	local head = ghostModel and ghostModel:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head, HORO_HINT_HEAD_OFFSET
	end

	return rootPart, HORO_HINT_ROOT_OFFSET
end

local function createGhostHint(rootPart, ghostModel)
	local anchorPart, studsOffset = getGhostHintAnchor(rootPart, ghostModel)
	if not anchorPart then
		return nil, nil
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "HoroGhostHint"
	gui.Adornee = anchorPart
	gui.Size = HORO_HINT_SIZE
	gui.StudsOffset = studsOffset
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.Parent = anchorPart

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "E  GRAB"
	label.TextColor3 = Color3.fromRGB(238, 251, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 60, 78)
	label.TextStrokeTransparency = 0.15
	label.TextSize = 16
	label.Parent = gui

	return gui, label
end

local function normalizeMoveVector(moveVector)
	if typeof(moveVector) ~= "Vector3" then
		return Vector3.zero
	end

	local flatMove = Vector3.new(moveVector.X, 0, moveVector.Z)
	if flatMove.Magnitude > 1 then
		return flatMove.Unit
	end

	return flatMove
end

local function getPlayerControls(player)
	local playerScripts = player and player:FindFirstChild("PlayerScripts")
	local playerModuleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript then
		return nil
	end

	local ok, playerModule = pcall(require, playerModuleScript)
	if not ok or type(playerModule) ~= "table" or typeof(playerModule.GetControls) ~= "function" then
		return nil
	end

	local controlsOk, controls = pcall(function()
		return playerModule:GetControls()
	end)
	if controlsOk then
		return controls
	end

	return nil
end

local function getControlMoveVector(controls)
	if type(controls) ~= "table" or typeof(controls.GetMoveVector) ~= "function" then
		return Vector3.zero
	end

	local ok, moveVector = pcall(function()
		return controls:GetMoveVector()
	end)
	if ok then
		return normalizeMoveVector(moveVector)
	end

	return Vector3.zero
end

local function getKeyboardMoveVector()
	if UserInputService:GetFocusedTextBox() then
		return Vector3.zero
	end

	local x = 0
	local z = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		z += 1
	end

	return normalizeMoveVector(Vector3.new(x, 0, z))
end

local function getGamepadMoveVector()
	for _, input in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local position = input.Position
			local x = if math.abs(position.X) > GAMEPAD_THUMBSTICK_DEADZONE then position.X else 0
			local z = if math.abs(position.Y) > GAMEPAD_THUMBSTICK_DEADZONE then -position.Y else 0
			return normalizeMoveVector(Vector3.new(x, 0, z))
		end
	end

	return Vector3.zero
end

local function getManualMoveVector()
	return normalizeMoveVector(getKeyboardMoveVector() + getGamepadMoveVector())
end

local function getVerticalInputAxis()
	if UserInputService:GetFocusedTextBox() then
		return 0
	end

	local verticalAxis = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		verticalAxis += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	then
		verticalAxis -= 1
	end

	return verticalAxis
end

local function getPlanarVector(vector)
	if typeof(vector) ~= "Vector3" then
		return Vector3.zero
	end

	return Vector3.new(vector.X, 0, vector.Z)
end

local function getFlightDeltaTime(dt)
	local numericDt = tonumber(dt)
	if numericDt == nil then
		return DEFAULT_FLIGHT_DT
	end

	return math.clamp(numericDt, MIN_FLIGHT_DT, MAX_FLIGHT_DT)
end

local function getWorldMoveVector(localMoveVector, camera)
	local moveVector = normalizeMoveVector(localMoveVector)
	if moveVector.Magnitude <= 0 then
		return Vector3.zero
	end

	local cameraCFrame = camera and camera.CFrame or CFrame.new()
	local lookVector = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
	local rightVector = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z)
	if lookVector.Magnitude <= MIN_CAMERA_AXIS_MAGNITUDE then
		lookVector = Vector3.new(0, 0, -1)
	else
		lookVector = lookVector.Unit
	end
	if rightVector.Magnitude <= MIN_CAMERA_AXIS_MAGNITUDE then
		rightVector = Vector3.new(1, 0, 0)
	else
		rightVector = rightVector.Unit
	end

	return normalizeMoveVector((rightVector * moveVector.X) + (lookVector * -moveVector.Z))
end

function HoroClient.Create(config)
	config = config or {}

	local self = setmetatable({}, HoroClient)
	self.player = config.player or Players.LocalPlayer
	self.activeState = nil
	return self
end

function HoroClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return nil
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function HoroClient:BuildRequestPayload(abilityName, _abilityEntry, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return nil
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function HoroClient:SendAction(actionName, payload)
	local remote = getActionRemote()
	if not remote or not remote:IsA("RemoteEvent") then
		horoClientTrace(
			"sendAction failed action=%s projectionId=%s reason=missing_remote",
			tostring(actionName),
			tostring(self.activeState and self.activeState.ProjectionId)
		)
		return false
	end

	horoClientTrace(
		"sendAction action=%s projectionId=%s carryAttrs={%s}",
		tostring(actionName),
		tostring((payload and payload.ProjectionId) or (self.activeState and self.activeState.ProjectionId)),
		getPlayerCarrySummary(self.player)
	)
	remote:FireServer(actionName, payload or {})
	return true
end

function HoroClient:StyleLocalGhost(ghostModel, localTransparency)
	for _, descendant in ipairs(ghostModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.LocalTransparencyModifier = math.clamp(localTransparency or 0.2, 0, 0.95)
		end
	end
end

function HoroClient:HookGhostTouches(state)
	local function hookPart(part)
		if not part:IsA("BasePart") then
			return
		end

		state.Connections[#state.Connections + 1] = part.Touched:Connect(function(hit)
			if isDangerousHazardPart(hit, state) then
				self:InterruptProjection("hazard_touch")
			end
		end)
	end

	for _, descendant in ipairs(state.GhostModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hookPart(descendant)
		end
	end

	state.Connections[#state.Connections + 1] = state.GhostModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			hookPart(descendant)
		end
	end)
end

function HoroClient:HookBodyTouches(state)
	if not state.BodyRoot then
		return
	end

	state.Connections[#state.Connections + 1] = state.BodyRoot.Touched:Connect(function(hit)
		if isDangerousHazardPart(hit, state) then
			self:ReportBodyHazard("body_hazard_touch")
		end
	end)
end

function HoroClient:StartLocalProjection(payload)
	self:StopLocalProjection(nil, false)

	local abilityConfig = getAbilityConfig()
	local ghostModel = findGhostModel(payload)
	local ghostRoot = getGhostRoot(ghostModel)
	if not ghostModel or not ghostRoot then
		horoClientTrace(
			"startLocalProjection failed projectionId=%s reason=ghost_missing ghostModel=%s ghostRoot=%s",
			tostring(payload and payload.ProjectionId),
			formatInstancePath(ghostModel),
			formatInstancePath(ghostRoot)
		)
		return false
	end

	local camera = Workspace.CurrentCamera
	local ghostHumanoid = ghostModel:FindFirstChildOfClass("Humanoid")
	local bodyCharacter = findProjectionBody(payload)
	local bodyRoot = bodyCharacter and bodyCharacter:FindFirstChild("HumanoidRootPart") or nil

	local state = {
		GhostModel = ghostModel,
		GhostRoot = ghostRoot,
		GhostHumanoid = ghostHumanoid,
		BodyCharacter = bodyCharacter,
		BodyRoot = bodyRoot,
		ProjectionId = payload and payload.ProjectionId,
		EndTime = tonumber(payload and payload.EndTime) or (Workspace:GetServerTimeNow() + DEFAULT_DURATION),
		Duration = clampNumber(
			payload and payload.Duration,
			DEFAULT_DURATION,
			MIN_PROJECTION_DURATION,
			MAX_PROJECTION_DURATION
		),
		GhostSpeed = clampNumber(
			payload and payload.GhostSpeed,
			abilityConfig.GhostSpeed or DEFAULT_GHOST_SPEED,
			MIN_GHOST_SPEED,
			MAX_PROJECTION_MOVE_SPEED
		),
		CarrySpeed = clampNumber(
			payload and payload.CarrySpeed,
			abilityConfig.CarrySpeed or DEFAULT_CARRY_SPEED,
			MIN_CARRY_SPEED,
			MAX_PROJECTION_MOVE_SPEED
		),
		MaxDistanceFromBody = clampNumber(
			payload and payload.MaxDistanceFromBody,
			abilityConfig.MaxDistanceFromBody or DEFAULT_MAX_DISTANCE_FROM_BODY,
			MIN_MAX_DISTANCE_FROM_BODY,
			MAX_MAX_DISTANCE_FROM_BODY
		),
		RewardInteractRadius = clampNumber(
			payload and payload.RewardInteractRadius,
			abilityConfig.RewardInteractRadius or DEFAULT_REWARD_INTERACT_RADIUS,
			MIN_REWARD_INTERACT_RADIUS,
			MAX_REWARD_INTERACT_RADIUS
		),
		HazardProbeRadius = clampNumber(
			payload and payload.HazardProbeRadius,
			abilityConfig.HazardProbeRadius or DEFAULT_HAZARD_PROBE_RADIUS,
			MIN_HAZARD_PROBE_RADIUS,
			MAX_HAZARD_PROBE_RADIUS
		),
		ClientHazardReportThrottle = clampNumber(
			abilityConfig.ClientHazardReportThrottle,
			DEFAULT_CLIENT_HAZARD_REPORT_THROTTLE,
			MIN_REMOTE_THROTTLE,
			MAX_REMOTE_THROTTLE
		),
		NextHazardProbeAt = 0,
		NextBodyHazardProbeAt = 0,
		NextPickupAt = 0,
		NextInterruptAt = 0,
		NextBodyInterruptAt = 0,
		GhostY = ghostRoot.Position.Y,
		HoverHeight = ghostRoot.Position.Y,
		FlightHorizontalResponse = DEFAULT_FLIGHT_HORIZONTAL_RESPONSE,
		FlightVerticalHoldResponse = DEFAULT_FLIGHT_VERTICAL_HOLD_RESPONSE,
		Connections = {},
		Camera = camera,
		PreviousCameraSubject = camera and camera.CameraSubject or nil,
		PreviousCameraType = camera and camera.CameraType or nil,
		Controls = getPlayerControls(self.player),
	}
	self.activeState = state
	playProjectionOneShot(SOUND_ACTIVATE, ghostRoot)
	startProjectionMoveLoop(state)
	horoClientTrace(
		"startLocalProjection projectionId=%s ghost=%s ghostPos=%s body=%s bodyPos=%s endTime=%s duration=%s carryAttrs={%s}",
		tostring(state.ProjectionId),
		formatInstancePath(ghostModel),
		formatVector3(ghostRoot.Position),
		formatInstancePath(bodyCharacter),
		formatVector3(bodyRoot and bodyRoot.Position or nil),
		tostring(state.EndTime),
		tostring(state.Duration),
		getPlayerCarrySummary(self.player)
	)

	self:StyleLocalGhost(ghostModel, clampNumber(abilityConfig.GhostLocalTransparency, 0.2, 0, 0.95))
	state.HintGui, state.HintLabel = createGhostHint(ghostRoot, ghostModel)

	if camera then
		camera.CameraSubject = ghostHumanoid or ghostRoot
		camera.CameraType = Enum.CameraType.Custom
	end

	self:HookGhostTouches(state)
	self:HookBodyTouches(state)
	state.Connections[#state.Connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.activeState ~= state then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			self:TryPickup()
		end
	end)

	return true
end

function HoroClient:StopLocalProjection(_payload, keepServerGhost)
	local state = self.activeState
	if not state then
		return
	end
	horoClientTrace(
		"stopLocalProjection projectionId=%s payloadPhase=%s resolveReason=%s keepServerGhost=%s carryAttrs={%s}",
		tostring(state.ProjectionId),
		tostring(_payload and _payload.Phase),
		tostring(_payload and _payload.ResolveReason),
		tostring(keepServerGhost == true),
		getPlayerCarrySummary(self.player)
	)

	self.activeState = nil
	stopProjectionMoveLoop(state)
	if shouldPlayReturnSound(_payload) then
		local returnParent = getProjectionReturnSoundParent(self.player, state)
		horoSoundLog(
			"return_attempt projectionId=%s phase=%s parent=%s",
			tostring(state.ProjectionId),
			tostring(_payload and _payload.Phase),
			formatInstancePath(returnParent)
		)
		playProjectionOneShot(SOUND_RETURN, returnParent)
	else
		horoSoundLog(
			"return_skipped projectionId=%s phase=%s",
			tostring(state.ProjectionId),
			tostring(_payload and _payload.Phase)
		)
	end
	disconnectAll(state.Connections)
	if state.GhostHumanoid and state.GhostHumanoid.Parent then
		state.GhostHumanoid:Move(Vector3.zero, false)
	end

	if state.Camera then
		if state.PreviousCameraType then
			state.Camera.CameraType = state.PreviousCameraType
		end
		local currentHumanoid = getCharacterHumanoid(self.player)
		if currentHumanoid and currentHumanoid ~= state.GhostHumanoid then
			state.Camera.CameraSubject = currentHumanoid
		elseif state.PreviousCameraSubject
			and state.PreviousCameraSubject.Parent
			and state.PreviousCameraSubject ~= state.GhostHumanoid
		then
			state.Camera.CameraSubject = state.PreviousCameraSubject
		else
			if currentHumanoid then
				state.Camera.CameraSubject = currentHumanoid
			end
		end
	end

	if state.HintGui and state.HintGui.Parent then
		state.HintGui:Destroy()
	end

	if not keepServerGhost and state.GhostModel and state.GhostModel.Parent == nil then
		state.GhostModel = nil
	end
end

function HoroClient:IsCarryingReward()
	return self.player:GetAttribute("HoroProjectionCarryingReward") == true
		or self.player:GetAttribute("CarriedMajorRewardType") ~= nil
		or self.player:GetAttribute("CarriedBrainrot") ~= nil
end

function HoroClient:GetCurrentSpeed(state)
	local attributeName = if self:IsCarryingReward() then "HoroProjectionCarrySpeed" else "HoroProjectionGhostSpeed"
	local projectedSpeed = self.player:GetAttribute(attributeName)
	if typeof(projectedSpeed) == "number" and projectedSpeed > 0 then
		return projectedSpeed
	end

	if self:IsCarryingReward() then
		return state.CarrySpeed
	end

	return state.GhostSpeed
end

function HoroClient:GetCurrentVerticalSpeed(state)
	return self:GetCurrentSpeed(state)
end

function HoroClient:GetTargetVerticalVelocity(state, _dt)
	local ghostRoot = state and state.GhostRoot
	if not ghostRoot or not ghostRoot.Parent then
		return 0
	end

	local verticalSpeed = self:GetCurrentVerticalSpeed(state)
	local verticalAxis = getVerticalInputAxis()
	if verticalAxis ~= 0 then
		state.HoverHeight = ghostRoot.Position.Y
		return verticalAxis * verticalSpeed
	end

	if typeof(state.HoverHeight) ~= "number" then
		state.HoverHeight = ghostRoot.Position.Y
	end

	local heightDelta = state.HoverHeight - ghostRoot.Position.Y
	if math.abs(heightDelta) <= HOVER_HEIGHT_SNAP_TOLERANCE then
		return 0
	end

	local holdResponse = math.max(1, tonumber(state.FlightVerticalHoldResponse) or DEFAULT_FLIGHT_VERTICAL_HOLD_RESPONSE)
	local correctionVelocity = heightDelta * holdResponse
	local maxCorrectionSpeed = math.max(1, verticalSpeed)
	return math.clamp(correctionVelocity, -maxCorrectionSpeed, maxCorrectionSpeed)
end

function HoroClient:DriveGhostMovement(state, dt)
	if not state.GhostHumanoid or not state.GhostHumanoid.Parent or not state.GhostRoot or not state.GhostRoot.Parent then
		return
	end

	local flightDt = getFlightDeltaTime(dt)
	local currentSpeed = self:GetCurrentSpeed(state)
	local desiredPlanarDirection = Vector3.zero
	local moveVector = Vector3.zero
	if not UserInputService:GetFocusedTextBox() then
		moveVector = getControlMoveVector(state.Controls)
		if moveVector.Magnitude <= MIN_MOVE_INPUT_MAGNITUDE then
			moveVector = getManualMoveVector()
		end
	end

	desiredPlanarDirection = getWorldMoveVector(moveVector, Workspace.CurrentCamera or state.Camera)
	local desiredPlanarVelocity = desiredPlanarDirection * currentSpeed
	local currentVelocity = state.GhostRoot.AssemblyLinearVelocity
	local currentPlanarVelocity = getPlanarVector(currentVelocity)
	local horizontalResponse = math.max(1, tonumber(state.FlightHorizontalResponse) or DEFAULT_FLIGHT_HORIZONTAL_RESPONSE)
	local blendAlpha = math.clamp(horizontalResponse * flightDt, 0, 1)
	local nextPlanarVelocity = currentPlanarVelocity:Lerp(desiredPlanarVelocity, blendAlpha)
	local nextVerticalVelocity = self:GetTargetVerticalVelocity(state, flightDt)

	state.GhostHumanoid.WalkSpeed = currentSpeed
	state.GhostHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	state.GhostHumanoid:Move(desiredPlanarDirection, false)
	state.GhostRoot.AssemblyLinearVelocity = Vector3.new(
		nextPlanarVelocity.X,
		nextVerticalVelocity,
		nextPlanarVelocity.Z
	)
end

function HoroClient:TryPickup()
	local state = self.activeState
	if not state then
		return false
	end

	local now = os.clock()
	if now < state.NextPickupAt then
		horoClientTrace(
			"tryPickup throttled projectionId=%s nextPickupIn=%.3f",
			tostring(state.ProjectionId),
			math.max(0, state.NextPickupAt - now)
		)
		return false
	end
	state.NextPickupAt = now + PICKUP_INPUT_THROTTLE
	horoClientTrace(
		"tryPickup begin projectionId=%s ghostPos=%s carryAttrs={%s}",
		tostring(state.ProjectionId),
		formatVector3(state.GhostRoot and state.GhostRoot.Position or nil),
		getPlayerCarrySummary(self.player)
	)

	return self:SendAction(ACTION_TRY_PICKUP, {
		ProjectionId = state.ProjectionId,
	})
end

function HoroClient:CanActivateOnLocalCooldown(abilityName)
	local canBypass = abilityName == ABILITY_NAME and self.activeState ~= nil
	horoClientTrace(
		"localCooldownRoute ability=%s activeProjection=%s projectionId=%s decision=%s route=%s carryAttrs={%s}",
		tostring(abilityName),
		tostring(self.activeState ~= nil),
		tostring(self.activeState and self.activeState.ProjectionId),
		tostring(canBypass),
		if canBypass then "manual_cancel_request" else "normal_cast_blocked",
		getPlayerCarrySummary(self.player)
	)
	return canBypass
end

function HoroClient:InterruptProjection(reason)
	local state = self.activeState
	if not state then
		return false
	end
	if state.PendingInterrupt then
		return false
	end

	local now = os.clock()
	if now < state.NextInterruptAt then
		return false
	end
	state.NextInterruptAt = now + state.ClientHazardReportThrottle
	state.PendingInterrupt = true

	self:SendAction(ACTION_INTERRUPT, {
		ProjectionId = state.ProjectionId,
		Reason = reason or "client_hazard",
	})
	return true
end

function HoroClient:ReportBodyHazard(reason)
	local state = self.activeState
	if not state then
		return false
	end
	if state.PendingBodyHazard then
		return false
	end

	local now = os.clock()
	if now < state.NextBodyInterruptAt then
		return false
	end
	state.NextBodyInterruptAt = now + state.ClientHazardReportThrottle
	state.PendingBodyHazard = true

	self:SendAction(ACTION_BODY_HAZARD, {
		ProjectionId = state.ProjectionId,
		Reason = reason or "body_hazard",
	})
	return true
end

function HoroClient:ProbeGhostHazards(state, now)
	if now < state.NextHazardProbeAt then
		return
	end
	state.NextHazardProbeAt = now + state.ClientHazardReportThrottle

	local parts = Workspace:GetPartBoundsInRadius(
		state.GhostRoot.Position,
		state.HazardProbeRadius,
		buildOverlapParams({
			state.GhostModel,
			state.BodyCharacter,
		})
	)
	for _, part in ipairs(parts) do
		if isDangerousHazardPart(part, state) then
			self:InterruptProjection("hazard_overlap")
			return
		end
	end
end

function HoroClient:ProbeBodyHazards(state, now)
	if now < state.NextBodyHazardProbeAt then
		return
	end
	state.NextBodyHazardProbeAt = now + state.ClientHazardReportThrottle

	state.BodyRoot = state.BodyRoot and state.BodyRoot.Parent and state.BodyRoot
		or (state.BodyCharacter and state.BodyCharacter:FindFirstChild("HumanoidRootPart"))
	if not state.BodyRoot then
		return
	end

	local parts = Workspace:GetPartsInPart(state.BodyRoot, buildOverlapParams({
		state.BodyCharacter,
		state.GhostModel,
	}))
	for _, part in ipairs(parts) do
		if isDangerousHazardPart(part, state) then
			self:ReportBodyHazard("body_hazard_overlap")
			return
		end
	end
end

function HoroClient:UpdateHint(state)
	if not state.HintLabel then
		return
	end

	local remaining = math.max(0, state.EndTime - Workspace:GetServerTimeNow())
	local carried = self:IsCarryingReward()
	state.HintLabel.Text = string.format("%s  %.1fs", if carried then "CARRYING" else "E  GRAB", remaining)
	state.HintLabel.TextColor3 = if carried then Color3.fromRGB(196, 255, 220) else Color3.fromRGB(238, 251, 255)
end

function HoroClient:Update(dt)
	local state = self.activeState
	if not state then
		return
	end
	if not state.GhostRoot or not state.GhostRoot.Parent then
		self:StopLocalProjection(nil, false)
		return
	end

	local serverNow = Workspace:GetServerTimeNow()
	if serverNow > state.EndTime + SERVER_RESOLVE_GRACE_DURATION then
		self:StopLocalProjection(nil, true)
		return
	end

	self:DriveGhostMovement(state, dt)
	local now = os.clock()
	self:ProbeGhostHazards(state, now)
	self:ProbeBodyHazards(state, now)
	self:UpdateHint(state)
end

function HoroClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= ABILITY_NAME then
		return false
	end

	local phase = payload and payload.Phase or "Start"
	horoClientTrace(
		"handleEffect phase=%s projectionId=%s resolveReason=%s targetPlayer=%s localActiveProjection=%s carryAttrs={%s}",
		tostring(phase),
		tostring(payload and payload.ProjectionId),
		tostring(payload and payload.ResolveReason),
		targetPlayer and targetPlayer.Name or "<nil>",
		tostring(self.activeState and self.activeState.ProjectionId),
		getPlayerCarrySummary(self.player)
	)
	if targetPlayer ~= self.player then
		return phase == "Start" or phase == "Resolve" or phase == "Interrupted" or phase == "Rejected" or phase == "Ignored"
	end

	if phase == "Start" then
		return self:StartLocalProjection(payload)
	elseif phase == "Resolve" or phase == "Interrupted" then
		self:StopLocalProjection(payload, false)
		return true
	elseif phase == "Rejected" then
		if self.activeState and payload and payload.ResolveReason == "already_active" then
			return true
		end
		self:StopLocalProjection(payload, false)
		return true
	elseif phase == "Ignored" then
		return true
	end

	return false
end

function HoroClient:HandleStateEvent()
	return false
end

function HoroClient:HandleUnequipped()
	self:StopLocalProjection(nil, true)
	return false
end

function HoroClient:HandleCharacterRemoving()
	self:StopLocalProjection(nil, true)
end

function HoroClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer == self.player then
		self:StopLocalProjection(nil, true)
	end
end

return HoroClient
