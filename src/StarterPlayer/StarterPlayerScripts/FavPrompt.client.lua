local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AvatarEditorService = game:GetService("AvatarEditorService")

local modules = ReplicatedStorage:WaitForChild("Modules")
local remotes = ReplicatedStorage:WaitForChild("Remotes")

local GrandLineRushMetaClient = require(modules:WaitForChild("GrandLineRushMetaClient"))
local ReactModalRegistry = require(modules:WaitForChild("ReactModalRegistry"))

local requestRemote = remotes:WaitForChild("FavoritePromptRequest")

local GAME_FAVORITE_ID = game.PlaceId
local GAME_FAVORITE_TYPE = Enum.AvatarItemType.Asset
local DEFAULT_SESSION_DELAY_SECONDS = 30 * 60
local PENDING_RETRY_SECONDS = 10
local SERVER_RETRY_SECONDS = 15
local DAILY_COOLDOWN_RETRY_SECONDS = 5 * 60

local completed = false
local pendingPrompt = false
local promptAttemptedThisSession = false
local evaluatingPrompt = false
local retryScheduled = false
local promptResultPending = false
local initialized = false
local destroyed = false
local serverState = nil
local connections = {}

local function requestServer(action, payload)
	local ok, response = pcall(function()
		return requestRemote:InvokeServer(action, payload)
	end)

	if not ok then
		warn(string.format("[FavoritePrompt] Server request failed action=%s error=%s", tostring(action), tostring(response)))
		return {
			ok = false,
			reason = "remote_error",
		}
	end

	if typeof(response) ~= "table" then
		return {
			ok = false,
			reason = "bad_response",
		}
	end

	if typeof(response.state) == "table" then
		serverState = response.state
		completed = response.state.completed == true
	end

	return response
end

local function isRunActive()
	local state = GrandLineRushMetaClient.GetState()
	local run = state and state.Run
	return typeof(run) == "table" and run.InRun == true
end

local evaluatePendingPrompt

local function queueRetry(delaySeconds)
	if destroyed or completed or promptAttemptedThisSession or retryScheduled then
		return
	end

	retryScheduled = true
	task.delay(math.max(1, tonumber(delaySeconds) or PENDING_RETRY_SECONDS), function()
		retryScheduled = false
		if not destroyed and evaluatePendingPrompt then
			evaluatePendingPrompt("retry")
		end
	end)
end

local function getFavoriteState()
	if GAME_FAVORITE_ID <= 0 then
		return false, "invalid_place_id"
	end

	local ok, result = pcall(function()
		if typeof(AvatarEditorService.GetFavoriteAsync) == "function" then
			return AvatarEditorService:GetFavoriteAsync(GAME_FAVORITE_ID, GAME_FAVORITE_TYPE)
		end
		return AvatarEditorService:GetFavorite(GAME_FAVORITE_ID, GAME_FAVORITE_TYPE)
	end)

	if not ok then
		return false, result
	end

	return result == true, nil
end

local function markCompleted(reason)
	if completed then
		return
	end

	local response = requestServer("MarkCompleted", {
		reason = reason,
	})
	if response.ok == true then
		completed = true
	end
end

local function showFavoritePrompt()
	local favoriteState, favoriteReason = getFavoriteState()
	if favoriteState == true then
		markCompleted("already_favorited")
		return
	elseif favoriteReason ~= nil then
		warn(string.format("[FavoritePrompt] Favorite state check failed: %s", tostring(favoriteReason)))
	end

	local recordResponse = requestServer("RecordAttempt")
	if recordResponse.ok ~= true then
		local reason = tostring(recordResponse.reason or "")
		if reason == "daily_cooldown" then
			local state = recordResponse.state or serverState or {}
			local remaining = tonumber(state.dailyCooldownRemainingSeconds) or DAILY_COOLDOWN_RETRY_SECONDS
			queueRetry(math.min(remaining, DAILY_COOLDOWN_RETRY_SECONDS))
		elseif reason == "not_in_base"
			or reason == "in_run"
			or reason == "data_not_ready"
			or reason == "run_state_unavailable"
			or reason == "base_state_unavailable"
		then
			queueRetry(PENDING_RETRY_SECONDS)
		elseif reason == "completed" then
			completed = true
		else
			promptAttemptedThisSession = true
		end
		return
	end

	promptAttemptedThisSession = true
	promptResultPending = true

	local ok, err = pcall(function()
		AvatarEditorService:PromptSetFavorite(GAME_FAVORITE_ID, GAME_FAVORITE_TYPE, true)
	end)

	if not ok then
		promptResultPending = false
		warn("[FavoritePrompt] Failed to show favorite prompt:", err)
	end
end

evaluatePendingPrompt = function(_reason)
	if destroyed or completed or not pendingPrompt or promptAttemptedThisSession or evaluatingPrompt then
		return
	end

	evaluatingPrompt = true

	if ReactModalRegistry.IsAnyVisible and ReactModalRegistry.IsAnyVisible() then
		evaluatingPrompt = false
		queueRetry(PENDING_RETRY_SECONDS)
		return
	end

	if isRunActive() then
		evaluatingPrompt = false
		queueRetry(PENDING_RETRY_SECONDS)
		return
	end

	local response = requestServer("CanPrompt")
	if response.ok == true then
		showFavoritePrompt()
		evaluatingPrompt = false
		return
	end

	local reason = tostring(response.reason or "")
	if reason == "completed" then
		completed = true
	elseif reason == "daily_cooldown" then
		local state = response.state or serverState or {}
		local remaining = tonumber(state.dailyCooldownRemainingSeconds) or DAILY_COOLDOWN_RETRY_SECONDS
		queueRetry(math.min(remaining, DAILY_COOLDOWN_RETRY_SECONDS))
	elseif reason == "not_in_base"
		or reason == "in_run"
		or reason == "data_not_ready"
		or reason == "run_state_unavailable"
		or reason == "base_state_unavailable"
	then
		queueRetry(PENDING_RETRY_SECONDS)
	else
		queueRetry(SERVER_RETRY_SECONDS)
	end

	evaluatingPrompt = false
end

local function scheduleSessionDelay()
	if completed or initialized then
		return
	end
	initialized = true

	local state = serverState or {}
	local delaySeconds = math.max(DEFAULT_SESSION_DELAY_SECONDS, tonumber(state.nextDelaySeconds) or DEFAULT_SESSION_DELAY_SECONDS)
	task.delay(delaySeconds, function()
		if destroyed or completed or promptAttemptedThisSession then
			return
		end

		pendingPrompt = true
		evaluatePendingPrompt("session_delay")
	end)
end

connections[#connections + 1] = AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result)
	if not promptResultPending then
		return
	end

	promptResultPending = false
	if result == Enum.AvatarPromptResult.Success then
		markCompleted("prompt_success")
	end
end)

connections[#connections + 1] = ReactModalRegistry.GetChangedSignal():Connect(function()
	if pendingPrompt then
		evaluatePendingPrompt("modal_changed")
	end
end)

connections[#connections + 1] = GrandLineRushMetaClient.ObserveState(function()
	if pendingPrompt then
		evaluatePendingPrompt("run_state_changed")
	end
end)

task.spawn(function()
	while not destroyed do
		local response = requestServer("GetState")
		if response.ok == true then
			if completed ~= true then
				scheduleSessionDelay()
			end
			return
		end

		task.wait(SERVER_RETRY_SECONDS)
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end)
