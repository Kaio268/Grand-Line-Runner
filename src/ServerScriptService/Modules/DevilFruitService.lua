local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DevilFruitService = {}

local COOLDOWN_BYPASS_ATTRIBUTE = "DevilFruitCooldownBypass"
local MERA_DASH_DEBUG_ATTRIBUTE = "MeraFlameDashDebug"
local MERA_AUDIT_MARKER = "MERA_AUDIT_2026_03_30_V4"
local PERSIST_RETRY_DELAY = 1
local MAX_PERSIST_ATTEMPTS = 20
local HYDRATION_READY_TIMEOUT = 30
local SET_PERSIST_READY_TIMEOUT = 10
local MOGU_CLAWS_MODEL_NAME = "Claws"
local MOGU_CLAWS_INSTANCE_NAME = "MoguClaws"

local cooldownsByPlayer = {}
local pendingPersistByPlayer = {}
local persistTaskByPlayer = {}
local hydrationTaskByPlayer = {}
local started = false
local getEquippedFruit
local clearFruitRuntimeState
local ModulesFolder = script.Parent
local FruitHandlersFolder = ModulesFolder:FindFirstChild("DevilFruits") or ModulesFolder:WaitForChild("DevilFruits")
local ServerArchitectureFolder = FruitHandlersFolder:WaitForChild("Server")
local SharedFruitModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Registry = require(SharedFruitModules:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFruitModules:WaitForChild("DevilFruitLogger"))
local DevilFruitRemotes = require(SharedFruitModules:WaitForChild("DevilFruitRemotes"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))
local IndexCollectionService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("IndexCollectionService"))
local TitleService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TitleService"))
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local DevilFruitRequestGuard = require(ModulesFolder:WaitForChild("DevilFruitRequestGuard"))
local FruitModuleLoader = require(ServerArchitectureFolder:WaitForChild("FruitModuleLoader"))
local DevilFruitSecurity = require(ServerArchitectureFolder:WaitForChild("DevilFruitSecurity"))
local DevilFruitReplication = require(ServerArchitectureFolder:WaitForChild("DevilFruitReplication"))
local DevilFruitValidation = require(ServerArchitectureFolder:WaitForChild("DevilFruitValidation"))
local DevilFruitAbilityRunner = require(ServerArchitectureFolder:WaitForChild("DevilFruitAbilityRunner"))
local syncFruitAttribute
local serverFruitModuleLoader = FruitModuleLoader.new()
local remoteBundle
local replication
local requestRemoteConnection

if not DataManager._initialized and typeof(DataManager.init) == "function" then
	DataManager.init()
end

local function swaptoR6G(player, newModelName)
	local character = player.Character or player.CharacterAdded:Wait()
	-- Wait a frame to ensure the character is fully in the workspace
	task.wait()

	-- NEW CHECK: Only skip if the character is ALREADY using the requested model.
	-- This allows swapping from "R6" to "R6G" (Mera to Gomu).
	if character:GetAttribute("CurrentModelAsset") == newModelName then
		return
	end

	local modelTemplate = ReplicatedStorage.Assets.CharacterModels:FindFirstChild(newModelName)
	if not modelTemplate then
		warn("[DevilFruitService] Could not find model template: " .. newModelName)
		return
	end

	-- 1. SETUP THE NEW RIG
	local originalCFrame = character:GetPivot()
	-- Add extra studs to the Y-axis (Up) to prevent clipping under the map
	local safeCFrame = originalCFrame + Vector3.new(0, 5, 0)

	local newCharacter = modelTemplate:Clone()
	newCharacter.Name = player.Name

	-- Track the specific model asset so we can swap between different custom models later
	newCharacter:SetAttribute("CurrentModelAsset", newModelName)
	newCharacter:SetAttribute("EatAnimationRig", newModelName)
	newCharacter:SetAttribute("FruitModelVariant", newModelName)
	newCharacter:SetAttribute("IsModifiedR15", true)

	local newHumanoid = newCharacter:FindFirstChildOfClass("Humanoid")
	if not newHumanoid then
		newCharacter:Destroy()
		return
	end

	-- 2. APPLY APPEARANCE
	local success, playerDescription = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)

	if success and playerDescription then
		playerDescription.HeadScale, playerDescription.HeightScale = 1, 1
		playerDescription.WidthScale, playerDescription.DepthScale = 1, 1

		local templateDescription = newHumanoid:GetAppliedDescription()
		playerDescription.LeftArm = templateDescription.LeftArm
		playerDescription.RightArm = templateDescription.RightArm
		playerDescription.LeftLeg = templateDescription.LeftLeg
		playerDescription.RightLeg = templateDescription.RightLeg
		playerDescription.Torso = templateDescription.Torso

		pcall(function()
			newHumanoid:ApplyDescription(playerDescription)
		end)
	end

	if newHumanoid and newModelName == "R6G" then
		-- Ensure the Humanoid recognizes the rig as R15 (since R6G is a modified R15)
		newHumanoid.HipHeight = 2
		newHumanoid.RigType = Enum.HumanoidRigType.R15
	end

	if newHumanoid then
		newHumanoid:SetAttribute("EatAnimationRig", newModelName)
		newHumanoid:SetAttribute("FruitModelVariant", newModelName)
	end

	player:SetAttribute("EatAnimationRig", newModelName)
	player:SetAttribute("FruitModelVariant", newModelName)

	-- 3. PERFORM THE SWAP
	player.Character = newCharacter
	newCharacter:PivotTo(safeCFrame)
	newCharacter.Parent = workspace

	character:Destroy()
end

local function getCharacterModelsFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		return nil
	end

	return assetsFolder:FindFirstChild("CharacterModels")
end

local function getCharacterArm(character, side)
	if typeof(character) ~= "Instance" then
		return nil
	end

	local candidateNames = side == "Left"
		and { "Left Arm", "LeftHand", "LeftLowerArm", "LeftUpperArm" }
		or { "Right Arm", "RightHand", "RightLowerArm", "RightUpperArm" }

	for _, candidateName in ipairs(candidateNames) do
		local arm = character:FindFirstChild(candidateName)
		if arm and arm:IsA("BasePart") then
			return arm
		end
	end

	return nil
end

local function destroyMoguClaws(character)
	if typeof(character) ~= "Instance" then
		return
	end

	local existingClaws = character:FindFirstChild(MOGU_CLAWS_INSTANCE_NAME)
	if existingClaws then
		existingClaws:Destroy()
	end
end

local function attachMoguClaws(player)
	local character = player.Character
	if not character then
		return
	end

	destroyMoguClaws(character)

	local characterModelsFolder = getCharacterModelsFolder()
	local clawsTemplate = characterModelsFolder and characterModelsFolder:FindFirstChild(MOGU_CLAWS_MODEL_NAME)
	if not clawsTemplate then
		warn(string.format("[DevilFruitService] Could not find model template: %s", MOGU_CLAWS_MODEL_NAME))
		return
	end

	local leftArm = getCharacterArm(character, "Left")
	local rightArm = getCharacterArm(character, "Right")
	if not leftArm or not rightArm then
		warn(string.format("[DevilFruitService] Could not find player arms for Mogu claws: %s", player.Name))
		return
	end

	local clawsModel = clawsTemplate:Clone()
	clawsModel.Name = MOGU_CLAWS_INSTANCE_NAME
	clawsModel.Parent = character

	local leftModel = clawsModel:FindFirstChild("Left")
	local rightModel = clawsModel:FindFirstChild("Right")
	local leftPaw = leftModel and leftModel:FindFirstChild("LeftPaw", true)
	local rightPaw = rightModel and rightModel:FindFirstChild("RightPaw", true)
	if not (leftPaw and leftPaw:IsA("BasePart") and rightPaw and rightPaw:IsA("BasePart")) then
		clawsModel:Destroy()
		warn(string.format("[DevilFruitService] Claws model is missing LeftPaw/RightPaw for %s", player.Name))
		return
	end

	for _, descendant in ipairs(clawsModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
		end
	end

	local leftMotor = Instance.new("Motor6D")
	leftMotor.Name = "MoguLeftClawMotor"
	leftMotor.Part0 = leftArm
	leftMotor.Part1 = leftPaw
	leftMotor.C0 = CFrame.new(-0.026, -0.983, -0.05) * CFrame.Angles(math.rad(-1.446), math.rad(-90), 0)
	leftMotor.Parent = leftArm

	local rightMotor = Instance.new("Motor6D")
	rightMotor.Name = "MoguRightClawMotor"
	rightMotor.Part0 = rightArm
	rightMotor.Part1 = rightPaw
	rightMotor.C0 = CFrame.new(0.042, -1.055, -0.05) * CFrame.Angles(math.rad(0.525), math.rad(90), 0)
	rightMotor.Parent = rightArm
end

local function getDesiredCharacterModelAsset(fruitName)
	if fruitName == "Gomu Gomu no Mi" then
		return "R6G"
	end

	return "R6"
end

local function applyFruitCharacterModel(player, fruitName)
	local character = player.Character
	if not character then
		return
	end

	local desiredModelAsset = getDesiredCharacterModelAsset(fruitName)
	if character:GetAttribute("CurrentModelAsset") ~= desiredModelAsset then
		swaptoR6G(player, desiredModelAsset)
		character = player.Character
		if not character then
			return
		end
	end

	if fruitName == "Mogu Mogu no Mi" then
		attachMoguClaws(player)
	else
		destroyMoguClaws(character)
	end
end

local function debugPrint(...)
	print("[DevilFruitService]", ...)
end

local function getRemoteBundle()
	if remoteBundle then
		return remoteBundle
	end

	remoteBundle = DevilFruitRemotes.GetBundle()
	replication = DevilFruitReplication.new(remoteBundle)
	return remoteBundle
end

local function describeRemote(instance)
	return DevilFruitRemotes.DescribeInstance(instance)
end

local function countPayloadKeys(payload)
	if typeof(payload) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(payload) do
		count += 1
	end

	return count
end

local function describePayloadForAudit(payload)
	if typeof(payload) ~= "table" then
		return string.format("type=%s value=%s", typeof(payload), tostring(payload))
	end

	local keys = {}
	for key in pairs(payload) do
		keys[#keys + 1] = key
	end

	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		local value = payload[key]
		if typeof(value) == "Vector3" then
			parts[#parts + 1] = string.format("%s=(%.2f, %.2f, %.2f)", tostring(key), value.X, value.Y, value.Z)
		else
			parts[#parts + 1] = string.format("%s=%s", tostring(key), tostring(value))
		end
	end

	return string.format("type=table keys=%d payload={%s}", #keys, table.concat(parts, ", "))
end

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function isMeraDashDebugEnabled(player)
	return ReplicatedStorage:GetAttribute(MERA_DASH_DEBUG_ATTRIBUTE) == true
		or (player and player:GetAttribute(MERA_DASH_DEBUG_ATTRIBUTE) == true)
end

local function shouldLogMeraDashAttempt(fruitName, abilityName)
	return abilityName == "FlameDash" or fruitName == "Mera Mera no Mi"
end

local function shouldLogMeraAudit(fruitName, abilityName)
	return fruitName == "Mera Mera no Mi" or abilityName == "FlameDash" or abilityName == "FireBurst"
end

local function logMeraAudit(level, message, ...)
	local formattedMessage = string.format("[%s] " .. message, MERA_AUDIT_MARKER, ...)
	if level == "WARN" then
		DevilFruitLogger.Warn("SERVER", formattedMessage)
		return
	end

	DevilFruitLogger.Info("SERVER", formattedMessage)
end

local function logMeraDashServer(player, message, ...)
	if not isMeraDashDebugEnabled(player) then
		return
	end

	print(string.format("[MERA DASH][SERVER] " .. message, ...))
end

local function resolveFruitName(fruitIdentifier)
	if fruitIdentifier == DevilFruitConfig.None then
		return DevilFruitConfig.None
	end

	return Registry.ResolveFruitName(fruitIdentifier)
end

local function getFruitHandler(fruitName)
	return serverFruitModuleLoader:GetHandler(fruitName)
end

local function normalizeStoredFruitName(fruitIdentifier)
	local resolvedFruit = resolveFruitName(fruitIdentifier)
	if resolvedFruit then
		return resolvedFruit
	end

	return DevilFruitConfig.None
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

local function getEquippedFruitValue(player)
	local fruitValue = getPlayerFruitValue(player)
	if not fruitValue then
		return DevilFruitConfig.None
	end

	if typeof(fruitValue.Value) ~= "string" then
		return DevilFruitConfig.None
	end

	return DevilFruitConfig.ResolveFruitName(fruitValue.Value) or DevilFruitConfig.None
end

local function waitForDataReady(player, timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or SET_PERSIST_READY_TIMEOUT)

	while player.Parent == Players and os.clock() <= deadline do
		if DataManager:IsReady(player) then
			return true
		end

		task.wait(0.1)
	end

	return DataManager:IsReady(player)
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

local function applyEquippedFruitValue(player, fruitName)
	local normalizedFruit = normalizeStoredFruitName(fruitName)
	local fruitValue = getPlayerFruitValue(player)
	fruitValue.Value = normalizedFruit
	syncFruitAttribute(player, normalizedFruit)
	return normalizedFruit
end

local function startPersistTask(player)
	if persistTaskByPlayer[player] then
		return
	end

	persistTaskByPlayer[player] = task.spawn(function()
		local attempts = 0
		local deadline = os.clock() + (MAX_PERSIST_ATTEMPTS * PERSIST_RETRY_DELAY)

		while player.Parent == Players and pendingPersistByPlayer[player] ~= nil and attempts < MAX_PERSIST_ATTEMPTS do
			if not DataManager:IsReady(player) then
				if os.clock() >= deadline then
					break
				end

				task.wait(PERSIST_RETRY_DELAY)
				continue
			end

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
		if not waitForDataReady(player, HYDRATION_READY_TIMEOUT) then
			hydrationTaskByPlayer[player] = nil
			return
		end

		local pendingFruit = pendingPersistByPlayer[player]
		if typeof(pendingFruit) == "string" then
			local persisted = persistEquippedFruit(player, normalizeStoredFruitName(pendingFruit))
			if persisted then
				pendingPersistByPlayer[player] = nil
			else
				queuePersist(player, pendingFruit)
			end

			applyEquippedFruitValue(player, pendingFruit)

			if player.Character then
				applyFruitCharacterModel(player, pendingFruit)
			end

			hydrationTaskByPlayer[player] = nil
			return
		end

		local hydratedFruit = loadEquippedFruitFromData(player)
		applyEquippedFruitValue(player, hydratedFruit)

		if player.Character then
			applyFruitCharacterModel(player, hydratedFruit)
		end

		hydrationTaskByPlayer[player] = nil
	end)
end

local function cleanupPlayerState(player)
	local targetFruit = pendingPersistByPlayer[player]
	if typeof(targetFruit) ~= "string" then
		targetFruit = getEquippedFruit(player)
	end

	local currentFruit = getEquippedFruit(player)
	if currentFruit ~= DevilFruitConfig.None then
		clearFruitRuntimeState(player, currentFruit)
	end

	if DataManager:IsReady(player) then
		local persisted, reason = persistEquippedFruit(player, normalizeStoredFruitName(targetFruit))
		if not persisted then
			warn(string.format(
				"[DevilFruitService] Failed final equipped fruit flush for %s: %s",
				player.Name,
				tostring(reason)
			))
		end
	end

	cooldownsByPlayer[player] = nil
	pendingPersistByPlayer[player] = nil
	persistTaskByPlayer[player] = nil
	hydrationTaskByPlayer[player] = nil
	DevilFruitRequestGuard.CleanupPlayer(player)
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

clearFruitRuntimeState = function(player, fruitName)
	if fruitName == DevilFruitConfig.None then
		return
	end

	if player.Character then
		destroyMoguClaws(player.Character)
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

	local fruitHandler = getFruitHandler(fruitName)
	if fruitHandler and typeof(fruitHandler.ClearRuntimeState) == "function" then
		local ok, err = pcall(fruitHandler.ClearRuntimeState, player, fruitName)
		if not ok then
			warn(string.format("[DevilFruitService] Failed to clear runtime state for %s: %s", fruitName, tostring(err)))
		end
	end
end

local function applyEquippedFruitRuntimeState(player, fruitValue, fruitName)
	fruitValue.Value = fruitName
	syncFruitAttribute(player, fruitName)
end

getEquippedFruit = function(player)
	local fruitValue = getPlayerFruitValue(player)
	if fruitValue then
		return normalizeStoredFruitName(fruitValue.Value)
	end

	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		return normalizeStoredFruitName(fruitAttribute)
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
	DevilFruitLogger.Info(
		"SERVER",
		"equipped sync player=%s equipped=%s attr=%s value=%s",
		player.Name,
		tostring(resolvedFruit),
		tostring(player:GetAttribute("EquippedDevilFruit")),
		tostring(getEquippedFruitValue(player))
	)
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
		applyEquippedFruitValue(player, DevilFruitConfig.None)
		if player:GetAttribute(COOLDOWN_BYPASS_ATTRIBUTE) == nil then
			player:SetAttribute(COOLDOWN_BYPASS_ATTRIBUTE, false)
		end
		applyFruitCharacterModel(player, DevilFruitConfig.None)
		hookFruitValue(player)
		hydrateFruitFromData(player)

		player.ChildAdded:Connect(function(child)
			if child.Name == "DevilFruit" then
				hookFruitValue(player)
				syncFruitAttribute(player, getPlayerFruitValue(player).Value)
			end
		end)

		player.CharacterAdded:Connect(function(character)
			task.defer(function()
				if player.Character ~= character then
					return
				end

				local equippedFruit = getEquippedFruit(player)
				applyFruitCharacterModel(player, equippedFruit)
			end)
		end)
	end)
end

local function getAliveCharacterState(player)
	local character = player.Character
	if not character then
		return nil, "NoCharacter"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return nil, "InvalidHumanoid"
	end

	return {
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
	}, nil
end

local function getCharacterContext(player, fruitName, abilityName, abilityConfig, requestPayload, characterState, requestMetadata)
	local resolvedCharacterState = characterState
	if type(resolvedCharacterState) ~= "table" then
		resolvedCharacterState = getAliveCharacterState(player)
	end

	if type(resolvedCharacterState) ~= "table" then
		return nil
	end

	local fruitConfig = DevilFruitConfig.GetFruit(fruitName)
	local fruitHandler = getFruitHandler(fruitName)

	if not fruitConfig or not abilityConfig or not fruitHandler then
		return nil
	end

	return {
		Player = player,
		Character = resolvedCharacterState.Character,
		Humanoid = resolvedCharacterState.Humanoid,
		RootPart = resolvedCharacterState.RootPart,
		FruitKey = fruitConfig.FruitKey,
		FruitName = fruitName,
		FruitConfig = fruitConfig,
		AbilityName = abilityName,
		AbilityConfig = abilityConfig,
		FruitHandler = fruitHandler,
		RequestPayload = requestPayload,
		RequestReceivedAt = requestMetadata and requestMetadata.ReceivedAt or nil,
		EmitEffect = function(effectAbilityName, effectPayload, effectTargetPlayer)
			local targetPlayer = effectTargetPlayer
			if targetPlayer ~= nil and (not targetPlayer:IsA("Player") or targetPlayer.Parent ~= Players) then
				targetPlayer = nil
			end

			if targetPlayer == nil and player.Parent == Players then
				targetPlayer = player
			end

			if targetPlayer == nil then
				return false
			end

			replication:BroadcastEffect(targetPlayer, fruitName, effectAbilityName or abilityName, effectPayload or {})
			return true
		end,
		ReportSuspicious = function(reason, detail, weight)
			DevilFruitRequestGuard.RecordSuspicious(player, reason, detail, weight)
		end,
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

local function shouldStartCooldownOnResolve(abilityConfig)
	if typeof(abilityConfig) ~= "table" then
		return false
	end

	local cooldownStartsOn = abilityConfig.CooldownStartsOn
	return typeof(cooldownStartsOn) == "string" and string.lower(cooldownStartsOn) == "resolve"
end

local function fireAbilityDenied(player, fruitName, abilityName, reason, readyAt)
	replication:FireDenied(player, fruitName or DevilFruitConfig.None, abilityName, reason, readyAt or 0)
end

local function fireAbilityActivated(player, fruitName, abilityName, readyAt, payload)
	if fruitName == "Mera Mera no Mi" and abilityName == "FireBurst" then
		player:SetAttribute("MeraFireBurstUntil", os.clock() + ((payload and payload.Duration) or 0))
	end

	replication:FireActivated(player, fruitName, abilityName, readyAt, payload or {})
	replication:BroadcastEffect(player, fruitName, abilityName, payload or {})
end

local function executeAbility(player, fruitName, abilityName, abilityConfig, requestPayload, characterState, requestMetadata)
	return DevilFruitAbilityRunner.Execute({
		Player = player,
		FruitName = fruitName,
		AbilityName = abilityName,
		AbilityConfig = abilityConfig,
		RequestPayload = requestPayload,
		CharacterState = characterState,
		RequestMetadata = requestMetadata,
		RequestGuard = DevilFruitRequestGuard,
		Security = DevilFruitSecurity,
		GetContext = getCharacterContext,
		IsAbilityReady = isAbilityReady,
		SetAbilityCooldown = setAbilityCooldown,
		ClearAbilityCooldown = clearAbilityCooldown,
		ShouldStartCooldownOnResolve = shouldStartCooldownOnResolve,
		FireDenied = fireAbilityDenied,
		FireActivated = fireAbilityActivated,
	})
end

local function handleAbilityRequest(player, abilityName, requestPayload)
	local requestRemote = getRemoteBundle().Request
	local requestIdentity = describeRemote(requestRemote)
	local requestReceivedAt = getSharedTimestamp()
	local equippedFruitAtReceipt = getEquippedFruit(player)
	DevilFruitLogger.Info(
		"SERVER",
		"request received remote=%s path=%s runtimeId=%s debugId=%s object=%s player=%s ability=%s payloadKeys=%d ts=%.6f",
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object),
		player and player.Name or "<nil>",
		tostring(abilityName),
		countPayloadKeys(requestPayload),
		requestReceivedAt
	)
	DevilFruitLogger.Info(
		"SERVER",
		"remote event entered remote=%s path=%s runtimeId=%s debugId=%s object=%s player=%s ability=%s payloadKeys=%d",
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object),
		player and player.Name or "<nil>",
		tostring(abilityName),
		countPayloadKeys(requestPayload)
	)
	if shouldLogMeraAudit(equippedFruitAtReceipt, abilityName) then
		logMeraAudit(
			"INFO",
			"Mera server request received player=%s equipped=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payload=%s",
			player and player.Name or "<nil>",
			tostring(equippedFruitAtReceipt),
			tostring(abilityName),
			tostring(requestIdentity.Name),
			tostring(requestIdentity.Path),
			tostring(requestIdentity.RuntimeId),
			tostring(requestIdentity.DebugId),
			tostring(requestIdentity.Object),
			describePayloadForAudit(requestPayload)
		)
	end

	local requestOk, validated = DevilFruitValidation.ValidateRequest({
		Player = player,
		AbilityName = abilityName,
		RequestPayload = requestPayload,
		RequestGuard = DevilFruitRequestGuard,
		Security = DevilFruitSecurity,
		NoneFruitName = DevilFruitConfig.None,
		GetEquippedFruit = getEquippedFruit,
		GetAliveCharacterState = getAliveCharacterState,
		GetAbilityConfig = function(fruitName, resolvedAbilityName)
			local abilityEntry = Registry.GetAbility(fruitName, resolvedAbilityName)
			return abilityEntry and abilityEntry.Config or DevilFruitConfig.GetAbility(fruitName, resolvedAbilityName)
		end,
		FireDenied = fireAbilityDenied,
	})
	if not requestOk then
		DevilFruitLogger.Warn(
			"SERVER",
			"request rejected player=%s ability=%s stage=validation",
			player and player.Name or "<nil>",
			tostring(abilityName)
		)
		if shouldLogMeraAudit(equippedFruitAtReceipt, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera server request rejected player=%s equipped=%s ability=%s stage=validation payload=%s",
				player and player.Name or "<nil>",
				tostring(equippedFruitAtReceipt),
				tostring(abilityName),
				describePayloadForAudit(requestPayload)
			)
		end
		if shouldLogMeraDashAttempt(getEquippedFruit(player), abilityName) then
			logMeraDashServer(
				player,
				"request_handled_by_validation ts=%.6f player=%s ability=%s processingMs=%.2f",
				getSharedTimestamp(),
				player.Name,
				tostring(abilityName),
				(getSharedTimestamp() - requestReceivedAt) * 1000
			)
		end
		return
	end
	DevilFruitLogger.Info(
		"SERVER",
		"request validated player=%s fruit=%s ability=%s payloadKeys=%d",
		player.Name,
		tostring(validated.EquippedFruit),
		tostring(abilityName),
		countPayloadKeys(validated.SanitizedPayload)
	)
	if shouldLogMeraAudit(validated.EquippedFruit, abilityName) then
		logMeraAudit(
			"INFO",
			"Mera server request validated player=%s fruit=%s ability=%s payload=%s",
			player.Name,
			tostring(validated.EquippedFruit),
			tostring(abilityName),
			describePayloadForAudit(validated.SanitizedPayload)
		)
	end

	local executed = executeAbility(player, validated.EquippedFruit, abilityName, validated.AbilityConfig, validated.SanitizedPayload, validated.CharacterState, {
		ReceivedAt = requestReceivedAt,
	})
	DevilFruitLogger.Info(
		"SERVER",
		"request execution complete player=%s fruit=%s ability=%s executed=%s",
		player.Name,
		tostring(validated.EquippedFruit),
		tostring(abilityName),
		tostring(executed == true)
	)
	if shouldLogMeraAudit(validated.EquippedFruit, abilityName) then
		logMeraAudit(
			executed == true and "INFO" or "WARN",
			"Mera server request execution complete player=%s fruit=%s ability=%s executed=%s",
			player.Name,
			tostring(validated.EquippedFruit),
			tostring(abilityName),
			tostring(executed == true)
		)
	end
end

local function ensureRequestRemoteConnection()
	if requestRemoteConnection then
		return requestRemoteConnection
	end

	local bundle = getRemoteBundle()
	local requestIdentity = describeRemote(bundle.Request)
	DevilFruitLogger.Info(
		"SERVER",
		"remote connection binding request=%s path=%s runtimeId=%s debugId=%s object=%s state=%s effect=%s folder=%s",
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object),
		tostring(describeRemote(bundle.State).Path),
		tostring(describeRemote(bundle.Effect).Path),
		tostring(bundle.Folder:GetFullName())
	)
	requestRemoteConnection = bundle.Request.OnServerEvent:Connect(handleAbilityRequest)
	DevilFruitLogger.Info(
		"SERVER",
		"remote connection ready request=%s path=%s runtimeId=%s debugId=%s object=%s",
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object)
	)
	return requestRemoteConnection
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
	serverFruitModuleLoader:ResetHandler(currentFruit)
	serverFruitModuleLoader:ResetHandler(resolvedFruitName)

	if currentFruit ~= DevilFruitConfig.None and currentFruit ~= resolvedFruitName then
		debugPrint("SetEquippedFruit STEP 3A - Clearing runtime state for previous fruit:", currentFruit)
		clearFruitRuntimeState(player, currentFruit)
	end

	debugPrint("SetEquippedFruit STEP 4 - Applying runtime state")
	applyEquippedFruitRuntimeState(player, fruitValue, resolvedFruitName)
	DevilFruitLogger.Info(
		"SERVER",
		"equipped fruit applied player=%s requested=%s resolved=%s value=%s attr=%s",
		player.Name,
		tostring(fruitName),
		tostring(resolvedFruitName),
		tostring(getEquippedFruitValue(player)),
		tostring(player:GetAttribute("EquippedDevilFruit"))
	)

	if resolvedFruitName ~= DevilFruitConfig.None then
		IndexCollectionService.MarkDevilFruitDiscovered(player, resolvedFruitName)
		TitleService.UnlockTitle(player, "EnemyOfTheSea")
	end

	-- ADDED THIS LINE: Apply the model swap immediately upon equipping
	if player.Character then
		applyFruitCharacterModel(player, resolvedFruitName)
	end

	debugPrint("SetEquippedFruit STEP 5 - Queueing persistence through DataManager")
	local persisted, reason = persistEquippedFruit(player, resolvedFruitName)
	if not persisted then
		debugPrint("SetEquippedFruit STEP 5A - Immediate persist unavailable:", tostring(reason))
		if (reason == "not_ready" or reason == "no_profile") and waitForDataReady(player, SET_PERSIST_READY_TIMEOUT) then
			persisted, reason = persistEquippedFruit(player, resolvedFruitName)
		end
		if not persisted then
			queuePersist(player, resolvedFruitName)
		else
			pendingPersistByPlayer[player] = nil
		end
	else
		pendingPersistByPlayer[player] = nil
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

function DevilFruitService.Start(startSource)
	if started then
		DevilFruitLogger.Info(
			"SERVER",
			"service start skipped source=%s reason=already_started",
			tostring(startSource or "unknown")
		)
		return
	end

	started = true
	ensureRequestRemoteConnection()
	local requestIdentity = describeRemote(getRemoteBundle().Request)
	DevilFruitLogger.Info(
		"SERVER",
		"service start begin source=%s request=%s path=%s runtimeId=%s debugId=%s object=%s",
		tostring(startSource or "unknown"),
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object)
	)
	HitEffectService.Start()

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	Players.PlayerAdded:Connect(hookPlayer)
	Players.PlayerRemoving:Connect(cleanupPlayerState)
	DevilFruitLogger.Info("SERVER", "service start complete source=%s", tostring(startSource or "unknown"))
end

task.defer(function()
	DevilFruitService.Start("module_auto_start")
end)

return DevilFruitService
