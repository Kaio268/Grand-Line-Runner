return {
	Production = {
		KeyId = "prod-historical-v1",
		DataKey = "REPLACE_WITH_HISTORICAL_PRODUCTION_KEY",
	},
	Staging = {
		KeyId = "staging-v1",
		DataKey = "REPLACE_WITH_PRIVATE_STAGING_KEY",
	},
	Development = {
		KeyId = "dev-local-v1",
		DataKey = "REPLACE_WITH_PRIVATE_DEVELOPMENT_KEY",
	},
	RecoveryStores = {
		-- Add suspected old production namespaces here during an incident.
		-- Use the alias in /datarecover source=<alias>; never type raw keys into chat.
		["historical-fallback"] = {
			KeyId = "historical-fallback-candidate",
			DataKey = "REPLACE_WITH_PRIVATE_HISTORICAL_FALLBACK_KEY",
		},
		OldProductionCandidate = {
			KeyId = "old-production-candidate",
			DataKey = "REPLACE_WITH_PRIVATE_RECOVERY_CANDIDATE_KEY",
		},
	},
}
