local ReactModalRegistry = {}

local entries = {}
local pendingOperations = {}
local changedEvent = Instance.new("BindableEvent")
local REACT_MODAL_NAMES = {
	CometMerchant = true,
	Gifts = true,
	Index = true,
	Inventory = true,
	NamiShop = true,
	Quest = true,
	Rebirth = true,
	Settings = true,
	SpeedUpgrade = true,
	Store = true,
}
local SIDE_MENU_MODAL_NAMES = {
	Gifts = true,
	Index = true,
	Inventory = true,
	NamiShop = true,
	Quest = true,
	Rebirth = true,
	Settings = true,
	SpeedUpgrade = true,
	Store = true,
}

local function fireChanged(name)
	changedEvent:Fire(name)
end

local function buildPendingOperation(action, payload)
	return {
		Action = action,
		Payload = payload,
	}
end

local function resolvePendingOperation(operation)
	if typeof(operation) == "table" then
		return tostring(operation.Action or ""), operation.Payload
	end

	return tostring(operation or ""), nil
end

local function closeVisibleSideMenusExcept(exceptName)
	for name, handlers in pairs(entries) do
		if name ~= exceptName
			and SIDE_MENU_MODAL_NAMES[name] == true
			and typeof(handlers.isVisible) == "function"
			and handlers.isVisible() == true
			and typeof(handlers.close) == "function"
		then
			handlers.close()
			fireChanged(name)
		end
	end
end

function ReactModalRegistry.Register(name, handlers)
	local key = tostring(name or "")
	if key == "" or typeof(handlers) ~= "table" then
		return function() end
	end

	entries[key] = handlers
	fireChanged(key)

	local pendingOperation = pendingOperations[key]
	if pendingOperation then
		pendingOperations[key] = nil
		task.defer(function()
			if entries[key] ~= handlers then
				return
			end

			local action, payload = resolvePendingOperation(pendingOperation)
			if action == "toggle" and typeof(handlers.toggle) == "function" then
				handlers.toggle(payload)
			elseif action == "open" and typeof(handlers.open) == "function" then
				handlers.open(payload)
			end
			fireChanged(key)
		end)
	end

	return function()
		if entries[key] == handlers then
			entries[key] = nil
			fireChanged(key)
		end
	end
end

function ReactModalRegistry.Has(name)
	return entries[tostring(name or "")] ~= nil
end

function ReactModalRegistry.IsReactModal(name)
	return REACT_MODAL_NAMES[tostring(name or "")] == true
end

function ReactModalRegistry.Toggle(name, payload)
	local key = tostring(name or "")
	local entry = entries[key]
	if entry then
		if typeof(entry.toggle) == "function" then
			if SIDE_MENU_MODAL_NAMES[key] == true and ReactModalRegistry.IsVisible(key) ~= true then
				closeVisibleSideMenusExcept(key)
			end
			entry.toggle(payload)
			fireChanged(key)
			return true
		end

		return SIDE_MENU_MODAL_NAMES[key] == true
	end

	if REACT_MODAL_NAMES[key] then
		pendingOperations[key] = buildPendingOperation("toggle", payload)
		return true
	end

	return false
end

function ReactModalRegistry.Open(name, payload)
	local key = tostring(name or "")
	local entry = entries[key]
	if entry then
		if typeof(entry.open) == "function" then
			if SIDE_MENU_MODAL_NAMES[key] == true then
				closeVisibleSideMenusExcept(key)
			end
			entry.open(payload)
			fireChanged(key)
			return true
		end

		return SIDE_MENU_MODAL_NAMES[key] == true
	end

	if REACT_MODAL_NAMES[key] then
		pendingOperations[key] = buildPendingOperation("open", payload)
		return true
	end

	return false
end

function ReactModalRegistry.Close(name)
	local key = tostring(name or "")
	local entry = entries[key]
	if entry and typeof(entry.close) == "function" then
		entry.close()
		fireChanged(key)
		return true
	end

	if REACT_MODAL_NAMES[key] then
		pendingOperations[key] = nil
		return true
	end

	return false
end

function ReactModalRegistry.IsVisible(name)
	local entry = entries[tostring(name or "")]
	if entry and typeof(entry.isVisible) == "function" then
		return entry.isVisible() == true
	end

	return false
end

function ReactModalRegistry.IsAnyVisible()
	for _, handlers in pairs(entries) do
		if typeof(handlers.isVisible) == "function" and handlers.isVisible() == true then
			return true
		end
	end

	return false
end

function ReactModalRegistry.GetChangedSignal()
	return changedEvent.Event
end

return ReactModalRegistry
