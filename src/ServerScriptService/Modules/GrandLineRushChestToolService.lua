local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestVisuals"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local SliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))

local ChestToolService = {}

local started = false
local busyTools = {}
local syncRetryStateByPlayer = {}
local updateRemote = ReplicatedStorage:FindFirstChild("InventoryGearRemote")
local CHEST_DEBUG = true
local getChestSummaryName

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

local function createChestTool(chestName)
	local tool = Instance.new("Tool")
	tool.Name = tostring(chestName)
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	tool.ToolTip = ChestUtils.GetDisplayName(chestName)
	tool:SetAttribute("InvItem", tostring(chestName))
	tool:SetAttribute("InventoryItemKind", "Chest")
	tool:SetAttribute("InventoryItemName", tostring(chestName))
	tool:SetAttribute("GrandLineRushChestTier", ChestUtils.GetVisualStyleName(chestName))
	ChestVisuals.PopulateTool(tool, ChestUtils.GetVisualStyleName(chestName))

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

local function consumeOpenedChestTool(player, tool)
	if not tool or not tool:IsA("Tool") then
		return
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		pcall(function()
			humanoid:UnequipTools()
		end)
	end

	if tool.Parent ~= nil then
		tool:Destroy()
	end
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
			if getChestSummaryName(chest) == tierName then
				chestId = chest.ChestId
				break
			end
		end

		if not chestId then
			sendPopup(player, string.format("No %s is available to open.", ChestUtils.GetDisplayName(tierName)), ERROR_COLOR, true)
			ChestToolService.SyncPlayer(player, state)
			busyTools[busyKey] = nil
			return
		end

		local response = SliceService.OpenChest(player, chestId)
		if response and response.ok then
			consumeOpenedChestTool(player, tool)
			if typeof(response.openResult) == "table" then
				PopUpModule:Server_ShowChestOpenResult(player, response.openResult)
			else
				sendPopup(player, tostring(response.message or "Chest opened."), SUCCESS_COLOR, false)
			end
		else
			sendPopup(player, tostring((response and response.message) or "Could not open chest."), ERROR_COLOR, true)
		end

		busyTools[busyKey] = nil
	end)
end

local function syncToolForTier(player, chestName, count)
	local existingTool = findExistingChestTool(player, chestName)
	if count <= 0 then
		if existingTool and existingTool.Parent then
			chestDebug("Destroying chest tool player=%s chest=%s parent=%s because count=%d", player.Name, tostring(chestName), existingTool.Parent:GetFullName(), count)
			existingTool:Destroy()
		end
		return
	end

	if existingTool then
		connectChestTool(player, existingTool)
		chestDebug(
			"Chest tool already exists player=%s chest=%s parent=%s count=%d",
			player.Name,
			tostring(chestName),
			existingTool.Parent and existingTool.Parent:GetFullName() or "nil",
			count
		)
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if not backpack then
		chestDebug("Backpack missing while syncing chest tool player=%s chest=%s count=%d", player.Name, tostring(chestName), count)
		return
	end

	local tool = createChestTool(chestName)
	connectChestTool(player, tool)
	tool.Parent = backpack
	chestDebug(
		"Created chest tool player=%s chest=%s toolName=%s parent=%s count=%d",
		player.Name,
		tostring(chestName),
		tool.Name,
		tool.Parent and tool.Parent:GetFullName() or "nil",
		count
	)
end

getChestSummaryName = function(chest)
	if typeof(chest) ~= "table" then
		return ""
	end

	if typeof(chest.InventoryName) == "string" and chest.InventoryName ~= "" then
		return chest.InventoryName
	end

	return ChestUtils.GetInventoryName(chest)
end

local function buildTierCounts(state)
	local counts = {}
	for tierName in pairs(Economy.Chests.Tiers or {}) do
		counts[tierName] = 0
	end

	local unopenedChests = state and state.UnopenedChests or {}
	for _, chest in ipairs(unopenedChests) do
		local chestName = getChestSummaryName(chest)
		if chestName ~= "" then
			counts[chestName] = (counts[chestName] or 0) + 1
		end
	end

	return counts
end

local function hasResolvedChestState(state)
	return typeof(state) == "table"
		and typeof(state.UnopenedChests) == "table"
		and tonumber(state.UnopenedChestCount) ~= nil
end

local function clearSyncRetryState(player)
	syncRetryStateByPlayer[player] = nil
end

local function scheduleSyncRetry(player, reason)
	if not player or player.Parent ~= Players then
		return
	end

	local retryState = syncRetryStateByPlayer[player]
	if typeof(retryState) ~= "table" then
		retryState = {
			Attempts = 0,
			Pending = false,
		}
		syncRetryStateByPlayer[player] = retryState
	end

	if retryState.Pending == true then
		return
	end

	if retryState.Attempts >= 20 then
		chestDebug(
			"SyncPlayer giving up waiting for resolved state player=%s reason=%s attempts=%d",
			player.Name,
			tostring(reason),
			retryState.Attempts
		)
		return
	end

	retryState.Attempts += 1
	retryState.Pending = true

	local delaySeconds = math.min(2, 0.2 * retryState.Attempts)
	chestDebug(
		"SyncPlayer unresolved state player=%s reason=%s attempt=%d retryIn=%.1f",
		player.Name,
		tostring(reason),
		retryState.Attempts,
		delaySeconds
	)

	task.delay(delaySeconds, function()
		if player.Parent ~= Players then
			return
		end

		local latestRetryState = syncRetryStateByPlayer[player]
		if latestRetryState ~= retryState then
			return
		end

		retryState.Pending = false
		ChestToolService.SyncPlayer(player)
	end)
end

function ChestToolService.SyncPlayer(player, providedState)
	if not player or player.Parent ~= Players then
		return false
	end

	local state = providedState or SliceService.GetState(player)
	if not hasResolvedChestState(state) then
		chestDebug(
			"SyncPlayer skipped unresolved state player=%s providedState=%s unopenedCount=%s",
			player.Name,
			tostring(providedState ~= nil),
			tostring(state and state.UnopenedChestCount)
		)
		scheduleSyncRetry(player, if providedState ~= nil then "provided_state_unresolved" else "slice_state_unresolved")
		return false
	end

	clearSyncRetryState(player)
	local counts = buildTierCounts(state)
	chestDebug("SyncPlayer running for %s with unopenedCount=%d", player.Name, tonumber(state and state.UnopenedChestCount) or 0)

	local inventoryFolder = getChestInventoryFolder(player)
	local namesToSync = {}
	local validSet = {}
	for tierName in pairs(Economy.Chests.Tiers or {}) do
		namesToSync[tierName] = true
		validSet[tierName] = true
	end
	for chestName in pairs(counts) do
		namesToSync[chestName] = true
		validSet[chestName] = true
	end
	for _, child in ipairs(inventoryFolder:GetChildren()) do
		if child:IsA("Folder") then
			namesToSync[child.Name] = true
		end
	end

	for chestName in pairs(namesToSync) do
		local tierFolder = getOrCreateTierFolder(inventoryFolder, chestName)
		local quantityValue = tierFolder:FindFirstChild("Quantity")
		if quantityValue and quantityValue:IsA("NumberValue") then
			quantityValue.Value = counts[chestName] or 0
		end
		chestDebug(
			"ChestInventory write player=%s chest=%s quantity=%d folder=%s",
			player.Name,
			tostring(chestName),
			counts[chestName] or 0,
			tierFolder:GetFullName()
		)

		syncToolForTier(player, chestName, counts[chestName] or 0)
		local postTool = findExistingChestTool(player, chestName)
		chestDebug(
			"Before InventoryGearRemote fire player=%s payload={kind=Chest,name=%s,qty=%d} toolExists=%s toolParent=%s",
			player.Name,
			tostring(chestName),
			counts[chestName] or 0,
			tostring(postTool ~= nil),
			postTool and postTool.Parent and postTool.Parent:GetFullName() or "nil"
		)
		updateRemote:FireClient(player, "Chest", chestName, counts[chestName] or 0)
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
	return true
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
	Players.PlayerRemoving:Connect(clearSyncRetryState)
	SliceService.StateChanged:Connect(function(player, state)
		ChestToolService.SyncPlayer(player, state)
	end)
end

return ChestToolService
