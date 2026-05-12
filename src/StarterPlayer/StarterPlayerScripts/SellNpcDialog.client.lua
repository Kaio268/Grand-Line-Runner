local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local DialogModule = require(ReplicatedStorage:WaitForChild("DialogModule"))
local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local LegacyCrewConfig = CrewCatalog.GetLegacyConfig()
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local player = Players.LocalPlayer
local refs = MapResolver.WaitForRefs(
	{ "SellNpc" },
	nil,
	{
		warn = true,
		context = "SellNpcDialog",
	}
)
local npc = refs.SellNpc
local prompt = npc:WaitForChild("ProximityPrompt")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local SellEvent = remotes:WaitForChild("SellItemEvent")
local SellDialogDisplayNameRequest = remotes:FindFirstChild("CrewMemberSellDialogDisplayNameRequest")
if SellDialogDisplayNameRequest and not SellDialogDisplayNameRequest:IsA("RemoteFunction") then
	SellDialogDisplayNameRequest = nil
end

local SELL_TIME_SECONDS = 15

local function getCrewInfo(name)
	return CrewCatalog.GetInfoById(name) or LegacyCrewConfig[name]
end

local function getCrewDisplayName(name)
	local info = getCrewInfo(name)
	if not info then
		return name
	end

	return tostring(info.DisplayName or info.Name or name)
end

local function getSellDialogDisplayName(name)
	local fallbackName = getCrewDisplayName(name)
	if not SellDialogDisplayNameRequest then
		local remote = remotes:FindFirstChild("CrewMemberSellDialogDisplayNameRequest")
		if remote and remote:IsA("RemoteFunction") then
			SellDialogDisplayNameRequest = remote
		end
	end
	if not SellDialogDisplayNameRequest then
		return fallbackName
	end

	local ok, result = pcall(function()
		return SellDialogDisplayNameRequest:InvokeServer(name)
	end)
	if ok and type(result) == "string" and result ~= "" then
		return result
	end
	return fallbackName
end

local function cleanName(raw)
	raw = tostring(raw or "")
	raw = raw:gsub("%(", ""):gsub("%)", "")
	return raw:gsub("^%s+", ""):gsub("%s+$", "")
end

local function getSellPrice(brainrotName)
	local data = getCrewInfo(brainrotName)
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

local function readValueObject(parent, childName)
	local valueObject = parent and parent:FindFirstChild(childName)
	if valueObject
		and (
			valueObject:IsA("StringValue")
			or valueObject:IsA("NumberValue")
			or valueObject:IsA("IntValue")
			or valueObject:IsA("BoolValue")
		)
	then
		return valueObject.Value
	end
	return nil
end

local function getCrewStorageName(instanceFolder)
	if not instanceFolder or not instanceFolder:IsA("Folder") then
		return ""
	end

	return cleanName(
		readValueObject(instanceFolder, "StorageName")
			or readValueObject(instanceFolder, "LegacyStorageName")
			or readValueObject(instanceFolder, "CrewMemberId")
			or readValueObject(instanceFolder, "BaseName")
			or ""
	)
end

local function getCanonicalInventorySellCounts()
	local crewInventory = player:FindFirstChild("CrewMemberInventory")
	local byId = crewInventory and crewInventory:FindFirstChild("ById")
	if not byId or not byId:IsA("Folder") then
		return {}
	end

	local counts = {}
	for _, instanceFolder in ipairs(byId:GetChildren()) do
		if instanceFolder:IsA("Folder") then
			local storageName = getCrewStorageName(instanceFolder)
			local assignedStand = tostring(readValueObject(instanceFolder, "AssignedStand") or "")
			if storageName ~= "" and assignedStand == "" then
				counts[storageName] = (counts[storageName] or 0) + 1
			end
		end
	end

	return counts
end

local function getTotalInventorySellValue()
	local canonicalCounts = getCanonicalInventorySellCounts()
	local inv = getClientInventoryFolder()

	local total = 0
	local countedCanonicalNames = {}

	for name, qty in pairs(canonicalCounts) do
		local price = getSellPrice(name) or 0
		total += price * qty
		countedCanonicalNames[cleanName(name)] = true
	end

	if not inv then
		return total
	end

	for _, brainrotFolder in ipairs(inv:GetChildren()) do
		local name = brainrotFolder.Name
		if not countedCanonicalNames[cleanName(name)] then
			local qObj = brainrotFolder:FindFirstChild("Quantity")
			local qty = qObj and tonumber(qObj.Value) or 0
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
		dialogObject:hideGui(("%s sold for %s%s"):format(getSellDialogDisplayName(name), moneyStr(price), CurrencyUtil.getCompactSuffix()))
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
			dialogObject:hideGui(("%s can be sold for %s%s (15 sec income)"):format(getSellDialogDisplayName(name), moneyStr(price), CurrencyUtil.getCompactSuffix()))
		else
			dialogObject:hideGui("This item cannot be sold.")
		end
	end
end)
