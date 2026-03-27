local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local STEAL_PRODUCT_ID = 3512126073
local MAX_INCOME_ON_JOIN = 1e16

local BrainrotFoodProgression = require(ServerScriptService.Modules:WaitForChild("BrainrotFoodProgression"))
local BrainrotInstanceService = require(ServerScriptService.Modules:WaitForChild("BrainrotInstanceService"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
local StandUpgradeMults = require(ServerScriptService.Modules.StandsMultiply)

local shorten = require(ReplicatedStorage.Modules.Shorten)
local CurrencyUtil = require(ReplicatedStorage.Modules:WaitForChild("CurrencyUtil"))

local stealProductByRarity = {
	Common = 3512126073,
	Uncommon = 3512126073,
	Rare = 3512126073,
	Epic = 3512126073,

	Legendary = 3512126373,
	Mythic = 3512127278,
	Godly = 3512127790,
	Secret = 3512128038,
	Omega = 3512128716,
}

local rarityPriority = { "Omega", "Secret", "Godly", "Mythic", "Legendary", "Epic", "Rare", "Uncommon", "Common" }

local function normalizeRarity(r)
	r = tostring(r or "")
	if r == "" then
		return "Common"
	end
	local lower = string.lower(r)
	for _, key in ipairs(rarityPriority) do
		if string.find(lower, string.lower(key), 1, true) then
			return key
		end
	end
	return "Common"
end




local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local MoneyCollectedRE = Remotes:FindFirstChild("StandMoneyCollected")
if not MoneyCollectedRE then
	MoneyCollectedRE = Instance.new("RemoteEvent")
	MoneyCollectedRE.Name = "StandMoneyCollected"
	MoneyCollectedRE.Parent = Remotes
end

local dmMod = script.Parent.Parent.Data.DataManager
local DataManager = dmMod and require(dmMod) or nil

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local BrainrotsConfig = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))
local RebirthConfig = require(Configs:WaitForChild("Rebirths"))
local BrainrotRegistry = require(Modules:WaitForChild("Server"):WaitForChild("Brainrot"):WaitForChild("Registry"))
local BrainrotFolder = ReplicatedStorage:WaitForChild("BrainrotFolder")
local dmGet

local PlotSystem = workspace:WaitForChild("PlotSystem")
local PlotsFolder = PlotSystem:WaitForChild("Plots")

pcall(function()
	BrainrotRegistry.Build()
end)

local getPlayerStandBrainrotName
local getPlayerStandBrainrotInstanceId
local getBrainrotLevel
local getStandLevelValue
local dmSet
local STAND_DEBUG = false
local ensuredStandFolders = {}
local standCommandFunction = ShipRuntimeSignals.GetStandCommandFunction()
local DEBUG_TRACE = RunService:IsStudio()

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function ownershipTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[OWNERSHIP TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function plotTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[PLOT TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function saveTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[SAVE TRACE] t=%.3f " .. message, os.clock(), ...))
end

local function countSavedStandEntries(incomeBrainrots)
	if typeof(incomeBrainrots) ~= "table" then
		return 0
	end

	local count = 0
	for _, standData in pairs(incomeBrainrots) do
		if typeof(standData) == "table" and tostring(standData.BrainrotName or "") ~= "" then
			count += 1
		end
	end

	return count
end

local function countTableEntries(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count += 1
	end

	return count
end

local function logSavedShipSnapshot(player, context)
	if not DEBUG_TRACE or not DataManager then
		return
	end

	local ok, result = pcall(function()
		local incomeBrainrots = DataManager:GetValue(player, "IncomeBrainrots")
		local standsLevels = DataManager:GetValue(player, "StandsLevels")
		local shipSlots = DataManager:GetValue(player, "Ship.Slots")
		local plotUpgrade = DataManager:GetValue(player, "HiddenLeaderstats.PlotUpgrade")

		return {
			IncomeBrainrots = incomeBrainrots,
			StandsLevels = standsLevels,
			ShipSlots = shipSlots,
			PlotUpgrade = plotUpgrade,
		}
	end)

	if not ok then
		saveTrace(
			"snapshot context=%s player=%s userId=%s result=lookup_failed reason=%s",
			tostring(context),
			player.Name,
			tostring(player.UserId),
			tostring(result)
		)
		return
	end

	saveTrace(
		"snapshot context=%s player=%s userId=%s plotUpgrade=%s savedStandEntries=%s standsLevels=%s shipSlots=%s",
		tostring(context),
		player.Name,
		tostring(player.UserId),
		tostring(result.PlotUpgrade),
		tostring(countSavedStandEntries(result.IncomeBrainrots)),
		tostring(countTableEntries(result.StandsLevels)),
		tostring(countTableEntries(result.ShipSlots))
	)
end

local function standDebug(message, ...)
	if STAND_DEBUG ~= true then
		return
	end

	warn(string.format("[GLR StandDebug] " .. tostring(message), ...))
end

standDebug("script init")

local function resetHugeIncomeOnJoin(player)
	if not DataManager then
		return
	end

	local ok, incomeBrainrots = pcall(function()
		return DataManager:GetValue(player, "IncomeBrainrots")
	end)

	if not ok or typeof(incomeBrainrots) ~= "table" then
		return
	end

	local changed = false

	for standName, standData in pairs(incomeBrainrots) do
		if typeof(standData) == "table" then
			local income = standData.IncomeToCollect
			if typeof(income) == "number" and income >= MAX_INCOME_ON_JOIN then
				standData.IncomeToCollect = 0
				changed = true
			end
		end
	end

	if changed then
		pcall(function()
			DataManager:SetValue(player, "IncomeBrainrots", incomeBrainrots)
		end)
	end
end


local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName)

	for _, vKey in ipairs(VariantCfg.Order or {}) do
		if vKey ~= "Normal" then
			local v = (VariantCfg.Versions or {})[vKey]
			local prefix = tostring((v and v.Prefix) or (vKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				local baseName = fullName:sub(#prefix + 1)
				return vKey, baseName, v
			end
		end
	end

	return "Normal", fullName, (VariantCfg.Versions or {}).Normal
end

local function findTemplateForName(brainrotName)
	local variantKey, baseName, v = getVariantAndBaseName(brainrotName)

	local registryTemplate = BrainrotRegistry.GetTemplateWithFallback(baseName, variantKey)
	if registryTemplate and registryTemplate:IsA("Model") then
		return registryTemplate
	end

	if variantKey ~= "Normal" then
		local folderName = (v and v.Folder) or variantKey
		local variantFolder = BrainrotFolder:FindFirstChild(folderName)
		if variantFolder and variantFolder:IsA("Folder") then
			local t = variantFolder:FindFirstChild(baseName)
			if t and t:IsA("Model") then
				return t
			end
			local t2 = variantFolder:FindFirstChild(brainrotName)
			if t2 and t2:IsA("Model") then
				return t2
			end
		end
	end

	local direct = BrainrotFolder:FindFirstChild(brainrotName)
	if direct and direct:IsA("Model") then
		return direct
	end

	local base = BrainrotFolder:FindFirstChild(baseName)
	if base and base:IsA("Model") then
		return base
	end

	return nil
end

local function ensurePrimaryPart(model)
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end
	local pp = model:FindFirstChildWhichIsA("BasePart", true)
	if pp then
		pcall(function()
			model.PrimaryPart = pp
		end)
	end
	return model.PrimaryPart or pp
end

local function anchorModel(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.AssemblyLinearVelocity = Vector3.zero
			d.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function makeStandVisualNonBlocking(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanQuery = false
			d.CanCollide = false
		end
	end
end

local function tryPlayIdle(model, animId)
	animId = tonumber(animId)
	if not animId or animId == 0 then
		return
	end
	local controller = model:FindFirstChildOfClass("Humanoid") or model:FindFirstChildOfClass("AnimationController")
	if not controller then
		return
	end
	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(animId)
	pcall(function()
		local track = animator:LoadAnimation(anim)
		track.Looped = true
		track:Play()
	end)
end

local function getStandCollectMultiplier(player, standName)
	local brainrotName = getPlayerStandBrainrotName(player, standName)
	local brainrotInstanceId = getPlayerStandBrainrotInstanceId(player, standName)
	local lvl
	if brainrotName ~= "" then
		lvl = getBrainrotLevel(player, brainrotInstanceId ~= "" and brainrotInstanceId or brainrotName)
		local lvObj = getStandLevelValue(player, standName)
		if lvObj.Value ~= lvl then
			lvObj.Value = lvl
			dmSet(player, "StandsLevels." .. standName, lvl)
		end
	else
		local folder = player:FindFirstChild("StandsLevels")
		local lvObj = folder and folder:FindFirstChild(standName)
		lvl = lvObj and tonumber(lvObj.Value) or 1
	end
	if lvl < 1 then lvl = 1 end

	local mult = tonumber(StandUpgradeMults[tostring(lvl)]) or 1
	if mult <= 0 then mult = 1 end
	local rebirthCount = 0

	local upgradeLevel = 0
	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
	if hiddenLeaderstats then
		local valueObject = hiddenLeaderstats:FindFirstChild("PlotUpgrade")
		if valueObject and valueObject:IsA("NumberValue") then
			upgradeLevel = valueObject.Value
		else
			local storedUpgrade = dmGet(player, "HiddenLeaderstats.PlotUpgrade")
			if typeof(storedUpgrade) == "number" then
				upgradeLevel = storedUpgrade
			end
		end
	else
		local storedUpgrade = dmGet(player, "HiddenLeaderstats.PlotUpgrade")
		if typeof(storedUpgrade) == "number" then
			upgradeLevel = storedUpgrade
		end
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local rebirthValue = leaderstats:FindFirstChild("Rebirths")
		if rebirthValue and rebirthValue:IsA("NumberValue") then
			rebirthCount = math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
		else
			local storedRebirths = dmGet(player, "leaderstats.Rebirths")
			if typeof(storedRebirths) == "number" then
				rebirthCount = math.max(0, math.floor(storedRebirths))
			end
		end
	else
		local storedRebirths = dmGet(player, "leaderstats.Rebirths")
		if typeof(storedRebirths) == "number" then
			rebirthCount = math.max(0, math.floor(storedRebirths))
		end
	end

	return mult
		* PlotUpgradeConfig.GetSlotBonusMultiplier(upgradeLevel, standName, rebirthCount)
		* RebirthConfig.GetShipIncomeMultiplier(rebirthCount)
end

 
local function getEquippedToolName(player)
	local char = player.Character
	if not char then
		return nil
	end
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			local canonical = c:GetAttribute("InvItem") or c:GetAttribute("InventoryItemName")
			if typeof(canonical) == "string" and canonical ~= "" then
				return canonical
			end
			return c.Name
		end
	end
	return nil
end

local function getInventoryQuantity(player, itemName)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		return 0
	end
	local item = inv:FindFirstChild(itemName)
	if not item then
		return 0
	end
	local q = item:FindFirstChild("Quantity")
	if not q or not q:IsA("NumberValue") then
		return 0
	end
	return q.Value
end

dmGet = function(player, path)
	if not DataManager then
		return nil
	end
	local ok, v = pcall(function()
		return DataManager:GetValue(player, path)
	end)
	if ok then
		return v
	end
	return nil
end

dmSet = function(player, path, value)
	if not DataManager then
		return
	end
	pcall(function()
		DataManager:SetValue(player, path, value)
	end)
end

local function dmAdjust(player, path, delta)
	if not DataManager then
		return
	end
	if typeof(DataManager.AdjustValue) == "function" then
		pcall(function()
			DataManager:AdjustValue(player, path, delta)
		end)
		return
	end
	if delta > 0 and typeof(DataManager.AddValue) == "function" then
		pcall(function()
			DataManager:AddValue(player, path, delta)
		end)
	elseif delta < 0 and typeof(DataManager.SubValue) == "function" then
		pcall(function()
			DataManager:SubValue(player, path, -delta)
		end)
	end
end

local function getPlayerShipUpgradeLevel(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 0
	end

	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
	if hiddenLeaderstats then
		local plotUpgradeValue = hiddenLeaderstats:FindFirstChild("PlotUpgrade")
		if plotUpgradeValue and plotUpgradeValue:IsA("NumberValue") then
			return PlotUpgradeConfig.ClampLevel(plotUpgradeValue.Value)
		end
	end

	local storedUpgrade = dmGet(player, "HiddenLeaderstats.PlotUpgrade")
	if typeof(storedUpgrade) == "number" then
		return PlotUpgradeConfig.ClampLevel(storedUpgrade)
	end

	return 0
end

local function getSlotBonusPercent(bonusInfo)
	if typeof(bonusInfo) ~= "table" then
		return 0
	end

	return math.max(0, math.floor((((tonumber(bonusInfo.Multiplier) or 1) - 1) * 100) + 0.5))
end

local function getStandSlotState(player, standName)
	local upgradeLevel = getPlayerShipUpgradeLevel(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirthValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
	local rebirthCount = 0
	if rebirthValue and rebirthValue:IsA("NumberValue") then
		rebirthCount = math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
	else
		local storedRebirths = dmGet(player, "leaderstats.Rebirths")
		if typeof(storedRebirths) == "number" then
			rebirthCount = math.max(0, math.floor(storedRebirths))
		end
	end

	local isVisible = PlotUpgradeConfig.IsStandVisible(upgradeLevel, standName, rebirthCount)
	local isUsable = PlotUpgradeConfig.IsStandUsable(upgradeLevel, standName, rebirthCount)
	local bonusInfo = isUsable and PlotUpgradeConfig.GetSlotBonusInfo(upgradeLevel, standName, rebirthCount) or nil

	return {
		Level = upgradeLevel,
		Rebirths = rebirthCount,
		Visible = isVisible,
		Usable = isUsable,
		BonusInfo = bonusInfo,
		BonusPercent = getSlotBonusPercent(bonusInfo),
		UnlockLevel = PlotUpgradeConfig.GetStandUnlockLevel(standName),
	}
end

local function getShipSlotsTable(player)
	local slots = dmGet(player, "Ship.Slots")
	if typeof(slots) ~= "table" then
		return {}
	end

	return slots
end

local function syncShipSlotAssignment(player, standName, slotData)
	local slots = getShipSlotsTable(player)
	if slotData == nil then
		slots[standName] = nil
	else
		slots[standName] = slotData
	end

	dmSet(player, "Ship.Slots", slots)
end

local function clearPlacedStandIncome(player, standName)
	dmSet(player, "IncomeBrainrots." .. standName .. ".IncomeToCollect", 0)
	syncShipSlotAssignment(player, standName, nil)
end

local function dmEnsureStandFolder(player, standName)
	if not DataManager then
		return false
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end
	if typeof(standName) ~= "string" or standName == "" then
		return false
	end

	local playerCache = ensuredStandFolders[player]
	if playerCache and playerCache[standName] == true then
		return true
	end

	local brainrotPath = "IncomeBrainrots." .. standName .. ".BrainrotName"
	local instancePath = "IncomeBrainrots." .. standName .. ".BrainrotInstanceId"
	local incomePath = "IncomeBrainrots." .. standName .. ".IncomeToCollect"
	local didRepair = false

	local okName, nameVal = pcall(function()
		return DataManager:GetValue(player, brainrotPath)
	end)
	if not okName then
		return false
	end

	if nameVal == nil then
		local okRepairIncome = pcall(function()
			local incomeBrainrots = DataManager:GetValue(player, "IncomeBrainrots")
			if typeof(incomeBrainrots) ~= "table" then
				incomeBrainrots = {}
			end

			if typeof(incomeBrainrots[standName]) ~= "table" then
				incomeBrainrots[standName] = {
					IncomeToCollect = 0,
					BrainrotName = "",
					BrainrotInstanceId = "",
				}
			else
				if typeof(incomeBrainrots[standName].IncomeToCollect) ~= "number" then
					incomeBrainrots[standName].IncomeToCollect = 0
				end
				if typeof(incomeBrainrots[standName].BrainrotName) ~= "string" then
					incomeBrainrots[standName].BrainrotName = ""
				end
				if typeof(incomeBrainrots[standName].BrainrotInstanceId) ~= "string" then
					incomeBrainrots[standName].BrainrotInstanceId = ""
				end
			end

			DataManager:SetValue(player, "IncomeBrainrots", incomeBrainrots)
		end)
		if not okRepairIncome then
			return false
		end
		didRepair = true

		local okRepairLevels = pcall(function()
			local lv = DataManager:GetValue(player, "StandsLevels")
			if typeof(lv) ~= "table" then
				lv = {}
			end
			if typeof(lv[standName]) ~= "number" or lv[standName] < 1 then
				lv[standName] = 1
			end
			DataManager:SetValue(player, "StandsLevels", lv)
		end)
		if not okRepairLevels then
			return false
		end
		didRepair = true
	else
		if typeof(nameVal) ~= "string" then
			local okRepairName = pcall(function()
				DataManager:SetValue(player, brainrotPath, "")
			end)
			if not okRepairName then
				return false
			end
			didRepair = true
		end
		local okInstance, instanceVal = pcall(function()
			return DataManager:GetValue(player, instancePath)
		end)
		if okInstance and typeof(instanceVal) ~= "string" then
			local okRepairInstance = pcall(function()
				DataManager:SetValue(player, instancePath, "")
			end)
			if not okRepairInstance then
				return false
			end
			didRepair = true
		end

		local okIncome, incVal = pcall(function()
			return DataManager:GetValue(player, incomePath)
		end)
		if not okIncome then
			return false
		end
		if incVal == nil or typeof(incVal) ~= "number" then
			local okRepairIncome = pcall(function()
				DataManager:SetValue(player, incomePath, 0)
			end)
			if not okRepairIncome then
				return false
			end
			didRepair = true
		end
	end

	playerCache = ensuredStandFolders[player]
	if not playerCache then
		playerCache = {}
		ensuredStandFolders[player] = playerCache
	end
	playerCache[standName] = true

	if didRepair then
		standDebug("dmEnsureStandFolder repaired player=%s stand=%s", player.Name, standName)
	end

	return true
end


getPlayerStandBrainrotName = function(player, standName)
	dmEnsureStandFolder(player, standName)
	local v = dmGet(player, "IncomeBrainrots." .. standName .. ".BrainrotName")
	if typeof(v) ~= "string" then
		return ""
	end
	return v
end

getPlayerStandBrainrotInstanceId = function(player, standName)
	dmEnsureStandFolder(player, standName)

	local standBrainrotName = getPlayerStandBrainrotName(player, standName)
	if standBrainrotName == "" then
		return ""
	end

	local instanceId = BrainrotInstanceService.GetStandInstanceId(player, standName)
	if instanceId ~= "" then
		return instanceId
	end

	local ensuredInstanceId = BrainrotInstanceService.EnsureStandInstance(player, standName, standBrainrotName)
	return tostring(ensuredInstanceId or "")
end

local function getPlayerStandIncome(player, standName)
	dmEnsureStandFolder(player, standName)
	local v = dmGet(player, "IncomeBrainrots." .. standName .. ".IncomeToCollect")
	if typeof(v) ~= "number" then
		return 0
	end
	return v
end

local function ensureInventoryLevelValue(player, brainrotName, level)
	local inv = player:FindFirstChild("Inventory")
	if not inv then
		inv = Instance.new("Folder")
		inv.Name = "Inventory"
		inv.Parent = player
	end

	local item = inv:FindFirstChild(brainrotName)
	if not item then
		item = Instance.new("Folder")
		item.Name = brainrotName
		item.Parent = inv
	end

	local lv = item:FindFirstChild("Level")
	if not lv then
		lv = Instance.new("NumberValue")
		lv.Name = "Level"
		lv.Parent = item
	end
	lv.Value = level

	local currentXP = item:FindFirstChild("CurrentXP")
	if not currentXP then
		currentXP = Instance.new("NumberValue")
		currentXP.Name = "CurrentXP"
		currentXP.Parent = item
	end
	if currentXP.Value < 0 then
		currentXP.Value = 0
	end
end

local function legacyFindBrainrotInfoByName(brainrotName)
	if BrainrotsConfig[brainrotName] then
		return BrainrotsConfig[brainrotName], brainrotName
	end
	for id, info in pairs(BrainrotsConfig) do
		if tostring(info.Render or "") == tostring(brainrotName) then
			return info, tostring(id)
		end
	end
	for id, info in pairs(BrainrotsConfig) do
		local n = tostring(info.Name or info.DisplayName or "")
		if n ~= "" and n == tostring(brainrotName) then
			return info, tostring(id)
		end
	end
	return nil, nil
end

local function hasInventoryBrainrotEntry(player, itemName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	if typeof(itemName) ~= "string" or itemName == "" then
		return false
	end

	local qty = dmGet(player, "Inventory." .. itemName .. ".Quantity")
	if typeof(qty) == "number" then
		return true
	end

	local inventory = player:FindFirstChild("Inventory")
	local folder = inventory and inventory:FindFirstChild(itemName)
	return folder ~= nil
end

local function getInventoryBrainrotMetadata(player, itemName)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil
	end

	if typeof(itemName) ~= "string" or itemName == "" then
		return nil, nil
	end

	local baseName = dmGet(player, "Inventory." .. itemName .. ".BaseName")
	local variantKey = dmGet(player, "Inventory." .. itemName .. ".Variant")

	if typeof(baseName) == "string" and baseName ~= "" then
		if typeof(variantKey) ~= "string" or variantKey == "" then
			variantKey = "Normal"
		end
		return variantKey, baseName
	end

	local inventory = player:FindFirstChild("Inventory")
	local folder = inventory and inventory:FindFirstChild(itemName)
	if not folder then
		return nil, nil
	end

	local baseValue = folder:FindFirstChild("BaseName")
	local variantValue = folder:FindFirstChild("Variant")
	local base = baseValue and baseValue:IsA("StringValue") and baseValue.Value or nil
	local variant = variantValue and variantValue:IsA("StringValue") and variantValue.Value or nil

	if typeof(base) == "string" and base ~= "" then
		if typeof(variant) ~= "string" or variant == "" then
			variant = "Normal"
		end
		return variant, base
	end

	return nil, nil
end

local function resolveBrainrotRecord(player, brainrotName)
	local rawName = tostring(brainrotName or "")
	if rawName == "" then
		return nil
	end

	local candidates = {}
	local seen = {}

	local function pushCandidate(itemName)
		if typeof(itemName) ~= "string" or itemName == "" or seen[itemName] then
			return
		end
		seen[itemName] = true
		table.insert(candidates, itemName)
	end

	pushCandidate(rawName)

	local invVariant, invBase = getInventoryBrainrotMetadata(player, rawName)
	if invBase then
		pushCandidate(BrainrotRegistry.MakeVariantId(invBase, invVariant))
	end

	local parsedVariant, parsedBase = getVariantAndBaseName(rawName)
	pushCandidate(BrainrotRegistry.MakeVariantId(parsedBase, parsedVariant))
	pushCandidate(parsedBase)

	local legacyInfo, legacyId = legacyFindBrainrotInfoByName(rawName)
	if legacyId then
		pushCandidate(legacyId)
	end

	for _, candidateName in ipairs(candidates) do
		local variantKey, baseName = getVariantAndBaseName(candidateName)
		local template, usedVariant = BrainrotRegistry.GetTemplateWithFallback(baseName, variantKey)
		local finalVariant = usedVariant or variantKey or "Normal"
		local info = BrainrotRegistry.GetOrBuildVariantInfo(baseName, finalVariant)

		if template or info then
			local canonicalName = BrainrotRegistry.MakeVariantId(baseName, finalVariant)
			local storageName = rawName

				if hasInventoryBrainrotEntry(player, candidateName) then
					storageName = candidateName
				elseif hasInventoryBrainrotEntry(player, canonicalName) or not hasInventoryBrainrotEntry(player, rawName) then
					storageName = canonicalName
				end

			return {
				RawName = rawName,
				CanonicalName = canonicalName,
				StorageName = storageName,
				BaseName = baseName,
				VariantKey = finalVariant,
				Template = template,
				Info = info or legacyInfo,
			}
		end
	end

	if legacyInfo then
		return {
			RawName = rawName,
			CanonicalName = tostring(legacyId or rawName),
			StorageName = hasInventoryBrainrotEntry(player, rawName) and rawName or tostring(legacyId or rawName),
			BaseName = tostring(legacyId or rawName),
			VariantKey = parsedVariant,
			Template = findTemplateForName(tostring(legacyId or rawName)),
			Info = legacyInfo,
		}
	end

	return nil
end

local function findBrainrotInfoByName(brainrotName, player)
	local resolved = resolveBrainrotRecord(player, brainrotName)
	if resolved and resolved.Info then
		return resolved.Info, resolved.CanonicalName
	end

	return legacyFindBrainrotInfoByName(brainrotName)
end

local function getStealProductIdForBrainrot(brainrotName)
	local info = findBrainrotInfoByName(brainrotName)
	local rarity = info and info.Rarity or "Common"
	local fixed = normalizeRarity(rarity)
	return stealProductByRarity[fixed] or 3512126073
end


local function updateStandPromptTexts(player, standModel)
	if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
		return
	end

	local handle = standModel:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		return
	end

	local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end

	local standName = standModel.Name
	local slotState = player and player:IsA("Player") and getStandSlotState(player, standName) or nil
	local brainrotName = ""

	if player and player:IsA("Player") then
		brainrotName = getPlayerStandBrainrotName(player, standName)
	end

	if slotState and slotState.Visible and not slotState.Usable then
		prompt.ObjectText = "Slot Locked"
		prompt.ActionText = PlotUpgradeConfig.GetLockedSlotDescription(slotState.Level, standName, slotState.Rebirths) or "Upgrade Ship"
		return
	end

	if brainrotName ~= "" then
		local resolved = resolveBrainrotRecord(player, brainrotName)
		local info = resolved and resolved.Info or findBrainrotInfoByName(brainrotName, player)
		local displayName = info and tostring(info.Name or info.DisplayName or resolved and resolved.CanonicalName or brainrotName) or tostring(brainrotName)
		if slotState and slotState.BonusInfo then
			prompt.ObjectText = string.format(
				"%s (%s +%d%%)",
				displayName,
				tostring(slotState.BonusInfo.Label or "Bonus"),
				slotState.BonusPercent
			)
		else
			prompt.ObjectText = displayName
		end
		prompt.ActionText = "Pick Up"
	else
		if slotState and slotState.BonusInfo then
			prompt.ObjectText = tostring(slotState.BonusInfo.Label or standName)
			prompt.ActionText = string.format("Place Here (+%d%%)", slotState.BonusPercent)
		else
			prompt.ObjectText = tostring(standName)
			prompt.ActionText = "Place Here"
		end
	end
end

local function findHoverGui(primaryPart)
	local h = primaryPart:FindFirstChild("BrainrotHover", true)
	if h and h:IsA("BillboardGui") then
		return h
	end
	h = primaryPart:FindFirstChild("BrainortHover", true)
	if h and h:IsA("BillboardGui") then
		return h
	end
	return nil
end

getBrainrotLevel = function(player, brainrotName)
	local progress = BrainrotFoodProgression.GetProgress(player, brainrotName)
	if not progress then
		return 1
	end
	return progress.Level
end

local function getBaseIncome(player, brainrotName)
	local resolved = resolveBrainrotRecord(player, brainrotName)
	local info = resolved and resolved.Info or findBrainrotInfoByName(brainrotName, player)
	local base = info and (tonumber(info.Income) or 0) or 0
	return base
end

local function getIncomeWithLevel(player, brainrotName)
	local base = getBaseIncome(player, brainrotName)
	if base <= 0 then
		return 0
	end
	local lvl = getBrainrotLevel(player, brainrotName)
	local mult =1
	return base * mult
end

local function getStandIncomeDisplay(player, standName)
	standDebug("getStandIncomeDisplay begin player=%s stand=%s", player.Name, standName)
	local base = getPlayerStandIncome(player, standName)
	if base <= 0 then
		standDebug("getStandIncomeDisplay early_zero player=%s stand=%s", player.Name, standName)
		return 0
	end
	local display = base * getStandCollectMultiplier(player, standName)
	standDebug("getStandIncomeDisplay done player=%s stand=%s base=%s display=%s", player.Name, standName, tostring(base), tostring(display))
	return display
end

local RaritiesFolder = ReplicatedStorage:WaitForChild("Rarities")
local BrainrotHoverTemplate = RaritiesFolder:WaitForChild("BrainrotHover")

local function ensureBrainrotHover(model)
	local primary = ensurePrimaryPart(model)
	if not primary then
		return nil
	end

	local existing = findHoverGui(primary)
	if existing then
		existing.Enabled = true
		return existing
	end

	if not BrainrotHoverTemplate or not BrainrotHoverTemplate:IsA("BillboardGui") then
		return nil
	end

	local clone = BrainrotHoverTemplate:Clone()
	clone.Name = "BrainrotHover"
	clone.Enabled = true
	clone.Adornee = primary
	clone.Parent = primary
	return clone
end

local function getTextTarget(root, name)
	local obj = root:FindFirstChild(name, true)
	if not obj then
		return nil
	end
	if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
		return obj
	end
	return obj:FindFirstChildWhichIsA("TextLabel", true) or obj:FindFirstChildWhichIsA("TextButton", true) or obj:FindFirstChildWhichIsA("TextBox", true)
end

local function buildHoverRefsNoTime(model)
	local primary = ensurePrimaryPart(model)
	if not primary then
		return nil
	end
	local hover = findHoverGui(primary)
	if not hover then
		return nil
	end
	hover.Enabled = true
	local income = getTextTarget(hover, "Income")
	local nameT = getTextTarget(hover, "Name")
	local rarityT = getTextTarget(hover, "Rarity")

	local timeLeftContainer = hover:FindFirstChild("TimeLeft", true)
	local timeT
	local timeImg
	if timeLeftContainer then
		timeT = getTextTarget(timeLeftContainer, "TextL")
		if not timeT then
			timeT = timeLeftContainer:FindFirstChildWhichIsA("TextLabel", true) or timeLeftContainer:FindFirstChildWhichIsA("TextButton", true) or timeLeftContainer:FindFirstChildWhichIsA("TextBox", true)
		end
		timeImg = timeLeftContainer:FindFirstChild("ImageLabel", true) or timeLeftContainer:FindFirstChildWhichIsA("ImageLabel", true)
	end
	if not timeT then
		timeT = getTextTarget(hover, "TextL") or getTextTarget(hover, "TimeLeft")
	end

	if timeT then timeT.Visible = false end
	if timeImg then timeImg.Visible = false end

	return {
		Income = income,
		Name = nameT,
		Rarity = rarityT,
		Gui = hover,
	}
end

local ReplicatedStorage2 = game:GetService("ReplicatedStorage")
local RarityTexts = ReplicatedStorage2:WaitForChild("Rarities"):WaitForChild("Texts")

local function clearRarityLabel(label)
	if label:IsA("TextLabel") then
		label.Text = ""
	end
	for _, child in ipairs(label:GetChildren()) do
		child:Destroy()
	end
end

local VariantOrder = { "Normal", "Golden", "Diamond" }
local VariantPrefix = {
	Normal = "",
	Golden = "Golden ",
	Diamond = "Diamond ",
}

local function startsWith(s, pref)
	return s:sub(1, #pref) == pref
end

local function detectVariant(text)
	text = tostring(text or "")
	for _, v in ipairs(VariantOrder) do
		if v ~= "Normal" then
			local pref = tostring(VariantPrefix[v] or (v .. " "))
			if pref ~= "" and startsWith(text, pref) then
				return v
			end
			local alt = v .. " "
			if startsWith(text, alt) then
				return v
			end
		end
	end
	return "Normal"
end

local function stripVariantPrefix(text, variantKey)
	text = tostring(text or "")
	if not variantKey or variantKey == "Normal" then
		return text
	end
	local pref = tostring(VariantPrefix[variantKey] or (variantKey .. " "))
	if pref ~= "" and startsWith(text, pref) then
		local out = text:sub(#pref + 1)
		if out ~= "" then
			return out
		end
	end
	local alt = variantKey .. " "
	if startsWith(text, alt) then
		local out = text:sub(#alt + 1)
		if out ~= "" then
			return out
		end
	end
	return text
end

local function applyVariantLabel(hoverGui, variantKey, enabled)
	if not hoverGui then
		return
	end
	for _, d in ipairs(hoverGui:GetDescendants()) do
		if d:IsA("GuiObject") then
			for _, v in ipairs(VariantOrder) do
				if d.Name == v then
					d.Visible = enabled and (v == variantKey)
				end
			end
		end
	end
end

local function applyRarityFromStorage(rarityLabel, rarityName)
	if not rarityLabel or rarityName == "" then
		return
	end

	clearRarityLabel(rarityLabel)

	local template = RarityTexts:FindFirstChild(rarityName)
	if not template then
		for _, obj in ipairs(RarityTexts:GetChildren()) do
			if obj:IsA("TextLabel") and obj.Name == rarityName then
				template = obj
				break
			end
		end
	end

	if not template or not template:IsA("TextLabel") then
		if rarityLabel:IsA("TextLabel") then
			rarityLabel.Text = rarityName
		end
		return
	end
	rarityLabel.Text = tostring(rarityName)

	for _, child in ipairs(template:GetChildren()) do
		child:Clone().Parent = rarityLabel
	end
end

local function setHoverTextsNoTime(refs, player, brainrotName)
	if not refs then
		return
	end

	local resolved = resolveBrainrotRecord(player, brainrotName)
	local info = resolved and resolved.Info or findBrainrotInfoByName(brainrotName, player)
	local canonicalName = resolved and resolved.CanonicalName or tostring(brainrotName)
	local rawName = info and tostring(info.Name or info.DisplayName or canonicalName) or tostring(brainrotName)
	local rawRarity = info and tostring(info.Rarity or "") or ""

	local variantKey = resolved and resolved.VariantKey or detectVariant(brainrotName)
	if variantKey == "Normal" then
		variantKey = detectVariant(rawName)
	end
	if variantKey == "Normal" then
		variantKey = detectVariant(rawRarity)
	end

	local displayName = stripVariantPrefix(rawName, variantKey)
	local displayRarity = stripVariantPrefix(rawRarity, variantKey)

	local income = 0
	if player and player:IsA("Player") then
		income = getIncomeWithLevel(player, canonicalName)
	else
		income = info and (tonumber(info.Income) or 0) or 0
	end

	if refs.Income then
		refs.Income.Text = shorten.roundNumber(math.floor(income)) .. CurrencyUtil.getPerSecondSuffix()
	end
	if refs.Name then
		refs.Name.Text = displayName
	end
	if refs.Rarity then
		applyRarityFromStorage(refs.Rarity, displayRarity)
	end
	if refs.Gui then
		refs.Gui.Enabled = true
		applyVariantLabel(refs.Gui, variantKey, true)
	end
end

local function clearStandVisual(standModel)
	local existing = standModel:FindFirstChild("PlacedBrainrot")
	if existing and existing:IsA("Model") then
		existing:Destroy()
	end
end

local function placeModelBottomOnHandleLeft(model, handle)
	local boxCF, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCF)
	local up = handle.CFrame.UpVector
	local surface = handle.Position + up * (handle.Size.Y / 2)
	local rot = (handle.CFrame - handle.Position) * CFrame.Angles(0, math.rad(90), 0)
	local desiredBox = CFrame.new(surface + up * (boxSize.Y / 2)) * rot
	local pivotTarget = desiredBox * offset:Inverse()
	model:PivotTo(pivotTarget)
end

local function spawnStandBrainrot(player, standModel, handle, brainrotName)
	clearStandVisual(standModel)

	local resolved = resolveBrainrotRecord(player, brainrotName)
	local template = resolved and resolved.Template or findTemplateForName(brainrotName)
	standDebug(
		"spawnStandBrainrot begin player=%s stand=%s savedName=%s canonical=%s template=%s",
		player and player.Name or "?",
		standModel and standModel.Name or "?",
		tostring(brainrotName),
		tostring(resolved and resolved.CanonicalName or brainrotName),
		tostring(template and template:GetFullName() or "nil")
	)
	if not template or not template:IsA("Model") then
		warn(string.format("[IncomeBrainrots] Failed to restore stand brainrot template player=%s stand=%s savedName=%s", player and player.Name or "?", standModel.Name, tostring(brainrotName)))
		standDebug(
			"spawnStandBrainrot failed player=%s stand=%s reason=no_template",
			player and player.Name or "?",
			standModel and standModel.Name or "?"
		)
		return
	end

	local clone = template:Clone()
	clone.Name = "PlacedBrainrot"
	clone.Parent = standModel

	ensurePrimaryPart(clone)
	anchorModel(clone)
	makeStandVisualNonBlocking(clone)
	placeModelBottomOnHandleLeft(clone, handle)

	ensureBrainrotHover(clone)

	local info = resolved and resolved.Info or findBrainrotInfoByName(brainrotName, player)
	if info then
		tryPlayIdle(clone, info.IdleAnim)
	end

	local refs = buildHoverRefsNoTime(clone)
	setHoverTextsNoTime(refs, player, resolved and resolved.CanonicalName or brainrotName)
	standDebug(
		"spawnStandBrainrot success player=%s stand=%s model=%s incomeBase=%s",
		player and player.Name or "?",
		standModel and standModel.Name or "?",
		clone:GetFullName(),
		tostring(resolved and resolved.Info and resolved.Info.Income or info and info.Income or "nil")
	)
end

local function getMoneyLabel(standModel)
	local claim = standModel:FindFirstChild("Claim", true)
	if not claim then
		return nil
	end
	local zone = claim:FindFirstChild("Zone", true)
	if not zone then
		return nil
	end
	local bb = zone:FindFirstChildWhichIsA("BillboardGui", true) or zone:FindFirstChild("BillboardGui", true)
	if not bb then
		return nil
	end
	return getTextTarget(bb, "Money")
end

local function setMoneyText(standModel, amount)
	local money = getMoneyLabel(standModel)
	if money then
		money.TextWrapped = true
		money.Text = shorten.roundNumber(math.floor(amount)) .. CurrencyUtil.getCompactSuffix()
	end
end

local function setMoneyLabelText(standModel, text)
	local money = getMoneyLabel(standModel)
	if money then
		money.TextWrapped = true
		money.Text = tostring(text)
	end
end

local function updateStandMoneyText(player, standModel)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local standName = standModel.Name
	local slotState = getStandSlotState(player, standName)
	if slotState.Visible and not slotState.Usable then
		setMoneyLabelText(standModel, "LOCKED")
		return
	end

	local brainrotName = getPlayerStandBrainrotName(player, standName)
	local incomeText = shorten.roundNumber(math.floor(getStandIncomeDisplay(player, standName))) .. CurrencyUtil.getCompactSuffix()
	if brainrotName == "" and slotState.BonusInfo then
		setMoneyLabelText(
			standModel,
			string.format("%s +%d%%", tostring(slotState.BonusInfo.Label or "Bonus"), slotState.BonusPercent)
		)
		return
	end

	if brainrotName ~= "" and slotState.BonusInfo then
		setMoneyLabelText(
			standModel,
			string.format("%s +%d%%\n%s", tostring(slotState.BonusInfo.Label or "Bonus"), slotState.BonusPercent, incomeText)
		)
		return
	end

	setMoneyText(standModel, getStandIncomeDisplay(player, standName))
end

local function getHitBoxPart(standModel)
	local claim = standModel:FindFirstChild("Claim", true)
	if not claim then
		return nil
	end
	local zone = claim:FindFirstChild("HitBox", true)
	if zone and zone:IsA("BasePart") then
		return zone
	end
	return nil
end

local function findPlotForPlayer(player)
	for _, m in ipairs(PlotsFolder:GetChildren()) do
		if m:IsA("Model") then
			local owner = m:GetAttribute("OwnerUserId")
			local ownerName = m:GetAttribute("OwnerName")
			local matchedByUserId = owner == player.UserId
			local decision = matchedByUserId and "accepted" or "rejected_owner_userid_mismatch"
			ownershipTrace(
				"findPlotForPlayer player=%s userId=%s plot=%s ownerUserId=%s ownerUserIdType=%s ownerName=%s plotName=%s matchedByUserId=%s decision=%s",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(m),
				tostring(owner),
				typeof(owner),
				tostring(ownerName),
				tostring(m.Name),
				tostring(matchedByUserId),
				decision
			)
			if matchedByUserId then
				return m
			end
		end
	end
	return nil
end

local function waitForPlot(player, timeout)
	local t0 = os.clock()
	standDebug("waitForPlot begin player=%s timeout=%s", player.Name, tostring(timeout or 15))
	saveTrace(
		"restoreWait begin player=%s userId=%s timeout=%s check=plot.OwnerUserId==player.UserId",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	ownershipTrace(
		"waitForPlot begin player=%s userId=%s timeout=%s",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	while os.clock() - t0 < (timeout or 15) do
		local plot = findPlotForPlayer(player)
		if plot then
			standDebug("waitForPlot found player=%s plot=%s", player.Name, plot:GetFullName())
			local slot = plot:FindFirstChild("Slot")
			local posPart = slot and slot:IsA("ObjectValue") and slot.Value or nil
			local spawnPart = plot:FindFirstChild("SpawnLocation", true)
			plotTrace(
				"waitForPlot found player=%s userId=%s plot=%s slot=%s slotPos=%s spawn=%s spawnPos=%s ownerUserId=%s ownerUserIdType=%s ownerName=%s accepted=%s",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(plot),
				formatInstancePath(posPart),
				formatVector3(posPart and posPart.Position or nil),
				formatInstancePath(spawnPart),
				formatVector3(spawnPart and spawnPart:IsA("BasePart") and spawnPart.Position or nil),
				tostring(plot:GetAttribute("OwnerUserId")),
				typeof(plot:GetAttribute("OwnerUserId")),
				tostring(plot:GetAttribute("OwnerName")),
				"true"
			)
			saveTrace(
				"restoreWait accepted player=%s userId=%s plot=%s plotOwnerUserId=%s plotOwnerUserIdType=%s reason=owner_userid_match",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(plot),
				tostring(plot:GetAttribute("OwnerUserId")),
				typeof(plot:GetAttribute("OwnerUserId"))
			)
			return plot
		end
		task.wait(0.25)
	end
	standDebug("waitForPlot timed_out player=%s", player.Name)
	saveTrace(
		"restoreWait skipped player=%s userId=%s reason=no_plot_with_matching_owner_userid timeout=%s",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	ownershipTrace(
		"waitForPlot timed_out player=%s userId=%s timeout=%s",
		player.Name,
		tostring(player.UserId),
		tostring(timeout or 15)
	)
	return nil
end

local function getStandsFolder(plot)
	local stands = plot:FindFirstChild("Stands", true)
	if stands and stands:IsA("Folder") then
		return stands
	end
	return nil
end

local function getLevelUpPart(standModel)
	local p = standModel:FindFirstChild("LevelUp", true)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function getLevelUpGuiRoot(standModel, player)
	local part = getLevelUpPart(standModel)
	if not part then
		return nil, nil, nil
	end
	local sg = part:FindFirstChildWhichIsA("SurfaceGui", true) or part:FindFirstChild("SurfaceGui")
	if (not sg or not sg:IsA("SurfaceGui")) and player and player:IsA("Player") then
		local playerGui = player:FindFirstChild("PlayerGui")
		local playerSurfaceGui = playerGui and playerGui:FindFirstChild(standModel.Name)
		if playerSurfaceGui and playerSurfaceGui:IsA("SurfaceGui") then
			sg = playerSurfaceGui
		end
	end
	if not sg or not sg:IsA("SurfaceGui") then
		return part, nil, nil
	end
	local root = sg:FindFirstChild("LevelUp")
	if root and root:IsA("GuiObject") then
		return part, sg, root
	end
	return part, sg, nil
end

local function setLevelUpVisible(standModel, visible, player)
	local part, sg, root = getLevelUpGuiRoot(standModel, player)
	if sg then
		sg.Enabled = visible
	end
	if root then
		root.Visible = visible
	end
	local cd = part and part:FindFirstChildOfClass("ClickDetector")
	if cd then
		cd.MaxActivationDistance = visible and 15 or 0
	end
end

local function getLevelUpRefs(standModel, player)
	local part, sg, root = getLevelUpGuiRoot(standModel, player)
	if not part or not sg then
		return nil
	end
	local container = root or sg
	local main = container:FindFirstChild("Main", true) or container
	local price = getTextTarget(main, "Price")
	local upg = getTextTarget(main, "Upgarde") or getTextTarget(main, "Upgrade")
	return {
		Part = part,
		SurfaceGui = sg,
		Root = root,
		Main = main,
		Price = price,
		Upgrade = upg,
	}
end

local function ensureLevelUpClickDetector(standModel)
	local part = getLevelUpPart(standModel)
	if not part then
		return nil
	end
	local cd = part:FindFirstChildOfClass("ClickDetector")
	if not cd then
		cd = Instance.new("ClickDetector")
		cd.MaxActivationDistance = 15
		cd.Parent = part
	end
	return cd
end

local function updateStandHover(player, standModel, brainrotName)
	local placed = standModel:FindFirstChild("PlacedBrainrot")
	if placed and placed:IsA("Model") then
		ensureBrainrotHover(placed)
		local refs = buildHoverRefsNoTime(placed)
		setHoverTextsNoTime(refs, player, brainrotName)
	end
end

getStandLevelValue = function(player, standName)
	local folder = player:FindFirstChild("StandsLevels")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "StandsLevels"
		folder.Parent = player
	end

	local v = folder:FindFirstChild(standName)
	if not v or not v:IsA("NumberValue") then
		if v then v:Destroy() end
		v = Instance.new("NumberValue")
		v.Name = standName
		v.Value = 1
		v.Parent = folder
	end

	if v.Value < 1 then v.Value = 1 end
	return v
end

local function getStandLevel(player, standName)
	return getStandLevelValue(player, standName).Value
end

local function setStandLevel(player, standName, level)
	local lvObj = getStandLevelValue(player, standName)
	local safeLevel = math.max(1, math.floor(tonumber(level) or 1))
	lvObj.Value = safeLevel
	dmSet(player, "StandsLevels." .. standName, safeLevel)
	return safeLevel
end

local function syncStandLevelFromBrainrot(player, standName, brainrotName)
	if brainrotName == nil or brainrotName == "" then
		return setStandLevel(player, standName, 1)
	end

	local lvl = getBrainrotLevel(player, brainrotName)
	return setStandLevel(player, standName, lvl)
end

local function updateLevelUpUI(player, standModel)
	local refs = getLevelUpRefs(standModel, player)
	if not refs then return end

	local standName = standModel.Name
	local slotState = getStandSlotState(player, standName)
	if slotState.Visible and not slotState.Usable then
		setLevelUpVisible(standModel, false, player)
		if refs.Price then refs.Price.Text = "" end
		if refs.Upgrade then refs.Upgrade.Text = "" end
		return
	end

	local brainrotName = getPlayerStandBrainrotName(player, standName)
	local brainrotInstanceId = getPlayerStandBrainrotInstanceId(player, standName)

	if brainrotName == "" then
		setLevelUpVisible(standModel, false, player)
		if refs.Price then refs.Price.Text = "" end
		if refs.Upgrade then refs.Upgrade.Text = "" end
		standDebug("updateLevelUpUI hidden player=%s stand=%s reason=no_brainrot", player.Name, standName)
		return
	end

	local progress = BrainrotFoodProgression.GetProgress(player, brainrotInstanceId ~= "" and brainrotInstanceId or brainrotName)
	if not progress then
		setLevelUpVisible(standModel, false, player)
		if refs.Price then refs.Price.Text = "" end
		if refs.Upgrade then refs.Upgrade.Text = "" end
		return
	end

	local currentLevel = setStandLevel(player, standName, progress.Level)
	local xpText = string.format("XP: %d / %d", math.max(0, progress.CurrentXP), math.max(0, progress.NextLevelXP))
	if BrainrotFoodProgression.GetTotalFoodCount(player) > 0 then
		xpText ..= " | Auto-feed"
	else
		xpText ..= " | No Food"
	end

	if currentLevel >= progress.MaxLevel then
		setLevelUpVisible(standModel, true, player)
		if refs.Upgrade then refs.Upgrade.Text = "Current Level: " .. tostring(currentLevel) end
		if refs.Price then refs.Price.Text = "Max Level" end
		standDebug("updateLevelUpUI maxed player=%s stand=%s currentLevel=%s", player.Name, standName, tostring(currentLevel))
		return
	end

	setLevelUpVisible(standModel, true, player)
	if refs.Upgrade then refs.Upgrade.Text = "Current Level: " .. tostring(currentLevel) end
	if refs.Price then refs.Price.Text = xpText end
	standDebug(
		"updateLevelUpUI visible player=%s stand=%s currentLevel=%s currentXP=%s nextXP=%s",
		player.Name,
		standName,
		tostring(currentLevel),
		tostring(progress.CurrentXP),
		tostring(progress.NextLevelXP)
	)
end

local promptBound = {}
local zoneBound = {}
local levelUpBound = {}
local playerStandList = {}
local touchDebounce = {}
local stealPromptDebounce = {}

local function bindZoneCollect(player, plot, standModel)
	local zone = getHitBoxPart(standModel)
	if not zone then
		return
	end
	if zoneBound[zone] then
		return
	end
	zoneBound[zone] = true

	zone.Touched:Connect(function(hit)
		if not hit or hit.Name ~= "HumanoidRootPart" then
			return
		end

		local char = hit.Parent
		if not char then
			return
		end

		local plr = Players:GetPlayerFromCharacter(char)
		if not plr or plr ~= player then
			return
		end

		local owner = plot:GetAttribute("OwnerUserId")
		if owner ~= plr.UserId then
			return
		end

		touchDebounce[plr] = touchDebounce[plr] or {}
		local now = os.clock()
		local last = touchDebounce[plr][zone]
		if last and (now - last) < 0.35 then
			return
		end
		touchDebounce[plr][zone] = now

		local standName = standModel.Name

		if not dmEnsureStandFolder(plr, standName) then
			return
		end

		local slotState = getStandSlotState(plr, standName)
		if slotState.Visible and not slotState.Usable then
			updateStandMoneyText(plr, standModel)
			return
		end

		local baseToCollect = getPlayerStandIncome(plr, standName)
		if baseToCollect <= 0 then
			updateStandMoneyText(plr, standModel)
			return
		end

		dmSet(plr, "IncomeBrainrots." .. standName .. ".IncomeToCollect", 0)

		local mult = getStandCollectMultiplier(plr, standName)
		local collected = math.floor(baseToCollect * mult)

		DataManager:AddValue(plr, CurrencyUtil.getPrimaryPath(), collected)
		DataManager:AddValue(plr, CurrencyUtil.getTotalPath(), collected)

		if MoneyCollectedRE then
			MoneyCollectedRE:FireClient(plr, standModel, collected)
		end

		updateStandMoneyText(plr, standModel)
	end)
end


local function bindLevelUp(player, plot, standModel)
	local cd = ensureLevelUpClickDetector(standModel)
	if not cd then
		return
	end
	if levelUpBound[cd] then
		return
	end
	levelUpBound[cd] = true

	cd.MaxActivationDistance = 0

	updateLevelUpUI(player, standModel)
end

local function bindStandPrompt(player, plot, standModel)
	local handle = standModel:FindFirstChild("Handle", true)
	if not handle or not handle:IsA("BasePart") then
		standDebug("bindStandPrompt skip player=%s stand=%s reason=no_handle", player.Name, standModel.Name)
		return
	end

	local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		standDebug("bindStandPrompt skip player=%s stand=%s reason=no_prompt", player.Name, standModel.Name)
		return
	end

	if promptBound[prompt] then
		standDebug("bindStandPrompt already_bound player=%s stand=%s", player.Name, standModel.Name)
		return
	end
	promptBound[prompt] = true

	dmEnsureStandFolder(player, standModel.Name)
	standDebug("bindStandPrompt ready player=%s stand=%s savedBrainrot=%s", player.Name, standModel.Name, tostring(getPlayerStandBrainrotName(player, standModel.Name)))
	updateStandMoneyText(player, standModel)
	bindZoneCollect(player, plot, standModel)
	bindLevelUp(player, plot, standModel)
	updateStandPromptTexts(player, standModel)

	prompt.Triggered:Connect(function(plr)
		local ok, err = xpcall(function()
			standDebug("prompt triggered actor=%s standOwner=%s stand=%s", plr and plr.Name or "nil", player.Name, standModel.Name)
			if not plr or not plr:IsA("Player") then
				standDebug("prompt rejected stand=%s reason=invalid_player", standModel.Name)
				return
			end

			local ownerUserId = plot:GetAttribute("OwnerUserId")
			if ownerUserId ~= player.UserId then
				standDebug("prompt rejected actor=%s stand=%s reason=owner_mismatch boundOwner=%s plotOwner=%s", plr.Name, standModel.Name, tostring(player.UserId), tostring(ownerUserId))
				return
			end

			local standName = standModel.Name

			if plr.UserId ~= ownerUserId then
				local brainrotToSteal = getPlayerStandBrainrotName(player, standName)
				if brainrotToSteal == "" then
					standDebug("steal rejected actor=%s stand=%s reason=empty_stand", plr.Name, standName)
					return
				end

				local now = os.clock()
				local last = stealPromptDebounce[plr]
				if last and (now - last) < 1 then
					return
				end
				stealPromptDebounce[plr] = now

				local productId = getStealProductIdForBrainrot(brainrotToSteal)

				plr:SetAttribute("StealOwnerUserId", ownerUserId)
				plr:SetAttribute("StealStandName", standName)
				plr:SetAttribute("StealBrainrotName", brainrotToSteal)
				plr:SetAttribute("StealBrainrotInstanceId", getPlayerStandBrainrotInstanceId(player, standName))
				plr:SetAttribute("StealProductId", productId)
				plr:SetAttribute("StealTime", os.time())

				MarketplaceService:PromptProductPurchase(plr, productId)
				standDebug("steal prompt actor=%s stand=%s brainrot=%s productId=%s", plr.Name, standName, tostring(brainrotToSteal), tostring(productId))
				return
			end

			dmEnsureStandFolder(plr, standName)
			local slotState = getStandSlotState(plr, standName)
			if slotState.Visible and not slotState.Usable then
				updateStandMoneyText(plr, standModel)
				updateLevelUpUI(plr, standModel)
				updateStandPromptTexts(plr, standModel)
				return
			end

			local current = getPlayerStandBrainrotName(plr, standName)
			if current ~= "" then
				local releasedInstanceId, releasedInstance = BrainrotInstanceService.ReleaseStandInstance(plr, standName)
				local storageName = releasedInstance and releasedInstance.StorageName or current
				standDebug("pickup from stand player=%s stand=%s savedName=%s storageName=%s instanceId=%s", plr.Name, standName, tostring(current), tostring(storageName), tostring(releasedInstanceId))
				clearPlacedStandIncome(plr, standName)
				setStandLevel(plr, standName, 1)
				clearStandVisual(standModel)
				updateStandMoneyText(plr, standModel)
				updateLevelUpUI(plr, standModel)
				updateStandPromptTexts(plr, standModel)
				return
			end

			local toolName = getEquippedToolName(plr)
			if not toolName or toolName == "" then
				standDebug("place rejected player=%s stand=%s reason=no_equipped_tool", plr.Name, standName)
				return
			end

			local qty = getInventoryQuantity(plr, toolName)
			if qty < 1 then
				standDebug("place rejected player=%s stand=%s tool=%s reason=no_inventory quantity=%s", plr.Name, standName, tostring(toolName), tostring(qty))
				return
			end

			local placedInstanceId, placedInstance = BrainrotInstanceService.AssignAvailableInstanceToStand(plr, toolName, standName)
			if not placedInstance then
				standDebug("place rejected player=%s stand=%s tool=%s reason=no_instance_available", plr.Name, standName, tostring(toolName))
				return
			end

			getBrainrotLevel(plr, placedInstanceId)
			syncStandLevelFromBrainrot(plr, standName, placedInstanceId)
			standDebug("place accepted player=%s stand=%s tool=%s quantityBefore=%s instanceId=%s", plr.Name, standName, tostring(toolName), tostring(qty), tostring(placedInstanceId))

			spawnStandBrainrot(plr, standModel, handle, placedInstance.StorageName)
			local placedModel = standModel:FindFirstChild("PlacedBrainrot")
			standDebug(
				"place post-spawn player=%s stand=%s tool=%s placedModel=%s incomePerTick=%s instanceId=%s",
				plr.Name,
				standName,
				tostring(toolName),
				tostring(placedModel and placedModel:GetFullName() or "nil"),
				tostring(getIncomeWithLevel(plr, placedInstance.StorageName)),
				tostring(placedInstanceId)
			)
			updateStandMoneyText(plr, standModel)
			updateLevelUpUI(plr, standModel)
			updateStandPromptTexts(plr, standModel)
		end, debug.traceback)

		if not ok then
			standDebug("prompt handler error stand=%s err=%s", standModel.Name, tostring(err))
		end
	end)
end

local function registerStand(player, plot, standModel)
	standDebug("registerStand begin player=%s stand=%s", player.Name, standModel.Name)
	saveTrace(
		"registerStand begin player=%s userId=%s plot=%s stand=%s standPath=%s ownerUserId=%s ownerName=%s",
		player.Name,
		tostring(player.UserId),
		formatInstancePath(plot),
		tostring(standModel.Name),
		formatInstancePath(standModel),
		tostring(plot and plot:GetAttribute("OwnerUserId")),
		tostring(plot and plot:GetAttribute("OwnerName"))
	)
	local list = playerStandList[player]
	if not list then
		list = {}
		playerStandList[player] = list
	end

	for i = 1, #list do
		if list[i] == standModel then
			standDebug("registerStand reuse player=%s stand=%s", player.Name, standModel.Name)
			bindStandPrompt(player, plot, standModel)
			return
		end
	end

	table.insert(list, standModel)

	bindStandPrompt(player, plot, standModel)
	standDebug("registerStand after bindStandPrompt player=%s stand=%s", player.Name, standModel.Name)

	task.spawn(function()
		standDebug("registerStand init-task begin player=%s stand=%s", player.Name, standModel.Name)
		local ok, err = xpcall(function()
			standDebug("registerStand before handle lookup player=%s stand=%s", player.Name, standModel.Name)
			local handle = standModel:FindFirstChild("Handle", true)
			standDebug("registerStand after handle lookup player=%s stand=%s handle=%s", player.Name, standModel.Name, tostring(handle ~= nil))
			if handle and handle:IsA("BasePart") then
				standDebug("registerStand before savedName lookup player=%s stand=%s", player.Name, standModel.Name)
				local name = getPlayerStandBrainrotName(player, standModel.Name)
				local savedInstanceId = getPlayerStandBrainrotInstanceId(player, standModel.Name)
				saveTrace(
					"restoreCheck player=%s userId=%s plot=%s stand=%s savedName=%s savedInstanceId=%s handle=%s",
					player.Name,
					tostring(player.UserId),
					formatInstancePath(plot),
					tostring(standModel.Name),
					tostring(name),
					tostring(savedInstanceId),
					formatInstancePath(handle)
				)
				standDebug("registerStand after savedName lookup player=%s stand=%s savedName=%s", player.Name, standModel.Name, tostring(name))
				if name ~= "" then
					standDebug("registerStand savedBrainrot branch entered player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand restore-begin player=%s stand=%s savedName=%s", player.Name, standModel.Name, tostring(name))
					standDebug("registerStand before ensureStandInstance player=%s stand=%s", player.Name, standModel.Name)
					local restoredInstanceId, restoredInstance = BrainrotInstanceService.EnsureStandInstance(player, standModel.Name, name)
					local persistedName = restoredInstance and restoredInstance.StorageName or name
					saveTrace(
						"restoreLookup player=%s userId=%s stand=%s requestedName=%s restoredInstanceId=%s persistedName=%s",
						player.Name,
						tostring(player.UserId),
						tostring(standModel.Name),
						tostring(name),
						tostring(restoredInstanceId),
						tostring(persistedName)
					)
					standDebug("registerStand after ensureStandInstance player=%s stand=%s instanceId=%s persisted=%s", player.Name, standModel.Name, tostring(restoredInstanceId), tostring(persistedName))
					name = persistedName
					standDebug("registerStand before getBrainrotLevel player=%s stand=%s", player.Name, standModel.Name)
					getBrainrotLevel(player, restoredInstanceId ~= nil and tostring(restoredInstanceId) ~= "" and restoredInstanceId or name)
					standDebug("registerStand after getBrainrotLevel player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand before syncStandLevelFromBrainrot player=%s stand=%s", player.Name, standModel.Name)
					syncStandLevelFromBrainrot(player, standModel.Name, restoredInstanceId ~= nil and tostring(restoredInstanceId) ~= "" and restoredInstanceId or name)
					standDebug("registerStand after syncStandLevelFromBrainrot player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand before spawnStandBrainrot player=%s stand=%s", player.Name, standModel.Name)
					spawnStandBrainrot(player, standModel, handle, name)
					local placedModel = standModel:FindFirstChild("PlacedBrainrot")
					saveTrace(
						"restoreApplied player=%s userId=%s stand=%s savedName=%s restoredInstanceId=%s placedModel=%s placedPivot=%s",
						player.Name,
						tostring(player.UserId),
						tostring(standModel.Name),
						tostring(name),
						tostring(restoredInstanceId),
						formatInstancePath(placedModel),
						formatVector3(placedModel and placedModel:IsA("Model") and placedModel:GetPivot().Position or nil)
					)
					standDebug("registerStand after spawnStandBrainrot player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand before updateStandHover player=%s stand=%s", player.Name, standModel.Name)
					updateStandHover(player, standModel, name)
					standDebug("registerStand after updateStandHover player=%s stand=%s", player.Name, standModel.Name)
					standDebug("registerStand restore-done player=%s stand=%s incomePerTick=%s", player.Name, standModel.Name, tostring(getIncomeWithLevel(player, name)))
				else
					saveTrace(
						"restoreSkipped player=%s userId=%s stand=%s reason=empty_saved_name",
						player.Name,
						tostring(player.UserId),
						tostring(standModel.Name)
					)
					standDebug("registerStand empty branch entered player=%s stand=%s", player.Name, standModel.Name)
					clearPlacedStandIncome(player, standModel.Name)
					setStandLevel(player, standModel.Name, 1)
					clearStandVisual(standModel)
					standDebug("registerStand empty player=%s stand=%s", player.Name, standModel.Name)
				end
			end

			standDebug("registerStand before setMoneyText player=%s stand=%s", player.Name, standModel.Name)
			updateStandMoneyText(player, standModel)
			standDebug("registerStand after setMoneyText player=%s stand=%s", player.Name, standModel.Name)
			standDebug("registerStand before updateLevelUpUI player=%s stand=%s", player.Name, standModel.Name)
			updateLevelUpUI(player, standModel)
			standDebug("registerStand after updateLevelUpUI player=%s stand=%s", player.Name, standModel.Name)
		end, debug.traceback)

		if not ok then
			standDebug("registerStand init-task error player=%s stand=%s err=%s", player.Name, standModel.Name, tostring(err))
		end
	end)
end


local plotScanBound = {} 

local function waitForStandsFolder(plot, timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 20) do
		local stands = plot:FindFirstChild("Stands", true)
		if stands and stands:IsA("Folder") then
			return stands
		end
		task.wait(0.25)
	end
	return nil
end

local function scanAndBindPlot(player, plot)
	standDebug("scanAndBindPlot begin player=%s plot=%s", player and player.Name or "nil", plot and plot:GetFullName() or "nil")
	plotTrace(
		"scanAndBindPlot player=%s userId=%s plot=%s ownerUserId=%s ownerName=%s",
		player and player.Name or "nil",
		tostring(player and player.UserId or "nil"),
		formatInstancePath(plot),
		tostring(plot and plot:GetAttribute("OwnerUserId")),
		tostring(plot and plot:GetAttribute("OwnerName"))
	)
	if not player or not player.Parent then
		standDebug("scanAndBindPlot abort reason=invalid_player")
		saveTrace("scanAndBindPlot skipped player=<nil> reason=invalid_player")
		return
	end
	if not plot or not plot.Parent then
		standDebug("scanAndBindPlot abort player=%s reason=invalid_plot", player.Name)
		saveTrace("scanAndBindPlot skipped player=%s userId=%s reason=invalid_plot", player.Name, tostring(player.UserId))
		return
	end

	if plotScanBound[plot] then
		standDebug("scanAndBindPlot skip player=%s plot=%s reason=already_bound", player.Name, plot:GetFullName())
		saveTrace("scanAndBindPlot skipped player=%s userId=%s plot=%s reason=already_bound", player.Name, tostring(player.UserId), formatInstancePath(plot))
		return
	end
	plotScanBound[plot] = true

	local stands = waitForStandsFolder(plot, 25)
	if not stands then
		standDebug("scanAndBindPlot failed player=%s plot=%s reason=no_stands_folder", player.Name, plot:GetFullName())
		saveTrace(
			"scanAndBindPlot failed player=%s userId=%s plot=%s reason=no_stands_folder",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(plot)
		)
		plotScanBound[plot] = nil
		return
	end
	standDebug("scanAndBindPlot stands_folder player=%s stands=%s", player.Name, stands:GetFullName())

	for _, m in ipairs(stands:GetDescendants()) do
		if m:IsA("Model") then
			local handle = m:FindFirstChild("Handle", true)
			local prompt = handle and handle:IsA("BasePart") and handle:FindFirstChildOfClass("ProximityPrompt") or nil
			standDebug(
				"scanAndBindPlot found_model player=%s stand=%s handle=%s prompt=%s",
				player.Name,
				m.Name,
				tostring(handle ~= nil),
				tostring(prompt ~= nil)
			)
			if prompt then
				registerStand(player, plot, m)
			end
		end
	end

	stands.DescendantAdded:Connect(function(inst)
		if not player.Parent then
			return
		end

		if inst:IsA("ProximityPrompt") then
			local h = inst.Parent
			if h and h:IsA("BasePart") and h.Name == "Handle" then
				local sm = h:FindFirstAncestorOfClass("Model")
				if sm then
					standDebug("scanAndBindPlot descendant_prompt player=%s stand=%s prompt=%s", player.Name, sm.Name, inst:GetFullName())
					registerStand(player, plot, sm)
				end
			end
		end
	end)
end

local function clearBoundStateForStand(standModel)
	if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
		return
	end

	local handle = standModel:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		local prompt = handle:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			promptBound[prompt] = nil
		end
	end

	local hitBox = getHitBoxPart(standModel)
	if hitBox then
		zoneBound[hitBox] = nil
	end

	local levelUpPart = getLevelUpPart(standModel)
	if levelUpPart then
		local clickDetector = levelUpPart:FindFirstChildOfClass("ClickDetector")
		if clickDetector then
			levelUpBound[clickDetector] = nil
		end
	end
end

local function clearPlotScanStateForPlayer(player)
	for plot in pairs(plotScanBound) do
		if not plot or not plot.Parent then
			plotScanBound[plot] = nil
		else
			local ownerUserId = plot:GetAttribute("OwnerUserId")
			local ownerName = plot:GetAttribute("OwnerName")
			if ownerUserId == player.UserId or plot.Name == player.Name or ownerName == player.Name then
				plotScanBound[plot] = nil
			end
		end
	end
end

local function clearPlayerStandRuntime(player)
	local stands = playerStandList[player]
	if stands then
		for i = 1, #stands do
			clearBoundStateForStand(stands[i])
		end
	end

	playerStandList[player] = nil
	ensuredStandFolders[player] = nil
	touchDebounce[player] = nil
	stealPromptDebounce[player] = nil
	clearPlotScanStateForPlayer(player)
end

local function refreshPlayerStandRuntime(player)
	clearPlayerStandRuntime(player)

	local plot = waitForPlot(player, 10)
	if not plot then
		return false, "plot_not_found"
	end

	scanAndBindPlot(player, plot)
	return true, plot
end


Players.PlayerAdded:Connect(function(player)
	standDebug("PlayerAdded player=%s", player.Name)
	task.spawn(function()
		saveTrace("PlayerAdded begin player=%s userId=%s event=restore_begin", player.Name, tostring(player.UserId))
		logSavedShipSnapshot(player, "PlayerAdded")
		resetHugeIncomeOnJoin(player)

		local plot = waitForPlot(player, 25)
		if not plot then
			standDebug("PlayerAdded abort player=%s reason=no_plot", player.Name)
			saveTrace("PlayerAdded restoreSkipped player=%s userId=%s reason=no_plot_owned_by_userid", player.Name, tostring(player.UserId))
			return
		end
		saveTrace(
			"PlayerAdded plotReady player=%s userId=%s plot=%s ownerUserId=%s ownerUserIdType=%s ownerName=%s event=restore_continue",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(plot),
			tostring(plot:GetAttribute("OwnerUserId")),
			typeof(plot:GetAttribute("OwnerUserId")),
			tostring(plot:GetAttribute("OwnerName"))
		)
		scanAndBindPlot(player, plot)
	end)
end)


Players.PlayerRemoving:Connect(function(player)
	clearPlayerStandRuntime(player)
end)

standCommandFunction.OnInvoke = function(action, player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	if action == "clear" then
		clearPlayerStandRuntime(player)
		return true
	end

	if action == "refresh" then
		return refreshPlayerStandRuntime(player)
	end

	return false, "unsupported_action"
end

for _, p in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		standDebug("bootstrap existing_player=%s", p.Name)
		local plot = waitForPlot(p, 5)
		if plot then
			scanAndBindPlot(p, plot)
			resetHugeIncomeOnJoin(p)
		else
			standDebug("bootstrap existing_player=%s reason=no_plot", p.Name)
		end
	end)
end
  
task.spawn(function()
	local zeroIncomeLogged = {}
	while true do
		task.wait(1)

		for plr, stands in pairs(playerStandList) do
			if not plr.Parent then
				playerStandList[plr] = nil
			else
				for i = 1, #stands do
					local standModel = stands[i]
					if standModel and standModel.Parent then
						local standName = standModel.Name
						dmEnsureStandFolder(plr, standName)

						local brainrotName = getPlayerStandBrainrotName(plr, standName)
						if brainrotName ~= "" then
							local inc = getIncomeWithLevel(plr, brainrotName)
							if inc ~= 0 then
								zeroIncomeLogged[plr] = zeroIncomeLogged[plr] or {}
								zeroIncomeLogged[plr][standName] = nil
								dmAdjust(plr, "IncomeBrainrots." .. standName .. ".IncomeToCollect", inc)
							else
								zeroIncomeLogged[plr] = zeroIncomeLogged[plr] or {}
								if zeroIncomeLogged[plr][standName] ~= true then
									zeroIncomeLogged[plr][standName] = true
									standDebug("income zero player=%s stand=%s brainrot=%s", plr.Name, standName, tostring(brainrotName))
								end
							end
						end

						updateStandMoneyText(plr, standModel)
						updateLevelUpUI(plr, standModel)
						updateStandPromptTexts(plr, standModel)
					end
				end
			end
		end
	end
end)
