local ServerScriptService = game:GetService("ServerScriptService")

local GroupLikeLuffyNpcSetupService = require(
	ServerScriptService:WaitForChild("Modules"):WaitForChild("GroupLikeLuffyNpcSetupService")
)

GroupLikeLuffyNpcSetupService.Start()
