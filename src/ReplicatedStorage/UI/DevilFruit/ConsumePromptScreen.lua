local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	FruitBackgroundImage = "rbxassetid://134053886107384",
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	HeaderBackground = Color3.fromRGB(16, 35, 59),
	SectionBackground = Color3.fromRGB(27, 46, 68),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	CloseFill = Color3.fromRGB(147, 0, 0),
	CloseHover = Color3.fromRGB(216, 34, 44),
}

local function gradient(first, second)
	return e("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, first),
			ColorSequenceKeypoint.new(1, second),
		}),
		Rotation = 90,
	})
end

local function actionButton(props)
	local hovered, setHovered = React.useState(false)
	local fill = if hovered then props.hoverFill else props.fill
	local textColor = if hovered then props.hoverText else props.textColor

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fill,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(0.5, -14, 0, 46),
		Text = "",
		[React.Event.Activated] = props.onActivated,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0.08,
			Thickness = 1.2,
		}),
		Gradient = gradient(hovered and props.hoverTop or props.top, hovered and props.hoverBottom or props.bottom),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Size = UDim2.fromScale(1, 1),
			Text = props.text,
			TextColor3 = textColor,
			TextSize = 22,
		}),
	})
end

local function ConsumePromptScreen(props)
	if props.visible ~= true then
		return e(React.Fragment)
	end

	return e("ScreenGui", {
		DisplayOrder = 120,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Dimmer = e("Frame", {
			BackgroundColor3 = THEME.MenuOverlay,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 60,
		}),
		Panel = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = THEME.PrimaryBg,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(620, 360),
			ZIndex = 80,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Thickness = 2.2,
			}),
			BackgroundImage = e("ImageLabel", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Image = THEME.FruitBackgroundImage,
				ScaleType = Enum.ScaleType.Stretch,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 79,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 16),
				}),
			}),
			Overlay = e("Frame", {
				BackgroundColor3 = THEME.MenuOverlay,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 79,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 16),
				}),
			}),
			TopBar = e("Frame", {
				BackgroundColor3 = THEME.HeaderBackground,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(14, 12),
				Size = UDim2.new(1, -28, 0, 88),
				ZIndex = 81,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = THEME.GoldHighlight,
					Thickness = 1.4,
				}),
				Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
				Accent = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Position = UDim2.fromOffset(16, 8),
					Size = UDim2.new(1, -32, 0, 20),
					Text = "DEVIL FRUIT",
					TextColor3 = THEME.GoldHighlight,
					TextSize = 16,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 82,
				}),
				Title = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Position = UDim2.fromOffset(16, 30),
					Size = UDim2.new(1, -32, 0, 48),
					Text = props.title,
					TextColor3 = THEME.TextMain,
					TextSize = 22,
					TextStrokeColor3 = THEME.GoldHighlight,
					TextStrokeTransparency = 0.58,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 82,
				}),
			}),
			Content = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(20, 114),
				Size = UDim2.new(1, -40, 1, -136),
				ZIndex = 81,
			}, {
				BodyCard = e("Frame", {
					BackgroundColor3 = THEME.SectionBackground,
					BackgroundTransparency = 0.22,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 1, -64),
					ZIndex = 81,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 12),
					}),
					Stroke = e("UIStroke", {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = THEME.GoldHighlight,
						Thickness = 1.2,
					}),
					Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
					Padding = e("UIPadding", {
						PaddingBottom = UDim.new(0, 14),
						PaddingLeft = UDim.new(0, 16),
						PaddingRight = UDim.new(0, 16),
						PaddingTop = UDim.new(0, 14),
					}),
					Body = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamBold,
						Size = UDim2.fromScale(1, 1),
						Text = props.body,
						TextColor3 = THEME.TextSecondary,
						TextSize = 24,
						TextWrapped = true,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Top,
						ZIndex = 82,
					}),
				}),
				ButtonRow = e("Frame", {
					AnchorPoint = Vector2.new(0.5, 1),
					BackgroundTransparency = 1,
					Position = UDim2.fromScale(0.5, 1),
					Size = UDim2.new(1, 0, 0, 48),
					ZIndex = 82,
				}, {
					Layout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, 28),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
					Confirm = e(actionButton, {
						bottom = THEME.GoldBase,
						fill = THEME.GoldBase,
						hoverBottom = THEME.GoldBase,
						hoverFill = THEME.GoldHighlight,
						hoverText = THEME.PrimaryBg,
						hoverTop = THEME.GoldHighlight,
						layoutOrder = 1,
						onActivated = props.onConfirm,
						text = props.confirmText,
						textColor = THEME.PrimaryBg,
						top = THEME.GoldHighlight,
					}),
					Cancel = e(actionButton, {
						bottom = THEME.PrimaryBg,
						fill = THEME.SectionBackground,
						hoverBottom = THEME.CloseFill,
						hoverFill = THEME.CloseHover,
						hoverText = Color3.fromRGB(255, 241, 230),
						hoverTop = THEME.CloseHover,
						layoutOrder = 2,
						onActivated = props.onCancel,
						text = props.cancelText,
						textColor = THEME.TextMain,
						top = THEME.SecondaryBg,
					}),
				}),
			}),
		}),
	})
end

return ConsumePromptScreen
