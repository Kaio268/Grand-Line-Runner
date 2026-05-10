local ServerScriptService = game:GetService("ServerScriptService")

-- Compatibility bootstrap. CrewSpawnRuntime is the canonical implementation;
-- legacy script name remains so Studio/Rojo wiring keeps existing behavior.
local CrewSpawnRuntime = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewSpawnRuntime"))

CrewSpawnRuntime.Start()
