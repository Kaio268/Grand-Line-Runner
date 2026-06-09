local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local CrewInstanceService = require(Modules:WaitForChild("CrewInstanceService"))
local service = require(Modules:WaitForChild("GrandLineRushBountyService"))

CrewInstanceService.RegisterCrewInventorySavedCallback(function(player, crewInventory, metadata)
	service.RefreshPlayerBounty(player, crewInventory)
	if typeof(metadata) == "table" and typeof(metadata.Counters) == "table" then
		metadata.Counters.BountyRecomputeCount = (tonumber(metadata.Counters.BountyRecomputeCount) or 0) + 1
	end
end)

service.Start()
