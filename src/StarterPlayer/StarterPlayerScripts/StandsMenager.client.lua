local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local remote = remotes:WaitForChild("StandUpgradeRemote")
local previewRemote = remotes:WaitForChild("StandUpgradePreviewRemote")
local resultRemote = remotes:WaitForChild("StandUpgradeStepResultRemote")
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local POPUP_ERROR = Color3.fromRGB(255, 94, 94)
local POPUP_INFO = Color3.fromRGB(111, 188, 255)
local POPUP_STROKE = Color3.fromRGB(0, 0, 0)

local connections = {}
local screenGui
local panel
local accentLabel
local titleLabel
local bodyLabel
local confirmButton
local cancelButton

local pendingPreview
local awaitingResultStandName
local scheduledPromptId = 0
local approvedFoodSessions = {}

local function clearApprovedFoodSession(standName)
	if typeof(standName) ~= "string" or standName == "" then
		return
	end
	approvedFoodSessions[standName] = nil
end

local function getApprovedFoodSession(standName, instanceId)
	local session = approvedFoodSessions[standName]
	if not session then
		return nil
	end

	if tostring(session.InstanceId or "") ~= tostring(instanceId or "") then
		approvedFoodSessions[standName] = nil
		return nil
	end

	return session
end

local function setApprovedFoodSession(standName, instanceId, foodKey, foodDisplayName)
	if typeof(standName) ~= "string" or standName == "" then
		return
	end

	approvedFoodSessions[standName] = {
		InstanceId = tostring(instanceId or ""),
		FoodKey = tostring(foodKey or ""),
		FoodDisplayName = tostring(foodDisplayName or foodKey or ""),
	}
end

local function hidePrompt()
	if panel then
		panel.Visible = false
	end
	pendingPreview = nil
end

local function sendLocalPopup(text, color, isError)
	PopUpModule:Local_SendPopUp(text, color or POPUP_INFO, POPUP_STROKE, 3, isError == true)
end

local function ensurePromptGui()
	if screenGui and screenGui.Parent then
		return
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "StandUpgradeConfirmPrompt"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 50
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(430, 235)
	panel.BackgroundColor3 = Color3.fromRGB(20, 18, 16)
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 147, 54)
	stroke.Transparency = 0.2
	stroke.Thickness = 1.5
	stroke.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 16)
	padding.PaddingBottom = UDim.new(0, 18)
	padding.PaddingLeft = UDim.new(0, 18)
	padding.PaddingRight = UDim.new(0, 18)
	padding.Parent = panel

	accentLabel = Instance.new("TextLabel")
	accentLabel.Name = "Accent"
	accentLabel.BackgroundTransparency = 1
	accentLabel.Size = UDim2.new(1, 0, 0, 18)
	accentLabel.Font = Enum.Font.GothamBold
	accentLabel.Text = "BRAINROT UPGRADE"
	accentLabel.TextColor3 = Color3.fromRGB(255, 178, 92)
	accentLabel.TextSize = 14
	accentLabel.TextXAlignment = Enum.TextXAlignment.Left
	accentLabel.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0, 0, 0, 24)
	titleLabel.Size = UDim2.new(1, 0, 0, 30)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Use Food?"
	titleLabel.TextColor3 = Color3.fromRGB(255, 241, 229)
	titleLabel.TextSize = 24
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

	bodyLabel = Instance.new("TextLabel")
	bodyLabel.Name = "Body"
	bodyLabel.BackgroundTransparency = 1
	bodyLabel.Position = UDim2.new(0, 0, 0, 64)
	bodyLabel.Size = UDim2.new(1, 0, 0, 102)
	bodyLabel.Font = Enum.Font.Gotham
	bodyLabel.Text = ""
	bodyLabel.TextColor3 = Color3.fromRGB(232, 223, 216)
	bodyLabel.TextSize = 18
	bodyLabel.TextWrapped = true
	bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
	bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
	bodyLabel.Parent = panel

	confirmButton = Instance.new("TextButton")
	confirmButton.Name = "Confirm"
	confirmButton.AnchorPoint = Vector2.new(0, 1)
	confirmButton.Position = UDim2.new(0, 0, 1, 0)
	confirmButton.Size = UDim2.fromOffset(180, 44)
	confirmButton.BackgroundColor3 = Color3.fromRGB(255, 138, 44)
	confirmButton.BorderSizePixel = 0
	confirmButton.Font = Enum.Font.GothamBold
	confirmButton.Text = "Use"
	confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	confirmButton.TextSize = 18
	confirmButton.Parent = panel

	local confirmCorner = Instance.new("UICorner")
	confirmCorner.CornerRadius = UDim.new(0, 10)
	confirmCorner.Parent = confirmButton

	cancelButton = Instance.new("TextButton")
	cancelButton.Name = "Cancel"
	cancelButton.AnchorPoint = Vector2.new(1, 1)
	cancelButton.Position = UDim2.new(1, 0, 1, 0)
	cancelButton.Size = UDim2.fromOffset(180, 44)
	cancelButton.BackgroundColor3 = Color3.fromRGB(46, 42, 39)
	cancelButton.BorderSizePixel = 0
	cancelButton.Font = Enum.Font.GothamBold
	cancelButton.Text = "Cancel"
	cancelButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	cancelButton.TextSize = 18
	cancelButton.Parent = panel

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 10)
	cancelCorner.Parent = cancelButton

	cancelButton.MouseButton1Click:Connect(function()
		if pendingPreview then
			clearApprovedFoodSession(pendingPreview.StandName)
		end
		hidePrompt()
	end)

	confirmButton.MouseButton1Click:Connect(function()
		if not pendingPreview or awaitingResultStandName then
			return
		end

		local preview = pendingPreview
		awaitingResultStandName = preview.StandName
		setApprovedFoodSession(
			preview.StandName,
			preview.InstanceId,
			preview.Step.FoodKey,
			preview.Step.FoodDisplayName
		)
		hidePrompt()

		remote:FireServer({
			StandName = preview.StandName,
			ExpectedFoodKey = preview.Step.FoodKey,
		})
	end)
end

local function showPreviewPrompt(standName, step, priorFoodDisplayName)
	if typeof(standName) ~= "string" or standName == "" or typeof(step) ~= "table" then
		return
	end

	ensurePromptGui()

	local foodDisplayName = tostring(step.FoodDisplayName or step.FoodKey or "Food")
	local amountUsed = math.max(0, math.floor(tonumber(step.AmountUsed) or 0))
	local xpGained = math.max(0, math.floor(tonumber(step.XPGained) or 0))
	local hasPriorFood = typeof(priorFoodDisplayName) == "string" and priorFoodDisplayName ~= ""

	pendingPreview = {
		StandName = standName,
		Step = step,
		PriorFoodDisplayName = priorFoodDisplayName,
		InstanceId = tostring(step.InstanceId or ""),
	}

	if hasPriorFood then
		titleLabel.Text = string.format("Use %s next?", foodDisplayName)
		bodyLabel.Text = table.concat({
			string.format("%s has run out.", priorFoodDisplayName),
			string.format("The next food is %s.", foodDisplayName),
			"",
			string.format("%dx %s will be consumed for +%d XP.", amountUsed, foodDisplayName, xpGained),
		}, "\n")
	else
		titleLabel.Text = string.format("Use %s?", foodDisplayName)
		bodyLabel.Text = table.concat({
			string.format("Are you sure you want to use %s to upgrade this brainrot?", foodDisplayName),
			"",
			string.format("%dx %s will be consumed for +%d XP.", amountUsed, foodDisplayName, xpGained),
		}, "\n")
	end

	confirmButton.Text = string.format("Use %s", foodDisplayName)
	cancelButton.Text = "Cancel"
	panel.Visible = true
end

local function scheduleNextPrompt(standName, step, priorFoodDisplayName)
	scheduledPromptId += 1
	local promptId = scheduledPromptId

	task.delay(0.15, function()
		if scheduledPromptId ~= promptId then
			return
		end
		showPreviewPrompt(standName, step, priorFoodDisplayName)
	end)
end

local function requestPreview(standName, priorFoodDisplayName)
	if typeof(standName) ~= "string" or standName == "" then
		return
	end

	ensurePromptGui()
	scheduledPromptId += 1

	local ok, response = pcall(function()
		return previewRemote:InvokeServer(standName)
	end)

	if not ok then
		sendLocalPopup("Unable to preview the next food step right now.", POPUP_ERROR, true)
		return
	end

	if typeof(response) ~= "table" or response.Ok ~= true or typeof(response.Step) ~= "table" then
		sendLocalPopup(
			tostring(response and response.Message or "Unable to preview the next food step right now."),
			POPUP_ERROR,
			true
		)
		return
	end

	local instanceId = tostring(response.Progress and response.Progress.InstanceId or "")
	local approvedSession = getApprovedFoodSession(standName, instanceId)
	if approvedSession and tostring(approvedSession.FoodKey or "") == tostring(response.Step.FoodKey or "") then
		awaitingResultStandName = standName
		remote:FireServer({
			StandName = standName,
			ExpectedFoodKey = response.Step.FoodKey,
		})
		return
	end

	response.Step.InstanceId = instanceId
	showPreviewPrompt(standName, response.Step, priorFoodDisplayName)
end

local function disconnectGui(name)
	local connection = connections[name]
	if connection then
		connection:Disconnect()
		connections[name] = nil
	end
end

local function isStandSurfaceGui(gui)
	return gui
		and gui:IsA("SurfaceGui")
		and tonumber(gui.Name) ~= nil
end

local function getOrCreateUpgradeButton(gui)
	local button = gui:FindFirstChildWhichIsA("GuiButton", true)
	if button then
		return button
	end

	local root = gui:FindFirstChild("LevelUp", true)
		or gui:FindFirstChild("Main", true)
		or gui:FindFirstChildWhichIsA("GuiObject", true)
	if not root then
		return nil
	end

	local overlay = root:FindFirstChild("UpgradeHitbox")
	if overlay and overlay:IsA("TextButton") then
		return overlay
	end

	overlay = Instance.new("TextButton")
	overlay.Name = "UpgradeHitbox"
	overlay.AutoButtonColor = false
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.Text = ""
	overlay.ZIndex = root.ZIndex + 10
	overlay.Parent = root

	return overlay
end

local function bindGui(gui)
	if not isStandSurfaceGui(gui) then
		return
	end

	disconnectGui(gui)

	local button = getOrCreateUpgradeButton(gui)
	if not button then
		return
	end

	connections[gui] = button.Activated:Connect(function()
		if awaitingResultStandName then
			return
		end
		requestPreview(gui.Name, nil)
	end)
end

resultRemote.OnClientEvent:Connect(function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	local standName = tostring(payload.StandName or "")
	if standName ~= "" and awaitingResultStandName ~= standName then
		return
	end

	awaitingResultStandName = nil

	if payload.Ok == true then
		local continuePreview = payload.ContinuePreview
		local appliedStep = payload.AppliedStep
		local levelUps = math.max(0, math.floor(tonumber(payload.LevelUps) or 0))
		local instanceId = tostring(payload.Progress and payload.Progress.InstanceId or "")

		if appliedStep then
			setApprovedFoodSession(
				standName,
				instanceId,
				appliedStep.FoodKey,
				appliedStep.FoodDisplayName
			)
		end

		if typeof(continuePreview) == "table" then
			continuePreview.InstanceId = instanceId
			local approvedSession = getApprovedFoodSession(standName, instanceId)
			local approvedFoodKey = approvedSession and tostring(approvedSession.FoodKey or "") or ""
			local nextFoodKey = tostring(continuePreview.FoodKey or "")

			if approvedFoodKey ~= "" and approvedFoodKey ~= nextFoodKey then
				local priorFoodDisplayName = appliedStep and tostring(appliedStep.FoodDisplayName or appliedStep.FoodKey or "") or ""
				scheduleNextPrompt(standName, continuePreview, priorFoodDisplayName)
			end
		else
			clearApprovedFoodSession(standName)
		end
		return
	end

	if payload.Error == "step_changed" and typeof(payload.Step) == "table" then
		clearApprovedFoodSession(standName)
		scheduleNextPrompt(standName, payload.Step, nil)
		return
	end

	clearApprovedFoodSession(standName)
end)

playerGui.DescendantAdded:Connect(function(gui)
	bindGui(gui)
end)

playerGui.DescendantRemoving:Connect(function(gui)
	if isStandSurfaceGui(gui) then
		disconnectGui(gui)
	end
end)

for _, gui in ipairs(playerGui:GetDescendants()) do
	bindGui(gui)
end
