--// Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

--// Variables

--// Modules
local DataManager = require(ServerScriptService.Data.DataManager)

--// Main

function UpdatePlaytime()
	task.spawn(function()
		while task.wait(1) do
			for _, Player in ipairs(Players:GetPlayers()) do
				DataManager:AddValue(Player, `TotalStats.TimePlayed`, 1)
			end
		end
	end)
end

UpdatePlaytime()

