local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AbilityTargeting = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Shared")
		:WaitForChild("AbilityTargeting")
)
local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local HitResolver = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitResolver"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))

local BomuServer = {}

local activeMinesByPlayer = {}

local EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local LAND_MINE_MODEL_NAME = "BomuLandMine"
local LAND_MINE_ACTION_PLACED = "Placed"
local LAND_MINE_ACTION_DETONATING = "Detonating"
local LAND_MINE_ACTION_DETONATED = "Detonated"
local LAND_MINE_SOURCE = "LandMine"
local MIN_PLANAR_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_PLANAR_DIRECTION = Vector3.new(0, 0, -1)
local GROUND_CAST_HEIGHT = 4
local GROUND_CAST_DISTANCE = 18
local GROUND_NORMAL_OFFSET = 0.02
local DEFAULT_HUMANOID_HIP_HEIGHT = 2
local FALLBACK_GROUND_CLEARANCE = 2.5
local MIN_FALLBACK_GROUND_HEIGHT = 4
local MINE_BODY_HEIGHT = 0.34
local MINE_INDICATOR_GROUND_OFFSET = 0.03
local MINE_CORE_GROUND_OFFSET = 0.01
local MINE_RADIUS_INDICATOR_THICKNESS = 0.08
local MINE_RADIUS_CORE_THICKNESS = 0.04
local MINE_RADIUS_CORE_SCALE = 1.2
local MINE_RADIUS_INDICATOR_TRANSPARENCY = 0.72
local MINE_RADIUS_CORE_TRANSPARENCY = 0.82
local MINE_BODY_SIZE = Vector3.new(1.15, 0.48, 1.15)
local MINE_CAP_SIZE = Vector3.new(0.58, 0.2, 0.58)
local MINE_BEACON_SIZE = Vector3.new(0.24, 0.24, 0.24)
local MINE_CAP_HEIGHT_OFFSET = 0.18
local MINE_BEACON_HEIGHT_OFFSET = 0.34
local MINE_CYLINDER_ORIENTATION = Vector3.new(90, 0, 0)
local MINE_RADIUS_DISC_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local MINE_INDICATOR_COLOR = Color3.fromRGB(255, 64, 64)
local MINE_CORE_COLOR = Color3.fromRGB(255, 110, 92)
local MINE_BODY_COLOR = Color3.fromRGB(38, 36, 36)
local MINE_CAP_COLOR = Color3.fromRGB(198, 44, 44)
local MINE_BEACON_COLOR = Color3.fromRGB(255, 82, 82)
local MINE_BEACON_TRANSPARENCY = 0.08
local OWNER_NETWORK_OWNER_RELEASE_DELAY = 0.35
local OWNER_INHERITED_HORIZONTAL_VELOCITY_FACTOR = 0.18
local RADIUS_MATCH_EPSILON = 0.05
local PLAYER_RADIUS_RECONCILE_TIME = 0.16
local MAX_PLAYER_RADIUS_RECONCILE_DISTANCE = 7
local MAX_PLAYER_PLANAR_EXTENT = 3
local SEGMENT_LENGTH_EPSILON = 0.0001
local HAZARD_QUERY_PLAYER_DISTANCE_PADDING = 8
local HAZARD_QUERY_MAX_TARGETS = 8
local DEFAULT_DETONATION_EXPLOSION_DELAY = 0.35
local DEFAULT_SPEED_SCALING_REFERENCE_SPEED = 32

local function getPlanarUnitOrFallback(vector, fallback)
	local planarVector = Vector3.new(vector.X, 0, vector.Z)
	if planarVector.Magnitude > MIN_PLANAR_DIRECTION_MAGNITUDE then
		return planarVector.Unit
	end

	if typeof(fallback) == "Vector3" and fallback.Magnitude > MIN_PLANAR_DIRECTION_MAGNITUDE then
		local planarFallback = Vector3.new(fallback.X, 0, fallback.Z)
		if planarFallback.Magnitude > MIN_PLANAR_DIRECTION_MAGNITUDE then
			return planarFallback.Unit
		end
	end

	return DEFAULT_PLANAR_DIRECTION
end

local function buildGroundRaycastParams(character, extraExclusions)
	local exclusions = {}
	if character then
		exclusions[#exclusions + 1] = character
	end

	if type(extraExclusions) == "table" then
		for _, exclusion in ipairs(extraExclusions) do
			if typeof(exclusion) == "Instance" then
				exclusions[#exclusions + 1] = exclusion
			end
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = exclusions
	raycastParams.IgnoreWater = false
	return raycastParams
end

local function ensureEffectsFolder()
	local folder = Workspace:FindFirstChild(EFFECTS_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = EFFECTS_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function getKnockbackVector(centerPosition, targetRootPart, fallbackDirection, abilityConfig)
	local direction = getPlanarUnitOrFallback(targetRootPart.Position - centerPosition, fallbackDirection)
	local horizontalStrength = math.max(0, tonumber(abilityConfig.KnockbackHorizontal) or 0)
	local verticalStrength = math.max(0, tonumber(abilityConfig.KnockbackVertical) or 0)

	return (direction * horizontalStrength) + Vector3.new(0, verticalStrength, 0)
end

local function applyLaunchVelocity(rootPart, launchVelocity)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = launchVelocity

	local velocityDelta = launchVelocity - currentVelocity
	local impulse = velocityDelta * rootPart.AssemblyMass
	rootPart:ApplyImpulse(impulse)
end

local function getMineOwnerKey(context)
	if type(context) ~= "table" then
		return nil
	end

	return context.Player or context.Character
end

local function getMineOwnerUserId(owner)
	if typeof(owner) == "Instance" and owner:IsA("Player") then
		return owner.UserId
	end

	return 0
end

local function getRootPlanarSpeed(rootPart)
	if typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") then
		return 0
	end

	local velocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function getWalkSpeedSample(humanoid, abilityConfig)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		return 0
	end

	local speedScaling = type(abilityConfig) == "table" and abilityConfig.SpeedScaling or nil
	if
		type(speedScaling) == "table"
		and (speedScaling.UseWalkSpeed == false or speedScaling.UseMovementIntentSpeed == false)
	then
		return 0
	end

	local multiplier = if type(speedScaling) == "table"
		then tonumber(speedScaling.WalkSpeedMultiplier) or tonumber(speedScaling.MovementIntentSpeedMultiplier)
		else nil
	return math.max(0, tonumber(humanoid.WalkSpeed) or 0) * math.max(0, multiplier or 1)
end

local function getEffectivePlanarSpeed(rootPart, humanoid, abilityConfig)
	return math.max(
		getRootPlanarSpeed(rootPart),
		getWalkSpeedSample(humanoid, abilityConfig)
	)
end

local function getSpeedScalingMultiplier(abilityConfig, sectionName, sourceSpeed)
	local speedScaling = type(abilityConfig) == "table" and abilityConfig.SpeedScaling or nil
	local section = type(speedScaling) == "table" and speedScaling[sectionName] or nil
	if type(section) ~= "table" then
		return 1, 0
	end

	local referenceSpeed = tonumber(section.ReferenceSpeed)
		or tonumber(speedScaling.ReferenceSpeed)
		or DEFAULT_SPEED_SCALING_REFERENCE_SPEED
	if referenceSpeed <= 0 then
		return 1, 0
	end

	local baselineSpeed = tonumber(section.BaselineSpeed) or tonumber(speedScaling.BaselineSpeed) or 0
	local speed = math.max(0, (tonumber(sourceSpeed) or 0) - math.max(0, baselineSpeed))
	local bonusPerReferenceSpeed = math.max(0, tonumber(section.BonusPerReferenceSpeed) or 0)
	local bonus = (speed / referenceSpeed) * bonusPerReferenceSpeed
	local maxBonus = tonumber(section.MaxBonus)
	if maxBonus then
		bonus = math.min(bonus, math.max(0, maxBonus))
	end

	return 1 + bonus, bonus
end

local function getScaledRadiusInfo(abilityConfig, rootPart, humanoid)
	local baseRadius = math.max(0, type(abilityConfig) == "table" and tonumber(abilityConfig.Radius) or 0)
	local sourceSpeed = getEffectivePlanarSpeed(rootPart, humanoid, abilityConfig)
	local multiplier, bonus = getSpeedScalingMultiplier(abilityConfig, "Radius", sourceSpeed)

	return {
		BaseRadius = baseRadius,
		Radius = baseRadius * multiplier,
		Speed = sourceSpeed,
		Multiplier = multiplier,
		Bonus = bonus,
	}
end

local function buildExplosionAbilityConfig(abilityConfig, radius, sourceSpeed)
	local explosionAbilityConfig = {}
	if type(abilityConfig) == "table" then
		for key, value in pairs(abilityConfig) do
			explosionAbilityConfig[key] = value
		end
	end

	local multiplier, bonus = getSpeedScalingMultiplier(abilityConfig, "DirectionalBlast", sourceSpeed)
	local baseRadius = type(abilityConfig) == "table" and tonumber(abilityConfig.Radius) or nil
	local baseKnockbackHorizontal =
		type(abilityConfig) == "table" and tonumber(abilityConfig.KnockbackHorizontal) or nil
	local baseOwnerLaunchHorizontal =
		type(abilityConfig) == "table" and tonumber(abilityConfig.OwnerLaunchHorizontal) or nil

	explosionAbilityConfig.Radius = math.max(0, tonumber(radius) or baseRadius or 0)
	explosionAbilityConfig.KnockbackHorizontal =
		math.max(0, baseKnockbackHorizontal or 0) * multiplier
	explosionAbilityConfig.OwnerLaunchHorizontal =
		math.max(0, baseOwnerLaunchHorizontal or 0) * multiplier

	return explosionAbilityConfig, {
		Speed = math.max(0, tonumber(sourceSpeed) or 0),
		Multiplier = multiplier,
		Bonus = bonus,
	}
end

local function getPlanarDistance(firstPosition, secondPosition)
	if typeof(firstPosition) ~= "Vector3" or typeof(secondPosition) ~= "Vector3" then
		return math.huge
	end

	local offset = firstPosition - secondPosition
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

local function getClosestPlanarDistanceToSegment(centerPosition, startPosition, endPosition)
	if typeof(centerPosition) ~= "Vector3" or typeof(startPosition) ~= "Vector3" or typeof(endPosition) ~= "Vector3" then
		return math.huge
	end

	local center = Vector3.new(centerPosition.X, 0, centerPosition.Z)
	local start = Vector3.new(startPosition.X, 0, startPosition.Z)
	local finish = Vector3.new(endPosition.X, 0, endPosition.Z)
	local segment = finish - start
	local lengthSquared = segment:Dot(segment)
	if lengthSquared <= SEGMENT_LENGTH_EPSILON then
		return (center - start).Magnitude
	end

	local alpha = math.clamp((center - start):Dot(segment) / lengthSquared, 0, 1)
	return (center - (start + (segment * alpha))).Magnitude
end

local function getCharacterPlanarBoxDistance(centerPosition, character)
	if typeof(centerPosition) ~= "Vector3" or typeof(character) ~= "Instance" or not character:IsA("Model") then
		return math.huge
	end

	local ok, boxCFrame, boxSize = pcall(function()
		return character:GetBoundingBox()
	end)
	if not ok or typeof(boxCFrame) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then
		return math.huge
	end

	local localCenter = boxCFrame:PointToObjectSpace(centerPosition)
	local halfSize = boxSize * 0.5
	local clampedLocal = Vector3.new(
		math.clamp(localCenter.X, -halfSize.X, halfSize.X),
		localCenter.Y,
		math.clamp(localCenter.Z, -halfSize.Z, halfSize.Z)
	)
	local closestPoint = boxCFrame:PointToWorldSpace(clampedLocal)
	return getPlanarDistance(centerPosition, closestPoint)
end

local function getCharacterPlanarExtent(character)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then
		return 0
	end

	local ok, _, boxSize = pcall(function()
		return character:GetBoundingBox()
	end)
	if not ok or typeof(boxSize) ~= "Vector3" then
		return 0
	end

	return math.min(Vector3.new(boxSize.X, 0, boxSize.Z).Magnitude * 0.5, MAX_PLAYER_PLANAR_EXTENT)
end

local function getRootMotionSweepOffset(rootPart)
	if typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") or not rootPart.Parent then
		return Vector3.zero
	end

	local velocity = rootPart.AssemblyLinearVelocity
	local planarVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = planarVelocity.Magnitude
	if speed <= MIN_PLANAR_DIRECTION_MAGNITUDE then
		return Vector3.zero
	end

	local distance = math.min(speed * PLAYER_RADIUS_RECONCILE_TIME, MAX_PLAYER_RADIUS_RECONCILE_DISTANCE)
	return planarVelocity.Unit * distance
end

local function doesCharacterOverlapDisplayedRadius(centerPosition, character, rootPart, radius)
	if typeof(centerPosition) ~= "Vector3" or radius <= 0 then
		return false
	end

	if getCharacterPlanarBoxDistance(centerPosition, character) <= radius + RADIUS_MATCH_EPSILON then
		return true
	end

	if typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") or not rootPart.Parent then
		return false
	end

	local sweepOffset = getRootMotionSweepOffset(rootPart)
	if sweepOffset.Magnitude <= RADIUS_MATCH_EPSILON then
		return false
	end

	local characterExtent = getCharacterPlanarExtent(character)
	return getClosestPlanarDistanceToSegment(
		centerPosition,
		rootPart.Position - sweepOffset,
		rootPart.Position + sweepOffset
	) <= radius + characterExtent + RADIUS_MATCH_EPSILON
end

local function getActiveMineEntry(player)
	local mineEntry = activeMinesByPlayer[player]
	if not mineEntry then
		return nil
	end

	local mineModel = mineEntry.Model
	if typeof(mineModel) ~= "Instance" or not mineModel.Parent then
		activeMinesByPlayer[player] = nil
		return nil
	end

	return mineEntry
end

local function clearActiveMine(player)
	local mineEntry = activeMinesByPlayer[player]
	activeMinesByPlayer[player] = nil

	if not mineEntry then
		return nil
	end

	local mineModel = mineEntry.Model
	if typeof(mineModel) == "Instance" and mineModel.Parent then
		mineModel:Destroy()
	end

	return mineEntry
end

local function setDisplayPartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function createDisplayPart(parent, name, size, color, cframe, shape, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CFrame = cframe
	part.Shape = shape or Enum.PartType.Block
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	setDisplayPartDefaults(part)
	part.Parent = parent
	return part
end

local function createLandMineModel(owner, groundPosition, radius)
	local ownerUserId = getMineOwnerUserId(owner)
	local model = Instance.new("Model")
	model.Name = string.format("%s_%d", LAND_MINE_MODEL_NAME, ownerUserId)
	model:SetAttribute("FruitKey", "Bomu")
	model:SetAttribute("OwnerUserId", ownerUserId)

	local indicatorPosition = groundPosition + Vector3.new(0, MINE_INDICATOR_GROUND_OFFSET, 0)
	createDisplayPart(
		model,
		"RadiusIndicator",
		Vector3.new(MINE_RADIUS_INDICATOR_THICKNESS, radius * 2, radius * 2),
		MINE_INDICATOR_COLOR,
		CFrame.new(indicatorPosition) * MINE_RADIUS_DISC_ROTATION,
		Enum.PartType.Cylinder,
		Enum.Material.Neon,
		MINE_RADIUS_INDICATOR_TRANSPARENCY
	)
	createDisplayPart(
		model,
		"RadiusCore",
		Vector3.new(MINE_RADIUS_CORE_THICKNESS, radius * MINE_RADIUS_CORE_SCALE, radius * MINE_RADIUS_CORE_SCALE),
		MINE_CORE_COLOR,
		CFrame.new(indicatorPosition + Vector3.new(0, MINE_CORE_GROUND_OFFSET, 0)) * MINE_RADIUS_DISC_ROTATION,
		Enum.PartType.Cylinder,
		Enum.Material.Neon,
		MINE_RADIUS_CORE_TRANSPARENCY
	)

	local bodyPosition = groundPosition + Vector3.new(0, MINE_BODY_HEIGHT, 0)
	local body = createDisplayPart(
		model,
		"Body",
		MINE_BODY_SIZE,
		MINE_BODY_COLOR,
		CFrame.new(bodyPosition),
		Enum.PartType.Cylinder,
		Enum.Material.Metal,
		0
	)
	body.Orientation = MINE_CYLINDER_ORIENTATION

	createDisplayPart(
		model,
		"Cap",
		MINE_CAP_SIZE,
		MINE_CAP_COLOR,
		CFrame.new(bodyPosition + Vector3.new(0, MINE_CAP_HEIGHT_OFFSET, 0)),
		Enum.PartType.Cylinder,
		Enum.Material.SmoothPlastic,
		0
	).Orientation = MINE_CYLINDER_ORIENTATION

	createDisplayPart(
		model,
		"Beacon",
		MINE_BEACON_SIZE,
		MINE_BEACON_COLOR,
		CFrame.new(bodyPosition + Vector3.new(0, MINE_BEACON_HEIGHT_OFFSET, 0)),
		Enum.PartType.Ball,
		Enum.Material.Neon,
		MINE_BEACON_TRANSPARENCY
	)

	model.PrimaryPart = body
	model.Parent = ensureEffectsFolder()
	return model, bodyPosition
end

local function scheduleMineCleanup(player, mineEntry, lifetime)
	if lifetime <= 0 then
		return
	end

	task.delay(lifetime, function()
		if activeMinesByPlayer[player] == mineEntry and mineEntry.PendingDetonation ~= true then
			clearActiveMine(player)
		end
	end)
end

local function getDetonationExplosionDelay(abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	local detonateConfig = type(animationConfig) == "table" and animationConfig.Detonate or nil
	local configuredDelay = type(detonateConfig) == "table" and tonumber(detonateConfig.ExplosionDelay) or nil
	if configuredDelay == nil then
		configuredDelay = type(abilityConfig) == "table" and tonumber(abilityConfig.DetonationExplosionDelay) or nil
	end

	return math.max(0, configuredDelay or DEFAULT_DETONATION_EXPLOSION_DELAY)
end

local function getMinePlacementPosition(context)
	local abilityConfig = context.AbilityConfig
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local placementDirection = getPlanarUnitOrFallback(humanoid.MoveDirection, rootPart.CFrame.LookVector)
	local placementDistance = math.max(0, tonumber(abilityConfig.PlacementDistance) or 0)
	local castOrigin = rootPart.Position + (placementDirection * placementDistance) + Vector3.new(0, GROUND_CAST_HEIGHT, 0)
	local raycastParams = buildGroundRaycastParams(character)
	local result = Workspace:Raycast(castOrigin, Vector3.new(0, -GROUND_CAST_DISTANCE, 0), raycastParams)

	if result then
		return result.Position + (result.Normal * GROUND_NORMAL_OFFSET)
	end

	local fallbackHeight = math.max(
		(humanoid.HipHeight or DEFAULT_HUMANOID_HIP_HEIGHT) + FALLBACK_GROUND_CLEARANCE,
		MIN_FALLBACK_GROUND_HEIGHT
	)
	return rootPart.Position + (placementDirection * placementDistance) - Vector3.new(0, fallbackHeight, 0)
end

local function buildExplosionPayload(context, centerPosition, abilityConfig)
	local radius = math.max(0, tonumber(abilityConfig.Radius) or 0)
	local knockdownDuration = math.max(0, tonumber(abilityConfig.KnockdownDuration) or 0)
	local fallbackDirection = getPlanarUnitOrFallback(context.RootPart.CFrame.LookVector, nil)
	local affectedUserIds = {}
	local destroyedHazardCount = 0
	local ownerUserId = getMineOwnerUserId(context.Player)
	local resolvedHits = HitResolver.ResolveRadiusHits({
		QueryId = string.format("bomu:%d:%d", ownerUserId, math.floor(os.clock() * 1000)),
		CenterPosition = centerPosition,
		Radius = radius,
		IncludePlayers = false,
		IncludeHazards = true,
		AllowedHazardClasses = {
			minor = true,
		},
		PlayerRootPosition = centerPosition,
		MaxPlayerDistance = radius + HAZARD_QUERY_PLAYER_DISTANCE_PADDING,
		MaxHazardTargets = HAZARD_QUERY_MAX_TARGETS,
		TracePrefix = "HIT",
	})

	for _, targetContext in ipairs(AbilityTargeting.GetCharacterTargets({
		ExcludePlayer = context.Player,
		ExcludeCharacter = context.Character,
	})) do
		local character = targetContext.Character
		local rootPart = targetContext.RootPart
		if not character or not rootPart then
			continue
		end

		if not doesCharacterOverlapDisplayedRadius(centerPosition, character, rootPart, radius) then
			continue
		end

		local knockbackVector = getKnockbackVector(centerPosition, rootPart, fallbackDirection, abilityConfig)
		local applied = HitEffectService.ApplyEffect(targetContext.Instance, "Knockdown", {
			Duration = knockdownDuration,
			DropPosition = rootPart.Position,
			RagdollJoints = true,
			RagdollImpulse = knockbackVector,
			Movement = {
				WalkSpeedMultiplier = 0,
				JumpMultiplier = 0,
				AutoRotate = false,
				PlatformStand = true,
				State = Enum.HumanoidStateType.Ragdoll,
			},
		})
		if applied then
			if targetContext.Player then
				affectedUserIds[#affectedUserIds + 1] = targetContext.Player.UserId
			end
		end
	end

	for _, hitInfo in ipairs(resolvedHits) do
		if hitInfo.Kind == HitResolver.ResultKind.Hazard and hitInfo.Hazard and hitInfo.Hazard.Root then
			if HazardRuntime.Destroy(hitInfo.Hazard.Root) then
				destroyedHazardCount += 1
			end
		end
	end

	return {
		Radius = radius,
		OriginPosition = centerPosition,
		KnockdownDuration = knockdownDuration,
		DestroyMinorHazards = true,
		DestroyedHazardCount = destroyedHazardCount,
		AffectedUserIds = affectedUserIds,
	}
end

local function applyOwnerLaunch(context, centerPosition, abilityConfig)
	local ownerLaunchRadius = math.max(0, tonumber(abilityConfig.Radius) or tonumber(abilityConfig.OwnerLaunchRadius) or 0)
	if ownerLaunchRadius <= 0 then
		return false
	end

	local player = context.Player
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	if not rootPart or not rootPart.Parent or not humanoid or humanoid.Health <= 0 then
		return false
	end

	local launchCenter = typeof(centerPosition) == "Vector3" and centerPosition or rootPart.Position
	if not doesCharacterOverlapDisplayedRadius(launchCenter, character, rootPart, ownerLaunchRadius) then
		return false
	end

	local planarOffset = Vector3.new(rootPart.Position.X - launchCenter.X, 0, rootPart.Position.Z - launchCenter.Z)
	local direction = getPlanarUnitOrFallback(planarOffset, rootPart.CFrame.LookVector)
	local launchHorizontal = math.max(0, tonumber(abilityConfig.OwnerLaunchHorizontal) or 0)
	local launchVertical = math.max(0, tonumber(abilityConfig.OwnerLaunchVertical) or 0)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	local inheritedHorizontalVelocity =
		Vector3.new(currentVelocity.X, 0, currentVelocity.Z) * OWNER_INHERITED_HORIZONTAL_VELOCITY_FACTOR
	local launchHorizontalVelocity = (direction * launchHorizontal) + inheritedHorizontalVelocity
	local launchVelocity = Vector3.new(
		launchHorizontalVelocity.X,
		math.max(currentVelocity.Y, 0) + launchVertical,
		launchHorizontalVelocity.Z
	)

	task.spawn(function()
		pcall(function()
			rootPart:SetNetworkOwner(nil)
		end)

		humanoid.Jump = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		applyLaunchVelocity(rootPart, launchVelocity)

		task.delay(OWNER_NETWORK_OWNER_RELEASE_DELAY, function()
			if not character.Parent or humanoid.Health <= 0 or not rootPart.Parent then
				return
			end

			if player and player.Parent then
				pcall(function()
					rootPart:SetNetworkOwner(player)
				end)
			end
		end)
	end)

	return true
end

local function placeLandMine(context, ownerKey)
	if ownerKey == nil then
		return {}, {
			ApplyCooldown = false,
			SuppressActivatedEvent = true,
		}
	end

	local radiusInfo = getScaledRadiusInfo(context.AbilityConfig, context.RootPart, context.Humanoid)
	local radius = radiusInfo.Radius
	local lifetime = math.max(0, tonumber(context.AbilityConfig.MineLifetime) or 0)
	local groundPosition = getMinePlacementPosition(context)
	local mineModel, originPosition = createLandMineModel(context.Player or context.Character, groundPosition, radius)
	local mineEntry = {
		Model = mineModel,
		GroundPosition = groundPosition,
		OriginPosition = originPosition,
		Radius = radius,
		BaseRadius = radiusInfo.BaseRadius,
		RadiusScaleSpeed = radiusInfo.Speed,
		RadiusScaleMultiplier = radiusInfo.Multiplier,
		PlacedAt = os.clock(),
	}

	activeMinesByPlayer[ownerKey] = mineEntry
	scheduleMineCleanup(ownerKey, mineEntry, lifetime)

	return {
		Action = LAND_MINE_ACTION_PLACED,
		Source = LAND_MINE_SOURCE,
		Radius = radius,
		BaseRadius = radiusInfo.BaseRadius,
		RadiusScaleSpeed = radiusInfo.Speed,
		RadiusScaleMultiplier = radiusInfo.Multiplier,
		MinePosition = groundPosition,
		OriginPosition = originPosition,
		MineLifetime = lifetime,
	}, {
		-- LandMine reserves cooldown only when the existing mine is detonated.
		ApplyCooldown = false,
	}
end

local function detonateLandMine(context, activeMine, ownerKey)
	if activeMine.PendingDetonation == true then
		return {}, {
			ApplyCooldown = false,
			SuppressActivatedEvent = true,
		}
	end

	activeMine.PendingDetonation = true

	local minePosition = activeMine.GroundPosition or activeMine.OriginPosition
	local originPosition = activeMine.OriginPosition or context.RootPart.Position
	local radius = math.max(0, tonumber(activeMine.Radius) or tonumber(context.AbilityConfig.Radius) or 0)
	local detonationSpeed = getEffectivePlanarSpeed(context.RootPart, context.Humanoid, context.AbilityConfig)
	local explosionAbilityConfig, directionalBlastInfo =
		buildExplosionAbilityConfig(context.AbilityConfig, radius, detonationSpeed)
	local explosionDelay = getDetonationExplosionDelay(context.AbilityConfig)
	if typeof(context.EmitEffect) == "function" then
		context.EmitEffect(LAND_MINE_SOURCE, {
			Action = LAND_MINE_ACTION_DETONATING,
			Source = LAND_MINE_SOURCE,
			Radius = radius,
			BaseRadius = activeMine.BaseRadius,
			RadiusScaleSpeed = activeMine.RadiusScaleSpeed,
			RadiusScaleMultiplier = activeMine.RadiusScaleMultiplier,
			DirectionalBlastSpeed = directionalBlastInfo.Speed,
			DirectionalBlastScaleMultiplier = directionalBlastInfo.Multiplier,
			MinePosition = minePosition,
			OriginPosition = originPosition,
			ExplosionDelay = explosionDelay,
		})
	end

	if explosionDelay > 0 then
		task.wait(explosionDelay)
	end

	if activeMinesByPlayer[ownerKey] == activeMine then
		clearActiveMine(ownerKey)
	elseif typeof(activeMine.Model) == "Instance" and activeMine.Model.Parent then
		activeMine.Model:Destroy()
	end

	local payload = buildExplosionPayload(context, originPosition, explosionAbilityConfig)
	payload.Action = LAND_MINE_ACTION_DETONATED
	payload.Source = LAND_MINE_SOURCE
	payload.MinePosition = minePosition
	payload.ExplosionDelay = explosionDelay
	payload.BaseRadius = activeMine.BaseRadius
	payload.RadiusScaleSpeed = activeMine.RadiusScaleSpeed
	payload.RadiusScaleMultiplier = activeMine.RadiusScaleMultiplier
	payload.DirectionalBlastSpeed = directionalBlastInfo.Speed
	payload.DirectionalBlastScaleMultiplier = directionalBlastInfo.Multiplier
	payload.OwnerLaunched = applyOwnerLaunch(
		context,
		minePosition or originPosition or context.RootPart.Position,
		explosionAbilityConfig
	)

	return payload, {
		ApplyCooldown = true,
	}
end

function BomuServer.LandMine(context)
	local ownerKey = getMineOwnerKey(context)
	local activeMine = getActiveMineEntry(ownerKey)
	if activeMine then
		return detonateLandMine(context, activeMine, ownerKey)
	end

	return placeLandMine(context, ownerKey)
end

function BomuServer.ClearRuntimeState(player)
	clearActiveMine(player)
end

return BomuServer
