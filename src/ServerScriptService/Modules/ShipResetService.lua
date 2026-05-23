local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local ProfileTemplate = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"):WaitForChild("ProfileTemplate"))
local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewSlotAssignmentReconciler = require(ServerScriptService.Modules:WaitForChild("CrewSlotAssignmentReconciler"))
local BountyService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushBountyService"))
local ShipRuntimeSignals = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeSignals"))
local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
local GrandLineRushEconomy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))

local Module = {}

local SHIP_UPGRADE_PATH = string.format("HiddenLeaderstats.%s", tostring(PlotUpgradeConfig.InternalStatName or "PlotUpgrade"))
local SPEED_PATH = "HiddenLeaderstats.Speed"
local DEFAULT_SPEED = math.max(1, math.floor(tonumber(ProfileTemplate.HiddenLeaderstats.Speed) or 1))
local SHIP_RESET_ATTRIBUTES = {
	"StealOwnerUserId",
	"StealStandName",
	"StealCrewMemberName",
	"StealCrewMemberInstanceId",
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

local function runOptionalMutation(player, mutation)
	if typeof(mutation) ~= "function" then
		return true
	end

	local ok, result, reason = pcall(mutation, player)
	if not ok then
		return false, "reset_mutation_error: " .. tostring(result)
	end

	if result == false then
		return false, tostring(reason or "reset_mutation_failed")
	end

	return true
end

local function resetPlayerShipData(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}

	local standCommand = ShipRuntimeSignals.GetStandCommandFunction()

	local ok, reason = invokeRuntimeCommand(standCommand, "clear", player)
	if not ok then
		return false, "failed_to_clear_ship_runtime: " .. tostring(reason)
	end

	if DataManager:SetValue(player, SHIP_UPGRADE_PATH, 0) == false then
		return false, "failed_to_reset_ship_level"
	end

	if DataManager:SetValue(player, SPEED_PATH, DEFAULT_SPEED) == false then
		return false, "failed_to_reset_speed"
	end

	local resetOk, resetReason, resetSummary = CrewSlotAssignmentReconciler.ResetAssignmentsForRebirth(player, {
		Source = tostring(options.Reason or "ship_reset"),
		SourcePath = tostring(options.Reason or "ship_reset") .. "_release_assigned",
	})
	if resetOk == false then
		return false, tostring(resetReason)
	end

	if DataManager:SetValue(player, "Ship", {
		MaxSlots = GrandLineRushEconomy.Rules.MaxShipSlots,
		Slots = {},
		CaptainSlot = {},
	}) == false then
		return false, "failed_to_clear_ship_slot_assignments"
	end

	if resetSummary
		and (
			(tonumber(resetSummary.UnassignedCount) or 0) > 0
			or (tonumber(resetSummary.MaterializedCount) or 0) > 0
			or (tonumber(resetSummary.ProgressMergedCount) or 0) > 0
		)
	then
		BountyService.RefreshPlayerBounty(player, CrewInstanceService.GetCrewInventory(player))
	end

	ok, reason = runOptionalMutation(player, options.MutateProfile)
	if not ok then
		return false, tostring(reason)
	end

	clearPlayerResetAttributes(player)

	return true, resetSummary
end

function Module.ResetPlayerShip(player, options)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	options = if typeof(options) == "table" then options else {}
	local reason = tostring(options.Reason or "ship_reset")
	local resetEpoch = CrewSlotAssignmentReconciler.BeginReset(player, reason)

	local ok, success, resultOrReason = xpcall(function()
		return resetPlayerShipData(player, options)
	end, debug.traceback)

	CrewSlotAssignmentReconciler.EndReset(player, resetEpoch)

	if not ok then
		warn(("[ShipResetService] Ship reset errored for %s: %s"):format(player.Name, tostring(success)))
		return false, "ship_reset_error"
	end

	if success == false then
		return false, tostring(resultOrReason)
	end

	local refreshed, refreshReason = ShipRuntimeService.RefreshPlayerShip(player, {
		ForceReplace = true,
		Reason = reason,
		ResetEpoch = resetEpoch,
	})
	if refreshed == false then
		warn(("[ShipResetService] Ship runtime refresh after reset skipped for %s: %s"):format(
			player.Name,
			tostring(refreshReason)
		))
		return false, "failed_to_refresh_ship_runtime: " .. tostring(refreshReason)
	end

	return true, {
		ShipLevel = 0,
		StarterSlots = PlotUpgradeConfig.GetUsableStandCount(0),
		ResetSummary = resultOrReason,
	}
end

return Module
