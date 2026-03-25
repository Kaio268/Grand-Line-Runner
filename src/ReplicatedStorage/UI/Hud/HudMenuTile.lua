local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))

local e = React.createElement

local FALLBACK_TITLE_STYLE = {
	anchorPoint = Vector2.new(0.5, 1),
	position = UDim2.new(0.5, 0, 1, -6),
	size = UDim2.new(1, -12, 0, 22),
	textColor3 = Color3.fromRGB(255, 250, 240),
	textStrokeColor3 = Color3.fromRGB(6, 10, 18),
	textStrokeTransparency = 0.02,
	textSize = 16,
	font = Enum.Font.GothamBold,
	textXAlignment = Enum.TextXAlignment.Center,
	textYAlignment = Enum.TextYAlignment.Center,
	textTransparency = 0,
	backgroundTransparency = 1,
	zIndex = 12,
}

local FALLBACK_ICON_STYLE = {
	anchorPoint = Vector2.new(0.5, 0.5),
	position = UDim2.new(0.5, 0, 0.42, 0),
	size = UDim2.new(0, 40, 0, 40),
	imageColor3 = Color3.fromRGB(255, 255, 255),
	imageTransparency = 0,
	backgroundTransparency = 1,
	zIndex = 6,
}

local TITLE_BAND_STYLE = {
	anchorPoint = Vector2.new(0.5, 1),
	position = UDim2.new(0.5, 0, 1, -4),
	size = UDim2.new(1, -8, 0, 28),
	zIndex = 10,
}

local function renderVisualImage(name, style)
	if typeof(style) ~= "table" then
		return nil
	end

	local image = tostring(style.image or "")
	if image == "" then
		return nil
	end

	return e("ImageLabel", {
		Name = name,
		AnchorPoint = style.anchorPoint,
		BackgroundColor3 = style.backgroundColor3,
		BackgroundTransparency = style.backgroundTransparency,
		BorderSizePixel = 0,
		Image = image,
		ImageColor3 = style.imageColor3,
		ImageRectOffset = style.imageRectOffset,
		ImageRectSize = style.imageRectSize,
		ImageTransparency = style.imageTransparency,
		Position = style.position,
		Rotation = style.rotation,
		ScaleType = style.scaleType,
		Size = style.size,
		SliceCenter = style.sliceCenter,
		SliceScale = style.sliceScale,
		ZIndex = style.zIndex,
	}, style.cornerRadius and {
		Corner = e("UICorner", {
			CornerRadius = style.cornerRadius,
		}),
	} or nil)
end

local function renderFallbackBackground()
	return e("Frame", {
		Name = "ReactHudMenuFallbackBackground",
		BackgroundColor3 = Color3.fromRGB(22, 30, 44),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(248, 205, 120),
			Transparency = 0.28,
			Thickness = 2,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 126)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 147, 95)),
			}),
			Rotation = 90,
		}),
	})
end

local function renderFallbackIcon(style)
	local iconStyle = style or FALLBACK_ICON_STYLE

	return e("Frame", {
		Name = "ReactHudMenuFallbackIcon",
		AnchorPoint = iconStyle.anchorPoint,
		BackgroundColor3 = Color3.fromRGB(255, 236, 191),
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Position = iconStyle.position,
		Rotation = iconStyle.rotation,
		Size = UDim2.new(
			0,
			math.max(16, math.floor((iconStyle.size and iconStyle.size.X.Offset or 40) * 0.55 + 0.5)),
			0,
			math.max(16, math.floor((iconStyle.size and iconStyle.size.Y.Offset or 40) * 0.55 + 0.5))
		),
		ZIndex = math.max(iconStyle.zIndex or 6, 6),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(255, 255, 255),
			Transparency = 0.52,
			Thickness = 1,
		}),
	})
end

local function renderTitleBand(bandStyle)
	local style = bandStyle or TITLE_BAND_STYLE

	return e("Frame", {
		Name = "ReactHudMenuTitleBand",
		AnchorPoint = style.anchorPoint or TITLE_BAND_STYLE.anchorPoint,
		BackgroundColor3 = Color3.fromRGB(7, 12, 20),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Position = style.position or TITLE_BAND_STYLE.position,
		Size = style.size or TITLE_BAND_STYLE.size,
		ZIndex = style.zIndex or TITLE_BAND_STYLE.zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(255, 240, 211),
			Transparency = 0.62,
			Thickness = 1,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(23, 31, 46)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 10, 18)),
			}),
			Rotation = 90,
		}),
	})
end

local function renderTitle(label, titleStyle)
	local style = titleStyle or FALLBACK_TITLE_STYLE

	return e("TextLabel", {
		Name = "ReactHudMenuTitle",
		AnchorPoint = style.anchorPoint or FALLBACK_TITLE_STYLE.anchorPoint,
		BackgroundTransparency = style.backgroundTransparency or 1,
		BorderSizePixel = 0,
		Font = style.font or FALLBACK_TITLE_STYLE.font,
		FontFace = style.fontFace,
		Position = style.position or FALLBACK_TITLE_STYLE.position,
		Rotation = style.rotation,
		Size = style.size or FALLBACK_TITLE_STYLE.size,
		Text = tostring(label or ""),
		TextColor3 = style.textColor3 or FALLBACK_TITLE_STYLE.textColor3,
		TextSize = style.textSize or FALLBACK_TITLE_STYLE.textSize,
		TextStrokeColor3 = style.textStrokeColor3 or FALLBACK_TITLE_STYLE.textStrokeColor3,
		TextStrokeTransparency = style.textStrokeTransparency or FALLBACK_TITLE_STYLE.textStrokeTransparency,
		TextTransparency = style.textTransparency or FALLBACK_TITLE_STYLE.textTransparency,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = style.textWrapped == true,
		TextXAlignment = style.textXAlignment or FALLBACK_TITLE_STYLE.textXAlignment,
		TextYAlignment = style.textYAlignment or FALLBACK_TITLE_STYLE.textYAlignment,
		ZIndex = style.zIndex or FALLBACK_TITLE_STYLE.zIndex,
	})
end

local function HudMenuTile(props)
	local host = props.host
	if typeof(host) ~= "Instance" or not host.Parent then
		return nil
	end

	local style = props.style or {}
	local titleStyle = style.title or FALLBACK_TITLE_STYLE
	local children = {
		Background = renderVisualImage("ReactHudMenuBackground", style.background) or renderFallbackBackground(),
		TitleBand = renderTitleBand(style.titleBand),
		Title = renderTitle(props.label, titleStyle),
	}

	local iconNode = renderVisualImage("ReactHudMenuIcon", style.icon or FALLBACK_ICON_STYLE)
	if iconNode then
		children.Icon = iconNode
	else
		children.Icon = renderFallbackIcon(style.icon or FALLBACK_ICON_STYLE)
	end

	local accent = renderVisualImage("ReactHudMenuAccent", style.accent)
	if accent then
		children.Accent = accent
	end

	return ReactRoblox.createPortal(e("Frame", {
		Name = "ReactHudMenuTileRoot",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = math.max((style.background and style.background.zIndex or 4), 4),
	}, children), host)
end

return HudMenuTile
