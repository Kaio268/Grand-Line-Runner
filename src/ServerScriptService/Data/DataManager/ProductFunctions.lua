local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Modules.Types)
local CrewQuickSlotService = require(script.Parent.Parent.Parent.Modules.CrewQuickSlotService)
local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization"))

local function DisabledDeveloperProduct(receiptInfo, player, _profile, _DataManager: Types.DataManager)
	local productId = tonumber(receiptInfo and receiptInfo.ProductId)
	local status, metadata = MonetizationConfig.GetDeveloperProductStatus(productId)
	local reason = metadata and metadata.Reason or "not_active_chefs_product"

	warn(string.format(
		"[ProductFunctions] Disabled/non-GTR developer product receipt consumed without grant player=%s userId=%s productId=%s status=%s reason=%s",
		player and player.Name or "<unknown>",
		tostring(player and player.UserId or "<unknown>"),
		tostring(productId),
		tostring(status),
		tostring(reason)
	))
end

local handlers = {}

for _, productId in ipairs(MonetizationConfig.GetDisabledDeveloperProductIds()) do
	handlers[productId] = DisabledDeveloperProduct
end

local crewQuickSlotProductId = tonumber(CrewQuickSlotConfig.ProductId)
if crewQuickSlotProductId and crewQuickSlotProductId > 0 then
	if not MonetizationConfig.IsActiveDeveloperProduct(crewQuickSlotProductId) then
		warn(string.format(
			"[ProductFunctions] Crew quick slot product id=%s is not marked active in Monetization config",
			tostring(crewQuickSlotProductId)
		))
	end

	handlers[crewQuickSlotProductId] = function(receiptInfo, player, _profile, DataManager: Types.DataManager)
		local ok, result = CrewQuickSlotService.ProcessUnlockReceipt(player, receiptInfo.ProductId, DataManager, receiptInfo)
		if ok ~= true then
			error("quick_slot_product_unlock_failed:" .. tostring(result and result.Reason or "unknown_error"))
		end
	end
end

return handlers
