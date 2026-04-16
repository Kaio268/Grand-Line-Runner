local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DevilFruitService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruitService"))
local DevilFruitConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits")
)
local ToriShared = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Tori"):WaitForChild("Shared"):WaitForChild("ToriShared")
)

local ToriPassiveService = {}

local PHOENIX_REBIRTH_KEY = "PhoenixRebirth"
local PHOENIX_REBIRTH = ToriShared.Passives.PhoenixRebirth

local started = false
local statesByPlayer = {}

local function getNow()
	return Workspace:GetServerTimeNow()
end

local function getPhoenixRebirthConfig()
	local fruitConfig = DevilFruitConfig.GetFruit(ToriShared.FruitName)
	local passiveConfig = fruitConfig and fruitConfig.Passives and fruitConfig.Passives[PHOENIX_REBIRTH_KEY] or nil

	return {
		RestoreDelay = math.max(0, tonumber(passiveConfig and passiveConfig.RestoreDelay) or PHOENIX_REBIRTH.RestoreDelay),
		ImmunityDuration = math.max(
			0,
			tonumber(passiveConfig and passiveConfig.ImmunityDuration) or PHOENIX_REBIRTH.ImmunityDuration
		),
		RestoreHealthPercent = math.max(
			0.05,
			tonumber(passiveConfig and passiveConfig.RestoreHealthPercent) or PHOENIX_REBIRTH.RestoreHealthPercent
		),
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
	player:SetAttribute(PHOENIX_REBIRTH.UsedAttribute, false)
end

local function syncPlayerAttributes(player, state)
	if not player then
		return
	end

	local now = getNow()
	local pendingUntil = state and state.PendingUntil or 0
	local immuneUntil = state and state.ImmuneUntil or 0

	player:SetAttribute(PHOENIX_REBIRTH.UsedAttribute, state and state.Used == true or false)
	player:SetAttribute(PHOENIX_REBIRTH.PendingUntilAttribute, pendingUntil > now and pendingUntil or nil)
	player:SetAttribute(PHOENIX_REBIRTH.ImmuneUntilAttribute, immuneUntil > now and immuneUntil or nil)
end

local function cleanupState(player)
	local state = statesByPlayer[player]
	if not state then
		clearPlayerAttributes(player)
		return
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

local function zeroRootMotion(state)
	local rootPart = getRootPart(state)
	if not rootPart then
		return
	end

	rootPart.Anchored = false
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function isProtected(state, now)
	now = now or getNow()
	return state ~= nil and (state.Reviving == true or (state.ImmuneUntil or 0) > now)
end

local function startImmunityWindow(player, state)
	local humanoid = getHumanoid(state)
	if not humanoid then
		return
	end

	local passiveConfig = state.PassiveConfig
	state.Reviving = false
	state.PendingUntil = 0
	state.ImmuneUntil = getNow() + passiveConfig.ImmunityDuration
	syncPlayerAttributes(player, state)
	restoreHealth(state, math.max(humanoid.MaxHealth * passiveConfig.RestoreHealthPercent, 1))

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

	task.delay(passiveConfig.ImmunityDuration, function()
		if statesByPlayer[player] ~= state then
			return
		end

		if (state.ImmuneUntil or 0) > getNow() then
			return
		end

		state.ImmuneUntil = 0
		syncPlayerAttributes(player, state)
	end)
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
	state.ImmuneUntil = 0
	state.PendingUntil = getNow() + state.PassiveConfig.RestoreDelay
	player:SetAttribute(PHOENIX_REBIRTH.TriggeredAtAttribute, getNow())
	syncPlayerAttributes(player, state)

	restoreHealth(state, math.max(humanoid.MaxHealth * state.PassiveConfig.RestoreHealthPercent, 1))
	zeroRootMotion(state)

	humanoid.Sit = false
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid.Jump = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)

	-- Placeholder hook for future phoenix rebirth animation and VFX replication.
	task.delay(state.PassiveConfig.RestoreDelay, function()
		if statesByPlayer[player] ~= state then
			return
		end

		local currentHumanoid = getHumanoid(state)
		if not currentHumanoid or currentHumanoid.Health <= 0 then
			return
		end

		zeroRootMotion(state)
		startImmunityWindow(player, state)
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
		if newHealth < humanoid.MaxHealth then
			restoreHealth(state, math.max(humanoid.MaxHealth * state.PassiveConfig.RestoreHealthPercent, 1))
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
		PendingUntil = 0,
		ImmuneUntil = 0,
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
