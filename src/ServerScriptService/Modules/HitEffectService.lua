local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local HitEffectConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("HitEffects"))

local HitEffectService = {}

local activeStatesByPlayer = {}
local started = false
local sliceServiceCache = nil

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

local function getCharacterContext(player)
	if not player or not player:IsA("Player") then
		return nil, nil, nil
	end

	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return character, nil, nil
	end

	return character, humanoid, rootPart
end

local function clearEffectAttributes(player)
	local attributes = HitEffectConfig.Attributes
	player:SetAttribute(attributes.Type, nil)
	player:SetAttribute(attributes.Until, nil)
	player:SetAttribute(attributes.WalkSpeedMultiplier, nil)
	player:SetAttribute(attributes.JumpMultiplier, nil)
end

local function setEffectAttributes(player, effectName, untilTime, movement)
	local attributes = HitEffectConfig.Attributes
	player:SetAttribute(attributes.Type, effectName)
	player:SetAttribute(attributes.Until, untilTime)
	player:SetAttribute(attributes.WalkSpeedMultiplier, movement.WalkSpeedMultiplier)
	player:SetAttribute(attributes.JumpMultiplier, movement.JumpMultiplier)
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

function HitEffectService.ApplyEffect(player, effectName, options)
	HitEffectService.Start()

	local effectDefinition = HitEffectConfig.GetEffect(effectName)
	if not effectDefinition then
		return false, "unknown_effect"
	end

	local _, humanoid, rootPart = getCharacterContext(player)
	if not humanoid or not rootPart then
		return false, "invalid_target"
	end

	options = if typeof(options) == "table" then options else {}

	local now = os.clock()
	local priority = tonumber(options.Priority) or tonumber(effectDefinition.Priority) or 0
	local activeState = activeStatesByPlayer[player]
	if activeState and activeState.UntilTime > now and (tonumber(activeState.Priority) or 0) > priority then
		return false, "higher_priority_effect_active"
	end

	clearActiveState(player)

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
		activeStatesByPlayer[player] = state
		setEffectAttributes(player, effectName, untilTime, movement)
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

	if forcesCarryDrop then
		local sliceService = getSliceService()
		if sliceService and typeof(sliceService.DropCarriedReward) == "function" then
			dropResponse = sliceService.DropCarriedReward(player, {
				Reason = "HitEffect",
				EffectName = effectName,
				DropPosition = dropPosition,
			})
		end
	end

	applyKnockback(rootPart, options.KnockbackVector or effectDefinition.Knockback)

	if duration > 0 then
		task.delay(duration + 0.05, function()
			clearActiveState(player, state)
		end)
	end

	return true, {
		EffectName = effectName,
		UntilTime = untilTime,
		ForcedCarryDrop = dropResponse and dropResponse.ok == true or false,
	}
end

return HitEffectService
