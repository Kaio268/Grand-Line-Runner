-- Crew-facing alias to the quick-slot product config.
local CrewQuickSlots = {}

CrewQuickSlots.DefaultUnlockedSlots = 2
CrewQuickSlots.MaxSlots = 8
CrewQuickSlots.ProductId = 3584712420
CrewQuickSlots.PriceRobux = 49

function CrewQuickSlots.ClampUnlockedSlots(value)
	return math.clamp(
		math.floor(tonumber(value) or CrewQuickSlots.DefaultUnlockedSlots),
		CrewQuickSlots.DefaultUnlockedSlots,
		CrewQuickSlots.MaxSlots
	)
end

function CrewQuickSlots.GetSlotProduct(slotIndex)
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
