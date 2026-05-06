local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local PALETTE = {
	Board = Color3.fromRGB(28, 41, 56),
	BoardSoft = Color3.fromRGB(42, 60, 80),
	Ink = Color3.fromRGB(12, 18, 25),
	Gold = Color3.fromRGB(212, 175, 55),
	GoldSoft = Color3.fromRGB(242, 209, 107),
	GoldBright = Color3.fromRGB(255, 241, 176),
	Cyan = Color3.fromRGB(126, 209, 255),
	Text = Color3.fromRGB(250, 249, 255),
	Shadow = Color3.fromRGB(3, 7, 18),
}

local function VIPBarrierSign(props)
	props = props or {}

	local widthPixels = props.WidthPixels or 240
	local heightPixels = props.HeightPixels or 120
	local minDimension = math.max(1, math.min(widthPixels, heightPixels))
	local cornerRadius = math.max(10, math.floor(minDimension * 0.07))
	local accentHeight = math.max(2, math.floor(minDimension * 0.018))

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, {
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = PALETTE.Board,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(widthPixels, heightPixels),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, cornerRadius),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = PALETTE.GoldSoft,
				Thickness = 2,
				Transparency = 0.28,
			}),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, PALETTE.BoardSoft),
					ColorSequenceKeypoint.new(0.54, PALETTE.Board),
					ColorSequenceKeypoint.new(1, PALETTE.Ink),
				}),
				Rotation = 90,
			}),

			TopAccent = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundColor3 = PALETTE.Cyan,
				BackgroundTransparency = 0.32,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.12),
				Size = UDim2.new(0.58, 0, 0, accentHeight),
				ZIndex = 3,
			}),

			BottomAccent = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = PALETTE.Gold,
				BackgroundTransparency = 0.38,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.88),
				Size = UDim2.new(0.42, 0, 0, accentHeight),
				ZIndex = 3,
			}),

			VipShadow = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.FredokaOne,
				Position = UDim2.fromScale(0.508, 0.4),
				Size = UDim2.fromScale(0.72, 0.48),
				Text = "VIP",
				TextColor3 = PALETTE.Shadow,
				TextScaled = true,
				TextTransparency = 0.1,
				ZIndex = 4,
			}, {
				SizeConstraint = e("UITextSizeConstraint", {
					MaxTextSize = 180,
					MinTextSize = 16,
				}),
			}),

			Vip = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.FredokaOne,
				Position = UDim2.fromScale(0.5, 0.36),
				Size = UDim2.fromScale(0.72, 0.48),
				Text = "VIP",
				TextColor3 = PALETTE.GoldBright,
				TextScaled = true,
				TextStrokeColor3 = PALETTE.Shadow,
				TextStrokeTransparency = 0.08,
				ZIndex = 5,
			}, {
				SizeConstraint = e("UITextSizeConstraint", {
					MaxTextSize = 180,
					MinTextSize = 16,
				}),
			}),

			Access = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.fromScale(0.5, 0.68),
				Size = UDim2.fromScale(0.78, 0.2),
				Text = "ACCESS ONLY",
				TextColor3 = PALETTE.Text,
				TextScaled = true,
				TextStrokeColor3 = PALETTE.Shadow,
				TextStrokeTransparency = 0.16,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 5,
			}, {
				SizeConstraint = e("UITextSizeConstraint", {
					MaxTextSize = 48,
					MinTextSize = 10,
				}),
			}),
		}),
	})
end

return VIPBarrierSign
