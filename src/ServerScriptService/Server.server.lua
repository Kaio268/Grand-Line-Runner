local ServerScriptService = game:GetService("ServerScriptService")

local function bootstrapServer()
	print("[SERVER BOOT] begin")

	local devilFruitServerController = require(
		ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Server"):WaitForChild("DevilFruitServerController")
	)
	devilFruitServerController.Start("Server.server.lua")

	print("[SERVER BOOT] devil fruit bootstrap requested")
	print("Hello world, from server!")
end

local ok, err = xpcall(bootstrapServer, debug.traceback)
if not ok then
	warn(string.format("[SERVER BOOT][ERROR] %s", tostring(err)))
	error(err)
end
