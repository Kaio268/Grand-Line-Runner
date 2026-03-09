local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeRewardsFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeRewards")
local RewardsConfig = require(TimeRewardsFolder:WaitForChild("Config"))
local DataManager = require(script.Parent.Parent.Data.DataManager)
local BrainrotModule = require(script.Parent.AddBrainrot)

local Remote = TimeRewardsFolder:WaitForChild("TimeRewardEvent")
local InstantRewardsEvent = TimeRewardsFolder:WaitForChild("TriggerInstantRewards")

local claimed = {}
local cycleStart = {}
local TOTAL_REWARDS = 0
local MAX_TIME = 0

for _, cfg in pairs(RewardsConfig) do
	TOTAL_REWARDS += 1
	if cfg.Time > MAX_TIME then
		MAX_TIME = cfg.Time
	end
end

local function rollReward(tbl)
	local roll = math.random(1, 100)
	local sum = 0
	for name, data in pairs(tbl) do
		sum += data.Chance
		if roll <= sum then
			return name, data.Amount, data
		end
	end
end

local function addReward(plr: Player, rewardName: string, amount: number)
	local inv = plr:FindFirstChild("Inventory")
	local feed = inv and inv:FindFirstChild("Feed")
	local stat = feed and feed:FindFirstChild(rewardName)
	if stat then
		DataManager:AddValue(plr, "Inventory.Feed." .. rewardName, amount)
		return
	end
	for _, folder in ipairs(plr:GetChildren()) do
		if folder:IsA("Folder") then
			local statObj = folder:FindFirstChild(rewardName)
			if statObj then
				DataManager:AddValue(plr, folder.Name .. "." .. rewardName, amount)
				return
			end
		end
	end
	DataManager:AddValue(plr, rewardName, amount)
end

local function getClaimedCount(plr: Player)
	local t = claimed[plr]
	if not t then
		return 0
	end
	local count = 0
	for _ in pairs(t) do
		count += 1
	end
	return count
end

local function startNewCycle(plr: Player)
	cycleStart[plr] = os.time()
	claimed[plr] = {}
	Remote:FireClient(plr, "cycleReset", cycleStart[plr])
end

local function claimSingleReward(plr: Player, id: number)
	local cfg = RewardsConfig[id]
	if not cfg then
		return
	end

	local rewardName, amount, rewardData = rollReward(cfg.Rewards)
	if not rewardName then
		return
	end

	if rewardData and rewardData.Brainrot == true then
		local ok = BrainrotModule:AddBrainrot(plr, rewardName, amount)
		if not ok then
			return
		end
	else
		addReward(plr, rewardName, amount)
	end

	claimed[plr][id] = true
	Remote:FireClient(plr, "claimed", id, rewardName, amount)
end

local function instantClaimAll(plr: Player)
	if not cycleStart[plr] then
		cycleStart[plr] = os.time()
	end
	if not claimed[plr] then
		claimed[plr] = {}
	end
	for id in pairs(RewardsConfig) do
		if not claimed[plr][id] then
			claimSingleReward(plr, id)
		end
	end
	startNewCycle(plr)
end

Players.PlayerAdded:Connect(function(plr)
	cycleStart[plr] = os.time()
	claimed[plr] = {}
	Remote:FireClient(plr, "startCycle", cycleStart[plr])
end)

for _, p in ipairs(Players:GetPlayers()) do
	cycleStart[p] = os.time()
	claimed[p] = {}
	Remote:FireClient(p, "startCycle", cycleStart[p])
end

Players.PlayerRemoving:Connect(function(plr)
	claimed[plr] = nil
	cycleStart[plr] = nil
end)

Remote.OnServerEvent:Connect(function(plr, id)
	id = tonumber(id)
	if not id then
		return
	end

	local cfg = RewardsConfig[id]
	if not cfg then
		return
	end

	if not claimed[plr] then
		claimed[plr] = {}
		cycleStart[plr] = os.time()
	end

	if claimed[plr][id] then
		Remote:FireClient(plr, "alreadyClaimed", id)
		return
	end

	local startTime = cycleStart[plr]
	if not startTime then
		cycleStart[plr] = os.time()
		startTime = cycleStart[plr]
	end

	local elapsed = os.time() - startTime
	if elapsed < cfg.Time then
		Remote:FireClient(plr, "notReady", id, cfg.Time - elapsed)
		return
	end

	claimSingleReward(plr, id)

	if getClaimedCount(plr) >= TOTAL_REWARDS then
		startNewCycle(plr)
	end
end)

InstantRewardsEvent.Event:Connect(function(plr)
	if typeof(plr) ~= "Instance" or not plr:IsA("Player") then
		return
	end
	instantClaimAll(plr)
end)

return {}