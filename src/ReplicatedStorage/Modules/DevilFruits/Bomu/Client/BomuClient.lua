local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DevilFruits = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits")
local AnimationLoadDiagnostics = require(DevilFruits:WaitForChild("AnimationLoadDiagnostics"))
local AnimationResolver = require(DevilFruits:WaitForChild("Shared"):WaitForChild("AnimationResolver"))
local CommonAnimation = require(DevilFruits:WaitForChild("Shared"):WaitForChild("CommonAnimation"))

local BomuClient = {}
BomuClient.__index = BomuClient

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
		return true
	end

	if payload.Action == LAND_MINE_ACTION_DETONATED then
		local sequence = self.actionSequenceByPlayer[targetPlayer] or beginActionSequence(self, targetPlayer)
		if payload.OwnerLaunched == true then
			queueJumpAnimation(self, targetPlayer, sequence)
		end

		-- Detonation still falls through so the current generic Bomu explosion
		-- fallback stays in control of that visual path.
		return false
	end

	if payload.Action ~= LAND_MINE_ACTION_PLACED then
		return false
	end

	beginActionSequence(self, targetPlayer)
	local playedAnimation = playActionAnimation(self, targetPlayer, BOMU_ACTION_PLANT)
	local minePosition = payload.MinePosition or payload.OriginPosition
	local playedPulse = playLandMinePlacementPulse(minePosition)

	return playedAnimation or playedPulse
end

function BomuClient:HandleStateEvent(_eventName, _abilityName, _value, _payload)
	return false
end

function BomuClient:Update()
	for targetPlayer in pairs(self.animationStatesByPlayer) do
		if not targetPlayer.Parent or not targetPlayer.Character then
			stopBomuAnimation(self, targetPlayer, 0)
			self.actionSequenceByPlayer[targetPlayer] = nil
		end
	end
end

function BomuClient:HandleCharacterRemoving()
	stopBomuAnimation(self, self.player, 0)
	if self.player ~= nil then
		self.actionSequenceByPlayer[self.player] = nil
	end
end

function BomuClient:HandlePlayerRemoving(leavingPlayer)
	stopBomuAnimation(self, leavingPlayer, 0)
	if leavingPlayer ~= nil then
		self.actionSequenceByPlayer[leavingPlayer] = nil
	end
end

return BomuClient
