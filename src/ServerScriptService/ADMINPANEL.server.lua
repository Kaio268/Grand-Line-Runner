local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local ServerScriptService = game:GetService("ServerScriptService")
local EventController = require(ServerScriptService:WaitForChild("EventController"))
local AdminPermissions = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AdminPermissions"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))

local function getOrCreateRemote(name, className)
	className = className or "RemoteEvent"
	local r = ReplicatedStorage:FindFirstChild(name)
	if r and not r:IsA(className) then
		r:Destroy()
		r = nil
	end
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local adminStatusFunction = getOrCreateRemote("AdminStatusRequest", "RemoteFunction")
local adminRosterFunction = getOrCreateRemote("AdminRosterRequest", "RemoteFunction")
local adminTesterRoleFunction = getOrCreateRemote("AdminTesterRoleRequest", "RemoteFunction")
local adminConsoleActionFunction = getOrCreateRemote("AdminConsoleActionRequest", "RemoteFunction")
local adminRosterUpdatedEvent = getOrCreateRemote("AdminRosterUpdated")
local requestEvent = getOrCreateRemote("AdminAnnouncementRequest")
local broadcastEvent = getOrCreateRemote("AdminAnnouncementBroadcast")

local luckRequestEvent = getOrCreateRemote("AdminLuckRequest")
local luckAppliedEvent = getOrCreateRemote("AdminLuckApplied")

local mainEventRequestEvent = getOrCreateRemote("AdminMainEventRequest")
local mainEventAppliedEvent = getOrCreateRemote("AdminMainEventApplied")

local TOPIC_ANN = "AdminAnnouncementsV1"
local TOPIC_LUCK = "ServerLuckV1"
local TOPIC_MAIN_EVENT = "MainEventsV1"

local seenAnn = {}
local seenLuck = {}
local seenMain = {}

local MAIN_EVENT_ALLOWLIST = {
	none = "none",
	comet = "Comet",
	luckyblock = "LuckyBlock",
	luckyblocks = "LuckyBlock",
}

local TESTER_ROLE_ACTIONS = {
	AddTester = true,
	RemoveTester = true,
}

local ADMIN_CONSOLE_ACTIONS = {
	AddTester = true,
	SetTester = true,
	RemoveTester = true,
	AddAdmin = true,
	SetAdmin = true,
	RemoveAdmin = true,
	AddSuperAdmin = true,
	SetSuperAdmin = true,
	RemoveSuperAdmin = true,
	Kick = true,
}

local function fireAdminRosterUpdated(reason)
	local payload = {
		Reason = tostring(reason or "roster_changed"),
		SentAt = os.time(),
	}

	for _, player in ipairs(Players:GetPlayers()) do
		if AdminPermissions.CanViewAdminConsole(player) then
			adminRosterUpdatedEvent:FireClient(player, payload)
		end
	end
end

local function getAllowedMainEventName(eventName)
	local trimmed = tostring(eventName or ""):gsub("\r", ""):gsub("\n", " ")
	trimmed = trimmed:match("^%s*(.-)%s*$") or ""
	local key = string.lower(trimmed):gsub("%s+", "")
	return MAIN_EVENT_ALLOWLIST[key]
end

local function isCometEvent(name: string)
	return getAllowedMainEventName(name) == "Comet"
end

adminStatusFunction.OnServerInvoke = function(player)
	AdminPermissions.LogAdminStatusRequest(player, "AdminStatusRequest")
	return AdminPermissions.CanViewAdminConsole(player)
end

adminRosterFunction.OnServerInvoke = function(player)
	AdminPermissions.LogAdminStatusRequest(player, "AdminRosterRequest")
	if not AdminPermissions.CanViewAdminConsole(player) then
		AdminPermissions.LogCommandRejected(player, "adminRoster", "AdminRosterRequest", "reason=not_admin")
		return {
			Success = false,
			Message = "Admin access required.",
		}
	end

	return AdminPermissions.GetAdminRoster(player)
end

adminTesterRoleFunction.OnServerInvoke = function(player, action, target)
	if not RemoteGuard.Check(player, "AdminTesterRoleRequest", { action, target }, {
		Cooldown = 0.5,
		ActionIndex = 1,
		ActionAllowlist = TESTER_ROLE_ACTIONS,
		Args = {
			{ Type = "string", MaxLength = 24 },
			{ Type = "string", MaxLength = 80 },
		},
	}) then
		return {
			Success = false,
			Message = "Invalid tester role request.",
		}
	end

	if not AdminPermissions.CanViewAdminConsole(player) then
		AdminPermissions.LogCommandRejected(player, "testerRole", "AdminTesterRoleRequest", "reason=not_admin")
		return {
			Success = false,
			Message = "Admin access required.",
		}
	end

	return AdminPermissions.SetTesterRole(player, target, action == "AddTester", "AdminTesterRoleRequest")
end

adminConsoleActionFunction.OnServerInvoke = function(player, payload)
	if not RemoteGuard.Check(player, "AdminConsoleActionRequest", { payload }, {
		Cooldown = 0.5,
		Args = {
			{ Type = "table" },
		},
	}) then
		return {
			Success = false,
			Message = "Invalid admin console request.",
		}
	end

	local action = tostring(payload.Action or "")
	if ADMIN_CONSOLE_ACTIONS[action] ~= true then
		AdminPermissions.LogCommandRejected(player, "adminConsole", "AdminConsoleActionRequest", "reason=unsupported_action")
		return {
			Success = false,
			Message = "Unsupported admin console action.",
		}
	end

	return AdminPermissions.ApplyAdminConsoleAction(player, payload)
end

AdminPermissions.TesterStateChanged:Connect(function(_, payload)
	local reason = "tester_state_changed"
	if typeof(payload) == "table" and typeof(payload.Source) == "string" then
		reason = payload.Source
	end
	fireAdminRosterUpdated(reason)
end)

AdminPermissions.StaffRoleStateChanged:Connect(function(_, payload)
	local reason = "staff_role_changed"
	if typeof(payload) == "table" and typeof(payload.Source) == "string" then
		reason = payload.Source
	end
	fireAdminRosterUpdated(reason)
end)

Players.PlayerAdded:Connect(function()
	task.defer(function()
		fireAdminRosterUpdated("player_added")
	end)
end)

Players.PlayerRemoving:Connect(function()
	fireAdminRosterUpdated("player_removing")
end)

local function markSeen(tbl, id)
	tbl[id] = os.clock()
end

task.spawn(function()
	while true do
		local now = os.clock()
		for k, t in pairs(seenAnn) do
			if now - t > 30 then
				seenAnn[k] = nil
			end
		end
		for k, t in pairs(seenLuck) do
			if now - t > 30 then
				seenLuck[k] = nil
			end
		end
		for k, t in pairs(seenMain) do
			if now - t > 30 then
				seenMain[k] = nil
			end
		end
		task.wait(10)
	end
end)

local function filterBroadcast(player, msg)
	local ok, res = pcall(function()
		local fr = TextService:FilterStringAsync(msg, player.UserId)
		return fr:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(res) == "string" and res ~= "" then
		return res
	end
	return nil
end

local function fireAll(payload)
	broadcastEvent:FireAllClients(payload)
end

local function getOrCreateNumberValue(parent, name, defaultValue)
	local v = parent:FindFirstChild(name)
	if not v then
		v = Instance.new("NumberValue")
		v.Name = name
		v.Value = defaultValue or 0
		v.Parent = parent
	end
	return v
end

local function setLuckValues(multiplier, seconds)
	local luckVal = getOrCreateNumberValue(workspace, "ServerLuck", 1)
	local timerVal = getOrCreateNumberValue(workspace, "ServerLuckTimer", 0)
	luckVal.Value = multiplier
	timerVal.Value = seconds
end

local function plural(n, s)
	if n == 1 then
		return ("%d %s"):format(n, s)
	end
	return ("%d %ss"):format(n, s)
end

local function formatDuration(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return plural(seconds, "second")
	end
	local minutes = math.floor(seconds / 60)
	local sec = seconds % 60
	if minutes < 60 then
		if sec == 0 then
			return plural(minutes, "minute")
		end
		return ("%s %s"):format(plural(minutes, "minute"), plural(sec, "second"))
	end
	local hours = math.floor(minutes / 60)
	local min = minutes % 60
	if min == 0 then
		return plural(hours, "hour")
	end
	return ("%s %s"):format(plural(hours, "hour"), plural(min, "minute"))
end

requestEvent.OnServerEvent:Connect(function(player, message, duration)
	-- Security: admin remotes still require admin status, but RemoteGuard rejects malformed or spammed payloads first.
	if not RemoteGuard.Check(player, "AdminAnnouncementRequest", { message, duration }, {
		Cooldown = 1,
		Args = {
			{ Type = "string", MaxLength = 240 },
			{ Type = "finiteNumber", AllowNil = true, Min = 1, Max = 86400 },
		},
	}) then
		return
	end

	AdminPermissions.LogCommandAttempt(player, "announcement", "remote", string.format("duration=%s", tostring(duration)))
	if not AdminPermissions.IsAdmin(player) then
		AdminPermissions.LogCommandRejected(player, "announcement", "remote")
		return
	end

	if type(message) ~= "string" then
		AdminPermissions.LogCommandFailed(player, "announcement", "remote", "message must be text")
		return
	end

	message = message:gsub("\r", ""):gsub("\n", " ")
	message = message:match("^%s*(.-)%s*$") or ""
	if message == "" then
		AdminPermissions.LogCommandFailed(player, "announcement", "remote", "message is empty")
		return
	end

	message = message:sub(1, 200)

	duration = tonumber(duration) or 10
	duration = math.clamp(duration, 2, 30)

	local filtered = filterBroadcast(player, message)
	if not filtered then
		AdminPermissions.LogCommandFailed(player, "announcement", "remote", "message failed Roblox text filtering")
		return
	end

	local payload = {
		id = HttpService:GenerateGUID(false),
		adminName = player.DisplayName or player.Name,
		adminUserId = player.UserId,
		message = filtered,
		duration = duration,
		sentAt = os.time(),
	}

	markSeen(seenAnn, payload.id)
	fireAll(payload)
	AdminPermissions.LogCommandExecuted(player, "announcement", "remote", string.format("message=%s duration=%d", filtered, duration))

	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC_ANN, payload)
		end)
	end)
end)

luckRequestEvent.OnServerEvent:Connect(function(player, luckValue, timeSeconds)
	-- Security: reject invalid numbers before mutating server-wide luck state.
	if not RemoteGuard.Check(player, "AdminLuckRequest", { luckValue, timeSeconds }, {
		Cooldown = 1,
		Args = {
			{ Type = "finiteNumber", Min = 1, Max = 256 },
			{ Type = "finiteNumber", Min = 1, Max = 86400 },
		},
	}) then
		return
	end

	AdminPermissions.LogCommandAttempt(player, "serverLuck", "remote", string.format(
		"luckValue=%s timeSeconds=%s",
		tostring(luckValue),
		tostring(timeSeconds)
	))
	if not AdminPermissions.IsAdmin(player) then
		AdminPermissions.LogCommandRejected(player, "serverLuck", "remote")
		return
	end

	local mult = tonumber(luckValue)
	if not mult then
		AdminPermissions.LogCommandFailed(player, "serverLuck", "remote", "multiplier must be a number")
		return
	end
	mult = math.floor(mult)
	if mult < 1 or mult > 256 then
		AdminPermissions.LogCommandFailed(player, "serverLuck", "remote", "multiplier must be between 1 and 256")
		return
	end

	local seconds = tonumber(timeSeconds)
	if not seconds then
		AdminPermissions.LogCommandFailed(player, "serverLuck", "remote", "duration must be a number")
		return
	end
	seconds = math.floor(seconds)
	seconds = math.clamp(seconds, 1, 86400)

	setLuckValues(mult, seconds)

	local luckId = HttpService:GenerateGUID(false)
	markSeen(seenLuck, luckId)

	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC_LUCK, {
				id = luckId,
				multiplier = mult,
				seconds = seconds,
			})
		end)
	end)

	local adminName = player.DisplayName or player.Name
	print(("%s activated x%d Luck for %s"):format(adminName, mult, formatDuration(seconds)))

	local msg = ("activated x%d Luck for %s"):format(mult, formatDuration(seconds))
	local filteredMsg = filterBroadcast(player, msg) or msg

	local payload = {
		id = HttpService:GenerateGUID(false),
		adminName = adminName,
		adminUserId = player.UserId,
		message = filteredMsg,
		duration = 8,
		sentAt = os.time(),
	}

	markSeen(seenAnn, payload.id)
	fireAll(payload)

	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC_ANN, payload)
		end)
	end)

	luckAppliedEvent:FireClient(player, mult, seconds)
	AdminPermissions.LogCommandExecuted(player, "serverLuck", "remote", string.format("x%d for %s", mult, formatDuration(seconds)))
end)

local CometMerchant = require(script.Parent.Modules.CometMerchant)

mainEventRequestEvent.OnServerEvent:Connect(function(player, eventName, timeSeconds)
	-- Security: only known event names can reach EventController or cross-server MessagingService.
	if not RemoteGuard.Check(player, "AdminMainEventRequest", { eventName, timeSeconds }, {
		Cooldown = 1,
		Args = {
			{ Type = "string", MaxLength = 80 },
			{ Type = "finiteNumber", Min = 1, Max = 86400 },
		},
	}) then
		return
	end

	AdminPermissions.LogCommandAttempt(player, "mainEvent", "remote", string.format(
		"eventName=%s timeSeconds=%s",
		tostring(eventName),
		tostring(timeSeconds)
	))
	if not AdminPermissions.IsAdmin(player) then
		AdminPermissions.LogCommandRejected(player, "mainEvent", "remote")
		return
	end

	if type(eventName) ~= "string" then
		AdminPermissions.LogCommandFailed(player, "mainEvent", "remote", "event name must be text")
		return
	end
	eventName = eventName:gsub("\r", ""):gsub("\n", " ")
	eventName = eventName:match("^%s*(.-)%s*$") or ""
	if eventName == "" then
		AdminPermissions.LogCommandFailed(player, "mainEvent", "remote", "event name is empty")
		return
	end
	eventName = eventName:sub(1, 60)
	local allowedEventName = getAllowedMainEventName(eventName)
	if not allowedEventName then
		AdminPermissions.LogCommandRejected(player, "mainEvent", "remote", "reason=event_not_allowlisted")
		return
	end
	eventName = allowedEventName

	local seconds = tonumber(timeSeconds)
	if not seconds then
		AdminPermissions.LogCommandFailed(player, "mainEvent", "remote", "duration must be a number")
		return
	end
	seconds = math.floor(seconds)
	seconds = math.clamp(seconds, 1, 86400)

	EventController:StartEvent(eventName, seconds)

	local adminName = player.DisplayName or player.Name
	local prettyTime = formatDuration(seconds)

	print(("%s activated \"%s\" event for %s"):format(adminName, eventName, prettyTime))

	local mainId = HttpService:GenerateGUID(false)
	markSeen(seenMain, mainId)

	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC_MAIN_EVENT, {
				id = mainId,
				adminName = adminName,
				adminUserId = player.UserId,
				eventName = eventName,
				seconds = seconds,
				sentAt = os.time(),
			})
		end)
	end)

	local msg = ("activated %s event for %s"):format(eventName, prettyTime)
	local filteredMsg = filterBroadcast(player, msg) or msg

	local payload = {
		id = HttpService:GenerateGUID(false),
		adminName = adminName,
		adminUserId = player.UserId,
		message = filteredMsg,
		duration = 8,
		sentAt = os.time(),
	}

	markSeen(seenAnn, payload.id)
	fireAll(payload)
 	
 


	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC_ANN, payload)
		end)
	end)

	mainEventAppliedEvent:FireClient(player, eventName, seconds)
	AdminPermissions.LogCommandExecuted(player, "mainEvent", "remote", string.format("%s for %s", eventName, formatDuration(seconds)))
end)

local function onAnnMessage(msg)
	local data = msg.Data
	if type(data) ~= "table" then return end
	local id = data.id
	if type(id) ~= "string" then return end
	if seenAnn[id] then return end
	markSeen(seenAnn, id)
	fireAll(data)
end

local function onLuckMessage(msg)
	local data = msg.Data
	if type(data) ~= "table" then return end
	local id = data.id
	if type(id) ~= "string" then return end
	if seenLuck[id] then return end
	markSeen(seenLuck, id)

	local mult = tonumber(data.multiplier)
	local seconds = tonumber(data.seconds)
	if not mult or not seconds then return end
	mult = math.floor(mult)
	seconds = math.floor(seconds)
	if mult < 1 or mult > 256 then return end
	if seconds < 1 or seconds > 86400 then return end

	setLuckValues(mult, seconds)
end

local function onMainEventMessage(msg)
	local data = msg.Data
	if type(data) ~= "table" then return end
	local id = data.id
	if type(id) ~= "string" then return end
	if seenMain[id] then return end
	markSeen(seenMain, id)

	local eventName = getAllowedMainEventName(data.eventName)
	local seconds = tonumber(data.seconds)
	if eventName == nil then return end
	if not seconds then return end
	seconds = math.floor(seconds)
	seconds = math.clamp(seconds, 1, 86400)

	EventController:StartEvent(eventName, seconds)

	if isCometEvent(eventName) then
		CometMerchant:ResetStock()
	end

	local adminName = tostring(data.adminName or "Admin")
	local prettyTime = formatDuration(seconds)

	print(("%s activated \"%s\" event for %s"):format(adminName, eventName, prettyTime))
end


pcall(function()
	MessagingService:SubscribeAsync(TOPIC_ANN, onAnnMessage)
end)

pcall(function()
	MessagingService:SubscribeAsync(TOPIC_LUCK, onLuckMessage)
end)

pcall(function()
	MessagingService:SubscribeAsync(TOPIC_MAIN_EVENT, onMainEventMessage)
end)
