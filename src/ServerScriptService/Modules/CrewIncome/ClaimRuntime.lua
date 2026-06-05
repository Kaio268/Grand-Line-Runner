local Module = {}

function Module.Install(ctx)
	local function buildIncomeToastDisplayPayload(...)
		return ctx.buildIncomeToastDisplayPayload(...)
	end
	local CrewStandIncomeAuthority = ctx.CrewStandIncomeAuthority
	local CurrencyUtil = ctx.CurrencyUtil
	local DataManager = ctx.DataManager
	local GTRActionDiagnostics = ctx.GTRActionDiagnostics
	local function dmEnsureStandFolder(...)
		return ctx.dmEnsureStandFolder(...)
	end
	local function formatInstancePath(...)
		return ctx.formatInstancePath(...)
	end
	local function getExistingSlotRuntime(...)
		return ctx.getExistingSlotRuntime(...)
	end
	local function getPlayerStandCrewMemberName(...)
		return ctx.getPlayerStandCrewMemberName(...)
	end
	local function getPlayerStandIncome(...)
		return ctx.getPlayerStandIncome(...)
	end
	local function getSlotRuntime(...)
		return ctx.getSlotRuntime(...)
	end
	local function getStandSlotState(...)
		return ctx.getStandSlotState(...)
	end
	local function getStandClaimSummary(...)
		return ctx.getStandClaimSummary(...)
	end
	local MoneyCollectedRE = ctx.MoneyCollectedRE
	local function ownershipTrace(...)
		return ctx.ownershipTrace(...)
	end
	local Players = ctx.Players
	local QuestSignals = ctx.QuestSignals
	local function refreshCollectedIncomeShadow(...)
		return ctx.refreshCollectedIncomeShadow(...)
	end
	local function saveTrace(...)
		return ctx.saveTrace(...)
	end
	local ShipRuntimeService = ctx.ShipRuntimeService
	local ShipSlotService = ctx.ShipSlotService
	local function standDebug(...)
		return ctx.standDebug(...)
	end
	local touchDebounce = ctx.touchDebounce
	local function updateStandMoneyText(...)
		return ctx.updateStandMoneyText(...)
	end
	local function publishClaimIncomeState(...)
		if typeof(ctx.publishClaimIncomeState) == "function" then
			return ctx.publishClaimIncomeState(...)
		end

		return false, "publish_unavailable"
	end

	local function getHitBoxPart(standModel, cache)
		cache = cache or getExistingSlotRuntime(standModel)
		if cache then
			return cache.ClaimHitBox
		end

		return ShipSlotService.GetClaimHitBox(standModel)
	end

	local function waitForPlot(player, timeout)
		local t0 = os.clock()
		standDebug("waitForShip begin player=%s timeout=%s", player.Name, tostring(timeout or 15))
		saveTrace(
			"restoreWait begin player=%s userId=%s timeout=%s check=active_ship.OwnerUserId==player.UserId",
			player.Name,
			tostring(player.UserId),
			tostring(timeout or 15)
		)
		ownershipTrace(
			"waitForShip begin player=%s userId=%s timeout=%s",
			player.Name,
			tostring(player.UserId),
			tostring(timeout or 15)
		)
		while os.clock() - t0 < (timeout or 15) do
			local activeShip = ShipRuntimeService.GetActiveShip(player)
			if activeShip then
				standDebug("waitForShip found player=%s ship=%s", player.Name, activeShip:GetFullName())
				saveTrace(
					"restoreWait accepted player=%s userId=%s ship=%s reason=active_ship_runtime",
					player.Name,
					tostring(player.UserId),
					formatInstancePath(activeShip)
				)
				return activeShip
			end

			task.wait(0.25)
		end
		standDebug("waitForShip timed_out player=%s", player.Name)
		saveTrace(
			"restoreWait skipped player=%s userId=%s reason=no_active_ship_with_matching_owner_userid timeout=%s",
			player.Name,
			tostring(player.UserId),
			tostring(timeout or 15)
		)
		ownershipTrace(
			"waitForShip timed_out player=%s userId=%s timeout=%s",
			player.Name,
			tostring(player.UserId),
			tostring(timeout or 15)
		)
		return nil
	end

	local function fireMoneyCollected(player, standModel, collected, incomeToastDisplayPayload)
		if not MoneyCollectedRE then
			return
		end

		if incomeToastDisplayPayload ~= nil then
			MoneyCollectedRE:FireClient(player, standModel, collected, incomeToastDisplayPayload)
		else
			MoneyCollectedRE:FireClient(player, standModel, collected)
		end
	end

	local function bindZoneCollect(player, plot, standModel, cache)
		cache = cache or getSlotRuntime(player, plot, standModel)
		local zone = getHitBoxPart(standModel, cache)
		if not zone then
			return
		end
		if cache.ZoneTouchedConnection and cache.ZoneTouchedConnection.Connected and cache.ClaimHitBox == zone then
			return
		end

		if cache.ZoneTouchedConnection and cache.ZoneTouchedConnection.Connected then
			cache.ZoneTouchedConnection:Disconnect()
		end

		cache.ZoneTouchedConnection = zone.Touched:Connect(function(hit)
			if not hit or hit.Name ~= "HumanoidRootPart" then
				return
			end

			local char = hit.Parent
			if not char then
				return
			end

			local plr = Players:GetPlayerFromCharacter(char)
			if not plr or plr ~= player then
				return
			end

			if not ShipRuntimeService.IsActiveShip(plot) then
				return
			end

			local owner = plot:GetAttribute("OwnerUserId")
			if owner ~= plr.UserId then
				return
			end

			touchDebounce[plr] = touchDebounce[plr] or {}
			local now = os.clock()
			local last = touchDebounce[plr][zone]
			if last and (now - last) < 0.35 then
				return
			end
			touchDebounce[plr][zone] = now

			local standName = standModel.Name
			local actionTrace = if GTRActionDiagnostics and typeof(GTRActionDiagnostics.Start) == "function"
				then GTRActionDiagnostics.Start("IncomeClaim", plr, {
					Target = standName,
				})
				else nil
			local function phaseAction(phase, metadata)
				if actionTrace == nil then
					return
				end
				metadata = if typeof(metadata) == "table" then metadata else {}
				if metadata.Target == nil then
					metadata.Target = standName
				end
				actionTrace:phase(phase, metadata)
			end
			local function finishAction(result, metadata)
				if actionTrace == nil then
					return
				end
				metadata = if typeof(metadata) == "table" then metadata else {}
				if metadata.Target == nil then
					metadata.Target = standName
				end
				actionTrace:finish(result, metadata)
			end

			if not dmEnsureStandFolder(plr, standName) then
				finishAction("failed", {
					Reason = "stand_folder_unavailable",
				})
				return
			end
			local collectedCrewMemberName = getPlayerStandCrewMemberName(plr, standName)

			local slotState = getStandSlotState(plr, standName)
			if slotState.Visible and not slotState.Usable then
				updateStandMoneyText(plr, standModel)
				phaseAction("prompt_refresh", {
					Result = "skipped",
					Reason = "slot_unusable",
				})
				finishAction("failed", {
					Reason = "slot_unusable",
				})
				return
			end

			local baseToCollect = getPlayerStandIncome(plr, standName)
			if baseToCollect <= 0 then
				updateStandMoneyText(plr, standModel)
				phaseAction("prompt_refresh", {
					Result = "skipped",
					Reason = "no_income",
				})
				finishAction("failed", {
					Reason = "no_income",
				})
				return
			end

			local claimSummary = getStandClaimSummary(plr, standName)
			local collected = math.max(0, math.floor(tonumber(claimSummary and claimSummary.FinalAmount) or 0))
			if collected <= 0 then
				updateStandMoneyText(plr, standModel)
				phaseAction("prompt_refresh", {
					Result = "skipped",
					Reason = "nothing_to_collect",
				})
				finishAction("failed", {
					Reason = "nothing_to_collect",
				})
				return
			end

			local remainingRawIncome = math.max(0, tonumber(claimSummary and claimSummary.RawRemainderAmount) or 0)
			phaseAction("validation_math", {
				Result = "ok",
			})

			local primaryPath = CurrencyUtil.getPrimaryPath()
			local totalPath = CurrencyUtil.getTotalPath()
			local currentPrimary = math.max(0, tonumber(DataManager:GetValue(plr, primaryPath)) or 0)
			local currentTotal = math.max(0, tonumber(DataManager:GetValue(plr, totalPath)) or 0)
			local batchOk, batchResult = DataManager:TryApplyBatch(plr, {
				CrewStandIncomeAuthority.BuildIncomeToCollectOperation(plr, standName, remainingRawIncome),
				{
					Kind = "Set",
					Path = primaryPath,
					Value = currentPrimary + collected,
				},
				{
					Kind = "Set",
					Path = totalPath,
					Value = currentTotal + collected,
				},
			}, {
				PerfContext = {
					Target = "income_claim:" .. standName,
				},
			})
			local writeCount = batchResult and batchResult.WriteCount or batchResult and batchResult.ReplicaWriteCount or 0
			phaseAction("batch", {
				WriteCount = writeCount,
				Result = if batchOk then "ok" else "failed",
				Reason = batchResult and batchResult.Reason or nil,
			})
			if batchOk ~= true then
				finishAction("failed", {
					WriteCount = writeCount,
					Reason = batchResult and batchResult.Reason or "batch_failed",
				})
				return
			end
			CrewStandIncomeAuthority.RecordExternalIncomeWrite(1)
			refreshCollectedIncomeShadow(plr)
			local claimStateOk, claimStateReason = publishClaimIncomeState(plr, standModel, {
				RawIncomeToCollect = remainingRawIncome,
				ClaimReadyAmount = 0,
			}, {
				RefreshIncomeTimestamp = true,
				RefreshUpdatedTimestamp = true,
			})
			phaseAction("claim_state", {
				Result = if claimStateOk then "ok" else "failed",
				Reason = claimStateReason,
			})

			QuestSignals.Record(plr, "EarnBeli", collected, {
				Source = "StandIncome",
				StandName = standName,
			})
			phaseAction("quest", {
				Result = "ok",
			})

			local incomeToastDisplayPayload = buildIncomeToastDisplayPayload(plr, collectedCrewMemberName)
			if MoneyCollectedRE then
				if incomeToastDisplayPayload ~= nil then
					MoneyCollectedRE:FireClient(plr, standModel, collected, incomeToastDisplayPayload)
				else
					MoneyCollectedRE:FireClient(plr, standModel, collected)
				end
			end
			phaseAction("client_event", {
				Result = if MoneyCollectedRE then "ok" else "skipped",
				Reason = if MoneyCollectedRE then nil else "missing_remote",
			})

			updateStandMoneyText(plr, standModel)
			phaseAction("prompt_refresh", {
				Result = "ok",
			})
			finishAction("ok", {
				WriteCount = writeCount,
			})
		end)
		cache.Connections.ZoneTouched = cache.ZoneTouchedConnection
	end


	ctx.bindZoneCollect = bindZoneCollect
	ctx.fireMoneyCollected = fireMoneyCollected
	ctx.getHitBoxPart = getHitBoxPart
	ctx.waitForPlot = waitForPlot
end

return Module
