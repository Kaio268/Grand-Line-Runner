local ServerScriptService = game:GetService("ServerScriptService")

local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))

local DevilFruitServerController = {}

function DevilFruitServerController.Start(startSource)
	DevilFruitService.Start(startSource or "DevilFruitServerController")
end

return DevilFruitServerController
