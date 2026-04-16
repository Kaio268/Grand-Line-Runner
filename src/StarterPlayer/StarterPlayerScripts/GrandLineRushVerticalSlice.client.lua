local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local verticalSliceConfig = Economy.VerticalSlice
if verticalSliceConfig.Enabled ~= true then
	return
end

local developerPanelEnabled = verticalSliceConfig.DeveloperPanelEnabled == true
local studioOnly = verticalSliceConfig.DeveloperPanelStudioOnly ~= false
if not developerPanelEnabled then
	return
end

if studioOnly and not RunService:IsStudio() then
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remotesFolder:WaitForChild(verticalSliceConfig.Remotes.RequestName)
local stateRemote = remotesFolder:WaitForChild(verticalSliceConfig.Remotes.StateEventName)

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GrandLineRushVerticalSlice"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = player:WaitForChild("PlayerGui")

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
local selectedDepthBand = verticalSliceConfig.DefaultDepthBand
local selectedCrewId = nil
local currentState = nil
local lastMessage = "Open the prototype panel and validate the loop."
local SAFE_CLIENT_ACTIONS = {
	GetState = true,
	OpenChest = true,
	FeedCrew = true,
}

local function createCorner(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 12)
	corner.Parent = parent
	return corner
end

local function createStroke(parent, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.Parent = parent
	return stroke
end

local function createLabel(parent, text, size, position, textSize, alignment)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Text = text or ""
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize or 16
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

local toggleButton = createButton(
	screenGui,
	"Rush Loop",
	UDim2.fromOffset(124, 36),
	UDim2.new(1, -144, 0, 120),
	Color3.fromRGB(19, 92, 126)
)
toggleButton.ZIndex = 25

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0.5)
panel.Position = UDim2.new(1, -18, 0.5, 0)
panel.Size = UDim2.fromOffset(470, 590)
panel.BackgroundColor3 = Color3.fromRGB(9, 28, 43)
panel.Parent = screenGui
panel.Visible = RunService:IsStudio()
panel.ZIndex = 20
createCorner(panel, 18)
createStroke(panel, Color3.fromRGB(140, 214, 255), 2, 0.25)

local panelGradient = Instance.new("UIGradient")
panelGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 41, 60)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 19, 31)),
})
panelGradient.Rotation = 90
panelGradient.Parent = panel

local topBar = Instance.new("Frame")
topBar.Size = UDim2.new(1, -24, 0, 48)
topBar.Position = UDim2.fromOffset(12, 12)
topBar.BackgroundColor3 = Color3.fromRGB(19, 70, 98)
topBar.Parent = panel
createCorner(topBar, 14)

local topBarGradient = Instance.new("UIGradient")
topBarGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(29, 108, 145)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 73, 103)),
})
topBarGradient.Parent = topBar

local title = createLabel(topBar, "Grand Line Rush Prototype Loop", UDim2.new(1, -20, 1, 0), UDim2.fromOffset(12, 0), 18)
title.ZIndex = 21

local subtitle = createLabel(panel, "Vertical slice: crew run -> extract -> open chest -> feed crew", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(16, 68), 12)
subtitle.TextColor3 = Color3.fromRGB(179, 222, 248)
subtitle.Font = Enum.Font.GothamMedium
subtitle.ZIndex = 21

local depthLabel = createLabel(panel, "Depth Band", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(16, 98), 13)
depthLabel.TextColor3 = Color3.fromRGB(255, 222, 156)
depthLabel.ZIndex = 21

local depthRow = Instance.new("Frame")
depthRow.BackgroundTransparency = 1
depthRow.Size = UDim2.new(1, -28, 0, 34)
depthRow.Position = UDim2.fromOffset(16, 120)
depthRow.Parent = panel

local depthButtons = {}
do
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Padding = UDim.new(0, 8)
	layout.Parent = depthRow

	for _, depthBand in ipairs(verticalSliceConfig.DepthBands) do
		local button = createButton(depthRow, depthBand, UDim2.fromOffset(102, 34), nil, Color3.fromRGB(24, 87, 109))
		button.ZIndex = 21
		depthButtons[depthBand] = button
	end
end

local actionLabel = createLabel(panel, "Corridor Actions (server-observed only)", UDim2.new(1, -28, 0, 18), UDim2.fromOffset(16, 168), 13)
actionLabel.TextColor3 = Color3.fromRGB(255, 222, 156)
actionLabel.ZIndex = 21

local actionGrid = Instance.new("Frame")
actionGrid.BackgroundTransparency = 1
actionGrid.Size = UDim2.new(1, -28, 0, 80)
actionGrid.Position = UDim2.fromOffset(16, 190)
actionGrid.Parent = panel

local actionLayout = Instance.new("UIGridLayout")
actionLayout.CellPadding = UDim2.fromOffset(8, 8)
actionLayout.CellSize = UDim2.fromOffset(140, 36)
actionLayout.Parent = actionGrid

local startChestButton = createButton(actionGrid, "World Chests Shared", nil, nil, Color3.fromRGB(73, 83, 93))
local startCrewButton = createButton(actionGrid, "Start At Corridor", nil, nil, Color3.fromRGB(42, 97, 153))
local claimRewardButton = createButton(actionGrid, "Pick Up In World", nil, nil, Color3.fromRGB(53, 127, 107))
local extractButton = createButton(actionGrid, "Extract In Zone", nil, nil, Color3.fromRGB(27, 124, 91))
local failRunButton = createButton(actionGrid, "Fail On Server", nil, nil, Color3.fromRGB(148, 62, 62))

for _, button in ipairs({ startChestButton, startCrewButton, claimRewardButton, extractButton, failRunButton }) do
	button.ZIndex = 21
end

local summaryFrame = Instance.new("Frame")
summaryFrame.BackgroundColor3 = Color3.fromRGB(13, 39, 57)
summaryFrame.Size = UDim2.new(1, -28, 0, 110)
summaryFrame.Position = UDim2.fromOffset(16, 280)
summaryFrame.Parent = panel
summaryFrame.ZIndex = 20
createCorner(summaryFrame, 14)
createStroke(summaryFrame, Color3.fromRGB(111, 191, 226), 1, 0.45)

local runStatusLabel = createLabel(summaryFrame, "", UDim2.new(1, -20, 0, 48), UDim2.fromOffset(10, 8), 13)
runStatusLabel.Font = Enum.Font.GothamMedium
runStatusLabel.TextWrapped = true
runStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
runStatusLabel.ZIndex = 21

local rewardStatusLabel = createLabel(summaryFrame, "", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 54), 13)
rewardStatusLabel.Font = Enum.Font.GothamMedium
rewardStatusLabel.TextColor3 = Color3.fromRGB(255, 231, 168)
rewardStatusLabel.ZIndex = 21

local messageLabel = createLabel(summaryFrame, lastMessage, UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 80), 12)
messageLabel.Font = Enum.Font.Gotham
messageLabel.TextColor3 = Color3.fromRGB(183, 223, 244)
messageLabel.TextWrapped = true
messageLabel.ZIndex = 21

local baseFrame = Instance.new("Frame")
baseFrame.BackgroundColor3 = Color3.fromRGB(13, 39, 57)
baseFrame.Size = UDim2.new(1, -28, 0, 122)
baseFrame.Position = UDim2.fromOffset(16, 402)
baseFrame.Parent = panel
baseFrame.ZIndex = 20
createCorner(baseFrame, 14)
createStroke(baseFrame, Color3.fromRGB(111, 191, 226), 1, 0.45)

local chestInventoryLabel = createLabel(baseFrame, "", UDim2.new(1, -20, 0, 24), UDim2.fromOffset(10, 8), 13)
chestInventoryLabel.TextColor3 = Color3.fromRGB(255, 222, 156)
chestInventoryLabel.ZIndex = 21

local chestListLabel = createLabel(baseFrame, "", UDim2.new(1, -154, 0, 42), UDim2.fromOffset(10, 34), 12)
chestListLabel.Font = Enum.Font.Gotham
chestListLabel.TextWrapped = true
chestListLabel.TextYAlignment = Enum.TextYAlignment.Top
chestListLabel.ZIndex = 21

local openChestButton = createButton(baseFrame, "Open Oldest Chest", UDim2.fromOffset(126, 40), UDim2.new(1, -136, 0, 34), Color3.fromRGB(147, 110, 47))
openChestButton.ZIndex = 21

local resourcesLabel = createLabel(baseFrame, "", UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, 78), 12)
resourcesLabel.Font = Enum.Font.Gotham
resourcesLabel.TextWrapped = true
resourcesLabel.TextYAlignment = Enum.TextYAlignment.Top
resourcesLabel.ZIndex = 21

local crewFrame = Instance.new("Frame")
crewFrame.BackgroundColor3 = Color3.fromRGB(13, 39, 57)
crewFrame.Size = UDim2.new(1, -28, 0, 54)
crewFrame.Position = UDim2.fromOffset(16, 534)
crewFrame.Parent = panel
crewFrame.ZIndex = 20
createCorner(crewFrame, 14)
createStroke(crewFrame, Color3.fromRGB(111, 191, 226), 1, 0.45)

local selectedCrewLabel = createLabel(crewFrame, "Selected Crew: None", UDim2.new(1, -20, 0, 20), UDim2.fromOffset(10, 8), 13)
selectedCrewLabel.ZIndex = 21

local feedRow = Instance.new("Frame")
feedRow.BackgroundTransparency = 1
feedRow.Size = UDim2.new(1, -20, 0, 22)
feedRow.Position = UDim2.fromOffset(10, 28)
feedRow.Parent = crewFrame
feedRow.ZIndex = 20

local feedLayout = Instance.new("UIListLayout")
feedLayout.FillDirection = Enum.FillDirection.Horizontal
feedLayout.Padding = UDim.new(0, 6)
feedLayout.Parent = feedRow

local feedButtons = {}
for _, foodKey in ipairs(foodOrder) do
	local button = createButton(feedRow, foodKey, UDim2.fromOffset(104, 22), nil, Color3.fromRGB(64, 111, 80))
	button.TextSize = 12
	button.ZIndex = 21
	feedButtons[foodKey] = button
end

local crewList = Instance.new("ScrollingFrame")
crewList.Name = "CrewList"
crewList.BackgroundTransparency = 1
crewList.BorderSizePixel = 0
crewList.Size = UDim2.new(1, -28, 0, 154)
crewList.Position = UDim2.fromOffset(16, 596)
crewList.CanvasSize = UDim2.new()
crewList.ScrollBarThickness = 6
crewList.AutomaticCanvasSize = Enum.AutomaticSize.Y
crewList.Parent = panel
crewList.ZIndex = 20

local crewListLayout = Instance.new("UIListLayout")
crewListLayout.Padding = UDim.new(0, 8)
crewListLayout.Parent = crewList

local crewListPadding = Instance.new("UIPadding")
crewListPadding.PaddingBottom = UDim.new(0, 6)
crewListPadding.Parent = crewList

local panelHeight = 760
panel.Size = UDim2.fromOffset(470, panelHeight)
crewList.Size = UDim2.new(1, -28, 0, panelHeight - 612)

local function setMessage(text)
	lastMessage = text or lastMessage
	messageLabel.Text = lastMessage
end

local function setWorldInteractionMessage(actionName)
	setMessage(string.format(
		"%s is now server-observed only. Use the real corridor start prompt, reward pickup prompt, or extraction zone.",
		tostring(actionName or "That action")
	))
end

local function setButtonEnabled(button, enabled)
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = enabled and 0 or 0.35
	button.BackgroundTransparency = enabled and 0 or 0.35
end

local function getSelectedCrew()
	if not currentState or not currentState.Crews then
		return nil
	end

	for _, crew in ipairs(currentState.Crews) do
		if crew.InstanceId == selectedCrewId then
			return crew
		end
	end

	return nil
end

local function render()
	if not currentState then
		return
	end

	local runState = currentState.Run or {}
	local spawnedText = runState.SpawnedReward and runState.SpawnedReward.DisplayName or "None"
	local carriedText = runState.CarriedReward and runState.CarriedReward.DisplayName or "None"

	runStatusLabel.Text = string.format(
		"Run Active: %s\nDepth: %s\nDoubloons: %s",
		runState.InRun and "Yes" or "No",
		tostring(runState.DepthBand or selectedDepthBand),
		tostring(currentState.Doubloons or 0)
	)
	rewardStatusLabel.Text = string.format("Spawned: %s    |    Carrying: %s", spawnedText, carriedText)
	setMessage(runState.ResolutionText or lastMessage)

	chestInventoryLabel.Text = string.format("Unopened Chests: %d", tonumber(currentState.UnopenedChestCount) or 0)
	if currentState.UnopenedChests and #currentState.UnopenedChests > 0 then
		local parts = {}
		for index, chest in ipairs(currentState.UnopenedChests) do
			parts[#parts + 1] = string.format("#%s %s", tostring(chest.ChestId), tostring(chest.DisplayName or chest.Tier))
			if index >= 5 then
				break
			end
		end
		chestListLabel.Text = "Stored: " .. table.concat(parts, ", ")
	else
		chestListLabel.Text = "Stored: none"
	end

	local foodInventory = currentState.FoodInventory or {}
	local materials = currentState.Materials or {}
	local resourceParts = {}
	for _, foodKey in ipairs(foodOrder) do
		resourceParts[#resourceParts + 1] = string.format("%s x%d", Economy.Food[foodKey].DisplayName, tonumber(foodInventory[foodKey]) or 0)
	end
	resourceParts[#resourceParts + 1] = string.format("Common Mats x%d", tonumber(materials.CommonShipMaterial) or 0)
	resourceParts[#resourceParts + 1] = string.format("Rare Mats x%d", tonumber(materials.RareShipMaterial) or 0)
	resourceParts[#resourceParts + 1] = string.format("Devil Fruits x%d", tonumber(currentState.DevilFruitCount) or 0)
	resourcesLabel.Text = table.concat(resourceParts, "   |   ")

	for depthBand, button in pairs(depthButtons) do
		if depthBand == selectedDepthBand then
			button.BackgroundColor3 = Color3.fromRGB(44, 149, 186)
		else
			button.BackgroundColor3 = Color3.fromRGB(24, 87, 109)
		end
	end

	local crews = currentState.Crews or {}
	if selectedCrewId == nil and #crews > 0 then
		selectedCrewId = crews[1].InstanceId
	end

	local selectedCrew = getSelectedCrew()
	if not selectedCrew and #crews > 0 then
		selectedCrewId = crews[1].InstanceId
		selectedCrew = crews[1]
	end

	if selectedCrew then
		selectedCrewLabel.Text = string.format(
			"Selected Crew: %s | %s | Lv.%d | XP %d/%d | %d D/hr",
			selectedCrew.Name,
			selectedCrew.Rarity,
			selectedCrew.Level,
			selectedCrew.CurrentXP,
			selectedCrew.NextLevelXP,
			selectedCrew.ShipIncomePerHour
		)
		selectedCrewLabel.TextColor3 = rarityColors[selectedCrew.Rarity] or Color3.new(1, 1, 1)
	else
		selectedCrewLabel.Text = "Selected Crew: None"
		selectedCrewLabel.TextColor3 = Color3.new(1, 1, 1)
	end

	for _, foodKey in ipairs(foodOrder) do
		local count = tonumber(foodInventory[foodKey]) or 0
		local button = feedButtons[foodKey]
		button.Text = string.format("%s x%d", Economy.Food[foodKey].DisplayName, count)
		setButtonEnabled(button, selectedCrew ~= nil and count > 0)
	end

	for _, child in ipairs(crewList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	for _, crew in ipairs(crews) do
		local card = Instance.new("TextButton")
		card.AutoButtonColor = true
		card.Text = ""
		card.Size = UDim2.new(1, -8, 0, 62)
		card.BackgroundColor3 = if crew.InstanceId == selectedCrewId then Color3.fromRGB(31, 89, 119) else Color3.fromRGB(16, 50, 72)
		card.Parent = crewList
		card.ZIndex = 21
		createCorner(card, 12)
		createStroke(card, rarityColors[crew.Rarity] or Color3.fromRGB(140, 214, 255), 1.5, 0.25)

		local crewName = createLabel(card, crew.Name, UDim2.new(1, -16, 0, 20), UDim2.fromOffset(10, 8), 14)
		crewName.ZIndex = 22
		crewName.TextColor3 = rarityColors[crew.Rarity] or Color3.new(1, 1, 1)

		local crewMeta = createLabel(
			card,
			string.format("%s | Lv.%d | XP %d/%d | %d D/hr", crew.Rarity, crew.Level, crew.CurrentXP, crew.NextLevelXP, crew.ShipIncomePerHour),
			UDim2.new(1, -16, 0, 18),
			UDim2.fromOffset(10, 32),
			12
		)
		crewMeta.Font = Enum.Font.Gotham
		crewMeta.TextColor3 = Color3.fromRGB(197, 228, 243)
		crewMeta.ZIndex = 22

		card.MouseButton1Click:Connect(function()
			selectedCrewId = crew.InstanceId
			render()
		end)
	end

	setButtonEnabled(claimRewardButton, false)
	setButtonEnabled(extractButton, false)
	setButtonEnabled(failRunButton, false)
	setButtonEnabled(openChestButton, (currentState.UnopenedChestCount or 0) > 0)
	setButtonEnabled(startChestButton, false)
	setButtonEnabled(startCrewButton, false)
end

local function request(actionName, payload)
	if SAFE_CLIENT_ACTIONS[actionName] ~= true then
		setWorldInteractionMessage(actionName)
		return
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer(actionName, payload)
	end)

	if not ok then
		setMessage("Request failed: " .. tostring(response))
		return
	end

	if typeof(response) ~= "table" then
		setMessage("Unexpected response from slice service.")
		return
	end

	currentState = response.state or currentState
	if response.message then
		setMessage(response.message)
	elseif response.ok == false and response.error then
		setMessage("Action blocked: " .. tostring(response.error))
	end

	if response.ok == true and typeof(response.openResult) == "table" then
		PopUpModule:Local_ShowChestOpenResult(response.openResult)
	end

	render()
end

toggleButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

for depthBand, button in pairs(depthButtons) do
	button.MouseButton1Click:Connect(function()
		selectedDepthBand = depthBand
		render()
	end)
end

startCrewButton.MouseButton1Click:Connect(function()
	setWorldInteractionMessage("StartRun")
end)

claimRewardButton.MouseButton1Click:Connect(function()
	setWorldInteractionMessage("ClaimReward")
end)

extractButton.MouseButton1Click:Connect(function()
	setWorldInteractionMessage("ExtractRun")
end)

failRunButton.MouseButton1Click:Connect(function()
	setWorldInteractionMessage("FailRun")
end)

openChestButton.MouseButton1Click:Connect(function()
	local chestList = currentState and currentState.UnopenedChests or nil
	local firstChest = chestList and chestList[1]
	request("OpenChest", {
		ChestId = firstChest and firstChest.ChestId or nil,
	})
end)

for foodKey, button in pairs(feedButtons) do
	button.MouseButton1Click:Connect(function()
		if not selectedCrewId then
			setMessage("Select a crew member first.")
			return
		end

		request("FeedCrew", {
			CrewInstanceId = selectedCrewId,
			FoodKey = foodKey,
		})
	end)
end

stateRemote.OnClientEvent:Connect(function(newState)
	if typeof(newState) ~= "table" then
		return
	end

	currentState = newState
	render()
end)

request("GetState")
