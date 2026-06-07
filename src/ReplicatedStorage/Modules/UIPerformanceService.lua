local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local RuntimeScheduler = require(Modules:WaitForChild("RuntimeScheduler"))
local Flags = require(Modules:WaitForChild("Configs"):WaitForChild("PerformanceArchitectureFlags"))

local UIPerformanceService = {}

local scheduler = RuntimeScheduler.GetDefault()
local diagnostics = {
	PopupExpiryCount = 0,
	ThrottledScanCount = 0,
	SkippedInactiveTasks = 0,
}

local activeTasks = {}

local function isEnabled()
	return Flags.IsEnabled("RuntimeSchedulerEnabled") and Flags.IsEnabled("UIPerformanceSchedulerEnabled")
end

function UIPerformanceService.ScheduleHeartbeat(id, callback, options)
	if not isEnabled() or typeof(callback) ~= "function" then
		return nil
	end

	options = if typeof(options) == "table" then options else {}
	local taskId = "ui:heartbeat:" .. tostring(id)
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

function UIPerformanceService.ScheduleRender(id, callback, options)
	if not isEnabled() or typeof(callback) ~= "function" then
		return nil
	end

	options = if typeof(options) == "table" then options else {}
	local taskId = "ui:render:" .. tostring(id)
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

function UIPerformanceService.RecordPopupExpiry(count)
	diagnostics.PopupExpiryCount += math.max(1, tonumber(count) or 1)
end

function UIPerformanceService.RecordThrottledScan(count)
	diagnostics.ThrottledScanCount += math.max(1, tonumber(count) or 1)
end

function UIPerformanceService.RecordSkippedInactiveTask(count)
	diagnostics.SkippedInactiveTasks += math.max(1, tonumber(count) or 1)
end

function UIPerformanceService.GetStats()
	local activeTaskCount = 0
	for _, handle in pairs(activeTasks) do
		if handle and handle:IsConnected() then
			activeTaskCount += 1
		end
	end

	return {
		ActiveUITasks = activeTaskCount,
		PopupExpiryCount = diagnostics.PopupExpiryCount,
		ThrottledScanCount = diagnostics.ThrottledScanCount,
		SkippedInactiveTasks = diagnostics.SkippedInactiveTasks,
	}
end

return UIPerformanceService
