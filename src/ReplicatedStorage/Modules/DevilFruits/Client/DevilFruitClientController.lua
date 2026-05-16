local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local DevilFruitClientController = {}
local started = false

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local SharedFolder = DevilFruits:WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFolder:WaitForChild("DevilFruitLogger"))
local DevilFruitRemotes = require(SharedFolder:WaitForChild("DevilFruitRemotes"))
local DevilFruitOptionalEffects = require(SharedFolder:WaitForChild("DevilFruitOptionalEffects"))
local ClientEffectVisuals = require(Modules:WaitForChild("DevilFruits"):WaitForChild("ClientEffectVisuals"))
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local ProtectionRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("ProtectionRuntime"))
local FruitModuleLoader = require(SharedFolder:WaitForChild("FruitModuleLoader"))
local DevilFruitInputController = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitInputController"))
local DevilFruitEffectRouter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitEffectRouter"))
local DevilFruitUiController = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Client"):WaitForChild("DevilFruitUiController"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MOGU_FRUIT_NAME = "Mogu Mogu no Mi"
local MOGU_BURROW_ABILITY = "Burrow"
local BOMU_FRUIT_NAME = "Bomu Bomu no Mi"
local BOMU_LAND_MINE_ABILITY = "LandMine"
local PHOENIX_FRUIT_NAME = "Tori Tori no Mi"
local PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local PHOENIX_REBIRTH_ABILITY = "PhoenixRebirth"
local HAZARD_SUPPRESSION_INTERVAL = 0.05
local FIRE_BURST_HAZARD_SUPPRESSION_INTERVAL = 0.16
local LOCAL_HAZARD_OVERLAP_MAX_PARTS = 128
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_MOGU_HAZARD_PROTECTION_RADIUS = 12
local DEFAULT_MOGU_RESOLVE_HAZARD_PROBE_PADDING = 0.25
local DEFAULT_HAZARD_SUPPRESSION_SOURCE = "Default"
local FIRE_BURST_HAZARD_SUPPRESSION_SOURCE = "FireBurst"
local MOGU_HAZARD_SUPPRESSION_SOURCE = "MoguBurrow"

local remoteBundle
local requestRemote
local stateRemote
local effectRemote

local localCooldowns = {}
local suppressedParts = {}
local activeFireBursts = {}
local activeMoguBurrow = nil
local hazardSuppressionLoopRunning = false
local playOptionalEffect
local getFruitFolder
local getEquippedFruit
local fruitModuleLoader
local inputController
local effectRouter
local syncDevilFruitClientState
local lastSyncedFruitName = DevilFruitConfig.None
local cooldownHud = {
	CurrentFruit = nil,
	Abilities = {},
	Visible = false,
}
local cooldownHudRoot
local cooldownHudRootContainer
local cooldownHudComponent
local react
local reactRoblox
local cooldownHudLastError
local DEVIL_FRUIT_UI = {
	Ready = Color3.fromRGB(116, 255, 161),
	Cooldown = Color3.fromRGB(255, 190, 116),
	CooldownFill = Color3.fromRGB(255, 133, 44),
}

local HUD_REFRESH_INTERVAL = 0.05
local nextHudRefreshAt = 0
local STATE_RECONCILE_INTERVAL = 0.25
local nextStateReconcileAt = 0

local function logDevilFruitClient(message, ...)
	print(string.format("[DEVILFRUIT CLIENT] " .. message, ...))
end

local function logDevilFruitRequest(message, ...)
	if not RunService:IsStudio() then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
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

local function isBomuLandMineWorldEffect(targetPlayer, fruitName, abilityName, payload)
	if targetPlayer ~= nil and targetPlayer ~= false then
		return false
	end

	if fruitName ~= BOMU_FRUIT_NAME or abilityName ~= BOMU_LAND_MINE_ABILITY or typeof(payload) ~= "table" then
		return false
	end

	local action = payload.Action
	if action == "Placed" then
		return typeof(payload.MinePosition) == "Vector3" or typeof(payload.OriginPosition) == "Vector3"
	end

	if action == "Detonating" or action == "Detonated" then
		return typeof(payload.OriginPosition) == "Vector3" or typeof(payload.MinePosition) == "Vector3"
	end

	return false
end

local function describeRemote(instance)
	return DevilFruitRemotes.DescribeInstance(instance)
end

local function formatVector3ForLog(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function shouldTraceAbilityInput(keyCode)
	return keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.C
end

local function normalizeEquippedFruitName(fruitIdentifier)
	if typeof(fruitIdentifier) ~= "string" then
		return DevilFruitConfig.None
	end

	if fruitIdentifier == DevilFruitConfig.None or fruitIdentifier == "None" then
		return DevilFruitConfig.None
	end

	return Registry.ResolveFruitName(fruitIdentifier) or fruitIdentifier
end

local function formatAbilityName(abilityName)
	return DevilFruitUiController.FormatAbilityName(abilityName)
end

local function formatCooldownTime(seconds)
	return DevilFruitUiController.FormatCooldownTime(seconds)
end

local function isCooldownBypassEnabled()
	return player:GetAttribute("DevilFruitCooldownBypass") == true
end

local function getCooldownNow()
	return Workspace:GetServerTimeNow()
end

local function getLocalCooldownReadyAt(cooldownState)
	if typeof(cooldownState) == "table" then
		return tonumber(cooldownState.ReadyAt) or 0
	end

	return tonumber(cooldownState) or 0
end

local function getLocalCooldownStartsAt(cooldownState, fallbackDuration)
	local readyAt = getLocalCooldownReadyAt(cooldownState)
	if typeof(cooldownState) == "table" then
		local startsAt = tonumber(cooldownState.StartsAt)
		if startsAt and startsAt > 0 then
			return startsAt
		end
	end

	return math.max(0, readyAt - math.max(0, tonumber(fallbackDuration) or 0))
end

local function getLocalCooldownDuration(cooldownState, fallbackDuration)
	if typeof(cooldownState) == "table" then
		local duration = tonumber(cooldownState.Duration)
		if duration and duration > 0 then
			return duration
		end
	end

	return math.max(0, tonumber(fallbackDuration) or 0)
end

local function setLocalCooldown(abilityName, readyAt, payload)
	local resolvedReadyAt = tonumber(readyAt) or 0
	if resolvedReadyAt <= 0 then
		localCooldowns[abilityName] = nil
		return
	end

	local cooldownState = {
		ReadyAt = resolvedReadyAt,
	}

	if typeof(payload) == "table" then
		local startsAt = tonumber(payload.CooldownStartsAt)
		local duration = tonumber(payload.CooldownDuration)
		if startsAt and startsAt > 0 and startsAt < resolvedReadyAt then
			cooldownState.StartsAt = startsAt
		end
		if duration and duration > 0 then
			cooldownState.Duration = duration
		end
	end

	localCooldowns[abilityName] = cooldownState
end

local function getOrderedAbilities(fruitName)
	return DevilFruitUiController.GetOrderedAbilities(fruitName)
end

local function setRuntimeAttribute(name, value)
	player:SetAttribute(name, value)
end

local function shouldShowCooldownHud(fruitName)
	return DevilFruitUiController.ShouldShowCooldownHud(fruitName)
end

local function loadCooldownHudComponent()
	if cooldownHudComponent and react and reactRoblox then
		return true
	end

	local packages = ReplicatedStorage:WaitForChild("Packages")
	local uiFolder = ReplicatedStorage:WaitForChild("UI")
	local devilFruitUiFolder = uiFolder:WaitForChild("DevilFruit")

	react = require(packages:WaitForChild("React"))
	reactRoblox = require(packages:WaitForChild("ReactRoblox"))
	cooldownHudComponent = require(devilFruitUiFolder:WaitForChild("CooldownHud"))

	return true
end

local function ensureCooldownHudRoot()
	loadCooldownHudComponent()

	if cooldownHudRoot then
		return
	end

	cooldownHudRootContainer = Instance.new("Folder")
	cooldownHudRootContainer.Name = "ReactDevilFruitHudRoot"
	cooldownHudRoot = reactRoblox.createRoot(cooldownHudRootContainer)
end

local function getCooldownHudHost()
	local hud = playerGui:FindFirstChild("HUD")
	if hud and hud:IsA("ScreenGui") then
		return hud
	end

	local fallback = playerGui:FindFirstChild("DevilFruitHUDHost")
	if fallback and fallback:IsA("ScreenGui") then
		return fallback
	end

	if fallback then
		fallback:Destroy()
	end

	fallback = Instance.new("ScreenGui")
	fallback.Name = "DevilFruitHUDHost"
	fallback.DisplayOrder = 118
	fallback.IgnoreGuiInset = true
	fallback.ResetOnSpawn = false
	fallback.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	fallback.Parent = playerGui
	return fallback
end

local function buildCooldownAbilities(fruitName)
	local abilities = {}
	for _, entry in ipairs(getOrderedAbilities(fruitName)) do
		local abilityName = entry.Name
		local abilityConfig = entry.Config or {}
		local cooldownValue = tonumber(abilityConfig.Cooldown) or 0
		local cooldownState = if isCooldownBypassEnabled() then nil else localCooldowns[abilityName]
		local readyAt = getLocalCooldownReadyAt(cooldownState)
		local now = getCooldownNow()
		local remaining = math.max(0, readyAt - now)
		local startsAt = getLocalCooldownStartsAt(cooldownState, cooldownValue)
		local startsIn = math.max(0, startsAt - now)
		local isWaitingForCooldownStart = remaining > 0 and startsIn > 0
		local total = math.max(getLocalCooldownDuration(cooldownState, cooldownValue), 0.001)
		local progress = if isWaitingForCooldownStart then 1 else math.clamp(1 - (remaining / total), 0, 1)
		local isReady = remaining <= 0

		if isReady then
			localCooldowns[abilityName] = nil
		end

		local status = "READY"
		local statusColor3 = DEVIL_FRUIT_UI.Ready
		local detail = "Move ready"
		if isWaitingForCooldownStart then
			status = "ACTIVE"
			detail = "Cooldown starts in " .. formatCooldownTime(startsIn)
		elseif not isReady then
			status = "CD " .. formatCooldownTime(remaining)
			statusColor3 = DEVIL_FRUIT_UI.Cooldown
			detail = "On cooldown for " .. formatCooldownTime(remaining)
		end

		local keyCode = abilityConfig.KeyCode
		abilities[#abilities + 1] = {
			detail = detail,
			fillColor3 = (isReady or isWaitingForCooldownStart) and DEVIL_FRUIT_UI.Ready
				or DEVIL_FRUIT_UI.CooldownFill,
			keyCodeName = keyCode and keyCode.Name or "?",
			name = formatAbilityName(abilityName),
			progress = progress,
			status = status,
			statusColor3 = statusColor3,
		}
	end

	return abilities
end

local function renderCooldownHud()
	local ok, err = xpcall(function()
		ensureCooldownHudRoot()
		local fruitName = cooldownHud.CurrentFruit
		local fruit = fruitName and DevilFruitConfig.GetFruit(fruitName)
		cooldownHudRoot:render(reactRoblox.createPortal(react.createElement(cooldownHudComponent, {
			abilities = cooldownHud.Abilities,
			fruitName = fruit and tostring(fruit.DisplayName or fruitName) or "",
			visible = cooldownHud.Visible == true,
		}), getCooldownHudHost()))
	end, debug.traceback)
	if ok then
		cooldownHudLastError = nil
		return true
	end

	if cooldownHudLastError ~= tostring(err) then
		cooldownHudLastError = tostring(err)
		warn(string.format("[DEVILFRUIT CLIENT][HUD] React cooldown HUD failed: %s", cooldownHudLastError))
	end

	return false
end

local function hideCooldownHud()
	cooldownHud.Visible = false
	cooldownHud.CurrentFruit = nil
	cooldownHud.Abilities = {}
	renderCooldownHud()
end

local function updateCooldownHud(_forceRebuild)
	local fruitName = getEquippedFruit()
	if not shouldShowCooldownHud(fruitName) then
		hideCooldownHud()
		return
	end

	cooldownHud.Visible = true
	cooldownHud.CurrentFruit = fruitName
	cooldownHud.Abilities = buildCooldownAbilities(fruitName)
	renderCooldownHud()
end

getFruitFolder = function()
	return player:FindFirstChild("DevilFruit")
end

getEquippedFruit = function()
	local equippedValueFruitName
	local fruitFolder = getFruitFolder()
	if fruitFolder then
		local equipped = fruitFolder:FindFirstChild("Equipped")
		if equipped and equipped:IsA("StringValue") then
			equippedValueFruitName = normalizeEquippedFruitName(equipped.Value)
			if equippedValueFruitName ~= DevilFruitConfig.None then
				return equippedValueFruitName
			end
		end
	end

	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		local attributeFruitName = normalizeEquippedFruitName(fruitAttribute)
		if attributeFruitName ~= DevilFruitConfig.None then
			return attributeFruitName
		end
	end

	return equippedValueFruitName or DevilFruitConfig.None
end

local function hookEquippedFruitValue(equippedValue)
	if not equippedValue or not equippedValue:IsA("StringValue") then
		return
	end

	if equippedValue:GetAttribute("__DevilFruitHudHooked") == true then
		return
	end

	equippedValue:SetAttribute("__DevilFruitHudHooked", true)
	equippedValue:GetPropertyChangedSignal("Value"):Connect(function()
		if typeof(syncDevilFruitClientState) == "function" then
			task.defer(syncDevilFruitClientState, "equipped_value_changed")
			return
		end

		updateCooldownHud(true)
	end)
end

local function hookFruitFolderSignals()
	local fruitFolder = getFruitFolder()
	if not fruitFolder then
		return
	end

	local equippedValue = fruitFolder:FindFirstChild("Equipped")
	if equippedValue then
		hookEquippedFruitValue(equippedValue)
	end

	if fruitFolder:GetAttribute("__DevilFruitHudFolderHooked") == true then
		return
	end

	fruitFolder:SetAttribute("__DevilFruitHudFolderHooked", true)
	fruitFolder.ChildAdded:Connect(function(child)
		if child.Name == "Equipped" then
			hookEquippedFruitValue(child)
			if typeof(syncDevilFruitClientState) == "function" then
				task.defer(syncDevilFruitClientState, "equipped_value_added")
				return
			end

			updateCooldownHud(true)
		end
	end)
end

local function getAbilityForKeyCode(keyCode)
	local fruitName = getEquippedFruit()
	if inputController then
		local resolvedFruitName, abilityName, abilityEntry = inputController:GetAbilityForKeyCode(fruitName, keyCode)
		if resolvedFruitName and abilityName then
			return resolvedFruitName, abilityName, abilityEntry
		end
	end

	local fruit = DevilFruitConfig.GetFruit(fruitName)
	if not fruit or not fruit.Abilities then
		return nil, nil, nil
	end

	for abilityName, abilityConfig in pairs(fruit.Abilities) do
		if abilityConfig.KeyCode == keyCode then
			return fruitName, abilityName, Registry.GetAbility(fruitName, abilityName)
		end
	end

	return nil, nil, nil
end

local function isLocallyReady(abilityName)
	if isCooldownBypassEnabled() then
		return true
	end

	local cooldownState = localCooldowns[abilityName]
	if not cooldownState then
		return true
	end

	local readyAt = getLocalCooldownReadyAt(cooldownState)
	if getCooldownNow() >= readyAt then
		localCooldowns[abilityName] = nil
		return true
	end

	return false
end

local function getCharacter()
	return player.Character
end

local function getCurrentCamera()
	return Workspace.CurrentCamera
end

local function getHumanoid()
	local character = getCharacter()
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRootPart()
	local character = getCharacter()
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local clientEffectVisuals = ClientEffectVisuals.new({
	GetLocalRootPart = getRootPart,
	GetPlayerRootPart = getPlayerRootPart,
	MinDirectionMagnitude = MIN_DIRECTION_MAGNITUDE,
	PhoenixFruitName = PHOENIX_FRUIT_NAME,
	PhoenixFlightAbility = PHOENIX_FLIGHT_ABILITY,
	PhoenixShieldAbility = PHOENIX_SHIELD_ABILITY,
	PhoenixRebirthAbility = PHOENIX_REBIRTH_ABILITY,
})

local function buildDefaultAbilityRequestPayload(_fruitName, _abilityName)
	return nil
end

local function buildAbilityRequestPayload(fruitName, abilityName)
	local abilityEntry = Registry.GetAbility(fruitName, abilityName)
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	local rootPart = character and character:FindFirstChild("HumanoidRootPart") or nil
	local moveDirection = humanoid and humanoid.MoveDirection or nil
	logDevilFruitRequest(
		"client build begin fruit=%s ability=%s abilityEntry=%s character=%s humanoid=%s root=%s moveDir=%s lookDir=%s",
		tostring(fruitName),
		tostring(abilityName),
		tostring(abilityEntry ~= nil),
		tostring(character ~= nil),
		tostring(humanoid ~= nil),
		tostring(rootPart ~= nil),
		formatVector3ForLog(moveDirection),
		formatVector3ForLog(rootPart and rootPart.CFrame.LookVector or nil)
	)
	if inputController then
		local payload = inputController:BuildRequestPayload(fruitName, abilityName, abilityEntry, function()
			return buildDefaultAbilityRequestPayload(fruitName, abilityName)
		end)
		logDevilFruitRequest(
			"client build end fruit=%s ability=%s payloadKeys=%d",
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(payload)
		)
		return payload
	end

	local fallbackPayload = buildDefaultAbilityRequestPayload(fruitName, abilityName)
	logDevilFruitRequest(
		"client build end fruit=%s ability=%s payloadKeys=%d source=default_builder_only",
		tostring(fruitName),
		tostring(abilityName),
		countPayloadKeys(fallbackPayload)
	)
	return fallbackPayload
end

local function isDescendantOfClientWave(instance, clientWavesFolder)
	clientWavesFolder = clientWavesFolder or MapResolver.GetRefs().ClientWaves
	if not clientWavesFolder then
		return false
	end

	return instance:IsDescendantOf(clientWavesFolder)
end

local function getWaveTemplate(instance)
	local current = instance
	while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
		current = current.Parent
	end

	if not current then
		return nil
	end

	local wavesFolder = ReplicatedStorage:FindFirstChild("Waves")
	if not wavesFolder then
		return nil
	end

	return wavesFolder:FindFirstChild(current.Name)
end

local function getHazardContainer(instance, clientWavesFolder)
	local root, hazardClass, hazardType, canFreeze, freezeBehavior = HazardUtils.GetHazardInfo(instance)
	if root then
		return root, hazardClass, hazardType, canFreeze, freezeBehavior
	end

	if isDescendantOfClientWave(instance, clientWavesFolder) then
		local template = getWaveTemplate(instance)
		if template then
			local _, templateClass, templateType, templateCanFreeze, templateFreezeBehavior = HazardUtils.GetHazardInfo(template)
			if templateClass or templateType or templateCanFreeze or templateFreezeBehavior then
				local current = instance
				while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
					current = current.Parent
				end

				return current or instance, templateClass, templateType, templateCanFreeze, templateFreezeBehavior
			end
		end
	end

	return nil, nil, nil, false, nil
end

local function getLatestSuppressionUntilTime(sources)
	local latestUntilTime = nil
	for _, sourceUntilTime in pairs(sources) do
		if typeof(sourceUntilTime) == "number" and (latestUntilTime == nil or sourceUntilTime > latestUntilTime) then
			latestUntilTime = sourceUntilTime
		end
	end

	return latestUntilTime
end

local function getSuppressionSources(state)
	if type(state.Sources) ~= "table" then
		state.Sources = {
			[DEFAULT_HAZARD_SUPPRESSION_SOURCE] = tonumber(state.UntilTime) or 0,
		}
	end

	return state.Sources
end

local function pruneExpiredSuppressionSources(sources, now)
	for source, sourceUntilTime in pairs(sources) do
		if typeof(sourceUntilTime) ~= "number" or now >= sourceUntilTime then
			sources[source] = nil
		end
	end
end

local function suppressPart(part, untilTime, source)
	if not part or not part:IsA("BasePart") then
		return
	end

	local sourceKey = source or DEFAULT_HAZARD_SUPPRESSION_SOURCE
	local state = suppressedParts[part]
	if state then
		local sources = getSuppressionSources(state)
		sources[sourceKey] = math.max(tonumber(sources[sourceKey]) or 0, untilTime)
		if untilTime > state.UntilTime then
			state.UntilTime = untilTime
		end
		return
	end

	suppressedParts[part] = {
		OriginalCanTouch = part.CanTouch,
		OriginalCanCollide = part.CanCollide,
		UntilTime = untilTime,
		Sources = {
			[sourceKey] = untilTime,
		},
	}

	part.CanTouch = false
	part.CanCollide = false
end

local function suppressHazard(container, untilTime, source)
	if not container then
		return
	end

	if container:IsA("BasePart") then
		suppressPart(container, untilTime, source)
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			suppressPart(descendant, untilTime, source)
		end
	end
end

local function restoreSuppressedParts(now, source)
	for part, state in pairs(suppressedParts) do
		if not part or not part.Parent then
			suppressedParts[part] = nil
		else
			local sources = getSuppressionSources(state)
			if source then
				sources[source] = nil
			end

			pruneExpiredSuppressionSources(sources, now)
			local latestUntilTime = getLatestSuppressionUntilTime(sources)
			if latestUntilTime then
				state.UntilTime = latestUntilTime
			else
				part.CanTouch = state.OriginalCanTouch
				part.CanCollide = state.OriginalCanCollide
				suppressedParts[part] = nil
			end
		end
	end
end

local function getMoguHazardProtectionRadius()
	local abilityConfig = DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}
	return math.max(0, tonumber(abilityConfig.HazardProtectionRadius) or DEFAULT_MOGU_HAZARD_PROTECTION_RADIUS)
end

local function getMoguResolveHazardProbePadding()
	local abilityConfig = DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}
	return math.max(
		0,
		tonumber(abilityConfig.ResolveHazardProbePadding)
			or tonumber(abilityConfig.SurfaceHazardProbePadding)
			or DEFAULT_MOGU_RESOLVE_HAZARD_PROBE_PADDING
	)
end

local function isLocalPlayerBurrowProtected(now)
	if type(activeMoguBurrow) ~= "table" then
		return false
	end

	if now >= (activeMoguBurrow.EndTime or 0) then
		activeMoguBurrow = nil
		return false
	end

	return true
end

ProtectionRuntime.Register("MoguBurrowProtection", function(targetPlayer, _position)
	if targetPlayer ~= player then
		return false
	end

	return isLocalPlayerBurrowProtected(os.clock())
end)

local function buildLocalHazardOverlapParams(refs, restrictToHazardRoots)
	local overlapParams = OverlapParams.new()
	refs = refs or MapResolver.GetRefs()

	if restrictToHazardRoots == true then
		local queryRoots = {}
		local waveFolder = refs and refs.WaveFolder
		local sharedHazardsFolder = waveFolder and waveFolder:FindFirstChild("Hazards")
		if sharedHazardsFolder then
			queryRoots[#queryRoots + 1] = sharedHazardsFolder
		end
		if refs and refs.ClientWaves then
			queryRoots[#queryRoots + 1] = refs.ClientWaves
		end

		if #queryRoots > 0 then
			overlapParams.FilterType = Enum.RaycastFilterType.Include
			overlapParams.FilterDescendantsInstances = queryRoots
			overlapParams.MaxParts = LOCAL_HAZARD_OVERLAP_MAX_PARTS
			return overlapParams
		end
	end

	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = player.Character and { player.Character } or {}
	return overlapParams
end

local function suppressHazardsNearPosition(centerPosition, radius, untilTime, shouldSuppress, restrictToHazardRoots, source)
	if typeof(centerPosition) ~= "Vector3" or radius <= 0 then
		return
	end

	local refs = MapResolver.GetRefs()
	local clientWavesFolder = refs and refs.ClientWaves
	local nearbyParts = Workspace:GetPartBoundsInRadius(
		centerPosition,
		radius,
		buildLocalHazardOverlapParams(refs, restrictToHazardRoots)
	)
	for _, part in ipairs(nearbyParts) do
		local container, hazardClass, hazardType = getHazardContainer(part, clientWavesFolder)
		if container and (shouldSuppress == nil or shouldSuppress(container, hazardClass, hazardType)) then
			suppressHazard(container, untilTime, source)
		end
	end
end

local function fireWaveKillFromMoguSurface(rootPosition)
	local character = getCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	if ProtectionRuntime.IsProtected(player, rootPosition, "WaveKill") then
		return
	end

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local killMeEvent = remotesFolder and remotesFolder:FindFirstChild("KillMe")
	if killMeEvent and killMeEvent:IsA("RemoteEvent") then
		killMeEvent:FireServer()
	else
		humanoid.Health = 0
	end
end

local function applyMoguSurfaceHazardOverlap()
	local rootPart = getRootPart()
	if not rootPart then
		return false
	end

	local refs = MapResolver.GetRefs()
	local clientWavesFolder = refs and refs.ClientWaves
	local padding = getMoguResolveHazardProbePadding()
	local probeSize = rootPart.Size + Vector3.new(padding * 2, padding * 2, padding * 2)
	local nearbyParts = Workspace:GetPartBoundsInBox(
		rootPart.CFrame,
		probeSize,
		buildLocalHazardOverlapParams(refs, true)
	)

	for _, part in ipairs(nearbyParts) do
		local container, hazardClass, hazardType = getHazardContainer(part, clientWavesFolder)
		if container and hazardClass ~= "minor" and hazardType == "wave" and container:GetAttribute("Frozen") ~= true then
			fireWaveKillFromMoguSurface(rootPart.Position)
			return true
		end
	end

	return false
end

local function hasActiveHazardProtection(now)
	if #activeFireBursts > 0 then
		return true
	end

	if isLocalPlayerBurrowProtected(now) then
		return true
	end

	return false
end

local function updateHazardSuppression()
	local now = os.clock()
	local rootPart = getRootPart()

	for i = #activeFireBursts, 1, -1 do
		local burst = activeFireBursts[i]
		if now >= burst.EndTime or not rootPart then
			table.remove(activeFireBursts, i)
		else
			-- Corridor hazards are client-created in this project, so Fire Burst
			-- suppresses nearby minor hazards locally after the server authorizes it.
			if now >= (burst.NextScanAt or 0) then
				burst.NextScanAt = now + FIRE_BURST_HAZARD_SUPPRESSION_INTERVAL
				suppressHazardsNearPosition(rootPart.Position, burst.Radius, burst.EndTime, function(_, hazardClass)
					return hazardClass == "minor"
				end, true, FIRE_BURST_HAZARD_SUPPRESSION_SOURCE)
			end
		end
	end

	if isLocalPlayerBurrowProtected(now) then
		if rootPart then
			suppressHazardsNearPosition(
				rootPart.Position,
				activeMoguBurrow.Radius,
				activeMoguBurrow.EndTime,
				nil,
				nil,
				MOGU_HAZARD_SUPPRESSION_SOURCE
			)
		end
	end

	restoreSuppressedParts(now)

	if hasActiveHazardProtection(now) then
		task.delay(HAZARD_SUPPRESSION_INTERVAL, updateHazardSuppression)
	else
		hazardSuppressionLoopRunning = false
	end
end

local function ensureHazardSuppressionLoop()
	if hazardSuppressionLoopRunning then
		return
	end

	hazardSuppressionLoopRunning = true
	updateHazardSuppression()
end

local function startFireBurst(_payload)
	-- FireBurst hazard targets are not ready yet; skip local hazard scans to avoid release stutter.
end

local function startMoguBurrow(targetPlayer, payload)
	if targetPlayer ~= player then
		return
	end

	local resolvedPayload = payload or {}
	local duration = math.max(0, tonumber(resolvedPayload.Duration) or 0)
	if duration <= 0 then
		duration = math.max(0.5, tonumber((DevilFruitConfig.GetAbility(MOGU_FRUIT_NAME, MOGU_BURROW_ABILITY) or {}).BurrowDuration) or 5)
	end

	activeMoguBurrow = {
		EndTime = os.clock() + duration,
		Radius = math.max(0, tonumber(resolvedPayload.HazardProtectionRadius) or getMoguHazardProtectionRadius()),
	}

	ensureHazardSuppressionLoop()
end

local function stopMoguBurrow(targetPlayer)
	if targetPlayer ~= player then
		return
	end

	activeMoguBurrow = nil
	restoreSuppressedParts(os.clock(), MOGU_HAZARD_SUPPRESSION_SOURCE)
	applyMoguSurfaceHazardOverlap()
end

local function _getProjectileDirection(direction, rootPart)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.01 then
		if not rootPart then
			return Vector3.new(0, 0, -1)
		end

		direction = rootPart.CFrame.LookVector
	end

	local planarDirection = Vector3.new(direction.X, 0, direction.Z)
	if planarDirection.Magnitude > 0.01 then
		return planarDirection.Unit
	end

	if direction.Magnitude > 0.01 then
		return direction.Unit
	end

	return Vector3.new(0, 0, -1)
end

playOptionalEffect = function(targetPlayer, fruitName, abilityName, payload)
	return DevilFruitOptionalEffects.Play(targetPlayer, fruitName, abilityName, payload)
end

fruitModuleLoader = FruitModuleLoader.new({
	player = player,
	clientEffectVisuals = clientEffectVisuals,
	GetCharacter = getCharacter,
	GetCurrentCamera = getCurrentCamera,
	GetEquippedFruit = getEquippedFruit,
	GetHumanoid = getHumanoid,
	GetLocalRootPart = getRootPart,
	GetPlayerRootPart = getPlayerRootPart,
	PlayOptionalEffect = playOptionalEffect,
	RequestAbility = function(abilityName, payload)
		requestRemote:FireServer(abilityName, payload)
		return true
	end,
	CreateEffectVisual = function(startPosition, endPosition, direction, isPredicted)
		clientEffectVisuals:CreateMeraFlameDashEffectVisual(startPosition, endPosition, direction, isPredicted)
	end,
})
inputController = DevilFruitInputController.new({
	player = player,
	loader = fruitModuleLoader,
})
effectRouter = DevilFruitEffectRouter.new({
	player = player,
	loader = fruitModuleLoader,
	playOptionalEffect = playOptionalEffect,
	clientEffectVisuals = clientEffectVisuals,
})

local function initializeDevilFruitClient()
	logDevilFruitClient("init begin")
	setRuntimeAttribute("DevilFruitClientRuntimeStarted", true)
	remoteBundle = DevilFruitRemotes.GetBundle()
	requestRemote = remoteBundle.Request
	stateRemote = remoteBundle.State
	effectRemote = remoteBundle.Effect
	local requestIdentity = describeRemote(requestRemote)
	logDevilFruitClient(
		"remote bundle resolved request=%s path=%s runtimeId=%s debugId=%s object=%s state=%s effect=%s folder=%s",
		tostring(requestIdentity.Name),
		tostring(requestIdentity.Path),
		tostring(requestIdentity.RuntimeId),
		tostring(requestIdentity.DebugId),
		tostring(requestIdentity.Object),
		tostring(describeRemote(stateRemote).Path),
		tostring(describeRemote(effectRemote).Path),
		tostring(remoteBundle.Folder:GetFullName())
	)
	setRuntimeAttribute("DevilFruitClientRemotesReady", true)
	setRuntimeAttribute("DevilFruitClientLastRemoteError", nil)

	local function performSyncDevilFruitClientState(reason)
		local currentFruitName = getEquippedFruit()
		local previousFruitName = lastSyncedFruitName
		if currentFruitName ~= lastSyncedFruitName then
			fruitModuleLoader:CallControllerMethod(previousFruitName, "HandleUnequipped", currentFruitName)
			logDevilFruitClient(
				"fruit changed previous=%s current=%s",
				tostring(lastSyncedFruitName),
				tostring(currentFruitName)
			)
			lastSyncedFruitName = currentFruitName
		end

		local warmedController = fruitModuleLoader:GetController(currentFruitName)
		if warmedController and currentFruitName ~= previousFruitName then
			fruitModuleLoader:CallControllerMethod(currentFruitName, "HandleEquipped", previousFruitName)
		end

		hookFruitFolderSignals()
		updateCooldownHud(true)
		setRuntimeAttribute("DevilFruitClientEquippedFruit", currentFruitName)
		setRuntimeAttribute("DevilFruitClientHudVisible", cooldownHud.Visible == true)
		setRuntimeAttribute("DevilFruitClientAbilityCount", #cooldownHud.Abilities)
		local fruitFolder = getFruitFolder()
		local equippedValue = fruitFolder and fruitFolder:FindFirstChild("Equipped")
		local equippedValueText = equippedValue and equippedValue:IsA("StringValue") and equippedValue.Value or "<nil>"
		logDevilFruitClient(
			"fruit state synced reason=%s equipped=%s attr=%s value=%s",
			tostring(reason or "unknown"),
			tostring(currentFruitName),
			tostring(player:GetAttribute("EquippedDevilFruit")),
			tostring(equippedValueText)
		)
	end

	syncDevilFruitClientState = function(reason)
		local ok, err = xpcall(function()
			performSyncDevilFruitClientState(reason)
		end, debug.traceback)
		if ok then
			setRuntimeAttribute("DevilFruitClientLastSyncError", nil)
			return true
		end

		setRuntimeAttribute("DevilFruitClientLastSyncError", tostring(err))
		warn(string.format("[DEVILFRUIT CLIENT][SYNC] failed reason=%s detail=%s", tostring(reason or "unknown"), tostring(err)))
		return false
	end

	logDevilFruitClient("UI bind success")

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local traceAbilityInput = shouldTraceAbilityInput(input.KeyCode)
		local equippedFruitName = traceAbilityInput and getEquippedFruit() or nil
		local focusedTextBox = UserInputService:GetFocusedTextBox()
		if traceAbilityInput then
			logDevilFruitClient(
				"bind raw key=%s processed=%s focused=%s modal=%s equipped=%s",
				tostring(input.KeyCode.Name),
				tostring(gameProcessed),
				tostring(focusedTextBox ~= nil),
				"false",
				tostring(equippedFruitName)
			)
		end

		if gameProcessed then
			if traceAbilityInput then
				logDevilFruitClient(
					"bind blocked key=%s reason=game_processed equipped=%s",
					tostring(input.KeyCode.Name),
					tostring(equippedFruitName)
				)
			end
			return
		end

		if focusedTextBox then
			if traceAbilityInput then
				logDevilFruitClient(
					"bind blocked key=%s reason=textbox_focus textbox=%s equipped=%s",
					tostring(input.KeyCode.Name),
					tostring(focusedTextBox:GetFullName()),
					tostring(equippedFruitName)
				)
			end
			return
		end

		local handledByCurrentFruit, shouldConsumeInput = fruitModuleLoader:CallControllerMethod(
			equippedFruitName or getEquippedFruit(),
			"HandleInputBegan",
			input,
			gameProcessed
		)
		if handledByCurrentFruit and shouldConsumeInput then
			return
		end

		local fruitName, abilityName, abilityEntry = getAbilityForKeyCode(input.KeyCode)
		if traceAbilityInput then
			logDevilFruitClient(
				"bind lookup key=%s equipped=%s resolvedFruit=%s ability=%s hasEntry=%s",
				tostring(input.KeyCode.Name),
				tostring(equippedFruitName),
				tostring(fruitName),
				tostring(abilityName),
				tostring(abilityEntry ~= nil)
			)
		end
		if not abilityName then
			if input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.C then
				logDevilFruitClient(
					"bind ignored key=%s equipped=%s reason=no_ability",
					tostring(input.KeyCode.Name),
					tostring(fruitName or getEquippedFruit())
				)
			end
			return
		end

		if not isLocallyReady(abilityName) then
			local _, canActivateOnLocalCooldown = fruitModuleLoader:CallControllerMethod(
				fruitName,
				"CanActivateOnLocalCooldown",
				abilityName,
				abilityEntry,
				input
			)
			if canActivateOnLocalCooldown == true then
				logDevilFruitClient(
					"bind bypass local cooldown key=%s fruit=%s ability=%s",
					tostring(input.KeyCode.Name),
					tostring(fruitName),
					tostring(abilityName)
				)
			else
				logDevilFruitClient(
					"bind ignored key=%s fruit=%s ability=%s reason=local_cooldown",
					tostring(input.KeyCode.Name),
					tostring(fruitName),
					tostring(abilityName)
				)
				return
			end
		end

		local requestStartedAt = os.clock()
		local dispatchRequestIdentity = describeRemote(requestRemote)
		logDevilFruitRequest(
			"client dispatch begin key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(dispatchRequestIdentity.Name),
			tostring(dispatchRequestIdentity.Path),
			tostring(dispatchRequestIdentity.RuntimeId),
			tostring(dispatchRequestIdentity.DebugId),
			tostring(dispatchRequestIdentity.Object)
		)
		local requestPayload = inputController:BuildPredictedRequest(fruitName, abilityName, function()
			return buildAbilityRequestPayload(fruitName, abilityName)
		end)
		logDevilFruitClient(
			"bind dispatch key=%s fruit=%s ability=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(requestPayload)
		)
		logDevilFruitClient(
			"remote fire begin key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(dispatchRequestIdentity.Name),
			tostring(dispatchRequestIdentity.Path),
			tostring(dispatchRequestIdentity.RuntimeId),
			tostring(dispatchRequestIdentity.DebugId),
			tostring(dispatchRequestIdentity.Object),
			countPayloadKeys(requestPayload)
		)
		requestRemote:FireServer(abilityName, requestPayload)
		logDevilFruitClient(
			"remote fire end key=%s fruit=%s ability=%s remote=%s path=%s runtimeId=%s debugId=%s object=%s payloadKeys=%d",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			tostring(dispatchRequestIdentity.Name),
			tostring(dispatchRequestIdentity.Path),
			tostring(dispatchRequestIdentity.RuntimeId),
			tostring(dispatchRequestIdentity.DebugId),
			tostring(dispatchRequestIdentity.Object),
			countPayloadKeys(requestPayload)
		)
		logDevilFruitRequest(
			"client dispatch end key=%s fruit=%s ability=%s payloadKeys=%d elapsedMs=%.2f",
			tostring(input.KeyCode.Name),
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(requestPayload),
			(os.clock() - requestStartedAt) * 1000
		)
		if traceAbilityInput then
			logDevilFruitClient(
				"bind remote fired key=%s fruit=%s ability=%s",
				tostring(input.KeyCode.Name),
				tostring(fruitName),
				tostring(abilityName)
			)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		fruitModuleLoader:CallControllerMethod(getEquippedFruit(), "HandleInputEnded", input)
	end)
	logDevilFruitClient("keybind connect success")

	local function handleStateEvent(eventName, fruitName, abilityName, value, payload)
		if eventName == "Activated" then
			local readyAt = tonumber(value) or 0
			setLocalCooldown(abilityName, readyAt, payload)
			updateCooldownHud()

			fruitModuleLoader:CallControllerMethod(fruitName, "HandleStateEvent", eventName, abilityName, value, payload)

			if fruitName == "Mera Mera no Mi" and abilityName == "FireBurst" then
				startFireBurst(payload or {})
			end
			return
		end

		fruitModuleLoader:CallControllerMethod(fruitName, "HandleStateEvent", eventName, abilityName, value, payload)

		if eventName == "Denied" and value == "Cooldown" then
			local readyAt = tonumber(payload) or 0
			if readyAt > 0 then
				setLocalCooldown(abilityName, readyAt)
				updateCooldownHud()
			end
		end
	end

	local function handleEffectEvent(targetPlayer, fruitName, abilityName, payload)
		local hasPlayerTarget = targetPlayer and targetPlayer:IsA("Player")
		if not hasPlayerTarget and not isBomuLandMineWorldEffect(targetPlayer, fruitName, abilityName, payload) then
			return
		end

		if hasPlayerTarget and fruitName == MOGU_FRUIT_NAME and abilityName == MOGU_BURROW_ABILITY then
			local phase = payload and payload.Phase
			if phase == "Start" then
				startMoguBurrow(targetPlayer, payload)
				effectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
				return
			elseif phase == "Resolve" then
				effectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
				stopMoguBurrow(targetPlayer)
				return
			end
		end

		effectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
	end

	stateRemote.OnClientEvent:Connect(handleStateEvent)
	effectRemote.OnClientEvent:Connect(handleEffectEvent)

	RunService.Heartbeat:Connect(function(dt)
		fruitModuleLoader:ForEachLoadedController("Update", dt)
	end)

	player.CharacterRemoving:Connect(function()
		activeFireBursts = {}
		activeMoguBurrow = nil
		fruitModuleLoader:ForEachLoadedController("HandleCharacterRemoving")
		hazardSuppressionLoopRunning = false
		restoreSuppressedParts(math.huge)
	end)

	Players.PlayerRemoving:Connect(function(leavingPlayer)
		fruitModuleLoader:ForEachLoadedController("HandlePlayerRemoving", leavingPlayer)
	end)

	player.CharacterAdded:Connect(function()
		if hasActiveHazardProtection(os.clock()) then
			ensureHazardSuppressionLoop()
		end
	end)

	player:GetAttributeChangedSignal("EquippedDevilFruit"):Connect(function()
		syncDevilFruitClientState("equipped_attribute_changed")
	end)

	player:GetAttributeChangedSignal("DevilFruitCooldownBypass"):Connect(function()
		updateCooldownHud(false)
	end)

	player.ChildAdded:Connect(function(child)
		if child.Name == "DevilFruit" then
			syncDevilFruitClientState("fruit_folder_added")
		end
	end)

	RunService.RenderStepped:Connect(function()
		fruitModuleLoader:ForEachLoadedController("RenderUpdate")

		local now = os.clock()
		if now >= nextStateReconcileAt then
			nextStateReconcileAt = now + STATE_RECONCILE_INTERVAL

			local currentFruitName = getEquippedFruit()
			local expectedAbilityCount = #getOrderedAbilities(currentFruitName)
			local hasValidFruit = shouldShowCooldownHud(currentFruitName)
			local needsFruitSync = currentFruitName ~= lastSyncedFruitName
			local needsHudRepair = hasValidFruit
				and (
					cooldownHud.CurrentFruit ~= currentFruitName
					or cooldownHud.Visible ~= true
					or #cooldownHud.Abilities ~= expectedAbilityCount
				)

			if needsFruitSync or needsHudRepair then
				syncDevilFruitClientState("render_reconcile")
			end
		end

		if now < nextHudRefreshAt then
			return
		end

		nextHudRefreshAt = now + HUD_REFRESH_INTERVAL
		updateCooldownHud(false)
	end)

	task.defer(function()
		syncDevilFruitClientState("startup")
	end)

	logDevilFruitClient("init success")
end

function DevilFruitClientController.Start()
	if started then
		return DevilFruitClientController
	end

	started = true

	local initOk, initError = xpcall(initializeDevilFruitClient, debug.traceback)
	if not initOk then
		started = false
		warn(string.format("[DEVILFRUIT CLIENT][ERROR] startup failed: %s", tostring(initError)))
		error(initError)
	end

	return DevilFruitClientController
end

return DevilFruitClientController
