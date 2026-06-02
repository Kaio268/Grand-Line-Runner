local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local TutorialConfig = require(Modules:WaitForChild("Configs"):WaitForChild("FirstTimeTutorial"))
local ObjectiveIndicator = require(UiFolder:WaitForChild("Tutorial"):WaitForChild("ObjectiveIndicator"))

local REQUEST_REMOTE_NAME = TutorialConfig.Remotes.RequestName
local STATE_REMOTE_NAME = TutorialConfig.Remotes.StateName
local TUTORIAL_GUI_NAME = "FirstTimeTutorialGui"
local OBJECTIVE_GUI_NAME = "FirstTimeTutorialObjectiveGui"
local TUTORIAL_GUI_TIMEOUT_SECONDS = 10

local tutorialGui = playerGui:WaitForChild(TUTORIAL_GUI_NAME, TUTORIAL_GUI_TIMEOUT_SECONDS)
if not tutorialGui or not tutorialGui:IsA("ScreenGui") then
	warn("[FirstTimeTutorial] Missing PlayerGui.FirstTimeTutorialGui; tutorial UI cannot render.")
	tutorialGui = nil
else
	tutorialGui.DisplayOrder = 180
	tutorialGui.IgnoreGuiInset = true
	tutorialGui.ResetOnSpawn = false
	tutorialGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	tutorialGui.Enabled = false
end

local objectiveGui = Instance.new("ScreenGui")
objectiveGui.Name = OBJECTIVE_GUI_NAME
objectiveGui.DisplayOrder = 181
objectiveGui.IgnoreGuiInset = true
objectiveGui.ResetOnSpawn = false
objectiveGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
objectiveGui.Enabled = false
objectiveGui.Parent = playerGui

local objectiveRoot = ReactRoblox.createRoot(objectiveGui)

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
local skipRequestInFlight = false

local tutorialRefs = {
	darkOverlay = nil,
	containersByStep = {},
	stepsByIndex = {},
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
	warn(string.format("[FirstTimeTutorial] Missing PlayerGui.FirstTimeTutorialGui.%s.", path))
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

	tutorialRefs.darkOverlay = findGuiChild(tutorialGui, "DarkOverlay", "DarkOverlay")
	tutorialRefs.containersByStep = {
		[1] = firstStepFrame,
		[2] = normalStepsFrame,
		[3] = normalStepsFrame,
		[4] = normalStepsFrame,
		[5] = normalStepsFrame,
		[6] = normalStepsFrame,
		[7] = normalStepsFrame,
		[8] = finalStepFrame,
	}
	tutorialRefs.stepsByIndex = {
		[1] = resolveStepFrame(firstStepFrame, "Step1_Welcome", "FirstStepFrame.Step1_Welcome"),
		[2] = resolveStepFrame(normalStepsFrame, "Step2_Footing", "NormalStepsFrame.Step2_Footing"),
		[3] = resolveStepFrame(normalStepsFrame, "Step3_Crewmate", "NormalStepsFrame.Step3_Crewmate"),
		[4] = resolveStepFrame(normalStepsFrame, "Step4_BringHome", "NormalStepsFrame.Step4_BringHome"),
		[5] = resolveStepFrame(normalStepsFrame, "Step5_PutToWork", "NormalStepsFrame.Step5_PutToWork"),
		[6] = resolveStepFrame(normalStepsFrame, "Step6_CollectBeli", "NormalStepsFrame.Step6_CollectBeli"),
		[7] = resolveStepFrame(normalStepsFrame, "Step7_GetFaster", "NormalStepsFrame.Step7_GetFaster"),
		[8] = resolveStepFrame(finalStepFrame, "Step8_SetSail", "FinalStepFrame.Step8_SetSail"),
	}
end

local function hideTutorialFrames()
	if not tutorialGui then
		return
	end

	setVisible(tutorialRefs.darkOverlay, false)

	local hiddenContainers = {}
	for _, container in pairs(tutorialRefs.containersByStep) do
		if container and not hiddenContainers[container] then
			hiddenContainers[container] = true
			setVisible(container, false)
		end
	end

	for _, stepFrame in pairs(tutorialRefs.stepsByIndex) do
		setVisible(stepFrame, false)
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
	setVisible(stepFrame, true)
end

local requestState
local refreshRemotes
local bindRemotesFolder
local requestAdvance
local requestSkip

local function connectButton(button, callback)
	if button and button:IsA("GuiButton") then
		table.insert(buttonConnections, button.Activated:Connect(callback))
	end
end

local function findButton(stepFrame, buttonName, path)
	local buttonFrame = findGuiChild(stepFrame, "ButtonFrame", path .. ".ButtonFrame")
	local button = findGuiChild(buttonFrame, buttonName, path .. ".ButtonFrame." .. buttonName)
	if button and not button:IsA("GuiButton") then
		warnMissingGuiPath(path .. ".ButtonFrame." .. buttonName .. " (not a GuiButton)")
		return nil
	end
	return button
end

local function connectTutorialButtons()
	disconnectButtonConnections()
	if not tutorialGui then
		return
	end

	local step1 = tutorialRefs.stepsByIndex[1]
	connectButton(findButton(step1, "StartButton", "FirstStepFrame.Step1_Welcome"), function()
		requestAdvance()
	end)
	connectButton(findButton(step1, "SkipButton", "FirstStepFrame.Step1_Welcome"), function()
		requestSkip()
	end)

	for stepIndex = 2, 7 do
		local stepFrame = tutorialRefs.stepsByIndex[stepIndex]
		local pathByStep = {
			[2] = "NormalStepsFrame.Step2_Footing",
			[3] = "NormalStepsFrame.Step3_Crewmate",
			[4] = "NormalStepsFrame.Step4_BringHome",
			[5] = "NormalStepsFrame.Step5_PutToWork",
			[6] = "NormalStepsFrame.Step6_CollectBeli",
			[7] = "NormalStepsFrame.Step7_GetFaster",
		}
		local path = pathByStep[stepIndex]

		connectButton(findButton(stepFrame, "MoveToContinueButton", path), function()
			if tutorialState and tutorialState.canAdvance == true then
				requestAdvance()
			end
		end)
		connectButton(findButton(stepFrame, "SkipButton", path), function()
			requestSkip()
		end)
	end

	local step8 = tutorialRefs.stepsByIndex[8]
	connectButton(findButton(step8, "FinishButton", "FinalStepFrame.Step8_SetSail"), function()
		requestAdvance()
	end)
	connectButton(findButton(step8, "SkipButton", "FinalStepFrame.Step8_SetSail"), function()
		requestSkip()
	end)
end

local function renderObjectiveIndicator(state)
	local active = state and state.active == true and state.completed ~= true
	local hasTarget = active and typeof(state.target) == "table"

	objectiveGui.Enabled = hasTarget
	if hasTarget then
		objectiveRoot:render(React.createElement(ObjectiveIndicator, {
			target = state.target,
			zIndex = 184,
		}))
	else
		objectiveRoot:render(React.createElement(React.Fragment))
	end
end

local function scheduleRender()
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
	if not requestRemote then
		PopUpModule:Local_SendPopUp("Tutorial service is starting.", Color3.fromRGB(255, 104, 104), Color3.fromRGB(0, 0, 0), 3, true)
		return
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer("Advance")
	end)

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

resolveTutorialGuiRefs()
hideTutorialFrames()
connectTutorialButtons()

local existingRemotes = ReplicatedStorage:FindFirstChild("Remotes")
if existingRemotes then
	bindRemotesFolder(existingRemotes)
end

table.insert(cleanupConnections, ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "Remotes" then
		bindRemotesFolder(child)
	end
end))

task.spawn(function()
	while not destroyed and (not requestRemote or not stateRemote) do
		local folder = ReplicatedStorage:FindFirstChild("Remotes")
		if folder then
			bindRemotesFolder(folder)
		end
		task.wait(1)
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll()
	disconnectButtonConnections()
	hideTutorialFrames()
	if tutorialGui then
		tutorialGui.Enabled = false
	end
	objectiveRoot:unmount()
	objectiveGui:Destroy()
end)
