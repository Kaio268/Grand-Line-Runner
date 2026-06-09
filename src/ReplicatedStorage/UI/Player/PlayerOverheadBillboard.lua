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

local REFERENCE_VIEWPORT = Vector2.new(1920, 1080)
local MIN_SCALE = 0.48
local BASE_SIZE = Vector2.new(330, 96)
local BASE_ROW_Y = {
	Name = 0,
	Beli = 31,
	Status = 59,
}
local BASE_TEXT_SIZE = {
	Name = 34,
	Beli = 24,
	Status = 18,
}
local MIN_TEXT_SIZE = {
	Name = 15,
	Beli = 11,
	Status = 8,
}
local BASE_STUDS_OFFSET_Y = 3.05
local MIN_STUDS_OFFSET_Y = 2.35
local BASE_MAX_DISTANCE = 120
local MIN_MAX_DISTANCE = 45

local function roundOffset(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function getViewportScale()
	local viewport = Responsive.getViewportSize()
	local rawScale = math.min(viewport.X / REFERENCE_VIEWPORT.X, viewport.Y / REFERENCE_VIEWPORT.Y)
	return math.clamp(rawScale, MIN_SCALE, 1)
end

local function scaleOffset(value, scale)
	return roundOffset((tonumber(value) or 0) * scale)
end

local function scaleTextSize(key, scale)
	return math.max(MIN_TEXT_SIZE[key], scaleOffset(BASE_TEXT_SIZE[key], scale))
end

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

local function PlayerOverheadBillboard(props)
	local entry = props.entry or {}
	local statusText, statusColor = getStatusText(entry)
	local scale = getViewportScale()
	local nameTextSize = scaleTextSize("Name", scale)
	local beliTextSize = scaleTextSize("Beli", scale)
	local statusTextSize = scaleTextSize("Status", scale)

	return e("BillboardGui", {
		Adornee = entry.adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = math.clamp(BASE_MAX_DISTANCE * scale, MIN_MAX_DISTANCE, BASE_MAX_DISTANCE),
		Size = UDim2.fromOffset(scaleOffset(BASE_SIZE.X, scale), scaleOffset(BASE_SIZE.Y, scale)),
		StudsOffsetWorldSpace = Vector3.new(0, math.max(MIN_STUDS_OFFSET_Y, BASE_STUDS_OFFSET_Y * scale), 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Name = textRow(tostring(entry.playerName or "Player"), TEXT, scaleOffset(BASE_ROW_Y.Name, scale), nameTextSize),
		Beli = textRow(formatBeli(entry.balance), GOLD, scaleOffset(BASE_ROW_Y.Beli, scale), beliTextSize),
		Status = textRow(statusText, statusColor, scaleOffset(BASE_ROW_Y.Status, scale), statusTextSize),
	})
end

return PlayerOverheadBillboard
