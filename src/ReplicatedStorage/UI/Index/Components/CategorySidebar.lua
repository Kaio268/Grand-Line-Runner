local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local BUTTON_HEIGHT = 62
local BUTTON_GAP = 8

local function categoryButton(props)
	local active = props.active == true
	local category = props.category or {}
	local hovered, setHovered = React.useState(false)
	local fillColor = if active
		then Theme.Palette.SidebarActive
		else (if hovered then Theme.Palette.PanelSoft else Theme.Palette.Section)
	local strokeColor = if active
		then Theme.Palette.GoldSoft
		else (if hovered then Theme.Palette.BorderSoft else Theme.Palette.Divider)
	local iconColor = if active then Theme.Palette.GoldSoft else (category.fillColor or Theme.Palette.Text)
	local labelColor = if active then Theme.Palette.GoldSoft else Theme.Palette.Muted

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = active and 0.02 or 0.14,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, 0, 0, BUTTON_HEIGHT),
		Text = "",
		ZIndex = 8,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			if props.onSelect then
				props.onSelect(category.id)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = strokeColor,
			Transparency = active and 0 or 0.22,
			Thickness = active and 1.8 or 1.2,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = if active
				then ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(82, 64, 22)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 20)),
				})
				else ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(28, 28, 32)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 12)),
				}),
		}),
		Icon = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(0, 7),
			Size = UDim2.new(1, 0, 0, 28),
			Text = tostring(category.iconText or ""),
			TextColor3 = iconColor,
			TextSize = 24,
			TextStrokeColor3 = Theme.Palette.GoldShadow,
			TextStrokeTransparency = active and 0.3 or 0.62,
			ZIndex = 9,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(4, 39),
			Size = UDim2.new(1, -8, 0, 15),
			Text = tostring(category.label or ""),
			TextColor3 = labelColor,
			TextSize = 11,
			TextStrokeColor3 = Theme.Palette.GoldShadow,
			TextStrokeTransparency = active and 0.42 or 0.72,
			TextWrapped = true,
			ZIndex = 9,
		}),
		Indicator = active and e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Theme.Palette.GoldSoft,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(4, 34),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
		}) or nil,
	})
end

local function CategorySidebar(props)
	local categories = props.categories or {}
	local sidebarChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, BUTTON_GAP),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, category in ipairs(categories) do
		sidebarChildren["Category" .. tostring(category.id)] = e(categoryButton, {
			active = props.activeCategory == category.id,
			category = category,
			layoutOrder = index,
			onSelect = props.onSelect,
		})
	end

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Board,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(0, Theme.Layout.SidebarWidth, 1, 0),
		ZIndex = 6,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Theme.Palette.BorderSoft,
			Transparency = 0.08,
			Thickness = 1.4,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 8),
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 7),
			PaddingRight = UDim.new(0, 7),
		}),
		Content = e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 7,
		}, sidebarChildren),
	})
end

return CategorySidebar
