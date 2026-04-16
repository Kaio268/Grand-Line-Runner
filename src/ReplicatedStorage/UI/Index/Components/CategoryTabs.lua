local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function categoryTab(props)
	local category = props.category or {}
	local active = props.active == true
	local hovered, setHovered = React.useState(false)
	local total = math.max(1, tonumber(category.total) or 1)
	local collected = math.max(0, tonumber(category.collected) or 0)
	local percent = math.clamp(collected / total, 0, 1)
	local fillColor = category.fillColor or Theme.Palette.ProgressFill

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = active and Theme.Palette.SidebarActive
			or (hovered and Theme.Palette.SectionSoft or Theme.Palette.TabFill),
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1 / props.totalTabs, if props.layoutOrder == 1 then 0 else -1, 1, 0),
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
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.GoldSoft,
			Transparency = 0,
			Thickness = active and 1.5 or 1.2,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(4, 7),
			Size = UDim2.new(1, -8, 0, 12),
			Text = tostring(category.label or ""),
			TextColor3 = active and Theme.Palette.SidebarIndicator or Theme.Palette.MutedSoft,
			TextSize = 10,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Count = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(4, 20),
			Size = UDim2.new(1, -8, 0, 14),
			Text = tostring(collected),
			TextColor3 = active and Theme.Palette.Text or Theme.Palette.MutedSoft,
			TextSize = 15,
		}),
		BarTrack = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Theme.Palette.ProgressTrack,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 8, 1, -5),
			Size = UDim2.new(1, -16, 0, 4),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Fill = e("Frame", {
				BackgroundColor3 = fillColor,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(percent, 1),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		}),
	})
end

local function CategoryTabs(props)
	local categories = props.categories or {}
	local children = {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.BorderSoft,
			Transparency = 0.34,
			Thickness = 1,
		}),
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 1),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, category in ipairs(categories) do
		children["Tab" .. tostring(category.id)] = e(categoryTab, {
			active = props.activeCategory == category.id,
			category = category,
			layoutOrder = index,
			onSelect = props.onSelect,
			totalTabs = #categories,
		})
	end

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.SidebarFill,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, Theme.Layout.FooterTabsHeight),
	}, children)
end

return CategoryTabs
