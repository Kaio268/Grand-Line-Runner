local Module = {}

function Module.Install(ctx)
	local function updateCrewStandIncomeForTick(runtime, player, standModel, equippedCrewMember, totalFoodCount, zeroIncomeLogged)

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

			runtime.updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)

			runtime.updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, false, totalFoodCount)

			runtime.updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)

			return false

		end



		local didBankIncome = false

		if crewMemberName ~= "" then

			if not standModel:FindFirstChild("PlacedCrewMember") then

				local handle = cache and cache.Handle or runtime.resolveSlotHandle(standModel)

				if handle and handle:IsA("BasePart") then

					runtime.spawnStandCrewMember(player, standModel, handle, crewMemberName)

				end

			end



			local inc = runtime.getIncomeWithLevel(player, crewMemberName) * runtime.getBeliBoostMultiplier(player)

			zeroIncomeLogged[player] = zeroIncomeLogged[player] or {}

			if inc ~= 0 then

				zeroIncomeLogged[player][standName] = nil

				if runtime.CrewStandIncomeAuthority.AdjustIncomeToCollect(player, standName, inc, "income_bank") then

					didBankIncome = true

				end

			elseif zeroIncomeLogged[player][standName] ~= true then

				zeroIncomeLogged[player][standName] = true

				runtime.standDebug("income zero player=%s stand=%s crewMember=%s", player.Name, standName, tostring(crewMemberName))

			end



			runtime.updateStandHover(player, standModel, crewMemberName)

		end



		runtime.updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)

		runtime.updateLevelUpUI(player, standModel, cache, slotState, crewMemberName, crewMemberInstanceId, false, totalFoodCount)

		runtime.updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName, equippedCrewMember)



		return didBankIncome

	end



	local function updateCrewPlayerIncomeForTick(runtime, player, stands, zeroIncomeLogged)

		if not player.Parent then

			runtime.clearPlayerStandRuntime(player)

			return

		end



		if typeof(stands) ~= "table" then

			return

		end



		local didBankIncome = false

		local equippedCrewMember = runtime.getEquippedCrewMemberToolInfo(player)

		local totalFoodCount = runtime.CrewFoodProgression.GetTotalFoodCount(player)



		for i = 1, #stands do

			if updateCrewStandIncomeForTick(runtime, player, stands[i], equippedCrewMember, totalFoodCount, zeroIncomeLogged) then

				didBankIncome = true

			end

		end



		if didBankIncome then

			runtime.refreshBankedIncomeShadow(player)

		end

	end



	local function runCrewIncomeBankLoop(runtime)

		local zeroIncomeLogged = {}



		while true do

			task.wait(1)



			for player, stands in pairs(runtime.playerStandList) do
				updateCrewPlayerIncomeForTick(runtime, player, stands, zeroIncomeLogged)
			end
		end
	end


	ctx.runCrewIncomeBankLoop = runCrewIncomeBankLoop
	ctx.updateCrewPlayerIncomeForTick = updateCrewPlayerIncomeForTick
	ctx.updateCrewStandIncomeForTick = updateCrewStandIncomeForTick

	function ctx.StartBankLoop()
		task.spawn(runCrewIncomeBankLoop, ctx)
	end
end

return Module
