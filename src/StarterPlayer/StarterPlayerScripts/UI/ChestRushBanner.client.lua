local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local ModulesFolder = ReplicatedStorage:WaitForChild("Modules")
local ChestRushWorldVfx = require(ModulesFolder:WaitForChild("ChestRushWorldVfx"))
local ConfigsFolder = ModulesFolder:WaitForChild("Configs")
local BiomeAreas = require(ConfigsFolder:WaitForChild("BiomeAreas"))
local UiFolder = ReplicatedStorage:WaitForChild("UI")
local Responsive = require(UiFolder:WaitForChild("Responsive"))
local HudLayout = require(UiFolder:WaitForChild("HudLayout"))

local STATE_EVENT_NAME = "GrandLineRushChestRushState"
local STATE_REQUEST_NAME = "GrandLineRushChestRushStateRequest"

local DISPLAY_ORDER = 124
local CHEST_RUSH_GUI_DISPLAY_ORDER = DISPLAY_ORDER - 1
local ANNOUNCEMENT_TOP_OFFSET = 176
local CHEST_RUSH_GUI_NAME = "ChestRushGui"
local BASE_BANNER_SIZE = Vector2.new(400, 95)
local BANNER_DESKTOP_SCALE = 1
local BANNER_DESKTOP_TOP_OFFSET = 96
local BANNER_MIN_SIZE = Vector2.new(288, 68)
local BANNER_MAX_SIZE = Vector2.new(400, 95)
local CHEST_RUSH_MAIN_TEXT = "CHEST RUSH"
local CHEST_RUSH_SUB_TEXT = "DOUBLE CHESTS ARE SPAWNING!"
local ACTIVE_AREA_ATTRIBUTE = BiomeAreas.ActiveAreaAttribute
local STARTING_AREA_KEY = BiomeAreas.StartingAreaKey
local HUD_FADE_IN_TIME = 0.22
local HUD_FADE_OUT_TIME = 0.24
local GOLD_OVERLAY_ACTIVE_TRANSPARENCY = 0.88
local SLIDE_OFFSET = 18
local FADE_IN_TIME = 0.26
local HOLD_TIME = 3.4
local FADE_OUT_TIME = 0.36

local BASE_CARD_COLOR = Color3.fromRGB(10, 24, 42)
local BASE_CARD_COLOR_2 = Color3.fromRGB(18, 45, 56)
local TEXT_MAIN = Color3.fromRGB(255, 250, 224)
local TEXT_MUTED = Color3.fromRGB(238, 204, 126)
local GOLD = Color3.fromRGB(255, 199, 82)
local GOLD_GLOW = Color3.fromRGB(255, 178, 56)

local stateEvent = nil
local stateRequest = nil
local currentState = nil
local announcementSequence = 0
local countdownToken = 0
local timerVisible = false
local countdownLoopRunning = false
local corridorEffectsActive = false
local announcementTweens = {}
local timerTweens = {}
local corridorEffectTweens = {}
local chestRushGui = nil
local chestRushTopBanner = nil
local chestRushTopBannerScale = nil
local chestRushTopBannerSize = nil
local chestRushTopBannerStroke = nil
local chestRushMainText = nil
local chestRushSubText = nil
local chestRushTimerText = nil
local chestRushGoldOverlay = nil
local chestRushFloatingImageFrame = nil
local chestRushLeftSideGlow = nil
local chestRushRightSideGlow = nil
local chestRushIconTemplates = {}
local chestRushTopBannerBackgroundTransparency = 0.35
local chestRushTopBannerStrokeTransparency = 0
local chestRushMainTextTransparency = 0
local chestRushSubTextTransparency = 0
local chestRushTimerTextTransparency = 0
local viewportSizeConnection = nil
local currentCameraConnection = nil
local activeAreaConnection = nil

local function isMobileViewport()
	local mode = Responsive.getHudLayoutMode()
	return mode == "phone" or mode == "tablet"
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

local function cancelTweens(tweens)
	for _, activeTween in ipairs(tweens) do
		activeTween:Cancel()
	end
	table.clear(tweens)
end

local function playTween(tweens, instance, tweenInfo, goal)
	local activeTween = TweenService:Create(instance, tweenInfo, goal)
	tweens[#tweens + 1] = activeTween
	activeTween:Play()
	return activeTween
end

local function getGuiObject(parent, name)
	local child = if parent then parent:FindFirstChild(name) else nil
	return if child and child:IsA("GuiObject") then child else nil
end

local function getTextLabel(parent, name)
	local child = if parent then parent:FindFirstChild(name) else nil
	return if child and child:IsA("TextLabel") then child else nil
end

local function getImageLabel(parent, name)
	local child = if parent then parent:FindFirstChild(name) else nil
	return if child and child:IsA("ImageLabel") then child else nil
end

local function getOrCreateChild(parent, name, className)
	local child = parent:FindFirstChild(name)
	if child and child:IsA(className) then
		return child
	end

	child = parent:FindFirstChildOfClass(className)
	if child then
		return child
	end

	child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function hideFloatingIconTemplates()
	for _, template in pairs(chestRushIconTemplates) do
		template.Visible = false
	end
end

local function setChestRushGuiRestState()
	if not chestRushGui then
		return
	end

	if chestRushMainText then
		chestRushMainText.Text = CHEST_RUSH_MAIN_TEXT
		chestRushMainText.TextTransparency = 1
	end

	if chestRushSubText then
		chestRushSubText.Text = CHEST_RUSH_SUB_TEXT
		chestRushSubText.TextTransparency = 1
	end

	if chestRushTimerText then
		chestRushTimerText.Text = "00:00"
		chestRushTimerText.TextTransparency = 1
	end

	if chestRushTopBanner then
		chestRushTopBanner.Visible = true
		chestRushTopBanner.BackgroundTransparency = 1
	end

	if chestRushTopBannerStroke then
		chestRushTopBannerStroke.Transparency = 1
	end

	if chestRushGoldOverlay then
		chestRushGoldOverlay.BackgroundTransparency = 1
	end

	if chestRushLeftSideGlow then
		chestRushLeftSideGlow.BackgroundTransparency = 1
		chestRushLeftSideGlow.Visible = false
	end

	if chestRushRightSideGlow then
		chestRushRightSideGlow.BackgroundTransparency = 1
		chestRushRightSideGlow.Visible = false
	end

	hideFloatingIconTemplates()
	chestRushGui.Enabled = false
end

local function getBannerScale(viewport)
	local layout = HudLayout.getTopBanner(Responsive.getHudLayoutMode(viewport))
	return layout.scale or BANNER_DESKTOP_SCALE
end

local function getBannerTopOffset(viewport)
	local layout = HudLayout.getTopBanner(Responsive.getHudLayoutMode(viewport))
	return layout.topOffset or BANNER_DESKTOP_TOP_OFFSET
end

local function applyChestRushGuiResponsiveLayout()
	if not chestRushGui then
		return
	end

	local viewport = Responsive.getViewportSize()
	local scale = getBannerScale(viewport)
	local topOffset = getBannerTopOffset(viewport)

	if chestRushTopBanner then
		chestRushTopBanner.Size = UDim2.fromOffset(BASE_BANNER_SIZE.X, BASE_BANNER_SIZE.Y)
		chestRushTopBanner.Position = UDim2.fromOffset(
			viewport.X * 0.5,
			topOffset + (BASE_BANNER_SIZE.Y * scale * 0.5)
		)
	end

	if chestRushTopBannerScale then
		chestRushTopBannerScale.Scale = scale
	end

	if chestRushTopBannerSize then
		chestRushTopBannerSize.MinSize = BANNER_MIN_SIZE
		chestRushTopBannerSize.MaxSize = BANNER_MAX_SIZE
	end

	if chestRushGoldOverlay then
		chestRushGoldOverlay.Size = UDim2.fromScale(1, 1)
	end

	if chestRushFloatingImageFrame then
		chestRushFloatingImageFrame.Size = UDim2.fromScale(1, 1)
		chestRushFloatingImageFrame.ClipsDescendants = false
	end
end

local function bindChestRushGui(candidate)
	if chestRushGui then
		return true
	end

	if not candidate or not candidate:IsA("ScreenGui") then
		return false
	end

	local topBanner = getGuiObject(candidate, "TopBanner")
	if not topBanner then
		return false
	end

	chestRushGui = candidate
	chestRushGui.DisplayOrder = CHEST_RUSH_GUI_DISPLAY_ORDER
	chestRushTopBanner = topBanner
	chestRushTopBannerScale = getOrCreateChild(topBanner, "ChestRushTopBannerScale", "UIScale")
	chestRushTopBannerSize = getOrCreateChild(topBanner, "ChestRushTopBannerSize", "UISizeConstraint")
	chestRushTopBannerStroke = topBanner:FindFirstChildOfClass("UIStroke")
	chestRushMainText = getTextLabel(topBanner, "MainText")
	chestRushSubText = getTextLabel(topBanner, "SubText")
	chestRushTimerText = getTextLabel(topBanner, "TimerText")
	chestRushGoldOverlay = getGuiObject(candidate, "GoldOverlay")
	chestRushFloatingImageFrame = getGuiObject(candidate, "FloatingImageFrame")
	chestRushLeftSideGlow = getGuiObject(candidate, "LeftSideGlow")
	chestRushRightSideGlow = getGuiObject(candidate, "RightSideGlow")

	table.clear(chestRushIconTemplates)
	if chestRushFloatingImageFrame then
		chestRushIconTemplates.chest = getImageLabel(chestRushFloatingImageFrame, "ChestTemplate")
		chestRushIconTemplates.sparkle = getImageLabel(chestRushFloatingImageFrame, "SparkleTemplate")
		chestRushIconTemplates.beli = getImageLabel(chestRushFloatingImageFrame, "BeliTemplate")
	end

	chestRushTopBannerBackgroundTransparency = chestRushTopBanner.BackgroundTransparency
	chestRushTopBannerStrokeTransparency = if chestRushTopBannerStroke then chestRushTopBannerStroke.Transparency else 0
	chestRushMainTextTransparency = if chestRushMainText then chestRushMainText.TextTransparency else 0
	chestRushSubTextTransparency = if chestRushSubText then chestRushSubText.TextTransparency else 0
	chestRushTimerTextTransparency = if chestRushTimerText then chestRushTimerText.TextTransparency else 0

	applyChestRushGuiResponsiveLayout()
	setChestRushGuiRestState()
	return true
end

local function connectViewportSizeChanged()
	if viewportSizeConnection then
		viewportSizeConnection:Disconnect()
		viewportSizeConnection = nil
	end

	local camera = Workspace.CurrentCamera
	if camera then
		viewportSizeConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyChestRushGuiResponsiveLayout)
	end

	applyChestRushGuiResponsiveLayout()
end

local screenGui = createInstance("ScreenGui", {
	Name = "ChestRushBannerGui",
	DisplayOrder = DISPLAY_ORDER,
	Enabled = true,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
screenGui.Parent = playerGui

local announcementRoot = createInstance("CanvasGroup", {
	Name = "ChestRushAnnouncement",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ClipsDescendants = false,
	GroupTransparency = 1,
	Position = UDim2.new(0.5, 0, 0, ANNOUNCEMENT_TOP_OFFSET + SLIDE_OFFSET),
	Size = UDim2.new(0.82, 0, 0, 92),
	Visible = false,
	ZIndex = 10,
})
announcementRoot.Parent = screenGui

local announcementScale = createInstance("UIScale", {
	Name = "ChestRushAnnouncementScale",
	Scale = 0.98,
})
announcementScale.Parent = announcementRoot

local announcementSize = createInstance("UISizeConstraint", {
	Name = "ChestRushAnnouncementSize",
	MinSize = Vector2.new(280, 92),
	MaxSize = Vector2.new(560, 92),
})
announcementSize.Parent = announcementRoot

local announcementGlow = createInstance("Frame", {
	Name = "Glow",
	AnchorPoint = Vector2.new(0.5, 0.5),
	BackgroundColor3 = GOLD_GLOW,
	BackgroundTransparency = 0.78,
	BorderSizePixel = 0,
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(1, 28, 1, 24),
	ZIndex = 9,
}, {
	createInstance("UICorner", {
		CornerRadius = UDim.new(0, 24),
	}),
	createInstance("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.35),
			NumberSequenceKeypoint.new(0.5, 0.08),
			NumberSequenceKeypoint.new(0.82, 0.35),
			NumberSequenceKeypoint.new(1, 1),
		}),
	}),
})
announcementGlow.Parent = announcementRoot

local announcementStroke = createInstance("UIStroke", {
	Name = "CardStroke",
	ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	Color = GOLD,
	Thickness = 1.4,
	Transparency = 0.14,
})

local announcementCard = createInstance("Frame", {
	Name = "Card",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = BASE_CARD_COLOR,
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	ClipsDescendants = true,
	Position = UDim2.new(0.5, 0, 0, 5),
	Size = UDim2.new(1, 0, 0, 82),
	ZIndex = 10,
}, {
	createInstance("UICorner", {
		CornerRadius = UDim.new(0, 16),
	}),
	createInstance("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, BASE_CARD_COLOR:Lerp(Color3.fromRGB(94, 68, 25), 0.28)),
			ColorSequenceKeypoint.new(0.5, BASE_CARD_COLOR_2),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 18, 34)),
		}),
		Rotation = 12,
	}),
	announcementStroke,
})
announcementCard.Parent = announcementRoot

local announcementSheen = createInstance("Frame", {
	Name = "Sheen",
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.86,
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(14, 8),
	Size = UDim2.new(1, -28, 0, 1),
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
announcementSheen.Parent = announcementCard

local announcementAccentLine = createInstance("Frame", {
	Name = "AccentLine",
	AnchorPoint = Vector2.new(0.5, 1),
	BackgroundColor3 = GOLD,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Position = UDim2.new(0.5, 0, 1, -7),
	Size = UDim2.new(1, -60, 0, 2),
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
announcementAccentLine.Parent = announcementCard

local announcementTitle = createLabel("Title", 24, Enum.Font.GothamBold, TEXT_MAIN)
announcementTitle.Position = UDim2.fromOffset(24, 18)
announcementTitle.Size = UDim2.new(1, -48, 0, 30)
announcementTitle.Parent = announcementCard

local announcementSubtitle = createLabel("Subtitle", 13, Enum.Font.GothamMedium, TEXT_MUTED)
announcementSubtitle.Position = UDim2.fromOffset(24, 50)
announcementSubtitle.Size = UDim2.new(1, -48, 0, 18)
announcementSubtitle.Parent = announcementCard

local function getAnnouncementTopOffset()
	local layout = HudLayout.getTopBanner()
	return layout.announcementTopOffset or ANNOUNCEMENT_TOP_OFFSET
end

local function getAnnouncementScaleTarget()
	local layout = HudLayout.getTopBanner()
	return layout.announcementScale or Responsive.getUiScale()
end

local function applyResponsiveLayout()
	local mode = Responsive.getHudLayoutMode()
	local mobile = mode == "phone" or mode == "tablet"
	if mobile then
		announcementRoot.Size = UDim2.new(0.72, 0, 0, 68)
		announcementSize.MinSize = Vector2.new(240, 68)
		announcementSize.MaxSize = Vector2.new(380, 68)
		announcementCard.Size = UDim2.new(1, 0, 0, 62)
		announcementTitle.TextSize = 16
		announcementTitle.Position = UDim2.fromOffset(16, 12)
		announcementTitle.Size = UDim2.new(1, -32, 0, 22)
		announcementSubtitle.TextSize = 9
		announcementSubtitle.Position = UDim2.fromOffset(16, 34)
		announcementSubtitle.Size = UDim2.new(1, -32, 0, 15)
		announcementAccentLine.Position = UDim2.new(0.5, 0, 1, -5)
	else
		announcementRoot.Size = UDim2.new(0.82, 0, 0, 92)
		announcementSize.MinSize = Vector2.new(280, 92)
		announcementSize.MaxSize = Vector2.new(560, 92)
		announcementCard.Size = UDim2.new(1, 0, 0, 82)
		announcementTitle.TextSize = 24
		announcementTitle.Position = UDim2.fromOffset(24, 18)
		announcementTitle.Size = UDim2.new(1, -48, 0, 30)
		announcementSubtitle.TextSize = 13
		announcementSubtitle.Position = UDim2.fromOffset(24, 50)
		announcementSubtitle.Size = UDim2.new(1, -48, 0, 18)
		announcementAccentLine.Position = UDim2.new(0.5, 0, 1, -7)
	end

	announcementRoot.Position = UDim2.new(0.5, 0, 0, getAnnouncementTopOffset())
	applyChestRushGuiResponsiveLayout()
end

local function formatRemainingTime(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local minutes = math.floor(seconds / 60)
	local remainingSeconds = seconds % 60
	return string.format("%02d:%02d", minutes, remainingSeconds)
end

local function showAnnouncement(title, subtitle)
	announcementSequence += 1
	local thisSequence = announcementSequence
	local topOffset = getAnnouncementTopOffset()
	local scaleTarget = getAnnouncementScaleTarget()

	cancelTweens(announcementTweens)
	applyResponsiveLayout()

	announcementTitle.Text = tostring(title or "")
	announcementSubtitle.Text = tostring(subtitle or "")
	announcementRoot.Visible = true
	announcementRoot.GroupTransparency = 1
	announcementRoot.Position = UDim2.new(0.5, 0, 0, topOffset + SLIDE_OFFSET)
	announcementScale.Scale = if isMobileViewport() then 0.7 else 0.98

	playTween(announcementTweens, announcementRoot, TweenInfo.new(
		FADE_IN_TIME,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	), {
		GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, 0, topOffset),
	})

	playTween(announcementTweens, announcementScale, TweenInfo.new(
		FADE_IN_TIME,
		Enum.EasingStyle.Quart,
		Enum.EasingDirection.Out
	), {
		Scale = scaleTarget,
	})

	task.delay(FADE_IN_TIME + HOLD_TIME, function()
		if thisSequence ~= announcementSequence then
			return
		end

		cancelTweens(announcementTweens)

		local fadeOut = playTween(announcementTweens, announcementRoot, TweenInfo.new(
			FADE_OUT_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			GroupTransparency = 1,
			Position = UDim2.new(0.5, 0, 0, topOffset - 8),
		})

		playTween(announcementTweens, announcementScale, TweenInfo.new(
			FADE_OUT_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			Scale = scaleTarget * 0.985,
		})

		fadeOut.Completed:Connect(function()
			if thisSequence == announcementSequence then
				announcementRoot.Visible = false
			end
		end)
	end)
end

local function isInChestRushCorridorArea()
	local activeArea = Lighting:GetAttribute(ACTIVE_AREA_ATTRIBUTE)
	return typeof(activeArea) == "string" and activeArea ~= "" and activeArea ~= STARTING_AREA_KEY
end

local function setCorridorEffectsEnabled(enabled)
	if enabled == corridorEffectsActive then
		return
	end

	corridorEffectsActive = enabled
	cancelTweens(corridorEffectTweens)

	if enabled then
		if chestRushGoldOverlay then
			playTween(corridorEffectTweens, chestRushGoldOverlay, TweenInfo.new(
				HUD_FADE_IN_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.Out
			), {
				BackgroundTransparency = GOLD_OVERLAY_ACTIVE_TRANSPARENCY,
			})
		end

		ChestRushWorldVfx.Start()
	else
		ChestRushWorldVfx.Stop()

		if chestRushGoldOverlay then
			playTween(corridorEffectTweens, chestRushGoldOverlay, TweenInfo.new(
				HUD_FADE_OUT_TIME,
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			), {
				BackgroundTransparency = 1,
			})
		end
	end
end

local function updateCorridorEffects()
	local shouldEnable = timerVisible
		and currentState
		and currentState.Active == true
		and isInChestRushCorridorArea()

	setCorridorEffectsEnabled(shouldEnable == true)
end

local function showTimer()
	if timerVisible then
		updateCorridorEffects()
		return
	end

	if not bindChestRushGui(playerGui:FindFirstChild(CHEST_RUSH_GUI_NAME)) then
		return
	end

	timerVisible = true
	cancelTweens(timerTweens)
	applyResponsiveLayout()
	hideFloatingIconTemplates()

	chestRushGui.Enabled = true

	if chestRushMainText then
		chestRushMainText.Text = CHEST_RUSH_MAIN_TEXT
		chestRushMainText.TextTransparency = 1
	end

	if chestRushSubText then
		chestRushSubText.Text = CHEST_RUSH_SUB_TEXT
		chestRushSubText.TextTransparency = 1
	end

	if chestRushTimerText then
		chestRushTimerText.TextTransparency = 1
	end

	if chestRushTopBanner then
		chestRushTopBanner.Visible = true
		chestRushTopBanner.BackgroundTransparency = 1
		playTween(timerTweens, chestRushTopBanner, TweenInfo.new(
			HUD_FADE_IN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			BackgroundTransparency = chestRushTopBannerBackgroundTransparency,
		})
	end

	if chestRushTopBannerStroke then
		chestRushTopBannerStroke.Transparency = 1
		playTween(timerTweens, chestRushTopBannerStroke, TweenInfo.new(
			HUD_FADE_IN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			Transparency = chestRushTopBannerStrokeTransparency,
		})
	end

	if chestRushMainText then
		playTween(timerTweens, chestRushMainText, TweenInfo.new(
			HUD_FADE_IN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			TextTransparency = chestRushMainTextTransparency,
		})
	end

	if chestRushSubText then
		playTween(timerTweens, chestRushSubText, TweenInfo.new(
			HUD_FADE_IN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			TextTransparency = chestRushSubTextTransparency,
		})
	end

	if chestRushTimerText then
		playTween(timerTweens, chestRushTimerText, TweenInfo.new(
			HUD_FADE_IN_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		), {
			TextTransparency = chestRushTimerTextTransparency,
		})
	end

	if chestRushGoldOverlay then
		chestRushGoldOverlay.BackgroundTransparency = 1
	end

	updateCorridorEffects()
end

local function hideTimer()
	if not timerVisible then
		setCorridorEffectsEnabled(false)
		if chestRushGui then
			setChestRushGuiRestState()
		end
		return
	end

	timerVisible = false
	countdownToken += 1
	countdownLoopRunning = false
	cancelTweens(timerTweens)
	setCorridorEffectsEnabled(false)

	local fadeOut = nil
	if chestRushTopBanner then
		fadeOut = playTween(timerTweens, chestRushTopBanner, TweenInfo.new(
			HUD_FADE_OUT_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			BackgroundTransparency = 1,
		})
	end

	if chestRushTopBannerStroke then
		playTween(timerTweens, chestRushTopBannerStroke, TweenInfo.new(
			HUD_FADE_OUT_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			Transparency = 1,
		})
	end

	if chestRushMainText then
		playTween(timerTweens, chestRushMainText, TweenInfo.new(
			HUD_FADE_OUT_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			TextTransparency = 1,
		})
	end

	if chestRushSubText then
		playTween(timerTweens, chestRushSubText, TweenInfo.new(
			HUD_FADE_OUT_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			TextTransparency = 1,
		})
	end

	if chestRushTimerText then
		playTween(timerTweens, chestRushTimerText, TweenInfo.new(
			HUD_FADE_OUT_TIME,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		), {
			TextTransparency = 1,
		})
	end

	local function disableAfterFade()
		if not timerVisible and chestRushGui then
			chestRushGui.Enabled = false
			hideFloatingIconTemplates()
		end
	end

	if fadeOut then
		fadeOut.Completed:Connect(disableAfterFade)
	else
		task.delay(HUD_FADE_OUT_TIME, disableAfterFade)
	end
end

local function getRemainingSeconds(state)
	if typeof(state) ~= "table" then
		return 0
	end

	local endsAtServerTime = tonumber(state.EndsAtServerTime)
	if not endsAtServerTime then
		return 0
	end

	return math.max(0, math.ceil(endsAtServerTime - Workspace:GetServerTimeNow()))
end

local function updateTimerText()
	if chestRushTimerText then
		chestRushTimerText.Text = formatRemainingTime(getRemainingSeconds(currentState))
	end
end

local function startCountdown()
	if countdownLoopRunning then
		return
	end

	countdownToken += 1
	local thisToken = countdownToken
	countdownLoopRunning = true

	task.spawn(function()
		while thisToken == countdownToken and currentState and currentState.Active == true do
			updateTimerText()
			if getRemainingSeconds(currentState) <= 0 then
				break
			end
			task.wait(1)
		end

		if thisToken == countdownToken then
			countdownLoopRunning = false
		end
	end)
end

local function applyState(state, source)
	if typeof(state) ~= "table" then
		return
	end

	local hadState = currentState ~= nil
	local wasActive = hadState and currentState.Active == true
	local isActive = state.Active == true

	currentState = state

	if isActive then
		showTimer()
		updateTimerText()
		startCountdown()
	else
		hideTimer()
	end

	if hadState and not wasActive and isActive then
		showAnnouncement("CHEST RUSH HAS STARTED!", "More treasure chests are appearing in the corridor.")
	elseif hadState and wasActive and not isActive and source ~= "initial" then
		showAnnouncement("CHEST RUSH HAS ENDED", "Chest spawns have returned to normal.")
	end
end

local function waitForRemote(parent, name, className, timeoutSeconds)
	local found = parent:FindFirstChild(name)
	if found and found:IsA(className) then
		return found
	end

	found = parent:WaitForChild(name, timeoutSeconds)
	if found and found:IsA(className) then
		return found
	end

	return nil
end

local function requestInitialState()
	if not stateRequest then
		return
	end

	local ok, state = pcall(function()
		return stateRequest:InvokeServer()
	end)
	if ok then
		applyState(state, "initial")
	end
end

applyResponsiveLayout()
bindChestRushGui(playerGui:FindFirstChild(CHEST_RUSH_GUI_NAME))
connectViewportSizeChanged()

currentCameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectViewportSizeChanged)
activeAreaConnection = Lighting:GetAttributeChangedSignal(ACTIVE_AREA_ATTRIBUTE):Connect(updateCorridorEffects)

task.defer(function()
	if chestRushGui then
		return
	end

	if bindChestRushGui(playerGui:WaitForChild(CHEST_RUSH_GUI_NAME, 10)) and currentState and currentState.Active == true then
		showTimer()
		updateTimerText()
		startCountdown()
	end
end)

local remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if remotes then
	stateEvent = waitForRemote(remotes, STATE_EVENT_NAME, "RemoteEvent", 15)
	stateRequest = waitForRemote(remotes, STATE_REQUEST_NAME, "RemoteFunction", 15)
end

if stateEvent then
	stateEvent.OnClientEvent:Connect(function(state)
		applyState(state, "event")
	end)
end

task.defer(requestInitialState)

script.Destroying:Connect(function()
	setCorridorEffectsEnabled(false)
	ChestRushWorldVfx.Destroy()
	cancelTweens(corridorEffectTweens)

	if viewportSizeConnection then
		viewportSizeConnection:Disconnect()
		viewportSizeConnection = nil
	end

	if currentCameraConnection then
		currentCameraConnection:Disconnect()
		currentCameraConnection = nil
	end

	if activeAreaConnection then
		activeAreaConnection:Disconnect()
		activeAreaConnection = nil
	end
end)
