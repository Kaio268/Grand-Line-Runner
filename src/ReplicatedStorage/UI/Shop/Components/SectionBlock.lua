local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local ProductCard = require(script.Parent:WaitForChild("ProductCard"))

local e = React.createElement

local function buildRows(items, columns)
	local rows = {}
	local current = {}

	for _, item in ipairs(items or {}) do
		current[#current + 1] = item
		if #current >= columns then
			rows[#rows + 1] = current
			current = {}
		end
	end

	if #current > 0 then
		rows[#rows + 1] = current
	end

	return rows
end

local function SectionBlock(props)
	local section = props.section or {}
	local columns = math.max(1, props.columns or 1)
	local sectionKey = tostring(section.key or "")
	local isFeatured = sectionKey == "featured"
	local gap = if columns >= 3 then 10 else 12
	local rows = buildRows(section.items or {}, columns)
	local surface = Theme.getSurfaceTheme(section.themeKey)
	local cellOffset = math.ceil((gap * math.max(0, columns - 1)) / columns)
	local layoutMode = columns >= 3 and "compact" or "stacked"
	local cardHeight
	if layoutMode == "compact" then
		cardHeight = isFeatured and 312 or 288
	elseif isFeatured then
		cardHeight = columns <= 1 and 352 or 328
	else
		cardHeight = columns <= 1 and 320 or 304
	end

	local rowChildren = {
		List = e("UIListLayout", {
			Padding = UDim.new(0, gap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for rowIndex, row in ipairs(rows) do
		local itemChildren = {
			List = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				Padding = UDim.new(0, gap),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}

		for columnIndex = 1, columns do
			local rowItem = row[columnIndex]
			if rowItem then
				itemChildren["Cell" .. tostring(columnIndex)] = e(ProductCard, {
					item = rowItem,
					layoutOrder = columnIndex,
					size = UDim2.new(1 / columns, -cellOffset, 0, cardHeight),
					visualMode = isFeatured and "featured" or "standard",
					layoutMode = layoutMode,
					onPurchaseRequested = props.onPurchaseRequested,
					onDetailsRequested = props.onDetailsRequested,
					zIndex = props.zIndex and (props.zIndex + 3) or nil,
				})
			end
		end

		rowChildren["Row" .. tostring(rowIndex)] = e("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = rowIndex,
			Size = UDim2.new(1, 0, 0, cardHeight),
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}, itemChildren)
	end

	return e("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromScale(1, 0),
		ZIndex = props.zIndex,
	}, {
		List = e("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Header = e("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 36),
		}, {
			Accent = e("Frame", {
				BackgroundColor3 = surface.accent,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 8),
				Size = UDim2.fromOffset(5, 21),
				ZIndex = props.zIndex and (props.zIndex + 1) or nil,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(1, -18, 1, 0),
				Text = section.title or "",
				TextColor3 = Theme.Palette.Text,
				TextSize = 23,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = props.zIndex and (props.zIndex + 1) or nil,
			}),
		}),
		Rows = e("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Size = UDim2.new(1, -2, 0, 0),
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}, rowChildren),
	})
end

return SectionBlock
