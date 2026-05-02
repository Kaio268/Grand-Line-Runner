local BrainrotQuickSlots = {}

BrainrotQuickSlots.DefaultUnlockedSlots = 2
BrainrotQuickSlots.MaxSlots = 8
BrainrotQuickSlots.ProductId = 3584712420 -- Replace with the real "+1 Brainrot Quick Slot" Developer Product ID.
BrainrotQuickSlots.PriceRobux = 49

function BrainrotQuickSlots.ClampUnlockedSlots(value)
	return math.clamp(
		math.floor(tonumber(value) or BrainrotQuickSlots.DefaultUnlockedSlots),
		BrainrotQuickSlots.DefaultUnlockedSlots,
		BrainrotQuickSlots.MaxSlots
	)
end

function BrainrotQuickSlots.GetSlotProduct(slotIndex)
	slotIndex = tonumber(slotIndex)
	if not slotIndex or slotIndex <= BrainrotQuickSlots.DefaultUnlockedSlots or slotIndex > BrainrotQuickSlots.MaxSlots then
		return nil
	end

	return {
		ProductId = BrainrotQuickSlots.ProductId,
		Price = BrainrotQuickSlots.PriceRobux,
		PriceRobux = BrainrotQuickSlots.PriceRobux,
	}
end

function BrainrotQuickSlots.IsUnlockProduct(productId)
	local configuredProductId = tonumber(BrainrotQuickSlots.ProductId)
	return configuredProductId ~= nil
		and configuredProductId > 0
		and tonumber(productId) == configuredProductId
end

function BrainrotQuickSlots.GetNextLockedSlot(unlockedSlots)
	local unlocked = BrainrotQuickSlots.ClampUnlockedSlots(unlockedSlots)
	if unlocked >= BrainrotQuickSlots.MaxSlots then
		return nil
	end
	return unlocked + 1
end

function BrainrotQuickSlots.GetDefaults()
	return {
		UnlockedSlots = BrainrotQuickSlots.DefaultUnlockedSlots,
		MaxSlots = BrainrotQuickSlots.MaxSlots,
	}
end

return BrainrotQuickSlots
