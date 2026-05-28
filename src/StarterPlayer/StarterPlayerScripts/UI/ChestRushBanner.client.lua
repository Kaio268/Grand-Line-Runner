local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UiFolder = ReplicatedStorage:WaitForChild("UI")
local Responsive = require(UiFolder:WaitForChild("Responsive"))

local STATE_EVENT_NAME = "GrandLineRushChestRushState"
local STATE_REQUEST_NAME = "GrandLineRushChestRushStateRequest"

local DISPLAY_ORDER = 124
local ANNOUNCEMENT_TOP_OFFSET = 176
local ANNOUNCEMENT_MOBILE_TOP_OFFSET = 114
local TIMER_TOP_OFFSET = 72
local TIMER_MOBILE_TOP_OFFSET = 58
local SLIDE_OFFSET = 18
local FADE_IN_TIME = 0.26
local HOLD_TIME = 3.4
local FADE_OUT_TIME = 0.36

local BASE_CARD_COLOR = Color3.fromRGB(10, 24, 42)
local BASE_CARD_COLOR_2 = Color3.fromRGB(18, 45, 56)
local TEXT_MAIN = Color3.fromRGB(255, 250, 224)
local TEXT_MUTED = Color3.fromRGB(238, 204, 126)
local GOLD = Color3.fromRGB(255, 199, 82)
local GOLD_BRIGHT = Color3.fromRGB(255, 224, 132)
local GOLD_GLOW = Color3.fromRGB(255, 178, 56)

local stateEvent = nil
local stateRequest = nil
local currentState = nil
local announcementSequence = 0
local countdownToken = 0
local timerVisible = false
local announcementTweens = {}
local timerTweens = {}

local function isMobileViewport()
	return Responsive.isMobile()
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

local timerRoot = createInstance("CanvasGroup", {
	Name = "ChestRushTimer",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Position = UDim2.new(0.5, 0, 0, TIMER_TOP_OFFSET),
	Size = UDim2.new(0.44, 0, 0, 56),
	Visible = false,
	ZIndex = 13,
})
timerRoot.Parent = screenGui

local timerSize = createInstance("UISizeConstraint", {
	Name = "ChestRushTimerSize",
	MinSize = Vector2.new(220, 56),
	MaxSize = Vector2.new(360, 56),
})
timerSize.Parent = timerRoot

local timerCard = createInstance("Frame", {
	Name = "Card",
	BackgroundColor3 = BASE_CARD_COLOR,
	BackgroundTransparency = 0.04,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1, 1),
	ZIndex = 13,
}, {
	createInstance("UICorner", {
		CornerRadius = UDim.new(0, 14),
	}),
	createInstance("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(41, 39, 30)),
			ColorSequenceKeypoint.new(0.55, Color3.fromRGB(12, 28, 44)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 18, 34)),
		}),
		Rotation = 10,
	}),
	createInstance("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = GOLD,
		Thickness = 1.2,
		Transparency = 0.16,
	}),
})
timerCard.Parent = timerRoot

local timerTitle = createLabel("Title", 11, Enum.Font.GothamBold, GOLD_BRIGHT)
timerTitle.Position = UDim2.fromOffset(18, 7)
timerTitle.Size = UDim2.new(1, -36, 0, 14)
timerTitle.Text = "CHEST RUSH"
timerTitle.Parent = timerCard

local timerLabel = createLabel("Time", 26, Enum.Font.GothamBold, TEXT_MAIN)
timerLabel.Position = UDim2.fromOffset(18, 22)
timerLabel.Size = UDim2.new(1, -36, 0, 28)
timerLabel.Text = "10:00"
timerLabel.Parent = timerCard

local function getAnnouncementTopOffset()
	return if isMobileViewport() then ANNOUNCEMENT_MOBILE_TOP_OFFSET else ANNOUNCEMENT_TOP_OFFSET
end

local function getTimerTopOffset()
	return if isMobileViewport() then TIMER_MOBILE_TOP_OFFSET else TIMER_TOP_OFFSET
end

local function getAnnouncementScaleTarget()
	return if isMobileViewport() then 0.76 else 1
end

local function applyResponsiveLayout()
	if isMobileViewport() then
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
		timerRoot.Size = UDim2.new(0.42, 0, 0, 46)
		timerSize.MinSize = Vector2.new(170, 46)
		timerSize.MaxSize = Vector2.new(260, 46)
		timerTitle.TextSize = 9
		timerTitle.Position = UDim2.fromOffset(14, 5)
		timerTitle.Size = UDim2.new(1, -28, 0, 12)
		timerLabel.TextSize = 20
		timerLabel.Position = UDim2.fromOffset(14, 17)
		timerLabel.Size = UDim2.new(1, -28, 0, 24)
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
		timerRoot.Size = UDim2.new(0.44, 0, 0, 56)
		timerSize.MinSize = Vector2.new(220, 56)
		timerSize.MaxSize = Vector2.new(360, 56)
		timerTitle.TextSize = 11
		timerTitle.Position = UDim2.fromOffset(18, 7)
		timerTitle.Size = UDim2.new(1, -36, 0, 14)
		timerLabel.TextSize = 26
		timerLabel.Position = UDim2.fromOffset(18, 22)
		timerLabel.Size = UDim2.new(1, -36, 0, 28)
	end

	announcementRoot.Position = UDim2.new(0.5, 0, 0, getAnnouncementTopOffset())
	timerRoot.Position = UDim2.new(0.5, 0, 0, getTimerTopOffset())
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

local function showTimer()
	if timerVisible then
		return
	end

	timerVisible = true
	cancelTweens(timerTweens)
	applyResponsiveLayout()
	timerRoot.Visible = true
	timerRoot.GroupTransparency = 1

	playTween(timerTweens, timerRoot, TweenInfo.new(
		0.18,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	), {
		GroupTransparency = 0,
	})
end

local function hideTimer()
	if not timerVisible then
		timerRoot.Visible = false
		return
	end

	timerVisible = false
	countdownToken += 1
	cancelTweens(timerTweens)

	local fadeOut = playTween(timerTweens, timerRoot, TweenInfo.new(
		0.2,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	), {
		GroupTransparency = 1,
	})

	fadeOut.Completed:Connect(function()
		if not timerVisible then
			timerRoot.Visible = false
		end
	end)
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
	timerLabel.Text = formatRemainingTime(getRemainingSeconds(currentState))
end

local function startCountdown()
	countdownToken += 1
	local thisToken = countdownToken

	task.spawn(function()
		while thisToken == countdownToken and currentState and currentState.Active == true do
			updateTimerText()
			if getRemainingSeconds(currentState) <= 0 then
				break
			end
			task.wait(1)
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
