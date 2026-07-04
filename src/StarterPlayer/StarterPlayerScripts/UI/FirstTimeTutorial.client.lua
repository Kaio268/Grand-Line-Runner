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
local STARTUP_GATE_TIMEOUT_SECONDS = 18

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
local startupGateStartedAt = os.clock()
local startupGateTimedOut = false

local tutorialRefs = {
	darkOverlay = nil,
	firstStepFrame = nil,
	normalStepsFrame = nil,
	finalStepFrame = nil,
	finalRewardFrame = nil,
	finalRewardPath = "",
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

local function setVisible(instance, visible)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible
		if visible ~= true then
			instance.Active = false
			instance.Selectable = false
		end
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

local function resolveOptionalGuiObject(parent, childName)
	local child = parent and parent:FindFirstChild(childName)
	if child and child:IsA("GuiObject") then
		return child
	end

	return nil
end

local function resolveFinalRewardFrame(tutorialRoot, finalStepFrame)
	local candidates = {
		{
			parent = tutorialRoot,
			name = "StepFinalRewards",
			path = "StepFinalRewards",
		},
		{
			parent = tutorialRoot,
			name = "StepFinalReward",
			path = "StepFinalReward",
		},
		{
			parent = finalStepFrame,
			name = "StepFinalRewards",
			path = "FinalStepFrame.StepFinalRewards",
		},
		{
			parent = finalStepFrame,
			name = "StepFinalReward",
			path = "FinalStepFrame.StepFinalReward",
		},
	}

	for _, candidate in ipairs(candidates) do
		local frame = resolveOptionalGuiObject(candidate.parent, candidate.name)
		if frame then
			return frame, candidate.path
		end
	end

	if finalStepFrame and finalStepFrame:FindFirstChild("ClaimRewards") then
		return finalStepFrame, "FinalStepFrame"
	end

	warnMissingGuiPath("StepFinalRewards or FinalStepFrame.ClaimRewards")
	return nil, ""
end

local function resolveTutorialGuiRefs()
	if not tutorialGui then
		return
	end

	local firstStepFrame = findGuiChild(tutorialGui, "FirstStepFrame", "FirstStepFrame")
	local normalStepsFrame = findGuiChild(tutorialGui, "NormalStepsFrame", "NormalStepsFrame")
	local finalStepFrame = tutorialGui:FindFirstChild("FinalStepFrame")
	if finalStepFrame and not finalStepFrame:IsA("GuiObject") then
		warnMissingGuiPath("FinalStepFrame (not a GuiObject)")
		finalStepFrame = nil
	end
	local finalRewardFrame, finalRewardPath = resolveFinalRewardFrame(tutorialGui, finalStepFrame)
	local welcomeStep = resolveStepFrame(firstStepFrame, "WelcomeStep", "FirstStepFrame.WelcomeStep")
	local step1Crewmate = resolveStepFrame(normalStepsFrame, "Step1_Crewmate", "NormalStepsFrame.Step1_Crewmate")
	local step2BringHome = resolveStepFrame(normalStepsFrame, "Step2_BringHome", "NormalStepsFrame.Step2_BringHome")
	local step3CollectBeli = resolveStepFrame(normalStepsFrame, "Step3_CollectBeli", "NormalStepsFrame.Step3_CollectBeli")
	local step4GetFaster = resolveStepFrame(normalStepsFrame, "Step4_GetFaster", "NormalStepsFrame.Step4_GetFaster")

	tutorialRefs.darkOverlay = findGuiChild(tutorialGui, "DarkOverlay", "DarkOverlay")
	tutorialRefs.firstStepFrame = firstStepFrame
	tutorialRefs.normalStepsFrame = normalStepsFrame
	tutorialRefs.finalStepFrame = finalStepFrame
	tutorialRefs.finalRewardFrame = finalRewardFrame
	tutorialRefs.finalRewardPath = finalRewardPath
	tutorialRefs.containersByStep = {
		[1] = firstStepFrame,
		[2] = normalStepsFrame,
		[3] = normalStepsFrame,
		[4] = normalStepsFrame,
		[5] = normalStepsFrame,
		[6] = finalRewardFrame,
	}
	tutorialRefs.stepsByIndex = {
		[1] = welcomeStep,
		[2] = step1Crewmate,
		[3] = step2BringHome,
		[4] = step3CollectBeli,
		[5] = step4GetFaster,
		[6] = finalRewardFrame,
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
		finalRewardFrame,
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

local function cleanupCompletedTutorialUi()
	hideTutorialFrames()
	if tutorialGui then
		local darkOverlay = tutorialGui:FindFirstChild("DarkOverlay")
		if darkOverlay and darkOverlay:IsA("GuiObject") then
			darkOverlay.Visible = false
		end
		tutorialGui.Enabled = false
	end
	objectiveController:Clear()
end

local function applyTutorialGuiState(state)
	if not tutorialGui then
		return
	end

	local active = state and state.active == true and state.completed ~= true
	if not active then
		cleanupCompletedTutorialUi()
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
local requestClaimRewards
local requestSkip
local scheduleRender

local function hasNumericValue(parent, childName)
	local child = parent and parent:FindFirstChild(childName)
	return child ~= nil and child:IsA("ValueBase") and typeof(child.Value) == "number"
end

local function isStartupReadyForTutorial()
	if startupGateTimedOut then
		return true
	end

	local loadingComplete = playerGui:GetAttribute("LoadingScreenComplete") == true
		or player:GetAttribute("LoadingScreenComplete") == true
	local hudReady = playerGui:GetAttribute("StartupHudReady") == true
		or player:GetAttribute("StartupHudReady") == true
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local leaderstats = player:FindFirstChild("leaderstats")
	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")

	if loadingComplete and hudReady and root and humanoid and hasNumericValue(leaderstats, "Beli") and hasNumericValue(hiddenLeaderstats, "Speed") then
		return true
	end

	if os.clock() - startupGateStartedAt >= STARTUP_GATE_TIMEOUT_SECONDS then
		startupGateTimedOut = true
		warn("[FirstTimeTutorial] Startup readiness timed out; showing tutorial with available dependencies.")
		return true
	end

	return false
end

local function refreshStartupGate()
	if scheduleRender then
		scheduleRender()
	end
	if requestRemote and not requestedInitialState and isStartupReadyForTutorial() then
		requestedInitialState = true
		requestState()
	end
end

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

local function findFinalRewardButton(stepFrame)
	local finalRewardPath = if tutorialRefs.finalRewardPath ~= "" then tutorialRefs.finalRewardPath else "StepFinalRewards"
	local claimRewards = findGuiChild(stepFrame, "ClaimRewards", finalRewardPath .. ".ClaimRewards")
	if claimRewards and claimRewards:IsA("GuiButton") then
		return claimRewards
	end
	if claimRewards and not claimRewards:IsA("GuiObject") then
		warnMissingGuiPath(finalRewardPath .. ".ClaimRewards (not a GuiObject)")
		return nil
	end

	local buttonFrame = findGuiChild(claimRewards, "ButtonFrame", finalRewardPath .. ".ClaimRewards.ButtonFrame")
	local setSailButton = findGuiChild(buttonFrame, "SetSailButton", finalRewardPath .. ".ClaimRewards.ButtonFrame.SetSailButton")
	if setSailButton and setSailButton:IsA("GuiButton") then
		return setSailButton
	end
	if setSailButton then
		warnMissingGuiPath(finalRewardPath .. ".ClaimRewards.ButtonFrame.SetSailButton (not a GuiButton)")
	end

	return nil
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

	local finalRewardStep = tutorialRefs.stepsByIndex[6]
	connectButtonOnce(connectedButtons, findFinalRewardButton(finalRewardStep), function()
		requestClaimRewards()
	end)
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

		if not isStartupReadyForTutorial() then
			cleanupCompletedTutorialUi()
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

	cleanupCompletedTutorialUi()

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

requestClaimRewards = function()
	if advanceRequestInFlight then
		return
	end

	if not requestRemote then
		PopUpModule:Local_SendPopUp("Tutorial service is starting.", Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
		return
	end

	advanceRequestInFlight = true
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("ClaimCompletionRewards")
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
		PopUpModule:Local_SendPopUp("Tutorial reward claim failed.", Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
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
		refreshStartupGate()
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

for _, attributeName in ipairs({ "LoadingScreenComplete", "StartupHudReady" }) do
	table.insert(cleanupConnections, playerGui:GetAttributeChangedSignal(attributeName):Connect(refreshStartupGate))
	table.insert(cleanupConnections, player:GetAttributeChangedSignal(attributeName):Connect(refreshStartupGate))
end

table.insert(cleanupConnections, player.ChildAdded:Connect(function(child)
	if child.Name == "leaderstats" or child.Name == "HiddenLeaderstats" then
		refreshStartupGate()
		table.insert(cleanupConnections, child.ChildAdded:Connect(refreshStartupGate))
	end
end))

table.insert(cleanupConnections, player.CharacterAdded:Connect(function(character)
	refreshStartupGate()
	table.insert(cleanupConnections, character.ChildAdded:Connect(refreshStartupGate))
end))

local existingLeaderstats = player:FindFirstChild("leaderstats")
if existingLeaderstats then
	table.insert(cleanupConnections, existingLeaderstats.ChildAdded:Connect(refreshStartupGate))
end
local existingHiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
if existingHiddenLeaderstats then
	table.insert(cleanupConnections, existingHiddenLeaderstats.ChildAdded:Connect(refreshStartupGate))
end
if player.Character then
	table.insert(cleanupConnections, player.Character.ChildAdded:Connect(refreshStartupGate))
end
task.delay(STARTUP_GATE_TIMEOUT_SECONDS, refreshStartupGate)

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
	cleanupCompletedTutorialUi()
	objectiveController:Destroy()
end)
