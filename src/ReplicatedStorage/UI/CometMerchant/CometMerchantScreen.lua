local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

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

local function offerRow(props)
	return e("Frame", {
		BackgroundColor3 = COLORS.PanelSoft,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 108),
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
			Position = UDim2.fromOffset(12, 28),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(52, 52),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(76, 10),
			Size = UDim2.new(1, -310, 0, 22),
			Text = props.name,
			TextColor3 = COLORS.Text,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Stock = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(76, 36),
			Size = UDim2.new(1, -310, 0, 20),
			Text = props.stockText,
			TextColor3 = COLORS.Muted,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(76, 60),
			Size = UDim2.new(1, -310, 0, 38),
			Text = props.description,
			TextColor3 = COLORS.Muted,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		Price = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -16, 0, 12),
			Size = UDim2.fromOffset(120, 20),
			Text = props.priceText,
			TextColor3 = COLORS.GoldSoft,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		Buy = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			BackgroundColor3 = props.canBuy and COLORS.Gold or COLORS.Panel,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -16, 1, -12),
			Size = UDim2.fromOffset(128, 36),
			Text = props.canBuy and "Buy" or "Sold Out",
			TextColor3 = props.canBuy and COLORS.ButtonText or COLORS.Muted,
			TextSize = 15,
			[React.Event.Activated] = if props.canBuy then props.onBuy else nil,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}),
	})
end

local function CometMerchantScreen(props)
	local children = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, offer in ipairs(props.offers or {}) do
		children["Offer" .. tostring(index)] = e(offerRow, {
			canBuy = offer.stock > 0,
			description = offer.description,
			icon = offer.icon,
			layoutOrder = index,
			name = offer.name,
			onBuy = function()
				props.onBuy(offer.fullPath)
			end,
			priceText = CurrencyUtil.formatCurrency(offer.price),
			stockText = string.format("x%d Stock", offer.stock),
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
			Text = "COMET MERCHANT",
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
		List = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(22, 64),
			Size = UDim2.new(1, -44, 1, -86),
		}, children),
	})
end

return CometMerchantScreen
