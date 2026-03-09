
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))

local remote = ReplicatedStorage.Remotes:FindFirstChild("PlotUpgradeRemote")

local busy = {}

local function getUpgradePath(player: Player)
	local a = player:FindFirstChild("HiddenLeadderstats")
	if a and a:FindFirstChild("PlotUpgrade") then
		return "HiddenLeadderstats.PlotUpgrade"
	end
	local b = player:FindFirstChild("HiddenLeaderstats")
	if b and b:FindFirstChild("PlotUpgrade") then
		return "HiddenLeaderstats.PlotUpgrade"
	end
	return "HiddenLeadderstats.PlotUpgrade"
end

local function getCurrentUpgrade(player: Player, path: string)
	local stats = player:FindFirstChild("HiddenLeadderstats") or player:FindFirstChild("HiddenLeaderstats")
	if stats then
		local v = stats:FindFirstChild("PlotUpgrade")
		if v and v:IsA("NumberValue") then
			return v.Value
		end
	end
	local dm = DataManager:GetValue(player, path)
	if typeof(dm) == "number" then return dm end
	return 0
end

local function getMoney(player: Player)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local m = ls:FindFirstChild("Money")
		if m and (m:IsA("IntValue") or m:IsA("NumberValue")) then
			return m.Value
		end
	end
	local dm = DataManager:GetValue(player, "leaderstats.Money")
	if typeof(dm) == "number" then return dm end
	return 0
end

local function priceFor(upgrade: number)
	local starter = tonumber(cfg.StarterPrice) or 0
	local mult = tonumber(cfg.PriceMult) or 1
	local p = starter * (mult ^ math.max(0, upgrade))
	if p < 0 then p = 0 end
	return math.floor(p + 0.5)
end

remote.OnServerEvent:Connect(function(player: Player)
	if busy[player] then return end
	busy[player] = true

	local upPath = getUpgradePath(player)
	local current = getCurrentUpgrade(player, upPath)
	local cost = priceFor(current)

	if cost >= 0 and getMoney(player) >= cost then
		DataManager:SubValue(player, "leaderstats.Money", cost)
		DataManager:AddValue(player, upPath, 1)
	end

	busy[player] = nil
end)

Players.PlayerRemoving:Connect(function(p)
	busy[p] = nil
end)


