local SpeedUpgradeLimits = {}

local SPEED_PATH = "HiddenLeaderstats.Speed"
local TOTAL_SPEED_PATH = "TotalStats.TotalSpeed"

local function getRuntimeSpeedValue(player)
	local hidden = player and player:FindFirstChild("HiddenLeaderstats")
	local speed = hidden and hidden:FindFirstChild("Speed")
	if speed and typeof(speed.Value) == "number" then
		return speed.Value
	end
	return nil
end

function SpeedUpgradeLimits.GetCurrentSpeed(dataManager, player)
	local runtime = getRuntimeSpeedValue(player)
	if typeof(runtime) == "number" then
		return runtime
	end

	local stored = dataManager:GetValue(player, SPEED_PATH)
	if typeof(stored) == "number" then
		return stored
	end

	return 1
end

function SpeedUpgradeLimits.SanitizeSpeedValue(speed)
	local numeric = tonumber(speed)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return 1
	end

	return math.max(1, numeric)
end

function SpeedUpgradeLimits.SanitizeSpeedIncrease(requestedIncrease)
	local requested = tonumber(requestedIncrease)
	if requested == nil or requested ~= requested or requested == math.huge or requested == -math.huge then
		return 0
	end

	return math.max(0, math.floor(requested))
end

function SpeedUpgradeLimits.ApplySpeedIncrease(dataManager, player, requestedIncrease)
	local increase = SpeedUpgradeLimits.SanitizeSpeedIncrease(requestedIncrease)
	if increase <= 0 then
		return false, 0, SpeedUpgradeLimits.GetCurrentSpeed(dataManager, player), "invalid_increase"
	end

	local newTotal, totalReason = dataManager:AdjustValue(player, TOTAL_SPEED_PATH, increase)
	if typeof(newTotal) ~= "number" then
		return false, 0, SpeedUpgradeLimits.GetCurrentSpeed(dataManager, player), totalReason or "total_speed_update_failed"
	end

	local newSpeed, speedReason = dataManager:AdjustValue(player, SPEED_PATH, increase)
	if typeof(newSpeed) == "number" then
		return true, increase, newSpeed
	end

	local rolledBackTotal = dataManager:AdjustValue(player, TOTAL_SPEED_PATH, -increase)
	if typeof(rolledBackTotal) ~= "number" then
		warn(string.format(
			"[SpeedUpgradeLimits] Failed to roll back TotalSpeed after Speed update failed for %s",
			player and player.Name or "<unknown>"
		))
	end

	return false, 0, SpeedUpgradeLimits.GetCurrentSpeed(dataManager, player), speedReason or "speed_update_failed"
end

function SpeedUpgradeLimits.RollbackSpeedIncrease(dataManager, player, appliedIncrease)
	local increase = SpeedUpgradeLimits.SanitizeSpeedIncrease(appliedIncrease)
	if increase <= 0 then
		return true
	end

	local speedAfter, speedReason = dataManager:AdjustValue(player, SPEED_PATH, -increase)
	local totalAfter, totalReason = dataManager:AdjustValue(player, TOTAL_SPEED_PATH, -increase)
	if typeof(speedAfter) == "number" and typeof(totalAfter) == "number" then
		return true
	end

	return false, speedReason or totalReason or "rollback_failed"
end

return SpeedUpgradeLimits
