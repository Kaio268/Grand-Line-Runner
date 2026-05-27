local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))

local Rebirths = {
	ShipIncomeMultiplierMilestones = {
		{ Rebirths = 0, Multiplier = 1.00 },
		{ Rebirths = 1, Multiplier = 1.50 },
		{ Rebirths = 2, Multiplier = 2.25 },
		{ Rebirths = 3, Multiplier = 3.25 },
		{ Rebirths = 4, Multiplier = 4.50 },
		{ Rebirths = 5, Multiplier = 6.00 },
		{ Rebirths = 10, Multiplier = 16.00 },
		{ Rebirths = 25, Multiplier = 80.00 },
		{ Rebirths = 50, Multiplier = 275.00 },
	},
	PostMilestoneShipIncomeGrowthRate = 0.08,
	ShipIncomeIcon = "rbxassetid://99305009492305",
	BeliCostBase = 1_000_000,
	BeliCostExponent = 1.45,
	BeliCostGrowth = 1.25,
	BeliCostRoundTo = 100_000,
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

local function roundToNearest(value, step)
	local numericStep = math.max(1, tonumber(step) or 1)
	return math.floor(((tonumber(value) or 0) / numericStep) + 0.5) * numericStep
end

local function getSortedShipIncomeMilestones()
	local milestones = {}

	for _, milestone in ipairs(Rebirths.ShipIncomeMultiplierMilestones) do
		local rebirths = tonumber(milestone.Rebirths)
		local multiplier = tonumber(milestone.Multiplier)
		if rebirths and multiplier and multiplier > 0 then
			milestones[#milestones + 1] = {
				Rebirths = math.max(0, math.floor(rebirths)),
				Multiplier = multiplier,
			}
		end
	end

	table.sort(milestones, function(left, right)
		return left.Rebirths < right.Rebirths
	end)

	return milestones
end

local function interpolateGeometric(startMultiplier, endMultiplier, alpha)
	local startValue = tonumber(startMultiplier) or 0
	local endValue = tonumber(endMultiplier) or 0
	local clampedAlpha = math.clamp(tonumber(alpha) or 0, 0, 1)

	if startValue <= 0 or endValue <= 0 then
		return startValue + ((endValue - startValue) * clampedAlpha)
	end

	return startValue * ((endValue / startValue) ^ clampedAlpha)
end

function Rebirths.GetShipIncomeMultiplier(rebirthCount)
	local numericRebirths = coerceWholeNumber(rebirthCount, 0)
	local milestones = getSortedShipIncomeMilestones()

	if #milestones == 0 then
		return 1
	end

	local firstMilestone = milestones[1]
	if numericRebirths <= firstMilestone.Rebirths then
		return roundToHundredths(firstMilestone.Multiplier)
	end

	for index, milestone in ipairs(milestones) do
		if numericRebirths == milestone.Rebirths then
			return roundToHundredths(milestone.Multiplier)
		end

		local nextMilestone = milestones[index + 1]
		if nextMilestone and numericRebirths < nextMilestone.Rebirths then
			local span = nextMilestone.Rebirths - milestone.Rebirths
			local progress = (numericRebirths - milestone.Rebirths) / span
			return roundToHundredths(interpolateGeometric(milestone.Multiplier, nextMilestone.Multiplier, progress))
		end
	end

	local finalMilestone = milestones[#milestones]
	local growthRate = math.max(0, tonumber(Rebirths.PostMilestoneShipIncomeGrowthRate) or 0)
	local extraRebirths = numericRebirths - finalMilestone.Rebirths
	local multiplier = finalMilestone.Multiplier * ((1 + growthRate) ^ extraRebirths)

	return roundToHundredths(multiplier)
end

function Rebirths.GetBeliCostForRebirth(targetRebirthCount)
	local target = math.max(1, coerceWholeNumber(targetRebirthCount, 1))
	local rawCost = Rebirths.BeliCostBase
		* (target ^ Rebirths.BeliCostExponent)
		* (Rebirths.BeliCostGrowth ^ (target - 1))

	return roundToNearest(rawCost, Rebirths.BeliCostRoundTo)
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

local function buildConfig(index)
	local targetRebirthCount = math.max(1, coerceWholeNumber(index, 1))
	local currentRebirthCount = targetRebirthCount - 1
	local shipLevelNeeded = Rebirths.GetHighestShipLevelForRebirthCount(currentRebirthCount)
	local price = Rebirths.GetBeliCostForRebirth(targetRebirthCount)
	local multiplier = Rebirths.GetShipIncomeMultiplier(targetRebirthCount)

	return {
		Index = targetRebirthCount,
		BeliCost = price,
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

