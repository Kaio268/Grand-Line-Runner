local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local HieConfig = {
	FruitKey = "Glacial",
	FruitName = "Glacial Fruit",
}

function HieConfig.GetFruitConfig()
	return DevilFruitConfig.GetFruit(HieConfig.FruitName)
end

function HieConfig.GetAbilityConfig(abilityName)
	return DevilFruitConfig.GetAbility(HieConfig.FruitName, abilityName)
end

return HieConfig
