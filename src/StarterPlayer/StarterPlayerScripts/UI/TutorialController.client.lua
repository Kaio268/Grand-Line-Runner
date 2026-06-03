local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local TutorialConfigs = require(Modules:WaitForChild("Configs"):WaitForChild("Tutorials"))
local GrandLineRushMetaClient = require(Modules:WaitForChild("GrandLineRushMetaClient"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local UiModalState = require(Modules:WaitForChild("UiModalState"))
local TutorialObjectiveIndicatorController = require(script.Parent:WaitForChild("TutorialObjectiveIndicatorController"))

local REQUEST_REMOTE_NAME = TutorialConfigs.Remotes.RequestName
local STATE_REMOTE_NAME = TutorialConfigs.Remotes.StateName
local QUEUED_START_THROTTLE_SECONDS = 0.75
local CONTEXTUAL_OBJECTIVE_GUI_NAME = "ContextualTutorialObjectiveGui"
local CONTEXTUAL_SCREEN_GUI_DISPLAY_ORDER = 180
local CONTEXTUAL_OBJECTIVE_DISPLAY_ORDER = 177
local CONTEXTUAL_OBJECTIVE_Z_INDEX = 184
local OBJECTIVE_TARGET_REFRESH_SECONDS = 2.5

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TutorialGui"
screenGui.DisplayOrder = 176
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = ReactRoblox.createRoot(screenGui)
local objectiveController = TutorialObjectiveIndicatorController.new(playerGui, {
	Name = CONTEXTUAL_OBJECTIVE_GUI_NAME,
	DisplayOrder = CONTEXTUAL_OBJECTIVE_DISPLAY_ORDER,
	ZIndex = CONTEXTUAL_OBJECTIVE_Z_INDEX,
})

local destroyed = false
local renderQueued = false
local tutorialState = nil
local cleanupConnections = {}
local remotes = nil
local requestRemote = nil
local stateRemote = nil
local stateRemoteConnection = nil
local remotesChildConnection = nil
local requestedInitialState = false
local requestInFlight = false
local lastQueuedStartAttemptAt = 0
local queuedStartRetryScheduled = false
local queuedStartAwaitingServerNudge = false
local objectiveRefreshScheduled = false
local runActive = false
local metaStateUnsubscribe = nil
local screenGuiButtonConnections = setmetatable({}, { __mode = "k" })
local screenGuiEnabledConnections = setmetatable({}, { __mode = "k" })
local warnedScreenGuiIssues = {}

local screenGuiPresentationsByTutorialId = {}
local screenGuiTutorialIdByGuiName = {}
local contextualScreenGuiNames = {}

for _, tutorialId in ipairs(TutorialConfigs.GetDefinitionOrder()) do
	local definition = TutorialConfigs.GetDefinition(tutorialId)
	local presentation = definition and definition.Presentation
	if typeof(presentation) == "table" and tostring(presentation.Type or "") == "ScreenGui" then
		local guiName = tostring(presentation.GuiName or "")
		if guiName ~= "" then
			screenGuiPresentationsByTutorialId[tutorialId] = presentation
			screenGuiTutorialIdByGuiName[guiName] = tutorialId
			contextualScreenGuiNames[#contextualScreenGuiNames + 1] = guiName
		end
	end
end

local requestState
local refreshRemotes
local bindRemotesFolder
local tryStartQueuedTutorial
local scheduleRender
local scheduleObjectiveTargetRefresh

local function warnScreenGuiIssue(key, message)
	if warnedScreenGuiIssues[key] then
		return
	end
	warnedScreenGuiIssues[key] = true
	warn(message)
end

local function getScreenGuiPresentation(tutorialId)
	return screenGuiPresentationsByTutorialId[tostring(tutorialId or "")]
end

local function isRunActiveFromState(state)
	local run = state and state.Run
	return typeof(run) == "table" and run.InRun == true
end

local function getActiveScreenGuiPresentation()
	if tutorialState and tutorialState.active == true and tutorialState.completed ~= true then
		return getScreenGuiPresentation(tutorialState.tutorialId)
	end

	return nil
end

local function shouldShowObjectiveForState(presentation)
	return typeof(presentation) == "table"
		and presentation.ShowObjectiveIndicator == true
		and runActive ~= true
		and tutorialState ~= nil
		and tutorialState.active == true
		and tutorialState.completed ~= true
		and typeof(tutorialState.target) == "table"
end

local function renderContextualObjective(presentation)
	if shouldShowObjectiveForState(presentation) then
		objectiveController:SetTarget(tutorialState.target, {
			PathOptions = presentation.ObjectivePathOptions,
			ShowPath = presentation.ShowObjectivePath == true,
			ZIndex = CONTEXTUAL_OBJECTIVE_Z_INDEX,
		})
		scheduleObjectiveTargetRefresh()
	else
		objectiveController:Clear()
	end
end

local function findGuiButton(guiRoot, buttonName)
	if typeof(guiRoot) ~= "Instance" or tostring(buttonName or "") == "" then
		return nil
	end

	for _, descendant in ipairs(guiRoot:GetDescendants()) do
		if descendant.Name == buttonName and descendant:IsA("GuiButton") then
			return descendant
		end
	end
	return nil
end

local function collectAvailableScreenGuis()
	local available = {}
	for _, guiName in ipairs(contextualScreenGuiNames) do
		local gui = playerGui:FindFirstChild(guiName)
		if gui and gui:IsA("ScreenGui") then
			available[guiName] = true
		end
	end
	return available
end

local function hideContextualScreenGuis(exceptGuiName)
	for _, guiName in ipairs(contextualScreenGuiNames) do
		if guiName ~= exceptGuiName then
			local gui = playerGui:FindFirstChild(guiName)
			if gui and gui:IsA("ScreenGui") then
				gui.Enabled = false
			end
		end
	end
end

local function updateContextualGuiDefaults(gui)
	if not gui or not gui:IsA("ScreenGui") then
		return
	end

	if screenGuiTutorialIdByGuiName[gui.Name] ~= nil then
		gui.DisplayOrder = math.max(gui.DisplayOrder, CONTEXTUAL_SCREEN_GUI_DISPLAY_ORDER)
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Enabled = false
	end
end

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)

	for button, connection in pairs(screenGuiButtonConnections) do
		if connection then
			connection:Disconnect()
		end
		screenGuiButtonConnections[button] = nil
	end

	for gui, connection in pairs(screenGuiEnabledConnections) do
		if connection then
			connection:Disconnect()
		end
		screenGuiEnabledConnections[gui] = nil
	end

	if metaStateUnsubscribe then
		metaStateUnsubscribe()
		metaStateUnsubscribe = nil
	end
end

local function requestAdvanceForScreenGuiTutorial(tutorialId)
	if not requestRemote or requestInFlight then
		return false
	end
	if not tutorialState or tutorialState.active ~= true or tostring(tutorialState.tutorialId or "") ~= tutorialId then
		return false
	end

	requestInFlight = true
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("Advance")
	end)
	requestInFlight = false

	if ok and typeof(response) == "table" and typeof(response.state) == "table" then
		tutorialState = response.state
		scheduleRender()
		return true
	end

	return false
end

local function runScreenGuiButtonAction(tutorialId, action)
	if typeof(action) ~= "table" then
		return
	end

	if action.CompleteTutorial ~= false and not requestAdvanceForScreenGuiTutorial(tutorialId) then
		return
	end

	local actionType = tostring(action.Type or "")
	if actionType == "OpenReactModal" then
		local modalName = tostring(action.ModalName or "")
		if modalName == "" then
			warnScreenGuiIssue(
				"missing_modal:" .. tostring(tutorialId or ""),
				string.format("[TutorialController] Tutorial %s action is missing ModalName.", tostring(tutorialId or ""))
			)
			return
		end

		ReactModalRegistry.Open(modalName, action.Payload)
	elseif actionType ~= "" then
		warnScreenGuiIssue(
			"unsupported_action:" .. tostring(tutorialId or "") .. ":" .. actionType,
			string.format("[TutorialController] Unsupported ScreenGui tutorial action %s.", actionType)
		)
	end
end

local function bindScreenGuiCompletionButtons(gui, presentation, tutorialId)
	if not gui or not gui:IsA("ScreenGui") or typeof(presentation) ~= "table" then
		return
	end

	local buttonNames = presentation.CompleteButtons
	if typeof(buttonNames) == "table" then
		for _, buttonName in ipairs(buttonNames) do
			buttonName = tostring(buttonName or "")
			local button = findGuiButton(gui, buttonName)
			if button then
				if screenGuiButtonConnections[button] == nil then
					screenGuiButtonConnections[button] = button.Activated:Connect(function()
						requestAdvanceForScreenGuiTutorial(tutorialId)
					end)
				end
			else
				warnScreenGuiIssue(
					gui.Name .. ":" .. buttonName,
					string.format("[TutorialController] %s is missing completion button %s.", gui.Name, buttonName)
				)
			end
		end
	end

	local actionButtons = presentation.ActionButtons
	if typeof(actionButtons) == "table" then
		for buttonName, action in pairs(actionButtons) do
			buttonName = tostring(buttonName or "")
			local button = findGuiButton(gui, buttonName)
			if button then
				if screenGuiButtonConnections[button] == nil then
					screenGuiButtonConnections[button] = button.Activated:Connect(function()
						runScreenGuiButtonAction(tutorialId, action)
					end)
				end
			else
				warnScreenGuiIssue(
					gui.Name .. ":" .. buttonName,
					string.format("[TutorialController] %s is missing action button %s.", gui.Name, buttonName)
				)
			end
		end
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

		local active = tutorialState and tutorialState.active == true and tutorialState.completed ~= true
		if active then
			if runActive == true then
				hideContextualScreenGuis(nil)
				objectiveController:Clear()
				root:render(React.createElement(React.Fragment))
				return
			end

			local presentation = getScreenGuiPresentation(tutorialState.tutorialId)
			if presentation then
				local guiName = tostring(presentation.GuiName or "")
				local gui = playerGui:FindFirstChild(guiName)
				hideContextualScreenGuis(guiName)

				if gui and gui:IsA("ScreenGui") then
					bindScreenGuiCompletionButtons(gui, presentation, tostring(tutorialState.tutorialId or ""))
					gui.Enabled = true
					renderContextualObjective(presentation)
				else
					objectiveController:Clear()
					warnScreenGuiIssue(
						"missing_gui:" .. guiName,
						string.format("[TutorialController] Missing contextual tutorial ScreenGui %s.", guiName)
					)
				end

				root:render(React.createElement(React.Fragment))
				return
			end

			hideContextualScreenGuis(nil)
			objectiveController:Clear()
			warnScreenGuiIssue(
				"unsupported_presentation:" .. tostring(tutorialState.tutorialId or ""),
				string.format(
					"[TutorialController] Tutorial %s has no ScreenGui presentation and will not render in the contextual controller.",
					tostring(tutorialState.tutorialId or "")
				)
			)
			root:render(React.createElement(React.Fragment))
		else
			hideContextualScreenGuis(nil)
			objectiveController:Clear()
			root:render(React.createElement(React.Fragment))
			task.defer(tryStartQueuedTutorial)
		end
	end)
end

local function isMajorModalVisible()
	if ReactModalRegistry.IsAnyVisible and ReactModalRegistry.IsAnyVisible() then
		return true
	end
	if UiModalState.IsOpen and UiModalState.IsOpen() then
		return true
	end

	local modalAttribute = if UiModalState.GetAttributeName then UiModalState.GetAttributeName() else "GameplayModalOpen"
	return player:GetAttribute(modalAttribute) == true
end

requestState = function()
	if not requestRemote then
		return
	end

	local ok, response = pcall(function()
		return requestRemote:InvokeServer("GetState")
	end)

	if ok and typeof(response) == "table" and typeof(response.state) == "table" then
		queuedStartAwaitingServerNudge = false
		tutorialState = response.state
		scheduleRender()
		task.defer(tryStartQueuedTutorial)
	end
end

scheduleObjectiveTargetRefresh = function()
	if destroyed or objectiveRefreshScheduled or not requestRemote then
		return
	end

	if not shouldShowObjectiveForState(getActiveScreenGuiPresentation()) then
		return
	end

	objectiveRefreshScheduled = true
	task.delay(OBJECTIVE_TARGET_REFRESH_SECONDS, function()
		objectiveRefreshScheduled = false
		if destroyed then
			return
		end

		if not shouldShowObjectiveForState(getActiveScreenGuiPresentation()) then
			return
		end

		if requestInFlight then
			scheduleObjectiveTargetRefresh()
			return
		end

		requestState()
		scheduleObjectiveTargetRefresh()
	end)
end

local function bindStateRemote(remote)
	if stateRemote == remote then
		return
	end

	disconnectConnection(stateRemoteConnection)
	stateRemote = remote
	stateRemoteConnection = remote.OnClientEvent:Connect(function(nextState)
		if typeof(nextState) ~= "table" then
			return
		end

		queuedStartAwaitingServerNudge = false
		tutorialState = nextState
		scheduleRender()
		task.defer(tryStartQueuedTutorial)
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
		task.defer(tryStartQueuedTutorial)
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

	disconnectConnection(remotesChildConnection)
	remotes = folder
	remotesChildConnection = folder.ChildAdded:Connect(function(child)
		if child.Name == REQUEST_REMOTE_NAME or child.Name == STATE_REMOTE_NAME then
			task.defer(refreshRemotes)
		end
	end)
	table.insert(cleanupConnections, remotesChildConnection)

	refreshRemotes()
end

tryStartQueuedTutorial = function()
	if destroyed or not requestRemote or requestInFlight then
		return
	end
	if tutorialState and tutorialState.active == true and tutorialState.completed ~= true then
		return
	end
	if queuedStartAwaitingServerNudge then
		return
	end
	if runActive == true then
		return
	end
	if isMajorModalVisible() then
		return
	end

	local now = os.clock()
	if now - lastQueuedStartAttemptAt < QUEUED_START_THROTTLE_SECONDS then
		if not queuedStartRetryScheduled then
			queuedStartRetryScheduled = true
			task.delay(QUEUED_START_THROTTLE_SECONDS - (now - lastQueuedStartAttemptAt), function()
				queuedStartRetryScheduled = false
				tryStartQueuedTutorial()
			end)
		end
		return
	end
	lastQueuedStartAttemptAt = now

	requestInFlight = true
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("TryStartQueued", {
			ClientReady = true,
			ScreenGuis = collectAvailableScreenGuis(),
		})
	end)
	requestInFlight = false

	if ok and typeof(response) == "table" and typeof(response.state) == "table" then
		queuedStartAwaitingServerNudge = response.success ~= true
		tutorialState = response.state
		scheduleRender()
	end
end

local function initializeContextualScreenGui(gui)
	updateContextualGuiDefaults(gui)

	local tutorialId = screenGuiTutorialIdByGuiName[gui and gui.Name or ""]
	if tutorialId then
		bindScreenGuiCompletionButtons(gui, getScreenGuiPresentation(tutorialId), tutorialId)
		if screenGuiEnabledConnections[gui] == nil then
			screenGuiEnabledConnections[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				if gui.Enabled == true then
					return
				end
				if
					tutorialState
					and tutorialState.active == true
					and tostring(tutorialState.tutorialId or "") == tutorialId
				then
					objectiveController:Clear()
				end
			end)
		end
	end
end

for _, guiName in ipairs(contextualScreenGuiNames) do
	local gui = playerGui:FindFirstChild(guiName)
	if gui and gui:IsA("ScreenGui") then
		initializeContextualScreenGui(gui)
	end
end

local existingRemotes = ReplicatedStorage:FindFirstChild("Remotes")
if existingRemotes then
	bindRemotesFolder(existingRemotes)
end

table.insert(cleanupConnections, ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "Remotes" then
		bindRemotesFolder(child)
	end
end))

table.insert(cleanupConnections, playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") and screenGuiTutorialIdByGuiName[child.Name] ~= nil then
		initializeContextualScreenGui(child)
		queuedStartAwaitingServerNudge = false
		scheduleRender()
		task.defer(tryStartQueuedTutorial)
	end
end))

table.insert(cleanupConnections, ReactModalRegistry.GetChangedSignal():Connect(function()
	task.defer(tryStartQueuedTutorial)
end))

local modalAttribute = if UiModalState.GetAttributeName then UiModalState.GetAttributeName() else "GameplayModalOpen"
table.insert(cleanupConnections, player:GetAttributeChangedSignal(modalAttribute):Connect(function()
	task.defer(tryStartQueuedTutorial)
end))

table.insert(cleanupConnections, player.CharacterAdded:Connect(function()
	objectiveController:Clear()
	task.defer(requestState)
end))

task.spawn(function()
	local ok, unsubscribe = pcall(function()
		return GrandLineRushMetaClient.ObserveState(function(state)
			local nextRunActive = isRunActiveFromState(state)
			if nextRunActive == runActive then
				return
			end

			runActive = nextRunActive
			if runActive == true then
				hideContextualScreenGuis(nil)
				objectiveController:Clear()
			end
			scheduleRender()
			if runActive ~= true then
				task.defer(tryStartQueuedTutorial)
			end
		end)
	end)

	if ok and typeof(unsubscribe) == "function" then
		if destroyed then
			unsubscribe()
			return
		end
		metaStateUnsubscribe = unsubscribe
	elseif not ok then
		warnScreenGuiIssue(
			"meta_observe_failed",
			string.format("[TutorialController] Failed to observe run state: %s", tostring(unsubscribe))
		)
	end
end)

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
	objectiveController:Destroy()
	root:unmount()
	screenGui:Destroy()
end)
