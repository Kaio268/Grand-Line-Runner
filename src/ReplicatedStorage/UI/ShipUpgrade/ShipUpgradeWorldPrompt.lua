local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))
local ShopTheme = require(ReplicatedStorage:WaitForChild("UI"):WaitForChild("Shop"):WaitForChild("Theme"))

local e = React.createElement

local THEME = {
	Panel = Color3.fromRGB(17, 29, 45),
	PanelTop = Color3.fromRGB(28, 45, 67),
	PanelBottom = Color3.fromRGB(12, 20, 34),
	Header = Color3.fromRGB(14, 31, 53),
	Section = Color3.fromRGB(26, 47, 70),
	SectionSoft = Color3.fromRGB(33, 55, 77),
	Stroke = Color3.fromRGB(224, 177, 65),
	StrokeSoft = Color3.fromRGB(101, 82, 47),
	Text = Color3.fromRGB(240, 240, 236),
	Muted = Color3.fromRGB(176, 190, 207),
	Gold = Color3.fromRGB(242, 209, 107),
	GoldDeep = Color3.fromRGB(146, 111, 31),
	Sea = Color3.fromRGB(91, 212, 255),
	Green = Color3.fromRGB(119, 222, 151),
	Red = Color3.fromRGB(235, 91, 102),
	Button = Color3.fromRGB(212, 175, 55),
	ButtonHover = Color3.fromRGB(236, 190, 94),
	ButtonDisabled = Color3.fromRGB(96, 113, 138),
	ButtonDisabledBottom = Color3.fromRGB(58, 72, 92),
	ButtonDisabledText = Color3.fromRGB(231, 238, 248),
	ButtonText = Color3.fromRGB(18, 22, 26),
}

local RESOURCE_ICON_IMAGES = {
	Beli = ShopTheme.Assets.BeliIcon,
	Rebirths = ShopTheme.Assets.RebirthIcon,
}

local MATERIAL_ICON_COLORS = {
	Timber = {
		Fill = Color3.fromRGB(159, 105, 59),
		FillAlt = Color3.fromRGB(106, 67, 38),
		Accent = Color3.fromRGB(224, 160, 88),
	},
	Iron = {
		Fill = Color3.fromRGB(165, 176, 191),
		FillAlt = Color3.fromRGB(83, 97, 116),
		Accent = Color3.fromRGB(219, 228, 238),
	},
	AncientTimber = {
		Fill = Color3.fromRGB(123, 88, 54),
		FillAlt = Color3.fromRGB(75, 51, 34),
		Accent = Color3.fromRGB(101, 232, 154),
	},
}

local function label(props)
	return e("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.Font or Enum.Font.Gotham,
		Position = props.Position,
		Size = props.Size,
		Text = props.Text or "",
		TextColor3 = props.Color or THEME.Text,
		TextSize = props.TextSize or 12,
		TextStrokeColor3 = props.StrokeColor,
		TextStrokeTransparency = props.StrokeTransparency,
		TextTruncate = props.TextTruncate,
		TextWrapped = props.TextWrapped,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		ZIndex = props.ZIndex or 3,
	})
end

local function materialIcon(props)
	local colors = MATERIAL_ICON_COLORS[props.Kind] or MATERIAL_ICON_COLORS.Timber
	local children = {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 3),
		}),
		Stroke = e("UIStroke", {
			Color = colors.Accent,
			Transparency = props.Ok and 0.38 or 0.18,
			Thickness = 1,
		}),
		SlatA = e("Frame", {
			BackgroundColor3 = colors.FillAlt,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.16, 0.25),
			Rotation = -12,
			Size = UDim2.fromScale(0.72, 0.18),
			ZIndex = props.ZIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 2),
			}),
		}),
		SlatB = e("Frame", {
			BackgroundColor3 = colors.Accent,
			BackgroundTransparency = props.Kind == "AncientTimber" and 0.05 or 0.34,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.22, 0.55),
			Rotation = -12,
			Size = UDim2.fromScale(0.62, 0.16),
			ZIndex = props.ZIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 2),
			}),
		}),
	}

	if props.Kind == "AncientTimber" then
		children.Glow = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = colors.Accent,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.72, 0.3),
			Size = UDim2.fromScale(0.22, 0.22),
			ZIndex = props.ZIndex + 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		})
	end

	return e("Frame", {
		BackgroundColor3 = colors.Fill,
		BorderSizePixel = 0,
		Position = props.Position,
		Size = props.Size,
		ZIndex = props.ZIndex,
	}, children)
end

local function resourceIcon(props)
	local image = RESOURCE_ICON_IMAGES[props.Kind]
	if image and image ~= "" then
		return e("ImageLabel", {
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = props.Ok and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 206, 216),
			Position = props.Position,
			ScaleType = Enum.ScaleType.Fit,
			Size = props.Size,
			ZIndex = props.ZIndex,
		})
	end

	return e(materialIcon, props)
end

local function statTile(props)
	local compact = props.Compact == true
	return e("Frame", {
		BackgroundColor3 = THEME.Section,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(0.5, -4, 1, 0),
		ZIndex = 3,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 7),
		}),
		Stroke = e("UIStroke", {
			Color = props.Accent or THEME.Stroke,
			Transparency = 0.48,
			Thickness = 1,
		}),
		Label = e(label, {
			Color = THEME.Muted,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(8, 3),
			Size = UDim2.new(1, -16, 0, 11),
			Text = props.Label,
			TextSize = compact and 8 or 9,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Value = e(label, {
			Color = props.Accent or THEME.Text,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(8, compact and 14 or 15),
			Size = UDim2.new(1, -16, 0, compact and 15 or 17),
			Text = props.Value,
			TextSize = compact and 11 or 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function costPill(props)
	local ok = props.Ok ~= false
	local text = tostring(props.Text or "")
	local iconSize = props.Compact and 11 or 12
	local hasIcon = props.Kind ~= nil and props.Kind ~= "Max"
	return e("Frame", {
		BackgroundColor3 = ok and THEME.SectionSoft or Color3.fromRGB(74, 42, 51),
		BackgroundTransparency = ok and 0.18 or 0.04,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = 3,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 6),
		}),
		Stroke = e("UIStroke", {
			Color = ok and THEME.StrokeSoft or THEME.Red,
			Transparency = ok and 0.62 or 0.26,
			Thickness = 1,
		}),
		Icon = hasIcon and e(resourceIcon, {
			Kind = props.Kind,
			Ok = ok,
			Position = UDim2.fromOffset(5, props.Compact and 1 or 1),
			Size = UDim2.fromOffset(iconSize, iconSize),
			ZIndex = 4,
		}) or nil,
		Text = e(label, {
			Color = ok and THEME.Text or THEME.Red,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(hasIcon and 20 or 6, 0),
			Size = UDim2.new(1, hasIcon and -24 or -12, 1, 0),
			Text = text,
			TextSize = props.Compact and 8 or 9,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function ShipUpgradeWorldPrompt(props)
	local view = props.View or {}
	local compact = props.Compact == true
	local hovered, setHovered = React.useState(false)
	local buttonEnabled = view.CanBuy == true and view.Pending ~= true
	local buttonFill = if buttonEnabled and hovered then THEME.ButtonHover elseif buttonEnabled then THEME.Button else THEME.ButtonDisabled
	local costChildren = {
		Grid = e("UIGridLayout", {
			CellPadding = UDim2.fromOffset(5, 3),
			CellSize = UDim2.new(0.5, -3, 0, compact and 14 or 14),
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, line in ipairs(view.CostLines or {}) do
		costChildren["Cost" .. tostring(index)] = e(costPill, {
			Compact = compact,
			LayoutOrder = index,
			Ok = line.Ok,
			Kind = line.Kind,
			Text = line.Text,
		})
	end

	return e("Frame", {
		BackgroundColor3 = THEME.Panel,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = THEME.Stroke,
			Transparency = 0.18,
			Thickness = 1.15,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, THEME.PanelTop),
				ColorSequenceKeypoint.new(1, THEME.PanelBottom),
			}),
			Rotation = 90,
		}),
		Header = e("Frame", {
			BackgroundColor3 = THEME.Header,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, compact and 38 or 42),
			ZIndex = 2,
		}, {
			BottomLine = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = THEME.Stroke,
				BackgroundTransparency = 0.22,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 1),
				ZIndex = 3,
			}),
			Eyebrow = e(label, {
				Color = THEME.Gold,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(12, 4),
				Size = UDim2.new(0.5, -12, 0, 10),
				Text = "SHIPYARD",
				TextSize = compact and 8 or 9,
			}),
			Title = e(label, {
				Color = THEME.Text,
				Font = Enum.Font.Cartoon,
				Position = UDim2.fromOffset(12, compact and 14 or 15),
				Size = UDim2.new(1, -104, 0, compact and 20 or 23),
				StrokeColor = THEME.GoldDeep,
				StrokeTransparency = 0.62,
				Text = tostring(view.Title or "Ship Upgrade"),
				TextSize = compact and 18 or 21,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Level = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = THEME.Section,
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -10, 0, 9),
				Size = UDim2.fromOffset(compact and 82 or 88, compact and 22 or 24),
				ZIndex = 3,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
				Stroke = e("UIStroke", {
					Color = THEME.Stroke,
					Transparency = 0.42,
					Thickness = 1,
				}),
				Text = e(label, {
					Color = THEME.Gold,
					Font = Enum.Font.GothamBold,
					Size = UDim2.fromScale(1, 1),
					Text = tostring(view.LevelText or ""),
					TextSize = compact and 9 or 10,
					TextXAlignment = Enum.TextXAlignment.Center,
				}),
			}),
		}),
		Description = e(label, {
			Color = THEME.Muted,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(12, compact and 45 or 49),
			Size = UDim2.new(1, -24, 0, compact and 18 or 20),
			Text = tostring(view.Description or ""),
			TextSize = compact and 9 or 10,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Stats = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, compact and 67 or 73),
			Size = UDim2.new(1, -24, 0, compact and 32 or 35),
			ZIndex = 3,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Slots = e(statTile, {
				Accent = THEME.Sea,
				Compact = compact,
				Label = "Normal Slots",
				LayoutOrder = 1,
				Value = tostring(view.SlotText or ""),
			}),
			Captain = e(statTile, {
				Accent = THEME.Gold,
				Compact = compact,
				Label = "Captain Bonus",
				LayoutOrder = 2,
				Value = tostring(view.CaptainText or ""),
			}),
		}),
		Costs = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(12, compact and 104 or 111),
			Size = UDim2.new(1, compact and -108 or -118, 0, compact and 50 or 50),
			ZIndex = 3,
		}, costChildren),
		Buy = e("TextButton", {
			Active = buttonEnabled,
			AutoButtonColor = false,
			BackgroundColor3 = buttonFill,
			BackgroundTransparency = buttonEnabled and 0.02 or 0.04,
			BorderSizePixel = 0,
			Position = UDim2.new(1, compact and -88 or -96, 1, compact and -42 or -46),
			Selectable = buttonEnabled,
			Size = UDim2.fromOffset(compact and 76 or 84, compact and 34 or 36),
			Text = tostring(view.ButtonText or "Buy"),
			TextColor3 = buttonEnabled and THEME.ButtonText or THEME.ButtonDisabledText,
			TextSize = compact and 13 or 14,
			TextStrokeColor3 = Color3.fromRGB(14, 21, 32),
			TextStrokeTransparency = buttonEnabled and 1 or 0.72,
			Font = Enum.Font.GothamBold,
			ZIndex = 4,
			[React.Event.Activated] = function()
				if buttonEnabled and props.OnBuy then
					props.OnBuy()
				end
			end,
			[React.Event.MouseEnter] = function()
				setHovered(true)
			end,
			[React.Event.MouseLeave] = function()
				setHovered(false)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 9),
			}),
			Stroke = e("UIStroke", {
				Color = buttonEnabled and Color3.fromRGB(255, 255, 255) or THEME.Muted,
				Transparency = buttonEnabled and 0.78 or 0.48,
				Thickness = 1,
			}),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, buttonFill),
					ColorSequenceKeypoint.new(1, buttonEnabled and THEME.GoldDeep or THEME.ButtonDisabledBottom),
				}),
				Rotation = 90,
			}),
		}),
	})
end

return ShipUpgradeWorldPrompt
