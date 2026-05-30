local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local CrewSlotAssignmentReconciler = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewSlotAssignmentReconciler"))
local GrandLineRushVerticalSliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
local ShipRuntimeService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ShipRuntimeService"))
local TitleProgressService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TitleProgressService"))
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
local RESET_REFRESH_WAIT_TIMEOUT_SECONDS = 8
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

local function fireUpgradeFailure(player, errorCode, title, accentText, lines, level, message, isError, extra)
	local payload = {
		Success = false,
		IsError = if isError == nil then true else isError,
		ErrorCode = tostring(errorCode or "upgrade_failed"),
		Title = tostring(title or "Ship Upgrade Failed"),
		AccentText = tostring(accentText or "Try Again"),
		Lines = if typeof(lines) == "table" then lines else { tostring(message or "Unable to upgrade your ship right now.") },
		Level = cfg.ClampLevel(level or 0),
		Message = tostring(message or (typeof(lines) == "table" and lines[1]) or "Unable to upgrade your ship right now."),
	}

	if typeof(extra) == "table" then
		for key, value in pairs(extra) do
			payload[key] = value
		end
	end

	fireUpgradeResult(player, payload)
end

local function fireRebirthUpgradeFailure(player, targetLevel, requiredRebirths, currentRebirths)
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

local function getRefreshReason(reason, details)
	if typeof(details) == "table" and details.Reason ~= nil then
		return tostring(details.Reason)
	end

	return tostring(reason or "unknown_error")
end

local function refreshShipAfterUpgrade(player)
	local refreshOk, refreshSuccess, refreshReason, refreshDetails = xpcall(function()
		return ShipRuntimeService.RefreshPlayerShip(player)
	end, debug.traceback)

	if not refreshOk then
		return false, "unknown_error", {
			Reason = "unknown_error",
			Error = tostring(refreshSuccess),
		}
	end

	if refreshSuccess == true then
		return true, refreshReason, refreshDetails
	end

	local reason = getRefreshReason(refreshReason, refreshDetails)
	local retryable = typeof(refreshDetails) == "table" and refreshDetails.Retryable == true
	if reason ~= "reset_in_progress" and retryable ~= true then
		return false, reason, refreshDetails
	end

	local resetComplete, resetReason = CrewSlotAssignmentReconciler.WaitForResetToComplete(
		player,
		RESET_REFRESH_WAIT_TIMEOUT_SECONDS
	)
	if resetComplete ~= true then
		return false, "reset_wait_failed", {
			Reason = "reset_wait_failed",
			ResetReason = tostring(resetReason),
			OriginalReason = reason,
		}
	end

	local retryOk, retrySuccess, retryReason, retryDetails = xpcall(function()
		return ShipRuntimeService.RefreshPlayerShip(player, {
			Reason = "ship_upgrade_after_reset_retry",
		})
	end, debug.traceback)

	if not retryOk then
		return false, "unknown_error", {
			Reason = "unknown_error",
			Error = tostring(retrySuccess),
			OriginalReason = reason,
		}
	end

	if retrySuccess == true then
		return true, retryReason, retryDetails
	end

	return false, getRefreshReason(retryReason, retryDetails), retryDetails
end

local function processUpgradePurchase(player)
	local current = getCurrentUpgrade(player, PLOT_UPGRADE_PATH)
	if cfg.IsMaxLevel(current) then
		fireUpgradeFailure(player, "max_level", "Ship Already Maxed", "Max Level", {
			"Your ship progression is already fully upgraded.",
		}, current, "Your ship progression is already fully upgraded.", false)
		return false
	end

	local requirement = cfg.GetRequirementForLevel(current)
	if typeof(requirement) ~= "table" then
		fireUpgradeFailure(player, "missing_requirement", "Ship Upgrade Unavailable", "Requirement Missing", {
			"The next ship upgrade requirement could not be loaded.",
		}, current, "The next ship upgrade requirement could not be loaded.")
		return false
	end

	local targetLevel = cfg.ClampLevel(tonumber(requirement.TargetLevel) or (current + 1))
	local currentRebirths = getRebirthCount(player)
	local requiredRebirths = math.max(0, math.floor(tonumber(requirement.Rebirths) or 0))
	if currentRebirths < requiredRebirths then
		fireRebirthUpgradeFailure(player, targetLevel, requiredRebirths, currentRebirths)
		return false
	end

	local currentMoney = getMoney(player)
	local beliCost = math.max(0, math.floor(tonumber(requirement.Beli) or 0))
	if currentMoney < beliCost then
		fireUpgradeFailure(player, "not_enough_beli", "Need More " .. CurrencyUtil.getDisplayName(), "Requirement Not Met", {
			string.format("Required: %s.", CurrencyUtil.formatCurrency(beliCost)),
			string.format("Current: %s.", CurrencyUtil.formatCurrency(currentMoney)),
		}, current, "Not enough " .. CurrencyUtil.getDisplayName() .. ".")
		return false
	end

	local materialBalances = {}
	for _, materialKey in ipairs(cfg.MaterialOrder) do
		local requiredAmount = cfg.GetMaterialCost(requirement, materialKey)
		local currentAmount = getMaterialAmount(player, materialKey)
		materialBalances[materialKey] = currentAmount

		if currentAmount < requiredAmount then
			local displayName = tostring(cfg.MaterialDisplayNames[materialKey] or materialKey)
			fireUpgradeFailure(player, "not_enough_" .. string.lower(tostring(materialKey)), "Need More " .. displayName, "Requirement Not Met", {
				string.format("Required: %s %s.", CurrencyUtil.formatCount(requiredAmount), displayName),
				string.format("Current: %s %s.", CurrencyUtil.formatCount(currentAmount), displayName),
			}, current, "Not enough " .. displayName .. ".")
			return false
		end
	end

	local newLevel = current + 1
	local mutations = {
		{
			Path = CurrencyUtil.getPrimaryPath(),
			Value = currentMoney - beliCost,
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
		fireUpgradeFailure(player, "data_not_ready", "Ship Upgrade Failed", "Data Not Ready", {
			"Your save data was not ready for this upgrade.",
			"Please try again in a moment.",
		}, current, "Your save data was not ready for this upgrade.")
		return false
	end

	local pushOk, pushErr = pcall(function()
		GrandLineRushVerticalSliceService.PushState(player)
	end)
	if not pushOk then
		warn(("[BuyPlotUpgrade] PushState failed for %s after ship upgrade to level %d: %s"):format(
			player.Name,
			newLevel,
			tostring(pushErr)
		))
	end

	local refreshSuccess, refreshReason, refreshDetails = refreshShipAfterUpgrade(player)
	if refreshSuccess ~= true then
		local detailReason = getRefreshReason(refreshReason, refreshDetails)
		warn(("[BuyPlotUpgrade] Ship refresh failed for %s after upgrade to level %d: %s"):format(
			player.Name,
			newLevel,
			detailReason
		))
		fireUpgradeFailure(player, "refresh_failed", "Ship Upgrade Saved", "Refresh Failed", {
			"Your upgrade was saved, but the active ship could not refresh.",
			"Reason: " .. detailReason,
			"Please try again or rejoin if the ship does not update.",
		}, newLevel, "Ship upgrade saved, but refresh failed.", true, {
			RefreshReason = detailReason,
			RefreshDetails = refreshDetails,
		})
		return false
	end

	fireUpgradeSuccess(player, newLevel)
	TitleProgressService.RecordShipUpgrade(player, newLevel)
	return true
end

remote.OnServerEvent:Connect(function(player)
	if busy[player] then
		fireUpgradeFailure(player, "already_processing", "Ship Upgrade Pending", "Please Wait", {
			"A ship upgrade is already being processed.",
		}, getCurrentUpgrade(player, PLOT_UPGRADE_PATH), "A ship upgrade is already being processed.", false)
		return
	end
	busy[player] = true

	local ok, err = xpcall(function()
		processUpgradePurchase(player)
	end, debug.traceback)

	if not ok then
		warn(("[BuyPlotUpgrade] Unexpected ship upgrade error for %s: %s"):format(player.Name, tostring(err)))
		fireUpgradeFailure(player, "server_error", "Ship Upgrade Failed", "Server Error", {
			"Something went wrong while upgrading your ship.",
			"Please try again in a moment.",
		}, getCurrentUpgrade(player, PLOT_UPGRADE_PATH), "Something went wrong while upgrading your ship.")
	end

	busy[player] = nil
end)

Players.PlayerRemoving:Connect(function(player)
	busy[player] = nil
end)
