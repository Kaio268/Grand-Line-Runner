local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))
local Responsive = require(UiFolder:WaitForChild("Responsive"))

local ACTIVE_AREA_ATTRIBUTE = BiomeAreas.ActiveAreaAttribute

local UI_CONFIG = BiomeAreas.Ui
local ANIMATION_CONFIG = BiomeAreas.Animation

local BASE_CARD_COLOR = Color3.fromRGB(10, 24, 42)
local BASE_CARD_COLOR_2 = Color3.fromRGB(8, 43, 62)
local TEXT_MAIN = Color3.fromRGB(246, 251, 255)
local TEXT_MUTED = Color3.fromRGB(167, 208, 226)
local STROKE_BASE = Color3.fromRGB(86, 203, 236)

local activeTweens = {}
local sequenceId = 0
local lastAnnouncedAreaKey = nil
local pendingAreaKey = nil
local loadingWaitRunning = false

local LOADING_SCREEN_NAME = "LoadingScreen"
local LOADING_SCREEN_ACTIVE_ATTRIBUTE = "LoadingScreenActive"

local function isMobileViewport()
	return Responsive.isMobile()
end

local function getBannerTopOffset()
	if isMobileViewport() then
		return UI_CONFIG.MobileTopOffset or 52
	end

	return UI_CONFIG.TopOffset
end

local function getBannerScaleTarget()
	return if isMobileViewport() then 0.84 else 1
end


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

local sizeConstraint = createInstance("UISizeConstraint", {
	Name = "AreaEnteredBannerSize",
	MinSize = Vector2.new(UI_CONFIG.MinWidth, UI_CONFIG.Height),
	MaxSize = Vector2.new(UI_CONFIG.MaxWidth, UI_CONFIG.Height),
})
sizeConstraint.Parent = root

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
entryLabel.Position = UDim2.fromOffset(24, 9)
entryLabel.Size = UDim2.new(1, -48, 0, 12)
entryLabel.Text = "AREA ENTERED"
entryLabel.TextTransparency = 0.08
entryLabel.Parent = card

local areaNameLabel = createLabel("AreaName", 26, Enum.Font.GothamBold, TEXT_MAIN)
areaNameLabel.Position = UDim2.fromOffset(24, 23)
areaNameLabel.Size = UDim2.new(1, -48, 0, 30)
areaNameLabel.Parent = card

local rarityLabel = createLabel("RarityTier", 12, Enum.Font.GothamMedium, STROKE_BASE)
rarityLabel.Position = UDim2.fromOffset(24, 53)
rarityLabel.Size = UDim2.new(1, -48, 0, 14)
rarityLabel.Parent = card

local function applyResponsiveLayout()
	if isMobileViewport() then
		sizeConstraint.MinSize = Vector2.new(220, 46)
		sizeConstraint.MaxSize = Vector2.new(340, 46)
		root.Size = UDim2.new(0.48, 0, 0, 46)
		rootScale.Scale = 0.68
		card.Size = UDim2.new(1, 0, 0, 42)
		entryLabel.TextSize = 7
		entryLabel.Position = UDim2.fromOffset(16, 5)
		entryLabel.Size = UDim2.new(1, -32, 0, 8)
		areaNameLabel.TextSize = 16
		areaNameLabel.Position = UDim2.fromOffset(16, 14)
		areaNameLabel.Size = UDim2.new(1, -32, 0, 20)
		rarityLabel.TextSize = 8
		rarityLabel.Position = UDim2.fromOffset(16, 31)
		rarityLabel.Size = UDim2.new(1, -32, 0, 10)
		accentLine.Position = UDim2.new(0.5, 0, 1, -4)
		return
	end

	root.Size = UDim2.new(UI_CONFIG.WidthScale, 0, 0, UI_CONFIG.Height)
	sizeConstraint.MinSize = Vector2.new(UI_CONFIG.MinWidth, UI_CONFIG.Height)
	sizeConstraint.MaxSize = Vector2.new(UI_CONFIG.MaxWidth, UI_CONFIG.Height)
	rootScale.Scale = 0.98
	card.Size = UDim2.new(1, 0, 0, 74)
	entryLabel.TextSize = 11
	entryLabel.Position = UDim2.fromOffset(24, 9)
	entryLabel.Size = UDim2.new(1, -48, 0, 12)
	areaNameLabel.TextSize = 26
	areaNameLabel.Position = UDim2.fromOffset(24, 23)
	areaNameLabel.Size = UDim2.new(1, -48, 0, 30)
	rarityLabel.TextSize = 12
	rarityLabel.Position = UDim2.fromOffset(24, 53)
	rarityLabel.Size = UDim2.new(1, -48, 0, 14)
	accentLine.Position = UDim2.new(0.5, 0, 1, -7)
end

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
	local topOffset = getBannerTopOffset()
	local scaleTarget = getBannerScaleTarget()

	cancelActiveTweens()
	applyResponsiveLayout()
	setBannerContent(entry)

	root.Visible = true
	root.GroupTransparency = 1
	root.Position = UDim2.new(0.5, 0, 0, topOffset + ANIMATION_CONFIG.SlideOffset)
	rootScale.Scale = if isMobileViewport() then 0.68 else 0.98

	tween(root, TweenInfo.new(
		ANIMATION_CONFIG.FadeInTime,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	), {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, topOffset),
	})

	tween(rootScale, TweenInfo.new(
		ANIMATION_CONFIG.FadeInTime,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	), {
		Scale = scaleTarget,
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
			Position = UDim2.new(0.5, 0, 0, topOffset - 8),
		})

		tween(rootScale, TweenInfo.new(
			ANIMATION_CONFIG.FadeOutTime,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			Scale = scaleTarget * 0.985,
		})

		fadeOut.Completed:Connect(function()
			if thisSequence == sequenceId then
				root.Visible = false
			end
		end)
	end)
end

local announceAreaFromAttribute

local function isLoadingScreenVisible()
	local loadingActive = playerGui:GetAttribute(LOADING_SCREEN_ACTIVE_ATTRIBUTE)
	if loadingActive ~= nil then
		return loadingActive == true
	end

	local loadingScreen = playerGui:FindFirstChild(LOADING_SCREEN_NAME)
	if not loadingScreen then
		return false
	end

	if loadingScreen:IsA("ScreenGui") then
		return loadingScreen.Enabled
	end

	return loadingScreen.Parent ~= nil
end

local function playAreaWhenLoadingFinishes()
	if loadingWaitRunning then
		return
	end

	loadingWaitRunning = true
	task.spawn(function()
		while isLoadingScreenVisible() do
			task.wait(0.05)
		end
		task.wait()

		loadingWaitRunning = false

		local areaKey = pendingAreaKey
		pendingAreaKey = nil
		if areaKey then
			local entry = BiomeAreas.GetArea(areaKey)
			if entry and areaKey ~= lastAnnouncedAreaKey then
				lastAnnouncedAreaKey = areaKey
				playBanner(entry)
			end
			return
		end

		if announceAreaFromAttribute then
			announceAreaFromAttribute()
		end
	end)
end

announceAreaFromAttribute = function()
	local areaKey = Lighting:GetAttribute(ACTIVE_AREA_ATTRIBUTE)
	local entry = BiomeAreas.GetArea(areaKey)
	if not entry then
		pendingAreaKey = nil
		return
	end

	local resolvedAreaKey = entry.AreaKey or tostring(areaKey)
	if resolvedAreaKey == lastAnnouncedAreaKey then
		return
	end

	if isLoadingScreenVisible() then
		pendingAreaKey = resolvedAreaKey
		playAreaWhenLoadingFinishes()
		return
	end

	pendingAreaKey = nil
	lastAnnouncedAreaKey = resolvedAreaKey
	playBanner(entry)
end

Lighting:GetAttributeChangedSignal(ACTIVE_AREA_ATTRIBUTE):Connect(announceAreaFromAttribute)
playerGui:GetAttributeChangedSignal(LOADING_SCREEN_ACTIVE_ATTRIBUTE):Connect(function()
	if not isLoadingScreenVisible() then
		task.defer(announceAreaFromAttribute)
	end
end)

player.CharacterAdded:Connect(function()
	lastAnnouncedAreaKey = nil
	task.defer(announceAreaFromAttribute)
end)

task.defer(announceAreaFromAttribute)
