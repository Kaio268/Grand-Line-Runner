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

local SpiritClient = {}
SpiritClient.__index = SpiritClient

local FRUIT_NAME = "Spirit Fruit"
local ABILITY_NAME = "GhostProjection"
local REMOTE_NAME = "HoroProjectionAction"
local WORLD_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local GHOSTS_FOLDER_NAME = "HoroGhosts"
local DEFAULT_DURATION = 8
local DEFAULT_GHOST_SPEED = 15
local DEFAULT_CARRY_SPEED = 8
local DEFAULT_GHOST_HAZARD_IMMUNE = true
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
local GHOST_HAZARD_INTERRUPT_REASONS = {
	client_hazard = true,
	hazard_overlap = true,
	hazard_touch = true,
	wave_touch = true,
}
local SOUND_ACTIVATE = "Activate"
local SOUND_MOVE_LOOP = "MoveLoop"
local SOUND_RETURN = "Return"
local SOUND_CLEANUP_FALLBACK_SECONDS = 8
local HORO_HINT_SIZE = UDim2.fromOffset(150, 30)
local HORO_HINT_HEAD_OFFSET = Vector3.new(0, 2.25, 0)
local HORO_HINT_ROOT_OFFSET = Vector3.new(0, 4.9, 0)
local DEBUG_SOUND = RunService:IsStudio()
local DEBUG_TRACE = RunService:IsStudio()
local SOUND_AUDIO_KEY_BY_NAME = {
	[SOUND_ACTIVATE] = "ActivateSoundId",
	[SOUND_MOVE_LOOP] = "MoveLoopSoundId",
	[SOUND_RETURN] = "ReturnSoundId",
}
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local HORO_GHOST_VFX_FRUIT_FOLDER_NAME = "Horo"
local HORO_GHOST_VFX_TEMPLATE_NAME = "R6"
local HORO_GHOST_VFX_CLONE_NAME = "HoroGhostProjectionAuthoredVfx"
local HORO_GHOST_VFX_FOLDER_NAME = "HoroGhostProjectionClientVfx"
local HORO_GHOST_VISIBLE_VFX_PART_ATTRIBUTE = "VisibleVfxPart"
local HORO_GHOST_PERSISTENT_EMITTER_ATTRIBUTE = "HoroPersistentProjectionEmitter"
local HORO_GHOST_PERSISTENT_EMITTER_FALLBACK_RATE = 18
local HORO_GHOST_PERSISTENT_EMITTER_MIN_LIFETIME = 0.75
local HORO_GHOST_PERSISTENT_EMITTER_NAMES = {
	"Fading Tint",
	"Ghostly Energy",
	"Swirling Basic Energy",
}
local HORO_GHOST_PERSISTENT_EMITTER_PROFILE = {
	["Fading Tint"] = {
		Rate = 42,
		Lifetime = NumberRange.new(1.25, 1.8),
		Speed = NumberRange.new(0.2, 0.9),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.38),
			NumberSequenceKeypoint.new(0.72, 0.5),
			NumberSequenceKeypoint.new(1, 0.88),
		}),
	},
	["Ghostly Energy"] = {
		Rate = 52,
		Lifetime = NumberRange.new(1, 1.65),
		Speed = NumberRange.new(0.25, 1.35),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.28),
			NumberSequenceKeypoint.new(0.7, 0.44),
			NumberSequenceKeypoint.new(1, 0.86),
		}),
	},
	["Swirling Basic Energy"] = {
		Rate = 36,
		Lifetime = NumberRange.new(1.15, 1.85),
		Speed = NumberRange.new(0.3, 1.75),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.32),
			NumberSequenceKeypoint.new(0.72, 0.48),
			NumberSequenceKeypoint.new(1, 0.9),
		}),
	},
}
local HORO_GHOST_VFX_ATTACH_TIMEOUT = 2
local HORO_GHOST_VFX_END_GRACE_DURATION = 0.75
local HORO_GHOST_VFX_WARNED = {}

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

local function resolveGhostHazardImmune(payload, abilityConfig)
	if payload and typeof(payload.GhostHazardImmune) == "boolean" then
		return payload.GhostHazardImmune
	end
	if abilityConfig.GhostHazardImmune == false then
		return false
	end

	return DEFAULT_GHOST_HAZARD_IMMUNE
end

local function isGhostHazardImmune(state)
	return state and state.GhostHazardImmune == true
end

local function isGhostHazardInterruptReason(reason)
	local normalizedReason = tostring(reason or "client_hazard")
	return GHOST_HAZARD_INTERRUPT_REASONS[normalizedReason] == true
end

local function getCarriedCrewMemberName(player)
	if not player then
		return nil
	end

	local carried = player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE)
	if typeof(carried) == "string" and carried ~= "" then
		return carried
	end

	return nil
end

local function hasCarriedCrewMember(player)
	return getCarriedCrewMemberName(player) ~= nil
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
		horoSoundWarn(
			"%s sound=%s path=%s issue=missing_sound_id",
			tostring(stage),
			tostring(soundName),
			formatInstancePath(sound)
		)
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
		horoSoundWarn(
			"%s sound=%s path=%s issue=nil_parent",
			tostring(stage),
			tostring(soundName),
			formatInstancePath(sound)
		)
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
		"attrMajor=%s attrMajorName=%s attrCrewMember=%s horoActive=%s horoProjectionId=%s horoCarrying=%s",
		tostring(player:GetAttribute("CarriedMajorRewardType")),
		tostring(player:GetAttribute("CarriedMajorRewardDisplayName")),
		tostring(player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE)),
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

	return ghostModel:FindFirstChild("HumanoidRootPart")
		or ghostModel.PrimaryPart
		or ghostModel:FindFirstChildWhichIsA("BasePart", true)
end

local function getCharacterHumanoid(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getCharacterRoot(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function normalizeSoundId(value)
	if typeof(value) == "number" then
		return "rbxassetid://" .. tostring(math.floor(value))
	end

	if typeof(value) ~= "string" or value == "" then
		return nil
	end

	if string.find(value, "rbxassetid://", 1, true) == 1 then
		return value
	end

	if tonumber(value) ~= nil then
		return "rbxassetid://" .. value
	end

	return value
end

local function getGhostProjectionAudioConfig()
	local abilityConfig = getAbilityConfig()
	local audioConfig = abilityConfig and abilityConfig.Audio
	if type(audioConfig) ~= "table" then
		return nil
	end

	return audioConfig
end

local function createGhostProjectionSound(soundName, looped)
	local audioKey = SOUND_AUDIO_KEY_BY_NAME[soundName]
	if not audioKey then
		horoSoundWarn("sound_config_missing sound=%s issue=unknown_sound", tostring(soundName))
		return nil
	end

	local audioConfig = getGhostProjectionAudioConfig()
	if not audioConfig then
		horoSoundWarn("sound_config_missing sound=%s issue=missing_audio_table", tostring(soundName))
		return nil
	end

	local soundId = normalizeSoundId(audioConfig[audioKey])
	if not soundId then
		horoSoundWarn(
			"sound_config_missing sound=%s key=%s issue=missing_sound_id",
			tostring(soundName),
			tostring(audioKey)
		)
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = tostring(soundName)
	sound.SoundId = soundId
	sound.Looped = looped == true
	sound.Volume = math.max(0, tonumber(audioConfig.Volume) or 1)

	local rollOffMaxDistance = tonumber(audioConfig.RollOffMaxDistance)
	if rollOffMaxDistance then
		sound.RollOffMaxDistance = math.max(1, rollOffMaxDistance)
	end

	return sound
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

	local sound = createGhostProjectionSound(soundName, false)
	if not sound then
		horoSoundWarn("one_shot_skipped sound=%s issue=sound_config_missing", tostring(soundName))
		return nil
	end

	horoSoundLog("one_shot_create_begin sound=%s parent=%s", tostring(soundName), formatInstancePath(parent))
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

	local sound = createGhostProjectionSound(SOUND_MOVE_LOOP, true)
	if not sound then
		horoSoundWarn("move_loop_skipped issue=sound_config_missing projectionId=%s", tostring(state.ProjectionId))
		return nil
	end

	horoSoundLog(
		"move_loop_create_begin projectionId=%s parent=%s",
		tostring(state.ProjectionId),
		formatInstancePath(state.GhostRoot)
	)
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
		horoSoundLog(
			"move_loop_stop_skipped projectionId=%s issue=no_sound_reference",
			tostring(state and state.ProjectionId)
		)
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
		horoSoundWarn(
			"move_loop_stop_skipped projectionId=%s issue=sound_parent_missing",
			tostring(state and state.ProjectionId)
		)
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
		and (
			effectsFolder:FindFirstChild(GHOSTS_FOLDER_NAME)
			or effectsFolder:WaitForChild(GHOSTS_FOLDER_NAME, GHOST_LOOKUP_TIMEOUT)
		)
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

local function warnHoroGhostVfxOnce(key, message, ...)
	if HORO_GHOST_VFX_WARNED[key] then
		return
	end
	HORO_GHOST_VFX_WARNED[key] = true
	warn(string.format("[HORO VFX] " .. tostring(message), ...))
end

local function getGhostProjectionVfxKey(projectionIdOrPayload)
	if typeof(projectionIdOrPayload) == "string" and projectionIdOrPayload ~= "" then
		return projectionIdOrPayload
	end
	if type(projectionIdOrPayload) ~= "table" then
		return nil
	end

	local projectionId = projectionIdOrPayload.ProjectionId
	if typeof(projectionId) == "string" and projectionId ~= "" then
		return projectionId
	end

	local ghostName = projectionIdOrPayload.GhostName
	if typeof(ghostName) == "string" and ghostName ~= "" then
		return ghostName
	end

	return nil
end

local function getHoroGhostVfxTemplate()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assetsFolder and assetsFolder:FindFirstChild("VFX")
	local horoFolder = vfxFolder and vfxFolder:FindFirstChild(HORO_GHOST_VFX_FRUIT_FOLDER_NAME)
	local template = horoFolder and horoFolder:FindFirstChild(HORO_GHOST_VFX_TEMPLATE_NAME)

	if not template then
		warnHoroGhostVfxOnce("missing_template", "missing asset ReplicatedStorage.Assets.VFX.Horo.R6")
		return nil
	end
	if not template:IsA("Model") then
		warnHoroGhostVfxOnce(
			"invalid_template",
			"expected ReplicatedStorage.Assets.VFX.Horo.R6 to be a Model, got %s",
			template.ClassName
		)
		return nil
	end

	return template
end

local function getGhostsFolder()
	local effectsFolder = Workspace:FindFirstChild(WORLD_EFFECTS_FOLDER_NAME)
	return effectsFolder and effectsFolder:FindFirstChild(GHOSTS_FOLDER_NAME) or nil
end

local function getHoroGhostVfxFolder()
	local folder = Workspace:FindFirstChild(HORO_GHOST_VFX_FOLDER_NAME)
	if folder then
		return folder
	end

	folder = Instance.new("Folder")
	folder.Name = HORO_GHOST_VFX_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function findGhostProjectionModel(payload)
	local projectionId = payload and payload.ProjectionId
	local ghostName = payload and payload.GhostName
	local deadline = os.clock() + HORO_GHOST_VFX_ATTACH_TIMEOUT

	while os.clock() <= deadline do
		local ghostsFolder = getGhostsFolder()
		if ghostsFolder then
			if typeof(projectionId) == "string" and projectionId ~= "" then
				for _, child in ipairs(ghostsFolder:GetChildren()) do
					if child:IsA("Model") and child:GetAttribute("ProjectionId") == projectionId then
						return child
					end
				end
			end

			if typeof(ghostName) == "string" and ghostName ~= "" then
				local namedGhost = ghostsFolder:FindFirstChild(ghostName)
				if namedGhost and namedGhost:IsA("Model") then
					return namedGhost
				end
			end
		end

		task.wait(GHOST_LOOKUP_POLL_INTERVAL)
	end

	return nil
end

local function getHoroGhostVfxRoot(vfxModel)
	if not vfxModel then
		return nil
	end

	local primaryPart = vfxModel.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") and primaryPart:IsDescendantOf(vfxModel) then
		return primaryPart
	end

	local namedRoot = vfxModel:FindFirstChild("HumanoidRootPart", true)
	if namedRoot and namedRoot:IsA("BasePart") then
		return namedRoot
	end

	return vfxModel:FindFirstChildWhichIsA("BasePart", true)
end

local function shouldRenderHoroGhostVfxInstance(instance)
	if instance:GetAttribute(HORO_GHOST_VISIBLE_VFX_PART_ATTRIBUTE) == true then
		return true
	end

	local ancestor = instance.Parent
	while ancestor do
		if ancestor:IsA("BasePart") then
			return ancestor:GetAttribute(HORO_GHOST_VISIBLE_VFX_PART_ATTRIBUTE) == true
		end
		ancestor = ancestor.Parent
	end

	return false
end

local function isHoroGhostVfxMovementInstance(instance)
	return instance:IsA("Humanoid")
		or instance:IsA("AnimationController")
		or instance:IsA("Animator")
		or instance:IsA("JointInstance")
		or instance:IsA("Constraint")
		or instance:IsA("WeldConstraint")
		or instance:IsA("BodyMover")
		or instance:IsA("VectorForce")
		or instance:IsA("LinearVelocity")
		or instance:IsA("AngularVelocity")
		or instance:IsA("AlignPosition")
		or instance:IsA("AlignOrientation")
end

local function sanitizeHoroGhostVfxClone(vfxModel)
	for _, descendant in ipairs(vfxModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local shouldRenderPart = shouldRenderHoroGhostVfxInstance(descendant)
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.CastShadow = false
			if not shouldRenderPart then
				descendant.Transparency = 1
				descendant.LocalTransparencyModifier = 1
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			if not shouldRenderHoroGhostVfxInstance(descendant) then
				descendant.Transparency = 1
			end
		elseif descendant:IsA("BaseScript") or isHoroGhostVfxMovementInstance(descendant) then
			descendant:Destroy()
		end
	end
end

local function getHoroPersistentEmitterAttachment(vfxModel)
	local fxPart = vfxModel and vfxModel:FindFirstChild("FX")
	if not fxPart then
		return nil
	end

	return fxPart:FindFirstChild("Attachment") or fxPart:FindFirstChildOfClass("Attachment")
end

local function configureHoroPersistentGhostEmitters(vfxModel)
	local attachment = getHoroPersistentEmitterAttachment(vfxModel)
	if not attachment then
		warnHoroGhostVfxOnce("missing_persistent_attachment", "missing Horo R6.FX.Attachment persistent emitters")
		return
	end

	for _, emitterName in ipairs(HORO_GHOST_PERSISTENT_EMITTER_NAMES) do
		local emitter = attachment:FindFirstChild(emitterName)
		if not (emitter and emitter:IsA("ParticleEmitter")) then
			warnHoroGhostVfxOnce(
				"missing_persistent_emitter_" .. emitterName,
				"missing Horo persistent ParticleEmitter %s under R6.FX.Attachment",
				emitterName
			)
			continue
		end

		horoClientTrace(
			"horoPersistentEmitter before name=%s enabled=%s rate=%s lifetime=%s speed=%s spread=%s transparency=%s timeScale=%s lockedToPart=%s drag=%s acceleration=%s zOffset=%s rotSpeed=%s emissionDirection=%s lightEmission=%s texture=%s emitCount=%s burstCount=%s persistent=%s continuous=%s",
			emitter.Name,
			tostring(emitter.Enabled),
			tostring(emitter.Rate),
			tostring(emitter.Lifetime),
			tostring(emitter.Speed),
			tostring(emitter.SpreadAngle),
			tostring(emitter.Transparency),
			tostring(emitter.TimeScale),
			tostring(emitter.LockedToPart),
			tostring(emitter.Drag),
			tostring(emitter.Acceleration),
			tostring(emitter.ZOffset),
			tostring(emitter.RotSpeed),
			tostring(emitter.EmissionDirection),
			tostring(emitter.LightEmission),
			tostring(emitter.Texture),
			tostring(emitter:GetAttribute("EmitCount")),
			tostring(emitter:GetAttribute("BurstCount")),
			tostring(emitter:GetAttribute("Persistent")),
			tostring(emitter:GetAttribute("Continuous"))
		)

		local profile = HORO_GHOST_PERSISTENT_EMITTER_PROFILE[emitterName]
		emitter:SetAttribute(HORO_GHOST_PERSISTENT_EMITTER_ATTRIBUTE, true)
		emitter.Enabled = true
		emitter.Rate = math.max(emitter.Rate, profile and profile.Rate or HORO_GHOST_PERSISTENT_EMITTER_FALLBACK_RATE)
		emitter.Lifetime = (profile and profile.Lifetime) or NumberRange.new(
			HORO_GHOST_PERSISTENT_EMITTER_MIN_LIFETIME,
			math.max(HORO_GHOST_PERSISTENT_EMITTER_MIN_LIFETIME, emitter.Lifetime.Max)
		)
		if profile and profile.Speed then
			emitter.Speed = profile.Speed
		end
		if profile and profile.Transparency then
			emitter.Transparency = profile.Transparency
		end
		emitter.LockedToPart = false
		if emitter.TimeScale <= 0 then
			emitter.TimeScale = 1
		end

		horoClientTrace(
			"horoPersistentEmitter after name=%s enabled=%s rate=%s lifetime=%s speed=%s transparency=%s timeScale=%s lockedToPart=%s",
			emitter.Name,
			tostring(emitter.Enabled),
			tostring(emitter.Rate),
			tostring(emitter.Lifetime),
			tostring(emitter.Speed),
			tostring(emitter.Transparency),
			tostring(emitter.TimeScale),
			tostring(emitter.LockedToPart)
		)
	end
end

local function enableHoroGhostVfxVisuals(vfxModel)
	for _, descendant in ipairs(vfxModel:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = true
			local emitCount = tonumber(descendant:GetAttribute("EmitCount"))
				or tonumber(descendant:GetAttribute("BurstCount"))
				or 0
			local emitterRate = tonumber(descendant.Rate) or 0
			local persistentEmitter = descendant:GetAttribute(HORO_GHOST_PERSISTENT_EMITTER_ATTRIBUTE) == true
			if not persistentEmitter and emitterRate <= 0 and emitCount > 0 then
				pcall(function()
					descendant:Emit(emitCount)
				end)
			end
		elseif descendant:IsA("Beam") or descendant:IsA("Trail") then
			if descendant.Attachment0 and descendant.Attachment1 then
				descendant.Enabled = true
			end
		elseif descendant:IsA("PointLight") or descendant:IsA("SpotLight") or descendant:IsA("SurfaceLight") then
			descendant.Enabled = true
		end
	end
end

local function disableHoroGhostVfxVisuals(vfxModel)
	for _, descendant in ipairs(vfxModel:GetDescendants()) do
		if
			descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("PointLight")
			or descendant:IsA("SpotLight")
			or descendant:IsA("SurfaceLight")
		then
			descendant.Enabled = false
		end
	end
end

local function disconnectHoroGhostVfxConnections(connections)
	for _, connection in ipairs(connections or {}) do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
end

local cleanupGhostProjectionVfx

local function cleanupGhostProjectionVfxForPlayer(controller, player)
	local states = controller and controller.ghostProjectionVfxByProjectionId
	if not states or not player then
		return
	end

	for projectionId, state in pairs(states) do
		if state.TargetPlayer == player then
			cleanupGhostProjectionVfx(controller, projectionId)
		end
	end
end

cleanupGhostProjectionVfx = function(controller, projectionIdOrPayload)
	local states = controller and controller.ghostProjectionVfxByProjectionId
	if not states then
		return
	end

	local projectionId = getGhostProjectionVfxKey(projectionIdOrPayload)
	if not projectionId then
		return
	end

	local state = states[projectionId]
	if not state then
		return
	end

	states[projectionId] = nil
	state.Destroyed = true
	if typeof(state.TimeoutThread) == "thread" then
		pcall(function()
			task.cancel(state.TimeoutThread)
		end)
	end
	disconnectHoroGhostVfxConnections(state.Connections)
	if state.Clone and state.Clone.Parent then
		disableHoroGhostVfxVisuals(state.Clone)
		state.Clone:Destroy()
	end
end

local function cleanupAllGhostProjectionVfx(controller)
	local states = controller and controller.ghostProjectionVfxByProjectionId
	if not states then
		return
	end

	for projectionId in pairs(states) do
		cleanupGhostProjectionVfx(controller, projectionId)
	end
end

local function scheduleGhostProjectionVfxTimeout(controller, state, payload)
	local endTime = tonumber(payload and payload.EndTime)
	if not endTime then
		return
	end

	local delaySeconds = endTime - Workspace:GetServerTimeNow() + HORO_GHOST_VFX_END_GRACE_DURATION
	if delaySeconds <= 0 then
		return
	end

	if typeof(state.TimeoutThread) == "thread" then
		pcall(function()
			task.cancel(state.TimeoutThread)
		end)
		state.TimeoutThread = nil
	end

	state.TimeoutThread = task.delay(delaySeconds, function()
		local states = controller and controller.ghostProjectionVfxByProjectionId
		if states and states[state.ProjectionId] == state and not state.Destroyed then
			cleanupGhostProjectionVfx(controller, state.ProjectionId)
		end
	end)
end

local function attachGhostProjectionVfx(controller, payload, targetPlayer)
	local states = controller and controller.ghostProjectionVfxByProjectionId
	if not states then
		return false
	end

	local projectionId = getGhostProjectionVfxKey(payload)
	if not projectionId then
		warnHoroGhostVfxOnce("missing_projection_id", "cannot attach ghost projection VFX without ProjectionId")
		return false
	end

	local existingState = states[projectionId]
	if existingState and not existingState.Destroyed then
		existingState.TargetPlayer = targetPlayer
		scheduleGhostProjectionVfxTimeout(controller, existingState, payload)
		return true
	end

	local state = {
		ProjectionId = projectionId,
		TargetPlayer = targetPlayer,
		Connections = {},
		Destroyed = false,
		Attaching = true,
		Attached = false,
	}
	states[projectionId] = state

	task.spawn(function()
		local ghostModel = findGhostProjectionModel(payload)
		if state.Destroyed or states[projectionId] ~= state then
			return
		end
		if not ghostModel then
			warnHoroGhostVfxOnce(
				"missing_ghost_" .. projectionId,
				"could not find replicated ghost for projectionId=%s",
				tostring(projectionId)
			)
			cleanupGhostProjectionVfx(controller, projectionId)
			return
		end

		local ghostRoot = getGhostRoot(ghostModel)
		if not ghostRoot then
			warnHoroGhostVfxOnce(
				"missing_ghost_root_" .. projectionId,
				"could not find ghost root for projectionId=%s",
				tostring(projectionId)
			)
			cleanupGhostProjectionVfx(controller, projectionId)
			return
		end

		local template = getHoroGhostVfxTemplate()
		if not template then
			cleanupGhostProjectionVfx(controller, projectionId)
			return
		end

		local clone = template:Clone()
		clone.Name = HORO_GHOST_VFX_CLONE_NAME
		sanitizeHoroGhostVfxClone(clone)
		configureHoroPersistentGhostEmitters(clone)

		local vfxRoot = getHoroGhostVfxRoot(clone)
		if not vfxRoot then
			clone:Destroy()
			warnHoroGhostVfxOnce(
				"missing_vfx_root",
				"could not find a BasePart root inside ReplicatedStorage.Assets.VFX.Horo.R6"
			)
			cleanupGhostProjectionVfx(controller, projectionId)
			return
		end

		clone.PrimaryPart = vfxRoot
		clone:PivotTo(ghostRoot.CFrame)
		clone.Parent = getHoroGhostVfxFolder()

		state.Clone = clone
		state.GhostModel = ghostModel
		state.GhostRoot = ghostRoot
		state.Attaching = false
		state.Attached = true
		state.Connections[#state.Connections + 1] = RunService.RenderStepped:Connect(function()
			if state.Destroyed then
				return
			end
			if not clone.Parent or not ghostRoot.Parent then
				cleanupGhostProjectionVfx(controller, projectionId)
				return
			end

			clone:PivotTo(ghostRoot.CFrame)
		end)
		state.Connections[#state.Connections + 1] = ghostModel.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				cleanupGhostProjectionVfx(controller, projectionId)
			end
		end)
		state.Connections[#state.Connections + 1] = ghostRoot.AncestryChanged:Connect(function(_, parent)
			if parent == nil then
				cleanupGhostProjectionVfx(controller, projectionId)
			end
		end)

		enableHoroGhostVfxVisuals(clone)
		scheduleGhostProjectionVfxTimeout(controller, state, payload)
		horoClientTrace(
			"attached authored ghost vfx projectionId=%s ghost=%s clone=%s",
			tostring(projectionId),
			formatInstancePath(ghostModel),
			formatInstancePath(clone)
		)
	end)

	return true
end

local function findProjectionBody(payload)
	local projectionId = payload and payload.ProjectionId
	if typeof(projectionId) ~= "string" or projectionId == "" then
		return nil
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if
			descendant:IsA("Model")
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
	if
		UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
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

function SpiritClient.Create(config)
	config = config or {}

	local self = setmetatable({}, SpiritClient)
	self.player = config.player or Players.LocalPlayer
	self.activeState = nil
	self.ghostProjectionVfxByProjectionId = {}
	return self
end

function SpiritClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return nil
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function SpiritClient:BuildRequestPayload(abilityName, _abilityEntry, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return nil
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function SpiritClient:SendAction(actionName, payload)
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

function SpiritClient:StyleLocalGhost(ghostModel, localTransparency)
	for _, descendant in ipairs(ghostModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.LocalTransparencyModifier = math.clamp(localTransparency or 0.2, 0, 0.95)
		end
	end
end

function SpiritClient:HookGhostTouches(state)
	if isGhostHazardImmune(state) then
		return
	end

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

function SpiritClient:HookBodyTouches(state)
	if not state.BodyRoot then
		return
	end

	state.Connections[#state.Connections + 1] = state.BodyRoot.Touched:Connect(function(hit)
		if isDangerousHazardPart(hit, state) then
			self:ReportBodyHazard("body_hazard_touch")
		end
	end)
end

function SpiritClient:StartLocalProjection(payload)
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
		GhostHazardImmune = resolveGhostHazardImmune(payload, abilityConfig),
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

function SpiritClient:StopLocalProjection(_payload, keepServerGhost)
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
	cleanupGhostProjectionVfx(self, state.ProjectionId)
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
		elseif
			state.PreviousCameraSubject
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

function SpiritClient:IsCarryingReward()
	return self.player:GetAttribute("HoroProjectionCarryingReward") == true
		or self.player:GetAttribute("CarriedMajorRewardType") ~= nil
		or hasCarriedCrewMember(self.player)
end

function SpiritClient:GetCurrentSpeed(state)
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

function SpiritClient:GetCurrentVerticalSpeed(state)
	return self:GetCurrentSpeed(state)
end

function SpiritClient:GetTargetVerticalVelocity(state, _dt)
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

	local holdResponse =
		math.max(1, tonumber(state.FlightVerticalHoldResponse) or DEFAULT_FLIGHT_VERTICAL_HOLD_RESPONSE)
	local correctionVelocity = heightDelta * holdResponse
	local maxCorrectionSpeed = math.max(1, verticalSpeed)
	return math.clamp(correctionVelocity, -maxCorrectionSpeed, maxCorrectionSpeed)
end

function SpiritClient:DriveGhostMovement(state, dt)
	if
		not state.GhostHumanoid
		or not state.GhostHumanoid.Parent
		or not state.GhostRoot
		or not state.GhostRoot.Parent
	then
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
	local horizontalResponse =
		math.max(1, tonumber(state.FlightHorizontalResponse) or DEFAULT_FLIGHT_HORIZONTAL_RESPONSE)
	local blendAlpha = math.clamp(horizontalResponse * flightDt, 0, 1)
	local nextPlanarVelocity = currentPlanarVelocity:Lerp(desiredPlanarVelocity, blendAlpha)
	local nextVerticalVelocity = self:GetTargetVerticalVelocity(state, flightDt)

	state.GhostHumanoid.WalkSpeed = currentSpeed
	state.GhostHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	state.GhostHumanoid:Move(desiredPlanarDirection, false)
	state.GhostRoot.AssemblyLinearVelocity =
		Vector3.new(nextPlanarVelocity.X, nextVerticalVelocity, nextPlanarVelocity.Z)
end

function SpiritClient:TryPickup()
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

function SpiritClient:CanActivateOnLocalCooldown(abilityName)
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

function SpiritClient:InterruptProjection(reason)
	local state = self.activeState
	if not state then
		return false
	end
	if isGhostHazardImmune(state) and isGhostHazardInterruptReason(reason) then
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

function SpiritClient:ReportBodyHazard(reason)
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

function SpiritClient:ProbeGhostHazards(state, now)
	if isGhostHazardImmune(state) then
		return
	end

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

function SpiritClient:ProbeBodyHazards(state, now)
	if now < state.NextBodyHazardProbeAt then
		return
	end
	state.NextBodyHazardProbeAt = now + state.ClientHazardReportThrottle

	state.BodyRoot = state.BodyRoot and state.BodyRoot.Parent and state.BodyRoot
		or (state.BodyCharacter and state.BodyCharacter:FindFirstChild("HumanoidRootPart"))
	if not state.BodyRoot then
		return
	end

	local parts = Workspace:GetPartsInPart(
		state.BodyRoot,
		buildOverlapParams({
			state.BodyCharacter,
			state.GhostModel,
		})
	)
	for _, part in ipairs(parts) do
		if isDangerousHazardPart(part, state) then
			self:ReportBodyHazard("body_hazard_overlap")
			return
		end
	end
end

function SpiritClient:UpdateHint(state)
	if not state.HintLabel then
		return
	end

	local remaining = math.max(0, state.EndTime - Workspace:GetServerTimeNow())
	local carried = self:IsCarryingReward()
	state.HintLabel.Text = string.format("%s  %.1fs", if carried then "CARRYING" else "E  GRAB", remaining)
	state.HintLabel.TextColor3 = if carried then Color3.fromRGB(196, 255, 220) else Color3.fromRGB(238, 251, 255)
end

function SpiritClient:Update(dt)
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
	if not isGhostHazardImmune(state) then
		self:ProbeGhostHazards(state, now)
	end
	self:ProbeBodyHazards(state, now)
	self:UpdateHint(state)
end

function SpiritClient:HandleEffect(targetPlayer, abilityName, payload)
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
		if phase == "Start" then
			attachGhostProjectionVfx(self, payload, targetPlayer)
			return true
		elseif phase == "Resolve" or phase == "Interrupted" then
			cleanupGhostProjectionVfx(self, payload)
			return true
		elseif phase == "Rejected" then
			if payload and payload.ResolveReason == "already_active" then
				return true
			end
			cleanupGhostProjectionVfx(self, payload)
			return true
		elseif phase == "Ignored" then
			return true
		end

		return false
	end

	if phase == "Start" then
		local started = self:StartLocalProjection(payload)
		attachGhostProjectionVfx(self, payload, targetPlayer)
		return started
	elseif phase == "Resolve" or phase == "Interrupted" then
		cleanupGhostProjectionVfx(self, payload)
		self:StopLocalProjection(payload, false)
		return true
	elseif phase == "Rejected" then
		if payload and payload.ResolveReason == "already_active" then
			return true
		end
		cleanupGhostProjectionVfx(self, payload)
		self:StopLocalProjection(payload, false)
		return true
	elseif phase == "Ignored" then
		return true
	end

	return false
end

function SpiritClient:HandleStateEvent()
	return false
end

function SpiritClient:HandleUnequipped()
	self:StopLocalProjection(nil, true)
	cleanupAllGhostProjectionVfx(self)
	return false
end

function SpiritClient:HandleCharacterRemoving()
	self:StopLocalProjection(nil, true)
	cleanupAllGhostProjectionVfx(self)
end

function SpiritClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer == self.player then
		self:StopLocalProjection(nil, true)
		cleanupAllGhostProjectionVfx(self)
	else
		cleanupGhostProjectionVfxForPlayer(self, leavingPlayer)
	end
end

return SpiritClient
