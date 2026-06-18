local Economy = require(script.Parent:WaitForChild("GrandLineRushEconomy"))

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

local function computeRawCost(config, currentSpeed)
	local starterPrice = tonumber(config and config.Starter_Price) or 0
	local priceMultiplier = tonumber(config and config.Price_Mult) or 1
	local addSpeed = tonumber(config and config.AddSpeed) or 1
	local speed = math.max(tonumber(currentSpeed) or 1, 1)
	local currentLevel = math.max(speed - 1, 0)
	local total = 0

	for offset = 0, addSpeed - 1 do
		total += starterPrice * (priceMultiplier ^ (currentLevel + offset))
	end

	return math.floor(total + 0.5)
end

function SpeeUpgrade.ComputeCost(config, currentSpeed)
	return Economy.ScaleAmount(computeRawCost(config, currentSpeed))
end

return SpeeUpgrade
