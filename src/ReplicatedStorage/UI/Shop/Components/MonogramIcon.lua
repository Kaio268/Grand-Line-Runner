local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function MonogramIcon(props)
	local surface = Theme.getSurfaceTheme(props.themeKey)
	local size = props.size or UDim2.fromOffset(78, 78)

	return e("Frame", {
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = surface.glow,
		BackgroundTransparency = 0.78,
		BorderSizePixel = 0,
		Position = props.position,
		Size = size,
		ZIndex = props.zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Glow = e("UIStroke", {
			Color = surface.glow,
			Transparency = 0.72,
			Thickness = 5,
		}),
		Core = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = surface.fill,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -10, 1, -10),
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = surface.stroke,
				Transparency = 0.08,
				Thickness = 1.3,
			}),
			Gradient = e("UIGradient", {
				Rotation = 55,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, surface.accent),
					ColorSequenceKeypoint.new(1, surface.fillAlt),
				}),
			}),
			Inset = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = surface.fill,
				BackgroundTransparency = 0.12,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -12, 1, -12),
				ZIndex = props.zIndex and (props.zIndex + 2) or nil,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
			Label = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -16, 1, -16),
				Text = tostring(props.label or "?"),
				TextColor3 = Theme.Palette.Text,
				TextScaled = true,
				TextStrokeTransparency = 0.65,
				TextWrapped = true,
				ZIndex = props.zIndex and (props.zIndex + 3) or nil,
			}),
		}),
	})
end

return MonogramIcon
