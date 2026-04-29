local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
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

local activeBurrowsByPlayer = setmetatable({}, { __mode = "k" })

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

local function faceCharacterAlongDirection(character, rootPart, direction)
	local planarDirection = getPlanarDirection(direction)
	if not character or not rootPart or not planarDirection then
		return
	end

	local rootPosition = rootPart.Position
	local targetRootCFrame = CFrame.lookAt(rootPosition, rootPosition + planarDirection, Vector3.yAxis)
	local pivotToRoot = character:GetPivot():ToObjectSpace(rootPart.CFrame)
	character:PivotTo(targetRootCFrame * pivotToRoot:Inverse())
	rootPart.AssemblyAngularVelocity = Vector3.zero
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
		EndedEarly = resolveReason ~= RESOLVE_REASON_DURATION_ELAPSED,
	}
end

function MoguServer.Burrow(context)
	local player = context.Player
	local abilityConfig = context.AbilityConfig or {}
	local activeBurrow = getActiveBurrow(player)
	if activeBurrow then
		clearActiveBurrow(player, CLEAR_REASON_RESOLVE)
		local resolveDirection, resolveDirectionSource =
			MoguBurrowShared.ResolveDirection(context.Humanoid, context.RootPart, context.RequestPayload)
		activeBurrow.Direction = resolveDirection
		activeBurrow.DirectionSource = resolveDirectionSource
		faceCharacterAlongDirection(context.Character, context.RootPart, activeBurrow.Direction)
		MoguAnimationController.PlayBurrowResolveAnimation(context.Character, abilityConfig)

		local endedAt = getSharedTimestamp()
		local resolveReason = endedAt >= activeBurrow.EndTime and RESOLVE_REASON_DURATION_ELAPSED or RESOLVE_REASON_MANUAL_SURFACE
		return buildResolvePayload(context, activeBurrow, endedAt, resolveReason), {
			ApplyCooldown = true,
			CooldownDuration = tonumber(abilityConfig.Cooldown) or 0,
		}
	end

	local startedAt = getSharedTimestamp()
	local duration = MoguBurrowShared.GetBurrowDuration(abilityConfig)
	local endsAt = startedAt + duration
	local direction, directionSource =
		MoguBurrowShared.ResolveDirection(context.Humanoid, context.RootPart, context.RequestPayload)
	local startSurfacePosition, hasStartSurface = MoguBurrowShared.ResolveSurfaceRootPosition(
		context.Character,
		context.RootPart,
		context.RootPart.Position,
		abilityConfig,
		context.RootPart.Position
	)
	if not hasStartSurface or not startSurfacePosition then
		return nil, {
			ApplyCooldown = false,
			SuppressActivatedEvent = true,
		}
	end

	faceCharacterAlongDirection(context.Character, context.RootPart, direction)
	local animationState = MoguAnimationController.PlayBurrowStartAnimation(context.Character, abilityConfig)

	local burrowState = {
		StartedAt = startedAt,
		EndTime = endsAt,
		Duration = duration,
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = startSurfacePosition,
		LastSafeSurfaceRootPosition = startSurfacePosition,
		AbilityConfig = abilityConfig,
		AnimationState = animationState,
	}
	activeBurrowsByPlayer[player] = burrowState
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
