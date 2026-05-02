local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local AbilityHitboxVisualizer = {}

local LOCAL_PLAYER = Players.LocalPlayer
local HITBOX_ATTRIBUTE = "ShowAbilityHitboxes"
local FOLDER_NAME = "ClientAbilityHitboxes"
local DEFAULT_DURATION = 0.75
local DEFAULT_PATH_RADIUS = 1.25
local RING_SEGMENT_MIN = 32
local RING_SEGMENT_MAX = 96
local RING_HEIGHT = 0.2
local GROUND_RAYCAST_UP = 8
local GROUND_RAYCAST_DOWN = 48
local MAX_DURATION = 5
local MAX_RADIUS = 300
local MAX_SEGMENT_LENGTH = 700
local MIN_RADIUS = 0.1

local RADIUS_KEYS = {
	"HitboxRadius",
	"Radius",
	"ImpactBurstRadius",
	"BurstRadius",
	"EntryBurstRadius",
	"ResolveBurstRadius",
	"ProjectileRadius",
	"OwnerLaunchRadius",
	"ShieldRadius",
	"HazardProtectionRadius",
	"RewardInteractRadius",
	"HazardProbeRadius",
}

local CENTER_POSITION_KEYS = {
	"HitboxPosition",
	"CenterPosition",
	"EffectPosition",
	"OriginPosition",
	"ImpactPosition",
	"MinePosition",
	"ActualEndPosition",
	"EndPosition",
	"StartPosition",
	"TargetPosition",
}

local START_POSITION_KEYS = {
	"VisualStartPosition",
	"StartPosition",
	"OriginPosition",
	"MinePosition",
	"EffectPosition",
	"CenterPosition",
}

local END_POSITION_KEYS = {
	"ActualEndPosition",
	"EndPosition",
	"ImpactPosition",
	"TargetPosition",
}

local DIRECTION_KEYS = {
	"Direction",
	"LookDirection",
	"LaunchDirection",
	"VisualDirection",
}

local started = false

local function isEnabled()
	return LOCAL_PLAYER ~= nil and LOCAL_PLAYER:GetAttribute(HITBOX_ATTRIBUTE) == true
end

local function getFolder()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder and not folder:IsA("Folder") then
		folder:Destroy()
		folder = nil
	end

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end

	return folder
end

local function clearVisuals()
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if not folder then
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

local function getVector3FromKeys(payload, keys)
	if typeof(payload) ~= "table" then
		return nil
	end

	for _, key in ipairs(keys) do
		local value = payload[key]
		if typeof(value) == "Vector3" then
			return value
		end
	end

	return nil
end

local function getTargetRootPosition(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end

	return nil
end

local function getRadius(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	for _, key in ipairs(RADIUS_KEYS) do
		local radius = tonumber(payload[key])
		if radius and radius > 0 then
			return math.clamp(radius, MIN_RADIUS, MAX_RADIUS)
		end
	end

	return nil
end

local function getPathRadius(payload)
	if typeof(payload) ~= "table" then
		return DEFAULT_PATH_RADIUS
	end

	local radius = tonumber(payload.ProjectileRadius)
		or tonumber(payload.PathRadius)
		or tonumber(payload.LineRadius)
		or tonumber(payload.HitboxRadius)
	if radius and radius > 0 then
		return math.clamp(radius, MIN_RADIUS, 24)
	end

	return DEFAULT_PATH_RADIUS
end

local function getDuration(payload)
	if typeof(payload) ~= "table" then
		return DEFAULT_DURATION
	end

	local duration = tonumber(payload.HitboxVisualDuration)
		or tonumber(payload.HitboxDuration)
		or tonumber(payload.Duration)
		or tonumber(payload.ExplosionDelay)
		or DEFAULT_DURATION

	return math.clamp(duration, 0.15, MAX_DURATION)
end

local function getColor(fruitName, abilityName)
	local fruitText = tostring(fruitName or ""):lower()
	local abilityText = tostring(abilityName or ""):lower()

	if fruitText:find("mera") or abilityText:find("fire") or abilityText:find("flame") then
		return Color3.fromRGB(255, 115, 42)
	elseif fruitText:find("hie") or abilityText:find("freeze") or abilityText:find("ice") then
		return Color3.fromRGB(92, 226, 255)
	elseif fruitText:find("bomu") or abilityText:find("bomb") or abilityText:find("mine") then
		return Color3.fromRGB(255, 215, 74)
	elseif fruitText:find("gomu") or abilityText:find("rubber") then
		return Color3.fromRGB(255, 95, 168)
	elseif fruitText:find("tori") or abilityText:find("phoenix") or abilityText:find("shield") then
		return Color3.fromRGB(88, 180, 255)
	elseif fruitText:find("mogu") or abilityText:find("burrow") then
		return Color3.fromRGB(151, 226, 101)
	end

	return Color3.fromRGB(255, 255, 255)
end

local function configureDebugPart(part, color, transparency)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Locked = true
	part.Material = Enum.Material.ForceField
	part.Transparency = transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function addSelectionOutline(part, color)
	local outline = Instance.new("SelectionBox")
	outline.Adornee = part
	outline.Color3 = color
	outline.LineThickness = 0.04
	outline.SurfaceTransparency = 1
	outline.Parent = part
end

local drawPoint

local function drawSphere(position, radius, color, duration)
	if typeof(position) ~= "Vector3" or typeof(radius) ~= "number" or radius <= 0 then
		return false
	end

	local part = Instance.new("Part")
	part.Name = "AbilityHitboxRadius"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	part.CFrame = CFrame.new(position)
	configureDebugPart(part, color, 0.78)
	addSelectionOutline(part, color)
	part.Parent = getFolder()
	Debris:AddItem(part, duration)

	return true
end

local function resolveGroundedPosition(position)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local filter = {}
	if LOCAL_PLAYER and LOCAL_PLAYER.Character then
		filter[#filter + 1] = LOCAL_PLAYER.Character
	end
	local folder = Workspace:FindFirstChild(FOLDER_NAME)
	if folder then
		filter[#filter + 1] = folder
	end
	params.FilterDescendantsInstances = filter

	local result = Workspace:Raycast(
		position + Vector3.new(0, GROUND_RAYCAST_UP, 0),
		Vector3.new(0, -(GROUND_RAYCAST_UP + GROUND_RAYCAST_DOWN), 0),
		params
	)

	if result then
		return Vector3.new(position.X, result.Position.Y + RING_HEIGHT * 0.5, position.Z)
	end

	return position
end

local function drawPlanarRadius(position, radius, color, duration, payload)
	if typeof(position) ~= "Vector3" or typeof(radius) ~= "number" or radius <= 0 then
		return false
	end

	local centerPosition = position
	if typeof(payload) == "table" and payload.HitboxGrounded == true then
		centerPosition = resolveGroundedPosition(position) or position
	end

	local segmentCount = math.clamp(math.floor(radius * 0.75), RING_SEGMENT_MIN, RING_SEGMENT_MAX)
	local thickness = math.clamp(radius * 0.0125, 0.6, 2.5)
	local folder = getFolder()

	for index = 1, segmentCount do
		local angleA = ((index - 1) / segmentCount) * math.pi * 2
		local angleB = (index / segmentCount) * math.pi * 2
		local pointA = centerPosition + Vector3.new(math.cos(angleA) * radius, 0, math.sin(angleA) * radius)
		local pointB = centerPosition + Vector3.new(math.cos(angleB) * radius, 0, math.sin(angleB) * radius)
		local offset = pointB - pointA
		local length = offset.Magnitude

		if length > 0.01 then
			local part = Instance.new("Part")
			part.Name = "AbilityHitboxPlanarRadius"
			part.Shape = Enum.PartType.Block
			part.Size = Vector3.new(thickness, RING_HEIGHT, length)
			part.CFrame = CFrame.lookAt(pointA + (offset * 0.5), pointB)
			configureDebugPart(part, color, 0.28)
			part.Parent = folder
			Debris:AddItem(part, duration)
		end
	end

	drawPoint(centerPosition, math.min(radius * 0.025, 3), color, duration)
	return true
end

function drawPoint(position, radius, color, duration)
	if typeof(position) ~= "Vector3" then
		return false
	end

	local markerRadius = math.clamp((tonumber(radius) or DEFAULT_PATH_RADIUS) * 1.35, 0.5, 8)
	local part = Instance.new("Part")
	part.Name = "AbilityHitboxPoint"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(markerRadius * 2, markerRadius * 2, markerRadius * 2)
	part.CFrame = CFrame.new(position)
	configureDebugPart(part, color, 0.45)
	part.Parent = getFolder()
	Debris:AddItem(part, duration)

	return true
end

local function drawSegment(startPosition, endPosition, radius, color, duration)
	if typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return false
	end

	local offset = endPosition - startPosition
	local length = offset.Magnitude
	if length <= 0.05 then
		return false
	end

	if length > MAX_SEGMENT_LENGTH then
		endPosition = startPosition + (offset.Unit * MAX_SEGMENT_LENGTH)
		offset = endPosition - startPosition
		length = offset.Magnitude
	end

	local width = math.clamp((tonumber(radius) or DEFAULT_PATH_RADIUS) * 2, 0.2, 48)
	local midpoint = startPosition + (offset * 0.5)

	local part = Instance.new("Part")
	part.Name = "AbilityHitboxPath"
	part.Shape = Enum.PartType.Block
	part.Size = Vector3.new(width, width, length)
	part.CFrame = CFrame.lookAt(midpoint, endPosition)
	configureDebugPart(part, color, 0.72)
	addSelectionOutline(part, color)
	part.Parent = getFolder()
	Debris:AddItem(part, duration)

	drawPoint(startPosition, width * 0.5, color, duration)
	drawPoint(endPosition, width * 0.5, color, duration)

	return true
end

local function getDirection(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	for _, key in ipairs(DIRECTION_KEYS) do
		local value = payload[key]
		if typeof(value) == "Vector3" and value.Magnitude > 0.01 then
			return value.Unit
		end
	end

	return nil
end

local function getDistance(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	local distance = tonumber(payload.Distance) or tonumber(payload.MaxDistance) or tonumber(payload.RequestedDistance)
	if distance and distance > 0 then
		return math.min(distance, MAX_SEGMENT_LENGTH)
	end

	return nil
end

local function drawPathVisual(payload, color, duration)
	local startPosition = getVector3FromKeys(payload, START_POSITION_KEYS)
	if not startPosition then
		return false
	end

	local endPosition = getVector3FromKeys(payload, END_POSITION_KEYS)
	if not endPosition then
		local direction = getDirection(payload)
		local distance = getDistance(payload)
		if direction and distance then
			endPosition = startPosition + (direction * distance)
		end
	end

	if not endPosition then
		return false
	end

	return drawSegment(startPosition, endPosition, getPathRadius(payload), color, duration)
end

local function shouldDrawPlanarRadius(payload)
	if typeof(payload) ~= "table" then
		return false
	end

	local shape = tostring(payload.HitboxShape or payload.Shape or ""):lower()
	return payload.HitboxPlanar == true
		or shape == "planarradius"
		or shape == "planarcircle"
		or shape == "circle"
end

function AbilityHitboxVisualizer.Start()
	if started then
		return
	end
	started = true

	if LOCAL_PLAYER then
		LOCAL_PLAYER:GetAttributeChangedSignal(HITBOX_ATTRIBUTE):Connect(function()
			if not isEnabled() then
				clearVisuals()
			end
		end)
	end
end

function AbilityHitboxVisualizer.Clear()
	clearVisuals()
end

function AbilityHitboxVisualizer.HandleEffect(targetPlayer, fruitName, abilityName, payload)
	AbilityHitboxVisualizer.Start()

	if not isEnabled() or typeof(payload) ~= "table" then
		return false
	end

	local duration = getDuration(payload)
	local color = getColor(fruitName, abilityName)
	local drewVisual = drawPathVisual(payload, color, duration)
	local radius = getRadius(payload)
	local centerPosition = getVector3FromKeys(payload, CENTER_POSITION_KEYS) or getTargetRootPosition(targetPlayer)

	if radius and centerPosition then
		if shouldDrawPlanarRadius(payload) then
			drewVisual = drawPlanarRadius(centerPosition, radius, color, duration, payload) or drewVisual
		else
			drewVisual = drawSphere(centerPosition, radius, color, duration) or drewVisual
		end
	end

	return drewVisual
end

return AbilityHitboxVisualizer
