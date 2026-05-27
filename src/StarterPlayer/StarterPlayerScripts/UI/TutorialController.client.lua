local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local TutorialConfigs = require(Modules:WaitForChild("Configs"):WaitForChild("Tutorials"))
local ReactModalRegistry = require(Modules:WaitForChild("ReactModalRegistry"))
local TutorialPrompt = require(UiFolder:WaitForChild("Tutorial"):WaitForChild("TutorialPrompt"))

local REQUEST_REMOTE_NAME = TutorialConfigs.Remotes.RequestName
local STATE_REMOTE_NAME = TutorialConfigs.Remotes.StateName
local INVENTORY_TUTORIAL_ID = "Inventory"
local INVENTORY_MODAL_NAME = "Inventory"
local TRIGGER_THROTTLE_SECONDS = 2

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TutorialGui"
screenGui.DisplayOrder = 176
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local root = ReactRoblox.createRoot(screenGui)

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
local lastInventoryTriggerAt = 0

local requestState
local refreshRemotes
local bindRemotesFolder
local tryTriggerInventoryTutorial

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

		if tutorialState and tutorialState.active == true and tutorialState.completed ~= true then
			root:render(React.createElement(TutorialPrompt, {
				state = tutorialState,
				onSkip = function()
					if not requestRemote or requestInFlight then
						return
					end

					requestInFlight = true
					local ok, response = pcall(function()
						return requestRemote:InvokeServer("Skip")
					end)
					requestInFlight = false

					if ok and typeof(response) == "table" and typeof(response.state) == "table" then
						tutorialState = response.state
						scheduleRender()
					end
				end,
				onAdvance = function()
					if not requestRemote or requestInFlight then
						return
					end

					requestInFlight = true
					local ok, response = pcall(function()
						return requestRemote:InvokeServer("Advance")
					end)
					requestInFlight = false

					if ok and typeof(response) == "table" and typeof(response.state) == "table" then
						tutorialState = response.state
						scheduleRender()
					end
				end,
			}))
		else
			root:render(React.createElement(React.Fragment))
		end
	end)
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

	disconnectConnection(stateRemoteConnection)
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

tryTriggerInventoryTutorial = function()
	if destroyed or not requestRemote or requestInFlight then
		return
	end
	if ReactModalRegistry.IsVisible(INVENTORY_MODAL_NAME) ~= true then
		return
	end

	local now = os.clock()
	if now - lastInventoryTriggerAt < TRIGGER_THROTTLE_SECONDS then
		return
	end
	lastInventoryTriggerAt = now

	requestInFlight = true
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("Trigger", {
			TutorialId = INVENTORY_TUTORIAL_ID,
			TriggerContext = {
				Type = "ClientModalOpened",
				ModalName = INVENTORY_MODAL_NAME,
			},
		})
	end)
	requestInFlight = false

	if ok and typeof(response) == "table" and typeof(response.state) == "table" then
		tutorialState = response.state
		scheduleRender()
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

table.insert(cleanupConnections, ReactModalRegistry.GetChangedSignal():Connect(function(name)
	if tostring(name or "") == INVENTORY_MODAL_NAME then
		task.defer(tryTriggerInventoryTutorial)
	end
end))

table.insert(cleanupConnections, player:GetAttributeChangedSignal("InventoryMenuOpen"):Connect(function()
	if player:GetAttribute("InventoryMenuOpen") == true then
		task.defer(tryTriggerInventoryTutorial)
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
	root:unmount()
	screenGui:Destroy()
end)
