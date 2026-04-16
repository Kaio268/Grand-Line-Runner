local Rewards = {

	[1] = {
		RewName = "+ 1000 Beli",
		Icon = "rbxassetid://76300573750363",

		Time               = 60,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			Doubloons = { Chance = 100, Amount = 1000 },
		},
	},

	[2] = {
		RewName = "5 Min x2 Beli",
		Icon = "rbxassetid://112694595954613",

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
		RewName = "+ 10000 Beli",
		Icon = "rbxassetid://76300573750363",

		Time               = 900,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			Doubloons = { Chance = 100, Amount = 10000 },
		},
	},

	[5] = {
		RewName = "10 Min x1.5 Walkspeed",
		Icon = "rbxassetid://96331945137652",

		Time               = 1800,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			x15WalkSpeedTime = { Chance = 100, Amount = 600 },
		},
	},
	
	[6] = {
		RewName = "Bombardiro Crocodilo",
		Icon = "rbxassetid://108324428541699",

		Time               = 2100,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			["Bombardiro Crocodilo"] = {Chance = 100, Amount  = 1, Brainrot = true},
		},
	},
	
	[7] = {
		RewName = "Frigo Camelo",
		Icon = "rbxassetid://84916034746691",

		Time               = 2400,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			["Frigo Camelo"] = {Chance = 100, Amount  = 1, Brainrot = true},
		},
	},
	
	[8] = {
		RewName = "+ 100000 Beli",
		Icon = "rbxassetid://76300573750363",

		Time               = 3600,
		RewardTextTemplate = "You Get %d %s",
		Rewards            = {
			Doubloons = { Chance = 100, Amount = 100000 },
		},
	},
	
}

return Rewards

