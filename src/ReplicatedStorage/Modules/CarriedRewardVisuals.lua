local CarriedRewardVisuals = {}

CarriedRewardVisuals.DefaultSpacing = 1.35

local function isOccupied(item)
	if typeof(item) ~= "table" then
		return false
	end

	if item.Occupied == true then
		return true
	end

	return typeof(item.CarryId) == "string" and item.CarryId ~= ""
end

local function getSortOrder(item)
	local carryOrder = tonumber(item.CarryOrder)
	if carryOrder ~= nil then
		return carryOrder
	end

	return math.huge
end

local function getSlotIndex(item)
	return math.max(0, math.floor(tonumber(item and item.SlotIndex) or 0))
end

function CarriedRewardVisuals.GetLateralOffsets(count, spacing)
	count = math.max(0, math.floor(tonumber(count) or 0))
	spacing = math.max(0, tonumber(spacing) or CarriedRewardVisuals.DefaultSpacing)

	local offsets = {}
	if count <= 0 then
		return offsets
	end

	local centerIndex = (count + 1) / 2
	for index = 1, count do
		offsets[index] = (index - centerIndex) * spacing
	end

	return offsets
end

function CarriedRewardVisuals.GetOrderedItems(items)
	local ordered = {}
	if typeof(items) ~= "table" then
		return ordered
	end

	for _, item in ipairs(items) do
		if isOccupied(item) then
			ordered[#ordered + 1] = item
		end
	end

	table.sort(ordered, function(left, right)
		local leftOrder = getSortOrder(left)
		local rightOrder = getSortOrder(right)
		if leftOrder ~= rightOrder then
			return leftOrder < rightOrder
		end

		local leftSlot = getSlotIndex(left)
		local rightSlot = getSlotIndex(right)
		if leftSlot ~= rightSlot then
			return leftSlot < rightSlot
		end

		return tostring(left.CarryId or "") < tostring(right.CarryId or "")
	end)

	return ordered
end

function CarriedRewardVisuals.BuildOffsetMap(items, spacing)
	local ordered = CarriedRewardVisuals.GetOrderedItems(items)
	local offsets = CarriedRewardVisuals.GetLateralOffsets(#ordered, spacing)
	local offsetMap = {}

	for index, item in ipairs(ordered) do
		local offset = offsets[index] or 0
		if typeof(item.CarryId) == "string" and item.CarryId ~= "" then
			offsetMap[item.CarryId] = offset
		end
		if item.SlotIndex ~= nil then
			offsetMap[tostring(item.SlotIndex)] = offset
		end
	end

	return offsetMap, ordered
end

function CarriedRewardVisuals.GetOffsetForItem(items, item, spacing)
	if typeof(item) ~= "table" then
		return 0
	end

	local offsetMap = CarriedRewardVisuals.BuildOffsetMap(items, spacing)
	if typeof(item.CarryId) == "string" and item.CarryId ~= "" then
		local carryOffset = offsetMap[item.CarryId]
		if typeof(carryOffset) == "number" then
			return carryOffset
		end
	end

	local slotOffset = offsetMap[tostring(item.SlotIndex or "")]
	return if typeof(slotOffset) == "number" then slotOffset else 0
end

return CarriedRewardVisuals
