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

local SHELL = {
	IndexBackgroundImage = "rbxassetid://75192947200012",
	FruitsBackgroundImage = "rbxassetid://134053886107384",
	RewardsBackgroundImage = "rbxassetid://130097582075753",
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
	local fillColor = active and Theme.Palette.TabRewardFill or (hovered and SHELL.SectionHover or SHELL.HeaderBackground)
	local strokeColor = SHELL.GoldHighlight
	local textColor = active and SHELL.GoldHighlight or Theme.Palette.Text
	local countText = isRewardTab and (props.claimableCount or 0) > 0 and tostring(props.claimableCount) or nil
	local buttonWidth = isRewardTab and 120 or 116

	return e("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = fillColor,
		BackgroundTransparency = 0.15,
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
			CornerRadius = UDim.new(0, 12),
		}),
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = strokeColor,
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
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(10, 1),
			Size = UDim2.new(1, if countText then -30 else -20, 1, 0),
			Text = tostring(tab.label or ""),
			TextColor3 = textColor,
			TextSize = 12,
			TextStrokeColor3 = Theme.Palette.Shadow,
			TextStrokeTransparency = 0.55,
			ZIndex = 9,
		}),
		Count = countText and e("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = Theme.Palette.TabRewardAccent,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(18, 18),
			ZIndex = 9,
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
				ZIndex = 10,
			}),
		}) or nil,
	})
end

local function header(props)
	local tabChildren = {
		List = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
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

	return e("Frame", {
		BackgroundColor3 = SHELL.HeaderBackground,
		BackgroundTransparency = SHELL.HeaderTransparency,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.new(1, 0, 0, Theme.Layout.HeaderHeight),
		ZIndex = 7,
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
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.new(0.5, 0, 0, 6),
			Size = UDim2.fromOffset(220, 24),
			Text = "INDEX",
			TextColor3 = SHELL.TextMain,
			TextSize = 28,
			TextStrokeColor3 = SHELL.GoldShadow,
			TextStrokeTransparency = 0.45,
			ZIndex = 8,
		}),
		Collected = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(14, 26),
			Size = UDim2.fromOffset(180, 18),
			Text = string.format("%d / %d Collected", props.collected or 0, props.total or 0),
			TextColor3 = Theme.Palette.MutedSoft,
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
			Size = UDim2.fromOffset(376, 34),
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
		Close = e("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			AutoButtonColor = false,
			BackgroundColor3 = SHELL.CloseFill,
			BorderSizePixel = 0,
			Position = UDim2.new(1, -10, 0, 10),
			Size = UDim2.fromOffset(34, 34),
			Text = "X",
			TextColor3 = Color3.new(1, 1, 1),
			TextSize = 16,
			Font = Enum.Font.GothamBold,
			TextStrokeColor3 = SHELL.TextShadow,
			TextStrokeTransparency = 0.4,
			ZIndex = 9,
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
				Color = SHELL.GoldShadow,
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
		Stroke = e("UIStroke", {
			Color = SHELL.GoldHighlight,
			Transparency = 0,
			Thickness = 1.5,
		}),
		Title = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(0, 2),
			Size = UDim2.new(1, 0, 0, 14),
			Text = string.format("Collected : %d/%d", collected, total),
			TextColor3 = Theme.Palette.Text,
			TextSize = 14,
			TextStrokeColor3 = Theme.Palette.Shadow,
			TextStrokeTransparency = 0.5,
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
	local backgroundImage = getBackgroundImageForTab(activeTab)

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
			Image = backgroundImage,
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
			ZIndex = 3,
		}, {
			SidebarShell = showCategoryNavigation and e("Frame", {
				BackgroundColor3 = Theme.Palette.SidebarFill,
				BackgroundTransparency = 0.25,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Size = UDim2.new(0, Theme.Layout.SidebarWidth, 1, 0),
				ZIndex = 4,
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
				ZIndex = 4,
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
					Position = UDim2.fromScale(0, 1),
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
