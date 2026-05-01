local Players = game:GetService("Players")

local DevilFruitRequestGuard = {}

local SETTINGS = {
	DebugEnabled = false,
	LogThrottleSeconds = 2,
	GlobalMinInterval = 0.05,
	DefaultAbilityMinInterval = 0.12,
	BurstWindow = 1.25,
	BurstLimit = 8,
	TemporaryIgnoreThreshold = 8,
	TemporaryIgnoreDuration = 2.5,
	KickEnabled = false,
	KickThreshold = 24,
	MaxAbilityNameLength = 48,
	MaxPayloadKeys = 4,
	MaxPayloadKeyLength = 32,
	MaxPayloadStringLength = 64,
	MaxAbsVectorComponent = 100000,
}

local SUSPICION_WEIGHTS = {
	InvalidAbilityName = 2,
	MalformedPayloadType = 2,
	PayloadTooLarge = 2,
	PayloadInvalidKey = 2,
	PayloadUnexpected = 2,
	PayloadUnknownField = 2,
	PayloadInvalidValue = 2,
	GlobalRateLimited = 1,
	BurstLimited = 2,
	PerAbilityRateLimited = 1,
	NoFruit = 1,
	UnknownAbility = 2,
	InvalidContext = 1,
	InvalidTargetHint = 1,
	OutOfRangeTargetHint = 2,
	OutOfRangeAimHint = 1,
}

local playerStates = setmetatable({}, { __mode = "k" })

local function debugLog(...)
	if SETTINGS.DebugEnabled then
		print("[DevilFruitRequestGuard]", ...)
	end
end

local function isFiniteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function getPlayerState(player)
	local state = playerStates[player]
	if not state then
		state = {
			LastRequestAt = 0,
			BurstStartedAt = 0,
			BurstCount = 0,
			SuspicionScore = 0,
			LastSuspicionAt = 0,
			IgnoreUntil = 0,
			RequestThrottle = {},
			LastLogAtByKey = {},
		}
		playerStates[player] = state
	end

	return state
end

local function shouldLogNow(state, key, now)
	local lastAt = state.LastLogAtByKey[key]
	if type(lastAt) == "number" and (now - lastAt) < SETTINGS.LogThrottleSeconds then
		return false
	end

	state.LastLogAtByKey[key] = now
	return true
end

local function logSuspicious(player, state, reason, detail, now)
	if not shouldLogNow(state, "suspicious:" .. tostring(reason), now) then
		return
	end

	warn(string.format(
		"[DevilFruitRequestGuard] suspicious player=%s userId=%s reason=%s detail=%s score=%.2f",
		player.Name,
		tostring(player.UserId),
		tostring(reason),
		tostring(detail or ""),
		state.SuspicionScore
	))
end

local function decaySuspicion(state, now)
	local lastAt = state.LastSuspicionAt
	if type(lastAt) ~= "number" or lastAt <= 0 then
		return
	end

	local elapsed = math.max(0, now - lastAt)
	if elapsed <= 0 then
		return
	end

	local decayedScore = math.max(0, state.SuspicionScore - (elapsed * 0.35))
	state.SuspicionScore = decayedScore
	state.LastSuspicionAt = now
end

local function addSuspicion(player, reason, detail, customWeight)
	local state = getPlayerState(player)
	local now = os.clock()
	decaySuspicion(state, now)

	local weight = tonumber(customWeight) or SUSPICION_WEIGHTS[reason] or 0
	if weight <= 0 then
		if SETTINGS.DebugEnabled and shouldLogNow(state, "debug:" .. tostring(reason), now) then
			debugLog(
				string.format(
					"rejected player=%s reason=%s detail=%s",
					player.Name,
					tostring(reason),
					tostring(detail or "")
				)
			)
		end
		return
	end

	state.SuspicionScore += weight
	state.LastSuspicionAt = now
	logSuspicious(player, state, reason, detail, now)

	if state.SuspicionScore >= SETTINGS.TemporaryIgnoreThreshold then
		state.IgnoreUntil = math.max(state.IgnoreUntil or 0, now + SETTINGS.TemporaryIgnoreDuration)
	end

	if SETTINGS.KickEnabled and state.SuspicionScore >= SETTINGS.KickThreshold then
		task.spawn(function()
			if player.Parent == Players then
				player:Kick("Repeated invalid Devil Fruit ability requests.")
			end
		end)
	end
end

local function countPayloadKeys(payload)
	local keyCount = 0
	for key in pairs(payload) do
		keyCount += 1
		if keyCount > SETTINGS.MaxPayloadKeys then
			break
		end
	end

	return keyCount
end

local function reservePerAbilityThrottle(player, fruitName, abilityName, abilityConfig)
	local throttleWindow = math.max(0, tonumber(abilityConfig.ServerRequestThrottle) or SETTINGS.DefaultAbilityMinInterval)
	if throttleWindow <= 0 then
		return true, 0
	end

	local state = getPlayerState(player)
	local throttleKey = string.format("%s::%s", tostring(fruitName), tostring(abilityName))
	local now = os.clock()
	local nextAllowedAt = state.RequestThrottle[throttleKey]
	if type(nextAllowedAt) == "number" and now < nextAllowedAt then
		addSuspicion(player, "PerAbilityRateLimited", throttleKey)
		return false, nextAllowedAt
	end

	local reservedUntil = now + throttleWindow
	state.RequestThrottle[throttleKey] = reservedUntil
	return true, reservedUntil
end

local function validateVector3(value)
	if typeof(value) ~= "Vector3" then
		return false
	end

	return isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
		and math.abs(value.X) <= SETTINGS.MaxAbsVectorComponent
		and math.abs(value.Y) <= SETTINGS.MaxAbsVectorComponent
		and math.abs(value.Z) <= SETTINGS.MaxAbsVectorComponent
end

local function validateUserId(value)
	return typeof(value) == "number" and value >= 1 and math.floor(value) == value
end

local function sanitizePayloadBySchema(player, payload, schema, characterState)
	if payload == nil or next(payload) == nil then
		return true, nil, nil, 0
	end

	if typeof(payload) ~= "table" then
		addSuspicion(player, "MalformedPayloadType", typeof(payload))
		return false, nil, "MalformedPayload", 0
	end

	if countPayloadKeys(payload) > math.max(0, tonumber(schema.MaxKeys) or SETTINGS.MaxPayloadKeys) then
		addSuspicion(player, "PayloadTooLarge")
		return false, nil, "PayloadTooLarge", 0
	end

	local fields = type(schema.Fields) == "table" and schema.Fields or {}
	local sanitized = {}

	for key, value in pairs(payload) do
		if typeof(key) ~= "string" or key == "" or #key > SETTINGS.MaxPayloadKeyLength then
			addSuspicion(player, "PayloadInvalidKey", tostring(key))
			return false, nil, "MalformedPayload", 0
		end

		local expectedType = fields[key]
		if expectedType == nil then
			addSuspicion(player, "PayloadUnknownField", key)
			return false, nil, "UnexpectedPayload", 0
		end

		if expectedType == "Vector3" then
			if not validateVector3(value) then
				addSuspicion(player, "PayloadInvalidValue", key)
				return false, nil, "MalformedPayload", 0
			end

			local rootPart = characterState and characterState.RootPart
			local maxHintDistance = math.max(0, tonumber(schema.MaxHintDistance) or 0)
			if rootPart and maxHintDistance > 0 and (value - rootPart.Position).Magnitude > maxHintDistance then
				addSuspicion(player, "OutOfRangeAimHint", key)
				return false, nil, "OutOfRange", 0
			end

			sanitized[key] = value
		elseif expectedType == "DirectionVector3" then
			if not validateVector3(value) or value.Magnitude <= 0.01 or value.Magnitude > 1.1 then
				addSuspicion(player, "PayloadInvalidValue", key)
				return false, nil, "MalformedPayload", 0
			end

			sanitized[key] = value
		elseif expectedType == "UserId" then
			if not validateUserId(value) then
				addSuspicion(player, "PayloadInvalidValue", key)
				return false, nil, "MalformedPayload", 0
			end

			sanitized[key] = value
		elseif expectedType == "String" then
			if typeof(value) ~= "string" or #value > SETTINGS.MaxPayloadStringLength then
				addSuspicion(player, "PayloadInvalidValue", key)
				return false, nil, "MalformedPayload", 0
			end

			sanitized[key] = value
		else
			addSuspicion(player, "PayloadInvalidValue", key)
			return false, nil, "MalformedPayload", 0
		end
	end

	return true, sanitized, nil, 0
end

local function getPlanarSpeed(rootPart)
	if not rootPart then
		return 0
	end

	local velocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function getSpeedScaledRubberLaunchDistance(abilityConfig, rootPart)
	local resolvedConfig = type(abilityConfig) == "table" and abilityConfig or {}
	local baseDistance = math.max(0, tonumber(resolvedConfig.LaunchDistance) or 0)
	local speedDistanceBonus = math.max(0, tonumber(resolvedConfig.SpeedLaunchDistanceBonus) or 0)
	if speedDistanceBonus <= 0 then
		return baseDistance
	end

	local referenceSpeed = math.max(1, tonumber(resolvedConfig.SpeedScaleReference) or 70)
	local speedAlpha = math.clamp(getPlanarSpeed(rootPart) / referenceSpeed, 0, 1)
	return baseDistance + (speedDistanceBonus * speedAlpha)
end

local function validateRubberLaunchHints(player, abilityConfig, sanitizedPayload, characterState)
	if type(sanitizedPayload) ~= "table" then
		return true, sanitizedPayload, nil, 0
	end

	local targetPlayerUserId = sanitizedPayload.TargetPlayerUserId
	if targetPlayerUserId == nil then
		return true, sanitizedPayload, nil, 0
	end

	local targetPlayer = Players:GetPlayerByUserId(targetPlayerUserId)
	local requesterRoot = characterState and characterState.RootPart
	if not requesterRoot or not targetPlayer or targetPlayer == player then
		addSuspicion(player, "InvalidTargetHint", targetPlayerUserId)
		return false, nil, "MalformedPayload", 0
	end

	local targetCharacter = targetPlayer.Character
	local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
	local targetRootPart = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHumanoid or not targetRootPart or targetHumanoid.Health <= 0 then
		addSuspicion(player, "InvalidTargetHint", targetPlayerUserId)
		return false, nil, "MalformedPayload", 0
	end

	local maxDistance = getSpeedScaledRubberLaunchDistance(abilityConfig, requesterRoot) + 12
	if maxDistance > 0 and (targetRootPart.Position - requesterRoot.Position).Magnitude > maxDistance then
		addSuspicion(player, "OutOfRangeTargetHint", targetPlayerUserId)
		return false, nil, "OutOfRange", 0
	end

	return true, sanitizedPayload, nil, 0
end

function DevilFruitRequestGuard.CleanupPlayer(player)
	playerStates[player] = nil
end

function DevilFruitRequestGuard.Preflight(player, abilityName, requestPayload)
	if not player or not player:IsA("Player") or player.Parent ~= Players then
		return false, "InvalidPlayer", 0
	end

	local state = getPlayerState(player)
	local now = os.clock()
	decaySuspicion(state, now)

	if type(state.IgnoreUntil) == "number" and now < state.IgnoreUntil then
		if shouldLogNow(state, "ignored", now) then
			debugLog(string.format("ignoring player=%s until=%.2f", player.Name, state.IgnoreUntil))
		end
		return false, "TemporarilyIgnored", state.IgnoreUntil
	end

	if state.LastRequestAt > 0 and (now - state.LastRequestAt) < SETTINGS.GlobalMinInterval then
		addSuspicion(player, "GlobalRateLimited", abilityName)
		return false, "RateLimited", state.LastRequestAt + SETTINGS.GlobalMinInterval
	end

	state.LastRequestAt = now
	if state.BurstStartedAt <= 0 or (now - state.BurstStartedAt) > SETTINGS.BurstWindow then
		state.BurstStartedAt = now
		state.BurstCount = 1
	else
		state.BurstCount += 1
		if state.BurstCount > SETTINGS.BurstLimit then
			addSuspicion(player, "BurstLimited", abilityName)
			return false, "BurstLimited", state.BurstStartedAt + SETTINGS.BurstWindow
		end
	end

	if typeof(abilityName) ~= "string" or abilityName == "" or #abilityName > SETTINGS.MaxAbilityNameLength then
		addSuspicion(player, "InvalidAbilityName", tostring(abilityName))
		return false, "InvalidAbilityName", 0
	end

	if not abilityName:match("^[%w_]+$") then
		addSuspicion(player, "InvalidAbilityName", abilityName)
		return false, "InvalidAbilityName", 0
	end

	if requestPayload ~= nil and typeof(requestPayload) ~= "table" then
		addSuspicion(player, "MalformedPayloadType", typeof(requestPayload))
		return false, "MalformedPayload", 0
	end

	if typeof(requestPayload) == "table" and countPayloadKeys(requestPayload) > SETTINGS.MaxPayloadKeys then
		addSuspicion(player, "PayloadTooLarge")
		return false, "PayloadTooLarge", 0
	end

	return true, nil, 0
end

function DevilFruitRequestGuard.ValidateAndReserve(player, fruitName, abilityName, abilityConfig, requestPayload, characterState, options)
	local bypassRequestThrottle = type(options) == "table" and options.BypassRequestThrottle == true
	local nextAllowedAt = 0
	if not bypassRequestThrottle then
		local requestAllowed, reservedUntil = reservePerAbilityThrottle(player, fruitName, abilityName, abilityConfig)
		if not requestAllowed then
			return false, nil, "Throttled", reservedUntil
		end

		nextAllowedAt = reservedUntil
	end

	local schema = type(abilityConfig) == "table" and abilityConfig.RequestPayloadSchema or nil
	if type(schema) ~= "table" then
		if requestPayload ~= nil and typeof(requestPayload) == "table" and next(requestPayload) ~= nil then
			addSuspicion(player, "PayloadUnexpected", abilityName)
			return false, nil, "UnexpectedPayload", 0
		end

		return true, nil, nil, nextAllowedAt
	end

	local payloadOk, sanitizedPayload, reason, readyAt = sanitizePayloadBySchema(player, requestPayload, schema, characterState)
	if not payloadOk then
		return false, nil, reason, readyAt
	end

	if fruitName == "Gomu Gomu no Mi" and abilityName == "RubberLaunch" then
		return validateRubberLaunchHints(player, abilityConfig, sanitizedPayload, characterState)
	end

	return true, sanitizedPayload, nil, nextAllowedAt
end

function DevilFruitRequestGuard.RecordRejection(player, reason, detail)
	if not player or not player:IsA("Player") then
		return
	end

	addSuspicion(player, reason, detail)
end

function DevilFruitRequestGuard.RecordAccepted(player, fruitName, abilityName)
	if not SETTINGS.DebugEnabled or not player or not player:IsA("Player") then
		return
	end

	local state = getPlayerState(player)
	local now = os.clock()
	if shouldLogNow(state, "accepted:" .. tostring(abilityName), now) then
		debugLog(string.format(
			"accepted player=%s fruit=%s ability=%s",
			player.Name,
			tostring(fruitName),
			tostring(abilityName)
		))
	end
end

function DevilFruitRequestGuard.RecordSuspicious(player, reason, detail, weight)
	if not player or not player:IsA("Player") then
		return
	end

	addSuspicion(player, reason, detail, weight)
end

return DevilFruitRequestGuard
