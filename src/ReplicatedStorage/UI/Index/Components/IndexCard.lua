local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local React = require(Packages:WaitForChild("React"))

local Theme = require(script.Parent.Parent:WaitForChild("Theme"))
local PreviewViewport = require(script.Parent:WaitForChild("PreviewViewport"))

local e = React.createElement

local FOOTER_HEIGHT = 50
local CARD_CORNER_RADIUS = UDim.new(0, 11)
local IMAGE_CORNER_RADIUS = UDim.new(0, 9)
local DEFAULT_CARD_BACKGROUND_TRANSPARENCY = 0.18
local FRUIT_CARD_BACKGROUND_TRANSPARENCY = 0.26
local FRUIT_BACKDROP_BACKGROUND_TRANSPARENCY = 0.28
local LOCKED_FRUIT_SILHOUETTE_COLOR = Color3.fromRGB(6, 7, 9)
local LOCKED_FRUIT_RIM_COLOR = Color3.fromRGB(215, 175, 86)
local LOCKED_FRUIT_AMBIENT = Color3.fromRGB(28, 30, 36)
local LOCKED_FRUIT_LIGHT = Color3.fromRGB(58, 54, 46)
local LOCKED_FRUIT_RIM_AMBIENT = Color3.fromRGB(16, 14, 11)
local LOCKED_FRUIT_RIM_LIGHT = Color3.fromRGB(82, 68, 34)
local LOCKED_CREW_SILHOUETTE_COLOR = Color3.fromRGB(0, 0, 0)
local LOCKED_CREW_AMBIENT = Color3.fromRGB(4, 4, 5)
local LOCKED_CREW_LIGHT = Color3.fromRGB(10, 10, 12)
local BLACK = Color3.fromRGB(0, 0, 0)
local PREVIEW_ANCHOR = Vector2.new(0.5, 0.5)
local PREVIEW_POSITION = UDim2.fromScale(0.5, 0.54)
local PREVIEW_SIZE = UDim2.fromScale(0.82, 0.82)
local IMAGE_SHADOW_POSITION = UDim2.fromScale(0.5, 0.58)
local IMAGE_SHADOW_SIZE = UDim2.fromScale(0.84, 0.84)
local INDEX_STATIC_PREVIEW_SCALE = 1.18
local INDEX_STATIC_PREVIEW_SIZE = UDim2.fromScale(INDEX_STATIC_PREVIEW_SCALE, INDEX_STATIC_PREVIEW_SCALE)
local INDEX_STATIC_PREVIEW_SCALE_OVERRIDES = {}
local INDEX_STATIC_PREVIEW_OVERRIDE_KEYS = {
	"displayName",
	"id",
	"baseName",
	"name",
	"previewName",
}

local function getIndexStaticPreviewSize(unit)
	for _, key in ipairs(INDEX_STATIC_PREVIEW_OVERRIDE_KEYS) do
		local scale = INDEX_STATIC_PREVIEW_SCALE_OVERRIDES[tostring(unit[key] or "")]
		if scale then
			return UDim2.fromScale(scale, scale)
		end
	end

	return INDEX_STATIC_PREVIEW_SIZE
end

local function fallbackSilhouette()
	return e("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, {
		Head = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.34),
			Size = UDim2.fromOffset(34, 34),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(1, 0),
			}),
		}),
		Body = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0.5, 0.48),
			Size = UDim2.fromOffset(54, 48),
		}, {
			Corner = e("UICorner", {
				CornerRadius = UDim.new(0, 12),
			}),
		}),
	})
end

local function previewDropShadow()
	return e("Frame", {
		AnchorPoint = PREVIEW_ANCHOR,
		BackgroundColor3 = BLACK,
		BackgroundTransparency = 0.72,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.82),
		Size = UDim2.fromScale(0.58, 0.14),
		ZIndex = 1,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(1, 0),
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.45),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
end

local function footerLabel(props)
	return e("TextLabel", {
		BackgroundTransparency = 1,
		Font = props.font,
		Position = props.position,
		Size = props.size,
		Text = props.text,
		TextColor3 = props.textColor,
		TextSize = props.textSize,
		TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
		TextStrokeTransparency = props.textStrokeTransparency or 0.45,
		TextWrapped = props.textWrapped == true,
		TextXAlignment = props.textXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.textYAlignment or Enum.TextYAlignment.Center,
	})
end

local function productionBadge(text)
	return e("Frame", {
		BackgroundColor3 = Theme.Palette.BadgeFill,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.fromOffset(72, 22),
		ZIndex = 4,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 7),
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.BadgeStroke,
			Transparency = 0.14,
			Thickness = 1,
		}),
		Label = e("TextLabel", {
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Size = UDim2.fromScale(1, 1),
			Text = tostring(text or ""),
			TextColor3 = Theme.Palette.BadgeText,
			TextSize = 11,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.45,
		}),
	})
end

local function createRaritySheen(rarityStyle, hovered)
	local sheenHeight = hovered and (rarityStyle.hoverSheenHeight or rarityStyle.sheenHeight) or rarityStyle.sheenHeight
	if not sheenHeight or sheenHeight <= 0 then
		return nil
	end

	local topTransparency = hovered and (rarityStyle.hoverSheenTopTransparency or rarityStyle.sheenTopTransparency)
		or rarityStyle.sheenTopTransparency
	if topTransparency == nil or topTransparency >= 1 then
		return nil
	end

	return e("Frame", {
		BackgroundColor3 = rarityStyle.gradientStart,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(6, 6),
		Size = UDim2.new(1, -12, 0, sheenHeight),
		ZIndex = 2,
	}, {
		Corner = e("UICorner", {
			CornerRadius = UDim.new(0, 8),
		}),
		Gradient = e("UIGradient", {
			Rotation = rarityStyle.sheenRotation or 0,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rarityStyle.gradientStart),
				ColorSequenceKeypoint.new(1, rarityStyle.gradientEnd),
			}),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, topTransparency),
				NumberSequenceKeypoint.new(0.45, math.min(1, topTransparency + 0.12)),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
end

local function blendColor(baseColor, accentColor, alpha)
	if typeof(baseColor) ~= "Color3" then
		return accentColor
	end

	if typeof(accentColor) ~= "Color3" then
		return baseColor
	end

	return baseColor:Lerp(accentColor, math.clamp(alpha or 0, 0, 1))
end

local function getDiscoveredCardAppearance(unit, rarityStyle, hovered)
	local appearance = {
		shellStart = Theme.Palette.CardShellSoft,
		shellEnd = Theme.Palette.CardShell,
		backdropStart = Theme.Palette.SectionSoft,
		backdropEnd = Theme.Palette.Section,
		backdropFill = Theme.Palette.Section,
		showRaritySheen = true,
	}

	if rarityStyle then
		local isFruit = unit and unit.itemKind == "DevilFruit"
		local shellWeight = isFruit and (hovered and 0.42 or 0.36) or (hovered and 0.36 or 0.3)
		local backdropStartWeight = isFruit and (hovered and 0.62 or 0.56) or (hovered and 0.56 or 0.48)
		local backdropEndWeight = isFruit and (hovered and 0.54 or 0.48) or (hovered and 0.48 or 0.4)
		local backdropFillWeight = isFruit and (hovered and 0.38 or 0.32) or (hovered and 0.34 or 0.28)

		appearance.shellStart = blendColor(appearance.shellStart, rarityStyle.gradientStart, shellWeight)
		appearance.shellEnd = blendColor(appearance.shellEnd, rarityStyle.gradientEnd, shellWeight * 0.8)
		appearance.backdropStart = blendColor(appearance.backdropStart, rarityStyle.gradientStart, backdropStartWeight)
		appearance.backdropEnd = blendColor(appearance.backdropEnd, rarityStyle.gradientEnd, backdropEndWeight)
		appearance.backdropFill = blendColor(appearance.backdropFill, rarityStyle.borderColor, backdropFillWeight)
		appearance.showRaritySheen = false
	end

	return appearance
end

local function imageAreaShell(children, rarityStyle, hovered, appearance)
	appearance = appearance or {}
	local shellChildren = {
		Corner = e("UICorner", {
			CornerRadius = IMAGE_CORNER_RADIUS,
		}),
		Gradient = e("UIGradient", {
			Rotation = 125,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, appearance.backdropStart or Theme.Palette.CardBackdropSoft),
				ColorSequenceKeypoint.new(1, appearance.backdropEnd or Theme.Palette.CardBackdrop),
			}),
		}),
		Vignette = e("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
		}, {
			Gradient = e("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 0, 0)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.68, 1),
					NumberSequenceKeypoint.new(1, 0.18),
				}),
			}),
		}),
	}

	local raritySheen = appearance.showRaritySheen ~= false and rarityStyle and createRaritySheen(rarityStyle, hovered)
	if raritySheen then
		shellChildren.RaritySheen = raritySheen
	end

	for key, value in pairs(children) do
		shellChildren[key] = value
	end

	return shellChildren
end

local function footer(rarityText, nameText, rarityColor)
	return e("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Theme.Palette.CardFooter,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 4, 1, -4),
		Size = UDim2.new(1, -8, 0, FOOTER_HEIGHT),
	}, {
		Corner = e("UICorner", {
			CornerRadius = IMAGE_CORNER_RADIUS,
		}),
		Stroke = e("UIStroke", {
			Color = Theme.Palette.CardFooterStroke,
			Transparency = 0.12,
		}),
		Rarity = footerLabel({
			font = Theme.Fonts.Label,
			position = UDim2.fromOffset(8, 4),
			size = UDim2.new(1, -16, 0, 12),
			text = rarityText,
			textColor = rarityColor,
			textSize = 10,
		}),
		Name = footerLabel({
			font = Theme.Fonts.Display,
			position = UDim2.fromOffset(8, 17),
			size = UDim2.new(1, -16, 0, 26),
			text = nameText,
			textColor = Theme.Palette.Text,
			textSize = 15,
			textWrapped = true,
			textYAlignment = Enum.TextYAlignment.Top,
		}),
	})
end

local function baseCard(props)
	return e("Frame", {
		Active = true,
		BackgroundColor3 = Theme.Palette.CardShell,
		BackgroundTransparency = props.backgroundTransparency or DEFAULT_CARD_BACKGROUND_TRANSPARENCY,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		LayoutOrder = props.layoutOrder or 0,
		Size = UDim2.fromScale(1, 1),
		[React.Event.MouseEnter] = props.onMouseEnter,
		[React.Event.MouseLeave] = props.onMouseLeave,
	}, props.children)
end

local function createRarityChrome(rarityStyle, hovered)
	local strokeTransparency = hovered and (rarityStyle.hoverStrokeTransparency or rarityStyle.strokeTransparency)
		or rarityStyle.strokeTransparency
	local strokeThickness = hovered and (rarityStyle.hoverStrokeThickness or rarityStyle.strokeThickness)
		or rarityStyle.strokeThickness

	local chromeChildren = {
		Stroke = e("UIStroke", {
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			Color = rarityStyle.borderColor,
			LineJoinMode = Enum.LineJoinMode.Round,
			Transparency = strokeTransparency,
			Thickness = strokeThickness,
		}),
	}

	local glowThickness = hovered and (rarityStyle.hoverGlowThickness or rarityStyle.glowThickness)
		or rarityStyle.glowThickness
	local glowTransparency = hovered and (rarityStyle.hoverGlowTransparency or rarityStyle.glowTransparency)
		or rarityStyle.glowTransparency

	if glowThickness and glowThickness > 0 and glowTransparency and glowTransparency < 1 then
		chromeChildren.GlowFrame = e("Frame", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
		}, {
			Corner = e("UICorner", {
				CornerRadius = CARD_CORNER_RADIUS,
			}),
			Stroke = e("UIStroke", {
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Color = rarityStyle.glowColor,
				LineJoinMode = Enum.LineJoinMode.Round,
				Transparency = glowTransparency,
				Thickness = glowThickness,
			}),
		})
	end

	return chromeChildren
end

local function createLockedImagePreview(image, unit, isFruit)
	if isFruit then
		return {
			Character = e("ImageLabel", {
				AnchorPoint = PREVIEW_ANCHOR,
				BackgroundTransparency = 1,
				Image = image,
				ImageColor3 = BLACK,
				ImageTransparency = 0,
				Position = PREVIEW_POSITION,
				ScaleType = Enum.ScaleType.Fit,
				Size = UDim2.fromScale(0.8, 0.8),
				ZIndex = 3,
			}),
		}
	end

	local previewSize = getIndexStaticPreviewSize(unit)
	return {
		Shadow = e("ImageLabel", {
			AnchorPoint = PREVIEW_ANCHOR,
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = BLACK,
			ImageTransparency = 0.3,
			Position = UDim2.fromScale(0.5, 0.56),
			ScaleType = Enum.ScaleType.Fit,
			Size = previewSize,
			ZIndex = 1,
		}),
		Character = e("ImageLabel", {
			AnchorPoint = PREVIEW_ANCHOR,
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = BLACK,
			ImageTransparency = 0,
			Position = UDim2.fromScale(0.5, 0.5),
			ScaleType = Enum.ScaleType.Fit,
			Size = previewSize,
			ZIndex = 3,
		}),
	}
end

local function createLockedCrewModelPreview(previewName, includeFallback)
	local previewChildren = {
		Shadow = e(PreviewViewport, {
			previewKind = "CrewMember",
			previewName = previewName,
			preferModel = true,
			size = UDim2.fromScale(0.86, 0.86),
			position = UDim2.fromScale(0.5, 0.57),
			anchorPoint = PREVIEW_ANCHOR,
			tintColor = BLACK,
			tintTransparency = 0.35,
			tintMaterial = Enum.Material.Plastic,
			ambient = LOCKED_CREW_AMBIENT,
			lightColor = LOCKED_CREW_LIGHT,
			lightDirection = Vector3.new(0.2, -0.2, -1),
			zIndex = 1,
		}),
		Character = e(PreviewViewport, {
			previewKind = "CrewMember",
			previewName = previewName,
			preferModel = true,
			size = UDim2.fromScale(0.84, 0.84),
			position = PREVIEW_POSITION,
			anchorPoint = PREVIEW_ANCHOR,
			tintColor = LOCKED_CREW_SILHOUETTE_COLOR,
			tintTransparency = 0,
			tintMaterial = Enum.Material.Plastic,
			ambient = LOCKED_CREW_AMBIENT,
			lightColor = LOCKED_CREW_LIGHT,
			lightDirection = Vector3.new(0.2, -0.2, -1),
			zIndex = 3,
		}),
	}

	if includeFallback then
		previewChildren.Fallback = fallbackSilhouette()
	end

	return previewChildren
end

local function createLockedPreview(unit, renderPreview)
	local isFruit = unit and unit.itemKind == "DevilFruit"

	if unit.previewKind and unit.previewName then
		if renderPreview == false then
			return {
				Fallback = fallbackSilhouette(),
			}
		end

		if isFruit then
			return {
				Rim = e(PreviewViewport, {
					previewKind = unit.previewKind,
					previewName = unit.previewName,
					size = UDim2.fromScale(0.88, 0.88),
					position = PREVIEW_POSITION,
					anchorPoint = PREVIEW_ANCHOR,
					tintColor = LOCKED_FRUIT_RIM_COLOR,
					tintTransparency = 0.74,
					tintMaterial = Enum.Material.Plastic,
					ambient = LOCKED_FRUIT_RIM_AMBIENT,
					lightColor = LOCKED_FRUIT_RIM_LIGHT,
					lightDirection = Vector3.new(0.15, -0.2, -1),
					zIndex = 2,
				}),
				Character = e(PreviewViewport, {
					previewKind = unit.previewKind,
					previewName = unit.previewName,
					size = UDim2.fromScale(0.84, 0.84),
					position = PREVIEW_POSITION,
					anchorPoint = PREVIEW_ANCHOR,
					tintColor = LOCKED_FRUIT_SILHOUETTE_COLOR,
					tintTransparency = 0,
					tintMaterial = Enum.Material.Plastic,
					ambient = LOCKED_FRUIT_AMBIENT,
					lightColor = LOCKED_FRUIT_LIGHT,
					lightDirection = Vector3.new(0.2, -0.25, -1),
					zIndex = 3,
				}),
			}
		end

		return createLockedCrewModelPreview(unit.previewName, true)
	end

	local crewModelName = tostring(unit.crewModelName or "")
	if not isFruit and crewModelName ~= "" and renderPreview ~= false then
		return createLockedCrewModelPreview(crewModelName, true)
	end

	local staticPreviewImage = tostring(unit.staticPreviewImage or "")
	if staticPreviewImage ~= "" then
		if isFruit then
			return createLockedImagePreview(staticPreviewImage, unit, isFruit)
		end

		return {
			Fallback = fallbackSilhouette(),
		}
	end

	if unit.image and unit.image ~= "" then
		if isFruit then
			return createLockedImagePreview(unit.image, unit, isFruit)
		end

		return {
			Fallback = fallbackSilhouette(),
		}
	end

	return {
		Fallback = fallbackSilhouette(),
	}
end

local function createStaticImagePreview(image, unit)
	local previewSize = getIndexStaticPreviewSize(unit)

	return {
		StaticPreviewImage = e("ImageLabel", {
			AnchorPoint = PREVIEW_ANCHOR,
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = Color3.new(1, 1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			ScaleType = Enum.ScaleType.Fit,
			Size = previewSize,
			ZIndex = 3,
		}),
		StaticPreviewShadow = e("ImageLabel", {
			AnchorPoint = PREVIEW_ANCHOR,
			BackgroundTransparency = 1,
			Image = image,
			ImageColor3 = BLACK,
			ImageTransparency = 0.7,
			Position = UDim2.fromScale(0.5, 0.5),
			ScaleType = Enum.ScaleType.Fit,
			Size = previewSize,
			ZIndex = 1,
		}),
	}
end

local function createDiscoveredPreview(unit, renderPreview, isFruit)
	local staticPreviewImage = tostring(unit.staticPreviewImage or "")
	if staticPreviewImage ~= "" then
		return createStaticImagePreview(staticPreviewImage, unit)
	end

	if unit.previewKind and unit.previewName then
		if renderPreview == false then
			return {
				Fallback = fallbackSilhouette(),
			}
		end

		return {
			Shadow = previewDropShadow(),
			Character = e(PreviewViewport, {
				previewKind = unit.previewKind,
				previewName = unit.previewName,
				size = PREVIEW_SIZE,
				position = PREVIEW_POSITION,
				anchorPoint = PREVIEW_ANCHOR,
				zIndex = 3,
			}),
		}
	end

	local crewModelName = tostring(unit.crewModelName or "")
	if not isFruit and crewModelName ~= "" and renderPreview ~= false then
		return {
			Fallback = fallbackSilhouette(),
			Shadow = previewDropShadow(),
			Character = e(PreviewViewport, {
				previewKind = "CrewMember",
				previewName = crewModelName,
				preferModel = true,
				size = PREVIEW_SIZE,
				position = PREVIEW_POSITION,
				anchorPoint = PREVIEW_ANCHOR,
				zIndex = 3,
			}),
		}
	end

	if unit.image and unit.image ~= "" then
		if isFruit then
			return {
				Character = e("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					Image = unit.image,
					ImageColor3 = Theme.Palette.Text,
					Position = UDim2.fromScale(0.5, 0.54),
					ScaleType = Enum.ScaleType.Fit,
					Size = UDim2.fromScale(0.8, 0.8),
					ZIndex = 3,
				}),
			}
		end

		return {
			Character = e("ImageLabel", {
				AnchorPoint = PREVIEW_ANCHOR,
				BackgroundTransparency = 1,
				Image = unit.image,
				ImageColor3 = Theme.Palette.Text,
				Position = PREVIEW_POSITION,
				ScaleType = Enum.ScaleType.Fit,
				Size = PREVIEW_SIZE,
				ZIndex = 3,
			}),
			Shadow = e("ImageLabel", {
				AnchorPoint = PREVIEW_ANCHOR,
				BackgroundTransparency = 1,
				Image = unit.image,
				ImageColor3 = BLACK,
				ImageTransparency = 0.7,
				Position = IMAGE_SHADOW_POSITION,
				ScaleType = Enum.ScaleType.Fit,
				Size = IMAGE_SHADOW_SIZE,
				ZIndex = 1,
			}),
		}
	end

	return {
		Character = fallbackSilhouette(),
	}
end

local function IndexCard(props)
	local unit = props.unit or {}
	local rarity = Theme.getRarityStyle(unit.rarity)
	local hovered, setHovered = React.useState(false)
	local isFruit = unit.itemKind == "DevilFruit"
	local cardBackgroundTransparency = isFruit and FRUIT_CARD_BACKGROUND_TRANSPARENCY
		or DEFAULT_CARD_BACKGROUND_TRANSPARENCY
	local backdropBackgroundTransparency = isFruit and FRUIT_BACKDROP_BACKGROUND_TRANSPARENCY
		or DEFAULT_CARD_BACKGROUND_TRANSPARENCY

	if not unit.discovered then
		local lockedChildren = createLockedPreview(unit, props.renderPreview)

		lockedChildren.Question = e("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Position = UDim2.new(1, -8, 0, 6),
			Size = UDim2.fromOffset(44, 18),
			Text = "???",
			TextColor3 = Theme.Palette.QuestionText,
			TextSize = 14,
			TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
			TextStrokeTransparency = 0.4,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 4,
		})

		return baseCard({
			backgroundTransparency = cardBackgroundTransparency,
			layoutOrder = props.layoutOrder,
			onMouseEnter = function()
				setHovered(true)
			end,
			onMouseLeave = function()
				setHovered(false)
			end,
			children = {
				Corner = e("UICorner", {
					CornerRadius = CARD_CORNER_RADIUS,
				}),
				Stroke = e("UIStroke", {
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
					Color = Theme.Palette.LockedStroke,
					LineJoinMode = Enum.LineJoinMode.Round,
					Transparency = hovered and 0.04 or 0.12,
					Thickness = hovered and 1.25 or 1,
				}),
				Gradient = e("UIGradient", {
					Rotation = 90,
					Color = ColorSequence.new({
						ColorSequenceKeypoint.new(0, Theme.Palette.CardShellSoft),
						ColorSequenceKeypoint.new(1, Theme.Palette.CardShell),
					}),
				}),
				ImageArea = e("Frame", {
					BackgroundColor3 = Theme.Palette.CardBackdrop,
					BackgroundTransparency = backdropBackgroundTransparency,
					BorderSizePixel = 0,
					ClipsDescendants = true,
					Position = UDim2.fromOffset(4, 4),
					Size = UDim2.new(1, -8, 1, -(FOOTER_HEIGHT + 8)),
				}, imageAreaShell(lockedChildren)),
				Footer = footer("???", "???", Theme.Palette.Text),
			},
		})
	end

	local discoveredChildren = createDiscoveredPreview(unit, props.renderPreview, isFruit)
	local cardAppearance = getDiscoveredCardAppearance(unit, rarity, hovered)

	if unit.production and unit.production ~= "" then
		discoveredChildren.Production = productionBadge(unit.production)
	end

	local discoveredCardChildren = {
		Corner = e("UICorner", {
			CornerRadius = CARD_CORNER_RADIUS,
		}),
		Gradient = e("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, cardAppearance.shellStart),
				ColorSequenceKeypoint.new(1, cardAppearance.shellEnd),
			}),
		}),
		ImageArea = e("Frame", {
			BackgroundColor3 = cardAppearance.backdropFill,
			BackgroundTransparency = backdropBackgroundTransparency,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Position = UDim2.fromOffset(4, 4),
			Size = UDim2.new(1, -8, 1, -(FOOTER_HEIGHT + 8)),
		}, imageAreaShell(discoveredChildren, rarity, hovered, cardAppearance)),
		Footer = footer(
			tostring(unit.rarity or ""),
			tostring(unit.displayName or unit.name or ""),
			rarity.textColor or Theme.Palette.Text
		),
	}

	for key, value in pairs(createRarityChrome(rarity, hovered)) do
		discoveredCardChildren[key] = value
	end

	return baseCard({
		backgroundTransparency = cardBackgroundTransparency,
		layoutOrder = props.layoutOrder,
		onMouseEnter = function()
			setHovered(true)
		end,
		onMouseLeave = function()
			setHovered(false)
		end,
		children = discoveredCardChildren,
	})
end

local function areIndexCardPropsEqual(oldProps, newProps)
	return oldProps.unit == newProps.unit
		and oldProps.renderPreview == newProps.renderPreview
		and oldProps.layoutOrder == newProps.layoutOrder
end

return React.memo(IndexCard, areIndexCardPropsEqual)
