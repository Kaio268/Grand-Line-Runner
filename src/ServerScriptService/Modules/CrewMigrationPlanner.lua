local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))
local CrewProfileSchema = require(script.Parent:WaitForChild("CrewProfileSchema"))

local CrewMigrationPlanner = {}

local RETIRED_REASON = "legacy_migration_tooling_retired"
local CANONICAL_QUICK_SLOT_PATH = "CrewMemberQuickSlots"

CrewMigrationPlanner.AuditDataStoreName = "CrewMemberMigrationAudit_retired"

local dataManagerCache = nil
local diagnosticSnapshotsByUserId = {}
local migrationWritePreviewsByUserId = {}

local function getDataManager()
	if dataManagerCache == nil then
		dataManagerCache = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerCache
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local cloned = {}
	for key, nested in pairs(value) do
		cloned[cloneValue(key)] = cloneValue(nested)
	end
	return cloned
end

local function getPlayer(source)
	if typeof(source) == "Instance" and source:IsA("Player") then
		return source
	end
	return nil
end

local function getRoot(source)
	if typeof(source) == "table" and typeof(source.Data) == "table" then
		return source.Data
	end
	if typeof(source) == "table" then
		return source
	end
	return nil
end

local function getUserId(source)
	local player = getPlayer(source)
	if player then
		return player.UserId
	end
	return 0
end

local function normalizeQuickSlots(raw)
	raw = if typeof(raw) == "table" then raw else {}
	local maxSlots = CrewQuickSlotConfig.MaxSlots
	return {
		SchemaVersion = CrewProfileSchema.SchemaVersion,
		UnlockedSlots = CrewQuickSlotConfig.ClampUnlockedSlots(raw.UnlockedSlots),
		MaxSlots = maxSlots,
	}
end

local function readReplicatedQuickSlots(player)
	local folder = player and player:FindFirstChild(CANONICAL_QUICK_SLOT_PATH)
	if not folder then
		return nil
	end

	local unlocked = folder:FindFirstChild("UnlockedSlots")
	local maxSlots = folder:FindFirstChild("MaxSlots")
	return normalizeQuickSlots({
		UnlockedSlots = unlocked and unlocked:IsA("ValueBase") and unlocked.Value or nil,
		MaxSlots = maxSlots and maxSlots:IsA("ValueBase") and maxSlots.Value or nil,
	})
end

local function readCanonicalQuickSlots(source)
	local player = getPlayer(source)
	if player then
		local ok, value = pcall(function()
			return getDataManager():GetValue(player, CANONICAL_QUICK_SLOT_PATH)
		end)
		if ok and typeof(value) == "table" then
			return normalizeQuickSlots(value)
		end

		local replicated = readReplicatedQuickSlots(player)
		if replicated ~= nil then
			return replicated
		end
	end

	local root = getRoot(source)
	if typeof(root) == "table" then
		return normalizeQuickSlots(root[CANONICAL_QUICK_SLOT_PATH])
	end

	return normalizeQuickSlots(nil)
end

local function writeCanonicalQuickSlots(source, slots)
	local player = getPlayer(source)
	if player then
		local ok, reason = getDataManager():SetValue(player, CANONICAL_QUICK_SLOT_PATH, slots)
		return ok == true, tostring(reason or "")
	end

	local root = getRoot(source)
	if typeof(root) == "table" then
		root[CANONICAL_QUICK_SLOT_PATH] = cloneValue(slots)
		return true, ""
	end

	return false, "player_or_profile_source_required"
end

local function buildCleanCompareReport(label)
	return {
		Passed = true,
		CanProceed = true,
		BlockingCount = 0,
		UnclassifiedCount = 0,
		MismatchCountsByCategory = {},
		NoGoReasons = {},
		Retired = true,
		Reason = RETIRED_REASON,
		Summary = tostring(label or "migrationCompare") .. " retired canonicalOnly=true blocking=0 unclassified=0",
	}
end

local function buildRetiredStoreResult(label)
	return {
		Ok = false,
		Missing = true,
		Reason = RETIRED_REASON,
		StoreName = CrewMigrationPlanner.AuditDataStoreName,
		Key = tostring(label or RETIRED_REASON),
		Summary = tostring(label or "migrationAudit") .. " retired reason=" .. RETIRED_REASON,
	}
end

local function printSummary(prefix, value)
	print("[CrewMigrationPlanner] " .. tostring(prefix or "retired") .. " " .. tostring(value and value.Summary or RETIRED_REASON))
end

function CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, _options)
	local canonical = readCanonicalQuickSlots(source)
	local configMin = CrewQuickSlotConfig.DefaultUnlockedSlots
	local configMax = CrewQuickSlotConfig.MaxSlots
	local inBounds = canonical.UnlockedSlots >= configMin
		and canonical.UnlockedSlots <= configMax
		and canonical.MaxSlots == configMax

	return {
		Passed = inBounds,
		Retired = true,
		Reason = RETIRED_REASON,
		Canonical = canonical,
		LegacyQuickSlots = cloneValue(canonical),
		LegacyQuickSlotsSynthetic = true,
		RootsMatch = true,
		PrimaryContentsMatch = true,
		ConfigValid = true,
		CanonicalValid = true,
		LegacyQuickSlotsValid = true,
		CanonicalInBounds = inBounds,
		LegacyQuickSlotsInBounds = inBounds,
		ConfigMinSlots = configMin,
		ConfigMaxSlots = configMax,
		Summary = string.format(
			"quickSlotsCanonicalStatus retired=%s canonical=%d/%d inBounds=%s",
			tostring(true),
			canonical.UnlockedSlots,
			canonical.MaxSlots,
			tostring(inBounds)
		),
	}
end

function CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
	printSummary("quickSlotsCanonicalStatus", status)
end

function CrewMigrationPlanner.ExecuteQuickSlotsWriteAuthoritySet(source, requestedCount, options)
	options = if typeof(options) == "table" then options else {}
	local before = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, options)
	local target = normalizeQuickSlots({
		UnlockedSlots = requestedCount,
		MaxSlots = before.Canonical and before.Canonical.MaxSlots or CrewQuickSlotConfig.MaxSlots,
	})
	local ok, reason = writeCanonicalQuickSlots(source, target)
	local postStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, options)
	local postCompare = buildCleanCompareReport("quickSlotsCanonicalSetCompare")
	local passed = ok == true
		and postStatus.Canonical ~= nil
		and postStatus.Canonical.UnlockedSlots == target.UnlockedSlots
		and postStatus.Canonical.MaxSlots == target.MaxSlots

	return {
		Passed = passed,
		Retired = true,
		Reason = if passed then RETIRED_REASON else tostring(reason or "canonical_quick_slot_write_failed"),
		CanonicalBecameMutationSource = true,
		LegacyDualWriteMatched = true,
		PreStatus = before,
		PostStatus = postStatus,
		PostCompare = postCompare,
		NoGoReasons = if passed then {} else { tostring(reason or "canonical_quick_slot_write_failed") },
		Writes = {
			{
				Root = CANONICAL_QUICK_SLOT_PATH,
				Ok = ok == true,
				Reason = reason,
			},
		},
		Summary = string.format(
			"quickSlotsCanonicalSet passed=%s target=%d/%d reason=%s",
			tostring(passed),
			target.UnlockedSlots,
			target.MaxSlots,
			if passed then RETIRED_REASON else tostring(reason or "canonical_quick_slot_write_failed")
		),
	}
end

function CrewMigrationPlanner.ExecuteProductQuickSlotsWriteAuthoritySet(source, targetCount, options)
	return CrewMigrationPlanner.ExecuteQuickSlotsWriteAuthoritySet(source, targetCount, options)
end

function CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityResult(result)
	printSummary("quickSlotsCanonicalSet", result)
end

function CrewMigrationPlanner.BuildDryRunProjection(source)
	local root = getRoot(source) or {}
	local projection = CrewProfileSchema.NewProjection()
	local indexCollection = if typeof(root[CrewProfileSchema.Keys.IndexCollection]) == "table"
		then root[CrewProfileSchema.Keys.IndexCollection]
		else nil

	if typeof(root[CrewProfileSchema.Keys.Inventory]) == "table" then
		projection[CrewProfileSchema.Keys.Inventory] = cloneValue(root[CrewProfileSchema.Keys.Inventory])
	end
	if typeof(root[CrewProfileSchema.Keys.QuickSlots]) == "table" then
		projection[CrewProfileSchema.Keys.QuickSlots] = cloneValue(root[CrewProfileSchema.Keys.QuickSlots])
	end
	if typeof(root[CrewProfileSchema.Keys.Income]) == "table" then
		projection[CrewProfileSchema.Keys.Income] = cloneValue(root[CrewProfileSchema.Keys.Income])
	end
	if indexCollection and typeof(indexCollection[CrewProfileSchema.Keys.Index]) == "table" then
		projection[CrewProfileSchema.Keys.IndexCollection][CrewProfileSchema.Keys.Index] =
			cloneValue(indexCollection[CrewProfileSchema.Keys.Index])
	end

	projection.Metadata = {
		Retired = true,
		Reason = RETIRED_REASON,
		UnknownLegacyIds = {},
		CompatibilityOnlyLegacyIds = {},
		BrookFallbackCount = 0,
	}
	return projection
end

function CrewMigrationPlanner.CompareLegacyToCrewMemberProjection(_source, _projection)
	return {
		Issues = {},
		Retired = true,
		Reason = RETIRED_REASON,
		Summary = "legacyProjectionCompare retired canonicalOnly=true issues=0",
	}
end

function CrewMigrationPlanner.ValidateStandConsistency(_source)
	return {
		Issues = {},
		Retired = true,
		Reason = RETIRED_REASON,
		Summary = "standConsistency retired canonicalOnly=true issues=0",
	}
end

function CrewMigrationPlanner.DetectDuplicateInstances(_source)
	return {
		Issues = {},
		Retired = true,
		Reason = RETIRED_REASON,
		Summary = "duplicateInstanceScan retired canonicalOnly=true issues=0",
	}
end

function CrewMigrationPlanner.BuildReadinessReport(source)
	local projection = CrewMigrationPlanner.BuildDryRunProjection(source)
	local inventory = projection[CrewProfileSchema.Keys.Inventory]
	local byId = if typeof(inventory) == "table" then inventory.ById else nil
	local projectedCount = 0
	if typeof(byId) == "table" then
		for _ in pairs(byId) do
			projectedCount += 1
		end
	end

	return {
		Retired = true,
		Reason = RETIRED_REASON,
		MigrationStatus = "retired_canonical_only",
		LegacyInstanceCount = 0,
		ProjectedCrewMemberInstanceCount = projectedCount,
		Diff = {
			Issues = {},
			Summary = "readiness retired canonicalOnly=true",
		},
		Summary = string.format(
			"readiness retired canonicalOnly=true projectedCrewMembers=%d",
			projectedCount
		),
	}
end

function CrewMigrationPlanner.BuildMigrationCompareReport(_source, _options)
	return buildCleanCompareReport("migrationCompare")
end

function CrewMigrationPlanner.PrintMigrationCompareReport(report)
	printSummary("migrationCompare", report)
end

function CrewMigrationPlanner.BuildMigrationSnapshot(source, _options)
	return {
		Retired = true,
		Reason = RETIRED_REASON,
		UserId = getUserId(source),
		Canonical = {
			CrewMemberQuickSlots = readCanonicalQuickSlots(source),
		},
		Legacy = {},
		BlockingCount = 0,
		UnclassifiedCount = 0,
		Summary = "migrationSnapshot retired canonicalOnly=true",
	}
end

function CrewMigrationPlanner.StoreDiagnosticSnapshot(source, snapshot)
	diagnosticSnapshotsByUserId[getUserId(source)] = cloneValue(snapshot)
	return true
end

function CrewMigrationPlanner.GetDiagnosticSnapshot(source)
	return diagnosticSnapshotsByUserId[getUserId(source)]
end

function CrewMigrationPlanner.ClearDiagnosticSnapshot(source)
	local userId = getUserId(source)
	local hadSnapshot = diagnosticSnapshotsByUserId[userId] ~= nil
	diagnosticSnapshotsByUserId[userId] = nil
	return hadSnapshot
end

function CrewMigrationPlanner.BuildMigrationDryRunReport()
	return buildCleanCompareReport("migrationDryRun")
end

function CrewMigrationPlanner.PrintMigrationDryRunReport(report)
	printSummary("migrationDryRun", report)
end

function CrewMigrationPlanner.BuildCompatibilityReviewReport()
	return buildCleanCompareReport("compatibilityReview")
end

function CrewMigrationPlanner.PrintCompatibilityReviewReport(report)
	printSummary("compatibilityReview", report)
end

function CrewMigrationPlanner.BuildCompatibilityCleanupPlan()
	return {
		Passed = true,
		Retired = true,
		Actions = {},
		Summary = "compatibilityCleanupPlan retired canonicalOnly=true actions=0",
	}
end

function CrewMigrationPlanner.PrintCompatibilityCleanupPlan(plan)
	printSummary("compatibilityCleanupPlan", plan)
end

function CrewMigrationPlanner.ExecuteCompatibilityCleanup()
	return {
		Passed = true,
		Retired = true,
		Writes = {},
		Summary = "compatibilityCleanup retired canonicalOnly=true writes=0",
	}
end

function CrewMigrationPlanner.PrintCompatibilityCleanupResult(result)
	printSummary("compatibilityCleanup", result)
end

function CrewMigrationPlanner.BuildMigrationSaveLoadReport()
	return buildCleanCompareReport("migrationSaveLoad")
end

function CrewMigrationPlanner.PrintMigrationSaveLoadReport(report)
	printSummary("migrationSaveLoad", report)
end

function CrewMigrationPlanner.BuildMigrationAuditReport(_source, label)
	return {
		CanSave = false,
		Retired = true,
		NoGoReasons = { RETIRED_REASON },
		Report = buildCleanCompareReport("migrationAudit"),
		Summary = tostring(label or "migrationAudit") .. " retired reason=" .. RETIRED_REASON,
	}
end

function CrewMigrationPlanner.PrintMigrationAuditReport(_label, report)
	printSummary("migrationAudit", report)
end

function CrewMigrationPlanner.SaveMigrationAuditBefore()
	return buildRetiredStoreResult("migrationAuditBefore")
end

function CrewMigrationPlanner.SaveMigrationAuditAfter()
	return buildRetiredStoreResult("migrationAuditAfter")
end

function CrewMigrationPlanner.LoadMigrationAudit()
	return buildRetiredStoreResult("migrationAuditLoad")
end

function CrewMigrationPlanner.ClearMigrationAudit()
	return buildRetiredStoreResult("migrationAuditClear")
end

function CrewMigrationPlanner.CompareMigrationAuditReports()
	return {
		Passed = false,
		Retired = true,
		Mismatches = {},
		Reason = RETIRED_REASON,
		Summary = "migrationAuditCompare retired reason=" .. RETIRED_REASON,
	}
end

function CrewMigrationPlanner.PrintMigrationAuditComparison(comparison)
	printSummary("migrationAuditCompare", comparison)
end

function CrewMigrationPlanner.BuildMigrationWritePreviewReport()
	return {
		CanWritePreview = false,
		CanWriteMigration = false,
		NoGoReasons = { RETIRED_REASON },
		Diff = {},
		Retired = true,
		Summary = "migrationWritePreview retired reason=" .. RETIRED_REASON,
	}
end

function CrewMigrationPlanner.PrintMigrationWritePreviewReport(report)
	printSummary("migrationWritePreview", report)
end

function CrewMigrationPlanner.StoreMigrationWritePreview(source, preview)
	migrationWritePreviewsByUserId[getUserId(source)] = cloneValue(preview)
	return true
end

function CrewMigrationPlanner.GetMigrationWritePreview(source)
	return migrationWritePreviewsByUserId[getUserId(source)]
end

function CrewMigrationPlanner.ClearMigrationWritePreview(source)
	local userId = getUserId(source)
	local hadPreview = migrationWritePreviewsByUserId[userId] ~= nil
	migrationWritePreviewsByUserId[userId] = nil
	return hadPreview
end

function CrewMigrationPlanner.SaveMigrationWritePreview()
	return buildRetiredStoreResult("migrationWritePreviewSave")
end

function CrewMigrationPlanner.LoadMigrationWritePreview()
	return buildRetiredStoreResult("migrationWritePreviewLoad")
end

function CrewMigrationPlanner.ClearMigrationWritePreviewAudit()
	return buildRetiredStoreResult("migrationWritePreviewClear")
end

function CrewMigrationPlanner.BuildSampledMigrationWritePreview()
	return CrewMigrationPlanner.BuildMigrationWritePreviewReport(), buildCleanCompareReport("sampledMigrationCompare")
end

function CrewMigrationPlanner.SaveAndVerifySampledMigrationRollback()
	return buildRetiredStoreResult("sampledMigrationRollbackSave"), buildRetiredStoreResult("sampledMigrationRollbackLoad")
end

function CrewMigrationPlanner.ExecuteSampledMigrationWrite()
	return {
		Passed = false,
		Retired = true,
		Writes = {},
		NoGoReasons = { RETIRED_REASON },
		Summary = "sampledMigrationWrite retired reason=" .. RETIRED_REASON,
	}
end

function CrewMigrationPlanner.PrintSampledMigrationWriteReport(result)
	printSummary("sampledMigrationWrite", result)
end

function CrewMigrationPlanner.LoadMigrationRollbackStatus()
	return buildRetiredStoreResult("migrationRollbackStatus")
end

function CrewMigrationPlanner.ExecuteMigrationRollbackLatest()
	return {
		Passed = false,
		Retired = true,
		Writes = {},
		LoadResult = buildRetiredStoreResult("migrationRollbackLatest"),
		NoGoReasons = { RETIRED_REASON },
		Summary = "migrationRollbackLatest retired reason=" .. RETIRED_REASON,
	}
end

function CrewMigrationPlanner.PrintMigrationRollbackReport(result)
	printSummary("migrationRollback", result)
end

function CrewMigrationPlanner.GetRetiredReason()
	return RETIRED_REASON
end

return CrewMigrationPlanner
