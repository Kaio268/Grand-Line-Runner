local ReplicatedStorage = game:GetService("ReplicatedStorage")

local clientFolder = ReplicatedStorage
	:WaitForChild("Modules")
	:WaitForChild("DevilFruits")
	:WaitForChild("Client")

local runtimeBootstrap = require(clientFolder:WaitForChild("DevilFruitRuntimeBootstrap"))

runtimeBootstrap.Start()
