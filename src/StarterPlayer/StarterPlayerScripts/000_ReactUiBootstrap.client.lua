local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local SettingsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Settings"))
local SpeedUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SpeedUpgrade"))
local TimeRewardsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeRewards"):WaitForChild("Config"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local HUD_DEBUG = false
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
local ensureLegacyInventoryButtonTemplate

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
	GiftsBackgroundImage = "rbxassetid://114391753019319",
	RebirthBackgroundImage = "rbxassetid://139545221830035",
}

local BUTTON_FX_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BUTTON_HOVER_SCALE = 1.03
local BUTTON_IDLE_SCALE = 1
local BUTTON_PRESS_SCALE = 0.97
local BUTTON_FX_BINDINGS = setmetatable({}, { __mode = "k" })

local function hudLog(tag, ...)
	if HUD_DEBUG then
		print(tag, ...)
	end
end

local function hudError(...)
	warn("[HUD][ERROR]", ...)
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

	local gamepassesAd = ensureFrame(hud, "GamepassesAd")
	gamepassesAd.Visible = false
	gamepassesAd.Size = UDim2.fromOffset(260, 120)
	gamepassesAd.Position = UDim2.new(1, -280, 0.5, -60)
	if not gamepassesAd:FindFirstChildOfClass("UIScale") then
		Instance.new("UIScale").Parent = gamepassesAd
	end
	ensureImageLabel(gamepassesAd, "Icon").Size = UDim2.fromOffset(56, 56)
	ensureTextLabel(gamepassesAd, "Info").Size = UDim2.fromOffset(160, 28)
	local productName = ensureTextLabel(gamepassesAd, "PName")
	productName.Size = UDim2.fromOffset(160, 28)
	ensureTextLabel(productName, "Shadow").Size = UDim2.fromScale(1, 1)
	ensureTextLabel(gamepassesAd, "Price").Size = UDim2.fromOffset(96, 24)
	ensureImageLabel(gamepassesAd, "ImageLabel").Size = UDim2.fromOffset(24, 24)
	ensureFrame(gamepassesAd, "Time").Size = UDim2.new(1, 0, 0, 6)
	ensureTextButton(gamepassesAd, "TextButton").Size = UDim2.new(1, 0, 1, 0)

	local inventory = ensureFrame(hud, "Inventory")
	local hotbarTemplate = ensureTextButton(inventory, "toolButton")
	hotbarTemplate.Visible = false
	hotbarTemplate.Size = UDim2.fromOffset(52, 52)
	ensureLegacyInventoryButtonTemplate(hotbarTemplate, false)
	local inv = ensureFrame(inventory, "Inv")
	inv.Visible = false
	local inventoryFrame = ensureFrame(inv, "InventoryFrame")
	local scrollingFrame = inventoryFrame:FindFirstChild("ScrollingFrame")
	if not (scrollingFrame and scrollingFrame:IsA("ScrollingFrame")) then
		scrollingFrame = Instance.new("ScrollingFrame")
		scrollingFrame.Name = "ScrollingFrame"
		scrollingFrame.BackgroundTransparency = 1
		scrollingFrame.BorderSizePixel = 0
		scrollingFrame.CanvasSize = UDim2.fromOffset(0, 0)
		scrollingFrame.Parent = inventoryFrame
	end
	scrollingFrame.Size = UDim2.new(1, 0, 1, 0)
	local inventoryTemplate = ensureTextButton(scrollingFrame, "toolButton")
	inventoryTemplate.Visible = false
	inventoryTemplate.Size = UDim2.fromOffset(80, 80)
	ensureLegacyInventoryButtonTemplate(inventoryTemplate, true)

	hudLog(
		"[HUD][LEGACY]",
		string.format(
			"gamepassesAd=%s inventory=%s hotbarTemplate=%s inventoryTemplate=%s",
			gamepassesAd:GetFullName(),
			inventory:GetFullName(),
			hotbarTemplate:GetFullName(),
			inventoryTemplate:GetFullName()
		)
	)
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

ensureLegacyInventoryButtonTemplate = function(button, isLargeButton)
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false

	local toolIcon = ensureImageLabel(button, "ToolIcon")
	toolIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	toolIcon.Position = isLargeButton and UDim2.new(0.5, 0, 0.36, 0) or UDim2.new(0.5, 0, 0.5, 0)
	toolIcon.Size = isLargeButton and UDim2.new(0.6, 0, 0.5, 0) or UDim2.new(0.68, 0, 0.68, 0)
	toolIcon.ScaleType = Enum.ScaleType.Fit
	toolIcon.ImageTransparency = 0

	local toolName = ensureTextLabel(button, "toolName")
	toolName.AnchorPoint = Vector2.new(0.5, 1)
	toolName.Position = UDim2.new(0.5, 0, 1, -3)
	toolName.Size = UDim2.new(1, -8, 0, 14)
	toolName.TextSize = isLargeButton and 10 or 9
	toolName.TextTruncate = Enum.TextTruncate.AtEnd
	toolName.TextWrapped = false
	toolName.Visible = isLargeButton

	local toolAmount = ensureTextLabel(button, "toolAmount")
	toolAmount.AnchorPoint = Vector2.new(1, 1)
	toolAmount.Position = UDim2.new(1, -4, 1, -4)
	toolAmount.Size = UDim2.fromOffset(42, 12)
	toolAmount.TextSize = 10
	toolAmount.TextXAlignment = Enum.TextXAlignment.Right
	toolAmount.TextYAlignment = Enum.TextYAlignment.Center
	toolAmount.Visible = false

	local toolNumber = ensureTextLabel(button, "toolNumber")
	toolNumber.Position = UDim2.fromOffset(4, 3)
	toolNumber.Size = UDim2.fromOffset(18, 12)
	toolNumber.TextSize = 10
	toolNumber.TextXAlignment = Enum.TextXAlignment.Left
	toolNumber.TextYAlignment = Enum.TextYAlignment.Top
	toolNumber.Visible = false
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

local function setLabelStyle(label, textSize, textColor)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = textColor or UI_STYLE.TextMain
	label.TextSize = textSize or 14
	label.TextStrokeColor3 = UI_STYLE.GoldShadow
	label.TextStrokeTransparency = 0.7
end

local function stylePanel(frame, cornerRadius)
	frame.BackgroundColor3 = UI_STYLE.PanelFill
	frame.BackgroundTransparency = 0.06
	frame.BorderSizePixel = 0
	ensureUICorner(frame, cornerRadius or 12)
	local stroke = ensureUIStroke(frame, UI_STYLE.GoldBase, 1.6)
	stroke.Transparency = 0.18
	local gradient = ensureUIGradient(frame, UI_STYLE.SecondaryBg, UI_STYLE.PrimaryBg)
	gradient.Rotation = 90
end

local function styleInsetPanel(frame, cornerRadius)
	frame.BackgroundColor3 = UI_STYLE.PanelFillDark
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	ensureUICorner(frame, cornerRadius or 10)
	local stroke = ensureUIStroke(frame, UI_STYLE.GoldShadow, 1.2)
	stroke.Transparency = 0.34
	local gradient = ensureUIGradient(frame, Color3.fromRGB(52, 72, 93), UI_STYLE.PanelFillDark)
	gradient.Rotation = 90
end

local function playScaleTween(scale, target)
	local tween = TweenService:Create(scale, BUTTON_FX_TWEEN, { Scale = target })
	tween:Play()
end

local function ensureButtonFeedback(button)
	if not button or not button:IsA("GuiButton") then
		return
	end
	if BUTTON_FX_BINDINGS[button] then
		return
	end

	local scale = button:FindFirstChild("GrandLineButtonScale")
	if not (scale and scale:IsA("UIScale")) then
		scale = Instance.new("UIScale")
		scale.Name = "GrandLineButtonScale"
		scale.Scale = BUTTON_IDLE_SCALE
		scale.Parent = button
	end

	local state = {
		hovered = false,
		pressing = false,
	}

	local function refreshScale()
		if state.pressing then
			playScaleTween(scale, BUTTON_PRESS_SCALE)
		elseif state.hovered then
			playScaleTween(scale, BUTTON_HOVER_SCALE)
		else
			playScaleTween(scale, BUTTON_IDLE_SCALE)
		end
	end

	local connections = {
		button.MouseEnter:Connect(function()
			state.hovered = true
			refreshScale()
		end),
		button.MouseLeave:Connect(function()
			state.hovered = false
			state.pressing = false
			refreshScale()
		end),
		button.MouseButton1Down:Connect(function()
			state.pressing = true
			refreshScale()
		end),
		button.MouseButton1Up:Connect(function()
			state.pressing = false
			refreshScale()
		end),
		button.Activated:Connect(function()
			state.pressing = false
			refreshScale()
		end),
		button.Destroying:Connect(function()
			local binding = BUTTON_FX_BINDINGS[button]
			if binding then
				for _, connection in ipairs(binding) do
					connection:Disconnect()
				end
				BUTTON_FX_BINDINGS[button] = nil
			end
		end),
	}

	BUTTON_FX_BINDINGS[button] = connections
end

local function stylePrimaryButton(button)
	button.BackgroundColor3 = UI_STYLE.Success
	button.BackgroundTransparency = 0
	button.TextColor3 = Color3.fromRGB(18, 30, 24)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 17
	local gradient = ensureUIGradient(button, UI_STYLE.SuccessSoft, UI_STYLE.Success)
	gradient.Rotation = 90
	local stroke = ensureUIStroke(button, UI_STYLE.GoldShadow, 1.1)
	stroke.Transparency = 0.28
	ensureUICorner(button, 10)
	ensureButtonFeedback(button)
end

local function styleSecondaryButton(button)
	button.BackgroundColor3 = UI_STYLE.ButtonInactive or UI_STYLE.PanelFillDark
	button.BackgroundTransparency = 0
	button.TextColor3 = UI_STYLE.TextMain
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	local gradient = ensureUIGradient(button, UI_STYLE.PanelFill, UI_STYLE.PrimaryBg)
	gradient.Rotation = 90
	local stroke = ensureUIStroke(button, UI_STYLE.GoldShadow, 1.1)
	stroke.Transparency = 0.2
	ensureUICorner(button, 10)
	ensureButtonFeedback(button)
end

local function styleCloseButton(button)
	button.BackgroundColor3 = UI_STYLE.Danger
	button.BackgroundTransparency = 0
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	local gradient = ensureUIGradient(button, UI_STYLE.DangerSoft, UI_STYLE.Danger)
	gradient.Rotation = 90
	local stroke = ensureUIStroke(button, UI_STYLE.GoldShadow, 1.1)
	stroke.Transparency = 0.16
	ensureUICorner(button, 8)
	ensureButtonFeedback(button)
end

local function styleMenuActionButton(frame)
	frame.BackgroundColor3 = UI_STYLE.HeaderBackground
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Active = true
	if frame:IsA("GuiButton") then
		frame.AutoButtonColor = false
	end
	ensureUICorner(frame, 10)
	local stroke = ensureUIStroke(frame, UI_STYLE.GoldHighlight, 1.2)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Transparency = 0.08
	local gradient = ensureUIGradient(frame, UI_STYLE.SecondaryBg, UI_STYLE.PrimaryBg)
	gradient.Rotation = 90
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
	icon.Position = UDim2.new(0, 0, 0.5, 0)
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

local function ensureSlotCard(slot, layoutOrder)
	slot.BackgroundColor3 = UI_STYLE.SectionBackground
	slot.BackgroundTransparency = 0.25
	slot.BorderSizePixel = 0
	slot.Active = true
	slot.Size = UDim2.new(1, -30, 0, 82)
	slot.LayoutOrder = layoutOrder
	slot.ClipsDescendants = true
	ensureUICorner(slot, 10)
	local slotStroke = ensureUIStroke(slot, UI_STYLE.GoldHighlight, 1.5)
	slotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	slotStroke.Transparency = 0

	if not slot:GetAttribute("HoverBound") then
		slot:SetAttribute("HoverBound", true)
		slot.MouseEnter:Connect(function()
			slot.BackgroundColor3 = UI_STYLE.SectionHover
		end)
		slot.MouseLeave:Connect(function()
			slot.BackgroundColor3 = UI_STYLE.SectionBackground
		end)
	end

	local rewName = ensureTextLabel(slot, "RewName")
	rewName.Size = UDim2.new(1, -192, 0, 22)
	rewName.Position = UDim2.fromOffset(68, 12)
	rewName.TextXAlignment = Enum.TextXAlignment.Left
	rewName.ZIndex = 5
	setLabelStyle(rewName, 17, UI_STYLE.TextMain)

	local timer = ensureTextLabel(slot, "Timer")
	timer.Size = UDim2.new(1, -192, 0, 20)
	timer.Position = UDim2.fromOffset(68, 40)
	timer.TextXAlignment = Enum.TextXAlignment.Left
	timer.ZIndex = 5
	setLabelStyle(timer, 15, UI_STYLE.TextSecondary)

	local icon = ensureImageLabel(slot, "Icon")
	icon.Size = UDim2.fromOffset(44, 44)
	icon.Position = UDim2.fromOffset(12, 19)
	icon.BackgroundColor3 = UI_STYLE.HeaderBackground
	icon.BackgroundTransparency = 0.25
	icon.BorderSizePixel = 0
	icon.ZIndex = 5
	ensureUICorner(icon, 8)
	local iconStroke = ensureUIStroke(icon, UI_STYLE.GoldHighlight, 1)
	iconStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	iconStroke.Transparency = 0

	local claimButton = ensureTextButton(slot, "ClaimButton")
	claimButton.AnchorPoint = Vector2.new(1, 0.5)
	claimButton.Size = UDim2.fromOffset(92, 34)
	claimButton.Position = UDim2.new(1, -14, 0.5, 0)
	claimButton.ZIndex = 6
	claimButton.Text = ""
	styleMenuActionButton(claimButton)
	ensureButtonFeedback(claimButton)

	local claimText = ensureTextLabel(claimButton, "Text")
	claimText.Size = UDim2.fromScale(1, 1)
	claimText.Position = UDim2.fromOffset(0, 0)
	claimText.Text = "Claim"
	claimText.TextScaled = false
	claimText.TextSize = 18
	claimText.Font = Enum.Font.GothamBold
	claimText.TextColor3 = UI_STYLE.TextMain
	claimText.TextStrokeColor3 = UI_STYLE.GoldShadow
	claimText.TextStrokeTransparency = 0.45
	claimText.ZIndex = 7
end

local function getTimeRewardCount()
	local count = 0
	for rewardId in pairs(TimeRewardsConfig) do
		if tonumber(rewardId) ~= nil then
			count += 1
		end
	end
	return math.max(count, 1)
end

local function ensureGiftsSlots(giftsMain)
	giftsMain.BackgroundTransparency = 1
	giftsMain.Size = UDim2.new(1, -42, 1, -126)
	giftsMain.Position = UDim2.fromOffset(18, 116)
	giftsMain.ClipsDescendants = true
	giftsMain.ZIndex = 3

	local scroll = giftsMain:FindFirstChild("Scroll")
	if scroll and not scroll:IsA("ScrollingFrame") then
		scroll:Destroy()
		scroll = nil
	end
	if not scroll then
		scroll = Instance.new("ScrollingFrame")
		scroll.Name = "Scroll"
		scroll.Parent = giftsMain
	end

	clearChildren(giftsMain, {
		Scroll = true,
	})

	scroll.Active = true
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.ClipsDescendants = true
	scroll.Position = UDim2.fromScale(0, 0)
	scroll.ScrollBarImageColor3 = UI_STYLE.GoldHighlight
	scroll.ScrollBarThickness = 8
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollingEnabled = true
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroll.ZIndex = 4

	local contentPadding = scroll:FindFirstChild("ContentPadding")
	if contentPadding and not contentPadding:IsA("UIPadding") then
		contentPadding:Destroy()
		contentPadding = nil
	end
	if not contentPadding then
		contentPadding = Instance.new("UIPadding")
		contentPadding.Name = "ContentPadding"
		contentPadding.Parent = scroll
	end
	contentPadding.PaddingTop = UDim.new(0, 8)
	contentPadding.PaddingBottom = UDim.new(0, 10)
	contentPadding.PaddingLeft = UDim.new(0, 4)
	contentPadding.PaddingRight = UDim.new(0, 4)

	local list = scroll:FindFirstChild("SlotLayout")
	if list and not list:IsA("UIListLayout") then
		list:Destroy()
		list = nil
	end
	if not list then
		list = Instance.new("UIListLayout")
		list.Name = "SlotLayout"
		list.Parent = scroll
	end
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)

	local preserveNames = {
		SlotLayout = true,
		ContentPadding = true,
	}
	local rewardCount = getTimeRewardCount()
	for index = 1, rewardCount do
		local slotName = "Slot" .. tostring(index)
		preserveNames[slotName] = true
		local slot = ensureFrame(scroll, slotName)
		slot.Visible = true
		ensureSlotCard(slot, index)
	end

	clearChildren(scroll, preserveNames)
end

local function ensureRebirthRequirement(parent, name, yOffset)
	local section = ensureFrame(parent, name)
	section.BackgroundColor3 = UI_STYLE.SectionBackground
	section.BackgroundTransparency = 0.25
	section.Size = UDim2.new(1, -32, 0, 72)
	section.Position = UDim2.fromOffset(16, yOffset)
	section.ZIndex = 4
	ensureUICorner(section, 10)
	local sectionStroke = ensureUIStroke(section, UI_STYLE.GoldHighlight, 1.5)
	sectionStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	sectionStroke.Transparency = 0

	local label = ensureTextLabel(section, "Label")
	label.Size = UDim2.new(1, -20, 0, 20)
	label.Position = UDim2.fromOffset(10, 8)
	label.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(label, 15, UI_STYLE.TextMain)
	label.Text = name == "Money" and "Beli" or "Ship Level"
	label.ZIndex = 5

	local value = ensureTextLabel(section, "Value")
	value.Size = UDim2.new(1, -20, 0, 22)
	value.Position = UDim2.fromOffset(10, 28)
	value.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(value, 16, UI_STYLE.TextMain)
	value.ZIndex = 5

	local track = ensureFrame(section, "Track")
	track.BackgroundColor3 = UI_STYLE.PrimaryBg
	track.BackgroundTransparency = 0.2
	track.Size = UDim2.new(1, -20, 0, 10)
	track.Position = UDim2.fromOffset(10, 56)
	track.ClipsDescendants = true
	track.ZIndex = 5
	ensureUICorner(track, 999)
	ensureUIStroke(track, UI_STYLE.GoldShadow, 1).Transparency = 0.15

	local bar = ensureFrame(track, "Bar")
	bar.BackgroundColor3 = UI_STYLE.Success
	bar.BackgroundTransparency = 0
	bar.Size = UDim2.new(0, 0, 1, 0)
	bar.Position = UDim2.fromOffset(0, 0)
	bar.ZIndex = 6
	ensureUICorner(bar, 999)
	ensureUIGradient(bar, UI_STYLE.SuccessSoft, UI_STYLE.Success).Rotation = 90

	return section
end

local function ensureSettingsSliderOption(scrollingFrame, optionName, layoutOrder)
	local option = ensureFrame(scrollingFrame, optionName)
	option.Size = UDim2.new(1, -18, 0, 88)
	option.LayoutOrder = layoutOrder
	styleInsetPanel(option, 10)

	local title = ensureTextLabel(option, "Title")
	title.Size = UDim2.new(1, -20, 0, 22)
	title.Position = UDim2.fromOffset(10, 8)
	title.Text = optionName
	title.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(title, 16, UI_STYLE.TextMain)

	local slider = ensureFrame(option, "Slider")
	slider.Size = UDim2.new(1, -64, 0, 42)
	slider.Position = UDim2.fromOffset(32, 38)
	slider.BackgroundColor3 = UI_STYLE.PrimaryBg
	slider.BackgroundTransparency = 0.08
	ensureUICorner(slider, 10)
	ensureUIStroke(slider, UI_STYLE.GoldShadow, 1).Transparency = 0.45
	ensureUIGradient(slider, UI_STYLE.SecondaryBg, UI_STYLE.PrimaryBg).Rotation = 90

	local main = ensureTextButton(slider, "Main")
	main.Size = UDim2.fromOffset(34, 34)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.new(0.47, 0, 0.5, 0)
	main.Text = ""
	ensureButtonFeedback(main)

	local mainFrame = ensureFrame(main, "Frame")
	mainFrame.Size = UDim2.fromScale(1, 1)
	mainFrame.BackgroundColor3 = UI_STYLE.GoldBase
	mainFrame.BackgroundTransparency = 0
	ensureUICorner(mainFrame, 999)
	ensureUIGradient(mainFrame, UI_STYLE.GoldHighlight, UI_STYLE.GoldBase)
	ensureUIStroke(mainFrame, UI_STYLE.GoldShadow, 1)

	local bg = ensureFrame(mainFrame, "BG")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundTransparency = 1
	local bgFrame = ensureFrame(bg, "Frame")
	bgFrame.Size = UDim2.fromScale(1, 1)
	bgFrame.BackgroundTransparency = 1
	ensureUIGradient(bgFrame, UI_STYLE.GoldHighlight, UI_STYLE.GoldBase)
	local bgMain = ensureFrame(bg, "Main")
	bgMain.Size = UDim2.fromScale(1, 1)
	bgMain.BackgroundTransparency = 1
	ensureUIGradient(bgMain, UI_STYLE.GoldHighlight, UI_STYLE.GoldBase)

	local bh = ensureFrame(mainFrame, "BH")
	bh.Size = UDim2.fromScale(1, 1)
	bh.BackgroundTransparency = 1
	local bhFrame = ensureFrame(bh, "Frame")
	bhFrame.Size = UDim2.fromScale(1, 1)
	bhFrame.BackgroundTransparency = 1
	ensureUIGradient(bhFrame, UI_STYLE.GoldHighlight, UI_STYLE.GoldBase)

	local textLabel = ensureTextLabel(mainFrame, "TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Text = "100"
	textLabel.TextScaled = true
	textLabel.TextColor3 = UI_STYLE.TextMain
	ensureUIGradient(textLabel, UI_STYLE.TextMain, UI_STYLE.TextMain)
	ensureUIStroke(textLabel, UI_STYLE.GoldShadow, 1).Transparency = 0.35
end

local function ensureSettingsSwitchOption(scrollingFrame, optionName, layoutOrder)
	local option = ensureFrame(scrollingFrame, optionName)
	option.Size = UDim2.new(1, -18, 0, 76)
	option.LayoutOrder = layoutOrder
	styleInsetPanel(option, 10)

	local title = ensureTextLabel(option, "Title")
	title.Size = UDim2.new(1, -132, 0, 24)
	title.Position = UDim2.fromOffset(10, 26)
	title.Text = optionName
	title.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(title, 16, UI_STYLE.TextMain)

	local on = ensureTextButton(option, "ON")
	on.Size = UDim2.fromOffset(92, 34)
	on.Position = UDim2.new(1, -102, 0.5, -17)
	on.BackgroundTransparency = 0
	on.Text = "ON"
	stylePrimaryButton(on)

	local off = ensureTextButton(option, "OFF")
	off.Size = on.Size
	off.Position = on.Position
	off.BackgroundTransparency = 0
	off.Text = "OFF"
	off.Visible = false
	styleSecondaryButton(off)
end

local function ensureSpeedUpgradeCard(main, index, layoutOrder)
	local card = ensureFrame(main, tostring(index))
	card.Size = UDim2.new(1, -20, 0, 112)
	card.LayoutOrder = layoutOrder
	styleInsetPanel(card, 12)

	local template = ensureFrame(card, "Template")
	template.Size = UDim2.fromScale(1, 1)
	template.BackgroundTransparency = 1

	local addSpeed = ensureTextLabel(template, "AddSpeed")
	addSpeed.Size = UDim2.new(1, -320, 0, 30)
	addSpeed.Position = UDim2.fromOffset(12, 8)
	addSpeed.TextXAlignment = Enum.TextXAlignment.Left
	addSpeed.TextSize = 24
	addSpeed.Font = Enum.Font.GothamBold
	addSpeed.TextColor3 = UI_STYLE.TextMain

	local now = ensureTextLabel(template, "Now")
	now.Size = UDim2.fromOffset(260, 22)
	now.Position = UDim2.fromOffset(12, 44)
	now.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(now, 16, UI_STYLE.TextSecondary)
	now.Text = "Current: 0"

	local after = ensureTextLabel(template, "After")
	after.Size = UDim2.fromOffset(260, 22)
	after.Position = UDim2.fromOffset(12, 70)
	after.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(after, 16, UI_STYLE.TextSecondary)
	after.Text = "After: 0"

	local buy = ensureTextButton(template, "Buy")
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Size = UDim2.fromOffset(132, 40)
	buy.Position = UDim2.new(1, -146, 0.5, 16)
	buy.Text = ""
	stylePrimaryButton(buy)
	local buyMain = ensureFrame(buy, "Main")
	buyMain.Size = UDim2.fromScale(1, 1)
	buyMain.BackgroundTransparency = 1
	local buyText = ensureTextLabel(buyMain, "TextL")
	buyText.Size = UDim2.fromScale(1, 1)
	buyText.TextScaled = true
	buyText.Text = "Buy"
	buyText.TextColor3 = Color3.fromRGB(18, 30, 24)
	buyText.Font = Enum.Font.GothamBold

	local robux = ensureTextButton(template, "Robux")
	robux.AnchorPoint = Vector2.new(1, 0.5)
	robux.Size = UDim2.fromOffset(132, 40)
	robux.Position = UDim2.new(1, -12, 0.5, 16)
	robux.Text = ""
	styleSecondaryButton(robux)
	local robuxMain = ensureFrame(robux, "Main")
	robuxMain.Size = UDim2.fromScale(1, 1)
	robuxMain.BackgroundTransparency = 1
	local robuxText = ensureTextLabel(robuxMain, "TextL")
	robuxText.Size = UDim2.fromScale(1, 1)
	robuxText.TextScaled = true
	robuxText.Text = "R$"
	robuxText.Font = Enum.Font.GothamBold
end

local function ensureFrameTopBar(frame, titleText)
	local topBar = ensureFrame(frame, "TopBar")
	topBar.Size = UDim2.new(1, 0, 0, 44)
	topBar.BackgroundColor3 = UI_STYLE.PanelFillDark
	topBar.BackgroundTransparency = 0.02
	ensureUIStroke(topBar, UI_STYLE.GoldBase, 1.6).Transparency = 0.15
	ensureUIGradient(topBar, UI_STYLE.SecondaryBg, UI_STYLE.PrimaryBg)

	local title = ensureTextLabel(topBar, "Title")
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.fromOffset(12, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(title, 18, UI_STYLE.TextMain)
	title.Text = titleText

	local close = ensureTextButton(topBar, "X")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Size = UDim2.fromOffset(34, 30)
	close.Position = UDim2.new(1, -10, 0.5, 0)
	close.Text = "X"
	styleCloseButton(close)

	return topBar
end

local function ensureStandardMenuShell(frame, titleText, backgroundImage)
	frame.BackgroundColor3 = UI_STYLE.MenuOverlay
	frame.BackgroundTransparency = 0
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	ensureUICorner(frame, 18)
	local frameGradient = frame:FindFirstChildOfClass("UIGradient")
	if frameGradient then
		frameGradient.Enabled = false
	end
	local frameStroke = frame:FindFirstChildOfClass("UIStroke")
	if frameStroke then
		frameStroke.Enabled = false
	end

	local baseTexture = ensureImageLabel(frame, "BaseTexture")
	baseTexture.BackgroundTransparency = 1
	baseTexture.BorderSizePixel = 0
	baseTexture.Image = backgroundImage or UI_STYLE.MenuBackgroundImage
	baseTexture.ImageTransparency = 0
	baseTexture.ScaleType = Enum.ScaleType.Stretch
	baseTexture.Position = UDim2.fromOffset(2, 2)
	baseTexture.Size = UDim2.new(1, -4, 1, -4)
	baseTexture.ZIndex = 1
	ensureUICorner(baseTexture, 16)

	local overlay = ensureFrame(frame, "Overlay")
	overlay.BackgroundColor3 = UI_STYLE.MenuOverlay
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Position = UDim2.fromOffset(2, 2)
	overlay.Size = UDim2.new(1, -4, 1, -4)
	overlay.ZIndex = 2
	ensureUICorner(overlay, 16)

	local outerBorder = ensureFrame(frame, "OuterBorder")
	outerBorder.BackgroundTransparency = 1
	outerBorder.BorderSizePixel = 0
	outerBorder.Position = UDim2.fromOffset(2, 2)
	outerBorder.Size = UDim2.new(1, -4, 1, -4)
	outerBorder.ZIndex = 10
	ensureUICorner(outerBorder, 16)
	local outerStroke = ensureUIStroke(outerBorder, UI_STYLE.GoldHighlight, 3)
	outerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outerStroke.Transparency = 0

	local topBar = ensureFrame(frame, "TopBar")
	topBar.BackgroundColor3 = UI_STYLE.HeaderBackground
	topBar.BackgroundTransparency = 0.25
	topBar.BorderSizePixel = 0
	topBar.Position = UDim2.fromOffset(12, 10)
	topBar.Size = UDim2.new(1, -24, 0, 54)
	topBar.ZIndex = 3
	ensureUICorner(topBar, 10)
	local topBarStroke = ensureUIStroke(topBar, UI_STYLE.GoldHighlight, 1.5)
	topBarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	topBarStroke.Transparency = 0

	local title = ensureTextLabel(topBar, "Title")
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Position = UDim2.fromScale(0.5, 0.5)
	title.Size = UDim2.fromOffset(260, 32)
	title.Text = string.upper(titleText)
	title.TextColor3 = UI_STYLE.TextMain
	title.TextScaled = true
	title.TextSize = 30
	title.TextStrokeColor3 = UI_STYLE.GoldShadow
	title.TextStrokeTransparency = 0.45
	title.ZIndex = 4
	title.TextXAlignment = Enum.TextXAlignment.Center

	local close = ensureTextButton(topBar, "X")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.AutoButtonColor = false
	close.BackgroundColor3 = UI_STYLE.CloseBright
	close.BackgroundTransparency = 0
	close.BorderSizePixel = 0
	close.Position = UDim2.new(1, -8, 0.5, 0)
	close.Size = UDim2.fromOffset(34, 34)
	close.Text = "X"
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Font = Enum.Font.GothamBold
	close.TextScaled = true
	close.TextStrokeColor3 = Color3.fromRGB(9, 17, 27)
	close.TextStrokeTransparency = 0.4
	close.ZIndex = 4
	ensureUICorner(close, 8)
	local closeStroke = ensureUIStroke(close, UI_STYLE.GoldShadow, 1)
	closeStroke.Transparency = 0.1
	local closeGradient = ensureUIGradient(close, UI_STYLE.CloseBrightSoft, UI_STYLE.CloseBright)
	closeGradient.Rotation = 90
end

local function ensureGearStoreLayout(frame)
	local topBar = ensureFrameTopBar(frame, "Gear Store")
	topBar.Visible = true

	local scrollingFrame = frame:FindFirstChild("ScrollingFrame")
	if not (scrollingFrame and scrollingFrame:IsA("ScrollingFrame")) then
		if scrollingFrame then
			scrollingFrame:Destroy()
		end
		scrollingFrame = Instance.new("ScrollingFrame")
		scrollingFrame.Name = "ScrollingFrame"
		scrollingFrame.Parent = frame
	end
	scrollingFrame.BackgroundTransparency = 1
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.Position = UDim2.fromOffset(12, 52)
	scrollingFrame.Size = UDim2.new(1, -24, 1, -64)
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollingFrame.ScrollBarThickness = 8
	scrollingFrame.CanvasSize = UDim2.new()
	scrollingFrame.ScrollBarImageColor3 = UI_STYLE.GoldHighlight

	local list = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not list then
		list = Instance.new("UIListLayout")
		list.Parent = scrollingFrame
	end
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)

	local template = ensureFrame(scrollingFrame, "Template")
	template.Visible = false
	template.Size = UDim2.new(1, -6, 0, 86)
	styleInsetPanel(template, 10)

	local icon = ensureImageLabel(template, "Icon")
	icon.Size = UDim2.fromOffset(54, 54)
	icon.Position = UDim2.fromOffset(10, 16)
	styleInsetPanel(icon, 8)

	local addSpeed = ensureTextLabel(template, "AddSpeed")
	addSpeed.Size = UDim2.new(1, -320, 0, 24)
	addSpeed.Position = UDim2.fromOffset(72, 8)
	addSpeed.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(addSpeed, 17, UI_STYLE.TextMain)
	addSpeed.Text = "Gear"
	local addSpeedShadow = ensureTextLabel(addSpeed, "Shadow")
	addSpeedShadow.Size = UDim2.fromScale(1, 1)
	addSpeedShadow.Text = addSpeed.Text

	local buy = ensureTextButton(template, "Buy")
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Size = UDim2.fromOffset(118, 34)
	buy.Position = UDim2.new(1, -140, 1, -8)
	buy.Text = ""
	stylePrimaryButton(buy)
	local buyMain = ensureFrame(buy, "Main")
	buyMain.Size = UDim2.fromScale(1, 1)
	local buyText = ensureTextLabel(buyMain, "TextL")
	buyText.Size = UDim2.fromScale(1, 1)
	buyText.TextScaled = true
	buyText.Text = "Buy"
	buyText.TextColor3 = Color3.fromRGB(18, 30, 24)

	local robux = ensureTextButton(template, "Robux")
	robux.AnchorPoint = Vector2.new(1, 1)
	robux.Size = UDim2.fromOffset(118, 34)
	robux.Position = UDim2.new(1, -12, 1, -8)
	robux.Text = ""
	styleSecondaryButton(robux)
	local robuxMain = ensureFrame(robux, "Main")
	robuxMain.Size = UDim2.fromScale(1, 1)
	local robuxText = ensureTextLabel(robuxMain, "TextL")
	robuxText.Size = UDim2.fromScale(1, 1)
	robuxText.TextScaled = true
	robuxText.Text = "R$"
end

local function ensureCometMerchantLayout(frame)
	local topBar = ensureFrameTopBar(frame, "Comet Merchant")
	topBar.Visible = true

	local main = ensureFrame(frame, "Main")
	main.BackgroundTransparency = 1
	main.Position = UDim2.fromOffset(12, 52)
	main.Size = UDim2.new(1, -24, 1, -64)

	local list = main:FindFirstChildOfClass("UIListLayout")
	if not list then
		list = Instance.new("UIListLayout")
		list.Parent = main
	end
	list.FillDirection = Enum.FillDirection.Vertical
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)

	local template = ensureFrame(main, "Template")
	template.Visible = false
	template.Size = UDim2.new(1, -6, 0, 104)
	styleInsetPanel(template, 10)

	local icon = ensureImageLabel(template, "Icon")
	icon.Size = UDim2.fromOffset(52, 52)
	icon.Position = UDim2.fromOffset(10, 26)
	styleInsetPanel(icon, 8)

	local tName = ensureTextLabel(template, "TName")
	tName.Size = UDim2.new(1, -290, 0, 24)
	tName.Position = UDim2.fromOffset(70, 8)
	tName.TextXAlignment = Enum.TextXAlignment.Left
	tName.Text = "+ Offer"
	setLabelStyle(tName, 16, UI_STYLE.TextMain)
	local tNameShadow = ensureTextLabel(tName, "Shadow")
	tNameShadow.Size = UDim2.fromScale(1, 1)
	tNameShadow.Text = tName.Text

	local left = ensureTextLabel(template, "Left")
	left.Size = UDim2.new(1, -290, 0, 20)
	left.Position = UDim2.fromOffset(70, 34)
	left.TextXAlignment = Enum.TextXAlignment.Left
	left.Text = "x0 Stock"
	setLabelStyle(left, 14, UI_STYLE.TextSecondary)
	local leftShadow = ensureTextLabel(left, "Shadow")
	leftShadow.Size = UDim2.fromScale(1, 1)
	leftShadow.Text = left.Text

	local info = ensureTextLabel(template, "Info")
	info.Size = UDim2.new(1, -290, 0, 40)
	info.Position = UDim2.fromOffset(70, 56)
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.TextWrapped = true
	info.TextSize = 13
	info.Text = "Offer description"
	setLabelStyle(info, 13, UI_STYLE.TextSecondary)
	local infoShadow = ensureTextLabel(info, "Shadow")
	infoShadow.Size = UDim2.fromScale(1, 1)
	infoShadow.Text = info.Text

	local textL = ensureTextLabel(template, "TextL")
	textL.AnchorPoint = Vector2.new(1, 0)
	textL.Size = UDim2.fromOffset(120, 22)
	textL.Position = UDim2.new(1, -12, 10 / 104, 0)
	textL.Text = "0"
	textL.TextScaled = true
	setLabelStyle(textL, 16, UI_STYLE.GoldHighlight)
	local textLShadow = ensureTextLabel(textL, "Shadow")
	textLShadow.Size = UDim2.fromScale(1, 1)
	textLShadow.Text = textL.Text

	local buy = ensureTextButton(template, "Buy")
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Size = UDim2.fromOffset(128, 36)
	buy.Position = UDim2.new(1, -12, 1, -10)
	buy.Text = "Buy"
	stylePrimaryButton(buy)
end

local function ensureLimitedRewardLayout(frame)
	local topBar = ensureFrameTopBar(frame, "Limited Reward")
	topBar.Visible = true

	local main = ensureFrame(frame, "Main")
	main.BackgroundTransparency = 1
	main.Position = UDim2.fromOffset(12, 52)
	main.Size = UDim2.new(1, -24, 0, 86)

	local joinEvent = ensureTextButton(main, "JoinEvent")
	joinEvent.Size = UDim2.fromOffset(180, 42)
	joinEvent.Position = UDim2.fromOffset(0, 0)
	joinEvent.Text = "Claim"
	stylePrimaryButton(joinEvent)

	local infoFrame = ensureFrame(frame, "Frame")
	infoFrame.BackgroundTransparency = 1
	infoFrame.Position = UDim2.fromOffset(12, 148)
	infoFrame.Size = UDim2.new(1, -24, 0, 84)

	local like = ensureFrame(infoFrame, "Like")
	like.BackgroundTransparency = 1
	like.Size = UDim2.fromOffset(160, 32)
	like.Position = UDim2.fromOffset(0, 0)
	local likeText = ensureTextLabel(like, "TextL")
	likeText.Size = UDim2.fromScale(1, 1)
	likeText.Text = "0/1"
	likeText.TextXAlignment = Enum.TextXAlignment.Left

	local favorite = ensureFrame(infoFrame, "Favorite")
	favorite.BackgroundTransparency = 1
	favorite.Size = UDim2.fromOffset(160, 32)
	favorite.Position = UDim2.fromOffset(0, 36)
	local favoriteText = ensureTextLabel(favorite, "TextL")
	favoriteText.Size = UDim2.fromScale(1, 1)
	favoriteText.Text = "0/1"
	favoriteText.TextXAlignment = Enum.TextXAlignment.Left
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
	counters.Size = UDim2.fromOffset(250, 172)
	counters.Position = UDim2.fromOffset(24, 520)
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

	local inventory = ensureFrame(hud, "Inventory")
	inventory.Visible = false
	inventory.Size = UDim2.fromOffset(200, 200)
	local inventoryBtn = ensureImageButton(inventory, "InventoryBtn")
	inventoryBtn.Size = UDim2.fromOffset(64, 64)
	inventoryBtn.Image = "rbxassetid://129583821766521"
	inventoryBtn.ImageTransparency = 0
	inventoryBtn.ScaleType = Enum.ScaleType.Fit

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
	local frames = ensureScreenGui("Frames", 120)

	local frameNames = {
		"Store",
		"Index",
		"SpeedUpgrade",
		"Rebirth",
		"Quest",
		"Settings",
		"Gifts",
		"GearStore",
		"GearShop",
		"CometMerchant",
	}

	for _, frameName in ipairs(frameNames) do
		local frame = ensureFrame(frames, frameName)
		clearChildren(frame)
		frame.Visible = false
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.new(0.9, 0, 0.84, 0)
		frame.ClipsDescendants = true
		stylePanel(frame, 12)
	end

	local speedUpgrade = ensureFrame(frames, "SpeedUpgrade")
	speedUpgrade.Size = UDim2.new(0.62, 0, 0.64, 0)
	ensureFrameTopBar(speedUpgrade, "Speed Upgrades")

	local speedMain = ensureFrame(speedUpgrade, "Main")
	speedMain.BackgroundTransparency = 1
	speedMain.Position = UDim2.fromOffset(10, 52)
	speedMain.Size = UDim2.new(1, -20, 1, -62)
	local speedList = speedMain:FindFirstChildOfClass("UIListLayout")
	if not speedList then
		speedList = Instance.new("UIListLayout")
		speedList.Parent = speedMain
	end
	speedList.FillDirection = Enum.FillDirection.Vertical
	speedList.SortOrder = Enum.SortOrder.LayoutOrder
	speedList.Padding = UDim.new(0, 8)

	local speedKeys = {}
	for key in pairs(SpeedUpgradeConfig) do
		speedKeys[#speedKeys + 1] = key
	end
	table.sort(speedKeys)
	for index, key in ipairs(speedKeys) do
		ensureSpeedUpgradeCard(speedMain, key, index)
	end

	local rebirth = ensureFrame(frames, "Rebirth")
	rebirth.Size = UDim2.new(0.54, 0, 0.62, 0)
	ensureStandardMenuShell(rebirth, "Rebirth", UI_STYLE.RebirthBackgroundImage)
	local rebirthMain = ensureFrame(rebirth, "Main")
	rebirthMain.BackgroundTransparency = 1
	rebirthMain.Position = UDim2.fromOffset(18, 116)
	rebirthMain.Size = UDim2.new(1, -42, 1, -126)
	rebirthMain.ZIndex = 3

	ensureRebirthRequirement(rebirthMain, "Money", 8)
	ensureRebirthRequirement(rebirthMain, "Speed", 88)

	local youGet = ensureFrame(rebirthMain, "YouGet")
	youGet.BackgroundTransparency = 1
	youGet.Position = UDim2.fromOffset(16, 172)
	youGet.Size = UDim2.new(1, -32, 1, -228)
	youGet.ZIndex = 4
	local getList = youGet:FindFirstChildOfClass("UIListLayout")
	if not getList then
		getList = Instance.new("UIListLayout")
		getList.Parent = youGet
	end
	getList.FillDirection = Enum.FillDirection.Vertical
	getList.SortOrder = Enum.SortOrder.LayoutOrder
	getList.Padding = UDim.new(0, 6)

	local template = ensureFrame(youGet, "Template")
	template.Visible = false
	template.Size = UDim2.new(1, 0, 0, 46)
	template.LayoutOrder = 100
	styleInsetPanel(template, 8)
	template.ZIndex = 4
	local render = ensureImageLabel(template, "Render")
	render.Position = UDim2.fromOffset(8, 8)
	render.Size = UDim2.fromOffset(30, 30)
	render.ZIndex = 5
	local amount = ensureTextLabel(template, "Amount")
	amount.Position = UDim2.fromOffset(46, 0)
	amount.Size = UDim2.new(1, -54, 1, 0)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	setLabelStyle(amount, 15, UI_STYLE.TextMain)
	amount.ZIndex = 5

	local rebirthButton = ensureTextButton(rebirthMain, "Rebirth")
	rebirthButton.Size = UDim2.fromOffset(180, 38)
	rebirthButton.AnchorPoint = Vector2.new(0.5, 1)
	rebirthButton.Position = UDim2.new(0.5, 0, 1, -10)
	rebirthButton.Text = "Rebirth"
	rebirthButton.ZIndex = 5
	stylePrimaryButton(rebirthButton)

	local settings = ensureFrame(frames, "Settings")
	settings.Size = UDim2.new(0.56, 0, 0.66, 0)
	ensureFrameTopBar(settings, "Settings")

	local scrollingFrame = settings:FindFirstChild("ScrollingFrame")
	if not (scrollingFrame and scrollingFrame:IsA("ScrollingFrame")) then
		if scrollingFrame then
			scrollingFrame:Destroy()
		end
		scrollingFrame = Instance.new("ScrollingFrame")
		scrollingFrame.Name = "ScrollingFrame"
		scrollingFrame.Parent = settings
	end
	scrollingFrame.BackgroundTransparency = 1
	scrollingFrame.BorderSizePixel = 0
	scrollingFrame.Position = UDim2.fromOffset(10, 52)
	scrollingFrame.Size = UDim2.new(1, -20, 1, -62)
	scrollingFrame.CanvasSize = UDim2.new(0, 0, 0, 520)
	scrollingFrame.ScrollBarThickness = 8
	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollingFrame.ScrollBarImageColor3 = UI_STYLE.GoldHighlight

	local settingsList = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not settingsList then
		settingsList = Instance.new("UIListLayout")
		settingsList.Parent = scrollingFrame
	end
	settingsList.FillDirection = Enum.FillDirection.Vertical
	settingsList.SortOrder = Enum.SortOrder.LayoutOrder
	settingsList.Padding = UDim.new(0, 8)

	local order = 1
	for settingName, data in pairs(SettingsConfig) do
		if typeof(data) == "table" and data.Type == "Slider" then
			ensureSettingsSliderOption(scrollingFrame, settingName, order)
			order += 1
		end
	end
	for settingName, data in pairs(SettingsConfig) do
		if typeof(data) == "table" and data.Type == "Switch" then
			ensureSettingsSwitchOption(scrollingFrame, settingName, order)
			order += 1
		end
	end

	local gifts = ensureFrame(frames, "Gifts")
	gifts.Size = UDim2.new(0.5, 0, 0.66, 0)
	ensureStandardMenuShell(gifts, "Gifts", UI_STYLE.GiftsBackgroundImage)
	local giftsMain = ensureFrame(gifts, "Main")
	ensureGiftsSlots(giftsMain)

	local gearStore = ensureFrame(frames, "GearStore")
	gearStore.Size = UDim2.new(0.62, 0, 0.72, 0)
	ensureGearStoreLayout(gearStore)

	local cometMerchant = ensureFrame(frames, "CometMerchant")
	cometMerchant.Size = UDim2.new(0.62, 0, 0.72, 0)
	ensureCometMerchantLayout(cometMerchant)

	local limitedReward = ensureFrame(frames, "LimitedReward")
	clearChildren(limitedReward)
	limitedReward.Visible = false
	limitedReward.AnchorPoint = Vector2.new(0.5, 0.5)
	limitedReward.Position = UDim2.fromScale(0.5, 0.5)
	limitedReward.Size = UDim2.new(0.5, 0, 0.46, 0)
	limitedReward.ClipsDescendants = true
	stylePanel(limitedReward, 12)
	ensureLimitedRewardLayout(limitedReward)
end

ensureHud()
ensureFrames()

