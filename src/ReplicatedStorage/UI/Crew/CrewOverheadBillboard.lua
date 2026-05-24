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
local SHADOW = Color3.fromRGB(0, 0, 0)

local function formatIncome(value)
	return CurrencyUtil.formatIncomeCompactPerSecond(math.max(0, tonumber(value) or 0))
end

local function blendColor(baseColor, accentColor, alpha)
	return baseColor:Lerp(accentColor, math.clamp(alpha or 0, 0, 1))
end

local function isMobileViewport()
	return Responsive.isMobile()
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

local function inferVariantFromDisplayName(displayName)
	local name = tostring(displayName or "")
	for _, variantName in ipairs(CrewVariantsCfg.Order or {}) do
		variantName = tostring(variantName or "")
		if variantName ~= "" and variantName ~= "Normal" then
			local prefix = getVariantPrefix(variantName)
			if startsWith(name, prefix) then
				return variantName
			end
		end
	end

	return nil
end

local function getEntryVariantLabel(entry)
	local rawVariant = entry.variant
	if rawVariant ~= nil then
		local variant = tostring(rawVariant)
		if variant ~= "" and variant ~= "Normal" then
			return variant
		end

		return nil
	end

	return inferVariantFromDisplayName(entry.displayName)
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

local function pill(text, textColor, size, position, textSize)
	return e("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = blendColor(PANEL_FILL_SOFT, textColor, 0.18),
		BackgroundTransparency = 0.03,
		BorderSizePixel = 0,
		Position = position,
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
			TextSize = textSize or 12,
			TextStrokeColor3 = SHADOW,
			TextStrokeTransparency = 0.42,
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
	local panelHeight = if hasSlotBonus then 82 else 58
	local hasVariant = variantStyle.variantLabel ~= nil
	local incomeColor = if entry.beliBoosted == true then BOOST_GOLD else GOLD
	local rarityPillWidth = if mobile then 72 else 92
	local variantPillWidth = if hasVariant then (if mobile then 58 else 70) else 0
	local rarityPillX = if hasVariant then (if mobile then 74 else 86) else 10
	local billboardWidth = if hasVariant then 252 else 228
	local incomeWidth = if hasVariant then 84 else 112
	local billboardScale = 0.84
	local pillHeight = if mobile then 18 else 22
	local pillY = 40
	local nameTextSize = 16
	local labelTextSize = if mobile then 10 else 12
	local incomeTextSize = 14
	local metaTextSize = 11
	local displayName = getVariantDisplayName(entry.displayName, variantStyle.variantLabel)

	return e("BillboardGui", {
		Adornee = entry.adornee,
		AlwaysOnTop = true,
		LightInfluence = 0,
		MaxDistance = 92,
		Size = UDim2.fromOffset(math.floor(billboardWidth * billboardScale), math.floor(panelHeight * billboardScale)),
		StudsOffsetWorldSpace = Vector3.new(0, 4.05, 0),
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Panel = e("Frame", {
			BackgroundColor3 = variantStyle.panelFill,
			BackgroundTransparency = 0.14,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
		}, {
			Scale = e("UIScale", {
				Scale = billboardScale,
			}),
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 10),
			}),
			Stroke = e("UIStroke", {
				Color = variantStyle.border,
				Transparency = 0,
				Thickness = if hasVariant then 1.65 else 1.35,
			}),
			Glow = if hasVariant
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
						Color = variantStyle.border,
						Transparency = variantStyle.glowTransparency,
						Thickness = 3,
					}),
				})
				else nil,
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, variantStyle.panelStart),
					ColorSequenceKeypoint.new(1, variantStyle.panelEnd),
				}),
			}),
			Name = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = IndexTheme.Fonts.Display,
				Position = UDim2.fromOffset(10, 5),
				Size = UDim2.new(1, -20, 0, 22),
				Text = displayName,
				TextColor3 = TEXT,
				TextSize = nameTextSize,
				TextStrokeColor3 = SHADOW,
				TextStrokeTransparency = 0.28,
				TextTruncate = Enum.TextTruncate.AtEnd,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Variant = if hasVariant
				then pill(
					variantStyle.variantLabel,
					variantStyle.variantAccent,
					UDim2.fromOffset(variantPillWidth, pillHeight),
					UDim2.fromOffset(10, pillY),
					labelTextSize
				)
				else nil,
			Rarity = pill(
				variantStyle.rarityLabel,
				variantStyle.rarityAccent,
				UDim2.fromOffset(rarityPillWidth, pillHeight),
				UDim2.fromOffset(rarityPillX, pillY),
				labelTextSize
			),
			Income = e("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 1,
				Font = IndexTheme.Fonts.Display,
				Position = UDim2.new(1, -10, 0, pillY),
				Size = UDim2.fromOffset(incomeWidth, pillHeight),
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
					MinTextSize = 7,
				}),
			}),
			SlotBonus = if hasSlotBonus
				then e("Frame", {
					BackgroundColor3 = blendColor(PANEL_FILL_SOFT, GOLD, 0.22),
					BackgroundTransparency = 0.02,
					BorderSizePixel = 0,
					Position = UDim2.fromOffset(10, 58),
					Size = UDim2.new(1, -20, 0, 16),
				}, {
					Corner = e("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					Label = e("TextLabel", {
						BackgroundTransparency = 1,
						Font = IndexTheme.Fonts.Label,
						Size = UDim2.fromScale(1, 1),
						Text = string.format(
							"%s +%d%%",
							tostring(entry.slotBonusLabel),
							math.floor((tonumber(entry.slotBonusPercent) or 0) + 0.5)
						),
						TextColor3 = GOLD,
						TextSize = metaTextSize,
						TextStrokeColor3 = SHADOW,
						TextStrokeTransparency = 0.4,
					}),
				})
				else nil,
		}),
	})
end

return CrewOverheadBillboard
