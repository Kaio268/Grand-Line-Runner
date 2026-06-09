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
		tileSize = 88,
		iconSize = 72,
		textSize = 13,
		gap = 8,
		columns = 3,
		rows = 2,
		position = UDim2.fromOffset(12, 124),
		badgeSize = UDim2.fromOffset(46, 26),
		newBadgeSize = UDim2.fromOffset(58, 26),
		timerSize = UDim2.fromOffset(70, 20),
		timerTextSize = 12,
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
		scale = 0.84,
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
		position = UDim2.new(1, -12, 0, 146),
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

local MOBILE_RIGHT_STACK = {
	rightInset = 12,
	gap = 6,
	minTop = 8,
	preferredTop = 96,
	bottomInset = 12,
	adminSize = Vector2.new(132, 40),
	boostSize = Vector2.new(300, 118),
	boostCollapsedHeight = 34,
	devilFruitReservedHeight = 190,
}

local PHONE_IN_HAND_ASPECT = 232 / 82
local PHONE_IN_HAND_MIN_WIDTH = 172
local PHONE_IN_HAND_MAX_WIDTH = 232
local PHONE_IN_HAND_MIN_HEIGHT = 61
local PHONE_IN_HAND_MAX_HEIGHT = 82

local BOTTOM_RIGHT_FLOATING_PANEL = {
	phone = {
		topInset = 96,
		anchorPadding = 12,
	},
	tablet = {
		topInset = 132,
		anchorPadding = 12,
	},
	compactDesktop = {
		topInset = 96,
		anchorPadding = 12,
	},
	desktop = {
		topInset = 122,
		anchorPadding = 12,
	},
}

local CORRIDOR_IN_HAND = {
	phone = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -96, 1, -194),
		size = UDim2.fromOffset(PHONE_IN_HAND_MAX_WIDTH, PHONE_IN_HAND_MAX_HEIGHT),
		scale = 1,
		aspectRatio = PHONE_IN_HAND_ASPECT,
		minSize = Vector2.new(PHONE_IN_HAND_MIN_WIDTH, PHONE_IN_HAND_MIN_HEIGHT),
		maxSize = Vector2.new(PHONE_IN_HAND_MAX_WIDTH, PHONE_IN_HAND_MAX_HEIGHT),
		priority = 200,
		reservationPadding = 12,
	},
	tablet = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -24, 1, -318),
		size = UDim2.new(0.32, 0, 0, 136),
		scale = 1,
		minSize = Vector2.new(286, 122),
		maxSize = Vector2.new(388, 136),
		priority = 200,
		reservationPadding = 12,
	},
	compactDesktop = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -140, 1, -226),
		size = UDim2.new(0.26, 0, 0, 104),
		scale = 0.78,
		minSize = Vector2.new(230, 94),
		maxSize = Vector2.new(310, 104),
		priority = 200,
		reservationPadding = 12,
	},
	desktop = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -24, 1, -318),
		size = UDim2.new(0.32, 0, 0, 136),
		scale = 1,
		minSize = Vector2.new(286, 122),
		maxSize = Vector2.new(388, 136),
		priority = 200,
		reservationPadding = 12,
	},
}

local BASE_HELD_CREW = {
	phone = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -12, 1, -270),
		size = UDim2.fromOffset(270, 140),
		scale = 1,
		compact = true,
		priority = 160,
		reservationPadding = 12,
	},
	tablet = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -24, 1, -392),
		size = UDim2.fromOffset(318, 176),
		scale = 1,
		compact = false,
		priority = 160,
		reservationPadding = 12,
	},
	compactDesktop = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -12, 1, -270),
		size = UDim2.fromOffset(270, 140),
		scale = 0.9,
		compact = true,
		priority = 160,
		reservationPadding = 12,
	},
	desktop = {
		anchorPoint = Vector2.new(1, 1),
		position = UDim2.new(1, -24, 1, -392),
		size = UDim2.fromOffset(318, 176),
		scale = 1,
		compact = false,
		priority = 160,
		reservationPadding = 12,
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

local function resolveMode(mode, viewport)
	local size = viewport or Responsive.getViewportSize()
	local resolvedMode = tostring(mode or Responsive.getHudLayoutMode(size))
	if resolvedMode == "compactDesktop" and Responsive.isPhoneViewport(size) then
		return "phone"
	end
	return resolvedMode
end

local function resolveUDimOffset(value, axisSize)
	return (tonumber(value.Scale) or 0) * axisSize + (tonumber(value.Offset) or 0)
end

local function clampSize(size, minSize, maxSize)
	local width = roundOffset(size.X)
	local height = roundOffset(size.Y)

	if minSize then
		width = math.max(width, roundOffset(minSize.X))
		height = math.max(height, roundOffset(minSize.Y))
	end
	if maxSize then
		width = math.min(width, roundOffset(maxSize.X))
		height = math.min(height, roundOffset(maxSize.Y))
	end

	return Vector2.new(width, height)
end

local function resolveLayoutSize(layout, viewport)
	local rawSize = layout.size or UDim2.fromOffset(0, 0)
	local size = Vector2.new(
		resolveUDimOffset(rawSize.X, viewport.X),
		resolveUDimOffset(rawSize.Y, viewport.Y)
	)
	return clampSize(size, layout.minSize, layout.maxSize)
end

local function getRectFromLayout(layout, viewport)
	local scale = tonumber(layout.scale) or 1
	local size = resolveLayoutSize(layout, viewport)
	local visualSize = Vector2.new(roundOffset(size.X * scale), roundOffset(size.Y * scale))
	local position = layout.position or UDim2.fromOffset(0, 0)
	local anchorPoint = layout.anchorPoint or Vector2.zero
	local anchorPosition = Vector2.new(
		resolveUDimOffset(position.X, viewport.X),
		resolveUDimOffset(position.Y, viewport.Y)
	)

	return {
		x = roundOffset(anchorPosition.X - (visualSize.X * anchorPoint.X)),
		y = roundOffset(anchorPosition.Y - (visualSize.Y * anchorPoint.Y)),
		width = visualSize.X,
		height = visualSize.Y,
	}
end

local function normalizeRect(rect)
	if typeof(rect) ~= "table" then
		return nil
	end

	local x = tonumber(rect.x)
	local y = tonumber(rect.y)
	local width = tonumber(rect.width)
	local height = tonumber(rect.height)
	if not (x and y and width and height) then
		return nil
	end

	return {
		x = x,
		y = y,
		width = math.max(0, width),
		height = math.max(0, height),
	}
end

local function placeLayoutAboveAnchor(layout, anchorRect, viewport, resolvedMode)
	local rect = normalizeRect(anchorRect)
	if not rect then
		return layout
	end

	local placement = getByMode(BOTTOM_RIGHT_FLOATING_PANEL, resolvedMode)
	local scale = tonumber(layout.scale) or 1
	local size = resolveLayoutSize(layout, viewport)
	local visualSize = Vector2.new(roundOffset(size.X * scale), roundOffset(size.Y * scale))
	local padding = math.max(
		0,
		tonumber(layout.reservationPadding)
			or tonumber(placement.anchorPadding)
			or 12
	)
	local anchorRight = rect.x + rect.width
	local rightInset = math.max(0, roundOffset(viewport.X - anchorRight))
	local minTop = math.max(0, roundOffset(tonumber(placement.topInset) or 96))
	local targetTop = roundOffset(rect.y - padding - visualSize.Y)
	local top = math.max(minTop, targetTop)

	layout.anchorPoint = Vector2.new(1, 0)
	layout.position = UDim2.new(1, -rightInset, 0, top)
	return layout
end

local function applyPhoneInHandAspect(layout, anchorRect)
	local aspectRatio = tonumber(layout.aspectRatio) or PHONE_IN_HAND_ASPECT
	if aspectRatio <= 0 then
		return layout
	end

	local rect = normalizeRect(anchorRect)
	local rightEdge = if rect then rect.x + rect.width else PHONE_IN_HAND_MAX_WIDTH + MOBILE_RIGHT_STACK.rightInset
	local availableWidth = math.max(1, rightEdge - MOBILE_RIGHT_STACK.rightInset)
	local width = roundOffset(math.clamp(availableWidth, PHONE_IN_HAND_MIN_WIDTH, PHONE_IN_HAND_MAX_WIDTH))
	local height = roundOffset(width / aspectRatio)
	layout.size = UDim2.fromOffset(width, height)
	layout.minSize = Vector2.new(PHONE_IN_HAND_MIN_WIDTH, PHONE_IN_HAND_MIN_HEIGHT)
	layout.maxSize = Vector2.new(PHONE_IN_HAND_MAX_WIDTH, PHONE_IN_HAND_MAX_HEIGHT)
	layout.scale = 1
	return layout
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

local function shouldUseMobileRightStack(mode, viewport)
	local size = viewport or Responsive.getViewportSize()
	local resolvedMode = resolveMode(mode, size)
	return resolvedMode == "phone" or Responsive.isPhoneViewport(size)
end

local function makeRightStackEntry(viewport, top, size)
	local width = roundOffset(size.X)
	local height = roundOffset(size.Y)
	local rightInset = MOBILE_RIGHT_STACK.rightInset

	return {
		anchorPoint = Vector2.new(1, 0),
		position = UDim2.new(1, -rightInset, 0, top),
		size = UDim2.fromOffset(width, height),
		rect = {
			x = viewport.X - rightInset - width,
			y = top,
			width = width,
			height = height,
		},
	}
end

function HudLayout.getMode(viewport)
	return Responsive.getHudLayoutMode(viewport)
end

function HudLayout.getMobileRightStack(mode, options)
	local viewport = Responsive.getViewportSize()
	if not shouldUseMobileRightStack(mode, viewport) then
		return nil
	end

	local config = MOBILE_RIGHT_STACK
	local adminHeight = roundOffset(config.adminSize.Y)
	local boostHeight = roundOffset(config.boostSize.Y)
	local fruitHeight =
		math.max(roundOffset(tonumber(options and options.devilFruitHeight) or 0), config.devilFruitReservedHeight)
	local gap = roundOffset(config.gap)
	local totalHeight = adminHeight + gap + boostHeight + gap + fruitHeight
	local bottomAlignedTop = viewport.Y - totalHeight - config.bottomInset
	local stackTop = math.clamp(bottomAlignedTop, config.minTop, config.preferredTop)
	local adminTop = stackTop
	local boostTop = adminTop + adminHeight + gap
	local devilFruitTop = boostTop + boostHeight + gap
	local admin = makeRightStackEntry(viewport, adminTop, config.adminSize)
	local boost = makeRightStackEntry(viewport, boostTop, config.boostSize)
	local devilFruit = makeRightStackEntry(viewport, devilFruitTop, Vector2.new(HudLayout.DevilFruit.phone.width, fruitHeight))

	boost.collapsedHeight = roundOffset(config.boostCollapsedHeight)
	boost.gap = gap
	devilFruit.position = UDim2.new(1, -config.rightInset, 0, devilFruitTop)

	return {
		gap = gap,
		rightInset = config.rightInset,
		admin = admin,
		boost = boost,
		devilFruit = devilFruit,
	}
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
	local resolvedMode = resolveMode(mode)

	local layout = getByMode(CURRENCY, resolvedMode)
	return layout
end

function HudLayout.getDevilFruit(mode)
	local resolvedMode = resolveMode(mode)

	return getByMode(HudLayout.DevilFruit, resolvedMode)
end

function HudLayout.getDevilFruitPlacement(mode, options)
	local viewport = Responsive.getViewportSize()
	local resolvedMode = resolveMode(mode, viewport)
	local layout = HudLayout.getDevilFruit(resolvedMode)
	local width = roundOffset(tonumber(options and options.width) or layout.width or 0)
	local height = roundOffset(tonumber(options and options.height) or 0)
	local scale = tonumber(layout.scale) or 1
	local anchorPoint = layout.anchorPoint or Vector2.new(1, 1)
	local position = layout.position

	local stack = HudLayout.getMobileRightStack(resolvedMode, {
		devilFruitHeight = height,
	})
	if stack then
		anchorPoint = stack.devilFruit.anchorPoint
		position = stack.devilFruit.position
	end

	return {
		anchorPoint = anchorPoint,
		position = position,
		width = width,
		height = height,
		scale = scale,
		rect = getRectFromLayout({
			anchorPoint = anchorPoint,
			position = position,
			size = UDim2.fromOffset(width, height),
			scale = scale,
		}, viewport),
	}
end

function HudLayout.getCorridorInHandLayout(mode, options)
	local viewport = Responsive.getViewportSize()
	local resolvedMode = resolveMode(mode, viewport)
	local layout = getByMode(CORRIDOR_IN_HAND, resolvedMode)
	layout.compact = resolvedMode == "phone" or resolvedMode == "compactDesktop" or Responsive.isCompact(viewport)
	layout.phoneFit = resolvedMode == "phone" or Responsive.isPhoneViewport(viewport)
	local anchorRect = options and (options.devilFruitRect or options.anchorRect)
	if resolvedMode == "phone" then
		applyPhoneInHandAspect(layout, anchorRect)
	end
	placeLayoutAboveAnchor(layout, anchorRect, viewport, resolvedMode)
	layout.rect = getRectFromLayout(layout, viewport)
	return layout
end

function HudLayout.getBaseHeldCrewLayout(mode, options)
	local viewport = Responsive.getViewportSize()
	local resolvedMode = resolveMode(mode, viewport)
	local layout = getByMode(BASE_HELD_CREW, resolvedMode)
	layout.compact = layout.compact == true or resolvedMode == "phone" or resolvedMode == "compactDesktop"
	local anchorRect = options and (options.devilFruitRect or options.anchorRect)
	placeLayoutAboveAnchor(layout, anchorRect, viewport, resolvedMode)
	layout.rect = getRectFromLayout(layout, viewport)
	return layout
end

function HudLayout.getTopBanner(mode)
	local resolvedMode = resolveMode(mode)

	return getByMode(HudLayout.TopBanner, resolvedMode)
end

function HudLayout.getBoostTimer(mode, options)
	local viewport = Responsive.getViewportSize()
	local resolvedMode = resolveMode(mode, viewport)

	local layout = getByMode(HudLayout.BoostTimer, resolvedMode)
	local stack = HudLayout.getMobileRightStack(resolvedMode)
	if stack then
		layout.position = stack.boost.position
		layout.size = stack.boost.size
		layout.collapsedHeight = stack.boost.collapsedHeight
		layout.stackGap = stack.gap
	end

	local anchorRect = options and (options.anchorRect or options.carriedRect)
	local rect = if resolvedMode == "phone" then normalizeRect(anchorRect) else nil
	if rect then
		local visualSize = resolveLayoutSize(layout, viewport)
		local padding = tonumber(options and options.padding) or BOTTOM_RIGHT_FLOATING_PANEL.phone.anchorPadding
		local rightInset = math.max(0, roundOffset(viewport.X - (rect.x + rect.width)))
		local top = math.max(MOBILE_RIGHT_STACK.minTop, roundOffset(rect.y - padding - visualSize.Y))
		layout.position = UDim2.new(1, -rightInset, 0, top)
	end

	return layout
end

function HudLayout.getInventoryToggle(mode)
	local resolvedMode = resolveMode(mode)

	return getByMode(HudLayout.InventoryToggle, resolvedMode)
end

function HudLayout.getHotbar(mode)
	local resolvedMode = resolveMode(mode)

	return getByMode(HudLayout.Hotbar, resolvedMode)
end

function HudLayout.getPopups(mode)
	local resolvedMode = resolveMode(mode)

	return getByMode(HudLayout.Popups, resolvedMode)
end

function HudLayout.getWaveProgress(mode)
	local resolvedMode = resolveMode(mode)

	return getByMode(HudLayout.WaveProgress, resolvedMode)
end

function HudLayout.getBelowWaveTopOffset(mode, spacing)
	local layout = HudLayout.getWaveProgress(mode)
	local topOffset = tonumber(layout.topOffset) or 0
	local barHeight = tonumber(layout.barHeight) or 0
	return topOffset + barHeight + 22 + (tonumber(spacing) or 6)
end

return HudLayout
