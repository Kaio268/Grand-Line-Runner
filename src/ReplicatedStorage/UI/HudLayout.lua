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
		tileSize = 50,
		iconSize = 44,
		textSize = 9,
		gap = 8,
		columns = 3,
		rows = 2,
		position = UDim2.fromOffset(4, 192),
		badgeSize = UDim2.fromOffset(24, 14),
		newBadgeSize = UDim2.fromOffset(30, 14),
		timerSize = UDim2.fromOffset(36, 10),
		timerTextSize = 6,
		titleYScale = 0.74,
	},
	tablet = {
		orientation = "horizontal",
		tileSize = 66,
		iconSize = 60,
		textSize = 12,
		gap = 8,
		columns = 3,
		rows = 2,
		position = UDim2.fromOffset(8, 196),
		badgeSize = UDim2.fromOffset(30, 17),
		newBadgeSize = UDim2.fromOffset(38, 18),
		timerSize = UDim2.fromOffset(48, 13),
		timerTextSize = 8,
		titleYScale = 0.75,
	},
	compactDesktop = {
		orientation = "horizontal",
		tileSize = 44,
		iconSize = 36,
		textSize = 10,
		gap = 8,
		columns = 6,
		rows = 1,
		position = UDim2.fromOffset(130, 88),
		badgeSize = UDim2.fromOffset(26, 15),
		newBadgeSize = UDim2.fromOffset(32, 15),
		timerSize = UDim2.fromOffset(38, 10),
		timerTextSize = 7,
		titleYScale = 0.75,
	},
	desktop = {
		orientation = "grid",
		tileSize = 98,
		iconSize = 66,
		textSize = 16,
		gap = 10,
		columns = 2,
		rows = 3,
		position = UDim2.fromOffset(10, 250),
		badgeSize = UDim2.fromOffset(34, 22),
		newBadgeSize = UDim2.fromOffset(42, 22),
		timerSize = UDim2.fromOffset(60, 18),
		timerTextSize = 13,
		titleYScale = 0.78,
	},
}

local CURRENCY = {
	phone = {
		width = 132,
		rowHeight = 26,
		rowSpacing = 3,
		iconSlotWidth = 28,
		iconSize = 20,
		barGap = 4,
		valueTextSize = 18,
		labelTextSize = 10,
		panelPadding = { Left = 2, Right = 4, Top = 3, Bottom = 2 },
		preferredPosition = UDim2.fromOffset(16, 146),
	},
	tablet = {
		width = 150,
		rowHeight = 28,
		rowSpacing = 4,
		iconSlotWidth = 30,
		iconSize = 22,
		barGap = 5,
		valueTextSize = 18,
		labelTextSize = 10,
		panelPadding = { Left = 4, Right = 5, Top = 4, Bottom = 3 },
		preferredPosition = UDim2.fromOffset(16, 152),
	},
	compactDesktop = {
		width = 150,
		rowHeight = 28,
		rowSpacing = 4,
		iconSlotWidth = 30,
		iconSize = 22,
		barGap = 5,
		valueTextSize = 18,
		labelTextSize = 10,
		panelPadding = { Left = 4, Right = 5, Top = 4, Bottom = 3 },
		preferredPosition = UDim2.fromOffset(16, 144),
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
		compact = true,
		position = UDim2.new(1, -12, 1, -300),
		width = 210,
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

function HudLayout.getCurrency(mode, leftMenuRect)
	local resolvedMode = mode or HudLayout.getMode()
	local layout = getByMode(CURRENCY, resolvedMode)
	if resolvedMode == "desktop" then
		return layout
	end

	local rect = leftMenuRect or HudLayout.getLeftMenuRect(resolvedMode)
	local y = rect.y + rect.height + 8
	layout.anchorPoint = Vector2.new(0, 0)
	layout.position = UDim2.fromOffset(16, y)
	layout.preferredPosition = layout.position
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
