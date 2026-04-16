local DiagnosticLogLimiter = {}

local lastEmissionByKey = {}

local function normalizeScope(scope)
	return tostring(scope or "default")
end

function DiagnosticLogLimiter.BuildKey(message, ...)
	local key = tostring(message or "<nil>")
	local argCount = select("#", ...)
	for index = 1, math.min(argCount, 2) do
		key ..= "::" .. tostring(select(index, ...))
	end

	return key
end

function DiagnosticLogLimiter.ShouldEmit(scope, key, cooldownSeconds)
	local now = os.clock()
	local resolvedCooldown = math.max(0, tonumber(cooldownSeconds) or 0)
	local resolvedKey = normalizeScope(scope) .. "::" .. tostring(key or "<nil>")
	local lastEmission = lastEmissionByKey[resolvedKey]
	if lastEmission and (now - lastEmission) < resolvedCooldown then
		return false
	end

	lastEmissionByKey[resolvedKey] = now
	return true
end

function DiagnosticLogLimiter.StartsWithAny(message, prefixes)
	local text = tostring(message or "")
	for _, prefix in ipairs(prefixes or {}) do
		if typeof(prefix) == "string" and prefix ~= "" and string.sub(text, 1, #prefix) == prefix then
			return true
		end
	end

	return false
end

return DiagnosticLogLimiter
