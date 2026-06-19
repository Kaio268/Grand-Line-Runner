local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local TutorialConfig = require(Modules:WaitForChild("Configs"):WaitForChild("FirstTimeTutorial"))
local TutorialObjectiveIndicatorController = require(script.Parent:WaitForChild("TutorialObjectiveIndicatorController"))

local REQUEST_REMOTE_NAME = TutorialConfig.Remotes.RequestName
local STATE_REMOTE_NAME = TutorialConfig.Remotes.StateName
local TUTORIAL_GUI_NAME = "FirstTimeTutorialGui"
local OBJECTIVE_GUI_NAME = "FirstTimeTutorialObjectiveGui"
local TUTORIAL_GUI_TIMEOUT_SECONDS = 10

local tutorialGui = playerGui:FindFirstChild(TUTORIAL_GUI_NAME)
if not tutorialGui then
	tutorialGui = playerGui:WaitForChild(TUTORIAL_GUI_NAME, TUTORIAL_GUI_TIMEOUT_SECONDS)
end
if tutorialGui and not tutorialGui:IsA("ScreenGui") then
	if game:GetAttribute("TutorialMissingUiWarnings") == true then
		warn("[FirstTimeTutorial] PlayerGui.FirstTimeTutorialGui is not a ScreenGui; tutorial UI cannot render.")
	end
	tutorialGui = nil
end

local objectiveController = TutorialObjectiveIndicatorController.new(playerGui, {
	Name = OBJECTIVE_GUI_NAME,
	DisplayOrder = 181,
	ZIndex = 184,
})

local destroyed = false
local renderQueued = false
local tutorialState = nil
local cleanupConnections = {}
local buttonConnections = {}
local remotes = nil
local requestRemote = nil
local stateRemote = nil
local stateRemoteConnection = nil
local remotesChildConnection = nil
local requestedInitialState = false
local advanceRequestInFlight = false
local skipRequestInFlight = false

local tutorialRefs = {
	darkOverlay = nil,
	firstStepFrame = nil,
	normalStepsFrame = nil,
	finalStepFrame = nil,
	containersByStep = {},
	stepsByIndex = {},
	allFrames = {},
}

local warnedMissingGuiPath = {}

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
end

local function disconnectButtonConnections()
	for _, connection in ipairs(buttonConnections) do
		connection:Disconnect()
	end
	table.clear(buttonConnections)
end

local function warnMissingGuiPath(path)
	if warnedMissingGuiPath[path] then
		return
	end
	warnedMissingGuiPath[path] = true
	if game:GetAttribute("TutorialMissingUiWarnings") == true then
		warn(string.format("[FirstTimeTutorial] Missing PlayerGui.FirstTimeTutorialGui.%s.", path))
	end
end

local function findGuiChild(parent, childName, path)
	if not parent then
		warnMissingGuiPath(path)
		return nil
	end

	local child = parent:FindFirstChild(childName)
	if not child then
		warnMissingGuiPath(path)
		return nil
	end

	return child
end

local function findDescendantGuiButtons(parent, buttonName)
	local buttons = {}
	if not parent or tostring(buttonName or "") == "" then
		return buttons
	end

	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant.Name == buttonName and descendant:IsA("GuiButton") then
			buttons[#buttons + 1] = descendant
		end
	end

	return buttons
end

local function findFirstActionButton(parent, excludedNames)
	if not parent then
		return nil
	end

	excludedNames = excludedNames or {}
	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant:IsA("GuiButton") and not excludedNames[descendant.Name] then
			return descendant
		end
	end

	return nil
end

local function setVisible(instance, visible)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

local function resolveStepFrame(container, stepName, path)
	local stepFrame = findGuiChild(container, stepName, path)
	if stepFrame and not stepFrame:IsA("GuiObject") then
		warnMissingGuiPath(path .. " (not a GuiObject)")
		return nil
	end
	return stepFrame
end

local function resolveTutorialGuiRefs()
	if not tutorialGui then
		return
	end

	local firstStepFrame = findGuiChild(tutorialGui, "FirstStepFrame", "FirstStepFrame")
	local normalStepsFrame = findGuiChild(tutorialGui, "NormalStepsFrame", "NormalStepsFrame")
	local finalStepFrame = findGuiChild(tutorialGui, "FinalStepFrame", "FinalStepFrame")
	local welcomeStep = resolveStepFrame(firstStepFrame, "WelcomeStep", "FirstStepFrame.WelcomeStep")
	local step1Crewmate = resolveStepFrame(normalStepsFrame, "Step1_Crewmate", "NormalStepsFrame.Step1_Crewmate")
	local step2BringHome = resolveStepFrame(normalStepsFrame, "Step2_BringHome", "NormalStepsFrame.Step2_BringHome")
	local step3CollectBeli = resolveStepFrame(normalStepsFrame, "Step3_CollectBeli", "NormalStepsFrame.Step3_CollectBeli")
	local step4GetFaster = resolveStepFrame(normalStepsFrame, "Step4_GetFaster", "NormalStepsFrame.Step4_GetFaster")

	tutorialRefs.darkOverlay = findGuiChild(tutorialGui, "DarkOverlay", "DarkOverlay")
	tutorialRefs.firstStepFrame = firstStepFrame
	tutorialRefs.normalStepsFrame = normalStepsFrame
	tutorialRefs.finalStepFrame = finalStepFrame
	tutorialRefs.containersByStep = {
		[1] = firstStepFrame,
		[2] = normalStepsFrame,
		[3] = normalStepsFrame,
		[4] = normalStepsFrame,
		[5] = normalStepsFrame,
		[6] = finalStepFrame,
	}
	tutorialRefs.stepsByIndex = {
		[1] = welcomeStep,
		[2] = step1Crewmate,
		[3] = step2BringHome,
		[4] = step3CollectBeli,
		[5] = step4GetFaster,
		[6] = finalStepFrame,
	}
	tutorialRefs.allFrames = {
		firstStepFrame,
		welcomeStep,
		normalStepsFrame,
		step1Crewmate,
		step2BringHome,
		step3CollectBeli,
		step4GetFaster,
		finalStepFrame,
	}
end

local function hideTutorialFrames()
	if not tutorialGui then
		return
	end

	setVisible(tutorialRefs.darkOverlay, false)

	for _, frame in ipairs(tutorialRefs.allFrames) do
		setVisible(frame, false)
	end
end

local function applyTutorialGuiState(state)
	if not tutorialGui then
		return
	end

	local active = state and state.active == true and state.completed ~= true
	if not active then
		hideTutorialFrames()
		tutorialGui.Enabled = false
		return
	end

	local stepIndex = math.clamp(math.floor(tonumber(state.stepIndex) or 0), 1, TutorialConfig.GetStepCount())
	local container = tutorialRefs.containersByStep[stepIndex]
	local stepFrame = tutorialRefs.stepsByIndex[stepIndex]

	tutorialGui.Enabled = true
	hideTutorialFrames()
	setVisible(tutorialRefs.darkOverlay, true)
	setVisible(container, true)
	if stepFrame ~= container then
		setVisible(stepFrame, true)
	end
end

local requestState
local refreshRemotes
local bindRemotesFolder
local requestAdvance
local requestSkip
local scheduleRender

local function connectButton(button, callback)
	if button and button:IsA("GuiButton") then
		table.insert(buttonConnections, button.Activated:Connect(callback))
	end
end

local function findButtonInButtonFrame(stepFrame, buttonName, path)
	local buttonFrame = findGuiChild(stepFrame, "ButtonFrame", path .. ".ButtonFrame")
	local button = findGuiChild(buttonFrame, buttonName, path .. ".ButtonFrame." .. buttonName)
	if button and not button:IsA("GuiButton") then
		warnMissingGuiPath(path .. ".ButtonFrame." .. buttonName .. " (not a GuiButton)")
		return nil
	end
	return button
end

local function connectButtonOnce(connectedButtons, button, callback)
	if not button or connectedButtons[button] == true then
		return
	end

	connectedButtons[button] = true
	connectButton(button, callback)
end

local function connectSkipButton(connectedButtons, stepFrame)
	for _, skipButton in ipairs(findDescendantGuiButtons(stepFrame, "SkipButton")) do
		connectButtonOnce(connectedButtons, skipButton, function()
			requestSkip()
		end)
	end
end

local function connectTutorialButtons()
	disconnectButtonConnections()
	if not tutorialGui then
		return
	end

	local connectedButtons = {}
	local welcomeStep = tutorialRefs.stepsByIndex[1]
	connectButtonOnce(
		connectedButtons,
		findButtonInButtonFrame(welcomeStep, "StartTutorialButton", "FirstStepFrame.WelcomeStep"),
		function()
			requestAdvance()
		end
	)
	connectSkipButton(connectedButtons, welcomeStep)

	for stepIndex = 2, 5 do
		connectSkipButton(connectedButtons, tutorialRefs.stepsByIndex[stepIndex])
	end

	local finalStep = tutorialRefs.stepsByIndex[6]
	local finalButton = findFirstActionButton(finalStep, {
		SkipButton = true,
	})
	connectButtonOnce(connectedButtons, finalButton, function()
		requestAdvance()
	end)
	connectSkipButton(connectedButtons, finalStep)
end

local function initializeTutorialGui(nextGui)
	if not nextGui or not nextGui:IsA("ScreenGui") then
		return false
	end

	tutorialGui = nextGui
	tutorialGui.DisplayOrder = 180
	tutorialGui.IgnoreGuiInset = true
	tutorialGui.ResetOnSpawn = false
	tutorialGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	tutorialGui.Enabled = false

	resolveTutorialGuiRefs()
	hideTutorialFrames()
	connectTutorialButtons()
	scheduleRender()

	return true
end

local function renderObjectiveIndicator(state)
	local active = state and state.active == true and state.completed ~= true
	local hasTarget = active and typeof(state.target) == "table"

	if hasTarget then
		objectiveController:SetTarget(state.target, {
			ShowPath = true,
			ZIndex = 184,
		})
	else
		objectiveController:Clear()
	end
end

scheduleRender = function()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if destroyed then
			return
		end

		applyTutorialGuiState(tutorialState)
		renderObjectiveIndicator(tutorialState)
	end)
end

requestSkip = function()
	if skipRequestInFlight then
		return
	end

	hideTutorialFrames()
	if tutorialGui then
		tutorialGui.Enabled = false
	end
	objectiveController:Clear()

	if not requestRemote then
		PopUpModule:Local_SendPopUp("Tutorial service is starting.", Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
		return
	end

	skipRequestInFlight = true
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("Skip")
	end)
	skipRequestInFlight = false

	if ok and typeof(response) == "table" then
		if typeof(response.state) == "table" then
			tutorialState = response.state
			scheduleRender()
		end
		if response.success ~= true and response.message then
			PopUpModule:Local_SendPopUp(tostring(response.message), Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
		end
	else
		PopUpModule:Local_SendPopUp("Tutorial skip failed.", Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
	end
end

requestAdvance = function()
	if advanceRequestInFlight then
		return
	end

	if not requestRemote then
		PopUpModule:Local_SendPopUp("Tutorial service is starting.", Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
		return
	end

	advanceRequestInFlight = true
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("Advance")
	end)
	advanceRequestInFlight = false

	if ok and typeof(response) == "table" then
		if typeof(response.state) == "table" then
			tutorialState = response.state
			scheduleRender()
		end
		local stateWarning = if typeof(response.state) == "table" then tostring(response.state.warning or "") else ""
		if response.success ~= true and response.message and tostring(response.message) ~= stateWarning then
			PopUpModule:Local_SendPopUp(tostring(response.message), Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
		end
	else
		PopUpModule:Local_SendPopUp("Tutorial request failed.", Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
	end
end

requestState = function()
	if not requestRemote then
		return
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer("GetState")
	end)

	if ok and typeof(response) == "table" and typeof(response.state) == "table" then
		tutorialState = response.state
		scheduleRender()
	end
end

local function bindStateRemote(remote)
	if stateRemote == remote then
		return
	end

	if stateRemoteConnection then
		stateRemoteConnection:Disconnect()
		stateRemoteConnection = nil
	end

	stateRemote = remote
	stateRemoteConnection = remote.OnClientEvent:Connect(function(nextState)
		if typeof(nextState) ~= "table" then
			return
		end

		tutorialState = nextState
		scheduleRender()
	end)
	table.insert(cleanupConnections, stateRemoteConnection)
end

refreshRemotes = function()
	if not remotes then
		return
	end

	local foundRequest = remotes:FindFirstChild(REQUEST_REMOTE_NAME)
	if foundRequest and foundRequest:IsA("RemoteFunction") then
		requestRemote = foundRequest
	end

	local foundState = remotes:FindFirstChild(STATE_REMOTE_NAME)
	if foundState and foundState:IsA("RemoteEvent") then
		bindStateRemote(foundState)
	end

	if requestRemote and not requestedInitialState then
		requestedInitialState = true
		requestState()
	end
end

bindRemotesFolder = function(folder)
	if not folder or folder.Name ~= "Remotes" then
		return
	end

	if remotes == folder then
		refreshRemotes()
		return
	end

	if remotesChildConnection then
		remotesChildConnection:Disconnect()
		remotesChildConnection = nil
	end

	remotes = folder
	remotesChildConnection = folder.ChildAdded:Connect(function(child)
		if child.Name == REQUEST_REMOTE_NAME or child.Name == STATE_REMOTE_NAME then
			task.defer(refreshRemotes)
		end
	end)
	table.insert(cleanupConnections, remotesChildConnection)

	refreshRemotes()
end

if not initializeTutorialGui(tutorialGui) and game:GetAttribute("TutorialMissingUiWarnings") == true then
	warn("[FirstTimeTutorial] Missing PlayerGui.FirstTimeTutorialGui; tutorial UI cannot render.")
end

table.insert(cleanupConnections, playerGui.ChildAdded:Connect(function(child)
	if child.Name == TUTORIAL_GUI_NAME and child:IsA("ScreenGui") then
		initializeTutorialGui(child)
	end
end))

local existingRemotes = ReplicatedStorage:FindFirstChild("Remotes")
if existingRemotes then
	bindRemotesFolder(existingRemotes)
end

table.insert(cleanupConnections, ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "Remotes" then
		bindRemotesFolder(child)
	end
end))

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	disconnectButtonConnections()
	hideTutorialFrames()
	if tutorialGui then
		tutorialGui.Enabled = false
	end
	objectiveController:Destroy()
end)
