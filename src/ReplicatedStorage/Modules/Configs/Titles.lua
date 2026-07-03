local Titles = {}

local TIER_ORDER = {
	"Common",
	"Uncommon",
	"Rare",
	"Epic",
	"Legendary",
	"Mythic",
	"Godly",
	"Secret",
}

local TIER_ALIASES = {
	common = "Common",
	uncommon = "Uncommon",
	rare = "Rare",
	epic = "Epic",
	legendary = "Legendary",
	mythic = "Mythic",
	mythical = "Mythic",
	godly = "Godly",
	secret = "Secret",
}

local TIERS = {
	Common = {
		Name = "Common",
		Rank = 1,
		VisualStyle = {
			AccentColor = Color3.fromRGB(188, 197, 211),
			SurfaceColor = Color3.fromRGB(42, 47, 58),
			SurfaceColor2 = Color3.fromRGB(22, 26, 34),
			SealColor = Color3.fromRGB(142, 151, 166),
			LedgerColor = Color3.fromRGB(188, 197, 211),
		},
		ChatStyle = {
			color = Color3.fromRGB(188, 197, 211),
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
	},
	Uncommon = {
		Name = "Uncommon",
		Rank = 2,
		VisualStyle = {
			AccentColor = Color3.fromRGB(112, 220, 140),
			SurfaceColor = Color3.fromRGB(21, 56, 35),
			SurfaceColor2 = Color3.fromRGB(9, 28, 18),
			SealColor = Color3.fromRGB(78, 154, 98),
			LedgerColor = Color3.fromRGB(112, 220, 140),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(112, 220, 140),
					Color3.fromRGB(154, 244, 174),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
	},
	Rare = {
		Name = "Rare",
		Rank = 3,
		VisualStyle = {
			AccentColor = Color3.fromRGB(91, 170, 255),
			SurfaceColor = Color3.fromRGB(18, 44, 67),
			SurfaceColor2 = Color3.fromRGB(9, 25, 40),
			SealColor = Color3.fromRGB(70, 123, 181),
			LedgerColor = Color3.fromRGB(91, 170, 255),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(91, 170, 255),
					Color3.fromRGB(142, 204, 255),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
	},
	Epic = {
		Name = "Epic",
		Rank = 4,
		VisualStyle = {
			AccentColor = Color3.fromRGB(200, 120, 255),
			SurfaceColor = Color3.fromRGB(48, 28, 70),
			SurfaceColor2 = Color3.fromRGB(26, 14, 43),
			SealColor = Color3.fromRGB(139, 84, 178),
			LedgerColor = Color3.fromRGB(200, 120, 255),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(200, 120, 255),
					Color3.fromRGB(230, 175, 255),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
	},
	Legendary = {
		Name = "Legendary",
		Rank = 5,
		VisualStyle = {
			AccentColor = Color3.fromRGB(255, 187, 74),
			SurfaceColor = Color3.fromRGB(61, 40, 18),
			SurfaceColor2 = Color3.fromRGB(28, 18, 9),
			SealColor = Color3.fromRGB(164, 126, 69),
			LedgerColor = Color3.fromRGB(255, 187, 74),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(255, 187, 74),
					Color3.fromRGB(255, 222, 124),
					Color3.fromRGB(255, 155, 64),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
		},
	},
	Mythic = {
		Name = "Mythic",
		Rank = 6,
		VisualStyle = {
			AccentColor = Color3.fromRGB(255, 101, 134),
			SurfaceColor = Color3.fromRGB(45, 17, 32),
			SurfaceColor2 = Color3.fromRGB(31, 10, 24),
			SealColor = Color3.fromRGB(178, 70, 99),
			LedgerColor = Color3.fromRGB(255, 101, 134),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(255, 101, 134),
					Color3.fromRGB(255, 156, 181),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
			animated = true,
			speed = 0.8,
		},
	},
	Godly = {
		Name = "Godly",
		Rank = 7,
		VisualStyle = {
			AccentColor = Color3.fromRGB(255, 84, 84),
			SurfaceColor = Color3.fromRGB(58, 20, 20),
			SurfaceColor2 = Color3.fromRGB(31, 9, 9),
			SealColor = Color3.fromRGB(178, 62, 62),
			LedgerColor = Color3.fromRGB(255, 84, 84),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(255, 84, 84),
					Color3.fromRGB(255, 142, 142),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
			animated = true,
			speed = 1,
		},
	},
	Secret = {
		Name = "Secret",
		Rank = 8,
		VisualStyle = {
			AccentColor = Color3.fromRGB(255, 240, 110),
			SurfaceColor = Color3.fromRGB(54, 48, 19),
			SurfaceColor2 = Color3.fromRGB(20, 17, 10),
			SealColor = Color3.fromRGB(178, 168, 77),
			LedgerColor = Color3.fromRGB(255, 240, 110),
		},
		ChatStyle = {
			gradient = {
				colors = {
					Color3.fromRGB(255, 240, 110),
					Color3.fromRGB(255, 250, 184),
					Color3.fromRGB(255, 221, 72),
				},
			},
			bold = true,
			brackets = true,
			spaceAfter = true,
			animated = true,
			speed = 1.2,
		},
	},
}

TIERS.Mythical = TIERS.Mythic

local TITLE_RARITY_STYLES = {
	Common = {
		Color = Color3.fromRGB(218, 224, 235),
		Effect = "None",
		StrokeTransparency = 0.2,
		ChatColor = Color3.fromRGB(218, 224, 235),
	},
	Uncommon = {
		Color = Color3.fromRGB(124, 232, 152),
		Effect = "None",
		StrokeTransparency = 0.18,
		ChatColor = Color3.fromRGB(124, 232, 152),
	},
	Rare = {
		Color = Color3.fromRGB(112, 198, 255),
		Effect = "SoftGlow",
		StrokeTransparency = 0.1,
		ChatColor = Color3.fromRGB(112, 198, 255),
	},
	Epic = {
		Color = Color3.fromRGB(213, 133, 255),
		Effect = "Gradient",
		StrokeTransparency = 0.08,
		GradientColors = {
			Color3.fromRGB(184, 102, 255),
			Color3.fromRGB(255, 138, 214),
		},
		ChatColor = Color3.fromRGB(213, 133, 255),
	},
	Legendary = {
		Color = Color3.fromRGB(255, 210, 92),
		Effect = "Shimmer",
		StrokeTransparency = 0.04,
		GradientColors = {
			Color3.fromRGB(255, 178, 67),
			Color3.fromRGB(255, 245, 162),
			Color3.fromRGB(255, 193, 74),
		},
		AnimationSpeed = 0.28,
		ChatColor = Color3.fromRGB(255, 210, 92),
	},
	Mythic = {
		Color = Color3.fromRGB(255, 112, 147),
		Effect = "AnimatedGradient",
		StrokeTransparency = 0.02,
		GradientColors = {
			Color3.fromRGB(255, 91, 130),
			Color3.fromRGB(255, 171, 106),
			Color3.fromRGB(255, 123, 192),
		},
		AnimationSpeed = 0.22,
		ChatColor = Color3.fromRGB(255, 112, 147),
	},
	Godly = {
		Color = Color3.fromRGB(255, 95, 95),
		Effect = "Rainbow",
		StrokeTransparency = 0,
		GradientColors = {
			Color3.fromRGB(255, 88, 88),
			Color3.fromRGB(255, 207, 92),
			Color3.fromRGB(119, 235, 157),
			Color3.fromRGB(101, 203, 255),
			Color3.fromRGB(212, 132, 255),
		},
		AnimationSpeed = 0.18,
		ChatColor = Color3.fromRGB(255, 118, 118),
	},
	Secret = {
		Color = Color3.fromRGB(255, 242, 118),
		Effect = "Rainbow",
		StrokeTransparency = 0,
		GradientColors = {
			Color3.fromRGB(255, 242, 118),
			Color3.fromRGB(255, 144, 97),
			Color3.fromRGB(255, 118, 212),
			Color3.fromRGB(123, 202, 255),
			Color3.fromRGB(255, 252, 190),
		},
		AnimationSpeed = 0.15,
		ChatColor = Color3.fromRGB(255, 242, 118),
	},
}

local TITLE_GROUPS = {
	Common = {
		Order = {
			"Tester",
			"Deckhand",
			"RookieCaptain",
			"FirstMate",
			"ChestCracker",
		},
		Definitions = {
			Tester = {
				Id = "Tester",
				DisplayName = "Tester",
				Description = "Temporary pre-release testing title.",
				UnlockType = "Persistent",
				Visibility = "TesterOrAdmin",
				Buffs = {
					beli = 0.10,
					resources = 0.10,
				},
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
			Deckhand = {
				DisplayName = "Deckhand",
				Description = "Every captain starts somewhere, even if it is just learning where the deck ends and the sea begins.",
				RequirementText = "Join the game and claim your starter crew.",
				UnlockType = "Persistent",
			},
			RookieCaptain = {
				DisplayName = "Rookie Captain",
				Description = "You learned the ropes, claimed your first reward, and set sail for the Grand Line.",
				RequirementText = "Complete the first-time tutorial.",
				UnlockType = "Persistent",
			},
			FirstMate = {
				DisplayName = "First Mate",
				Description = "Your first recruit proved that a voyage is stronger with someone standing beside you.",
				RequirementText = "Extract your first crew member.",
				UnlockType = "Persistent",
			},
			ChestCracker = {
				DisplayName = "Chest Cracker",
				Description = "You heard treasure calling and knew exactly what to do.",
				RequirementText = "Open your first treasure chest.",
				UnlockType = "Persistent",
			},
		},
	},
	Uncommon = {
		Order = {
			"CrewCollector",
			"Shiphand",
		},
		Definitions = {
			CrewCollector = {
				DisplayName = "Crew Collector",
				Description = "A growing roster means more hands, more stories, and more Beli flowing back to the ship.",
				RequirementText = "Own 5 crew members.",
				UnlockType = "Persistent",
			},
			Shiphand = {
				DisplayName = "Shiphand",
				Description = "You put resources back into the ship and made the next voyage stronger.",
				RequirementText = "Upgrade your ship for the first time.",
				UnlockType = "Persistent",
			},
		},
	},
	Rare = {
		Order = {
			"EnemyOfTheSea",
			"DeepSeaCourier",
			"RubberRookie",
		},
		Definitions = {
			EnemyOfTheSea = {
				DisplayName = "Enemy of the Sea",
				Description = "Marked by the sea after tasting the power of a Devil Fruit.",
				RequirementText = "Eat your first Devil Fruit.",
				UnlockType = "Persistent",
			},
			DeepSeaCourier = {
				DisplayName = "Deep Sea Courier",
				Description = "You brought cargo back from waters most players avoid.",
				RequirementText = "Extract a reward from Deep depth.",
				UnlockType = "Persistent",
			},
			RubberRookie = {
				DisplayName = "Rubber Rookie",
				Description = "Your first stretch into rubber power made the route feel a little less impossible.",
				RequirementText = "Eat the Elastic Fruit.",
				UnlockType = "Persistent",
			},
		},
	},
	Epic = {
		Order = {
			"WaveFreezer",
			"ColdHearted",
			"CaptainTrainer",
			"GreedOverSpeed",
			"GoldFever",
		},
		Definitions = {
			WaveFreezer = {
				DisplayName = "Wave Freezer",
				Description = "The sea itself stopped moving when your cold will touched it.",
				RequirementText = "Freeze a wave using an ice ability.",
				UnlockType = "Persistent",
			},
			ColdHearted = {
				DisplayName = "Cold-Hearted",
				Description = "One touch was enough to turn another pirate into a statue of ice.",
				RequirementText = "Freeze another player using an ice ability.",
				UnlockType = "Persistent",
			},
			CaptainTrainer = {
				DisplayName = "Captain Trainer",
				Description = "Your crew did not get stronger by accident. You fed them, trained them, and kept them moving.",
				RequirementText = "Gain 15 crew levels by feeding crew members.",
				UnlockType = "Persistent",
			},
			GreedOverSpeed = {
				DisplayName = "Greed Over Speed",
				Description = "You were overloaded, slow, and still refused to drop the loot.",
				RequirementText = "Extract while carrying the maximum number of rewards.",
				UnlockType = "Persistent",
				Buffs = {
					resources = 0.15,
				},
			},
			GoldFever = {
				DisplayName = "Gold Fever",
				Description = "If it shines, it is coming home with you.",
				RequirementText = "Extract a Gold chest from any depth.",
				UnlockType = "Persistent",
				Buffs = {
					beli = 0.08,
				},
			},
		},
	},
	Legendary = {
		Order = {
			"Captain",
			"WoodenMiracle",
			"MaxDeck",
		},
		Definitions = {
			Captain = {
				Id = "Captain",
				DisplayName = "Captain",
				Description = "Permanent title granted by the Captain Pass.",
				RequirementText = "Own the Captain Pass.",
				UnlockType = "Persistent",
				Buffs = {
					beli = 0.50,
					resources = 0.50,
					speed = 0.10,
				},
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
			WoodenMiracle = {
				DisplayName = "Wooden Miracle",
				Description = "The weakest chest gave you something it had no business giving.",
				RequirementText = "Get a high-rarity reward from a Wooden chest.",
				UnlockType = "Persistent",
				Buffs = {
					resources = 0.10,
				},
			},
			MaxDeck = {
				DisplayName = "Max Deck",
				Description = "Your ship is no longer transport. It is a warning.",
				RequirementText = "Upgrade your ship to Level 8.",
				UnlockType = "Persistent",
			},
		},
	},
	Mythic = {
		Order = {
			"SuperRookie",
			"ThePhoenix",
			"RebornFlame",
			"DespawnDenier",
		},
		Definitions = {
			SuperRookie = {
				DisplayName = "Super Rookie",
				Description = "Too slow to survive, too bold to turn back.",
				RequirementText = "Complete an Abyssal run with less than 10 speed.",
				UnlockType = "Persistent",
				Buffs = {
					speed = 0.10,
				},
			},
			ThePhoenix = {
				DisplayName = "The Phoenix",
				Description = "Cloaked in sacred blue flames, this captain rises even when the sea thinks they have fallen.",
				RequirementText = "Eat the Phoenix Fruit.",
				UnlockType = "Persistent",
			},
			RebornFlame = {
				DisplayName = "Reborn Flame",
				Description = "The final blow came, the flames answered, and you stood back up anyway.",
				RequirementText = "Trigger Phoenix Rebirth and survive.",
				UnlockType = "Persistent",
			},
			DespawnDenier = {
				DisplayName = "Despawn Denier",
				Description = "The world tried to erase the loot. You got there first.",
				RequirementText = "Recover and extract a dropped shared chest before despawn.",
				UnlockType = "Persistent",
			},
		},
	},
	Godly = {
		Order = {
			"AbyssTaxCollector",
		},
		Definitions = {
			AbyssTaxCollector = {
				DisplayName = "Abyss Tax Collector",
				Description = "Even the darkest waters had to pay you.",
				RequirementText = "Extract 10 rewards from Abyssal depth.",
				UnlockType = "Persistent",
				Buffs = {
					beli = 0.10,
				},
			},
		},
	},
	Secret = {
		Order = {
			"DressrosaSecret",
			"InsuranceFraud",
			"PirateEmperor",
		},
		Definitions = {
			DressrosaSecret = {
				DisplayName = "Dressrosa Secret",
				Description = "You found a name the world tried to hide.",
				RequirementText = "Own or extract a Secret-rarity crewmate.",
				UnlockType = "Persistent",
				Buffs = {
					resources = 0.10,
				},
			},
			InsuranceFraud = {
				DisplayName = "Insurance Fraud",
				Description = "You died carrying treasure and came back like nothing happened.",
				RequirementText = "Trigger Phoenix Rebirth while carrying a reward.",
				UnlockType = "Persistent",
				Buffs = {
					beli = 0.10,
				},
			},
			PirateEmperor = {
				DisplayName = "Pirate Emperor",
				Description = "Your name sits above the sea.",
				RequirementText = "Reach #1 on the Bounty leaderboard.",
				UnlockType = "DynamicRank",
				RankAttribute = "LB_Bounty",
				RequiredRank = 1,
				Buffs = {
					beli = 1,
					resources = 1,
				},
			},
		},
	},
}

local ORDER = {}
local BY_ID = {}

local function applyTierDefaults(definition)
	local tierKey = TIER_ALIASES[string.lower(tostring(definition.Tier or ""))] or "Common"
	local tier = TIERS[tierKey] or TIERS.Common
	definition.Tier = tier.Name
	definition.TierRank = tier.Rank
	definition.VisualStyle = definition.VisualStyle or tier.VisualStyle
	definition.ChatStyle = definition.ChatStyle or tier.ChatStyle
	definition.Buffs = definition.Buffs or {}
	return definition
end

for _, tierName in ipairs(TIER_ORDER) do
	local group = TITLE_GROUPS[tierName]
	local definitions = group and group.Definitions or {}

	for _, titleId in ipairs((group and group.Order) or {}) do
		local definition = definitions[titleId]
		if definition then
			definition.Id = definition.Id or titleId
			definition.Tier = definition.Tier or tierName
			definition.SortOrder = #ORDER
			ORDER[#ORDER + 1] = titleId
			BY_ID[titleId] = applyTierDefaults(definition)
		end
	end
end

Titles.Order = ORDER
Titles.ById = BY_ID
Titles.ByTier = TITLE_GROUPS
Titles.TierOrder = TIER_ORDER
Titles.TierAliases = TIER_ALIASES
Titles.Tiers = TIERS
Titles.TitleRarityStyles = TITLE_RARITY_STYLES

local function sanitizeDisplayName(value)
	local text = tostring(value or "")
	text = string.gsub(text, "[%c\r\n]", " ")
	text = string.gsub(text, "[%[%]<>]", "")
	text = string.gsub(text, "%s+", " ")
	text = text:match("^%s*(.-)%s*$") or ""
	if #text > 48 then
		text = string.sub(text, 1, 48)
		text = text:match("^(.-)%s*$") or text
	end
	return text
end

function Titles.Get(titleId)
	return BY_ID[titleId]
end

function Titles.SanitizeDisplayName(value)
	return sanitizeDisplayName(value)
end

function Titles.GetDisplayName(titleId)
	local definition = Titles.Get(titleId)
	if typeof(definition) ~= "table" then
		return nil
	end

	local displayName = sanitizeDisplayName(definition.DisplayName or definition.Id or titleId)
	return if displayName ~= "" then displayName else nil
end

local function copyColorArray(colors)
	if typeof(colors) ~= "table" then
		return nil
	end

	local result = {}
	for _, color in ipairs(colors) do
		if typeof(color) == "Color3" then
			result[#result + 1] = color
		end
	end

	return if #result > 0 then result else nil
end

local function getTierStyle(tierName)
	local canonicalTier = TIER_ALIASES[string.lower(tostring(tierName or ""))] or "Common"
	return TITLE_RARITY_STYLES[canonicalTier] or TITLE_RARITY_STYLES.Common, canonicalTier
end

function Titles.ResolveDisplayStyle(titleId)
	local definition = Titles.Get(titleId)
	if typeof(definition) ~= "table" then
		return nil
	end

	local displayName = Titles.GetDisplayName(titleId)
	if not displayName then
		return nil
	end

	local style, rarity = getTierStyle(definition.Tier)
	local color = if typeof(style.Color) == "Color3" then style.Color else Color3.fromRGB(218, 224, 235)
	local chatColor = if typeof(style.ChatColor) == "Color3" then style.ChatColor else color

	return {
		TitleId = tostring(definition.Id or titleId),
		DisplayName = displayName,
		Rarity = rarity,
		TierRank = math.max(1, math.floor(tonumber(definition.TierRank) or 1)),
		Color = color,
		ChatColor = chatColor,
		Effect = tostring(style.Effect or "None"),
		GradientColors = copyColorArray(style.GradientColors),
		AnimationSpeed = math.max(0, tonumber(style.AnimationSpeed) or 0),
		StrokeTransparency = math.clamp(tonumber(style.StrokeTransparency) or 0.18, 0, 1),
		Bold = true,
	}
end

function Titles.GetChatStyle(titleId)
	local style = Titles.ResolveDisplayStyle(titleId)
	if not style then
		return nil
	end

	return {
		color = style.ChatColor,
		bold = style.Bold ~= false,
		brackets = true,
		spaceAfter = true,
		animated = false,
	}
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
