local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CrewIncomeBalance = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance")
)

local maxLevel = CrewIncomeBalance.GetMaxLevel()
local multipliers = {}

for level = 1, maxLevel do
	multipliers[tostring(level)] = CrewIncomeBalance.GetLevelIncomeMultiplier(level)
end

return multipliers
