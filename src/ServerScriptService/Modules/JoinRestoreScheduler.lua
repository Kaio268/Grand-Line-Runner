local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local JoinRestoreScheduler = {}

local HEARTBEAT_BUDGET_SECONDS = 0.003
local MAX_STEPS_PER_HEARTBEAT = 48
local MAX_STEPS_PER_PLAYER_PER_HEARTBEAT = 1
local SLOW_PHASE_SECONDS = 0.025
local GENERATION_ATTRIBUTE = "GTRJoinRestoreGeneration"

local queuesByPlayer = {}
local activePlayers = {}
local activePlayerSet = {}
local roundRobinIndex = 1
local heartbeatConnection = nil
local processing = false
local pendingJobs = 0
local sequence = 0

local stats = {
	Enqueued = 0,
	Completed = 0,
	Cancelled = 0,
	Failed = 0,
	SkippedStale = 0,
}

local function isDebugEnabled()
	return game:GetAttribute("GTRJoinDebug") == true
end

local function getPlayerName(player)
	return tostring(player and player.Name or "unknown")
end

local function getUserId(player)
	return tostring(player and player.UserId or 0)
end

local function getQueueState(player)
	local state = queuesByPlayer[player]
	if state then
		return state
	end

	state = {
		Count = 0,
		Generation = tonumber(player and player:GetAttribute(GENERATION_ATTRIBUTE)) or 0,
		Jobs = {},
		JobsByKey = {},
	}
	queuesByPlayer[player] = state
	return state
end

local function getPendingPlayerCount()
	local count = 0
	for player, state in pairs(queuesByPlayer) do
		if player.Parent == Players and state.Count > 0 then
			count += 1
		end
	end
	return count
end

local function logJoin(player, phase, durationSeconds, result, metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	durationSeconds = tonumber(durationSeconds) or 0
	local shouldLog = metadata.Always == true or isDebugEnabled() or durationSeconds >= SLOW_PHASE_SECONDS
	if not shouldLog then
		return
	end

	local suffix = ""
	local cursorIndex = metadata.CursorIndex or metadata.cursorIndex
	local cursorCount = metadata.CursorCount or metadata.cursorCount
	if cursorIndex ~= nil and cursorCount ~= nil then
		suffix ..= string.format(" cursor=%s/%s", tostring(cursorIndex), tostring(cursorCount))
	end

	print(string.format(
		"[GTR_JOIN] player=%s userId=%s phase=%s durationMs=%.3f jobsProcessed=%s pendingJobs=%s budgetExceeded=%s generation=%s result=%s",
		getPlayerName(player),
		getUserId(player),
		tostring(phase or "unknown"),
		durationSeconds * 1000,
		tostring(metadata.JobsProcessed or metadata.jobsProcessed or 0),
		tostring(metadata.PendingJobs or pendingJobs),
		tostring(metadata.BudgetExceeded == true or metadata.budgetExceeded == true),
		tostring(metadata.Generation or metadata.generation or ""),
		tostring(result or metadata.Result or "ok")
	) .. suffix)
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
	if player then
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

local function sortQueue(state)
	table.sort(state.Jobs, function(left, right)
		local leftPriority = tonumber(left.Priority) or 1000
		local rightPriority = tonumber(right.Priority) or 1000
		if leftPriority == rightPriority then
			return (left.Sequence or 0) < (right.Sequence or 0)
		end
		return leftPriority < rightPriority
	end)
end

local function callCancel(job, reason)
	if typeof(job.OnCancel) ~= "function" then
		return
	end
	pcall(job.OnCancel, job, reason)
end

local function clearQueue(player, reason)
	local state = queuesByPlayer[player]
	if not state then
		return false, "not_queued"
	end

	for _, job in ipairs(state.Jobs) do
		callCancel(job, reason or "cancelled")
	end
	pendingJobs = math.max(0, pendingJobs - state.Count)
	stats.Cancelled += state.Count
	queuesByPlayer[player] = nil
	removeActivePlayer(player)
	return true, tostring(reason or "cancelled")
end

local function validateJob(job)
	local player = job.Player
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "player_unavailable"
	end

	local state = queuesByPlayer[player]
	if not state then
		return false, "queue_missing"
	end

	local expectedGeneration = tonumber(job.Generation)
	if expectedGeneration ~= nil and expectedGeneration ~= tonumber(state.Generation) then
		return false, "stale_generation"
	end

	return true, nil
end

local function runJobStep(job, deadline)
	local valid, invalidReason = validateJob(job)
	if not valid then
		stats.SkippedStale += 1
		return true, invalidReason
	end

	local startedAt = os.clock()
	local ok, doneOrErr, reason = xpcall(function()
		return job.Step(job, deadline)
	end, debug.traceback)
	local duration = os.clock() - startedAt

	if not ok then
		stats.Failed += 1
		warn(("[GTR_JOIN] player=%s userId=%s phase=%s durationMs=%.3f jobsProcessed=1 pendingJobs=%d budgetExceeded=%s generation=%s result=error reason=%s"):format(
			getPlayerName(job.Player),
			getUserId(job.Player),
			tostring(job.Phase or "unknown"),
			duration * 1000,
			pendingJobs,
			tostring(os.clock() >= deadline),
			tostring(job.Generation or ""),
			tostring(doneOrErr)
		))
		return true, "error"
	end

	local done = doneOrErr == true
	if done then
		stats.Completed += 1
		logJoin(job.Player, job.Phase, duration, reason or "ok", {
			Always = job.AlwaysLog == true,
			JobsProcessed = 1,
			BudgetExceeded = os.clock() >= deadline,
			Generation = job.Generation,
			CursorIndex = job.CursorIndex,
			CursorCount = job.CursorCount,
		})
	end
	return done, reason
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
	if processing or pendingJobs <= 0 then
		return
	end

	processing = true
	local startedAt = os.clock()
	local deadline = startedAt + HEARTBEAT_BUDGET_SECONDS
	local stepsStarted = 0
	local stepsByPlayer = {}
	local visitsWithoutWork = 0

	while pendingJobs > 0
		and stepsStarted < MAX_STEPS_PER_HEARTBEAT
		and os.clock() < deadline
		and #activePlayers > 0
		and visitsWithoutWork < #activePlayers
	do
		if roundRobinIndex > #activePlayers then
			roundRobinIndex = 1
		end

		local player = activePlayers[roundRobinIndex]
		local state = queuesByPlayer[player]
		if typeof(player) ~= "Instance" or player.Parent ~= Players or not state or state.Count <= 0 then
			if state then
				clearQueue(player, "inactive")
			else
				removeActivePlayerAt(roundRobinIndex)
			end
		elseif (stepsByPlayer[player] or 0) >= MAX_STEPS_PER_PLAYER_PER_HEARTBEAT then
			roundRobinIndex += 1
			visitsWithoutWork += 1
		else
			local job = state.Jobs[1]
			stepsByPlayer[player] = (stepsByPlayer[player] or 0) + 1
			stepsStarted += 1
			visitsWithoutWork = 0

			local done = runJobStep(job, deadline)
			if done then
				table.remove(state.Jobs, 1)
				state.JobsByKey[job.Key] = nil
				state.Count -= 1
				pendingJobs = math.max(0, pendingJobs - 1)
			else
				sortQueue(state)
			end

			if not queuesByPlayer[player] or state.Count <= 0 then
				removeActivePlayerAt(roundRobinIndex)
			else
				roundRobinIndex += 1
			end
		end
	end

	if stepsStarted > 0 then
		logJoin(nil, "scheduler_pass", os.clock() - startedAt, "ok", {
			JobsProcessed = stepsStarted,
			BudgetExceeded = os.clock() >= deadline,
			PendingJobs = pendingJobs,
		})
	end

	processing = false
	if pendingJobs <= 0 and heartbeatConnection ~= nil then
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
	end
end

function JoinRestoreScheduler.BeginPlayerRestore(player, reason, generationOverride)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 0
	end

	clearQueue(player, reason or "new_restore")
	local generation = tonumber(generationOverride)
	if generation == nil then
		generation = (tonumber(player:GetAttribute(GENERATION_ATTRIBUTE)) or 0) + 1
	end
	player:SetAttribute(GENERATION_ATTRIBUTE, generation)
	local state = getQueueState(player)
	state.Generation = generation
	logJoin(player, "begin", 0, tostring(reason or "restore"), {
		Always = true,
		Generation = generation,
	})
	return generation
end

function JoinRestoreScheduler.Log(player, phase, durationSeconds, result, metadata)
	logJoin(player, phase, durationSeconds, result, metadata)
end

function JoinRestoreScheduler.Enqueue(player, job)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end
	if typeof(job) ~= "table" or typeof(job.Step) ~= "function" then
		return false, "invalid_job"
	end

	local state = getQueueState(player)
	local key = tostring(job.Key or job.Phase or "job")
	local existing = state.JobsByKey[key]
	if existing then
		existing.Step = job.Step
		existing.Phase = job.Phase or existing.Phase
		existing.Priority = job.Priority or existing.Priority
		existing.Generation = job.Generation or existing.Generation
		existing.Source = job.Source or existing.Source
		existing.OnCancel = job.OnCancel or existing.OnCancel
		sortQueue(state)
		return false, "updated_pending"
	end

	sequence += 1
	job.Player = player
	job.Key = key
	job.Sequence = sequence
	job.Generation = if job.Generation ~= nil then job.Generation else state.Generation
	job.EnqueuedAt = os.clock()
	state.JobsByKey[key] = job
	state.Jobs[#state.Jobs + 1] = job
	state.Count += 1
	pendingJobs += 1
	stats.Enqueued += 1
	sortQueue(state)
	addActivePlayer(player)
	ensureHeartbeat()
	return true, "enqueued"
end

function JoinRestoreScheduler.CancelPlayer(player, reason)
	return clearQueue(player, reason)
end

function JoinRestoreScheduler.GetStats()
	return {
		ActivePlayers = getPendingPlayerCount(),
		PendingJobs = pendingJobs,
		Enqueued = stats.Enqueued,
		Completed = stats.Completed,
		Cancelled = stats.Cancelled,
		Failed = stats.Failed,
		SkippedStale = stats.SkippedStale,
	}
end

function JoinRestoreScheduler.GetActionContext()
	local snapshot = JoinRestoreScheduler.GetStats()
	return {
		joinRestoreActive = snapshot.PendingJobs > 0,
		joinRestorePlayers = snapshot.ActivePlayers,
		pendingJoinJobs = snapshot.PendingJobs,
	}
end

function JoinRestoreScheduler.IsPlayerActive(player)
	local state = queuesByPlayer[player]
	return state ~= nil and state.Count > 0
end

Players.PlayerRemoving:Connect(function(player)
	clearQueue(player, "player_removing")
end)

return JoinRestoreScheduler
