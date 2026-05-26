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
local ShipVisuals = require(Modules:WaitForChild("Configs"):WaitForChild("ShipVisuals"))
local ShipSailIdentityCard = require(UiFolder:WaitForChild("ShipSail"):WaitForChild("ShipSailIdentityCard"))

local CONFIG = ShipVisuals.SailName or {}
local MODEL_CONFIGS = CONFIG.Models or {}
local SHIP_ATTRIBUTES = ShipVisuals.Attributes or {}
local ATTRIBUTES = {
	Enabled = tostring(CONFIG.EnabledAttribute or "SailIdentityEnabled"),
	OwnerUserId = tostring(CONFIG.OwnerUserIdAttribute or "ShipSailIdentityOwnerUserId"),
	OwnerName = tostring(CONFIG.OwnerNameAttribute or "ShipSailIdentityOwnerName"),
	DisplayText = tostring(CONFIG.DisplayTextAttribute or "ShipSailIdentityDisplayText"),
	ConfigKey = tostring(CONFIG.ConfigKeyAttribute or "ShipSailIdentityConfigKey"),
}

local ANCHOR_NAME = tostring(CONFIG.AnchorName or "ShipSailIdentityAnchor")
local SURFACE_GUI_NAME = tostring(CONFIG.SurfaceGuiName or "ShipSailIdentitySurfaceGui")
local OWNER_DISPLAY_TEXT_ATTRIBUTE = tostring(CONFIG.OwnerDisplayTextAttribute or "OwnerDisplayText")
local ACTIVE_MODEL_NAME_ATTRIBUTE = tostring(SHIP_ATTRIBUTES.ActiveModelName or "ActiveShipModelName")
local SHIP_OWNER_USER_ID_ATTRIBUTE = tostring(SHIP_ATTRIBUTES.OwnerUserId or "OwnerUserId")
local SHIP_OWNER_NAME_ATTRIBUTE = tostring(SHIP_ATTRIBUTES.OwnerName or "OwnerName")
local DEFAULT_CANVAS_SIZE = if typeof(CONFIG.CanvasSize) == "Vector2" then CONFIG.CanvasSize else Vector2.new(512, 192)
local DEFAULT_PIXELS_PER_STUD = math.max(1, tonumber(CONFIG.PixelsPerStud) or 50)
local DEFAULT_MAX_DISTANCE = math.max(1, tonumber(CONFIG.MaxDistance) or 250)
local DEFAULT_LIGHT_INFLUENCE = math.clamp(tonumber(CONFIG.LightInfluence) or 0.15, 0, 1)
local DEBUG = false
local DEBUG_PREFIX = "[SHIP_SAIL_IDENTITY]"

local anchorStates = {}
local shipConnections = {}
local activeShipsConnections = {}
local activeShipsFolder = nil
local destroyed = false

local function diag(message, ...)
	if not DEBUG then
		return
	end

	print(DEBUG_PREFIX .. " " .. string.format(message, ...))
end

local function track(connection, bucket)
	if connection then
		bucket[#bucket + 1] = connection
	end
	return connection
end

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(bucket)
end

local function trim(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmed = string.match(value, "^%s*(.-)%s*$")
	if not trimmed or trimmed == "" then
		return nil
	end

	return trimmed
end

local function getModelConfig(anchor, ship)
	local modelKey = trim(anchor:GetAttribute(ATTRIBUTES.ConfigKey))
		or (ship and trim(ship:GetAttribute(ATTRIBUTES.ConfigKey)))
		or (ship and trim(ship:GetAttribute(ACTIVE_MODEL_NAME_ATTRIBUTE)))
	return modelKey and MODEL_CONFIGS[modelKey] or nil
end

local function getConfigValue(modelConfig, key, fallback)
	if type(modelConfig) == "table" and modelConfig[key] ~= nil then
		return modelConfig[key]
	end

	if CONFIG[key] ~= nil then
		return CONFIG[key]
	end

	return fallback
end

local function getCanvasSize(modelConfig)
	local value = getConfigValue(modelConfig, "CanvasSize", DEFAULT_CANVAS_SIZE)
	if typeof(value) == "Vector2" then
		return value
	end

	return DEFAULT_CANVAS_SIZE
end

local function getPixelsPerStud(modelConfig)
	return math.max(1, tonumber(getConfigValue(modelConfig, "PixelsPerStud", DEFAULT_PIXELS_PER_STUD)) or DEFAULT_PIXELS_PER_STUD)
end

local function getSurfaceFace(modelConfig)
	local value = getConfigValue(modelConfig, "SurfaceFace", CONFIG.SurfaceFace or Enum.NormalId.Back)
	if typeof(value) == "EnumItem" and value.EnumType == Enum.NormalId then
		return value
	end

	return Enum.NormalId.Back
end

local function getOwnerUserId(anchor, ship)
	return anchor:GetAttribute(ATTRIBUTES.OwnerUserId)
		or (ship and ship:GetAttribute(ATTRIBUTES.OwnerUserId))
		or (ship and ship:GetAttribute(SHIP_OWNER_USER_ID_ATTRIBUTE))
end

local function getOwnerName(anchor, ship)
	return trim(anchor:GetAttribute(ATTRIBUTES.OwnerName))
		or (ship and trim(ship:GetAttribute(ATTRIBUTES.OwnerName)))
		or (ship and trim(ship:GetAttribute(SHIP_OWNER_NAME_ATTRIBUTE)))
end

local function getDisplayText(anchor, ship)
	local displayText = trim(anchor:GetAttribute(ATTRIBUTES.DisplayText))
		or (ship and trim(ship:GetAttribute(ATTRIBUTES.DisplayText)))
		or (ship and trim(ship:GetAttribute(OWNER_DISPLAY_TEXT_ATTRIBUTE)))
	if displayText then
		return displayText
	end

	local ownerName = getOwnerName(anchor, ship) or "Player"
	if string.sub(ownerName, -2) == "'s" or string.sub(ownerName, -2) == "'S" then
		return ownerName
	end

	return ownerName .. "'s"
end

local function isIdentityEnabled(anchor, ship)
	return anchor:GetAttribute(ATTRIBUTES.Enabled) == true
		or (ship and ship:GetAttribute(ATTRIBUTES.Enabled) == true)
end

local function ensureSurfaceGui(anchor, modelConfig)
	local selectedGui = nil

	for _, child in ipairs(anchor:GetChildren()) do
		if child.Name == SURFACE_GUI_NAME then
			if not selectedGui and child:IsA("SurfaceGui") then
				selectedGui = child
			else
				child:Destroy()
			end
		end
	end

	if not selectedGui then
		selectedGui = Instance.new("SurfaceGui")
		selectedGui.Name = SURFACE_GUI_NAME
		selectedGui.Parent = anchor
	end

	selectedGui.Adornee = anchor
	selectedGui.AlwaysOnTop = false
	selectedGui.CanvasSize = getCanvasSize(modelConfig)
	selectedGui.ClipsDescendants = true
	selectedGui.Enabled = true
	selectedGui.Face = getSurfaceFace(modelConfig)
	selectedGui.LightInfluence = DEFAULT_LIGHT_INFLUENCE
	selectedGui.MaxDistance = DEFAULT_MAX_DISTANCE
	selectedGui.PixelsPerStud = getPixelsPerStud(modelConfig)
	selectedGui.ResetOnSpawn = false
	selectedGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	selectedGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	return selectedGui
end

local function unwatchAnchor(anchor)
	local state = anchorStates[anchor]
	if not state then
		return
	end

	disconnectAll(state.Connections)
	if state.Root then
		state.Root:unmount()
	end
	if state.SurfaceGui then
		state.SurfaceGui:Destroy()
	end
	if state.RootContainer then
		state.RootContainer:Destroy()
	end
	anchorStates[anchor] = nil
end

local function renderAnchor(anchor)
	local state = anchorStates[anchor]
	if not state or not anchor.Parent then
		return
	end

	local ship = state.Ship
	if not isIdentityEnabled(anchor, ship) then
		if state.SurfaceGui then
			state.SurfaceGui.Enabled = false
		end
		return
	end

	local modelConfig = getModelConfig(anchor, ship)
	local surfaceGui = ensureSurfaceGui(anchor, modelConfig)
	state.SurfaceGui = surfaceGui
	state.Root:render(ReactRoblox.createPortal(React.createElement(ShipSailIdentityCard, {
		displayText = getDisplayText(anchor, ship),
		ownerUserId = getOwnerUserId(anchor, ship),
	}), surfaceGui))
	diag("render ship=%s anchor=%s text=%s", ship and ship.Name or "<nil>", anchor.Name, getDisplayText(anchor, ship))
end

local function scheduleRender(anchor)
	local state = anchorStates[anchor]
	if not state or state.RenderQueued or destroyed then
		return
	end

	state.RenderQueued = true
	task.defer(function()
		state.RenderQueued = false
		renderAnchor(anchor)
	end)
end

local function watchAnchor(anchor, ship)
	if not anchor:IsA("BasePart") or anchor.Name ~= ANCHOR_NAME then
		return
	end

	if anchorStates[anchor] then
		anchorStates[anchor].Ship = ship
		scheduleRender(anchor)
		return
	end

	local rootContainer = Instance.new("Folder")
	rootContainer.Name = "ReactShipSailIdentityRoot"
	rootContainer.Parent = playerGui

	local state = {
		Connections = {},
		RenderQueued = false,
		Root = ReactRoblox.createRoot(rootContainer),
		RootContainer = rootContainer,
		Ship = ship,
		SurfaceGui = nil,
	}
	anchorStates[anchor] = state

	for _, attributeName in pairs(ATTRIBUTES) do
		track(anchor:GetAttributeChangedSignal(attributeName):Connect(function()
			scheduleRender(anchor)
		end), state.Connections)
	end

	track(anchor.AncestryChanged:Connect(function(_, parent)
		if not parent then
			unwatchAnchor(anchor)
		end
	end), state.Connections)

	scheduleRender(anchor)
	diag("mount ship=%s anchor=%s", ship and ship.Name or "<nil>", anchor.Name)
end

local function scanShip(ship)
	for _, descendant in ipairs(ship:GetDescendants()) do
		if descendant.Name == ANCHOR_NAME and descendant:IsA("BasePart") then
			watchAnchor(descendant, ship)
		end
	end
end

local function scheduleShipAnchors(ship)
	for anchor, state in pairs(anchorStates) do
		if state.Ship == ship then
			scheduleRender(anchor)
		end
	end
end

local function watchShip(ship)
	if not ship:IsA("Model") or shipConnections[ship] then
		return
	end

	local connections = {}
	shipConnections[ship] = connections

	track(ship.DescendantAdded:Connect(function(descendant)
		if descendant.Name == ANCHOR_NAME and descendant:IsA("BasePart") then
			watchAnchor(descendant, ship)
		end
	end), connections)

	for _, attributeName in ipairs({
		ATTRIBUTES.Enabled,
		ATTRIBUTES.OwnerUserId,
		ATTRIBUTES.OwnerName,
		ATTRIBUTES.DisplayText,
		ATTRIBUTES.ConfigKey,
		OWNER_DISPLAY_TEXT_ATTRIBUTE,
		ACTIVE_MODEL_NAME_ATTRIBUTE,
		SHIP_OWNER_USER_ID_ATTRIBUTE,
		SHIP_OWNER_NAME_ATTRIBUTE,
	}) do
		track(ship:GetAttributeChangedSignal(attributeName):Connect(function()
			scheduleShipAnchors(ship)
		end), connections)
	end

	track(ship.AncestryChanged:Connect(function(_, parent)
		if not parent then
			disconnectAll(connections)
			shipConnections[ship] = nil
		end
	end), connections)

	scanShip(ship)
	diag("watch_ship ship=%s", ship.Name)
end

local function unwatchShip(ship)
	local connections = shipConnections[ship]
	if connections then
		disconnectAll(connections)
		shipConnections[ship] = nil
	end

	local anchors = {}
	for anchor in pairs(anchorStates) do
		if anchor:IsDescendantOf(ship) then
			anchors[#anchors + 1] = anchor
		end
	end

	for _, anchor in ipairs(anchors) do
		unwatchAnchor(anchor)
	end
	diag("cleanup_ship ship=%s", ship.Name)
end

local function resolveWorkspacePath(pathSegments)
	local current = Workspace
	for _, segment in ipairs(pathSegments or {}) do
		current = current and current:WaitForChild(segment, 30)
		if not current then
			return nil
		end
	end

	return current
end

task.spawn(function()
	local shipSystem = resolveWorkspacePath(ShipVisuals.ShipSystemPath)
	activeShipsFolder = shipSystem and shipSystem:WaitForChild(ShipVisuals.ActiveShipsName, 30)
	if not activeShipsFolder then
		warn("[ShipSailIdentityClient] Missing ActiveShips folder; sail identity UI will stay hidden.")
		return
	end

	for _, child in ipairs(activeShipsFolder:GetChildren()) do
		watchShip(child)
	end

	track(activeShipsFolder.ChildAdded:Connect(watchShip), activeShipsConnections)
	track(activeShipsFolder.ChildRemoved:Connect(unwatchShip), activeShipsConnections)
end)

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(activeShipsConnections)

	for ship in pairs(shipConnections) do
		unwatchShip(ship)
	end

	local anchors = {}
	for anchor in pairs(anchorStates) do
		anchors[#anchors + 1] = anchor
	end

	for _, anchor in ipairs(anchors) do
		unwatchAnchor(anchor)
	end
end)
