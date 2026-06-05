local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local EconomyConfig = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))

local config = if typeof(EconomyConfig.AFKTeleport) == "table" then EconomyConfig.AFKTeleport else {}
local remoteConfig = if typeof(config.Remotes) == "table" then config.Remotes else {}
local rewardConfig = if typeof(config.Rewards) == "table" then config.Rewards else {}

local function getPlaceId(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function getLocalAfkPlaceId()
	local placePairsByEnvironment = config.PlacePairsByEnvironment
	if typeof(placePairsByEnvironment) == "table" then
		for _, placePair in pairs(placePairsByEnvironment) do
			if typeof(placePair) == "table" then
				local afkPlaceId = getPlaceId(placePair.AFKPlaceId)
				if afkPlaceId > 0 and game.PlaceId == afkPlaceId then
					return afkPlaceId
				end
			end
		end
	end

	return getPlaceId(config.AFKPlaceId)
end

local AFK_PLACE_ID = getLocalAfkPlaceId()
local IS_LOCAL_AFK_PLACE = AFK_PLACE_ID > 0 and game.PlaceId == AFK_PLACE_ID

local STATE_EVENT_NAME = tostring(remoteConfig.StateEventName or "AFKTeleportState")
local STATE_REQUEST_NAME = tostring(remoteConfig.StateRequestName or "AFKTeleportStateRequest")
local RETURN_REQUEST_NAME = tostring(remoteConfig.ReturnRequestName or "AFKTeleportReturnRequest")
local ACTIVITY_PING_EVENT_NAME = tostring(remoteConfig.ActivityPingEventName or "AFKActivityPing")
local ACTIVITY_PING_COOLDOWN_SECONDS = math.max(1, tonumber(config.ActivityPingCooldownSeconds) or 15)
local DISPLAY_ORDER = 10000
local MUSIC_SILENCE_INTERVAL_SECONDS = 2
local TOPBAR_ENABLED_CORE_KEY = "TopbarEnabled"

local MAIN_MUSIC_SOUND_NAMES = {
	"BGMUSIC",
	"Music",
	"BackgroundMusic",
}

local AFK_DISABLED_CORE_GUI_TYPES = {
	Enum.CoreGuiType.Backpack,
	Enum.CoreGuiType.EmotesMenu,
}

local GREEN = Color3.fromRGB(78, 220, 146)
local GOLD = Color3.fromRGB(255, 211, 97)
local GOLD_BRIGHT = Color3.fromRGB(255, 231, 145)
local CYAN = Color3.fromRGB(111, 211, 255)
local RED = Color3.fromRGB(255, 118, 142)
local PANEL_DARK = Color3.fromRGB(11, 13, 18)
local CARD = Color3.fromRGB(31, 35, 43)
local CARD_ALT = Color3.fromRGB(35, 38, 42)
local TEXT = Color3.fromRGB(255, 249, 229)
local MUTED = Color3.fromRGB(198, 204, 214)
local TOAST_BG = Color3.fromRGB(16, 20, 25)
local BACKGROUND_IMAGE = "rbxassetid://124045609313388"
local BACKGROUND_COLOR = Color3.fromRGB(10, 9, 13)
local BACKGROUND_IMAGE_TINT = Color3.fromRGB(255, 238, 218)
local DASHBOARD_MAX_WIDTH = 1160
local DASHBOARD_DESKTOP_MARGIN = 48
local DASHBOARD_MOBILE_MARGIN = 16
local DASHBOARD_DESKTOP_VERTICAL_MARGIN = 42
local DASHBOARD_MOBILE_VERTICAL_MARGIN = 16
local DASHBOARD_DESKTOP_HEIGHT = 720
local DASHBOARD_MOBILE_HEIGHT = 700
local DASHBOARD_COMPACT_BREAKPOINT = 720
local DASHBOARD_DESKTOP_GRID_GAP = 18
local DASHBOARD_MOBILE_GRID_GAP = 12
local DASHBOARD_DESKTOP_CARD_HEIGHT = 132
local DASHBOARD_MOBILE_CARD_HEIGHT = 124
local DASHBOARD_DESKTOP_REWARDS_HEIGHT = 136
local DASHBOARD_MOBILE_REWARDS_HEIGHT = 154
local CARD_STROKE_SAFE_PADDING = 8
local AFK_MOVEMENT_LOCK_ACTION_NAME = "AFKLobbyMovementLock"
local AFK_MOVEMENT_LOCK_PRIORITY = Enum.ContextActionPriority.High.Value + 100

local stateEvent = nil
local stateRequest = nil
local returnRequest = nil
local activityPingEvent = nil
local currentState = nil
local stateReceivedAt = 0
local lastActivityPingAt = 0
local returnInFlight = false
local afkIsolationEnabled = false
local hiddenScreenGuis = {}
local previousCoreGuiEnabledByType = {}
local previousTopbarEnabled = nil
local playerGuiChildAddedConnection = nil
local soundServiceChildAddedConnection = nil
local musicSilenceToken = 0

local function waitForRemote(remotes, remoteName, className)
	local remote = remotes:WaitForChild(remoteName, 30)
	if remote and remote:IsA(className) then
		return remote
	end
	return nil
end

local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
if remotes then
	stateEvent = waitForRemote(remotes, STATE_EVENT_NAME, "RemoteEvent")
	stateRequest = waitForRemote(remotes, STATE_REQUEST_NAME, "RemoteFunction")
	returnRequest = waitForRemote(remotes, RETURN_REQUEST_NAME, "RemoteFunction")
	activityPingEvent = waitForRemote(remotes, ACTIVITY_PING_EVENT_NAME, "RemoteEvent")
end

local function clearLocalJump()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Jump = false
	end
end

local function sinkAfkMovementAction()
	clearLocalJump()
	return Enum.ContextActionResult.Sink
end

local function bindAfkMovementLock()
	ContextActionService:BindActionAtPriority(
		AFK_MOVEMENT_LOCK_ACTION_NAME,
		sinkAfkMovementAction,
		false,
		AFK_MOVEMENT_LOCK_PRIORITY,
		Enum.PlayerActions.CharacterForward,
		Enum.PlayerActions.CharacterBackward,
		Enum.PlayerActions.CharacterLeft,
		Enum.PlayerActions.CharacterRight,
		Enum.PlayerActions.CharacterJump
	)
end

if IS_LOCAL_AFK_PLACE then
	bindAfkMovementLock()
	player.CharacterAdded:Connect(function()
		task.defer(clearLocalJump)
	end)
	UserInputService.JumpRequest:Connect(clearLocalJump)
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AFKTeleportGui"
screenGui.DisplayOrder = DISPLAY_ORDER
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = true
screenGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.BackgroundColor3 = BACKGROUND_COLOR
backdrop.BackgroundTransparency = 0
backdrop.BorderSizePixel = 0
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Visible = false
backdrop.Parent = screenGui

local function applyCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 8)
	corner.Parent = parent
	return corner
end

local function applyStroke(parent, color, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or GOLD
	stroke.Transparency = transparency or 0.4
	stroke.Thickness = 1
	stroke.Parent = parent
	return stroke
end

local function applyGradient(parent, name, color, transparency, rotation)
	local gradient = Instance.new("UIGradient")
	gradient.Name = name
	gradient.Color = color
	if transparency ~= nil then
		gradient.Transparency = transparency
	end
	gradient.Rotation = rotation or 0
	gradient.Parent = parent
	return gradient
end

local function makeText(parent, name, font, color, size)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	return label
end

local backgroundImage = Instance.new("ImageLabel")
backgroundImage.Name = "BackgroundImage"
backgroundImage.BackgroundTransparency = 1
backgroundImage.Image = BACKGROUND_IMAGE
backgroundImage.ImageColor3 = BACKGROUND_IMAGE_TINT
backgroundImage.ImageTransparency = 0
backgroundImage.ScaleType = Enum.ScaleType.Crop
backgroundImage.Size = UDim2.fromScale(1, 1)
backgroundImage.ZIndex = 1
backgroundImage.Parent = backdrop

local gradientHost = Instance.new("Frame")
gradientHost.Name = "GradientHost"
gradientHost.BackgroundTransparency = 1
gradientHost.BorderSizePixel = 0
gradientHost.Size = UDim2.fromScale(1, 1)
gradientHost.ZIndex = 2
gradientHost.Parent = backdrop

local warmBloom = Instance.new("Frame")
warmBloom.Name = "WarmBloom"
warmBloom.AnchorPoint = Vector2.new(0.5, 0.5)
warmBloom.BackgroundColor3 = Color3.fromRGB(255, 178, 72)
warmBloom.BackgroundTransparency = 0.78
warmBloom.BorderSizePixel = 0
warmBloom.Position = UDim2.fromScale(0.62, 0.34)
warmBloom.Rotation = -8
warmBloom.Size = UDim2.fromScale(0.72, 0.58)
warmBloom.ZIndex = 2
warmBloom.Parent = gradientHost
applyCorner(warmBloom, 36)
applyGradient(warmBloom, "WarmBloomGradient", ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 220, 122)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 133, 54)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(43, 116, 190)),
}), NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.92),
	NumberSequenceKeypoint.new(0.45, 0.26),
	NumberSequenceKeypoint.new(1, 0.96),
}), 18)

local vignette = Instance.new("Frame")
vignette.Name = "Vignette"
vignette.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
vignette.BackgroundTransparency = 0.06
vignette.BorderSizePixel = 0
vignette.Size = UDim2.fromScale(1, 1)
vignette.ZIndex = 3
vignette.Parent = backdrop
applyGradient(vignette, "VignetteGradient", ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)), NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(0.34, 0.72),
	NumberSequenceKeypoint.new(0.62, 0.64),
	NumberSequenceKeypoint.new(1, 0.08),
}), 90)

local cinematicShade = Instance.new("Frame")
cinematicShade.Name = "CinematicShade"
cinematicShade.BackgroundColor3 = Color3.fromRGB(12, 8, 10)
cinematicShade.BackgroundTransparency = 0.42
cinematicShade.BorderSizePixel = 0
cinematicShade.Size = UDim2.fromScale(1, 1)
cinematicShade.ZIndex = 4
cinematicShade.Parent = backdrop
applyGradient(cinematicShade, "CinematicGradient", ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(10, 10, 22)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8, 6, 7)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 0, 0)),
}), NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.42),
	NumberSequenceKeypoint.new(0.52, 0.8),
	NumberSequenceKeypoint.new(1, 0.24),
}), 90)

local dashboard = Instance.new("Frame")
dashboard.Name = "Dashboard"
dashboard.BackgroundTransparency = 1
dashboard.BorderSizePixel = 0
dashboard.Size = UDim2.fromScale(1, 1)
dashboard.ZIndex = 5
dashboard.Parent = backdrop

local dashboardPadding = Instance.new("UIPadding")
dashboardPadding.PaddingBottom = UDim.new(0, 0)
dashboardPadding.PaddingLeft = UDim.new(0, 0)
dashboardPadding.PaddingRight = UDim.new(0, 0)
dashboardPadding.PaddingTop = UDim.new(0, 0)
dashboardPadding.Parent = dashboard

local dashboardContainer = Instance.new("Frame")
dashboardContainer.Name = "DashboardContainer"
dashboardContainer.AnchorPoint = Vector2.new(0.5, 0.5)
dashboardContainer.BackgroundTransparency = 1
dashboardContainer.BorderSizePixel = 0
dashboardContainer.Position = UDim2.fromScale(0.5, 0.5)
dashboardContainer.Size = UDim2.new(1, -DASHBOARD_DESKTOP_MARGIN * 2, 1, -DASHBOARD_DESKTOP_VERTICAL_MARGIN * 2)
dashboardContainer.ZIndex = 5
dashboardContainer.Parent = dashboard

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundTransparency = 1
header.BorderSizePixel = 0
header.Size = UDim2.new(1, 0, 0, 104)
header.ZIndex = 6
header.Parent = dashboardContainer

local headerTitle = makeText(header, "Title", Enum.Font.GothamBlack, GOLD_BRIGHT, 36)
headerTitle.Size = UDim2.new(1, 0, 0, 46)
headerTitle.Text = "AFK Lobby"
headerTitle.TextWrapped = false
headerTitle.TextXAlignment = Enum.TextXAlignment.Center
headerTitle.ZIndex = 6

local headerSubtitle = makeText(header, "Subtitle", Enum.Font.Gotham, MUTED, 16)
headerSubtitle.Position = UDim2.fromOffset(2, 50)
headerSubtitle.Size = UDim2.new(1, 0, 0, 26)
headerSubtitle.Text = "Stay here to earn rewards while you're away."
headerSubtitle.TextXAlignment = Enum.TextXAlignment.Center
headerSubtitle.TextTruncate = Enum.TextTruncate.AtEnd
headerSubtitle.ZIndex = 6

local statusLabel = makeText(header, "Status", Enum.Font.GothamMedium, GREEN, 14)
statusLabel.Position = UDim2.fromOffset(2, 78)
statusLabel.Size = UDim2.new(1, 0, 0, 22)
statusLabel.Text = "Loading AFK rewards..."
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
statusLabel.ZIndex = 6

local footer = Instance.new("Frame")
footer.Name = "Footer"
footer.AnchorPoint = Vector2.new(0, 1)
footer.BackgroundTransparency = 1
footer.BorderSizePixel = 0
footer.Position = UDim2.fromScale(0, 1)
footer.Size = UDim2.new(1, 0, 0, 86)
footer.ZIndex = 6
footer.Parent = dashboardContainer

local button = Instance.new("TextButton")
button.Name = "LeaveButton"
button.AnchorPoint = Vector2.new(0.5, 0)
button.AutoButtonColor = true
button.BackgroundColor3 = GREEN
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBlack
button.Position = UDim2.fromScale(0.5, 0)
button.Size = UDim2.fromOffset(260, 44)
button.Text = "Leave AFK Lobby"
button.TextColor3 = PANEL_DARK
button.TextSize = 16
button.TextWrapped = true
button.ZIndex = 7
button.Parent = footer
applyCorner(button, 8)
applyStroke(button, GOLD_BRIGHT, 0.55)

local autoSaveNote = makeText(footer, "AutoSaveNote", Enum.Font.GothamMedium, MUTED, 13)
autoSaveNote.AnchorPoint = Vector2.new(0.5, 0)
autoSaveNote.Position = UDim2.new(0.5, 0, 0, 52)
autoSaveNote.Size = UDim2.new(1, 0, 0, 24)
autoSaveNote.Text = "Rewards are added to your inventory automatically."
autoSaveNote.TextXAlignment = Enum.TextXAlignment.Center
autoSaveNote.ZIndex = 7

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Scroll"
scroll.Active = true
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.CanvasSize = UDim2.fromOffset(0, 0)
scroll.Position = UDim2.fromOffset(0, 116)
scroll.ScrollBarImageColor3 = GOLD
scroll.ScrollBarThickness = 6
scroll.Size = UDim2.new(1, 0, 1, -214)
scroll.ZIndex = 6
scroll.Parent = dashboardContainer

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
scrollLayout.Padding = UDim.new(0, DASHBOARD_DESKTOP_GRID_GAP)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll

local scrollPadding = Instance.new("UIPadding")
scrollPadding.PaddingBottom = UDim.new(0, CARD_STROKE_SAFE_PADDING)
scrollPadding.PaddingLeft = UDim.new(0, CARD_STROKE_SAFE_PADDING)
scrollPadding.PaddingRight = UDim.new(0, CARD_STROKE_SAFE_PADDING)
scrollPadding.PaddingTop = UDim.new(0, CARD_STROKE_SAFE_PADDING)
scrollPadding.Parent = scroll

local cardsGrid = Instance.new("Frame")
cardsGrid.Name = "Cards"
cardsGrid.BackgroundTransparency = 1
cardsGrid.LayoutOrder = 1
cardsGrid.Size = UDim2.new(1, -CARD_STROKE_SAFE_PADDING * 2, 0, 256)
cardsGrid.ZIndex = 6
cardsGrid.Parent = scroll

local cardsGridLayout = Instance.new("UIGridLayout")
cardsGridLayout.CellPadding = UDim2.fromOffset(DASHBOARD_DESKTOP_GRID_GAP, DASHBOARD_DESKTOP_GRID_GAP)
cardsGridLayout.CellSize = UDim2.new(0.5, -DASHBOARD_DESKTOP_GRID_GAP / 2, 0, DASHBOARD_DESKTOP_CARD_HEIGHT)
cardsGridLayout.FillDirectionMaxCells = 2
cardsGridLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsGridLayout.Parent = cardsGrid

local function makeStatCard(cardTitle, value, detail, accent)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = CARD
	card.BorderSizePixel = 0
	card.Size = UDim2.fromOffset(260, DASHBOARD_DESKTOP_CARD_HEIGHT)
	card.ZIndex = 6
	applyCorner(card, 8)
	applyStroke(card, accent, 0.38)

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 14)
	padding.Parent = card

	local titleLabel = makeText(card, "Title", Enum.Font.GothamMedium, MUTED, 14)
	titleLabel.Size = UDim2.new(1, 0, 0, 22)
	titleLabel.Text = cardTitle
	titleLabel.ZIndex = 7

	local valueLabel = makeText(card, "Value", Enum.Font.GothamBlack, accent, 28)
	valueLabel.Position = UDim2.fromOffset(0, 32)
	valueLabel.Size = UDim2.new(1, 0, 0, 40)
	valueLabel.Text = value
	valueLabel.TextScaled = true
	valueLabel.ZIndex = 7

	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 28
	sizeLimit.MinTextSize = 13
	sizeLimit.Parent = valueLabel

	local detailLabel = makeText(card, "Detail", Enum.Font.Gotham, MUTED, 13)
	detailLabel.Position = UDim2.fromOffset(0, 80)
	detailLabel.Size = UDim2.new(1, 0, 0, 34)
	detailLabel.Text = detail
	detailLabel.TextYAlignment = Enum.TextYAlignment.Top
	detailLabel.ZIndex = 7

	return {
		Frame = card,
		Value = valueLabel,
		Detail = detailLabel,
		Stroke = card:FindFirstChildOfClass("UIStroke"),
	}
end

local function makeWideCard(cardTitle, body, accent, height)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = CARD_ALT
	card.BorderSizePixel = 0
	card.LayoutOrder = 0
	card.Size = UDim2.new(1, -CARD_STROKE_SAFE_PADDING * 2, 0, height or DASHBOARD_DESKTOP_REWARDS_HEIGHT)
	card.ZIndex = 6
	applyCorner(card, 8)
	applyStroke(card, accent, 0.46)

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 14)
	padding.PaddingLeft = UDim.new(0, 16)
	padding.PaddingRight = UDim.new(0, 16)
	padding.PaddingTop = UDim.new(0, 14)
	padding.Parent = card

	local titleLabel = makeText(card, "Title", Enum.Font.GothamBold, GOLD_BRIGHT, 16)
	titleLabel.Size = UDim2.new(1, 0, 0, 24)
	titleLabel.Text = cardTitle
	titleLabel.ZIndex = 7

	local bodyLabel = makeText(card, "Body", Enum.Font.GothamMedium, TEXT, 15)
	bodyLabel.Position = UDim2.fromOffset(0, 32)
	bodyLabel.Size = UDim2.new(1, 0, 1, -34)
	bodyLabel.Text = body
	bodyLabel.TextWrapped = true
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.ZIndex = 7

	return {
		Frame = card,
		Body = bodyLabel,
		Stroke = card:FindFirstChildOfClass("UIStroke"),
	}
end

local chestsEarnedCard = makeStatCard("Gold Chests Earned", "0", "Saved to your inventory.", GOLD_BRIGHT)
chestsEarnedCard.Frame.LayoutOrder = 1
chestsEarnedCard.Frame.Parent = cardsGrid

local nextChestCard = makeStatCard("Next Gold Chest", "Loading", "Chest timer is starting.", GREEN)
nextChestCard.Frame.LayoutOrder = 2
nextChestCard.Frame.Parent = cardsGrid

local beliEarnedCard = makeStatCard("Beli Earned", "0", "Saved while you stay AFK.", GOLD)
beliEarnedCard.Frame.LayoutOrder = 3
beliEarnedCard.Frame.Parent = cardsGrid

local afkRateCard = makeStatCard("Beli While Away", "Loading", "Based on your ship crew.", CYAN)
afkRateCard.Frame.LayoutOrder = 4
afkRateCard.Frame.Parent = cardsGrid

local bonusCard = makeWideCard("AFK Rewards", "Loading reward rates...", GOLD, 126)
bonusCard.Frame.LayoutOrder = 2
bonusCard.Frame.Parent = scroll

local toastHost = Instance.new("Frame")
toastHost.Name = "Toasts"
toastHost.AnchorPoint = Vector2.new(1, 0)
toastHost.BackgroundTransparency = 1
toastHost.Position = UDim2.new(1, -24, 0, 84)
toastHost.Size = UDim2.fromOffset(340, 220)
toastHost.ZIndex = 20
toastHost.Parent = screenGui

local toastLayout = Instance.new("UIListLayout")
toastLayout.FillDirection = Enum.FillDirection.Vertical
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.Padding = UDim.new(0, 8)
toastLayout.Parent = toastHost

local function updateGridHeight()
	cardsGrid.Size = UDim2.new(1, -CARD_STROKE_SAFE_PADDING * 2, 0, cardsGridLayout.AbsoluteContentSize.Y)
end

cardsGridLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateGridHeight)
task.defer(updateGridHeight)

local function updateResponsiveLayout()
	local width = backdrop.AbsoluteSize.X
	local height = backdrop.AbsoluteSize.Y
	if width <= 0 or height <= 0 then
		updateGridHeight()
		return
	end

	local compact = width < DASHBOARD_COMPACT_BREAKPOINT
	local horizontalMargin = if compact then DASHBOARD_MOBILE_MARGIN else DASHBOARD_DESKTOP_MARGIN
	local verticalMargin = if compact then DASHBOARD_MOBILE_VERTICAL_MARGIN else DASHBOARD_DESKTOP_VERTICAL_MARGIN
	local availableWidth = math.max(0, width - horizontalMargin * 2)
	local availableHeight = math.max(0, height - verticalMargin * 2)
	local containerWidth = if compact then availableWidth else math.min(availableWidth, DASHBOARD_MAX_WIDTH)
	local targetHeight = if compact then DASHBOARD_MOBILE_HEIGHT else DASHBOARD_DESKTOP_HEIGHT
	local containerHeight = math.min(availableHeight, targetHeight)
	local headerHeight = if compact then 132 else 116
	local footerHeight = if compact then 92 else 90
	local gap = if compact then DASHBOARD_MOBILE_GRID_GAP else DASHBOARD_DESKTOP_GRID_GAP
	local cardHeight = if compact then DASHBOARD_MOBILE_CARD_HEIGHT else DASHBOARD_DESKTOP_CARD_HEIGHT
	local rewardsHeight = if compact then DASHBOARD_MOBILE_REWARDS_HEIGHT else DASHBOARD_DESKTOP_REWARDS_HEIGHT
	local scrollTop = headerHeight + gap
	local scrollHeight = math.max(0, containerHeight - headerHeight - footerHeight - gap * 2)

	dashboardContainer.Size = UDim2.fromOffset(containerWidth, containerHeight)
	dashboardContainer.Position = UDim2.fromScale(0.5, 0.5)

	dashboardPadding.PaddingBottom = UDim.new(0, 0)
	dashboardPadding.PaddingLeft = UDim.new(0, 0)
	dashboardPadding.PaddingRight = UDim.new(0, 0)
	dashboardPadding.PaddingTop = UDim.new(0, 0)

	header.Position = UDim2.fromOffset(0, 0)
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	footer.Position = UDim2.fromOffset(0, containerHeight)
	footer.Size = UDim2.new(1, 0, 0, footerHeight)
	scroll.Position = UDim2.fromOffset(0, scrollTop)
	scroll.Size = UDim2.new(1, 0, 0, scrollHeight)
	scrollLayout.Padding = UDim.new(0, gap)
	scroll.ScrollBarThickness = if compact then 4 else 6
	cardsGridLayout.CellPadding = UDim2.fromOffset(gap, gap)
	cardsGridLayout.CellSize = if compact
		then UDim2.new(1, 0, 0, cardHeight)
		else UDim2.new(0.5, -gap / 2, 0, cardHeight)
	bonusCard.Frame.Size = UDim2.new(1, -CARD_STROKE_SAFE_PADDING * 2, 0, rewardsHeight)

	if compact then
		headerTitle.Position = UDim2.fromOffset(0, 0)
		headerTitle.Size = UDim2.new(1, 0, 0, 42)
		headerTitle.TextSize = 32
		headerSubtitle.Position = UDim2.fromOffset(0, 46)
		headerSubtitle.Size = UDim2.new(1, 0, 0, 42)
		headerSubtitle.TextTruncate = Enum.TextTruncate.None
		headerSubtitle.TextSize = 15
		statusLabel.Position = UDim2.fromOffset(0, 94)
		statusLabel.Size = UDim2.new(1, 0, 0, 24)
		statusLabel.TextSize = 14
		button.Size = UDim2.new(1, 0, 0, 44)
		button.TextSize = 16
		autoSaveNote.Position = UDim2.new(0.5, 0, 0, 52)
		autoSaveNote.Size = UDim2.new(1, 0, 0, 30)
		cardsGridLayout.FillDirectionMaxCells = 1
	else
		headerTitle.Position = UDim2.fromOffset(0, 0)
		headerTitle.Size = UDim2.new(1, 0, 0, 54)
		headerTitle.TextSize = 42
		headerSubtitle.Position = UDim2.fromOffset(0, 56)
		headerSubtitle.Size = UDim2.new(1, 0, 0, 26)
		headerSubtitle.TextTruncate = Enum.TextTruncate.AtEnd
		headerSubtitle.TextSize = 17
		statusLabel.Position = UDim2.fromOffset(0, 84)
		statusLabel.Size = UDim2.new(1, 0, 0, 24)
		statusLabel.TextSize = 15
		button.Size = UDim2.fromOffset(300, 46)
		button.TextSize = 17
		autoSaveNote.Position = UDim2.new(0.5, 0, 0, 56)
		autoSaveNote.Size = UDim2.new(1, 0, 0, 24)
		cardsGridLayout.FillDirectionMaxCells = 2
	end
	updateGridHeight()
end

backdrop:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateResponsiveLayout)
task.defer(updateResponsiveLayout)

local function getCoreGuiEnabled(coreGuiType)
	local ok, enabled = pcall(function()
		return StarterGui:GetCoreGuiEnabled(coreGuiType)
	end)
	if ok and typeof(enabled) == "boolean" then
		return enabled
	end
	return true
end

local function setCoreGuiEnabled(coreGuiType, enabled)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
	end)
end

local function setCoreGuiSuppressed(suppressed)
	for _, coreGuiType in ipairs(AFK_DISABLED_CORE_GUI_TYPES) do
		if suppressed then
			if previousCoreGuiEnabledByType[coreGuiType] == nil then
				previousCoreGuiEnabledByType[coreGuiType] = getCoreGuiEnabled(coreGuiType)
			end
			setCoreGuiEnabled(coreGuiType, false)
		else
			local previous = previousCoreGuiEnabledByType[coreGuiType]
			if previous ~= nil then
				setCoreGuiEnabled(coreGuiType, previous)
				previousCoreGuiEnabledByType[coreGuiType] = nil
			end
		end
	end
end

local function getTopbarEnabled()
	local ok, enabled = pcall(function()
		return StarterGui:GetCore(TOPBAR_ENABLED_CORE_KEY)
	end)
	if ok and typeof(enabled) == "boolean" then
		return enabled
	end
	return true
end

local function setTopbarEnabled(enabled)
	pcall(function()
		StarterGui:SetCore(TOPBAR_ENABLED_CORE_KEY, enabled)
	end)
end

local function setTopbarSuppressed(suppressed)
	if suppressed then
		if previousTopbarEnabled == nil then
			previousTopbarEnabled = getTopbarEnabled()
		end
		setTopbarEnabled(false)
	elseif previousTopbarEnabled ~= nil then
		setTopbarEnabled(previousTopbarEnabled)
		previousTopbarEnabled = nil
	end
end

local function shouldKeepScreenGui(gui)
	return gui == screenGui or gui.Name == screenGui.Name
end

local function suppressScreenGui(gui)
	if not gui:IsA("ScreenGui") or shouldKeepScreenGui(gui) then
		return
	end
	if hiddenScreenGuis[gui] == nil then
		hiddenScreenGuis[gui] = gui.Enabled
	end
	gui.Enabled = false
end

local function suppressExistingPlayerGuis()
	for _, child in ipairs(playerGui:GetChildren()) do
		suppressScreenGui(child)
	end
end

local function restorePlayerGuis()
	for gui, wasEnabled in pairs(hiddenScreenGuis) do
		if gui.Parent ~= nil then
			gui.Enabled = wasEnabled == true
		end
	end
	table.clear(hiddenScreenGuis)
end

local function silenceSound(sound)
	if not sound:IsA("Sound") then
		return
	end
	sound:Stop()
	sound.Volume = 0
end

local function silenceMainMusicInstance(instance)
	if instance:IsA("Sound") then
		silenceSound(instance)
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		silenceSound(descendant)
	end
end

local function silenceMainMusic()
	for _, soundName in ipairs(MAIN_MUSIC_SOUND_NAMES) do
		local instance = SoundService:FindFirstChild(soundName)
		if instance ~= nil then
			silenceMainMusicInstance(instance)
		end
	end
end

local function startMusicSilenceLoop()
	musicSilenceToken += 1
	local token = musicSilenceToken
	task.spawn(function()
		while afkIsolationEnabled and token == musicSilenceToken do
			silenceMainMusic()
			task.wait(MUSIC_SILENCE_INTERVAL_SECONDS)
		end
	end)
end

local function setAfkVisualIsolation(enabled)
	enabled = enabled == true
	if afkIsolationEnabled == enabled then
		if enabled then
			setCoreGuiSuppressed(true)
			setTopbarSuppressed(true)
			suppressExistingPlayerGuis()
			silenceMainMusic()
		end
		return
	end

	afkIsolationEnabled = enabled
	if enabled then
		setCoreGuiSuppressed(true)
		setTopbarSuppressed(true)
		suppressExistingPlayerGuis()
		if playerGuiChildAddedConnection == nil then
			playerGuiChildAddedConnection = playerGui.ChildAdded:Connect(function(child)
				task.defer(function()
					if afkIsolationEnabled then
						suppressScreenGui(child)
					end
				end)
			end)
		end

		silenceMainMusic()
		if soundServiceChildAddedConnection == nil then
			soundServiceChildAddedConnection = SoundService.ChildAdded:Connect(function(child)
				task.defer(function()
					if afkIsolationEnabled then
						silenceMainMusicInstance(child)
					end
				end)
			end)
		end
		startMusicSilenceLoop()
	else
		musicSilenceToken += 1
		if playerGuiChildAddedConnection ~= nil then
			playerGuiChildAddedConnection:Disconnect()
			playerGuiChildAddedConnection = nil
		end
		if soundServiceChildAddedConnection ~= nil then
			soundServiceChildAddedConnection:Disconnect()
			soundServiceChildAddedConnection = nil
		end
		restorePlayerGuis()
		setTopbarSuppressed(false)
		setCoreGuiSuppressed(false)
	end
end

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		if minutes > 0 then
			return string.format("%dh %dm", hours, minutes)
		end
		return string.format("%dh", hours)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

local function formatInterval(seconds)
	seconds = math.max(1, math.floor(tonumber(seconds) or 1))
	if seconds == 3600 then
		return "1 hour"
	end
	return formatDuration(seconds)
end

local function formatPercent(multiplier)
	return tostring(math.max(0, math.floor((tonumber(multiplier) or 0) * 100 + 0.5))) .. "%"
end

local function formatCurrencyAmount(amount)
	return CurrencyUtil.formatAmount(math.max(0, math.floor(tonumber(amount) or 0)))
end

local function formatCurrencyRate(amount)
	return CurrencyUtil.formatIncomePerSecond(math.max(0, tonumber(amount) or 0))
end

local function getLocalVip()
	local passes = player:FindFirstChild("Passes")
	local vip = passes and passes:FindFirstChild("VIP")
	return vip ~= nil and vip:IsA("BoolValue") and vip.Value == true
end

local function getSummaryVip(summary)
	if typeof(summary) == "table" and typeof(summary.IsVIP) == "boolean" then
		return summary.IsVIP
	end
	return getLocalVip()
end

local function getChestIntervalSeconds(summary)
	local isVip = getSummaryVip(summary)
	local settings = if isVip then rewardConfig.VIP else rewardConfig.Standard
	settings = if typeof(settings) == "table" then settings else {}
	local fallback = if isVip then 5400 else 3600
	return math.max(1, math.floor(tonumber(summary and summary.ChestIntervalSeconds) or tonumber(settings.ChestIntervalSeconds) or fallback))
end

local function getChestsPerInterval(summary)
	local isVip = getSummaryVip(summary)
	local settings = if isVip then rewardConfig.VIP else rewardConfig.Standard
	settings = if typeof(settings) == "table" then settings else {}
	local fallback = if isVip then 2 else 1
	return math.max(1, math.floor(tonumber(summary and summary.ChestsPerInterval) or tonumber(settings.ChestsPerInterval) or fallback))
end

local function getChestTier(summary)
	return tostring(summary and summary.ChestTier or rewardConfig.ChestTier or "Gold")
end

local function getAfkRateMultiplier(summary)
	return math.max(0, tonumber(summary and summary.AFKIncomeMultiplier) or tonumber(rewardConfig.BeliRateMultiplier) or 0.3)
end

local function isLocalAfkPlace()
	return IS_LOCAL_AFK_PLACE
end

local function getElapsedSinceState()
	if typeof(currentState) ~= "table" or currentState.SessionActive ~= true then
		return 0
	end
	return math.max(0, math.floor(os.clock() - stateReceivedAt))
end

local function getVisibleRewards()
	local summary = {}
	if typeof(currentState) == "table" and typeof(currentState.Rewards) == "table" then
		summary = table.clone(currentState.Rewards)
	end

	local elapsedDelta = getElapsedSinceState()
	local intervalSeconds = getChestIntervalSeconds(summary)
	local chestsPerInterval = getChestsPerInterval(summary)
	local nextChest = tonumber(summary.NextChestInSeconds or summary.SecondsUntilNextChest)
	local chestProgress = math.max(0, math.floor(tonumber(summary.ChestProgressSeconds) or 0))
	if nextChest ~= nil then
		nextChest = math.max(0, math.floor(nextChest) - elapsedDelta)
		chestProgress = if nextChest <= 0 then intervalSeconds else math.max(0, intervalSeconds - nextChest)
	else
		chestProgress = math.min(intervalSeconds, chestProgress + elapsedDelta)
		nextChest = math.max(0, intervalSeconds - chestProgress)
	end

	local afkIncomePerSecond = math.max(0, tonumber(summary.AFKIncomePerSecond) or 0)
	local baseBeli = math.max(0, math.floor(tonumber(summary.BeliEarnedThisSession or summary.Beli) or 0))
	local visibleBeli = baseBeli + math.floor(afkIncomePerSecond * elapsedDelta)

	return {
		ChestTier = getChestTier(summary),
		ChestIntervalSeconds = intervalSeconds,
		ChestsPerInterval = chestsPerInterval,
		NextChestInSeconds = nextChest,
		ChestProgressSeconds = chestProgress,
		ChestsEarnedThisSession = math.max(0, math.floor(tonumber(summary.ChestsEarnedThisSession or summary.ClaimableChests) or 0)),
		BeliEarnedThisSession = visibleBeli,
		ShipIncomePerSecond = math.max(0, tonumber(summary.ShipIncomePerSecond) or 0),
		AFKIncomeMultiplier = getAfkRateMultiplier(summary),
		AFKIncomePerSecond = afkIncomePerSecond,
		IsVIP = getSummaryVip(summary),
		AutoSaveEnabled = summary.AutoSaveEnabled ~= false,
	}
end

local function formatChestRate(chestsPerInterval, chestTier, intervalSeconds)
	return tostring(chestsPerInterval)
		.. " "
		.. chestTier
		.. " Chest"
		.. (if chestsPerInterval == 1 then "" else "s")
		.. " every "
		.. formatInterval(intervalSeconds)
end

local function getBonusText(rewards)
	local chestTier = getChestTier(rewards)
	local intervalSeconds = getChestIntervalSeconds(rewards)
	local chestsPerInterval = getChestsPerInterval(rewards)
	local chestRateText = formatChestRate(chestsPerInterval, chestTier, intervalSeconds)
	local chestLine = if getSummaryVip(rewards)
		then "VIP Bonus Active: " .. chestRateText .. "."
		else "You earn " .. chestRateText .. "."
	return chestLine
		.. "\nYou also earn "
		.. formatPercent(getAfkRateMultiplier(rewards))
		.. " of your ship's Beli while AFK."
		.. "\nRewards are added to your inventory automatically."
end

local function setStatCard(card, value, detail, accent)
	card.Value.Text = tostring(value or "")
	card.Detail.Text = tostring(detail or "")
	if accent ~= nil then
		card.Value.TextColor3 = accent
		if card.Stroke ~= nil then
			card.Stroke.Color = accent
		end
	end
end

local function setButtonEnabled(enabled)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then GREEN else Color3.fromRGB(90, 104, 112)
end

local function showToast(message, color, duration)
	local toast = Instance.new("Frame")
	toast.Name = "Toast"
	toast.AutomaticSize = Enum.AutomaticSize.Y
	toast.BackgroundColor3 = TOAST_BG
	toast.BorderSizePixel = 0
	toast.Size = UDim2.fromScale(1, 0)
	toast.ZIndex = 21
	toast.Parent = toastHost
	applyCorner(toast, 8)
	applyStroke(toast, color or GOLD, 0.1)

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = toast

	local label = makeText(toast, "Message", Enum.Font.GothamBold, color or TEXT, 14)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Size = UDim2.fromScale(1, 0)
	label.Text = tostring(message or "")
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 22

	task.delay(math.max(1, tonumber(duration) or 3), function()
		if toast.Parent ~= nil then
			toast:Destroy()
		end
	end)
end

local function renderLoadingDashboard()
	updateResponsiveLayout()
	local fallbackRewards = getVisibleRewards()
	statusLabel.Text = "Setting up your AFK rewards..."
	statusLabel.TextColor3 = GOLD
	setStatCard(chestsEarnedCard, "Loading", "Checking your saved rewards.", GOLD_BRIGHT)
	setStatCard(nextChestCard, "Loading", "Chest timer is starting.", GREEN)
	setStatCard(beliEarnedCard, "Loading", "Checking your ship income.", GOLD)
	setStatCard(afkRateCard, "Loading", "Based on your ship crew.", CYAN)
	bonusCard.Body.Text = getBonusText(fallbackRewards)
	button.Text = "Loading..."
	setButtonEnabled(false)
end

local function renderAfkDashboard()
	updateResponsiveLayout()

	local rewards = getVisibleRewards()
	local dataReady = currentState.DataReady ~= false
	local pending = currentState.TeleportPending == true
	local returnEnabled = dataReady and pending ~= true and returnInFlight ~= true and returnRequest ~= nil
	local statusText = if dataReady
		then "Rewards are saving automatically."
		else "Setting up your AFK rewards..."

	if dataReady ~= true then
		statusText = "Setting up your AFK rewards..."
	elseif pending or returnInFlight then
		statusText = "Leaving the AFK lobby..."
	elseif rewards.AutoSaveEnabled ~= true then
		statusText = "Rewards will save when you leave."
	end

	statusLabel.Text = statusText
	statusLabel.TextColor3 = if dataReady ~= true then GOLD elseif pending or returnInFlight then GOLD else GREEN

	local chestTier = rewards.ChestTier
	local chestsEarned = rewards.ChestsEarnedThisSession
	setStatCard(
		chestsEarnedCard,
		tostring(chestsEarned),
		chestTier .. " Chest" .. (if chestsEarned == 1 then "" else "s") .. " saved this session.",
		GOLD_BRIGHT
	)

	if rewards.NextChestInSeconds <= 0 then
		setStatCard(nextChestCard, "Saving...", "Adding your next chest automatically.", GREEN)
	else
		setStatCard(
			nextChestCard,
			formatDuration(rewards.NextChestInSeconds),
			formatDuration(rewards.ChestProgressSeconds) .. " / " .. formatDuration(rewards.ChestIntervalSeconds),
			GREEN
		)
	end

	setStatCard(
		beliEarnedCard,
		formatCurrencyAmount(rewards.BeliEarnedThisSession),
		"Saved Beli from your AFK session.",
		GOLD
	)
	setStatCard(
		afkRateCard,
		formatCurrencyRate(rewards.AFKIncomePerSecond),
		formatPercent(rewards.AFKIncomeMultiplier) .. " of " .. formatCurrencyRate(rewards.ShipIncomePerSecond) .. " ship income.",
		CYAN
	)

	bonusCard.Body.Text = getBonusText(rewards)
	button.Text = if returnInFlight or pending then "Leaving..." else "Leave AFK Lobby"
	setButtonEnabled(returnEnabled)
end

local function render()
	if typeof(currentState) ~= "table" then
		local showLoading = isLocalAfkPlace()
		setAfkVisualIsolation(showLoading)
		backdrop.Visible = showLoading
		if showLoading then
			renderLoadingDashboard()
		end
		return
	end

	local isAfkLobby = currentState.Role == "AFKPlace"
	local showAfkBackdrop = isAfkLobby and isLocalAfkPlace()
	setAfkVisualIsolation(showAfkBackdrop)
	backdrop.Visible = showAfkBackdrop
	if not showAfkBackdrop then
		return
	end

	renderAfkDashboard()
end

local function setCurrentState(state)
	if typeof(state) ~= "table" then
		return
	end
	currentState = state
	stateReceivedAt = os.clock()
	render()
end

local function requestState()
	if stateRequest == nil then
		return
	end
	local ok, state = pcall(function()
		return stateRequest:InvokeServer()
	end)
	if ok and typeof(state) == "table" then
		setCurrentState(state)
	end
end

local function describeClaim(claim)
	if typeof(claim) ~= "table" or typeof(claim.Summary) ~= "table" then
		return "AFK rewards saved."
	end

	local summary = claim.Summary
	local beli = math.max(0, math.floor(tonumber(summary.BeliEarnedThisSession or summary.Beli) or 0))
	local chests = math.max(0, math.floor(tonumber(summary.ChestsEarnedThisSession or summary.ClaimableChests) or 0))
	local parts = {}
	if chests > 0 then
		parts[#parts + 1] = tostring(chests) .. " " .. getChestTier(summary) .. " Chest" .. (if chests == 1 then "" else "s")
	end
	if beli > 0 then
		parts[#parts + 1] = formatCurrencyAmount(beli) .. " Beli"
	end
	if #parts == 0 then
		return "AFK session ended."
	end
	return "AFK rewards saved: " .. table.concat(parts, " and ")
end

if stateEvent then
	stateEvent.OnClientEvent:Connect(function(eventName, payload)
		if eventName == "State" then
			setCurrentState(payload)
		elseif eventName == "Claimed" and typeof(payload) == "table" then
			if typeof(payload.State) == "table" then
				setCurrentState(payload.State)
			else
				render()
			end
			showToast(describeClaim(payload.Claim), GREEN, 4)
		end
	end)
end

button.Activated:Connect(function()
	if returnRequest == nil or returnInFlight or button.Active ~= true then
		return
	end
	returnInFlight = true
	render()

	local ok, response = pcall(function()
		return returnRequest:InvokeServer()
	end)
	returnInFlight = false
	if ok and typeof(response) == "table" then
		if typeof(response.state) == "table" then
			setCurrentState(response.state)
		end
		if response.ok ~= true then
			local message = tostring(response.message or "Unable to leave AFK lobby.")
			if typeof(currentState) == "table" then
				currentState.Message = message
			end
			statusLabel.Text = message
			statusLabel.TextColor3 = RED
			showToast(message, RED, 3)
		else
			local message = tostring(response.message or "Leaving AFK lobby...")
			if typeof(currentState) == "table" then
				currentState.Message = message
			end
			statusLabel.Text = message
			statusLabel.TextColor3 = GOLD
		end
	else
		if typeof(currentState) == "table" then
			currentState.Message = "Unable to leave AFK lobby."
		end
		statusLabel.Text = "Unable to leave AFK lobby."
		statusLabel.TextColor3 = RED
		showToast("Unable to leave AFK lobby.", RED, 3)
	end
	render()
end)

local function sendActivityPing()
	if activityPingEvent == nil then
		return
	end
	local now = os.clock()
	if now - lastActivityPingAt < ACTIVITY_PING_COOLDOWN_SECONDS then
		return
	end
	lastActivityPingAt = now
	activityPingEvent:FireServer()
end

UserInputService.InputBegan:Connect(function(_input, _gameProcessed)
	sendActivityPing()
end)

UserInputService.WindowFocused:Connect(sendActivityPing)

task.spawn(function()
	requestState()
	while true do
		render()
		if backdrop.Visible and stateRequest ~= nil and os.clock() - stateReceivedAt > 15 then
			requestState()
		end
		task.wait(1)
	end
end)
