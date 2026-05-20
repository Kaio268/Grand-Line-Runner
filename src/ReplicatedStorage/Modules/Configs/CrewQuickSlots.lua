-- Crew-facing quick-slot capacity config.
local CrewQuickSlots = {}

CrewQuickSlots.MaxSlots = 8
CrewQuickSlots.DefaultUnlockedSlots = CrewQuickSlots.MaxSlots
CrewQuickSlots.ProductId = 0
CrewQuickSlots.PriceRobux = 0
CrewQuickSlots.PaidUnlocksEnabled = false
CrewQuickSlots.RetiredProductIds = {
	[3584712420] = true,
}

function CrewQuickSlots.ClampUnlockedSlots(value)
	return math.clamp(
		math.floor(tonumber(value) or CrewQuickSlots.DefaultUnlockedSlots),
		CrewQuickSlots.DefaultUnlockedSlots,
		CrewQuickSlots.MaxSlots
	)
end

function CrewQuickSlots.GetSlotProduct(slotIndex)
	if CrewQuickSlots.PaidUnlocksEnabled ~= true then
		return nil
	end

	slotIndex = tonumber(slotIndex)
	if not slotIndex or slotIndex <= CrewQuickSlots.DefaultUnlockedSlots or slotIndex > CrewQuickSlots.MaxSlots then
		return nil
	end

	return {
		ProductId = CrewQuickSlots.ProductId,
		Price = CrewQuickSlots.PriceRobux,
		PriceRobux = CrewQuickSlots.PriceRobux,
	}
end

function CrewQuickSlots.IsUnlockProduct(productId)
	local configuredProductId = tonumber(CrewQuickSlots.ProductId)
	return configuredProductId ~= nil
		and configuredProductId > 0
		and tonumber(productId) == configuredProductId
end

function CrewQuickSlots.IsRetiredUnlockProduct(productId)
	local retiredProductId = tonumber(productId)
	return retiredProductId ~= nil and CrewQuickSlots.RetiredProductIds[retiredProductId] == true
end

function CrewQuickSlots.GetNextLockedSlot(unlockedSlots)
	local unlocked = CrewQuickSlots.ClampUnlockedSlots(unlockedSlots)
	if unlocked >= CrewQuickSlots.MaxSlots then
		return nil
	end
	return unlocked + 1
end

function CrewQuickSlots.GetDefaults()
	return {
		UnlockedSlots = CrewQuickSlots.DefaultUnlockedSlots,
		MaxSlots = CrewQuickSlots.MaxSlots,
	}
end

return CrewQuickSlots
