local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local REMOTES_FOLDER_NAME = "Remotes"
local REMOTE_NAME = "GTRLoadTelemetry"
local STORE_NAME = "GTR_LoadTelemetry_Abnormal_v1"
local SLOW_LOAD_THRESHOLD_SECONDS = 12
local RECENT_SUMMARY_LIMIT = 200
local MAX_PENDING_ABNORMAL = 100
local MAX_BATCH_SIZE = 20
local FLUSH_INTERVAL_SECONDS = 30
local RATE_WINDOW_SECONDS = 60
local MAX_REPORTS_PER_WINDOW = 8

local recentSummaries = {}
local pendingAbnormal = {}
local flushScheduled = false
local batchCounter = 0
local rateByPlayer = {}

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotes and remotes:IsA("Folder") then
		return remotes
	end
	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = REMOTES_FOLDER_NAME
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemoteEvent()
	local remotes = getOrCreateRemotesFolder()
	local remote = remotes:FindFirstChild(REMOTE_NAME)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = REMOTE_NAME
	remote.Parent = remotes
	return remote
end

local function clampNumber(value, minValue, maxValue, fallback)
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue then
		return fallback
	end
	return math.clamp(numberValue, minValue, maxValue)
end

local function asBoolean(value)
	return value == true
end

local function asString(value, maxLength)
	local text = tostring(value or "")
	if #text > maxLength then
		text = text:sub(1, maxLength)
	end
	return text
end

local function addRecentSummary(summary)
	recentSummaries[#recentSummaries + 1] = summary
	if #recentSummaries > RECENT_SUMMARY_LIMIT then
		table.remove(recentSummaries, 1)
	end
end

local function isAbnormal(summary)
	return summary.TimedOut == true
		or summary.OverlayRecovery == true
		or summary.CameraRecovery == true
		or summary.BootstrapError == true
		or summary.DataInitError == true
		or summary.LoadDuration > SLOW_LOAD_THRESHOLD_SECONDS
end

local function makeBatchKey()
	batchCounter += 1
	local jobId = tostring(game.JobId or "studio"):gsub("[^%w_%-]", "")
	if jobId == "" then
		jobId = "studio"
	end
	local suffixStart = math.max(1, #jobId - 7)
	local jobSuffix = jobId:sub(suffixStart)
	return string.format("b_%d_%04d_%s", os.time(), batchCounter % 10000, jobSuffix)
end

local function flushPendingAbnormal()
	flushScheduled = false
	if #pendingAbnormal <= 0 then
		return
	end

	local budget = 0
	pcall(function()
		budget = DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	if budget <= 0 then
		task.delay(FLUSH_INTERVAL_SECONDS, function()
			flushPendingAbnormal()
		end)
		return
	end

	local batch = {}
	while #pendingAbnormal > 0 and #batch < MAX_BATCH_SIZE do
		batch[#batch + 1] = table.remove(pendingAbnormal, 1)
	end
	if #batch <= 0 then
		return
	end

	local okStore, store = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not okStore or not store then
		return
	end

	local key = makeBatchKey()
	pcall(function()
		store:UpdateAsync(key, function()
			return {
				CreatedAt = os.time(),
				JobId = game.JobId,
				Records = batch,
			}
		end)
	end)

	if #pendingAbnormal > 0 then
		task.delay(1, function()
			flushPendingAbnormal()
		end)
	end
end

local function scheduleFlush(delaySeconds)
	if flushScheduled then
		return
	end
	flushScheduled = true
	task.delay(delaySeconds, function()
		flushPendingAbnormal()
	end)
end

local function queueAbnormal(summary)
	pendingAbnormal[#pendingAbnormal + 1] = summary
	while #pendingAbnormal > MAX_PENDING_ABNORMAL do
		table.remove(pendingAbnormal, 1)
	end

	if #pendingAbnormal >= MAX_BATCH_SIZE then
		task.spawn(flushPendingAbnormal)
	else
		scheduleFlush(FLUSH_INTERVAL_SECONDS)
	end
end

local function passesRateLimit(player)
	local now = os.clock()
	local state = rateByPlayer[player]
	if not state or now - state.WindowStart > RATE_WINDOW_SECONDS then
		rateByPlayer[player] = {
			WindowStart = now,
			Count = 1,
		}
		return true
	end

	state.Count += 1
	return state.Count <= MAX_REPORTS_PER_WINDOW
end

local function sanitizeSummary(player, payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	return {
		UserId = player.UserId,
		PlayerName = asString(player.Name, 40),
		JoinTimestamp = math.floor(clampNumber(payload.JoinTimestamp, 0, os.time(), os.time())),
		ReportedAt = os.time(),
		LoadDuration = clampNumber(payload.LoadDuration, 0, 300, 0),
		CloseReason = asString(payload.CloseReason, 60),
		TimedOut = asBoolean(payload.TimedOut),
		OverlayRecovery = asBoolean(payload.OverlayRecovery),
		CameraRecovery = asBoolean(payload.CameraRecovery),
		MissingMilestones = asString(payload.MissingMilestones, 240),
		DeviceInputType = asString(payload.DeviceInputType, 40),
		BootstrapError = asBoolean(payload.BootstrapError),
		DataInitError = asBoolean(payload.DataInitError),
	}
end

local remote = getOrCreateRemoteEvent()

remote.OnServerEvent:Connect(function(player, payload)
	if not passesRateLimit(player) then
		return
	end

	local summary = sanitizeSummary(player, payload)
	if not summary then
		return
	end

	addRecentSummary(summary)
	if isAbnormal(summary) then
		queueAbnormal(summary)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	rateByPlayer[player] = nil
end)

game:BindToClose(function()
	pcall(function()
		flushPendingAbnormal()
	end)
end)
