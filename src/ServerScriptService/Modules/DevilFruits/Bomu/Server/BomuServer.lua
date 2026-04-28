local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local HitResolver = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitResolver"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))

local BomuServer = {}

local activeMinesByPlayer = {}

local EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local LAND_MINE_MODEL_NAME = "BomuLandMine"
local LAND_MINE_ACTION_PLACED = "Placed"
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

local function getPlayerCharacterContext(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil, nil
	end

	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return character, nil, nil
	end

	return character, humanoid, rootPart
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

local function createLandMineModel(player, groundPosition, radius)
	local model = Instance.new("Model")
	model.Name = string.format("%s_%d", LAND_MINE_MODEL_NAME, player.UserId)
	model:SetAttribute("FruitKey", "Bomu")
	model:SetAttribute("OwnerUserId", player.UserId)

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
		if activeMinesByPlayer[player] == mineEntry then
			clearActiveMine(player)
		end
	end)
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
	local resolvedHits = HitResolver.ResolveRadiusHits({
		QueryId = string.format("bomu:%d:%d", context.Player.UserId, math.floor(os.clock() * 1000)),
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

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer == context.Player then
			continue
		end

		local character, _, rootPart = getPlayerCharacterContext(targetPlayer)
		if not character or not rootPart then
			continue
		end

		if not doesCharacterOverlapDisplayedRadius(centerPosition, character, rootPart, radius) then
			continue
		end

		local knockbackVector = getKnockbackVector(centerPosition, rootPart, fallbackDirection, abilityConfig)
		local applied = HitEffectService.ApplyEffect(targetPlayer, "Knockdown", {
			Duration = knockdownDuration,
			DropPosition = rootPart.Position,
			KnockbackVector = knockbackVector,
		})
		if applied then
			affectedUserIds[#affectedUserIds + 1] = targetPlayer.UserId
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

local function placeLandMine(context)
	local radius = math.max(0, tonumber(context.AbilityConfig.Radius) or 0)
	local lifetime = math.max(0, tonumber(context.AbilityConfig.MineLifetime) or 0)
	local groundPosition = getMinePlacementPosition(context)
	local mineModel, originPosition = createLandMineModel(context.Player, groundPosition, radius)
	local mineEntry = {
		Model = mineModel,
		GroundPosition = groundPosition,
		OriginPosition = originPosition,
		PlacedAt = os.clock(),
	}

	activeMinesByPlayer[context.Player] = mineEntry
	scheduleMineCleanup(context.Player, mineEntry, lifetime)

	return {
		Action = LAND_MINE_ACTION_PLACED,
		Source = LAND_MINE_SOURCE,
		Radius = radius,
		MinePosition = groundPosition,
		OriginPosition = originPosition,
		MineLifetime = lifetime,
	}, {
		-- LandMine reserves cooldown only when the existing mine is detonated.
		ApplyCooldown = false,
	}
end

local function detonateLandMine(context, activeMine)
	clearActiveMine(context.Player)

	local payload = buildExplosionPayload(context, activeMine.OriginPosition or context.RootPart.Position, context.AbilityConfig)
	payload.Action = LAND_MINE_ACTION_DETONATED
	payload.Source = LAND_MINE_SOURCE
	payload.MinePosition = activeMine.GroundPosition or activeMine.OriginPosition
	payload.OwnerLaunched = applyOwnerLaunch(
		context,
		activeMine.GroundPosition or activeMine.OriginPosition or context.RootPart.Position,
		context.AbilityConfig
	)

	return payload, {
		ApplyCooldown = true,
	}
end

function BomuServer.LandMine(context)
	local activeMine = getActiveMineEntry(context.Player)
	if activeMine then
		return detonateLandMine(context, activeMine)
	end

	return placeLandMine(context)
end

function BomuServer.ClearRuntimeState(player)
	clearActiveMine(player)
end

return BomuServer
