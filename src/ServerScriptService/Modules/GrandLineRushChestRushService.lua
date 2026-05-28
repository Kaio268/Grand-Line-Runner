local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))

local ChestRushService = {}

local STATE_EVENT_NAME = "GrandLineRushChestRushState"
local STATE_REQUEST_NAME = "GrandLineRushChestRushStateRequest"
local DEFAULT_STARTS_EVERY_MINUTES = 60
local DEFAULT_DURATION_MINUTES = 10
local DEFAULT_MAX_ACTIVE_MULTIPLIER = 2
local DEFAULT_SPAWN_INTERVAL_MULTIPLIER = 0.65
local DEFAULT_MIN_SPAWN_INTERVAL_SECONDS = 12
local DEFAULT_MAX_ACTIVE_CAP = 20

local started = false
local stateEvent = nil
local stateRequest = nil
local lastBroadcastSignature = nil
local forcedStartedAtUnix = nil
local forcedEndsAtUnix = nil
local forcedByUserId = nil
local forcedByName = nil

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	return remotes
end

local function getOrCreateRemote(parent, className, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote.ClassName == className then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemotes()
	local remotes = getOrCreateRemotesFolder()
	stateEvent = getOrCreateRemote(remotes, "RemoteEvent", STATE_EVENT_NAME)
	stateRequest = getOrCreateRemote(remotes, "RemoteFunction", STATE_REQUEST_NAME)
end

local function getSharedChestConfig()
	local verticalSlice = Economy.VerticalSlice
	local worldRun = typeof(verticalSlice) == "table" and verticalSlice.WorldRun or nil
	return if typeof(worldRun) == "table" and typeof(worldRun.SharedChests) == "table" then worldRun.SharedChests else {}
end

local function getChestRushConfig()
	local sharedConfig = getSharedChestConfig()
	return if typeof(sharedConfig.ChestRush) == "table" then sharedConfig.ChestRush else {}
end

local function getNumber(config, key, defaultValue)
	local value = tonumber(config[key])
	if value == nil then
		return defaultValue
	end

	return value
end

local function getSchedule(config)
	if config.Enabled ~= true then
		return nil
	end

	local periodSeconds = math.max(60, math.floor(getNumber(config, "StartsEveryMinutes", DEFAULT_STARTS_EVERY_MINUTES) * 60))
	local durationSeconds = math.floor(getNumber(config, "DurationMinutes", DEFAULT_DURATION_MINUTES) * 60)
	durationSeconds = math.clamp(durationSeconds, 1, periodSeconds)

	return periodSeconds, durationSeconds
end

local function getServerTimeForUnix(serverNow, unixNow, unixTimestamp)
	if unixTimestamp == nil then
		return nil
	end

	return serverNow + (unixTimestamp - unixNow)
end

local function getStateSignature(state)
	return table.concat({
		if state.Active then "1" else "0",
		tostring(state.StartsAtUnix or ""),
		tostring(state.EndsAtUnix or ""),
		tostring(state.NextStartsAtUnix or ""),
		if state.ScheduledActive then "scheduled" else "",
		if state.ForcedActive then "forced" else "",
		tostring(state.ForcedEndsAtUnix or ""),
	}, "|")
end

local function clearExpiredForcedOverride(unixNow)
	if forcedEndsAtUnix ~= nil and forcedEndsAtUnix <= unixNow then
		forcedStartedAtUnix = nil
		forcedEndsAtUnix = nil
		forcedByUserId = nil
		forcedByName = nil
	end
end

local function getMaxUnixTime(firstValue, secondValue)
	if firstValue == nil then
		return secondValue
	elseif secondValue == nil then
		return firstValue
	end

	return math.max(firstValue, secondValue)
end

local function getMinUnixTime(firstValue, secondValue)
	if firstValue == nil then
		return secondValue
	elseif secondValue == nil then
		return firstValue
	end

	return math.min(firstValue, secondValue)
end

local function broadcastState(reason)
	if not stateEvent then
		return
	end

	local state = ChestRushService.GetState()
	state.Reason = tostring(reason or "sync")
	stateEvent:FireAllClients(state)
end

function ChestRushService.GetState()
	local config = getChestRushConfig()
	local serverNow = Workspace:GetServerTimeNow()
	local unixNow = os.time()
	local periodSeconds, durationSeconds = getSchedule(config)
	clearExpiredForcedOverride(unixNow)

	if not periodSeconds or not durationSeconds then
		return {
			EventName = "ChestRush",
			Enabled = false,
			Active = false,
			ServerNow = serverNow,
			UnixNow = unixNow,
		}
	end

	local elapsed = unixNow % periodSeconds
	local scheduledStartsAtUnix = unixNow - elapsed
	local scheduledEndsAtUnix = scheduledStartsAtUnix + durationSeconds
	local scheduledActive = elapsed < durationSeconds
	local nextStartsAtUnix = scheduledStartsAtUnix + periodSeconds
	local forcedActive = forcedEndsAtUnix ~= nil and forcedEndsAtUnix > unixNow
	local active = scheduledActive or forcedActive
	local activeStartsAtUnix = if scheduledActive then scheduledStartsAtUnix else nil
	activeStartsAtUnix = getMinUnixTime(activeStartsAtUnix, if forcedActive then forcedStartedAtUnix else nil)
	local activeEndsAtUnix = if scheduledActive then scheduledEndsAtUnix else nil
	activeEndsAtUnix = getMaxUnixTime(activeEndsAtUnix, if forcedActive then forcedEndsAtUnix else nil)
	local startsAtUnix = activeStartsAtUnix or scheduledStartsAtUnix
	local endsAtUnix = activeEndsAtUnix or scheduledEndsAtUnix

	return {
		EventName = "ChestRush",
		Enabled = true,
		Active = active,
		StartsAtUnix = startsAtUnix,
		EndsAtUnix = endsAtUnix,
		NextStartsAtUnix = nextStartsAtUnix,
		StartsAtServerTime = getServerTimeForUnix(serverNow, unixNow, startsAtUnix),
		EndsAtServerTime = getServerTimeForUnix(serverNow, unixNow, endsAtUnix),
		NextStartsAtServerTime = getServerTimeForUnix(serverNow, unixNow, nextStartsAtUnix),
		ScheduledActive = scheduledActive,
		ScheduledStartsAtUnix = scheduledStartsAtUnix,
		ScheduledEndsAtUnix = scheduledEndsAtUnix,
		ScheduledStartsAtServerTime = getServerTimeForUnix(serverNow, unixNow, scheduledStartsAtUnix),
		ScheduledEndsAtServerTime = getServerTimeForUnix(serverNow, unixNow, scheduledEndsAtUnix),
		ForcedActive = forcedActive,
		ForcedStartedAtUnix = forcedStartedAtUnix,
		ForcedEndsAtUnix = forcedEndsAtUnix,
		ForcedStartedAtServerTime = getServerTimeForUnix(serverNow, unixNow, forcedStartedAtUnix),
		ForcedEndsAtServerTime = getServerTimeForUnix(serverNow, unixNow, forcedEndsAtUnix),
		ForcedByUserId = forcedByUserId,
		ForcedByName = forcedByName,
		ServerNow = serverNow,
		UnixNow = unixNow,
		DurationSeconds = durationSeconds,
		PeriodSeconds = periodSeconds,
		MaxActiveMultiplier = getNumber(config, "MaxActiveMultiplier", DEFAULT_MAX_ACTIVE_MULTIPLIER),
		SpawnIntervalMultiplier = getNumber(config, "SpawnIntervalMultiplier", DEFAULT_SPAWN_INTERVAL_MULTIPLIER),
		GoldChanceMultiplier = getNumber(config, "GoldChanceMultiplier", 1.0),
	}
end

function ChestRushService.GetSpawnModifiers()
	local state = ChestRushService.GetState()
	local config = getChestRushConfig()
	if state.Active ~= true then
		return {
			Active = false,
			MaxActiveMultiplier = 1,
			SpawnIntervalMultiplier = 1,
			MinSpawnIntervalSeconds = 1,
			MaxActiveCap = math.huge,
		}
	end

	return {
		Active = true,
		MaxActiveMultiplier = math.max(1, getNumber(config, "MaxActiveMultiplier", DEFAULT_MAX_ACTIVE_MULTIPLIER)),
		SpawnIntervalMultiplier = math.clamp(getNumber(config, "SpawnIntervalMultiplier", DEFAULT_SPAWN_INTERVAL_MULTIPLIER), 0.01, 1),
		MinSpawnIntervalSeconds = math.max(1, getNumber(config, "MinSpawnIntervalSeconds", DEFAULT_MIN_SPAWN_INTERVAL_SECONDS)),
		MaxActiveCap = math.max(1, math.floor(getNumber(config, "MaxActiveCap", DEFAULT_MAX_ACTIVE_CAP))),
	}
end

function ChestRushService.IsActive()
	return ChestRushService.GetState().Active == true
end

function ChestRushService.GetStatus()
	return ChestRushService.GetState()
end

function ChestRushService.GetStatePayload()
	return ChestRushService.GetState()
end

function ChestRushService.ForceStart(sourcePlayer)
	local config = getChestRushConfig()
	local periodSeconds, durationSeconds = getSchedule(config)
	if not periodSeconds or not durationSeconds then
		return false, "Chest Rush is disabled."
	end

	local unixNow = os.time()
	clearExpiredForcedOverride(unixNow)

	forcedStartedAtUnix = unixNow
	forcedEndsAtUnix = unixNow + durationSeconds
	forcedByUserId = sourcePlayer and sourcePlayer.UserId or nil
	forcedByName = sourcePlayer and sourcePlayer.Name or nil

	broadcastState("force_started")
	return true, string.format("Chest Rush forced for %d minute(s).", math.ceil(durationSeconds / 60))
end

function ChestRushService.ForceStop(_sourcePlayer)
	local hadForcedOverride = forcedEndsAtUnix ~= nil and forcedEndsAtUnix > os.time()
	forcedStartedAtUnix = nil
	forcedEndsAtUnix = nil
	forcedByUserId = nil
	forcedByName = nil

	broadcastState("force_stopped")
	if hadForcedOverride then
		return true, "Forced Chest Rush override cleared."
	end

	return true, "No active forced Chest Rush override to clear."
end

local function fireStateToPlayer(player, reason)
	if not stateEvent or player.Parent ~= Players then
		return
	end

	local state = ChestRushService.GetState()
	state.Reason = tostring(reason or "sync")
	stateEvent:FireClient(player, state)
end

local function stateLoop()
	while started do
		local state = ChestRushService.GetState()
		local signature = getStateSignature(state)
		if signature ~= lastBroadcastSignature then
			lastBroadcastSignature = signature
			broadcastState("phase_changed")
		end

		task.wait(1)
	end
end

function ChestRushService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()

	stateRequest.OnServerInvoke = function()
		return ChestRushService.GetState()
	end

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			fireStateToPlayer(player, "player_joined")
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			fireStateToPlayer(player, "startup")
		end)
	end

	task.spawn(stateLoop)
end

return ChestRushService
