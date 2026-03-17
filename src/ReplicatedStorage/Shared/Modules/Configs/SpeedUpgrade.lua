do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SpeedUpgrade"))
end

local SpeeUpgrade = {
	[1] = {
		Starter_Price = 200,
		
		Price_Mult = 1.15,
		
		AddSpeed = 1,
		
		ProductID = 3516522193
	},
	 
	[2] = {
		Starter_Price = 200,

		Price_Mult = 1.15,

		AddSpeed = 5,
		
		ProductID = 3516522992
	},
	
	[3] = {
		Starter_Price = 200,

		Price_Mult = 1.15,

		AddSpeed = 10,
		
		ProductID = 3516522609
	},
}

return SpeeUpgrade
