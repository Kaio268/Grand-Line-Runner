do
	return require(game:GetService("ReplicatedStorage"):WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CometMerchant"))
end

local CometMerchant = {
	
	All_Things = {
		["Potions.x2MoneyTime"] = {
			Display_name = "x2 Doubloons Boost",
			
			Chance = 40,
			Amount = math.random(120,300),
			
			Stock = math.random(1,3),
			
			Price = 125,
			
			Icon = "rbxassetid://102766068687661",
			Desc = "Earn x2 Doubloons and double your profits for a limited time!"
		},
		
		["Potions.x15WalkSpeedTime"] = {
			Display_name = "x1.5 Walk Speed Boost",

			Chance = 40,
			Amount = math.random(120,300),

			Stock = math.random(1,3),

			Price = 125,
			
			Icon = "rbxassetid://89427336475199",
			Desc = "Get x1.5 WalkSpeed and move faster for a limited time!"
		},
		
		["leaderstats.Doubloons"] = {
			Display_name = "??? Doubloons",

			Chance = 40,
			Amount = math.random(100,100000),

			Stock = math.random(1,5),

			Price = 25,

			Icon = "rbxassetid://134664902697800",
			Desc = "Random amount of Doubloons, you can get over 100M!"
		},
		
		["Pot Hotspot"] = {
			Display_name = "Pot Hotspot",

			Chance = 1,
			Amount = math.random(1,1),

			Stock = math.random(1,1),

			Price = 2500,

			Icon = "rbxassetid://104255768072595",
			Desc = "Generate insane amounts of Doubloons and skyrocket your progression!"
		},
		
		["Tirilikalika Tirilikalako"] = {
			Display_name = "Tirilikalika Tirilikalako",

			Chance = 20,
			Amount = math.random(1,1),

			Stock = math.random(1,1),

			Price = 750,

			Icon = "rbxassetid://136792506025468",
			Desc = "Generate insane amounts of Doubloons and skyrocket your progression!"
		},
		
		["Rhino Toasterino"] = {
			Display_name = "Rhino Toasterino",

			Chance = 50,
			Amount = math.random(1,1),

			Stock = math.random(1,3),

			Price = 50,

			Icon = "rbxassetid://92244593874593",
			Desc = "Generate insane amounts of Doubloons and skyrocket your progression!"
		},
	}
}

return CometMerchant
