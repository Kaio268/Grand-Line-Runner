local service = require(game.ServerScriptService.Modules:WaitForChild("CometMerchant"))
local add = require(script.Parent.Parent.Modules.AddCrewMember)

service:SetRewardHandler("Pot Hotspot", function(player, amount, DataManager, info)
	add:AddCrewMember(player, "Pot Hotspot", 1)
end)

service:SetRewardHandler("Tirilikalika Tirilikalako", function(player, amount, DataManager, info)
	add:AddCrewMember(player, "Tirilikalika Tirilikalako", 1)
end)

service:SetRewardHandler("Rhino Toasterino", function(player, amount, DataManager, info)
	add:AddCrewMember(player, "Rhino Toasterino", 1)
end)
