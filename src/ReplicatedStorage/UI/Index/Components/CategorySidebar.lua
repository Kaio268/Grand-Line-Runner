local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function categoryButton(props)
	local active = props.active == true
	local category = props.category or {}
	local hovered, setHovered = React.useState(false)
	local fillColor = active and Theme.Palette.SidebarActive
		or (hovered and Theme.Palette.SectionSoft or Theme.Palette.Section)
	local textColor = active and Theme.Palette.SidebarIndicator or Theme.Palette.MutedSoft

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.new(1, -2, 0, 72),
		Text = "",
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			props.onSelect(category.id)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.SidebarActiveStroke,
			Transparency = 0,
			Thickness = active and 1.5 or 1.2,
		}),
		Icon = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(0, 10),
			Size = UDim2.new(1, 0, 0, 26),
			Text = tostring(category.iconText or ""),
			TextColor3 = active and Theme.Palette.SidebarIndicator or (category.fillColor or Theme.Palette.Text),
			TextSize = 24,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(4, 42),
			Size = UDim2.new(1, -8, 0, 16),
			Text = tostring(category.label or ""),
			TextColor3 = active and Theme.Palette.SidebarIndicator or textColor,
			TextSize = 10,
			TextWrapped = true,
		}),
		Indicator = active and e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Theme.Palette.SidebarIndicator,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(4, 28),
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
			Padding = UDim.new(0, 6),
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
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Size = UDim2.new(0, Theme.Layout.SidebarWidth, 1, 0),
	}, {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 1),
			PaddingRight = UDim.new(0, 1),
		}),
		Content = e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, sidebarChildren),
	})
end

return CategorySidebar
