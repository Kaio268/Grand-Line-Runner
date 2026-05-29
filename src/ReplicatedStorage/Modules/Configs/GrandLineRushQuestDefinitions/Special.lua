local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))

return {
	{
		Id = "special_first_crew",
		Category = "Special",
		Name = "First Mate",
		Description = "Extract your first crew member.",
		Objective = { Type = "ExtractCrew", Target = 1 },
		Rewards = {
			{
				Type = "Chest",
				ChestKind = ChestRewards.ChestKinds.DevilFruit,
				Tier = "Wooden",
				FruitRarity = "Common",
				Amount = 1,
			},
		},
	},
	{
		Id = "special_chest_starter",
		Category = "Special",
		Name = "Locked Supply",
		Description = "Open 10 treasure chests.",
		Objective = { Type = "OpenChest", Target = 10 },
		Rewards = {
			{
				Type = "Chest",
				ChestKind = ChestRewards.ChestKinds.DevilFruit,
				Tier = "Wooden",
				FruitRarity = "Common",
				Amount = 1,
			},
		},
	},
	{
		Id = "special_deep_explorer",
		Category = "Special",
		Name = "Deep Route",
		Description = "Extract 5 rewards from Deep depth or deeper.",
		Objective = { Type = "ReachDepth", Target = 5, DepthBand = "Deep" },
		Rewards = {
			{
				Type = "Chest",
				ChestKind = ChestRewards.ChestKinds.DevilFruit,
				Tier = "Iron",
				FruitRarity = "Common",
				Amount = 1,
			},
		},
	},
	{
		Id = "special_crew_training",
		Category = "Special",
		Name = "Reliable Hands",
		Description = "Gain 15 crew levels by feeding crew members.",
		Objective = { Type = "UpgradeCrew", Target = 15 },
		Rewards = {
			{
				Type = "Chest",
				ChestKind = ChestRewards.ChestKinds.DevilFruit,
				Tier = "Iron",
				FruitRarity = "Common",
				Amount = 1,
			},
		},
	},
	{
		Id = "special_route_runner",
		Category = "Special",
		Name = "Route Runner",
		Description = "Extract 25 rewards from corridor runs.",
		Objective = { Type = "ReachDepth", Target = 25, DepthBand = "Shallow" },
		Rewards = {
			{ Type = "Currency", Amount = 1200 },
			{ Type = "Food", Key = "Rice", Amount = 10 },
			{ Type = "Material", Key = "Timber", Amount = 10 },
		},
	},
	{
		Id = "special_beli_hoard",
		Category = "Special",
		Name = "Beli Hoard",
		Description = "Collect 10,000 Beli from support systems.",
		Objective = { Type = "EarnBeli", Target = 10000 },
		Rewards = {
			{ Type = "Currency", Amount = 2000 },
			{ Type = "Food", Key = "Meat", Amount = 4 },
			{ Type = "Material", Key = "Iron", Amount = 3 },
		},
	},
	{
		Id = "special_gold_cache",
		Category = "Special",
		Name = "Golden Cache",
		Description = "Open 25 Gold treasure chests.",
		Objective = { Type = "OpenChest", Target = 25, Tier = "Gold" },
		Rewards = {
			{
				Type = "Chest",
				ChestKind = ChestRewards.ChestKinds.DevilFruit,
				Tier = "Iron",
				FruitRarity = "Common",
				Amount = 2,
			},
		},
	},
	{
		Id = "special_master_recruiter",
		Category = "Special",
		Name = "Master Recruiter",
		Description = "Extract 50 crew members from corridor runs.",
		Objective = { Type = "ExtractCrew", Target = 50 },
		Rewards = {
			{ Type = "Currency", Amount = 3500 },
			{ Type = "Food", Key = "Meat", Amount = 6 },
			{ Type = "Material", Key = "Iron", Amount = 6 },
		},
	},
	{
		Id = "special_elite_training",
		Category = "Special",
		Name = "Elite Training",
		Description = "Gain 100 crew levels by feeding crew members.",
		Objective = { Type = "UpgradeCrew", Target = 100 },
		Rewards = {
			{ Type = "Currency", Amount = 4000 },
			{ Type = "Food", Key = "SeaBeastMeat", Amount = 2 },
			{ Type = "Material", Key = "Iron", Amount = 8 },
		},
	},
	{
		Id = "special_final_golden_legend",
		Category = "Special",
		Name = "Final Voyage",
		Description = "Open 10,000 Gold treasure chests.",
		Objective = { Type = "OpenChest", Target = 10000, Tier = "Gold" },
		Rewards = {
			{
				Type = "Crew",
				CrewMemberId = "Azure Phoenix",
				DisplayName = "Azure Phoenix",
				Amount = 1,
			},
		},
	},
}
