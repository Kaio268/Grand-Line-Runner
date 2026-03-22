local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Brainrots = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local BrainrotVariants = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))
local DevilFruits = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local IndexCollectionService = {}

local DataManagerModule
local VALID_BRAINROT_ITEM_IDS = {}

for itemId, info in pairs(Brainrots) do
	if type(info) == "table" then
		VALID_BRAINROT_ITEM_IDS[tostring(itemId)] = true
	end
end

local function getDataManager()
	if not DataManagerModule then
		DataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end

	return DataManagerModule
end

local function getVariantInfo(variantKey)
	if variantKey == "Normal" or not variantKey then
		return (BrainrotVariants.Versions or {}).Normal or { Prefix = "", IncomeMult = 1 }
	end

	return (BrainrotVariants.Versions or {})[variantKey]
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

local function normalizeVariantKey(variantKey)
	local candidate = tostring(variantKey or "")
	for _, supportedVariant in ipairs(BrainrotVariants.Order or { "Normal", "Golden", "Diamond" }) do
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

	for _, variantKey in ipairs(BrainrotVariants.Order or { "Normal", "Golden", "Diamond" }) do
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

function IndexCollectionService.ResolveBrainrotItemId(storageName, baseName, variantKey)
	local storageNameValue = tostring(storageName or "")
	local baseNameValue = tostring(baseName or "")
	local normalizedVariant = normalizeVariantKey(variantKey)

	if baseNameValue == "" and storageNameValue ~= "" then
		local parsedVariant, parsedBaseName = parseVariantAndBaseName(storageNameValue)
		normalizedVariant = normalizeVariantKey(parsedVariant)
		baseNameValue = parsedBaseName
	end

	if baseNameValue ~= "" then
		local itemId = getVariantItemId(normalizedVariant, baseNameValue)
		if itemId and VALID_BRAINROT_ITEM_IDS[itemId] then
			return itemId
		end
	end

	if storageNameValue ~= "" and VALID_BRAINROT_ITEM_IDS[storageNameValue] then
		return storageNameValue
	end

	return nil
end

function IndexCollectionService.MarkBrainrotDiscovered(player, storageName, baseName, variantKey)
	local itemId = IndexCollectionService.ResolveBrainrotItemId(storageName, baseName, variantKey)
	if not itemId then
		return nil
	end

	local dataManager = getDataManager()
	local path = "IndexCollection.Brainrots." .. itemId
	local currentValue = dataManager:TryGetValue(player, path)
	if currentValue ~= true then
		dataManager:TrySetValue(player, path, true)
	end

	return itemId
end

function IndexCollectionService.MarkDevilFruitDiscovered(player, fruitIdentifier)
	local fruit = DevilFruits.GetFruit(fruitIdentifier)
	if not fruit then
		return nil
	end

	local dataManager = getDataManager()
	local path = "IndexCollection.DevilFruits." .. tostring(fruit.FruitKey)
	local currentValue = dataManager:TryGetValue(player, path)
	if currentValue ~= true then
		dataManager:TrySetValue(player, path, true)
	end

	return fruit.FruitKey
end

function IndexCollectionService.GetDiscoveredBrainrotHistory(player)
	local history = getDataManager():GetValue(player, "IndexCollection.Brainrots")
	if typeof(history) == "table" then
		return history
	end

	return nil
end

function IndexCollectionService.CountDiscoveredBrainrots(player)
	local history = IndexCollectionService.GetDiscoveredBrainrotHistory(player)
	if history == nil then
		return nil
	end

	local count = 0
	for _, discovered in pairs(history) do
		if discovered == true then
			count += 1
		end
	end

	return count
end

return IndexCollectionService
