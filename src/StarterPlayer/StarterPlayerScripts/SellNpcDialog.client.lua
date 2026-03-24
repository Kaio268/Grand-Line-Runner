local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local Brainrots = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local player = Players.LocalPlayer
local refs = MapResolver.WaitForRefs(
	{ "MapRoot" },
	nil,
	{
		warn = true,
		context = "SellNpcDialog",
	}
)
local npc = refs.MapRoot:WaitForChild("Lobby"):WaitForChild("Normal")
local prompt = npc:WaitForChild("ProximityPrompt")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SellEvent = remotes:WaitForChild("SellItemEvent")

local SELL_TIME_SECONDS = 15

local function cleanName(raw)
	raw = tostring(raw or "")
	raw = raw:gsub("%(", ""):gsub("%)", "")
	return raw:gsub("^%s+", ""):gsub("%s+$", "")
end

local function getSellPrice(brainrotName)
	local data = Brainrots[brainrotName]
	if not data then
		return nil
	end

	if data.SellPrice then
		return tonumber(data.SellPrice)
	end

	local income = tonumber(data.Income)
	if not income then
		return nil
	end

	return income * SELL_TIME_SECONDS
end

local function moneyStr(n)
	n = tonumber(n) or 0
	if math.floor(n) == n then
		return tostring(n)
	end
	return string.format("%.2f", n)
end

local dialogObject = DialogModule.new("OpenSell", npc, prompt)
dialogObject:addDialog("YO brooo!", {
	"I want to sell my inventory!",
	"I want to sell this item!",
	"How much does this item cost?",
})

local function playNpcSellEffects()
	local primary = npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true)
	if not primary then
		return
	end

	local attachment = primary:FindFirstChild("Attachment")
	if attachment then
		local coin2 = attachment:FindFirstChild("Greyscaled Coin 2")
		local coin1 = attachment:FindFirstChild("Greyscaled Coin 1")
		if coin2 and coin2:IsA("ParticleEmitter") then
			coin2:Emit(15)
		end
		if coin1 and coin1:IsA("ParticleEmitter") then
			coin1:Emit(15)
		end
	end

	local sound = npc:FindFirstChild("Coin sfx", true)
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

prompt.Triggered:Connect(function(triggeringPlayer)
	dialogObject:triggerDialog(triggeringPlayer, 1)
end)

local function getClientInventoryFolder()
	return player:FindFirstChild("Inventory")
end

local function getTotalInventorySellValue()
	local inv = getClientInventoryFolder()
	if not inv then
		return 0
	end

	local total = 0
	for _, brainrotFolder in ipairs(inv:GetChildren()) do
		local name = brainrotFolder.Name
		local qObj = brainrotFolder:FindFirstChild("Quantity")
		local qty = qObj and tonumber(qObj.Value) or 0

		if qty > 0 then
			local price = getSellPrice(name) or 0
			total += price * qty
		end
	end

	return total
end

dialogObject.responded:Connect(function(responseNum, dialogNum)
	if dialogNum ~= 1 then
		return
	end

	if responseNum == 1 then
		local total = getTotalInventorySellValue()
		SellEvent:FireServer("ALL")
		dialogObject:hideGui(("Let me count your loot... %s%s"):format(moneyStr(total), CurrencyUtil.getCompactSuffix()))
		playNpcSellEffects()
	elseif responseNum == 2 then
		local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
		if not tool then
			dialogObject:hideGui("You don't have any item equipped.")
			return
		end

		local name = cleanName(tool.Name)
		local price = getSellPrice(name)
		if not price or price <= 0 then
			dialogObject:hideGui("You can't sell this item.")
			return
		end

		SellEvent:FireServer("SINGLE", tool.Name)
		dialogObject:hideGui(("%s sold for %s%s"):format(name, moneyStr(price), CurrencyUtil.getCompactSuffix()))
		playNpcSellEffects()
	elseif responseNum == 3 then
		local tool = player.Character and player.Character:FindFirstChildOfClass("Tool")
		if not tool then
			dialogObject:hideGui("You don't have any item equipped.")
			return
		end

		local name = cleanName(tool.Name)
		local price = getSellPrice(name)

		if price and price > 0 then
			dialogObject:hideGui(("%s can be sold for %s%s (15 sec income)"):format(name, moneyStr(price), CurrencyUtil.getCompactSuffix()))
		else
			dialogObject:hideGui("This item cannot be sold.")
		end
	end
end)
