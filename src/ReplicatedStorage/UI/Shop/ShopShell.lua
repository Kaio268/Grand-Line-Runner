local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent:WaitForChild("Theme"))
local FeaturedOfferCard = require(script.Parent:WaitForChild("Components"):WaitForChild("FeaturedOfferCard"))
local SectionBlock = require(script.Parent:WaitForChild("Components"):WaitForChild("SectionBlock"))
local SectionNav = require(script.Parent:WaitForChild("Components"):WaitForChild("SectionNav"))
local RedeemCodesPanel = require(script.Parent:WaitForChild("Components"):WaitForChild("RedeemCodesPanel"))

local e = React.createElement

local function titleDivider(props)
	return e("Frame", {
		BackgroundColor3 = Theme.Palette.GoldShadow,
		BackgroundTransparency = 0.22,
		BorderSizePixel = 0,
		Position = props.position,
		Size = props.size,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 999),
		}),
	})
end

local function statChip(props)
	return e("Frame", {
		BackgroundColor3 = Theme.Palette.Panel,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder or 0,
		Size = props.size or UDim2.fromOffset(164, 54),
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 16),
		}),
		Stroke = e("UIStroke", {
			Color = props.accentColor,
			Transparency = 0.18,
			Thickness = 1.1,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.PanelSoft),
				ColorSequenceKeypoint.new(1, Theme.Palette.Panel),
			}),
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Label,
			Position = UDim2.fromOffset(14, 8),
			Size = UDim2.new(1, -24, 0, 12),
			Text = props.label,
			TextColor3 = Theme.Palette.MutedSoft,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromOffset(14, 22),
			Size = UDim2.new(1, -28, 0, 20),
			Text = props.value,
			TextColor3 = Theme.Palette.Text,
			TextSize = 17,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function sectionBanner(props)
	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, 34),
	}, {
		Left = titleDivider({
			position = UDim2.new(0, 0, 0.5, 1),
			size = UDim2.new(0.36, -14, 0, 3),
		}),
		Right = titleDivider({
			position = UDim2.new(0.64, 14, 0.5, 1),
			size = UDim2.new(0.36, -14, 0, 3),
		}),
		Title = e("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(420, 32),
			Text = props.title,
			TextColor3 = Theme.Palette.Text,
			TextSize = 30,
			TextStrokeTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

local function ShopShell(props)
	local shellRef = React.useRef(nil)
	local scrollerRef = React.useRef(nil)
	local contentWidth, setContentWidth = React.useState(1220)
	local activeSectionKey, setActiveSectionKey = React.useState(
		props.catalog.sections[1] and props.catalog.sections[1].key or ""
	)

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
	if contentWidth < 1140 then
		columns = 2
	end
	if contentWidth < 760 then
		columns = 1
	end

	local wideHero = contentWidth >= 1160
	local introWide = contentWidth >= 1180
	local introHeight = introWide and 170 or 254
	local headerHeight = 174
	local noticeHeight = props.noticeText and 48 or 0
	local navHeight = 68
	local navTop = headerHeight + noticeHeight + 12
	local contentTop = navTop + navHeight + 14
	local titleBubbleWidth = math.floor(math.clamp(contentWidth * 0.53, 520, 760))
	local subtitleWidth = math.floor(math.clamp(contentWidth * 0.34, 320, 500))
	local titleTextSize = contentWidth >= 1320 and 56 or (contentWidth >= 1120 and 52 or 46)

	local function scrollToSection(sectionKey)
		local scroller = scrollerRef.current
		if not scroller then
			return false
		end

		local target = scroller:FindFirstChild("Section_" .. tostring(sectionKey), true)
		if not target or not target:IsA("GuiObject") then
			return false
		end

		local nextY = target.AbsolutePosition.Y - scroller.AbsolutePosition.Y + scroller.CanvasPosition.Y - 10
		local maxCanvasY = math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y)
		scroller.CanvasPosition = Vector2.new(0, math.clamp(math.floor(nextY), 0, maxCanvasY))
		return true
	end

	local function handleSectionSelected(sectionKey)
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
			local nextKey = props.catalog.sections[1] and props.catalog.sections[1].key or activeSectionKey

			for _, section in ipairs(props.catalog.sections or {}) do
				local target = scroller:FindFirstChild("Section_" .. tostring(section.key), true)
				if target and target:IsA("GuiObject") then
					if target.AbsolutePosition.Y <= (viewportTop + 98) then
						nextKey = section.key
					else
						break
					end
				end
			end

			if nextKey and nextKey ~= "" then
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
			Padding = UDim.new(0, 26),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 28),
			PaddingRight = UDim.new(0, 36),
			PaddingTop = UDim.new(0, 26),
			PaddingBottom = UDim.new(0, 34),
		}),
		Intro = e("Frame", {
			BackgroundColor3 = Theme.Palette.Panel,
			BorderSizePixel = 0,
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, introHeight),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 26),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.Border,
				Transparency = 0.12,
				Thickness = 1.5,
			}),
			Gradient = e("UIGradient", {
				Rotation = 125,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Theme.Palette.BoardSoft),
					ColorSequenceKeypoint.new(1, Theme.Palette.Panel),
				}),
			}),
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, 24),
				PaddingRight = UDim.new(0, 24),
				PaddingTop = UDim.new(0, 22),
				PaddingBottom = UDim.new(0, 22),
			}),
			Eyebrow = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Size = UDim2.new(1, 0, 0, 14),
				Text = props.catalog.heroEyebrow,
				TextColor3 = Theme.Palette.Cyan,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Headline = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(0, 18),
				Size = UDim2.new(introWide and 0.62 or 1, introWide and -18 or 0, 0, introWide and 56 or 78),
				Text = props.catalog.heroHeadline,
				TextColor3 = Theme.Palette.Text,
				TextSize = introWide and 40 or 36,
				TextStrokeTransparency = 1,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			Copy = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.fromOffset(0, introWide and 84 or 110),
				Size = UDim2.new(introWide and 0.62 or 1, introWide and -18 or 0, 0, introWide and 46 or 58),
				Text = props.catalog.heroCopy,
				TextColor3 = Theme.Palette.Muted,
				TextSize = 14,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			Stats = e("Frame", {
				AnchorPoint = introWide and Vector2.new(1, 0) or Vector2.new(0, 0),
				BackgroundTransparency = 1,
				Position = introWide and UDim2.new(1, 0, 0, 0) or UDim2.new(0, 0, 0, 176),
				Size = introWide and UDim2.fromOffset(252, 136) or UDim2.new(1, 0, 0, 54),
			}, {
				List = e("UIListLayout", {
					FillDirection = introWide and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 8),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Featured = statChip({
					layoutOrder = 1,
					label = "Featured",
					value = tostring(#(props.catalog.featuredOffers or {})) .. " marquee offers",
					accentColor = Theme.Palette.Gold,
					size = introWide and UDim2.new(1, 0, 0, 40) or UDim2.new(1 / 3, -6, 0, 54),
				}),
				Live = statChip({
					layoutOrder = 2,
					label = "Captain Picks",
					value = "Bundles, perks, boosts",
					accentColor = Theme.Palette.Emerald,
					size = introWide and UDim2.new(1, 0, 0, 40) or UDim2.new(1 / 3, -6, 0, 54),
				}),
				Structure = statChip({
					layoutOrder = 3,
					label = "Limited Windows",
					value = "Codes and timed offers",
					accentColor = Theme.Palette.Cyan,
					size = introWide and UDim2.new(1, 0, 0, 40) or UDim2.new(1 / 3, -6, 0, 54),
				}),
			}),
		}),
		FeaturedLabel = sectionBanner({
			layoutOrder = 2,
			title = "Featured / Top Offers",
		}),
	}

	for index, item in ipairs(props.catalog.featuredOffers or {}) do
		contentChildren["Featured" .. tostring(index)] = e(FeaturedOfferCard, {
			item = item,
			layoutOrder = 2 + index,
			onPurchaseRequested = props.onPurchaseRequested,
			onGiftRequested = props.onGiftRequested,
			zIndex = 8,
			isWide = wideHero,
			size = UDim2.new(1, 0, 0, wideHero and 258 or 290),
		})
	end

	for index, section in ipairs(props.catalog.sections or {}) do
		contentChildren["Section_" .. tostring(section.key or index)] = e(SectionBlock, {
			section = section,
			columns = columns,
			layoutOrder = 10 + index,
			onPurchaseRequested = props.onPurchaseRequested,
			onGiftRequested = props.onGiftRequested,
			zIndex = 8,
		})
	end

	if props.catalog.codesPanel then
		contentChildren.CodesBanner = sectionBanner({
			layoutOrder = 998,
			title = "Redeem Codes",
		})
		contentChildren.CodesPanel = e(RedeemCodesPanel, {
			layoutOrder = 999,
			title = props.catalog.codesPanel.title,
			eyebrow = props.catalog.codesPanel.eyebrow,
			description = props.catalog.codesPanel.description,
			placeholder = props.catalog.codesPanel.placeholder,
			helperText = props.catalog.codesPanel.helperText,
			buttonText = props.catalog.codesPanel.buttonText,
			zIndex = 8,
			onRedeemRequested = props.onRedeemRequested,
		})
	end

	contentChildren.BottomSpacer = e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = 1001,
		Size = UDim2.new(1, 0, 0, 12),
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
				CornerRadius = UDim.new(0, 24),
			}),
		}),
		Overlay = e("Frame", {
			BackgroundColor3 = Theme.Palette.Ink,
			BackgroundTransparency = 0.24,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 2,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 24),
			}),
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 26),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.Border,
			Transparency = 0.08,
			Thickness = 1.6,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Theme.Palette.BoardSoft),
				ColorSequenceKeypoint.new(0.42, Theme.Palette.Board),
				ColorSequenceKeypoint.new(1, Theme.Palette.Ink),
			}),
		}),
		Header = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(24, 10),
			Size = UDim2.new(1, -56, 0, headerHeight),
			ZIndex = 10,
		}, {
			ShopEyebrow = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Position = UDim2.fromOffset(0, 4),
				Size = UDim2.fromOffset(titleBubbleWidth, 16),
				Text = "GRAND LINE RUSH SHOP",
				TextColor3 = Theme.Palette.GoldSoft,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			ShopTitle = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Position = UDim2.fromOffset(0, 24),
				Size = UDim2.fromOffset(titleBubbleWidth, 98),
				Text = props.catalog.title,
				TextColor3 = Theme.Palette.GoldSoft,
				TextSize = titleTextSize,
				TextStrokeTransparency = 1,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Top,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Subtitle = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Position = UDim2.new(1, -156, 0, 22),
				Size = UDim2.fromOffset(subtitleWidth, 54),
				Text = props.catalog.subtitle,
				TextColor3 = Theme.Palette.Muted,
				TextSize = 15,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Right,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
			Close = e("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				AutoButtonColor = false,
				BackgroundColor3 = Theme.Palette.CloseFill or Color3.fromRGB(186, 86, 100),
				BorderSizePixel = 0,
				Position = UDim2.new(1, 0, 0, 8),
				Size = UDim2.fromOffset(38, 38),
				Text = "X",
				TextColor3 = Theme.Palette.Text,
				TextSize = 18,
				Font = Theme.Fonts.Display,
				ZIndex = 11,
				[React.Event.Activated] = props.onClose,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 12),
				}),
				Stroke = e("UIStroke", {
					Color = Theme.Palette.GoldShadow,
					Transparency = 0.04,
				}),
			}),
		}),
		Notice = props.noticeText and e("Frame", {
			BackgroundColor3 = Theme.Palette.PanelSoft,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(30, headerHeight),
			Size = UDim2.new(1, -60, 0, 42),
			ZIndex = 10,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 14),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.Gold,
				Transparency = 0.12,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Label,
				Position = UDim2.fromOffset(14, 0),
				Size = UDim2.new(1, -28, 1, 0),
				Text = props.noticeText,
				TextColor3 = Theme.Palette.Text,
				TextSize = 12,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}) or nil,
		StickyNav = e("Frame", {
			BackgroundColor3 = Theme.Palette.InkSoft,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(28, navTop),
			Size = UDim2.new(1, -56, 0, navHeight),
			ZIndex = 12,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 20),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.BorderSoft,
				Transparency = 0.1,
				Thickness = 1.2,
			}),
			Nav = e(SectionNav, {
				layoutOrder = 1,
				sections = props.catalog.sections,
				activeSectionKey = activeSectionKey,
				onSectionSelected = handleSectionSelected,
				position = UDim2.fromOffset(12, 5),
				size = UDim2.new(1, -24, 0, 56),
				zIndex = 13,
			}),
		}),
		Content = e("ScrollingFrame", {
			ref = scrollerRef,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.new(),
			Position = UDim2.fromOffset(0, contentTop),
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ScrollBarImageColor3 = Theme.Palette.Cyan,
			ScrollBarThickness = 9,
			Size = UDim2.new(1, 0, 1, -contentTop),
			ZIndex = 8,
		}, contentChildren),
	})
end

return ShopShell
