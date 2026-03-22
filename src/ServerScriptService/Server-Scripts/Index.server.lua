local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.Data:WaitForChild("DataManager"))
local IndexCollectionService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("IndexCollectionService"))
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local Shorten = require(Modules:WaitForChild("Shorten"))

local Brainrots = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))
local IndexConfig = require(Configs:WaitForChild("Index"))

local function findRemoteEventByName(parent, remoteName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == remoteName and child:IsA("RemoteEvent") then
			return child
		end
	end

	return nil
end

local claimRemote = findRemoteEventByName(ReplicatedStorage, "ClaimIndexReward")
if not claimRemote then
	claimRemote = Instance.new("RemoteEvent")
	claimRemote.Name = "ClaimIndexReward"
	claimRemote.Parent = ReplicatedStorage
end

local VALID_BRAINROT_ITEM_IDS = {}

for itemId, info in pairs(Brainrots) do
	if type(info) == "table" then
		VALID_BRAINROT_ITEM_IDS[tostring(itemId)] = true
	end
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

local function countUnlockedBrainrots(player)
	local inv = player:FindFirstChild("Inventory")
	local brainrotInventory = player:FindFirstChild("BrainrotInventory")
	local discovered = {}
	local history = IndexCollectionService.GetDiscoveredBrainrotHistory(player)

	if history then
		for itemId, isDiscovered in pairs(history) do
			if isDiscovered == true then
				discovered[tostring(itemId)] = true
			end
		end
	end

	local byIdFolder = brainrotInventory and brainrotInventory:FindFirstChild("ById")
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

	if inv then
		for _, child in ipairs(inv:GetChildren()) do
			if child:IsA("Folder") and child.Name ~= "DevilFruits" then
				markDiscoveredBrainrot(
					discovered,
					child.Name,
					readStringField(child, "BaseName"),
					readStringField(child, "Variant")
				)
			end
		end
	end

	local count = 0
	for _ in pairs(discovered) do
		count += 1
	end

	return count
end

local function humanizeToken(token)
	local value = tostring(token or "")
	value = value:gsub("(%l)(%u)", "%1 %2")
	value = value:gsub("(%a)(%d)", "%1 %2")
	value = value:gsub("(%d)(%a)", "%1 %2")
	value = value:gsub("_", " ")
	return value
end

local function formatRewardLabel(path)
	local pathValue = tostring(path or "")
	if pathValue:find("MoneyMult", 1, true) then
		return "Ship Income"
	end
	if pathValue:find("x2MoneyTime", 1, true) then
		return "x2 Money"
	end
	if pathValue:find("WalkSpeed", 1, true) then
		return "Speed Boost"
	end

	local parts = string.split(pathValue, ".")
	return humanizeToken(parts[#parts] or pathValue)
end

local function formatRewardAmount(path, amount)
	local numeric = tonumber(amount)
	if numeric == nil then
		return tostring(amount or "")
	end

	if tostring(path or ""):find("Mult", 1, true) then
		return ("+%d%%"):format(math.floor((numeric * 100) + 0.5))
	end

	if tostring(path or ""):find("Time", 1, true) then
		return Shorten.timeSuffix3(math.floor(numeric + 0.5))
	end

	return Shorten.withCommas(math.floor(numeric + 0.5))
end

local function buildRewardPopupTable(config)
	local rewardPopupTable = {}

	for path, reward in pairs((config and config.Rewards) or {}) do
		rewardPopupTable[#rewardPopupTable + 1] = {
			string.format("%s %s", formatRewardLabel(path), formatRewardAmount(path, reward and reward.Amount)),
			reward and reward.Icon or "",
		}
	end

	table.sort(rewardPopupTable, function(a, b)
		return tostring(a[1]) < tostring(b[1])
	end)

	return rewardPopupTable
end

local function sendClaimPopup(player, text, isError)
	local textColor = isError and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 255, 60)
	local strokeColor = Color3.fromRGB(0, 0, 0)
	PopUpModule:Server_SendPopUp(player, text, textColor, strokeColor, 3, isError == true)
end

local processing = {}

claimRemote.OnServerEvent:Connect(function(player, questId)
	if processing[player] then
		return
	end

	processing[player] = true
	local q = tonumber(questId)

	local function finish()
		processing[player] = nil
	end

	local function sendClientClaimResult(success)
		claimRemote:FireClient(player, "ClaimResult", success == true, q)
	end

	if not q then
		sendClaimPopup(player, "That reward claim is invalid.", true)
		sendClientClaimResult(false)
		finish()
		return
	end

	local ok, err = pcall(function()
		local cfg = IndexConfig[q]
		if type(cfg) ~= "table" then
			sendClaimPopup(player, "That reward milestone doesn't exist.", true)
			sendClientClaimResult(false)
			return
		end

		local claimed = DataManager:GetValue(player, "IndexRewards." .. tostring(q))
		if claimed == true then
			sendClaimPopup(player, "You already claimed this milestone.", true)
			sendClientClaimResult(false)
			return
		end

		local unlocked = countUnlockedBrainrots(player)
		if unlocked < q then
			sendClaimPopup(player, "Discover more entries before claiming this reward.", true)
			sendClientClaimResult(false)
			return
		end

		for path, reward in pairs(cfg.Rewards or {}) do
			if typeof(path) == "string" and type(reward) == "table" then
				local amount = reward.Amount
				if typeof(amount) == "number" then
					local success, reason = DataManager:AddValue(player, path, amount)
					if success == false then
						error(string.format("failed to grant '%s' for quest %d: %s", path, q, tostring(reason)))
					end
				end
			end
		end

		local markedClaimed, reason = DataManager:SetValue(player, "IndexRewards." .. tostring(q), true)
		if markedClaimed == false then
			error(string.format("failed to mark quest %d claimed: %s", q, tostring(reason)))
		end

		sendClientClaimResult(true)
		sendClaimPopup(player, "Milestone reward claimed!", false)

		local rewardPopupTable = buildRewardPopupTable(cfg)
		if #rewardPopupTable > 0 then
			PopUpModule:Server_ShowReward(player, rewardPopupTable)
		end
	end)

	if not ok then
		warn(string.format("[IndexRewards] Failed to process claim %s for %s: %s", tostring(q), player.Name, tostring(err)))
		sendClaimPopup(player, "Couldn't claim that reward right now.", true)
		sendClientClaimResult(false)
	end

	finish()
end)

Players.PlayerRemoving:Connect(function(player)
	processing[player] = nil
end)
