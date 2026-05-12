local CrewMemberLegacyStatus = {}

local RETIRED_REASON = "legacy_status_tooling_retired"

function CrewMemberLegacyStatus.Build(_player)
	return {
		Retired = true,
		Reason = RETIRED_REASON,
		Summary = "CrewMember legacy status canaries are retired; canonical CrewMember data is the only active path.",
	}
end

function CrewMemberLegacyStatus.Print(player)
	local status = CrewMemberLegacyStatus.Build(player)
	print("[CrewLegacyStatus] " .. status.Summary)
	return status, status.Summary
end

return CrewMemberLegacyStatus
