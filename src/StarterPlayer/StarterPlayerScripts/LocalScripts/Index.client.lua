local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local IndexDiscovery = require(Modules:WaitForChild("Crew"):WaitForChild("IndexDiscovery"))
local IndexConfig = require(Configs:WaitForChild("Index"))

local inventory = player:WaitForChild("Inventory")

local cleanupConnections = {}
local rewardConnections = {}
local indexCollectionConnections = {}
local crewMemberInventoryConnections = {}
local claimRemoteConnection = nil

local indexRewardsFolder = nil
local indexCollectionFolder = nil
local crewMemberInventoryFolder = nil
local claimedRewardOverrides = {}

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		connection:Disconnect()
	end

	table.clear(bucket)
end

local function trackConnection(signal, callback, bucket)
	local connection = signal:Connect(callback)
	table.insert(bucket, connection)
	return connection
end

local function findRemoteEventByName(parent, remoteName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == remoteName and child:IsA("RemoteEvent") then
			return child
		end
	end

	return nil
end

local function findIndexBadge()
	local hud = playerGui:FindFirstChild("HUD")
	local lButtons = hud and hud:FindFirstChild("LButtons")
	local indexButton = lButtons and lButtons:FindFirstChild("Index")
	local badge = indexButton and indexButton:FindFirstChild("Not", true)
	local textLabel = badge and badge:FindFirstChild("TextLB", true)

	return badge, textLabel
end

local function buildQuestKeys()
	local questKeys = {}

	for key in pairs(IndexConfig) do
		if typeof(key) == "number" then
			questKeys[#questKeys + 1] = key
		end
	end

	table.sort(questKeys, function(a, b)
		return a < b
	end)

	return questKeys
end

local QUEST_KEYS = buildQuestKeys()

local function countCollectedGlobal()
	local discovered = IndexDiscovery.BuildDiscoveredSetFromFolders(indexCollectionFolder, crewMemberInventoryFolder)
	return IndexDiscovery.CountDiscoveredSet(discovered)
end

local updateIndexBadge

local function bindIndexCollectionFolder()
	disconnectAll(indexCollectionConnections)

	indexCollectionFolder = player:FindFirstChild("IndexCollection")
	if not indexCollectionFolder then
		return
	end

	local function bindValueObserver(descendant)
		if descendant:IsA("ValueBase") then
			trackConnection(descendant:GetPropertyChangedSignal("Value"), function()
				if updateIndexBadge then
					updateIndexBadge()
				end
			end, indexCollectionConnections)
		end
	end

	for _, descendant in ipairs(indexCollectionFolder:GetDescendants()) do
		bindValueObserver(descendant)
	end

	trackConnection(indexCollectionFolder.ChildAdded, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, indexCollectionConnections)

	trackConnection(indexCollectionFolder.ChildRemoved, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, indexCollectionConnections)

	trackConnection(indexCollectionFolder.DescendantAdded, function(descendant)
		bindValueObserver(descendant)
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, indexCollectionConnections)

	trackConnection(indexCollectionFolder.DescendantRemoving, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, indexCollectionConnections)
end

local function bindCrewMemberInventoryFolder()
	disconnectAll(crewMemberInventoryConnections)

	crewMemberInventoryFolder = player:FindFirstChild("CrewMemberInventory")
	if not crewMemberInventoryFolder then
		return
	end

	local function bindValueObserver(descendant)
		if descendant:IsA("ValueBase") then
			trackConnection(descendant:GetPropertyChangedSignal("Value"), function()
				if updateIndexBadge then
					updateIndexBadge()
				end
			end, crewMemberInventoryConnections)
		end
	end

	for _, descendant in ipairs(crewMemberInventoryFolder:GetDescendants()) do
		bindValueObserver(descendant)
	end

	trackConnection(crewMemberInventoryFolder.ChildAdded, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, crewMemberInventoryConnections)

	trackConnection(crewMemberInventoryFolder.ChildRemoved, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, crewMemberInventoryConnections)

	trackConnection(crewMemberInventoryFolder.DescendantAdded, function(descendant)
		bindValueObserver(descendant)
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, crewMemberInventoryConnections)

	trackConnection(crewMemberInventoryFolder.DescendantRemoving, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, crewMemberInventoryConnections)
end

local function isClaimed(questId)
	if claimedRewardOverrides[tostring(questId)] == true then
		return true
	end

	if not indexRewardsFolder or indexRewardsFolder.Parent ~= player then
		indexRewardsFolder = player:FindFirstChild("IndexRewards")
	end

	if not indexRewardsFolder then
		return false
	end

	local value = indexRewardsFolder:FindFirstChild(tostring(questId))
	return value ~= nil and value:IsA("BoolValue") and value.Value == true
end

updateIndexBadge = function()
	local badge, textLabel = findIndexBadge()
	if not badge then
		return
	end

	local collected = countCollectedGlobal()
	local claimableCount = 0

	for _, questId in ipairs(QUEST_KEYS) do
		if (not isClaimed(questId)) and collected >= questId then
			claimableCount += 1
		end
	end

	badge.Visible = claimableCount > 0

	if textLabel and (textLabel:IsA("TextLabel") or textLabel:IsA("TextButton")) then
		textLabel.Text = tostring(claimableCount)
	end
end

local function bindIndexRewardsFolder()
	disconnectAll(rewardConnections)

	indexRewardsFolder = player:FindFirstChild("IndexRewards")
	if not indexRewardsFolder then
		return
	end

	for _, child in ipairs(indexRewardsFolder:GetChildren()) do
		if child:IsA("BoolValue") then
			trackConnection(child:GetPropertyChangedSignal("Value"), updateIndexBadge, rewardConnections)
		end
	end

	trackConnection(indexRewardsFolder.ChildAdded, function(child)
		if child:IsA("BoolValue") then
			trackConnection(child:GetPropertyChangedSignal("Value"), updateIndexBadge, rewardConnections)
		end

		updateIndexBadge()
	end, rewardConnections)

	trackConnection(indexRewardsFolder.ChildRemoved, updateIndexBadge, rewardConnections)
end

local function bindClaimRemote(remote)
	if claimRemoteConnection then
		claimRemoteConnection:Disconnect()
		claimRemoteConnection = nil
	end

	if not remote then
		return
	end

	claimRemoteConnection = remote.OnClientEvent:Connect(function(actionName, success, rewardId)
		if actionName == "ClaimResult" and success == true then
			claimedRewardOverrides[tostring(rewardId or "")] = true
			updateIndexBadge()
		end
	end)
end

trackConnection(inventory.ChildAdded, updateIndexBadge, cleanupConnections)
trackConnection(inventory.ChildRemoved, updateIndexBadge, cleanupConnections)

trackConnection(player.ChildAdded, function(child)
	if child.Name == "IndexCollection" then
		bindIndexCollectionFolder()
		updateIndexBadge()
	elseif child.Name == "CrewMemberInventory" then
		bindCrewMemberInventoryFolder()
		updateIndexBadge()
	elseif child.Name == "IndexRewards" then
		bindIndexRewardsFolder()
		updateIndexBadge()
	end
end, cleanupConnections)

trackConnection(player.ChildRemoved, function(child)
	if child.Name == "IndexCollection" then
		bindIndexCollectionFolder()
		updateIndexBadge()
	elseif child.Name == "CrewMemberInventory" then
		bindCrewMemberInventoryFolder()
		updateIndexBadge()
	elseif child.Name == "IndexRewards" then
		bindIndexRewardsFolder()
		updateIndexBadge()
	end
end, cleanupConnections)

trackConnection(playerGui.ChildAdded, function(child)
	if child.Name == "HUD" then
		task.defer(updateIndexBadge)
	end
end, cleanupConnections)

trackConnection(ReplicatedStorage.ChildAdded, function(child)
	if child.Name == "ClaimIndexReward" and child:IsA("RemoteEvent") then
		bindClaimRemote(child)
	end
end, cleanupConnections)

bindIndexCollectionFolder()
bindCrewMemberInventoryFolder()
bindIndexRewardsFolder()
bindClaimRemote(findRemoteEventByName(ReplicatedStorage, "ClaimIndexReward") or ReplicatedStorage:WaitForChild("ClaimIndexReward", 2))
updateIndexBadge()

script.Destroying:Connect(function()
	disconnectAll(cleanupConnections)
	disconnectAll(indexCollectionConnections)
	disconnectAll(crewMemberInventoryConnections)
	disconnectAll(rewardConnections)
	if claimRemoteConnection then
		claimRemoteConnection:Disconnect()
		claimRemoteConnection = nil
	end
end)
