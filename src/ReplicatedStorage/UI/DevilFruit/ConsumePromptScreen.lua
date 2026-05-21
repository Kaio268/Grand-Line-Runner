local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

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

local function isMobileViewport()
	local camera = Workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	return UserInputService.TouchEnabled or viewport.Y < 1000 or viewport.X < 760
end

local function actionButton(props)
	local hovered, setHovered = React.useState(false)
	local fill = if hovered then props.hoverFill else props.fill
	local textColor = if hovered then props.hoverText else props.textColor
	local compact = props.compact == true

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fill,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(0.5, compact and -8 or -14, 0, compact and 36 or 46),
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
			TextSize = compact and 16 or 22,
		}),
	})
end

local function ConsumePromptScreen(props)
	if props.visible ~= true then
		return e(React.Fragment)
	end
	local mobile = isMobileViewport()
	local panelSize = mobile and Vector2.new(380, 248) or Vector2.new(620, 360)
	local topBarHeight = mobile and 62 or 88
	local contentTop = mobile and 88 or 114

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
			Size = UDim2.fromOffset(panelSize.X, panelSize.Y),
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
				Position = UDim2.fromOffset(mobile and 10 or 14, mobile and 10 or 12),
				Size = UDim2.new(1, mobile and -20 or -28, 0, topBarHeight),
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
					Position = UDim2.fromOffset(mobile and 12 or 16, mobile and 6 or 8),
					Size = UDim2.new(1, mobile and -24 or -32, 0, mobile and 16 or 20),
					Text = "DEVIL FRUIT",
					TextColor3 = THEME.GoldHighlight,
					TextSize = mobile and 11 or 16,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 82,
				}),
				Title = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Enum.Font.GothamBold,
					Position = UDim2.fromOffset(mobile and 12 or 16, mobile and 22 or 30),
					Size = UDim2.new(1, mobile and -24 or -32, 0, mobile and 34 or 48),
					Text = props.title,
					TextColor3 = THEME.TextMain,
					TextSize = mobile and 17 or 22,
					TextStrokeColor3 = THEME.GoldHighlight,
					TextStrokeTransparency = 0.58,
					TextTruncate = Enum.TextTruncate.AtEnd,
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 82,
				}),
			}),
			Content = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(mobile and 14 or 20, contentTop),
				Size = UDim2.new(1, mobile and -28 or -40, 1, -(contentTop + (mobile and 14 or 22))),
				ZIndex = 81,
			}, {
				BodyCard = e("Frame", {
					BackgroundColor3 = THEME.SectionBackground,
					BackgroundTransparency = 0.22,
					BorderSizePixel = 0,
					Size = UDim2.new(1, 0, 1, mobile and -48 or -64),
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
						PaddingBottom = UDim.new(0, mobile and 10 or 14),
						PaddingLeft = UDim.new(0, mobile and 12 or 16),
						PaddingRight = UDim.new(0, mobile and 12 or 16),
						PaddingTop = UDim.new(0, mobile and 10 or 14),
					}),
					Body = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = Enum.Font.GothamBold,
						Size = UDim2.fromScale(1, 1),
						Text = props.body,
						TextColor3 = THEME.TextSecondary,
						TextSize = mobile and 16 or 24,
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
					Size = UDim2.new(1, 0, 0, mobile and 38 or 48),
					ZIndex = 82,
				}, {
					Layout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						Padding = UDim.new(0, mobile and 16 or 28),
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
						compact = mobile,
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
						compact = mobile,
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
