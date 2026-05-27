local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local Config = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig")
)
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local RemoteGuard = require(ServerScriptService.Modules:WaitForChild("RemoteGuard"))
local ProtectionVisuals = require(ServerScriptService.Modules:WaitForChild("PremiumCrewStealProtectionVisuals"))

local RaidShieldService = {}

local SHIELD_CONFIG = Config.RaidShield or {}
local REMOTE_CONFIG = SHIELD_CONFIG.Remotes or {}
local ATTRIBUTES = SHIELD_CONFIG.Attributes or {}

local DATA_PATH = tostring(SHIELD_CONFIG.DataPath or "RaidShield")
local LEGACY_MANUAL_PATH = tostring(SHIELD_CONFIG.LegacyManualEnabledPath or "Settings.PremiumStealProtectionEnabled")
local NEW_PLAYER_GRANT_ID = tostring(SHIELD_CONFIG.NewPlayerGrantId or "new_player")
local NEW_PLAYER_SOURCE = tostring(SHIELD_CONFIG.NewPlayerSource or "new_player")
local NEW_PLAYER_DURATION_SECONDS = math.max(0, math.floor(tonumber(SHIELD_CONFIG.NewPlayerDurationSeconds) or 28800))
local RAID_SUPPRESSION_SECONDS = math.max(0, math.floor(tonumber(SHIELD_CONFIG.SuppressionSeconds) or 300))
local SCHEMA_VERSION = math.max(1, math.floor(tonumber(SHIELD_CONFIG.SchemaVersion) or 1))

local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local started = false
local stateRemote = nil
local setEnabledRemote = nil
local playerConnections = {}
local refreshTokens = {}

local function now()
	return os.time()
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[key] = cloneValue(child)
	end
	return result
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes:IsA("Folder") then
		return remotes
	end
	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemoteEvent(parent, remoteName)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = parent
	end
	return remote
end

local function getOrCreateRemoteFunction(parent, remoteName)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteFunction") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = remoteName
		remote.Parent = parent
	end
	return remote
end

local function ensureRemotes()
	if stateRemote and setEnabledRemote then
		return stateRemote, setEnabledRemote
	end

	local remotes = getOrCreateRemotesFolder()
	stateRemote = getOrCreateRemoteEvent(remotes, tostring(REMOTE_CONFIG.StateName or "RaidShieldState"))
	setEnabledRemote = getOrCreateRemoteFunction(remotes, tostring(REMOTE_CONFIG.SetEnabledName or "RaidShieldSetEnabled"))
	return stateRemote, setEnabledRemote
end

local function formatDuration(seconds)
	seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
	local hours = math.floor(seconds / 3600)
	local minutes = math.floor((seconds % 3600) / 60)
	local secs = seconds % 60
	if hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, secs)
	end
	return string.format("%ds", secs)
end

local function defaultData()
	return {
		SchemaVersion = SCHEMA_VERSION,
		Enabled = true,
		SuppressionUntil = 0,
		NewPlayerGrantSeeded = false,
		LastRaidPenaltyReceiptId = "",
		LastRaidPenaltyAt = 0,
		LastRaidPenaltyReason = "",
		Grants = {},
	}
end

local function normalizeGrant(rawGrant)
	local grant = if typeof(rawGrant) == "table" then cloneValue(rawGrant) else {}
	grant.Source = tostring(grant.Source or "")
	grant.GrantedAt = math.max(0, math.floor(tonumber(grant.GrantedAt) or 0))
	grant.StartsAt = math.max(0, math.floor(tonumber(grant.StartsAt) or grant.GrantedAt or 0))
	grant.ExpiresAt = math.max(0, math.floor(tonumber(grant.ExpiresAt) or 0))
	grant.DurationSeconds = math.max(0, math.floor(tonumber(grant.DurationSeconds) or math.max(0, grant.ExpiresAt - grant.StartsAt)))
	grant.RevokedAt = math.max(0, math.floor(tonumber(grant.RevokedAt) or 0))
	grant.RevokedReason = tostring(grant.RevokedReason or "")
	return grant
end

local function normalizeData(rawData)
	local data = defaultData()
	if typeof(rawData) == "table" then
		data = cloneValue(rawData)
	end

	data.SchemaVersion = math.max(SCHEMA_VERSION, math.floor(tonumber(data.SchemaVersion) or SCHEMA_VERSION))
	data.Enabled = data.Enabled == true
	data.SuppressionUntil = math.max(0, math.floor(tonumber(data.SuppressionUntil) or 0))
	data.NewPlayerGrantSeeded = data.NewPlayerGrantSeeded == true
	data.LastRaidPenaltyReceiptId = tostring(data.LastRaidPenaltyReceiptId or "")
	data.LastRaidPenaltyAt = math.max(0, math.floor(tonumber(data.LastRaidPenaltyAt) or 0))
	data.LastRaidPenaltyReason = tostring(data.LastRaidPenaltyReason or "")

	local grants = {}
	if typeof(data.Grants) == "table" then
		for grantId, grant in pairs(data.Grants) do
			grants[tostring(grantId)] = normalizeGrant(grant)
		end
	end
	data.Grants = grants
	return data
end

local function readData(player)
	local value, reason = DataManager:TryGetValue(player, DATA_PATH)
	if reason ~= nil then
		return nil, reason
	end
	return normalizeData(value), nil
end

local function saveData(player, data)
	local success, reason = DataManager:TrySetValue(player, DATA_PATH, normalizeData(data))
	if success ~= true then
		return false, reason or "shield_persistence_unavailable"
	end
	return true, nil
end

local function mirrorLegacyToggle(player, enabled)
	local success, reason = DataManager:TrySetValue(player, LEGACY_MANUAL_PATH, enabled == true)
	if success ~= true then
		return false, reason or "shield_persistence_unavailable"
	end
	return true, nil
end

local function readLegacyRemoved(player)
	local path = "PremiumCrewStealProtection.NewPlayerRemoved"
	local value, reason = DataManager:TryGetValue(player, path)
	if reason ~= nil then
		return false, reason
	end
	return value == true, nil
end

local function readLegacyEnabled(player)
	local value, reason = DataManager:TryGetValue(player, LEGACY_MANUAL_PATH)
	if reason ~= nil then
		return true, reason
	end
	if typeof(value) == "boolean" then
		return value, nil
	end
	return true, nil
end

local function readPlaytime(player)
	local value, reason = DataManager:TryGetValue(player, "TotalStats.TimePlayed")
	if reason ~= nil then
		return 0, reason
	end
	return math.max(0, math.floor(tonumber(value) or 0)), nil
end

local function getActiveShieldInfo(data, timestamp)
	local activeUntil = 0
	local activeSource = nil
	local sources = {}

	for grantId, grant in pairs(data.Grants or {}) do
		local expiresAt = math.max(0, math.floor(tonumber(grant.ExpiresAt) or 0))
		local revokedAt = math.max(0, math.floor(tonumber(grant.RevokedAt) or 0))
		if revokedAt <= 0 and expiresAt > timestamp then
			local source = tostring(grant.Source or grantId)
			sources[source] = true
			if expiresAt > activeUntil then
				activeUntil = expiresAt
				activeSource = source
			end
		end
	end

	return activeUntil, activeSource, sources
end

local function computeState(player, data)
	local timestamp = now()
	local activeUntil, activeSource, sourceMap = getActiveShieldInfo(data, timestamp)
	local remainingSeconds = math.max(0, activeUntil - timestamp)
	local suppressionUntil = math.max(0, math.floor(tonumber(data.SuppressionUntil) or 0))
	local suppressionRemaining = math.max(0, suppressionUntil - timestamp)
	local canEnable = remainingSeconds > 0 and suppressionRemaining <= 0
	local effectiveEnabled = data.Enabled == true and canEnable
	local disabledReason = ""

	if remainingSeconds <= 0 then
		disabledReason = "shield_expired"
	elseif suppressionRemaining > 0 then
		disabledReason = "raid_suppression"
	elseif data.Enabled ~= true then
		disabledReason = "manual_disabled"
	end

	local playtimeSeconds = readPlaytime(player)
	return {
		SchemaVersion = SCHEMA_VERSION,
		ServerTime = timestamp,
		Enabled = effectiveEnabled,
		PreferredEnabled = data.Enabled == true,
		IsActive = effectiveEnabled,
		CanEnable = canEnable,
		ActiveUntil = activeUntil,
		RemainingSeconds = remainingSeconds,
		SuppressionUntil = suppressionUntil,
		SuppressionRemainingSeconds = suppressionRemaining,
		DisabledReason = disabledReason,
		Source = activeSource,
		PlaytimeSeconds = playtimeSeconds,
		SuppressionDurationSeconds = RAID_SUPPRESSION_SECONDS,
		Sources = {
			NewPlayerProtection = sourceMap[NEW_PLAYER_SOURCE] == true or sourceMap[NEW_PLAYER_GRANT_ID] == true,
			ManualProtectionDisabled = disabledReason == "manual_disabled",
			FutureShieldProtection = next(sourceMap) ~= nil,
			RaidSuppression = suppressionRemaining > 0,
		},
	}
end

local function ensureInitialized(player)
	local data, reason = readData(player)
	if not data then
		return nil, reason or "shield_persistence_unavailable"
	end
	if data.NewPlayerGrantSeeded == true then
		return data, nil
	end

	local legacyRemoved, removedReason = readLegacyRemoved(player)
	if removedReason ~= nil then
		return nil, removedReason
	end
	local legacyEnabled, enabledReason = readLegacyEnabled(player)
	if enabledReason ~= nil then
		return nil, enabledReason
	end
	local playtimeSeconds, playtimeReason = readPlaytime(player)
	if playtimeReason ~= nil then
		return nil, playtimeReason
	end

	data.NewPlayerGrantSeeded = true
	data.Enabled = legacyEnabled == true
	if legacyRemoved == true then
		data.Enabled = false
	elseif NEW_PLAYER_DURATION_SECONDS > 0 and playtimeSeconds < NEW_PLAYER_DURATION_SECONDS then
		local timestamp = now()
		local remaining = math.max(1, NEW_PLAYER_DURATION_SECONDS - playtimeSeconds)
		if typeof(data.Grants[NEW_PLAYER_GRANT_ID]) ~= "table" then
			data.Grants[NEW_PLAYER_GRANT_ID] = {
				Source = NEW_PLAYER_SOURCE,
				GrantedAt = timestamp,
				StartsAt = timestamp,
				ExpiresAt = timestamp + remaining,
				DurationSeconds = remaining,
				RevokedAt = 0,
				RevokedReason = "",
			}
		end
	end

	local saved, saveReason = saveData(player, data)
	if saved ~= true then
		return nil, saveReason or "shield_persistence_unavailable"
	end
	mirrorLegacyToggle(player, data.Enabled == true)
	return data, nil
end

local function applyAttributes(player, state)
	local premiumSource = state.Source or state.DisabledReason
	player:SetAttribute(Config.Attributes.ProtectedUntil, if state.IsActive then state.ActiveUntil else nil)
	player:SetAttribute(Config.Attributes.ProtectionActive, state.IsActive == true)
	player:SetAttribute(Config.Attributes.ProtectionSource, premiumSource)
	player:SetAttribute(Config.Attributes.ProtectionRemainingSeconds, math.max(0, math.floor(tonumber(state.RemainingSeconds) or 0)))
	player:SetAttribute(Config.Attributes.ProtectionPlaytimeSeconds, math.max(0, math.floor(tonumber(state.PlaytimeSeconds) or 0)))
	player:SetAttribute(Config.Attributes.ProtectionRemovedReason, state.DisabledReason)

	player:SetAttribute(ATTRIBUTES.Enabled or "RaidShieldEnabled", state.Enabled == true)
	player:SetAttribute(ATTRIBUTES.Active or "RaidShieldActive", state.IsActive == true)
	player:SetAttribute(ATTRIBUTES.ActiveUntil or "RaidShieldActiveUntil", math.max(0, math.floor(tonumber(state.ActiveUntil) or 0)))
	player:SetAttribute(ATTRIBUTES.RemainingSeconds or "RaidShieldRemainingSeconds", math.max(0, math.floor(tonumber(state.RemainingSeconds) or 0)))
	player:SetAttribute(ATTRIBUTES.SuppressionUntil or "RaidShieldSuppressionUntil", math.max(0, math.floor(tonumber(state.SuppressionUntil) or 0)))
	player:SetAttribute(ATTRIBUTES.SuppressionRemainingSeconds or "RaidShieldSuppressionRemainingSeconds", math.max(0, math.floor(tonumber(state.SuppressionRemainingSeconds) or 0)))
	player:SetAttribute(ATTRIBUTES.CanEnable or "RaidShieldCanEnable", state.CanEnable == true)
	player:SetAttribute(ATTRIBUTES.DisabledReason or "RaidShieldDisabledReason", state.DisabledReason)
	player:SetAttribute(ATTRIBUTES.Source or "RaidShieldSource", state.Source)
end

local function fireState(player, state)
	ensureRemotes()
	if player.Parent == Players then
		stateRemote:FireClient(player, cloneValue(state))
	end
end

local function scheduleRefresh(player, state)
	refreshTokens[player] = nil
	local timestamp = now()
	local nextAt = math.huge
	if tonumber(state.ActiveUntil) and state.ActiveUntil > timestamp then
		nextAt = math.min(nextAt, state.ActiveUntil)
	end
	if tonumber(state.SuppressionUntil) and state.SuppressionUntil > timestamp then
		nextAt = math.min(nextAt, state.SuppressionUntil)
	end
	if nextAt == math.huge then
		return
	end

	local token = {}
	refreshTokens[player] = token
	task.delay(math.max(1, nextAt - timestamp + 1), function()
		if refreshTokens[player] == token and player.Parent == Players then
			RaidShieldService.RefreshPlayer(player)
		end
	end)
end

local function disconnectPlayer(player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	playerConnections[player] = nil
	refreshTokens[player] = nil
	ProtectionVisuals.ClearPlayer(player)
end

local function bindPlayer(player)
	disconnectPlayer(player)
	playerConnections[player] = {}

	task.spawn(function()
		DataManager:WaitUntilReady(player, 30)
		if player.Parent ~= Players then
			return
		end
		RaidShieldService.RefreshPlayer(player)
	end)
end

function RaidShieldService.RefreshPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, "invalid_player"
	end

	local data, reason = ensureInitialized(player)
	if not data then
		local inactiveState = {
			ServerTime = now(),
			Enabled = false,
			PreferredEnabled = false,
			IsActive = false,
			CanEnable = false,
			ActiveUntil = 0,
			RemainingSeconds = 0,
			SuppressionUntil = 0,
			SuppressionRemainingSeconds = 0,
			DisabledReason = reason or "shield_persistence_unavailable",
			Source = nil,
			PlaytimeSeconds = 0,
			SuppressionDurationSeconds = RAID_SUPPRESSION_SECONDS,
			Sources = {},
		}
		applyAttributes(player, inactiveState)
		ProtectionVisuals.UpdatePlayer(player)
		fireState(player, inactiveState)
		return nil, reason or "shield_persistence_unavailable"
	end

	local state = computeState(player, data)
	applyAttributes(player, state)
	ProtectionVisuals.UpdatePlayer(player)
	fireState(player, state)
	scheduleRefresh(player, state)
	return state, nil
end

function RaidShieldService.GetState(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, "invalid_player"
	end
	local data, reason = ensureInitialized(player)
	if not data then
		return nil, reason or "shield_persistence_unavailable"
	end
	return computeState(player, data), nil
end

function RaidShieldService.IsPlayerProtected(player)
	local state, reason = RaidShieldService.GetState(player)
	if not state then
		return nil, 0, reason or "shield_persistence_unavailable"
	end
	if state.IsActive then
		return true, state.RemainingSeconds, state.Source
	end
	return false, 0, state.DisabledReason
end

function RaidShieldService.GrantShield(player, source, durationSeconds, metadata)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local duration = math.max(0, math.floor(tonumber(durationSeconds) or 0))
	if duration <= 0 then
		return false, "invalid_duration"
	end

	local data, reason = ensureInitialized(player)
	if not data then
		return false, reason or "shield_persistence_unavailable"
	end

	local timestamp = now()
	local activeUntil = getActiveShieldInfo(data, timestamp)
	local startsAt = math.max(timestamp, activeUntil)
	local grantSource = tostring(source or "grant")
	local grantId = if grantSource == NEW_PLAYER_SOURCE then NEW_PLAYER_GRANT_ID else grantSource .. ":" .. HttpService:GenerateGUID(false)
	data.Grants[grantId] = {
		Source = grantSource,
		GrantedAt = timestamp,
		StartsAt = startsAt,
		ExpiresAt = startsAt + duration,
		DurationSeconds = duration,
		RevokedAt = 0,
		RevokedReason = "",
		Metadata = if typeof(metadata) == "table" then cloneValue(metadata) else nil,
	}
	if grantSource == NEW_PLAYER_SOURCE then
		data.NewPlayerGrantSeeded = true
		data.Enabled = true
	end

	local saved, saveReason = saveData(player, data)
	if saved ~= true then
		return false, saveReason or "shield_persistence_unavailable"
	end
	RaidShieldService.RefreshPlayer(player)
	local state = RaidShieldService.GetState(player)
	return true, state
end

function RaidShieldService.SetEnabled(player, enabled, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local data, readReason = ensureInitialized(player)
	if not data then
		return false, readReason or "shield_persistence_unavailable"
	end

	local state = computeState(player, data)
	if enabled == true then
		if state.RemainingSeconds <= 0 then
			return false, "shield_expired", state
		end
		if state.SuppressionRemainingSeconds > 0 then
			return false, "raid_suppression", state
		end
		data.Enabled = true
	else
		data.Enabled = false
	end

	local saved, saveReason = saveData(player, data)
	if saved ~= true then
		return false, saveReason or "shield_persistence_unavailable", state
	end
	mirrorLegacyToggle(player, data.Enabled == true)

	local refreshedState = RaidShieldService.RefreshPlayer(player)
	return true, refreshedState, tostring(reason or "settings_toggle")
end

function RaidShieldService.ApplyRaidCompletedPenalty(player, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	context = if typeof(context) == "table" then context else {}
	local data, readReason = ensureInitialized(player)
	if not data then
		return false, readReason or "shield_persistence_unavailable"
	end

	local receiptId = tostring(context.ReceiptId or context.PurchaseId or "")
	if receiptId ~= "" and data.LastRaidPenaltyReceiptId == receiptId then
		local state = RaidShieldService.GetState(player)
		return true, state, "already_applied"
	end

	local timestamp = math.max(0, math.floor(tonumber(context.CompletedAt) or now()))
	data.Enabled = false
	if RAID_SUPPRESSION_SECONDS > 0 then
		data.SuppressionUntil = math.max(data.SuppressionUntil, timestamp + RAID_SUPPRESSION_SECONDS)
	end
	data.LastRaidPenaltyReceiptId = receiptId
	data.LastRaidPenaltyAt = timestamp
	data.LastRaidPenaltyReason = tostring(context.Reason or "raid_completed")

	local saved, saveReason = saveData(player, data)
	if saved ~= true then
		return false, saveReason or "shield_persistence_unavailable"
	end
	mirrorLegacyToggle(player, false)

	local state = RaidShieldService.RefreshPlayer(player)
	return true, state, nil
end

function RaidShieldService.BuildRaidAttemptPromptState(player)
	local state, reason = RaidShieldService.GetState(player)
	if not state then
		return {
			Mode = "unavailable",
			RequiresConfirmation = true,
			Reason = reason or "shield_persistence_unavailable",
			Message = "Protection status could not be verified. The server will recheck before purchase.",
			SuppressionDurationSeconds = RAID_SUPPRESSION_SECONDS,
		}
	end

	local mode = "expired"
	local message = "You do not have active protection time remaining. A successful raid will keep protection disabled until you earn or buy more shield time."
	if state.IsActive then
		mode = "shield_on"
		message = "Your protection is ON. If this raid succeeds, protection will be turned OFF and cannot be re-enabled for "
			.. formatDuration(RAID_SUPPRESSION_SECONDS)
			.. "."
	elseif state.SuppressionRemainingSeconds > 0 then
		mode = "suppressed"
		message = "Protection is already disabled. You can enable it again in "
			.. formatDuration(state.SuppressionRemainingSeconds)
			.. "."
	elseif state.RemainingSeconds > 0 then
		mode = "shield_off"
		message = "Protection is OFF. If this raid succeeds, it will stay disabled for "
			.. formatDuration(RAID_SUPPRESSION_SECONDS)
			.. "."
	end

	return {
		Mode = mode,
		RequiresConfirmation = true,
		Message = message,
		RemainingSeconds = state.RemainingSeconds,
		SuppressionRemainingSeconds = state.SuppressionRemainingSeconds,
		SuppressionDurationSeconds = RAID_SUPPRESSION_SECONDS,
	}
end

function RaidShieldService.GetDenialMessage(reason, state)
	reason = tostring(reason or "")
	if reason == "raid_suppression" then
		local remaining = state and state.SuppressionRemainingSeconds or 0
		return "Protection can be enabled again in " .. formatDuration(remaining) .. "."
	elseif reason == "shield_expired" then
		return "You do not have any protection time remaining."
	elseif reason == "shield_persistence_unavailable" then
		return "Protection is temporarily unavailable. Try again soon."
	end
	return "Protection could not be updated."
end

function RaidShieldService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()
	setEnabledRemote.OnServerInvoke = function(player, enabled)
		if not RemoteGuard.Check(player, tostring(REMOTE_CONFIG.SetEnabledName or "RaidShieldSetEnabled"), { enabled }, {
			Cooldown = 0.2,
			Args = {
				{ Type = "boolean" },
			},
		}) then
			return {
				Ok = false,
				Reason = "remote_rejected",
				Message = "Protection toggle is cooling down.",
			}
		end

		local ok, resultOrReason, maybeState = RaidShieldService.SetEnabled(player, enabled, "settings_toggle")
		if ok == true then
			return {
				Ok = true,
				State = resultOrReason,
			}
		end

		local state = maybeState
		local message = RaidShieldService.GetDenialMessage(resultOrReason, state)
		PopUpModule:Server_SendPopUp(player, message, ERROR_COLOR, STROKE_COLOR, 3, true)
		if state then
			fireState(player, state)
		end
		return {
			Ok = false,
			Reason = resultOrReason,
			Message = message,
			State = state,
		}
	end

	ProtectionVisuals.Start()
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(disconnectPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

return RaidShieldService
