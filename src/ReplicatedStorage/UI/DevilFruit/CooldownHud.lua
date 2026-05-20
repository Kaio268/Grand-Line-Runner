local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local e = React.createElement

local THEME = {
	FruitBackgroundImage = "rbxassetid://134053886107384",
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	HeaderBg = Color3.fromRGB(16, 35, 59),
	SectionBg = Color3.fromRGB(27, 46, 68),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	Ready = Color3.fromRGB(116, 255, 161),
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
	local compact = props.compact == true
	local rowHeight = compact and 28 or 58
	local keySize = compact and Vector2.new(20, 16) or Vector2.new(34, 24)

	return e("Frame", {
		BackgroundColor3 = THEME.SectionBg,
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, rowHeight),
		ZIndex = 3,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Transparency = 0.1,
			Thickness = 1,
		}),
		Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
		Key = e("TextLabel", {
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
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(compact and 30 or 52, compact and 3 or 8),
			Size = UDim2.new(1, compact and -76 or -136, 0, compact and 11 or 18),
			Text = props.name,
			TextColor3 = THEME.TextMain,
			TextSize = compact and 8 or 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}),
		Status = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(1, -10, 0, 8),
			Size = UDim2.fromOffset(compact and 42 or 72, compact and 11 or 18),
			Text = props.status,
			TextColor3 = props.statusColor3,
			TextSize = compact and 7 or 13,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 4,
		}),
		Detail = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Position = UDim2.fromOffset(compact and 30 or 52, compact and 15 or 29),
			Size = UDim2.new(1, compact and -38 or -68, 0, compact and 9 or 12),
			Text = props.detail,
			TextColor3 = THEME.TextSecondary,
			TextSize = compact and 7 or 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}),
		Bar = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = THEME.PrimaryBg,
			BorderSizePixel = 0,
			Position = UDim2.new(0, compact and 6 or 10, 1, compact and -4 or -8),
			Size = UDim2.new(1, compact and -12 or -20, 0, compact and 3 or 6),
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
				BackgroundColor3 = props.fillColor3,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(props.progress, 1),
				ZIndex = 5,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		}),
	})
end

local function CooldownHud(props)
	if props.visible ~= true then
		return e(React.Fragment)
	end

	local compact = props.compact == true

	local rows = {
		Layout = e("UIListLayout", {
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, compact and 6 or 8),
			PaddingLeft = UDim.new(0, compact and 6 or 8),
			PaddingRight = UDim.new(0, compact and 6 or 8),
			PaddingTop = UDim.new(0, compact and 6 or 8),
		}),
	}

	for index, ability in ipairs(props.abilities or {}) do
		rows["Ability" .. tostring(index)] = e(abilityRow, {
			detail = ability.detail,
			fillColor3 = ability.fillColor3,
			keyCodeName = ability.keyCodeName,
			compact = compact,
			layoutOrder = index,
			name = ability.name,
			progress = ability.progress,
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
		then (compact and 8 or 16) + (#(props.abilities or {}) * (compact and 28 or 58)) + ((#(props.abilities or {}) - 1) * (compact and 4 or 6))
		else (compact and 24 or 44)
	local topBarHeight = compact and 32 or 58
	local totalHeight = (compact and 5 or 10) + topBarHeight + (compact and 5 or 8) + listHeight + (compact and 5 or 10)

	return e("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = THEME.PrimaryBg,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = compact and UDim2.new(1, -8, 1, -54) or UDim2.new(1, -24, 1, -24),
		Size = UDim2.fromOffset(compact and 178 or 318, totalHeight),
		ZIndex = 30,
	}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = THEME.GoldHighlight,
			Thickness = 1.6,
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
			BackgroundTransparency = 0.42,
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
			BackgroundTransparency = 0.24,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(compact and 8 or 10, compact and 8 or 10),
			Size = UDim2.new(1, compact and -16 or -20, 0, topBarHeight),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = THEME.GoldHighlight,
				Thickness = 1.2,
			}),
			Gradient = gradient(THEME.SecondaryBg, THEME.PrimaryBg),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(10, compact and 3 or 4),
				Size = UDim2.new(1, -20, 0, 16),
				Text = "DEVIL FRUIT",
				TextColor3 = THEME.GoldHighlight,
				TextSize = compact and 7 or 12,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			}),
			FruitName = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(10, compact and 14 or 20),
				Size = UDim2.new(1, -20, 0, compact and 15 or 30),
				Text = props.fruitName,
				TextColor3 = THEME.TextMain,
				TextScaled = true,
				TextSize = compact and 12 or 28,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 3,
			}),
		}),
		List = e("Frame", {
			BackgroundColor3 = THEME.SectionBg,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(compact and 8 or 10, (compact and 8 or 10) + topBarHeight + 8),
			Size = UDim2.new(1, compact and -16 or -20, 0, listHeight),
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
