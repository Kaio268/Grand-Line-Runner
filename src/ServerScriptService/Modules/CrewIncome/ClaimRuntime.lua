local Module = {}

function Module.Install(ctx)
	local function buildIncomeToastDisplayPayload(...)
		return ctx.buildIncomeToastDisplayPayload(...)
	end
	local CrewStandIncomeAuthority = ctx.CrewStandIncomeAuthority
	local CurrencyUtil = ctx.CurrencyUtil
	local DataManager = ctx.DataManager
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
	local function getStandCollectMultiplier(...)
		return ctx.getStandCollectMultiplier(...)
	end
	local IncomeClaimMath = ctx.IncomeClaimMath
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

			if not dmEnsureStandFolder(plr, standName) then
				return
			end
			local collectedCrewMemberName = getPlayerStandCrewMemberName(plr, standName)

			local slotState = getStandSlotState(plr, standName)
			if slotState.Visible and not slotState.Usable then
				updateStandMoneyText(plr, standModel)
				return
			end

			local baseToCollect = getPlayerStandIncome(plr, standName)
			if baseToCollect <= 0 then
				updateStandMoneyText(plr, standModel)
				return
			end

			local mult = getStandCollectMultiplier(plr, standName)
			local collected = IncomeClaimMath.GetWholeClaimableAmount(baseToCollect, mult)
			if collected <= 0 then
				updateStandMoneyText(plr, standModel)
				return
			end

			local remainingRawIncome = IncomeClaimMath.GetRawRemainderAfterClaim(baseToCollect, mult, collected)
			if CrewStandIncomeAuthority.SetIncomeToCollect(plr, standName, remainingRawIncome, "income_collect") then
				refreshCollectedIncomeShadow(plr)
			else
				return
			end

			DataManager:AddValue(plr, CurrencyUtil.getPrimaryPath(), collected)
			DataManager:AddValue(plr, CurrencyUtil.getTotalPath(), collected)
			QuestSignals.Record(plr, "EarnBeli", collected, {
				Source = "StandIncome",
				StandName = standName,
			})

			local incomeToastDisplayPayload = buildIncomeToastDisplayPayload(plr, collectedCrewMemberName)
			if MoneyCollectedRE then
				if incomeToastDisplayPayload ~= nil then
					MoneyCollectedRE:FireClient(plr, standModel, collected, incomeToastDisplayPayload)
				else
					MoneyCollectedRE:FireClient(plr, standModel, collected)
				end
			end

			updateStandMoneyText(plr, standModel)
		end)
		cache.Connections.ZoneTouched = cache.ZoneTouchedConnection
	end


	ctx.bindZoneCollect = bindZoneCollect
	ctx.fireMoneyCollected = fireMoneyCollected
	ctx.getHitBoxPart = getHitBoxPart
	ctx.waitForPlot = waitForPlot
end

return Module
