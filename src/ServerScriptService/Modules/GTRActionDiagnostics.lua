local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local GTRActionDiagnostics = {}

local SLOW_ACTION_THRESHOLD_SECONDS = 0.025
local MULTIPLAYER_JOIN_WINDOW_SECONDS = 20
local playerJoinTimes = {}
local joinRestoreScheduler = nil
local joinRestoreSchedulerLoaded = false

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

local function getJoinRestoreContext()
	if not joinRestoreSchedulerLoaded then
		joinRestoreSchedulerLoaded = true
		local ok, result = pcall(function()
			return require(ServerScriptService.Modules:WaitForChild("JoinRestoreScheduler"))
		end)
		if ok and typeof(result) == "table" then
			joinRestoreScheduler = result
		end
	end
	if not joinRestoreScheduler or typeof(joinRestoreScheduler.GetActionContext) ~= "function" then
		return nil
	end

	local ok, result = pcall(joinRestoreScheduler.GetActionContext)
	if ok and typeof(result) == "table" then
		return result
	end
	return nil
end

local function getRecentJoinContext(actionPlayer)
	local players = Players:GetPlayers()
	local now = os.clock()
	local recentPlayer = nil
	local recentAge = nil

	for _, joinedPlayer in ipairs(players) do
		if joinedPlayer ~= actionPlayer then
			local joinedAt = tonumber(playerJoinTimes[joinedPlayer])
			local age = if joinedAt then now - joinedAt else nil
			if age ~= nil and age >= 0 and age <= MULTIPLAYER_JOIN_WINDOW_SECONDS then
				if recentAge == nil or age < recentAge then
					recentPlayer = joinedPlayer
					recentAge = age
				end
			end
		end
	end

	return {
		ActivePlayers = #players,
		RecentJoinPlayer = recentPlayer,
		RecentJoinAge = recentAge,
		ValidationWindow = recentPlayer ~= nil,
	}
end

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	playerJoinTimes[existingPlayer] = os.clock()
end

Players.PlayerAdded:Connect(function(joinedPlayer)
	playerJoinTimes[joinedPlayer] = os.clock()
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	playerJoinTimes[leavingPlayer] = nil
end)

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
	local joinContext = getRecentJoinContext(player)
	local joinRestoreContext = getJoinRestoreContext()

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
	appendField(parts, "activePlayers", joinContext.ActivePlayers)
	if joinRestoreContext and joinRestoreContext.joinRestoreActive == true then
		appendField(parts, "joinRestoreActive", true)
		appendField(parts, "joinRestorePlayers", joinRestoreContext.joinRestorePlayers)
		appendField(parts, "pendingJoinJobs", joinRestoreContext.pendingJoinJobs)
	end
	if joinContext.ValidationWindow == true then
		appendField(parts, "validation", "multiplayer_join_window")
		appendField(parts, "recentJoinPlayer", joinContext.RecentJoinPlayer and joinContext.RecentJoinPlayer.Name)
		appendField(parts, "recentJoinUserId", joinContext.RecentJoinPlayer and joinContext.RecentJoinPlayer.UserId)
		appendField(
			parts,
			"recentJoinAgeMs",
			if joinContext.RecentJoinAge then string.format("%.0f", joinContext.RecentJoinAge * 1000) else nil
		)
	end

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
