-- Code reward reference:
--
-- Standard chests:
-- {
-- 	Amount = 1,
-- 	ChestKind = "Standard",
-- 	Tier = "Wooden", -- "Wooden", "Iron", or "Gold"
-- }
--
-- Devil fruit chests:
-- {
-- 	Amount = 1,
-- 	ChestKind = "DevilFruit",
-- 	FruitRarity = "Mythic", -- "Common", "Rare", "Legendary", or "Mythic"
-- }
--
-- You can give multiple rewards by adding more entries inside Rewards.Chests.
-- Players must be in the Roblox group configured by SocialGroups.GroupRewardGroupId.
-- ExpiresAtUnix can be nil for no expiry, or a Unix timestamp for an expiry date.
local Codes = {
	RELEASE = {
		DisplayName = "Release",
		ExpiresAtUnix = nil,
		Rewards = {
			Chests = {
				{
					Amount = 1,
					ChestKind = "Standard",
					Tier = "Gold",
				},
			},
		},
	},

	SUMMER = {
		DisplayName = "Summer",
		ExpiresAtIso = "2026-08-05T00:00:00Z",
		Rewards = {
			Chests = {
				{
					Amount = 1,
					ChestKind = "Standard",
					Tier = "Iron",
				},
			},
		},
	},
	KAIO = {
		DisplayName = "Secret Boss",
		ExpiresAtIso = nil,
		Rewards = {
			Chests = {
				{
					Amount = 5,
					ChestKind = "Standard",
					Tier = "Gold",
				},
			},
		},
	},
}

return Codes
