local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewMembersConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewMembers"))
local DevilFruits = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local IndexCollectionService = {}

local DataManagerModule
local CrewMemberCanonicalReadGateModule
local CrewVariants = CrewCatalog.GetVariantConfig()
local VALID_CREW_MEMBER_ITEM_IDS = {}

-- Source-of-truth rules:
-- Inventory.DevilFruits = currently owned fruit items.
-- IndexCollection.DevilFruits = lifetime discovery/unlock history.
-- DevilFruit.Equipped = currently active fruit only.
-- Tool scans below are one-way legacy backfill inputs, not authoritative state.

for _, entry in ipairs(CrewMembersConfig.GetEntries()) do
	if type(entry) == "table" then
		local crewMemberId = tostring(entry.CrewMemberId or "")
		if crewMemberId ~= "" then
			for _, variantKey in ipairs(CrewVariants.Order or { "Normal", "Golden", "Diamond" }) do
				VALID_CREW_MEMBER_ITEM_IDS[CrewCatalog.MakeVariantId(crewMemberId, variantKey)] = true
			end
		end
	end
end

local function getDataManager()
	if not DataManagerModule then
		DataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end

	return DataManagerModule
end

local function getCrewMemberCanonicalReadGate()
	if not CrewMemberCanonicalReadGateModule then
		CrewMemberCanonicalReadGateModule = require(
			ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewMemberCanonicalReadGate")
		)
	end

	return CrewMemberCanonicalReadGateModule
end

local function addDevilFruitCandidate(candidates, fruitIdentifier)
	local fruit = DevilFruits.GetFruit(fruitIdentifier)
	if fruit then
		candidates[fruit.FruitKey] = true
	end
end

local function addDevilFruitTableEntryCandidates(candidates, entry)
	addDevilFruitCandidate(candidates, entry.FruitKey)
	addDevilFruitCandidate(candidates, entry.Key)
	addDevilFruitCandidate(candidates, entry.Id)
	addDevilFruitCandidate(candidates, entry.Name)
	addDevilFruitCandidate(candidates, entry.DisplayName)
	addDevilFruitCandidate(candidates, entry.FruitName)

	for _, value in pairs(entry) do
		if typeof(value) == "string" then
			addDevilFruitCandidate(candidates, value)
		elseif typeof(value) == "table" then
			addDevilFruitCandidate(candidates, value.FruitKey)
			addDevilFruitCandidate(candidates, value.Key)
			addDevilFruitCandidate(candidates, value.Id)
			addDevilFruitCandidate(candidates, value.Name)
			addDevilFruitCandidate(candidates, value.DisplayName)
			addDevilFruitCandidate(candidates, value.FruitName)
		end
	end
end

local function isExplicitlyUndiscoveredDevilFruitEntry(entry)
	if entry == false then
		return true
	end

	if typeof(entry) ~= "table" then
		return false
	end

	return entry.Discovered == false or entry.Unlocked == false or entry.Collected == false or entry.Value == false
end

local function shouldReadLifetimeDevilFruitEntry(entry)
	if isExplicitlyUndiscoveredDevilFruitEntry(entry) then
		return false
	end

	local entryType = typeof(entry)
	if entryType == "boolean" then
		return entry == true
	elseif entryType == "number" then
		return entry > 0
	elseif entryType == "string" then
		return entry ~= ""
	elseif entryType == "table" then
		return true
	end

	return false
end

local function hasLiveDiscoveredDevilFruitValue(player, fruitKey)
	local indexCollection = player and player:FindFirstChild("IndexCollection")
	local devilFruits = indexCollection and indexCollection:FindFirstChild("DevilFruits")
	local value = devilFruits and devilFruits:FindFirstChild(tostring(fruitKey))
	return value ~= nil and value:IsA("BoolValue") and value.Value == true
end

local function addDevilFruitTableCandidates(candidates, devilFruits, options)
	if typeof(devilFruits) ~= "table" then
		return
	end

	local requireTruthy = options and options.RequireTruthy == true
	for fruitIdentifier, entry in pairs(devilFruits) do
		if requireTruthy and not shouldReadLifetimeDevilFruitEntry(entry) then
			continue
		end

		addDevilFruitCandidate(candidates, fruitIdentifier)

		if typeof(entry) == "table" then
			addDevilFruitTableEntryCandidates(candidates, entry)
		elseif typeof(entry) == "string" then
			addDevilFruitCandidate(candidates, entry)
		end
	end
end

local function readStringField(container, childName)
	if not container then
		return nil
	end

	local child = container:FindFirstChild(childName)
	if child and child:IsA("StringValue") then
		local value = tostring(child.Value or "")
		if value ~= "" then
			return value
		end
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

local function addDevilFruitFolderCandidates(candidates, devilFruitsFolder)
	if not devilFruitsFolder or not devilFruitsFolder:IsA("Folder") then
		return
	end

	for _, child in ipairs(devilFruitsFolder:GetChildren()) do
		addDevilFruitCandidate(candidates, child.Name)
		addDevilFruitCandidate(candidates, readStringField(child, "FruitKey"))
		addDevilFruitCandidate(candidates, readStringField(child, "Name"))
		addDevilFruitCandidate(candidates, readStringField(child, "DisplayName"))
	end
end

local function addDevilFruitToolCandidate(candidates, tool)
	if not tool or not tool:IsA("Tool") then
		return
	end

	local inventoryKind = tool:GetAttribute("InventoryItemKind")
	if inventoryKind ~= nil and tostring(inventoryKind) ~= "DevilFruit" then
		return
	end

	addDevilFruitCandidate(candidates, tool:GetAttribute("FruitKey"))
	addDevilFruitCandidate(candidates, tool:GetAttribute("InventoryItemName"))
	addDevilFruitCandidate(candidates, tool:GetAttribute("InvItem"))
	addDevilFruitCandidate(candidates, tool.Name)
end

local function addDevilFruitToolContainerCandidates(candidates, container)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		addDevilFruitToolCandidate(candidates, child)
	end
end

local function addEquippedDevilFruitCandidates(candidates, player, dataManager)
	local equippedValue = nil
	local equippedReason = nil

	if dataManager and dataManager.TryGetValue then
		equippedValue, equippedReason = dataManager:TryGetValue(player, "DevilFruit.Equipped")
	end

	if equippedReason == nil then
		addDevilFruitCandidate(candidates, equippedValue)
	end

	local devilFruitFolder = player:FindFirstChild("DevilFruit")
	local liveEquipped = devilFruitFolder and devilFruitFolder:FindFirstChild("Equipped")
	if liveEquipped and liveEquipped:IsA("StringValue") then
		addDevilFruitCandidate(candidates, liveEquipped.Value)
	end

	addDevilFruitCandidate(candidates, player:GetAttribute("EquippedDevilFruit"))
end

local function getVariantInfo(variantKey)
	if variantKey == "Normal" or not variantKey then
		return (CrewVariants.Versions or {}).Normal or { Prefix = "", IncomeMult = 1 }
	end

	return (CrewVariants.Versions or {})[variantKey]
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
	for _, supportedVariant in ipairs(CrewVariants.Order or { "Normal", "Golden", "Diamond" }) do
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

	for _, variantKey in ipairs(CrewVariants.Order or { "Normal", "Golden", "Diamond" }) do
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

function IndexCollectionService.ResolveCrewMemberItemId(crewMemberId, baseName, variantKey)
	local crewMemberIdValue = tostring(crewMemberId or "")
	local baseNameValue = tostring(baseName or "")
	local normalizedVariant = normalizeVariantKey(variantKey)

	if baseNameValue == "" and crewMemberIdValue ~= "" then
		local parsedVariant, parsedBaseName = parseVariantAndBaseName(crewMemberIdValue)
		normalizedVariant = normalizeVariantKey(parsedVariant)
		baseNameValue = parsedBaseName
	end

	local resolvedCrewMemberId, info = CrewCatalog.ResolveCrewMemberId(baseNameValue)
	if info then
		baseNameValue = tostring(info.CrewMemberId or resolvedCrewMemberId)
	end

	if baseNameValue ~= "" then
		local itemId = getVariantItemId(normalizedVariant, baseNameValue)
		if itemId and VALID_CREW_MEMBER_ITEM_IDS[itemId] then
			return itemId
		end
	end

	if crewMemberIdValue ~= "" and VALID_CREW_MEMBER_ITEM_IDS[crewMemberIdValue] then
		return crewMemberIdValue
	end

	return nil
end

function IndexCollectionService.MarkCrewMemberDiscovered(player, crewMemberId, baseName, variantKey, _options)
	local itemId = IndexCollectionService.ResolveCrewMemberItemId(crewMemberId, baseName, variantKey)
	if not itemId then
		return nil
	end

	local dataManager = getDataManager()
	local path = "IndexCollection.CrewMembers." .. itemId
	local currentValue = dataManager:TryGetValue(player, path)
	if currentValue ~= true then
		dataManager:TrySetValue(player, path, true)
	end

	getCrewMemberCanonicalReadGate().CompareIndexDisplay(player, itemId, {
		LogThrottleSeconds = 60,
	})

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
	if currentValue ~= true or not hasLiveDiscoveredDevilFruitValue(player, fruit.FruitKey) then
		dataManager:TrySetValue(player, path, true)
	end

	return fruit.FruitKey
end

function IndexCollectionService.BackfillDevilFruitDiscoveries(player)
	if not player then
		return 0
	end

	local dataManager = getDataManager()
	local candidates = {}

	local savedIndexCollection = dataManager:GetValue(player, "IndexCollection.DevilFruits")
	addDevilFruitTableCandidates(candidates, savedIndexCollection, {
		RequireTruthy = true,
	})

	local savedDevilFruits = dataManager:GetValue(player, "Inventory.DevilFruits")
	addDevilFruitTableCandidates(candidates, savedDevilFruits)

	local inventory = player:FindFirstChild("Inventory")
	addDevilFruitFolderCandidates(candidates, inventory and inventory:FindFirstChild("DevilFruits"))

	-- Legacy compatibility only. Fruit tools should normally be created from
	-- Inventory.DevilFruits, but older sessions may still expose tool-only fruit
	-- ownership long enough for this backfill to preserve discovery history.
	addDevilFruitToolContainerCandidates(candidates, player:FindFirstChild("Backpack"))
	addDevilFruitToolContainerCandidates(candidates, player:FindFirstChild("StarterGear"))
	addDevilFruitToolContainerCandidates(candidates, player.Character)
	addEquippedDevilFruitCandidates(candidates, player, dataManager)

	local markedCount = 0
	for fruitKey in pairs(candidates) do
		local currentValue = dataManager:TryGetValue(player, "IndexCollection.DevilFruits." .. tostring(fruitKey))
		if currentValue ~= true or not hasLiveDiscoveredDevilFruitValue(player, fruitKey) then
			local marked = IndexCollectionService.MarkDevilFruitDiscovered(player, fruitKey)
			if marked then
				markedCount += 1
			end
		end
	end

	return markedCount
end

function IndexCollectionService.GetDiscoveredDevilFruitHistory(player)
	local history = getDataManager():GetValue(player, "IndexCollection.DevilFruits")
	if typeof(history) == "table" then
		return history
	end

	return nil
end

function IndexCollectionService.GetDiscoveredCrewMemberHistory(player)
	local history = getDataManager():GetValue(player, "IndexCollection.CrewMembers")
	if typeof(history) == "table" then
		return history
	end

	return nil
end

function IndexCollectionService.CountDiscoveredCrewMembers(player)
	local history = IndexCollectionService.GetDiscoveredCrewMemberHistory(player)
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
