local QuestSignals = {}

local objectiveRecorded = Instance.new("BindableEvent")
local LEGACY_OBJECTIVE_TYPES = {
	EarnDoubloons = "EarnBeli",
}

QuestSignals.ObjectiveRecorded = objectiveRecorded.Event

function QuestSignals.Record(player, objectiveType, amount, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	local normalizedType = LEGACY_OBJECTIVE_TYPES[tostring(objectiveType or "")] or tostring(objectiveType or "")

	objectiveRecorded:Fire(player, {
		Type = normalizedType,
		Amount = math.max(1, math.floor(tonumber(amount) or 1)),
		Context = if typeof(context) == "table" then table.clone(context) else {},
		RecordedAt = os.time(),
	})
end

return QuestSignals
