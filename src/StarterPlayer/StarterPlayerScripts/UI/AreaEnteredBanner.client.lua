local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))

local ACTIVE_BIOME_ATTRIBUTE = BiomeAreas.ActiveBiomeAttribute

local UI_CONFIG = BiomeAreas.Ui
local ANIMATION_CONFIG = BiomeAreas.Animation

local BASE_CARD_COLOR = Color3.fromRGB(10, 24, 42)
local BASE_CARD_COLOR_2 = Color3.fromRGB(8, 43, 62)
local TEXT_MAIN = Color3.fromRGB(246, 251, 255)
local TEXT_MUTED = Color3.fromRGB(167, 208, 226)
local STROKE_BASE = Color3.fromRGB(86, 203, 236)

local activeTweens = {}
local sequenceId = 0
local lastAnnouncedBiomeIndex = nil

local function cancelActiveTweens()
	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end
	table.clear(activeTweens)
end

local function tween(instance, tweenInfo, goal)
	local activeTween = TweenService:Create(instance, tweenInfo, goal)
	activeTweens[#activeTweens + 1] = activeTween
	activeTween:Play()
	return activeTween
end

local function createInstance(className, props, children)
	local instance = Instance.new(className)

	for key, value in pairs(props or {}) do
		instance[key] = value
	end

	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end

	return instance
end

local function createLabel(name, textSize, font, color)
	return createInstance("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = font,
		RichText = false,
		Text = "",
		TextColor3 = color,
		TextSize = textSize,
		TextStrokeTransparency = 1,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = 12,
	})
end

local screenGui = createInstance("ScreenGui", {
	Name = "AreaEnteredBannerGui",
	DisplayOrder = UI_CONFIG.DisplayOrder,
	Enabled = true,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
screenGui.Parent = playerGui

local root = createInstance("CanvasGroup", {
	Name = "AreaEnteredBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = false,
	GroupTransparency = 1,
	Position = UDim2.new(0.5, 0, 0, UI_CONFIG.TopOffset + ANIMATION_CONFIG.SlideOffset),
	Size = UDim2.new(UI_CONFIG.WidthScale, 0, 0, UI_CONFIG.Height),
	Visible = false,
	ZIndex = 10,
})
root.Parent = screenGui

local rootScale = createInstance("UIScale", {
	Name = "AreaEnteredBannerScale",
	Scale = 0.98,
})
rootScale.Parent = root

createInstance("UISizeConstraint", {
	Name = "AreaEnteredBannerSize",
	MinSize = Vector2.new(UI_CONFIG.MinWidth, UI_CONFIG.Height),
	MaxSize = Vector2.new(UI_CONFIG.MaxWidth, UI_CONFIG.Height),
}).Parent = root

local glow = createInstance("Frame", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = STROKE_BASE,
	BackgroundTransparency = 0.78,
	BorderSizePixel = 0,
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(1, 26, 1, 22),
	ZIndex = 9,
}, {
	createInstance("UICorner", {
		CornerRadius = UDim.new(0, 24),
	}),
	createInstance("UIGradient", {
		Rotation = 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.38),
			NumberSequenceKeypoint.new(0.5, 0.08),
			NumberSequenceKeypoint.new(0.82, 0.38),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})
glow.Parent = root

local cardStroke = createInstance("UIStroke", {
	Name = "CardStroke",
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Color = STROKE_BASE,
	Thickness = 1.3,
	Transparency = 0.18,
})

local card = createInstance("Frame", {
	Name = "Card",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = BASE_CARD_COLOR,
	BackgroundTransparency = 0.06,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Position = UDim2.new(0.5, 0, 0, 5),
	Size = UDim2.new(1, 0, 0, 74),
	ZIndex = 10,
}, {
	createInstance("UICorner", {
		CornerRadius = UDim.new(0, 16),
	}),
	createInstance("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, BASE_CARD_COLOR:Lerp(Color3.fromRGB(22, 73, 96), 0.22)),
			ColorSequenceKeypoint.new(0.5, BASE_CARD_COLOR_2),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 18, 34)),
		}),
		Rotation = 12,
	}),
	cardStroke,
})
card.Parent = root

local sheen = createInstance("Frame", {
	Name = "Sheen",
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.87,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(12, 8),
	Size = UDim2.new(1, -24, 0, 1),
	ZIndex = 11,
}, {
	createInstance("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})
sheen.Parent = card

local accentLine = createInstance("Frame", {
	Name = "AccentLine",
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = STROKE_BASE,
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Position = UDim2.new(0.5, 0, 1, -7),
	Size = UDim2.new(1, -56, 0, 2),
	ZIndex = 12,
}, {
	createInstance("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.15, 0.22),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.85, 0.22),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})
accentLine.Parent = card

local entryLabel = createLabel("EntryLabel", 11, Enum.Font.GothamMedium, TEXT_MUTED)
entryLabel.Position = UDim2.new(0, 24, 0, 9)
entryLabel.Size = UDim2.new(1, -48, 0, 12)
entryLabel.Text = "AREA ENTERED"
entryLabel.TextTransparency = 0.08
entryLabel.Parent = card

local areaNameLabel = createLabel("AreaName", 26, Enum.Font.GothamBold, TEXT_MAIN)
areaNameLabel.Position = UDim2.new(0, 24, 0, 23)
areaNameLabel.Size = UDim2.new(1, -48, 0, 30)
areaNameLabel.Parent = card

local rarityLabel = createLabel("RarityTier", 12, Enum.Font.GothamMedium, STROKE_BASE)
rarityLabel.Position = UDim2.new(0, 24, 0, 53)
rarityLabel.Size = UDim2.new(1, -48, 0, 14)
rarityLabel.Parent = card

local function setBannerContent(entry)
	local style = BiomeAreas.GetRarityStyle(entry.Rarity)
	local accentColor = style.AccentColor
	local glowColor = style.GlowColor or accentColor

	areaNameLabel.Text = tostring(entry.AreaName or entry.BiomeName or "")
	rarityLabel.Text = BiomeAreas.GetSubtitle(entry)

	rarityLabel.TextColor3 = accentColor
	cardStroke.Color = accentColor:Lerp(STROKE_BASE, 0.24)
	accentLine.BackgroundColor3 = accentColor
	glow.BackgroundColor3 = glowColor
end

local function playBanner(entry)
	sequenceId += 1
	local thisSequence = sequenceId

	cancelActiveTweens()
	setBannerContent(entry)

	root.Visible = true
	root.GroupTransparency = 1
	root.Position = UDim2.new(0.5, 0, 0, UI_CONFIG.TopOffset + ANIMATION_CONFIG.SlideOffset)
	rootScale.Scale = 0.98

	tween(root, TweenInfo.new(
		ANIMATION_CONFIG.FadeInTime,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	), {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, UI_CONFIG.TopOffset),
	})

	tween(rootScale, TweenInfo.new(
		ANIMATION_CONFIG.FadeInTime,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	), {
		Scale = 1,
	})

	task.delay(ANIMATION_CONFIG.FadeInTime + ANIMATION_CONFIG.HoldTime, function()
		if thisSequence ~= sequenceId then
			return
		end

		cancelActiveTweens()

		local fadeOut = tween(root, TweenInfo.new(
			ANIMATION_CONFIG.FadeOutTime,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			GroupTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, UI_CONFIG.TopOffset - 8),
		})

		tween(rootScale, TweenInfo.new(
			ANIMATION_CONFIG.FadeOutTime,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			Scale = 0.985,
		})

		fadeOut.Completed:Connect(function()
			if thisSequence == sequenceId then
				root.Visible = false
			end
		end)
	end)
end

local function announceBiomeFromAttribute()
	local biomeIndex = tonumber(Lighting:GetAttribute(ACTIVE_BIOME_ATTRIBUTE))
	local entry = BiomeAreas.GetBiome(biomeIndex)
	if not entry then
		return
	end

	if biomeIndex == lastAnnouncedBiomeIndex then
		return
	end

	lastAnnouncedBiomeIndex = biomeIndex
	playBanner(entry)
end

Lighting:GetAttributeChangedSignal(ACTIVE_BIOME_ATTRIBUTE):Connect(announceBiomeFromAttribute)

player.CharacterAdded:Connect(function()
	lastAnnouncedBiomeIndex = nil
	task.defer(announceBiomeFromAttribute)
end)

task.defer(announceBiomeFromAttribute)
