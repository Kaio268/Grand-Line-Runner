local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local SpeedUpgrade = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Configs")
		:WaitForChild("SpeedUpgrade")
)

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local TUTORIAL_COMPLETION_PATH = "HiddenLeaderstats.Tutorial"
local TUTORIAL_SPEED_TOP_UP_GRANTED_PATH = "HiddenLeaderstats.TutorialSpeedTopUpGranted"

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
	if s < 1 then
		s = 1
	end

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

local function isTutorialIncomplete(player)
	local completed, reason = DataManager:TryGetValue(player, TUTORIAL_COMPLETION_PATH)
	if reason == nil and typeof(completed) == "boolean" then
		return completed ~= true
	end

	local hidden = player:FindFirstChild("HiddenLeaderstats")
	local tutorial = hidden and hidden:FindFirstChild("Tutorial")
	return not (tutorial and tutorial:IsA("BoolValue") and tutorial.Value == true)
end

local function applyTutorialSpeedRecovery(player, upgradeIndex, moneyPath, money, cost, speedVal)
	if upgradeIndex ~= 1 then
		return false, 0
	end
	if not isTutorialIncomplete(player) or (tonumber(speedVal) or 1) > 1 then
		return false, 0
	end

	local granted, reason = DataManager:TryGetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH)
	if reason ~= nil or granted == true then
		return false, 0
	end

	local flagged = DataManager:TrySetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, true)
	if flagged ~= true then
		return false, 0
	end

	local shortfall = math.max(0, cost - money)
	if shortfall <= 0 then
		return true, 0
	end

	local added = DataManager:TryAddValue(player, moneyPath, shortfall)
	if added ~= true then
		DataManager:TrySetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, false)
		return false, 0
	end

	return true, shortfall
end

remote.OnServerEvent:Connect(function(player, upgradeName)
	if typeof(upgradeName) ~= "string" then
		return
	end
	local idx = tonumber(upgradeName)
	if not idx then
		return
	end

	local cfg = SpeedUpgrade[idx]
	if not cfg then
		return
	end

	local addSpeed = cfg.AddSpeed or 0
	if typeof(addSpeed) ~= "number" then
		return
	end

	local speedVal = getSpeedValue(player)
	local cost = computeCost(cfg, speedVal)

	local moneyPath = CurrencyUtil.getPrimaryPath()
	local money = DataManager:GetValue(player, moneyPath)

	if typeof(money) ~= "number" then
		local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
		money = (moneyValue and moneyValue.Value) or 0
	end

	local usedTutorialRecovery = false
	local tutorialRecoveryAmount = 0
	if money < cost then
		local recovered, recoveryAmount = applyTutorialSpeedRecovery(player, idx, moneyPath, money, cost, speedVal)
		if not recovered then
			return
		end
		usedTutorialRecovery = true
		tutorialRecoveryAmount = recoveryAmount
	end

	local newBalance = DataManager:AdjustValue(player, moneyPath, -cost)
	if typeof(newBalance) ~= "number" then
		if usedTutorialRecovery then
			if tutorialRecoveryAmount > 0 then
				DataManager:TryAddValue(player, moneyPath, -tutorialRecoveryAmount)
			end
			DataManager:TrySetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, false)
		end
		return
	end
	DataManager:AdjustValue(player, "TotalStats.TotalSpeed", addSpeed)
	DataManager:AdjustValue(player, "HiddenLeaderstats.Speed", addSpeed)

end)
