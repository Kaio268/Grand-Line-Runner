local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local COLORS = {
	Backdrop = Color3.fromRGB(7, 14, 25),
	PanelSoft = Color3.fromRGB(21, 38, 61),
	Gold = Color3.fromRGB(212, 175, 55),
	GoldSoft = Color3.fromRGB(242, 209, 107),
	Text = Color3.fromRGB(241, 237, 226),
	Muted = Color3.fromRGB(187, 196, 211),
	ButtonText = Color3.fromRGB(30, 24, 14),
}

local function statRow(props)
	return e("Frame", {
		BackgroundColor3 = COLORS.PanelSoft,
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 54),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(14, 0),
			Size = UDim2.new(0.55, -14, 1, 0),
			Text = props.label,
			TextColor3 = COLORS.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromScale(0.55, 0),
			Size = UDim2.new(0.45, -14, 1, 0),
			Text = props.value,
			TextColor3 = COLORS.GoldSoft,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

local function LimitedRewardScreen(props)
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = COLORS.Backdrop,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = COLORS.Gold,
			Transparency = 0.08,
			Thickness = 1.4,
		}),
		Header = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(22, 16),
			Size = UDim2.new(1, -88, 0, 32),
			Text = "LIMITED REWARD",
			TextColor3 = COLORS.GoldSoft,
			TextSize = 24,
			TextStrokeColor3 = COLORS.GoldSoft,
			TextStrokeTransparency = 0.52,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Close = e("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundColor3 = Color3.fromRGB(158, 34, 39),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -16, 0, 16),
			Size = UDim2.fromOffset(34, 34),
			Text = "X",
			TextColor3 = COLORS.Text,
			TextSize = 16,
			[React.Event.Activated] = props.onClose,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}),
		Body = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(22, 66),
			Size = UDim2.new(1, -44, 1, -88),
		}, {
			Layout = e("UIListLayout", {
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Like = e(statRow, {
				label = "Leave a Like",
				layoutOrder = 1,
				value = props.likeText,
			}),
			Favorite = e(statRow, {
				label = "Favorite the Game",
				layoutOrder = 2,
				value = props.favoriteText,
			}),
			Claim = e("TextButton", {
				BackgroundColor3 = COLORS.Gold,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBlack,
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 46),
				Text = "CLAIM",
				TextColor3 = COLORS.ButtonText,
				TextSize = 18,
				[React.Event.Activated] = props.onClaim,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
			}),
			Footer = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.Gotham,
				LayoutOrder = 4,
				Size = UDim2.new(1, 0, 0, 32),
				Text = props.statusText,
				TextColor3 = COLORS.Muted,
				TextSize = 14,
				TextWrapped = true,
			}),
		}),
	})
end

return LimitedRewardScreen
