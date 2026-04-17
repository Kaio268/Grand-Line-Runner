local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local EatAnimationClient = require(modules:WaitForChild("DevilFruits"):WaitForChild("EatAnimationClient"))
local promptRemote = remotes:WaitForChild("DevilFruitConsumePrompt")
local responseRemote = remotes:WaitForChild("DevilFruitConsumeResponse")

local screenGui
local dimmer
local panel
local titleLabel
local bodyLabel
local confirmButton
local cancelButton
local confirmButtonLabel
local cancelButtonLabel
local pendingPayload

local UI_THEME = {
	PrimaryBg = Color3.fromRGB(30, 42, 56),
	SecondaryBg = Color3.fromRGB(36, 52, 71),
	PanelFill = Color3.fromRGB(44, 62, 80),
	MenuOverlay = Color3.fromRGB(15, 27, 42),
	HeaderBackground = Color3.fromRGB(16, 35, 59),
	SectionBackground = Color3.fromRGB(27, 46, 68),
	SectionHover = Color3.fromRGB(46, 74, 99),
	GoldBase = Color3.fromRGB(212, 175, 55),
	GoldHighlight = Color3.fromRGB(242, 209, 107),
	GoldShadow = Color3.fromRGB(140, 107, 31),
	TextMain = Color3.fromRGB(230, 230, 230),
	TextSecondary = Color3.fromRGB(184, 193, 204),
	FruitBackgroundImage = "rbxassetid://134053886107384",
}

local BUTTON_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function shouldRequireReplaceWarning(currentFruitName, nextFruitKey)
	local currentName = tostring(currentFruitName or "")
	if currentName == "" or currentName == "None" or currentName == DevilFruitConfig.None then
		return false
	end

	local resolvedCurrent = DevilFruitConfig.ResolveFruitName(currentName)
	local resolvedNext = DevilFruitConfig.ResolveFruitName(nextFruitKey)
	if resolvedCurrent ~= nil and resolvedNext ~= nil and resolvedCurrent == resolvedNext then
		return false
	end

	return resolvedCurrent ~= nil
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

local function bindThemedButton(button, style)
	local isHovering = false
	local hoverScale = tonumber(style and style.hoverScale) or 1.01
	local clickScale = tonumber(style and style.clickScale) or 0.99
	local uiScale = button:FindFirstChild("PromptButtonScale")
	if not (uiScale and uiScale:IsA("UIScale")) then
		uiScale = Instance.new("UIScale")
		uiScale.Name = "PromptButtonScale"
		uiScale.Scale = 1
		uiScale.Parent = button
	end

	local function applyVisual(isHovered)
		local fill = isHovered and style.hoverFill or style.fill
		local text = isHovered and style.hoverText or style.text
		local gradientTop = isHovered and style.hoverTop or style.top
		local gradientBottom = isHovered and style.hoverBottom or style.bottom
		local transparency = if isHovered
			then (tonumber(style and style.hoverTransparency) or tonumber(style and style.transparency) or 0)
			else (tonumber(style and style.transparency) or 0)

		button.BackgroundColor3 = fill
		button.BackgroundTransparency = transparency
		local label = button:FindFirstChild("Label")
		if label and label:IsA("TextLabel") then
			label.TextColor3 = text
		else
			button.TextColor3 = text
		end
		ensureGradient(button, gradientTop, gradientBottom)
	end

	button.MouseEnter:Connect(function()
		isHovering = true
		applyVisual(true)
		TweenService:Create(uiScale, BUTTON_TWEEN, { Scale = hoverScale }):Play()
	end)

	button.MouseLeave:Connect(function()
		isHovering = false
		applyVisual(false)
		TweenService:Create(uiScale, BUTTON_TWEEN, { Scale = 1 }):Play()
	end)

	button.MouseButton1Down:Connect(function()
		TweenService:Create(uiScale, BUTTON_TWEEN, { Scale = clickScale }):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(uiScale, BUTTON_TWEEN, { Scale = if isHovering then hoverScale else 1 }):Play()
	end)

	applyVisual(false)
end

local function setPromptVisible(isVisible)
	if not screenGui then
		return
	end

	screenGui.Enabled = isVisible
	if dimmer then
		dimmer.Visible = isVisible
	end
	if panel then
		panel.Visible = isVisible
	end
end

local function isPromptGuiValid(gui)
	if not (gui and gui:IsA("ScreenGui")) then
		return false
	end

	local guiDimmer = gui:FindFirstChild("Dimmer")
	local guiPanel = gui:FindFirstChild("Panel")
	if not (guiDimmer and guiDimmer:IsA("Frame") and guiPanel and guiPanel:IsA("Frame")) then
		return false
	end

	local topBar = guiPanel:FindFirstChild("TopBar")
	local content = guiPanel:FindFirstChild("Content")
	local bodyCard = content and content:FindFirstChild("BodyCard")
	local buttonRow = content and content:FindFirstChild("ButtonRow")
	local confirm = buttonRow and buttonRow:FindFirstChild("Confirm")
	local cancel = buttonRow and buttonRow:FindFirstChild("Cancel")
	local confirmLabel = confirm and confirm:FindFirstChild("Label")
	local cancelLabel = cancel and cancel:FindFirstChild("Label")

	return topBar ~= nil
		and content ~= nil
		and bodyCard ~= nil
		and buttonRow ~= nil
		and confirm ~= nil
		and cancel ~= nil
		and confirmLabel ~= nil
		and cancelLabel ~= nil
end

local function playEatAnimation(fruitKey)
	EatAnimationClient.Play(player, fruitKey)
end

local function ensurePromptGui()
	if screenGui and screenGui.Parent and isPromptGuiValid(screenGui) then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
	local existingGui = playerGui:FindFirstChild("DevilFruitConsumePrompt")
	if existingGui and existingGui ~= screenGui then
		existingGui:Destroy()
	end
	if screenGui and screenGui.Parent then
		screenGui:Destroy()
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DevilFruitConsumePrompt"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 120
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	dimmer = Instance.new("Frame")
	dimmer.Name = "Dimmer"
	dimmer.BackgroundColor3 = UI_THEME.MenuOverlay
	dimmer.BackgroundTransparency = 0.4
	dimmer.BorderSizePixel = 0
	dimmer.Size = UDim2.fromScale(1, 1)
	dimmer.ZIndex = 60
	dimmer.Parent = screenGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(620, 360)
	panel.BackgroundColor3 = UI_THEME.PrimaryBg
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.ClipsDescendants = true
	panel.Visible = false
	panel.ZIndex = 80
	panel.Parent = screenGui

	ensureCorner(panel, 16)
	ensureStroke(panel, UI_THEME.GoldHighlight, 0, 2.2)

	local bgImage = Instance.new("ImageLabel")
	bgImage.Name = "BackgroundImage"
	bgImage.BackgroundTransparency = 1
	bgImage.BorderSizePixel = 0
	bgImage.Image = UI_THEME.FruitBackgroundImage
	bgImage.ScaleType = Enum.ScaleType.Stretch
	bgImage.Size = UDim2.fromScale(1, 1)
	bgImage.ZIndex = 79
	bgImage.Parent = panel
	ensureCorner(bgImage, 16)

	local imageOverlay = Instance.new("Frame")
	imageOverlay.Name = "BackgroundOverlay"
	imageOverlay.BackgroundColor3 = UI_THEME.MenuOverlay
	imageOverlay.BackgroundTransparency = 0.45
	imageOverlay.BorderSizePixel = 0
	imageOverlay.Size = UDim2.fromScale(1, 1)
	imageOverlay.ZIndex = 79
	imageOverlay.Parent = panel
	ensureCorner(imageOverlay, 16)

	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.BackgroundColor3 = UI_THEME.HeaderBackground
	topBar.BackgroundTransparency = 0.25
	topBar.BorderSizePixel = 0
	topBar.Position = UDim2.fromOffset(14, 12)
	topBar.Size = UDim2.new(1, -28, 0, 88)
	topBar.ZIndex = 81
	topBar.Parent = panel
	ensureCorner(topBar, 10)
	ensureStroke(topBar, UI_THEME.GoldHighlight, 0, 1.4)
	ensureGradient(topBar, UI_THEME.SecondaryBg, UI_THEME.PrimaryBg)

	local accentLabel = Instance.new("TextLabel")
	accentLabel.Name = "Accent"
	accentLabel.BackgroundTransparency = 1
	accentLabel.Position = UDim2.fromOffset(16, 8)
	accentLabel.Size = UDim2.new(1, -32, 0, 20)
	accentLabel.Font = Enum.Font.GothamBold
	accentLabel.Text = "DEVIL FRUIT"
	accentLabel.TextColor3 = UI_THEME.GoldHighlight
	accentLabel.TextSize = 16
	accentLabel.TextXAlignment = Enum.TextXAlignment.Left
	accentLabel.ZIndex = 82
	accentLabel.Parent = topBar

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(16, 30)
	titleLabel.Size = UDim2.new(1, -32, 0, 48)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Eat Devil Fruit"
	titleLabel.TextColor3 = UI_THEME.TextMain
	titleLabel.TextSize = 22
	titleLabel.TextScaled = false
	titleLabel.TextWrapped = false
	titleLabel.TextTruncate = Enum.TextTruncate.AtEnd
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.ZIndex = 82
	titleLabel.Parent = topBar

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(20, 114)
	content.Size = UDim2.new(1, -40, 1, -136)
	content.ZIndex = 81
	content.Parent = panel

	local bodyCard = Instance.new("Frame")
	bodyCard.Name = "BodyCard"
	bodyCard.BackgroundColor3 = UI_THEME.SectionBackground
	bodyCard.BackgroundTransparency = 0.22
	bodyCard.BorderSizePixel = 0
	bodyCard.Position = UDim2.fromOffset(0, 0)
	bodyCard.Size = UDim2.new(1, 0, 1, -64)
	bodyCard.ZIndex = 81
	bodyCard.Parent = content
	ensureCorner(bodyCard, 12)
	ensureStroke(bodyCard, UI_THEME.GoldHighlight, 0, 1.2)
	ensureGradient(bodyCard, UI_THEME.SecondaryBg, UI_THEME.PrimaryBg)

	local bodyPadding = Instance.new("UIPadding")
	bodyPadding.PaddingTop = UDim.new(0, 14)
	bodyPadding.PaddingBottom = UDim.new(0, 14)
	bodyPadding.PaddingLeft = UDim.new(0, 16)
	bodyPadding.PaddingRight = UDim.new(0, 16)
	bodyPadding.Parent = bodyCard

	bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Position = UDim2.fromOffset(0, 0)
	bodyLabel.Size = UDim2.fromScale(1, 1)
	bodyLabel.Font = Enum.Font.GothamBold
	bodyLabel.Text = ""
	bodyLabel.TextColor3 = UI_THEME.TextSecondary
	bodyLabel.TextSize = 24
	bodyLabel.TextScaled = false
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.ZIndex = 82
	bodyLabel.Parent = bodyCard

	local buttonRow = Instance.new("Frame")
	buttonRow.Name = "ButtonRow"
	buttonRow.BackgroundTransparency = 1
	buttonRow.AnchorPoint = Vector2.new(0.5, 1)
	buttonRow.Position = UDim2.new(0.5, 0, 1, 0)
	buttonRow.Size = UDim2.new(1, 0, 0, 48)
	buttonRow.ZIndex = 82
	buttonRow.Parent = content

	confirmButton = Instance.new("TextButton")
	confirmButton.Name = "Confirm"
	confirmButton.AnchorPoint = Vector2.new(0, 0.5)
	confirmButton.Position = UDim2.new(0, 0, 0.5, 0)
	confirmButton.Size = UDim2.new(0.5, -14, 0, 46)
	confirmButton.BackgroundColor3 = UI_THEME.GoldBase
	confirmButton.BorderSizePixel = 0
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.Text = ""
	confirmButton.TextColor3 = UI_THEME.PrimaryBg
	confirmButton.TextSize = 22
	confirmButton.TextScaled = false
	confirmButton.AutoButtonColor = false
	confirmButton.ZIndex = 82
	confirmButton.Parent = buttonRow

	confirmButtonLabel = Instance.new("TextLabel")
	confirmButtonLabel.Name = "Label"
	confirmButtonLabel.BackgroundTransparency = 1
	confirmButtonLabel.Size = UDim2.fromScale(1, 1)
	confirmButtonLabel.Font = Enum.Font.GothamBold
	confirmButtonLabel.Text = "Eat"
	confirmButtonLabel.TextColor3 = UI_THEME.PrimaryBg
	confirmButtonLabel.TextSize = 22
	confirmButtonLabel.ZIndex = 84
	confirmButtonLabel.Parent = confirmButton

	ensureCorner(confirmButton, 10)
	local confirmStroke = ensureStroke(confirmButton, UI_THEME.GoldHighlight, 0.08, 1.2)
	confirmStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bindThemedButton(confirmButton, {
		fill = UI_THEME.GoldBase,
		text = UI_THEME.PrimaryBg,
		top = UI_THEME.GoldHighlight,
		bottom = UI_THEME.GoldBase,
		hoverFill = UI_THEME.GoldHighlight,
		hoverText = UI_THEME.PrimaryBg,
		hoverTop = UI_THEME.GoldHighlight,
		hoverBottom = UI_THEME.GoldBase,
		transparency = 0.12,
		hoverTransparency = 0.12,
		hoverScale = 1.0,
		clickScale = 0.99,
	})

	cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.AnchorPoint = Vector2.new(1, 0.5)
	cancelButton.Position = UDim2.new(1, 0, 0.5, 0)
	cancelButton.Size = UDim2.new(0.5, -14, 0, 46)
	cancelButton.BackgroundColor3 = UI_THEME.SectionBackground
	cancelButton.BorderSizePixel = 0
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.Text = ""
	cancelButton.TextColor3 = UI_THEME.TextMain
	cancelButton.TextSize = 22
	cancelButton.TextScaled = false
	cancelButton.AutoButtonColor = false
	cancelButton.ZIndex = 82
	cancelButton.Parent = buttonRow

	cancelButtonLabel = Instance.new("TextLabel")
	cancelButtonLabel.Name = "Label"
	cancelButtonLabel.BackgroundTransparency = 1
	cancelButtonLabel.Size = UDim2.fromScale(1, 1)
	cancelButtonLabel.Font = Enum.Font.GothamBold
	cancelButtonLabel.Text = "Cancel"
	cancelButtonLabel.TextColor3 = UI_THEME.TextMain
	cancelButtonLabel.TextSize = 22
	cancelButtonLabel.ZIndex = 84
	cancelButtonLabel.Parent = cancelButton

	ensureCorner(cancelButton, 10)
	local cancelStroke = ensureStroke(cancelButton, UI_THEME.GoldHighlight, 0.08, 1.2)
	cancelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bindThemedButton(cancelButton, {
		fill = UI_THEME.SectionBackground,
		text = UI_THEME.TextMain,
		top = UI_THEME.SecondaryBg,
		bottom = UI_THEME.PrimaryBg,
		hoverFill = Color3.fromRGB(200, 0, 9),
		hoverText = Color3.fromRGB(255, 241, 230),
		hoverTop = Color3.fromRGB(216, 34, 44),
		hoverBottom = Color3.fromRGB(147, 0, 0),
		transparency = 0.12,
		hoverTransparency = 0.12,
		hoverScale = 1.0,
		clickScale = 0.99,
	})

	cancelButton.MouseButton1Click:Connect(function()
		setPromptVisible(false)
		if pendingPayload then
			responseRemote:FireServer(false, pendingPayload.FruitKey)
		end
		pendingPayload = nil
	end)

	confirmButton.MouseButton1Click:Connect(function()
		if not pendingPayload then
			return
		end

		if pendingPayload.Step == 1 and pendingPayload.RequiresReplaceWarning then
			pendingPayload.Step = 2
			bodyLabel.Text = string.format("This will replace your %s.", pendingPayload.CurrentFruitName)
			if confirmButtonLabel then
				confirmButtonLabel.Text = "Replace"
			end
			if cancelButtonLabel then
				cancelButtonLabel.Text = "Cancel"
			end
			return
		end

		setPromptVisible(false)
		local confirmedPayload = pendingPayload
		pendingPayload = nil

		playEatAnimation(confirmedPayload.FruitKey)
		responseRemote:FireServer(true, confirmedPayload.FruitKey)
	end)
end

promptRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	ensurePromptGui()
	if payload.Hide == true or payload.Show == false then
		pendingPayload = nil
		setPromptVisible(false)
		return
	end

	local currentFruitName = tostring(payload.CurrentFruitName or "")
	local nextFruitKey = tostring(payload.FruitKey or "")
	pendingPayload = {
		FruitKey = payload.FruitKey,
		CurrentFruitName = currentFruitName,
		RequiresReplaceWarning = shouldRequireReplaceWarning(currentFruitName, nextFruitKey),
		Step = 1,
	}

	titleLabel.Text = tostring(payload.FruitName or payload.FruitKey or "Devil Fruit")
	bodyLabel.Text = "Are you sure you want to eat this fruit?"
	if confirmButtonLabel then
		confirmButtonLabel.Text = "Eat"
	end
	if cancelButtonLabel then
		cancelButtonLabel.Text = "Cancel"
	end
	setPromptVisible(true)
end)
