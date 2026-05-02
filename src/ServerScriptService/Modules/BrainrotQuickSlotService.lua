local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BrainrotQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotQuickSlots"))
local Brainrots = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local BrainrotVariants = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotVariants"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))

local BrainrotQuickSlotService = {}

local QUICK_SLOT_PATH = "BrainrotQuickSlots"
local LEGACY_STORAGE_PATH = "BrainrotStorage"
local DATA_READY_TIMEOUT = 30
local INFO_COLOR = Color3.fromRGB(255, 229, 132)
local SUCCESS_COLOR = Color3.fromRGB(90, 255, 145)
local ERROR_COLOR = Color3.fromRGB(255, 86, 86)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local FULL_MESSAGE = "Brainrot quick slots full. Unlock another slot to carry more."

local RARITY_ORDER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Mythical = 6,
	Godly = 7,
	Secret = 8,
	Omega = 9,
}

local dataManagerModule = nil
local initialized = false

local function getDataManager()
	if dataManagerModule == nil then
		dataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerModule
end

local function sendPopup(player, text, color, isError)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	print(string.format(
		"[BrainrotQuickSlots] popup sent player=%s text=%s",
		player.Name,
		tostring(text)
	))
	PopUpModule:Server_SendPopUp(player, text, color or INFO_COLOR, STROKE_COLOR, 3, isError == true)
end

local function waitForReady(player)
	local dataManager = getDataManager()
	if dataManager:IsReady(player) then
		return true
	end
	if dataManager.WaitUntilReady then
		return dataManager:WaitUntilReady(player, DATA_READY_TIMEOUT)
	end
	return false
end

local function canPromptUnlockProduct(productId)
	productId = tonumber(productId)
	if not productId or productId <= 0 then
		return false, "missing_product_id"
	end

	local ok, productInfo = pcall(function()
		return MarketplaceService:GetProductInfo(productId, Enum.InfoType.Product)
	end)
	if not ok or typeof(productInfo) ~= "table" then
		return false, tostring(productInfo)
	end

	return true, productInfo
end

local function normalizeSlotData(slotData)
	if typeof(slotData) ~= "table" then
		slotData = BrainrotQuickSlotConfig.GetDefaults()
	end

	local maxSlots = math.max(
		BrainrotQuickSlotConfig.DefaultUnlockedSlots,
		math.floor(tonumber(slotData.MaxSlots) or BrainrotQuickSlotConfig.MaxSlots)
	)
	maxSlots = math.min(maxSlots, BrainrotQuickSlotConfig.MaxSlots)

	local unlockedSlots = BrainrotQuickSlotConfig.ClampUnlockedSlots(slotData.UnlockedSlots)
	unlockedSlots = math.min(unlockedSlots, maxSlots)

	return {
		UnlockedSlots = unlockedSlots,
		MaxSlots = maxSlots,
	}
end

local function getQuantityFromProfileEntry(entry)
	if typeof(entry) ~= "table" then
		return 0
	end
	return math.max(0, math.floor(tonumber(entry.Quantity) or 0))
end

local function getQuantityFromFolder(folder)
	if typeof(folder) ~= "Instance" or not folder:IsA("Folder") then
		return 0
	end

	local quantity = folder:FindFirstChild("Quantity")
	if quantity and quantity:IsA("NumberValue") then
		return math.max(0, math.floor(tonumber(quantity.Value) or 0))
	end

	return 0
end

local function getBrainrotDisplayName(storageName)
	local info = Brainrots[storageName]
	return tostring((info and info.DisplayName) or storageName or "Brainrot")
end

local function getBaseStorageName(storageName)
	storageName = tostring(storageName or "")
	for _, variantKey in ipairs(BrainrotVariants.Order or {}) do
		if variantKey ~= "Normal" then
			local variantData = (BrainrotVariants.Versions or {})[variantKey]
			local prefix = tostring((variantData and variantData.Prefix) or (variantKey .. " "))
			if prefix ~= "" and storageName:sub(1, #prefix) == prefix then
				return storageName:sub(#prefix + 1)
			end
		end
	end
	return storageName
end

local function isBrainrotStorageName(storageName)
	storageName = tostring(storageName or "")
	return Brainrots[storageName] ~= nil or Brainrots[getBaseStorageName(storageName)] ~= nil
end

local function getBrainrotRank(storageName)
	local info = Brainrots[storageName] or Brainrots[getBaseStorageName(storageName)]
	return RARITY_ORDER[tostring(info and info.Rarity or "")] or 0
end

local function sortBrainrotEntries(entries)
	table.sort(entries, function(a, b)
		local rankA = getBrainrotRank(a.Name)
		local rankB = getBrainrotRank(b.Name)
		if rankA ~= rankB then
			return rankA > rankB
		end

		local displayA = string.lower(getBrainrotDisplayName(a.Name))
		local displayB = string.lower(getBrainrotDisplayName(b.Name))
		if displayA ~= displayB then
			return displayA < displayB
		end

		if a.Quantity ~= b.Quantity then
			return a.Quantity > b.Quantity
		end

		return tostring(a.Name) < tostring(b.Name)
	end)
end

local function collectBrainrotEntriesFromProfile(player)
	local dataManager = getDataManager()
	local inventory = dataManager:GetValue(player, "Inventory")
	if typeof(inventory) ~= "table" then
		return nil
	end

	local entries = {}
	for storageName, entry in pairs(inventory) do
		if storageName ~= "Feed" and storageName ~= "DevilFruits" and isBrainrotStorageName(storageName) then
			local quantity = getQuantityFromProfileEntry(entry)
			if quantity > 0 then
				table.insert(entries, {
					Name = tostring(storageName),
					Quantity = quantity,
				})
			end
		end
	end

	sortBrainrotEntries(entries)
	return entries
end

local function collectBrainrotEntriesFromFolders(player)
	local inventory = player:FindFirstChild("Inventory")
	if not inventory or not inventory:IsA("Folder") then
		return {}
	end

	local entries = {}
	for _, child in ipairs(inventory:GetChildren()) do
		if child:IsA("Folder") and child.Name ~= "Feed" and child.Name ~= "DevilFruits" and isBrainrotStorageName(child.Name) then
			local quantity = getQuantityFromFolder(child)
			if quantity > 0 then
				table.insert(entries, {
					Name = child.Name,
					Quantity = quantity,
				})
			end
		end
	end

	sortBrainrotEntries(entries)
	return entries
end

local function getBrainrotQuickEntries(player)
	return collectBrainrotEntriesFromProfile(player) or collectBrainrotEntriesFromFolders(player)
end

local function addOccupiedSlotName(slotNames, storageName)
	storageName = tostring(storageName or "")
	if storageName ~= "" and isBrainrotStorageName(storageName) then
		slotNames[storageName] = true
	end
end

local function addEntrySlotNames(slotNames, entries)
	for _, entry in ipairs(entries or {}) do
		if math.max(0, math.floor(tonumber(entry.Quantity) or 0)) > 0 then
			addOccupiedSlotName(slotNames, entry.Name)
		end
	end
end

local function addAvailableInstanceSlotNamesFromProfile(player, slotNames)
	local dataManager = getDataManager()
	local brainrotInventory = dataManager:GetValue(player, "BrainrotInventory")
	if typeof(brainrotInventory) ~= "table" or typeof(brainrotInventory.ById) ~= "table" then
		return
	end

	for _, instanceData in pairs(brainrotInventory.ById) do
		if typeof(instanceData) == "table"
			and tostring(instanceData.AssignedStand or "") == ""
			and isBrainrotStorageName(instanceData.StorageName) then
			addOccupiedSlotName(slotNames, instanceData.StorageName)
		end
	end
end

local function countSlotNames(slotNames)
	local count = 0
	for _ in pairs(slotNames) do
		count += 1
	end
	return count
end

local function countOccupiedSlotNames(player)
	local slotNames = {}
	addEntrySlotNames(slotNames, collectBrainrotEntriesFromProfile(player))
	addEntrySlotNames(slotNames, collectBrainrotEntriesFromFolders(player))
	addAvailableInstanceSlotNamesFromProfile(player, slotNames)
	return countSlotNames(slotNames)
end

function BrainrotQuickSlotService.EnsureSlots(player)
	local dataManager = getDataManager()
	local current = dataManager:GetValue(player, QUICK_SLOT_PATH)
	local source = current

	if typeof(source) ~= "table" then
		source = dataManager:GetValue(player, LEGACY_STORAGE_PATH)
	end

	local normalized = normalizeSlotData(source)
	if typeof(current) ~= "table" then
		dataManager:SetValue(player, QUICK_SLOT_PATH, normalized)
	else
		if current.UnlockedSlots ~= normalized.UnlockedSlots then
			dataManager:SetValue(player, QUICK_SLOT_PATH .. ".UnlockedSlots", normalized.UnlockedSlots)
		end
		if current.MaxSlots ~= normalized.MaxSlots then
			dataManager:SetValue(player, QUICK_SLOT_PATH .. ".MaxSlots", normalized.MaxSlots)
		end
	end

	return normalized
end

function BrainrotQuickSlotService.GetUnlockedSlots(player)
	return BrainrotQuickSlotService.EnsureSlots(player).UnlockedSlots
end

function BrainrotQuickSlotService.GetMaxSlots(player)
	return BrainrotQuickSlotService.EnsureSlots(player).MaxSlots
end

function BrainrotQuickSlotService.CountOccupiedSlots(player)
	return countOccupiedSlotNames(player)
end

function BrainrotQuickSlotService.CanGainBrainrots(player, amount, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, 0, 0, 0
	end

	local requested = math.max(0, math.floor(tonumber(amount) or 0))
	if requested <= 0 then
		return true, BrainrotQuickSlotService.CountOccupiedSlots(player), BrainrotQuickSlotService.GetUnlockedSlots(player), BrainrotQuickSlotService.GetMaxSlots(player)
	end

	local slots = BrainrotQuickSlotService.EnsureSlots(player)
	local occupied = BrainrotQuickSlotService.CountOccupiedSlots(player)
	local requiredSlots = 1
	local allowed = (occupied + requiredSlots) <= slots.UnlockedSlots

	print(string.format(
		"[BrainrotQuickSlots] gain %s player=%s context=%s occupied=%d unlocked=%d amount=%d requiredSlots=%d max=%d",
		allowed and "allow" or "block",
		player.Name,
		tostring(context or "unknown"),
		occupied,
		slots.UnlockedSlots,
		requested,
		requiredSlots,
		slots.MaxSlots
	))

	return allowed, occupied, slots.UnlockedSlots, slots.MaxSlots
end

function BrainrotQuickSlotService.NotifyFull(player)
	sendPopup(player, FULL_MESSAGE, ERROR_COLOR, true)
end

function BrainrotQuickSlotService.CanGainOrNotify(player, amount, context)
	local allowed, occupied, unlockedSlots, maxSlots = BrainrotQuickSlotService.CanGainBrainrots(player, amount, context)
	if not allowed then
		BrainrotQuickSlotService.NotifyFull(player)
	end
	return allowed, occupied, unlockedSlots, maxSlots
end

function BrainrotQuickSlotService.GetBrainrotSlotIndex(player, storageName)
	storageName = tostring(storageName or "")
	if storageName == "" then
		return nil
	end

	for index, entry in ipairs(getBrainrotQuickEntries(player)) do
		if tostring(entry.Name) == storageName then
			return index
		end
	end

	return nil
end

function BrainrotQuickSlotService.CanEquipBrainrot(player, storageName)
	local slotIndex = BrainrotQuickSlotService.GetBrainrotSlotIndex(player, storageName)
	if not slotIndex then
		return false, nil, BrainrotQuickSlotService.GetUnlockedSlots(player)
	end

	local slots = BrainrotQuickSlotService.EnsureSlots(player)
	return slotIndex <= slots.UnlockedSlots, slotIndex, slots.UnlockedSlots
end

function BrainrotQuickSlotService.RequestUnlock(player, requestedSlot)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if not waitForReady(player) then
		sendPopup(player, "Player data is still loading. Try again in a moment.", ERROR_COLOR, true)
		return false
	end

	local dataManager = getDataManager()
	local slots = BrainrotQuickSlotService.EnsureSlots(player)
	if slots.UnlockedSlots >= slots.MaxSlots then
		sendPopup(player, "Brainrot Quick Slots are already fully unlocked.", INFO_COLOR, false)
		return false
	end

	local nextSlot = BrainrotQuickSlotConfig.GetNextLockedSlot(slots.UnlockedSlots)
	local requested = math.floor(tonumber(requestedSlot) or nextSlot or 0)
	if requested > 0 and requested < nextSlot then
		return false
	end

	local productId = tonumber(BrainrotQuickSlotConfig.ProductId)
	if not productId or productId <= 0 then
		sendPopup(player, "Brainrot Quick Slot purchases are not configured yet.", ERROR_COLOR, true)
		return false
	end
	local canPrompt, productInfoOrReason = canPromptUnlockProduct(productId)
	if not canPrompt then
		warn(string.format(
			"[BrainrotQuickSlots] unlock prompt blocked player=%s productId=%s reason=%s",
			player.Name,
			tostring(productId),
			tostring(productInfoOrReason)
		))
		sendPopup(player, "Brainrot Quick Slot product is not valid for this experience yet.", ERROR_COLOR, true)
		return false
	end

	player:SetAttribute("PendingBrainrotQuickSlot", nextSlot)
	dataManager:PromptProductPurchase(player, productId)
	return true
end

function BrainrotQuickSlotService.PromptUnlockForBrainrot(player, storageName)
	local slotIndex = BrainrotQuickSlotService.GetBrainrotSlotIndex(player, storageName)
	local slots = BrainrotQuickSlotService.EnsureSlots(player)
	if not slotIndex or slotIndex <= slots.UnlockedSlots then
		return false
	end

	sendPopup(player, string.format("Brainrot Quick Slot %d is locked.", slotIndex), INFO_COLOR, false)
	return BrainrotQuickSlotService.RequestUnlock(player, slotIndex)
end

function BrainrotQuickSlotService.ProcessUnlockReceipt(player, productId, dataManager)
	dataManager = dataManager or getDataManager()
	if not BrainrotQuickSlotConfig.IsUnlockProduct(productId) then
		return false
	end

	local slots = BrainrotQuickSlotService.EnsureSlots(player)
	if slots.UnlockedSlots >= slots.MaxSlots then
		print(string.format(
			"[BrainrotQuickSlots] purchase processed player=%s productId=%s result=already_max unlocked=%d",
			player.Name,
			tostring(productId),
			slots.UnlockedSlots
		))
		player:SetAttribute("PendingBrainrotQuickSlot", nil)
		return true
	end

	local grantedSlots = math.min(slots.UnlockedSlots + 1, slots.MaxSlots)
	dataManager:SetValue(player, QUICK_SLOT_PATH .. ".UnlockedSlots", grantedSlots)
	dataManager:SetValue(player, QUICK_SLOT_PATH .. ".MaxSlots", slots.MaxSlots)
	player:SetAttribute("PendingBrainrotQuickSlot", nil)

	print(string.format(
		"[BrainrotQuickSlots] purchase processed player=%s productId=%s unlockedSlots=%d",
		player.Name,
		tostring(productId),
		grantedSlots
	))
	sendPopup(player, string.format("Brainrot Quick Slot %d unlocked.", grantedSlots), SUCCESS_COLOR, false)
	return true
end

function BrainrotQuickSlotService.Init()
	if initialized then
		return
	end
	initialized = true

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local requestRemote = remotes:FindFirstChild("BrainrotQuickSlotsRequest")
	if requestRemote and not requestRemote:IsA("RemoteEvent") then
		requestRemote:Destroy()
		requestRemote = nil
	end
	if not requestRemote then
		requestRemote = Instance.new("RemoteEvent")
		requestRemote.Name = "BrainrotQuickSlotsRequest"
		requestRemote.Parent = remotes
	end

	requestRemote.OnServerEvent:Connect(function(player, action, slotIndex)
		if action == "UnlockSlot" then
			BrainrotQuickSlotService.RequestUnlock(player, slotIndex)
		end
	end)

	local function onPlayerAdded(player)
		task.spawn(function()
			if waitForReady(player) then
				local slots = BrainrotQuickSlotService.EnsureSlots(player)
				print(string.format(
					"[BrainrotQuickSlots] player=%s unlockedSlots=%d maxSlots=%d",
					player.Name,
					slots.UnlockedSlots,
					slots.MaxSlots
				))
			end
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
end

return BrainrotQuickSlotService
