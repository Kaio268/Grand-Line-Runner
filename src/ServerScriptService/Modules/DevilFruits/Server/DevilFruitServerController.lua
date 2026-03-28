local ServerScriptService = game:GetService("ServerScriptService")

local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))

local DevilFruitServerController = {}

function DevilFruitServerController.Start()
	DevilFruitService.Start()
end

return DevilFruitServerController
