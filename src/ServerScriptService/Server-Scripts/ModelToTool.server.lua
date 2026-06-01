local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewModules = Modules:WaitForChild("Crew")
local CrewCatalog = require(CrewModules:WaitForChild("CrewCatalog"))
local CrewRegistry = require(CrewModules:WaitForChild("CrewRegistry"))
local CrewInstanceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewQuickSlotService"))

local CREW_ITEM_KIND = "CrewMember"
local CANONICAL_INVENTORY_NAME = "CrewMemberInventory"
local CANONICAL_BY_ID_NAME = "ById"
local QUICK_SLOT_ROOT_NAME = "CrewMemberQuickSlots"

local playerConnections = {}
local playerBoundRoots = {}
local playerSyncQueued = {}
local invalidCrewToolWarnings = {}

local function addConnection(player, connection)
	playerConnections[player] = playerConnections[player] or {}
	table.insert(playerConnections[player], connection)
end

local function disconnectPlayer(player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end

	playerConnections[player] = nil
	playerBoundRoots[player] = nil
	playerSyncQueued[player] = nil
end

local function getVariantAndBaseName(itemName)
	return CrewCatalog.ParseVariantId(itemName)
end

local function resolveCrewItemName(itemName)
	local canonicalItemName, info, legacyStorageName = CrewCatalog.ResolveCanonicalCrewMemberId(itemName)
	if info then
		return canonicalItemName, info, legacyStorageName
	end
	return "", nil, ""
end

local function warnInvalidCrewToolIdentity(source, player, identity)
	local key = tostring(source or "unknown") .. ":" .. (player and tostring(player.UserId) or "unknown") .. ":" .. tostring(identity or "")
	if invalidCrewToolWarnings[key] then
		return
	end
	invalidCrewToolWarnings[key] = true
	warn(string.format(
		"[ModelToTool] Rejected unknown CrewMember identity source=%s player=%s identity=%s",
		tostring(source or "unknown"),
		player and player.Name or "unknown",
		tostring(identity or "")
	))
end

local function getCrewInfo(itemName)
	local canonicalItemName, info = resolveCrewItemName(itemName)
	if info then
		return info
	end
	local _, baseName = getVariantAndBaseName(canonicalItemName)
	return CrewCatalog.GetInfoById(canonicalItemName) or CrewCatalog.GetInfoById(baseName)
end

local function findTemplate(itemName)
	local canonicalItemName = resolveCrewItemName(itemName)
	if canonicalItemName == "" then
		return nil
	end
	local displayInfo = CrewCatalog.GetDisplayInfo(canonicalItemName)
	local variantKey = tostring(displayInfo.Variant or "Normal")
	local baseName = tostring(displayInfo.BaseId or canonicalItemName)
	local template, usedVariant = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
	if template then
		return template, usedVariant or variantKey, baseName, canonicalItemName
	end

	template, usedVariant = CrewRegistry.GetTemplateWithFallback(canonicalItemName, "Normal")
	return template, usedVariant or variantKey, baseName, canonicalItemName
end

local function isKnownCrewItem(itemName)
	if tostring(itemName or "") == "" then
		return false
	end
	if getCrewInfo(itemName) ~= nil then
		return true
	end

	local template = findTemplate(itemName)
	return template ~= nil
end

local function normalizeItemKind(kind)
	return kind
end

local function getToolItemName(tool)
	local itemName = tool:GetAttribute("InventoryItemName") or tool:GetAttribute("InvItem")
	if typeof(itemName) == "string" and itemName ~= "" then
		return itemName
	end
	return tool.Name
end

local function isCrewTool(tool)
	if not tool:IsA("Tool") then
		return false
	end

	local kind = normalizeItemKind(tool:GetAttribute("InventoryItemKind"))
	if kind == CREW_ITEM_KIND then
		return true
	end
	if typeof(kind) == "string" and kind ~= "" then
		return false
	end

	return isKnownCrewItem(getToolItemName(tool))
end

local function applyToolMetadata(tool, itemName, variantKey, baseName, instanceId, instanceData)
	local canonicalItemName, resolvedInfo, legacyStorageName = resolveCrewItemName(itemName)
	itemName = canonicalItemName
	instanceData = if typeof(instanceData) == "table" then instanceData else {}
	instanceId = tostring(instanceId or instanceData.InstanceId or "")
	local displayInfo = CrewCatalog.GetDisplayInfo(itemName, instanceData)
	variantKey = variantKey or displayInfo.Variant or "Normal"
	baseName = baseName or displayInfo.BaseId or itemName

	local info = resolvedInfo or CrewCatalog.GetInfoById(itemName) or CrewCatalog.GetInfoById(baseName)
	local displayName = tostring(displayInfo.DisplayName or (info and (info.DisplayName or info.Name)) or itemName)
	local productionName = tostring((info and (info.RealCharacterName or info.ModelName or info.CrewMemberId)) or "")
	local realCharacterName = tostring((info and info.RealCharacterName) or "")
	local modelName = tostring((info and info.ModelName) or baseName)
	local crewMemberId = tostring((info and info.CrewMemberId) or itemName)
	local rarity = tostring(instanceData.Rarity or (info and info.Rarity) or "")
	local income = tonumber(instanceData.Income or (info and info.Income))

	tool.Name = itemName
	tool.ToolTip = displayName
	tool:SetAttribute("InvItem", itemName)
	tool:SetAttribute("InventoryItemKind", CREW_ITEM_KIND)
	tool:SetAttribute("InventoryItemName", itemName)
	tool:SetAttribute("CrewMemberInstanceId", if instanceId ~= "" then instanceId else nil)
	tool:SetAttribute("CrewInstanceId", if instanceId ~= "" then instanceId else nil)
	tool:SetAttribute("DisplayName", displayName)
	tool:SetAttribute("CrewMemberDisplayName", displayName)
	tool:SetAttribute("Variant", variantKey)
	tool:SetAttribute("BaseName", baseName)
	tool:SetAttribute("CrewMemberBaseDisplayName", displayInfo.BaseDisplayName)
	tool:SetAttribute("CrewMemberVariantTag", if tostring(displayInfo.VariantTag or "") ~= "" then displayInfo.VariantTag else nil)
	tool:SetAttribute("CrewMemberVariantDisplayName", displayInfo.VariantDisplayName)
	tool:SetAttribute("CrewMemberShowVariantTag", displayInfo.ShowVariantTag == true)
	tool:SetAttribute("ModelName", modelName)
	tool:SetAttribute("CrewMemberId", crewMemberId)
	tool:SetAttribute("CrewMemberRarity", if rarity ~= "" then rarity else nil)
	tool:SetAttribute("CrewMemberIncome", income)
	tool:SetAttribute("CrewMemberLevel", tonumber(instanceData.Level))
	tool:SetAttribute("CrewMemberCurrentXP", tonumber(instanceData.CurrentXP))
	tool:SetAttribute("CrewMemberTotalXP", tonumber(instanceData.TotalXP))
	_ = legacyStorageName

	if productionName ~= "" then
		tool:SetAttribute("ProductionName", productionName)
	end
	if realCharacterName ~= "" then
		tool:SetAttribute("RealCharacterName", realCharacterName)
	end
	return itemName
end

local function makeTool(itemName, instanceId, instanceData)
	local template, variantKey, baseName, canonicalItemName = findTemplate(itemName)
	if not template then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	applyToolMetadata(tool, canonicalItemName or itemName, variantKey, baseName, instanceId, instanceData)

	local function setupPart(part)
		part.Anchored = false
		part.CanCollide = false
		part.Massless = true
	end

	if template:IsA("BasePart") then
		local handle = template:Clone()
		handle.Name = "Handle"
		setupPart(handle)
		handle.CFrame = CFrame.new()
		handle.Parent = tool
		return tool
	end

	if not template:IsA("Model") then
		tool:Destroy()
		return nil
	end

	local primary = template.PrimaryPart
	if not primary then
		for _, descendant in ipairs(template:GetDescendants()) do
			if descendant:IsA("BasePart") then
				primary = descendant
				break
			end
		end
	end
	if not primary then
		tool:Destroy()
		return nil
	end

	local base = CFrame.new()
	local clones = {}

	for _, descendant in ipairs(template:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local clone = descendant:Clone()
			setupPart(clone)
			local rel = primary.CFrame:ToObjectSpace(descendant.CFrame)
			clone.CFrame = base * rel
			clone.Parent = tool
			clones[descendant] = clone
		end
	end

	local handle = clones[primary]
	if not handle then
		tool:Destroy()
		return nil
	end
	handle.Name = "Handle"

	for _, clone in pairs(clones) do
		if clone ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = clone
			weld.Parent = handle
		end
	end

	return tool
end

local function readValue(parent, childName)
	local child = parent and parent:FindFirstChild(childName)
	if child and child:IsA("ValueBase") then
		return child.Value
	end
	return nil
end

local function getToolInstanceId(tool)
	if not tool or not tool:IsA("Tool") then
		return ""
	end
	return tostring(tool:GetAttribute("CrewMemberInstanceId") or tool:GetAttribute("CrewInstanceId") or "")
end

local function addDesiredTool(tools, player, instanceId, itemName, instanceData, source)
	instanceId = tostring(instanceId or "")
	itemName = resolveCrewItemName(itemName)
	if instanceId == "" or itemName == "" or not isKnownCrewItem(itemName) then
		warnInvalidCrewToolIdentity(source or "desired_tool", player, itemName)
		return
	end

	table.insert(tools, {
		InstanceId = instanceId,
		ItemName = itemName,
		InstanceData = if typeof(instanceData) == "table" then instanceData else nil,
	})
end

local function readQuickSlotAssignments(player)
	local ok, assignments = pcall(function()
		return CrewQuickSlotService.GetAssignments(player)
	end)
	if ok and typeof(assignments) == "table" then
		return assignments
	end
	return {}
end

local function getSortedAssignedInstanceIds(assignments)
	local assignedSlots = {}
	for rawSlotIndex, rawInstanceId in pairs(if typeof(assignments) == "table" then assignments else {}) do
		local slotIndex = tonumber(rawSlotIndex)
		local instanceId = tostring(rawInstanceId or "")
		if slotIndex ~= nil and instanceId ~= "" then
			table.insert(assignedSlots, {
				SlotIndex = slotIndex,
				InstanceId = instanceId,
			})
		end
	end

	table.sort(assignedSlots, function(left, right)
		return left.SlotIndex < right.SlotIndex
	end)

	local ids = {}
	for _, entry in ipairs(assignedSlots) do
		table.insert(ids, entry.InstanceId)
	end
	return ids
end

local function readCanonicalToolsFromData(player, inventory)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return nil, false
	end

	local tools = {}
	local hasCanonicalData = true
	for _, instanceId in ipairs(getSortedAssignedInstanceIds(readQuickSlotAssignments(player))) do
		local instanceData = inventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" then
			local storageName = tostring(
				instanceData.CrewMemberId
					or instanceData.StorageName
					or ""
			)
			local canonicalStorageName = resolveCrewItemName(storageName)
			if canonicalStorageName ~= "" and isKnownCrewItem(canonicalStorageName) then
				if tostring(instanceData.AssignedStand or "") == "" and instanceData.Overflow ~= true then
					addDesiredTool(tools, player, instanceId, canonicalStorageName, instanceData, "inventory_data")
				end
			elseif storageName ~= "" then
				warnInvalidCrewToolIdentity("inventory_data", player, storageName)
			end
		end
	end

	return tools, hasCanonicalData
end

local function readCanonicalToolsFromService(player)
	if player:GetAttribute("PlayerDataReady") ~= true then
		return nil, false
	end

	local ok, inventory = pcall(function()
		return CrewInstanceService.GetCrewInventory(player)
	end)
	if not ok then
		return nil, false
	end

	return readCanonicalToolsFromData(player, inventory)
end

local function readCanonicalToolsFromFolder(player)
	local root = player:FindFirstChild(CANONICAL_INVENTORY_NAME)
	if not root or not root:IsA("Folder") then
		return nil, false
	end

	local byId = root:FindFirstChild(CANONICAL_BY_ID_NAME)
	if not byId or not byId:IsA("Folder") then
		return nil, false
	end

	local tools = {}
	local hasCanonicalData = true
	for _, assignedInstanceId in ipairs(getSortedAssignedInstanceIds(readQuickSlotAssignments(player))) do
		local instanceFolder = byId:FindFirstChild(tostring(assignedInstanceId))
		if instanceFolder and instanceFolder:IsA("Folder") then
			local instanceId = tostring(readValue(instanceFolder, "InstanceId") or instanceFolder.Name or "")
			local storageName = tostring(
				readValue(instanceFolder, "CrewMemberId")
					or readValue(instanceFolder, "StorageName")
					or ""
			)
			local canonicalStorageName = resolveCrewItemName(storageName)
			if canonicalStorageName ~= "" and isKnownCrewItem(canonicalStorageName) then
				if tostring(readValue(instanceFolder, "AssignedStand") or "") == "" and readValue(instanceFolder, "Overflow") ~= true then
					addDesiredTool(tools, player, instanceId, canonicalStorageName, {
						InstanceId = instanceId,
						StorageName = canonicalStorageName,
						CrewMemberId = canonicalStorageName,
						Rarity = readValue(instanceFolder, "Rarity"),
						Level = readValue(instanceFolder, "Level"),
						CurrentXP = readValue(instanceFolder, "CurrentXP"),
						TotalXP = readValue(instanceFolder, "TotalXP"),
					}, "inventory_folder")
				end
			elseif storageName ~= "" then
				warnInvalidCrewToolIdentity("inventory_folder", player, storageName)
			end
		end
	end

	return tools, hasCanonicalData
end

local function getDesiredCrewTools(player)
	local tools, hasCanonicalData = readCanonicalToolsFromService(player)
	if hasCanonicalData then
		return tools
	end

	tools, hasCanonicalData = readCanonicalToolsFromFolder(player)
	if hasCanonicalData then
		return tools
	end

	return {}
end

local function collectCrewTools(player, container, tools)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and isCrewTool(child) then
			local itemName = getToolItemName(child)
			if itemName ~= "" then
				local canonicalItemName = resolveCrewItemName(itemName)
				if canonicalItemName ~= "" then
					applyToolMetadata(child, canonicalItemName, nil, nil, getToolInstanceId(child))
					table.insert(tools, child)
				else
					warnInvalidCrewToolIdentity("existing_tool", player, itemName)
					table.insert(tools, child)
				end
			end
		end
	end
end

local function syncDesiredTools(player, desiredTools)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local existingTools = {}
	collectCrewTools(player, backpack, existingTools)
	collectCrewTools(player, player.Character, existingTools)

	local desiredById = {}
	for _, desired in ipairs(desiredTools or {}) do
		desiredById[tostring(desired.InstanceId or "")] = desired
	end

	local toolsByInstanceId = {}
	local toolsByName = {}
	for _, tool in ipairs(existingTools) do
		local itemName = resolveCrewItemName(getToolItemName(tool))
		local instanceId = getToolInstanceId(tool)
		if instanceId ~= "" then
			toolsByInstanceId[instanceId] = toolsByInstanceId[instanceId] or {}
			table.insert(toolsByInstanceId[instanceId], tool)
		end
		if itemName ~= "" then
			toolsByName[itemName] = toolsByName[itemName] or {}
			table.insert(toolsByName[itemName], tool)
		end
	end

	local usedTools = {}

	local function useTool(tool, desired)
		usedTools[tool] = true
		applyToolMetadata(tool, desired.ItemName, nil, nil, desired.InstanceId, desired.InstanceData)
	end

	for _, desired in ipairs(desiredTools or {}) do
		local desiredInstanceId = tostring(desired.InstanceId or "")
		local selectedTool = nil
		for _, candidate in ipairs(toolsByInstanceId[desiredInstanceId] or {}) do
			if not usedTools[candidate] then
				selectedTool = candidate
				break
			end
		end

		if not selectedTool then
			for _, candidate in ipairs(toolsByName[desired.ItemName] or {}) do
				local candidateInstanceId = getToolInstanceId(candidate)
				if
					not usedTools[candidate]
					and (candidateInstanceId == "" or desiredById[candidateInstanceId] == nil)
				then
					selectedTool = candidate
					break
				end
			end
		end

		if selectedTool then
			useTool(selectedTool, desired)
		else
			local tool = makeTool(desired.ItemName, desired.InstanceId, desired.InstanceData)
			if tool then
				tool.Parent = backpack
				usedTools[tool] = true
			end
		end
	end

	for _, tool in ipairs(existingTools) do
		if not usedTools[tool] and tool.Parent then
			tool:Destroy()
		end
	end
end

local function syncCrewTools(player)
	local desiredTools = getDesiredCrewTools(player)
	syncDesiredTools(player, desiredTools)
end

local function scheduleSync(player)
	if not player or player.Parent ~= Players or playerSyncQueued[player] then
		return
	end

	playerSyncQueued[player] = true
	task.defer(function()
		playerSyncQueued[player] = nil
		if player.Parent == Players then
			syncCrewTools(player)
		end
	end)
end

local function isTrackedRootName(rootName)
	return rootName == CANONICAL_INVENTORY_NAME or rootName == QUICK_SLOT_ROOT_NAME
end

local function bindValueObject(player, object)
	if not object:IsA("ValueBase") then
		return
	end

	addConnection(player, object.Changed:Connect(function()
		scheduleSync(player)
	end))
end

local function bindInventoryRoot(player, root)
	if not root or not root:IsA("Folder") then
		return
	end

	playerBoundRoots[player] = playerBoundRoots[player] or {}
	if playerBoundRoots[player][root] then
		return
	end
	playerBoundRoots[player][root] = true

	for _, descendant in ipairs(root:GetDescendants()) do
		bindValueObject(player, descendant)
	end

	addConnection(player, root.DescendantAdded:Connect(function(descendant)
		bindValueObject(player, descendant)
		scheduleSync(player)
	end))
	addConnection(player, root.DescendantRemoving:Connect(function()
		scheduleSync(player)
	end))
	scheduleSync(player)
end

local function bindKnownInventoryRoots(player)
	local canonicalRoot = player:FindFirstChild(CANONICAL_INVENTORY_NAME)
	if canonicalRoot then
		bindInventoryRoot(player, canonicalRoot)
	end
	local quickSlotRoot = player:FindFirstChild(QUICK_SLOT_ROOT_NAME)
	if quickSlotRoot then
		bindInventoryRoot(player, quickSlotRoot)
	end
end

local function setupPlayer(player)
	disconnectPlayer(player)

	addConnection(player, player.ChildAdded:Connect(function(child)
		if isTrackedRootName(child.Name) and child:IsA("Folder") then
			bindInventoryRoot(player, child)
		elseif child:IsA("Backpack") then
			scheduleSync(player)
		end
	end))

	addConnection(player, player.ChildRemoved:Connect(function(child)
		if isTrackedRootName(child.Name) or child:IsA("Backpack") then
			scheduleSync(player)
		end
	end))

	addConnection(player, player.CharacterAdded:Connect(function()
		task.defer(function()
			scheduleSync(player)
		end)
	end))

	bindKnownInventoryRoots(player)
	scheduleSync(player)
end

CrewInstanceService.RegisterCrewInventorySavedCallback(function(player)
	scheduleSync(player)
end)

Players.PlayerAdded:Connect(setupPlayer)
Players.PlayerRemoving:Connect(disconnectPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end
