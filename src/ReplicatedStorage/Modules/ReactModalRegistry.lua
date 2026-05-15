local ReactModalRegistry = {}

local entries = {}
local pendingOperations = {}
local changedEvent = Instance.new("BindableEvent")
local REACT_MODAL_NAMES = {
	CometMerchant = true,
	GearStore = true,
	Index = true,
	LimitedReward = true,
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

			if pendingOperation == "toggle" and typeof(handlers.toggle) == "function" then
				handlers.toggle()
			elseif pendingOperation == "open" and typeof(handlers.open) == "function" then
				handlers.open()
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

function ReactModalRegistry.Toggle(name)
	local key = tostring(name or "")
	local entry = entries[key]
	if entry and typeof(entry.toggle) == "function" then
		entry.toggle()
		fireChanged(key)
		return true
	end

	if REACT_MODAL_NAMES[key] then
		pendingOperations[key] = "toggle"
		return true
	end

	return false
end

function ReactModalRegistry.Open(name)
	local key = tostring(name or "")
	local entry = entries[key]
	if entry and typeof(entry.open) == "function" then
		entry.open()
		fireChanged(key)
		return true
	end

	if REACT_MODAL_NAMES[key] then
		pendingOperations[key] = "open"
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

function ReactModalRegistry.GetChangedSignal()
	return changedEvent.Event
end

return ReactModalRegistry
