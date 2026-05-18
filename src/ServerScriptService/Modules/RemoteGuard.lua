local Players = game:GetService("Players")

local RemoteGuard = {}

local DEFAULT_COOLDOWN_SECONDS = 0.1
local REJECT_LOG_THROTTLE_SECONDS = 5
local playerStates = setmetatable({}, { __mode = "k" })

local function isFiniteNumber(value)
	return typeof(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function getState(player)
	local state = playerStates[player]
	if state == nil then
		state = {
			LastCallByRemote = {},
			RejectLogs = {},
		}
		playerStates[player] = state
	end
	return state
end

local function shouldLogReject(player, remoteName, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return true
	end

	local state = getState(player)
	state.RejectLogs = state.RejectLogs or {}
	local key = string.format("%s:%s", tostring(remoteName), tostring(reason))
	local now = os.clock()
	local last = state.RejectLogs[key]
	if typeof(last) == "number" and (now - last) < REJECT_LOG_THROTTLE_SECONDS then
		return false
	end

	state.RejectLogs[key] = now
	return true
end

local function reject(player, remoteName, reason, detail)
	if shouldLogReject(player, remoteName, reason) then
		warn(string.format(
			"[RemoteGuard] rejected remote=%s player=%s userId=%s reason=%s detail=%s",
			tostring(remoteName),
			player and player.Name or "<nil>",
			player and tostring(player.UserId) or "<nil>",
			tostring(reason),
			tostring(detail or "")
		))
	end
	return false, reason
end

local function validateType(value, expectedType)
	if expectedType == nil or expectedType == "any" then
		return true
	end
	if expectedType == "finiteNumber" then
		return isFiniteNumber(value)
	end
	return typeof(value) == expectedType
end

local function validateArg(player, remoteName, index, value, spec)
	if spec == nil then
		return true
	end

	if value == nil and spec.AllowNil == true then
		return true
	end

	local expectedType = spec.Type
	if not validateType(value, expectedType) then
		return reject(player, remoteName, "bad_type", string.format("arg=%d expected=%s actual=%s", index, tostring(expectedType), typeof(value)))
	end

	if expectedType == "string" then
		local maxLength = tonumber(spec.MaxLength)
		if maxLength and #value > maxLength then
			return reject(player, remoteName, "string_too_long", string.format("arg=%d max=%d actual=%d", index, maxLength, #value))
		end
	end

	if expectedType == "number" or expectedType == "finiteNumber" then
		if not isFiniteNumber(value) then
			return reject(player, remoteName, "non_finite_number", string.format("arg=%d", index))
		end
		if spec.Integer == true and value ~= math.floor(value) then
			return reject(player, remoteName, "non_integer_number", string.format("arg=%d value=%s", index, tostring(value)))
		end
		local minValue = tonumber(spec.Min)
		if minValue and value < minValue then
			return reject(player, remoteName, "number_too_small", string.format("arg=%d min=%s value=%s", index, tostring(minValue), tostring(value)))
		end
		local maxValue = tonumber(spec.Max)
		if maxValue and value > maxValue then
			return reject(player, remoteName, "number_too_large", string.format("arg=%d max=%s value=%s", index, tostring(maxValue), tostring(value)))
		end
	end

	if spec.Allowlist ~= nil and spec.Allowlist[value] ~= true then
		return reject(player, remoteName, "not_allowlisted", string.format("arg=%d value=%s", index, tostring(value)))
	end

	return true
end

function RemoteGuard.Check(player, remoteName, args, options)
	options = if type(options) == "table" then options else {}
	args = if type(args) == "table" then args else {}
	remoteName = tostring(remoteName or "UnknownRemote")

	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return reject(player, remoteName, "invalid_player")
	end

	local cooldown = tonumber(options.Cooldown)
	if cooldown == nil then
		cooldown = DEFAULT_COOLDOWN_SECONDS
	end
	if cooldown > 0 then
		local state = getState(player)
		local now = os.clock()
		local last = state.LastCallByRemote[remoteName]
		if typeof(last) == "number" and (now - last) < cooldown then
			return reject(player, remoteName, "cooldown", string.format("remaining=%.3f", cooldown - (now - last)))
		end
		state.LastCallByRemote[remoteName] = now
	end

	local argSpecs = if type(options.Args) == "table" then options.Args else {}
	for index, spec in ipairs(argSpecs) do
		local ok, reason = validateArg(player, remoteName, index, args[index], spec)
		if not ok then
			return false, reason
		end
	end

	local actionIndex = tonumber(options.ActionIndex)
	if actionIndex and type(options.ActionAllowlist) == "table" then
		local action = args[actionIndex]
		if options.ActionAllowlist[action] ~= true then
			return reject(player, remoteName, "action_not_allowlisted", string.format("arg=%d action=%s", actionIndex, tostring(action)))
		end
	end

	return true, nil
end

function RemoteGuard.CleanupPlayer(player)
	playerStates[player] = nil
end

Players.PlayerRemoving:Connect(RemoteGuard.CleanupPlayer)

return RemoteGuard
