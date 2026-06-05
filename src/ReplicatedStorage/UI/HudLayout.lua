local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Responsive = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Responsive"))

local HudLayout = {}

HudLayout.Modes = {
	Phone = "phone",
	Tablet = "tablet",
	CompactDesktop = "compactDesktop",
	Desktop = "desktop",
}

local LEFT_MENU = {
	phone = {
		orientation = "horizontal",
		tileSize = 42,
		iconSize = 36,
		textSize = 10,
		gap = 8,
		columns = 3,
		rows = 2,
		position = UDim2.fromOffset(12, 68),
		badgeSize = UDim2.fromOffset(28, 16),
		newBadgeSize = UDim2.fromOffset(36, 16),
		timerSize = UDim2.fromOffset(42, 13),
		timerTextSize = 8,
		titleYScale = 0.74,
	},
	tablet = {
		orientation = "horizontal",
		tileSize = 132,
		iconSize = 120,
		textSize = 24,
		gap = 16,
		columns = 3,
		rows = 2,
		position = UDim2.fromOffset(8, 196),
		badgeSize = UDim2.fromOffset(60, 34),
		newBadgeSize = UDim2.fromOffset(76, 36),
		timerSize = UDim2.fromOffset(96, 26),
		timerTextSize = 16,
		titleYScale = 0.75,
	},
	compactDesktop = {
		orientation = "horizontal",
		tileSize = 56,
		iconSize = 48,
		textSize = 12,
		gap = 8,
		columns = 6,
		rows = 1,
		position = UDim2.fromOffset(122, 92),
		badgeSize = UDim2.fromOffset(34, 20),
		newBadgeSize = UDim2.fromOffset(42, 20),
		timerSize = UDim2.fromOffset(52, 16),
		timerTextSize = 10,
		titleYScale = 0.75,
	},
	desktop = {
		orientation = "grid",
		tileSize = 86,
		iconSize = 66,
		textSize = 15,
		gap = 8,
		columns = 2,
		rows = 3,
		position = UDim2.fromOffset(18, 124),
		badgeSize = UDim2.fromOffset(34, 22),
		newBadgeSize = UDim2.fromOffset(44, 22),
		timerSize = UDim2.fromOffset(54, 17),
		timerTextSize = 11,
		titleYScale = 0.8,
	},
}

local CURRENCY = {
	phone = {
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 12, 1, -12),
		width = 112,
		rowHeight = 20,
		rowSpacing = 2,
		iconSlotWidth = 22,
		iconSize = 16,
		barGap = 3,
		valueTextSize = 14,
		labelTextSize = 8,
		panelPadding = { Left = 2, Right = 4, Top = 3, Bottom = 2 },
	},
	tablet = {
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 16, 1, -24),
		width = 150,
		rowHeight = 28,
		rowSpacing = 4,
		iconSlotWidth = 30,
		iconSize = 22,
		barGap = 5,
		valueTextSize = 18,
		labelTextSize = 10,
		panelPadding = { Left = 4, Right = 5, Top = 4, Bottom = 3 },
	},
	compactDesktop = {
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 16, 1, -24),
		width = 150,
		rowHeight = 28,
		rowSpacing = 4,
		iconSlotWidth = 30,
		iconSize = 22,
		barGap = 5,
		valueTextSize = 18,
		labelTextSize = 10,
		panelPadding = { Left = 4, Right = 5, Top = 4, Bottom = 3 },
	},
	desktop = {
		anchorPoint = Vector2.new(0, 1),
		position = nil,
	},
}

HudLayout.DevilFruit = {
	phone = {
		compact = true,
		position = UDim2.new(1, 0, 1, -128),
		width = 142,
		rowHeight = 26,
		rowGap = 3,
		listInset = 7,
		topBarHeight = 22,
		outerInset = 4,
		sectionGap = 4,
		nameTextSize = 8,
		statusTextSize = 7,
		nameY = 3,
		statusY = 11,
		barHeight = 2,
		barBottom = 3,
		barInset = 4,
		headerTitleY = 1,
		headerTitleHeight = 8,
		headerTitleTextSize = 5,
		fruitNameY = 9,
		fruitNameHeight = 11,
		fruitNameTextSize = 10,
	},
	tablet = {
		compact = false,
		position = UDim2.new(1, -12, 1, -300),
		width = 318,
	},
	compactDesktop = {
		compact = true,
		position = UDim2.new(1, -12, 1, -24),
		width = 196,
	},
	desktop = {
		compact = false,
		position = UDim2.new(1, -24, 1, -24),
		width = 318,
	},
}

HudLayout.TopBanner = {
	phone = {
		scale = 0.72,
		announcementScale = 0.76,
		topOffset = 76,
		announcementTopOffset = 114,
	},
	tablet = {
		scale = 0.8,
		announcementScale = 0.84,
		topOffset = 84,
		announcementTopOffset = 124,
	},
	compactDesktop = {
		scale = 0.88,
		announcementScale = 0.9,
		topOffset = 90,
		announcementTopOffset = 150,
	},
	desktop = {
		scale = 1,
		announcementScale = nil,
		topOffset = 96,
		announcementTopOffset = 176,
	},
}

HudLayout.BoostTimer = {
	phone = {
		position = UDim2.new(1, -12, 0, 118),
		size = UDim2.fromOffset(300, 120),
		compact = true,
	},
	tablet = {
		position = UDim2.new(1, -14, 0, 124),
		size = UDim2.fromOffset(330, 130),
		compact = true,
	},
	compactDesktop = {
		position = UDim2.new(1, -16, 0, 114),
		size = UDim2.fromOffset(340, 130),
		compact = true,
	},
	desktop = {
		position = UDim2.new(1, -18, 0, 122),
		size = UDim2.fromOffset(360, 140),
		compact = false,
	},
}

HudLayout.InventoryToggle = {
	phone = { size = 38 },
	tablet = { size = 62 },
	compactDesktop = { size = 62 },
	desktop = { size = 74 },
}

HudLayout.Hotbar = {
	phone = {
		slotSize = 36,
		slotGap = 4,
		toggleGap = 5,
		bottomXOffset = 16,
		bottomOffset = -6,
		bottomBarHeight = 46,
		hotbarHeight = 44,
		scrollerHeight = 40,
		scrollerY = 2,
		toggleY = 2,
	},
	tablet = {
		slotSize = 46,
		slotGap = 5,
		toggleGap = 7,
		bottomXOffset = 28,
		bottomOffset = -10,
		bottomBarHeight = 62,
		hotbarHeight = 58,
		scrollerHeight = 52,
		scrollerY = 4,
		toggleY = 4,
	},
	compactDesktop = {
		slotSize = 42,
		slotGap = 5,
		toggleGap = 6,
		bottomXOffset = 18,
		bottomOffset = -8,
		bottomBarHeight = 54,
		hotbarHeight = 50,
		scrollerHeight = 46,
		scrollerY = 3,
		toggleY = 3,
	},
	desktop = {
		slotSize = 64,
		slotGap = 10,
		toggleGap = 20,
		bottomXOffset = 0,
		bottomOffset = -20,
		bottomBarHeight = 104,
		hotbarHeight = 96,
		scrollerHeight = 78,
		scrollerY = 18,
		toggleY = 20,
	},
}

HudLayout.Popups = {
	phone = { rewardScale = 0.74, acknowledgementMaxScale = 0.74 },
	tablet = { rewardScale = 0.82, acknowledgementMaxScale = 0.82 },
	compactDesktop = { rewardScale = nil, acknowledgementMaxScale = 0.9 },
	desktop = { rewardScale = nil, acknowledgementMaxScale = 1 },
}

HudLayout.WaveProgress = {
	phone = {
		barHeight = 20,
		markerSize = 26,
		rootWidth = 390,
		topOffset = 8,
		minWidth = 280,
		maxWidth = 450,
		compact = true,
	},
	tablet = {
		barHeight = 30,
		markerSize = 34,
		rootWidth = 500,
		topOffset = 8,
		minWidth = 320,
		maxWidth = 580,
		compact = true,
	},
	compactDesktop = {
		barHeight = 18,
		markerSize = 22,
		rootWidth = 340,
		topOffset = 8,
		minWidth = 240,
		maxWidth = 380,
		compact = true,
	},
	desktop = {
		barHeight = 44,
		markerSize = 44,
		rootWidth = 900,
		topOffset = 18,
		minWidth = 560,
		maxWidth = 980,
		compact = false,
	},
}

local function cloneTable(source)
	local copy = {}
	for key, value in pairs(source) do
		if typeof(value) == "table" then
			copy[key] = cloneTable(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local function getByMode(tableByMode, mode)
	local resolvedMode = mode or HudLayout.getMode()
	local source = tableByMode[resolvedMode] or tableByMode.desktop
	return cloneTable(source)
end

local function getGridSize(layout)
	local width = (layout.columns * layout.tileSize) + (math.max(0, layout.columns - 1) * layout.gap)
	local height = (layout.rows * layout.tileSize) + (math.max(0, layout.rows - 1) * layout.gap)
	return Vector2.new(width, height)
end

local function roundOffset(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function scaleOffsetSize(size, scale)
	return UDim2.new(
		size.X.Scale,
		roundOffset(size.X.Offset * scale),
		size.Y.Scale,
		roundOffset(size.Y.Offset * scale)
	)
end

local function getLeftMenuScale(resolvedMode, layout, viewport)
	if resolvedMode == "desktop" then
		local targetScale = math.clamp(viewport.Y / 635, 1.25, 2.05)
		local baseSize = getGridSize(layout)
		local safeHeight = math.max(1, viewport.Y - 112 - 128)
		local safeWidth = math.max(1, math.min(viewport.X * 0.22, 390))
		local heightCap = safeHeight / math.max(baseSize.Y, 1)
		local widthCap = safeWidth / math.max(baseSize.X, 1)
		local safetyScale = math.max(1.05, math.min(heightCap, widthCap))

		return math.clamp(math.min(targetScale, safetyScale), 1.05, 2.05)
	elseif resolvedMode == "compactDesktop" then
		local targetScale = math.min(viewport.X / 900, viewport.Y / 640) * 1.2
		return math.clamp(targetScale, 1.05, 1.35)
	elseif resolvedMode == "tablet" then
		return math.clamp(math.min(viewport.X, viewport.Y) / 800, 0.9, 1.15)
	elseif resolvedMode == "phone" then
		return math.clamp(math.min(viewport.X, viewport.Y) / 420, 0.9, 1.2)
	end

	return 1
end

local function applyLeftMenuScale(layout, scale)
	layout.tileSize = roundOffset(layout.tileSize * scale)
	layout.iconSize = roundOffset(layout.iconSize * scale)
	layout.textSize = roundOffset(layout.textSize * scale)
	layout.gap = math.max(4, roundOffset(layout.gap * scale))
	layout.timerTextSize = math.max(7, roundOffset(layout.timerTextSize * scale))
	layout.badgeSize = scaleOffsetSize(layout.badgeSize, scale)
	layout.newBadgeSize = scaleOffsetSize(layout.newBadgeSize, scale)
	layout.timerSize = scaleOffsetSize(layout.timerSize, scale)
	layout.uiScale = scale
end

function HudLayout.getMode(viewport)
	return Responsive.getHudLayoutMode(viewport)
end

function HudLayout.getLeftMenu(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	local layout = getByMode(LEFT_MENU, resolvedMode)
	local viewport = Responsive.getViewportSize()
	local scale = getLeftMenuScale(resolvedMode, layout, viewport)
	applyLeftMenuScale(layout, scale)
	local size = getGridSize(layout)
	if layout.orientation == "horizontal" then
		local x = math.clamp(layout.position.X.Offset, 6, math.max(6, viewport.X - size.X - 6))
		local topReserve = if resolvedMode == "phone" then 58 elseif resolvedMode == "tablet" then 110 else 76
		local bottomReserve = if resolvedMode == "tablet" then 140 else 92
		local maxY = math.max(topReserve, viewport.Y - size.Y - bottomReserve)
		local y = math.clamp(layout.position.Y.Offset, topReserve, maxY)
		layout.position = UDim2.fromOffset(x, y)
	else
		local bottomReserve = if resolvedMode == "desktop" then 128 else 92
		local minY = if resolvedMode == "desktop" then 112 else 70
		local maxY = math.max(minY, viewport.Y - size.Y - bottomReserve)
		local targetY = if resolvedMode == "desktop" then (viewport.Y - size.Y) * 0.5 else layout.position.Y.Offset
		local y = math.clamp(targetY, minY, maxY)
		local x = if resolvedMode == "desktop"
			then math.clamp(roundOffset(viewport.X * 0.018), 18, 44)
			else layout.position.X.Offset
		layout.position = UDim2.fromOffset(x, y)
	end
	return layout
end

function HudLayout.getLeftMenuSize(mode)
	local layout = HudLayout.getLeftMenu(mode)
	return getGridSize(layout)
end

function HudLayout.getLeftMenuRect(mode)
	local layout = HudLayout.getLeftMenu(mode)
	local size = HudLayout.getLeftMenuSize(mode)
	return {
		x = layout.position.X.Offset,
		y = layout.position.Y.Offset,
		width = size.X,
		height = size.Y,
	}
end

function HudLayout.rectsIntersect(a, b)
	if not a or not b then
		return false
	end

	return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

function HudLayout.getCurrency(mode, _leftMenuRect)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	local layout = getByMode(CURRENCY, resolvedMode)
	return layout
end

function HudLayout.getDevilFruit(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	return getByMode(HudLayout.DevilFruit, resolvedMode)
end

function HudLayout.getTopBanner(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	return getByMode(HudLayout.TopBanner, resolvedMode)
end

function HudLayout.getBoostTimer(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	return getByMode(HudLayout.BoostTimer, resolvedMode)
end

function HudLayout.getInventoryToggle(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	return getByMode(HudLayout.InventoryToggle, resolvedMode)
end

function HudLayout.getHotbar(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	return getByMode(HudLayout.Hotbar, resolvedMode)
end

function HudLayout.getPopups(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	return getByMode(HudLayout.Popups, resolvedMode)
end

function HudLayout.getWaveProgress(mode)
	local resolvedMode = mode or HudLayout.getMode()
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(Responsive.getViewportSize()) then
		resolvedMode = "phone"
	end

	return getByMode(HudLayout.WaveProgress, resolvedMode)
end

function HudLayout.getBelowWaveTopOffset(mode, spacing)
	local layout = HudLayout.getWaveProgress(mode)
	local topOffset = tonumber(layout.topOffset) or 0
	local barHeight = tonumber(layout.barHeight) or 0
	return topOffset + barHeight + 22 + (tonumber(spacing) or 6)
end

return HudLayout
