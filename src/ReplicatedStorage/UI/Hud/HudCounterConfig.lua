local HudCounterConfig = {
	LeftPadding = 24,
	BottomPadding = 26,
	Width = 250,
	RowHeight = 46,
	RowSpacing = 6,
	PanelPadding = {
		Left = 10,
		Right = 10,
		Top = 10,
		Bottom = 10,
	},
	IconSlotWidth = 50,
	IconSize = 38,
	BarGap = 8,
	LabelSlotWidth = 72,
	NotificationWidth = 184,
	NotificationHeight = 96,
	DisplayLayerZIndex = 25,
}

function HudCounterConfig.getContentLeft()
	return HudCounterConfig.PanelPadding.Left
end

function HudCounterConfig.getContentTop()
	return HudCounterConfig.PanelPadding.Top
end

function HudCounterConfig.getContentWidth()
	return HudCounterConfig.Width - HudCounterConfig.PanelPadding.Left - HudCounterConfig.PanelPadding.Right
end

function HudCounterConfig.getTotalHeight(rowCount)
	local safeCount = math.max(0, tonumber(rowCount) or 0)
	return HudCounterConfig.PanelPadding.Top
		+ HudCounterConfig.PanelPadding.Bottom
		+ (safeCount * HudCounterConfig.RowHeight)
		+ (math.max(0, safeCount - 1) * HudCounterConfig.RowSpacing)
end

function HudCounterConfig.getRowY(index)
	local safeIndex = math.max(1, tonumber(index) or 1)
	return HudCounterConfig.PanelPadding.Top
		+ ((safeIndex - 1) * (HudCounterConfig.RowHeight + HudCounterConfig.RowSpacing))
end

function HudCounterConfig.getBarX()
	return HudCounterConfig.IconSlotWidth + HudCounterConfig.BarGap
end

function HudCounterConfig.getNotificationX()
	return HudCounterConfig.getContentLeft() + HudCounterConfig.getBarX() + 10
end

return HudCounterConfig
