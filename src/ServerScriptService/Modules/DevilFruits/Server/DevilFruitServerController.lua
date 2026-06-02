local ServerScriptService = game:GetService("ServerScriptService")

local function getNamedFolder(parent, childName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName and child:IsA("Folder") then
			return child
		end
	end

	error(string.format("Missing Folder named %s under %s", childName, parent:GetFullName()))
end

local devilFruitModules = ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruits")
local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))
local PhoenixPassiveService = require(
	getNamedFolder(devilFruitModules, "Phoenix"):WaitForChild("Server"):WaitForChild("PhoenixPassiveService")
)

local DevilFruitServerController = {}

function DevilFruitServerController.Start(startSource)
	DevilFruitService.Start(startSource or "DevilFruitServerController")
	PhoenixPassiveService.Start()
end

return DevilFruitServerController
