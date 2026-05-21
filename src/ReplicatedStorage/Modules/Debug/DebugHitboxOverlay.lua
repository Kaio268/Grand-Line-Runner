local Workspace = game:GetService("Workspace")

local DebugHitboxOverlay = {}

local DEFAULT_FOLDER_NAME = "ClientDebugHitboxOverlays"
local DEFAULT_COLOR = Color3.fromRGB(255, 0, 0)
local DEFAULT_TRANSPARENCY = 0.72
local DEFAULT_LINE_THICKNESS = 0.06
local DEFAULT_Z_INDEX = 10
local RING_SEGMENT_MIN = 32
local RING_SEGMENT_MAX = 96
local RING_HEIGHT = 0.2

local Scope = {}
Scope.__index = Scope

local function disconnect(connection)
	if connection then
		connection:Disconnect()
	end
end

local function getColor(options)
	return if typeof(options and options.Color) == "Color3" then options.Color else DEFAULT_COLOR
end

local function getNumber(options, key, fallback)
	local value = tonumber(options and options[key])
	if value == nil then
		return fallback
	end
	return value
end

local function configureProxyPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Locked = true
	part.Transparency = 1
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function configureVisibleDebugPart(part, options)
	configureProxyPart(part)
	part.Color = getColor(options)
	part.Material = Enum.Material.ForceField
	part.Transparency = getNumber(options, "Transparency", DEFAULT_TRANSPARENCY)
end

local function makeRecord(scope, options)
	local record = {
		Scope = scope,
		Instances = {},
		Connections = {},
		OnDestroy = options and options.OnDestroy or nil,
		Destroyed = false,
	}

	function record:AddInstance(instance)
		if instance then
			self.Instances[#self.Instances + 1] = instance
		end
	end

	function record:AddConnection(connection)
		if connection then
			self.Connections[#self.Connections + 1] = connection
		end
	end

	function record:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		self.Scope.Records[self] = nil

		for _, connection in ipairs(self.Connections) do
			disconnect(connection)
		end
		table.clear(self.Connections)

		for _, instance in ipairs(self.Instances) do
			if instance and instance.Parent then
				instance:Destroy()
			end
		end
		table.clear(self.Instances)

		if typeof(self.OnDestroy) == "function" then
			task.defer(self.OnDestroy)
		end
	end

	scope.Records[record] = true
	return record
end

local function scheduleRecordCleanup(record, duration)
	local cleanupDelay = tonumber(duration)
	if not cleanupDelay or cleanupDelay <= 0 then
		return
	end

	task.delay(cleanupDelay, function()
		record:Destroy()
	end)
end

local function addSelectionBox(record, part, options)
	local outline = Instance.new("SelectionBox")
	outline.Name = tostring(options and options.OutlineName or "DebugHitboxOutline")
	outline.Adornee = part
	outline.Color3 = getColor(options)
	outline.LineThickness = getNumber(options, "LineThickness", DEFAULT_LINE_THICKNESS)
	outline.SurfaceColor3 = getColor(options)
	outline.SurfaceTransparency = 1
	outline.Parent = record.Scope:GetFolder()
	record:AddInstance(outline)
	return outline
end

function Scope:GetOverlayParent()
	if self.UseCameraParent ~= false then
		return Workspace.CurrentCamera or Workspace
	end
	return Workspace
end

function Scope:GetFolder()
	local parent = self:GetOverlayParent()
	if not parent then
		return nil
	end

	if self.Folder and self.Folder.Parent == parent then
		return self.Folder
	end

	local folder = parent:FindFirstChild(self.FolderName)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = self.FolderName
		folder.Parent = parent
	end

	self.Folder = folder
	return folder
end

function Scope:Clear()
	local records = {}
	for record in pairs(self.Records) do
		records[#records + 1] = record
	end

	for _, record in ipairs(records) do
		record:Destroy()
	end

	if self.Folder then
		self.Folder:ClearAllChildren()
	end
end

function Scope:Destroy()
	self:Clear()
	disconnect(self.CameraConnection)
	self.CameraConnection = nil
end

function Scope:AttachBox(part, options)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	local folder = self:GetFolder()
	if not folder then
		return nil
	end

	local record = makeRecord(self, options)

	local box = Instance.new("BoxHandleAdornment")
	box.Name = tostring(options and options.BoxName or "DebugHitboxAdornment")
	box.Adornee = part
	box.AlwaysOnTop = not (options and options.AlwaysOnTop == false)
	box.ZIndex = getNumber(options, "ZIndex", DEFAULT_Z_INDEX)
	box.Color3 = getColor(options)
	box.Transparency = getNumber(options, "Transparency", DEFAULT_TRANSPARENCY)
	box.Size = part.Size
	box.Parent = folder
	record:AddInstance(box)

	addSelectionBox(record, part, options)

	record:AddConnection(part:GetPropertyChangedSignal("Size"):Connect(function()
		if box.Parent then
			box.Size = part.Size
		end
	end))
	record:AddConnection(part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			record:Destroy()
		end
	end))

	scheduleRecordCleanup(record, options and options.Duration)
	return record
end

function Scope:StaticSphere(position, radius, options)
	if typeof(position) ~= "Vector3" or typeof(radius) ~= "number" or radius <= 0 then
		return nil
	end

	local folder = self:GetFolder()
	if not folder then
		return nil
	end

	local record = makeRecord(self)
	local anchor = Instance.new("Part")
	anchor.Name = tostring(options and options.Name or "DebugHitboxRadius")
	anchor.Shape = Enum.PartType.Ball
	anchor.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	anchor.CFrame = CFrame.new(position)
	configureVisibleDebugPart(anchor, options)
	anchor.Parent = folder
	record:AddInstance(anchor)

	addSelectionBox(record, anchor, options)
	scheduleRecordCleanup(record, options and options.Duration)
	return record
end

function Scope:FollowSphere(part, radius, options)
	if not part or not part:IsA("BasePart") or typeof(radius) ~= "number" or radius <= 0 then
		return nil
	end

	local folder = self:GetFolder()
	if not folder then
		return nil
	end

	local record = makeRecord(self)

	local sphere = Instance.new("SphereHandleAdornment")
	sphere.Name = tostring(options and options.Name or "DebugHitboxFollowRadius")
	sphere.Adornee = part
	sphere.AlwaysOnTop = not (options and options.AlwaysOnTop == false)
	sphere.ZIndex = getNumber(options, "ZIndex", DEFAULT_Z_INDEX)
	sphere.Color3 = getColor(options)
	sphere.Transparency = getNumber(options, "Transparency", DEFAULT_TRANSPARENCY)
	sphere.Radius = radius
	sphere.CFrame = CFrame.new()
	sphere.Parent = folder
	record:AddInstance(sphere)

	record:AddConnection(part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			record:Destroy()
		end
	end))

	scheduleRecordCleanup(record, options and options.Duration)
	return record
end

function Scope:StaticPath(startPosition, endPosition, radius, options)
	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return nil
	end

	local offset = endPosition - startPosition
	local length = offset.Magnitude
	if length <= 0.05 then
		return nil
	end

	local folder = self:GetFolder()
	if not folder then
		return nil
	end

	local width = math.max(0.2, (tonumber(radius) or 1) * 2)
	local midpoint = startPosition + (offset * 0.5)
	local record = makeRecord(self)

	local pathPart = Instance.new("Part")
	pathPart.Name = tostring(options and options.Name or "DebugHitboxPath")
	pathPart.Size = Vector3.new(width, width, length)
	pathPart.CFrame = CFrame.lookAt(midpoint, endPosition)
	configureVisibleDebugPart(pathPart, options)
	pathPart.Parent = folder
	record:AddInstance(pathPart)

	addSelectionBox(record, pathPart, options)
	scheduleRecordCleanup(record, options and options.Duration)
	return record
end

function Scope:StaticPlanarRadius(position, radius, options)
	if typeof(position) ~= "Vector3" or typeof(radius) ~= "number" or radius <= 0 then
		return nil
	end

	local folder = self:GetFolder()
	if not folder then
		return nil
	end

	local record = makeRecord(self)
	local segmentCount = math.clamp(math.floor(radius * 0.75), RING_SEGMENT_MIN, RING_SEGMENT_MAX)
	local thickness = math.clamp(radius * 0.0125, 0.6, 2.5)
	local color = getColor(options)
	local transparency = getNumber(options, "Transparency", 0.28)

	for index = 1, segmentCount do
		local angleA = ((index - 1) / segmentCount) * math.pi * 2
		local angleB = (index / segmentCount) * math.pi * 2
		local pointA = position + Vector3.new(math.cos(angleA) * radius, 0, math.sin(angleA) * radius)
		local pointB = position + Vector3.new(math.cos(angleB) * radius, 0, math.sin(angleB) * radius)
		local offset = pointB - pointA
		local length = offset.Magnitude

		if length > 0.01 then
			local part = Instance.new("Part")
			part.Name = tostring(options and options.Name or "DebugHitboxPlanarRadius")
			part.Size = Vector3.new(thickness, RING_HEIGHT, length)
			part.CFrame = CFrame.lookAt(pointA + (offset * 0.5), pointB)
			configureVisibleDebugPart(part, {
				Color = color,
				Transparency = transparency,
			})
			part.Parent = folder
			record:AddInstance(part)
		end
	end

	scheduleRecordCleanup(record, options and options.Duration)
	return record
end

function DebugHitboxOverlay.CreateScope(options)
	options = type(options) == "table" and options or {}

	local scope = setmetatable({
		FolderName = tostring(options.FolderName or DEFAULT_FOLDER_NAME),
		UseCameraParent = options.UseCameraParent ~= false,
		Records = {},
		Folder = nil,
		CameraConnection = nil,
	}, Scope)

	scope.CameraConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		scope:GetFolder()
	end)

	return scope
end

return DebugHitboxOverlay
