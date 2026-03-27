local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MeraDashShared = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraDashShared"))
local flameDashAnimation = "rbxassetid://124285257843194"
local flameBurstAnimation = "rbxassetid://130411347773227"
local MeraMeraNoMi = {}

local MERA_DASH_DEBUG_ATTRIBUTE = "MeraFlameDashDebug"
local MAX_RUNTIME_GRACE = 0.18

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function spawnStationaryGroundParticles(character, target, folder, emitCountMultiplier)
	local meraParticles = ReplicatedStorage:FindFirstChild("MeraParticles") or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("MeraParticles"))
	local targetFolder = meraParticles and meraParticles:FindFirstChild(folder)

	if not targetFolder then return end

	local targetCFrame = typeof(target) == "CFrame" and target or CFrame.new(target)
	local position = targetCFrame.Position

	-- Ground detection
	local rayOrigin = position + Vector3.new(0, 2, 0)
	local rayDirection = Vector3.new(0, -10, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(rayOrigin, rayDirection, params)
	local spawnPos = result and result.Position or (position - Vector3.new(0, 3, 0))

	-- Create a temporary part to hold the particles
	local effectPart = Instance.new("Part")
	effectPart.Name = "MeraEffect"
	effectPart.Size = Vector3.new(1, 1, 1)
	effectPart.Transparency = 1
	effectPart.CanCollide = false
	effectPart.Anchored = true
	-- Use ground position but keep original rotation
	effectPart.CFrame = CFrame.new(spawnPos) * targetCFrame.Rotation
	effectPart.Parent = Workspace

	for _, particle in ipairs(targetFolder:GetChildren()) do
		if particle:IsA("ParticleEmitter") then
			local clone = particle:Clone()
			clone.LockedToPart = false
			clone.Parent = effectPart
			clone:Emit((clone:GetAttribute("EmitCount") or 100) * (emitCountMultiplier or 1))
		end
	end

	Debris:AddItem(effectPart, 3)
end

local function playFlameDashAnimation(humanoid, character, rootPart)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameDashAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action

	local flameConnection
	local dashConnection

	-- Cleanup function for all connections
	local function cleanup()
		if flameConnection then
			flameConnection:Disconnect()
			flameConnection = nil
		end
		if dashConnection then
			dashConnection:Disconnect()
			dashConnection = nil
		end
	end

	-- Start event: Start Flame (fixed) until End
	track:GetMarkerReachedSignal("Start"):Connect(function()
		local startPos = rootPart.Position
		if flameConnection then flameConnection:Disconnect() end

		-- Flame loop at fixed position
		flameConnection = RunService.Heartbeat:Connect(function()
			if not rootPart.Parent or not character.Parent then return end
			spawnStationaryGroundParticles(character, startPos, "Flame", 0.5)
		end)
	end)

	-- Trail event: Start Dash emission (moving trail)
	track:GetMarkerReachedSignal("Trail"):Connect(function()
		if dashConnection then dashConnection:Disconnect() end

		-- Dash loop following player with rotation
		dashConnection = RunService.Heartbeat:Connect(function()
			if not rootPart.Parent or not character.Parent then return end
			local rotationOffset = CFrame.Angles(0, math.rad(90), 0)
			local spawnCFrame = rootPart.CFrame * rotationOffset
			spawnStationaryGroundParticles(character, spawnCFrame, "Dash", 0.5)
		end)
	end)

	-- TrailEnd event: Stop Dash emission and spawn Trail particles
	track:GetMarkerReachedSignal("TrailEnd"):Connect(function()
		if dashConnection then
			dashConnection:Disconnect()
			dashConnection = nil
		end

		local rotationOffset = CFrame.Angles(0, math.rad(90), 0)
		local spawnCFrame = rootPart.CFrame * rotationOffset
		spawnStationaryGroundParticles(character, spawnCFrame, "Trail")
	end)

	-- End event: Stop all effects
	track:GetMarkerReachedSignal("End"):Connect(function()
		cleanup()
	end)

	track:Play()

	track.Stopped:Connect(function()
		cleanup()
	end)

	return track
end


local function playFlameBurstAnimation(humanoid, character, rootPart)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameBurstAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action

	local ringConnection

	-- Start event: Sustained Ring effect at feet
	track:GetMarkerReachedSignal("Start"):Connect(function()
		if ringConnection then ringConnection:Disconnect() end
		ringConnection = RunService.Heartbeat:Connect(function()
			if not rootPart.Parent or not character.Parent then return end
			spawnStationaryGroundParticles(character, rootPart.Position, "Ring", 0.5)
		end)
	end)

	-- FlameBurst event: Big burst at feet
	track:GetMarkerReachedSignal("FlameBurst"):Connect(function()
		-- Clean up Ring emission if active first
		if ringConnection then
			ringConnection:Disconnect()
			ringConnection = nil
		end

		spawnStationaryGroundParticles(character, rootPart.Position, "Burst", 1.5)
	end)

	-- End event: Stop Ring effect
	track:GetMarkerReachedSignal("End"):Connect(function()
		if ringConnection then
			ringConnection:Disconnect()
			ringConnection = nil
		end
	end)

	track:Play()

	track.Stopped:Connect(function()
		if ringConnection then
			ringConnection:Disconnect()
			ringConnection = nil
		end
	end)

	return track
end

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

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
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
	playFlameDashAnimation(humanoid, character, rootPart)

	local player = context.Player
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

	task.spawn(function()
		local resolveReason = "completed"
		local interrupted = false
		local connection
		local elapsed = 0
		local maxRuntime = math.max(plan.Duration + MAX_RUNTIME_GRACE, 0.08)
		local burstStartPosition = rootPart.Position

		if plan.Distance <= 0.05 then
			resolveReason = "blocked_at_start"
		else
			if plan.InstantDistance > 0.05 and character.Parent and rootPart.Parent then
				local targetRootPosition = startPosition + (plan.Direction * plan.InstantDistance)
				pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
			end

			setHorizontalVelocity(rootPart, plan.Direction * plan.StartDashSpeed)
			burstStartPosition = rootPart.Position

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
	end)

	return startPayload
end

function MeraMeraNoMi.FireBurst(context)
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local abilityConfig = context.AbilityConfig

	playFlameBurstAnimation(humanoid, character, rootPart)

	return {
		Radius = abilityConfig.Radius,
		Duration = abilityConfig.Duration,
	}
end

return MeraMeraNoMi
