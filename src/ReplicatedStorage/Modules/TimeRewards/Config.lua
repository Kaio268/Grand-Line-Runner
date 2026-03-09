local Rewards = {

	[1] = {
		RewName = "+ 1000 Money",
		Icon = "rbxassetid://134664902697800",

		Time               = 60,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			Money = { Chance = 100, Amount = 1000 },
		},
	},

	[2] = {
		RewName = "5 Min x2 Money",
		Icon = "rbxassetid://102766068687661",

		Time               = 120,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			x2MoneyTime = { Chance = 100, Amount = 300 },
		},
	},
	
	[3] = {
		RewName = "Balerina Capucina",
		Icon = "rbxassetid://113452691198946",

		Time               = 300,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			["Balerina Capucina"] = {Chance = 100, Amount  = 1, Brainrot = true},
		},
	},
	
	[4] = {
		RewName = "+ 10000 Money",
		Icon = "rbxassetid://134664902697800",

		Time               = 900,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			Money = { Chance = 100, Amount = 10000 },
		},
	},

	[5] = {
		RewName = "10 Min x1.5 Walkspeed",
		Icon = "rbxassetid://89427336475199",

		Time               = 1800,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			x15WalkSpeedTime = { Chance = 100, Amount = 600 },
		},
	},
	
	[6] = {
		RewName = "Frigo Camelo",
		Icon = "rbxassetid://84916034746691",

		Time               = 2400,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			["Frigo Camelo"] = {Chance = 100, Amount  = 1, Brainrot = true},
		},
	},
	
	[7] = {
		RewName = "+ 100000 Money",
		Icon = "rbxassetid://134664902697800",

		Time               = 3600,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			Money = { Chance = 100, Amount = 100000 },
		},
	},
	
	[8] = {
		RewName = "Bombardiro Crocodilo",
		Icon = "rbxassetid://108324428541699",

		Time               = 5400,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			["Bombardiro Crocodilo"] = {Chance = 100, Amount  = 1, Brainrot = true},
		},
	},
}

return Rewards
