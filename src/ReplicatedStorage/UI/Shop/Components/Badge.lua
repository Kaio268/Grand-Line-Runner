local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function Badge(props)
	local text = props.text
	if not text or text == "" then
		return nil
	end

	local badgeTheme = Theme.getBadgeTheme(props.variant or text)

	return e("Frame", {
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = badgeTheme.fill,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Position = props.position,
		Size = props.size or UDim2.fromOffset(0, 28),
		ZIndex = props.zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 999),
		}),
		Stroke = e("UIStroke", {
			Color = badgeTheme.stroke,
			Transparency = 0.12,
			Thickness = 1.1,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, badgeTheme.fill),
				ColorSequenceKeypoint.new(1, badgeTheme.fillAlt),
			}),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		Label = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Size = UDim2.new(0, 0, 1, 0),
			Text = string.upper(text),
			TextColor3 = badgeTheme.text,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}),
	})
end

return Badge
