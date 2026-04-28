local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local DevilFruitLogger = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local AffectableRegistry = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local HieAnimationController = require(script.Parent:WaitForChild("HieAnimationController"))
local HitResolver = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitResolver"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))

local HieHieNoMi = {}

local DEBUG = RunService:IsStudio()
local VERBOSE_DEBUG = false
local PROJECTILE_VERTICAL_OFFSET = 1.2
local DEFAULT_PROJECTILE_HAND_FORWARD_OFFSET = 2.5
local PROJECTILE_LIFETIME_GRACE = 0.1
local RESTORE_LOG_GRACE = 0.1
local VERBOSE_STEP_INTERVAL = 0.2
local MAX_IGNORED_HITS_PER_STEP = 12
local DEFAULT_MIN_AIM_DISTANCE = 6
local DEFAULT_TURN_THRESHOLD_DEGREES = 28
local TURN_TUNE_LOG_MARGIN_DEGREES = 5
local DEFAULT_MOVEMENT_INHERITANCE_FACTOR = 0.85
local DEFAULT_MAX_INHERITED_SPEED = 140
local DEFAULT_SPAWN_LEAD_TIME = 0.08
local DEFAULT_MAX_SPAWN_LEAD = 8
local DEFAULT_SHOTGUN_PROJECTILE_COUNT = 5
local DEFAULT_SHOTGUN_SPREAD_ANGLE = 12
local MAX_SHOTGUN_PROJECTILE_COUNT = 12
local DEFAULT_CAST_STARTUP_SPEED_MULTIPLIER = 0
local DEFAULT_CAST_STARTUP_SLOW_MAX_DURATION = 0.75
local DEFAULT_CAST_POST_LAUNCH_LOCK_DURATION = 0.35
local MIN_DIRECTION_MAGNITUDE = 0.01
local HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE = "HieFreezeShotCastSlowUntil"
local HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE = "HieFreezeShotCastSpeedMultiplier"
local HIE_ICE_BOOST_UNTIL_ATTRIBUTE = "HieIceBoostUntil"
local HIE_ICE_BOOST_SPEED_MULTIPLIER_ATTRIBUTE = "HieIceBoostSpeedMultiplier"
local HIE_ICE_BOOST_SPEED_BONUS_ATTRIBUTE = "HieIceBoostSpeedBonus"
local DEFAULT_ICE_BOOST_SPEED_MULTIPLIER = 2
local ICE_BOOST_DURATION_CLEANUP_BUFFER = 0.05

local IGNORED_HELPER_NAMES = {
	HitBox = true,
	ExtractionZone = true,
	RunHub = true,
	DecreaseSpeed = true,
}
local FREEZE_SHOT_ALLOWED_ENTITY_TYPES = {
	[AffectableRegistry.EntityType.Player] = true,
	[AffectableRegistry.EntityType.Hazard] = true,
}

local projectileSequence = 0
local restoreTokensByPlayer = setmetatable({}, { __mode = "k" })
local castSlowTokensByPlayer = setmetatable({}, { __mode = "k" })

local function logMessage(tag, message, ...)
	if not DEBUG then
		return
	end

	print(string.format("[HIE][%s] " .. message, tag, ...))
end

local function logVerbose(message, ...)
	if not (DEBUG and VERBOSE_DEBUG) then
		return
	end

	print(string.format("[HIE][STEP] " .. message, ...))
end

local function logError(message, ...)
	warn(string.format("[HIE][ERROR] " .. message, ...))
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstance(instance)
	if typeof(instance) ~= "Instance" then
		return tostring(instance)
	end

	return instance:GetFullName()
end

local function countPayloadKeys(payload)
	if typeof(payload) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(payload) do
		count += 1
	end

	return count
end

local function getForwardDirection(rootPart)
	local look = rootPart.CFrame.LookVector
	local planarLook = Vector3.new(look.X, 0, look.Z)
	if planarLook.Magnitude > 0.01 then
		return planarLook.Unit
	end

	if look.Magnitude > 0.01 then
		return look.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getFreezeShotGripPart(character)
	if typeof(character) ~= "Instance" then
		return nil
	end

	return character:FindFirstChild("RightHand")
		or character:FindFirstChild("RightLowerArm")
		or character:FindFirstChild("Right Arm")
end

local function getFreezeShotToolHandle(character)
	if typeof(character) ~= "Instance" then
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

local function getFreezeShotLaunchOrigin(context)
	local toolHandle = getFreezeShotToolHandle(context and context.Character)
	if toolHandle then
		local attachment = toolHandle:FindFirstChild("ToolGripAttachment")
			or toolHandle:FindFirstChild("GripAttachment")
		if attachment and attachment:IsA("Attachment") then
			return attachment.WorldPosition, attachment.Name
		end

		return toolHandle.Position, toolHandle.Name
	end

	local gripPart = getFreezeShotGripPart(context and context.Character)
	if gripPart and gripPart:IsA("BasePart") then
		local attachment = gripPart:FindFirstChild("RightGripAttachment")
			or gripPart:FindFirstChild("RightGrip")
		if attachment and attachment:IsA("Attachment") then
			return attachment.WorldPosition, "RightGripAttachment"
		end

		return gripPart.Position, gripPart.Name
	end

	return context.RootPart.Position + Vector3.new(0, PROJECTILE_VERTICAL_OFFSET, 0), "RootFallback"
end

local function resolveLaunchDirectionFromAim(originPosition, aimPosition, fallbackDirection, abilityConfig)
	if typeof(originPosition) ~= "Vector3" or typeof(aimPosition) ~= "Vector3" then
		return fallbackDirection
	end

	local sanitizedAimPosition = (abilityConfig ~= nil and abilityConfig.AllowVerticalAim == true)
		and aimPosition
		or Vector3.new(aimPosition.X, originPosition.Y, aimPosition.Z)
	local aimVector = sanitizedAimPosition - originPosition
	if aimVector.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return fallbackDirection
	end

	return aimVector.Unit
end

local function getShotgunBasis(direction)
	local forward = typeof(direction) == "Vector3" and direction.Magnitude > MIN_DIRECTION_MAGNITUDE
		and direction.Unit
		or Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	if right.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end

	local up = right:Cross(forward)
	if up.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		up = Vector3.yAxis
	else
		up = up.Unit
	end

	return forward, right, up
end

local function rotateDirectionAroundAxis(direction, axis, angleRadians)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector3.new(0, 0, -1)
	end

	if typeof(axis) ~= "Vector3" or axis.Magnitude <= MIN_DIRECTION_MAGNITUDE or math.abs(angleRadians) <= 0.0001 then
		return direction.Unit
	end

	return CFrame.fromAxisAngle(axis.Unit, angleRadians):VectorToWorldSpace(direction.Unit).Unit
end

local function getShotgunProjectileDirection(baseDirection, projectileIndex, projectileCount, spreadAngleDegrees)
	local forward, right = getShotgunBasis(baseDirection)
	if projectileCount <= 1 or projectileIndex <= 1 then
		return forward
	end

	local sideCount = math.max(1, projectileCount - 1)
	local sideIndex = projectileIndex - 2
	local ringAngle = (math.pi * 2) * (sideIndex / sideCount)
	local spreadRadians = math.rad(math.max(0, tonumber(spreadAngleDegrees) or 0))
	local yawRadians = math.cos(ringAngle) * spreadRadians
	local pitchRadians = math.sin(ringAngle) * spreadRadians * 0.45
	local rotatedDirection = rotateDirectionAroundAxis(forward, Vector3.yAxis, yawRadians)
	rotatedDirection = rotateDirectionAroundAxis(rotatedDirection, right, pitchRadians)

	if rotatedDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return forward
	end

	return rotatedDirection.Unit
end

local function getPlanarDirection(vector)
	if typeof(vector) ~= "Vector3" then
		return nil
	end

	local planarVector = Vector3.new(vector.X, 0, vector.Z)
	if planarVector.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil
	end

	return planarVector.Unit
end

local function getPlanarAngleDegrees(currentDirection, desiredDirection)
	local currentPlanar = getPlanarDirection(currentDirection)
	local desiredPlanar = getPlanarDirection(desiredDirection)
	if not currentPlanar or not desiredPlanar then
		return 0, currentPlanar, desiredPlanar, 1
	end

	local facingDot = math.clamp(currentPlanar:Dot(desiredPlanar), -1, 1)
	return math.deg(math.acos(facingDot)), currentPlanar, desiredPlanar, facingDot
end

local function isVerticalAimEnabled(abilityConfig)
	return abilityConfig ~= nil and abilityConfig.AllowVerticalAim == true
end

local function applyFreezeShotTurn(context, desiredDirection, abilityConfig)
	local thresholdDegrees = math.max(0, tonumber(abilityConfig.TurnThresholdDegrees) or DEFAULT_TURN_THRESHOLD_DEGREES)
	local angleDegrees, currentFacing, desiredFacing, facingDot = getPlanarAngleDegrees(
		context.RootPart.CFrame.LookVector,
		desiredDirection
	)

	currentFacing = currentFacing or getForwardDirection(context.RootPart)
	desiredFacing = desiredFacing or getForwardDirection(context.RootPart)

	logMessage(
		"TURN",
		"player=%s currentFacing=%s desiredFacing=%s angle=%.2f threshold=%.2f",
		context.Player.Name,
		formatVector3(currentFacing),
		formatVector3(desiredFacing),
		angleDegrees,
		thresholdDegrees
	)

	if math.abs(angleDegrees - thresholdDegrees) <= TURN_TUNE_LOG_MARGIN_DEGREES then
		logMessage(
			"TURN][TUNE",
			"player=%s angle=%.2f threshold=%.2f currentFacing=%s desiredFacing=%s nearThreshold=true predictedAction=%s",
			context.Player.Name,
			angleDegrees,
			thresholdDegrees,
			formatVector3(currentFacing),
			formatVector3(desiredFacing),
			angleDegrees < thresholdDegrees and "skip" or "apply"
		)
	end

	if angleDegrees < thresholdDegrees then
		logMessage(
			"TURN][SKIP",
			"player=%s currentFacing=%s desiredFacing=%s angle=%.2f threshold=%.2f rotate=false finalFacing=%s",
			context.Player.Name,
			formatVector3(currentFacing),
			formatVector3(desiredFacing),
			angleDegrees,
			thresholdDegrees,
			formatVector3(currentFacing)
		)
		return currentFacing, false, angleDegrees, facingDot
	end

	local characterPivot = context.Character:GetPivot()
	local pivotToRoot = characterPivot:ToObjectSpace(context.RootPart.CFrame)
	local rootPosition = context.RootPart.Position
	local targetRootCFrame = CFrame.lookAt(rootPosition, rootPosition + desiredFacing, Vector3.yAxis)
	local targetPivot = targetRootCFrame * pivotToRoot:Inverse()

	local ok, err = pcall(function()
		context.Character:PivotTo(targetPivot)
	end)
	if not ok then
		logError(
			"turn apply failed player=%s desiredFacing=%s angle=%.2f detail=%s",
			context.Player.Name,
			formatVector3(desiredFacing),
			angleDegrees,
			tostring(err)
		)
		logMessage(
			"TURN][SKIP",
			"player=%s currentFacing=%s desiredFacing=%s angle=%.2f threshold=%.2f rotate=false reason=pivot_failed finalFacing=%s",
			context.Player.Name,
			formatVector3(currentFacing),
			formatVector3(desiredFacing),
			angleDegrees,
			thresholdDegrees,
			formatVector3(currentFacing)
		)
		return currentFacing, false, angleDegrees, facingDot
	end

	local finalFacing = getPlanarDirection(context.RootPart.CFrame.LookVector) or desiredFacing
	logMessage(
		"TURN][APPLY",
		"player=%s currentFacing=%s desiredFacing=%s angle=%.2f threshold=%.2f rotate=true finalFacing=%s",
		context.Player.Name,
		formatVector3(currentFacing),
		formatVector3(desiredFacing),
		angleDegrees,
		thresholdDegrees,
		formatVector3(finalFacing)
	)
	return finalFacing, true, angleDegrees, facingDot
end

local function resolveFreezeShotDirection(context, baseOriginPosition, abilityConfig)
	local fallbackDirection = getForwardDirection(context.RootPart)
	local requestPayload = context.RequestPayload
	local rawAimPosition = type(requestPayload) == "table" and requestPayload.AimPosition or nil
	local verticalAimEnabled = isVerticalAimEnabled(abilityConfig)
	if typeof(rawAimPosition) ~= "Vector3" then
		logMessage(
			"WARN",
			"aim rejected reason=missing_aim player=%s origin=%s",
			context.Player.Name,
			formatVector3(baseOriginPosition)
		)
		logMessage(
			"AIM][FALLBACK",
			"player=%s reason=missing_aim origin=%s fallbackDirection=%s",
			context.Player.Name,
			formatVector3(baseOriginPosition),
			formatVector3(fallbackDirection)
		)
		return fallbackDirection, nil, false, true
	end

	logMessage(
		"AIM][SERVER",
		"rawAimPosition=%s verticalAimEnabled=%s player=%s",
		formatVector3(rawAimPosition),
		tostring(verticalAimEnabled),
		context.Player.Name
	)

	local sanitizedAimPosition = verticalAimEnabled
		and rawAimPosition
		or Vector3.new(rawAimPosition.X, baseOriginPosition.Y, rawAimPosition.Z)
	local rawAimVector = sanitizedAimPosition - baseOriginPosition
	local minAimDistance = math.max(0.5, tonumber(abilityConfig.MinimumAimDistance) or DEFAULT_MIN_AIM_DISTANCE)
	if rawAimVector.Magnitude < minAimDistance then
		logMessage(
			"WARN",
			"aim rejected reason=aim_too_close player=%s rawAimPosition=%s origin=%s minDistance=%.2f verticalAimEnabled=%s",
			context.Player.Name,
			formatVector3(rawAimPosition),
			formatVector3(baseOriginPosition),
			minAimDistance,
			tostring(verticalAimEnabled)
		)
		logMessage(
			"AIM][FALLBACK",
			"player=%s reason=aim_too_close aimPosition=%s origin=%s minDistance=%.2f fallbackDirection=%s",
			context.Player.Name,
			formatVector3(rawAimPosition),
			formatVector3(baseOriginPosition),
			minAimDistance,
			formatVector3(fallbackDirection)
		)
		return fallbackDirection, sanitizedAimPosition, false, true
	end

	local finalDirection = rawAimVector.Unit
	local forwardDot = fallbackDirection:Dot(finalDirection)

	local flattenedY = not verticalAimEnabled and math.abs(rawAimPosition.Y - sanitizedAimPosition.Y) > 0.001
	if flattenedY then
		logMessage(
			"AIM][FILTER",
			"player=%s reason=flatten_y rawAimPosition=%s chosenAimPosition=%s origin=%s",
			context.Player.Name,
			formatVector3(rawAimPosition),
			formatVector3(sanitizedAimPosition),
			formatVector3(baseOriginPosition)
		)
	end

	logMessage(
		"AIM][SERVER",
		"player=%s rawAimPosition=%s chosenAimPosition=%s origin=%s finalDirection3D=%s forwardDot=%.2f flattenedY=%s verticalAimEnabled=%s fallback=false",
		context.Player.Name,
		formatVector3(rawAimPosition),
		formatVector3(sanitizedAimPosition),
		formatVector3(baseOriginPosition),
		formatVector3(finalDirection),
		forwardDot,
		tostring(flattenedY),
		tostring(verticalAimEnabled)
	)
	return finalDirection, sanitizedAimPosition, flattenedY, false
end

local function nextProjectileId(player)
	projectileSequence += 1
	return string.format("%s:%d", tostring(player.UserId), projectileSequence)
end

local function getProjectileSettings(abilityConfig)
	local maxDistance = math.max(1, tonumber(abilityConfig.Range) or 0)
	local baseSpeed = math.max(1, tonumber(abilityConfig.ProjectileSpeed) or 0)
	local radius = math.max(0.25, tonumber(abilityConfig.ProjectileRadius) or 0.8)
	local burstRadius = math.max(0, tonumber(abilityConfig.ImpactBurstRadius) or 0)
	local freezeDuration = math.max(0, tonumber(abilityConfig.FreezeDuration) or 0)
	local shotgunProjectileCount = math.clamp(
		math.floor(
			tonumber(abilityConfig.ShotgunProjectileCount)
				or tonumber(abilityConfig.VisualBurstCount)
				or DEFAULT_SHOTGUN_PROJECTILE_COUNT
		),
		1,
		MAX_SHOTGUN_PROJECTILE_COUNT
	)

	return {
		MaxDistance = maxDistance,
		BaseSpeed = baseSpeed,
		Radius = radius,
		BurstRadius = burstRadius,
		FreezeDuration = freezeDuration,
		MovementInheritanceFactor = math.max(
			0,
			tonumber(abilityConfig.MovementInheritanceFactor) or DEFAULT_MOVEMENT_INHERITANCE_FACTOR
		),
		MaxInheritedSpeed = math.max(0, tonumber(abilityConfig.MaxInheritedSpeed) or DEFAULT_MAX_INHERITED_SPEED),
		SpawnLeadTime = math.max(0, tonumber(abilityConfig.SpawnLeadTime) or DEFAULT_SPAWN_LEAD_TIME),
		MaxSpawnLead = math.max(0, tonumber(abilityConfig.MaxSpawnLead) or DEFAULT_MAX_SPAWN_LEAD),
		LaunchForwardOffset = math.max(
			0,
			tonumber(abilityConfig.LaunchForwardOffset) or DEFAULT_PROJECTILE_HAND_FORWARD_OFFSET
		),
		ShotgunProjectileCount = shotgunProjectileCount,
		ShotgunSpreadAngle = math.max(
			0,
			tonumber(abilityConfig.ShotgunSpreadAngle)
				or tonumber(abilityConfig.VisualShotgunSpreadAngle)
				or DEFAULT_SHOTGUN_SPREAD_ANGLE
		),
	}
end

local function resolveFreezeShotVelocity(context, direction, settings)
	local rootVelocity = context.RootPart.AssemblyLinearVelocity
	local planarVelocity = Vector3.new(rootVelocity.X, 0, rootVelocity.Z)
	local inheritedSpeed = 0

	if planarVelocity.Magnitude > MIN_DIRECTION_MAGNITUDE then
		inheritedSpeed = math.max(0, planarVelocity:Dot(direction)) * settings.MovementInheritanceFactor
		inheritedSpeed = math.min(inheritedSpeed, settings.MaxInheritedSpeed)
	end

	local inheritedVelocity = direction * inheritedSpeed
	local finalVelocity = (direction * settings.BaseSpeed) + inheritedVelocity
	local finalSpeed = math.max(settings.BaseSpeed, finalVelocity.Magnitude)
	local spawnLeadDistance = math.min(inheritedSpeed * settings.SpawnLeadTime, settings.MaxSpawnLead)

	logMessage(
		"VELOCITY",
		"player=%s baseSpeed=%.2f casterVelocity=%s planarVelocity=%s inheritedVelocity=%s finalVelocity=%s finalSpeed=%.2f",
		context.Player.Name,
		settings.BaseSpeed,
		formatVector3(rootVelocity),
		formatVector3(planarVelocity),
		formatVector3(inheritedVelocity),
		formatVector3(finalVelocity),
		finalSpeed
	)

	return {
		RootVelocity = rootVelocity,
		PlanarVelocity = planarVelocity,
		InheritedVelocity = inheritedVelocity,
		InheritedSpeed = inheritedSpeed,
		FinalVelocity = finalVelocity,
		FinalSpeed = finalSpeed,
		SpawnLeadDistance = spawnLeadDistance,
	}
end

local function clearFreezeShotCastSlow(player, expectedToken)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	if expectedToken ~= nil and castSlowTokensByPlayer[player] ~= expectedToken then
		return
	end

	castSlowTokensByPlayer[player] = nil
	player:SetAttribute(HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE, nil)
	player:SetAttribute(HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE, nil)
end

local function clearIceBoostAttributes(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	player:SetAttribute(HIE_ICE_BOOST_UNTIL_ATTRIBUTE, nil)
	player:SetAttribute(HIE_ICE_BOOST_SPEED_MULTIPLIER_ATTRIBUTE, nil)
	player:SetAttribute(HIE_ICE_BOOST_SPEED_BONUS_ATTRIBUTE, nil)
end

local function clearIceBoostRuntimeState(player, reason)
	clearIceBoostAttributes(player)
	HieAnimationController.StopIceBoostAnimation(player, nil, reason or "runtime_clear")
end

local function stopPlanarVelocity(rootPart)
	if typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") then
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
end

local function applyFreezeShotCastSlow(context, abilityConfig)
	local player = context and context.Player
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local speedMultiplier = math.clamp(
		tonumber(abilityConfig and abilityConfig.CastStartupSpeedMultiplier) or DEFAULT_CAST_STARTUP_SPEED_MULTIPLIER,
		0,
		1
	)
	local maxDuration = math.max(
		0,
		tonumber(abilityConfig and abilityConfig.CastStartupSlowMaxDuration) or DEFAULT_CAST_STARTUP_SLOW_MAX_DURATION
	)
	local postLaunchLockDuration = math.max(
		0,
		tonumber(abilityConfig and abilityConfig.CastPostLaunchLockDuration) or DEFAULT_CAST_POST_LAUNCH_LOCK_DURATION
	)

	if speedMultiplier >= 1 or maxDuration <= 0 then
		return nil
	end

	local token = {}
	castSlowTokensByPlayer[player] = token
	player:SetAttribute(HIE_FREEZE_SHOT_CAST_SPEED_ATTRIBUTE, speedMultiplier)
	player:SetAttribute(HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE, os.clock() + maxDuration)
	stopPlanarVelocity(context.RootPart)

	logMessage(
		"CAST",
		"player=%s startupSlow=true multiplier=%.2f maxDuration=%.2f postLaunchLock=%.2f",
		player.Name,
		speedMultiplier,
		maxDuration,
		postLaunchLockDuration
	)

	task.delay(maxDuration + postLaunchLockDuration + 0.05, function()
		clearFreezeShotCastSlow(player, token)
	end)

	return function(delayDuration)
		local delaySeconds = math.max(0, tonumber(delayDuration) or 0)
		if delaySeconds <= 0 then
			clearFreezeShotCastSlow(player, token)
			return
		end

		if castSlowTokensByPlayer[player] ~= token then
			return
		end

		stopPlanarVelocity(context.RootPart)
		player:SetAttribute(HIE_FREEZE_SHOT_CAST_UNTIL_ATTRIBUTE, os.clock() + delaySeconds)
		task.delay(delaySeconds, function()
			clearFreezeShotCastSlow(player, token)
		end)
	end, postLaunchLockDuration
end

local function playFreezeShotAnimationAndWait(context, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	DevilFruitLogger.Info(
		"ANIM",
		"server animation begin fruit=%s ability=%s player=%s character=%s humanoid=%s root=%s",
		"Hie Hie no Mi",
		"FreezeShot",
		context.Player and context.Player.Name or "<nil>",
		tostring(context.Character ~= nil),
		tostring(context.Humanoid ~= nil),
		tostring(context.RootPart ~= nil)
	)
	local animationState = HieAnimationController.PlayFreezeShotAnimation(context.Character, animationConfig)
	if not animationState then
		DevilFruitLogger.Warn(
			"ANIM",
			"server animation unavailable fruit=%s ability=%s player=%s",
			"Hie Hie no Mi",
			"FreezeShot",
			context.Player and context.Player.Name or "<nil>"
		)
		return false
	end

	local clearCastSlow, postLaunchLockDuration = applyFreezeShotCastSlow(context, abilityConfig)
	local markerReached = HieAnimationController.WaitForFreezeShotRelease(animationState)
	if clearCastSlow then
		clearCastSlow(postLaunchLockDuration)
	end

	DevilFruitLogger.Info(
		"ANIM",
		"server animation release gate fruit=%s ability=%s player=%s markerReached=%s",
		"Hie Hie no Mi",
		"FreezeShot",
		context.Player and context.Player.Name or "<nil>",
		tostring(markerReached == true)
	)
	return markerReached
end

local function resolveProjectileStep(state, origin, displacement)
	local resolution = HitResolver.ResolveSegmentHit({
		QueryId = state.Id,
		StartPosition = origin,
		EndPosition = origin + displacement,
		QueryRadius = state.Radius,
		ExcludeInstances = { state.Character },
		IgnoredInstances = state.IgnoredInstances,
		IgnoredLookup = state.IgnoredLookup,
		AttackerPlayer = state.Player,
		AllowedEntityTypes = FREEZE_SHOT_ALLOWED_ENTITY_TYPES,
		RequireCanFreeze = true,
		IgnoreHelperNames = IGNORED_HELPER_NAMES,
		MaxIgnoredHits = MAX_IGNORED_HITS_PER_STEP,
		DebugEnabled = DEBUG,
		TracePrefix = "HIT",
	})

	if resolution.Status == "Hit" and resolution.Hit then
		logMessage(
			"ENTITY][SEGMENT",
			"projectileId=%s kind=%s label=%s reason=%s impact=%s",
			state.Id,
			tostring(resolution.Hit.Kind),
			tostring(resolution.Hit.Label),
			tostring(resolution.Hit.Reason),
			formatVector3(resolution.Hit.HitPosition)
		)
	elseif resolution.Status == HitResolver.ResultKind.NoHit then
		logVerbose(
			"projectileId=%s segment=no_hit origin=%s displacement=%s",
			state.Id,
			formatVector3(origin),
			formatVector3(displacement)
		)
	end

	return resolution
end

local function emitProjectileEffect(context, payload)
	local ok, result = pcall(function()
		return context.EmitEffect("FreezeShot", payload)
	end)
	if not ok then
		logError("effect emit failed player=%s projectileId=%s detail=%s", context.Player.Name, tostring(payload.ProjectileId), tostring(result))
		return false
	end

	return result == true
end

local function scheduleRestoreLog(targetPlayer, duration, projectileId)
	local token = (restoreTokensByPlayer[targetPlayer] or 0) + 1
	restoreTokensByPlayer[targetPlayer] = token

	task.delay(duration + RESTORE_LOG_GRACE, function()
		if restoreTokensByPlayer[targetPlayer] ~= token then
			return
		end

		local ok, activeEffect = pcall(function()
			return HitEffectService.GetActiveEffect(targetPlayer)
		end)
		if not ok then
			logError("restore check failed projectileId=%s target=%s detail=%s", tostring(projectileId), targetPlayer.Name, tostring(activeEffect))
			return
		end

		if activeEffect and activeEffect.EffectName == "Freeze" then
			logMessage(
				"RESTORE",
				"projectileId=%s target=%s restored=false activeEffect=%s until=%.2f",
				tostring(projectileId),
				targetPlayer.Name,
				tostring(activeEffect.EffectName),
				tonumber(activeEffect.UntilTime) or 0
			)
			return
		end

		logMessage(
			"RESTORE",
			"projectileId=%s target=%s restored=true duration=%.2f",
			tostring(projectileId),
			targetPlayer.Name,
			duration
		)
	end)
end

local function freezePlayer(state, hitInfo)
	if state.FreezeDuration <= 0 then
		logMessage("FREEZE_PLAYER", "projectileId=%s target=%s skipped duration=%.2f", state.Id, hitInfo.Player.Name, state.FreezeDuration)
		return false, "invalid_duration"
	end

	local applied, result = HitEffectService.ApplyEffect(hitInfo.Player, "Freeze", {
		Duration = state.FreezeDuration,
	})
	if not applied then
		logMessage(
			"FREEZE_PLAYER",
			"projectileId=%s target=%s applied=false reason=%s duration=%.2f",
			state.Id,
			hitInfo.Player.Name,
			tostring(result),
			state.FreezeDuration
		)
		return false, tostring(result)
	end

	local velocityOk, velocityError = pcall(function()
		hitInfo.RootPart.AssemblyLinearVelocity = Vector3.zero
		hitInfo.RootPart.AssemblyAngularVelocity = Vector3.zero
	end)
	if not velocityOk then
		logError("failed to zero target velocity projectileId=%s target=%s detail=%s", state.Id, hitInfo.Player.Name, tostring(velocityError))
	end

	logMessage(
		"FREEZE_PLAYER",
		"projectileId=%s target=%s duration=%.2f",
		state.Id,
		hitInfo.Player.Name,
		state.FreezeDuration
	)

	scheduleRestoreLog(hitInfo.Player, state.FreezeDuration, state.Id)
	return true, "ok"
end

local function freezeHazard(state, hitInfo)
	if state.FreezeDuration <= 0 then
		logMessage(
			"FREEZE_HAZARD",
			"projectileId=%s target=%s root=%s match=%s attempted=false applied=false duration=%.2f",
			state.Id,
			hitInfo.Label,
			formatInstance(hitInfo.Hazard and hitInfo.Hazard.Root or nil),
			tostring(hitInfo.MatchSource or hitInfo.Hazard and hitInfo.Hazard.MatchSource or "unknown"),
			state.FreezeDuration
		)
		return false, "invalid_duration"
	end

	local applied = HazardRuntime.Freeze(hitInfo.Hazard.Root, state.FreezeDuration) == true
	logMessage(
		"FREEZE_HAZARD",
		"projectileId=%s target=%s root=%s match=%s attempted=true applied=%s duration=%.2f",
		state.Id,
		hitInfo.Label,
		formatInstance(hitInfo.Hazard.Root),
		tostring(hitInfo.MatchSource or hitInfo.Hazard.MatchSource or "unknown"),
		tostring(applied),
		state.FreezeDuration
	)
	return applied, applied and "ok" or "freeze_rejected"
end

local function triggerImpactBurst(context, state, impactPosition, triggerKind, directHitInfo)
	if state.BurstRadius <= 0 then
		logMessage(
			"BURST][SKIP",
			"projectileId=%s trigger=%s reason=disabled impact=%s radius=%.2f",
			state.Id,
			tostring(triggerKind),
			formatVector3(impactPosition),
			state.BurstRadius
		)
		return {
			Triggered = false,
			Reason = "disabled",
		}
	end

	if typeof(impactPosition) ~= "Vector3" then
		logMessage(
			"BURST][SKIP",
			"projectileId=%s trigger=%s reason=invalid_impact impact=%s radius=%.2f",
			state.Id,
			tostring(triggerKind),
			formatVector3(impactPosition),
			state.BurstRadius
		)
		return {
			Triggered = false,
			Reason = "invalid_impact",
		}
	end

	logMessage(
		"BURST][TRIGGER",
		"projectileId=%s trigger=%s impact=%s radius=%.2f",
		state.Id,
		tostring(triggerKind),
		formatVector3(impactPosition),
		state.BurstRadius
	)
	logMessage(
		"ENTITY][BURST",
		"projectileId=%s action=query impact=%s radius=%.2f",
		state.Id,
		formatVector3(impactPosition),
		state.BurstRadius
	)

	local resolvedHits = HitResolver.ResolveRadiusHits({
		QueryId = string.format("%s:burst", state.Id),
		CenterPosition = impactPosition,
		Radius = state.BurstRadius,
		AttackerPlayer = state.Player,
		AllowedEntityTypes = FREEZE_SHOT_ALLOWED_ENTITY_TYPES,
		RequireCanFreeze = true,
		MaxMatches = 12,
		DebugEnabled = DEBUG,
		TracePrefix = "HIT",
	})

	local handledPlayers = {}
	local handledHazards = {}
	if directHitInfo then
		if directHitInfo.Kind == HitResolver.ResultKind.Player and directHitInfo.Player then
			handledPlayers[directHitInfo.Player] = "direct_hit"
		elseif directHitInfo.Kind == HitResolver.ResultKind.Hazard and directHitInfo.Hazard and directHitInfo.Hazard.Root then
			handledHazards[directHitInfo.Hazard.Root] = "direct_hit"
		end
	end

	local frozenPlayers = 0
	local frozenHazards = 0
	local skippedTargets = 0

	for _, burstHitInfo in ipairs(resolvedHits) do
		if burstHitInfo.Kind == HitResolver.ResultKind.Player and burstHitInfo.Player then
			local skipReason = handledPlayers[burstHitInfo.Player]
			if skipReason then
				skippedTargets += 1
				logMessage(
					"BURST][SKIP",
					"projectileId=%s kind=Player target=%s reason=%s",
					state.Id,
					burstHitInfo.Player.Name,
					tostring(skipReason)
				)
			else
				handledPlayers[burstHitInfo.Player] = "burst"
				local applied, applyReason = freezePlayer(state, burstHitInfo)
				if applied then
					frozenPlayers += 1
				else
					skippedTargets += 1
					logMessage(
						"BURST][SKIP",
						"projectileId=%s kind=Player target=%s reason=%s",
						state.Id,
						burstHitInfo.Player.Name,
						tostring(applyReason)
					)
				end
			end
		elseif burstHitInfo.Kind == HitResolver.ResultKind.Hazard and burstHitInfo.Hazard and burstHitInfo.Hazard.Root then
			local hazardRoot = burstHitInfo.Hazard.Root
			local skipReason = handledHazards[hazardRoot]
			if skipReason then
				skippedTargets += 1
				logMessage(
					"BURST][SKIP",
					"projectileId=%s kind=Hazard target=%s reason=%s",
					state.Id,
					formatInstance(hazardRoot),
					tostring(skipReason)
				)
			else
				handledHazards[hazardRoot] = "burst"
				local applied, applyReason = freezeHazard(state, burstHitInfo)
				if applied then
					frozenHazards += 1
				else
					skippedTargets += 1
					logMessage(
						"BURST][SKIP",
						"projectileId=%s kind=Hazard target=%s reason=%s",
						state.Id,
						formatInstance(hazardRoot),
						tostring(applyReason)
					)
				end
			end
		end
	end

	logMessage(
		"BURST][AOE",
		"projectileId=%s trigger=%s impact=%s radius=%.2f results=%d frozenPlayers=%d frozenHazards=%d skipped=%d",
		state.Id,
		tostring(triggerKind),
		formatVector3(impactPosition),
		state.BurstRadius,
		#resolvedHits,
		frozenPlayers,
		frozenHazards,
		skippedTargets
	)
	logMessage(
		"ENTITY][BURST",
		"projectileId=%s action=resolve results=%d frozenPlayers=%d frozenHazards=%d skipped=%d",
		state.Id,
		#resolvedHits,
		frozenPlayers,
		frozenHazards,
		skippedTargets
	)

	return {
		Triggered = true,
		Reason = "ok",
		Results = resolvedHits,
		FrozenPlayers = frozenPlayers,
		FrozenHazards = frozenHazards,
		SkippedTargets = skippedTargets,
	}
end

local function buildLaunchPayload(state)
	return {
		Phase = "Launch",
		ProjectileId = state.Id,
		StartedAt = state.ServerStartedAt,
		Direction = state.Direction,
		ProjectileVelocity = state.Velocity,
		InheritedVelocity = state.InheritedVelocity,
		BaseProjectileSpeed = state.BaseSpeed,
		ProjectileSpeed = state.Speed,
		ProjectileRadius = state.Radius,
		StartPosition = state.StartPosition,
		LaunchForwardOffset = state.LaunchForwardOffset,
		DisableVisualBurst = true,
		ShotgunIndex = state.ShotgunIndex,
		ShotgunCount = state.ShotgunCount,
		ShotgunGroupId = state.ShotgunGroupId,
		ShotgunOriginDirection = state.ShotgunOriginDirection,
		MaxDistance = state.MaxDistance,
		Range = state.MaxDistance,
		Lifetime = state.Lifetime,
		FreezeDuration = state.FreezeDuration,
	}
end

local function cleanupProjectile(state, reason)
	if state.CleanedUp then
		return
	end

	state.CleanedUp = true
	logMessage(
		"CLEANUP",
		"projectileId=%s reason=%s finalPos=%s distance=%.2f",
		state.Id,
		tostring(reason),
		formatVector3(state.Position),
		state.DistanceTraveled
	)
end

local function emitResolution(context, state, phase, hitKind, hitLabel, impactPosition, resolveReason)
	if phase == "Impact" then
		logMessage(
			"HIT",
			"projectileId=%s impact=%s kind=%s label=%s reason=%s",
			state.Id,
			formatVector3(impactPosition),
			tostring(hitKind),
			tostring(hitLabel),
			tostring(resolveReason)
		)
	end

	logMessage(
		"RESOLVE",
		"projectileId=%s phase=%s kind=%s label=%s reason=%s impact=%s distance=%.2f",
		state.Id,
		tostring(phase),
		tostring(hitKind),
		tostring(hitLabel),
		tostring(resolveReason),
		formatVector3(impactPosition),
		state.DistanceTraveled
	)
	emitProjectileEffect(context, {
		Phase = phase,
		ProjectileId = state.Id,
		ResolvedAt = Workspace:GetServerTimeNow(),
		ImpactPosition = impactPosition,
		TravelDistance = state.DistanceTraveled,
		HitKind = hitKind,
		HitLabel = hitLabel,
		ResolveReason = resolveReason,
	})
end

local function simulateProjectile(context, state)
	logMessage(
		"PROJECTILE",
		"projectileId=%s init speed=%.2f maxDistance=%.2f radius=%.2f lifetime=%.2f",
		state.Id,
		state.Speed,
		state.MaxDistance,
		state.Radius,
		state.Lifetime
	)
	logMessage(
		"MOVE",
		"projectileId=%s origin=%s start=%s velocity=%s direction=%s speed=%.2f",
		state.Id,
		formatVector3(state.OriginPosition),
		formatVector3(state.StartPosition),
		formatVector3(state.Velocity),
		formatVector3(state.Direction),
		state.Speed
	)

	local startedAt = os.clock()

	while not state.CleanedUp do
		local dt = RunService.Heartbeat:Wait()
		if state.CleanedUp then
			break
		end

		local elapsed = os.clock() - startedAt
		if elapsed >= state.Lifetime or state.DistanceTraveled >= state.MaxDistance then
			logMessage(
				"BURST][SKIP",
				"projectileId=%s reason=no_impact impact=%s radius=%.2f",
				state.Id,
				formatVector3(state.Position),
				state.BurstRadius
			)
			logMessage(
				"EXPIRE",
				"projectileId=%s player=%s reason=max_range distance=%.2f pos=%s",
				state.Id,
				context.Player.Name,
				state.DistanceTraveled,
				formatVector3(state.Position)
			)
			emitResolution(context, state, "Expire", "Expire", "NoHit", state.Position, "max_range")
			cleanupProjectile(state, "expire:max_range")
			return
		end

		local stepDistance = math.min(state.Speed * dt, state.MaxDistance - state.DistanceTraveled)
		if stepDistance <= 0 then
			continue
		end

		local displacement = state.Direction * stepDistance
		local stepResolution = resolveProjectileStep(state, state.Position, displacement)
		if stepResolution.Status == HitResolver.ResultKind.Fail then
			local failureReason = tostring(stepResolution.Reason or HitResolver.Reasons.MissingClassification)
			logMessage(
				"BURST][SKIP",
				"projectileId=%s reason=%s impact=%s radius=%.2f",
				state.Id,
				failureReason,
				formatVector3(state.Position),
				state.BurstRadius
			)
			emitResolution(
				context,
				state,
				"Impact",
				"Fail",
				tostring(stepResolution.Hit and stepResolution.Hit.Label or "classification_fail"),
				state.Position,
				failureReason
			)
			cleanupProjectile(state, string.format("classify_fail:%s", failureReason))
			return
		end

		if stepResolution.Status == HitResolver.ResultKind.NoHit then
			state.Position += displacement
			state.DistanceTraveled += stepDistance
			if VERBOSE_DEBUG and elapsed >= state.NextVerboseLogAt then
				state.NextVerboseLogAt = elapsed + VERBOSE_STEP_INTERVAL
				logMessage(
					"MOVE",
					"projectileId=%s elapsed=%.2f distance=%.2f pos=%s velocity=%s",
					state.Id,
					elapsed,
					state.DistanceTraveled,
					formatVector3(state.Position),
					formatVector3(state.Velocity)
				)
			end
			continue
		end

		local result = stepResolution.CastResult
		local hitInfo = stepResolution.Hit

		local hitDistance = math.min(stepDistance, (result.Position - state.Position).Magnitude)
		state.Position = result.Position
		state.DistanceTraveled += hitDistance

		if not hitInfo then
			emitResolution(
				context,
				state,
				"Impact",
				"Fail",
				"missing_classification",
				state.Position,
				HitResolver.Reasons.MissingClassification
			)
			cleanupProjectile(state, string.format("classify_fail:%s", HitResolver.Reasons.MissingClassification))
			return
		end

		if hitInfo.Kind == HitResolver.ResultKind.Player then
			logMessage(
				"HIT][PLAYER",
				"projectileId=%s hit=%s continue=false distance=%.2f tick=%.2f",
				state.Id,
				hitInfo.Label,
				state.DistanceTraveled,
				Workspace:GetServerTimeNow()
			)
			local applied, applyReason = freezePlayer(state, hitInfo)
			triggerImpactBurst(context, state, state.Position, HitResolver.ResultKind.Player, hitInfo)
			if applied then
				emitResolution(context, state, "Impact", "Player", hitInfo.Label, state.Position, applyReason)
				cleanupProjectile(state, "player_hit:ok")
			else
				logMessage(
					"CLASSIFY][FAIL",
					"projectileId=%s kind=Player target=%s reason=%s final=PlayerRejected",
					state.Id,
					hitInfo.Label,
					tostring(applyReason)
				)
				emitResolution(context, state, "Impact", "PlayerRejected", hitInfo.Label, state.Position, applyReason)
				cleanupProjectile(state, string.format("player_rejected:%s", tostring(applyReason)))
			end
			return
		end

		if hitInfo.Kind == HitResolver.ResultKind.Hazard then
			logMessage(
				"HIT][HAZARD",
				"projectileId=%s hit=%s continue=false distance=%.2f tick=%.2f",
				state.Id,
				hitInfo.Label,
				state.DistanceTraveled,
				Workspace:GetServerTimeNow()
			)
			local applied, applyReason = freezeHazard(state, hitInfo)
			triggerImpactBurst(context, state, state.Position, HitResolver.ResultKind.Hazard, hitInfo)
			if applied then
				emitResolution(context, state, "Impact", "Hazard", hitInfo.Label, state.Position, applyReason)
				cleanupProjectile(state, "hazard_hit:ok")
			else
				logMessage(
					"CLASSIFY][FAIL",
					"projectileId=%s kind=Hazard target=%s reason=%s final=HazardRejected",
					state.Id,
					hitInfo.Label,
					tostring(applyReason)
				)
				emitResolution(context, state, "Impact", "HazardRejected", hitInfo.Label, state.Position, applyReason)
				cleanupProjectile(state, string.format("hazard_rejected:%s", tostring(applyReason)))
			end
			return
		end

		if hitInfo.Kind == HitResolver.ResultKind.Fail then
			logMessage(
				"BURST][SKIP",
				"projectileId=%s reason=%s impact=%s radius=%.2f",
				state.Id,
				tostring(hitInfo.Reason),
				formatVector3(state.Position),
				state.BurstRadius
			)
			emitResolution(context, state, "Impact", "Fail", hitInfo.Label, state.Position, hitInfo.Reason)
			cleanupProjectile(state, string.format("classify_fail:%s", tostring(hitInfo.Reason)))
			return
		end

		logMessage(
			"HIT][BLOCK",
			"projectileId=%s hit=%s classification=%s continue=false distance=%.2f tick=%.2f",
			state.Id,
			hitInfo.Label,
			tostring(hitInfo.Reason),
			state.DistanceTraveled,
			Workspace:GetServerTimeNow()
		)
		triggerImpactBurst(context, state, state.Position, HitResolver.ResultKind.Block, nil)
		emitResolution(context, state, "Impact", "Block", hitInfo.Label, state.Position, hitInfo.Reason)
		cleanupProjectile(state, string.format("blocked:%s", tostring(hitInfo.Reason)))
		return
	end
end

local function createFreezeShotProjectileState(
	context,
	settings,
	originPosition,
	startPosition,
	originDirection,
	projectileDirection,
	velocityData,
	shotgunIndex,
	shotgunCount,
	shotgunGroupId,
	spawnLeadDistance
)
	local projectileId = nextProjectileId(context.Player)
	local lifetime = (settings.MaxDistance / velocityData.FinalSpeed) + PROJECTILE_LIFETIME_GRACE

	return {
		Id = projectileId,
		Player = context.Player,
		Character = context.Character,
		HazardsFolder = HazardRuntime.GetSharedHazardsFolder(),
		OriginPosition = originPosition,
		StartPosition = startPosition,
		Position = startPosition,
		LaunchForwardOffset = settings.LaunchForwardOffset,
		Direction = projectileDirection,
		ShotgunOriginDirection = originDirection,
		Velocity = velocityData.FinalVelocity,
		InheritedVelocity = velocityData.InheritedVelocity,
		BaseSpeed = settings.BaseSpeed,
		Speed = velocityData.FinalSpeed,
		Radius = settings.Radius,
		BurstRadius = settings.BurstRadius,
		MaxDistance = settings.MaxDistance,
		FreezeDuration = settings.FreezeDuration,
		Lifetime = lifetime,
		ServerStartedAt = Workspace:GetServerTimeNow(),
		DistanceTraveled = 0,
		CleanedUp = false,
		IgnoredInstances = {},
		IgnoredLookup = {},
		SpawnLeadDistance = spawnLeadDistance,
		ShotgunIndex = shotgunIndex,
		ShotgunCount = shotgunCount,
		ShotgunGroupId = shotgunGroupId,
		NextVerboseLogAt = 0,
	}
end

local function startProjectileSimulation(context, state)
	task.defer(function()
		local ok, err = pcall(simulateProjectile, context, state)
		if not ok then
			logError("projectile simulation crashed projectileId=%s player=%s detail=%s", state.Id, context.Player.Name, tostring(err))
			emitResolution(context, state, "Expire", "Fail", "simulation_error", state.Position, "simulation_error")
			cleanupProjectile(state, "error:simulation")
		end
	end)
end

function HieHieNoMi.FreezeShot(context)
	local abilityConfig = context.AbilityConfig
	local humanoid = context.Humanoid
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")) or nil
	local settings = getProjectileSettings(abilityConfig)
	local slotLabel = tostring(abilityConfig.KeyCode or "Q")
	local aimOriginPosition = context.RootPart.Position + Vector3.new(0, PROJECTILE_VERTICAL_OFFSET, 0)
	local direction, aimPosition = resolveFreezeShotDirection(context, aimOriginPosition, abilityConfig)
	local finalFacing = applyFreezeShotTurn(context, direction, abilityConfig)
	DevilFruitLogger.Info(
		"MOVE",
		"handler enter fruit=%s ability=%s player=%s character=%s humanoid=%s root=%s animator=%s payloadKeys=%d aim=%s direction=%s",
		"Hie Hie no Mi",
		"FreezeShot",
		context.Player and context.Player.Name or "<nil>",
		tostring(context.Character ~= nil),
		tostring(humanoid ~= nil),
		tostring(context.RootPart ~= nil),
		tostring(animator ~= nil),
		countPayloadKeys(context.RequestPayload),
		formatVector3(aimPosition),
		formatVector3(direction)
	)

	playFreezeShotAnimationAndWait(context, abilityConfig)

	local originPosition, launchSource = getFreezeShotLaunchOrigin(context)
	direction = resolveLaunchDirectionFromAim(originPosition, aimPosition, direction, abilityConfig)
	local launchVelocityData = resolveFreezeShotVelocity(context, direction, settings)
	local sharedStartPosition = originPosition + direction * (settings.LaunchForwardOffset + launchVelocityData.SpawnLeadDistance)
	local shotgunGroupId = string.format("%s:shotgun:%d", tostring(context.Player.UserId), projectileSequence + 1)
	local projectileStates = {}

	for shotgunIndex = 1, settings.ShotgunProjectileCount do
		local projectileDirection = getShotgunProjectileDirection(
			direction,
			shotgunIndex,
			settings.ShotgunProjectileCount,
			settings.ShotgunSpreadAngle
		)
		local velocityData = shotgunIndex == 1
			and launchVelocityData
			or resolveFreezeShotVelocity(context, projectileDirection, settings)
		local state = createFreezeShotProjectileState(
			context,
			settings,
			originPosition,
			sharedStartPosition,
			direction,
			projectileDirection,
			velocityData,
			shotgunIndex,
			settings.ShotgunProjectileCount,
			shotgunGroupId,
			launchVelocityData.SpawnLeadDistance
		)
		projectileStates[#projectileStates + 1] = state

		logMessage(
			"SPAWN",
			"player=%s projectileId=%s shotgun=%d/%d origin=%s start=%s source=%s baseOffset=%.2f spawnLead=%.2f",
			context.Player.Name,
			state.Id,
			shotgunIndex,
			settings.ShotgunProjectileCount,
			formatVector3(originPosition),
			formatVector3(state.StartPosition),
			tostring(launchSource),
			settings.LaunchForwardOffset,
			launchVelocityData.SpawnLeadDistance
		)

		logMessage(
			"FIRE",
			"player=%s ability=%s slot=%s shotgun=%d/%d origin=%s aimPosition=%s direction=%s finalFacing=%s velocity=%s",
			context.Player.Name,
			context.AbilityName,
			slotLabel,
			shotgunIndex,
			settings.ShotgunProjectileCount,
			formatVector3(originPosition),
			formatVector3(aimPosition),
			formatVector3(projectileDirection),
			formatVector3(finalFacing),
			formatVector3(velocityData.FinalVelocity)
		)
	end

	task.defer(function()
		for index = 2, #projectileStates do
			emitProjectileEffect(context, buildLaunchPayload(projectileStates[index]))
		end

		for _, state in ipairs(projectileStates) do
			startProjectileSimulation(context, state)
		end
	end)

	return buildLaunchPayload(projectileStates[1])
end

function HieHieNoMi.IceBoost(context)
	local player = context.Player
	local abilityConfig = context.AbilityConfig
	local humanoid = context.Humanoid
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")) or nil
	local duration = math.max(0, tonumber(abilityConfig.Duration) or 0)
	local speedMultiplier = math.max(1, tonumber(abilityConfig.SpeedMultiplier) or DEFAULT_ICE_BOOST_SPEED_MULTIPLIER)
	local untilTime = os.clock() + duration
	DevilFruitLogger.Info(
		"MOVE",
		"handler enter fruit=%s ability=%s player=%s character=%s humanoid=%s root=%s animator=%s payloadKeys=%d duration=%.2f speedMultiplier=%.2f",
		"Hie Hie no Mi",
		"IceBoost",
		player and player.Name or "<nil>",
		tostring(context.Character ~= nil),
		tostring(humanoid ~= nil),
		tostring(context.RootPart ~= nil),
		tostring(animator ~= nil),
		countPayloadKeys(context.RequestPayload),
		duration,
		speedMultiplier
	)

	player:SetAttribute(HIE_ICE_BOOST_UNTIL_ATTRIBUTE, untilTime)
	player:SetAttribute(HIE_ICE_BOOST_SPEED_MULTIPLIER_ATTRIBUTE, speedMultiplier)
	player:SetAttribute(HIE_ICE_BOOST_SPEED_BONUS_ATTRIBUTE, nil)
	HieAnimationController.PlayIceBoostAnimation(player, context.Character, abilityConfig.Animation, untilTime)

	task.delay(duration + ICE_BOOST_DURATION_CLEANUP_BUFFER, function()
		if player.Parent == nil then
			HieAnimationController.StopIceBoostAnimation(player, untilTime, "player_removed")
			return
		end

		local currentUntil = player:GetAttribute(HIE_ICE_BOOST_UNTIL_ATTRIBUTE)
		if currentUntil == untilTime then
			clearIceBoostAttributes(player)
			HieAnimationController.StopIceBoostAnimation(player, untilTime, "duration_complete")
		elseif typeof(currentUntil) ~= "number" or currentUntil < untilTime then
			HieAnimationController.StopIceBoostAnimation(player, untilTime, "interrupted")
		end
	end)

	return {
		Duration = duration,
		SpeedMultiplier = speedMultiplier,
	}
end

function HieHieNoMi.ClearRuntimeState(player)
	clearFreezeShotCastSlow(player)
	clearIceBoostRuntimeState(player, "runtime_clear")
end

logMessage("INIT", "Freeze Shot runtime initialized")

return HieHieNoMi
