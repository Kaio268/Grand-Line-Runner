local Debris = game:GetService("Debris")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local AnimationLoadDiagnostics = require(DevilFruits:WaitForChild("AnimationLoadDiagnostics"))
local AnimationResolver = require(DevilFruits:WaitForChild("Shared"):WaitForChild("AnimationResolver"))
local CommonAnimation = require(DevilFruits:WaitForChild("Shared"):WaitForChild("CommonAnimation"))
local SettingsAudioController = require(Modules:WaitForChild("SettingsAudioController"))

local BomuClient = {}
BomuClient.__index = BomuClient

local FRUIT_NAME = "Bomu Bomu no Mi"
local LAND_MINE_ABILITY = "LandMine"
local LAND_MINE_ACTION_PLACED = "Placed"
local LAND_MINE_ACTION_DETONATING = "Detonating"
local LAND_MINE_ACTION_DETONATED = "Detonated"
local BOMU_ACTION_PLANT = "Plant"
local BOMU_ACTION_DETONATE = "Detonate"
local BOMU_ACTION_JUMP = "Jump"
local DEFAULT_ANIMATION_KEY_BY_ACTION = {
	[BOMU_ACTION_PLANT] = "Bomu.Plant",
	[BOMU_ACTION_DETONATE] = "Bomu.Detonate",
	[BOMU_ACTION_JUMP] = "Bomu.Jump",
}
local DEFAULT_FADE_TIME = 0.05
local DEFAULT_STOP_FADE_TIME = 0.08
local DEFAULT_JUMP_DELAY = 0.12
local DEFAULT_PLANT_MOVEMENT_LOCK_DURATION = 0.55
local DEFAULT_DETONATE_MOVEMENT_LOCK_DURATION = 0.35
local MOVEMENT_LOCK_INPUT_ACTION = "BomuActionMovementLock"
local MOVEMENT_LOCK_INPUT_PRIORITY = 10000
local SOURCE_LABEL = "ReplicatedStorage.Modules.DevilFruits.Bomu.Client.BomuClient"
local PLACEMENT_PULSE_NAME = "BomuLandMinePlacementPulse"
local PLACEMENT_PULSE_COLOR = Color3.fromRGB(255, 89, 89)
local PLACEMENT_PULSE_TRANSPARENCY = 0.25
local PLACEMENT_PULSE_SIZE = Vector3.new(1.1, 1.1, 1.1)
local PLACEMENT_PULSE_OFFSET = Vector3.new(0, 0.35, 0)
local PLACEMENT_PULSE_SIZE_STEP = Vector3.new(0.18, 0.18, 0.18)
local PLACEMENT_PULSE_TRANSPARENCY_STEP = 0.1
local PLACEMENT_PULSE_STEPS = 6
local PLACEMENT_PULSE_STEP_DELAY = 0.03
local PLACEMENT_PULSE_LIFETIME = 0.3
local SOUND_DETONATE = "Detonate"
local SOUND_CLEANUP_FALLBACK_SECONDS = 8
local DEFAULT_DETONATE_ROLLOFF_MAX_DISTANCE = 180
local DEBUG_SOUND = RunService:IsStudio()
local SOUND_LOG_LIMIT = 40
local soundLogCount = 0
local soundWarnCount = 0

local function formatInstancePath(instance)
	if typeof(instance) ~= "Instance" then
		return "<nil>"
	end

	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)

	return ok and fullName or instance.Name
end

local function bomuSoundLog(message, ...)
	if not DEBUG_SOUND or soundLogCount >= SOUND_LOG_LIMIT then
		return
	end

	soundLogCount += 1
	print(string.format("[BOMU SOUND] " .. tostring(message), ...))
end

local function bomuSoundWarn(message, ...)
	if not DEBUG_SOUND or soundWarnCount >= SOUND_LOG_LIMIT then
		return
	end

	soundWarnCount += 1
	warn(string.format("[BOMU SOUND] " .. tostring(message), ...))
end

local function getSoundPlayingState(sound)
	if not sound then
		return "<nil>"
	end

	local ok, isPlaying = pcall(function()
		return sound.IsPlaying
	end)

	return ok and tostring(isPlaying) or "<unreadable>"
end

local function logSoundDiagnostics(stage, soundName, sound)
	if not DEBUG_SOUND then
		return
	end

	if not sound then
		bomuSoundWarn("%s sound=%s issue=missing_instance", tostring(stage), tostring(soundName))
		return
	end

	local soundId = tostring(sound.SoundId or "")
	local volume = tonumber(sound.Volume) or 0
	local rollOffMaxDistance = tonumber(sound.RollOffMaxDistance) or 0
	if soundId == "" then
		bomuSoundWarn("%s sound=%s path=%s issue=missing_sound_id", tostring(stage), tostring(soundName), formatInstancePath(sound))
	end
	if volume <= 0 then
		bomuSoundWarn(
			"%s sound=%s path=%s issue=zero_or_negative_volume volume=%.3f",
			tostring(stage),
			tostring(soundName),
			formatInstancePath(sound),
			volume
		)
	end
	if rollOffMaxDistance <= 0 then
		bomuSoundWarn(
			"%s sound=%s path=%s issue=invalid_rolloff_max_distance value=%.3f",
			tostring(stage),
			tostring(soundName),
			formatInstancePath(sound),
			rollOffMaxDistance
		)
	end
	if not sound.Parent then
		bomuSoundWarn("%s sound=%s path=%s issue=nil_parent", tostring(stage), tostring(soundName), formatInstancePath(sound))
	end

	bomuSoundLog(
		"%s sound=%s path=%s parent=%s soundId=%s volume=%.3f rollOffMaxDistance=%.3f looped=%s timeLength=%.3f isPlaying=%s",
		tostring(stage),
		tostring(soundName),
		formatInstancePath(sound),
		formatInstancePath(sound.Parent),
		soundId,
		volume,
		rollOffMaxDistance,
		tostring(sound.Looped),
		tonumber(sound.TimeLength) or 0,
		getSoundPlayingState(sound)
	)
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

local function getLandMineAudioConfig()
	local abilityConfig = DevilFruitConfig.GetAbility(FRUIT_NAME, LAND_MINE_ABILITY)
	local audioConfig = abilityConfig and abilityConfig.Audio
	if type(audioConfig) ~= "table" then
		return nil
	end

	return audioConfig
end

local function getLandMineAudioNumber(fieldName, fallback, minimum)
	local audioConfig = getLandMineAudioConfig()
	local numericValue = audioConfig and tonumber(audioConfig[fieldName]) or nil
	if not numericValue then
		return fallback
	end

	if typeof(minimum) == "number" then
		return math.max(minimum, numericValue)
	end

	return numericValue
end

local function createLandMineSound(soundName, looped)
	local audioConfig = getLandMineAudioConfig()
	if not audioConfig then
		bomuSoundWarn("sound_config_missing sound=%s issue=missing_audio_table", tostring(soundName))
		return nil
	end

	local soundId = normalizeSoundId(audioConfig.DetonateSoundId)
	if not soundId then
		bomuSoundWarn("sound_config_missing sound=%s key=DetonateSoundId issue=missing_sound_id", tostring(soundName))
		return nil
	end

	local sound = Instance.new("Sound")
	sound.Name = tostring(soundName)
	sound.SoundId = soundId
	sound.Looped = looped == true
	sound.Volume = getLandMineAudioNumber("Volume", 1, 0)
	sound.RollOffMaxDistance = getLandMineAudioNumber(
		"RollOffMaxDistance",
		DEFAULT_DETONATE_ROLLOFF_MAX_DISTANCE,
		1
	)
	return sound
end

local function getSoundCleanupDelay(sound)
	local timeLength = tonumber(sound and sound.TimeLength) or 0
	if timeLength > 0 then
		return timeLength + 1
	end

	return SOUND_CLEANUP_FALLBACK_SECONDS
end

local function getCharacterRoot(targetPlayer)
	local character = targetPlayer and targetPlayer.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function createSoundAnchor(position, soundName)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local anchor = Instance.new("Part")
	anchor.Name = "BomuSound_" .. tostring(soundName)
	anchor.Anchored = true
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	return anchor
end

local function resolveDetonateSoundParent(targetPlayer, payload)
	local explosionPosition = typeof(payload and payload.OriginPosition) == "Vector3" and payload.OriginPosition
		or typeof(payload and payload.MinePosition) == "Vector3" and payload.MinePosition
		or nil
	if explosionPosition then
		local anchor = createSoundAnchor(explosionPosition, SOUND_DETONATE)
		return anchor, anchor
	end

	local rootPart = getCharacterRoot(targetPlayer)
	if rootPart then
		bomuSoundWarn("detonate_parent_fallback sound=%s parent=%s", SOUND_DETONATE, formatInstancePath(rootPart))
		return rootPart, nil
	end

	bomuSoundWarn("detonate_parent_missing sound=%s player=%s", SOUND_DETONATE, tostring(targetPlayer and targetPlayer.Name))
	return nil, nil
end

local function playLandMineDetonateSound(targetPlayer, payload)
	local parent, anchor = resolveDetonateSoundParent(targetPlayer, payload)
	if not parent then
		return nil
	end

	local sound = createLandMineSound(SOUND_DETONATE, false)
	if not sound then
		if anchor and anchor.Parent then
			anchor:Destroy()
		end
		bomuSoundWarn("detonate_skipped sound=%s issue=sound_config_missing", SOUND_DETONATE)
		return nil
	end

	sound.Parent = parent
	logSoundDiagnostics("detonate_parented", SOUND_DETONATE, sound)
	SettingsAudioController.TrackSound(sound)
	logSoundDiagnostics("detonate_tracked", SOUND_DETONATE, sound)
	sound:Play()
	logSoundDiagnostics("detonate_play_called", SOUND_DETONATE, sound)

	local cleanupDelay = getSoundCleanupDelay(sound)
	local endedConnection
	endedConnection = sound.Ended:Connect(function()
		if endedConnection then
			endedConnection:Disconnect()
			endedConnection = nil
		end
		if sound.Parent then
			sound:Destroy()
		end
		if anchor and anchor.Parent then
			anchor:Destroy()
		end
		bomuSoundLog("detonate_cleanup sound=%s", SOUND_DETONATE)
	end)

	Debris:AddItem(sound, cleanupDelay)
	if anchor then
		Debris:AddItem(anchor, cleanupDelay + 0.25)
	end

	return sound
end

local function playLandMinePlacementPulse(worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return false
	end

	local pulse = Instance.new("Part")
	pulse.Name = PLACEMENT_PULSE_NAME
	pulse.Anchored = true
	pulse.CanCollide = false
	pulse.CanTouch = false
	pulse.CanQuery = false
	pulse.Shape = Enum.PartType.Ball
	pulse.Material = Enum.Material.Neon
	pulse.Color = PLACEMENT_PULSE_COLOR
	pulse.Transparency = PLACEMENT_PULSE_TRANSPARENCY
	pulse.Size = PLACEMENT_PULSE_SIZE
	pulse.CFrame = CFrame.new(worldPosition + PLACEMENT_PULSE_OFFSET)
	pulse.Parent = Workspace

	task.spawn(function()
		for _ = 1, PLACEMENT_PULSE_STEPS do
			if not pulse.Parent then
				break
			end

			pulse.Size += PLACEMENT_PULSE_SIZE_STEP
			pulse.Transparency += PLACEMENT_PULSE_TRANSPARENCY_STEP
			task.wait(PLACEMENT_PULSE_STEP_DELAY)
		end
	end)

	Debris:AddItem(pulse, PLACEMENT_PULSE_LIFETIME)
	return true
end

local function getLandMineAbilityConfig(fruitEntry)
	if type(fruitEntry) ~= "table" then
		return nil
	end

	local abilities = fruitEntry.Abilities
	local abilityEntry = type(abilities) == "table" and abilities[LAND_MINE_ABILITY] or nil
	if type(abilityEntry) == "table" and type(abilityEntry.Config) == "table" then
		return abilityEntry.Config
	end

	local fruitConfig = fruitEntry.Config
	local configAbilities = type(fruitConfig) == "table" and fruitConfig.Abilities or nil
	local abilityConfig = type(configAbilities) == "table" and configAbilities[LAND_MINE_ABILITY] or nil
	if type(abilityConfig) == "table" then
		return abilityConfig
	end

	return nil
end

local function getActionAnimationConfig(abilityConfig, actionKey)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	local actionConfig = type(animationConfig) == "table" and animationConfig[actionKey] or nil
	if type(actionConfig) == "table" then
		return actionConfig
	end

	return {}
end

local function getJumpAnimationDelay(abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	local configuredDelay = type(animationConfig) == "table" and tonumber(animationConfig.JumpDelay) or nil
	return math.max(0, configuredDelay or DEFAULT_JUMP_DELAY)
end

local function getActionMovementLockDuration(abilityConfig, actionKey, fallbackDuration)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	local actionConfig = type(animationConfig) == "table" and animationConfig[actionKey] or nil
	local configuredDuration = type(actionConfig) == "table" and tonumber(actionConfig.MovementLockDuration) or nil
	if configuredDuration == nil then
		configuredDuration = type(abilityConfig) == "table" and tonumber(abilityConfig.MovementLockDuration) or nil
	end

	return math.max(0, configuredDuration or fallbackDuration or 0)
end

local function getTrackPriority(actionConfig)
	local priority = type(actionConfig) == "table" and actionConfig.Priority or nil
	if typeof(priority) == "EnumItem" then
		return priority
	end

	return Enum.AnimationPriority.Action
end

local function stopBomuAnimation(self, targetPlayer, fadeTime)
	if type(self.animationStatesByPlayer) ~= "table" then
		return false
	end
	if targetPlayer == nil then
		return false
	end

	local state = self.animationStatesByPlayer[targetPlayer]
	if type(state) ~= "table" then
		return false
	end

	self.animationStatesByPlayer[targetPlayer] = nil
	if state.StoppedConnection then
		state.StoppedConnection:Disconnect()
		state.StoppedConnection = nil
	end

	CommonAnimation.StopTrack(state.Track, fadeTime or state.StopFadeTime)
	return true
end

local function getCharacterHumanoid(player)
	local character = player and player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function sinkMovementInput()
	return Enum.ContextActionResult.Sink
end

local function setLocalMovementInputLocked(isLocked)
	if isLocked then
		ContextActionService:BindActionAtPriority(
			MOVEMENT_LOCK_INPUT_ACTION,
			sinkMovementInput,
			false,
			MOVEMENT_LOCK_INPUT_PRIORITY,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump
		)
	else
		ContextActionService:UnbindAction(MOVEMENT_LOCK_INPUT_ACTION)
	end
end

local function enforceLocalMovementLock(state)
	local humanoid = state and state.Humanoid
	if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
		return false
	end

	pcall(function()
		humanoid:Move(Vector3.zero, false)
	end)
	return true
end

local function releaseLocalMovementLock(self, _reason)
	local state = self.localMovementLock
	if not state then
		return false
	end

	self.localMovementLock = nil
	setLocalMovementInputLocked(false)

	local humanoid = state.Humanoid
	if humanoid and humanoid.Parent and humanoid.Health > 0 then
		pcall(function()
			humanoid:Move(Vector3.zero, false)
		end)
	end

	return true
end

local function applyLocalMovementLock(self, targetPlayer, actionKey, duration)
	if targetPlayer ~= self.player then
		return nil
	end

	duration = math.max(0, tonumber(duration) or 0)
	if duration <= 0 then
		return nil
	end

	local humanoid = getCharacterHumanoid(targetPlayer)
	if not humanoid then
		return nil
	end

	releaseLocalMovementLock(self, "replaced")

	local lockState = {
		Action = actionKey,
		Humanoid = humanoid,
		EndAt = os.clock() + duration,
	}
	self.localMovementLock = lockState
	setLocalMovementInputLocked(true)
	enforceLocalMovementLock(lockState)

	task.delay(duration, function()
		if self.localMovementLock == lockState then
			releaseLocalMovementLock(self, "duration_complete")
		end
	end)

	return lockState
end

local function beginActionSequence(self, targetPlayer)
	if targetPlayer == nil then
		return nil
	end

	self.actionSequenceByPlayer[targetPlayer] = (self.actionSequenceByPlayer[targetPlayer] or 0) + 1
	return self.actionSequenceByPlayer[targetPlayer]
end

local function resolveActionAnimation(actionKey, actionConfig)
	local animationKey = actionConfig.AnimationKey or DEFAULT_ANIMATION_KEY_BY_ACTION[actionKey]
	if typeof(animationKey) ~= "string" or animationKey == "" then
		return nil, nil, animationKey
	end

	local animation, descriptor = AnimationResolver.GetAnimation(animationKey, {
		Context = string.format("Bomu.%s", tostring(actionKey)),
	})
	return animation, descriptor, animationKey
end

local function playActionAnimation(self, targetPlayer, actionKey)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	stopBomuAnimation(self, targetPlayer)

	local actionConfig = getActionAnimationConfig(self.abilityConfig, actionKey)
	local animation, descriptor, animationKey = resolveActionAnimation(actionKey, actionConfig)
	if not animation then
		return false
	end

	local character = targetPlayer.Character
	local animator = CommonAnimation.GetAnimatorFromCharacter(character, 0.25)
	if not animator then
		return false
	end

	local track, loadFailure = AnimationLoadDiagnostics.LoadTrack(animator, animation, SOURCE_LABEL)
	if not track then
		warn(string.format(
			"[BOMU ANIM][WARN] animation failed action=%s player=%s detail=%s",
			tostring(actionKey),
			tostring(targetPlayer.Name),
			tostring(loadFailure)
		))
		return false
	end

	local fadeTime = math.max(0, tonumber(actionConfig.FadeTime) or DEFAULT_FADE_TIME)
	local stopFadeTime = math.max(0, tonumber(actionConfig.StopFadeTime) or DEFAULT_STOP_FADE_TIME)
	local playbackSpeed = tonumber(actionConfig.PlaybackSpeed) or 1
	track.Priority = getTrackPriority(actionConfig)
	track.Looped = actionConfig.Looped == true
	track:Play(fadeTime, 1, playbackSpeed)

	local state = {
		Action = actionKey,
		AnimationKey = animationKey,
		AnimationId = descriptor and descriptor.AnimationId,
		Track = track,
		StopFadeTime = stopFadeTime,
	}
	self.animationStatesByPlayer[targetPlayer] = state
	state.StoppedConnection = track.Stopped:Connect(function()
		if self.animationStatesByPlayer[targetPlayer] == state then
			self.animationStatesByPlayer[targetPlayer] = nil
		end

		if state.StoppedConnection then
			state.StoppedConnection:Disconnect()
			state.StoppedConnection = nil
		end
	end)

	local stopAfter = tonumber(actionConfig.StopAfter)
	if stopAfter and stopAfter > 0 then
		task.delay(stopAfter, function()
			if self.animationStatesByPlayer[targetPlayer] == state then
				stopBomuAnimation(self, targetPlayer, stopFadeTime)
			end
		end)
	end

	AnimationLoadDiagnostics.LogTrackPlay(
		track,
		SOURCE_LABEL,
		string.format("Bomu.%s", tostring(actionKey)),
		descriptor and descriptor.AnimationId,
		string.format(
			"key=%s fade=%.3f speed=%.3f looped=%s",
			tostring(animationKey),
			fadeTime,
			playbackSpeed,
			tostring(track.Looped)
		)
	)

	return true
end

local function queueJumpAnimation(self, targetPlayer, sequence)
	local jumpDelay = getJumpAnimationDelay(self.abilityConfig)

	local function playJumpIfCurrent()
		if sequence == nil then
			return
		end

		if self.actionSequenceByPlayer[targetPlayer] ~= sequence then
			return
		end

		playActionAnimation(self, targetPlayer, BOMU_ACTION_JUMP)
	end

	if jumpDelay <= 0 then
		playJumpIfCurrent()
		return
	end

	task.delay(jumpDelay, playJumpIfCurrent)
end

function BomuClient.Create(config, fruitEntry)
	config = config or {}

	local self = setmetatable({}, BomuClient)
	self.player = config.player
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or nil
	self.abilityConfig = getLandMineAbilityConfig(fruitEntry)
	self.animationStatesByPlayer = {}
	self.actionSequenceByPlayer = {}
	self.localMovementLock = nil
	return self
end

function BomuClient:BeginPredictedRequest(_abilityName, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:BuildRequestPayload(_abilityName, _abilityConfig, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= LAND_MINE_ABILITY or typeof(payload) ~= "table" then
		return false
	end

	if payload.Action == LAND_MINE_ACTION_DETONATING then
		beginActionSequence(self, targetPlayer)
		playActionAnimation(self, targetPlayer, BOMU_ACTION_DETONATE)
		local detonateLockDuration = getActionMovementLockDuration(
			self.abilityConfig,
			BOMU_ACTION_DETONATE,
			tonumber(payload.ExplosionDelay) or DEFAULT_DETONATE_MOVEMENT_LOCK_DURATION
		)
		applyLocalMovementLock(self, targetPlayer, BOMU_ACTION_DETONATE, detonateLockDuration)
		return true
	end

	if payload.Action == LAND_MINE_ACTION_DETONATED then
		local sequence = self.actionSequenceByPlayer[targetPlayer] or beginActionSequence(self, targetPlayer)
		if targetPlayer == self.player then
			releaseLocalMovementLock(self, "detonated")
		end
		if payload.OwnerLaunched == true then
			queueJumpAnimation(self, targetPlayer, sequence)
		end
		playLandMineDetonateSound(targetPlayer, payload)

		-- Detonation still falls through so the current generic Bomu explosion
		-- fallback stays in control of that visual path.
		return false
	end

	if payload.Action ~= LAND_MINE_ACTION_PLACED then
		return false
	end

	beginActionSequence(self, targetPlayer)
	local playedAnimation = playActionAnimation(self, targetPlayer, BOMU_ACTION_PLANT)
	local plantLockDuration = getActionMovementLockDuration(
		self.abilityConfig,
		BOMU_ACTION_PLANT,
		DEFAULT_PLANT_MOVEMENT_LOCK_DURATION
	)
	applyLocalMovementLock(self, targetPlayer, BOMU_ACTION_PLANT, plantLockDuration)
	local minePosition = payload.MinePosition or payload.OriginPosition
	local playedPulse = playLandMinePlacementPulse(minePosition)

	return playedAnimation or playedPulse
end

function BomuClient:HandleStateEvent(_eventName, _abilityName, _value, _payload)
	return false
end

function BomuClient:Update()
	local localMovementLock = self.localMovementLock
	if localMovementLock then
		if os.clock() >= (localMovementLock.EndAt or 0) or not enforceLocalMovementLock(localMovementLock) then
			releaseLocalMovementLock(self, "duration_complete")
		end
	end

	for targetPlayer in pairs(self.animationStatesByPlayer) do
		if not targetPlayer.Parent or not targetPlayer.Character then
			stopBomuAnimation(self, targetPlayer, 0)
			self.actionSequenceByPlayer[targetPlayer] = nil
		end
	end
end

function BomuClient:HandleCharacterRemoving()
	releaseLocalMovementLock(self, "character_removing")
	stopBomuAnimation(self, self.player, 0)
	if self.player ~= nil then
		self.actionSequenceByPlayer[self.player] = nil
	end
end

function BomuClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer == self.player then
		releaseLocalMovementLock(self, "player_removing")
	end
	stopBomuAnimation(self, leavingPlayer, 0)
	if leavingPlayer ~= nil then
		self.actionSequenceByPlayer[leavingPlayer] = nil
	end
end

return BomuClient
