local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UiFolder = ReplicatedStorage:WaitForChild("UI")
local Responsive = require(UiFolder:WaitForChild("Responsive"))
local HudLayout = require(UiFolder:WaitForChild("HudLayout"))

local REMOTE_NAME = "ServerRestartAnnouncement"
local GUI_NAME = "ServerRestartAnnouncementGui"
local DISPLAY_ORDER = 10060
local BASE_WIDTH = 460
local BASE_HEIGHT = 70
local MIN_WIDTH = 300
local MAX_WIDTH = 520
local SLIDE_OFFSET = 14
local FADE_IN_TIME = 0.18
local FADE_OUT_TIME = 0.22

local activeTweens = {}
local displayToken = 0

local function create(className, props, children)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

local function cancelTweens()
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

local screenGui = create("ScreenGui", {
	Name = GUI_NAME,
	DisplayOrder = DISPLAY_ORDER,
	Enabled = true,
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
screenGui.Parent = playerGui

local root = create("CanvasGroup", {
	Name = "ServerRestartBanner",
	AnchorPoint = Vector2.new(0.5, 0),
	BackgroundColor3 = Color3.fromRGB(12, 18, 26),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	GroupTransparency = 1,
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.fromOffset(BASE_WIDTH, BASE_HEIGHT),
	Visible = false,
	ZIndex = 20,
}, {
	create("UICorner", {
		CornerRadius = UDim.new(0, 8),
	}),
	create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = Color3.fromRGB(255, 190, 66),
		Thickness = 1,
		Transparency = 0.08,
	}),
})
root.Parent = screenGui

local rootScale = create("UIScale", {
	Name = "BannerScale",
	Scale = 1,
})
rootScale.Parent = root

local sizeConstraint = create("UISizeConstraint", {
	Name = "BannerSize",
	MinSize = Vector2.new(MIN_WIDTH, BASE_HEIGHT),
	MaxSize = Vector2.new(MAX_WIDTH, BASE_HEIGHT),
})
sizeConstraint.Parent = root

local accent = create("Frame", {
	Name = "Accent",
	BackgroundColor3 = Color3.fromRGB(255, 190, 66),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.new(0, 5, 1, 0),
	ZIndex = 21,
}, {
	create("UICorner", {
		CornerRadius = UDim.new(0, 8),
	}),
})
accent.Parent = root

local icon = create("TextLabel", {
	Name = "Icon",
	BackgroundColor3 = Color3.fromRGB(255, 190, 66),
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBlack,
	Text = "!",
	TextColor3 = Color3.fromRGB(24, 18, 8),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	Position = UDim2.fromOffset(20, 17),
	Size = UDim2.fromOffset(36, 36),
	ZIndex = 22,
}, {
	create("UICorner", {
		CornerRadius = UDim.new(1, 0),
	}),
})
icon.Parent = root

local messageLabel = create("TextLabel", {
	Name = "Message",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	RichText = false,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 247, 220),
	TextSize = 16,
	TextTruncate = Enum.TextTruncate.AtEnd,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	Position = UDim2.fromOffset(72, 0),
	Size = UDim2.new(1, -92, 1, 0),
	ZIndex = 22,
})
messageLabel.Parent = root

local function applyLayout()
	local viewport = Responsive.getViewportSize()
	local mode = Responsive.getHudLayoutMode(viewport)
	local layout = HudLayout.getTopBanner(mode)
	local scale = layout.announcementScale or layout.scale or Responsive.getUiScale(viewport)
	local topOffset = layout.topOffset or 96
	local width = math.clamp(math.floor(viewport.X * 0.56), MIN_WIDTH, BASE_WIDTH)

	if mode == "phone" then
		width = math.clamp(math.floor(viewport.X - 28), MIN_WIDTH, BASE_WIDTH)
	elseif mode == "tablet" then
		width = math.clamp(math.floor(viewport.X * 0.62), MIN_WIDTH, BASE_WIDTH)
	end

	rootScale.Scale = scale
	root.Size = UDim2.fromOffset(width, BASE_HEIGHT)
	root.Position = UDim2.new(0.5, 0, 0, topOffset)
end

local function hide(token)
	if token ~= nil and token ~= displayToken then
		return
	end

	cancelTweens()
	local activeToken = displayToken
	tween(root, TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		GroupTransparency = 1,
		Position = root.Position + UDim2.fromOffset(0, -SLIDE_OFFSET),
	})

	task.delay(FADE_OUT_TIME, function()
		if displayToken ~= activeToken then
			return
		end
		root.Visible = false
	end)
end

local function show(payload)
	local message = if typeof(payload) == "table" then tostring(payload.Message or payload.message or "") else tostring(payload or "")
	if message == "" then
		return
	end

	displayToken += 1
	local token = displayToken
	local duration = if typeof(payload) == "table" then tonumber(payload.Duration or payload.duration) or 5 else 5
	local sticky = typeof(payload) == "table" and payload.Sticky == true

	applyLayout()
	messageLabel.Text = message
	root.Visible = true
	root.GroupTransparency = 1
	root.Position = root.Position + UDim2.fromOffset(0, -SLIDE_OFFSET)

	cancelTweens()
	tween(root, TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
		Position = root.Position + UDim2.fromOffset(0, SLIDE_OFFSET),
	})

	if not sticky then
		task.delay(math.max(0.5, duration), function()
			hide(token)
		end)
	end
end

local function connectCamera(camera)
	if not camera then
		return
	end

	camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyLayout)
end

applyLayout()
connectCamera(Workspace.CurrentCamera)
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	applyLayout()
	connectCamera(Workspace.CurrentCamera)
end)

local remote = ReplicatedStorage:WaitForChild(REMOTE_NAME, 30)
if remote and remote:IsA("RemoteEvent") then
	remote.OnClientEvent:Connect(show)
else
	warn("[ServerRestartAnnouncement] RemoteEvent unavailable.")
end
