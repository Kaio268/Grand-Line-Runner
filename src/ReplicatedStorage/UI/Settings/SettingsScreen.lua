local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	MenuBackgroundImage = "rbxassetid://75192947200012",
	MenuOverlay = Color3.fromRGB(15, 27, 42), -- #0f1b2a
	HeaderBackground = Color3.fromRGB(16, 35, 59), -- #10233b
	SectionBackground = Color3.fromRGB(27, 46, 68), -- #1b2e44
	SectionHover = Color3.fromRGB(46, 74, 99), -- #2e4a63
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextBright = Color3.fromRGB(247, 249, 255),
	TextShadow = Color3.fromRGB(9, 17, 27),
	CloseFill = Color3.fromRGB(200, 0, 9), -- #c80009
	CloseFillSoft = Color3.fromRGB(235, 70, 78),
	SwitchFill = Color3.fromRGB(16, 35, 59),
}

local ROW_HEIGHT = 72
local ROW_PADDING = 10

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
	local externalValue = clamp(round(props.value), 0, 100)
	local displayValue, setDisplayValue = React.useState(externalValue)
	local displayValueRef = React.useRef(externalValue)
	local draggingRef = React.useRef(false)
	local inputChangedConnectionRef = React.useRef(nil)
	local inputEndedConnectionRef = React.useRef(nil)
	local renderSteppedConnectionRef = React.useRef(nil)
	local knobHovered, setKnobHovered = React.useState(false)
	local progress = displayValue / 100
	local knobDiameter = knobHovered and 40 or 36
	local knobOffset = math.floor((0.5 - progress) * knobDiameter)

	local function setDisplayAndPreview(nextValue)
		local clamped = clamp(round(nextValue), 0, 100)
		if clamped == displayValueRef.current then
			return
		end

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
			return displayValueRef.current
		end

		local normalized = clamp((screenX - track.AbsolutePosition.X) / width, 0, 1)
		return normalized * 100
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

		local synced = clamp(round(externalValue), 0, 100)
		displayValueRef.current = synced
		setDisplayValue(synced)
		return nil
	end, { externalValue })

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
		startDrag(xPosition)
	end

	return e(RowShell, {
		layoutOrder = props.layoutOrder,
		children = {
			Icon = e(IconBubble, {
				icon = props.icon,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(74, 19),
				Size = UDim2.fromOffset(188, 28),
				Text = props.label,
				TextColor3 = THEME.TextMain,
				TextSize = 20,
				TextScaled = false,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 6,
			}),
			Track = e("Frame", {
				ref = trackRef,
				Active = true,
				BackgroundColor3 = THEME.HeaderBackground,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 266, 0.5, 6),
				Size = UDim2.new(1, -348, 0, 10),
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
					BackgroundColor3 = THEME.GoldBase,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(progress, 1),
					ZIndex = 6,
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
						Font = Enum.Font.GothamBold,
						Size = UDim2.fromScale(1, 1),
						Text = tostring(displayValue),
						TextColor3 = THEME.TextBright,
						TextScaled = false,
						TextSize = 18,
						TextStrokeColor3 = THEME.TextShadow,
						TextStrokeTransparency = 0.35,
						ZIndex = 8,
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
		rows["Slider_" .. tostring(item.id)] = e(SliderRow, {
			icon = item.icon,
			label = item.label,
			layoutOrder = index,
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
			value = item.value,
		})
	end

	return e("Frame", {
		BackgroundColor3 = THEME.MenuOverlay,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		BaseTexture = e("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = THEME.MenuBackgroundImage,
			ImageTransparency = 0,
			ScaleType = Enum.ScaleType.Stretch,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
		}),
		Overlay = e("Frame", {
			BackgroundColor3 = THEME.MenuOverlay,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
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
		Header = e("Frame", {
			BackgroundColor3 = THEME.HeaderBackground,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 54),
			ZIndex = 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Thickness = 1.5,
				Transparency = 0,
			}),
			Title = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(260, 32),
				Text = "SETTINGS",
				TextColor3 = THEME.TextMain,
				TextSize = 30,
				TextScaled = true,
				TextStrokeColor3 = THEME.GoldShadow,
				TextStrokeTransparency = 0.45,
				ZIndex = 4,
			}),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = THEME.CloseFill,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(34, 34),
				Text = "X",
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextStrokeColor3 = THEME.TextShadow,
				TextStrokeTransparency = 0.4,
				ZIndex = 4,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Stroke = e("UIStroke", {
					Color = THEME.GoldShadow,
					Thickness = 1,
					Transparency = 0.1,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, THEME.CloseFillSoft),
						ColorSequenceKeypoint.new(1, THEME.CloseFill),
					}),
				}),
			}),
		}),
		Body = e("ScrollingFrame", {
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			Position = UDim2.fromOffset(18, 116),
			ScrollBarImageColor3 = THEME.GoldHighlight,
			ScrollBarThickness = 8,
			Size = UDim2.new(1, -42, 1, -126),
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
