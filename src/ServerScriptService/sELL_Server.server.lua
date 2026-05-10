local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local DataManager = require(script.Parent.Data.DataManager)
local CrewMemberCanonicalReadGate = require(script.Parent.Modules.CrewMemberCanonicalReadGate)
local CrewInstanceService = require(script.Parent.Modules.CrewInstanceService)
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

local function getSellPrice(brainrotName)
	local data = Brainrots[brainrotName]
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

	local displayName = CrewMemberCanonicalReadGate.ResolveSellDialogDisplayName(player, sanitizeKey(displayKey), {
		LogThrottleSeconds = 60,
	})
	return tostring(displayName or wantName)
end

local function sellSingle(player, rawName)
	local wantName   = sanitizeKey(rawName)
	local inventory  = DataManager:GetValue(player, "Inventory")
	if type(inventory) ~= "table" then return end

	local realKey = locateInventoryKey(inventory, wantName)
	if not realKey then return end

	local qty = getQuantity(inventory[realKey])
	if qty <= 0 then return end

	local brainrotName = sanitizeKey(realKey)
	CrewMemberCanonicalReadGate.CompareSellDialogDisplay(player, brainrotName, {
		LogThrottleSeconds = 60,
	})
	local price        = getSellPrice(brainrotName)
	if price <= 0 then return end

	local removedInstanceId = CrewInstanceService.RemoveAvailableCrewMember(player, realKey)
	if not removedInstanceId then
		return
	end

	DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), price)
end

local function sellAll(player)
	local inventory = DataManager:GetValue(player, "Inventory")
	if type(inventory) ~= "table" then return end

	local total = 0

	for key, entry in pairs(inventory) do
		local qty = getQuantity(entry)
		if qty > 0 then
			local brainrotName = sanitizeKey(key)
			CrewMemberCanonicalReadGate.CompareSellDialogDisplay(player, brainrotName, {
				LogThrottleSeconds = 60,
			})
			local price        = getSellPrice(brainrotName)

			if price > 0 then
				local soldCount = 0
				for _ = 1, qty do
					if CrewInstanceService.RemoveAvailableCrewMember(player, key) then
						soldCount += 1
					end
				end
				total += price * soldCount
			end
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
	if player.Parent ~= Players then return end

	if mode == "SINGLE" and fullName then
		sellSingle(player, fullName)
	elseif mode == "ALL" then
		sellAll(player)
	end
end)
