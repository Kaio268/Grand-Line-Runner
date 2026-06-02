local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService:WaitForChild("Framework"):WaitForChild("ProfileStore"))
local GetTemplate = require(script.Parent:WaitForChild("DataManager"):WaitForChild("GetTemplate"))

local DataRecoveryService = {}

local MAX_SUMMARY_KEYS = 24
local RECOVERY_AUDIT_STORE_NAME = "__DataRecoveryAudit"
local RECOVERY_AUDIT_KEY = "Events"

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local cloned = {}
	for key, nestedValue in pairs(value) do
		cloned[key] = cloneValue(nestedValue)
	end
	return cloned
end

local function fnvFingerprint(value)
	local text = tostring(value or "")
	local hash = 2166136261
	for index = 1, #text do
		hash = bit32.bxor(hash, string.byte(text, index))
		hash = (hash * 16777619) % 4294967296
	end
	return string.format("fnv1a32:%08x", hash)
end

local function keyFingerprint(value)
	return fnvFingerprint(value)
end

local function safeNumber(value)
	local numberValue = tonumber(value)
	if numberValue == nil or numberValue ~= numberValue then
		return 0
	end
	return numberValue
end

local function countDictionaryKeys(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count
end

local function summarizeProfileData(data)
	if typeof(data) ~= "table" then
		return {
			Exists = false,
			RootKeyCount = 0,
		}
	end

	local rootKeys = {}
	for key in pairs(data) do
		rootKeys[#rootKeys + 1] = tostring(key)
	end
	table.sort(rootKeys)

	local clippedRootKeys = {}
	for index = 1, math.min(#rootKeys, MAX_SUMMARY_KEYS) do
		clippedRootKeys[index] = rootKeys[index]
	end

	local leaderstats = if typeof(data.leaderstats) == "table" then data.leaderstats else {}
	local hiddenLeaderstats = if typeof(data.HiddenLeaderstats) == "table" then data.HiddenLeaderstats else {}
	local totalStats = if typeof(data.TotalStats) == "table" then data.TotalStats else {}
	local inventory = if typeof(data.Inventory) == "table" then data.Inventory else {}
	local crewInventory = if typeof(data.CrewMemberInventory) == "table" then data.CrewMemberInventory else {}
	local unopenedChests = if typeof(data.UnopenedChests) == "table" then data.UnopenedChests else {}
	local afk = if typeof(data.AFK) == "table" then data.AFK else {}

	return {
		Exists = true,
		RootKeyCount = #rootKeys,
		RootKeys = clippedRootKeys,
		LeaderstatsBeli = safeNumber(leaderstats.Beli or leaderstats.Doubloons or leaderstats.Money),
		LeaderstatsBounty = safeNumber(leaderstats.Bounty),
		PlotUpgrade = safeNumber(hiddenLeaderstats.PlotUpgrade),
		Speed = safeNumber(hiddenLeaderstats.Speed),
		Rebirths = safeNumber(hiddenLeaderstats.Rebirths or hiddenLeaderstats.Rebirth),
		TotalBeli = safeNumber(totalStats.TotalBeli or totalStats.TotalDoubloons or totalStats.TotalMoney),
		TimePlayed = safeNumber(totalStats.TimePlayed),
		InventoryKeyCount = countDictionaryKeys(inventory),
		CrewInventoryType = typeof(crewInventory),
		UnopenedChestOrderCount = if typeof(unopenedChests.Order) == "table" then #unopenedChests.Order else 0,
		AFKSchemaVersion = safeNumber(afk.SchemaVersion),
	}
end

local function summarizeProfile(profile)
	if profile == nil then
		return {
			Exists = false,
			Data = summarizeProfileData(nil),
		}
	end

	local data = if typeof(profile.Data) == "table" then profile.Data else nil
	local summary = {
		Exists = true,
		Key = profile.Key,
		FirstSessionTime = profile.FirstSessionTime or 0,
		SessionLoadCount = profile.SessionLoadCount or 0,
		UserIdCount = if typeof(profile.UserIds) == "table" then #profile.UserIds else 0,
		Data = summarizeProfileData(data),
	}

	if data ~= nil then
		summary.InventoryKeyCount = countDictionaryKeys(data.Inventory)
		summary.CrewInventoryKeyCount = countDictionaryKeys(data.CrewMemberInventory)
		summary.PassesKeyCount = countDictionaryKeys(data.Passes)
	end

	return summary
end

local function getProfileKey(userId)
	return string.format("Player_%d", userId)
end

local function getStore(storeName)
	return ProfileStore.New(storeName, GetTemplate)
end

local function readProfile(storeName, profileKey)
	local store = getStore(storeName)
	local ok, profile = pcall(function()
		return store:GetAsync(profileKey)
	end)
	if not ok then
		return nil, tostring(profile)
	end
	return profile, nil
end

local function readNewestVersion(storeName, profileKey)
	local store = getStore(storeName)
	local ok, profile = pcall(function()
		local query = store:VersionQuery(profileKey, Enum.SortDirection.Descending)
		return query:NextAsync()
	end)
	if not ok then
		return nil, tostring(profile)
	end
	return profile, nil
end

local function appendAuditEvent(event)
	local auditStore = ProfileStore.New(RECOVERY_AUDIT_STORE_NAME, {
		Events = {},
	})
	local profile = auditStore:StartSessionAsync(RECOVERY_AUDIT_KEY, {
		Steal = true,
	})
	if profile == nil then
		return false, "audit_profile_unavailable"
	end

	profile:Reconcile()
	if typeof(profile.Data.Events) ~= "table" then
		profile.Data.Events = {}
	end

	table.insert(profile.Data.Events, event)
	while #profile.Data.Events > 200 do
		table.remove(profile.Data.Events, 1)
	end

	profile:EndSession()
	return true, nil
end

function DataRecoveryService.GetStoreFingerprint(storeName)
	return {
		Length = #tostring(storeName or ""),
		Fingerprint = keyFingerprint(storeName),
	}
end

function DataRecoveryService.DryRun(options)
	options = options or {}
	local userId = tonumber(options.UserId or options.userId)
	if userId == nil or userId <= 0 or userId % 1 ~= 0 then
		return {
			Success = false,
			Error = "invalid_user_id",
		}
	end

	local sourceStoreName = tostring(options.SourceStoreName or options.sourceStoreName or "")
	local targetStoreName = tostring(options.TargetStoreName or options.targetStoreName or "")
	if sourceStoreName == "" or targetStoreName == "" then
		return {
			Success = false,
			Error = "missing_store_name",
		}
	end

	local profileKey = getProfileKey(userId)
	local sourceProfile, sourceError = readProfile(sourceStoreName, profileKey)
	local targetProfile, targetError = readProfile(targetStoreName, profileKey)
	local sourceVersion, sourceVersionError = readNewestVersion(sourceStoreName, profileKey)
	local targetVersion, targetVersionError = readNewestVersion(targetStoreName, profileKey)

	return {
		Success = true,
		Mode = "dry-run",
		UserId = userId,
		ProfileKey = profileKey,
		Source = {
			Store = DataRecoveryService.GetStoreFingerprint(sourceStoreName),
			Current = summarizeProfile(sourceProfile),
			CurrentError = sourceError,
			NewestVersion = summarizeProfile(sourceVersion),
			NewestVersionError = sourceVersionError,
		},
		Target = {
			Store = DataRecoveryService.GetStoreFingerprint(targetStoreName),
			Current = summarizeProfile(targetProfile),
			CurrentError = targetError,
			NewestVersion = summarizeProfile(targetVersion),
			NewestVersionError = targetVersionError,
		},
	}
end

function DataRecoveryService.RestoreOnePlayer(options)
	options = options or {}
	if options.Confirm ~= "RESTORE_ONE_PLAYER" then
		return {
			Success = false,
			Error = "confirmation_required",
		}
	end

	local dryRun = DataRecoveryService.DryRun(options)
	if dryRun.Success ~= true then
		return dryRun
	end

	if dryRun.Source.Current.Exists ~= true then
		return {
			Success = false,
			Error = "source_profile_missing",
			DryRun = dryRun,
		}
	end

	local userId = dryRun.UserId
	local profileKey = dryRun.ProfileKey
	local sourceStoreName = tostring(options.SourceStoreName or options.sourceStoreName or "")
	local targetStoreName = tostring(options.TargetStoreName or options.targetStoreName or "")

	local sourceProfile, sourceError = readProfile(sourceStoreName, profileKey)
	if sourceProfile == nil then
		return {
			Success = false,
			Error = "source_profile_unavailable",
			Detail = sourceError,
			DryRun = dryRun,
		}
	end

	local targetStore = getStore(targetStoreName)
	local targetProfile = targetStore:StartSessionAsync(profileKey, {
		Steal = options.Steal == true,
	})
	if targetProfile == nil then
		return {
			Success = false,
			Error = "target_profile_session_unavailable",
			DryRun = dryRun,
		}
	end

	local beforeSummary = summarizeProfile(targetProfile)
	targetProfile.Data = cloneValue(sourceProfile.Data)
	targetProfile.RobloxMetaData = cloneValue(sourceProfile.RobloxMetaData)
	targetProfile.UserIds = cloneValue(sourceProfile.UserIds)
	targetProfile:EndSession()

	local auditEvent = {
		Action = "restore_one_player",
		UserId = userId,
		ProfileKey = profileKey,
		ActorUserId = tonumber(options.ActorUserId or options.actorUserId) or 0,
		SourceStore = DataRecoveryService.GetStoreFingerprint(sourceStoreName),
		TargetStore = DataRecoveryService.GetStoreFingerprint(targetStoreName),
		Before = beforeSummary,
		After = summarizeProfile(sourceProfile),
		UnixTime = os.time(),
	}
	local auditOk, auditError = appendAuditEvent(auditEvent)

	return {
		Success = true,
		Mode = "restore-one-player",
		UserId = userId,
		ProfileKey = profileKey,
		Before = beforeSummary,
		After = summarizeProfile(sourceProfile),
		AuditWritten = auditOk,
		AuditError = auditError,
	}
end

return DataRecoveryService
