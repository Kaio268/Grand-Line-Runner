local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeRewardsFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeRewards")
local RewardsConfig = require(TimeRewardsFolder:WaitForChild("Config"))
local DataManager = require(script.Parent.Parent.Data.DataManager)
local BrainrotModule = require(script.Parent.AddBrainrot)
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local Remote = TimeRewardsFolder:WaitForChild("TimeRewardEvent")
local InstantRewardsEvent = TimeRewardsFolder:WaitForChild("TriggerInstantRewards")

local claimed = {}
local queueStart = {}
local orderedRewardIds = {}
local TOTAL_REWARDS = 0
local MAX_TIME = 0

for id, cfg in pairs(RewardsConfig) do
	TOTAL_REWARDS += 1
	table.insert(orderedRewardIds, id)
	if cfg.Time > MAX_TIME then
		MAX_TIME = cfg.Time
	end
end
table.sort(orderedRewardIds, function(a, b)
	return a < b
end)

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
	local function tryAddValue(path, delta)
		local ok, result = pcall(function()
			return DataManager:AddValue(plr, path, delta)
		end)
		return ok and result ~= false
	end

	local normalizedRewardName = tostring(rewardName)
	if normalizedRewardName == "Money" or normalizedRewardName == "Doubloons" then
		return tryAddValue(CurrencyUtil.getPrimaryPath(), amount)
	end

	local inv = plr:FindFirstChild("Inventory")
	local feed = inv and inv:FindFirstChild("Feed")
	local stat = feed and feed:FindFirstChild(normalizedRewardName)
	if stat then
		return tryAddValue("Inventory.Feed." .. normalizedRewardName, amount)
	end
	for _, folder in ipairs(plr:GetChildren()) do
		if folder:IsA("Folder") then
			local statObj = folder:FindFirstChild(normalizedRewardName)
			if statObj then
				return tryAddValue(folder.Name .. "." .. normalizedRewardName, amount)
			end
		end
	end
	return tryAddValue(normalizedRewardName, amount)
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
	queueStart[plr] = os.time()
	claimed[plr] = {}
	Remote:FireClient(plr, "cycleReset", queueStart[plr])
end

local function getNextRewardId(plr: Player)
	local playerClaimed = claimed[plr]
	if not playerClaimed then
		return orderedRewardIds[1]
	end

	for _, id in ipairs(orderedRewardIds) do
		if playerClaimed[id] ~= true then
			return id
		end
	end
	return nil
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
		local rewarded = addReward(plr, rewardName, amount)
		if not rewarded then
			return
		end
	end

	claimed[plr][id] = true
	queueStart[plr] = os.time()
	Remote:FireClient(plr, "claimed", id, rewardName, amount, queueStart[plr])
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
	queueStart[plr] = os.time()
	claimed[plr] = {}
	Remote:FireClient(plr, "startCycle", queueStart[plr])
end)

for _, p in ipairs(Players:GetPlayers()) do
	queueStart[p] = os.time()
	claimed[p] = {}
	Remote:FireClient(p, "startCycle", queueStart[p])
end

Players.PlayerRemoving:Connect(function(plr)
	claimed[plr] = nil
	queueStart[plr] = nil
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
		queueStart[plr] = os.time()
	end

	if claimed[plr][id] then
		Remote:FireClient(plr, "alreadyClaimed", id)
		return
	end

	local nextRewardId = getNextRewardId(plr)
	if nextRewardId == nil then
		startNewCycle(plr)
		return
	end
	if id ~= nextRewardId then
		Remote:FireClient(plr, "notReady", id, 0)
		return
	end

	local cfgNext = RewardsConfig[nextRewardId]
	if not cfgNext then
		return
	end

	local startTime = queueStart[plr]
	if not startTime then
		queueStart[plr] = os.time()
		startTime = queueStart[plr]
	end

	local elapsed = os.time() - startTime
	if elapsed < cfgNext.Time then
		Remote:FireClient(plr, "notReady", id, cfgNext.Time - elapsed)
		return
	end

	claimSingleReward(plr, nextRewardId)

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
