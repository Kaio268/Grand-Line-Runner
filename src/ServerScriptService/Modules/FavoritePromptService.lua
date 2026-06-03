local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BaseAreaService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("BaseAreaService"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))

local FavoritePromptService = {}

local REMOTES_FOLDER_NAME = "Remotes"
local REMOTE_NAME = "FavoritePromptRequest"
local FIRST_PROMPT_DELAY_SECONDS = 30 * 60
local DAILY_COOLDOWN_SECONDS = 24 * 60 * 60
local MAX_BACKOFF_EXPONENT = 20

local COMPLETED_PATH = "Settings.HasFavoritedGamePromptCompleted"
local COMPLETED_AT_PATH = "Settings.FavoriteGamePromptCompletedAtUnix"
local ATTEMPT_COUNT_PATH = "Settings.FavoriteGamePromptAttemptCount"
local LAST_ATTEMPT_AT_PATH = "Settings.FavoriteGamePromptLastAttemptAtUnix"

local ACTION_ALLOWLIST = {
	GetState = true,
	CanPrompt = true,
	RecordAttempt = true,
	MarkCompleted = true,
}

local started = false
local requestRemote = nil
local verticalSliceService = nil
local warnedRunStateUnavailable = false

local function warnRunStateOnce(message)
	if warnedRunStateUnavailable then
		return
	end
	warnedRunStateUnavailable = true
	warn(message)
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = REMOTES_FOLDER_NAME
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemoteFunction(parent, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemote()
	requestRemote = getOrCreateRemoteFunction(getOrCreateRemotesFolder(), REMOTE_NAME)
end

local function normalizeNonNegativeInteger(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function normalizeUnix(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function getNextDelaySeconds(attemptCount)
	local exponent = math.min(normalizeNonNegativeInteger(attemptCount), MAX_BACKOFF_EXPONENT)
	return FIRST_PROMPT_DELAY_SECONDS * (2 ^ exponent)
end

local function getVerticalSliceService()
	if verticalSliceService ~= nil then
		return verticalSliceService
	end

	local module = ServerScriptService:WaitForChild("Modules"):FindFirstChild("GrandLineRushVerticalSliceService")
	if module == nil then
		warnRunStateOnce("[FavoritePromptService] GrandLineRushVerticalSliceService is unavailable.")
		return nil
	end

	local ok, service = pcall(require, module)
	if not ok then
		warnRunStateOnce(
			string.format("[FavoritePromptService] Failed to require GrandLineRushVerticalSliceService: %s", tostring(service))
		)
		return nil
	end

	verticalSliceService = service
	return verticalSliceService
end

local function isPlayerInActiveRun(player)
	local service = getVerticalSliceService()
	if typeof(service) ~= "table" or typeof(service.GetState) ~= "function" then
		return nil, "run_state_unavailable"
	end

	local ok, state = pcall(service.GetState, player)
	if not ok then
		warnRunStateOnce(string.format("[FavoritePromptService] Failed to read run state: %s", tostring(state)))
		return nil, "run_state_unavailable"
	end

	local run = state and state.Run
	return typeof(run) == "table" and run.InRun == true, nil
end

local function isPlayerInBaseArea(player)
	local ok, inBase = pcall(BaseAreaService.IsPlayerInBaseArea, player)
	if not ok then
		warn(string.format("[FavoritePromptService] Failed to read base-area state for %s: %s", player.Name, tostring(inBase)))
		return nil, "base_state_unavailable"
	end

	return inBase == true, nil
end

local function buildState(player)
	if DataManager:IsReady(player) ~= true then
		return nil, "data_not_ready"
	end

	local completed, completedReason = DataManager:TryGetValue(player, COMPLETED_PATH)
	if completedReason ~= nil then
		return nil, completedReason
	end

	local completedAt, completedAtReason = DataManager:TryGetValue(player, COMPLETED_AT_PATH)
	if completedAtReason ~= nil then
		return nil, completedAtReason
	end

	local attemptCount, attemptCountReason = DataManager:TryGetValue(player, ATTEMPT_COUNT_PATH)
	if attemptCountReason ~= nil then
		return nil, attemptCountReason
	end

	local lastAttemptAt, lastAttemptReason = DataManager:TryGetValue(player, LAST_ATTEMPT_AT_PATH)
	if lastAttemptReason ~= nil then
		return nil, lastAttemptReason
	end

	attemptCount = normalizeNonNegativeInteger(attemptCount)
	lastAttemptAt = normalizeUnix(lastAttemptAt)

	local now = os.time()
	local cooldownRemaining = 0
	if lastAttemptAt > 0 then
		local elapsed = math.max(0, now - lastAttemptAt)
		cooldownRemaining = math.max(0, DAILY_COOLDOWN_SECONDS - elapsed)
	end

	return {
		completed = completed == true,
		completedAtUnix = normalizeUnix(completedAt),
		attemptCount = attemptCount,
		lastAttemptAtUnix = lastAttemptAt,
		nextDelaySeconds = getNextDelaySeconds(attemptCount),
		dailyCooldownSeconds = DAILY_COOLDOWN_SECONDS,
		dailyCooldownRemainingSeconds = cooldownRemaining,
		dailyCooldownEndsAtUnix = if cooldownRemaining > 0 then lastAttemptAt + DAILY_COOLDOWN_SECONDS else 0,
	}, nil
end

local function canPrompt(player)
	local state, stateReason = buildState(player)
	if state == nil then
		return false, stateReason or "state_unavailable", nil
	end

	if state.completed == true then
		return false, "completed", state
	end
	if state.dailyCooldownRemainingSeconds > 0 then
		return false, "daily_cooldown", state
	end

	local inRun, runReason = isPlayerInActiveRun(player)
	if inRun == nil then
		return false, runReason or "run_state_unavailable", state
	end
	if inRun == true then
		return false, "in_run", state
	end

	local inBase, baseReason = isPlayerInBaseArea(player)
	if inBase == nil then
		return false, baseReason or "base_state_unavailable", state
	end
	if inBase ~= true then
		return false, "not_in_base", state
	end

	return true, nil, state
end

local function markCompleted(player)
	if DataManager:IsReady(player) ~= true then
		return false, "data_not_ready", nil
	end

	local now = os.time()
	local completedOk, completedReason = DataManager:TrySetValue(player, COMPLETED_PATH, true)
	local completedAtOk, completedAtReason = DataManager:TrySetValue(player, COMPLETED_AT_PATH, now)
	local state = buildState(player)

	if completedOk ~= true then
		return false, completedReason or "save_failed", state
	end
	if completedAtOk ~= true then
		warn(string.format(
			"[FavoritePromptService] Failed to save completion time for %s: %s",
			player.Name,
			tostring(completedAtReason)
		))
	end

	return true, nil, state
end

local function recordAttempt(player)
	local allowed, reason, state = canPrompt(player)
	if allowed ~= true then
		return false, reason or "not_allowed", state
	end

	local now = os.time()
	local nextAttemptCount = normalizeNonNegativeInteger(state.attemptCount) + 1
	local lastAttemptOk, lastAttemptReason = DataManager:TrySetValue(player, LAST_ATTEMPT_AT_PATH, now)
	local countOk, countReason = DataManager:TrySetValue(player, ATTEMPT_COUNT_PATH, nextAttemptCount)
	local nextState = buildState(player)

	if lastAttemptOk ~= true then
		return false, lastAttemptReason or "save_failed", nextState
	end
	if countOk ~= true then
		return false, countReason or "save_failed", nextState
	end

	return true, nil, nextState
end

local function response(ok, reason, state)
	return {
		ok = ok == true,
		reason = reason,
		state = state,
	}
end

local function handleRequest(player, action)
	action = tostring(action or "")
	local cooldown = if action == "RecordAttempt" then 0.2 else 0

	local guardOk, guardReason = RemoteGuard.Check(player, REMOTE_NAME, { action }, {
		Cooldown = cooldown,
		ActionIndex = 1,
		ActionAllowlist = ACTION_ALLOWLIST,
		Args = {
			{
				Type = "string",
				MaxLength = 32,
			},
		},
	})
	if guardOk ~= true then
		return response(false, guardReason or "remote_rejected", nil)
	end

	if action == "GetState" then
		local state, reason = buildState(player)
		return response(state ~= nil, reason, state)
	elseif action == "CanPrompt" then
		local allowed, reason, state = canPrompt(player)
		return response(allowed, reason, state)
	elseif action == "RecordAttempt" then
		local recorded, reason, state = recordAttempt(player)
		return response(recorded, reason, state)
	elseif action == "MarkCompleted" then
		local marked, reason, state = markCompleted(player)
		return response(marked, reason, state)
	end

	return response(false, "unknown_action", nil)
end

function FavoritePromptService.Start()
	if started then
		return
	end
	started = true

	ensureRemote()
	requestRemote.OnServerInvoke = handleRequest
end

return FavoritePromptService
