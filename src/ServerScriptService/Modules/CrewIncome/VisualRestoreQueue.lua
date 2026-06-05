local Module = {}

local MAX_JOBS_PER_HEARTBEAT = 2
local MAX_JOBS_PER_PLAYER_PER_HEARTBEAT = 1
local HEARTBEAT_TIME_BUDGET_SECONDS = 0.004
local DEBUG_LOG_INTERVAL_SECONDS = 5

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or "")
		if value ~= "" then
			return value
		end
	end

	return ""
end

function Module.Install(ctx)
	local Players = ctx.Players
	local RunService = ctx.RunService
	local CaptainSlotRuntime = ctx.CaptainSlotRuntime
	local ShipRuntimeService = ctx.ShipRuntimeService
	local ShipSlotService = ctx.ShipSlotService
	local PlacedCrewState = require(ctx.Modules:WaitForChild("Crew"):WaitForChild("PlacedCrewState"))
	local OWNER_USER_ID_ATTRIBUTE = (ctx.ShipVisuals.Attributes and ctx.ShipVisuals.Attributes.OwnerUserId) or "OwnerUserId"

	local playerQueues = {}
	local activePlayers = {}
	local activePlayerSet = {}
	local roundRobinIndex = 1
	local sequence = 0
	local pendingJobCount = 0
	local processing = false
	local heartbeatConnection = nil
	local lastDebugLogAt = 0

	local stats = {
		Enqueued = 0,
		Deduped = 0,
		UpdatedPending = 0,
		Completed = 0,
		SkippedStale = 0,
		Failed = 0,
	}

	local function getDebugEnabled()
		return game:GetAttribute("GTRPerformanceDebug") == true
	end

	local function getPendingPlayerCount()
		local count = 0
		for player, queueState in pairs(playerQueues) do
			if player.Parent == Players and queueState.Count > 0 then
				count += 1
			end
		end
		return count
	end

	local function getStatsSnapshot()
		return {
			Enqueued = stats.Enqueued,
			Deduped = stats.Deduped,
			UpdatedPending = stats.UpdatedPending,
			Completed = stats.Completed,
			SkippedStale = stats.SkippedStale,
			Failed = stats.Failed,
			PendingJobs = pendingJobCount,
			PendingPlayers = getPendingPlayerCount(),
		}
	end

	local function logDebugStats()
		if not getDebugEnabled() then
			return
		end
		if pendingJobCount <= 0 then
			return
		end

		local now = os.clock()
		if now - lastDebugLogAt < DEBUG_LOG_INTERVAL_SECONDS then
			return
		end
		lastDebugLogAt = now

		local snapshot = getStatsSnapshot()
		print(string.format(
			"[GTR_PERF] visualQueue pendingJobs=%d pendingPlayers=%d enqueued=%d deduped=%d updatedPending=%d completed=%d skippedStale=%d failed=%d",
			snapshot.PendingJobs,
			snapshot.PendingPlayers,
			snapshot.Enqueued,
			snapshot.Deduped,
			snapshot.UpdatedPending,
			snapshot.Completed,
			snapshot.SkippedStale,
			snapshot.Failed
		))
	end

	local function isCaptainSlotName(slotName)
		return ShipSlotService
			and typeof(ShipSlotService.IsCaptainSlotName) == "function"
			and ShipSlotService.IsCaptainSlotName(slotName) == true
	end

	local function normalizeSlotKey(standModel)
		local standName = tostring(standModel and standModel.Name or "")
		if isCaptainSlotName(standName) then
			return tostring(ctx.CAPTAIN_SLOT_KEY or "Captain")
		end

		if ShipSlotService and typeof(ShipSlotService.NormalizeSlotNumber) == "function" then
			local slotNumber = ShipSlotService.NormalizeSlotNumber(standName)
			if slotNumber ~= nil then
				return tostring(slotNumber)
			end
		end

		return standName
	end

	local function getSlotPriority(standModel, slotKey, options)
		local explicitPriority = tonumber(options and options.Priority)
		if explicitPriority then
			return explicitPriority
		end

		if isCaptainSlotName(standModel and standModel.Name) or slotKey == tostring(ctx.CAPTAIN_SLOT_KEY or "Captain") then
			return 0
		end

		local slotNumber = tonumber(slotKey)
		if slotNumber then
			return 100 + slotNumber
		end

		return 10000
	end

	local function getCaptainAssignment(player)
		if typeof(CaptainSlotRuntime) ~= "table" or typeof(CaptainSlotRuntime.GetAssignment) ~= "function" then
			return "", ""
		end

		local assignment = CaptainSlotRuntime.GetAssignment(player)
		if typeof(assignment) ~= "table" then
			return "", ""
		end

		return firstNonEmpty(
			assignment.CrewMemberName,
			assignment.CrewMemberId,
			assignment.StorageName,
			assignment.LegacyStorageName
		),
			firstNonEmpty(assignment.CrewMemberInstanceId, assignment.InstanceId, assignment.CrewInstanceId)
	end

	local function getCurrentAssignment(player, standModel)
		local standName = tostring(standModel and standModel.Name or "")
		if isCaptainSlotName(standName) then
			return getCaptainAssignment(player)
		end

		local crewName = if typeof(ctx.getPlayerStandCrewMemberName) == "function"
			then tostring(ctx.getPlayerStandCrewMemberName(player, standName) or "")
			else ""
		local instanceId = if crewName ~= "" and typeof(ctx.getPlayerStandCrewMemberInstanceId) == "function"
			then tostring(ctx.getPlayerStandCrewMemberInstanceId(player, standName) or "")
			else ""

		return crewName, instanceId
	end

	local function getRequestedInstanceId(player, standModel, crewMemberName, options)
		local explicitInstanceId = tostring(options and options.CrewMemberInstanceId or "")
		if explicitInstanceId ~= "" then
			return explicitInstanceId
		end

		local _, currentInstanceId = getCurrentAssignment(player, standModel)
		if currentInstanceId ~= "" then
			return currentInstanceId
		end

		return tostring(crewMemberName or "")
	end

	local function getQueueState(player)
		local queueState = playerQueues[player]
		if queueState then
			return queueState
		end

		queueState = {
			Count = 0,
			Jobs = {},
			JobsByKey = {},
		}
		playerQueues[player] = queueState
		return queueState
	end

	local function addActivePlayer(player)
		if activePlayerSet[player] == true then
			return
		end

		activePlayerSet[player] = true
		activePlayers[#activePlayers + 1] = player
	end

	local function removeActivePlayerAt(index)
		local player = activePlayers[index]
		if player ~= nil then
			activePlayerSet[player] = nil
		end

		table.remove(activePlayers, index)
		if #activePlayers == 0 or roundRobinIndex > #activePlayers then
			roundRobinIndex = 1
		end
	end

	local function removeActivePlayer(player)
		for index = #activePlayers, 1, -1 do
			if activePlayers[index] == player then
				removeActivePlayerAt(index)
			end
		end
	end

	local function sortPlayerQueue(queueState)
		table.sort(queueState.Jobs, function(left, right)
			if left.Priority == right.Priority then
				return left.Sequence < right.Sequence
			end
			return left.Priority < right.Priority
		end)
	end

	local function clearPlayerQueue(player, reason)
		local queueState = playerQueues[player]
		if not queueState then
			return false, "not_queued"
		end

		pendingJobCount = math.max(0, pendingJobCount - queueState.Count)
		playerQueues[player] = nil
		removeActivePlayer(player)
		return true, tostring(reason or "cleared")
	end

	local function validateJob(job)
		local player = job.Player
		local standModel = job.StandModel
		local handle = job.Handle

		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
			return false, "player_unavailable"
		end
		if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") or standModel.Parent == nil then
			return false, "stand_unavailable"
		end
		if typeof(handle) ~= "Instance" or not handle:IsA("BasePart") or handle.Parent == nil then
			return false, "handle_unavailable"
		end
		if standModel:GetAttribute(PlacedCrewState.Attribute.Active) == true then
			local stateInstanceId = tostring(standModel:GetAttribute(PlacedCrewState.Attribute.CrewMemberInstanceId) or "")
			if stateInstanceId == "" or stateInstanceId == tostring(job.CrewMemberInstanceId or "") then
				return false, "state_published"
			end
		end
		if tonumber(job.Generation) ~= tonumber(ShipRuntimeService.GetCrewVisualGeneration(player)) then
			return false, "stale_generation"
		end

		local activeShip = ShipRuntimeService.GetActiveShip(player)
		if typeof(activeShip) ~= "Instance" or activeShip.Parent == nil then
			return false, "active_ship_unavailable"
		end
		if activeShip:GetAttribute(OWNER_USER_ID_ATTRIBUTE) ~= player.UserId then
			return false, "active_ship_owner_mismatch"
		end
		if not standModel:IsDescendantOf(activeShip) then
			return false, "stand_not_in_active_ship"
		end

		local currentName, currentInstanceId = getCurrentAssignment(player, standModel)
		if currentName == "" then
			return false, "assignment_empty"
		end
		if tostring(job.CrewMemberName or "") ~= "" and tostring(job.CrewMemberName) ~= currentName then
			return false, "assignment_name_changed"
		end
		if
			tostring(job.CrewMemberInstanceId or "") ~= ""
			and currentInstanceId ~= ""
			and tostring(job.CrewMemberInstanceId) ~= currentInstanceId
		then
			return false, "assignment_instance_changed"
		end

		if not isCaptainSlotName(standModel.Name) and typeof(ctx.getStandSlotState) == "function" then
			local slotState = ctx.getStandSlotState(player, standModel.Name)
			if typeof(slotState) == "table" and slotState.Usable ~= true then
				return false, "slot_unusable"
			end
		end

		return true, currentName
	end

	local function runJob(job)
		local valid, crewNameOrReason = validateJob(job)
		if not valid then
			stats.SkippedStale += 1
			return false, crewNameOrReason
		end

		local ok, placedModel, reason = xpcall(function()
			return ctx.spawnStandCrewMember(job.Player, job.StandModel, job.Handle, crewNameOrReason)
		end, debug.traceback)

		if not ok then
			stats.Failed += 1
			warn(("[GTR_PERF] visualQueue restore failed for %s slot=%s: %s"):format(
				job.Player and job.Player.Name or "unknown",
				tostring(job.SlotKey),
				tostring(placedModel)
			))
			return false, "spawn_error"
		end
		if not placedModel then
			stats.Failed += 1
			return false, tostring(reason or "spawn_failed")
		end

		stats.Completed += 1
		return true, nil
	end

	local processQueue

	local function ensureHeartbeat()
		if heartbeatConnection ~= nil then
			return
		end

		heartbeatConnection = RunService.Heartbeat:Connect(function()
			processQueue()
		end)
	end

	processQueue = function()
		if processing or pendingJobCount <= 0 then
			return
		end

		processing = true
		local startedAt = os.clock()
		local jobsStarted = 0
		local jobsByPlayer = {}
		local visitsWithoutJob = 0

		while pendingJobCount > 0
			and jobsStarted < MAX_JOBS_PER_HEARTBEAT
			and (os.clock() - startedAt) < HEARTBEAT_TIME_BUDGET_SECONDS
			and #activePlayers > 0
			and visitsWithoutJob < #activePlayers
		do
			if roundRobinIndex > #activePlayers then
				roundRobinIndex = 1
			end

			local player = activePlayers[roundRobinIndex]
			local queueState = playerQueues[player]
			if player.Parent ~= Players or not queueState or queueState.Count <= 0 then
				if queueState then
					clearPlayerQueue(player, "inactive")
				else
					removeActivePlayerAt(roundRobinIndex)
				end
			elseif (jobsByPlayer[player] or 0) >= MAX_JOBS_PER_PLAYER_PER_HEARTBEAT then
				roundRobinIndex += 1
				visitsWithoutJob += 1
			else
				local job = table.remove(queueState.Jobs, 1)
				queueState.JobsByKey[job.Key] = nil
				queueState.Count -= 1
				pendingJobCount = math.max(0, pendingJobCount - 1)

				if queueState.Count <= 0 then
					removeActivePlayerAt(roundRobinIndex)
				else
					roundRobinIndex += 1
				end

				jobsByPlayer[player] = (jobsByPlayer[player] or 0) + 1
				jobsStarted += 1
				visitsWithoutJob = 0
				runJob(job)
			end
		end

		logDebugStats()
		processing = false
	end

	local function enqueueCrewVisualRestore(player, standModel, handle, crewMemberName, options)
		options = if typeof(options) == "table" then options else {}
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false, "invalid_player"
		end
		if typeof(standModel) ~= "Instance" or not standModel:IsA("Model") then
			return false, "invalid_stand"
		end
		if typeof(handle) ~= "Instance" or not handle:IsA("BasePart") then
			return false, "invalid_handle"
		end

		local slotKey = normalizeSlotKey(standModel)
		local requestedName = tostring(crewMemberName or "")
		local instanceId = getRequestedInstanceId(player, standModel, requestedName, options)
		local dedupeIdentity = if instanceId ~= "" then instanceId else requestedName
		if dedupeIdentity == "" then
			return false, "missing_crew_identity"
		end

		local key = table.concat({
			tostring(player.UserId),
			slotKey,
			dedupeIdentity,
		}, "|")
		local generation = tonumber(options.Generation)
		if generation == nil then
			generation = ShipRuntimeService.GetCrewVisualGeneration(player)
		end
		local priority = getSlotPriority(standModel, slotKey, options)
		local queueState = getQueueState(player)
		local existing = queueState.JobsByKey[key]
		local activeShip = if typeof(options.ActiveShip) == "Instance"
			then options.ActiveShip
			else ShipRuntimeService.GetActiveShip(player)

		if existing then
			local changed = existing.StandModel ~= standModel
				or existing.Handle ~= handle
				or existing.CrewMemberName ~= requestedName
				or existing.CrewMemberInstanceId ~= instanceId
				or existing.Generation ~= generation
				or existing.Priority ~= priority
				or existing.ActiveShip ~= activeShip

			existing.StandModel = standModel
			existing.Handle = handle
			existing.CrewMemberName = requestedName
			existing.CrewMemberInstanceId = instanceId
			existing.Generation = generation
			existing.Priority = priority
			existing.ActiveShip = activeShip
			existing.Source = tostring(options.Source or existing.Source or "visual_restore")
			existing.UpdatedAt = os.clock()

			if changed then
				stats.UpdatedPending += 1
				sortPlayerQueue(queueState)
				return false, "updated_pending"
			end

			stats.Deduped += 1
			return false, "already_pending"
		end

		sequence += 1
		local job = {
			Key = key,
			Player = player,
			StandModel = standModel,
			Handle = handle,
			CrewMemberName = requestedName,
			CrewMemberInstanceId = instanceId,
			SlotKey = slotKey,
			Generation = generation,
			Priority = priority,
			ActiveShip = activeShip,
			Sequence = sequence,
			Source = tostring(options.Source or "visual_restore"),
			EnqueuedAt = os.clock(),
		}
		queueState.JobsByKey[key] = job
		queueState.Jobs[#queueState.Jobs + 1] = job
		queueState.Count += 1
		pendingJobCount += 1
		stats.Enqueued += 1
		sortPlayerQueue(queueState)
		addActivePlayer(player)
		ensureHeartbeat()

		return true, "enqueued"
	end

	Players.PlayerRemoving:Connect(function(player)
		clearPlayerQueue(player, "player_removing")
	end)

	ctx.enqueueCrewVisualRestore = enqueueCrewVisualRestore
	ctx.cancelCrewVisualRestoresForPlayer = clearPlayerQueue
	ctx.getCrewVisualRestoreQueueStats = getStatsSnapshot
	ctx.processCrewVisualRestoreQueue = processQueue
	if
		ctx.GTRPerformanceDiagnostics
		and typeof(ctx.GTRPerformanceDiagnostics.SetQueueStatsProvider) == "function"
	then
		ctx.GTRPerformanceDiagnostics.SetQueueStatsProvider(getStatsSnapshot)
	end
end

return Module
