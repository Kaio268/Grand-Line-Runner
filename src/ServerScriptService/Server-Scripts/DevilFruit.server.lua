local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BOOTSTRAP_DEBUG = ReplicatedStorage:GetAttribute("DebugDevilFruitLogs") == true

local function bootstrap()
	if BOOTSTRAP_DEBUG then
		print("[DEVILFRUIT SERVER] bootstrap begin")
	end
	local devilFruitServerController = require(
		ServerScriptService.Modules:WaitForChild("DevilFruits"):WaitForChild("Server"):WaitForChild("DevilFruitServerController")
	)

	devilFruitServerController.Start("Server-Scripts/DevilFruit.server.lua")
	if BOOTSTRAP_DEBUG then
		print("[DEVILFRUIT SERVER] bootstrap success")
	end
end

local ok, err = xpcall(bootstrap, debug.traceback)
if not ok then
	warn(string.format("[DEVILFRUIT SERVER][ERROR] bootstrap failed: %s", tostring(err)))
	error(err)
end
