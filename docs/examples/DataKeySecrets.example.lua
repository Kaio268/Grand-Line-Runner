return {
	Production = {
		KeyId = "prod-v1",
		DataKey = "REPLACE_WITH_RELEASE_PRODUCTION_KEY",
	},
	Staging = {
		KeyId = "staging-v1",
		DataKey = "REPLACE_WITH_PRIVATE_STAGING_KEY",
	},
	Development = {
		KeyId = "dev-v1",
		DataKey = "REPLACE_WITH_PRIVATE_DEVELOPMENT_KEY",
	},
	RecoveryStores = {
		-- Add suspected old production namespaces here only during a reviewed incident.
		-- Use the alias in /datarecover source=<alias>; never type raw keys into chat.
		OldProductionCandidate = {
			KeyId = "old-production-candidate",
			DataKey = "REPLACE_WITH_PRIVATE_RECOVERY_CANDIDATE_KEY",
		},
	},
}
