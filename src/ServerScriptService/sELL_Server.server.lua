local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local DataManager = require(script.Parent.Data.DataManager)
local SellEvent   = ReplicatedStorage.Remotes:WaitForChild("SellItemEvent")

local Brainrots = require(ReplicatedStorage.Modules.Configs:WaitForChild("Brainrots"))

local SELL_TIME_SECONDS = 15

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

local function sellSingle(player, rawName)
	local wantName   = sanitizeKey(rawName)
	local inventory  = DataManager:GetValue(player, "Inventory")
	if type(inventory) ~= "table" then return end

	local realKey = locateInventoryKey(inventory, wantName)
	if not realKey then return end

	local qty = getQuantity(inventory[realKey])
	if qty <= 0 then return end

	local brainrotName = sanitizeKey(realKey)
	local price        = getSellPrice(brainrotName)
	if price <= 0 then return end

	DataManager:SubValue(player, ("Inventory.%s.Quantity"):format(realKey), 1)
	DataManager:AddValue(player, "leaderstats.Money", price)
end

local function sellAll(player)
	local inventory = DataManager:GetValue(player, "Inventory")
	if type(inventory) ~= "table" then return end

	local total = 0

	for key, entry in pairs(inventory) do
		local qty = getQuantity(entry)
		if qty > 0 then
			local brainrotName = sanitizeKey(key)
			local price        = getSellPrice(brainrotName)

			if price > 0 then
				total += price * qty
				DataManager:SetValue(player, ("Inventory.%s.Quantity"):format(key), 0)
			end
		end
	end

	if total > 0 then
		DataManager:AddValue(player, "leaderstats.Money", total)
	end
end

SellEvent.OnServerEvent:Connect(function(player, mode, fullName)
	if player.Parent ~= Players then return end

	if mode == "SINGLE" and fullName then
		sellSingle(player, fullName)
	elseif mode == "ALL" then
		sellAll(player)
	end
end)
