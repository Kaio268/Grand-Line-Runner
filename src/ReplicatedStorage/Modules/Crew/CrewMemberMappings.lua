local CrewMembers = require(script.Parent:WaitForChild("CrewMembers"))

local CrewMemberMappings = {}

-- Legacy saved reward IDs still live in player profiles for now. This mapping
-- lets old storage/reward keys resolve to production Crew names and models.
CrewMemberMappings.LegacyIdToCrewMember = CrewMembers.GetLegacyIdMappings()

return CrewMemberMappings
