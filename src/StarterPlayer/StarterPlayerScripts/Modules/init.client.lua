local GIFT_BOOT_DEBUG = false

local function giftBootLog(...)
	if GIFT_BOOT_DEBUG then
		print("[GIFT][BOOT]", ...)
	end
end

local timeRewardsModule = script:WaitForChild("Time_Rewards")
giftBootLog("loader", script:GetFullName(), "module", timeRewardsModule:GetFullName())

local ok, result = pcall(require, timeRewardsModule)
if not ok then
	warn("[GIFT][ERROR]", "Failed to require Time_Rewards module:", result)
else
	giftBootLog("required", timeRewardsModule:GetFullName())
end
