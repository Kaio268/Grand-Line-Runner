local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local GrandLineRushVerticalSliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
local cfg = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local PLOT_UPGRADE_DEBUG = true
local PLOT_UPGRADE_LOG_PREFIX = "[PlotUpgradeServer]"

local function formatDebugMessage(message, ...)
	if select("#", ...) > 0 then
		local ok, formatted = pcall(string.format, tostring(message), ...)
		if ok then
			return formatted
		end
	end

	return tostring(message)
end

local function plotUpgradeLog(message, ...)
	if PLOT_UPGRADE_DEBUG ~= true then
		return
	end

	print(PLOT_UPGRADE_LOG_PREFIX, formatDebugMessage(message, ...))
end

local function plotUpgradeWarn(message, ...)
	warn(PLOT_UPGRADE_LOG_PREFIX, formatDebugMessage(message, ...))
end

local function getOrCreateRemotesFolder()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
	plotUpgradeWarn("Created missing ReplicatedStorage.Remotes folder.")
	return folder
end

local function getOrCreateRemoteEvent(parent, remoteName)
	local remoteEvent = parent:FindFirstChild(remoteName)
	if remoteEvent and remoteEvent:IsA("RemoteEvent") then
		return remoteEvent
	end

	if remoteEvent then
		remoteEvent:Destroy()
	end

	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = remoteName
	remoteEvent.Parent = parent
	plotUpgradeWarn("Created missing remote %s.", remoteName)
	return remoteEvent
end

local remotesFolder = getOrCreateRemotesFolder()
local remote = getOrCreateRemoteEvent(remotesFolder, "PlotUpgradeRemote")
local upgradeResultRemote = getOrCreateRemoteEvent(remotesFolder, "ShipUpgradeResultRemote")

plotUpgradeLog(
	"Initialized remotes plot=%s shipUpgrade=%s",
	remote:GetFullName(),
	upgradeResultRemote:GetFullName()
)

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

local function getRebirthCount(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		local rebirthValue = leaderstats:FindFirstChild("Rebirths")
		if rebirthValue and rebirthValue:IsA("NumberValue") then
			return math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
		end
	end

	local storedValue = DataManager:GetValue(player, "leaderstats.Rebirths")
	if typeof(storedValue) == "number" then
		return math.max(0, math.floor(storedValue))
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

local function fireUpgradeResult(player, payload)
	if not player or player.Parent ~= Players then
		return
	end

	plotUpgradeLog(
		"FireClient player=%s success=%s level=%s error=%s",
		player.Name,
		tostring(payload and payload.Success),
		tostring(payload and payload.Level),
		tostring(payload and payload.ErrorCode)
	)
	upgradeResultRemote:FireClient(player, payload)
end

local function fireUpgradeSuccess(player, newLevel)
	fireUpgradeResult(player, {
		Success = true,
		Level = cfg.ClampLevel(newLevel),
		Description = cfg.GetLevelUnlockDescription(newLevel),
		IsMaxLevel = cfg.IsMaxLevel(newLevel),
	})
end

local function fireUpgradeFailure(player, targetLevel, requiredRebirths, currentRebirths)
	fireUpgradeResult(player, {
		Success = false,
		IsError = true,
		ErrorCode = "rebirth_required",
		Title = string.format("Ship Lv %d Locked", cfg.ClampLevel(targetLevel)),
		AccentText = "Rebirth Required",
		Lines = {
			string.format(
				"Ship Lv %d requires %d rebirth%s.",
				cfg.ClampLevel(targetLevel),
				requiredRebirths,
				requiredRebirths == 1 and "" or "s"
			),
			string.format("Current rebirths: %d", currentRebirths),
		},
		Level = cfg.ClampLevel(targetLevel),
		RequiredRebirths = requiredRebirths,
		CurrentRebirths = currentRebirths,
	})
end

remote.OnServerEvent:Connect(function(player)
	plotUpgradeLog("Upgrade requested by %s", player and player.Name or "unknown")

	if busy[player] then
		plotUpgradeWarn("Ignoring duplicate upgrade request for %s while busy.", player.Name)
		return
	end
	busy[player] = true

	local current = getCurrentUpgrade(player, PLOT_UPGRADE_PATH)
	if cfg.IsMaxLevel(current) then
		plotUpgradeLog("Player %s is already at max ship level %s.", player.Name, tostring(current))
		busy[player] = nil
		return
	end

	local requirement = cfg.GetRequirementForLevel(current)
	if typeof(requirement) ~= "table" then
		plotUpgradeWarn("Missing requirement table for player=%s currentLevel=%s.", player.Name, tostring(current))
		busy[player] = nil
		return
	end

	local targetLevel = cfg.ClampLevel(tonumber(requirement.TargetLevel) or (current + 1))
	local currentRebirths = getRebirthCount(player)
	local requiredRebirths = math.max(0, math.floor(tonumber(requirement.Rebirths) or 0))
	if currentRebirths < requiredRebirths then
		plotUpgradeLog(
			"Rebirth requirement failed player=%s current=%d required=%d",
			player.Name,
			currentRebirths,
			requiredRebirths
		)
		fireUpgradeFailure(player, targetLevel, requiredRebirths, currentRebirths)
		busy[player] = nil
		return
	end

	local currentMoney = getMoney(player)
	local doubloonCost = math.max(0, math.floor(tonumber(requirement.Doubloons) or 0))
	if currentMoney < doubloonCost then
		plotUpgradeLog(
			"Doubloon requirement failed player=%s balance=%d cost=%d",
			player.Name,
			currentMoney,
			doubloonCost
		)
		busy[player] = nil
		return
	end

	local materialBalances = {}
	for _, materialKey in ipairs(cfg.MaterialOrder) do
		local requiredAmount = cfg.GetMaterialCost(requirement, materialKey)
		local currentAmount = getMaterialAmount(player, materialKey)
		materialBalances[materialKey] = currentAmount

		if currentAmount < requiredAmount then
			plotUpgradeLog(
				"Material requirement failed player=%s material=%s current=%d required=%d",
				player.Name,
				materialKey,
				currentAmount,
				requiredAmount
			)
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
		plotUpgradeWarn("Failed to apply plot upgrade mutations for %s.", player.Name)
		busy[player] = nil
		return
	end

	GrandLineRushVerticalSliceService.PushState(player)
	plotUpgradeLog("Upgrade succeeded player=%s newLevel=%d", player.Name, newLevel)
	fireUpgradeSuccess(player, newLevel)
	busy[player] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
end)
