local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local IndexData = require(script.Parent:WaitForChild("IndexData"))
local CategorySidebar = require(script.Parent:WaitForChild("Components"):WaitForChild("CategorySidebar"))
local CategoryTabs = require(script.Parent:WaitForChild("Components"):WaitForChild("CategoryTabs"))
local IndexGrid = require(script.Parent:WaitForChild("Components"):WaitForChild("IndexGrid"))
local RewardsPanel = require(script.Parent:WaitForChild("Components"):WaitForChild("RewardsPanel"))

local e = React.createElement

local function findCategoryById(categories, categoryId)
	for _, category in ipairs(categories) do
		if category.id == categoryId then
			return category
		end
	end

	return categories[1]
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
	local isFruitTab = tab.id == "fruits"
	local fillColor = active and (isRewardTab and Theme.Palette.TabRewardFill or Theme.Palette.HeaderBottom)
		or Color3.fromRGB(19, 41, 67)
	local strokeColor = active and (isRewardTab and Theme.Palette.TabRewardAccent or Theme.Palette.Text)
		or Color3.fromRGB(50, 84, 120)
	local textColor = active and Theme.Palette.Text or Color3.fromRGB(229, 237, 255)
	local countText = isRewardTab and (props.claimableCount or 0) > 0 and tostring(props.claimableCount) or nil
	local buttonWidth = isRewardTab and 120 or (isFruitTab and 116 or 104)

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromOffset(buttonWidth, Theme.Layout.TabHeight),
		Text = "",
		[React.Event.Activated] = function()
			props.onTabChange(tab.id)
		end,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Stroke = e("UIStroke", {
			Color = strokeColor,
			Transparency = active and 0.02 or 0.18,
			Thickness = 1,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(10, 0),
			Size = UDim2.new(1, if countText then -30 else -20, 1, 0),
			Text = tostring(tab.label or ""),
			TextColor3 = textColor,
			TextSize = 12,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.55,
		}),
		Count = countText and e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Palette.TabRewardAccent,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Text = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Size = UDim2.fromScale(1, 1),
				Text = countText,
				TextColor3 = Theme.Palette.Ink,
				TextSize = 11,
			}),
		}) or nil,
	})
end

local function header(props)
	local tabChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 8),
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

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.HeaderMid,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, Theme.Layout.HeaderHeight),
	}, {
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.HeaderStart),
				ColorSequenceKeypoint.new(0.45, Theme.Palette.HeaderMid),
				ColorSequenceKeypoint.new(1, Theme.Palette.HeaderEnd),
			}),
		}),
		Shine = e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
		}, {
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.82),
					NumberSequenceKeypoint.new(0.35, 0.96),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		}),
		BottomShade = e("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			BackgroundColor3 = Theme.Palette.HeaderBottom,
			BorderSizePixel = 0,
			Position = UDim2.new(0, 0, 1, 0),
			Size = UDim2.new(1, 0, 0, 4),
		}),
		Brand = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(14, 9),
			Size = UDim2.fromOffset(180, 12),
			Text = "GRAND LINE RUSH",
			TextColor3 = Theme.Palette.Text,
			TextSize = 10,
			TextStrokeColor3 = Theme.Palette.HeaderTextStroke,
			TextStrokeTransparency = 0.5,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Title = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(220, 24),
			Text = "Index",
			TextColor3 = Theme.Palette.Text,
			TextSize = 30,
			TextStrokeColor3 = Theme.Palette.HeaderTextStroke,
			TextStrokeTransparency = 0.35,
		}),
		Collected = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(14, 26),
			Size = UDim2.fromOffset(180, 18),
			Text = string.format("%d / %d Collected", props.collected or 0, props.total or 0),
			TextColor3 = Theme.Palette.Text,
			TextSize = 13,
			TextStrokeColor3 = Theme.Palette.HeaderTextStroke,
			TextStrokeTransparency = 0.45,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Tabs = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, 39),
			Size = UDim2.fromOffset(360, Theme.Layout.TabHeight),
		}, tabChildren),
		Close = e("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			AutoButtonColor = false,
			BackgroundColor3 = Theme.Palette.CloseFill,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(34, 34),
			Text = "X",
			TextColor3 = Theme.Palette.Text,
			TextSize = 16,
			Font = Theme.Fonts.Display,
			TextStrokeColor3 = Theme.Palette.HeaderTextStroke,
			TextStrokeTransparency = 0.55,
			[React.Event.Activated] = function()
				if props.onClose then
					props.onClose()
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 7),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.CloseStroke,
				Transparency = 0.02,
			}),
		}),
	})
end

local function progressStrip(props)
	local total = math.max(1, tonumber(props.total) or 1)
	local collected = math.max(0, tonumber(props.collected) or 0)
	local percent = math.clamp(collected / total, 0, 1)

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Section,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, Theme.Layout.HeroHeight),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 10),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.BorderSoft,
			Transparency = 0.16,
			Thickness = 1,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.new(0, 0, 0, 2),
			Size = UDim2.new(1, 0, 0, 14),
			Text = string.format("Collected : %d/%d", collected, total),
			TextColor3 = Theme.Palette.Text,
			TextSize = 14,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.5,
		}),
		Track = e("Frame", {
			BackgroundColor3 = Theme.Palette.ProgressTrack,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(10, 18),
			Size = UDim2.new(1, -20, 0, 10),
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
				Size = UDim2.new(percent, 0, 1, 0),
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

	local filteredUnits = filterUnits(units, activeCategory)
	local fruitUnits = devilFruitCollection.units or {}
	local fruitStats = devilFruitCollection.collectionStats or {
		collected = 0,
		total = #fruitUnits,
	}
	local contentTop = Theme.Layout.HeroHeight + Theme.Layout.ContentGap
	local footerHeight = activeTab == "index" and (Theme.Layout.FooterTabsHeight + Theme.Layout.ContentGap) or 0
	local claimableCount = props.claimableCount or stats.claimableCount or 0
	local showCategoryNavigation = activeTab == "index"
	local activeStats = activeTab == "fruits" and fruitStats or stats
	local mainX = showCategoryNavigation and (Theme.Layout.SidebarWidth + Theme.Layout.ContentGap) or 0
	local mainWidth = showCategoryNavigation and -(Theme.Layout.SidebarWidth + Theme.Layout.ContentGap) or 0

	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Ink,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 18),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.Border,
			Transparency = 0.02,
			Thickness = 1.2,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.BoardSoft),
				ColorSequenceKeypoint.new(0.28, Theme.Palette.Board),
				ColorSequenceKeypoint.new(1, Theme.Palette.InkSoft),
			}),
		}),
		Header = header({
			activeTab = activeTab,
			claimableCount = claimableCount,
			collected = activeStats.collected,
			onClose = props.onClose,
			onTabChange = setActiveTab,
			tabs = tabs,
			total = activeStats.total,
		}),
		Body = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(Theme.Layout.OuterPadding, Theme.Layout.HeaderHeight + Theme.Layout.OuterPadding),
			Size = UDim2.new(1, -(Theme.Layout.OuterPadding * 2), 1, -(Theme.Layout.HeaderHeight + (Theme.Layout.OuterPadding * 2))),
		}, {
			SidebarShell = showCategoryNavigation and e("Frame", {
				BackgroundColor3 = Theme.Palette.SidebarFill,
				BorderSizePixel = 0,
				Size = UDim2.new(0, Theme.Layout.SidebarWidth, 1, 0),
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 12),
				}),
				Stroke = e("UIStroke", {
					Color = Theme.Palette.BorderSoft,
					Transparency = 0.18,
					Thickness = 1,
				}),
				Padding = e("UIPadding", {
					PaddingBottom = UDim.new(0, 6),
					PaddingTop = UDim.new(0, 6),
				}),
				Sidebar = e(CategorySidebar, {
					activeCategory = activeCategory,
					categories = categories,
					onSelect = setActiveCategory,
				}),
			}) or nil,
			Main = e("Frame", {
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(mainX, 0),
				Size = UDim2.new(1, mainWidth, 1, 0),
			}, {
				Progress = e(progressStrip, {
					collected = activeStats.collected,
					total = activeStats.total,
				}),
				Grid = activeTab == "index" and e("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, contentTop),
					Size = UDim2.new(1, 0, 1, -(contentTop + footerHeight)),
				}, {
					Content = e(IndexGrid, {
						units = filteredUnits,
					}),
				}) or activeTab == "fruits" and e("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, contentTop),
					Size = UDim2.new(1, 0, 1, -contentTop),
				}, {
					Content = e(IndexGrid, {
						units = fruitUnits,
					}),
				}) or nil,
				Rewards = activeTab == "rewards" and e("Frame", {
					BackgroundTransparency = 1,
					Position = UDim2.fromOffset(0, contentTop),
					Size = UDim2.new(1, 0, 1, -contentTop),
				}, {
					Content = e(RewardsPanel, {
						onClaimRequested = props.onClaimRewardRequested,
						rewards = rewards,
					}),
				}) or nil,
				FooterTabs = activeTab == "index" and e("Frame", {
					AnchorPoint = Vector2.new(0, 1),
					BackgroundTransparency = 1,
					Position = UDim2.new(0, 0, 1, 0),
					Size = UDim2.new(1, 0, 0, Theme.Layout.FooterTabsHeight),
				}, {
					Tabs = e(CategoryTabs, {
						activeCategory = activeCategory,
						categories = categories,
						onSelect = setActiveCategory,
					}),
				}) or nil,
			}),
		}),
	})
end

return IndexScreen
