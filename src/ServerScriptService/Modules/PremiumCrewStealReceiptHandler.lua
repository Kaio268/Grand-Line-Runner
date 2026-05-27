local ServerScriptService = game:GetService("ServerScriptService")

local PremiumCrewStealService = require(ServerScriptService.Modules:WaitForChild("PremiumCrewStealService"))

local PremiumCrewStealReceiptHandler = {}

function PremiumCrewStealReceiptHandler.ProcessReceipt(receiptInfo, player, profile, dataManager)
	return PremiumCrewStealService.ProcessReceipt(receiptInfo, player, profile, dataManager)
end

return PremiumCrewStealReceiptHandler
