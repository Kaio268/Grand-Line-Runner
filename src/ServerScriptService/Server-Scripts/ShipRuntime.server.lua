local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

Players.CharacterAutoLoads = false

local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))

ShipRuntimeService.Start()
