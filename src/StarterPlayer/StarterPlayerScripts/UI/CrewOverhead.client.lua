local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local CrewOverheadBillboard = require(UiFolder:WaitForChild("Crew"):WaitForChild("CrewOverheadBillboard"))

local OVERHEAD_ATTRIBUTES = CrewOverhead.Attribute
local CARRIED_MODEL_ATTRIBUTE = "CrewCarryHeld"

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactCrewOverheadRoot"

local portalHost = Instance.new("ScreenGui")
portalHost.Name = "ReactCrewOverheadLayer"
portalHost.IgnoreGuiInset = true
portalHost.ResetOnSpawn = false
portalHost.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
portalHost.Parent = playerGui

local root = ReactRoblox.createRoot(rootContainer)
local changedEvent = Instance.new("BindableEvent")
local trackedModels = {}
local modelConnections = {}
local nextModelKey = 0

local function disconnectModel(model)
	local connections = modelConnections[model]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	modelConnections[model] = nil
	trackedModels[model] = nil
end

local function fireChanged()
	changedEvent:Fire()
end

local function getAdornee(model)
	if not model or not model.Parent or not model:IsA("Model") then
		return nil
	end

	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function connectModel(model)
	if trackedModels[model] or not model:IsA("Model") then
		return
	end

	nextModelKey += 1
	trackedModels[model] = tostring(nextModelKey)
	local connections = {}
	for _, attributeName in pairs(OVERHEAD_ATTRIBUTES) do
		connections[#connections + 1] = model:GetAttributeChangedSignal(attributeName):Connect(fireChanged)
	end
	connections[#connections + 1] = model:GetAttributeChangedSignal(CARRIED_MODEL_ATTRIBUTE):Connect(fireChanged)
	connections[#connections + 1] = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectModel(model)
			fireChanged()
		end
	end)
	connections[#connections + 1] = model:GetPropertyChangedSignal("PrimaryPart"):Connect(fireChanged)
	modelConnections[model] = connections
	fireChanged()
end

local function buildEntries(now)
	local entries = {}

	for model, key in pairs(trackedModels) do
		local adornee = getAdornee(model)
		local kind = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.Kind) or "")
		if adornee and kind ~= "" then
			local expiresAt = tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.ExpiresAt))
			entries[#entries + 1] = {
				key = key,
				adornee = adornee,
				kind = kind,
				displayName = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.DisplayName) or "Crewmate"),
				rarity = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.Rarity) or "Common"),
				variant = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.Variant) or "Normal"),
				incomePerSecond = tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.IncomePerSecond)) or 0,
				held = model:GetAttribute(CARRIED_MODEL_ATTRIBUTE) == true,
				remaining = if expiresAt then math.max(0, expiresAt - now) else nil,
			}
		end
	end

	table.sort(entries, function(a, b)
		return tostring(a.key) < tostring(b.key)
	end)

	return entries
end

local function CrewOverheadLayer()
	local _, setRevision = React.useState(0)
	local now, setNow = React.useState(Workspace:GetServerTimeNow())

	React.useEffect(function()
		local changedConnection = changedEvent.Event:Connect(function()
			setRevision(function(value)
				return value + 1
			end)
		end)

		local running = true
		task.spawn(function()
			while running do
				task.wait(1)
				setNow(Workspace:GetServerTimeNow())
			end
		end)

		return function()
			running = false
			changedConnection:Disconnect()
		end
	end, {})

	local entries = buildEntries(now)
	local children = {}
	for _, entry in ipairs(entries) do
		children[entry.key] = React.createElement(CrewOverheadBillboard, {
			entry = entry,
		})
	end

	return ReactRoblox.createPortal(children, portalHost)
end

for _, model in ipairs(CollectionService:GetTagged(CrewOverhead.Tag)) do
	connectModel(model)
end

local addedConnection = CollectionService:GetInstanceAddedSignal(CrewOverhead.Tag):Connect(connectModel)
local removedConnection = CollectionService:GetInstanceRemovedSignal(CrewOverhead.Tag):Connect(function(model)
	disconnectModel(model)
	fireChanged()
end)
local respawnConnection = player.CharacterAdded:Connect(function()
	fireChanged()
end)

root:render(React.createElement(CrewOverheadLayer))

script.Destroying:Connect(function()
	addedConnection:Disconnect()
	removedConnection:Disconnect()
	respawnConnection:Disconnect()
	for model in pairs(trackedModels) do
		disconnectModel(model)
	end
	changedEvent:Destroy()
	root:unmount()
	rootContainer:Destroy()
	portalHost:Destroy()
end)
