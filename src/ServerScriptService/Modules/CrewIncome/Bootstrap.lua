local Module = {}

function Module.Install(ctx)
	local function clearPlayerStandRuntime(...)
		return ctx.clearPlayerStandRuntime(...)
	end
	local function countSavedStandEntries(...)
		return ctx.countSavedStandEntries(...)
	end
	local function countTableEntries(...)
		return ctx.countTableEntries(...)
	end
	local CrewInstanceService = ctx.CrewInstanceService
	local CrewSlotAssignmentReconciler = ctx.CrewSlotAssignmentReconciler
	local DataManager = ctx.DataManager
	local DEBUG_TRACE = ctx.DEBUG_TRACE
	local function formatInstancePath(...)
		return ctx.formatInstancePath(...)
	end
	local function getCrewStorage(...)
		return ctx.getCrewStorage(...)
	end
	local Players = ctx.Players
	local function reconcilePlayerStandAssignments(...)
		return ctx.reconcilePlayerStandAssignments(...)
	end
	local function reconcileSlotAssignmentsForRender(...)
		return ctx.reconcileSlotAssignmentsForRender(...)
	end
	local function refreshPlayerIncomeDisplaysAfterLifecycleUpdate(...)
		return ctx.refreshPlayerIncomeDisplaysAfterLifecycleUpdate(...)
	end
	local function queuePlayerStandRuntimeRefresh(...)
		if typeof(ctx.queuePlayerStandRuntimeRefresh) == "function" then
			return ctx.queuePlayerStandRuntimeRefresh(...)
		end
		return false, "queue_unavailable"
	end
	local function resetHugeIncomeOnJoin(...)
		return ctx.resetHugeIncomeOnJoin(...)
	end
	local function saveTrace(...)
		return ctx.saveTrace(...)
	end
	local function scanAndBindCaptainSlot(...)
		return ctx.scanAndBindCaptainSlot(...)
	end
	local function scanAndBindPlot(...)
		return ctx.scanAndBindPlot(...)
	end
	local ShipRuntimeService = ctx.ShipRuntimeService
	local function standDebug(...)
		return ctx.standDebug(...)
	end
	local function waitForPlot(...)
		return ctx.waitForPlot(...)
	end
	local EQUIPPED_TITLE_ATTRIBUTE = "EquippedTitleId"
	local titleRefreshConnections = setmetatable({}, { __mode = "k" })
	local multiplierRefreshConnections = setmetatable({}, { __mode = "k" })

	local function disconnectTitleRefresh(player)
		local connection = titleRefreshConnections[player]
		if connection then
			connection:Disconnect()
			titleRefreshConnections[player] = nil
		end
	end

	local function disconnectMultiplierRefresh(player)
		local connections = multiplierRefreshConnections[player]
		if not connections then
			return
		end

		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		multiplierRefreshConnections[player] = nil
	end

	local function refreshIncomeDisplaysForTitleChange(player)
		local activeShip = ShipRuntimeService.GetActiveShip(player)
		if activeShip then
			scanAndBindCaptainSlot(player, activeShip)
		end
		refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
	end

	local function bindTitleRefresh(player)
		disconnectTitleRefresh(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end

		titleRefreshConnections[player] = player:GetAttributeChangedSignal(EQUIPPED_TITLE_ATTRIBUTE):Connect(function()
			refreshIncomeDisplaysForTitleChange(player)
		end)
	end

	local function bindMultiplierRefresh(player)
		disconnectMultiplierRefresh(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return
		end

		local connections = {}
		multiplierRefreshConnections[player] = connections

		local function refresh()
			refreshIncomeDisplaysForTitleChange(player)
		end

		local function bindMoneyMult(valueObject)
			if not valueObject or not (valueObject:IsA("NumberValue") or valueObject:IsA("IntValue")) then
				return
			end
			table.insert(connections, valueObject:GetPropertyChangedSignal("Value"):Connect(refresh))
		end

		local function bindMultipliersFolder(folder)
			if not folder then
				return
			end

			bindMoneyMult(folder:FindFirstChild("MoneyMult"))
			table.insert(connections, folder.ChildAdded:Connect(function(child)
				if child.Name == "MoneyMult" then
					bindMoneyMult(child)
					task.defer(refresh)
				end
			end))
			table.insert(connections, folder.ChildRemoved:Connect(function(child)
				if child.Name == "MoneyMult" then
					task.defer(refresh)
				end
			end))
		end

		bindMultipliersFolder(player:FindFirstChild("Multipliers"))
		table.insert(connections, player.ChildAdded:Connect(function(child)
			if child.Name == "Multipliers" then
				bindMultipliersFolder(child)
				task.defer(refresh)
			end
		end))
		table.insert(connections, player.ChildRemoved:Connect(function(child)
			if child.Name == "Multipliers" then
				task.defer(refresh)
			end
		end))
	end

	local function bootstrapExistingCrewIncomePlayer(runtime, player)
		runtime.standDebug("bootstrap existing_player=%s", player.Name)
		bindTitleRefresh(player)
		bindMultiplierRefresh(player)

		local plot = runtime.waitForPlot(player, 5)
		if plot then
			runtime.resetHugeIncomeOnJoin(player)
			local queued = false
			if typeof(runtime.queuePlayerStandRuntimeRefresh) == "function" then
				queued = runtime.queuePlayerStandRuntimeRefresh(player, plot, {
					Source = "bootstrap_existing_player",
				}) == true
			end
			if not queued then
				runtime.scanAndBindPlot(player, plot)
				runtime.reconcilePlayerStandAssignments(player)
				runtime.refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
			end
		else
			runtime.standDebug("bootstrap existing_player=%s reason=no_active_ship", player.Name)
		end
	end

	local function bootstrapExistingCrewIncomePlayers(runtime)
		for _, player in ipairs(runtime.Players:GetPlayers()) do
			task.spawn(bootstrapExistingCrewIncomePlayer, runtime, player)
		end
	end

	local function logSavedShipSnapshot(player, context)
		if not DEBUG_TRACE or not DataManager then
			return
		end

		local ok, result = pcall(function()
			local function read(path)
				if typeof(DataManager.TryGetValue) == "function" then
					local value = DataManager:TryGetValue(player, path)
					return value
				end
				return DataManager:GetValue(player, path)
			end

			local crewMemberIncome = read("CrewMemberIncome")
			local shipSlots = read("Ship.Slots")
			local plotUpgrade = read("HiddenLeaderstats.PlotUpgrade")

			return {
				CrewMemberIncome = crewMemberIncome,
				ShipSlots = shipSlots,
				PlotUpgrade = plotUpgrade,
			}
		end)

		if not ok then
			saveTrace(
				"snapshot context=%s player=%s userId=%s result=lookup_failed reason=%s",
				tostring(context),
				player.Name,
				tostring(player.UserId),
				tostring(result)
			)
			return
		end

		saveTrace(
			"snapshot context=%s player=%s userId=%s plotUpgrade=%s savedStandEntries=%s shipSlots=%s",
			tostring(context),
			player.Name,
			tostring(player.UserId),
			tostring(result.PlotUpgrade),
			tostring(countSavedStandEntries(result.CrewMemberIncome)),
			tostring(countTableEntries(result.ShipSlots))
		)
	end


	CrewInstanceService.RegisterCrewInventorySavedCallback(function(player)
		if player and player.Parent == Players then
			if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
				return
			end

			task.defer(function()
				if CrewSlotAssignmentReconciler.IsResetInProgress(player) then
					return
				end

				local activeShip = ShipRuntimeService.GetActiveShip(player)
				local queued = false
				if activeShip then
					queued = queuePlayerStandRuntimeRefresh(player, activeShip, {
						Generation = ShipRuntimeService.GetCrewVisualGeneration(player),
						Source = "inventory_saved",
					}) == true
				end
				if not queued then
					reconcileSlotAssignmentsForRender(player, activeShip, "inventory_saved")
					if activeShip then
						scanAndBindCaptainSlot(player, activeShip)
					end
					reconcilePlayerStandAssignments(player)
					refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
				end
			end)
		end
	end)


	Players.PlayerAdded:Connect(function(player)
		standDebug("PlayerAdded player=%s", player.Name)
		bindTitleRefresh(player)
		bindMultiplierRefresh(player)
		task.spawn(function()
			saveTrace("PlayerAdded begin player=%s userId=%s event=restore_begin", player.Name, tostring(player.UserId))
			logSavedShipSnapshot(player, "PlayerAdded")
			resetHugeIncomeOnJoin(player)

			local plot = waitForPlot(player, 25)
			if not plot then
				standDebug("PlayerAdded abort player=%s reason=no_active_ship", player.Name)
				saveTrace("PlayerAdded restoreSkipped player=%s userId=%s reason=no_active_ship_owned_by_userid", player.Name, tostring(player.UserId))
				return
			end
			saveTrace(
				"PlayerAdded plotReady player=%s userId=%s plot=%s ownerUserId=%s ownerUserIdType=%s ownerName=%s event=restore_continue",
				player.Name,
				tostring(player.UserId),
				formatInstancePath(plot),
				tostring(plot:GetAttribute("OwnerUserId")),
				typeof(plot:GetAttribute("OwnerUserId")),
				tostring(plot:GetAttribute("OwnerName"))
			)
			local queued = queuePlayerStandRuntimeRefresh(player, plot, {
				Generation = ShipRuntimeService.GetCrewVisualGeneration(player),
				Source = "player_added",
			}) == true
			if not queued then
				scanAndBindPlot(player, plot)
				reconcilePlayerStandAssignments(player)
				refreshPlayerIncomeDisplaysAfterLifecycleUpdate(player)
			end
		end)
	end)


	Players.PlayerRemoving:Connect(function(player)
		disconnectTitleRefresh(player)
		disconnectMultiplierRefresh(player)
		clearPlayerStandRuntime(player)
		getCrewStorage().ClearIncomeShadowSyncState(player)
	end)

	if DataManager and DataManager.HardResetStarting then
		DataManager.HardResetStarting:Connect(function(player)
			if typeof(player) ~= "Instance" or not player:IsA("Player") then
				return
			end

			clearPlayerStandRuntime(player)
			disconnectTitleRefresh(player)
			disconnectMultiplierRefresh(player)
			getCrewStorage().ClearIncomeShadowSyncState(player)
		end)
	end

	task.spawn(bootstrapExistingCrewIncomePlayers, {
		Players = Players,
		standDebug = standDebug,
		waitForPlot = waitForPlot,
		scanAndBindPlot = scanAndBindPlot,
		queuePlayerStandRuntimeRefresh = queuePlayerStandRuntimeRefresh,
		reconcilePlayerStandAssignments = reconcilePlayerStandAssignments,
		resetHugeIncomeOnJoin = resetHugeIncomeOnJoin,
		refreshPlayerIncomeDisplaysAfterLifecycleUpdate = refreshPlayerIncomeDisplaysAfterLifecycleUpdate,
	})


	ctx.bootstrapExistingCrewIncomePlayer = bootstrapExistingCrewIncomePlayer
	ctx.bootstrapExistingCrewIncomePlayers = bootstrapExistingCrewIncomePlayers
	ctx.logSavedShipSnapshot = logSavedShipSnapshot
end

return Module
