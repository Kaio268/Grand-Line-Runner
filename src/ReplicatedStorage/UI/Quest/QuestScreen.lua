local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement
local SHELL = {
	MenuBackgroundImage = "rbxassetid://120757950442747",
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	MenuOverlayTransparency = 0.45,
	HeaderBackground = Color3.fromRGB(16, 35, 59),
	HeaderTransparency = 0.25,
	SectionBackground = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	CloseFill = Color3.fromRGB(200, 0, 9),
	CloseFillSoft = Color3.fromRGB(235, 70, 78),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextShadow = Color3.fromRGB(9, 17, 27),
}

local DEFAULT_ORDER = { "Daily", "Weekly", "Special" }
local TAB_WIDTH = 118
local QUEST_CARD_HEIGHT = 132
local QUEST_CARD_WIDTH_OFFSET = -14

local function findCategory(state, categoryId)
	for _, category in ipairs((state and state.categories) or {}) do
		if category.id == categoryId then
			return category
		end
	end

	return (state and state.categories and state.categories[1]) or nil
end

local function statusText(quest)
	if quest.claimed then
		return "Completed"
	elseif quest.claimable then
		return "Claim"
	elseif quest.completed then
		return "Ready"
	end

	return "In Progress"
end

local function tabButton(props)
	local active = props.active == true
	local category = props.category or {}
	local hovered, setHovered = React.useState(false)
	local claimableCount = math.max(0, tonumber(category.claimableCount) or 0)
	local fillColor = active and Theme.Palette.TabRewardFill or (hovered and SHELL.SectionHover or SHELL.HeaderBackground)
	local textColor = active and SHELL.GoldHighlight or Theme.Palette.Text

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(TAB_WIDTH, 30),
		Text = "",
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			if props.onSelect then
				props.onSelect(category.id)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = SHELL.GoldHighlight,
			Transparency = 0,
			Thickness = 1.35,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, active and Theme.Palette.TabRewardFill or SHELL.SectionBackground),
				ColorSequenceKeypoint.new(1, fillColor),
			}),
		}),
		TitleWrap = e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, claimableCount > 0 and 28 or 8),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Size = UDim2.fromScale(1, 1),
				Text = tostring(category.label or category.id or ""),
				TextColor3 = textColor,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
		}),
		Badge = claimableCount > 0 and e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = SHELL.GoldHighlight,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(21, 19),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Text = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Size = UDim2.fromScale(1, 1),
				Text = tostring(math.min(99, claimableCount)),
				TextColor3 = Theme.Palette.Ink,
				TextSize = 12,
			}),
		}) or nil,
	})
end

local function progressBar(props)
	local progress = math.max(0, tonumber(props.progress) or 0)
	local target = math.max(1, tonumber(props.target) or 1)
	local percent = math.clamp(progress / target, 0, 1)

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.ProgressTrack,
		BorderSizePixel = 0,
		Position = props.position,
		Size = props.size,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.ProgressStroke,
			Transparency = 0.18,
			Thickness = 1,
		}),
		Fill = e("Frame", {
			BackgroundColor3 = props.fillColor or Theme.Palette.ProgressFill,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(percent, 1),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Gradient = e("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Theme.Palette.ProgressFill),
					ColorSequenceKeypoint.new(1, Theme.Palette.Cyan),
				}),
			}),
		}),
	})
end

local function questCard(props)
	local quest = props.quest or {}
	local hovered, setHovered = React.useState(false)
	local claimable = quest.claimable == true
	local claimed = quest.claimed == true
	local buttonColor = if claimable then Theme.Palette.TabRewardFill else SHELL.HeaderBackground
	local buttonTextColor = if claimed then Theme.Palette.Emerald
		elseif claimable then SHELL.GoldHighlight
		else Theme.Palette.Text

	return e("Frame", {
		Active = true,
		BackgroundColor3 = hovered and SHELL.SectionHover or SHELL.SectionBackground,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, QUEST_CARD_WIDTH_OFFSET, 0, QUEST_CARD_HEIGHT),
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
			Color = SHELL.GoldHighlight,
			Transparency = 0,
			Thickness = 1.5,
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(18, 12),
			Size = UDim2.new(1, -196, 0, 24),
			Text = tostring(quest.name or "Quest"),
			TextColor3 = Theme.Palette.Text,
			TextSize = 32,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextScaled = true,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(18, 38),
			Size = UDim2.new(1, -196, 0, 34),
			Text = tostring(quest.description or ""),
			TextColor3 = Theme.Palette.Muted,
			TextSize = 15,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		ProgressText = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(18, 78),
			Size = UDim2.fromOffset(120, 18),
			Text = string.format("%d / %d", tonumber(quest.progress) or 0, tonumber(quest.target) or 1),
			TextColor3 = Theme.Palette.Text,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Progress = e(progressBar, {
			progress = quest.progress,
			target = quest.target,
			position = UDim2.fromOffset(98, 82),
			size = UDim2.new(1, -282, 0, 11),
		}),
		Reward = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(18, 102),
			Size = UDim2.new(1, -196, 0, 18),
			Text = "Reward: " .. tostring(quest.rewardText or ""),
			TextColor3 = Theme.Palette.Gold,
			TextSize = 14,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Status = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			AutoButtonColor = false,
			BackgroundColor3 = buttonColor,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -16, 1, -14),
			Size = UDim2.fromOffset(122, 34),
			Text = statusText(quest),
			TextColor3 = buttonTextColor,
			TextSize = 14,
			Font = Theme.Fonts.Display,
			[React.Event.Activated] = function()
				if claimable and props.onClaim then
					props.onClaim(quest.category, quest.id)
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
			Stroke = e("UIStroke", {
				Color = SHELL.GoldHighlight,
				Transparency = 0,
				Thickness = 1.2,
			}),
		}),
	})
end

local function QuestScreen(props)
	local state = props.state or {}
	local activeTab, setActiveTab = React.useState((state.categoryOrder and state.categoryOrder[1]) or "Daily")
	local activeCategory = findCategory(state, activeTab) or findCategory(state, "Daily")
	local categoryOrder = state.categoryOrder or DEFAULT_ORDER

	local tabChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, categoryId in ipairs(categoryOrder) do
		local category = findCategory(state, categoryId)
		if category then
			tabChildren["Tab" .. categoryId] = e(tabButton, {
				active = activeCategory and activeCategory.id == category.id,
				category = category,
				layoutOrder = index,
				onSelect = setActiveTab,
			})
		end
	end

	local listChildren = {
		List = e("UIListLayout", {
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingBottom = UDim.new(0, 14),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
			PaddingTop = UDim.new(0, 6),
		}),
	}
	for index, quest in ipairs((activeCategory and activeCategory.quests) or {}) do
		listChildren["Quest" .. tostring(quest.id)] = e(questCard, {
			layoutOrder = index,
			onClaim = props.onClaimQuest,
			quest = quest,
		})
	end
	local listY = props.noticeText and 150 or 118
	local listHeightDelta = props.noticeText and -162 or -130

	return e("Frame", {
		BackgroundColor3 = SHELL.MenuOverlay,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		BaseTexture = e("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = SHELL.MenuBackgroundImage,
			ImageTransparency = 0,
			ScaleType = Enum.ScaleType.Stretch,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 16),
			}),
		}),
		Overlay = e("Frame", {
			BackgroundColor3 = SHELL.MenuOverlay,
			BackgroundTransparency = SHELL.MenuOverlayTransparency,
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
				Color = SHELL.GoldHighlight,
				Thickness = 3,
				Transparency = 0,
			}),
		}),
		Header = e("Frame", {
			BackgroundColor3 = SHELL.HeaderBackground,
			BackgroundTransparency = SHELL.HeaderTransparency,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(12, 10),
			Size = UDim2.new(1, -24, 0, 54),
			ZIndex = 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = SHELL.GoldHighlight,
				Thickness = 1.5,
				Transparency = 0,
			}),
			Title = e("TextLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(260, 32),
				Text = "QUESTS",
				TextColor3 = SHELL.TextMain,
				TextScaled = true,
				TextSize = 30,
				TextStrokeColor3 = SHELL.GoldShadow,
				TextStrokeTransparency = 0.45,
				ZIndex = 4,
			}),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = SHELL.CloseFill,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(34, 34),
				Text = "X",
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = 0.4,
				ZIndex = 4,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 8),
				}),
				Stroke = e("UIStroke", {
					Color = SHELL.GoldShadow,
					Thickness = 1,
					Transparency = 0.1,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, SHELL.CloseFillSoft),
						ColorSequenceKeypoint.new(1, SHELL.CloseFill),
					}),
				}),
			}),
		}),
		Body = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18, 116),
			Size = UDim2.new(1, -42, 1, -126),
			ZIndex = 3,
		}, {
			Tabs = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Position = UDim2.fromScale(0.5, 0),
				Size = UDim2.fromOffset(380, 34),
				ZIndex = 4,
			}, tabChildren),
			Summary = e("Frame", {
				BackgroundColor3 = SHELL.SectionBackground,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 42),
				Size = UDim2.new(1, 0, 0, 56),
				ZIndex = 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = e("UIStroke", {
					Color = SHELL.GoldHighlight,
					Transparency = 0,
					Thickness = 1.5,
				}),
				Label = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Display,
					Position = UDim2.fromOffset(16, 7),
					Size = UDim2.new(1, -32, 0, 18),
					Text = activeCategory and tostring(activeCategory.label) or "Quests",
					TextColor3 = Theme.Palette.Text,
					TextSize = 18,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Copy = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Body,
					Position = UDim2.fromOffset(16, 30),
					Size = UDim2.new(1, -32, 0, 16),
					Text = activeCategory and string.format("%d/%d complete - %s", activeCategory.completedCount or 0, activeCategory.totalCount or 0, activeCategory.resetText or "") or "Loading quests...",
					TextColor3 = Theme.Palette.Muted,
					TextSize = 13,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}),
			Notice = props.noticeText and e("TextLabel", {
				BackgroundColor3 = Theme.Palette.TabRewardFill,
				BackgroundTransparency = 0.2,
				BorderSizePixel = 0,
				Font = Theme.Fonts.BodyStrong,
				Position = UDim2.fromOffset(0, 108),
				Size = UDim2.new(1, 0, 0, 32),
				Text = tostring(props.noticeText),
				TextColor3 = SHELL.GoldHighlight,
				TextSize = 13,
				ZIndex = 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = e("UIStroke", {
					Color = SHELL.GoldHighlight,
					Thickness = 1.2,
					Transparency = 0,
				}),
			}),
			List = e("ScrollingFrame", {
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromOffset(0, 0),
				Position = UDim2.fromOffset(0, listY),
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
				ScrollBarImageColor3 = SHELL.GoldHighlight,
				ScrollBarThickness = 8,
				Size = UDim2.new(1, -8, 1, listHeightDelta),
				ZIndex = 4,
			}, listChildren),
		}),
	})
end

return QuestScreen
