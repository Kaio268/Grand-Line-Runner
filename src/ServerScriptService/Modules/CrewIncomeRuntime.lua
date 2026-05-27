local CrewIncomeRuntime = {}

local Players = game:GetService("Players")

local started = false
local activeContext = nil

local CrewIncomeFolder = script.Parent:WaitForChild("CrewIncome")
local Context = require(CrewIncomeFolder:WaitForChild("Context"))

local installers = {
	require(CrewIncomeFolder:WaitForChild("CrewResolver")),
	require(CrewIncomeFolder:WaitForChild("StandState")),
	require(CrewIncomeFolder:WaitForChild("SlotRuntimeCache")),
	require(CrewIncomeFolder:WaitForChild("VisualRuntime")),
	require(CrewIncomeFolder:WaitForChild("DisplayRuntime")),
	require(CrewIncomeFolder:WaitForChild("ClaimRuntime")),
	require(CrewIncomeFolder:WaitForChild("PromptRuntime")),
	require(CrewIncomeFolder:WaitForChild("CaptainBridge")),
	require(CrewIncomeFolder:WaitForChild("StandRegistry")),
	require(CrewIncomeFolder:WaitForChild("Bootstrap")),
	require(CrewIncomeFolder:WaitForChild("BankLoop")),
}

function CrewIncomeRuntime.Start()
	if started then
		return
	end
	started = true

	local ctx = Context.Create()
	for _, installer in ipairs(installers) do
		installer.Install(ctx)
	end
	activeContext = ctx

	if typeof(ctx.StartBankLoop) == "function" then
		ctx.StartBankLoop()
	end
end

function CrewIncomeRuntime.RefreshPlayer(player, source)
	CrewIncomeRuntime.Start()
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "invalid_player"
	end
	if typeof(activeContext) ~= "table" then
		return false, "context_unavailable"
	end

	local ok, err = pcall(function()
		local activeShip = nil
		if activeContext.ShipRuntimeService and typeof(activeContext.ShipRuntimeService.GetActiveShip) == "function" then
			activeShip = activeContext.ShipRuntimeService.GetActiveShip(player)
		end
		if typeof(activeContext.reconcileSlotAssignmentsForRender) == "function" then
			local reconcileOk, reconcileReason =
				activeContext.reconcileSlotAssignmentsForRender(player, activeShip, tostring(source or "manual_refresh"))
			if reconcileOk == false then
				error(tostring(reconcileReason or "slot_reconcile_failed"))
			end
		end
		if typeof(activeContext.reconcilePlayerStandAssignments) == "function" then
			activeContext.reconcilePlayerStandAssignments(player)
		end
		if typeof(activeContext.refreshPlayerIncomeDisplaysAfterLifecycleUpdate) == "function" then
			activeContext.refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
		end
	end)
	if not ok then
		return false, tostring(err)
	end

	return true, nil
end

return CrewIncomeRuntime
