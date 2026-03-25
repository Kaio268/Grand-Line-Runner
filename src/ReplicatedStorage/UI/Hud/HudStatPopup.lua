local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")

local React = require(Packages:WaitForChild("React"))
local HudStatsTheme = require(script.Parent:WaitForChild("HudStatsTheme"))

local e = React.createElement

local function lerp(a, b, t)
	return a + ((b - a) * t)
end

local function easeOutQuad(t)
	return 1 - ((1 - t) * (1 - t))
end

local function easeOutBack(t)
	local c1 = 1.70158
	local c3 = c1 + 1
	local x = t - 1
	return 1 + (c3 * x * x * x) + (c1 * x * x)
end

local function renderLayeredText(name, props)
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
			Font = HudStatsTheme.Font,
			Position = UDim2.fromOffset(props.shadowOffset.X, props.shadowOffset.Y),
			Size = UDim2.new(0, 0, 1, 0),
			Text = props.text,
			TextColor3 = props.shadowColor,
			TextScaled = false,
			TextSize = props.textSize,
			TextStrokeColor3 = props.shadowColor,
			TextStrokeTransparency = props.shadowStrokeTransparency,
			TextTransparency = props.textTransparency,
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
			Font = HudStatsTheme.Font,
			Size = UDim2.new(0, 0, 1, 0),
			Text = props.text,
			TextColor3 = props.textColor3,
			TextScaled = false,
			TextSize = props.textSize,
			TextStrokeColor3 = props.strokeColor3,
			TextStrokeTransparency = props.strokeTransparency,
			TextTransparency = props.textTransparency,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = props.zIndex + 1,
		}),
	})
end

local function HudStatPopup(props)
	local notification = props.notification
	if not notification then
		return nil
	end

	local progress, setProgress = React.useState(0)

	React.useEffect(function()
		local alive = true
		local connection
		local startedAt = notification.createdAt or os.clock()

		local function update()
			if not alive then
				return
			end

			local elapsed = os.clock() - startedAt
			local nextProgress = math.clamp(elapsed / HudStatsTheme.Popup.Duration, 0, 1)
			setProgress(nextProgress)

			if nextProgress >= 1 then
				alive = false
				if connection then
					connection:Disconnect()
					connection = nil
				end
				if props.onFinished then
					props.onFinished(notification.id)
				end
			end
		end

		update()
		connection = RunService.RenderStepped:Connect(update)

		return function()
			alive = false
			if connection then
				connection:Disconnect()
			end
		end
	end, { notification.id })

	local theme = HudStatsTheme.Popup
	local palette = HudStatsTheme.getPopupPalette(notification.kind, notification.isPositive)
	local enterAlpha = math.clamp(progress / theme.EnterDuration, 0, 1)
	local fadeAlpha = math.clamp((progress - theme.FadeStart) / math.max(0.001, 1 - theme.FadeStart), 0, 1)
	local motionAlpha = easeOutQuad(progress)
	local scale = lerp(theme.EnterScale, 1, easeOutBack(enterAlpha)) * lerp(1, theme.ExitScale, fadeAlpha)
	local yOffset = math.floor(lerp(theme.StartYOffset, theme.EndYOffset, motionAlpha))
	local textTransparency = fadeAlpha
	local icon = notification.icon
	local valueText = string.format("%s%s", notification.isPositive and "+" or "-", tostring(notification.valueText or ""))
	local labelText = tostring(notification.labelText or "")

	return e("Frame", {
		Name = string.format("ReactHudStatPopup_%s", tostring(notification.id)),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		LayoutOrder = tonumber(props.layoutOrder) or 1,
		Size = UDim2.new(1, 0, 0, theme.ItemHeight),
		ZIndex = 20,
	}, {
		Inner = e("Frame", {
			Name = "ReactHudStatPopupInner",
			AnchorPoint = Vector2.new(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = false,
			Position = UDim2.new(0, 0, 1, yOffset),
			Size = UDim2.new(0, 0, 1, 0),
			ZIndex = 21,
		}, {
			Scale = e("UIScale", {
				Scale = scale,
			}),
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				Padding = UDim.new(0, theme.IconGap),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			Icon = icon and icon.image and e("ImageLabel", {
				Name = "ReactHudStatPopupIcon",
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = icon.image,
				ImageColor3 = icon.imageColor3 or Color3.fromRGB(255, 255, 255),
				ImageRectOffset = icon.imageRectOffset or Vector2.zero,
				ImageRectSize = icon.imageRectSize or Vector2.zero,
				ImageTransparency = math.clamp((tonumber(icon.imageTransparency) or 0) + textTransparency, 0, 1),
				LayoutOrder = 1,
				Rotation = tonumber(icon.rotation) or 0,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromOffset(theme.IconSize, theme.IconSize),
				ZIndex = 22,
			}) or nil,
			TextGroup = e("Frame", {
				Name = "ReactHudStatPopupTextGroup",
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				LayoutOrder = 2,
				Size = UDim2.new(0, 0, 1, 0),
				ZIndex = 22,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Left,
					Padding = UDim.new(0, 2),
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),
				Value = renderLayeredText("ReactHudStatPopupValue", {
					layoutOrder = 1,
					text = valueText,
					textColor3 = palette.value,
					strokeColor3 = palette.stroke,
					strokeTransparency = theme.ValueStrokeTransparency,
					shadowColor = palette.shadow,
					shadowOffset = theme.ValueShadowOffset,
					shadowStrokeTransparency = theme.ShadowStrokeTransparency,
					textSize = theme.ValueSize,
					textTransparency = textTransparency,
					zIndex = 22,
				}),
				Label = labelText ~= "" and renderLayeredText("ReactHudStatPopupLabel", {
					layoutOrder = 2,
					text = labelText,
					textColor3 = palette.label,
					strokeColor3 = palette.stroke,
					strokeTransparency = theme.LabelStrokeTransparency,
					shadowColor = palette.shadow,
					shadowOffset = theme.LabelShadowOffset,
					shadowStrokeTransparency = theme.ShadowStrokeTransparency,
					textSize = theme.LabelSize,
					textTransparency = textTransparency,
					zIndex = 22,
				}) or nil,
			}),
		}),
	})
end

return HudStatPopup
