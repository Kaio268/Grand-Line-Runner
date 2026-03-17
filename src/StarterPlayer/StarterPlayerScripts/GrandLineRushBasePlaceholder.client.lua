local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Temporary base UI for chest opening and crew feeding.
-- Designers can replace this whole script later and keep using GrandLineRushMetaClient.
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
if Economy.VerticalSlice.Enabled ~= true then
	return
end

local placeholderConfig = Economy.PlaceholderBaseUI
if typeof(placeholderConfig) ~= "table" or placeholderConfig.Enabled ~= true then
	return
end

local MetaClient = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushMetaClient"))
MetaClient.Init()

local rarityColors = {
	Common = Color3.fromRGB(214, 214, 214),
	Uncommon = Color3.fromRGB(107, 229, 124),
	Rare = Color3.fromRGB(85, 171, 255),
	Epic = Color3.fromRGB(202, 116, 255),
	Legendary = Color3.fromRGB(255, 194, 92),
	Mythical = Color3.fromRGB(255, 110, 161),
	Celestial = Color3.fromRGB(135, 245, 255),
	Godly = Color3.fromRGB(255, 112, 112),
	Secret = Color3.fromRGB(255, 255, 255),
}

local foodOrder = { "Apple", "Rice", "Meat", "SeaBeastMeat" }

local currentState = MetaClient.GetState()
local selectedCrewId = nil
local activeTab = "Chests"
local lastMessage = "Temporary base UI active. Final art/layout can replace this later."
local lastRunResolutionText = nil

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

local function createStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.fromRGB(195, 233, 255)
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function createLabel(parent, text, size, position, textSize, font, alignment)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = font or Enum.Font.GothamBold
	label.TextSize = textSize or 14
	label.TextWrapped = false
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Size = size or UDim2.new(1, 0, 0, 24)
	label.Position = position or UDim2.new()
	label.Parent = parent
	return label
end

local function createButton(parent, text, size, position, backgroundColor)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.Text = text or ""
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.BackgroundColor3 = backgroundColor or Color3.fromRGB(35, 116, 148)
	button.Size = size or UDim2.fromOffset(120, 34)
	button.Position = position or UDim2.new()
	button.Parent = parent
	createCorner(button, 10)
	createStroke(button, Color3.fromRGB(195, 233, 255), 1, 0.2)
	return button
end

local function createSection(parent, name, size, position)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Color3.fromRGB(13, 39, 57)
	frame.Parent = parent
	createCorner(frame, 14)
	createStroke(frame, Color3.fromRGB(111, 191, 226), 1, 0.45)
	return frame
end

local function setButtonEnabled(button, enabled)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = enabled and 0 or 0.35
	button.BackgroundTransparency = enabled and 0 or 0.3
end

local function destroyRows(container)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Name ~= "Layout" and child.Name ~= "Padding" then
			child:Destroy()
		end
	end
end

local function getCrewById(state, crewId)
	if typeof(state) ~= "table" or typeof(state.Crews) ~= "table" then
		return nil
	end

	for _, crew in ipairs(state.Crews) do
		if tostring(crew.InstanceId) == tostring(crewId) then
			return crew
		end
	end

	return nil
end

local function getSelectedCrew(state)
	return getCrewById(state, selectedCrewId)
end

local function normalizeSelectedCrew(state)
	local crews = state and state.Crews or nil
	if typeof(crews) ~= "table" or #crews == 0 then
		selectedCrewId = nil
		return nil
	end

	if selectedCrewId and getCrewById(state, selectedCrewId) then
		return getCrewById(state, selectedCrewId)
	end

	selectedCrewId = tostring(crews[1].InstanceId)
	return crews[1]
end

local function getFoodCount(state, foodKey)
	local inventory = state and state.FoodInventory or {}
	return tonumber(inventory and inventory[foodKey]) or 0
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GrandLineRushBasePlaceholder"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

local toggleButton = createButton(
	screenGui,
	tostring(placeholderConfig.ToggleButtonText or "Ship Meta"),
	UDim2.fromOffset(132, 38),
	UDim2.new(1, -152, 0, 164),
	Color3.fromRGB(18, 92, 124)
)
toggleButton.ZIndex = 25

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -18, 0.5, 0)
panel.Size = UDim2.fromOffset(560, 560)
panel.BackgroundColor3 = Color3.fromRGB(8, 23, 36)
panel.Visible = false
panel.Parent = screenGui
panel.ZIndex = 20
createCorner(panel, 18)
createStroke(panel, Color3.fromRGB(140, 214, 255), 2, 0.25)

local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 40, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 17, 28)),
})
panelGradient.Rotation = 90
panelGradient.Parent = panel

local header = Instance.new("Frame")
header.Size = UDim2.new(1, -24, 0, 50)
header.Position = UDim2.fromOffset(12, 12)
header.BackgroundColor3 = Color3.fromRGB(19, 70, 98)
header.Parent = panel
header.ZIndex = 21
createCorner(header, 14)

local headerGradient = Instance.new("UIGradient")
headerGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(30, 111, 148)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 73, 103)),
})
headerGradient.Parent = header

local titleLabel = createLabel(header, "Grand Line Rush Base Placeholder", UDim2.new(1, -92, 1, 0), UDim2.fromOffset(14, 0), 18)
titleLabel.ZIndex = 22

local closeButton = createButton(header, "X", UDim2.fromOffset(46, 34), UDim2.new(1, -56, 0, 8), Color3.fromRGB(157, 75, 67))
closeButton.ZIndex = 22

local subtitle = createLabel(panel, "Temporary chest + crew management UI. Future art can replace this layer.", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(16, 68), 12, Enum.Font.GothamMedium)
subtitle.TextColor3 = Color3.fromRGB(179, 222, 248)
subtitle.ZIndex = 21

local summaryFrame = createSection(panel, "Summary", UDim2.new(1, -28, 0, 86), UDim2.fromOffset(16, 92))
summaryFrame.ZIndex = 20

local summaryLabel = createLabel(summaryFrame, "", UDim2.new(1, -20, 0, 26), UDim2.fromOffset(10, 8), 14)
summaryLabel.ZIndex = 21
local resourceSummaryLabel = createLabel(summaryFrame, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 34), 12, Enum.Font.Gotham)
resourceSummaryLabel.ZIndex = 21
local runSummaryLabel = createLabel(summaryFrame, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 58), 12, Enum.Font.Gotham)
runSummaryLabel.TextColor3 = Color3.fromRGB(255, 229, 156)
runSummaryLabel.ZIndex = 21

local tabRow = Instance.new("Frame")
tabRow.BackgroundTransparency = 1
tabRow.Size = UDim2.new(1, -28, 0, 36)
tabRow.Position = UDim2.fromOffset(16, 188)
tabRow.Parent = panel
tabRow.ZIndex = 20

local chestTabButton = createButton(tabRow, "Chests", UDim2.fromOffset(116, 36), UDim2.fromOffset(0, 0), Color3.fromRGB(120, 80, 37))
chestTabButton.ZIndex = 21
local crewTabButton = createButton(tabRow, "Crew", UDim2.fromOffset(116, 36), UDim2.fromOffset(126, 0), Color3.fromRGB(45, 96, 152))
crewTabButton.ZIndex = 21

local tabContainer = Instance.new("Frame")
tabContainer.BackgroundTransparency = 1
tabContainer.Size = UDim2.new(1, -28, 0, 266)
tabContainer.Position = UDim2.fromOffset(16, 234)
tabContainer.Parent = panel
tabContainer.ZIndex = 20

local chestsFrame = Instance.new("Frame")
chestsFrame.Name = "Chests"
chestsFrame.BackgroundTransparency = 1
chestsFrame.Size = UDim2.fromScale(1, 1)
chestsFrame.Parent = tabContainer
chestsFrame.ZIndex = 20

local chestHeaderLabel = createLabel(chestsFrame, "Stored chests", UDim2.new(1, -130, 0, 20), UDim2.fromOffset(0, 0), 14)
chestHeaderLabel.TextColor3 = Color3.fromRGB(255, 222, 156)
chestHeaderLabel.ZIndex = 21
local openOldestButton = createButton(chestsFrame, "Open Oldest", UDim2.fromOffset(116, 34), UDim2.new(1, -116, 0, 0), Color3.fromRGB(147, 110, 47))
openOldestButton.ZIndex = 21

local chestScroll = Instance.new("ScrollingFrame")
chestScroll.Name = "ChestScroll"
chestScroll.BackgroundColor3 = Color3.fromRGB(11, 31, 47)
chestScroll.Position = UDim2.fromOffset(0, 30)
chestScroll.Size = UDim2.new(1, 0, 1, -30)
chestScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
chestScroll.CanvasSize = UDim2.new()
chestScroll.ScrollBarThickness = 6
chestScroll.BorderSizePixel = 0
chestScroll.Parent = chestsFrame
chestScroll.ZIndex = 20
createCorner(chestScroll, 14)
createStroke(chestScroll, Color3.fromRGB(111, 191, 226), 1, 0.45)

local chestPadding = Instance.new("UIPadding")
chestPadding.Name = "Padding"
chestPadding.PaddingLeft = UDim.new(0, 10)
chestPadding.PaddingRight = UDim.new(0, 10)
chestPadding.PaddingTop = UDim.new(0, 10)
chestPadding.PaddingBottom = UDim.new(0, 10)
chestPadding.Parent = chestScroll

local chestLayout = Instance.new("UIListLayout")
chestLayout.Name = "Layout"
chestLayout.Padding = UDim.new(0, 8)
chestLayout.Parent = chestScroll

local crewFrame = Instance.new("Frame")
crewFrame.Name = "Crew"
crewFrame.BackgroundTransparency = 1
crewFrame.Size = UDim2.fromScale(1, 1)
crewFrame.Parent = tabContainer
crewFrame.Visible = false
crewFrame.ZIndex = 20

local crewDetailFrame = createSection(crewFrame, "CrewDetail", UDim2.new(1, 0, 0, 110), UDim2.fromOffset(0, 0))
crewDetailFrame.ZIndex = 20

local selectedCrewLabel = createLabel(crewDetailFrame, "Selected Crew: None", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 8), 14)
selectedCrewLabel.ZIndex = 21
local selectedCrewStatsLabel = createLabel(crewDetailFrame, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 36), 12, Enum.Font.Gotham)
selectedCrewStatsLabel.ZIndex = 21
local selectedCrewProgressLabel = createLabel(crewDetailFrame, "", UDim2.new(1, -20, 0, 22), UDim2.fromOffset(10, 58), 12, Enum.Font.Gotham)
selectedCrewProgressLabel.ZIndex = 21

local feedRow = Instance.new("Frame")
feedRow.BackgroundTransparency = 1
feedRow.Size = UDim2.new(1, -20, 0, 34)
feedRow.Position = UDim2.fromOffset(10, 78)
feedRow.Parent = crewDetailFrame

local feedLayout = Instance.new("UIListLayout")
feedLayout.FillDirection = Enum.FillDirection.Horizontal
feedLayout.Padding = UDim.new(0, 8)
feedLayout.Parent = feedRow

local feedButtons = {}
for _, foodKey in ipairs(foodOrder) do
	local button = createButton(feedRow, foodKey, UDim2.fromOffset(122, 34), nil, Color3.fromRGB(52, 107, 84))
	button.ZIndex = 21
	feedButtons[foodKey] = button
end

local crewHeaderLabel = createLabel(crewFrame, "Owned crew", UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, 120), 14)
crewHeaderLabel.TextColor3 = Color3.fromRGB(255, 222, 156)
crewHeaderLabel.ZIndex = 21

local crewScroll = Instance.new("ScrollingFrame")
crewScroll.Name = "CrewScroll"
crewScroll.BackgroundColor3 = Color3.fromRGB(11, 31, 47)
crewScroll.Position = UDim2.fromOffset(0, 150)
crewScroll.Size = UDim2.new(1, 0, 1, -150)
crewScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
crewScroll.CanvasSize = UDim2.new()
crewScroll.ScrollBarThickness = 6
crewScroll.BorderSizePixel = 0
crewScroll.Parent = crewFrame
crewScroll.ZIndex = 20
createCorner(crewScroll, 14)
createStroke(crewScroll, Color3.fromRGB(111, 191, 226), 1, 0.45)

local crewPadding = Instance.new("UIPadding")
crewPadding.Name = "Padding"
crewPadding.PaddingLeft = UDim.new(0, 10)
crewPadding.PaddingRight = UDim.new(0, 10)
crewPadding.PaddingTop = UDim.new(0, 10)
crewPadding.PaddingBottom = UDim.new(0, 10)
crewPadding.Parent = crewScroll

local crewLayout = Instance.new("UIListLayout")
crewLayout.Name = "Layout"
crewLayout.Padding = UDim.new(0, 8)
crewLayout.Parent = crewScroll

local messageFrame = createSection(panel, "Message", UDim2.new(1, -28, 0, 48), UDim2.fromOffset(16, 508))
messageFrame.ZIndex = 20

local messageLabel = createLabel(messageFrame, lastMessage, UDim2.new(1, -20, 1, 0), UDim2.fromOffset(10, 0), 12, Enum.Font.Gotham)
messageLabel.TextWrapped = true
messageLabel.TextColor3 = Color3.fromRGB(183, 223, 244)
messageLabel.ZIndex = 21

local function setMessage(text)
	if typeof(text) == "string" and text ~= "" then
		lastMessage = text
	end
	messageLabel.Text = lastMessage
end

local function setActiveTab(tabName)
	activeTab = tabName
	local onChest = tabName == "Chests"
	chestsFrame.Visible = onChest
	crewFrame.Visible = not onChest

	chestTabButton.BackgroundColor3 = onChest and Color3.fromRGB(151, 105, 46) or Color3.fromRGB(72, 60, 44)
	crewTabButton.BackgroundColor3 = onChest and Color3.fromRGB(61, 75, 99) or Color3.fromRGB(56, 114, 181)
end

local function renderSummary(state)
	local doubloons = tonumber(state and state.Doubloons) or 0
	local chestCount = tonumber(state and state.UnopenedChestCount) or 0
	local crewCount = state and state.Crews and #state.Crews or 0
	summaryLabel.Text = string.format("Doubloons: %d D | Stored Chests: %d | Crew: %d", doubloons, chestCount, crewCount)

	local mats = state and state.Materials or {}
	resourceSummaryLabel.Text = string.format(
		"Food: Apple x%d | Rice x%d | Meat x%d | Sea Beast Meat x%d | Common Mats x%d | Rare Mats x%d | Devil Fruits x%d",
		getFoodCount(state, "Apple"),
		getFoodCount(state, "Rice"),
		getFoodCount(state, "Meat"),
		getFoodCount(state, "SeaBeastMeat"),
		tonumber(mats.CommonShipMaterial) or 0,
		tonumber(mats.RareShipMaterial) or 0,
		tonumber(state and state.DevilFruitCount) or 0
	)

	local runState = state and state.Run or {}
	local carrying = runState.CarriedReward and runState.CarriedReward.DisplayName or "None"
	runSummaryLabel.Text = string.format(
		"Run: %s | Depth: %s | Carrying: %s",
		runState.InRun and "Active" or "Idle",
		tostring(runState.DepthBand or Economy.VerticalSlice.DefaultDepthBand),
		tostring(carrying)
	)
end

local function renderChests(state)
	destroyRows(chestScroll)

	local unopenedChests = state and state.UnopenedChests or {}
	setButtonEnabled(openOldestButton, false)
	chestHeaderLabel.Text = string.format("Stored chests (%d)", #unopenedChests)

	if #unopenedChests == 0 then
		local emptyLabel = createLabel(chestScroll, "No unopened chests yet. Extract one from the corridor first.", UDim2.new(1, -12, 0, 24), UDim2.fromOffset(0, 0), 13, Enum.Font.Gotham)
		emptyLabel.Name = "EmptyState"
		emptyLabel.TextColor3 = Color3.fromRGB(176, 211, 228)
		emptyLabel.ZIndex = 21
		return
	end

	for _, chest in ipairs(unopenedChests) do
		local row = Instance.new("Frame")
		row.Name = "ChestRow"
		row.Size = UDim2.new(1, 0, 0, 56)
		row.BackgroundColor3 = Color3.fromRGB(17, 49, 71)
		row.Parent = chestScroll
		row.ZIndex = 20
		createCorner(row, 12)
		createStroke(row, Color3.fromRGB(111, 191, 226), 1, 0.45)

		local infoLabel = createLabel(
			row,
			string.format("%s Chest | Depth %s | #%s", tostring(chest.Tier), tostring(chest.DepthBand), tostring(chest.ChestId)),
			UDim2.new(1, -128, 0, 24),
			UDim2.fromOffset(12, 6),
			14
		)
		infoLabel.ZIndex = 21

		local rewardHint = createLabel(
			row,
			"Extracted chests now enter your hotbar. Equip the chest and click to open it.",
			UDim2.new(1, -128, 0, 18),
			UDim2.fromOffset(12, 30),
			12,
			Enum.Font.Gotham
		)
		rewardHint.TextColor3 = Color3.fromRGB(176, 211, 228)
		rewardHint.ZIndex = 21

		local openButton = createButton(row, "Use Hotbar", UDim2.fromOffset(96, 34), UDim2.new(1, -108, 0, 11), Color3.fromRGB(81, 97, 112))
		openButton.ZIndex = 21
		setButtonEnabled(openButton, false)
	end
end

local function renderCrewDetail(state)
	local selectedCrew = normalizeSelectedCrew(state)
	if not selectedCrew then
		selectedCrewLabel.Text = "Selected Crew: None"
		selectedCrewStatsLabel.Text = "No crew acquired yet."
		selectedCrewProgressLabel.Text = "Extract a crew reward or use the starter crew to test the system."
		for _, foodKey in ipairs(foodOrder) do
			local button = feedButtons[foodKey]
			button.Text = string.format("%s x0", Economy.Food[foodKey].DisplayName)
			setButtonEnabled(button, false)
		end
		return
	end

	selectedCrewLabel.Text = string.format(
		"Selected Crew: %s | %s",
		tostring(selectedCrew.Name),
		tostring(selectedCrew.Rarity)
	)
	selectedCrewLabel.TextColor3 = rarityColors[selectedCrew.Rarity] or Color3.new(1, 1, 1)
	selectedCrewStatsLabel.Text = string.format(
		"Level %d | Ship Income %d D/hr | Source: %s",
		tonumber(selectedCrew.Level) or 1,
		tonumber(selectedCrew.ShipIncomePerHour) or 0,
		tostring(selectedCrew.Source or "Unknown")
	)

	local nextLevelXP = tonumber(selectedCrew.NextLevelXP) or 0
	if nextLevelXP > 0 then
		selectedCrewProgressLabel.Text = string.format(
			"XP %d / %d",
			tonumber(selectedCrew.CurrentXP) or 0,
			nextLevelXP
		)
	else
		selectedCrewProgressLabel.Text = "Max level reached"
	end

	for _, foodKey in ipairs(foodOrder) do
		local count = getFoodCount(state, foodKey)
		local button = feedButtons[foodKey]
		button.Text = string.format("%s x%d", Economy.Food[foodKey].DisplayName, count)
		setButtonEnabled(button, count > 0)
	end
end

local function renderCrewRows(state)
	destroyRows(crewScroll)

	local crews = state and state.Crews or {}
	crewHeaderLabel.Text = string.format("Owned crew (%d)", #crews)

	if #crews == 0 then
		local emptyLabel = createLabel(crewScroll, "No crew stored yet.", UDim2.new(1, -12, 0, 24), UDim2.fromOffset(0, 0), 13, Enum.Font.Gotham)
		emptyLabel.Name = "EmptyState"
		emptyLabel.TextColor3 = Color3.fromRGB(176, 211, 228)
		emptyLabel.ZIndex = 21
		return
	end

	for _, crew in ipairs(crews) do
		local isSelected = tostring(crew.InstanceId) == tostring(selectedCrewId)

		local row = Instance.new("TextButton")
		row.Name = "CrewRow"
		row.AutoButtonColor = true
		row.Text = ""
		row.Size = UDim2.new(1, 0, 0, 62)
		row.BackgroundColor3 = if isSelected then Color3.fromRGB(34, 82, 114) else Color3.fromRGB(17, 49, 71)
		row.Parent = crewScroll
		row.ZIndex = 20
		createCorner(row, 12)
		createStroke(row, if isSelected then Color3.fromRGB(255, 231, 168) else Color3.fromRGB(111, 191, 226), 1, 0.35)

		local nameLabel = createLabel(row, tostring(crew.Name), UDim2.new(1, -16, 0, 22), UDim2.fromOffset(10, 6), 14)
		nameLabel.TextColor3 = rarityColors[crew.Rarity] or Color3.new(1, 1, 1)
		nameLabel.ZIndex = 21

		local statLabel = createLabel(
			row,
			string.format("%s | Lv.%d | XP %d/%d | %d D/hr", tostring(crew.Rarity), tonumber(crew.Level) or 1, tonumber(crew.CurrentXP) or 0, tonumber(crew.NextLevelXP) or 0, tonumber(crew.ShipIncomePerHour) or 0),
			UDim2.new(1, -16, 0, 18),
			UDim2.fromOffset(10, 30),
			12,
			Enum.Font.Gotham
		)
		statLabel.TextColor3 = Color3.fromRGB(176, 211, 228)
		statLabel.ZIndex = 21

		row.MouseButton1Click:Connect(function()
			selectedCrewId = tostring(crew.InstanceId)
			renderCrewDetail(currentState)
			renderCrewRows(currentState)
		end)
	end
end

local function render(state)
	currentState = state or currentState or {}
	renderSummary(currentState)
	renderChests(currentState)
	renderCrewDetail(currentState)
	renderCrewRows(currentState)

	local runResolutionText = currentState.Run and currentState.Run.ResolutionText or nil
	if typeof(runResolutionText) == "string" and runResolutionText ~= "" and runResolutionText ~= lastRunResolutionText then
		lastRunResolutionText = runResolutionText
		setMessage(runResolutionText)
	end
end

toggleButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

closeButton.MouseButton1Click:Connect(function()
	panel.Visible = false
end)

chestTabButton.MouseButton1Click:Connect(function()
	setActiveTab("Chests")
end)

crewTabButton.MouseButton1Click:Connect(function()
	setActiveTab("Crew")
end)

openOldestButton.MouseButton1Click:Connect(function()
	setMessage("Use the chest from your hotbar to open it.")
end)

for _, foodKey in ipairs(foodOrder) do
	feedButtons[foodKey].MouseButton1Click:Connect(function()
		local selectedCrew = getSelectedCrew(currentState)
		if not selectedCrew then
			setMessage("Select a crew first.")
			return
		end

		local response = MetaClient.FeedCrew(selectedCrew.InstanceId, foodKey)
		setMessage(response and response.message or "Feed request failed.")
	end)
end

MetaClient.ObserveState(function(newState)
	currentState = newState
	render(newState)
end)

setActiveTab(activeTab)
render(currentState or {})
