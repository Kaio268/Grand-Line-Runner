local Titles = {}

local ORDER = {
	"EnemyOfTheSea",
	"PirateEmperor",
}

local BY_ID = {
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
		SortOrder = 1,
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
		SortOrder = 2,
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
