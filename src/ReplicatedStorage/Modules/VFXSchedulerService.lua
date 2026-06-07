local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local RuntimeScheduler = require(Modules:WaitForChild("RuntimeScheduler"))
local Flags = require(Modules:WaitForChild("Configs"):WaitForChild("PerformanceArchitectureFlags"))

local VFXSchedulerService = {}

local scheduler = RuntimeScheduler.GetDefault()
local activeTasks = {}
local pools = {}
local diagnostics = {
	ClonesCreated = 0,
	PoolReuses = 0,
	SpawnCapHits = 0,
}

local DEFAULT_MAX_SPAWNS_PER_FRAME = 12

local function isEnabled()
	return Flags.IsEnabled("RuntimeSchedulerEnabled") and Flags.IsEnabled("VFXSchedulerEnabled")
end

local function getPool(poolKey)
	poolKey = tostring(poolKey or "default")
	local pool = pools[poolKey]
	if not pool then
		pool = {}
		pools[poolKey] = pool
	end
	return pool
end

function VFXSchedulerService.CloneFromPool(poolKey, template)
	if typeof(template) ~= "Instance" then
		return nil
	end

	local pool = getPool(poolKey)
	local instance = table.remove(pool)
	if instance then
		diagnostics.PoolReuses += 1
		return instance
	end

	diagnostics.ClonesCreated += 1
	return template:Clone()
end

function VFXSchedulerService.ReturnToPool(poolKey, instance)
	if typeof(instance) ~= "Instance" then
		return false
	end

	instance.Parent = nil
	getPool(poolKey)[#getPool(poolKey) + 1] = instance
	return true
end

function VFXSchedulerService.ScheduleRender(id, callback, options)
	if not isEnabled() or typeof(callback) ~= "function" then
		return nil
	end

	options = if typeof(options) == "table" then options else {}
	local taskId = "vfx:render:" .. tostring(id)
	local handle = scheduler:Schedule({
		Id = taskId,
		Phase = "RenderStepped",
		Interval = tonumber(options.Interval) or 0,
		Priority = tonumber(options.Priority) or 0,
		Callback = callback,
		OnStop = options.OnStop,
	})
	activeTasks[taskId] = handle
	return handle
end

function VFXSchedulerService.ScheduleHeartbeat(id, callback, options)
	if not isEnabled() or typeof(callback) ~= "function" then
		return nil
	end

	options = if typeof(options) == "table" then options else {}
	local taskId = "vfx:heartbeat:" .. tostring(id)
	local handle = scheduler:Schedule({
		Id = taskId,
		Phase = "Heartbeat",
		Interval = tonumber(options.Interval) or 0,
		Priority = tonumber(options.Priority) or 0,
		Callback = callback,
		OnStop = options.OnStop,
	})
	activeTasks[taskId] = handle
	return handle
end

function VFXSchedulerService.ScheduleDelay(id, delaySeconds, callback)
	if typeof(callback) ~= "function" then
		return nil
	end

	local resolvedDelay = math.max(0, tonumber(delaySeconds) or 0)
	if not isEnabled() then
		local disconnected = false
		local thread = nil
		thread = task.delay(resolvedDelay, function()
			if not disconnected then
				disconnected = true
				callback()
			end
			thread = nil
		end)

		return {
			Disconnect = function()
				if disconnected then
					return
				end
				disconnected = true
				if thread then
					task.cancel(thread)
					thread = nil
				end
			end,
			IsConnected = function()
				return not disconnected
			end,
		}
	end

	local elapsed = 0
	local handle
	handle = scheduler:Schedule({
		Id = "vfx:delay:" .. tostring(id),
		Phase = "Heartbeat",
		Callback = function(dt)
			elapsed += dt
			if elapsed >= resolvedDelay then
				callback()
				return false
			end
			return true
		end,
	})
	return handle
end

function VFXSchedulerService.GetSpawnBudget(maxPerFrame)
	local remaining = math.max(1, math.floor(tonumber(maxPerFrame) or DEFAULT_MAX_SPAWNS_PER_FRAME))
	return function()
		if remaining <= 0 then
			diagnostics.SpawnCapHits += 1
			return false
		end
		remaining -= 1
		return true
	end
end

function VFXSchedulerService.GetStats()
	local poolCounts = {}
	for poolKey, pool in pairs(pools) do
		poolCounts[poolKey] = #pool
	end

	local activeTaskCount = 0
	for _, handle in pairs(activeTasks) do
		if handle and handle:IsConnected() then
			activeTaskCount += 1
		end
	end

	return {
		ActiveVFXTasks = activeTaskCount,
		PooledInstances = poolCounts,
		ClonesCreated = diagnostics.ClonesCreated,
		PoolReuses = diagnostics.PoolReuses,
		SpawnCapHits = diagnostics.SpawnCapHits,
	}
end

return VFXSchedulerService
