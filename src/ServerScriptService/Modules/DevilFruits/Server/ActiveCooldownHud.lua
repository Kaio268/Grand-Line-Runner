local Workspace = game:GetService("Workspace")

local ActiveCooldownHud = {}

local HUD_PHASE_ACTIVE = "Active"

local function getNow()
	return Workspace:GetServerTimeNow()
end

local function clonePayload(payload)
	local result = {}
	if typeof(payload) ~= "table" then
		return result
	end

	for key, value in pairs(payload) do
		result[key] = value
	end
	return result
end

local function nonNegativeNumber(value, fallback)
	local numericValue = tonumber(value)
	if numericValue == nil then
		numericValue = tonumber(fallback) or 0
	end
	return math.max(0, numericValue)
end

function ActiveCooldownHud.BuildActivePayload(payload, options)
	options = if type(options) == "table" then options else {}
	local result = clonePayload(payload)

	local startedAt = tonumber(options.StartedAt) or tonumber(result.StartedAt) or getNow()
	local countdownStartsAt = tonumber(options.ActiveCountdownStartsAt)
		or tonumber(options.CountdownStartsAt)
		or tonumber(result.ActiveCountdownStartsAt)
		or tonumber(result.CountdownStartsAt)
		or startedAt
	countdownStartsAt = math.max(startedAt, countdownStartsAt)

	local activeDuration = tonumber(options.ActiveDuration) or tonumber(result.ActiveDuration)
	local activeEndsAt = tonumber(options.ActiveEndsAt)
		or tonumber(options.EndTime)
		or tonumber(result.ActiveEndsAt)
		or tonumber(result.EndTime)
	if activeEndsAt == nil and activeDuration ~= nil then
		activeEndsAt = countdownStartsAt + activeDuration
	end
	activeEndsAt = tonumber(activeEndsAt) or startedAt
	activeDuration = nonNegativeNumber(activeDuration, activeEndsAt - countdownStartsAt)

	local cooldownStartsAt = tonumber(options.CooldownStartsAt) or activeEndsAt
	local cooldownDuration = nonNegativeNumber(options.CooldownDuration or result.CooldownDuration, 0)
	local cooldownReadyAt = tonumber(options.CooldownReadyAt) or tonumber(result.CooldownReadyAt)
	if cooldownReadyAt == nil and cooldownDuration > 0 then
		cooldownReadyAt = cooldownStartsAt + cooldownDuration
	end

	result.HudPhase = HUD_PHASE_ACTIVE
	result.ActiveStartsAt = startedAt
	result.ActiveCountdownStartsAt = countdownStartsAt
	result.CountdownStartsAt = countdownStartsAt
	result.ActiveEndsAt = activeEndsAt
	result.ActiveDuration = activeDuration
	result.CooldownStartsAt = cooldownStartsAt
	result.CooldownDuration = cooldownDuration
	result.CooldownReadyAt = cooldownReadyAt

	if options.RuntimeId ~= nil then
		result.RuntimeId = options.RuntimeId
	end

	return result
end

function ActiveCooldownHud.BuildCooldownStartedPayload(payload, options)
	options = if type(options) == "table" then options else {}
	local result = clonePayload(payload)
	local endedAt = tonumber(options.EndedAt) or tonumber(result.EndedAt) or getNow()
	local cooldownDuration = nonNegativeNumber(options.CooldownDuration or result.CooldownDuration, 0)
	local cooldownStartsAt = tonumber(options.CooldownStartsAt) or endedAt

	result.HudPhase = nil
	result.EndedAt = endedAt
	result.CooldownStartsAt = cooldownStartsAt
	result.CooldownDuration = cooldownDuration
	result.CooldownReadyAt = tonumber(options.CooldownReadyAt) or (cooldownStartsAt + cooldownDuration)

	if options.RuntimeId ~= nil then
		result.RuntimeId = options.RuntimeId
	end

	return result
end

function ActiveCooldownHud.BuildReadyPayload(payload, options)
	options = if type(options) == "table" then options else {}
	local result = clonePayload(payload)

	result.HudPhase = nil
	result.EndedAt = tonumber(options.EndedAt) or tonumber(result.EndedAt) or getNow()
	result.CooldownStartsAt = nil
	result.CooldownDuration = nil
	result.CooldownReadyAt = nil

	if options.Phase ~= nil then
		result.Phase = options.Phase
	end
	if options.Reason ~= nil and result.ResolveReason == nil then
		result.ResolveReason = options.Reason
	end
	if options.RuntimeId ~= nil then
		result.RuntimeId = options.RuntimeId
	end

	return result
end

return ActiveCooldownHud
