local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local AFKGoldChestRewardService = {}

local STATE_PATH = "ChestRewards.AFKGoldChests"
local DEFAULT_STATE_EVENT_NAME = "AFKGoldChestState"
local DEFAULT_STATE_REQUEST_NAME = "AFKGoldChestStateRequest"
local DEFAULT_ENTRY_REQUEST_NAME = "AFKGoldChestEntryRequest"
local DEFAULT_REWARD_TIER = "Gold"
local DEFAULT_SOURCE = "AFK"
local DEFAULT_NORMAL_INTERVAL_SECONDS = 3600
local DEFAULT_PREMIUM_INTERVAL_SECONDS = 1800
local DEFAULT_NORMAL_DAILY_CAP = 8
local DEFAULT_PREMIUM_DAILY_CAP = 16
local DEFAULT_ENTRY_MAX_DISTANCE = 18
local TICK_SECONDS = 1
local MAX_DELTA_SECONDS = 5
local PERSIST_INTERVAL_SECONDS = 30
local ZONE_REFRESH_SECONDS = 10
local GRANT_RETRY_SECONDS = 30
local ZONE_PADDING = 0.5

local started = false
local dataManagerRef = nil
local stateEvent = nil
local stateRequest = nil
local entryRequest = nil
local runtimeByPlayer = {}
local zoneRecord = nil
local nextZoneRefreshAt = 0
local warnedMissingZone = false
local verticalSliceService = nil

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

	stateEvent = existingStateEvent
	stateRequest = existingStateRequest
	entryRequest = existingEntryRequest
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
			WasInZone = false,
			WasEligible = false,
			WasSessionActive = false,
			NextGrantRetryAt = 0,
		}
		runtimeByPlayer[player] = runtime
	end
	return runtime
end

local function getBounds(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	if instance:IsA("Model") then
		local cframe, size = instance:GetBoundingBox()
		return cframe, size
	end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local foundPart = false

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			foundPart = true
			local halfSize = descendant.Size * 0.5
			local position = descendant.Position
			minX = math.min(minX, position.X - halfSize.X)
			minY = math.min(minY, position.Y - halfSize.Y)
			minZ = math.min(minZ, position.Z - halfSize.Z)
			maxX = math.max(maxX, position.X + halfSize.X)
			maxY = math.max(maxY, position.Y + halfSize.Y)
			maxZ = math.max(maxZ, position.Z + halfSize.Z)
		end
	end

	if foundPart ~= true then
		return nil
	end

	local minVector = Vector3.new(minX, minY, minZ)
	local maxVector = Vector3.new(maxX, maxY, maxZ)
	return CFrame.new((minVector + maxVector) * 0.5), maxVector - minVector
end

local function hasZoneName(instance, names)
	local name = instance and instance.Name or ""
	for _, candidate in ipairs(names or {}) do
		if name == tostring(candidate) then
			return true
		end
	end
	return false
end

local function isZoneCandidate(instance)
	if not instance then
		return false
	end

	local config = getAfkConfig()
	local zoneConfig = if typeof(config.Zone) == "table" then config.Zone else {}
	local attributeName = tostring(zoneConfig.Attribute or "AFKGoldChestZone")
	local names = if typeof(zoneConfig.Names) == "table"
		then zoneConfig.Names
		else { "AFKGoldChestZone", "AFKZone", "AFKLobby" }

	return instance:GetAttribute(attributeName) == true or hasZoneName(instance, names)
end

local function buildZoneRecord(instance)
	local cframe, size = getBounds(instance)
	if cframe == nil or size == nil then
		return nil
	end

	return {
		Instance = instance,
		CFrame = cframe,
		Size = size,
	}
end

local function findZone(root)
	if not root then
		return nil
	end

	if isZoneCandidate(root) then
		local record = buildZoneRecord(root)
		if record then
			return record
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isZoneCandidate(descendant) then
			local record = buildZoneRecord(descendant)
			if record then
				return record
			end
		end
	end

	return nil
end

local function findActiveZoneRecord(refs)
	local roots = {}
	if refs and refs.Lobby then
		roots[#roots + 1] = refs.Lobby
	end
	if refs and refs.ActiveMapRoot then
		roots[#roots + 1] = refs.ActiveMapRoot
	end
	if refs and refs.ActiveMapContainer then
		roots[#roots + 1] = refs.ActiveMapContainer
	end
	if refs and refs.MapContainer then
		roots[#roots + 1] = refs.MapContainer
	end
	local seen = {}

	for _, root in ipairs(roots) do
		if root and not seen[root] then
			seen[root] = true
			local found = findZone(root)
			if found then
				return found
			end
		end
	end

	return nil
end

local function getActiveZoneRecord(now)
	now = tonumber(now) or os.clock()
	if zoneRecord ~= nil and zoneRecord.Instance and zoneRecord.Instance.Parent ~= nil and now < nextZoneRefreshAt then
		return zoneRecord
	end

	nextZoneRefreshAt = now + ZONE_REFRESH_SECONDS
	local refs = MapResolver.GetRefs({
		context = "AFKGoldChestRewardService",
	})
	zoneRecord = findActiveZoneRecord(refs)

	if zoneRecord == nil and warnedMissingZone ~= true then
		warn("[AFKGoldChestRewardService] No AFK Gold chest zone found in the active map.")
		warnedMissingZone = true
	elseif zoneRecord ~= nil then
		warnedMissingZone = false
	end

	return zoneRecord
end

local function isPointInsideZone(position, record)
	if typeof(position) ~= "Vector3" or typeof(record) ~= "table" then
		return false
	end

	local cframe = record.CFrame
	local size = record.Size
	if typeof(cframe) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return false
	end

	local localPosition = cframe:PointToObjectSpace(position)
	return math.abs(localPosition.X) <= size.X * 0.5 + ZONE_PADDING
		and math.abs(localPosition.Y) <= size.Y * 0.5 + ZONE_PADDING
		and math.abs(localPosition.Z) <= size.Z * 0.5 + ZONE_PADDING
end

local function isPlayerInZone(player, now)
	local record = getActiveZoneRecord(now)
	if record == nil then
		return false
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not (rootPart and rootPart:IsA("BasePart")) then
		return false
	end

	return isPointInsideZone(rootPart.Position, record)
end

local function getPlayerRootPart(player)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end
	return nil
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
		return false, "Move closer to Rayleigh to enter the AFK World."
	end

	return true, nil
end

local function buildStatePayload(player, state, inZone, sessionActive)
	local settings = getPlayerSettings(player)
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
		ServerTime = workspace:GetServerTimeNow(),
		ZoneAvailable = zoneRecord ~= nil,
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
	while getNumber(state.ProgressSeconds, 0) >= settings.IntervalSeconds
		and math.max(0, math.floor(getNumber(state.EarnedToday, 0))) < settings.DailyCap do
		if grantGoldChest(player, settings) ~= true then
			runtime.NextGrantRetryAt = now + GRANT_RETRY_SECONDS
			break
		end

		state.ProgressSeconds = math.max(0, getNumber(state.ProgressSeconds, 0) - settings.IntervalSeconds)
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

	local inZone = isPlayerInZone(player, now)
	local delta = math.clamp(now - (runtime.LastTickAt or now), 0, MAX_DELTA_SECONDS)
	runtime.LastTickAt = now
	local sessionActive = runtime.SessionActive == true

	if sessionActive and inZone then
		runtime.SessionHadZone = true
	end

	if sessionActive and runtime.SessionHadZone == true and not inZone then
		runtime.SessionActive = false
		runtime.SessionHadZone = false
		sessionActive = false
		persistAfkState(player, state)
	end

	local eligible = sessionActive and inZone

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
			ZoneAvailable = zoneRecord ~= nil,
			DataReady = false,
		}
	end

	local state = getAfkState(player)
	local inZone = isPlayerInZone(player, os.clock())
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

local function handleEntryRequest(player)
	local config = getAfkConfig()
	if config.Enabled == false then
		return buildEntryResponse(false, "AFK Gold Chest rewards are currently unavailable.", buildCurrentStateForPlayer(player))
	end

	if dataManagerRef == nil or dataManagerRef:IsReady(player) ~= true then
		return buildEntryResponse(false, "Your profile is still loading. Try again in a moment.", buildCurrentStateForPlayer(player))
	end

	local now = os.clock()
	if getActiveZoneRecord(now) == nil then
		return buildEntryResponse(false, "The AFK World is not available on this map.", buildCurrentStateForPlayer(player))
	end

	local nearRayleigh, reason = isPlayerNearRayleigh(player)
	if nearRayleigh ~= true then
		return buildEntryResponse(false, reason or "Move closer to Rayleigh to enter the AFK World.", buildCurrentStateForPlayer(player))
	end

	local state, stateReason = getAfkState(player)
	if state == nil then
		return buildEntryResponse(false, tostring(stateReason or "AFK progress is unavailable."), buildCurrentStateForPlayer(player))
	end

	local runtime = getRuntime(player)
	local inZone = isPlayerInZone(player, now)
	runtime.SessionActive = true
	runtime.SessionHadZone = inZone
	runtime.LastTickAt = now
	runtime.LastStatePushAt = now
	runtime.WasInZone = inZone
	runtime.WasEligible = inZone
	runtime.WasSessionActive = true

	local payload = buildStatePayload(player, state, inZone, true)
	payload.DataReady = true
	fireState(player, state, inZone)

	local message = if inZone
		then "AFK training started."
		else "AFK training started. Enter the AFK World to begin earning."
	return buildEntryResponse(true, message, payload)
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

	Players.PlayerRemoving:Connect(function(player)
		if dataManagerRef ~= nil and dataManagerRef:IsReady(player) == true then
			local state = getAfkState(player)
			if state then
				persistAfkState(player, state)
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

	if RunService:IsStudio() then
		task.defer(function()
			getActiveZoneRecord(os.clock())
		end)
	end
end

return AFKGoldChestRewardService
