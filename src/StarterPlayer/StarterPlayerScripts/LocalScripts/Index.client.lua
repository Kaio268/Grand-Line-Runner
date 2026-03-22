local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local Brainrots = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))
local IndexConfig = require(Configs:WaitForChild("Index"))

local inventory = player:WaitForChild("Inventory")

local cleanupConnections = {}
local rewardConnections = {}
local indexCollectionConnections = {}
local brainrotInventoryConnections = {}
local claimRemoteConnection = nil

local indexRewardsFolder = nil
local indexCollectionFolder = nil
local brainrotInventoryFolder = nil
local claimedRewardOverrides = {}

local VALID_BRAINROT_ITEM_IDS = {}

for itemId, info in pairs(Brainrots) do
	if type(info) == "table" then
		VALID_BRAINROT_ITEM_IDS[tostring(itemId)] = true
	end
end

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

local function getVariantInfo(variantKey)
	if variantKey == "Normal" or not variantKey then
		return (VariantCfg.Versions or {}).Normal or { Prefix = "", IncomeMult = 1 }
	end

	return (VariantCfg.Versions or {})[variantKey]
end

local function getVariantItemId(variantKey, baseName)
	if typeof(baseName) ~= "string" or baseName == "" then
		return nil
	end

	if variantKey == "Normal" or not variantKey then
		return baseName
	end

	local variantInfo = getVariantInfo(variantKey)
	local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
	return prefix .. baseName
end

local function readStringValue(container, childName)
	local child = container and container:FindFirstChild(childName)
	if child and child:IsA("StringValue") then
		local value = tostring(child.Value or "")
		if value ~= "" then
			return value
		end
	end

	return nil
end

local function readStringField(container, childName)
	local value = readStringValue(container, childName)
	if value ~= nil then
		return value
	end

	if not container then
		return nil
	end

	local attributeValue = container:GetAttribute(childName)
	if attributeValue == nil then
		return nil
	end

	local text = tostring(attributeValue)
	if text == "" then
		return nil
	end

	return text
end

local function normalizeVariantKey(variantKey)
	local candidate = tostring(variantKey or "")
	for _, supportedVariant in ipairs(VariantCfg.Order or { "Normal", "Golden", "Diamond" }) do
		if candidate == supportedVariant then
			return supportedVariant
		end
	end

	return "Normal"
end

local function parseVariantAndBaseName(fullName)
	local value = tostring(fullName or "")
	if value == "" then
		return "Normal", ""
	end

	for _, variantKey in ipairs(VariantCfg.Order or { "Normal", "Golden", "Diamond" }) do
		if variantKey ~= "Normal" then
			local variantInfo = getVariantInfo(variantKey)
			local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
			if value:sub(1, #prefix) == prefix then
				return variantKey, value:sub(#prefix + 1)
			end
		end
	end

	return "Normal", value
end

local function resolveBrainrotItemId(storageName, baseName, variantKey)
	local storageNameValue = tostring(storageName or "")
	local baseNameValue = tostring(baseName or "")
	local normalizedVariant = normalizeVariantKey(variantKey)
	if baseNameValue == "" and storageNameValue ~= "" then
		local parsedVariant, parsedBaseName = parseVariantAndBaseName(storageNameValue)
		normalizedVariant = normalizeVariantKey(parsedVariant)
		baseNameValue = parsedBaseName
	end

	if baseNameValue == "" then
		return nil
	end

	local itemId = getVariantItemId(normalizedVariant, baseNameValue)
	if itemId and VALID_BRAINROT_ITEM_IDS[itemId] then
		return itemId
	end

	if storageNameValue ~= "" and VALID_BRAINROT_ITEM_IDS[storageNameValue] then
		return storageNameValue
	end

	return nil
end

local function markDiscoveredBrainrot(discovered, storageName, baseName, variantKey)
	local itemId = resolveBrainrotItemId(storageName, baseName, variantKey)
	if itemId then
		discovered[itemId] = true
	end
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
	local discovered = {}
	local discoveredFolder = indexCollectionFolder and indexCollectionFolder:FindFirstChild("Brainrots")

	if discoveredFolder then
		for _, child in ipairs(discoveredFolder:GetChildren()) do
			if child:IsA("BoolValue") and child.Value == true then
				discovered[tostring(child.Name)] = true
			end
		end
	end

	local byIdFolder = brainrotInventoryFolder and brainrotInventoryFolder:FindFirstChild("ById")
	if byIdFolder then
		for _, child in ipairs(byIdFolder:GetChildren()) do
			if child:IsA("Folder") then
				markDiscoveredBrainrot(
					discovered,
					readStringField(child, "StorageName"),
					readStringField(child, "BaseName"),
					readStringField(child, "Variant")
				)
			end
		end
	end

	for _, child in ipairs(inventory:GetChildren()) do
		if child:IsA("Folder") and child.Name ~= "DevilFruits" then
			markDiscoveredBrainrot(
				discovered,
				child.Name,
				readStringField(child, "BaseName"),
				readStringField(child, "Variant")
			)
		end
	end

	local count = 0
	for _ in pairs(discovered) do
		count += 1
	end

	return count
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

local function bindBrainrotInventoryFolder()
	disconnectAll(brainrotInventoryConnections)

	brainrotInventoryFolder = player:FindFirstChild("BrainrotInventory")
	if not brainrotInventoryFolder then
		return
	end

	local function bindValueObserver(descendant)
		if descendant:IsA("ValueBase") then
			trackConnection(descendant:GetPropertyChangedSignal("Value"), function()
				if updateIndexBadge then
					updateIndexBadge()
				end
			end, brainrotInventoryConnections)
		end
	end

	for _, descendant in ipairs(brainrotInventoryFolder:GetDescendants()) do
		bindValueObserver(descendant)
	end

	trackConnection(brainrotInventoryFolder.ChildAdded, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, brainrotInventoryConnections)

	trackConnection(brainrotInventoryFolder.ChildRemoved, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, brainrotInventoryConnections)

	trackConnection(brainrotInventoryFolder.DescendantAdded, function(descendant)
		bindValueObserver(descendant)
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, brainrotInventoryConnections)

	trackConnection(brainrotInventoryFolder.DescendantRemoving, function()
		if updateIndexBadge then
			updateIndexBadge()
		end
	end, brainrotInventoryConnections)
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
	elseif child.Name == "BrainrotInventory" then
		bindBrainrotInventoryFolder()
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
	elseif child.Name == "BrainrotInventory" then
		bindBrainrotInventoryFolder()
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
bindBrainrotInventoryFolder()
bindIndexRewardsFolder()
bindClaimRemote(findRemoteEventByName(ReplicatedStorage, "ClaimIndexReward") or ReplicatedStorage:WaitForChild("ClaimIndexReward", 2))
updateIndexBadge()

script.Destroying:Connect(function()
	disconnectAll(cleanupConnections)
	disconnectAll(indexCollectionConnections)
	disconnectAll(brainrotInventoryConnections)
	disconnectAll(rewardConnections)
	if claimRemoteConnection then
		claimRemoteConnection:Disconnect()
		claimRemoteConnection = nil
	end
end)
