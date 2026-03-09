local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataManager = require(game.ServerScriptService.Data:WaitForChild("DataManager"))
local Config = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CometMerchant"))

local PurchaseEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CometMerchantPurchase")

local CometMerchantService = {}
CometMerchantService.RewardHandlers = {}

function CometMerchantService:SetRewardHandler(key: string, fn)
	if typeof(key) ~= "string" then return end
	if typeof(fn) ~= "function" then return end
	self.RewardHandlers[key] = fn
end

local function lastSegment(path)
	return (tostring(path):match("([^.]+)$"))
end

local function isPath(fullKey: string)
	return tostring(fullKey):find("%.") ~= nil
end

local ItemByName = {}
local AllItemNames = {}

for fullKey, _ in pairs(Config.All_Things or {}) do
	local name = lastSegment(fullKey)
	if name then
		ItemByName[name] = fullKey
		table.insert(AllItemNames, name)
	end
end

local function stockPath(name)
	return "CometMerchant." .. name
end

local function setNumberExact(player: Player, path: string, value: number)
	local cur = DataManager:GetValue(player, path)
	if typeof(cur) ~= "number" then
		DataManager:AdjustValue(player, path, value)
		return value
	end
	local delta = value - cur
	if delta ~= 0 then
		return DataManager:AdjustValue(player, path, delta)
	end
	return cur
end

local function ensureStocksExist(player: Player)
	for _, name in ipairs(AllItemNames) do
		setNumberExact(player, stockPath(name), 0)
	end
	if DataManager.UpdateData then
		pcall(function()
			DataManager:UpdateData(player)
		end)
	end
end

local function getCfgByName(name)
	local fullKey = ItemByName[name]
	if not fullKey then return end
	local info = Config.All_Things[fullKey]
	if not info then return end
	return fullKey, info
end

local function weightedPick(available)
	local total = 0
	for _, name in ipairs(available) do
		local _, info = getCfgByName(name)
		total += math.max(0, tonumber(info and info.Chance) or 0)
	end

	if total <= 0 then
		return available[math.random(1, #available)]
	end

	local r = math.random() * total
	local acc = 0

	for _, name in ipairs(available) do
		local _, info = getCfgByName(name)
		local w = math.max(0, tonumber(info and info.Chance) or 0)
		acc += w
		if r <= acc then
			return name
		end
	end

	return available[#available]
end

local function clearAll(player)
	for _, name in ipairs(AllItemNames) do
		setNumberExact(player, stockPath(name), 0)
		DataManager:AddAttribute(player, "CometMerchant." .. name, {
			IsOffer = false,
			OfferIndex = 0,
			FullPath = "",
			Amount = 0,
			Price = 0,
			Icon = "",
			Display_name = "",
			Desc = ""
		})
	end

	if DataManager.UpdateData then
		pcall(function()
			DataManager:UpdateData(player)
		end)
	end
end

function CometMerchantService:ResetStock(targetPlayer)
	local function restockPlayer(player)
		ensureStocksExist(player)
		clearAll(player)

		local available = {}
		for _, name in ipairs(AllItemNames) do
			table.insert(available, name)
		end

		local picked = {}
		local tries = 0

		while #picked < 3 and #available > 0 and tries < 60 do
			tries += 1
			local choice = weightedPick(available)
			local idx = table.find(available, choice)
			if idx then
				table.remove(available, idx)
				table.insert(picked, choice)
			end
		end

		for i, name in ipairs(picked) do
			local fullKey, info = getCfgByName(name)
			if fullKey and info then
				local stock = tonumber(info.Stock) or 0
				local price = tonumber(info.Price) or 0
				local amount = tonumber(info.Amount) or 0
				local icon = tostring(info.Icon or "")
				local display_name = tostring(info.Display_name or "")
				local desc = tostring(info.Desc or "")

				setNumberExact(player, stockPath(name), stock)
				DataManager:AddAttribute(player, "CometMerchant." .. name, {
					IsOffer = true,
					OfferIndex = i,
					FullPath = fullKey,
					Amount = amount,
					Price = price,
					Icon = icon,
					Display_name = display_name,
					Desc = desc
				})
			end
		end

		if DataManager.UpdateData then
			pcall(function()
				DataManager:UpdateData(player)
			end)
		end
	end

	if targetPlayer then
		restockPlayer(targetPlayer)
	else
		for _, p in ipairs(Players:GetPlayers()) do
			restockPlayer(p)
		end
	end
end

local function spendComets(player, price)
	local cur = DataManager:GetValue(player, "HiddenLeaderstats.Comets")
	if typeof(cur) ~= "number" then return false end
	if cur < price then return false end
	DataManager:AdjustValue(player, "HiddenLeaderstats.Comets", -price)
	return true
end

local function refundComets(player, price)
	if typeof(price) ~= "number" or price <= 0 then return end
	DataManager:AdjustValue(player, "HiddenLeaderstats.Comets", price)
end

local function runReward(player, fullKey, amount)
	local info = Config.All_Things[fullKey]

	if isPath(fullKey) then
		local ok = pcall(function()
			DataManager:AdjustValue(player, fullKey, amount)
		end)
		return ok
	end

	local handler = CometMerchantService.RewardHandlers[fullKey]
	if not handler then
		return false
	end

	local ok = pcall(function()
		handler(player, amount, DataManager, info)
	end)

	return ok
end

PurchaseEvent.OnServerEvent:Connect(function(player, fullKeyIncoming)
	local incoming = tostring(fullKeyIncoming or "")
	if incoming == "" then return end

	local name = lastSegment(incoming) or incoming

	local stock = DataManager:GetValue(player, stockPath(name))
	if typeof(stock) ~= "number" or stock <= 0 then
		return
	end

	local stockInst = player:FindFirstChild("CometMerchant") and player.CometMerchant:FindFirstChild(name)

	local fullKey = stockInst and stockInst:GetAttribute("FullPath")
	local amount = stockInst and stockInst:GetAttribute("Amount")
	local price = stockInst and stockInst:GetAttribute("Price")

	if typeof(fullKey) ~= "string" or fullKey == "" or typeof(amount) ~= "number" or typeof(price) ~= "number" then
		local cfgFull, cfg = getCfgByName(name)
		if not cfgFull or not cfg then return end
		fullKey = cfgFull
		amount = tonumber(cfg.Amount) or 0
		price = tonumber(cfg.Price) or 0
	end

	if not isPath(fullKey) then
		if CometMerchantService.RewardHandlers[fullKey] == nil then
			return
		end
	end

	if not spendComets(player, price) then
		return
	end

	local okReward = runReward(player, fullKey, amount)
	if not okReward then
		refundComets(player, price)
		return
	end

	DataManager:AdjustValue(player, stockPath(name), -1)
end)

local function onPlayerAdded(player)
	task.defer(function()
		for i = 1, 5 do
			ensureStocksExist(player)
			task.wait(0.15)
			local folder = player:FindFirstChild("CometMerchant")
			if folder then break end
		end
		CometMerchantService:ResetStock(player)
	end)
end

for _, p in ipairs(Players:GetPlayers()) do
	onPlayerAdded(p)
end

Players.PlayerAdded:Connect(onPlayerAdded)

return CometMerchantService
