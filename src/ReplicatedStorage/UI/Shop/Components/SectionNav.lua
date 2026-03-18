local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function SectionNav(props)
	local children = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, section in ipairs(props.sections or {}) do
		local surface = Theme.getSurfaceTheme(section.themeKey)
		local isActive = props.activeSectionKey == section.key
		children["Button" .. tostring(index)] = e("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = isActive and surface.accent or Theme.Palette.PanelSoft,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.fromOffset(186, 56),
			Text = "",
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
			[React.Event.Activated] = function()
				if props.onSectionSelected then
					props.onSectionSelected(section.key)
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = isActive and surface.stroke or Color3.fromRGB(69, 94, 132),
				Transparency = isActive and 0.06 or 0.24,
				Thickness = isActive and 1.4 or 1.1,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, isActive and surface.accent or Theme.Palette.BoardSoft),
					ColorSequenceKeypoint.new(1, isActive and surface.accentSoft or Theme.Palette.Panel),
				}),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Position = UDim2.fromOffset(16, 10),
				Size = UDim2.new(1, -28, 0, 14),
				Text = section.title,
				TextColor3 = isActive and Theme.Palette.Ink or Theme.Palette.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = props.zIndex and (props.zIndex + 2) or nil,
			}),
			Subtitle = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Position = UDim2.fromOffset(16, 27),
				Size = UDim2.new(1, -32, 0, 12),
				Text = section.eyebrow,
				TextColor3 = isActive and Theme.Palette.Board or Theme.Palette.Muted,
				TextSize = 9,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = props.zIndex and (props.zIndex + 2) or nil,
			}),
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
