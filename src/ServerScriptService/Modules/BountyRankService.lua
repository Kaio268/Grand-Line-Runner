local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BountyService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushBountyService"))

local Service = {}

local STORE_NAME = "GrandLineRush_BountyLeaderboard_v2"
local RANK_ATTRIBUTE = "LB_Bounty"
local MAX_RANK_ENTRIES = 100
local DEFAULT_DISPLAY_LIMIT = 10
local READY_TIMEOUT_SECONDS = 30
local WRITE_DEBOUNCE_SECONDS = 2
local REFRESH_AFTER_WRITE_SECONDS = 3
local MIN_GLOBAL_READ_SECONDS = 60
local SAFE_REFRESH_SECONDS = 300
local DATASTORE_RETRIES = 3
local PLAYER_REMOVING_FLUSH_TIMEOUT = 5
local BIND_TO_CLOSE_FLUSH_TIMEOUT = 12

local STATUS_LOADING = "Loading"
local STATUS_READY = "Ready"
local STATUS_ERROR = "Error"
local STATUS_STALE = "Stale"

local function getRequestType(name, fallback)
	local ok, value = pcall(function()
		return Enum.DataStoreRequestType[name]
	end)

	if ok and value ~= nil then
		return value
	end

	return fallback
end

local READ_BUDGET_TYPE = Enum.DataStoreRequestType.GetSortedAsync
local WRITE_BUDGET_TYPE = getRequestType(
	"SetIncrementSortedAsync",
	getRequestType("SetIncrementAsync", Enum.DataStoreRequestType.UpdateAsync)
)

local bountyStore = DataStoreService:GetOrderedDataStore(STORE_NAME)
local changedEvent = Instance.new("BindableEvent")

local currentSnapshot = {}
local rankByUserId = {}
local identityCache = {}
local playerConnections = {}
local pendingWrites = {}
local pendingWriteOrder = {}
local writeQueuedByKey = {}
local lastWrittenValues = {}

local started = false
local refreshScheduled = false
local refreshDirty = false
local lastGlobalReadAt = -math.huge
local lastSuccessfulRefreshUnix = 0
local currentStatus = STATUS_LOADING
local currentErrorMessage = nil

Service.Changed = changedEvent.Event

local function normalizeBounty(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function sanitizeReason(reason)
	if reason == nil then
		return nil
	end

	local text = tostring(reason)
	text = text:gsub("[%c\r\n\t]", " ")
	text = text:gsub("%s+", " ")
	text = text:gsub("^%s+", "")
	text = text:gsub("%s+$", "")

	if #text > 80 then
		text = string.sub(text, 1, 77) .. "..."
	end

	if text == "" then
		return nil
	end

	return text
end

local function isSnapshotUsable()
	return (currentStatus == STATUS_READY or currentStatus == STATUS_STALE) and lastSuccessfulRefreshUnix > 0
end

local function getStatusPayload()
	return {
		Status = currentStatus,
		Ready = isSnapshotUsable(),
		LastRefreshAt = lastSuccessfulRefreshUnix,
		ErrorMessage = currentErrorMessage,
		VisibleLimit = MAX_RANK_ENTRIES,
		VisibleCount = #currentSnapshot,
	}
end

local function disconnectConnections(connections)
	for _, connection in ipairs(connections or {}) do
		connection:Disconnect()
	end
end

local function getUserId(playerOrUserId)
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end

	local userId = math.floor(tonumber(playerOrUserId) or 0)
	if userId > 0 then
		return userId
	end

	return nil
end

local function getRankEntryForUserId(userId)
	if not isSnapshotUsable() then
		return nil
	end

	local entry = rankByUserId[tonumber(userId)]
	if entry and normalizeBounty(entry.bounty) > 0 then
		return entry
	end

	return nil
end

local function publishPlayerAttributes(player)
	if not player or player.Parent ~= Players then
		return
	end

	local entry = getRankEntryForUserId(player.UserId)
	player:SetAttribute(RANK_ATTRIBUTE, entry and entry.rank or nil)
	player:SetAttribute(RANK_ATTRIBUTE .. "_Ready", isSnapshotUsable())
	player:SetAttribute(RANK_ATTRIBUTE .. "_Status", currentStatus)
	player:SetAttribute(RANK_ATTRIBUTE .. "_LastRefreshAt", lastSuccessfulRefreshUnix)
	player:SetAttribute(RANK_ATTRIBUTE .. "_ErrorMessage", currentErrorMessage)
	player:SetAttribute(RANK_ATTRIBUTE .. "_VisibleLimit", MAX_RANK_ENTRIES)
	player:SetAttribute(RANK_ATTRIBUTE .. "_VisibleCount", #currentSnapshot)
end

local function publishAllPlayerAttributes()
	for _, player in ipairs(Players:GetPlayers()) do
		publishPlayerAttributes(player)
	end
end

local function fireChanged()
	changedEvent:Fire(getStatusPayload())
end

local function setStatus(status, reason)
	local sanitizedReason = sanitizeReason(reason)
	local changed = currentStatus ~= status or currentErrorMessage ~= sanitizedReason

	currentStatus = status
	currentErrorMessage = sanitizedReason
	publishAllPlayerAttributes()

	if changed then
		fireChanged()
	end
end

local function getRequestBudget(requestType)
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)

	if ok and typeof(budget) == "number" then
		return budget
	end

	return 0
end

local function waitForBudget(requestType, deadline)
	while true do
		if getRequestBudget(requestType) > 0 then
			return true
		end

		if deadline and os.clock() >= deadline then
			return false
		end

		task.wait(0.1)
	end
end

local function readPlayerBounty(player)
	if not player or player.Parent ~= Players or not DataManager:IsReady(player) then
		return nil, "not_ready"
	end

	local breakdown = BountyService.GetBreakdown(player)
	if typeof(breakdown) == "table" and typeof(breakdown.Total) == "number" then
		return normalizeBounty(breakdown.Total), nil
	end

	local storedBounty = nil
	local reason = nil
	if typeof(DataManager.TryGetValue) == "function" then
		storedBounty, reason = DataManager:TryGetValue(player, "leaderstats.Bounty")
	else
		storedBounty = DataManager:GetValue(player, "leaderstats.Bounty")
	end

	if storedBounty == nil then
		return nil, reason or "missing_bounty"
	end

	return normalizeBounty(storedBounty), nil
end

local function getGlobalReadCooldownRemaining()
	return math.max(0, (lastGlobalReadAt + MIN_GLOBAL_READ_SECONDS) - os.clock())
end

local function buildIdentityMap(userIds)
	local identities = {}
	local lookupIds = {}
	local lookupSeen = {}

	for _, userId in ipairs(userIds) do
		local onlinePlayer = Players:GetPlayerByUserId(userId)
		if onlinePlayer then
			local identity = {
				userId = userId,
				name = onlinePlayer.Name,
				displayName = onlinePlayer.DisplayName,
			}
			identityCache[userId] = identity
			identities[userId] = identity
		elseif identityCache[userId] then
			identities[userId] = identityCache[userId]
		elseif not lookupSeen[userId] then
			lookupSeen[userId] = true
			lookupIds[#lookupIds + 1] = userId
		end
	end

	if #lookupIds > 0 then
		local ok, infos = pcall(function()
			return UserService:GetUserInfosByUserIdsAsync(lookupIds)
		end)

		if ok and typeof(infos) == "table" then
			for index, info in ipairs(infos) do
				local userId = math.floor(tonumber(info and info.Id) or 0)
				if userId <= 0 then
					userId = lookupIds[index]
				end

				local identity = {
					userId = userId,
					name = info and tostring(info.Username or "") or ("User " .. tostring(userId)),
					displayName = info and tostring(info.DisplayName or "") or ("User " .. tostring(userId)),
				}
				identityCache[userId] = identity
				identities[userId] = identity
			end
		end
	end

	for _, userId in ipairs(userIds) do
		if identities[userId] == nil then
			local identity = {
				userId = userId,
				name = "User " .. tostring(userId),
				displayName = "User " .. tostring(userId),
			}
			identityCache[userId] = identity
			identities[userId] = identity
		end
	end

	return identities
end

local function buildSnapshotFromPage(page)
	local rawEntries = {}
	local userIds = {}

	for _, entry in ipairs(page or {}) do
		local userId = math.floor(tonumber(entry.key) or 0)
		if userId > 0 then
			rawEntries[#rawEntries + 1] = {
				userId = userId,
				bounty = normalizeBounty(entry.value),
			}
			userIds[#userIds + 1] = userId
		end
	end

	local identities = buildIdentityMap(userIds)
	local snapshot = {}

	for _, entry in ipairs(rawEntries) do
		local identity = identities[entry.userId] or {}
		snapshot[#snapshot + 1] = {
			bounty = entry.bounty,
			displayName = tostring(identity.displayName or ("User " .. tostring(entry.userId))),
			name = tostring(identity.name or ("User " .. tostring(entry.userId))),
			rank = #snapshot + 1,
			userId = entry.userId,
		}
	end

	return snapshot
end

local function applySnapshot(snapshot)
	currentSnapshot = snapshot or {}
	rankByUserId = {}

	for _, entry in ipairs(currentSnapshot) do
		if typeof(entry) == "table" and tonumber(entry.userId) then
			rankByUserId[tonumber(entry.userId)] = entry
		end
	end

	lastSuccessfulRefreshUnix = os.time()
	currentStatus = STATUS_READY
	currentErrorMessage = nil
	publishAllPlayerAttributes()
	fireChanged()
end

local function handleRefreshFailure(reason)
	local status = if lastSuccessfulRefreshUnix > 0 then STATUS_STALE else STATUS_ERROR
	setStatus(status, reason or "read_failed")
end

local refreshBoardFromStore
local scheduleBoardRefresh

refreshBoardFromStore = function(reason)
	if getRequestBudget(READ_BUDGET_TYPE) <= 0 then
		handleRefreshFailure("no_read_budget")
		return false, "no_read_budget"
	end

	lastGlobalReadAt = os.clock()
	local ok, pagesOrError = pcall(function()
		return bountyStore:GetSortedAsync(false, MAX_RANK_ENTRIES)
	end)

	if not ok then
		warn(("[BountyRankService] Failed to read OrderedDataStore reason=%s: %s"):format(
			tostring(reason or "unspecified"),
			tostring(pagesOrError)
		))
		handleRefreshFailure(pagesOrError)
		return false, pagesOrError
	end

	applySnapshot(buildSnapshotFromPage(pagesOrError:GetCurrentPage()))
	return true, nil
end

scheduleBoardRefresh = function(reason, delaySeconds)
	refreshDirty = true

	if refreshScheduled then
		return
	end

	local requestedDelay = math.max(0, tonumber(delaySeconds) or 0)
	local cooldownDelay = getGlobalReadCooldownRemaining()
	local scheduledDelay = math.max(requestedDelay, cooldownDelay)

	refreshScheduled = true
	task.delay(scheduledDelay, function()
		refreshScheduled = false

		if not refreshDirty then
			return
		end

		local cooldownRemaining = getGlobalReadCooldownRemaining()
		if cooldownRemaining > 0 then
			scheduleBoardRefresh(reason or "cooldown", cooldownRemaining)
			return
		end

		refreshDirty = false
		local refreshed, refreshReason = refreshBoardFromStore(reason)
		if not refreshed then
			refreshDirty = true
			local retryDelay = if refreshReason == "no_read_budget" then 15 else MIN_GLOBAL_READ_SECONDS
			scheduleBoardRefresh(refreshReason or "read_retry", retryDelay)
		end
	end)
end

local function queueBountyWrite(player, bounty)
	if not player or player.UserId <= 0 then
		return false, "invalid_player"
	end

	local key = tostring(player.UserId)
	local normalized = normalizeBounty(bounty)

	if lastWrittenValues[key] == normalized and not pendingWrites[key] then
		return true, "unchanged"
	end

	pendingWrites[key] = {
		userId = player.UserId,
		value = normalized,
		queuedAt = os.clock(),
	}

	if not writeQueuedByKey[key] then
		writeQueuedByKey[key] = true
		pendingWriteOrder[#pendingWriteOrder + 1] = key
	end

	return true, "queued"
end

local function writePendingKey(key, force, deadline)
	local entry = pendingWrites[key]
	if entry == nil then
		return true, "empty"
	end

	if not force and os.clock() - entry.queuedAt < WRITE_DEBOUNCE_SECONDS then
		return false, "debouncing"
	end

	if not waitForBudget(WRITE_BUDGET_TYPE, deadline) then
		return false, "no_write_budget"
	end

	local value = normalizeBounty(entry.value)
	local lastError = nil

	for attempt = 1, DATASTORE_RETRIES do
		if deadline and os.clock() >= deadline then
			return false, lastError or "flush_timeout"
		end

		local ok, err = pcall(function()
			return bountyStore:SetAsync(key, value)
		end)

		if ok then
			pendingWrites[key] = nil
			lastWrittenValues[key] = value
			scheduleBoardRefresh("write_success", REFRESH_AFTER_WRITE_SECONDS)
			return true, "written"
		end

		lastError = err
		task.wait(math.min(5, 0.4 * (2 ^ attempt)))
	end

	warn(("[BountyRankService] Failed to write bounty userId=%s: %s"):format(key, tostring(lastError)))
	return false, lastError or "write_failed"
end

local function drainWrites()
	while true do
		local processed = 0
		local budget = getRequestBudget(WRITE_BUDGET_TYPE)

		while budget > processed and #pendingWriteOrder > 0 do
			local key = table.remove(pendingWriteOrder, 1)
			writeQueuedByKey[key] = nil

			local ok, reason = writePendingKey(key, false)
			if not ok and pendingWrites[key] ~= nil then
				if not writeQueuedByKey[key] then
					writeQueuedByKey[key] = true
					pendingWriteOrder[#pendingWriteOrder + 1] = key
				end

				if reason == "debouncing" then
					break
				end
			end

			processed += 1
		end

		task.wait(0.5)
	end
end

local function waitForReady(player, timeoutSeconds)
	if typeof(DataManager.WaitUntilReady) == "function" then
		return DataManager:WaitUntilReady(player, timeoutSeconds or READY_TIMEOUT_SECONDS)
	end

	local deadline = os.clock() + (timeoutSeconds or READY_TIMEOUT_SECONDS)
	while player.Parent == Players and os.clock() < deadline do
		if DataManager:IsReady(player) then
			return true
		end
		task.wait(0.1)
	end

	return player.Parent == Players and DataManager:IsReady(player)
end

local function refreshPlayerWhenReady(player)
	task.spawn(function()
		if not waitForReady(player, READY_TIMEOUT_SECONDS) or player.Parent ~= Players then
			return
		end

		local breakdown = BountyService.RefreshPlayerBounty(player)
		local bounty = typeof(breakdown) == "table" and breakdown.Total or nil
		if bounty == nil then
			bounty = readPlayerBounty(player)
		end

		if bounty ~= nil then
			queueBountyWrite(player, bounty)
			scheduleBoardRefresh("player_ready", REFRESH_AFTER_WRITE_SECONDS)
		end
	end)
end

local function connectPlayer(player)
	disconnectConnections(playerConnections[player])
	publishPlayerAttributes(player)

	local connections = {}
	playerConnections[player] = connections

	connections[#connections + 1] = player:GetAttributeChangedSignal("PlayerDataReady"):Connect(function()
		if player:GetAttribute("PlayerDataReady") == true then
			refreshPlayerWhenReady(player)
		end
	end)

	connections[#connections + 1] = player.ChildAdded:Connect(function(child)
		if child.Name == "leaderstats" or child.Name == "Bounty" then
			refreshPlayerWhenReady(player)
		end
	end)

	refreshPlayerWhenReady(player)
end

local function disconnectPlayer(player)
	local bounty = readPlayerBounty(player)
	if bounty ~= nil then
		queueBountyWrite(player, bounty)
	end

	Service.FlushPlayer(player, PLAYER_REMOVING_FLUSH_TIMEOUT)
	disconnectConnections(playerConnections[player])
	playerConnections[player] = nil
	scheduleBoardRefresh("player_left", REFRESH_AFTER_WRITE_SECONDS)
end

function Service.Start()
	if started then
		return
	end

	started = true
	currentStatus = STATUS_LOADING
	currentErrorMessage = nil

	for _, player in ipairs(Players:GetPlayers()) do
		connectPlayer(player)
	end

	Players.PlayerAdded:Connect(connectPlayer)
	Players.PlayerRemoving:Connect(disconnectPlayer)

	BountyService.BountyChanged:Connect(function(player, breakdown)
		if player and player.Parent == Players then
			local bounty = typeof(breakdown) == "table" and breakdown.Total or nil
			if bounty == nil then
				bounty = readPlayerBounty(player)
			end

			if bounty ~= nil then
				queueBountyWrite(player, bounty)
				scheduleBoardRefresh("bounty_changed", REFRESH_AFTER_WRITE_SECONDS)
			end
		end
	end)

	game:BindToClose(function()
		Service.FlushAll(BIND_TO_CLOSE_FLUSH_TIMEOUT)
	end)

	task.spawn(drainWrites)

	task.spawn(function()
		task.wait(2)
		if not refreshBoardFromStore("startup") then
			scheduleBoardRefresh("startup_retry", 15)
		end

		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				local bounty = readPlayerBounty(player)
				if bounty ~= nil then
					queueBountyWrite(player, bounty)
				end
			end

			scheduleBoardRefresh("safety")
			task.wait(SAFE_REFRESH_SECONDS)
		end
	end)
end

function Service.RecordPlayer(player, bounty)
	Service.Start()

	if not player or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local value = bounty
	if value == nil then
		value = readPlayerBounty(player)
	end

	if value == nil then
		return false, "missing_bounty"
	end

	return queueBountyWrite(player, value)
end

function Service.FlushPlayer(playerOrUserId, timeoutSeconds)
	local userId = getUserId(playerOrUserId)
	if userId == nil then
		return true, "invalid_user"
	end

	local key = tostring(userId)
	local deadline = os.clock() + math.max(0.5, tonumber(timeoutSeconds) or PLAYER_REMOVING_FLUSH_TIMEOUT)

	while pendingWrites[key] ~= nil and os.clock() < deadline do
		local ok = writePendingKey(key, true, deadline)
		if ok then
			return true, "flushed"
		end
		task.wait(0.1)
	end

	return pendingWrites[key] == nil, if pendingWrites[key] == nil then "flushed" else "flush_timeout"
end

function Service.FlushAll(timeoutSeconds)
	local deadline = os.clock() + math.max(1, tonumber(timeoutSeconds) or BIND_TO_CLOSE_FLUSH_TIMEOUT)

	for _, player in ipairs(Players:GetPlayers()) do
		local bounty = readPlayerBounty(player)
		if bounty ~= nil then
			queueBountyWrite(player, bounty)
		end
	end

	while next(pendingWrites) ~= nil and os.clock() < deadline do
		for key in pairs(pendingWrites) do
			if os.clock() >= deadline then
				break
			end
			writePendingKey(key, true, deadline)
		end
		task.wait(0.1)
	end

	return next(pendingWrites) == nil
end

function Service.GetPlayerRank(playerOrUserId)
	local userId = getUserId(playerOrUserId)
	if userId == nil then
		return nil, nil, getStatusPayload()
	end

	local entry = getRankEntryForUserId(userId)
	if entry == nil then
		return nil, rankByUserId[userId], getStatusPayload()
	end

	return entry.rank, table.clone(entry), getStatusPayload()
end

function Service.IsReady()
	return isSnapshotUsable()
end

function Service.GetStatus()
	return getStatusPayload()
end

function Service.GetDisplayRows(limit)
	local maxRows = math.max(0, math.floor(tonumber(limit) or DEFAULT_DISPLAY_LIMIT))
	local rows = {}

	for index = 1, math.min(maxRows, #currentSnapshot) do
		rows[index] = table.clone(currentSnapshot[index])
	end

	return rows
end

function Service.IsPirateEmperorEligible(player)
	Service.Start()

	if not player or not player:IsA("Player") then
		return false, "invalid_player", getStatusPayload()
	end

	local rank, entry, status = Service.GetPlayerRank(player)
	if not status.Ready then
		return false, string.lower(tostring(status.Status or STATUS_LOADING)), status
	end

	if rank == 1 and entry and normalizeBounty(entry.bounty) > 0 then
		return true, "bounty_rank_1", status
	end

	if entry and normalizeBounty(entry.bounty) <= 0 then
		return false, "no_bounty", status
	end

	return false, rank and "bounty_rank_miss" or "outside_bounty_board", status
end

return Service
