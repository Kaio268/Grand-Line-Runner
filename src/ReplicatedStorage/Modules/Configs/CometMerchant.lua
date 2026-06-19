local Economy = require(script.Parent:WaitForChild("GrandLineRushEconomy"))

local CometMerchant = {
	RequiresPaidRandomItemPolicy = false,
	RobuxFundedRandomCurrency = false,

	All_Things = {
		["Potions.x2MoneyTime"] = {
			Display_name = "2x Beli Boost",

			Chance = 40,
			Amount = math.random(120, 300),

			Stock = math.random(1, 3),

			Price = 125,

			Icon = "rbxassetid://123727379614328",
			Desc = "Earn 2x Beli and double your profits for a limited time!",
		},

		["Potions.x15WalkSpeedTime"] = {
			Display_name = "x1.5 Walk Speed Boost",

			Chance = 40,
			Amount = math.random(120, 300),

			Stock = math.random(1, 3),

			Price = 125,

			Icon = "rbxassetid://96331945137652",
			Desc = "Get x1.5 WalkSpeed and move faster for a limited time!",
		},

		["leaderstats.Beli"] = {
			Display_name = "??? Beli",

			Chance = 40,
			Amount = math.random(100, 100000),

			Stock = math.random(1, 5),

			Price = 25,

			Icon = "rbxassetid://76300573750363",
			Desc = "Random amount of Beli, you can get over 100M!",
		},

		["Pot Hotspot"] = {
			Display_name = "Crew Reward Pending",

			Chance = 0,
			Amount = math.random(1, 1),

			Stock = math.random(1, 1),

			Price = 2500,

			Icon = "rbxassetid://104255768072595",
			Desc = "This crew reward is being updated before launch.",
		},

		["Tide Monk"] = {
			Display_name = "Tide Monk",

			Chance = 20,
			Amount = math.random(1, 1),

			Stock = math.random(1, 1),

			Price = 750,

			Icon = "rbxassetid://112159737210505",
			Desc = "Recruit a Mythic crewmate to boost your Beli production.",
		},

		["Rhino Toasterino"] = {
			Display_name = "Leopard Agent",

			Chance = 50,
			Amount = math.random(1, 1),

			Stock = math.random(1, 3),

			Price = 50,

			Icon = "rbxassetid://92244593874593",
			Desc = "Generate insane amounts of Beli and skyrocket your progression!",
		},
	},
}

for itemKey, itemConfig in pairs(CometMerchant.All_Things or {}) do
	if typeof(itemConfig) == "table" then
		if itemConfig.Price ~= nil then
			itemConfig.Price = Economy.ScaleAmount(itemConfig.Price)
		end
		if tostring(itemKey) == "leaderstats.Beli" and itemConfig.Amount ~= nil then
			itemConfig.Amount = Economy.ScaleAmount(itemConfig.Amount)
		end
	end
end

return CometMerchant
