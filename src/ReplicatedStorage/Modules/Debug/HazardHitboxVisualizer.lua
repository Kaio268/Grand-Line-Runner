local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local HazardDebugConstants = require(script.Parent:WaitForChild("HazardDebugConstants"))
local DebugHitboxOverlay = require(script.Parent:WaitForChild("DebugHitboxOverlay"))

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
local trackedParts = {}
local activeConnections = {}
local overlayScope = DebugHitboxOverlay.CreateScope({
	FolderName = OVERLAY_FOLDER_NAME,
})

local function disconnectConnection(connection)
	if connection then
		connection:Disconnect()
	end
end

local function isTaggedHazardHitbox(instance)
	return CollectionService:HasTag(instance, HazardDebugConstants.HitboxTag)
		or instance:GetAttribute(HazardDebugConstants.DebugHitboxAttribute) == true
		or instance:GetAttribute(HazardDebugConstants.HazardHitboxAttribute) == true
end

local function isValidHitboxPart(instance)
	return instance and instance:IsA("BasePart") and isTaggedHazardHitbox(instance)
end

local function getCylinderHitboxRadius(part)
	if not part then
		return nil
	end

	local shape = string.lower(tostring(part:GetAttribute("HazardHitboxShape") or ""))
	if shape ~= "cylinder" then
		return nil
	end

	local radius = tonumber(part:GetAttribute("HazardHitboxRadius"))
	if not radius or radius <= 0 then
		return nil
	end

	return radius
end

local function removeOverlay(part)
	local record = trackedParts[part]
	if not record then
		return
	end

	trackedParts[part] = nil
	record:Destroy()
end

local function addOverlay(instance)
	if not enabled or not isValidHitboxPart(instance) then
		return
	end

	local part = instance
	if trackedParts[part] then
		return
	end

	local radius = getCylinderHitboxRadius(part)
	local record
	if radius then
		record = overlayScope:StaticPlanarRadius(part.Position, radius, {
			Name = "DebugHazardHitboxRadius",
			Color = OVERLAY_COLOR,
			Transparency = 0.28,
		})
		if record then
			record:AddConnection(part.AncestryChanged:Connect(function(_, parent)
				if not parent then
					removeOverlay(part)
				end
			end))
		end
	else
		record = overlayScope:AttachBox(part, {
			BoxName = BOX_ADORNMENT_NAME,
			OutlineName = OUTLINE_NAME,
			Color = OVERLAY_COLOR,
			Transparency = OVERLAY_TRANSPARENCY,
			LineThickness = 0.06,
			OnDestroy = function()
				trackedParts[part] = nil
			end,
		})
	end
	if not record then
		return
	end

	trackedParts[part] = record
end

local function clearOverlays()
	local parts = {}
	for part in pairs(trackedParts) do
		parts[#parts + 1] = part
	end

	for _, part in ipairs(parts) do
		removeOverlay(part)
	end

	overlayScope:Clear()
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
