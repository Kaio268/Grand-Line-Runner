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
	local headerHeight = 136
	local noticeHeight = props.noticeText and 48 or 0
	local navHeight = 68
	local navTop = headerHeight + noticeHeight + 12
	local contentTop = navTop + navHeight + 14
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
		FeaturedLabel = sectionBanner({
			layoutOrder = 1,
			title = "Featured / Top Offers",
		}),
	}

	for index, item in ipairs(props.catalog.featuredOffers or {}) do
		contentChildren["Featured" .. tostring(index)] = e(FeaturedOfferCard, {
			item = item,
			layoutOrder = 1 + index,
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
			Transparency = 0.02,
			Thickness = 2.2,
		}),
		InnerBorder = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(2, 2),
			Size = UDim2.new(1, -4, 1, -4),
			ZIndex = 9,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 24),
			}),
			Stroke = e("UIStroke", {
				Color = Theme.Palette.BorderSoft,
				Transparency = 0.08,
				Thickness = 1.2,
			}),
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
			Position = UDim2.fromOffset(24, 8),
			Size = UDim2.new(1, -56, 0, headerHeight),
			ZIndex = 10,
		}, {
			Panel = e("Frame", {
				BackgroundColor3 = Theme.Palette.InkSoft,
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Position = UDim2.fromOffset(0, 6),
				Size = UDim2.new(1, -56, 0, 112),
				ZIndex = 10,
			}, {
				Corner = e("UICorner", {
					CornerRadius = UDim.new(0, 20),
				}),
				Stroke = e("UIStroke", {
					Color = Theme.Palette.BorderSoft,
					Transparency = 0.06,
					Thickness = 1.35,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Theme.Palette.BoardSoft),
						ColorSequenceKeypoint.new(1, Theme.Palette.Board),
					}),
				}),
			}),
			ShopTitle = e("TextLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Display,
					Position = UDim2.new(0.5, -28, 0.5, 0),
					Size = UDim2.new(1, -148, 0, 72),
					Text = props.catalog.title or "Grand Line Rush Store",
					TextColor3 = Theme.Palette.GoldSoft,
					TextSize = titleTextSize,
					TextStrokeTransparency = 1,
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Center,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 11,
				}),
				Close = e("TextButton", {
					AnchorPoint = Vector2.new(1, 0),
					AutoButtonColor = false,
					BackgroundColor3 = Color3.fromRGB(200, 0, 9),
					BorderSizePixel = 0,
					Position = UDim2.new(1, 0, 0, 14),
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
				position = UDim2.fromOffset(12, 6),
				size = UDim2.new(1, -24, 0, 54),
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
