local CrewCatalog = require(script.Parent:WaitForChild("CrewCatalog"))
local CrewMembers = require(script.Parent:WaitForChild("CrewMembers"))

local CrewVariants = CrewCatalog.GetVariantConfig()

local IndexDiscovery = {}

local VALID_CREW_MEMBER_ITEM_IDS = {}
local SORTED_CREW_MEMBER_ITEM_IDS = {}

for _, entry in ipairs(CrewMembers.GetEntries()) do
	if type(entry) == "table" then
		local crewMemberId = tostring(entry.CrewMemberId or "")
		if crewMemberId ~= "" then
			for _, variantKey in ipairs(CrewVariants.Order or { "Normal", "Golden", "Diamond" }) do
				local itemId = CrewCatalog.MakeVariantId(crewMemberId, variantKey)
				VALID_CREW_MEMBER_ITEM_IDS[itemId] = true
				SORTED_CREW_MEMBER_ITEM_IDS[#SORTED_CREW_MEMBER_ITEM_IDS + 1] = itemId
			end
		end
	end
end

table.sort(SORTED_CREW_MEMBER_ITEM_IDS)

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
			if prefix ~= "" and value:sub(1, #prefix) == prefix then
				return variantKey, value:sub(#prefix + 1)
			end
		end
	end

	return "Normal", value
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

function IndexDiscovery.IsValidCrewMemberItemId(itemId)
	return VALID_CREW_MEMBER_ITEM_IDS[tostring(itemId or "")] == true
end

function IndexDiscovery.GetSortedCrewMemberItemIds()
	return table.clone(SORTED_CREW_MEMBER_ITEM_IDS)
end

function IndexDiscovery.ResolveCrewMemberItemId(crewMemberId, baseName, variantKey)
	local crewMemberIdValue = tostring(crewMemberId or "")
	local baseNameValue = tostring(baseName or "")
	local rawVariantKey = tostring(variantKey or "")
	local normalizedVariant = normalizeVariantKey(rawVariantKey)

	local shouldTrustExactItemId = crewMemberIdValue ~= ""
		and baseNameValue == ""
		and rawVariantKey == ""
		and IndexDiscovery.IsValidCrewMemberItemId(crewMemberIdValue)
	if shouldTrustExactItemId then
		return crewMemberIdValue
	end

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
		if itemId and IndexDiscovery.IsValidCrewMemberItemId(itemId) then
			return itemId
		end
	end

	if crewMemberIdValue ~= "" then
		local resolvedId, resolvedInfo = CrewCatalog.ResolveCrewMemberId(crewMemberIdValue)
		if resolvedInfo and IndexDiscovery.IsValidCrewMemberItemId(resolvedId) then
			return resolvedId
		end

		if IndexDiscovery.IsValidCrewMemberItemId(crewMemberIdValue) then
			return crewMemberIdValue
		end
	end

	return nil
end

function IndexDiscovery.MarkDiscovered(discovered, crewMemberId, baseName, variantKey)
	if typeof(discovered) ~= "table" then
		return nil
	end

	local itemId = IndexDiscovery.ResolveCrewMemberItemId(crewMemberId, baseName, variantKey)
	if itemId then
		discovered[itemId] = true
	end

	return itemId
end

function IndexDiscovery.AddDiscoveredFromIndexMap(discovered, history)
	if typeof(discovered) ~= "table" or typeof(history) ~= "table" then
		return 0
	end

	local ignored = 0
	for rawItemId, isDiscovered in pairs(history) do
		if isDiscovered == true then
			local itemId = IndexDiscovery.ResolveCrewMemberItemId(rawItemId)
			if itemId then
				discovered[itemId] = true
			else
				ignored += 1
			end
		elseif isDiscovered ~= nil then
			ignored += 1
		end
	end

	return ignored
end

function IndexDiscovery.AddDiscoveredFromIndexFolder(discovered, folder)
	if typeof(discovered) ~= "table" or not folder then
		return 0
	end

	local ignored = 0
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BoolValue") and child.Value == true then
			local itemId = IndexDiscovery.ResolveCrewMemberItemId(child.Name)
			if itemId then
				discovered[itemId] = true
			else
				ignored += 1
			end
		elseif child:IsA("BoolValue") then
			ignored += 1
		end
	end

	return ignored
end

function IndexDiscovery.AddDiscoveredFromInventoryFolder(discovered, crewMemberInventory)
	if typeof(discovered) ~= "table" or not crewMemberInventory then
		return
	end

	local byIdFolder = crewMemberInventory:FindFirstChild("ById")
	if not byIdFolder then
		return
	end

	for _, child in ipairs(byIdFolder:GetChildren()) do
		if child:IsA("Folder") then
			IndexDiscovery.MarkDiscovered(
				discovered,
				readStringField(child, "CrewMemberId"),
				readStringField(child, "BaseName"),
				readStringField(child, "Variant")
			)
		end
	end
end

function IndexDiscovery.AddDiscoveredFromInventoryData(discovered, crewInventory)
	if typeof(discovered) ~= "table"
		or typeof(crewInventory) ~= "table"
		or typeof(crewInventory.ById) ~= "table"
	then
		return
	end

	for _, instanceData in pairs(crewInventory.ById) do
		if typeof(instanceData) == "table" then
			IndexDiscovery.MarkDiscovered(
				discovered,
				instanceData.CrewMemberId,
				instanceData.BaseName,
				instanceData.Variant
			)
		end
	end
end

function IndexDiscovery.BuildDiscoveredSetFromFolders(indexCollection, crewMemberInventory)
	local discovered = {}
	IndexDiscovery.AddDiscoveredFromIndexFolder(discovered, indexCollection and indexCollection:FindFirstChild("CrewMembers"))
	IndexDiscovery.AddDiscoveredFromInventoryFolder(discovered, crewMemberInventory)
	return discovered
end

function IndexDiscovery.BuildDiscoveredSetFromData(indexHistory, crewInventory)
	local discovered = {}
	IndexDiscovery.AddDiscoveredFromIndexMap(discovered, indexHistory)
	IndexDiscovery.AddDiscoveredFromInventoryData(discovered, crewInventory)
	return discovered
end

function IndexDiscovery.CountDiscoveredSet(discovered)
	if typeof(discovered) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(discovered) do
		count += 1
	end
	return count
end

function IndexDiscovery.CanonicalizeIndexCollectionMap(history)
	local repaired = {}
	local stats = {
		Changed = false,
		Kept = 0,
		Mapped = 0,
		Removed = 0,
	}

	if typeof(history) ~= "table" then
		stats.Changed = true
		return repaired, stats
	end

	for rawItemId, isDiscovered in pairs(history) do
		local rawKey = tostring(rawItemId or "")
		if isDiscovered == true then
			local itemId = IndexDiscovery.ResolveCrewMemberItemId(rawKey)
			if itemId then
				repaired[itemId] = true
				if itemId == rawKey then
					stats.Kept += 1
				else
					stats.Mapped += 1
					stats.Changed = true
				end
			else
				stats.Removed += 1
				stats.Changed = true
			end
		else
			stats.Removed += 1
			stats.Changed = true
		end
	end

	return repaired, stats
end

return IndexDiscovery
