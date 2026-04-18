local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

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
local DEBUG_SETTINGS_SERVER = true

local function debugSettings(message, ...)
	if not DEBUG_SETTINGS_SERVER then
		return
	end

	print(string.format("[SETTINGS][SERVER] " .. message, ...))
end

local function isValidNumber(n)
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

Remote.OnServerEvent:Connect(function(player, settingName, settingPath, value)
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

	if entry.Type == "Slider" then
		if not isValidNumber(value) then
			debugSettings("reject reason=bad_number value=%s", tostring(value))
			return
		end
		value = math.floor(value + 0.5)
		if value < 0 then value = 0 end
		if value > 100 then value = 100 end
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

Players.PlayerRemoving:Connect(function(player) end)
