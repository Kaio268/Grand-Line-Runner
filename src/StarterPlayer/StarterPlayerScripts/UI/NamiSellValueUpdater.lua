local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyUtil = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CurrencyUtil"))

local NamiSellValueUpdater = {}

local boundGuis = setmetatable({}, { __mode = "k" })
local activeContext = nil
local updateQueued = false

local VALUE_PATHS = {
	Inventory = { "SellCard", "Info", "Row1", "Value" },
	Hotbar = { "SellCard", "Info", "Row2", "Value" },
	Hand = { "SellCard", "Info", "Row3", "Value" },
}

local ZERO_VALUES = {
	Inventory = 0,
	Hotbar = 0,
	Hand = 0,
}

local function isTextObject(instance)
	return instance
		and (
			instance:IsA("TextLabel")
			or instance:IsA("TextButton")
			or instance:IsA("TextBox")
		)
end

local function findPath(root, path)
	local current = root
	for _, childName in ipairs(path) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(childName)
	end
	return current
end

local function resolveLabels(gui)
	local labels = {}
	for key, path in pairs(VALUE_PATHS) do
		local label = findPath(gui, path)
		if isTextObject(label) then
			labels[key] = label
		end
	end
	return labels
end

local function cleanNumber(value)
	return math.max(0, math.floor((tonumber(value) or 0) + 0.5))
end

local function formatValue(value)
	return CurrencyUtil.formatCurrency(cleanNumber(value))
end

local function applyValues(values)
	values = values or ZERO_VALUES
	for gui, binding in pairs(boundGuis) do
		if gui and gui.Parent then
			binding.labels = binding.labels or resolveLabels(gui)
			for key, label in pairs(binding.labels) do
				if isTextObject(label) then
					label.Text = formatValue(values[key])
				end
			end
		end
	end
end

local function getEntryInstanceIds(entry)
	local ids = {}
	if typeof(entry) ~= "table" then
		return ids
	end

	if typeof(entry.instanceIds) == "table" then
		local seen = {}
		for _, rawInstanceId in ipairs(entry.instanceIds) do
			local instanceId = tostring(rawInstanceId or "")
			if instanceId ~= "" and seen[instanceId] ~= true then
				seen[instanceId] = true
				ids[#ids + 1] = instanceId
			end
		end
	end

	local instanceId = tostring(entry.instanceId or entry.representativeInstanceId or "")
	if instanceId ~= "" then
		local alreadyIncluded = false
		for _, existingId in ipairs(ids) do
			if existingId == instanceId then
				alreadyIncluded = true
				break
			end
		end
		if not alreadyIncluded then
			ids[#ids + 1] = instanceId
		end
	end

	return ids
end

local function getEntryInstanceCount(entry)
	local ids = getEntryInstanceIds(entry)
	if #ids > 0 then
		if typeof(entry) == "table" and typeof(entry.instanceIds) ~= "table" then
			return math.max(1, cleanNumber(entry.quantity or 1))
		end
		return #ids
	end
	return 0
end

local function isCrewEntry(context, entry)
	if typeof(entry) ~= "table" then
		return false
	end

	local matcher = context and context.IsCrewItemKind
	if typeof(matcher) == "function" then
		return matcher(entry.kind)
	end

	return entry.kind == (context and context.CrewItemKind or "CrewMember")
end

local function getSellValue(context, entry)
	local getter = context and context.GetSellValue
	if typeof(getter) == "function" then
		return cleanNumber(getter(entry))
	end

	return cleanNumber(entry and (entry.SellValue or entry.sellValue) or 0)
end

local function getEntryTotalValue(context, entry)
	if not isCrewEntry(context, entry) or entry.emptySlot == true or entry.interactive == false then
		return 0
	end

	local sellValue = getSellValue(context, entry)
	if sellValue <= 0 then
		return 0
	end

	local count = getEntryInstanceCount(entry)
	if count <= 0 then
		return 0
	end

	return sellValue * count
end

local function getEntryUnitValue(context, entry)
	if not isCrewEntry(context, entry) or entry.emptySlot == true or entry.interactive == false then
		return 0
	end

	if #getEntryInstanceIds(entry) <= 0 then
		return 0
	end

	return getSellValue(context, entry)
end

local function iterateInventoryStates(context, callback)
	local iterator = context and context.ForEachInventoryState
	if typeof(iterator) == "function" then
		iterator(callback)
	end
end

local function buildEntry(context, key, state)
	local builder = context and context.BuildEntry
	if typeof(builder) ~= "function" then
		return nil
	end

	return builder(key, state)
end

local function stateHasInstanceId(state, instanceId)
	if typeof(state) ~= "table" or instanceId == "" then
		return false
	end

	local stateInstanceId = tostring(state.instanceId or state.representativeInstanceId or "")
	if stateInstanceId == instanceId then
		return true
	end

	if typeof(state.instanceIds) == "table" then
		for _, rawInstanceId in ipairs(state.instanceIds) do
			if tostring(rawInstanceId or "") == instanceId then
				return true
			end
		end
	end

	return false
end

local function findEntryByInstanceId(context, instanceId)
	local foundEntry = nil
	iterateInventoryStates(context, function(key, state)
		if foundEntry ~= nil or not stateHasInstanceId(state, instanceId) then
			return
		end
		foundEntry = buildEntry(context, key, state)
	end)
	return foundEntry
end

local function computeInventoryValue(context)
	local total = 0
	iterateInventoryStates(context, function(key, state)
		if
			typeof(state) == "table"
			and isCrewEntry(context, state)
			and cleanNumber(state.qty or 0) > 0
			and state.inventoryState ~= "Equipped"
		then
			total += getEntryTotalValue(context, buildEntry(context, key, state))
		end
	end)
	return total
end

local function addHotbarEntryValue(context, entry, seenInstanceIds)
	if not isCrewEntry(context, entry) or entry.emptySlot == true or entry.interactive == false then
		return 0
	end

	local sellValue = getSellValue(context, entry)
	if sellValue <= 0 then
		return 0
	end

	local total = 0
	local ids = getEntryInstanceIds(entry)
	for _, instanceId in ipairs(ids) do
		if seenInstanceIds[instanceId] ~= true then
			seenInstanceIds[instanceId] = true
			total += sellValue
		end
	end

	return total
end

local function computeHotbarValue(context, renderData)
	local total = 0
	local seenInstanceIds = {}
	for _, slot in ipairs(renderData and renderData.hotbarSlots or {}) do
		local entry = if typeof(slot) == "table" then slot.item else nil
		total += addHotbarEntryValue(context, entry, seenInstanceIds)
	end
	return total
end

local function findHotbarEntryByInstanceId(renderData, instanceId)
	for _, slot in ipairs(renderData and renderData.hotbarSlots or {}) do
		local entry = if typeof(slot) == "table" then slot.item else nil
		for _, entryInstanceId in ipairs(getEntryInstanceIds(entry)) do
			if entryInstanceId == instanceId then
				return entry
			end
		end
	end
	return nil
end

local function computeHandValue(context, renderData)
	local clientRuntime = context and context.ClientRuntime
	local hotbarState = clientRuntime and clientRuntime.HotbarState or {}
	local instanceId = tostring(hotbarState.EquippedInstanceId or "")
	if instanceId == "" then
		return 0
	end

	local entry = findHotbarEntryByInstanceId(renderData, instanceId) or findEntryByInstanceId(context, instanceId)
	if not entry then
		return 0
	end

	return getEntryUnitValue(context, entry)
end

local function computeValues(context, renderData)
	if typeof(context) ~= "table" then
		return ZERO_VALUES
	end

	return {
		Inventory = computeInventoryValue(context),
		Hotbar = computeHotbarValue(context, renderData),
		Hand = computeHandValue(context, renderData),
	}
end

local function hasBoundGui()
	for gui in pairs(boundGuis) do
		if gui and gui.Parent then
			return true
		end
	end
	return false
end

function NamiSellValueUpdater.UpdateFromRenderData(renderData)
	if not hasBoundGui() then
		return
	end

	applyValues(computeValues(activeContext, renderData))
end

function NamiSellValueUpdater.RequestUpdate()
	if updateQueued or not hasBoundGui() then
		return
	end

	updateQueued = true
	task.defer(function()
		updateQueued = false
		local renderData = nil
		local buildRenderData = activeContext and activeContext.BuildRenderData
		if typeof(buildRenderData) == "function" then
			local ok, result = pcall(buildRenderData)
			if ok then
				renderData = result
			end
		end
		NamiSellValueUpdater.UpdateFromRenderData(renderData)
	end)
end

function NamiSellValueUpdater.SetContext(context)
	activeContext = if typeof(context) == "table" then context else nil
	NamiSellValueUpdater.RequestUpdate()
end

function NamiSellValueUpdater.ClearContext(context)
	if context == nil or context == activeContext then
		activeContext = nil
	end
end

function NamiSellValueUpdater.BindGui(gui)
	if not (gui and gui:IsA("ScreenGui")) then
		return gui
	end

	if boundGuis[gui] then
		NamiSellValueUpdater.RequestUpdate()
		return gui
	end

	local binding = {
		labels = resolveLabels(gui),
		connections = {},
	}
	boundGuis[gui] = binding
	applyValues(ZERO_VALUES)

	binding.connections[#binding.connections + 1] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			NamiSellValueUpdater.RequestUpdate()
		end
	end)

	binding.connections[#binding.connections + 1] = gui.Destroying:Connect(function()
		local currentBinding = boundGuis[gui]
		boundGuis[gui] = nil
		if not currentBinding then
			return
		end
		for _, connection in ipairs(currentBinding.connections) do
			connection:Disconnect()
		end
	end)

	if gui.Enabled then
		NamiSellValueUpdater.RequestUpdate()
	end

	return gui
end

return NamiSellValueUpdater
