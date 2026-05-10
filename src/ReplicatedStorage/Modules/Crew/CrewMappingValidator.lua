local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local LegacyCrewConfig = require(Configs:WaitForChild("Brainrots"))
local CrewAssetAudit = require(script.Parent:WaitForChild("CrewAssetAudit"))
local CrewMemberMappings = require(script.Parent:WaitForChild("CrewMemberMappings"))

local CrewMappingValidator = {}

local MAX_PRINT_ITEMS = 25

local warned = {}

local function warnOnce(key, message)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function append(list, value)
	list[#list + 1] = value
end

local function sortByLegacyId(list)
	table.sort(list, function(a, b)
		return tostring(a.LegacyId) < tostring(b.LegacyId)
	end)
end

local function sortByName(list)
	table.sort(list, function(a, b)
		return tostring(a.Name) < tostring(b.Name)
	end)
end

local function getLegacyBaseIds()
	local ids = {}

	for id, info in pairs(LegacyCrewConfig) do
		if typeof(info) == "table" and not info.IsVariant and not info.Variant then
			append(ids, tostring(id))
		end
	end

	table.sort(ids)
	return ids
end

local function normalizeMapping(legacyId, rawMapping)
	if rawMapping == nil then
		return nil
	end

	if typeof(rawMapping) ~= "table" then
		return {
			LegacyId = legacyId,
			IsValid = false,
			Reason = "MappingValueMustBeTable",
			RawType = typeof(rawMapping),
		}
	end

	local modelName = rawMapping.ModelName
	local crewMemberName = rawMapping.CrewMemberName
	local displayName = rawMapping.DisplayName

	if modelName == nil and crewMemberName ~= nil then
		modelName = crewMemberName
	end

	local resolvedModelName = tostring(modelName or legacyId)

	return {
		LegacyId = legacyId,
		IsValid = true,
		ModelName = resolvedModelName,
		ExplicitModelName = rawMapping.ModelName ~= nil,
		CrewMemberName = crewMemberName and tostring(crewMemberName) or nil,
		DisplayName = displayName and tostring(displayName) or nil,
		CrewMemberId = rawMapping.CrewMemberId and tostring(rawMapping.CrewMemberId) or nil,
		UsesLegacyIdAsModelName = resolvedModelName == legacyId and rawMapping.ModelName == nil and rawMapping.CrewMemberName == nil,
	}
end

local function modelNameExists(auditReport, modelName)
	local paths = auditReport.ModelNamesByName and auditReport.ModelNamesByName[tostring(modelName)]
	return paths ~= nil and #paths > 0, paths
end

local function buildMappedModelNameSet(report)
	local mapped = {}

	for _, entry in ipairs(report.MappedExistingModels) do
		mapped[entry.ModelName] = true
	end
	for _, entry in ipairs(report.MappedMissingModels) do
		mapped[entry.ModelName] = true
	end
	for _, entry in ipairs(report.MappingsUncheckedBecauseFolderMissing) do
		mapped[entry.ModelName] = true
	end

	return mapped
end

local function collectDuplicateMappings(entries)
	local byModelName = {}
	for _, entry in ipairs(entries) do
		if entry.IsValid then
			byModelName[entry.ModelName] = byModelName[entry.ModelName] or {}
			append(byModelName[entry.ModelName], entry.LegacyId)
		end
	end

	local duplicates = {}
	for modelName, legacyIds in pairs(byModelName) do
		if #legacyIds > 1 then
			table.sort(legacyIds)
			append(duplicates, {
				ModelName = modelName,
				LegacyIds = legacyIds,
			})
		end
	end

	table.sort(duplicates, function(a, b)
		return tostring(a.ModelName) < tostring(b.ModelName)
	end)

	return duplicates
end

local function printList(label, list, formatter)
	print(string.format("[CrewMappingValidator] %s (%d)", label, #list))
	for index, value in ipairs(list) do
		if index > MAX_PRINT_ITEMS then
			print(string.format("[CrewMappingValidator] ... %d more", #list - MAX_PRINT_ITEMS))
			break
		end
		print("[CrewMappingValidator] - " .. formatter(value))
	end
end

function CrewMappingValidator.Run(options)
	options = options or {}
	local shouldWarn = options.Warn ~= false
	local auditReport = options.AssetAuditReport or CrewAssetAudit.Run({ Warn = false })
	local mappings = CrewMemberMappings.LegacyIdToCrewMember or {}
	local legacyIds = getLegacyBaseIds()
	local knownLegacyIds = {}

	for _, legacyId in ipairs(legacyIds) do
		knownLegacyIds[legacyId] = true
	end

	local report = {
		AssetFolderExists = auditReport.FolderExists,
		AssetFolderPath = auditReport.FolderPath,
		LegacyBaseIdCount = #legacyIds,
		MappingCount = 0,
		MappedExistingModels = {},
		MappedMissingModels = {},
		MappingsUncheckedBecauseFolderMissing = {},
		DuplicateModelMappings = {},
		UnmappedModels = {},
		LegacyIdsWithoutMapping = {},
		LegacyIdFallbackMappings = {},
		DisplayNameWithoutModelName = {},
		InvalidMappings = {},
		UnknownLegacyIdMappings = {},
		AssetAudit = auditReport,
		Summary = nil,
	}

	local normalizedMappings = {}
	for legacyId, rawMapping in pairs(mappings) do
		legacyId = tostring(legacyId)
		report.MappingCount += 1

		local normalized = normalizeMapping(legacyId, rawMapping)
		append(normalizedMappings, normalized)

		if not knownLegacyIds[legacyId] then
			append(report.UnknownLegacyIdMappings, {
				LegacyId = legacyId,
				ModelName = normalized.ModelName,
			})
		end

		if not normalized.IsValid then
			append(report.InvalidMappings, normalized)
			continue
		end

		if normalized.UsesLegacyIdAsModelName then
			append(report.LegacyIdFallbackMappings, normalized)
		end
		if (normalized.DisplayName ~= nil or normalized.CrewMemberName ~= nil) and normalized.ExplicitModelName == false then
			append(report.DisplayNameWithoutModelName, {
				LegacyId = legacyId,
				DisplayName = normalized.DisplayName,
				CrewMemberName = normalized.CrewMemberName,
				ResolvedModelName = normalized.ModelName,
				Reason = "DisplayName/CrewMemberName is player-facing; ModelName should be the exact Studio model name.",
			})
		end

		if not auditReport.FolderExists then
			append(report.MappingsUncheckedBecauseFolderMissing, normalized)
		else
			local exists, paths = modelNameExists(auditReport, normalized.ModelName)
			if exists then
				normalized.ModelPaths = paths
				append(report.MappedExistingModels, normalized)
			else
				append(report.MappedMissingModels, normalized)
			end
		end
	end

	for _, legacyId in ipairs(legacyIds) do
		if mappings[legacyId] == nil then
			append(report.LegacyIdsWithoutMapping, {
				LegacyId = legacyId,
				ModelName = legacyId,
			})
		end
	end

	report.DuplicateModelMappings = collectDuplicateMappings(normalizedMappings)

	if auditReport.FolderExists then
		local mappedModelNames = buildMappedModelNameSet(report)
		for _, modelDetail in ipairs(auditReport.DirectModels or auditReport.AllModels) do
			if not mappedModelNames[modelDetail.Name] then
				append(report.UnmappedModels, modelDetail)
			end
		end
	end

	sortByLegacyId(report.MappedExistingModels)
	sortByLegacyId(report.MappedMissingModels)
	sortByLegacyId(report.MappingsUncheckedBecauseFolderMissing)
	sortByLegacyId(report.LegacyIdsWithoutMapping)
	sortByLegacyId(report.LegacyIdFallbackMappings)
	sortByLegacyId(report.DisplayNameWithoutModelName)
	sortByLegacyId(report.InvalidMappings)
	sortByLegacyId(report.UnknownLegacyIdMappings)
	sortByName(report.UnmappedModels)

	report.Summary = string.format(
		"assetFolderExists=%s legacyBaseIds=%d mappings=%d mappedExisting=%d mappedMissing=%d unchecked=%d unmappedModels=%d duplicateModelMappings=%d legacyIdsWithoutMapping=%d",
		tostring(report.AssetFolderExists),
		report.LegacyBaseIdCount,
		report.MappingCount,
		#report.MappedExistingModels,
		#report.MappedMissingModels,
		#report.MappingsUncheckedBecauseFolderMissing,
		#report.UnmappedModels,
		#report.DuplicateModelMappings,
		#report.LegacyIdsWithoutMapping
	)

	if shouldWarn and not report.AssetFolderExists then
		warnOnce(
			"missing_asset_folder",
			"[CrewMappingValidator] ReplicatedStorage.Assets.One Piece Characters is missing; mappings cannot be checked against real crewmate models yet."
		)
	end

	return report
end

function CrewMappingValidator.PrintReport(options)
	local report = CrewMappingValidator.Run(options)
	print("[CrewMappingValidator] " .. report.Summary)
	print("[CrewMappingValidator] Asset folder: " .. tostring(report.AssetFolderPath))

	printList("mapped legacy IDs with existing models", report.MappedExistingModels, function(value)
		return string.format("%s -> %s", tostring(value.LegacyId), tostring(value.ModelName))
	end)
	printList("mapped legacy IDs with missing models", report.MappedMissingModels, function(value)
		return string.format("%s -> %s", tostring(value.LegacyId), tostring(value.ModelName))
	end)
	printList("mappings unchecked because asset folder is missing", report.MappingsUncheckedBecauseFolderMissing, function(value)
		return string.format("%s -> %s", tostring(value.LegacyId), tostring(value.ModelName))
	end)
	printList("duplicate model mappings", report.DuplicateModelMappings, function(value)
		return string.format("%s legacyIds=%s", tostring(value.ModelName), table.concat(value.LegacyIds, ", "))
	end)
	printList("unmapped crewmate models", report.UnmappedModels, function(value)
		return string.format("%s path=%s", tostring(value.Name), tostring(value.Path))
	end)
	printList("legacy IDs without mappings", report.LegacyIdsWithoutMapping, function(value)
		return string.format("%s -> legacy model name fallback", tostring(value.LegacyId))
	end)
	printList("display-name mappings missing explicit ModelName", report.DisplayNameWithoutModelName, function(value)
		return string.format(
			"%s displayName=%s crewMemberName=%s",
			tostring(value.LegacyId),
			tostring(value.DisplayName),
			tostring(value.CrewMemberName)
		)
	end)
	printList("invalid mappings", report.InvalidMappings, function(value)
		return string.format("%s reason=%s rawType=%s", tostring(value.LegacyId), tostring(value.Reason), tostring(value.RawType))
	end)
	printList("unknown legacy ID mappings", report.UnknownLegacyIdMappings, function(value)
		return string.format("%s -> %s", tostring(value.LegacyId), tostring(value.ModelName))
	end)

	return report
end

return CrewMappingValidator
