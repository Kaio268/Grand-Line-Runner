local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local GrandLineRushVerticalSliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
local cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local remotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local remote = remotesFolder:WaitForChild("PlotUpgradeRemote")
local upgradeResultRemote = remotesFolder:FindFirstChild("ShipUpgradeResultRemote")
if not upgradeResultRemote then
	upgradeResultRemote = Instance.new("RemoteEvent")
	upgradeResultRemote.Name = "ShipUpgradeResultRemote"
	upgradeResultRemote.Parent = remotesFolder
end

local busy = {}
local PLOT_UPGRADE_PATH = "HiddenLeaderstats.PlotUpgrade"
local MATERIAL_PATHS = {
	Timber = {
		Primary = "Materials.Timber",
		Aliases = { "Materials.CommonShipMaterial" },
	},
	Iron = {
		Primary = "Materials.Iron",
		Aliases = { "Materials.RareShipMaterial" },
	},
	AncientTimber = {
		Primary = "Materials.AncientTimber",
		Aliases = {},
	},
}

local function splitPath(path)
	local segments = string.split(tostring(path), ".")
	if segments[1] == "Data" then
		table.remove(segments, 1)
	end
	return segments
end

local function setNestedValue(root, path, value)
	local segments = splitPath(path)
	local pointer = root

	for index = 1, #segments - 1 do
		local key = segments[index]
		if typeof(pointer[key]) ~= "table" then
			pointer[key] = {}
		end
		pointer = pointer[key]
	end

	pointer[segments[#segments]] = value
	return segments
end

local function applyMutations(player, mutations)
	local profile = DataManager:TryGetProfile(player)
	local replica = DataManager:TryGetReplica(player)
	if not (profile and replica) then
		return false
	end

	local pathTables = {}
	for index, mutation in ipairs(mutations) do
		pathTables[index] = setNestedValue(profile.Data, mutation.Path, mutation.Value)
	end

	for index, mutation in ipairs(mutations) do
		replica:Set(pathTables[index], mutation.Value)
	end

	DataManager:UpdateData(player)
	return true
end

local function getCurrentUpgrade(player, path)
	local stats = player:FindFirstChild("HiddenLeaderstats")
	if stats then
		local valueObject = stats:FindFirstChild("PlotUpgrade")
		if valueObject and valueObject:IsA("NumberValue") then
			return cfg.ClampLevel(valueObject.Value)
		end
	end

	local storedUpgrade = DataManager:GetValue(player, path)
	if typeof(storedUpgrade) == "number" then
		return cfg.ClampLevel(storedUpgrade)
	end

	return 0
end

local function getMoney(player)
	local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
	if moneyValue then
		return math.max(0, tonumber(moneyValue.Value) or 0)
	end

	local storedBalance = DataManager:GetValue(player, CurrencyUtil.getPrimaryPath())
	if typeof(storedBalance) == "number" then
		return math.max(0, storedBalance)
	end

	return 0
end

local function getMaterialAmount(player, materialKey)
	local pathInfo = MATERIAL_PATHS[materialKey]
	local materialFolder = player:FindFirstChild("Materials")
	local bestValue = 0

	local function considerName(name)
		if materialFolder then
			local valueObject = materialFolder:FindFirstChild(name)
			if valueObject and valueObject:IsA("NumberValue") then
				bestValue = math.max(bestValue, math.max(0, tonumber(valueObject.Value) or 0))
			end
		end

		local storedValue = DataManager:GetValue(player, "Materials." .. name)
		if typeof(storedValue) == "number" then
			bestValue = math.max(bestValue, math.max(0, storedValue))
		end
	end

	if pathInfo then
		considerName(string.match(pathInfo.Primary, "Materials%.(.+)$"))
		for _, aliasPath in ipairs(pathInfo.Aliases) do
			considerName(string.match(aliasPath, "Materials%.(.+)$"))
		end
	else
		considerName(materialKey)
	end

	return bestValue
end

local function addMaterialMutations(mutations, materialKey, remainingAmount)
	local pathInfo = MATERIAL_PATHS[materialKey]
	if not pathInfo then
		mutations[#mutations + 1] = {
			Path = "Materials." .. materialKey,
			Value = remainingAmount,
		}
		return
	end

	mutations[#mutations + 1] = {
		Path = pathInfo.Primary,
		Value = remainingAmount,
	}

	for _, aliasPath in ipairs(pathInfo.Aliases) do
		mutations[#mutations + 1] = {
			Path = aliasPath,
			Value = remainingAmount,
		}
	end
end

local function fireUpgradeResult(player, newLevel)
	if not player or player.Parent ~= Players then
		return
	end

	upgradeResultRemote:FireClient(player, {
		Level = cfg.ClampLevel(newLevel),
		Description = cfg.GetLevelUnlockDescription(newLevel),
		IsMaxLevel = cfg.IsMaxLevel(newLevel),
	})
end

remote.OnServerEvent:Connect(function(player)
	if busy[player] then
		return
	end
	busy[player] = true

	local current = getCurrentUpgrade(player, PLOT_UPGRADE_PATH)
	if cfg.IsMaxLevel(current) then
		busy[player] = nil
		return
	end

	local requirement = cfg.GetRequirementForLevel(current)
	if typeof(requirement) ~= "table" then
		busy[player] = nil
		return
	end

	local currentMoney = getMoney(player)
	local doubloonCost = math.max(0, math.floor(tonumber(requirement.Doubloons) or 0))
	if currentMoney < doubloonCost then
		busy[player] = nil
		return
	end

	local materialBalances = {}
	for _, materialKey in ipairs(cfg.MaterialOrder) do
		local requiredAmount = cfg.GetMaterialCost(requirement, materialKey)
		local currentAmount = getMaterialAmount(player, materialKey)
		materialBalances[materialKey] = currentAmount

		if currentAmount < requiredAmount then
			busy[player] = nil
			return
		end
	end

	local newLevel = current + 1
	local mutations = {
		{
			Path = CurrencyUtil.getPrimaryPath(),
			Value = currentMoney - doubloonCost,
		},
		{
			Path = PLOT_UPGRADE_PATH,
			Value = newLevel,
		},
	}

	for _, materialKey in ipairs(cfg.MaterialOrder) do
		local requiredAmount = cfg.GetMaterialCost(requirement, materialKey)
		if requiredAmount > 0 then
			local remainingAmount = materialBalances[materialKey] - requiredAmount
			addMaterialMutations(mutations, materialKey, remainingAmount)
		end
	end

	if not applyMutations(player, mutations) then
		busy[player] = nil
		return
	end

	GrandLineRushVerticalSliceService.PushState(player)
	fireUpgradeResult(player, newLevel)
	busy[player] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
end)
