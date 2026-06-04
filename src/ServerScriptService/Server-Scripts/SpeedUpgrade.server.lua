local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local SpeedUpgrade = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("Configs")
		:WaitForChild("SpeedUpgrade")
)

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local PlayerMovementSpeedService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerMovementSpeedService"))
local SpeedUpgradeLimits = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("SpeedUpgradeLimits"))
local TUTORIAL_COMPLETION_PATH = "HiddenLeaderstats.Tutorial"
local TUTORIAL_SPEED_TOP_UP_GRANTED_PATH = "HiddenLeaderstats.TutorialSpeedTopUpGranted"
local purchaseLocks = {}

local remote = ReplicatedStorage:FindFirstChild("BuySpeedUpgrade")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "BuySpeedUpgrade"
	remote.Parent = ReplicatedStorage
end

local function computeCost(cfg, speedVal, stepCount)
	local starter = cfg.Starter_Price or 0
	local mult = cfg.Price_Mult or 1
	local addSpeed = cfg.AddSpeed or 1
	if typeof(stepCount) == "number" then
		addSpeed = stepCount
	end

	local s = tonumber(speedVal) or 1
	if s < 1 then
		s = 1
	end

	local level = math.max(s - 1, 0)

	local function priceForLevel(lv)
		return starter * (mult ^ lv)
	end

	local total = 0
	for i = 0, addSpeed - 1 do
		total += priceForLevel(level + i)
	end

	return math.floor(total + 0.5)
end

local function isTutorialIncomplete(player)
	local completed, reason = DataManager:TryGetValue(player, TUTORIAL_COMPLETION_PATH)
	if reason == nil and typeof(completed) == "boolean" then
		return completed ~= true
	end

	local hidden = player:FindFirstChild("HiddenLeaderstats")
	local tutorial = hidden and hidden:FindFirstChild("Tutorial")
	return not (tutorial and tutorial:IsA("BoolValue") and tutorial.Value == true)
end

local function applyTutorialSpeedRecovery(player, upgradeIndex, moneyPath, money, cost, speedVal)
	if upgradeIndex ~= 1 then
		return false, 0
	end
	if not isTutorialIncomplete(player) or (tonumber(speedVal) or 1) > 1 then
		return false, 0
	end

	local granted, reason = DataManager:TryGetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH)
	if reason ~= nil or granted == true then
		return false, 0
	end

	local flagged = DataManager:TrySetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, true)
	if flagged ~= true then
		return false, 0
	end

	local shortfall = math.max(0, cost - money)
	if shortfall <= 0 then
		return true, 0
	end

	local added = DataManager:TryAddValue(player, moneyPath, shortfall, { ApplyTitleBuff = false })
	if added ~= true then
		DataManager:TrySetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, false)
		return false, 0
	end

	return true, shortfall
end

local function rollbackTutorialSpeedRecovery(player, moneyPath, tutorialRecoveryAmount)
	if tutorialRecoveryAmount > 0 then
		local rolledBack = DataManager:TryAddValue(player, moneyPath, -tutorialRecoveryAmount)
		if rolledBack ~= true then
			warn(string.format(
				"[BuySpeedUpgrade] failed to roll back tutorial top-up player=%s amount=%s",
				player.Name,
				tostring(tutorialRecoveryAmount)
			))
		end
	end
	DataManager:TrySetValue(player, TUTORIAL_SPEED_TOP_UP_GRANTED_PATH, false)
end

local function handleSpeedUpgrade(player, upgradeName)
	if typeof(upgradeName) ~= "string" then
		return
	end
	local idx = tonumber(upgradeName)
	if not idx then
		return
	end

	local cfg = SpeedUpgrade[idx]
	if not cfg then
		return
	end

	local addSpeed = cfg.AddSpeed or 0
	if typeof(addSpeed) ~= "number" then
		return
	end

	local speedVal = SpeedUpgradeLimits.GetCurrentSpeed(DataManager, player)
	local effectiveAddSpeed = SpeedUpgradeLimits.SanitizeSpeedIncrease(addSpeed)
	if effectiveAddSpeed <= 0 then
		return
	end
	local cost = computeCost(cfg, speedVal, effectiveAddSpeed)

	local moneyPath = CurrencyUtil.getPrimaryPath()
	local money = DataManager:GetValue(player, moneyPath)

	if typeof(money) ~= "number" then
		local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
		money = (moneyValue and moneyValue.Value) or 0
	end

	local usedTutorialRecovery = false
	local tutorialRecoveryAmount = 0
	if money < cost then
		local recovered, recoveryAmount = applyTutorialSpeedRecovery(player, idx, moneyPath, money, cost, speedVal)
		if not recovered then
			return
		end
		usedTutorialRecovery = true
		tutorialRecoveryAmount = recoveryAmount
	end

	local speedApplied, appliedIncrease, newSpeed, speedReason =
		SpeedUpgradeLimits.ApplySpeedIncrease(DataManager, player, effectiveAddSpeed)
	if speedApplied ~= true then
		if usedTutorialRecovery then
			rollbackTutorialSpeedRecovery(player, moneyPath, tutorialRecoveryAmount)
		end
		warn(string.format(
			"[BuySpeedUpgrade] speed update failed player=%s reason=%s",
			player.Name,
			tostring(speedReason)
		))
		return
	end

	local chargeMoney = DataManager:GetValue(player, moneyPath)
	if typeof(chargeMoney) ~= "number" then
		local moneyValue = CurrencyUtil.findPrimaryValueObject(player)
		chargeMoney = (moneyValue and moneyValue.Value) or 0
	end
	if chargeMoney < cost then
		local rollbackOk, rollbackReason = SpeedUpgradeLimits.RollbackSpeedIncrease(DataManager, player, appliedIncrease)
		if usedTutorialRecovery then
			rollbackTutorialSpeedRecovery(player, moneyPath, tutorialRecoveryAmount)
		end
		warn(string.format(
			"[BuySpeedUpgrade] balance changed before charge player=%s speedRollback=%s reason=%s",
			player.Name,
			tostring(rollbackOk),
			tostring(rollbackReason or "insufficient_balance_before_charge")
		))
		PlayerMovementSpeedService.ApplyPlayerSpeed(player, "speed_upgrade_balance_rollback")
		return
	end

	local newBalance = DataManager:AdjustValue(player, moneyPath, -cost)
	if typeof(newBalance) ~= "number" then
		local rollbackOk, rollbackReason = SpeedUpgradeLimits.RollbackSpeedIncrease(DataManager, player, appliedIncrease)
		if usedTutorialRecovery then
			rollbackTutorialSpeedRecovery(player, moneyPath, tutorialRecoveryAmount)
		end
		warn(string.format(
			"[BuySpeedUpgrade] currency charge failed after speed update player=%s speedRollback=%s reason=%s",
			player.Name,
			tostring(rollbackOk),
			tostring(rollbackReason or "charge_failed")
		))
		PlayerMovementSpeedService.ApplyPlayerSpeed(player, "speed_upgrade_charge_rollback")
		return
	end

	local settingsResult, settingsReason = PlayerMovementSpeedService.NormalizePlayerSpeedSettings(
		player,
		DataManager,
		"speed_upgrade_purchase"
	)
	if not settingsResult then
		warn(string.format(
			"[BuySpeedUpgrade] speed settings normalize failed player=%s newSpeed=%s reason=%s",
			player.Name,
			tostring(newSpeed),
			tostring(settingsReason)
		))
	end
	PlayerMovementSpeedService.ApplyPlayerSpeed(player, "speed_upgrade_purchase")
end

remote.OnServerEvent:Connect(function(player, upgradeName)
	-- Security: shared guard and local lock stop malformed/spammed upgrade requests before currency mutation.
	if not RemoteGuard.Check(player, "BuySpeedUpgrade", { upgradeName }, {
		Cooldown = 0.2,
		Args = {
			{ Type = "string", MaxLength = 8 },
		},
	}) then
		return
	end

	if purchaseLocks[player] then
		return
	end
	purchaseLocks[player] = true

	local ok, err = pcall(handleSpeedUpgrade, player, upgradeName)
	purchaseLocks[player] = nil
	if not ok then
		warn(string.format("[BuySpeedUpgrade] failed player=%s error=%s", player.Name, tostring(err)))
	end
end)

Players.PlayerRemoving:Connect(function(player)
	purchaseLocks[player] = nil
end)
