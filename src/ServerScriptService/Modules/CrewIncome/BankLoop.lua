local Module = {}

local BANK_MAINTENANCE_INTERVAL_SECONDS = 5
local SAFETY_FLUSH_INTERVAL_SECONDS = 60
local BANK_LOOP_FRAME_BUDGET_SECONDS = 0.006

function Module.Install(ctx)
	local function getPlayerIncomeTickReadiness(runtime, player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "cleanup"
		end
		if player.Parent ~= runtime.Players then
			return false, "cleanup"
		end

		local dataManager = runtime.DataManager
		if dataManager and typeof(dataManager.IsHardResetPending) == "function" and dataManager:IsHardResetPending(player.UserId) then
			return false, "cleanup"
		end
		if dataManager and typeof(dataManager.IsReady) == "function" and not dataManager:IsReady(player) then
			return false, "not_ready"
		end

		return true, nil
	end

	local PlacedCrewState = require(ctx.Modules:WaitForChild("Crew"):WaitForChild("PlacedCrewState"))

	local function updateCrewStandIncomeForTick(
		runtime,
		player,
		standModel,
		equippedCrewMember,
		totalFoodCount,
		zeroIncomeLogged,
		materializeIncome
	)

		if not standModel or not standModel.Parent then

			return false

		end



		local standName = standModel.Name

		local cache = runtime.getSlotRuntime(player, standModel.Parent, standModel)

		runtime.dmEnsureStandFolder(player, standName)



		local slotState = runtime.getStandSlotState(player, standName)

		local crewMemberName = runtime.getPlayerStandCrewMemberName(player, standName)

		local crewMemberInstanceId = if crewMemberName ~= "" then runtime.getPlayerStandCrewMemberInstanceId(player, standName) else ""



		if not slotState.Usable then

			runtime.clearStandVisual(standModel)

			runtime.updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, false, totalFoodCount)

			runtime.updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)

			return false

		end



		local didBankIncome = false

		if crewMemberName ~= "" then

			if standModel:GetAttribute(PlacedCrewState.Attribute.Active) ~= true then

				local handle = cache and cache.Handle or runtime.resolveSlotHandle(standModel)

				if
					handle
					and handle:IsA("BasePart")
					and typeof(runtime.enqueueCrewVisualRestore) == "function"
				then

					runtime.enqueueCrewVisualRestore(player, standModel, handle, crewMemberName, {
						CrewMemberInstanceId = crewMemberInstanceId,
						Generation = runtime.ShipRuntimeService.GetCrewVisualGeneration(player),
						Source = "bank_loop_missing_visual",
					})

				end

			end



			zeroIncomeLogged[player] = zeroIncomeLogged[player] or {}

			if runtime.getRawBankIncomePerSecond(player, crewMemberName, crewMemberInstanceId) ~= 0 then
				zeroIncomeLogged[player][standName] = nil
			elseif zeroIncomeLogged[player][standName] ~= true then

				zeroIncomeLogged[player][standName] = true

				runtime.standDebug("income zero player=%s stand=%s crewMember=%s", player.Name, standName, tostring(crewMemberName))

			end



			if materializeIncome == true and typeof(runtime.materializeStandIncome) == "function" then
				if runtime.materializeStandIncome(player, standName, "income_safety_flush") then
					didBankIncome = true
				end
			end

		end


		runtime.updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, false, totalFoodCount)

		runtime.updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)



		return didBankIncome

	end



	local function updateCrewPlayerIncomeForTick(runtime, player, stands, zeroIncomeLogged, materializeIncome)

		local ready, readinessReason = getPlayerIncomeTickReadiness(runtime, player)

		if not ready then
			if readinessReason == "cleanup" then
				zeroIncomeLogged[player] = nil
				runtime.clearPlayerStandRuntime(player)
			end
			return
		end



		if typeof(stands) ~= "table" then

			return

		end



		local didBankIncome = false

		local equippedCrewMember = runtime.getEquippedCrewMemberToolInfo(player)

		local totalFoodCount = nil
		if typeof(runtime.CrewFoodProgression.TryGetTotalFoodCount) == "function" then
			totalFoodCount = runtime.CrewFoodProgression.TryGetTotalFoodCount(player)
		else
			totalFoodCount = runtime.CrewFoodProgression.GetTotalFoodCount(player)
		end
		if totalFoodCount == nil then
			return
		end



		local sliceStartedAt = os.clock()
		for i = 1, #stands do

			if
				updateCrewStandIncomeForTick(
					runtime,
					player,
					stands[i],
					equippedCrewMember,
					totalFoodCount,
					zeroIncomeLogged,
					materializeIncome
				)
			then

				didBankIncome = true

			end

			if os.clock() - sliceStartedAt >= BANK_LOOP_FRAME_BUDGET_SECONDS then
				task.wait()
				sliceStartedAt = os.clock()
			end

		end



		if didBankIncome then

			runtime.refreshBankedIncomeShadow(player)

		end

	end



	local function runCrewIncomeBankLoop(runtime)

		local zeroIncomeLogged = {}
		local nextSafetyFlushAt = os.clock() + SAFETY_FLUSH_INTERVAL_SECONDS



		while true do

			task.wait(BANK_MAINTENANCE_INTERVAL_SECONDS)


			local loopStartedAt = os.clock()
			local materializeIncome = loopStartedAt >= nextSafetyFlushAt
			if materializeIncome then
				nextSafetyFlushAt = loopStartedAt + SAFETY_FLUSH_INTERVAL_SECONDS
			end
			local playersProcessed = 0
			local standsProcessed = 0
			local occupiedStands = 0
			local outerSliceStartedAt = loopStartedAt

			for player, stands in pairs(runtime.playerStandList) do
				local ok, err = xpcall(function()
					playersProcessed += 1
					if typeof(stands) == "table" then
						standsProcessed += #stands
						for _, standModel in ipairs(stands) do
							if
								typeof(standModel) == "Instance"
								and standModel:GetAttribute(PlacedCrewState.Attribute.Active) == true
							then
								occupiedStands += 1
							end
						end
					end
					updateCrewPlayerIncomeForTick(runtime, player, stands, zeroIncomeLogged, materializeIncome)
				end, debug.traceback)
				if not ok then
					warn(("[CrewIncome] Bank loop tick failed for %s: %s"):format(
						player and player.Name or "unknown",
						tostring(err)
					))
				end
				if os.clock() - outerSliceStartedAt >= BANK_LOOP_FRAME_BUDGET_SECONDS then
					task.wait()
					outerSliceStartedAt = os.clock()
				end
			end
			if
				runtime.GTRPerformanceDiagnostics
				and typeof(runtime.GTRPerformanceDiagnostics.RecordBankLoop) == "function"
			then
				runtime.GTRPerformanceDiagnostics.RecordBankLoop(
					os.clock() - loopStartedAt,
					playersProcessed,
					standsProcessed,
					occupiedStands
				)
			end
		end
	end

	local function flushPlayerStandIncome(runtime, player, sourcePath)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end
		local stands = runtime.playerStandList[player]
		if typeof(stands) ~= "table" then
			return true, "no_stands"
		end

		local flushed = 0
		for _, standModel in ipairs(stands) do
			if standModel and standModel.Parent then
				local standName = standModel.Name
				local crewMemberName = runtime.getPlayerStandCrewMemberName(player, standName)
				if crewMemberName ~= "" and typeof(runtime.materializeStandIncome) == "function" then
					if runtime.materializeStandIncome(player, standName, sourcePath or "income_flush") then
						flushed += 1
					end
				end
			end
		end
		return true, flushed
	end


	ctx.runCrewIncomeBankLoop = runCrewIncomeBankLoop
	ctx.flushPlayerStandIncome = function(player, sourcePath)
		return flushPlayerStandIncome(ctx, player, sourcePath)
	end
	ctx.updateCrewPlayerIncomeForTick = updateCrewPlayerIncomeForTick
	ctx.updateCrewStandIncomeForTick = updateCrewStandIncomeForTick

	function ctx.StartBankLoop()
		task.spawn(runCrewIncomeBankLoop, ctx)
	end
end

return Module
