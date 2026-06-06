local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function MonogramIcon(props)
	local size = props.size or UDim2.fromOffset(78, 78)
	local hasImage = props.image and props.image ~= ""

	return e("Frame", {
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = props.position,
		Size = size,
		ZIndex = props.zIndex,
	}, {
		Icon = hasImage and e("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.image,
			ImageColor3 = Color3.fromRGB(255, 255, 255),
			ImageTransparency = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(1, 1),
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}) or e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, 1),
			Text = tostring(props.label or "?"),
			TextColor3 = Theme.Palette.GoldSoft,
			TextScaled = true,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.4,
			TextWrapped = true,
			ZIndex = props.zIndex and (props.zIndex + 1) or nil,
		}),
	})
end

return MonogramIcon
