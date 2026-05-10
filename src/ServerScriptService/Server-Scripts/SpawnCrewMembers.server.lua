local ServerScriptService = game:GetService("ServerScriptService")

local CrewSpawnRuntime = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewSpawnRuntime"))

CrewSpawnRuntime.Start()
