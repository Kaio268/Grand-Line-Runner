local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DebugHitboxOverlay = require(Modules:WaitForChild("Debug"):WaitForChild("DebugHitboxOverlay"))

local AbilityHitboxVisualizer = {}

local LOCAL_PLAYER = Players.LocalPlayer
local HITBOX_ATTRIBUTE = "ShowAbilityHitboxes"
local FOLDER_NAME = "ClientAbilityHitboxes"
local DEFAULT_DURATION = 0.75
local DEFAULT_PATH_RADIUS = 1.25
local RING_HEIGHT = 0.2
local GROUND_RAYCAST_UP = 8
local GROUND_RAYCAST_DOWN = 48
local MAX_DURATION = 15
local MAX_RADIUS = 300
local MAX_SEGMENT_LENGTH = 700
local MIN_RADIUS = 0.1
local OVERLAY_COLOR = Color3.fromRGB(255, 0, 0)
local WORLD_LOOKUP_TIMEOUT = 1.5
local WORLD_LOOKUP_INTERVAL = 0.05

local RADIUS_KEYS = {
	"HitboxDebugRadius",
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
local overlayScope = DebugHitboxOverlay.CreateScope({
	FolderName = FOLDER_NAME,
})

local function isEnabled()
	return LOCAL_PLAYER ~= nil and LOCAL_PLAYER:GetAttribute(HITBOX_ATTRIBUTE) == true
end

local function clearVisuals()
	overlayScope:Clear()
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

local function getTargetRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function getTargetRootPosition(targetPlayer)
	local rootPart = getTargetRootPart(targetPlayer)
	return rootPart and rootPart.Position or nil
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

local function getColor(_fruitName, _abilityName)
	return OVERLAY_COLOR
end

local drawPoint

local function drawSphere(position, radius, color, duration)
	if typeof(position) ~= "Vector3" or typeof(radius) ~= "number" or radius <= 0 then
		return false
	end

	return overlayScope:StaticSphere(position, radius, {
		Name = "AbilityHitboxRadius",
		Color = color,
		Transparency = 0.78,
		Duration = duration,
	}) ~= nil
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

	overlayScope:StaticPlanarRadius(centerPosition, radius, {
		Name = "AbilityHitboxPlanarRadius",
		Color = color,
		Transparency = 0.28,
		Duration = duration,
	})

	drawPoint(centerPosition, math.min(radius * 0.025, 3), color, duration)
	return true
end

function drawPoint(position, radius, color, duration)
	if typeof(position) ~= "Vector3" then
		return false
	end

	local markerRadius = math.clamp((tonumber(radius) or DEFAULT_PATH_RADIUS) * 1.35, 0.5, 8)
	return overlayScope:StaticSphere(position, markerRadius, {
		Name = "AbilityHitboxPoint",
		Color = color,
		Transparency = 0.45,
		Duration = duration,
	}) ~= nil
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

	local pathRadius = math.clamp(tonumber(radius) or DEFAULT_PATH_RADIUS, 0.1, 24)
	local width = pathRadius * 2
	overlayScope:StaticPath(startPosition, endPosition, pathRadius, {
		Name = "AbilityHitboxPath",
		Color = color,
		Transparency = 0.72,
		Duration = duration,
	})

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

local function normalizeMode(value)
	if typeof(value) ~= "string" then
		return nil
	end

	local text = value:lower():gsub("[%s_%-]", "")
	if text == "" then
		return nil
	end
	return text
end

local function getDebugMode(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	return normalizeMode(payload.HitboxDebugMode or payload.DebugHitboxMode or payload.HitboxMode)
end

local function getDebugRadii(payload)
	local radii = {}
	if typeof(payload) == "table" and type(payload.HitboxDebugRadii) == "table" then
		for index, entry in ipairs(payload.HitboxDebugRadii) do
			local radius
			local label = "Radius" .. tostring(index)
			if type(entry) == "table" then
				radius = tonumber(entry.Radius or entry.HitboxDebugRadius or entry.Value or entry[1])
				if typeof(entry.Name) == "string" and entry.Name ~= "" then
					label = entry.Name
				end
			else
				radius = tonumber(entry)
			end

			if radius and radius > 0 then
				radii[#radii + 1] = {
					Radius = math.clamp(radius, MIN_RADIUS, MAX_RADIUS),
					Label = label,
				}
			end
		end
	end

	if #radii > 0 then
		return radii
	end

	local radius = getRadius(payload)
	if radius then
		return {
			{
				Radius = radius,
				Label = "Radius",
			},
		}
	end

	return {}
end

local function getPlayerByUserId(value)
	local userId = tonumber(value)
	if not userId then
		return nil
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.UserId == userId then
			return player
		end
	end

	return nil
end

local function getFollowRootPart(targetPlayer, payload, mode)
	if mode == "followownerroot" then
		local owner = getPlayerByUserId(payload and (payload.HitboxDebugOwnerUserId or payload.OwnerUserId))
		if owner then
			return getTargetRootPart(owner)
		end
	end

	return getTargetRootPart(targetPlayer)
end

local function drawFollowRootRadii(targetPlayer, payload, radii, color, duration, mode)
	local rootPart = getFollowRootPart(targetPlayer, payload, mode)
	if not rootPart then
		return false
	end

	local drewVisual = false
	for _, radiusInfo in ipairs(radii) do
		local record = overlayScope:FollowSphere(rootPart, radiusInfo.Radius, {
			Name = "AbilityHitboxFollow" .. tostring(radiusInfo.Label or "Radius"),
			Color = color,
			Transparency = 0.72,
			Duration = duration,
		})
		drewVisual = record ~= nil or drewVisual
	end

	return drewVisual
end

local function getRootFromPath(path)
	if type(path) ~= "table" then
		return Workspace
	end

	local current = nil
	for index, segment in ipairs(path) do
		if typeof(segment) ~= "string" or segment == "" then
			return nil
		end

		if index == 1 then
			local lowered = segment:lower()
			if lowered == "workspace" or lowered == "game.workspace" then
				current = Workspace
			elseif lowered == "replicatedstorage" or lowered == "game.replicatedstorage" then
				current = ReplicatedStorage
			elseif lowered == "players" or lowered == "game.players" then
				current = Players
			else
				current = Workspace:FindFirstChild(segment)
			end
		else
			current = current and current:FindFirstChild(segment) or nil
		end

		if not current then
			return nil
		end
	end

	return current or Workspace
end

local function findPartInInstance(instance, partName)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	if typeof(partName) == "string" and partName ~= "" then
		local namedPart = instance:FindFirstChild(partName, true)
		if namedPart and namedPart:IsA("BasePart") then
			return namedPart
		end
	end

	if instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function findFollowPart(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	local directPart = payload.HitboxDebugFollowPart
	if typeof(directPart) == "Instance" and directPart:IsA("BasePart") then
		return directPart
	end

	local root = getRootFromPath(payload.HitboxDebugSearchPath)
	if not root then
		return nil
	end

	local attributeName = payload.HitboxDebugAttributeName
	local attributeValue = payload.HitboxDebugAttributeValue
	local partName = payload.HitboxDebugPartName or "HumanoidRootPart"
	if typeof(attributeName) ~= "string" or attributeName == "" or attributeValue == nil then
		return findPartInInstance(root, partName)
	end

	for _, child in ipairs(root:GetChildren()) do
		if child:GetAttribute(attributeName) == attributeValue then
			return findPartInInstance(child, partName)
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:GetAttribute(attributeName) == attributeValue then
			return findPartInInstance(descendant, partName)
		end
	end

	return nil
end

local function drawFollowPartRadii(payload, radii, color, duration)
	local function attachToPart()
		local part = findFollowPart(payload)
		if not part then
			return false
		end

		local drewVisual = false
		for _, radiusInfo in ipairs(radii) do
			local record = overlayScope:FollowSphere(part, radiusInfo.Radius, {
				Name = "AbilityHitboxFollow" .. tostring(radiusInfo.Label or "Radius"),
				Color = color,
				Transparency = 0.72,
				Duration = duration,
			})
			drewVisual = record ~= nil or drewVisual
		end
		return drewVisual
	end

	if attachToPart() then
		return true
	end

	task.spawn(function()
		local deadline = os.clock() + math.max(0, tonumber(payload.HitboxDebugLookupTimeout) or WORLD_LOOKUP_TIMEOUT)
		while isEnabled() and os.clock() <= deadline do
			task.wait(WORLD_LOOKUP_INTERVAL)
			if attachToPart() then
				return
			end
		end
	end)

	return true
end

local function drawDynamicRadiusVisual(targetPlayer, payload, color, duration)
	local mode = getDebugMode(payload)
	if not mode then
		return false
	end

	local radii = getDebugRadii(payload)
	if #radii <= 0 then
		return false
	end

	if mode == "followtargetroot" or mode == "followownerroot" or mode == "followroot" then
		return drawFollowRootRadii(targetPlayer, payload, radii, color, duration, mode)
	elseif mode == "followpart" or mode == "followworldpart" or mode == "followmodelroot" then
		return drawFollowPartRadii(payload, radii, color, duration)
	elseif mode == "staticradius" then
		return false
	end

	return false
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
	local drewDynamicVisual = drawDynamicRadiusVisual(targetPlayer, payload, color, duration)
	if drewDynamicVisual then
		return true
	end

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
