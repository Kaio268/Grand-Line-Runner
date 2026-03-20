local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BrainrotInstanceService = require(ServerScriptService.Modules:WaitForChild("BrainrotInstanceService"))
local BountyService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushBountyService"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
local GrandLineRushEconomy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))

local Module = {}

local SHIP_UPGRADE_PATH = string.format("HiddenLeaderstats.%s", tostring(PlotUpgradeConfig.InternalStatName or "PlotUpgrade"))
local STAND_STATE_PATH = "IncomeBrainrots"
local STAND_LEVEL_PATH = "StandsLevels"
local SHIP_RESET_ATTRIBUTES = {
	"StealOwnerUserId",
	"StealStandName",
	"StealBrainrotName",
	"StealBrainrotInstanceId",
	"StealProductId",
	"StealTime",
}

local function invokeRuntimeCommand(bindable, action, player)
	local ok, result, extra = pcall(function()
		return bindable:Invoke(action, player)
	end)

	if not ok then
		return false, result
	end

	if result == false then
		return false, extra or "runtime_command_failed"
	end

	return true, extra
end

local function clearPlayerResetAttributes(player)
	for _, attributeName in ipairs(SHIP_RESET_ATTRIBUTES) do
		player:SetAttribute(attributeName, nil)
	end
end

local function releaseAllAssignedShipUnits(player)
	local brainrotInventory = BrainrotInstanceService.EnsureInventory(player)
	if typeof(brainrotInventory) ~= "table" then
		return false, "missing_brainrot_inventory"
	end

	local byId = typeof(brainrotInventory.ById) == "table" and brainrotInventory.ById or {}
	local changed = false
	local now = os.time()

	for _, instanceData in pairs(byId) do
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") ~= "" then
			instanceData.AssignedStand = ""
			instanceData.LastReleasedAt = now
			changed = true
		end
	end

	if changed then
		local success = DataManager:SetValue(player, "BrainrotInventory", brainrotInventory)
		if success == false then
			return false, "failed_to_release_assigned_units"
		end

		BountyService.RefreshPlayerBounty(player, brainrotInventory)
	end

	BrainrotInstanceService.SyncAvailableCounts(player)
	return true
end

function Module.ResetPlayerShip(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local standCommand = ShipRuntimeSignals.GetStandCommandFunction()
	local plotCommand = ShipRuntimeSignals.GetPlotCommandFunction()

	local ok, reason = invokeRuntimeCommand(standCommand, "clear", player)
	if not ok then
		return false, "failed_to_clear_ship_runtime: " .. tostring(reason)
	end

	if DataManager:SetValue(player, SHIP_UPGRADE_PATH, 0) == false then
		return false, "failed_to_reset_ship_level"
	end

	if DataManager:Clear(player, STAND_STATE_PATH) == false then
		return false, "failed_to_clear_ship_stands"
	end

	if DataManager:Clear(player, STAND_LEVEL_PATH) == false then
		return false, "failed_to_clear_ship_stand_levels"
	end

	if DataManager:SetValue(player, "Ship", {
		MaxSlots = GrandLineRushEconomy.Rules.MaxShipSlots,
		Slots = {},
	}) == false then
		return false, "failed_to_clear_ship_slot_assignments"
	end

	ok, reason = releaseAllAssignedShipUnits(player)
	if not ok then
		return false, tostring(reason)
	end

	clearPlayerResetAttributes(player)

	ok, reason = invokeRuntimeCommand(plotCommand, "reset", player)
	if not ok then
		return false, "failed_to_rebuild_ship_plot: " .. tostring(reason)
	end

	ok, reason = invokeRuntimeCommand(standCommand, "refresh", player)
	if not ok then
		return false, "failed_to_refresh_ship_stands: " .. tostring(reason)
	end

	return true, {
		ShipLevel = 0,
		StarterSlots = PlotUpgradeConfig.GetUsableStandCount(0),
	}
end

return Module
