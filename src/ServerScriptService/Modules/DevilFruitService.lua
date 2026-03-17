local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DevilFruitService = {}

local REQUEST_REMOTE_NAME = "DevilFruitAbilityRequest"
local STATE_REMOTE_NAME = "DevilFruitAbilityState"
local EFFECT_REMOTE_NAME = "DevilFruitAbilityEffect"
local COOLDOWN_BYPASS_ATTRIBUTE = "DevilFruitCooldownBypass"
local PERSIST_RETRY_DELAY = 1
local MAX_PERSIST_ATTEMPTS = 20

local cooldownsByPlayer = {}
local pendingPersistByPlayer = {}
local persistTaskByPlayer = {}
local hydrationTaskByPlayer = {}
local fruitHandlerCache = {}
local started = false

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	return remotes
end

local function getOrCreateRemote(parent, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getRemoteBundle()
	local remotes = getOrCreateRemotesFolder()

	return {
		Request = getOrCreateRemote(remotes, REQUEST_REMOTE_NAME),
		State = getOrCreateRemote(remotes, STATE_REMOTE_NAME),
		Effect = getOrCreateRemote(remotes, EFFECT_REMOTE_NAME),
	}
end

local RemoteBundle = getRemoteBundle()
local ModulesFolder = script.Parent
local FruitHandlersFolder = ModulesFolder:FindFirstChild("DevilFruits") or ModulesFolder:WaitForChild("DevilFruits")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local syncFruitAttribute

if not DataManager._initialized and typeof(DataManager.init) == "function" then
	DataManager.init()
end

local function debugPrint(...)
	print("[DevilFruitService]", ...)
end

local function resolveFruitName(fruitIdentifier)
	if fruitIdentifier == DevilFruitConfig.None then
		return DevilFruitConfig.None
	end

	return DevilFruitConfig.ResolveFruitName(fruitIdentifier)
end

local function normalizeStoredFruitName(fruitIdentifier)
	local resolvedFruit = resolveFruitName(fruitIdentifier)
	if resolvedFruit then
		return resolvedFruit
	end

	return DevilFruitConfig.None
end

local function getFruitHandlerModuleName(fruitConfig)
	if not fruitConfig then
		return nil
	end

	return fruitConfig.AbilityModule or fruitConfig.HandlerModule or fruitConfig.FruitKey or fruitConfig.Id
end

local function getFruitHandler(fruitName)
	local fruitConfig = DevilFruitConfig.GetFruit(fruitName)
	if not fruitConfig then
		return nil
	end

	local moduleName = getFruitHandlerModuleName(fruitConfig)
	if typeof(moduleName) ~= "string" or moduleName == "" then
		return nil
	end

	local cachedHandler = fruitHandlerCache[moduleName]
	if cachedHandler ~= nil then
		return cachedHandler or nil
	end

	local handlerModule = FruitHandlersFolder:FindFirstChild(moduleName)
	if not handlerModule then
		fruitHandlerCache[moduleName] = false
		warn(string.format("[DevilFruitService] Missing fruit handler module '%s' for %s", moduleName, fruitConfig.DisplayName))
		return nil
	end

	local ok, handler = pcall(require, handlerModule)
	if not ok then
		fruitHandlerCache[moduleName] = false
		warn(string.format("[DevilFruitService] Failed to require fruit handler '%s': %s", moduleName, tostring(handler)))
		return nil
	end

	fruitHandlerCache[moduleName] = handler
	return handler
end

local function getPlayerFruitFolder(player)
	return player:FindFirstChild("DevilFruit")
end

local function ensurePlayerFruitInstances(player)
	local fruitFolder = getPlayerFruitFolder(player)
	if not fruitFolder then
		fruitFolder = Instance.new("Folder")
		fruitFolder.Name = "DevilFruit"
		fruitFolder.Parent = player
	end

	local equipped = fruitFolder:FindFirstChild("Equipped")
	if equipped and not equipped:IsA("StringValue") then
		equipped:Destroy()
		equipped = nil
	end

	if not equipped then
		equipped = Instance.new("StringValue")
		equipped.Name = "Equipped"
		equipped.Value = DevilFruitConfig.None
		equipped.Parent = fruitFolder
	end

	return fruitFolder, equipped
end

local function getPlayerFruitValue(player)
	local _, equipped = ensurePlayerFruitInstances(player)
	return equipped
end

local function ensureFruitDataPath(player)
	local fruitData, reason = DataManager:TryGetValue(player, "DevilFruit")
	if reason ~= nil then
		return false, reason
	end

	if typeof(fruitData) ~= "table" then
		return DataManager:TryAddValue(player, "DevilFruit", {
			Equipped = DevilFruitConfig.None,
		})
	end

	local currentEquipped, equippedReason = DataManager:TryGetValue(player, "DevilFruit.Equipped")
	if equippedReason ~= nil then
		return false, equippedReason
	end

	if typeof(currentEquipped) ~= "string" then
		return DataManager:TryAddValue(player, "DevilFruit", {
			Equipped = DevilFruitConfig.None,
		})
	end

	return true, nil
end

local function loadEquippedFruitFromData(player)
	local storedValue = DataManager:TryGetValue(player, "DevilFruit.Equipped")
	if typeof(storedValue) == "string" then
		return normalizeStoredFruitName(storedValue)
	end

	return DevilFruitConfig.None
end

local function persistEquippedFruit(player, fruitName)
	local ensured, ensureReason = ensureFruitDataPath(player)
	if not ensured then
		return false, ensureReason
	end

	local success, reason = DataManager:TrySetValue(player, "DevilFruit.Equipped", fruitName)
	if not success then
		return false, reason
	end

	return true, "data_manager_synced"
end

local function startPersistTask(player)
	if persistTaskByPlayer[player] then
		return
	end

	persistTaskByPlayer[player] = task.spawn(function()
		local attempts = 0

		while player.Parent == Players and pendingPersistByPlayer[player] ~= nil and attempts < MAX_PERSIST_ATTEMPTS do
			attempts += 1
			local targetFruit = pendingPersistByPlayer[player]
			debugPrint(string.format("Persist attempt %d for %s", attempts, player.Name), targetFruit)

			local ok, reason = persistEquippedFruit(player, targetFruit)
			if ok then
				debugPrint("Persist succeeded for", player.Name, targetFruit)
				if pendingPersistByPlayer[player] == targetFruit then
					pendingPersistByPlayer[player] = nil
				end
				break
			end

			debugPrint("Persist deferred for", player.Name, "reason:", tostring(reason))
			task.wait(PERSIST_RETRY_DELAY)
		end

		if pendingPersistByPlayer[player] ~= nil and attempts >= MAX_PERSIST_ATTEMPTS then
			warn(string.format("[DevilFruitService] Failed to persist equipped fruit for %s after %d attempts", player.Name, attempts))
		end

		persistTaskByPlayer[player] = nil
	end)
end

local function queuePersist(player, fruitName)
	pendingPersistByPlayer[player] = fruitName
	startPersistTask(player)
end

local function hydrateFruitFromData(player)
	if hydrationTaskByPlayer[player] then
		return
	end

	hydrationTaskByPlayer[player] = task.spawn(function()
		for _ = 1, MAX_PERSIST_ATTEMPTS do
			if player.Parent ~= Players then
				break
			end

			local storedValue, reason = DataManager:TryGetValue(player, "DevilFruit.Equipped")
			if typeof(storedValue) == "string" then
				local normalizedFruit = normalizeStoredFruitName(storedValue)
				local fruitValue = getPlayerFruitValue(player)
				fruitValue.Value = normalizedFruit
				syncFruitAttribute(player, normalizedFruit)
				break
			end

			if reason ~= "not_ready" then
				break
			end

			task.wait(PERSIST_RETRY_DELAY)
		end

		hydrationTaskByPlayer[player] = nil
	end)
end

local function cleanupPlayerState(player)
	cooldownsByPlayer[player] = nil
	pendingPersistByPlayer[player] = nil
	persistTaskByPlayer[player] = nil
	hydrationTaskByPlayer[player] = nil
end

local function isCooldownBypassEnabled(player)
	return player:GetAttribute(COOLDOWN_BYPASS_ATTRIBUTE) == true
end

local function getCooldownTable(player)
	local playerCooldowns = cooldownsByPlayer[player]
	if not playerCooldowns then
		playerCooldowns = {}
		cooldownsByPlayer[player] = playerCooldowns
	end

	return playerCooldowns
end

local function clearFruitRuntimeState(player, fruitName)
	if fruitName == DevilFruitConfig.None then
		return
	end

	local fruitConfig = DevilFruitConfig.GetFruit(fruitName)
	if fruitConfig and fruitConfig.Abilities then
		local cooldowns = getCooldownTable(player)
		for abilityName in pairs(fruitConfig.Abilities) do
			cooldowns[abilityName] = nil
		end
	end

	if fruitName == "Mera Mera no Mi" then
		player:SetAttribute("MeraFireBurstUntil", nil)
	elseif fruitName == "Hie Hie no Mi" then
		player:SetAttribute("HieIceBoostUntil", nil)
		player:SetAttribute("HieIceBoostSpeedMultiplier", nil)
		player:SetAttribute("HieIceBoostSpeedBonus", nil)
	end
end

local function applyEquippedFruitRuntimeState(player, fruitValue, fruitName)
	fruitValue.Value = fruitName
	syncFruitAttribute(player, fruitName)
end

local function getEquippedFruit(player)
	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		return normalizeStoredFruitName(fruitAttribute)
	end

	local fruitValue = getPlayerFruitValue(player)
	if fruitValue then
		return normalizeStoredFruitName(fruitValue.Value)
	end

	return DevilFruitConfig.None
end

syncFruitAttribute = function(player, fruitName)
	local resolvedFruit = fruitName
	if typeof(resolvedFruit) ~= "string" then
		resolvedFruit = getEquippedFruit(player)
	else
		resolvedFruit = normalizeStoredFruitName(resolvedFruit)
	end

	player:SetAttribute("EquippedDevilFruit", resolvedFruit)
end

local function hookFruitValue(player)
	local fruitFolder = getPlayerFruitFolder(player)
	if not fruitFolder then
		return
	end

	local function connectEquippedValue()
		local fruitValue = getPlayerFruitValue(player)
		if not fruitValue or fruitValue:GetAttribute("__DevilFruitHooked") == true then
			return
		end

		fruitValue:SetAttribute("__DevilFruitHooked", true)
		fruitValue:GetPropertyChangedSignal("Value"):Connect(function()
			syncFruitAttribute(player)
		end)
	end

	connectEquippedValue()

	fruitFolder.ChildAdded:Connect(function(child)
		if child.Name == "Equipped" then
			connectEquippedValue()
			syncFruitAttribute(player)
		end
	end)
end

local function hookPlayer(player)
	task.spawn(function()
		local _, fruitValue = ensurePlayerFruitInstances(player)
		local storedFruit = loadEquippedFruitFromData(player)
		fruitValue.Value = storedFruit
		syncFruitAttribute(player, storedFruit)
		if player:GetAttribute(COOLDOWN_BYPASS_ATTRIBUTE) == nil then
			player:SetAttribute(COOLDOWN_BYPASS_ATTRIBUTE, false)
		end
		hookFruitValue(player)
		hydrateFruitFromData(player)

		player.ChildAdded:Connect(function(child)
			if child.Name == "DevilFruit" then
				hookFruitValue(player)
				syncFruitAttribute(player, getPlayerFruitValue(player).Value)
			end
		end)
	end)
end

local function getCharacterContext(player, fruitName, abilityName, requestPayload)
	local character = player.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return nil
	end

	local fruitConfig = DevilFruitConfig.GetFruit(fruitName)
	local abilityConfig = DevilFruitConfig.GetAbility(fruitName, abilityName)
	local fruitHandler = getFruitHandler(fruitName)

	if not fruitConfig or not abilityConfig or not fruitHandler then
		return nil
	end

	return {
		Player = player,
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		FruitKey = fruitConfig.FruitKey,
		FruitName = fruitName,
		FruitConfig = fruitConfig,
		AbilityName = abilityName,
		AbilityConfig = abilityConfig,
		FruitHandler = fruitHandler,
		RequestPayload = requestPayload,
	}
end

local function isAbilityReady(player, abilityName)
	if isCooldownBypassEnabled(player) then
		return true, 0
	end

	local cooldowns = getCooldownTable(player)
	local readyAt = cooldowns[abilityName]
	if not readyAt then
		return true, 0
	end

	local now = os.clock()
	if now >= readyAt then
		return true, 0
	end

	return false, readyAt
end

local function setAbilityCooldown(player, abilityName, duration)
	if isCooldownBypassEnabled(player) then
		local cooldowns = getCooldownTable(player)
		cooldowns[abilityName] = nil
		return 0
	end

	local cooldowns = getCooldownTable(player)
	local readyAt = os.clock() + duration
	cooldowns[abilityName] = readyAt
	return readyAt
end

local function clearAbilityCooldown(player, abilityName)
	local cooldowns = getCooldownTable(player)
	cooldowns[abilityName] = nil
end

local function fireAbilityDenied(player, fruitName, abilityName, reason, readyAt)
	RemoteBundle.State:FireClient(player, "Denied", fruitName or DevilFruitConfig.None, abilityName, reason, readyAt or 0)
end

local function fireAbilityActivated(player, fruitName, abilityName, readyAt, payload)
	if fruitName == "Mera Mera no Mi" and abilityName == "FireBurst" then
		player:SetAttribute("MeraFireBurstUntil", os.clock() + ((payload and payload.Duration) or 0))
	end

	RemoteBundle.State:FireClient(player, "Activated", fruitName, abilityName, readyAt, payload or {})
	RemoteBundle.Effect:FireAllClients(player, fruitName, abilityName, payload or {})
end

local function executeAbility(player, abilityName, requestPayload)
	local fruitName = getEquippedFruit(player)
	local context = getCharacterContext(player, fruitName, abilityName, requestPayload)
	if not context then
		fireAbilityDenied(player, fruitName, abilityName, "InvalidContext")
		return
	end

	local abilityHandler = context.FruitHandler[abilityName]
	if typeof(abilityHandler) ~= "function" then
		fireAbilityDenied(player, fruitName, abilityName, "MissingHandler")
		return
	end

	local isReady, readyAt = isAbilityReady(player, abilityName)
	if not isReady then
		fireAbilityDenied(player, fruitName, abilityName, "Cooldown", readyAt)
		return
	end

	local nextReadyAt = setAbilityCooldown(player, abilityName, context.AbilityConfig.Cooldown)
	local ok, payload = pcall(abilityHandler, context)
	if not ok then
		clearAbilityCooldown(player, abilityName)
		warn("[DevilFruitService] Failed to execute " .. fruitName .. " / " .. abilityName .. ": " .. tostring(payload))
		fireAbilityDenied(player, fruitName, abilityName, "ExecutionFailed")
		return
	end

	fireAbilityActivated(player, fruitName, abilityName, nextReadyAt, payload)
end

function DevilFruitService.GetEquippedFruit(player)
	return getEquippedFruit(player)
end

function DevilFruitService.GetEquippedFruitKey(player)
	return DevilFruitConfig.GetFruitKey(getEquippedFruit(player))
end

function DevilFruitService.SetEquippedFruit(player, fruitName)
	debugPrint("SetEquippedFruit STEP 1 - Player:", player and player.Name or "nil")
	if not player or not player:IsA("Player") then
		debugPrint("SetEquippedFruit STEP 1A - Invalid player")
		return false
	end

	if typeof(fruitName) ~= "string" then
		debugPrint("SetEquippedFruit STEP 1B - Invalid fruitName type")
		return false
	end

	local resolvedFruitName = resolveFruitName(fruitName)
	debugPrint("SetEquippedFruit STEP 2 - Validating fruit:", fruitName, "->", resolvedFruitName or "nil")
	if resolvedFruitName == nil then
		debugPrint("SetEquippedFruit STEP 2A - Unknown fruit")
		return false
	end

	debugPrint("SetEquippedFruit STEP 3 - Ensuring runtime DevilFruit folder/value")
	local _, fruitValue = ensurePlayerFruitInstances(player)
	local currentFruit = getEquippedFruit(player)

	if currentFruit ~= DevilFruitConfig.None and currentFruit ~= resolvedFruitName then
		debugPrint("SetEquippedFruit STEP 3A - Clearing runtime state for previous fruit:", currentFruit)
		clearFruitRuntimeState(player, currentFruit)
	end

	debugPrint("SetEquippedFruit STEP 4 - Applying runtime state")
	applyEquippedFruitRuntimeState(player, fruitValue, resolvedFruitName)

	debugPrint("SetEquippedFruit STEP 5 - Queueing persistence through DataManager")
	local persisted, reason = persistEquippedFruit(player, resolvedFruitName)
	if not persisted then
		debugPrint("SetEquippedFruit STEP 5A - Immediate persist unavailable:", tostring(reason))
		queuePersist(player, resolvedFruitName)
	end

	debugPrint("SetEquippedFruit STEP 6 - Persist result:", persisted, reason)

	return true, persisted
end

function DevilFruitService.SetCooldownBypass(player, isEnabled)
	if not player or not player:IsA("Player") then
		return false
	end

	player:SetAttribute(COOLDOWN_BYPASS_ATTRIBUTE, isEnabled == true)
	if isEnabled == true then
		cooldownsByPlayer[player] = {}
	end

	return true
end

function DevilFruitService.GetCooldownBypass(player)
	if not player or not player:IsA("Player") then
		return false
	end

	return isCooldownBypassEnabled(player)
end

function DevilFruitService.IsHazardSuppressedForPlayer(player, instance)
	local untilTime = player:GetAttribute("MeraFireBurstUntil")
	if typeof(untilTime) ~= "number" then
		return false
	end

	return untilTime > os.clock()
end

function DevilFruitService.Start()
	if started then
		return
	end

	started = true

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayerState)

	RemoteBundle.Request.OnServerEvent:Connect(function(player, abilityName, requestPayload)
		if typeof(abilityName) ~= "string" then
			return
		end

		local equippedFruit = getEquippedFruit(player)
		if equippedFruit == DevilFruitConfig.None then
			fireAbilityDenied(player, equippedFruit, abilityName, "NoFruit")
			return
		end

		local abilityConfig = DevilFruitConfig.GetAbility(equippedFruit, abilityName)
		if not abilityConfig then
			fireAbilityDenied(player, equippedFruit, abilityName, "UnknownAbility")
			return
		end

		executeAbility(player, abilityName, typeof(requestPayload) == "table" and requestPayload or nil)
	end)
end

return DevilFruitService
