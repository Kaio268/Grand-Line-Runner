local GiftsViewBridge = {}

local refs = nil
local changedEvent = Instance.new("BindableEvent")

function GiftsViewBridge.SetRefs(nextRefs)
	refs = nextRefs
	changedEvent:Fire(refs)
end

function GiftsViewBridge.ClearRefs()
	refs = nil
	changedEvent:Fire(nil)
end

function GiftsViewBridge.GetRefs()
	return refs
end

function GiftsViewBridge.WaitForRefs(timeoutSeconds)
	local timeoutAt = os.clock() + (timeoutSeconds or 5)
	while refs == nil and os.clock() < timeoutAt do
		changedEvent.Event:Wait()
	end
	return refs
end

return GiftsViewBridge
