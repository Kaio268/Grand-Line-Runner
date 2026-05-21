local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HazardDebugConstants = require(script.Parent:WaitForChild("HazardDebugConstants"))

local HazardHitboxVisualizer = {}

local LOCAL_PLAYER = Players.LocalPlayer
local TOGGLE_ATTRIBUTE = "ShowAbilityHitboxes"
local OVERLAY_FOLDER_NAME = "ClientHazardHitboxOverlays"
local BOX_ADORNMENT_NAME = "DebugHazardHitboxAdornment"
local OUTLINE_NAME = "DebugHazardHitboxOutline"
local OVERLAY_COLOR = Color3.fromRGB(255, 0, 0)
local OVERLAY_TRANSPARENCY = 0.72

local started = false
local enabled = false
local overlayFolder = nil
local trackedParts = {}
local activeConnections = {}

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function getOverlayParent()
	return Workspace.CurrentCamera or Workspace
end

local function getOverlayFolder()
	local parent = getOverlayParent()
	if not parent then
		return nil
	end

	if overlayFolder and overlayFolder.Parent == parent then
		return overlayFolder
	end

	overlayFolder = parent:FindFirstChild(OVERLAY_FOLDER_NAME)
	if not overlayFolder then
		overlayFolder = Instance.new("Folder")
		overlayFolder.Name = OVERLAY_FOLDER_NAME
		overlayFolder.Parent = parent
	end

	return overlayFolder
end

local function isTaggedHazardHitbox(instance)
	return CollectionService:HasTag(instance, HazardDebugConstants.HitboxTag)
		or instance:GetAttribute(HazardDebugConstants.DebugHitboxAttribute) == true
		or instance:GetAttribute(HazardDebugConstants.HazardHitboxAttribute) == true
end

local function isValidHitboxPart(instance)
	return instance and instance:IsA("BasePart") and isTaggedHazardHitbox(instance)
end

local function updateBoxSize(part)
	local record = trackedParts[part]
	if not record or not record.Box or not record.Box.Parent then
		return
	end

	record.Box.Size = part.Size
end

local function removeOverlay(part)
	local record = trackedParts[part]
	if not record then
		return
	end

	trackedParts[part] = nil
	disconnectConnection(record.SizeConnection)
	disconnectConnection(record.AncestryConnection)
	if record.Box then
		record.Box:Destroy()
	end
	if record.Outline then
		record.Outline:Destroy()
	end
end

local function addOverlay(instance)
	if not enabled or not isValidHitboxPart(instance) then
		return
	end

	local part = instance
	if trackedParts[part] then
		updateBoxSize(part)
		return
	end

	local folder = getOverlayFolder()
	if not folder then
		return
	end

	local box = Instance.new("BoxHandleAdornment")
	box.Name = BOX_ADORNMENT_NAME
	box.Adornee = part
	box.AlwaysOnTop = true
	box.ZIndex = 10
	box.Color3 = OVERLAY_COLOR
	box.Transparency = OVERLAY_TRANSPARENCY
	box.Size = part.Size
	box.Parent = folder

	local outline = Instance.new("SelectionBox")
	outline.Name = OUTLINE_NAME
	outline.Adornee = part
	outline.Color3 = OVERLAY_COLOR
	outline.LineThickness = 0.06
	outline.SurfaceColor3 = OVERLAY_COLOR
	outline.SurfaceTransparency = 1
	outline.Parent = folder

	trackedParts[part] = {
		Box = box,
		Outline = outline,
		SizeConnection = part:GetPropertyChangedSignal("Size"):Connect(function()
			updateBoxSize(part)
		end),
		AncestryConnection = part.AncestryChanged:Connect(function(_, parent)
			if not parent then
				removeOverlay(part)
			end
		end),
	}
end

local function clearOverlays()
	local parts = {}
	for part in pairs(trackedParts) do
		parts[#parts + 1] = part
	end

	for _, part in ipairs(parts) do
		removeOverlay(part)
	end

	if overlayFolder then
		overlayFolder:ClearAllChildren()
	end
end

local function disconnectActiveConnections()
	for _, connection in ipairs(activeConnections) do
		disconnectConnection(connection)
	end
	table.clear(activeConnections)
end

local function scanTaggedHitboxes()
	for _, instance in ipairs(CollectionService:GetTagged(HazardDebugConstants.HitboxTag)) do
		addOverlay(instance)
	end
end

local function enable()
	if enabled then
		return
	end

	enabled = true
	scanTaggedHitboxes()

	activeConnections[#activeConnections + 1] =
		CollectionService:GetInstanceAddedSignal(HazardDebugConstants.HitboxTag):Connect(addOverlay)
	activeConnections[#activeConnections + 1] =
		CollectionService:GetInstanceRemovedSignal(HazardDebugConstants.HitboxTag):Connect(removeOverlay)
	activeConnections[#activeConnections + 1] =
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			if enabled then
				clearOverlays()
				scanTaggedHitboxes()
			end
		end)
end

local function disable()
	if not enabled then
		clearOverlays()
		return
	end

	enabled = false
	disconnectActiveConnections()
	clearOverlays()
end

local function syncEnabledState()
	if LOCAL_PLAYER and LOCAL_PLAYER:GetAttribute(TOGGLE_ATTRIBUTE) == true then
		enable()
	else
		disable()
	end
end

function HazardHitboxVisualizer.Start()
	if started then
		return
	end
	started = true

	if LOCAL_PLAYER then
		LOCAL_PLAYER:GetAttributeChangedSignal(TOGGLE_ATTRIBUTE):Connect(syncEnabledState)
	end

	syncEnabledState()
end

function HazardHitboxVisualizer.Clear()
	disable()
end

return HazardHitboxVisualizer
