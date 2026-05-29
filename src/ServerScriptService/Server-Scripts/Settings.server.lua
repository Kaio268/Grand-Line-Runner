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
local PlayerMovementSpeedService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerMovementSpeedService"))
local RaidShieldService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RaidShieldService"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local DEBUG_SETTINGS_SERVER = true
local SPEED_SETTING_NAME = "Speed"
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

local function normalizePlayerSpeedSettings(player, reason)
	local result, normalizeReason = PlayerMovementSpeedService.NormalizePlayerSpeedSettings(player, DataManager, reason)
	if not result then
		debugSettings(
			"normalize failed player=%s reason=%s context=%s",
			player.Name,
			tostring(normalizeReason),
			tostring(reason)
		)
		return
	end

	PlayerMovementSpeedService.ApplyPlayerSpeed(player, "settings_normalized")
	debugSettings(
		"normalized speed player=%s reason=%s selected=%d max=%d auto=%s",
		player.Name,
		tostring(reason),
		result.SelectedSpeed,
		result.EarnedMaxSpeed,
		tostring(result.SpeedAutoMax)
	)
end

local function saveRequestedSpeed(player, value)
	if not isValidNumber(value) then
		return nil, "bad_number"
	end

	local earnedMax = PlayerMovementSpeedService.GetEarnedMaxSpeed(player, DataManager)
	local selected = PlayerMovementSpeedService.ClampSelectedSpeed(value, earnedMax)
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
		PlayerMovementSpeedService.ApplyPlayerSpeed(player, "settings_speed_saved")
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

RaidShieldService.Start()

for _, player in ipairs(Players:GetPlayers()) do
	bindPlayerSpeedSettings(player)
end

Players.PlayerAdded:Connect(bindPlayerSpeedSettings)

Players.PlayerRemoving:Connect(function(player)
	disconnectSpeedConnections(player)
end)
