local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local SectionBlock = require(script.Parent:WaitForChild("Components"):WaitForChild("SectionBlock"))
local SectionNav = require(script.Parent:WaitForChild("Components"):WaitForChild("SectionNav"))

local e = React.createElement

local FEATURED_TAB = {
	key = "featured",
	title = "Featured",
	themeKey = "Gold",
}

local function buildFeaturedSection(catalog)
	local featuredItems = {}

	for _, item in ipairs(catalog.featuredOffers or {}) do
		featuredItems[#featuredItems + 1] = item
	end

	for _, section in ipairs(catalog.featuredSections or {}) do
		for _, item in ipairs(section.items or {}) do
			featuredItems[#featuredItems + 1] = item
		end
	end

	return {
		key = FEATURED_TAB.key,
		title = FEATURED_TAB.title,
		themeKey = FEATURED_TAB.themeKey,
		items = featuredItems,
	}
end

local function buildPageSections(catalog)
	local sections = {}
	local featuredSection = buildFeaturedSection(catalog)

	if #(featuredSection.items or {}) > 0 then
		sections[#sections + 1] = featuredSection
	end

	for _, section in ipairs(catalog.sections or {}) do
		sections[#sections + 1] = section
	end

	return sections
end

local function ShopShell(props)
	local shellRef = React.useRef(nil)
	local scrollerRef = React.useRef(nil)
	local contentWidth, setContentWidth = React.useState(1220)
	local activeSectionKey, setActiveSectionKey = React.useState(FEATURED_TAB.key)
	local activeSectionKeyRef = React.useRef(FEATURED_TAB.key)

	React.useEffect(function()
		local shell = shellRef.current
		if not shell then
			return nil
		end

		local function updateWidth()
			setContentWidth(shell.AbsoluteSize.X)
		end

		updateWidth()
		local connection = shell:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateWidth)

		return function()
			connection:Disconnect()
		end
	end, {})

	local columns = 3
	if contentWidth < 1080 then
		columns = 2
	end
	if contentWidth < 720 then
		columns = 1
	end

	local isNarrow = contentWidth < 760
	local headerHeight = isNarrow and 78 or 88
	local noticeHeight = props.noticeText and 42 or 0
	local navHeight = isNarrow and 52 or 58
	local navTop = headerHeight + noticeHeight + 8
	local contentTop = navTop + navHeight + 10
	local titleTextSize = if isNarrow then 30 elseif contentWidth < 1040 then 34 else 38
	local horizontalInset = isNarrow and 16 or 24
	local pageSections = buildPageSections(props.catalog)

	activeSectionKeyRef.current = activeSectionKey

	local function scrollToSection(sectionKey)
		local scroller = scrollerRef.current
		if not scroller then
			return false
		end

		local target = scroller:FindFirstChild("Section_" .. tostring(sectionKey), true)
		if not target or not target:IsA("GuiObject") then
			return false
		end

		local nextY = target.AbsolutePosition.Y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y - 8
		local maxCanvasY = math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y)
		scroller.CanvasPosition = Vector2.new(0, math.clamp(math.floor(nextY), 0, maxCanvasY))
		return true
	end

	local function handleSectionSelected(sectionKey)
		activeSectionKeyRef.current = sectionKey
		setActiveSectionKey(sectionKey)
		if props.onSectionSelected then
			props.onSectionSelected(sectionKey)
		end

		task.spawn(function()
			for _ = 1, 8 do
				if scrollToSection(sectionKey) then
					return
				end
				task.wait()
			end
		end)
	end

	React.useEffect(function()
		local scroller = scrollerRef.current
		if not scroller then
			return nil
		end

		local function syncActiveSection()
			local viewportTop = scroller.AbsolutePosition.Y
			local nextKey = pageSections[1] and pageSections[1].key or activeSectionKeyRef.current

			for _, section in ipairs(pageSections) do
				local target = scroller:FindFirstChild("Section_" .. tostring(section.key), true)
				if target and target:IsA("GuiObject") then
					if target.AbsolutePosition.Y <= (viewportTop + 72) then
						nextKey = section.key
					else
						break
					end
				end
			end

			if nextKey and nextKey ~= "" and nextKey ~= activeSectionKeyRef.current then
				activeSectionKeyRef.current = nextKey
				setActiveSectionKey(nextKey)
			end
		end

		syncActiveSection()

		local canvasConnection = scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(syncActiveSection)
		local sizeConnection = scroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncActiveSection)

		return function()
			canvasConnection:Disconnect()
			sizeConnection:Disconnect()
		end
	end, {})

	local contentChildren = {
		List = e("UIListLayout", {
			Padding = UDim.new(0, isNarrow and 18 or 22),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, horizontalInset),
			PaddingRight = UDim.new(0, horizontalInset + 8),
			PaddingTop = UDim.new(0, isNarrow and 16 or 20),
			PaddingBottom = UDim.new(0, 28),
		}),
	}

	for index, section in ipairs(pageSections) do
		contentChildren["Section_" .. tostring(section.key or index)] = e(SectionBlock, {
			section = section,
			columns = columns,
			layoutOrder = index,
			onPurchaseRequested = props.onPurchaseRequested,
			zIndex = 8,
		})
	end

	contentChildren.BottomSpacer = e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = 1000,
		Size = UDim2.new(1, 0, 0, 8),
	})

	return e("Frame", {
		ref = shellRef,
		BackgroundColor3 = Theme.Palette.Ink,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, {
		BaseTexture = e("ImageLabel", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = Theme.Assets.ShopBackground,
			ImageTransparency = 0,
			ScaleType = Enum.ScaleType.Stretch,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 1,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 18),
			}),
		}),
		Overlay = e("Frame", {
			BackgroundColor3 = Theme.Palette.Ink,
			BackgroundTransparency = 0.16,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 18),
			}),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 20),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.Border,
			Transparency = 0.05,
			Thickness = 1.6,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.BoardSoft),
				ColorSequenceKeypoint.new(1, Theme.Palette.Ink),
			}),
		}),
		Header = e("Frame", {
			BackgroundColor3 = Theme.Palette.InkSoft,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(horizontalInset, 10),
			Size = UDim2.new(1, -(horizontalInset * 2), 0, headerHeight - 18),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.BorderSoft,
				Transparency = 0.12,
				Thickness = 1.1,
			}),
			Title = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(18, 0),
				Size = UDim2.new(1, -82, 1, 0),
				Text = props.catalog.title or "Store",
				TextColor3 = Theme.Palette.GoldSoft,
				TextSize = titleTextSize,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Center,
				ZIndex = 11,
			}),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5),
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Palette.CloseFill,
				BorderSizePixel = 0,
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(40, 40),
				Text = "X",
				TextColor3 = Theme.Palette.Text,
				TextSize = 18,
				Font = Theme.Fonts.Display,
				ZIndex = 12,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 10),
				}),
				Stroke = e("UIStroke", {
					Color = Theme.Palette.CloseStroke,
					Transparency = 0.08,
					Thickness = 1,
				}),
			}),
		}),
		Notice = props.noticeText and e("Frame", {
			BackgroundColor3 = Theme.Palette.PanelSoft,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(horizontalInset, headerHeight),
			Size = UDim2.new(1, -(horizontalInset * 2), 0, 36),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -24, 1, 0),
				Text = props.noticeText,
				TextColor3 = Theme.Palette.Text,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 11,
			}),
		}) or nil,
		StickyNav = e("Frame", {
			BackgroundColor3 = Theme.Palette.InkSoft,
			BackgroundTransparency = 0.04,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(horizontalInset, navTop),
			Size = UDim2.new(1, -(horizontalInset * 2), 0, navHeight),
			ZIndex = 12,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.BorderSoft,
				Transparency = 0.16,
				Thickness = 1,
			}),
			Nav = e(SectionNav, {
				sections = pageSections,
				activeSectionKey = activeSectionKey,
				onSectionSelected = handleSectionSelected,
				compact = contentWidth < 1020,
				position = UDim2.fromOffset(8, 6),
				size = UDim2.new(1, -16, 0, navHeight - 8),
				zIndex = 13,
			}),
		}),
		Content = e("ScrollingFrame", {
			ref = scrollerRef,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			ElasticBehavior = Enum.ElasticBehavior.Never,
			Position = UDim2.fromOffset(0, contentTop),
			ScrollBarImageColor3 = Theme.Palette.Cyan,
			ScrollBarThickness = isNarrow and 5 or 7,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			Size = UDim2.new(1, 0, 1, -contentTop),
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ZIndex = 8,
		}, contentChildren),
	})
end

return ShopShell
