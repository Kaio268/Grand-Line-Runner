local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewStorage = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewStorage"))

local CrewStandIncomeAuthority = {}

local CANONICAL_ROOT = "CrewMemberIncome"
local AUDIT_ROOT = "CrewMemberStandIncomeAuthorityAudit"

local dataManagerModule = nil

local function getDataManager()
	if dataManagerModule == nil then
		dataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerModule
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneValue(child)
	end
	return copy
end

local function writeRoot(player, path, value)
	local dataManager = getDataManager()
	if typeof(dataManager.TrySetValue) == "function" then
		local ok, reason = dataManager:TrySetValue(player, path, value)
		return ok == true, tostring(reason or "")
	end

	dataManager:SetValue(player, path, value)
	return true, nil
end

local function getCanonicalCrewMemberId(storageName, info)
	local fallback = tostring(storageName or "")
	local canonicalId, resolvedInfo = CrewCatalog.ResolveCanonicalCrewMemberId(fallback)
	if resolvedInfo then
		return canonicalId
	end
	if typeof(info) == "table" and tostring(info.CrewMemberId or "") ~= "" then
		return tostring(info.CrewMemberId)
	end

	return ""
end

local function getDisplayName(storageName, info)
	local _, resolvedInfo = CrewCatalog.ResolveCanonicalCrewMemberId(storageName)
	if resolvedInfo then
		info = resolvedInfo
	end
	if typeof(info) == "table" then
		return tostring(info.DisplayName or info.CrewMemberName or info.Name or storageName)
	end
	return tostring(storageName or "")
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

local function normalizeStandRow(row)
	row = if typeof(row) == "table" then row else {}
	local rawCrewMemberName = firstNonEmpty(row.CrewMemberName)
	local explicitLegacyStorageName = tostring(row.LegacyStorageName or "")
	local crewMemberName, info, legacyStorageName = CrewCatalog.ResolveCanonicalCrewMemberId(rawCrewMemberName)
	legacyStorageName = firstNonEmpty(legacyStorageName, if explicitLegacyStorageName ~= crewMemberName then explicitLegacyStorageName else "")
	local legacyOnly = rawCrewMemberName == "" and explicitLegacyStorageName ~= ""
	local hasInvalidCrewMember = (rawCrewMemberName ~= "" and info == nil) or legacyOnly
	if hasInvalidCrewMember then
		crewMemberName = ""
	end
	local crewMemberInstanceId = if hasInvalidCrewMember then "" else firstNonEmpty(row.CrewMemberInstanceId)
	return {
		CrewMemberName = crewMemberName,
		CrewMemberInstanceId = crewMemberInstanceId,
		IncomeToCollect = tonumber(row.IncomeToCollect) or 0,
		StandLevel = math.max(1, math.floor(tonumber(row.StandLevel) or 1)),
		LegacyStorageName = legacyStorageName,
		NeedsCanonicalRepair = rawCrewMemberName ~= "" and crewMemberName ~= "" and rawCrewMemberName ~= crewMemberName,
		HasInvalidCrewMember = hasInvalidCrewMember,
		QuarantinedCrewMemberName = if hasInvalidCrewMember then firstNonEmpty(rawCrewMemberName, explicitLegacyStorageName) else "",
	}
end

local function standRowFromCanonicalRow(row)
	row = if typeof(row) == "table" then row else {}
	return normalizeStandRow({
		CrewMemberName = firstNonEmpty(row.CrewMemberName),
		LegacyStorageName = row.LegacyStorageName,
		CrewMemberInstanceId = firstNonEmpty(row.CrewMemberInstanceId),
		IncomeToCollect = row.IncomeToCollect,
		StandLevel = row.StandLevel,
	})
end

local function canonicalFromStandRow(player, standName, standRow)
	standRow = normalizeStandRow(standRow)
	local storageName = tostring(standRow.CrewMemberName or "")
	local _, info = CrewCatalog.ResolveCanonicalCrewMemberId(storageName)
	local legacyStorageName = tostring(standRow.LegacyStorageName or "")
	local existing = getDataManager():GetValue(player, CANONICAL_ROOT .. "." .. tostring(standName or ""))
	local existingLevel = if typeof(existing) == "table" then tonumber(existing.StandLevel) else nil
	local standLevel = math.max(1, math.floor(tonumber(standRow.StandLevel) or existingLevel or 1))
	if storageName == "" and tostring(standRow.CrewMemberInstanceId or "") == "" then
		standLevel = 1
	end

	return {
		CrewMemberName = if storageName ~= "" then getCanonicalCrewMemberId(storageName, info) else "",
		CrewMemberDisplayName = if storageName ~= "" then getDisplayName(storageName, info) else "",
		CrewMemberInstanceId = tostring(standRow.CrewMemberInstanceId or ""),
		LegacyStorageName = legacyStorageName,
		IncomeToCollect = if standRow.HasInvalidCrewMember == true then 0 else tonumber(standRow.IncomeToCollect) or 0,
		StandLevel = standLevel,
		QuarantinedCrewMemberName = tostring(standRow.QuarantinedCrewMemberName or ""),
		QuarantineReason = if standRow.HasInvalidCrewMember == true then "unknown_crew_member_id" else nil,
	}
end

local function updateAudit(player, updates)
	local dataManager = getDataManager()
	local audit = dataManager:GetValue(player, AUDIT_ROOT)
	if typeof(audit) ~= "table" then
		audit = {}
	else
		audit = cloneValue(audit)
	end

	for key, value in pairs(if typeof(updates) == "table" then updates else {}) do
		audit[key] = value
	end
	audit.UpdatedAt = os.time()
	pcall(function()
		dataManager:SetValue(player, AUDIT_ROOT, audit)
	end)
	return audit
end

local function restoreSnapshot(player, snapshot, reason)
	if typeof(snapshot) ~= "table" then
		return false, "snapshot_missing"
	end

	local canonicalOk, canonicalReason = writeRoot(player, CANONICAL_ROOT, cloneValue(snapshot.Canonical) or {})
	if canonicalOk ~= true then
		return false, "rollback_write_failed:" .. tostring(canonicalReason)
	end

	updateAudit(player, {
		LastRollback = {
			Reason = tostring(reason or ""),
			CompletedAt = os.time(),
		},
	})
	return true, nil
end

local function buildSnapshot(player)
	local dataManager = getDataManager()
	return {
		Kind = "stand_income_write_authority",
		PlayerUserId = player and player.UserId or 0,
		PlaceId = game.PlaceId,
		GameId = game.GameId,
		CreatedAt = os.time(),
		Canonical = cloneValue(dataManager:GetValue(player, CANONICAL_ROOT)),
	}
end

local function compareRows(standRow, canonicalRow)
	local expected = normalizeStandRow(standRow)

	if typeof(canonicalRow) ~= "table" then
		return false, "canonical_missing"
	end
	local expectedCrewMemberName = tostring((CrewCatalog.ResolveCanonicalCrewMemberId(expected.CrewMemberName)))
	if tostring(canonicalRow.CrewMemberName or "") ~= expectedCrewMemberName then
		return false, "storage_mismatch"
	end
	if tostring(canonicalRow.CrewMemberInstanceId or "") ~= tostring(expected.CrewMemberInstanceId or "") then
		return false, "instance_mismatch"
	end
	if math.floor(tonumber(canonicalRow.IncomeToCollect) or 0) ~= math.floor(tonumber(expected.IncomeToCollect) or 0) then
		return false, "income_mismatch"
	end
	if math.floor(tonumber(canonicalRow.StandLevel) or 1) ~= math.floor(tonumber(expected.StandLevel) or 1) then
		return false, "stand_level_mismatch"
	end
	return true, nil
end

function CrewStandIncomeAuthority.IsWriteAuthorityEnabled(flags)
	flags = if typeof(flags) == "table" then flags else CrewStorage.GetShadowFlags()
	return flags.CrewMemberStandIncomeWriteAuthorityEnabled == true, flags
end

function CrewStandIncomeAuthority.EnsureWriteAuthorityReady(player, sourcePath)
	local enabled, flags = CrewStandIncomeAuthority.IsWriteAuthorityEnabled()
	if enabled ~= true then
		return true, nil
	end

	local blockingFlag = nil
	if flags.CrewMemberCanonicalReadEnabled == true then
		blockingFlag = "canonical_read_enabled"
	elseif flags.CrewMemberCanaryGameplayReadsEnabled == true then
		blockingFlag = "gameplay_reads_enabled"
	elseif flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		blockingFlag = "profile_migration_write_enabled"
	elseif flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		blockingFlag = "broad_write_authority_enabled"
	elseif flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		blockingFlag = "quick_slots_write_authority_enabled"
	elseif flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true then
		blockingFlag = "product_quick_slot_write_authority_enabled"
	end

	if blockingFlag ~= nil then
		updateAudit(player, {
			LastFailClosedReason = blockingFlag,
			LastFailClosedSourcePath = tostring(sourcePath or ""),
		})
		return false, blockingFlag
	end

	return true, nil
end

function CrewStandIncomeAuthority.GetStandData(player, standName)
	standName = tostring(standName or "")
	local dataManager = getDataManager()
	local canonicalRow = dataManager:GetValue(player, CANONICAL_ROOT .. "." .. standName)
	if typeof(canonicalRow) == "table" then
		return standRowFromCanonicalRow(canonicalRow), {
			UsedCanonical = true,
			CanonicalRow = canonicalRow,
		}
	end

	return normalizeStandRow(nil), {
		UsedCanonical = false,
		MissingCanonical = true,
	}
end

function CrewStandIncomeAuthority.SetStandData(player, standName, standRow, sourcePath)
	standName = tostring(standName or "")
	local normalizedStandRow = normalizeStandRow(standRow)
	local snapshot = buildSnapshot(player)
	local canonicalRow = canonicalFromStandRow(player, standName, normalizedStandRow)
	updateAudit(player, {
		LastRollbackSnapshot = snapshot,
		LastMutation = {
			SourcePath = tostring(sourcePath or ""),
			StandName = standName,
			StartedAt = os.time(),
		},
	})

	local canonicalOk, canonicalReason = writeRoot(player, CANONICAL_ROOT .. "." .. standName, canonicalRow)
	if canonicalOk ~= true then
		restoreSnapshot(player, snapshot, "canonical_write_failed")
		updateAudit(player, { LastFailClosedReason = "stand_income_write_failed:canonical:" .. tostring(canonicalReason) })
		return false, "stand_income_write_failed:canonical:" .. tostring(canonicalReason)
	end

	local persistedCanonical = getDataManager():GetValue(player, CANONICAL_ROOT .. "." .. standName)
	local expectedPersistedStandRow = standRowFromCanonicalRow(canonicalRow)
	local mirrorOk, mirrorReason = compareRows(expectedPersistedStandRow, persistedCanonical)
	if mirrorOk ~= true then
		local restoreOk, restoreReason = restoreSnapshot(player, snapshot, "post_validation_failed")
		updateAudit(player, {
			LastFailClosedReason = "stand_income_post_validation_failed:" .. tostring(mirrorReason),
			LastRollbackRestoreOk = restoreOk,
			LastRollbackRestoreReason = restoreReason,
		})
		return false, "stand_income_post_validation_failed:" .. tostring(mirrorReason)
	end

	updateAudit(player, {
		LastMutation = {
			SourcePath = tostring(sourcePath or ""),
			StandName = standName,
			CompletedAt = os.time(),
			MirrorMatch = true,
		},
		LastFailClosedReason = nil,
	})
	return true, nil
end

function CrewStandIncomeAuthority.UpdateStandData(player, standName, updates, sourcePath)
	local row = CrewStandIncomeAuthority.GetStandData(player, standName)
	for key, value in pairs(if typeof(updates) == "table" then updates else {}) do
		row[key] = value
	end
	return CrewStandIncomeAuthority.SetStandData(player, standName, row, sourcePath)
end

function CrewStandIncomeAuthority.SetIncomeToCollect(player, standName, value, sourcePath)
	return CrewStandIncomeAuthority.UpdateStandData(player, standName, {
		IncomeToCollect = tonumber(value) or 0,
	}, sourcePath)
end

function CrewStandIncomeAuthority.AdjustIncomeToCollect(player, standName, delta, sourcePath)
	local row = CrewStandIncomeAuthority.GetStandData(player, standName)
	row.IncomeToCollect = (tonumber(row.IncomeToCollect) or 0) + (tonumber(delta) or 0)
	return CrewStandIncomeAuthority.SetStandData(player, standName, row, sourcePath)
end

function CrewStandIncomeAuthority.GetStandLevel(player, standName)
	local row = CrewStandIncomeAuthority.GetStandData(player, standName)
	return math.max(1, math.floor(tonumber(row and row.StandLevel) or 1))
end

function CrewStandIncomeAuthority.SetStandLevel(player, standName, level, sourcePath)
	return CrewStandIncomeAuthority.UpdateStandData(player, standName, {
		StandLevel = math.max(1, math.floor(tonumber(level) or 1)),
	}, sourcePath or "stand_level_update")
end

function CrewStandIncomeAuthority.ClearStandData(player, standName, sourcePath)
	return CrewStandIncomeAuthority.SetStandData(player, standName, {
		CrewMemberName = "",
		CrewMemberInstanceId = "",
		IncomeToCollect = 0,
		StandLevel = 1,
	}, sourcePath or "stand_clear")
end

function CrewStandIncomeAuthority.GetAllStandData(player)
	local dataManager = getDataManager()
	local result = {}
	local canonical = dataManager:GetValue(player, CANONICAL_ROOT)
	if typeof(canonical) == "table" then
		for standName, row in pairs(canonical) do
			if typeof(row) == "table" then
				result[tostring(standName)] = standRowFromCanonicalRow(row)
			end
		end
	end

	return result
end

function CrewStandIncomeAuthority.EnsureStandRow(player, standName, sourcePath)
	local row = CrewStandIncomeAuthority.GetStandData(player, standName)
	return CrewStandIncomeAuthority.SetStandData(player, standName, row, sourcePath or "ensure_stand_row")
end

return CrewStandIncomeAuthority
