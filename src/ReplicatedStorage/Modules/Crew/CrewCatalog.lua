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

	info.Id = variantCrewMemberId
	info.CrewMemberId = variantCrewMemberId
	info.CrewMemberName = variantCrewMemberId
	info.DisplayName = variantCrewMemberId
	info.Name = variantCrewMemberId
	info.IsVariant = true
	info.BaseId = tostring(baseInfo.CrewMemberId or baseIdStr)
	info.CrewMemberBaseId = tostring(baseInfo.CrewMemberId or baseIdStr)
	info.Variant = variantKey
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
