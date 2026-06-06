local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	CardBg = Color3.fromRGB(15, 27, 42),
	PanelBg = Color3.fromRGB(11, 22, 35),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TitleCream = Color3.fromRGB(255, 222, 130),
	TextMain = Color3.fromRGB(235, 235, 235),
	TextSecondary = Color3.fromRGB(196, 205, 216),
	TextDisabled = Color3.fromRGB(122, 134, 150),
	Success = Color3.fromRGB(125, 219, 159),
	PrimaryButton = Color3.fromRGB(212, 175, 55),
	PrimaryButtonHover = Color3.fromRGB(236, 201, 92),
	PrimaryButtonText = Color3.fromRGB(58, 33, 3),
	SecondaryButton = Color3.fromRGB(11, 22, 35),
	SecondaryButtonHover = Color3.fromRGB(24, 40, 58),
	SecondaryButtonText = Color3.fromRGB(235, 235, 235),
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

local function goldStroke(thickness, transparency)
	return e("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = THEME.GoldHighlight,
		Transparency = transparency or 0,
		Thickness = thickness or 1.5,
	}, {
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, THEME.GoldHighlight),
				ColorSequenceKeypoint.new(1, THEME.GoldShadow),
			}),
			Rotation = 90,
		}),
	})
end

local function actionButton(props)
	local buttonRef = React.useRef(nil)

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

	return e("TextButton", {
		ref = buttonRef,
		AutoButtonColor = false,
		BackgroundColor3 = if props.hovered then props.hoverColor3 else props.color3,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		Font = Enum.Font.Cartoon,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, -16, 0, 48),
		Text = "",
		ZIndex = 6,
		[React.Event.Activated] = props.onActivated,
		[React.Event.MouseEnter] = props.onMouseEnter,
		[React.Event.MouseLeave] = props.onMouseLeave,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = goldStroke(1.4, 0),
		Gradient = gradient(if props.hovered then props.hoverColor3 else props.color3, THEME.CardBg),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Cartoon,
			Size = UDim2.fromScale(1, 1),
			Text = props.text,
			TextColor3 = props.textColor3,
			TextSize = 18,
			TextStrokeColor3 = Color3.fromRGB(10, 14, 18),
			TextStrokeTransparency = 0.5,
			ZIndex = 7,
		}),
	})
end

local function infoRow(props)
	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 24),
	}, {
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.SourceSans,
			Size = UDim2.fromScale(0.44, 1),
			Text = props.label,
			TextColor3 = THEME.TextSecondary,
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.SourceSansBold,
			Position = UDim2.fromScale(0.44, 0),
			Size = UDim2.fromScale(0.56, 1),
			Text = props.value,
			TextColor3 = props.valueColor3 or THEME.TextMain,
			TextSize = 16,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

local function NamiShopScreen(props)
	local hoveredAction, setHoveredAction = React.useState(nil)

	local function makeActionHoverHandler(name)
		return function()
			setHoveredAction(name)
		end
	end

	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = THEME.CardBg,
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
			ImageTransparency = 0.82,
			Position = UDim2.fromOffset(2, 2),
			ScaleType = Enum.ScaleType.Stretch,
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 1,
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
			Stroke = goldStroke(3, 0),
		}),
		InnerBorder = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(8, 8),
			Size = UDim2.new(1, -16, 1, -16),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
			Stroke = goldStroke(1.2, 0.3),
		}),
		TopBar = e("Frame", {
			BackgroundColor3 = THEME.PanelBg,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 48),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = goldStroke(1.5, 0),
			Title = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.SpecialElite,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(260, 32),
				Text = "NAMI",
				TextColor3 = THEME.TitleCream,
				TextScaled = true,
				TextSize = 30,
				TextStrokeColor3 = THEME.GoldShadow,
				TextStrokeTransparency = 0.5,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 6,
			}),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = THEME.CloseBright,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(32, 32),
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
		Info = e("Frame", {
			BackgroundColor3 = THEME.PanelBg,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 70),
			Size = UDim2.new(1, -36, 0, 100),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = goldStroke(1.5, 0),
			Padding = e("UIPadding", {
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 12),
				PaddingRight = UDim.new(0, 12),
				PaddingTop = UDim.new(0, 8),
			}),
			Layout = e("UIListLayout", {
				Padding = UDim.new(0, 4),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			InventoryValue = e(infoRow, {
				label = "Inventory value",
				layoutOrder = 1,
				value = props.inventoryValueText,
				valueColor3 = THEME.Success,
			}),
			EquippedItem = e(infoRow, {
				label = "Equipped item",
				layoutOrder = 2,
				value = props.equippedItemText,
			}),
			EquippedValue = e(infoRow, {
				label = "Equipped value",
				layoutOrder = 3,
				value = props.equippedValueText,
				valueColor3 = props.hasEquippedValue and THEME.GoldHighlight or THEME.TextDisabled,
			}),
		}),
		Actions = e("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(18, 182),
			Size = UDim2.new(1, -36, 0, 112),
			ZIndex = 5,
		}, {
			Layout = e("UIListLayout", {
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
				PaddingTop = UDim.new(0, 4),
			}),
			SellInventory = e(actionButton, {
				color3 = THEME.PrimaryButton,
				hovered = hoveredAction == "SellInventory",
				hoverColor3 = THEME.PrimaryButtonHover,
				layoutOrder = 1,
				onActivated = props.onSellInventory,
				onMouseEnter = makeActionHoverHandler("SellInventory"),
				onMouseLeave = makeActionHoverHandler(nil),
				text = "Use Inventory",
				textColor3 = THEME.PrimaryButtonText,
			}),
			SellEquipped = e(actionButton, {
				color3 = THEME.SecondaryButton,
				hovered = hoveredAction == "SellEquipped",
				hoverColor3 = THEME.SecondaryButtonHover,
				layoutOrder = 2,
				onActivated = props.onSellEquipped,
				onMouseEnter = makeActionHoverHandler("SellEquipped"),
				onMouseLeave = makeActionHoverHandler(nil),
				text = "Stored Only",
				textColor3 = THEME.SecondaryButtonText,
			}),
		}),
		Status = e("Frame", {
			BackgroundColor3 = THEME.PanelBg,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 18, 1, -58),
			Size = UDim2.new(1, -36, 0, 46),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = goldStroke(1.2, 0.2),
			Gradient = gradient(THEME.PanelBg, THEME.CardBg),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.SourceSansBold,
				Size = UDim2.fromScale(1, 1),
				Text = props.statusText,
				TextColor3 = props.statusColor3 or THEME.TextMain,
				TextSize = 16,
				TextStrokeColor3 = THEME.GoldShadow,
				TextStrokeTransparency = 0.5,
				TextWrapped = true,
				ZIndex = 6,
			}),
		}),
	})
end

return NamiShopScreen
