local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local AFKGoldChestRewardService = {}

local STATE_PATH = "ChestRewards.AFKGoldChests"
local DEFAULT_STATE_EVENT_NAME = "AFKGoldChestState"
local DEFAULT_STATE_REQUEST_NAME = "AFKGoldChestStateRequest"
local DEFAULT_ENTRY_REQUEST_NAME = "AFKGoldChestEntryRequest"
local DEFAULT_EXIT_REQUEST_NAME = "AFKGoldChestExitRequest"
local DEFAULT_UI_HEARTBEAT_EVENT_NAME = "AFKGoldChestUiHeartbeat"
local DEFAULT_REWARD_TIER = "Gold"
local DEFAULT_SOURCE = "AFK"
local DEFAULT_NORMAL_INTERVAL_SECONDS = 3600
local DEFAULT_PREMIUM_INTERVAL_SECONDS = 1800
local DEFAULT_NORMAL_DAILY_CAP = 8
local DEFAULT_PREMIUM_DAILY_CAP = 16
local DEFAULT_ENTRY_MAX_DISTANCE = 18
local DEFAULT_SHIP_AFK_RADIUS = 34
local TICK_SECONDS = 1
local MAX_DELTA_SECONDS = 5
local PERSIST_INTERVAL_SECONDS = 30
local GRANT_RETRY_SECONDS = 30
local UI_HEARTBEAT_INTERVAL_SECONDS = 5
local UI_HEARTBEAT_TIMEOUT_SECONDS = 15
local EXIT_TELEPORT_OFFSET = Vector3.new(0, 4, 0)
local RAYLEIGH_EXIT_OFFSET = Vector3.new(0, 0, 10)

local started = false
local dataManagerRef = nil
local stateEvent = nil
local stateRequest = nil
local entryRequest = nil
local exitRequest = nil
local uiHeartbeatEvent = nil
local runtimeByPlayer = {}
local verticalSliceService = nil
local shipRuntimeService = nil

local function getAfkConfig()
	local chests = if typeof(Economy.Chests) == "table" then Economy.Chests else {}
	return if typeof(chests.AFKGoldRewards) == "table" then chests.AFKGoldRewards else {}
end

local function getEntryConfig()
	local config = getAfkConfig()
	return if typeof(config.Entry) == "table" then config.Entry else {}
end

local function getNumber(value, fallback)
	local numberValue = tonumber(value)
	if numberValue == nil then
		return fallback
	end
	return numberValue
end

local function getPositiveInteger(value, fallback)
	return math.max(1, math.floor(getNumber(value, fallback)))
end

local function getPositiveNumber(value, fallback)
	return math.max(0.01, getNumber(value, fallback))
end

local function todayUtc()
	return os.date("!%Y-%m-%d")
end

local function getOrCreateRemotes()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local config = getAfkConfig()
	local remoteConfig = if typeof(config.Remotes) == "table" then config.Remotes else {}
	local stateEventName = tostring(remoteConfig.StateEventName or DEFAULT_STATE_EVENT_NAME)
	local stateRequestName = tostring(remoteConfig.StateRequestName or DEFAULT_STATE_REQUEST_NAME)
	local entryRequestName = tostring(remoteConfig.EntryRequestName or DEFAULT_ENTRY_REQUEST_NAME)
	local exitRequestName = tostring(remoteConfig.ExitRequestName or DEFAULT_EXIT_REQUEST_NAME)
	local uiHeartbeatEventName = tostring(remoteConfig.UiHeartbeatEventName or DEFAULT_UI_HEARTBEAT_EVENT_NAME)

	local existingStateEvent = remotes:FindFirstChild(stateEventName)
	if existingStateEvent and not existingStateEvent:IsA("RemoteEvent") then
		existingStateEvent:Destroy()
		existingStateEvent = nil
	end
	if not existingStateEvent then
		existingStateEvent = Instance.new("RemoteEvent")
		existingStateEvent.Name = stateEventName
		existingStateEvent.Parent = remotes
	end

	local existingStateRequest = remotes:FindFirstChild(stateRequestName)
	if existingStateRequest and not existingStateRequest:IsA("RemoteFunction") then
		existingStateRequest:Destroy()
		existingStateRequest = nil
	end
	if not existingStateRequest then
		existingStateRequest = Instance.new("RemoteFunction")
		existingStateRequest.Name = stateRequestName
		existingStateRequest.Parent = remotes
	end

	local existingEntryRequest = remotes:FindFirstChild(entryRequestName)
	if existingEntryRequest and not existingEntryRequest:IsA("RemoteFunction") then
		existingEntryRequest:Destroy()
		existingEntryRequest = nil
	end
	if not existingEntryRequest then
		existingEntryRequest = Instance.new("RemoteFunction")
		existingEntryRequest.Name = entryRequestName
		existingEntryRequest.Parent = remotes
	end

	local existingExitRequest = remotes:FindFirstChild(exitRequestName)
	if existingExitRequest and not existingExitRequest:IsA("RemoteFunction") then
		existingExitRequest:Destroy()
		existingExitRequest = nil
	end
	if not existingExitRequest then
		existingExitRequest = Instance.new("RemoteFunction")
		existingExitRequest.Name = exitRequestName
		existingExitRequest.Parent = remotes
	end

	local existingUiHeartbeatEvent = remotes:FindFirstChild(uiHeartbeatEventName)
	if existingUiHeartbeatEvent and not existingUiHeartbeatEvent:IsA("RemoteEvent") then
		existingUiHeartbeatEvent:Destroy()
		existingUiHeartbeatEvent = nil
	end
	if not existingUiHeartbeatEvent then
		existingUiHeartbeatEvent = Instance.new("RemoteEvent")
		existingUiHeartbeatEvent.Name = uiHeartbeatEventName
		existingUiHeartbeatEvent.Parent = remotes
	end

	stateEvent = existingStateEvent
	stateRequest = existingStateRequest
	entryRequest = existingEntryRequest
	exitRequest = existingExitRequest
	uiHeartbeatEvent = existingUiHeartbeatEvent
end

local function getPlayerSettings(player)
	local config = getAfkConfig()
	local isPremium = player.MembershipType == Enum.MembershipType.Premium
	local normalConfig = if typeof(config.Normal) == "table" then config.Normal else {}
	local premiumConfig = if typeof(config.Premium) == "table" then config.Premium else {}
	local selectedConfig = if isPremium then premiumConfig else normalConfig

	local fallbackInterval = if isPremium then DEFAULT_PREMIUM_INTERVAL_SECONDS else DEFAULT_NORMAL_INTERVAL_SECONDS
	local fallbackCap = if isPremium then DEFAULT_PREMIUM_DAILY_CAP else DEFAULT_NORMAL_DAILY_CAP

	return {
		IsPremium = isPremium,
		IntervalSeconds = getPositiveInteger(selectedConfig.IntervalSeconds, fallbackInterval),
		DailyCap = getPositiveInteger(selectedConfig.DailyCap, fallbackCap),
		RewardTier = tostring(config.RewardTier or DEFAULT_REWARD_TIER),
		Source = tostring(config.Source or DEFAULT_SOURCE),
	}
end

local function sanitizeState(rawState)
	local state = if typeof(rawState) == "table" then rawState else {}
	local currentDay = todayUtc()

	if typeof(state.DayKey) ~= "string" then
		state.DayKey = ""
	end
	if state.DayKey ~= currentDay then
		state.DayKey = currentDay
		state.EarnedToday = 0
		state.ProgressSeconds = 0
	else
		state.EarnedToday = math.max(0, math.floor(getNumber(state.EarnedToday, 0)))
		state.ProgressSeconds = math.max(0, getNumber(state.ProgressSeconds, 0))
	end

	return state
end

local function getAfkState(player)
	if dataManagerRef == nil or typeof(dataManagerRef.TryGetValue) ~= "function" then
		return nil, "data_manager_unavailable"
	end
	if dataManagerRef:IsReady(player) ~= true then
		return nil, "profile_not_ready"
	end

	local rawState = dataManagerRef:TryGetValue(player, STATE_PATH)
	return sanitizeState(rawState), nil
end

local function persistAfkState(player, state)
	if dataManagerRef == nil or typeof(dataManagerRef.TrySetValue) ~= "function" then
		return false, "data_manager_unavailable"
	end
	if typeof(state) ~= "table" then
		return false, "invalid_state"
	end

	return dataManagerRef:TrySetValue(player, STATE_PATH, {
		DayKey = tostring(state.DayKey or todayUtc()),
		EarnedToday = math.max(0, math.floor(getNumber(state.EarnedToday, 0))),
		ProgressSeconds = math.max(0, getNumber(state.ProgressSeconds, 0)),
	})
end

local function getRuntime(player)
	local runtime = runtimeByPlayer[player]
	if runtime == nil then
		runtime = {
			LastTickAt = os.clock(),
			LastPersistAt = 0,
			LastStatePushAt = 0,
			SessionActive = false,
			SessionHadZone = false,
			SessionToken = nil,
			LastUiHeartbeatAt = 0,
			WasInZone = false,
			WasEligible = false,
			WasSessionActive = false,
			NextGrantRetryAt = 0,
		}
		runtimeByPlayer[player] = runtime
	end
	return runtime
end

local function getPlayerRootPart(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end
	return nil
end

local function getShipRuntimeService()
	if shipRuntimeService == nil then
		shipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
	end
	return shipRuntimeService
end

local function getShipAfkRadius()
	return getPositiveNumber(getEntryConfig().ShipAfkRadius, DEFAULT_SHIP_AFK_RADIUS)
end

local function getPlayerShipSpawnCFrame(player)
	local service = getShipRuntimeService()
	if typeof(service.GetPlayerSpawnCFrame) ~= "function" then
		return nil
	end

	local ok, spawnCFrame = pcall(function()
		return service.GetPlayerSpawnCFrame(player)
	end)
	if ok and typeof(spawnCFrame) == "CFrame" then
		return spawnCFrame
	end
	return nil
end

local function isPlayerInShipAfkArea(player)
	local rootPart = getPlayerRootPart(player)
	if not rootPart then
		return false
	end

	local spawnCFrame = getPlayerShipSpawnCFrame(player)
	if typeof(spawnCFrame) ~= "CFrame" then
		return false
	end

	return (rootPart.Position - spawnCFrame.Position).Magnitude <= getShipAfkRadius()
end

local function getInstancePosition(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.Position
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart.Position
		end

		local ok, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if ok and typeof(pivot) == "CFrame" then
			return pivot.Position
		end
	end

	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.Position or nil
end

local function getRayleighNpc()
	local refs = MapResolver.GetRefs({
		context = "AFKGoldChestRewardService",
	})
	return refs.AFKRayleighNpc
end

local function isPlayerNearRayleigh(player)
	local rootPart = getPlayerRootPart(player)
	if not rootPart then
		return false, "Character is not ready."
	end

	local rayleighNpc = getRayleighNpc()
	local rayleighPosition = getInstancePosition(rayleighNpc)
	if typeof(rayleighPosition) ~= "Vector3" then
		return false, "Rayleigh AFK trainer is unavailable."
	end

	local maxDistance = getPositiveNumber(getEntryConfig().MaxDistance, DEFAULT_ENTRY_MAX_DISTANCE)
	if (rootPart.Position - rayleighPosition).Magnitude > maxDistance then
		return false, "Move closer to Rayleigh to start training."
	end

	return true, nil
end

local function getProfileDataRoot(player)
	if dataManagerRef == nil or typeof(dataManagerRef.TryGetProfile) ~= "function" then
		return nil
	end

	local profile = dataManagerRef:TryGetProfile(player)
	return if profile and typeof(profile.Data) == "table" then profile.Data else nil
end

local function getGoldChestCount(dataRoot)
	if typeof(dataRoot) ~= "table" then
		return 0
	end

	local unopenedChests = dataRoot.UnopenedChests
	if typeof(unopenedChests) ~= "table" then
		return 0
	end

	local count = 0
	local stacks = unopenedChests.Stacks
	if typeof(stacks) == "table" then
		count += math.max(0, math.floor(tonumber(stacks.Gold) or 0))
	end

	local byId = unopenedChests.ById
	if typeof(byId) == "table" then
		for _, chestData in pairs(byId) do
			if typeof(chestData) == "table" and tostring(chestData.Tier or "") == "Gold" then
				count += math.max(1, math.floor(tonumber(chestData.Quantity) or 1))
			end
		end
	end

	return count
end

local function getBeliAmount(player, dataRoot)
	local valueObject = CurrencyUtil.findPrimaryValueObject(player)
	if valueObject then
		return math.max(0, tonumber(valueObject.Value) or 0)
	end

	if typeof(dataRoot) ~= "table" then
		return 0
	end

	return CurrencyUtil.getAmountFromTable(dataRoot.leaderstats)
end

local function getGoldFruitPityProgress(dataRoot)
	local chestRewardsState = if typeof(dataRoot) == "table" then dataRoot.ChestRewards else nil
	return ChestRewards.GetFruitPityProgress(chestRewardsState, "Gold")
end

local function buildStatePayload(player, state, inZone, sessionActive)
	local settings = getPlayerSettings(player)
	local dataRoot = getProfileDataRoot(player)
	local runtime = runtimeByPlayer[player]
	local earnedToday = math.max(0, math.floor(getNumber(state and state.EarnedToday, 0)))
	local progressSeconds = math.max(0, getNumber(state and state.ProgressSeconds, 0))
	local capReached = earnedToday >= settings.DailyCap
	local secondsUntilNext = if capReached
		then 0
		else math.max(0, math.ceil(settings.IntervalSeconds - math.min(progressSeconds, settings.IntervalSeconds)))

	return {
		InZone = inZone == true,
		SessionActive = sessionActive == true,
		Eligible = sessionActive == true and inZone == true,
		IsPremium = settings.IsPremium == true,
		SecondsUntilNext = secondsUntilNext,
		IntervalSeconds = settings.IntervalSeconds,
		EarnedToday = earnedToday,
		DailyCap = settings.DailyCap,
		CapReached = capReached,
		ProgressSeconds = progressSeconds,
		RewardTier = settings.RewardTier,
		SessionToken = if sessionActive == true and runtime ~= nil then runtime.SessionToken else nil,
		UiHeartbeatIntervalSeconds = UI_HEARTBEAT_INTERVAL_SECONDS,
		UiHeartbeatTimeoutSeconds = UI_HEARTBEAT_TIMEOUT_SECONDS,
		UiHeartbeatRequired = true,
		ServerTime = workspace:GetServerTimeNow(),
		ShipAfkRadius = getShipAfkRadius(),
		GoldChestCount = getGoldChestCount(dataRoot),
		FruitPityProgress = getGoldFruitPityProgress(dataRoot),
		Beli = getBeliAmount(player, dataRoot),
	}
end

local function fireState(player, state, inZone)
	if stateEvent == nil or player.Parent ~= Players then
		return
	end
	local runtime = runtimeByPlayer[player]
	local sessionActive = runtime and runtime.SessionActive == true
	stateEvent:FireClient(player, "State", buildStatePayload(player, state, inZone, sessionActive))
end

local function getChestGrantService()
	if verticalSliceService == nil then
		verticalSliceService = require(ServerScriptService.Modules:WaitForChild("GrandLineRushVerticalSliceService"))
	end
	return verticalSliceService
end

local function grantGoldChest(player, settings)
	local service = getChestGrantService()
	local ok, response = pcall(function()
		return service.GrantChest(player, settings.RewardTier, 1, nil, {
			Source = settings.Source,
		})
	end)
	if ok ~= true then
		warn(string.format(
			"[AFKGoldChestRewardService] Gold chest grant errored player=%s error=%s",
			player and player.Name or "<unknown>",
			tostring(response)
		))
		return false
	end

	if typeof(response) ~= "table" or response.ok ~= true then
		warn(string.format(
			"[AFKGoldChestRewardService] Gold chest grant failed player=%s reason=%s",
			player and player.Name or "<unknown>",
			tostring(response and response.error or "unknown")
		))
		return false
	end

	return true
end

local function fireReward(player, settings, state, inZone)
	if stateEvent == nil or player.Parent ~= Players then
		return
	end

	stateEvent:FireClient(player, "Reward", {
		IsPremium = settings.IsPremium == true,
		Amount = 1,
		RewardTier = settings.RewardTier,
		Message = if settings.IsPremium
			then "Premium AFK Reward: +1 Gold Chest"
			else "AFK Reward: +1 Gold Chest",
		State = buildStatePayload(player, state, inZone, true),
	})
end

local endSession
local isPlayerAlive

local function processCompletedIntervals(player, state, runtime, inZone, now)
	local settings = getPlayerSettings(player)
	if math.max(0, math.floor(getNumber(state.EarnedToday, 0))) >= settings.DailyCap then
		if getNumber(state.ProgressSeconds, 0) ~= 0 then
			state.ProgressSeconds = 0
			persistAfkState(player, state)
		end
		return
	end

	if runtime.NextGrantRetryAt and now < runtime.NextGrantRetryAt then
		return
	end

	local grantedAny = false
	if getNumber(state.ProgressSeconds, 0) >= settings.IntervalSeconds then
		if grantGoldChest(player, settings) ~= true then
			runtime.NextGrantRetryAt = now + GRANT_RETRY_SECONDS
			return
		end

		state.ProgressSeconds = 0
		state.EarnedToday = math.max(0, math.floor(getNumber(state.EarnedToday, 0))) + 1
		grantedAny = true
		persistAfkState(player, state)
		fireReward(player, settings, state, inZone)
	end

	if grantedAny then
		runtime.NextGrantRetryAt = 0
	end
end

local function processPlayer(player, now)
	local config = getAfkConfig()
	if config.Enabled == false then
		return
	end
	if dataManagerRef == nil or dataManagerRef:IsReady(player) ~= true then
		return
	end

	local runtime = getRuntime(player)
	local state, reason = getAfkState(player)
	if state == nil then
		if reason ~= "profile_not_ready" then
			warn(string.format(
				"[AFKGoldChestRewardService] Missing AFK state player=%s reason=%s",
				player and player.Name or "<unknown>",
				tostring(reason)
			))
		end
		return
	end

	local inZone = isPlayerInShipAfkArea(player)
	local delta = math.clamp(now - (runtime.LastTickAt or now), 0, MAX_DELTA_SECONDS)
	runtime.LastTickAt = now
	local sessionActive = runtime.SessionActive == true

	if sessionActive and isPlayerAlive(player) ~= true then
		endSession(player, state, {
			Reason = "character_unavailable",
		})
		sessionActive = false
		inZone = false
		fireState(player, state, inZone)
		runtime.LastStatePushAt = now
	end

	if sessionActive and inZone then
		runtime.SessionHadZone = true
	end

	if sessionActive and runtime.SessionHadZone == true and not inZone then
		endSession(player, state, {
			Reason = "left_ship_afk_radius",
			TeleportToShip = true,
			TeleportOnlyIfOutside = true,
			TeleportContext = "rayleigh_training_radius_exit",
		})
		sessionActive = false
		inZone = isPlayerInShipAfkArea(player)
		fireState(player, state, inZone)
		runtime.LastStatePushAt = now
	end

	local heartbeatFresh = sessionActive
		and runtime.SessionToken ~= nil
		and now - getNumber(runtime.LastUiHeartbeatAt, 0) <= UI_HEARTBEAT_TIMEOUT_SECONDS

	if sessionActive and inZone and heartbeatFresh ~= true then
		endSession(player, state, {
			Reason = "ui_heartbeat_expired",
			TeleportToShip = true,
			TeleportContext = "rayleigh_training_heartbeat_exit",
		})
		sessionActive = false
		inZone = isPlayerInShipAfkArea(player)
		fireState(player, state, inZone)
		runtime.LastStatePushAt = now
	end

	local eligible = sessionActive and inZone and heartbeatFresh

	if eligible then
		local settings = getPlayerSettings(player)
		if math.max(0, math.floor(getNumber(state.EarnedToday, 0))) < settings.DailyCap then
			state.ProgressSeconds = math.max(0, getNumber(state.ProgressSeconds, 0)) + delta
		else
			state.ProgressSeconds = 0
		end
		processCompletedIntervals(player, state, runtime, inZone, now)
	elseif runtime.WasEligible == true then
		persistAfkState(player, state)
	end

	if sessionActive or runtime.WasSessionActive ~= sessionActive or runtime.WasInZone ~= inZone then
		if
			now - (runtime.LastStatePushAt or 0) >= 1
			or runtime.WasSessionActive ~= sessionActive
			or runtime.WasInZone ~= inZone
		then
			fireState(player, state, inZone)
			runtime.LastStatePushAt = now
		end
	end

	if eligible and now - (runtime.LastPersistAt or 0) >= PERSIST_INTERVAL_SECONDS then
		persistAfkState(player, state)
		runtime.LastPersistAt = now
	end

	runtime.WasInZone = inZone
	runtime.WasEligible = eligible
	runtime.WasSessionActive = sessionActive
end

local function buildCurrentStateForPlayer(player)
	if dataManagerRef == nil or dataManagerRef:IsReady(player) ~= true then
		return {
			InZone = false,
			SessionActive = false,
			Eligible = false,
			IsPremium = player.MembershipType == Enum.MembershipType.Premium,
			SecondsUntilNext = 0,
			IntervalSeconds = DEFAULT_NORMAL_INTERVAL_SECONDS,
			EarnedToday = 0,
			DailyCap = DEFAULT_NORMAL_DAILY_CAP,
			CapReached = false,
			ShipAfkRadius = getShipAfkRadius(),
			SessionToken = nil,
			UiHeartbeatIntervalSeconds = UI_HEARTBEAT_INTERVAL_SECONDS,
			UiHeartbeatTimeoutSeconds = UI_HEARTBEAT_TIMEOUT_SECONDS,
			UiHeartbeatRequired = true,
			GoldChestCount = 0,
			FruitPityProgress = ChestRewards.GetFruitPityProgress(nil, "Gold"),
			Beli = 0,
			DataReady = false,
		}
	end

	local state = getAfkState(player)
	local inZone = isPlayerInShipAfkArea(player)
	local runtime = getRuntime(player)
	local payload = buildStatePayload(player, state, inZone, runtime.SessionActive == true)
	payload.DataReady = true
	return payload
end

local function buildEntryResponse(ok, message, state)
	return {
		ok = ok == true,
		message = tostring(message or ""),
		State = state,
	}
end

local function teleportPlayerToShip(player, context)
	local service = getShipRuntimeService()
	if typeof(service.TeleportPlayerToShip) ~= "function" then
		return false, "ship_service_unavailable"
	end

	local ok, success, reason = pcall(function()
		return service.TeleportPlayerToShip(player, nil, context or "rayleigh_training_ship")
	end)
	if ok ~= true then
		return false, "ship_teleport_error"
	end
	if success ~= true then
		return false, reason or "ship_teleport_failed"
	end
	return true, nil
end

function isPlayerAlive(player)
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	return character:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getReturnCFrame()
	local refs = MapResolver.GetRefs({
		context = "AFKGoldChestRewardService.Exit",
	})
	local spawnPart = refs and refs.SpawnPart
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame + EXIT_TELEPORT_OFFSET
	end

	local rayleighNpc = refs and refs.AFKRayleighNpc
	local rayleighPosition = getInstancePosition(rayleighNpc)
	if typeof(rayleighPosition) == "Vector3" then
		return CFrame.new(rayleighPosition + RAYLEIGH_EXIT_OFFSET + EXIT_TELEPORT_OFFSET)
	end

	return CFrame.new(EXIT_TELEPORT_OFFSET)
end

local function teleportPlayerToReturnPoint(player)
	local character = player.Character
	if not character then
		return false, "missing_character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health <= 0 then
		return false, "dead"
	end

	character:PivotTo(getReturnCFrame())
	return true, nil
end

function endSession(player, state, options)
	options = if typeof(options) == "table" then options else {}
	local runtime = getRuntime(player)
	local now = os.clock()
	runtime.SessionActive = false
	runtime.SessionHadZone = false
	runtime.SessionToken = nil
	runtime.LastUiHeartbeatAt = 0
	runtime.WasInZone = false
	runtime.WasEligible = false
	runtime.WasSessionActive = false
	runtime.NextGrantRetryAt = 0
	runtime.LastTickAt = now
	runtime.LastStatePushAt = now

	if typeof(state) == "table" then
		state.ProgressSeconds = 0
		persistAfkState(player, state)
	end

	local teleportAttempted = false
	local teleported = false
	local teleportReason = nil
	if options.TeleportToShip == true and player.Parent == Players and isPlayerAlive(player) then
		if options.TeleportOnlyIfOutside ~= true or isPlayerInShipAfkArea(player) ~= true then
			teleportAttempted = true
			teleported, teleportReason = teleportPlayerToShip(player, tostring(options.TeleportContext or "rayleigh_training_exit"))
		else
			teleported = true
		end
	end

	return {
		TeleportAttempted = teleportAttempted,
		Teleported = teleported,
		TeleportReason = teleportReason,
	}
end

local function handleEntryRequest(player)
	local config = getAfkConfig()
	if config.Enabled == false then
		return buildEntryResponse(false, "Rayleigh Training rewards are currently unavailable.", buildCurrentStateForPlayer(player))
	end

	if dataManagerRef == nil or dataManagerRef:IsReady(player) ~= true then
		return buildEntryResponse(false, "Your profile is still loading. Try again in a moment.", buildCurrentStateForPlayer(player))
	end

	local now = os.clock()
	local nearRayleigh, reason = isPlayerNearRayleigh(player)
	if nearRayleigh ~= true then
		return buildEntryResponse(false, reason or "Move closer to Rayleigh to start training.", buildCurrentStateForPlayer(player))
	end

	local state, stateReason = getAfkState(player)
	if state == nil then
		return buildEntryResponse(false, tostring(stateReason or "Rayleigh Training progress is unavailable."), buildCurrentStateForPlayer(player))
	end

	if getNumber(state.ProgressSeconds, 0) ~= 0 then
		state.ProgressSeconds = 0
		persistAfkState(player, state)
	end

	local teleported, teleportReason = teleportPlayerToShip(player, "rayleigh_training_entry")
	if teleported ~= true then
		local message = "Your ship is not ready for Rayleigh Training. Try again in a moment."
		if teleportReason == "active_ship_not_found" or teleportReason == "spawn_cframe_not_found" then
			message = "Your active ship is not ready for Rayleigh Training. Try again in a moment."
		end
		return buildEntryResponse(false, message, buildCurrentStateForPlayer(player))
	end

	local runtime = getRuntime(player)
	local inZone = isPlayerInShipAfkArea(player)
	if inZone ~= true then
		endSession(player, state, {
			Reason = "entry_ship_area_unavailable",
		})
		return buildEntryResponse(false, "The training ship area is unavailable. Try again in a moment.", buildCurrentStateForPlayer(player))
	end

	runtime.SessionActive = true
	runtime.SessionHadZone = true
	runtime.SessionToken = HttpService:GenerateGUID(false)
	runtime.LastUiHeartbeatAt = now
	runtime.LastTickAt = now
	runtime.LastStatePushAt = now
	runtime.NextGrantRetryAt = 0
	runtime.WasInZone = inZone
	runtime.WasEligible = inZone
	runtime.WasSessionActive = true

	local payload = buildStatePayload(player, state, inZone, true)
	payload.DataReady = true
	fireState(player, state, inZone)

	local message = "Rayleigh Training started."
	return buildEntryResponse(true, message, payload)
end

local function handleExitRequest(player)
	if dataManagerRef == nil or dataManagerRef:IsReady(player) ~= true then
		return buildEntryResponse(false, "Your profile is still loading. Try again in a moment.", buildCurrentStateForPlayer(player))
	end

	local state = getAfkState(player)
	local result = endSession(player, state, {
		Reason = "explicit_exit",
		TeleportToShip = true,
		TeleportContext = "rayleigh_training_exit",
	})
	local teleported = result.Teleported == true
	local teleportReason = result.TeleportReason
	local usedFallback = false
	if teleported ~= true then
		usedFallback = true
		teleported, teleportReason = teleportPlayerToReturnPoint(player)
	end

	local inZone = isPlayerInShipAfkArea(player)
	local payload = buildStatePayload(player, state, inZone, false)
	payload.DataReady = true
	fireState(player, state, inZone)

	if teleported ~= true then
		return buildEntryResponse(false, tostring(teleportReason or "Unable to leave Rayleigh Training right now."), payload)
	end
	if usedFallback then
		return buildEntryResponse(true, "Left Rayleigh Training. Your ship was unavailable, so you were moved to a safe point.", payload)
	end
	return buildEntryResponse(true, "Left Rayleigh Training.", payload)
end

local function handleUiHeartbeat(player, sessionToken)
	if typeof(sessionToken) ~= "string" or sessionToken == "" then
		return
	end

	local runtime = runtimeByPlayer[player]
	if runtime == nil or runtime.SessionActive ~= true then
		return
	end
	if runtime.SessionToken ~= sessionToken then
		return
	end

	runtime.LastUiHeartbeatAt = os.clock()
end

local function runLoop()
	task.spawn(function()
		while started do
			local now = os.clock()
			for _, player in ipairs(Players:GetPlayers()) do
				processPlayer(player, now)
			end
			task.wait(TICK_SECONDS)
		end
	end)
end

function AFKGoldChestRewardService.Start(dataManager)
	if started then
		return
	end

	started = true
	dataManagerRef = dataManager
	getOrCreateRemotes()

	stateRequest.OnServerInvoke = function(player)
		return buildCurrentStateForPlayer(player)
	end

	entryRequest.OnServerInvoke = function(player)
		return handleEntryRequest(player)
	end

	exitRequest.OnServerInvoke = function(player)
		return handleExitRequest(player)
	end

	uiHeartbeatEvent.OnServerEvent:Connect(function(player, sessionToken)
		handleUiHeartbeat(player, sessionToken)
	end)

	Players.PlayerRemoving:Connect(function(player)
		if dataManagerRef ~= nil and dataManagerRef:IsReady(player) == true then
			local state = getAfkState(player)
			if state then
				endSession(player, state, {
					Reason = "player_removing",
				})
			end
		end
		runtimeByPlayer[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		getRuntime(player)
	end
	Players.PlayerAdded:Connect(function(player)
		getRuntime(player)
	end)

	runLoop()
end

return AFKGoldChestRewardService
