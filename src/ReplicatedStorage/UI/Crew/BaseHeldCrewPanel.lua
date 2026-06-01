local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local React = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("React"))
local PreviewViewport = require(
	script.Parent.Parent:WaitForChild("Index"):WaitForChild("Components"):WaitForChild("PreviewViewport")
)
local IndexTheme = require(script.Parent.Parent:WaitForChild("Index"):WaitForChild("Theme"))

local e = React.createElement

local CREW_RARITY_ORDER = {
	"Omega",
	"Secret",
	"Godly",
	"Mythic",
	"Mythical",
	"Legendary",
	"Epic",
	"Rare",
	"Uncommon",
	"Common",
}
local CREW_RARITY_ALIASES = {
	Mythical = "Mythic",
}

local PALETTE = {
	Ink = Color3.fromRGB(9, 9, 11),
	Glass = Color3.fromRGB(29, 28, 33),
	GlassDeep = Color3.fromRGB(15, 15, 18),
	Border = Color3.fromRGB(218, 230, 238),
	Text = Color3.fromRGB(230, 234, 241),
	MutedText = Color3.fromRGB(176, 177, 187),
	Gold = Color3.fromRGB(218, 177, 91),
	Ready = Color3.fromRGB(106, 255, 138),
	Store = Color3.fromRGB(218, 177, 91),
	StoreDisabled = Color3.fromRGB(86, 81, 71),
}

local function formatStat(value)
	local numberValue = tonumber(value)
	if numberValue == nil then
		return nil
	end
	if math.floor(numberValue) == numberValue then
		return tostring(numberValue)
	end
	return string.format("%.1f", numberValue)
end

local function getDisplayName(item)
	if typeof(item) ~= "table" then
		return "Crewmate"
	end

	local displayName = item.DisplayName or item.displayName or item.Name or item.name
	if typeof(displayName) == "string" and displayName ~= "" then
		return displayName
	end

	return "Crewmate"
end

local function normalizeCrewRarity(rarity)
	local value = tostring(rarity or "")
	if value == "" then
		return "Common"
	end
	if IndexTheme.RarityStyles[value] ~= nil then
		return value
	end

	for _, rarityName in ipairs(CREW_RARITY_ORDER) do
		if value == rarityName or string.sub(value, -#rarityName) == rarityName then
			return CREW_RARITY_ALIASES[rarityName] or rarityName
		end
	end

	return CREW_RARITY_ALIASES[value] or value
end

local function getCrewRarity(item)
	if typeof(item) ~= "table" then
		return "Common"
	end

	return normalizeCrewRarity(item.Rarity or item.rarity or item.CanonicalRarity or item.canonicalRarity)
end

local function getCrewRarityStyle(item)
	return IndexTheme.getRarityStyle(getCrewRarity(item))
end

local function getPreviewName(item)
	if typeof(item) ~= "table" then
		return "Crewmate"
	end

	local previewName = item.PreviewName
		or item.previewName
		or item.ModelName
		or item.modelName
		or item.BaseName
		or item.baseName
		or item.CrewMemberId
		or item.crewMemberId
		or getDisplayName(item)
	if typeof(previewName) == "string" and previewName ~= "" then
		return previewName
	end

	return getDisplayName(item)
end

local function getMetaText(item)
	local parts = {}
	local level = formatStat(item.Level or item.level)
	local income = formatStat(item.Income or item.income)

	if level ~= nil then
		parts[#parts + 1] = "Lv " .. level
	end
	if income ~= nil then
		parts[#parts + 1] = CurrencyUtil.formatIncomeCompactPerSecond(income)
	end

	return if #parts > 0 then table.concat(parts, "  |  ") else "Ready"
end

local function getVariantTag(item)
	if typeof(item) ~= "table" then
		return ""
	end

	local tag = tostring(item.VariantTag or item.variantTag or "")
	if tag == "" then
		tag = tostring(item.VariantDisplayName or item.variantDisplayName or item.Variant or item.variant or "")
	end
	if tag == "" or tag == "Normal" then
		return ""
	end
	return tag
end

local function statChip(text, textColor, width, layoutOrder, zIndex)
	return e("Frame", {
		BackgroundColor3 = PALETTE.GlassDeep,
		BackgroundTransparency = 0.06,
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
		Size = UDim2.fromOffset(width, 17),
		ZIndex = zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Stroke = e("UIStroke", {
			Color = textColor,
			Thickness = 1,
			Transparency = 0.28,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Size = UDim2.fromScale(1, 1),
			Text = text,
			TextColor3 = textColor,
			TextScaled = true,
			TextStrokeColor3 = PALETTE.Ink,
			TextStrokeTransparency = 0.48,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = zIndex + 1,
		}, {
			TextSizeConstraint = e("UITextSizeConstraint", {
				MaxTextSize = 10,
				MinTextSize = 6,
			}),
		}),
	})
end

local function baseHeldSlot(props)
	local item = props.item or {}
	local compact = props.compact == true
	local zIndex = props.zIndex or 1
	local displayName = getDisplayName(item)
	local rarity = getCrewRarity(item)
	local rarityStyle = getCrewRarityStyle(item)
	local rarityColor = if rarityStyle and typeof(rarityStyle.textColor) == "Color3" then rarityStyle.textColor else PALETTE.Ready
	local strokeColor = if rarityStyle and typeof(rarityStyle.borderColor) == "Color3" then rarityStyle.borderColor else PALETTE.Gold
	local variantTag = getVariantTag(item)
	local variant = item.Variant or item.variant or variantTag
	local previewName = getPreviewName(item)
	local previewSize = compact and 56 or 76
	local previewLeft = compact and 36 or 42
	local textLeft = compact and 94 or 124
	local nameY = compact and 14 or 18
	local rarityY = compact and 38 or 46
	local metaY = compact and 57 or 68

	return e("Frame", {
		BackgroundColor3 = PALETTE.Ink,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Size = UDim2.fromScale(1, 1),
		ZIndex = zIndex,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, PALETTE.Glass),
				ColorSequenceKeypoint.new(1, PALETTE.Ink),
			}),
		}),
		Stroke = e("UIStroke", {
			Color = strokeColor,
			Thickness = 1.75,
			Transparency = 0.18,
		}),
		NumberBadge = e("Frame", {
			BackgroundColor3 = PALETTE.GlassDeep,
			BackgroundTransparency = 0.06,
			BorderSizePixel = 0,
			Position = UDim2.fromOffset(7, 7),
			Size = UDim2.fromOffset(compact and 18 or 22, compact and 18 or 22),
			ZIndex = zIndex + 3,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
			Stroke = e("UIStroke", {
				Color = strokeColor,
				Thickness = 1,
				Transparency = 0.22,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Size = UDim2.fromScale(1, 1),
				Text = "1",
				TextColor3 = PALETTE.Text,
				TextSize = compact and 10 or 12,
				TextStrokeColor3 = PALETTE.Ink,
				TextStrokeTransparency = 0.45,
				ZIndex = zIndex + 4,
			}),
		}),
		Preview = e("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Position = UDim2.new(0, previewLeft, 0.5, 0),
			Size = UDim2.fromOffset(previewSize, previewSize),
			ZIndex = zIndex + 2,
		}, {
			Preview = e(PreviewViewport, {
				anchorPoint = Vector2.new(0.5, 0.5),
				animateCrewIdle = true,
				crewMemberId = item.CrewMemberId or item.crewMemberId,
				fieldOfView = 34,
				gender = item.Gender or item.gender,
				position = UDim2.fromScale(0.5, 0.52),
				preferModel = variantTag ~= "",
				previewKind = "CrewMember",
				previewName = previewName,
				scaleType = Enum.ScaleType.Fit,
				showCrewAura = variantTag ~= "",
				size = UDim2.fromScale(1, 1),
				variant = variant,
				zIndex = zIndex + 2,
			}),
		}),
		Name = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(textLeft, nameY),
			Size = UDim2.new(1, -(textLeft + 12), 0, compact and 18 or 22),
			Text = displayName,
			TextColor3 = PALETTE.Text,
			TextSize = compact and 13 or 15,
			TextStrokeColor3 = PALETTE.Ink,
			TextStrokeTransparency = 0.48,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = zIndex + 3,
		}),
		Tags = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(textLeft, rarityY),
			Size = UDim2.new(1, -(textLeft + 12), 0, compact and 14 or 16),
			ZIndex = zIndex + 3,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding = UDim.new(0, 5),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
			Rarity = statChip(rarity, rarityColor, compact and 58 or 70, 1, zIndex + 3),
			Variant = variantTag ~= "" and statChip(variantTag, strokeColor, compact and 54 or 64, 2, zIndex + 3) or nil,
		}),
		Meta = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Position = UDim2.fromOffset(textLeft, metaY),
			Size = UDim2.new(1, -(textLeft + 12), 0, compact and 13 or 15),
			Text = getMetaText(item),
			TextColor3 = PALETTE.MutedText,
			TextSize = compact and 9 or 10,
			TextStrokeColor3 = PALETTE.Ink,
			TextStrokeTransparency = 0.58,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = zIndex + 3,
		}),
	})
end

local function BaseHeldCrewPanel(props)
	if props.visible ~= true then
		return nil
	end

	local item = props.item or {}
	local pending = props.pending == true
	local compact = props.compact == true
	local width = if compact then 270 else 318
	local height = if compact then 140 else 176
	local bottomOffset = if compact then 270 else 392
	local rightOffset = if compact then 12 else 24
	local slotTop = if compact then 22 else 24
	local slotHeight = if compact then 78 else 100
	local buttonHeight = if compact then 26 else 32
	local buttonTop = height - buttonHeight - (if compact then 10 else 12)

	return e("Frame", {
		Active = false,
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = PALETTE.Glass,
		BackgroundTransparency = 0.14,
		BorderSizePixel = 0,
		ClipsDescendants = false,
		Position = UDim2.new(1, -rightOffset, 1, -bottomOffset),
		Size = UDim2.fromOffset(width, height),
		ZIndex = 60,
	}, {
		Scale = e("UIScale", {
			Scale = compact and 0.9 or 1,
		}),
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, PALETTE.Glass),
				ColorSequenceKeypoint.new(1, PALETTE.GlassDeep),
			}),
		}),
		Stroke = e("UIStroke", {
			Color = PALETTE.Gold,
			Thickness = 1.5,
			Transparency = 0.3,
		}),
		HeaderTab = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundColor3 = PALETTE.GlassDeep,
			BorderSizePixel = 0,
			Position = UDim2.new(0.5, 0, 0, 4),
			Size = UDim2.fromOffset(96, 22),
			ZIndex = 66,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.Gold,
				Thickness = 1,
				Transparency = 0.34,
			}),
			Label = e("TextLabel", {
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBlack,
				Size = UDim2.fromScale(1, 1),
				Text = "IN HAND",
				TextColor3 = PALETTE.Text,
				TextSize = 12,
				TextStrokeColor3 = PALETTE.Ink,
				TextStrokeTransparency = 0.45,
				ZIndex = 67,
			}),
		}),
		Slot = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(10, slotTop),
			Size = UDim2.new(1, -20, 0, slotHeight),
			ZIndex = 61,
		}, {
			Card = e(baseHeldSlot, {
				compact = compact,
				item = item,
				zIndex = 62,
			}),
		}),
		Store = e("TextButton", {
			AutoButtonColor = pending ~= true,
			BackgroundColor3 = if pending then PALETTE.StoreDisabled else PALETTE.Store,
			BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack,
			Position = UDim2.fromOffset(10, buttonTop),
			Size = UDim2.new(1, -20, 0, buttonHeight),
			Text = if pending then "STORING..." else "STORE",
			TextColor3 = PALETTE.Ink,
			TextSize = compact and 12 or 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 64,
			[React.Event.Activated] = function()
				if pending ~= true and props.onStore then
					props.onStore(item)
				end
			end,
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 8),
			}),
			Stroke = e("UIStroke", {
				Color = PALETTE.Border,
				Thickness = 1,
				Transparency = if pending then 0.72 else 0.28,
			}),
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(245, 219, 139)),
					ColorSequenceKeypoint.new(1, PALETTE.Store),
				}),
			}),
		}),
	})
end

return BaseHeldCrewPanel
