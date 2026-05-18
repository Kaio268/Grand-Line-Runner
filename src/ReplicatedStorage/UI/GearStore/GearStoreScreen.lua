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
	ButtonText = Color3.fromRGB(30, 24, 14),
}

local function gearRow(props)
	return e("Frame", {
		BackgroundColor3 = COLORS.PanelSoft,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 88),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = COLORS.Gold,
			Transparency = 0.56,
			Thickness = 1,
		}),
		Icon = e("ImageLabel", {
			BackgroundColor3 = COLORS.Panel,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Image = props.icon,
			Position = UDim2.fromOffset(12, 17),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(54, 54),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(78, 12),
			Size = UDim2.new(1, -352, 0, 24),
			Text = props.name,
			TextColor3 = COLORS.Text,
			TextSize = 17,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Type = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(78, 40),
			Size = UDim2.new(1, -352, 0, 20),
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
				Color = COLORS.Gold,
				Transparency = 0.42,
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
			Color = COLORS.Gold,
			Transparency = 0.08,
			Thickness = 1.4,
		}),
		Header = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(22, 16),
			Size = UDim2.new(1, -88, 0, 32),
			Text = "GEAR STORE",
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
