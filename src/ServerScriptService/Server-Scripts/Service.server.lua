local service = require(game.ServerScriptService.Modules:WaitForChild("CometMerchant"))
local CrewRewardService = require(script.Parent.Parent.Modules.CrewRewardService)

local function grantCometCrewReward(player, rewardName, amount)
	local ok = CrewRewardService.Grant(player, rewardName, amount or 1, {
		Source = "CometMerchant",
		Context = "CometMerchant:" .. tostring(rewardName),
	})
	return ok
end

service:SetRewardHandler("Pot Hotspot", function(player, amount, _DataManager, _info)
	return grantCometCrewReward(player, "Pot Hotspot", amount)
end)

service:SetRewardHandler("Tide Monk", function(player, amount, _DataManager, _info)
	return grantCometCrewReward(player, "Tide Monk", amount)
end)

service:SetRewardHandler("Rhino Toasterino", function(player, amount, _DataManager, _info)
	return grantCometCrewReward(player, "Rhino Toasterino", amount)
end)
