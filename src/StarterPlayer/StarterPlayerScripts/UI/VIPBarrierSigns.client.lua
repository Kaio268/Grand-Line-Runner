local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local VIPBarrierSign = require(UiFolder:WaitForChild("Components"):WaitForChild("VIPBarrierSign"))

local FRONT_SURFACE_NAME = "VIPBarrierSignSurfaceFront"
local BACK_SURFACE_NAME = "VIPBarrierSignSurfaceBack"
local LEGACY_SURFACE_NAME = "VIPBarrierSignSurface"
local LEGACY_BILLBOARD_NAME = "VIPBarrierSignBillboard"
local FACE_ATTRIBUTE = "VipSurfaceFace"
local PIXELS_PER_STUD_ATTRIBUTE = "VipSurfacePixelsPerStud"
local SIGN_WIDTH_ATTRIBUTE = "VipSignWidthStuds"
local SIGN_HEIGHT_ATTRIBUTE = "VipSignHeightStuds"
local REMOTES_FOLDER_NAME = "Remotes"
local ACCESS_STATE_EVENT_NAME = "VIPBarrierAccessStateChanged"
local ACCESS_STATE_REQUEST_NAME = "VIPBarrierAccessStateRequest"
local DEFAULT_PIXELS_PER_STUD = 32
local DEFAULT_SIGN_ASPECT_RATIO = 196 / 86
local FACE_PADDING_RATIO_X = 0.9
local FACE_PADDING_RATIO_Y = 0.86
local RESOLVE_RETRY_SECONDS = 2

local SURFACE_FACE_BY_ATTRIBUTE = {
	back = Enum.NormalId.Back,
	front = Enum.NormalId.Front,
	left = Enum.NormalId.Left,
	right = Enum.NormalId.Right,
}

local OPPOSITE_FACE = {
	[Enum.NormalId.Back] = Enum.NormalId.Front,
	[Enum.NormalId.Front] = Enum.NormalId.Back,
	[Enum.NormalId.Left] = Enum.NormalId.Right,
	[Enum.NormalId.Right] = Enum.NormalId.Left,
}

local destroyed = false
local currentBarrierFolder = nil
local showVIPBarrierSigns = false
local rootConnections = {}
local folderConnections = {}
local rootStatesByBarrier = {}

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	table.clear(connections)
end

local function getFallbackVipBarriers()
	local map = Workspace:FindFirstChild("Map")
	local mainMap = map and map:FindFirstChild("Main Map")
	local vipRefuge = mainMap and mainMap:FindFirstChild("Vip Refuge")
	return vipRefuge and vipRefuge:FindFirstChild("VIPBarriers") or nil
end

local function resolveVipBarriers()
	local refs = MapResolver.GetRefs({
		context = "VIPBarrierSigns",
	})

	if refs.VipBarriers then
		return refs.VipBarriers
	end

	return getFallbackVipBarriers()
end

local function getSurfaceFace(barrier)
	local faceAttribute = barrier:GetAttribute(FACE_ATTRIBUTE)
	if typeof(faceAttribute) ~= "string" then
		return Enum.NormalId.Front
	end

	return SURFACE_FACE_BY_ATTRIBUTE[string.lower(faceAttribute)] or Enum.NormalId.Front
end

local function getSurfaceFaces(barrier)
	local frontFace = getSurfaceFace(barrier)
	return frontFace, OPPOSITE_FACE[frontFace] or Enum.NormalId.Back
end

local function getNumberAttribute(barrier, attributeName, defaultValue, minValue, maxValue)
	local value = barrier:GetAttribute(attributeName)
	if typeof(value) ~= "number" then
		return defaultValue
	end

	return math.clamp(value, minValue, maxValue)
end

local function getOptionalNumberAttribute(barrier, attributeName, minValue, maxValue)
	local value = barrier:GetAttribute(attributeName)
	if typeof(value) ~= "number" then
		return nil
	end

	return math.clamp(value, minValue, maxValue)
end

local function getPixelsPerStud(barrier)
	return getNumberAttribute(barrier, PIXELS_PER_STUD_ATTRIBUTE, DEFAULT_PIXELS_PER_STUD, 12, 96)
end

local function getFaceSizeStuds(barrier, face)
	local size = barrier.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return math.max(size.Z, 0.1), math.max(size.Y, 0.1)
	end

	return math.max(size.X, 0.1), math.max(size.Y, 0.1)
end

local function getAutoFitSignSizeStuds(barrier, face)
	local faceWidth, faceHeight = getFaceSizeStuds(barrier, face)
	local availableWidth = math.max(faceWidth * FACE_PADDING_RATIO_X, 0.1)
	local availableHeight = math.max(faceHeight * FACE_PADDING_RATIO_Y, 0.1)
	local widthOverride = getOptionalNumberAttribute(barrier, SIGN_WIDTH_ATTRIBUTE, 0.1, availableWidth)
	local heightOverride = getOptionalNumberAttribute(barrier, SIGN_HEIGHT_ATTRIBUTE, 0.1, availableHeight)

	local widthStuds = widthOverride
	local heightStuds = heightOverride

	if widthStuds and heightStuds then
		return widthStuds, heightStuds
	end

	if widthStuds then
		heightStuds = math.min(widthStuds / DEFAULT_SIGN_ASPECT_RATIO, availableHeight)
		widthStuds = math.min(widthStuds, heightStuds * DEFAULT_SIGN_ASPECT_RATIO, availableWidth)
		return widthStuds, heightStuds
	end

	if heightStuds then
		widthStuds = math.min(heightStuds * DEFAULT_SIGN_ASPECT_RATIO, availableWidth)
		heightStuds = math.min(heightStuds, widthStuds / DEFAULT_SIGN_ASPECT_RATIO, availableHeight)
		return widthStuds, heightStuds
	end

	if availableWidth / availableHeight > DEFAULT_SIGN_ASPECT_RATIO then
		heightStuds = availableHeight
		widthStuds = heightStuds * DEFAULT_SIGN_ASPECT_RATIO
	else
		widthStuds = availableWidth
		heightStuds = widthStuds / DEFAULT_SIGN_ASPECT_RATIO
	end

	return widthStuds, heightStuds
end

local function getSignProps(barrier, face)
	local pixelsPerStud = getPixelsPerStud(barrier)
	local widthStuds, heightStuds = getAutoFitSignSizeStuds(barrier, face)

	return {
		HeightPixels = heightStuds * pixelsPerStud,
		WidthPixels = widthStuds * pixelsPerStud,
	}
end

local function removeLegacySignInstances(barrier)
	for _, child in ipairs(barrier:GetChildren()) do
		if child.Name == LEGACY_BILLBOARD_NAME or child.Name == LEGACY_SURFACE_NAME then
			child:Destroy()
		end
	end
end

local function ensureSurfaceGui(barrier, surfaceName, face)
	local surface = barrier:FindFirstChild(surfaceName)
	local createdSurface = false
	if surface and not surface:IsA("SurfaceGui") then
		surface:Destroy()
		surface = nil
	end

	if not surface then
		surface = Instance.new("SurfaceGui")
		surface.Name = surfaceName
		createdSurface = true
	end

	surface.Adornee = barrier
	surface.AlwaysOnTop = false
	surface.Brightness = 1.25
	surface.Enabled = showVIPBarrierSigns
	surface.Face = face
	surface.LightInfluence = 0.18
	surface.PixelsPerStud = getPixelsPerStud(barrier)
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surface.Parent = barrier

	return surface, createdSurface
end

local function setSurfaceVisibility(state)
	for _, surfaceState in pairs(state.surfaces) do
		if surfaceState.surface then
			surfaceState.surface.Enabled = showVIPBarrierSigns
		end
	end
end

local function updateSurfaceVisibility()
	for _, state in pairs(rootStatesByBarrier) do
		setSurfaceVisibility(state)
	end
end

local function renderSurface(barrier, surfaceState, face)
	surfaceState.surface.Face = face
	surfaceState.surface.PixelsPerStud = getPixelsPerStud(barrier)
	surfaceState.surface.Enabled = showVIPBarrierSigns
	surfaceState.root:render(React.createElement(VIPBarrierSign, getSignProps(barrier, face)))
end

local function renderBarrierSigns(barrier, state)
	local frontFace, backFace = getSurfaceFaces(barrier)
	renderSurface(barrier, state.surfaces.front, frontFace)
	renderSurface(barrier, state.surfaces.back, backFace)
end

local function cleanupBarrier(barrier)
	local state = rootStatesByBarrier[barrier]
	if not state then
		return
	end

	disconnectAll(state.connections)
	for _, surfaceState in pairs(state.surfaces) do
		if surfaceState.root then
			surfaceState.root:unmount()
		end
		if surfaceState.createdSurface and surfaceState.surface then
			surfaceState.surface:Destroy()
		end
	end

	rootStatesByBarrier[barrier] = nil
end

local function cleanupRemovedBarriers()
	for barrier in pairs(rootStatesByBarrier) do
		if not currentBarrierFolder or not barrier:IsDescendantOf(currentBarrierFolder) then
			cleanupBarrier(barrier)
		end
	end
end

local function mountBarrier(barrier)
	if destroyed or not barrier:IsA("BasePart") or rootStatesByBarrier[barrier] then
		return
	end

	removeLegacySignInstances(barrier)

	local frontFace, backFace = getSurfaceFaces(barrier)
	local frontSurface, createdFrontSurface = ensureSurfaceGui(barrier, FRONT_SURFACE_NAME, frontFace)
	local backSurface, createdBackSurface = ensureSurfaceGui(barrier, BACK_SURFACE_NAME, backFace)

	local state = {
		connections = {},
		surfaces = {
			front = {
				createdSurface = createdFrontSurface,
				root = ReactRoblox.createRoot(frontSurface),
				surface = frontSurface,
			},
			back = {
				createdSurface = createdBackSurface,
				root = ReactRoblox.createRoot(backSurface),
				surface = backSurface,
			},
		},
	}
	rootStatesByBarrier[barrier] = state
	renderBarrierSigns(barrier, state)

	for _, attributeName in ipairs({
		FACE_ATTRIBUTE,
		PIXELS_PER_STUD_ATTRIBUTE,
		SIGN_WIDTH_ATTRIBUTE,
		SIGN_HEIGHT_ATTRIBUTE,
	}) do
		table.insert(state.connections, barrier:GetAttributeChangedSignal(attributeName):Connect(function()
			if rootStatesByBarrier[barrier] == state then
				renderBarrierSigns(barrier, state)
			end
		end))
	end

	table.insert(state.connections, barrier:GetPropertyChangedSignal("Size"):Connect(function()
		if rootStatesByBarrier[barrier] == state then
			renderBarrierSigns(barrier, state)
		end
	end))

	table.insert(state.connections, barrier.AncestryChanged:Connect(function()
		if currentBarrierFolder and not barrier:IsDescendantOf(currentBarrierFolder) then
			cleanupBarrier(barrier)
		end
	end))
end

local function scanBarrierFolder(folder)
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			mountBarrier(descendant)
		end
	end
	cleanupRemovedBarriers()
end

local function bindBarrierFolder(folder)
	if currentBarrierFolder == folder then
		if folder then
			scanBarrierFolder(folder)
		end
		return
	end

	disconnectAll(folderConnections)
	currentBarrierFolder = folder
	cleanupRemovedBarriers()

	if not folder then
		return
	end

	table.insert(folderConnections, folder.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			mountBarrier(descendant)
		end
	end))
	table.insert(folderConnections, folder.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			cleanupBarrier(descendant)
		end
	end))

	scanBarrierFolder(folder)
end

local function refreshBarrierFolder()
	if destroyed then
		return
	end

	bindBarrierFolder(resolveVipBarriers())
end

local function applyAccessState(accessState)
	if typeof(accessState) ~= "table" then
		return
	end

	local shouldShow = accessState.ShowVIPBarrierSigns
	if typeof(shouldShow) ~= "boolean" then
		shouldShow = accessState.CanBypassVIPBarrier ~= true
	end

	if showVIPBarrierSigns == shouldShow then
		return
	end

	showVIPBarrierSigns = shouldShow
	updateSurfaceVisibility()
end

local function bindAccessStateRemotes()
	local remotes = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME, 10)
	if not remotes then
		return
	end

	local accessStateEvent = remotes:WaitForChild(ACCESS_STATE_EVENT_NAME, 10)
	if accessStateEvent and accessStateEvent:IsA("RemoteEvent") then
		table.insert(rootConnections, accessStateEvent.OnClientEvent:Connect(applyAccessState))
	end

	local accessStateRequest = remotes:WaitForChild(ACCESS_STATE_REQUEST_NAME, 10)
	if accessStateRequest and accessStateRequest:IsA("RemoteFunction") then
		local ok, accessState = pcall(function()
			return accessStateRequest:InvokeServer()
		end)
		if ok then
			applyAccessState(accessState)
		end
	end
end

table.insert(rootConnections, Workspace:GetAttributeChangedSignal("ActiveMapName"):Connect(refreshBarrierFolder))
table.insert(rootConnections, Workspace.ChildAdded:Connect(function(child)
	if child.Name == "Map" then
		task.defer(refreshBarrierFolder)
	end
end))

task.spawn(bindAccessStateRemotes)

task.spawn(function()
	while not destroyed do
		refreshBarrierFolder()
		task.wait(RESOLVE_RETRY_SECONDS)
	end
end)

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(rootConnections)
	disconnectAll(folderConnections)

	for barrier in pairs(rootStatesByBarrier) do
		cleanupBarrier(barrier)
	end
end)
