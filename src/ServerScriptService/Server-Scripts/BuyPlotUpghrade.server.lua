
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local remote = ReplicatedStorage.Remotes:FindFirstChild("PlotUpgradeRemote")

local busy = {}
local PLOT_UPGRADE_PATH = "HiddenLeaderstats.PlotUpgrade"

local function getUpgradePath(player: Player)
	return PLOT_UPGRADE_PATH
end

local function getCurrentUpgrade(player: Player, path: string)
	local stats = player:FindFirstChild("HiddenLeaderstats")
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
	local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
	if moneyValue then
		return moneyValue.Value
	end
	local dm = DataManager:GetValue(player, CurrencyUtil.getPrimaryPath())
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
		DataManager:SubValue(player, CurrencyUtil.getPrimaryPath(), cost)
		DataManager:AddValue(player, upPath, 1)
	end

	busy[player] = nil
end)

Players.PlayerRemoving:Connect(function(p)
	busy[p] = nil
end)


