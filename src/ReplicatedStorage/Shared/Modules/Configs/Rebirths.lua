do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Rebirths"))
end

local Rebirths = {
	[1] = {
		Price = 1000,
		SpeedNeeded = 15,
		
		Getting = {
			["Multipliers.MoneyMult"] = {Amount =1.5, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 150, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 150, Icon = "rbxassetid://96331945137652"},
		}
	},
	
	[2] = {
		Price = 25000,
		SpeedNeeded = 30,

		Getting = {
			["Multipliers.MoneyMult"] = {Amount =2, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 300, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 300, Icon = "rbxassetid://96331945137652"},
		}
	},
	
	[3] = {
		Price = 300000,
		SpeedNeeded = 45,

		Getting = {
			["Multipliers.MoneyMult"] = {Amount =2.5, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 450, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 450, Icon = "rbxassetid://96331945137652"},
		}
	},
	[4] = {
		Price = 2500000,
		SpeedNeeded = 60,

		Getting = {
			["Multipliers.MoneyMult"] = {Amount =3, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 600, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 600, Icon = "rbxassetid://96331945137652"},
		}
	},
	[5] = {
		Price = 50000000,
		SpeedNeeded = 75,

		Getting = {
			["Multipliers.MoneyMult"] = {Amount =3.5, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 750, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 750, Icon = "rbxassetid://96331945137652"},
		}
	},
	[6] = {
		Price = 250000000,
		SpeedNeeded = 90,

		Getting = {
			["Multipliers.MoneyMult"] = {Amount =4, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 900, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 900, Icon = "rbxassetid://96331945137652"},
		}
	},
	[7] = {
		Price = 2500000000,
		SpeedNeeded = 105,

		Getting = {
			["Multipliers.MoneyMult"] = {Amount =4.5, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 1200, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 1200, Icon = "rbxassetid://96331945137652"},
		}
	},
	[8] = {
		Price = 10000000000,
		SpeedNeeded = 120,

		Getting = {
			["Multipliers.MoneyMult"] = {Amount =5, Icon = "rbxassetid://99305009492305"},
			["Potions.x2MoneyTime"] = {Amount = 1500, Icon = "rbxassetid://112694595954613"},
			["Potions.x15WalkSpeedTime"] = {Amount = 1500, Icon = "rbxassetid://96331945137652"},
		}
	},
}

return Rebirths

