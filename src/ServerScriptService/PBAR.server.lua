local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
end

local ProgressBarSync = remotes:FindFirstChild("ProgressBarSync")
if not ProgressBarSync then
	ProgressBarSync = Instance.new("RemoteEvent")
	ProgressBarSync.Name = "ProgressBarSync"
	ProgressBarSync.Parent = remotes
end

local joinOrder = {}

local function removeFromJoinOrder(userId)
	for i = #joinOrder, 1, -1 do
		if joinOrder[i] == userId then
			table.remove(joinOrder, i)
		end
	end
end

local function buildPayload()
	local payload = {}
	for _, uid in ipairs(joinOrder) do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			payload[#payload + 1] = { UserId = p.UserId, Name = p.Name }
		end
	end
	return payload
end

local function broadcastAll()
	local payload = buildPayload()
	ProgressBarSync:FireAllClients(#payload, payload)
end

local function sendToPlayer(plr)
	local payload = buildPayload()
	ProgressBarSync:FireClient(plr, #payload, payload)
end

ProgressBarSync.OnServerEvent:Connect(function(plr, action)
	if action == "Request" then
		sendToPlayer(plr)
	end
end)

Players.PlayerAdded:Connect(function(plr)
	joinOrder[#joinOrder + 1] = plr.UserId
	task.defer(broadcastAll)
	task.delay(1, function()
		if plr and plr.Parent then
			sendToPlayer(plr)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	removeFromJoinOrder(plr.UserId)
	task.defer(broadcastAll)
end)

for _, p in ipairs(Players:GetPlayers()) do
	joinOrder[#joinOrder + 1] = p.UserId
end
broadcastAll()
