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
local ChestOverhead = require(Modules:WaitForChild("ChestOverhead"))
local CrewOverheadBillboard = require(UiFolder:WaitForChild("Crew"):WaitForChild("CrewOverheadBillboard"))
local ChestOverheadBillboard = require(UiFolder:WaitForChild("ChestOverheadBillboard"))

local OVERHEAD_ATTRIBUTES = CrewOverhead.Attribute
local CHEST_OVERHEAD_ATTRIBUTES = ChestOverhead.Attribute
local CARRIED_MODEL_ATTRIBUTE = "CrewCarryHeld"
local TRACK_KIND_CREW = "Crew"
local TRACK_KIND_CHEST = "Chest"

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

local function getModelOverheadOffsetY(model)
	local ok, _, boxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and typeof(boxSize) == "Vector3" then
		return math.clamp((boxSize.Y / 2) + 1.35, 3.4, 7)
	end

	return 4.6
end

local function connectModel(model, trackKind)
	if trackedModels[model] or not model:IsA("Model") then
		return
	end

	trackKind = trackKind or TRACK_KIND_CREW
	nextModelKey += 1
	trackedModels[model] = {
		key = tostring(nextModelKey),
		trackKind = trackKind,
	}
	local connections = {}
	local attributes = if trackKind == TRACK_KIND_CHEST then CHEST_OVERHEAD_ATTRIBUTES else OVERHEAD_ATTRIBUTES
	for _, attributeName in pairs(attributes) do
		connections[#connections + 1] = model:GetAttributeChangedSignal(attributeName):Connect(fireChanged)
	end
	if trackKind == TRACK_KIND_CREW then
		connections[#connections + 1] = model:GetAttributeChangedSignal(CARRIED_MODEL_ATTRIBUTE):Connect(fireChanged)
	end
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
	local crewEntries = {}
	local chestEntries = {}

	for model, record in pairs(trackedModels) do
		local adornee = getAdornee(model)
		if adornee then
			local key = tostring(record.key or "")
			if record.trackKind == TRACK_KIND_CHEST then
				local kind = tostring(model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.Kind) or "")
				if kind ~= "" then
					local despawnDeadline = tonumber(model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.DespawnDeadlineUnix))
					chestEntries[#chestEntries + 1] = {
						key = key,
						adornee = adornee,
						kind = kind,
						displayName = tostring(model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.DisplayName) or "Chest"),
						tier = tostring(model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.Tier) or "Wooden"),
						typeLabel = tostring(model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.TypeLabel) or "Chest"),
						helperText = tostring(model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.HelperText) or "Extract to open"),
						despawnSeconds = tonumber(model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.DespawnSeconds)),
						dropped = model:GetAttribute(CHEST_OVERHEAD_ATTRIBUTES.Dropped) == true,
						remaining = if despawnDeadline then math.max(0, despawnDeadline - now) else nil,
						offsetY = getModelOverheadOffsetY(model),
					}
				end
			else
				local kind = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.Kind) or "")
				if kind ~= "" then
					local expiresAt = tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.ExpiresAt))
					local variantAttribute = model:GetAttribute(OVERHEAD_ATTRIBUTES.Variant)
					crewEntries[#crewEntries + 1] = {
						key = key,
						adornee = adornee,
						kind = kind,
						displayName = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.DisplayName) or "Crewmate"),
						rarity = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.Rarity) or "Common"),
						variant = if variantAttribute == nil then nil else tostring(variantAttribute),
						incomePerSecond = tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.IncomePerSecond)) or 0,
						beliBoosted = model:GetAttribute(OVERHEAD_ATTRIBUTES.BeliBoosted) == true,
						slotBonusLabel = tostring(model:GetAttribute(OVERHEAD_ATTRIBUTES.SlotBonusLabel) or ""),
						slotBonusPercent = tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.SlotBonusPercent)) or 0,
						held = model:GetAttribute(CARRIED_MODEL_ATTRIBUTE) == true,
						remaining = if expiresAt then math.max(0, expiresAt - now) else nil,
						despawnSeconds = tonumber(model:GetAttribute(OVERHEAD_ATTRIBUTES.DespawnSeconds)),
					}
				end
			end
		end
	end

	table.sort(crewEntries, function(a, b)
		return tostring(a.key) < tostring(b.key)
	end)
	table.sort(chestEntries, function(a, b)
		return tostring(a.key) < tostring(b.key)
	end)

	return crewEntries, chestEntries
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

	local crewEntries, chestEntries = buildEntries(now)
	local children = {}
	for _, entry in ipairs(crewEntries) do
		children["Crew" .. entry.key] = React.createElement(CrewOverheadBillboard, {
			entry = entry,
		})
	end
	for _, entry in ipairs(chestEntries) do
		children["Chest" .. entry.key] = React.createElement(ChestOverheadBillboard, {
			entry = entry,
		})
	end

	return ReactRoblox.createPortal(children, portalHost)
end

for _, model in ipairs(CollectionService:GetTagged(CrewOverhead.Tag)) do
	connectModel(model, TRACK_KIND_CREW)
end
for _, model in ipairs(CollectionService:GetTagged(ChestOverhead.Tag)) do
	connectModel(model, TRACK_KIND_CHEST)
end

local crewAddedConnection = CollectionService:GetInstanceAddedSignal(CrewOverhead.Tag):Connect(function(model)
	connectModel(model, TRACK_KIND_CREW)
end)
local crewRemovedConnection = CollectionService:GetInstanceRemovedSignal(CrewOverhead.Tag):Connect(function(model)
	disconnectModel(model)
	fireChanged()
end)
local chestAddedConnection = CollectionService:GetInstanceAddedSignal(ChestOverhead.Tag):Connect(function(model)
	connectModel(model, TRACK_KIND_CHEST)
end)
local chestRemovedConnection = CollectionService:GetInstanceRemovedSignal(ChestOverhead.Tag):Connect(function(model)
	disconnectModel(model)
	fireChanged()
end)
local respawnConnection = player.CharacterAdded:Connect(function()
	fireChanged()
end)

root:render(React.createElement(CrewOverheadLayer))

script.Destroying:Connect(function()
	crewAddedConnection:Disconnect()
	crewRemovedConnection:Disconnect()
	chestAddedConnection:Disconnect()
	chestRemovedConnection:Disconnect()
	respawnConnection:Disconnect()
	for model in pairs(trackedModels) do
		disconnectModel(model)
	end
	changedEvent:Destroy()
	root:unmount()
	rootContainer:Destroy()
	portalHost:Destroy()
end)
