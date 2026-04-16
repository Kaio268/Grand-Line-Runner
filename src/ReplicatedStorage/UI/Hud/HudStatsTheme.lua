local HudStatsTheme = {}

HudStatsTheme.Font = Enum.Font.FredokaOne

HudStatsTheme.Card = {
	CornerRadius = 20,
	ShadowColor = Color3.fromRGB(0, 0, 0),
	ShadowTransparency = 0.72,
	AmbientGlowColor = Color3.fromRGB(124, 138, 178),
	AmbientGlowTransparency = 0.97,
	BackgroundTop = Color3.fromRGB(31, 35, 44),
	BackgroundBottom = Color3.fromRGB(12, 14, 20),
	BackgroundTransparency = 0.18,
	StrokeColor = Color3.fromRGB(255, 255, 255),
	StrokeTransparency = 0.88,
	InnerStrokeColor = Color3.fromRGB(117, 128, 159),
	InnerStrokeTransparency = 0.95,
	SheenColor = Color3.fromRGB(255, 255, 255),
	SheenTransparency = 0.975,
	SheenBottomTransparency = 1,
	DividerColor = Color3.fromRGB(255, 255, 255),
	DividerTransparency = 0.98,
}

HudStatsTheme.Row = {
	CornerRadius = 14,
	BackgroundColor = Color3.fromRGB(24, 28, 36),
	BackgroundTopColor = Color3.fromRGB(34, 38, 48),
	BackgroundBottomColor = Color3.fromRGB(19, 22, 29),
	BackgroundTransparency = 0.5,
	BackgroundHighlightTransparency = 0.5,
	StrokeTransparency = 0.975,
	IconPlateColor = Color3.fromRGB(17, 20, 29),
	IconPlateTransparency = 0.24,
	IconPlateShadowTransparency = 0.88,
	IconStrokeTransparency = 0.93,
	IconGlowTransparency = 0.94,
	ContentPaddingLeft = 2,
	ContentPaddingRight = 4,
	TextGap = 4,
}

HudStatsTheme.Typography = {
	ValueSize = 30,
	LabelSize = 17,
	ValueShadowOffset = Vector2.new(0, 3),
	LabelShadowOffset = Vector2.new(0, 2),
	ValueMainOffset = Vector2.new(0, -1),
	LabelMainOffset = Vector2.new(0, 0),
	ValueStrokeTransparency = 0.05,
	LabelStrokeTransparency = 0.12,
	ShadowStrokeTransparency = 0.58,
}

HudStatsTheme.Popup = {
	Duration = 1.35,
	EnterDuration = 0.16,
	FadeStart = 0.62,
	ItemHeight = 26,
	Spacing = 4,
	StartYOffset = 8,
	EndYOffset = -10,
	EnterScale = 0.72,
	ExitScale = 0.9,
	IconSize = 16,
	IconGap = 5,
	ValueSize = 21,
	LabelSize = 14,
	ValueShadowOffset = Vector2.new(0, 2),
	LabelShadowOffset = Vector2.new(0, 1),
	ValueStrokeTransparency = 0.08,
	LabelStrokeTransparency = 0.18,
	ShadowStrokeTransparency = 0.7,
	NegativeValue = Color3.fromRGB(255, 205, 205),
	NegativeLabel = Color3.fromRGB(255, 162, 162),
	NegativeStroke = Color3.fromRGB(115, 29, 37),
	NegativeShadow = Color3.fromRGB(45, 10, 14),
}

HudStatsTheme.Palette = {
	Comet = {
		value = Color3.fromRGB(250, 249, 255),
		label = Color3.fromRGB(220, 214, 255),
		stroke = Color3.fromRGB(67, 73, 103),
		shadow = Color3.fromRGB(17, 20, 30),
		glow = Color3.fromRGB(145, 152, 198),
		rowFill = Color3.fromRGB(126, 132, 180),
		rowStroke = Color3.fromRGB(159, 169, 214),
	},
	Speed = {
		value = Color3.fromRGB(255, 226, 185),
		label = Color3.fromRGB(255, 190, 132),
		stroke = Color3.fromRGB(110, 34, 32),
		shadow = Color3.fromRGB(40, 11, 12),
		glow = Color3.fromRGB(214, 96, 81),
		rowFill = Color3.fromRGB(180, 87, 63),
		rowStroke = Color3.fromRGB(233, 127, 97),
	},
	Money = {
		value = Color3.fromRGB(255, 241, 176),
		label = Color3.fromRGB(242, 209, 107),
		stroke = Color3.fromRGB(120, 81, 22),
		shadow = Color3.fromRGB(48, 31, 8),
		glow = Color3.fromRGB(232, 190, 82),
		rowFill = Color3.fromRGB(163, 121, 41),
		rowStroke = Color3.fromRGB(242, 209, 107),
	},
	Default = {
		value = Color3.fromRGB(242, 244, 250),
		label = Color3.fromRGB(218, 222, 236),
		stroke = Color3.fromRGB(52, 58, 78),
		shadow = Color3.fromRGB(17, 19, 27),
		glow = Color3.fromRGB(135, 145, 174),
		rowFill = Color3.fromRGB(135, 145, 174),
		rowStroke = Color3.fromRGB(175, 186, 222),
	},
}

function HudStatsTheme.getPalette(kind)
	return HudStatsTheme.Palette[kind] or HudStatsTheme.Palette.Default
end

function HudStatsTheme.getPopupPalette(kind, isPositive)
	if isPositive then
		local palette = HudStatsTheme.getPalette(kind)
		return {
			value = palette.value,
			label = palette.label,
			stroke = palette.stroke,
			shadow = palette.shadow,
		}
	end

	return {
		value = HudStatsTheme.Popup.NegativeValue,
		label = HudStatsTheme.Popup.NegativeLabel,
		stroke = HudStatsTheme.Popup.NegativeStroke,
		shadow = HudStatsTheme.Popup.NegativeShadow,
	}
end

return HudStatsTheme
