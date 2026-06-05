local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

-- Shared design language with the SELL / QUESTS menus: semi-transparent black
-- card, brighter gold gradient borders, a prominent gold edge glow, a gold
-- SpecialElite pill badge and Fredoka text with black outlines. Element NAMES
-- (Scroll / RewName / Timer / Icon / ClaimButton / Text) are preserved because
-- Time_Rewards.lua populates them by name.
local SHELL = {
	CardBg = Color3.fromRGB(8, 8, 9),
	SlotBg = Color3.fromRGB(14, 14, 16),
	SlotHover = Color3.fromRGB(24, 24, 28),
	IconBg = Color3.fromRGB(10, 10, 12),
	GoldBase = Color3.fromRGB(228, 190, 78),
	GoldHighlight = Color3.fromRGB(255, 224, 120),
	GoldShadow = Color3.fromRGB(150, 112, 42),
	Cream = Color3.fromRGB(255, 222, 130),
	TextMain = Color3.fromRGB(235, 235, 235),
	TextMuted = Color3.fromRGB(184, 188, 196),
	TextShadow = Color3.fromRGB(0, 0, 0),
	CloseFill = Color3.fromRGB(200, 0, 9),
	CloseFillSoft = Color3.fromRGB(235, 70, 78),
	GlowImage = "rbxassetid://114516018211032",
}

local BADGE_FONT = Font.new("rbxasset://fonts/families/SpecialElite.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local BODY = Enum.Font.FredokaOne

local function gradient(first, second, rotation)
	return e("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, first),
			ColorSequenceKeypoint.new(1, second),
		}),
		Rotation = rotation or 90,
	})
end

local function goldStroke(thickness, transparency)
	return e("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = SHELL.GoldHighlight,
		Transparency = transparency or 0,
		Thickness = thickness or 1.5,
	}, {
		Grad = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, SHELL.GoldHighlight),
				ColorSequenceKeypoint.new(1, SHELL.GoldShadow),
			}),
		}),
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
		BackgroundColor3 = hovered and SHELL.SlotHover or SHELL.SlotBg,
		BackgroundTransparency = 0,
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
		Stroke = goldStroke(1.5, 0),
		RewName = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY,
			Position = UDim2.fromOffset(68, 15),
			Size = UDim2.new(1, -192, 0, 22),
			Text = "",
			TextColor3 = SHELL.TextMain,
			TextSize = 17,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.3,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}),
		Timer = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY,
			Position = UDim2.fromOffset(68, 42),
			Size = UDim2.new(1, -192, 0, 20),
			Text = "",
			TextColor3 = SHELL.TextMuted,
			TextSize = 15,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 5,
		}),
		Icon = e("ImageLabel", {
			BackgroundColor3 = SHELL.IconBg,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 19),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromOffset(44, 44),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = goldStroke(1, 0),
		}),
		ClaimButton = e("TextButton", {
			ref = claimRef,
			Active = true,
			AnchorPoint = Vector2.new(1, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = SHELL.GoldBase,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(92, 34),
			Text = "",
			ZIndex = 6,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Outline = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(0, 0, 0),
				Thickness = 1.8,
				Transparency = 0,
			}, {
				Grad = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(0, 0, 0)),
				}),
			}),
			Sheen = gradient(Color3.fromRGB(255, 250, 222), Color3.fromRGB(216, 168, 64)),
			Text = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Size = UDim2.fromScale(1, 1),
				Text = "Claim",
				TextColor3 = Color3.new(1, 1, 1),
				TextSize = 18,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = 0,
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
			PaddingTop = UDim.new(0, 2),
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
		BackgroundColor3 = SHELL.CardBg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Position = UDim2.fromScale(0.5, 0.5),
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
		-- semi-transparent black fill (like Sell / Quest)
		Fill = e("Frame", {
			BackgroundColor3 = SHELL.CardBg,
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
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 16) }),
			Stroke = goldStroke(3, 0),
		}),
		InnerBorder = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 1, -16),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 12) }),
			Stroke = goldStroke(1.2, 0.3),
		}),
		-- gold pill badge title
		TitleBadge = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = SHELL.CardBg,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(176, 42),
			ZIndex = 25,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = SHELL.GoldBase,
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
				Text = "GIFTS",
				TextColor3 = SHELL.GoldBase,
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
		-- floating close button (top-right, flush to the edge)
		Close = e("TextButton", {
			ref = closeRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			AutoButtonColor = false,
			BackgroundColor3 = SHELL.CloseFill,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -4, 0, 4),
			Size = UDim2.fromOffset(34, 34),
			Text = "X",
			TextColor3 = Color3.new(1, 1, 1),
			TextScaled = true,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.25,
			ZIndex = 30,
			[React.Event.Activated] = props.onClose,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, 9) }),
			Outline = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(0, 0, 0),
				Transparency = 0,
				Thickness = 1.6,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 96, 102)),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(214, 24, 34)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 0, 6)),
				}),
			}),
		}),
		Main = e("Frame", {
			ref = mainRef,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(18, 50),
			Size = UDim2.new(1, -42, 1, -66),
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
				ScrollBarImageColor3 = SHELL.GoldHighlight,
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
