local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewCatalog = require(script.Parent:WaitForChild("CrewCatalog"))

local CrewResolver = {}

local warned = {}
local diagnostics = {
	MissingOnePieceCharactersFolder = false,
	MissingCrewMemberIds = {},
	MissingCrewModels = {},
	AttemptedLegacyModelFallbacks = {},
}
local diagnosticSets = {
	MissingCrewMemberIds = {},
	MissingCrewModels = {},
	AttemptedLegacyModelFallbacks = {},
}
local missingCrewModelWarningCount = 0
local MAX_MISSING_CREW_MODEL_WARNINGS = 5

local function warnOnce(key, message)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function appendDiagnostic(listName, value)
	value = tostring(value or "")
	if value == "" or diagnosticSets[listName][value] then
		return
	end

	diagnosticSets[listName][value] = true
	diagnostics[listName][#diagnostics[listName] + 1] = value
	table.sort(diagnostics[listName])
end

local function warnMissingCrewModel(modelName)
	appendDiagnostic("MissingCrewModels", modelName)

	if warned["missing_crew_model:" .. tostring(modelName)] then
		return
	end

	if missingCrewModelWarningCount < MAX_MISSING_CREW_MODEL_WARNINGS then
		missingCrewModelWarningCount += 1
		warned["missing_crew_model:" .. tostring(modelName)] = true
		warn(
			string.format(
				"[CrewResolver] Crewmate model '%s' was not found in One Piece Characters.",
				tostring(modelName)
			)
		)
	elseif not warned.missing_crew_model_suppressed then
		warned.missing_crew_model_suppressed = true
		warn("[CrewResolver] Additional missing crewmate model warnings are suppressed. Run CrewMappingValidator.PrintReport() for the full mapping status.")
	end
end

local function copyArray(list)
	return table.clone(list)
end

local function getOnePieceCharactersFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("One Piece Characters")
	if not folder then
		diagnostics.MissingOnePieceCharactersFolder = true
		warnOnce(
			"missing_one_piece_characters",
			"[CrewResolver] ReplicatedStorage.Assets.One Piece Characters is missing. CrewMember physical models cannot spawn."
		)
	end
	return folder
end

local function findModel(folder, modelName)
	if not folder then
		return nil
	end

	local direct = folder:FindFirstChild(tostring(modelName))
	if direct and direct:IsA("Model") then
		return direct
	end

	local descendant = folder:FindFirstChild(tostring(modelName), true)
	if descendant and descendant:IsA("Model") then
		return descendant
	end

	return nil
end

local function findVariantModel(folder, modelName, variantKey)
	if not folder then
		return nil
	end
	if variantKey == "Normal" or variantKey == nil then
		return findModel(folder, modelName)
	end

	local variantCfg = CrewCatalog.GetVariantConfig()
	local variantInfo = (variantCfg.Versions or {})[variantKey]
	local folderName = variantInfo and variantInfo.Folder
	local variantFolder = folderName and folder:FindFirstChild(folderName)
	if variantFolder and variantFolder:IsA("Folder") then
		return findModel(variantFolder, modelName)
	end

	return findModel(folder, modelName)
end

function CrewResolver.ResolveCrewMember(crewMemberId, variantKey)
	local canonicalId, resolvedInfo = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	local lookupId = if canonicalId ~= "" then canonicalId else crewMemberId
	local displayInfo = CrewCatalog.GetDisplayInfo(lookupId, resolvedInfo)
	local baseId = tostring(displayInfo.BaseId or lookupId or crewMemberId)
	variantKey = variantKey or displayInfo.Variant or "Normal"

	local info = CrewCatalog.GetOrBuildVariantInfo(baseId, variantKey) or resolvedInfo or CrewCatalog.GetInfoById(crewMemberId)
	if not info then
		appendDiagnostic("MissingCrewMemberIds", crewMemberId)
		return nil
	end

	return {
		Id = CrewCatalog.MakeVariantId(baseId, variantKey),
		BaseId = baseId,
		Variant = variantKey,
		Info = info,
		ModelName = tostring(info.ModelName or baseId),
		DisplayName = tostring(info.DisplayName or info.CrewMemberName or baseId),
	}
end

function CrewResolver.GetTemplateStrict(crewMemberId, variantKey)
	local resolved = CrewResolver.ResolveCrewMember(crewMemberId, variantKey)
	if not resolved then
		return nil
	end

	local crewFolder = getOnePieceCharactersFolder()
	local modelName = resolved.ModelName
	local crewModel = findVariantModel(crewFolder, modelName, resolved.Variant)
	if crewModel then
		return crewModel, resolved.Variant, resolved
	end

	if crewFolder then
		warnMissingCrewModel(modelName)
	end

	appendDiagnostic("AttemptedLegacyModelFallbacks", resolved.BaseId)
	warnOnce(
		"canonical_model_required:" .. tostring(resolved.BaseId),
		string.format(
			"[CrewResolver] Missing canonical CrewMember model '%s' for '%s'. Legacy model fallback is disabled.",
			tostring(modelName),
			tostring(resolved.DisplayName)
		)
	)

	return nil
end

function CrewResolver.GetTemplateWithFallback(crewMemberId, variantKey)
	local template, usedVariant, resolved = CrewResolver.GetTemplateStrict(crewMemberId, variantKey)
	if template then
		return template, usedVariant, resolved
	end

	template, usedVariant, resolved = CrewResolver.GetTemplateStrict(crewMemberId, "Normal")
	return template, usedVariant or "Normal", resolved
end

function CrewResolver.GetDiagnostics()
	return {
		MissingOnePieceCharactersFolder = diagnostics.MissingOnePieceCharactersFolder,
		MissingCrewMemberIds = copyArray(diagnostics.MissingCrewMemberIds),
		MissingCrewModels = copyArray(diagnostics.MissingCrewModels),
		AttemptedLegacyModelFallbacks = copyArray(diagnostics.AttemptedLegacyModelFallbacks),
	}
end

return CrewResolver
