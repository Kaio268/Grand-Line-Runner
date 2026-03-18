local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Badge = require(script.Parent:WaitForChild("Badge"))
local MonogramIcon = require(script.Parent:WaitForChild("MonogramIcon"))
local PriceDisplay = require(script.Parent:WaitForChild("PriceDisplay"))

local e = React.createElement

local function ProductCard(props)
	local item = props.item
	local state = item.purchaseState or {}
	local surface = Theme.getSurfaceTheme(item.themeKey)
	local hovered, setHovered = React.useState(false)
	local iconSize = 70
	local iconX = -6
	local iconY = 54
	local copyX = 106
	local copyWidthOffset = copyX + 18
	local footerHeight = 58

	return e("Frame", {
		Active = true,
		BackgroundColor3 = surface.fill,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Size = props.size or UDim2.new(1, 0, 1, 0),
		ZIndex = props.zIndex,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 20),
		}),
		Stroke = e("UIStroke", {
			Color = surface.stroke,
			Transparency = hovered and 0.05 or 0.22,
			Thickness = hovered and 1.6 or 1.2,
		}),
		Glow = e("UIStroke", {
			Color = surface.glow,
			Transparency = hovered and 0.78 or 0.9,
			Thickness = 4,
		}),
		Gradient = e("UIGradient", {
			Rotation = 125,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, surface.fill),
				ColorSequenceKeypoint.new(1, surface.fillAlt),
			}),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 16),
			PaddingRight = UDim.new(0, 16),
			PaddingTop = UDim.new(0, 16),
			PaddingBottom = UDim.new(0, 16),
		}),
		TopMeta = e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 28),
		}, {
			Badge = e(Badge, {
				text = item.badge,
				variant = item.badge,
				position = UDim2.fromOffset(0, 0),
				zIndex = props.zIndex and (props.zIndex + 2) or nil,
			}),
			Timer = item.timerText and e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Position = UDim2.new(1, 0, 0, 6),
				Size = UDim2.new(0, 136, 0, 12),
				Text = item.timerText,
				TextColor3 = surface.accent,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = props.zIndex and (props.zIndex + 2) or nil,
			}) or nil,
		}),
		Icon = e(MonogramIcon, {
			position = UDim2.fromOffset(iconX, iconY),
			size = UDim2.fromOffset(iconSize, iconSize),
			label = item.iconText,
			themeKey = item.themeKey,
			zIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(copyX, 48),
			Size = UDim2.new(1, -copyWidthOffset, 0, 40),
			Text = item.title,
			TextColor3 = Theme.Palette.Text,
			TextSize = 24,
			TextStrokeTransparency = 1,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(copyX, 96),
			Size = UDim2.new(1, -copyWidthOffset, 0, 64),
			Text = item.description,
			TextColor3 = Theme.Palette.Muted,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Price = e(PriceDisplay, {
			position = UDim2.new(0, 0, 1, -footerHeight),
			size = UDim2.new(1, 0, 0, footerHeight - 2),
			compact = true,
			priceText = state.priceText,
			buttonText = state.buttonText,
			buttonEnabled = state.buttonEnabled,
			isOwned = state.isOwned,
			isPriceLoading = state.isPriceLoading,
			statusText = state.statusText,
			themeKey = item.themeKey,
			zIndex = props.zIndex and (props.zIndex + 2) or nil,
			onActivated = function()
				if props.onPurchaseRequested then
					props.onPurchaseRequested(item)
				end
			end,
			onGiftActivated = function()
				if props.onGiftRequested then
					props.onGiftRequested(item)
				end
			end,
		}),
	})
end

return ProductCard
