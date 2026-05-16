local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientFolder = ReplicatedStorage
	:WaitForChild("Modules")
	:WaitForChild("DevilFruits")
	:WaitForChild("Client")

local DevilFruitRuntimeBootstrap = {}

local started = false
local startLoopRunning = false
local RETRY_DELAY = 1

local function startRuntime()
	local controllerModule = ClientFolder:WaitForChild("DevilFruitClientController")
	local controller = require(controllerModule)
	controller.Start()

	local holdOk, holdError = xpcall(function()
		local fruitHoldPresentation = require(ClientFolder:WaitForChild("FruitHoldPresentation"))
		fruitHoldPresentation.Start()
	end, debug.traceback)
	if not holdOk then
		warn(string.format("[DEVILFRUIT CLIENT][BOOTSTRAP] hold presentation failed: %s", tostring(holdError)))
	end
end

local function runStartLoop()
	if started or startLoopRunning then
		return
	end

	startLoopRunning = true
	task.spawn(function()
		local attempt = 0
		while not started do
			attempt += 1
			local ok, err = xpcall(startRuntime, debug.traceback)
			if ok then
				started = true
				break
			end

			warn(string.format(
				"[DEVILFRUIT CLIENT][BOOTSTRAP] start attempt %d failed: %s",
				attempt,
				tostring(err)
			))
			task.wait(RETRY_DELAY)
		end

		startLoopRunning = false
	end)
end

function DevilFruitRuntimeBootstrap.Start()
	runStartLoop()
	return DevilFruitRuntimeBootstrap
end

function DevilFruitRuntimeBootstrap.IsStarted()
	return started
end

return DevilFruitRuntimeBootstrap
