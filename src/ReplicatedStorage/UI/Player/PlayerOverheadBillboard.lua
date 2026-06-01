local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Shorten = require(Modules:WaitForChild("Shorten"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local Responsive = require(script.Parent.Parent:WaitForChild("Responsive"))
local IndexTheme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local TEXT = Color3.fromRGB(242, 242, 238)
local GOLD = Color3.fromRGB(242, 209, 107)
local MUTED = Color3.fromRGB(194, 203, 216)
local CYAN = Color3.fromRGB(176, 220, 255)
local SHADOW = Color3.fromRGB(0, 0, 0)

local function formatBeli(value)
	return Shorten.roundNumber(math.max(0, math.floor((tonumber(value) or 0) + 0.5))) .. CurrencyUtil.getCompactSuffix()
end

local function formatRemaining(seconds)
	local safeSeconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	local minutes = math.floor(safeSeconds / 60)
	local remainder = safeSeconds % 60
	return string.format("%d:%02d", minutes, remainder)
end

local function textRow(text, color, y, size)
	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Font = IndexTheme.Fonts.Display,
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, 0, 0, size + 6),
		Text = text,
		TextColor3 = color,
		TextSize = size,
		TextStrokeColor3 = SHADOW,
		TextStrokeTransparency = 0.18,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

local function titleRow(text, color, y, size)
	return e("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Font = IndexTheme.Fonts.Display,
		Position = UDim2.new(0.5, 0, 0, y),
		Size = UDim2.new(1, 0, 0, size + 5),
		Text = text,
		TextColor3 = color or GOLD,
		TextSize = size,
		TextStrokeColor3 = SHADOW,
		TextStrokeTransparency = 0.1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
end

local function getStatusText(entry)
	if entry.horoActive == true and tonumber(entry.horoRemaining) ~= nil then
		return "Ghost Projection " .. formatRemaining(entry.horoRemaining), CYAN
	end

	return string.format("Rebirths %d", math.max(0, math.floor(tonumber(entry.rebirths) or 0))), MUTED
end

local function isCompact()
	return Responsive.isCompact()
end

local function PlayerOverheadBillboard(props)
	local entry = props.entry or {}
	local statusText, statusColor = getStatusText(entry)
	local compact = isCompact()
	local titleDisplay = tostring(entry.titleDisplay or "")
	local hasTitle = titleDisplay ~= ""
	local nameY = 0
	local titleY = compact and 15 or 32
	local beliY = if hasTitle then (compact and 27 or 52) else (compact and 15 or 31)
	local statusY = if hasTitle then (compact and 39 or 76) else (compact and 28 or 59)

	return e("BillboardGui", {
		Adornee = entry.adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = compact and 45 or 120,
		Size = compact and UDim2.fromOffset(150, hasTitle and 56 or 44) or UDim2.fromOffset(330, hasTitle and 116 or 96),
		StudsOffsetWorldSpace = compact and Vector3.new(0, hasTitle and 2.7 or 2.45, 0) or Vector3.new(0, hasTitle and 3.25 or 3.05, 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Name = textRow(tostring(entry.playerName or "Player"), TEXT, nameY, compact and 15 or 34),
		Title = hasTitle and titleRow(titleDisplay, entry.titleColor, titleY, compact and 10 or 18) or nil,
		Beli = textRow(formatBeli(entry.balance), GOLD, beliY, compact and 11 or 24),
		Status = textRow(statusText, statusColor, statusY, compact and 8 or 18),
	})
end

return PlayerOverheadBillboard
