return {
	Production = {
		KeyId = "prod-release-v1",
		DataKey = "REPLACE_WITH_RELEASE_PRODUCTION_KEY",
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
		-- Add recovery aliases only during a reviewed data incident.
		-- Use aliases in /datarecover; never type raw datastore keys into chat.
		OldProductionCandidate = {
			KeyId = "old-production-candidate",
			DataKey = "REPLACE_WITH_PRIVATE_RECOVERY_CANDIDATE_KEY",
		},
	},
}
