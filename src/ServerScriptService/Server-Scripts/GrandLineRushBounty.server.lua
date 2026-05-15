local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local CrewInstanceService = require(Modules:WaitForChild("CrewInstanceService"))
local service = require(Modules:WaitForChild("GrandLineRushBountyService"))

CrewInstanceService.RegisterCrewInventorySavedCallback(function(player, crewInventory)
	service.RefreshPlayerBounty(player, crewInventory)
end)

service.Start()
