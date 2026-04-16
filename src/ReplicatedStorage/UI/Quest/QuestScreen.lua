local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local DEFAULT_ORDER = { "Daily", "Weekly", "Special" }

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
	local claimableCount = math.max(0, tonumber(category.claimableCount) or 0)

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = active and Theme.Palette.HeaderBottom or Theme.Palette.TabFill,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(116, 30),
		Text = "",
		[React.Event.Activated] = function()
			if props.onSelect then
				props.onSelect(category.id)
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = active and Theme.Palette.Cyan or Theme.Palette.BorderSoft,
			Transparency = active and 0.02 or 0.18,
			Thickness = 1,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(12, 0),
			Size = UDim2.new(1, claimableCount > 0 and -40 or -24, 1, 0),
			Text = tostring(category.label or category.id or ""),
			TextColor3 = active and Theme.Palette.Text or Color3.fromRGB(229, 237, 255),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Badge = claimableCount > 0 and e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Palette.TabRewardAccent,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(22, 20),
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
			Size = UDim2.new(percent, 0, 1, 0),
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
	local claimable = quest.claimable == true
	local claimed = quest.claimed == true
	local buttonColor = if claimed then Theme.Palette.Locked
		elseif claimable then Theme.Palette.TabRewardAccent
		else Theme.Palette.TabFillHover
	local buttonTextColor = if claimable then Theme.Palette.Ink else Theme.Palette.Muted

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Panel,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, 0, 0, 118),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = claimable and Theme.Palette.TabRewardAccent or Theme.Palette.BorderSoft,
			Transparency = claimable and 0.04 or 0.18,
			Thickness = claimable and 1.4 or 1,
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(18, 12),
			Size = UDim2.new(1, -170, 0, 20),
			Text = tostring(quest.name or "Quest"),
			TextColor3 = Theme.Palette.Text,
			TextSize = 18,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Body,
			Position = UDim2.fromOffset(18, 36),
			Size = UDim2.new(1, -176, 0, 34),
			Text = tostring(quest.description or ""),
			TextColor3 = Theme.Palette.Muted,
			TextSize = 13,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		ProgressText = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(18, 74),
			Size = UDim2.fromOffset(120, 18),
			Text = string.format("%d / %d", tonumber(quest.progress) or 0, tonumber(quest.target) or 1),
			TextColor3 = Theme.Palette.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Progress = e(progressBar, {
			progress = quest.progress,
			target = quest.target,
			position = UDim2.new(0, 96, 0, 78),
			size = UDim2.new(1, -256, 0, 10),
		}),
		Reward = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(18, 96),
			Size = UDim2.new(1, -178, 0, 16),
			Text = "Reward: " .. tostring(quest.rewardText or ""),
			TextColor3 = Theme.Palette.Gold,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Status = e("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			AutoButtonColor = false,
			BackgroundColor3 = buttonColor,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -16, 1, -16),
			Size = UDim2.fromOffset(128, 34),
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
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = claimable and Theme.Palette.Gold or Theme.Palette.BorderSoft,
				Transparency = claimable and 0.02 or 0.28,
				Thickness = 1,
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
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
			PaddingTop = UDim.new(0, 4),
		}),
	}
	for index, quest in ipairs((activeCategory and activeCategory.quests) or {}) do
		listChildren["Quest" .. tostring(quest.id)] = e(questCard, {
			layoutOrder = index,
			onClaim = props.onClaimQuest,
			quest = quest,
		})
	end

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Board,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.BorderSoft,
			Transparency = 0.05,
			Thickness = 1,
		}),
		Header = e("Frame", {
			BackgroundColor3 = Theme.Palette.HeaderMid,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 82),
		}, {
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Theme.Palette.HeaderStart),
					ColorSequenceKeypoint.new(0.48, Theme.Palette.HeaderMid),
					ColorSequenceKeypoint.new(1, Theme.Palette.HeaderEnd),
				}),
			}),
			Brand = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Position = UDim2.fromOffset(16, 10),
				Size = UDim2.fromOffset(200, 14),
				Text = "GRAND LINE RUSH",
				TextColor3 = Theme.Palette.Text,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(16, 25),
				Size = UDim2.fromOffset(240, 34),
				Text = "Quests",
				TextColor3 = Theme.Palette.Text,
				TextSize = 30,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Tabs = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				Position = UDim2.new(0.5, 0, 0, 43),
				Size = UDim2.fromOffset(364, 30),
			}, tabChildren),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Palette.CloseFill,
				BorderSizePixel = 0,
				Font = Theme.Fonts.Display,
				Position = UDim2.new(1, -12, 0, 12),
				Size = UDim2.fromOffset(34, 34),
				Text = "X",
				TextColor3 = Theme.Palette.Text,
				TextSize = 16,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 7),
				}),
				Stroke = e("UIStroke", {
					Color = Theme.Palette.CloseStroke,
					Transparency = 0.02,
				}),
			}),
		}),
		Summary = e("Frame", {
			BackgroundColor3 = Theme.Palette.Section,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(18, 96),
			Size = UDim2.new(1, -36, 0, 54),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.BorderSoft,
				Transparency = 0.18,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(16, 7),
				Size = UDim2.new(1, -32, 0, 18),
				Text = activeCategory and tostring(activeCategory.label) or "Quests",
				TextColor3 = Theme.Palette.Text,
				TextSize = 17,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Copy = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(16, 29),
				Size = UDim2.new(1, -32, 0, 16),
				Text = activeCategory and string.format("%d/%d complete - %s", activeCategory.completedCount or 0, activeCategory.totalCount or 0, activeCategory.resetText or "") or "Loading quests...",
				TextColor3 = Theme.Palette.Muted,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),
		Notice = props.noticeText and e("TextLabel", {
			BackgroundColor3 = Theme.Palette.TabRewardFill,
			BorderSizePixel = 0,
			Font = Theme.Fonts.BodyStrong,
			Position = UDim2.fromOffset(18, 158),
			Size = UDim2.new(1, -36, 0, 28),
			Text = tostring(props.noticeText),
			TextColor3 = Theme.Palette.Gold,
			TextSize = 13,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
		}) or nil,
		List = e("ScrollingFrame", {
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, 0),
			Position = UDim2.fromOffset(18, props.noticeText and 196 or 164),
			ScrollBarImageColor3 = Theme.Palette.Cyan,
			ScrollBarThickness = 6,
			Size = UDim2.new(1, -36, 1, props.noticeText and -214 or -182),
		}, listChildren),
	})
end

return QuestScreen
