local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewModules = Modules:WaitForChild("Crew")
local CrewCatalog = require(CrewModules:WaitForChild("CrewCatalog"))
local CrewRegistry = require(CrewModules:WaitForChild("CrewRegistry"))
local CrewInstanceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))

local CREW_ITEM_KIND = "CrewMember"
local CANONICAL_INVENTORY_NAME = "CrewMemberInventory"
local CANONICAL_BY_ID_NAME = "ById"

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
	local variantKey, baseName = getVariantAndBaseName(canonicalItemName)
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

local function applyToolMetadata(tool, itemName, variantKey, baseName)
	local canonicalItemName, resolvedInfo, legacyStorageName = resolveCrewItemName(itemName)
	itemName = canonicalItemName
	local parsedVariant, parsedBaseName = getVariantAndBaseName(itemName)
	variantKey = variantKey or parsedVariant
	baseName = baseName or parsedBaseName

	local info = resolvedInfo or CrewCatalog.GetInfoById(itemName) or CrewCatalog.GetInfoById(baseName)
	local displayName = tostring((info and (info.DisplayName or info.Name)) or itemName)
	local productionName = tostring((info and (info.RealCharacterName or info.ModelName or info.CrewMemberId)) or "")
	local realCharacterName = tostring((info and info.RealCharacterName) or "")
	local modelName = tostring((info and info.ModelName) or baseName)
	local crewMemberId = tostring((info and info.CrewMemberId) or itemName)

	tool.Name = itemName
	tool.ToolTip = displayName
	tool:SetAttribute("InvItem", itemName)
	tool:SetAttribute("InventoryItemKind", CREW_ITEM_KIND)
	tool:SetAttribute("InventoryItemName", itemName)
	tool:SetAttribute("DisplayName", displayName)
	tool:SetAttribute("CrewMemberDisplayName", displayName)
	tool:SetAttribute("Variant", variantKey)
	tool:SetAttribute("BaseName", baseName)
	tool:SetAttribute("ModelName", modelName)
	tool:SetAttribute("CrewMemberId", crewMemberId)
	_ = legacyStorageName

	if productionName ~= "" then
		tool:SetAttribute("ProductionName", productionName)
	end
	if realCharacterName ~= "" then
		tool:SetAttribute("RealCharacterName", realCharacterName)
	end
	return itemName
end

local function makeTool(itemName)
	local template, variantKey, baseName, canonicalItemName = findTemplate(itemName)
	if not template then
		return nil
	end

	local tool = Instance.new("Tool")
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	applyToolMetadata(tool, canonicalItemName or itemName, variantKey, baseName)

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

local function normalizeCount(value)
	local count = tonumber(value) or 0
	if count < 0 then
		count = 0
	end
	return math.floor(count + 1e-9)
end

local function addDesiredCount(counts, itemName, amount)
	itemName = resolveCrewItemName(itemName)
	if itemName == "" or not isKnownCrewItem(itemName) then
		return
	end

	counts[itemName] = normalizeCount((counts[itemName] or 0) + amount)
end

local function readCanonicalCountsFromData(player, inventory)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return nil, false
	end

	local counts = {}
	local hasCanonicalData = false
	for _, instanceData in pairs(inventory.ById) do
		if typeof(instanceData) == "table" then
			local storageName = tostring(
				instanceData.CrewMemberId
					or instanceData.StorageName
					or ""
			)
			local canonicalStorageName = resolveCrewItemName(storageName)
			if canonicalStorageName ~= "" and isKnownCrewItem(canonicalStorageName) then
				hasCanonicalData = true
				if tostring(instanceData.AssignedStand or "") == "" then
					addDesiredCount(counts, canonicalStorageName, 1)
				end
			elseif storageName ~= "" then
				warnInvalidCrewToolIdentity("inventory_data", player, storageName)
			end
		end
	end

	return counts, hasCanonicalData
end

local function readCanonicalCountsFromService(player)
	if player:GetAttribute("PlayerDataReady") ~= true then
		return nil, false
	end

	local ok, inventory = pcall(function()
		return CrewInstanceService.GetCrewInventory(player)
	end)
	if not ok then
		return nil, false
	end

	return readCanonicalCountsFromData(player, inventory)
end

local function readCanonicalCountsFromFolder(player)
	local root = player:FindFirstChild(CANONICAL_INVENTORY_NAME)
	if not root or not root:IsA("Folder") then
		return nil, false
	end

	local byId = root:FindFirstChild(CANONICAL_BY_ID_NAME)
	if not byId or not byId:IsA("Folder") then
		return nil, false
	end

	local counts = {}
	local hasCanonicalData = false
	for _, instanceFolder in ipairs(byId:GetChildren()) do
		if instanceFolder:IsA("Folder") then
			local storageName = tostring(
				readValue(instanceFolder, "CrewMemberId")
					or readValue(instanceFolder, "StorageName")
					or ""
			)
			local canonicalStorageName = resolveCrewItemName(storageName)
			if canonicalStorageName ~= "" and isKnownCrewItem(canonicalStorageName) then
				hasCanonicalData = true
				if tostring(readValue(instanceFolder, "AssignedStand") or "") == "" then
					addDesiredCount(counts, canonicalStorageName, 1)
				end
			elseif storageName ~= "" then
				warnInvalidCrewToolIdentity("inventory_folder", player, storageName)
			end
		end
	end

	return counts, hasCanonicalData
end

local function getDesiredCrewCounts(player)
	local counts, hasCanonicalData = readCanonicalCountsFromService(player)
	if hasCanonicalData then
		return counts
	end

	counts, hasCanonicalData = readCanonicalCountsFromFolder(player)
	if hasCanonicalData then
		return counts
	end

	return {}
end

local function collectCrewTools(player, container, toolsByName)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and isCrewTool(child) then
			local itemName = getToolItemName(child)
			if itemName ~= "" then
				local canonicalItemName = resolveCrewItemName(itemName)
				if canonicalItemName ~= "" then
					itemName = applyToolMetadata(child, canonicalItemName) or canonicalItemName
					toolsByName[itemName] = toolsByName[itemName] or {}
					table.insert(toolsByName[itemName], child)
				else
					warnInvalidCrewToolIdentity("existing_tool", player, itemName)
					toolsByName[itemName] = toolsByName[itemName] or {}
					table.insert(toolsByName[itemName], child)
				end
			end
		end
	end
end

local function syncDesiredTools(player, desiredCounts)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return
	end

	local toolsByName = {}
	collectCrewTools(player, backpack, toolsByName)
	collectCrewTools(player, player.Character, toolsByName)

	for itemName, tools in pairs(toolsByName) do
		local desiredCount = normalizeCount(desiredCounts[itemName] or 0)
		for index = #tools, desiredCount + 1, -1 do
			local tool = tools[index]
			if tool and tool.Parent then
				tool:Destroy()
			end
			tools[index] = nil
		end
	end

	for itemName, desiredCount in pairs(desiredCounts) do
		desiredCount = normalizeCount(desiredCount)
		local tools = toolsByName[itemName] or {}
		for _ = #tools + 1, desiredCount do
			local tool = makeTool(itemName)
			if tool then
				tool.Parent = backpack
			end
		end
	end
end

local function syncCrewTools(player)
	local desiredCounts = getDesiredCrewCounts(player)
	syncDesiredTools(player, desiredCounts)
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
	return rootName == CANONICAL_INVENTORY_NAME
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
