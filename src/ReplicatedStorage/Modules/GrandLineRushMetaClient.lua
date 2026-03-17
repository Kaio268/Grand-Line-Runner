local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))

-- Future UI screens should depend on this module instead of talking to
-- GrandLineRushSliceRequest directly. That keeps the placeholder UI disposable.
local MetaClient = {
	_state = nil,
	_initialized = false,
	_observers = {},
}

local player = Players.LocalPlayer
local requestRemote
local stateRemote
local remoteConnection

local function cloneObservers(observers)
	local cloned = {}
	for observer, _ in pairs(observers) do
		cloned[#cloned + 1] = observer
	end
	return cloned
end

local function notifyObservers(newState)
	for _, observer in ipairs(cloneObservers(MetaClient._observers)) do
		task.spawn(observer, newState)
	end
end

local function applyState(newState)
	if typeof(newState) ~= "table" then
		return MetaClient._state
	end

	MetaClient._state = newState
	notifyObservers(newState)
	return newState
end

local function ensureRemotes()
	if requestRemote and stateRemote then
		return requestRemote, stateRemote
	end

	local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
	requestRemote = remotesFolder:WaitForChild(Economy.VerticalSlice.Remotes.RequestName)
	stateRemote = remotesFolder:WaitForChild(Economy.VerticalSlice.Remotes.StateEventName)
	return requestRemote, stateRemote
end

function MetaClient.Init()
	if MetaClient._initialized then
		return
	end

	MetaClient._initialized = true
	ensureRemotes()

	if remoteConnection == nil then
		remoteConnection = stateRemote.OnClientEvent:Connect(function(newState)
			applyState(newState)
		end)
	end

	MetaClient.Refresh()
end

function MetaClient.GetPlayer()
	return player
end

function MetaClient.GetState()
	MetaClient.Init()
	return MetaClient._state
end

function MetaClient.ObserveState(callback)
	assert(typeof(callback) == "function", "ObserveState requires a callback")
	MetaClient.Init()

	MetaClient._observers[callback] = true
	if MetaClient._state then
		task.spawn(callback, MetaClient._state)
	end

	return function()
		MetaClient._observers[callback] = nil
	end
end

function MetaClient.Request(actionName, payload)
	MetaClient.Init()

	local ok, response = pcall(function()
		return requestRemote:InvokeServer(actionName, payload)
	end)

	if not ok then
		return {
			ok = false,
			message = "Request failed.",
			error = "remote_failure",
			debug = response,
			state = MetaClient._state,
		}
	end

	if typeof(response) == "table" and typeof(response.state) == "table" then
		applyState(response.state)
	end

	return response
end

function MetaClient.Refresh()
	return MetaClient.Request("GetState")
end

function MetaClient.OpenChest(chestId)
	return MetaClient.Request("OpenChest", {
		ChestId = chestId,
	})
end

function MetaClient.FeedCrew(crewInstanceId, foodKey)
	return MetaClient.Request("FeedCrew", {
		CrewInstanceId = crewInstanceId,
		FoodKey = foodKey,
	})
end

return MetaClient
