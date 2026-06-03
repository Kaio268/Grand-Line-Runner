local IncomeClaimMath = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CrewIncomeBalance = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance")
)

local cachedTitleService = nil

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

function IncomeClaimMath.BuildClaimSummary(rawIncome, collectMultiplier, titleMultiplier)
	local normalizedCollectMultiplier = sanitizeMultiplier(collectMultiplier)
	local normalizedTitleMultiplier = sanitizeMultiplier(titleMultiplier)
	local preTitleAmount, preTitleExactAmount =
		CrewIncomeBalance.GetClaimableFromRaw(rawIncome, normalizedCollectMultiplier)
	local finalAmount = IncomeClaimMath.ApplyWholeAmountMultiplier(preTitleAmount, normalizedTitleMultiplier)
	local rawRemainderAmount, exactRemainderAmount =
		CrewIncomeBalance.GetRawRemainderAfterClaim(rawIncome, normalizedCollectMultiplier, preTitleAmount)

	return {
		RawIncome = math.max(0, tonumber(rawIncome) or 0),
		CollectMultiplier = normalizedCollectMultiplier,
		TitleMultiplier = normalizedTitleMultiplier,
		PreTitleAmount = preTitleAmount,
		PreTitleExactAmount = preTitleExactAmount,
		FinalAmount = finalAmount,
		ExactAmount = preTitleExactAmount * normalizedTitleMultiplier,
		RawRemainderAmount = rawRemainderAmount,
		ExactRemainderAmount = exactRemainderAmount,
		IsBoosted = (normalizedCollectMultiplier * normalizedTitleMultiplier) > 1.001,
		TitleBoosted = normalizedTitleMultiplier > 1.001,
	}
end

function IncomeClaimMath.BuildRateSummary(baseIncome, bankMultiplier, collectMultiplier, titleMultiplier)
	local normalizedBaseIncome = math.max(0, tonumber(baseIncome) or 0)
	local normalizedBankMultiplier = sanitizeMultiplier(bankMultiplier)
	local normalizedCollectMultiplier = sanitizeMultiplier(collectMultiplier)
	local normalizedTitleMultiplier = sanitizeMultiplier(titleMultiplier)
	local totalMultiplier = normalizedBankMultiplier * normalizedCollectMultiplier * normalizedTitleMultiplier
	local preTitleAmount = normalizedBaseIncome * normalizedBankMultiplier * normalizedCollectMultiplier
	local finalAmount = preTitleAmount * normalizedTitleMultiplier

	return {
		BaseIncome = normalizedBaseIncome,
		BankMultiplier = normalizedBankMultiplier,
		CollectMultiplier = normalizedCollectMultiplier,
		TitleMultiplier = normalizedTitleMultiplier,
		TotalMultiplier = totalMultiplier,
		PreTitleAmount = preTitleAmount,
		FinalAmount = finalAmount,
		IsBoosted = totalMultiplier > 1.001,
		TitleBoosted = normalizedTitleMultiplier > 1.001,
	}
end

return IncomeClaimMath
