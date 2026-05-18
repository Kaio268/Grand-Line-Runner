local ReactNpcDialogService = {}

local changedEvent = Instance.new("BindableEvent")
local activeDialog = nil

local function fireChanged()
	changedEvent:Fire(activeDialog)
end

function ReactNpcDialogService.Open(dialog)
	if typeof(dialog) ~= "table" then
		return nil
	end

	activeDialog = {
		title = tostring(dialog.title or ""),
		message = tostring(dialog.message or ""),
		responses = table.clone(dialog.responses or {}),
		onRespond = dialog.onRespond,
	}
	fireChanged()
	return activeDialog
end

function ReactNpcDialogService.Close(dialog)
	if dialog ~= nil and dialog ~= activeDialog then
		return false
	end

	if activeDialog == nil then
		return false
	end

	activeDialog = nil
	fireChanged()
	return true
end

function ReactNpcDialogService.Respond(index)
	local dialog = activeDialog
	if dialog == nil then
		return false
	end

	local responseIndex = math.floor(tonumber(index) or 0)
	if responseIndex < 1 or responseIndex > #dialog.responses then
		return false
	end

	activeDialog = nil
	fireChanged()

	if typeof(dialog.onRespond) == "function" then
		dialog.onRespond(responseIndex)
	end

	return true
end

function ReactNpcDialogService.GetActiveDialog()
	return activeDialog
end

function ReactNpcDialogService.GetChangedSignal()
	return changedEvent.Event
end

return ReactNpcDialogService
