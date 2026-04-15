local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local Economy = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local UiModalState = require(Modules:WaitForChild("UiModalState"))
local DropAction = require(UiFolder:WaitForChild("Corridor"):WaitForChild("DropAction"))

local verticalSliceConfig = Economy.VerticalSlice
if verticalSliceConfig.Enabled ~= true then
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local requestRemote = remotesFolder:WaitForChild(verticalSliceConfig.Remotes.RequestName)
local stateRemote = remotesFolder:WaitForChild(verticalSliceConfig.Remotes.StateEventName)

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactCorridorDropRoot"
rootContainer.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local modalOpenAttribute = UiModalState.GetAttributeName()

local currentState = nil
local dropPending = false
local renderQueued = false
local destroyed = false
local cleanupConnections = {}

local function trackConnection(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(cleanupConnections, connection)
	return connection
end

local function getRunState()
	return currentState and currentState.Run or nil
end

local function getCarriedReward()
	local runState = getRunState()
	local carriedReward = runState and runState.CarriedReward or nil
	if carriedReward ~= nil then
		return carriedReward
	end

	local carriedDisplayName = player:GetAttribute("CarriedMajorRewardDisplayName")
	local carriedType = player:GetAttribute("CarriedMajorRewardType")
	if typeof(carriedDisplayName) == "string" and carriedDisplayName ~= "" then
		return {
			DisplayName = carriedDisplayName,
			RewardType = if typeof(carriedType) == "string" then carriedType else nil,
		}
	end

	local carriedBrainrot = player:GetAttribute("CarriedBrainrot")
	if typeof(carriedBrainrot) == "string" and carriedBrainrot ~= "" then
		local carriedBrainrotImage = player:GetAttribute("CarriedBrainrotImage")
		return {
			DisplayName = carriedBrainrot,
			RewardType = "Brainrot",
			Image = if typeof(carriedBrainrotImage) == "string" then carriedBrainrotImage else nil,
		}
	end

	return nil
end

local function showPopup(text, isError)
	local color = if isError then Color3.fromRGB(255, 104, 126) else Color3.fromRGB(113, 255, 184)
	local stroke = Color3.fromRGB(10, 8, 12)

	task.spawn(function()
		pcall(function()
			PopUpModule:Local_SendPopUp(tostring(text), color, stroke, 2, isError == true)
		end)
	end)
end

local function getFallbackError(response)
	local errorCode = response and response.error
	if errorCode == "no_carried_reward" or errorCode == "no_held_brainrot" or errorCode == "no_carried_item" then
		return "No carried item to drop."
	elseif errorCode == "missing_drop_position" then
		return "Move a little before dropping that."
	elseif errorCode == "missing_context" or errorCode == "missing_state" then
		return "That item is not ready to drop yet."
	elseif errorCode == "profile_not_ready" then
		return "Your run data is still loading."
	end

	return "Could not drop item."
end

local function render()
	local modalOpen = playerGui:GetAttribute(modalOpenAttribute) == true
	local carriedReward = getCarriedReward()
	local visible = carriedReward ~= nil and modalOpen ~= true

	root:render(ReactRoblox.createPortal(React.createElement(DropAction, {
		visible = visible,
		isPending = dropPending,
		reward = carriedReward,
		onDrop = function()
			if dropPending or getCarriedReward() == nil then
				return
			end

			dropPending = true
			render()

			task.spawn(function()
				local ok, response = pcall(function()
					return requestRemote:InvokeServer("DropCarriedReward")
				end)

				dropPending = false

				if ok and typeof(response) == "table" then
					currentState = response.state or currentState
					if response.ok == true then
						if response.message then
							showPopup(response.message, false)
						end
					else
						showPopup(response.message or getFallbackError(response), true)
					end
				else
					showPopup("Could not drop item.", true)
				end

				if not destroyed then
					render()
				end
			end)
		end,
	}), playerGui))
end

local function scheduleRender()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

trackConnection(stateRemote.OnClientEvent, function(nextState)
	if typeof(nextState) ~= "table" then
		return
	end

	currentState = nextState
	scheduleRender()
end)

trackConnection(playerGui:GetAttributeChangedSignal(modalOpenAttribute), scheduleRender)
trackConnection(player:GetAttributeChangedSignal("CarriedMajorRewardDisplayName"), scheduleRender)
trackConnection(player:GetAttributeChangedSignal("CarriedMajorRewardType"), scheduleRender)
trackConnection(player:GetAttributeChangedSignal("CarriedBrainrot"), scheduleRender)
trackConnection(player:GetAttributeChangedSignal("CarriedBrainrotImage"), scheduleRender)

task.spawn(function()
	local ok, response = pcall(function()
		return requestRemote:InvokeServer("GetState")
	end)

	if ok and typeof(response) == "table" then
		currentState = response.state or currentState
	end

	scheduleRender()
end)

render()

script.Destroying:Connect(function()
	destroyed = true
	for _, connection in ipairs(cleanupConnections) do
		connection:Disconnect()
	end
	table.clear(cleanupConnections)
	root:unmount()
end)
