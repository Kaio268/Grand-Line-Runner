local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local MeraShared = Modules:WaitForChild("DevilFruits"):WaitForChild("Mera"):WaitForChild("Shared")
local MeraDashShared = require(MeraShared:WaitForChild("MeraDashShared"))
local MeraAnimationController = require(script.Parent:WaitForChild("MeraAnimationController"))

local MeraMeraNoMi = {}

local MERA_DASH_DEBUG_ATTRIBUTE = "MeraFlameDashDebug"
local MERA_AUDIT_MARKER = "MERA_AUDIT_2026_03_30_V4"
local MAX_RUNTIME_GRACE = 0.18
local DEBUG_INFO = RunService:IsStudio()
local MOVE_LOG_COOLDOWN = 0.08
local PREVIOUS_FIRE_BURST_RADIUS = 50

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

local function describePayloadForAudit(payload)
	if typeof(payload) ~= "table" then
		return string.format("type=%s value=%s", typeof(payload), tostring(payload))
	end

	local keys = {}
	for key in pairs(payload) do
		keys[#keys + 1] = key
	end

	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		local value = payload[key]
		if typeof(value) == "Vector3" then
			parts[#parts + 1] = string.format("%s=(%.2f, %.2f, %.2f)", tostring(key), value.X, value.Y, value.Z)
		else
			parts[#parts + 1] = string.format("%s=%s", tostring(key), tostring(value))
		end
	end

	return string.format("type=table keys=%d payload={%s}", #keys, table.concat(parts, ", "))
end

local function logMeraAudit(level, message, ...)
	local formattedMessage = string.format("[%s] " .. message, MERA_AUDIT_MARKER, ...)
	if level == "WARN" then
		DevilFruitLogger.Warn("MOVE", formattedMessage)
		return
	end

	DevilFruitLogger.Info("MOVE", formattedMessage)
end

local function getCharacterPivotOffset(character, rootPart)
	local pivot = character:GetPivot()
	return pivot.Position - rootPart.Position
end

local function pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
	local offset = getCharacterPivotOffset(character, rootPart)
	local pivot = character:GetPivot()
	local rotation = pivot - pivot.Position
	local targetPivot = CFrame.new(targetRootPosition + offset) * rotation
	character:PivotTo(targetPivot)
end

local function setHorizontalVelocity(rootPart, horizontalVelocity)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, currentVelocity.Y, horizontalVelocity.Z)
end

local function stopDashVelocity(rootPart)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
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

local function buildStartPayload(plan, requestReceivedAt, dashStartAt, startPosition, requestedDirection, rawRequestedDistance)
	local directionDeltaDegrees = requestedDirection and MeraDashShared.GetDirectionDeltaDegrees(requestedDirection, plan.Direction) or 0
	local validationAdjusted = rawRequestedDistance > (plan.RequestedDistance + 0.05) or directionDeltaDegrees > 1

	return {
		Phase = "Start",
		Direction = plan.Direction,
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

local function emitResolvePayload(context, plan, resolveState)
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
		EndedEarly = resolveState.TraveledDistance + 0.5 < plan.Distance,
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
	local rawRequestedDistance = typeof(dashTargetPosition) == "Vector3"
			and MeraDashShared.GetPlanarMagnitude(dashTargetPosition - rootPart.Position)
		or MeraDashShared.GetMaxDashDistance(humanoid, rootPart, context.AbilityConfig)
	local plan = MeraDashShared.BuildDashPlan(character, humanoid, rootPart, context.AbilityConfig, dashTargetPosition)
	local dashStartAt = getSharedTimestamp()
	local startPosition = rootPart.Position
	local startPayload = buildStartPayload(plan, requestReceivedAt, dashStartAt, startPosition, requestedDirection, rawRequestedDistance)
	logMeraAudit(
		"INFO",
		"Mera handler enter ability=FlameDash player=%s payload=%s",
		player and player.Name or "<nil>",
		describePayloadForAudit(context.RequestPayload)
	)
	logMeraAudit(
		"INFO",
		"Mera FlameDash enter player=%s requestedDir=%s dashTarget=%s plannedDistance=%.2f requestedDistance=%.2f",
		player and player.Name or "<nil>",
		formatVector3(requestedDirection),
		formatVector3(dashTargetPosition),
		tonumber(plan and plan.Distance) or 0,
		tonumber(plan and plan.RequestedDistance) or 0
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
		local maxRuntime = math.max(plan.Duration + MAX_RUNTIME_GRACE, 0.08)
		local burstStartPosition = rootPart.Position

		if plan.Distance <= 0.05 then
			resolveReason = "blocked_at_start"
			logMeraAudit(
				"WARN",
				"Mera FlameDash early return player=%s reason=%s plannedDistance=%.2f requestedDistance=%.2f",
				player and player.Name or "<nil>",
				tostring(resolveReason),
				tonumber(plan.Distance) or 0,
				tonumber(plan.RequestedDistance) or 0
			)
		else
			if plan.InstantDistance > 0.05 and character.Parent and rootPart.Parent then
				local targetRootPosition = startPosition + (plan.Direction * plan.InstantDistance)
				pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
			end

			setHorizontalVelocity(rootPart, plan.Direction * plan.StartDashSpeed)
			burstStartPosition = rootPart.Position
			logMove(player, "move=FlameDash release source=server_authorized player=%s", player.Name)

			if plan.RemainingDistance > 0.1 then
				connection = RunService.Heartbeat:Connect(function(dt)
					if not character.Parent or not rootPart.Parent or humanoid.Health <= 0 then
						resolveReason = "interrupted_invalid_state"
						interrupted = true
						connection:Disconnect()
						return
					end

					elapsed += dt

					local traveledDistance = MeraDashShared.GetTravelDistance(burstStartPosition, rootPart.Position, plan.Direction)
					local currentRemainingDistance = plan.RemainingDistance - traveledDistance
					if currentRemainingDistance <= 0.1 then
						setHorizontalVelocity(rootPart, plan.Direction * plan.EndCarrySpeed)
						resolveReason = "completed"
						connection:Disconnect()
						return
					end

					local alpha = math.clamp(elapsed / plan.Duration, 0, 1)
					local dashSpeed = plan.StartDashSpeed
						+ ((plan.EndDashSpeed - plan.StartDashSpeed) * MeraDashShared.Smoothstep(alpha))
					local lookAheadDistance = math.min(
						MeraDashShared.GetLookAheadDistance(dashSpeed, dt),
						currentRemainingDistance + 2
					)
					if MeraDashShared.ShouldStopForWall(character, rootPart, plan.Direction, lookAheadDistance) then
						stopDashVelocity(rootPart)
						resolveReason = "wall_blocked_mid_dash"
						interrupted = true
						connection:Disconnect()
						return
					end

					setHorizontalVelocity(rootPart, plan.Direction * dashSpeed)

					if elapsed >= maxRuntime then
						setHorizontalVelocity(rootPart, plan.Direction * plan.EndCarrySpeed)
						resolveReason = "max_runtime_reached"
						interrupted = true
						connection:Disconnect()
					end
				end)

				task.wait(maxRuntime + 0.05)
				if connection and connection.Connected then
					resolveReason = "timeout_disconnect"
					interrupted = true
					connection:Disconnect()
				end
			else
				setHorizontalVelocity(rootPart, plan.Direction * plan.EndCarrySpeed)
				resolveReason = "instant_commit_only"
			end
		end

		local dashEndAt = getSharedTimestamp()
		local endPosition = rootPart.Parent and rootPart.Position or startPosition
		local traveledDistance = MeraDashShared.GetTravelDistance(startPosition, endPosition, plan.Direction)
		local resolvePayload = emitResolvePayload(context, plan, {
			StartedAt = dashStartAt,
			EndedAt = dashEndAt,
			StartPosition = startPosition,
			EndPosition = endPosition,
			TraveledDistance = traveledDistance,
			ResolveReason = resolveReason,
			Interrupted = interrupted,
		})

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

function MeraMeraNoMi.FireBurst(context)
	local abilityConfig = context.AbilityConfig
	local player = context.Player
	local humanoid = context.Humanoid
	local animator = humanoid and (humanoid:FindFirstChildOfClass("Animator") or humanoid:FindFirstChild("Animator")) or nil
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	local duration = math.max(0, tonumber(abilityConfig.Duration) or 0)
	local radius = math.max(0, tonumber(abilityConfig.Radius) or 0)
	logMeraAudit(
		"INFO",
		"Mera handler enter ability=FireBurst player=%s payload=%s",
		player and player.Name or "<nil>",
		describePayloadForAudit(context.RequestPayload)
	)
	logMeraAudit(
		"INFO",
		"Mera FireBurst enter player=%s radius=%.2f duration=%.2f",
		player and player.Name or "<nil>",
		radius,
		duration
	)
	DevilFruitLogger.Info(
		"MOVE",
		"handler enter fruit=%s ability=%s player=%s character=%s humanoid=%s root=%s animator=%s payloadKeys=%d radius=%.2f duration=%.2f",
		"Mera Mera no Mi",
		"FireBurst",
		player and player.Name or "<nil>",
		tostring(context.Character ~= nil),
		tostring(humanoid ~= nil),
		tostring(context.RootPart ~= nil),
		tostring(animator ~= nil),
		countPayloadKeys(context.RequestPayload),
		radius,
		duration
	)

	logMove(player, "move=FlameBurst startup player=%s", player and player.Name or "<unknown>")
	logMove(
		player,
		"move=FlameBurst radius old=%s new=%s",
		tostring(PREVIOUS_FIRE_BURST_RADIUS),
		tostring(radius)
	)
	context.EmitEffect("FireBurst", {
		Phase = "Start",
		Radius = radius,
		Duration = duration,
	})
	local animationState = MeraAnimationController.PlayFireBurstAnimation(context.Character, animationConfig)
	DevilFruitLogger.Info(
		"ANIM",
		"server animation state fruit=%s ability=%s player=%s state=%s",
		"Mera Mera no Mi",
		"FireBurst",
		player and player.Name or "<nil>",
		tostring(animationState ~= nil)
	)
	local releaseReached = MeraAnimationController.WaitForFireBurstRelease(animationState, animationConfig)
	DevilFruitLogger.Info(
		"MOVE",
		"server release gate fruit=%s ability=%s player=%s animationState=%s releaseReached=%s",
		"Mera Mera no Mi",
		"FireBurst",
		player and player.Name or "<nil>",
		tostring(animationState ~= nil),
		tostring(releaseReached == true)
	)
	logMove(player, "move=FlameBurst release player=%s", player and player.Name or "<unknown>")
	if animationState then
		task.delay(math.max(duration, 0.25), function()
			MeraAnimationController.StopAnimation(animationState, "duration_complete")
		end)
	end

	if player then
		task.delay(duration, function()
			if player.Parent ~= nil then
				logMove(player, "move=FlameBurst complete player=%s", player.Name)
			end
		end)
	end

	return {
		Phase = "Release",
		Radius = radius,
		Duration = duration,
	}
end

return MeraMeraNoMi
