local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local IndexCard = require(script.Parent:WaitForChild("IndexCard"))

local e = React.createElement

local GRID_GAP = 6
local GRID_PADDING = 6
local DEFAULT_COLUMNS = 5
local DEFAULT_VIEWPORT_HEIGHT = 560
local VIRTUAL_OVERSCAN_ROWS = 3
local LAZY_PREVIEW_OVERSCAN_ROWS = 1
local MIN_LAYOUT_SCALE = 0.05
local SCROLL_CHANGE_EPSILON = 24
local SCROLL_UPDATE_DEBOUNCE_SECONDS = 0.04
local WIDTH_CHANGE_EPSILON = 1
local DEBUG_INDEX_GRID_PERF = false

local function getCardMetrics(containerWidth, columns)
	local width = math.max(containerWidth, 0)
	local usableWidth = math.max(320, width - (GRID_PADDING * 2) - 6)
	local totalGap = GRID_GAP * math.max(0, columns - 1)
	local cardWidth = math.floor((usableWidth - totalGap) / columns)
	cardWidth = math.clamp(cardWidth, Theme.Layout.CardMinWidth, Theme.Layout.CardMaxWidth)

	local cardHeight = math.floor(cardWidth * Theme.Layout.CardAspectRatio)
	return cardWidth, cardHeight
end

local function getCumulativeUiScale(instance)
	local scale = 1
	local current = instance

	while current do
		for _, child in ipairs(current:GetChildren()) do
			if child:IsA("UIScale") then
				local childScale = tonumber(child.Scale) or 1
				if childScale <= 0 then
					return 0
				end

				scale *= childScale
			end
		end

		current = current.Parent
	end

	return scale
end

local function getStableLayoutWidth(guiObject)
	local absoluteWidth = guiObject.AbsoluteSize.X
	if absoluteWidth <= 0 then
		return nil
	end

	local uiScale = getCumulativeUiScale(guiObject)
	if uiScale < MIN_LAYOUT_SCALE then
		return nil
	end

	return math.floor((absoluteWidth / uiScale) + 0.5)
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

local function shouldRenderPreview(index, columns, cardHeight, viewportHeight, canvasY)
	local rowHeight = math.max(1, cardHeight + GRID_GAP)
	local row = math.floor((math.max(1, index) - 1) / columns) + 1
	local firstVisibleRow = math.floor(math.max(0, (canvasY or 0) - GRID_PADDING) / rowHeight) + 1
	local visibleRows = math.ceil(math.max(cardHeight, viewportHeight or DEFAULT_VIEWPORT_HEIGHT) / rowHeight)
	local minRow = math.max(1, firstVisibleRow - LAZY_PREVIEW_OVERSCAN_ROWS)
	local maxRow = firstVisibleRow + visibleRows + LAZY_PREVIEW_OVERSCAN_ROWS

	return row >= minRow and row <= maxRow
end

local function getTotalRows(unitCount, columns)
	if unitCount <= 0 then
		return 0
	end

	return math.ceil(unitCount / math.max(1, columns))
end

local function getCanvasHeight(unitCount, columns, cardHeight)
	local totalRows = getTotalRows(unitCount, columns)
	if totalRows <= 0 then
		return 0
	end

	return (GRID_PADDING * 2) + (totalRows * cardHeight) + (math.max(0, totalRows - 1) * GRID_GAP)
end

local function getVirtualIndexRange(unitCount, columns, cardHeight, viewportHeight, canvasY)
	if unitCount <= 0 then
		return 1, 0
	end

	local rowHeight = math.max(1, cardHeight + GRID_GAP)
	local totalRows = getTotalRows(unitCount, columns)
	local firstVisibleRow = math.floor(math.max(0, (canvasY or 0) - GRID_PADDING) / rowHeight) + 1
	local visibleRows = math.ceil(math.max(cardHeight, viewportHeight or DEFAULT_VIEWPORT_HEIGHT) / rowHeight)
	local minRow = math.max(1, firstVisibleRow - VIRTUAL_OVERSCAN_ROWS)
	local maxRow = math.min(totalRows, firstVisibleRow + visibleRows + VIRTUAL_OVERSCAN_ROWS)

	return ((minRow - 1) * columns) + 1, math.min(unitCount, maxRow * columns)
end

local function getCardPosition(index, columns, cardWidth, cardHeight)
	local zeroIndex = math.max(0, index - 1)
	local row = math.floor(zeroIndex / columns)
	local column = zeroIndex % columns
	local x = GRID_PADDING + (column * (cardWidth + GRID_GAP))
	local y = GRID_PADDING + (row * (cardHeight + GRID_GAP))

	return x, y
end

local function debugGridLog(message)
	if DEBUG_INDEX_GRID_PERF then
		print("[IndexGridPerf] " .. message)
	end
end

local function IndexGrid(props)
	local units = props.units or {}
	local columns = math.max(1, props.columns or DEFAULT_COLUMNS)
	local containerWidth, setContainerWidth = React.useState(920)
	local previewScrollState, setPreviewScrollState = React.useState({
		canvasY = 0,
		viewportHeight = DEFAULT_VIEWPORT_HEIGHT,
	})
	local pendingPreviewScrollStateRef = React.useRef(nil)
	local previewScrollUpdateThreadRef = React.useRef(nil)
	local cardWidth, cardHeight = getCardMetrics(containerWidth, columns)

	React.useEffect(function()
		return function()
			local thread = previewScrollUpdateThreadRef.current
			if thread then
				task.cancel(thread)
				previewScrollUpdateThreadRef.current = nil
			end
			pendingPreviewScrollStateRef.current = nil
		end
	end, {})

	local function setPreviewScrollStateIfChanged(nextState)
		if math.abs((nextState.canvasY or 0) - (previewScrollState.canvasY or 0)) < SCROLL_CHANGE_EPSILON
			and math.abs((nextState.viewportHeight or 0) - (previewScrollState.viewportHeight or 0)) < WIDTH_CHANGE_EPSILON
		then
			return
		end

		setPreviewScrollState(nextState)
	end

	local function schedulePreviewScrollState(nextState, immediate)
		pendingPreviewScrollStateRef.current = nextState

		if immediate then
			local thread = previewScrollUpdateThreadRef.current
			if thread then
				task.cancel(thread)
				previewScrollUpdateThreadRef.current = nil
			end

			pendingPreviewScrollStateRef.current = nil
			setPreviewScrollStateIfChanged(nextState)
			return
		end

		if previewScrollUpdateThreadRef.current then
			return
		end

		previewScrollUpdateThreadRef.current = task.delay(SCROLL_UPDATE_DEBOUNCE_SECONDS, function()
			local pending = pendingPreviewScrollStateRef.current
			pendingPreviewScrollStateRef.current = nil
			previewScrollUpdateThreadRef.current = nil

			if pending then
				setPreviewScrollState(pending)
			end
		end)
	end

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

	local canvasHeight = getCanvasHeight(#units, columns, cardHeight)
	local firstRenderedIndex, lastRenderedIndex = getVirtualIndexRange(
		#units,
		columns,
		cardHeight,
		previewScrollState.viewportHeight,
		previewScrollState.canvasY
	)
	local renderedCardCount = math.max(0, lastRenderedIndex - firstRenderedIndex + 1)
	local gridChildren = {}

	debugGridLog(string.format(
		"units=%d rendered=%d range=%d-%d canvasY=%d viewport=%d card=%dx%d",
		#units,
		renderedCardCount,
		firstRenderedIndex,
		lastRenderedIndex,
		previewScrollState.canvasY or 0,
		previewScrollState.viewportHeight or 0,
		cardWidth,
		cardHeight
	))

	for index = firstRenderedIndex, lastRenderedIndex do
		local unit = units[index]
		if unit then
			local x, y = getCardPosition(index, columns, cardWidth, cardHeight)
			gridChildren["Card" .. tostring(unit.id)] = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(x, y),
				Size = UDim2.fromOffset(cardWidth, cardHeight),
			}, {
				Content = e(IndexCard, {
					layoutOrder = index,
					renderPreview = shouldRenderPreview(
						index,
						columns,
						cardHeight,
						previewScrollState.viewportHeight,
						previewScrollState.canvasY
					),
					unit = unit,
				}),
			})
		end
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
			AutomaticCanvasSize = Enum.AutomaticSize.None,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, canvasHeight),
			ScrollBarImageColor3 = Theme.Palette.GoldSoft,
			ScrollBarThickness = 5,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Size = UDim2.fromScale(1, 1),
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			[React.Change.AbsoluteSize] = function(rbx)
				local nextWidth = getStableLayoutWidth(rbx)
				if nextWidth and math.abs(nextWidth - containerWidth) >= WIDTH_CHANGE_EPSILON then
					setContainerWidth(nextWidth)
				end

				local nextHeight = math.floor(rbx.AbsoluteSize.Y + 0.5)
				if nextHeight > 0
					and math.abs(nextHeight - (previewScrollState.viewportHeight or 0)) >= WIDTH_CHANGE_EPSILON
				then
					schedulePreviewScrollState({
						canvasY = previewScrollState.canvasY or 0,
						viewportHeight = nextHeight,
					}, true)
				end
			end,
			[React.Change.CanvasPosition] = function(rbx)
				local nextY = math.max(0, math.floor(rbx.CanvasPosition.Y + 0.5))
				if math.abs(nextY - (previewScrollState.canvasY or 0)) >= SCROLL_CHANGE_EPSILON then
					schedulePreviewScrollState({
						canvasY = nextY,
						viewportHeight = previewScrollState.viewportHeight or DEFAULT_VIEWPORT_HEIGHT,
					}, false)
				end
			end,
		}, {
			Canvas = e("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.new(1, 0, 0, canvasHeight),
			}, gridChildren),
		}),
	})
end

local function areIndexGridPropsEqual(oldProps, newProps)
	return oldProps.units == newProps.units
		and oldProps.columns == newProps.columns
		and oldProps.layoutOrder == newProps.layoutOrder
end

return React.memo(IndexGrid, areIndexGridPropsEqual)
