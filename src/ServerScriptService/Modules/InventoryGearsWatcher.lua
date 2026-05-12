local Module = {}

local didWarn = false

function Module.Start()
	if didWarn then
		return
	end

	didWarn = true
	warn("[InventoryGearsWatcher] Deprecated no-op. InventorySystemServer owns InventoryGearRemote updates.")
end

return Module
