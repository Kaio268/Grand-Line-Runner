local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))

local e = React.createElement

local function PriceDisplay(props)
	local rootRef = React.useRef(nil)
	local footerWidth, setFooterWidth = React.useState(0)
	local surface = Theme.getSurfaceTheme(props.themeKey)
	local height = props.compact and 42 or 48
	local buttonEnabled = props.buttonEnabled ~= false
	local priceLabel = props.isPriceLoading and "..." or Theme.formatPrice(props.priceText)
	local purchaseText
	local controlHeight = props.compact and 34 or 38
	local horizontalInset = props.compact and 14 or 18

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
	elseif buttonEnabled == false and props.buttonText ~= nil and tostring(props.buttonText) ~= "" then
		purchaseText = tostring(props.buttonText)
	else
		purchaseText = tostring(priceLabel or "...")
	end

	local fallbackWidth = props.compact and 236 or 332
	local availableSpace = math.max(120, (footerWidth > 0 and footerWidth or fallbackWidth) - (horizontalInset * 2))
	local purchaseWidth = math.floor(math.clamp(availableSpace, props.compact and 146 or 168, props.compact and 228 or 260))
	local buttonTextColor = buttonEnabled and Theme.Palette.Ink or Theme.Palette.Text
	local showRobuxIcon = buttonEnabled and props.isOwned ~= true

	return e("Frame", {
		ref = rootRef,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 0,
		Position = props.position,
		Size = props.size or UDim2.new(1, 0, 0, height),
		ZIndex = props.zIndex,
	}, {
		PurchaseButton = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = buttonEnabled and surface.accent or Theme.Palette.ButtonInactive,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(purchaseWidth, controlHeight),
			Text = "",
			ZIndex = props.zIndex,
			[React.Event.Activated] = buttonEnabled and props.onActivated or nil,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, buttonEnabled and surface.accentSoft or Theme.Palette.PanelSoft),
					ColorSequenceKeypoint.new(1, buttonEnabled and surface.accent or Theme.Palette.ButtonInactive),
				}),
			}),
			Content = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.new(1, -12, 1, 0),
				ZIndex = props.zIndex and (props.zIndex + 1) or nil,
			}, {
				List = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, 5),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Robux = showRobuxIcon and e("ImageLabel", {
					BackgroundTransparency = 1,
					Image = Theme.Assets.RobuxIcon,
					ImageColor3 = buttonTextColor,
					LayoutOrder = 1,
					Size = UDim2.fromOffset(props.compact and 13 or 15, props.compact and 13 or 15),
					ZIndex = props.zIndex and (props.zIndex + 2) or nil,
				}) or nil,
				Label = e("TextLabel", {
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Display,
					LayoutOrder = 2,
					Size = UDim2.fromScale(0, 1),
					Text = purchaseText,
					TextColor3 = buttonTextColor,
					TextSize = props.compact and 13 or 15,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = props.zIndex and (props.zIndex + 2) or nil,
				}),
			}),
		}),
	})
end

return PriceDisplay
