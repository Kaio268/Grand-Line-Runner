local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Modules.Types)
local BrainrotInstanceService = require(script.Parent.Parent.Parent.Modules.BrainrotInstanceService)
local BrainrotQuickSlotService = require(script.Parent.Parent.Parent.Modules.BrainrotQuickSlotService)
local GearConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
local BrainrotQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("BrainrotQuickSlots"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local PlotSystem = nil
local PlotsFolder = nil
local addbrairntos = nil

local STEAL_PRODUCTS = {
	[3512126073] = true,
	[3512126373] = true,
	[3512127278] = true,
	[3512127790] = true,
	[3512128038] = true,
	[3512128716] = true,
}

local function getAddBrainrot()
	addbrairntos = addbrairntos or require(script.Parent.Parent.Parent.Modules.AddBrainrot)
	return addbrairntos
end

local function getPlotsFolder()
	if PlotsFolder and PlotsFolder.Parent then
		return PlotsFolder
	end

	PlotSystem = PlotSystem or workspace:FindFirstChild("PlotSystem") or workspace:WaitForChild("PlotSystem", 10)
	if not PlotSystem then
		return nil
	end

	PlotsFolder = PlotSystem:FindFirstChild("Plots") or PlotSystem:WaitForChild("Plots", 10)
	return PlotsFolder
end

local function findPlotForUserId(userId)
	local plotsFolder = getPlotsFolder()
	if not plotsFolder then
		return nil
	end

	for _, m in ipairs(plotsFolder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("OwnerUserId") == userId then
			return m
		end
	end
	return nil
end

local function findStandModel(plot, standName)
	local standsFolder = plot:FindFirstChild("Stands", true)
	if not standsFolder then
		return nil
	end
	for _, inst in ipairs(standsFolder:GetDescendants()) do
		if inst:IsA("Model") and inst.Name == standName then
			return inst
		end
	end
	return nil
end

local function ensureInventorySlot(player, brainrotName, DataManager: Types.DataManager)
	local qPath = "Inventory." .. brainrotName .. ".Quantity"

	local qVal = DataManager:GetValue(player, qPath)

	if qVal == nil then
		DataManager:AddValue(player, "Inventory", {
			[brainrotName] = {
				Quantity = 0,
			},
		})
	end
end

local function StealBrainrotProduct(receiptInfo, buyer, profile, DataManager: Types.DataManager)
	local productId = tonumber(receiptInfo.ProductId)
	if not productId or not STEAL_PRODUCTS[productId] then
		return
	end

	local ownerUserId = buyer:GetAttribute("StealOwnerUserId")
	local standName = buyer:GetAttribute("StealStandName")
	local brainrotName = buyer:GetAttribute("StealBrainrotName")
	local brainrotInstanceId = buyer:GetAttribute("StealBrainrotInstanceId")
	local expectedId = buyer:GetAttribute("StealProductId")
	local ts = buyer:GetAttribute("StealTime")

	buyer:SetAttribute("StealOwnerUserId", nil)
	buyer:SetAttribute("StealStandName", nil)
	buyer:SetAttribute("StealBrainrotName", nil)
	buyer:SetAttribute("StealBrainrotInstanceId", nil)
	buyer:SetAttribute("StealProductId", nil)
	buyer:SetAttribute("StealTime", nil)

	if typeof(expectedId) ~= "number" or expectedId ~= productId then
		return
	end
	if typeof(ownerUserId) ~= "number" then
		return
	end
	if typeof(standName) ~= "string" or standName == "" then
		return
	end
	if typeof(brainrotName) ~= "string" or brainrotName == "" then
		return
	end
	if typeof(ts) == "number" and (os.time() - ts) > 120 then
		return
	end

	local owner = Players:GetPlayerByUserId(ownerUserId)
	if not owner or owner == buyer then
		return
	end

	local current = DataManager:GetValue(owner, "IncomeBrainrots." .. standName .. ".BrainrotName")
	if current ~= brainrotName then
		return
	end
	if typeof(brainrotInstanceId) == "string" and brainrotInstanceId ~= "" then
		local currentInstanceId = BrainrotInstanceService.GetStandInstanceId(owner, standName)
		if currentInstanceId ~= "" and currentInstanceId ~= brainrotInstanceId then
			return
		end
	end

	local transferredInstanceId = BrainrotInstanceService.TransferStandInstance(owner, buyer, standName)
	if not transferredInstanceId then
		return
	end
	DataManager:SetValue(owner, "IncomeBrainrots." .. standName .. ".IncomeToCollect", 0)

	local plot = findPlotForUserId(ownerUserId)
	if plot then
		local standModel = findStandModel(plot, standName)
		if standModel then
			local placed = standModel:FindFirstChild("PlacedBrainrot")
			if placed and placed:IsA("Model") then
				placed:Destroy()
			end
			local handle = standModel:FindFirstChild("Handle", true)
			if handle and handle:IsA("BasePart") then
				local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
				if prompt then
					prompt.ObjectText = tostring(standName)
					prompt.ActionText = "Place Here"
				end
			end
		end
	end

	ensureInventorySlot(buyer, brainrotName, DataManager)
end

local handlers = {
	[3509346360] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		getAddBrainrot():AddBrainrot(player, "67", 1)
		getAddBrainrot():AddBrainrot(player, "Dragon Cannelloni", 1)
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 1_000_000_000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 1_000_000_000)
		DataManager:SetValue(player, "Packs.Super OP Starter Pack", true)
	end,

	[3512059347] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		getAddBrainrot():AddBrainrot(player, "La Vacca Saturno Saturnita", 1)
	end,

	[3509346182] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		getAddBrainrot():AddBrainrot(player, "Tralalero Tralala", 1)
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 1_000_000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 1_000_000)
		if DataManager:GetValue(player, "Gears.Lava SpeedCoil") then
			DataManager:SetValue(player, "Gears.Lava SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Lava SpeedCoil"] = true })
		end
		DataManager:SetValue(player, "Packs.Best Starter Pack", true)
	end,

	[3509346000] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		getAddBrainrot():AddBrainrot(player, "Elefanto Cocofanto", 1)
		DataManager:SetValue(player, "Packs.Better Starter Pack", true)

		if DataManager:GetValue(player, "Gears.Diamond SpeedCoil") then
			DataManager:SetValue(player, "Gears.Diamond SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Diamond SpeedCoil"] = true })
		end

		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 100_000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 100_000)
	end,

	[3509345784] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		getAddBrainrot():AddBrainrot(player, "Odin Din Din Dun", 1)
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 1000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 1000)
		DataManager:SetValue(player, "Packs.Starter Pack", true)

		if DataManager:GetValue(player, "Gears.SpeedCoil") then
			DataManager:SetValue(player, "Gears.SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["SpeedCoil"] = true })
		end
	end,

	[3515419300] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x15WalkSpeed", 30*60, 3)
	end,

	[3515418772] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x15WalkSpeed", 30*60, 1)
	end,

	[3515418047] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x2Money", 30*60, 3)
	end,

	[3515417573] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x2Money", 30*60, 1)
	end,

	[3515409012] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 2
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3515409311] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 4
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3515410147] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 8
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3515410559] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 16
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3509345591] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		game.Workspace.NoDisastersTimer.Value += 30
	end,

	[3516522193] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		DataManager:AddValue(player, "HiddenLeaderstats.Speed", 1)
		DataManager:AddValue(player, "TotalStats.TotalSpeed", 1)
	end,

	[3516522992] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		DataManager:AddValue(player, "HiddenLeaderstats.Speed", 5)
		DataManager:AddValue(player, "TotalStats.TotalSpeed", 5)
	end,

	[3516522609] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		DataManager:AddValue(player, "HiddenLeaderstats.Speed", 10)
		DataManager:AddValue(player, "TotalStats.TotalSpeed", 10)
	end,

	[3516539588] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.SpeedCoil") then
			DataManager:SetValue(player, "Gears.SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["SpeedCoil"] = true })
		end
	end,

	[3516540101] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Golden Slap") then
			DataManager:SetValue(player, "Gears.Golden Slap", true)
		else
			DataManager:AddValue(player, "Gears", { ["Golden Slap"] = true })
		end
	end,

	[3516540402] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Golden SpeedCoil") then
			DataManager:SetValue(player, "Gears.Golden SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Golden SpeedCoil"] = true })
		end
	end,

	[3516540726] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Diamond SpeedCoil") then
			DataManager:SetValue(player, "Gears.Diamond SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Diamond SpeedCoil"] = true })
		end
	end,

	[3516541650] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Galaxy Slap") then
			DataManager:SetValue(player, "Gears.Galaxy Slap", true)
		else
			DataManager:AddValue(player, "Gears", { ["Galaxy Slap"] = true })
		end
	end,

	[3516542043] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Galaxy SpeedCoil") then
			DataManager:SetValue(player, "Gears.Galaxy SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Galaxy SpeedCoil"] = true })
		end
	end,

	[3516542817] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Lava Slap") then
			DataManager:SetValue(player, "Gears.Lava Slap", true)
		else
			DataManager:AddValue(player, "Gears", { ["Lava Slap"] = true })
		end
	end,

	[3516543186] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Lava SpeedCoil") then
			DataManager:SetValue(player, "Gears.Lava SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Lava SpeedCoil"] = true })
		end
	end,

	[3512126073] = StealBrainrotProduct,
	[3512126373] = StealBrainrotProduct,
	[3512127278] = StealBrainrotProduct,
	[3512127790] = StealBrainrotProduct,
	[3512128038] = StealBrainrotProduct,
	[3512128716] = StealBrainrotProduct,
}

local brainrotQuickSlotProductId = tonumber(BrainrotQuickSlotConfig.ProductId)
if brainrotQuickSlotProductId and brainrotQuickSlotProductId > 0 then
	handlers[brainrotQuickSlotProductId] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
		BrainrotQuickSlotService.ProcessUnlockReceipt(player, receiptInfo.ProductId, DataManager)
	end
end

local productToGears = {}

for gearName, data in pairs(GearConfig) do
	local id = tonumber(data.ProductID)
	if id then
		productToGears[id] = productToGears[id] or {}
		table.insert(productToGears[id], gearName)
	end
end

local function grantGears(productId, receiptInfo, player, profile, DataManager: Types.DataManager)
	local list = productToGears[productId]
	if not list then
		return
	end

	for _, gearName in ipairs(list) do
		local owned = DataManager:GetValue(player, "Gears." .. gearName)
		if owned == nil then
			DataManager:AddValue(player, "Gears", { [tostring(gearName)] = false })
		end
	end
end

for productId in pairs(productToGears) do
	if handlers[productId] then
		local old = handlers[productId]
		handlers[productId] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
			old(receiptInfo, player, profile, DataManager)
			grantGears(productId, receiptInfo, player, profile, DataManager)
		end
	else
		handlers[productId] = function(receiptInfo, player, profile, DataManager: Types.DataManager)
			grantGears(productId, receiptInfo, player, profile, DataManager)
		end
	end
end

return handlers
