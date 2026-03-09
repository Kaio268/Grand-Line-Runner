local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local dmModule = ServerScriptService:FindFirstChild("DataManager", true)
if not dmModule then
	error("DataManager module not found in ServerScriptService")
end
local DataManager = require(dmModule)

local Rebirths = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Rebirths"))

local RebirthRemote = ReplicatedStorage:FindFirstChild("RebirthRemote")
if not RebirthRemote then
	RebirthRemote = Instance.new("RemoteEvent")
	RebirthRemote.Name = "RebirthRemote"
	RebirthRemote.Parent = ReplicatedStorage
end

local serverDebounce = {}

local function getNumber(player, path)
	local v = DataManager:GetValue(player, path)
	if typeof(v) ~= "number" then
		return 0
	end
	return v
end

local function setNumber(player, path, target)
	local cur = getNumber(player, path)
	local delta = target - cur
	if delta ~= 0 then
		DataManager:AdjustValue(player, path, delta)
	end
end

RebirthRemote.OnServerEvent:Connect(function(player)
	if serverDebounce[player] then return end
	serverDebounce[player] = true

	local rebirthsCount = getNumber(player, "leaderstats.Rebirths")
	local nextIndex = rebirthsCount + 1
	local config = Rebirths[nextIndex]
	if not config then
		serverDebounce[player] = nil
		return
	end

	local money = getNumber(player, "leaderstats.Money")
	local speed = getNumber(player, "HiddenLeaderstats.Speed")

	local price = (typeof(config.Price) == "number") and config.Price or 0
	local speedNeeded = (typeof(config.SpeedNeeded) == "number") and config.SpeedNeeded or 0

	if money < price or speed < speedNeeded then
		serverDebounce[player] = nil
		return
	end

	setNumber(player, "leaderstats.Money", 0)
	setNumber(player, "HiddenLeaderstats.Speed", 1)
	DataManager:AdjustValue(player, "leaderstats.Rebirths", 1)

	if typeof(config.Getting) == "table" then
		for path, info in pairs(config.Getting) do
			if typeof(path) == "string" and typeof(info) == "table" then
				local amount = info.Amount
				if typeof(amount) == "number" then
					setNumber(player, path, amount)
				end
			end
		end
	end

	serverDebounce[player] = nil
end)
