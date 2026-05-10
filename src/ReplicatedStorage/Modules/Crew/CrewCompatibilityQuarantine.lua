local CrewCompatibilityQuarantine = {}

local COMPATIBILITY_ONLY = {
	["67"] = {
		Disposition = "quarantine_dev_canary",
		Reason = "Legacy canary/sample id with no production CrewMember mapping; keep explicit until dev profiles are reset or reward config is retargeted.",
		RetirementAction = "clean_dev_index_or_retarget_reward",
	},
	["Balerina Capucina"] = {
		Disposition = "quarantine_reward_legacy",
		Reason = "Legacy time reward crew with no confirmed production CrewMember identity or model mapping.",
		RetirementAction = "choose_reward_mapping_or_rebuild_dev_profiles",
	},
	["Mateo"] = {
		Disposition = "quarantine_legacy_inventory",
		Reason = "Legacy-only inventory/catalog row with no confirmed production CrewMember identity.",
		RetirementAction = "clean_dev_inventory_or_choose_mapping",
	},
	["Pipi Kiwi"] = {
		Disposition = "quarantine_legacy_inventory",
		Reason = "Legacy-only inventory/catalog row with no confirmed production CrewMember identity.",
		RetirementAction = "clean_dev_inventory_or_choose_mapping",
	},
	["Trippi Troppi"] = {
		Disposition = "quarantine_legacy_inventory",
		Reason = "Legacy-only inventory/catalog row with no confirmed production CrewMember identity.",
		RetirementAction = "clean_dev_inventory_or_choose_mapping",
	},
}

local BROOK_FALLBACK = {
	["Gangster Footera"] = {
		Disposition = "quarantine_missing_model",
		CrewMemberId = "Soul Fiddler",
		ModelName = "Brook",
		Reason = "Production CrewMember mapping exists, but the approved Crew model asset named Brook is not present.",
		RetirementAction = "add_verified_brook_model_or_retarget_model",
	},
	["Soul Fiddler"] = {
		Disposition = "quarantine_missing_model",
		CrewMemberId = "Soul Fiddler",
		ModelName = "Brook",
		Reason = "CrewMember identity exists, but the approved Crew model asset named Brook is not present.",
		RetirementAction = "add_verified_brook_model_or_retarget_model",
	},
}

local function copyDecision(decision, kind, identity)
	if typeof(decision) ~= "table" then
		return nil
	end

	local copy = table.clone(decision)
	copy.Kind = kind
	copy.Identity = tostring(identity or "")
	copy.Allowed = true
	return copy
end

function CrewCompatibilityQuarantine.GetCompatibilityOnlyDecision(identity)
	local id = tostring(identity or "")
	return copyDecision(COMPATIBILITY_ONLY[id], "compatibility_only", id)
end

function CrewCompatibilityQuarantine.GetBrookFallbackDecision(identity)
	local id = tostring(identity or "")
	return copyDecision(BROOK_FALLBACK[id], "brook_fallback", id)
end

function CrewCompatibilityQuarantine.GetDecision(identity, kind)
	local normalizedKind = tostring(kind or "")
	if normalizedKind == "brook_fallback" then
		return CrewCompatibilityQuarantine.GetBrookFallbackDecision(identity)
	end
	if normalizedKind == "compatibility_only" then
		return CrewCompatibilityQuarantine.GetCompatibilityOnlyDecision(identity)
	end
	return nil
end

function CrewCompatibilityQuarantine.IsAllowedCompatibilityOnly(identity)
	return CrewCompatibilityQuarantine.GetCompatibilityOnlyDecision(identity) ~= nil
end

function CrewCompatibilityQuarantine.IsAllowedBrookFallback(identity)
	return CrewCompatibilityQuarantine.GetBrookFallbackDecision(identity) ~= nil
end

function CrewCompatibilityQuarantine.GetCompatibilityOnlyIds()
	local ids = {}
	for id in pairs(COMPATIBILITY_ONLY) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

function CrewCompatibilityQuarantine.GetBrookFallbackIds()
	local ids = {}
	for id in pairs(BROOK_FALLBACK) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	return ids
end

return CrewCompatibilityQuarantine
