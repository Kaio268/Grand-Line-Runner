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

local function isValidNumber(n)
	return typeof(n) == "number" and n == n and n > -math.huge and n < math.huge
end

Remote.OnServerEvent:Connect(function(player, settingName, settingPath, value)
	if typeof(settingName) ~= "string" or typeof(settingPath) ~= "string" then return end

	local entry = SettingsConfig[settingName]
	if type(entry) ~= "table" then return end
	if entry.Path ~= settingPath then return end

	if entry.Type == "Slider" then
		if not isValidNumber(value) then return end
		value = math.floor(value + 0.5)
		if value < 0 then value = 0 end
		if value > 100 then value = 100 end
		DataManager:SetValue(player, entry.Path, value)
	elseif entry.Type == "Switch" then
		if typeof(value) ~= "boolean" then return end
		DataManager:SetValue(player, entry.Path, value)
	end
end)

Players.PlayerRemoving:Connect(function(player) end)
