local ServerScriptService = game:GetService("ServerScriptService")

local function bootstrap()
	print("[DEVILFRUIT SERVER] bootstrap begin")
	local devilFruitServerController = require(
		ServerScriptService.Modules:WaitForChild("DevilFruits"):WaitForChild("Server"):WaitForChild("DevilFruitServerController")
	)

	devilFruitServerController.Start("Server-Scripts/DevilFruit.server.lua")
	print("[DEVILFRUIT SERVER] bootstrap success")
end

local ok, err = xpcall(bootstrap, debug.traceback)
if not ok then
	warn(string.format("[DEVILFRUIT SERVER][ERROR] bootstrap failed: %s", tostring(err)))
	error(err)
end
