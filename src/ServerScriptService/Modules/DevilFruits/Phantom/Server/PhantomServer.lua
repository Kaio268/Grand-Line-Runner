local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local MovementSpeedConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("MovementSpeed"))
local PlayerMovementSpeedService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerMovementSpeedService"))
local ActiveCooldownHud = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("ActiveCooldownHud")
)

local PhantomServer = {}

local DEFAULT_DURATION = 8
local DEFAULT_FADE_OUT_TIME = 0.22
local DEFAULT_FADE_IN_TIME = 0.28
local DEFAULT_LOCAL_BODY_TRANSPARENCY = 0.68
local DEFAULT_LOCAL_DECAL_TRANSPARENCY = 0.72
local DEFAULT_OBSERVER_BODY_TRANSPARENCY = 1
local DEFAULT_OBSERVER_DECAL_TRANSPARENCY = 1
local DEFAULT_SHIMMER_COLOR = Color3.fromRGB(193, 255, 245)
local DEFAULT_SHIMMER_ACCENT_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_HIGHLIGHT_FILL_TRANSPARENCY = 0.88
local DEFAULT_HIGHLIGHT_OUTLINE_TRANSPARENCY = 0.36
local DEFAULT_PARTICLE_RATE = 14
local DEFAULT_PARTICLE_TRANSPARENCY = 0.7
local DEFAULT_PARTICLE_LIFETIME = 0.65
local DEFAULT_PULSE_PERIOD = 0.7
local DEFAULT_SPEED_BOOST_BASE_SPEED = 1
local DEFAULT_SPEED_BOOST_MAX_SPEED = 200
local DEFAULT_SPEED_BOOST_MIN_MULTIPLIER = 1
local DEFAULT_SPEED_BOOST_MAX_MULTIPLIER = 2
local SUKE_INVISIBILITY_UNTIL_ATTRIBUTE = "SukeInvisibilityUntil"
local SUKE_INVISIBILITY_SPEED_ATTRIBUTE = "SukeInvisibilitySpeedMultiplier"

local activeFadeByPlayer = setmetatable({}, { __mode = "k" })
local fadeSequence = 0

local function clampNumber(value, fallback, minValue, maxValue)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return fallback
	end

	return math.clamp(numericValue, minValue, maxValue)
end

local function resolveColor(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function applyPlayerSpeed(player, reason)
	if player then
		PlayerMovementSpeedService.ApplyPlayerSpeed(player, reason)
	end
end

local function buildFadeExitPayload(state, reason)
	return {
		Phase = "End",
		StartedAt = state and state.StartedAt or nil,
		EndedAt = Workspace:GetServerTimeNow(),
		EndTime = state and state.EndTime or nil,
		Duration = state and state.Duration or nil,
		SpeedMultiplier = state and state.SpeedMultiplier or nil,
		ResolveReason = reason,
	}
end

local function clearFadeState(player, reason, expectedSequence, shouldApplySpeed, options)
	local state = player and activeFadeByPlayer[player] or nil
	if not state then
		return false
	end
	if expectedSequence ~= nil and state.Sequence ~= expectedSequence then
		return false
	end

	options = if type(options) == "table" then options else {}
	activeFadeByPlayer[player] = nil
	disconnectAll(state.Connections)
	if player.Parent then
		player:SetAttribute(SUKE_INVISIBILITY_UNTIL_ATTRIBUTE, nil)
		player:SetAttribute(SUKE_INVISIBILITY_SPEED_ATTRIBUTE, nil)
		if shouldApplySpeed ~= false then
			applyPlayerSpeed(player, reason or "suke_fade_clear")
		end
		if options.StartCooldown == true and typeof(state.StartAbilityCooldown) == "function" then
			local cooldownDuration = tonumber(state.AbilityConfig and state.AbilityConfig.Cooldown) or 0
			state.StartAbilityCooldown(cooldownDuration, ActiveCooldownHud.BuildCooldownStartedPayload(
				buildFadeExitPayload(state, reason),
				{
					CooldownDuration = cooldownDuration,
					RuntimeId = state.RuntimeId,
				}
			))
		elseif options.EmitReadyHud == true and typeof(state.ClearAbilityCooldown) == "function" then
			state.ClearAbilityCooldown(ActiveCooldownHud.BuildReadyPayload(buildFadeExitPayload(state, reason), {
				Reason = reason,
				RuntimeId = state.RuntimeId,
			}))
		end
	end
	return true
end

local function getSpeedBoostConfig(abilityConfig)
	local speedBoostConfig = if type(abilityConfig.SpeedBoost) == "table" then abilityConfig.SpeedBoost else {}
	return {
		BaseSpeed = clampNumber(
			speedBoostConfig.BaseSpeed,
			DEFAULT_SPEED_BOOST_BASE_SPEED,
			1,
			DEFAULT_SPEED_BOOST_MAX_SPEED
		),
		MaxSpeed = clampNumber(
			speedBoostConfig.MaxSpeed,
			DEFAULT_SPEED_BOOST_MAX_SPEED,
			1,
			10000
		),
		MinMultiplier = clampNumber(
			speedBoostConfig.MinMultiplier,
			DEFAULT_SPEED_BOOST_MIN_MULTIPLIER,
			0,
			DEFAULT_SPEED_BOOST_MAX_MULTIPLIER
		),
		MaxMultiplier = clampNumber(
			speedBoostConfig.MaxMultiplier,
			DEFAULT_SPEED_BOOST_MAX_MULTIPLIER,
			0,
			10
		),
	}
end

local function resolveSpeedBoostMultiplier(player, abilityConfig)
	local speedBoostConfig = getSpeedBoostConfig(abilityConfig)
	local selectedSpeed = MovementSpeedConfig.GetPlayerSelectedSpeed(player)
	local baseSpeed = speedBoostConfig.BaseSpeed
	local maxSpeed = math.max(baseSpeed + 0.001, speedBoostConfig.MaxSpeed)
	local progress = math.clamp((selectedSpeed - baseSpeed) / (maxSpeed - baseSpeed), 0, 1)
	local minMultiplier = speedBoostConfig.MinMultiplier
	local maxMultiplier = math.max(minMultiplier, speedBoostConfig.MaxMultiplier)
	return math.max(1, minMultiplier + (progress * (maxMultiplier - minMultiplier)))
end

local function startFadeState(player, context, abilityConfig, duration, startedAt)
	if not player then
		return 1
	end

	clearFadeState(player, "suke_fade_refresh", nil, false)

	fadeSequence += 1
	local sequence = fadeSequence
	local endsAt = os.clock() + duration
	local speedMultiplier = resolveSpeedBoostMultiplier(player, abilityConfig)
	local hudStartedAt = tonumber(startedAt) or Workspace:GetServerTimeNow()
	local state = {
		Sequence = sequence,
		RuntimeId = string.format("%d:Fade:%d", player.UserId, sequence),
		Character = context.Character,
		AbilityConfig = abilityConfig,
		StartedAt = hudStartedAt,
		EndTime = hudStartedAt + duration,
		Duration = duration,
		SpeedMultiplier = speedMultiplier,
		StartAbilityCooldown = context.StartAbilityCooldown,
		ClearAbilityCooldown = context.ClearAbilityCooldown,
		Connections = {},
	}
	activeFadeByPlayer[player] = state

	player:SetAttribute(SUKE_INVISIBILITY_UNTIL_ATTRIBUTE, endsAt)
	player:SetAttribute(SUKE_INVISIBILITY_SPEED_ATTRIBUTE, speedMultiplier)
	applyPlayerSpeed(player, "suke_fade_start")

	local humanoid = context.Humanoid
	if not humanoid and context.Character then
		humanoid = context.Character:FindFirstChildOfClass("Humanoid")
	end
	if humanoid then
		state.Connections[#state.Connections + 1] = humanoid.Died:Connect(function()
			clearFadeState(player, "suke_fade_death", sequence, nil, {
				EmitReadyHud = true,
			})
		end)
	end

	state.Connections[#state.Connections + 1] = player.CharacterRemoving:Connect(function(character)
		if character == state.Character then
			clearFadeState(player, "suke_fade_character_removing", sequence, nil, {
				EmitReadyHud = true,
			})
		end
	end)

	task.delay(duration + 0.05, function()
		clearFadeState(player, "suke_fade_expired", sequence, nil, {
			StartCooldown = true,
		})
	end)

	return speedMultiplier, state
end

function PhantomServer.Fade(context)
	local abilityConfig = context.AbilityConfig or {}
	local vfxConfig = type(abilityConfig.Vfx) == "table" and abilityConfig.Vfx or {}
	local duration = clampNumber(abilityConfig.Duration, DEFAULT_DURATION, 0.1, 10)
	local startedAt = Workspace:GetServerTimeNow()
	local speedMultiplier, state = startFadeState(context.Player, context, abilityConfig, duration, startedAt)

	local payload = {
		Phase = "Start",
		StartedAt = startedAt,
		EndTime = startedAt + duration,
		Duration = duration,
		SpeedMultiplier = speedMultiplier,
		FadeOutTime = clampNumber(abilityConfig.FadeOutTime, DEFAULT_FADE_OUT_TIME, 0, 1),
		FadeInTime = clampNumber(abilityConfig.FadeInTime, DEFAULT_FADE_IN_TIME, 0, 1),
		LocalBodyTransparency = clampNumber(
			abilityConfig.LocalBodyTransparency or abilityConfig.BodyTransparency,
			DEFAULT_LOCAL_BODY_TRANSPARENCY,
			0,
			0.95
		),
		LocalDecalTransparency = clampNumber(
			abilityConfig.LocalDecalTransparency or abilityConfig.DecalTransparency,
			DEFAULT_LOCAL_DECAL_TRANSPARENCY,
			0,
			0.98
		),
		ObserverBodyTransparency = clampNumber(
			abilityConfig.ObserverBodyTransparency,
			DEFAULT_OBSERVER_BODY_TRANSPARENCY,
			0,
			1
		),
		ObserverDecalTransparency = clampNumber(
			abilityConfig.ObserverDecalTransparency,
			DEFAULT_OBSERVER_DECAL_TRANSPARENCY,
			0,
			1
		),
		ShimmerColor = resolveColor(vfxConfig.ShimmerColor, DEFAULT_SHIMMER_COLOR),
		ShimmerAccentColor = resolveColor(vfxConfig.ShimmerAccentColor, DEFAULT_SHIMMER_ACCENT_COLOR),
		HighlightFillTransparency = clampNumber(vfxConfig.HighlightFillTransparency, DEFAULT_HIGHLIGHT_FILL_TRANSPARENCY, 0, 1),
		HighlightOutlineTransparency = clampNumber(vfxConfig.HighlightOutlineTransparency, DEFAULT_HIGHLIGHT_OUTLINE_TRANSPARENCY, 0, 1),
		ParticleRate = clampNumber(vfxConfig.ParticleRate, DEFAULT_PARTICLE_RATE, 0, 80),
		ParticleTransparency = clampNumber(vfxConfig.ParticleTransparency, DEFAULT_PARTICLE_TRANSPARENCY, 0, 1),
		ParticleLifetime = clampNumber(vfxConfig.ParticleLifetime, DEFAULT_PARTICLE_LIFETIME, 0.1, 2),
		PulsePeriod = clampNumber(vfxConfig.PulsePeriod, DEFAULT_PULSE_PERIOD, 0.2, 3),
	}
	return ActiveCooldownHud.BuildActivePayload(payload, {
		StartedAt = startedAt,
		ActiveEndsAt = startedAt + duration,
		ActiveDuration = duration,
		CooldownDuration = tonumber(abilityConfig.Cooldown) or 0,
		RuntimeId = state and state.RuntimeId or nil,
	}), {
		ApplyCooldown = false,
	}
end

function PhantomServer.ClearRuntimeState(player)
	clearFadeState(player, "suke_fade_runtime_clear", nil, nil, {
		EmitReadyHud = true,
	})
end

function PhantomServer.GetLegacyHandler()
	return PhantomServer
end

return PhantomServer
