local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeRewardsFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TimeRewards")
local RewardsConfig = require(TimeRewardsFolder:WaitForChild("Config"))
local DataManager = require(script.Parent.Parent.Data.DataManager)
local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

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

local Remote = getOrCreateChild(TimeRewardsFolder, "RemoteEvent", "TimeRewardEvent")
local InstantRewardsEvent = getOrCreateChild(TimeRewardsFolder, "BindableEvent", "TriggerInstantRewards")

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

local GIFT_DEBUG = false

local function giftLog(tag: string, ...)
	if GIFT_DEBUG then
		print(tag, ...)
	end
end

local function giftError(...)
	warn("[GIFT][ERROR]", ...)
end

for id in pairs(RewardsConfig) do
	table.insert(rewardIds, id)
end

table.sort(rewardIds)

local TOTAL_REWARDS = #rewardIds

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

local function addReward(player: Player, rewardName: string, amount: number)
	local normalizedRewardName = tostring(rewardName)
	if normalizedRewardName == "Money" or normalizedRewardName == "Doubloons" then
		return DataManager:TryAddValue(player, CurrencyUtil.getPrimaryPath(), amount)
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

local function syncPlayerState(player: Player)
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
	return true
end

local function canProcessClaimRequest(player: Player): boolean
	if claimLocks[player] then
		return false
	end

	local now = os.clock()
	local previousRequestAt = lastClaimRequestAt[player]
	if previousRequestAt and (now - previousRequestAt) < CLAIM_REQUEST_THROTTLE then
		return false
	end

	lastClaimRequestAt[player] = now
	return true
end

local function claimReward(player: Player, rewardId: number)
	if not canProcessClaimRequest(player) then
		return
	end

	if not waitForDataReady(player, DATA_READY_TIMEOUT) then
		giftError("Timed out waiting for time rewards data during claim for", player.Name, rewardId)
		return
	end

	local config = RewardsConfig[rewardId]
	if not config then
		return
	end

	local state, currentPlayTime = ensureTimeRewardState(player)
	if not state then
		giftError("Missing time rewards state during claim for", player.Name, rewardId)
		return
	end

	if isRewardClaimed(state, rewardId) then
		giftLog("[GIFT][DATA]", "player", player.Name, "action=alreadyClaimed", "rewardId", rewardId)
		Remote:FireClient(player, "alreadyClaimed", rewardId)
		return
	end

	local elapsedPlayTime = getElapsedPlayTime(state, currentPlayTime)
	if elapsedPlayTime < config.Time then
		giftLog(
			"[GIFT][DATA]",
			"player",
			player.Name,
			"action=notReady",
			"rewardId",
			rewardId,
			"remaining",
			config.Time - elapsedPlayTime
		)
		Remote:FireClient(player, "notReady", rewardId, config.Time - elapsedPlayTime)
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
		return
	end

	local rewardGranted, rewardName, amount, grantReason = safeGrantReward(player, rewardId)
	if not rewardGranted then
		state.ClaimedRewards = previousClaimedRewards
		state.LastClaimPlayTime = previousLastClaimPlayTime
		persistTimeRewardState(player, state)
		claimLocks[player] = nil
		giftError("Failed to grant time reward", player.Name, rewardId, grantReason)
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
		syncPlayerState(player)
	end)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		syncPlayerState(player)
	end)
end

Players.PlayerRemoving:Connect(function(player)
	claimLocks[player] = nil
	lastClaimRequestAt[player] = nil
	playTimeSessions[player] = nil
end)

Remote.OnServerEvent:Connect(function(player, rewardId)
	rewardId = tonumber(rewardId)
	if not rewardId or rewardId ~= math.floor(rewardId) then
		return
	end

	claimReward(player, rewardId)
end)

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
