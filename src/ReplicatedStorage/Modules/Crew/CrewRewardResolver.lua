local CrewCatalog = require(script.Parent:WaitForChild("CrewCatalog"))
local CrewMembers = require(script.Parent:WaitForChild("CrewMembers"))

local CrewRewardResolver = {}

local GENERIC_UNRESOLVED_DISPLAY = "Crewmate Reward"
local PENDING_HIGH_TIER_DISPLAY = "High-Tier Crew Reward Pending"

local PENDING_HIGH_TIER_REWARDS = {
	["Dragon Cannelloni"] = true,
	["Pakrahmatmatina"] = true,
	["Pot Hotspot"] = true,
}

local APPROVED_REPLACEMENT_ALIASES = {
	["Odin Din Din Dun"] = "Rubber Captain",
	["Pandaccini Bananini"] = "Tide Monk",
	["Tirilikalika Tirilikalako"] = "Tide Monk",
}

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function pushCandidate(candidates, value)
	if typeof(value) == "string" then
		local candidate = trim(value)
		if candidate ~= "" then
			table.insert(candidates, candidate)
		end
	end
end

local function cloneEntry(entry)
	return if entry then table.clone(entry) else nil
end

local function findProductionEntry(rawName)
	local name = trim(rawName)
	if name == "" then
		return nil, "empty_reward_name"
	end
	if PENDING_HIGH_TIER_REWARDS[name] == true then
		return nil, "pending_high_tier_crew_replacement"
	end
	name = APPROVED_REPLACEMENT_ALIASES[name] or name

	local direct = CrewMembers.GetByCrewMemberId(name)
		or CrewMembers.GetByDisplayName(name)
		or CrewMembers.GetByRealCharacterName(name)

	if direct then
		return direct, nil, "Normal", name
	end

	local variantKey, baseName = CrewCatalog.ParseVariantId(name)
	if variantKey ~= "Normal" then
		local baseEntry = CrewMembers.GetByCrewMemberId(baseName)
			or CrewMembers.GetByDisplayName(baseName)
			or CrewMembers.GetByRealCharacterName(baseName)

		if baseEntry then
			return baseEntry, nil, variantKey, baseName
		end
	end

	return nil, "unmapped_crew_reward", "Normal", name
end

local function getCandidates(input, config)
	local candidates = {}

	if typeof(input) == "table" then
		config = input
	else
		pushCandidate(candidates, input)
	end

	if typeof(config) == "table" then
		pushCandidate(candidates, config.CrewMemberId)
		pushCandidate(candidates, config.CrewMemberName)
		pushCandidate(candidates, config.DisplayName)
		pushCandidate(candidates, config.Display_name)
		pushCandidate(candidates, config.RewardName)
		pushCandidate(candidates, config.Name)
	end

	return candidates
end

local function buildResolved(entry, variantKey, inputName, sourceName)
	local displayName = tostring(entry.DisplayName or entry.CrewMemberId or inputName)
	local legacyId = tostring(entry.LegacyId or "")
	local crewMemberId = tostring(entry.CrewMemberId or displayName)
	local grantName = crewMemberId
	local resolvedDisplayName = displayName

	if variantKey ~= "Normal" then
		grantName = CrewCatalog.MakeVariantId(crewMemberId, variantKey)
		resolvedDisplayName = CrewCatalog.MakeVariantId(displayName, variantKey)
	end

	return {
		Resolved = true,
		InputName = inputName,
		SourceName = sourceName or inputName,
		GrantName = grantName,
		DisplayName = resolvedDisplayName,
		BaseDisplayName = displayName,
		CrewMemberId = crewMemberId,
		LegacyId = legacyId,
		ModelName = entry.ModelName,
		Rarity = entry.Rarity,
		Variant = variantKey,
		Entry = cloneEntry(entry),
	}
end

function CrewRewardResolver.Resolve(input, config)
	local candidates = getCandidates(input, config)

	for _, candidate in ipairs(candidates) do
		local entry, reason, variantKey, sourceName = findProductionEntry(candidate)
		if entry then
			return buildResolved(entry, variantKey, candidate, sourceName)
		end
		if reason == "pending_high_tier_crew_replacement" then
			return {
				Resolved = false,
				InputName = candidate,
				DisplayName = PENDING_HIGH_TIER_DISPLAY,
				Reason = reason,
			}
		end
		if reason == "empty_reward_name" then
			return {
				Resolved = false,
				InputName = candidate,
				DisplayName = GENERIC_UNRESOLVED_DISPLAY,
				Reason = reason,
			}
		end
	end

	local inputName = if typeof(input) == "string" then trim(input) else ""
	return {
		Resolved = false,
		InputName = inputName,
		DisplayName = GENERIC_UNRESOLVED_DISPLAY,
		Reason = "unmapped_crew_reward",
	}
end

function CrewRewardResolver.GetDisplayName(input, config)
	local resolved = CrewRewardResolver.Resolve(input, config)
	return resolved.DisplayName, resolved
end

function CrewRewardResolver.IsResolved(input, config)
	local resolved = CrewRewardResolver.Resolve(input, config)
	return resolved.Resolved == true, resolved
end

return CrewRewardResolver
