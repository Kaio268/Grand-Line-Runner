local timeRewardsModule = script.Parent:WaitForChild("Time_Rewards")

local ok, result = pcall(require, timeRewardsModule)
if not ok then
	warn("[GIFT][ERROR]", "Failed to require Time_Rewards module:", result)
end
