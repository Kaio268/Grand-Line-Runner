local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Types = require(ReplicatedStorage.Modules.Types)
local CrewInstanceService = require(script.Parent.Parent.Parent.Modules.CrewInstanceService)
local CrewQuickSlotService = require(script.Parent.Parent.Parent.Modules.CrewQuickSlotService)
local CrewStandIncomeAuthority = require(script.Parent.Parent.Parent.Modules.CrewStandIncomeAuthority)
local SpeedUpgradeLimits = require(script.Parent.Parent.Parent.Modules.SpeedUpgradeLimits)
local GearConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local PlotSystem = nil
local PlotsFolder = nil
local crewRewardService = nil

local STEAL_PRODUCTS = {
	[3512126073] = true,
	[3512126373] = true,
	[3512127278] = true,
	[3512127790] = true,
	[3512128038] = true,
	[3512128716] = true,
}

local function getCrewRewardService()
	crewRewardService = crewRewardService or require(script.Parent.Parent.Parent.Modules.CrewRewardService)
	return crewRewardService
end

local function grantCrewReward(player, rewardName, context)
	local ok, resolved, reason = getCrewRewardService().Grant(player, rewardName, 1, {
		Source = "ProductReward",
		Context = context,
	})
	if not ok then
		warn(
			"[ProductFunctions] Crew reward grant skipped",
			"context=" .. tostring(context),
			"reward=" .. tostring(rewardName),
			"reason=" .. tostring(reason),
			"display=" .. tostring(resolved and resolved.DisplayName or "Crewmate Reward")
		)
	end
	return ok, resolved, reason
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

local function StealBrainrotProduct(receiptInfo, buyer, _profile, _DataManager: Types.DataManager)
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

	local standData = CrewStandIncomeAuthority.GetStandData(owner, standName)
	local current = standData and standData.BrainrotName
	if current ~= brainrotName then
		return
	end
	if typeof(brainrotInstanceId) == "string" and brainrotInstanceId ~= "" then
		local currentInstanceId = CrewInstanceService.GetStandInstanceId(owner, standName)
		if currentInstanceId ~= "" and currentInstanceId ~= brainrotInstanceId then
			return
		end
	end

	local transferredInstanceId = CrewInstanceService.TransferStandInstance(owner, buyer, standName)
	if not transferredInstanceId then
		return
	end
	CrewStandIncomeAuthority.SetIncomeToCollect(owner, standName, 0, "product_reward_steal_collect_clear")

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
end

local handlers = {
	[3509346360] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		-- TODO(ProductRewards): Add an Omega/high-tier CrewMember replacement for this retired legacy reward.
		grantCrewReward(player, "Dragon Cannelloni", "ProductFunctions:SuperOPStarterPack")
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 1_000_000_000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 1_000_000_000)
		DataManager:SetValue(player, "Packs.Super OP Starter Pack", true)
	end,

	[3512059347] = function(_receiptInfo, player, _profile, _DataManager: Types.DataManager)
		grantCrewReward(player, "La Vacca Saturno Saturnita", "ProductFunctions:JuiceDuchess")
	end,

	[3509346182] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		grantCrewReward(player, "Tralalero Tralala", "ProductFunctions:BestStarterPack")
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 1_000_000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 1_000_000)
		if DataManager:GetValue(player, "Gears.Lava SpeedCoil") then
			DataManager:SetValue(player, "Gears.Lava SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Lava SpeedCoil"] = true })
		end
		DataManager:SetValue(player, "Packs.Best Starter Pack", true)
	end,

	[3509346000] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		grantCrewReward(player, "Elefanto Cocofanto", "ProductFunctions:BetterStarterPack")
		DataManager:SetValue(player, "Packs.Better Starter Pack", true)

		if DataManager:GetValue(player, "Gears.Diamond SpeedCoil") then
			DataManager:SetValue(player, "Gears.Diamond SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Diamond SpeedCoil"] = true })
		end

		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 100_000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 100_000)
	end,

	[3509345784] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		grantCrewReward(player, "Rubber Captain", "ProductFunctions:StarterPack")
		DataManager:AddValue(player, CurrencyUtil.getPrimaryPath(), 1000)
		DataManager:AddValue(player, CurrencyUtil.getTotalPath(), 1000)
		DataManager:SetValue(player, "Packs.Starter Pack", true)

		if DataManager:GetValue(player, "Gears.SpeedCoil") then
			DataManager:SetValue(player, "Gears.SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["SpeedCoil"] = true })
		end
	end,

	[3515419300] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x15WalkSpeed", 30*60, 3)
	end,

	[3515418772] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x15WalkSpeed", 30*60, 1)
	end,

	[3515418047] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x2Money", 30*60, 3)
	end,

	[3515417573] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		DataManager:StartBoost(player, "x2Money", 30*60, 1)
	end,

	[3515409012] = function(_receiptInfo, _player, _profile, _DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 2
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3515409311] = function(_receiptInfo, _player, _profile, _DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 4
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3515410147] = function(_receiptInfo, _player, _profile, _DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 8
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3515410559] = function(_receiptInfo, _player, _profile, _DataManager: Types.DataManager)
		game.Workspace.ServerLuck.Value = 16
		game.Workspace.ServerLuckTimer.Value += 15 * 60
	end,

	[3509345591] = function(_receiptInfo, _player, _profile, _DataManager: Types.DataManager)
		game.Workspace.NoDisastersTimer.Value += 30
	end,

	[3516522193] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		SpeedUpgradeLimits.ApplySpeedIncrease(DataManager, player, 1)
	end,

	[3516522992] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		SpeedUpgradeLimits.ApplySpeedIncrease(DataManager, player, 5)
	end,

	[3516522609] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		SpeedUpgradeLimits.ApplySpeedIncrease(DataManager, player, 10)
	end,

	[3516539588] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.SpeedCoil") then
			DataManager:SetValue(player, "Gears.SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["SpeedCoil"] = true })
		end
	end,

	[3516540101] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Golden Slap") then
			DataManager:SetValue(player, "Gears.Golden Slap", true)
		else
			DataManager:AddValue(player, "Gears", { ["Golden Slap"] = true })
		end
	end,

	[3516540402] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Golden SpeedCoil") then
			DataManager:SetValue(player, "Gears.Golden SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Golden SpeedCoil"] = true })
		end
	end,

	[3516540726] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Diamond SpeedCoil") then
			DataManager:SetValue(player, "Gears.Diamond SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Diamond SpeedCoil"] = true })
		end
	end,

	[3516541650] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Galaxy Slap") then
			DataManager:SetValue(player, "Gears.Galaxy Slap", true)
		else
			DataManager:AddValue(player, "Gears", { ["Galaxy Slap"] = true })
		end
	end,

	[3516542043] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Galaxy SpeedCoil") then
			DataManager:SetValue(player, "Gears.Galaxy SpeedCoil", true)
		else
			DataManager:AddValue(player, "Gears", { ["Galaxy SpeedCoil"] = true })
		end
	end,

	[3516542817] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
		if DataManager:GetValue(player, "Gears.Lava Slap") then
			DataManager:SetValue(player, "Gears.Lava Slap", true)
		else
			DataManager:AddValue(player, "Gears", { ["Lava Slap"] = true })
		end
	end,

	[3516543186] = function(_receiptInfo, player, _profile, DataManager: Types.DataManager)
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

local crewQuickSlotProductId = tonumber(CrewQuickSlotConfig.ProductId)
if crewQuickSlotProductId and crewQuickSlotProductId > 0 then
	handlers[crewQuickSlotProductId] = function(receiptInfo, player, _profile, DataManager: Types.DataManager)
		local ok, result = CrewQuickSlotService.ProcessUnlockReceipt(player, receiptInfo.ProductId, DataManager, receiptInfo)
		if ok ~= true then
			error("quick_slot_product_unlock_failed:" .. tostring(result and result.Reason or "unknown_error"))
		end
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

local function grantGears(productId, _receiptInfo, player, _profile, DataManager: Types.DataManager)
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
