local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestVisuals"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local SliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))

local ChestToolService = {}

local started = false
local busyTools = {}
local updateRemote = ReplicatedStorage:FindFirstChild("InventoryGearRemote")
local CHEST_DEBUG = true

local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local function chestDebug(message, ...)
	if CHEST_DEBUG ~= true then
		return
	end

	warn(string.format("[GLR ChestDebug][ToolService] " .. tostring(message), ...))
end

if not updateRemote then
	updateRemote = Instance.new("RemoteEvent")
	updateRemote.Name = "InventoryGearRemote"
	updateRemote.Parent = ReplicatedStorage
end

local function sendPopup(player, text, color, isError)
	if not player or player.Parent ~= Players then
		return
	end

	PopUpModule:Server_SendPopUp(player, text, color or SUCCESS_COLOR, STROKE_COLOR, 3, isError == true)
end

local function getChestInventoryFolder(player)
	local folder = player:FindFirstChild("ChestInventory")
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = "ChestInventory"
	folder.Parent = player
	return folder
end

local function getOrCreateTierFolder(parent, tierName)
	local folder = parent:FindFirstChild(tierName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = tierName
	folder.Parent = parent

	local quantity = Instance.new("NumberValue")
	quantity.Name = "Quantity"
	quantity.Value = 0
	quantity.Parent = folder

	return folder
end

local function destroyExtraTierFolders(parent, validSet)
	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Folder") and validSet[child.Name] ~= true then
			child:Destroy()
		end
	end
end

local function createChestTool(tierName)
	local tool = Instance.new("Tool")
	tool.Name = tostring(tierName)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = string.format("%s Chest", tostring(tierName))
	tool:SetAttribute("InvItem", tostring(tierName))
	tool:SetAttribute("InventoryItemKind", "Chest")
	tool:SetAttribute("InventoryItemName", tostring(tierName))
	tool:SetAttribute("GrandLineRushChestTier", tostring(tierName))
	ChestVisuals.PopulateTool(tool, tierName)

	return tool
end

local function getToolContainers(player)
	return {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
	}
end

local function findExistingChestTool(player, tierName)
	for _, container in ipairs(getToolContainers(player)) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool")
					and child:GetAttribute("InventoryItemKind") == "Chest"
					and child:GetAttribute("InventoryItemName") == tierName then
					return child
				end
			end
		end
	end

	return nil
end

local function connectChestTool(player, tool)
	if not tool or not tool:IsA("Tool") then
		return
	end
	if tool:GetAttribute("GrandLineRushChestBound") == true then
		return
	end

	tool:SetAttribute("GrandLineRushChestBound", true)
	tool.Equipped:Connect(function()
		chestDebug(
			"Tool Equipped player=%s tool=%s parent=%s",
			player.Name,
			tostring(tool.Name),
			tool.Parent and tool.Parent:GetFullName() or "nil"
		)
	end)
	tool.Unequipped:Connect(function()
		chestDebug(
			"Tool Unequipped player=%s tool=%s parent=%s",
			player.Name,
			tostring(tool.Name),
			tool.Parent and tool.Parent:GetFullName() or "nil"
		)
	end)
	tool.AncestryChanged:Connect(function(_, parent)
		chestDebug(
			"Tool AncestryChanged player=%s tool=%s newParent=%s",
			player.Name,
			tostring(tool.Name),
			parent and parent:GetFullName() or "nil"
		)
	end)
	tool.Activated:Connect(function()
		if tool.Parent == nil or player.Parent ~= Players then
			return
		end

		local busyKey = string.format("%d:%s", player.UserId, tostring(tool:GetAttribute("InventoryItemName") or tool.Name))
		if busyTools[busyKey] then
			return
		end
		busyTools[busyKey] = true

		local tierName = tostring(tool:GetAttribute("InventoryItemName") or tool.Name)
		local state = SliceService.GetState(player)
		local unopenedChests = state and state.UnopenedChests or {}
		local chestId = nil
		for _, chest in ipairs(unopenedChests) do
			if tostring(chest.Tier) == tierName then
				chestId = chest.ChestId
				break
			end
		end

		if not chestId then
			sendPopup(player, string.format("No %s chest is available to open.", tierName), ERROR_COLOR, true)
			ChestToolService.SyncPlayer(player, state)
			busyTools[busyKey] = nil
			return
		end

		local response = SliceService.OpenChest(player, chestId)
		if response and response.ok then
			sendPopup(player, tostring(response.message or "Chest opened."), SUCCESS_COLOR, false)
		else
			sendPopup(player, tostring((response and response.message) or "Could not open chest."), ERROR_COLOR, true)
		end

		busyTools[busyKey] = nil
	end)
end

local function syncToolForTier(player, tierName, count)
	local existingTool = findExistingChestTool(player, tierName)
	if count <= 0 then
		if existingTool and existingTool.Parent then
			chestDebug("Destroying chest tool player=%s tier=%s parent=%s because count=%d", player.Name, tostring(tierName), existingTool.Parent:GetFullName(), count)
			existingTool:Destroy()
		end
		return
	end

	if existingTool then
		connectChestTool(player, existingTool)
		chestDebug(
			"Chest tool already exists player=%s tier=%s parent=%s count=%d",
			player.Name,
			tostring(tierName),
			existingTool.Parent and existingTool.Parent:GetFullName() or "nil",
			count
		)
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		chestDebug("Backpack missing while syncing chest tool player=%s tier=%s count=%d", player.Name, tostring(tierName), count)
		return
	end

	local tool = createChestTool(tierName)
	connectChestTool(player, tool)
	tool.Parent = backpack
	chestDebug(
		"Created chest tool player=%s tier=%s toolName=%s parent=%s count=%d",
		player.Name,
		tostring(tierName),
		tool.Name,
		tool.Parent and tool.Parent:GetFullName() or "nil",
		count
	)
end

local function buildTierCounts(state)
	local counts = {}
	for tierName in pairs(Economy.Chests.Tiers or {}) do
		counts[tierName] = 0
	end

	local unopenedChests = state and state.UnopenedChests or {}
	for _, chest in ipairs(unopenedChests) do
		local tierName = tostring(chest.Tier or "Wooden")
		counts[tierName] = (counts[tierName] or 0) + 1
	end

	return counts
end

function ChestToolService.SyncPlayer(player, providedState)
	if not player or player.Parent ~= Players then
		return
	end

	local state = providedState or SliceService.GetState(player)
	local counts = buildTierCounts(state)
	chestDebug("SyncPlayer running for %s with unopenedCount=%d", player.Name, tonumber(state and state.UnopenedChestCount) or 0)

	local inventoryFolder = getChestInventoryFolder(player)
	local validSet = {}
	for tierName in pairs(Economy.Chests.Tiers or {}) do
		validSet[tierName] = true
		local tierFolder = getOrCreateTierFolder(inventoryFolder, tierName)
		local quantityValue = tierFolder:FindFirstChild("Quantity")
		if quantityValue and quantityValue:IsA("NumberValue") then
			quantityValue.Value = counts[tierName] or 0
		end
		chestDebug(
			"ChestInventory write player=%s tier=%s quantity=%d folder=%s",
			player.Name,
			tostring(tierName),
			counts[tierName] or 0,
			tierFolder:GetFullName()
		)

		syncToolForTier(player, tierName, counts[tierName] or 0)
		local postTool = findExistingChestTool(player, tierName)
		chestDebug(
			"Before InventoryGearRemote fire player=%s payload={kind=Chest,name=%s,qty=%d} toolExists=%s toolParent=%s",
			player.Name,
			tostring(tierName),
			counts[tierName] or 0,
			tostring(postTool ~= nil),
			postTool and postTool.Parent and postTool.Parent:GetFullName() or "nil"
		)
		updateRemote:FireClient(player, "Chest", tierName, counts[tierName] or 0)
	end

	local folderDump = {}
	for _, child in ipairs(inventoryFolder:GetChildren()) do
		if child:IsA("Folder") then
			local qty = child:FindFirstChild("Quantity")
			folderDump[#folderDump + 1] = string.format("%s=%s", child.Name, qty and tostring(qty.Value) or "nil")
		end
	end
	chestDebug("ChestInventory contents player=%s %s", player.Name, table.concat(folderDump, ", "))

	destroyExtraTierFolders(inventoryFolder, validSet)
end

function ChestToolService.EnsureToolForTier(player, tierName, providedState)
	if not player or player.Parent ~= Players then
		return nil
	end

	local normalizedTier = tostring(tierName or "")
	if normalizedTier == "" then
		return nil
	end

	local existing = findExistingChestTool(player, normalizedTier)
	if existing then
		connectChestTool(player, existing)
		return existing
	end

	ChestToolService.SyncPlayer(player, providedState)

	existing = findExistingChestTool(player, normalizedTier)
	if existing then
		connectChestTool(player, existing)
	end

	return existing
end

function ChestToolService.Start()
	if started then
		return
	end

	started = true
	SliceService.Start()

	local function setupPlayer(player)
		getChestInventoryFolder(player)
		task.defer(function()
			ChestToolService.SyncPlayer(player)
		end)

		player.CharacterAdded:Connect(function()
			task.delay(0.2, function()
				if player.Parent == Players then
					ChestToolService.SyncPlayer(player)
				end
			end)
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		setupPlayer(player)
	end

	Players.PlayerAdded:Connect(setupPlayer)
	SliceService.StateChanged:Connect(function(player, state)
		ChestToolService.SyncPlayer(player, state)
	end)
end

return ChestToolService
