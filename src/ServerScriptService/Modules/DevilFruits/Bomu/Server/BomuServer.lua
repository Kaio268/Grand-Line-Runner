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
local GROUND_CAST_HEIGHT = 4
local GROUND_CAST_DISTANCE = 18
local MINE_BODY_HEIGHT = 0.34
local OWNER_NETWORK_OWNER_RELEASE_DELAY = 0.35

local function getPlanarUnitOrFallback(vector, fallback)
	local planarVector = Vector3.new(vector.X, 0, vector.Z)
	if planarVector.Magnitude > 0.01 then
		return planarVector.Unit
	end

	if typeof(fallback) == "Vector3" and fallback.Magnitude > 0.01 then
		local planarFallback = Vector3.new(fallback.X, 0, fallback.Z)
		if planarFallback.Magnitude > 0.01 then
			return planarFallback.Unit
		end
	end

	return Vector3.new(0, 0, -1)
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

	local indicatorPosition = groundPosition + Vector3.new(0, 0.03, 0)
	createDisplayPart(
		model,
		"RadiusIndicator",
		Vector3.new(0.08, radius * 2, radius * 2),
		Color3.fromRGB(255, 64, 64),
		CFrame.new(indicatorPosition) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.PartType.Cylinder,
		Enum.Material.Neon,
		0.72
	)
	createDisplayPart(
		model,
		"RadiusCore",
		Vector3.new(0.04, radius * 1.2, radius * 1.2),
		Color3.fromRGB(255, 110, 92),
		CFrame.new(indicatorPosition + Vector3.new(0, 0.01, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.PartType.Cylinder,
		Enum.Material.Neon,
		0.82
	)

	local bodyPosition = groundPosition + Vector3.new(0, MINE_BODY_HEIGHT, 0)
	local body = createDisplayPart(
		model,
		"Body",
		Vector3.new(1.15, 0.48, 1.15),
		Color3.fromRGB(38, 36, 36),
		CFrame.new(bodyPosition),
		Enum.PartType.Cylinder,
		Enum.Material.Metal,
		0
	)
	body.Orientation = Vector3.new(90, 0, 0)

	createDisplayPart(
		model,
		"Cap",
		Vector3.new(0.58, 0.2, 0.58),
		Color3.fromRGB(198, 44, 44),
		CFrame.new(bodyPosition + Vector3.new(0, 0.18, 0)),
		Enum.PartType.Cylinder,
		Enum.Material.SmoothPlastic,
		0
	).Orientation = Vector3.new(90, 0, 0)

	createDisplayPart(
		model,
		"Beacon",
		Vector3.new(0.24, 0.24, 0.24),
		Color3.fromRGB(255, 82, 82),
		CFrame.new(bodyPosition + Vector3.new(0, 0.34, 0)),
		Enum.PartType.Ball,
		Enum.Material.Neon,
		0.08
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
		return result.Position + (result.Normal * 0.02)
	end

	local fallbackHeight = math.max((humanoid.HipHeight or 2) + 2.5, 4)
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
		AttackerPlayer = context.Player,
		IncludePlayers = true,
		IncludeHazards = true,
		AllowedHazardClasses = {
			minor = true,
		},
		PlayerRootPosition = centerPosition,
		MaxPlayerDistance = radius + 8,
		MaxHazardTargets = 8,
		TracePrefix = "HIT",
	})

	for _, hitInfo in ipairs(resolvedHits) do
		if hitInfo.Kind == HitResolver.ResultKind.Player and hitInfo.Player and hitInfo.RootPart then
			local knockbackVector = getKnockbackVector(centerPosition, hitInfo.RootPart, fallbackDirection, abilityConfig)
			local applied = HitEffectService.ApplyEffect(hitInfo.Player, "Knockdown", {
				Duration = knockdownDuration,
				DropPosition = hitInfo.RootPart.Position,
				KnockbackVector = knockbackVector,
			})
			if applied then
				affectedUserIds[#affectedUserIds + 1] = hitInfo.Player.UserId
			end
		elseif hitInfo.Kind == HitResolver.ResultKind.Hazard and hitInfo.Hazard and hitInfo.Hazard.Root then
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
	local ownerLaunchRadius = math.max(0, tonumber(abilityConfig.OwnerLaunchRadius) or 0)
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
	local planarOffset = Vector3.new(rootPart.Position.X - launchCenter.X, 0, rootPart.Position.Z - launchCenter.Z)
	if planarOffset.Magnitude > ownerLaunchRadius then
		return false
	end

	local direction = getPlanarUnitOrFallback(planarOffset, rootPart.CFrame.LookVector)
	local launchHorizontal = math.max(0, tonumber(abilityConfig.OwnerLaunchHorizontal) or 0)
	local launchVertical = math.max(0, tonumber(abilityConfig.OwnerLaunchVertical) or 0)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	local inheritedHorizontalVelocity = Vector3.new(currentVelocity.X, 0, currentVelocity.Z) * 0.18
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

function BomuServer.LandMine(context)
	local activeMine = getActiveMineEntry(context.Player)
	if activeMine then
		clearActiveMine(context.Player)

		local payload = buildExplosionPayload(context, activeMine.OriginPosition or context.RootPart.Position, context.AbilityConfig)
		payload.Action = "Detonated"
		payload.Source = "LandMine"
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
		Action = "Placed",
		Source = "LandMine",
		Radius = radius,
		MinePosition = groundPosition,
		OriginPosition = originPosition,
		MineLifetime = lifetime,
	}, {
		ApplyCooldown = false,
	}
end

function BomuServer.ClearRuntimeState(player)
	clearActiveMine(player)
end

return BomuServer
