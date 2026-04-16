local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ServerScriptService:WaitForChild("Modules")
local BrainrotInstanceService = require(Modules:WaitForChild("BrainrotInstanceService"))
local service = require(Modules:WaitForChild("GrandLineRushBountyService"))

BrainrotInstanceService.RegisterInventorySavedCallback(function(player, brainrotInventory)
	service.RefreshPlayerBounty(player, brainrotInventory)
end)

service.Start()
