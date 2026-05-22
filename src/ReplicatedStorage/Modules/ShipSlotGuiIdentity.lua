local ShipSlotGuiIdentity = {}

ShipSlotGuiIdentity.RuntimeGuiAttribute = "ShipSlotRuntimeGui"
ShipSlotGuiIdentity.SlotNumberAttribute = "ShipSlotNumber"
ShipSlotGuiIdentity.RuntimeGuiNamePrefix = "ShipSlotLevelUp_"

local function normalizeSlotNumber(value)
	local numberValue = tonumber(value)
	if not numberValue or numberValue ~= numberValue or numberValue == math.huge or numberValue == -math.huge then
		return nil
	end

	numberValue = math.floor(numberValue)
	if numberValue < 1 then
		return nil
	end

	return numberValue
end

function ShipSlotGuiIdentity.NormalizeSlotNumber(value)
	return normalizeSlotNumber(value)
end

function ShipSlotGuiIdentity.NormalizeSlotKey(value)
	local slotNumber = normalizeSlotNumber(value)
	return if slotNumber then tostring(slotNumber) else nil
end

function ShipSlotGuiIdentity.GetRuntimeGuiName(slotNumber)
	local slotKey = ShipSlotGuiIdentity.NormalizeSlotKey(slotNumber)
	return if slotKey then ShipSlotGuiIdentity.RuntimeGuiNamePrefix .. slotKey else nil
end

local function isSurfaceGui(gui)
	return typeof(gui) == "Instance" and gui:IsA("SurfaceGui")
end

function ShipSlotGuiIdentity.IsRuntimeShipSlotGui(gui)
	return isSurfaceGui(gui)
		and gui:GetAttribute(ShipSlotGuiIdentity.RuntimeGuiAttribute) == true
		and ShipSlotGuiIdentity.NormalizeSlotNumber(gui:GetAttribute(ShipSlotGuiIdentity.SlotNumberAttribute)) ~= nil
end

function ShipSlotGuiIdentity.IsLegacyNumericSlotGui(gui)
	return isSurfaceGui(gui) and ShipSlotGuiIdentity.NormalizeSlotNumber(gui.Name) ~= nil
end

function ShipSlotGuiIdentity.GetSlotNumberFromGui(gui)
	if not isSurfaceGui(gui) then
		return nil
	end

	if gui:GetAttribute(ShipSlotGuiIdentity.RuntimeGuiAttribute) == true then
		return ShipSlotGuiIdentity.NormalizeSlotNumber(gui:GetAttribute(ShipSlotGuiIdentity.SlotNumberAttribute))
	end

	return ShipSlotGuiIdentity.NormalizeSlotNumber(gui.Name)
end

function ShipSlotGuiIdentity.GetSlotKeyFromGui(gui)
	local slotNumber = ShipSlotGuiIdentity.GetSlotNumberFromGui(gui)
	return if slotNumber then tostring(slotNumber) else nil
end

function ShipSlotGuiIdentity.IsSlotGui(gui)
	return ShipSlotGuiIdentity.GetSlotNumberFromGui(gui) ~= nil
end

return ShipSlotGuiIdentity
