local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Shorten = require(Modules:WaitForChild("Shorten"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local Titles = require(Modules:WaitForChild("Configs"):WaitForChild("Titles"))
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
local BASE_TITLE_SIZE = Vector2.new(360, 144)
local BASE_ROW_PADDING = 4
local BASE_TEXT_SIZE = {
	Title = 38,
	Name = 34,
	Beli = 24,
	Status = 18,
}
local MIN_TEXT_SIZE = {
	Title = 17,
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

local function labelHeight(textSize)
	return math.max(1, textSize + 6)
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

local function makeColorSequence(colors)
	if typeof(colors) ~= "table" or #colors <= 0 then
		return nil
	end

	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end

	local keypoints = {}
	for index, color in ipairs(colors) do
		if typeof(color) == "Color3" then
			local position = if #colors == 1 then 0 else (index - 1) / (#colors - 1)
			keypoints[#keypoints + 1] = ColorSequenceKeypoint.new(position, color)
		end
	end

	return if #keypoints >= 2 then ColorSequence.new(keypoints) else nil
end

local function titleGradient(style, now)
	local colors = style and style.GradientColors
	local colorSequence = makeColorSequence(colors)
	if not colorSequence then
		return nil
	end

	local effect = tostring(style.Effect or "None")
	local speed = math.max(0, tonumber(style.AnimationSpeed) or 0)
	local phase = if speed > 0 then (now * speed) % 1 else 0
	local animated = effect == "Shimmer" or effect == "AnimatedGradient" or effect == "Rainbow"

	return e("UIGradient", {
		Color = colorSequence,
		Offset = if animated then Vector2.new((phase * 2) - 1, 0) else Vector2.zero,
		Rotation = if effect == "Rainbow" then 12 else 0,
	})
end

local function textRow(text, color, size, layoutOrder, options)
	options = options or {}
	return e("TextLabel", {
		BackgroundTransparency = 1,
		Font = IndexTheme.Fonts.Display,
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, labelHeight(size)),
		Text = text,
		TextColor3 = color,
		TextSize = size,
		TextStrokeColor3 = SHADOW,
		TextStrokeTransparency = math.clamp(tonumber(options.StrokeTransparency) or 0.18, 0, 1),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextXAlignment = Enum.TextXAlignment.Center,
	}, options.Children)
end

local function getTitleStyle(entry)
	local titleId = tostring(entry.equippedTitleId or "")
	if titleId == "" then
		return nil
	end

	return Titles.ResolveDisplayStyle(titleId)
end

local function getTitleChildren(style, now)
	return {
		Gradient = titleGradient(style, now),
	}
end

local function titleTextRow(style, now, size)
	if not style then
		return nil
	end

	local hasGradient = typeof(style.GradientColors) == "table" and #style.GradientColors > 0
	return textRow(style.DisplayName, if hasGradient then Color3.new(1, 1, 1) else style.Color, size, 1, {
		StrokeTransparency = style.StrokeTransparency,
		Children = getTitleChildren(style, now),
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
	local titleTextSize = scaleTextSize("Title", scale)
	local titleStyle = getTitleStyle(entry)
	local hasTitle = titleStyle ~= nil
	local baseSize = if hasTitle then BASE_TITLE_SIZE else BASE_SIZE
	local now = tonumber(entry.now) or 0

	return e("BillboardGui", {
		Adornee = entry.adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = math.clamp(BASE_MAX_DISTANCE * scale, MIN_MAX_DISTANCE, BASE_MAX_DISTANCE),
		Size = UDim2.fromOffset(scaleOffset(baseSize.X, scale), scaleOffset(baseSize.Y, scale)),
		StudsOffsetWorldSpace = Vector3.new(0, math.max(MIN_STUDS_OFFSET_Y, BASE_STUDS_OFFSET_Y * scale), 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Stack = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
		}, {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, scaleOffset(BASE_ROW_PADDING, scale)),
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			Title = if hasTitle then titleTextRow(titleStyle, now, titleTextSize) else nil,
			Name = textRow(tostring(entry.playerName or "Player"), TEXT, nameTextSize, 2),
			Beli = textRow(formatBeli(entry.balance), GOLD, beliTextSize, 3),
			Status = textRow(statusText, statusColor, statusTextSize, 4),
		}),
	})
end

return PlayerOverheadBillboard
