local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local AppClientFormatters = {}

function AppClientFormatters.trim(text)
	return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function AppClientFormatters.matchesQuery(entry, query)
	if query == "" then
		return true
	end

	local haystack = string.lower(table.concat({
		tostring(entry.displayName or ""),
		tostring(entry.subtitle or ""),
		tostring(entry.footer or ""),
		tostring(entry.description or ""),
		tostring(entry.requirementText or ""),
		tostring(entry.stateText or ""),
	}, " "))

	return string.find(haystack, string.lower(query), 1, true) ~= nil
end

function AppClientFormatters.shortName(text)
	local value = tostring(text or "")
	if #value <= 12 then
		return value
	end
	return string.sub(value, 1, 11) .. "..."
end

function AppClientFormatters.formatIncomeNumber(value)
	return CurrencyUtil.formatCurrency(value)
end

function AppClientFormatters.formatDuration(seconds)
	local totalSeconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	if hours > 0 then
		return string.format("%dh %02dm", hours, minutes)
	end
	return string.format("%dm", minutes)
end

function AppClientFormatters.formatMultiplier(value)
	local rounded = math.floor((tonumber(value) or 1) * 100 + 0.5) / 100
	return string.format("%.2fx", rounded)
end

return AppClientFormatters
