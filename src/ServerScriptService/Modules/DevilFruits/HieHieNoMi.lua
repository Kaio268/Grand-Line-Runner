local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local AffectableRegistry = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local HitResolver = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitResolver"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))

local HieHieNoMi = {}
local iceBlastAnimation = "rbxassetid://112900668980719"
local iceBoostAnimation = "rbxassetid://84130968608346"

local lastSpawnInfo = {}
local TRAIL_DISTANCE_THRESHOLD = 2.2
local TRAIL_TIME_THRESHOLD = 0.1

local function playIceBlastAnimation(humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = iceBlastAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	return track
end

local function playIceBoostAnimation(humanoid, duration)
	local animation = Instance.new("Animation")
	animation.AnimationId = iceBoostAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action

	local moveConnection
	moveConnection = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		if humanoid.MoveDirection.Magnitude > 0 then
			if not track.IsPlaying then
				track:Play()
			end
		else
			if track.IsPlaying then
				track:Stop()
			end
		end
	end)

	if humanoid.MoveDirection.Magnitude > 0 then
		track:Play()
	end

	task.delay(duration, function()
		if moveConnection then
			moveConnection:Disconnect()
		end
		if track then
			track:Stop()
			track:Destroy()
		end
	end)

	return track
end



local DEBUG = RunService:IsStudio()
local VERBOSE_DEBUG = false
local PROJECTILE_FORWARD_OFFSET = 3
local PROJECTILE_VERTICAL_OFFSET = 1.2
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
local MIN_DIRECTION_MAGNITUDE = 0.01

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
	if typeof(rawAimPosition) ~= "Vector3" then
		logMessage(
			"AIM][FALLBACK",
			"player=%s reason=missing_aim origin=%s fallbackDirection=%s",
			context.Player.Name,
			formatVector3(baseOriginPosition),
			formatVector3(fallbackDirection)
		)
		return fallbackDirection, nil, false, true
	end

	local sanitizedAimPosition = Vector3.new(rawAimPosition.X, baseOriginPosition.Y, rawAimPosition.Z)
	local rawAimVector = sanitizedAimPosition - baseOriginPosition
	local minAimDistance = math.max(0.5, tonumber(abilityConfig.MinimumAimDistance) or DEFAULT_MIN_AIM_DISTANCE)
	if rawAimVector.Magnitude < minAimDistance then
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

	local planarDirection = rawAimVector.Unit
	local forwardDot = fallbackDirection:Dot(planarDirection)

	local flattenedY = math.abs(rawAimPosition.Y - sanitizedAimPosition.Y) > 0.001
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
		"player=%s rawAimPosition=%s chosenAimPosition=%s origin=%s finalDirection=%s forwardDot=%.2f flattenedY=%s fallback=false",
		context.Player.Name,
		formatVector3(rawAimPosition),
		formatVector3(sanitizedAimPosition),
		formatVector3(baseOriginPosition),
		formatVector3(planarDirection),
		forwardDot,
		tostring(flattenedY)
	)
	return planarDirection, sanitizedAimPosition, flattenedY, false
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

function HieHieNoMi.FreezeShot(context)
	local humanoid = context.Humanoid
	local track = playIceBlastAnimation(humanoid)
	local abilityConfig = context.AbilityConfig

	-- Align projectile release with Eric's animation marker when present.
	local startTime = os.clock()
	local markerReached = false
	local markerConnection = track:GetMarkerReachedSignal("IceBlast"):Connect(function()
		markerReached = true
	end)

	while not markerReached and (os.clock() - startTime) < 1.0 do
		task.wait()
	end

	if markerConnection then
		markerConnection:Disconnect()
	end

	local settings = getProjectileSettings(abilityConfig)
	local slotLabel = tostring(abilityConfig.KeyCode or "Q")
	local originPosition = context.RootPart.Position
	local aimOriginPosition = originPosition + Vector3.new(0, PROJECTILE_VERTICAL_OFFSET, 0)
	local direction, aimPosition = resolveFreezeShotDirection(context, aimOriginPosition, abilityConfig)
	local finalFacing = applyFreezeShotTurn(context, direction, abilityConfig)

	originPosition = context.RootPart.Position
	aimOriginPosition = originPosition + Vector3.new(0, PROJECTILE_VERTICAL_OFFSET, 0)
	local velocityData = resolveFreezeShotVelocity(context, direction, settings)
	local startPosition = aimOriginPosition + direction * (PROJECTILE_FORWARD_OFFSET + velocityData.SpawnLeadDistance)
	local projectileId = nextProjectileId(context.Player)
	local lifetime = (settings.MaxDistance / velocityData.FinalSpeed) + PROJECTILE_LIFETIME_GRACE

	logMessage(
		"SPAWN",
		"player=%s projectileId=%s origin=%s start=%s baseOffset=%.2f spawnLead=%.2f",
		context.Player.Name,
		projectileId,
		formatVector3(aimOriginPosition),
		formatVector3(startPosition),
		PROJECTILE_FORWARD_OFFSET,
		velocityData.SpawnLeadDistance
	)

	logMessage(
		"FIRE",
		"player=%s ability=%s slot=%s origin=%s aimPosition=%s direction=%s finalFacing=%s velocity=%s",
		context.Player.Name,
		context.AbilityName,
		slotLabel,
		formatVector3(originPosition),
		formatVector3(aimPosition),
		formatVector3(direction),
		formatVector3(finalFacing),
		formatVector3(velocityData.FinalVelocity)
	)

	local state = {
		Id = projectileId,
		Player = context.Player,
		Character = context.Character,
		HazardsFolder = HazardRuntime.GetSharedHazardsFolder(),
		OriginPosition = originPosition,
		StartPosition = startPosition,
		Position = startPosition,
		Direction = direction,
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
		SpawnLeadDistance = velocityData.SpawnLeadDistance,
		NextVerboseLogAt = 0,
	}

	task.defer(function()
		local ok, err = pcall(simulateProjectile, context, state)
		if not ok then
			logError("projectile simulation crashed projectileId=%s player=%s detail=%s", state.Id, context.Player.Name, tostring(err))
			emitResolution(context, state, "Expire", "Fail", "simulation_error", state.Position, "simulation_error")
			cleanupProjectile(state, "error:simulation")
		end
	end)

	return buildLaunchPayload(state)
end

function HieHieNoMi.IceBoost(context)
	local player = context.Player
	local character = context.Character
	local rootPart = context.RootPart
	local abilityConfig = context.AbilityConfig
	local duration = math.max(0, tonumber(abilityConfig.Duration) or 0)
	local humanoid = context.Humanoid

	playIceBoostAnimation(humanoid, duration)

	local speedMultiplier = math.max(1, tonumber(abilityConfig.SpeedMultiplier) or 2)
	local untilTime = os.clock() + duration

	player:SetAttribute("HieIceBoostUntil", untilTime)
	player:SetAttribute("HieIceBoostSpeedMultiplier", speedMultiplier)
	player:SetAttribute("HieIceBoostSpeedBonus", nil)

	task.delay(duration + 0.05, function()
		if player.Parent == nil then
			return
		end

		local currentUntil = player:GetAttribute("HieIceBoostUntil")
		if currentUntil == untilTime then
			player:SetAttribute("HieIceBoostUntil", nil)
			player:SetAttribute("HieIceBoostSpeedMultiplier", nil)
			player:SetAttribute("HieIceBoostSpeedBonus", nil)
		end
	end)

	return {
		Duration = duration,
		SpeedMultiplier = speedMultiplier,
	}
end

logMessage("INIT", "Freeze Shot runtime initialized")

local function spawnIceTrail(player, rootCFrame, duration)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local hieParticles = assets and assets:FindFirstChild("HieParticles")
	local iceTrail = hieParticles and hieParticles:FindFirstChild("IceTrail")

	if not iceTrail then return end

	local character = player.Character
	if not character then return end

	local rayOrigin = rootCFrame.Position
	local rayDirection = Vector3.new(0, -10, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local spawnPos = rayResult and rayResult.Position or (rootCFrame.Position - Vector3.new(0, 3, 0))
	local spawnCFrame = CFrame.new(spawnPos) * rootCFrame.Rotation

	local trailClone = iceTrail:Clone()
	trailClone.Parent = Workspace

	local baseplate = Workspace:FindFirstChild("Baseplate") or Workspace.Terrain

	if trailClone:IsA("Model") then
		trailClone:PivotTo(spawnCFrame)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = baseplate
		weld.Part1 = trailClone.PrimaryPart or trailClone:FindFirstChildWhichIsA("BasePart")
		weld.Parent = trailClone
	else
		trailClone.CFrame = spawnCFrame

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = baseplate
		weld.Part1 = trailClone
		weld.Parent = trailClone
	end

	Debris:AddItem(trailClone, duration)
end

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local effectTrigger = remotes and remotes:FindFirstChild("DevilFruitEffectTrigger")

if effectTrigger then
	effectTrigger.OnServerEvent:Connect(function(player, effectName, rootCFrame, duration)
		if effectName == "IceTrail" then
			local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
			if fruitAttribute == "Hie Hie no Mi" and typeof(rootCFrame) == "CFrame" then
				local now = os.clock()
				local info = lastSpawnInfo[player]

				if info then
					local distance = (rootCFrame.Position - info.Position).Magnitude
					if distance < TRAIL_DISTANCE_THRESHOLD or (now - info.Time) < TRAIL_TIME_THRESHOLD then
						return
					end
				end

				lastSpawnInfo[player] = {
					Position = rootCFrame.Position,
					Time = now
				}

				spawnIceTrail(player, rootCFrame, duration)
			end
		end
	end)
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastSpawnInfo[player] = nil
end)

return HieHieNoMi
