local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local QuestConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushQuests"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local e = React.createElement

local SHELL = {
	CardBg = Color3.fromRGB(8, 8, 9),
	PanelBg = Color3.fromRGB(8, 8, 9),
	GoldBase = Color3.fromRGB(228, 190, 78),
	GoldHighlight = Color3.fromRGB(255, 224, 120),
	GoldSoft = Color3.fromRGB(255, 244, 200),
	GoldShadow = Color3.fromRGB(150, 112, 42),
	Cream = Color3.fromRGB(255, 222, 130),
	TextMain = Color3.fromRGB(235, 235, 235),
	TextMuted = Color3.fromRGB(180, 184, 190),
	TextShadow = Color3.fromRGB(0, 0, 0),
	Emerald = Color3.fromRGB(85, 255, 120),
	CloseFill = Color3.fromRGB(200, 0, 9),
	CloseFillSoft = Color3.fromRGB(235, 70, 78),
	DailyTint = Color3.fromRGB(245, 245, 245),
	WeeklyTint = Color3.fromRGB(176, 154, 255),
	SpecialTint = Color3.fromRGB(255, 214, 112),
	FinalTint = Color3.fromRGB(255, 122, 122),
	GlowImage = "rbxassetid://114516018211032",
	MapImage = "rbxassetid://120757950442747",
}

local BADGE_FONT = Font.new("rbxasset://fonts/families/SpecialElite.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local BODY = Enum.Font.FredokaOne

local REWARD_TINT = {
	Currency = Color3.fromRGB(85, 255, 120),
	Food = Color3.fromRGB(255, 96, 96),
}

local SILVER_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 247, 252)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(168, 172, 184)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(224, 227, 236)),
})

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

local function categoryTint(category, questId)
	if questId == "special_final_golden_legend" then
		return SHELL.FinalTint
	elseif category == "Weekly" then
		return SHELL.WeeklyTint
	elseif category == "Special" then
		return SHELL.SpecialTint
	end
	return SHELL.DailyTint
end

local function formatQuestProgress(quest)
	local progress = tonumber(quest.progress) or 0
	local target = tonumber(quest.target) or 1
	local objectiveType = tostring(quest.objectiveType or "")
	if objectiveType == "EarnBeli" or objectiveType == "EarnDoubloons" then
		return string.format("%s / %s", CurrencyUtil.formatCompactNumber(progress), CurrencyUtil.formatCompactNumber(target))
	end

	return string.format("%d / %d", progress, target)
end

local function goldStroke(thickness, transparency)
	return e("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = SHELL.GoldHighlight,
		Transparency = transparency or 0,
		Thickness = thickness or 1.5,
	}, {
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, SHELL.GoldHighlight),
				ColorSequenceKeypoint.new(1, SHELL.GoldShadow),
			}),
		}),
	})
end

local function tabButton(props)
	local active = props.active == true
	local category = props.category or {}
	local hovered, setHovered = React.useState(false)
	local claimableCount = math.max(0, tonumber(category.claimableCount) or 0)
	local fillColor = active and SHELL.GoldBase or (hovered and Color3.fromRGB(26, 26, 30) or SHELL.PanelBg)

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(TAB_WIDTH, 32),
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
			CornerRadius = UDim.new(0, 10),
		}),
		Outline = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = Color3.fromRGB(0, 0, 0),
			Thickness = 1.8,
			Transparency = 0,
		}, active and {
			Grad = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(0, 0, 0)),
			}),
		} or nil),
		Sheen = e("UIGradient", {
			Rotation = 90,
			Color = active
				and ColorSequence.new(Color3.fromRGB(255, 250, 222), Color3.fromRGB(216, 168, 64))
				or ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200)),
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
				Font = BODY,
				Size = UDim2.fromScale(1, 1),
				Text = tostring(category.label or category.id or ""),
				TextColor3 = active and Color3.new(1, 1, 1) or SHELL.TextMain,
				TextSize = 15,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = active and 0 or 0.4,
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
				Font = BODY,
				Size = UDim2.fromScale(1, 1),
				Text = tostring(math.min(99, claimableCount)),
				TextColor3 = Color3.fromRGB(20, 20, 20),
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
		BackgroundColor3 = Color3.fromRGB(20, 20, 22),
		BorderSizePixel = 0,
		Position = props.position,
		Size = props.size,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = SHELL.GoldShadow,
			Transparency = 0.3,
			Thickness = 1,
		}),
		Fill = e("Frame", {
			BackgroundColor3 = SHELL.GoldBase,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(percent, 1),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Gradient = e("UIGradient", {
				Rotation = 0,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(176, 132, 44)),
					ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 214, 110)),
					ColorSequenceKeypoint.new(0.85, Color3.fromRGB(255, 240, 180)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 252, 224)),
				}),
			}),
			Glow = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(255, 226, 130),
				Thickness = 2,
				Transparency = 0.45,
			}),
			Sheen = e("Frame", {
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 0.55,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 0.08),
				Size = UDim2.fromScale(1, 0.32),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 6),
				}),
				Fade = e("UIGradient", {
					Rotation = 90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.4),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
		}),
	})
end

local function rewardLine(quest)
	local rewards = quest.rewards or {}
	local rewardChildren = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
		Prefix = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = BODY,
			LayoutOrder = 0,
			Size = UDim2.fromScale(0, 1),
			Text = "Reward:",
			TextColor3 = SHELL.Cream,
			TextSize = 15,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.45,
		}),
	}

	local renderedRewards = 0
	for _, reward in ipairs(rewards) do
		local text = QuestConfig.FormatReward(reward)
		if text ~= "" then
			local kind = tostring(reward.Type or "")
			if kind == "Currency" then
				text = "$" .. text
			end

			renderedRewards += 1
			local isMaterial = kind == "Material"
			rewardChildren["Reward" .. tostring(renderedRewards)] = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Font = BODY,
				LayoutOrder = renderedRewards,
				Size = UDim2.fromScale(0, 1),
				Text = text,
				TextColor3 = isMaterial and Color3.new(1, 1, 1) or (REWARD_TINT[kind] or SHELL.Cream),
				TextSize = 15,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = 0,
			}, isMaterial and {
				Silver = e("UIGradient", {
					Rotation = 90,
					Color = SILVER_SEQUENCE,
				}),
			} or nil)
		end
	end

	if renderedRewards == 0 and tostring(quest.rewardText or "") ~= "" then
		rewardChildren.Fallback = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = BODY,
			LayoutOrder = 1,
			Size = UDim2.fromScale(0, 1),
			Text = tostring(quest.rewardText),
			TextColor3 = SHELL.Cream,
			TextSize = 15,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0,
		})
	end

	return rewardChildren
end

local function questCard(props)
	local quest = props.quest or {}
	local hovered, setHovered = React.useState(false)
	local claimable = quest.claimable == true
	local claimed = quest.claimed == true
	local buttonColor = if claimable then SHELL.GoldBase else SHELL.PanelBg
	local buttonTextColor = if claimed then SHELL.Emerald
		elseif claimable then Color3.new(1, 1, 1)
		else SHELL.TextMain
	local compact = props.compact == true
	local tint = categoryTint(quest.category, quest.id)

	return e("Frame", {
		Active = true,
		BackgroundColor3 = hovered and Color3.fromRGB(18, 18, 21) or SHELL.PanelBg,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.new(1, QUEST_CARD_WIDTH_OFFSET, 0, compact and 164 or QUEST_CARD_HEIGHT),
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
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY,
			Position = UDim2.fromOffset(18, 12),
			Size = UDim2.new(1, compact and -36 or -196, 0, 24),
			Text = tostring(quest.name or "Quest"),
			TextColor3 = tint,
			TextSize = 20,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.35,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Description = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY,
			Position = UDim2.fromOffset(18, 38),
			Size = UDim2.new(1, compact and -36 or -196, 0, compact and 44 or 34),
			Text = tostring(quest.description or ""),
			TextColor3 = SHELL.TextMuted,
			TextSize = 15,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.55,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),
		ProgressText = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY,
			Position = UDim2.fromOffset(18, compact and 88 or 78),
			Size = UDim2.fromOffset(120, 18),
			Text = formatQuestProgress(quest),
			TextColor3 = SHELL.TextMain,
			TextSize = 15,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.5,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Progress = e(progressBar, {
			progress = quest.progress,
			target = quest.target,
			position = UDim2.fromOffset(98, compact and 92 or 82),
			size = UDim2.new(1, compact and -116 or -282, 0, 11),
		}),
		Reward = e("Frame", {
			BackgroundTransparency = 1,
			ClipsDescendants = false,
			Position = UDim2.fromOffset(18, compact and 116 or 102),
			Size = UDim2.new(1, compact and -36 or -196, 0, 18),
		}, rewardLine(quest)),
		Status = e("TextButton", {
			AnchorPoint = compact and Vector2.new(0, 0.5) or Vector2.new(1, 1),
			AutoButtonColor = false,
			BackgroundColor3 = buttonColor,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Font = BODY,
			Position = compact and UDim2.fromOffset(18, 144) or UDim2.new(1, -16, 1, -14),
			Size = compact and UDim2.new(1, -36, 0, 34) or UDim2.fromOffset(122, 34),
			Text = statusText(quest),
			TextColor3 = buttonTextColor,
			TextSize = 15,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = claimable and 0 or 0.5,
			[React.Event.Activated] = function()
				if claimable and props.onClaim then
					props.onClaim(quest.category, quest.id)
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Outline = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(0, 0, 0),
				Thickness = 1.8,
				Transparency = 0,
			}, claimable and {
				Grad = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(0, 0, 0)),
				}),
			} or nil),
			Sheen = e("UIGradient", {
				Rotation = 90,
				Color = claimable
					and ColorSequence.new(Color3.fromRGB(255, 250, 222), Color3.fromRGB(216, 168, 64))
					or ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200)),
			}),
		}),
	})
end

local function QuestScreen(props)
	local rootRef = React.useRef(nil)
	local contentWidth, setContentWidth = React.useState(900)
	local state = props.state or {}
	local activeTab, setActiveTab = React.useState((state.categoryOrder and state.categoryOrder[1]) or "Daily")
	local activeCategory = findCategory(state, activeTab) or findCategory(state, "Daily")
	local categoryOrder = state.categoryOrder or DEFAULT_ORDER
	local compact = contentWidth < 640

	React.useEffect(function()
		local root = rootRef.current
		if not root then
			return nil
		end

		local function updateWidth()
			setContentWidth(root.AbsoluteSize.X)
		end

		updateWidth()
		local connection = root:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateWidth)
		return function()
			connection:Disconnect()
		end
	end, {})

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
			compact = compact,
			layoutOrder = index,
			onClaim = props.onClaimQuest,
			quest = quest,
		})
	end
	local listY = props.noticeText and 142 or 106
	local listHeightDelta = props.noticeText and -154 or -118

	return e("Frame", {
		ref = rootRef,
		BackgroundColor3 = SHELL.CardBg,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		Anchor = e("ImageLabel", {
			BackgroundTransparency = 1,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Image = "rbxassetid://87910431269362",
			Position = UDim2.fromScale(0.949, 0.895),
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.fromScale(0.075, 0.275),
			ZIndex = 4,
		}),
		Fill = e("Frame", {
			BackgroundColor3 = SHELL.CardBg,
			BackgroundTransparency = 0.12,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 18),
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
		TitleBadge = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = SHELL.CardBg,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(186, 42),
			ZIndex = 25,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0.5, 0),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = SHELL.GoldBase,
				Thickness = 2,
				Transparency = 0.15,
			}, {
				Gradient = e("UIGradient", {
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
				Text = "QUESTS",
				TextColor3 = SHELL.GoldBase,
				TextScaled = true,
				ZIndex = 26,
			}, {
				Constraint = e("UITextSizeConstraint", {
					MaxTextSize = 22,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 251, 230)),
						ColorSequenceKeypoint.new(0.47, Color3.fromRGB(255, 216, 107)),
						ColorSequenceKeypoint.new(1, Color3.fromRGB(95, 56, 2)),
					}),
				}),
				Outline = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
					Color = Color3.fromRGB(36, 18, 0),
					LineJoinMode = Enum.LineJoinMode.Miter,
					Thickness = 3,
					Transparency = 0.2,
				}),
			}),
		}),
		Close = e("TextButton", {
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
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 9),
			}),
			Outline = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(0, 0, 0),
				Thickness = 1.6,
				Transparency = 0,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, SHELL.CloseFillSoft),
					ColorSequenceKeypoint.new(0.5, Color3.fromRGB(214, 24, 34)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 0, 6)),
				}),
			}),
		}),
		Body = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(18, 58),
			Size = UDim2.new(1, -42, 1, -70),
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
				BackgroundColor3 = SHELL.PanelBg,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 42),
				Size = UDim2.new(1, 0, 0, 56),
				ZIndex = 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = goldStroke(1.5, 0),
				Label = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = BODY,
					Position = UDim2.fromOffset(16, 7),
					Size = UDim2.new(1, -32, 0, 20),
					Text = activeCategory and tostring(activeCategory.label) or "Quests",
					TextColor3 = SHELL.Cream,
					TextSize = 18,
					TextStrokeColor3 = SHELL.TextShadow,
					TextStrokeTransparency = 0.4,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Copy = e("TextLabel", {
					BackgroundTransparency = 1,
					Font = BODY,
					Position = UDim2.fromOffset(16, 30),
					Size = UDim2.new(1, -32, 0, 18),
					Text = activeCategory and string.format("%d/%d complete - %s", activeCategory.completedCount or 0, activeCategory.totalCount or 0, activeCategory.resetText or "") or "Loading quests...",
					TextColor3 = SHELL.TextMuted,
					TextSize = 14,
					TextStrokeColor3 = SHELL.TextShadow,
					TextStrokeTransparency = 0.6,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
			}),
			Notice = props.noticeText and e("TextLabel", {
				BackgroundColor3 = SHELL.PanelBg,
				BackgroundTransparency = 0,
				BorderSizePixel = 0,
				Font = BODY,
				Position = UDim2.fromOffset(0, 108),
				Size = UDim2.new(1, 0, 0, 36),
				Text = tostring(props.noticeText),
				TextColor3 = SHELL.GoldHighlight,
				TextSize = 15,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = 0.4,
				ZIndex = 4,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = goldStroke(1.2, 0),
			}) or nil,
			List = e("ScrollingFrame", {
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.fromOffset(0, 0),
				Position = UDim2.fromOffset(0, listY),
				ScrollBarImageColor3 = SHELL.GoldHighlight,
				ScrollBarThickness = 8,
				Size = UDim2.new(1, -8, 1, listHeightDelta),
				VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
				ZIndex = 4,
			}, listChildren),
		}),
	})
end

return QuestScreen
