local Module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(Modules:WaitForChild("Crew"):WaitForChild("CrewIncomeBalance"))
local CrewRegistry = require(Modules:WaitForChild("Crew"):WaitForChild("CrewRegistry"))
local CrewInstanceService = require(script.Parent:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(script.Parent:WaitForChild("CrewQuickSlotService"))
local TitleProgressService = require(script.Parent:WaitForChild("TitleProgressService"))

local function validName(name)
	if type(name) ~= "string" then return nil end
	if #name < 1 or #name > 80 then return nil end
	if name:find("%.") then return nil end
	return name
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

local function buildGrantDescriptor(plr, crewMemberName, amount, options)
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
			return true, {
				NoOp = true,
				Amount = 0,
				CrewMemberName = crewMemberName,
				RequestedCrewMemberName = requestedCrewMemberName,
			}
		end
		return rejectGrant(plr, "non_positive_amount", "amount=" .. tostring(amount))
	end

	options = if typeof(options) == "table" then options else {}

	local canonicalCrewMemberName, resolvedInfo, legacyStorageName = CrewCatalog.ResolveCrewMemberId(crewMemberName)
	if resolvedInfo then
		crewMemberName = canonicalCrewMemberName
	end

	local displayInfo = CrewCatalog.GetDisplayInfo(crewMemberName, resolvedInfo)
	local variantKey = tostring(displayInfo.Variant or "Normal")
	local baseName = tostring(displayInfo.BaseId or crewMemberName)
	local releaseInfo = resolvedInfo or CrewCatalog.GetInfoById(baseName)

	if releaseInfo and CrewCatalog.IsPubliclyObtainable(releaseInfo) ~= true and options.AllowUnreleased ~= true then
		return rejectGrant(plr, "crew_member_unreleased", string.format(
			"requested=%s canonical=%s base=%s variant=%s source=%s",
			tostring(requestedCrewMemberName),
			tostring(crewMemberName),
			tostring(baseName),
			tostring(variantKey),
			tostring(options.Source or "")
		))
	end

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
	local cleanDisplayName = tostring(displayInfo.DisplayName or info.DisplayName or info.CrewMemberName or info.Name or crewMemberName)
	local grantRarity = tostring(info.Rarity or "Common")
	local grantIncome = tonumber(info.Income) or 0
	local grantBaseIncomeRoll = nil
	local grantIncomeRollVersion = nil
	local rarityOverride = tostring(options.RarityOverride or "")
	if rarityOverride ~= "" then
		grantRarity = CrewIncomeBalance.NormalizeRarity(rarityOverride)
		grantBaseIncomeRoll = CrewIncomeBalance.GetBaseIncomeRangeMidpoint(grantRarity)
		grantIncomeRollVersion = CrewIncomeBalance.GetIncomeRollVersion()
		grantIncome = CrewIncomeBalance.ComputeIncome(grantBaseIncomeRoll, variantKey, 1, grantRarity)
	end

	local metadata = {
		StorageName = crewMemberName,
		LegacyStorageName = legacyStorageName,
		CrewMemberId = tostring(info.CrewMemberId or crewMemberName),
		DisplayName = cleanDisplayName,
		ModelName = tostring(info.ModelName or baseName),
		BaseName = baseName,
		Variant = variantKey,
		Rarity = grantRarity,
		BaseIncomeRoll = grantBaseIncomeRoll,
		IncomeRollVersion = grantIncomeRollVersion,
		Income = grantIncome,
		Render = render,
		GoldenRender = goldenRender,
		DiamondRender = diamondRender,
	}
	local instanceOverrides = {
		StorageName = crewMemberName,
		LegacyStorageName = legacyStorageName,
		CrewMemberId = tostring(info.CrewMemberId or crewMemberName),
		DisplayName = cleanDisplayName,
		ModelName = tostring(info.ModelName or baseName),
		BaseName = baseName,
		Variant = variantKey,
		Rarity = grantRarity,
		BaseIncomeRoll = grantBaseIncomeRoll,
		IncomeRollVersion = grantIncomeRollVersion,
		Income = grantIncome,
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
	}

	return true, {
		RequestedCrewMemberName = requestedCrewMemberName,
		CrewMemberName = crewMemberName,
		Amount = n,
		BaseName = baseName,
		Variant = variantKey,
		Rarity = grantRarity,
		Income = grantIncome,
		LegacyStorageName = legacyStorageName,
		DisplayName = cleanDisplayName,
		BypassQuickSlotCapacity = bypassQuickSlotCapacity,
		Metadata = metadata,
		InstanceOverrides = instanceOverrides,
		Source = tostring(options.Source or ""),
		DepthBand = tostring(options.DepthBand or ""),
	}
end

function Module.BuildGrantDescriptor(plr, crewMemberName, amount, options)
	return buildGrantDescriptor(plr, crewMemberName, amount, options)
end

function Module:AddCrewMember(plr, crewMemberName, amount, options)
	options = if typeof(options) == "table" then options else {}
	local descriptorOk, descriptorOrReason = buildGrantDescriptor(plr, crewMemberName, amount, options)
	if descriptorOk ~= true then
		return false, descriptorOrReason
	end

	local descriptor = descriptorOrReason
	if descriptor.NoOp == true then
		return true
	end
	local n = descriptor.Amount
	crewMemberName = descriptor.CrewMemberName

	if not descriptor.BypassQuickSlotCapacity then
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

	CrewInstanceService.EnsureInventoryMetadata(plr, crewMemberName, descriptor.Metadata)
	local createdIds, createReason = CrewInstanceService.CreateInstances(plr, crewMemberName, n, descriptor.InstanceOverrides)
	if #createdIds ~= n then
		return rejectGrant(plr, tostring(createReason or "crew_instance_create_count_mismatch"), string.format(
			"requested=%s canonical=%s expected=%d created=%d",
			tostring(descriptor.RequestedCrewMemberName),
			tostring(crewMemberName),
			n,
			#createdIds
		))
	end

	TitleProgressService.RecordCrewGained(plr, {
		CrewName = crewMemberName,
		Amount = n,
		Rarity = descriptor.Rarity,
		Source = descriptor.Source,
		DepthBand = descriptor.DepthBand,
	})

	return true, createdIds
end

return Module
