return {
	Production = {
		KeyId = "prod-historical-v1",
		DataKey = "DefaultKey_123",
	},
	Staging = {
		KeyId = "staging-v1",
		DataKey = "",
	},
	Development = {
		KeyId = "dev-local-v1",
		DataKey = "",
	},
	RecoveryStores = {
		["historical-fallback"] = {
			KeyId = "historical-fallback-candidate",
			DataKey = "DefaultKey_123",
		},
	},
}
