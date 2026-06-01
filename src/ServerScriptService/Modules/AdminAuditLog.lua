local AdminAuditLog = {}

local MAX_ENTRIES = 100
local entries = {}
local nextId = 0

local function cleanText(value, limit)
	local text = tostring(value or ""):gsub("\r", ""):gsub("\n", " ")
	text = text:match("^%s*(.-)%s*$") or ""
	if limit and #text > limit then
		text = text:sub(1, limit)
	end
	return text
end

function AdminAuditLog.Record(entry)
	entry = if typeof(entry) == "table" then entry else {}
	nextId += 1

	local normalized = {
		Id = nextId,
		Time = math.floor(tonumber(entry.Time) or os.time()),
		ActorUserId = math.floor(tonumber(entry.ActorUserId) or 0),
		ActorName = cleanText(entry.ActorName, 80),
		Action = cleanText(entry.Action, 40),
		TargetUserId = math.floor(tonumber(entry.TargetUserId) or 0),
		TargetName = cleanText(entry.TargetName, 80),
		Result = cleanText(entry.Result, 24),
		Reason = cleanText(entry.Reason, 160),
	}

	table.insert(entries, 1, normalized)
	while #entries > MAX_ENTRIES do
		table.remove(entries)
	end

	print(string.format(
		"[AdminAudit] id=%d action=%s result=%s actor=%s(%d) target=%s(%d) reason=%s",
		normalized.Id,
		normalized.Action,
		normalized.Result,
		normalized.ActorName,
		normalized.ActorUserId,
		normalized.TargetName,
		normalized.TargetUserId,
		normalized.Reason
	))

	return normalized
end

function AdminAuditLog.GetRecent(limit)
	limit = math.clamp(math.floor(tonumber(limit) or 40), 1, MAX_ENTRIES)
	local result = {}
	for index = 1, math.min(limit, #entries) do
		local entry = entries[index]
		result[index] = {
			Id = entry.Id,
			Time = entry.Time,
			ActorUserId = entry.ActorUserId,
			ActorName = entry.ActorName,
			Action = entry.Action,
			TargetUserId = entry.TargetUserId,
			TargetName = entry.TargetName,
			Result = entry.Result,
			Reason = entry.Reason,
		}
	end
	return result
end

return AdminAuditLog
