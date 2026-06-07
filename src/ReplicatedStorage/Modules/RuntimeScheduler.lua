local RunService = game:GetService("RunService")

local RuntimeScheduler = {}
RuntimeScheduler.__index = RuntimeScheduler

local VALID_PHASES = {
	Heartbeat = true,
	RenderStepped = true,
}

local defaultScheduler = nil

local function normalizePhase(phase)
	phase = tostring(phase or "Heartbeat")
	if VALID_PHASES[phase] then
		return phase
	end
	return "Heartbeat"
end

local function makeNoopHandle()
	local handle = {}

	function handle:Disconnect(_reason) end
	function handle:Pause() end
	function handle:Resume() end
	function handle:IsConnected()
		return false
	end

	return handle
end

local function sortTasks(left, right)
	local leftPriority = tonumber(left.Priority) or 0
	local rightPriority = tonumber(right.Priority) or 0
	if leftPriority ~= rightPriority then
		return leftPriority > rightPriority
	end
	return tostring(left.Id) < tostring(right.Id)
end

function RuntimeScheduler.new(name, options)
	options = if typeof(options) == "table" then options else {}

	local self = setmetatable({}, RuntimeScheduler)
	self.Name = tostring(name or "RuntimeScheduler")
	self.Environment = if RunService:IsServer() then "server" else "client"
	self.FrameBudgetSeconds = math.max(0, tonumber(options.FrameBudgetSeconds) or 0.004)
	self.TasksByPhase = {
		Heartbeat = {},
		RenderStepped = {},
	}
	self.TaskOrderByPhase = {
		Heartbeat = {},
		RenderStepped = {},
	}
	self.Connections = {}
	self.Stats = {
		AverageTaskMs = 0,
		MaxTaskMs = 0,
		BudgetOverrunCount = 0,
		SampleCount = 0,
	}
	return self
end

function RuntimeScheduler.GetDefault()
	if defaultScheduler == nil then
		defaultScheduler = RuntimeScheduler.new("Default")
	end
	return defaultScheduler
end

function RuntimeScheduler:_rebuildOrder(phase)
	local order = {}
	for _, taskRecord in pairs(self.TasksByPhase[phase]) do
		if taskRecord.Connected == true then
			order[#order + 1] = taskRecord
		end
	end
	table.sort(order, sortTasks)
	self.TaskOrderByPhase[phase] = order
end

function RuntimeScheduler:_disconnectPhaseIfIdle(phase)
	if next(self.TasksByPhase[phase]) ~= nil then
		return
	end

	local connection = self.Connections[phase]
	if connection then
		connection:Disconnect()
		self.Connections[phase] = nil
	end
end

function RuntimeScheduler:_runPhase(phase, dt)
	local now = os.clock()
	local phaseStartedAt = now
	local order = self.TaskOrderByPhase[phase]

	for _, taskRecord in ipairs(order) do
		if taskRecord.Connected == true and taskRecord.Paused ~= true then
			taskRecord.Elapsed += dt
			if taskRecord.Interval <= 0 or taskRecord.Elapsed >= taskRecord.Interval then
				local callbackDt = taskRecord.Elapsed
				taskRecord.Elapsed = 0

				local startedAt = os.clock()
				local ok, result = pcall(taskRecord.Callback, callbackDt, now, taskRecord.State)
				local duration = os.clock() - startedAt

				self.Stats.SampleCount += 1
				local sampleCount = self.Stats.SampleCount
				local durationMs = duration * 1000
				self.Stats.AverageTaskMs += (durationMs - self.Stats.AverageTaskMs) / sampleCount
				self.Stats.MaxTaskMs = math.max(self.Stats.MaxTaskMs, durationMs)

				if not ok then
					warn(string.format("[RuntimeScheduler] task failed scheduler=%s phase=%s id=%s error=%s", self.Name, phase, tostring(taskRecord.Id), tostring(result)))
					self:_disconnectTask(taskRecord, "error")
				elseif result == false then
					self:_disconnectTask(taskRecord, "callback_false")
				end
			end
		end
	end

	if os.clock() - phaseStartedAt > self.FrameBudgetSeconds then
		self.Stats.BudgetOverrunCount += 1
	end
end

function RuntimeScheduler:_ensurePhase(phase)
	if self.Connections[phase] then
		return true
	end

	if phase == "RenderStepped" and not RunService:IsClient() then
		warn(string.format("[RuntimeScheduler] RenderStepped is client-only scheduler=%s", self.Name))
		return false
	end

	if phase == "Heartbeat" then
		self.Connections[phase] = RunService.Heartbeat:Connect(function(dt)
			self:_runPhase(phase, tonumber(dt) or 0)
		end)
	elseif phase == "RenderStepped" then
		self.Connections[phase] = RunService.RenderStepped:Connect(function(dt)
			self:_runPhase(phase, tonumber(dt) or 0)
		end)
	end

	return true
end

function RuntimeScheduler:_disconnectTask(taskRecord, reason)
	if taskRecord.Connected ~= true then
		return
	end

	taskRecord.Connected = false
	self.TasksByPhase[taskRecord.Phase][taskRecord.Id] = nil
	self:_rebuildOrder(taskRecord.Phase)
	self:_disconnectPhaseIfIdle(taskRecord.Phase)

	if typeof(taskRecord.OnStop) == "function" then
		task.spawn(function()
			taskRecord.OnStop(reason or "disconnect")
		end)
	end
end

function RuntimeScheduler:Schedule(taskSpec)
	if typeof(taskSpec) ~= "table" or typeof(taskSpec.Callback) ~= "function" then
		return makeNoopHandle()
	end

	local phase = normalizePhase(taskSpec.Phase)
	if phase == "RenderStepped" and not RunService:IsClient() then
		return makeNoopHandle()
	end

	local id = tostring(taskSpec.Id or (phase .. ":" .. tostring(taskSpec.Callback)))
	local existing = self.TasksByPhase[phase][id]
	if existing then
		self:_disconnectTask(existing, "replaced")
	end

	local taskRecord = {
		Id = id,
		Phase = phase,
		Interval = math.max(0, tonumber(taskSpec.Interval) or 0),
		Priority = tonumber(taskSpec.Priority) or 0,
		Callback = taskSpec.Callback,
		OnStop = taskSpec.OnStop,
		State = if typeof(taskSpec.State) == "table" then taskSpec.State else {},
		Elapsed = 0,
		Paused = false,
		Connected = true,
	}

	self.TasksByPhase[phase][id] = taskRecord
	self:_rebuildOrder(phase)

	if not self:_ensurePhase(phase) then
		self.TasksByPhase[phase][id] = nil
		self:_rebuildOrder(phase)
		return makeNoopHandle()
	end

	local handle = {}
	local selfScheduler = self

	function handle.Disconnect(firstArg, secondArg)
		local reason = secondArg
		if firstArg ~= handle then
			reason = firstArg
		end
		selfScheduler:_disconnectTask(taskRecord, reason or "handle_disconnect")
	end

	function handle.Pause()
		taskRecord.Paused = true
	end

	function handle.Resume()
		taskRecord.Paused = false
	end

	function handle.IsConnected()
		return taskRecord.Connected == true
	end

	return handle
end

function RuntimeScheduler:GetStats()
	local taskIdsByPhase = {}
	local activeCounts = {}
	for phase, tasks in pairs(self.TasksByPhase) do
		local ids = {}
		local count = 0
		for id, taskRecord in pairs(tasks) do
			if taskRecord.Connected == true then
				ids[#ids + 1] = id
				count += 1
			end
		end
		table.sort(ids)
		taskIdsByPhase[phase] = ids
		activeCounts[phase] = count
	end

	return {
		Name = self.Name,
		Environment = self.Environment,
		ActiveHeartbeatTasks = activeCounts.Heartbeat or 0,
		ActiveRenderSteppedTasks = activeCounts.RenderStepped or 0,
		AverageTaskMs = self.Stats.AverageTaskMs,
		MaxTaskMs = self.Stats.MaxTaskMs,
		BudgetOverrunCount = self.Stats.BudgetOverrunCount,
		TaskIdsByPhase = taskIdsByPhase,
	}
end

return RuntimeScheduler
