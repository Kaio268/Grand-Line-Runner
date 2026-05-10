local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")

local LegacyBrainrots = require(Configs:WaitForChild("Brainrots"))
local VariantCfg = require(Configs:WaitForChild("BrainrotVariants"))
local CrewMembers = require(script.Parent:WaitForChild("CrewMembers"))
local CrewMemberMappings = require(script.Parent:WaitForChild("CrewMemberMappings"))

local CrewCatalog = {}

local legacyIdToCrewMember = CrewMemberMappings.LegacyIdToCrewMember or {}

local function cloneShallow(value)
	return table.clone(value or {})
end

local function getMapping(legacyId)
	local mapping = legacyIdToCrewMember[tostring(legacyId)]
	if typeof(mapping) == "table" then
		return mapping
	end
	return nil
end

local function getProductionEntry(id)
	return CrewMembers.GetByCrewMemberId(id)
		or CrewMembers.GetByDisplayName(id)
		or CrewMembers.GetByRealCharacterName(id)
end

local function getVariantConfig(variantKey)
	return (VariantCfg.Versions or {})[variantKey]
end

function CrewCatalog.GetVariantConfig()
	return VariantCfg
end

function CrewCatalog.GetLegacyConfig()
	return LegacyBrainrots
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
	local id = tostring(baseId)
	local legacyInfo = LegacyBrainrots[id]
	if typeof(legacyInfo) ~= "table" or legacyInfo.IsVariant or legacyInfo.Variant then
		return nil
	end

	local mapping = getMapping(id)
	local info = cloneShallow(legacyInfo)
	local displayName = tostring((mapping and mapping.DisplayName) or info.DisplayName or info.Name or id)

	info.Id = id
	info.LegacyId = id
	info.CrewMemberId = tostring((mapping and mapping.CrewMemberId) or id)
	info.CrewMemberName = displayName
	info.DisplayName = displayName
	info.Name = displayName
	info.ModelName = tostring((mapping and mapping.ModelName) or (mapping and mapping.CrewMemberName) or id)
	info.RealCharacterName = mapping and mapping.RealCharacterName or info.RealCharacterName
	info.Arc = mapping and mapping.Arc or info.Arc
	info.CrewArc = info.Arc
	info.ModelNameVerified = mapping and mapping.ModelNameVerified == true or nil
	info.MissingCrewModel = mapping and mapping.MissingModel == true or nil
	if mapping and mapping.Rarity then
		info.Rarity = tostring(mapping.Rarity)
	end

	return info
end

function CrewCatalog.GetInfoById(crewMemberId)
	local id = tostring(crewMemberId)
	local direct = CrewCatalog.GetBaseInfo(id)
	if direct then
		return direct
	end

	local productionEntry = getProductionEntry(id)
	if productionEntry and productionEntry.LegacyId then
		return CrewCatalog.GetBaseInfo(productionEntry.LegacyId)
	end

	local variantKey, baseId = CrewCatalog.ParseVariantId(id)
	if variantKey ~= "Normal" then
		return CrewCatalog.GetOrBuildVariantInfo(baseId, variantKey)
	end

	return nil
end

function CrewCatalog.GetOrBuildVariantInfo(baseId, variantKey)
	local baseIdStr = tostring(baseId)
	if variantKey == "Normal" or variantKey == nil then
		return CrewCatalog.GetBaseInfo(baseIdStr)
	end

	local baseInfo = CrewCatalog.GetBaseInfo(baseIdStr)
	if not baseInfo then
		local productionEntry = getProductionEntry(baseIdStr)
		if productionEntry and productionEntry.LegacyId then
			baseInfo = CrewCatalog.GetBaseInfo(productionEntry.LegacyId)
		end
	end
	if not baseInfo then
		return nil
	end

	local finalId = CrewCatalog.MakeVariantId(baseIdStr, variantKey)
	local legacyVariantInfo = LegacyBrainrots[finalId]
	local variantInfo = getVariantConfig(variantKey)
	local mult = tonumber(variantInfo and variantInfo.IncomeMult) or 1
	local info = cloneShallow(if typeof(legacyVariantInfo) == "table" then legacyVariantInfo else baseInfo)
	local variantDisplay = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " ")) .. tostring(baseInfo.DisplayName or baseIdStr)

	info.Id = finalId
	info.LegacyId = finalId
	info.CrewMemberId = finalId
	info.CrewMemberName = variantDisplay
	info.DisplayName = variantDisplay
	info.Name = variantDisplay
	info.ModelName = baseInfo.ModelName
	info.IsVariant = true
	info.BaseId = baseIdStr
	info.Variant = variantKey
	info.RealCharacterName = baseInfo.RealCharacterName
	info.Arc = baseInfo.Arc
	info.CrewArc = baseInfo.CrewArc
	info.ModelNameVerified = baseInfo.ModelNameVerified
	info.MissingCrewModel = baseInfo.MissingCrewModel
	info.Income = tonumber(info.Income) or math.floor((tonumber(baseInfo.Income) or 0) * mult + 0.5)

	return info
end

function CrewCatalog.FindInfoByName(name)
	local rawName = tostring(name or "")
	if rawName == "" then
		return nil, nil
	end

	local direct = CrewCatalog.GetInfoById(rawName)
	if direct then
		return direct, rawName
	end

	for id, legacyInfo in pairs(LegacyBrainrots) do
		if typeof(legacyInfo) == "table" then
			local crewInfo = CrewCatalog.GetBaseInfo(id)
			if crewInfo then
				if tostring(crewInfo.Render or "") == rawName
					or tostring(crewInfo.Name or "") == rawName
					or tostring(crewInfo.DisplayName or "") == rawName
					or tostring(crewInfo.CrewMemberName or "") == rawName
					or tostring(crewInfo.RealCharacterName or "") == rawName
					or tostring(crewInfo.ModelName or "") == rawName
				then
					return crewInfo, tostring(id)
				end
			end
		end
	end

	return nil, nil
end

function CrewCatalog.GetBaseEntries()
	local entries = {}
	local productionEntries = CrewMembers.GetEntries()

	for _, entry in ipairs(productionEntries) do
		local legacyId = tostring(entry.LegacyId or "")
		local crewInfo = CrewCatalog.GetBaseInfo(legacyId)
		if crewInfo then
			entries[#entries + 1] = {
				Id = legacyId,
				Info = crewInfo,
			}
		end
	end

	return entries
end

return CrewCatalog
