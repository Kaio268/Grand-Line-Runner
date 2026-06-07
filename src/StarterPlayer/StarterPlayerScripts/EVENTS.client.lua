local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local mainEventsFolder = nil
local currentEventValue = nil
local eventsFolder = nil
local activeName = nil
local started = false

local function normalizeEventName(name)
	name = tostring(name or "")
	name = name:gsub("\r", ""):gsub("\n", " ")
	name = name:match("^%s*(.-)%s*$") or ""
	if name == "" then
		return "None"
	end
	if name:lower() == "none" then
		return "None"
	end
	return name
end

local function ensureEventsFolder()
	eventsFolder = Workspace:FindFirstChild("Events")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "Events"
		eventsFolder.Parent = Workspace
	end
	return eventsFolder
end

local function clearEvents()
	if not eventsFolder then
		return
	end

	for _, child in ipairs(eventsFolder:GetChildren()) do
		child:Destroy()
	end
end

local function applyEvent(eventNameRaw)
	if not mainEventsFolder or not eventsFolder then
		return
	end

	local eventName = normalizeEventName(eventNameRaw)
	if activeName == eventName then
		return
	end

	local source = mainEventsFolder:FindFirstChild(eventName)
	if not source then
		eventName = "None"
		source = mainEventsFolder:FindFirstChild("None")
	end
	if not source then
		return
	end

	clearEvents()

	local clone = source:Clone()
	clone.Name = source.Name
	clone.Parent = eventsFolder

	activeName = eventName
end

local function tryStart()
	if started then
		return
	end

	mainEventsFolder = mainEventsFolder or ReplicatedStorage:FindFirstChild("MainEvents")
	currentEventValue = currentEventValue or Workspace:FindFirstChild("CurrentEvent")
	if not (mainEventsFolder and mainEventsFolder:IsA("Folder")) then
		return
	end
	if not (currentEventValue and currentEventValue:IsA("StringValue")) then
		return
	end

	started = true
	ensureEventsFolder()
	applyEvent(currentEventValue.Value)

	currentEventValue:GetPropertyChangedSignal("Value"):Connect(function()
		applyEvent(currentEventValue.Value)
	end)
end

ReplicatedStorage.ChildAdded:Connect(function(child)
	if child.Name == "MainEvents" then
		mainEventsFolder = child
		tryStart()
	end
end)

Workspace.ChildAdded:Connect(function(child)
	if child.Name == "CurrentEvent" then
		currentEventValue = child
		tryStart()
	end
end)

tryStart()
