do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SpawnParts"))
end

return {
	DefaultLuckMult = 1,

	LuckMult = {
		Common = 100,
		Uncommon = 50,
		Rare = 20,
		Epic = 4,
		Legendary = .2,
		Mythic = .02,
		Mythical = .004,
		Godly = .0008,
		Secret = .0004,
		Omega = .00008,
	},

	RarityTier = {
		Common = 1,
		Uncommon = 2,
		Rare = 3,
		Epic = 4,
		Legendary = 5,

		Mythic = 6,
		Mythical = 6,  

		Godly = 7,
		Secret = 8,
		Omega = 9,
	},
}
