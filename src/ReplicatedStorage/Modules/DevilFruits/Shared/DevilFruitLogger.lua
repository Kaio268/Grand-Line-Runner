local DevilFruitLogger = {}

local function buildPrefix(scope, level)
	local prefix = "[DEVILFRUIT " .. string.upper(tostring(scope or "SYSTEM")) .. "]"
	if level == "WARN" then
		return prefix .. "[WARN]"
	end
	if level == "ERROR" then
		return prefix .. "[ERROR]"
	end

	return prefix
end

function DevilFruitLogger.Info(scope, message, ...)
	print(string.format(buildPrefix(scope, "INFO") .. " " .. message, ...))
end

function DevilFruitLogger.Warn(scope, message, ...)
	warn(string.format(buildPrefix(scope, "WARN") .. " " .. message, ...))
end

function DevilFruitLogger.Error(scope, message, ...)
	warn(string.format(buildPrefix(scope, "ERROR") .. " " .. message, ...))
end

return DevilFruitLogger
