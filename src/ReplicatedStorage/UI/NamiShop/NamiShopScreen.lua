local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	PanelFillDark = Color3.fromRGB(34, 49, 66),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	TextDisabled = Color3.fromRGB(122, 134, 150),
	Success = Color3.fromRGB(125, 219, 159),
	HeaderBackground = Color3.fromRGB(16, 35, 59),
	SectionBackground = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	SellAll = Color3.fromRGB(58, 104, 63),
	SellAllHover = Color3.fromRGB(82, 143, 88),
	SellOne = Color3.fromRGB(28, 67, 102),
	SellOneHover = Color3.fromRGB(42, 95, 142),
	CheckValue = Color3.fromRGB(108, 78, 28),
	CheckValueHover = Color3.fromRGB(149, 108, 40),
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
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
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
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0,
			Thickness = 1.4,
		}),
		Gradient = gradient(props.hovered and props.hoverColor3 or props.color3, THEME.PrimaryBg),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Size = UDim2.fromScale(1, 1),
			Text = props.text,
			TextColor3 = Color3.fromRGB(247, 242, 229),
			TextSize = 16,
			TextStrokeColor3 = Color3.fromRGB(10, 14, 18),
			TextStrokeTransparency = 0.12,
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
			Font = Enum.Font.Gotham,
			Size = UDim2.fromScale(0.44, 1),
			Text = props.label,
			TextColor3 = THEME.TextSecondary,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromScale(0.44, 0),
			Size = UDim2.fromScale(0.56, 1),
			Text = props.value,
			TextColor3 = props.valueColor3 or THEME.TextMain,
			TextSize = 14,
			TextStrokeColor3 = THEME.GoldShadow,
			TextStrokeTransparency = 0.72,
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
			Size = UDim2.new(1, -24, 0, 48),
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
				Text = "NAMI",
				TextColor3 = THEME.TextMain,
				TextScaled = true,
				TextSize = 30,
				TextStrokeColor3 = THEME.GoldHighlight,
				TextStrokeTransparency = 0.42,
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
			BackgroundColor3 = THEME.SectionBackground,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 70),
			Size = UDim2.new(1, -36, 0, 100),
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
				color3 = THEME.SellAll,
				hovered = hoveredAction == "SellInventory",
				hoverColor3 = THEME.SellAllHover,
				layoutOrder = 1,
				onActivated = props.onSellInventory,
				onMouseEnter = makeActionHoverHandler("SellInventory"),
				onMouseLeave = makeActionHoverHandler(nil),
				text = "Sell My Inventory",
			}),
			SellEquipped = e(actionButton, {
				color3 = THEME.SellOne,
				hovered = hoveredAction == "SellEquipped",
				hoverColor3 = THEME.SellOneHover,
				layoutOrder = 2,
				onActivated = props.onSellEquipped,
				onMouseEnter = makeActionHoverHandler("SellEquipped"),
				onMouseLeave = makeActionHoverHandler(nil),
				text = "Sell This Item",
			}),
		}),
		Status = e("Frame", {
			BackgroundColor3 = THEME.PanelFillDark,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 18, 1, -58),
			Size = UDim2.new(1, -36, 0, 46),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = THEME.GoldBase,
				Transparency = 0.4,
				Thickness = 1,
			}),
			Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Size = UDim2.fromScale(1, 1),
				Text = props.statusText,
				TextColor3 = props.statusColor3 or THEME.TextMain,
				TextSize = 14,
				TextStrokeColor3 = THEME.GoldShadow,
				TextStrokeTransparency = 0.35,
				TextWrapped = true,
				ZIndex = 6,
			}),
		}),
	})
end

return NamiShopScreen
