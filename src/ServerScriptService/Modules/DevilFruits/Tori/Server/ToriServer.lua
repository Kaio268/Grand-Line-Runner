local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ToriServer = {}

local DEFAULT_PHOENIX_FLAME_SHIELD_RADIUS = 18
local DEFAULT_PHOENIX_FLIGHT_DURATION = 4.5
local DEFAULT_PHOENIX_FLIGHT_STARTUP_DURATION = 0.85
local DEFAULT_PHOENIX_TAKEOFF_DURATION = 0.4
local DEFAULT_PHOENIX_INITIAL_LIFT = 22
local DEFAULT_PHOENIX_MAX_RISE_HEIGHT = 132
local DEFAULT_PHOENIX_VERTICAL_SPEED = 90
local DEFAULT_PHOENIX_FLIGHT_SPEED = 80
local DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_REFERENCE = 17
local DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_STRENGTH = 0.5
local DEFAULT_PHOENIX_MAX_DESCEND_SPEED = 72
local DEFAULT_PHOENIX_HORIZONTAL_RESPONSIVENESS = 14
local DEFAULT_PHOENIX_SHIELD_DURATION = 5
local DEFAULT_PHOENIX_SHIELD_ANIMATION_LOCK_DURATION = 1.6666667
local PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local PHOENIX_FLIGHT_END_ACTION = "End"
local CLIENT_NATURAL_END_GRACE = 0.35
local SERVER_NATURAL_FALLBACK_GRACE = 0.75
local CHARACTER_REMOVING_REASON = "character_removing"

local cachedToriPassiveService = nil
local endCooldownSequence = 0
local activeEndCooldownStates = {
	[PHOENIX_FLIGHT_ABILITY] = setmetatable({}, { __mode = "k" }),
	[PHOENIX_SHIELD_ABILITY] = setmetatable({}, { __mode = "k" }),
}

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function toriCooldownLog(message, ...)
	print("[ToriCooldown] " .. string.format(message, ...))
end

local function resolveAbilityContext(selfOrContext, maybeContext)
	if type(maybeContext) == "table" and maybeContext.Player ~= nil then
		return maybeContext
	end

	if type(selfOrContext) == "table" and selfOrContext.Player ~= nil then
		return selfOrContext
	end

	return nil
end

local function getStateBucket(abilityName)
	return activeEndCooldownStates[abilityName]
end

local function getActiveEndCooldownState(player, abilityName)
	local bucket = getStateBucket(abilityName)
	if not bucket then
		return nil
	end

	return bucket[player]
end

local function clearActiveEndCooldownState(state)
	local bucket = state and getStateBucket(state.AbilityName)
	if bucket and bucket[state.Player] == state then
		bucket[state.Player] = nil
	end
end

local function isPhoenixFlightEndPayload(payload)
	return type(payload) == "table"
		and typeof(payload.Action) == "string"
		and string.lower(payload.Action) == string.lower(PHOENIX_FLIGHT_END_ACTION)
end

local function buildEndPayload(state, reason, endedAt)
	return {
		Phase = "End",
		EndReason = reason,
		RuntimeId = state.RuntimeId,
		StartedAt = state.StartedAt,
		EndedAt = endedAt,
		NaturalEndAt = state.NaturalEndAt,
		FallbackEndAt = state.FallbackEndAt,
		ActualDuration = math.max(0, endedAt - state.StartedAt),
		CooldownDuration = state.CooldownDuration,
	}
end

local function beginCooldownForEndedState(state, reason, endedAt)
	if not state or state.CooldownStarted then
		return false, state and (state.CooldownReadyAt or 0) or 0
	end

	state.CooldownStarted = true
	local readyAt = 0
	if state.Player and state.Player.Parent == Players and typeof(state.StartAbilityCooldown) == "function" then
		readyAt = state.StartAbilityCooldown(state.CooldownDuration, buildEndPayload(state, reason, endedAt))
	end

	state.CooldownReadyAt = readyAt
	toriCooldownLog(
		"%s cooldown begin player=%s userId=%s runtimeId=%s reason=%s cooldownDuration=%.2f readyAt=%s",
		tostring(state.AbilityName),
		state.Player and state.Player.Name or "<nil>",
		tostring(state.Player and state.Player.UserId),
		tostring(state.RuntimeId),
		tostring(reason),
		tonumber(state.CooldownDuration) or 0,
		tostring(readyAt)
	)
	return true, readyAt
end

local function finishEndCooldownState(state, reason)
	if not state or state.Ended then
		return false, 0
	end

	state.Ended = true
	clearActiveEndCooldownState(state)

	local endedAt = getSharedTimestamp()
	toriCooldownLog(
		"%s end player=%s userId=%s runtimeId=%s reason=%s elapsed=%.2f naturalEndIn=%.2f",
		tostring(state.AbilityName),
		state.Player and state.Player.Name or "<nil>",
		tostring(state.Player and state.Player.UserId),
		tostring(state.RuntimeId),
		tostring(reason),
		math.max(0, endedAt - state.StartedAt),
		(state.NaturalEndAt or endedAt) - endedAt
	)

	return beginCooldownForEndedState(state, reason, endedAt)
end

local function abandonEndCooldownState(state, reason)
	if not state or state.Ended then
		return false
	end

	state.Ended = true
	clearActiveEndCooldownState(state)
	toriCooldownLog(
		"%s cleared without cooldown player=%s userId=%s runtimeId=%s reason=%s",
		tostring(state.AbilityName),
		state.Player and state.Player.Name or "<nil>",
		tostring(state.Player and state.Player.UserId),
		tostring(state.RuntimeId),
		tostring(reason)
	)
	return true
end

local function startEndCooldownState(context, abilityName, naturalDelay, cooldownDuration, fallbackGrace)
	local player = context.Player
	local bucket = getStateBucket(abilityName)
	if not player or not bucket then
		return nil
	end

	endCooldownSequence += 1
	local startedAt = getSharedTimestamp()
	local resolvedNaturalDelay = math.max(0, tonumber(naturalDelay) or 0)
	local resolvedFallbackGrace = math.max(0, tonumber(fallbackGrace) or 0)
	local state = {
		Player = player,
		AbilityName = abilityName,
		AbilityConfig = context.AbilityConfig,
		RuntimeId = string.format("%d:%s:%d", player.UserId, abilityName, endCooldownSequence),
		StartedAt = startedAt,
		NaturalEndAt = startedAt + resolvedNaturalDelay,
		FallbackEndAt = startedAt + resolvedNaturalDelay + resolvedFallbackGrace,
		CooldownDuration = math.max(0, tonumber(cooldownDuration) or 0),
		StartAbilityCooldown = context.StartAbilityCooldown,
	}

	bucket[player] = state
	local naturalToken = {}
	state.NaturalToken = naturalToken

	toriCooldownLog(
		"%s start player=%s userId=%d runtimeId=%s naturalEndIn=%.2f fallbackGrace=%.2f cooldownDuration=%.2f",
		abilityName,
		player.Name,
		player.UserId,
		state.RuntimeId,
		resolvedNaturalDelay,
		resolvedFallbackGrace,
		state.CooldownDuration
	)

	task.delay(resolvedNaturalDelay + resolvedFallbackGrace, function()
		if getActiveEndCooldownState(player, abilityName) ~= state then
			return
		end
		if state.NaturalToken ~= naturalToken or state.Ended then
			return
		end

		finishEndCooldownState(state, "natural")
	end)

	return state
end

local function resolveClientFlightEndReason(state, requestPayload)
	local requestedReason = if type(requestPayload) == "table" and typeof(requestPayload.EndReason) == "string"
		then string.lower(requestPayload.EndReason)
		else ""
	local now = getSharedTimestamp()

	if requestedReason == "natural" and now + CLIENT_NATURAL_END_GRACE >= (state.NaturalEndAt or now) then
		return "natural"
	end

	return "early_cancel"
end

local function buildIgnoredPayload(reason, state)
	return {
		Phase = "Ignored",
		EndReason = reason,
		RuntimeId = state and state.RuntimeId or nil,
	}
end

local function clampPositiveNumber(value, fallback)
	local numericValue = tonumber(value)
	if not numericValue or numericValue <= 0 then
		return fallback
	end

	return numericValue
end

local function clampNonNegativeNumber(value, fallback)
	local numericValue = tonumber(value)
	if not numericValue or numericValue < 0 then
		return fallback
	end

	return numericValue
end

local function copyStringArray(value)
	if type(value) ~= "table" then
		return nil
	end

	local result = {}
	for _, item in ipairs(value) do
		if typeof(item) == "string" and item ~= "" then
			result[#result + 1] = item
		end
	end

	return if #result > 0 then result else nil
end

local function resolvePhoenixShieldRadius(abilityConfig)
	local configuredRadius = abilityConfig.ShieldRadius
	if configuredRadius == nil then
		configuredRadius = abilityConfig.Radius
	end

	return clampPositiveNumber(configuredRadius, DEFAULT_PHOENIX_FLAME_SHIELD_RADIUS)
end

local function estimatePhoenixFlightHeightDelay(abilityConfig, initialLift, maxRiseHeight, takeoffDuration)
	local resolvedInitialLift = math.max(0, initialLift)
	local resolvedMaxRiseHeight = math.max(resolvedInitialLift, maxRiseHeight)
	local verticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, DEFAULT_PHOENIX_VERTICAL_SPEED)

	return math.max(takeoffDuration, resolvedMaxRiseHeight / verticalSpeed)
end

local function getToriPassiveService()
	if cachedToriPassiveService then
		return cachedToriPassiveService
	end

	cachedToriPassiveService = require(script.Parent:WaitForChild("ToriPassiveService"))
	return cachedToriPassiveService
end

function ToriServer.PhoenixFlight(context)
	local abilityConfig = context.AbilityConfig
	local requestPayload = context.RequestPayload
	local activeFlight = getActiveEndCooldownState(context.Player, PHOENIX_FLIGHT_ABILITY)
	if isPhoenixFlightEndPayload(requestPayload) then
		if not activeFlight then
			toriCooldownLog(
				"%s end ignored player=%s userId=%s reason=no_active_flight",
				PHOENIX_FLIGHT_ABILITY,
				context.Player and context.Player.Name or "<nil>",
				tostring(context.Player and context.Player.UserId)
			)
			return buildIgnoredPayload("no_active_flight"), {
				ApplyCooldown = false,
				SuppressActivatedEvent = true,
			}
		end

		local endReason = resolveClientFlightEndReason(activeFlight, requestPayload)
		finishEndCooldownState(activeFlight, endReason)
		return buildIgnoredPayload(endReason, activeFlight), {
			ApplyCooldown = false,
			PreserveExistingCooldown = true,
			SuppressActivatedEvent = true,
		}
	end

	if activeFlight then
		toriCooldownLog(
			"%s start ignored player=%s userId=%s runtimeId=%s reason=already_active",
			PHOENIX_FLIGHT_ABILITY,
			context.Player and context.Player.Name or "<nil>",
			tostring(context.Player and context.Player.UserId),
			tostring(activeFlight.RuntimeId)
		)
		return buildIgnoredPayload("already_active", activeFlight), {
			ApplyCooldown = false,
			SuppressActivatedEvent = true,
		}
	end

	local duration = clampPositiveNumber(abilityConfig.Duration, DEFAULT_PHOENIX_FLIGHT_DURATION)
	local startupDuration = clampNonNegativeNumber(abilityConfig.FlightStartupDuration, DEFAULT_PHOENIX_FLIGHT_STARTUP_DURATION)
	local takeoffDuration = clampPositiveNumber(abilityConfig.TakeoffDuration, DEFAULT_PHOENIX_TAKEOFF_DURATION)
	local initialLift = clampPositiveNumber(abilityConfig.InitialLift, DEFAULT_PHOENIX_INITIAL_LIFT)
	local maxRiseHeight = clampPositiveNumber(abilityConfig.MaxRiseHeight, DEFAULT_PHOENIX_MAX_RISE_HEIGHT)
	local verticalSpeed = clampPositiveNumber(abilityConfig.VerticalSpeed, DEFAULT_PHOENIX_VERTICAL_SPEED)
	local heightDelay = estimatePhoenixFlightHeightDelay(abilityConfig, initialLift, maxRiseHeight, takeoffDuration)
	startEndCooldownState(
		context,
		PHOENIX_FLIGHT_ABILITY,
		startupDuration + heightDelay + duration,
		tonumber(abilityConfig.Cooldown) or 0,
		SERVER_NATURAL_FALLBACK_GRACE
	)

	return {
		Duration = duration,
		StartupDuration = startupDuration,
		TakeoffDuration = takeoffDuration,
		InitialLift = initialLift,
		MaxRiseHeight = maxRiseHeight,
		FlightSpeed = clampPositiveNumber(abilityConfig.FlightSpeed, DEFAULT_PHOENIX_FLIGHT_SPEED),
		FlightSpeedScaleReference = clampPositiveNumber(
			abilityConfig.FlightSpeedScaleReference,
			DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_REFERENCE
		),
		FlightSpeedScaleStrength = clampNonNegativeNumber(
			abilityConfig.FlightSpeedScaleStrength,
			DEFAULT_PHOENIX_FLIGHT_SPEED_SCALE_STRENGTH
		),
		VerticalSpeed = verticalSpeed,
		MaxDescendSpeed = clampPositiveNumber(abilityConfig.MaxDescendSpeed, DEFAULT_PHOENIX_MAX_DESCEND_SPEED),
		HorizontalResponsiveness = clampPositiveNumber(
			abilityConfig.HorizontalResponsiveness,
			DEFAULT_PHOENIX_HORIZONTAL_RESPONSIVENESS
		),
		TrailPartNames = copyStringArray(abilityConfig.FlightTrailPartNames),
		TrailOffset = typeof(abilityConfig.FlightTrailOffset) == "CFrame" and abilityConfig.FlightTrailOffset or nil,
	}, {
		ApplyCooldown = false,
	}
end

function ToriServer.PhoenixFlameShield(context)
	local abilityConfig = context.AbilityConfig
	local activeShield = getActiveEndCooldownState(context.Player, PHOENIX_SHIELD_ABILITY)
	if activeShield then
		toriCooldownLog(
			"%s start ignored player=%s userId=%s runtimeId=%s reason=already_active",
			PHOENIX_SHIELD_ABILITY,
			context.Player and context.Player.Name or "<nil>",
			tostring(context.Player and context.Player.UserId),
			tostring(activeShield.RuntimeId)
		)
		return buildIgnoredPayload("already_active", activeShield), {
			ApplyCooldown = false,
			SuppressActivatedEvent = true,
		}
	end

	local duration = clampPositiveNumber(abilityConfig.Duration, DEFAULT_PHOENIX_SHIELD_DURATION)
	startEndCooldownState(context, PHOENIX_SHIELD_ABILITY, duration, tonumber(abilityConfig.Cooldown) or 0)

	return {
		Radius = resolvePhoenixShieldRadius(abilityConfig),
		Duration = duration,
		AnimationLockDuration = clampPositiveNumber(
			abilityConfig.AnimationLockDuration,
			DEFAULT_PHOENIX_SHIELD_ANIMATION_LOCK_DURATION
		),
	}, {
		ApplyCooldown = false,
	}
end

function ToriServer.ShouldBypassCooldownCheck(selfOrContext, maybeContext)
	local context = resolveAbilityContext(selfOrContext, maybeContext)
	local activeFlight = context
		and context.AbilityName == PHOENIX_FLIGHT_ABILITY
		and isPhoenixFlightEndPayload(context.RequestPayload)
		and getActiveEndCooldownState(context.Player, PHOENIX_FLIGHT_ABILITY)
		or nil
	return activeFlight ~= nil
end

function ToriServer.ShouldBypassRequestThrottle(selfOrContext, maybeContext)
	return ToriServer.ShouldBypassCooldownCheck(selfOrContext, maybeContext)
end

function ToriServer.ClearRuntimeState(player, _fruitName, cleanupReason)
	local resolvedCleanupReason = tostring(cleanupReason or "runtime_clear")
	for _, abilityName in ipairs({ PHOENIX_FLIGHT_ABILITY, PHOENIX_SHIELD_ABILITY }) do
		local state = getActiveEndCooldownState(player, abilityName)
		if state then
			if resolvedCleanupReason == CHARACTER_REMOVING_REASON then
				finishEndCooldownState(state, resolvedCleanupReason)
			else
				abandonEndCooldownState(state, resolvedCleanupReason)
			end
		end
	end

	local passiveService = getToriPassiveService()
	if not passiveService or typeof(passiveService.ClearRuntimeState) ~= "function" then
		return false
	end

	return passiveService.ClearRuntimeState(player)
end

function ToriServer.GetLegacyHandler()
	return ToriServer
end

return ToriServer
