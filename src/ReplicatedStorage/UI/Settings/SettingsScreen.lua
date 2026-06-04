local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	GlowImage = "rbxassetid://114516018211032",
	CardBg = Color3.fromRGB(8, 8, 9),
	MenuOverlay = Color3.fromRGB(8, 8, 9),
	HeaderBackground = Color3.fromRGB(14, 14, 16),
	SectionBackground = Color3.fromRGB(14, 14, 16),
	SectionHover = Color3.fromRGB(24, 24, 28),
	GoldBase = Color3.fromRGB(228, 190, 78),
	GoldHighlight = Color3.fromRGB(255, 224, 120),
	GoldShadow = Color3.fromRGB(150, 112, 42),
	Cream = Color3.fromRGB(255, 222, 130),
	TextMain = Color3.fromRGB(235, 235, 235),
	TextBright = Color3.fromRGB(247, 249, 255),
	TextShadow = Color3.fromRGB(0, 0, 0),
	CloseFill = Color3.fromRGB(200, 0, 9),
	CloseFillSoft = Color3.fromRGB(235, 70, 78),
	SwitchFill = Color3.fromRGB(20, 20, 24),
}

local BADGE_FONT = Font.new("rbxasset://fonts/families/SpecialElite.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local BODY = Enum.Font.FredokaOne

local ROW_HEIGHT = 72
local ROW_PADDING = 10
local DEBUG_SETTINGS_SLIDER = false

local function debugSlider(id, message, ...)
	if not DEBUG_SETTINGS_SLIDER or id ~= "SoundEffects" then
		return
	end

	print(string.format("[SETTINGS][SLIDER] " .. message, ...))
end

local function clamp(value, minValue, maxValue)
	local numeric = tonumber(value) or minValue
	if numeric < minValue then
		return minValue
	end
	if numeric > maxValue then
		return maxValue
	end
	return numeric
end

local function round(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function RowShell(props)
	local hovered, setHovered = React.useState(false)
	local enableHover = props.enableHover ~= false
	local children = {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0,
			Thickness = 1.5,
		}),
	}

	for name, child in pairs(props.children or {}) do
		children[name] = child
	end

	return e("Frame", {
		Active = true,
		BackgroundColor3 = (enableHover and hovered) and THEME.SectionHover or THEME.SectionBackground,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		ZIndex = 4,
		[React.Event.MouseEnter] = function()
			if enableHover then
				setHovered(true)
			end
		end,
		[React.Event.MouseLeave] = function()
			if enableHover then
				setHovered(false)
			end
		end,
	}, children)
end

local function IconBubble(props)
	return e("Frame", {
		BackgroundColor3 = THEME.HeaderBackground,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 13),
		Size = UDim2.fromOffset(46, 46),
		ZIndex = 5,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 11),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0,
			Thickness = 1,
		}),
		Icon = props.icon and props.icon ~= "" and e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = props.icon,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.fromOffset(38, 38),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 6,
		}) or nil,
	})
end

local function SliderRow(props)
	local trackRef = React.useRef(nil)
	local minValue = round(if props.min ~= nil then props.min else 0)
	local maxValue = round(if props.max ~= nil then props.max else 100)
	if maxValue < minValue then
		maxValue = minValue
	end
	local step = math.max(1, round(props.step or 1))
	local function clampSliderValue(value)
		local clamped = clamp(round(value), minValue, maxValue)
		if step > 1 then
			local stepped = minValue + (math.floor(((clamped - minValue) / step) + 0.5) * step)
			return clamp(round(stepped), minValue, maxValue)
		end
		return clamped
	end
	local externalValue = clampSliderValue(props.value)
	local displayValue, setDisplayValue = React.useState(externalValue)
	local displayValueRef = React.useRef(externalValue)
	local draggingRef = React.useRef(false)
	local inputChangedConnectionRef = React.useRef(nil)
	local inputEndedConnectionRef = React.useRef(nil)
	local renderSteppedConnectionRef = React.useRef(nil)
	local knobHovered, setKnobHovered = React.useState(false)
	local sliderRange = math.max(0, maxValue - minValue)
	local progress = if sliderRange > 0 then clamp((displayValue - minValue) / sliderRange, 0, 1) else 1
	local knobDiameter = 36 -- constant so the knob never shifts/jumps on hover
	local knobOffset = math.floor((0.5 - progress) * knobDiameter)
	local knobScaleRef = React.useRef(nil)
	React.useEffect(function()
		local scale = knobScaleRef.current
		if not scale then
			return
		end
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad), {
			Scale = knobHovered and 1.12 or 1,
		}):Play()
	end, { knobHovered })

	local function setDisplayAndPreview(nextValue)
		local clamped = clampSliderValue(nextValue)
		if clamped == displayValueRef.current then
			return
		end

		debugSlider(props.id, "preview id=%s value=%d previous=%s", tostring(props.id), clamped, tostring(displayValueRef.current))
		displayValueRef.current = clamped
		setDisplayValue(clamped)
		if props.onPreview then
			props.onPreview(clamped)
		end
	end

	local function valueFromScreenX(screenX)
		local track = trackRef.current
		if not track then
			return displayValueRef.current
		end

		local width = track.AbsoluteSize.X
		if width <= 0 then
			debugSlider(props.id, "valueFromScreenX ignored id=%s width=%d", tostring(props.id), width)
			return displayValueRef.current
		end

		local normalized = clamp((screenX - track.AbsolutePosition.X) / width, 0, 1)
		local value = minValue + (normalized * math.max(0, maxValue - minValue))
		debugSlider(
			props.id,
			"valueFromScreenX id=%s screenX=%.1f trackX=%.1f width=%.1f normalized=%.3f value=%.1f",
			tostring(props.id),
			screenX,
			track.AbsolutePosition.X,
			width,
			normalized,
			value
		)
		return value
	end

	local function updateFromScreenX(screenX)
		setDisplayAndPreview(valueFromScreenX(screenX))
	end

	local function disconnectDragConnections()
		local changedConnection = inputChangedConnectionRef.current
		if changedConnection then
			changedConnection:Disconnect()
			inputChangedConnectionRef.current = nil
		end

		local endedConnection = inputEndedConnectionRef.current
		if endedConnection then
			endedConnection:Disconnect()
			inputEndedConnectionRef.current = nil
		end

		local renderConnection = renderSteppedConnectionRef.current
		if renderConnection then
			renderConnection:Disconnect()
			renderSteppedConnectionRef.current = nil
		end
	end

	local function commitCurrentValue()
		debugSlider(props.id, "commit id=%s value=%s", tostring(props.id), tostring(displayValueRef.current))
		if props.onCommit then
			props.onCommit(displayValueRef.current)
		end
	end

	local function endDrag(shouldCommit)
		if not draggingRef.current then
			return
		end

		draggingRef.current = false
		disconnectDragConnections()
		if shouldCommit then
			commitCurrentValue()
		end
	end

	local function startDrag(screenX)
		if type(screenX) ~= "number" then
			screenX = UserInputService:GetMouseLocation().X
		end
		debugSlider(props.id, "startDrag id=%s screenX=%s", tostring(props.id), tostring(screenX))
		draggingRef.current = true
		updateFromScreenX(screenX)

		disconnectDragConnections()

		inputChangedConnectionRef.current = UserInputService.InputChanged:Connect(function(input)
			if not draggingRef.current then
				return
			end

			if
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			then
				updateFromScreenX(input.Position.X)
			end
		end)

		inputEndedConnectionRef.current = UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				endDrag(true)
			end
		end)

		renderSteppedConnectionRef.current = RunService.RenderStepped:Connect(function()
			if not draggingRef.current then
				return
			end
			local mouseLocation = UserInputService:GetMouseLocation()
			updateFromScreenX(mouseLocation.X)
		end)
	end

	React.useEffect(function()
		if draggingRef.current then
			return nil
		end

		local synced = clampSliderValue(externalValue)
		displayValueRef.current = synced
		setDisplayValue(synced)
		return nil
	end, { externalValue, minValue, maxValue })

	React.useEffect(function()
		return function()
			draggingRef.current = false
			disconnectDragConnections()
		end
	end, {})

	local function beginDragFromInput(_, input)
		local userInputType = input and input.UserInputType
		if
			userInputType ~= Enum.UserInputType.MouseButton1
			and userInputType ~= Enum.UserInputType.Touch
		then
			return
		end

		local xPosition = if input.Position then input.Position.X else UserInputService:GetMouseLocation().X
		debugSlider(
			props.id,
			"inputBegan id=%s input=%s x=%s y=%s",
			tostring(props.id),
			tostring(userInputType),
			tostring(xPosition),
			tostring(input.Position and input.Position.Y or nil)
		)
		startDrag(xPosition)
	end

	return e(RowShell, {
		enableHover = false,
		layoutOrder = props.layoutOrder,
		children = {
			Icon = e(IconBubble, {
				icon = props.icon,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Position = UDim2.fromOffset(74, 19),
				Size = UDim2.fromOffset(188, 28),
				Text = props.label,
				TextColor3 = THEME.TextMain,
				TextSize = 20,
				TextScaled = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
			}),
			RangeLabel = props.rangeText and props.rangeText ~= "" and e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Position = UDim2.fromOffset(74, 44),
				Size = UDim2.fromOffset(178, 18),
				Text = tostring(props.rangeText),
				TextColor3 = THEME.GoldHighlight,
				TextSize = 14,
				TextScaled = false,
				TextStrokeColor3 = THEME.TextShadow,
				TextStrokeTransparency = 0.45,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
			}) or nil,
			Track = e("TextButton", {
				ref = trackRef,
				Active = true,
				AutoButtonColor = false,
				BackgroundColor3 = THEME.HeaderBackground,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 266, 0.5, 6),
				Size = UDim2.new(1, -348, 0, 64),
				Text = "",
				ZIndex = 5,
				[React.Event.InputBegan] = beginDragFromInput,
				[React.Event.InputChanged] = function(_, input)
					if not draggingRef.current then
						return
					end
					if
						input.UserInputType == Enum.UserInputType.MouseMovement
						or input.UserInputType == Enum.UserInputType.Touch
					then
						updateFromScreenX(input.Position.X)
					end
				end,
			}, {
				TrackBar = e("Frame", {
					AnchorPoint = Vector2.new(0, 0.5),
					Active = true,
					BackgroundColor3 = THEME.HeaderBackground,
					BackgroundTransparency = 0.25,
					BorderSizePixel = 0,
					Position = UDim2.fromScale(0, 0.5),
					Size = UDim2.new(1, 0, 0, 10),
					ZIndex = 5,
					[React.Event.InputBegan] = beginDragFromInput,
					[React.Event.InputChanged] = function(_, input)
						if not draggingRef.current then
							return
						end
						if
							input.UserInputType == Enum.UserInputType.MouseMovement
							or input.UserInputType == Enum.UserInputType.Touch
						then
							updateFromScreenX(input.Position.X)
						end
					end,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Stroke = e("UIStroke", {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = THEME.GoldHighlight,
						Transparency = 0,
						Thickness = 1.5,
					}),
					Fill = e("Frame", {
						Active = true,
						BackgroundColor3 = THEME.GoldBase,
						BorderSizePixel = 0,
						Size = UDim2.fromScale(progress, 1),
						ZIndex = 6,
						[React.Event.InputBegan] = beginDragFromInput,
						[React.Event.InputChanged] = function(_, input)
							if not draggingRef.current then
								return
							end
							if
								input.UserInputType == Enum.UserInputType.MouseMovement
								or input.UserInputType == Enum.UserInputType.Touch
							then
								updateFromScreenX(input.Position.X)
							end
						end,
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
						Gradient = e("UIGradient", {
							Rotation = 90,
							Color = ColorSequence.new({
								ColorSequenceKeypoint.new(0, THEME.GoldHighlight),
								ColorSequenceKeypoint.new(1, THEME.GoldBase),
							}),
						}),
					}),
				}),
				Knob = e("TextButton", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Active = true,
					AutoButtonColor = false,
					BackgroundColor3 = THEME.GoldBase,
					BorderSizePixel = 0,
					Position = UDim2.new(progress, knobOffset, 0.5, 0),
					Size = UDim2.fromOffset(knobDiameter, knobDiameter),
					Text = "",
					ZIndex = 7,
					[React.Event.InputBegan] = beginDragFromInput,
					[React.Event.InputChanged] = function(_, input)
						if not draggingRef.current then
							return
						end
						if
							input.UserInputType == Enum.UserInputType.MouseMovement
							or input.UserInputType == Enum.UserInputType.Touch
						then
							updateFromScreenX(input.Position.X)
						end
					end,
					[React.Event.MouseButton1Down] = function(_, x)
						startDrag(x)
					end,
					[React.Event.MouseButton1Up] = function()
						endDrag(true)
					end,
					[React.Event.MouseEnter] = function()
						setKnobHovered(true)
					end,
					[React.Event.MouseLeave] = function()
						setKnobHovered(false)
					end,
				}, {
					Scale = e("UIScale", { ref = knobScaleRef }),
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Stroke = e("UIStroke", {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = THEME.GoldHighlight,
						Transparency = 0,
						Thickness = 1.5,
					}),
					Value = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = BODY,
						Size = UDim2.fromScale(1, 1),
						Text = tostring(displayValue),
						TextColor3 = THEME.TextBright,
						TextScaled = true,
						TextSize = 18,
						TextStrokeColor3 = THEME.TextShadow,
						TextStrokeTransparency = 0.35,
						ZIndex = 8,
					}, {
						TextSize = e("UITextSizeConstraint", {
							MaxTextSize = 18,
							MinTextSize = 9,
						}),
					}),
				}),
			}),
		},
	})
end

local function SwitchRow(props)
	local enabled = props.value == true
	local hasStatus = typeof(props.statusText) == "string" and props.statusText ~= ""
	local knobX = if enabled then 42 else 4
	local fillColor = if enabled then THEME.GoldBase else THEME.SwitchFill
	local labelText = if enabled then "ON" else "OFF"

	return e(RowShell, {
		layoutOrder = props.layoutOrder,
		children = {
			Icon = e(IconBubble, {
				icon = props.icon,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Position = UDim2.fromOffset(74, if hasStatus then 13 else 22),
				Size = UDim2.new(1, -240, 0, 28),
				Text = props.label,
				TextColor3 = THEME.TextMain,
				TextSize = 20,
				TextScaled = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
			}),
			Status = hasStatus and e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Position = UDim2.fromOffset(74, 42),
				Size = UDim2.new(1, -240, 0, 18),
				Text = props.statusText,
				TextColor3 = THEME.GoldHighlight,
				TextSize = 14,
				TextScaled = false,
				TextStrokeColor3 = THEME.TextShadow,
				TextStrokeTransparency = 0.45,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				ZIndex = 6,
			}) or nil,
			Switch = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = fillColor,
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -20, 0.5, 0),
				Size = UDim2.fromOffset(88, 40),
				Text = "",
				ZIndex = 6,
				[React.Event.Activated] = function()
					if props.onToggle then
						props.onToggle(not enabled)
					end
				end,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Stroke = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = THEME.GoldHighlight,
					Transparency = if enabled then 0 else 0.35,
					Thickness = 1.5,
				}),
				State = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = BODY,
					Position = UDim2.fromOffset(if enabled then 8 else 34, 0),
					Size = UDim2.fromOffset(42, 40),
					Text = labelText,
					TextColor3 = THEME.TextBright,
					TextSize = 14,
					TextStrokeColor3 = THEME.TextShadow,
					TextStrokeTransparency = 0.45,
					ZIndex = 7,
				}),
				Knob = e("Frame", {
					BackgroundColor3 = THEME.TextBright,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(knobX, 4),
					Size = UDim2.fromOffset(32, 32),
					ZIndex = 8,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Stroke = e("UIStroke", {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = THEME.GoldShadow,
						Transparency = 0.15,
						Thickness = 1,
					}),
				}),
			}),
		},
	})
end

local function SettingsScreen(props)
	local items = props.items or {}

	local rows = {
		List = e("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, ROW_PADDING),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, item in ipairs(items) do
		if item.type == "Slider" then
			rows["Slider_" .. tostring(item.id)] = e(SliderRow, {
				id = item.id,
				icon = item.icon,
				label = item.label,
				layoutOrder = index,
				max = item.max,
				min = item.min,
				onCommit = function(value)
					if props.onSliderCommit then
						props.onSliderCommit(item.id, value)
					end
				end,
				onPreview = function(value)
					if props.onSliderPreview then
						props.onSliderPreview(item.id, value)
					end
				end,
				rangeText = item.rangeText,
				step = item.step,
				value = item.value,
			})
		else
			rows["Switch_" .. tostring(item.id)] = e(SwitchRow, {
				id = item.id,
				icon = item.icon,
				label = item.label,
				layoutOrder = index,
				onToggle = function(value)
					if props.onSwitchToggle then
						props.onSwitchToggle(item.id, value)
					end
				end,
				statusText = item.statusText,
				value = item.value,
			})
		end
	end

	return e("Frame", {
		BackgroundColor3 = THEME.CardBg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		Anchor = e("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.949, 0, 0.895, 0),
			Size = UDim2.new(0.075, 0, 0.275, 0),
			Image = "rbxassetid://87910431269362",
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 4,
		}),
		Fill = e("Frame", {
			BackgroundColor3 = THEME.CardBg,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = -2,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 18) }),
		}),
		OuterBorder = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Thickness = 3,
				Transparency = 0,
			}),
		}),
		InnerBorder = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 1, -16),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 12) }),
			Stroke = e("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = THEME.GoldHighlight, Thickness = 1.2, Transparency = 0.3 }),
		}),
		TitleBadge = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = THEME.CardBg,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(208, 42),
			ZIndex = 25,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldBase,
				Thickness = 2,
				Transparency = 0.15,
			}, {
				Grad = e("UIGradient", {
					Rotation = 0,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 216, 107)),
						ColorSequenceKeypoint.new(0.47, Color3.fromRGB(138, 90, 19)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 216, 107)),
					}),
				}),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				FontFace = BADGE_FONT,
				Size = UDim2.fromScale(1, 1),
				Text = "SETTINGS",
				TextColor3 = THEME.GoldBase,
				TextScaled = true,
				ZIndex = 26,
			}, {
				Constraint = e("UITextSizeConstraint", { MaxTextSize = 22 }),
				Grad = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 251, 230)),
						ColorSequenceKeypoint.new(0.47, Color3.fromRGB(255, 216, 107)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 56, 2)),
					}),
				}),
				Outline = e("UIStroke", {
					Color = Color3.fromRGB(36, 18, 0),
					Thickness = 3,
					Transparency = 0.2,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
					LineJoinMode = Enum.LineJoinMode.Miter,
				}),
			}),
		}),
		Close = e("TextButton", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = THEME.CloseFill,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(34, 34),
			Text = "X",
			TextColor3 = Color3.new(1, 1, 1),
			Font = BODY,
			TextScaled = true,
			TextStrokeColor3 = THEME.TextShadow,
			TextStrokeTransparency = 0.25,
			ZIndex = 30,
			[React.Event.Activated] = props.onClose,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 9) }),
			Outline = e("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Color = Color3.fromRGB(0, 0, 0), Thickness = 1.6, Transparency = 0 }),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 96, 102)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(214, 24, 34)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 0, 6)),
				}),
			}),
		}),
		Body = e("ScrollingFrame", {
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			Position = UDim2.fromOffset(18, 62),
			ScrollBarImageColor3 = THEME.GoldHighlight,
			ScrollBarThickness = 8,
			Size = UDim2.new(1, -42, 1, -76),
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ZIndex = 3,
		}, {
			Content = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, -4, 0, 0),
				Size = UDim2.new(1, -22, 0, 0),
				ZIndex = 4,
			}, {
				Padding = e("UIPadding", {
					PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
					PaddingTop = UDim.new(0, 2),
				}),
				Rows = e("Frame", {
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundTransparency = 1,
					Size = UDim2.fromScale(1, 0),
					ZIndex = 4,
				}, rows),
			}),
		}),
	})
end

return SettingsScreen
