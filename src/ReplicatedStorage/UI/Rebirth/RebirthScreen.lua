local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local COLORS = {
	Backdrop = Color3.fromRGB(7, 14, 25),
	Panel = Color3.fromRGB(15, 28, 47),
	PanelSoft = Color3.fromRGB(21, 38, 61),
	Gold = Color3.fromRGB(212, 175, 55),
	GoldSoft = Color3.fromRGB(242, 209, 107),
	Text = Color3.fromRGB(241, 237, 226),
	Muted = Color3.fromRGB(187, 196, 211),
	Good = Color3.fromRGB(120, 224, 154),
}

local function requirementRow(props)
	return e("Frame", {
		BackgroundColor3 = COLORS.PanelSoft,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 76),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = COLORS.Gold,
			Transparency = 0.56,
			Thickness = 1,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(16, 10),
			Size = UDim2.new(0.4, -16, 0, 22),
			Text = props.label,
			TextColor3 = COLORS.Text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0.4, 0, 0, 10),
			Size = UDim2.new(0.6, -16, 0, 22),
			Text = props.valueText,
			TextColor3 = props.complete and COLORS.Good or COLORS.Text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		Track = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(8, 13, 23),
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(16, 44),
			Size = UDim2.new(1, -32, 0, 16),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Fill = e("Frame", {
				BackgroundColor3 = props.complete and COLORS.Good or COLORS.GoldSoft,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(math.clamp(props.progress or 0, 0, 1), 1),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		}),
	})
end

local function rewardRow(props)
	return e("Frame", {
		BackgroundColor3 = COLORS.PanelSoft,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 48),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Icon = props.icon ~= "" and e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = props.icon,
			Position = UDim2.fromOffset(10, 8),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(32, 32),
		}) or nil,
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(52, 0),
			Size = UDim2.new(1, -62, 1, 0),
			Text = props.text,
			TextColor3 = COLORS.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function RebirthScreen(props)
	local rewards = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, reward in ipairs(props.rewards or {}) do
		rewards["Reward" .. tostring(index)] = e(rewardRow, {
			icon = reward.icon or "",
			layoutOrder = index,
			text = reward.text or "",
		})
	end

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
			Text = "REBIRTH",
			TextColor3 = COLORS.GoldSoft,
			TextSize = 26,
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
			Position = UDim2.fromOffset(22, 64),
			Size = UDim2.new(1, -44, 1, -86),
		}, {
			Layout = e("UIListLayout", {
				Padding = UDim.new(0, 12),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Money = e(requirementRow, {
				complete = props.moneyComplete,
				label = "Beli",
				layoutOrder = 1,
				progress = props.moneyProgress,
				valueText = props.moneyText,
			}),
			Ship = e(requirementRow, {
				complete = props.shipComplete,
				label = "Ship Level",
				layoutOrder = 2,
				progress = props.shipProgress,
				valueText = props.shipText,
			}),
			RewardTitle = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				LayoutOrder = 3,
				Size = UDim2.new(1, 0, 0, 24),
				Text = "You Get",
				TextColor3 = COLORS.Muted,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			RewardList = e("Frame", {
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 4,
				Size = UDim2.fromScale(1, 0),
			}, rewards),
			Rebirth = e("TextButton", {
				BackgroundColor3 = props.canRebirth and COLORS.Gold or COLORS.PanelSoft,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBlack,
				LayoutOrder = 5,
				Size = UDim2.new(1, 0, 0, 46),
				Text = props.isMaxed and "MAXED" or "REBIRTH",
				TextColor3 = props.canRebirth and Color3.fromRGB(30, 24, 14) or COLORS.Muted,
				TextSize = 18,
				[React.Event.Activated] = if props.canRebirth then props.onRebirth else nil,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
			}),
		}),
	})
end

return RebirthScreen
