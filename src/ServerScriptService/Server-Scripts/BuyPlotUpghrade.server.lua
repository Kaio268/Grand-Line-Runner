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

local function getUpgradePath(player: Player)
	return PLOT_UPGRADE_PATH
end

local function splitPath(path: string): { string }
	local segments = string.split(tostring(path), ".")
	if segments[1] == "Data" then
		table.remove(segments, 1)
	end
	return segments
end

local function setNestedValue(root, path: string, value)
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

local function applyMutations(player: Player, mutations)
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

local function getCurrentUpgrade(player: Player, path: string)
	local stats = player:FindFirstChild("HiddenLeaderstats")
	if stats then
		local v = stats:FindFirstChild("PlotUpgrade")
		if v and v:IsA("NumberValue") then
			return cfg.ClampLevel(v.Value)
		end
	end

	local dm = DataManager:GetValue(player, path)
	if typeof(dm) == "number" then
		return cfg.ClampLevel(dm)
	end

	return 0
end

local function getMoney(player: Player)
	local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
	if moneyValue then
		return math.max(0, tonumber(moneyValue.Value) or 0)
	end

	local dm = DataManager:GetValue(player, CurrencyUtil.getPrimaryPath())
	if typeof(dm) == "number" then
		return math.max(0, dm)
	end

	return 0
end

local function getMaterialAmount(player: Player, materialKey: string)
	local materialFolder = player:FindFirstChild("Materials")
	if materialFolder then
		local valueObject = materialFolder:FindFirstChild(materialKey)
		if valueObject and valueObject:IsA("NumberValue") then
			return math.max(0, tonumber(valueObject.Value) or 0)
		end
	end

	local dm = DataManager:GetValue(player, "Materials." .. materialKey)
	if typeof(dm) == "number" then
		return math.max(0, dm)
	end

	return 0
end

local function fireUpgradeResult(player: Player, newLevel: number)
	if not player or player.Parent ~= Players then
		return
	end

	upgradeResultRemote:FireClient(player, {
		Level = cfg.ClampLevel(newLevel),
		Description = cfg.GetLevelUnlockDescription(newLevel),
		IsMaxLevel = cfg.IsMaxLevel(newLevel),
	})
end

remote.OnServerEvent:Connect(function(player: Player)
	if busy[player] then
		return
	end
	busy[player] = true

	local upPath = getUpgradePath(player)
	local current = getCurrentUpgrade(player, upPath)
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

	local mutations = {
		{
			Path = CurrencyUtil.getPrimaryPath(),
			Value = currentMoney - doubloonCost,
		},
		{
			Path = upPath,
			Value = current + 1,
		},
	}

	for _, materialKey in ipairs(cfg.MaterialOrder) do
		local requiredAmount = cfg.GetMaterialCost(requirement, materialKey)
		if requiredAmount > 0 then
			local remaining = materialBalances[materialKey] - requiredAmount
			mutations[#mutations + 1] = {
				Path = "Materials." .. materialKey,
				Value = remaining,
			}
		end
	end

	local timberAfter = materialBalances.Timber or getMaterialAmount(player, "Timber")
	local ironAfter = materialBalances.Iron or getMaterialAmount(player, "Iron")
	for _, mutation in ipairs(mutations) do
		if mutation.Path == "Materials.Timber" then
			timberAfter = mutation.Value
		elseif mutation.Path == "Materials.Iron" then
			ironAfter = mutation.Value
		end
	end

	mutations[#mutations + 1] = {
		Path = "Materials.CommonShipMaterial",
		Value = timberAfter,
	}
	mutations[#mutations + 1] = {
		Path = "Materials.RareShipMaterial",
		Value = ironAfter,
	}

	local newLevel = current + 1
	local applied = applyMutations(player, mutations)
	if not applied then
		busy[player] = nil
		return
	end

	GrandLineRushVerticalSliceService.PushState(player)
	fireUpgradeResult(player, newLevel)
	busy[player] = nil
end)

Players.PlayerRemoving:Connect(function(p)
	busy[p] = nil
end)
