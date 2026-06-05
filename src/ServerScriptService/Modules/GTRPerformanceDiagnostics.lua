local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local PlacedCrewState = require(Modules:WaitForChild("Crew"):WaitForChild("PlacedCrewState"))

local Diagnostics = {}

local LOG_PREFIX = "[GTR_PERF]"
local SUMMARY_INTERVAL_SECONDS = 5
local HEARTBEAT_SPIKE_SECONDS = 0.08
local CACHE_SCAN_BUDGET_SECONDS = 0.004
local COUNTER_QUEUE_BUDGET_SECONDS = 0.002
local MAX_COUNTER_QUEUE_SIZE = 2000

local started = false
local cachedCountersStarted = false
local queueStatsProvider = nil
local standCountsProvider = nil
local lastDebugEnabled = false
local counterQueue = {}
local counterQueueHead = 1
local queuedCounterJobs = {}
local visualStats = {
	PlacedServerVisuals = 0,
	Humanoids = 0,
	Animators = 0,
	AuraVfx = 0,
	Descendants = 0,
}
local trackedVisuals = {}
local trackedPlacedStates = {}
local placedStateActiveCount = 0
local counters = {
	BankLoopDurationSeconds = 0,
	BankLoopPlayers = 0,
	BankLoopStands = 0,
	BankLoopOccupiedStands = 0,
	IncomeWrites = 0,
	DisplayUpdates = 0,
	WorldUiUpdates = 0,
	HeartbeatSpikeMs = 0,
}

local function debugEnabled()
	return game:GetAttribute("GTRPerformanceDebug") == true
end

local function cachedCountersEnabled()
	return debugEnabled() or game:GetAttribute("GTRPerformanceCountersEnabled") == true
end

local function syncDebugEnabledLog()
	local enabled = debugEnabled()
	if enabled and not lastDebugEnabled then
		print(LOG_PREFIX .. " enabled")
	end
	lastDebugEnabled = enabled
end

local function resetIntervalCounters()
	counters.IncomeWrites = 0
	counters.DisplayUpdates = 0
	counters.WorldUiUpdates = 0
	counters.HeartbeatSpikeMs = 0
end

local function isPlacedCrewVisual(model)
	return typeof(model) == "Instance"
		and model:IsA("Model")
		and tostring(model:GetAttribute(CrewOverhead.Attribute.Kind) or "") == CrewOverhead.Kind.Placed
end

local function isAuraVfx(descendant)
	return descendant:IsA("ParticleEmitter")
		or descendant:IsA("Beam")
		or descendant:IsA("Trail")
		or descendant:IsA("PointLight")
		or descendant:IsA("SpotLight")
		or descendant:IsA("SurfaceLight")
end

local function applyVisualDescendantDelta(descendant, delta)
	visualStats.Descendants += delta
	if descendant:IsA("Humanoid") then
		visualStats.Humanoids += delta
	elseif descendant:IsA("Animator") or descendant:IsA("AnimationController") then
		visualStats.Animators += delta
	elseif isAuraVfx(descendant) then
		visualStats.AuraVfx += delta
	end
end

local function setVisualCounted(model, state, counted)
	if state.Counted == counted then
		return
	end

	if counted then
		state.Counted = true
		visualStats.PlacedServerVisuals += 1
		state.Seen = {}
		local budgetStartedAt = os.clock()
		local scanQueue = { model }
		local scanIndex = 1
		while scanIndex <= #scanQueue do
			if state.Counted ~= true then
				break
			end
			local current = scanQueue[scanIndex]
			scanIndex += 1
			for _, descendant in ipairs(current:GetChildren()) do
				scanQueue[#scanQueue + 1] = descendant
				if state.Seen[descendant] ~= true then
					state.Seen[descendant] = true
					applyVisualDescendantDelta(descendant, 1)
				end
			end
			if os.clock() - budgetStartedAt >= CACHE_SCAN_BUDGET_SECONDS then
				task.wait()
				budgetStartedAt = os.clock()
			end
		end
		return
	end

	state.Counted = false
	visualStats.PlacedServerVisuals = math.max(0, visualStats.PlacedServerVisuals - 1)
	local budgetStartedAt = os.clock()
	for descendant in pairs(state.Seen or {}) do
		applyVisualDescendantDelta(descendant, -1)
		if os.clock() - budgetStartedAt >= CACHE_SCAN_BUDGET_SECONDS then
			task.wait()
			budgetStartedAt = os.clock()
		end
	end
	state.Seen = {}
end

local function trackVisual(model)
	if trackedVisuals[model] ~= nil then
		return
	end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end

	local state = {
		Counted = false,
		Seen = {},
		Connections = {},
	}
	trackedVisuals[model] = state

	state.Connections[#state.Connections + 1] = model.DescendantAdded:Connect(function(descendant)
		if state.Counted == true and state.Seen[descendant] ~= true then
			state.Seen[descendant] = true
			applyVisualDescendantDelta(descendant, 1)
		end
	end)
	state.Connections[#state.Connections + 1] = model.DescendantRemoving:Connect(function(descendant)
		if state.Counted == true and state.Seen[descendant] == true then
			state.Seen[descendant] = nil
			applyVisualDescendantDelta(descendant, -1)
		end
	end)
	state.Connections[#state.Connections + 1] = model:GetAttributeChangedSignal(CrewOverhead.Attribute.Kind):Connect(function()
		setVisualCounted(model, state, isPlacedCrewVisual(model))
	end)

	task.spawn(function()
		if trackedVisuals[model] == state then
			setVisualCounted(model, state, isPlacedCrewVisual(model))
		end
	end)
end

local function untrackVisual(model)
	local state = trackedVisuals[model]
	if state == nil then
		return
	end
	trackedVisuals[model] = nil
	for _, connection in ipairs(state.Connections or {}) do
		connection:Disconnect()
	end
	setVisualCounted(model, state, false)
end

local function setPlacedStateCounted(_instance, state, counted)
	if state.Counted == counted then
		return
	end
	state.Counted = counted
	placedStateActiveCount += if counted then 1 else -1
	placedStateActiveCount = math.max(0, placedStateActiveCount)
end

local function trackPlacedState(instance)
	if trackedPlacedStates[instance] ~= nil or typeof(instance) ~= "Instance" then
		return
	end

	local state = {
		Counted = false,
		Connection = nil,
	}
	trackedPlacedStates[instance] = state
	state.Connection = instance:GetAttributeChangedSignal(PlacedCrewState.Attribute.Active):Connect(function()
		setPlacedStateCounted(instance, state, instance:GetAttribute(PlacedCrewState.Attribute.Active) == true)
	end)
	setPlacedStateCounted(instance, state, instance:GetAttribute(PlacedCrewState.Attribute.Active) == true)
end

local function untrackPlacedState(instance)
	local state = trackedPlacedStates[instance]
	if state == nil then
		return
	end
	trackedPlacedStates[instance] = nil
	setPlacedStateCounted(instance, state, false)
	if state.Connection then
		state.Connection:Disconnect()
	end
end

local function enqueueCounterJob(kind, instance)
	if cachedCountersEnabled() ~= true or typeof(instance) ~= "Instance" then
		return
	end

	local existing = queuedCounterJobs[instance]
	if existing ~= nil then
		existing.Kind = kind
		return
	end

	local pendingCount = math.max(0, #counterQueue - counterQueueHead + 1)
	if pendingCount >= MAX_COUNTER_QUEUE_SIZE then
		return
	end

	local job = {
		Kind = kind,
		Instance = instance,
	}
	queuedCounterJobs[instance] = job
	counterQueue[#counterQueue + 1] = job
end

local function compactCounterQueueIfEmpty()
	if counterQueueHead <= #counterQueue then
		return
	end

	table.clear(counterQueue)
	table.clear(queuedCounterJobs)
	counterQueueHead = 1
end

local function processCounterQueue()
	if cachedCountersStarted ~= true or cachedCountersEnabled() ~= true then
		return
	end

	local budgetStartedAt = os.clock()
	while counterQueueHead <= #counterQueue do
		local job = counterQueue[counterQueueHead]
		counterQueue[counterQueueHead] = nil
		counterQueueHead += 1

		if job ~= nil and queuedCounterJobs[job.Instance] == job then
			queuedCounterJobs[job.Instance] = nil
			if job.Kind == "trackVisual" then
				trackVisual(job.Instance)
			elseif job.Kind == "untrackVisual" then
				untrackVisual(job.Instance)
			elseif job.Kind == "trackPlacedState" then
				trackPlacedState(job.Instance)
			elseif job.Kind == "untrackPlacedState" then
				untrackPlacedState(job.Instance)
			end
		end

		if os.clock() - budgetStartedAt >= COUNTER_QUEUE_BUDGET_SECONDS then
			break
		end
	end

	compactCounterQueueIfEmpty()
end

local function startCachedCounters()
	if cachedCountersStarted then
		return
	end
	if cachedCountersEnabled() ~= true then
		return
	end
	cachedCountersStarted = true

	CollectionService:GetInstanceAddedSignal(CrewOverhead.Tag):Connect(function(instance)
		enqueueCounterJob("trackVisual", instance)
	end)
	CollectionService:GetInstanceRemovedSignal(CrewOverhead.Tag):Connect(function(instance)
		enqueueCounterJob("untrackVisual", instance)
	end)
	CollectionService:GetInstanceAddedSignal(PlacedCrewState.Tag):Connect(function(instance)
		enqueueCounterJob("trackPlacedState", instance)
	end)
	CollectionService:GetInstanceRemovedSignal(PlacedCrewState.Tag):Connect(function(instance)
		enqueueCounterJob("untrackPlacedState", instance)
	end)

	task.spawn(function()
		local budgetStartedAt = os.clock()
		for _, model in ipairs(CollectionService:GetTagged(CrewOverhead.Tag)) do
			enqueueCounterJob("trackVisual", model)
			if os.clock() - budgetStartedAt >= CACHE_SCAN_BUDGET_SECONDS then
				task.wait()
				budgetStartedAt = os.clock()
			end
		end
		for _, instance in ipairs(CollectionService:GetTagged(PlacedCrewState.Tag)) do
			enqueueCounterJob("trackPlacedState", instance)
			if os.clock() - budgetStartedAt >= CACHE_SCAN_BUDGET_SECONDS then
				task.wait()
				budgetStartedAt = os.clock()
			end
		end
	end)
end

local function countServerPlacedCrewVisuals()
	return visualStats.PlacedServerVisuals,
		visualStats.Humanoids,
		visualStats.Animators,
		visualStats.AuraVfx,
		visualStats.Descendants
end

local function countPlacedStateStands()
	return placedStateActiveCount
end

local function formatTopPlayers()
	if typeof(standCountsProvider) ~= "function" then
		return ""
	end

	local ok, rows = pcall(standCountsProvider)
	if not ok or typeof(rows) ~= "table" then
		return ""
	end

	table.sort(rows, function(left, right)
		return (tonumber(left.Count) or 0) > (tonumber(right.Count) or 0)
	end)

	local parts = {}
	for index = 1, math.min(3, #rows) do
		local row = rows[index]
		parts[#parts + 1] = string.format("%s:%d", tostring(row.Name or "?"), math.max(0, tonumber(row.Count) or 0))
	end
	return table.concat(parts, ",")
end

local function getQueueStats()
	if typeof(queueStatsProvider) ~= "function" then
		return nil
	end

	local ok, stats = pcall(queueStatsProvider)
	if ok and typeof(stats) == "table" then
		return stats
	end
	return nil
end

local function logSummary()
	if not debugEnabled() then
		resetIntervalCounters()
		return
	end

	local placedVisuals, humanoids, animators, auraVfx, descendants = countServerPlacedCrewVisuals()
	local queueStats = getQueueStats() or {}
	print(string.format(
		"%s summary players=%d placedState=%d placedServerVisuals=%d humanoids=%d animators=%d auraVfx=%d descendants=%d bankMs=%.3f bankPlayers=%d stands=%d occupied=%d incomeWritesPerSec=%.2f displayUpdates=%d worldUiUpdates=%d queuePending=%d queueDeduped=%d queueUpdated=%d queueCompleted=%d queueStale=%d topCrew=%s heartbeatSpikeMs=%.1f placeId=%d",
		LOG_PREFIX,
		#Players:GetPlayers(),
		countPlacedStateStands(),
		placedVisuals,
		humanoids,
		animators,
		auraVfx,
		descendants,
		counters.BankLoopDurationSeconds * 1000,
		counters.BankLoopPlayers,
		counters.BankLoopStands,
		counters.BankLoopOccupiedStands,
		counters.IncomeWrites / SUMMARY_INTERVAL_SECONDS,
		counters.DisplayUpdates,
		counters.WorldUiUpdates,
		math.max(0, tonumber(queueStats.PendingJobs) or 0),
		math.max(0, tonumber(queueStats.Deduped) or 0),
		math.max(0, tonumber(queueStats.UpdatedPending) or 0),
		math.max(0, tonumber(queueStats.Completed) or 0),
		math.max(0, tonumber(queueStats.SkippedStale) or 0),
		formatTopPlayers(),
		counters.HeartbeatSpikeMs,
		game.PlaceId
	))
	resetIntervalCounters()
end

function Diagnostics.Start()
	if started then
		return
	end
	started = true
	syncDebugEnabledLog()
	game:GetAttributeChangedSignal("GTRPerformanceDebug"):Connect(function()
		syncDebugEnabledLog()
		startCachedCounters()
	end)
	game:GetAttributeChangedSignal("GTRPerformanceCountersEnabled"):Connect(startCachedCounters)
	startCachedCounters()

	local lastHeartbeatAt = os.clock()
	RunService.Heartbeat:Connect(function()
		processCounterQueue()

		local now = os.clock()
		local delta = now - lastHeartbeatAt
		lastHeartbeatAt = now
		if delta >= HEARTBEAT_SPIKE_SECONDS then
			counters.HeartbeatSpikeMs = math.max(counters.HeartbeatSpikeMs, delta * 1000)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(SUMMARY_INTERVAL_SECONDS)
			logSummary()
		end
	end)
end

function Diagnostics.RecordBankLoop(durationSeconds, playersProcessed, standsProcessed, occupiedStands)
	counters.BankLoopDurationSeconds = math.max(0, tonumber(durationSeconds) or 0)
	counters.BankLoopPlayers = math.max(0, tonumber(playersProcessed) or 0)
	counters.BankLoopStands = math.max(0, tonumber(standsProcessed) or 0)
	counters.BankLoopOccupiedStands = math.max(0, tonumber(occupiedStands) or 0)
end

function Diagnostics.RecordIncomeWrite(count)
	counters.IncomeWrites += math.max(1, tonumber(count) or 1)
end

function Diagnostics.RecordDisplayUpdate(kind, count)
	count = math.max(1, tonumber(count) or 1)
	counters.DisplayUpdates += count
	if tostring(kind or "") == "world_ui" then
		counters.WorldUiUpdates += count
	end
end

function Diagnostics.SetQueueStatsProvider(provider)
	queueStatsProvider = provider
end

function Diagnostics.SetStandCountsProvider(provider)
	standCountsProvider = provider
end

function Diagnostics.GetServerPlacedCrewVisualStats()
	local placedVisuals, humanoids, animators, auraVfx, descendants = countServerPlacedCrewVisuals()
	return {
		PlacedServerVisuals = placedVisuals,
		Humanoids = humanoids,
		Animators = animators,
		AuraVfx = auraVfx,
		Descendants = descendants,
		WorkspaceDescendants = 0,
	}
end

return Diagnostics
