local IncomeClaimMath = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CrewIncomeBalance = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewIncomeBalance")
)

function IncomeClaimMath.GetWholeClaimableAmount(rawIncome, collectMultiplier)
	return CrewIncomeBalance.GetClaimableFromRaw(rawIncome, collectMultiplier)
end

function IncomeClaimMath.GetRawRemainderAfterClaim(rawIncome, collectMultiplier, claimedAmount)
	return CrewIncomeBalance.GetRawRemainderAfterClaim(rawIncome, collectMultiplier, claimedAmount)
end

return IncomeClaimMath
