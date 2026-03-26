local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HazardRuntime = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))

local HieHieNoMi = {}

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

local function resolveFreezeTarget(context, direction, abilityConfig)
	local range = math.max(1, tonumber(abilityConfig.Range) or 0)
	local projectileRadius = math.max(0.25, tonumber(abilityConfig.ProjectileRadius) or 0.8)
	local startPosition = context.RootPart.Position + Vector3.new(0, 1.2, 0) + direction * 3
	local endPosition = startPosition + direction * range
	local searchRadius = math.max(projectileRadius * 1.15, 1)

	local hazardContext, impactPosition = HazardRuntime.FindNearestHazardAlongSegment(
		startPosition,
		endPosition,
		searchRadius,
		{
			RequireCanFreeze = true,
			PlayerRootPosition = context.RootPart.Position,
			MaxPlayerDistance = range + 6,
			ExcludeInstances = { context.Character },
			MaxUniqueHazards = 1,
			MaxSamples = 72,
		}
	)

	return {
		StartPosition = startPosition,
		EndPosition = endPosition,
		HazardContext = hazardContext,
		ImpactPosition = impactPosition,
	}
end

function HieHieNoMi.FreezeShot(context)
	local abilityConfig = context.AbilityConfig
	local direction = getForwardDirection(context.RootPart)
	local range = math.max(1, tonumber(abilityConfig.Range) or 0)
	local projectileSpeed = math.max(1, tonumber(abilityConfig.ProjectileSpeed) or 0)
	local projectileRadius = math.max(0.25, tonumber(abilityConfig.ProjectileRadius) or 0.8)
	local freezeDuration = math.max(0, tonumber(abilityConfig.FreezeDuration) or 0)

	local targetResult = resolveFreezeTarget(context, direction, abilityConfig)
	local hazardContext = targetResult.HazardContext
	local hitPosition = targetResult.ImpactPosition or targetResult.EndPosition
	local hazardEffectApplied = false

	if hazardContext and freezeDuration > 0 then
		hazardEffectApplied = HazardRuntime.Freeze(hazardContext.Root, freezeDuration) == true
	end

	return {
		Direction = direction,
		Range = range,
		ProjectileSpeed = projectileSpeed,
		ProjectileRadius = projectileRadius,
		FreezeDuration = freezeDuration,
		StartPosition = targetResult.StartPosition,
		EndPosition = targetResult.EndPosition,
		HitPosition = hitPosition,
		HazardHit = hazardContext ~= nil,
		HazardEffectApplied = hazardEffectApplied,
	}
end

function HieHieNoMi.IceBoost(context)
	local player = context.Player
	local abilityConfig = context.AbilityConfig
	local duration = math.max(0, tonumber(abilityConfig.Duration) or 0)
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

return HieHieNoMi
