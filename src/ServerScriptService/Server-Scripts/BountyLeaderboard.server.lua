local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MAX_ENTRIES = 10
local UPDATE_DEBOUNCE_SECONDS = 0.15
local REMOTES_FOLDER_NAME = "Remotes"
local STATE_EVENT_NAME = "BountyLeaderboardState"
local SNAPSHOT_REQUEST_NAME = "BountyLeaderboardSnapshotRequest"

local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = REMOTES_FOLDER_NAME
	remotesFolder.Parent = ReplicatedStorage
end

local stateEvent = remotesFolder:FindFirstChild(STATE_EVENT_NAME)
if stateEvent and not stateEvent:IsA("RemoteEvent") then
	stateEvent:Destroy()
	stateEvent = nil
end
if not stateEvent then
	stateEvent = Instance.new("RemoteEvent")
	stateEvent.Name = STATE_EVENT_NAME
	stateEvent.Parent = remotesFolder
end

local snapshotRequest = remotesFolder:FindFirstChild(SNAPSHOT_REQUEST_NAME)
if snapshotRequest and not snapshotRequest:IsA("RemoteFunction") then
	snapshotRequest:Destroy()
	snapshotRequest = nil
end
if not snapshotRequest then
	snapshotRequest = Instance.new("RemoteFunction")
	snapshotRequest.Name = SNAPSHOT_REQUEST_NAME
	snapshotRequest.Parent = remotesFolder
end

local playerConnections = {}
local updateScheduled = false

local function disconnectConnections(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function readNumberValue(instance)
	if instance and instance:IsA("ValueBase") then
		return tonumber(instance.Value)
	end

	return nil
end

local function getPlayerBounty(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local bountyValue = leaderstats and leaderstats:FindFirstChild("Bounty")
	local bounty = readNumberValue(bountyValue)

	if bounty == nil then
		-- Fallback hook for future stat pipelines if bounty leaves leaderstats.
		bounty = tonumber(player:GetAttribute("Bounty")) or 0
	end

	return math.max(0, math.floor(bounty + 0.5))
end

local function buildSnapshot()
	local entries = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local bounty = getPlayerBounty(player)
		entries[#entries + 1] = {
			bounty = bounty,
			displayName = player.DisplayName,
			name = player.Name,
			userId = player.UserId,
		}
	end

	table.sort(entries, function(a, b)
		if a.bounty ~= b.bounty then
			return a.bounty > b.bounty
		end
		return tostring(a.name) < tostring(b.name)
	end)

	local topEntries = {}
	for index = 1, math.min(MAX_ENTRIES, #entries) do
		local entry = entries[index]
		topEntries[index] = {
			bounty = entry.bounty,
			displayName = entry.displayName,
			name = entry.name,
			rank = index,
			userId = entry.userId,
		}
	end

	return topEntries
end

local function broadcastSnapshot()
	stateEvent:FireAllClients(buildSnapshot())
end

local function scheduleBroadcast()
	if updateScheduled then
		return
	end

	updateScheduled = true
	task.delay(UPDATE_DEBOUNCE_SECONDS, function()
		updateScheduled = false
		broadcastSnapshot()
	end)
end

local function watchBountyValue(connections, value)
	if not value or not value:IsA("ValueBase") then
		return
	end

	connections[#connections + 1] = value:GetPropertyChangedSignal("Value"):Connect(scheduleBroadcast)
end

local function watchLeaderstats(player, leaderstats)
	local connections = playerConnections[player]
	if not connections or not leaderstats then
		return
	end

	local bountyValue = leaderstats:FindFirstChild("Bounty")
	watchBountyValue(connections, bountyValue)

	connections[#connections + 1] = leaderstats.ChildAdded:Connect(function(child)
		if child.Name == "Bounty" then
			watchBountyValue(connections, child)
			scheduleBroadcast()
		end
	end)

	connections[#connections + 1] = leaderstats.ChildRemoved:Connect(function(child)
		if child.Name == "Bounty" then
			scheduleBroadcast()
		end
	end)
end

local function connectPlayer(player)
	local connections = {}
	playerConnections[player] = connections

	watchLeaderstats(player, player:FindFirstChild("leaderstats"))
	connections[#connections + 1] = player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" then
			watchLeaderstats(player, child)
			scheduleBroadcast()
		end
	end)
	connections[#connections + 1] = player.ChildRemoved:Connect(function(child)
		if child.Name == "leaderstats" then
			scheduleBroadcast()
		end
	end)
	connections[#connections + 1] = player:GetAttributeChangedSignal("Bounty"):Connect(scheduleBroadcast)

	task.defer(function()
		if player.Parent == Players then
			stateEvent:FireClient(player, buildSnapshot())
		end
		scheduleBroadcast()
	end)
end

local function disconnectPlayer(player)
	local connections = playerConnections[player]
	if connections then
		disconnectConnections(connections)
	end
	playerConnections[player] = nil
	scheduleBroadcast()
end

snapshotRequest.OnServerInvoke = function()
	return buildSnapshot()
end

for _, player in ipairs(Players:GetPlayers()) do
	connectPlayer(player)
end

Players.PlayerAdded:Connect(connectPlayer)
Players.PlayerRemoving:Connect(disconnectPlayer)

task.defer(broadcastSnapshot)
