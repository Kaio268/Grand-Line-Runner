local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	Panel = Color3.fromRGB(18, 24, 34),
	PanelStroke = Color3.fromRGB(235, 195, 92),
	Text = Color3.fromRGB(248, 248, 244),
	TextStroke = Color3.fromRGB(10, 10, 10),
	AvatarBg = Color3.fromRGB(255, 241, 198),
}

local function getAvatarImage(ownerUserId)
	local userId = tonumber(ownerUserId)
	if not userId or userId <= 0 then
		return ""
	end

	return string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", math.floor(userId))
end

local function ShipSailIdentityCard(props)
	local displayText = tostring(props.displayText or "Player's")
	local avatarImage = getAvatarImage(props.ownerUserId)

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		Card = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = THEME.Panel,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.62),
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.PanelStroke,
				Thickness = 3,
				Transparency = 0.12,
			}),
			Avatar = e("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = THEME.AvatarBg,
				BackgroundTransparency = 0.05,
				BorderSizePixel = 0,
				Image = avatarImage,
				Position = UDim2.fromScale(0.065, 0.5),
				ScaleType = Enum.ScaleType.Crop,
				Size = UDim2.fromScale(0.21, 0.72),
				ZIndex = 2,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Stroke = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = THEME.TextStroke,
					Thickness = 3,
					Transparency = 0.08,
				}),
			}),
			Name = e("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.fromScale(0.32, 0.5),
				Size = UDim2.fromScale(0.61, 0.62),
				Text = displayText,
				TextColor3 = THEME.Text,
				TextScaled = true,
				TextStrokeColor3 = THEME.TextStroke,
				TextStrokeTransparency = 0.12,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextWrapped = false,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 2,
			}, {
				SizeConstraint = e("UITextSizeConstraint", {
					MaxTextSize = 68,
					MinTextSize = 12,
				}),
			}),
		}),
	})
end

return ShipSailIdentityCard
