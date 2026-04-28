local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MoguBurrowShared = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguBurrowShared")
)
local MoguAnimationController = require(script.Parent:WaitForChild("MoguAnimationController"))

local MoguServer = {}
local BURROW_PROTECTED_UNTIL_ATTRIBUTE = "MoguBurrowProtectedUntil"
local PHASE_START = "Start"
local PHASE_RESOLVE = "Resolve"
local RESOLVE_REASON_DURATION_ELAPSED = "duration_elapsed"
local RESOLVE_REASON_MANUAL_SURFACE = "manual_surface"
local CLEAR_REASON_EXPIRED = "expired"
local CLEAR_REASON_RESOLVE = "resolve"
local CLEAR_REASON_RUNTIME_RESET = "runtime_reset"

local activeBurrowsByPlayer = setmetatable({}, { __mode = "k" })

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

local function buildStartPayload(context, startedAt, endsAt, direction, directionSource)
	local abilityConfig = context.AbilityConfig or {}

	return {
		Phase = PHASE_START,
		StartedAt = startedAt,
		EndTime = endsAt,
		Duration = endsAt - startedAt,
		MoveSpeed = MoguBurrowShared.GetMoveSpeed(abilityConfig),
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = context.RootPart.Position,
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
			MoguBurrowShared.ResolveSurfaceRootPosition(character, rootPart, actualEndPosition, abilityConfig)
		)
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
	local animationState = MoguAnimationController.PlayBurrowStartAnimation(context.Character, abilityConfig)

	activeBurrowsByPlayer[player] = {
		StartedAt = startedAt,
		EndTime = endsAt,
		Duration = duration,
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = context.RootPart.Position,
		AbilityConfig = abilityConfig,
		AnimationState = animationState,
	}
	setProtectionState(player, endsAt + MoguBurrowShared.GetSurfaceResolveGrace(abilityConfig))

	return buildStartPayload(context, startedAt, endsAt, direction, directionSource), {
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
