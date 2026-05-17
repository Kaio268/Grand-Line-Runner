local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local MoguBurrowShared = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguBurrowShared")
)
local MoguAnimationController = require(script.Parent:WaitForChild("MoguAnimationController"))

local MoguServer = {}
local BURROW_PROTECTED_UNTIL_ATTRIBUTE = "MoguBurrowProtectedUntil"
local WORKSPACE_ANIMATION_RIG_NAME = "Mogu"
local PHASE_START = "Start"
local PHASE_RESOLVE = "Resolve"
local RESOLVE_REASON_DURATION_ELAPSED = "duration_elapsed"
local RESOLVE_REASON_MANUAL_SURFACE = "manual_surface"
local CLEAR_REASON_EXPIRED = "expired"
local CLEAR_REASON_RESOLVE = "resolve"
local CLEAR_REASON_RUNTIME_RESET = "runtime_reset"
local RESOLVE_VALIDATION_DISTANCE_PADDING = 8
local START_POSITION_VALIDATION_DISTANCE = 8
local ZERO_VELOCITY_EPSILON = 0.025
local DEFAULT_MIN_MANUAL_RESOLVE_DELAY = 0.5
local DEBUG_INFO = RunService:IsStudio()
local INFO_COOLDOWN = 0.5
local WARN_COOLDOWN = 3

local activeBurrowsByPlayer = setmetatable({}, { __mode = "k" })

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MoguServer:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MOGU SERVER][WARN] " .. message, ...))
end

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MoguServer:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MOGU SERVER] " .. message, ...))
end

local function getStartAnimationConfig(abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and type(animationConfig.Start) == "table" and animationConfig.Start or {}
end

local function getMinimumManualResolveDelay(abilityConfig)
	local startConfig = getStartAnimationConfig(abilityConfig)
	return math.max(
		0,
		tonumber(abilityConfig and abilityConfig.MinManualResolveDelay)
			or tonumber(startConfig.MinManualResolveDelay)
			or tonumber(startConfig.EntryCueFallbackTime)
			or DEFAULT_MIN_MANUAL_RESOLVE_DELAY
	)
end

local function getPlanarDirection(direction)
	if typeof(direction) ~= "Vector3" then
		return nil
	end

	local planarDirection = Vector3.new(direction.X, 0, direction.Z)
	if planarDirection.Magnitude <= 0.01 then
		return nil
	end

	return planarDirection.Unit
end

local function zeroRootVelocity(rootPart)
	if not rootPart then
		return false
	end

	local wrote = false
	if rootPart.AssemblyLinearVelocity.Magnitude > ZERO_VELOCITY_EPSILON then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		wrote = true
	end
	if rootPart.AssemblyAngularVelocity.Magnitude > ZERO_VELOCITY_EPSILON then
		rootPart.AssemblyAngularVelocity = Vector3.zero
		wrote = true
	end
	return wrote
end

local function getTrustedPredictedStartPosition(requestPayload, rootPart, player)
	if type(requestPayload) ~= "table" or not rootPart then
		return nil, nil
	end

	local predictedStartPosition = requestPayload.PredictedStartPosition
	if typeof(predictedStartPosition) ~= "Vector3" then
		return nil, nil
	end

	local distance = (predictedStartPosition - rootPart.Position).Magnitude
	if distance <= START_POSITION_VALIDATION_DISTANCE then
		return predictedStartPosition, distance
	end

	logWarn(
		"predicted start rejected player=%s distance=%.2f limit=%.2f",
		player and player.Name or "<nil>",
		distance,
		START_POSITION_VALIDATION_DISTANCE
	)
	return nil, distance
end

local function faceCharacterAlongDirection(character, rootPart, direction)
	local planarDirection = getPlanarDirection(direction)
	if not character or not rootPart or not planarDirection then
		return
	end

	local rootPosition = rootPart.Position
	local targetRootCFrame = CFrame.lookAt(rootPosition, rootPosition + planarDirection, Vector3.yAxis)
	local pivotToRoot = character:GetPivot():ToObjectSpace(rootPart.CFrame)
	character:PivotTo(targetRootCFrame * pivotToRoot:Inverse())
	zeroRootVelocity(rootPart)
end

local function getPlanarDelta(fromPosition, toPosition)
	if typeof(fromPosition) ~= "Vector3" or typeof(toPosition) ~= "Vector3" then
		return nil
	end

	return Vector3.new(toPosition.X - fromPosition.X, 0, toPosition.Z - fromPosition.Z)
end

local function clampResolvePositionToAuthorizedDistance(burrowState, requestedEndPosition, endedAt)
	local startPosition = burrowState and burrowState.StartPosition
	if typeof(startPosition) ~= "Vector3" or typeof(requestedEndPosition) ~= "Vector3" then
		return requestedEndPosition, 0
	end

	local planarDelta = getPlanarDelta(startPosition, requestedEndPosition)
	if not planarDelta or planarDelta.Magnitude <= 0.01 then
		return requestedEndPosition, 0
	end

	local elapsed = math.clamp(
		(tonumber(endedAt) or tonumber(burrowState.StartedAt) or 0)
			- (tonumber(burrowState.StartedAt) or tonumber(endedAt) or 0),
		0,
		math.max(0, tonumber(burrowState.Duration) or 0) + MoguBurrowShared.GetSurfaceResolveGrace(burrowState.AbilityConfig)
	)
	local maxTravelDistance = (
		math.max(0, tonumber(burrowState.MoveSpeed) or MoguBurrowShared.GetMoveSpeed(burrowState.AbilityConfig))
			* elapsed
	)
		+ RESOLVE_VALIDATION_DISTANCE_PADDING
	local planarDistance = planarDelta.Magnitude
	if planarDistance <= maxTravelDistance then
		return requestedEndPosition, 0
	end

	local clampedPlanarDelta = planarDelta.Unit * maxTravelDistance
	return Vector3.new(
		startPosition.X + clampedPlanarDelta.X,
		requestedEndPosition.Y,
		startPosition.Z + clampedPlanarDelta.Z
	), planarDistance - maxTravelDistance
end

local function hideWorkspaceAnimationRig(instance)
	if not instance or instance.Name ~= WORKSPACE_ANIMATION_RIG_NAME or not instance:FindFirstChild("AnimSaves") then
		return
	end

	instance:SetAttribute("MoguRuntimeHidden", true)
	local humanoids = {}
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.Transparency = 1
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") then
			descendant.Enabled = false
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			humanoids[#humanoids + 1] = descendant
		end
	end

	for _, humanoid in ipairs(humanoids) do
		humanoid:Destroy()
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
end

hideWorkspaceAnimationRig(Workspace:FindFirstChild(WORKSPACE_ANIMATION_RIG_NAME))
Workspace.ChildAdded:Connect(hideWorkspaceAnimationRig)

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function clearProtectionState(player)
	if not player or not player:IsA("Player") then
		return
	end

	player:SetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE, nil)
end

local function setProtectionState(player, untilTimestamp)
	if not player or not player:IsA("Player") then
		return
	end

	if typeof(untilTimestamp) ~= "number" or untilTimestamp <= getSharedTimestamp() then
		clearProtectionState(player)
		return
	end

	player:SetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE, untilTimestamp)
end

local function clearActiveBurrow(player, reason)
	if not player or not player:IsA("Player") then
		return nil
	end

	local burrowState = activeBurrowsByPlayer[player]
	activeBurrowsByPlayer[player] = nil
	clearProtectionState(player)

	if not burrowState then
		return nil
	end

	MoguAnimationController.StopAnimation(burrowState.AnimationState, reason)
	return burrowState
end

local function getActiveBurrow(player)
	local burrowState = activeBurrowsByPlayer[player]
	if not burrowState then
		return nil
	end

	if getSharedTimestamp() > (burrowState.EndTime + MoguBurrowShared.GetSurfaceResolveGrace(burrowState.AbilityConfig)) then
		clearActiveBurrow(player, CLEAR_REASON_EXPIRED)
		return nil
	end

	return burrowState
end

local function buildStartPayload(context, startedAt, endsAt, direction, directionSource, startPosition)
	local abilityConfig = context.AbilityConfig or {}
	local resolvedStartPosition = startPosition or context.RootPart.Position

	return {
		Phase = PHASE_START,
		StartedAt = startedAt,
		EndTime = endsAt,
		Duration = endsAt - startedAt,
		MoveSpeed = MoguBurrowShared.GetMoveSpeed(abilityConfig),
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = resolvedStartPosition,
		EntryBurstRadius = MoguBurrowShared.GetEntryBurstRadius(abilityConfig),
		ResolveBurstRadius = MoguBurrowShared.GetResolveBurstRadius(abilityConfig),
		HazardProtectionRadius = math.max(0, tonumber(abilityConfig.HazardProtectionRadius) or 0),
		ConcealTransparency = MoguBurrowShared.GetConcealTransparency(abilityConfig),
		TrailInterval = MoguBurrowShared.GetTrailInterval(abilityConfig),
	}
end

local function buildResolvePayload(context, burrowState, endedAt, resolveReason)
	local abilityConfig = context.AbilityConfig or {}
	local rootPart = context.RootPart
	local character = context.Character
	local actualEndPosition = rootPart and rootPart.Position or burrowState.StartPosition
	local resolveCorrectionDistance = 0
	actualEndPosition, resolveCorrectionDistance =
		clampResolvePositionToAuthorizedDistance(burrowState, actualEndPosition, endedAt)
	if character and rootPart then
		actualEndPosition = select(
			1,
			MoguBurrowShared.ResolveSurfaceRootPosition(
				character,
				rootPart,
				actualEndPosition,
				abilityConfig,
				burrowState.LastSafeSurfaceRootPosition or burrowState.StartPosition
			)
		) or burrowState.LastSafeSurfaceRootPosition or burrowState.StartPosition or actualEndPosition
	end
	if context.Player then
		context.Player:SetAttribute("MoguResolveCorrectionDistance", resolveCorrectionDistance)
	end

	return {
		Phase = PHASE_RESOLVE,
		StartedAt = burrowState.StartedAt,
		EndedAt = endedAt,
		Duration = burrowState.Duration,
		Direction = burrowState.Direction,
		StartPosition = burrowState.StartPosition,
		ActualEndPosition = actualEndPosition,
		ResolveReason = resolveReason,
		ResolveBurstRadius = MoguBurrowShared.GetResolveBurstRadius(abilityConfig),
		ResolveCorrectionDistance = resolveCorrectionDistance,
		EndedEarly = resolveReason ~= RESOLVE_REASON_DURATION_ELAPSED,
	}
end

function MoguServer.Burrow(context)
	local player = context.Player
	local abilityConfig = context.AbilityConfig or {}
	local activeBurrow = getActiveBurrow(player)
	if activeBurrow then
		local endedAt = getSharedTimestamp()
		local minResolveDelay = getMinimumManualResolveDelay(activeBurrow.AbilityConfig or abilityConfig)
		local resolveReadyAt = (tonumber(activeBurrow.StartedAt) or endedAt) + minResolveDelay
		if endedAt < resolveReadyAt then
			logInfo(
				"resolve ignored player=%s reason=resolve_not_ready elapsed=%.2f readyIn=%.2f",
				player and player.Name or "<nil>",
				endedAt - (tonumber(activeBurrow.StartedAt) or endedAt),
				resolveReadyAt - endedAt
			)
			return nil, {
				ApplyCooldown = false,
				DenyReason = "ResolveNotReady",
			}
		end

		clearActiveBurrow(player, CLEAR_REASON_RESOLVE)
		local resolveDirection, resolveDirectionSource =
			MoguBurrowShared.ResolveDirection(context.Humanoid, context.RootPart, context.RequestPayload)
		activeBurrow.Direction = resolveDirection
		activeBurrow.DirectionSource = resolveDirectionSource
		faceCharacterAlongDirection(context.Character, context.RootPart, activeBurrow.Direction)
		logInfo(
			"server resolve animation suppressed player=%s reason=client_visual_path",
			player and player.Name or "<nil>"
		)

		local resolveReason = endedAt >= activeBurrow.EndTime and RESOLVE_REASON_DURATION_ELAPSED or RESOLVE_REASON_MANUAL_SURFACE
		return buildResolvePayload(context, activeBurrow, endedAt, resolveReason), {
			ApplyCooldown = true,
			CooldownDuration = tonumber(abilityConfig.Cooldown) or 0,
		}
	end

	local rootSpeedBeforeHardStop = context.RootPart.AssemblyLinearVelocity.Magnitude
	local rootAngularSpeedBeforeHardStop = context.RootPart.AssemblyAngularVelocity.Magnitude
	zeroRootVelocity(context.RootPart)
	logInfo(
		"startup stabilization applied player=%s speed=%.2f angular=%.2f",
		player and player.Name or "<nil>",
		rootSpeedBeforeHardStop,
		rootAngularSpeedBeforeHardStop
	)

	local startedAt = getSharedTimestamp()
	local duration = MoguBurrowShared.GetBurrowDuration(abilityConfig)
	local endsAt = startedAt + duration
	local direction, directionSource =
		MoguBurrowShared.ResolveDirection(context.Humanoid, context.RootPart, context.RequestPayload)
	local predictedStartPosition, predictedStartDistance =
		getTrustedPredictedStartPosition(context.RequestPayload, context.RootPart, player)
	if predictedStartDistance then
		logInfo(
			"predicted vs authoritative start player=%s distance=%.2f trusted=%s",
			player and player.Name or "<nil>",
			predictedStartDistance,
			tostring(predictedStartPosition ~= nil)
		)
	end
	local requestedStartPosition = predictedStartPosition or context.RootPart.Position
	local startSurfacePosition, hasStartSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
		context.Character,
		context.RootPart,
		requestedStartPosition,
		abilityConfig,
		context.RootPart.Position,
		{
			AllowActivationDrop = true,
		}
	)
	if (not hasStartSurface or not startSurfacePosition) and predictedStartPosition then
		logWarn(
			"predicted start surface probe failed player=%s retrying server root",
			player and player.Name or "<nil>"
		)
		startSurfacePosition, hasStartSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
			context.Character,
			context.RootPart,
			context.RootPart.Position,
			abilityConfig,
			context.RootPart.Position,
			{
				AllowActivationDrop = true,
			}
		)
	end
	if not hasStartSurface or not startSurfacePosition then
		logWarn(
			"server ground probe failed player=%s rootPosition=%s hasStartSurface=%s",
			player and player.Name or "<nil>",
			tostring(context.RootPart and context.RootPart.Position or nil),
			tostring(hasStartSurface)
		)
		return nil, {
			ApplyCooldown = false,
			DenyReason = "NoGround",
		}
	end

	faceCharacterAlongDirection(context.Character, context.RootPart, direction)
	logInfo(
		"server start animation suppressed player=%s reason=client_visual_path",
		player and player.Name or "<nil>"
	)

	local burrowState = {
		StartedAt = startedAt,
		EndTime = endsAt,
		Duration = duration,
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = startSurfacePosition,
		LastSafeSurfaceRootPosition = startSurfacePosition,
		AbilityConfig = abilityConfig,
		MoveSpeed = MoguBurrowShared.GetMoveSpeed(abilityConfig),
	}
	activeBurrowsByPlayer[player] = burrowState
	player:SetAttribute("MoguResolveCorrectionDistance", 0)
	setProtectionState(player, endsAt + MoguBurrowShared.GetSurfaceResolveGrace(abilityConfig))

	return buildStartPayload(context, startedAt, endsAt, direction, directionSource, startSurfacePosition), {
		ApplyCooldown = false,
	}
end

function MoguServer.IsProtected(player)
	if not player or not player:IsA("Player") then
		return false
	end

	local activeBurrow = getActiveBurrow(player)
	if activeBurrow then
		return true
	end

	local protectedUntil = player:GetAttribute(BURROW_PROTECTED_UNTIL_ATTRIBUTE)
	if typeof(protectedUntil) ~= "number" then
		return false
	end

	if protectedUntil > getSharedTimestamp() then
		return true
	end

	clearProtectionState(player)
	return false
end

function MoguServer.ClearRuntimeState(player)
	-- Runtime cleanup should not emit a Resolve payload or start cooldown.
	clearActiveBurrow(player, CLEAR_REASON_RUNTIME_RESET)
end

function MoguServer.GetLegacyHandler()
	return MoguServer
end

return MoguServer
