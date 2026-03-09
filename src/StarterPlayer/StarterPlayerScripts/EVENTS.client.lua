local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local mainEventsFolder = ReplicatedStorage:WaitForChild("MainEvents")
local currentEventValue = Workspace:WaitForChild("CurrentEvent")

local eventsFolder = Workspace:FindFirstChild("Events")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = Workspace
end

local activeName = nil

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

local function clearEvents()
	for _, child in ipairs(eventsFolder:GetChildren()) do
		child:Destroy()
	end
end

local function applyEvent(eventNameRaw)
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

applyEvent(currentEventValue.Value)

currentEventValue:GetPropertyChangedSignal("Value"):Connect(function()
	applyEvent(currentEventValue.Value)
end)
