local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SettingsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Settings"))
local SpeedUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SpeedUpgrade"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUD_BUTTON_LAYOUT = {
	Store = UDim2.fromOffset(0, 0),
	Index = UDim2.fromOffset(90, 0),
	Gifts = UDim2.fromOffset(0, 90),
	Settings = UDim2.fromOffset(90, 90),
	Rebirth = UDim2.fromOffset(0, 180),
}

local function ensureScreenGui(name, displayOrder)
	local existing = playerGui:FindFirstChild(name)
	if existing and existing:IsA("ScreenGui") then
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
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = displayOrder
	screenGui.Parent = playerGui
	return screenGui
end

local function ensureFrame(parent, name)
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

local function ensureTextLabel(parent, name)
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

local function ensureImageLabel(parent, name)
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

local function ensureImageButton(parent, name)
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

local function ensureTextButton(parent, name)
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
	host.Text = string.format("0 %s", name == "Money" and "$" or name)
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
	local button = ensureImageButton(lButtons, name)
	button.Size = UDim2.fromOffset(84, 84)
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

	local timer = ensureTextLabel(button, "Timer")
	timer.Visible = showTimer == true
	timer.Text = "--"
	timer.Size = UDim2.fromOffset(72, 20)
	timer.Position = UDim2.new(0.5, -36, 1, -24)
	timer.TextScaled = true
	local timer2 = ensureTextLabel(timer, "Timer2")
	timer2.Visible = true
	timer2.Text = "--"
	timer2.Size = UDim2.fromScale(1, 1)

	return button
end

local function ensureSlotCard(slot, layoutOrder)
	slot.BackgroundColor3 = Color3.fromRGB(20, 28, 45)
	slot.BackgroundTransparency = 0.15
	slot.BorderSizePixel = 0
	slot.AutoButtonColor = true
	slot.Size = UDim2.new(1, -12, 0, 84)
	slot.LayoutOrder = layoutOrder
	ensureUICorner(slot, 12)
	ensureUIStroke(slot, Color3.fromRGB(77, 104, 142), 1)

	local rewName = ensureTextLabel(slot, "RewName")
	rewName.Size = UDim2.new(1, -76, 0, 22)
	rewName.Position = UDim2.fromOffset(62, 6)
	rewName.TextXAlignment = Enum.TextXAlignment.Left
	rewName.TextSize = 16

	local timer = ensureTextLabel(slot, "Timer")
	timer.Size = UDim2.new(1, -76, 0, 22)
	timer.Position = UDim2.fromOffset(62, 34)
	timer.TextXAlignment = Enum.TextXAlignment.Left
	timer.TextSize = 15

	local icon = ensureImageLabel(slot, "Icon")
	icon.Size = UDim2.fromOffset(46, 46)
	icon.Position = UDim2.fromOffset(8, 19)
	icon.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
	icon.BackgroundTransparency = 0.2
	ensureUICorner(icon, 8)
end

local function ensureGiftsSlots(giftsMain)
	giftsMain.BackgroundTransparency = 1
	giftsMain.Size = UDim2.new(1, -26, 1, -66)
	giftsMain.Position = UDim2.fromOffset(13, 54)

	local list = giftsMain:FindFirstChildOfClass("UIListLayout")
	if not list then
		list = Instance.new("UIListLayout")
		list.Parent = giftsMain
	end
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)

	for index = 1, 5 do
		local slot = ensureTextButton(giftsMain, "Slot" .. tostring(index))
		slot.Visible = true
		ensureSlotCard(slot, index)
	end
end

local function ensureRebirthRequirement(parent, name, yOffset)
	local section = ensureFrame(parent, name)
	section.BackgroundColor3 = Color3.fromRGB(19, 26, 40)
	section.BackgroundTransparency = 0.2
	section.Size = UDim2.new(1, -32, 0, 72)
	section.Position = UDim2.fromOffset(16, yOffset)
	ensureUICorner(section, 10)
	ensureUIStroke(section, Color3.fromRGB(74, 96, 132), 1)

	local label = ensureTextLabel(section, "Label")
	label.Size = UDim2.new(1, -20, 0, 20)
	label.Position = UDim2.fromOffset(10, 8)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextSize = 15
	label.Text = name == "Money" and "Doubloons" or "Ship Level"

	local value = ensureTextLabel(section, "Value")
	value.Size = UDim2.new(1, -20, 0, 22)
	value.Position = UDim2.fromOffset(10, 28)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextSize = 16

	local track = ensureFrame(section, "Track")
	track.BackgroundColor3 = Color3.fromRGB(10, 14, 23)
	track.BackgroundTransparency = 0.15
	track.Size = UDim2.new(1, -20, 0, 10)
	track.Position = UDim2.fromOffset(10, 56)
	ensureUICorner(track, 999)

	local bar = ensureFrame(section, "Bar")
	bar.BackgroundColor3 = Color3.fromRGB(102, 220, 146)
	bar.BackgroundTransparency = 0
	bar.Size = UDim2.new(0.3, -20, 0, 10)
	bar.Position = UDim2.fromOffset(10, 56)
	ensureUICorner(bar, 999)

	return section
end

local function ensureSettingsSliderOption(scrollingFrame, optionName, layoutOrder)
	local option = ensureFrame(scrollingFrame, optionName)
	option.Size = UDim2.new(1, -18, 0, 88)
	option.LayoutOrder = layoutOrder
	option.BackgroundColor3 = Color3.fromRGB(21, 29, 44)
	option.BackgroundTransparency = 0.15
	ensureUICorner(option, 10)
	ensureUIStroke(option, Color3.fromRGB(74, 99, 142), 1)

	local title = ensureTextLabel(option, "Title")
	title.Size = UDim2.new(1, -20, 0, 22)
	title.Position = UDim2.fromOffset(10, 8)
	title.Text = optionName
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 16

	local slider = ensureFrame(option, "Slider")
	slider.Size = UDim2.new(1, -64, 0, 42)
	slider.Position = UDim2.fromOffset(32, 38)
	slider.BackgroundColor3 = Color3.fromRGB(9, 14, 24)
	slider.BackgroundTransparency = 0.08
	ensureUICorner(slider, 10)
	ensureUIStroke(slider, Color3.fromRGB(58, 78, 111), 1)

	local main = ensureTextButton(slider, "Main")
	main.Size = UDim2.fromOffset(34, 34)
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.new(0.47, 0, 0.5, 0)
	main.Text = ""

	local mainFrame = ensureFrame(main, "Frame")
	mainFrame.Size = UDim2.fromScale(1, 1)
	mainFrame.BackgroundColor3 = Color3.fromRGB(255, 183, 90)
	mainFrame.BackgroundTransparency = 0
	ensureUICorner(mainFrame, 999)
	ensureUIGradient(mainFrame, Color3.fromRGB(255, 208, 129), Color3.fromRGB(255, 144, 72))
	ensureUIStroke(mainFrame, Color3.fromRGB(255, 240, 204), 1)

	local bg = ensureFrame(mainFrame, "BG")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundTransparency = 1
	local bgFrame = ensureFrame(bg, "Frame")
	bgFrame.Size = UDim2.fromScale(1, 1)
	bgFrame.BackgroundTransparency = 1
	ensureUIGradient(bgFrame, Color3.fromRGB(255, 200, 112), Color3.fromRGB(255, 126, 59))
	local bgMain = ensureFrame(bg, "Main")
	bgMain.Size = UDim2.fromScale(1, 1)
	bgMain.BackgroundTransparency = 1
	ensureUIGradient(bgMain, Color3.fromRGB(255, 220, 154), Color3.fromRGB(255, 142, 82))

	local bh = ensureFrame(mainFrame, "BH")
	bh.Size = UDim2.fromScale(1, 1)
	bh.BackgroundTransparency = 1
	local bhFrame = ensureFrame(bh, "Frame")
	bhFrame.Size = UDim2.fromScale(1, 1)
	bhFrame.BackgroundTransparency = 1
	ensureUIGradient(bhFrame, Color3.fromRGB(255, 206, 140), Color3.fromRGB(255, 154, 88))

	local textLabel = ensureTextLabel(mainFrame, "TextLabel")
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Text = "100"
	textLabel.TextScaled = true
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ensureUIGradient(textLabel, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255))
	ensureUIStroke(textLabel, Color3.fromRGB(0, 0, 0), 1)
end

local function ensureSettingsSwitchOption(scrollingFrame, optionName, layoutOrder)
	local option = ensureFrame(scrollingFrame, optionName)
	option.Size = UDim2.new(1, -18, 0, 76)
	option.LayoutOrder = layoutOrder
	option.BackgroundColor3 = Color3.fromRGB(21, 29, 44)
	option.BackgroundTransparency = 0.15
	ensureUICorner(option, 10)
	ensureUIStroke(option, Color3.fromRGB(74, 99, 142), 1)

	local title = ensureTextLabel(option, "Title")
	title.Size = UDim2.new(1, -132, 0, 24)
	title.Position = UDim2.fromOffset(10, 26)
	title.Text = optionName
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 16

	local on = ensureTextButton(option, "ON")
	on.Size = UDim2.fromOffset(92, 34)
	on.Position = UDim2.new(1, -102, 0.5, -17)
	on.BackgroundColor3 = Color3.fromRGB(82, 204, 131)
	on.BackgroundTransparency = 0
	on.Text = "ON"
	on.TextColor3 = Color3.fromRGB(9, 20, 16)
	on.Font = Enum.Font.GothamBlack
	on.TextSize = 16
	ensureUICorner(on, 8)

	local off = ensureTextButton(option, "OFF")
	off.Size = on.Size
	off.Position = on.Position
	off.BackgroundColor3 = Color3.fromRGB(200, 85, 85)
	off.BackgroundTransparency = 0
	off.Text = "OFF"
	off.TextColor3 = Color3.fromRGB(255, 239, 239)
	off.Font = Enum.Font.GothamBlack
	off.TextSize = 16
	off.Visible = false
	ensureUICorner(off, 8)
end

local function ensureSpeedUpgradeCard(main, index, layoutOrder)
	local card = ensureFrame(main, tostring(index))
	card.Size = UDim2.new(1, -20, 0, 112)
	card.LayoutOrder = layoutOrder
	card.BackgroundColor3 = Color3.fromRGB(16, 26, 45)
	card.BackgroundTransparency = 0.05
	ensureUICorner(card, 12)
	ensureUIStroke(card, Color3.fromRGB(78, 125, 198), 1.2)
	ensureUIGradient(card, Color3.fromRGB(21, 35, 61), Color3.fromRGB(11, 21, 40))

	local template = ensureFrame(card, "Template")
	template.Size = UDim2.fromScale(1, 1)
	template.BackgroundTransparency = 1

	local addSpeed = ensureTextLabel(template, "AddSpeed")
	addSpeed.Size = UDim2.new(1, -320, 0, 30)
	addSpeed.Position = UDim2.fromOffset(12, 8)
	addSpeed.TextXAlignment = Enum.TextXAlignment.Left
	addSpeed.TextSize = 24
	addSpeed.Font = Enum.Font.GothamBlack
	addSpeed.TextColor3 = Color3.fromRGB(255, 255, 255)

	local now = ensureTextLabel(template, "Now")
	now.Size = UDim2.fromOffset(260, 22)
	now.Position = UDim2.fromOffset(12, 44)
	now.TextXAlignment = Enum.TextXAlignment.Left
	now.TextSize = 16
	now.Text = "Current: 0"
	now.TextColor3 = Color3.fromRGB(202, 226, 255)

	local after = ensureTextLabel(template, "After")
	after.Size = UDim2.fromOffset(260, 22)
	after.Position = UDim2.fromOffset(12, 70)
	after.TextXAlignment = Enum.TextXAlignment.Left
	after.TextSize = 16
	after.Text = "After: 0"
	after.TextColor3 = Color3.fromRGB(183, 255, 211)

	local buy = ensureTextButton(template, "Buy")
	buy.AnchorPoint = Vector2.new(1, 0.5)
	buy.Size = UDim2.fromOffset(132, 40)
	buy.Position = UDim2.new(1, -146, 0.5, 16)
	buy.BackgroundColor3 = Color3.fromRGB(94, 220, 146)
	buy.BackgroundTransparency = 0
	buy.Text = ""
	ensureUICorner(buy, 8)
	ensureUIGradient(buy, Color3.fromRGB(131, 241, 169), Color3.fromRGB(73, 190, 124))
	ensureUIStroke(buy, Color3.fromRGB(202, 255, 219), 1)
	local buyMain = ensureFrame(buy, "Main")
	buyMain.Size = UDim2.fromScale(1, 1)
	buyMain.BackgroundTransparency = 1
	local buyText = ensureTextLabel(buyMain, "TextL")
	buyText.Size = UDim2.fromScale(1, 1)
	buyText.TextScaled = true
	buyText.Text = "Buy"
	buyText.TextColor3 = Color3.fromRGB(7, 33, 18)
	buyText.Font = Enum.Font.GothamBlack

	local robux = ensureTextButton(template, "Robux")
	robux.AnchorPoint = Vector2.new(1, 0.5)
	robux.Size = UDim2.fromOffset(132, 40)
	robux.Position = UDim2.new(1, -12, 0.5, 16)
	robux.BackgroundColor3 = Color3.fromRGB(70, 116, 214)
	robux.BackgroundTransparency = 0
	robux.Text = ""
	ensureUICorner(robux, 8)
	ensureUIGradient(robux, Color3.fromRGB(106, 152, 255), Color3.fromRGB(70, 110, 210))
	ensureUIStroke(robux, Color3.fromRGB(197, 219, 255), 1)
	local robuxMain = ensureFrame(robux, "Main")
	robuxMain.Size = UDim2.fromScale(1, 1)
	robuxMain.BackgroundTransparency = 1
	local robuxText = ensureTextLabel(robuxMain, "TextL")
	robuxText.Size = UDim2.fromScale(1, 1)
	robuxText.TextScaled = true
	robuxText.Text = "R$"
	robuxText.Font = Enum.Font.GothamBlack
end

local function ensureFrameTopBar(frame, titleText)
	local topBar = ensureFrame(frame, "TopBar")
	topBar.Size = UDim2.new(1, 0, 0, 44)
	topBar.BackgroundColor3 = Color3.fromRGB(10, 17, 32)
	topBar.BackgroundTransparency = 0.02
	ensureUIStroke(topBar, Color3.fromRGB(56, 74, 104), 1)
	ensureUIGradient(topBar, Color3.fromRGB(13, 28, 58), Color3.fromRGB(8, 16, 34))

	local title = ensureTextLabel(topBar, "Title")
	title.Size = UDim2.new(1, -60, 1, 0)
	title.Position = UDim2.fromOffset(12, 0)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextSize = 18
	title.Text = titleText

	local close = ensureTextButton(topBar, "X")
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Size = UDim2.fromOffset(34, 30)
	close.Position = UDim2.new(1, -10, 0.5, 0)
	close.BackgroundColor3 = Color3.fromRGB(160, 74, 88)
	close.BackgroundTransparency = 0
	close.Text = "X"
	close.TextColor3 = Color3.fromRGB(255, 240, 240)
	close.Font = Enum.Font.GothamBlack
	close.TextSize = 16
	ensureUICorner(close, 8)

	return topBar
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
	template.BackgroundColor3 = Color3.fromRGB(19, 28, 45)
	template.BackgroundTransparency = 0.1
	ensureUICorner(template, 10)
	ensureUIStroke(template, Color3.fromRGB(66, 92, 137), 1)

	local icon = ensureImageLabel(template, "Icon")
	icon.Size = UDim2.fromOffset(54, 54)
	icon.Position = UDim2.fromOffset(10, 16)
	icon.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
	icon.BackgroundTransparency = 0.15
	ensureUICorner(icon, 8)

	local addSpeed = ensureTextLabel(template, "AddSpeed")
	addSpeed.Size = UDim2.new(1, -320, 0, 24)
	addSpeed.Position = UDim2.fromOffset(72, 8)
	addSpeed.TextXAlignment = Enum.TextXAlignment.Left
	addSpeed.TextSize = 17
	addSpeed.Text = "Gear"
	local addSpeedShadow = ensureTextLabel(addSpeed, "Shadow")
	addSpeedShadow.Size = UDim2.fromScale(1, 1)
	addSpeedShadow.Text = addSpeed.Text

	local buy = ensureTextButton(template, "Buy")
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Size = UDim2.fromOffset(118, 34)
	buy.Position = UDim2.new(1, -140, 1, -8)
	buy.BackgroundColor3 = Color3.fromRGB(94, 210, 132)
	buy.BackgroundTransparency = 0
	buy.Text = ""
	ensureUICorner(buy, 8)
	local buyMain = ensureFrame(buy, "Main")
	buyMain.Size = UDim2.fromScale(1, 1)
	local buyText = ensureTextLabel(buyMain, "TextL")
	buyText.Size = UDim2.fromScale(1, 1)
	buyText.TextScaled = true
	buyText.Text = "Buy"
	buyText.TextColor3 = Color3.fromRGB(10, 24, 16)

	local robux = ensureTextButton(template, "Robux")
	robux.AnchorPoint = Vector2.new(1, 1)
	robux.Size = UDim2.fromOffset(118, 34)
	robux.Position = UDim2.new(1, -12, 1, -8)
	robux.BackgroundColor3 = Color3.fromRGB(70, 116, 214)
	robux.BackgroundTransparency = 0
	robux.Text = ""
	ensureUICorner(robux, 8)
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
	template.BackgroundColor3 = Color3.fromRGB(20, 29, 46)
	template.BackgroundTransparency = 0.1
	ensureUICorner(template, 10)
	ensureUIStroke(template, Color3.fromRGB(66, 92, 137), 1)

	local icon = ensureImageLabel(template, "Icon")
	icon.Size = UDim2.fromOffset(52, 52)
	icon.Position = UDim2.fromOffset(10, 26)
	icon.BackgroundColor3 = Color3.fromRGB(10, 14, 24)
	icon.BackgroundTransparency = 0.15
	ensureUICorner(icon, 8)

	local tName = ensureTextLabel(template, "TName")
	tName.Size = UDim2.new(1, -290, 0, 24)
	tName.Position = UDim2.fromOffset(70, 8)
	tName.TextXAlignment = Enum.TextXAlignment.Left
	tName.Text = "+ Offer"
	local tNameShadow = ensureTextLabel(tName, "Shadow")
	tNameShadow.Size = UDim2.fromScale(1, 1)
	tNameShadow.Text = tName.Text

	local left = ensureTextLabel(template, "Left")
	left.Size = UDim2.new(1, -290, 0, 20)
	left.Position = UDim2.fromOffset(70, 34)
	left.TextXAlignment = Enum.TextXAlignment.Left
	left.Text = "x0 Stock"
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
	local infoShadow = ensureTextLabel(info, "Shadow")
	infoShadow.Size = UDim2.fromScale(1, 1)
	infoShadow.Text = info.Text

	local textL = ensureTextLabel(template, "TextL")
	textL.AnchorPoint = Vector2.new(1, 0)
	textL.Size = UDim2.fromOffset(120, 22)
	textL.Position = UDim2.new(1, -12, 10 / 104, 0)
	textL.Text = "0"
	textL.TextScaled = true
	local textLShadow = ensureTextLabel(textL, "Shadow")
	textLShadow.Size = UDim2.fromScale(1, 1)
	textLShadow.Text = textL.Text

	local buy = ensureTextButton(template, "Buy")
	buy.AnchorPoint = Vector2.new(1, 1)
	buy.Size = UDim2.fromOffset(128, 36)
	buy.Position = UDim2.new(1, -12, 1, -10)
	buy.BackgroundColor3 = Color3.fromRGB(94, 210, 132)
	buy.BackgroundTransparency = 0
	buy.Text = "Buy"
	buy.TextColor3 = Color3.fromRGB(10, 24, 16)
	buy.TextSize = 16
	buy.Font = Enum.Font.GothamBlack
	ensureUICorner(buy, 8)
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
	joinEvent.BackgroundColor3 = Color3.fromRGB(255, 200, 98)
	joinEvent.BackgroundTransparency = 0
	joinEvent.Text = "Claim"
	joinEvent.TextColor3 = Color3.fromRGB(24, 24, 20)
	joinEvent.Font = Enum.Font.GothamBlack
	joinEvent.TextSize = 18
	ensureUICorner(joinEvent, 10)

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

	local lButtons = ensureFrame(hud, "LButtons")
	clearChildren(lButtons)
	lButtons.Size = UDim2.fromOffset(188, 274)
	lButtons.Position = UDim2.fromOffset(10, 250)
	lButtons.ClipsDescendants = false

	ensureHudButton(lButtons, "Store", false)
	ensureHudButton(lButtons, "Index", false)
	ensureHudButton(lButtons, "Gifts", true)
	ensureHudButton(lButtons, "Settings", false)
	ensureHudButton(lButtons, "Rebirth", false)

	local counters = ensureFrame(hud, "Counters")
	clearChildren(counters)
	counters.Size = UDim2.fromOffset(250, 172)
	counters.Position = UDim2.fromOffset(24, 520)
	counters.ClipsDescendants = false

	local comet = ensureCounterHost(counters, "Comet")
	comet.Position = UDim2.fromOffset(0, 0)
	ensureUIGradient(comet, Color3.fromRGB(185, 159, 222), Color3.fromRGB(226, 240, 255))

	local speed = ensureCounterHost(counters, "Speed")
	speed.Position = UDim2.fromOffset(0, 52)
	ensureUIGradient(speed, Color3.fromRGB(255, 122, 122), Color3.fromRGB(255, 204, 176))

	local money = ensureCounterHost(counters, "Money")
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
end

local function ensureFrames()
	local frames = ensureScreenGui("Frames", 120)

	local frameNames = {
		"Store",
		"Index",
		"SpeedUpgrade",
		"Rebirth",
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
		frame.BackgroundColor3 = Color3.fromRGB(7, 14, 31)
		frame.BackgroundTransparency = 0.04
		frame.BorderSizePixel = 0
		ensureUICorner(frame, 12)
		ensureUIStroke(frame, Color3.fromRGB(57, 89, 141), 1)
		ensureUIGradient(frame, Color3.fromRGB(9, 23, 49), Color3.fromRGB(6, 14, 30))
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
	ensureFrameTopBar(rebirth, "Rebirth")
	local rebirthMain = ensureFrame(rebirth, "Main")
	rebirthMain.BackgroundTransparency = 1
	rebirthMain.Position = UDim2.fromOffset(12, 52)
	rebirthMain.Size = UDim2.new(1, -24, 1, -62)

	ensureRebirthRequirement(rebirthMain, "Money", 8)
	ensureRebirthRequirement(rebirthMain, "Speed", 88)

	local youGet = ensureFrame(rebirthMain, "YouGet")
	youGet.BackgroundTransparency = 1
	youGet.Position = UDim2.fromOffset(16, 172)
	youGet.Size = UDim2.new(1, -32, 1, -228)
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
	template.BackgroundColor3 = Color3.fromRGB(20, 29, 46)
	template.BackgroundTransparency = 0.12
	ensureUICorner(template, 8)
	ensureUIStroke(template, Color3.fromRGB(70, 95, 132), 1)
	local render = ensureImageLabel(template, "Render")
	render.Position = UDim2.fromOffset(8, 8)
	render.Size = UDim2.fromOffset(30, 30)
	local amount = ensureTextLabel(template, "Amount")
	amount.Position = UDim2.fromOffset(46, 0)
	amount.Size = UDim2.new(1, -54, 1, 0)
	amount.TextXAlignment = Enum.TextXAlignment.Left
	amount.TextSize = 15

	local rebirthButton = ensureTextButton(rebirthMain, "Rebirth")
	rebirthButton.Size = UDim2.fromOffset(180, 38)
	rebirthButton.AnchorPoint = Vector2.new(0.5, 1)
	rebirthButton.Position = UDim2.new(0.5, 0, 1, -10)
	rebirthButton.BackgroundColor3 = Color3.fromRGB(112, 218, 145)
	rebirthButton.BackgroundTransparency = 0
	rebirthButton.Text = "Rebirth"
	rebirthButton.TextColor3 = Color3.fromRGB(10, 20, 16)
	rebirthButton.Font = Enum.Font.GothamBlack
	rebirthButton.TextSize = 18
	ensureUICorner(rebirthButton, 10)

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
	ensureFrameTopBar(gifts, "Gifts")
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
	limitedReward.Size = UDim2.new(0.5, 0, 0.46, 0)
	ensureLimitedRewardLayout(limitedReward)
end

ensureHud()
ensureFrames()
