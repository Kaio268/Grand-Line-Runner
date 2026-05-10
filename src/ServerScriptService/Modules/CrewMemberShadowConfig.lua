local RunService = game:GetService("RunService")

local CrewMemberShadowConfig = {}

CrewMemberShadowConfig.EmergencyDisableShadowWrite = false

CrewMemberShadowConfig.EnableInStudio = true

-- Add non-production staging/test place or universe ids here before a published staging soak.
-- Studio/local Play remains staging through EnableInStudio.
CrewMemberShadowConfig.StagingPlaceIds = {}
CrewMemberShadowConfig.StagingGameIds = {}

CrewMemberShadowConfig.ProductionFlags = {
	CrewMemberShadowWriteEnabled = false,
	CrewMemberShadowValidateEnabled = false,
	CrewMemberShadowReportEnabled = true,
	CrewMemberDualReadEnabled = false,
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
	CrewMemberSaveLoadCanonicalFirstEnabled = false,
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
	CrewMemberCanaryModelPreviewReadsEnabled = false,
	CrewMemberCanaryAdminModelPreviewReadEnabled = false,
	CrewMemberCanaryIndexModelPreviewReadEnabled = false,
	CrewMemberCanaryInventoryModelPreviewReadEnabled = false,
	CrewMemberCanonicalReadStrictValidation = true,
	CrewMemberCanonicalReadFallbackToLegacy = true,
	CrewMemberCanonicalReadDisableOnMismatch = true,
	CrewMemberShadowWriteStrictMode = false,
	CrewMemberDisplayHelperLegacyFallbackDenyEnabled = false,
	CrewMemberStandIncomeLegacyFallbackReadDenyEnabled = false,
	CrewMemberFoodProgressionLegacyFallbackReadDenyEnabled = false,
}

CrewMemberShadowConfig.StagingFlags = {
	CrewMemberShadowWriteEnabled = true,
	CrewMemberShadowValidateEnabled = true,
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
	CrewMemberSaveLoadCanonicalFirstEnabled = false,
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
	CrewMemberCanaryModelPreviewReadsEnabled = false,
	CrewMemberCanaryAdminModelPreviewReadEnabled = false,
	CrewMemberCanaryIndexModelPreviewReadEnabled = false,
	CrewMemberCanaryInventoryModelPreviewReadEnabled = false,
	CrewMemberCanonicalReadStrictValidation = true,
	CrewMemberCanonicalReadFallbackToLegacy = true,
	CrewMemberCanonicalReadDisableOnMismatch = true,
	CrewMemberShadowWriteStrictMode = false,
	CrewMemberDisplayHelperLegacyFallbackDenyEnabled = true,
	CrewMemberStandIncomeLegacyFallbackReadDenyEnabled = true,
	CrewMemberFoodProgressionLegacyFallbackReadDenyEnabled = true,
}

CrewMemberShadowConfig.ReportCleanIncomeBankEverySeconds = 30
CrewMemberShadowConfig.CanonicalReadValidationFreshnessSeconds = 120
CrewMemberShadowConfig.CanaryDiagnosticLogThrottleSeconds = 60

local function isEnabledId(map, id)
	return typeof(map) == "table" and map[tonumber(id) or 0] == true
end

function CrewMemberShadowConfig.ResolveEnvironment(context)
	context = if typeof(context) == "table" then context else {}

	local isStudio = if context.IsStudio ~= nil then context.IsStudio == true else RunService:IsStudio()
	local placeId = tonumber(context.PlaceId) or game.PlaceId
	local gameId = tonumber(context.GameId) or game.GameId
	local jobId = tostring(context.JobId or game.JobId or "")
	local enabledByStudio = CrewMemberShadowConfig.EnableInStudio == true and isStudio
	local enabledByPlace = isEnabledId(CrewMemberShadowConfig.StagingPlaceIds, placeId)
	local enabledByGame = isEnabledId(CrewMemberShadowConfig.StagingGameIds, gameId)
	local isStaging = (enabledByStudio or enabledByPlace or enabledByGame)
		and CrewMemberShadowConfig.EmergencyDisableShadowWrite ~= true

	return {
		IsStudio = isStudio,
		PlaceId = placeId,
		GameId = gameId,
		JobId = jobId,
		IsStaging = isStaging,
		EnabledByStudio = enabledByStudio,
		EnabledByPlace = enabledByPlace,
		EnabledByGame = enabledByGame,
		EmergencyDisabled = CrewMemberShadowConfig.EmergencyDisableShadowWrite == true,
		Source = if enabledByStudio then "studio"
			elseif enabledByPlace then "place_id"
			elseif enabledByGame then "game_id"
			else "production_default",
	}
end

function CrewMemberShadowConfig.GetEnvironmentFlags(context)
	local environment = CrewMemberShadowConfig.ResolveEnvironment(context)
	local flags = if environment.IsStaging
		then table.clone(CrewMemberShadowConfig.StagingFlags)
		else table.clone(CrewMemberShadowConfig.ProductionFlags)

	flags.CrewMemberCanonicalReadEnabled = false

	return flags, environment
end

return CrewMemberShadowConfig
