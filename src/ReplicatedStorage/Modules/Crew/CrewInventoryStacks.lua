local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewStacking = require(Modules:WaitForChild("Configs"):WaitForChild("CrewStacking"))

local CrewInventoryStacks = {}

local function getInstanceId(instanceId, instanceData)
	local value = ""
	if typeof(instanceData) == "table" then
		value = tostring(instanceData.InstanceId or "")
	end
	if value == "" then
		value = tostring(instanceId or "")
	end
	return value
end

local function compareInstanceIds(a, b)
	local numberA = tonumber(a)
	local numberB = tonumber(b)
	if numberA ~= nil and numberB ~= nil and numberA ~= numberB then
		return numberA < numberB
	end
	return tostring(a) < tostring(b)
end

local function buildOrderedInstanceIds(inventory)
	local ids = {}
	local seen = {}

	if typeof(inventory.Order) == "table" then
		for _, instanceId in ipairs(inventory.Order) do
			local normalized = tostring(instanceId or "")
			if normalized ~= "" and seen[normalized] ~= true then
				seen[normalized] = true
				table.insert(ids, normalized)
			end
		end
	end

	local remaining = {}
	if typeof(inventory.ById) == "table" then
		for instanceId in pairs(inventory.ById) do
			local normalized = tostring(instanceId or "")
			if normalized ~= "" and seen[normalized] ~= true then
				seen[normalized] = true
				table.insert(remaining, normalized)
			end
		end
	end

	table.sort(remaining, compareInstanceIds)
	for _, instanceId in ipairs(remaining) do
		table.insert(ids, instanceId)
	end

	return ids
end

local function resolveCrewMember(instanceData)
	local rawCrewMemberId = tostring(instanceData.CrewMemberId or instanceData.StorageName or "")
	if rawCrewMemberId == "" then
		return nil, nil
	end

	local crewMemberId, info = CrewCatalog.ResolveCrewMemberId(rawCrewMemberId)
	if info then
		return crewMemberId, info
	end

	return rawCrewMemberId, nil
end

local function getStackRarity(instanceData, info)
	local catalogRarity = tostring(info and info.Rarity or "")
	if catalogRarity ~= "" then
		return CrewStacking.NormalizeRarity(catalogRarity)
	end

	return CrewStacking.NormalizeRarity(instanceData and instanceData.Rarity or nil)
end

local function createStack(crewMemberId, rarity, maxQuantity, stackNumber, sortOrder)
	return {
		StackId = string.format("CrewMember|%s|%d", tostring(crewMemberId), stackNumber),
		StackNumber = stackNumber,
		StackOrder = sortOrder,
		CrewMemberId = tostring(crewMemberId),
		Name = tostring(crewMemberId),
		Rarity = rarity,
		Quantity = 0,
		MaxQuantity = maxQuantity,
		InstanceIds = {},
		RepresentativeInstanceId = "",
		Representative = nil,
	}
end

function CrewInventoryStacks.BuildAvailableStacks(inventory)
	local stacks = {}
	if typeof(inventory) ~= "table" or typeof(inventory.ById) ~= "table" then
		return stacks
	end

	local bucketsByCrewMemberId = {}
	local orderedCrewMemberIds = {}

	for _, instanceId in ipairs(buildOrderedInstanceIds(inventory)) do
		local instanceData = inventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == "" then
			local crewMemberId, info = resolveCrewMember(instanceData)
			if crewMemberId then
				local bucket = bucketsByCrewMemberId[crewMemberId]
				if bucket == nil then
					local rarity = getStackRarity(instanceData, info)
					bucket = {
						CrewMemberId = crewMemberId,
						Rarity = rarity,
						MaxQuantity = CrewStacking.GetMaxStackForRarity(rarity),
						Instances = {},
					}
					bucketsByCrewMemberId[crewMemberId] = bucket
					table.insert(orderedCrewMemberIds, crewMemberId)
				end

				local normalizedInstanceId = getInstanceId(instanceId, instanceData)
				table.insert(bucket.Instances, {
					InstanceId = normalizedInstanceId,
					Data = instanceData,
				})
			end
		end
	end

	for _, crewMemberId in ipairs(orderedCrewMemberIds) do
		local bucket = bucketsByCrewMemberId[crewMemberId]
		local stack = nil
		local stackNumber = 0

		for _, instanceRecord in ipairs(bucket.Instances) do
			if stack == nil or stack.Quantity >= stack.MaxQuantity then
				stackNumber += 1
				stack = createStack(
					bucket.CrewMemberId,
					bucket.Rarity,
					bucket.MaxQuantity,
					stackNumber,
					#stacks + 1
				)
				table.insert(stacks, stack)
			end

			stack.Quantity += 1
			table.insert(stack.InstanceIds, instanceRecord.InstanceId)
			if stack.RepresentativeInstanceId == "" then
				stack.RepresentativeInstanceId = instanceRecord.InstanceId
				stack.Representative = table.clone(instanceRecord.Data)
				stack.Representative.InstanceId = instanceRecord.InstanceId
			end
		end
	end

	return stacks
end

function CrewInventoryStacks.BuildAvailableCounts(inventory)
	local counts = {}
	local representatives = {}

	for _, stack in ipairs(CrewInventoryStacks.BuildAvailableStacks(inventory)) do
		counts[stack.CrewMemberId] = (counts[stack.CrewMemberId] or 0) + stack.Quantity
		if representatives[stack.CrewMemberId] == nil then
			representatives[stack.CrewMemberId] = stack.Representative
		end
	end

	return counts, representatives
end

function CrewInventoryStacks.CalculateIncomingFitFromStacks(stacks, crewMemberId, amount, unlockedSlots)
	local requested = math.max(0, math.floor(tonumber(amount) or 0))
	local unlocked = math.max(0, math.floor(tonumber(unlockedSlots) or 0))
	local canonicalCrewMemberId, info = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	stacks = if typeof(stacks) == "table" then stacks else {}
	local occupied = #stacks

	if requested <= 0 then
		return {
			Allowed = true,
			Reason = "empty_request",
			CrewMemberId = canonicalCrewMemberId,
			Requested = requested,
			OccupiedStacks = occupied,
			UnlockedSlots = unlocked,
			RequiredNewStacks = 0,
			ExistingRoom = 0,
			MaxQuantity = 0,
		}
	end

	if not info then
		return {
			Allowed = false,
			Reason = "unknown_crew_member",
			CrewMemberId = tostring(crewMemberId or ""),
			Requested = requested,
			OccupiedStacks = occupied,
			UnlockedSlots = unlocked,
			RequiredNewStacks = 0,
			ExistingRoom = 0,
			MaxQuantity = CrewStacking.DefaultMaxStack,
		}
	end

	local maxQuantity = CrewStacking.GetMaxStackForCrewMemberId(canonicalCrewMemberId)
	local existingRoom = 0
	for _, stack in ipairs(stacks) do
		if stack.CrewMemberId == canonicalCrewMemberId then
			existingRoom += math.max(0, stack.MaxQuantity - stack.Quantity)
		end
	end

	local overflow = math.max(0, requested - existingRoom)
	local requiredNewStacks = if overflow > 0 then math.ceil(overflow / maxQuantity) else 0
	local totalAfter = occupied + requiredNewStacks

	return {
		Allowed = totalAfter <= unlocked,
		Reason = if totalAfter <= unlocked then "ok" else "crew_stack_capacity_full",
		CrewMemberId = canonicalCrewMemberId,
		Requested = requested,
		OccupiedStacks = occupied,
		UnlockedSlots = unlocked,
		RequiredNewStacks = requiredNewStacks,
		ExistingRoom = existingRoom,
		MaxQuantity = maxQuantity,
		TotalStacksAfter = totalAfter,
	}
end

function CrewInventoryStacks.CalculateIncomingFit(inventory, crewMemberId, amount, unlockedSlots)
	return CrewInventoryStacks.CalculateIncomingFitFromStacks(
		CrewInventoryStacks.BuildAvailableStacks(inventory),
		crewMemberId,
		amount,
		unlockedSlots
	)
end

local function cloneStackStates(stacks)
	local stackStates = {}
	for _, stack in ipairs(stacks) do
		table.insert(stackStates, {
			CrewMemberId = stack.CrewMemberId,
			Quantity = stack.Quantity,
			MaxQuantity = stack.MaxQuantity,
		})
	end
	return stackStates
end

local function applyGrantToStackStates(stackStates, crewMemberId, amount)
	local requested = math.max(0, math.floor(tonumber(amount) or 0))
	if requested <= 0 then
		return true, "empty_request", nil
	end

	local canonicalCrewMemberId, info = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	if not info then
		return false, "unknown_crew_member", tostring(crewMemberId or "")
	end

	local maxQuantity = CrewStacking.GetMaxStackForCrewMemberId(canonicalCrewMemberId)
	local remaining = requested
	for _, stack in ipairs(stackStates) do
		if stack.CrewMemberId == canonicalCrewMemberId and stack.Quantity < stack.MaxQuantity then
			local added = math.min(remaining, stack.MaxQuantity - stack.Quantity)
			stack.Quantity += added
			remaining -= added
			if remaining <= 0 then
				return true, "ok", canonicalCrewMemberId
			end
		end
	end

	while remaining > 0 do
		local added = math.min(remaining, maxQuantity)
		table.insert(stackStates, {
			CrewMemberId = canonicalCrewMemberId,
			Quantity = added,
			MaxQuantity = maxQuantity,
		})
		remaining -= added
	end

	return true, "ok", canonicalCrewMemberId
end

function CrewInventoryStacks.CalculateBatchFitFromStacks(stacks, grants, unlockedSlots)
	local unlocked = math.max(0, math.floor(tonumber(unlockedSlots) or 0))
	local currentStacks = if typeof(stacks) == "table" then stacks else {}
	local stackStates = cloneStackStates(currentStacks)
	local occupiedBefore = #stackStates
	local requested = 0

	if typeof(grants) ~= "table" then
		grants = {}
	end

	for _, grant in ipairs(grants) do
		local crewMemberId = tostring((grant and (grant.CrewMemberId or grant.Name)) or "")
		local amount = math.max(0, math.floor(tonumber(grant and (grant.Amount or grant.Quantity)) or 0))
		requested += amount
		local ok, reason, resolvedCrewMemberId = applyGrantToStackStates(stackStates, crewMemberId, amount)
		if not ok then
			return {
				Allowed = false,
				Reason = reason,
				CrewMemberId = resolvedCrewMemberId,
				Requested = requested,
				OccupiedStacks = occupiedBefore,
				UnlockedSlots = unlocked,
				RequiredNewStacks = 0,
				TotalStacksAfter = occupiedBefore,
			}
		end
	end

	local occupiedAfter = #stackStates
	return {
		Allowed = occupiedAfter <= unlocked,
		Reason = if occupiedAfter <= unlocked then "ok" else "crew_stack_capacity_full",
		Requested = requested,
		OccupiedStacks = occupiedBefore,
		UnlockedSlots = unlocked,
		RequiredNewStacks = math.max(0, occupiedAfter - occupiedBefore),
		TotalStacksAfter = occupiedAfter,
	}
end

function CrewInventoryStacks.CalculateBatchFit(inventory, grants, unlockedSlots)
	return CrewInventoryStacks.CalculateBatchFitFromStacks(
		CrewInventoryStacks.BuildAvailableStacks(inventory),
		grants,
		unlockedSlots
	)
end

return CrewInventoryStacks
