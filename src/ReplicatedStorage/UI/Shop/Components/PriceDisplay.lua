local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function giftIcon(iconColor, zIndex)
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(18, 18),
		ZIndex = zIndex,
	}, {
		Body = e("Frame", {
			BackgroundColor3 = iconColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(3, 8),
			Size = UDim2.fromOffset(12, 8),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 3),
			}),
		}),
		Lid = e("Frame", {
			BackgroundColor3 = iconColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2, 6),
			Size = UDim2.fromOffset(14, 3),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 2),
			}),
		}),
		RibbonVertical = e("Frame", {
			BackgroundColor3 = Theme.Palette.Text,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 5),
			Size = UDim2.fromOffset(2, 11),
			ZIndex = zIndex and (zIndex + 1) or nil,
		}),
		RibbonHorizontal = e("Frame", {
			BackgroundColor3 = Theme.Palette.Text,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(3, 9),
			Size = UDim2.fromOffset(12, 2),
			ZIndex = zIndex and (zIndex + 1) or nil,
		}),
		BowLeft = e("Frame", {
			BackgroundColor3 = iconColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(4, 2),
			Rotation = -28,
			Size = UDim2.fromOffset(5, 5),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		BowRight = e("Frame", {
			BackgroundColor3 = iconColor,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(9, 2),
			Rotation = 28,
			Size = UDim2.fromOffset(5, 5),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
	})
end

local function PriceDisplay(props)
	local rootRef = React.useRef(nil)
	local footerWidth, setFooterWidth = React.useState(0)
	local surface = Theme.getSurfaceTheme(props.themeKey)
	local height = props.compact and 42 or 50
	local buttonEnabled = props.buttonEnabled ~= false
	local priceLabel = props.isPriceLoading and "..." or Theme.formatPrice(props.priceText)
	local purchaseText
	local buttonTextColor = buttonEnabled and Theme.Palette.Ink or Theme.Palette.Text
	local giftButtonColor = buttonEnabled and Theme.Palette.GoldSoft or Theme.Palette.ButtonInactive
	local giftIconColor = buttonEnabled and Theme.Palette.Ink or Theme.Palette.Text
	local controlHeight = props.compact and 34 or 38
	local giftSize = controlHeight
	local gap = props.compact and 8 or 9
	local horizontalInset = props.compact and 12 or 18

	React.useEffect(function()
		local root = rootRef.current
		if not root then
			return nil
		end

		local function updateWidth()
			setFooterWidth(root.AbsoluteSize.X)
		end

		updateWidth()
		local connection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateWidth)

		return function()
			connection:Disconnect()
		end
	end, {})

	if props.isOwned then
		purchaseText = "Owned"
	else
		purchaseText = tostring(priceLabel or "...")
	end

	local fallbackWidth = props.compact and 236 or 332
	local availableSpace = math.max(120, (footerWidth > 0 and footerWidth or fallbackWidth) - (horizontalInset * 2))
	local minPurchaseWidth = props.compact and 128 or 156
	local purchaseWidthRatio = props.compact and 0.56 or 0.6
	local maxPurchaseWidth = math.max(minPurchaseWidth, availableSpace - giftSize - gap)
	local purchaseWidth = math.floor(math.clamp(availableSpace * purchaseWidthRatio, minPurchaseWidth, maxPurchaseWidth))
	local groupWidth = purchaseWidth + giftSize + gap

	return e("Frame", {
		ref = rootRef,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Position = props.position,
		Size = props.size or UDim2.new(1, 0, 0, height),
		ZIndex = props.zIndex,
	}, {
		Row = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(groupWidth, controlHeight),
			ZIndex = props.zIndex,
		}, {
			PurchaseButton = e("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = buttonEnabled and surface.accent or Theme.Palette.ButtonInactive,
				BorderSizePixel = 0,
				Size = UDim2.fromOffset(purchaseWidth, controlHeight),
				Text = "",
				ZIndex = props.zIndex,
				[React.Event.Activated] = buttonEnabled and props.onActivated or nil,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 12),
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, buttonEnabled and surface.accent or Theme.Palette.PanelSoft),
						ColorSequenceKeypoint.new(1, buttonEnabled and surface.accentSoft or Theme.Palette.ButtonInactive),
					}),
				}),
				Content = e("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.new(1, -10, 1, -4),
					ZIndex = props.zIndex and (props.zIndex + 1) or nil,
				}, {
					List = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 5),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Robux = not props.isOwned and e("ImageLabel", {
						BackgroundTransparency = 1,
						Image = Theme.Assets.RobuxIcon,
						ImageColor3 = buttonTextColor,
						LayoutOrder = 1,
						Size = UDim2.fromOffset(props.compact and 12 or 14, props.compact and 12 or 14),
						ZIndex = props.zIndex and (props.zIndex + 2) or nil,
					}) or nil,
					Label = e("TextLabel", {
						AutomaticSize = Enum.AutomaticSize.X,
						BackgroundTransparency = 1,
						Font = Theme.Fonts.Display,
						LayoutOrder = 2,
						Size = UDim2.new(0, 0, 1, 0),
						Text = purchaseText,
						TextColor3 = buttonTextColor,
						TextSize = props.compact and 13 or 15,
						TextXAlignment = Enum.TextXAlignment.Center,
						ZIndex = props.zIndex and (props.zIndex + 2) or nil,
					}),
				}),
			}),
			GiftButton = e("TextButton", {
				AutoButtonColor = false,
				BackgroundColor3 = giftButtonColor,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(purchaseWidth + gap, 0),
				Size = UDim2.fromOffset(giftSize, controlHeight),
				Text = "",
				ZIndex = props.zIndex,
				[React.Event.Activated] = props.onGiftActivated,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 12),
				}),
				Icon = giftIcon(giftIconColor, props.zIndex and (props.zIndex + 2) or nil),
			}),
		}),
	})
end

return PriceDisplay
