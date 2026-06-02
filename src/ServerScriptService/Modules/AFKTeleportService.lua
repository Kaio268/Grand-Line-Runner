local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local Economy = require(Configs:WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))
local RebirthConfig = require(Configs:WaitForChild("Rebirths"))
local CurrencyUtil = require(Modules:WaitForChild("CurrencyUtil"))
local ChestRewards = require(Configs:WaitForChild("GrandLineRushChestRewards"))
local ChestUtils = require(Modules:WaitForChild("GrandLineRushChestUtils"))
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(Modules:WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))

local AFKTeleportService = {}

local AFK_PATH = "AFK"
local DEFAULT_STATE_EVENT_NAME = "AFKTeleportState"
local DEFAULT_STATE_REQUEST_NAME = "AFKTeleportStateRequest"
local DEFAULT_ENTRY_REQUEST_NAME = "AFKTeleportEntryRequest"
local DEFAULT_RETURN_REQUEST_NAME = "AFKTeleportReturnRequest"
local DEFAULT_ACTIVITY_PING_EVENT_NAME = "AFKActivityPing"
local DEFAULT_INACTIVITY_SECONDS = 1080
local DEFAULT_ACTIVITY_PING_COOLDOWN_SECONDS = 15
local DEFAULT_SCAN_INTERVAL_SECONDS = 30
local DEFAULT_REFRESH_SECONDS = 960
local DEFAULT_REFRESH_RETRY_SECONDS = 30
local DEFAULT_REWARD_SETTLEMENT_SECONDS = 30
local DEFAULT_AFK_BELI_RATE_MULTIPLIER = 0.3
local DEFAULT_CHEST_TIER = "Gold"
local DEFAULT_CHEST_SOURCE = "AFK"
local DEFAULT_STANDARD_CHEST_INTERVAL_SECONDS = 3600
local DEFAULT_STANDARD_CHESTS_PER_INTERVAL = 1
local DEFAULT_VIP_CHEST_INTERVAL_SECONDS = 5400
local DEFAULT_VIP_CHESTS_PER_INTERVAL = 2
local TELEPORT_PENDING_TIMEOUT_SECONDS = 20
local CAPTAIN_SLOT_KEY = "Captain"

local SPECIAL_STATE_ATTRIBUTES = {
	"HoroProjectionActive",
	"MoguBurrowSessionId",
	"MoguBurrowSessionState",
}

local TIMED_SPECIAL_STATE_ATTRIBUTES = {
	"BomuMovementLockUntil",
	"MoguMovementLockUntil",
	"MoguBurrowProtectedUntil",
}

local started = false
local dataManagerRef = nil
local stateEvent = nil
local stateRequest = nil
local entryRequest = nil
local returnRequest = nil
local activityPingEvent = nil
local runtimeByPlayer = {}
local verticalSliceService = nil

local function getConfig()
	return if typeof(Economy.AFKTeleport) == "table" then Economy.AFKTeleport else {}
end

local function getNumber(value, fallback)
	return if typeof(value) == "number" then value else fallback
end

local function getNonNegativeNumber(value, fallback)
	return math.max(0, getNumber(value, fallback))
end

local function getPositiveNumber(value, fallback)
	return math.max(0.01, getNumber(value, fallback))
end

local function getPositiveInteger(value, fallback)
	return math.max(1, math.floor(getNumber(value, fallback)))
end

local function getPlaceId(value)
	return math.max(0, math.floor(getNumber(value, 0)))
end

local function getAfkPlaceId()
	return getPlaceId(getConfig().AFKPlaceId)
end

local function getMainPlaceId()
	return getPlaceId(getConfig().MainPlaceId)
end

local function isAfkPlace()
	local afkPlaceId = getAfkPlaceId()
	return afkPlaceId > 0 and game.PlaceId == afkPlaceId
end

local function isMainPlace()
	local mainPlaceId = getMainPlaceId()
	if mainPlaceId > 0 then
		return game.PlaceId == mainPlaceId
	end
	return not isAfkPlace()
end

local function todayUtc(now)
	return os.date("!%Y-%m-%d", now or os.time())
end

local function copyTable(value)
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[key] = copyTable(child)
	end
	return result
end

local function firstNonEmpty(...)
	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or "")
		if value ~= "" then
			return value
		end
	end
	return ""
end

local function normalizeAmount(value)
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function getValueObjectNumber(parent, childName)
	local valueObject = parent and parent:FindFirstChild(childName)
	if valueObject and valueObject:IsA("ValueBase") then
		return tonumber(valueObject.Value)
	end
	return nil
end

local function getRemoteNames()
	local remoteConfig = getConfig().Remotes
	remoteConfig = if typeof(remoteConfig) == "table" then remoteConfig else {}
	return {
		StateEventName = tostring(remoteConfig.StateEventName or DEFAULT_STATE_EVENT_NAME),
		StateRequestName = tostring(remoteConfig.StateRequestName or DEFAULT_STATE_REQUEST_NAME),
		EntryRequestName = tostring(remoteConfig.EntryRequestName or DEFAULT_ENTRY_REQUEST_NAME),
		ReturnRequestName = tostring(remoteConfig.ReturnRequestName or DEFAULT_RETURN_REQUEST_NAME),
		ActivityPingEventName = tostring(remoteConfig.ActivityPingEventName or DEFAULT_ACTIVITY_PING_EVENT_NAME),
	}
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end
	return remotes
end

local function getOrCreateRemote(parent, className, remoteName)
	local existing = parent:FindFirstChild(remoteName)
	if existing and not existing:IsA(className) then
		existing:Destroy()
		existing = nil
	end
	if not existing then
		existing = Instance.new(className)
		existing.Name = remoteName
		existing.Parent = parent
	end
	return existing
end

local function getOrCreateRemotes()
	local remotes = getOrCreateRemotesFolder()
	local names = getRemoteNames()
	stateEvent = getOrCreateRemote(remotes, "RemoteEvent", names.StateEventName)
	stateRequest = getOrCreateRemote(remotes, "RemoteFunction", names.StateRequestName)
	entryRequest = getOrCreateRemote(remotes, "RemoteFunction", names.EntryRequestName)
	returnRequest = getOrCreateRemote(remotes, "RemoteFunction", names.ReturnRequestName)
	activityPingEvent = getOrCreateRemote(remotes, "RemoteEvent", names.ActivityPingEventName)
end

local function getRuntime(player)
	local runtime = runtimeByPlayer[player]
	if runtime == nil then
		local now = os.clock()
		runtime = {
			LastActivityAt = now,
			LastActivityPingAt = 0,
			JoinedAtClock = now,
			LastRefreshAttemptAt = 0,
			NextRefreshRetryAt = 0,
			TeleportPending = false,
			TeleportPendingStartedAt = 0,
			LastAutoAttemptAt = 0,
			LastRewardSettlementAttemptAt = 0,
		}
		runtimeByPlayer[player] = runtime
	end
	return runtime
end

local function resetSessionRewardCursors(session, now)
	session.LastRewardSettledAtUnix = now
	session.AwardedChestIntervals = 0
	session.BeliRemainder = 0
	session.EarnedChestsThisSession = 0
	session.EarnedBeliThisSession = 0
end

local function sanitizeSession(session)
	session = if typeof(session) == "table" then session else {}
	session.Active = session.Active == true
	session.SessionId = if typeof(session.SessionId) == "string" then session.SessionId else ""
	session.StartedAtUnix = math.max(0, math.floor(getNumber(session.StartedAtUnix, 0)))
	session.LastAccruedAtUnix = math.max(0, math.floor(getNumber(session.LastAccruedAtUnix, 0)))
	session.ClaimedThroughUnix = math.max(0, math.floor(getNumber(session.ClaimedThroughUnix, 0)))
	session.LastRewardSettledAtUnix = math.max(0, math.floor(getNumber(session.LastRewardSettledAtUnix, 0)))
	session.AwardedChestIntervals = math.max(0, math.floor(getNumber(session.AwardedChestIntervals, 0)))
	session.BeliRemainder = math.max(0, getNumber(session.BeliRemainder, 0))
	session.EarnedChestsThisSession = math.max(0, math.floor(getNumber(session.EarnedChestsThisSession, 0)))
	session.EarnedBeliThisSession = math.max(0, math.floor(getNumber(session.EarnedBeliThisSession, 0)))
	session.RefreshCount = math.max(0, math.floor(getNumber(session.RefreshCount, 0)))
	session.PendingReturn = session.PendingReturn == true
	session.Source = if typeof(session.Source) == "string" then session.Source else ""
	session.LastClaimId = if typeof(session.LastClaimId) == "string" then session.LastClaimId else ""
	session.LastKnownPlaceId = math.max(0, math.floor(getNumber(session.LastKnownPlaceId, 0)))
	session.LastTeleportAtUnix = math.max(0, math.floor(getNumber(session.LastTeleportAtUnix, 0)))
	return session
end

local function sanitizeAfkData(afk)
	afk = if typeof(afk) == "table" then afk else {}
	afk.SchemaVersion = 1
	afk.Session = sanitizeSession(afk.Session)
	afk.Daily = if typeof(afk.Daily) == "table" then afk.Daily else {}
	afk.Daily.DayKey = if typeof(afk.Daily.DayKey) == "string" then afk.Daily.DayKey else ""
	afk.Daily.ClaimedSeconds = math.max(0, math.floor(getNumber(afk.Daily.ClaimedSeconds, 0)))
	afk.Totals = if typeof(afk.Totals) == "table" then afk.Totals else {}
	afk.Totals.ClaimedSeconds = math.max(0, math.floor(getNumber(afk.Totals.ClaimedSeconds, 0)))
	afk.Totals.Claims = math.max(0, math.floor(getNumber(afk.Totals.Claims, 0)))
	return afk
end

local function getAfkData(player)
	if dataManagerRef == nil then
		return nil, "service_not_started"
	end
	local profile = dataManagerRef:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return nil, "profile_not_ready"
	end

	profile.Data.AFK = sanitizeAfkData(profile.Data.AFK)
	return profile.Data.AFK, nil
end

local function getPlayerData(player)
	if dataManagerRef == nil then
		return nil, "service_not_started"
	end
	local profile = dataManagerRef:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return nil, "profile_not_ready"
	end
	return profile.Data, nil
end

local function persistAfkData(player, afk)
	if dataManagerRef == nil then
		return false, "service_not_started"
	end
	local ok, reason = dataManagerRef:TrySetValue(player, AFK_PATH, copyTable(sanitizeAfkData(afk)))
	return ok == true, reason
end

local function normalizeDaily(afk, now)
	local currentDay = todayUtc(now)
	local daily = afk.Daily
	if daily.DayKey ~= currentDay then
		daily.DayKey = currentDay
		daily.ClaimedSeconds = 0
	end
end

local function getRewardConfig()
	local rewards = getConfig().Rewards
	return if typeof(rewards) == "table" then rewards else {}
end

local function getAfkBeliRateMultiplier()
	return getNonNegativeNumber(getRewardConfig().BeliRateMultiplier, DEFAULT_AFK_BELI_RATE_MULTIPLIER)
end

local function getRewardSettlementSeconds()
	return getPositiveNumber(getConfig().RewardSettlementSeconds, DEFAULT_REWARD_SETTLEMENT_SECONDS)
end

local function getChestTier()
	local rewards = getRewardConfig()
	return tostring(rewards.ChestTier or DEFAULT_CHEST_TIER)
end

local function getChestSource()
	local rewards = getRewardConfig()
	return tostring(rewards.ChestSource or DEFAULT_CHEST_SOURCE)
end

local function isVipPlayer(player, dataRoot)
	local passes = player and player:FindFirstChild("Passes")
	local vipValue = passes and passes:FindFirstChild("VIP")
	if vipValue and vipValue:IsA("BoolValue") then
		return vipValue.Value == true
	end

	local savedPasses = dataRoot and dataRoot.Passes
	return typeof(savedPasses) == "table" and savedPasses.VIP == true
end

local function getChestRewardSettings(isVip)
	local rewards = getRewardConfig()
	local settings = if isVip then rewards.VIP else rewards.Standard
	settings = if typeof(settings) == "table" then settings else {}
	local intervalFallback = if isVip then DEFAULT_VIP_CHEST_INTERVAL_SECONDS else DEFAULT_STANDARD_CHEST_INTERVAL_SECONDS
	local countFallback = if isVip then DEFAULT_VIP_CHESTS_PER_INTERVAL else DEFAULT_STANDARD_CHESTS_PER_INTERVAL
	return {
		IntervalSeconds = getPositiveInteger(settings.ChestIntervalSeconds or settings.IntervalSeconds, intervalFallback),
		ChestsPerInterval = getPositiveInteger(settings.ChestsPerInterval or settings.Amount, countFallback),
	}
end

local function getDataNumber(dataRoot, path, fallback)
	local current = dataRoot
	for segment in string.gmatch(tostring(path or ""), "[^%.]+") do
		if typeof(current) ~= "table" then
			return fallback
		end
		current = current[segment]
	end
	local number = tonumber(current)
	return if number ~= nil then number else fallback
end

local function getPlayerRebirthCount(player, dataRoot)
	local leaderstats = player and player:FindFirstChild("leaderstats")
	local rebirthValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if rebirthValue and rebirthValue:IsA("ValueBase") then
		return normalizeAmount(rebirthValue.Value)
	end
	return normalizeAmount(getDataNumber(dataRoot, "leaderstats.Rebirths", 0))
end

local function getPlayerShipUpgradeLevel(player, dataRoot)
	local hiddenLeaderstats = player and player:FindFirstChild("HiddenLeaderstats")
	local plotUpgradeValue = hiddenLeaderstats and hiddenLeaderstats:FindFirstChild("PlotUpgrade")
	if plotUpgradeValue and plotUpgradeValue:IsA("ValueBase") then
		return PlotUpgradeConfig.ClampLevel(plotUpgradeValue.Value)
	end
	return PlotUpgradeConfig.ClampLevel(getDataNumber(dataRoot, "HiddenLeaderstats.PlotUpgrade", 0))
end

local function getBeliBoostMultiplier(player, dataRoot)
	local potions = player and player:FindFirstChild("Potions")
	local boostedSeconds = getValueObjectNumber(potions, "x2MoneyTime")
	if boostedSeconds == nil then
		boostedSeconds = getDataNumber(dataRoot, "Potions.x2MoneyTime", 0)
	end
	return if (tonumber(boostedSeconds) or 0) > 0 then 2 else 1
end

local function getCrewInventoryById(dataRoot)
	local inventory = dataRoot and dataRoot.CrewMemberInventory
	return if typeof(inventory) == "table" and typeof(inventory.ById) == "table" then inventory.ById else {}
end

local function getCrewInstanceData(dataRoot, instanceId)
	instanceId = tostring(instanceId or "")
	if instanceId == "" then
		return nil
	end
	local byId = getCrewInventoryById(dataRoot)
	return if typeof(byId[instanceId]) == "table" then byId[instanceId] else nil
end

local function getCrewStorageName(row, instanceData)
	return firstNonEmpty(
		instanceData and instanceData.CrewMemberId,
		instanceData and instanceData.StorageName,
		instanceData and instanceData.LegacyStorageName,
		row and row.CrewMemberId,
		row and row.CrewMemberName,
		row and row.StorageName,
		row and row.LegacyStorageName,
		row and row.Name
	)
end

local function getCrewLevel(row, instanceData, levelFieldName)
	if typeof(instanceData) == "table" then
		return CrewIncomeBalance.NormalizeLevel(instanceData.Level)
	end
	if typeof(row) == "table" then
		return CrewIncomeBalance.NormalizeLevel(row[levelFieldName] or row.Level)
	end
	return 1
end

local function getRawCrewIncome(row, instanceData)
	if typeof(instanceData) == "table" then
		local rawIncome = CrewIncomeBalance.GetRawBankIncomePerSecond(instanceData)
		if rawIncome > 0 then
			return rawIncome
		end
	end

	local storageName = getCrewStorageName(row, instanceData)
	local info = CrewCatalog.GetInfoByAnyId(storageName)
	return math.max(0, tonumber(info and info.Income) or tonumber(row and row.Income) or 0)
end

local function calculateStandIncomePerSecond(_player, dataRoot, standName, row, rebirthMultiplier, beliBoostMultiplier)
	if typeof(row) ~= "table" then
		return 0
	end
	if tostring(standName or "") == CAPTAIN_SLOT_KEY then
		return 0
	end

	local instanceId = firstNonEmpty(row.CrewMemberInstanceId, row.InstanceId, row.CrewInstanceId)
	local instanceData = getCrewInstanceData(dataRoot, instanceId)
	local storageName = getCrewStorageName(row, instanceData)
	if storageName == "" and instanceId == "" then
		return 0
	end

	local rawIncome = getRawCrewIncome(row, instanceData)
	if rawIncome <= 0 then
		return 0
	end

	local level = getCrewLevel(row, instanceData, "StandLevel")
	return rawIncome * beliBoostMultiplier * CrewIncomeBalance.GetClaimMultiplier(level, rebirthMultiplier)
end

local function calculateCaptainIncomePerSecond(player, dataRoot, rebirthMultiplier, beliBoostMultiplier)
	local ship = dataRoot and dataRoot.Ship
	local captainSlot = ship and ship.CaptainSlot
	if typeof(captainSlot) ~= "table" then
		return 0
	end

	local instanceId = firstNonEmpty(captainSlot.CrewMemberInstanceId, captainSlot.InstanceId, captainSlot.CrewInstanceId)
	local instanceData = getCrewInstanceData(dataRoot, instanceId)
	local storageName = getCrewStorageName(captainSlot, instanceData)
	if storageName == "" and instanceId == "" then
		return 0
	end

	local rawIncome = getRawCrewIncome(captainSlot, instanceData)
	if rawIncome <= 0 then
		return 0
	end

	local level = getCrewLevel(captainSlot, instanceData, "Level")
	local upgradeLevel = getPlayerShipUpgradeLevel(player, dataRoot)
	local rebirthCount = getPlayerRebirthCount(player, dataRoot)
	local captainMultiplier = PlotUpgradeConfig.GetCaptainBonusMultiplier(upgradeLevel, rebirthCount)
	return rawIncome
		* beliBoostMultiplier
		* CrewIncomeBalance.GetClaimMultiplier(level, {
			rebirthMultiplier,
			captainMultiplier,
		})
end

local function calculateShipIncomePerSecond(player, dataRoot)
	if typeof(dataRoot) ~= "table" then
		return 0
	end

	local rebirthMultiplier = RebirthConfig.GetShipIncomeMultiplier(getPlayerRebirthCount(player, dataRoot))
	local beliBoostMultiplier = getBeliBoostMultiplier(player, dataRoot)
	local total = 0
	local crewMemberIncome = dataRoot.CrewMemberIncome
	if typeof(crewMemberIncome) == "table" then
		for standName, row in pairs(crewMemberIncome) do
			total += calculateStandIncomePerSecond(player, dataRoot, standName, row, rebirthMultiplier, beliBoostMultiplier)
		end
	end
	total += calculateCaptainIncomePerSecond(player, dataRoot, rebirthMultiplier, beliBoostMultiplier)
	return math.max(0, total)
end

local function getSessionElapsedSeconds(session, now)
	local startedAt = math.max(0, math.floor(getNumber(session and session.StartedAtUnix, 0)))
	if startedAt <= 0 then
		return 0
	end

	if session.Active == true or session.PendingReturn == true then
		return math.max(0, math.floor(now - startedAt))
	end

	local endedAt = math.max(startedAt, math.floor(getNumber(session.LastAccruedAtUnix, startedAt)))
	return math.max(0, math.floor(endedAt - startedAt))
end

local function buildRewardSummary(player, afk, now)
	local session = afk and afk.Session or {}
	local elapsedSeconds = getSessionElapsedSeconds(session, now)
	local dataRoot = getPlayerData(player)
	dataRoot = if typeof(dataRoot) == "table" then dataRoot else {}
	local isVip = isVipPlayer(player, dataRoot)
	local chestSettings = getChestRewardSettings(isVip)
	local completedChestIntervals = math.max(0, math.floor(elapsedSeconds / chestSettings.IntervalSeconds))
	local awardedChestIntervals = math.max(0, math.floor(getNumber(session.AwardedChestIntervals, 0)))
	local pendingChestIntervals = math.max(0, completedChestIntervals - awardedChestIntervals)
	local chestsEarnedThisSession = math.max(0, math.floor(getNumber(session.EarnedChestsThisSession, 0)))
		+ pendingChestIntervals * chestSettings.ChestsPerInterval
	local chestProgressSeconds = elapsedSeconds % chestSettings.IntervalSeconds
	local shipIncomePerSecond = calculateShipIncomePerSecond(player, dataRoot)
	local afkIncomeMultiplier = getAfkBeliRateMultiplier()
	local afkIncomePerSecond = shipIncomePerSecond * afkIncomeMultiplier
	local secondsUntilNextChest = if pendingChestIntervals > 0
		then 0
		else math.max(0, chestSettings.IntervalSeconds - chestProgressSeconds)
	local settledAt = math.max(
		math.max(0, math.floor(getNumber(session.StartedAtUnix, 0))),
		math.floor(getNumber(session.LastRewardSettledAtUnix, 0))
	)
	local settleNow = if session.Active == true or session.PendingReturn == true
		then now
		else math.max(settledAt, math.floor(getNumber(session.LastAccruedAtUnix, settledAt)))
	local pendingBeli = math.floor(
		math.max(0, settleNow - settledAt) * afkIncomePerSecond
			+ math.max(0, getNumber(session.BeliRemainder, 0))
	)
	local beliEarnedThisSession = math.max(0, math.floor(getNumber(session.EarnedBeliThisSession, 0))) + pendingBeli

	return {
		RewardSeconds = elapsedSeconds,
		Beli = beliEarnedThisSession,
		ShipIncomePerSecond = shipIncomePerSecond,
		AFKIncomeMultiplier = afkIncomeMultiplier,
		AFKIncomePerSecond = afkIncomePerSecond,
		IsVIP = isVip,
		ChestTier = getChestTier(),
		ChestSource = getChestSource(),
		ChestIntervalSeconds = chestSettings.IntervalSeconds,
		ChestsPerInterval = chestSettings.ChestsPerInterval,
		ClaimableChests = chestsEarnedThisSession,
		ChestProgressSeconds = chestProgressSeconds,
		NextChestInSeconds = secondsUntilNextChest,
		SecondsUntilNextChest = secondsUntilNextChest,
		ChestsEarnedThisSession = chestsEarnedThisSession,
		BeliEarnedThisSession = beliEarnedThisSession,
		AutoSaveEnabled = true,
	}
end

local function calculateClaim(player, afk, now)
	normalizeDaily(afk, now)
	local session = afk.Session
	if session.Active ~= true and session.PendingReturn ~= true then
		local summary = buildRewardSummary(player, afk, now)
		return {
			ElapsedSeconds = summary.RewardSeconds,
			ClaimableSeconds = 0,
			RewardSeconds = summary.RewardSeconds,
			Summary = summary,
		}
	end

	local elapsed = getSessionElapsedSeconds(session, now)

	return {
		ElapsedSeconds = elapsed,
		ClaimableSeconds = elapsed,
		RewardSeconds = elapsed,
		Summary = buildRewardSummary(player, afk, now),
	}
end

local function hasGrantRewards(summary)
	if typeof(summary) ~= "table" then
		return false
	end
	if normalizeAmount(summary.Beli) > 0 then
		return true
	end
	if normalizeAmount(summary.ClaimableChests) > 0 then
		return true
	end
	return false
end

local function hasRewards(summary)
	if hasGrantRewards(summary) then
		return true
	end
	if typeof(summary) ~= "table" then
		return false
	end
	if normalizeAmount(summary.BeliEarnedThisSession) > 0 then
		return true
	end
	if normalizeAmount(summary.ChestsEarnedThisSession) > 0 then
		return true
	end
	return false
end

local function tryAddValue(player, path, amount)
	if amount == nil or amount == 0 then
		return true
	end
	local ok, reason = dataManagerRef:TryAddValue(player, path, amount)
	if ok ~= true then
		warn(string.format("[AFKTeleportService] Grant failed player=%s path=%s amount=%s reason=%s",
			player and player.Name or "<unknown>",
			tostring(path),
			tostring(amount),
			tostring(reason)
		))
		return false, reason
	end
	return true
end

local function ensureUnopenedChests(unopenedChests)
	unopenedChests = if typeof(unopenedChests) == "table" then unopenedChests else {}
	unopenedChests.ById = if typeof(unopenedChests.ById) == "table" then unopenedChests.ById else {}
	unopenedChests.Order = if typeof(unopenedChests.Order) == "table" then unopenedChests.Order else {}
	unopenedChests.Stacks = if typeof(unopenedChests.Stacks) == "table" then unopenedChests.Stacks else {}
	for _, tierName in ipairs(ChestRewards.StandardTierOrder or {}) do
		unopenedChests.Stacks[tierName] = normalizeAmount(unopenedChests.Stacks[tierName])
	end
	unopenedChests.NextChestId = math.max(1, math.floor(tonumber(unopenedChests.NextChestId) or 1))
	unopenedChests.StackSchemaVersion = 1
	return unopenedChests
end

local function grantAfkChests(player, summary)
	local chestCount = normalizeAmount(summary and summary.ClaimableChests)
	if chestCount <= 0 then
		return true
	end

	local profile = dataManagerRef:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return false, "profile_not_ready"
	end

	local chestData = ChestUtils.BuildChestData({
		ChestKind = ChestRewards.ChestKinds.Standard,
		Tier = summary.ChestTier or getChestTier(),
		Source = summary.ChestSource or getChestSource(),
	})
	local stackKey = ChestUtils.GetStackKey(chestData)
	if stackKey == nil then
		return false, "invalid_chest_tier"
	end

	local unopenedChests = ensureUnopenedChests(copyTable(profile.Data.UnopenedChests))
	unopenedChests.Stacks[stackKey] = normalizeAmount(unopenedChests.Stacks[stackKey]) + chestCount
	unopenedChests.NextChestId = math.max(1, math.floor(tonumber(unopenedChests.NextChestId) or 1)) + chestCount

	local ok, reason = dataManagerRef:TrySetValue(player, "UnopenedChests", unopenedChests)
	if ok ~= true then
		warn(string.format("[AFKTeleportService] Chest grant failed player=%s tier=%s amount=%s reason=%s",
			player and player.Name or "<unknown>",
			tostring(stackKey),
			tostring(chestCount),
			tostring(reason)
		))
		return false, reason
	end

	return true
end

local function grantRewards(player, summary)
	if hasGrantRewards(summary) ~= true then
		return true
	end

	local ok, reason = tryAddValue(player, CurrencyUtil.getPrimaryPath(), summary.Beli)
	if not ok then
		return false, reason
	end
	ok, reason = tryAddValue(player, CurrencyUtil.getTotalPath(), summary.Beli)
	if not ok then
		return false, reason
	end

	ok, reason = grantAfkChests(player, summary)
	if not ok then
		return false, reason
	end

	return true
end

local function buildStatePayload(player, message)
	local afk, reason = getAfkData(player)
	local now = os.time()
	local runtime = getRuntime(player)
	local claim = if afk ~= nil
		then calculateClaim(player, afk, now)
		else {
			ElapsedSeconds = 0,
			ClaimableSeconds = 0,
			RewardSeconds = 0,
			Summary = buildRewardSummary(player, nil, now),
		}
	local session = afk and afk.Session or {}
	local role = if isAfkPlace() then "AFKPlace" elseif isMainPlace() then "MainPlace" else "Unknown"

	return {
		Enabled = getConfig().Enabled ~= false,
		Role = role,
		PlaceId = game.PlaceId,
		MainPlaceId = getMainPlaceId(),
		AFKPlaceId = getAfkPlaceId(),
		AFKPlaceConfigured = getAfkPlaceId() > 0,
		MainPlaceConfigured = getMainPlaceId() > 0,
		DataReady = afk ~= nil,
		DataReason = reason,
		SessionActive = session.Active == true,
		PendingReturn = session.PendingReturn == true,
		SessionId = tostring(session.SessionId or ""),
		StartedAtUnix = math.max(0, math.floor(getNumber(session.StartedAtUnix, 0))),
		LastAccruedAtUnix = math.max(0, math.floor(getNumber(session.LastAccruedAtUnix, 0))),
		ClaimedThroughUnix = math.max(0, math.floor(getNumber(session.ClaimedThroughUnix, 0))),
		RefreshCount = math.max(0, math.floor(getNumber(session.RefreshCount, 0))),
		NowUnix = now,
		ElapsedSeconds = claim.ElapsedSeconds,
		ClaimableSeconds = claim.ClaimableSeconds,
		RewardSeconds = claim.RewardSeconds,
		Rewards = claim.Summary,
		RefreshSeconds = getPositiveInteger(getConfig().RefreshSeconds, DEFAULT_REFRESH_SECONDS),
		NextRefreshInSeconds = math.max(0, math.floor((runtime.JoinedAtClock + getPositiveInteger(getConfig().RefreshSeconds, DEFAULT_REFRESH_SECONDS)) - os.clock())),
		TeleportPending = runtime.TeleportPending == true,
		Message = message,
	}
end

local function fireState(player, message)
	if stateEvent ~= nil and player.Parent == Players then
		stateEvent:FireClient(player, "State", buildStatePayload(player, message))
	end
end

local function fireClaimed(player, claim, message)
	if stateEvent ~= nil and player.Parent == Players then
		stateEvent:FireClient(player, "Claimed", {
			Message = message,
			Claim = claim,
			State = buildStatePayload(player, message),
		})
	end
end

local function buildSettlementGrantSummary(player, afk, now)
	local session = afk and afk.Session or {}
	if session.Active ~= true and session.PendingReturn ~= true then
		return nil
	end

	local startedAt = math.max(0, math.floor(getNumber(session.StartedAtUnix, 0)))
	if startedAt <= 0 then
		return nil
	end

	local dataRoot = getPlayerData(player)
	dataRoot = if typeof(dataRoot) == "table" then dataRoot else {}
	local isVip = isVipPlayer(player, dataRoot)
	local chestSettings = getChestRewardSettings(isVip)
	local elapsedSeconds = math.max(0, math.floor(now - startedAt))
	local completedChestIntervals = math.max(0, math.floor(elapsedSeconds / chestSettings.IntervalSeconds))
	local awardedChestIntervals = math.max(0, math.floor(getNumber(session.AwardedChestIntervals, 0)))
	local intervalsToAward = math.max(0, completedChestIntervals - awardedChestIntervals)
	local chestsToAward = intervalsToAward * chestSettings.ChestsPerInterval

	local settledAt = math.max(startedAt, math.floor(getNumber(session.LastRewardSettledAtUnix, startedAt)))
	settledAt = math.min(settledAt, now)
	local secondsToSettle = math.max(0, math.floor(now - settledAt))
	local shipIncomePerSecond = calculateShipIncomePerSecond(player, dataRoot)
	local afkIncomePerSecond = shipIncomePerSecond * getAfkBeliRateMultiplier()
	local rawBeli = secondsToSettle * afkIncomePerSecond + math.max(0, getNumber(session.BeliRemainder, 0))
	local beliToAward = math.max(0, math.floor(rawBeli))

	return {
		Summary = {
			Beli = beliToAward,
			ClaimableChests = chestsToAward,
			ChestTier = getChestTier(),
			ChestSource = getChestSource(),
		},
		IntervalsToAward = intervalsToAward,
		BeliRemainder = math.max(0, rawBeli - beliToAward),
		SecondsToSettle = secondsToSettle,
	}
end

local function settleAfkRewardsUnlocked(player, source)
	local afk, reason = getAfkData(player)
	if afk == nil then
		return false, reason, nil
	end

	local now = os.time()
	normalizeDaily(afk, now)
	local settlement = buildSettlementGrantSummary(player, afk, now)
	if settlement == nil then
		return true, "no_active_session", calculateClaim(player, afk, now)
	end

	local summary = settlement.Summary
	local grantOk, grantReason = grantRewards(player, summary)
	if grantOk ~= true then
		return false, grantReason, calculateClaim(player, afk, now)
	end

	local session = afk.Session
	session.LastRewardSettledAtUnix = now
	session.AwardedChestIntervals = math.max(0, math.floor(getNumber(session.AwardedChestIntervals, 0)))
		+ settlement.IntervalsToAward
	session.BeliRemainder = settlement.BeliRemainder
	session.EarnedChestsThisSession = math.max(0, math.floor(getNumber(session.EarnedChestsThisSession, 0)))
		+ normalizeAmount(summary.ClaimableChests)
	session.EarnedBeliThisSession = math.max(0, math.floor(getNumber(session.EarnedBeliThisSession, 0)))
		+ normalizeAmount(summary.Beli)
	session.LastAccruedAtUnix = now
	session.LastKnownPlaceId = game.PlaceId

	local persistOk, persistReason = persistAfkData(player, afk)
	if persistOk ~= true then
		return false, persistReason, calculateClaim(player, afk, now)
	end

	local claim = calculateClaim(player, afk, now)
	if hasGrantRewards(summary) then
		fireState(player, source == "chest_interval" and "Gold Chest saved." or nil)
	end
	return true, source or "settled", claim
end

local function settleAfkRewards(player, source)
	local runtime = getRuntime(player)
	if runtime.SettlementPending == true then
		return false, "settlement_pending", nil
	end

	runtime.SettlementPending = true
	local ok, success, reason, claim = xpcall(function()
		return settleAfkRewardsUnlocked(player, source)
	end, debug.traceback)
	runtime.SettlementPending = false

	if ok ~= true then
		warn(string.format("[AFKTeleportService] Settlement failed player=%s error=%s",
			player and player.Name or "<unknown>",
			tostring(success)
		))
		return false, "settlement_failed", nil
	end

	return success, reason, claim
end

local function hasChestIntervalToSettle(player, afk, now)
	local session = afk and afk.Session or {}
	if session.Active ~= true and session.PendingReturn ~= true then
		return false
	end

	local startedAt = math.max(0, math.floor(getNumber(session.StartedAtUnix, 0)))
	if startedAt <= 0 then
		return false
	end

	local dataRoot = getPlayerData(player)
	dataRoot = if typeof(dataRoot) == "table" then dataRoot else {}
	local chestSettings = getChestRewardSettings(isVipPlayer(player, dataRoot))
	local completedChestIntervals = math.max(0, math.floor(math.max(0, now - startedAt) / chestSettings.IntervalSeconds))
	local awardedChestIntervals = math.max(0, math.floor(getNumber(session.AwardedChestIntervals, 0)))
	return completedChestIntervals > awardedChestIntervals
end

local function isPlayerAlive(player)
	local character = player.Character
	if character == nil or character.Parent == nil then
		return false, "character_not_ready"
	end

	if character:GetAttribute("HoroProjectionGhost") == true or character:GetAttribute("HoroProjectionBody") == true then
		return false, "horo_projection_character"
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil then
		return false, "character_not_ready"
	end
	if humanoid.Health <= 0 then
		return false, "character_dead"
	end
	return true
end

local function getSpecialStateReason(player)
	for _, attributeName in ipairs(SPECIAL_STATE_ATTRIBUTES) do
		local value = player:GetAttribute(attributeName)
		if value ~= nil and value ~= false and value ~= "" then
			return string.lower(attributeName)
		end
	end

	local now = os.clock()
	for _, attributeName in ipairs(TIMED_SPECIAL_STATE_ATTRIBUTES) do
		local value = player:GetAttribute(attributeName)
		if typeof(value) == "number" and value > now then
			return string.lower(attributeName)
		elseif value ~= nil and attributeName:find("Until") == nil then
			return string.lower(attributeName)
		end
	end

	return nil
end

local function getVerticalSliceService()
	if verticalSliceService ~= nil then
		return verticalSliceService
	end

	local ok, result = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
	end)
	if ok and typeof(result) == "table" then
		verticalSliceService = result
	end
	return verticalSliceService
end

local function cleanupRunState(player)
	local service = getVerticalSliceService()
	if service == nil or typeof(service.GetState) ~= "function" then
		return true
	end

	local state = service.GetState(player)
	local run = state and state.Run
	if typeof(run) ~= "table" then
		return true
	end

	local hasActiveRun = run.InRun == true or run.SpawnedReward ~= nil or run.CarriedReward ~= nil
	local carrySlots = run.CarrySlots
	if typeof(carrySlots) == "table" then
		for _, slot in ipairs(carrySlots) do
			if typeof(slot) == "table" and slot.Empty ~= true then
				hasActiveRun = true
				break
			end
		end
	end

	if hasActiveRun ~= true then
		return true
	end

	if typeof(service.DropAllCarriedRewards) == "function" then
		pcall(function()
			service.DropAllCarriedRewards(player, {
				Reason = "AFKTeleport",
				IgnoreProtection = true,
			})
		end)
	end
	if typeof(service.ClearAllCarryItems) == "function" then
		pcall(function()
			service.ClearAllCarryItems(player, "AFKTeleport")
		end)
	end
	if typeof(service.FailRun) == "function" then
		pcall(function()
			service.FailRun(player, "AFK teleport started. Unextracted corridor rewards were cleared.")
		end)
	end

	return true
end

local function validateTeleportAllowed(player, source)
	if getConfig().Enabled == false then
		return false, "AFK teleport is disabled."
	end
	if source == "Manual" and getConfig().ManualEnabled == false then
		return false, "Manual AFK is disabled."
	end
	if source == "Auto" and getConfig().AutoEnabled == false then
		return false, "Auto AFK is disabled."
	end
	if isMainPlace() ~= true then
		return false, "AFK entry is only available from the main place."
	end
	if getAfkPlaceId() <= 0 then
		return false, "AFK lobby place is not configured yet."
	end
	if dataManagerRef == nil or dataManagerRef:IsReady(player) ~= true then
		return false, "Your profile is still loading. Try again in a moment."
	end

	local alive, aliveReason = isPlayerAlive(player)
	if alive ~= true then
		return false, "Cannot enter AFK while your character is unavailable: " .. tostring(aliveReason)
	end

	local specialReason = getSpecialStateReason(player)
	if specialReason ~= nil then
		return false, "Wait for your current ability state to finish before entering AFK."
	end

	return true
end

local function beginSession(player, source)
	local afk, reason = getAfkData(player)
	if afk == nil then
		return false, reason
	end

	local now = os.time()
	normalizeDaily(afk, now)
	local session = afk.Session
	if session.Active ~= true or session.SessionId == "" then
		session.SessionId = HttpService:GenerateGUID(false)
		session.StartedAtUnix = now
		session.ClaimedThroughUnix = now
		resetSessionRewardCursors(session, now)
		session.RefreshCount = 0
	elseif session.LastRewardSettledAtUnix <= 0 then
		session.LastRewardSettledAtUnix = math.max(session.StartedAtUnix, session.ClaimedThroughUnix)
	end
	session.Active = true
	session.PendingReturn = false
	session.LastAccruedAtUnix = now
	session.LastKnownPlaceId = game.PlaceId
	session.LastTeleportAtUnix = now
	session.Source = tostring(source or "Manual")

	return persistAfkData(player, afk)
end

local function updateSessionBeforeTeleport(player, options)
	local afk, reason = getAfkData(player)
	if afk == nil then
		return false, reason
	end
	local now = os.time()
	normalizeDaily(afk, now)
	local session = afk.Session
	session.LastAccruedAtUnix = now
	session.LastKnownPlaceId = game.PlaceId
	session.LastTeleportAtUnix = now
	if options and options.PendingReturn ~= nil then
		session.PendingReturn = options.PendingReturn == true
	end
	if options and options.IncrementRefresh == true then
		session.RefreshCount = math.max(0, math.floor(getNumber(session.RefreshCount, 0))) + 1
	end
	return persistAfkData(player, afk)
end

local function teleportPlayer(player, placeId, teleportData, reason)
	local runtime = getRuntime(player)
	if runtime.TeleportPending == true and os.clock() - runtime.TeleportPendingStartedAt < TELEPORT_PENDING_TIMEOUT_SECONDS then
		return false, "teleport_already_pending"
	end
	if placeId <= 0 then
		return false, "target_place_not_configured"
	end

	runtime.TeleportPending = true
	runtime.TeleportPendingStartedAt = os.clock()
	fireState(player, "Teleporting...")

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions:SetTeleportData(teleportData or {})
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(placeId, { player }, teleportOptions)
	end)
	if not ok then
		runtime.TeleportPending = false
		warn(string.format("[AFKTeleportService] Teleport failed player=%s reason=%s error=%s",
			player and player.Name or "<unknown>",
			tostring(reason),
			tostring(err)
		))
		fireState(player, "Teleport failed. Retrying is safe.")
		return false, tostring(err)
	end

	return true
end

local function startAfkTeleport(player, source)
	local runtime = getRuntime(player)
	local allowed, message = validateTeleportAllowed(player, source)
	if allowed ~= true then
		fireState(player, message)
		return {
			ok = false,
			message = message,
		}
	end

	cleanupRunState(player)

	local ok, reason = beginSession(player, source)
	if ok ~= true then
		return {
			ok = false,
			message = "Unable to start AFK session: " .. tostring(reason),
		}
	end

	local afk = getAfkData(player)
	local session = afk and afk.Session or {}
	local teleported, teleportReason = teleportPlayer(player, getAfkPlaceId(), {
		Kind = "EnterAFK",
		SessionId = tostring(session.SessionId or ""),
		Source = tostring(source or "Manual"),
		FromPlaceId = game.PlaceId,
		SentAtUnix = os.time(),
	}, "enter_afk")

	if teleported ~= true then
		runtime.TeleportPending = false
		return {
			ok = false,
			message = "AFK teleport failed: " .. tostring(teleportReason),
			state = buildStatePayload(player),
		}
	end

	return {
		ok = true,
		message = "Traveling to the AFK lobby...",
		state = buildStatePayload(player, "Traveling to the AFK lobby..."),
	}
end

local function claimAfkRewardsUnlocked(player, source)
	local settleOk, settleReason = settleAfkRewards(player, tostring(source or "claim") .. "_final")
	if settleOk ~= true then
		return false, settleReason, nil
	end

	local afk, reason = getAfkData(player)
	if afk == nil then
		return false, reason, nil
	end

	local now = os.time()
	normalizeDaily(afk, now)
	local session = afk.Session
	if session.Active ~= true and session.PendingReturn ~= true then
		return true, "no_active_session", calculateClaim(player, afk, now)
	end

	local claim = calculateClaim(player, afk, now)
	local summary = claim.Summary

	session.Active = false
	session.PendingReturn = false
	session.LastAccruedAtUnix = now
	session.ClaimedThroughUnix = now
	session.LastRewardSettledAtUnix = now
	session.LastKnownPlaceId = game.PlaceId
	session.LastClaimId = tostring(session.SessionId or "") .. ":" .. tostring(now)

	if claim.ElapsedSeconds > 0 then
		afk.Totals.ClaimedSeconds = math.max(0, math.floor(getNumber(afk.Totals.ClaimedSeconds, 0))) + claim.ElapsedSeconds
		afk.Totals.Claims = math.max(0, math.floor(getNumber(afk.Totals.Claims, 0))) + 1
	end

	local persistOk, persistReason = persistAfkData(player, afk)
	if persistOk ~= true then
		return false, persistReason, claim
	end

	local message = if hasRewards(summary)
		then "AFK rewards saved."
		else "AFK session ended. No AFK rewards accrued."
	fireClaimed(player, claim, message)
	fireState(player, message)
	return true, source or "claimed", claim
end

local function claimAfkRewards(player, source)
	local runtime = getRuntime(player)
	if runtime.ClaimPending == true then
		return false, "claim_pending", nil
	end

	runtime.ClaimPending = true
	local ok, success, reason, claim = xpcall(function()
		return claimAfkRewardsUnlocked(player, source)
	end, debug.traceback)
	runtime.ClaimPending = false

	if ok ~= true then
		warn(string.format("[AFKTeleportService] Claim failed player=%s error=%s",
			player and player.Name or "<unknown>",
			tostring(success)
		))
		return false, "claim_failed", nil
	end

	return success, reason, claim
end

local function handleStateRequest(player)
	if not RemoteGuard.Check(player, getRemoteNames().StateRequestName, {}, {
		Cooldown = 0.5,
	}) then
		return buildStatePayload(player, "Request rejected.")
	end
	return buildStatePayload(player)
end

local function handleEntryRequest(player)
	if not RemoteGuard.Check(player, getRemoteNames().EntryRequestName, {}, {
		Cooldown = 2,
	}) then
		return {
			ok = false,
			message = "Please wait a moment before trying again.",
		}
	end
	return startAfkTeleport(player, "Manual")
end

local function handleActivityPing(player)
	if not RemoteGuard.Check(player, getRemoteNames().ActivityPingEventName, {}, {
		Cooldown = getPositiveNumber(getConfig().ActivityPingCooldownSeconds, DEFAULT_ACTIVITY_PING_COOLDOWN_SECONDS),
	}) then
		return
	end

	local runtime = getRuntime(player)
	local now = os.clock()
	runtime.LastActivityAt = now
	runtime.LastActivityPingAt = now
end

local function handleReturnRequest(player)
	if not RemoteGuard.Check(player, getRemoteNames().ReturnRequestName, {}, {
		Cooldown = 2,
	}) then
		return {
			ok = false,
			message = "Please wait a moment before trying again.",
		}
	end
	if isAfkPlace() ~= true then
		local ok, reason, claim = claimAfkRewards(player, "main_return_request")
		return {
			ok = ok == true,
			message = if ok then "AFK rewards saved." else "Unable to save AFK rewards: " .. tostring(reason),
			claim = claim,
			state = buildStatePayload(player),
		}
	end

	local mainPlaceId = getMainPlaceId()
	if mainPlaceId <= 0 then
		return {
			ok = false,
			message = "Main place is not configured yet.",
			state = buildStatePayload(player),
		}
	end

	local settled, settleReason = settleAfkRewards(player, "return")
	if settled ~= true then
		return {
			ok = false,
			message = "Unable to save AFK rewards: " .. tostring(settleReason),
			state = buildStatePayload(player),
		}
	end

	local persisted, persistReason = updateSessionBeforeTeleport(player, {
		PendingReturn = true,
	})
	if persisted ~= true then
		return {
			ok = false,
			message = "Unable to prepare AFK return: " .. tostring(persistReason),
			state = buildStatePayload(player),
		}
	end

	local afk = getAfkData(player)
	local session = afk and afk.Session or {}
	local teleported, teleportReason = teleportPlayer(player, mainPlaceId, {
		Kind = "ReturnFromAFK",
		SessionId = tostring(session.SessionId or ""),
		FromPlaceId = game.PlaceId,
		SentAtUnix = os.time(),
	}, "return_from_afk")

	if teleported ~= true then
		return {
			ok = false,
			message = "Return teleport failed: " .. tostring(teleportReason),
			state = buildStatePayload(player),
		}
	end

	return {
		ok = true,
		message = "Leaving AFK lobby...",
		state = buildStatePayload(player, "Leaving AFK lobby..."),
	}
end

local function initializeAfkPlacePlayer(player)
	if dataManagerRef == nil or dataManagerRef:WaitUntilReady(player, 30) ~= true then
		return
	end

	local afk, reason = getAfkData(player)
	if afk == nil then
		warn("[AFKTeleportService] AFK place profile unavailable:", player.Name, reason)
		return
	end

	local now = os.time()
	normalizeDaily(afk, now)
	local session = afk.Session
	if session.Active ~= true then
		session.Active = true
		session.SessionId = if session.SessionId ~= "" then session.SessionId else HttpService:GenerateGUID(false)
		session.StartedAtUnix = now
		session.ClaimedThroughUnix = now
		resetSessionRewardCursors(session, now)
		session.RefreshCount = 0
		session.Source = "DirectAFKPlaceJoin"
	elseif session.LastRewardSettledAtUnix <= 0 then
		session.LastRewardSettledAtUnix = math.max(session.StartedAtUnix, session.ClaimedThroughUnix)
	end
	session.PendingReturn = false
	session.LastAccruedAtUnix = now
	session.LastKnownPlaceId = game.PlaceId
	persistAfkData(player, afk)
	fireState(player, "AFK session active.")
end

local function initializeMainPlacePlayer(player)
	getRuntime(player).LastActivityAt = os.clock()
	if dataManagerRef == nil or dataManagerRef:WaitUntilReady(player, 30) ~= true then
		return
	end

	local afk = getAfkData(player)
	local session = afk and afk.Session or nil
	if session and (session.Active == true or session.PendingReturn == true) then
		claimAfkRewards(player, "main_join")
	else
		fireState(player)
	end
end

local function onPlayerAdded(player)
	getRuntime(player)
	task.spawn(function()
		if isAfkPlace() then
			initializeAfkPlacePlayer(player)
		else
			initializeMainPlacePlayer(player)
		end
	end)
end

local function onPlayerRemoving(player)
	if dataManagerRef ~= nil and dataManagerRef:IsReady(player) == true then
		settleAfkRewards(player, "player_removing")
		local afk = getAfkData(player)
		if afk ~= nil and afk.Session.Active == true then
			afk.Session.LastAccruedAtUnix = os.time()
			afk.Session.LastKnownPlaceId = game.PlaceId
			persistAfkData(player, afk)
		end
	end
	runtimeByPlayer[player] = nil
end

local function runMainLoop()
	task.spawn(function()
		while started and isMainPlace() do
			local config = getConfig()
			local scanInterval = getPositiveNumber(config.ScanIntervalSeconds, DEFAULT_SCAN_INTERVAL_SECONDS)
			if config.Enabled ~= false and config.AutoEnabled ~= false and getAfkPlaceId() > 0 then
				local now = os.clock()
				local inactivitySeconds = getPositiveNumber(config.InactivitySeconds, DEFAULT_INACTIVITY_SECONDS)
				for _, player in ipairs(Players:GetPlayers()) do
					local runtime = getRuntime(player)
					if runtime.TeleportPending == true and now - runtime.TeleportPendingStartedAt > TELEPORT_PENDING_TIMEOUT_SECONDS then
						runtime.TeleportPending = false
					end
					if runtime.TeleportPending ~= true and now - runtime.LastActivityAt >= inactivitySeconds then
						runtime.LastAutoAttemptAt = now
						task.spawn(function()
							startAfkTeleport(player, "Auto")
						end)
					end
				end
			end
			task.wait(scanInterval)
		end
	end)
end

local function runAfkRefreshLoop()
	task.spawn(function()
		while started and isAfkPlace() do
			local config = getConfig()
			local refreshSeconds = getPositiveNumber(config.RefreshSeconds, DEFAULT_REFRESH_SECONDS)
			local retrySeconds = getPositiveNumber(config.RefreshRetrySeconds, DEFAULT_REFRESH_RETRY_SECONDS)
			local now = os.clock()
			local nowUnix = os.time()
			for _, player in ipairs(Players:GetPlayers()) do
				local runtime = getRuntime(player)
				if runtime.TeleportPending == true and now - runtime.TeleportPendingStartedAt > TELEPORT_PENDING_TIMEOUT_SECONDS then
					runtime.TeleportPending = false
					runtime.NextRefreshRetryAt = now + retrySeconds
				end

				local afk = getAfkData(player)
				local chestDue = afk ~= nil and hasChestIntervalToSettle(player, afk, nowUnix)
				local settlementDue = now - runtime.LastRewardSettlementAttemptAt >= getRewardSettlementSeconds()
				if runtime.TeleportPending ~= true and (settlementDue or chestDue) then
					runtime.LastRewardSettlementAttemptAt = now
					settleAfkRewards(player, if chestDue then "chest_interval" else "interval")
				end

				local due = now - runtime.JoinedAtClock >= refreshSeconds
				if runtime.TeleportPending ~= true and due and now >= runtime.NextRefreshRetryAt then
					settleAfkRewards(player, "refresh")
					local persisted = updateSessionBeforeTeleport(player, {
						PendingReturn = false,
						IncrementRefresh = true,
					})
					if persisted == true then
						local refreshAfk = getAfkData(player)
						local session = refreshAfk and refreshAfk.Session or {}
						local teleported = teleportPlayer(player, getAfkPlaceId(), {
							Kind = "RefreshAFK",
							SessionId = tostring(session.SessionId or ""),
							RefreshCount = math.max(0, math.floor(getNumber(session.RefreshCount, 0))),
							FromPlaceId = game.PlaceId,
							SentAtUnix = os.time(),
						}, "refresh_afk")
						if teleported ~= true then
							runtime.NextRefreshRetryAt = now + retrySeconds
						end
					else
						runtime.NextRefreshRetryAt = now + retrySeconds
					end
				end
			end
			task.wait(5)
		end
	end)
end

function AFKTeleportService.Start(dataManager)
	if started then
		return
	end

	started = true
	dataManagerRef = dataManager
	getOrCreateRemotes()

	stateRequest.OnServerInvoke = handleStateRequest
	entryRequest.OnServerInvoke = handleEntryRequest
	returnRequest.OnServerInvoke = handleReturnRequest
	activityPingEvent.OnServerEvent:Connect(handleActivityPing)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	if isAfkPlace() then
		runAfkRefreshLoop()
	else
		runMainLoop()
	end
end

return AFKTeleportService
