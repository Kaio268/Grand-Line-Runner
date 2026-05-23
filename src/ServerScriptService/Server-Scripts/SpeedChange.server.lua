local ServerScriptService = game:GetService("ServerScriptService")

local PlayerMovementSpeedService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("PlayerMovementSpeedService"))

PlayerMovementSpeedService.Start()
