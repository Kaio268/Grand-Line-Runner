local IncomeClaimMath = {}

local EPSILON = 1e-7

local function sanitizeNumber(value)
	local numeric = tonumber(value) or 0
	if numeric ~= numeric or numeric == math.huge or numeric == -math.huge then
		return 0
	end

	return math.max(0, numeric)
end

function IncomeClaimMath.GetWholeClaimableAmount(rawIncome, collectMultiplier)
	local raw = sanitizeNumber(rawIncome)
	local multiplier = sanitizeNumber(collectMultiplier)
	local exactAmount = raw * multiplier
	if exactAmount <= 0 then
		return 0, 0
	end

	return math.max(0, math.floor(exactAmount + EPSILON)), exactAmount
end

function IncomeClaimMath.GetRawRemainderAfterClaim(rawIncome, collectMultiplier, claimedAmount)
	local raw = sanitizeNumber(rawIncome)
	local multiplier = sanitizeNumber(collectMultiplier)
	if raw <= 0 or multiplier <= 0 then
		return 0, 0
	end

	local claimed = math.max(0, math.floor(sanitizeNumber(claimedAmount)))
	local exactAmount = raw * multiplier
	local remainingExactAmount = exactAmount - claimed
	if remainingExactAmount <= EPSILON then
		return 0, 0
	end

	return remainingExactAmount / multiplier, remainingExactAmount
end

return IncomeClaimMath
