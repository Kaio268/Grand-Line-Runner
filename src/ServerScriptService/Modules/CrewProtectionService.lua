local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrewInstanceService = require(script.Parent:WaitForChild("CrewInstanceService"))
local RemoteGuard = require(script.Parent:WaitForChild("RemoteGuard"))

local CrewProtectionService = {}

local DATA_PATH = "CrewProtection"
local DAY_SECONDS = 24 * 60 * 60
local ACTION_REMOTE_NAME = "CrewProtectionActionRequest"

local ACTION_ALLOWLIST = {
	ApplyCrewShield = true,
	ApplyPermanentSlot = true,
	ActivateFleetShield = true,
	PauseFleetShield = true,
	ResumeFleetShield = true,
}

local DataManagerModule
local started = false

local function getDataManager(dataManager)
	if dataManager ~= nil then
		return dataManager
	end
	if DataManagerModule == nil then
		DataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return DataManagerModule
end

local function getProfile(player, dataManager)
	local manager = getDataManager(dataManager)
	if manager == nil or typeof(manager.TryGetProfile) ~= "function" then
		return nil, "data_manager_unavailable"
	end

	local profile = manager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return nil, "profile_not_ready"
	end

	return profile, nil
end

local function coerceNumber(value, fallback)
	local numeric = tonumber(value)
	if numeric == nil or numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return fallback
	end
	return numeric
end

local function ensureTable(parent, key)
	if typeof(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

local function ensureData(dataRoot)
	local data = ensureTable(dataRoot, DATA_PATH)
	data.SchemaVersion = 1
	data.ShieldTokens = math.max(0, math.floor(coerceNumber(data.ShieldTokens, 0)))
	data.FleetShieldTokens = math.max(0, math.floor(coerceNumber(data.FleetShieldTokens, 0)))
	data.CrewShields = ensureTable(data, "CrewShields")
	data.CrewShields.ByInstanceId = ensureTable(data.CrewShields, "ByInstanceId")
	data.FleetShield = ensureTable(data, "FleetShield")
	data.FleetShield.Enabled = data.FleetShield.Enabled ~= false
	data.FleetShield.ExpiresAtPlayTime = math.max(0, coerceNumber(data.FleetShield.ExpiresAtPlayTime, 0))
	data.FleetShield.PausedRemainingSeconds = math.max(0, math.floor(coerceNumber(data.FleetShield.PausedRemainingSeconds, 0)))
	data.FleetShield.LastGrantedAt = math.max(0, coerceNumber(data.FleetShield.LastGrantedAt, 0))
	if typeof(data.FleetShield.Source) ~= "string" then
		data.FleetShield.Source = ""
	end
	data.PermanentSlotsOwned = math.max(0, math.floor(coerceNumber(data.PermanentSlotsOwned, 0)))
	data.PermanentAssignments = ensureTable(data, "PermanentAssignments")
	return data
end

local function getPlayTime(player, dataManager)
	local manager = getDataManager(dataManager)
	if manager and typeof(manager.TryGetValue) == "function" then
		local value = manager:TryGetValue(player, "TotalStats.TimePlayed")
		return math.max(0, math.floor(coerceNumber(value, 0)))
	end
	return 0
end

local function syncData(player, dataManager, data)
	local manager = getDataManager(dataManager)
	if manager and typeof(manager.TrySetValue) == "function" then
		return manager:TrySetValue(player, DATA_PATH, data)
	end
	return false, "data_manager_unavailable"
end

local function instanceExists(player, instanceId)
	local resolvedInstanceId = CrewInstanceService.GetInstance(player, tostring(instanceId or ""))
	return resolvedInstanceId ~= nil
end

local function getOwnedInstance(player, instanceId)
	local resolvedInstanceId, instanceData = CrewInstanceService.GetInstance(player, tostring(instanceId or ""))
	if resolvedInstanceId == nil or typeof(instanceData) ~= "table" then
		return nil, nil
	end

	return tostring(resolvedInstanceId), instanceData
end

local function getFleetShieldRemaining(data, currentPlayTime)
	local fleetShield = data and data.FleetShield
	if typeof(fleetShield) ~= "table" or fleetShield.Enabled == false then
		return 0
	end

	return math.max(0, math.floor(coerceNumber(fleetShield.ExpiresAtPlayTime, 0) - currentPlayTime))
end

local function getRaidShieldService()
	local ok, RaidShieldService = pcall(function()
		return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RaidShieldService"))
	end)
	if ok and RaidShieldService then
		return RaidShieldService
	end
	return nil
end

local function grantRaidShield(player, durationSeconds, metadata)
	local RaidShieldService = getRaidShieldService()
	if RaidShieldService and typeof(RaidShieldService.GrantShield) == "function" then
		local grantOk, serviceOk, reason = pcall(function()
			return RaidShieldService.GrantShield(player, "fleet_shield", durationSeconds, metadata)
		end)
		if not grantOk or serviceOk ~= true then
			return false, reason or "raid_shield_unavailable"
		end
	end
	if RaidShieldService and typeof(RaidShieldService.SetEnabled) == "function" then
		local enableOk, serviceOk, reason = pcall(function()
			return RaidShieldService.SetEnabled(player, true, "crew_management_fleet_on")
		end)
		if not enableOk or serviceOk ~= true then
			return false, reason or "raid_shield_unavailable"
		end
	end
	return true, nil
end

local function setRaidShieldEnabled(player, enabled)
	local RaidShieldService = getRaidShieldService()
	if RaidShieldService and typeof(RaidShieldService.SetEnabled) == "function" then
		local reason = if enabled then "crew_management_fleet_on" else "crew_management_fleet_off"
		local callOk, serviceOk, serviceReason = pcall(function()
			return RaidShieldService.SetEnabled(player, enabled == true, reason)
		end)
		if not callOk or serviceOk ~= true then
			return false, serviceReason or "raid_shield_unavailable"
		end
	end
	return true, nil
end

local function countPermanentAssignments(assignments, player)
	local count = 0
	for slotKey, assignedInstanceId in pairs(assignments) do
		if not instanceExists(player, assignedInstanceId) then
			assignments[slotKey] = nil
		else
			count += 1
		end
	end
	return count
end

function CrewProtectionService.EnsureData(player, dataManager)
	local profile, reason = getProfile(player, dataManager)
	if profile == nil then
		return nil, reason
	end

	return ensureData(profile.Data), nil
end

function CrewProtectionService.GrantCrewShieldTokens(player, count, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local amount = math.max(1, math.floor(coerceNumber(count, 1)))
	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	data.ShieldTokens += amount
	return syncData(player, dataManager, data)
end

function CrewProtectionService.GrantFleetShieldTokens(player, count, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local amount = math.max(1, math.floor(coerceNumber(count, 1)))
	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	data.FleetShieldTokens += amount
	return syncData(player, dataManager, data)
end

function CrewProtectionService.AssignCrewShield(player, instanceId, durationSeconds, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local normalizedInstanceId = tostring(instanceId or "")
	local ownedInstanceId, instanceData = getOwnedInstance(player, normalizedInstanceId)
	if ownedInstanceId == nil or instanceData == nil then
		return false, "invalid_instance"
	end
	normalizedInstanceId = ownedInstanceId

	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end
	if data.ShieldTokens <= 0 then
		return false, "no_shield_tokens"
	end

	local duration = math.max(1, math.floor(coerceNumber(durationSeconds, DAY_SECONDS)))
	local currentPlayTime = getPlayTime(player, dataManager)

	for slotKey, assignedInstanceId in pairs(data.PermanentAssignments) do
		if not instanceExists(player, assignedInstanceId) then
			data.PermanentAssignments[slotKey] = nil
		elseif tostring(assignedInstanceId) == normalizedInstanceId then
			return false, "already_protected"
		end
	end

	local fleetRemaining = getFleetShieldRemaining(data, currentPlayTime)
	if fleetRemaining > 0 and tostring(instanceData.AssignedStand or "") ~= "" then
		return false, "already_protected"
	end

	local current = data.CrewShields.ByInstanceId[normalizedInstanceId]
	if typeof(current) == "table" then
		local remaining = math.max(0, math.floor(coerceNumber(current.ExpiresAtPlayTime, 0) - currentPlayTime))
		if remaining > 0 then
			return false, "already_protected"
		end
	end

	local previousTokens = data.ShieldTokens
	local previousShield = data.CrewShields.ByInstanceId[normalizedInstanceId]
	data.ShieldTokens -= 1
	data.CrewShields.ByInstanceId[normalizedInstanceId] = {
		GrantedAtPlayTime = currentPlayTime,
		ExpiresAtPlayTime = currentPlayTime + duration,
		DurationSeconds = duration,
		Source = "crew_shield",
	}

	local saved, saveReason = syncData(player, dataManager, data)
	if saved ~= true then
		data.ShieldTokens = previousTokens
		data.CrewShields.ByInstanceId[normalizedInstanceId] = previousShield
		return false, saveReason
	end

	return true, nil
end

function CrewProtectionService.GrantFleetShield(player, durationSeconds, dataManager, metadata)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local duration = math.max(1, math.floor(coerceNumber(durationSeconds, DAY_SECONDS)))
	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	local currentPlayTime = getPlayTime(player, dataManager)
	local startsAt = math.max(currentPlayTime, coerceNumber(data.FleetShield.ExpiresAtPlayTime, 0))
	local previousFleetShield = {
		Enabled = data.FleetShield.Enabled,
		ExpiresAtPlayTime = data.FleetShield.ExpiresAtPlayTime,
		PausedRemainingSeconds = data.FleetShield.PausedRemainingSeconds,
		LastGrantedAt = data.FleetShield.LastGrantedAt,
		Source = data.FleetShield.Source,
	}
	data.FleetShield.Enabled = true
	data.FleetShield.PausedRemainingSeconds = 0
	data.FleetShield.ExpiresAtPlayTime = startsAt + duration
	data.FleetShield.LastGrantedAt = os.time()
	data.FleetShield.Source = tostring(metadata and metadata.Source or "fleet_shield")

	local saved, saveReason = syncData(player, dataManager, data)
	if saved ~= true then
		return false, saveReason
	end

	local raidOk, raidReason = grantRaidShield(player, duration, metadata)
	if raidOk ~= true then
		data.FleetShield.Enabled = previousFleetShield.Enabled
		data.FleetShield.ExpiresAtPlayTime = previousFleetShield.ExpiresAtPlayTime
		data.FleetShield.PausedRemainingSeconds = previousFleetShield.PausedRemainingSeconds
		data.FleetShield.LastGrantedAt = previousFleetShield.LastGrantedAt
		data.FleetShield.Source = previousFleetShield.Source
		syncData(player, dataManager, data)
		return false, raidReason
	end

	return true, nil
end

function CrewProtectionService.ActivateFleetShieldFromToken(player, durationSeconds, dataManager, metadata)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local duration = math.max(1, math.floor(coerceNumber(durationSeconds, DAY_SECONDS)))
	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	local currentPlayTime = getPlayTime(player, dataManager)
	local remaining = getFleetShieldRemaining(data, currentPlayTime)
	if remaining > 0 then
		return false, "fleet_already_active"
	end
	if data.FleetShieldTokens <= 0 then
		return false, "no_fleet_shield_tokens"
	end

	local previousTokens = data.FleetShieldTokens
	local previousFleetShield = {
		Enabled = data.FleetShield.Enabled,
		ExpiresAtPlayTime = data.FleetShield.ExpiresAtPlayTime,
		PausedRemainingSeconds = data.FleetShield.PausedRemainingSeconds,
		LastGrantedAt = data.FleetShield.LastGrantedAt,
		Source = data.FleetShield.Source,
	}
	data.FleetShieldTokens -= 1
	data.FleetShield.Enabled = true
	data.FleetShield.PausedRemainingSeconds = 0
	data.FleetShield.ExpiresAtPlayTime = currentPlayTime + duration
	data.FleetShield.LastGrantedAt = os.time()
	data.FleetShield.Source = tostring(metadata and metadata.Source or "fleet_shield_token")

	local saved, saveReason = syncData(player, dataManager, data)
	if saved ~= true then
		data.FleetShieldTokens = previousTokens
		data.FleetShield.Enabled = previousFleetShield.Enabled
		data.FleetShield.ExpiresAtPlayTime = previousFleetShield.ExpiresAtPlayTime
		data.FleetShield.PausedRemainingSeconds = previousFleetShield.PausedRemainingSeconds
		data.FleetShield.LastGrantedAt = previousFleetShield.LastGrantedAt
		data.FleetShield.Source = previousFleetShield.Source
		return false, saveReason
	end

	local raidOk, raidReason = grantRaidShield(player, duration, metadata)
	if raidOk ~= true then
		data.FleetShieldTokens = previousTokens
		data.FleetShield.Enabled = previousFleetShield.Enabled
		data.FleetShield.ExpiresAtPlayTime = previousFleetShield.ExpiresAtPlayTime
		data.FleetShield.PausedRemainingSeconds = previousFleetShield.PausedRemainingSeconds
		data.FleetShield.LastGrantedAt = previousFleetShield.LastGrantedAt
		data.FleetShield.Source = previousFleetShield.Source
		syncData(player, dataManager, data)
		return false, raidReason
	end

	return true, nil
end

function CrewProtectionService.PauseFleetShield(player, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	local currentPlayTime = getPlayTime(player, dataManager)
	local remaining = getFleetShieldRemaining(data, currentPlayTime)
	if remaining <= 0 then
		return false, "fleet_not_active"
	end

	local previousFleetShield = {
		Enabled = data.FleetShield.Enabled,
		ExpiresAtPlayTime = data.FleetShield.ExpiresAtPlayTime,
		PausedRemainingSeconds = data.FleetShield.PausedRemainingSeconds,
		LastGrantedAt = data.FleetShield.LastGrantedAt,
		Source = data.FleetShield.Source,
	}

	data.FleetShield.Enabled = false
	data.FleetShield.ExpiresAtPlayTime = 0
	data.FleetShield.PausedRemainingSeconds = remaining
	data.FleetShield.LastGrantedAt = os.time()
	data.FleetShield.Source = "fleet_shield_paused"

	local saved, saveReason = syncData(player, dataManager, data)
	if saved ~= true then
		data.FleetShield.Enabled = previousFleetShield.Enabled
		data.FleetShield.ExpiresAtPlayTime = previousFleetShield.ExpiresAtPlayTime
		data.FleetShield.PausedRemainingSeconds = previousFleetShield.PausedRemainingSeconds
		data.FleetShield.LastGrantedAt = previousFleetShield.LastGrantedAt
		data.FleetShield.Source = previousFleetShield.Source
		return false, saveReason
	end

	local raidOk, raidReason = setRaidShieldEnabled(player, false)
	if raidOk ~= true then
		data.FleetShield.Enabled = previousFleetShield.Enabled
		data.FleetShield.ExpiresAtPlayTime = previousFleetShield.ExpiresAtPlayTime
		data.FleetShield.PausedRemainingSeconds = previousFleetShield.PausedRemainingSeconds
		data.FleetShield.LastGrantedAt = previousFleetShield.LastGrantedAt
		data.FleetShield.Source = previousFleetShield.Source
		syncData(player, dataManager, data)
		return false, raidReason
	end

	return true, nil
end

function CrewProtectionService.ResumeFleetShield(player, dataManager, metadata)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	local currentPlayTime = getPlayTime(player, dataManager)
	if getFleetShieldRemaining(data, currentPlayTime) > 0 then
		return false, "fleet_already_active"
	end

	local pausedRemaining = math.max(0, math.floor(coerceNumber(data.FleetShield.PausedRemainingSeconds, 0)))
	if pausedRemaining <= 0 then
		return false, "no_fleet_shield_tokens"
	end

	local previousFleetShield = {
		Enabled = data.FleetShield.Enabled,
		ExpiresAtPlayTime = data.FleetShield.ExpiresAtPlayTime,
		PausedRemainingSeconds = data.FleetShield.PausedRemainingSeconds,
		LastGrantedAt = data.FleetShield.LastGrantedAt,
		Source = data.FleetShield.Source,
	}

	data.FleetShield.Enabled = true
	data.FleetShield.ExpiresAtPlayTime = currentPlayTime + pausedRemaining
	data.FleetShield.PausedRemainingSeconds = 0
	data.FleetShield.LastGrantedAt = os.time()
	data.FleetShield.Source = tostring(metadata and metadata.Source or "fleet_shield_resumed")

	local saved, saveReason = syncData(player, dataManager, data)
	if saved ~= true then
		data.FleetShield.Enabled = previousFleetShield.Enabled
		data.FleetShield.ExpiresAtPlayTime = previousFleetShield.ExpiresAtPlayTime
		data.FleetShield.PausedRemainingSeconds = previousFleetShield.PausedRemainingSeconds
		data.FleetShield.LastGrantedAt = previousFleetShield.LastGrantedAt
		data.FleetShield.Source = previousFleetShield.Source
		return false, saveReason
	end

	local raidOk, raidReason = grantRaidShield(player, pausedRemaining, metadata)
	if raidOk ~= true then
		data.FleetShield.Enabled = previousFleetShield.Enabled
		data.FleetShield.ExpiresAtPlayTime = previousFleetShield.ExpiresAtPlayTime
		data.FleetShield.PausedRemainingSeconds = previousFleetShield.PausedRemainingSeconds
		data.FleetShield.LastGrantedAt = previousFleetShield.LastGrantedAt
		data.FleetShield.Source = previousFleetShield.Source
		syncData(player, dataManager, data)
		return false, raidReason
	end

	return true, nil
end

function CrewProtectionService.EnsurePermanentSlots(player, slotsOwned, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local targetSlots = math.max(0, math.floor(coerceNumber(slotsOwned, 0)))
	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	data.PermanentSlotsOwned = math.max(data.PermanentSlotsOwned, targetSlots)
	countPermanentAssignments(data.PermanentAssignments, player)
	return syncData(player, dataManager, data)
end

function CrewProtectionService.GrantPermanentSlots(player, count, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local amount = math.max(1, math.floor(coerceNumber(count, 1)))
	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	data.PermanentSlotsOwned += amount
	countPermanentAssignments(data.PermanentAssignments, player)
	return syncData(player, dataManager, data)
end

function CrewProtectionService.AssignPermanentSlot(player, slotKey, instanceId, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local normalizedSlotKey = tostring(slotKey or "")
	local normalizedInstanceId = tostring(instanceId or "")
	if normalizedSlotKey == "" then
		return false, "invalid_slot"
	end
	if normalizedInstanceId == "" or not instanceExists(player, normalizedInstanceId) then
		return false, "invalid_instance"
	end

	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	countPermanentAssignments(data.PermanentAssignments, player)
	if data.PermanentAssignments[normalizedSlotKey] == nil
		and countPermanentAssignments(data.PermanentAssignments, player) >= data.PermanentSlotsOwned
	then
		return false, "no_permanent_slots"
	end

	data.PermanentAssignments[normalizedSlotKey] = normalizedInstanceId
	return syncData(player, dataManager, data)
end

function CrewProtectionService.AssignNextPermanentSlot(player, instanceId, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "invalid_player"
	end

	local normalizedInstanceId, instanceData = getOwnedInstance(player, instanceId)
	if normalizedInstanceId == nil or instanceData == nil then
		return false, "invalid_instance"
	end

	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return false, reason
	end

	local currentPlayTime = getPlayTime(player, dataManager)
	local fleetRemaining = getFleetShieldRemaining(data, currentPlayTime)
	if fleetRemaining > 0 and tostring(instanceData.AssignedStand or "") ~= "" then
		return false, "already_protected"
	end

	for slotKey, assignedInstanceId in pairs(data.PermanentAssignments) do
		if not instanceExists(player, assignedInstanceId) then
			data.PermanentAssignments[slotKey] = nil
		elseif tostring(assignedInstanceId) == normalizedInstanceId then
			return false, "already_protected"
		end
	end

	local shield = data.CrewShields.ByInstanceId[normalizedInstanceId]
	if typeof(shield) == "table" then
		local remaining = math.max(0, math.floor(coerceNumber(shield.ExpiresAtPlayTime, 0) - currentPlayTime))
		if remaining > 0 then
			return false, "already_protected"
		end
		data.CrewShields.ByInstanceId[normalizedInstanceId] = nil
	end

	if countPermanentAssignments(data.PermanentAssignments, player) >= data.PermanentSlotsOwned then
		return false, "no_permanent_slots"
	end

	local slotIndex = 1
	local slotKey = "Slot1"
	while data.PermanentAssignments[slotKey] ~= nil do
		slotIndex += 1
		slotKey = "Slot" .. tostring(slotIndex)
	end

	data.PermanentAssignments[slotKey] = normalizedInstanceId
	local saved, saveReason = syncData(player, dataManager, data)
	if saved ~= true then
		data.PermanentAssignments[slotKey] = nil
		return false, saveReason
	end

	return true, nil
end

function CrewProtectionService.IsFleetProtected(player, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, 0, "invalid_player"
	end

	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return nil, 0, reason
	end

	local remaining = getFleetShieldRemaining(data, getPlayTime(player, dataManager))
	if remaining > 0 then
		return true, remaining, "fleet_shield"
	end

	return false, 0, "not_protected"
end

function CrewProtectionService.IsInstanceProtected(player, instanceId, dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, 0, "invalid_player"
	end

	local normalizedInstanceId = tostring(instanceId or "")
	if normalizedInstanceId == "" then
		return false, 0, "missing_instance"
	end

	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return nil, 0, reason
	end

	for slotKey, assignedInstanceId in pairs(data.PermanentAssignments) do
		if not instanceExists(player, assignedInstanceId) then
			data.PermanentAssignments[slotKey] = nil
		elseif tostring(assignedInstanceId) == normalizedInstanceId then
			return true, math.huge, "permanent_shield_slot"
		end
	end

	local shield = data.CrewShields.ByInstanceId[normalizedInstanceId]
	if typeof(shield) == "table" then
		local remaining = math.max(0, math.floor(coerceNumber(shield.ExpiresAtPlayTime, 0) - getPlayTime(player, dataManager)))
		if remaining > 0 then
			return true, remaining, "crew_shield"
		end
		data.CrewShields.ByInstanceId[normalizedInstanceId] = nil
	end

	return false, 0, "not_protected"
end

function CrewProtectionService.GetClientState(player, dataManager)
	local data, reason = CrewProtectionService.EnsureData(player, dataManager)
	if data == nil then
		return nil, reason
	end

	local currentPlayTime = getPlayTime(player, dataManager)
	local permanentAssignments = {}
	local permanentAssignedCount = 0
	for slotKey, assignedInstanceId in pairs(data.PermanentAssignments) do
		if instanceExists(player, assignedInstanceId) then
			local normalizedInstanceId = tostring(assignedInstanceId)
			permanentAssignments[tostring(slotKey)] = normalizedInstanceId
			permanentAssignedCount += 1
		end
	end

	local crewShields = {}
	for instanceId, shield in pairs(data.CrewShields.ByInstanceId) do
		if typeof(shield) == "table" and instanceExists(player, instanceId) then
			local remaining = math.max(0, math.floor(coerceNumber(shield.ExpiresAtPlayTime, 0) - currentPlayTime))
			if remaining > 0 then
				crewShields[tostring(instanceId)] = {
					RemainingSeconds = remaining,
					ExpiresAtPlayTime = coerceNumber(shield.ExpiresAtPlayTime, 0),
				}
			end
		end
	end

	local fleetRemaining = getFleetShieldRemaining(data, currentPlayTime)
	local pausedRemaining = math.max(0, math.floor(coerceNumber(data.FleetShield.PausedRemainingSeconds, 0)))
	local slotsOwned = math.max(0, math.floor(coerceNumber(data.PermanentSlotsOwned, 0)))

	return {
		ShieldTokens = data.ShieldTokens,
		FleetShieldTokens = data.FleetShieldTokens,
		PermanentSlotsOwned = slotsOwned,
		PermanentSlotsAvailable = math.max(0, slotsOwned - permanentAssignedCount),
		PermanentAssignments = permanentAssignments,
		CrewShields = crewShields,
		FleetShield = {
			Active = fleetRemaining > 0,
			Enabled = data.FleetShield.Enabled ~= false,
			Paused = data.FleetShield.Enabled == false and pausedRemaining > 0,
			RemainingSeconds = fleetRemaining,
			PausedRemainingSeconds = pausedRemaining,
			ExpiresAtPlayTime = coerceNumber(data.FleetShield.ExpiresAtPlayTime, 0),
		},
	}, nil
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

local function mapReasonToCode(reason)
	reason = tostring(reason or "")
	if reason == "no_shield_tokens" or reason == "no_fleet_shield_tokens" then
		return "no_tokens"
	elseif reason == "no_permanent_slots" then
		return "no_slots"
	elseif reason == "invalid_instance" or reason == "missing_instance" then
		return "invalid_crewmate"
	elseif reason == "already_protected" then
		return "already_protected"
	elseif reason == "fleet_already_active" then
		return "fleet_already_active"
	elseif reason == "fleet_not_active" then
		return "fleet_not_active"
	elseif reason == "profile_not_ready" or reason == "data_manager_unavailable" or reason == "missing_profile" or reason == "raid_shield_unavailable" then
		return "data_unavailable"
	end
	return "error"
end

local function messageForCode(code, actionName)
	if code == "success" then
		if actionName == "ApplyCrewShield" then
			return "Crew Shield applied."
		elseif actionName == "ApplyPermanentSlot" then
			return "Permanent protection applied."
		elseif actionName == "PauseFleetShield" then
			return "Fleet Shield paused."
		elseif actionName == "ActivateFleetShield" or actionName == "ResumeFleetShield" then
			return "Fleet Shield activated."
		end
		return "Crew protection updated."
	elseif code == "no_tokens" then
		return "You do not have a shield available."
	elseif code == "no_slots" then
		return "You do not have a permanent slot available."
	elseif code == "invalid_crewmate" then
		return "That crewmate could not be found."
	elseif code == "already_protected" then
		return "That crewmate is already protected."
	elseif code == "fleet_already_active" then
		return "Fleet Shield is already active."
	elseif code == "fleet_not_active" then
		return "Fleet Shield is already off."
	elseif code == "data_unavailable" then
		return "Crew protection data is not ready yet."
	end
	return "Crew protection could not be updated."
end

local function makeResponse(player, ok, code, dataManager, actionName)
	local defaultCode = if ok then "success" else "error"
	code = tostring(code or defaultCode)
	local state = CrewProtectionService.GetClientState(player, dataManager)
	return {
		Ok = ok == true,
		Code = code,
		Action = tostring(actionName or ""),
		Message = messageForCode(code, actionName),
		State = state,
	}
end

local function isAssignedInstance(player, instanceId)
	local _, instanceData = getOwnedInstance(player, instanceId)
	if typeof(instanceData) ~= "table" then
		return false
	end

	return tostring(instanceData.AssignedStand or "") ~= ""
end

local function isTargetProtected(player, instanceId, dataManager)
	local protected, _, reason = CrewProtectionService.IsInstanceProtected(player, instanceId, dataManager)
	if protected == true then
		return true, reason
	end

	local fleetProtected = CrewProtectionService.IsFleetProtected(player, dataManager)
	if fleetProtected == true and isAssignedInstance(player, instanceId) then
		return true, "fleet_shield"
	end

	return false, "not_protected"
end

local function handleAction(player, actionName, payload, dataManager)
	if not RemoteGuard.Check(player, ACTION_REMOTE_NAME, { actionName, payload }, {
		Cooldown = 0.2,
		ActionIndex = 1,
		ActionAllowlist = ACTION_ALLOWLIST,
		Args = {
			{ Type = "string", MaxLength = 40 },
			{ Type = "table", AllowNil = true },
		},
	}) then
		return makeResponse(player, false, "error", dataManager, actionName)
	end

	payload = if typeof(payload) == "table" then payload else {}
	if actionName == "ActivateFleetShield" then
		local ok, reason = CrewProtectionService.ActivateFleetShieldFromToken(player, DAY_SECONDS, dataManager, {
			Source = "crew_management",
		})
		return makeResponse(player, ok == true, if ok == true then "success" else mapReasonToCode(reason), dataManager, actionName)
	elseif actionName == "PauseFleetShield" then
		local ok, reason = CrewProtectionService.PauseFleetShield(player, dataManager)
		return makeResponse(player, ok == true, if ok == true then "success" else mapReasonToCode(reason), dataManager, actionName)
	elseif actionName == "ResumeFleetShield" then
		local ok, reason = CrewProtectionService.ResumeFleetShield(player, dataManager, {
			Source = "crew_management",
		})
		return makeResponse(player, ok == true, if ok == true then "success" else mapReasonToCode(reason), dataManager, actionName)
	end

	local instanceId = tostring(payload.CrewMemberInstanceId or payload.InstanceId or "")
	if instanceId == "" or getOwnedInstance(player, instanceId) == nil then
		return makeResponse(player, false, "invalid_crewmate", dataManager, actionName)
	end

	local protected = isTargetProtected(player, instanceId, dataManager)
	if protected == true then
		return makeResponse(player, false, "already_protected", dataManager, actionName)
	end

	if actionName == "ApplyCrewShield" then
		local ok, reason = CrewProtectionService.AssignCrewShield(player, instanceId, DAY_SECONDS, dataManager)
		return makeResponse(player, ok == true, if ok == true then "success" else mapReasonToCode(reason), dataManager, actionName)
	elseif actionName == "ApplyPermanentSlot" then
		local ok, reason = CrewProtectionService.AssignNextPermanentSlot(player, instanceId, dataManager)
		return makeResponse(player, ok == true, if ok == true then "success" else mapReasonToCode(reason), dataManager, actionName)
	end

	return makeResponse(player, false, "error", dataManager, actionName)
end

function CrewProtectionService.Start(dataManager)
	if started then
		return
	end
	started = true

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local actionRemote = getOrCreateRemoteFunction(remotes, ACTION_REMOTE_NAME)
	actionRemote.OnServerInvoke = function(player, actionName, payload)
		local ok, response = pcall(handleAction, player, actionName, payload, dataManager)
		if ok and typeof(response) == "table" then
			return response
		end
		warn(string.format("[CrewProtectionService] action failed for %s: %s", player and player.Name or "<nil>", tostring(response)))
		return makeResponse(player, false, "error", dataManager)
	end
end

Players.PlayerRemoving:Connect(function(player)
	if DataManagerModule == nil then
		return
	end
	local profile = DataManagerModule:TryGetProfile(player)
	if profile and typeof(profile.Data) == "table" then
		ensureData(profile.Data)
	end
end)

return CrewProtectionService
