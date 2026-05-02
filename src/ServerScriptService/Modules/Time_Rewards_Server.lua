local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeRewardsFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeRewards")

local GIFT_DEBUG = false
local GIFT_SYNC_DEBUG = false
local GIFT_CLAIM_DEBUG = true
local AUTHORITATIVE_TIME_REWARD_REMOTE_ATTRIBUTE = "TimeRewardsAuthoritativeRemote"

local function giftLog(tag: string, ...)
	if GIFT_DEBUG then
		print(tag, ...)
	end
end

local function giftClaimLog(...)
	if GIFT_CLAIM_DEBUG then
		print("[GIFT][CLAIM][SERVER]", ...)
	end
end

local function giftSyncLog(...)
	if GIFT_SYNC_DEBUG then
		print("[GIFT][SYNC]", ...)
	end
end

local function giftError(...)
	warn("[GIFT][ERROR]", ...)
end

local function describeInstance(instance: Instance?): string
	if not instance then
		return "nil"
	end

	return instance:GetFullName() .. " [" .. instance.ClassName .. "]"
end

local function getNamedDescendantSummary(root: Instance, childName: string): (number, string)
	local count = 0
	local paths = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == childName then
			count += 1
			table.insert(paths, describeInstance(descendant))
		end
	end

	return count, table.concat(paths, " | ")
end

local function getOrCreateChild(parent: Instance, className: string, childName: string)
	local child = parent:FindFirstChild(childName)
	if child then
		if child:IsA(className) then
			return child
		end
		child:Destroy()
	end

	child = Instance.new(className)
	child.Name = childName
	child.Parent = parent
	return child
end

local function getAuthoritativeTimeRewardRemote(parent: Instance): RemoteEvent
	local namedChildren = {}
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "TimeRewardEvent" then
			table.insert(namedChildren, child)
		end
	end

	local authoritativeRemote = nil
	for _, child in ipairs(namedChildren) do
		if child:IsA("RemoteEvent") and child:GetAttribute(AUTHORITATIVE_TIME_REWARD_REMOTE_ATTRIBUTE) == true then
			authoritativeRemote = child
			break
		end
	end

	if not authoritativeRemote then
		for _, child in ipairs(namedChildren) do
			if child:IsA("RemoteEvent") then
				authoritativeRemote = child
				break
			end
		end
	end

	if not authoritativeRemote then
		authoritativeRemote = Instance.new("RemoteEvent")
		authoritativeRemote.Name = "TimeRewardEvent"
		authoritativeRemote.Parent = parent
		giftClaimLog("authoritativeRemoteCreated", "remote", describeInstance(authoritativeRemote))
	end

	authoritativeRemote:SetAttribute(AUTHORITATIVE_TIME_REWARD_REMOTE_ATTRIBUTE, true)

	local removedCount = 0
	for _, child in ipairs(namedChildren) do
		if child ~= authoritativeRemote then
			removedCount += 1
			giftClaimLog(
				"duplicateRemoteRemoved",
				"kept",
				describeInstance(authoritativeRemote),
				"removed",
				describeInstance(child)
			)
			child:Destroy()
		end
	end

	local countAfterCleanup, pathsAfterCleanup = getNamedDescendantSummary(ReplicatedStorage, "TimeRewardEvent")
	giftClaimLog(
		"authoritativeRemoteSelected",
		"kept",
		describeInstance(authoritativeRemote),
		"initialTimeRewardEventCount",
		#namedChildren,
		"removedCount",
		removedCount,
		"timeRewardEventCountAfterCleanup",
		countAfterCleanup,
		"timeRewardEventPathsAfterCleanup",
		pathsAfterCleanup
	)

	return authoritativeRemote
end

local Remote = getAuthoritativeTimeRewardRemote(TimeRewardsFolder)
local SnapshotRequest = getOrCreateChild(TimeRewardsFolder, "RemoteFunction", "TimeRewardSnapshotRequest")
local InstantRewardsEvent = getOrCreateChild(TimeRewardsFolder, "BindableEvent", "TriggerInstantRewards")
local RewardsConfig = require(TimeRewardsFolder:WaitForChild("Config"))
local DataManager = require(script.Parent.Parent.Data.DataManager)
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local TIME_REWARDS_ROOT_PATH = "TimeRewards"
local CYCLE_START_PATH = TIME_REWARDS_ROOT_PATH .. ".CycleStartPlayTime"
local CLAIMED_REWARDS_PATH = TIME_REWARDS_ROOT_PATH .. ".ClaimedRewards"
local LAST_CLAIM_PATH = TIME_REWARDS_ROOT_PATH .. ".LastClaimPlayTime"
local TOTAL_PLAY_TIME_PATH = "TotalStats.TimePlayed"

local CLAIM_REQUEST_THROTTLE = 0.25
local DATA_READY_TIMEOUT = 30

local claimLocks = {}
local lastClaimRequestAt = {}
local playTimeSessions = {}
local rewardIds = {}
local BrainrotModule = nil

local POTION_REWARD_KEYS = {
	x2Money = true,
	x2MoneyTime = true,
	x15WalkSpeed = true,
	x15WalkSpeedTime = true,
}

for id in pairs(RewardsConfig) do
	table.insert(rewardIds, id)
end

table.sort(rewardIds)

local TOTAL_REWARDS = #rewardIds

local timeRewardEventCount, timeRewardEventPaths = getNamedDescendantSummary(ReplicatedStorage, "TimeRewardEvent")

giftClaimLog(
	"serverModuleInit",
	"module",
	script:GetFullName(),
	"timeRewardsFolder",
	TimeRewardsFolder:GetFullName(),
	"remote",
	Remote:GetFullName(),
	"remoteClass",
	Remote.ClassName,
	"snapshot",
	SnapshotRequest:GetFullName(),
	"snapshotClass",
	SnapshotRequest.ClassName,
	"instant",
	InstantRewardsEvent:GetFullName(),
	"instantClass",
	InstantRewardsEvent.ClassName,
	"timeRewardEventCount",
	timeRewardEventCount,
	"timeRewardEventPaths",
	timeRewardEventPaths
)

local function getClaimedCountFromMap(rawClaimedRewards): number
	local count = 0
	if typeof(rawClaimedRewards) ~= "table" then
		return count
	end

	for _, claimed in pairs(rawClaimedRewards) do
		if claimed == true then
			count += 1
		end
	end

	return count
end

local function waitForDataReady(player: Player, timeoutSeconds: number): boolean
	if DataManager:IsReady(player) then
		return true
	end

	local deadline = os.clock() + timeoutSeconds
	while player.Parent == Players and os.clock() < deadline do
		if DataManager:IsReady(player) then
			return true
		end
		task.wait(0.1)
	end

	return player.Parent == Players and DataManager:IsReady(player)
end

local function waitForPlayerDataReady(player: Player, timeoutSeconds: number): boolean
	local deadline = os.clock() + timeoutSeconds
	while player.Parent == Players and os.clock() < deadline do
		if DataManager:IsReady(player) and player:GetAttribute("PlayerDataReady") == true then
			return true
		end
		task.wait(0.1)
	end

	return player.Parent == Players and DataManager:IsReady(player) and player:GetAttribute("PlayerDataReady") == true
end

local function getCurrentPlayTime(player: Player): (number?, string?)
	local value, reason = DataManager:TryGetValue(player, TOTAL_PLAY_TIME_PATH)
	if reason ~= nil then
		return nil, reason
	end

	local storedPlayTime = math.max(0, math.floor(tonumber(value) or 0))
	local now = os.clock()
	local session = playTimeSessions[player]

	if not session then
		session = {
			BasePlayTime = storedPlayTime,
			StartedAt = now,
		}
		playTimeSessions[player] = session
	end

	local sessionPlayTime = session.BasePlayTime + math.max(0, math.floor(now - session.StartedAt))
	if storedPlayTime > sessionPlayTime then
		session.BasePlayTime = storedPlayTime
		session.StartedAt = now
		sessionPlayTime = storedPlayTime
	end

	return math.max(storedPlayTime, sessionPlayTime), nil
end

local function copyClaimedRewards(rawClaimedRewards): {[string]: boolean}
	local claimedRewards = {}
	if typeof(rawClaimedRewards) ~= "table" then
		return claimedRewards
	end

	for rawKey, rawValue in pairs(rawClaimedRewards) do
		local rewardId = tonumber(rawKey)
		if rewardId and RewardsConfig[rewardId] and rawValue == true then
			claimedRewards[tostring(rewardId)] = true
		end
	end

	return claimedRewards
end

local function hasNormalizedClaimedMismatch(rawClaimedRewards, normalizedClaimedRewards): boolean
	if typeof(rawClaimedRewards) ~= "table" then
		return true
	end

	local rawCount = 0
	local normalizedCount = 0

	for rawKey, rawValue in pairs(rawClaimedRewards) do
		rawCount += 1

		local rewardId = tonumber(rawKey)
		if typeof(rawKey) ~= "string" then
			return true
		end
		if not rewardId or not RewardsConfig[rewardId] or rawValue ~= true then
			return true
		end
		if normalizedClaimedRewards[tostring(rewardId)] ~= true then
			return true
		end
	end

	for _ in pairs(normalizedClaimedRewards) do
		normalizedCount += 1
	end

	return rawCount ~= normalizedCount
end

local function persistTimeRewardState(player: Player, state): (boolean, string?)
	local ok, reason = DataManager:TrySetValue(player, TIME_REWARDS_ROOT_PATH, {
		CycleStartPlayTime = state.CycleStartPlayTime,
		ClaimedRewards = copyClaimedRewards(state.ClaimedRewards),
		LastClaimPlayTime = state.LastClaimPlayTime,
	})
	if not ok then
		return false, reason or "persist_failed"
	end

	return true, nil
end

local function ensureTimeRewardState(player: Player)
	if not DataManager:IsReady(player) then
		return nil, nil, "not_ready"
	end

	local currentPlayTime, playTimeReason = getCurrentPlayTime(player)
	if currentPlayTime == nil then
		return nil, nil, playTimeReason or "missing_play_time"
	end

	local cycleStartPlayTime = DataManager:TryGetValue(player, CYCLE_START_PATH)
	local rawClaimedRewards = DataManager:TryGetValue(player, CLAIMED_REWARDS_PATH)
	local lastClaimPlayTime = DataManager:TryGetValue(player, LAST_CLAIM_PATH)

	local stateChanged = false
	local normalizedClaimedRewards = copyClaimedRewards(rawClaimedRewards)

	if typeof(cycleStartPlayTime) ~= "number" then
		cycleStartPlayTime = currentPlayTime
		stateChanged = true
	else
		cycleStartPlayTime = math.max(0, math.floor(cycleStartPlayTime))
		if cycleStartPlayTime > currentPlayTime then
			cycleStartPlayTime = currentPlayTime
			stateChanged = true
		end
	end

	if hasNormalizedClaimedMismatch(rawClaimedRewards, normalizedClaimedRewards) then
		stateChanged = true
	end

	if typeof(lastClaimPlayTime) ~= "number" then
		lastClaimPlayTime = cycleStartPlayTime
		stateChanged = true
	else
		lastClaimPlayTime = math.max(0, math.floor(lastClaimPlayTime))
		if lastClaimPlayTime < cycleStartPlayTime then
			lastClaimPlayTime = cycleStartPlayTime
			stateChanged = true
		elseif lastClaimPlayTime > currentPlayTime then
			lastClaimPlayTime = currentPlayTime
			stateChanged = true
		end
	end

	local state = {
		CycleStartPlayTime = cycleStartPlayTime,
		ClaimedRewards = normalizedClaimedRewards,
		LastClaimPlayTime = lastClaimPlayTime,
	}

	if stateChanged then
		local ok, reason = persistTimeRewardState(player, state)
		if not ok then
			return nil, nil, reason or "persist_failed"
		end
	end

	return state, currentPlayTime, nil
end

local function buildClientState(state, currentPlayTime: number)
	return {
		CycleStartPlayTime = state.CycleStartPlayTime,
		CurrentPlayTime = currentPlayTime,
		ClaimedRewards = copyClaimedRewards(state.ClaimedRewards),
	}
end

local function fireClientState(player: Player, state, currentPlayTime: number)
	local clientState = buildClientState(state, currentPlayTime)
	giftLog(
		"[GIFT][DATA]",
		string.format(
			"player=%s action=syncState claimed=%d totalRewards=%d currentPlayTime=%d cycleStart=%d",
			player.Name,
			getClaimedCountFromMap(clientState.ClaimedRewards),
			TOTAL_REWARDS,
			clientState.CurrentPlayTime,
			clientState.CycleStartPlayTime
		)
	)
	Remote:FireClient(player, "syncState", clientState)
end

local function getClaimedCount(state): number
	local count = 0
	for rawKey, rawValue in pairs(state.ClaimedRewards) do
		local rewardId = tonumber(rawKey)
		if rewardId and RewardsConfig[rewardId] and rawValue == true then
			count += 1
		end
	end
	return count
end

local function isRewardClaimed(state, rewardId: number): boolean
	return state.ClaimedRewards[tostring(rewardId)] == true
end

local function markRewardClaimed(state, rewardId: number)
	state.ClaimedRewards[tostring(rewardId)] = true
end

local function resetCycleState(state, currentPlayTime: number)
	state.CycleStartPlayTime = currentPlayTime
	state.ClaimedRewards = {}
	state.LastClaimPlayTime = currentPlayTime
end

local function getElapsedPlayTime(state, currentPlayTime: number): number
	return math.max(0, currentPlayTime - state.CycleStartPlayTime)
end

local function rollReward(tbl)
	local roll = math.random(1, 100)
	local sum = 0
	for name, data in pairs(tbl) do
		sum += data.Chance
		if roll <= sum then
			return name, data.Amount, data
		end
	end
end

local function tryAddPotionReward(player: Player, rewardName: string, amount: number): (boolean?, string?)
	local potionName = rewardName
	local prefix = "Potions."
	if string.sub(potionName, 1, #prefix) == prefix then
		potionName = string.sub(potionName, #prefix + 1)
	end

	if POTION_REWARD_KEYS[potionName] ~= true then
		return nil, nil
	end

	local ok, reason = DataManager:TryAddValue(player, prefix .. potionName, amount)
	if ok and string.sub(potionName, -4) == "Time" and typeof(DataManager.ResumeBoost) == "function" then
		local boostName = string.sub(potionName, 1, #potionName - 4)
		DataManager:ResumeBoost(player, boostName)
	end

	return ok, reason
end

local function addReward(player: Player, rewardName: string, amount: number)
	local normalizedRewardName = tostring(rewardName)
	if normalizedRewardName == "Money" or normalizedRewardName == "Doubloons" then
		return DataManager:TryAddValue(player, CurrencyUtil.getPrimaryPath(), amount)
	end

	local potionOk, potionReason = tryAddPotionReward(player, normalizedRewardName, amount)
	if potionOk ~= nil then
		return potionOk, potionReason
	end

	local inventory = player:FindFirstChild("Inventory")
	local feed = inventory and inventory:FindFirstChild("Feed")
	local stat = feed and feed:FindFirstChild(normalizedRewardName)
	if stat then
		return DataManager:TryAddValue(player, "Inventory.Feed." .. normalizedRewardName, amount)
	end

	for _, folder in ipairs(player:GetChildren()) do
		if folder:IsA("Folder") then
			local statObj = folder:FindFirstChild(normalizedRewardName)
			if statObj then
				return DataManager:TryAddValue(player, folder.Name .. "." .. normalizedRewardName, amount)
			end
		end
	end

	return DataManager:TryAddValue(player, normalizedRewardName, amount)
end

local function grantReward(player: Player, rewardId: number)
	local config = RewardsConfig[rewardId]
	if not config then
		return false, nil, nil, "invalid_reward"
	end

	local rewardName, amount, rewardData = rollReward(config.Rewards)
	if not rewardName then
		return false, nil, nil, "no_reward_roll"
	end

	local ok, reason
	if rewardData and rewardData.Brainrot == true then
		BrainrotModule = BrainrotModule or require(script.Parent.AddBrainrot)
		ok = BrainrotModule:AddBrainrot(player, rewardName, amount)
		reason = if ok then nil else "brainrot_grant_failed"
	else
		ok, reason = addReward(player, rewardName, amount)
	end

	if not ok then
		return false, nil, nil, reason or "grant_failed"
	end

	return true, rewardName, amount, nil
end

local function safeGrantReward(player: Player, rewardId: number)
	local ok, rewardGranted, rewardName, amount, reason = pcall(grantReward, player, rewardId)
	if not ok then
		giftError("Unhandled time reward grant error", player.Name, rewardId, rewardGranted)
		return false, nil, nil, "grant_exception"
	end

	return rewardGranted, rewardName, amount, reason
end

local function saveProfileNow(player: Player)
	local profile = DataManager:GetProfile(player)
	if not profile or profile:IsActive() ~= true then
		return
	end

	pcall(function()
		profile:Save()
	end)
end

local function syncPlayerState(player: Player, source: string?)
	if not waitForDataReady(player, DATA_READY_TIMEOUT) then
		giftError("Timed out waiting for time rewards data for", player.Name)
		return false
	end

	local state, currentPlayTime, reason = ensureTimeRewardState(player)
	if not state then
		giftError("Failed to build time rewards state for", player.Name, reason or "unknown_reason")
		return false
	end

	fireClientState(player, state, currentPlayTime)
	giftSyncLog(
		"replay",
		"player",
		player.Name,
		"source",
		tostring(source or "server"),
		"claimed",
		getClaimedCountFromMap(state.ClaimedRewards),
		"currentPlayTime",
		currentPlayTime,
		"cycleStart",
		state.CycleStartPlayTime
	)
	return true
end

local function requestSyncState(player: Player, source: string?)
	giftSyncLog("request", "player", player.Name, "source", tostring(source or "client"))
	task.spawn(syncPlayerState, player, "client_request:" .. tostring(source or "unknown"))
end

local function buildSnapshotResponse(player: Player)
	if not waitForPlayerDataReady(player, DATA_READY_TIMEOUT) then
		return {
			ok = false,
			error = "data_not_ready",
		}
	end

	local state, currentPlayTime, reason = ensureTimeRewardState(player)
	if not state then
		return {
			ok = false,
			error = reason or "missing_state",
		}
	end

	return {
		ok = true,
		state = buildClientState(state, currentPlayTime),
	}
end

local function canProcessClaimRequest(player: Player): (boolean, string?)
	if claimLocks[player] then
		return false, "claim_locked"
	end

	local now = os.clock()
	local previousRequestAt = lastClaimRequestAt[player]
	if previousRequestAt and (now - previousRequestAt) < CLAIM_REQUEST_THROTTLE then
		return false, "claim_throttled"
	end

	lastClaimRequestAt[player] = now
	return true, nil
end

local function claimReward(player: Player, rewardId: number)
	giftClaimLog(
		"claimRequestReceived",
		"player",
		player.Name,
		"rewardId",
		rewardId,
		"dataReady",
		tostring(DataManager:IsReady(player)),
		"playerDataReady",
		tostring(player:GetAttribute("PlayerDataReady") == true)
	)

	local canProcess, processReason = canProcessClaimRequest(player)
	if not canProcess then
		giftClaimLog("claimRejected", "player", player.Name, "rewardId", rewardId, "reason", processReason or "cannot_process")
		return
	end

	if not waitForDataReady(player, DATA_READY_TIMEOUT) then
		giftError("Timed out waiting for time rewards data during claim for", player.Name, rewardId)
		giftClaimLog("claimRejected", "player", player.Name, "rewardId", rewardId, "reason", "data_timeout")
		return
	end

	local config = RewardsConfig[rewardId]
	if not config then
		giftClaimLog("claimRejected", "player", player.Name, "rewardId", rewardId, "reason", "invalid_reward")
		return
	end

	local state, currentPlayTime, stateReason = ensureTimeRewardState(player)
	if not state then
		giftError("Missing time rewards state during claim for", player.Name, rewardId)
		giftClaimLog(
			"claimRejected",
			"player",
			player.Name,
			"rewardId",
			rewardId,
			"reason",
			stateReason or "missing_state"
		)
		return
	end

	if isRewardClaimed(state, rewardId) then
		giftLog("[GIFT][DATA]", "player", player.Name, "action=alreadyClaimed", "rewardId", rewardId)
		giftClaimLog("claimRejected", "player", player.Name, "rewardId", rewardId, "reason", "already_claimed")
		Remote:FireClient(player, "alreadyClaimed", rewardId)
		return
	end

	local elapsedPlayTime = getElapsedPlayTime(state, currentPlayTime)
	if elapsedPlayTime < config.Time then
		local remaining = config.Time - elapsedPlayTime
		giftLog(
			"[GIFT][DATA]",
			"player",
			player.Name,
			"action=notReady",
			"rewardId",
			rewardId,
			"remaining",
			remaining
		)
		giftClaimLog(
			"claimRejected",
			"player",
			player.Name,
			"rewardId",
			rewardId,
			"reason",
			"not_ready",
			"remaining",
			remaining,
			"elapsedPlayTime",
			elapsedPlayTime,
			"requiredTime",
			config.Time
		)
		Remote:FireClient(player, "notReady", rewardId, remaining)
		return
	end

	claimLocks[player] = true

	local previousClaimedRewards = copyClaimedRewards(state.ClaimedRewards)
	local previousLastClaimPlayTime = state.LastClaimPlayTime

	markRewardClaimed(state, rewardId)
	state.LastClaimPlayTime = currentPlayTime

	local persisted, persistReason = persistTimeRewardState(player, state)
	if not persisted then
		state.ClaimedRewards = previousClaimedRewards
		state.LastClaimPlayTime = previousLastClaimPlayTime
		claimLocks[player] = nil
		giftError("Failed to persist claim state", player.Name, rewardId, persistReason)
		giftClaimLog(
			"claimRejected",
			"player",
			player.Name,
			"rewardId",
			rewardId,
			"reason",
			"persist_failed",
			"detail",
			tostring(persistReason)
		)
		return
	end

	local rewardGranted, rewardName, amount, grantReason = safeGrantReward(player, rewardId)
	if not rewardGranted then
		state.ClaimedRewards = previousClaimedRewards
		state.LastClaimPlayTime = previousLastClaimPlayTime
		persistTimeRewardState(player, state)
		claimLocks[player] = nil
		giftError("Failed to grant time reward", player.Name, rewardId, grantReason)
		giftClaimLog(
			"claimRejected",
			"player",
			player.Name,
			"rewardId",
			rewardId,
			"reason",
			"grant_failed",
			"detail",
			tostring(grantReason)
		)
		return
	end

	giftLog(
		"[GIFT][DATA]",
		string.format(
			"player=%s action=claimed rewardId=%d rewardName=%s amount=%s",
			player.Name,
			rewardId,
			tostring(rewardName),
			tostring(amount)
		)
	)
	Remote:FireClient(player, "claimed", rewardId, rewardName, amount)
	giftClaimLog(
		"claimGranted",
		"player",
		player.Name,
		"rewardId",
		rewardId,
		"rewardName",
		tostring(rewardName),
		"amount",
		tostring(amount)
	)

	if getClaimedCount(state) >= TOTAL_REWARDS then
		resetCycleState(state, currentPlayTime)
		local resetPersisted, resetReason = persistTimeRewardState(player, state)
		if not resetPersisted then
			giftError("Failed to persist time rewards cycle reset", player.Name, resetReason)
		end
	end

	fireClientState(player, state, currentPlayTime)
	saveProfileNow(player)

	claimLocks[player] = nil
end

local function instantClaimAll(player: Player)
	if claimLocks[player] then
		return
	end

	if not waitForDataReady(player, DATA_READY_TIMEOUT) then
		return
	end

	local state, currentPlayTime = ensureTimeRewardState(player)
	if not state then
		giftError("Missing time rewards state during instant claim for", player.Name)
		return
	end

	claimLocks[player] = true

	for _, rewardId in ipairs(rewardIds) do
		if not isRewardClaimed(state, rewardId) then
			local rewardGranted, rewardName, amount = safeGrantReward(player, rewardId)
			if rewardGranted then
				markRewardClaimed(state, rewardId)
				state.LastClaimPlayTime = currentPlayTime
				giftLog(
					"[GIFT][DATA]",
					string.format(
						"player=%s action=claimed rewardId=%d rewardName=%s amount=%s source=instant",
						player.Name,
						rewardId,
						tostring(rewardName),
						tostring(amount)
					)
				)
				Remote:FireClient(player, "claimed", rewardId, rewardName, amount)
			end
		end
	end

	if getClaimedCount(state) >= TOTAL_REWARDS then
		resetCycleState(state, currentPlayTime)
	end

	local persisted, reason = persistTimeRewardState(player, state)
	if not persisted then
		giftError("Failed to persist instant reward state", player.Name, reason)
	end

	fireClientState(player, state, currentPlayTime)
	saveProfileNow(player)

	claimLocks[player] = nil
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		syncPlayerState(player, "join")
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		syncPlayerState(player, "existing_player")
	end)
end

Players.PlayerRemoving:Connect(function(player)
	claimLocks[player] = nil
	lastClaimRequestAt[player] = nil
	playTimeSessions[player] = nil
end)

local claimRemoteConnection

claimRemoteConnection = Remote.OnServerEvent:Connect(function(player, rewardId, source)
	local playerName = if player then player.Name else "nil"

	giftClaimLog(
		"rawRemoteReceived",
		"player",
		playerName,
		"arg1",
		tostring(rewardId),
		"arg1Type",
		typeof(rewardId),
		"arg2",
		tostring(source),
		"arg2Type",
		typeof(source),
		"remote",
		Remote:GetFullName()
	)

	giftClaimLog(
		"remoteReceived",
		"player",
		playerName,
		"rewardId",
		tostring(rewardId),
		"rewardIdType",
		typeof(rewardId),
		"source",
		tostring(source),
		"remote",
		Remote:GetFullName()
	)

	if typeof(rewardId) == "string" then
		if rewardId == "requestSync" then
			requestSyncState(player, source)
		else
			giftClaimLog(
				"claimRejected",
				"player",
				player.Name,
				"rewardId",
				tostring(rewardId),
				"reason",
				"string_payload_not_claim"
			)
		end
		return
	end

	rewardId = tonumber(rewardId)
	if not rewardId or rewardId ~= math.floor(rewardId) then
		giftClaimLog(
			"claimRejected",
			"player",
			player.Name,
			"rewardId",
			tostring(rewardId),
			"reason",
			"invalid_payload"
		)
		return
	end

	claimReward(player, rewardId)
end)

giftClaimLog(
	"remoteConnectionMade",
	"module",
	script:GetFullName(),
	"remote",
	Remote:GetFullName(),
	"remoteClass",
	Remote.ClassName,
	"connected",
	tostring(claimRemoteConnection ~= nil)
)

SnapshotRequest.OnServerInvoke = function(player)
	local ok, response = pcall(buildSnapshotResponse, player)
	if ok and typeof(response) == "table" then
		return response
	end

	giftError("Failed to build time rewards snapshot for", player.Name, response)
	return {
		ok = false,
		error = "snapshot_exception",
	}
end

InstantRewardsEvent.Event:Connect(function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	instantClaimAll(player)
end)

local module = {}

function module.ResetClaims(player: Player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	claimLocks[player] = nil
	lastClaimRequestAt[player] = nil

	if not waitForDataReady(player, DATA_READY_TIMEOUT) then
		return false, "not_ready"
	end

	local state, currentPlayTime, reason = ensureTimeRewardState(player)
	if not state then
		return false, reason or "missing_state"
	end

	resetCycleState(state, currentPlayTime)

	local persisted, persistReason = persistTimeRewardState(player, state)
	if not persisted then
		return false, persistReason or "persist_failed"
	end

	fireClientState(player, state, currentPlayTime)
	saveProfileNow(player)

	giftLog(
		"[GIFT][DATA]",
		string.format(
			"player=%s action=adminReset claimed=%d currentPlayTime=%d",
			player.Name,
			getClaimedCount(state),
			currentPlayTime
		)
	)

	return true, nil
end

return module
