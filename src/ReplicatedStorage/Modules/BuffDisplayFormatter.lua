local BuffDisplayFormatter = {}

local function trimTrailingZeros(text)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

function BuffDisplayFormatter.formatMultiplier(multiplier)
	local numericMultiplier = tonumber(multiplier) or 1
	local roundedMultiplier = math.floor((numericMultiplier * 100) + 0.5) / 100
	return "x" .. trimTrailingZeros(string.format("%.2f", roundedMultiplier))
end

function BuffDisplayFormatter.formatMultiplierLabel(multiplier, label)
	local suffix = tostring(label or "")
	if suffix == "" then
		return BuffDisplayFormatter.formatMultiplier(multiplier)
	end

	return BuffDisplayFormatter.formatMultiplier(multiplier) .. " " .. suffix
end

return BuffDisplayFormatter
