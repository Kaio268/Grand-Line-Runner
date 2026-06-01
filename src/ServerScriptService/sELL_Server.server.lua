local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(script.Parent.Data.DataManager)
local CrewMemberCanonicalReadGate = require(script.Parent.Modules.CrewMemberCanonicalReadGate)
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SellEvent = Remotes:WaitForChild("SellItemEvent")

local CrewCatalog = require(ReplicatedStorage.Modules.Crew:WaitForChild("CrewCatalog"))

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
	return CrewCatalog.GetInfoById(crewName)
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
	local displayInfo = CrewCatalog.GetDisplayInfo(displayKey, {
		DisplayName = displayName,
	})
	return tostring(displayInfo.DisplayName or displayName or wantName)
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

	warn(string.format(
		"[SellItemEvent] rejected legacy crew sell request player=%s mode=%s item=%s; use CrewMemberActionRequest exact InstanceId",
		player.Name,
		tostring(mode),
		tostring(fullName or "")
	))
end)
