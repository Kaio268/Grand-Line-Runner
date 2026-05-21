local CollectionService = game:GetService("CollectionService")

local BiomePlacementResolver = {}

local BIOME_FOLDER_PATTERN = "^Biome%s*(%d+)$"

local DEFAULT_DENY_NAME_KEYWORDS = {
	"barrier",
	"bound",
	"ceiling",
	"chest",
	"crew",
	"damage",
	"debug",
	"decor",
	"decoration",
	"fence",
	"gap",
	"hitbox",
	"hit box",
	"hurtbox",
	"marker",
	"npc",
	"reward",
	"safe",
	"spawn",
	"trigger",
	"vfx",
	"visual",
	"wall",
	"wave",
}

local DEFAULT_DENY_NAME_TOKENS = {
	"end",
	"start",
}

local DEFAULT_DENY_ATTRIBUTES = {
	"BombSafe",
	"DebugHitbox",
	"HazardHitbox",
	"IsSafeZone",
	"NoHazard",
	"NoHazards",
	"NoPuddle",
	"NoPuddles",
	"SafeZone",
}

local DEFAULT_ALLOW_ATTRIBUTES = {
	"AllowPuddle",
	"AllowPuddles",
	"BiomeFloor",
	"Floor",
	"HazardFloor",
	"PuddleFloor",
	"PuddlePlacement",
	"PuddleSpawnFloor",
}

local DEFAULT_DENY_TAGS = {
	"CrewSpawnPad",
	"DebugHitbox",
	"HazardHitbox",
	"NoHazard",
	"NoPuddle",
	"NoPuddles",
	"SafeZone",
}

local DEFAULT_ALLOW_TAGS = {
	"AllowPuddle",
	"AllowPuddles",
	"BiomeFloor",
	"Floor",
	"HazardFloor",
	"PuddleFloor",
	"PuddlePlacement",
	"PuddleSpawnFloor",
}

local cacheByBiomesRoot = setmetatable({}, { __mode = "k" })
local warned = {}

local function normalizeBiomeIndex(biomeIndex)
	local index = math.floor(tonumber(biomeIndex) or 0)
	if index < 1 then
		return nil
	end

	return index
end

local function getContext(options)
	return tostring((options and (options.Context or options.FilterKey)) or "BiomePlacementResolver")
end

local function getFilterKey(options)
	return tostring((options and options.FilterKey) or getContext(options))
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function warnOnce(key, message, ...)
	if warned[key] then
		return
	end

	warned[key] = true
	warn(string.format(message, ...))
end

local function getRootCache(biomesRoot)
	local rootCache = cacheByBiomesRoot[biomesRoot]
	if rootCache then
		return rootCache
	end

	rootCache = {}
	cacheByBiomesRoot[biomesRoot] = rootCache
	return rootCache
end

local function getList(options, key, fallback)
	local value = options and options[key]
	if type(value) == "table" then
		return value
	end

	return fallback
end

local function findKeyword(name, keywords)
	local lowerName = string.lower(tostring(name or ""))
	for _, keyword in ipairs(keywords or {}) do
		local normalized = string.lower(tostring(keyword or ""))
		if normalized ~= "" and lowerName:find(normalized, 1, true) then
			return normalized
		end
	end

	return nil
end

local function findNameToken(name, tokens)
	local normalizedName = string.lower(tostring(name or ""))
	local tokenText = " " .. normalizedName:gsub("[^%w]+", " ") .. " "
	for _, token in ipairs(tokens or {}) do
		local normalized = string.lower(tostring(token or ""))
		if normalized ~= "" and tokenText:find(" " .. normalized .. " ", 1, true) then
			return normalized
		end
	end

	return nil
end

local function containsKeyword(name, keywords)
	return findKeyword(name, keywords) ~= nil
end

local function hasAnyAttribute(instance, attributeNames)
	local current = instance
	while current do
		for _, attributeName in ipairs(attributeNames or {}) do
			if current:GetAttribute(tostring(attributeName)) == true then
				return true
			end
		end

		current = current.Parent
	end

	return false
end

local function hasAnyTag(instance, tagNames)
	for _, tagName in ipairs(tagNames or {}) do
		if CollectionService:HasTag(instance, tostring(tagName)) then
			return true
		end
	end

	return false
end

local function hasExplicitAllow(instance, options)
	return hasAnyAttribute(instance, getList(options, "AllowAttributes", DEFAULT_ALLOW_ATTRIBUTES))
		or hasAnyTag(instance, getList(options, "AllowTags", DEFAULT_ALLOW_TAGS))
end

local function hasDenyMarker(instance, options)
	return hasAnyAttribute(instance, getList(options, "DenyAttributes", DEFAULT_DENY_ATTRIBUTES))
		or hasAnyTag(instance, getList(options, "DenyTags", DEFAULT_DENY_TAGS))
end

local function isLikelyInvisibleHelper(part, options)
	if part.Transparency < 1 then
		return false
	end

	if hasExplicitAllow(part, options) then
		return false
	end

	local helperKeywords = getList(options, "InvisibleHelperNameKeywords", {
		"bound",
		"debug",
		"helper",
		"hitbox",
		"invisible",
		"marker",
		"trigger",
	})
	return containsKeyword(part.Name, helperKeywords)
end

local function getDeniedNameKeyword(part, options)
	local denyKeywords = getList(options, "DenyNameKeywords", DEFAULT_DENY_NAME_KEYWORDS)
	local denyTokens = getList(options, "DenyNameTokens", DEFAULT_DENY_NAME_TOKENS)
	local current = part
	while current do
		local keyword = findKeyword(current.Name, denyKeywords)
		if keyword then
			return keyword
		end

		local token = findNameToken(current.Name, denyTokens)
		if token then
			return token
		end

		current = current.Parent
	end

	return nil
end

local function getPartRejectReason(part, options)
	if not (part and part:IsA("BasePart") and part.Parent) then
		return "not_basepart"
	end

	if part.CanCollide ~= true then
		return "not_collidable"
	end

	if part.CanQuery == false then
		return "not_queryable"
	end

	if hasDenyMarker(part, options) then
		return "deny_marker"
	end

	local explicitAllow = hasExplicitAllow(part, options)
	local deniedKeyword = getDeniedNameKeyword(part, options)
	if deniedKeyword and not explicitAllow then
		return "deny_name:" .. deniedKeyword
	end

	if isLikelyInvisibleHelper(part, options) then
		return "invisible_helper"
	end

	local minSurfaceSize = math.max(1, tonumber(options and options.MinSurfaceSize) or 6)
	if part.Size.X < minSurfaceSize or part.Size.Z < minSurfaceSize then
		return "too_small"
	end

	local minUpDot = math.clamp(tonumber(options and options.MinUpDot) or 0.65, 0, 1)
	if part.CFrame.UpVector:Dot(Vector3.yAxis) < minUpDot then
		return "not_upright"
	end

	return nil
end

local function addRejectDiagnostic(diagnostics, reason, part)
	if type(diagnostics) ~= "table" then
		return
	end

	reason = tostring(reason or "unknown")
	diagnostics.Rejections[reason] = (diagnostics.Rejections[reason] or 0) + 1

	local samples = diagnostics.RejectionSamples[reason]
	if not samples then
		samples = {}
		diagnostics.RejectionSamples[reason] = samples
	end

	if #samples < 3 then
		samples[#samples + 1] = formatInstancePath(part)
	end
end

local function getBiomeIndexFromName(name)
	local indexText = tostring(name or ""):match(BIOME_FOLDER_PATTERN)
	return indexText and tonumber(indexText) or nil
end

function BiomePlacementResolver.GetBiomeRoot(refs, biomeIndex)
	local biomesRoot = refs and refs.Biomes
	local index = normalizeBiomeIndex(biomeIndex)
	if not (biomesRoot and index) then
		return nil
	end

	for _, child in ipairs(biomesRoot:GetChildren()) do
		if getBiomeIndexFromName(child.Name) == index then
			return child:FindFirstChild(child.Name) or child
		end
	end

	return nil
end

local function getEntryWeight(entries)
	local total = 0
	for _, entry in ipairs(entries or {}) do
		total += math.max(0, tonumber(entry.Weight) or 0)
	end

	return total
end

local function addSurfaceEntry(entries, part, isExplicit)
	local weight = math.max(1, part.Size.X * part.Size.Z)
	entries[#entries + 1] = {
		Part = part,
		Weight = weight,
		UsedExplicitSurface = isExplicit == true,
	}
end

local function makeSurfaceDiagnostics(root)
	return {
		RootPath = formatInstancePath(root),
		TotalParts = 0,
		UsableParts = 0,
		ExplicitUsableParts = 0,
		GeneralUsableParts = 0,
		UsedExplicitOnly = false,
		Rejections = {},
		RejectionSamples = {},
	}
end

local function getEntriesForUse(explicitEntries, generalEntries, options)
	if #explicitEntries > 0 and (not options or options.PreferExplicit ~= false) then
		return explicitEntries, getEntryWeight(explicitEntries), true
	end

	return generalEntries, getEntryWeight(generalEntries), false
end

local function makeSurfaceData(root, explicitEntries, generalEntries, diagnostics, options)
	local entries, totalWeight, usedExplicit = getEntriesForUse(explicitEntries, generalEntries, options)
	diagnostics.UsedExplicitOnly = usedExplicit

	return {
		Entries = entries,
		TotalWeight = totalWeight,
		ExplicitEntries = explicitEntries,
		ExplicitTotalWeight = getEntryWeight(explicitEntries),
		GeneralEntries = generalEntries,
		GeneralTotalWeight = getEntryWeight(generalEntries),
		UsedExplicit = usedExplicit,
		Diagnostics = diagnostics,
		Root = root,
	}
end

local function collectBiomeSurfaceEntries(root, options)
	local explicitEntries = {}
	local generalEntries = {}
	local diagnostics = makeSurfaceDiagnostics(root)

	local function tryAddPart(part)
		diagnostics.TotalParts += 1

		local reason = getPartRejectReason(part, options)
		if reason then
			addRejectDiagnostic(diagnostics, reason, part)
			return
		end

		diagnostics.UsableParts += 1
		if hasExplicitAllow(part, options) then
			diagnostics.ExplicitUsableParts += 1
			addSurfaceEntry(explicitEntries, part, true)
		else
			diagnostics.GeneralUsableParts += 1
			addSurfaceEntry(generalEntries, part, false)
		end
	end

	if root:IsA("BasePart") then
		tryAddPart(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			tryAddPart(descendant)
		end
	end

	return makeSurfaceData(root, explicitEntries, generalEntries, diagnostics, options)
end

local function getSurfaceCount(surfaceData)
	return surfaceData and #surfaceData.Entries or 0
end

local function getExplicitSurfaceCount(surfaceData)
	return surfaceData and #surfaceData.ExplicitEntries or 0
end

local function getGeneralSurfaceCount(surfaceData)
	return surfaceData and #surfaceData.GeneralEntries or 0
end

local function getRootPath(surfaceData)
	return (surfaceData and surfaceData.Diagnostics and surfaceData.Diagnostics.RootPath) or "<nil>"
end

function BiomePlacementResolver.GetSurfaceSummary(surfaceData)
	if not surfaceData then
		return {
			RootPath = "<nil>",
			SurfaceCount = 0,
			ExplicitSurfaceCount = 0,
			GeneralSurfaceCount = 0,
			UsedExplicit = false,
			Diagnostics = nil,
		}
	end

	return {
		RootPath = getRootPath(surfaceData),
		SurfaceCount = getSurfaceCount(surfaceData),
		ExplicitSurfaceCount = getExplicitSurfaceCount(surfaceData),
		GeneralSurfaceCount = getGeneralSurfaceCount(surfaceData),
		UsedExplicit = surfaceData.UsedExplicit == true,
		Diagnostics = surfaceData.Diagnostics,
	}
end

function BiomePlacementResolver.FormatRejectionSummary(diagnostics)
	if type(diagnostics) ~= "table" or type(diagnostics.Rejections) ~= "table" then
		return "none"
	end

	local parts = {}
	for reason, count in pairs(diagnostics.Rejections) do
		parts[#parts + 1] = string.format("%s=%d", tostring(reason), tonumber(count) or 0)
	end
	table.sort(parts)

	if #parts == 0 then
		return "none"
	end

	return table.concat(parts, ",")
end

function BiomePlacementResolver.FormatRejectionSamples(diagnostics)
	if type(diagnostics) ~= "table" or type(diagnostics.RejectionSamples) ~= "table" then
		return "none"
	end

	local parts = {}
	for reason, samples in pairs(diagnostics.RejectionSamples) do
		parts[#parts + 1] = string.format("%s=[%s]", tostring(reason), table.concat(samples, " | "))
	end
	table.sort(parts)

	if #parts == 0 then
		return "none"
	end

	return table.concat(parts, "; ")
end

function BiomePlacementResolver.GetBiomeSurfaces(refs, biomeIndex, options)
	options = if type(options) == "table" then options else {}
	local biomesRoot = refs and refs.Biomes
	local index = normalizeBiomeIndex(biomeIndex)
	if not (biomesRoot and index) then
		return nil
	end

	local rootCache = getRootCache(biomesRoot)
	local filterKey = getFilterKey(options)
	rootCache[filterKey] = rootCache[filterKey] or {}

	local cached = rootCache[filterKey][index]
	if cached and cached.Root and cached.Root.Parent then
		return cached
	end

	local root = BiomePlacementResolver.GetBiomeRoot(refs, index)
	if not root then
		return nil
	end

	local collected = collectBiomeSurfaceEntries(root, options)
	rootCache[filterKey][index] = collected

	if #collected.Entries == 0 and options.WarnIfMissing ~= false then
		warnOnce(
			string.format("%s:%s:%s", getContext(options), formatInstancePath(root), tostring(index)),
			"[BiomePlacementResolver] No usable placement surfaces found for %s biome=%d root=%s rejections={%s}",
			getContext(options),
			index,
			formatInstancePath(root),
			BiomePlacementResolver.FormatRejectionSummary(collected.Diagnostics)
		)
	end

	return collected
end

function BiomePlacementResolver.GetBiomeSurfaceEntries(refs, biomeIndex, options)
	local surfaceData = BiomePlacementResolver.GetBiomeSurfaces(refs, biomeIndex, options)
	if not surfaceData then
		return {}, BiomePlacementResolver.GetSurfaceSummary(nil)
	end

	return surfaceData.Entries, BiomePlacementResolver.GetSurfaceSummary(surfaceData)
end

local function chooseEntry(surfaceData, rng)
	if not surfaceData or #surfaceData.Entries == 0 then
		return nil
	end

	local random = rng or Random.new()
	local totalWeight = math.max(0, tonumber(surfaceData.TotalWeight) or 0)
	if totalWeight <= 0 then
		return surfaceData.Entries[random:NextInteger(1, #surfaceData.Entries)]
	end

	local roll = random:NextNumber(0, totalWeight)
	local cursor = 0
	for _, entry in ipairs(surfaceData.Entries) do
		cursor += math.max(0, tonumber(entry.Weight) or 0)
		if roll <= cursor then
			return entry
		end
	end

	return surfaceData.Entries[#surfaceData.Entries]
end

local function getPlanarUnit(vector, fallback)
	local planar = typeof(vector) == "Vector3" and Vector3.new(vector.X, 0, vector.Z) or Vector3.zero
	if planar.Magnitude > 1e-4 then
		return planar.Unit
	end

	local fallbackPlanar = typeof(fallback) == "Vector3" and Vector3.new(fallback.X, 0, fallback.Z) or Vector3.zero
	if fallbackPlanar.Magnitude > 1e-4 then
		return fallbackPlanar.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getHalfFootprint(footprintSize)
	if typeof(footprintSize) ~= "Vector3" then
		return 0, 0
	end

	return math.max(0, footprintSize.X * 0.5), math.max(0, footprintSize.Z * 0.5)
end

local function makeCandidateDiagnostics(surfaceData, reason)
	local summary = BiomePlacementResolver.GetSurfaceSummary(surfaceData)
	summary.Reason = tostring(reason or "")
	return summary
end

local function chooseCandidateFromEntries(surfaceData, entries, totalWeight, rng, options, usedExplicit)
	if #entries == 0 then
		return nil, "no_biome_surfaces"
	end

	local random = rng or Random.new()
	local attempts = math.max(1, math.floor(tonumber(options.CandidateAttempts) or 12))
	local footprintHalfX, footprintHalfZ = getHalfFootprint(options.FootprintSize)
	local edgePadding = math.max(0, tonumber(options.EdgePadding) or 0)
	local tooSmallCount = 0

	local candidateData = {
		Entries = entries,
		TotalWeight = totalWeight,
	}

	for _ = 1, attempts do
		local entry = chooseEntry(candidateData, random)
		local part = entry and entry.Part
		local rejectReason = getPartRejectReason(part, options)
		if not rejectReason then
			local halfX = (part.Size.X * 0.5) - footprintHalfX - edgePadding
			local halfZ = (part.Size.Z * 0.5) - footprintHalfZ - edgePadding
			if halfX >= 0 and halfZ >= 0 then
				local localX = if halfX > 0 then random:NextNumber(-halfX, halfX) else 0
				local localZ = if halfZ > 0 then random:NextNumber(-halfZ, halfZ) else 0
				local topOffset = math.max(0.25, tonumber(options.TopOffset) or 2)
				local position = (part.CFrame * CFrame.new(localX, (part.Size.Y * 0.5) + topOffset, localZ)).Position
				local forward = getPlanarUnit(part.CFrame.LookVector, Vector3.new(0, 0, -1))
				local lateral = getPlanarUnit(part.CFrame.RightVector, forward:Cross(Vector3.yAxis))

				return {
					Part = part,
					Position = position,
					Forward = forward,
					Lateral = lateral,
					Root = surfaceData.Root,
					UsedExplicitSurface = usedExplicit == true,
				}
			end

			tooSmallCount += 1
		elseif surfaceData.Diagnostics then
			addRejectDiagnostic(surfaceData.Diagnostics, "runtime_" .. rejectReason, part)
		end
	end

	if tooSmallCount > 0 and surfaceData.Diagnostics then
		surfaceData.Diagnostics.Rejections.candidate_too_small =
			(surfaceData.Diagnostics.Rejections.candidate_too_small or 0) + tooSmallCount
	end

	return nil, "no_candidate_fits_footprint"
end

local function getCandidateFallbackEntries(surfaceData)
	if not (surfaceData and surfaceData.UsedExplicit == true) then
		return nil, 0
	end

	if #surfaceData.GeneralEntries == 0 then
		return nil, 0
	end

	return surfaceData.GeneralEntries, surfaceData.GeneralTotalWeight
end

local function stampCandidateSummary(candidate, biomeIndex, surfaceData)
	candidate.BiomeIndex = normalizeBiomeIndex(biomeIndex)
	candidate.SurfaceCount = getSurfaceCount(surfaceData)
	candidate.ExplicitSurfaceCount = getExplicitSurfaceCount(surfaceData)
	candidate.GeneralSurfaceCount = getGeneralSurfaceCount(surfaceData)
	candidate.BiomeRootPath = getRootPath(surfaceData)
	candidate.Diagnostics = surfaceData.Diagnostics
	return candidate
end

function BiomePlacementResolver.GetRandomSurfaceCandidate(refs, biomeIndex, rng, options)
	options = if type(options) == "table" then options else {}

	local surfaceData = BiomePlacementResolver.GetBiomeSurfaces(refs, biomeIndex, options)
	if not surfaceData then
		return nil, "missing_biome_root", makeCandidateDiagnostics(nil, "missing_biome_root")
	end
	if #surfaceData.Entries == 0 then
		return nil, "no_biome_surfaces", makeCandidateDiagnostics(surfaceData, "no_biome_surfaces")
	end

	local candidate, reason = chooseCandidateFromEntries(
		surfaceData,
		surfaceData.Entries,
		surfaceData.TotalWeight,
		rng,
		options,
		surfaceData.UsedExplicit
	)
	if candidate then
		return stampCandidateSummary(candidate, biomeIndex, surfaceData), nil, makeCandidateDiagnostics(surfaceData, "ok")
	end

	local fallbackEntries, fallbackTotalWeight = getCandidateFallbackEntries(surfaceData)
	if fallbackEntries then
		candidate, reason = chooseCandidateFromEntries(surfaceData, fallbackEntries, fallbackTotalWeight, rng, options, false)
		if candidate then
			candidate.ExplicitFallbackUsed = true
			return stampCandidateSummary(candidate, biomeIndex, surfaceData), nil, makeCandidateDiagnostics(surfaceData, "ok")
		end
	end

	return nil, reason or "no_candidate", makeCandidateDiagnostics(surfaceData, reason or "no_candidate")
end

function BiomePlacementResolver.GetRandomSurfaceCandidateFromEntry(refs, biomeIndex, surfaceEntry, rng, options)
	options = if type(options) == "table" then options else {}

	local surfaceData = BiomePlacementResolver.GetBiomeSurfaces(refs, biomeIndex, options)
	if not surfaceData then
		return nil, "missing_biome_root", makeCandidateDiagnostics(nil, "missing_biome_root")
	end

	if not (surfaceEntry and surfaceEntry.Part and surfaceEntry.Part.Parent) then
		return nil, "invalid_surface_entry", makeCandidateDiagnostics(surfaceData, "invalid_surface_entry")
	end

	local candidate, reason = chooseCandidateFromEntries(
		surfaceData,
		{ surfaceEntry },
		math.max(1, tonumber(surfaceEntry.Weight) or 1),
		rng,
		options,
		surfaceEntry.UsedExplicitSurface == true
	)
	if candidate then
		return stampCandidateSummary(candidate, biomeIndex, surfaceData), nil, makeCandidateDiagnostics(surfaceData, "ok")
	end

	return nil, reason or "no_candidate", makeCandidateDiagnostics(surfaceData, reason or "no_candidate")
end

function BiomePlacementResolver.ClearCache(biomesRoot)
	if biomesRoot == nil then
		table.clear(cacheByBiomesRoot)
		table.clear(warned)
		return
	end

	cacheByBiomesRoot[biomesRoot] = nil
end

return BiomePlacementResolver
