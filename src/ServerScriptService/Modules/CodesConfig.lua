local CodesConfig = {
	DefaultDurationSeconds = 30 * 24 * 60 * 60,

	Codes = {
		RELEASE = {
			Enabled = true,
			DisplayName = "Launch Reward",
			StartsAtUnix = 0,
			ExpiresAtUnix = 1783468800, -- 2026-07-08 00:00:00 UTC
			Rewards = {
				{ Type = "Chest", Tier = "Gold", Amount = 50 },
				{ Type = "Chest", Tier = "Iron", Amount = 50 },
				{ Type = "Currency", Currency = "Beli", Amount = 25000 },
				{ Type = "Material", Key = "Timber", Amount = 250 },
				{ Type = "Material", Key = "Iron", Amount = 40 },
			},
		},
	},
}

return CodesConfig
