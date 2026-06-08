local NamiDirectSell = {}

local directSellInFlight = false

local function getEntryInstanceId(entry)
	if typeof(entry) ~= "table" then
		return ""
	end

	local instanceId = tostring(entry.instanceId or entry.representativeInstanceId or "")
	if instanceId ~= "" then
		return instanceId
	end

	if typeof(entry.instanceIds) == "table" then
		for _, rawInstanceId in ipairs(entry.instanceIds) do
			instanceId = tostring(rawInstanceId or "")
			if instanceId ~= "" then
				return instanceId
			end
		end
	end

	return ""
end

local function isCrewEntryKind(context, kind)
	local matcher = context and context.IsCrewItemKind
	if typeof(matcher) == "function" then
		return matcher(kind)
	end

	return kind == (context and context.CrewItemKind or "CrewMember")
end

local function showPopup(context, message, isError)
	local popUpModule = context and context.PopUpModule
	if not popUpModule then
		return
	end

	popUpModule:Local_SendPopUp(
		tostring(message or ""),
		if isError then Color3.fromRGB(255, 104, 104) else Color3.fromRGB(111, 255, 136),
		Color3.fromRGB(0, 0, 0),
		3,
		isError == true
	)
end

local function getResponseMessage(mode, soldCount, failedCount, skippedCount)
	local targetText = if mode == "Hand" then "held crewmate" else "hotbar crewmates"
	if soldCount > 0 then
		if failedCount > 0 or skippedCount > 0 then
			return string.format(
				"Sold %d %s. %d skipped.",
				soldCount,
				if soldCount == 1 then "crewmate" else "crewmates",
				failedCount + skippedCount
			), false
		end

		return string.format(
			"Sold %d %s.",
			soldCount,
			if soldCount == 1 then "crewmate" else "crewmates"
		), false
	end

	if skippedCount > 0 then
		return "No sellable crew found. Non-crew items are not supported by safe selling yet.", true
	end

	return "No sellable " .. targetText .. " found.", true
end

local function collectHotbarSellEntries(context, renderData)
	local entries = {}
	local skipped = 0
	local seenInstanceIds = {}

	for _, slot in ipairs(renderData and renderData.hotbarSlots or {}) do
		local entry = if typeof(slot) == "table" then slot.item else nil
		if typeof(entry) == "table" and entry.emptySlot ~= true and entry.interactive ~= false then
			local instanceId = getEntryInstanceId(entry)
			if isCrewEntryKind(context, entry.kind) and instanceId ~= "" and seenInstanceIds[instanceId] ~= true then
				seenInstanceIds[instanceId] = true
				entries[#entries + 1] = entry
			elseif entry.kind ~= "CrewQuickSlot" then
				skipped += 1
			end
		end
	end

	return entries, skipped
end

local function collectHandSellEntries(context, renderData)
	local clientRuntime = context and context.ClientRuntime
	local hotbarState = clientRuntime and clientRuntime.HotbarState or {}
	local equippedInstanceId = tostring(hotbarState.EquippedInstanceId or "")
	if equippedInstanceId == "" then
		return {}, 0
	end

	if not isCrewEntryKind(context, hotbarState.EquippedKind) then
		return {}, 1
	end

	for _, slot in ipairs(renderData and renderData.hotbarSlots or {}) do
		local entry = if typeof(slot) == "table" then slot.item else nil
		if typeof(entry) == "table" and getEntryInstanceId(entry) == equippedInstanceId then
			return { entry }, 0
		end
	end

	return {
		{
			kind = context and context.CrewItemKind or "CrewMember",
			instanceId = equippedInstanceId,
		},
	}, 0
end

local function invokeCrewSell(context, entry)
	local clientRuntime = context and context.ClientRuntime
	local getRemote = clientRuntime and clientRuntime.getCrewActionRemote
	local remote = if typeof(getRemote) == "function" then getRemote() else nil
	if not (remote and remote:IsA("RemoteFunction")) then
		return false, "remote_unavailable"
	end

	local instanceId = getEntryInstanceId(entry)
	if instanceId == "" then
		return false, "missing_instance_id"
	end

	local ok, response = pcall(function()
		return remote:InvokeServer({
			Action = "SellEquipped",
			InstanceId = instanceId,
			SlotIndex = tonumber(entry.quickSlotIndex),
		})
	end)
	if not ok then
		return false, tostring(response)
	end
	if typeof(response) ~= "table" then
		return false, "invalid_response"
	end

	return response.Ok == true, tostring(response.Reason or "unknown")
end

local function requestRefresh(context)
	local clientRuntime = context and context.ClientRuntime
	if clientRuntime and clientRuntime.ScheduleInventorySnapshotRequest ~= nil then
		clientRuntime.ScheduleInventorySnapshotRequest("namiDirectSell")
	end

	local scheduleRender = context and context.ScheduleRender
	if typeof(scheduleRender) == "function" then
		task.defer(scheduleRender)
	end
end

function NamiDirectSell.Handle(context, mode)
	mode = if tostring(mode or "") == "Hand" then "Hand" else "Hotbar"
	if directSellInFlight then
		showPopup(context, "Sell already in progress.", true)
		return
	end

	local buildRenderData = context and context.BuildRenderData
	local renderData = if typeof(buildRenderData) == "function" then buildRenderData() else nil
	local entries, skipped
	if mode == "Hand" then
		entries, skipped = collectHandSellEntries(context, renderData)
	else
		entries, skipped = collectHotbarSellEntries(context, renderData)
	end

	if #entries <= 0 then
		local message, isError = getResponseMessage(mode, 0, 0, skipped)
		showPopup(context, message, isError)
		return
	end

	directSellInFlight = true
	task.spawn(function()
		local soldCount = 0
		local failedCount = 0

		for _, entry in ipairs(entries) do
			local ok = invokeCrewSell(context, entry)
			if ok then
				soldCount += 1
			else
				failedCount += 1
			end
		end

		directSellInFlight = false
		requestRefresh(context)

		local message, isError = getResponseMessage(mode, soldCount, failedCount, skipped)
		showPopup(context, message, isError)
	end)
end

return NamiDirectSell
