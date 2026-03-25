local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local React = require(Packages:WaitForChild("React"))
local HudCounterConfig = require(script.Parent:WaitForChild("HudCounterConfig"))
local HudStatsTheme = require(script.Parent:WaitForChild("HudStatsTheme"))

local e = React.createElement

local function findFirstChildOfClass(instance, className)
	if not instance then
		return nil
	end

	return instance:FindFirstChildOfClass(className)
end

local function getTextStrokeTransparency(host, stroke)
	if stroke then
		return stroke.Transparency
	end

	return tonumber(host.TextStrokeTransparency) or 0
end

local function getTextStrokeColor(host, stroke, fallback)
	if stroke then
		return stroke.Color
	end

	local hostColor = host.TextStrokeColor3
	if typeof(hostColor) == "Color3" then
		return hostColor
	end

	return fallback
end

local function snapshot(host, iconSource, palette)
	local stroke = findFirstChildOfClass(host, "UIStroke")
	local iconScale = iconSource and findFirstChildOfClass(iconSource, "UIScale") or nil

	return {
		text = tostring(host.Text or ""),
		font = host.Font,
		fontFace = host.FontFace,
		textStrokeColor3 = getTextStrokeColor(host, stroke, palette.stroke),
		textStrokeTransparency = getTextStrokeTransparency(host, stroke),
		textTransparency = 0,
		zIndex = tonumber(host.ZIndex) or 1,
		iconImage = iconSource and tostring(iconSource.Image or "") or "",
		iconColor3 = iconSource and iconSource.ImageColor3 or Color3.fromRGB(255, 255, 255),
		iconImageRectOffset = iconSource and iconSource.ImageRectOffset or Vector2.zero,
		iconImageRectSize = iconSource and iconSource.ImageRectSize or Vector2.zero,
		iconRotation = iconSource and tonumber(iconSource.Rotation) or 0,
		iconScale = iconScale and tonumber(iconScale.Scale) or 1,
		iconImageTransparency = iconSource and tonumber(iconSource.ImageTransparency) or 0,
	}
end

local function connectProperty(connections, instance, propertyName, handler)
	if not instance then
		return
	end

	connections[#connections + 1] = instance:GetPropertyChangedSignal(propertyName):Connect(handler)
end

local function trim(text)
	return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function simplifyValueText(kind, text)
	local raw = trim(text)
	if raw == "" then
		return "--"
	end

	if kind == "Speed" then
		local simplified = trim(raw:gsub("%s+[Ss]peed%s*$", ""))
		if simplified ~= "" then
			return simplified
		end
	elseif kind == "Money" then
		local simplified = trim(raw:gsub("%s+[%a$]+%s*$", ""))
		if simplified ~= "" then
			return simplified
		end
	end

	return raw
end

local function extractDisplayParts(text, fallbackLabel)
	local raw = trim(text)
	local sourceLabel = trim(fallbackLabel)

	if raw == "" then
		return "--", sourceLabel
	end

	local prefix, trailing = raw:match("^(.-)%s+([^%s]+)$")
	if prefix and trailing then
		local valueText = trim(prefix)
		local labelText = trim(trailing)
		if valueText:find("%d") then
			if labelText == "" then
				labelText = sourceLabel
			end
			return valueText ~= "" and valueText or raw, labelText
		end
	end

	local numberPart, trailingPart = raw:match("^([%+%-]?[%d,%.]+)(.*)$")
	if numberPart then
		local valueText = trim(numberPart)
		local labelText = trim(trailingPart)
		if labelText == "" then
			labelText = sourceLabel
		end
		return valueText ~= "" and valueText or raw, labelText
	end

	return raw, sourceLabel
end

local function renderLayeredText(name, props)
	local theme = HudStatsTheme.Typography
	local font = props.font or HudStatsTheme.Font
	local shadowOffset = props.shadowOffset or theme.ValueShadowOffset
	local mainOffset = props.mainOffset or Vector2.zero

	return e("Frame", {
		Name = name,
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(0, 0, 1, 0),
		ZIndex = props.zIndex,
	}, {
		Shadow = e("TextLabel", {
			Name = "Shadow",
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = font,
			Position = UDim2.fromOffset(shadowOffset.X, shadowOffset.Y),
			Size = UDim2.new(0, 0, 1, 0),
			Text = props.text,
			TextColor3 = props.shadowColor,
			TextScaled = false,
			TextSize = props.textSize,
			TextStrokeColor3 = props.shadowColor,
			TextStrokeTransparency = HudStatsTheme.Typography.ShadowStrokeTransparency,
			TextTransparency = props.textTransparency or 0,
			TextTruncate = Enum.TextTruncate.None,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = props.zIndex,
		}),
		Main = e("TextLabel", {
			Name = "Main",
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Font = font,
			Position = UDim2.fromOffset(mainOffset.X, mainOffset.Y),
			Size = UDim2.new(0, 0, 1, 0),
			Text = props.text,
			TextColor3 = props.textColor3,
			TextScaled = false,
			TextSize = props.textSize,
			TextStrokeColor3 = props.textStrokeColor3,
			TextStrokeTransparency = props.textStrokeTransparency,
			TextTransparency = props.textTransparency or 0,
			TextTruncate = Enum.TextTruncate.None,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = props.zIndex + 1,
		}),
	})
end

local function HudStatCounter(props)
	local host = props.host
	if typeof(host) ~= "Instance" or not host.Parent then
		return nil
	end

	local palette = HudStatsTheme.getPalette(props.kind)
	local iconSource = props.iconSource
	local state, setState = React.useState(function()
		return snapshot(host, iconSource, palette)
	end)

	React.useEffect(function()
		if typeof(host) ~= "Instance" or not host.Parent then
			setState(nil)
			return nil
		end

		local destroyed = false
		local connections = {}
		local stroke = findFirstChildOfClass(host, "UIStroke")
		local iconScale = iconSource and findFirstChildOfClass(iconSource, "UIScale") or nil

		local function refresh()
			if destroyed then
				return
			end

			setState(snapshot(host, iconSource, palette))
		end

		connectProperty(connections, host, "Text", refresh)
		connectProperty(connections, host, "TextStrokeColor3", refresh)
		connectProperty(connections, host, "TextStrokeTransparency", refresh)
		connectProperty(connections, host, "TextTransparency", refresh)
		connectProperty(connections, host, "ZIndex", refresh)
		connectProperty(connections, stroke, "Color", refresh)
		connectProperty(connections, stroke, "Transparency", refresh)
		connectProperty(connections, iconSource, "Image", refresh)
		connectProperty(connections, iconSource, "ImageColor3", refresh)
		connectProperty(connections, iconSource, "ImageRectOffset", refresh)
		connectProperty(connections, iconSource, "ImageRectSize", refresh)
		connectProperty(connections, iconSource, "ImageTransparency", refresh)
		connectProperty(connections, iconSource, "Rotation", refresh)
		connectProperty(connections, iconScale, "Scale", refresh)

		return function()
			destroyed = true
			for _, connection in ipairs(connections) do
				connection:Disconnect()
			end
		end
	end, { host, iconSource })

	if not state then
		return nil
	end

	local fallbackLabel = tostring(props.sourceLabel or props.name or "")
	local valueText, labelText = extractDisplayParts(state.text, fallbackLabel)
	valueText = simplifyValueText(props.kind, valueText)

	local rowHeight = tonumber(props.rowHeight) or HudCounterConfig.RowHeight
	local iconSlotWidth = tonumber(props.iconSlotWidth) or HudCounterConfig.IconSlotWidth
	local iconSlotInnerSize = tonumber(props.iconSlotInnerSize) or HudCounterConfig.IconSize
	local barGap = tonumber(props.barGap) or HudCounterConfig.BarGap
	local hasIconImage = state.iconImage ~= ""
	local effectiveIconScale = math.clamp(state.iconScale, 0.88, 1.12)

	local typography = HudStatsTheme.Typography
	local valueTextSize = typography.ValueSize
	local labelTextSize = typography.LabelSize
	local valueStroke = math.min(typography.ValueStrokeTransparency, math.clamp(state.textStrokeTransparency, 0, 1))
	local labelStroke = math.min(typography.LabelStrokeTransparency, math.clamp(state.textStrokeTransparency, 0, 1))
	local contentWidthOffset = iconSlotWidth + barGap
	local showDivider = props.showDivider == true
	local rowCornerRadius = HudStatsTheme.Row.CornerRadius
	local iconPlateSize = math.max(iconSlotInnerSize + 2, rowHeight - 10)
	local iconGlowSize = math.max(iconSlotInnerSize - 12, 18)
	local rowZIndex = 4

	return e("Frame", {
		Name = "ReactHudStatRow",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		LayoutOrder = tonumber(props.layoutOrder) or 1,
		Size = UDim2.new(1, 0, 0, rowHeight),
	}, {
		RowShadow = e("Frame", {
			Name = "ReactHudStatRowShadow",
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0.5, 2),
			Size = UDim2.new(1, -2, 1, 0),
			ZIndex = rowZIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, rowCornerRadius + 2),
			}),
		}),
		RowSurface = e("Frame", {
			Name = "ReactHudStatRowSurface",
			BackgroundColor3 = HudStatsTheme.Row.BackgroundColor,
			BackgroundTransparency = HudStatsTheme.Row.BackgroundTransparency,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = rowZIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, rowCornerRadius),
			}),
			Stroke = e("UIStroke", {
				Color = palette.rowStroke,
				Thickness = 1,
				Transparency = HudStatsTheme.Row.StrokeTransparency,
			}),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, HudStatsTheme.Row.BackgroundTopColor),
					ColorSequenceKeypoint.new(1, HudStatsTheme.Row.BackgroundBottomColor),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, HudStatsTheme.Row.BackgroundHighlightTransparency),
					NumberSequenceKeypoint.new(1, HudStatsTheme.Row.BackgroundTransparency),
				}),
				Rotation = 90,
			}),
		}),
		RowContent = e("Frame", {
			Name = "ReactHudStatRowContent",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			ZIndex = rowZIndex + 2,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				Padding = UDim.new(0, barGap),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			IconSlot = e("Frame", {
				Name = "ReactHudStatIconSlot",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 1,
				Size = UDim2.new(0, iconSlotWidth, 1, 0),
				ZIndex = rowZIndex + 3,
			}, {
				IconPlateShadow = e("Frame", {
					Name = "ReactHudStatIconPlateShadow",
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = Color3.fromRGB(4, 4, 7),
					BackgroundTransparency = HudStatsTheme.Row.IconPlateShadowTransparency,
					BorderSizePixel = 0,
					Position = UDim2.new(0.5, 0, 0.5, 1),
					Size = UDim2.fromOffset(iconPlateSize + 1, iconPlateSize + 1),
					ZIndex = rowZIndex + 1,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, math.floor(iconPlateSize * 0.38)),
					}),
				}),
				IconPlate = e("Frame", {
					Name = "ReactHudStatIconPlate",
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = HudStatsTheme.Row.IconPlateColor,
					BackgroundTransparency = HudStatsTheme.Row.IconPlateTransparency,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(iconPlateSize, iconPlateSize),
					ZIndex = rowZIndex + 2,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, math.floor(iconPlateSize * 0.36)),
					}),
					Stroke = e("UIStroke", {
						Color = palette.stroke,
						Thickness = 1.2,
						Transparency = HudStatsTheme.Row.IconStrokeTransparency,
					}),
				}),
				IconGlow = e("Frame", {
					Name = "ReactHudStatIconGlow",
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = palette.glow,
					BackgroundTransparency = HudStatsTheme.Row.IconGlowTransparency,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(iconGlowSize, iconGlowSize),
					ZIndex = rowZIndex + 2,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
				}),
				Icon = hasIconImage and e("ImageLabel", {
					Name = "ReactHudStatIcon",
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Image = state.iconImage,
					ImageColor3 = state.iconColor3,
					ImageRectOffset = state.iconImageRectOffset,
					ImageRectSize = state.iconImageRectSize,
					ImageTransparency = state.iconImageTransparency,
					Position = UDim2.fromScale(0.5, 0.5),
					Rotation = state.iconRotation,
					ScaleType = Enum.ScaleType.Fit,
					Size = UDim2.fromOffset(iconSlotInnerSize, iconSlotInnerSize),
					ZIndex = rowZIndex + 4,
				}, {
					Scale = e("UIScale", {
						Scale = effectiveIconScale,
					}),
				}) or nil,
			}),
			Content = e("Frame", {
				Name = "ReactHudStatContent",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 2,
				Size = UDim2.new(1, -contentWidthOffset, 1, 0),
				ZIndex = rowZIndex + 3,
			}, {
				Padding = e("UIPadding", {
					PaddingLeft = UDim.new(0, HudStatsTheme.Row.ContentPaddingLeft),
					PaddingRight = UDim.new(0, HudStatsTheme.Row.ContentPaddingRight),
				}),
				TextCluster = e("Frame", {
					Name = "ReactHudStatTextCluster",
					AnchorPoint = Vector2.new(0, 0.5),
					AutomaticSize = Enum.AutomaticSize.X,
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Position = UDim2.new(0, 0, 0.5, 0),
					Size = UDim2.new(0, 0, 1, 0),
					ZIndex = rowZIndex + 4,
				}, {
					Layout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
						Padding = UDim.new(0, HudStatsTheme.Row.TextGap),
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					}),
					Value = renderLayeredText("ReactHudStatValue", {
						layoutOrder = 1,
						font = HudStatsTheme.Font,
						text = valueText,
						textColor3 = palette.value,
						textStrokeColor3 = palette.stroke,
						textStrokeTransparency = valueStroke,
						textTransparency = math.clamp(state.textTransparency, 0, 1),
						textSize = valueTextSize,
						mainOffset = typography.ValueMainOffset,
						shadowColor = palette.shadow,
						shadowOffset = typography.ValueShadowOffset,
						zIndex = rowZIndex + 5,
					}),
					Label = labelText ~= "" and renderLayeredText("ReactHudStatLabel", {
						layoutOrder = 2,
						font = HudStatsTheme.Font,
						text = labelText,
						textColor3 = palette.label,
						textStrokeColor3 = palette.stroke,
						textStrokeTransparency = labelStroke,
						textTransparency = 0,
						textSize = labelTextSize,
						mainOffset = typography.LabelMainOffset,
						shadowColor = palette.shadow,
						shadowOffset = typography.LabelShadowOffset,
						zIndex = rowZIndex + 5,
					}) or nil,
				}),
			}),
		}),
		Divider = showDivider and e("Frame", {
			Name = "ReactHudStatDivider",
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = HudStatsTheme.Card.DividerColor,
			BackgroundTransparency = HudStatsTheme.Card.DividerTransparency,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 1, 2),
			Size = UDim2.new(1, -12, 0, 1),
			ZIndex = rowZIndex + 1,
		}) or nil,
	})
end

return HudStatCounter
