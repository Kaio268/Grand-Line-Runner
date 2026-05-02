local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local AbilityTargeting = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("AbilityTargeting")
)
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local MeraShared = Modules:WaitForChild("DevilFruits"):WaitForChild("Mera"):WaitForChild("Shared")
local MeraDashShared = require(MeraShared:WaitForChild("MeraDashShared"))
local MeraAnimationController = require(script.Parent:WaitForChild("MeraAnimationController"))

local MeraMeraNoMi = {}

local MERA_DASH_DEBUG_ATTRIBUTE = "MeraFlameDashDebug"
local DEBUG_INFO = RunService:IsStudio()
local MOVE_LOG_COOLDOWN = 0.08
local FIRE_BURST_MOVEMENT_LOCK_ATTRIBUTE = "MeraFireBurstMovementLocked"
local FIRE_BURST_MOVEMENT_UNLOCK_TIMEOUT_BUFFER = 0.45
local MIN_DASH_DISTANCE = 0.05
local MIN_DASH_RUNTIME = 0.08
local DASH_TIMEOUT_BUFFER = 0.1
local WALL_LOOKAHEAD_BUFFER = 2
local MIN_FIRE_BURST_UNLOCK_DELAY = 0.05
local MIN_FIRE_BURST_STOP_DELAY = 0.25
local MIN_FIRE_BURST_KNOCKDOWN_DURATION = 1
local DEFAULT_FIRE_BURST_KNOCKDOWN_DURATION = 1
local DEFAULT_FIRE_BURST_KNOCKDOWN_PUSH_HORIZONTAL = 44
local DEFAULT_FIRE_BURST_KNOCKDOWN_PUSH_VERTICAL = -55
local DEFAULT_FIRE_BURST_SPEED_RADIUS_MAX_SPEED = 300
local REQUEST_VALIDATION_DISTANCE_EPSILON = 0.05
local REQUEST_VALIDATION_DIRECTION_DELTA_DEGREES = 1
local MIN_REMAINING_DASH_DISTANCE = 0.1
local activeFireBurstMovementLocksByPlayer = {}
local hitEffectService = nil
local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function isDashDebugEnabled(player)
	return ReplicatedStorage:GetAttribute(MERA_DASH_DEBUG_ATTRIBUTE) == true
		or (player and player:GetAttribute(MERA_DASH_DEBUG_ATTRIBUTE) == true)
end

local function logDash(player, message, ...)
	if not isDashDebugEnabled(player) then
		return
	end

	print(string.format("[MERA DASH][SERVER] " .. message, ...))
end

local function logMove(player, message, ...)
	if not (DEBUG_INFO or isDashDebugEnabled(player)) then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraMeraNoMi:MOVE", DiagnosticLogLimiter.BuildKey(message, ...), MOVE_LOG_COOLDOWN) then
		return
	end

	print(string.format("[MERA MOVE] " .. message, ...))
end

local function logFireBurst(player, message, ...)
	if not (DEBUG_INFO or isDashDebugEnabled(player)) then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraMeraNoMi:FIREBURST", DiagnosticLogLimiter.BuildKey(message, ...), MOVE_LOG_COOLDOWN) then
		return
	end

	print(string.format("[MERA FIREBURST][SERVER] " .. message, ...))
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
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

local function buildFireBurstCastId(player, startedAt)
	return string.format("%s:%.6f", tostring(player and player.UserId or 0), tonumber(startedAt) or 0)
end

local function getNonNegativeNumber(value, fallback)
	local numberValue = tonumber(value)
	if numberValue and numberValue >= 0 then
		return numberValue
	end

	return fallback
end

local function getRootPlanarSpeed(rootPart)
	if typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") then
		return 0
	end

	local velocity = rootPart.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude
end

local function getFireBurstWalkSpeedSample(humanoid, speedScaling)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") then
		return 0
	end

	if type(speedScaling) ~= "table" or speedScaling.UseWalkSpeed ~= true then
		return 0
	end

	local multiplier = math.max(0, tonumber(speedScaling.WalkSpeedMultiplier) or 1)
	return math.max(0, tonumber(humanoid.WalkSpeed) or 0) * multiplier
end

local function readNumericValueObject(instance)
	if typeof(instance) ~= "Instance" or not instance:IsA("ValueBase") then
		return nil
	end

	local ok, value = pcall(function()
		return instance.Value
	end)
	if ok and typeof(value) == "number" then
		return math.max(0, value)
	end

	return nil
end

local function getFireBurstSpeedStatSample(player, speedScaling)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, nil
	end

	if type(speedScaling) == "table" and speedScaling.UseSpeedStat == false then
		return nil, nil
	end

	local folderName = type(speedScaling) == "table" and speedScaling.SpeedStatFolder or nil
	local statName = type(speedScaling) == "table" and speedScaling.SpeedStatName or nil
	folderName = if type(folderName) == "string" and folderName ~= "" then folderName else "HiddenLeaderstats"
	statName = if type(statName) == "string" and statName ~= "" then statName else "Speed"

	local folder = player:FindFirstChild(folderName)
	local speedValue = folder and folder:FindFirstChild(statName) or nil
	local statSpeed = readNumericValueObject(speedValue)
	if statSpeed ~= nil then
		return statSpeed, string.format("%s.%s", folderName, statName)
	end

	return nil, string.format("%s.%s_missing", folderName, statName)
end

local function getFireBurstSourceSpeed(context, speedScaling)
	local sourceSpeed, sourceName = getFireBurstSpeedStatSample(type(context) == "table" and context.Player or nil, speedScaling)
	if sourceSpeed ~= nil then
		return sourceSpeed, sourceName
	end

	sourceSpeed = 0
	sourceName = "none"
	local rootPart = type(context) == "table" and context.RootPart or nil
	local humanoid = type(context) == "table" and context.Humanoid or nil

	if type(speedScaling) ~= "table" or speedScaling.UsePlanarVelocity ~= false then
		local planarVelocitySpeed = getRootPlanarSpeed(rootPart)
		if planarVelocitySpeed > sourceSpeed then
			sourceSpeed = planarVelocitySpeed
			sourceName = "planar_velocity"
		end
	end

	local walkSpeed = getFireBurstWalkSpeedSample(humanoid, speedScaling)
	if walkSpeed > sourceSpeed then
		sourceSpeed = walkSpeed
		sourceName = "walk_speed"
	end

	return sourceSpeed, sourceName
end

local function getFireBurstSpeedRadiusScale(context, abilityConfig)
	local speedScaling = type(abilityConfig) == "table" and abilityConfig.SpeedRadiusScaling or nil
	if type(speedScaling) ~= "table" or speedScaling.Enabled == false then
		return 1, 0, 0, "disabled"
	end

	local minScale = getNonNegativeNumber(speedScaling.MinScale, 1)
	local maxScale = getNonNegativeNumber(speedScaling.MaxScale, minScale)
	local baselineSpeed = math.max(0, tonumber(speedScaling.BaselineSpeed) or 0)
	local maxSpeed = tonumber(speedScaling.SpeedForMaxScale)
		or tonumber(speedScaling.MaxSpeed)
		or DEFAULT_FIRE_BURST_SPEED_RADIUS_MAX_SPEED
	local sourceSpeed, sourceName = getFireBurstSourceSpeed(context, speedScaling)

	if maxSpeed <= baselineSpeed then
		return maxScale, sourceSpeed, 1, sourceName
	end

	local alpha = math.clamp((sourceSpeed - baselineSpeed) / (maxSpeed - baselineSpeed), 0, 1)
	return minScale + ((maxScale - minScale) * alpha), sourceSpeed, alpha, sourceName
end

local function buildFireBurstPhasePayload(sequence, phase)
	return {
		Phase = phase,
		CastId = sequence.CastId,
		StartedAt = sequence.StartedAt,
		ReleasedAt = sequence.ReleasedAt,
		BaseRadius = sequence.BaseRadius,
		Radius = sequence.Radius,
		RadiusScale = sequence.RadiusScale,
		SpeedRadiusScale = sequence.SpeedRadiusScale,
		SpeedRadiusSourceSpeed = sequence.SpeedRadiusSourceSpeed,
		SpeedRadiusScaleAlpha = sequence.SpeedRadiusScaleAlpha,
		SpeedRadiusSource = sequence.SpeedRadiusSource,
		HitboxRadiusScale = sequence.HitboxRadiusScale,
		HitboxShape = sequence.HitboxShape,
		HitboxGrounded = sequence.HitboxGrounded,
		VisualRadius = sequence.VisualRadius,
		VisualBaseRadius = sequence.VisualBaseRadius,
		VisualRadiusScale = sequence.VisualRadiusScale,
		AutoScaleVisualToHitbox = sequence.AutoScaleVisualToHitbox,
		Duration = sequence.Duration,
		ReleaseSource = sequence.ReleaseSource,
	}
end

local function getCharacterPivotOffset(character, rootPart)
	local pivot = character:GetPivot()
	return pivot.Position - rootPart.Position
end

local function getPlanarDistance(firstPosition, secondPosition)
	if typeof(firstPosition) ~= "Vector3" or typeof(secondPosition) ~= "Vector3" then
		return math.huge
	end

	local offset = firstPosition - secondPosition
	return Vector3.new(offset.X, 0, offset.Z).Magnitude
end

local function pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
	local offset = getCharacterPivotOffset(character, rootPart)
	local pivot = character:GetPivot()
	local rotation = pivot - pivot.Position
	local targetPivot = CFrame.new(targetRootPosition + offset) * rotation
	character:PivotTo(targetPivot)
end

local function isPlayerNetworkOwner(player, rootPart)
	if not player or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local ok, owner = pcall(function()
		return rootPart:GetNetworkOwner()
	end)
	return ok and owner == player
end

local function shouldServerCommitDashMotion(player, rootPart)
	return not isPlayerNetworkOwner(player, rootPart)
end

local function getDashTargetPosition(context)
	local requestPayload = context.RequestPayload
	if type(requestPayload) ~= "table" then
		return nil
	end

	return requestPayload.DashTargetPosition
end

local function getRequestedDirection(rootPart, dashTargetPosition)
	if typeof(dashTargetPosition) ~= "Vector3" then
		return nil
	end

	local delta = MeraDashShared.GetPlanarVector(dashTargetPosition - rootPart.Position)
	if delta.Magnitude <= 0.01 then
		return nil
	end

	return delta.Unit
end

local function getRequestedVisualDirection(rootPart, requestPayload)
	local payloadDirection = type(requestPayload) == "table" and requestPayload.VisualDirection or nil
	local planarPayloadDirection = typeof(payloadDirection) == "Vector3" and MeraDashShared.GetPlanarVector(payloadDirection) or nil
	if planarPayloadDirection and planarPayloadDirection.Magnitude > 0.01 then
		return planarPayloadDirection.Unit
	end

	local fallbackDirection = rootPart and MeraDashShared.GetPlanarVector(rootPart.CFrame.LookVector) or nil
	if fallbackDirection and fallbackDirection.Magnitude > 0.01 then
		return fallbackDirection.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function buildStartPayload(
	plan,
	requestReceivedAt,
	dashStartAt,
	startPosition,
	requestedDirection,
	visualDirection,
	rawRequestedDistance
)
	local directionDeltaDegrees = requestedDirection and MeraDashShared.GetDirectionDeltaDegrees(requestedDirection, plan.Direction) or 0
	local validationAdjusted = rawRequestedDistance > (plan.RequestedDistance + REQUEST_VALIDATION_DISTANCE_EPSILON)
		or directionDeltaDegrees > REQUEST_VALIDATION_DIRECTION_DELTA_DEGREES

	return {
		Phase = "Start",
		Direction = plan.Direction,
		VisualDirection = visualDirection,
		DirectionSource = plan.DirectionSource,
		RequestedDirection = requestedDirection,
		RawRequestedDistance = rawRequestedDistance,
		RequestedDistance = plan.RequestedDistance,
		MaxDistance = plan.MaxDistance,
		Distance = plan.Distance,
		Duration = plan.Duration,
		InstantDistance = plan.InstantDistance,
		RemainingDistance = plan.RemainingDistance,
		StartDashSpeed = plan.StartDashSpeed,
		EndDashSpeed = plan.EndDashSpeed,
		EndCarrySpeed = plan.EndCarrySpeed,
		RequiredBurstSpeed = plan.RequiredBurstSpeed,
		WallShortened = plan.WallShortened,
		ValidationAdjusted = validationAdjusted,
		DirectionDeltaDegrees = directionDeltaDegrees,
		RequestReceivedAt = requestReceivedAt,
		StartedAt = dashStartAt,
		ServerProcessingTimeMs = math.max(0, (dashStartAt - requestReceivedAt) * 1000),
		StartPosition = startPosition,
		EndPosition = startPosition + (plan.Direction * plan.Distance),
	}
end

local function emitResolvePayload(context, plan, resolveState, completionTolerance)
	local resolvePayload = {
		Phase = "Resolve",
		Direction = plan.Direction,
		Distance = plan.Distance,
		RequestedDistance = plan.RequestedDistance,
		TraveledDistance = resolveState.TraveledDistance,
		DistanceShortfall = math.max(0, plan.Distance - resolveState.TraveledDistance),
		StartedAt = resolveState.StartedAt,
		EndedAt = resolveState.EndedAt,
		ActualDuration = math.max(0, resolveState.EndedAt - resolveState.StartedAt),
		ResolveReason = resolveState.ResolveReason,
		Interrupted = resolveState.Interrupted,
		EndedEarly = resolveState.TraveledDistance + math.max(completionTolerance or 0.5, 0.5) < plan.Distance,
		WallShortened = plan.WallShortened,
		StartPosition = resolveState.StartPosition,
		ActualEndPosition = resolveState.EndPosition,
		EndPosition = resolveState.StartPosition + (plan.Direction * plan.Distance),
	}

	context.EmitEffect("FlameDash", resolvePayload)
	return resolvePayload
end

function MeraMeraNoMi.FlameDash(context)
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local player = context.Player
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")) or nil
	local requestReceivedAt = tonumber(context.RequestReceivedAt) or getSharedTimestamp()
	local dashTargetPosition = getDashTargetPosition(context)
	local requestedDirection = getRequestedDirection(rootPart, dashTargetPosition)
	local requestedVisualDirection = getRequestedVisualDirection(rootPart, context.RequestPayload)
	local rawRequestedDistance = typeof(dashTargetPosition) == "Vector3"
			and MeraDashShared.GetPlanarMagnitude(dashTargetPosition - rootPart.Position)
		or MeraDashShared.GetMaxDashDistance(humanoid, rootPart, context.AbilityConfig)
	local plan = MeraDashShared.BuildDashPlan(character, humanoid, rootPart, context.AbilityConfig, dashTargetPosition)
	local dashStartAt = getSharedTimestamp()
	local startPosition = rootPart.Position
	local startPayload = buildStartPayload(
		plan,
		requestReceivedAt,
		dashStartAt,
		startPosition,
		requestedDirection,
		requestedVisualDirection,
		rawRequestedDistance
	)
	DevilFruitLogger.Info(
		"MOVE",
		"handler enter fruit=%s ability=%s player=%s character=%s humanoid=%s root=%s animator=%s payloadKeys=%d requestedDir=%s start=%s",
		"Mera Mera no Mi",
		"FlameDash",
		player and player.Name or "<nil>",
		tostring(character ~= nil),
		tostring(humanoid ~= nil),
		tostring(rootPart ~= nil),
		tostring(animator ~= nil),
		countPayloadKeys(context.RequestPayload),
		formatVector3(requestedDirection),
		formatVector3(startPosition)
	)

	logDash(
		player,
		"request_accepted ts=%.6f player=%s direction=%s requestedDir=%s source=%s intended=%.2f final=%.2f max=%.2f wallShortened=%s duration=%.3f processingMs=%.2f validationAdjusted=%s",
		dashStartAt,
		player.Name,
		formatVector3(plan.Direction),
		formatVector3(requestedDirection),
		tostring(plan.DirectionSource),
		plan.RequestedDistance,
		plan.Distance,
		plan.MaxDistance,
		tostring(plan.WallShortened),
		plan.Duration,
		startPayload.ServerProcessingTimeMs,
		tostring(startPayload.ValidationAdjusted)
	)
	logMove(player, "move=FlameDash startup source=server_authorized player=%s", player.Name)

	task.spawn(function()
		local resolveReason = "completed"
		local interrupted = false
		local connection
		local elapsed = 0
		local dashFinished = false
		local completionTolerance = MeraDashShared.GetCompletionTolerance(context.AbilityConfig)
		local runtimeGrace = MeraDashShared.GetRuntimeGrace(context.AbilityConfig)
		local finalSnapTolerance = MeraDashShared.GetFinalSnapTolerance(context.AbilityConfig)
		local maxRuntime = math.max(plan.Duration + runtimeGrace, MIN_DASH_RUNTIME)
		local burstStartPosition = rootPart.Position
		local resolveTargetPosition = startPosition + (plan.Direction * plan.Distance)
		local serverCommitsMotion = shouldServerCommitDashMotion(player, rootPart)

		logDash(
			player,
			"motion_authority ts=%.6f player=%s serverCommitsMotion=%s",
			dashStartAt,
			player.Name,
			tostring(serverCommitsMotion)
		)

		local function getCorrectionTarget(targetRootPosition)
			if not rootPart.Parent or typeof(targetRootPosition) ~= "Vector3" then
				return nil
			end

			local planarDistanceToTarget = MeraDashShared.GetPlanarMagnitude(targetRootPosition - rootPart.Position)
			if planarDistanceToTarget <= finalSnapTolerance then
				return nil
			end

			return targetRootPosition
		end

		local function finishDash(reason, wasInterrupted, options)
			if dashFinished then
				return
			end

			dashFinished = true
			resolveReason = tostring(reason or resolveReason)
			interrupted = wasInterrupted == true

			if connection and connection.Connected then
				connection:Disconnect()
			end

			if rootPart.Parent then
				local targetRootPosition = options and options.TargetRootPosition or nil
				if serverCommitsMotion and typeof(targetRootPosition) == "Vector3" and character.Parent then
					pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
				end
			end
		end

		if plan.Distance <= MIN_DASH_DISTANCE then
			resolveReason = "blocked_at_start"
			dashFinished = true
		else
			if serverCommitsMotion and plan.InstantDistance > MIN_DASH_DISTANCE and character.Parent and rootPart.Parent then
				local targetRootPosition = startPosition + (plan.Direction * plan.InstantDistance)
				pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
			end

			burstStartPosition = rootPart.Position
			logMove(player, "move=FlameDash release source=server_authorized player=%s", player.Name)

			if plan.RemainingDistance > MIN_REMAINING_DASH_DISTANCE then
				connection = RunService.Heartbeat:Connect(function(dt)
					if not character.Parent or not rootPart.Parent or humanoid.Health <= 0 then
						finishDash("interrupted_invalid_state", true)
						return
					end

					elapsed += dt

					local traveledDistance = MeraDashShared.GetTravelDistance(burstStartPosition, rootPart.Position, plan.Direction)
					local currentRemainingDistance = plan.RemainingDistance - traveledDistance
					if currentRemainingDistance <= completionTolerance then
						finishDash("completed", false, {
							TargetRootPosition = getCorrectionTarget(resolveTargetPosition),
						})
						return
					end

					local alpha = math.clamp(elapsed / plan.Duration, 0, 1)
					local dashSpeed = plan.StartDashSpeed
						+ ((plan.EndDashSpeed - plan.StartDashSpeed) * MeraDashShared.Smoothstep(alpha))
					local lookAheadDistance = math.min(
						MeraDashShared.GetLookAheadDistance(dashSpeed, dt),
						currentRemainingDistance + WALL_LOOKAHEAD_BUFFER
					)
					if MeraDashShared.ShouldStopForWall(character, rootPart, plan.Direction, lookAheadDistance) then
						finishDash("wall_blocked_mid_dash", true)
						return
					end

					if elapsed >= maxRuntime then
						local correctionTarget = getCorrectionTarget(resolveTargetPosition)
						local closeEnoughToComplete = currentRemainingDistance <= completionTolerance
							or correctionTarget == nil
						finishDash(closeEnoughToComplete and "completed" or "max_runtime_reached", not closeEnoughToComplete, {
							TargetRootPosition = correctionTarget,
						})
					end
				end)

				local timeoutAt = os.clock() + maxRuntime + DASH_TIMEOUT_BUFFER
				while not dashFinished and os.clock() < timeoutAt do
					task.wait()
				end
				if not dashFinished then
					local correctionTarget = getCorrectionTarget(resolveTargetPosition)
					finishDash("timeout_disconnect", true, {
						TargetRootPosition = correctionTarget,
					})
				end
			else
				finishDash("instant_commit_only", false, {
					TargetRootPosition = getCorrectionTarget(resolveTargetPosition),
				})
			end
		end

		local dashEndAt = getSharedTimestamp()
		local endPosition = rootPart.Parent and rootPart.Position or startPosition
		local traveledDistance = math.clamp(
			MeraDashShared.GetTravelDistance(startPosition, endPosition, plan.Direction),
			0,
			math.max(plan.Distance, 0)
		)
		local resolvePayload = emitResolvePayload(context, plan, {
			StartedAt = dashStartAt,
			EndedAt = dashEndAt,
			StartPosition = startPosition,
			EndPosition = endPosition,
			TraveledDistance = traveledDistance,
			ResolveReason = resolveReason,
			Interrupted = interrupted,
		}, completionTolerance)

		logDash(
			player,
			"dash_summary ts=%.6f player=%s start=%.6f finish=%.6f duration=%.3f planned=%.2f traveled=%.2f shortfall=%.2f resolve=%s interrupted=%s wallShortened=%s",
			dashEndAt,
			player.Name,
			dashStartAt,
			dashEndAt,
			resolvePayload.ActualDuration,
			plan.Distance,
			resolvePayload.TraveledDistance,
			resolvePayload.DistanceShortfall,
			tostring(resolveReason),
			tostring(interrupted),
			tostring(plan.WallShortened)
		)
		logMove(
			player,
			"move=FlameDash complete source=server_authorized player=%s reason=%s interrupted=%s",
			player.Name,
			tostring(resolveReason),
			tostring(interrupted)
		)
	end)

	return startPayload
end

local function setFireBurstMovementLockAttribute(player, locked)
	if player and player.Parent then
		player:SetAttribute(FIRE_BURST_MOVEMENT_LOCK_ATTRIBUTE, locked == true and true or nil)
	end
end

local function stopRootMotion(rootPart)
	if typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") then
		return
	end

	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function applyFireBurstMovementLock(context, abilityConfig)
	if type(abilityConfig) == "table" and abilityConfig.MovementLockEnabled == false then
		return nil
	end

	local player = context and context.Player
	local humanoid = context and context.Humanoid
	local rootPart = context and context.RootPart
	if not player or not player:IsA("Player")
		or typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid")
		or typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart")
	then
		return nil
	end

	local lockState = {}
	activeFireBurstMovementLocksByPlayer[player] = lockState
	setFireBurstMovementLockAttribute(player, true)

	local original = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
		RootAnchored = rootPart.Anchored,
	}

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	pcall(function()
		humanoid:Move(Vector3.zero, false)
	end)

	stopRootMotion(rootPart)
	rootPart.Anchored = true

	local function releaseMovementLock(reason)
		if activeFireBurstMovementLocksByPlayer[player] ~= lockState then
			return false
		end

		activeFireBurstMovementLocksByPlayer[player] = nil
		setFireBurstMovementLockAttribute(player, false)

		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.WalkSpeed = original.WalkSpeed
			humanoid.JumpPower = original.JumpPower
			humanoid.JumpHeight = original.JumpHeight
			humanoid.AutoRotate = original.AutoRotate
			pcall(function()
				humanoid:Move(Vector3.zero, false)
			end)
		end

		if rootPart.Parent then
			rootPart.Anchored = original.RootAnchored == true
			stopRootMotion(rootPart)
		end

		logFireBurst(player, "movement unlock player=%s reason=%s", player.Name, tostring(reason or "unknown"))
		return true
	end

	lockState.Release = releaseMovementLock
	return releaseMovementLock
end

local function clearFireBurstMovementLock(player, reason)
	if not player then
		return false
	end

	local lockState = activeFireBurstMovementLocksByPlayer[player]
	if type(lockState) == "table" and type(lockState.Release) == "function" then
		return lockState.Release(reason or "runtime_clear")
	end

	activeFireBurstMovementLocksByPlayer[player] = nil
	setFireBurstMovementLockAttribute(player, false)
	return false
end

local function scheduleFireBurstMovementUnlock(releaseMovementLock, animationState, stopDelay)
	if type(releaseMovementLock) ~= "function" then
		return
	end

	local unlocked = false
	local stoppedConnection = nil

	local function unlock(reason)
		if unlocked then
			return
		end

		unlocked = true
		if stoppedConnection then
			stoppedConnection:Disconnect()
			stoppedConnection = nil
		end

		releaseMovementLock(reason)
	end

	local track = type(animationState) == "table" and animationState.Track or nil
	if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
		stoppedConnection = track.Stopped:Connect(function()
			unlock("animation_stopped")
		end)
		if not track.IsPlaying then
			task.defer(function()
				unlock("animation_already_stopped")
			end)
		end
	end

	task.delay(math.max(MIN_FIRE_BURST_UNLOCK_DELAY, tonumber(stopDelay) or 0) + FIRE_BURST_MOVEMENT_UNLOCK_TIMEOUT_BUFFER, function()
		unlock("timeout")
	end)
end

local function getFireBurstAnimationStopDelay(animationState, fallbackDelay)
	local resolvedFallback = math.max(MIN_FIRE_BURST_STOP_DELAY, tonumber(fallbackDelay) or 0)
	local track = type(animationState) == "table" and animationState.Track or nil
	if typeof(track) ~= "Instance" or not track:IsA("AnimationTrack") then
		return resolvedFallback
	end

	local trackLength = tonumber(track.Length) or 0
	local timePosition = tonumber(track.TimePosition) or 0
	if trackLength <= 0 then
		return resolvedFallback
	end

	return math.max(resolvedFallback, trackLength - timePosition)
end

local function getHitEffectService()
	if hitEffectService == nil then
		hitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))
	end

	return hitEffectService
end

local function getFireBurstKnockdownDuration(abilityConfig)
	if type(abilityConfig) ~= "table" then
		return DEFAULT_FIRE_BURST_KNOCKDOWN_DURATION
	end

	return math.max(
		MIN_FIRE_BURST_KNOCKDOWN_DURATION,
		tonumber(abilityConfig.KnockdownDuration) or DEFAULT_FIRE_BURST_KNOCKDOWN_DURATION
	)
end

local function getFireBurstKnockdownImpulse(originPosition, targetRootPart, abilityConfig)
	if typeof(originPosition) ~= "Vector3" or not targetRootPart then
		return nil
	end

	local horizontalStrength = DEFAULT_FIRE_BURST_KNOCKDOWN_PUSH_HORIZONTAL
	local verticalStrength = DEFAULT_FIRE_BURST_KNOCKDOWN_PUSH_VERTICAL
	if type(abilityConfig) == "table" then
		horizontalStrength = math.max(
			0,
			tonumber(abilityConfig.KnockdownPushHorizontal) or DEFAULT_FIRE_BURST_KNOCKDOWN_PUSH_HORIZONTAL
		)
		verticalStrength = tonumber(abilityConfig.KnockdownPushVertical) or DEFAULT_FIRE_BURST_KNOCKDOWN_PUSH_VERTICAL
	end

	local offset = targetRootPart.Position - originPosition
	local planarOffset = Vector3.new(offset.X, 0, offset.Z)
	local fallbackDirection = Vector3.new(targetRootPart.CFrame.LookVector.X, 0, targetRootPart.CFrame.LookVector.Z)
	local direction = if planarOffset.Magnitude > MIN_DASH_DISTANCE
		then planarOffset.Unit
		elseif fallbackDirection.Magnitude > MIN_DASH_DISTANCE then fallbackDirection.Unit
		else Vector3.zAxis

	return (direction * horizontalStrength) + Vector3.new(0, verticalStrength, 0)
end

local function applyFireBurstKnockdown(context, radius, abilityConfig)
	if type(context) ~= "table" or radius <= 0 then
		return 0
	end

	local originRootPart = context.RootPart
	if typeof(originRootPart) ~= "Instance" or not originRootPart:IsA("BasePart") or not originRootPart.Parent then
		return 0
	end

	local affectedCount = 0
	local originPosition = originRootPart.Position
	local resolvedHitEffectService = getHitEffectService()
	local knockdownDuration = getFireBurstKnockdownDuration(abilityConfig)

	for _, targetContext in ipairs(AbilityTargeting.GetCharacterTargets({
		ExcludePlayer = context.Player,
		ExcludeCharacter = context.Character,
	})) do
		local targetRootPart = targetContext.RootPart
		if not targetRootPart then
			continue
		end

		if getPlanarDistance(originPosition, targetRootPart.Position) > radius then
			continue
		end

		local knockdownImpulse = getFireBurstKnockdownImpulse(originPosition, targetRootPart, abilityConfig)
		local applied = resolvedHitEffectService.ApplyEffect(targetContext.Instance, "Knockdown", {
			Duration = knockdownDuration,
			DropPosition = targetRootPart.Position,
			RagdollJoints = true,
			RagdollImpulse = knockdownImpulse,
			Movement = {
				WalkSpeedMultiplier = 0,
				JumpMultiplier = 0,
				AutoRotate = false,
				PlatformStand = true,
				State = Enum.HumanoidStateType.Ragdoll,
			},
		})
		if applied then
			affectedCount += 1
		end
	end

	return affectedCount
end

function MeraMeraNoMi.FireBurst(context)
	local abilityConfig = context.AbilityConfig
	local player = context.Player
	local humanoid = context.Humanoid
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")) or nil
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	local duration = math.max(0, tonumber(abilityConfig.Duration) or 0)
	local baseRadius = math.max(0, tonumber(abilityConfig.Radius) or 0)
	local radiusScale = getNonNegativeNumber(abilityConfig.RadiusScale, 1)
	local hitboxRadiusScale = getNonNegativeNumber(abilityConfig.HitboxRadiusScale, 1)
	local visualRadiusScale = getNonNegativeNumber(abilityConfig.VisualRadiusScale, 1)
	local speedRadiusScale, speedRadiusSourceSpeed, speedRadiusScaleAlpha, speedRadiusSource =
		getFireBurstSpeedRadiusScale(context, abilityConfig)
	local radius = baseRadius * radiusScale * hitboxRadiusScale * speedRadiusScale
	local visualBaseRadius = math.max(
		0,
		tonumber(abilityConfig.VisualRadius) or tonumber(abilityConfig.VisualBaseRadius) or baseRadius
	)
	local visualRadius = visualBaseRadius * radiusScale * visualRadiusScale * speedRadiusScale
	local knockdownDuration = getFireBurstKnockdownDuration(abilityConfig)
	local startedAt = getSharedTimestamp()
	local releaseMovementLock = applyFireBurstMovementLock(context, abilityConfig)
	local sequence = {
		CastId = buildFireBurstCastId(player, startedAt),
		StartedAt = startedAt,
		ReleasedAt = nil,
		ReleaseSource = "pending",
		BaseRadius = baseRadius,
		Radius = radius,
		RadiusScale = radiusScale,
		SpeedRadiusScale = speedRadiusScale,
		SpeedRadiusSourceSpeed = speedRadiusSourceSpeed,
		SpeedRadiusScaleAlpha = speedRadiusScaleAlpha,
		SpeedRadiusSource = speedRadiusSource,
		HitboxRadiusScale = hitboxRadiusScale,
		HitboxShape = "PlanarRadius",
		HitboxGrounded = true,
		VisualRadius = visualRadius,
		VisualBaseRadius = visualBaseRadius,
		VisualRadiusScale = visualRadiusScale,
		AutoScaleVisualToHitbox = abilityConfig.AutoScaleVisualToHitbox ~= false,
		Duration = duration,
		KnockdownDuration = knockdownDuration,
	}
	DevilFruitLogger.Info(
		"MOVE",
		"handler enter fruit=%s ability=%s player=%s character=%s humanoid=%s root=%s animator=%s payloadKeys=%d baseRadius=%.2f radius=%.2f visualRadius=%.2f speed=%.2f speedSource=%s speedScale=%.3f speedAlpha=%.3f duration=%.2f knockdownDuration=%.2f",
		"Mera Mera no Mi",
		"FireBurst",
		player and player.Name or "<nil>",
		tostring(context.Character ~= nil),
		tostring(humanoid ~= nil),
		tostring(context.RootPart ~= nil),
		tostring(animator ~= nil),
		countPayloadKeys(context.RequestPayload),
		baseRadius,
		radius,
		visualRadius,
		speedRadiusSourceSpeed,
		tostring(speedRadiusSource),
		speedRadiusScale,
		speedRadiusScaleAlpha,
		duration,
		knockdownDuration
	)
	logFireBurst(
		player,
		"start received player=%s cast=%s baseRadius=%.2f hitboxRadius=%.2f visualRadius=%.2f radiusScale=%.3f hitboxScale=%.3f visualScale=%.3f speed=%.2f speedSource=%s speedScale=%.3f speedAlpha=%.3f duration=%.2f knockdownDuration=%.2f movementLock=%s",
		player and player.Name or "<unknown>",
		sequence.CastId,
		baseRadius,
		radius,
		visualRadius,
		radiusScale,
		hitboxRadiusScale,
		visualRadiusScale,
		speedRadiusSourceSpeed,
		tostring(speedRadiusSource),
		speedRadiusScale,
		speedRadiusScaleAlpha,
		duration,
		knockdownDuration,
		tostring(releaseMovementLock ~= nil)
	)
	logFireBurst(player, "startup effect begin player=%s cast=%s", player and player.Name or "<unknown>", sequence.CastId)
	context.EmitEffect("FireBurst", buildFireBurstPhasePayload(sequence, "Start"))
	local animationState = MeraAnimationController.PlayFireBurstAnimation(context.Character, animationConfig)
	logFireBurst(
		player,
		"animation start player=%s cast=%s state=%s",
		player and player.Name or "<unknown>",
		sequence.CastId,
		tostring(animationState ~= nil)
	)
	DevilFruitLogger.Info(
		"ANIM",
		"server animation state fruit=%s ability=%s player=%s state=%s",
		"Mera Mera no Mi",
		"FireBurst",
		player and player.Name or "<nil>",
		tostring(animationState ~= nil)
	)
	local releaseReached, releaseSource = MeraAnimationController.WaitForFireBurstRelease(animationState, animationConfig)
	sequence.ReleasedAt = getSharedTimestamp()
	sequence.ReleaseSource = releaseSource or (releaseReached and "marker" or "fallback")
	logFireBurst(
		player,
		"release gate player=%s cast=%s source=%s markerReached=%s",
		player and player.Name or "<unknown>",
		sequence.CastId,
		tostring(sequence.ReleaseSource),
		tostring(releaseReached == true)
	)
	DevilFruitLogger.Info(
		"MOVE",
		"server release gate fruit=%s ability=%s player=%s animationState=%s releaseReached=%s",
		"Mera Mera no Mi",
		"FireBurst",
		player and player.Name or "<nil>",
		tostring(animationState ~= nil),
		tostring(releaseReached == true)
	)
	logFireBurst(
		player,
		"release triggered player=%s cast=%s radius=%.2f duration=%.2f",
		player and player.Name or "<unknown>",
		sequence.CastId,
		radius,
		duration
	)
	local affectedCount = applyFireBurstKnockdown(context, radius, abilityConfig)
	logFireBurst(
		player,
		"knockdown applied player=%s cast=%s affected=%d radius=%.2f knockdownDuration=%.2f",
		player and player.Name or "<unknown>",
		sequence.CastId,
		affectedCount,
		radius,
		knockdownDuration
	)
	if animationState then
		local stopDelay = getFireBurstAnimationStopDelay(animationState, duration)
		scheduleFireBurstMovementUnlock(releaseMovementLock, animationState, stopDelay)
		task.delay(stopDelay, function()
			MeraAnimationController.StopAnimation(animationState, "duration_complete")
		end)
	else
		task.delay(math.max(duration, MIN_FIRE_BURST_STOP_DELAY), function()
			if releaseMovementLock then
				releaseMovementLock("no_animation")
			end
		end)
	end

	if player then
		task.delay(duration, function()
			if player.Parent ~= nil then
				logFireBurst(player, "cleanup complete player=%s cast=%s", player.Name, sequence.CastId)
			end
		end)
	end

	return buildFireBurstPhasePayload(sequence, "Release")
end

function MeraMeraNoMi.ClearRuntimeState(player)
	if player and player.Parent then
		player:SetAttribute("MeraFireBurstUntil", nil)
	end

	clearFireBurstMovementLock(player, "runtime_clear")
end

return MeraMeraNoMi
