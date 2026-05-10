local CrewMemberLegacyFallbackTelemetry = {}

local recordsByKey = {}

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneValue(child)
	end
	return copy
end

local function getPlayerFields(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return "server", 0
	end
	return player.Name, player.UserId
end

local function shouldPrint(count)
	return count <= 3 or count == 5 or count == 10 or count % 25 == 0
end

function CrewMemberLegacyFallbackTelemetry.RecordUsage(category, surface, source, player, details)
	details = if typeof(details) == "table" then details else {}

	local categoryName = tostring(category or "legacy_fallback")
	local surfaceName = tostring(surface or categoryName)
	local sourceName = tostring(source or "unknown")
	local playerName, userId = getPlayerFields(player)
	local denied = details.Denied == true
	local key = table.concat({ categoryName, surfaceName, sourceName, tostring(userId), denied and "denied" or "used" }, "|")
	local now = os.time()

	local record = recordsByKey[key]
	if record == nil then
		record = {
			Category = categoryName,
			Surface = surfaceName,
			Source = sourceName,
			PlayerName = playerName,
			UserId = userId,
			FirstTimestamp = now,
			LastTimestamp = now,
			Count = 0,
			DeniedCount = 0,
			LastReason = "",
		}
		recordsByKey[key] = record
	end

	record.Count += 1
	record.LastTimestamp = now
	record.PlayerName = playerName
	record.UserId = userId
	record.LastReason = tostring(details.Reason or record.LastReason or "")
	if denied then
		record.DeniedCount += 1
	end

	if shouldPrint(record.Count) then
		warn(string.format(
			"[CrewMemberLegacyFallbackTelemetry] category=%s surface=%s source=%s player=%s userId=%s denied=%s reason=%s count=%d",
			categoryName,
			surfaceName,
			sourceName,
			playerName,
			tostring(userId),
			tostring(denied),
			record.LastReason,
			record.Count
		))
	end

	return cloneValue(record)
end

function CrewMemberLegacyFallbackTelemetry.GetSnapshot()
	return cloneValue(recordsByKey)
end

function CrewMemberLegacyFallbackTelemetry.GetSummary()
	local summary = {
		TotalCount = 0,
		DeniedCount = 0,
		CategoryCounts = {},
		CategoryDeniedCounts = {},
		SurfaceCounts = {},
		SurfaceDeniedCounts = {},
	}

	for _, record in pairs(recordsByKey) do
		local count = math.max(0, tonumber(record.Count) or 0)
		local deniedCount = math.max(0, tonumber(record.DeniedCount) or 0)
		local category = tostring(record.Category or "legacy_fallback")
		local surface = tostring(record.Surface or category)

		summary.TotalCount += count
		summary.DeniedCount += deniedCount
		summary.CategoryCounts[category] = (summary.CategoryCounts[category] or 0) + count
		summary.CategoryDeniedCounts[category] = (summary.CategoryDeniedCounts[category] or 0) + deniedCount
		summary.SurfaceCounts[surface] = (summary.SurfaceCounts[surface] or 0) + count
		summary.SurfaceDeniedCounts[surface] = (summary.SurfaceDeniedCounts[surface] or 0) + deniedCount
	end

	return summary
end

return CrewMemberLegacyFallbackTelemetry
