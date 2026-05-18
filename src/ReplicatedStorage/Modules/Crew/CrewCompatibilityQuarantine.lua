local CrewCompatibilityQuarantine = {}

local COMPATIBILITY_ONLY = {}

local BROOK_FALLBACK = {}

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

function CrewCompatibilityQuarantine.ShouldSuppressRuntimeFallbackTelemetry(identity, kind)
	local decision = CrewCompatibilityQuarantine.GetDecision(identity, kind)
	if decision ~= nil then
		return decision.SuppressRuntimeFallbackTelemetry == true, decision
	end

	local compatibilityDecision = CrewCompatibilityQuarantine.GetCompatibilityOnlyDecision(identity)
	if compatibilityDecision ~= nil then
		return compatibilityDecision.SuppressRuntimeFallbackTelemetry == true, compatibilityDecision
	end

	local brookDecision = CrewCompatibilityQuarantine.GetBrookFallbackDecision(identity)
	if brookDecision ~= nil then
		return brookDecision.SuppressRuntimeFallbackTelemetry == true, brookDecision
	end

	return false, nil
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
