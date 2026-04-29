local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevilFruitClientController = {}
local started = false

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local SharedFolder = DevilFruits:WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFolder:WaitForChild("DevilFruitLogger"))
local DevilFruitRemotes = require(SharedFolder:WaitForChild("DevilFruitRemotes"))
local DevilFruitOptionalEffects = require(SharedFolder:WaitForChild("DevilFruitOptionalEffects"))
local ClientEffectVisuals = require(Modules:WaitForChild("DevilFruits"):WaitForChild("ClientEffectVisuals"))
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local ProtectionRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("ProtectionRuntime"))
local FruitModuleLoader = require(SharedFolder:WaitForChild("FruitModuleLoader"))
local DevilFruitInputController = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitInputController"))
local DevilFruitEffectRouter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitEffectRouter"))
local DevilFruitUiController = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitUiController"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local GAMEPLAY_MODAL_OPEN_ATTRIBUTE = "GameplayModalOpen"

local MOGU_FRUIT_NAME = "Mogu Mogu no Mi"
local MOGU_BURROW_ABILITY = "Burrow"
local PHOENIX_FRUIT_NAME = "Tori Tori no Mi"
local PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local PHOENIX_REBIRTH_ABILITY = "PhoenixRebirth"
local HAZARD_SUPPRESSION_INTERVAL = 0.05
local FIRE_BURST_HAZARD_SUPPRESSION_INTERVAL = 0.16
local LOCAL_HAZARD_OVERLAP_MAX_PARTS = 128
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_MOGU_HAZARD_PROTECTION_RADIUS = 12
local DEFAULT_MOGU_RESOLVE_HAZARD_PROBE_PADDING = 0.25
local DEFAULT_HAZARD_SUPPRESSION_SOURCE = "Default"
local FIRE_BURST_HAZARD_SUPPRESSION_SOURCE = "FireBurst"
local MOGU_HAZARD_SUPPRESSION_SOURCE = "MoguBurrow"

local RemoteBundle = DevilFruitRemotes.GetBundle()
local requestRemote = RemoteBundle.Request
local stateRemote = RemoteBundle.State
local effectRemote = RemoteBundle.Effect

local localCooldowns = {}
local suppressedParts = {}
local activeFireBursts = {}
local activeMoguBurrow = nil
local hazardSuppressionLoopRunning = false
local playOptionalEffect
local getFruitFolder
local getEquippedFruit
local fruitModuleLoader
local inputController
local effectRouter
local syncDevilFruitClientState
local lastSyncedFruitName = DevilFruitConfig.None
local cooldownHud = {
	CurrentFruit = nil,
	Gui = nil,
	Panel = nil,
	Backdrop = nil,
	Overlay = nil,
	TopBar = nil,
	FruitLabel = nil,
	List = nil,
	EmptyState = nil,
	Rows = {},
}
local clearCooldownRows
local refreshCooldownHudLayout
local DEVIL_FRUIT_UI = {
	FruitBackgroundImage = "rbxassetid://134053886107384",
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	HeaderBg = Color3.fromRGB(16, 35, 59),
	SectionBg = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	Ready = Color3.fromRGB(116, 255, 161),
	Cooldown = Color3.fromRGB(255, 190, 116),
	CooldownFill = Color3.fromRGB(255, 133, 44),
}

local HUD_REFRESH_INTERVAL = 0.05
local nextHudRefreshAt = 0
local COOLDOWN_PANEL_WIDTH = 318
local COOLDOWN_PANEL_INSET_X = 10
local COOLDOWN_ROW_HEIGHT = 58
local COOLDOWN_LIST_SPACING = 6
local COOLDOWN_LIST_VERTICAL_PADDING = 16
local COOLDOWN_PANEL_TOP_PADDING = 10
local COOLDOWN_PANEL_BOTTOM_PADDING = 10
local COOLDOWN_TOPBAR_HEIGHT = 58
local COOLDOWN_SECTION_GAP = 8

local function logDevilFruitClient(message, ...)
	print(string.format("[DEVILFRUIT CLIENT] " .. message, ...))
end

local function logDevilFruitRequest(message, ...)
	if not RunService:IsStudio() then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
end

local function countPayloadKeys(payload)
	if typeof(payload) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(payload) do
		count += 1
	end

	return count
end

local function describeRemote(instance)
	return DevilFruitRemotes.DescribeInstance(instance)
end

local function formatVector3ForLog(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function shouldTraceAbilityInput(keyCode)
	return keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.C
end

local function normalizeEquippedFruitName(fruitIdentifier)
	if typeof(fruitIdentifier) ~= "string" then
		return DevilFruitConfig.None
	end

	if fruitIdentifier == DevilFruitConfig.None or fruitIdentifier == "None" then
		return DevilFruitConfig.None
	end

	return Registry.ResolveFruitName(fruitIdentifier) or fruitIdentifier
end

local function formatAbilityName(abilityName)
	return DevilFruitUiController.FormatAbilityName(abilityName)
end

local function formatCooldownTime(seconds)
	return DevilFruitUiController.FormatCooldownTime(seconds)
end

local function isCooldownBypassEnabled()
	return player:GetAttribute("DevilFruitCooldownBypass") == true
end

local function getCooldownNow()
	return Workspace:GetServerTimeNow()
end

local function getLocalCooldownReadyAt(cooldownState)
	if typeof(cooldownState) == "table" then
		return tonumber(cooldownState.ReadyAt) or 0
	end

	return tonumber(cooldownState) or 0
end

local function getLocalCooldownStartsAt(cooldownState, fallbackDuration)
	local readyAt = getLocalCooldownReadyAt(cooldownState)
	if typeof(cooldownState) == "table" then
		local startsAt = tonumber(cooldownState.StartsAt)
		if startsAt and startsAt > 0 then
			return startsAt
		end
	end

	return math.max(0, readyAt - math.max(0, tonumber(fallbackDuration) or 0))
end

local function getLocalCooldownDuration(cooldownState, fallbackDuration)
	if typeof(cooldownState) == "table" then
		local duration = tonumber(cooldownState.Duration)
		if duration and duration > 0 then
			return duration
		end
	end

	return math.max(0, tonumber(fallbackDuration) or 0)
end

local function setLocalCooldown(abilityName, readyAt, payload)
	local resolvedReadyAt = tonumber(readyAt) or 0
	if resolvedReadyAt <= 0 then
		localCooldowns[abilityName] = nil
		return
	end

	local cooldownState = {
		ReadyAt = resolvedReadyAt,
	}

	if typeof(payload) == "table" then
		local startsAt = tonumber(payload.CooldownStartsAt)
		local duration = tonumber(payload.CooldownDuration)
		if startsAt and startsAt > 0 and startsAt < resolvedReadyAt then
			cooldownState.StartsAt = startsAt
		end
		if duration and duration > 0 then
			cooldownState.Duration = duration
		end
	end

	localCooldowns[abilityName] = cooldownState
end

local function getPlayerGui()
	return playerGui
end

local function isGameplayModalOpen()
	return playerGui:GetAttribute(GAMEPLAY_MODAL_OPEN_ATTRIBUTE) == true
end

local function ensureStroke(instance, color, transparency, thickness)
	local stroke = instance:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = instance
	end

	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	return stroke
end

local function ensureCorner(instance, radius)
	local corner = instance:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = instance
	end

	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function ensureGradient(instance, topColor, bottomColor)
	local gradient = instance:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = instance
	end

	gradient.Rotation = 90
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, topColor),
		ColorSequenceKeypoint.new(1, bottomColor),
	})
	return gradient
end

local function getOrderedAbilities(fruitName)
	return DevilFruitUiController.GetOrderedAbilities(fruitName)
end

local function shouldShowCooldownHud(fruitName)
	return DevilFruitUiController.ShouldShowCooldownHud(fruitName)
end

local function isCooldownPanelValid(panel)
	if not (panel and panel:IsA("Frame")) then
		return false
	end

	local backdrop = panel:FindFirstChild("Backdrop")
	local overlay = panel:FindFirstChild("BackdropOverlay")
	local topBar = panel:FindFirstChild("TopBar")
	local list = panel:FindFirstChild("AbilityList")
	local title = topBar and topBar:FindFirstChild("Title")
	local fruitName = topBar and topBar:FindFirstChild("FruitName")

	return backdrop ~= nil
		and overlay ~= nil
		and topBar ~= nil
		and list ~= nil
		and title ~= nil
		and fruitName ~= nil
end

local function ensureCooldownHud()
	local playerGui = getPlayerGui()
	local screenGui = playerGui:FindFirstChild("DevilFruitHUD")
	local panelRebuilt = false
	if screenGui and not screenGui:IsA("ScreenGui") then
		screenGui:Destroy()
		screenGui = nil
		panelRebuilt = true
	end

	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "DevilFruitHUD"
		screenGui.Parent = playerGui
		panelRebuilt = true
	end

	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 25
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local panel = screenGui:FindFirstChild("CooldownPanel")
	if panel and not panel:IsA("Frame") then
		panel:Destroy()
		panel = nil
		panelRebuilt = true
	end
	if panel and not isCooldownPanelValid(panel) then
		panel:Destroy()
		panel = nil
		panelRebuilt = true
	end

	if not panel then
		panel = Instance.new("Frame")
		panel.Name = "CooldownPanel"
		panel.AnchorPoint = Vector2.new(1, 1)
		panel.Position = UDim2.new(1, -24, 1, -24)
		panel.Size = UDim2.fromOffset(COOLDOWN_PANEL_WIDTH, 140)
		panel.AutomaticSize = Enum.AutomaticSize.None
		panel.BackgroundColor3 = DEVIL_FRUIT_UI.PrimaryBg
		panel.BackgroundTransparency = 1
		panel.BorderSizePixel = 0
		panel.ClipsDescendants = true
		panel.Visible = false
		panel.Parent = screenGui
		panelRebuilt = true
	end

	panel.BackgroundColor3 = DEVIL_FRUIT_UI.PrimaryBg
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -24, 1, -24)
	panel.Size = UDim2.fromOffset(COOLDOWN_PANEL_WIDTH, 140)
	panel.AutomaticSize = Enum.AutomaticSize.None
	panel.ClipsDescendants = true
	ensureCorner(panel, 14)
	local panelStroke = ensureStroke(panel, DEVIL_FRUIT_UI.GoldHighlight, 0, 1.6)
	panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local backdrop = panel:FindFirstChild("Backdrop")
	if backdrop and not backdrop:IsA("ImageLabel") then
		backdrop:Destroy()
		backdrop = nil
	end
	if not backdrop then
		backdrop = Instance.new("ImageLabel")
		backdrop.Name = "Backdrop"
		backdrop.BackgroundTransparency = 1
		backdrop.BorderSizePixel = 0
		backdrop.Image = DEVIL_FRUIT_UI.FruitBackgroundImage
		backdrop.ScaleType = Enum.ScaleType.Stretch
		backdrop.Size = UDim2.fromScale(1, 1)
		backdrop.ZIndex = 0
		backdrop.Parent = panel
		ensureCorner(backdrop, 14)
	end
	backdrop.Image = DEVIL_FRUIT_UI.FruitBackgroundImage
	backdrop.ScaleType = Enum.ScaleType.Stretch
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 0

	local overlay = panel:FindFirstChild("BackdropOverlay")
	if overlay and not overlay:IsA("Frame") then
		overlay:Destroy()
		overlay = nil
	end
	if not overlay then
		overlay = Instance.new("Frame")
		overlay.Name = "BackdropOverlay"
		overlay.BackgroundColor3 = DEVIL_FRUIT_UI.MenuOverlay
		overlay.BackgroundTransparency = 0.42
		overlay.BorderSizePixel = 0
		overlay.Size = UDim2.fromScale(1, 1)
		overlay.ZIndex = 1
		overlay.Parent = panel
		ensureCorner(overlay, 14)
	end
	overlay.BackgroundColor3 = DEVIL_FRUIT_UI.MenuOverlay
	overlay.BackgroundTransparency = 0.42
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = 1
	ensureCorner(overlay, 14)

	for _, child in ipairs(panel:GetChildren()) do
		if child:IsA("UIPadding") or child:IsA("UIListLayout") then
			child:Destroy()
		end
	end

	local topBar = panel:FindFirstChild("TopBar")
	if topBar and not topBar:IsA("Frame") then
		topBar:Destroy()
		topBar = nil
	end
	if not topBar then
		topBar = Instance.new("Frame")
		topBar.Name = "TopBar"
		topBar.BackgroundColor3 = DEVIL_FRUIT_UI.HeaderBg
		topBar.BackgroundTransparency = 0.24
		topBar.BorderSizePixel = 0
		topBar.Position = UDim2.fromOffset(COOLDOWN_PANEL_INSET_X, COOLDOWN_PANEL_TOP_PADDING)
		topBar.Size = UDim2.new(1, -(COOLDOWN_PANEL_INSET_X * 2), 0, COOLDOWN_TOPBAR_HEIGHT)
		topBar.ZIndex = 2
		topBar.Parent = panel
		ensureCorner(topBar, 10)
		local topBarStroke = ensureStroke(topBar, DEVIL_FRUIT_UI.GoldHighlight, 0, 1.2)
		topBarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ensureGradient(topBar, DEVIL_FRUIT_UI.SecondaryBg, DEVIL_FRUIT_UI.PrimaryBg)
	end
	topBar.BackgroundColor3 = DEVIL_FRUIT_UI.HeaderBg
	topBar.BackgroundTransparency = 0.24
	topBar.BorderSizePixel = 0
	topBar.Position = UDim2.fromOffset(COOLDOWN_PANEL_INSET_X, COOLDOWN_PANEL_TOP_PADDING)
	topBar.Size = UDim2.new(1, -(COOLDOWN_PANEL_INSET_X * 2), 0, COOLDOWN_TOPBAR_HEIGHT)
	topBar.ZIndex = 2
	ensureCorner(topBar, 10)
	local topBarStroke = ensureStroke(topBar, DEVIL_FRUIT_UI.GoldHighlight, 0, 1.2)
	topBarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ensureGradient(topBar, DEVIL_FRUIT_UI.SecondaryBg, DEVIL_FRUIT_UI.PrimaryBg)

	local title = topBar:FindFirstChild("Title")
	if title and not title:IsA("TextLabel") then
		title:Destroy()
		title = nil
	end
	if not title then
		title = Instance.new("TextLabel")
		title.Name = "Title"
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(10, 4)
		title.Size = UDim2.new(1, -20, 0, 16)
		title.Font = Enum.Font.GothamBold
		title.Text = "DEVIL FRUIT"
		title.TextSize = 12
		title.TextColor3 = DEVIL_FRUIT_UI.GoldHighlight
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.ZIndex = 3
		title.Parent = topBar
	end
	title.Text = "DEVIL FRUIT"
	title.TextTransparency = 0
	title.TextColor3 = DEVIL_FRUIT_UI.GoldHighlight
	title.ZIndex = 3

	local fruitLabel = topBar:FindFirstChild("FruitName")
	if fruitLabel and not fruitLabel:IsA("TextLabel") then
		fruitLabel:Destroy()
		fruitLabel = nil
	end
	if not fruitLabel then
		fruitLabel = Instance.new("TextLabel")
		fruitLabel.Name = "FruitName"
		fruitLabel.BackgroundTransparency = 1
		fruitLabel.Position = UDim2.fromOffset(10, 20)
		fruitLabel.Size = UDim2.new(1, -20, 0, 30)
		fruitLabel.Font = Enum.Font.GothamBold
		fruitLabel.Text = ""
		fruitLabel.TextColor3 = DEVIL_FRUIT_UI.TextMain
		fruitLabel.TextSize = 28
		fruitLabel.TextScaled = true
		fruitLabel.TextWrapped = false
		fruitLabel.TextTruncate = Enum.TextTruncate.AtEnd
		fruitLabel.TextXAlignment = Enum.TextXAlignment.Left
		fruitLabel.ZIndex = 3
		fruitLabel.Parent = topBar
	end
	fruitLabel.TextTransparency = 0
	fruitLabel.TextColor3 = DEVIL_FRUIT_UI.TextMain
	fruitLabel.ZIndex = 3

	local list = panel:FindFirstChild("AbilityList")
	if list and not list:IsA("Frame") then
		list:Destroy()
		list = nil
	end
	if not list then
		list = Instance.new("Frame")
		list.Name = "AbilityList"
		list.BackgroundColor3 = DEVIL_FRUIT_UI.SectionBg
		list.BackgroundTransparency = 0.2
		list.BorderSizePixel = 0
		list.Position = UDim2.fromOffset(
			COOLDOWN_PANEL_INSET_X,
			COOLDOWN_PANEL_TOP_PADDING + COOLDOWN_TOPBAR_HEIGHT + COOLDOWN_SECTION_GAP
		)
		list.Size = UDim2.new(1, -(COOLDOWN_PANEL_INSET_X * 2), 0, 0)
		list.AutomaticSize = Enum.AutomaticSize.None
		list.ZIndex = 2
		list.ClipsDescendants = true
		list.Parent = panel
		ensureCorner(list, 10)
		local listStroke = ensureStroke(list, DEVIL_FRUIT_UI.GoldHighlight, 0.14, 1)
		listStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	list.BackgroundColor3 = DEVIL_FRUIT_UI.SectionBg
	list.BackgroundTransparency = 0.2
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(
		COOLDOWN_PANEL_INSET_X,
		COOLDOWN_PANEL_TOP_PADDING + COOLDOWN_TOPBAR_HEIGHT + COOLDOWN_SECTION_GAP
	)
	list.Size = UDim2.new(1, -(COOLDOWN_PANEL_INSET_X * 2), 0, 0)
	list.AutomaticSize = Enum.AutomaticSize.None
	list.ZIndex = 2
	list.ClipsDescendants = true
	ensureCorner(list, 10)
	local listStroke = ensureStroke(list, DEVIL_FRUIT_UI.GoldHighlight, 0.14, 1)
	listStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local listLayout = list:FindFirstChildOfClass("UIListLayout")
	if not listLayout then
		listLayout = Instance.new("UIListLayout")
		listLayout.Parent = list
	end
	listLayout.Padding = UDim.new(0, 6)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local listPadding = list:FindFirstChildOfClass("UIPadding")
	if not listPadding then
		listPadding = Instance.new("UIPadding")
		listPadding.Parent = list
	end
	listPadding.PaddingTop = UDim.new(0, 8)
	listPadding.PaddingBottom = UDim.new(0, 8)
	listPadding.PaddingLeft = UDim.new(0, 8)
	listPadding.PaddingRight = UDim.new(0, 8)

	if panelRebuilt then
		cooldownHud.CurrentFruit = nil
		cooldownHud.Rows = {}
		cooldownHud.EmptyState = nil
	end

	cooldownHud.Gui = screenGui
	cooldownHud.Panel = panel
	cooldownHud.Backdrop = backdrop
	cooldownHud.Overlay = overlay
	cooldownHud.TopBar = topBar
	cooldownHud.FruitLabel = fruitLabel
	cooldownHud.List = list
	cooldownHud.EmptyState = cooldownHud.EmptyState and cooldownHud.EmptyState.Parent and cooldownHud.EmptyState or nil
	cooldownHud.Rows = cooldownHud.Rows or {}

	return cooldownHud
end

local function setCooldownHudVisible(isVisible)
	ensureCooldownHud()
	local shouldShow = isVisible and not isGameplayModalOpen()
	cooldownHud.Gui.Enabled = shouldShow
	cooldownHud.Panel.Visible = shouldShow
end

local function hideCooldownHud()
	setCooldownHudVisible(false)
	cooldownHud.CurrentFruit = nil
	clearCooldownRows()

	if cooldownHud.FruitLabel then
		cooldownHud.FruitLabel.Text = ""
	end
end

clearCooldownRows = function()
	for _, row in pairs(cooldownHud.Rows) do
		if row.Container and row.Container.Parent then
			row.Container:Destroy()
		end
	end

	if cooldownHud.EmptyState and cooldownHud.EmptyState.Parent then
		cooldownHud.EmptyState:Destroy()
	end

	cooldownHud.Rows = {}
	cooldownHud.EmptyState = nil
	refreshCooldownHudLayout()
end

refreshCooldownHudLayout = function()
	ensureCooldownHud()

	local rowCount = 0
	for _ in pairs(cooldownHud.Rows) do
		rowCount += 1
	end

	local listHeight = COOLDOWN_LIST_VERTICAL_PADDING
	if rowCount > 0 then
		listHeight += (rowCount * COOLDOWN_ROW_HEIGHT) + ((rowCount - 1) * COOLDOWN_LIST_SPACING)
	else
		listHeight = math.max(COOLDOWN_LIST_VERTICAL_PADDING + 28, 44)
	end

	local listWidthOffset = -(COOLDOWN_PANEL_INSET_X * 2)
	if cooldownHud.List then
		cooldownHud.List.Position = UDim2.fromOffset(
			COOLDOWN_PANEL_INSET_X,
			COOLDOWN_PANEL_TOP_PADDING + COOLDOWN_TOPBAR_HEIGHT + COOLDOWN_SECTION_GAP
		)
		cooldownHud.List.Size = UDim2.new(1, listWidthOffset, 0, listHeight)
		cooldownHud.List.Visible = true
	end

	if cooldownHud.TopBar then
		cooldownHud.TopBar.Position = UDim2.fromOffset(COOLDOWN_PANEL_INSET_X, COOLDOWN_PANEL_TOP_PADDING)
		cooldownHud.TopBar.Size = UDim2.new(1, listWidthOffset, 0, COOLDOWN_TOPBAR_HEIGHT)
		cooldownHud.TopBar.Visible = true
	end

	local totalHeight = COOLDOWN_PANEL_TOP_PADDING
		+ COOLDOWN_TOPBAR_HEIGHT
		+ COOLDOWN_SECTION_GAP
		+ listHeight
		+ COOLDOWN_PANEL_BOTTOM_PADDING

	if cooldownHud.Panel then
		cooldownHud.Panel.Size = UDim2.fromOffset(COOLDOWN_PANEL_WIDTH, totalHeight)
	end
end

local function createCooldownRow(layoutOrder, abilityName, abilityConfig)
	local cooldownValue = tonumber(abilityConfig and abilityConfig.Cooldown) or 0
	local keyCode = abilityConfig and abilityConfig.KeyCode
	local keyCodeName = keyCode and keyCode.Name or "?"

	local row = Instance.new("Frame")
	row.Name = abilityName
	row.Size = UDim2.new(1, 0, 0, 58)
	row.BackgroundColor3 = DEVIL_FRUIT_UI.SectionBg
	row.BackgroundTransparency = 0.18
	row.BorderSizePixel = 0
	row.LayoutOrder = layoutOrder
	row.ZIndex = 3
	row.Parent = cooldownHud.List

	ensureCorner(row, 10)
	local rowStroke = ensureStroke(row, DEVIL_FRUIT_UI.GoldHighlight, 0.1, 1)
	rowStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ensureGradient(row, DEVIL_FRUIT_UI.SecondaryBg, DEVIL_FRUIT_UI.PrimaryBg)

	local keyBadge = Instance.new("TextLabel")
	keyBadge.Name = "Key"
	keyBadge.AnchorPoint = Vector2.new(0, 0.5)
	keyBadge.Position = UDim2.new(0, 8, 0.5, -6)
	keyBadge.Size = UDim2.fromOffset(34, 24)
	keyBadge.BackgroundColor3 = DEVIL_FRUIT_UI.GoldBase
	keyBadge.BorderSizePixel = 0
	keyBadge.Font = Enum.Font.GothamBold
	keyBadge.Text = keyCodeName
	keyBadge.TextColor3 = DEVIL_FRUIT_UI.PrimaryBg
	keyBadge.TextSize = 14
	keyBadge.ZIndex = 4
	keyBadge.Parent = row

	ensureCorner(keyBadge, 8)
	ensureStroke(keyBadge, DEVIL_FRUIT_UI.GoldHighlight, 0, 1)
	ensureGradient(keyBadge, DEVIL_FRUIT_UI.GoldHighlight, DEVIL_FRUIT_UI.GoldBase)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 52, 0, 8)
	nameLabel.Size = UDim2.new(1, -136, 0, 18)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = formatAbilityName(abilityName)
	nameLabel.TextColor3 = DEVIL_FRUIT_UI.TextMain
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 4
	nameLabel.Parent = row

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.AnchorPoint = Vector2.new(1, 0)
	statusLabel.Position = UDim2.new(1, -10, 0, 8)
	statusLabel.Size = UDim2.new(0, 72, 0, 18)
	statusLabel.Font = Enum.Font.GothamBold
	statusLabel.Text = "READY"
	statusLabel.TextColor3 = DEVIL_FRUIT_UI.Ready
	statusLabel.TextSize = 13
	statusLabel.TextXAlignment = Enum.TextXAlignment.Right
	statusLabel.ZIndex = 4
	statusLabel.Parent = row

	local detailLabel = Instance.new("TextLabel")
	detailLabel.Name = "Detail"
	detailLabel.BackgroundTransparency = 1
	detailLabel.Position = UDim2.new(0, 52, 0, 29)
	detailLabel.Size = UDim2.new(1, -68, 0, 12)
	detailLabel.Font = Enum.Font.Gotham
	detailLabel.Text = string.format("Cooldown %.1fs", cooldownValue)
	detailLabel.TextColor3 = DEVIL_FRUIT_UI.TextSecondary
	detailLabel.TextSize = 11
	detailLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailLabel.ZIndex = 4
	detailLabel.Parent = row

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0, 1)
	bar.Position = UDim2.new(0, 10, 1, -8)
	bar.Size = UDim2.new(1, -20, 0, 6)
	bar.BackgroundColor3 = DEVIL_FRUIT_UI.PrimaryBg
	bar.BorderSizePixel = 0
	bar.ZIndex = 4
	bar.Parent = row

	ensureCorner(bar, 999)
	ensureStroke(bar, DEVIL_FRUIT_UI.GoldShadow, 0.26, 0.8)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = DEVIL_FRUIT_UI.Ready
	fill.BorderSizePixel = 0
	fill.ZIndex = 5
	fill.Parent = bar

	ensureCorner(fill, 999)

	return {
		Container = row,
		Status = statusLabel,
		Fill = fill,
		Detail = detailLabel,
		Cooldown = cooldownValue,
	}
end

local function rebuildCooldownHud(fruitName)
	ensureCooldownHud()
	clearCooldownRows()

	cooldownHud.CurrentFruit = fruitName
	local fruit = DevilFruitConfig.GetFruit(fruitName)
	if not fruit then
		hideCooldownHud()
		return
	end

	setCooldownHudVisible(true)
	cooldownHud.FruitLabel.Text = fruit.DisplayName or fruitName

	local orderedAbilities = getOrderedAbilities(fruitName)
	if #orderedAbilities == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Name = "NoAbilities"
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Size = UDim2.new(1, -16, 0, 24)
		emptyLabel.Position = UDim2.fromOffset(8, 10)
		emptyLabel.Font = Enum.Font.GothamSemibold
		emptyLabel.Text = "No active fruit skills."
		emptyLabel.TextColor3 = DEVIL_FRUIT_UI.TextSecondary
		emptyLabel.TextSize = 14
		emptyLabel.TextXAlignment = Enum.TextXAlignment.Left
		emptyLabel.ZIndex = 4
		emptyLabel.Parent = cooldownHud.List
		cooldownHud.EmptyState = emptyLabel
	else
		for index, entry in ipairs(orderedAbilities) do
			cooldownHud.Rows[entry.Name] = createCooldownRow(index, entry.Name, entry.Config)
		end
	end
	refreshCooldownHudLayout()
end

local function updateCooldownHud(forceRebuild)
	ensureCooldownHud()

	local fruitName = getEquippedFruit()
	local needsRebuild = forceRebuild or fruitName ~= cooldownHud.CurrentFruit
	if not needsRebuild then
		for _, row in pairs(cooldownHud.Rows) do
			if not (row and row.Container and row.Container.Parent == cooldownHud.List and row.Status and row.Detail and row.Fill) then
				needsRebuild = true
				break
			end
		end
	end

	if not needsRebuild and cooldownHud.List and next(cooldownHud.Rows) ~= nil then
		local rowFrames = 0
		for _, child in ipairs(cooldownHud.List:GetChildren()) do
			if child:IsA("Frame") then
				rowFrames += 1
			end
		end
		if rowFrames == 0 then
			needsRebuild = true
		end
	end

	if needsRebuild then
		rebuildCooldownHud(fruitName)
	end

	if not shouldShowCooldownHud(fruitName) then
		hideCooldownHud()
		return
	end

	setCooldownHudVisible(true)

	for abilityName, row in pairs(cooldownHud.Rows) do
		local cooldownState = if isCooldownBypassEnabled() then nil else localCooldowns[abilityName]
		local readyAt = getLocalCooldownReadyAt(cooldownState)
		local now = getCooldownNow()
		local remaining = math.max(0, readyAt - now)
		local startsAt = getLocalCooldownStartsAt(cooldownState, row.Cooldown)
		local startsIn = math.max(0, startsAt - now)
		local isWaitingForCooldownStart = remaining > 0 and startsIn > 0
		local total = math.max(getLocalCooldownDuration(cooldownState, row.Cooldown), 0.001)
		local progress = if isWaitingForCooldownStart then 1 else math.clamp(1 - (remaining / total), 0, 1)
		local isReady = remaining <= 0
		if isReady then
			localCooldowns[abilityName] = nil
		end

		if isReady then
			row.Status.Text = "READY"
			row.Status.TextColor3 = DEVIL_FRUIT_UI.Ready
			row.Detail.Text = "Move ready"
		elseif isWaitingForCooldownStart then
			row.Status.Text = "ACTIVE"
			row.Status.TextColor3 = DEVIL_FRUIT_UI.Ready
			row.Detail.Text = "Cooldown starts in " .. formatCooldownTime(startsIn)
		else
			row.Status.Text = "CD " .. formatCooldownTime(remaining)
			row.Status.TextColor3 = DEVIL_FRUIT_UI.Cooldown
			row.Detail.Text = "On cooldown for " .. formatCooldownTime(remaining)
		end
		row.Fill.Size = UDim2.new(progress, 0, 1, 0)
		row.Fill.BackgroundColor3 = (isReady or isWaitingForCooldownStart) and DEVIL_FRUIT_UI.Ready
			or DEVIL_FRUIT_UI.CooldownFill
	end
	refreshCooldownHudLayout()
end

getFruitFolder = function()
	return player:FindFirstChild("DevilFruit")
end

getEquippedFruit = function()
	local fruitFolder = getFruitFolder()
	if fruitFolder then
		local equipped = fruitFolder:FindFirstChild("Equipped")
		if equipped and equipped:IsA("StringValue") then
			return normalizeEquippedFruitName(equipped.Value)
		end
	end

	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		return normalizeEquippedFruitName(fruitAttribute)
	end

	return DevilFruitConfig.None
end

local function hookEquippedFruitValue(equippedValue)
	if not equippedValue or not equippedValue:IsA("StringValue") then
		return
	end

	if equippedValue:GetAttribute("__DevilFruitHudHooked") == true then
		return
	end

	equippedValue:SetAttribute("__DevilFruitHudHooked", true)
	equippedValue:GetPropertyChangedSignal("Value"):Connect(function()
		if typeof(syncDevilFruitClientState) == "function" then
			task.defer(syncDevilFruitClientState)
			return
		end

		updateCooldownHud(true)
	end)
end

local function hookFruitFolderSignals()
	local fruitFolder = getFruitFolder()
	if not fruitFolder then
		return
	end

	local equippedValue = fruitFolder:FindFirstChild("Equipped")
	if equippedValue then
		hookEquippedFruitValue(equippedValue)
	end

	if fruitFolder:GetAttribute("__DevilFruitHudFolderHooked") == true then
		return
	end

	fruitFolder:SetAttribute("__DevilFruitHudFolderHooked", true)
	fruitFolder.ChildAdded:Connect(function(child)
		if child.Name == "Equipped" then
			hookEquippedFruitValue(child)
			updateCooldownHud(true)
		end
	end)
end

local function getAbilityForKeyCode(keyCode)
	local fruitName = getEquippedFruit()
	if inputController then
		local resolvedFruitName, abilityName, abilityEntry = inputController:GetAbilityForKeyCode(fruitName, keyCode)
		if resolvedFruitName and abilityName then
			return resolvedFruitName, abilityName, abilityEntry
		end
	end

	local fruit = DevilFruitConfig.GetFruit(fruitName)
	if not fruit or not fruit.Abilities then
		return nil, nil, nil
	end

	for abilityName, abilityConfig in pairs(fruit.Abilities) do
		if abilityConfig.KeyCode == keyCode then
			return fruitName, abilityName, Registry.GetAbility(fruitName, abilityName)
		end
	end

	return nil, nil, nil
end

local function isLocallyReady(abilityName)
	if isCooldownBypassEnabled() then
		return true
	end

	local cooldownState = localCooldowns[abilityName]
	if not cooldownState then
		return true
	end

	local readyAt = getLocalCooldownReadyAt(cooldownState)
	if getCooldownNow() >= readyAt then
		localCooldowns[abilityName] = nil
		return true
	end

	return false
end

local function getCharacter()
	return player.Character
end

local function getRootPart()
	local character = getCharacter()
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local clientEffectVisuals = ClientEffectVisuals.new({
	GetLocalRootPart = getRootPart,
	GetPlayerRootPart = getPlayerRootPart,
	MinDirectionMagnitude = MIN_DIRECTION_MAGNITUDE,
	PhoenixFruitName = PHOENIX_FRUIT_NAME,
	PhoenixFlightAbility = PHOENIX_FLIGHT_ABILITY,
	PhoenixShieldAbility = PHOENIX_SHIELD_ABILITY,
	PhoenixRebirthAbility = PHOENIX_REBIRTH_ABILITY,
})

local function buildDefaultAbilityRequestPayload(fruitName, abilityName)
	return nil
end

local function buildAbilityRequestPayload(fruitName, abilityName)
	local abilityEntry = Registry.GetAbility(fruitName, abilityName)
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") or nil
	local moveDirection = humanoid and humanoid.MoveDirection or nil
	logDevilFruitRequest(
		"client build begin fruit=%s ability=%s abilityEntry=%s character=%s humanoid=%s root=%s moveDir=%s lookDir=%s",
		tostring(fruitName),
		tostring(abilityName),
		tostring(abilityEntry ~= nil),
		tostring(character ~= nil),
		tostring(humanoid ~= nil),
		tostring(rootPart ~= nil),
		formatVector3ForLog(moveDirection),
		formatVector3ForLog(rootPart and rootPart.CFrame.LookVector or nil)
	)
	if inputController then
		local payload = inputController:BuildRequestPayload(fruitName, abilityName, abilityEntry, function()
			return buildDefaultAbilityRequestPayload(fruitName, abilityName)
		end)
		logDevilFruitRequest(
			"client build end fruit=%s ability=%s payloadKeys=%d",
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(payload)
		)
		return payload
	end

	local fallbackPayload = buildDefaultAbilityRequestPayload(fruitName, abilityName)
	logDevilFruitRequest(
		"client build end fruit=%s ability=%s payloadKeys=%d source=default_builder_only",
		tostring(fruitName),
		tostring(abilityName),
		countPayloadKeys(fallbackPayload)
	)
	return fallbackPayload
end

local function isDescendantOfClientWave(instance, clientWavesFolder)
	clientWavesFolder = clientWavesFolder or MapResolver.GetRefs().ClientWaves
	if not clientWavesFolder then
		return false
	end

	return instance:IsDescendantOf(clientWavesFolder)
end

local function getWaveTemplate(instance)
	local current = instance
	while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
		current = current.Parent
	end

	if not current then
		return nil
	end

	local wavesFolder = ReplicatedStorage:FindFirstChild("Waves")
	if not wavesFolder then
		return nil
	end

	return wavesFolder:FindFirstChild(current.Name)
end

local function getHazardContainer(instance, clientWavesFolder)
	local root, hazardClass, hazardType, canFreeze, freezeBehavior = HazardUtils.GetHazardInfo(instance)
	if root then
		return root, hazardClass, hazardType, canFreeze, freezeBehavior
	end

	if isDescendantOfClientWave(instance, clientWavesFolder) then
		local template = getWaveTemplate(instance)
		if template then
			local _, templateClass, templateType, templateCanFreeze, templateFreezeBehavior = HazardUtils.GetHazardInfo(template)
			if templateClass or templateType or templateCanFreeze or templateFreezeBehavior then
				local current = instance
				while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
					current = current.Parent
				end

				return current or instance, templateClass, templateType, templateCanFreeze, templateFreezeBehavior
			end
		end
	end

	return nil, nil, nil, false, nil
end

local function getLatestSuppressionUntilTime(sources)
	local latestUntilTime = nil
	for _, sourceUntilTime in pairs(sources) do
		if typeof(sourceUntilTime) == "number" and (latestUntilTime == nil or sourceUntilTime > latestUntilTime) then
			latestUntilTime = sourceUntilTime
		end
	end

	return latestUntilTime
end

local function getSuppressionSources(state)
	if type(state.Sources) ~= "table" then
		state.Sources = {
			[DEFAULT_HAZARD_SUPPRESSION_SOURCE] = tonumber(state.UntilTime) or 0,
		}
	end

	return state.Sources
end

local function pruneExpiredSuppressionSources(sources, now)
	for source, sourceUntilTime in pairs(sources) do
		if typeof(sourceUntilTime) ~= "number" or now >= sourceUntilTime then
			sources[source] = nil
		end
	end
end

local function suppressPart(part, untilTime, source)
	if not part or not part:IsA("BasePart") then
		return
	end

	local sourceKey = source or DEFAULT_HAZARD_SUPPRESSION_SOURCE
	local state = suppressedParts[part]
	if state then
		local sources = getSuppressionSources(state)
		sources[sourceKey] = math.max(tonumber(sources[sourceKey]) or 0, untilTime)
		if untilTime > state.UntilTime then
			state.UntilTime = untilTime
		end
		return
	end

	suppressedParts[part] = {
		OriginalCanTouch = part.CanTouch,
		OriginalCanCollide = part.CanCollide,
		UntilTime = untilTime,
		Sources = {
			[sourceKey] = untilTime,
		},
	}

	part.CanTouch = false
	part.CanCollide = false
end

local function suppressHazard(container, untilTime, source)
	if not container then
		return
	end

	if container:IsA("BasePart") then
		suppressPart(container, untilTime, source)
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			suppressPart(descendant, untilTime, source)
		end
	end
end

local function restoreSuppressedParts(now, source)
	for part, state in pairs(suppressedParts) do
		if not part or not part.Parent then
			suppressedParts[part] = nil
		else
			local sources = getSuppressionSources(state)
			if source then
				sources[source] = nil
			end

			pruneExpiredSuppressionSources(sources, now)
			local latestUntilTime = getLatestSuppressionUntilTime(sources)
			if latestUntilTime then
				state.UntilTime = latestUntilTime
			else
				part.CanTouch = state.OriginalCanTouch
				part.CanCollide = state.OriginalCanCollide
				suppressedParts[part] = nil
			end
		end
	end
end

local function getMoguHazardProtectionRadius()
	local abilityConfig = DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}
	return math.max(0, tonumber(abilityConfig.HazardProtectionRadius) or DEFAULT_MOGU_HAZARD_PROTECTION_RADIUS)
end

local function getMoguResolveHazardProbePadding()
	local abilityConfig = DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}
	return math.max(
		0,
		tonumber(abilityConfig.ResolveHazardProbePadding)
			or tonumber(abilityConfig.SurfaceHazardProbePadding)
			or DEFAULT_MOGU_RESOLVE_HAZARD_PROBE_PADDING
	)
end

local function isLocalPlayerBurrowProtected(now)
	if type(activeMoguBurrow) ~= "table" then
		return false
	end

	if now >= (activeMoguBurrow.EndTime or 0) then
		activeMoguBurrow = nil
		return false
	end

	return true
end

ProtectionRuntime.Register("MoguBurrowProtection", function(targetPlayer, position)
	if targetPlayer ~= player then
		return false
	end

	return isLocalPlayerBurrowProtected(os.clock())
end)

local function buildLocalHazardOverlapParams(refs, restrictToHazardRoots)
	local overlapParams = OverlapParams.new()
	refs = refs or MapResolver.GetRefs()

	if restrictToHazardRoots == true then
		local queryRoots = {}
		local waveFolder = refs and refs.WaveFolder
		local sharedHazardsFolder = waveFolder and waveFolder:FindFirstChild("Hazards")
		if sharedHazardsFolder then
			queryRoots[#queryRoots + 1] = sharedHazardsFolder
		end
		if refs and refs.ClientWaves then
			queryRoots[#queryRoots + 1] = refs.ClientWaves
		end

		if #queryRoots > 0 then
			overlapParams.FilterType = Enum.RaycastFilterType.Include
			overlapParams.FilterDescendantsInstances = queryRoots
			overlapParams.MaxParts = LOCAL_HAZARD_OVERLAP_MAX_PARTS
			return overlapParams
		end
	end

	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = player.Character and { player.Character } or {}
	return overlapParams
end

local function suppressHazardsNearPosition(centerPosition, radius, untilTime, shouldSuppress, restrictToHazardRoots, source)
	if typeof(centerPosition) ~= "Vector3" or radius <= 0 then
		return
	end

	local refs = MapResolver.GetRefs()
	local clientWavesFolder = refs and refs.ClientWaves
	local nearbyParts = Workspace:GetPartBoundsInRadius(
		centerPosition,
		radius,
		buildLocalHazardOverlapParams(refs, restrictToHazardRoots)
	)
	for _, part in ipairs(nearbyParts) do
		local container, hazardClass, hazardType = getHazardContainer(part, clientWavesFolder)
		if container and (shouldSuppress == nil or shouldSuppress(container, hazardClass, hazardType)) then
			suppressHazard(container, untilTime, source)
		end
	end
end

local function fireWaveKillFromMoguSurface(rootPosition)
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if ProtectionRuntime.IsProtected(player, rootPosition, "WaveKill") then
		return
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local killMeEvent = remotesFolder and remotesFolder:FindFirstChild("KillMe")
	if killMeEvent and killMeEvent:IsA("RemoteEvent") then
		killMeEvent:FireServer()
	else
		humanoid.Health = 0
	end
end

local function applyMoguSurfaceHazardOverlap()
	local rootPart = getRootPart()
	if not rootPart then
		return false
	end

	local refs = MapResolver.GetRefs()
	local clientWavesFolder = refs and refs.ClientWaves
	local padding = getMoguResolveHazardProbePadding()
	local probeSize = rootPart.Size + Vector3.new(padding * 2, padding * 2, padding * 2)
	local nearbyParts = Workspace:GetPartBoundsInBox(
		rootPart.CFrame,
		probeSize,
		buildLocalHazardOverlapParams(refs, true)
	)

	for _, part in ipairs(nearbyParts) do
		local container, hazardClass, hazardType = getHazardContainer(part, clientWavesFolder)
		if container and hazardClass ~= "minor" and hazardType == "wave" and container:GetAttribute("Frozen") ~= true then
			fireWaveKillFromMoguSurface(rootPart.Position)
			return true
		end
	end

	return false
end

local function hasActiveHazardProtection(now)
	if #activeFireBursts > 0 then
		return true
	end

	if isLocalPlayerBurrowProtected(now) then
		return true
	end

	return false
end

local function updateHazardSuppression()
	local now = os.clock()
	local rootPart = getRootPart()

	for i = #activeFireBursts, 1, -1 do
		local burst = activeFireBursts[i]
		if now >= burst.EndTime or not rootPart then
			table.remove(activeFireBursts, i)
		else
			-- Corridor hazards are client-created in this project, so Fire Burst
			-- suppresses nearby minor hazards locally after the server authorizes it.
			if now >= (burst.NextScanAt or 0) then
				burst.NextScanAt = now + FIRE_BURST_HAZARD_SUPPRESSION_INTERVAL
				suppressHazardsNearPosition(rootPart.Position, burst.Radius, burst.EndTime, function(_, hazardClass)
					return hazardClass == "minor"
				end, true, FIRE_BURST_HAZARD_SUPPRESSION_SOURCE)
			end
		end
	end

	if isLocalPlayerBurrowProtected(now) then
		if rootPart then
			suppressHazardsNearPosition(
				rootPart.Position,
				activeMoguBurrow.Radius,
				activeMoguBurrow.EndTime,
				nil,
				nil,
				MOGU_HAZARD_SUPPRESSION_SOURCE
			)
		end
	end

	restoreSuppressedParts(now)

	if hasActiveHazardProtection(now) then
		task.delay(HAZARD_SUPPRESSION_INTERVAL, updateHazardSuppression)
	else
		hazardSuppressionLoopRunning = false
	end
end

local function ensureHazardSuppressionLoop()
	if hazardSuppressionLoopRunning then
		return
	end

	hazardSuppressionLoopRunning = true
	updateHazardSuppression()
end

local function startFireBurst(_payload)
	-- FireBurst hazard targets are not ready yet; skip local hazard scans to avoid release stutter.
end

local function startMoguBurrow(targetPlayer, payload)
	if targetPlayer ~= player then
		return
	end

	local resolvedPayload = payload or {}
	local duration = math.max(0, tonumber(resolvedPayload.Duration) or 0)
	if duration <= 0 then
		duration = math.max(0.5, tonumber((DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}).BurrowDuration) or 5)
	end

	activeMoguBurrow = {
		EndTime = os.clock() + duration,
		Radius = math.max(0, tonumber(resolvedPayload.HazardProtectionRadius) or getMoguHazardProtectionRadius()),
	}

	ensureHazardSuppressionLoop()
end

local function stopMoguBurrow(targetPlayer)
	if targetPlayer ~= player then
		return
	end

	activeMoguBurrow = nil
	restoreSuppressedParts(os.clock(), MOGU_HAZARD_SUPPRESSION_SOURCE)
	applyMoguSurfaceHazardOverlap()
end

local function getProjectileDirection(direction, rootPart)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.01 then
		if not rootPart then
			return Vector3.new(0, 0, -1)
		end

		direction = rootPart.CFrame.LookVector
	end

	local planarDirection = Vector3.new(direction.X, 0, direction.Z)
	if planarDirection.Magnitude > 0.01 then
		return planarDirection.Unit
	end

	if direction.Magnitude > 0.01 then
		return direction.Unit
	end

	return Vector3.new(0, 0, -1)
end

playOptionalEffect = function(targetPlayer, fruitName, abilityName, payload)
	return DevilFruitOptionalEffects.Play(targetPlayer, fruitName, abilityName, payload)
end

fruitModuleLoader = FruitModuleLoader.new({
	player = player,
	clientEffectVisuals = clientEffectVisuals,
	GetCharacter = getCharacter,
	GetCurrentCamera = getCurrentCamera,
	GetEquippedFruit = getEquippedFruit,
	GetHumanoid = getHumanoid,
	GetLocalRootPart = getRootPart,
	GetPlayerRootPart = getPlayerRootPart,
	PlayOptionalEffect = playOptionalEffect,
	RequestAbility = function(abilityName, payload)
		requestRemote:FireServer(abilityName, payload)
	end,
	CreateEffectVisual = function(startPosition, endPosition, direction, isPredicted)
		clientEffectVisuals:CreateMeraFlameDashEffectVisual(startPosition, endPosition, direction, isPredicted)
	end,
})
inputController = DevilFruitInputController.new({
	player = player,
	loader = fruitModuleLoader,
})
effectRouter = DevilFruitEffectRouter.new({
	player = player,
	loader = fruitModuleLoader,
	playOptionalEffect = playOptionalEffect,
	clientEffectVisuals = clientEffectVisuals,
})

local function initializeDevilFruitClient()
	logDevilFruitClient("init begin")
	local requestIdentity = describeRemote(requestRemote)
	logDevilFruitClient(
		"remote bundle resolved request=%s path=%s runtimeId=%s debugId=%s object=%s state=%s effect=%s folder=%s",
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object),
		tostring(describeRemote(stateRemote).Path),
		tostring(describeRemote(effectRemote).Path),
		tostring(RemoteBundle.Folder:GetFullName())
	)

	syncDevilFruitClientState = function()
		local currentFruitName = getEquippedFruit()
		local previousFruitName = lastSyncedFruitName
		if currentFruitName ~= lastSyncedFruitName then
			fruitModuleLoader:CallControllerMethod(previousFruitName, "HandleUnequipped", currentFruitName)
			logDevilFruitClient(
				"fruit changed previous=%s current=%s",
				tostring(lastSyncedFruitName),
				tostring(currentFruitName)
			)
			lastSyncedFruitName = currentFruitName
		end

		local warmedController = fruitModuleLoader:GetController(currentFruitName)
		if warmedController and currentFruitName ~= previousFruitName then
			fruitModuleLoader:CallControllerMethod(currentFruitName, "HandleEquipped", previousFruitName)
		end

		hookFruitFolderSignals()
		updateCooldownHud(true)
		local fruitFolder = getFruitFolder()
		local equippedValue = fruitFolder and fruitFolder:FindFirstChild("Equipped")
		local equippedValueText = equippedValue and equippedValue:IsA("StringValue") and equippedValue.Value or "<nil>"
		logDevilFruitClient(
			"fruit state synced equipped=%s attr=%s value=%s",
			tostring(currentFruitName),
			tostring(player:GetAttribute("EquippedDevilFruit")),
			tostring(equippedValueText)
		)
	end

	ensureCooldownHud()
	logDevilFruitClient("UI bind success")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local traceAbilityInput = shouldTraceAbilityInput(input.KeyCode)
		local equippedFruitName = traceAbilityInput and getEquippedFruit() or nil
		local focusedTextBox = UserInputService:GetFocusedTextBox()
		if traceAbilityInput then
			logDevilFruitClient(
				"bind raw key=%s processed=%s focused=%s modal=%s equipped=%s",
				tostring(input.KeyCode.Name),
				tostring(gameProcessed),
				tostring(focusedTextBox ~= nil),
				tostring(isGameplayModalOpen()),
				tostring(equippedFruitName)
			)
		end

		if gameProcessed then
			if traceAbilityInput then
				logDevilFruitClient(
					"bind blocked key=%s reason=game_processed equipped=%s",
					tostring(input.KeyCode.Name),
					tostring(equippedFruitName)
				)
			end
			return
		end

		if focusedTextBox then
			if traceAbilityInput then
				logDevilFruitClient(
					"bind blocked key=%s reason=textbox_focus textbox=%s equipped=%s",
					tostring(input.KeyCode.Name),
					tostring(focusedTextBox:GetFullName()),
					tostring(equippedFruitName)
				)
			end
			return
		end

		local handledByCurrentFruit, shouldConsumeInput = fruitModuleLoader:CallControllerMethod(
			equippedFruitName or getEquippedFruit(),
			"HandleInputBegan",
			input,
			gameProcessed
		)
		if handledByCurrentFruit and shouldConsumeInput then
			return
		end

		local fruitName, abilityName, abilityEntry = getAbilityForKeyCode(input.KeyCode)
		if traceAbilityInput then
			logDevilFruitClient(
				"bind lookup key=%s equipped=%s resolvedFruit=%s ability=%s hasEntry=%s",
				tostring(input.KeyCode.Name),
				tostring(equippedFruitName),
				tostring(fruitName),
				tostring(abilityName),
				tostring(abilityEntry ~= nil)
			)
		end
		if not abilityName then
			if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.C then
				logDevilFruitClient(
					"bind ignored key=%s equipped=%s reason=no_ability",
					tostring(input.KeyCode.Name),
					tostring(fruitName or getEquippedFruit())
				)
			end
			return
		end

		if not isLocallyReady(abilityName) then
			local _, canActivateOnLocalCooldown = fruitModuleLoader:CallControllerMethod(
				fruitName,
				"CanActivateOnLocalCooldown",
				abilityName,
				abilityEntry,
				input
			)
			if canActivateOnLocalCooldown == true then
				logDevilFruitClient(
					"bind bypass local cooldown key=%s fruit=%s ability=%s",
					tostring(input.KeyCode.Name),
					tostring(fruitName),
					tostring(abilityName)
				)
			else
				logDevilFruitClient(
					"bind ignored key=%s fruit=%s ability=%s reason=local_cooldown",
					tostring(input.KeyCode.Name),
					tostring(fruitName),
					tostring(abilityName)
				)
				return
			end
		end

		local requestStartedAt = os.clock()
		local requestIdentity = describeRemote(requestRemote)
		logDevilFruitRequest(
			"client dispatch begin key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(requestIdentity.Name),
			tostring(requestIdentity.Path),
			tostring(requestIdentity.RuntimeId),
			tostring(requestIdentity.DebugId),
			tostring(requestIdentity.Object)
		)
		local requestPayload = inputController:BuildPredictedRequest(fruitName, abilityName, function()
			return buildAbilityRequestPayload(fruitName, abilityName)
		end)
		logDevilFruitClient(
			"bind dispatch key=%s fruit=%s ability=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(requestPayload)
		)
		logDevilFruitClient(
			"remote fire begin key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(requestIdentity.Name),
			tostring(requestIdentity.Path),
			tostring(requestIdentity.RuntimeId),
			tostring(requestIdentity.DebugId),
			tostring(requestIdentity.Object),
			countPayloadKeys(requestPayload)
		)
		requestRemote:FireServer(abilityName, requestPayload)
		logDevilFruitClient(
			"remote fire end key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(requestIdentity.Name),
			tostring(requestIdentity.Path),
			tostring(requestIdentity.RuntimeId),
			tostring(requestIdentity.DebugId),
			tostring(requestIdentity.Object),
			countPayloadKeys(requestPayload)
		)
		logDevilFruitRequest(
			"client dispatch end key=%s fruit=%s ability=%s payloadKeys=%d elapsedMs=%.2f",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(requestPayload),
			(os.clock() - requestStartedAt) * 1000
		)
		if traceAbilityInput then
			logDevilFruitClient(
				"bind remote fired key=%s fruit=%s ability=%s",
				tostring(input.KeyCode.Name),
				tostring(fruitName),
				tostring(abilityName)
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		fruitModuleLoader:CallControllerMethod(getEquippedFruit(), "HandleInputEnded", input)
	end)
	logDevilFruitClient("keybind connect success")

	stateRemote.OnClientEvent:Connect(function(eventName, fruitName, abilityName, value, payload)
		if eventName == "Activated" then
			local readyAt = tonumber(value) or 0
			setLocalCooldown(abilityName, readyAt, payload)
			updateCooldownHud()

			fruitModuleLoader:CallControllerMethod(fruitName, "HandleStateEvent", eventName, abilityName, value, payload)

			if fruitName == "Mera Mera no Mi" and abilityName == "FireBurst" then
				startFireBurst(payload or {})
			end
			return
		end

		fruitModuleLoader:CallControllerMethod(fruitName, "HandleStateEvent", eventName, abilityName, value, payload)

		if eventName == "Denied" and value == "Cooldown" then
			local readyAt = tonumber(payload) or 0
			if readyAt > 0 then
				setLocalCooldown(abilityName, readyAt)
				updateCooldownHud()
			end
		end
	end)

	effectRemote.OnClientEvent:Connect(function(targetPlayer, fruitName, abilityName, payload)
		if not targetPlayer or not targetPlayer:IsA("Player") then
			return
		end

		if fruitName == MOGU_FRUIT_NAME and abilityName == MOGU_BURROW_ABILITY then
			local phase = payload and payload.Phase
			if phase == "Start" then
				startMoguBurrow(targetPlayer, payload)
				effectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
				return
			elseif phase == "Resolve" then
				effectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
				stopMoguBurrow(targetPlayer)
				return
			end
		end

		effectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
	end)

	RunService.Heartbeat:Connect(function(dt)
		fruitModuleLoader:ForEachLoadedController("Update", dt)
	end)

	player.CharacterRemoving:Connect(function()
		activeFireBursts = {}
		activeMoguBurrow = nil
		fruitModuleLoader:ForEachLoadedController("HandleCharacterRemoving")
		hazardSuppressionLoopRunning = false
		restoreSuppressedParts(math.huge)
	end)

	Players.PlayerRemoving:Connect(function(leavingPlayer)
		fruitModuleLoader:ForEachLoadedController("HandlePlayerRemoving", leavingPlayer)
	end)

	player.CharacterAdded:Connect(function()
		if hasActiveHazardProtection(os.clock()) then
			ensureHazardSuppressionLoop()
		end
	end)

	player:GetAttributeChangedSignal("EquippedDevilFruit"):Connect(function()
		syncDevilFruitClientState()
	end)

	player:GetAttributeChangedSignal("DevilFruitCooldownBypass"):Connect(function()
		updateCooldownHud(false)
	end)

	playerGui:GetAttributeChangedSignal(GAMEPLAY_MODAL_OPEN_ATTRIBUTE):Connect(function()
		updateCooldownHud(false)
	end)

	player.ChildAdded:Connect(function(child)
		if child.Name == "DevilFruit" then
			syncDevilFruitClientState()
		end
	end)

	RunService.RenderStepped:Connect(function()
		fruitModuleLoader:ForEachLoadedController("RenderUpdate")

		local now = os.clock()
		if now < nextHudRefreshAt then
			return
		end

		nextHudRefreshAt = now + HUD_REFRESH_INTERVAL
		updateCooldownHud(false)
	end)

	task.defer(function()
		local ok, err = xpcall(syncDevilFruitClientState, debug.traceback)
		if not ok then
			warn(string.format("[DEVILFRUIT CLIENT][ERROR] startup failed: %s", tostring(err)))
		end
	end)

	logDevilFruitClient("init success")
end

function DevilFruitClientController.Start()
	if started then
		return DevilFruitClientController
	end

	started = true

	local initOk, initError = xpcall(initializeDevilFruitClient, debug.traceback)
	if not initOk then
		warn(string.format("[DEVILFRUIT CLIENT][ERROR] startup failed: %s", tostring(initError)))
		error(initError)
	end

	return DevilFruitClientController
end

return DevilFruitClientController
