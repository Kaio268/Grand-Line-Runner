local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MeleeAttackService = {}

local DEFAULTS = {
	MaxRange = 15,
	RagdollTime = 1.2,
	PushSpeed = 10,
	UpPush = 5,
	SwingWindow = 0.2,
	AttackCooldown = 0.25,
	MinFacingDot = 0.05,
}

local slapSoundTemplate = ReplicatedStorage:FindFirstChild("SlapSound")

local playerStates = setmetatable({}, { __mode = "k" })
local toolStates = setmetatable({}, { __mode = "k" })
local ragdollTokens = setmetatable({}, { __mode = "k" })

local function getMergedConfig(config)
	local resolved = table.clone(DEFAULTS)

	if typeof(config) == "table" then
		for key, value in pairs(config) do
			resolved[key] = value
		end
	end

	resolved.MaxRange = math.max(0, tonumber(resolved.MaxRange) or DEFAULTS.MaxRange)
	resolved.RagdollTime = math.max(0, tonumber(resolved.RagdollTime) or DEFAULTS.RagdollTime)
	resolved.PushSpeed = math.max(0, tonumber(resolved.PushSpeed) or DEFAULTS.PushSpeed)
	resolved.UpPush = tonumber(resolved.UpPush) or DEFAULTS.UpPush
	resolved.SwingWindow = math.max(0.05, tonumber(resolved.SwingWindow) or DEFAULTS.SwingWindow)
	resolved.AttackCooldown = math.max(0, tonumber(resolved.AttackCooldown) or DEFAULTS.AttackCooldown)
	resolved.MinFacingDot = math.clamp(tonumber(resolved.MinFacingDot) or DEFAULTS.MinFacingDot, -1, 1)

	return resolved
end

local function getPlayerState(player)
	local state = playerStates[player]
	if state then
		return state
	end

	state = {
		NextAttackAt = 0,
		SwingSequence = 0,
		ActiveSwing = nil,
	}

	playerStates[player] = state
	return state
end

local function playSlapSound(parentPart)
	if not slapSoundTemplate or not parentPart then
		return
	end

	local sound = slapSoundTemplate:Clone()
	sound.Parent = parentPart
	sound:Play()
	Debris:AddItem(sound, 2)
end

local function getAttackerContext(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local character = tool.Parent
	if not character or not character:IsA("Model") then
		return nil
	end

	local player = Players:GetPlayerFromCharacter(character)
	if not player or player.Character ~= character then
		return nil
	end

	if tool.Parent ~= character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil
	end

	local gearsFolder = player:FindFirstChild("Gears")
	local ownedValue = gearsFolder and gearsFolder:FindFirstChild(tool.Name)
	if not ownedValue or not ownedValue:IsA("BoolValue") or ownedValue.Value ~= true then
		return nil
	end

	return player, character, humanoid, rootPart
end

local function beginSwing(player, tool, config)
	local state = getPlayerState(player)
	local now = os.clock()

	if now < state.NextAttackAt then
		return nil
	end

	state.NextAttackAt = now + config.AttackCooldown
	state.SwingSequence += 1

	local swing = {
		Id = state.SwingSequence,
		Tool = tool,
		StartedAt = now,
		ExpiresAt = now + config.SwingWindow,
		Consumed = false,
		HitTargets = {},
	}

	state.ActiveSwing = swing

	task.delay(config.SwingWindow + 0.05, function()
		if state.ActiveSwing == swing then
			state.ActiveSwing = nil
		end
	end)

	return swing
end

local function isSwingActive(player, swing, tool)
	if not swing or swing.Tool ~= tool or swing.Consumed then
		return false
	end

	local state = getPlayerState(player)
	if state.ActiveSwing ~= swing then
		return false
	end

	return os.clock() <= swing.ExpiresAt
end

local function findTargetFromRaycast(attackerCharacter, attackerRootPart, tool, config)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { attackerCharacter, tool }
	params.IgnoreWater = true

	local direction = attackerRootPart.CFrame.LookVector * config.MaxRange
	local result = Workspace:Raycast(attackerRootPart.Position, direction, params)
	if not result then
		return nil
	end

	local hitPart = result.Instance
	if not hitPart or not hitPart:IsA("BasePart") then
		return nil
	end

	return hitPart:FindFirstAncestorOfClass("Model")
end

local function getValidatedTarget(player, attackerCharacter, attackerRootPart, tool, swing, config)
	local targetCharacter = findTargetFromRaycast(attackerCharacter, attackerRootPart, tool, config)
	if not targetCharacter or targetCharacter == attackerCharacter then
		return nil
	end

	local targetPlayer = Players:GetPlayerFromCharacter(targetCharacter)
	if not targetPlayer or targetPlayer == player then
		return nil
	end

	local targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
	local targetRootPart = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHumanoid or targetHumanoid.Health <= 0 or not targetRootPart then
		return nil
	end

	if swing.HitTargets[targetHumanoid] then
		return nil
	end

	local offset = targetRootPart.Position - attackerRootPart.Position
	local distance = offset.Magnitude
	if distance <= 0 or distance > config.MaxRange then
		return nil
	end

	local facingDot = attackerRootPart.CFrame.LookVector:Dot(offset.Unit)
	if facingDot < config.MinFacingDot then
		return nil
	end

	return targetPlayer, targetCharacter, targetHumanoid, targetRootPart
end

local function applyRagdollAndPush(attackerRootPart, targetHumanoid, targetRootPart, config)
	local token = (ragdollTokens[targetHumanoid] or 0) + 1
	ragdollTokens[targetHumanoid] = token

	local originalPlatformStand = targetHumanoid.PlatformStand
	local originalAutoRotate = targetHumanoid.AutoRotate

	targetHumanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
	targetHumanoid.PlatformStand = true
	targetHumanoid.AutoRotate = false

	pcall(function()
		targetRootPart:SetNetworkOwner(nil)
	end)

	local mass = targetRootPart.AssemblyMass
	local forward = attackerRootPart.CFrame.LookVector
	local impulse = (forward * (mass * config.PushSpeed)) + Vector3.new(0, mass * config.UpPush, 0)

	targetRootPart:ApplyImpulse(impulse)
	playSlapSound(targetRootPart)

	task.delay(config.RagdollTime, function()
		if ragdollTokens[targetHumanoid] ~= token then
			return
		end

		if not targetHumanoid.Parent or not targetRootPart.Parent then
			return
		end

		targetHumanoid.PlatformStand = originalPlatformStand
		targetHumanoid.AutoRotate = originalAutoRotate

		if targetHumanoid.Health > 0 and originalPlatformStand ~= true then
			targetHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end

		local targetPlayer = Players:GetPlayerFromCharacter(targetHumanoid.Parent)
		if targetPlayer then
			pcall(function()
				targetRootPart:SetNetworkOwner(targetPlayer)
			end)
		end
	end)
end

local function handleToolActivated(tool)
	local toolState = toolStates[tool]
	if not toolState then
		return
	end

	local config = toolState.Config
	local player, attackerCharacter, _, attackerRootPart = getAttackerContext(tool)
	if not player then
		return
	end

	local swing = beginSwing(player, tool, config)
	if not swing or not isSwingActive(player, swing, tool) then
		return
	end

	local _, _, targetHumanoid, targetRootPart =
		getValidatedTarget(player, attackerCharacter, attackerRootPart, tool, swing, config)
	if not targetHumanoid or not targetRootPart then
		return
	end

	swing.HitTargets[targetHumanoid] = true
	swing.Consumed = true

	applyRagdollAndPush(attackerRootPart, targetHumanoid, targetRootPart, config)
end

function MeleeAttackService.BindTool(tool, config)
	if not tool or not tool:IsA("Tool") then
		return
	end

	if toolStates[tool] then
		return
	end

	toolStates[tool] = {
		Config = getMergedConfig(config),
	}

	tool.Activated:Connect(function()
		handleToolActivated(tool)
	end)
end

return MeleeAttackService
