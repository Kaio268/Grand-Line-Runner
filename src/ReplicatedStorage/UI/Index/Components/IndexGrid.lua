local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local IndexCard = require(script.Parent:WaitForChild("IndexCard"))

local e = React.createElement

local GRID_GAP = 6
local GRID_PADDING = 6
local DEFAULT_COLUMNS = 5

local function getCardMetrics(containerWidth, columns)
	local width = math.max(containerWidth, 0)
	local usableWidth = math.max(320, width - (GRID_PADDING * 2) - 6)
	local totalGap = GRID_GAP * math.max(0, columns - 1)
	local cardWidth = math.floor((usableWidth - totalGap) / columns)
	cardWidth = math.clamp(cardWidth, Theme.Layout.CardMinWidth, Theme.Layout.CardMaxWidth)

	local cardHeight = math.floor(cardWidth * Theme.Layout.CardAspectRatio)
	return cardWidth, cardHeight
end

local function emptyState()
	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, {
		Title = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromOffset(280, 24),
			Text = "Nothing discovered here yet.",
			TextColor3 = Theme.Palette.Muted,
			TextSize = 20,
		}),
		Subtitle = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromScale(0.5, 0.54),
			Size = UDim2.fromOffset(360, 18),
			Text = "Open eggs and come back once you find a new unit.",
			TextColor3 = Theme.Palette.MutedSoft,
			TextSize = 12,
		}),
	})
end

local function IndexGrid(props)
	local units = props.units or {}
	local columns = math.max(1, props.columns or DEFAULT_COLUMNS)
	local containerWidth, setContainerWidth = React.useState(920)
	local cardWidth, cardHeight = getCardMetrics(containerWidth, columns)

	if #units == 0 then
		return e("Frame", {
			BackgroundColor3 = Theme.Palette.Section,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			LayoutOrder = props.layoutOrder or 0,
			Size = UDim2.fromScale(1, 1),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.GoldSoft,
				Transparency = 0,
				Thickness = 1.5,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Theme.Palette.SectionSoft),
					ColorSequenceKeypoint.new(1, Theme.Palette.Section),
				}),
			}),
			Empty = emptyState(),
		})
	end

	local gridChildren = {
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, GRID_PADDING),
			PaddingLeft = UDim.new(0, GRID_PADDING),
			PaddingRight = UDim.new(0, GRID_PADDING),
			PaddingTop = UDim.new(0, GRID_PADDING),
		}),
		Grid = e("UIGridLayout", {
			FillDirectionMaxCells = columns,
			CellPadding = UDim2.fromOffset(GRID_GAP, GRID_GAP),
			CellSize = UDim2.fromOffset(cardWidth, cardHeight),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, unit in ipairs(units) do
		gridChildren["Card" .. tostring(unit.id)] = e(IndexCard, {
			layoutOrder = index,
			unit = unit,
		})
	end

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Section,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.GoldSoft,
			Transparency = 0,
			Thickness = 1.5,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.SectionSoft),
				ColorSequenceKeypoint.new(1, Theme.Palette.Section),
			}),
		}),
		Scroller = e("ScrollingFrame", {
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			ScrollBarImageColor3 = Theme.Palette.GoldSoft,
			ScrollBarThickness = 5,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Size = UDim2.fromScale(1, 1),
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			[React.Change.AbsoluteSize] = function(rbx)
				local nextWidth = rbx.AbsoluteSize.X
				if nextWidth > 0 and nextWidth ~= containerWidth then
					setContainerWidth(nextWidth)
				end
			end,
		}, gridChildren),
	})
end

return IndexGrid
