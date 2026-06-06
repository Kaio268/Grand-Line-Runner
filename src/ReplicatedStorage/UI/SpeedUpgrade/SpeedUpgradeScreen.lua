local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	PrimaryBg = Color3.fromRGB(8, 8, 9),
	SecondaryBg = Color3.fromRGB(16, 16, 19),
	PanelFillDark = Color3.fromRGB(12, 12, 14),
	GoldBase = Color3.fromRGB(228, 190, 78),
	GoldHighlight = Color3.fromRGB(255, 224, 120),
	GoldShadow = Color3.fromRGB(150, 112, 42),
	TextMain = Color3.fromRGB(235, 235, 235),
	TextSecondary = Color3.fromRGB(190, 194, 202),
	TextBright = Color3.fromRGB(255, 247, 216),
	HeaderBackground = Color3.fromRGB(16, 16, 19),
	SectionBackground = Color3.fromRGB(18, 18, 21),
	SectionHover = Color3.fromRGB(30, 30, 35),
	MenuOverlay = Color3.fromRGB(8, 8, 9),
	BeliFill = Color3.fromRGB(228, 190, 78),
	BeliFillHover = Color3.fromRGB(255, 224, 120),
	RobuxFill = Color3.fromRGB(20, 20, 24),
	RobuxFillHover = Color3.fromRGB(30, 30, 35),
	Success = Color3.fromRGB(129, 232, 168),
	CloseBright = Color3.fromRGB(200, 0, 9),
	CloseBrightSoft = Color3.fromRGB(235, 70, 78),
	BackgroundImage = "rbxassetid://75192947200012",
}

local function gradient(first, second, rotation)
	return e("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, first),
			ColorSequenceKeypoint.new(1, second),
		}),
		Rotation = rotation or 90,
	})
end

local function purchaseButton(props)
	local hovered, setHovered = React.useState(false)
	local internalRef = React.useRef(nil)
	local buttonRef = props.buttonRef or internalRef

	React.useEffect(function()
		local button = buttonRef.current
		if not button then
			return
		end

		CollectionService:AddTag(button, "NoAnim")
		return function()
			if button.Parent then
				CollectionService:RemoveTag(button, "NoAnim")
			end
		end
	end, {})

	local fill = if hovered then props.hoverColor3 else props.color3

	return e("TextButton", {
		ref = buttonRef,
		AnchorPoint = Vector2.new(1, 0.5),
		AutoButtonColor = false,
		BackgroundColor3 = fill,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Position = props.position,
		Size = props.size,
		Text = "",
		ZIndex = 7,
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
			Transparency = 0.18,
			Thickness = 1.25,
		}),
		Gradient = gradient(fill, props.gradientEndColor3 or THEME.PrimaryBg),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Size = UDim2.fromScale(1, 1),
			Text = props.text,
			TextColor3 = props.textColor3 or THEME.TextBright,
			TextSize = 13,
			TextStrokeColor3 = Color3.fromRGB(10, 14, 18),
			TextStrokeTransparency = 0.18,
			ZIndex = 8,
		}),
	})
end

local function statPill(props)
	return e("Frame", {
		BackgroundColor3 = THEME.PanelFillDark,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Position = props.position,
		Size = props.size,
		ZIndex = 6,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0.42,
			Thickness = 1,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(8, 4),
			Size = UDim2.new(1, -16, 0, 12),
			Text = props.label,
			TextColor3 = THEME.TextSecondary,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		}),
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(8, 17),
			Size = UDim2.new(1, -16, 0, 17),
			Text = props.value,
			TextColor3 = props.valueColor3 or THEME.TextMain,
			TextSize = 13,
			TextStrokeColor3 = THEME.GoldShadow,
			TextStrokeTransparency = 0.62,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 7,
		}),
	})
end

local function upgradeRow(props)
	local hovered, setHovered = React.useState(false)

	return e("Frame", {
		Active = true,
		BackgroundColor3 = if hovered then THEME.SectionHover else THEME.SectionBackground,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, -16, 0, 92),
		ZIndex = 5,
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
			Transparency = hovered and 0.16 or 0.34,
			Thickness = 1.5,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(14, 9),
			Size = UDim2.fromOffset(168, 18),
			Text = props.title,
			TextColor3 = THEME.TextBright,
			TextSize = 15,
			TextStrokeColor3 = THEME.GoldShadow,
			TextStrokeTransparency = 0.52,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 6,
		}),
		Current = e(statPill, {
			label = "Current",
			position = UDim2.fromOffset(14, 36),
			size = UDim2.fromOffset(106, 40),
			value = props.currentText,
		}),
		After = e(statPill, {
			label = "After",
			position = UDim2.fromOffset(128, 36),
			size = UDim2.fromOffset(106, 40),
			value = props.afterText,
			valueColor3 = THEME.Success,
		}),
		Buy = e(purchaseButton, {
			buttonRef = props.buyRef,
			color3 = THEME.BeliFill,
			gradientEndColor3 = THEME.GoldShadow,
			hoverColor3 = THEME.BeliFillHover,
			onActivated = props.onBuy,
			position = UDim2.new(1, -132, 0.5, 0),
			size = UDim2.fromOffset(116, 34),
			text = props.buyText,
			textColor3 = Color3.new(1, 1, 1),
		}),
		Robux = e(purchaseButton, {
			color3 = THEME.RobuxFill,
			gradientEndColor3 = THEME.PrimaryBg,
			hoverColor3 = THEME.RobuxFillHover,
			onActivated = props.onRobux,
			position = UDim2.new(1, -10, 0.5, 0),
			size = UDim2.fromOffset(112, 34),
			text = props.robuxText,
		}),
	})
end

local function SpeedUpgradeScreen(props)
	local rootRef = React.useRef(nil)
	local buyRef = React.useRef(nil)
	local closeRef = React.useRef(nil)

	React.useEffect(function()
		if props.onRefsChanged then
			props.onRefsChanged(buyRef.current, closeRef.current, rootRef.current)
		end
	end)

	local children = {
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, 8),
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 6),
			PaddingTop = UDim.new(0, 6),
		}),
		Layout = e("UIListLayout", {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, item in ipairs(props.items or {}) do
		children["Upgrade" .. tostring(index)] = e(upgradeRow, {
			afterText = item.afterText,
			buyRef = if index == 1 then buyRef else nil,
			buyText = item.buyText,
			currentText = item.currentText,
			layoutOrder = index,
			onBuy = function()
				props.onBuy(item.key)
			end,
			onRobux = function()
				props.onRobux(item.productId)
			end,
			robuxText = item.robuxText,
			title = item.title,
		})
	end

	return e("Frame", {
		ref = rootRef,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.MenuOverlay,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		BaseTexture = e("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = THEME.BackgroundImage,
			Position = UDim2.fromOffset(2, 2),
			ScaleType = Enum.ScaleType.Stretch,
			Size = UDim2.new(1, -4, 1, -4),
			ImageTransparency = 0.48,
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
		}),
		Overlay = e("Frame", {
			BackgroundColor3 = THEME.MenuOverlay,
			BackgroundTransparency = 0.12,
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
				Transparency = 0.08,
				Thickness = 2.5,
			}),
		}),
		TopBar = e("Frame", {
			BackgroundColor3 = THEME.HeaderBackground,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 8),
			Size = UDim2.new(1, -20, 0, 44),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Transparency = 0.18,
				Thickness = 1.5,
			}),
			Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
			Title = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(300, 26),
				Text = "SPEED UPGRADES",
				TextColor3 = THEME.GoldHighlight,
				TextScaled = true,
				TextSize = 24,
				TextStrokeColor3 = THEME.GoldHighlight,
				TextStrokeTransparency = 0.58,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 6,
			}),
			Close = e("TextButton", {
				ref = closeRef,
				AnchorPoint = Vector2.new(1, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = THEME.CloseBright,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(1, -7, 0.5, 0),
				Size = UDim2.fromOffset(28, 28),
				Text = "X",
				TextColor3 = Color3.new(1, 1, 1),
				TextScaled = true,
				TextStrokeColor3 = Color3.fromRGB(9, 17, 27),
				TextStrokeTransparency = 0.4,
				ZIndex = 6,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Stroke = e("UIStroke", {
					Color = THEME.GoldShadow,
					Transparency = 0.1,
					Thickness = 1,
				}),
				Gradient = gradient(THEME.CloseBrightSoft, THEME.CloseBright),
			}),
		}),
		List = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(16, 62),
			Size = UDim2.new(1, -32, 1, -76),
			ZIndex = 5,
		}, children),
	})
end

return SpeedUpgradeScreen
