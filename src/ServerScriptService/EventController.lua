local EventController = {}
EventController.__index = EventController

local activeId = 0

local function getOrCreateStringValue(parent, name, defaultValue)
	local v = parent:FindFirstChild(name)
	if not v then
		v = Instance.new("StringValue")
		v.Name = name
		v.Value = defaultValue or ""
		v.Parent = parent
	end
	return v
end

local function getOrCreateIntValue(parent, name, defaultValue)
	local v = parent:FindFirstChild(name)
	if not v then
		v = Instance.new("IntValue")
		v.Name = name
		v.Value = defaultValue or 0
		v.Parent = parent
	end
	return v
end

local function ensureValues()
	local currentEvent = getOrCreateStringValue(workspace, "CurrentEvent", "none")
	local currentTime = getOrCreateIntValue(workspace, "CurrentEventTime", 0)
	return currentEvent, currentTime
end

function EventController:StartEvent(eventName, seconds)
	eventName = tostring(eventName or "")
	eventName = eventName:gsub("\r", ""):gsub("\n", " ")
	eventName = eventName:match("^%s*(.-)%s*$") or ""
	if eventName == "" then
		eventName = "none"
	end

	seconds = tonumber(seconds) or 0
	seconds = math.clamp(math.floor(seconds), 0, 86400)

	activeId += 1
	local myId = activeId

	local currentEvent, currentTime = ensureValues()
	currentEvent.Value = eventName
	currentTime.Value = seconds

	if eventName == "none" or seconds <= 0 then
		currentEvent.Value = "none"
		currentTime.Value = 0
		return
	end

	task.spawn(function()
		while myId == activeId do
			if currentTime.Value <= 0 then
				break
			end
			task.wait(1)
			if myId ~= activeId then
				return
			end
			currentTime.Value = math.max(0, currentTime.Value - 1)
		end

		if myId == activeId then
			currentEvent.Value = "none"
			currentTime.Value = 0
		end
	end)
end

return EventController
