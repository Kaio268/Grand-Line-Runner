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
	require(CrewIncomeFolder:WaitForChild("VisualRestoreQueue")),
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

function CrewIncomeRuntime.RefreshStand(player, standName, source)
	CrewIncomeRuntime.Start()
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "invalid_player"
	end
	if typeof(activeContext) ~= "table" then
		return false, "context_unavailable"
	end

	standName = tostring(standName or "")
	if standName == "" then
		return false, "invalid_stand"
	end

	local ok, err = pcall(function()
		if typeof(activeContext.enqueueStandIncomeDisplayRefresh) == "function" then
			local queued, queueReason =
				activeContext.enqueueStandIncomeDisplayRefresh(player, standName, source or "single_stand_refresh")
			if queued == false then
				error(tostring(queueReason or "single_stand_refresh_queue_failed"))
			end
			return
		end

		if typeof(activeContext.refreshStandIncomeDisplay) == "function" then
			local refreshOk, refreshReason =
				activeContext.refreshStandIncomeDisplay(player, standName, source or "single_stand_refresh")
			if refreshOk == false then
				error(tostring(refreshReason or "single_stand_refresh_failed"))
			end
		end
	end)
	if not ok then
		return false, tostring(err)
	end

	return true, nil
end

function CrewIncomeRuntime.FlushPlayerAccruals(player, source)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end
	if typeof(activeContext) ~= "table" or typeof(activeContext.flushPlayerStandIncome) ~= "function" then
		return true, "runtime_inactive"
	end

	local standOk, standResult = activeContext.flushPlayerStandIncome(player, source or "crew_income_runtime_flush")
	local captainOk, captainResult = true, nil
	if
		activeContext.CaptainSlotRuntime
		and typeof(activeContext.CaptainSlotRuntime.FlushPlayerAccrual) == "function"
	then
		captainOk, captainResult = activeContext.CaptainSlotRuntime.FlushPlayerAccrual(player)
	end
	if standOk ~= true then
		return false, standResult
	end
	if captainOk ~= true then
		return false, captainResult
	end

	return true, standResult
end

return CrewIncomeRuntime
