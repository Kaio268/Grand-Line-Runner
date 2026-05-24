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
	Rebirth = ShopTheme.Assets.RebirthIcon,
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
		Fill = Color3.fromRGB(113, 48, 176),
		FillAlt = Color3.fromRGB(62, 30, 103),
		Accent = Color3.fromRGB(218, 118, 255),
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
		AnchorPoint = props.AnchorPoint,
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
			AnchorPoint = props.AnchorPoint,
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

local function crewSlotsIcon(props)
	local accent = props.Accent or THEME.Sea
	local zIndex = props.ZIndex or 4
	return e("Frame", {
		BackgroundTransparency = 1,
		Position = props.Position,
		Size = props.Size,
		ZIndex = zIndex,
	}, {
		CenterHead = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.3),
			Size = UDim2.fromScale(0.24, 0.24),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		LeftHead = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.24, 0.44),
			Size = UDim2.fromScale(0.18, 0.18),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		RightHead = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.76, 0.44),
			Size = UDim2.fromScale(0.18, 0.18),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Body = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.68),
			Size = UDim2.fromScale(0.7, 0.24),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
		}),
	})
end

local function captainBonusIcon(props)
	local accent = props.Accent or THEME.Gold
	local zIndex = props.ZIndex or 4
	return e("Frame", {
		BackgroundTransparency = 1,
		Position = props.Position,
		Size = props.Size,
		ZIndex = zIndex,
	}, {
		Diamond = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Rotation = 45,
			Size = UDim2.fromScale(0.46, 0.46),
			ZIndex = zIndex + 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
		Glow = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = accent,
			BackgroundTransparency = 0.72,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.8),
			ZIndex = zIndex,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
	})
end

local function statCard(props)
	local accent = props.Accent or THEME.Stroke
	local icon = if props.Icon == "Captain"
		then e(captainBonusIcon, {
			Accent = accent,
			Position = UDim2.fromOffset(28, 32),
			Size = UDim2.fromOffset(44, 44),
			ZIndex = 5,
		})
		else e(crewSlotsIcon, {
			Accent = accent,
			Position = UDim2.fromOffset(24, 33),
			Size = UDim2.fromOffset(52, 42),
			ZIndex = 5,
		})

	return e("Frame", {
		BackgroundColor3 = THEME.Section,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		Size = UDim2.new(0.5, -8, 1, 0),
		ZIndex = 3,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = accent,
			Transparency = 0.36,
			Thickness = 1.4,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, THEME.SectionSoft),
				ColorSequenceKeypoint.new(1, THEME.PanelBottom),
			}),
			Rotation = 90,
		}),
		Icon = icon,
		Label = e(label, {
			Color = accent,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(96, 18),
			Size = UDim2.new(1, -116, 0, 24),
			Text = props.Label,
			TextSize = 18,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Value = e(label, {
			Color = THEME.Text,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(96, 45),
			Size = UDim2.new(1, -116, 0, 34),
			Text = props.Value,
			TextSize = 27,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
	})
end

local function requirementCard(props)
	local ok = props.Ok ~= false
	local isMax = props.Kind == "Max"
	local amountColor = if isMax then THEME.Green elseif ok then THEME.Text else THEME.Red
	local strokeColor = if isMax then THEME.Green elseif ok then THEME.StrokeSoft else THEME.Red

	return e("Frame", {
		BackgroundColor3 = ok and THEME.Section or Color3.fromRGB(44, 32, 44),
		BackgroundTransparency = ok and 0.1 or 0.02,
		BorderSizePixel = 0,
		LayoutOrder = props.LayoutOrder,
		ZIndex = 3,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = strokeColor,
			Transparency = ok and 0.48 or 0.22,
			Thickness = 1.2,
		}),
		Icon = if isMax
			then e(label, {
				Color = THEME.Green,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.fromOffset(0, 11),
				Size = UDim2.new(1, 0, 0, 24),
				Text = "OK",
				TextSize = 16,
				TextXAlignment = Enum.TextXAlignment.Center,
			})
			else e(resourceIcon, {
				Kind = props.Kind,
				Ok = ok,
				AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0, 8),
				Size = UDim2.fromOffset(28, 28),
				ZIndex = 4,
			}),
		Name = e(label, {
			Color = THEME.Text,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(6, 36),
			Size = UDim2.new(1, -12, 0, 22),
			Text = tostring(props.Label or props.Kind or ""),
			TextSize = 11,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
		Amount = e(label, {
			Color = amountColor,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(6, 58),
			Size = UDim2.new(1, -12, 0, 16),
			Text = tostring(props.Text or ""),
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

local function ShipUpgradeWorldPrompt(props)
	local view = props.View or {}
	local hovered, setHovered = React.useState(false)
	local buttonEnabled = view.CanBuy == true and view.Pending ~= true
	local buttonFill = if buttonEnabled and hovered then THEME.ButtonHover elseif buttonEnabled then THEME.Button else THEME.ButtonDisabled
	local requirements = view.Requirements or view.CostLines or {}
	local requirementChildren = {
		Grid = e("UIGridLayout", {
			CellPadding = UDim2.fromOffset(10, 0),
			CellSize = UDim2.new(0.2, -8, 1, 0),
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
		}),
	}

	for index, line in ipairs(requirements) do
		requirementChildren["Requirement" .. tostring(index)] = e(requirementCard, {
			Kind = line.Kind,
			Label = line.Label,
			LayoutOrder = index,
			Ok = line.Ok,
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
			CornerRadius = UDim.new(0, 16),
		}),
		Stroke = e("UIStroke", {
			Color = THEME.Stroke,
			Transparency = 0.08,
			Thickness = 1.5,
		}),
		Gradient = e("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(17, 29, 47)),
				ColorSequenceKeypoint.new(0.48, Color3.fromRGB(9, 18, 31)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(6, 13, 22)),
			}),
			Rotation = 90,
		}),
		Header = e("Frame", {
			BackgroundColor3 = THEME.Header,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 112),
			ZIndex = 2,
		}, {
			BottomLine = e("Frame", {
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = THEME.Stroke,
				BackgroundTransparency = 0.16,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 1),
				Size = UDim2.new(1, 0, 0, 2),
				ZIndex = 3,
			}),
			Eyebrow = e(label, {
				Color = THEME.Gold,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromOffset(34, 26),
				Size = UDim2.new(0.5, -34, 0, 20),
				Text = "SHIPYARD",
				TextSize = 17,
			}),
			Title = e(label, {
				Color = THEME.Text,
				Font = Enum.Font.GothamBlack,
				Position = UDim2.fromOffset(34, 51),
				Size = UDim2.new(1, -270, 0, 46),
				StrokeColor = Color3.fromRGB(0, 0, 0),
				StrokeTransparency = 0.82,
				Text = tostring(view.Title or "Ship Upgrade"),
				TextSize = 39,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Level = e("Frame", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundColor3 = Color3.fromRGB(17, 27, 42),
				BackgroundTransparency = 0.02,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -34, 0, 30),
				Size = UDim2.fromOffset(164, 50),
				ZIndex = 3,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 999),
				}),
				Stroke = e("UIStroke", {
					Color = THEME.Stroke,
					Transparency = 0.02,
					Thickness = 1.5,
				}),
				Text = e(label, {
					Color = THEME.Gold,
					Font = Enum.Font.GothamBlack,
					Size = UDim2.fromScale(1, 1),
					Text = tostring(view.LevelText or ""),
					TextSize = 23,
					TextXAlignment = Enum.TextXAlignment.Center,
				}),
			}),
		}),
		Description = e(label, {
			Color = THEME.Text,
			Font = Enum.Font.GothamMedium,
			Position = UDim2.fromOffset(34, 128),
			Size = UDim2.new(1, -68, 0, 44),
			Text = tostring(view.Description or ""),
			TextSize = 19,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		Stats = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(34, 183),
			Size = UDim2.new(1, -68, 0, 94),
			ZIndex = 3,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 16),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Slots = e(statCard, {
				Accent = THEME.Sea,
				Icon = "Slots",
				Label = "Normal Slots",
				LayoutOrder = 1,
				Value = tostring(view.SlotText or ""),
			}),
			Captain = e(statCard, {
				Accent = THEME.Gold,
				Icon = "Captain",
				Label = "Captain Bonus",
				LayoutOrder = 2,
				Value = tostring(view.CaptainText or ""),
			}),
		}),
		RequirementTitle = e(label, {
			Color = THEME.Muted,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(34, 297),
			Size = UDim2.new(1, -68, 0, 23),
			Text = "REQUIREMENTS",
			TextSize = 16,
		}),
		RequirementDivider = e("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 321),
			Size = UDim2.new(1, 0, 0, 1),
			ZIndex = 2,
		}),
		Requirements = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(34, 337),
			Size = UDim2.new(1, -282, 0, 76),
			ZIndex = 3,
		}, requirementChildren),
		Buy = e("TextButton", {
			Active = buttonEnabled,
			AutoButtonColor = false,
			BackgroundColor3 = buttonFill,
			BackgroundTransparency = buttonEnabled and 0.02 or 0.08,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -224, 0, 337),
			Selectable = buttonEnabled,
			Size = UDim2.fromOffset(190, 76),
			Text = tostring(view.ButtonText or "Upgrade Ship"),
			TextColor3 = buttonEnabled and THEME.ButtonText or THEME.ButtonDisabledText,
			TextSize = 18,
			TextStrokeColor3 = Color3.fromRGB(14, 21, 32),
			TextStrokeTransparency = buttonEnabled and 1 or 0.72,
			TextWrapped = true,
			Font = Enum.Font.GothamBlack,
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
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = buttonEnabled and Color3.fromRGB(255, 255, 255) or THEME.Muted,
				Transparency = buttonEnabled and 0.72 or 0.48,
				Thickness = 1.2,
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
