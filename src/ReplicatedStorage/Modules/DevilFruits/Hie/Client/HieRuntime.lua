local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local HieFolder = DevilFruits:WaitForChild("Hie")
local HieShared = HieFolder:WaitForChild("Shared")
local HieConfig = require(HieShared:WaitForChild("HieConfig"))
local HieVfx = require(HieShared:WaitForChild("Vfx"))

local HieClient = {}
HieClient.__index = HieClient

HieClient.FRUIT_NAME = "Hie Hie no Mi"
HieClient.FREEZE_SHOT_ABILITY = "FreezeShot"
HieClient.ICE_BOOST_ABILITY = "IceBoost"

local DEBUG_AIM = RunService:IsStudio()
local DEBUG_VFX = RunService:IsStudio()
local DEBUG_VFX_VERBOSE = false
local FREEZE_SHOT_HAND_FORWARD_OFFSET = 2.5
local FREEZE_SHOT_MUZZLE_CACHE_TTL = 1
local FREEZE_SHOT_LOCAL_CAST_LOCK_MIN_DURATION = 1
local LOG_INFO_COOLDOWN = 0.2
local LOG_WARN_COOLDOWN = 3
local BURST_CONFIG = {
	BurstCount = 5,
	BurstInterval = 0,
	OptionalVisualSpread = 0,
	SpawnOffsetRadius = 0,
	VerticalOffsetRange = {
		Min = 0,
		Max = 0,
	},
	InitialSpreadAngle = 12,
	HomingStrength = 0,
	HomingDelay = 0,
	MaxTurnRate = 0,
	OrientationCorrectionCFrame = CFrame.Angles(math.rad(-90), 0, 0),
	Mode = "visual_only",
}
local DEFAULT_AIM_RAY_DISTANCE = 700
local AIM_PLANE_HEIGHT_OFFSET = 1.2
local MAX_AIM_FILTER_PASSES = 12
local AIM_HELPER_NAMES = {
	HitBox = true,
	ExtractionZone = true,
	RunHub = true,
	DecreaseSpeed = true,
}

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatOrientationCorrection(value)
	if typeof(value) ~= "CFrame" then
		return tostring(value)
	end

	local x, y, z = value:ToEulerAnglesXYZ()
	return string.format(
		"X=%.1f Y=%.1f Z=%.1f",
		math.deg(x),
		math.deg(y),
		math.deg(z)
	)
end

local function describeFreezeShotPayload(payload)
	payload = payload or {}

	return string.format(
		"phase=%s projectileId=%s shotgun=%s/%s group=%s start=%s impact=%s speed=%s baseSpeed=%s velocity=%s inherited=%s radius=%s maxDistance=%s startedAt=%s resolvedAt=%s hitKind=%s hitLabel=%s resolveReason=%s",
		tostring(payload.Phase),
		tostring(payload.ProjectileId),
		tostring(payload.ShotgunIndex),
		tostring(payload.ShotgunCount),
		tostring(payload.ShotgunGroupId),
		formatVector3(payload.StartPosition),
		formatVector3(payload.ImpactPosition),
		tostring(payload.ProjectileSpeed),
		tostring(payload.BaseProjectileSpeed),
		formatVector3(payload.ProjectileVelocity),
		formatVector3(payload.InheritedVelocity),
		tostring(payload.ProjectileRadius),
		tostring(payload.MaxDistance or payload.Range),
		tostring(payload.StartedAt),
		tostring(payload.ResolvedAt),
		tostring(payload.HitKind),
		tostring(payload.HitLabel),
		tostring(payload.ResolveReason)
	)
end

local function logVfx(tag, message, ...)
	if not DEBUG_VFX then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit(
		"HieClient:VFX",
		tostring(tag or "") .. "::" .. DiagnosticLogLimiter.BuildKey(message, ...),
		LOG_INFO_COOLDOWN
	) then
		return
	end

	local prefix = "[HIE][VFX]"
	if typeof(tag) == "string" and tag ~= "" then
		prefix ..= string.format("[%s]", tag)
	end

	print(string.format(prefix .. " " .. message, ...))
end

local function logVfxVerbose(message, ...)
	if not (DEBUG_VFX and DEBUG_VFX_VERBOSE) then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("HieClient:VFX_VERBOSE", DiagnosticLogLimiter.BuildKey(message, ...), 1) then
		return
	end

	print(string.format("[HIE][VFX][STEP] " .. message, ...))
end

local function logVfxError(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("HieClient:VFX_ERROR", DiagnosticLogLimiter.BuildKey(message, ...), LOG_WARN_COOLDOWN) then
		return
	end

	warn(string.format("[HIE][VFX][ERROR] " .. message, ...))
end

local function logBurst(message, ...)
	if not DEBUG_VFX then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("HieClient:BURST", DiagnosticLogLimiter.BuildKey(message, ...), LOG_INFO_COOLDOWN) then
		return
	end

	print(string.format("[HIE BURST] " .. message, ...))
end

local function warnBurst(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("HieClient:BURST_WARN", DiagnosticLogLimiter.BuildKey(message, ...), LOG_WARN_COOLDOWN) then
		return
	end

	warn(string.format("[HIE BURST][WARN] " .. message, ...))
end

local function logAim(tag, message, ...)
	if not DEBUG_AIM then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit(
		"HieClient:AIM",
		tostring(tag or "") .. "::" .. DiagnosticLogLimiter.BuildKey(message, ...),
		LOG_INFO_COOLDOWN
	) then
		return
	end

	local prefix = "[HIE][AIM][CLIENT]"
	if typeof(tag) == "string" and tag ~= "" then
		prefix = string.format("[HIE][AIM][%s]", tag)
	end

	print(string.format(prefix .. " " .. message, ...))
end

local function hasTruthyInstanceAttribute(instance, attributeName)
	if typeof(instance) ~= "Instance" then
		return false
	end

	local value = instance:GetAttribute(attributeName)
	if value == true then
		return true
	end

	if typeof(value) == "number" then
		return value ~= 0
	end

	if typeof(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "true" or lowered == "1" or lowered == "yes"
	end

	return false
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getPlayerHumanoid(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getFreezeShotGripPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("RightLowerArm")
		or character:FindFirstChild("Right Arm")
end

local function getFreezeShotToolHandle(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local handle = child:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				return handle
			end
		end
	end

	return nil
end

local function getFreezeShotLaunchOriginPosition(targetPlayer)
	local toolHandle = getFreezeShotToolHandle(targetPlayer)
	if toolHandle then
		local attachment = toolHandle:FindFirstChild("ToolGripAttachment")
			or toolHandle:FindFirstChild("GripAttachment")
		if attachment and attachment:IsA("Attachment") then
			return attachment.WorldPosition, attachment.Name
		end

		return toolHandle.Position, toolHandle.Name
	end

	local gripPart = getFreezeShotGripPart(targetPlayer)
	if gripPart and gripPart:IsA("BasePart") then
		local attachment = gripPart:FindFirstChild("RightGripAttachment")
			or gripPart:FindFirstChild("RightGrip")
		if attachment and attachment:IsA("Attachment") then
			return attachment.WorldPosition, "RightGripAttachment"
		end

		return gripPart.Position, gripPart.Name
	end

	local rootPart = getPlayerRootPart(targetPlayer)
	if rootPart then
		return rootPart.Position + Vector3.new(0, AIM_PLANE_HEIGHT_OFFSET, 0), "RootFallback"
	end

	return nil, nil
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getPlayerFromDescendant(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local targetPlayer = Players:GetPlayerFromCharacter(current)
			if targetPlayer then
				return targetPlayer
			end
		end

		current = current.Parent
	end

	return nil
end

local function getCursorAimRay()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil, nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	return camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y), mouseLocation
end

local function projectPointToHorizontalPlane(point, planeY)
	if typeof(point) ~= "Vector3" then
		return nil
	end

	return Vector3.new(point.X, planeY, point.Z)
end

local function getHorizontalRayPlaneIntersection(rayOrigin, rayDirection, planeY, maxDistance)
	if typeof(rayOrigin) ~= "Vector3" or typeof(rayDirection) ~= "Vector3" then
		return nil
	end

	if math.abs(rayDirection.Y) <= 0.0001 then
		return nil
	end

	local distance = (planeY - rayOrigin.Y) / rayDirection.Y
	if distance <= 0 then
		return nil
	end

	local maxAllowedDistance = math.max(1, tonumber(maxDistance) or DEFAULT_AIM_RAY_DISTANCE)
	if distance > maxAllowedDistance then
		return nil
	end

	return rayOrigin + (rayDirection * distance)
end

local function isCharacterDescendant(instance)
	return getPlayerFromDescendant(instance) ~= nil
end

local function isVerticalAimEnabled(abilityConfig)
	return abilityConfig ~= nil and abilityConfig.AllowVerticalAim == true
end

local function getProjectileDirection(direction, rootPart)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.01 then
		if not rootPart then
			return Vector3.new(0, 0, -1)
		end

		direction = rootPart.CFrame.LookVector
	end

	if direction.Magnitude > 0.01 then
		return direction.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getFreezeShotVelocity(payload, direction, speed)
	if typeof(payload.ProjectileVelocity) == "Vector3" and payload.ProjectileVelocity.Magnitude > 0.01 then
		return payload.ProjectileVelocity
	end

	return direction * math.max(1, speed)
end

local function setFreezeShotVisualTransform(part, position, velocity, fallbackDirection)
	if not part then
		return
	end

	local facing = typeof(velocity) == "Vector3" and velocity.Magnitude > 0.01 and velocity.Unit or fallbackDirection
	if typeof(facing) ~= "Vector3" or facing.Magnitude <= 0.01 then
		facing = Vector3.new(0, 0, -1)
	end

	part.CFrame = CFrame.lookAt(position, position + facing)
end

local function hashBurstSeed(text)
	local hash = 5381
	for index = 1, #text do
		hash = ((hash * 33) + string.byte(text, index)) % 2147483647
	end

	return hash
end

local function getBurstRandom(projectileId, burstIndex)
	return Random.new(hashBurstSeed(string.format("%s:%d", tostring(projectileId), tonumber(burstIndex) or 0)))
end

local function getBurstBasis(direction)
	local forward = getProjectileDirection(direction, nil)
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude <= 0.01 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end

	local up = right:Cross(forward)
	if up.Magnitude <= 0.01 then
		up = Vector3.yAxis
	else
		up = up.Unit
	end

	return forward, right, up
end

local function rotateDirectionAroundAxis(direction, axis, angleRadians)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.01 then
		return Vector3.new(0, 0, -1)
	end

	if typeof(axis) ~= "Vector3" or axis.Magnitude <= 0.01 or math.abs(angleRadians) <= 0.0001 then
		return direction.Unit
	end

	return CFrame.fromAxisAngle(axis.Unit, angleRadians):VectorToWorldSpace(direction.Unit).Unit
end

local function turnDirectionTowards(currentDirection, desiredDirection, maxTurnRadians)
	local currentUnit = getProjectileDirection(currentDirection, nil)
	local desiredUnit = getProjectileDirection(desiredDirection, nil)
	local dot = math.clamp(currentUnit:Dot(desiredUnit), -1, 1)
	local angleBetween = math.acos(dot)

	if angleBetween <= 0.0001 then
		return desiredUnit, false, angleBetween
	end

	if angleBetween <= math.max(0.0001, maxTurnRadians) then
		return desiredUnit, false, angleBetween
	end

	local turnAxis = currentUnit:Cross(desiredUnit)
	if turnAxis.Magnitude <= 0.0001 then
		return currentUnit, true, angleBetween
	end

	local turnedDirection = CFrame.fromAxisAngle(turnAxis.Unit, math.max(0.0001, maxTurnRadians)):VectorToWorldSpace(currentUnit)
	return turnedDirection.Unit, true, angleBetween
end

local function getFreezeShotTravelSnapshot(startPosition, velocity, maxDistance, startedAt, queryTime, resolutionPayload)
	local speed = typeof(velocity) == "Vector3" and velocity.Magnitude or 0
	local elapsed = math.max(0, queryTime - startedAt)
	local maxTravelTime = speed > 0.01 and (maxDistance / speed) or 0
	local effectiveTravelTime = math.min(elapsed, maxTravelTime)
	local distance = math.min(speed * effectiveTravelTime, maxDistance)
	local position = startPosition + (velocity * effectiveTravelTime)
	local clamped = effectiveTravelTime < elapsed
	local clampReason = clamped and "max_distance" or "none"

	if type(resolutionPayload) == "table" then
		local resolvedAt = tonumber(resolutionPayload.ResolvedAt)
		local impactPosition = typeof(resolutionPayload.ImpactPosition) == "Vector3" and resolutionPayload.ImpactPosition or nil
		if resolvedAt and impactPosition and queryTime >= resolvedAt then
			position = impactPosition
			distance = math.min((impactPosition - startPosition).Magnitude, maxDistance)
			clamped = true
			clampReason = "resolved"
		end
	end

	return {
		Position = position,
		Elapsed = elapsed,
		Distance = distance,
		Speed = speed,
		Clamped = clamped,
		ClampReason = clampReason,
		EffectiveTravelTime = effectiveTravelTime,
	}
end

local function createIceImpactEffect(position)
	local burst = Instance.new("Part")
	burst.Name = "HieFreezeImpact"
	burst.Shape = Enum.PartType.Ball
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Material = Enum.Material.Neon
	burst.Color = Color3.fromRGB(175, 240, 255)
	burst.Transparency = 0.15
	burst.Size = Vector3.new(1.6, 1.6, 1.6)
	burst.CFrame = CFrame.new(position)
	burst.Parent = Workspace

	local tween = TweenService:Create(burst, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(5.5, 5.5, 5.5),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if burst.Parent then
			burst:Destroy()
		end
	end)
end

local function createFallbackIceBoostEffect(targetPlayer)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	local ring = Instance.new("Part")
	ring.Name = "HieIceBoostRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(152, 232, 255)
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.2, 5, 5)
	ring.CFrame = CFrame.new(rootPart.Position - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace

	local tween = TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.2, 8, 8),
	})

	tween:Play()
	tween.Completed:Connect(function()
		if ring.Parent then
			ring:Destroy()
		end
	end)
end

function HieClient.new(config)
	config = config or {}

	local self = setmetatable({}, HieClient)
	self.player = config.player or Players.LocalPlayer
	self.activeFreezeShots = {}
	self.activeBurstGroups = {}
	self.activeIceBoostEffects = {}
	self.pendingResolutions = {}
	self.freezeShotLaunchGroups = {}
	self.localFreezeShotCastLock = nil
	return self
end

function HieClient:GetRootPart()
	local character = self.player and self.player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

function HieClient:GetFreezeShotBurstSettings()
	local abilityConfig = HieConfig.GetAbilityConfig("FreezeShot") or {}
	local burstCount = math.max(1, math.floor(tonumber(abilityConfig.VisualBurstCount) or tonumber(BURST_CONFIG.BurstCount) or 1))
	local burstInterval = math.max(0, tonumber(abilityConfig.VisualBurstInterval) or tonumber(BURST_CONFIG.BurstInterval) or 0)
	local optionalVisualSpread = math.max(0, tonumber(BURST_CONFIG.OptionalVisualSpread) or 0)
	local spawnOffsetRadius = math.max(0, tonumber(BURST_CONFIG.SpawnOffsetRadius) or 0)
	local verticalOffsetRange = type(BURST_CONFIG.VerticalOffsetRange) == "table" and BURST_CONFIG.VerticalOffsetRange or {}
	local verticalOffsetMin = tonumber(verticalOffsetRange.Min) or -0.1
	local verticalOffsetMax = tonumber(verticalOffsetRange.Max) or 0.1
	if verticalOffsetMin > verticalOffsetMax then
		verticalOffsetMin, verticalOffsetMax = verticalOffsetMax, verticalOffsetMin
	end
	local initialSpreadAngle = math.max(
		0,
		tonumber(abilityConfig.VisualShotgunSpreadAngle) or tonumber(BURST_CONFIG.InitialSpreadAngle) or 0
	)
	local homingStrength = math.max(0, tonumber(BURST_CONFIG.HomingStrength) or 0)
	local homingDelay = math.max(0, tonumber(BURST_CONFIG.HomingDelay) or 0)
	local maxTurnRate = math.max(0, tonumber(BURST_CONFIG.MaxTurnRate) or 0)
	local orientationCorrectionCFrame = typeof(BURST_CONFIG.OrientationCorrectionCFrame) == "CFrame"
		and BURST_CONFIG.OrientationCorrectionCFrame
		or CFrame.new()
	local mode = string.lower(tostring(BURST_CONFIG.Mode or "visual_only"))

	if mode ~= "visual_only" and mode ~= "gameplay_burst" then
		warnBurst("invalid mode=%s; defaulting to visual_only", tostring(BURST_CONFIG.Mode))
		mode = "visual_only"
	end

	if mode == "gameplay_burst" then
		warnBurst("mode=gameplay_burst requested but not implemented; using visual_only")
		mode = "visual_only"
	end

	return {
		BurstCount = burstCount,
		BurstInterval = burstInterval,
		OptionalVisualSpread = optionalVisualSpread,
		SpawnOffsetRadius = spawnOffsetRadius,
		VerticalOffsetMin = verticalOffsetMin,
		VerticalOffsetMax = verticalOffsetMax,
		InitialSpreadAngle = initialSpreadAngle,
		HomingStrength = homingStrength,
		HomingDelay = homingDelay,
		MaxTurnRateRadians = math.rad(maxTurnRate),
		OrientationCorrectionCFrame = orientationCorrectionCFrame,
		Mode = mode,
	}
end

function HieClient:GetAimExclusion(instance)
	if typeof(instance) ~= "Instance" then
		return false, nil, nil
	end

	if instance == Workspace.Terrain then
		return false, nil, nil
	end

	if isCharacterDescendant(instance) then
		return false, nil, nil
	end

	local hazardRoot = HazardUtils.GetHazardInfo(instance)
	if hazardRoot then
		return false, nil, nil
	end

	local current = instance
	while current and current ~= Workspace do
		if hasTruthyInstanceAttribute(current, "IgnoreAim")
			or hasTruthyInstanceAttribute(current, "AimIgnore")
			or hasTruthyInstanceAttribute(current, "IgnoreProjectiles")
			or hasTruthyInstanceAttribute(current, "ProjectileIgnore") then
			return true, current, "ConfiguredIgnore"
		end

		local loweredName = string.lower(current.Name)
		if AIM_HELPER_NAMES[current.Name]
			or loweredName:find("hitbox", 1, true)
			or loweredName:find("trigger", 1, true)
			or loweredName:find("boundary", 1, true)
			or loweredName == "decreasespeed"
			or (current:IsA("BasePart") and current.CanCollide ~= true and loweredName:find("zone", 1, true)) then
			return true, current, current.Name
		end

		current = current.Parent
	end

	if instance:IsA("BasePart") and instance.CanCollide ~= true then
		return true, instance, "NonCollidable"
	end

	return false, nil, nil
end

function HieClient:GetFreezeAimRaycast(maxDistance)
	local unitRay, mouseLocation = getCursorAimRay()
	if not unitRay then
		return nil, nil, nil, nil, mouseLocation
	end

	local rayDistance = math.max(1, tonumber(maxDistance) or DEFAULT_AIM_RAY_DISTANCE)
	local rayVector = unitRay.Direction * rayDistance
	local ignoredInstances = self.player.Character and { self.player.Character } or {}

	for _ = 1, MAX_AIM_FILTER_PASSES do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoredInstances
		params.IgnoreWater = true

		local result = Workspace:Raycast(unitRay.Origin, rayVector, params)
		if not result then
			return nil, nil, unitRay.Origin, unitRay.Direction.Unit, mouseLocation
		end

		local shouldExclude, excludeInstance, excludeReason = self:GetAimExclusion(result.Instance)
		logAim(
			"FILTER",
			"hit=%s excluded=%s reason=%s hitPosition=%s",
			result.Instance:GetFullName(),
			tostring(shouldExclude),
			tostring(excludeReason or "Accepted"),
			formatVector3(result.Position)
		)

		if not shouldExclude then
			return result, result.Position, unitRay.Origin, unitRay.Direction.Unit, mouseLocation
		end

		ignoredInstances[#ignoredInstances + 1] = excludeInstance or result.Instance
	end

	logAim(
		"FILTER",
		"raycast exhausted filterPasses=%d fallback=true rayOrigin=%s rayDirection=%s",
		MAX_AIM_FILTER_PASSES,
		formatVector3(unitRay.Origin),
		formatVector3(unitRay.Direction.Unit)
	)

	return nil, nil, unitRay.Origin, unitRay.Direction.Unit, mouseLocation
end

function HieClient:ResolveVerticalAimPoint(rootPart, candidatePosition, abilityConfig)
	if not rootPart or typeof(candidatePosition) ~= "Vector3" then
		return nil, "InvalidCandidate", nil
	end

	local aimOrigin = rootPart.Position + Vector3.new(0, AIM_PLANE_HEIGHT_OFFSET, 0)
	local offset = candidatePosition - aimOrigin
	local distance = offset.Magnitude
	local minDistance = math.max(0.5, tonumber(abilityConfig and abilityConfig.MinimumAimDistance) or 6)
	if distance < minDistance then
		return nil, "TooClose", nil
	end

	local lookVector = rootPart.CFrame.LookVector
	local forwardDot = lookVector.Magnitude > 0.01 and lookVector.Unit:Dot(offset.Unit) or 1
	local maxDistance = math.max(minDistance, tonumber(abilityConfig and abilityConfig.AimRayDistance) or DEFAULT_AIM_RAY_DISTANCE)
	local clampedDistance = math.clamp(distance, minDistance, maxDistance)
	return aimOrigin + (offset.Unit * clampedDistance), nil, forwardDot
end

function HieClient:ResolvePlanarAimPoint(rootPart, candidatePosition, abilityConfig)
	if not rootPart or typeof(candidatePosition) ~= "Vector3" then
		return nil, "InvalidCandidate", nil
	end

	local aimOrigin = rootPart.Position + Vector3.new(0, AIM_PLANE_HEIGHT_OFFSET, 0)
	local projectedPosition = projectPointToHorizontalPlane(candidatePosition, aimOrigin.Y)
	local planarOffset = projectedPosition - aimOrigin
	local planarMagnitude = planarOffset.Magnitude
	local minDistance = math.max(0.5, tonumber(abilityConfig and abilityConfig.MinimumAimDistance) or 6)
	if planarMagnitude < minDistance then
		return nil, "TooClose", nil
	end

	local forwardPlanar = getPlanarVector(rootPart.CFrame.LookVector)
	if forwardPlanar.Magnitude <= 0.01 then
		forwardPlanar = Vector3.new(0, 0, -1)
	end

	local forwardDot = forwardPlanar.Unit:Dot(planarOffset.Unit)
	local maxDistance = math.max(minDistance, tonumber(abilityConfig and abilityConfig.Range) or 0)
	local clampedDistance = math.clamp(planarMagnitude, minDistance, maxDistance)
	return aimOrigin + (planarOffset.Unit * clampedDistance), nil, forwardDot
end

function HieClient:GetFallbackAimPoint(rootPart, rayOrigin, rayDirection, abilityConfig)
	if not rootPart then
		return nil, "MissingRoot"
	end

	local aimOrigin = rootPart.Position + Vector3.new(0, AIM_PLANE_HEIGHT_OFFSET, 0)
	local aimRayDistance = math.max(1, tonumber(abilityConfig and abilityConfig.AimRayDistance) or DEFAULT_AIM_RAY_DISTANCE)
	if isVerticalAimEnabled(abilityConfig) and typeof(rayDirection) == "Vector3" and rayDirection.Magnitude > 0.01 then
		local forwardDistance = math.max(
			math.max(tonumber(abilityConfig and abilityConfig.MinimumAimDistance) or 6, 18),
			math.min(tonumber(abilityConfig and abilityConfig.Range) or 45, aimRayDistance)
		)
		local fallbackPoint = aimOrigin + (rayDirection.Unit * forwardDistance)
		logAim(
			"FALLBACK",
			"mode=ray3d aimPoint=%s origin=%s direction=%s",
			formatVector3(fallbackPoint),
			formatVector3(aimOrigin),
			formatVector3(rayDirection.Unit)
		)
		return fallbackPoint
	end

	local planePoint = getHorizontalRayPlaneIntersection(rayOrigin, rayDirection, aimOrigin.Y, aimRayDistance)
	if planePoint then
		local resolvedPoint, rejectReason, forwardDot = self:ResolvePlanarAimPoint(rootPart, planePoint, abilityConfig)
		if resolvedPoint then
			logAim(
				"FALLBACK",
				"mode=plane resolved=true aimPoint=%s origin=%s forwardDot=%.2f",
				formatVector3(resolvedPoint),
				formatVector3(aimOrigin),
				forwardDot or 0
			)
			return resolvedPoint
		end

		logAim(
			"FALLBACK",
			"mode=plane resolved=false reason=%s planePoint=%s origin=%s",
			tostring(rejectReason),
			formatVector3(planePoint),
			formatVector3(aimOrigin)
		)
	end

	local forwardPlanar = getPlanarVector(rootPart.CFrame.LookVector)
	if forwardPlanar.Magnitude <= 0.01 then
		forwardPlanar = Vector3.new(0, 0, -1)
	end

	local fallbackDistance = math.max(
		math.max(tonumber(abilityConfig and abilityConfig.MinimumAimDistance) or 6, 18),
		math.min(tonumber(abilityConfig and abilityConfig.Range) or 45, aimRayDistance)
	)
	local fallbackPoint = aimOrigin + (forwardPlanar.Unit * fallbackDistance)
	logAim(
		"FALLBACK",
		"mode=forward aimPoint=%s origin=%s direction=%s",
		formatVector3(fallbackPoint),
		formatVector3(aimOrigin),
		formatVector3(forwardPlanar.Unit)
	)
	return fallbackPoint
end

function HieClient:GetFreezeShotAimPosition(abilityConfig)
	local aimRayDistance = math.max(1, tonumber(abilityConfig and abilityConfig.AimRayDistance) or DEFAULT_AIM_RAY_DISTANCE)
	local rootPart = self:GetRootPart()
	local result, hitPosition, rayOrigin, rayDirection, mouseLocation = self:GetFreezeAimRaycast(aimRayDistance)
	if rootPart and hitPosition then
		local chosenAimPosition, rejectReason, forwardDot
		if isVerticalAimEnabled(abilityConfig) then
			chosenAimPosition, rejectReason, forwardDot = self:ResolveVerticalAimPoint(rootPart, hitPosition, abilityConfig)
		else
			chosenAimPosition, rejectReason, forwardDot = self:ResolvePlanarAimPoint(rootPart, hitPosition, abilityConfig)
		end
		if chosenAimPosition then
			local flattenedY = math.abs(hitPosition.Y - chosenAimPosition.Y) > 0.01
			logAim(
				"CLIENT",
				"captured=true mouse=%s hit=%s chosenAim=%s rayOrigin=%s rayDirection=%s flattenedY=%s forwardDot=%.2f verticalAim=%s",
				tostring(mouseLocation),
				result and result.Instance and result.Instance:GetFullName() or "<none>",
				formatVector3(chosenAimPosition),
				formatVector3(rayOrigin),
				formatVector3(rayDirection),
				tostring(flattenedY),
				forwardDot or 0,
				tostring(isVerticalAimEnabled(abilityConfig))
			)
			return chosenAimPosition
		end

		logAim(
			"FALLBACK",
			"capturedHitRejected=true reason=%s mouse=%s hit=%s hitPosition=%s",
			tostring(rejectReason),
			tostring(mouseLocation),
			result and result.Instance and result.Instance:GetFullName() or "<none>",
			formatVector3(hitPosition)
		)
	end

	if rootPart then
		return self:GetFallbackAimPoint(rootPart, rayOrigin, rayDirection, abilityConfig)
	end

	logAim("FALLBACK", "captured=false reason=no_cursor_ray_and_no_root")
	return nil
end

function HieClient:ClearLocalFreezeShotCastLock(expectedToken)
	local state = self.localFreezeShotCastLock
	if not state or (expectedToken ~= nil and state.Token ~= expectedToken) then
		return
	end

	self.localFreezeShotCastLock = nil
	local humanoid = state.Humanoid
	if humanoid and humanoid.Parent then
		humanoid.WalkSpeed = state.WalkSpeed
		humanoid.AutoRotate = state.AutoRotate
	end
end

function HieClient:ApplyLocalFreezeShotCastLock(abilityConfig, aimPosition)
	local humanoid = getPlayerHumanoid(self.player)
	local rootPart = self:GetRootPart()
	if not humanoid or not rootPart then
		return
	end

	self:ClearLocalFreezeShotCastLock()

	local speedMultiplier = math.clamp(tonumber(abilityConfig and abilityConfig.CastStartupSpeedMultiplier) or 0, 0, 1)
	local maxDuration = math.max(0, tonumber(abilityConfig and abilityConfig.CastStartupSlowMaxDuration) or 0.75)
	local postLaunchLockDuration = math.max(0, tonumber(abilityConfig and abilityConfig.CastPostLaunchLockDuration) or 0.35)
	if speedMultiplier >= 1 or maxDuration <= 0 then
		return
	end

	local token = {}
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)

	if typeof(aimPosition) == "Vector3" then
		local planarAim = Vector3.new(aimPosition.X - rootPart.Position.X, 0, aimPosition.Z - rootPart.Position.Z)
		if planarAim.Magnitude > 0.01 then
			rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + planarAim.Unit, Vector3.yAxis)
		end
	end

	self.localFreezeShotCastLock = {
		Token = token,
		Humanoid = humanoid,
		WalkSpeed = humanoid.WalkSpeed,
		AutoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = humanoid.WalkSpeed * speedMultiplier
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero, false)

	task.delay(math.max(maxDuration + postLaunchLockDuration, FREEZE_SHOT_LOCAL_CAST_LOCK_MIN_DURATION), function()
		self:ClearLocalFreezeShotCastLock(token)
	end)
end

function HieClient:BuildFreezeShotRequestPayload(abilityConfig)
	local aimPosition = self:GetFreezeShotAimPosition(abilityConfig)
	return aimPosition and {
		AimPosition = aimPosition,
	} or nil
end

function HieClient:BeginPredictedFreezeShotRequest()
	local abilityConfig = HieConfig.GetAbilityConfig("FreezeShot") or {}
	local payload = self:BuildFreezeShotRequestPayload(abilityConfig)
	if payload then
		self:ApplyLocalFreezeShotCastLock(abilityConfig, payload.AimPosition)
	end

	return payload
end

function HieClient:CleanupIceBoostEffect(targetPlayer, reason)
	local state = self.activeIceBoostEffects[targetPlayer]
	if not state then
		return
	end

	self.activeIceBoostEffects[targetPlayer] = nil
	HieVfx.CleanupIceBoostEffect(state.VisualState, reason or "cleanup")
end

function HieClient:CreateIceBoostEffect(targetPlayer, payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return
	end

	self:CleanupIceBoostEffect(targetPlayer, "restart")

	local duration = math.max(0.05, tonumber(payload and payload.Duration) or 0.35)
	local visualState = HieVfx.CreateIceBoostEffect({
		TargetPlayer = targetPlayer,
		RootPart = rootPart,
		Duration = duration,
	})

	if not visualState then
		createFallbackIceBoostEffect(targetPlayer)
		return
	end

	self.activeIceBoostEffects[targetPlayer] = {
		VisualState = visualState,
		EndAt = os.clock() + duration,
	}
end

function HieClient:DestroyFreezeShotPart(projectileState)
	if projectileState and projectileState.VisualState then
		HieVfx.CleanupFreezeShotProjectile(projectileState.VisualState, "cleanup")
		projectileState.VisualState = nil
		projectileState.Part = nil
		return
	end

	if projectileState and projectileState.Part and projectileState.Part.Parent then
		projectileState.Part:Destroy()
	end
end

function HieClient:ReleaseBurstGroupIfComplete(authoritativeProjectileId)
	local burstGroup = self.activeBurstGroups[authoritativeProjectileId]
	if not burstGroup then
		return
	end

	if next(burstGroup.CloneIds) ~= nil then
		return
	end

	if self.activeFreezeShots[authoritativeProjectileId] ~= nil then
		return
	end

	self.activeBurstGroups[authoritativeProjectileId] = nil
end

function HieClient:CleanupBurstGroup(authoritativeProjectileId, reason, cleanupClones)
	local burstGroup = self.activeBurstGroups[authoritativeProjectileId]
	if not burstGroup then
		return
	end

	burstGroup.Canceled = true

	if cleanupClones then
		local cloneIds = {}
		for cloneId in pairs(burstGroup.CloneIds) do
			cloneIds[#cloneIds + 1] = cloneId
		end

		for _, cloneId in ipairs(cloneIds) do
			if self.activeFreezeShots[cloneId] then
				self:CleanupFreezeShot(cloneId, reason or "burst_cleanup")
			end
		end
	end

	self:ReleaseBurstGroupIfComplete(authoritativeProjectileId)
end

function HieClient:CleanupFreezeShot(projectileId, reason)
	local projectileState = self.activeFreezeShots[projectileId]
	if not projectileState then
		return
	end

	self.activeFreezeShots[projectileId] = nil
	self:DestroyFreezeShotPart(projectileState)

	local authoritativeProjectileId = projectileState.AuthoritativeProjectileId or projectileId
	if projectileState.IsVisualOnly then
		local burstGroup = self.activeBurstGroups[authoritativeProjectileId]
		if burstGroup then
			burstGroup.CloneIds[projectileId] = nil
		end
		logBurst(
			"cleanup complete for visual shot index=%d projectileId=%s reason=%s",
			tonumber(projectileState.BurstIndex) or 1,
			authoritativeProjectileId,
			tostring(reason or "cleanup")
		)
		self:ReleaseBurstGroupIfComplete(authoritativeProjectileId)
	else
		self:CleanupBurstGroup(authoritativeProjectileId, reason or "cleanup", true)
	end

	logVfx("CLEANUP", "projectileId=%s cleanedUp=true", tostring(projectileId))
end

function HieClient:CreateTemporaryFreezeShotVisual(radius, startPosition, initialVelocity)
	local ok, projectile = pcall(function()
		local freezeShotVisualConfig = HieVfx.GetFreezeShotVisualConfig and HieVfx.GetFreezeShotVisualConfig() or {}
		local projectileScale = math.max(0.1, tonumber(freezeShotVisualConfig.ProjectileScale) or 1)
		local projectileLightRangeScale = math.max(0.1, tonumber(freezeShotVisualConfig.ProjectileLightRangeScale) or 1)
		local projectileTrailWidthScale = math.max(0.1, tonumber(freezeShotVisualConfig.ProjectileTrailWidthScale) or 1)

		local part = Instance.new("Part")
		part.Name = "HieFreezeShotTemp"
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(173, 244, 255)
		part.Transparency = 0.08
		part.Size = Vector3.new(radius * 2 * projectileScale, radius * 2 * projectileScale, radius * 2 * projectileScale)
		setFreezeShotVisualTransform(part, startPosition, initialVelocity, nil)

		local light = Instance.new("PointLight")
		light.Name = "Glow"
		light.Color = Color3.fromRGB(196, 248, 255)
		light.Brightness = 1.8
		light.Range = math.max(6, radius * 8 * projectileLightRangeScale)
		light.Parent = part

		local attachment0 = Instance.new("Attachment")
		attachment0.Name = "TrailStart"
		attachment0.Position = Vector3.new(0, 0, -radius * 0.55 * projectileScale)
		attachment0.Parent = part

		local attachment1 = Instance.new("Attachment")
		attachment1.Name = "TrailEnd"
		attachment1.Position = Vector3.new(0, 0, radius * 0.55 * projectileScale)
		attachment1.Parent = part

		local trail = Instance.new("Trail")
		trail.Name = "Trail"
		trail.Attachment0 = attachment0
		trail.Attachment1 = attachment1
		trail.Color = ColorSequence.new(
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(153, 234, 255)
		)
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.LightEmission = 1
		trail.Lifetime = 0.09
		trail.MinLength = 0.02
		trail.WidthScale = NumberSequence.new(projectileTrailWidthScale)
		trail.Enabled = true
		trail.Parent = part

		part.Parent = Workspace
		return part
	end)

	if not ok then
		logVfxError("temporary projectile creation failed detail=%s", tostring(projectile))
		return nil
	end

	logVfx(
		"PROJECTILE",
		"temporary projectile created success=true radius=%.2f start=%s",
		radius,
		formatVector3(startPosition)
	)

	return projectile
end

function HieClient:CreateFreezeShotProjectileState(options)
	options = options or {}

	local projectileKey = tostring(options.ProjectileKey or "")
	if projectileKey == "" then
		return nil
	end

	local projectileVelocity = typeof(options.ProjectileVelocity) == "Vector3" and options.ProjectileVelocity or Vector3.new(0, 0, -1)
	local direction = typeof(options.Direction) == "Vector3" and options.Direction or getProjectileDirection(projectileVelocity, nil)
	local radius = math.max(0.25, tonumber(options.Radius) or 0.8)
	local startPosition = typeof(options.StartPosition) == "Vector3" and options.StartPosition or Vector3.zero
	local visualStartPosition = typeof(options.VisualStartPosition) == "Vector3" and options.VisualStartPosition or startPosition
	local authoritativeProjectileId = tostring(options.AuthoritativeProjectileId or projectileKey)
	local burstIndex = math.max(1, tonumber(options.BurstIndex) or 1)
	local now = Workspace:GetServerTimeNow()
	local targetPosition = typeof(options.TargetPosition) == "Vector3" and options.TargetPosition or nil
	local orientationCorrectionCFrame = typeof(options.OrientationCorrectionCFrame) == "CFrame"
		and options.OrientationCorrectionCFrame
		or CFrame.new()
	local visualState = HieVfx.CreateFreezeShotProjectile({
		Position = visualStartPosition,
		Velocity = projectileVelocity,
		Direction = direction,
		Radius = radius,
		ProjectileId = authoritativeProjectileId,
	})
	local projectile = visualState and visualState.AnchorPart or self:CreateTemporaryFreezeShotVisual(radius, visualStartPosition, projectileVelocity)
	if not projectile then
		logVfxError(
			"launch failed visualCreation=false projectileId=%s player=%s",
			authoritativeProjectileId,
			tostring(options.TargetPlayerName or "unknown")
		)
		return nil
	end

	if not visualState then
		warnBurst("visual burst fallback used projectileId=%s index=%d", authoritativeProjectileId, burstIndex)
	end

	local projectileState = {
		Id = projectileKey,
		AuthoritativeProjectileId = authoritativeProjectileId,
		IsVisualOnly = options.IsVisualOnly == true,
		BurstIndex = burstIndex,
		BurstMode = tostring(options.BurstMode or "visual_only"),
		Part = projectile,
		VisualState = visualState,
		Direction = direction,
		Velocity = projectileVelocity,
		Speed = math.max(1, projectileVelocity.Magnitude),
		Radius = radius,
		MaxDistance = math.max(1, tonumber(options.MaxDistance) or 1),
		Lifetime = math.max(0.05, tonumber(options.Lifetime) or 0.05),
		StartedAt = tonumber(options.StartedAt) or Workspace:GetServerTimeNow(),
		StartPosition = startPosition,
		ResolvedAt = tonumber(options.ResolvedAt),
		ImpactPosition = typeof(options.ImpactPosition) == "Vector3" and options.ImpactPosition or nil,
		ImpactEffectPlayed = false,
		ShouldCreateImpact = options.ShouldCreateImpact == true,
		CurrentPosition = visualStartPosition,
		CurrentDirection = direction,
		TargetPosition = targetPosition,
		UseCurvedVisualPath = options.UseCurvedVisualPath == true,
		HomingEnabled = options.HomingEnabled == true,
		HomingDelay = math.max(0, tonumber(options.HomingDelay) or 0),
		HomingStrength = math.max(0, tonumber(options.HomingStrength) or 0),
		MaxTurnRateRadians = math.max(0, tonumber(options.MaxTurnRateRadians) or 0),
		LastUpdateAt = now,
		NextHomingLogAt = now,
		LoggedOrientationCorrection = false,
		WarnedMissingShardCore = false,
		VisualSpawnOffset = typeof(options.VisualSpawnOffset) == "Vector3" and options.VisualSpawnOffset or Vector3.zero,
		OrientationCorrectionCFrame = orientationCorrectionCFrame,
		DistanceTraveled = math.max(0, tonumber(options.InitialDistanceTraveled) or 0),
		WarnedCloseTarget = options.WarnedCloseTarget == true,
	}

	self.activeFreezeShots[projectileKey] = projectileState

	local burstGroup = self.activeBurstGroups[authoritativeProjectileId]
	if burstGroup and projectileState.IsVisualOnly then
		burstGroup.CloneIds[projectileKey] = true
	end

	return projectileState
end

function HieClient:PropagateBurstResolution(projectileState)
	if not projectileState or projectileState.IsVisualOnly then
		return
	end

	local authoritativeProjectileId = projectileState.AuthoritativeProjectileId or projectileState.Id
	local burstGroup = self.activeBurstGroups[authoritativeProjectileId]
	if not burstGroup then
		return
	end

	burstGroup.Canceled = true
	burstGroup.ResolvedAt = projectileState.ResolvedAt
	burstGroup.ImpactPosition = projectileState.ImpactPosition

	for cloneId in pairs(burstGroup.CloneIds) do
		local cloneState = self.activeFreezeShots[cloneId]
		if cloneState then
			cloneState.ResolvedAt = projectileState.ResolvedAt
			cloneState.ImpactPosition = projectileState.ImpactPosition
			cloneState.TargetPosition = projectileState.ImpactPosition or cloneState.TargetPosition
			cloneState.ShouldCreateImpact = false
			logBurst(
				"skipped gameplay hit logic for visual-only clone index=%d projectileId=%s",
				tonumber(cloneState.BurstIndex) or 1,
				authoritativeProjectileId
			)
		end
	end
end

local function computeBurstLaneOffset(baseDirection, optionalVisualSpread, burstIndex)
	if optionalVisualSpread <= 0 or burstIndex <= 1 then
		return Vector3.zero
	end

	local _, right = getBurstBasis(baseDirection)
	local patternIndex = burstIndex - 1
	local offsetStep
	if patternIndex % 2 == 1 then
		offsetStep = -math.ceil(patternIndex / 2)
	else
		offsetStep = math.floor(patternIndex / 2)
	end

	return right * (optionalVisualSpread * offsetStep)
end

local function computeVisualBurstSpawnOffset(projectileId, burstIndex, sharedOptions, burstSettings)
	local random = getBurstRandom(projectileId, burstIndex)
	local _, right = getBurstBasis(sharedOptions.Direction)
	local laneOffset = computeBurstLaneOffset(sharedOptions.Direction, burstSettings.OptionalVisualSpread, burstIndex)
	local lateralOffset = right * random:NextNumber(-burstSettings.SpawnOffsetRadius, burstSettings.SpawnOffsetRadius)
	local verticalOffset = Vector3.yAxis * random:NextNumber(burstSettings.VerticalOffsetMin, burstSettings.VerticalOffsetMax)
	return laneOffset + lateralOffset + verticalOffset
end

local function computeVisualBurstInitialDirection(projectileId, burstIndex, baseDirection, burstSettings)
	local random = getBurstRandom(projectileId .. "_direction", burstIndex)
	local _, right = getBurstBasis(baseDirection)
	local yawRadians = math.rad(random:NextNumber(-burstSettings.InitialSpreadAngle, burstSettings.InitialSpreadAngle))
	local pitchRadians = math.rad(random:NextNumber(-burstSettings.InitialSpreadAngle * 0.45, burstSettings.InitialSpreadAngle * 0.45))
	local rotatedDirection = rotateDirectionAroundAxis(baseDirection, Vector3.yAxis, yawRadians)
	rotatedDirection = rotateDirectionAroundAxis(rotatedDirection, right, pitchRadians)
	return getProjectileDirection(rotatedDirection, nil)
end

local function applyProjectileVisualTransform(projectileState, position, velocity, fallbackDirection)
	local facingVelocity = typeof(velocity) == "Vector3" and velocity or projectileState.Velocity
	if projectileState.VisualState then
		local transformApplied, coreFound, facing = HieVfx.SetFreezeShotProjectileTransform(
			projectileState.VisualState,
			position,
			facingVelocity,
			fallbackDirection or projectileState.Direction,
			projectileState.OrientationCorrectionCFrame
		)
		if transformApplied then
			projectileState.Part = projectileState.VisualState.AnchorPart
			if not coreFound and not projectileState.WarnedMissingShardCore then
				projectileState.WarnedMissingShardCore = true
				warnBurst(
					"shard core missing for orientation fix projectileId=%s index=%d",
					tostring(projectileState.AuthoritativeProjectileId or projectileState.Id),
					tonumber(projectileState.BurstIndex) or 1
				)
			elseif coreFound and not projectileState.LoggedOrientationCorrection then
				projectileState.LoggedOrientationCorrection = true
				logBurst(
					"shard facing base=%s index=%d projectileId=%s",
					formatVector3(facing),
					tonumber(projectileState.BurstIndex) or 1,
					tostring(projectileState.AuthoritativeProjectileId or projectileState.Id)
				)
				logBurst(
					"shard orientation correction applied=%s index=%d projectileId=%s",
					formatOrientationCorrection(projectileState.OrientationCorrectionCFrame),
					tonumber(projectileState.BurstIndex) or 1,
					tostring(projectileState.AuthoritativeProjectileId or projectileState.Id)
				)
			end
			return
		end
	end

	setFreezeShotVisualTransform(projectileState.Part, position, facingVelocity, projectileState.Direction)
end

local function updateVisualOnlyProjectileMotion(projectileState, serverNow)
	local currentPosition = typeof(projectileState.CurrentPosition) == "Vector3" and projectileState.CurrentPosition or projectileState.StartPosition
	local currentDirection = getProjectileDirection(projectileState.CurrentDirection or projectileState.Direction, nil)
	local currentVelocity = currentDirection * projectileState.Speed
	local dt = math.clamp(serverNow - (tonumber(projectileState.LastUpdateAt) or serverNow), 0, 0.1)
	projectileState.LastUpdateAt = serverNow

	if projectileState.HomingEnabled and projectileState.TargetPosition and dt > 0 then
		local elapsed = math.max(0, serverNow - projectileState.StartedAt)
		if elapsed >= projectileState.HomingDelay then
			local targetPosition = projectileState.ImpactPosition or projectileState.TargetPosition
			local toTarget = targetPosition - currentPosition
			if toTarget.Magnitude <= math.max(1.25, projectileState.Radius * 2.5) then
				if not projectileState.WarnedCloseTarget then
					projectileState.WarnedCloseTarget = true
					warnBurst(
						"target too close for homing, using straight path projectileId=%s index=%d",
						tostring(projectileState.AuthoritativeProjectileId or projectileState.Id),
						tonumber(projectileState.BurstIndex) or 1
					)
				end
				projectileState.HomingEnabled = false
			else
				local desiredDirection = toTarget.Unit
				local homingAlpha = 1 - math.exp(-projectileState.HomingStrength * dt)
				local steeringDirection = currentDirection:Lerp(desiredDirection, homingAlpha)
				if steeringDirection.Magnitude > 0.01 then
					desiredDirection = steeringDirection.Unit
				end

				local nextDirection, wasClamped, angleBetween = turnDirectionTowards(
					currentDirection,
					desiredDirection,
					projectileState.MaxTurnRateRadians * dt
				)
				currentDirection = nextDirection
				currentVelocity = currentDirection * projectileState.Speed
				local canLogHoming = DEBUG_VFX and serverNow >= (projectileState.NextHomingLogAt or 0)

				if canLogHoming then
					logBurst(
						"visual shard homing update index=%d projectileId=%s position=%s target=%s direction=%s",
						tonumber(projectileState.BurstIndex) or 1,
						tostring(projectileState.AuthoritativeProjectileId or projectileState.Id),
						formatVector3(currentPosition),
						formatVector3(targetPosition),
						formatVector3(currentDirection)
					)
				end

				if wasClamped and canLogHoming then
					logBurst(
						"visual shard turn clamped index=%d projectileId=%s angle=%.2f",
						tonumber(projectileState.BurstIndex) or 1,
						tostring(projectileState.AuthoritativeProjectileId or projectileState.Id),
						math.deg(angleBetween)
					)
				end

				if canLogHoming then
					projectileState.NextHomingLogAt = serverNow + 0.12
				end
			end
		end
	end

	local remainingDistance = math.max(0, projectileState.MaxDistance - (tonumber(projectileState.DistanceTraveled) or 0))
	local stepDistance = math.min(projectileState.Speed * dt, remainingDistance)
	currentPosition = currentPosition + (currentDirection * stepDistance)
	projectileState.DistanceTraveled = math.min(projectileState.MaxDistance, (tonumber(projectileState.DistanceTraveled) or 0) + stepDistance)
	projectileState.CurrentPosition = currentPosition
	projectileState.CurrentDirection = currentDirection
	projectileState.Velocity = currentVelocity

	return currentPosition, currentVelocity
end

function HieClient:SpawnVisualBurstClone(targetPlayer, projectileId, sharedOptions, burstIndex, spawnDelay)
	local burstGroup = self.activeBurstGroups[projectileId]
	if not burstGroup or burstGroup.Canceled then
		return
	end

	local authoritativeState = self.activeFreezeShots[projectileId]
	if not authoritativeState then
		return
	end

	local snapshotTime = Workspace:GetServerTimeNow()
	local cloneStartedAt = snapshotTime
	local burstBasePosition = sharedOptions.StartPosition

	if authoritativeState.ResolvedAt and authoritativeState.ResolvedAt <= cloneStartedAt then
		logBurst("skipped gameplay hit logic for visual-only clone index=%d projectileId=%s", burstIndex, projectileId)
		return
	end

	local spawnOffset = computeVisualBurstSpawnOffset(projectileId, burstIndex, sharedOptions, burstGroup.Settings)
	local cloneStartPosition = burstBasePosition + spawnOffset
	local initialDirection = computeVisualBurstInitialDirection(projectileId, burstIndex, sharedOptions.Direction, burstGroup.Settings)
	local targetPosition = cloneStartPosition + (initialDirection * sharedOptions.MaxDistance)
	local resolutionPayload = nil
	if authoritativeState.ResolvedAt ~= nil then
		resolutionPayload = {
			ResolvedAt = authoritativeState.ResolvedAt,
			ImpactPosition = authoritativeState.ImpactPosition,
		}
	end

	local spawnSnapshot = getFreezeShotTravelSnapshot(
		cloneStartPosition,
		initialDirection * sharedOptions.ProjectileSpeed,
		sharedOptions.MaxDistance,
		cloneStartedAt,
		snapshotTime,
		resolutionPayload
	)
	local visualProjectileId = string.format("%s_visual_%d", projectileId, burstIndex)
	local cloneState = self:CreateFreezeShotProjectileState({
		ProjectileKey = visualProjectileId,
		AuthoritativeProjectileId = projectileId,
		TargetPlayerName = targetPlayer.Name,
		Direction = initialDirection,
		ProjectileVelocity = initialDirection * sharedOptions.ProjectileSpeed,
		Radius = sharedOptions.Radius,
		MaxDistance = sharedOptions.MaxDistance,
		Lifetime = sharedOptions.Lifetime,
		StartedAt = cloneStartedAt,
		StartPosition = cloneStartPosition,
		VisualStartPosition = spawnSnapshot.Position,
		InitialDistanceTraveled = spawnSnapshot.Distance,
		TargetPosition = targetPosition,
		UseCurvedVisualPath = true,
		HomingEnabled = burstGroup.Settings.HomingStrength > 0 and burstGroup.Settings.MaxTurnRateRadians > 0,
		HomingDelay = burstGroup.Settings.HomingDelay,
		HomingStrength = burstGroup.Settings.HomingStrength,
		MaxTurnRateRadians = burstGroup.Settings.MaxTurnRateRadians,
		VisualSpawnOffset = spawnOffset,
		OrientationCorrectionCFrame = burstGroup.Settings.OrientationCorrectionCFrame,
		ResolvedAt = authoritativeState.ResolvedAt,
		ImpactPosition = authoritativeState.ImpactPosition,
		ShouldCreateImpact = false,
		IsVisualOnly = true,
		BurstIndex = burstIndex,
		BurstMode = burstGroup.Settings.Mode,
	})
	if not cloneState then
		return
	end

	if (targetPosition - spawnSnapshot.Position).Magnitude <= math.max(1.25, cloneState.Radius * 2.5) then
		cloneState.HomingEnabled = false
		cloneState.WarnedCloseTarget = true
		warnBurst("target too close for homing, using straight path projectileId=%s index=%d", projectileId, burstIndex)
	end

	logBurst(
		"spawned visual shot index=%d projectileId=%s visualProjectileId=%s position=%s",
		burstIndex,
		projectileId,
		visualProjectileId,
		formatVector3(spawnSnapshot.Position)
	)
	logBurst("visual shard spawn index=%d offset=%s", burstIndex, formatVector3(spawnOffset))
	logBurst("visual shard initialDirection index=%d direction=%s", burstIndex, formatVector3(initialDirection))
	logBurst("visual shard target index=%d target=%s", burstIndex, formatVector3(targetPosition))
	logBurst("skipped gameplay hit logic for visual-only clone index=%d projectileId=%s", burstIndex, projectileId)
end

function HieClient:StartVisualBurst(targetPlayer, projectileId, sharedOptions)
	local burstSettings = self:GetFreezeShotBurstSettings()
	if burstSettings.BurstCount <= 1 then
		return
	end

	self.activeBurstGroups[projectileId] = {
		ProjectileId = projectileId,
		Canceled = false,
		CloneIds = {},
		Settings = burstSettings,
	}

	logBurst("Freeze Shot burst start")
	logBurst(
		"mode=%s count=%d interval=%.3f shotgunAngle=%.2f positionSpread=%.3f offsetRadius=%.3f homingStrength=%.2f homingDelay=%.3f projectileId=%s",
		burstSettings.Mode,
		burstSettings.BurstCount,
		burstSettings.BurstInterval,
		burstSettings.InitialSpreadAngle,
		burstSettings.OptionalVisualSpread,
		burstSettings.SpawnOffsetRadius,
		burstSettings.HomingStrength,
		burstSettings.HomingDelay,
		projectileId
	)
	logBurst("authoritative projectile index=1 projectileId=%s", projectileId)

	if burstSettings.BurstInterval <= 0.01 then
		logBurst("burstInterval=%.3f using single-point shotgun burst", burstSettings.BurstInterval)
	end

	if burstSettings.OptionalVisualSpread > 0.4 then
		warnBurst("optionalVisualSpread=%.3f may make the burst look inaccurate", burstSettings.OptionalVisualSpread)
	end
	if burstSettings.SpawnOffsetRadius > 1.5 then
		warnBurst("spawnOffsetRadius=%.3f may make the burst look chaotic", burstSettings.SpawnOffsetRadius)
	end
	if burstSettings.MaxTurnRateRadians > math.rad(540) then
		warnBurst("maxTurnRate=%.2fdeg may cause snapping", math.deg(burstSettings.MaxTurnRateRadians))
	end

	for burstIndex = 2, burstSettings.BurstCount do
		local spawnDelay = burstSettings.BurstInterval * (burstIndex - 1)
		if spawnDelay <= 0 then
			self:SpawnVisualBurstClone(targetPlayer, projectileId, sharedOptions, burstIndex, spawnDelay)
		else
			task.delay(spawnDelay, function()
				self:SpawnVisualBurstClone(targetPlayer, projectileId, sharedOptions, burstIndex, spawnDelay)
			end)
		end
	end
end

function HieClient:RegisterFreezeShotLaunch(targetPlayer, payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		logVfxError("launch ignored missingRoot player=%s payload={%s}", targetPlayer.Name, describeFreezeShotPayload(payload))
		return false
	end

	local projectileId = tostring(payload.ProjectileId or "")
	if projectileId == "" then
		logVfxError("launch ignored missingProjectileId player=%s payload={%s}", targetPlayer.Name, describeFreezeShotPayload(payload))
		return false
	end

	logVfx("INIT", "launch received player=%s payload={%s}", targetPlayer.Name, describeFreezeShotPayload(payload))

	if targetPlayer == self.player then
		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
	end

	self:CleanupFreezeShot(projectileId, "restart")

	local receiptTime = Workspace:GetServerTimeNow()
	local pendingResolution = self.pendingResolutions[projectileId]
	local direction = getProjectileDirection(payload.Direction, rootPart)
	local speed = math.max(1, tonumber(payload.ProjectileSpeed) or 0)
	local radius = math.max(0.25, tonumber(payload.ProjectileRadius) or 0.8)
	local maxDistance = math.max(1, tonumber(payload.MaxDistance) or tonumber(payload.Range) or 0)
	local lifetime = math.max(0.05, tonumber(payload.Lifetime) or (maxDistance / speed))
	local launchForwardOffset = math.max(
		0,
		tonumber(payload.LaunchForwardOffset) or FREEZE_SHOT_HAND_FORWARD_OFFSET
	)
	local startedAt = tonumber(payload.StartedAt) or Workspace:GetServerTimeNow()
	local startPosition = typeof(payload.StartPosition) == "Vector3"
		and payload.StartPosition
		or (rootPart.Position + Vector3.new(0, 1.2, 0) + direction * 3)
	local projectileVelocity = getFreezeShotVelocity(payload, direction, speed)
	speed = math.max(1, projectileVelocity.Magnitude)
	direction = projectileVelocity.Magnitude > 0.01 and projectileVelocity.Unit or direction
	local launchForwardDirection = typeof(payload.ShotgunOriginDirection) == "Vector3"
		and getProjectileDirection(payload.ShotgunOriginDirection, nil)
		or direction
	local burstSettings = self:GetFreezeShotBurstSettings()
	local visualStartPosition
	local fastForwardDistance = 0
	local launchSource = "ServerStart"

	if targetPlayer == self.player then
		local groupKey = tostring(payload.ShotgunGroupId or projectileId)
		self.freezeShotLaunchGroups = self.freezeShotLaunchGroups or {}
		local cachedLaunch = self.freezeShotLaunchGroups[groupKey]
		if not cachedLaunch then
			local localLaunchOrigin, localLaunchSource = getFreezeShotLaunchOriginPosition(targetPlayer)
			if typeof(localLaunchOrigin) == "Vector3" then
				cachedLaunch = {
					Origin = localLaunchOrigin,
					Direction = launchForwardDirection,
					Source = localLaunchSource or "LocalHand",
				}
				self.freezeShotLaunchGroups[groupKey] = cachedLaunch
				task.delay(FREEZE_SHOT_MUZZLE_CACHE_TTL, function()
					if self.freezeShotLaunchGroups and self.freezeShotLaunchGroups[groupKey] == cachedLaunch then
						self.freezeShotLaunchGroups[groupKey] = nil
					end
				end)
			end
		end

		if cachedLaunch and typeof(cachedLaunch.Origin) == "Vector3" then
			local cachedDirection = typeof(cachedLaunch.Direction) == "Vector3" and cachedLaunch.Direction or launchForwardDirection
			startPosition = cachedLaunch.Origin + (cachedDirection * launchForwardOffset)
			visualStartPosition = startPosition
			startedAt = receiptTime
			launchSource = cachedLaunch.Source or "LocalHand"
			logVfx(
				"HAND",
				"projectileId=%s source=%s receipt=%.3f visualStart=%s velocity=%s",
				projectileId,
				tostring(launchSource),
				receiptTime,
				formatVector3(visualStartPosition),
				formatVector3(projectileVelocity)
			)
		end
	end

	if typeof(visualStartPosition) ~= "Vector3" then
		local spawnSnapshot = getFreezeShotTravelSnapshot(
			startPosition,
			projectileVelocity,
			maxDistance,
			startedAt,
			receiptTime,
			pendingResolution and pendingResolution.Payload or nil
		)
		visualStartPosition = spawnSnapshot.Position
		fastForwardDistance = (visualStartPosition - startPosition).Magnitude

		if fastForwardDistance > 0.05 then
			logVfx(
				"DESYNC",
				"projectileId=%s receipt=%.3f startedAt=%.3f elapsed=%.3f rawStart=%s visualStart=%s offset=%.2f velocity=%s",
				projectileId,
				receiptTime,
				startedAt,
				spawnSnapshot.Elapsed,
				formatVector3(startPosition),
				formatVector3(visualStartPosition),
				fastForwardDistance,
				formatVector3(projectileVelocity)
			)
		end

		logVfx(
			"FASTFORWARD",
			"projectileId=%s receipt=%.3f startedAt=%.3f elapsed=%.3f rawStart=%s visualStart=%s velocity=%s maxDistance=%.2f clamped=%s reason=%s",
			projectileId,
			receiptTime,
			startedAt,
			spawnSnapshot.Elapsed,
			formatVector3(startPosition),
			formatVector3(visualStartPosition),
			formatVector3(projectileVelocity),
			maxDistance,
			tostring(spawnSnapshot.Clamped),
			spawnSnapshot.ClampReason
		)
	end

	local projectileState = self:CreateFreezeShotProjectileState({
		ProjectileKey = projectileId,
		AuthoritativeProjectileId = projectileId,
		TargetPlayerName = targetPlayer.Name,
		Direction = direction,
		ProjectileVelocity = projectileVelocity,
		Radius = radius,
		MaxDistance = maxDistance,
		Lifetime = lifetime,
		StartedAt = startedAt,
		StartPosition = startPosition,
		VisualStartPosition = visualStartPosition,
		ShouldCreateImpact = false,
		IsVisualOnly = false,
		BurstIndex = math.max(1, tonumber(payload.ShotgunIndex) or 1),
		BurstMode = burstSettings.Mode,
		OrientationCorrectionCFrame = burstSettings.OrientationCorrectionCFrame,
	})
	if not projectileState then
		return false
	end

	if payload.DisableVisualBurst == true then
		logBurst(
			"server gameplay shotgun projectile index=%s/%s projectileId=%s visualBurst=false",
			tostring(payload.ShotgunIndex),
			tostring(payload.ShotgunCount),
			projectileId
		)
	else
		self:StartVisualBurst(targetPlayer, projectileId, {
			StartPosition = startPosition,
			StartedAt = startedAt,
			Direction = direction,
			ProjectileVelocity = projectileVelocity,
			ProjectileSpeed = speed,
			Radius = radius,
			MaxDistance = maxDistance,
			Lifetime = lifetime,
			LaunchForwardOffset = launchForwardOffset,
			TargetPosition = startPosition + (direction * maxDistance),
		})
	end

	logVfx(
		"SPAWN",
		"projectile initialized player=%s projectileId=%s receipt=%.3f startedAt=%.3f speed=%.2f velocity=%s rawStart=%s visualStart=%s source=%s maxDistance=%.2f radius=%.2f lifetime=%.2f",
		targetPlayer.Name,
		projectileId,
		receiptTime,
		startedAt,
		speed,
		formatVector3(projectileVelocity),
		formatVector3(startPosition),
		formatVector3(visualStartPosition),
		tostring(launchSource),
		maxDistance,
		radius,
		lifetime
	)

	if pendingResolution then
		self.pendingResolutions[projectileId] = nil
		logVfx(
			"PROJECTILE",
			"applying queued resolution projectileId=%s createImpact=%s",
			projectileId,
			tostring(pendingResolution.ShouldCreateImpact)
		)
		self:ResolveFreezeShotVisual(pendingResolution.Payload, pendingResolution.ShouldCreateImpact)
	end

	return true
end

function HieClient:ResolveFreezeShotVisual(payload, shouldCreateImpact)
	local projectileId = tostring(payload.ProjectileId or "")
	if projectileId == "" then
		logVfxError("resolution ignored missingProjectileId payload={%s}", describeFreezeShotPayload(payload))
		return false
	end

	logVfx(
		"PROJECTILE",
		"resolution received projectileId=%s createImpact=%s payload={%s}",
		projectileId,
		tostring(shouldCreateImpact),
		describeFreezeShotPayload(payload)
	)

	local projectileState = self.activeFreezeShots[projectileId]
	if not projectileState then
		self.pendingResolutions[projectileId] = {
			Payload = payload,
			ShouldCreateImpact = shouldCreateImpact,
		}
		logVfx(
			"PROJECTILE",
			"resolution queued waitingForLaunch projectileId=%s createImpact=%s",
			projectileId,
			tostring(shouldCreateImpact)
		)
		return false
	end

	projectileState.ResolvedAt = tonumber(payload.ResolvedAt) or Workspace:GetServerTimeNow()
	projectileState.ImpactPosition = typeof(payload.ImpactPosition) == "Vector3" and payload.ImpactPosition or projectileState.Part.Position
	projectileState.ShouldCreateImpact = shouldCreateImpact
	self:PropagateBurstResolution(projectileState)
	return true
end

function HieClient:UpdateFreezeShots()
	local serverNow = Workspace:GetServerTimeNow()
	local cleanupIds = {}

	for projectileId, projectileState in pairs(self.activeFreezeShots) do
		if not projectileState.Part or not projectileState.Part.Parent then
			logVfxError("projectile visual missing projectileId=%s cleanedUp=true", projectileId)
			cleanupIds[#cleanupIds + 1] = projectileId
			continue
		end

		local elapsed = math.max(0, serverNow - projectileState.StartedAt)
		local currentPosition
		local currentVelocity

		if projectileState.IsVisualOnly and projectileState.UseCurvedVisualPath then
			currentPosition, currentVelocity = updateVisualOnlyProjectileMotion(projectileState, serverNow)
		else
			local maxTravelTime = projectileState.Speed > 0 and (projectileState.MaxDistance / projectileState.Speed) or 0
			local effectiveTravelTime = math.min(elapsed, maxTravelTime)
			local traveledDistance = math.min(projectileState.Speed * effectiveTravelTime, projectileState.MaxDistance)
			currentVelocity = projectileState.Velocity
			currentPosition = projectileState.StartPosition + (currentVelocity * effectiveTravelTime)
			projectileState.DistanceTraveled = traveledDistance
			projectileState.CurrentPosition = currentPosition
			projectileState.CurrentDirection = currentVelocity.Magnitude > 0.01 and currentVelocity.Unit or projectileState.Direction
		end

		if DEBUG_VFX_VERBOSE then
			logVfxVerbose(
				"projectileId=%s elapsed=%.2f distance=%.2f current=%s velocity=%s",
				projectileId,
				elapsed,
				tonumber(projectileState.DistanceTraveled) or 0,
				formatVector3(currentPosition),
				formatVector3(currentVelocity)
			)
		end

		if projectileState.ResolvedAt ~= nil then
			local resolvedPosition = projectileState.ImpactPosition or currentPosition
			if serverNow >= projectileState.ResolvedAt then
				applyProjectileVisualTransform(
					projectileState,
					resolvedPosition,
					currentVelocity,
					projectileState.Direction
				)

				if projectileState.ShouldCreateImpact and not projectileState.ImpactEffectPlayed then
					projectileState.ImpactEffectPlayed = true
					logVfx(
						"IMPACT",
						"rendering impact projectileId=%s position=%s",
						projectileId,
						formatVector3(resolvedPosition)
					)
					local impactOk = projectileState.VisualState and HieVfx.TriggerFreezeShotImpact(resolvedPosition)
					if not impactOk then
						local fallbackOk, fallbackError = pcall(createIceImpactEffect, resolvedPosition)
						if not fallbackOk then
							logVfxError("impact effect failed projectileId=%s detail=%s", projectileId, tostring(fallbackError))
						end
					end
				end

				cleanupIds[#cleanupIds + 1] = projectileId
				continue
			end
		end

		applyProjectileVisualTransform(
			projectileState,
			currentPosition,
			currentVelocity,
			projectileState.Direction
		)

		if elapsed >= (projectileState.Lifetime + 0.2) or (tonumber(projectileState.DistanceTraveled) or 0) >= projectileState.MaxDistance then
			logVfx("PROJECTILE", "forcing cleanup expiredVisual=true projectileId=%s", projectileId)
			cleanupIds[#cleanupIds + 1] = projectileId
		end
	end

	for _, projectileId in ipairs(cleanupIds) do
		self:CleanupFreezeShot(projectileId, "update_loop")
	end
end

function HieClient:UpdateIceBoostEffects()
	local now = os.clock()

	for targetPlayer, state in pairs(self.activeIceBoostEffects) do
		local rootPart = getPlayerRootPart(targetPlayer)
		if not rootPart then
			self:CleanupIceBoostEffect(targetPlayer, "missing_root")
			continue
		end

		if now >= (state.EndAt or 0) then
			self:CleanupIceBoostEffect(targetPlayer, "duration_complete")
			continue
		end

		if not HieVfx.UpdateIceBoostEffect(state.VisualState, rootPart) then
			self:CleanupIceBoostEffect(targetPlayer, "update_failed")
		end
	end
end

function HieClient:HandleFreezeShotEffect(targetPlayer, payload)
	local resolvedPayload = payload or {}
	local phase = typeof(resolvedPayload.Phase) == "string" and resolvedPayload.Phase or "Launch"

	logVfx(
		"INIT",
		"effect received player=%s phase=%s payload={%s}",
		targetPlayer.Name,
		phase,
		describeFreezeShotPayload(resolvedPayload)
	)

	local ok, err = pcall(function()
		if phase == "Launch" then
			self:RegisterFreezeShotLaunch(targetPlayer, resolvedPayload)
			return
		end

		if phase == "Impact" then
			self:ResolveFreezeShotVisual(resolvedPayload, true)
			return
		end

		if phase == "Expire" then
			logVfx("PROJECTILE", "impactless expiry received projectileId=%s", tostring(resolvedPayload.ProjectileId))
			self:ResolveFreezeShotVisual(resolvedPayload, false)
			return
		end

		logVfxError("unknown phase=%s player=%s payload={%s}", tostring(phase), targetPlayer.Name, describeFreezeShotPayload(resolvedPayload))
	end)

	if not ok then
		logVfxError(
			"handler failed player=%s phase=%s detail=%s payload={%s}",
			targetPlayer.Name,
			tostring(phase),
			tostring(err),
			describeFreezeShotPayload(resolvedPayload)
		)
	end
end

function HieClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName == HieClient.FREEZE_SHOT_ABILITY then
		self:HandleFreezeShotEffect(targetPlayer, payload or {})
		return true
	end

	if abilityName == HieClient.ICE_BOOST_ABILITY then
		self:CreateIceBoostEffect(targetPlayer, payload or {})
		return true
	end

	return false
end

function HieClient:HandleStateEvent(eventName, abilityName)
	if abilityName == HieClient.FREEZE_SHOT_ABILITY and eventName == "Denied" then
		self:ClearLocalFreezeShotCastLock()
	end
end

function HieClient:Update()
	self:UpdateFreezeShots()
	self:UpdateIceBoostEffects()
end

function HieClient:CleanupCharacterRemoving()
	self:ClearLocalFreezeShotCastLock()

	local projectileIds = {}
	for projectileId in pairs(self.activeFreezeShots) do
		projectileIds[#projectileIds + 1] = projectileId
	end

	for _, projectileId in ipairs(projectileIds) do
		self:CleanupFreezeShot(projectileId, "character_removing")
	end

	self.activeBurstGroups = {}
	self.freezeShotLaunchGroups = {}
	for targetPlayer in pairs(self.activeIceBoostEffects) do
		self:CleanupIceBoostEffect(targetPlayer, "character_removing")
	end
	self.pendingResolutions = {}
end

function HieClient:CleanupPlayerRemoving(leavingPlayer)
	self:CleanupIceBoostEffect(leavingPlayer, "player_removing")
end

return HieClient
