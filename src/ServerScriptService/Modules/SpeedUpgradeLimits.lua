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
		return 0, SpeedUpgradeLimits.GetCurrentSpeed(dataManager, player)
	end

	dataManager:AdjustValue(player, TOTAL_SPEED_PATH, increase)
	local newSpeed = dataManager:AdjustValue(player, SPEED_PATH, increase)
	if typeof(newSpeed) == "number" then
		return increase, newSpeed
	end

	return increase, SpeedUpgradeLimits.GetCurrentSpeed(dataManager, player)
end

return SpeedUpgradeLimits
