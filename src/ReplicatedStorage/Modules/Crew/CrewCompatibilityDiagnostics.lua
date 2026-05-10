local CrewAssetAudit = require(script.Parent:WaitForChild("CrewAssetAudit"))
local CrewMappingValidator = require(script.Parent:WaitForChild("CrewMappingValidator"))
local CrewResolver = require(script.Parent:WaitForChild("CrewResolver"))

local CrewCompatibilityDiagnostics = {}

local MAX_PRINT_ITEMS = 25

local function copyLegacyMappings(list)
	local out = {}
	for _, entry in ipairs(list or {}) do
		out[#out + 1] = {
			LegacyId = tostring(entry.LegacyId or ""),
			DisplayName = tostring(entry.DisplayName or entry.CrewMemberName or ""),
			ModelName = tostring(entry.ModelName or ""),
		}
	end
	return out
end

local function copyModelNames(list)
	local out = {}
	for _, entry in ipairs(list or {}) do
		out[#out + 1] = tostring(entry.Name or entry.ModelName or entry.LegacyId or "")
	end
	table.sort(out)
	return out
end

local function printList(label, list, formatter)
	print(string.format("[CrewCompatibilityDiagnostics] %s (%d)", label, #list))
	for index, value in ipairs(list) do
		if index > MAX_PRINT_ITEMS then
			print(string.format("[CrewCompatibilityDiagnostics] ... %d more", #list - MAX_PRINT_ITEMS))
			break
		end
		print("[CrewCompatibilityDiagnostics] - " .. formatter(value))
	end
end

function CrewCompatibilityDiagnostics.Run(options)
	options = options or {}
	local audit = options.AssetAuditReport or CrewAssetAudit.Run({ Warn = false })
	local validation = options.MappingValidationReport or CrewMappingValidator.Run({
		Warn = false,
		AssetAuditReport = audit,
	})
	local resolverDiagnostics = CrewResolver.GetDiagnostics()

	local productionFallbacks = copyLegacyMappings(validation.MappedMissingModels)
	local compatibilityOnlyLegacyIds = copyLegacyMappings(validation.LegacyIdsWithoutMapping)
	local unmappedRootModels = copyModelNames(validation.UnmappedModels)

	return {
		Summary = string.format(
			"mappedExisting=%d productionFallbacks=%d compatibilityOnlyLegacyIds=%d unmappedRootModels=%d runtimeFallbacks=%d missingRuntimeIds=%d",
			#validation.MappedExistingModels,
			#productionFallbacks,
			#compatibilityOnlyLegacyIds,
			#unmappedRootModels,
			#resolverDiagnostics.LegacyFallbackModelIds,
			#resolverDiagnostics.MissingCrewMemberIds
		),
		AssetAudit = audit,
		MappingValidation = validation,
		ResolverDiagnostics = resolverDiagnostics,
		ProductionCrewUsingFallbackModels = productionFallbacks,
		CompatibilityOnlyLegacyIds = compatibilityOnlyLegacyIds,
		UnmappedRootModelNames = unmappedRootModels,
	}
end

function CrewCompatibilityDiagnostics.PrintReport(options)
	local report = CrewCompatibilityDiagnostics.Run(options)
	print("[CrewCompatibilityDiagnostics] " .. report.Summary)

	printList("production crew using fallback models", report.ProductionCrewUsingFallbackModels, function(entry)
		return string.format("%s display=%s model=%s", entry.LegacyId, entry.DisplayName, entry.ModelName)
	end)
	printList("compatibility-only legacy IDs", report.CompatibilityOnlyLegacyIds, function(entry)
		return string.format("%s model=%s", entry.LegacyId, entry.ModelName)
	end)
	printList("unmapped direct root models", report.UnmappedRootModelNames, function(name)
		return tostring(name)
	end)
	printList("runtime fallback model IDs", report.ResolverDiagnostics.LegacyFallbackModelIds, function(id)
		return tostring(id)
	end)
	printList("missing runtime crew IDs", report.ResolverDiagnostics.MissingCrewMemberIds, function(id)
		return tostring(id)
	end)

	return report
end

return CrewCompatibilityDiagnostics
