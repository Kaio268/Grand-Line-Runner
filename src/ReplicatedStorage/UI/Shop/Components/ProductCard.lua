local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local MonogramIcon = require(script.Parent:WaitForChild("MonogramIcon"))
local PriceDisplay = require(script.Parent:WaitForChild("PriceDisplay"))

local e = React.createElement

local function buildTagRow(tags, zIndex)
	local tagChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local tagCount = math.min(3, #(tags or {}))
	if tagCount <= 0 then
		return nil
	end

	local cellOffset = math.ceil((6 * math.max(0, tagCount - 1)) / tagCount)
	for index = 1, tagCount do
		tagChildren["Tag" .. tostring(index)] = e("Frame", {
			BackgroundColor3 = Theme.Palette.PanelSoft,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1 / tagCount, -cellOffset, 0, 22),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Size = UDim2.new(1, -8, 1, 0),
				Position = UDim2.fromOffset(4, 0),
				Text = tostring(tags[index] or ""),
				TextColor3 = Theme.Palette.Muted,
				TextSize = 10,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = zIndex and (zIndex + 1) or nil,
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 174),
		Size = UDim2.new(1, -32, 0, 22),
		ZIndex = zIndex,
	}, tagChildren)
end

local function ProductCard(props)
	local item = props.item or {}
	local state = item.purchaseState or {}
	local surface = Theme.getSurfaceTheme(item.themeKey)
	local hovered, setHovered = React.useState(false)
	local footerHeight = 46
	local contentZ = props.zIndex and (props.zIndex + 2) or nil

	return e("Frame", {
		Active = true,
		BackgroundColor3 = surface.fill,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Size = props.size or UDim2.fromScale(1, 1),
		ZIndex = props.zIndex,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			Color = surface.stroke,
			Transparency = hovered and 0.08 or 0.28,
			Thickness = hovered and 1.5 or 1,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, surface.fill),
				ColorSequenceKeypoint.new(1, surface.fillAlt),
			}),
		}),
		Icon = e(MonogramIcon, {
			position = UDim2.new(0.5, -42, 0, 14),
			size = UDim2.fromOffset(84, 84),
			image = Theme.getItemIcon(item),
			label = item.iconText,
			themeKey = item.themeKey,
			isLarge = true,
			zIndex = contentZ,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(14, 104),
			Size = UDim2.new(1, -28, 0, 38),
			Text = item.title or "",
			TextColor3 = Theme.Palette.Text,
			TextSize = 21,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = contentZ,
		}),
		Subtitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(16, 142),
			Size = UDim2.new(1, -32, 0, 20),
			Text = tostring(item.subtitle or item.description or ""),
			TextColor3 = surface.accentSoft,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = contentZ,
		}),
		Tags = buildTagRow(item.tags, contentZ),
		Price = e(PriceDisplay, {
			position = UDim2.new(0, 0, 1, -footerHeight),
			size = UDim2.new(1, 0, 0, footerHeight),
			compact = true,
			priceText = state.priceText,
			buttonText = state.buttonText,
			buttonEnabled = state.buttonEnabled,
			isOwned = state.isOwned,
			isPriceLoading = state.isPriceLoading,
			statusText = state.statusText,
			themeKey = item.themeKey,
			zIndex = contentZ,
			onActivated = function()
				if props.onPurchaseRequested then
					props.onPurchaseRequested(item)
				end
			end,
		}),
	})
end

return ProductCard
