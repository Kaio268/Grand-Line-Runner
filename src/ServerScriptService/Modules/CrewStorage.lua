local CrewStorage = {}

local CrewMemberShadowConfig = require(script.Parent:WaitForChild("CrewMemberShadowConfig"))

CrewStorage.Keys = {
	Inventory = "BrainrotInventory",
	QuickSlots = "BrainrotQuickSlots",
	Income = "IncomeBrainrots",
	IndexCollection = "IndexCollection",
	Index = "Brainrots",
	CarriedAttribute = "CarriedBrainrot",
	CarriedImageAttribute = "CarriedBrainrotImage",
	StandName = "BrainrotName",
	StandInstanceId = "BrainrotInstanceId",
}

-- Canonical CrewMember save keys. Retired legacy roots may still be compared
-- by dev tools while saved-data cleanup finishes.
CrewStorage.FutureKeys = {
	Inventory = "CrewMemberInventory",
	QuickSlots = "CrewMemberQuickSlots",
	Income = "CrewMemberIncome",
	IndexCollection = "IndexCollection",
	Index = "CrewMembers",
	CarriedAttribute = "CarriedCrewMember",
	CarriedImageAttribute = "CarriedCrewMemberImage",
	StandName = "CrewMemberName",
	StandInstanceId = "CrewMemberInstanceId",
}

CrewStorage.ShadowFlags = table.clone(CrewMemberShadowConfig.ProductionFlags)
CrewStorage.SessionShadowFlagOverrides = {}

local function applyFlagOverrides(flags, overrides)
	if typeof(overrides) ~= "table" then
		return
	end

	for key in pairs(flags) do
		if overrides[key] ~= nil then
			flags[key] = overrides[key] == true
		end
	end
end

local function cloneSessionOverrides()
	local overrides = {}
	for key, value in pairs(CrewStorage.SessionShadowFlagOverrides) do
		overrides[key] = value == true
	end
	return overrides
end

CrewStorage.ShadowFlagDefaults = {
	CrewMemberShadowWriteEnabled = false,
	CrewMemberShadowValidateEnabled = false,
	CrewMemberShadowReportEnabled = true,
	CrewMemberDualReadEnabled = true,
	CrewMemberCanonicalReadEnabled = false,
	CrewMemberCanaryDisplayReadsEnabled = false,
	CrewMemberCanaryInventoryDisplayReadEnabled = false,
	CrewMemberCanarySellDialogDisplayReadEnabled = false,
	CrewMemberCanaryIndexDisplayReadEnabled = false,
	CrewMemberCanaryDiagnosticsEnabled = true,
	CrewMemberCanaryGameplayReadsEnabled = false,
	CrewMemberCanaryReadAuthorityEnabled = false,
	CrewMemberCanaryStandStatusReadAuthorityEnabled = false,
	CrewMemberCanaryIncomeStatusReadAuthorityEnabled = false,
	CrewMemberCanaryFoodStatusReadAuthorityEnabled = false,
	CrewMemberCanaryWriteAuthorityEnabled = false,
	CrewMemberCanaryQuickSlotsWriteAuthorityEnabled = false,
	CrewMemberProductQuickSlotWriteAuthorityEnabled = false,
	CrewMemberInventoryWriteAuthorityEnabled = false,
	CrewMemberStandIncomeWriteAuthorityEnabled = false,
	CrewMemberProgressionWriteAuthorityEnabled = false,
	CrewMemberLegacyUsageTelemetryEnabled = true,
	CrewMemberLegacyWriteFreezeEnabled = false,
	CrewMemberCanaryProfileMigrationDryRunEnabled = false,
	CrewMemberCanaryProfileMigrationWriteEnabled = false,
	CrewMemberCanarySaveLoadValidationEnabled = false,
	CrewMemberMigrationKillSwitchEnabled = true,
	CrewMemberCanaryGameplayHelperReadsEnabled = false,
	CrewMemberCanaryMetadataHelperReadsEnabled = false,
	CrewMemberCanaryStandStatusHelperReadEnabled = false,
	CrewMemberCanaryIncomeStatusHelperReadEnabled = false,
	CrewMemberCanaryIncomeToastHelperReadEnabled = false,
	CrewMemberCanaryFoodStatusHelperReadEnabled = false,
	CrewMemberCanaryModelPreviewReadsEnabled = true,
	CrewMemberCanaryAdminModelPreviewReadEnabled = false,
	CrewMemberCanaryIndexModelPreviewReadEnabled = true,
	CrewMemberCanaryInventoryModelPreviewReadEnabled = true,
	CrewMemberCanonicalReadStrictValidation = true,
	CrewMemberCanonicalReadFallbackToLegacy = true,
	CrewMemberCanonicalReadDisableOnMismatch = true,
	CrewMemberShadowWriteStrictMode = false,
}

local incomeShadowSyncStateByPlayer = setmetatable({}, { __mode = "k" })

function CrewStorage.GetShadowFlags(overrides)
	local flags, environment = CrewMemberShadowConfig.GetEnvironmentFlags()

	if environment.IsStaging ~= true then
		applyFlagOverrides(flags, CrewStorage.ShadowFlags)
	else
		applyFlagOverrides(flags, CrewStorage.SessionShadowFlagOverrides)
	end
	applyFlagOverrides(flags, overrides)

	if CrewMemberShadowConfig.EmergencyDisableShadowWrite == true then
		flags.CrewMemberShadowWriteEnabled = false
		flags.CrewMemberShadowValidateEnabled = false
	end

	-- Canonical reads are intentionally locked off for the shadow-write phase.
	flags.CrewMemberCanonicalReadEnabled = false
	if flags.CrewMemberCanaryWriteAuthorityEnabled ~= true then
		flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled = false
	end
	if flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true
		and (
			flags.CrewMemberCanaryWriteAuthorityEnabled == true
			or flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true
			or flags.CrewMemberCanaryProfileMigrationWriteEnabled == true
			or flags.CrewMemberCanaryReadAuthorityEnabled == true
			or flags.CrewMemberCanonicalReadEnabled == true
			or flags.CrewMemberCanaryGameplayReadsEnabled == true
		)
	then
		flags.CrewMemberProductQuickSlotWriteAuthorityEnabled = false
	end
	if flags.CrewMemberInventoryWriteAuthorityEnabled == true
		and (
			flags.CrewMemberCanaryWriteAuthorityEnabled == true
			or flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true
			or flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true
			or flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true
			or flags.CrewMemberCanaryProfileMigrationWriteEnabled == true
			or flags.CrewMemberCanaryReadAuthorityEnabled == true
			or flags.CrewMemberCanonicalReadEnabled == true
			or flags.CrewMemberCanaryGameplayReadsEnabled == true
		)
	then
		flags.CrewMemberInventoryWriteAuthorityEnabled = false
	end
	if flags.CrewMemberStandIncomeWriteAuthorityEnabled == true
		and (
			flags.CrewMemberCanaryWriteAuthorityEnabled == true
			or flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true
			or flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true
			or flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true
			or flags.CrewMemberCanaryProfileMigrationWriteEnabled == true
			or flags.CrewMemberCanaryReadAuthorityEnabled == true
			or flags.CrewMemberCanonicalReadEnabled == true
			or flags.CrewMemberCanaryGameplayReadsEnabled == true
		)
	then
		flags.CrewMemberStandIncomeWriteAuthorityEnabled = false
	end
	if flags.CrewMemberProgressionWriteAuthorityEnabled == true
		and (
			flags.CrewMemberCanaryWriteAuthorityEnabled == true
			or flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true
			or flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true
			or flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true
			or flags.CrewMemberCanaryProfileMigrationWriteEnabled == true
			or flags.CrewMemberCanaryReadAuthorityEnabled == true
			or flags.CrewMemberCanonicalReadEnabled == true
			or flags.CrewMemberCanaryGameplayReadsEnabled == true
		)
	then
		flags.CrewMemberProgressionWriteAuthorityEnabled = false
	end
	if flags.CrewMemberLegacyWriteFreezeEnabled == true
		and (
			flags.CrewMemberCanaryProfileMigrationWriteEnabled == true
			or flags.CrewMemberCanonicalReadEnabled == true
			or flags.CrewMemberCanaryGameplayReadsEnabled == true
		)
	then
		flags.CrewMemberLegacyWriteFreezeEnabled = false
	end
	return flags
end

function CrewStorage.SetSessionShadowFlagOverride(flagName, enabled)
	if CrewStorage.ShadowFlagDefaults[tostring(flagName or "")] == nil then
		return false, "unknown_flag"
	end

	CrewStorage.SessionShadowFlagOverrides[tostring(flagName)] = enabled == true
	return true, nil
end

function CrewStorage.SetMetadataHelperReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryModelPreviewReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetStandStatusHelperReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetIncomeStatusHelperReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetStandIncomeStatusHelperReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetIncomeToastHelperReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetFoodStatusHelperReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetAllGameplayHelperReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryModelPreviewReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetStandStatusReadAuthoritySessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetIncomeStatusReadAuthoritySessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetFoodStatusReadAuthoritySessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetCombinedReadAuthoritySessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetProfileMigrationDryRunSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanarySaveLoadValidationEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberMigrationKillSwitchEnabled", true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberProductQuickSlotWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberInventoryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetProfileMigrationWriteSampledSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanarySaveLoadValidationEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberMigrationKillSwitchEnabled", true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberProductQuickSlotWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberInventoryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetQuickSlotsWriteAuthoritySessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberProductQuickSlotWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberInventoryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberMigrationKillSwitchEnabled", true)

	local flags = CrewStorage.GetShadowFlags()
	if flags.CrewMemberCanaryWriteAuthorityEnabled ~= true then
		CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
		flags = CrewStorage.GetShadowFlags()
	end
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetProductQuickSlotWriteAuthoritySessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberProductQuickSlotWriteAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberInventoryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberMigrationKillSwitchEnabled", true)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetInventoryWriteAuthoritySessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberInventoryWriteAuthorityEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryQuickSlotsWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberProductQuickSlotWriteAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationDryRunEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryProfileMigrationWriteEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusReadAuthorityEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryMetadataHelperReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryStandStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIncomeToastHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryFoodStatusHelperReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryModelPreviewReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryAdminModelPreviewReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIndexModelPreviewReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryInventoryModelPreviewReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberMigrationKillSwitchEnabled", true)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetAdminModelPreviewReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryModelPreviewReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryAdminModelPreviewReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIndexModelPreviewReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryInventoryModelPreviewReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetIndexModelPreviewReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryModelPreviewReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIndexModelPreviewReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryAdminModelPreviewReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryInventoryModelPreviewReadEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.SetInventoryModelPreviewReadSessionOverride(enabled)
	local environment = CrewMemberShadowConfig.ResolveEnvironment()
	if enabled == true and environment.IsStaging ~= true then
		return false, "staging_environment_required", environment
	end

	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryModelPreviewReadsEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryInventoryModelPreviewReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryIndexModelPreviewReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryAdminModelPreviewReadEnabled", enabled == true)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanaryGameplayReadsEnabled", false)
	CrewStorage.SetSessionShadowFlagOverride("CrewMemberCanonicalReadEnabled", false)

	local flags = CrewStorage.GetShadowFlags()
	return true, nil, {
		Environment = environment,
		Overrides = cloneSessionOverrides(),
		Flags = flags,
	}
end

function CrewStorage.GetSessionShadowFlagOverrides()
	return cloneSessionOverrides()
end

function CrewStorage.GetShadowEnvironment()
	return CrewMemberShadowConfig.ResolveEnvironment()
end

function CrewStorage.MarkIncomeShadowBankPending(player, throttleSeconds)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local now = os.clock()
	local state = incomeShadowSyncStateByPlayer[player]
	if typeof(state) ~= "table" then
		state = {}
		incomeShadowSyncStateByPlayer[player] = state
	end

	state.ThrottleSeconds = math.max(0, tonumber(throttleSeconds) or 0)
	state.PendingSince = state.PendingSince or now
	state.LastPendingAt = now
	state.PendingCount = math.max(0, tonumber(state.PendingCount) or 0) + 1
	return table.clone(state)
end

function CrewStorage.MarkIncomeShadowBankSynced(player, throttleSeconds)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local now = os.clock()
	local state = incomeShadowSyncStateByPlayer[player]
	if typeof(state) ~= "table" then
		state = {}
		incomeShadowSyncStateByPlayer[player] = state
	end

	state.ThrottleSeconds = math.max(0, tonumber(throttleSeconds) or 0)
	state.LastRefreshAt = now
	state.PendingSince = nil
	state.LastPendingAt = nil
	state.PendingCount = 0
	return table.clone(state)
end

function CrewStorage.GetIncomeShadowSyncState(player)
	local state = if typeof(player) == "Instance" and player:IsA("Player")
		then incomeShadowSyncStateByPlayer[player]
		else nil
	if typeof(state) ~= "table" then
		return {
			HasPendingIncomeSync = false,
			IncomeLagWithinCoalesceWindow = false,
		}
	end

	local now = os.clock()
	local throttleSeconds = math.max(0, tonumber(state.ThrottleSeconds) or 0)
	local lastRefreshAt = tonumber(state.LastRefreshAt) or 0
	local hasPending = state.PendingSince ~= nil
	local withinWindow = hasPending and throttleSeconds > 0 and now - lastRefreshAt < throttleSeconds
	local copy = table.clone(state)
	copy.HasPendingIncomeSync = hasPending
	copy.IncomeLagWithinCoalesceWindow = withinWindow
	copy.SecondsUntilNextIncomeShadowRefresh = if withinWindow
		then math.max(0, throttleSeconds - (now - lastRefreshAt))
		else 0
	return copy
end

function CrewStorage.ClearIncomeShadowSyncState(player)
	if typeof(player) == "Instance" and player:IsA("Player") then
		incomeShadowSyncStateByPlayer[player] = nil
	end
end

return CrewStorage
