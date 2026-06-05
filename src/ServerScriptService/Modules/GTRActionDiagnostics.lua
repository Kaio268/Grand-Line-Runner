local GTRActionDiagnostics = {}

local SLOW_ACTION_THRESHOLD_SECONDS = 0.025

local Trace = {}
Trace.__index = Trace

local function shouldLog(durationSeconds, metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	if metadata.Always == true then
		return true
	end
	if game:GetAttribute("GTRActionDebug") == true then
		return true
	end
	return (tonumber(durationSeconds) or 0) >= SLOW_ACTION_THRESHOLD_SECONDS
end

local function getWriteCount(metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	return metadata.WriteCount or metadata.ReplicaWriteCount or metadata.writes or ""
end

local function appendField(parts, key, value)
	if value == nil then
		return
	end
	parts[#parts + 1] = string.format("%s=%s", key, tostring(value))
end

function GTRActionDiagnostics.Log(actionName, player, phase, durationSeconds, result, metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	durationSeconds = tonumber(durationSeconds) or 0
	if not shouldLog(durationSeconds, metadata) then
		return
	end

	local parts = {
		"[GTR_ACTION]",
		"action=" .. tostring(actionName or "unknown"),
		"player=" .. tostring(player and player.Name or "unknown"),
		"userId=" .. tostring(player and player.UserId or 0),
		"phase=" .. tostring(phase or "complete"),
		string.format("durationMs=%.3f", durationSeconds * 1000),
		"result=" .. tostring(result or metadata.Result or "ok"),
		"writes=" .. tostring(getWriteCount(metadata)),
	}

	appendField(parts, "reason", metadata.Reason)
	appendField(parts, "target", metadata.Target)
	appendField(parts, "requestId", metadata.RequestId)
	appendField(parts, "source", metadata.Source)
	appendField(parts, "stand", metadata.StandName)
	appendField(parts, "processedStands", metadata.ProcessedStands)
	appendField(parts, "queuedFull", metadata.QueuedFull)
	appendField(parts, "dirtyQueued", metadata.DirtyQueued)
	appendField(parts, "cacheHits", metadata.CacheHits)
	appendField(parts, "cacheMisses", metadata.CacheMisses)

	print(table.concat(parts, " "))
end

function GTRActionDiagnostics.Start(actionName, player, metadata)
	local now = os.clock()
	return setmetatable({
		ActionName = tostring(actionName or "unknown"),
		Player = player,
		StartedAt = now,
		LastAt = now,
		Metadata = if typeof(metadata) == "table" then metadata else {},
	}, Trace)
end

function Trace:phase(phase, metadata)
	local now = os.clock()
	metadata = if typeof(metadata) == "table" then metadata else {}
	for key, value in pairs(self.Metadata) do
		if metadata[key] == nil then
			metadata[key] = value
		end
	end
	GTRActionDiagnostics.Log(self.ActionName, self.Player, phase, now - self.LastAt, metadata.Result or "ok", metadata)
	self.LastAt = now
end

function Trace:finish(result, metadata)
	local now = os.clock()
	metadata = if typeof(metadata) == "table" then metadata else {}
	for key, value in pairs(self.Metadata) do
		if metadata[key] == nil then
			metadata[key] = value
		end
	end
	GTRActionDiagnostics.Log(self.ActionName, self.Player, "complete", now - self.StartedAt, result or "ok", metadata)
	self.LastAt = now
end

return GTRActionDiagnostics
