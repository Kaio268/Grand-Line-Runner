do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
end

local Gears = {
	["Slap"] = {
		Type = "Weapon",
		Price = 100,
		Icon = "rbxassetid://88148104241451",
		
		ProductID  = 000000000,
	},
	
	["SpeedCoil"] = {
		Type = "Speed",

		Price = 25000,
		Power = 100,
		Icon = "rbxassetid://122153987474570",
		
		ProductID  = 3516539588,

	},
	
	["Golden Slap"] = {
		Type = "Weapon",
		Price = 25001,
		Icon = "rbxassetid://131060638928619",

		ProductID  = 3516540101,
	},
	
	["Golden SpeedCoil"] = {
		Type = "Speed",

		Price = 100000,
		Power = 100,
		Icon = "rbxassetid://94265886793107",

		ProductID  = 3516540402,
	},
	
	["Diamond Slap"] = {
		Type = "Weapon",
		Price = 100001,
		Icon = "rbxassetid://139918022304787",

		ProductID  = 3516540726,
	},
	
	["Diamond SpeedCoil"] = {
		Type = "Speed",

		Price = 1250000,
		Power = 100,
		Icon = "rbxassetid://95392007897016",

		ProductID  = 3516541163,
	},
	
	["Galaxy Slap"] = {
		Type = "Weapon",
		Price = 1250001,
		Icon = "rbxassetid://104659581417778",

		ProductID  = 3516541650,
	},
	
	["Galaxy SpeedCoil"] = {
		Type = "Speed",

		Price = 7500000,
		Power = 100,
		Icon = "rbxassetid://125805320684399",

		ProductID  = 3516542043,
	},
	
	["Lava Slap"] = {
		Type = "Weapon",
		Price = 7500001,
		Icon = "rbxassetid://102666494299264",

		ProductID  = 3516542817,
	},
	
	["Lava SpeedCoil"] = {
		Type = "Speed",

		Price = 50000000,
		Power = 100,
		Icon = "rbxassetid://77116729306685",

		ProductID  = 3516543186,
	},
}

return Gears
