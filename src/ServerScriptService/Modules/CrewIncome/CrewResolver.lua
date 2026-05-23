local Module = {}

function Module.Install(ctx)
	local CrewCatalog = ctx.CrewCatalog
	local CrewInstanceService = ctx.CrewInstanceService
	local crewRecordCache = ctx.crewRecordCache
	local CrewRegistry = ctx.CrewRegistry
	local DEBUG_TRACE = ctx.DEBUG_TRACE
	local function getCrewMemberCanonicalReadGate(...)
		return ctx.getCrewMemberCanonicalReadGate(...)
	end
	local VariantCfg = ctx.VariantCfg

	local function getVariantAndBaseName(fullName)
		fullName = tostring(fullName)

		for _, vKey in ipairs(VariantCfg.Order or {}) do
			if vKey ~= "Normal" then
				local v = (VariantCfg.Versions or {})[vKey]
				local prefix = tostring((v and v.Prefix) or (vKey .. " "))
				if prefix ~= "" and fullName:sub(1, #prefix) == prefix then
					local baseName = fullName:sub(#prefix + 1)
					return vKey, baseName, v
				end
			end
		end

		return "Normal", fullName, (VariantCfg.Versions or {}).Normal
	end

	local function resolveCanonicalCrewMemberId(itemName)
		local canonicalItemName, info = CrewCatalog.ResolveCanonicalCrewMemberId(itemName)
		if info then
			return canonicalItemName
		end
		return ""
	end

	local function findTemplateForName(crewMemberName)
		local canonicalName = resolveCanonicalCrewMemberId(crewMemberName)
		if canonicalName == "" then
			return nil
		end
		local variantKey, baseName = getVariantAndBaseName(canonicalName)

		local registryTemplate = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
		if registryTemplate and registryTemplate:IsA("Model") then
			return registryTemplate
		end

		registryTemplate = CrewRegistry.GetTemplateWithFallback(canonicalName, "Normal")
		if registryTemplate and registryTemplate:IsA("Model") then
			return registryTemplate
		end

		return nil
	end

	local function findCatalogInfoByName(crewMemberName)
		local crewInfo, crewId = CrewCatalog.FindInfoByName(crewMemberName)
		if crewInfo then
			return crewInfo, crewId
		end

		return nil, nil
	end

	local function hasInventoryCrewMemberEntry(player, itemName)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return false
		end

		if typeof(itemName) ~= "string" or itemName == "" then
			return false
		end
		local canonicalItemName = resolveCanonicalCrewMemberId(itemName)
		if canonicalItemName == "" then
			return false
		end

		local crewInventory = CrewInstanceService.GetCrewInventory(player)
		if typeof(crewInventory) == "table" and typeof(crewInventory.ById) == "table" then
			for _, instanceData in pairs(crewInventory.ById) do
				if typeof(instanceData) == "table"
					and (
						tostring(instanceData.CrewMemberId or instanceData.StorageName or "") == canonicalItemName
						or tostring(instanceData.LegacyStorageName or "") == itemName
					)
				then
					return true
				end
			end
		end

		return false
	end

	local function getInventoryCrewMemberMetadata(player, itemName)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return nil, nil
		end

		if typeof(itemName) ~= "string" or itemName == "" then
			return nil, nil
		end
		local canonicalItemName = resolveCanonicalCrewMemberId(itemName)
		if canonicalItemName == "" then
			return nil, nil
		end

		local crewInventory = CrewInstanceService.GetCrewInventory(player)
		if typeof(crewInventory) == "table" and typeof(crewInventory.ById) == "table" then
			for _, instanceData in pairs(crewInventory.ById) do
				if typeof(instanceData) == "table"
					and (
						tostring(instanceData.CrewMemberId or instanceData.StorageName or "") == canonicalItemName
						or tostring(instanceData.LegacyStorageName or "") == itemName
					)
				then
					local baseName = tostring(instanceData.BaseName or "")
					local variantKey = tostring(instanceData.Variant or "")
					if baseName ~= "" then
						if variantKey == "" then
							variantKey = "Normal"
						end
						return variantKey, baseName
					end
				end
			end
		end

		return nil, nil
	end

	local function clearCrewRecordCache(player)
		if player ~= nil then
			crewRecordCache[player] = nil
			return
		end

		for cachedPlayer in pairs(crewRecordCache) do
			crewRecordCache[cachedPlayer] = nil
		end
	end

	local function readCachedCrewRecord(player, rawName)
		local playerCache = crewRecordCache[player]
		if playerCache == nil then
			return nil, false
		end

		local cached = playerCache[rawName]
		if cached == nil then
			return nil, false
		end
		if cached == false then
			return nil, true
		end
		return cached, true
	end

	local function writeCachedCrewRecord(player, rawName, record)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return record
		end

		local playerCache = crewRecordCache[player]
		if playerCache == nil then
			playerCache = {}
			crewRecordCache[player] = playerCache
		end
		playerCache[rawName] = record or false
		return record
	end

	local function resolveCrewMemberRecord(player, crewMemberName)
		local rawName = tostring(crewMemberName or "")
		if rawName == "" then
			return nil
		end

		local cachedRecord, foundCachedRecord = readCachedCrewRecord(player, rawName)
		if foundCachedRecord then
			return cachedRecord
		end

		local candidates = {}
		local seen = {}

		local function pushCandidate(itemName)
			if typeof(itemName) ~= "string" or itemName == "" or seen[itemName] then
				return
			end
			seen[itemName] = true
			table.insert(candidates, itemName)
		end

		pushCandidate(rawName)
		pushCandidate(resolveCanonicalCrewMemberId(rawName))

		local invVariant, invBase = getInventoryCrewMemberMetadata(player, rawName)
		if invBase then
			pushCandidate(CrewRegistry.MakeVariantId(invBase, invVariant))
		end

		local parsedVariant, parsedBase = getVariantAndBaseName(rawName)
		pushCandidate(CrewRegistry.MakeVariantId(parsedBase, parsedVariant))
		pushCandidate(parsedBase)

		local legacyInfo, legacyId = findCatalogInfoByName(rawName)
		if legacyId then
			pushCandidate(legacyId)
		end

		for _, candidateName in ipairs(candidates) do
			candidateName = resolveCanonicalCrewMemberId(candidateName)
			if candidateName == "" then
				continue
			end
			local variantKey, baseName = getVariantAndBaseName(candidateName)
			local template, usedVariant = CrewRegistry.GetTemplateWithFallback(baseName, variantKey)
			local finalVariant = usedVariant or variantKey or "Normal"
			local info = CrewRegistry.GetOrBuildVariantInfo(baseName, finalVariant)

			if template or info then
				local canonicalName = CrewRegistry.MakeVariantId(baseName, finalVariant)
				local storageName = rawName

					if hasInventoryCrewMemberEntry(player, candidateName) then
						storageName = candidateName
					elseif hasInventoryCrewMemberEntry(player, canonicalName) or not hasInventoryCrewMemberEntry(player, rawName) then
						storageName = canonicalName
					end

				return writeCachedCrewRecord(player, rawName, {
					RawName = rawName,
					CanonicalName = canonicalName,
					StorageName = storageName,
					BaseName = baseName,
					VariantKey = finalVariant,
					Template = template,
					Info = info or legacyInfo,
				})
			end
		end

		if legacyInfo then
			return writeCachedCrewRecord(player, rawName, {
				RawName = rawName,
				CanonicalName = tostring(legacyId or rawName),
				StorageName = hasInventoryCrewMemberEntry(player, rawName) and rawName or tostring(legacyId or rawName),
				BaseName = tostring(legacyId or rawName),
				VariantKey = parsedVariant,
				Template = findTemplateForName(tostring(legacyId or rawName)),
				Info = legacyInfo,
			})
		end

		return writeCachedCrewRecord(player, rawName, nil)
	end

	local function findCrewMemberInfoByName(crewMemberName, player)
		local resolved = resolveCrewMemberRecord(player, crewMemberName)
		if resolved and resolved.Info then
			return resolved.Info, resolved.CanonicalName
		end

		return findCatalogInfoByName(crewMemberName)
	end

	local function getLegacyStandStatusDisplayName(player, crewMemberName)
		local resolved = resolveCrewMemberRecord(player, crewMemberName)
		local info = resolved and resolved.Info or findCrewMemberInfoByName(crewMemberName, player)
		return info and tostring(info.Name or info.DisplayName or resolved and resolved.CanonicalName or crewMemberName)
			or tostring(crewMemberName)
	end

	local function resolveStandStatusDisplayName(player, crewMemberName)
		local fallbackDisplayName = getLegacyStandStatusDisplayName(player, crewMemberName)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return fallbackDisplayName, nil
		end

		local gate = getCrewMemberCanonicalReadGate()
		if typeof(gate) ~= "table" or typeof(gate.ResolveStandStatusDisplayName) ~= "function" then
			return fallbackDisplayName, nil
		end

		local ok, value, result = pcall(function()
			return gate.ResolveStandStatusDisplayName(player, crewMemberName, {
				Player = player,
				SkipLog = true,
			})
		end)
		if not ok then
			if DEBUG_TRACE then
				warn(string.format(
					"[CrewMemberStandStatusHelper] fallback player=%s item=%s reason=%s",
					player.Name,
					tostring(crewMemberName),
					tostring(value)
				))
			end
			return fallbackDisplayName, nil
		end

		local displayName = tostring(value or "")
		if displayName == "" then
			return fallbackDisplayName, result
		end

		return displayName, result
	end

	local function resolveIncomeStatusReadAuthorityDisplayName(player, standName)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return nil, nil
		end

		local gate = getCrewMemberCanonicalReadGate()
		if typeof(gate) ~= "table" or typeof(gate.ResolveIncomeStatusReadAuthority) ~= "function" then
			return nil, nil
		end

		local ok, _, result = pcall(function()
			return gate.ResolveIncomeStatusReadAuthority(player, standName, {
				Player = player,
				SkipLog = true,
			})
		end)
		if not ok or typeof(result) ~= "table" then
			if DEBUG_TRACE then
				warn(string.format(
					"[CrewMemberIncomeStatusReadAuthority] fallback player=%s stand=%s reason=%s",
					player.Name,
					tostring(standName),
					tostring(_)
				))
			end
			return nil, nil
		end

		local fallbackReason = tostring(result.FallbackReason or "")
		local readGateReason = tostring(result.ReadGateReason or "")
		local readAuthorityDisabled = fallbackReason == "read_authority_disabled"
			or fallbackReason == "income_status_read_authority_disabled"
			or readGateReason == "read_authority_disabled"
			or readGateReason == "income_status_read_authority_disabled"
		if readAuthorityDisabled then
			return nil, nil
		end

		local displayName = tostring(result.DisplayName or "")
		if displayName == "" then
			return nil, result
		end
		return displayName, result
	end

	local function resolveIncomeStatusDisplayName(player, standName, crewMemberName)
		local fallbackDisplayName = getLegacyStandStatusDisplayName(player, crewMemberName)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return fallbackDisplayName, nil
		end

		if tostring(standName or "") ~= "" then
			local authorityDisplayName, authorityResult = resolveIncomeStatusReadAuthorityDisplayName(player, standName)
			if authorityResult ~= nil then
				return authorityDisplayName or fallbackDisplayName, authorityResult
			end
		end

		local gate = getCrewMemberCanonicalReadGate()
		if typeof(gate) ~= "table" or typeof(gate.ResolveIncomeStatusDisplayName) ~= "function" then
			return fallbackDisplayName, nil
		end

		local ok, value, result = pcall(function()
			return gate.ResolveIncomeStatusDisplayName(player, crewMemberName, {
				Player = player,
				SkipLog = true,
			})
		end)
		if not ok then
			if DEBUG_TRACE then
				warn(string.format(
					"[CrewMemberIncomeStatusHelper] fallback player=%s item=%s reason=%s",
					player.Name,
					tostring(crewMemberName),
					tostring(value)
				))
			end
			return fallbackDisplayName, nil
		end

		local displayName = tostring(value or "")
		if displayName == "" then
			return fallbackDisplayName, result
		end

		return displayName, result
	end

	local function resolveIncomeToastDisplayName(player, crewMemberName)
		local fallbackDisplayName = getLegacyStandStatusDisplayName(player, crewMemberName)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return fallbackDisplayName, nil
		end

		local gate = getCrewMemberCanonicalReadGate()
		if typeof(gate) ~= "table" or typeof(gate.ResolveIncomeToastDisplayName) ~= "function" then
			return fallbackDisplayName, nil
		end

		local ok, value, result = pcall(function()
			return gate.ResolveIncomeToastDisplayName(player, crewMemberName, {
				Player = player,
				SkipLog = true,
			})
		end)
		if not ok then
			if DEBUG_TRACE then
				warn(string.format(
					"[CrewMemberIncomeToastHelper] fallback player=%s item=%s reason=%s",
					player.Name,
					tostring(crewMemberName),
					tostring(value)
				))
			end
			return fallbackDisplayName, nil
		end

		local displayName = tostring(value or "")
		if displayName == "" then
			return fallbackDisplayName, result
		end

		return displayName, result
	end

	local function buildIncomeToastDisplayPayload(player, crewMemberName)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return nil
		end

		local legacyIdentity = tostring(crewMemberName or "")
		if legacyIdentity == "" then
			return nil
		end

		local gate = getCrewMemberCanonicalReadGate()
		if typeof(gate) ~= "table" or typeof(gate.GetFlags) ~= "function" then
			return nil
		end

		local flags = gate.GetFlags()
		if flags.CrewMemberCanaryGameplayHelperReadsEnabled ~= true
			or flags.CrewMemberCanaryIncomeToastHelperReadEnabled ~= true
			or flags.CrewMemberCanaryGameplayReadsEnabled == true
			or flags.CrewMemberCanonicalReadEnabled == true
		then
			return nil
		end

		local fallbackDisplayName = getLegacyStandStatusDisplayName(player, legacyIdentity)
		local displayName, result = resolveIncomeToastDisplayName(player, legacyIdentity)
		if typeof(result) ~= "table" then
			return {
				DisplayName = tostring(fallbackDisplayName or legacyIdentity),
				LegacyIdentity = legacyIdentity,
				UsedCanonical = false,
				FallbackReason = "helper_result_missing",
				Path = "gameplay.helper.income_toast_display_name",
				IsAuthoritative = false,
			}
		end

		return {
			DisplayName = tostring(displayName or fallbackDisplayName or legacyIdentity),
			LegacyIdentity = tostring(result.LegacyIdentity or legacyIdentity),
			UsedCanonical = result.UsedCanonical == true,
			FallbackReason = result.FallbackReason,
			Path = tostring(result.Path or "gameplay.helper.income_toast_display_name"),
			IsAuthoritative = false,
		}
	end

	local function buildIncomeStatusDisplayDescriptor(result, fallbackDisplayName, crewMemberName)
		if typeof(result) ~= "table" then
			return {
				DisplayName = tostring(fallbackDisplayName or crewMemberName or ""),
				UsedCanonical = false,
				FallbackReason = "helper_result_missing",
				LegacyIdentity = tostring(crewMemberName or ""),
				IsAuthoritative = false,
				Path = "gameplay.helper.income_status_display_name",
			}
		end

		return {
			DisplayName = tostring(result.DisplayName or result.Value or fallbackDisplayName or crewMemberName or ""),
			UsedCanonical = result.UsedCanonical == true,
			FallbackReason = result.FallbackReason,
			LegacyValue = result.LegacyValue,
			CanonicalValue = result.CanonicalValue,
			LegacyIdentity = tostring(result.LegacyIdentity or crewMemberName or ""),
			Path = tostring(result.Path or "gameplay.helper.income_status_display_name"),
			IsAuthoritative = result.IsAuthoritative == true,
			IsAuthoritativeRead = result.IsAuthoritativeRead == true,
			IsMutationAuthority = result.IsMutationAuthority == true,
			Source = result.Source,
			AuthorityMode = result.AuthorityMode,
			ValidationAgeSeconds = tonumber(result.ValidationAgeSeconds) or -1,
		}
	end

	local VariantOrder = { "Normal", "Golden", "Diamond" }
	local VariantPrefix = {
		Normal = "",
		Golden = "Golden ",
		Diamond = "Diamond ",
	}

	local function startsWith(s, pref)
		return s:sub(1, #pref) == pref
	end

	local function detectVariant(text)
		text = tostring(text or "")
		for _, v in ipairs(VariantOrder) do
			if v ~= "Normal" then
				local pref = tostring(VariantPrefix[v] or (v .. " "))
				if pref ~= "" and startsWith(text, pref) then
					return v
				end
				local alt = v .. " "
				if startsWith(text, alt) then
					return v
				end
			end
		end
		return "Normal"
	end

	local function stripVariantPrefix(text, variantKey)
		text = tostring(text or "")
		if not variantKey or variantKey == "Normal" then
			return text
		end
		local pref = tostring(VariantPrefix[variantKey] or (variantKey .. " "))
		if pref ~= "" and startsWith(text, pref) then
			local out = text:sub(#pref + 1)
			if out ~= "" then
				return out
			end
		end
		local alt = variantKey .. " "
		if startsWith(text, alt) then
			local out = text:sub(#alt + 1)
			if out ~= "" then
				return out
			end
		end
		return text
	end


	ctx.buildIncomeStatusDisplayDescriptor = buildIncomeStatusDisplayDescriptor
	ctx.buildIncomeToastDisplayPayload = buildIncomeToastDisplayPayload
	ctx.clearCrewRecordCache = clearCrewRecordCache
	ctx.detectVariant = detectVariant
	ctx.findCatalogInfoByName = findCatalogInfoByName
	ctx.findCrewMemberInfoByName = findCrewMemberInfoByName
	ctx.findTemplateForName = findTemplateForName
	ctx.getInventoryCrewMemberMetadata = getInventoryCrewMemberMetadata
	ctx.getLegacyStandStatusDisplayName = getLegacyStandStatusDisplayName
	ctx.getVariantAndBaseName = getVariantAndBaseName
	ctx.hasInventoryCrewMemberEntry = hasInventoryCrewMemberEntry
	ctx.readCachedCrewRecord = readCachedCrewRecord
	ctx.resolveCanonicalCrewMemberId = resolveCanonicalCrewMemberId
	ctx.resolveCrewMemberRecord = resolveCrewMemberRecord
	ctx.resolveIncomeStatusDisplayName = resolveIncomeStatusDisplayName
	ctx.resolveIncomeStatusReadAuthorityDisplayName = resolveIncomeStatusReadAuthorityDisplayName
	ctx.resolveIncomeToastDisplayName = resolveIncomeToastDisplayName
	ctx.resolveStandStatusDisplayName = resolveStandStatusDisplayName
	ctx.startsWith = startsWith
	ctx.stripVariantPrefix = stripVariantPrefix
	ctx.VariantOrder = VariantOrder
	ctx.VariantPrefix = VariantPrefix
	ctx.writeCachedCrewRecord = writeCachedCrewRecord
end

return Module
