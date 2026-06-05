local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local BOOTSTRAP_STARTED_AT = os.clock()
local PLAYER_GUI_TIMEOUT_SECONDS = 5
local REMOTES_FOLDER_NAME = "Remotes"
local LOAD_TELEMETRY_REMOTE_NAME = "GTRLoadTelemetry"
local SLOW_LOAD_THRESHOLD_SECONDS = 12
local playerGui = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", PLAYER_GUI_TIMEOUT_SECONDS)
local HUD_DEBUG = false
local GIFT_BOOTSTRAP_DEBUG = ReplicatedStorage:GetAttribute("GiftBootstrapDebug") == true
local GIFT_BOOTSTRAP_DEBUG_VERSION = "gifts-bootstrap-slots-debug-2026-05-01"
local DEFAULT_COUNTER_ICONS = {
	Comet = "",
	Speed = "rbxassetid://108512951338844",
	Money = "rbxassetid://76300573750363",
}
local ensureFrame
local ensureTextLabel
local ensureImageLabel
local ensureImageButton
local ensureTextButton

local function getBootstrapDuration(): number
	return math.max(0, os.clock() - BOOTSTRAP_STARTED_AT)
end

local function sanitizeLogValue(value)
	return (tostring(value):gsub("%s+", "_"))
end

local function gtrLoadLog(status: string, reason: string, extras: {[string]: any}?, useWarn: boolean?)
	local fields = {
		"[GTR_LOAD]",
		"player=" .. sanitizeLogValue(player.Name),
		"userId=" .. tostring(player.UserId),
		"status=" .. sanitizeLogValue(status),
		string.format("duration=%.2f", getBootstrapDuration()),
		"reason=" .. sanitizeLogValue(reason),
	}

	if extras then
		for key, value in pairs(extras) do
			fields[#fields + 1] = sanitizeLogValue(key) .. "=" .. sanitizeLogValue(value)
		end
	end

	local message = table.concat(fields, " ")
	if useWarn then
		warn(message)
	else
		print(message)
	end
end

local function getDeviceInputType(): string
	local ok, inputType = pcall(function()
		return UserInputService:GetLastInputType()
	end)
	if ok and inputType then
		return tostring(inputType.Name)
	end
	if UserInputService.TouchEnabled then
		return "Touch"
	end
	if UserInputService.GamepadEnabled then
		return "Gamepad"
	end
	if UserInputService.KeyboardEnabled then
		return "Keyboard"
	end
	return "unknown"
end

local function submitBootstrapTelemetry(errorMessage: string)
	local payload = {
		UserId = player.UserId,
		JoinTimestamp = os.time(),
		LoadDuration = getBootstrapDuration(),
		CloseReason = "bootstrap_error",
		TimedOut = false,
		OverlayRecovery = false,
		CameraRecovery = false,
		MissingMilestones = "StartupHudReady",
		DeviceInputType = getDeviceInputType(),
		BootstrapError = true,
		DataInitError = false,
		SlowThresholdSeconds = SLOW_LOAD_THRESHOLD_SECONDS,
		Error = tostring(errorMessage):sub(1, 180),
	}

	task.spawn(function()
		local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
			or ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 5)
		if not remotes then
			return
		end

		local remote = remotes:FindFirstChild(LOAD_TELEMETRY_REMOTE_NAME)
			or remotes:WaitForChild(LOAD_TELEMETRY_REMOTE_NAME, 5)
		if remote and remote:IsA("RemoteEvent") then
			pcall(function()
				remote:FireServer(payload)
			end)
		end
	end)
end

local UI_STYLE = {
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	PanelFill = Color3.fromRGB(44, 62, 80),
	PanelFillDark = Color3.fromRGB(34, 49, 66),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	TextDisabled = Color3.fromRGB(122, 134, 150),
	ButtonInactive = Color3.fromRGB(42, 58, 77),
	Success = Color3.fromRGB(125, 219, 159),
	SuccessSoft = Color3.fromRGB(169, 240, 194),
	Danger = Color3.fromRGB(186, 86, 100),
	DangerSoft = Color3.fromRGB(218, 125, 138),
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	HeaderBackground = Color3.fromRGB(16, 35, 59),
	SectionBackground = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	CloseBright = Color3.fromRGB(200, 0, 9),
	CloseBrightSoft = Color3.fromRGB(235, 70, 78),
	MenuBackgroundImage = "rbxassetid://75192947200012",
}

local function hudLog(tag, ...)
	if HUD_DEBUG then
		print(tag, ...)
	end
end

local function hudError(...)
	warn("[HUD][ERROR]", ...)
end

local function giftBootstrapSafeName(inst)
	if not inst then
		return "nil"
	end
	local ok, full = pcall(function()
		return inst:GetFullName()
	end)
	return ok and full or tostring(inst)
end

local function giftBootstrapLog(...)
	if GIFT_BOOTSTRAP_DEBUG then
		print("[GIFT][BOOTSTRAP]", ...)
	end
end

local function markHudReady()
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local startupStateScript = modules and modules:FindFirstChild("StartupState")
	if startupStateScript and startupStateScript:IsA("ModuleScript") then
		local ok, StartupState = pcall(require, startupStateScript)
		if ok and typeof(StartupState) == "table" and StartupState.MarkHudReady then
			if StartupState.MarkHudReady(player) then
				return
			end
		end
	end

	if playerGui and playerGui.Parent then
		playerGui:SetAttribute("StartupHudReady", true)
		return
	end

	player:SetAttribute("StartupHudReady", true)
	task.spawn(function()
		local latePlayerGui = player:WaitForChild("PlayerGui", 2)
		if latePlayerGui and latePlayerGui:IsA("PlayerGui") then
			playerGui = latePlayerGui
			latePlayerGui:SetAttribute("StartupHudReady", true)
		end
	end)
end

local function ensureLegacyHudCompatibility(hud)
	hudLog("[HUD][LEGACY]", "enter", hud and hud:GetFullName() or "nil")
	if hud == nil then
		hudError("ensureLegacyHudCompatibility called with nil HUD")
		return
	end

	if not ensureFrame or not ensureTextLabel or not ensureImageLabel or not ensureTextButton then
		hudError(
			"Missing legacy compatibility helpers",
			"ensureFrame=" .. tostring(ensureFrame),
			"ensureTextLabel=" .. tostring(ensureTextLabel),
			"ensureImageLabel=" .. tostring(ensureImageLabel),
			"ensureTextButton=" .. tostring(ensureTextButton)
		)
		return
	end

	local existingGamepassesAd = hud:FindFirstChild("GamepassesAd")
	if existingGamepassesAd and existingGamepassesAd:IsA("GuiObject") then
		existingGamepassesAd.Visible = false
	end

	hudLog("[HUD][LEGACY]", "legacy GamepassesAd disabled")
end

local HUD_BUTTON_LAYOUT = {
	Store = UDim2.fromOffset(0, 0),
	Index = UDim2.fromOffset(94, 0),
	Gifts = UDim2.fromOffset(0, 94),
	Settings = UDim2.fromOffset(94, 94),
	Rebirth = UDim2.fromOffset(0, 188),
	Quest = UDim2.fromOffset(94, 188),
}

local HUD_BUTTON_NAMES = {
	Store = true,
	Index = true,
	Gifts = true,
	Settings = true,
	Rebirth = true,
	Quest = true,
}

local function ensureScreenGui(name, displayOrder)
	local existing = playerGui:FindFirstChild(name)
	if existing and existing:IsA("ScreenGui") then
		existing.Enabled = true
		existing.IgnoreGuiInset = true
		existing.ResetOnSpawn = false
		existing.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		existing.DisplayOrder = math.max(existing.DisplayOrder, displayOrder)
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = name
	screenGui.Enabled = true
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = displayOrder
	screenGui.Parent = playerGui
	return screenGui
end

ensureFrame = function(parent, name)
	local frame = parent:FindFirstChild(name)
	if frame and frame:IsA("Frame") then
		return frame
	end

	if frame then
		frame:Destroy()
	end

	frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Visible = true
	frame.Parent = parent
	return frame
end

ensureTextLabel = function(parent, name)
	local label = parent:FindFirstChild(name)
	if label and label:IsA("TextLabel") then
		return label
	end

	if label then
		label:Destroy()
	end

	label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.Text = ""
	label.Parent = parent
	return label
end

ensureImageLabel = function(parent, name)
	local image = parent:FindFirstChild(name)
	if image and image:IsA("ImageLabel") then
		return image
	end

	if image then
		image:Destroy()
	end

	image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Image = ""
	image.Parent = parent
	return image
end

ensureImageButton = function(parent, name)
	local button = parent:FindFirstChild(name)
	if button and button:IsA("ImageButton") then
		return button
	end

	if button then
		button:Destroy()
	end

	button = Instance.new("ImageButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.ImageTransparency = 1
	button.Parent = parent
	return button
end

local function ensureGuiButton(parent, name)
	local button = parent:FindFirstChild(name)
	if button and button:IsA("GuiButton") then
		return button
	end

	return ensureImageButton(parent, name)
end

ensureTextButton = function(parent, name)
	local button = parent:FindFirstChild(name)
	if button and button:IsA("TextButton") then
		return button
	end

	if button then
		button:Destroy()
	end

	button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.Parent = parent
	return button
end

local function ensureUIStroke(parent, color, thickness)
	local stroke = parent:FindFirstChildOfClass("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Parent = parent
	end

	if color then
		stroke.Color = color
	end

	if thickness then
		stroke.Thickness = thickness
	end

	return stroke
end

local function ensureUIGradient(parent, color0, color1)
	local gradient = parent:FindFirstChildOfClass("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Parent = parent
	end

	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color0),
		ColorSequenceKeypoint.new(1, color1),
	})
	return gradient
end

local function ensureUICorner(parent, radius)
	local corner = parent:FindFirstChildOfClass("UICorner")
	if not corner then
		corner = Instance.new("UICorner")
		corner.Parent = parent
	end
	corner.CornerRadius = UDim.new(0, radius)
	return corner
end

local function clearChildren(parent, preserveNames)
	for _, child in ipairs(parent:GetChildren()) do
		if preserveNames and preserveNames[child.Name] then
			continue
		end
		child:Destroy()
	end
end

local function captureLegacyCounterImages(counters)
	local images = {
		Comet = DEFAULT_COUNTER_ICONS.Comet,
		Speed = DEFAULT_COUNTER_ICONS.Speed,
		Money = DEFAULT_COUNTER_ICONS.Money,
	}
	if not counters then
		return images
	end

	for _, statName in ipairs({ "Comet", "Speed", "Money" }) do
		local host = counters:FindFirstChild(statName)
		if host then
			local icon = host:FindFirstChild("Icon")
			if not (icon and icon:IsA("ImageLabel")) then
				icon = host:FindFirstChildWhichIsA("ImageLabel", true)
			end
			if icon and icon:IsA("ImageLabel") and tostring(icon.Image) ~= "" then
				images[statName] = tostring(icon.Image)
			end
		end
	end

	return images
end

local function ensureCounterHost(counters, name, iconImage)
	local host = counters:FindFirstChild(name)
	if host and not host:IsA("TextLabel") then
		host:Destroy()
		host = nil
	end

	if not host then
		host = Instance.new("TextLabel")
		host.Name = name
		host.Parent = counters
	end

	host.BackgroundTransparency = 1
	host.BorderSizePixel = 0
	host.Size = UDim2.fromOffset(220, 46)
	host.Text = string.format("0 %s", name == "Money" and "Beli" or name)
	host.TextColor3 = Color3.fromRGB(255, 255, 255)
	host.TextStrokeTransparency = 0
	host.TextXAlignment = Enum.TextXAlignment.Left
	host.Font = Enum.Font.GothamBlack
	host.TextSize = 32
	host.ClipsDescendants = false

	local icon = ensureImageLabel(host, "Icon")
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.Size = UDim2.fromOffset(36, 36)
	icon.Image = iconImage or ""
	icon.ScaleType = Enum.ScaleType.Fit

	ensureUIGradient(host, Color3.fromRGB(255, 255, 255), Color3.fromRGB(210, 210, 210))
	ensureUIStroke(host, Color3.fromRGB(0, 0, 0), 2)

	return host
end

local function ensureHudButton(lButtons, name, showTimer)
	local button = ensureGuiButton(lButtons, name)
	button.Visible = true
	button.Active = true
	button.AutoButtonColor = false
	button.Size = UDim2.fromOffset(92, 92)
	button.Position = HUD_BUTTON_LAYOUT[name] or UDim2.fromOffset(0, 0)
	button.ClipsDescendants = false

	local badge = ensureFrame(button, "Not")
	badge.Visible = false
	badge.Size = UDim2.fromOffset(34, 22)
	badge.Position = UDim2.new(1, -24, 0, -4)
	badge.BackgroundColor3 = Color3.fromRGB(235, 65, 92)
	badge.BackgroundTransparency = 0
	ensureUICorner(badge, 11)

	local badgeText = ensureTextLabel(badge, "TextLB")
	badgeText.Size = UDim2.fromScale(1, 1)
	badgeText.TextScaled = true
	badgeText.Text = "0"

	local summaryTimer = button:FindFirstChild("GiftSummaryTimer")

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant.Name == "Timer" or descendant.Name == "Timer2" or (descendant.Name == "GiftSummaryTimer" and showTimer ~= true) then
			local descendantPath = descendant:GetFullName()
			descendant:Destroy()
			hudLog(
				"[HUD][TIMER]",
				string.format(
					"button=%s removedDescendant=%s giftsSummaryRequested=%s",
					button:GetFullName(),
					descendantPath,
					tostring(showTimer == true)
				)
			)
		end
	end

	if showTimer == true then
		if summaryTimer and not summaryTimer:IsA("TextLabel") then
			summaryTimer:Destroy()
			summaryTimer = nil
		end
		if not summaryTimer then
			summaryTimer = ensureTextLabel(button, "GiftSummaryTimer")
		end

		summaryTimer.Visible = true
		summaryTimer.AnchorPoint = Vector2.new(0.5, 0)
		summaryTimer.BackgroundColor3 = UI_STYLE.PanelFillDark
		summaryTimer.BackgroundTransparency = 0.04
		summaryTimer.BorderSizePixel = 0
		summaryTimer.Font = Enum.Font.GothamBold
		summaryTimer.Position = UDim2.new(0.5, 0, 0, 8)
		summaryTimer.Size = UDim2.new(1, -20, 0, 18)
		summaryTimer.Text = "--"
		summaryTimer.TextColor3 = UI_STYLE.TextMain
		summaryTimer.TextScaled = true
		summaryTimer.TextStrokeColor3 = UI_STYLE.GoldShadow
		summaryTimer.TextStrokeTransparency = 0.25
		summaryTimer.TextXAlignment = Enum.TextXAlignment.Center
		summaryTimer.TextYAlignment = Enum.TextYAlignment.Center
		summaryTimer.ZIndex = math.max(button.ZIndex + 9, 11)
		ensureUICorner(summaryTimer, 9)
		ensureUIStroke(summaryTimer, UI_STYLE.GoldBase, 1).Transparency = 0.4
		ensureUIGradient(summaryTimer, UI_STYLE.SecondaryBg, UI_STYLE.PrimaryBg).Rotation = 90

		hudLog(
			"[HUD][TIMER]",
			string.format("button=%s summaryTimer=%s visible=%s", button:GetFullName(), summaryTimer:GetFullName(), tostring(summaryTimer.Visible))
		)
	elseif summaryTimer and summaryTimer:IsA("GuiObject") then
		summaryTimer:Destroy()
	end

	hudLog(
		"[HUD][SIDEBAR]",
		string.format(
			"button=%s class=%s visible=%s active=%s descendants=%d position=%s size=%s showTimer=%s",
			button:GetFullName(),
			button.ClassName,
			tostring(button.Visible),
			tostring(button.Active),
			#button:GetDescendants(),
			tostring(button.Position),
			tostring(button.Size),
			tostring(showTimer == true)
		)
	)

	return button
end

local function ensureHud()
	local hud = ensureScreenGui("HUD", 110)
	hud.Enabled = true

	local lButtons = ensureFrame(hud, "LButtons")
	clearChildren(lButtons, HUD_BUTTON_NAMES)
	lButtons.Visible = true
	lButtons.Size = UDim2.fromOffset(198, 288)
	lButtons.Position = UDim2.fromOffset(10, 250)
	lButtons.ClipsDescendants = false

	hudLog(
		"[HUD][BOOT]",
		string.format(
			"hud=%s enabled=%s sidebar=%s preservedChildren=%d",
			hud:GetFullName(),
			tostring(hud.Enabled),
			lButtons:GetFullName(),
			#lButtons:GetChildren()
		)
	)

	ensureHudButton(lButtons, "Store", false)
	ensureHudButton(lButtons, "Index", false)
	ensureHudButton(lButtons, "Gifts", true)
	ensureHudButton(lButtons, "Settings", false)
	ensureHudButton(lButtons, "Rebirth", false)
	ensureHudButton(lButtons, "Quest", false)

	local counters = ensureFrame(hud, "Counters")
	local legacyCounterImages = captureLegacyCounterImages(counters)
	clearChildren(counters)
	counters.AnchorPoint = Vector2.new(0, 1)
	counters.Size = UDim2.fromOffset(250, 172)
	counters.Position = UDim2.fromScale(0, 1)
	counters.ClipsDescendants = false

	local comet = ensureCounterHost(counters, "Comet", legacyCounterImages.Comet)
	comet.Position = UDim2.fromOffset(0, 0)
	ensureUIGradient(comet, Color3.fromRGB(185, 159, 222), Color3.fromRGB(226, 240, 255))

	local speed = ensureCounterHost(counters, "Speed", legacyCounterImages.Speed)
	speed.Position = UDim2.fromOffset(0, 52)
	ensureUIGradient(speed, Color3.fromRGB(255, 122, 122), Color3.fromRGB(255, 204, 176))

	local money = ensureCounterHost(counters, "Money", legacyCounterImages.Money)
	money.Position = UDim2.fromOffset(0, 104)
	ensureUIGradient(money, Color3.fromRGB(62, 181, 35), Color3.fromRGB(198, 255, 76))

	local countersNot = ensureFrame(counters, "Not")
	countersNot.Visible = false
	countersNot.Size = UDim2.fromOffset(40, 24)

	local progressBar = ensureFrame(hud, "ProgressBar")
	progressBar.Size = UDim2.new(1, 0, 0, 82)
	progressBar.Position = UDim2.fromOffset(0, 0)
	ensureImageLabel(progressBar, "PFP").Visible = false
	ensureImageLabel(progressBar, "Disaster").Visible = false

	local boosts = ensureFrame(hud, "Boosts")
	clearChildren(boosts)
	boosts.Size = UDim2.fromOffset(210, 120)
	boosts.Position = UDim2.fromOffset(16, 300)
	local boostTemplate = ensureFrame(boosts, "Template")
	boostTemplate.Visible = false
	boostTemplate.Size = UDim2.fromOffset(150, 42)
	ensureImageLabel(boostTemplate, "Icon").Size = UDim2.fromOffset(24, 24)
	ensureTextLabel(boostTemplate, "Count").Size = UDim2.fromOffset(100, 20)

	local tutorial = ensureFrame(hud, "Tutorial")
	tutorial.Visible = false
	tutorial.Size = UDim2.fromOffset(520, 120)
	tutorial.Position = UDim2.new(0.5, -260, 0, 96)
	local step = ensureTextLabel(tutorial, "Step")
	step.Size = UDim2.fromOffset(500, 30)
	local stepWave = ensureTextLabel(step, "Wave")
	stepWave.Size = UDim2.fromScale(1, 1)
	local info = ensureTextLabel(tutorial, "Info")
	info.Size = UDim2.fromOffset(500, 64)
	info.Position = UDim2.fromOffset(0, 34)
	local infoWave = ensureTextLabel(info, "Wave")
	infoWave.Size = UDim2.fromScale(1, 1)

	local leaving = ensureFrame(hud, "Leaving")
	leaving.Visible = false
	leaving.Size = UDim2.fromOffset(300, 120)
	local gradient = ensureFrame(leaving, "Gradient")
	local gradientOne = ensureFrame(gradient, "1")
	if not gradientOne:FindFirstChildOfClass("UIGradient") then
		Instance.new("UIGradient").Parent = gradientOne
	end
	local letsDoIt = ensureTextButton(leaving, "LetsDoIt")
	letsDoIt.Size = UDim2.fromOffset(120, 36)

	local leavingInfo = ensureFrame(hud, "LeavingInfo")
	leavingInfo.Visible = false
	leavingInfo.Size = UDim2.fromOffset(240, 90)
	ensureTextLabel(leavingInfo, "Time").Size = UDim2.fromOffset(160, 40)

	local adminInfo = ensureFrame(hud, "AdminInfo")
	clearChildren(adminInfo)
	adminInfo.Visible = true
	adminInfo.Size = UDim2.new(1, 0, 0, 180)
	adminInfo.Position = UDim2.fromOffset(0, 16)
	local annTemplate = ensureFrame(adminInfo, "AnnTemplate")
	annTemplate.Visible = false
	annTemplate.Size = UDim2.fromOffset(460, 80)
	local textLb = ensureTextLabel(annTemplate, "TextLB")
	textLb.Size = UDim2.fromOffset(320, 28)
	local shadow = ensureTextLabel(textLb, "Shadow")
	shadow.Size = UDim2.fromScale(1, 1)
	ensureImageLabel(annTemplate, "PFP").Size = UDim2.fromOffset(56, 56)

	ensureLegacyHudCompatibility(hud)
end

local function ensureFrames()
	ensureScreenGui("Frames", 120)
end

local function runBootstrap()
	if not (playerGui and playerGui.Parent) then
		error(string.format("PlayerGui unavailable after %.1fs", PLAYER_GUI_TIMEOUT_SECONDS))
	end

	giftBootstrapLog(
		"start",
		"version",
		GIFT_BOOTSTRAP_DEBUG_VERSION,
		"playerGui",
		giftBootstrapSafeName(playerGui)
	)
	ensureHud()
	ensureFrames()
end

local ok, err = xpcall(runBootstrap, debug.traceback)
markHudReady()
if not ok then
	local message = tostring(err)
	gtrLoadLog("milestone_recovered", "bootstrap_error", {
		error = message:sub(1, 180),
	}, true)
	submitBootstrapTelemetry(message)
end
