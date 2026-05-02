local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AbilityTargeting = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Shared")
		:WaitForChild("AbilityTargeting")
)
local HazardProtection = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("HazardProtection")
)
local HitEffectConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("HitEffects"))

local HitEffectService = {}

local activeStatesByPlayer = {}
local started = false
local sliceServiceCache = nil
local brainrotInteractionCache = nil
local temporaryRagdollServiceCache = nil

local function getTemporaryRagdollService()
	if temporaryRagdollServiceCache ~= nil then
		return if temporaryRagdollServiceCache == false then nil else temporaryRagdollServiceCache
	end

	local ok, service = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TemporaryRagdollService"))
	end)

	if not ok then
		warn(string.format("[HitEffectService] Failed to resolve TemporaryRagdollService: %s", tostring(service)))
		temporaryRagdollServiceCache = false
		return nil
	end

	temporaryRagdollServiceCache = service
	return service
end

local function getSliceService()
	if sliceServiceCache ~= nil then
		return if sliceServiceCache == false then nil else sliceServiceCache
	end

	local ok, service = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
	end)

	if not ok then
		warn(string.format("[HitEffectService] Failed to resolve GrandLineRushVerticalSliceService: %s", tostring(service)))
		sliceServiceCache = false
		return nil
	end

	sliceServiceCache = service
	return service
end

local function getBrainrotInteraction()
	if brainrotInteractionCache ~= nil then
		return if brainrotInteractionCache == false then nil else brainrotInteractionCache
	end

	local ok, interaction = pcall(function()
		return require(
			ReplicatedStorage:WaitForChild("Modules")
				:WaitForChild("Server")
				:WaitForChild("Brainrot")
				:WaitForChild("Interaction")
		)
	end)

	if not ok then
		warn(string.format("[HitEffectService] Failed to resolve Brainrot Interaction: %s", tostring(interaction)))
		brainrotInteractionCache = false
		return nil
	end

	brainrotInteractionCache = interaction
	return interaction
end

local function getCharacterContext(target)
	local targetContext = AbilityTargeting.GetCharacterContext(target)
	if not targetContext then
		return nil, nil, nil
	end

	return targetContext.Character, targetContext.Humanoid, targetContext.RootPart, targetContext.Player
end

local function clearEffectAttributes(target)
	if typeof(target) ~= "Instance" then
		return
	end

	local attributes = HitEffectConfig.Attributes
	target:SetAttribute(attributes.Type, nil)
	target:SetAttribute(attributes.Until, nil)
	target:SetAttribute(attributes.WalkSpeedMultiplier, nil)
	target:SetAttribute(attributes.JumpMultiplier, nil)
end

local function setEffectAttributes(target, effectName, untilTime, movement)
	if typeof(target) ~= "Instance" then
		return
	end

	local attributes = HitEffectConfig.Attributes
	target:SetAttribute(attributes.Type, effectName)
	target:SetAttribute(attributes.Until, untilTime)
	target:SetAttribute(attributes.WalkSpeedMultiplier, movement.WalkSpeedMultiplier)
	target:SetAttribute(attributes.JumpMultiplier, movement.JumpMultiplier)
end

local function mergeMovement(baseMovement, overrideMovement)
	local mergedMovement = {}

	if typeof(baseMovement) == "table" then
		for key, value in pairs(baseMovement) do
			mergedMovement[key] = value
		end
	end

	if typeof(overrideMovement) == "table" then
		for key, value in pairs(overrideMovement) do
			mergedMovement[key] = value
		end
	end

	return mergedMovement
end

local function clearActiveState(player, expectedState)
	local activeState = activeStatesByPlayer[player]
	if not activeState or (expectedState ~= nil and activeState ~= expectedState) then
		return
	end

	local humanoid = activeState.Humanoid
	local temporaryRagdoll = activeState.TemporaryRagdoll
	if temporaryRagdoll then
		local ragdollService = getTemporaryRagdollService()
		if ragdollService then
			ragdollService.Restore(temporaryRagdoll)
		end
	end

	if humanoid and humanoid.Parent then
		if activeState.Movement.AutoRotate ~= nil then
			humanoid.AutoRotate = activeState.OriginalAutoRotate
		end

		if activeState.Movement.PlatformStand == true then
			humanoid.PlatformStand = activeState.OriginalPlatformStand
			if activeState.OriginalPlatformStand ~= true and humanoid.Health > 0 then
				humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end
	end

	activeStatesByPlayer[player] = nil
	clearEffectAttributes(player)
end

local function applyKnockback(rootPart, knockbackVector)
	if typeof(knockbackVector) ~= "Vector3" or knockbackVector.Magnitude <= 0.01 then
		return
	end

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		knockbackVector.X,
		math.max(currentVelocity.Y, knockbackVector.Y),
		knockbackVector.Z
	)
end

local function forceDropCarriedItems(player, dropPosition, effectName)
	local droppedAny = false
	local dropResponse = nil

	local sliceService = getSliceService()
	if sliceService and typeof(sliceService.DropCarriedReward) == "function" then
		dropResponse = sliceService.DropCarriedReward(player, {
			Reason = "HitEffect",
			EffectName = effectName,
			DropPosition = dropPosition,
		})
		if dropResponse and dropResponse.ok == true then
			droppedAny = true
		end
	end

	local brainrotInteraction = getBrainrotInteraction()
	if brainrotInteraction
		and typeof(brainrotInteraction.GetActiveContext) == "function"
		and typeof(brainrotInteraction.DropHeldAtPosition) == "function"
	then
		local context = brainrotInteraction.GetActiveContext()
		local isHoldingBrainrot = player:GetAttribute("CarriedBrainrot") ~= nil
		if not isHoldingBrainrot and typeof(brainrotInteraction.HasHeld) == "function" then
			isHoldingBrainrot = brainrotInteraction.HasHeld(context, player) == true
		end

		if isHoldingBrainrot and brainrotInteraction.DropHeldAtPosition(context, player, nil, dropPosition) == true then
			droppedAny = true
		end
	end

	return {
		ok = droppedAny,
		RewardResponse = dropResponse,
	}
end

local function hookPlayer(player)
	player.CharacterAdded:Connect(function()
		clearActiveState(player)
		clearEffectAttributes(player)
	end)
end

function HitEffectService.Start()
	if started then
		return
	end

	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
		clearEffectAttributes(player)
	end

	Players.PlayerAdded:Connect(function(player)
		hookPlayer(player)
		clearEffectAttributes(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearActiveState(player)
	end)
end

function HitEffectService.GetActiveEffect(player)
	local activeState = activeStatesByPlayer[player]
	if not activeState then
		return nil
	end

	if activeState.UntilTime <= os.clock() then
		clearActiveState(player, activeState)
		return nil
	end

	return activeState
end

function HitEffectService.ApplyEffect(target, effectName, options)
	HitEffectService.Start()

	local effectDefinition = HitEffectConfig.GetEffect(effectName)
	if not effectDefinition then
		return false, "unknown_effect"
	end

	local character, humanoid, rootPart, targetPlayer = getCharacterContext(target)
	if not humanoid or not rootPart then
		return false, "invalid_target"
	end

	options = if typeof(options) == "table" then options else {}
	local targetContext = {
		Instance = target,
		Player = targetPlayer,
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
	}
	local isHazardProtected, protectionReason = HazardProtection.IsProtected(target, {
		TargetContext = targetContext,
		Position = rootPart.Position,
		EffectName = effectName,
		IgnoreProtection = options.IgnoreProtection,
		IgnoreHazardProtection = options.IgnoreHazardProtection,
	})
	if isHazardProtected then
		return false, protectionReason or "hazard_protected"
	end

	local now = os.clock()
	local priority = tonumber(options.Priority) or tonumber(effectDefinition.Priority) or 0
	local activeState = activeStatesByPlayer[target]
	if activeState and activeState.UntilTime > now and (tonumber(activeState.Priority) or 0) > priority then
		return false, "higher_priority_effect_active"
	end

	clearActiveState(target)

	local duration = math.max(0, tonumber(options.Duration) or tonumber(effectDefinition.Duration) or 0)
	local movement = mergeMovement(effectDefinition.Movement, options.Movement)
	local untilTime = now + duration

	local state = {
		EffectName = effectName,
		UntilTime = untilTime,
		Priority = priority,
		Humanoid = humanoid,
		Movement = movement,
		OriginalAutoRotate = humanoid.AutoRotate,
		OriginalPlatformStand = humanoid.PlatformStand,
	}

	if duration > 0 then
		activeStatesByPlayer[target] = state
		setEffectAttributes(target, effectName, untilTime, movement)
	end

	if options.RagdollJoints == true then
		local ragdollService = getTemporaryRagdollService()
		if ragdollService and character then
			state.TemporaryRagdoll = ragdollService.Apply(character, duration, {
				Impulse = options.RagdollImpulse,
				NetworkOwner = targetPlayer,
			})
		end
	end

	if movement.AutoRotate ~= nil then
		humanoid.AutoRotate = movement.AutoRotate
	end

	if movement.PlatformStand == true then
		humanoid.PlatformStand = true
	end

	if movement.State and humanoid.Health > 0 then
		humanoid:ChangeState(movement.State)
	end

	local dropPosition = if typeof(options.DropPosition) == "Vector3" then options.DropPosition else rootPart.Position
	local dropResponse = nil
	local forcesCarryDrop = if options.ForcesCarryDrop ~= nil
		then options.ForcesCarryDrop == true
		else effectDefinition.ForcesCarryDrop == true

	if forcesCarryDrop and targetPlayer then
		dropResponse = forceDropCarriedItems(targetPlayer, dropPosition, effectName)
	end

	applyKnockback(rootPart, options.KnockbackVector or effectDefinition.Knockback)

	if duration > 0 then
		task.delay(duration + 0.05, function()
			clearActiveState(target, state)
		end)
	end

	return true, {
		EffectName = effectName,
		UntilTime = untilTime,
		ForcedCarryDrop = dropResponse and dropResponse.ok == true or false,
	}
end

return HitEffectService
