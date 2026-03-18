local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local Badge = require(script.Parent:WaitForChild("Badge"))
local MonogramIcon = require(script.Parent:WaitForChild("MonogramIcon"))
local PriceDisplay = require(script.Parent:WaitForChild("PriceDisplay"))

local e = React.createElement

local function FeaturedOfferCard(props)
	local item = props.item
	local state = item.purchaseState or {}
	local surface = Theme.getSurfaceTheme(item.themeKey)
	local hovered, setHovered = React.useState(false)
	local isWide = props.isWide ~= false
	local leftColumnWidth = isWide and 176 or 154
	local iconSize = isWide and 124 or 112
	local iconX = isWide and -8 or -6
	local iconY = isWide and 50 or 56
	local copyX = leftColumnWidth + 26
	local copyWidthOffset = copyX + 22
	local footerHeight = 58

	local children = {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 24),
		}),
		Stroke = e("UIStroke", {
			Color = surface.stroke,
			Transparency = hovered and 0.02 or 0.12,
			Thickness = hovered and 1.9 or 1.4,
		}),
		Glow = e("UIStroke", {
			Color = surface.glow,
			Transparency = hovered and 0.68 or 0.82,
			Thickness = 5,
		}),
		Gradient = e("UIGradient", {
			Rotation = 135,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, surface.fill),
				ColorSequenceKeypoint.new(0.45, surface.accentSoft),
				ColorSequenceKeypoint.new(1, surface.fillAlt),
			}),
		}),
		Accent = e("Frame", {
			BackgroundColor3 = surface.accent,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(-40, -30),
			Size = UDim2.fromOffset(200, 200),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 20),
			PaddingRight = UDim.new(0, 20),
			PaddingTop = UDim.new(0, 18),
			PaddingBottom = UDim.new(0, 18),
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
				Size = UDim2.new(0, isWide and 220 or 170, 0, 14),
				Text = item.timerText,
				TextColor3 = surface.accent,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = props.zIndex and (props.zIndex + 2) or nil,
			}) or nil,
		}),
		Icon = e(MonogramIcon, {
			position = UDim2.fromOffset(iconX, iconY),
			size = UDim2.fromOffset(iconSize, iconSize),
			label = item.iconText,
			themeKey = item.themeKey,
			isLarge = true,
			zIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Eyebrow = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(copyX, 44),
			Size = UDim2.new(1, -copyWidthOffset, 0, 16),
			Text = "Featured / Top Offer",
			TextColor3 = Theme.Palette.Muted,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(copyX, 64),
			Size = UDim2.new(1, -copyWidthOffset, 0, isWide and 42 or 52),
			Text = item.title,
			TextColor3 = Theme.Palette.Text,
			TextSize = isWide and 30 or 28,
			TextStrokeTransparency = 1,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(copyX, isWide and 108 or 122),
			Size = UDim2.new(1, -copyWidthOffset, 0, isWide and 54 or 62),
			Text = item.description,
			TextColor3 = Theme.Palette.Muted,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = props.zIndex and (props.zIndex + 2) or nil,
		}),
		Price = e(PriceDisplay, {
			position = UDim2.new(0, copyX, 1, -footerHeight),
			size = UDim2.new(1, -copyWidthOffset, 0, footerHeight - 2),
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
	}

	return e("Frame", {
		Active = true,
		BackgroundColor3 = surface.fill,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Size = props.size or UDim2.new(1, 0, 0, 192),
		ZIndex = props.zIndex,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, children)
end

return FeaturedOfferCard
