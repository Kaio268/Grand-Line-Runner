local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.Data:WaitForChild("DataManager"))
local Configs = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs")

local Brainrots = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))
local IndexConfig = require(Configs:WaitForChild("Index"))

local claimRemote = ReplicatedStorage:WaitForChild("ClaimIndexReward")

local supportedVariants = { "Normal", "Golden", "Diamond" }

local function getVariantInfo(variantKey)
	if variantKey == "Normal" or not variantKey then
		return (VariantCfg.Versions or {}).Normal or { Prefix = "", IncomeMult = 1 }
	end
	return (VariantCfg.Versions or {})[variantKey]
end

local function getVariantItemId(variantKey, baseName)
	local v = getVariantInfo(variantKey)
	if not v or variantKey == "Normal" then
		return baseName
	end
	local prefix = tostring(v.Prefix or (variantKey .. " "))
	return prefix .. baseName
end

local baseNames = {}
for name, data in pairs(Brainrots) do
	if type(data) == "table" and not data.IsVariant and not data.Variant then
		table.insert(baseNames, name)
	end
end

local allItemIds = {}
for _, baseName in ipairs(baseNames) do
	for _, vKey in ipairs(supportedVariants) do
		table.insert(allItemIds, getVariantItemId(vKey, baseName))
	end
end

local function countUnlockedBrainrots(player)
	local inv = player:FindFirstChild("Inventory")
	if not inv then return 0 end
	local c = 0
	for _, itemId in ipairs(allItemIds) do
		if inv:FindFirstChild(itemId) then
			c += 1
		end
	end
	return c
end

local processing = {}

claimRemote.OnServerEvent:Connect(function(player, questId)
	if processing[player] then return end
	processing[player] = true

	local q = tonumber(questId)
	if not q then
		processing[player] = nil
		return
	end

	local cfg = IndexConfig[q]
	if type(cfg) ~= "table" then
		processing[player] = nil
		return
	end

	local claimed = DataManager:GetValue(player, "IndexRewards." .. tostring(q))
	if claimed == true then
		processing[player] = nil
		return
	end

	local unlocked = countUnlockedBrainrots(player)
	if unlocked < q then
		processing[player] = nil
		return
	end

	for path, reward in pairs(cfg.Rewards or {}) do
		if typeof(path) == "string" and type(reward) == "table" then
			local amount = reward.Amount
			if typeof(amount) == "number" then
				DataManager:AddValue(player, path, amount)
			end
		end
	end

	DataManager:AddValue(player, "IndexRewards", { [tostring(q)] = true })

	processing[player] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	processing[player] = nil
end)
