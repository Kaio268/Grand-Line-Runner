local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))
local DevilFruitConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits")
)
local SharedDevilFruitModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared")
local AnimationRegistry = require(SharedDevilFruitModules:WaitForChild("AnimationRegistry"))
local DevilFruitRemotes = require(SharedDevilFruitModules:WaitForChild("DevilFruitRemotes"))
local ToriShared = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Tori"):WaitForChild("Shared"):WaitForChild("ToriShared")
)

local ToriPassiveService = {}

local PHOENIX_REBIRTH_KEY = "PhoenixRebirth"
local PHOENIX_REBIRTH_ABILITY = "PhoenixRebirth"
local PHOENIX_REBIRTH = ToriShared.Passives.PhoenixRebirth
local MIN_STABILIZED_HEALTH = 1
local REBIRTH_GROUND_RAY_HEIGHT = 6
local REBIRTH_GROUND_RAY_DEPTH = 40
local REBIRTH_STABILIZED_STATES = {
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Physics,
}

local started = false
local statesByPlayer = {}

local function getNow()
	return Workspace:GetServerTimeNow()
end

local function copyStringArray(value, fallback)
	local result = {}
	if type(value) == "table" then
		for _, item in ipairs(value) do
			if typeof(item) == "string" and item ~= "" then
				result[#result + 1] = item
			end
		end
	end

	if #result > 0 then
		return result
	end

	if type(fallback) == "table" then
		for _, item in ipairs(fallback) do
			if typeof(item) == "string" and item ~= "" then
				result[#result + 1] = item
			end
		end
	end

	return result
end

local function resolveRegistryNode(logicalKey)
	if typeof(logicalKey) ~= "string" or logicalKey == "" then
		return nil
	end

	local node = AnimationRegistry
	for segment in logicalKey:gmatch("[^%.]+") do
		if type(node) ~= "table" then
			return nil
		end

		node = node[segment]
	end

	return type(node) == "table" and node or nil
end

local function resolveInstanceByPath(path)
	if type(path) ~= "table" then
		return nil
	end

	local current = ReplicatedStorage
	for _, segment in ipairs(path) do
		if typeof(segment) ~= "string" or segment == "" then
			return nil
		end

		current = current and current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	return current
end

local function buildNameSet(names)
	local nameSet = {}
	for _, name in ipairs(names or {}) do
		if typeof(name) == "string" and name ~= "" then
			nameSet[name] = true
		end
	end
	return nameSet
end

local function getKeyframeMarkerTime(sequence, markerNames)
	if not sequence or not sequence:IsA("KeyframeSequence") then
		return nil
	end

	local markerSet = buildNameSet(markerNames)
	local earliestTime = nil
	for _, keyframe in ipairs(sequence:GetKeyframes()) do
		if markerSet[keyframe.Name] then
			earliestTime = math.min(earliestTime or keyframe.Time, keyframe.Time)
		end

		for _, marker in ipairs(keyframe:GetMarkers()) do
			if markerSet[marker.Name] then
				earliestTime = math.min(earliestTime or keyframe.Time, keyframe.Time)
			end
		end
	end

	return earliestTime
end

local function resolveReviveMarkerDelay(animationKey, markerNames)
	local node = resolveRegistryNode(animationKey)
	if not node then
		return nil
	end

	local candidatePaths = {}
	if type(node.KeyframeSequencePath) == "table" then
		candidatePaths[#candidatePaths + 1] = node.KeyframeSequencePath
	end
	if type(node.FallbackKeyframeSequencePaths) == "table" then
		for _, path in ipairs(node.FallbackKeyframeSequencePaths) do
			candidatePaths[#candidatePaths + 1] = path
		end
	end

	for _, path in ipairs(candidatePaths) do
		local sequence = resolveInstanceByPath(path)
		local markerTime = getKeyframeMarkerTime(sequence, markerNames)
		if markerTime then
			return markerTime
		end
	end

	return nil
end

local function getPhoenixRebirthConfig()
	local fruitConfig = DevilFruitConfig.GetFruit(ToriShared.FruitName)
	local passiveConfig = fruitConfig and fruitConfig.Passives and fruitConfig.Passives[PHOENIX_REBIRTH_KEY] or nil
	local animationKey = tostring(passiveConfig and passiveConfig.AnimationKey or PHOENIX_REBIRTH.AnimationKey)
	local markerNames = copyStringArray(
		passiveConfig and passiveConfig.ReviveMarkerNames,
		PHOENIX_REBIRTH.ReviveMarkerNames
	)
	local animationDuration = math.max(
		0.1,
		tonumber(passiveConfig and passiveConfig.AnimationDuration) or PHOENIX_REBIRTH.AnimationDuration
	)
	local configuredReviveDelay = math.max(
		0,
		tonumber(passiveConfig and passiveConfig.ReviveDelay)
			or tonumber(passiveConfig and passiveConfig.RestoreDelay)
			or PHOENIX_REBIRTH.ReviveDelay
			or PHOENIX_REBIRTH.RestoreDelay
	)
	local markerReviveDelay = resolveReviveMarkerDelay(animationKey, markerNames)
	local reviveDelay = math.clamp(markerReviveDelay or configuredReviveDelay, 0, animationDuration)

	return {
		ActivationDelay = math.max(
			0,
			tonumber(passiveConfig and passiveConfig.ActivationDelay) or PHOENIX_REBIRTH.ActivationDelay or 0
		),
		RestoreDelay = reviveDelay,
		ReviveDelay = reviveDelay,
		AnimationDuration = math.max(animationDuration, reviveDelay),
		ImmunityDuration = math.max(
			0,
			tonumber(passiveConfig and passiveConfig.ImmunityDuration) or PHOENIX_REBIRTH.ImmunityDuration
		),
		StabilizeHealthPercent = math.max(
			0,
			tonumber(passiveConfig and passiveConfig.StabilizeHealthPercent) or PHOENIX_REBIRTH.StabilizeHealthPercent
		),
		RestoreHealthPercent = math.max(
			0.05,
			tonumber(passiveConfig and passiveConfig.RestoreHealthPercent) or PHOENIX_REBIRTH.RestoreHealthPercent
		),
		AnimationKey = animationKey,
		ReviveMarkerNames = markerNames,
	}
end

local function isToriEquipped(player)
	return DevilFruitService.GetEquippedFruit(player) == ToriShared.FruitName
end

local function disconnectConnections(connectionTable)
	for _, connection in ipairs(connectionTable or {}) do
		connection:Disconnect()
	end
end

local function clearPlayerAttributes(player)
	if not player then
		return
	end

	player:SetAttribute(PHOENIX_REBIRTH.PendingUntilAttribute, nil)
	player:SetAttribute(PHOENIX_REBIRTH.ImmuneUntilAttribute, nil)
	player:SetAttribute(PHOENIX_REBIRTH.TriggeredAtAttribute, nil)
	player:SetAttribute(PHOENIX_REBIRTH.ReviveAtAttribute, nil)
	player:SetAttribute(PHOENIX_REBIRTH.EndsAtAttribute, nil)
	player:SetAttribute(PHOENIX_REBIRTH.UsedAttribute, false)
end

local function syncPlayerAttributes(player, state)
	if not player then
		return
	end

	local now = getNow()
	local pendingUntil = state and state.PendingUntil or 0
	local immuneUntil = state and state.ImmuneUntil or 0
	local reviveAt = state and state.ReviveAt or 0
	local endsAt = state and state.EndsAt or 0

	player:SetAttribute(PHOENIX_REBIRTH.UsedAttribute, state and state.Used == true or false)
	player:SetAttribute(PHOENIX_REBIRTH.PendingUntilAttribute, pendingUntil > now and pendingUntil or nil)
	player:SetAttribute(PHOENIX_REBIRTH.ImmuneUntilAttribute, immuneUntil > now and immuneUntil or nil)
	player:SetAttribute(PHOENIX_REBIRTH.ReviveAtAttribute, reviveAt > now and reviveAt or nil)
	player:SetAttribute(PHOENIX_REBIRTH.EndsAtAttribute, endsAt > now and endsAt or nil)
end

local stopRebirthStabilization

local function cleanupState(player)
	local state = statesByPlayer[player]
	if not state then
		clearPlayerAttributes(player)
		return
	end

	if stopRebirthStabilization then
		stopRebirthStabilization(state)
	end
	disconnectConnections(state.Connections)
	statesByPlayer[player] = nil
	clearPlayerAttributes(player)
end

local function getRootPart(state)
	local rootPart = state and state.RootPart
	if rootPart and rootPart.Parent then
		return rootPart
	end

	local character = state and state.Character
	if not character or character.Parent == nil then
		return nil
	end

	rootPart = character:FindFirstChild("HumanoidRootPart")
	state.RootPart = rootPart
	return rootPart
end

local function getHumanoid(state)
	local humanoid = state and state.Humanoid
	if humanoid and humanoid.Parent then
		return humanoid
	end

	local character = state and state.Character
	if not character or character.Parent == nil then
		return nil
	end

	humanoid = character:FindFirstChildOfClass("Humanoid")
	state.Humanoid = humanoid
	return humanoid
end

local function restoreHealth(state, health)
	local humanoid = getHumanoid(state)
	if not humanoid then
		return false
	end

	local targetHealth = math.clamp(health, 1, math.max(humanoid.MaxHealth, 1))
	state.InternalUpdate = true
	humanoid.Health = targetHealth
	state.InternalUpdate = false
	state.LastHealth = humanoid.Health
	return true
end

local function getPlanarLookDirection(rootPart)
	local lookVector = rootPart and rootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
	local planarLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if planarLook.Magnitude <= 0.01 then
		return Vector3.new(0, 0, -1)
	end

	return planarLook.Unit
end

local function buildCharacterRaycastParams(character)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = character and { character } or {}
	raycastParams.IgnoreWater = true
	return raycastParams
end

local function getGroundedRootPosition(state, rootPart, humanoid)
	local character = state and state.Character
	local rayOrigin = rootPart.Position + Vector3.new(0, REBIRTH_GROUND_RAY_HEIGHT, 0)
	local rayDirection = Vector3.new(0, -(REBIRTH_GROUND_RAY_HEIGHT + REBIRTH_GROUND_RAY_DEPTH), 0)
	local result = Workspace:Raycast(rayOrigin, rayDirection, buildCharacterRaycastParams(character))
	if not result then
		return rootPart.Position
	end

	local rootHalfHeight = math.max(0.5, rootPart.Size.Y * 0.5)
	local hipHeight = math.max(0, tonumber(humanoid and humanoid.HipHeight) or 0)
	local targetY = result.Position.Y + rootHalfHeight + hipHeight
	return Vector3.new(rootPart.Position.X, targetY, rootPart.Position.Z)
end

local function setRootUprightAndGrounded(state)
	local rootPart = getRootPart(state)
	local humanoid = getHumanoid(state)
	if not rootPart or not humanoid then
		return
	end

	local position = getGroundedRootPosition(state, rootPart, humanoid)
	local lookDirection = getPlanarLookDirection(rootPart)
	rootPart.CFrame = CFrame.lookAt(position, position + lookDirection, Vector3.yAxis)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function applyHumanoidStandingLock(humanoid)
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = false
	humanoid.Jump = false
end

local function startRebirthRagdoll(state)
	local humanoid = getHumanoid(state)
	local rootPart = getRootPart(state)
	if not humanoid then
		return
	end

	if rootPart then
		rootPart.Anchored = false
	end

	humanoid.Sit = false
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.Jump = false
	humanoid:ChangeState(Enum.HumanoidStateType.Ragdoll)
end

function stopRebirthStabilization(state)
	local stabilization = state and state.Stabilization
	if not stabilization then
		return
	end

	state.Stabilization = nil
	if stabilization.Connection then
		stabilization.Connection:Disconnect()
	end

	local humanoid = stabilization.Humanoid
	if humanoid and humanoid.Parent then
		for humanoidState, wasEnabled in pairs(stabilization.StateEnabled or {}) do
			pcall(function()
				humanoid:SetStateEnabled(humanoidState, wasEnabled)
			end)
		end

		humanoid.Sit = false
		humanoid.PlatformStand = false
		humanoid.AutoRotate = if stabilization.AutoRotate ~= nil then stabilization.AutoRotate else true
	end

	local rootPart = getRootPart(state)
	if rootPart then
		rootPart.Anchored = stabilization.RootAnchored == true
		setRootUprightAndGrounded(state)
	end
end

local function startRebirthStabilization(player, state)
	local humanoid = getHumanoid(state)
	local rootPart = getRootPart(state)
	if not humanoid or not rootPart then
		return
	end

	stopRebirthStabilization(state)

	local stateEnabled = {}
	for _, humanoidState in ipairs(REBIRTH_STABILIZED_STATES) do
		local ok, wasEnabled = pcall(function()
			return humanoid:GetStateEnabled(humanoidState)
		end)
		if ok then
			stateEnabled[humanoidState] = wasEnabled
		end
		pcall(function()
			humanoid:SetStateEnabled(humanoidState, false)
		end)
	end

	state.Stabilization = {
		Humanoid = humanoid,
		RootAnchored = rootPart.Anchored,
		AutoRotate = humanoid.AutoRotate,
		StateEnabled = stateEnabled,
	}

	rootPart.Anchored = true
	applyHumanoidStandingLock(humanoid)
	setRootUprightAndGrounded(state)
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	state.Stabilization.Connection = RunService.Heartbeat:Connect(function()
		if statesByPlayer[player] ~= state or not state.Reviving then
			stopRebirthStabilization(state)
			return
		end

		local currentHumanoid = getHumanoid(state)
		local currentRootPart = getRootPart(state)
		if not currentHumanoid or not currentRootPart then
			return
		end

		applyHumanoidStandingLock(currentHumanoid)
		currentRootPart.Anchored = true
		setRootUprightAndGrounded(state)
		local currentState = currentHumanoid:GetState()
		if currentState == Enum.HumanoidStateType.Ragdoll
			or currentState == Enum.HumanoidStateType.FallingDown
			or currentState == Enum.HumanoidStateType.Physics
		then
			currentHumanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end)
end

local function isProtected(state, now)
	now = now or getNow()
	return state ~= nil and (state.Reviving == true or (state.ImmuneUntil or 0) > now)
end

local function getStabilizedHealth(state)
	local humanoid = getHumanoid(state)
	if not humanoid then
		return MIN_STABILIZED_HEALTH
	end

	local passiveConfig = state.PassiveConfig or {}
	return math.max(
		MIN_STABILIZED_HEALTH,
		humanoid.MaxHealth * math.max(0, tonumber(passiveConfig.StabilizeHealthPercent) or 0)
	)
end

local function getRestoredHealth(state)
	local humanoid = getHumanoid(state)
	if not humanoid then
		return MIN_STABILIZED_HEALTH
	end

	local passiveConfig = state.PassiveConfig or {}
	return math.max(
		MIN_STABILIZED_HEALTH,
		humanoid.MaxHealth * math.max(0.05, tonumber(passiveConfig.RestoreHealthPercent) or 1)
	)
end

local function scheduleImmunityClear(player, state)
	local delayTime = math.max(0, (state.ImmuneUntil or 0) - getNow())
	task.delay(delayTime, function()
		if statesByPlayer[player] ~= state then
			return
		end

		if (state.ImmuneUntil or 0) > getNow() then
			scheduleImmunityClear(player, state)
			return
		end

		state.ImmuneUntil = 0
		syncPlayerAttributes(player, state)
	end)
end

local function beginReviveMoment(player, state)
	local humanoid = getHumanoid(state)
	if not humanoid then
		return
	end
	if state.Revived then
		return
	end

	state.Revived = true
	state.PendingUntil = 0
	state.ImmuneUntil = math.max(state.ImmuneUntil or 0, getNow() + state.PassiveConfig.ImmunityDuration)
	restoreHealth(state, getRestoredHealth(state))
	syncPlayerAttributes(player, state)
	scheduleImmunityClear(player, state)
end

local function finishRebirthAnimation(player, state)
	local humanoid = getHumanoid(state)
	if not humanoid then
		return
	end

	state.Reviving = false
	state.PendingUntil = 0
	state.ReviveAt = 0
	state.EndsAt = 0
	if not state.Revived then
		beginReviveMoment(player, state)
	end
	stopRebirthStabilization(state)
	syncPlayerAttributes(player, state)

	setRootUprightAndGrounded(state)
	humanoid.Sit = false
	humanoid.PlatformStand = false
	humanoid.AutoRotate = true
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	task.defer(function()
		if statesByPlayer[player] ~= state then
			return
		end

		local currentHumanoid = getHumanoid(state)
		if not currentHumanoid or currentHumanoid.Health <= 0 then
			return
		end

		currentHumanoid:ChangeState(Enum.HumanoidStateType.Running)
	end)
end

local function broadcastPhoenixRebirthEffect(player, state, reason, triggeredAt)
	local remoteBundle = DevilFruitRemotes.GetBundle()
	local reviveDelay = math.max(0, (state.ReviveAt or triggeredAt) - triggeredAt)
	local duration = math.max(reviveDelay, (state.EndsAt or triggeredAt) - triggeredAt)

	remoteBundle.Effect:FireAllClients(player, ToriShared.FruitName, PHOENIX_REBIRTH_ABILITY, {
		Phase = "Start",
		Reason = reason,
		TriggeredAt = triggeredAt,
		ReviveAt = state.ReviveAt,
		ReviveDelay = reviveDelay,
		EndsAt = state.EndsAt,
		Duration = duration,
		AnimationKey = state.PassiveConfig.AnimationKey,
		ReviveMarkerNames = state.PassiveConfig.ReviveMarkerNames,
	})
end

local function startPhoenixRebirthEffect(player, state, reason, triggeredAt)
	if statesByPlayer[player] ~= state or not state.Reviving then
		return
	end

	startRebirthStabilization(player, state)
	player:SetAttribute(PHOENIX_REBIRTH.TriggeredAtAttribute, triggeredAt)
	broadcastPhoenixRebirthEffect(player, state, reason, triggeredAt)
end

local function triggerPhoenixRebirth(player, state, reason)
	local humanoid = getHumanoid(state)
	if not humanoid then
		return false
	end

	if state.Used or state.Reviving or not isToriEquipped(player) then
		return false
	end

	state.Used = true
	state.Reviving = true
	state.Revived = false
	state.ImmuneUntil = 0
	local deathAt = getNow()
	local activationDelay = math.max(0, tonumber(state.PassiveConfig.ActivationDelay) or 0)
	local reviveDelay = math.max(0, tonumber(state.PassiveConfig.ReviveDelay) or state.PassiveConfig.RestoreDelay or 0)
	local animationDuration = math.max(reviveDelay, tonumber(state.PassiveConfig.AnimationDuration) or reviveDelay)
	local rebirthStartAt = deathAt + activationDelay
	state.PendingUntil = rebirthStartAt + reviveDelay
	state.ReviveAt = rebirthStartAt + reviveDelay
	state.EndsAt = rebirthStartAt + animationDuration
	syncPlayerAttributes(player, state)

	restoreHealth(state, getStabilizedHealth(state))
	startRebirthRagdoll(state)

	if activationDelay <= 0 then
		startPhoenixRebirthEffect(player, state, reason, rebirthStartAt)
	else
		task.delay(activationDelay, function()
			startPhoenixRebirthEffect(player, state, reason, rebirthStartAt)
		end)
	end

	task.delay(activationDelay + reviveDelay, function()
		if statesByPlayer[player] ~= state then
			return
		end

		local currentHumanoid = getHumanoid(state)
		if not currentHumanoid then
			return
		end

		setRootUprightAndGrounded(state)
		beginReviveMoment(player, state)
	end)

	task.delay(activationDelay + animationDuration, function()
		if statesByPlayer[player] ~= state then
			return
		end

		finishRebirthAnimation(player, state)
	end)

	return true
end

local function onHealthChanged(player, state, newHealth)
	if statesByPlayer[player] ~= state or state.InternalUpdate then
		return
	end

	local humanoid = getHumanoid(state)
	if not humanoid then
		return
	end

	local now = getNow()
	if isProtected(state, now) then
		if state.Reviving and not state.Revived then
			if newHealth < getStabilizedHealth(state) then
				restoreHealth(state, getStabilizedHealth(state))
			else
				state.LastHealth = newHealth
			end
		elseif newHealth < humanoid.MaxHealth then
			restoreHealth(state, getRestoredHealth(state))
		else
			state.LastHealth = newHealth
		end
		return
	end

	if newHealth > 0 then
		state.LastHealth = newHealth
		return
	end

	triggerPhoenixRebirth(player, state, "HealthDepleted")
end

local function bindCharacter(player, character)
	cleanupState(player)

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end

	local state = {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		RootPart = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 10),
		PassiveConfig = getPhoenixRebirthConfig(),
		Connections = {},
		InternalUpdate = false,
		LastHealth = humanoid.Health,
		Used = false,
		Reviving = false,
		Revived = false,
		PendingUntil = 0,
		ImmuneUntil = 0,
		ReviveAt = 0,
		EndsAt = 0,
	}

	statesByPlayer[player] = state
	syncPlayerAttributes(player, state)

	state.Connections[#state.Connections + 1] = humanoid.HealthChanged:Connect(function(newHealth)
		onHealthChanged(player, state, newHealth)
	end)

	state.Connections[#state.Connections + 1] = character.AncestryChanged:Connect(function(_, parent)
		if parent == nil and statesByPlayer[player] == state then
			cleanupState(player)
		end
	end)
end

local function hookPlayer(player)
	clearPlayerAttributes(player)

	player.CharacterAdded:Connect(function(character)
		bindCharacter(player, character)
	end)

	if player.Character then
		task.defer(bindCharacter, player, player.Character)
	end
end

function ToriPassiveService.Start()
	if started then
		return
	end

	started = true

	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(function(player)
		cleanupState(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end
end

function ToriPassiveService.IsProtected(player)
	local state = statesByPlayer[player]
	if not state and player and player.Character then
		bindCharacter(player, player.Character)
		state = statesByPlayer[player]
	end

	return isProtected(state)
end

function ToriPassiveService.TryConsumeRebirth(player, reason)
	local state = statesByPlayer[player]
	if not state and player and player.Character then
		bindCharacter(player, player.Character)
		state = statesByPlayer[player]
	end

	if not state then
		return false
	end

	if isProtected(state) then
		return true
	end

	return triggerPhoenixRebirth(player, state, reason or "FatalDamage")
end

return ToriPassiveService
