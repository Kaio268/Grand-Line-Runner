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
	local fillColor = isActive and surface.fill or (hovered and Theme.Palette.PanelSoft or Theme.Palette.ButtonInactive)
	local textColor = isActive and Theme.Palette.GoldSoft or Theme.Palette.Text
	local subtitleColor = isActive and surface.accentSoft or Theme.Palette.Muted

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(184, 52),
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
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.GoldSoft,
			Transparency = 0,
			Thickness = 1.35,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, isActive and surface.fill or Theme.Palette.PanelSoft),
				ColorSequenceKeypoint.new(1, fillColor),
			}),
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 0, 15),
			Text = section.title,
			TextColor3 = textColor,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Subtitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(8, 25),
			Size = UDim2.new(1, -16, 0, 12),
			Text = section.eyebrow,
			TextColor3 = subtitleColor,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
	})
end

local function SectionNav(props)
	local children = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, section in ipairs(props.sections or {}) do
		children["Button" .. tostring(index)] = e(navButton, {
			active = props.activeSectionKey == section.key,
			layoutOrder = index,
			onSectionSelected = props.onSectionSelected,
			section = section,
			zIndex = props.zIndex,
		})
	end

	return e("ScrollingFrame", {
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		LayoutOrder = props.layoutOrder or 0,
		Position = props.position,
		ScrollBarImageTransparency = 1,
		ScrollBarThickness = 0,
		ScrollingDirection = Enum.ScrollingDirection.X,
		Size = props.size or UDim2.new(1, 0, 0, 58),
		ZIndex = props.zIndex,
	}, children)
end

return SectionNav
