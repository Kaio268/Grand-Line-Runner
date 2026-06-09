local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local CrewModules = Modules:WaitForChild("Crew")

local CrewCatalog = require(CrewModules:WaitForChild("CrewCatalog"))
local CrewIncomeBalance = require(CrewModules:WaitForChild("CrewIncomeBalance"))
local CrewMembers = require(CrewModules:WaitForChild("CrewMembers"))
local CrewRegistry = require(CrewModules:WaitForChild("CrewRegistry"))
local CrewVariants = require(Configs:WaitForChild("CrewVariants"))
local PlotUpgradeConfig = require(Configs:WaitForChild("PlotUpgrade"))
local ShipVisuals = require(Configs:WaitForChild("ShipVisuals"))

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local AddCrewMember = require(script.Parent:WaitForChild("AddCrewMember"))
local CrewInstanceService = require(script.Parent:WaitForChild("CrewInstanceService"))
local ShipRuntimeService = require(script.Parent:WaitForChild("ShipRuntimeService"))
local ShipRuntimeSignals = require(script.Parent:WaitForChild("ShipRuntimeSignals"))
local ShipSlotService = require(script.Parent:WaitForChild("ShipSlotService"))

local AdminFillShipService = {}

local PLAYER_DATA_READY_ATTRIBUTE = "PlayerDataReady"
local DATA_READY_TIMEOUT_SECONDS = 8
local MAX_OPERATION_CAP = 64
local MUTATION_BATCH_SIZE = 5
local MUTATION_BATCH_YIELD_SECONDS = 0.03
local RUN_TIMEOUT_SECONDS = 45
local RUN_WAIT_STEP_SECONDS = 0.1

local rng = Random.new()
local activeRunsByUserId = {}

local function cleanText(value, limit)
	local text = tostring(value or ""):gsub("\r", ""):gsub("\n", " ")
	text = text:match("^%s*(.-)%s*$") or ""
	if limit and #text > limit then
		text = text:sub(1, limit)
	end
	return text
end

local function normalizeToken(value)
	return string.lower(cleanText(value, 80)):gsub("[%s_%-%./]+", "")
end

local function getPlayerLabel(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return "unknown(0)"
	end
	return string.format("%s(%d)", player.Name, player.UserId)
end

local function makeFailure(message, reason, extras)
	local result = if typeof(extras) == "table" then table.clone(extras) else {}
	result.Success = false
	result.Message = tostring(message or "Fill Ship failed.")
	result.Reason = tostring(reason or "unknown")
	return result
end

local function isSelfMode(value)
	local token = normalizeToken(value)
	return token == "" or token == "self" or token == "me" or token == "myself"
end

local function findOnlineTarget(adminPlayer, payload)
	local targetMode = tostring(payload.TargetMode or payload.TargetSelection or payload.TargetScope or "")
	local targetValue = payload.TargetUserId or payload.Target or payload.TargetText or payload.Player or payload.TargetPlayer
	local targetText = cleanText(targetValue, 80)

	if isSelfMode(targetMode) or normalizeToken(targetText) == "self" then
		return adminPlayer, "self"
	end

	if targetText == "" then
		return nil, "target_required"
	end

	local numericUserId = tonumber(targetText)
	if numericUserId then
		local target = Players:GetPlayerByUserId(math.floor(numericUserId))
		return target, if target then "user_id" else "target_offline"
	end

	local normalizedTarget = string.lower(targetText)
	for _, player in ipairs(Players:GetPlayers()) do
		if string.lower(player.Name) == normalizedTarget or string.lower(player.DisplayName) == normalizedTarget then
			return player, "name"
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local name = string.lower(player.Name)
		local displayName = string.lower(player.DisplayName)
		if name:sub(1, #normalizedTarget) == normalizedTarget or displayName:sub(1, #normalizedTarget) == normalizedTarget then
			return player, "partial_name"
		end
	end

	return nil, "target_offline"
end

local function waitForTargetDataReady(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return false, "target_offline"
	end

	if typeof(DataManager.WaitUntilReady) == "function" then
		if not DataManager:WaitUntilReady(player, DATA_READY_TIMEOUT_SECONDS) then
			return false, "data_manager_not_ready"
		end
	elseif typeof(DataManager.IsReady) == "function" and not DataManager:IsReady(player) then
		return false, "data_manager_not_ready"
	end

	local deadline = os.clock() + DATA_READY_TIMEOUT_SECONDS
	while player.Parent == Players and os.clock() < deadline do
		if player:GetAttribute(PLAYER_DATA_READY_ATTRIBUTE) == true then
			return true
		end
		task.wait(0.1)
	end

	return player.Parent == Players and player:GetAttribute(PLAYER_DATA_READY_ATTRIBUTE) == true, "player_data_not_ready"
end

local function readNumberValueObject(parent, childName)
	local child = parent and parent:FindFirstChild(childName)
	if child and child:IsA("ValueBase") then
		return tonumber(child.Value)
	end
	return nil
end

local function getTargetShipProgress(player)
	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
	local leaderstats = player:FindFirstChild("leaderstats")
	local rawUpgrade = readNumberValueObject(hiddenLeaderstats, PlotUpgradeConfig.InternalStatName or "PlotUpgrade")
	local rebirths = readNumberValueObject(leaderstats, "Rebirths")

	if rawUpgrade == nil then
		rawUpgrade = tonumber(DataManager:GetValue(player, "HiddenLeaderstats." .. tostring(PlotUpgradeConfig.InternalStatName or "PlotUpgrade"))) or 0
	end
	if rebirths == nil then
		rebirths = tonumber(DataManager:GetValue(player, "leaderstats.Rebirths")) or 0
	end

	rawUpgrade = PlotUpgradeConfig.ClampLevel(rawUpgrade)
	rebirths = math.max(0, math.floor(tonumber(rebirths) or 0))
	local effectiveLevel = PlotUpgradeConfig.GetEffectiveLevel(rawUpgrade, rebirths)
	local capacity = math.min(MAX_OPERATION_CAP, ShipVisuals.GetNormalCrewSlotsForUpgradeLevel(effectiveLevel))

	return rawUpgrade, rebirths, effectiveLevel, capacity
end

local function ensureActiveShip(player)
	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if activeShip and activeShip.Parent then
		return activeShip, "existing"
	end

	local refreshed = ShipRuntimeService.RefreshPlayerShip(player, {
		Reason = "admin_fill_ship_prepare",
		ForceDataReady = true,
	})
	if refreshed == true and typeof(ShipRuntimeService.WaitForShipFinalized) == "function" then
		ShipRuntimeService.WaitForShipFinalized(player, ShipRuntimeService.GetCrewVisualGeneration(player), 3)
	end

	activeShip = ShipRuntimeService.GetActiveShip(player)
	if activeShip and activeShip.Parent then
		return activeShip, "refreshed"
	end

	return nil, "active_ship_unavailable"
end

local function normalizeFillMode(value)
	local token = normalizeToken(value)
	if token == "replaceall" or token == "replaceallshipslots" or token == "all" or token == "replace" then
		return "ReplaceAll"
	end
	return "EmptyOnly"
end

local function getValidRarities()
	local rarities = {}
	local seen = {}
	for _, rarity in ipairs(CrewMembers.RarityOrder or {}) do
		local normalized = CrewIncomeBalance.NormalizeRarity(rarity)
		if not seen[normalized] then
			seen[normalized] = true
			rarities[#rarities + 1] = normalized
		end
	end
	if #rarities == 0 then
		rarities[1] = "Common"
	end
	return rarities
end

local function normalizeRarityChoice(value)
	local raw = cleanText(value, 40)
	if raw == "" or normalizeToken(raw) == "random" then
		return "Random"
	end

	local normalizedRaw = CrewIncomeBalance.NormalizeRarity(raw)
	for _, rarity in ipairs(getValidRarities()) do
		if string.lower(rarity) == string.lower(raw) or rarity == normalizedRaw then
			return rarity
		end
	end

	return nil, "invalid_rarity"
end

local function normalizeVariantChoice(value)
	local raw = cleanText(value, 40)
	if raw == "" or normalizeToken(raw) == "random" then
		return "Random"
	end

	for _, variant in ipairs(CrewVariants.Order or {}) do
		if string.lower(tostring(variant)) == string.lower(raw) then
			return tostring(variant)
		end
	end

	local normalized = CrewIncomeBalance.NormalizeVariant(raw)
	for _, variant in ipairs(CrewVariants.Order or {}) do
		if normalized == tostring(variant) then
			return normalized
		end
	end

	return nil, "invalid_variant"
end

local function chooseRandomVariant()
	local variants = CrewVariants.Order or { "Normal" }
	local totalWeight = 0
	for _, variant in ipairs(variants) do
		local config = (CrewVariants.Versions or {})[variant]
		totalWeight += math.max(0, tonumber(config and config.Chance) or 0)
	end
	if totalWeight <= 0 then
		return tostring(variants[rng:NextInteger(1, #variants)] or "Normal")
	end

	local roll = rng:NextNumber(0, totalWeight)
	local cursor = 0
	for _, variant in ipairs(variants) do
		local config = (CrewVariants.Versions or {})[variant]
		cursor += math.max(0, tonumber(config and config.Chance) or 0)
		if roll <= cursor then
			return tostring(variant)
		end
	end

	return tostring(variants[#variants] or "Normal")
end

local function isVisualVariant(value)
	local variant = tostring(value or "")
	return variant == "Golden" or variant == "Diamond"
end

local function resolveSpecificCrewBase(crewText)
	local requested = cleanText(crewText, 80)
	if requested == "" or normalizeToken(requested) == "random" then
		return nil, "random"
	end

	local canonicalId, info = CrewCatalog.ResolveCrewMemberId(requested)
	if not info then
		local foundInfo, foundId = CrewCatalog.FindInfoByName(requested)
		info = foundInfo
		canonicalId = foundId
	end
	if not info then
		return nil, "invalid_crew"
	end
	if CrewCatalog.IsPubliclyObtainable(info) ~= true then
		return nil, "crew_unreleased"
	end

	local displayInfo = CrewCatalog.GetDisplayInfo(canonicalId, info)
	local baseId = tostring(displayInfo.BaseId or info.BaseId or info.CrewMemberBaseId or info.CrewMemberId or canonicalId or "")
	if baseId == "" then
		return nil, "invalid_crew_base"
	end

	return baseId
end

local function getCatalogBaseRarity(baseId)
	baseId = tostring(baseId or "")
	if baseId == "" then
		return nil
	end

	for _, entry in ipairs(CrewCatalog.GetReleasedBaseEntries()) do
		if tostring(entry.Id or "") == baseId then
			local info = if typeof(entry.Info) == "table" then entry.Info else {}
			return CrewIncomeBalance.NormalizeRarity(info.Rarity)
		end
	end

	local _, info = CrewCatalog.ResolveCrewMemberId(baseId)
	if info and CrewCatalog.IsPubliclyObtainable(info) == true then
		return CrewIncomeBalance.NormalizeRarity(info.Rarity)
	end

	return nil
end

local function hasCrewTemplate(baseId, variant)
	local model = CrewRegistry.GetTemplateWithFallback(tostring(baseId or ""), tostring(variant or "Normal"))
	return model and model:IsA("Model")
end

local function resolveCrewTemplateVariant(baseId, variant)
	local requestedVariant = tostring(variant or "Normal")
	local model, usedVariant = CrewRegistry.GetTemplateWithFallback(tostring(baseId or ""), requestedVariant)
	return model and model:IsA("Model"), tostring(usedVariant or ""), isVisualVariant(requestedVariant)
		and tostring(usedVariant or "") ~= ""
		and tostring(usedVariant or "") ~= requestedVariant
end

local function getEligibleBasePool(variant, rarityChoice, cache)
	local normalizedRarity = if rarityChoice == "Random" then "Random" else CrewIncomeBalance.NormalizeRarity(rarityChoice)
	local cacheKey = tostring(variant or "Normal") .. ":" .. tostring(normalizedRarity)
	cache[cacheKey] = cache[cacheKey] or {}
	if cache[cacheKey].Built == true then
		return cache[cacheKey].Pool
	end

	local pool = {}
	for _, entry in ipairs(CrewCatalog.GetReleasedBaseEntries()) do
		local baseId = tostring(entry.Id or "")
		local info = if typeof(entry.Info) == "table" then entry.Info else {}
		local naturalRarity = CrewIncomeBalance.NormalizeRarity(info.Rarity)
		if
			baseId ~= ""
			and (normalizedRarity == "Random" or naturalRarity == normalizedRarity)
			and hasCrewTemplate(baseId, variant)
		then
			pool[#pool + 1] = {
				BaseId = baseId,
				Rarity = naturalRarity,
			}
		end
	end
	table.sort(pool, function(left, right)
		return tostring(left.BaseId) < tostring(right.BaseId)
	end)

	cache[cacheKey].Built = true
	cache[cacheKey].Pool = pool
	return pool
end

local function buildCrewSpec(options, poolCache)
	local variant = if options.VariantChoice == "Random" then chooseRandomVariant() else options.VariantChoice
	local baseId = options.SpecificBaseId
	local rarityChoice = tostring(options.RarityChoice or "Random")
	local rarityFilter = if rarityChoice == "Random" then "Random" else CrewIncomeBalance.NormalizeRarity(rarityChoice)
	local poolSize = nil
	local naturalRarity = nil

	if not baseId then
		local pool = getEligibleBasePool(variant, rarityFilter, poolCache)
		poolSize = #pool
		if #pool == 0 then
			return nil, if rarityFilter == "Random"
				then "no_eligible_crew_for_variant:" .. tostring(variant)
				else "no_eligible_crew_for_rarity:" .. tostring(rarityFilter)
		end
		local selected = pool[rng:NextInteger(1, #pool)]
		baseId = tostring(selected.BaseId or "")
		naturalRarity = tostring(selected.Rarity or "Common")
	else
		naturalRarity = getCatalogBaseRarity(baseId)
		if not naturalRarity then
			return nil, "crew_catalog_rarity_unavailable:" .. tostring(baseId)
		end
		if rarityFilter ~= "Random" and naturalRarity ~= rarityFilter then
			return nil,
				"selected_crew_rarity_mismatch:" .. tostring(naturalRarity) .. ":expected_" .. tostring(rarityFilter),
				string.format("Selected crew is not %s rarity.", tostring(rarityFilter))
		end

		local hasTemplate = hasCrewTemplate(baseId, variant)
		if not hasTemplate then
			return nil, "crew_model_unavailable:" .. tostring(baseId) .. ":" .. tostring(variant)
		end
	end

	local hasResolvedTemplate, usedVariant, visualFallback = resolveCrewTemplateVariant(baseId, variant)
	if hasResolvedTemplate ~= true or usedVariant == "" then
		return nil, "crew_model_unavailable:" .. tostring(baseId) .. ":" .. tostring(variant)
	end

	return {
		BaseId = baseId,
		CrewId = CrewCatalog.MakeVariantId(baseId, variant),
		Rarity = naturalRarity,
		RarityFilter = rarityFilter,
		RarityFilterMode = if rarityFilter == "Random" then "all" else "catalog:" .. tostring(rarityFilter),
		PoolSize = poolSize,
		Variant = variant,
		VisualVariant = usedVariant,
		VisualFallback = visualFallback == true,
	}
end

local function isSlotOccupied(player, slotName, inventory)
	local standData = DataManager:GetValue(player, "CrewMemberIncome." .. tostring(slotName))
	if typeof(standData) == "table" then
		if tostring(standData.CrewMemberName or "") ~= "" or tostring(standData.CrewMemberInstanceId or "") ~= "" then
			return true, tostring(standData.CrewMemberInstanceId or ""), tostring(standData.CrewMemberName or "")
		end
	end

	if typeof(inventory) == "table" and typeof(inventory.ById) == "table" then
		for instanceId, instanceData in pairs(inventory.ById) do
			if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == tostring(slotName) then
				return true, tostring(instanceId), tostring(instanceData.StorageName or "")
			end
		end
	end

	return false, "", ""
end

local function queueStandRefresh(player, activeShip)
	if typeof(activeShip) ~= "Instance" or not activeShip:IsA("Model") or activeShip.Parent == nil then
		return false, "active_ship_unavailable"
	end

	local standCommand = ShipRuntimeSignals.GetStandCommandFunction()
	if not standCommand or not standCommand:IsA("BindableFunction") then
		return false, "stand_refresh_missing"
	end

	local ok, result, reason = pcall(function()
		return standCommand:Invoke("queue_refresh", player, {
			ActiveShip = activeShip,
			Generation = ShipRuntimeService.GetCrewVisualGeneration(player),
			Source = "admin_fill_ship",
		})
	end)
	if not ok then
		return false, tostring(result)
	end
	if result == false then
		return false, tostring(reason or "stand_refresh_failed")
	end
	return true, tostring(reason or result or "queued")
end

local function getSlotNumbers(activeShip, capacity)
	local slotNumbers = ShipSlotService.GetAvailableSlotNumbers(activeShip, {
		MaxSlots = capacity,
	})
	table.sort(slotNumbers, function(left, right)
		return tonumber(left) < tonumber(right)
	end)
	while #slotNumbers > MAX_OPERATION_CAP do
		table.remove(slotNumbers)
	end
	return slotNumbers
end

local function formatFailureList(failures)
	local parts = {}
	for index = 1, math.min(#failures, 6) do
		parts[#parts + 1] = tostring(failures[index])
	end
	if #failures > #parts then
		parts[#parts + 1] = string.format("+%d_more", #failures - #parts)
	end
	return table.concat(parts, ";")
end

local function formatCreatedList(createdRecords)
	local parts = {}
	for index = 1, math.min(#createdRecords, 10) do
		local record = createdRecords[index]
		parts[#parts + 1] = string.format(
			"%s@%s:%s/%s",
			tostring(record.InstanceId or ""),
			tostring(record.SlotName or ""),
			tostring(record.Rarity or ""),
			tostring(record.Variant or "")
		)
	end
	if #createdRecords > #parts then
		parts[#parts + 1] = string.format("+%d_more", #createdRecords - #parts)
	end
	return table.concat(parts, ";")
end

local function runUnlocked(adminPlayer, payload, runContext)
	if typeof(adminPlayer) ~= "Instance" or not adminPlayer:IsA("Player") then
		return makeFailure("Admin player is unavailable.", "invalid_admin")
	end
	payload = if typeof(payload) == "table" then payload else {}
	runContext = if typeof(runContext) == "table" then runContext else {}
	local cancelToken = if typeof(runContext.CancelToken) == "table" then runContext.CancelToken else nil

	local targetPlayer, targetReason = findOnlineTarget(adminPlayer, payload)
	if not targetPlayer then
		return makeFailure("Target player must be online.", targetReason)
	end

	local ready, readyReason = waitForTargetDataReady(targetPlayer)
	if ready ~= true then
		return makeFailure("Target data is not ready yet.", readyReason, {
			TargetUserId = targetPlayer.UserId,
		})
	end

	local fillMode = normalizeFillMode(payload.FillMode or payload.Mode)
	local rarityChoice, rarityReason = normalizeRarityChoice(payload.Rarity)
	if not rarityChoice then
		return makeFailure("Invalid crew rarity.", rarityReason, {
			TargetUserId = targetPlayer.UserId,
		})
	end

	local variantChoice, variantReason = normalizeVariantChoice(payload.Variant)
	if not variantChoice then
		return makeFailure("Invalid crew variant.", variantReason, {
			TargetUserId = targetPlayer.UserId,
		})
	end

	local specificBaseId, crewReason = resolveSpecificCrewBase(payload.CrewMember or payload.CrewMemberId or payload.Crew)
	if crewReason ~= "random" and not specificBaseId then
		return makeFailure("Invalid crew member.", crewReason, {
			TargetUserId = targetPlayer.UserId,
		})
	end
	local rarityFilterMode = if rarityChoice == "Random" then "all" else "catalog:" .. tostring(rarityChoice)
	if specificBaseId and rarityChoice ~= "Random" then
		local naturalRarity = getCatalogBaseRarity(specificBaseId)
		if naturalRarity ~= rarityChoice then
			return makeFailure(string.format("Selected crew is not %s rarity.", tostring(rarityChoice)), "selected_crew_rarity_mismatch", {
				TargetUserId = targetPlayer.UserId,
				CrewMember = specificBaseId,
				CatalogRarity = tostring(naturalRarity or ""),
				RequestedRarity = rarityChoice,
			})
		end
	end

	local activeShip, activeShipReason = ensureActiveShip(targetPlayer)
	if not activeShip then
		return makeFailure("Target active ship is unavailable.", activeShipReason, {
			TargetUserId = targetPlayer.UserId,
		})
	end

	local plotUpgrade, rebirths, effectiveLevel, capacity = getTargetShipProgress(targetPlayer)
	if capacity <= 0 then
		return makeFailure("Target ship has no normal crew slots.", "no_ship_capacity", {
			TargetUserId = targetPlayer.UserId,
		})
	end

	local slotNumbers = getSlotNumbers(activeShip, capacity)
	if #slotNumbers == 0 then
		return makeFailure("Target active ship has no available numbered crew slots.", "no_active_ship_slots", {
			TargetUserId = targetPlayer.UserId,
		})
	end

	local activeModelName = tostring(activeShip:GetAttribute(ShipVisuals.Attributes.ActiveModelName or "ActiveShipModelName")
		or ShipVisuals.GetModelNameForUpgradeLevel(effectiveLevel)
		or activeShip.Name)
	local activeTier = tonumber(activeShip:GetAttribute(ShipVisuals.Attributes.ActiveTier or "ActiveShipTier"))
		or ShipVisuals.GetTierForUpgradeLevel(effectiveLevel)
		or 0

	print(string.format(
		"[AdminFillShip] start admin=%s target=%s plotUpgrade=%d rebirths=%d effectiveLevel=%d activeShipModel=%s activeShipTier=%s fillMode=%s crew=%s rarity=%s rarityFilterMode=%s variant=%s capacity=%d activeSlots=%d",
		getPlayerLabel(adminPlayer),
		getPlayerLabel(targetPlayer),
		plotUpgrade,
		rebirths,
		effectiveLevel,
		activeModelName,
		tostring(activeTier),
		fillMode,
		cleanText(payload.CrewMember or payload.CrewMemberId or payload.Crew or "Random", 80),
		rarityChoice,
		rarityFilterMode,
		variantChoice,
		capacity,
		#slotNumbers
	))

	local inventory = CrewInstanceService.EnsureInventory(targetPlayer)
	local targetSlots = {}
	local skippedSlots = 0
	local skippedReasons = {}

	for _, slotNumber in ipairs(slotNumbers) do
		local slotName = tostring(slotNumber)
		local occupied = isSlotOccupied(targetPlayer, slotName, inventory)
		if fillMode == "EmptyOnly" and occupied then
			skippedSlots += 1
			skippedReasons[#skippedReasons + 1] = slotName .. ":occupied"
		else
			targetSlots[#targetSlots + 1] = {
				SlotName = slotName,
				Occupied = occupied,
			}
		end
	end

	local failures = {}
	local poolCache = {}
	local bulkRequests = {}
	local visualFallbackBySlot = {}
	local crewPoolSizeMax = if specificBaseId then 1 else 0

	for index, slotInfo in ipairs(targetSlots) do
		local spec, specReason, specMessage = buildCrewSpec({
			SpecificBaseId = specificBaseId,
			RarityChoice = rarityChoice,
			VariantChoice = variantChoice,
		}, poolCache)
		if not spec then
			failures[#failures + 1] = slotInfo.SlotName .. ":" .. tostring(specMessage or specReason)
		else
			crewPoolSizeMax = math.max(crewPoolSizeMax, tonumber(spec.PoolSize) or crewPoolSizeMax)
			local descriptorOk, descriptorOrReason = AddCrewMember.BuildGrantDescriptor(targetPlayer, spec.CrewId, 1, {
				Source = "AdminFillShip",
				_QuickSlotCapacityReserved = true,
			})
			if descriptorOk ~= true then
				failures[#failures + 1] = slotInfo.SlotName .. ":" .. tostring(descriptorOrReason or "crew_grant_descriptor_failed")
			else
				bulkRequests[#bulkRequests + 1] = {
					SlotName = slotInfo.SlotName,
					FillMode = fillMode,
					Occupied = slotInfo.Occupied,
					Descriptor = descriptorOrReason,
					ExpectedIncomingStorageName = spec.CrewId,
					BaseId = spec.BaseId,
					Rarity = spec.Rarity,
					RarityFilterMode = spec.RarityFilterMode,
					PoolSize = spec.PoolSize,
					Variant = spec.Variant,
					VisualVariant = spec.VisualVariant,
					VisualFallback = spec.VisualFallback == true,
				}
				if spec.VisualFallback == true then
					visualFallbackBySlot[slotInfo.SlotName] = {
						BaseId = spec.BaseId,
						RequestedVariant = spec.Variant,
						UsedVariant = spec.VisualVariant,
					}
				end
			end
		end

		if index % MUTATION_BATCH_SIZE == 0 and index < #targetSlots then
			task.wait(MUTATION_BATCH_YIELD_SECONDS)
		end
	end

	local counters = {
		InventoryNotifyCount = 0,
		BountyRecomputeCount = 0,
		StandRefreshRequestCount = 0,
		StandIncomeWriteCount = 0,
	}
	if cancelToken and cancelToken.Cancelled == true then
		warn(string.format(
			"[AdminFillShip] failure admin=%s target=%s reason=cancelled_before_bulk",
			getPlayerLabel(adminPlayer),
			getPlayerLabel(targetPlayer)
		))
		return makeFailure("Fill Ship timed out before the bulk mutation could run.", "cancelled", {
			TargetUserId = targetPlayer.UserId,
		})
	end
	local bulkResult = CrewInstanceService.ApplyAdminFillShipBulk(targetPlayer, bulkRequests, {
		FillMode = fillMode,
		SourcePath = "admin_fill_ship_bulk",
		Counters = counters,
		CancelToken = cancelToken,
	})
	for _, failure in ipairs(bulkResult.Failures or {}) do
		failures[#failures + 1] = tostring(failure)
	end
	if bulkResult.Success ~= true and #(bulkResult.Failures or {}) == 0 then
		failures[#failures + 1] = tostring(bulkResult.Reason or "bulk_fill_failed")
	end
	local bulkSkipped = bulkResult.Skipped or {}
	for _, skipped in ipairs(bulkSkipped) do
		skippedReasons[#skippedReasons + 1] = tostring(skipped)
	end
	skippedSlots += #bulkSkipped

	local createdRecords = bulkResult.Created or {}
	local filledSlots = tonumber(bulkResult.Filled) or 0
	local replacedSlots = tonumber(bulkResult.Replaced) or 0
	local createdCount = #createdRecords
	local visualFallbackCount = 0
	local visualFallbackDetails = {}
	for _, record in ipairs(createdRecords) do
		local fallback = visualFallbackBySlot[tostring(record.SlotName or "")]
		if fallback then
			visualFallbackCount += 1
			visualFallbackDetails[#visualFallbackDetails + 1] = string.format(
				"slot=%s instance=%s base=%s requested=%s used=%s",
				tostring(record.SlotName or ""),
				tostring(record.InstanceId or ""),
				tostring(fallback.BaseId or ""),
				tostring(fallback.RequestedVariant or ""),
				tostring(fallback.UsedVariant or "")
			)
		end
	end
	if visualFallbackCount > 0 then
		warn(string.format(
			"[AdminFillShip] visual_variant_fallback admin=%s target=%s count=%d details=%s",
			getPlayerLabel(adminPlayer),
			getPlayerLabel(targetPlayer),
			visualFallbackCount,
			formatFailureList(visualFallbackDetails)
		))
	end

	local refreshOk, refreshReason = true, "not_needed"
	if filledSlots > 0 then
		counters.StandRefreshRequestCount += 1
		refreshOk, refreshReason = queueStandRefresh(targetPlayer, activeShip)
	end

	local failureSummary = formatFailureList(failures)
	local skippedSummary = formatFailureList(skippedReasons)
	local createdSummary = formatCreatedList(createdRecords)
	local resultDetail = string.format(
		"targetUserId=%d plotUpgrade=%d effectiveLevel=%d activeShipModel=%s activeShipTier=%s fillMode=%s crew=%s rarity=%s rarityFilterMode=%s crewPoolSizeMax=%d variant=%s capacity=%d activeSlots=%d targetSlots=%d created=%d filled=%d replaced=%d skipped=%d failures=%d refreshOk=%s refreshReason=%s inventoryNotifyCount=%d bountyRecomputeCount=%d standRefreshRequestCount=%d standIncomeWriteCount=%d visualFallbacks=%d createdDetails=%s skippedDetails=%s failureDetails=%s",
		targetPlayer.UserId,
		plotUpgrade,
		effectiveLevel,
		activeModelName,
		tostring(activeTier),
		fillMode,
		if specificBaseId then specificBaseId else "Random",
		rarityChoice,
		rarityFilterMode,
		crewPoolSizeMax,
		variantChoice,
		capacity,
		#slotNumbers,
		#targetSlots,
		createdCount,
		filledSlots,
		replacedSlots,
		skippedSlots,
		#failures,
		tostring(refreshOk),
		tostring(refreshReason),
		tonumber(counters.InventoryNotifyCount) or 0,
		tonumber(counters.BountyRecomputeCount) or 0,
		tonumber(counters.StandRefreshRequestCount) or 0,
		tonumber(counters.StandIncomeWriteCount) or 0,
		visualFallbackCount,
		createdSummary,
		skippedSummary,
		failureSummary
	)

	if bulkResult.Success ~= true or #failures > 0 or refreshOk ~= true then
		warn("[AdminFillShip] partial_failure " .. resultDetail)
	else
		print("[AdminFillShip] complete " .. resultDetail)
	end

	local partial = filledSlots > 0 and (bulkResult.Success ~= true or #failures > 0 or refreshOk ~= true)
	local success = filledSlots > 0 and bulkResult.Success == true and not partial
	local noOp = filledSlots == 0 and #failures == 0 and bulkResult.Success == true
	return {
		Success = success or partial or noOp,
		Partial = partial,
		Message = if partial
			then string.format("Fill Ship partially completed: %d filled, %d failed.", filledSlots, #failures)
			elseif success
			then string.format("Fill Ship completed: %d slots filled.", filledSlots)
			elseif noOp
			then string.format("No empty ship slots to fill. Skipped %d.", skippedSlots)
			else string.format("No ship slots filled. Skipped %d, failed %d.", skippedSlots, #failures),
		Changed = filledSlots > 0,
		TargetUserId = targetPlayer.UserId,
		TargetName = targetPlayer.Name,
		PlotUpgrade = plotUpgrade,
		Rebirths = rebirths,
		EffectiveLevel = effectiveLevel,
		ActiveShipModelName = activeModelName,
		ActiveShipTier = activeTier,
		FillMode = fillMode,
		CrewSelection = if specificBaseId then specificBaseId else "Random",
		RaritySelection = rarityChoice,
		RarityFilterMode = rarityFilterMode,
		CrewPoolSizeMax = crewPoolSizeMax,
		VariantSelection = variantChoice,
		SlotsFilled = filledSlots,
		SlotsReplaced = replacedSlots,
		SlotsSkipped = skippedSlots,
		Failures = failures,
		RefreshOk = refreshOk,
		RefreshReason = refreshReason,
		InventoryNotifyCount = counters.InventoryNotifyCount,
		BountyRecomputeCount = counters.BountyRecomputeCount,
		StandRefreshRequestCount = counters.StandRefreshRequestCount,
		StandIncomeWriteCount = counters.StandIncomeWriteCount,
		VisualFallbackCount = visualFallbackCount,
	}
end

function AdminFillShipService.Run(adminPlayer, payload)
	local targetPlayer = nil
	if typeof(payload) == "table" then
		targetPlayer = select(1, findOnlineTarget(adminPlayer, payload))
	end
	local targetUserId = if targetPlayer then targetPlayer.UserId else 0
	if targetUserId > 0 and activeRunsByUserId[targetUserId] ~= nil then
		return makeFailure("Fill Ship is already running for that player.", "target_busy", {
			TargetUserId = targetUserId,
		})
	end

	local runToken = nil
	if targetUserId > 0 then
		runToken = {
			Cancelled = false,
			StartedAt = os.clock(),
		}
		activeRunsByUserId[targetUserId] = runToken
	end

	local function clearActiveRun(reason)
		if targetUserId <= 0 then
			return
		end
		if activeRunsByUserId[targetUserId] == runToken then
			activeRunsByUserId[targetUserId] = nil
			print(string.format(
				"[AdminFillShip] active_run_cleared admin=%s targetUserId=%d reason=%s",
				getPlayerLabel(adminPlayer),
				targetUserId,
				tostring(reason or "unknown")
			))
		else
			warn(string.format(
				"[AdminFillShip] active_run_cleanup_skipped admin=%s targetUserId=%d reason=%s",
				getPlayerLabel(adminPlayer),
				targetUserId,
				tostring(reason or "unknown")
			))
		end
	end

	local finished = false
	local ok = false
	local result = nil
	task.spawn(function()
		ok, result = xpcall(function()
			return runUnlocked(adminPlayer, payload, {
				CancelToken = runToken,
			})
		end, debug.traceback)
		finished = true
	end)

	local deadline = os.clock() + RUN_TIMEOUT_SECONDS
	while finished ~= true and os.clock() < deadline do
		task.wait(RUN_WAIT_STEP_SECONDS)
	end

	if finished ~= true then
		if runToken then
			runToken.Cancelled = true
		end
		clearActiveRun("timeout")
		warn(string.format(
			"[AdminFillShip] timed_out admin=%s targetUserId=%s timeoutSeconds=%d",
			getPlayerLabel(adminPlayer),
			tostring(targetUserId),
			RUN_TIMEOUT_SECONDS
		))
		return makeFailure("Fill Ship timed out. No commit will be attempted after cancellation.", "timeout", {
			TargetUserId = targetUserId,
			TimeoutSeconds = RUN_TIMEOUT_SECONDS,
		})
	end

	clearActiveRun(if ok then "completed" else "exception")

	if not ok then
		warn(string.format(
			"[AdminFillShip] crashed admin=%s targetUserId=%s error=%s",
			getPlayerLabel(adminPlayer),
			tostring(targetUserId),
			tostring(result)
		))
		return makeFailure("Fill Ship failed unexpectedly.", "exception", {
			TargetUserId = targetUserId,
			Error = tostring(result),
		})
	end

	if typeof(result) == "table" and result.Success == true then
		print(string.format(
			"[AdminFillShip] run_complete admin=%s targetUserId=%s changed=%s filled=%s replaced=%s",
			getPlayerLabel(adminPlayer),
			tostring(targetUserId),
			tostring(result.Changed == true),
			tostring(result.SlotsFilled or 0),
			tostring(result.SlotsReplaced or 0)
		))
	else
		warn(string.format(
			"[AdminFillShip] run_failed admin=%s targetUserId=%s reason=%s",
			getPlayerLabel(adminPlayer),
			tostring(targetUserId),
			tostring(typeof(result) == "table" and result.Reason or "unknown")
		))
	end

	return result
end

return AdminFillShipService
