local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))

local Rebirths = {
	BaseShipIncomeMultiplier = 1,
	ShipIncomeMultiplierStep = 0.15,
	ShipIncomeIcon = "rbxassetid://99305009492305",
}

local function coerceWholeNumber(value, fallback)
	local numeric = tonumber(value)
	if typeof(numeric) ~= "number" then
		return fallback
	end

	return math.max(0, math.floor(numeric))
end

local function roundToHundredths(value)
	return math.floor((tonumber(value) or 0) * 100 + 0.5) / 100
end

function Rebirths.GetShipIncomeMultiplier(rebirthCount)
	local numericRebirths = coerceWholeNumber(rebirthCount, 0)
	return roundToHundredths(Rebirths.BaseShipIncomeMultiplier + (numericRebirths * Rebirths.ShipIncomeMultiplierStep))
end

function Rebirths.GetHighestShipLevelForRebirthCount(rebirthCount)
	local numericRebirths = coerceWholeNumber(rebirthCount, 0)
	local highestLevel = 0

	for level = 1, PlotUpgradeConfig.MaxLevel do
		if PlotUpgradeConfig.HasRequiredRebirthsForLevel(level, numericRebirths) then
			highestLevel = level
		else
			break
		end
	end

	return highestLevel
end

local function getPriceForShipLevel(level)
	local targetLevel = PlotUpgradeConfig.ClampLevel(level)
	if targetLevel <= 0 then
		return 0
	end

	local costRequirement = PlotUpgradeConfig.RequirementsByLevel[targetLevel - 1]
	if typeof(costRequirement) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(costRequirement.Doubloons) or 0))
end

local function buildConfig(index)
	local targetRebirthCount = math.max(1, coerceWholeNumber(index, 1))
	local currentRebirthCount = targetRebirthCount - 1
	local shipLevelNeeded = Rebirths.GetHighestShipLevelForRebirthCount(currentRebirthCount)
	local price = getPriceForShipLevel(shipLevelNeeded)
	local multiplier = Rebirths.GetShipIncomeMultiplier(targetRebirthCount)

	return {
		Index = targetRebirthCount,
		Price = price,
		ShipLevelNeeded = shipLevelNeeded,
		PlotUpgradeNeeded = shipLevelNeeded,
		DisplayMultiplier = multiplier,
		Getting = {
			ShipIncomeMultiplier = {
				Amount = multiplier,
				Icon = Rebirths.ShipIncomeIcon,
			},
		},
	}
end

function Rebirths.GetConfig(index)
	return buildConfig(index)
end

function Rebirths.GetNextConfig(currentRebirths)
	return buildConfig(coerceWholeNumber(currentRebirths, 0) + 1)
end

function Rebirths.CanRebirth(currentRebirths, shipLevel, money)
	local config = Rebirths.GetNextConfig(currentRebirths)
	local currentShipLevel = PlotUpgradeConfig.ClampLevel(shipLevel)
	local currentMoney = math.max(0, tonumber(money) or 0)

	return currentShipLevel >= config.PlotUpgradeNeeded and currentMoney >= config.Price, config
end

return setmetatable(Rebirths, {
	__index = function(_, key)
		if typeof(key) == "number" then
			return buildConfig(key)
		end

		return nil
	end,
})

