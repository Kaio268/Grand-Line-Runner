local Module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewRegistry = require(Modules:WaitForChild("Crew"):WaitForChild("CrewRegistry"))
local VariantCfg = CrewCatalog.GetVariantConfig()
local CrewInstanceService = require(script.Parent:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(script.Parent:WaitForChild("CrewQuickSlotService"))
local TitleProgressService = require(script.Parent:WaitForChild("TitleProgressService"))

local function validName(name)
	if type(name) ~= "string" then return nil end
	if #name < 1 or #name > 80 then return nil end
	if name:find("%.") then return nil end
	return name
end

local function getVariantAndBaseName(fullName)
	fullName = tostring(fullName)

	for _, vKey in ipairs(VariantCfg.Order or {}) do
		if vKey ~= "Normal" then
			local v = (VariantCfg.Versions or {})[vKey]
			local prefix = tostring(v and v.Prefix or (vKey .. " "))
			if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
				local baseName = fullName:sub(#prefix + 1)
				return vKey, baseName
			end
		end
	end

	return "Normal", fullName
end

local function findModelFor(variantKey, baseName)
	local model = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
	return model and model:IsA("Model") and model or nil
end

local function getPlayerName(plr)
	return if typeof(plr) == "Instance" and plr:IsA("Player") then plr.Name else "unknown"
end

local function rejectGrant(plr, reason, detail)
	warn(string.format(
		"[AddCrewMember] grant rejected player=%s reason=%s%s",
		getPlayerName(plr),
		tostring(reason or "unknown"),
		if tostring(detail or "") ~= "" then " " .. tostring(detail) else ""
	))
	return false, tostring(reason or "unknown")
end

function Module:AddCrewMember(plr, crewMemberName, amount, options)
	if typeof(plr) ~= "Instance" or not plr:IsA("Player") then
		return rejectGrant(plr, "invalid_player")
	end

	local requestedCrewMemberName = crewMemberName
	crewMemberName = validName(crewMemberName)
	if not crewMemberName then
		return rejectGrant(plr, "invalid_crew_member_name", "requested=" .. tostring(requestedCrewMemberName))
	end

	local n = tonumber(amount)
	if not n then
		return rejectGrant(plr, "invalid_amount", "amount=" .. tostring(amount))
	end

	n = math.floor(n)
	if n <= 0 then
		if n == 0 then
			return true
		end
		return rejectGrant(plr, "non_positive_amount", "amount=" .. tostring(amount))
	end

	local canonicalCrewMemberName, resolvedInfo, legacyStorageName = CrewCatalog.ResolveCrewMemberId(crewMemberName)
	if resolvedInfo then
		crewMemberName = canonicalCrewMemberName
	end

	local variantKey, baseName = getVariantAndBaseName(crewMemberName)

	local model = findModelFor(variantKey, baseName)
	if not model then
		return rejectGrant(plr, "crew_model_unavailable", string.format(
			"requested=%s canonical=%s base=%s variant=%s",
			tostring(requestedCrewMemberName),
			tostring(crewMemberName),
			tostring(baseName),
			tostring(variantKey)
		))
	end

	local info = resolvedInfo or CrewCatalog.GetInfoById(crewMemberName) or CrewCatalog.GetInfoById(baseName)
	if not info then
		return rejectGrant(plr, "crew_info_missing", string.format(
			"requested=%s canonical=%s base=%s variant=%s",
			tostring(requestedCrewMemberName),
			tostring(crewMemberName),
			tostring(baseName),
			tostring(variantKey)
		))
	end

	options = if typeof(options) == "table" then options else {}
	if tostring(options.LegacyStorageName or "") ~= "" then
		legacyStorageName = tostring(options.LegacyStorageName)
	elseif legacyStorageName == "" and tostring(info.LegacyId or "") ~= "" then
		legacyStorageName = tostring(info.LegacyId)
	end

	local baseInfo = CrewCatalog.GetInfoById(baseName) or info
	local render = info.Render or ""
	local goldenRender = (baseInfo and (baseInfo.GoldenRender or baseInfo.Render)) or render
	local diamondRender = (baseInfo and (baseInfo.DiamondRender or baseInfo.Render)) or render
	local bypassQuickSlotCapacity = options.TutorialReward == true or options._QuickSlotCapacityReserved == true

	if not bypassQuickSlotCapacity then
		local canGain, _, _, _, capacityReason = CrewQuickSlotService.CanGainOrNotify(plr, crewMemberName, n, "AddCrewMember:" .. crewMemberName)
		if not canGain then
			return false, tostring(capacityReason or "crew_stack_capacity_full")
		end
	end

	if CrewInstanceService.IsInventoryWriteAuthorityEnabled() == true then
		local status = CrewInstanceService.ValidateInventoryMirrors(plr)
		if status == nil or status.Passed ~= true then
			local issues = if typeof(status) == "table" and typeof(status.Issues) == "table"
				then table.concat(status.Issues, ",")
				else "none"
			return rejectGrant(plr, "inventory_mirror_validation_failed", "issues=" .. issues)
		end
	end

	CrewInstanceService.EnsureInventoryMetadata(plr, crewMemberName, {
		StorageName = crewMemberName,
		LegacyStorageName = legacyStorageName,
		CrewMemberId = tostring(info.CrewMemberId or crewMemberName),
		DisplayName = tostring(info.DisplayName or info.CrewMemberName or info.Name or crewMemberName),
		ModelName = tostring(info.ModelName or baseName),
		BaseName = baseName,
		Variant = variantKey,
		Rarity = tostring(info.Rarity or "Common"),
		Income = tonumber(info.Income) or 0,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
	})
	local createdIds, createReason = CrewInstanceService.CreateInstances(plr, crewMemberName, n, {
		StorageName = crewMemberName,
		LegacyStorageName = legacyStorageName,
		CrewMemberId = tostring(info.CrewMemberId or crewMemberName),
		DisplayName = tostring(info.DisplayName or info.CrewMemberName or info.Name or crewMemberName),
		ModelName = tostring(info.ModelName or baseName),
		BaseName = baseName,
		Variant = variantKey,
		Rarity = tostring(info.Rarity or "Common"),
		Income = tonumber(info.Income) or 0,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
		Level = 1,
		CurrentXP = 0,
		TotalXP = math.max(0, math.floor(tonumber(options.TotalXP) or 0)),
		Source = tostring(options.Source or ""),
		DepthBand = tostring(options.DepthBand or ""),
		TutorialReward = options.TutorialReward == true,
		TutorialToken = tostring(options.TutorialToken or ""),
		GrandLineRushStarter = options.GrandLineRushStarter == true,
		_QuickSlotCapacityReserved = true,
	})
	if #createdIds ~= n then
		return rejectGrant(plr, tostring(createReason or "crew_instance_create_count_mismatch"), string.format(
			"requested=%s canonical=%s expected=%d created=%d",
			tostring(requestedCrewMemberName),
			tostring(crewMemberName),
			n,
			#createdIds
		))
	end

	TitleProgressService.RecordCrewGained(plr, {
		CrewName = crewMemberName,
		Amount = n,
		Rarity = tostring(info.Rarity or "Common"),
		Source = tostring(options.Source or ""),
		DepthBand = tostring(options.DepthBand or ""),
	})

	return true, createdIds
end

return Module
