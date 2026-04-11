local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MoguBurrowShared = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguBurrowShared")
)

local MoguServer = {}
local BURROW_PROTECTED_UNTIL_ATTRIBUTE = "MoguBurrowProtectedUntil"

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

local function getActiveBurrow(player)
	local burrowState = activeBurrowsByPlayer[player]
	if not burrowState then
		return nil
	end

	if getSharedTimestamp() > (burrowState.EndTime + MoguBurrowShared.GetSurfaceResolveGrace(burrowState.AbilityConfig)) then
		activeBurrowsByPlayer[player] = nil
		clearProtectionState(player)
		return nil
	end

	return burrowState
end

local function buildStartPayload(context, startedAt, endsAt, direction, directionSource)
	local abilityConfig = context.AbilityConfig or {}

	return {
		Phase = "Start",
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
		Phase = "Resolve",
		StartedAt = burrowState.StartedAt,
		EndedAt = endedAt,
		Duration = burrowState.Duration,
		Direction = burrowState.Direction,
		StartPosition = burrowState.StartPosition,
		ActualEndPosition = actualEndPosition,
		ResolveReason = resolveReason,
		ResolveBurstRadius = MoguBurrowShared.GetResolveBurstRadius(abilityConfig),
		EndedEarly = resolveReason ~= "duration_elapsed",
	}
end

function MoguServer.Burrow(context)
	local player = context.Player
	local abilityConfig = context.AbilityConfig or {}
	local activeBurrow = getActiveBurrow(player)
	if activeBurrow then
		activeBurrowsByPlayer[player] = nil
		clearProtectionState(player)

		local endedAt = getSharedTimestamp()
		local resolveReason = endedAt >= activeBurrow.EndTime and "duration_elapsed" or "manual_surface"
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

	activeBurrowsByPlayer[player] = {
		StartedAt = startedAt,
		EndTime = endsAt,
		Duration = duration,
		Direction = direction,
		DirectionSource = directionSource,
		StartPosition = context.RootPart.Position,
		AbilityConfig = abilityConfig,
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

function MoguServer.GetLegacyHandler()
	return MoguServer
end

return MoguServer
