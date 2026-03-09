local BrainrotVariants = {}

BrainrotVariants.Order = { "Normal", "Golden", "Diamond" }

BrainrotVariants.Versions = {
	Normal = {
		Chance = 90,
		Folder = nil,
		Prefix = "",
		IncomeMult = 1,
		
		BgColor = Color3.new(0, 0, 0)
	},

	Golden = {
		Chance = 8,
		Folder = "Golden",
		Prefix = "Golden ",
		IncomeMult = 2,
		
		BgColor = Color3.new(1, 0.909804, 0.227451)

	},

	Diamond = {
		Chance = 2,
		Folder = "Diamond",
		Prefix = "Diamond ",
		IncomeMult = 5,
		
		BgColor = Color3.new(0.290196, 0.870588, 1)

	},
}

return BrainrotVariants
