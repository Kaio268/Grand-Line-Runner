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
	local gap = columns <= 1 and 12 or 14
	local rows = buildRows(section.items or {}, columns)
	local surface = Theme.getSurfaceTheme(section.themeKey)
	local cardSafetyInset = columns > 1 and 12 or 4
	local cellOffset = math.ceil((((columns - 1) * gap) + cardSafetyInset) / columns)
	local cardHeight = columns <= 1 and 304 or 292

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
					onPurchaseRequested = props.onPurchaseRequested,
					onDetailsRequested = props.onDetailsRequested,
					zIndex = props.zIndex and (props.zIndex + 3) or nil,
				})
			else
				itemChildren["Spacer" .. tostring(columnIndex)] = e("Frame", {
					BackgroundTransparency = 1,
					LayoutOrder = columnIndex,
					Size = UDim2.new(1 / columns, -cellOffset, 0, cardHeight),
				})
			end
		end

		rowChildren["Row" .. tostring(rowIndex)] = e("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = rowIndex,
			Size = UDim2.new(1, -cardSafetyInset, 0, cardHeight),
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
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Header = e("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 42),
		}, {
			Accent = e("Frame", {
				BackgroundColor3 = surface.accent,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 10),
				Size = UDim2.fromOffset(5, 24),
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
				TextSize = 25,
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
