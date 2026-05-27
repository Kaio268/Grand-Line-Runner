local Players = game:GetService("Players")
local MemoryStoreService = game:GetService("MemoryStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local Config = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig")
)
local ProtectionVisuals = require(ServerScriptService.Modules:WaitForChild("PremiumCrewStealProtectionVisuals"))

local Protection = {}

local SOURCE_NEW_PLAYER = "NewPlayerProtection"
local SOURCE_MANUAL_DISABLED = "ManualProtectionDisabled"
local SOURCE_REMOVED = "ProtectionRemoved"
local SOURCE_PLAYTIME_COMPLETE = "PlaytimeThresholdMet"

local started = false
local removalMap = nil
local locallyRemovedProtection = {}
local playerConnections = {}
local thresholdRefreshTokens = {}

local function now()
	return os.time()
end

local function getNewPlayerConfig()
	return Config.NewPlayerProtection or {}
end

local function getThresholdSeconds()
	return math.max(0, math.floor(tonumber(getNewPlayerConfig().PlaytimeThresholdSeconds) or 28800))
end

local function getRemovalMemoryStoreMap()
	if removalMap ~= nil then
		return removalMap, nil
	end

	local mapName = tostring(Config.Protection.RemovalMemoryStoreName or "PremiumCrewStealProtectionRemoved_v1")
	local ok, result = pcall(function()
		return MemoryStoreService:GetHashMap(mapName)
	end)
	if ok and result then
		removalMap = result
		return removalMap, nil
	end

	warn("[PremiumCrewStealProtection] MemoryStore protection removal persistence unavailable: " .. tostring(result))
	return nil, "protection_persistence_unavailable"
end

local function getRemovalKey(playerOrUserId)
	local userId = if typeof(playerOrUserId) == "Instance" then playerOrUserId.UserId else tonumber(playerOrUserId)
	if not userId then
		return nil
	end
	return "removed:" .. tostring(userId)
end

local function getValue(player, path)
	local ok, value, reason = pcall(function()
		return DataManager:TryGetValue(player, path)
	end)
	if not ok then
		warn("[PremiumCrewStealProtection] Data read failed path=" .. tostring(path) .. " error=" .. tostring(value))
		return nil, false, "protection_persistence_unavailable"
	end
	if reason ~= nil then
		return nil, false, "protection_persistence_unavailable"
	end
	return value, true, nil
end

local function setValue(player, path, value)
	local ok, success, reason = pcall(function()
		return DataManager:TrySetValue(player, path, value)
	end)
	if not ok then
		warn("[PremiumCrewStealProtection] Data write failed path=" .. tostring(path) .. " error=" .. tostring(success))
		return false, "protection_persistence_unavailable"
	end
	if success ~= true then
		return false, "protection_persistence_unavailable"
	end
	return true, reason
end

local function getPathInstance(root, path)
	if typeof(root) ~= "Instance" then
		return nil
	end

	local current = root
	for segment in string.gmatch(tostring(path or ""), "[^%.]+") do
		current = current and current:FindFirstChild(segment) or nil
		if not current then
			return nil
		end
	end
	return current
end

local function waitForPathInstance(root, path, timeoutSeconds)
	if typeof(root) ~= "Instance" then
		return nil
	end

	local deadline = os.clock() + math.max(0, tonumber(timeoutSeconds) or 0)
	local current = root
	for segment in string.gmatch(tostring(path or ""), "[^%.]+") do
		local child = current:FindFirstChild(segment)
		while not child and os.clock() < deadline do
			child = current:WaitForChild(segment, math.max(0.05, deadline - os.clock()))
		end
		if not child then
			return nil
		end
		current = child
	end
	return current
end

local function getManualProtectionEnabled(player)
	local path = tostring(getNewPlayerConfig().ManualEnabledPath or "Settings.PremiumStealProtectionEnabled")
	local value, verified, reason = getValue(player, path)
	if verified ~= true then
		return nil, reason or "protection_persistence_unavailable"
	end
	if typeof(value) ~= "boolean" then
		return true, nil
	end
	return value == true, nil
end

local function getPlaytimeSeconds(player)
	local path = tostring(getNewPlayerConfig().PlaytimePath or "TotalStats.TimePlayed")
	local value, verified, reason = getValue(player, path)
	if verified ~= true then
		return nil, reason or "protection_persistence_unavailable"
	end
	return math.max(0, math.floor(tonumber(value) or 0)), nil
end

local function getProfileRemoval(player)
	local removedPath = tostring(getNewPlayerConfig().RemovedPath or "PremiumCrewStealProtection.NewPlayerRemoved")
	local reasonPath = tostring(getNewPlayerConfig().RemovedReasonPath or "PremiumCrewStealProtection.RemovedReason")

	local removedValue, removedVerified, removedReason = getValue(player, removedPath)
	if removedVerified ~= true then
		return false, nil, false, removedReason or "protection_persistence_unavailable"
	end

	if removedValue ~= true then
		return false, nil, true
	end

	local reasonValue = getValue(player, reasonPath)
	local reasonText = if typeof(reasonValue) == "string" and reasonValue ~= "" then reasonValue else "profile_removal"
	return true, reasonText, true
end

local function persistProfileRemoval(playerOrUserId, reason)
	if not (typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player")) then
		return false, "protection_persistence_unavailable"
	end

	local cfg = getNewPlayerConfig()
	local player = playerOrUserId
	local removedPath = tostring(cfg.RemovedPath or "PremiumCrewStealProtection.NewPlayerRemoved")
	local removedAtPath = tostring(cfg.RemovedAtPath or "PremiumCrewStealProtection.RemovedAt")
	local removedReasonPath = tostring(cfg.RemovedReasonPath or "PremiumCrewStealProtection.RemovedReason")

	local ok, setReason = setValue(player, removedPath, true)
	if ok ~= true then
		return false, setReason or "protection_persistence_unavailable"
	end
	ok, setReason = setValue(player, removedAtPath, now())
	if ok ~= true then
		return false, setReason or "protection_persistence_unavailable"
	end
	ok, setReason = setValue(player, removedReasonPath, tostring(reason or "cleared"))
	if ok ~= true then
		return false, setReason or "protection_persistence_unavailable"
	end

	return true, nil
end

local function getMemoryStoreRemoval(playerOrUserId)
	local key = getRemovalKey(playerOrUserId)
	if not key then
		return false, nil, false, "invalid_player"
	end

	local localRemoval = locallyRemovedProtection[key]
	if typeof(localRemoval) == "table" then
		return true, tostring(localRemoval.Reason or "local_removal"), true
	end

	local map, mapReason = getRemovalMemoryStoreMap()
	if not map then
		return false, nil, false, mapReason or "protection_persistence_unavailable"
	end

	local ok, result = pcall(function()
		return map:GetAsync(key)
	end)
	if ok and typeof(result) == "table" then
		locallyRemovedProtection[key] = result
		return true, tostring(result.Reason or "persisted_removal"), true
	elseif not ok then
		warn("[PremiumCrewStealProtection] MemoryStore protection removal read failed key=" .. tostring(key) .. " error=" .. tostring(result))
		return false, nil, false, "protection_persistence_unavailable"
	end

	return false, nil, true
end

local function persistMemoryStoreRemoval(playerOrUserId, reason)
	local key = getRemovalKey(playerOrUserId)
	if not key then
		return false, "invalid_player"
	end

	local userId = if typeof(playerOrUserId) == "Instance" then playerOrUserId.UserId else tonumber(playerOrUserId)
	local marker = {
		UserId = userId,
		Reason = tostring(reason or "cleared"),
		RemovedAt = now(),
	}

	local map, mapReason = getRemovalMemoryStoreMap()
	if not map then
		return false, mapReason or "protection_persistence_unavailable"
	end

	local ttl = math.max(60, math.floor(tonumber(Config.Protection.RemovalMemoryStoreTtlSeconds) or 86400))
	local ok, err = pcall(function()
		map:SetAsync(key, marker, ttl)
	end)
	if not ok then
		warn("[PremiumCrewStealProtection] MemoryStore protection removal write failed key=" .. tostring(key) .. " error=" .. tostring(err))
		return false, "protection_persistence_unavailable"
	end

	locallyRemovedProtection[key] = marker
	return true, nil
end

local function isProtectionRemovalPersisted(player)
	local profileRemoved, profileReason, profileVerified, profileVerifyReason = getProfileRemoval(player)
	if profileVerified ~= true then
		return false, nil, false, profileVerifyReason or "protection_persistence_unavailable"
	end

	local memoryRemoved, memoryReason, memoryVerified, memoryVerifyReason = getMemoryStoreRemoval(player)
	if memoryVerified ~= true then
		return false, nil, false, memoryVerifyReason or "protection_persistence_unavailable"
	end

	if profileRemoved and not memoryRemoved then
		local persisted, persistReason = persistMemoryStoreRemoval(player, profileReason or "profile_removal")
		if persisted ~= true then
			return false, nil, false, persistReason or "protection_persistence_unavailable"
		end
		return true, profileReason or "profile_removal", true
	end

	if memoryRemoved and not profileRemoved then
		local persisted, persistReason = persistProfileRemoval(player, memoryReason or "persisted_removal")
		if persisted ~= true then
			return false, nil, false, persistReason or "protection_persistence_unavailable"
		end
		return true, memoryReason or "persisted_removal", true
	end

	if profileRemoved or memoryRemoved then
		return true, profileReason or memoryReason or "persisted_removal", true
	end

	return false, nil, true
end

local function verifyRemovalPersistenceWrite(playerOrUserId)
	if not (typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player")) then
		return false, "protection_persistence_unavailable"
	end
	if not DataManager:IsReady(playerOrUserId) then
		return false, "protection_persistence_unavailable"
	end

	local key = getRemovalKey(playerOrUserId)
	if not key then
		return false, "invalid_player"
	end

	local map, mapReason = getRemovalMemoryStoreMap()
	if not map then
		return false, mapReason or "protection_persistence_unavailable"
	end

	local ok, err = pcall(function()
		map:SetAsync("verify:" .. tostring(key), now(), 60)
	end)
	if not ok then
		warn("[PremiumCrewStealProtection] MemoryStore protection removal verify write failed key=" .. tostring(key) .. " error=" .. tostring(err))
		return false, "protection_persistence_unavailable"
	end
	return true, nil
end

local function clearProtectionAttributes(player, source, playtimeSeconds)
	player:SetAttribute(Config.Attributes.ProtectedUntil, nil)
	player:SetAttribute(Config.Attributes.ProtectionActive, false)
	player:SetAttribute(Config.Attributes.ProtectionSource, source)
	player:SetAttribute(Config.Attributes.ProtectionRemainingSeconds, 0)
	player:SetAttribute(Config.Attributes.ProtectionPlaytimeSeconds, playtimeSeconds or 0)
end

local function applyProtectionAttributes(player, state)
	player:SetAttribute(Config.Attributes.ProtectedUntil, nil)
	player:SetAttribute(Config.Attributes.ProtectionActive, state.IsProtected == true)
	player:SetAttribute(Config.Attributes.ProtectionSource, state.Source)
	player:SetAttribute(Config.Attributes.ProtectionRemainingSeconds, math.max(0, math.floor(tonumber(state.RemainingSeconds) or 0)))
	player:SetAttribute(Config.Attributes.ProtectionPlaytimeSeconds, math.max(0, math.floor(tonumber(state.PlaytimeSeconds) or 0)))
	player:SetAttribute(Config.Attributes.ProtectionRemovedReason, state.RemovedReason)
end

local function scheduleThresholdRefresh(player, remainingSeconds)
	thresholdRefreshTokens[player] = nil
	local remaining = math.max(0, math.floor(tonumber(remainingSeconds) or 0))
	if remaining <= 0 then
		return
	end

	local token = {}
	thresholdRefreshTokens[player] = token
	task.delay(remaining + 1, function()
		if thresholdRefreshTokens[player] == token and player.Parent == Players then
			Protection.RefreshPlayer(player)
		end
	end)
end

function Protection.GetProtectionState(player)
	if Config.Protection.Enabled ~= true or getNewPlayerConfig().Enabled ~= true then
		return {
			IsProtected = false,
			Source = nil,
			RemainingSeconds = 0,
			PlaytimeSeconds = 0,
			Sources = {
				NewPlayerProtection = false,
				ManualProtectionDisabled = false,
				FutureShieldProtection = false,
			},
		}, nil
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return {
			IsProtected = false,
			Source = nil,
			RemainingSeconds = 0,
			PlaytimeSeconds = 0,
			Sources = {
				NewPlayerProtection = false,
				ManualProtectionDisabled = false,
				FutureShieldProtection = false,
			},
		}, nil
	end

	local removed, removalReason, verified, verifyReason = isProtectionRemovalPersisted(player)
	if verified ~= true then
		return nil, verifyReason or "protection_persistence_unavailable"
	end
	if removed then
		return {
			IsProtected = false,
			Source = SOURCE_REMOVED,
			RemainingSeconds = 0,
			PlaytimeSeconds = 0,
			RemovedReason = removalReason or "persisted_removal",
			Sources = {
				NewPlayerProtection = false,
				ManualProtectionDisabled = false,
				FutureShieldProtection = false,
			},
		}, nil
	end

	local manualEnabled, manualReason = getManualProtectionEnabled(player)
	if manualEnabled == nil then
		return nil, manualReason or "protection_persistence_unavailable"
	end

	local playtimeSeconds, playtimeReason = getPlaytimeSeconds(player)
	if playtimeSeconds == nil then
		return nil, playtimeReason or "protection_persistence_unavailable"
	end

	local threshold = getThresholdSeconds()
	if manualEnabled ~= true then
		return {
			IsProtected = false,
			Source = SOURCE_MANUAL_DISABLED,
			RemainingSeconds = math.max(0, threshold - playtimeSeconds),
			PlaytimeSeconds = playtimeSeconds,
			Sources = {
				NewPlayerProtection = false,
				ManualProtectionDisabled = true,
				FutureShieldProtection = false,
			},
		}, nil
	end

	if threshold <= 0 or playtimeSeconds >= threshold then
		return {
			IsProtected = false,
			Source = SOURCE_PLAYTIME_COMPLETE,
			RemainingSeconds = 0,
			PlaytimeSeconds = playtimeSeconds,
			Sources = {
				NewPlayerProtection = false,
				ManualProtectionDisabled = false,
				FutureShieldProtection = false,
			},
		}, nil
	end

	local remaining = threshold - playtimeSeconds
	return {
		IsProtected = true,
		Source = SOURCE_NEW_PLAYER,
		RemainingSeconds = remaining,
		PlaytimeSeconds = playtimeSeconds,
		Sources = {
			NewPlayerProtection = true,
			ManualProtectionDisabled = false,
			FutureShieldProtection = false,
		},
	}, nil
end

function Protection.RefreshPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, "invalid_player"
	end

	local state, reason = Protection.GetProtectionState(player)
	if not state then
		clearProtectionAttributes(player, reason or "protection_persistence_unavailable", 0)
		player:SetAttribute(Config.Attributes.ProtectionRemovedReason, reason or "protection_persistence_unavailable")
		ProtectionVisuals.UpdatePlayer(player)
		return nil, reason or "protection_persistence_unavailable"
	end

	applyProtectionAttributes(player, state)
	ProtectionVisuals.UpdatePlayer(player)
	if state.IsProtected then
		scheduleThresholdRefresh(player, state.RemainingSeconds)
	else
		thresholdRefreshTokens[player] = nil
	end
	return state, nil
end

function Protection.IsProtected(player)
	local state, reason = Protection.GetProtectionState(player)
	if not state then
		return nil, 0, reason or "protection_persistence_unavailable"
	end
	if state.IsProtected then
		return true, state.RemainingSeconds, state.Source
	end
	return false, 0, state.Source
end

function Protection.CanPersistRemoval(playerOrUserId)
	if Config.Protection.Enabled ~= true then
		return true, nil
	end
	return verifyRemovalPersistenceWrite(playerOrUserId)
end

function Protection.ClearProtection(playerOrUserId, reason)
	local isPlayer = typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player")
	if not isPlayer then
		return false, "protection_persistence_unavailable"
	end

	local profileOk, profileReason = persistProfileRemoval(playerOrUserId, reason)
	if profileOk ~= true then
		return false, profileReason or "protection_persistence_unavailable"
	end

	local memoryOk, memoryReason = persistMemoryStoreRemoval(playerOrUserId, reason)
	if memoryOk ~= true then
		return false, memoryReason or "protection_persistence_unavailable"
	end

	playerOrUserId:SetAttribute(Config.Attributes.ProtectedUntil, nil)
	playerOrUserId:SetAttribute(Config.Attributes.ProtectionActive, false)
	playerOrUserId:SetAttribute(Config.Attributes.ProtectionSource, SOURCE_REMOVED)
	playerOrUserId:SetAttribute(Config.Attributes.ProtectionRemainingSeconds, 0)
	playerOrUserId:SetAttribute(Config.Attributes.ProtectionRemovedReason, tostring(reason or "cleared"))
	ProtectionVisuals.UpdatePlayer(playerOrUserId)
	return true, nil
end

local function disconnectPlayer(player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	playerConnections[player] = nil
	thresholdRefreshTokens[player] = nil
	ProtectionVisuals.ClearPlayer(player)
end

local function bindPlayer(player)
	disconnectPlayer(player)
	local connections = {}
	playerConnections[player] = connections

	task.spawn(function()
		DataManager:WaitUntilReady(player, 30)
		if player.Parent ~= Players then
			return
		end

		local manualPath = tostring(getNewPlayerConfig().ManualEnabledPath or "Settings.PremiumStealProtectionEnabled")
		local manualValue = waitForPathInstance(player, manualPath, 10)
		if manualValue and manualValue:IsA("ValueBase") then
			table.insert(connections, manualValue:GetPropertyChangedSignal("Value"):Connect(function()
				Protection.RefreshPlayer(player)
			end))
		end

		local settingsFolder = getPathInstance(player, "Settings")
		if settingsFolder then
			table.insert(connections, settingsFolder.DescendantAdded:Connect(function(descendant)
				if descendant.Name == "PremiumStealProtectionEnabled" and descendant:IsA("ValueBase") then
					table.insert(connections, descendant:GetPropertyChangedSignal("Value"):Connect(function()
						Protection.RefreshPlayer(player)
					end))
					Protection.RefreshPlayer(player)
				end
			end))
		end

		Protection.RefreshPlayer(player)
	end)
end

function Protection.Start()
	if started then
		return
	end
	started = true

	ProtectionVisuals.Start()
	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(disconnectPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

return Protection
