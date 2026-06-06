local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local UiFolder = ReplicatedStorage:WaitForChild("UI")
local React = require(Packages:WaitForChild("React"))
local HudLayout = require(UiFolder:WaitForChild("HudLayout"))

local e = React.createElement

local THEME = {
	FruitBackgroundImage = "rbxassetid://134053886107384",
	MenuOverlay = Color3.fromRGB(5, 6, 10),
	PrimaryBg = Color3.fromRGB(8, 9, 12),
	SecondaryBg = Color3.fromRGB(15, 15, 19),
	HeaderBg = Color3.fromRGB(12, 12, 16),
	SectionBg = Color3.fromRGB(13, 14, 18),
	GoldBase = Color3.fromRGB(208, 160, 62),
	GoldHighlight = Color3.fromRGB(247, 216, 118),
	GoldShadow = Color3.fromRGB(116, 77, 24),
	TextMain = Color3.fromRGB(247, 242, 226),
	TextSecondary = Color3.fromRGB(188, 184, 171),
	Ready = Color3.fromRGB(116, 255, 161),
	Active = Color3.fromRGB(116, 208, 255),
	ActiveFill = Color3.fromRGB(67, 171, 255),
	Cooldown = Color3.fromRGB(255, 190, 116),
	CooldownFill = Color3.fromRGB(255, 133, 44),
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

local function abilityRow(props)
	local layout = HudLayout.getDevilFruit(props.layoutMode)
	local compact = layout.compact == true or props.compact == true
	local rowHeight = tonumber(layout.rowHeight) or (compact and 34 or 58)
	local keySize = compact and Vector2.new(20, 16) or Vector2.new(34, 24)
	local onActivateAbility = props.onActivateAbility
	local showKeybind = props.showKeybinds == true
	local textLeft = showKeybind and 48 or 7
	local statusWidth = compact and 68 or 118
	local nameRightPadding = compact and 7 or 10
	local nameY = tonumber(layout.nameY) or (compact and 4 or 7)
	local statusY = tonumber(layout.statusY) or (compact and 17 or 29)
	local nameTextSize = tonumber(layout.nameTextSize) or (compact and 9 or 16)
	local statusTextSize = tonumber(layout.statusTextSize) or (compact and 8 or 12)
	local barHeight = tonumber(layout.barHeight) or (compact and 3 or 6)
	local barBottom = tonumber(layout.barBottom) or (compact and 4 or 8)
	local barInset = tonumber(layout.barInset) or (compact and 5 or 10)
	local nameText = props.name
	local detailText = if typeof(props.detail) == "string" then props.detail else ""
	local showDetail = detailText ~= "" and not compact
	local fillColor = props.fillColor3 or THEME.Ready
	if compact and typeof(props.compactName) == "string" and props.compactName ~= "" then
		nameText = props.compactName
	end

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = THEME.SectionBg,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, rowHeight),
		Text = "",
		ZIndex = 3,
		[React.Event.Activated] = function()
			if onActivateAbility then
				onActivateAbility(props.abilityName)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0.18,
			Thickness = 1.15,
		}),
		Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
		TopSheen = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 236, 174),
			BackgroundTransparency = 0.92,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, math.max(1, math.floor(rowHeight * 0.28))),
			ZIndex = 3,
		}, {
			Fade = e("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.5),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
		Key = showKeybind and e("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = THEME.GoldBase,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0, compact and 5 or 8, 0.5, compact and -4 or -6),
			Size = UDim2.fromOffset(keySize.X, keySize.Y),
			Text = props.keyCodeName,
			TextColor3 = THEME.PrimaryBg,
			TextSize = compact and 8 or 14,
			ZIndex = 4,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = THEME.GoldHighlight,
				Thickness = 1,
			}),
			Gradient = gradient(THEME.GoldHighlight, THEME.GoldBase),
		}) or nil,
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(textLeft, nameY),
			Size = UDim2.new(1, -(textLeft + nameRightPadding), 0, showDetail and 17 or (compact and 11 or 22)),
			Text = nameText,
			TextColor3 = THEME.TextMain,
			TextSize = nameTextSize,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.5,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}),
		Detail = showDetail and e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(textLeft, nameY + 18),
			Size = UDim2.new(1, -(textLeft + statusWidth + 16), 0, 12),
			Text = detailText,
			TextColor3 = THEME.TextSecondary,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}) or nil,
		Status = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, compact and -7 or -10, 0, statusY),
			Size = compact and UDim2.new(1, -14, 0, 10) or UDim2.fromOffset(statusWidth, 12),
			Text = props.status,
			TextColor3 = props.statusColor3,
			TextSize = statusTextSize,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.48,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 4,
		}),
		Bar = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Color3.fromRGB(4, 5, 8),
			BorderSizePixel = 0,
			Position = UDim2.new(0, barInset, 1, -barBottom),
			Size = UDim2.new(1, -(barInset * 2), 0, barHeight),
			ZIndex = 4,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = THEME.GoldShadow,
				Transparency = 0.26,
				Thickness = 0.8,
			}),
			Fill = e("Frame", {
				BackgroundColor3 = fillColor,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(props.progress, 1),
				ZIndex = 5,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Gloss = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 244, 202)),
						ColorSequenceKeypoint.new(1, fillColor),
					}),
				}),
			}),
		}),
	})
end

local function CooldownHud(props)
	if props.visible ~= true then
		return e(React.Fragment)
	end

	local layout = HudLayout.getDevilFruit(props.layoutMode)
	local compact = layout.compact == true or props.compact == true
	local rowHeight = tonumber(layout.rowHeight) or (compact and 34 or 58)
	local rowGap = tonumber(layout.rowGap) or (compact and 4 or 6)
	local listInset = tonumber(layout.listInset) or (compact and 10 or 16)
	local topBarHeight = tonumber(layout.topBarHeight) or (compact and 28 or 58)
	local outerInset = tonumber(layout.outerInset) or (compact and 5 or 10)
	local gap = tonumber(layout.sectionGap) or (compact and 5 or 8)
	local padding = math.floor(listInset * 0.5)
	local headerTitleY = tonumber(layout.headerTitleY) or (compact and 2 or 4)
	local headerTitleHeight = tonumber(layout.headerTitleHeight) or (compact and 10 or 16)
	local headerTitleTextSize = tonumber(layout.headerTitleTextSize) or (compact and 6 or 12)
	local fruitNameY = tonumber(layout.fruitNameY) or (compact and 12 or 20)
	local fruitNameHeight = tonumber(layout.fruitNameHeight) or (compact and 13 or 30)
	local fruitNameTextSize = tonumber(layout.fruitNameTextSize) or (compact and 12 or 28)

	local rows = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, rowGap),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, padding),
			PaddingLeft = UDim.new(0, padding),
			PaddingRight = UDim.new(0, padding),
			PaddingTop = UDim.new(0, padding),
		}),
	}

	for index, ability in ipairs(props.abilities or {}) do
		rows["Ability" .. tostring(index)] = e(abilityRow, {
			detail = ability.detail,
			fillColor3 = ability.fillColor3,
			abilityName = ability.abilityName,
			keyCodeName = ability.keyCodeName,
			compact = compact,
			compactName = ability.compactName,
			layoutMode = props.layoutMode,
			layoutOrder = index,
			name = ability.name,
			onActivateAbility = props.onActivateAbility,
			progress = ability.progress,
			showKeybinds = props.showKeybinds,
			status = ability.status,
			statusColor3 = ability.statusColor3,
		})
	end

	if #(props.abilities or {}) == 0 then
		rows.Empty = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			LayoutOrder = 1,
			Size = UDim2.new(1, -16, 0, 24),
			Text = "No active fruit skills.",
			TextColor3 = THEME.TextSecondary,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		})
	end

	local listHeight = if #(props.abilities or {}) > 0
		then listInset + (#(props.abilities or {}) * rowHeight) + ((#(props.abilities or {}) - 1) * rowGap)
		else (compact and 24 or 44)
	local totalHeight = outerInset + topBarHeight + gap + listHeight + outerInset

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = THEME.PrimaryBg,
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = layout.position,
		Size = UDim2.fromOffset(layout.width, totalHeight),
		ZIndex = 30,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 14),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0.05,
			Thickness = 1.8,
		}),
		Glow = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Transparency = 0.72,
				Thickness = 4,
			}),
		}),
		Backdrop = e("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = THEME.FruitBackgroundImage,
			ScaleType = Enum.ScaleType.Stretch,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
		}),
		Overlay = e("Frame", {
			BackgroundColor3 = THEME.MenuOverlay,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
		}),
		TopBar = e("Frame", {
			BackgroundColor3 = THEME.HeaderBg,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(outerInset, outerInset),
			Size = UDim2.new(1, -(outerInset * 2), 0, topBarHeight),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Transparency = 0.12,
				Thickness = 1.2,
			}),
			Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(compact and 8 or 10, headerTitleY),
				Size = UDim2.new(1, compact and -16 or -20, 0, headerTitleHeight),
				Text = "DEVIL FRUIT",
				TextColor3 = THEME.GoldHighlight,
				TextSize = headerTitleTextSize,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			}),
			FruitName = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(compact and 8 or 10, fruitNameY),
				Size = UDim2.new(1, compact and -16 or -20, 0, fruitNameHeight),
				Text = props.fruitName,
				TextColor3 = THEME.TextMain,
				TextScaled = true,
				TextSize = fruitNameTextSize,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			}),
		}),
		List = e("Frame", {
			BackgroundColor3 = THEME.SectionBg,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(outerInset, outerInset + topBarHeight + gap),
			Size = UDim2.new(1, -(outerInset * 2), 0, listHeight),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Transparency = 0.14,
				Thickness = 1,
			}),
			Rows = e("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 3,
			}, rows),
		}),
	})
end

return CooldownHud
