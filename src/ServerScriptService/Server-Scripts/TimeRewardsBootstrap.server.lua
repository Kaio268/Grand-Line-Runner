local ServerScriptService = game:GetService("ServerScriptService")

local modulesFolder = ServerScriptService:WaitForChild("Modules")
local timeRewardsModule = modulesFolder:WaitForChild("Time_Rewards_Server")

local ok, err = pcall(require, timeRewardsModule)
if not ok then
	warn("[GIFT][ERROR] Failed to bootstrap Time_Rewards_Server:", err)
end
