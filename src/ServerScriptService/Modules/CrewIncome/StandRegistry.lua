local Module = {}

function Module.Install(ctx)
	local function bindStandPrompt(...)
		return ctx.bindStandPrompt(...)
	end
	local CaptainSlotRuntime = ctx.CaptainSlotRuntime
	local function cancelCrewVisualRestoresForPlayer(...)
		if typeof(ctx.cancelCrewVisualRestoresForPlayer) == "function" then
			return ctx.cancelCrewVisualRestoresForPlayer(...)
		end

		return false, "visual_restore_queue_unavailable"
	end
	local function cleanupPlayerSlotRuntime(...)
		return ctx.cleanupPlayerSlotRuntime(...)
	end
	local function cleanupSlotRuntime(...)
		return ctx.cleanupSlotRuntime(...)
	end
	local function clearCrewRecordCache(...)
		return ctx.clearCrewRecordCache(...)
	end
	local function clearPlacedStandIncome(...)
		return ctx.clearPlacedStandIncome(...)
	end
	local function clearStandVisual(...)
		return ctx.clearStandVisual(...)
	end
	local CrewFoodProgression = ctx.CrewFoodProgression
	local CrewInstanceService = ctx.CrewInstanceService
	local JoinRestoreScheduler = ctx.JoinRestoreScheduler
	local ensuredStandFolders = ctx.ensuredStandFolders
	local function formatInstancePath(...)
		return ctx.formatInstancePath(...)
	end
	local function formatVector3(...)
		return ctx.formatVector3(...)
	end
	local function getCrewMemberLevel(...)
		return ctx.getCrewMemberLevel(...)
	end
	local function getIncomeWithLevel(...)
		return ctx.getIncomeWithLevel(...)
	end
	local function getPlayerStandCrewMemberInstanceId(...)
		return ctx.getPlayerStandCrewMemberInstanceId(...)
	end
	local function getPlayerStandCrewMemberName(...)
		return ctx.getPlayerStandCrewMemberName(...)
	end
	local function getSlotRuntime(...)
		return ctx.getSlotRuntime(...)
	end
	local function getStandSlotState(...)
		return ctx.getStandSlotState(...)
	end
	local placementPickupGuardUntil = ctx.placementPickupGuardUntil
	local playerStandList = ctx.playerStandList
	local function plotTrace(...)
		return ctx.plotTrace(...)
	end
	local function reconcileSlotAssignmentsForRender(...)
		return ctx.reconcileSlotAssignmentsForRender(...)
	end
	local function refreshPlayerIncomeDisplaysAfterLifecycleUpdate(...)
		return ctx.refreshPlayerIncomeDisplaysAfterLifecycleUpdate(...)
	end
	local function resolveSlotHandle(...)
		return ctx.resolveSlotHandle(...)
	end
	local function saveTrace(...)
		return ctx.saveTrace(...)
	end
	local function setStandLevel(...)
		return ctx.setStandLevel(...)
	end
	local ShipRuntimeService = ctx.ShipRuntimeService
	local ShipSlotService = ctx.ShipSlotService
	local PlacedCrewState = require(ctx.Modules:WaitForChild("Crew"):WaitForChild("PlacedCrewState"))
	local function enqueueCrewVisualRestore(...)
		if typeof(ctx.enqueueCrewVisualRestore) == "function" then
			return ctx.enqueueCrewVisualRestore(...)
		end

		return false, "visual_restore_queue_unavailable"
	end
	local standCommandFunction = ctx.standCommandFunction
	local function standDebug(...)
		return ctx.standDebug(...)
	end
	local function syncStandLevelFromCrewMember(...)
		return ctx.syncStandLevelFromCrewMember(...)
	end
	local touchDebounce = ctx.touchDebounce
	local function updateLevelUpUI(...)
		return ctx.updateLevelUpUI(...)
	end
	local function updateStandHover(...)
		return ctx.updateStandHover(...)
	end
	local function updateStandMoneyText(...)
		return ctx.updateStandMoneyText(...)
	end
	local function updateStandPromptTexts(...)
		return ctx.updateStandPromptTexts(...)
	end
	local function waitForPlot(...)
		return ctx.waitForPlot(...)
	end

	local function registerStand(player, plot, standModel, options)
		options = if typeof(options) == "table" then options else {}
		standDebug("registerStand begin player=%s stand=%s", player.Name, standModel.Name)
		saveTrace(
			"registerStand begin player=%s userId=%s plot=%s stand=%s standPath=%s ownerUserId=%s ownerName=%s",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(plot),
			tostring(standModel.Name),
			formatInstancePath(standModel),
			tostring(plot and plot:GetAttribute("OwnerUserId")),
			tostring(plot and plot:GetAttribute("OwnerName"))
		)
		local list = playerStandList[player]
		if not list then
			list = {}
			playerStandList[player] = list
		end
		local cache = getSlotRuntime(player, plot, standModel)

		for i = 1, #list do
			if list[i] == standModel then
				standDebug("registerStand reuse player=%s stand=%s", player.Name, standModel.Name)
				bindStandPrompt(player, plot, standModel)
				local slotState = getStandSlotState(player, standModel.Name)
				local crewMemberName = getPlayerStandCrewMemberName(player, standModel.Name)
				local crewMemberInstanceId = if crewMemberName ~= "" then getPlayerStandCrewMemberInstanceId(player, standModel.Name) else ""
				updateStandMoneyText(player, standModel, cache, slotState, crewMemberName)
				local totalFoodCount = nil
				if typeof(CrewFoodProgression.TryGetTotalFoodCount) == "function" then
					totalFoodCount = CrewFoodProgression.TryGetTotalFoodCount(player)
				else
					totalFoodCount = CrewFoodProgression.GetTotalFoodCount(player)
				end
				if totalFoodCount == nil then
					return
				end
				updateLevelUpUI(
					player,
					standModel,
					cache,
					slotState,
					crewMemberName,
					crewMemberInstanceId,
					true,
					totalFoodCount
				)
				updateStandPromptTexts(player, standModel, cache, slotState, crewMemberName)
				return
			end
		end

		table.insert(list, standModel)

		bindStandPrompt(player, plot, standModel)
		standDebug("registerStand after bindStandPrompt player=%s stand=%s", player.Name, standModel.Name)

		local function runStandInit()
			standDebug("registerStand init-task begin player=%s stand=%s", player.Name, standModel.Name)
			local ok, err = xpcall(function()
				standDebug("registerStand before handle lookup player=%s stand=%s", player.Name, standModel.Name)
				local handle = cache and cache.Handle or resolveSlotHandle(standModel)
				standDebug("registerStand after handle lookup player=%s stand=%s handle=%s", player.Name, standModel.Name, tostring(handle ~= nil))
				if handle and handle:IsA("BasePart") then
					standDebug("registerStand before savedName lookup player=%s stand=%s", player.Name, standModel.Name)
					local name = getPlayerStandCrewMemberName(player, standModel.Name)
					local savedInstanceId = getPlayerStandCrewMemberInstanceId(player, standModel.Name)
					saveTrace(
						"restoreCheck player=%s userId=%s plot=%s stand=%s savedName=%s savedInstanceId=%s handle=%s",
						player.Name,
						tostring(player.UserId),
						formatInstancePath(plot),
						tostring(standModel.Name),
						tostring(name),
						tostring(savedInstanceId),
						formatInstancePath(handle)
					)
					standDebug("registerStand after savedName lookup player=%s stand=%s savedName=%s", player.Name, standModel.Name, tostring(name))
					if name ~= "" then
						local slotState = getStandSlotState(player, standModel.Name)
						if not slotState.Usable then
							saveTrace(
								"restoreDeferred player=%s userId=%s stand=%s savedName=%s reason=slot_locked level=%s",
								player.Name,
								tostring(player.UserId),
								tostring(standModel.Name),
								tostring(name),
								tostring(slotState.Level)
							)
							clearStandVisual(standModel)
							updateStandMoneyText(player, standModel, cache, slotState, name)
							updateLevelUpUI(player, standModel, cache, slotState, name, savedInstanceId, true)
							updateStandPromptTexts(player, standModel, cache, slotState, name)
							return
						end

						standDebug("registerStand savedCrewMember branch entered player=%s stand=%s", player.Name, standModel.Name)
						standDebug("registerStand restore-begin player=%s stand=%s savedName=%s", player.Name, standModel.Name, tostring(name))
						standDebug("registerStand before ensureStandInstance player=%s stand=%s", player.Name, standModel.Name)
						local restoredInstanceId, restoredInstance = CrewInstanceService.EnsureStandInstance(player, standModel.Name, name)
						local persistedName = restoredInstance and restoredInstance.StorageName or name
						saveTrace(
							"restoreLookup player=%s userId=%s stand=%s requestedName=%s restoredInstanceId=%s persistedName=%s",
							player.Name,
							tostring(player.UserId),
							tostring(standModel.Name),
							tostring(name),
							tostring(restoredInstanceId),
							tostring(persistedName)
						)
						standDebug("registerStand after ensureStandInstance player=%s stand=%s instanceId=%s persisted=%s", player.Name, standModel.Name, tostring(restoredInstanceId), tostring(persistedName))
						name = persistedName
						standDebug("registerStand before getCrewMemberLevel player=%s stand=%s", player.Name, standModel.Name)
						getCrewMemberLevel(player, restoredInstanceId ~= nil and tostring(restoredInstanceId) ~= "" and restoredInstanceId or name)
						standDebug("registerStand after getCrewMemberLevel player=%s stand=%s", player.Name, standModel.Name)
						standDebug("registerStand before syncStandLevelFromCrewMember player=%s stand=%s", player.Name, standModel.Name)
						syncStandLevelFromCrewMember(player, standModel.Name, restoredInstanceId ~= nil and tostring(restoredInstanceId) ~= "" and restoredInstanceId or name)
						standDebug("registerStand after syncStandLevelFromCrewMember player=%s stand=%s", player.Name, standModel.Name)
						standDebug("registerStand before enqueueCrewVisualRestore player=%s stand=%s", player.Name, standModel.Name)
						local generation = ShipRuntimeService.GetCrewVisualGeneration(player)
						local stateActive = standModel:GetAttribute(PlacedCrewState.Attribute.Active) == true
						local stateCrewName = tostring(standModel:GetAttribute(PlacedCrewState.Attribute.CrewMemberName) or "")
						local stateInstanceId = tostring(standModel:GetAttribute(PlacedCrewState.Attribute.CrewMemberInstanceId) or "")
						local restoredInstanceKey = tostring(restoredInstanceId or "")
						local stateGeneration = tonumber(standModel:GetAttribute(PlacedCrewState.Attribute.VisualGeneration))
						local identityChanged = stateCrewName ~= tostring(name)
							or (restoredInstanceKey ~= "" and stateInstanceId ~= restoredInstanceKey)
						local shouldRefreshState = stateActive ~= true
							or identityChanged
							or stateGeneration ~= generation
						local visualQueued, visualQueueReason = false, "already_spawned"
						if stateActive ~= true then
							visualQueued, visualQueueReason = enqueueCrewVisualRestore(player, standModel, handle, name, {
								CrewMemberInstanceId = tostring(restoredInstanceId or ""),
								Generation = generation,
								Source = "stand_registry_restore",
							})
						end
						local placedModel = standModel:FindFirstChild("PlacedCrewMember")
						saveTrace(
							"restoreQueued player=%s userId=%s stand=%s savedName=%s restoredInstanceId=%s visualQueued=%s visualQueueReason=%s placedModel=%s placedPivot=%s",
							player.Name,
							tostring(player.UserId),
							tostring(standModel.Name),
							tostring(name),
							tostring(restoredInstanceId),
							tostring(visualQueued),
							tostring(visualQueueReason),
							formatInstancePath(placedModel),
							formatVector3(placedModel and placedModel:IsA("Model") and placedModel:GetPivot().Position or nil)
						)
						standDebug("registerStand after enqueueCrewVisualRestore player=%s stand=%s reason=%s", player.Name, standModel.Name, tostring(visualQueueReason))
						if shouldRefreshState then
							standDebug("registerStand before updateStandHover player=%s stand=%s", player.Name, standModel.Name)
							updateStandHover(player, standModel, name, {
								Reason = "stand_registry_restore",
								RefreshIncomeTimestamp = stateActive ~= true or identityChanged,
								RefreshUpdatedTimestamp = true,
							})
							standDebug("registerStand after updateStandHover player=%s stand=%s", player.Name, standModel.Name)
						end
						standDebug("registerStand restore-done player=%s stand=%s incomePerTick=%s", player.Name, standModel.Name, tostring(getIncomeWithLevel(player, name, restoredInstanceId)))
					else
						saveTrace(
							"restoreSkipped player=%s userId=%s stand=%s reason=empty_saved_name",
							player.Name,
							tostring(player.UserId),
							tostring(standModel.Name)
						)
						standDebug("registerStand empty branch entered player=%s stand=%s", player.Name, standModel.Name)
						clearPlacedStandIncome(player, standModel.Name)
						setStandLevel(player, standModel.Name, 1)
						clearStandVisual(standModel)
						standDebug("registerStand empty player=%s stand=%s", player.Name, standModel.Name)
					end
				end

				standDebug("registerStand before setMoneyText player=%s stand=%s", player.Name, standModel.Name)
				updateStandMoneyText(player, standModel, cache)
				standDebug("registerStand after setMoneyText player=%s stand=%s", player.Name, standModel.Name)
				standDebug("registerStand before updateLevelUpUI player=%s stand=%s", player.Name, standModel.Name)
				updateLevelUpUI(player, standModel, cache, nil, nil, nil, true)
				standDebug("registerStand after updateLevelUpUI player=%s stand=%s", player.Name, standModel.Name)
			end, debug.traceback)

			if not ok then
				standDebug("registerStand init-task error player=%s stand=%s err=%s", player.Name, standModel.Name, tostring(err))
				warn(("[CrewIncomeRuntime] Failed to initialize crew slot %s for %s: %s"):format(
					standModel:GetFullName(),
					player.Name,
					tostring(err)
				))
			end
		end

		if options.DeferInit == false then
			runStandInit()
		else
			task.spawn(runStandInit)
		end
	end


	local plotScanBound = {} 

	local function waitForStandContainer(plot, _timeout)
		if ShipRuntimeService.IsActiveShip(plot) then
			return plot, "ship"
		end

		return nil, nil
	end

	local function scanAndBindShipSlots(player, activeShip)
		local slotNumbers = ShipSlotService.GetAvailableSlotNumbers(activeShip)
		if #slotNumbers == 0 then
			warn(("[CrewIncomeRuntime] Active ship has no numbered crew slots with Handles: %s"):format(activeShip:GetFullName()))
			return
		end

		for _, slotNumber in ipairs(slotNumbers) do
			local slotModel = ShipSlotService.GetSlot(activeShip, slotNumber)
			if slotModel and slotModel:IsA("Model") then
				registerStand(player, activeShip, slotModel)
			elseif slotModel then
				warn(("[CrewIncomeRuntime] Ship slot %s is not a Model and cannot host crew visuals yet: %s"):format(
					tostring(slotNumber),
					slotModel:GetFullName()
				))
			end
		end
	end

	local function scanAndBindCaptainSlot(player, activeShip)
		CaptainSlotRuntime.RefreshPlayer(player, activeShip)
	end

	local function scanAndBindPlot(player, plot)
		standDebug("scanAndBindPlot begin player=%s plot=%s", player and player.Name or "nil", plot and plot:GetFullName() or "nil")
		plotTrace(
			"scanAndBindPlot player=%s userId=%s plot=%s ownerUserId=%s ownerName=%s",
			player and player.Name or "nil",
			tostring(player and player.UserId or "nil"),
			formatInstancePath(plot),
			tostring(plot and plot:GetAttribute("OwnerUserId")),
			tostring(plot and plot:GetAttribute("OwnerName"))
		)
		if not player or not player.Parent then
			standDebug("scanAndBindPlot abort reason=invalid_player")
			saveTrace("scanAndBindPlot skipped player=<nil> reason=invalid_player")
			return
		end
		if not plot or not plot.Parent then
			standDebug("scanAndBindPlot abort player=%s reason=invalid_plot", player.Name)
			saveTrace("scanAndBindPlot skipped player=%s userId=%s reason=invalid_plot", player.Name, tostring(player.UserId))
			return
		end

		if plotScanBound[plot] then
			standDebug("scanAndBindPlot skip player=%s plot=%s reason=already_bound", player.Name, plot:GetFullName())
			saveTrace("scanAndBindPlot skipped player=%s userId=%s plot=%s reason=already_bound", player.Name, tostring(player.UserId), formatInstancePath(plot))
			return
		end
		plotScanBound[plot] = true

		local stands, containerKind = waitForStandContainer(plot, 25)
		if not stands or containerKind ~= "ship" then
			standDebug("scanAndBindPlot failed player=%s plot=%s reason=no_active_ship_slots", player.Name, plot:GetFullName())
			saveTrace(
				"scanAndBindPlot failed player=%s userId=%s plot=%s reason=no_active_ship_slots",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(plot)
			)
			plotScanBound[plot] = nil
			return
		end
		standDebug("scanAndBindPlot active_ship player=%s ship=%s", player.Name, stands:GetFullName())
		reconcileSlotAssignmentsForRender(player, plot, "scan_and_bind_ship")
		scanAndBindShipSlots(player, plot)
		scanAndBindCaptainSlot(player, plot)
	end

	local function clearBoundStateForStand(standModel)
		if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
			return
		end

		cleanupSlotRuntime(standModel)
	end

	local function clearPlotScanStateForPlayer(player)
		for plot in pairs(plotScanBound) do
			if not plot or not plot.Parent then
				plotScanBound[plot] = nil
			else
				local ownerUserId = plot:GetAttribute("OwnerUserId")
				local ownerName = plot:GetAttribute("OwnerName")
				if ownerUserId == player.UserId or plot.Name == player.Name or ownerName == player.Name then
					plotScanBound[plot] = nil
				end
			end
		end
	end

	local reconcilePlayerStandAssignments

	local function clearPlayerStandRuntime(player)
		cancelCrewVisualRestoresForPlayer(player, "stand_runtime_clear")

		local stands = playerStandList[player]
		if stands then
			for i = 1, #stands do
				clearBoundStateForStand(stands[i])
			end
		end

		CaptainSlotRuntime.CleanupPlayer(player)
		playerStandList[player] = nil
		cleanupPlayerSlotRuntime(player)
		ensuredStandFolders[player] = nil
		touchDebounce[player] = nil
		placementPickupGuardUntil[player] = nil
		clearCrewRecordCache(player)
		clearPlotScanStateForPlayer(player)
	end

	local function refreshPlayerStandRuntime(player)
		clearPlayerStandRuntime(player)

		local plot = waitForPlot(player, 10)
		if not plot then
			return false, "active_ship_not_found"
		end

		scanAndBindPlot(player, plot)
		reconcilePlayerStandAssignments(player)
		refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
		return true, plot
	end

	reconcilePlayerStandAssignments = function(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end

		clearCrewRecordCache(player)
		local stands = playerStandList[player]
		if typeof(stands) ~= "table" then
			return
		end

		for i = 1, #stands do
			local standModel = stands[i]
			if standModel and standModel.Parent then
				CrewInstanceService.ReconcileStandAssignment(player, standModel.Name)
			end
		end
	end

	local function queuePlayerStandRuntimeRefresh(player, activeShip, options)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end
		if not JoinRestoreScheduler or typeof(JoinRestoreScheduler.Enqueue) ~= "function" then
			return refreshPlayerStandRuntime(player)
		end

		options = if typeof(options) == "table" then options else {}
		activeShip = if typeof(activeShip) == "Instance" and activeShip:IsA("Model")
			then activeShip
			else ShipRuntimeService.GetActiveShip(player)
		if typeof(activeShip) ~= "Instance" or not activeShip:IsA("Model") then
			return false, "active_ship_not_found"
		end

		local generation = tonumber(options.Generation) or ShipRuntimeService.GetCrewVisualGeneration(player)
		local source = tostring(options.Source or "join_restore")
		if activeShip:GetAttribute("GTRRuntimeShell") == true then
			if JoinRestoreScheduler and typeof(JoinRestoreScheduler.Log) == "function" then
				JoinRestoreScheduler.Log(player, "stand_restore_blocked", 0, "blocked_shell_not_active", {
					Always = true,
					Generation = generation,
				})
			end
			return false, "blocked_shell_not_active"
		end

		clearPlayerStandRuntime(player)
		plotScanBound[activeShip] = true
		saveTrace(
			"queuePlayerStandRuntimeRefresh player=%s userId=%s ship=%s generation=%s source=%s",
			player.Name,
			tostring(player.UserId),
			formatInstancePath(activeShip),
			tostring(generation),
			source
		)

		local function validate()
			return player.Parent ~= nil
				and activeShip.Parent ~= nil
				and ShipRuntimeService.GetActiveShip(player) == activeShip
				and ShipRuntimeService.GetCrewVisualGeneration(player) == generation
		end

		JoinRestoreScheduler.Enqueue(player, {
			Phase = "stand_captain_restore",
			Key = "stand_captain_restore",
			Generation = generation,
			Priority = 200,
			Step = function()
				if not validate() then
					return true, "stale"
				end
				scanAndBindCaptainSlot(player, activeShip)
				return true, "ok"
			end,
		})

		local slotNumbers = ShipSlotService.GetAvailableSlotNumbers(activeShip)
		if #slotNumbers == 0 then
			warn(("[CrewIncomeRuntime] Active ship has no numbered crew slots with Handles: %s"):format(activeShip:GetFullName()))
		end

		for _, slotNumber in ipairs(slotNumbers) do
			local slotName = tostring(slotNumber)
			JoinRestoreScheduler.Enqueue(player, {
				Phase = "stand_register",
				Key = "stand_register:" .. slotName,
				Generation = generation,
				Priority = 300 + (tonumber(slotName) or 999),
				Step = function()
					if not validate() then
						return true, "stale"
					end

					local slotModel = ShipSlotService.GetSlot(activeShip, slotName)
					if slotModel and slotModel:IsA("Model") then
						registerStand(player, activeShip, slotModel, {
							DeferInit = false,
							Source = source,
						})
					elseif slotModel then
						warn(("[CrewIncomeRuntime] Ship slot %s is not a Model and cannot host crew visuals yet: %s"):format(
							tostring(slotName),
							slotModel:GetFullName()
						))
					end
					return true, "ok"
				end,
			})
		end

		JoinRestoreScheduler.Enqueue(player, {
			Phase = "stand_reconcile",
			Key = "stand_reconcile",
			Generation = generation,
			Priority = 20000,
			Step = function()
				if not validate() then
					return true, "stale"
				end
				reconcileSlotAssignmentsForRender(player, activeShip, source .. "_scheduled_repair")
				reconcilePlayerStandAssignments(player)
				return true, "ok"
			end,
		})

		JoinRestoreScheduler.Enqueue(player, {
			Phase = "stand_display_refresh",
			Key = "stand_display_refresh",
			Generation = generation,
			Priority = 20100,
			Step = function()
				if not validate() then
					return true, "stale"
				end
				refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
				return true, "ok"
			end,
		})

		return true, "queued"
	end

	standCommandFunction.OnInvoke = function(action, player, options)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end

		if action == "clear" then
			clearPlayerStandRuntime(player)
			return true
		end

		if action == "refresh" then
			return refreshPlayerStandRuntime(player)
		end

		if action == "queue_refresh" then
			local activeShip = if typeof(options) == "table" and typeof(options.ActiveShip) == "Instance"
				then options.ActiveShip
				else nil
			return queuePlayerStandRuntimeRefresh(player, activeShip, options)
		end

		return false, "unsupported_action"
	end


	ctx.clearBoundStateForStand = clearBoundStateForStand
	ctx.clearPlayerStandRuntime = clearPlayerStandRuntime
	ctx.clearPlotScanStateForPlayer = clearPlotScanStateForPlayer
	ctx.reconcilePlayerStandAssignments = reconcilePlayerStandAssignments
	ctx.refreshPlayerStandRuntime = refreshPlayerStandRuntime
	ctx.queuePlayerStandRuntimeRefresh = queuePlayerStandRuntimeRefresh
	ctx.registerStand = registerStand
	ctx.scanAndBindCaptainSlot = scanAndBindCaptainSlot
	ctx.scanAndBindPlot = scanAndBindPlot
	ctx.scanAndBindShipSlots = scanAndBindShipSlots
	ctx.waitForStandContainer = waitForStandContainer
end

return Module
