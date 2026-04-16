local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement
local BUTTON_BOTTOM_OFFSET = 156
local BUTTON_HEIGHT = 78
local BUTTON_MAX_SIZE = Vector2.new(372, BUTTON_HEIGHT)
local BUTTON_MIN_SIZE = Vector2.new(268, 68)

local PALETTE = {
	Ink = Color3.fromRGB(9, 9, 11),
	Glass = Color3.fromRGB(29, 28, 33),
	GlassDeep = Color3.fromRGB(15, 15, 18),
	Border = Color3.fromRGB(218, 230, 238),
	Highlight = Color3.fromRGB(245, 249, 252),
	Text = Color3.fromRGB(230, 234, 241),
	MutedText = Color3.fromRGB(176, 177, 187),
	Icon = Color3.fromRGB(166, 180, 190),
	IconDark = Color3.fromRGB(56, 63, 72),
	IconLight = Color3.fromRGB(210, 221, 228),
}

local function useButtonState(enabled)
	local hovered, setHovered = React.useState(false)
	local pressed, setPressed = React.useState(false)

	React.useEffect(function()
		if not enabled then
			setHovered(false)
			setPressed(false)
		end

		return function()
			setHovered(false)
			setPressed(false)
		end
	end, { enabled })

	local handlers = {}
	if enabled then
		handlers[React.Event.MouseEnter] = function()
			setHovered(true)
		end
		handlers[React.Event.MouseLeave] = function()
			setHovered(false)
			setPressed(false)
		end
		handlers[React.Event.MouseButton1Down] = function()
			setPressed(true)
		end
		handlers[React.Event.MouseButton1Up] = function()
			setPressed(false)
		end
	end

	return hovered, pressed, handlers
end

local function mergeProps(baseProps, extraProps)
	local merged = {}
	for key, value in pairs(baseProps) do
		merged[key] = value
	end
	for key, value in pairs(extraProps or {}) do
		merged[key] = value
	end
	return merged
end

local function trashIcon(props)
	local zIndex = props.zIndex or 1
	local strokeThickness = props.strokeThickness or 3
	local iconTransparency = props.transparency or 0.12
	local strokeTransparency = props.strokeTransparency or 0.34

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		Size = props.size or UDim2.fromOffset(70, 58),
		ZIndex = zIndex,
	}, {
		Handle = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = PALETTE.Icon,
			BackgroundTransparency = iconTransparency,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(28, 10),
			ZIndex = zIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.IconDark,
				Thickness = strokeThickness,
				Transparency = strokeTransparency,
			}),
		}),
		Lid = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = PALETTE.Icon,
			BackgroundTransparency = iconTransparency,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 17),
			Size = UDim2.fromOffset(50, 8),
			ZIndex = zIndex + 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.IconDark,
				Thickness = strokeThickness,
				Transparency = strokeTransparency,
			}),
		}),
		Body = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = PALETTE.Icon,
			BackgroundTransparency = iconTransparency,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 24),
			Size = UDim2.fromOffset(40, 31),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.IconDark,
				Thickness = strokeThickness,
				Transparency = strokeTransparency,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, PALETTE.IconLight),
					ColorSequenceKeypoint.new(1, PALETTE.Icon),
				}),
			}),
			Slot1 = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = PALETTE.IconDark,
				BackgroundTransparency = math.min(iconTransparency + 0.08, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.34, 0.52),
				Size = UDim2.fromOffset(3, 19),
				ZIndex = zIndex + 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
			}),
			Slot2 = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = PALETTE.IconDark,
				BackgroundTransparency = math.min(iconTransparency + 0.08, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.5, 0.52),
				Size = UDim2.fromOffset(3, 21),
				ZIndex = zIndex + 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
			}),
			Slot3 = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = PALETTE.IconDark,
				BackgroundTransparency = math.min(iconTransparency + 0.08, 1),
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0.66, 0.52),
				Size = UDim2.fromOffset(3, 19),
				ZIndex = zIndex + 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 2),
				}),
			}),
		}),
	})
end

local function DropAction(props)
	local visible = props.visible == true
	local canDrop = visible and props.isPending ~= true and props.disabled ~= true
	local hovered, pressed, handlers = useButtonState(canDrop)
	local buttonRef = React.useRef(nil)
	local scale = 1
	if hovered then
		scale += 0.025
	end
	if pressed or props.isPending == true then
		scale -= 0.055
	end
	local reward = props.reward
	local metaText = "ITEM"
	if typeof(reward) == "table" and typeof(reward.RewardType) == "string" and reward.RewardType ~= "" then
		metaText = string.upper(reward.RewardType)
	end
	local panelTransparency = if pressed or props.isPending == true then 0.32 elseif hovered then 0.4 else 0.5
	local strokeTransparency = if hovered then 0.58 else 0.74

	React.useEffect(function()
		local button = buttonRef.current
		if not visible or not button then
			return nil
		end

		CollectionService:AddTag(button, "NoAnim")

		return function()
			if button.Parent then
				CollectionService:RemoveTag(button, "NoAnim")
			end
		end
	end, { visible })

	if not visible then
		return nil
	end

	local buttonProps = mergeProps({
		AnchorPoint = Vector2.new(0.5, 1),
		AutoButtonColor = false,
		BackgroundColor3 = PALETTE.Glass,
		BackgroundTransparency = panelTransparency,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.new(0.5, 0, 1, -BUTTON_BOTTOM_OFFSET),
		Name = "CorridorDropButton",
		ref = buttonRef,
		Size = UDim2.new(0.45, 0, 0, BUTTON_HEIGHT),
		Text = "",
		ZIndex = 50,
		[React.Event.Activated] = function()
			if canDrop and props.onDrop then
				props.onDrop()
			end
		end,
	}, handlers)

	return e("ScreenGui", {
		DisplayOrder = 155,
		IgnoreGuiInset = true,
		Name = "ReactCorridorDropAction",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Button = e("TextButton", buttonProps, {
			Scale = e("UIScale", {
				Scale = scale,
			}),
			SizeLimit = e("UISizeConstraint", {
				MaxSize = BUTTON_MAX_SIZE,
				MinSize = BUTTON_MIN_SIZE,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, PALETTE.Glass),
					ColorSequenceKeypoint.new(1, PALETTE.GlassDeep),
				}),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.Border,
				Thickness = hovered and 2 or 1.5,
				Transparency = strokeTransparency,
			}),
			TopStripe = e("Frame", {
				BackgroundColor3 = PALETTE.Highlight,
				BackgroundTransparency = hovered and 0.78 or 0.88,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(9, 7),
				Size = UDim2.new(1, -18, 0, 4),
				ZIndex = 51,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 3),
				}),
			}),
			BottomEdge = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = PALETTE.Ink,
				BackgroundTransparency = pressed and 0.52 or 0.7,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 0, 1, 0),
				Size = UDim2.new(1, 0, 0, 7),
				ZIndex = 51,
			}),
			RightRail = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = PALETTE.Border,
				BackgroundTransparency = hovered and 0.72 or 0.86,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -10, 0, 18),
				Size = UDim2.new(0, 4, 1, -36),
				ZIndex = 52,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 3),
				}),
			}),
			IconWell = e("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = PALETTE.Ink,
				BackgroundTransparency = 0.36,
				BorderSizePixel = 0,
				Position = UDim2.new(0, 18, 0.5, 0),
				Size = UDim2.fromOffset(76, 60),
				ZIndex = 52,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, PALETTE.Glass),
						ColorSequenceKeypoint.new(1, PALETTE.Ink),
					}),
				}),
				Stroke = e("UIStroke", {
					Color = PALETTE.Border,
					Thickness = 1.5,
					Transparency = if hovered then 0.62 else 0.78,
				}),
				Icon = e(trashIcon, {
					position = UDim2.fromScale(0.5, 0.5),
					size = UDim2.fromOffset(70, 58),
					transparency = 0.18,
					strokeTransparency = 0.46,
					zIndex = 54,
				}),
			}),
			Meta = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(0, 112, 0, 15),
				Size = UDim2.new(1, -148, 0, 16),
				Text = metaText,
				TextColor3 = PALETTE.MutedText,
				TextSize = 12,
				TextStrokeTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 52,
			}),
			Label = e("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.new(0, 110, 0.5, 12),
				Size = UDim2.new(1, -148, 0, 40),
				Text = "DROP",
				TextColor3 = PALETTE.Text,
				TextStrokeColor3 = PALETTE.GlassDeep,
				TextStrokeTransparency = 0.48,
				TextSize = 36,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 52,
			}),
		}),
	})
end

return DropAction
