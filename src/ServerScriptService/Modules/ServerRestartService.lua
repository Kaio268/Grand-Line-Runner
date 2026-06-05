local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")

local ServerRestartService = {}

local TOPIC = "ServerRestartV1"
local REMOTE_NAME = "ServerRestartAnnouncement"
local FINAL_LOCK_SECONDS = 60
local FLUSH_TIMEOUT_SECONDS = 8
local ANNOUNCEMENT_HOLD_SECONDS = 5
local DUPLICATE_TTL_SECONDS = 900
local ALLOWED_DURATIONS_MINUTES = {
	[1] = true,
	[5] = true,
	[10] = true,
}

local started = false
local subscription = nil
local remoteEvent = nil
local activeRestart = nil
local generation = 0
local seenMessageIds = {}
local announcedByRestartId = {}
local cachedAdminPermissions = nil
local cachedDataManager = nil
local cachedPopUpModule = nil

local function restartLog(message, ...)
	print("[ServerRestart] " .. string.format(message, ...))
end

local function restartWarn(message, ...)
	warn("[ServerRestart] " .. string.format(message, ...))
end

local function getOrCreateRemote()
	if remoteEvent and remoteEvent.Parent == ReplicatedStorage then
		return remoteEvent
	end

	local existing = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
	if existing and not existing:IsA("RemoteEvent") then
		existing:Destroy()
		existing = nil
	end

	if existing then
		remoteEvent = existing
	else
		remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = REMOTE_NAME
		remoteEvent.Parent = ReplicatedStorage
	end

	return remoteEvent
end

local function getAdminPermissions()
	if cachedAdminPermissions ~= nil then
		return cachedAdminPermissions
	end

	cachedAdminPermissions = require(ServerScriptService.Modules:WaitForChild("AdminPermissions"))
	return cachedAdminPermissions
end

local function getDataManager()
	if cachedDataManager ~= nil then
		return cachedDataManager
	end

	cachedDataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	return cachedDataManager
end

local function getPopUpModule()
	if cachedPopUpModule ~= nil then
		return if cachedPopUpModule == false then nil else cachedPopUpModule
	end

	local modulesFolder = ReplicatedStorage:FindFirstChild("Modules")
	local module = modulesFolder and modulesFolder:FindFirstChild("PopUpModule")
	if not module then
		cachedPopUpModule = false
		return nil
	end

	local ok, popUpModule = pcall(require, module)
	if ok and typeof(popUpModule) == "table" then
		cachedPopUpModule = popUpModule
	else
		cachedPopUpModule = false
	end

	return if cachedPopUpModule == false then nil else cachedPopUpModule
end

local function nowUnix()
	return os.time()
end

local function generateId()
	return HttpService:GenerateGUID(false)
end

local function normalizePlayerName(player)
	return player and tostring(player.Name or player.UserId or "unknown") or "server"
end

local function markMessageSeen(messageId)
	local id = tostring(messageId or "")
	if id == "" then
		return false
	end

	local now = os.clock()
	for seenId, seenAt in pairs(seenMessageIds) do
		if now - seenAt > DUPLICATE_TTL_SECONDS then
			seenMessageIds[seenId] = nil
		end
	end

	if seenMessageIds[id] ~= nil then
		return false
	end

	seenMessageIds[id] = now
	return true
end

local function getRemainingSeconds(info)
	info = info or activeRestart
	if typeof(info) ~= "table" then
		return 0
	end

	return math.max(0, math.floor((tonumber(info.EndsAtUnix) or 0) - nowUnix()))
end

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	if seconds >= 60 then
		local minutes = math.floor(seconds / 60)
		return string.format("%d minute%s", minutes, minutes == 1 and "" or "s")
	end

	return string.format("%d second%s", seconds, seconds == 1 and "" or "s")
end

local function getAnnouncedSet(restartId)
	local key = tostring(restartId or "")
	local set = announcedByRestartId[key]
	if typeof(set) ~= "table" then
		set = {}
		announcedByRestartId[key] = set
	end
	return set
end

local function fireAnnouncement(message, options)
	options = if typeof(options) == "table" then options else {}
	local event = getOrCreateRemote()
	event:FireAllClients({
		Kind = tostring(options.Kind or "Restart"),
		Message = tostring(message or ""),
		RestartId = tostring(options.RestartId or (activeRestart and activeRestart.RestartId) or ""),
		RemainingSeconds = math.max(0, math.floor(tonumber(options.RemainingSeconds) or getRemainingSeconds())),
		Duration = math.max(0.5, tonumber(options.Duration) or ANNOUNCEMENT_HOLD_SECONDS),
		Sticky = options.Sticky == true,
		SentAtUnix = nowUnix(),
	})
end

local function announceMilestone(info, remainingSeconds, message, sticky)
	if typeof(info) ~= "table" or activeRestart == nil or activeRestart.RestartId ~= info.RestartId then
		return
	end

	local announcedSet = getAnnouncedSet(info.RestartId)
	local key = tostring(remainingSeconds)
	if announcedSet[key] == true then
		return
	end
	announcedSet[key] = true

	fireAnnouncement(message, {
		RestartId = info.RestartId,
		RemainingSeconds = remainingSeconds,
		Duration = if sticky then 12 else ANNOUNCEMENT_HOLD_SECONDS,
		Sticky = sticky == true,
	})
end

local function scheduleMilestone(info, remainingSeconds, message, sticky)
	local delaySeconds = math.max(0, (tonumber(info.EndsAtUnix) or nowUnix()) - nowUnix() - remainingSeconds)
	local scheduledGeneration = generation

	task.delay(delaySeconds, function()
		if generation ~= scheduledGeneration then
			return
		end

		if activeRestart == nil or activeRestart.RestartId ~= info.RestartId then
			return
		end

		announceMilestone(info, remainingSeconds, message, sticky)
	end)
end

local function publishMessage(payload)
	local ok, err = pcall(function()
		MessagingService:PublishAsync(TOPIC, payload)
	end)

	if not ok then
		restartWarn("publish failed type=%s restartId=%s err=%s", tostring(payload.Type), tostring(payload.RestartId), tostring(err))
		return false, err
	end

	return true, nil
end

local function beginRestart(payload, source)
	if typeof(payload) ~= "table" then
		return false, "invalid_payload"
	end

	local restartId = tostring(payload.RestartId or "")
	if restartId == "" then
		return false, "missing_restart_id"
	end

	if activeRestart ~= nil and activeRestart.RestartId == restartId then
		return true, "duplicate_restart"
	end
	if activeRestart ~= nil then
		return false, "restart_already_pending"
	end

	local durationSeconds = math.max(1, math.floor(tonumber(payload.DurationSeconds) or 0))
	local startsAt = math.floor(tonumber(payload.StartedAtUnix) or nowUnix())
	local endsAt = math.floor(tonumber(payload.EndsAtUnix) or (startsAt + durationSeconds))
	local remaining = math.max(0, endsAt - nowUnix())
	if remaining <= 0 then
		return false, "restart_already_elapsed"
	end

	generation += 1
	activeRestart = {
		RestartId = restartId,
		DurationSeconds = durationSeconds,
		StartedAtUnix = startsAt,
		EndsAtUnix = endsAt,
		RequestedBy = tostring(payload.RequestedBy or "unknown"),
		RequestedByUserId = tonumber(payload.RequestedByUserId) or 0,
		Source = tostring(source or payload.Source or "unknown"),
	}
	announcedByRestartId[restartId] = {}

	local startMessage = string.format(
		"Server update in %s. You will be moved to a fresh server automatically.",
		formatDuration(remaining)
	)
	announceMilestone(activeRestart, remaining, startMessage, false)

	if remaining > 600 then
		scheduleMilestone(activeRestart, 600, "Server update in 10 minutes.", false)
	end
	if remaining > 300 then
		scheduleMilestone(activeRestart, 300, "Server update in 5 minutes.", false)
	end
	if remaining > 60 then
		scheduleMilestone(activeRestart, 60, "Server update in 1 minute. Please avoid starting new actions.", false)
	end
	if remaining > 30 then
		scheduleMilestone(activeRestart, 30, "Server update in 30 seconds.", false)
	end
	if remaining > 10 then
		scheduleMilestone(activeRestart, 10, "Restarting in 10 seconds.", true)
	end
	if remaining > 5 then
		scheduleMilestone(activeRestart, 5, "Restarting in 5 seconds.", true)
	end

	local finalGeneration = generation
	task.delay(remaining, function()
		if generation ~= finalGeneration or activeRestart == nil or activeRestart.RestartId ~= restartId then
			return
		end

		announceMilestone(activeRestart, 0, "Restarting now.", true)

		local flushOk, flushSummary = true, nil
		local dataManagerOk, dataManager = pcall(getDataManager)
		if not dataManagerOk then
			flushOk = false
			flushSummary = { Error = tostring(dataManager) }
			dataManager = nil
		end
		if dataManager and typeof(dataManager.FlushActiveProfilesForTeleport) == "function" then
			local ok, resultOk, resultSummary = pcall(function()
				return dataManager:FlushActiveProfilesForTeleport(FLUSH_TIMEOUT_SECONDS)
			end)
			if ok then
				flushOk = resultOk == true
				flushSummary = resultSummary
			else
				flushOk = false
				flushSummary = { Error = tostring(resultOk) }
			end
		end
		if not flushOk then
			restartWarn("profile flush before teleport incomplete summary=%s", HttpService:JSONEncode(flushSummary or {}))
		end

		local players = Players:GetPlayers()
		if #players <= 0 then
			activeRestart = nil
			return
		end

		local teleportOk, teleportErr = pcall(function()
			TeleportService:TeleportAsync(game.PlaceId, players)
		end)
		if not teleportOk then
			restartWarn("TeleportAsync failed placeId=%s players=%d err=%s", tostring(game.PlaceId), #players, tostring(teleportErr))
			activeRestart = nil
			return
		end

		activeRestart = nil
	end)

	restartLog(
		"restart scheduled restartId=%s remaining=%ds requestedBy=%s source=%s",
		restartId,
		remaining,
		tostring(activeRestart.RequestedBy),
		tostring(source)
	)

	return true, string.format("restart scheduled for %s", formatDuration(remaining))
end

local function cancelRestart(payload, source)
	local restartId = activeRestart and activeRestart.RestartId or tostring(payload and payload.RestartId or "")
	if activeRestart == nil then
		return true, "no_restart_pending"
	end

	local cancelAll = typeof(payload) == "table" and payload.CancelAll == true
	local targetRestartId = typeof(payload) == "table" and tostring(payload.RestartId or "") or ""
	if not cancelAll and targetRestartId ~= "" and targetRestartId ~= activeRestart.RestartId then
		return false, "restart_id_mismatch"
	end

	generation += 1
	activeRestart = nil
	fireAnnouncement("Server restart cancelled.", {
		Kind = "Cancel",
		RestartId = restartId,
		Duration = ANNOUNCEMENT_HOLD_SECONDS,
		Sticky = false,
		RemainingSeconds = 0,
	})

	restartLog("restart cancelled restartId=%s source=%s", restartId, tostring(source))
	return true, "restart cancelled"
end

local function handleRestartMessage(payload, source)
	if typeof(payload) ~= "table" then
		return
	end

	if not markMessageSeen(payload.MessageId) then
		return
	end

	local messageType = tostring(payload.Type or "")
	if messageType == "Start" then
		beginRestart(payload, source)
	elseif messageType == "Cancel" then
		cancelRestart(payload, source)
	end
end

function ServerRestartService.Start()
	if started then
		return
	end
	started = true

	getOrCreateRemote()

	local ok, subscribeResult = pcall(function()
		return MessagingService:SubscribeAsync(TOPIC, function(message)
			handleRestartMessage(message.Data, "MessagingService")
		end)
	end)

	if ok then
		subscription = subscribeResult
	else
		restartWarn("SubscribeAsync failed topic=%s err=%s", TOPIC, tostring(subscribeResult))
	end
end

function ServerRestartService.IsRestartPending()
	return activeRestart ~= nil and getRemainingSeconds(activeRestart) > 0
end

function ServerRestartService.IsFinalMinuteLocked()
	return ServerRestartService.IsRestartPending() and getRemainingSeconds(activeRestart) <= FINAL_LOCK_SECONDS
end

function ServerRestartService.GetActiveRestartInfo()
	if activeRestart == nil then
		return nil
	end

	local info = table.clone(activeRestart)
	info.RemainingSeconds = getRemainingSeconds(activeRestart)
	info.FinalMinuteLocked = ServerRestartService.IsFinalMinuteLocked()
	return info
end

function ServerRestartService.GetFinalMinuteLockMessage(actionName)
	local actionText = tostring(actionName or "doing that")
	return "Server restart is in its final minute. Please wait for the fresh server before " .. actionText .. "."
end

function ServerRestartService.NotifyActionBlocked(player, actionName)
	local message = ServerRestartService.GetFinalMinuteLockMessage(actionName)
	local popUpModule = getPopUpModule()
	if popUpModule ~= nil and typeof(popUpModule.Server_SendPopUp) == "function" then
		pcall(function()
			popUpModule:Server_SendPopUp(
				player,
				message,
				Color3.fromRGB(255, 205, 86),
				Color3.fromRGB(0, 0, 0),
				3,
				true
			)
		end)
	end

	return message
end

function ServerRestartService.RejectIfFinalMinuteLocked(player, actionName)
	if not ServerRestartService.IsFinalMinuteLocked() then
		return false, nil
	end

	return true, ServerRestartService.NotifyActionBlocked(player, actionName)
end

function ServerRestartService.HandleCommand(player, argumentText, source)
	ServerRestartService.Start()

	local adminPermissions = getAdminPermissions()
	if typeof(adminPermissions) ~= "table" or typeof(adminPermissions.IsAdmin) ~= "function" or adminPermissions.IsAdmin(player) ~= true then
		return false, "restart_requires_admin"
	end

	local argument = tostring(argumentText or ""):lower():match("^%s*(.-)%s*$") or ""
	if argument == "cancel" then
		local payload = {
			MessageId = generateId(),
			Type = "Cancel",
			RestartId = activeRestart and activeRestart.RestartId or "",
			CancelAll = true,
			RequestedBy = normalizePlayerName(player),
			RequestedByUserId = player.UserId,
			SentAtUnix = nowUnix(),
			Source = tostring(source or "AdminCommand"),
		}
		markMessageSeen(payload.MessageId)
		local published = publishMessage(payload)
		if published ~= true then
			return false, "restart_cancel_publish_failed"
		end
		local ok, detail = cancelRestart(payload, source or "AdminCommand")
		return ok, detail
	end

	local minutes = tonumber(argument)
	if minutes == nil or minutes % 1 ~= 0 or ALLOWED_DURATIONS_MINUTES[minutes] ~= true then
		return false, "usage=/restart 10 | /restart 5 | /restart 1 | /restart cancel"
	end

	if ServerRestartService.IsRestartPending() then
		return false, string.format("restart_already_pending remaining=%s", formatDuration(getRemainingSeconds(activeRestart)))
	end

	local sentAt = nowUnix()
	local payload = {
		MessageId = generateId(),
		Type = "Start",
		RestartId = generateId(),
		DurationSeconds = minutes * 60,
		StartedAtUnix = sentAt,
		EndsAtUnix = sentAt + (minutes * 60),
		RequestedBy = normalizePlayerName(player),
		RequestedByUserId = player.UserId,
		Source = tostring(source or "AdminCommand"),
	}

	markMessageSeen(payload.MessageId)
	local published = publishMessage(payload)
	if published ~= true then
		return false, "restart_publish_failed"
	end
	local ok, detail = beginRestart(payload, source or "AdminCommand")

	return ok, detail
end

function ServerRestartService.Destroy()
	if subscription then
		pcall(function()
			subscription:Disconnect()
		end)
		subscription = nil
	end

	started = false
	generation += 1
	activeRestart = nil
end

return ServerRestartService
