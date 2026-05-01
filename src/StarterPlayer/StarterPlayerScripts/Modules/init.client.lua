local GIFT_BOOT_DEBUG = true
local GIFT_CLIENT_DEBUG_VERSION = "gifts-client-ui-slots-debug-2026-05-01"

local function giftBootLog(...)
	if GIFT_BOOT_DEBUG then
		print("[GIFT][BOOT][LOADER]", ...)
	end
end

giftBootLog("start", "version", GIFT_CLIENT_DEBUG_VERSION, "script", script:GetFullName())

local timeRewardsModule = script:WaitForChild("Time_Rewards", 15)
if not timeRewardsModule then
	warn(
		"[GIFT][ERROR]",
		"Time_Rewards module missing under Gifts loader after 15s",
		"version",
		GIFT_CLIENT_DEBUG_VERSION,
		"loader",
		script:GetFullName()
	)
else
	giftBootLog("moduleFound", "module", timeRewardsModule:GetFullName(), "class", timeRewardsModule.ClassName)

	local ok, result = pcall(require, timeRewardsModule)
	if not ok then
		warn(
			"[GIFT][ERROR]",
			"Failed to require Time_Rewards module:",
			result,
			"version",
			GIFT_CLIENT_DEBUG_VERSION
		)
	else
		giftBootLog("required", "module", timeRewardsModule:GetFullName(), "resultType", typeof(result))
	end
end
