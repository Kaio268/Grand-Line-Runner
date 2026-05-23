local ServerScriptService = game:GetService("ServerScriptService")

local SpikeRuntimeService = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("Hazards")
		:WaitForChild("SpikeRuntimeService")
)

SpikeRuntimeService.StartNormalPlatformLoop()
