local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local COLORS = {
	Backdrop = Color3.fromRGB(8, 8, 9),
	Panel = Color3.fromRGB(16, 16, 19),
	PanelSoft = Color3.fromRGB(20, 20, 24),
	Gold = Color3.fromRGB(228, 190, 78),
	GoldSoft = Color3.fromRGB(255, 224, 120),
	GoldShadow = Color3.fromRGB(150, 112, 42),
	Text = Color3.fromRGB(235, 235, 235),
	Muted = Color3.fromRGB(190, 194, 202),
	ButtonText = Color3.fromRGB(30, 24, 14),
}

local function gearRow(props)
	return e("Frame", {
		BackgroundColor3 = COLORS.PanelSoft,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 88),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = COLORS.GoldSoft,
			Transparency = 0.48,
			Thickness = 1.1,
		}),
		Icon = e("ImageLabel", {
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.02,
			BorderSizePixel = 0,
			Image = props.icon,
			Position = UDim2.fromOffset(12, 14),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(60, 60),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = COLORS.Gold,
				Transparency = 0.62,
				Thickness = 1,
			}),
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(84, 12),
			Size = UDim2.new(1, -358, 0, 24),
			Text = props.name,
			TextColor3 = COLORS.Text,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Type = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(84, 40),
			Size = UDim2.new(1, -358, 0, 20),
			Text = props.typeText,
			TextColor3 = COLORS.Muted,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Buy = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			BackgroundColor3 = COLORS.Gold,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -146, 1, -12),
			Size = UDim2.fromOffset(126, 36),
			Text = props.buyText,
			TextColor3 = COLORS.ButtonText,
			TextSize = 15,
			[React.Event.Activated] = props.onBuy,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = COLORS.GoldSoft,
				Transparency = 0.22,
				Thickness = 1,
			}),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, COLORS.GoldSoft),
					ColorSequenceKeypoint.new(1, COLORS.Gold),
				}),
				Rotation = 90,
			}),
		}),
		Robux = props.showRobux and e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			BackgroundColor3 = COLORS.Panel,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -12, 1, -12),
			Size = UDim2.fromOffset(126, 36),
			Text = props.robuxText,
			TextColor3 = COLORS.GoldSoft,
			TextSize = 15,
			[React.Event.Activated] = props.onRobux,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = COLORS.GoldSoft,
				Transparency = 0.36,
				Thickness = 1,
			}),
		}) or nil,
	})
end

local function GearStoreScreen(props)
	local children = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, item in ipairs(props.items or {}) do
		children["Gear" .. tostring(index)] = e(gearRow, {
			buyText = item.buyText,
			icon = item.icon,
			layoutOrder = index,
			name = item.name,
			onBuy = function()
				props.onBuy(item.name)
			end,
			onRobux = function()
				props.onRobux(item.name)
			end,
			robuxText = item.robuxText,
			showRobux = item.showRobux,
			typeText = item.typeText,
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
			Color = COLORS.GoldSoft,
			Transparency = 0.08,
			Thickness = 1.6,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, COLORS.Panel),
				ColorSequenceKeypoint.new(0.46, COLORS.Backdrop),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 5, 6)),
			}),
			Rotation = 90,
		}),
		Header = e("TextLabel", {
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.02,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(22, 16),
			Size = UDim2.fromOffset(230, 36),
			Text = "GEAR STORE",
			TextColor3 = COLORS.GoldSoft,
			TextSize = 22,
			TextStrokeColor3 = COLORS.GoldSoft,
			TextStrokeTransparency = 0.62,
			TextXAlignment = Enum.TextXAlignment.Center,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = COLORS.GoldSoft,
				Transparency = 0.22,
				Thickness = 1.2,
			}),
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
			Stroke = e("UIStroke", {
				Color = COLORS.GoldShadow,
				Transparency = 0.18,
				Thickness = 1,
			}),
		}),
		List = e("ScrollingFrame", {
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			Position = UDim2.fromOffset(22, 64),
			ScrollBarImageColor3 = COLORS.Gold,
			ScrollBarThickness = 8,
			Size = UDim2.new(1, -44, 1, -86),
		}, children),
	})
end

return GearStoreScreen
