local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local MonogramIcon = require(script.Parent:WaitForChild("MonogramIcon"))
local PriceDisplay = require(script.Parent:WaitForChild("PriceDisplay"))

local e = React.createElement

local function hasDetails(item)
	return tostring(item.description or "") ~= ""
		or #(item.includes or {}) > 0
		or #(item.detailGroups or {}) > 0
end

local function buildTagRow(tags, positionY, zIndex)
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
		Position = UDim2.fromOffset(16, positionY),
		Size = UDim2.new(1, -32, 0, 22),
		ZIndex = zIndex,
	}, tagChildren)
end

local function getSelectedVariant(item, selectedVariantId)
	local variants = item.variants or {}
	if #variants <= 0 then
		return nil
	end

	for _, variant in ipairs(variants) do
		if tostring(variant.id or "") == tostring(selectedVariantId or "") then
			return variant
		end
	end

	return variants[1]
end

local function buildVariantRow(item, selectedVariant, setSelectedVariantId, surface, zIndex)
	local variants = item.variants or {}
	if #variants <= 0 then
		return nil
	end

	local children = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	local count = #variants
	local cellOffset = math.ceil((6 * math.max(0, count - 1)) / count)
	for index, variant in ipairs(variants) do
		local isSelected = selectedVariant and tostring(selectedVariant.id) == tostring(variant.id)
		local state = variant.purchaseState or {}
		local priceText = Theme.formatPrice(state.priceText or variant.priceText or "Soon")
		children["Variant" .. tostring(index)] = e("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = isSelected and surface.accent or Theme.Palette.PanelSoft,
			BackgroundTransparency = isSelected and 0 or 0.08,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1 / count, -cellOffset, 0, 32),
			Text = "",
			ZIndex = zIndex,
			[React.Event.Activated] = function()
				setSelectedVariantId(variant.id)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 9),
			}),
			Stroke = e("UIStroke", {
				Color = isSelected and surface.accentSoft or Theme.Palette.BorderSoft,
				Transparency = isSelected and 0.15 or 0.45,
				Thickness = 1,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Size = UDim2.new(1, -6, 1, 0),
				Position = UDim2.fromOffset(3, 0),
				Text = string.format("%s\n%s", tostring(variant.label or ""), tostring(priceText)),
				TextColor3 = isSelected and Theme.Palette.Ink or Theme.Palette.Text,
				TextSize = 10,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = zIndex and (zIndex + 1) or nil,
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 188),
		Size = UDim2.new(1, -32, 0, 32),
		ZIndex = zIndex,
	}, children)
end

local function ProductCard(props)
	local item = props.item or {}
	local variants = item.variants or {}
	local initialVariantId = variants[1] and variants[1].id or nil
	local selectedVariantId, setSelectedVariantId = React.useState(initialVariantId)
	local selectedVariant = getSelectedVariant(item, selectedVariantId)
	local state = (selectedVariant and selectedVariant.purchaseState) or item.purchaseState or {}
	local surface = Theme.getSurfaceTheme(item.themeKey)
	local hovered, setHovered = React.useState(false)
	local footerHeight = 46
	local contentZ = props.zIndex and (props.zIndex + 2) or nil
	local showDetails = hasDetails(item)
	local hasVariants = #variants > 0

	React.useEffect(function()
		setSelectedVariantId(initialVariantId)
		return nil
	end, { item.id })

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
			position = UDim2.new(0.5, -36, 0, 12),
			size = UDim2.fromOffset(72, 72),
			image = Theme.getItemIcon(item),
			label = item.iconText,
			themeKey = item.themeKey,
			isLarge = true,
			zIndex = contentZ,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(14, 86),
			Size = UDim2.new(1, -28, 0, 34),
			Text = item.title or "",
			TextColor3 = Theme.Palette.Text,
			TextSize = 20,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = contentZ,
		}),
		Subtitle = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(16, 121),
			Size = UDim2.new(1, -32, 0, 20),
			Text = tostring(item.subtitle or ""),
			TextColor3 = surface.accentSoft,
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = contentZ,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(16, 144),
			Size = UDim2.new(1, -32, 0, 36),
			Text = tostring(item.description or ""),
			TextColor3 = Theme.Palette.Muted,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = contentZ,
		}),
		Variants = buildVariantRow(item, selectedVariant, setSelectedVariantId, surface, contentZ),
		Tags = if hasVariants then nil else buildTagRow(item.tags, 190, contentZ),
		Details = showDetails and e("TextButton", {
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(16, hasVariants and 222 or 218),
			Size = UDim2.new(1, -32, 0, 18),
			Text = "Details",
			TextColor3 = surface.accentSoft,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = contentZ,
			[React.Event.Activated] = function()
				if props.onDetailsRequested then
					props.onDetailsRequested(item)
				end
			end,
		}) or nil,
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
					props.onPurchaseRequested(item, selectedVariant)
				end
			end,
		}),
	})
end

return ProductCard
