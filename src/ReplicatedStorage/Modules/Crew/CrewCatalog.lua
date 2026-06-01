local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local VariantCfg = require(Configs:WaitForChild("CrewVariants"))
local CrewMembers = require(script.Parent:WaitForChild("CrewMembers"))
local CrewIncomeBalance = require(script.Parent:WaitForChild("CrewIncomeBalance"))

local CrewCatalog = {}

local warned = {}
local emptyLegacyConfig = table.freeze({})
local retiredAliases = table.freeze({
	Bruiser = "Diamond Bruiser",
})

local function warnOnce(key, message)
	if warned[key] then
		return
	end
	warned[key] = true
	warn(message)
end

local function cloneShallow(value)
	return table.clone(value or {})
end

local function getVariantConfig(variantKey)
	return (VariantCfg.Versions or {})[variantKey]
end

local function getVariantDisplayName(variantKey)
	local normalizedVariant = tostring(variantKey or "")
	if normalizedVariant == "" then
		return ""
	end

	local variantInfo = getVariantConfig(normalizedVariant)
	return tostring(
		(variantInfo and (variantInfo.DisplayName or variantInfo.Name or variantInfo.Label))
			or normalizedVariant
	)
end

local function getVariantPrefix(variantKey)
	local variantInfo = getVariantConfig(variantKey)
	return tostring((variantInfo and variantInfo.Prefix) or (tostring(variantKey or "") .. " "))
end

local function stripConfirmedVariantPrefix(displayName, variantKey)
	local text = tostring(displayName or "")
	local prefix = getVariantPrefix(variantKey)
	if prefix ~= "" and text:sub(1, #prefix) == prefix then
		local stripped = text:sub(#prefix + 1)
		if stripped ~= "" then
			return stripped
		end
	end

	return text
end

local function getBaseDisplayName(info, fallback)
	if typeof(info) == "table" then
		local displayName = tostring(info.BaseDisplayName or info.DisplayName or info.CrewMemberName or info.Name or "")
		if displayName ~= "" then
			return displayName
		end
	end

	local fallbackText = tostring(fallback or "")
	if fallbackText ~= "" then
		return fallbackText
	end
	return "Crewmate"
end

local function getProductionEntry(id)
	return CrewMembers.GetByCrewMemberId(id)
		or CrewMembers.GetByDisplayName(id)
		or CrewMembers.GetByRealCharacterName(id)
end

local function getLegacyProductionEntry(id)
	return CrewMembers.GetByLegacyId(id)
end

local function getRetiredAlias(id)
	return retiredAliases[tostring(id or "")]
end

local function infoFromProductionEntry(entry)
	if typeof(entry) ~= "table" then
		return nil
	end

	local crewMemberId = tostring(entry.CrewMemberId or "")
	if crewMemberId == "" then
		warnOnce("missing_crew_member_id", "[CrewCatalog] Canonical CrewMember entry is missing CrewMemberId.")
		return nil
	end

	local displayName = tostring(entry.DisplayName or crewMemberId)
	local render = tostring(entry.Render or "")
	local renderStatus = tostring(entry.RenderStatus or "")
	if render == "" then
		warnOnce(
			"missing_render:" .. crewMemberId,
			string.format("[CrewCatalog] CrewMember '%s' is missing canonical Render metadata.", crewMemberId)
		)
	elseif renderStatus == "NeedsCanonicalPortrait" then
		warnOnce(
			"placeholder_render_assets",
			"[CrewCatalog] CrewMember portrait renders are neutral placeholders until final canonical portraits are added."
		)
	end

	local info = cloneShallow(entry)
	info.Id = crewMemberId
	info.CrewMemberId = crewMemberId
	info.CrewMemberName = displayName
	info.DisplayName = displayName
	info.Name = displayName
	info.ModelName = tostring(entry.ModelName or entry.RealCharacterName or crewMemberId)
	info.RealCharacterName = tostring(entry.RealCharacterName or "")
	info.Arc = tostring(entry.Arc or "")
	info.CrewArc = info.Arc
	info.Rarity = CrewIncomeBalance.NormalizeRarity(entry.Rarity or "Common")
	info.Render = render
	info.GoldenRender = tostring(entry.GoldenRender or render)
	info.DiamondRender = tostring(entry.DiamondRender or render)
	info.RenderStatus = renderStatus
	local baseIncomeRoll = CrewIncomeBalance.GetBaseIncomeRangeMidpoint(info.Rarity)
	info.BaseIncomeMin, info.BaseIncomeMax = CrewIncomeBalance.GetBaseIncomeRange(info.Rarity)
	info.Income = baseIncomeRoll
	info.Chance = tonumber(entry.Chance) or 0
	info.TimeLeft = tonumber(entry.TimeLeft) or 30
	info.ModelNameVerified = entry.ModelNameVerified == true
	info.MissingCrewModel = entry.MissingModel == true

	return info
end

function CrewCatalog.GetVariantConfig()
	return VariantCfg
end

function CrewCatalog.GetLegacyConfig()
	warnOnce(
		"legacy_config_requested",
		"[CrewCatalog] GetLegacyConfig is deprecated. Active systems must use canonical CrewMember data."
	)
	return emptyLegacyConfig
end

function CrewCatalog.MakeVariantId(baseId, variantKey)
	if variantKey == "Normal" or variantKey == nil then
		return tostring(baseId)
	end

	local variantInfo = getVariantConfig(variantKey)
	local prefix = (variantInfo and variantInfo.Prefix) or (tostring(variantKey) .. " ")
	return prefix .. tostring(baseId)
end

function CrewCatalog.ParseVariantId(crewMemberId)
	local id = tostring(crewMemberId or "")

	for _, variantKey in ipairs(VariantCfg.Order or {}) do
		if variantKey ~= "Normal" then
			local variantInfo = getVariantConfig(variantKey)
			local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
			if prefix ~= "" and id:sub(1, #prefix) == prefix then
				return variantKey, id:sub(#prefix + 1), variantInfo
			end
		end
	end

	return "Normal", id, getVariantConfig("Normal")
end

function CrewCatalog.GetBaseInfo(baseId)
	local entry = getProductionEntry(tostring(baseId or ""))
	return infoFromProductionEntry(entry)
end

function CrewCatalog.GetInfoByLegacyId(legacyId)
	local entry = getLegacyProductionEntry(tostring(legacyId or ""))
	local info = infoFromProductionEntry(entry)
	if info then
		info.LegacyId = tostring(legacyId or "")
	end
	return info
end

function CrewCatalog.GetInfoById(crewMemberId)
	local id = tostring(crewMemberId or "")
	local direct = CrewCatalog.GetBaseInfo(id)
	if direct then
		return direct
	end

	local variantKey, baseId = CrewCatalog.ParseVariantId(id)
	if variantKey ~= "Normal" then
		return CrewCatalog.GetOrBuildVariantInfo(baseId, variantKey)
	end

	return nil
end

function CrewCatalog.ResolveCrewMemberId(crewMemberId)
	local id = tostring(crewMemberId or "")
	if id == "" then
		return "", nil, ""
	end

	local directInfo = CrewCatalog.GetBaseInfo(id)
	if directInfo then
		return tostring(directInfo.CrewMemberId or id), directInfo, ""
	end

	local variantKey, baseId = CrewCatalog.ParseVariantId(id)
	local aliasTarget = getRetiredAlias(baseId)
	if aliasTarget then
		baseId = aliasTarget
	end
	local info = CrewCatalog.GetBaseInfo(baseId)
	local legacyStorageName = ""

	if not info then
		info = CrewCatalog.GetInfoByLegacyId(baseId)
		if info then
			legacyStorageName = id
		end
	end

	if not info then
		return id, nil, ""
	end

	local canonicalBaseId = tostring(info.CrewMemberId or baseId)
	if variantKey ~= "Normal" then
		local variantInfo = CrewCatalog.GetOrBuildVariantInfo(canonicalBaseId, variantKey)
		if variantInfo then
			local canonicalVariantId = tostring(variantInfo.CrewMemberId or CrewCatalog.MakeVariantId(canonicalBaseId, variantKey))
			if (canonicalVariantId ~= id or aliasTarget ~= nil) and legacyStorageName == "" then
				legacyStorageName = id
			end
			return canonicalVariantId, variantInfo, legacyStorageName
		end
	end

	if (canonicalBaseId ~= id or aliasTarget ~= nil) and legacyStorageName == "" then
		legacyStorageName = id
	end

	return canonicalBaseId, info, legacyStorageName
end

function CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	local canonicalId, info, legacyStorageName = CrewCatalog.ResolveCrewMemberId(crewMemberId)
	if not info then
		return "", nil, ""
	end
	return canonicalId, info, legacyStorageName
end

function CrewCatalog.GetInfoByAnyId(crewMemberId)
	local _, info = CrewCatalog.ResolveCrewMemberId(crewMemberId)
	return info
end

function CrewCatalog.GetDisplayInfo(crewMemberId, metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	local lookupId = tostring(crewMemberId or "")
	if lookupId == "" then
		lookupId = tostring(metadata.CrewMemberId or "")
	end
	if lookupId == "" then
		lookupId = tostring(metadata.StorageName or metadata.BaseName or metadata.Id or metadata.Name or "")
	end
	local explicitVariant = tostring(metadata.Variant or metadata.VariantKey or "")
	local canonicalId, info = CrewCatalog.ResolveCrewMemberId(lookupId)
	local variantKey = "Normal"
	local baseId = tostring(canonicalId or lookupId)
	local baseInfo = info
	local isVariant = false

	if typeof(info) == "table" and info.IsVariant == true then
		variantKey = tostring(info.Variant or explicitVariant or "Normal")
		baseId = tostring(info.BaseId or info.CrewMemberBaseId or baseId)
		baseInfo = CrewCatalog.GetBaseInfo(baseId) or info
		isVariant = variantKey ~= "Normal"
	elseif explicitVariant ~= "" and explicitVariant ~= "Normal" then
		local explicitBaseInfo = CrewCatalog.GetBaseInfo(baseId)
		if explicitBaseInfo then
			variantKey = explicitVariant
			baseId = tostring(explicitBaseInfo.CrewMemberId or baseId)
			baseInfo = explicitBaseInfo
			isVariant = true
		end
	end

	if not isVariant and lookupId ~= "" then
		local parsedVariant, parsedBaseId = CrewCatalog.ParseVariantId(lookupId)
		if parsedVariant ~= "Normal" then
			local parsedBaseInfo = CrewCatalog.GetBaseInfo(parsedBaseId)
			if parsedBaseInfo then
				variantKey = parsedVariant
				baseId = tostring(parsedBaseInfo.CrewMemberId or parsedBaseId)
				baseInfo = parsedBaseInfo
				info = CrewCatalog.GetOrBuildVariantInfo(baseId, variantKey) or info
				canonicalId = tostring((info and info.CrewMemberId) or CrewCatalog.MakeVariantId(baseId, variantKey))
				isVariant = true
			end
		end
	end

	local metadataDisplayName = tostring(metadata.DisplayName or metadata.CrewMemberName or metadata.Name or "")
	local baseDisplayName = getBaseDisplayName(baseInfo, if isVariant then baseId else metadataDisplayName)
	local displayName = baseDisplayName
	if not isVariant and metadataDisplayName ~= "" and info == nil then
		displayName = metadataDisplayName
	elseif isVariant and displayName == "" then
		displayName = stripConfirmedVariantPrefix(metadataDisplayName, variantKey)
	end

	local variantDisplayName = getVariantDisplayName(variantKey)
	local showVariantTag = isVariant and variantKey ~= "Normal"

	return {
		DisplayName = displayName,
		BaseDisplayName = baseDisplayName,
		Variant = variantKey,
		VariantTag = if showVariantTag then variantDisplayName else "",
		VariantDisplayName = variantDisplayName,
		ShowVariantTag = showVariantTag,
		IsVariant = isVariant,
		BaseId = baseId,
		CrewMemberId = tostring((info and info.CrewMemberId) or canonicalId or lookupId),
	}
end

function CrewCatalog.GetOrBuildVariantInfo(baseId, variantKey)
	local baseIdStr = tostring(baseId or "")
	if variantKey == "Normal" or variantKey == nil then
		return CrewCatalog.GetBaseInfo(baseIdStr)
	end

	local baseInfo = CrewCatalog.GetBaseInfo(baseIdStr)
	if not baseInfo then
		return nil
	end

	local variantInfo = getVariantConfig(variantKey)
	local variantPrefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
	local variantCrewMemberId = variantPrefix .. tostring(baseInfo.CrewMemberId or baseIdStr)
	local info = cloneShallow(baseInfo)
	local baseDisplayName = getBaseDisplayName(baseInfo, baseIdStr)
	local variantDisplayName = getVariantDisplayName(variantKey)

	info.Id = variantCrewMemberId
	info.CrewMemberId = variantCrewMemberId
	info.CrewMemberName = baseDisplayName
	info.DisplayName = baseDisplayName
	info.Name = baseDisplayName
	info.IsVariant = true
	info.BaseId = tostring(baseInfo.CrewMemberId or baseIdStr)
	info.CrewMemberBaseId = tostring(baseInfo.CrewMemberId or baseIdStr)
	info.Variant = variantKey
	info.BaseDisplayName = baseDisplayName
	info.VariantDisplayName = variantDisplayName
	info.VariantTag = variantDisplayName
	info.ShowVariantTag = true
	info.GoldenRender = baseInfo.GoldenRender
	info.DiamondRender = baseInfo.DiamondRender
	if variantKey == "Golden" then
		info.Render = tostring(baseInfo.GoldenRender or baseInfo.Render or "")
	elseif variantKey == "Diamond" then
		info.Render = tostring(baseInfo.DiamondRender or baseInfo.Render or "")
	else
		info.Render = tostring(baseInfo.Render or "")
	end
	info.Income = CrewIncomeBalance.ComputeIncome(tonumber(baseInfo.Income) or 0, variantKey)

	return info
end

function CrewCatalog.FindInfoByName(name)
	local rawName = tostring(name or "")
	if rawName == "" then
		return nil, nil
	end

	local canonicalId, resolved = CrewCatalog.ResolveCrewMemberId(rawName)
	if resolved then
		return resolved, canonicalId
	end

	local direct = CrewCatalog.GetInfoById(rawName)
	if direct then
		return direct, rawName
	end

	for _, entry in ipairs(CrewMembers.GetEntries()) do
		local crewInfo = infoFromProductionEntry(entry)
		if crewInfo then
			if tostring(crewInfo.Name or "") == rawName
				or tostring(crewInfo.DisplayName or "") == rawName
				or tostring(crewInfo.CrewMemberName or "") == rawName
				or tostring(crewInfo.RealCharacterName or "") == rawName
				or tostring(crewInfo.ModelName or "") == rawName
			then
				return crewInfo, tostring(crewInfo.CrewMemberId)
			end
		end
	end

	return nil, nil
end

function CrewCatalog.GetBaseEntries()
	local entries = {}

	for _, entry in ipairs(CrewMembers.GetEntries()) do
		local crewInfo = infoFromProductionEntry(entry)
		if crewInfo then
			entries[#entries + 1] = {
				Id = tostring(crewInfo.CrewMemberId),
				Info = crewInfo,
			}
		end
	end

	return entries
end

return CrewCatalog
