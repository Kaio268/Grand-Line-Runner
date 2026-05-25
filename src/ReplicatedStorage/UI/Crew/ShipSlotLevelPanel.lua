local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local PROGRESS_TWEEN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local THEME = {
	PanelTop = Color3.fromRGB(255, 224, 39),
	PanelMid = Color3.fromRGB(246, 184, 38),
	PanelBottom = Color3.fromRGB(210, 105, 8),
	PanelEdge = Color3.fromRGB(96, 48, 2),
	PanelShadow = Color3.fromRGB(58, 29, 4),
	CardTop = Color3.fromRGB(205, 124, 14),
	CardBottom = Color3.fromRGB(145, 71, 6),
	Text = Color3.fromRGB(255, 255, 255),
	TextShadow = Color3.fromRGB(0, 0, 0),
	NoFood = Color3.fromRGB(255, 111, 104),
	ReadyFood = Color3.fromRGB(202, 255, 133),
	ProgressTrack = Color3.fromRGB(29, 32, 30),
	ProgressFillTop = Color3.fromRGB(111, 255, 24),
	ProgressFillBottom = Color3.fromRGB(19, 181, 21),
	ButtonTop = Color3.fromRGB(115, 255, 18),
	ButtonBottom = Color3.fromRGB(0, 172, 22),
	ButtonEdge = Color3.fromRGB(0, 85, 17),
	ButtonHighlight = Color3.fromRGB(195, 255, 86),
	ButtonText = Color3.fromRGB(255, 255, 255),
	ButtonDisabledTop = Color3.fromRGB(96, 113, 138),
	ButtonDisabledBottom = Color3.fromRGB(58, 72, 92),
	ButtonDisabledStroke = Color3.fromRGB(176, 190, 207),
	ButtonDisabledText = Color3.fromRGB(231, 238, 248),
	Cost = Color3.fromRGB(255, 237, 50),
}

local PANEL_TUNING = {
	TitleTextScale = 1,
	XpTextScale = 1,
	CardTextScale = 1,
	ProgressTextScale = 1,
	ButtonTextScale = 1,
	LoadingTextScale = 1,

	TextStrokeThickness = 2,
	SmallTextStrokeThickness = 1.5,
	PanelStroke = 4,
	ButtonStroke = 3,
	CardStroke = 2,
	TextStrokeTransparency = 0.26,
	SmallTextStrokeTransparency = 0.3,

	ButtonHoverScale = 1,
	ButtonPressScale = 1,
	ButtonHoverBrightness = 1.08,
	ButtonCornerRadius = 13,
	ButtonDisabledBrightness = 0.72,
	ButtonGradientStrength = 1,

	ButtonTextPaddingX = 0.045,
	ButtonTextPaddingY = 0.08,
	CardTextPaddingX = 0.08,
	CardTextPaddingY = 0.12,
	ContentPaddingX = 0.04,
	ContentPaddingY = 0.04,
	PanelHeightScale = 0.62,
	RowGapScale = 0.025,
	ProgressBarHeight = 0.085,
	BottomRowHeight = 0.26,
	ButtonHeightScale = 0.98,
	ButtonWidthScale = 0.9,
	VerticalPaddingScale = 0.075,
}

local function tunedTextSize(baseSize, scaleKey)
	return math.max(1, math.floor((tonumber(baseSize) or 1) * (PANEL_TUNING[scaleKey] or 1) + 0.5))
end

local function brighten(color, factor)
	local amount = tonumber(factor) or 1
	return Color3.new(
		math.clamp(color.R * amount, 0, 1),
		math.clamp(color.G * amount, 0, 1),
		math.clamp(color.B * amount, 0, 1)
	)
end

local function corner(radius)
	return e("UICorner", {
		CornerRadius = UDim.new(0, radius),
	})
end

local function stroke(color, thickness, transparency)
	return e("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = thickness,
		Transparency = transparency or 0,
	})
end

local function gradient(topColor, bottomColor, rotation)
	return e("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, topColor),
			ColorSequenceKeypoint.new(1, bottomColor),
		}),
		Rotation = rotation or 90,
	})
end

local function crispText(props)
	local scaled = props.scaled == true
	local children = nil
	if scaled then
		children = {
			SizeConstraint = e("UITextSizeConstraint", {
				MaxTextSize = props.maxTextSize or props.textSize or 24,
				MinTextSize = props.minTextSize or 10,
			}),
		}
	end

	return e("TextLabel", {
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
		Font = props.font or Enum.Font.GothamBold,
		LayoutOrder = props.layoutOrder,
		Position = props.position,
		RichText = props.richText == true,
		Size = props.size,
		Text = props.text,
		TextColor3 = props.color3 or THEME.Text,
		TextScaled = scaled,
		TextSize = props.textSize or props.maxTextSize or 24,
		TextStrokeColor3 = THEME.TextShadow,
		TextStrokeTransparency = props.strokeTransparency or PANEL_TUNING.TextStrokeTransparency,
		TextTruncate = props.truncate or Enum.TextTruncate.AtEnd,
		TextWrapped = props.wrapped == true,
		TextXAlignment = props.xAlignment or Enum.TextXAlignment.Center,
		TextYAlignment = props.yAlignment or Enum.TextYAlignment.Center,
		ZIndex = props.zIndex or 10,
	}, children)
end

local function ShipSlotLevelPanel(props)
	local isLoading = props.isLoading == true
	local isMaxLevel = props.isMaxLevel == true
	local hasFood = props.hasFood == true
	local currentXP = math.max(0, math.floor(tonumber(props.currentXP) or 0))
	local nextLevelXP = math.max(0, math.floor(tonumber(props.nextLevelXP) or 0))
	local progressRatio = math.clamp(tonumber(props.progressRatio) or 0, 0, 1)
	local levelText = tostring(props.levelText or "")
	local xpText = tostring(props.xpText or props.progressText or "")
	local visible = isLoading or levelText ~= "" or xpText ~= ""
	local statusText = if isMaxLevel then "Max Level" elseif hasFood then "Auto-feed" else "No Food"
	local statusColor = if isMaxLevel then THEME.Cost elseif hasFood then THEME.ReadyFood else THEME.NoFood
	local xpValueText = if isMaxLevel then "XP Complete" else string.format("XP: %d / %d", currentXP, nextLevelXP)
	local upgradeText = if isMaxLevel then "MAX LEVEL" else "UPGRADE"
	local fillRef = React.useRef(nil)
	local displayedProgressRef = React.useRef(progressRatio)
	local isButtonHovered, setIsButtonHovered = React.useState(false)
	local buttonEnabled = not isLoading and not isMaxLevel
	local buttonTop = if isMaxLevel then THEME.ButtonDisabledTop else THEME.ButtonTop
	local buttonBottom = if isMaxLevel then THEME.ButtonDisabledBottom else THEME.ButtonBottom
	local buttonFill = if buttonEnabled and isButtonHovered then brighten(buttonTop, PANEL_TUNING.ButtonHoverBrightness) else buttonTop
	local buttonGradientTop = buttonFill
	local buttonGradientBottom = if buttonEnabled and isButtonHovered
		then brighten(buttonBottom, PANEL_TUNING.ButtonHoverBrightness)
		else buttonBottom
	local buttonStroke = if isMaxLevel then THEME.ButtonDisabledStroke else THEME.ButtonEdge
	local buttonTextColor = if isMaxLevel then THEME.ButtonDisabledText else THEME.ButtonText

	React.useEffect(function()
		local fill = fillRef.current
		if not fill then
			displayedProgressRef.current = progressRatio
			return nil
		end

		fill.Size = UDim2.fromScale(displayedProgressRef.current, 1)
		local tween = TweenService:Create(fill, PROGRESS_TWEEN, {
			Size = UDim2.fromScale(progressRatio, 1),
		})
		local completedConnection = tween.Completed:Connect(function()
			displayedProgressRef.current = progressRatio
		end)
		tween:Play()

		return function()
			completedConnection:Disconnect()
			tween:Cancel()
			displayedProgressRef.current = progressRatio
		end
	end, { progressRatio })

	return e("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
		Visible = visible,
		ZIndex = 1,
	}, {
		Card = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = THEME.PanelTop,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(1, PANEL_TUNING.PanelHeightScale),
			ZIndex = 1,
		}, {
			Corner = corner(16),
			OuterStroke = stroke(THEME.PanelEdge, PANEL_TUNING.PanelStroke),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, THEME.PanelTop),
					ColorSequenceKeypoint.new(0.48, THEME.PanelMid),
					ColorSequenceKeypoint.new(1, THEME.PanelBottom),
				}),
				Rotation = 90,
			}),
			LowerShade = e("Frame", {
				BackgroundColor3 = THEME.PanelShadow,
				BackgroundTransparency = 0.84,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 0.52),
				Size = UDim2.fromScale(1, 0.48),
				ZIndex = 2,
			}),
			Content = e("Frame", {
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = false,
				Position = UDim2.fromScale(PANEL_TUNING.ContentPaddingX, PANEL_TUNING.VerticalPaddingScale),
				Size = UDim2.fromScale(
					1 - (PANEL_TUNING.ContentPaddingX * 2),
					1 - (PANEL_TUNING.VerticalPaddingScale * 2)
				),
				ZIndex = 5,
			}, {
				Layout = not isLoading and e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					HorizontalAlignment = Enum.HorizontalAlignment.Center,
					Padding = UDim.new(PANEL_TUNING.RowGapScale, 0),
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}) or nil,
				Loading = isLoading and e(crispText, {
					position = UDim2.fromScale(0.12, 0.35),
					size = UDim2.fromScale(0.76, 0.3),
					strokeTransparency = PANEL_TUNING.TextStrokeTransparency,
					text = "Loading...",
					textSize = tunedTextSize(48, "LoadingTextScale"),
					zIndex = 9,
				}) or nil,
				Level = not isLoading and e(crispText, {
					layoutOrder = 1,
					size = UDim2.fromScale(1, 0.26),
					strokeTransparency = PANEL_TUNING.TextStrokeTransparency,
					text = levelText,
					textSize = tunedTextSize(50, "TitleTextScale"),
					zIndex = 9,
				}) or nil,
				XPRow = not isLoading and e("Frame", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					LayoutOrder = 2,
					Size = UDim2.fromScale(0.92, 0.15),
					ZIndex = 8,
				}, {
					XPValue = e(crispText, {
						position = UDim2.fromScale(0, 0),
						size = UDim2.fromScale(0.62, 1),
						strokeTransparency = PANEL_TUNING.TextStrokeTransparency,
						text = xpValueText,
						textSize = tunedTextSize(34, "XpTextScale"),
						xAlignment = Enum.TextXAlignment.Right,
						zIndex = 9,
					}),
					Status = e(crispText, {
						color3 = statusColor,
						position = UDim2.fromScale(0.65, 0),
						size = UDim2.fromScale(0.35, 1),
						strokeTransparency = PANEL_TUNING.TextStrokeTransparency,
						text = statusText,
						textSize = tunedTextSize(34, "XpTextScale"),
						xAlignment = Enum.TextXAlignment.Left,
						zIndex = 9,
					}),
				}) or nil,
				ProgressTrack = not isLoading and e("Frame", {
					BackgroundColor3 = THEME.ProgressTrack,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					LayoutOrder = 3,
					Size = UDim2.fromScale(0.92, PANEL_TUNING.ProgressBarHeight),
					ZIndex = 8,
				}, {
					Corner = corner(999),
					Stroke = stroke(Color3.fromRGB(7, 10, 8), 2, 0.04),
					Fill = e("Frame", {
						BackgroundColor3 = THEME.ProgressFillTop,
						BorderSizePixel = 0,
						ref = fillRef,
						Size = UDim2.fromScale(displayedProgressRef.current, 1),
						ZIndex = 9,
					}, {
						Corner = corner(999),
						Gradient = gradient(THEME.ProgressFillTop, THEME.ProgressFillBottom),
					}),
				}) or nil,
				BottomRow = not isLoading and e("Frame", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					LayoutOrder = 4,
					Size = UDim2.fromScale(0.92, PANEL_TUNING.BottomRowHeight),
					ZIndex = 7,
				}, {
					Layout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					}),
					ButtonWrap = e("Frame", {
						BackgroundTransparency = 1,
						BorderSizePixel = 0,
						ClipsDescendants = false,
						LayoutOrder = 2,
						Size = UDim2.fromScale(PANEL_TUNING.ButtonWidthScale, PANEL_TUNING.ButtonHeightScale),
						ZIndex = 7,
					}, {
						UpgradeButton = e("TextButton", {
							Active = buttonEnabled,
							AnchorPoint = Vector2.new(0.5, 0.5),
							AutoButtonColor = false,
							BackgroundColor3 = buttonFill,
							BorderSizePixel = 0,
							ClipsDescendants = true,
							Position = UDim2.fromScale(0.5, 0.5),
							Selectable = buttonEnabled,
							Size = UDim2.fromScale(1, 1),
							Text = "",
							ZIndex = 9,
							[React.Event.Activated] = buttonEnabled and props.onActivated or nil,
							[React.Event.MouseEnter] = function()
								if buttonEnabled then
									setIsButtonHovered(true)
								end
							end,
							[React.Event.MouseLeave] = function()
								if buttonEnabled then
									setIsButtonHovered(false)
								end
							end,
						}, {
							Corner = corner(PANEL_TUNING.ButtonCornerRadius),
							Stroke = stroke(
								buttonStroke,
								PANEL_TUNING.ButtonStroke,
								if isMaxLevel then 0.42 else 0.08
							),
							Gradient = gradient(buttonGradientTop, buttonGradientBottom),
							TopHighlight = not isMaxLevel and e("Frame", {
								BackgroundColor3 = THEME.ButtonHighlight,
								BackgroundTransparency = 0.62,
								BorderSizePixel = 0,
								Position = UDim2.fromScale(0.03, 0.08),
								Size = UDim2.fromScale(0.94, 0.32),
								ZIndex = 10,
							}, {
								Corner = corner(PANEL_TUNING.ButtonCornerRadius - 2),
							}) or nil,
							UpgradeText = e(crispText, {
								color3 = buttonTextColor,
								font = Enum.Font.GothamBlack,
								position = UDim2.fromScale(PANEL_TUNING.ButtonTextPaddingX, PANEL_TUNING.ButtonTextPaddingY),
								size = UDim2.fromScale(
									1 - (PANEL_TUNING.ButtonTextPaddingX * 2),
									1 - (PANEL_TUNING.ButtonTextPaddingY * 2)
								),
								maxTextSize = tunedTextSize(46, "ButtonTextScale"),
								minTextSize = tunedTextSize(22, "ButtonTextScale"),
								scaled = true,
								strokeTransparency = if isMaxLevel then 0.58 else 0.18,
								text = upgradeText,
								zIndex = 11,
							}),
						}),
					}),
				}) or nil,
			}),
		}),
	})
end

return ShipSlotLevelPanel
