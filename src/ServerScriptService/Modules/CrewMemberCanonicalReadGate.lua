local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewCompatibilityQuarantine =
	require(Modules:WaitForChild("Crew"):WaitForChild("CrewCompatibilityQuarantine"))
local CrewProfileSchema = require(script.Parent:WaitForChild("CrewProfileSchema"))
local CrewStorage = require(script.Parent:WaitForChild("CrewStorage"))
local CrewMemberShadowConfig = require(script.Parent:WaitForChild("CrewMemberShadowConfig"))
local CrewMemberShadowWriter = require(script.Parent:WaitForChild("CrewMemberShadowWriter"))
local CrewMemberLegacyFallbackTelemetry = require(script.Parent:WaitForChild("CrewMemberLegacyFallbackTelemetry"))

local CrewMemberCanonicalReadGate = {}

CrewMemberCanonicalReadGate.Paths = {
	InventoryDisplay = "inventory.display",
	IndexDisplay = "index.display",
	SellDialogDisplay = "sell_dialog.display",
	MetadataHelperDisplayName = "metadata.helper.display_name",
	MetadataHelperRarity = "metadata.helper.rarity",
	MetadataHelperRenderIcon = "metadata.helper.render_icon",
	MetadataHelperRealCharacterName = "metadata.helper.real_character_name",
	MetadataHelperArc = "metadata.helper.arc",
	MetadataHelperCompatibilityClassification = "metadata.helper.compatibility_classification",
	GameplayHelperStandStatusDisplayName = "gameplay.helper.stand_status_display_name",
	GameplayHelperIncomeStatusDisplayName = "gameplay.helper.income_status_display_name",
	GameplayHelperIncomeToastDisplayName = "gameplay.helper.income_toast_display_name",
	GameplayHelperFoodStatusDisplayName = "gameplay.helper.food_status_display_name",
	ReadAuthorityStandStatus = "canary.read_authority.stand_status",
	ReadAuthorityIncomeStatus = "canary.read_authority.income_status",
	ReadAuthorityFoodStatus = "canary.read_authority.food_status",
	AdminModelPreview = "admin.model_preview",
	IndexModelPreview = "index.model_preview",
	InventoryModelPreview = "inventory.model_preview",
	AdminDiagnostics = "admin.diagnostics",
}

local LOG_PREFIX = "[CrewMemberDualReadCanary]"
local DEFAULT_VALIDATION_FRESHNESS_SECONDS =
	math.max(0, tonumber(CrewMemberShadowConfig.CanonicalReadValidationFreshnessSeconds) or 120)
local DEFAULT_LOG_THROTTLE_SECONDS =
	math.max(0, tonumber(CrewMemberShadowConfig.CanaryDiagnosticLogThrottleSeconds) or 60)

local dataManagerModule = nil
local lastDiagnosticLogByKey = {}
local disabledCanonicalReadsByPlayer = setmetatable({}, { __mode = "k" })

local DISPLAY_PATHS = {
	[CrewMemberCanonicalReadGate.Paths.InventoryDisplay] = true,
	[CrewMemberCanonicalReadGate.Paths.IndexDisplay] = true,
	[CrewMemberCanonicalReadGate.Paths.SellDialogDisplay] = true,
}

local PATH_SPECIFIC_DISPLAY_READ_FLAGS = {
	[CrewMemberCanonicalReadGate.Paths.InventoryDisplay] = "CrewMemberCanaryInventoryDisplayReadEnabled",
	[CrewMemberCanonicalReadGate.Paths.IndexDisplay] = "CrewMemberCanaryIndexDisplayReadEnabled",
	[CrewMemberCanonicalReadGate.Paths.SellDialogDisplay] = "CrewMemberCanarySellDialogDisplayReadEnabled",
}

local METADATA_HELPER_PATHS = {
	[CrewMemberCanonicalReadGate.Paths.MetadataHelperDisplayName] = "DisplayName",
	[CrewMemberCanonicalReadGate.Paths.MetadataHelperRarity] = "Rarity",
	[CrewMemberCanonicalReadGate.Paths.MetadataHelperRenderIcon] = "Render",
	[CrewMemberCanonicalReadGate.Paths.MetadataHelperRealCharacterName] = "RealCharacterName",
	[CrewMemberCanonicalReadGate.Paths.MetadataHelperArc] = "Arc",
	[CrewMemberCanonicalReadGate.Paths.MetadataHelperCompatibilityClassification] = "CompatibilityClassification",
}

local MODEL_PREVIEW_PATH_FLAGS = {
	[CrewMemberCanonicalReadGate.Paths.AdminModelPreview] = "CrewMemberCanaryAdminModelPreviewReadEnabled",
	[CrewMemberCanonicalReadGate.Paths.IndexModelPreview] = "CrewMemberCanaryIndexModelPreviewReadEnabled",
	[CrewMemberCanonicalReadGate.Paths.InventoryModelPreview] = "CrewMemberCanaryInventoryModelPreviewReadEnabled",
}

local GAMEPLAY_HELPER_PATH_FLAGS = {
	[CrewMemberCanonicalReadGate.Paths.GameplayHelperStandStatusDisplayName] =
		"CrewMemberCanaryStandStatusHelperReadEnabled",
	[CrewMemberCanonicalReadGate.Paths.GameplayHelperIncomeStatusDisplayName] =
		"CrewMemberCanaryIncomeStatusHelperReadEnabled",
	[CrewMemberCanonicalReadGate.Paths.GameplayHelperIncomeToastDisplayName] =
		"CrewMemberCanaryIncomeToastHelperReadEnabled",
	[CrewMemberCanonicalReadGate.Paths.GameplayHelperFoodStatusDisplayName] =
		"CrewMemberCanaryFoodStatusHelperReadEnabled",
}

local function getDataManager()
	if dataManagerModule == nil then
		dataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerModule
end

local function getPlayerName(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		return player.Name
	end
	return "unknown"
end

local function getPlayerKey(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		return tostring(player.UserId)
	end
	return "unknown"
end

local function recordLegacyFallbackUsage(player, category, surface, source, details)
	details = if typeof(details) == "table" then details else {}
	CrewMemberLegacyFallbackTelemetry.RecordUsage(category, surface, source, player, details)

	if typeof(player) == "Instance" and player:IsA("Player") then
		local ok, dataManager = pcall(getDataManager)
		if ok == true and typeof(dataManager) == "table" and dataManager.RecordLegacyDeprecationUsage then
			dataManager:RecordLegacyDeprecationUsage(player, "legacy_fallback", {
				Category = tostring(category or ""),
				Surface = tostring(surface or ""),
				Source = tostring(source or ""),
				Reason = tostring(details.Reason or ""),
				Denied = details.Denied == true,
			})
		end
	end
end

local function getFallbackPolicyReason(result)
	local reason = tostring(result.FallbackReason or "")
	if reason == "" or reason == "none" then
		reason = tostring(result.DisplayReadFallbackReason or "")
	end
	if reason == "" or reason == "none" then
		return nil
	end
	return reason
end

local function getFallbackPolicyIdentity(result)
	local candidates = {
		result.LegacyIdentity,
		result.ItemId,
		result.Identity,
		result.CanonicalIdentity,
	}

	for _, candidate in ipairs(candidates) do
		local value = tostring(candidate or "")
		if value ~= "" then
			return value
		end
	end

	if typeof(result.LegacyValue) == "string" and result.LegacyValue ~= "" then
		return result.LegacyValue
	end
	return ""
end

local function isColdReadFallback(result, reason)
	if result.CanonicalReadAllowed == false or tostring(result.ReadGateReason or "") ~= "" then
		return true
	end

	return reason == "helper_reads_disabled"
		or reason == "metadata_helper_reads_disabled"
		or reason == "gameplay_reads_disabled"
		or reason == "display_reads_disabled"
		or reason == "read_authority_disabled"
		or reason == "canonical_read_disabled"
		or reason == "canonical_read_not_allowed"
end

local function getAllowedFallbackPolicy(result, reason)
	local identity = getFallbackPolicyIdentity(result)
	local classification = tostring(result.CompatibilityClassification or "")

	if classification == "" then
		if string.find(reason, "brook_fallback", 1, true) then
			classification = "brook_fallback"
		elseif string.find(reason, "compatibility_only", 1, true) then
			classification = "compatibility_only"
		end
	end

	local brookDecision = CrewCompatibilityQuarantine.GetBrookFallbackDecision(identity)
	if brookDecision == nil and classification == "brook_fallback" then
		brookDecision = CrewCompatibilityQuarantine.GetBrookFallbackDecision(tostring(result.ItemId or ""))
	end
	if brookDecision ~= nil then
		return "allowedBrookFallback", "brook_fallback", identity, brookDecision
	end

	local compatibilityDecision = CrewCompatibilityQuarantine.GetCompatibilityOnlyDecision(identity)
	if compatibilityDecision == nil and classification == "compatibility_only" then
		compatibilityDecision = CrewCompatibilityQuarantine.GetCompatibilityOnlyDecision(tostring(result.ItemId or ""))
	end
	if compatibilityDecision ~= nil then
		return "allowedCompatibilityFallback", "compatibility_only", identity, compatibilityDecision
	end

	return nil, classification, identity
end

local function markFallbackPolicy(result, category, kind, identity, decision)
	result.FallbackPolicyCategory = category
	result.FallbackPolicyKind = kind
	result.FallbackPolicyIdentity = identity
	result.AllowedFallback = category == "allowedCompatibilityFallback" or category == "allowedBrookFallback"
	result.UnknownFallback = kind == "unknown_unapproved_fallback"
	result.CanonicalSelected = category == "canonicalSelected"
	if typeof(decision) == "table" then
		result.FallbackPolicyDisposition = tostring(decision.Disposition or "")
		result.FallbackPolicyStatusCategory = tostring(decision.StatusCategory or "")
		result.FallbackTelemetrySuppressed = decision.SuppressRuntimeFallbackTelemetry == true
	end
end

local function recordCanonicalSelected(result, surface, source)
	markFallbackPolicy(result, "canonicalSelected", "canonical", getFallbackPolicyIdentity(result))
	recordLegacyFallbackUsage(result.Player, "canonicalSelected", surface, source, {
		Denied = false,
		Reason = "canonical_selected",
	})
end

local function applyReadResultFallbackPolicy(result, category, surface, source)
	if typeof(result) ~= "table" then
		return false
	end

	local reason = getFallbackPolicyReason(result)
	if result.UsedCanonical == true or result.DisplayReadUseCanonical == true or reason == nil then
		recordCanonicalSelected(result, surface, source)
		return false
	end

	if isColdReadFallback(result, reason) then
		markFallbackPolicy(result, tostring(category or ""), "cold_read_fallback", getFallbackPolicyIdentity(result))
		result.FallbackTelemetrySuppressed = true
		return false
	end

	local policyCategory, policyKind, policyIdentity, policyDecision = getAllowedFallbackPolicy(result, reason)
	if policyCategory ~= nil then
		markFallbackPolicy(result, policyCategory, policyKind, policyIdentity, policyDecision)
		if not (typeof(policyDecision) == "table" and policyDecision.SuppressRuntimeFallbackTelemetry == true) then
			recordLegacyFallbackUsage(result.Player, policyCategory, surface, source, {
				Denied = false,
				Reason = reason,
			})
		end
		return false
	end

	markFallbackPolicy(result, tostring(category or ""), "unknown_unapproved_fallback", policyIdentity)
	recordLegacyFallbackUsage(result.Player, category, surface, source, {
		Denied = false,
		Reason = reason,
	})
	return false
end

local function getRoot(source)
	if typeof(source) == "table" and typeof(source.Data) == "table" then
		return source.Data, nil
	end
	if typeof(source) == "table" then
		return source, nil
	end
	if typeof(source) == "Instance" and source:IsA("Player") then
		local profile = getDataManager():TryGetProfile(source)
		if typeof(profile) == "table" and typeof(profile.Data) == "table" then
			return profile.Data, nil
		end
		return nil, "profile_unavailable"
	end
	return nil, "invalid_source"
end

local function getPathKind(path)
	local pathValue = tostring(path or "")
	if DISPLAY_PATHS[pathValue] == true or pathValue:find("%.display", 1, true) ~= nil then
		return "display"
	end
	if METADATA_HELPER_PATHS[pathValue] ~= nil or pathValue:find("metadata.helper", 1, true) ~= nil then
		return "metadata_helper"
	end
	if pathValue:find("model_preview", 1, true) ~= nil then
		return "model_preview"
	end
	if GAMEPLAY_HELPER_PATH_FLAGS[pathValue] ~= nil or pathValue:find("gameplay.helper", 1, true) ~= nil then
		return "gameplay_helper"
	end
	if pathValue:find("gameplay", 1, true) ~= nil then
		return "gameplay"
	end
	return "diagnostics"
end

local function isDiagnosticsEnabled(flags)
	return flags.CrewMemberDualReadEnabled == true
		and flags.CrewMemberCanaryDiagnosticsEnabled == true
end

local function isPathSpecificDisplayReadAllowedForPath(flags, path)
	local flagName = PATH_SPECIFIC_DISPLAY_READ_FLAGS[tostring(path or "")]
	if flagName == nil then
		return false, "canonical_read_disabled"
	end
	if flags.CrewMemberDualReadEnabled ~= true then
		return false, "dual_read_disabled"
	end
	if flags.CrewMemberCanaryDisplayReadsEnabled ~= true then
		return false, "display_reads_disabled"
	end
	if flags[flagName] ~= true then
		return false, "path_display_read_disabled"
	end
	return true, nil
end

local function isPathSpecificMetadataHelperReadAllowedForPath(flags, path)
	if METADATA_HELPER_PATHS[tostring(path or "")] == nil then
		return false, "canonical_read_disabled"
	end
	if flags.CrewMemberDualReadEnabled ~= true then
		return false, "dual_read_disabled"
	end
	if flags.CrewMemberCanaryGameplayHelperReadsEnabled ~= true then
		return false, "helper_reads_disabled"
	end
	if flags.CrewMemberCanaryMetadataHelperReadsEnabled ~= true then
		return false, "metadata_helper_reads_disabled"
	end
	return true, nil
end

local function isPathSpecificModelPreviewReadAllowedForPath(flags, path)
	local flagName = MODEL_PREVIEW_PATH_FLAGS[tostring(path or "")]
	if flagName == nil then
		return false, "canonical_read_disabled"
	end
	if flags.CrewMemberDualReadEnabled ~= true then
		return false, "dual_read_disabled"
	end
	if flags.CrewMemberCanaryModelPreviewReadsEnabled ~= true then
		return false, "model_preview_reads_disabled"
	end
	if flags[flagName] ~= true then
		return false, "path_model_preview_read_disabled"
	end
	return true, nil
end

local function isPathSpecificGameplayHelperReadAllowedForPath(flags, path)
	local flagName = GAMEPLAY_HELPER_PATH_FLAGS[tostring(path or "")]
	if flagName == nil then
		return false, "canonical_read_disabled"
	end
	if flags.CrewMemberDualReadEnabled ~= true then
		return false, "dual_read_disabled"
	end
	if flags.CrewMemberCanaryGameplayHelperReadsEnabled ~= true then
		return false, "helper_reads_disabled"
	end
	if flags[flagName] ~= true then
		return false, "path_gameplay_helper_read_disabled"
	end
	return true, nil
end

local function isPathSpecificStandStatusReadAuthorityAllowed(flags, path)
	if tostring(path or "") ~= CrewMemberCanonicalReadGate.Paths.ReadAuthorityStandStatus then
		return false, "canonical_read_disabled"
	end
	if flags.CrewMemberDualReadEnabled ~= true then
		return false, "dual_read_disabled"
	end
	if flags.CrewMemberCanaryReadAuthorityEnabled ~= true then
		return false, "read_authority_disabled"
	end
	if flags.CrewMemberCanaryStandStatusReadAuthorityEnabled ~= true then
		return false, "stand_status_read_authority_disabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		return false, "write_authority_enabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		return false, "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		return false, "gameplay_reads_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		return false, "global_canonical_read_enabled"
	end
	return true, nil
end

local function isPathSpecificIncomeStatusReadAuthorityAllowed(flags, path)
	if tostring(path or "") ~= CrewMemberCanonicalReadGate.Paths.ReadAuthorityIncomeStatus then
		return false, "canonical_read_disabled"
	end
	if flags.CrewMemberDualReadEnabled ~= true then
		return false, "dual_read_disabled"
	end
	if flags.CrewMemberCanaryReadAuthorityEnabled ~= true then
		return false, "read_authority_disabled"
	end
	if flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled ~= true then
		return false, "income_status_read_authority_disabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		return false, "write_authority_enabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		return false, "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		return false, "gameplay_reads_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		return false, "global_canonical_read_enabled"
	end
	return true, nil
end

local function isPathSpecificFoodStatusReadAuthorityAllowed(flags, path)
	if tostring(path or "") ~= CrewMemberCanonicalReadGate.Paths.ReadAuthorityFoodStatus then
		return false, "canonical_read_disabled"
	end
	if flags.CrewMemberDualReadEnabled ~= true then
		return false, "dual_read_disabled"
	end
	if flags.CrewMemberCanaryReadAuthorityEnabled ~= true then
		return false, "read_authority_disabled"
	end
	if flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled ~= true then
		return false, "food_status_read_authority_disabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		return false, "write_authority_enabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		return false, "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		return false, "gameplay_reads_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		return false, "global_canonical_read_enabled"
	end
	return true, nil
end

local function isCanonicalReadAllowedForPath(flags, path)
	if flags.CrewMemberCanonicalReadEnabled ~= true then
		if METADATA_HELPER_PATHS[tostring(path or "")] ~= nil then
			return isPathSpecificMetadataHelperReadAllowedForPath(flags, path)
		end
		if MODEL_PREVIEW_PATH_FLAGS[tostring(path or "")] ~= nil then
			return isPathSpecificModelPreviewReadAllowedForPath(flags, path)
		end
		if GAMEPLAY_HELPER_PATH_FLAGS[tostring(path or "")] ~= nil then
			return isPathSpecificGameplayHelperReadAllowedForPath(flags, path)
		end
		return isPathSpecificDisplayReadAllowedForPath(flags, path)
	end

	local pathKind = getPathKind(path)
	if pathKind == "display" and flags.CrewMemberCanaryDisplayReadsEnabled ~= true then
		return false, "display_reads_disabled"
	end
	if pathKind == "metadata_helper" then
		return isPathSpecificMetadataHelperReadAllowedForPath(flags, path)
	end
	if pathKind == "model_preview" then
		return isPathSpecificModelPreviewReadAllowedForPath(flags, path)
	end
	if pathKind == "gameplay_helper" then
		return isPathSpecificGameplayHelperReadAllowedForPath(flags, path)
	end
	if pathKind == "gameplay" and flags.CrewMemberCanaryGameplayReadsEnabled ~= true then
		return false, "gameplay_reads_disabled"
	end

	return true, nil
end

local function normalizeDisplayMetadata(value, fallbackName, source)
	if typeof(value) ~= "table" then
		return nil
	end

	local displayInfo = CrewCatalog.GetDisplayInfo(value.CrewMemberId or value.StorageName or fallbackName, value)
	local displayName = displayInfo.DisplayName
		or value.DisplayName
		or value.CrewMemberDisplayName
		or value.CrewMemberName
		or value.Name
		or fallbackName
	return {
		DisplayName = tostring(displayName or ""),
		Rarity = tostring(value.Rarity or ""),
		Render = tostring(value.Render or value.Image or ""),
		RealCharacterName = tostring(value.RealCharacterName or ""),
		Arc = tostring(value.Arc or value.CrewArc or ""),
		CompatibilityClassification = tostring(value.CompatibilityClassification or ""),
		Source = tostring(source or value.Source or ""),
	}
end

local function classifyCrewMember(storageName, info)
	local id = tostring(storageName or "")
	local isProductionCrew = typeof(info) == "table" and info.RealCharacterName ~= nil
	local isUnknownLegacyId = id ~= "" and typeof(info) ~= "table"
	local isCompatibilityOnly = typeof(info) == "table" and not isProductionCrew
	local isBrookFallback = typeof(info) == "table"
		and info.MissingCrewModel == true
		and (
			id == "Gangster Footera"
			or tostring(info.DisplayName or "") == "Soul Fiddler"
			or tostring(info.RealCharacterName or "") == "Brook"
		)

	if isBrookFallback then
		return "brook_fallback"
	end
	if isUnknownLegacyId then
		return "unknown_legacy_id"
	end
	if isCompatibilityOnly then
		return "compatibility_only"
	end
	if isProductionCrew then
		return "production_crew"
	end
	return "unknown"
end

local function applyCompatibilityClassification(metadata, storageName, info)
	if typeof(metadata) == "table" then
		metadata.CompatibilityClassification = classifyCrewMember(storageName, info)
	end
	return metadata
end

local function buildLegacyDisplayMetadata(storageName)
	local id = tostring(storageName or "")
	local legacyInfo = CrewCatalog.GetInfoById(id)
	local metadata = normalizeDisplayMetadata(legacyInfo, id, "LegacyDisplayAdapter")
	if metadata then
		return applyCompatibilityClassification(metadata, id, legacyInfo), nil
	end
	return {
		DisplayName = id,
		Rarity = "",
		Render = "",
		RealCharacterName = "",
		Arc = "",
		CompatibilityClassification = "unknown_legacy_id",
		Source = "CrewCatalogMissing",
	}, "legacy_config_missing"
end

local function getCanonicalCrewMemberId(storageName, info)
	local fallback = tostring(storageName or "")
	local canonicalId, resolvedInfo = CrewCatalog.ResolveCrewMemberId(fallback)
	if resolvedInfo then
		return canonicalId
	end
	if typeof(info) == "table" and tostring(info.CrewMemberId or "") ~= "" then
		return tostring(info.CrewMemberId)
	end
	return fallback
end

local function buildCanonicalCatalogMetadata(storageName)
	local id = tostring(storageName or "")
	local info = CrewCatalog.GetInfoById(id)
	local metadata = normalizeDisplayMetadata(info, id, "CrewCatalog")
	if metadata then
		metadata.CrewMemberId = getCanonicalCrewMemberId(id, info)
		applyCompatibilityClassification(metadata, id, info)
	end
	return metadata
end

local function getCanonicalInventory(root)
	if typeof(root) ~= "table" then
		return nil
	end
	return root[CrewProfileSchema.Keys.Inventory]
end

local function inventoryInstanceMatches(instanceData, storageName)
	if typeof(instanceData) ~= "table" then
		return false
	end

	local id = tostring(storageName or "")
	return tostring(instanceData.LegacyStorageName or "") == id
		or tostring(instanceData.CrewMemberId or "") == id
		or tostring(instanceData.StorageName or "") == id
end

local function findCanonicalInventoryMetadata(root, storageName, includeAssigned)
	local inventory = getCanonicalInventory(root)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return nil, "canonical_inventory_missing"
	end

	local function useInstance(instanceData)
		if not inventoryInstanceMatches(instanceData, storageName) then
			return nil
		end
		if includeAssigned ~= true and tostring(instanceData.AssignedStand or "") ~= "" then
			return nil
		end
		return normalizeDisplayMetadata(instanceData, storageName, "CrewMemberInventory")
	end

	if typeof(inventory.Order) == "table" then
		for _, rawInstanceId in ipairs(inventory.Order) do
			local metadata = useInstance(inventory.ById[tostring(rawInstanceId)])
			if metadata then
				return metadata, nil
			end
		end
	end

	for _, instanceData in pairs(inventory.ById) do
		local metadata = useInstance(instanceData)
		if metadata then
			return metadata, nil
		end
	end

	return nil, "canonical_inventory_entry_missing"
end

local function buildCanonicalInventoryMetadata(root, storageName, includeAssigned)
	local metadata, reason = findCanonicalInventoryMetadata(root, storageName, includeAssigned)
	if metadata then
		return metadata, nil
	end

	local catalogMetadata = buildCanonicalCatalogMetadata(storageName)
	if catalogMetadata then
		catalogMetadata.Source = "CrewCatalogProjection"
		return catalogMetadata, reason
	end

	return nil, reason or "canonical_catalog_missing"
end

local function buildCanonicalIndexMetadata(root, storageName)
	local catalogMetadata = buildCanonicalCatalogMetadata(storageName)
	if not catalogMetadata then
		return nil, "canonical_catalog_missing"
	end

	local indexCollection = if typeof(root) == "table" then root[CrewProfileSchema.Keys.IndexCollection] else nil
	local canonicalIndex = if typeof(indexCollection) == "table" then indexCollection[CrewProfileSchema.Keys.Index] else nil
	if typeof(canonicalIndex) == "table" then
		local canonicalId = tostring(catalogMetadata.CrewMemberId or storageName or "")
		if canonicalId ~= "" and canonicalIndex[canonicalId] ~= true then
			catalogMetadata.Source = "CrewCatalogProjection"
			return catalogMetadata, "canonical_index_entry_not_discovered"
		end
	end

	catalogMetadata.Source = "CrewCatalogProjection"
	return catalogMetadata, nil
end

local function metadataMatches(legacyValue, canonicalValue)
	if typeof(legacyValue) ~= "table" or typeof(canonicalValue) ~= "table" then
		return false
	end

	return tostring(legacyValue.DisplayName or "") == tostring(canonicalValue.DisplayName or "")
		and tostring(legacyValue.Rarity or "") == tostring(canonicalValue.Rarity or "")
		and tostring(legacyValue.Render or "") == tostring(canonicalValue.Render or "")
end

local function metadataToText(value)
	if typeof(value) ~= "table" then
		return "<nil>"
	end

	return string.format(
		"{display=%s rarity=%s render=%s source=%s}",
		tostring(value.DisplayName or ""),
		tostring(value.Rarity or ""),
		tostring(value.Render or ""),
		tostring(value.Source or "")
	)
end

local function getBlockingCounts(status)
	return {
		Total = status and status.BlockingIssueCount or 0,
		Mismatch = status and status.MismatchCount or 0,
		Stand = status and status.StandIssueCount or 0,
		Duplicate = status and status.DuplicateIssueCount or 0,
		Unknown = status and status.UnknownLegacyIdCount or 0,
		BlockingIncomeMismatch = status and status.BlockingIncomeMismatchCount or 0,
		CompatibilityOnly = status and status.CompatibilityOnlyIdCount or 0,
		BrookFallback = status and status.BrookFallbackCount or 0,
	}
end

local function getValidationStatus(root, player, options)
	local status = CrewMemberShadowWriter.GetLastValidationStatus(root, {
		Player = player,
	})
	if status == nil then
		return nil, "validation_missing"
	end

	local maxAgeSeconds = tonumber(options.MaxValidationAgeSeconds) or DEFAULT_VALIDATION_FRESHNESS_SECONDS
	local ageSeconds = tonumber(status.ValidationAgeSeconds) or math.huge
	if maxAgeSeconds > 0 and ageSeconds > maxAgeSeconds then
		return status, "validation_stale"
	end

	local keys = status.CanonicalKeys
	if typeof(keys) ~= "table" or keys.IsValid ~= true then
		return status, "canonical_key_shape_invalid"
	end

	if options.Flags and options.Flags.CrewMemberCanonicalReadStrictValidation ~= nil then
		if options.Flags.CrewMemberCanonicalReadStrictValidation ~= true then
			return status, nil
		end
	end

	if (status.BlockingIssueCount or 0) > 0
		or (status.MismatchCount or 0) > 0
		or (status.StandIssueCount or 0) > 0
		or (status.DuplicateIssueCount or 0) > 0
		or (status.UnknownLegacyIdCount or 0) > 0
		or (status.BlockingIncomeMismatchCount or 0) > 0
	then
		return status, "validation_blocking_counts"
	end

	return status, nil
end

local function isDisabledForPlayer(player, path)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local disabled = disabledCanonicalReadsByPlayer[player]
	return typeof(disabled) == "table" and disabled[tostring(path or "")] == true
end

local function disableForPlayer(player, path)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local disabled = disabledCanonicalReadsByPlayer[player]
	if typeof(disabled) ~= "table" then
		disabled = {}
		disabledCanonicalReadsByPlayer[player] = disabled
	end
	disabled[tostring(path or "")] = true
end

local function makeFallbackReason(result)
	if result.CanonicalAvailable ~= true then
		return result.CanonicalUnavailableReason or "canonical_unavailable"
	end
	if result.ValidationValid ~= true then
		return result.ValidationReason or "validation_invalid"
	end
	if result.DisabledByMismatch == true then
		return "mismatch_disabled"
	end
	if result.Match ~= true then
		return "value_mismatch"
	end
	if result.CanonicalReadAllowed ~= true then
		return result.ReadGateReason or "canonical_read_not_allowed"
	end
	return "diagnostics_only_legacy_authority"
end

local function getDisplayNameFromMetadata(value)
	if typeof(value) ~= "table" then
		return nil
	end

	local displayName = tostring(value.DisplayName or "")
	if displayName == "" then
		return nil
	end
	return displayName
end

local function cloneDisplayMetadata(value)
	if typeof(value) ~= "table" then
		return nil
	end

	local displayName = getDisplayNameFromMetadata(value)
	if displayName == nil then
		return nil
	end

	return {
		DisplayName = displayName,
		Rarity = tostring(value.Rarity or ""),
		Render = tostring(value.Render or ""),
		Source = tostring(value.Source or ""),
	}
end

local function chooseCanonicalDisplayMetadata(result)
	local legacyDisplayName = getDisplayNameFromMetadata(result.LegacyValue)
	local canonicalDisplayName = getDisplayNameFromMetadata(result.CanonicalValue)
	local legacyMetadata = cloneDisplayMetadata(result.LegacyValue)
	local canonicalMetadata = cloneDisplayMetadata(result.CanonicalValue)

	result.LegacyFallbackDisplayName = legacyDisplayName
	result.CanonicalDisplayName = canonicalDisplayName
	result.DisplayReadUseCanonical = false
	result.DisplayReadFallbackReason = nil

	if result.CanonicalReadAllowed ~= true then
		result.DisplayReadFallbackReason = result.ReadGateReason or "canonical_read_not_allowed"
	elseif result.ValidationValid ~= true then
		result.DisplayReadFallbackReason = result.ValidationReason or "validation_invalid"
	elseif result.CanonicalAvailable ~= true then
		result.DisplayReadFallbackReason = result.CanonicalUnavailableReason or "canonical_unavailable"
	elseif result.DisabledByMismatch == true then
		result.DisplayReadFallbackReason = "mismatch_disabled"
	elseif result.Match ~= true then
		result.DisplayReadFallbackReason = "value_mismatch"
	elseif canonicalMetadata == nil then
		result.DisplayReadFallbackReason = "canonical_display_metadata_missing"
	elseif legacyMetadata == nil then
		result.DisplayReadFallbackReason = "legacy_fallback_missing"
	else
		result.DisplayReadUseCanonical = true
		result.DisplayReadFallbackReason = "none"
		result.SelectedValue = canonicalMetadata
	end

	if result.DisplayReadUseCanonical ~= true then
		applyReadResultFallbackPolicy(
			result,
			"display_helper_legacy_fallback",
			result.Path,
			"display_metadata"
		)
		result.SelectedValue = legacyMetadata or {
			DisplayName = tostring(result.ItemId or ""),
			Rarity = "",
			Render = "",
			Source = "LegacyFallbackMissing",
		}
	else
		recordCanonicalSelected(result, result.Path, "display_metadata")
		result.SelectedValue = canonicalMetadata
	end

	if result.DisplayReadUseCanonical ~= true and result.SelectedValue == nil then
		result.SelectedValue = legacyMetadata or {
			DisplayName = tostring(result.ItemId or ""),
			Rarity = "",
			Render = "",
			Source = "LegacyFallbackMissing",
		}
	end

	result.SelectedDisplayMetadata = result.SelectedValue
	result.SelectedDisplayName = getDisplayNameFromMetadata(result.SelectedDisplayMetadata)
		or tostring(result.ItemId or "")

	return result.SelectedDisplayMetadata, result
end

local function chooseCanonicalDisplayName(result)
	local metadata = chooseCanonicalDisplayMetadata(result)
	return getDisplayNameFromMetadata(metadata) or tostring(result.ItemId or ""), result
end

local function getMetadataFieldValue(metadata, fieldName)
	if typeof(metadata) ~= "table" then
		return nil
	end

	local rawValue = metadata[fieldName]
	if rawValue == nil then
		return nil
	end

	local value = tostring(rawValue)
	if value == "" then
		return nil
	end
	return value
end

local function metadataHelperResultFallbackReason(result)
	if result.CanonicalReadAllowed ~= true then
		return result.ReadGateReason or "canonical_read_not_allowed"
	end
	if result.ValidationValid ~= true then
		return result.ValidationReason or "validation_invalid"
	end
	if result.CanonicalValue == nil then
		return "canonical_metadata_field_missing"
	end
	if result.LegacyValue == nil then
		return "legacy_fallback_missing"
	end
	if result.DisabledByMismatch == true then
		return "mismatch_disabled"
	end
	if result.Match ~= true then
		return "value_mismatch"
	end
	return nil
end

local function metadataHelperValueToText(value)
	if value == nil then
		return "<nil>"
	end
	return tostring(value)
end

local function logMetadataHelperResult(result)
	if result.DiagnosticsEnabled ~= true then
		return
	end

	local throttleSeconds = math.max(0, tonumber(result.LogThrottleSeconds) or DEFAULT_LOG_THROTTLE_SECONDS)
	local key = table.concat({
		getPlayerKey(result.Player),
		tostring(result.Path or ""),
		tostring(result.ItemId or ""),
	}, "|")
	local counts = result.BlockingCounts or {}
	local signature = table.concat({
		tostring(result.UsedCanonical),
		tostring(result.FallbackReason),
		tostring(result.Match),
		tostring(result.ValidationValid),
		metadataHelperValueToText(result.LegacyValue),
		metadataHelperValueToText(result.CanonicalValue),
		tostring(counts.Total or 0),
		tostring(counts.Mismatch or 0),
		tostring(counts.Stand or 0),
		tostring(counts.Duplicate or 0),
		tostring(counts.Unknown or 0),
		tostring(counts.BlockingIncomeMismatch or 0),
	}, "|")
	local now = os.clock()
	local last = lastDiagnosticLogByKey[key]
	if typeof(last) == "table"
		and last.Signature == signature
		and throttleSeconds > 0
		and now - (tonumber(last.At) or 0) < throttleSeconds
	then
		return
	end
	lastDiagnosticLogByKey[key] = {
		At = now,
		Signature = signature,
	}

	local message = string.format(
		"%s helper player=%s path=%s item=%s usedCanonical=%s legacy=%s canonical=%s fallback=%s validationAge=%.1fs blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(result.Player),
		tostring(result.Path or ""),
		tostring(result.ItemId or ""),
		tostring(result.UsedCanonical == true),
		metadataHelperValueToText(result.LegacyValue),
		metadataHelperValueToText(result.CanonicalValue),
		tostring(result.FallbackReason or "none"),
		tonumber(result.ValidationAge) or -1,
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	)

	if result.UsedCanonical == true or result.ReadGateReason ~= nil then
		print(message)
	else
		warn(message)
	end
end

local function getApprovedModelPreviewRoot()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	return assets and assets:FindFirstChild("One Piece Characters") or nil
end

local function findPreviewModel(root, modelName)
	if not root then
		return nil
	end

	local name = tostring(modelName or "")
	if name == "" then
		return nil
	end

	local direct = root:FindFirstChild(name)
	if direct and direct:IsA("Model") then
		return direct
	end

	local descendant = root:FindFirstChild(name, true)
	if descendant and descendant:IsA("Model") then
		return descendant
	end

	return nil
end

local function modelPassesPreviewSafeChecks(model)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return false, "preview_model_not_model"
	end
	if model.Archivable == false then
		return false, "preview_model_not_archivable"
	end

	local descendants = model:GetDescendants()
	if #descendants > 5000 then
		return false, "preview_model_too_large"
	end

	for _, descendant in ipairs(descendants) do
		if descendant:IsA("BasePart") or descendant:IsA("Humanoid") then
			return true, nil
		end
	end

	return false, "preview_model_no_visual_descendants"
end

local function buildModelPreviewDescriptor(storageName, modelName, model, usedCanonical, fallbackReason, sourceName, path)
	return {
		ModelName = tostring(modelName or ""),
		ModelPath = if typeof(model) == "Instance" then model:GetFullName() else "",
		UsedCanonical = usedCanonical == true,
		FallbackReason = fallbackReason,
		IsPreviewOnly = true,
		LegacyIdentity = tostring(storageName or ""),
		Path = tostring(path or ""),
		Source = tostring(sourceName or ""),
	}
end

local function buildCanonicalModelPreviewDescriptor(storageName, path)
	local id = tostring(storageName or "")
	local info = CrewCatalog.GetInfoById(id)
	if typeof(info) ~= "table" then
		return nil, "canonical_model_metadata_missing"
	end

	local classification = classifyCrewMember(id, info)
	if classification == "brook_fallback" or info.MissingCrewModel == true then
		return nil, "brook_fallback_model"
	end
	if classification ~= "production_crew" then
		return nil, "compatibility_only_model_preview_fallback"
	end

	local modelName = tostring(info.ModelName or "")
	if modelName == "" then
		return nil, "canonical_model_metadata_missing"
	end

	local root = getApprovedModelPreviewRoot()
	if not root then
		return nil, "preview_asset_root_missing"
	end

	local model = findPreviewModel(root, modelName)
	if not model then
		return nil, "canonical_preview_model_missing"
	end

	local safe, reason = modelPassesPreviewSafeChecks(model)
	if safe ~= true then
		return nil, reason
	end

	return buildModelPreviewDescriptor(storageName, modelName, model, true, nil, "One Piece Characters", path), nil
end

local function logModelPreviewResult(result)
	if result.DiagnosticsEnabled ~= true then
		return
	end

	local counts = result.BlockingCounts or {}
	print(string.format(
		"%s model-preview player=%s path=%s legacyIdentity=%s model=%s usedCanonical=%s fallback=%s modelPath=%s validationAge=%.1fs blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(result.Player),
		tostring(result.Path or ""),
		tostring(result.LegacyIdentity or ""),
		tostring(result.ModelName or ""),
		tostring(result.UsedCanonical == true),
		tostring(result.FallbackReason or "none"),
		tostring(result.ModelPath or ""),
		tonumber(result.ValidationAgeSeconds) or -1,
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	))
end

local function evaluateModelPreviewRead(source, path, storageName, options)
	options = if typeof(options) == "table" then options else {}
	local player = if typeof(options.Player) == "Instance" and options.Player:IsA("Player")
		then options.Player
		elseif typeof(source) == "Instance" and source:IsA("Player") then source
		else nil
	local root, rootReason = getRoot(source)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local diagnosticsEnabled = isDiagnosticsEnabled(flags)
	local readAllowed, readGateReason = isCanonicalReadAllowedForPath(flags, path)
	local validationStatus, validationReason = nil, "validation_missing"

	if root ~= nil then
		validationStatus, validationReason = getValidationStatus(root, player, {
			Flags = flags,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	else
		validationReason = rootReason or "invalid_source"
	end

	local canonicalDescriptor, canonicalReason = buildCanonicalModelPreviewDescriptor(storageName, path)
	local fallbackReason = nil
	local selected = canonicalDescriptor

	if readAllowed ~= true then
		fallbackReason = readGateReason or "canonical_read_not_allowed"
	elseif canonicalDescriptor ~= nil then
		selected = canonicalDescriptor
	elseif validationReason ~= nil then
		fallbackReason = validationReason
	elseif canonicalDescriptor == nil then
		fallbackReason = canonicalReason or "canonical_preview_unavailable"
	end

	if selected == nil then
		selected = buildModelPreviewDescriptor(
			storageName,
			storageName,
			nil,
			false,
			fallbackReason or "preview_descriptor_unavailable",
			"Unavailable",
			path
		)
	end

	local counts = getBlockingCounts(validationStatus)
	local result = table.clone(selected)
	result.Player = player
	result.Flags = flags
	result.DiagnosticsEnabled = diagnosticsEnabled
	result.CanonicalReadAllowed = readAllowed
	result.ReadGateReason = readGateReason
	result.ValidationStatus = validationStatus
	result.ValidationValid = validationReason == nil
	result.ValidationReason = validationReason
	result.ValidationAge = if validationStatus then validationStatus.ValidationAgeSeconds else -1
	result.ValidationAgeSeconds = if validationStatus then validationStatus.ValidationAgeSeconds else -1
	result.BlockingCounts = counts
	result.CanonicalDescriptor = canonicalDescriptor
	result.CanonicalUnavailableReason = canonicalReason

	if fallbackReason ~= nil then
		result.UsedCanonical = false
		result.FallbackReason = fallbackReason
	end

	if options.SkipLog ~= true then
		logModelPreviewResult(result)
	end

	return result, result
end

local function evaluateMetadataHelperRead(source, path, storageName, fieldName, options)
	options = if typeof(options) == "table" then options else {}
	local player = if typeof(options.Player) == "Instance" and options.Player:IsA("Player")
		then options.Player
		elseif typeof(source) == "Instance" and source:IsA("Player") then source
		else nil
	local root, rootReason = getRoot(source)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local diagnosticsEnabled = isDiagnosticsEnabled(flags)
	local readAllowed, readGateReason = isCanonicalReadAllowedForPath(flags, path)
	local validationStatus, validationReason = nil, "validation_missing"

	if root ~= nil then
		validationStatus, validationReason = getValidationStatus(root, player, {
			Flags = flags,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	else
		validationReason = rootReason or "invalid_source"
	end

	local legacyMetadata = buildLegacyDisplayMetadata(storageName)
	local canonicalMetadata = buildCanonicalCatalogMetadata(storageName)
	local legacyValue = getMetadataFieldValue(legacyMetadata, fieldName)
	local canonicalValue = getMetadataFieldValue(canonicalMetadata, fieldName)
	local match = canonicalValue ~= nil and legacyValue ~= nil and canonicalValue == legacyValue
	local disabledByMismatch = isDisabledForPlayer(player, path)
	if canonicalValue ~= nil
		and legacyValue ~= nil
		and match ~= true
		and flags.CrewMemberCanonicalReadDisableOnMismatch == true
	then
		disableForPlayer(player, path)
		disabledByMismatch = true
	end

	local counts = getBlockingCounts(validationStatus)
	local result = {
		Value = legacyValue,
		UsedCanonical = false,
		FallbackReason = nil,
		LegacyValue = legacyValue,
		CanonicalValue = canonicalValue,
		Path = tostring(path or ""),
		ItemId = tostring(storageName or ""),
		Identity = tostring(storageName or ""),
		Player = player,
		Flags = flags,
		DiagnosticsEnabled = diagnosticsEnabled,
		CanonicalReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationStatus = validationStatus,
		ValidationValid = validationReason == nil,
		ValidationReason = validationReason,
		ValidationAge = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		ValidationAgeSeconds = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		BlockingCounts = counts,
		Match = match,
		ComparisonValid = diagnosticsEnabled
			and canonicalValue ~= nil
			and validationReason == nil,
		DisabledByMismatch = disabledByMismatch,
		LogThrottleSeconds = options.LogThrottleSeconds,
	}
	result.FallbackReason = metadataHelperResultFallbackReason(result)

	if result.FallbackReason == nil then
		result.Value = canonicalValue
		result.UsedCanonical = true
		recordCanonicalSelected(result, path, "metadata_helper")
	else
		applyReadResultFallbackPolicy(
			result,
			"display_helper_legacy_fallback",
			path,
			"metadata_helper"
		)
		result.Value = legacyValue
	end

	if options.SkipLog ~= true then
		logMetadataHelperResult(result)
	end

	return result.Value, result
end

local function buildCanonicalStandStatusDisplayName(storageName)
	local metadata = buildCanonicalCatalogMetadata(storageName)
	if typeof(metadata) ~= "table" then
		return nil, "canonical_metadata_field_missing"
	end

	local classification = tostring(metadata.CompatibilityClassification or "")
	if classification == "brook_fallback" then
		return nil, "brook_fallback_stand_status_display_name"
	end
	if classification ~= "production_crew" then
		return nil, "compatibility_only_stand_status_display_name"
	end

	return getMetadataFieldValue(metadata, "DisplayName"), nil
end

local function buildCanonicalIncomeStatusDisplayName(storageName)
	local metadata = buildCanonicalCatalogMetadata(storageName)
	if typeof(metadata) ~= "table" then
		return nil, "canonical_metadata_field_missing"
	end

	local classification = tostring(metadata.CompatibilityClassification or "")
	if classification == "brook_fallback" then
		return nil, "brook_fallback_income_status_display_name"
	end
	if classification ~= "production_crew" then
		return nil, "compatibility_only_income_status_display_name"
	end

	return getMetadataFieldValue(metadata, "DisplayName"), nil
end

local function buildCanonicalIncomeToastDisplayName(storageName)
	local metadata = buildCanonicalCatalogMetadata(storageName)
	if typeof(metadata) ~= "table" then
		return nil, "canonical_metadata_field_missing"
	end

	local classification = tostring(metadata.CompatibilityClassification or "")
	if classification == "brook_fallback" then
		return nil, "brook_fallback_income_toast_display_name"
	end
	if classification ~= "production_crew" then
		return nil, "compatibility_only_income_toast_display_name"
	end

	return getMetadataFieldValue(metadata, "DisplayName"), nil
end

local function buildCanonicalFoodStatusDisplayName(storageName)
	local metadata = buildCanonicalCatalogMetadata(storageName)
	if typeof(metadata) ~= "table" then
		return nil, "canonical_metadata_field_missing"
	end

	local classification = tostring(metadata.CompatibilityClassification or "")
	if classification == "brook_fallback" then
		return nil, "brook_fallback_food_status_display_name"
	end
	if classification ~= "production_crew" then
		return nil, "compatibility_only_food_status_display_name"
	end

	return getMetadataFieldValue(metadata, "DisplayName"), nil
end

local function gameplayHelperResultFallbackReason(result)
	if result.CanonicalReadAllowed ~= true then
		return result.ReadGateReason or "canonical_read_not_allowed"
	end
	if result.ValidationValid ~= true then
		return result.ValidationReason or "validation_invalid"
	end
	if result.CanonicalValue == nil then
		return result.CanonicalUnavailableReason or "canonical_metadata_field_missing"
	end
	if result.LegacyValue == nil then
		return "legacy_fallback_missing"
	end
	if result.DisabledByMismatch == true then
		return "mismatch_disabled"
	end
	if result.Match ~= true then
		return "value_mismatch"
	end
	return nil
end

local function logGameplayHelperResult(result)
	if result.DiagnosticsEnabled ~= true then
		return
	end

	local throttleSeconds = math.max(0, tonumber(result.LogThrottleSeconds) or DEFAULT_LOG_THROTTLE_SECONDS)
	local key = table.concat({
		getPlayerKey(result.Player),
		tostring(result.Path or ""),
		tostring(result.LegacyIdentity or result.ItemId or ""),
	}, "|")
	local counts = result.BlockingCounts or {}
	local signature = table.concat({
		tostring(result.UsedCanonical),
		tostring(result.FallbackReason),
		tostring(result.Match),
		tostring(result.ValidationValid),
		metadataHelperValueToText(result.LegacyValue),
		metadataHelperValueToText(result.CanonicalValue),
		tostring(counts.Total or 0),
		tostring(counts.Mismatch or 0),
		tostring(counts.Stand or 0),
		tostring(counts.Duplicate or 0),
		tostring(counts.Unknown or 0),
		tostring(counts.BlockingIncomeMismatch or 0),
	}, "|")
	local now = os.clock()
	local last = lastDiagnosticLogByKey[key]
	if typeof(last) == "table"
		and last.Signature == signature
		and throttleSeconds > 0
		and now - (tonumber(last.At) or 0) < throttleSeconds
	then
		return
	end
	lastDiagnosticLogByKey[key] = {
		At = now,
		Signature = signature,
	}

	local message = string.format(
		"%s gameplay-helper player=%s path=%s legacyIdentity=%s usedCanonical=%s authoritative=%s legacy=%s canonical=%s fallback=%s validationAge=%.1fs blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(result.Player),
		tostring(result.Path or ""),
		tostring(result.LegacyIdentity or ""),
		tostring(result.UsedCanonical == true),
		tostring(result.IsAuthoritative == true),
		metadataHelperValueToText(result.LegacyValue),
		metadataHelperValueToText(result.CanonicalValue),
		tostring(result.FallbackReason or "none"),
		tonumber(result.ValidationAge) or -1,
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	)

	if result.UsedCanonical == true or result.ReadGateReason ~= nil then
		print(message)
	else
		warn(message)
	end
end

local function evaluateGameplayDisplayNameHelper(source, storageName, path, canonicalBuilder, options)
	local player = if typeof(options.Player) == "Instance" and options.Player:IsA("Player")
		then options.Player
		elseif typeof(source) == "Instance" and source:IsA("Player") then source
		else nil
	local root, rootReason = getRoot(source)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local diagnosticsEnabled = isDiagnosticsEnabled(flags)
	local readAllowed, readGateReason = isCanonicalReadAllowedForPath(flags, path)
	local validationStatus, validationReason = nil, "validation_missing"

	if root ~= nil then
		validationStatus, validationReason = getValidationStatus(root, player, {
			Flags = flags,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	else
		validationReason = rootReason or "invalid_source"
	end

	local legacyMetadata = buildLegacyDisplayMetadata(storageName)
	local legacyValue = getMetadataFieldValue(legacyMetadata, "DisplayName") or tostring(storageName or "")
	local canonicalValue, canonicalReason = canonicalBuilder(storageName)
	local match = canonicalValue ~= nil and legacyValue ~= nil and canonicalValue == legacyValue
	local disabledByMismatch = isDisabledForPlayer(player, path)
	if canonicalValue ~= nil
		and legacyValue ~= nil
		and match ~= true
		and flags.CrewMemberCanonicalReadDisableOnMismatch == true
	then
		disableForPlayer(player, path)
		disabledByMismatch = true
	end

	local counts = getBlockingCounts(validationStatus)
	local result = {
		Value = legacyValue,
		UsedCanonical = false,
		FallbackReason = nil,
		LegacyValue = legacyValue,
		CanonicalValue = canonicalValue,
		CanonicalUnavailableReason = canonicalReason,
		LegacyIdentity = tostring(storageName or ""),
		Path = path,
		ItemId = tostring(storageName or ""),
		Player = player,
		Flags = flags,
		DiagnosticsEnabled = diagnosticsEnabled,
		CanonicalReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationStatus = validationStatus,
		ValidationValid = validationReason == nil,
		ValidationReason = validationReason,
		ValidationAge = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		ValidationAgeSeconds = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		BlockingCounts = counts,
		Match = match,
		ComparisonValid = diagnosticsEnabled
			and canonicalValue ~= nil
			and validationReason == nil,
		DisabledByMismatch = disabledByMismatch,
		IsAuthoritative = false,
		LogThrottleSeconds = options.LogThrottleSeconds,
	}
	result.FallbackReason = gameplayHelperResultFallbackReason(result)

	if result.FallbackReason == nil then
		result.Value = canonicalValue
		result.UsedCanonical = true
		recordCanonicalSelected(result, path, "gameplay_helper")
	else
		applyReadResultFallbackPolicy(
			result,
			"display_helper_legacy_fallback",
			path,
			"gameplay_helper"
		)
		result.Value = legacyValue
	end

	if options.SkipLog ~= true then
		logGameplayHelperResult(result)
	end

	return result.Value, result
end

local function evaluateStandStatusDisplayNameHelper(source, storageName, options)
	options = if typeof(options) == "table" then options else {}
	return evaluateGameplayDisplayNameHelper(
		source,
		storageName,
		CrewMemberCanonicalReadGate.Paths.GameplayHelperStandStatusDisplayName,
		buildCanonicalStandStatusDisplayName,
		options
	)
end

local function evaluateIncomeStatusDisplayNameHelper(source, storageName, options)
	options = if typeof(options) == "table" then options else {}
	return evaluateGameplayDisplayNameHelper(
		source,
		storageName,
		CrewMemberCanonicalReadGate.Paths.GameplayHelperIncomeStatusDisplayName,
		buildCanonicalIncomeStatusDisplayName,
		options
	)
end

local function evaluateIncomeToastDisplayNameHelper(source, storageName, options)
	options = if typeof(options) == "table" then options else {}
	return evaluateGameplayDisplayNameHelper(
		source,
		storageName,
		CrewMemberCanonicalReadGate.Paths.GameplayHelperIncomeToastDisplayName,
		buildCanonicalIncomeToastDisplayName,
		options
	)
end

local function evaluateFoodStatusDisplayNameHelper(source, storageName, options)
	options = if typeof(options) == "table" then options else {}
	return evaluateGameplayDisplayNameHelper(
		source,
		storageName,
		CrewMemberCanonicalReadGate.Paths.GameplayHelperFoodStatusDisplayName,
		buildCanonicalFoodStatusDisplayName,
		options
	)
end

local function readLegacyStandOccupant(root, standName)
	local income = if typeof(root) == "table" then root[CrewProfileSchema.LegacyKeys.Income] else nil
	if typeof(income) ~= "table" then
		return nil, "legacy_income_missing"
	end

	local standData = income[tostring(standName or "")]
	if typeof(standData) ~= "table" then
		return nil, "legacy_stand_missing"
	end

	local legacyIdentity = tostring(standData[CrewProfileSchema.LegacyKeys.StandName] or standData.CrewMemberName or "")
	local instanceId = tostring(
		standData[CrewProfileSchema.LegacyKeys.StandInstanceId] or standData.CrewMemberInstanceId or ""
	)
	return {
		StandName = tostring(standName or ""),
		LegacyIdentity = legacyIdentity,
		InstanceId = instanceId,
		Raw = standData,
	}, nil
end

local function getCanonicalStandLegacyIdentity(instanceData)
	if typeof(instanceData) ~= "table" then
		return ""
	end

	local legacyIdentity = tostring(instanceData.LegacyStorageName or instanceData.CrewMemberName or "")
	if legacyIdentity ~= "" then
		return legacyIdentity
	end
	return tostring(instanceData.StorageName or "")
end

local function getCanonicalStandDisplayName(instanceData)
	if typeof(instanceData) ~= "table" then
		return nil, "canonical_entry_missing"
	end

	local legacyIdentity = getCanonicalStandLegacyIdentity(instanceData)
	local metadata = normalizeDisplayMetadata(instanceData, legacyIdentity, "CrewMemberInventory")
	local displayName = getMetadataFieldValue(metadata, "DisplayName")
	if displayName ~= nil then
		return displayName, nil
	end

	local catalogMetadata = buildCanonicalCatalogMetadata(legacyIdentity)
	displayName = getMetadataFieldValue(catalogMetadata, "DisplayName")
	if displayName ~= nil then
		return displayName, nil
	end
	return nil, "canonical_display_metadata_missing"
end

local function findCanonicalStandOccupants(root, standName)
	local inventory = getCanonicalInventory(root)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return {}, "canonical_inventory_missing"
	end

	local normalizedStandName = tostring(standName or "")
	local matches = {}
	local seen = {}

	local function append(instanceId, instanceData)
		local id = tostring(instanceId or "")
		if id == "" or seen[id] == true or typeof(instanceData) ~= "table" then
			return
		end
		seen[id] = true
		if tostring(instanceData.AssignedStand or "") ~= normalizedStandName then
			return
		end

		local instanceDisplayName, displayReason = getCanonicalStandDisplayName(instanceData)
		matches[#matches + 1] = {
			InstanceId = tostring(instanceData.InstanceId or id),
			LegacyIdentity = getCanonicalStandLegacyIdentity(instanceData),
			StorageName = tostring(instanceData.StorageName or ""),
			CrewMemberId = tostring(instanceData.CrewMemberId or ""),
			DisplayName = instanceDisplayName,
			DisplayUnavailableReason = displayReason,
			Raw = instanceData,
		}
	end

	if typeof(inventory.Order) == "table" then
		for _, rawInstanceId in ipairs(inventory.Order) do
			local instanceId = tostring(rawInstanceId or "")
			append(instanceId, inventory.ById[instanceId])
		end
	end

	for rawInstanceId, instanceData in pairs(inventory.ById) do
		append(rawInstanceId, instanceData)
	end

	if #matches == 0 then
		return matches, "canonical_stand_assignment_missing"
	end
	return matches, nil
end

local function buildStandStatusReadAuthorityResult(
	standName,
	legacyOccupant,
	canonicalOccupant,
	source,
	fallbackReason,
	context
)
	context = if typeof(context) == "table" then context else {}
	local legacyIdentity = if legacyOccupant then tostring(legacyOccupant.LegacyIdentity or "") else ""
	local legacyInstanceId = if legacyOccupant then tostring(legacyOccupant.InstanceId or "") else ""
	local legacyMetadata = buildLegacyDisplayMetadata(legacyIdentity)
	local legacyDisplayName = getMetadataFieldValue(legacyMetadata, "DisplayName") or legacyIdentity
	local displayName = legacyDisplayName
	local canonicalDisplayName = if canonicalOccupant then canonicalOccupant.DisplayName else nil
	local canonicalInstanceId = if canonicalOccupant then tostring(canonicalOccupant.InstanceId or "") else ""
	local canonicalIdentity = if canonicalOccupant then tostring(canonicalOccupant.LegacyIdentity or "") else ""

	if source == "canonical" and canonicalDisplayName ~= nil then
		displayName = canonicalDisplayName
	end

	local result = {
		StandName = tostring(standName or ""),
		LegacyIdentity = legacyIdentity,
		InstanceId = if source == "canonical" then canonicalInstanceId else legacyInstanceId,
		DisplayName = displayName,
		Source = tostring(source or "legacy"),
		AuthorityMode = CrewMemberCanonicalReadGate.Paths.ReadAuthorityStandStatus,
		Path = CrewMemberCanonicalReadGate.Paths.ReadAuthorityStandStatus,
		UsedCanonical = source == "canonical",
		FallbackReason = fallbackReason,
		IsAuthoritativeRead = true,
		IsMutationAuthority = false,
		LegacyValue = legacyIdentity,
		CanonicalValue = canonicalDisplayName,
		LegacyDisplayName = legacyDisplayName,
		CanonicalDisplayName = canonicalDisplayName,
		CanonicalIdentity = canonicalIdentity,
		CanonicalInstanceId = canonicalInstanceId,
		LegacyInstanceId = legacyInstanceId,
		CanonicalEntryCount = tonumber(context.CanonicalEntryCount) or 0,
		CanonicalUnavailableReason = context.CanonicalUnavailableReason,
		CanonicalReadAllowed = context.CanonicalReadAllowed,
		ReadGateReason = context.ReadGateReason,
		ValidationStatus = context.ValidationStatus,
		ValidationValid = context.ValidationValid == true,
		ValidationReason = context.ValidationReason,
		ValidationAge = context.ValidationAgeSeconds,
		ValidationAgeSeconds = context.ValidationAgeSeconds,
		BlockingCounts = context.BlockingCounts,
		Player = context.Player,
		Flags = context.Flags,
		DiagnosticsEnabled = context.DiagnosticsEnabled == true,
		CompatibilityClassification = context.CompatibilityClassification,
		Match = context.Match == true,
		ComparisonValid = context.ComparisonValid == true,
		LogThrottleSeconds = context.LogThrottleSeconds,
	}

	return result
end

local function standStatusReadAuthorityFallbackReason(context)
	if context.ReadAllowed ~= true then
		return context.ReadGateReason or "read_authority_disabled"
	end
	if context.ValidationReason ~= nil then
		return context.ValidationReason
	end
	if context.LegacyIdentity == "" then
		return "legacy_fallback_missing"
	end
	if context.LegacyInstanceId == "" then
		return "legacy_instance_missing"
	end
	if context.CompatibilityClassification == "brook_fallback" then
		return "brook_fallback_stand_status_read_authority"
	end
	if context.CompatibilityClassification == "unknown_legacy_id" then
		return "unknown_legacy_stand_status_read_authority"
	end
	if context.CompatibilityClassification ~= "production_crew" then
		return "compatibility_only_stand_status_read_authority"
	end
	if context.CanonicalUnavailableReason ~= nil then
		return context.CanonicalUnavailableReason
	end
	if context.CanonicalEntryCount ~= 1 then
		return "duplicate_assigned_stand"
	end
	if context.CanonicalDisplayName == nil then
		return context.CanonicalDisplayUnavailableReason or "canonical_display_metadata_missing"
	end
	if context.IdentityMatch ~= true then
		return "canonical_legacy_identity_mismatch"
	end
	if context.InstanceMatch ~= true then
		return "canonical_legacy_instance_mismatch"
	end
	return nil
end

local function logStandStatusReadAuthorityResult(result)
	if result.DiagnosticsEnabled ~= true then
		return
	end

	local throttleSeconds = math.max(0, tonumber(result.LogThrottleSeconds) or DEFAULT_LOG_THROTTLE_SECONDS)
	local key = table.concat({
		getPlayerKey(result.Player),
		tostring(result.Path or ""),
		tostring(result.StandName or ""),
	}, "|")
	local counts = result.BlockingCounts or {}
	local signature = table.concat({
		tostring(result.Source),
		tostring(result.UsedCanonical),
		tostring(result.FallbackReason),
		tostring(result.Match),
		tostring(result.ValidationValid),
		tostring(result.LegacyIdentity),
		tostring(result.CanonicalIdentity),
		tostring(result.LegacyInstanceId),
		tostring(result.CanonicalInstanceId),
		tostring(counts.Total or 0),
		tostring(counts.Mismatch or 0),
		tostring(counts.Stand or 0),
		tostring(counts.Duplicate or 0),
		tostring(counts.Unknown or 0),
		tostring(counts.BlockingIncomeMismatch or 0),
	}, "|")
	local now = os.clock()
	local last = lastDiagnosticLogByKey[key]
	if typeof(last) == "table"
		and last.Signature == signature
		and throttleSeconds > 0
		and now - (tonumber(last.At) or 0) < throttleSeconds
	then
		return
	end
	lastDiagnosticLogByKey[key] = {
		At = now,
		Signature = signature,
	}

	local message = string.format(
		"%s read-authority stand-status player=%s stand=%s source=%s legacy=%s canonical=%s selectedDisplay=%s usedCanonical=%s fallback=%s authorityMode=%s mutationAuthority=%s validationAge=%.1fs blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(result.Player),
		tostring(result.StandName or ""),
		tostring(result.Source or ""),
		tostring(result.LegacyIdentity or ""),
		tostring(result.CanonicalIdentity or ""),
		tostring(result.DisplayName or ""),
		tostring(result.UsedCanonical == true),
		tostring(result.FallbackReason or "none"),
		tostring(result.AuthorityMode or ""),
		tostring(result.IsMutationAuthority == true),
		tonumber(result.ValidationAgeSeconds) or -1,
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	)

	if result.UsedCanonical == true then
		print(message)
	else
		warn(message)
	end
end

local function evaluateStandStatusReadAuthority(source, standName, options)
	options = if typeof(options) == "table" then options else {}
	local player = if typeof(options.Player) == "Instance" and options.Player:IsA("Player")
		then options.Player
		elseif typeof(source) == "Instance" and source:IsA("Player") then source
		else nil
	local root, rootReason = getRoot(source)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local diagnosticsEnabled = isDiagnosticsEnabled(flags)
	local path = CrewMemberCanonicalReadGate.Paths.ReadAuthorityStandStatus
	local readAllowed, readGateReason = isPathSpecificStandStatusReadAuthorityAllowed(flags, path)
	local validationStatus, validationReason = nil, "validation_missing"

	if root ~= nil then
		validationStatus, validationReason = getValidationStatus(root, player, {
			Flags = flags,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	else
		validationReason = rootReason or "invalid_source"
	end

	local legacyOccupant = nil
	local legacyReason = nil
	if root ~= nil then
		legacyOccupant, legacyReason = readLegacyStandOccupant(root, standName)
	else
		legacyReason = rootReason or "invalid_source"
	end

	local canonicalOccupants = {}
	local canonicalReason = "canonical_inventory_missing"
	if root ~= nil then
		canonicalOccupants, canonicalReason = findCanonicalStandOccupants(root, standName)
	end
	local canonicalOccupant = if #canonicalOccupants == 1 then canonicalOccupants[1] else nil
	local legacyIdentity = if legacyOccupant then tostring(legacyOccupant.LegacyIdentity or "") else ""
	local legacyInstanceId = if legacyOccupant then tostring(legacyOccupant.InstanceId or "") else ""
	local canonicalIdentity = if canonicalOccupant then tostring(canonicalOccupant.LegacyIdentity or "") else ""
	local canonicalInstanceId = if canonicalOccupant then tostring(canonicalOccupant.InstanceId or "") else ""
	local legacyMetadata = buildLegacyDisplayMetadata(legacyIdentity)
	local classification = tostring(legacyMetadata.CompatibilityClassification or "")
	local identityMatch = legacyIdentity ~= "" and canonicalIdentity ~= "" and legacyIdentity == canonicalIdentity
	local instanceMatch = legacyInstanceId ~= ""
		and canonicalInstanceId ~= ""
		and legacyInstanceId == canonicalInstanceId
	local counts = getBlockingCounts(validationStatus)
	local fallbackContext = {
		ReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationReason = validationReason,
		LegacyIdentity = legacyIdentity,
		LegacyInstanceId = legacyInstanceId,
		CompatibilityClassification = classification,
		CanonicalUnavailableReason = canonicalReason,
		CanonicalEntryCount = #canonicalOccupants,
		CanonicalDisplayName = if canonicalOccupant then canonicalOccupant.DisplayName else nil,
		CanonicalDisplayUnavailableReason = if canonicalOccupant
			then canonicalOccupant.DisplayUnavailableReason
			else nil,
		IdentityMatch = identityMatch,
		InstanceMatch = instanceMatch,
	}
	local fallbackReason = standStatusReadAuthorityFallbackReason(fallbackContext)
	if legacyOccupant == nil and legacyReason ~= nil and fallbackReason == nil then
		fallbackReason = legacyReason
	end

	local selectedSource = if fallbackReason == nil then "canonical" else "legacy"
	local context = {
		Player = player,
		Flags = flags,
		DiagnosticsEnabled = diagnosticsEnabled,
		CanonicalReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationStatus = validationStatus,
		ValidationValid = validationReason == nil,
		ValidationReason = validationReason,
		ValidationAgeSeconds = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		BlockingCounts = counts,
		CompatibilityClassification = classification,
		CanonicalEntryCount = #canonicalOccupants,
		CanonicalUnavailableReason = canonicalReason,
		Match = identityMatch and instanceMatch,
		ComparisonValid = diagnosticsEnabled
			and validationReason == nil
			and canonicalOccupant ~= nil,
		LogThrottleSeconds = options.LogThrottleSeconds,
	}
	local result = buildStandStatusReadAuthorityResult(
		standName,
		legacyOccupant,
		canonicalOccupant,
		selectedSource,
		fallbackReason,
		context
	)
	applyReadResultFallbackPolicy(
		result,
		"stand_income_legacy_fallback_read",
		path,
		"stand_status_read_authority"
	)

	if options.SkipLog ~= true then
		logStandStatusReadAuthorityResult(result)
	end

	return result, result
end

local function getCanonicalIncome(root)
	if typeof(root) ~= "table" then
		return nil
	end
	return root[CrewProfileSchema.Keys.Income]
end

local function readCanonicalIncomeRow(root, standName)
	local income = getCanonicalIncome(root)
	if typeof(income) ~= "table" then
		return nil, "canonical_income_missing"
	end

	local row = income[tostring(standName or "")]
	if typeof(row) ~= "table" then
		return nil, "canonical_income_row_missing"
	end
	return row, nil
end

local function getCanonicalIncomeLegacyIdentity(row)
	if typeof(row) ~= "table" then
		return ""
	end

	local legacyIdentity = tostring(row.LegacyStorageName or "")
	if legacyIdentity ~= "" then
		return legacyIdentity
	end

	local legacy = row.Legacy
	if typeof(legacy) == "table" then
		return tostring(legacy.CrewMemberName or "")
	end
	return ""
end

local function getCanonicalIncomeInstanceId(row)
	if typeof(row) ~= "table" then
		return ""
	end

	local instanceId = tostring(row.CrewMemberInstanceId or "")
	if instanceId ~= "" then
		return instanceId
	end

	local legacy = row.Legacy
	if typeof(legacy) == "table" then
		return tostring(legacy.CrewMemberInstanceId or "")
	end
	return ""
end

local function findCanonicalInventoryInstanceById(root, instanceId)
	local inventory = getCanonicalInventory(root)
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return nil, "canonical_inventory_missing"
	end

	local id = tostring(instanceId or "")
	if id == "" then
		return nil, "canonical_income_instance_missing"
	end

	local direct = inventory.ById[id]
	if typeof(direct) == "table" then
		return direct, nil
	end

	for _, instanceData in pairs(inventory.ById) do
		if typeof(instanceData) == "table" and tostring(instanceData.InstanceId or "") == id then
			return instanceData, nil
		end
	end

	return nil, "canonical_inventory_instance_missing"
end

local function getCanonicalIncomeDisplayName(incomeRow, inventoryInstance, legacyIdentity)
	if typeof(incomeRow) == "table" then
		local rowDisplayName = tostring(incomeRow.CrewMemberDisplayName or "")
		if rowDisplayName ~= "" then
			return rowDisplayName, nil
		end
	end

	local inventoryDisplayName, inventoryDisplayReason = getCanonicalStandDisplayName(inventoryInstance)
	if inventoryDisplayName ~= nil then
		return inventoryDisplayName, nil
	end

	local catalogMetadata = buildCanonicalCatalogMetadata(legacyIdentity)
	local catalogDisplayName = getMetadataFieldValue(catalogMetadata, "DisplayName")
	if catalogDisplayName ~= nil then
		return catalogDisplayName, inventoryDisplayReason
	end
	return nil, inventoryDisplayReason or "canonical_display_metadata_missing"
end

local function buildIncomeStatusReadAuthorityResult(
	standName,
	legacyOccupant,
	canonicalIncome,
	canonicalInventoryInstance,
	source,
	fallbackReason,
	context
)
	context = if typeof(context) == "table" then context else {}
	local legacyIdentity = if legacyOccupant then tostring(legacyOccupant.LegacyIdentity or "") else ""
	local legacyInstanceId = if legacyOccupant then tostring(legacyOccupant.InstanceId or "") else ""
	local legacyIncomeToCollect = if legacyOccupant and typeof(legacyOccupant.Raw) == "table"
		then tonumber(legacyOccupant.Raw.IncomeToCollect) or 0
		else 0
	local legacyMetadata = buildLegacyDisplayMetadata(legacyIdentity)
	local legacyDisplayName = getMetadataFieldValue(legacyMetadata, "DisplayName") or legacyIdentity
	local canonicalIncomeIdentity = getCanonicalIncomeLegacyIdentity(canonicalIncome)
	local canonicalIncomeInstanceId = getCanonicalIncomeInstanceId(canonicalIncome)
	local canonicalInventoryIdentity = getCanonicalStandLegacyIdentity(canonicalInventoryInstance)
	local canonicalInventoryInstanceId = if canonicalInventoryInstance
		then tostring(canonicalInventoryInstance.InstanceId or canonicalIncomeInstanceId)
		else ""
	local canonicalDisplayName = context.CanonicalDisplayName
	local displayName = legacyDisplayName

	if source == "canonical" and canonicalDisplayName ~= nil then
		displayName = canonicalDisplayName
	end

	return {
		StandName = tostring(standName or ""),
		LegacyIdentity = legacyIdentity,
		InstanceId = if source == "canonical" then canonicalIncomeInstanceId else legacyInstanceId,
		DisplayName = displayName,
		Source = tostring(source or "legacy"),
		AuthorityMode = CrewMemberCanonicalReadGate.Paths.ReadAuthorityIncomeStatus,
		Path = CrewMemberCanonicalReadGate.Paths.ReadAuthorityIncomeStatus,
		UsedCanonical = source == "canonical",
		FallbackReason = fallbackReason,
		IsAuthoritativeRead = true,
		IsMutationAuthority = false,
		LegacyValue = legacyIdentity,
		CanonicalValue = canonicalDisplayName,
		LegacyDisplayName = legacyDisplayName,
		CanonicalDisplayName = canonicalDisplayName,
		CanonicalIdentity = canonicalIncomeIdentity,
		CanonicalIncomeIdentity = canonicalIncomeIdentity,
		CanonicalInventoryIdentity = canonicalInventoryIdentity,
		CanonicalIncomeInstanceId = canonicalIncomeInstanceId,
		CanonicalInventoryInstanceId = canonicalInventoryInstanceId,
		CanonicalInstanceId = canonicalIncomeInstanceId,
		LegacyInstanceId = legacyInstanceId,
		LegacyIncomeToCollect = legacyIncomeToCollect,
		CanonicalIncomeToCollect = if typeof(canonicalIncome) == "table"
			then tonumber(canonicalIncome.IncomeToCollect) or 0
			else 0,
		CanonicalInventoryAssignedStand = if canonicalInventoryInstance
			then tostring(canonicalInventoryInstance.AssignedStand or "")
			else "",
		CanonicalEntryCount = tonumber(context.CanonicalEntryCount) or 0,
		CanonicalUnavailableReason = context.CanonicalUnavailableReason,
		CanonicalReadAllowed = context.CanonicalReadAllowed,
		ReadGateReason = context.ReadGateReason,
		ValidationStatus = context.ValidationStatus,
		ValidationValid = context.ValidationValid == true,
		ValidationReason = context.ValidationReason,
		ValidationAge = context.ValidationAgeSeconds,
		ValidationAgeSeconds = context.ValidationAgeSeconds,
		BlockingCounts = context.BlockingCounts,
		Player = context.Player,
		Flags = context.Flags,
		DiagnosticsEnabled = context.DiagnosticsEnabled == true,
		CompatibilityClassification = context.CompatibilityClassification,
		Match = context.Match == true,
		ComparisonValid = context.ComparisonValid == true,
		LogThrottleSeconds = context.LogThrottleSeconds,
	}
end

local function incomeStatusReadAuthorityFallbackReason(context)
	if context.ReadAllowed ~= true then
		return context.ReadGateReason or "read_authority_disabled"
	end
	if context.ValidationReason ~= nil then
		return context.ValidationReason
	end
	if context.LegacyIdentity == "" then
		return "legacy_fallback_missing"
	end
	if context.LegacyInstanceId == "" then
		return "legacy_instance_missing"
	end
	if context.CompatibilityClassification == "brook_fallback" then
		return "brook_fallback_income_status_read_authority"
	end
	if context.CompatibilityClassification == "unknown_legacy_id" then
		return "unknown_legacy_income_status_read_authority"
	end
	if context.CompatibilityClassification ~= "production_crew" then
		return "compatibility_only_income_status_read_authority"
	end
	if context.CanonicalIncomeUnavailableReason ~= nil then
		return context.CanonicalIncomeUnavailableReason
	end
	if context.CanonicalIncomeIdentity == "" then
		return "canonical_income_identity_missing"
	end
	if context.CanonicalIncomeInstanceId == "" then
		return "canonical_income_instance_missing"
	end
	if context.CanonicalInventoryUnavailableReason ~= nil then
		return context.CanonicalInventoryUnavailableReason
	end
	if context.CanonicalInventoryAssignedStand ~= context.StandName then
		return "canonical_inventory_stand_mismatch"
	end
	if context.CanonicalStandUnavailableReason ~= nil then
		return context.CanonicalStandUnavailableReason
	end
	if context.CanonicalEntryCount ~= 1 then
		return "duplicate_assigned_stand"
	end
	if context.CanonicalStandInstanceId ~= context.LegacyInstanceId then
		return "canonical_assigned_stand_instance_mismatch"
	end
	if context.CanonicalDisplayName == nil then
		return context.CanonicalDisplayUnavailableReason or "canonical_display_metadata_missing"
	end
	if context.IncomeIdentityMatch ~= true then
		return "canonical_income_legacy_identity_mismatch"
	end
	if context.InventoryIdentityMatch ~= true then
		return "canonical_inventory_legacy_identity_mismatch"
	end
	if context.IncomeInstanceMatch ~= true then
		return "canonical_income_legacy_instance_mismatch"
	end
	if context.InventoryInstanceMatch ~= true then
		return "canonical_inventory_legacy_instance_mismatch"
	end
	return nil
end

local function logIncomeStatusReadAuthorityResult(result)
	if result.DiagnosticsEnabled ~= true then
		return
	end

	local throttleSeconds = math.max(0, tonumber(result.LogThrottleSeconds) or DEFAULT_LOG_THROTTLE_SECONDS)
	local key = table.concat({
		getPlayerKey(result.Player),
		tostring(result.Path or ""),
		tostring(result.StandName or ""),
	}, "|")
	local counts = result.BlockingCounts or {}
	local signature = table.concat({
		tostring(result.Source),
		tostring(result.UsedCanonical),
		tostring(result.FallbackReason),
		tostring(result.Match),
		tostring(result.ValidationValid),
		tostring(result.LegacyIdentity),
		tostring(result.CanonicalIncomeIdentity),
		tostring(result.CanonicalInventoryIdentity),
		tostring(result.LegacyInstanceId),
		tostring(result.CanonicalIncomeInstanceId),
		tostring(result.CanonicalInventoryInstanceId),
		tostring(counts.Total or 0),
		tostring(counts.Mismatch or 0),
		tostring(counts.Stand or 0),
		tostring(counts.Duplicate or 0),
		tostring(counts.Unknown or 0),
		tostring(counts.BlockingIncomeMismatch or 0),
	}, "|")
	local now = os.clock()
	local last = lastDiagnosticLogByKey[key]
	if typeof(last) == "table"
		and last.Signature == signature
		and throttleSeconds > 0
		and now - (tonumber(last.At) or 0) < throttleSeconds
	then
		return
	end
	lastDiagnosticLogByKey[key] = {
		At = now,
		Signature = signature,
	}

	local message = string.format(
		"%s read-authority income-status player=%s stand=%s source=%s legacy=%s canonicalIncome=%s canonicalInventory=%s selectedDisplay=%s usedCanonical=%s fallback=%s authorityMode=%s mutationAuthority=%s legacyIncome=%s canonicalIncomeAmount=%s validationAge=%.1fs blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(result.Player),
		tostring(result.StandName or ""),
		tostring(result.Source or ""),
		tostring(result.LegacyIdentity or ""),
		tostring(result.CanonicalIncomeIdentity or ""),
		tostring(result.CanonicalInventoryIdentity or ""),
		tostring(result.DisplayName or ""),
		tostring(result.UsedCanonical == true),
		tostring(result.FallbackReason or "none"),
		tostring(result.AuthorityMode or ""),
		tostring(result.IsMutationAuthority == true),
		tostring(result.LegacyIncomeToCollect or 0),
		tostring(result.CanonicalIncomeToCollect or 0),
		tonumber(result.ValidationAgeSeconds) or -1,
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	)

	if result.UsedCanonical == true then
		print(message)
	else
		warn(message)
	end
end

local function evaluateIncomeStatusReadAuthority(source, standName, options)
	options = if typeof(options) == "table" then options else {}
	local player = if typeof(options.Player) == "Instance" and options.Player:IsA("Player")
		then options.Player
		elseif typeof(source) == "Instance" and source:IsA("Player") then source
		else nil
	local root, rootReason = getRoot(source)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local diagnosticsEnabled = isDiagnosticsEnabled(flags)
	local path = CrewMemberCanonicalReadGate.Paths.ReadAuthorityIncomeStatus
	local readAllowed, readGateReason = isPathSpecificIncomeStatusReadAuthorityAllowed(flags, path)
	local validationStatus, validationReason = nil, "validation_missing"

	if root ~= nil then
		validationStatus, validationReason = getValidationStatus(root, player, {
			Flags = flags,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	else
		validationReason = rootReason or "invalid_source"
	end

	local legacyOccupant = nil
	local legacyReason = nil
	if root ~= nil then
		legacyOccupant, legacyReason = readLegacyStandOccupant(root, standName)
	else
		legacyReason = rootReason or "invalid_source"
	end

	local canonicalIncome = nil
	local canonicalIncomeReason = nil
	if root ~= nil then
		canonicalIncome, canonicalIncomeReason = readCanonicalIncomeRow(root, standName)
	else
		canonicalIncomeReason = rootReason or "invalid_source"
	end

	local canonicalIncomeIdentity = getCanonicalIncomeLegacyIdentity(canonicalIncome)
	local canonicalIncomeInstanceId = getCanonicalIncomeInstanceId(canonicalIncome)
	local canonicalInventoryInstance = nil
	local canonicalInventoryReason = nil
	if root ~= nil then
		canonicalInventoryInstance, canonicalInventoryReason =
			findCanonicalInventoryInstanceById(root, canonicalIncomeInstanceId)
	else
		canonicalInventoryReason = rootReason or "invalid_source"
	end

	local canonicalOccupants = {}
	local canonicalStandReason = nil
	if root ~= nil then
		canonicalOccupants, canonicalStandReason = findCanonicalStandOccupants(root, standName)
	end

	local canonicalDisplayName, canonicalDisplayReason =
		getCanonicalIncomeDisplayName(canonicalIncome, canonicalInventoryInstance, canonicalIncomeIdentity)
	local legacyIdentity = if legacyOccupant then tostring(legacyOccupant.LegacyIdentity or "") else ""
	local legacyInstanceId = if legacyOccupant then tostring(legacyOccupant.InstanceId or "") else ""
	local canonicalInventoryIdentity = getCanonicalStandLegacyIdentity(canonicalInventoryInstance)
	local canonicalInventoryInstanceId = if canonicalInventoryInstance
		then tostring(canonicalInventoryInstance.InstanceId or canonicalIncomeInstanceId)
		else ""
	local canonicalInventoryAssignedStand = if canonicalInventoryInstance
		then tostring(canonicalInventoryInstance.AssignedStand or "")
		else ""
	local canonicalStandInstanceId = if #canonicalOccupants == 1 then tostring(canonicalOccupants[1].InstanceId or "") else ""
	local legacyMetadata = buildLegacyDisplayMetadata(legacyIdentity)
	local classification = tostring(legacyMetadata.CompatibilityClassification or "")
	local incomeIdentityMatch = legacyIdentity ~= ""
		and canonicalIncomeIdentity ~= ""
		and legacyIdentity == canonicalIncomeIdentity
	local inventoryIdentityMatch = legacyIdentity ~= ""
		and canonicalInventoryIdentity ~= ""
		and legacyIdentity == canonicalInventoryIdentity
	local incomeInstanceMatch = legacyInstanceId ~= ""
		and canonicalIncomeInstanceId ~= ""
		and legacyInstanceId == canonicalIncomeInstanceId
	local inventoryInstanceMatch = legacyInstanceId ~= ""
		and canonicalInventoryInstanceId ~= ""
		and legacyInstanceId == canonicalInventoryInstanceId
	local counts = getBlockingCounts(validationStatus)

	local fallbackContext = {
		ReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationReason = validationReason,
		LegacyIdentity = legacyIdentity,
		LegacyInstanceId = legacyInstanceId,
		CompatibilityClassification = classification,
		CanonicalIncomeUnavailableReason = canonicalIncomeReason,
		CanonicalIncomeIdentity = canonicalIncomeIdentity,
		CanonicalIncomeInstanceId = canonicalIncomeInstanceId,
		CanonicalInventoryUnavailableReason = canonicalInventoryReason,
		CanonicalInventoryAssignedStand = canonicalInventoryAssignedStand,
		CanonicalEntryCount = #canonicalOccupants,
		CanonicalStandUnavailableReason = canonicalStandReason,
		CanonicalStandInstanceId = canonicalStandInstanceId,
		CanonicalDisplayName = canonicalDisplayName,
		CanonicalDisplayUnavailableReason = canonicalDisplayReason,
		IncomeIdentityMatch = incomeIdentityMatch,
		InventoryIdentityMatch = inventoryIdentityMatch,
		IncomeInstanceMatch = incomeInstanceMatch,
		InventoryInstanceMatch = inventoryInstanceMatch,
		StandName = tostring(standName or ""),
	}
	local fallbackReason = incomeStatusReadAuthorityFallbackReason(fallbackContext)
	if legacyOccupant == nil and legacyReason ~= nil and fallbackReason == nil then
		fallbackReason = legacyReason
	end

	local selectedSource = if fallbackReason == nil then "canonical" else "legacy"
	local context = {
		Player = player,
		Flags = flags,
		DiagnosticsEnabled = diagnosticsEnabled,
		CanonicalReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationStatus = validationStatus,
		ValidationValid = validationReason == nil,
		ValidationReason = validationReason,
		ValidationAgeSeconds = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		BlockingCounts = counts,
		CompatibilityClassification = classification,
		CanonicalEntryCount = #canonicalOccupants,
		CanonicalUnavailableReason = canonicalIncomeReason or canonicalInventoryReason or canonicalStandReason,
		CanonicalDisplayName = canonicalDisplayName,
		Match = incomeIdentityMatch and inventoryIdentityMatch and incomeInstanceMatch and inventoryInstanceMatch,
		ComparisonValid = diagnosticsEnabled
			and validationReason == nil
			and canonicalIncome ~= nil
			and canonicalInventoryInstance ~= nil,
		LogThrottleSeconds = options.LogThrottleSeconds,
	}
	local result = buildIncomeStatusReadAuthorityResult(
		standName,
		legacyOccupant,
		canonicalIncome,
		canonicalInventoryInstance,
		selectedSource,
		fallbackReason,
		context
	)
	applyReadResultFallbackPolicy(
		result,
		"stand_income_legacy_fallback_read",
		path,
		"income_status_read_authority"
	)

	if options.SkipLog ~= true then
		logIncomeStatusReadAuthorityResult(result)
	end

	return result, result
end

local function floorOptionalNumber(value)
	local numberValue = tonumber(value)
	if numberValue == nil then
		return nil
	end
	return math.floor(numberValue)
end

local function readLegacyInventoryInstanceById(root, instanceId)
	local legacyInventory = if typeof(root) == "table" then root[CrewProfileSchema.LegacyKeys.Inventory] else nil
	if typeof(legacyInventory) ~= "table" then
		return nil, "legacy_inventory_missing"
	end

	local byId = legacyInventory.ById
	if typeof(byId) ~= "table" then
		return nil, "legacy_inventory_by_id_missing"
	end

	local id = tostring(instanceId or "")
	if id == "" then
		return nil, "legacy_instance_missing"
	end

	local direct = byId[id]
	if typeof(direct) == "table" then
		return direct, nil
	end

	for _, instanceData in pairs(byId) do
		if typeof(instanceData) == "table" and tostring(instanceData.InstanceId or "") == id then
			return instanceData, nil
		end
	end

	return nil, "legacy_inventory_instance_missing"
end

local function readLegacyStandLevel(_root, standName)
	local normalizedStandName = tostring(standName or "")
	if normalizedStandName == "" then
		return nil, nil
	end

	return nil, "legacy_stand_level_retired"
end

local function normalizeFoodStatusContext(target, options)
	local context = {}
	if typeof(target) == "table" then
		for key, value in pairs(target) do
			context[key] = value
		end
	elseif target ~= nil then
		if typeof(options) == "table" and tostring(options.StandName or "") ~= "" then
			context.StandName = tostring(options.StandName or "")
			context.LegacyIdentity = tostring(target or "")
		else
			context.LegacyIdentity = tostring(target or "")
		end
	end

	if typeof(options) == "table" then
		for _, key in ipairs({
			"StandName",
			"LegacyIdentity",
			"CrewMemberName",
			"InstanceId",
			"CrewMemberInstanceId",
			"Progress",
			"AppliedStep",
			"StorageName",
			"Level",
			"CurrentXP",
		}) do
			if options[key] ~= nil then
				context[key] = options[key]
			end
		end
	end

	return context
end

local function readLegacyFoodStatusRow(root, target, options)
	local context = normalizeFoodStatusContext(target, options)
	local standName = tostring(context.StandName or "")
	local progress = if typeof(context.Progress) == "table" then context.Progress else {}
	local legacyOccupant = nil
	local legacyStandReason = nil
	if standName ~= "" then
		legacyOccupant, legacyStandReason = readLegacyStandOccupant(root, standName)
	end

	local legacyIdentity = tostring(
		context.LegacyIdentity
			or context.CrewMemberName
			or (legacyOccupant and legacyOccupant.LegacyIdentity)
			or progress.StorageName
			or ""
	)
	local instanceId = tostring(
		context.InstanceId
			or context.CrewMemberInstanceId
			or progress.InstanceId
			or (legacyOccupant and legacyOccupant.InstanceId)
			or ""
	)

	local legacyInstance = nil
	local legacyInstanceReason = nil
	if root ~= nil and instanceId ~= "" then
		legacyInstance, legacyInstanceReason = readLegacyInventoryInstanceById(root, instanceId)
	elseif instanceId == "" then
		legacyInstanceReason = "legacy_instance_missing"
	end

	local storageName = tostring(
		context.StorageName
			or progress.StorageName
			or (legacyInstance and legacyInstance.StorageName)
			or legacyIdentity
			or ""
	)
	local level = floorOptionalNumber(context.Level)
		or floorOptionalNumber(progress.Level)
		or floorOptionalNumber(legacyInstance and legacyInstance.Level)
	local currentXP = floorOptionalNumber(context.CurrentXP)
		or floorOptionalNumber(progress.CurrentXP)
		or floorOptionalNumber(legacyInstance and legacyInstance.CurrentXP)
	local standLevel, standLevelReason = readLegacyStandLevel(root, standName)

	return {
		StandName = standName,
		LegacyIdentity = legacyIdentity,
		InstanceId = instanceId,
		StorageName = storageName,
		Level = if level ~= nil then math.max(1, level) else nil,
		CurrentXP = if currentXP ~= nil then math.max(0, currentXP) else nil,
		StandLevel = standLevel,
		StandLevelReason = standLevelReason,
		LegacyStandReason = legacyStandReason,
		LegacyInstanceReason = legacyInstanceReason,
		LegacyOccupant = legacyOccupant,
		LegacyInstance = legacyInstance,
		AppliedStep = if typeof(context.AppliedStep) == "table" then context.AppliedStep else nil,
		Raw = context,
	}, nil
end

local function getCanonicalFoodDisplayName(instanceData, legacyIdentity)
	local displayName, displayReason = getCanonicalStandDisplayName(instanceData)
	if displayName ~= nil then
		return displayName, nil
	end

	local catalogMetadata = buildCanonicalCatalogMetadata(legacyIdentity)
	local catalogDisplayName = getMetadataFieldValue(catalogMetadata, "DisplayName")
	if catalogDisplayName ~= nil then
		return catalogDisplayName, displayReason
	end
	return nil, displayReason or "canonical_display_metadata_missing"
end

local function buildFoodStatusReadAuthorityResult(
	legacyRow,
	canonicalInstance,
	source,
	fallbackReason,
	context
)
	context = if typeof(context) == "table" then context else {}
	local legacyIdentity = if legacyRow then tostring(legacyRow.LegacyIdentity or "") else ""
	local legacyInstanceId = if legacyRow then tostring(legacyRow.InstanceId or "") else ""
	local legacyStorageName = if legacyRow then tostring(legacyRow.StorageName or "") else ""
	local legacyLevel = if legacyRow then legacyRow.Level else nil
	local legacyCurrentXP = if legacyRow then legacyRow.CurrentXP else nil
	local legacyMetadata = buildLegacyDisplayMetadata(legacyIdentity)
	local legacyDisplayName = getMetadataFieldValue(legacyMetadata, "DisplayName") or legacyIdentity
	local canonicalIdentity = getCanonicalStandLegacyIdentity(canonicalInstance)
	local canonicalInstanceId = if canonicalInstance then tostring(canonicalInstance.InstanceId or legacyInstanceId) else ""
	local canonicalStorageName = if canonicalInstance then tostring(canonicalInstance.StorageName or "") else ""
	local canonicalLevel = if canonicalInstance then floorOptionalNumber(canonicalInstance.Level) else nil
	local canonicalCurrentXP = if canonicalInstance then floorOptionalNumber(canonicalInstance.CurrentXP) else nil
	local canonicalDisplayName = context.CanonicalDisplayName
	local displayName = legacyDisplayName

	if source == "canonical" and canonicalDisplayName ~= nil then
		displayName = canonicalDisplayName
	end

	return {
		StandName = if legacyRow then tostring(legacyRow.StandName or "") else "",
		LegacyIdentity = legacyIdentity,
		InstanceId = legacyInstanceId,
		DisplayName = displayName,
		Level = legacyLevel,
		CurrentXP = legacyCurrentXP,
		Source = tostring(source or "legacy"),
		AuthorityMode = CrewMemberCanonicalReadGate.Paths.ReadAuthorityFoodStatus,
		Path = CrewMemberCanonicalReadGate.Paths.ReadAuthorityFoodStatus,
		UsedCanonical = source == "canonical",
		FallbackReason = fallbackReason,
		IsAuthoritativeRead = true,
		IsMutationAuthority = false,
		LegacyValue = legacyIdentity,
		CanonicalValue = canonicalDisplayName,
		LegacyDisplayName = legacyDisplayName,
		CanonicalDisplayName = canonicalDisplayName,
		LegacyStorageName = legacyStorageName,
		CanonicalIdentity = canonicalIdentity,
		CanonicalStorageName = canonicalStorageName,
		CanonicalInstanceId = canonicalInstanceId,
		LegacyInstanceId = legacyInstanceId,
		CanonicalAssignedStand = if canonicalInstance then tostring(canonicalInstance.AssignedStand or "") else "",
		CanonicalLevel = canonicalLevel,
		CanonicalCurrentXP = canonicalCurrentXP,
		StandLevel = if legacyRow then legacyRow.StandLevel else nil,
		AppliedFoodKey = context.AppliedFoodKey,
		AppliedFoodAmountUsed = context.AppliedFoodAmountUsed,
		AppliedFoodXPGained = context.AppliedFoodXPGained,
		CanonicalEntryCount = tonumber(context.CanonicalEntryCount) or 0,
		CanonicalUnavailableReason = context.CanonicalUnavailableReason,
		CanonicalReadAllowed = context.CanonicalReadAllowed,
		ReadGateReason = context.ReadGateReason,
		ValidationStatus = context.ValidationStatus,
		ValidationValid = context.ValidationValid == true,
		ValidationReason = context.ValidationReason,
		ValidationAge = context.ValidationAgeSeconds,
		ValidationAgeSeconds = context.ValidationAgeSeconds,
		BlockingCounts = context.BlockingCounts,
		Player = context.Player,
		Flags = context.Flags,
		DiagnosticsEnabled = context.DiagnosticsEnabled == true,
		CompatibilityClassification = context.CompatibilityClassification,
		Match = context.Match == true,
		ComparisonValid = context.ComparisonValid == true,
		LogThrottleSeconds = context.LogThrottleSeconds,
	}
end

local function foodStatusReadAuthorityFallbackReason(context)
	if context.ReadAllowed ~= true then
		return context.ReadGateReason or "read_authority_disabled"
	end
	if context.ValidationReason ~= nil then
		return context.ValidationReason
	end
	if context.LegacyIdentity == "" then
		return "legacy_fallback_missing"
	end
	if context.LegacyInstanceId == "" then
		return "legacy_instance_missing"
	end
	if context.LegacyProgressAvailable ~= true then
		return context.LegacyProgressReason or "legacy_progress_missing"
	end
	if context.StandLevelReason ~= nil then
		return context.StandLevelReason
	end
	if context.StandLevelMatch == false then
		return "legacy_stand_level_mismatch"
	end
	if context.CompatibilityClassification == "brook_fallback" then
		return "brook_fallback_food_status_read_authority"
	end
	if context.CompatibilityClassification == "unknown_legacy_id" then
		return "unknown_legacy_food_status_read_authority"
	end
	if context.CompatibilityClassification ~= "production_crew" then
		return "compatibility_only_food_status_read_authority"
	end
	if context.CanonicalInventoryUnavailableReason ~= nil then
		return context.CanonicalInventoryUnavailableReason
	end
	if context.CanonicalIdentity == "" then
		return "canonical_inventory_identity_missing"
	end
	if context.CanonicalInstanceId == "" then
		return "canonical_inventory_instance_missing"
	end
	if context.StandName ~= "" and context.CanonicalAssignedStand ~= context.StandName then
		return "canonical_assigned_stand_mismatch"
	end
	if context.CanonicalStandUnavailableReason ~= nil then
		return context.CanonicalStandUnavailableReason
	end
	if context.StandName ~= "" and context.CanonicalEntryCount ~= 1 then
		return "duplicate_assigned_stand"
	end
	if context.CanonicalDisplayName == nil then
		return context.CanonicalDisplayUnavailableReason or "canonical_display_metadata_missing"
	end
	if context.IdentityMatch ~= true then
		return "canonical_legacy_identity_mismatch"
	end
	if context.InstanceMatch ~= true then
		return "canonical_legacy_instance_mismatch"
	end
	if context.StorageMatch ~= true then
		return "canonical_legacy_storage_mismatch"
	end
	if context.LevelMatch ~= true then
		return "canonical_legacy_level_mismatch"
	end
	if context.XPMatch ~= true then
		return "canonical_legacy_xp_mismatch"
	end
	return nil
end

local function logFoodStatusReadAuthorityResult(result)
	if result.DiagnosticsEnabled ~= true then
		return
	end

	local throttleSeconds = math.max(0, tonumber(result.LogThrottleSeconds) or DEFAULT_LOG_THROTTLE_SECONDS)
	local key = table.concat({
		getPlayerKey(result.Player),
		tostring(result.Path or ""),
		tostring(result.StandName or ""),
		tostring(result.LegacyIdentity or ""),
		tostring(result.LegacyInstanceId or ""),
	}, "|")
	local counts = result.BlockingCounts or {}
	local signature = table.concat({
		tostring(result.Source),
		tostring(result.UsedCanonical),
		tostring(result.FallbackReason),
		tostring(result.Match),
		tostring(result.ValidationValid),
		tostring(result.LegacyIdentity),
		tostring(result.CanonicalIdentity),
		tostring(result.LegacyInstanceId),
		tostring(result.CanonicalInstanceId),
		tostring(result.Level),
		tostring(result.CurrentXP),
		tostring(result.CanonicalLevel),
		tostring(result.CanonicalCurrentXP),
		tostring(counts.Total or 0),
		tostring(counts.Mismatch or 0),
		tostring(counts.Stand or 0),
		tostring(counts.Duplicate or 0),
		tostring(counts.Unknown or 0),
		tostring(counts.BlockingIncomeMismatch or 0),
	}, "|")
	local now = os.clock()
	local last = lastDiagnosticLogByKey[key]
	if typeof(last) == "table"
		and last.Signature == signature
		and throttleSeconds > 0
		and now - (tonumber(last.At) or 0) < throttleSeconds
	then
		return
	end
	lastDiagnosticLogByKey[key] = {
		At = now,
		Signature = signature,
	}

	local message = string.format(
		"%s read-authority food-status player=%s stand=%s source=%s legacy=%s legacyInstance=%s canonical=%s canonicalInstance=%s selectedDisplay=%s usedCanonical=%s fallback=%s authorityMode=%s mutationAuthority=%s level=%s/%s xp=%s/%s standLevel=%s appliedFood=%s amount=%s gainedXP=%s validationAge=%.1fs blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(result.Player),
		tostring(result.StandName or ""),
		tostring(result.Source or ""),
		tostring(result.LegacyIdentity or ""),
		tostring(result.LegacyInstanceId or ""),
		tostring(result.CanonicalIdentity or ""),
		tostring(result.CanonicalInstanceId or ""),
		tostring(result.DisplayName or ""),
		tostring(result.UsedCanonical == true),
		tostring(result.FallbackReason or "none"),
		tostring(result.AuthorityMode or ""),
		tostring(result.IsMutationAuthority == true),
		tostring(result.Level or ""),
		tostring(result.CanonicalLevel or ""),
		tostring(result.CurrentXP or ""),
		tostring(result.CanonicalCurrentXP or ""),
		tostring(result.StandLevel or ""),
		tostring(result.AppliedFoodKey or ""),
		tostring(result.AppliedFoodAmountUsed or ""),
		tostring(result.AppliedFoodXPGained or ""),
		tonumber(result.ValidationAgeSeconds) or -1,
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	)

	if result.UsedCanonical == true then
		print(message)
	else
		warn(message)
	end
end

local function evaluateFoodStatusReadAuthority(source, target, options)
	options = if typeof(options) == "table" then options else {}
	local player = if typeof(options.Player) == "Instance" and options.Player:IsA("Player")
		then options.Player
		elseif typeof(source) == "Instance" and source:IsA("Player") then source
		else nil
	local root, rootReason = getRoot(source)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local diagnosticsEnabled = isDiagnosticsEnabled(flags)
	local path = CrewMemberCanonicalReadGate.Paths.ReadAuthorityFoodStatus
	local readAllowed, readGateReason = isPathSpecificFoodStatusReadAuthorityAllowed(flags, path)
	local validationStatus, validationReason = nil, "validation_missing"

	if root ~= nil then
		validationStatus, validationReason = getValidationStatus(root, player, {
			Flags = flags,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	else
		validationReason = rootReason or "invalid_source"
	end

	local legacyRow = nil
	local legacyReason = nil
	if root ~= nil then
		legacyRow, legacyReason = readLegacyFoodStatusRow(root, target, options)
	else
		legacyReason = rootReason or "invalid_source"
	end

	local legacyIdentity = if legacyRow then tostring(legacyRow.LegacyIdentity or "") else ""
	local legacyInstanceId = if legacyRow then tostring(legacyRow.InstanceId or "") else ""
	local legacyStorageName = if legacyRow then tostring(legacyRow.StorageName or "") else ""
	local legacyLevel = if legacyRow then legacyRow.Level else nil
	local legacyCurrentXP = if legacyRow then legacyRow.CurrentXP else nil
	local standName = if legacyRow then tostring(legacyRow.StandName or "") else ""
	local legacyMetadata = buildLegacyDisplayMetadata(legacyIdentity)
	local classification = tostring(legacyMetadata.CompatibilityClassification or "")
	local canonicalInstance = nil
	local canonicalInventoryReason = nil
	if root ~= nil then
		canonicalInstance, canonicalInventoryReason = findCanonicalInventoryInstanceById(root, legacyInstanceId)
	else
		canonicalInventoryReason = rootReason or "invalid_source"
	end

	local canonicalOccupants = {}
	local canonicalStandReason = nil
	if root ~= nil and standName ~= "" then
		canonicalOccupants, canonicalStandReason = findCanonicalStandOccupants(root, standName)
	end

	local canonicalIdentity = getCanonicalStandLegacyIdentity(canonicalInstance)
	local canonicalInstanceId = if canonicalInstance then tostring(canonicalInstance.InstanceId or legacyInstanceId) else ""
	local canonicalStorageName = if canonicalInstance then tostring(canonicalInstance.StorageName or "") else ""
	local canonicalAssignedStand = if canonicalInstance then tostring(canonicalInstance.AssignedStand or "") else ""
	local canonicalLevel = if canonicalInstance then floorOptionalNumber(canonicalInstance.Level) else nil
	local canonicalCurrentXP = if canonicalInstance then floorOptionalNumber(canonicalInstance.CurrentXP) else nil
	local canonicalDisplayName, canonicalDisplayReason = getCanonicalFoodDisplayName(canonicalInstance, legacyIdentity)
	local identityMatch = legacyIdentity ~= "" and canonicalIdentity ~= "" and legacyIdentity == canonicalIdentity
	local instanceMatch = legacyInstanceId ~= "" and canonicalInstanceId ~= "" and legacyInstanceId == canonicalInstanceId
	local storageMatch = legacyStorageName ~= ""
		and (
			legacyStorageName == canonicalIdentity
			or (canonicalStorageName ~= "" and legacyStorageName == canonicalStorageName)
		)
	local levelMatch = legacyLevel ~= nil and canonicalLevel ~= nil and legacyLevel == canonicalLevel
	local xpMatch = legacyCurrentXP ~= nil and canonicalCurrentXP ~= nil and legacyCurrentXP == canonicalCurrentXP
	local standLevelMatch = nil
	if standName ~= "" and legacyRow and legacyRow.StandLevel ~= nil and legacyLevel ~= nil then
		standLevelMatch = legacyRow.StandLevel == legacyLevel
	end
	local appliedStep = legacyRow and legacyRow.AppliedStep
	local counts = getBlockingCounts(validationStatus)

	local fallbackContext = {
		ReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationReason = validationReason,
		LegacyIdentity = legacyIdentity,
		LegacyInstanceId = legacyInstanceId,
		LegacyProgressAvailable = legacyLevel ~= nil and legacyCurrentXP ~= nil,
		LegacyProgressReason = legacyRow and legacyRow.LegacyInstanceReason,
		StandLevelReason = legacyRow and legacyRow.StandLevelReason,
		StandLevelMatch = standLevelMatch,
		CompatibilityClassification = classification,
		CanonicalInventoryUnavailableReason = canonicalInventoryReason,
		CanonicalIdentity = canonicalIdentity,
		CanonicalInstanceId = canonicalInstanceId,
		CanonicalAssignedStand = canonicalAssignedStand,
		CanonicalStandUnavailableReason = canonicalStandReason,
		CanonicalEntryCount = #canonicalOccupants,
		CanonicalDisplayName = canonicalDisplayName,
		CanonicalDisplayUnavailableReason = canonicalDisplayReason,
		IdentityMatch = identityMatch,
		InstanceMatch = instanceMatch,
		StorageMatch = storageMatch,
		LevelMatch = levelMatch,
		XPMatch = xpMatch,
		StandName = standName,
	}
	local fallbackReason = foodStatusReadAuthorityFallbackReason(fallbackContext)
	if legacyRow == nil and legacyReason ~= nil and fallbackReason == nil then
		fallbackReason = legacyReason
	end

	local selectedSource = if fallbackReason == nil then "canonical" else "legacy"
	local context = {
		Player = player,
		Flags = flags,
		DiagnosticsEnabled = diagnosticsEnabled,
		CanonicalReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationStatus = validationStatus,
		ValidationValid = validationReason == nil,
		ValidationReason = validationReason,
		ValidationAgeSeconds = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		BlockingCounts = counts,
		CompatibilityClassification = classification,
		CanonicalEntryCount = #canonicalOccupants,
		CanonicalUnavailableReason = canonicalInventoryReason or canonicalStandReason,
		CanonicalDisplayName = canonicalDisplayName,
		AppliedFoodKey = if typeof(appliedStep) == "table" then tostring(appliedStep.FoodKey or "") else nil,
		AppliedFoodAmountUsed = if typeof(appliedStep) == "table" then tonumber(appliedStep.AmountUsed) or 0 else nil,
		AppliedFoodXPGained = if typeof(appliedStep) == "table" then tonumber(appliedStep.XPGained) or 0 else nil,
		Match = identityMatch and instanceMatch and storageMatch and levelMatch and xpMatch and standLevelMatch ~= false,
		ComparisonValid = diagnosticsEnabled
			and validationReason == nil
			and canonicalInstance ~= nil,
		LogThrottleSeconds = options.LogThrottleSeconds,
	}
	local result = buildFoodStatusReadAuthorityResult(
		legacyRow,
		canonicalInstance,
		selectedSource,
		fallbackReason,
		context
	)
	applyReadResultFallbackPolicy(
		result,
		"food_progression_legacy_fallback_read",
		path,
		"food_status_read_authority"
	)

	if options.SkipLog ~= true then
		logFoodStatusReadAuthorityResult(result)
	end

	return result, result
end

local function logDiagnostic(result)
	if result.DiagnosticsEnabled ~= true then
		return
	end

	local throttleSeconds = math.max(0, tonumber(result.LogThrottleSeconds) or DEFAULT_LOG_THROTTLE_SECONDS)
	local key = table.concat({
		getPlayerKey(result.Player),
		tostring(result.Path or ""),
		tostring(result.ItemId or ""),
	}, "|")
	local counts = result.BlockingCounts or {}
	local signature = table.concat({
		tostring(result.Match),
		tostring(result.ComparisonValid),
		tostring(result.FallbackReason),
		tostring(result.ReadGateReason),
		tostring(counts.Total or 0),
		tostring(counts.Mismatch or 0),
		tostring(counts.Stand or 0),
		tostring(counts.Duplicate or 0),
		tostring(counts.Unknown or 0),
		tostring(counts.BlockingIncomeMismatch or 0),
		tostring(result.DisplayReadUseCanonical),
		tostring(result.DisplayReadFallbackReason),
		tostring(result.SelectedDisplayName),
		metadataToText(result.LegacyValue),
		metadataToText(result.CanonicalValue),
	}, "|")
	local now = os.clock()
	local last = lastDiagnosticLogByKey[key]
	if typeof(last) == "table"
		and last.Signature == signature
		and throttleSeconds > 0
		and now - (tonumber(last.At) or 0) < throttleSeconds
	then
		return
	end
	lastDiagnosticLogByKey[key] = {
		At = now,
		Signature = signature,
	}

	local message = string.format(
		"%s player=%s path=%s item=%s match=%s comparisonValid=%s legacy=%s canonical=%s fallback=%s readGate=%s displayReadCanonical=%s selectedDisplay=%s validationAge=%.1fs blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(result.Player),
		tostring(result.Path or ""),
		tostring(result.ItemId or ""),
		tostring(result.Match),
		tostring(result.ComparisonValid),
		metadataToText(result.LegacyValue),
		metadataToText(result.CanonicalValue),
		tostring(result.DisplayReadFallbackReason or result.FallbackReason or ""),
		tostring(result.ReadGateReason or "ok"),
		tostring(result.DisplayReadUseCanonical == true),
		tostring(result.SelectedDisplayName or ""),
		tonumber(result.ValidationAgeSeconds) or -1,
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	)

	if result.Match == true and result.ComparisonValid == true then
		print(message)
	else
		warn(message)
	end
end

function CrewMemberCanonicalReadGate.GetFlags(overrides)
	return CrewStorage.GetShadowFlags(overrides)
end

function CrewMemberCanonicalReadGate.SetMetadataHelperReadSessionOverride(enabled)
	return CrewStorage.SetMetadataHelperReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetStandStatusHelperReadSessionOverride(enabled)
	return CrewStorage.SetStandStatusHelperReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetIncomeStatusHelperReadSessionOverride(enabled)
	return CrewStorage.SetIncomeStatusHelperReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetStandIncomeStatusHelperReadSessionOverride(enabled)
	return CrewStorage.SetStandIncomeStatusHelperReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetIncomeToastHelperReadSessionOverride(enabled)
	return CrewStorage.SetIncomeToastHelperReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetFoodStatusHelperReadSessionOverride(enabled)
	return CrewStorage.SetFoodStatusHelperReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetAllGameplayHelperReadSessionOverride(enabled)
	return CrewStorage.SetAllGameplayHelperReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetStandStatusReadAuthoritySessionOverride(enabled)
	return CrewStorage.SetStandStatusReadAuthoritySessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetIncomeStatusReadAuthoritySessionOverride(enabled)
	return CrewStorage.SetIncomeStatusReadAuthoritySessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetFoodStatusReadAuthoritySessionOverride(enabled)
	return CrewStorage.SetFoodStatusReadAuthoritySessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetCombinedReadAuthoritySessionOverride(enabled)
	return CrewStorage.SetCombinedReadAuthoritySessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetProfileMigrationDryRunSessionOverride(enabled)
	return CrewStorage.SetProfileMigrationDryRunSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetProfileMigrationWriteSampledSessionOverride(enabled)
	return CrewStorage.SetProfileMigrationWriteSampledSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetQuickSlotsWriteAuthoritySessionOverride(enabled)
	return CrewStorage.SetQuickSlotsWriteAuthoritySessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetProductQuickSlotWriteAuthoritySessionOverride(enabled)
	return CrewStorage.SetProductQuickSlotWriteAuthoritySessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetInventoryWriteAuthoritySessionOverride(enabled)
	return CrewStorage.SetInventoryWriteAuthoritySessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetAdminModelPreviewReadSessionOverride(enabled)
	return CrewStorage.SetAdminModelPreviewReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetIndexModelPreviewReadSessionOverride(enabled)
	return CrewStorage.SetIndexModelPreviewReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.SetInventoryModelPreviewReadSessionOverride(enabled)
	return CrewStorage.SetInventoryModelPreviewReadSessionOverride(enabled == true)
end

function CrewMemberCanonicalReadGate.GetSessionShadowFlagOverrides()
	return CrewStorage.GetSessionShadowFlagOverrides()
end

function CrewMemberCanonicalReadGate.EvaluateDiagnosticComparison(source, path, legacyValue, canonicalValue, options)
	options = if typeof(options) == "table" then options else {}
	local player = if typeof(options.Player) == "Instance" and options.Player:IsA("Player")
		then options.Player
		elseif typeof(source) == "Instance" and source:IsA("Player") then source
		else nil
	local root, rootReason = getRoot(source)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local diagnosticsEnabled = isDiagnosticsEnabled(flags)
	local readAllowed, readGateReason = isCanonicalReadAllowedForPath(flags, path)
	local validationStatus, validationReason = nil, "validation_missing"

	if root ~= nil then
		validationStatus, validationReason = getValidationStatus(root, player, {
			Flags = flags,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	else
		validationReason = rootReason or "invalid_source"
	end

	local canonicalAvailable = typeof(canonicalValue) == "table"
	local match = canonicalAvailable and metadataMatches(legacyValue, canonicalValue)
	local disabledByMismatch = isDisabledForPlayer(player, path)
	if match ~= true and flags.CrewMemberCanonicalReadDisableOnMismatch == true then
		disableForPlayer(player, path)
		disabledByMismatch = true
	end

	local counts = getBlockingCounts(validationStatus)
	local result = {
		Player = player,
		Path = tostring(path or ""),
		ItemId = tostring(options.ItemId or ""),
		Flags = flags,
		DiagnosticsEnabled = diagnosticsEnabled,
		CanonicalReadAllowed = readAllowed,
		ReadGateReason = readGateReason,
		ValidationStatus = validationStatus,
		ValidationValid = validationReason == nil,
		ValidationReason = validationReason,
		ValidationAgeSeconds = if validationStatus then validationStatus.ValidationAgeSeconds else -1,
		BlockingCounts = counts,
		LegacyValue = legacyValue,
		CanonicalValue = canonicalValue,
		CanonicalAvailable = canonicalAvailable,
		CanonicalUnavailableReason = options.CanonicalUnavailableReason,
		CanonicalProjectionReason = options.CanonicalProjectionReason,
		Match = match,
		ComparisonValid = diagnosticsEnabled
			and canonicalAvailable
			and validationReason == nil,
		DisabledByMismatch = disabledByMismatch,
		UseCanonical = false,
		SelectedValue = legacyValue,
		LogThrottleSeconds = options.LogThrottleSeconds,
	}
	result.FallbackReason = makeFallbackReason(result)

	if options.SkipLog ~= true then
		logDiagnostic(result)
	end

	return result
end

function CrewMemberCanonicalReadGate.CompareInventoryDisplay(player, storageName, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	local root = getRoot(player)
	local legacyValue = buildLegacyDisplayMetadata(storageName)
	local canonicalValue, projectionReason = buildCanonicalInventoryMetadata(root, storageName, false)
	options.Player = player
	options.ItemId = tostring(storageName or "")
	options.CanonicalUnavailableReason = if canonicalValue then nil else projectionReason
	options.CanonicalProjectionReason = projectionReason
	return CrewMemberCanonicalReadGate.EvaluateDiagnosticComparison(
		player,
		CrewMemberCanonicalReadGate.Paths.InventoryDisplay,
		legacyValue,
		canonicalValue,
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveInventoryDisplayMetadata(player, storageName, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	options.SkipLog = true
	local result = CrewMemberCanonicalReadGate.CompareInventoryDisplay(player, storageName, options)
	local metadata = chooseCanonicalDisplayMetadata(result)

	if options.SkipSelectionLog ~= true then
		logDiagnostic(result)
	end

	return metadata, result
end

function CrewMemberCanonicalReadGate.CompareIndexDisplay(player, storageName, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	local root = getRoot(player)
	local legacyValue = buildLegacyDisplayMetadata(storageName)
	local canonicalValue, projectionReason = buildCanonicalIndexMetadata(root, storageName)
	options.Player = player
	options.ItemId = tostring(storageName or "")
	options.CanonicalUnavailableReason = if canonicalValue then nil else projectionReason
	options.CanonicalProjectionReason = projectionReason
	return CrewMemberCanonicalReadGate.EvaluateDiagnosticComparison(
		player,
		CrewMemberCanonicalReadGate.Paths.IndexDisplay,
		legacyValue,
		canonicalValue,
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveIndexDisplayMetadata(player, storageName, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	options.SkipLog = true
	local result = CrewMemberCanonicalReadGate.CompareIndexDisplay(player, storageName, options)
	local metadata = chooseCanonicalDisplayMetadata(result)

	if options.SkipSelectionLog ~= true then
		logDiagnostic(result)
	end

	return metadata, result
end

function CrewMemberCanonicalReadGate.CompareSellDialogDisplay(player, storageName, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	local root = getRoot(player)
	local legacyValue = buildLegacyDisplayMetadata(storageName)
	local canonicalValue, projectionReason = buildCanonicalInventoryMetadata(root, storageName, false)
	options.Player = player
	options.ItemId = tostring(storageName or "")
	options.CanonicalUnavailableReason = if canonicalValue then nil else projectionReason
	options.CanonicalProjectionReason = projectionReason
	return CrewMemberCanonicalReadGate.EvaluateDiagnosticComparison(
		player,
		CrewMemberCanonicalReadGate.Paths.SellDialogDisplay,
		legacyValue,
		canonicalValue,
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveSellDialogDisplayName(player, storageName, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	options.SkipLog = true
	local result = CrewMemberCanonicalReadGate.CompareSellDialogDisplay(player, storageName, options)
	local displayName = chooseCanonicalDisplayName(result)

	if options.SkipSelectionLog ~= true then
		logDiagnostic(result)
	end

	return displayName, result
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelper(source, storageName, helperName, options)
	local helperKey = tostring(helperName or "")
	local path
	if helperKey == "display_name" or helperKey == "DisplayName" then
		path = CrewMemberCanonicalReadGate.Paths.MetadataHelperDisplayName
	elseif helperKey == "rarity" or helperKey == "Rarity" then
		path = CrewMemberCanonicalReadGate.Paths.MetadataHelperRarity
	elseif helperKey == "render_icon" or helperKey == "render" or helperKey == "Render" then
		path = CrewMemberCanonicalReadGate.Paths.MetadataHelperRenderIcon
	elseif helperKey == "real_character_name" or helperKey == "RealCharacterName" then
		path = CrewMemberCanonicalReadGate.Paths.MetadataHelperRealCharacterName
	elseif helperKey == "arc" or helperKey == "Arc" then
		path = CrewMemberCanonicalReadGate.Paths.MetadataHelperArc
	elseif helperKey == "compatibility_classification" or helperKey == "CompatibilityClassification" then
		path = CrewMemberCanonicalReadGate.Paths.MetadataHelperCompatibilityClassification
	else
		path = helperKey
	end

	local fieldName = METADATA_HELPER_PATHS[path]
	if fieldName == nil then
		local result = {
			Value = nil,
			UsedCanonical = false,
			FallbackReason = "metadata_helper_path_disabled",
			LegacyValue = nil,
			CanonicalValue = nil,
			Path = tostring(path or ""),
			ItemId = tostring(storageName or ""),
			Identity = tostring(storageName or ""),
			ValidationAge = -1,
			ValidationAgeSeconds = -1,
		}
		return nil, result
	end

	return evaluateMetadataHelperRead(source, path, storageName, fieldName, options)
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelperDisplayName(source, storageName, options)
	return evaluateMetadataHelperRead(
		source,
		CrewMemberCanonicalReadGate.Paths.MetadataHelperDisplayName,
		storageName,
		"DisplayName",
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelperRarity(source, storageName, options)
	return evaluateMetadataHelperRead(
		source,
		CrewMemberCanonicalReadGate.Paths.MetadataHelperRarity,
		storageName,
		"Rarity",
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelperRenderIcon(source, storageName, options)
	return evaluateMetadataHelperRead(
		source,
		CrewMemberCanonicalReadGate.Paths.MetadataHelperRenderIcon,
		storageName,
		"Render",
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelperRealCharacterName(source, storageName, options)
	return evaluateMetadataHelperRead(
		source,
		CrewMemberCanonicalReadGate.Paths.MetadataHelperRealCharacterName,
		storageName,
		"RealCharacterName",
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelperArc(source, storageName, options)
	return evaluateMetadataHelperRead(
		source,
		CrewMemberCanonicalReadGate.Paths.MetadataHelperArc,
		storageName,
		"Arc",
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelperCompatibilityClassification(source, storageName, options)
	return evaluateMetadataHelperRead(
		source,
		CrewMemberCanonicalReadGate.Paths.MetadataHelperCompatibilityClassification,
		storageName,
		"CompatibilityClassification",
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveMetadataHelperSet(source, storageName, options)
	local helperOptions = if typeof(options) == "table" then table.clone(options) else {}
	return {
		DisplayName = select(2, CrewMemberCanonicalReadGate.ResolveMetadataHelperDisplayName(source, storageName, helperOptions)),
		Rarity = select(2, CrewMemberCanonicalReadGate.ResolveMetadataHelperRarity(source, storageName, helperOptions)),
		RenderIcon = select(2, CrewMemberCanonicalReadGate.ResolveMetadataHelperRenderIcon(source, storageName, helperOptions)),
		RealCharacterName = select(
			2,
			CrewMemberCanonicalReadGate.ResolveMetadataHelperRealCharacterName(source, storageName, helperOptions)
		),
		Arc = select(2, CrewMemberCanonicalReadGate.ResolveMetadataHelperArc(source, storageName, helperOptions)),
		CompatibilityClassification = select(
			2,
			CrewMemberCanonicalReadGate.ResolveMetadataHelperCompatibilityClassification(source, storageName, helperOptions)
		),
	}
end

function CrewMemberCanonicalReadGate.ResolveStandStatusDisplayName(source, storageName, options)
	return evaluateStandStatusDisplayNameHelper(source, storageName, options)
end

function CrewMemberCanonicalReadGate.ResolveIncomeStatusDisplayName(source, storageName, options)
	return evaluateIncomeStatusDisplayNameHelper(source, storageName, options)
end

function CrewMemberCanonicalReadGate.ResolveIncomeToastDisplayName(source, storageName, options)
	return evaluateIncomeToastDisplayNameHelper(source, storageName, options)
end

function CrewMemberCanonicalReadGate.ResolveFoodStatusDisplayName(source, storageName, options)
	return evaluateFoodStatusDisplayNameHelper(source, storageName, options)
end

function CrewMemberCanonicalReadGate.ResolveStandStatusReadAuthority(source, standName, options)
	return evaluateStandStatusReadAuthority(source, standName, options)
end

function CrewMemberCanonicalReadGate.ResolveIncomeStatusReadAuthority(source, standName, options)
	return evaluateIncomeStatusReadAuthority(source, standName, options)
end

function CrewMemberCanonicalReadGate.ResolveFoodStatusReadAuthority(source, target, options)
	return evaluateFoodStatusReadAuthority(source, target, options)
end

function CrewMemberCanonicalReadGate.ResolveAdminModelPreviewDescriptor(source, storageName, options)
	return evaluateModelPreviewRead(
		source,
		CrewMemberCanonicalReadGate.Paths.AdminModelPreview,
		storageName,
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveIndexModelPreviewDescriptor(source, storageName, options)
	return evaluateModelPreviewRead(
		source,
		CrewMemberCanonicalReadGate.Paths.IndexModelPreview,
		storageName,
		options
	)
end

function CrewMemberCanonicalReadGate.ResolveInventoryModelPreviewDescriptor(source, storageName, options)
	return evaluateModelPreviewRead(
		source,
		CrewMemberCanonicalReadGate.Paths.InventoryModelPreview,
		storageName,
		options
	)
end

function CrewMemberCanonicalReadGate.PrintStatus(player, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	local root, rootReason = getRoot(player)
	local flags = CrewMemberCanonicalReadGate.GetFlags(options.Flags)
	local status = if root then CrewMemberShadowWriter.GetLastValidationStatus(root, { Player = player }) else nil
	local counts = getBlockingCounts(status)
	local keys = status and status.CanonicalKeys
	print(string.format(
		"%s status player=%s dualRead=%s canonicalRead=%s displayReads=%s inventoryDisplayRead=%s sellDialogDisplayRead=%s indexDisplayRead=%s gameplayReads=%s readAuthority=%s standStatusReadAuthority=%s incomeStatusReadAuthority=%s foodStatusReadAuthority=%s writeAuthority=%s quickSlotsWriteAuthority=%s productQuickSlotWriteAuthority=%s profileMigrationDryRun=%s profileMigrationWrite=%s saveLoadValidation=%s migrationKillSwitch=%s helperReads=%s metadataHelperReads=%s standStatusHelperRead=%s incomeStatusHelperRead=%s incomeToastHelperRead=%s foodStatusHelperRead=%s modelPreviewReads=%s adminModelPreviewRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s diagnostics=%s validationAge=%.1fs keysValid=%s root=%s blocking={total=%d mismatch=%d stand=%d duplicate=%d unknown=%d income=%d compatibilityOnly=%d brookFallback=%d}",
		LOG_PREFIX,
		getPlayerName(player),
		tostring(flags.CrewMemberDualReadEnabled),
		tostring(flags.CrewMemberCanonicalReadEnabled),
		tostring(flags.CrewMemberCanaryDisplayReadsEnabled),
		tostring(flags.CrewMemberCanaryInventoryDisplayReadEnabled),
		tostring(flags.CrewMemberCanarySellDialogDisplayReadEnabled),
		tostring(flags.CrewMemberCanaryIndexDisplayReadEnabled),
		tostring(flags.CrewMemberCanaryGameplayReadsEnabled),
		tostring(flags.CrewMemberCanaryReadAuthorityEnabled),
		tostring(flags.CrewMemberCanaryStandStatusReadAuthorityEnabled),
		tostring(flags.CrewMemberCanaryIncomeStatusReadAuthorityEnabled),
		tostring(flags.CrewMemberCanaryFoodStatusReadAuthorityEnabled),
		tostring(flags.CrewMemberCanaryWriteAuthorityEnabled),
		tostring(flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled),
		tostring(flags.CrewMemberProductQuickSlotWriteAuthorityEnabled),
		tostring(flags.CrewMemberCanaryProfileMigrationDryRunEnabled),
		tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled),
		tostring(flags.CrewMemberCanarySaveLoadValidationEnabled),
		tostring(flags.CrewMemberMigrationKillSwitchEnabled),
		tostring(flags.CrewMemberCanaryGameplayHelperReadsEnabled),
		tostring(flags.CrewMemberCanaryMetadataHelperReadsEnabled),
		tostring(flags.CrewMemberCanaryStandStatusHelperReadEnabled),
		tostring(flags.CrewMemberCanaryIncomeStatusHelperReadEnabled),
		tostring(flags.CrewMemberCanaryIncomeToastHelperReadEnabled),
		tostring(flags.CrewMemberCanaryFoodStatusHelperReadEnabled),
		tostring(flags.CrewMemberCanaryModelPreviewReadsEnabled),
		tostring(flags.CrewMemberCanaryAdminModelPreviewReadEnabled),
		tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
		tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
		tostring(flags.CrewMemberCanaryDiagnosticsEnabled),
		status and (tonumber(status.ValidationAgeSeconds) or -1) or -1,
		tostring(keys and keys.IsValid == true),
		tostring(root and "ok" or rootReason),
		counts.Total or 0,
		counts.Mismatch or 0,
		counts.Stand or 0,
		counts.Duplicate or 0,
		counts.Unknown or 0,
		counts.BlockingIncomeMismatch or 0,
		counts.CompatibilityOnly or 0,
		counts.BrookFallback or 0
	))
	return status
end

function CrewMemberCanonicalReadGate.PrintMetadataHelperStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local helperResults = CrewMemberCanonicalReadGate.ResolveMetadataHelperSet(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Results = helperResults,
		}
		print(string.format(
			"%s helper-status item=%s display={value=%s canonical=%s fallback=%s} rarity={value=%s canonical=%s fallback=%s} render={value=%s canonical=%s fallback=%s} realName={value=%s canonical=%s fallback=%s} arc={value=%s canonical=%s fallback=%s} compatibility={value=%s canonical=%s fallback=%s}",
			LOG_PREFIX,
			tostring(storageName or ""),
			metadataHelperValueToText(helperResults.DisplayName.Value),
			tostring(helperResults.DisplayName.UsedCanonical == true),
			tostring(helperResults.DisplayName.FallbackReason or "none"),
			metadataHelperValueToText(helperResults.Rarity.Value),
			tostring(helperResults.Rarity.UsedCanonical == true),
			tostring(helperResults.Rarity.FallbackReason or "none"),
			metadataHelperValueToText(helperResults.RenderIcon.Value),
			tostring(helperResults.RenderIcon.UsedCanonical == true),
			tostring(helperResults.RenderIcon.FallbackReason or "none"),
			metadataHelperValueToText(helperResults.RealCharacterName.Value),
			tostring(helperResults.RealCharacterName.UsedCanonical == true),
			tostring(helperResults.RealCharacterName.FallbackReason or "none"),
			metadataHelperValueToText(helperResults.Arc.Value),
			tostring(helperResults.Arc.UsedCanonical == true),
			tostring(helperResults.Arc.FallbackReason or "none"),
			metadataHelperValueToText(helperResults.CompatibilityClassification.Value),
			tostring(helperResults.CompatibilityClassification.UsedCanonical == true),
			tostring(helperResults.CompatibilityClassification.FallbackReason or "none")
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintStandStatusHelperStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local _, result = CrewMemberCanonicalReadGate.ResolveStandStatusDisplayName(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Result = result,
		}
		print(string.format(
			"%s stand-status-helper item=%s value=%s canonical=%s fallback=%s legacy=%s canonicalValue=%s authoritative=%s legacyIdentity=%s validationAge=%.1fs",
			LOG_PREFIX,
			tostring(storageName or ""),
			metadataHelperValueToText(result.Value),
			tostring(result.UsedCanonical == true),
			tostring(result.FallbackReason or "none"),
			metadataHelperValueToText(result.LegacyValue),
			metadataHelperValueToText(result.CanonicalValue),
			tostring(result.IsAuthoritative == true),
			tostring(result.LegacyIdentity or ""),
			tonumber(result.ValidationAgeSeconds) or -1
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintStandStatusReadAuthorityStatus(source, standNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	standNames = if typeof(standNames) == "table" then standNames else { standNames }

	local rows = {}
	for _, standName in ipairs(standNames) do
		local _, result = CrewMemberCanonicalReadGate.ResolveStandStatusReadAuthority(source, standName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			StandName = tostring(standName or ""),
			Result = result,
		}
		print(string.format(
			"%s stand-status-read-authority stand=%s source=%s selectedDisplay=%s usedCanonical=%s fallback=%s legacy=%s legacyInstance=%s canonical=%s canonicalInstance=%s authorityMode=%s mutationAuthority=%s validationAge=%.1fs",
			LOG_PREFIX,
			tostring(standName or ""),
			tostring(result.Source or ""),
			tostring(result.DisplayName or ""),
			tostring(result.UsedCanonical == true),
			tostring(result.FallbackReason or "none"),
			tostring(result.LegacyIdentity or ""),
			tostring(result.LegacyInstanceId or ""),
			tostring(result.CanonicalIdentity or ""),
			tostring(result.CanonicalInstanceId or ""),
			tostring(result.AuthorityMode or ""),
			tostring(result.IsMutationAuthority == true),
			tonumber(result.ValidationAgeSeconds) or -1
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintIncomeStatusReadAuthorityStatus(source, standNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	standNames = if typeof(standNames) == "table" then standNames else { standNames }

	local rows = {}
	for _, standName in ipairs(standNames) do
		local _, result = CrewMemberCanonicalReadGate.ResolveIncomeStatusReadAuthority(source, standName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			StandName = tostring(standName or ""),
			Result = result,
		}
		print(string.format(
			"%s income-status-read-authority stand=%s source=%s selectedDisplay=%s usedCanonical=%s fallback=%s legacy=%s legacyInstance=%s canonicalIncome=%s canonicalIncomeInstance=%s canonicalInventory=%s assignedStand=%s legacyIncome=%s canonicalIncomeAmount=%s authorityMode=%s mutationAuthority=%s validationAge=%.1fs",
			LOG_PREFIX,
			tostring(standName or ""),
			tostring(result.Source or ""),
			tostring(result.DisplayName or ""),
			tostring(result.UsedCanonical == true),
			tostring(result.FallbackReason or "none"),
			tostring(result.LegacyIdentity or ""),
			tostring(result.LegacyInstanceId or ""),
			tostring(result.CanonicalIncomeIdentity or ""),
			tostring(result.CanonicalIncomeInstanceId or ""),
			tostring(result.CanonicalInventoryIdentity or ""),
			tostring(result.CanonicalInventoryAssignedStand or ""),
			tostring(result.LegacyIncomeToCollect or 0),
			tostring(result.CanonicalIncomeToCollect or 0),
			tostring(result.AuthorityMode or ""),
			tostring(result.IsMutationAuthority == true),
			tonumber(result.ValidationAgeSeconds) or -1
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintFoodStatusReadAuthorityStatus(source, contexts, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	contexts = if typeof(contexts) == "table" then contexts else { contexts }

	local rows = {}
	for _, foodContext in ipairs(contexts) do
		local _, result = CrewMemberCanonicalReadGate.ResolveFoodStatusReadAuthority(source, foodContext, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			Context = foodContext,
			Result = result,
		}
		print(string.format(
			"%s food-status-read-authority stand=%s source=%s selectedDisplay=%s usedCanonical=%s fallback=%s legacy=%s legacyInstance=%s storage=%s canonical=%s canonicalInstance=%s assignedStand=%s level=%s/%s xp=%s/%s standLevel=%s appliedFood=%s amount=%s gainedXP=%s authorityMode=%s mutationAuthority=%s validationAge=%.1fs",
			LOG_PREFIX,
			tostring(result.StandName or ""),
			tostring(result.Source or ""),
			tostring(result.DisplayName or ""),
			tostring(result.UsedCanonical == true),
			tostring(result.FallbackReason or "none"),
			tostring(result.LegacyIdentity or ""),
			tostring(result.LegacyInstanceId or ""),
			tostring(result.LegacyStorageName or ""),
			tostring(result.CanonicalIdentity or ""),
			tostring(result.CanonicalInstanceId or ""),
			tostring(result.CanonicalAssignedStand or ""),
			tostring(result.Level or ""),
			tostring(result.CanonicalLevel or ""),
			tostring(result.CurrentXP or ""),
			tostring(result.CanonicalCurrentXP or ""),
			tostring(result.StandLevel or ""),
			tostring(result.AppliedFoodKey or ""),
			tostring(result.AppliedFoodAmountUsed or ""),
			tostring(result.AppliedFoodXPGained or ""),
			tostring(result.AuthorityMode or ""),
			tostring(result.IsMutationAuthority == true),
			tonumber(result.ValidationAgeSeconds) or -1
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintIncomeStatusHelperStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local _, result = CrewMemberCanonicalReadGate.ResolveIncomeStatusDisplayName(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Result = result,
		}
		print(string.format(
			"%s income-status-helper item=%s value=%s canonical=%s fallback=%s legacy=%s canonicalValue=%s authoritative=%s legacyIdentity=%s validationAge=%.1fs",
			LOG_PREFIX,
			tostring(storageName or ""),
			metadataHelperValueToText(result.Value),
			tostring(result.UsedCanonical == true),
			tostring(result.FallbackReason or "none"),
			metadataHelperValueToText(result.LegacyValue),
			metadataHelperValueToText(result.CanonicalValue),
			tostring(result.IsAuthoritative == true),
			tostring(result.LegacyIdentity or ""),
			tonumber(result.ValidationAgeSeconds) or -1
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintIncomeToastHelperStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local _, result = CrewMemberCanonicalReadGate.ResolveIncomeToastDisplayName(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Result = result,
		}
		print(string.format(
			"%s income-toast-helper item=%s value=%s canonical=%s fallback=%s legacy=%s canonicalValue=%s authoritative=%s legacyIdentity=%s validationAge=%.1fs",
			LOG_PREFIX,
			tostring(storageName or ""),
			metadataHelperValueToText(result.Value),
			tostring(result.UsedCanonical == true),
			tostring(result.FallbackReason or "none"),
			metadataHelperValueToText(result.LegacyValue),
			metadataHelperValueToText(result.CanonicalValue),
			tostring(result.IsAuthoritative == true),
			tostring(result.LegacyIdentity or ""),
			tonumber(result.ValidationAgeSeconds) or -1
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintFoodStatusHelperStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local _, result = CrewMemberCanonicalReadGate.ResolveFoodStatusDisplayName(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Result = result,
		}
		print(string.format(
			"%s food-status-helper item=%s value=%s canonical=%s fallback=%s legacy=%s canonicalValue=%s authoritative=%s legacyIdentity=%s validationAge=%.1fs",
			LOG_PREFIX,
			tostring(storageName or ""),
			metadataHelperValueToText(result.Value),
			tostring(result.UsedCanonical == true),
			tostring(result.FallbackReason or "none"),
			metadataHelperValueToText(result.LegacyValue),
			metadataHelperValueToText(result.CanonicalValue),
			tostring(result.IsAuthoritative == true),
			tostring(result.LegacyIdentity or ""),
			tonumber(result.ValidationAgeSeconds) or -1
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintAdminModelPreviewStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local descriptor = CrewMemberCanonicalReadGate.ResolveAdminModelPreviewDescriptor(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Descriptor = descriptor,
		}
		print(string.format(
			"%s model-preview-status item=%s model={name=%s path=%s canonical=%s fallback=%s previewOnly=%s legacyIdentity=%s source=%s canonicalUnavailable=%s legacyUnavailable=%s}",
			LOG_PREFIX,
			tostring(storageName or ""),
			tostring(descriptor.ModelName or ""),
			tostring(descriptor.ModelPath or ""),
			tostring(descriptor.UsedCanonical == true),
			tostring(descriptor.FallbackReason or "none"),
			tostring(descriptor.IsPreviewOnly == true),
			tostring(descriptor.LegacyIdentity or ""),
			tostring(descriptor.Source or ""),
			tostring(descriptor.CanonicalUnavailableReason or "none"),
			tostring(descriptor.LegacyUnavailableReason or "none")
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintIndexModelPreviewStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local descriptor = CrewMemberCanonicalReadGate.ResolveIndexModelPreviewDescriptor(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Descriptor = descriptor,
		}
		print(string.format(
			"%s index-model-preview-status item=%s model={name=%s path=%s canonical=%s fallback=%s previewOnly=%s legacyIdentity=%s source=%s canonicalUnavailable=%s legacyUnavailable=%s}",
			LOG_PREFIX,
			tostring(storageName or ""),
			tostring(descriptor.ModelName or ""),
			tostring(descriptor.ModelPath or ""),
			tostring(descriptor.UsedCanonical == true),
			tostring(descriptor.FallbackReason or "none"),
			tostring(descriptor.IsPreviewOnly == true),
			tostring(descriptor.LegacyIdentity or ""),
			tostring(descriptor.Source or ""),
			tostring(descriptor.CanonicalUnavailableReason or "none"),
			tostring(descriptor.LegacyUnavailableReason or "none")
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.PrintInventoryModelPreviewStatus(source, storageNames, options)
	options = if typeof(options) == "table" then table.clone(options) else {}
	storageNames = if typeof(storageNames) == "table" then storageNames else { storageNames }

	local rows = {}
	for _, storageName in ipairs(storageNames) do
		local descriptor = CrewMemberCanonicalReadGate.ResolveInventoryModelPreviewDescriptor(source, storageName, {
			Flags = options.Flags,
			LogThrottleSeconds = options.LogThrottleSeconds,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Player = options.Player,
			SkipLog = true,
		})
		rows[#rows + 1] = {
			ItemId = tostring(storageName or ""),
			Descriptor = descriptor,
		}
		print(string.format(
			"%s inventory-model-preview-status item=%s model={name=%s path=%s canonical=%s fallback=%s previewOnly=%s legacyIdentity=%s source=%s canonicalUnavailable=%s legacyUnavailable=%s}",
			LOG_PREFIX,
			tostring(storageName or ""),
			tostring(descriptor.ModelName or ""),
			tostring(descriptor.ModelPath or ""),
			tostring(descriptor.UsedCanonical == true),
			tostring(descriptor.FallbackReason or "none"),
			tostring(descriptor.IsPreviewOnly == true),
			tostring(descriptor.LegacyIdentity or ""),
			tostring(descriptor.Source or ""),
			tostring(descriptor.CanonicalUnavailableReason or "none"),
			tostring(descriptor.LegacyUnavailableReason or "none")
		))
	end
	return rows
end

function CrewMemberCanonicalReadGate.GetLegacyDisplayMetadata(storageName)
	return buildLegacyDisplayMetadata(storageName)
end

function CrewMemberCanonicalReadGate.GetCanonicalCatalogMetadata(storageName)
	return buildCanonicalCatalogMetadata(storageName)
end

return CrewMemberCanonicalReadGate
