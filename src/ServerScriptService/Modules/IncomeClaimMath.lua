local IncomeClaimMath = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CrewIncomeBalance = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance")
)

local cachedTitleService = nil
local INDEX_MONEY_MULTIPLIER_PATH = "Multipliers.MoneyMult"

local function sanitizeMultiplier(value)
	return math.max(0, tonumber(value) or 1)
end

local function getTitleService()
	if cachedTitleService == nil then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TitleService"))
		end)
		cachedTitleService = if ok and typeof(result) == "table" then result else false
	end

	return if cachedTitleService == false then nil else cachedTitleService
end

function IncomeClaimMath.GetWholeClaimableAmount(rawIncome, collectMultiplier)
	return CrewIncomeBalance.GetClaimableFromRaw(rawIncome, collectMultiplier)
end

function IncomeClaimMath.GetRawRemainderAfterClaim(rawIncome, collectMultiplier, claimedAmount)
	return CrewIncomeBalance.GetRawRemainderAfterClaim(rawIncome, collectMultiplier, claimedAmount)
end

function IncomeClaimMath.GetTitleBeliMultiplier(player)
	local titleService = getTitleService()
	if titleService == nil or typeof(titleService.GetEquippedTitleBuffMultiplier) ~= "function" then
		return 1
	end

	local ok, multiplier = pcall(titleService.GetEquippedTitleBuffMultiplier, player, "beli")
	return if ok then sanitizeMultiplier(multiplier) else 1
end

function IncomeClaimMath.GetIndexMoneyMultiplier(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return 1
	end

	local valueObject = nil
	local multipliers = player:FindFirstChild("Multipliers")
	if multipliers then
		valueObject = multipliers:FindFirstChild("MoneyMult")
	end

	local amount = 0
	if valueObject and (valueObject:IsA("NumberValue") or valueObject:IsA("IntValue")) then
		amount = tonumber(valueObject.Value) or 0
	else
		local current = player
		for _, segment in ipairs(INDEX_MONEY_MULTIPLIER_PATH:split(".")) do
			current = current and current:FindFirstChild(segment)
			if not current then
				break
			end
		end
		if current and (current:IsA("NumberValue") or current:IsA("IntValue")) then
			amount = tonumber(current.Value) or 0
		end
	end

	return 1 + math.max(0, amount)
end

function IncomeClaimMath.GetRewardBeliMultiplier(player)
	return sanitizeMultiplier(IncomeClaimMath.GetTitleBeliMultiplier(player))
		* sanitizeMultiplier(IncomeClaimMath.GetIndexMoneyMultiplier(player))
end

function IncomeClaimMath.ApplyWholeAmountMultiplier(amount, multiplier)
	local wholeAmount = math.max(0, math.floor(tonumber(amount) or 0))
	local normalizedMultiplier = sanitizeMultiplier(multiplier)
	if wholeAmount <= 0 then
		return 0
	end
	if math.abs(normalizedMultiplier - 1) < 0.001 then
		return wholeAmount
	end

	return math.max(0, math.floor((wholeAmount * normalizedMultiplier) + 0.5))
end

function IncomeClaimMath.BuildClaimSummary(rawIncome, collectMultiplier, rewardMultiplier, multiplierMetadata)
	local normalizedCollectMultiplier = sanitizeMultiplier(collectMultiplier)
	local normalizedRewardMultiplier = sanitizeMultiplier(rewardMultiplier)
	local normalizedTitleMultiplier = sanitizeMultiplier(
		multiplierMetadata and multiplierMetadata.TitleMultiplier or normalizedRewardMultiplier
	)
	local normalizedIndexMultiplier = sanitizeMultiplier(
		multiplierMetadata and multiplierMetadata.IndexMultiplier or 1
	)
	local preTitleAmount, preTitleExactAmount =
		CrewIncomeBalance.GetClaimableFromRaw(rawIncome, normalizedCollectMultiplier)
	local finalAmount = IncomeClaimMath.ApplyWholeAmountMultiplier(preTitleAmount, normalizedRewardMultiplier)
	local rawRemainderAmount, exactRemainderAmount =
		CrewIncomeBalance.GetRawRemainderAfterClaim(rawIncome, normalizedCollectMultiplier, preTitleAmount)

	return {
		RawIncome = math.max(0, tonumber(rawIncome) or 0),
		CollectMultiplier = normalizedCollectMultiplier,
		TitleMultiplier = normalizedTitleMultiplier,
		IndexMultiplier = normalizedIndexMultiplier,
		RewardMultiplier = normalizedRewardMultiplier,
		PreTitleAmount = preTitleAmount,
		PreTitleExactAmount = preTitleExactAmount,
		FinalAmount = finalAmount,
		ExactAmount = preTitleExactAmount * normalizedRewardMultiplier,
		RawRemainderAmount = rawRemainderAmount,
		ExactRemainderAmount = exactRemainderAmount,
		IsBoosted = (normalizedCollectMultiplier * normalizedRewardMultiplier) > 1.001,
		TitleBoosted = normalizedTitleMultiplier > 1.001,
		IndexBoosted = normalizedIndexMultiplier > 1.001,
	}
end

function IncomeClaimMath.BuildRateSummary(baseIncome, bankMultiplier, collectMultiplier, rewardMultiplier, multiplierMetadata)
	local normalizedBaseIncome = math.max(0, tonumber(baseIncome) or 0)
	local normalizedBankMultiplier = sanitizeMultiplier(bankMultiplier)
	local normalizedCollectMultiplier = sanitizeMultiplier(collectMultiplier)
	local normalizedRewardMultiplier = sanitizeMultiplier(rewardMultiplier)
	local normalizedTitleMultiplier = sanitizeMultiplier(
		multiplierMetadata and multiplierMetadata.TitleMultiplier or normalizedRewardMultiplier
	)
	local normalizedIndexMultiplier = sanitizeMultiplier(
		multiplierMetadata and multiplierMetadata.IndexMultiplier or 1
	)
	local totalMultiplier = normalizedBankMultiplier * normalizedCollectMultiplier * normalizedRewardMultiplier
	local preTitleAmount = normalizedBaseIncome * normalizedBankMultiplier * normalizedCollectMultiplier
	local finalAmount = preTitleAmount * normalizedRewardMultiplier

	return {
		BaseIncome = normalizedBaseIncome,
		BankMultiplier = normalizedBankMultiplier,
		CollectMultiplier = normalizedCollectMultiplier,
		TitleMultiplier = normalizedTitleMultiplier,
		IndexMultiplier = normalizedIndexMultiplier,
		RewardMultiplier = normalizedRewardMultiplier,
		TotalMultiplier = totalMultiplier,
		PreTitleAmount = preTitleAmount,
		FinalAmount = finalAmount,
		IsBoosted = totalMultiplier > 1.001,
		TitleBoosted = normalizedTitleMultiplier > 1.001,
		IndexBoosted = normalizedIndexMultiplier > 1.001,
	}
end

return IncomeClaimMath
