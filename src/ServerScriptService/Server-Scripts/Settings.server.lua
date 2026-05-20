local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Remote = ReplicatedStorage:FindFirstChild("UpdateSetting")
if not Remote then
	Remote = Instance.new("RemoteEvent")
	Remote.Name = "UpdateSetting"
	Remote.Parent = ReplicatedStorage
end

local SettingsConfig = require(
	ReplicatedStorage
		:WaitForChild("Modules")
		:WaitForChild("Configs")
		:WaitForChild("Settings")
)

local DataManager = require(game.ServerScriptService.Data:WaitForChild("DataManager"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local DEBUG_SETTINGS_SERVER = true
local SPEED_SETTING_NAME = "Speed"
local SPEED_PATH = "HiddenLeaderstats.Speed"
local SELECTED_SPEED_PATH = "Settings.SelectedSpeed"
local SPEED_AUTO_MAX_PATH = "Settings.SpeedAutoMax"
local speedConnectionsByPlayer = {}

local function debugSettings(message, ...)
	if not DEBUG_SETTINGS_SERVER then
		return
	end

	print(string.format("[SETTINGS][SERVER] " .. message, ...))
end

local function isValidNumber(n)
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function roundNumber(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function clampSelectedSpeed(value, earnedMax)
	local maximum = math.max(1, roundNumber(earnedMax))
	return math.clamp(roundNumber(value), 1, maximum)
end

local function getEarnedSpeedValue(player)
	local hidden = player and player:FindFirstChild("HiddenLeaderstats")
	local speed = hidden and hidden:FindFirstChild("Speed")
	if speed and (speed:IsA("NumberValue") or speed:IsA("IntValue")) then
		return speed
	end

	return nil
end

local function getEarnedMaxSpeed(player)
	local speedValue = getEarnedSpeedValue(player)
	if speedValue then
		return math.max(1, roundNumber(speedValue.Value))
	end

	local stored = DataManager:GetValue(player, SPEED_PATH)
	if typeof(stored) == "number" then
		return math.max(1, roundNumber(stored))
	end

	return 1
end

local function getSettingsValue(player, valueName)
	local settings = player and player:FindFirstChild("Settings")
	return settings and settings:FindFirstChild(valueName) or nil
end

local function setProfileValueIfChanged(player, path, value, instance)
	if instance and instance:IsA("ValueBase") and instance.Value == value then
		return true
	end

	return DataManager:SetValue(player, path, value) ~= false
end

local function normalizePlayerSpeedSettings(player, reason)
	local earnedMax = getEarnedMaxSpeed(player)
	local selectedValue = getSettingsValue(player, "SelectedSpeed")
	local autoValue = getSettingsValue(player, "SpeedAutoMax")
	local autoMax = true

	if autoValue and autoValue:IsA("BoolValue") then
		autoMax = autoValue.Value == true
	end

	local selected = earnedMax
	if not autoMax and selectedValue and (selectedValue:IsA("NumberValue") or selectedValue:IsA("IntValue")) then
		selected = selectedValue.Value
	end
	selected = if autoMax then earnedMax else clampSelectedSpeed(selected, earnedMax)

	setProfileValueIfChanged(player, SPEED_AUTO_MAX_PATH, autoMax, autoValue)
	setProfileValueIfChanged(player, SELECTED_SPEED_PATH, selected, selectedValue)
	debugSettings(
		"normalized speed player=%s reason=%s selected=%d max=%d auto=%s",
		player.Name,
		tostring(reason),
		selected,
		earnedMax,
		tostring(autoMax)
	)
end

local function saveRequestedSpeed(player, value)
	if not isValidNumber(value) then
		return nil, "bad_number"
	end

	local earnedMax = getEarnedMaxSpeed(player)
	local selected = clampSelectedSpeed(value, earnedMax)
	local autoMax = selected >= earnedMax

	if DataManager:SetValue(player, SPEED_AUTO_MAX_PATH, autoMax) == false then
		return nil, "save_auto_failed"
	end
	if DataManager:SetValue(player, SELECTED_SPEED_PATH, selected) == false then
		return nil, "save_selected_failed"
	end

	return {
		SelectedSpeed = selected,
		EarnedMaxSpeed = earnedMax,
		SpeedAutoMax = autoMax,
	}
end

local function disconnectSpeedConnections(player)
	local connections = speedConnectionsByPlayer[player]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	speedConnectionsByPlayer[player] = nil
end

local function trackSpeedConnection(player, signal, callback)
	local connections = speedConnectionsByPlayer[player]
	if not connections then
		connections = {}
		speedConnectionsByPlayer[player] = connections
	end

	local connection = signal:Connect(callback)
	connections[#connections + 1] = connection
	return connection
end

local function bindPlayerSpeedSettings(player)
	task.spawn(function()
		local hidden = player:FindFirstChild("HiddenLeaderstats") or player:WaitForChild("HiddenLeaderstats", 30)
		local speedValue = hidden and (hidden:FindFirstChild("Speed") or hidden:WaitForChild("Speed", 30))
		if not player:FindFirstChild("Settings") then
			player:WaitForChild("Settings", 30)
		end

		if player.Parent ~= Players then
			return
		end

		normalizePlayerSpeedSettings(player, "player_ready")

		if speedValue and (speedValue:IsA("NumberValue") or speedValue:IsA("IntValue")) then
			trackSpeedConnection(player, speedValue:GetPropertyChangedSignal("Value"), function()
				normalizePlayerSpeedSettings(player, "earned_speed_changed")
			end)
		end
	end)
end

Remote.OnServerEvent:Connect(function(player, settingName, settingPath, value)
	-- Security: setting path/name must match config before any persisted write can happen.
	if not RemoteGuard.Check(player, "UpdateSetting", { settingName, settingPath }, {
		Cooldown = 0.1,
		Args = {
			{ Type = "string", MaxLength = 80 },
			{ Type = "string", MaxLength = 160 },
		},
	}) then
		return
	end

	debugSettings(
		"received player=%s name=%s path=%s value=%s",
		player and player.Name or "<nil>",
		tostring(settingName),
		tostring(settingPath),
		tostring(value)
	)
	if typeof(settingName) ~= "string" or typeof(settingPath) ~= "string" then
		debugSettings("reject reason=bad_types")
		return
	end

	local entry = SettingsConfig[settingName]
	if type(entry) ~= "table" then
		debugSettings("reject reason=missing_config name=%s", settingName)
		return
	end
	if entry.Path ~= settingPath then
		debugSettings("reject reason=path_mismatch expected=%s actual=%s", tostring(entry.Path), tostring(settingPath))
		return
	end

	if settingName == SPEED_SETTING_NAME then
		local result, reason = saveRequestedSpeed(player, value)
		if not result then
			debugSettings("reject reason=%s value=%s", tostring(reason), tostring(value))
			return
		end
		debugSettings(
			"saved speed player=%s selected=%d max=%d auto=%s",
			player.Name,
			result.SelectedSpeed,
			result.EarnedMaxSpeed,
			tostring(result.SpeedAutoMax)
		)
		return
	end

	if entry.Type == "Slider" then
		if not isValidNumber(value) then
			debugSettings("reject reason=bad_number value=%s", tostring(value))
			return
		end
		value = math.floor(value + 0.5)
		if value < 0 then
			value = 0
		end
		if value > 100 then
			value = 100
		end
		DataManager:SetValue(player, entry.Path, value)
		debugSettings("saved slider player=%s path=%s value=%d", player.Name, entry.Path, value)
	elseif entry.Type == "Switch" then
		if typeof(value) ~= "boolean" then
			debugSettings("reject reason=bad_boolean value=%s", tostring(value))
			return
		end
		DataManager:SetValue(player, entry.Path, value)
		debugSettings("saved switch player=%s path=%s value=%s", player.Name, entry.Path, tostring(value))
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayerSpeedSettings(player)
end

Players.PlayerAdded:Connect(bindPlayerSpeedSettings)

Players.PlayerRemoving:Connect(function(player)
	disconnectSpeedConnections(player)
end)
