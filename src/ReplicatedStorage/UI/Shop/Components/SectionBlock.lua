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
	local section = props.section
	local columns = math.max(1, props.columns or 1)
	local gap = 18
	local rows = buildRows(section.items or {}, columns)
	local surface = Theme.getSurfaceTheme(section.themeKey)
	local cellOffset = math.floor((((columns - 1) * gap) / columns) + 0.5)
	local cardHeight = columns <= 1 and 276 or 254

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
			local item = row[columnIndex]
			if item then
				itemChildren["Cell" .. tostring(columnIndex)] = e(ProductCard, {
					item = item,
					layoutOrder = columnIndex,
					size = UDim2.new(1 / columns, -cellOffset, 0, cardHeight),
					onPurchaseRequested = props.onPurchaseRequested,
					onGiftRequested = props.onGiftRequested,
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
			AutomaticSize = Enum.AutomaticSize.Y,
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
		Size = UDim2.new(1, 0, 0, 0),
		ZIndex = props.zIndex,
	}, {
		List = e("UIListLayout", {
			Padding = UDim.new(0, 14),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Header = e("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 108),
		}, {
			Eyebrow = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 0),
				Size = UDim2.new(0.52, 0, 0, 14),
				Text = section.eyebrow or "",
				TextColor3 = surface.accent,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 16),
				Size = UDim2.new(0.68, 0, 0, 36),
				Text = section.title,
				TextColor3 = Theme.Palette.Text,
				TextSize = 34,
				TextStrokeTransparency = 0.68,
				TextStrokeColor3 = Theme.Palette.Shadow,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
			DividerLeft = e("Frame", {
				BackgroundColor3 = Color3.fromRGB(69, 98, 143),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 0, 60),
				Size = UDim2.new(0.34, -14, 0, 3),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
			}),
			DividerRight = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = Color3.fromRGB(69, 98, 143),
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Position = UDim2.new(1, 0, 0, 60),
				Size = UDim2.new(0.34, -14, 0, 3),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
			}),
			Description = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 70),
				Size = UDim2.new(0.74, 0, 0, 34),
				Text = section.description or "",
				TextColor3 = Theme.Palette.Muted,
				TextSize = 13,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
		}),
		Rows = e("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
			Size = UDim2.new(1, 0, 0, 0),
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}, rowChildren),
	})
end

return SectionBlock
