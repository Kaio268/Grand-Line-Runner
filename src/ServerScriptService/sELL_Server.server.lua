local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(script.Parent.Data.DataManager)
local CrewMemberCanonicalReadGate = require(script.Parent.Modules.CrewMemberCanonicalReadGate)
local CrewInstanceService = require(script.Parent.Modules.CrewInstanceService)
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SellEvent = Remotes:WaitForChild("SellItemEvent")

local CrewCatalog = require(ReplicatedStorage.Modules.Crew:WaitForChild("CrewCatalog"))
local Brainrots = CrewCatalog.GetLegacyConfig()
local CurrencyUtil = require(ReplicatedStorage.Modules:WaitForChild("CurrencyUtil"))

local SELL_TIME_SECONDS = 15
local SELL_DIALOG_DISPLAY_NAME_REQUEST = "CrewMemberSellDialogDisplayNameRequest"

local displayNameRequest = Remotes:FindFirstChild(SELL_DIALOG_DISPLAY_NAME_REQUEST)
if displayNameRequest and not displayNameRequest:IsA("RemoteFunction") then
	displayNameRequest:Destroy()
	displayNameRequest = nil
end
if not displayNameRequest then
	displayNameRequest = Instance.new("RemoteFunction")
	displayNameRequest.Name = SELL_DIALOG_DISPLAY_NAME_REQUEST
	displayNameRequest.Parent = Remotes
end

local function sanitizeKey(str)
	str = tostring(str or "")
	str = str:gsub("%s*%(", ""):gsub("%)", "")
	return str:gsub("^%s+", ""):gsub("%s+$", "")
end

local function getCrewInfo(crewName)
	return CrewCatalog.GetInfoById(crewName) or Brainrots[crewName]
end

local function getSellPrice(brainrotName)
	local data = getCrewInfo(brainrotName)
	if not data then return 0 end

	if data.SellPrice then
		return tonumber(data.SellPrice) or 0
	end

	local income = tonumber(data.Income)
	if not income then return 0 end

	return income * SELL_TIME_SECONDS
end

local function locateInventoryKey(inventoryTbl, wantName)
	if inventoryTbl[wantName] ~= nil then
		return wantName
	end

	local wantSan = sanitizeKey(wantName)
	for k, _ in pairs(inventoryTbl) do
		if sanitizeKey(k) == wantSan then
			return k
		end
	end

	return nil
end

local function getQuantity(entry)
	if type(entry) == "table" then
		return tonumber(entry.Quantity) or 0
	end
	return tonumber(entry) or 0
end

local function getCanonicalCrewInventory(player)
	local inventory = DataManager:GetValue(player, "CrewMemberInventory")
	if type(inventory) ~= "table" or type(inventory.ById) ~= "table" then
		return nil
	end
	return inventory
end

local function getStorageNameFromInstance(instanceData)
	if type(instanceData) ~= "table" then
		return ""
	end

	local storageName = tostring(
		instanceData.StorageName
			or instanceData.LegacyStorageName
			or instanceData.CrewMemberId
			or instanceData.BaseName
			or ""
	)
	return sanitizeKey(storageName)
end

local function isAvailableCrewInstance(instanceData)
	return type(instanceData) == "table"
		and getStorageNameFromInstance(instanceData) ~= ""
		and tostring(instanceData.AssignedStand or "") == ""
end

local function addCrewNameMatchCandidates(candidates, crewName)
	local info = getCrewInfo(crewName)
	if type(info) ~= "table" then
		return
	end

	for _, field in ipairs({
		"Id",
		"LegacyId",
		"CrewMemberId",
		"CrewMemberName",
		"DisplayName",
		"Name",
		"RealCharacterName",
		"ModelName",
		"BaseId",
	}) do
		local value = info[field]
		if value ~= nil then
			candidates[sanitizeKey(value)] = true
		end
	end
end

local function buildCrewNameMatchCandidates(crewName)
	local normalizedName = sanitizeKey(crewName)
	local candidates = {}
	if normalizedName ~= "" then
		candidates[normalizedName] = true
	end
	addCrewNameMatchCandidates(candidates, crewName)
	return candidates
end

local function crewNamesMatch(leftName, rightName)
	local left = sanitizeKey(leftName)
	local right = sanitizeKey(rightName)
	if left == "" or right == "" then
		return false
	end
	if left == right then
		return true
	end

	local leftCandidates = buildCrewNameMatchCandidates(leftName)
	local rightCandidates = buildCrewNameMatchCandidates(rightName)
	for candidate in pairs(leftCandidates) do
		if rightCandidates[candidate] == true then
			return true
		end
	end

	return false
end

local function getCanonicalAvailableCounts(player)
	local counts = {}
	local inventory = getCanonicalCrewInventory(player)
	if not inventory then
		return counts
	end

	for _, instanceData in pairs(inventory.ById) do
		if isAvailableCrewInstance(instanceData) then
			local storageName = getStorageNameFromInstance(instanceData)
			counts[storageName] = (counts[storageName] or 0) + 1
		end
	end

	return counts
end

local function locateCanonicalStorageName(player, wantName)
	local counts = getCanonicalAvailableCounts(player)
	for storageName, quantity in pairs(counts) do
		if quantity > 0 and crewNamesMatch(storageName, wantName) then
			return storageName, quantity
		end
	end
	return nil, 0
end

local function sellCrewStorage(player, storageName, quantity)
	storageName = sanitizeKey(storageName)
	quantity = math.max(0, math.floor(tonumber(quantity) or 0))
	if storageName == "" or quantity <= 0 then
		return 0, 0
	end

	CrewMemberCanonicalReadGate.CompareSellDialogDisplay(player, storageName, {
		LogThrottleSeconds = 60,
	})

	local price = getSellPrice(storageName)
	if price <= 0 then
		return 0, 0
	end

	local soldCount = 0
	for _ = 1, quantity do
		if CrewInstanceService.RemoveAvailableCrewMember(player, storageName) then
			soldCount += 1
		else
			break
		end
	end

	return price * soldCount, soldCount
end

local function wasCanonicalStorageSold(soldCanonicalStorageNames, storageName)
	for _, soldStorageName in ipairs(soldCanonicalStorageNames) do
		if crewNamesMatch(soldStorageName, storageName) then
			return true
		end
	end
	return false
end

local function resolveSellDialogDisplayName(player, rawName)
	local wantName = sanitizeKey(rawName)
	if wantName == "" then
		return ""
	end

	local inventory = DataManager:GetValue(player, "Inventory")
	local displayKey = wantName
	if type(inventory) == "table" then
		displayKey = locateInventoryKey(inventory, wantName) or wantName
	end
	if displayKey == wantName then
		displayKey = locateCanonicalStorageName(player, wantName) or wantName
	end

	local displayName = CrewMemberCanonicalReadGate.ResolveSellDialogDisplayName(player, sanitizeKey(displayKey), {
		LogThrottleSeconds = 60,
	})
	return tostring(displayName or wantName)
end

local function sellSingle(player, rawName)
	local wantName   = sanitizeKey(rawName)
	local inventory  = DataManager:GetValue(player, "Inventory")
	if wantName == "" then
		return
	end

	local storageName = nil
	local qty = 0

	storageName, qty = locateCanonicalStorageName(player, wantName)

	if type(inventory) == "table" then
		local realKey = locateInventoryKey(inventory, wantName)
		if not storageName and realKey then
			local legacyQty = getQuantity(inventory[realKey])
			if legacyQty > 0 then
				storageName = sanitizeKey(realKey)
				qty = legacyQty
			end
		end
	end

	if not storageName or qty <= 0 then
		return
	end

	local total, soldCount = sellCrewStorage(player, storageName, 1)
	if soldCount > 0 and total > 0 then
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), total)
	end
end

local function sellAll(player)
	local inventory = DataManager:GetValue(player, "Inventory")
	local total = 0
	local soldCanonicalStorageNames = {}

	for storageName, qty in pairs(getCanonicalAvailableCounts(player)) do
		local soldTotal, soldCount = sellCrewStorage(player, storageName, qty)
		if soldCount > 0 then
			total += soldTotal
			table.insert(soldCanonicalStorageNames, storageName)
		end
	end

	if type(inventory) ~= "table" then
		if total > 0 then
			DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), total)
		end
		return
	end

	for key, entry in pairs(inventory) do
		local qty = getQuantity(entry)
		if qty > 0 and not wasCanonicalStorageSold(soldCanonicalStorageNames, key) then
			local soldTotal = sellCrewStorage(player, key, qty)
			total += soldTotal
		end
	end

	if total > 0 then
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), total)
	end
end

displayNameRequest.OnServerInvoke = function(player, rawName)
	if player.Parent ~= Players then
		return sanitizeKey(rawName)
	end

	return resolveSellDialogDisplayName(player, rawName)
end

SellEvent.OnServerEvent:Connect(function(player, mode, fullName)
	-- Security: selling mutates currency/inventory, so reject malformed or spammed sell requests first.
	if not RemoteGuard.Check(player, "SellItemEvent", { mode, fullName }, {
		Cooldown = 0.2,
		Args = {
			{ Type = "string", MaxLength = 16, Allowlist = { SINGLE = true, ALL = true } },
			{ Type = "string", MaxLength = 128, AllowNil = true },
		},
	}) then
		return
	end

	if player.Parent ~= Players then return end

	if mode == "SINGLE" and fullName then
		sellSingle(player, fullName)
	elseif mode == "ALL" then
		sellAll(player)
	end
end)
