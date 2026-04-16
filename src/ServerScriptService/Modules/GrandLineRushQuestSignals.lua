local QuestSignals = {}

local objectiveRecorded = Instance.new("BindableEvent")

QuestSignals.ObjectiveRecorded = objectiveRecorded.Event

function QuestSignals.Record(player, objectiveType, amount, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	objectiveRecorded:Fire(player, {
		Type = tostring(objectiveType or ""),
		Amount = math.max(1, math.floor(tonumber(amount) or 1)),
		Context = if typeof(context) == "table" then table.clone(context) else {},
		RecordedAt = os.time(),
	})
end

return QuestSignals
