local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local UserService = game:GetService("UserService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local BountyService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushBountyService"))

local BOARD_MODEL_NAME = "BountyLeaderboard"
local LEADERBOARD_PLANE_NAME = "LeaderboardGuiPlane"
local SURFACE_GUI_NAME = "LeaderboardSurfaceGui"
local POSTERS_FRAME_NAME = "PostersFrame"
local STORE_NAME = "GrandLineRush_BountyLeaderboard_v2"
local MAX_ENTRIES = 10
local READY_TIMEOUT_SECONDS = 30
local WRITE_DEBOUNCE_SECONDS = 2
local REFRESH_AFTER_WRITE_SECONDS = 3
local SAFE_REFRESH_SECONDS = 120
local DATASTORE_RETRIES = 3
local DEFAULT_SILHOUETTE_IMAGE = "rbxassetid://114486835434518"

local REMOTES_FOLDER_NAME = "Remotes"
local STATE_EVENT_NAME = "BountyLeaderboardState"
local SNAPSHOT_REQUEST_NAME = "BountyLeaderboardSnapshotRequest"

local bountyStore = DataStoreService:GetOrderedDataStore(STORE_NAME)
local currentSnapshot = {}
local identityCache = {}
local playerConnections = {}
local pendingWrites = {}
local pendingWriteOrder = {}
local writeQueuedByKey = {}
local lastWrittenValues = {}
local refreshScheduled = false
local warnedMissingBoard = false

local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = REMOTES_FOLDER_NAME
	remotesFolder.Parent = ReplicatedStorage
end

local stateEvent = remotesFolder:FindFirstChild(STATE_EVENT_NAME)
if stateEvent and not stateEvent:IsA("RemoteEvent") then
	stateEvent:Destroy()
	stateEvent = nil
end
if not stateEvent then
	stateEvent = Instance.new("RemoteEvent")
	stateEvent.Name = STATE_EVENT_NAME
	stateEvent.Parent = remotesFolder
end

local snapshotRequest = remotesFolder:FindFirstChild(SNAPSHOT_REQUEST_NAME)
if snapshotRequest and not snapshotRequest:IsA("RemoteFunction") then
	snapshotRequest:Destroy()
	snapshotRequest = nil
end
if not snapshotRequest then
	snapshotRequest = Instance.new("RemoteFunction")
	snapshotRequest.Name = SNAPSHOT_REQUEST_NAME
	snapshotRequest.Parent = remotesFolder
end

local function disconnectConnections(connections)
	for _, connection in ipairs(connections or {}) do
		connection:Disconnect()
	end
end

local function normalizeBounty(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function formatNumber(value)
	local bounty = normalizeBounty(value)
	local compactTiers = {
		{threshold = 1_000_000_000_000, suffix = "T"},
		{threshold = 1_000_000_000, suffix = "B"},
		{threshold = 1_000_000, suffix = "M"},
	}

	for _, tier in ipairs(compactTiers) do
		if bounty >= tier.threshold then
			return string.format("%.2f%s", bounty / tier.threshold, tier.suffix)
		end
	end

	local formatted = tostring(bounty)

	while true do
		local replaced, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = replaced
		if count == 0 then
			break
		end
	end

	return formatted
end

local function shortenName(name, maxLength)
	local text = tostring(name or "")
	if #text > maxLength then
		return string.sub(text, 1, maxLength - 3) .. "..."
	end

	return text
end

local function getPostersFrame()
	local board = workspace:FindFirstChild(BOARD_MODEL_NAME)
	if not board then
		if not warnedMissingBoard then
			warn("[BountyLeaderboard] Missing Workspace." .. BOARD_MODEL_NAME)
			warnedMissingBoard = true
		end
		return nil
	end

	local plane = board:FindFirstChild(LEADERBOARD_PLANE_NAME)
	local surfaceGui = plane and plane:FindFirstChild(SURFACE_GUI_NAME)
	local postersFrame = surfaceGui and surfaceGui:FindFirstChild(POSTERS_FRAME_NAME)
	if not postersFrame then
		if not warnedMissingBoard then
			warn("[BountyLeaderboard] Missing authored poster UI under Workspace." .. BOARD_MODEL_NAME)
			warnedMissingBoard = true
		end
		return nil
	end

	warnedMissingBoard = false
	return postersFrame
end

local function setTextDeep(parent, objectName, textValue)
	local object = parent and parent:FindFirstChild(objectName, true)
	if object and object:IsA("TextLabel") then
		object.Text = textValue
	end
end

local function setImageDeep(parent, objectName, imageValue)
	local object = parent and parent:FindFirstChild(objectName, true)
	if object and object:IsA("ImageLabel") then
		object.Image = imageValue
	end
end

local function getPosterName(index)
	return string.format("Poster%02d", index)
end

local function getThumbnailForUserId(userId)
	if not userId or userId <= 0 then
		return DEFAULT_SILHOUETTE_IMAGE
	end

	return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=180&h=180"
end

local function renderSnapshot(snapshot)
	local postersFrame = getPostersFrame()
	if not postersFrame then
		return
	end

	for index = 1, MAX_ENTRIES do
		local poster = postersFrame:FindFirstChild(getPosterName(index))
		local entry = snapshot[index]

		if poster then
			setTextDeep(poster, "RankText", "#" .. tostring(index))

			if entry then
				local displayName = tostring(entry.displayName or "")
				local username = tostring(entry.name or "")
				local visibleName = if displayName ~= "" then displayName else username

				setTextDeep(poster, "NameText", shortenName(visibleName, 18))
				setTextDeep(poster, "BountyText", formatNumber(entry.bounty))
				setImageDeep(poster, "AvatarImage", getThumbnailForUserId(tonumber(entry.userId)))
			else
				setTextDeep(poster, "NameText", "WANTED")
				setTextDeep(poster, "BountyText", "???")
				setImageDeep(poster, "AvatarImage", DEFAULT_SILHOUETTE_IMAGE)
			end
		else
			warn("[BountyLeaderboard] Missing poster: " .. getPosterName(index))
		end
	end
end

local function publishSnapshot(snapshot)
	currentSnapshot = snapshot or {}
	renderSnapshot(currentSnapshot)
	stateEvent:FireAllClients(currentSnapshot)
end

local function callWithRetries(callback, retries)
	local lastError = nil

	for attempt = 1, retries or DATASTORE_RETRIES do
		local ok, result = pcall(callback)
		if ok then
			return true, result
		end

		lastError = result
		task.wait(math.min(5, 0.4 * (2 ^ attempt)))
	end

	return false, lastError
end

local function getIdentity(userId)
	userId = tonumber(userId)
	if not userId or userId <= 0 then
		return {
			userId = userId or 0,
			name = "Unknown",
			displayName = "Unknown",
		}
	end

	local cached = identityCache[userId]
	if cached then
		return cached
	end

	local onlinePlayer = Players:GetPlayerByUserId(userId)
	if onlinePlayer then
		cached = {
			userId = userId,
			name = onlinePlayer.Name,
			displayName = onlinePlayer.DisplayName,
		}
		identityCache[userId] = cached
		return cached
	end

	local ok, infos = pcall(function()
		return UserService:GetUserInfosByUserIdsAsync({ userId })
	end)

	local info = ok and infos and infos[1] or nil
	cached = {
		userId = userId,
		name = info and tostring(info.Username or "") or ("User " .. tostring(userId)),
		displayName = info and tostring(info.DisplayName or "") or ("User " .. tostring(userId)),
	}
	identityCache[userId] = cached
	return cached
end

local function buildSnapshotFromPage(page)
	local snapshot = {}

	for rank, entry in ipairs(page or {}) do
		local userId = tonumber(entry.key)
		local identity = getIdentity(userId)

		snapshot[#snapshot + 1] = {
			bounty = normalizeBounty(entry.value),
			displayName = identity.displayName,
			name = identity.name,
			rank = rank,
			userId = identity.userId,
		}
	end

	return snapshot
end

local function refreshBoardFromStore()
	local budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetSortedAsync)
	if budget <= 0 then
		return false, "no_get_budget"
	end

	local ok, pagesOrError = callWithRetries(function()
		return bountyStore:GetSortedAsync(false, MAX_ENTRIES)
	end)
	if not ok then
		warn("[BountyLeaderboard] Failed to read OrderedDataStore: " .. tostring(pagesOrError))
		return false, pagesOrError
	end

	local page = pagesOrError:GetCurrentPage()
	publishSnapshot(buildSnapshotFromPage(page))
	return true, nil
end

local function scheduleBoardRefresh(delaySeconds)
	if refreshScheduled then
		return
	end

	refreshScheduled = true
	task.delay(delaySeconds or 0, function()
		refreshScheduled = false
		local refreshed = refreshBoardFromStore()
		if not refreshed then
			renderSnapshot(currentSnapshot)
		end
	end)
end

local function readPlayerBounty(player)
	if not DataManager:IsReady(player) then
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

local function queueBountyWrite(player, bounty)
	if not player or player.UserId <= 0 then
		return
	end

	local userId = player.UserId
	local key = tostring(userId)
	local normalized = normalizeBounty(bounty)

	if lastWrittenValues[key] == normalized and not pendingWrites[key] then
		return
	end

	pendingWrites[key] = {
		userId = userId,
		value = normalized,
		queuedAt = os.clock(),
	}

	if not writeQueuedByKey[key] then
		writeQueuedByKey[key] = true
		pendingWriteOrder[#pendingWriteOrder + 1] = key
	end
end

local function queuePlayerBountyWrite(player)
	local bounty = readPlayerBounty(player)
	if bounty == nil then
		return
	end

	queueBountyWrite(player, bounty)
end

local function drainWrites()
	while true do
		local now = os.clock()
		local updateBudget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		local processed = 0

		while updateBudget > processed and #pendingWriteOrder > 0 do
			local key = table.remove(pendingWriteOrder, 1)
			writeQueuedByKey[key] = nil

			local entry = pendingWrites[key]
			if entry and now - entry.queuedAt >= WRITE_DEBOUNCE_SECONDS then
				pendingWrites[key] = nil

				local value = entry.value
				local ok, err = callWithRetries(function()
					return bountyStore:UpdateAsync(key, function()
						return value
					end)
				end)

				if ok then
					lastWrittenValues[key] = value
					scheduleBoardRefresh(REFRESH_AFTER_WRITE_SECONDS)
				else
					warn(("[BountyLeaderboard] Failed to write bounty userId=%s: %s"):format(key, tostring(err)))
					pendingWrites[key] = entry
					if not writeQueuedByKey[key] then
						writeQueuedByKey[key] = true
						pendingWriteOrder[#pendingWriteOrder + 1] = key
					end
				end

				processed += 1
			elseif entry then
				if not writeQueuedByKey[key] then
					writeQueuedByKey[key] = true
					pendingWriteOrder[#pendingWriteOrder + 1] = key
				end
				break
			end
		end

		task.wait(0.5)
	end
end

local function refreshPlayerWhenReady(player)
	task.spawn(function()
		local ready = false
		if typeof(DataManager.WaitUntilReady) == "function" then
			ready = DataManager:WaitUntilReady(player, READY_TIMEOUT_SECONDS)
		else
			local deadline = os.clock() + READY_TIMEOUT_SECONDS
			while player.Parent == Players and os.clock() < deadline do
				if DataManager:IsReady(player) then
					ready = true
					break
				end
				task.wait(0.1)
			end
		end

		if ready and player.Parent == Players then
			BountyService.RefreshPlayerBounty(player)
			queuePlayerBountyWrite(player)
			scheduleBoardRefresh(REFRESH_AFTER_WRITE_SECONDS)
		end
	end)
end

local function connectPlayer(player)
	disconnectConnections(playerConnections[player])

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
	queuePlayerBountyWrite(player)
	disconnectConnections(playerConnections[player])
	playerConnections[player] = nil
	scheduleBoardRefresh(REFRESH_AFTER_WRITE_SECONDS)
end

snapshotRequest.OnServerInvoke = function()
	return currentSnapshot
end

BountyService.BountyChanged:Connect(function(player, breakdown)
	if player and player.Parent == Players then
		local bounty = typeof(breakdown) == "table" and breakdown.Total or nil
		if bounty == nil then
			bounty = readPlayerBounty(player)
		end
		if bounty ~= nil then
			queueBountyWrite(player, bounty)
			scheduleBoardRefresh(REFRESH_AFTER_WRITE_SECONDS)
		end
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	connectPlayer(player)
end

Players.PlayerAdded:Connect(connectPlayer)
Players.PlayerRemoving:Connect(disconnectPlayer)

task.spawn(drainWrites)

task.spawn(function()
	renderSnapshot({})
	task.wait(2)
	if not refreshBoardFromStore() then
		renderSnapshot(currentSnapshot)
	end

	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			queuePlayerBountyWrite(player)
		end
		scheduleBoardRefresh()
		task.wait(SAFE_REFRESH_SECONDS)
	end
end)
