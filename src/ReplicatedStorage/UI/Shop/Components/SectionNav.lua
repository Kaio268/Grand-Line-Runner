local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function navButton(props)
	local section = props.section or {}
	local surface = Theme.getSurfaceTheme(section.themeKey)
	local isActive = props.active == true
	local hovered, setHovered = React.useState(false)
	local fillColor = if isActive
		then surface.fill
		elseif hovered then Theme.Palette.TabFillHover
		else Theme.Palette.TabFill
	local textColor = if isActive then Theme.Palette.GoldSoft else Theme.Palette.Text

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(props.compact and 118 or 136, props.compact and 40 or 44),
		Text = "",
		ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			if props.onSectionSelected then
				props.onSectionSelected(section.key)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 9),
		}),
		Stroke = e("UIStroke", {
			Color = isActive and surface.stroke or Theme.Palette.BorderSoft,
			Transparency = isActive and 0.1 or 0.42,
			Thickness = isActive and 1.2 or 1,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(8, 0),
			Size = UDim2.new(1, -16, 1, 0),
			Text = section.title or "",
			TextColor3 = textColor,
			TextSize = props.compact and 12 or 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		ActiveLine = isActive and e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = surface.accent,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 1, -4),
			Size = UDim2.new(1, -26, 0, 3),
			ZIndex = props.zIndex and (props.zIndex + 3) or nil,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 999),
			}),
		}) or nil,
	})
end

local function SectionNav(props)
	local compact = props.compact == true
	local padding = compact and 4 or 6

	local children = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, compact and 7 or 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, padding),
			PaddingRight = UDim.new(0, padding),
		}),
	}

	for index, section in ipairs(props.sections or {}) do
		children["Button" .. tostring(index)] = e(navButton, {
			active = props.activeSectionKey == section.key,
			layoutOrder = index,
			onSectionSelected = props.onSectionSelected,
			compact = compact,
			section = section,
			zIndex = props.zIndex,
		})
	end

	return e("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		ElasticBehavior = Enum.ElasticBehavior.Never,
		LayoutOrder = props.layoutOrder or 0,
		Position = props.position,
		ScrollBarImageTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Size = props.size or UDim2.new(1, 0, 0, 48),
		ZIndex = props.zIndex,
	}, children)
end

return SectionNav
