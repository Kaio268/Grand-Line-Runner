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
local TutorialPrompt = require(UiFolder:WaitForChild("Tutorial"):WaitForChild("TutorialPrompt"))
local ObjectiveIndicator = require(UiFolder:WaitForChild("Tutorial"):WaitForChild("ObjectiveIndicator"))

local REQUEST_REMOTE_NAME = TutorialConfig.Remotes.RequestName
local STATE_REMOTE_NAME = TutorialConfig.Remotes.StateName

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "FirstTimeTutorialGui"
screenGui.DisplayOrder = 180
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
local skipRequestInFlight = false

local function disconnectAll()
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
end

local requestState
local refreshRemotes
local bindRemotesFolder

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
			root:render(React.createElement(React.Fragment, nil, {
				ObjectiveIndicator = if typeof(tutorialState.target) == "table"
					then React.createElement(ObjectiveIndicator, {
						target = tutorialState.target,
						zIndex = 184,
					})
					else nil,
				Prompt = React.createElement(TutorialPrompt, {
					state = tutorialState,
					onSkip = function()
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
					end,
					onAdvance = function()
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
					end,
				}),
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
	root:unmount()
	screenGui:Destroy()
end)
