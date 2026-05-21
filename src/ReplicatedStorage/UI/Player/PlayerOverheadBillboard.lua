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

	return e("BillboardGui", {
		Adornee = entry.adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = compact and 45 or 120,
		Size = compact and UDim2.fromOffset(150, 44) or UDim2.fromOffset(330, 96),
		StudsOffsetWorldSpace = compact and Vector3.new(0, 2.45, 0) or Vector3.new(0, 3.05, 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Name = textRow(tostring(entry.playerName or "Player"), TEXT, 0, compact and 15 or 34),
		Beli = textRow(formatBeli(entry.balance), GOLD, compact and 15 or 31, compact and 11 or 24),
		Status = textRow(statusText, statusColor, compact and 28 or 59, compact and 8 or 18),
	})
end

return PlayerOverheadBillboard
