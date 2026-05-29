local Titles = {}

local ORDER = {
	"Tester",
	"Captain",
	"EnemyOfTheSea",
	"PirateEmperor",
}

local BY_ID = {
	Tester = {
		Id = "Tester",
		DisplayName = "Tester",
		Description = "Temporary pre-release testing title.",
		UnlockType = "Persistent",
		VisualStyle = {
			AccentColor = Color3.fromRGB(105, 225, 255),
			SurfaceColor = Color3.fromRGB(15, 48, 65),
			SurfaceColor2 = Color3.fromRGB(7, 22, 35),
			SealColor = Color3.fromRGB(61, 165, 205),
			LedgerColor = Color3.fromRGB(125, 234, 255),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(122, 255, 244),
					Color3.fromRGB(92, 181, 255),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
		SortOrder = 0,
	},
	Captain = {
		Id = "Captain",
		DisplayName = "Captain",
		Description = "Permanent title granted by the Captain Pass.",
		RequirementText = "Own the Captain Pass.",
		UnlockType = "Persistent",
		VisualStyle = {
			AccentColor = Color3.fromRGB(255, 213, 92),
			SurfaceColor = Color3.fromRGB(72, 48, 18),
			SurfaceColor2 = Color3.fromRGB(30, 19, 8),
			SealColor = Color3.fromRGB(205, 151, 48),
			LedgerColor = Color3.fromRGB(255, 234, 146),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(255, 244, 173),
					Color3.fromRGB(255, 205, 82),
					Color3.fromRGB(255, 153, 58),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
		SortOrder = 1,
	},
	EnemyOfTheSea = {
		Id = "EnemyOfTheSea",
		DisplayName = "Enemy of the Sea",
		Description = "Marked by the sea after tasting the power of a Devil Fruit.",
		RequirementText = "Eat your first Devil Fruit.",
		UnlockType = "Persistent",
		VisualStyle = {
			AccentColor = Color3.fromRGB(108, 225, 255),
			SurfaceColor = Color3.fromRGB(18, 44, 67),
			SurfaceColor2 = Color3.fromRGB(9, 25, 40),
			SealColor = Color3.fromRGB(82, 132, 164),
			LedgerColor = Color3.fromRGB(137, 233, 255),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(122, 224, 230),
					Color3.fromRGB(85, 180, 255),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
		SortOrder = 2,
	},
	PirateEmperor = {
		Id = "PirateEmperor",
		DisplayName = "Pirate Emperor",
		Description = "Reserved for the captain currently sitting at the top of the bounty seas.",
		RequirementText = "Reach #1 on the Bounty leaderboard.",
		UnlockType = "DynamicRank",
		RankAttribute = "LB_Bounty",
		RequiredRank = 1,
		VisualStyle = {
			AccentColor = Color3.fromRGB(255, 188, 82),
			SurfaceColor = Color3.fromRGB(61, 40, 18),
			SurfaceColor2 = Color3.fromRGB(28, 18, 9),
			SealColor = Color3.fromRGB(164, 126, 69),
			LedgerColor = Color3.fromRGB(255, 214, 116),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(255, 241, 161),
					Color3.fromRGB(255, 199, 84),
					Color3.fromRGB(255, 140, 57),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
		SortOrder = 3,
	},
}

Titles.Order = ORDER
Titles.ById = BY_ID

function Titles.Get(titleId)
	return BY_ID[titleId]
end

function Titles.GetAll()
	local results = {}
	for _, titleId in ipairs(ORDER) do
		local definition = BY_ID[titleId]
		if definition then
			results[#results + 1] = definition
		end
	end

	return results
end

return Titles
