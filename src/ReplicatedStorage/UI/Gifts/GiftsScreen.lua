local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	HeaderBackground = Color3.fromRGB(16, 35, 59),
	SectionBackground = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	CloseBright = Color3.fromRGB(200, 0, 9),
	CloseBrightSoft = Color3.fromRGB(235, 70, 78),
	BackgroundImage = "rbxassetid://114391753019319",
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

local function slotCard(props)
	local hovered, setHovered = React.useState(false)
	local claimRef = React.useRef(nil)

	React.useEffect(function()
		local claimButton = claimRef.current
		if not claimButton then
			return
		end

		CollectionService:AddTag(claimButton, "NoAnim")
		return function()
			if claimButton.Parent then
				CollectionService:RemoveTag(claimButton, "NoAnim")
			end
		end
	end, {})

	return e("Frame", {
		Active = true,
		BackgroundColor3 = hovered and THEME.SectionHover or THEME.SectionBackground,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, -30, 0, 82),
		ZIndex = 4,
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
			Transparency = 0,
			Thickness = 1.5,
		}),
		RewName = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(68, 15),
			Size = UDim2.new(1, -192, 0, 22),
			Text = "",
			TextColor3 = THEME.TextMain,
			TextSize = 17,
			TextStrokeColor3 = THEME.GoldShadow,
			TextStrokeTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}),
		Timer = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(68, 42),
			Size = UDim2.new(1, -192, 0, 20),
			Text = "",
			TextColor3 = THEME.TextSecondary,
			TextSize = 15,
			TextStrokeColor3 = THEME.GoldShadow,
			TextStrokeTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}),
		Icon = e("ImageLabel", {
			BackgroundColor3 = THEME.HeaderBackground,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 19),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(44, 44),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Transparency = 0,
				Thickness = 1,
			}),
		}),
		ClaimButton = e("TextButton", {
			ref = claimRef,
			Active = true,
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = THEME.SecondaryBg,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(92, 34),
			Text = "",
			ZIndex = 6,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Transparency = 0,
				Thickness = 1.2,
			}),
			Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
			Text = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Size = UDim2.fromScale(1, 1),
				Text = "Claim",
				TextColor3 = THEME.TextMain,
				TextSize = 18,
				TextStrokeColor3 = THEME.GoldShadow,
				TextStrokeTransparency = 0.45,
				ZIndex = 7,
			}),
		}),
	})
end

local function GiftsScreen(props)
	local rootRef = React.useRef(nil)
	local mainRef = React.useRef(nil)
	local closeRef = React.useRef(nil)

	React.useEffect(function()
		if props.onRefsChanged then
			props.onRefsChanged(rootRef.current, mainRef.current, closeRef.current)
		end
	end)

	local slots = {
		ContentPadding = e("UIPadding", {
			PaddingBottom = UDim.new(0, 10),
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 8),
		}),
		SlotLayout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index = 1, props.rewardCount do
		slots["Slot" .. tostring(index)] = e(slotCard, {
			layoutOrder = index,
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
				Transparency = 0,
				Thickness = 3,
			}),
		}),
		TopBar = e("Frame", {
			BackgroundColor3 = THEME.HeaderBackground,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 54),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Transparency = 0,
				Thickness = 1.5,
			}),
			Title = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(260, 32),
				Text = "GIFTS",
				TextColor3 = THEME.TextMain,
				TextScaled = true,
				TextSize = 30,
				TextStrokeColor3 = THEME.GoldHighlight,
				TextStrokeTransparency = 0.42,
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
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(34, 34),
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
		Main = e("Frame", {
			ref = mainRef,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(18, 116),
			Size = UDim2.new(1, -42, 1, -126),
			ZIndex = 3,
		}, {
			Scroll = e("ScrollingFrame", {
				Active = true,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromOffset(0, 0),
				ClipsDescendants = true,
				Position = UDim2.fromScale(0, 0),
				ScrollBarImageColor3 = THEME.GoldHighlight,
				ScrollBarThickness = 8,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				ScrollingEnabled = true,
				Size = UDim2.fromScale(1, 1),
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
				ZIndex = 4,
			}, slots),
		}),
	})
end

return GiftsScreen
