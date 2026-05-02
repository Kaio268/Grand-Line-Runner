local ServerScriptService = game:GetService("ServerScriptService")

local BOOTSTRAP_DEBUG = true

local function bootstrapLog(...)
	if BOOTSTRAP_DEBUG then
		print("[GIFT][CLAIM][SERVER]", ...)
	end
end

bootstrapLog("bootstrapStart", "script", script:GetFullName())

local modulesFolder = ServerScriptService:WaitForChild("Modules")
bootstrapLog("bootstrapModulesFound", "modules", modulesFolder:GetFullName())

local timeRewardsModule = modulesFolder:WaitForChild("Time_Rewards_Server")
bootstrapLog("bootstrapModuleFound", "module", timeRewardsModule:GetFullName(), "class", timeRewardsModule.ClassName)

local ok, result = pcall(require, timeRewardsModule)
if not ok then
	warn("[GIFT][ERROR] Failed to bootstrap Time_Rewards_Server:", result)
else
	bootstrapLog("bootstrapRequireResult", "ok", tostring(ok), "resultType", typeof(result))
end
