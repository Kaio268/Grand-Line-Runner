local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")
local TextService = game:GetService("TextService")
local HttpService = game:GetService("HttpService")

local EventController = require(game:GetService("ServerScriptService"):WaitForChild("EventController"))

local ADMIN_USER_IDS = {
	1103783585,
	2442286217,
	780333260,
}

local adminSet = {}
for _, id in ipairs(ADMIN_USER_IDS) do
	adminSet[id] = true
end

local function getOrCreateRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

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

local function isCometEvent(name: string)
	return string.lower(tostring(name or "")) == "comet"
end


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
	if not adminSet[player.UserId] then
		return
	end

	if type(message) ~= "string" then
		return
	end

	message = message:gsub("\r", ""):gsub("\n", " ")
	message = message:match("^%s*(.-)%s*$") or ""
	if message == "" then
		return
	end

	message = message:sub(1, 200)

	duration = tonumber(duration) or 10
	duration = math.clamp(duration, 2, 30)

	local filtered = filterBroadcast(player, message)
	if not filtered then
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

	task.spawn(function()
		pcall(function()
			MessagingService:PublishAsync(TOPIC_ANN, payload)
		end)
	end)
end)

luckRequestEvent.OnServerEvent:Connect(function(player, luckValue, timeSeconds)
	if not adminSet[player.UserId] then
		return
	end

	local mult = tonumber(luckValue)
	if not mult then return end
	mult = math.floor(mult)
	if mult < 1 or mult > 256 then return end

	local seconds = tonumber(timeSeconds)
	if not seconds then return end
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
end)

local CometMerchant = require(script.Parent.Modules.CometMerchant)

mainEventRequestEvent.OnServerEvent:Connect(function(player, eventName, timeSeconds)
	if not adminSet[player.UserId] then
		return
	end

	if type(eventName) ~= "string" then return end
	eventName = eventName:gsub("\r", ""):gsub("\n", " ")
	eventName = eventName:match("^%s*(.-)%s*$") or ""
	if eventName == "" then return end
	eventName = eventName:sub(1, 60)

	local seconds = tonumber(timeSeconds)
	if not seconds then return end
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

	local eventName = tostring(data.eventName or "")
	local seconds = tonumber(data.seconds)
	if eventName == "" then return end
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
