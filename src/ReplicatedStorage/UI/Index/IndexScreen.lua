local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local IndexData = require(script.Parent:WaitForChild("IndexData"))
local IndexGrid = require(script.Parent:WaitForChild("Components"):WaitForChild("IndexGrid"))
local RewardsPanel = require(script.Parent:WaitForChild("Components"):WaitForChild("RewardsPanel"))

local e = React.createElement

local SHELL = {
	IndexBackgroundImage = "rbxassetid://75192947200012",
	FruitsBackgroundImage = "rbxassetid://134053886107384",
	RewardsBackgroundImage = "rbxassetid://130097582075753",
	CardBg = Color3.fromRGB(8, 8, 9),
	MenuOverlay = Color3.fromRGB(8, 8, 9),
	MenuOverlayTransparency = 0.12,
	HeaderBackground = Color3.fromRGB(8, 8, 9),
	HeaderTransparency = 0.1,
	SectionBackground = Color3.fromRGB(20, 20, 24),
	SectionHover = Color3.fromRGB(30, 30, 35),
	GoldBase = Color3.fromRGB(228, 190, 78),
	GoldHighlight = Color3.fromRGB(255, 224, 120),
	GoldShadow = Color3.fromRGB(150, 112, 42),
	CloseFill = Color3.fromRGB(200, 0, 9),
	CloseFillSoft = Color3.fromRGB(235, 70, 78),
	TextMain = Color3.fromRGB(235, 235, 235),
	TextShadow = Color3.fromRGB(0, 0, 0),
}

local BADGE_FONT = Font.new("rbxasset://fonts/families/SpecialElite.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
local BODY = Enum.Font.FredokaOne

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

local function titleBadge(labelText, width)
	return e("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = SHELL.CardBg,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.fromOffset(width or 208, 42),
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
			Text = labelText,
			TextColor3 = SHELL.GoldBase,
			TextScaled = true,
			ZIndex = 26,
		}, {
			Constraint = e("UITextSizeConstraint", {
				MaxTextSize = 22,
			}),
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
	})
end

local function closeButton(onClose)
	return e("TextButton", {
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
		[React.Event.Activated] = function()
			if onClose then
				onClose()
			end
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 9),
		}),
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
	})
end

local DEBUG_INDEX_UI_PERF = false

local function debugUiLog(message)
	if DEBUG_INDEX_UI_PERF then
		print("[IndexUIPerf] " .. message)
	end
end

local function copySetWith(source, key)
	local result = table.clone(source or {})
	result[key] = true
	return result
end

local function filterUnits(units, categoryId)
	local filtered = {}

	for _, unit in ipairs(units) do
		if unit.category == categoryId then
			filtered[#filtered + 1] = unit
		end
	end

	return filtered
end

local function tabButton(props)
	local active = props.active == true
	local tab = props.tab or {}
	local isRewardTab = tab.id == "rewards"
	local hovered, setHovered = React.useState(false)
	local countText = isRewardTab and (props.claimableCount or 0) > 0 and tostring(props.claimableCount) or nil
	local buttonWidth = isRewardTab and 120 or 116
	local fillColor = active and SHELL.GoldBase or (hovered and Color3.fromRGB(26, 26, 30) or SHELL.CardBg)

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(buttonWidth, 30),
		Text = "",
		ZIndex = 8,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			props.onTabChange(tab.id)
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
			ZIndex = 9,
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, countText and 28 or 8),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Size = UDim2.fromScale(1, 1),
				Text = tostring(tab.label or ""),
				TextColor3 = active and Color3.new(1, 1, 1) or SHELL.TextMain,
				TextSize = 14,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = active and 0 or 0.4,
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 9,
			}),
		}),
		Count = countText and e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = SHELL.GoldHighlight,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -7, 0.5, 0),
			Size = UDim2.fromOffset(20, 18),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Text = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Size = UDim2.fromScale(1, 1),
				Text = countText,
				TextColor3 = Color3.fromRGB(20, 20, 20),
				TextSize = 12,
				ZIndex = 11,
			}),
		}) or nil,
	})
end

local function categoryDropdown(props)
	local categories = props.categories or {}
	local active = props.activeCategory
	local open, setOpen = React.useState(false)
	local hovered, setHovered = React.useState(false)

	local activeLabel = "Filter"
	for _, category in ipairs(categories) do
		if tostring(category.id) == tostring(active) then
			activeLabel = tostring(category.label or "Filter")
		end
	end

	local optionChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, category in ipairs(categories) do
		local isActive = tostring(category.id) == tostring(active)
		optionChildren["Opt" .. tostring(category.id)] = e("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = isActive and SHELL.GoldBase or SHELL.CardBg,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 26),
			Text = "",
			ZIndex = 44,
			[React.Event.Activated] = function()
				setOpen(false)
				if props.onSelect then
					props.onSelect(category.id)
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Outline = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(0, 0, 0),
				Thickness = 1.6,
			}, isActive and {
				Grad = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new(Color3.fromRGB(80, 80, 80), Color3.fromRGB(0, 0, 0)),
				}),
			} or nil),
			Sheen = e("UIGradient", {
				Rotation = 90,
				Color = isActive
						and ColorSequence.new(Color3.fromRGB(255, 250, 222), Color3.fromRGB(216, 168, 64))
					or ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200)),
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Size = UDim2.fromScale(1, 1),
				Text = tostring(category.label or ""),
				TextColor3 = isActive and Color3.new(1, 1, 1) or SHELL.TextMain,
				TextSize = 14,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = isActive and 0 or 0.4,
				ZIndex = 45,
			}),
		})
	end

	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder or 99,
		Size = UDim2.fromOffset(126, 30),
		ZIndex = 41,
	}, {
		Button = e("TextButton", {
			AutoButtonColor = false,
			BackgroundColor3 = hovered and Color3.fromRGB(26, 26, 30) or SHELL.CardBg,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			Text = "",
			ZIndex = 42,
			[React.Event.MouseEnter] = function()
				setHovered(true)
			end,
			[React.Event.MouseLeave] = function()
				setHovered(false)
			end,
			[React.Event.Activated] = function()
				setOpen(not open)
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Outline = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = Color3.fromRGB(0, 0, 0),
				Thickness = 1.8,
			}),
			Sheen = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200)),
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = BODY,
				Position = UDim2.fromOffset(10, 0),
				Size = UDim2.new(1, -28, 1, 0),
				Text = activeLabel,
				TextColor3 = SHELL.TextMain,
				TextSize = 13,
				TextStrokeColor3 = SHELL.TextShadow,
				TextStrokeTransparency = 0.4,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 43,
			}),
			Chevron = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Position = UDim2.new(1, -8, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				Text = open and "^" or "v",
				TextColor3 = SHELL.TextMain,
				TextSize = 12,
				ZIndex = 43,
			}),
		}),
		Menu = open and e("Frame", {
			BackgroundColor3 = SHELL.CardBg,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(0, 34),
			Size = UDim2.new(1, 0, 0, #categories * 29 + 8),
			ZIndex = 43,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = SHELL.GoldHighlight,
				Thickness = 1.35,
			}),
			Pad = e("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
			}),
			Options = e("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ZIndex = 44,
			}, optionChildren),
		}) or nil,
	})
end

local function header(props)
	local tabChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 10),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, tab in ipairs(props.tabs or {}) do
		tabChildren["Tab" .. tostring(tab.id)] = e(tabButton, {
			active = props.activeTab == tab.id,
			claimableCount = props.claimableCount,
			layoutOrder = index,
			onTabChange = props.onTabChange,
			tab = tab,
		})
	end

	if props.activeTab == "index" then
		tabChildren.CategoryFilter = e(categoryDropdown, {
			categories = props.categories,
			activeCategory = props.activeCategory,
			onSelect = props.onSelect,
			layoutOrder = #(props.tabs or {}) + 1,
		})
	end

	return e("Frame", {
		BackgroundColor3 = SHELL.HeaderBackground,
		BackgroundTransparency = SHELL.HeaderTransparency,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.new(1, 0, 0, Theme.Layout.HeaderHeight),
		ZIndex = 7,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Collected = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = BODY,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.fromOffset(180, 18),
			Text = string.format("%d / %d Collected", props.collected or 0, props.total or 0),
			TextColor3 = SHELL.GoldHighlight,
			TextSize = 12,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 8,
		}),
		Tabs = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, 36),
			Size = UDim2.fromOffset(520, 34),
			ZIndex = 8,
		}, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 1),
				PaddingBottom = UDim.new(0, 1),
			}),
			Content = e("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
			}, tabChildren),
		}),
	})
end

local function getBackgroundImageForTab(activeTab)
	if activeTab == "fruits" then
		return SHELL.FruitsBackgroundImage
	end
	if activeTab == "rewards" then
		return SHELL.RewardsBackgroundImage
	end
	return SHELL.IndexBackgroundImage
end

local function progressStrip(props)
	local total = math.max(1, tonumber(props.total) or 1)
	local collected = math.max(0, tonumber(props.collected) or 0)
	local percent = math.clamp(collected / total, 0, 1)

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Section,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, Theme.Layout.HeroHeight),
		ZIndex = 4,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(0, 2),
			Size = UDim2.new(1, 0, 0, 14),
			Text = string.format("Collected : %d/%d", collected, total),
			TextColor3 = Theme.Palette.Text,
			TextSize = 14,
			TextStrokeColor3 = Theme.Palette.GoldShadow,
			TextStrokeTransparency = 0.54,
			ZIndex = 5,
		}),
		Track = e("Frame", {
			BackgroundColor3 = Theme.Palette.ProgressTrack,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 18),
			Size = UDim2.new(1, -20, 0, 10),
			ZIndex = 5,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.ProgressStroke,
				Transparency = 0.1,
				Thickness = 1,
			}),
			Fill = e("Frame", {
				BackgroundColor3 = Theme.Palette.ProgressFill,
				BorderSizePixel = 0,
				Size = UDim2.fromScale(percent, 1),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
				Gradient = e("UIGradient", {
					Rotation = 0,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Theme.Palette.ProgressFill),
						ColorSequenceKeypoint.new(1, Theme.Palette.ProgressFillSoft),
					}),
				}),
			}),
		}),
	})
end

local function IndexScreen(props)
	local fallbackViewModel = (not props.categories or not props.units or not props.collectionStats or not props.devilFruitCollection)
		and IndexData.getDefaultViewModel()
		or nil
	local categories = props.categories or (fallbackViewModel and fallbackViewModel.categories) or {}
	local units = props.units or (fallbackViewModel and fallbackViewModel.units) or {}
	local unitsByCategory = props.unitsByCategory or (fallbackViewModel and fallbackViewModel.unitsByCategory) or nil
	local stats = props.collectionStats or (fallbackViewModel and fallbackViewModel.collectionStats) or {
		collected = 0,
		total = 0,
		claimableCount = 0,
	}
	local devilFruitCollection = props.devilFruitCollection or (fallbackViewModel and fallbackViewModel.devilFruitCollection) or {}
	local tabs = props.tabs or (fallbackViewModel and fallbackViewModel.tabs) or IndexData.Tabs
	local rewards = props.rewards or (fallbackViewModel and fallbackViewModel.rewards) or {}
	local defaultCategoryId = categories[1] and categories[1].id or "normal"

	local activeTab, setActiveTab = React.useState("index")
	local activeCategory, setActiveCategory = React.useState(defaultCategoryId)
	local mountedTabs, setMountedTabs = React.useState({
		index = true,
	})
	local mountedCategories, setMountedCategories = React.useState({
		[defaultCategoryId] = true,
	})
	local tabSwitchStartedAtRef = React.useRef(nil)
	local categorySwitchStartedAtRef = React.useRef(nil)

	React.useEffect(function()
		if DEBUG_INDEX_UI_PERF and tabSwitchStartedAtRef.current then
			debugUiLog(string.format("tab=%s duration=%.4fs", tostring(activeTab), os.clock() - tabSwitchStartedAtRef.current))
			tabSwitchStartedAtRef.current = nil
		end
	end, { activeTab })

	React.useEffect(function()
		if DEBUG_INDEX_UI_PERF and categorySwitchStartedAtRef.current then
			debugUiLog(string.format(
				"category=%s duration=%.4fs",
				tostring(activeCategory),
				os.clock() - categorySwitchStartedAtRef.current
			))
			categorySwitchStartedAtRef.current = nil
		end
	end, { activeCategory })

	local function handleTabChange(tabId)
		tabId = tostring(tabId or "")
		if tabId == "" or tabId == activeTab then
			return
		end

		if DEBUG_INDEX_UI_PERF then
			tabSwitchStartedAtRef.current = os.clock()
		end
		if mountedTabs[tabId] ~= true then
			setMountedTabs(copySetWith(mountedTabs, tabId))
		end
		setActiveTab(tabId)
	end

	local function handleCategorySelect(categoryId)
		categoryId = tostring(categoryId or "")
		if categoryId == "" or categoryId == activeCategory then
			return
		end

		if DEBUG_INDEX_UI_PERF then
			categorySwitchStartedAtRef.current = os.clock()
		end
		if mountedCategories[categoryId] ~= true then
			setMountedCategories(copySetWith(mountedCategories, categoryId))
		end
		setActiveCategory(categoryId)
	end

	local filteredUnits = React.useMemo(function()
		if unitsByCategory and unitsByCategory[activeCategory] then
			return unitsByCategory[activeCategory]
		end

		return filterUnits(units, activeCategory)
	end, { units, unitsByCategory, activeCategory })
	local fruitUnits = devilFruitCollection.units or {}
	local fruitStats = devilFruitCollection.collectionStats or {
		collected = 0,
		total = #fruitUnits,
	}
	local contentTop = Theme.Layout.HeroHeight + Theme.Layout.ContentGap
	local indexFooterHeight = 0
	local claimableCount = props.claimableCount or stats.claimableCount or 0
	local activeStats = activeTab == "fruits" and fruitStats or stats
	local mainX = 0
	local mainWidth = 0
	local backgroundImage = getBackgroundImageForTab(activeTab)
	local indexGridHeight = UDim2.new(1, 0, 1, -(contentTop + indexFooterHeight))
	local fullPanelHeight = UDim2.new(1, 0, 1, -contentTop)
	local indexCategoryPanels = {}

	for _, category in ipairs(categories) do
		local categoryId = tostring(category.id or "")
		if categoryId ~= "" and (mountedCategories[categoryId] == true or categoryId == activeCategory) then
			local categoryUnits = if unitsByCategory and unitsByCategory[categoryId]
				then unitsByCategory[categoryId]
				else filterUnits(units, categoryId)

			indexCategoryPanels["Category" .. categoryId] = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(0, 0),
				Size = UDim2.fromScale(1, 1),
				Visible = activeTab == "index" and activeCategory == categoryId,
			}, {
				Content = e(IndexGrid, {
					columns = 5,
					units = categoryUnits,
				}),
			})
		end
	end

	if next(indexCategoryPanels) == nil then
		indexCategoryPanels.ActiveCategory = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromScale(1, 1),
			Visible = activeTab == "index",
		}, {
			Content = e(IndexGrid, {
				columns = 5,
				units = filteredUnits,
			}),
		})
	end

	return e("Frame", {
		BackgroundColor3 = SHELL.MenuOverlay,
		BackgroundTransparency = 0.4,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		BaseTexture = e("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = backgroundImage,
			ImageTransparency = 1,
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
			BackgroundTransparency = 1,
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
			Stroke = goldStroke(3, 0),
		}),
		TitleBadge = titleBadge("INDEX", 208),
		CloseButton = closeButton(props.onClose),
		Header = header({
			activeTab = activeTab,
			categories = categories,
			activeCategory = activeCategory,
			onSelect = handleCategorySelect,
			claimableCount = claimableCount,
			collected = activeStats.collected,
			onClose = props.onClose,
			onTabChange = handleTabChange,
			tabs = tabs,
			total = activeStats.total,
		}),
		Body = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.Layout.OuterPadding, Theme.Layout.HeaderHeight + Theme.Layout.OuterPadding),
			Size = UDim2.new(1, -(Theme.Layout.OuterPadding * 2), 1, -(Theme.Layout.HeaderHeight + (Theme.Layout.OuterPadding * 2))),
			ZIndex = 3,
		}, {
			Main = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(mainX, 0),
				Size = UDim2.new(1, mainWidth, 1, 0),
				ZIndex = 4,
			}, {
				Progress = e(progressStrip, {
					collected = activeStats.collected,
					total = activeStats.total,
				}),
				Index = mountedTabs.index and e("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, contentTop),
					Size = indexGridHeight,
					Visible = activeTab == "index",
				}, indexCategoryPanels) or nil,
				Fruits = mountedTabs.fruits and e("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, contentTop),
					Size = fullPanelHeight,
					Visible = activeTab == "fruits",
				}, {
					Content = e(IndexGrid, {
						columns = 5,
						units = fruitUnits,
					}),
				}) or nil,
				Rewards = mountedTabs.rewards and e("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, contentTop),
					Size = fullPanelHeight,
					Visible = activeTab == "rewards",
				}, {
					Content = e(RewardsPanel, {
						onClaimRequested = props.onClaimRewardRequested,
						rewards = rewards,
					}),
				}) or nil,
			}),
		}),
	})
end

return IndexScreen
