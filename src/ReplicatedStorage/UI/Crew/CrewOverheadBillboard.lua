local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local CrewVariantsCfg = require(Configs:WaitForChild("CrewVariants"))
local Responsive = require(script.Parent.Parent:WaitForChild("Responsive"))
local RewardOverheadBillboard = require(script.Parent.Parent:WaitForChild("RewardOverheadBillboard"))
local IndexTheme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local PANEL_FILL = Color3.fromRGB(17, 26, 39)
local PANEL_FILL_SOFT = Color3.fromRGB(29, 43, 61)
local TEXT = Color3.fromRGB(239, 239, 235)
local GOLD = Color3.fromRGB(242, 209, 107)
local BOOST_GOLD = Color3.fromRGB(111, 230, 124)
local GOLD_VARIANT = Color3.fromRGB(255, 210, 92)
local DIAMOND_VARIANT = Color3.fromRGB(128, 236, 255)
local FLEET_SHIELD = Color3.fromRGB(103, 221, 255)
local CREW_SHIELD = Color3.fromRGB(111, 230, 124)
local PERMANENT_PURPLE = Color3.fromRGB(172, 121, 255)
local PERMANENT_GOLD = Color3.fromRGB(255, 216, 104)
local SHADOW = Color3.fromRGB(0, 0, 0)
local SHIELD_GLYPH = utf8.char(0x1F6E1)

local PLACED_LAYOUT_WIDTH_DESKTOP = 304
local PLACED_LAYOUT_WIDTH_MOBILE = 264
local PLACED_LAYOUT_HEIGHT = 104
local PLACED_WORLD_WIDTH_DESKTOP_STUDS = 8.6
local PLACED_WORLD_WIDTH_MOBILE_STUDS = 7.5
local PLACED_WORLD_HEIGHT_STUDS = 2.95

local function formatIncome(value)
	return CurrencyUtil.formatIncomeCompactPerSecond(math.max(0, tonumber(value) or 0))
end

local function blendColor(baseColor, accentColor, alpha)
	return baseColor:Lerp(accentColor, math.clamp(alpha or 0, 0, 1))
end

local function isMobileViewport()
	return Responsive.isMobile()
end

local function proportion(value, total)
	return value / math.max(total, 1)
end

local function startsWith(text, prefix)
	return prefix ~= "" and text:sub(1, #prefix) == prefix
end

local function getVariantPrefix(variantLabel)
	local versions = CrewVariantsCfg.Versions or {}
	local variantInfo = versions[variantLabel]
	local configuredPrefix = variantInfo and variantInfo.Prefix
	if typeof(configuredPrefix) == "string" and configuredPrefix ~= "" then
		return configuredPrefix
	end

	return tostring(variantLabel or "") .. " "
end

local function getEntryVariantLabel(entry)
	local rawVariant = entry.variant or entry.variantTag
	if rawVariant ~= nil then
		local variant = tostring(rawVariant)
		if variant ~= "" and variant ~= "Normal" then
			return variant
		end

		return nil
	end

	return nil
end

local function getVariantDisplayName(displayName, variantLabel)
	local name = tostring(displayName or "Crewmate")
	if not variantLabel then
		return name
	end

	local prefix = getVariantPrefix(variantLabel)
	if startsWith(name, prefix) then
		local stripped = name:sub(#prefix + 1)
		if stripped ~= "" then
			return stripped
		end
	end

	return name
end

local function getVariantStyle(entry, rarityStyle)
	local variant = getEntryVariantLabel(entry)
	local rarityAccent = rarityStyle.textColor or GOLD
	if variant == "Golden" then
		return {
			variantAccent = GOLD_VARIANT,
			rarityAccent = rarityAccent,
			border = GOLD_VARIANT,
			variantLabel = "Golden",
			rarityLabel = tostring(entry.rarity or "Common"),
			panelFill = blendColor(PANEL_FILL, GOLD_VARIANT, 0.22),
			panelStart = blendColor(PANEL_FILL_SOFT, GOLD_VARIANT, 0.54),
			panelEnd = blendColor(PANEL_FILL, GOLD_VARIANT, 0.24),
			glowTransparency = 0.72,
		}
	elseif variant == "Diamond" then
		return {
			variantAccent = DIAMOND_VARIANT,
			rarityAccent = rarityAccent,
			border = DIAMOND_VARIANT,
			variantLabel = "Diamond",
			rarityLabel = tostring(entry.rarity or "Common"),
			panelFill = blendColor(PANEL_FILL, DIAMOND_VARIANT, 0.22),
			panelStart = blendColor(PANEL_FILL_SOFT, DIAMOND_VARIANT, 0.54),
			panelEnd = blendColor(PANEL_FILL, DIAMOND_VARIANT, 0.24),
			glowTransparency = 0.72,
		}
	end

	return {
		variantAccent = nil,
		rarityAccent = rarityAccent,
		border = rarityStyle.borderColor or GOLD,
		variantLabel = nil,
		rarityLabel = tostring(entry.rarity or "Common"),
		panelFill = PANEL_FILL,
		panelStart = blendColor(PANEL_FILL_SOFT, rarityAccent, 0.12),
		panelEnd = PANEL_FILL,
		glowTransparency = 1,
	}
end

local function getProtectionStyle(protectionType)
	protectionType = tostring(protectionType or "none")
	if protectionType == "fleet" then
		return {
			label = "Fleet Shield",
			detail = "",
			textColor = FLEET_SHIELD,
			border = FLEET_SHIELD,
			fill = blendColor(PANEL_FILL_SOFT, FLEET_SHIELD, 0.24),
		}
	elseif protectionType == "crew" then
		return {
			label = "Crew Shield",
			detail = "",
			textColor = CREW_SHIELD,
			border = CREW_SHIELD,
			fill = blendColor(PANEL_FILL_SOFT, CREW_SHIELD, 0.24),
		}
	elseif protectionType == "permanent" then
		return {
			label = "Permanent",
			detail = "Cannot Be Stolen",
			textColor = PERMANENT_GOLD,
			border = PERMANENT_GOLD,
			fill = blendColor(PANEL_FILL_SOFT, PERMANENT_PURPLE, 0.3),
		}
	end

	return nil
end

local function pill(text, textColor, size, textSize, layoutOrder)
	return e("Frame", {
		BackgroundColor3 = blendColor(PANEL_FILL_SOFT, textColor, 0.18),
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
		Size = size,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Stroke = e("UIStroke", {
			Color = textColor,
			Transparency = 0.28,
			Thickness = 1,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = IndexTheme.Fonts.Label,
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextColor3 = textColor,
			TextScaled = true,
			TextSize = textSize or 12,
			TextStrokeColor3 = SHADOW,
			TextStrokeTransparency = 0.42,
		}, {
			TextSizeConstraint = e("UITextSizeConstraint", {
				MaxTextSize = textSize or 12,
				MinTextSize = 7,
			}),
		}),
	})
end

local function CrewOverheadBillboard(props)
	local entry = props.entry or {}
	local rarityStyle = IndexTheme.getRarityStyle(entry.rarity)
	local variantStyle = getVariantStyle(entry, rarityStyle)
	local isSpawned = entry.kind == CrewOverhead.Kind.Spawned

	if isSpawned then
		local remaining = if entry.held == true then nil else tonumber(entry.remaining)
		local displayName = getVariantDisplayName(entry.displayName, variantStyle.variantLabel)
		return e(RewardOverheadBillboard, {
			adornee = entry.adornee,
			offsetY = 4.45,
			maxDistance = 54,
			title = displayName,
			typeLabel = "Crewmate",
			extraLabel = variantStyle.variantLabel,
			extraColor = variantStyle.variantAccent,
			metaLabel = variantStyle.rarityLabel,
			helperText = "Recruit / Extract",
			remaining = remaining,
			totalSeconds = tonumber(entry.despawnSeconds),
			accentColor = variantStyle.border,
			metaColor = variantStyle.rarityAccent,
			panelFill = variantStyle.panelFill,
			panelStart = variantStyle.panelStart,
			panelEnd = variantStyle.panelEnd,
			glowTransparency = variantStyle.glowTransparency,
		})
	end

	local hasSlotBonus = tostring(entry.slotBonusLabel or "") ~= "" and (tonumber(entry.slotBonusPercent) or 0) > 0
	local mobile = isMobileViewport()
	local hasVariant = variantStyle.variantLabel ~= nil
	local protectionType = tostring(entry.protectionType or "none")
	local protectionStyle = getProtectionStyle(protectionType)
	local hasProtection = protectionStyle ~= nil
	local isPermanentProtection = protectionType == "permanent"
	local protectionLabel = if hasProtection and tostring(entry.protectionLabel or "") ~= ""
		then tostring(entry.protectionLabel)
		else if protectionStyle then protectionStyle.label else ""
	local protectionDetail = if hasProtection and tostring(entry.protectionDetail or "") ~= ""
		then tostring(entry.protectionDetail)
		else if protectionStyle then protectionStyle.detail else ""
	local protectionBadgeText = if protectionDetail ~= "" and not mobile
		then protectionLabel .. " | " .. protectionDetail
		else protectionLabel
	local protectionBadgeDisplayText = if protectionType == "crew"
		then SHIELD_GLYPH .. " " .. protectionBadgeText
		else protectionBadgeText
	local incomeColor = if entry.beliBoosted == true then BOOST_GOLD else GOLD
	local rarityPillWidth = if mobile then 72 else 92
	local variantPillWidth = if hasVariant then (if mobile then 58 else 70) else 0
	local layoutWidth = if mobile then PLACED_LAYOUT_WIDTH_MOBILE else PLACED_LAYOUT_WIDTH_DESKTOP
	local rowGap = 4
	local protectionRowHeight = if hasProtection then 18 else 0
	local protectionExtraHeight = if hasProtection then protectionRowHeight + rowGap else 0
	local layoutHeight = PLACED_LAYOUT_HEIGHT + protectionExtraHeight
	local billboardStudWidth = if mobile then PLACED_WORLD_WIDTH_MOBILE_STUDS else PLACED_WORLD_WIDTH_DESKTOP_STUDS
	local billboardStudHeight = PLACED_WORLD_HEIGHT_STUDS + (if hasProtection then 0.52 else 0)
	local panelPaddingX = 12
	local panelPaddingY = 6
	local nameRowHeight = 22
	local pillHeight = 22
	local incomeRowHeight = 20
	local slotBonusRowHeight = 16
	local nameTextSize = 16
	local labelTextSize = if mobile then 10 else 12
	local incomeTextSize = 14
	local metaTextSize = 11
	local protectionTextSize = if mobile then 10 else 11
	local contentLayoutWidth = layoutWidth - (panelPaddingX * 2)
	local contentLayoutHeight = layoutHeight - (panelPaddingY * 2)
	local displayName = getVariantDisplayName(entry.displayName, variantStyle.variantLabel)
	local panelStrokeColor = if isPermanentProtection then PERMANENT_GOLD else variantStyle.border
	local panelFill = if isPermanentProtection
		then blendColor(variantStyle.panelFill, PERMANENT_PURPLE, 0.12)
		else variantStyle.panelFill
	local panelStart = if isPermanentProtection
		then blendColor(variantStyle.panelStart, PERMANENT_PURPLE, 0.22)
		else variantStyle.panelStart
	local panelEnd = if isPermanentProtection
		then blendColor(variantStyle.panelEnd, PERMANENT_GOLD, 0.1)
		else variantStyle.panelEnd
	local showPanelGlow = hasVariant or isPermanentProtection
	local panelGlowTransparency = if isPermanentProtection then 0.66 else variantStyle.glowTransparency
	local panelGlowThickness = if isPermanentProtection then 4 else 3

	return e("BillboardGui", {
		Adornee = entry.adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 92,
		Size = UDim2.fromScale(billboardStudWidth, billboardStudHeight),
		StudsOffsetWorldSpace = Vector3.new(0, 4.45, 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Panel = e("Frame", {
			BackgroundColor3 = panelFill,
			BackgroundTransparency = 0.14,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = panelStrokeColor,
				Transparency = 0,
				Thickness = if isPermanentProtection then 2 else if hasVariant then 1.65 else 1.35,
			}),
			Glow = if showPanelGlow
				then e("Frame", {
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					Size = UDim2.fromScale(1, 1),
					ZIndex = 0,
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(0, 10),
					}),
					Stroke = e("UIStroke", {
						ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						Color = panelStrokeColor,
						Transparency = panelGlowTransparency,
						Thickness = panelGlowThickness,
					}),
				})
				else nil,
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, panelStart),
					ColorSequenceKeypoint.new(1, panelEnd),
				}),
			}),
			Content = e("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
			}, {
				Padding = e("UIPadding", {
					PaddingBottom = UDim.new(proportion(panelPaddingY, layoutHeight), 0),
					PaddingLeft = UDim.new(proportion(panelPaddingX, layoutWidth), 0),
					PaddingRight = UDim.new(proportion(panelPaddingX, layoutWidth), 0),
					PaddingTop = UDim.new(proportion(panelPaddingY, layoutHeight), 0),
				}),
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(proportion(rowGap, contentLayoutHeight), 0),
					SortOrder = Enum.SortOrder.LayoutOrder,
					VerticalAlignment = Enum.VerticalAlignment.Top,
				}),
				NameRow = e("Frame", {
					BackgroundTransparency = 1,
					LayoutOrder = 1,
					Size = UDim2.fromScale(1, proportion(nameRowHeight, contentLayoutHeight)),
				}, {
					Label = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = IndexTheme.Fonts.Display,
						Size = UDim2.fromScale(1, 1),
						Text = displayName,
						TextColor3 = TEXT,
						TextScaled = true,
						TextSize = nameTextSize,
						TextStrokeColor3 = SHADOW,
						TextStrokeTransparency = 0.28,
						TextTruncate = Enum.TextTruncate.AtEnd,
						TextXAlignment = Enum.TextXAlignment.Left,
					}, {
						TextSizeConstraint = e("UITextSizeConstraint", {
							MaxTextSize = nameTextSize,
							MinTextSize = 8,
						}),
					}),
				}),
				PillRow = e("Frame", {
					BackgroundTransparency = 1,
					LayoutOrder = 2,
					Size = UDim2.fromScale(1, proportion(pillHeight, contentLayoutHeight)),
				}, {
					Layout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
						Padding = UDim.new(proportion(8, contentLayoutWidth), 0),
						SortOrder = Enum.SortOrder.LayoutOrder,
						VerticalAlignment = Enum.VerticalAlignment.Center,
					}),
					Variant = if hasVariant
						then pill(
							variantStyle.variantLabel,
							variantStyle.variantAccent,
							UDim2.fromScale(proportion(variantPillWidth, contentLayoutWidth), 1),
							labelTextSize,
							1
						)
						else nil,
					Rarity = pill(
						variantStyle.rarityLabel,
						variantStyle.rarityAccent,
						UDim2.fromScale(proportion(rarityPillWidth, contentLayoutWidth), 1),
						labelTextSize,
						2
					),
				}),
				IncomeRow = e("Frame", {
					BackgroundTransparency = 1,
					LayoutOrder = 3,
					Size = UDim2.fromScale(1, proportion(incomeRowHeight, contentLayoutHeight)),
				}, {
					Label = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = IndexTheme.Fonts.Display,
						Size = UDim2.fromScale(1, 1),
						Text = formatIncome(entry.incomePerSecond),
						TextColor3 = incomeColor,
						TextScaled = true,
						TextSize = incomeTextSize,
						TextStrokeColor3 = SHADOW,
						TextStrokeTransparency = 0.3,
						TextXAlignment = Enum.TextXAlignment.Right,
					}, {
						TextSizeConstraint = e("UITextSizeConstraint", {
							MaxTextSize = incomeTextSize,
							MinTextSize = 8,
						}),
					}),
				}),
				ProtectionRow = if hasProtection
					then e("Frame", {
						BackgroundColor3 = protectionStyle.fill,
						BackgroundTransparency = 0.02,
						BorderSizePixel = 0,
						LayoutOrder = 4,
						Size = UDim2.fromScale(1, proportion(protectionRowHeight, contentLayoutHeight)),
					}, {
						Corner = e("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
						Stroke = e("UIStroke", {
							Color = protectionStyle.border,
							Transparency = if isPermanentProtection then 0.08 else 0.24,
							Thickness = if isPermanentProtection then 1.35 else 1,
						}),
						Label = e("TextLabel", {
							BackgroundTransparency = 1,
							Font = IndexTheme.Fonts.Label,
							Size = UDim2.fromScale(1, 1),
							Text = protectionBadgeDisplayText,
							TextColor3 = protectionStyle.textColor,
							TextScaled = true,
							TextSize = protectionTextSize,
							TextStrokeColor3 = SHADOW,
							TextStrokeTransparency = 0.38,
						}, {
							TextSizeConstraint = e("UITextSizeConstraint", {
								MaxTextSize = protectionTextSize,
								MinTextSize = 7,
							}),
						}),
					})
					else nil,
				SlotBonusRow = e("Frame", {
					BackgroundColor3 = blendColor(PANEL_FILL_SOFT, GOLD, 0.22),
					BackgroundTransparency = if hasSlotBonus then 0.02 else 1,
					BorderSizePixel = 0,
					LayoutOrder = 5,
					Size = UDim2.fromScale(1, proportion(slotBonusRowHeight, contentLayoutHeight)),
				}, {
					Corner = if hasSlotBonus
						then e("UICorner", {
							CornerRadius = UDim.new(1, 0),
						})
						else nil,
					Label = if hasSlotBonus
						then e("TextLabel", {
							BackgroundTransparency = 1,
							Font = IndexTheme.Fonts.Label,
							Size = UDim2.fromScale(1, 1),
							Text = string.format(
								"%s +%d%%",
								tostring(entry.slotBonusLabel),
								math.floor((tonumber(entry.slotBonusPercent) or 0) + 0.5)
							),
							TextColor3 = GOLD,
							TextScaled = true,
							TextSize = metaTextSize,
							TextStrokeColor3 = SHADOW,
							TextStrokeTransparency = 0.4,
						}, {
							TextSizeConstraint = e("UITextSizeConstraint", {
								MaxTextSize = metaTextSize,
								MinTextSize = 7,
							}),
						})
						else nil,
				}),
			}),
		}),
	})
end

return CrewOverheadBillboard
