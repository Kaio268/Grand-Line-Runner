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
		tileSize = 100,
		iconSize = 88,
		textSize = 18,
		gap = 16,
		columns = 3,
		rows = 2,
		position = UDim2.fromOffset(4, 192),
		badgeSize = UDim2.fromOffset(48, 28),
		newBadgeSize = UDim2.fromOffset(60, 28),
		timerSize = UDim2.fromOffset(72, 20),
		timerTextSize = 12,
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
		tileSize = 88,
		iconSize = 72,
		textSize = 20,
		gap = 16,
		columns = 6,
		rows = 1,
		position = UDim2.fromOffset(130, 88),
		badgeSize = UDim2.fromOffset(52, 30),
		newBadgeSize = UDim2.fromOffset(64, 30),
		timerSize = UDim2.fromOffset(76, 20),
		timerTextSize = 14,
		titleYScale = 0.75,
	},
	desktop = {
		orientation = "grid",
		tileSize = 196,
		iconSize = 132,
		textSize = 32,
		gap = 20,
		columns = 2,
		rows = 3,
		position = UDim2.fromOffset(10, 80),
		badgeSize = UDim2.fromOffset(68, 44),
		newBadgeSize = UDim2.fromOffset(84, 44),
		timerSize = UDim2.fromOffset(120, 36),
		timerTextSize = 26,
		titleYScale = 0.78,
	},
}

local CURRENCY = {
	phone = {
		anchorPoint = Vector2.new(0, 1),
		position = UDim2.new(0, 16, 1, -24),
		width = 132,
		rowHeight = 26,
		rowSpacing = 3,
		iconSlotWidth = 28,
		iconSize = 20,
		barGap = 4,
		valueTextSize = 18,
		labelTextSize = 10,
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
		position = UDim2.new(1, -8, 1, -164),
		width = 168,
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
	phone = { size = 56 },
	tablet = { size = 62 },
	compactDesktop = { size = 62 },
	desktop = { size = 74 },
}

HudLayout.Popups = {
	phone = { rewardScale = 0.74, acknowledgementMaxScale = 0.74 },
	tablet = { rewardScale = 0.82, acknowledgementMaxScale = 0.82 },
	compactDesktop = { rewardScale = nil, acknowledgementMaxScale = 0.9 },
	desktop = { rewardScale = nil, acknowledgementMaxScale = 1 },
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

function HudLayout.getMode(viewport)
	return Responsive.getHudLayoutMode(viewport)
end

function HudLayout.getLeftMenu(mode)
	local layout = getByMode(LEFT_MENU, mode)
	if layout.orientation == "horizontal" then
		local viewport = Responsive.getViewportSize()
		local size = getGridSize(layout)
		local x = math.clamp(layout.position.X.Offset, 6, math.max(6, viewport.X - size.X - 6))
		layout.position = UDim2.fromOffset(x, layout.position.Y.Offset)
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
	local layout = getByMode(CURRENCY, resolvedMode)
	return layout
end

function HudLayout.getDevilFruit(mode)
	return getByMode(HudLayout.DevilFruit, mode)
end

function HudLayout.getTopBanner(mode)
	return getByMode(HudLayout.TopBanner, mode)
end

function HudLayout.getBoostTimer(mode)
	return getByMode(HudLayout.BoostTimer, mode)
end

function HudLayout.getInventoryToggle(mode)
	return getByMode(HudLayout.InventoryToggle, mode)
end

function HudLayout.getPopups(mode)
	return getByMode(HudLayout.Popups, mode)
end

return HudLayout
