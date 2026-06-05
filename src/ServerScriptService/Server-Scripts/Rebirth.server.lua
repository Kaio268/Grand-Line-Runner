local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local dmModule = ServerScriptService:FindFirstChild("DataManager", true)
if not dmModule then
	error("DataManager module not found in ServerScriptService")
end
local DataManager = require(dmModule)
local ShipResetService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ShipResetService"))
local TutorialService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TutorialService"))

local Rebirths = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Rebirths"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local RebirthRemote = ReplicatedStorage:FindFirstChild("RebirthRemote")
if not RebirthRemote then
	RebirthRemote = Instance.new("RemoteEvent")
	RebirthRemote.Name = "RebirthRemote"
	RebirthRemote.Parent = ReplicatedStorage
end

local serverDebounce = {}

local function getNumber(player, path)
	local v = DataManager:GetValue(player, path)
	if typeof(v) ~= "number" then
		return 0
	end
	return v
end

local function setNumber(player, path, target)
	local cur = getNumber(player, path)
	local delta = target - cur
	if delta ~= 0 then
		local result, reason = DataManager:AdjustValue(player, path, delta)
		if result == nil then
			return false, reason or "adjust_failed"
		end
	end

	return true
end

local function getShipLevel(player)
	local hiddenStats = player:FindFirstChild("HiddenLeaderstats")
	if hiddenStats then
		local valueObject = hiddenStats:FindFirstChild("PlotUpgrade")
		if valueObject and valueObject:IsA("NumberValue") then
			return math.max(0, math.floor(tonumber(valueObject.Value) or 0))
		end
	end

	return math.max(0, math.floor(tonumber(DataManager:GetValue(player, "HiddenLeaderstats.PlotUpgrade")) or 0))
end

RebirthRemote.OnServerEvent:Connect(function(player)
	if serverDebounce[player] then return end
	serverDebounce[player] = true

	local rebirthsCount = getNumber(player, "leaderstats.Rebirths")
	local moneyPath = CurrencyUtil.getPrimaryPath()
	local money = getNumber(player, moneyPath)
	local shipLevel = getShipLevel(player)
	local canRebirth = Rebirths.CanRebirth(rebirthsCount, shipLevel, money)
	if not canRebirth then
		serverDebounce[player] = nil
		return
	end

	local rebirthsAfterReset = nil
	local resetOk = ShipResetService.ResetPlayerShip(player, {
		Reason = "rebirth",
		MutateProfile = function()
			local moneyOk, moneyReason = setNumber(player, moneyPath, 0)
			if not moneyOk then
				return false, moneyReason
			end

			local rebirthsAfter, rebirthReason = DataManager:AdjustValue(player, "leaderstats.Rebirths", 1)
			if rebirthsAfter == nil then
				return false, rebirthReason or "failed_to_increment_rebirths"
			end

			rebirthsAfterReset = rebirthsAfter
			return true
		end,
	})
	if resetOk == false then
		serverDebounce[player] = nil
		return
	end

	if rebirthsCount == 0 and rebirthsAfterReset == 1 then
		TutorialService.Enqueue(player, "RebirthInfo", {
			Source = "FirstRebirth",
			RebirthsBefore = rebirthsCount,
			RebirthsAfter = rebirthsAfterReset,
		}, nil)
	end

	serverDebounce[player] = nil
end)
