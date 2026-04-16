local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SpeedUpgrade = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Configs")
		:WaitForChild("SpeedUpgrade")
)

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local remote = ReplicatedStorage:FindFirstChild("BuySpeedUpgrade")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "BuySpeedUpgrade"
	remote.Parent = ReplicatedStorage
end

local function getSpeedValue(player)
	local hidden = player:FindFirstChild("HiddenLeaderstats")
	local sp = hidden and hidden:FindFirstChild("Speed")
	if sp and typeof(sp.Value) == "number" then
		return sp.Value
	end
	local v = DataManager:GetValue(player, "HiddenLeaderstats.Speed")
	if typeof(v) == "number" then
		return v
	end
	return 1
end

local function computeCost(cfg, speedVal)
	local starter = cfg.Starter_Price or 0
	local mult = cfg.Price_Mult or 1
	local addSpeed = cfg.AddSpeed or 1

	local s = tonumber(speedVal) or 1
	if s < 1 then s = 1 end

	local level = math.max(s - 1, 0)

	local function priceForLevel(lv)
		return starter * (mult ^ lv)
	end

	local total = 0
	for i = 0, addSpeed - 1 do
		total += priceForLevel(level + i)
	end

	return math.floor(total + 0.5)
end


remote.OnServerEvent:Connect(function(player, upgradeName)
	if typeof(upgradeName) ~= "string" then return end
	local idx = tonumber(upgradeName)
	if not idx then return end

	local cfg = SpeedUpgrade[idx]
	if not cfg then return end

	local addSpeed = cfg.AddSpeed or 0
	if typeof(addSpeed) ~= "number" then return end

	local speedVal = getSpeedValue(player)
	local cost = computeCost(cfg, speedVal)

	local moneyPath = CurrencyUtil.getPrimaryPath()
	local money = DataManager:GetValue(player, moneyPath)

	if typeof(money) ~= "number" then
		local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
		money = (moneyValue and moneyValue.Value) or 0
	end

	if money < cost then
		return
	end

	DataManager:AdjustValue(player, moneyPath, -cost)
	DataManager:AdjustValue(player, "TotalStats.TotalSpeed", addSpeed)
	DataManager:AdjustValue(player, "HiddenLeaderstats.Speed", addSpeed)

end)
