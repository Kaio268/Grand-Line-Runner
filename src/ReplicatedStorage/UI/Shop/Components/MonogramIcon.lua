local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function MonogramIcon(props)
	local surface = Theme.getSurfaceTheme(props.themeKey)
	local size = props.size or UDim2.fromOffset(78, 78)
	local outerInset = props.isLarge and 12 or 10
	local innerInset = props.isLarge and 14 or 12
	local iconInset = props.isLarge and 16 or 14
	local glowThickness = props.isLarge and 3 or 2.4
	local glowTransparency = props.isLarge and 0.78 or 0.8

	return e("Frame", {
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = surface.glow,
		BackgroundTransparency = 0.86,
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
			Transparency = glowTransparency,
			Thickness = glowThickness,
		}),
		Core = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = surface.fill,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -outerInset, 1, -outerInset),
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
				Size = UDim2.new(1, -innerInset, 1, -innerInset),
				ZIndex = props.zIndex and (props.zIndex + 2) or nil,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
			Icon = (props.image and props.image ~= "") and e("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = props.image,
				ImageColor3 = Color3.fromRGB(255, 255, 255),
				ImageTransparency = 0,
				Position = UDim2.fromScale(0.5, 0.5),
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.new(1, -iconInset, 1, -iconInset),
				ZIndex = props.zIndex and (props.zIndex + 3) or nil,
			}) or e("TextLabel", {
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
