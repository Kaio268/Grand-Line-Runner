local CrewMigrationPlanner = require(script.Parent:WaitForChild("CrewMigrationPlanner"))
local CrewProfileSchema = require(script.Parent:WaitForChild("CrewProfileSchema"))
local CrewStorage = require(script.Parent:WaitForChild("CrewStorage"))
local CrewMemberShadowConfig = require(script.Parent:WaitForChild("CrewMemberShadowConfig"))

local CrewMemberShadowWriter = {}

local LOG_PREFIX = "[CrewMemberShadowWriter]"
local lastCleanIncomeReportAtByActor = {}
local lastValidationStatusByRoot = setmetatable({}, { __mode = "k" })
local lastValidationStatusByPlayer = setmetatable({}, { __mode = "k" })

local function getRoot(source)
	if typeof(source) == "table" and typeof(source.Data) == "table" then
		return source.Data
	end
	if typeof(source) == "table" then
		return source
	end
	return nil
end

local function deepCopy(value, seen)
	if typeof(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local copy = {}
	seen[value] = copy
	for key, child in pairs(value) do
		copy[deepCopy(key, seen)] = deepCopy(child, seen)
	end
	return copy
end

local function countPairs(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count
end

local function countArray(value)
	if typeof(value) ~= "table" then
		return 0
	end
	return #value
end

local function getFlags(options)
	options = if typeof(options) == "table" then options else {}
	return CrewStorage.GetShadowFlags(options.Flags)
end

local function getPath(root, path)
	local node = root
	for _, key in ipairs(path) do
		if typeof(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

local function addIssue(issues, kind, detail)
	detail = if typeof(detail) == "table" then detail else {}
	detail.Kind = kind
	issues[#issues + 1] = detail
end

local function compareValue(expected, actual, path, issues)
	local expectedType = typeof(expected)
	local actualType = typeof(actual)
	if expectedType ~= actualType then
		addIssue(issues, "ShadowTypeMismatch", {
			Path = path,
			ExpectedType = expectedType,
			ActualType = actualType,
		})
		return
	end

	if expectedType ~= "table" then
		if expected ~= actual then
			addIssue(issues, "ShadowValueMismatch", {
				Path = path,
				Expected = tostring(expected),
				Actual = tostring(actual),
			})
		end
		return
	end

	local keys = {}
	for key in pairs(expected) do
		keys[key] = true
	end
	for key in pairs(actual) do
		keys[key] = true
	end

	for key in pairs(keys) do
		compareValue(expected[key], actual[key], path .. "." .. tostring(key), issues)
	end
end

local function getCanonicalKeyStatus(root)
	local indexCollection = if typeof(root) == "table" then root[CrewProfileSchema.Keys.IndexCollection] else nil
	local inventory = if typeof(root) == "table" then root[CrewProfileSchema.Keys.Inventory] else nil
	local quickSlots = if typeof(root) == "table" then root[CrewProfileSchema.Keys.QuickSlots] else nil
	local income = if typeof(root) == "table" then root[CrewProfileSchema.Keys.Income] else nil
	local index = if typeof(indexCollection) == "table" then indexCollection[CrewProfileSchema.Keys.Index] else nil
	local issues = {}

	local function addShapeIssue(path, expectedType, actualValue)
		issues[#issues + 1] = {
			Path = tostring(path),
			ExpectedType = tostring(expectedType),
			ActualType = typeof(actualValue),
		}
	end

	local function expectField(container, path, expectedType)
		local value = if typeof(container) == "table" then container[path] else nil
		if typeof(value) ~= expectedType then
			addShapeIssue(path, expectedType, value)
			return false
		end
		return true
	end

	local inventoryExists = typeof(inventory) == "table"
	local quickSlotsExists = typeof(quickSlots) == "table"
	local incomeExists = typeof(income) == "table"
	local indexExists = typeof(index) == "table"

	if not inventoryExists then
		addShapeIssue(CrewProfileSchema.Keys.Inventory, "table", inventory)
	end
	if not quickSlotsExists then
		addShapeIssue(CrewProfileSchema.Keys.QuickSlots, "table", quickSlots)
	end
	if not incomeExists then
		addShapeIssue(CrewProfileSchema.Keys.Income, "table", income)
	end
	if typeof(indexCollection) ~= "table" then
		addShapeIssue(CrewProfileSchema.Keys.IndexCollection, "table", indexCollection)
	end
	if not indexExists then
		addShapeIssue(CrewProfileSchema.Keys.IndexCollection .. "." .. CrewProfileSchema.Keys.Index, "table", index)
	end

	local inventoryShape = inventoryExists
		and expectField(inventory, "SchemaVersion", "number")
		and expectField(inventory, "NextInstanceId", "number")
		and expectField(inventory, "ById", "table")
		and expectField(inventory, "Order", "table")
	local quickSlotsShape = quickSlotsExists
		and expectField(quickSlots, "SchemaVersion", "number")
		and expectField(quickSlots, "UnlockedSlots", "number")
		and expectField(quickSlots, "MaxSlots", "number")
	local incomeShape = incomeExists
	local indexShape = indexExists

	return {
		CrewMemberInventory = inventoryExists,
		CrewMemberInventoryShape = inventoryShape == true,
		CrewMemberQuickSlots = quickSlotsExists,
		CrewMemberQuickSlotsShape = quickSlotsShape == true,
		CrewMemberIncome = incomeExists,
		CrewMemberIncomeShape = incomeShape == true,
		IndexCrewMembers = indexExists,
		IndexCrewMembersShape = indexShape == true,
		IsValid = #issues == 0,
		Issues = issues,
	}
end

local function cloneCanonicalKeyStatus(status)
	if typeof(status) ~= "table" then
		return nil
	end

	local copy = table.clone(status)
	copy.Issues = if typeof(status.Issues) == "table" then table.clone(status.Issues) else {}
	return copy
end

local function buildValidationStatus(root, validation, options)
	options = if typeof(options) == "table" then options else {}
	local player = options.Player
	local actor = if typeof(player) == "Instance" and player:IsA("Player")
		then player.Name
		else tostring(options.Actor or "unknown")
	local validatedAt = tonumber(validation.ValidatedAt) or os.clock()
	return {
		Actor = actor,
		ValidatedAt = validatedAt,
		CanonicalKeys = getCanonicalKeyStatus(root),
		MismatchCount = validation.MismatchCount or 0,
		StandIssueCount = validation.StandIssueCount or 0,
		DuplicateIssueCount = validation.DuplicateIssueCount or 0,
		UnknownLegacyIdCount = validation.UnknownLegacyIdCount or 0,
		CompatibilityOnlyIdCount = validation.CompatibilityOnlyIdCount or 0,
		BrookFallbackCount = validation.BrookFallbackCount or 0,
		BlockingIncomeMismatchCount = validation.BlockingIncomeMismatchCount or 0,
		BlockingShadowMirrorIssueCount = validation.BlockingShadowMirrorIssueCount or 0,
		BlockingIssueCount = validation.BlockingIssueCount or 0,
		ShadowMirrorIssueCount = validation.ShadowMirrorIssueCount or 0,
		PendingIncomeSyncCount = validation.PendingIncomeSyncCount or 0,
		Summary = tostring(validation.Summary or ""),
	}
end

local function cloneValidationStatus(status)
	if typeof(status) ~= "table" then
		return nil
	end

	local copy = table.clone(status)
	copy.CanonicalKeys = cloneCanonicalKeyStatus(status.CanonicalKeys)
	copy.ValidationAgeSeconds = math.max(0, os.clock() - (tonumber(status.ValidatedAt) or os.clock()))
	return copy
end

local function recordValidationStatus(root, validation, options)
	if typeof(root) ~= "table" or typeof(validation) ~= "table" then
		return nil
	end

	local status = buildValidationStatus(root, validation, options)
	lastValidationStatusByRoot[root] = status

	local player = if typeof(options) == "table" then options.Player else nil
	if typeof(player) == "Instance" and player:IsA("Player") then
		lastValidationStatusByPlayer[player] = status
	end

	return cloneValidationStatus(status)
end

local function countCanonicalInstances(root)
	local inventory = getPath(root, { CrewProfileSchema.Keys.Inventory })
	return countPairs(if typeof(inventory) == "table" then inventory.ById else nil)
end

local function compareCanonicalShadowToProjection(root, projection)
	local issues = {}
	local indexCollection = projection[CrewProfileSchema.Keys.IndexCollection] or {}

	local checks = {
		{
			Name = CrewProfileSchema.Keys.Inventory,
			Path = { CrewProfileSchema.Keys.Inventory },
			Expected = projection[CrewProfileSchema.Keys.Inventory],
		},
		{
			Name = CrewProfileSchema.Keys.QuickSlots,
			Path = { CrewProfileSchema.Keys.QuickSlots },
			Expected = projection[CrewProfileSchema.Keys.QuickSlots],
		},
		{
			Name = CrewProfileSchema.Keys.Income,
			Path = { CrewProfileSchema.Keys.Income },
			Expected = projection[CrewProfileSchema.Keys.Income],
		},
		{
			Name = CrewProfileSchema.Keys.Index,
			Path = { CrewProfileSchema.Keys.IndexCollection, CrewProfileSchema.Keys.Index },
			Expected = indexCollection[CrewProfileSchema.Keys.Index],
		},
	}

	for _, check in ipairs(checks) do
		local actual = getPath(root, check.Path)
		if typeof(actual) ~= "table" then
			addIssue(issues, "ShadowKeyMissing", {
				Path = table.concat(check.Path, "."),
				Key = check.Name,
			})
		else
			compareValue(check.Expected, actual, table.concat(check.Path, "."), issues)
		end
	end

	return {
		Issues = issues,
		Summary = string.format("shadowMirrorIssues=%d", #issues),
	}
end

local function classifyIncomeMirrorIssues(shadowIssues, options)
	options = if typeof(options) == "table" then options else {}
	local syncState = if typeof(options.IncomeShadowSyncState) == "table"
		then options.IncomeShadowSyncState
		else CrewStorage.GetIncomeShadowSyncState(options.Player)
	local pendingIssues = {}
	local blockingIncomeMismatchCount = 0
	local pendingIncomeSyncTotal = 0
	local incomeLagWithinWindow = syncState.IncomeLagWithinCoalesceWindow == true

	for _, issue in ipairs(shadowIssues) do
		local path = tostring(issue.Path or "")
		if issue.Kind == "ShadowValueMismatch"
			and path:sub(1, #CrewProfileSchema.Keys.Income + 1) == CrewProfileSchema.Keys.Income .. "."
			and path:sub(-#".IncomeToCollect") == ".IncomeToCollect"
		then
			local expected = tonumber(issue.Expected)
			local actual = tonumber(issue.Actual)
			local delta = if expected and actual then expected - actual else 0
			if incomeLagWithinWindow and delta > 0 then
				pendingIssues[#pendingIssues + 1] = issue
				pendingIncomeSyncTotal += delta
			else
				blockingIncomeMismatchCount += 1
			end
		end
	end

	return {
		PendingIncomeSyncCount = #pendingIssues,
		PendingIncomeSyncTotal = pendingIncomeSyncTotal,
		IncomeLagWithinCoalesceWindow = incomeLagWithinWindow and #pendingIssues > 0,
		BlockingIncomeMismatchCount = blockingIncomeMismatchCount,
		SyncState = syncState,
	}
end

local function buildValidationReport(root, projection, options)
	local validatedAt = os.clock()
	local diff = CrewMigrationPlanner.CompareLegacyToCrewMemberProjection(root, projection)
	local standConsistency = CrewMigrationPlanner.ValidateStandConsistency(root)
	local duplicates = CrewMigrationPlanner.DetectDuplicateInstances(root)
	local shadowMirror = compareCanonicalShadowToProjection(root, projection)
	local metadata = projection.Metadata or {}
	local unknownLegacyIdCount = #(metadata.UnknownLegacyIds or {})
	local incomeMirror = classifyIncomeMirrorIssues(shadowMirror.Issues, options)
	local blockingShadowMirrorIssueCount = math.max(0, #shadowMirror.Issues - incomeMirror.PendingIncomeSyncCount)
	local blockingIssueCount = #diff.Issues
		+ #standConsistency.Issues
		+ #duplicates.Issues
		+ unknownLegacyIdCount
		+ blockingShadowMirrorIssueCount

	return {
		ValidatedAt = validatedAt,
		MismatchCount = #diff.Issues,
		StandIssueCount = #standConsistency.Issues,
		DuplicateIssueCount = #duplicates.Issues,
		UnknownLegacyIdCount = unknownLegacyIdCount,
		CompatibilityOnlyIdCount = #(metadata.CompatibilityOnlyLegacyIds or {}),
		BrookFallbackCount = metadata.BrookFallbackCount or 0,
		ShadowMirrorIssueCount = #shadowMirror.Issues,
		BlockingShadowMirrorIssueCount = blockingShadowMirrorIssueCount,
		PendingIncomeSyncCount = incomeMirror.PendingIncomeSyncCount,
		PendingIncomeSyncTotal = incomeMirror.PendingIncomeSyncTotal,
		IncomeLagWithinCoalesceWindow = incomeMirror.IncomeLagWithinCoalesceWindow,
		BlockingIncomeMismatchCount = incomeMirror.BlockingIncomeMismatchCount,
		IncomeShadowSyncState = incomeMirror.SyncState,
		BlockingIssueCount = blockingIssueCount,
		Diff = diff,
		StandConsistency = standConsistency,
		Duplicates = duplicates,
		ShadowMirror = shadowMirror,
		Summary = string.format(
			"mismatches=%d standIssues=%d duplicateIssues=%d unknown=%d compatibilityOnly=%d brookFallback=%d shadowMirrorIssues=%d pendingIncomeSync=%d pendingIncomeTotal=%d blockingMirrorIssues=%d",
			#diff.Issues,
			#standConsistency.Issues,
			#duplicates.Issues,
			unknownLegacyIdCount,
			#(metadata.CompatibilityOnlyLegacyIds or {}),
			metadata.BrookFallbackCount or 0,
			#shadowMirror.Issues,
			incomeMirror.PendingIncomeSyncCount,
			incomeMirror.PendingIncomeSyncTotal,
			blockingShadowMirrorIssueCount
		),
	}
end

local function writeProjection(root, projection)
	local indexCollection = root[CrewProfileSchema.Keys.IndexCollection]
	if typeof(indexCollection) ~= "table" then
		indexCollection = {}
		root[CrewProfileSchema.Keys.IndexCollection] = indexCollection
	end

	local projectedIndexCollection = projection[CrewProfileSchema.Keys.IndexCollection] or {}
	root[CrewProfileSchema.Keys.Inventory] = deepCopy(projection[CrewProfileSchema.Keys.Inventory])
	root[CrewProfileSchema.Keys.QuickSlots] = deepCopy(projection[CrewProfileSchema.Keys.QuickSlots])
	root[CrewProfileSchema.Keys.Income] = deepCopy(projection[CrewProfileSchema.Keys.Income])
	indexCollection[CrewProfileSchema.Keys.Index] =
		deepCopy(projectedIndexCollection[CrewProfileSchema.Keys.Index])
end

local function getActorName(options)
	options = if typeof(options) == "table" then options else {}
	local player = options.Player
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player.Name
	end
	return tostring(options.Actor or "unknown")
end

local function isProjectionReportDebugEnabled()
	return game:GetAttribute("CrewMemberShadowReportDebug") == true
		or game:GetAttribute("CrewMemberShadowWriterDebug") == true
end

local function hasProjectionIssue(result)
	if typeof(result) ~= "table" then
		return false
	end
	if result.StrictFailure == true then
		return true
	end

	local validation = result.Validation
	if typeof(validation) ~= "table" then
		return false
	end

	return (tonumber(validation.MismatchCount) or 0) > 0
		or (tonumber(validation.StandIssueCount) or 0) > 0
		or (tonumber(validation.DuplicateIssueCount) or 0) > 0
		or (tonumber(validation.UnknownLegacyIdCount) or 0) > 0
		or (tonumber(validation.CompatibilityOnlyIdCount) or 0) > 0
		or (tonumber(validation.PendingIncomeSyncCount) or 0) > 0
		or (tonumber(validation.BlockingIncomeMismatchCount) or 0) > 0
		or (tonumber(validation.ShadowMirrorIssueCount) or 0) > 0
		or (tonumber(validation.BlockingIssueCount) or 0) > 0
end

local function clearCanonicalShadowKeys(root)
	if typeof(root) ~= "table" then
		return
	end

	root[CrewProfileSchema.Keys.Inventory] = nil
	root[CrewProfileSchema.Keys.QuickSlots] = nil
	root[CrewProfileSchema.Keys.Income] = nil

	local indexCollection = root[CrewProfileSchema.Keys.IndexCollection]
	if typeof(indexCollection) == "table" then
		indexCollection[CrewProfileSchema.Keys.Index] = nil
	end
end

local function printProjectionResult(result)
	if not isProjectionReportDebugEnabled() and not hasProjectionIssue(result) then
		return
	end

	local validation = result.Validation
	local reason = tostring(result.Reason or "unspecified")
	if validation
		and reason == "income_bank"
		and validation.BlockingIssueCount == 0
		and validation.PendingIncomeSyncCount == 0
		and validation.ShadowMirrorIssueCount == 0
	then
		local actor = tostring(result.Actor or "unknown")
		local now = os.clock()
		local throttleSeconds = math.max(0, tonumber(CrewMemberShadowConfig.ReportCleanIncomeBankEverySeconds) or 0)
		local lastReportAt = tonumber(lastCleanIncomeReportAtByActor[actor]) or 0
		if throttleSeconds > 0 and now - lastReportAt < throttleSeconds then
			return
		end
		lastCleanIncomeReportAtByActor[actor] = now
	end

	if validation then
		print(string.format(
			"%s reason=%s actor=%s wrote=%s strictFailure=%s readiness=%s legacyInstances=%d canonicalInstances=%d mismatches=%d standIssues=%d duplicateIssues=%d unknown=%d compatibilityOnly=%d brookFallback=%d pendingIncomeSync=%d blockingIncomeMismatch=%d shadowMirrorIssues=%d blockingIssues=%d canonicalRead=%s",
			LOG_PREFIX,
			reason,
			tostring(result.Actor),
			tostring(result.DidWrite),
			tostring(result.StrictFailure),
			tostring(result.ReadinessStatus),
			result.LegacyInstanceCount or 0,
			result.CanonicalInstanceCount or 0,
			validation.MismatchCount or 0,
			validation.StandIssueCount or 0,
			validation.DuplicateIssueCount or 0,
			validation.UnknownLegacyIdCount or 0,
			validation.CompatibilityOnlyIdCount or 0,
			validation.BrookFallbackCount or 0,
			validation.PendingIncomeSyncCount or 0,
			validation.BlockingIncomeMismatchCount or 0,
			validation.ShadowMirrorIssueCount or 0,
			validation.BlockingIssueCount or 0,
			tostring(result.Flags and result.Flags.CrewMemberCanonicalReadEnabled)
		))
		return
	end

	print(string.format(
		"%s reason=%s actor=%s wrote=%s strictFailure=%s readiness=%s legacyInstances=%d canonicalInstances=%d validation=disabled canonicalRead=%s",
		LOG_PREFIX,
		reason,
		tostring(result.Actor),
		tostring(result.DidWrite),
		tostring(result.StrictFailure),
		tostring(result.ReadinessStatus),
		result.LegacyInstanceCount or 0,
		result.CanonicalInstanceCount or 0,
		tostring(result.Flags and result.Flags.CrewMemberCanonicalReadEnabled)
	))
end

function CrewMemberShadowWriter.ProjectLegacyToCanonicalShadow(source, options)
	local root = getRoot(source)
	local flags = getFlags(options)
	local actor = getActorName(options)
	options = if typeof(options) == "table" then options else {}
	local reason = tostring(options.Reason or "manual_projection")

	if root == nil then
		return {
			Actor = actor,
			Reason = reason,
			DidWrite = false,
			Flags = flags,
			Error = "invalid_source",
		}
	end

	if flags.CrewMemberShadowWriteEnabled ~= true then
		return {
			Actor = actor,
			Reason = reason,
			DidWrite = false,
			Flags = flags,
			SkippedReason = "shadow_write_disabled",
		}
	end

	if options.ClearBeforeWrite == true then
		clearCanonicalShadowKeys(root)
	end

	local projection = CrewMigrationPlanner.BuildDryRunProjection(root)
	writeProjection(root, projection)

	local readiness = CrewMigrationPlanner.BuildReadinessReport(root)
	local validation = nil
	local validationStatus = nil
	if flags.CrewMemberShadowValidateEnabled == true then
		validation = buildValidationReport(root, projection, options)
		validationStatus = recordValidationStatus(root, validation, options)
	end

	local result = {
		Actor = actor,
		Reason = reason,
		DidWrite = true,
		Flags = flags,
		Projection = projection,
		Validation = validation,
		ValidationStatus = validationStatus,
		ReadinessStatus = readiness.MigrationStatus,
		LegacyInstanceCount = readiness.LegacyInstanceCount,
		CanonicalInstanceCount = countCanonicalInstances(root),
		CompatibilityOnlyIdCount = #((projection.Metadata or {}).CompatibilityOnlyLegacyIds or {}),
		BrookFallbackCount = (projection.Metadata or {}).BrookFallbackCount or 0,
		StrictFailure = validation ~= nil
			and flags.CrewMemberShadowWriteStrictMode == true
			and validation.BlockingIssueCount > 0,
	}

	if flags.CrewMemberShadowReportEnabled == true then
		printProjectionResult(result)
	end

	return result
end

function CrewMemberShadowWriter.RunProfileReadyProjection(source, options)
	return CrewMemberShadowWriter.ProjectLegacyToCanonicalShadow(source, options)
end

function CrewMemberShadowWriter.RefreshAfterLegacyMutation(source, reason, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	options.Reason = tostring(reason or options.Reason or "legacy_mutation")
	return CrewMemberShadowWriter.ProjectLegacyToCanonicalShadow(source, options)
end

function CrewMemberShadowWriter.RefreshAfterDestructiveLegacyReset(source, reason, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	options.Reason = tostring(reason or options.Reason or "destructive_legacy_reset")
	options.ClearBeforeWrite = true
	return CrewMemberShadowWriter.ProjectLegacyToCanonicalShadow(source, options)
end

function CrewMemberShadowWriter.BuildShadowWriteStatus(source, options)
	local root = getRoot(source)
	local flags = getFlags(options)
	if root == nil then
		return {
			Flags = flags,
			Error = "invalid_source",
		}
	end

	local projection = CrewMigrationPlanner.BuildDryRunProjection(root)
	local readiness = CrewMigrationPlanner.BuildReadinessReport(root)
	local canonicalKeys = getCanonicalKeyStatus(root)
	local validation = buildValidationReport(root, projection, options)
	local validationStatus = recordValidationStatus(root, validation, options)

	return {
		Flags = flags,
		CanonicalKeys = canonicalKeys,
		LegacyInstanceCount = readiness.LegacyInstanceCount,
		ProjectedInstanceCount = readiness.ProjectedCrewMemberInstanceCount,
		CanonicalInstanceCount = countCanonicalInstances(root),
		CanonicalOrderCount = countArray(getPath(root, { CrewProfileSchema.Keys.Inventory, "Order" })),
		DiffSummary = readiness.Diff.Summary,
		ReadinessStatus = readiness.MigrationStatus,
		ShadowMirror = validation.ShadowMirror,
		Validation = validation,
		ValidationStatus = validationStatus,
		PendingIncomeSyncCount = validation.PendingIncomeSyncCount,
		PendingIncomeSyncTotal = validation.PendingIncomeSyncTotal,
		IncomeLagWithinCoalesceWindow = validation.IncomeLagWithinCoalesceWindow,
		BlockingIncomeMismatchCount = validation.BlockingIncomeMismatchCount,
		BlockingShadowMirrorIssueCount = validation.BlockingShadowMirrorIssueCount,
		BlockingIssueCount = validation.BlockingIssueCount,
		UnknownLegacyIdCount = #((projection.Metadata or {}).UnknownLegacyIds or {}),
		CompatibilityOnlyIdCount = #((projection.Metadata or {}).CompatibilityOnlyLegacyIds or {}),
		BrookFallbackCount = (projection.Metadata or {}).BrookFallbackCount or 0,
	}
end

function CrewMemberShadowWriter.PrintShadowWriteStatus(source, options)
	local status = CrewMemberShadowWriter.BuildShadowWriteStatus(source, options)
	if status.Error then
		warn(string.format("%s statusError=%s", LOG_PREFIX, tostring(status.Error)))
		return status
	end

	local flags = status.Flags
	local keys = status.CanonicalKeys
	print(string.format(
		"%s flags shadowWrite=%s validate=%s report=%s canonicalRead=%s strict=%s",
		LOG_PREFIX,
		tostring(flags.CrewMemberShadowWriteEnabled),
		tostring(flags.CrewMemberShadowValidateEnabled),
		tostring(flags.CrewMemberShadowReportEnabled),
		tostring(flags.CrewMemberCanonicalReadEnabled),
		tostring(flags.CrewMemberShadowWriteStrictMode)
	))
	print(string.format(
		"%s status readiness=%s legacyInstances=%d projectedInstances=%d canonicalInstances=%d canonicalOrder=%d keys={inventory=%s quickSlots=%s income=%s index=%s} %s unknown=%d compatibilityOnly=%d brookFallback=%d",
		LOG_PREFIX,
		tostring(status.ReadinessStatus),
		status.LegacyInstanceCount or 0,
		status.ProjectedInstanceCount or 0,
		status.CanonicalInstanceCount or 0,
		status.CanonicalOrderCount or 0,
		tostring(keys.CrewMemberInventory),
		tostring(keys.CrewMemberQuickSlots),
		tostring(keys.CrewMemberIncome),
		tostring(keys.IndexCrewMembers),
		tostring(status.DiffSummary),
		status.UnknownLegacyIdCount or 0,
		status.CompatibilityOnlyIdCount or 0,
		status.BrookFallbackCount or 0
	))
	return status
end

function CrewMemberShadowWriter.ValidateShadowProjection(root, projection, options)
	local validation = buildValidationReport(root, projection, options)
	recordValidationStatus(root, validation, options)
	return validation
end

function CrewMemberShadowWriter.GetLastValidationStatus(source, options)
	options = if typeof(options) == "table" then options else {}
	local root = getRoot(source)
	local status = if typeof(root) == "table" then lastValidationStatusByRoot[root] else nil

	if status == nil and typeof(options.Player) == "Instance" and options.Player:IsA("Player") then
		status = lastValidationStatusByPlayer[options.Player]
	end
	if status == nil and typeof(source) == "Instance" and source:IsA("Player") then
		status = lastValidationStatusByPlayer[source]
	end

	return cloneValidationStatus(status)
end

return CrewMemberShadowWriter
