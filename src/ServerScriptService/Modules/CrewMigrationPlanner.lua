local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CrewCatalog = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewCompatibilityDiagnostics = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCompatibilityDiagnostics")
)
local CrewCompatibilityQuarantine = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Crew"):WaitForChild("CrewCompatibilityQuarantine")
)
local CrewProfileSchema = require(script.Parent:WaitForChild("CrewProfileSchema"))
local CrewStorage = require(script.Parent:WaitForChild("CrewStorage"))
local CrewMemberShadowConfig = require(script.Parent:WaitForChild("CrewMemberShadowConfig"))
local CrewQuickSlotConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))

local CrewMigrationPlanner = {}

local MIGRATION_TOOL_VERSION = "crew_member_migration_diagnostics_v1"
local AUDIT_DATA_STORE_NAME = "CrewMemberMigrationAudit_v1"

local dataManagerCache = nil
local auditDataStoreCache = nil
local diagnosticSnapshotsByUserId = {}
local migrationWritePreviewsByUserId = {}

local function getDataManager()
	if dataManagerCache == nil then
		dataManagerCache = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerCache
end

local function getAuditDataStore()
	if auditDataStoreCache == nil then
		auditDataStoreCache = DataStoreService:GetDataStore(AUDIT_DATA_STORE_NAME)
	end
	return auditDataStoreCache
end

local function getRoot(source)
	if typeof(source) == "table" and typeof(source.Data) == "table" then
		return source.Data
	end
	if typeof(source) == "table" then
		return source
	end
	return nil
end

local function readPath(root, path)
	local node = root
	for _, key in ipairs(path) do
		if typeof(node) ~= "table" then
			return nil
		end
		node = node[key]
	end
	return node
end

local function readPlayerValue(player, path)
	local ok, value = pcall(function()
		return getDataManager():GetValue(player, table.concat(path, "."))
	end)
	if ok then
		return value
	end
	return nil
end

local function readValue(source, path)
	if typeof(source) == "Instance" and source:IsA("Player") then
		return readPlayerValue(source, path)
	end
	return readPath(getRoot(source), path)
end

local function shallowCopy(value)
	if typeof(value) ~= "table" then
		return {}
	end
	return table.clone(value)
end

local function deepCopy(value, seen)
	if typeof(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local copy = {}
	seen[value] = copy
	for key, child in pairs(value) do
		copy[deepCopy(key, seen)] = deepCopy(child, seen)
	end
	return copy
end

local function countPairs(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(value) do
		count += 1
	end
	return count
end

local function addIssue(issues, kind, detail)
	detail = if typeof(detail) == "table" then detail else {}
	detail.Kind = kind
	issues[#issues + 1] = detail
	return detail
end

local function addUnique(list, seen, key, detail)
	key = tostring(key or "")
	if key == "" or seen[key] == true then
		return
	end

	seen[key] = true
	if detail ~= nil then
		list[#list + 1] = detail
	else
		list[#list + 1] = key
	end
end

local function sortByStorageName(list)
	table.sort(list, function(left, right)
		return tostring(left.StorageName or left.LegacyId or left) < tostring(right.StorageName or right.LegacyId or right)
	end)
end

local function sortIssueList(issues)
	table.sort(issues, function(left, right)
		local leftKey = string.format(
			"%s:%s:%s:%s",
			tostring(left.Kind),
			tostring(left.StorageName or left.LegacyId or ""),
			tostring(left.StandName or ""),
			tostring(left.InstanceId or "")
		)
		local rightKey = string.format(
			"%s:%s:%s:%s",
			tostring(right.Kind),
			tostring(right.StorageName or right.LegacyId or ""),
			tostring(right.StandName or ""),
			tostring(right.InstanceId or "")
		)
		return leftKey < rightKey
	end)
end

local function isCrewInventoryEntry(key, entry)
	if key == "Feed" or key == "DevilFruits" then
		return false
	end
	if typeof(entry) ~= "table" then
		return false
	end
	return entry.Quantity ~= nil
		or entry.BaseName ~= nil
		or entry.Variant ~= nil
		or entry.Rarity ~= nil
		or entry.Level ~= nil
		or entry.CurrentXP ~= nil
end

local function resolveCrewInfo(storageName, entry)
	entry = if typeof(entry) == "table" then entry else {}
	local baseName = tostring(entry.BaseName or "")
	local info = CrewCatalog.GetInfoById(storageName)
	if not info and baseName ~= "" then
		info = CrewCatalog.GetInfoById(baseName)
	end
	return info
end

local function getCanonicalCrewMemberId(storageName, info)
	local fallback = tostring(storageName or "")
	if typeof(info) ~= "table" then
		return fallback
	end
	if info.RealCharacterName ~= nil then
		return tostring(info.DisplayName or info.CrewMemberName or info.CrewMemberId or fallback)
	end
	return fallback
end

local function getDisplayName(storageName, info)
	if typeof(info) == "table" then
		return tostring(info.DisplayName or info.CrewMemberName or info.Name or storageName)
	end
	return tostring(storageName or "")
end

local function classifyCrewMember(storageName, info)
	local isProductionCrew = typeof(info) == "table" and info.RealCharacterName ~= nil
	local isUnknownLegacyId = tostring(storageName or "") ~= "" and typeof(info) ~= "table"
	local isCompatibilityOnly = typeof(info) == "table" and not isProductionCrew
	local usesFallbackModel = typeof(info) == "table" and info.MissingCrewModel == true
	local isBrookFallback = usesFallbackModel
		and (
			tostring(storageName or "") == "Gangster Footera"
			or tostring(info.DisplayName or "") == "Soul Fiddler"
			or tostring(info.RealCharacterName or "") == "Brook"
		)

	return {
		IsProductionCrew = isProductionCrew,
		IsUnknownLegacyId = isUnknownLegacyId,
		IsCompatibilityOnly = isCompatibilityOnly,
		UsesFallbackModel = usesFallbackModel,
		IsBrookFallback = isBrookFallback,
	}
end

local function getReviewKind(classification)
	if typeof(classification) ~= "table" then
		return nil
	end
	if classification.IsBrookFallback == true then
		return "brook_fallback"
	end
	if classification.IsCompatibilityOnly == true then
		return "compatibility_only"
	end
	return nil
end

local function applyReviewDecision(detail, storageName, classification)
	local reviewKind = getReviewKind(classification)
	if reviewKind == nil then
		return nil
	end

	local decision = CrewCompatibilityQuarantine.GetDecision(storageName, reviewKind)
	detail.ReviewKind = reviewKind
	if decision ~= nil then
		detail.ReviewAllowed = decision.Allowed == true
		detail.ReviewDisposition = tostring(decision.Disposition or "quarantined")
		detail.ReviewReason = tostring(decision.Reason or "")
		detail.RetirementAction = tostring(decision.RetirementAction or "")
		detail.ReviewCrewMemberId = tostring(decision.CrewMemberId or detail.CrewMemberId or "")
		detail.ReviewModelName = tostring(decision.ModelName or detail.ModelName or "")
	else
		detail.ReviewAllowed = false
		detail.ReviewDisposition = "needs_mapping_or_cleanup_decision"
		detail.ReviewReason = "No explicit compatibility quarantine decision exists for this legacy row."
		detail.RetirementAction = "decide_mapping_or_clean_data"
	end
	return decision
end

local function readLegacyData(source)
	return {
		Inventory = readValue(source, { "Inventory" }),
		BrainrotInventory = readValue(source, { CrewStorage.Keys.Inventory }),
		BrainrotQuickSlots = readValue(source, { CrewStorage.Keys.QuickSlots }),
		BrainrotStorage = readValue(source, { CrewStorage.Keys.QuickSlotsLegacy }),
		IncomeBrainrots = readValue(source, { CrewStorage.Keys.Income }),
		IndexBrainrots = readValue(source, { CrewStorage.Keys.IndexCollection, CrewStorage.Keys.Index }),
		StandsLevels = readValue(source, { "StandsLevels" }),
		FoodInventory = readValue(source, { "FoodInventory" }),
	}
end

local function getInventoryEntry(legacyData, storageName)
	local inventory = legacyData.Inventory
	if typeof(inventory) ~= "table" then
		return nil
	end
	return inventory[tostring(storageName or "")]
end

local function normalizeInstanceId(rawInstanceId)
	local instanceId = tostring(rawInstanceId or "")
	if instanceId == "" then
		return nil
	end
	return instanceId
end

local function collectLegacyInstances(brainrotInventory)
	local issues = {}
	local instances = {}
	local seen = {}
	local byId = typeof(brainrotInventory) == "table" and brainrotInventory.ById or nil
	local order = typeof(brainrotInventory) == "table" and brainrotInventory.Order or nil

	if typeof(byId) ~= "table" then
		return instances, issues
	end

	if typeof(order) == "table" then
		for _, rawInstanceId in ipairs(order) do
			local instanceId = normalizeInstanceId(rawInstanceId)
			if not instanceId then
				addIssue(issues, "BlankInstanceIdInOrder")
			elseif seen[instanceId] then
				addIssue(issues, "DuplicateInstanceIdInOrder", {
					InstanceId = instanceId,
				})
			else
				seen[instanceId] = true
				local instanceData = byId[instanceId]
				if typeof(instanceData) == "table" then
					instances[#instances + 1] = {
						InstanceId = instanceId,
						Data = instanceData,
						Source = "BrainrotInventory",
					}
				else
					addIssue(issues, "OrderInstanceMissingById", {
						InstanceId = instanceId,
					})
				end
			end
		end
	end

	local unorderedIds = {}
	for rawInstanceId, instanceData in pairs(byId) do
		local instanceId = normalizeInstanceId(rawInstanceId)
		if instanceId and not seen[instanceId] then
			if typeof(instanceData) == "table" then
				unorderedIds[#unorderedIds + 1] = instanceId
			else
				addIssue(issues, "InvalidInstanceData", {
					InstanceId = instanceId,
				})
			end
		end
	end

	table.sort(unorderedIds, function(left, right)
		local leftNumber = tonumber(left)
		local rightNumber = tonumber(right)
		if leftNumber and rightNumber then
			return leftNumber < rightNumber
		end
		return left < right
	end)

	for _, instanceId in ipairs(unorderedIds) do
		instances[#instances + 1] = {
			InstanceId = instanceId,
			Data = byId[instanceId],
			Source = "BrainrotInventoryUnordered",
		}
		addIssue(issues, "ByIdInstanceMissingFromOrder", {
			InstanceId = instanceId,
		})
	end

	return instances, issues
end

local function countInstancesByStorageName(brainrotInventory)
	local counts = {}
	local byId = typeof(brainrotInventory) == "table" and brainrotInventory.ById or nil
	if typeof(byId) ~= "table" then
		return counts
	end

	for _, instanceData in pairs(byId) do
		if typeof(instanceData) == "table" then
			local storageName = tostring(instanceData.StorageName or instanceData.BrainrotName or "")
			if storageName ~= "" then
				counts[storageName] = (counts[storageName] or 0) + 1
			end
		end
	end

	return counts
end

local function buildCrewItem(storageName, entry, instanceCount)
	local info = resolveCrewInfo(storageName, entry)
	local classification = classifyCrewMember(storageName, info)
	entry = if typeof(entry) == "table" then entry else {}

	return {
		StorageName = tostring(storageName),
		Quantity = math.max(0, math.floor(tonumber(entry.Quantity) or 0)),
		InstanceCount = math.max(0, math.floor(tonumber(instanceCount) or 0)),
		BaseName = tostring(entry.BaseName or storageName),
		Variant = tostring(entry.Variant or "Normal"),
		Level = math.max(1, math.floor(tonumber(entry.Level) or 1)),
		CurrentXP = math.max(0, math.floor(tonumber(entry.CurrentXP) or 0)),
		CrewMemberId = getCanonicalCrewMemberId(storageName, info),
		DisplayName = getDisplayName(storageName, info),
		RealCharacterName = info and tostring(info.RealCharacterName or "") or "",
		Arc = info and tostring(info.Arc or "") or "",
		Rarity = info and tostring(info.Rarity or entry.Rarity or "Common") or tostring(entry.Rarity or "Common"),
		Income = info and (tonumber(info.Income) or 0) or tonumber(entry.Income) or 0,
		ModelName = info and tostring(info.ModelName or storageName) or tostring(storageName),
		IsProductionCrew = classification.IsProductionCrew,
		UsesFallbackModel = classification.UsesFallbackModel,
		IsCompatibilityOnly = classification.IsCompatibilityOnly,
		IsUnknownLegacyId = classification.IsUnknownLegacyId,
		IsBrookFallback = classification.IsBrookFallback,
	}
end

local function buildInventorySnapshot(source)
	local legacyData = readLegacyData(source)
	local instanceCounts = countInstancesByStorageName(legacyData.BrainrotInventory)
	local entries = {}
	local totals = {
		ProductionCrew = 0,
		CompatibilityOnly = 0,
		UnknownLegacyIds = 0,
		FallbackModel = 0,
		BrookFallback = 0,
		Quantity = 0,
		Instances = 0,
	}

	for storageName, entry in pairs(shallowCopy(legacyData.Inventory)) do
		if isCrewInventoryEntry(storageName, entry) then
			local crewItem = buildCrewItem(storageName, entry, instanceCounts[tostring(storageName)] or 0)
			entries[#entries + 1] = crewItem
			totals.Quantity += crewItem.Quantity
			totals.Instances += crewItem.InstanceCount
			if crewItem.IsProductionCrew then
				totals.ProductionCrew += 1
			end
			if crewItem.IsCompatibilityOnly then
				totals.CompatibilityOnly += 1
			end
			if crewItem.IsUnknownLegacyId then
				totals.UnknownLegacyIds += 1
			end
			if crewItem.UsesFallbackModel then
				totals.FallbackModel += 1
			end
			if crewItem.IsBrookFallback then
				totals.BrookFallback += 1
			end
		end
	end

	table.sort(entries, function(a, b)
		return tostring(a.DisplayName) < tostring(b.DisplayName)
	end)

	return entries, totals
end

local function buildStandSnapshot(source)
	local incomeData = readValue(source, { CrewStorage.Keys.Income })
	local entries = {}

	if typeof(incomeData) ~= "table" then
		return entries
	end

	for standName, standData in pairs(incomeData) do
		if typeof(standData) == "table" then
			local storageName = tostring(standData[CrewStorage.Keys.StandName] or "")
			local info = CrewCatalog.GetInfoById(storageName)
			local classification = classifyCrewMember(storageName, info)
			entries[#entries + 1] = {
				StandName = tostring(standName),
				StorageName = storageName,
				InstanceId = tostring(standData[CrewStorage.Keys.StandInstanceId] or ""),
				IncomeToCollect = tonumber(standData.IncomeToCollect) or 0,
				CrewMemberId = getCanonicalCrewMemberId(storageName, info),
				DisplayName = getDisplayName(storageName, info),
				RealCharacterName = info and tostring(info.RealCharacterName or "") or "",
				Arc = info and tostring(info.Arc or "") or "",
				Rarity = info and tostring(info.Rarity or "") or "",
				ModelName = info and tostring(info.ModelName or storageName) or storageName,
				IsProductionCrew = classification.IsProductionCrew,
				UsesFallbackModel = classification.UsesFallbackModel,
				IsCompatibilityOnly = storageName ~= "" and classification.IsCompatibilityOnly,
				IsUnknownLegacyId = storageName ~= "" and classification.IsUnknownLegacyId,
				IsBrookFallback = classification.IsBrookFallback,
			}
		end
	end

	table.sort(entries, function(a, b)
		return tostring(a.StandName) < tostring(b.StandName)
	end)

	return entries
end

local function makeProjectionMetadata()
	return {
		ProjectionIssues = {},
		UnknownLegacyIds = {},
		CompatibilityOnlyLegacyIds = {},
		BrookFallbackEntries = {},
		ProductionFallbackEntries = {},
		InferredIndexEntries = {},
		LegacyInstanceCount = 0,
		ProjectedInstanceCount = 0,
		SynthesizedInstanceCount = 0,
	}
end

local function recordClassification(metadata, storageName, info, context)
	local classification = classifyCrewMember(storageName, info)
	local displayName = getDisplayName(storageName, info)
	local detail = {
		StorageName = tostring(storageName or ""),
		CrewMemberId = getCanonicalCrewMemberId(storageName, info),
		DisplayName = displayName,
		Context = tostring(context or ""),
	}
	applyReviewDecision(detail, detail.StorageName, classification)

	metadata._unknownSeen = metadata._unknownSeen or {}
	metadata._compatibilitySeen = metadata._compatibilitySeen or {}
	metadata._brookSeen = metadata._brookSeen or {}
	metadata._fallbackSeen = metadata._fallbackSeen or {}

	if classification.IsUnknownLegacyId then
		addUnique(metadata.UnknownLegacyIds, metadata._unknownSeen, detail.StorageName, detail)
	elseif classification.IsCompatibilityOnly then
		addUnique(metadata.CompatibilityOnlyLegacyIds, metadata._compatibilitySeen, detail.StorageName, detail)
	end

	if classification.IsBrookFallback then
		metadata.BrookFallbackCount = (metadata.BrookFallbackCount or 0) + 1
		addUnique(metadata.BrookFallbackEntries, metadata._brookSeen, detail.StorageName, detail)
	elseif classification.UsesFallbackModel then
		addUnique(metadata.ProductionFallbackEntries, metadata._fallbackSeen, detail.StorageName, detail)
	end

	return classification
end

local function buildProjectedInstance(instanceId, instanceData, legacyData, projectionSource, metadata)
	instanceData = if typeof(instanceData) == "table" then instanceData else {}
	local storageName = tostring(instanceData.StorageName or instanceData.BrainrotName or "")
	local inventoryEntry = getInventoryEntry(legacyData, storageName)
	local entryForResolution = {
		BaseName = instanceData.BaseName or (typeof(inventoryEntry) == "table" and inventoryEntry.BaseName or nil),
		Variant = instanceData.Variant or (typeof(inventoryEntry) == "table" and inventoryEntry.Variant or nil),
		Rarity = instanceData.Rarity or (typeof(inventoryEntry) == "table" and inventoryEntry.Rarity or nil),
	}
	local info = resolveCrewInfo(storageName, entryForResolution)
	local classification = recordClassification(metadata, storageName, info, projectionSource)
	local canonicalId = getCanonicalCrewMemberId(storageName, info)

	return {
		InstanceId = tostring(instanceId),
		CrewMemberId = canonicalId,
		DisplayName = getDisplayName(storageName, info),
		LegacyStorageName = storageName,
		StorageName = canonicalId,
		BaseName = tostring(instanceData.BaseName or entryForResolution.BaseName or storageName),
		Variant = tostring(instanceData.Variant or entryForResolution.Variant or "Normal"),
		Rarity = tostring((info and info.Rarity) or instanceData.Rarity or entryForResolution.Rarity or "Common"),
		Income = tonumber((info and info.Income) or instanceData.Income or 0) or 0,
		Render = tostring(instanceData.Render or (typeof(inventoryEntry) == "table" and inventoryEntry.Render or "") or ""),
		GoldenRender = tostring(instanceData.GoldenRender or (typeof(inventoryEntry) == "table" and inventoryEntry.GoldenRender or "") or ""),
		DiamondRender = tostring(instanceData.DiamondRender or (typeof(inventoryEntry) == "table" and inventoryEntry.DiamondRender or "") or ""),
		Level = math.max(1, math.floor(tonumber(instanceData.Level) or 1)),
		CurrentXP = math.max(0, math.floor(tonumber(instanceData.CurrentXP) or 0)),
		AssignedStand = tostring(instanceData.AssignedStand or ""),
		AcquiredAt = math.max(0, math.floor(tonumber(instanceData.AcquiredAt) or 0)),
		LastReleasedAt = math.max(0, math.floor(tonumber(instanceData.LastReleasedAt) or 0)),
		TutorialReward = instanceData.TutorialReward == true,
		TutorialToken = tostring(instanceData.TutorialToken or ""),
		ProjectionSource = tostring(projectionSource or "Unknown"),
		Compatibility = classification,
	}
end

local function getNextSyntheticInstanceId(usedIds, nextId)
	local candidate = math.max(1, math.floor(tonumber(nextId) or 1))
	while usedIds[tostring(candidate)] == true do
		candidate += 1
	end
	usedIds[tostring(candidate)] = true
	return tostring(candidate), candidate + 1
end

local function countPlacedByStorage(incomeBrainrots)
	local counts = {}
	local standNamesByStorage = {}
	if typeof(incomeBrainrots) ~= "table" then
		return counts, standNamesByStorage
	end

	for standName, standData in pairs(incomeBrainrots) do
		if typeof(standData) == "table" then
			local storageName = tostring(standData.BrainrotName or "")
			if storageName ~= "" then
				counts[storageName] = (counts[storageName] or 0) + 1
				standNamesByStorage[storageName] = standNamesByStorage[storageName] or {}
				table.insert(standNamesByStorage[storageName], tostring(standName))
			end
		end
	end

	return counts, standNamesByStorage
end

local function synthesizeInstancesFromLegacy(legacyData, usedIds, startingNextId, metadata)
	local synthesized = {}
	local nextId = startingNextId
	local _, standNamesByStorage = countPlacedByStorage(legacyData.IncomeBrainrots)

	for storageName, entry in pairs(shallowCopy(legacyData.Inventory)) do
		if isCrewInventoryEntry(storageName, entry) then
			local standNames = standNamesByStorage[tostring(storageName)] or {}
			table.sort(standNames)

			for _, standName in ipairs(standNames) do
				local standData = legacyData.IncomeBrainrots and legacyData.IncomeBrainrots[standName] or nil
				local preferredId = tostring((standData and standData.BrainrotInstanceId) or "")
				local instanceId
				if preferredId ~= "" and usedIds[preferredId] ~= true then
					instanceId = preferredId
					usedIds[instanceId] = true
				else
					instanceId, nextId = getNextSyntheticInstanceId(usedIds, nextId)
				end

				synthesized[#synthesized + 1] = {
					InstanceId = instanceId,
					Data = {
						StorageName = tostring(storageName),
						BaseName = entry.BaseName,
						Variant = entry.Variant,
						Rarity = entry.Rarity,
						Income = entry.Income,
						Render = entry.Render,
						GoldenRender = entry.GoldenRender,
						DiamondRender = entry.DiamondRender,
						Level = entry.Level,
						CurrentXP = entry.CurrentXP,
						AssignedStand = standName,
					},
					Source = "SynthesizedStand",
				}
			end

			local availableQuantity = math.max(0, math.floor(tonumber(entry.Quantity) or 0))
			for _ = 1, availableQuantity do
				local instanceId
				instanceId, nextId = getNextSyntheticInstanceId(usedIds, nextId)
				synthesized[#synthesized + 1] = {
					InstanceId = instanceId,
					Data = {
						StorageName = tostring(storageName),
						BaseName = entry.BaseName,
						Variant = entry.Variant,
						Rarity = entry.Rarity,
						Income = entry.Income,
						Render = entry.Render,
						GoldenRender = entry.GoldenRender,
						DiamondRender = entry.DiamondRender,
						Level = entry.Level,
						CurrentXP = entry.CurrentXP,
						AssignedStand = "",
					},
					Source = "SynthesizedInventoryQuantity",
				}
			end
		end
	end

	metadata.SynthesizedInstanceCount = #synthesized
	if #synthesized > 0 then
		addIssue(metadata.ProjectionIssues, "ProjectionSynthesizedLegacyInstances", {
			Count = #synthesized,
		})
	end

	return synthesized, nextId
end

local function buildProjectedInventory(legacyData, metadata)
	local inventory = CrewProfileSchema.NewCrewMemberInventory({
		NextInstanceId = typeof(legacyData.BrainrotInventory) == "table" and legacyData.BrainrotInventory.NextInstanceId or 1,
	})
	local legacyInstances, collectIssues = collectLegacyInstances(legacyData.BrainrotInventory)
	local usedIds = {}
	local maxNumericId = inventory.NextInstanceId - 1

	for _, issue in ipairs(collectIssues) do
		metadata.ProjectionIssues[#metadata.ProjectionIssues + 1] = issue
	end

	for _, item in ipairs(legacyInstances) do
		usedIds[item.InstanceId] = true
		maxNumericId = math.max(maxNumericId, tonumber(item.InstanceId) or 0)
	end

	if #legacyInstances == 0 then
		local synthesized, nextId = synthesizeInstancesFromLegacy(legacyData, usedIds, inventory.NextInstanceId, metadata)
		legacyInstances = synthesized
		maxNumericId = math.max(maxNumericId, nextId - 1)
	end

	metadata.LegacyInstanceCount = countPairs(typeof(legacyData.BrainrotInventory) == "table" and legacyData.BrainrotInventory.ById or nil)

	for _, item in ipairs(legacyInstances) do
		local projected = buildProjectedInstance(item.InstanceId, item.Data, legacyData, item.Source, metadata)
		inventory.ById[item.InstanceId] = projected
		table.insert(inventory.Order, item.InstanceId)
	end

	inventory.NextInstanceId = math.max(inventory.NextInstanceId, maxNumericId + 1)
	metadata.ProjectedInstanceCount = #inventory.Order
	return inventory
end

local function buildProjectedQuickSlots(legacyData)
	local legacyQuickSlots = if typeof(legacyData.BrainrotQuickSlots) == "table" then legacyData.BrainrotQuickSlots else {}
	return CrewProfileSchema.NewCrewMemberQuickSlots({
		UnlockedSlots = legacyQuickSlots.UnlockedSlots,
		MaxSlots = legacyQuickSlots.MaxSlots,
	})
end

local function buildProjectedIncome(legacyData, metadata)
	local income = CrewProfileSchema.NewCrewMemberIncome()
	local legacyIncome = legacyData.IncomeBrainrots
	local standLevels = legacyData.StandsLevels

	if typeof(legacyIncome) ~= "table" then
		return income
	end

	for standName, standData in pairs(legacyIncome) do
		if typeof(standData) == "table" then
			local storageName = tostring(standData.BrainrotName or "")
			local info = CrewCatalog.GetInfoById(storageName)
			recordClassification(metadata, storageName, info, "IncomeBrainrots")
			local crewMemberId = if storageName ~= "" then getCanonicalCrewMemberId(storageName, info) else ""

			income[tostring(standName)] = {
				CrewMemberName = crewMemberId,
				CrewMemberDisplayName = if storageName ~= "" then getDisplayName(storageName, info) else "",
				CrewMemberInstanceId = tostring(standData.BrainrotInstanceId or ""),
				LegacyStorageName = storageName,
				IncomeToCollect = tonumber(standData.IncomeToCollect) or 0,
				StandLevel = if typeof(standLevels) == "table" then math.max(1, math.floor(tonumber(standLevels[standName]) or 1)) else 1,
				Legacy = {
					BrainrotName = storageName,
					BrainrotInstanceId = tostring(standData.BrainrotInstanceId or ""),
				},
			}
		end
	end

	return income
end

local function addProjectedIndexEntry(projectedIndex, metadata, legacyId, source)
	local storageName = tostring(legacyId or "")
	if storageName == "" then
		return nil
	end

	local info = CrewCatalog.GetInfoById(storageName)
	recordClassification(metadata, storageName, info, source)
	local crewMemberId = getCanonicalCrewMemberId(storageName, info)
	if crewMemberId == "" then
		return nil
	end

	projectedIndex[crewMemberId] = true
	return crewMemberId
end

local function buildProjectedIndex(legacyData, projectedInventory, metadata)
	local projectedIndex = CrewProfileSchema.NewCrewMemberIndex()
	local legacyIndex = legacyData.IndexBrainrots

	if typeof(legacyIndex) == "table" then
		for legacyId, discovered in pairs(legacyIndex) do
			if discovered == true then
				addProjectedIndexEntry(projectedIndex, metadata, legacyId, "IndexCollection.Brainrots")
			end
		end
	end

	local inferredSeen = {}
	for _, instanceId in ipairs(projectedInventory.Order) do
		local instanceData = projectedInventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" then
			local crewMemberId = tostring(instanceData.CrewMemberId or "")
			if crewMemberId ~= "" and projectedIndex[crewMemberId] ~= true then
				projectedIndex[crewMemberId] = true
				addUnique(metadata.InferredIndexEntries, inferredSeen, crewMemberId, {
					CrewMemberId = crewMemberId,
					LegacyStorageName = tostring(instanceData.LegacyStorageName or ""),
					InstanceId = tostring(instanceId),
				})
			end
		end
	end

	return projectedIndex
end

function CrewMigrationPlanner.BuildRollbackSnapshot(source)
	local legacyData = readLegacyData(source)
	return {
		BrainrotInventory = deepCopy(legacyData.BrainrotInventory),
		BrainrotQuickSlots = deepCopy(legacyData.BrainrotQuickSlots),
		IncomeBrainrots = deepCopy(legacyData.IncomeBrainrots),
		IndexCollection = {
			Brainrots = deepCopy(legacyData.IndexBrainrots),
		},
		Inventory = deepCopy(legacyData.Inventory),
		StandsLevels = deepCopy(legacyData.StandsLevels),
	}
end

function CrewMigrationPlanner.BuildCrewMemberProjection(source)
	local legacyData = readLegacyData(source)
	local projection = CrewProfileSchema.NewProjection()
	local metadata = makeProjectionMetadata()

	local projectedInventory = buildProjectedInventory(legacyData, metadata)
	local projectedQuickSlots = buildProjectedQuickSlots(legacyData)
	local projectedIncome = buildProjectedIncome(legacyData, metadata)
	local projectedIndex = buildProjectedIndex(legacyData, projectedInventory, metadata)

	projection[CrewProfileSchema.Keys.Inventory] = projectedInventory
	projection[CrewProfileSchema.Keys.QuickSlots] = projectedQuickSlots
	projection[CrewProfileSchema.Keys.Income] = projectedIncome
	projection[CrewProfileSchema.Keys.IndexCollection][CrewProfileSchema.Keys.Index] = projectedIndex
	projection.Metadata = metadata

	sortByStorageName(metadata.UnknownLegacyIds)
	sortByStorageName(metadata.CompatibilityOnlyLegacyIds)
	sortByStorageName(metadata.BrookFallbackEntries)
	sortByStorageName(metadata.ProductionFallbackEntries)
	sortIssueList(metadata.ProjectionIssues)

	return projection
end

CrewMigrationPlanner.BuildDryRunProjection = CrewMigrationPlanner.BuildCrewMemberProjection

local function countProjectedAvailableByStorage(projectedInventory)
	local counts = {}
	for _, instanceId in ipairs(projectedInventory.Order or {}) do
		local instanceData = projectedInventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") == "" then
			local storageName = tostring(instanceData.LegacyStorageName or "")
			if storageName ~= "" then
				counts[storageName] = (counts[storageName] or 0) + 1
			end
		end
	end
	return counts
end

local function countProjectedTotalByStorage(projectedInventory)
	local counts = {}
	for _, instanceId in ipairs(projectedInventory.Order or {}) do
		local instanceData = projectedInventory.ById[tostring(instanceId)]
		if typeof(instanceData) == "table" then
			local storageName = tostring(instanceData.LegacyStorageName or "")
			if storageName ~= "" then
				counts[storageName] = (counts[storageName] or 0) + 1
			end
		end
	end
	return counts
end

local function collectLegacyQuantities(legacyData)
	local quantities = {}
	for storageName, entry in pairs(shallowCopy(legacyData.Inventory)) do
		if isCrewInventoryEntry(storageName, entry) then
			quantities[tostring(storageName)] = math.max(0, math.floor(tonumber(entry.Quantity) or 0))
		end
	end
	return quantities
end

local function unionKeys(left, right, third)
	local keys = {}
	for key in pairs(left or {}) do
		keys[key] = true
	end
	for key in pairs(right or {}) do
		keys[key] = true
	end
	for key in pairs(third or {}) do
		keys[key] = true
	end
	return keys
end

function CrewMigrationPlanner.ValidateStandConsistency(source)
	local legacyData = readLegacyData(source)
	local issues = {}
	local incomeBrainrots = legacyData.IncomeBrainrots
	local brainrotInventory = legacyData.BrainrotInventory
	local byId = typeof(brainrotInventory) == "table" and brainrotInventory.ById or {}
	local standLevels = legacyData.StandsLevels
	local standByInstanceId = {}
	local assignedStandByName = {}

	if typeof(byId) == "table" then
		for instanceId, instanceData in pairs(byId) do
			if typeof(instanceData) == "table" then
				local assignedStand = tostring(instanceData.AssignedStand or "")
				if assignedStand ~= "" then
					if assignedStandByName[assignedStand] ~= nil then
						addIssue(issues, "DuplicateAssignedStand", {
							StandName = assignedStand,
							InstanceId = tostring(instanceId),
							OtherInstanceId = assignedStandByName[assignedStand],
						})
					else
						assignedStandByName[assignedStand] = tostring(instanceId)
					end
				end
			end
		end
	end

	if typeof(incomeBrainrots) ~= "table" then
		return {
			Issues = issues,
			Summary = "standConsistencyIssues=0",
		}
	end

	for standName, standData in pairs(incomeBrainrots) do
		if typeof(standData) ~= "table" then
			addIssue(issues, "InvalidStandData", {
				StandName = tostring(standName),
			})
			continue
		end

		local storageName = tostring(standData.BrainrotName or "")
		local instanceId = tostring(standData.BrainrotInstanceId or "")
		if storageName == "" and instanceId ~= "" then
			addIssue(issues, "StandInstanceWithoutName", {
				StandName = tostring(standName),
				InstanceId = instanceId,
			})
		end

		if instanceId ~= "" then
			if standByInstanceId[instanceId] ~= nil then
				addIssue(issues, "DuplicateStandInstanceReference", {
					StandName = tostring(standName),
					OtherStandName = standByInstanceId[instanceId],
					InstanceId = instanceId,
				})
			else
				standByInstanceId[instanceId] = tostring(standName)
			end

			local instanceData = typeof(byId) == "table" and byId[instanceId] or nil
			if typeof(instanceData) ~= "table" then
				addIssue(issues, "StandInstanceMissing", {
					StandName = tostring(standName),
					StorageName = storageName,
					InstanceId = instanceId,
				})
			else
				local instanceStorageName = tostring(instanceData.StorageName or "")
				local assignedStand = tostring(instanceData.AssignedStand or "")
				if storageName ~= "" and instanceStorageName ~= "" and instanceStorageName ~= storageName then
					addIssue(issues, "StandNameMismatch", {
						StandName = tostring(standName),
						StorageName = storageName,
						InstanceStorageName = instanceStorageName,
						InstanceId = instanceId,
					})
				end
				if assignedStand ~= tostring(standName) then
					addIssue(issues, "StandAssignmentMismatch", {
						StandName = tostring(standName),
						AssignedStand = assignedStand,
						InstanceId = instanceId,
					})
				end

				local standLevel = typeof(standLevels) == "table" and tonumber(standLevels[standName]) or nil
				local instanceLevel = tonumber(instanceData.Level)
				if storageName ~= "" and standLevel == nil then
					addIssue(issues, "MissingStandLevel", {
						StandName = tostring(standName),
						StorageName = storageName,
						InstanceId = instanceId,
					})
				elseif standLevel and instanceLevel and math.floor(standLevel) ~= math.floor(instanceLevel) then
					addIssue(issues, "StandLevelMismatch", {
						StandName = tostring(standName),
						StorageName = storageName,
						InstanceId = instanceId,
						StandLevel = standLevel,
						InstanceLevel = instanceLevel,
					})
				end
			end
		elseif storageName ~= "" then
			addIssue(issues, "StandMissingInstanceId", {
				StandName = tostring(standName),
				StorageName = storageName,
			})
		end
	end

	sortIssueList(issues)
	return {
		Issues = issues,
		Summary = string.format("standConsistencyIssues=%d", #issues),
	}
end

function CrewMigrationPlanner.DetectDuplicateInstances(source)
	local legacyData = readLegacyData(source)
	local issues = {}
	local _, collectIssues = collectLegacyInstances(legacyData.BrainrotInventory)

	for _, issue in ipairs(collectIssues) do
		if issue.Kind == "DuplicateInstanceIdInOrder" then
			issues[#issues + 1] = issue
		end
	end

	local byId = typeof(legacyData.BrainrotInventory) == "table" and legacyData.BrainrotInventory.ById or {}
	local assignedByStand = {}
	if typeof(byId) == "table" then
		for instanceId, instanceData in pairs(byId) do
			if typeof(instanceData) == "table" then
				local assignedStand = tostring(instanceData.AssignedStand or "")
				if assignedStand ~= "" then
					if assignedByStand[assignedStand] ~= nil then
						addIssue(issues, "DuplicateAssignedStand", {
							StandName = assignedStand,
							InstanceId = tostring(instanceId),
							OtherInstanceId = assignedByStand[assignedStand],
						})
					else
						assignedByStand[assignedStand] = tostring(instanceId)
					end
				end
			end
		end
	end

	local standIds = {}
	for standName, standData in pairs(shallowCopy(legacyData.IncomeBrainrots)) do
		if typeof(standData) == "table" then
			local instanceId = tostring(standData.BrainrotInstanceId or "")
			if instanceId ~= "" then
				if standIds[instanceId] ~= nil then
					addIssue(issues, "DuplicateStandInstanceReference", {
						StandName = tostring(standName),
						OtherStandName = standIds[instanceId],
						InstanceId = instanceId,
					})
				else
					standIds[instanceId] = tostring(standName)
				end
			end
		end
	end

	sortIssueList(issues)
	return {
		Issues = issues,
		Summary = string.format("duplicateIssues=%d", #issues),
	}
end

function CrewMigrationPlanner.CompareLegacyToCrewMemberProjection(source, projection)
	local legacyData = readLegacyData(source)
	projection = projection or CrewMigrationPlanner.BuildCrewMemberProjection(source)

	local projectedInventory = projection[CrewProfileSchema.Keys.Inventory]
	local projectedQuickSlots = projection[CrewProfileSchema.Keys.QuickSlots]
	local projectedIncome = projection[CrewProfileSchema.Keys.Income]
	local projectedIndex = projection[CrewProfileSchema.Keys.IndexCollection][CrewProfileSchema.Keys.Index]
	local issues = {}

	for _, issue in ipairs(projection.Metadata.ProjectionIssues or {}) do
		issues[#issues + 1] = deepCopy(issue)
	end

	local legacyQuantities = collectLegacyQuantities(legacyData)
	local projectedAvailableCounts = countProjectedAvailableByStorage(projectedInventory)
	local projectedTotalCounts = countProjectedTotalByStorage(projectedInventory)
	local placedCounts = countPlacedByStorage(legacyData.IncomeBrainrots)

	for storageName in pairs(unionKeys(legacyQuantities, projectedAvailableCounts, projectedTotalCounts)) do
		local legacyQuantity = legacyQuantities[storageName] or 0
		local projectedAvailable = projectedAvailableCounts[storageName] or 0
		local projectedTotal = projectedTotalCounts[storageName] or 0
		local expectedTotal = legacyQuantity + (placedCounts[storageName] or 0)

		if legacyQuantity ~= projectedAvailable then
			addIssue(issues, "QuantityMismatch", {
				StorageName = storageName,
				LegacyQuantity = legacyQuantity,
				ProjectedAvailableInstances = projectedAvailable,
			})
		end
		if projectedTotal < expectedTotal then
			addIssue(issues, "MissingInstances", {
				StorageName = storageName,
				ExpectedInstances = expectedTotal,
				ProjectedInstances = projectedTotal,
			})
		elseif expectedTotal > 0 and projectedTotal > expectedTotal then
			addIssue(issues, "ExtraInstances", {
				StorageName = storageName,
				ExpectedInstances = expectedTotal,
				ProjectedInstances = projectedTotal,
			})
		end
	end

	for standName, standData in pairs(shallowCopy(legacyData.IncomeBrainrots)) do
		if typeof(standData) == "table" then
			local projectedStand = projectedIncome[tostring(standName)]
			if typeof(projectedStand) ~= "table" then
				addIssue(issues, "ProjectedStandMissing", {
					StandName = tostring(standName),
				})
				continue
			end

			local legacyIncome = tonumber(standData.IncomeToCollect) or 0
			local projectedIncomeToCollect = tonumber(projectedStand.IncomeToCollect) or 0
			if legacyIncome ~= projectedIncomeToCollect then
				addIssue(issues, "IncomeMismatch", {
					StandName = tostring(standName),
					LegacyIncome = legacyIncome,
					ProjectedIncome = projectedIncomeToCollect,
				})
			end
			if tostring(standData.BrainrotInstanceId or "") ~= tostring(projectedStand.CrewMemberInstanceId or "") then
				addIssue(issues, "StandInstanceProjectionMismatch", {
					StandName = tostring(standName),
					LegacyInstanceId = tostring(standData.BrainrotInstanceId or ""),
					ProjectedInstanceId = tostring(projectedStand.CrewMemberInstanceId or ""),
				})
			end
		end
	end

	local legacyQuickSlots = if typeof(legacyData.BrainrotQuickSlots) == "table" then legacyData.BrainrotQuickSlots else {}
	if math.max(0, math.floor(tonumber(legacyQuickSlots.UnlockedSlots) or 0)) ~= projectedQuickSlots.UnlockedSlots then
		addIssue(issues, "QuickSlotUnlockedMismatch", {
			LegacyUnlockedSlots = legacyQuickSlots.UnlockedSlots,
			ProjectedUnlockedSlots = projectedQuickSlots.UnlockedSlots,
		})
	end
	if math.max(0, math.floor(tonumber(legacyQuickSlots.MaxSlots) or 0)) ~= projectedQuickSlots.MaxSlots then
		addIssue(issues, "QuickSlotMaxMismatch", {
			LegacyMaxSlots = legacyQuickSlots.MaxSlots,
			ProjectedMaxSlots = projectedQuickSlots.MaxSlots,
		})
	end

	for _, inferred in ipairs(projection.Metadata.InferredIndexEntries or {}) do
		addIssue(issues, "IndexBackfillWouldAddEntry", inferred)
	end

	if typeof(legacyData.IndexBrainrots) == "table" then
		for legacyId, discovered in pairs(legacyData.IndexBrainrots) do
			if discovered == true then
				local crewMemberId = addProjectedIndexEntry({}, makeProjectionMetadata(), legacyId, "IndexCheck")
				if crewMemberId and projectedIndex[crewMemberId] ~= true then
					addIssue(issues, "IndexProjectionMissing", {
						LegacyId = tostring(legacyId),
						CrewMemberId = crewMemberId,
					})
				end
			end
		end
	end

	sortIssueList(issues)
	return {
		Projection = projection,
		Issues = issues,
		Summary = string.format(
			"legacyInstances=%d projectedInstances=%d mismatches=%d",
			projection.Metadata.LegacyInstanceCount or 0,
			projection.Metadata.ProjectedInstanceCount or 0,
			#issues
		),
	}
end

function CrewMigrationPlanner.BuildCrewProfileSnapshot(source)
	local inventoryEntries, inventoryTotals = buildInventorySnapshot(source)
	local standEntries = buildStandSnapshot(source)
	local quickSlots = readValue(source, { CrewStorage.Keys.QuickSlots })
	local indexData = readValue(source, { CrewStorage.Keys.IndexCollection, CrewStorage.Keys.Index })

	return {
		FutureKeys = table.clone(CrewStorage.FutureKeys),
		CanonicalKeys = table.clone(CrewProfileSchema.Keys),
		LegacyKeys = table.clone(CrewStorage.Keys),
		Inventory = inventoryEntries,
		InventoryTotals = inventoryTotals,
		Stands = standEntries,
		QuickSlots = shallowCopy(quickSlots),
		Index = shallowCopy(indexData),
		CompatibilityDiagnostics = CrewCompatibilityDiagnostics.Run(),
	}
end

function CrewMigrationPlanner.CompareLegacyInventoryToCrewInventory(source)
	local snapshot = CrewMigrationPlanner.BuildCrewProfileSnapshot(source)
	local issues = {}

	for _, item in ipairs(snapshot.Inventory) do
		if item.IsCompatibilityOnly then
			issues[#issues + 1] = {
				Kind = "CompatibilityOnlyInventoryItem",
				StorageName = item.StorageName,
				DisplayName = item.DisplayName,
			}
		end
		if item.IsUnknownLegacyId then
			issues[#issues + 1] = {
				Kind = "UnknownLegacyInventoryItem",
				StorageName = item.StorageName,
				DisplayName = item.DisplayName,
			}
		end
		if item.UsesFallbackModel then
			issues[#issues + 1] = {
				Kind = "ProductionCrewFallbackModel",
				StorageName = item.StorageName,
				DisplayName = item.DisplayName,
				ModelName = item.ModelName,
			}
		end
	end

	for _, stand in ipairs(snapshot.Stands) do
		if stand.IsCompatibilityOnly then
			issues[#issues + 1] = {
				Kind = "CompatibilityOnlyStandItem",
				StandName = stand.StandName,
				StorageName = stand.StorageName,
			}
		end
		if stand.IsUnknownLegacyId then
			issues[#issues + 1] = {
				Kind = "UnknownLegacyStandItem",
				StandName = stand.StandName,
				StorageName = stand.StorageName,
			}
		end
		if stand.UsesFallbackModel then
			issues[#issues + 1] = {
				Kind = "ProductionCrewStandFallbackModel",
				StandName = stand.StandName,
				StorageName = stand.StorageName,
				ModelName = stand.ModelName,
			}
		end
	end

	return {
		Snapshot = snapshot,
		Issues = issues,
		Summary = string.format(
			"inventory=%d production=%d compatibilityOnly=%d unknown=%d fallbackModels=%d brookFallback=%d stands=%d issues=%d",
			#snapshot.Inventory,
			snapshot.InventoryTotals.ProductionCrew,
			snapshot.InventoryTotals.CompatibilityOnly,
			snapshot.InventoryTotals.UnknownLegacyIds,
			snapshot.InventoryTotals.FallbackModel,
			snapshot.InventoryTotals.BrookFallback,
			#snapshot.Stands,
			#issues
		),
	}
end

local reviewIssueKinds = {
	ByIdInstanceMissingFromOrder = true,
	IndexBackfillWouldAddEntry = true,
	ProjectionSynthesizedLegacyInstances = true,
}

local unsafeIssueKinds = {
	BlankInstanceIdInOrder = true,
	DuplicateAssignedStand = true,
	DuplicateInstanceIdInOrder = true,
	DuplicateStandInstanceReference = true,
	ExtraInstances = true,
	IncomeMismatch = true,
	InvalidInstanceData = true,
	InvalidStandData = true,
	MissingInstances = true,
	MissingStandLevel = true,
	OrderInstanceMissingById = true,
	ProjectedStandMissing = true,
	QuantityMismatch = true,
	QuickSlotMaxMismatch = true,
	QuickSlotUnlockedMismatch = true,
	StandAssignmentMismatch = true,
	StandInstanceMissing = true,
	StandInstanceProjectionMismatch = true,
	StandInstanceWithoutName = true,
	StandLevelMismatch = true,
	StandMissingInstanceId = true,
	StandNameMismatch = true,
	UnknownLegacyInventoryItem = true,
	UnknownLegacyStandItem = true,
}

local function classifyReadiness(diffIssues, standIssues, projection)
	local hasUnsafe = false
	local hasReview = false

	for _, issue in ipairs(diffIssues) do
		if unsafeIssueKinds[issue.Kind] then
			hasUnsafe = true
		elseif reviewIssueKinds[issue.Kind] then
			hasReview = true
		end
	end

	for _, issue in ipairs(standIssues) do
		if unsafeIssueKinds[issue.Kind] then
			hasUnsafe = true
		else
			hasReview = true
		end
	end

	local metadata = projection.Metadata or {}
	if #(metadata.UnknownLegacyIds or {}) > 0 then
		hasUnsafe = true
	end
	if #(metadata.CompatibilityOnlyLegacyIds or {}) > 0 then
		hasReview = true
	end

	if hasUnsafe then
		return "unsafe"
	end
	if hasReview then
		return "needs_review"
	end
	return "safe"
end

function CrewMigrationPlanner.BuildReadinessReport(source)
	local projection = CrewMigrationPlanner.BuildCrewMemberProjection(source)
	local diff = CrewMigrationPlanner.CompareLegacyToCrewMemberProjection(source, projection)
	local standConsistency = CrewMigrationPlanner.ValidateStandConsistency(source)
	local duplicateReport = CrewMigrationPlanner.DetectDuplicateInstances(source)
	local metadata = projection.Metadata or {}
	local status = classifyReadiness(diff.Issues, standConsistency.Issues, projection)

	return {
		CanProjectSafely = status ~= "unsafe",
		MigrationStatus = status,
		LegacyInstanceCount = metadata.LegacyInstanceCount or 0,
		ProjectedCrewMemberInstanceCount = metadata.ProjectedInstanceCount or 0,
		MismatchCount = #diff.Issues,
		StandConsistencyIssueCount = #standConsistency.Issues,
		DuplicateIssueCount = #duplicateReport.Issues,
		UnknownLegacyIds = metadata.UnknownLegacyIds or {},
		CompatibilityOnlyLegacyIds = metadata.CompatibilityOnlyLegacyIds or {},
		BrookFallbackCount = metadata.BrookFallbackCount or 0,
		BrookFallbackEntries = metadata.BrookFallbackEntries or {},
		ProductionFallbackEntries = metadata.ProductionFallbackEntries or {},
		InferredIndexEntries = metadata.InferredIndexEntries or {},
		Projection = projection,
		Diff = diff,
		StandConsistency = standConsistency,
		Duplicates = duplicateReport,
		Summary = string.format(
			"status=%s canProject=%s legacyInstances=%d projectedInstances=%d mismatches=%d standIssues=%d duplicateIssues=%d unknown=%d compatibilityOnly=%d brookFallback=%d",
			status,
			tostring(status ~= "unsafe"),
			metadata.LegacyInstanceCount or 0,
			metadata.ProjectedInstanceCount or 0,
			#diff.Issues,
			#standConsistency.Issues,
			#duplicateReport.Issues,
			#(metadata.UnknownLegacyIds or {}),
			#(metadata.CompatibilityOnlyLegacyIds or {}),
			metadata.BrookFallbackCount or 0
		),
	}
end

function CrewMigrationPlanner.PrintReadinessReport(source)
	local report = CrewMigrationPlanner.BuildReadinessReport(source)
	print("[CrewMigrationPlanner] readiness " .. report.Summary)

	local function printIssues(label, issues)
		print(string.format("[CrewMigrationPlanner] %s=%d", label, #issues))
		for _, issue in ipairs(issues) do
			print(string.format(
				"[CrewMigrationPlanner] issue=%s storage=%s stand=%s instance=%s detail=%s",
				tostring(issue.Kind),
				tostring(issue.StorageName or issue.LegacyStorageName or issue.LegacyId or ""),
				tostring(issue.StandName or ""),
				tostring(issue.InstanceId or issue.CrewMemberInstanceId or ""),
				tostring(issue.CrewMemberId or issue.DisplayName or "")
			))
		end
	end

	printIssues("mismatches", report.Diff.Issues)
	printIssues("standConsistencyIssues", report.StandConsistency.Issues)
	printIssues("duplicateIssues", report.Duplicates.Issues)
	return report
end

function CrewMigrationPlanner.PrintReport(source)
	local report = CrewMigrationPlanner.CompareLegacyInventoryToCrewInventory(source)
	print("[CrewMigrationPlanner] " .. report.Summary)
	for _, issue in ipairs(report.Issues) do
		print(string.format(
			"[CrewMigrationPlanner] issue=%s storage=%s stand=%s model=%s",
			tostring(issue.Kind),
			tostring(issue.StorageName),
			tostring(issue.StandName or ""),
			tostring(issue.ModelName or "")
		))
	end
	return report
end

local diagnosticCategoryByIssueKind = {
	BlankInstanceIdInOrder = "missing_key",
	BrookFallback = "brook_fallback",
	ByIdInstanceMissingFromOrder = "missing_key",
	CanonicalIndexExtra = "missing_key",
	CanonicalIndexMissing = "missing_key",
	CanonicalIncomeExtra = "income_mismatch",
	CanonicalIncomeMissing = "income_mismatch",
	CanonicalInventoryExtra = "instance_mismatch",
	CanonicalInventoryMissing = "missing_key",
	CanonicalInventoryOrderMismatch = "instance_mismatch",
	CanonicalRootMissing = "missing_key",
	CanonicalShapeInvalid = "canonical_shape_invalid",
	CompatibilityOnlyLegacyId = "compatibility_only",
	DuplicateAssignedStand = "duplicate_assignment",
	DuplicateStandInstanceReference = "duplicate_assignment",
	ExtraInstances = "instance_mismatch",
	IncomeMismatch = "income_mismatch",
	InvalidInstanceData = "canonical_shape_invalid",
	InvalidStandData = "canonical_shape_invalid",
	LevelMismatch = "level_mismatch",
	MissingInstances = "missing_key",
	MissingStandLevel = "missing_key",
	OrderInstanceMissingById = "missing_key",
	ProjectedStandMissing = "income_mismatch",
	ProjectionSynthesizedLegacyInstances = "missing_key",
	ProductionFallbackModel = "brook_fallback",
	QuickSlotMaxMismatch = "instance_mismatch",
	QuickSlotUnlockedMismatch = "instance_mismatch",
	SnapshotMissing = "missing_key",
	SnapshotRootMismatch = "instance_mismatch",
	StandAssignmentMismatch = "stand_mismatch",
	StandInstanceMissing = "missing_key",
	StandInstanceProjectionMismatch = "instance_mismatch",
	StandInstanceWithoutName = "missing_key",
	StandLevelMismatch = "level_mismatch",
	StandMissingInstanceId = "missing_key",
	StandNameMismatch = "identity_mismatch",
	UnknownLegacyId = "unknown_id",
	UnknownLegacyInventoryItem = "unknown_id",
	UnknownLegacyStandItem = "unknown_id",
	XPMismatch = "xp_mismatch",
}

local nonBlockingDiagnosticIssueKinds = {
	BrookFallback = true,
	CompatibilityOnlyLegacyId = true,
	IndexBackfillWouldAddEntry = true,
	ProductionFallbackModel = true,
}

local function getDiagnosticIssueCategory(kind)
	return diagnosticCategoryByIssueKind[tostring(kind or "")] or "canonical_shape_invalid"
end

local function addDiagnosticIssue(issues, kind, detail, blocking)
	detail = if typeof(detail) == "table" then detail else {}
	detail.Category = detail.Category or getDiagnosticIssueCategory(kind)
	detail.Blocking = blocking ~= false
	return addIssue(issues, kind, detail)
end

local function addCategorizedIssues(target, sourceIssues)
	for _, issue in ipairs(sourceIssues or {}) do
		local cloned = deepCopy(issue)
		local kind = tostring(cloned.Kind or "")
		cloned.Category = cloned.Category or getDiagnosticIssueCategory(kind)
		cloned.Blocking = nonBlockingDiagnosticIssueKinds[kind] ~= true
		target[#target + 1] = cloned
	end
end

local function countArray(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _ in ipairs(value) do
		count += 1
	end
	return count
end

local function countDiscoveredIndex(value)
	if typeof(value) ~= "table" then
		return 0
	end

	local count = 0
	for _, discovered in pairs(value) do
		if discovered == true then
			count += 1
		end
	end
	return count
end

local function readCanonicalData(source)
	return {
		CrewMemberInventory = readValue(source, { CrewStorage.FutureKeys.Inventory }),
		CrewMemberQuickSlots = readValue(source, { CrewStorage.FutureKeys.QuickSlots }),
		CrewMemberIncome = readValue(source, { CrewStorage.FutureKeys.Income }),
		IndexCrewMembers = readValue(source, { CrewStorage.FutureKeys.IndexCollection, CrewStorage.FutureKeys.Index }),
	}
end

local function getInventoryCounts(inventory)
	local byId = typeof(inventory) == "table" and inventory.ById or nil
	local order = typeof(inventory) == "table" and inventory.Order or nil
	return {
		ById = countPairs(byId),
		Order = countArray(order),
	}
end

local function getRootCounts(legacyData, canonicalData, projection)
	local legacyInventoryCounts = getInventoryCounts(legacyData and legacyData.BrainrotInventory)
	local canonicalInventoryCounts = getInventoryCounts(canonicalData and canonicalData.CrewMemberInventory)
	local projectedInventory = projection and projection[CrewProfileSchema.Keys.Inventory] or nil
	local projectedInventoryCounts = getInventoryCounts(projectedInventory)

	return {
		LegacyInstances = legacyInventoryCounts.ById,
		LegacyOrder = legacyInventoryCounts.Order,
		ProjectedInstances = projectedInventoryCounts.ById,
		ProjectedOrder = projectedInventoryCounts.Order,
		LiveCanonicalInstances = canonicalInventoryCounts.ById,
		LiveCanonicalOrder = canonicalInventoryCounts.Order,
		LegacyQuickSlotKeys = countPairs(legacyData and legacyData.BrainrotQuickSlots),
		CanonicalQuickSlotKeys = countPairs(canonicalData and canonicalData.CrewMemberQuickSlots),
		LegacyStandRows = countPairs(legacyData and legacyData.IncomeBrainrots),
		ProjectedIncomeRows = countPairs(projection and projection[CrewProfileSchema.Keys.Income]),
		LiveCanonicalIncomeRows = countPairs(canonicalData and canonicalData.CrewMemberIncome),
		LegacyIndexEntries = countDiscoveredIndex(legacyData and legacyData.IndexBrainrots),
		ProjectedIndexEntries = countDiscoveredIndex(
			projection
				and projection[CrewProfileSchema.Keys.IndexCollection]
				and projection[CrewProfileSchema.Keys.IndexCollection][CrewProfileSchema.Keys.Index]
		),
		LiveCanonicalIndexEntries = countDiscoveredIndex(canonicalData and canonicalData.IndexCrewMembers),
		StandsLevels = countPairs(legacyData and legacyData.StandsLevels),
		FoodInventoryKeys = countPairs(legacyData and legacyData.FoodInventory),
	}
end

local function getSourceMetadata(source, options)
	options = if typeof(options) == "table" then options else {}
	local validation = if typeof(options.ValidationStatus) == "table" then options.ValidationStatus else nil
	local keys = validation and validation.CanonicalKeys
	local maxValidationAgeSeconds =
		math.max(0, tonumber(options.MaxValidationAgeSeconds or CrewMemberShadowConfig.CanonicalReadValidationFreshnessSeconds) or 120)
	local validationAgeSeconds = validation and tonumber(validation.ValidationAgeSeconds) or math.huge

	local userId = options.UserId
	local playerName = options.PlayerName
	if typeof(source) == "Instance" and source:IsA("Player") then
		userId = source.UserId
		playerName = source.Name
	end

	local validationSummary = {
		Present = validation ~= nil,
		AgeSeconds = if validationAgeSeconds == math.huge then nil else validationAgeSeconds,
		IsStale = validation == nil or (maxValidationAgeSeconds > 0 and validationAgeSeconds > maxValidationAgeSeconds),
		CanonicalKeysValid = typeof(keys) == "table" and keys.IsValid == true,
		BlockingIssueCount = validation and validation.BlockingIssueCount or 0,
		MismatchCount = validation and validation.MismatchCount or 0,
		StandIssueCount = validation and validation.StandIssueCount or 0,
		DuplicateIssueCount = validation and validation.DuplicateIssueCount or 0,
		UnknownLegacyIdCount = validation and validation.UnknownLegacyIdCount or 0,
		BlockingIncomeMismatchCount = validation and validation.BlockingIncomeMismatchCount or 0,
		CompatibilityOnlyIdCount = validation and validation.CompatibilityOnlyIdCount or 0,
		BrookFallbackCount = validation and validation.BrookFallbackCount or 0,
	}
	validationSummary.IsClean = validationSummary.Present == true
		and validationSummary.IsStale ~= true
		and validationSummary.CanonicalKeysValid == true
		and validationSummary.BlockingIssueCount == 0
		and validationSummary.MismatchCount == 0
		and validationSummary.StandIssueCount == 0
		and validationSummary.DuplicateIssueCount == 0
		and validationSummary.UnknownLegacyIdCount == 0
		and validationSummary.BlockingIncomeMismatchCount == 0

	return {
		UserId = userId,
		PlayerName = playerName,
		PlaceId = game.PlaceId,
		GameId = game.GameId,
		JobId = game.JobId,
		TimestampUnix = os.time(),
		TimestampClock = os.clock(),
		ToolVersion = MIGRATION_TOOL_VERSION,
		ValidationSummary = validationSummary,
	}
end

local function buildMismatchSummary(issues)
	local categoryCounts = {}
	local blockingCount = 0
	local reviewCount = 0
	local unclassifiedCount = 0

	for _, issue in ipairs(issues or {}) do
		local category = tostring(issue.Category or getDiagnosticIssueCategory(issue.Kind))
		categoryCounts[category] = (categoryCounts[category] or 0) + 1
		if diagnosticCategoryByIssueKind[tostring(issue.Kind or "")] == nil
			and issue.Category == nil
			and nonBlockingDiagnosticIssueKinds[tostring(issue.Kind or "")] ~= true
		then
			unclassifiedCount += 1
		end
		if issue.Blocking == false then
			reviewCount += 1
		else
			blockingCount += 1
		end
	end

	return {
		CategoryCounts = categoryCounts,
		BlockingCount = blockingCount,
		ReviewCount = reviewCount,
		UnclassifiedCount = unclassifiedCount,
	}
end

local function compactCategoryCounts(categoryCounts)
	local parts = {}
	for category, count in pairs(categoryCounts or {}) do
		parts[#parts + 1] = tostring(category) .. "=" .. tostring(count)
	end
	table.sort(parts)
	return if #parts > 0 then table.concat(parts, ",") else "none"
end

local function makeProjectionSampleRows(projection, canonicalData, limit)
	local rows = {}
	limit = math.max(1, math.floor(tonumber(limit) or 8))
	local projectedInventory = projection and projection[CrewProfileSchema.Keys.Inventory]
	local projectedById = typeof(projectedInventory) == "table" and projectedInventory.ById or {}
	local projectedOrder = typeof(projectedInventory) == "table" and projectedInventory.Order or {}
	local liveInventory = canonicalData and canonicalData.CrewMemberInventory
	local liveById = typeof(liveInventory) == "table" and liveInventory.ById or {}

	for _, instanceId in ipairs(projectedOrder) do
		if #rows >= limit then
			break
		end
		local projectedInstance = projectedById[tostring(instanceId)]
		local liveInstance = liveById[tostring(instanceId)]
		if typeof(projectedInstance) == "table" then
			rows[#rows + 1] = {
				InstanceId = tostring(instanceId),
				LegacyStorageName = tostring(projectedInstance.LegacyStorageName or ""),
				CrewMemberId = tostring(projectedInstance.CrewMemberId or ""),
				AssignedStand = tostring(projectedInstance.AssignedStand or ""),
				Level = tonumber(projectedInstance.Level) or 1,
				CurrentXP = tonumber(projectedInstance.CurrentXP) or 0,
				LiveCrewMemberId = if typeof(liveInstance) == "table" then tostring(liveInstance.CrewMemberId or "") else "",
				LiveAssignedStand = if typeof(liveInstance) == "table" then tostring(liveInstance.AssignedStand or "") else "",
			}
		end
	end

	return rows
end

local function addMetadataClassificationIssues(issues, metadata)
	metadata = if typeof(metadata) == "table" then metadata else {}
	for _, entry in ipairs(metadata.UnknownLegacyIds or {}) do
		addDiagnosticIssue(issues, "UnknownLegacyId", deepCopy(entry), true)
	end
	for _, entry in ipairs(metadata.CompatibilityOnlyLegacyIds or {}) do
		addDiagnosticIssue(issues, "CompatibilityOnlyLegacyId", deepCopy(entry), false)
	end
	for _, entry in ipairs(metadata.BrookFallbackEntries or {}) do
		addDiagnosticIssue(issues, "BrookFallback", deepCopy(entry), false)
	end
	for _, entry in ipairs(metadata.ProductionFallbackEntries or {}) do
		addDiagnosticIssue(issues, "ProductionFallbackModel", deepCopy(entry), false)
	end
end

local function compareScalarField(issues, kind, category, instanceId, fieldName, left, right, blocking)
	if tostring(left or "") == tostring(right or "") then
		return
	end

	addDiagnosticIssue(issues, kind, {
		Category = category,
		InstanceId = tostring(instanceId or ""),
		Field = tostring(fieldName or ""),
		Projected = left,
		Live = right,
	}, blocking)
end

local function compareNumberField(issues, kind, category, instanceId, fieldName, left, right, blocking)
	local leftNumber = math.floor(tonumber(left) or 0)
	local rightNumber = math.floor(tonumber(right) or 0)
	if leftNumber == rightNumber then
		return
	end

	addDiagnosticIssue(issues, kind, {
		Category = category,
		InstanceId = tostring(instanceId or ""),
		Field = tostring(fieldName or ""),
		Projected = leftNumber,
		Live = rightNumber,
	}, blocking)
end

local function compareCanonicalInventoryToProjection(issues, canonicalData, projection)
	local liveInventory = canonicalData and canonicalData.CrewMemberInventory
	local projectedInventory = projection and projection[CrewProfileSchema.Keys.Inventory]
	if typeof(liveInventory) ~= "table" then
		addDiagnosticIssue(issues, "CanonicalRootMissing", {
			Path = CrewStorage.FutureKeys.Inventory,
		}, true)
		return
	end
	if typeof(liveInventory.ById) ~= "table" or typeof(liveInventory.Order) ~= "table" then
		addDiagnosticIssue(issues, "CanonicalShapeInvalid", {
			Path = CrewStorage.FutureKeys.Inventory,
		}, true)
		return
	end

	local projectedById = typeof(projectedInventory) == "table" and projectedInventory.ById or {}
	local projectedOrder = typeof(projectedInventory) == "table" and projectedInventory.Order or {}
	if #liveInventory.Order ~= #projectedOrder then
		addDiagnosticIssue(issues, "CanonicalInventoryOrderMismatch", {
			ProjectedOrder = #projectedOrder,
			LiveOrder = #liveInventory.Order,
		}, true)
	end

	local projectedSeen = {}
	for _, instanceId in ipairs(projectedOrder) do
		local key = tostring(instanceId)
		projectedSeen[key] = true
		local projectedInstance = projectedById[key]
		local liveInstance = liveInventory.ById[key]
		if typeof(projectedInstance) ~= "table" then
			continue
		end
		if typeof(liveInstance) ~= "table" then
			addDiagnosticIssue(issues, "CanonicalInventoryMissing", {
				InstanceId = key,
				LegacyStorageName = tostring(projectedInstance.LegacyStorageName or ""),
			}, true)
			continue
		end

		compareScalarField(issues, "InstanceMismatch", "instance_mismatch", key, "InstanceId", projectedInstance.InstanceId, liveInstance.InstanceId, true)
		compareScalarField(issues, "IdentityMismatch", "identity_mismatch", key, "CrewMemberId", projectedInstance.CrewMemberId, liveInstance.CrewMemberId, true)
		compareScalarField(issues, "IdentityMismatch", "identity_mismatch", key, "LegacyStorageName", projectedInstance.LegacyStorageName, liveInstance.LegacyStorageName, true)
		compareScalarField(issues, "StandAssignmentMismatch", "stand_mismatch", key, "AssignedStand", projectedInstance.AssignedStand, liveInstance.AssignedStand, true)
		compareNumberField(issues, "LevelMismatch", "level_mismatch", key, "Level", projectedInstance.Level, liveInstance.Level, true)
		compareNumberField(issues, "XPMismatch", "xp_mismatch", key, "CurrentXP", projectedInstance.CurrentXP, liveInstance.CurrentXP, true)
	end

	for instanceId, liveInstance in pairs(liveInventory.ById) do
		if projectedSeen[tostring(instanceId)] ~= true then
			addDiagnosticIssue(issues, "CanonicalInventoryExtra", {
				InstanceId = tostring(instanceId),
				LegacyStorageName = if typeof(liveInstance) == "table" then tostring(liveInstance.LegacyStorageName or "") else "",
			}, true)
		end
	end

	local assignedByStand = {}
	for instanceId, liveInstance in pairs(liveInventory.ById) do
		if typeof(liveInstance) == "table" then
			local assignedStand = tostring(liveInstance.AssignedStand or "")
			if assignedStand ~= "" then
				if assignedByStand[assignedStand] ~= nil then
					addDiagnosticIssue(issues, "DuplicateAssignedStand", {
						StandName = assignedStand,
						InstanceId = tostring(instanceId),
						OtherInstanceId = assignedByStand[assignedStand],
					}, true)
				else
					assignedByStand[assignedStand] = tostring(instanceId)
				end
			end
		end
	end
end

local function compareCanonicalQuickSlotsToProjection(issues, canonicalData, projection)
	local liveQuickSlots = canonicalData and canonicalData.CrewMemberQuickSlots
	local projectedQuickSlots = projection and projection[CrewProfileSchema.Keys.QuickSlots]
	if typeof(liveQuickSlots) ~= "table" then
		addDiagnosticIssue(issues, "CanonicalRootMissing", {
			Path = CrewStorage.FutureKeys.QuickSlots,
		}, true)
		return
	end

	compareNumberField(issues, "QuickSlotUnlockedMismatch", "instance_mismatch", "", "UnlockedSlots", projectedQuickSlots and projectedQuickSlots.UnlockedSlots, liveQuickSlots.UnlockedSlots, true)
	compareNumberField(issues, "QuickSlotMaxMismatch", "instance_mismatch", "", "MaxSlots", projectedQuickSlots and projectedQuickSlots.MaxSlots, liveQuickSlots.MaxSlots, true)
end

local function compareCanonicalIncomeToProjection(issues, canonicalData, projection)
	local liveIncome = canonicalData and canonicalData.CrewMemberIncome
	local projectedIncome = projection and projection[CrewProfileSchema.Keys.Income]
	if typeof(liveIncome) ~= "table" then
		addDiagnosticIssue(issues, "CanonicalRootMissing", {
			Path = CrewStorage.FutureKeys.Income,
		}, true)
		return 0
	end

	local amountDeltaRows = 0
	local projectedSeen = {}
	for standName, projectedRow in pairs(projectedIncome or {}) do
		local standKey = tostring(standName)
		projectedSeen[standKey] = true
		local liveRow = liveIncome[standKey]
		if typeof(projectedRow) ~= "table" then
			continue
		end
		if typeof(liveRow) ~= "table" then
			addDiagnosticIssue(issues, "CanonicalIncomeMissing", {
				StandName = standKey,
				LegacyStorageName = tostring(projectedRow.LegacyStorageName or ""),
				InstanceId = tostring(projectedRow.CrewMemberInstanceId or ""),
			}, true)
			continue
		end

		compareScalarField(issues, "IncomeIdentityMismatch", "income_mismatch", standKey, "CrewMemberName", projectedRow.CrewMemberName, liveRow.CrewMemberName, true)
		compareScalarField(issues, "IncomeIdentityMismatch", "income_mismatch", standKey, "LegacyStorageName", projectedRow.LegacyStorageName, liveRow.LegacyStorageName, true)
		compareScalarField(issues, "StandInstanceProjectionMismatch", "instance_mismatch", standKey, "CrewMemberInstanceId", projectedRow.CrewMemberInstanceId, liveRow.CrewMemberInstanceId, true)

		if math.floor(tonumber(projectedRow.IncomeToCollect) or 0) ~= math.floor(tonumber(liveRow.IncomeToCollect) or 0) then
			amountDeltaRows += 1
		end
	end

	for standName in pairs(liveIncome) do
		if projectedSeen[tostring(standName)] ~= true then
			addDiagnosticIssue(issues, "CanonicalIncomeExtra", {
				StandName = tostring(standName),
			}, true)
		end
	end

	return amountDeltaRows
end

local function compareCanonicalIndexToProjection(issues, canonicalData, projection)
	local liveIndex = canonicalData and canonicalData.IndexCrewMembers
	local projectedIndexCollection = projection and projection[CrewProfileSchema.Keys.IndexCollection]
	local projectedIndex = projectedIndexCollection and projectedIndexCollection[CrewProfileSchema.Keys.Index]
	if typeof(liveIndex) ~= "table" then
		addDiagnosticIssue(issues, "CanonicalRootMissing", {
			Path = CrewStorage.FutureKeys.IndexCollection .. "." .. CrewStorage.FutureKeys.Index,
		}, true)
		return
	end

	for crewMemberId, discovered in pairs(projectedIndex or {}) do
		if discovered == true and liveIndex[crewMemberId] ~= true then
			addDiagnosticIssue(issues, "CanonicalIndexMissing", {
				CrewMemberId = tostring(crewMemberId),
			}, true)
		end
	end
	for crewMemberId, discovered in pairs(liveIndex) do
		if discovered == true and (projectedIndex == nil or projectedIndex[crewMemberId] ~= true) then
			addDiagnosticIssue(issues, "CanonicalIndexExtra", {
				CrewMemberId = tostring(crewMemberId),
			}, true)
		end
	end
end

local function compareLiveCanonicalToProjection(source, projection)
	local canonicalData = readCanonicalData(source)
	local issues = {}

	compareCanonicalInventoryToProjection(issues, canonicalData, projection)
	compareCanonicalQuickSlotsToProjection(issues, canonicalData, projection)
	local incomeAmountDeltaRows = compareCanonicalIncomeToProjection(issues, canonicalData, projection)
	compareCanonicalIndexToProjection(issues, canonicalData, projection)
	sortIssueList(issues)

	local mismatchSummary = buildMismatchSummary(issues)
	return {
		Issues = issues,
		MismatchCountsByCategory = mismatchSummary.CategoryCounts,
		BlockingCount = mismatchSummary.BlockingCount,
		ReviewCount = mismatchSummary.ReviewCount,
		UnclassifiedCount = mismatchSummary.UnclassifiedCount,
		IncomeAmountDeltaRows = incomeAmountDeltaRows,
		CanonicalData = canonicalData,
		Summary = string.format(
			"liveCanonicalIssues=%d blocking=%d review=%d incomeAmountDeltaRows=%d categories=%s",
			#issues,
			mismatchSummary.BlockingCount,
			mismatchSummary.ReviewCount,
			incomeAmountDeltaRows,
			compactCategoryCounts(mismatchSummary.CategoryCounts)
		),
	}
end

function CrewMigrationPlanner.BuildMigrationSnapshot(source, options)
	options = if typeof(options) == "table" then options else {}
	local legacyData = readLegacyData(source)
	local canonicalData = readCanonicalData(source)
	local metadata = getSourceMetadata(source, options)
	local counts = getRootCounts(legacyData, canonicalData, nil)

	local snapshot = {
		Metadata = metadata,
		Legacy = {
			BrainrotInventory = deepCopy(legacyData.BrainrotInventory),
			BrainrotQuickSlots = deepCopy(legacyData.BrainrotQuickSlots),
			BrainrotStorage = deepCopy(legacyData.BrainrotStorage),
			IncomeBrainrots = deepCopy(legacyData.IncomeBrainrots),
			IndexCollection = {
				Brainrots = deepCopy(legacyData.IndexBrainrots),
			},
			StandsLevels = deepCopy(legacyData.StandsLevels),
			FoodInventory = deepCopy(legacyData.FoodInventory),
			InventoryFeed = deepCopy(typeof(legacyData.Inventory) == "table" and legacyData.Inventory.Feed or nil),
		},
		Canonical = {
			CrewMemberInventory = deepCopy(canonicalData.CrewMemberInventory),
			CrewMemberQuickSlots = deepCopy(canonicalData.CrewMemberQuickSlots),
			CrewMemberIncome = deepCopy(canonicalData.CrewMemberIncome),
			IndexCollection = {
				CrewMembers = deepCopy(canonicalData.IndexCrewMembers),
			},
		},
		Counts = counts,
	}
	snapshot.Summary = string.format(
		"snapshot legacyInstances=%d canonicalInstances=%d legacyStands=%d canonicalIncomeRows=%d legacyIndex=%d canonicalIndex=%d validationClean=%s validationStale=%s toolVersion=%s",
		counts.LegacyInstances,
		counts.LiveCanonicalInstances,
		counts.LegacyStandRows,
		counts.LiveCanonicalIncomeRows,
		counts.LegacyIndexEntries,
		counts.LiveCanonicalIndexEntries,
		tostring(metadata.ValidationSummary.IsClean),
		tostring(metadata.ValidationSummary.IsStale),
		MIGRATION_TOOL_VERSION
	)
	return snapshot
end

function CrewMigrationPlanner.BuildMigrationDryRunReport(source, options)
	options = if typeof(options) == "table" then options else {}
	local projection = CrewMigrationPlanner.BuildCrewMemberProjection(source)
	local diff = CrewMigrationPlanner.CompareLegacyToCrewMemberProjection(source, projection)
	local standConsistency = CrewMigrationPlanner.ValidateStandConsistency(source)
	local duplicateReport = CrewMigrationPlanner.DetectDuplicateInstances(source)
	local legacyData = readLegacyData(source)
	local canonicalData = readCanonicalData(source)
	local issues = {}

	addCategorizedIssues(issues, diff.Issues)
	addCategorizedIssues(issues, standConsistency.Issues)
	addCategorizedIssues(issues, duplicateReport.Issues)
	addMetadataClassificationIssues(issues, projection.Metadata)
	sortIssueList(issues)

	local mismatchSummary = buildMismatchSummary(issues)
	local counts = getRootCounts(legacyData, canonicalData, projection)
	local metadata = getSourceMetadata(source, options)
	local report = {
		Metadata = metadata,
		Projection = projection,
		Diff = diff,
		StandConsistency = standConsistency,
		Duplicates = duplicateReport,
		Issues = issues,
		MismatchCountsByCategory = mismatchSummary.CategoryCounts,
		BlockingCount = mismatchSummary.BlockingCount,
		ReviewCount = mismatchSummary.ReviewCount,
		UnclassifiedCount = mismatchSummary.UnclassifiedCount,
		Counts = counts,
		SampleRows = makeProjectionSampleRows(projection, canonicalData, 8),
	}
	report.CanProceed = report.BlockingCount == 0
		and report.UnclassifiedCount == 0
		and metadata.ValidationSummary.IsClean == true
	report.Summary = string.format(
		"dryrun legacyInstances=%d projectedInstances=%d legacyStands=%d projectedIncomeRows=%d legacyIndex=%d projectedIndex=%d issues=%d blocking=%d review=%d unclassified=%d validationClean=%s categories=%s",
		counts.LegacyInstances,
		counts.ProjectedInstances,
		counts.LegacyStandRows,
		counts.ProjectedIncomeRows,
		counts.LegacyIndexEntries,
		counts.ProjectedIndexEntries,
		#issues,
		report.BlockingCount,
		report.ReviewCount,
		report.UnclassifiedCount,
		tostring(metadata.ValidationSummary.IsClean),
		compactCategoryCounts(report.MismatchCountsByCategory)
	)
	return report
end

local compareSnapshotToCurrent

function CrewMigrationPlanner.BuildMigrationCompareReport(source, options)
	options = if typeof(options) == "table" then options else {}
	local dryRun = CrewMigrationPlanner.BuildMigrationDryRunReport(source, options)
	local liveCompare = compareLiveCanonicalToProjection(source, dryRun.Projection)
	local currentSnapshot = if options.Snapshot ~= nil then CrewMigrationPlanner.BuildMigrationSnapshot(source, options) else nil
	local snapshotIssues = if options.Snapshot ~= nil and compareSnapshotToCurrent ~= nil
		then compareSnapshotToCurrent(options.Snapshot, currentSnapshot)
		else {}
	local issues = {}

	addCategorizedIssues(issues, dryRun.Issues)
	addCategorizedIssues(issues, liveCompare.Issues)
	addCategorizedIssues(issues, snapshotIssues)
	sortIssueList(issues)

	local mismatchSummary = buildMismatchSummary(issues)
	local legacyData = readLegacyData(source)
	local canonicalData = readCanonicalData(source)
	local counts = getRootCounts(legacyData, canonicalData, dryRun.Projection)
	local report = {
		Metadata = dryRun.Metadata,
		DryRun = dryRun,
		LiveCompare = liveCompare,
		SnapshotIssues = snapshotIssues,
		Issues = issues,
		MismatchCountsByCategory = mismatchSummary.CategoryCounts,
		BlockingCount = mismatchSummary.BlockingCount,
		ReviewCount = mismatchSummary.ReviewCount,
		UnclassifiedCount = mismatchSummary.UnclassifiedCount,
		Counts = counts,
		SampleRows = dryRun.SampleRows,
		SnapshotCompared = options.Snapshot ~= nil,
	}
	report.CanProceed = report.BlockingCount == 0
		and report.UnclassifiedCount == 0
		and report.Metadata.ValidationSummary.IsClean == true
	report.Summary = string.format(
		"compare legacyInstances=%d projectedInstances=%d liveCanonicalInstances=%d quickSlotKeys=%d/%d standRows=%d incomeRows=%d/%d index=%d/%d/%d issues=%d blocking=%d review=%d unclassified=%d liveIncomeAmountDeltaRows=%d validationClean=%s snapshotCompared=%s snapshotIssues=%d categories=%s",
		counts.LegacyInstances,
		counts.ProjectedInstances,
		counts.LiveCanonicalInstances,
		counts.LegacyQuickSlotKeys,
		counts.CanonicalQuickSlotKeys,
		counts.LegacyStandRows,
		counts.ProjectedIncomeRows,
		counts.LiveCanonicalIncomeRows,
		counts.LegacyIndexEntries,
		counts.ProjectedIndexEntries,
		counts.LiveCanonicalIndexEntries,
		#issues,
		report.BlockingCount,
		report.ReviewCount,
		report.UnclassifiedCount,
		liveCompare.IncomeAmountDeltaRows,
		tostring(report.Metadata.ValidationSummary.IsClean),
		tostring(report.SnapshotCompared),
		#snapshotIssues,
		compactCategoryCounts(report.MismatchCountsByCategory)
	)
	return report
end

local function compareSnapshotScalar(issues, rootName, fieldName, before, after, category)
	if tostring(before or "") == tostring(after or "") then
		return
	end

	addDiagnosticIssue(issues, "SnapshotRootMismatch", {
		Category = category or "instance_mismatch",
		Root = tostring(rootName or ""),
		Field = tostring(fieldName or ""),
		Before = before,
		After = after,
	}, true)
end

local function compareSnapshotNumber(issues, rootName, fieldName, before, after, category)
	local beforeNumber = math.floor(tonumber(before) or 0)
	local afterNumber = math.floor(tonumber(after) or 0)
	if beforeNumber == afterNumber then
		return
	end

	addDiagnosticIssue(issues, "SnapshotRootMismatch", {
		Category = category or "instance_mismatch",
		Root = tostring(rootName or ""),
		Field = tostring(fieldName or ""),
		Before = beforeNumber,
		After = afterNumber,
	}, true)
end

local function compareInventorySnapshot(issues, rootName, beforeInventory, afterInventory)
	local beforeById = typeof(beforeInventory) == "table" and beforeInventory.ById or nil
	local beforeOrder = typeof(beforeInventory) == "table" and beforeInventory.Order or nil
	local afterById = typeof(afterInventory) == "table" and afterInventory.ById or nil
	local afterOrder = typeof(afterInventory) == "table" and afterInventory.Order or nil
	if typeof(beforeById) ~= "table" or typeof(afterById) ~= "table" then
		compareSnapshotScalar(issues, rootName, "ByIdShape", typeof(beforeById), typeof(afterById), "canonical_shape_invalid")
		return
	end

	compareSnapshotNumber(issues, rootName, "OrderCount", countArray(beforeOrder), countArray(afterOrder), "instance_mismatch")
	compareSnapshotNumber(issues, rootName, "ByIdCount", countPairs(beforeById), countPairs(afterById), "instance_mismatch")
	for instanceId, beforeInstance in pairs(beforeById) do
		local afterInstance = afterById[instanceId]
		if typeof(afterInstance) ~= "table" then
			addDiagnosticIssue(issues, "SnapshotRootMismatch", {
				Category = "missing_key",
				Root = rootName,
				InstanceId = tostring(instanceId),
			}, true)
			continue
		end
		compareSnapshotScalar(issues, rootName, tostring(instanceId) .. ".StorageName", beforeInstance.StorageName or beforeInstance.LegacyStorageName, afterInstance.StorageName or afterInstance.LegacyStorageName, "identity_mismatch")
		compareSnapshotScalar(issues, rootName, tostring(instanceId) .. ".AssignedStand", beforeInstance.AssignedStand, afterInstance.AssignedStand, "stand_mismatch")
		compareSnapshotNumber(issues, rootName, tostring(instanceId) .. ".Level", beforeInstance.Level, afterInstance.Level, "level_mismatch")
		compareSnapshotNumber(issues, rootName, tostring(instanceId) .. ".CurrentXP", beforeInstance.CurrentXP, afterInstance.CurrentXP, "xp_mismatch")
	end
end

local function compareIncomeSnapshot(issues, rootName, beforeIncome, afterIncome)
	beforeIncome = if typeof(beforeIncome) == "table" then beforeIncome else {}
	afterIncome = if typeof(afterIncome) == "table" then afterIncome else {}
	compareSnapshotNumber(issues, rootName, "RowCount", countPairs(beforeIncome), countPairs(afterIncome), "income_mismatch")
	for standName, beforeRow in pairs(beforeIncome) do
		local afterRow = afterIncome[standName]
		if typeof(beforeRow) ~= "table" or typeof(afterRow) ~= "table" then
			addDiagnosticIssue(issues, "SnapshotRootMismatch", {
				Category = "income_mismatch",
				Root = rootName,
				StandName = tostring(standName),
			}, true)
			continue
		end
		compareSnapshotScalar(issues, rootName, tostring(standName) .. ".Identity", beforeRow.BrainrotName or beforeRow.LegacyStorageName or beforeRow.CrewMemberName, afterRow.BrainrotName or afterRow.LegacyStorageName or afterRow.CrewMemberName, "identity_mismatch")
		compareSnapshotScalar(issues, rootName, tostring(standName) .. ".InstanceId", beforeRow.BrainrotInstanceId or beforeRow.CrewMemberInstanceId, afterRow.BrainrotInstanceId or afterRow.CrewMemberInstanceId, "instance_mismatch")
	end
end

local function compareIndexSnapshot(issues, rootName, beforeIndex, afterIndex)
	beforeIndex = if typeof(beforeIndex) == "table" then beforeIndex else {}
	afterIndex = if typeof(afterIndex) == "table" then afterIndex else {}
	compareSnapshotNumber(issues, rootName, "DiscoveredCount", countDiscoveredIndex(beforeIndex), countDiscoveredIndex(afterIndex), "missing_key")
	for key, discovered in pairs(beforeIndex) do
		if discovered == true and afterIndex[key] ~= true then
			addDiagnosticIssue(issues, "SnapshotRootMismatch", {
				Category = "missing_key",
				Root = rootName,
				Key = tostring(key),
			}, true)
		end
	end
end

local function compareFlatNumberMapSnapshot(issues, rootName, beforeMap, afterMap, category)
	beforeMap = if typeof(beforeMap) == "table" then beforeMap else {}
	afterMap = if typeof(afterMap) == "table" then afterMap else {}
	compareSnapshotNumber(issues, rootName, "KeyCount", countPairs(beforeMap), countPairs(afterMap), category)
	for key, beforeValue in pairs(beforeMap) do
		compareSnapshotNumber(issues, rootName, tostring(key), beforeValue, afterMap[key], category)
	end
end

compareSnapshotToCurrent = function(snapshot, currentSnapshot)
	local issues = {}
	if typeof(snapshot) ~= "table" then
		addDiagnosticIssue(issues, "SnapshotMissing", {
			Reason = "snapshot_missing",
		}, true)
		return issues
	end

	compareInventorySnapshot(issues, "Canonical.CrewMemberInventory", snapshot.Canonical and snapshot.Canonical.CrewMemberInventory, currentSnapshot.Canonical and currentSnapshot.Canonical.CrewMemberInventory)
	compareSnapshotNumber(issues, "Canonical.CrewMemberQuickSlots", "UnlockedSlots", snapshot.Canonical and snapshot.Canonical.CrewMemberQuickSlots and snapshot.Canonical.CrewMemberQuickSlots.UnlockedSlots, currentSnapshot.Canonical and currentSnapshot.Canonical.CrewMemberQuickSlots and currentSnapshot.Canonical.CrewMemberQuickSlots.UnlockedSlots, "instance_mismatch")
	compareSnapshotNumber(issues, "Canonical.CrewMemberQuickSlots", "MaxSlots", snapshot.Canonical and snapshot.Canonical.CrewMemberQuickSlots and snapshot.Canonical.CrewMemberQuickSlots.MaxSlots, currentSnapshot.Canonical and currentSnapshot.Canonical.CrewMemberQuickSlots and currentSnapshot.Canonical.CrewMemberQuickSlots.MaxSlots, "instance_mismatch")
	compareIncomeSnapshot(issues, "Canonical.CrewMemberIncome", snapshot.Canonical and snapshot.Canonical.CrewMemberIncome, currentSnapshot.Canonical and currentSnapshot.Canonical.CrewMemberIncome)
	compareIndexSnapshot(issues, "Canonical.IndexCollection.CrewMembers", snapshot.Canonical and snapshot.Canonical.IndexCollection and snapshot.Canonical.IndexCollection.CrewMembers, currentSnapshot.Canonical and currentSnapshot.Canonical.IndexCollection and currentSnapshot.Canonical.IndexCollection.CrewMembers)

	compareInventorySnapshot(issues, "Legacy.BrainrotInventory", snapshot.Legacy and snapshot.Legacy.BrainrotInventory, currentSnapshot.Legacy and currentSnapshot.Legacy.BrainrotInventory)
	compareSnapshotNumber(issues, "Legacy.BrainrotQuickSlots", "UnlockedSlots", snapshot.Legacy and snapshot.Legacy.BrainrotQuickSlots and snapshot.Legacy.BrainrotQuickSlots.UnlockedSlots, currentSnapshot.Legacy and currentSnapshot.Legacy.BrainrotQuickSlots and currentSnapshot.Legacy.BrainrotQuickSlots.UnlockedSlots, "instance_mismatch")
	compareSnapshotNumber(issues, "Legacy.BrainrotQuickSlots", "MaxSlots", snapshot.Legacy and snapshot.Legacy.BrainrotQuickSlots and snapshot.Legacy.BrainrotQuickSlots.MaxSlots, currentSnapshot.Legacy and currentSnapshot.Legacy.BrainrotQuickSlots and currentSnapshot.Legacy.BrainrotQuickSlots.MaxSlots, "instance_mismatch")
	compareSnapshotNumber(issues, "Legacy.BrainrotStorage", "UnlockedSlots", snapshot.Legacy and snapshot.Legacy.BrainrotStorage and snapshot.Legacy.BrainrotStorage.UnlockedSlots, currentSnapshot.Legacy and currentSnapshot.Legacy.BrainrotStorage and currentSnapshot.Legacy.BrainrotStorage.UnlockedSlots, "instance_mismatch")
	compareSnapshotNumber(issues, "Legacy.BrainrotStorage", "MaxSlots", snapshot.Legacy and snapshot.Legacy.BrainrotStorage and snapshot.Legacy.BrainrotStorage.MaxSlots, currentSnapshot.Legacy and currentSnapshot.Legacy.BrainrotStorage and currentSnapshot.Legacy.BrainrotStorage.MaxSlots, "instance_mismatch")
	compareIncomeSnapshot(issues, "Legacy.IncomeBrainrots", snapshot.Legacy and snapshot.Legacy.IncomeBrainrots, currentSnapshot.Legacy and currentSnapshot.Legacy.IncomeBrainrots)
	compareIndexSnapshot(issues, "Legacy.IndexCollection.Brainrots", snapshot.Legacy and snapshot.Legacy.IndexCollection and snapshot.Legacy.IndexCollection.Brainrots, currentSnapshot.Legacy and currentSnapshot.Legacy.IndexCollection and currentSnapshot.Legacy.IndexCollection.Brainrots)
	compareFlatNumberMapSnapshot(issues, "Legacy.StandsLevels", snapshot.Legacy and snapshot.Legacy.StandsLevels, currentSnapshot.Legacy and currentSnapshot.Legacy.StandsLevels, "level_mismatch")
	compareFlatNumberMapSnapshot(issues, "Legacy.FoodInventory", snapshot.Legacy and snapshot.Legacy.FoodInventory, currentSnapshot.Legacy and currentSnapshot.Legacy.FoodInventory, "missing_key")
	sortIssueList(issues)
	return issues
end

function CrewMigrationPlanner.BuildMigrationSaveLoadReport(source, snapshot, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(snapshot) ~= "table" then
		local issues = {}
		addDiagnosticIssue(issues, "SnapshotMissing", {
			Reason = "snapshot_missing",
		}, true)
		local mismatchSummary = buildMismatchSummary(issues)
		return {
			Issues = issues,
			MismatchCountsByCategory = mismatchSummary.CategoryCounts,
			BlockingCount = mismatchSummary.BlockingCount,
			ReviewCount = mismatchSummary.ReviewCount,
			UnclassifiedCount = mismatchSummary.UnclassifiedCount,
			Summary = "saveload status=no_snapshot blocking=1 categories=missing_key=1",
			Passed = false,
			NoGoReasons = { "snapshot_missing" },
		}
	end

	local currentSnapshot = CrewMigrationPlanner.BuildMigrationSnapshot(source, options)
	local compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local prePostIssues = compareSnapshotToCurrent(snapshot, currentSnapshot)
	local issues = {}
	addCategorizedIssues(issues, compareReport.Issues)
	addCategorizedIssues(issues, prePostIssues)
	sortIssueList(issues)

	local mismatchSummary = buildMismatchSummary(issues)
	local noGoReasons = {}
	if mismatchSummary.UnclassifiedCount > 0 then
		noGoReasons[#noGoReasons + 1] = "unclassified_mismatch"
	end
	if currentSnapshot.Metadata.ValidationSummary.IsStale == true then
		noGoReasons[#noGoReasons + 1] = "validation_stale"
	end
	if currentSnapshot.Metadata.ValidationSummary.IsClean ~= true then
		noGoReasons[#noGoReasons + 1] = "validation_not_clean"
	end
	if mismatchSummary.BlockingCount > 0 then
		noGoReasons[#noGoReasons + 1] = "blocking_mismatch"
	end

	local report = {
		PreSnapshot = snapshot,
		PostSnapshot = currentSnapshot,
		Compare = compareReport,
		PrePostIssues = prePostIssues,
		Issues = issues,
		MismatchCountsByCategory = mismatchSummary.CategoryCounts,
		BlockingCount = mismatchSummary.BlockingCount,
		ReviewCount = mismatchSummary.ReviewCount,
		UnclassifiedCount = mismatchSummary.UnclassifiedCount,
		NoGoReasons = noGoReasons,
	}
	report.Passed = #noGoReasons == 0
	report.Summary = string.format(
		"saveload passed=%s prePostIssues=%d compareIssues=%d blocking=%d review=%d unclassified=%d validationClean=%s categories=%s noGo=%s",
		tostring(report.Passed),
		#prePostIssues,
		#compareReport.Issues,
		report.BlockingCount,
		report.ReviewCount,
		report.UnclassifiedCount,
		tostring(currentSnapshot.Metadata.ValidationSummary.IsClean),
		compactCategoryCounts(report.MismatchCountsByCategory),
		if #noGoReasons > 0 then table.concat(noGoReasons, ",") else "none"
	)
	return report
end

local function getDiagnosticSnapshotKey(source)
	if typeof(source) == "Instance" and source:IsA("Player") then
		return tostring(source.UserId)
	end
	if typeof(source) == "table" then
		return source
	end
	return "unknown"
end

function CrewMigrationPlanner.StoreDiagnosticSnapshot(source, snapshot)
	local key = getDiagnosticSnapshotKey(source)
	diagnosticSnapshotsByUserId[key] = snapshot
	return snapshot
end

function CrewMigrationPlanner.GetDiagnosticSnapshot(source)
	return diagnosticSnapshotsByUserId[getDiagnosticSnapshotKey(source)]
end

function CrewMigrationPlanner.ClearDiagnosticSnapshot(source)
	local key = getDiagnosticSnapshotKey(source)
	local previous = diagnosticSnapshotsByUserId[key]
	diagnosticSnapshotsByUserId[key] = nil
	return previous ~= nil
end

local function collectLegacyReviewLocation(legacyData, storageName)
	local target = tostring(storageName or "")
	local quantity = 0
	local instanceIds = {}
	local assignedInstanceIds = {}
	local unassignedInstanceIds = {}
	local standNames = {}
	local standSeen = {}

	local inventoryEntry = typeof(legacyData.Inventory) == "table" and legacyData.Inventory[target] or nil
	if typeof(inventoryEntry) == "table" then
		quantity = math.max(0, math.floor(tonumber(inventoryEntry.Quantity) or 0))
	end

	local byId = typeof(legacyData.BrainrotInventory) == "table" and legacyData.BrainrotInventory.ById or nil
	if typeof(byId) == "table" then
		for instanceId, instanceData in pairs(byId) do
			if typeof(instanceData) == "table" then
				local instanceStorageName = tostring(instanceData.StorageName or instanceData.BrainrotName or "")
				if instanceStorageName == target then
					local normalizedInstanceId = tostring(instanceId)
					instanceIds[#instanceIds + 1] = normalizedInstanceId
					local assignedStand = tostring(instanceData.AssignedStand or "")
					if assignedStand ~= "" then
						assignedInstanceIds[#assignedInstanceIds + 1] = normalizedInstanceId
						if standSeen[assignedStand] ~= true then
							standSeen[assignedStand] = true
							standNames[#standNames + 1] = assignedStand
						end
					else
						unassignedInstanceIds[#unassignedInstanceIds + 1] = normalizedInstanceId
					end
				end
			end
		end
	end

	local incomeRows = typeof(legacyData.IncomeBrainrots) == "table" and legacyData.IncomeBrainrots or nil
	if typeof(incomeRows) == "table" then
		for standName, standData in pairs(incomeRows) do
			if typeof(standData) == "table" and tostring(standData.BrainrotName or "") == target then
				local normalizedStandName = tostring(standName)
				if standSeen[normalizedStandName] ~= true then
					standSeen[normalizedStandName] = true
					standNames[#standNames + 1] = normalizedStandName
				end
			end
		end
	end

	table.sort(instanceIds)
	table.sort(assignedInstanceIds)
	table.sort(unassignedInstanceIds)
	table.sort(standNames)

	local indexDiscovered = typeof(legacyData.IndexBrainrots) == "table" and legacyData.IndexBrainrots[target] == true
	local location = "metadata_only"
	if #standNames > 0 then
		location = "live_assigned"
	elseif #instanceIds > 0 or quantity > 0 then
		location = "inventory_only"
	elseif indexDiscovered then
		location = "index_only"
	end

	return {
		Location = location,
		InventoryQuantity = quantity,
		InstanceCount = #instanceIds,
		AssignedInstanceCount = #assignedInstanceIds,
		UnassignedInstanceCount = #unassignedInstanceIds,
		InstanceIds = instanceIds,
		AssignedInstanceIds = assignedInstanceIds,
		UnassignedInstanceIds = unassignedInstanceIds,
		StandNames = standNames,
		IndexDiscovered = indexDiscovered,
	}
end

local function buildCompatibilityReviewRow(entry, kind, legacyData)
	local row = deepCopy(entry)
	row.Kind = tostring(kind or "")
	row.StorageName = tostring(row.StorageName or row.LegacyId or "")
	local classification = {
		IsCompatibilityOnly = row.Kind == "compatibility_only",
		IsBrookFallback = row.Kind == "brook_fallback",
	}
	applyReviewDecision(row, row.StorageName, classification)

	local location = collectLegacyReviewLocation(legacyData, row.StorageName)
	for key, value in pairs(location) do
		row[key] = value
	end
	return row
end

local function appendCompatibilityReviewRows(target, entries, kind, legacyData)
	for _, entry in ipairs(entries or {}) do
		target[#target + 1] = buildCompatibilityReviewRow(entry, kind, legacyData)
	end
end

local function countCompatibilityReviewRows(rows)
	local counts = {
		CompatibilityOnly = 0,
		BrookFallback = 0,
		AllowedCompatibility = 0,
		AllowedBrook = 0,
		UndecidedCompatibility = 0,
		UndecidedBrook = 0,
		LiveAssigned = 0,
		InventoryOnly = 0,
		IndexOnly = 0,
		MetadataOnly = 0,
	}

	for _, row in ipairs(rows or {}) do
		if row.Kind == "compatibility_only" then
			counts.CompatibilityOnly += 1
			if row.ReviewAllowed == true then
				counts.AllowedCompatibility += 1
			else
				counts.UndecidedCompatibility += 1
			end
		elseif row.Kind == "brook_fallback" then
			counts.BrookFallback += 1
			if row.ReviewAllowed == true then
				counts.AllowedBrook += 1
			else
				counts.UndecidedBrook += 1
			end
		end

		if row.Location == "live_assigned" then
			counts.LiveAssigned += 1
		elseif row.Location == "inventory_only" then
			counts.InventoryOnly += 1
		elseif row.Location == "index_only" then
			counts.IndexOnly += 1
		elseif row.Location == "metadata_only" then
			counts.MetadataOnly += 1
		end
	end

	return counts
end

function CrewMigrationPlanner.BuildCompatibilityReviewReport(source)
	local legacyData = readLegacyData(source)
	local projection = CrewMigrationPlanner.BuildCrewMemberProjection(source)
	local metadata = projection.Metadata or {}
	local rows = {}

	appendCompatibilityReviewRows(rows, metadata.CompatibilityOnlyLegacyIds, "compatibility_only", legacyData)
	appendCompatibilityReviewRows(rows, metadata.BrookFallbackEntries, "brook_fallback", legacyData)
	table.sort(rows, function(left, right)
		local leftKey = string.format("%s:%s", tostring(left.Kind), tostring(left.StorageName))
		local rightKey = string.format("%s:%s", tostring(right.Kind), tostring(right.StorageName))
		return leftKey < rightKey
	end)

	local counts = countCompatibilityReviewRows(rows)
	local report = {
		Rows = rows,
		Counts = counts,
		Metadata = metadata,
	}
	report.Summary = string.format(
		"compatibilityReview compatibilityOnly=%d allowedCompatibility=%d undecidedCompatibility=%d brookFallback=%d allowedBrook=%d undecidedBrook=%d liveAssigned=%d inventoryOnly=%d indexOnly=%d metadataOnly=%d",
		counts.CompatibilityOnly,
		counts.AllowedCompatibility,
		counts.UndecidedCompatibility,
		counts.BrookFallback,
		counts.AllowedBrook,
		counts.UndecidedBrook,
		counts.LiveAssigned,
		counts.InventoryOnly,
		counts.IndexOnly,
		counts.MetadataOnly
	)
	return report
end

function CrewMigrationPlanner.PrintCompatibilityReviewReport(report)
	report = if typeof(report) == "table" then report else { Rows = {}, Summary = "compatibilityReview unavailable" }
	print("[CrewMigrationPlanner] migration " .. tostring(report.Summary))
	for index, row in ipairs(report.Rows or {}) do
		if index > 25 then
			print(string.format("[CrewMigrationPlanner] compatibilityReviewRow ... %d more", #(report.Rows or {}) - 25))
			break
		end
		print(string.format(
			"[CrewMigrationPlanner] compatibilityReviewRow kind=%s storage=%s crew=%s disposition=%s location=%s qty=%d instances=%d assigned=%d stands=%s index=%s action=%s reason=%s",
			tostring(row.Kind or ""),
			tostring(row.StorageName or ""),
			tostring(row.CrewMemberId or row.ReviewCrewMemberId or ""),
			tostring(row.ReviewDisposition or ""),
			tostring(row.Location or ""),
			tonumber(row.InventoryQuantity) or 0,
			tonumber(row.InstanceCount) or 0,
			tonumber(row.AssignedInstanceCount) or 0,
			if typeof(row.StandNames) == "table" and #row.StandNames > 0 then table.concat(row.StandNames, ",") else "none",
			tostring(row.IndexDiscovered == true),
			tostring(row.RetirementAction or ""),
			tostring(row.ReviewReason or "")
		))
	end
	return report
end

function CrewMigrationPlanner.PrintMigrationSnapshotReport(snapshot)
	print("[CrewMigrationPlanner] migration " .. tostring(snapshot and snapshot.Summary or "snapshot unavailable"))
	return snapshot
end

local function printMigrationIssueSamples(label, issues)
	print(string.format("[CrewMigrationPlanner] %sIssues=%d", label, #(issues or {})))
	for index, issue in ipairs(issues or {}) do
		if index > 12 then
			break
		end
		print(string.format(
			"[CrewMigrationPlanner] %sIssue kind=%s category=%s blocking=%s storage=%s stand=%s instance=%s field=%s disposition=%s action=%s",
			label,
			tostring(issue.Kind),
			tostring(issue.Category),
			tostring(issue.Blocking),
			tostring(issue.StorageName or issue.LegacyStorageName or issue.CrewMemberId or ""),
			tostring(issue.StandName or ""),
			tostring(issue.InstanceId or ""),
			tostring(issue.Field or ""),
			tostring(issue.ReviewDisposition or ""),
			tostring(issue.RetirementAction or "")
		))
	end
end

function CrewMigrationPlanner.PrintMigrationDryRunReport(report)
	print("[CrewMigrationPlanner] migration " .. tostring(report and report.Summary or "dryrun unavailable"))
	printMigrationIssueSamples("dryrun", report and report.Issues or {})
	return report
end

function CrewMigrationPlanner.PrintMigrationCompareReport(report)
	print("[CrewMigrationPlanner] migration " .. tostring(report and report.Summary or "compare unavailable"))
	printMigrationIssueSamples("compare", report and report.Issues or {})
	return report
end

function CrewMigrationPlanner.PrintMigrationSaveLoadReport(report)
	print("[CrewMigrationPlanner] migration " .. tostring(report and report.Summary or "saveload unavailable"))
	printMigrationIssueSamples("saveload", report and report.Issues or {})
	return report
end

CrewMigrationPlanner.AuditDataStoreName = AUDIT_DATA_STORE_NAME

local auditHashFields = {
	"LegacyInstances",
	"ProjectedInstances",
	"LiveCanonicalInstances",
	"LegacyOrder",
	"ProjectedOrder",
	"LiveCanonicalOrder",
	"LegacyQuickSlotKeys",
	"CanonicalQuickSlotKeys",
	"StandAssignments",
	"LegacyIncomeRows",
	"ProjectedIncomeRows",
	"LiveCanonicalIncomeRows",
	"LegacyIndexEntries",
	"ProjectedIndexEntries",
	"LiveCanonicalIndexEntries",
	"LevelMismatchCount",
	"XPMismatchCount",
	"DuplicateAssignmentCount",
	"UnknownIdCount",
	"BlockingCount",
	"UnclassifiedCount",
	"CompatibilityReviewCount",
	"BrookReviewCount",
}

local auditCompareFields = {
	{ Key = "LegacyInstances", Label = "legacy_instances" },
	{ Key = "ProjectedInstances", Label = "projected_instances" },
	{ Key = "LiveCanonicalInstances", Label = "live_canonical_instances" },
	{ Key = "LegacyOrder", Label = "legacy_order" },
	{ Key = "ProjectedOrder", Label = "projected_order" },
	{ Key = "LiveCanonicalOrder", Label = "live_canonical_order" },
	{ Key = "LegacyQuickSlotKeys", Label = "legacy_quick_slot_keys" },
	{ Key = "CanonicalQuickSlotKeys", Label = "canonical_quick_slot_keys" },
	{ Key = "StandAssignments", Label = "stand_assignments" },
	{ Key = "LegacyIncomeRows", Label = "legacy_income_rows" },
	{ Key = "ProjectedIncomeRows", Label = "projected_income_rows" },
	{ Key = "LiveCanonicalIncomeRows", Label = "live_canonical_income_rows" },
	{ Key = "LegacyIndexEntries", Label = "legacy_index_entries" },
	{ Key = "ProjectedIndexEntries", Label = "projected_index_entries" },
	{ Key = "LiveCanonicalIndexEntries", Label = "live_canonical_index_entries" },
	{ Key = "LevelMismatchCount", Label = "level_mismatch_count" },
	{ Key = "XPMismatchCount", Label = "xp_mismatch_count" },
	{ Key = "DuplicateAssignmentCount", Label = "duplicate_assignment_count" },
	{ Key = "UnknownIdCount", Label = "unknown_id_count" },
	{ Key = "BlockingCount", Label = "blocking_count" },
	{ Key = "UnclassifiedCount", Label = "unclassified_count" },
	{ Key = "CompatibilityReviewCount", Label = "compatibility_review_count" },
	{ Key = "BrookReviewCount", Label = "brook_review_count" },
	{ Key = "ReportHash", Label = "report_hash" },
}

local function getAuditUserId(source, options)
	options = if typeof(options) == "table" then options else {}
	if tonumber(options.UserId) ~= nil then
		return math.floor(tonumber(options.UserId))
	end
	if typeof(source) == "Instance" and source:IsA("Player") then
		return source.UserId
	end
	return nil
end

local function getAuditKey(userId)
	local safeUserId = tonumber(userId)
	if safeUserId == nil then
		return nil
	end
	return tostring(math.floor(safeUserId)) .. ":latest"
end

local function getAuditCategoryCount(report, category)
	local counts = if typeof(report) == "table" then report.MismatchCountsByCategory else nil
	return if typeof(counts) == "table" then math.max(0, math.floor(tonumber(counts[tostring(category or "")]) or 0)) else 0
end

local function makeAuditHash(compact)
	local sourceParts = {}
	for _, key in ipairs(auditHashFields) do
		sourceParts[#sourceParts + 1] = tostring(key) .. "=" .. tostring(compact[key] or 0)
	end

	local source = table.concat(sourceParts, "|")
	local hash = 0
	for index = 1, #source do
		hash = (hash * 31 + string.byte(source, index)) % 2147483647
	end
	return string.format("%08x", hash), source
end

local function compactMigrationAuditReport(source, commandType, compareReport, snapshot, options)
	options = if typeof(options) == "table" then options else {}
	compareReport = if typeof(compareReport) == "table" then compareReport else CrewMigrationPlanner.BuildMigrationCompareReport(source, options)
	snapshot = if typeof(snapshot) == "table" then snapshot else CrewMigrationPlanner.BuildMigrationSnapshot(source, options)

	local counts = compareReport.Counts or {}
	local metadata = compareReport.Metadata or getSourceMetadata(source, options)
	local validation = metadata.ValidationSummary or {}
	local compact = {
		UserId = metadata.UserId,
		PlayerName = metadata.PlayerName,
		PlaceId = metadata.PlaceId,
		GameId = metadata.GameId,
		JobId = metadata.JobId,
		TimestampUnix = os.time(),
		TimestampClock = os.clock(),
		ToolVersion = MIGRATION_TOOL_VERSION,
		SchemaVersion = 1,
		CommandType = tostring(commandType or "audit"),
		ValidationSummary = deepCopy(validation),
		Flags = deepCopy(options.Flags or {}),
		LegacyInstances = counts.LegacyInstances or 0,
		ProjectedInstances = counts.ProjectedInstances or 0,
		LiveCanonicalInstances = counts.LiveCanonicalInstances or 0,
		LegacyOrder = counts.LegacyOrder or 0,
		ProjectedOrder = counts.ProjectedOrder or 0,
		LiveCanonicalOrder = counts.LiveCanonicalOrder or 0,
		LegacyQuickSlotKeys = counts.LegacyQuickSlotKeys or 0,
		CanonicalQuickSlotKeys = counts.CanonicalQuickSlotKeys or 0,
		StandAssignments = counts.LegacyStandRows or 0,
		LegacyIncomeRows = counts.LegacyStandRows or 0,
		ProjectedIncomeRows = counts.ProjectedIncomeRows or 0,
		LiveCanonicalIncomeRows = counts.LiveCanonicalIncomeRows or 0,
		LegacyIndexEntries = counts.LegacyIndexEntries or 0,
		ProjectedIndexEntries = counts.ProjectedIndexEntries or 0,
		LiveCanonicalIndexEntries = counts.LiveCanonicalIndexEntries or 0,
		LevelMismatchCount = getAuditCategoryCount(compareReport, "level_mismatch"),
		XPMismatchCount = getAuditCategoryCount(compareReport, "xp_mismatch"),
		DuplicateAssignmentCount = getAuditCategoryCount(compareReport, "duplicate_assignment"),
		UnknownIdCount = getAuditCategoryCount(compareReport, "unknown_id"),
		BlockingCount = compareReport.BlockingCount or 0,
		ReviewCount = compareReport.ReviewCount or 0,
		UnclassifiedCount = compareReport.UnclassifiedCount or 0,
		CompatibilityReviewCount = getAuditCategoryCount(compareReport, "compatibility_only"),
		BrookReviewCount = getAuditCategoryCount(compareReport, "brook_fallback"),
		CanProceed = compareReport.CanProceed == true,
		CompareSummary = tostring(compareReport.Summary or ""),
		SnapshotSummary = tostring(snapshot.Summary or ""),
	}
	compact.ReportHash, compact.ReportHashSource = makeAuditHash(compact)
	compact.Summary = string.format(
		"%s legacyInstances=%d projectedInstances=%d liveCanonicalInstances=%d order=%d/%d/%d quickSlotKeys=%d/%d standAssignments=%d incomeRows=%d/%d/%d index=%d/%d/%d levelMismatch=%d xpMismatch=%d duplicates=%d unknown=%d blocking=%d unclassified=%d compatibilityReview=%d brookReview=%d canProceed=%s hash=%s",
		tostring(compact.CommandType),
		compact.LegacyInstances,
		compact.ProjectedInstances,
		compact.LiveCanonicalInstances,
		compact.LegacyOrder,
		compact.ProjectedOrder,
		compact.LiveCanonicalOrder,
		compact.LegacyQuickSlotKeys,
		compact.CanonicalQuickSlotKeys,
		compact.StandAssignments,
		compact.LegacyIncomeRows,
		compact.ProjectedIncomeRows,
		compact.LiveCanonicalIncomeRows,
		compact.LegacyIndexEntries,
		compact.ProjectedIndexEntries,
		compact.LiveCanonicalIndexEntries,
		compact.LevelMismatchCount,
		compact.XPMismatchCount,
		compact.DuplicateAssignmentCount,
		compact.UnknownIdCount,
		compact.BlockingCount,
		compact.UnclassifiedCount,
		compact.CompatibilityReviewCount,
		compact.BrookReviewCount,
		tostring(compact.CanProceed),
		compact.ReportHash
	)

	return compact
end

local function getAuditNoGoReasons(compact)
	local reasons = {}
	local validation = compact and compact.ValidationSummary or {}
	if typeof(compact) ~= "table" then
		return { "audit_report_missing" }
	end
	if compact.CanProceed ~= true then
		reasons[#reasons + 1] = "compare_not_clean"
	end
	if (compact.BlockingCount or 0) > 0 then
		reasons[#reasons + 1] = "blocking_mismatch"
	end
	if (compact.UnclassifiedCount or 0) > 0 then
		reasons[#reasons + 1] = "unclassified_mismatch"
	end
	if (compact.DuplicateAssignmentCount or 0) > 0 then
		reasons[#reasons + 1] = "duplicate_assignment"
	end
	if (compact.UnknownIdCount or 0) > 0 then
		reasons[#reasons + 1] = "unknown_id"
	end
	if (compact.LevelMismatchCount or 0) > 0 then
		reasons[#reasons + 1] = "level_mismatch"
	end
	if (compact.XPMismatchCount or 0) > 0 then
		reasons[#reasons + 1] = "xp_mismatch"
	end
	if validation.IsStale == true then
		reasons[#reasons + 1] = "validation_stale"
	end
	if validation.IsClean ~= true then
		reasons[#reasons + 1] = "validation_not_clean"
	end
	local flags = compact.Flags or {}
	if flags.CrewMemberCanaryProfileMigrationDryRunEnabled ~= true then
		reasons[#reasons + 1] = "profile_migration_dryrun_disabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		reasons[#reasons + 1] = "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "write_authority_enabled"
	end
	if flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "quick_slots_write_authority_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		reasons[#reasons + 1] = "canonical_read_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		reasons[#reasons + 1] = "gameplay_reads_enabled"
	end
	if flags.CrewMemberMigrationKillSwitchEnabled ~= true then
		reasons[#reasons + 1] = "migration_kill_switch_not_enabled"
	end
	return reasons
end

function CrewMigrationPlanner.BuildMigrationAuditReport(source, commandType, options)
	options = if typeof(options) == "table" then options else {}
	local snapshot = CrewMigrationPlanner.BuildMigrationSnapshot(source, options)
	local compareReport = options.CompareReport
	if typeof(compareReport) ~= "table" then
		compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
			ValidationStatus = options.ValidationStatus,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
		})
	end
	local compact = compactMigrationAuditReport(source, commandType, compareReport, snapshot, options)
	local noGoReasons = getAuditNoGoReasons(compact)
	return {
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = getAuditKey(compact.UserId),
		Report = compact,
		Snapshot = snapshot,
		Compare = compareReport,
		CanSave = #noGoReasons == 0,
		NoGoReasons = noGoReasons,
		Summary = compact.Summary,
	}
end

function CrewMigrationPlanner.CompareMigrationAuditReports(beforeReport, afterReport)
	local mismatches = {}
	beforeReport = if typeof(beforeReport) == "table" then beforeReport else nil
	afterReport = if typeof(afterReport) == "table" then afterReport else nil
	if beforeReport == nil then
		mismatches[#mismatches + 1] = {
			Field = "before_report",
			Before = "missing",
			After = "present",
		}
	end
	if afterReport == nil then
		mismatches[#mismatches + 1] = {
			Field = "after_report",
			Before = "present",
			After = "missing",
		}
	end

	if beforeReport ~= nil and afterReport ~= nil then
		for _, field in ipairs(auditCompareFields) do
			local beforeValue = beforeReport[field.Key]
			local afterValue = afterReport[field.Key]
			if tostring(beforeValue or "") ~= tostring(afterValue or "") then
				mismatches[#mismatches + 1] = {
					Field = field.Label,
					Before = beforeValue,
					After = afterValue,
				}
			end
		end
	end

	local noGoReasons = {}
	for _, reason in ipairs(getAuditNoGoReasons(afterReport)) do
		noGoReasons[#noGoReasons + 1] = reason
	end
	if #mismatches > 0 then
		noGoReasons[#noGoReasons + 1] = "before_after_mismatch"
	end

	return {
		Passed = #noGoReasons == 0,
		Mismatches = mismatches,
		NoGoReasons = noGoReasons,
		Summary = string.format(
			"auditCompare passed=%s mismatches=%d noGo=%s beforeHash=%s afterHash=%s",
			tostring(#noGoReasons == 0),
			#mismatches,
			if #noGoReasons > 0 then table.concat(noGoReasons, ",") else "none",
			tostring(beforeReport and beforeReport.ReportHash or ""),
			tostring(afterReport and afterReport.ReportHash or "")
		),
	}
end

function CrewMigrationPlanner.SaveMigrationAuditBefore(source, auditReport, options)
	options = if typeof(options) == "table" then options else {}
	local report = if typeof(auditReport) == "table" then auditReport.Report or auditReport else nil
	local userId = getAuditUserId(source, {
		UserId = report and report.UserId,
	})
	local key = getAuditKey(userId)
	if key == nil then
		return {
			Ok = false,
			Reason = "invalid_user_id",
			StoreName = AUDIT_DATA_STORE_NAME,
		}
	end
	if typeof(report) ~= "table" then
		return {
			Ok = false,
			Reason = "audit_report_missing",
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}
	end

	local record = {
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
		UpdatedAt = os.time(),
		Before = report,
		LastAfter = nil,
		LastResult = nil,
	}
	local ok, err = pcall(function()
		getAuditDataStore():SetAsync(key, record)
	end)
	return {
		Ok = ok == true,
		Reason = if ok then nil else tostring(err),
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
		Record = if ok then record else nil,
	}
end

function CrewMigrationPlanner.LoadMigrationAudit(source, options)
	options = if typeof(options) == "table" then options else {}
	local userId = getAuditUserId(source, options)
	local key = getAuditKey(userId)
	if key == nil then
		return {
			Ok = false,
			Reason = "invalid_user_id",
			StoreName = AUDIT_DATA_STORE_NAME,
		}
	end

	local record = nil
	local ok, err = pcall(function()
		record = getAuditDataStore():GetAsync(key)
	end)
	return {
		Ok = ok == true,
		Reason = if ok then nil else tostring(err),
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
		Record = record,
		Missing = ok == true and record == nil,
	}
end

function CrewMigrationPlanner.SaveMigrationAuditAfter(source, beforeRecord, afterAuditReport, comparison, options)
	options = if typeof(options) == "table" then options else {}
	local afterReport = if typeof(afterAuditReport) == "table" then afterAuditReport.Report or afterAuditReport else nil
	local userId = getAuditUserId(source, {
		UserId = afterReport and afterReport.UserId,
	})
	local key = getAuditKey(userId)
	if key == nil then
		return {
			Ok = false,
			Reason = "invalid_user_id",
			StoreName = AUDIT_DATA_STORE_NAME,
		}
	end
	if typeof(beforeRecord) ~= "table" or typeof(beforeRecord.Before) ~= "table" then
		return {
			Ok = false,
			Reason = "before_audit_missing",
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}
	end
	if typeof(afterReport) ~= "table" then
		return {
			Ok = false,
			Reason = "after_audit_missing",
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}
	end

	local record = {
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
		UpdatedAt = os.time(),
		Before = beforeRecord.Before,
		LastAfter = afterReport,
		LastResult = comparison,
	}
	local ok, err = pcall(function()
		getAuditDataStore():SetAsync(key, record)
	end)
	return {
		Ok = ok == true,
		Reason = if ok then nil else tostring(err),
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
		Record = if ok then record else nil,
	}
end

function CrewMigrationPlanner.ClearMigrationAudit(source, options)
	options = if typeof(options) == "table" then options else {}
	local userId = getAuditUserId(source, options)
	local key = getAuditKey(userId)
	if key == nil then
		return {
			Ok = false,
			Reason = "invalid_user_id",
			StoreName = AUDIT_DATA_STORE_NAME,
		}
	end

	local ok, err = pcall(function()
		getAuditDataStore():RemoveAsync(key)
	end)
	return {
		Ok = ok == true,
		Reason = if ok then nil else tostring(err),
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
	}
end

function CrewMigrationPlanner.PrintMigrationAuditReport(label, auditReport)
	local report = if typeof(auditReport) == "table" then auditReport.Report or auditReport else nil
	print(string.format(
		"[CrewMigrationPlanner] migrationAudit %s %s auditKey=%s store=%s noGo=%s",
		tostring(label or "audit"),
		tostring(report and report.Summary or "unavailable"),
		tostring(auditReport and auditReport.Key or (report and getAuditKey(report.UserId)) or ""),
		AUDIT_DATA_STORE_NAME,
		if auditReport and typeof(auditReport.NoGoReasons) == "table" and #auditReport.NoGoReasons > 0
			then table.concat(auditReport.NoGoReasons, ",")
			else "none"
	))
	return auditReport
end

function CrewMigrationPlanner.PrintMigrationAuditComparison(comparison)
	print("[CrewMigrationPlanner] migrationAudit " .. tostring(comparison and comparison.Summary or "comparison unavailable"))
	if comparison and typeof(comparison.Mismatches) == "table" then
		for index, mismatch in ipairs(comparison.Mismatches) do
			if index > 12 then
				break
			end
			print(string.format(
				"[CrewMigrationPlanner] migrationAuditMismatch field=%s before=%s after=%s",
				tostring(mismatch.Field),
				tostring(mismatch.Before),
				tostring(mismatch.After)
			))
		end
	end
	return comparison
end

local function stableSerialize(value, depth)
	depth = math.max(0, math.floor(tonumber(depth) or 0))
	local valueType = typeof(value)
	if valueType ~= "table" then
		return valueType .. ":" .. tostring(value)
	end
	if depth > 40 then
		return "table:<max_depth>"
	end

	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local parts = { "table:{" }
	for _, key in ipairs(keys) do
		parts[#parts + 1] = stableSerialize(key, depth + 1)
		parts[#parts + 1] = "="
		parts[#parts + 1] = stableSerialize(value[key], depth + 1)
		parts[#parts + 1] = ";"
	end
	parts[#parts + 1] = "}"
	return table.concat(parts)
end

local function hashStableValue(value)
	local source = stableSerialize(value, 0)
	local hash = 0
	for index = 1, #source do
		hash = (hash * 31 + string.byte(source, index)) % 2147483647
	end
	return string.format("%08x", hash), source
end

local function countDeepKeys(value)
	if typeof(value) ~= "table" then
		return 1
	end

	local count = 0
	for _, child in pairs(value) do
		count += 1
		if typeof(child) == "table" then
			count += countDeepKeys(child)
		end
	end
	return count
end

local function appendDiffSample(samples, sample)
	if #samples >= 16 then
		return
	end
	samples[#samples + 1] = sample
end

local function collectCanonicalDiffStats(liveValue, projectedValue, path, stats)
	local liveType = typeof(liveValue)
	local projectedType = typeof(projectedValue)
	if liveType ~= "table" or projectedType ~= "table" then
		if stableSerialize(liveValue, 0) ~= stableSerialize(projectedValue, 0) then
			stats.KeysUpdated += 1
			appendDiffSample(stats.SampleChanges, {
				Kind = "updated",
				Path = path,
				Live = liveValue,
				Projected = projectedValue,
			})
		end
		return
	end

	local seen = {}
	for key, projectedChild in pairs(projectedValue) do
		local childPath = if path == "" then tostring(key) else path .. "." .. tostring(key)
		seen[key] = true
		local liveChild = liveValue[key]
		if liveChild == nil then
			stats.KeysAdded += countDeepKeys(projectedChild)
			appendDiffSample(stats.SampleChanges, {
				Kind = "added",
				Path = childPath,
			})
		else
			collectCanonicalDiffStats(liveChild, projectedChild, childPath, stats)
		end
	end

	for key, liveChild in pairs(liveValue) do
		if seen[key] ~= true and projectedValue[key] == nil then
			local childPath = if path == "" then tostring(key) else path .. "." .. tostring(key)
			stats.KeysRemoved += countDeepKeys(liveChild)
			appendDiffSample(stats.SampleChanges, {
				Kind = "removed",
				Path = childPath,
			})
		end
	end
end

local function getWritePreviewRootCount(rootName, value)
	if rootName == "CrewMemberInventory" then
		local counts = getInventoryCounts(value)
		return counts.ById, counts.Order
	elseif rootName == "CrewMemberQuickSlots" then
		return countPairs(value), nil
	elseif rootName == "CrewMemberIncome" then
		return countPairs(value), nil
	elseif rootName == "IndexCollection.CrewMembers" then
		return countDiscoveredIndex(value), nil
	end
	return countPairs(value), nil
end

local function buildWritePreviewRootDiff(rootName, path, liveRoot, projectedRoot)
	local stats = {
		KeysAdded = 0,
		KeysRemoved = 0,
		KeysUpdated = 0,
		SampleChanges = {},
	}
	collectCanonicalDiffStats(liveRoot, projectedRoot, "", stats)

	local liveHash = hashStableValue(liveRoot)
	local projectedHash = hashStableValue(projectedRoot)
	local liveCount, liveOrderCount = getWritePreviewRootCount(rootName, liveRoot)
	local projectedCount, projectedOrderCount = getWritePreviewRootCount(rootName, projectedRoot)
	local wouldChange = liveHash ~= projectedHash

	return {
		Root = rootName,
		Path = path,
		WouldChange = wouldChange,
		LiveHash = liveHash,
		ProjectedHash = projectedHash,
		LiveCount = liveCount,
		ProjectedCount = projectedCount,
		LiveOrderCount = liveOrderCount,
		ProjectedOrderCount = projectedOrderCount,
		KeysAdded = stats.KeysAdded,
		KeysRemoved = stats.KeysRemoved,
		KeysUpdated = stats.KeysUpdated,
		SampleChanges = stats.SampleChanges,
	}
end

local function buildProjectedCanonicalRoots(projection)
	local projectedIndexCollection = projection and projection[CrewProfileSchema.Keys.IndexCollection]
	return {
		CrewMemberInventory = deepCopy(projection and projection[CrewProfileSchema.Keys.Inventory]),
		CrewMemberQuickSlots = deepCopy(projection and projection[CrewProfileSchema.Keys.QuickSlots]),
		CrewMemberIncome = deepCopy(projection and projection[CrewProfileSchema.Keys.Income]),
		IndexCollection = {
			CrewMembers = deepCopy(projectedIndexCollection and projectedIndexCollection[CrewProfileSchema.Keys.Index]),
		},
	}
end

local function buildWritePreviewDiff(canonicalData, projectedRoots)
	local rootDiffs = {
		buildWritePreviewRootDiff(
			"CrewMemberInventory",
			CrewStorage.FutureKeys.Inventory,
			canonicalData and canonicalData.CrewMemberInventory,
			projectedRoots.CrewMemberInventory
		),
		buildWritePreviewRootDiff(
			"CrewMemberQuickSlots",
			CrewStorage.FutureKeys.QuickSlots,
			canonicalData and canonicalData.CrewMemberQuickSlots,
			projectedRoots.CrewMemberQuickSlots
		),
		buildWritePreviewRootDiff(
			"CrewMemberIncome",
			CrewStorage.FutureKeys.Income,
			canonicalData and canonicalData.CrewMemberIncome,
			projectedRoots.CrewMemberIncome
		),
		buildWritePreviewRootDiff(
			"IndexCollection.CrewMembers",
			CrewStorage.FutureKeys.IndexCollection .. "." .. CrewStorage.FutureKeys.Index,
			canonicalData and canonicalData.IndexCrewMembers,
			projectedRoots.IndexCollection.CrewMembers
		),
	}

	local rootsChanged = 0
	local keysAdded = 0
	local keysRemoved = 0
	local keysUpdated = 0
	for _, diff in ipairs(rootDiffs) do
		if diff.WouldChange == true then
			rootsChanged += 1
		end
		keysAdded += diff.KeysAdded or 0
		keysRemoved += diff.KeysRemoved or 0
		keysUpdated += diff.KeysUpdated or 0
	end

	return {
		RootDiffs = rootDiffs,
		RootsChanged = rootsChanged,
		KeysAdded = keysAdded,
		KeysRemoved = keysRemoved,
		KeysUpdated = keysUpdated,
		WouldBeNoOp = rootsChanged == 0 and keysAdded == 0 and keysRemoved == 0 and keysUpdated == 0,
		CanonicalAlreadyMatchesProjection = rootsChanged == 0,
	}
end

local function getWritePreviewNoGoReasons(compareReport, flags, projectionHashStable)
	local reasons = {}
	local validation = compareReport and compareReport.Metadata and compareReport.Metadata.ValidationSummary or {}
	if flags.CrewMemberCanaryProfileMigrationDryRunEnabled ~= true then
		reasons[#reasons + 1] = "profile_migration_dryrun_disabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		reasons[#reasons + 1] = "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "write_authority_enabled"
	end
	if flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "quick_slots_write_authority_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		reasons[#reasons + 1] = "canonical_read_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		reasons[#reasons + 1] = "gameplay_reads_enabled"
	end
	if flags.CrewMemberMigrationKillSwitchEnabled ~= true then
		reasons[#reasons + 1] = "migration_kill_switch_not_enabled"
	end
	if compareReport == nil or compareReport.CanProceed ~= true then
		reasons[#reasons + 1] = "compare_not_clean"
	end
	if compareReport and (compareReport.BlockingCount or 0) > 0 then
		reasons[#reasons + 1] = "blocking_mismatch"
	end
	if compareReport and (compareReport.UnclassifiedCount or 0) > 0 then
		reasons[#reasons + 1] = "unclassified_mismatch"
	end
	if validation.IsStale == true then
		reasons[#reasons + 1] = "validation_stale"
	end
	if validation.IsClean ~= true then
		reasons[#reasons + 1] = "validation_not_clean"
	end
	if getAuditCategoryCount(compareReport, "duplicate_assignment") > 0 then
		reasons[#reasons + 1] = "duplicate_assignment"
	end
	if getAuditCategoryCount(compareReport, "unknown_id") > 0 then
		reasons[#reasons + 1] = "unknown_id"
	end
	if getAuditCategoryCount(compareReport, "canonical_shape_invalid") > 0 then
		reasons[#reasons + 1] = "canonical_shape_invalid"
	end
	if projectionHashStable ~= true then
		reasons[#reasons + 1] = "projection_hash_unstable"
	end
	return reasons
end

function CrewMigrationPlanner.BuildMigrationWritePreviewReport(source, options)
	options = if typeof(options) == "table" then options else {}
	local flags = if typeof(options.Flags) == "table" then options.Flags else {}
	local compareReport = options.CompareReport
	if typeof(compareReport) ~= "table" then
		compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
			ValidationStatus = options.ValidationStatus,
			MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
			Snapshot = options.Snapshot,
		})
	end
	local projection = compareReport
		and compareReport.DryRun
		and compareReport.DryRun.Projection
		or CrewMigrationPlanner.BuildCrewMemberProjection(source)
	local projectedRoots = buildProjectedCanonicalRoots(projection)
	local canonicalData = readCanonicalData(source)
	local rollbackSnapshot = CrewMigrationPlanner.BuildMigrationSnapshot(source, options)
	local diff = buildWritePreviewDiff(canonicalData, projectedRoots)
	local projectionHash, projectionHashSource = hashStableValue(projectedRoots)
	local projectionHashConfirm = hashStableValue(deepCopy(projectedRoots))
	local projectionHashStable = projectionHash == projectionHashConfirm
	local snapshotHash = hashStableValue(rollbackSnapshot)
	local noGoReasons = getWritePreviewNoGoReasons(compareReport, flags, projectionHashStable)
	local metadata = compareReport.Metadata or getSourceMetadata(source, options)
	local report = {
		UserId = metadata.UserId,
		PlayerName = metadata.PlayerName,
		PlaceId = metadata.PlaceId,
		GameId = metadata.GameId,
		JobId = metadata.JobId,
		TimestampUnix = os.time(),
		TimestampClock = os.clock(),
		ToolVersion = MIGRATION_TOOL_VERSION,
		SchemaVersion = 1,
		CommandType = "writepreview",
		ValidationSummary = deepCopy(metadata.ValidationSummary or {}),
		Flags = deepCopy(flags),
		ProjectionHash = projectionHash,
		ProjectionHashSource = projectionHashSource,
		ProjectionHashStable = projectionHashStable,
		RollbackSnapshotHash = snapshotHash,
		RootsChanged = diff.RootsChanged,
		KeysAdded = diff.KeysAdded,
		KeysRemoved = diff.KeysRemoved,
		KeysUpdated = diff.KeysUpdated,
		WouldBeNoOp = diff.WouldBeNoOp,
		CanonicalAlreadyMatchesProjection = diff.CanonicalAlreadyMatchesProjection,
		BlockingCount = compareReport.BlockingCount or 0,
		ReviewCount = compareReport.ReviewCount or 0,
		UnclassifiedCount = compareReport.UnclassifiedCount or 0,
		DuplicateAssignmentCount = getAuditCategoryCount(compareReport, "duplicate_assignment"),
		UnknownIdCount = getAuditCategoryCount(compareReport, "unknown_id"),
		CompatibilityReviewCount = getAuditCategoryCount(compareReport, "compatibility_only"),
		BrookReviewCount = getAuditCategoryCount(compareReport, "brook_fallback"),
		CanWriteMigration = false,
	}
	report.CanWritePreview = #noGoReasons == 0
	report.Summary = string.format(
		"writepreview canWritePreview=%s canWriteMigration=false noop=%s rootsChanged=%d keysAdded=%d keysRemoved=%d keysUpdated=%d projectionHash=%s stable=%s blocking=%d unclassified=%d compatibilityReview=%d brookReview=%d noGo=%s",
		tostring(report.CanWritePreview),
		tostring(report.WouldBeNoOp),
		report.RootsChanged,
		report.KeysAdded,
		report.KeysRemoved,
		report.KeysUpdated,
		report.ProjectionHash,
		tostring(report.ProjectionHashStable),
		report.BlockingCount,
		report.UnclassifiedCount,
		report.CompatibilityReviewCount,
		report.BrookReviewCount,
		if #noGoReasons > 0 then table.concat(noGoReasons, ",") else "none"
	)
	return {
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = getAuditKey(report.UserId),
		Report = report,
		Diff = diff,
		Compare = compareReport,
		RollbackSnapshot = rollbackSnapshot,
		ProjectedCanonical = projectedRoots,
		CanWritePreview = report.CanWritePreview,
		CanWriteMigration = false,
		NoGoReasons = noGoReasons,
		Summary = report.Summary,
	}
end

function CrewMigrationPlanner.StoreMigrationWritePreview(source, previewReport)
	local key = getDiagnosticSnapshotKey(source)
	migrationWritePreviewsByUserId[key] = previewReport
	return previewReport
end

function CrewMigrationPlanner.GetMigrationWritePreview(source)
	return migrationWritePreviewsByUserId[getDiagnosticSnapshotKey(source)]
end

function CrewMigrationPlanner.ClearMigrationWritePreview(source)
	local key = getDiagnosticSnapshotKey(source)
	local previous = migrationWritePreviewsByUserId[key]
	migrationWritePreviewsByUserId[key] = nil
	return previous ~= nil
end

function CrewMigrationPlanner.SaveMigrationWritePreview(source, previewReport, options)
	options = if typeof(options) == "table" then options else {}
	local report = if typeof(previewReport) == "table" then previewReport.Report or previewReport else nil
	local userId = getAuditUserId(source, {
		UserId = report and report.UserId,
	})
	local key = getAuditKey(userId)
	if key == nil then
		return {
			Ok = false,
			Reason = "invalid_user_id",
			StoreName = AUDIT_DATA_STORE_NAME,
		}
	end
	if typeof(report) ~= "table" then
		return {
			Ok = false,
			Reason = "writepreview_report_missing",
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}
	end

	local existing = nil
	local okGet, getErr = pcall(function()
		existing = getAuditDataStore():GetAsync(key)
	end)
	if okGet ~= true then
		return {
			Ok = false,
			Reason = tostring(getErr),
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}
	end

	local record = if typeof(existing) == "table" then existing else {}
	record.StoreName = AUDIT_DATA_STORE_NAME
	record.Key = key
	record.UpdatedAt = os.time()
	record.WritePreview = report
	record.WritePreviewDiff = previewReport.Diff
	record.WritePreviewRollbackSnapshot = previewReport.RollbackSnapshot
	record.WritePreviewProjectedCanonical = previewReport.ProjectedCanonical
	record.LatestRollbackKind = "canonical_migration_roots"

	local okSet, setErr = pcall(function()
		getAuditDataStore():SetAsync(key, record)
	end)
	return {
		Ok = okSet == true,
		Reason = if okSet then nil else tostring(setErr),
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
		Record = if okSet then record else nil,
	}
end

function CrewMigrationPlanner.LoadMigrationWritePreview(source, options)
	local loadResult = CrewMigrationPlanner.LoadMigrationAudit(source, options)
	local record = loadResult.Record
	local preview = if typeof(record) == "table" then record.WritePreview else nil
	return {
		Ok = loadResult.Ok,
		Reason = loadResult.Reason,
		StoreName = loadResult.StoreName,
		Key = loadResult.Key,
		Missing = loadResult.Ok == true and typeof(preview) ~= "table",
		Record = record,
		WritePreview = preview,
		WritePreviewDiff = if typeof(record) == "table" then record.WritePreviewDiff else nil,
	}
end

function CrewMigrationPlanner.ClearMigrationWritePreviewAudit(source, options)
	options = if typeof(options) == "table" then options else {}
	local userId = getAuditUserId(source, options)
	local key = getAuditKey(userId)
	if key == nil then
		return {
			Ok = false,
			Reason = "invalid_user_id",
			StoreName = AUDIT_DATA_STORE_NAME,
		}
	end

	local existing = nil
	local okGet, getErr = pcall(function()
		existing = getAuditDataStore():GetAsync(key)
	end)
	if okGet ~= true then
		return {
			Ok = false,
			Reason = tostring(getErr),
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}
	end
	if typeof(existing) ~= "table" then
		return {
			Ok = true,
			Missing = true,
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}
	end

	existing.WritePreview = nil
	existing.WritePreviewDiff = nil
	existing.WritePreviewRollbackSnapshot = nil
	existing.WritePreviewProjectedCanonical = nil
	existing.UpdatedAt = os.time()

	local okSet, setErr = pcall(function()
		getAuditDataStore():SetAsync(key, existing)
	end)
	return {
		Ok = okSet == true,
		Reason = if okSet then nil else tostring(setErr),
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
	}
end

function CrewMigrationPlanner.PrintMigrationWritePreviewReport(previewReport)
	print("[CrewMigrationPlanner] migration " .. tostring(previewReport and previewReport.Summary or "writepreview unavailable"))
	local diff = previewReport and previewReport.Diff
	for _, rootDiff in ipairs(diff and diff.RootDiffs or {}) do
		print(string.format(
			"[CrewMigrationPlanner] writePreviewRoot root=%s path=%s wouldChange=%s liveCount=%s projectedCount=%s liveOrder=%s projectedOrder=%s keysAdded=%d keysRemoved=%d keysUpdated=%d liveHash=%s projectedHash=%s",
			tostring(rootDiff.Root),
			tostring(rootDiff.Path),
			tostring(rootDiff.WouldChange),
			tostring(rootDiff.LiveCount),
			tostring(rootDiff.ProjectedCount),
			tostring(rootDiff.LiveOrderCount or ""),
			tostring(rootDiff.ProjectedOrderCount or ""),
			rootDiff.KeysAdded or 0,
			rootDiff.KeysRemoved or 0,
			rootDiff.KeysUpdated or 0,
			tostring(rootDiff.LiveHash),
			tostring(rootDiff.ProjectedHash)
		))
	end
	return previewReport
end

local canonicalMigrationRootWrites = {
	{
		Name = "CrewMemberInventory",
		Path = CrewStorage.FutureKeys.Inventory,
		GetValue = function(roots)
			return roots and roots.CrewMemberInventory
		end,
	},
	{
		Name = "CrewMemberQuickSlots",
		Path = CrewStorage.FutureKeys.QuickSlots,
		GetValue = function(roots)
			return roots and roots.CrewMemberQuickSlots
		end,
	},
	{
		Name = "CrewMemberIncome",
		Path = CrewStorage.FutureKeys.Income,
		GetValue = function(roots)
			return roots and roots.CrewMemberIncome
		end,
	},
	{
		Name = "IndexCollection.CrewMembers",
		Path = CrewStorage.FutureKeys.IndexCollection .. "." .. CrewStorage.FutureKeys.Index,
		GetValue = function(roots)
			return roots and roots.IndexCollection and roots.IndexCollection.CrewMembers
		end,
	},
}

local function getMigrationMutationNoGoReasons(flags, requireProfileMigrationWrite)
	local reasons = {}
	flags = if typeof(flags) == "table" then flags else CrewStorage.GetShadowFlags()
	if flags.CrewMemberMigrationKillSwitchEnabled ~= true then
		reasons[#reasons + 1] = "migration_kill_switch_not_enabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "write_authority_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		reasons[#reasons + 1] = "canonical_read_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		reasons[#reasons + 1] = "gameplay_reads_enabled"
	end
	if requireProfileMigrationWrite == true and flags.CrewMemberCanaryProfileMigrationWriteEnabled ~= true then
		reasons[#reasons + 1] = "profile_migration_write_disabled"
	end
	return reasons
end

local function writeCanonicalMigrationRoots(player, roots)
	local writes = {}
	for _, root in ipairs(canonicalMigrationRootWrites) do
		local value = root.GetValue(roots)
		if typeof(value) ~= "table" then
			return false, "canonical_root_missing:" .. root.Name, writes
		end

		local ok, reason = getDataManager():TrySetValue(player, root.Path, deepCopy(value))
		writes[#writes + 1] = {
			Root = root.Name,
			Path = root.Path,
			Ok = ok == true,
			Reason = reason,
		}
		if ok ~= true then
			return false, tostring(reason or "set_failed") .. ":" .. root.Name, writes
		end
	end
	return true, nil, writes
end

local function normalizeQuickSlotCount(value)
	local count = tonumber(value)
	if count == nil then
		return nil
	end
	return math.floor(count)
end

local function describeQuickSlotsRoot(value)
	if typeof(value) ~= "table" then
		return {
			Exists = false,
			Valid = false,
			Root = nil,
			UnlockedSlots = nil,
			MaxSlots = nil,
			Hash = hashStableValue(value),
		}
	end

	local unlockedSlots = normalizeQuickSlotCount(value.UnlockedSlots)
	local maxSlots = normalizeQuickSlotCount(value.MaxSlots)
	local valid = unlockedSlots ~= nil and maxSlots ~= nil
	return {
		Exists = true,
		Valid = valid,
		Root = deepCopy(value),
		UnlockedSlots = unlockedSlots,
		MaxSlots = maxSlots,
		Hash = hashStableValue(value),
	}
end

local function readQuickSlotsRoot(source, path)
	return describeQuickSlotsRoot(readValue(source, path))
end

local function buildQuickSlotRoot(currentRoot, unlockedSlots, maxSlots, includeSchemaVersion)
	local root = if typeof(currentRoot) == "table" then deepCopy(currentRoot) else {}
	root.UnlockedSlots = math.floor(tonumber(unlockedSlots) or CrewQuickSlotConfig.DefaultUnlockedSlots)
	root.MaxSlots = math.floor(tonumber(maxSlots) or CrewQuickSlotConfig.MaxSlots)
	if includeSchemaVersion == true then
		root.SchemaVersion = CrewProfileSchema.SchemaVersion
	else
		root.SchemaVersion = nil
	end
	return root
end

local function quickSlotCountsMatch(left, right)
	return typeof(left) == "table"
		and typeof(right) == "table"
		and left.Valid == true
		and right.Valid == true
		and left.UnlockedSlots == right.UnlockedSlots
		and left.MaxSlots == right.MaxSlots
end

local function quickSlotCountsInBounds(root, minSlots, maxSlots)
	return typeof(root) == "table"
		and root.Valid == true
		and root.UnlockedSlots >= minSlots
		and root.UnlockedSlots <= maxSlots
		and root.MaxSlots == maxSlots
end

local quickSlotCountKeys = {
	MaxSlots = true,
	SchemaVersion = true,
	UnlockedSlots = true,
}

local function getComparableQuickSlotContents(root)
	local source = if typeof(root) == "table" and typeof(root.Root) == "table" then root.Root else nil
	if source == nil then
		return {}
	end

	local contents = {}
	for key, value in pairs(source) do
		if quickSlotCountKeys[key] ~= true then
			contents[key] = deepCopy(value)
		end
	end
	return contents
end

local function quickSlotContentsMatch(left, right)
	if typeof(left) ~= "table" or typeof(right) ~= "table" or left.Valid ~= true or right.Valid ~= true then
		return false
	end
	return hashStableValue(getComparableQuickSlotContents(left)) == hashStableValue(getComparableQuickSlotContents(right))
end

local function getQuickSlotsWriteAuthorityNoGoReasons(flags, compareReport, status, requestedCount)
	local reasons = {}
	flags = if typeof(flags) == "table" then flags else CrewStorage.GetShadowFlags()
	local validation = compareReport and compareReport.Metadata and compareReport.Metadata.ValidationSummary or {}
	local requested = normalizeQuickSlotCount(requestedCount)
	local minSlots = math.max(0, math.floor(tonumber(CrewQuickSlotConfig.DefaultUnlockedSlots) or 0))
	local maxSlots = math.max(minSlots, math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or minSlots))

	if flags.CrewMemberMigrationKillSwitchEnabled ~= true then
		reasons[#reasons + 1] = "migration_kill_switch_not_enabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled ~= true then
		reasons[#reasons + 1] = "write_authority_disabled"
	end
	if flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled ~= true then
		reasons[#reasons + 1] = "quick_slots_write_authority_disabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		reasons[#reasons + 1] = "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		reasons[#reasons + 1] = "canonical_read_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		reasons[#reasons + 1] = "gameplay_reads_enabled"
	end
	if requested == nil then
		reasons[#reasons + 1] = "requested_count_invalid"
	elseif requested < minSlots or requested > maxSlots then
		reasons[#reasons + 1] = "requested_count_out_of_bounds"
	end
	if compareReport == nil or compareReport.CanProceed ~= true then
		reasons[#reasons + 1] = "compare_not_clean"
	end
	if compareReport and (compareReport.BlockingCount or 0) > 0 then
		reasons[#reasons + 1] = "blocking_mismatch"
	end
	if compareReport and (compareReport.UnclassifiedCount or 0) > 0 then
		reasons[#reasons + 1] = "unclassified_mismatch"
	end
	if validation.IsStale == true then
		reasons[#reasons + 1] = "validation_stale"
	end
	if validation.IsClean ~= true then
		reasons[#reasons + 1] = "validation_not_clean"
	end
	if getAuditCategoryCount(compareReport, "duplicate_assignment") > 0 then
		reasons[#reasons + 1] = "duplicate_assignment"
	end
	if getAuditCategoryCount(compareReport, "unknown_id") > 0 then
		reasons[#reasons + 1] = "unknown_id"
	end
	if getAuditCategoryCount(compareReport, "identity_mismatch") > 0 then
		reasons[#reasons + 1] = "identity_mismatch"
	end
	if getAuditCategoryCount(compareReport, "instance_mismatch") > 0 then
		reasons[#reasons + 1] = "instance_mismatch"
	end
	if getAuditCategoryCount(compareReport, "stand_mismatch") > 0 then
		reasons[#reasons + 1] = "stand_mismatch"
	end
	if getAuditCategoryCount(compareReport, "level_mismatch") > 0 then
		reasons[#reasons + 1] = "level_mismatch"
	end
	if getAuditCategoryCount(compareReport, "xp_mismatch") > 0 then
		reasons[#reasons + 1] = "xp_mismatch"
	end
	if status == nil or status.PrimaryRootsMatch ~= true then
		reasons[#reasons + 1] = "quick_slot_roots_mismatch"
	end
	if status and status.PrimaryContentsMatch ~= true then
		reasons[#reasons + 1] = "quick_slot_contents_mismatch"
	end
	if status and status.ConfigValid ~= true then
		reasons[#reasons + 1] = "quick_slot_config_missing"
	end
	if status and status.CanonicalValid ~= true then
		reasons[#reasons + 1] = "canonical_quick_slots_invalid"
	end
	if status and status.LegacyQuickSlotsValid ~= true then
		reasons[#reasons + 1] = "legacy_quick_slots_invalid"
	end
	if status and status.CanonicalInBounds ~= true then
		reasons[#reasons + 1] = "canonical_quick_slots_out_of_bounds"
	end
	if status and status.LegacyQuickSlotsInBounds ~= true then
		reasons[#reasons + 1] = "legacy_quick_slots_out_of_bounds"
	end
	return reasons
end

function CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, options)
	options = if typeof(options) == "table" then options else {}
	local flags = if typeof(options.Flags) == "table" then options.Flags else CrewStorage.GetShadowFlags()
	local canonical = readQuickSlotsRoot(source, { CrewStorage.FutureKeys.QuickSlots })
	local legacyQuickSlots = readQuickSlotsRoot(source, { CrewStorage.Keys.QuickSlots })
	local legacyStorage = readQuickSlotsRoot(source, { CrewStorage.Keys.QuickSlotsLegacy })
	local legacyStorageRetired = true
	local configMin = normalizeQuickSlotCount(CrewQuickSlotConfig.DefaultUnlockedSlots)
	local configMax = normalizeQuickSlotCount(CrewQuickSlotConfig.MaxSlots)
	local configValid = configMin ~= nil and configMax ~= nil and configMin >= 0 and configMax >= configMin
	local primaryRootsMatch = quickSlotCountsMatch(canonical, legacyQuickSlots)
	local legacyStorageMatchesCanonical = true
	local primaryContentsMatch = quickSlotContentsMatch(canonical, legacyQuickSlots)
	local legacyStorageContentsMatch = true
	local canonicalInBounds = configValid == true and quickSlotCountsInBounds(canonical, configMin, configMax)
	local legacyQuickSlotsInBounds = configValid == true and quickSlotCountsInBounds(legacyQuickSlots, configMin, configMax)
	local legacyStorageInBounds = true
	local legacyStorageStaleMirror = false
	local storageClassification = "retired"
	local rootsMatch = primaryRootsMatch == true
		and primaryContentsMatch == true
	local status = {
		AuthorityMode = "canary.write_authority.quick_slots",
		Flags = deepCopy(flags),
		ConfigValid = configValid,
		ConfigMinSlots = configMin,
		ConfigMaxSlots = configMax,
		Canonical = canonical,
		LegacyQuickSlots = legacyQuickSlots,
		LegacyStorage = legacyStorage,
		LegacyStorageRetired = legacyStorageRetired,
		CanonicalValid = canonical.Valid == true,
		LegacyQuickSlotsValid = legacyQuickSlots.Valid == true,
		LegacyStorageValid = legacyStorage.Valid == true,
		CanonicalInBounds = canonicalInBounds == true,
		LegacyQuickSlotsInBounds = legacyQuickSlotsInBounds == true,
		LegacyStorageInBounds = legacyStorageInBounds == true,
		PrimaryRootsMatch = primaryRootsMatch == true,
		LegacyStorageMatchesCanonical = legacyStorageMatchesCanonical == true,
		PrimaryContentsMatch = primaryContentsMatch == true,
		LegacyStorageContentsMatch = legacyStorageContentsMatch == true,
		LegacyStorageStaleMirror = legacyStorageStaleMirror == true,
		StorageClassification = storageClassification,
		ReviewClassifications = if legacyStorageStaleMirror == true then { storageClassification } else {},
		RootsMatch = rootsMatch == true,
		WriteAuthorityEnabled = flags.CrewMemberCanaryWriteAuthorityEnabled == true,
		QuickSlotsWriteAuthorityEnabled = flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true,
		ProductQuickSlotWriteAuthorityEnabled = flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true,
		CanonicalReadEnabled = flags.CrewMemberCanonicalReadEnabled == true,
		GameplayReadsEnabled = flags.CrewMemberCanaryGameplayReadsEnabled == true,
		ProfileMigrationWriteEnabled = flags.CrewMemberCanaryProfileMigrationWriteEnabled == true,
		KillSwitchEnabled = flags.CrewMemberMigrationKillSwitchEnabled == true,
	}
	status.Summary = string.format(
		"quickSlotsWriteAuthority status rootsMatch=%s primaryRootsMatch=%s storageRetired=%s storageClassification=%s canonical=%s/%s legacyQuick=%s/%s legacyStorage=%s/%s config=%s..%s bounds={canonical=%s legacyQuick=%s legacyStorage=%s} contents={primary=%s storage=%s} writeAuthority=%s quickSlotsWriteAuthority=%s productQuickSlotWriteAuthority=%s profileMigrationWrite=%s canonicalRead=%s gameplayReads=%s killSwitch=%s hashes={canonical=%s legacyQuick=%s legacyStorage=%s}",
		tostring(status.RootsMatch),
		tostring(status.PrimaryRootsMatch),
		tostring(status.LegacyStorageRetired),
		tostring(status.StorageClassification),
		tostring(canonical.UnlockedSlots),
		tostring(canonical.MaxSlots),
		tostring(legacyQuickSlots.UnlockedSlots),
		tostring(legacyQuickSlots.MaxSlots),
		tostring(legacyStorage.UnlockedSlots),
		tostring(legacyStorage.MaxSlots),
		tostring(configMin),
		tostring(configMax),
		tostring(status.CanonicalInBounds),
		tostring(status.LegacyQuickSlotsInBounds),
		tostring(status.LegacyStorageInBounds),
		tostring(status.PrimaryContentsMatch),
		tostring(status.LegacyStorageContentsMatch),
		tostring(status.WriteAuthorityEnabled),
		tostring(status.QuickSlotsWriteAuthorityEnabled),
		tostring(status.ProductQuickSlotWriteAuthorityEnabled),
		tostring(status.ProfileMigrationWriteEnabled),
		tostring(status.CanonicalReadEnabled),
		tostring(status.GameplayReadsEnabled),
		tostring(status.KillSwitchEnabled),
		tostring(canonical.Hash),
		tostring(legacyQuickSlots.Hash),
		tostring(legacyStorage.Hash)
	)
	return status
end

function CrewMigrationPlanner.SaveAndVerifyQuickSlotsWriteAuthorityRollback(source, report, snapshot)
	local userId = getAuditUserId(source, {
		UserId = report and report.UserId,
	})
	local key = getAuditKey(userId)
	if key == nil then
		return {
			Ok = false,
			Reason = "invalid_user_id",
			StoreName = AUDIT_DATA_STORE_NAME,
		}, nil
	end
	if typeof(snapshot) ~= "table" then
		return {
			Ok = false,
			Reason = "rollback_snapshot_missing",
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}, nil
	end

	local existing = nil
	local okGet, getErr = pcall(function()
		existing = getAuditDataStore():GetAsync(key)
	end)
	if okGet ~= true then
		return {
			Ok = false,
			Reason = tostring(getErr),
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}, nil
	end

	local record = if typeof(existing) == "table" then existing else {}
	record.StoreName = AUDIT_DATA_STORE_NAME
	record.Key = key
	record.UpdatedAt = os.time()
	record.LatestRollbackKind = "quick_slots_write_authority"
	record.QuickSlotsWriteAuthority = report
	record.QuickSlotsWriteAuthorityRollbackSnapshot = snapshot

	local okSet, setErr = pcall(function()
		getAuditDataStore():SetAsync(key, record)
	end)
	if okSet ~= true then
		return {
			Ok = false,
			Reason = tostring(setErr),
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}, nil
	end

	local loadResult = CrewMigrationPlanner.LoadMigrationAudit(source)
	local loadedRecord = loadResult.Record
	local loadedSnapshot = if typeof(loadedRecord) == "table" then loadedRecord.QuickSlotsWriteAuthorityRollbackSnapshot else nil
	local expectedHash = report and report.RollbackSnapshotHash
	local loadedHash = if typeof(loadedSnapshot) == "table" then hashStableValue(loadedSnapshot) else nil
	if loadResult.Ok ~= true or typeof(loadedSnapshot) ~= "table" or loadedHash ~= expectedHash then
		return {
			Ok = false,
			Reason = "rollback_snapshot_verify_failed",
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = key,
		}, loadResult
	end

	return {
		Ok = true,
		StoreName = AUDIT_DATA_STORE_NAME,
		Key = key,
		Record = record,
	}, loadResult
end

local function writeQuickSlotAuthorityRoots(player, preStatus, targetUnlockedSlots, targetMaxSlots)
	local writes = {}
	local canonicalRoot = buildQuickSlotRoot(
		preStatus and preStatus.Canonical and preStatus.Canonical.Root,
		targetUnlockedSlots,
		targetMaxSlots,
		true
	)
	local legacyQuickSlotsRoot = buildQuickSlotRoot(
		preStatus and preStatus.Canonical and preStatus.Canonical.Root,
		targetUnlockedSlots,
		targetMaxSlots,
		false
	)

	local function writeRoot(name, path, value)
		local ok, reason = getDataManager():TrySetValue(player, path, value)
		writes[#writes + 1] = {
			Root = name,
			Path = path,
			Ok = ok == true,
			Reason = reason,
		}
		if ok ~= true then
			return false, tostring(reason or "set_failed") .. ":" .. name
		end
		return true, nil
	end

	local ok, reason = writeRoot("CrewMemberQuickSlots", CrewStorage.FutureKeys.QuickSlots, canonicalRoot)
	if ok ~= true then
		return false, reason, writes
	end
	ok, reason = writeRoot("BrainrotQuickSlots", CrewStorage.Keys.QuickSlots, legacyQuickSlotsRoot)
	if ok ~= true then
		return false, reason, writes
	end
	return true, nil, writes
end

local function getProductQuickSlotsWriteAuthorityNoGoReasons(flags, compareReport, status, targetCount, options)
	local reasons = {}
	options = if typeof(options) == "table" then options else {}
	flags = if typeof(flags) == "table" then flags else CrewStorage.GetShadowFlags()
	local requested = normalizeQuickSlotCount(targetCount)
	local minSlots = math.max(0, math.floor(tonumber(CrewQuickSlotConfig.DefaultUnlockedSlots) or 0))
	local maxSlots = math.max(minSlots, math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or minSlots))
	local tokenAuthority = options.TokenAuthority == true

	if flags.CrewMemberMigrationKillSwitchEnabled ~= true then
		reasons[#reasons + 1] = "migration_kill_switch_not_enabled"
	end
	if flags.CrewMemberProductQuickSlotWriteAuthorityEnabled ~= true and tokenAuthority ~= true then
		reasons[#reasons + 1] = "product_quick_slot_write_authority_disabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "broad_write_authority_enabled"
	end
	if flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "quick_slots_canary_write_authority_enabled"
	end
	if flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true then
		reasons[#reasons + 1] = "profile_migration_dry_run_enabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		reasons[#reasons + 1] = "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		reasons[#reasons + 1] = "canonical_read_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		reasons[#reasons + 1] = "gameplay_reads_enabled"
	end
	if flags.CrewMemberCanaryReadAuthorityEnabled == true then
		reasons[#reasons + 1] = "read_authority_enabled"
	end
	if requested == nil then
		reasons[#reasons + 1] = "target_count_invalid"
	elseif requested < minSlots or requested > maxSlots then
		reasons[#reasons + 1] = "target_count_out_of_bounds"
	end
	if compareReport == nil then
		reasons[#reasons + 1] = "compare_missing"
	elseif (compareReport.BlockingCount or 0) > 0 then
		reasons[#reasons + 1] = "blocking_mismatch"
	end
	if compareReport and (compareReport.UnclassifiedCount or 0) > 0 then
		reasons[#reasons + 1] = "unclassified_mismatch"
	end
	if getAuditCategoryCount(compareReport, "duplicate_assignment") > 0 then
		reasons[#reasons + 1] = "duplicate_assignment"
	end
	if getAuditCategoryCount(compareReport, "unknown_id") > 0 then
		reasons[#reasons + 1] = "unknown_id"
	end
	if status == nil or status.RootsMatch ~= true then
		reasons[#reasons + 1] = "quick_slot_roots_mismatch"
	end
	if status and status.PrimaryContentsMatch ~= true then
		reasons[#reasons + 1] = "quick_slot_contents_mismatch"
	end
	if status and status.ConfigValid ~= true then
		reasons[#reasons + 1] = "quick_slot_config_missing"
	end
	if status and status.CanonicalValid ~= true then
		reasons[#reasons + 1] = "canonical_quick_slots_invalid"
	end
	if status and status.LegacyQuickSlotsValid ~= true then
		reasons[#reasons + 1] = "legacy_quick_slots_invalid"
	end
	if status and status.CanonicalInBounds ~= true then
		reasons[#reasons + 1] = "canonical_quick_slots_out_of_bounds"
	end
	if status and status.LegacyQuickSlotsInBounds ~= true then
		reasons[#reasons + 1] = "legacy_quick_slots_out_of_bounds"
	end

	return reasons
end

function CrewMigrationPlanner.ExecuteProductQuickSlotsWriteAuthoritySet(source, targetCount, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return {
			Passed = false,
			NoGoReasons = { "player_source_required" },
			Summary = "productQuickSlotsWriteAuthoritySet passed=false noGo=player_source_required",
		}
	end

	local flags = if typeof(options.Flags) == "table" then options.Flags else CrewStorage.GetShadowFlags()
	local preStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, {
		Flags = flags,
	})
	local compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local requested = normalizeQuickSlotCount(targetCount)
	local targetMaxSlots = math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or 0)
	local targetUnlockedSlots = CrewQuickSlotConfig.ClampUnlockedSlots(requested)
	local metadata = compareReport.Metadata or getSourceMetadata(source, options)
	local receiptInfo = if typeof(options.ReceiptInfo) == "table" then options.ReceiptInfo else {}
	local productId = tonumber(options.ProductId or receiptInfo.ProductId)
	local purchaseId = tostring(options.PurchaseId or receiptInfo.PurchaseId or "")
	local noGoReasons = getProductQuickSlotsWriteAuthorityNoGoReasons(
		flags,
		compareReport,
		preStatus,
		requested,
		options
	)
	local report = {
		UserId = metadata.UserId,
		PlayerName = metadata.PlayerName,
		PlaceId = metadata.PlaceId,
		GameId = metadata.GameId,
		JobId = metadata.JobId,
		TimestampUnix = os.time(),
		TimestampClock = os.clock(),
		ToolVersion = MIGRATION_TOOL_VERSION,
		SchemaVersion = 1,
		CommandType = tostring(options.CommandType or "product.quick_slot_unlock"),
		AuthorityMode = tostring(options.AuthorityMode or "product.write_authority.quick_slots"),
		ProductId = productId,
		PurchaseId = purchaseId,
		TargetUnlockedSlots = targetUnlockedSlots,
		TargetMaxSlots = targetMaxSlots,
		OldUnlockedSlots = preStatus.Canonical and preStatus.Canonical.UnlockedSlots,
		OldMaxSlots = preStatus.Canonical and preStatus.Canonical.MaxSlots,
		OldLegacyQuickSlotsUnlockedSlots = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.UnlockedSlots,
		OldLegacyQuickSlotsMaxSlots = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.MaxSlots,
		OldLegacyStorageUnlockedSlots = preStatus.LegacyStorage and preStatus.LegacyStorage.UnlockedSlots,
		OldLegacyStorageMaxSlots = preStatus.LegacyStorage and preStatus.LegacyStorage.MaxSlots,
		OldCanonicalHash = preStatus.Canonical and preStatus.Canonical.Hash,
		OldLegacyQuickSlotsHash = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.Hash,
		OldLegacyStorageHash = preStatus.LegacyStorage and preStatus.LegacyStorage.Hash,
		StorageClassification = preStatus.StorageClassification,
		TokenAuthority = options.TokenAuthority == true,
		TokenId = tostring(options.TokenId or ""),
		TokenState = tostring(options.TokenState or ""),
		TokenSource = tostring(options.TokenSource or ""),
		GlobalFlagAtReceipt = options.GlobalFlagAtReceipt == true,
		RecoveryUsed = options.RecoveryUsed == true,
		BlockingCount = compareReport.BlockingCount or 0,
		UnclassifiedCount = compareReport.UnclassifiedCount or 0,
		ValidationSummary = deepCopy(metadata.ValidationSummary or {}),
		Flags = deepCopy(flags),
		CanWriteQuickSlots = #noGoReasons == 0,
	}
	report.Summary = string.format(
		"productQuickSlotsWriteAuthorityPreview canWrite=%s receipt=%s productId=%s oldCanonical=%s/%s oldLegacyQuick=%s/%s oldStorage=%s/%s target=%s/%s storageClassification=%s blocking=%d unclassified=%d noGo=%s",
		tostring(report.CanWriteQuickSlots),
		tostring(report.PurchaseId),
		tostring(report.ProductId),
		tostring(report.OldUnlockedSlots),
		tostring(report.OldMaxSlots),
		tostring(report.OldLegacyQuickSlotsUnlockedSlots),
		tostring(report.OldLegacyQuickSlotsMaxSlots),
		tostring(report.OldLegacyStorageUnlockedSlots),
		tostring(report.OldLegacyStorageMaxSlots),
		tostring(report.TargetUnlockedSlots),
		tostring(report.TargetMaxSlots),
		tostring(report.StorageClassification),
		report.BlockingCount,
		report.UnclassifiedCount,
		if #noGoReasons > 0 then table.concat(noGoReasons, ",") else "none"
	)

	if #noGoReasons > 0 then
		return {
			Passed = false,
			Report = report,
			PreStatus = preStatus,
			PreCompare = compareReport,
			NoGoReasons = noGoReasons,
			Summary = "productQuickSlotsWriteAuthoritySet passed=false noGo=" .. table.concat(noGoReasons, ","),
		}
	end

	local writeOk, writeReason, writes = writeQuickSlotAuthorityRoots(
		source,
		preStatus,
		targetUnlockedSlots,
		targetMaxSlots
	)
	local postStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, {
		Flags = flags,
	})
	local postCompare = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local postNoGoReasons = {}
	if writeOk ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = tostring(writeReason or "write_failed")
	end
	if postStatus.RootsMatch ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = "quick_slot_roots_mismatch"
	end
	if postStatus.PrimaryContentsMatch ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = "quick_slot_contents_mismatch"
	end
	if postCompare.BlockingCount ~= 0 then
		postNoGoReasons[#postNoGoReasons + 1] = "blocking_mismatch"
	end
	if postCompare.UnclassifiedCount ~= 0 then
		postNoGoReasons[#postNoGoReasons + 1] = "unclassified_mismatch"
	end
	if postStatus.Canonical == nil or postStatus.Canonical.UnlockedSlots ~= targetUnlockedSlots then
		postNoGoReasons[#postNoGoReasons + 1] = "canonical_target_mismatch"
	end
	if postStatus.LegacyQuickSlots == nil or postStatus.LegacyQuickSlots.UnlockedSlots ~= targetUnlockedSlots then
		postNoGoReasons[#postNoGoReasons + 1] = "legacy_quick_slots_target_mismatch"
	end

	local result = {
		Passed = #postNoGoReasons == 0,
		Report = report,
		PreStatus = preStatus,
		PostStatus = postStatus,
		PreCompare = compareReport,
		PostCompare = postCompare,
		Writes = writes,
		WriteReason = writeReason,
		NoGoReasons = postNoGoReasons,
		ProductAudit = {
			ReceiptId = purchaseId,
			ProductId = productId,
			OldUnlockedSlots = report.OldUnlockedSlots,
			OldLegacyQuickSlotsUnlockedSlots = report.OldLegacyQuickSlotsUnlockedSlots,
			OldLegacyStorageUnlockedSlots = report.OldLegacyStorageUnlockedSlots,
			TargetUnlockedSlots = targetUnlockedSlots,
			TargetMaxSlots = targetMaxSlots,
			RootWrites = deepCopy(writes),
			PostRootsMatch = postStatus.RootsMatch == true,
			PostBlockingCount = postCompare.BlockingCount or 0,
			PostUnclassifiedCount = postCompare.UnclassifiedCount or 0,
			EntitlementAlreadyGranted = #postNoGoReasons == 0,
		},
	}
	result.Summary = string.format(
		"productQuickSlotsWriteAuthoritySet passed=%s receipt=%s productId=%s oldCanonical=%s/%s oldStorage=%s/%s newCanonical=%s/%s newLegacyQuick=%s/%s newStorage=%s/%s writes=%d rootsMatch=%s storageClassification=%s writeReason=%s postBlocking=%d postUnclassified=%d noGo=%s",
		tostring(result.Passed),
		tostring(report.PurchaseId),
		tostring(report.ProductId),
		tostring(report.OldUnlockedSlots),
		tostring(report.OldMaxSlots),
		tostring(report.OldLegacyStorageUnlockedSlots),
		tostring(report.OldLegacyStorageMaxSlots),
		tostring(postStatus.Canonical and postStatus.Canonical.UnlockedSlots),
		tostring(postStatus.Canonical and postStatus.Canonical.MaxSlots),
		tostring(postStatus.LegacyQuickSlots and postStatus.LegacyQuickSlots.UnlockedSlots),
		tostring(postStatus.LegacyQuickSlots and postStatus.LegacyQuickSlots.MaxSlots),
		tostring(postStatus.LegacyStorage and postStatus.LegacyStorage.UnlockedSlots),
		tostring(postStatus.LegacyStorage and postStatus.LegacyStorage.MaxSlots),
		#writes,
		tostring(postStatus.RootsMatch == true),
		tostring(report.StorageClassification),
		tostring(writeReason or "none"),
		postCompare.BlockingCount or 0,
		postCompare.UnclassifiedCount or 0,
		if #postNoGoReasons > 0 then table.concat(postNoGoReasons, ",") else "none"
	)
	return result
end

local function getProductQuickSlotsStorageReconciliationNoGoReasons(flags, compareReport, status, targetCount)
	local reasons = {}
	flags = if typeof(flags) == "table" then flags else CrewStorage.GetShadowFlags()
	local requested = normalizeQuickSlotCount(targetCount)
	local minSlots = math.max(0, math.floor(tonumber(CrewQuickSlotConfig.DefaultUnlockedSlots) or 0))
	local maxSlots = math.max(minSlots, math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or minSlots))

	if flags.CrewMemberMigrationKillSwitchEnabled ~= true then
		reasons[#reasons + 1] = "migration_kill_switch_not_enabled"
	end
	if flags.CrewMemberCanaryWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "broad_write_authority_enabled"
	end
	if flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true then
		reasons[#reasons + 1] = "quick_slots_canary_write_authority_enabled"
	end
	if flags.CrewMemberCanaryProfileMigrationDryRunEnabled == true then
		reasons[#reasons + 1] = "profile_migration_dry_run_enabled"
	end
	if flags.CrewMemberCanaryProfileMigrationWriteEnabled == true then
		reasons[#reasons + 1] = "profile_migration_write_enabled"
	end
	if flags.CrewMemberCanonicalReadEnabled == true then
		reasons[#reasons + 1] = "canonical_read_enabled"
	end
	if flags.CrewMemberCanaryGameplayReadsEnabled == true then
		reasons[#reasons + 1] = "gameplay_reads_enabled"
	end
	if flags.CrewMemberCanaryReadAuthorityEnabled == true then
		reasons[#reasons + 1] = "read_authority_enabled"
	end
	if requested == nil then
		reasons[#reasons + 1] = "target_count_invalid"
	elseif requested < minSlots or requested > maxSlots then
		reasons[#reasons + 1] = "target_count_out_of_bounds"
	end
	if compareReport == nil then
		reasons[#reasons + 1] = "compare_missing"
	elseif (compareReport.BlockingCount or 0) > 0 then
		reasons[#reasons + 1] = "blocking_mismatch"
	end
	if compareReport and (compareReport.UnclassifiedCount or 0) > 0 then
		reasons[#reasons + 1] = "unclassified_mismatch"
	end
	if getAuditCategoryCount(compareReport, "duplicate_assignment") > 0 then
		reasons[#reasons + 1] = "duplicate_assignment"
	end
	if getAuditCategoryCount(compareReport, "unknown_id") > 0 then
		reasons[#reasons + 1] = "unknown_id"
	end
	if status == nil or status.PrimaryRootsMatch ~= true then
		reasons[#reasons + 1] = "quick_slot_primary_roots_mismatch"
	end
	if status and status.StorageClassification ~= "quick_slot_storage_stale_mirror" then
		reasons[#reasons + 1] = "quick_slot_storage_not_stale_mirror"
	end
	if status and status.PrimaryContentsMatch ~= true then
		reasons[#reasons + 1] = "quick_slot_contents_mismatch"
	end
	if status and status.LegacyStorageContentsMatch ~= true then
		reasons[#reasons + 1] = "quick_slot_storage_contents_mismatch"
	end
	if status and status.ConfigValid ~= true then
		reasons[#reasons + 1] = "quick_slot_config_missing"
	end
	if status and status.CanonicalValid ~= true then
		reasons[#reasons + 1] = "canonical_quick_slots_invalid"
	end
	if status and status.LegacyQuickSlotsValid ~= true then
		reasons[#reasons + 1] = "legacy_quick_slots_invalid"
	end
	if status and status.LegacyStorageValid ~= true then
		reasons[#reasons + 1] = "legacy_storage_quick_slots_invalid"
	end
	if status and status.CanonicalInBounds ~= true then
		reasons[#reasons + 1] = "canonical_quick_slots_out_of_bounds"
	end
	if status and status.LegacyQuickSlotsInBounds ~= true then
		reasons[#reasons + 1] = "legacy_quick_slots_out_of_bounds"
	end
	if status and status.LegacyStorageInBounds ~= true then
		reasons[#reasons + 1] = "legacy_storage_quick_slots_out_of_bounds"
	end
	if status and status.Canonical and status.Canonical.UnlockedSlots ~= requested then
		reasons[#reasons + 1] = "canonical_target_mismatch"
	end
	if status and status.LegacyQuickSlots and status.LegacyQuickSlots.UnlockedSlots ~= requested then
		reasons[#reasons + 1] = "legacy_quick_slots_target_mismatch"
	end

	return reasons
end

function CrewMigrationPlanner.ExecuteProductQuickSlotsStorageReconciliation(source, targetCount, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return {
			Passed = false,
			NoGoReasons = { "player_source_required" },
			Summary = "productQuickSlotsStorageReconciliation passed=false noGo=player_source_required",
		}
	end
	local receiptInfo = if typeof(options.ReceiptInfo) == "table" then options.ReceiptInfo else {}
	local productId = tonumber(options.ProductId or receiptInfo.ProductId)
	local purchaseId = tostring(options.PurchaseId or receiptInfo.PurchaseId or "")
	do
		return {
			Passed = true,
			Skipped = true,
			NoGoReasons = {},
			RecoveryUsed = false,
			ProductAudit = {
				ReceiptId = purchaseId,
				ProductId = productId,
				RootWrites = {},
				RecoveryUsed = false,
				EntitlementAlreadyGranted = true,
			},
			Summary = string.format(
				"productQuickSlotsStorageReconciliation passed=true skipped=true receipt=%s productId=%s reason=brainrot_storage_retired",
				tostring(purchaseId),
				tostring(productId)
			),
		}
	end

	local flags = if typeof(options.Flags) == "table" then options.Flags else CrewStorage.GetShadowFlags()
	local preStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, {
		Flags = flags,
	})
	local compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local requested = normalizeQuickSlotCount(targetCount)
	local targetMaxSlots = math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or 0)
	local targetUnlockedSlots = CrewQuickSlotConfig.ClampUnlockedSlots(requested)
	local metadata = compareReport.Metadata or getSourceMetadata(source, options)
	local noGoReasons = getProductQuickSlotsStorageReconciliationNoGoReasons(
		flags,
		compareReport,
		preStatus,
		requested
	)
	local report = {
		UserId = metadata.UserId,
		PlayerName = metadata.PlayerName,
		PlaceId = metadata.PlaceId,
		GameId = metadata.GameId,
		JobId = metadata.JobId,
		TimestampUnix = os.time(),
		TimestampClock = os.clock(),
		ToolVersion = MIGRATION_TOOL_VERSION,
		SchemaVersion = 1,
		CommandType = tostring(options.CommandType or "product.quick_slot_storage_reconciliation"),
		AuthorityMode = tostring(options.AuthorityMode or "product.write_authority.quick_slots.reconciliation"),
		ProductId = productId,
		PurchaseId = purchaseId,
		TokenAuthority = options.TokenAuthority == true,
		TokenId = tostring(options.TokenId or ""),
		TokenState = tostring(options.TokenState or ""),
		TokenSource = tostring(options.TokenSource or ""),
		GlobalFlagAtReceipt = options.GlobalFlagAtReceipt == true,
		RecoveryUsed = true,
		TargetUnlockedSlots = targetUnlockedSlots,
		TargetMaxSlots = targetMaxSlots,
		OldUnlockedSlots = preStatus.Canonical and preStatus.Canonical.UnlockedSlots,
		OldMaxSlots = preStatus.Canonical and preStatus.Canonical.MaxSlots,
		OldLegacyQuickSlotsUnlockedSlots = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.UnlockedSlots,
		OldLegacyQuickSlotsMaxSlots = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.MaxSlots,
		OldLegacyStorageUnlockedSlots = preStatus.LegacyStorage and preStatus.LegacyStorage.UnlockedSlots,
		OldLegacyStorageMaxSlots = preStatus.LegacyStorage and preStatus.LegacyStorage.MaxSlots,
		StorageClassification = preStatus.StorageClassification,
		BlockingCount = compareReport.BlockingCount or 0,
		UnclassifiedCount = compareReport.UnclassifiedCount or 0,
		ValidationSummary = deepCopy(metadata.ValidationSummary or {}),
		Flags = deepCopy(flags),
		CanRepairQuickSlots = #noGoReasons == 0,
	}

	if #noGoReasons > 0 then
		return {
			Passed = false,
			Report = report,
			PreStatus = preStatus,
			PreCompare = compareReport,
			NoGoReasons = noGoReasons,
			Summary = "productQuickSlotsStorageReconciliation passed=false noGo=" .. table.concat(noGoReasons, ","),
		}
	end

	local writeOk, writeReason, writes = writeQuickSlotAuthorityRoots(
		source,
		preStatus,
		targetUnlockedSlots,
		targetMaxSlots
	)
	local postStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, {
		Flags = flags,
	})
	local postCompare = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local postNoGoReasons = {}
	if writeOk ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = tostring(writeReason or "write_failed")
	end
	if postStatus.RootsMatch ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = "quick_slot_roots_mismatch"
	end
	if postStatus.PrimaryContentsMatch ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = "quick_slot_contents_mismatch"
	end
	if postStatus.LegacyStorageContentsMatch ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = "quick_slot_storage_contents_mismatch"
	end
	if postCompare.BlockingCount ~= 0 then
		postNoGoReasons[#postNoGoReasons + 1] = "blocking_mismatch"
	end
	if postCompare.UnclassifiedCount ~= 0 then
		postNoGoReasons[#postNoGoReasons + 1] = "unclassified_mismatch"
	end
	if postStatus.Canonical == nil or postStatus.Canonical.UnlockedSlots ~= targetUnlockedSlots then
		postNoGoReasons[#postNoGoReasons + 1] = "canonical_target_mismatch"
	end
	if postStatus.LegacyQuickSlots == nil or postStatus.LegacyQuickSlots.UnlockedSlots ~= targetUnlockedSlots then
		postNoGoReasons[#postNoGoReasons + 1] = "legacy_quick_slots_target_mismatch"
	end
	if postStatus.LegacyStorage == nil or postStatus.LegacyStorage.UnlockedSlots ~= targetUnlockedSlots then
		postNoGoReasons[#postNoGoReasons + 1] = "legacy_storage_target_mismatch"
	end

	local result = {
		Passed = #postNoGoReasons == 0,
		Report = report,
		PreStatus = preStatus,
		PostStatus = postStatus,
		PreCompare = compareReport,
		PostCompare = postCompare,
		Writes = writes,
		WriteReason = writeReason,
		NoGoReasons = postNoGoReasons,
		RecoveryUsed = true,
		ProductAudit = {
			ReceiptId = purchaseId,
			ProductId = productId,
			TokenId = report.TokenId,
			OldUnlockedSlots = report.OldUnlockedSlots,
			OldLegacyQuickSlotsUnlockedSlots = report.OldLegacyQuickSlotsUnlockedSlots,
			OldLegacyStorageUnlockedSlots = report.OldLegacyStorageUnlockedSlots,
			TargetUnlockedSlots = targetUnlockedSlots,
			TargetMaxSlots = targetMaxSlots,
			RootWrites = deepCopy(writes),
			PostRootsMatch = postStatus.RootsMatch == true,
			PostBlockingCount = postCompare.BlockingCount or 0,
			PostUnclassifiedCount = postCompare.UnclassifiedCount or 0,
			RecoveryUsed = true,
			EntitlementAlreadyGranted = #postNoGoReasons == 0,
		},
	}
	result.Summary = string.format(
		"productQuickSlotsStorageReconciliation passed=%s receipt=%s productId=%s token=%s oldCanonical=%s/%s oldStorage=%s/%s target=%s/%s newCanonical=%s/%s newLegacyQuick=%s/%s newStorage=%s/%s writes=%d rootsMatch=%s storageClassification=%s writeReason=%s postBlocking=%d postUnclassified=%d noGo=%s",
		tostring(result.Passed),
		tostring(report.PurchaseId),
		tostring(report.ProductId),
		tostring(report.TokenId),
		tostring(report.OldUnlockedSlots),
		tostring(report.OldMaxSlots),
		tostring(report.OldLegacyStorageUnlockedSlots),
		tostring(report.OldLegacyStorageMaxSlots),
		tostring(report.TargetUnlockedSlots),
		tostring(report.TargetMaxSlots),
		tostring(postStatus.Canonical and postStatus.Canonical.UnlockedSlots),
		tostring(postStatus.Canonical and postStatus.Canonical.MaxSlots),
		tostring(postStatus.LegacyQuickSlots and postStatus.LegacyQuickSlots.UnlockedSlots),
		tostring(postStatus.LegacyQuickSlots and postStatus.LegacyQuickSlots.MaxSlots),
		tostring(postStatus.LegacyStorage and postStatus.LegacyStorage.UnlockedSlots),
		tostring(postStatus.LegacyStorage and postStatus.LegacyStorage.MaxSlots),
		#writes,
		tostring(postStatus.RootsMatch == true),
		tostring(report.StorageClassification),
		tostring(writeReason or "none"),
		postCompare.BlockingCount or 0,
		postCompare.UnclassifiedCount or 0,
		if #postNoGoReasons > 0 then table.concat(postNoGoReasons, ",") else "none"
	)
	return result
end

local quickSlotRollbackSnapshotRoots = {
	{
		Name = "CrewMemberQuickSlots",
		Path = CrewStorage.FutureKeys.QuickSlots,
		GetValue = function(snapshot)
			return snapshot and snapshot.Canonical and snapshot.Canonical.CrewMemberQuickSlots
		end,
	},
	{
		Name = "BrainrotQuickSlots",
		Path = CrewStorage.Keys.QuickSlots,
		GetValue = function(snapshot)
			return snapshot and snapshot.Legacy and snapshot.Legacy.BrainrotQuickSlots
		end,
	},
}

local function validateQuickSlotRollbackSnapshotRoot(rootName, value)
	local status = describeQuickSlotsRoot(value)
	if status.Exists ~= true then
		return false, "quick_slots_rollback_snapshot_root_missing:" .. rootName, status
	end
	if status.Valid ~= true then
		return false, "quick_slots_rollback_snapshot_root_invalid:" .. rootName, status
	end
	local minSlots = math.max(0, math.floor(tonumber(CrewQuickSlotConfig.DefaultUnlockedSlots) or 0))
	local maxSlots = math.max(minSlots, math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or minSlots))
	if quickSlotCountsInBounds(status, minSlots, maxSlots) ~= true then
		return false, "quick_slots_rollback_snapshot_root_out_of_bounds:" .. rootName, status
	end
	return true, nil, status
end

local function getQuickSlotRollbackSnapshotRoots(snapshot)
	local roots = {}
	local statuses = {}
	for _, root in ipairs(quickSlotRollbackSnapshotRoots) do
		local value = root.GetValue(snapshot)
		local ok, reason, status = validateQuickSlotRollbackSnapshotRoot(root.Name, value)
		if ok ~= true then
			return nil, nil, reason
		end
		roots[root.Name] = deepCopy(value)
		statuses[root.Name] = status
	end

	local canonical = statuses.CrewMemberQuickSlots
	if quickSlotCountsMatch(canonical, statuses.BrainrotQuickSlots) ~= true then
		return nil, nil, "quick_slots_rollback_snapshot_roots_mismatch"
	end
	if quickSlotContentsMatch(canonical, statuses.BrainrotQuickSlots) ~= true then
		return nil, nil, "quick_slots_rollback_snapshot_contents_mismatch"
	end

	return roots, statuses, nil
end

local function writeQuickSlotAuthorityRollbackRoots(player, snapshot)
	local roots, statuses, snapshotReason = getQuickSlotRollbackSnapshotRoots(snapshot)
	if roots == nil then
		return false, tostring(snapshotReason or "quick_slots_rollback_snapshot_invalid"), {}, statuses
	end

	local writes = {}
	local function writeRoot(root)
		local value = roots[root.Name]
		local ok, reason = getDataManager():TrySetValue(player, root.Path, deepCopy(value))
		writes[#writes + 1] = {
			Root = root.Name,
			Path = root.Path,
			Ok = ok == true,
			Reason = reason,
		}
		if ok ~= true then
			return false, "rollback_write_failed:" .. root.Name
		end
		return true, nil
	end

	for _, root in ipairs(quickSlotRollbackSnapshotRoots) do
		local ok, reason = writeRoot(root)
		if ok ~= true then
			return false, reason, writes, statuses
		end
	end
	return true, nil, writes, statuses
end

local function quickSlotStatusMatchesRollbackSnapshot(status, snapshotStatuses)
	if typeof(status) ~= "table" or typeof(snapshotStatuses) ~= "table" then
		return false
	end
	return quickSlotCountsMatch(status.Canonical, snapshotStatuses.CrewMemberQuickSlots)
		and quickSlotCountsMatch(status.LegacyQuickSlots, snapshotStatuses.BrainrotQuickSlots)
end

function CrewMigrationPlanner.ExecuteQuickSlotsWriteAuthoritySet(source, requestedCount, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return {
			Passed = false,
			NoGoReasons = { "player_source_required" },
			Summary = "quickSlotsWriteAuthoritySet passed=false noGo=player_source_required",
		}
	end

	local flags = if typeof(options.Flags) == "table" then options.Flags else CrewStorage.GetShadowFlags()
	local validationStatus = options.ValidationStatus
	local compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = validationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local preStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, {
		Flags = flags,
	})
	local snapshot = CrewMigrationPlanner.BuildMigrationSnapshot(source, {
		ValidationStatus = validationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local rollbackHash = hashStableValue(snapshot)
	local requested = normalizeQuickSlotCount(requestedCount)
	local targetMaxSlots = math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or 0)
	local targetUnlockedSlots = CrewQuickSlotConfig.ClampUnlockedSlots(requested)
	local metadata = compareReport.Metadata or getSourceMetadata(source, options)
	local noGoReasons = getQuickSlotsWriteAuthorityNoGoReasons(flags, compareReport, preStatus, requested)
	local report = {
		UserId = metadata.UserId,
		PlayerName = metadata.PlayerName,
		PlaceId = metadata.PlaceId,
		GameId = metadata.GameId,
		JobId = metadata.JobId,
		TimestampUnix = os.time(),
		TimestampClock = os.clock(),
		ToolVersion = MIGRATION_TOOL_VERSION,
		SchemaVersion = 1,
		CommandType = "writeauthority.quick_slots",
		AuthorityMode = "canary.write_authority.quick_slots",
		RequestedUnlockedSlots = requested,
		TargetUnlockedSlots = targetUnlockedSlots,
		TargetMaxSlots = targetMaxSlots,
		OldUnlockedSlots = preStatus.Canonical and preStatus.Canonical.UnlockedSlots,
		OldMaxSlots = preStatus.Canonical and preStatus.Canonical.MaxSlots,
		OldLegacyQuickSlotsUnlockedSlots = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.UnlockedSlots,
		OldLegacyQuickSlotsMaxSlots = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.MaxSlots,
		OldLegacyStorageUnlockedSlots = preStatus.LegacyStorage and preStatus.LegacyStorage.UnlockedSlots,
		OldLegacyStorageMaxSlots = preStatus.LegacyStorage and preStatus.LegacyStorage.MaxSlots,
		OldCanonicalHash = preStatus.Canonical and preStatus.Canonical.Hash,
		OldLegacyQuickSlotsHash = preStatus.LegacyQuickSlots and preStatus.LegacyQuickSlots.Hash,
		OldLegacyStorageHash = preStatus.LegacyStorage and preStatus.LegacyStorage.Hash,
		StorageClassification = preStatus.StorageClassification,
		ReviewClassifications = deepCopy(preStatus.ReviewClassifications or {}),
		RollbackSnapshotHash = rollbackHash,
		BlockingCount = compareReport.BlockingCount or 0,
		UnclassifiedCount = compareReport.UnclassifiedCount or 0,
		DuplicateAssignmentCount = getAuditCategoryCount(compareReport, "duplicate_assignment"),
		UnknownIdCount = getAuditCategoryCount(compareReport, "unknown_id"),
		ValidationSummary = deepCopy(metadata.ValidationSummary or {}),
		Flags = deepCopy(flags),
		CanWriteQuickSlots = #noGoReasons == 0,
	}
	report.Summary = string.format(
		"quickSlotsWriteAuthorityPreview canWrite=%s oldCanonical=%s/%s oldLegacyQuick=%s/%s oldStorage=%s/%s target=%s/%s storageClassification=%s blocking=%d unclassified=%d rollbackHash=%s noGo=%s",
		tostring(report.CanWriteQuickSlots),
		tostring(report.OldUnlockedSlots),
		tostring(report.OldMaxSlots),
		tostring(report.OldLegacyQuickSlotsUnlockedSlots),
		tostring(report.OldLegacyQuickSlotsMaxSlots),
		tostring(report.OldLegacyStorageUnlockedSlots),
		tostring(report.OldLegacyStorageMaxSlots),
		tostring(report.TargetUnlockedSlots),
		tostring(report.TargetMaxSlots),
		tostring(report.StorageClassification),
		report.BlockingCount,
		report.UnclassifiedCount,
		tostring(report.RollbackSnapshotHash),
		if #noGoReasons > 0 then table.concat(noGoReasons, ",") else "none"
	)

	if #noGoReasons > 0 then
		return {
			Passed = false,
			Report = report,
			PreStatus = preStatus,
			PreCompare = compareReport,
			NoGoReasons = noGoReasons,
			Summary = "quickSlotsWriteAuthoritySet passed=false noGo=" .. table.concat(noGoReasons, ","),
		}
	end

	local saveResult, loadResult = CrewMigrationPlanner.SaveAndVerifyQuickSlotsWriteAuthorityRollback(source, report, snapshot)
	if saveResult.Ok ~= true then
		return {
			Passed = false,
			Report = report,
			PreStatus = preStatus,
			PreCompare = compareReport,
			SaveResult = saveResult,
			LoadResult = loadResult,
			NoGoReasons = { "rollback_snapshot_store_failed" },
			Summary = "quickSlotsWriteAuthoritySet passed=false noGo=rollback_snapshot_store_failed",
		}
	end

	local writeOk, writeReason, writes = writeQuickSlotAuthorityRoots(
		source,
		preStatus,
		targetUnlockedSlots,
		targetMaxSlots
	)
	local postStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, {
		Flags = flags,
	})
	local postCompare = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local passed = writeOk == true
		and postStatus.RootsMatch == true
		and postCompare.BlockingCount == 0
		and postCompare.UnclassifiedCount == 0
		and postStatus.Canonical
		and postStatus.Canonical.UnlockedSlots == targetUnlockedSlots
		and postStatus.Canonical.MaxSlots == targetMaxSlots
	local result = {
		Passed = passed,
		Report = report,
		PreStatus = preStatus,
		PostStatus = postStatus,
		PreCompare = compareReport,
		PostCompare = postCompare,
		SaveResult = saveResult,
		LoadResult = loadResult,
		Writes = writes,
		NoGoReasons = if writeOk == true then {} else { tostring(writeReason or "write_failed") },
		CanonicalBecameMutationSource = writeOk == true,
		LegacyDualWriteMatched = postStatus.RootsMatch == true,
	}
	result.Summary = string.format(
		"quickSlotsWriteAuthoritySet passed=%s oldCanonical=%s/%s oldStorage=%s/%s newCanonical=%s/%s newLegacyQuick=%s/%s newStorage=%s/%s writes=%d rootsMatch=%s storageClassification=%s writeReason=%s postBlocking=%d postUnclassified=%d postCanProceed=%s rollbackKey=%s",
		tostring(result.Passed),
		tostring(report.OldUnlockedSlots),
		tostring(report.OldMaxSlots),
		tostring(report.OldLegacyStorageUnlockedSlots),
		tostring(report.OldLegacyStorageMaxSlots),
		tostring(postStatus.Canonical and postStatus.Canonical.UnlockedSlots),
		tostring(postStatus.Canonical and postStatus.Canonical.MaxSlots),
		tostring(postStatus.LegacyQuickSlots and postStatus.LegacyQuickSlots.UnlockedSlots),
		tostring(postStatus.LegacyQuickSlots and postStatus.LegacyQuickSlots.MaxSlots),
		tostring(postStatus.LegacyStorage and postStatus.LegacyStorage.UnlockedSlots),
		tostring(postStatus.LegacyStorage and postStatus.LegacyStorage.MaxSlots),
		#writes,
		tostring(postStatus.RootsMatch == true),
		tostring(report.StorageClassification),
		tostring(writeReason or "none"),
		postCompare.BlockingCount or 0,
		postCompare.UnclassifiedCount or 0,
		tostring(postCompare.CanProceed == true),
		tostring(saveResult.Key or "")
	)
	return result
end

function CrewMigrationPlanner.ExecuteSampledMigrationWrite(source, previewReport, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return {
			Passed = false,
			NoGoReasons = { "player_source_required" },
			Summary = "sampledWrite passed=false noGo=player_source_required",
		}
	end

	local report = if typeof(previewReport) == "table" then previewReport.Report else nil
	local noGoReasons = getMigrationMutationNoGoReasons(options.Flags, true)
	if typeof(previewReport) ~= "table" or typeof(report) ~= "table" or previewReport.CanWritePreview ~= true then
		noGoReasons[#noGoReasons + 1] = "writepreview_not_clean"
	end
	if report and tonumber(report.UserId) ~= source.UserId then
		noGoReasons[#noGoReasons + 1] = "user_id_mismatch"
	end
	if typeof(previewReport) == "table" and typeof(previewReport.ProjectedCanonical) ~= "table" then
		noGoReasons[#noGoReasons + 1] = "projected_canonical_missing"
	end
	if #noGoReasons > 0 then
		return {
			Passed = false,
			NoGoReasons = noGoReasons,
			Summary = "sampledWrite passed=false noGo=" .. table.concat(noGoReasons, ","),
		}
	end

	local writeOk, writeReason, writes = writeCanonicalMigrationRoots(source, previewReport.ProjectedCanonical)
	local postCompare = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local passed = writeOk == true and postCompare.CanProceed == true
	local result = {
		Passed = passed,
		Writes = writes,
		PostCompare = postCompare,
		NoGoReasons = if writeOk == true then {} else { tostring(writeReason or "write_failed") },
	}
	result.Summary = string.format(
		"sampledWrite passed=%s writes=%d writeReason=%s postBlocking=%d postUnclassified=%d postCanProceed=%s",
		tostring(result.Passed),
		#writes,
		tostring(writeReason or "none"),
		postCompare.BlockingCount or 0,
		postCompare.UnclassifiedCount or 0,
		tostring(postCompare.CanProceed == true)
	)
	return result
end

function CrewMigrationPlanner.BuildSampledMigrationWritePreview(source, options)
	options = if typeof(options) == "table" then options else {}
	local compareReport = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		Snapshot = options.Snapshot,
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local previewReport = CrewMigrationPlanner.BuildMigrationWritePreviewReport(source, {
		ValidationStatus = options.ValidationStatus,
		CompareReport = compareReport,
		Flags = options.Flags,
	})
	return previewReport, compareReport
end

function CrewMigrationPlanner.SaveAndVerifySampledMigrationRollback(source, previewReport)
	local saveResult = CrewMigrationPlanner.SaveMigrationWritePreview(source, previewReport)
	if saveResult.Ok ~= true then
		return saveResult, nil
	end

	local loadResult = CrewMigrationPlanner.LoadMigrationWritePreview(source)
	local loadedRecord = loadResult.Record
	local loadedSnapshot = if typeof(loadedRecord) == "table" then loadedRecord.WritePreviewRollbackSnapshot else nil
	local expectedHash = previewReport and previewReport.Report and previewReport.Report.RollbackSnapshotHash
	local loadedHash = if typeof(loadedSnapshot) == "table" then hashStableValue(loadedSnapshot) else nil
	if loadResult.Ok ~= true or typeof(loadedSnapshot) ~= "table" or loadedHash ~= expectedHash then
		return {
			Ok = false,
			Reason = "rollback_snapshot_verify_failed",
			StoreName = AUDIT_DATA_STORE_NAME,
			Key = saveResult.Key,
		}, loadResult
	end

	return saveResult, loadResult
end

local function getLatestRollbackSnapshot(record)
	if typeof(record) ~= "table" then
		return nil, nil
	end
	if tostring(record.LatestRollbackKind or "") == "quick_slots_write_authority"
		and typeof(record.QuickSlotsWriteAuthorityRollbackSnapshot) == "table"
	then
		return record.QuickSlotsWriteAuthorityRollbackSnapshot, "quick_slots_write_authority"
	end
	if typeof(record.WritePreviewRollbackSnapshot) == "table" then
		return record.WritePreviewRollbackSnapshot, "canonical_migration_roots"
	end
	if typeof(record.Before) == "table" and typeof(record.Before.RollbackSnapshot) == "table" then
		return record.Before.RollbackSnapshot, "audit_before"
	end
	if typeof(record.QuickSlotsWriteAuthorityRollbackSnapshot) == "table" then
		return record.QuickSlotsWriteAuthorityRollbackSnapshot, "quick_slots_write_authority"
	end
	return nil, nil
end

function CrewMigrationPlanner.LoadMigrationRollbackStatus(source, options)
	local loadResult = CrewMigrationPlanner.LoadMigrationAudit(source, options)
	local snapshot, rollbackKind = getLatestRollbackSnapshot(loadResult.Record)
	return {
		Ok = loadResult.Ok,
		Reason = loadResult.Reason,
		StoreName = loadResult.StoreName,
		Key = loadResult.Key,
		Missing = loadResult.Ok == true and typeof(snapshot) ~= "table",
		Record = loadResult.Record,
		RollbackSnapshot = snapshot,
		RollbackKind = rollbackKind,
	}
end

function CrewMigrationPlanner.ExecuteMigrationRollbackLatest(source, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(source) ~= "Instance" or not source:IsA("Player") then
		return {
			Passed = false,
			NoGoReasons = { "player_source_required" },
			Summary = "rollbackLatest passed=false noGo=player_source_required",
		}
	end

	local loadResult = CrewMigrationPlanner.LoadMigrationRollbackStatus(source)
	local snapshot = loadResult.RollbackSnapshot
	local noGoReasons = getMigrationMutationNoGoReasons(options.Flags, false)
	if loadResult.Ok ~= true then
		noGoReasons[#noGoReasons + 1] = "rollback_snapshot_load_failed"
	end
	if typeof(snapshot) ~= "table" then
		noGoReasons[#noGoReasons + 1] = "rollback_snapshot_missing"
	end
	local metadata = snapshot and snapshot.Metadata or {}
	if tostring(metadata.ToolVersion or "") ~= MIGRATION_TOOL_VERSION then
		noGoReasons[#noGoReasons + 1] = "rollback_snapshot_version_invalid"
	end
	if tonumber(metadata.UserId) ~= source.UserId then
		noGoReasons[#noGoReasons + 1] = "rollback_snapshot_user_mismatch"
	end
	if tonumber(metadata.PlaceId) ~= game.PlaceId then
		noGoReasons[#noGoReasons + 1] = "rollback_snapshot_place_mismatch"
	end
	if tonumber(metadata.GameId) ~= game.GameId then
		noGoReasons[#noGoReasons + 1] = "rollback_snapshot_game_mismatch"
	end
	if snapshot and typeof(snapshot.Canonical) ~= "table" then
		noGoReasons[#noGoReasons + 1] = "rollback_canonical_roots_missing"
	end
	if #noGoReasons > 0 then
		return {
			Passed = false,
			LoadResult = loadResult,
			NoGoReasons = noGoReasons,
			Summary = "rollbackLatest passed=false noGo=" .. table.concat(noGoReasons, ","),
		}
	end

	local writeOk, writeReason, writes
	local quickSlotRollbackSnapshotStatuses = nil
	local postStatus = nil
	if loadResult.RollbackKind == "quick_slots_write_authority" then
		writeOk, writeReason, writes, quickSlotRollbackSnapshotStatuses = writeQuickSlotAuthorityRollbackRoots(source, snapshot)
	else
		writeOk, writeReason, writes = writeCanonicalMigrationRoots(source, snapshot.Canonical)
	end
	if loadResult.RollbackKind == "quick_slots_write_authority" then
		postStatus = CrewMigrationPlanner.BuildQuickSlotsWriteAuthorityStatus(source, {
			Flags = options.Flags,
		})
	end
	local postCompare = CrewMigrationPlanner.BuildMigrationCompareReport(source, {
		ValidationStatus = options.ValidationStatus,
		MaxValidationAgeSeconds = options.MaxValidationAgeSeconds,
	})
	local postNoGoReasons = {}
	if writeOk ~= true then
		postNoGoReasons[#postNoGoReasons + 1] = tostring(writeReason or "rollback_write_failed")
	elseif loadResult.RollbackKind == "quick_slots_write_authority" then
		if quickSlotStatusMatchesRollbackSnapshot(postStatus, quickSlotRollbackSnapshotStatuses) ~= true then
			postNoGoReasons[#postNoGoReasons + 1] = "quick_slots_rollback_snapshot_restore_mismatch"
		end
		if postStatus == nil or postStatus.RootsMatch ~= true then
			postNoGoReasons[#postNoGoReasons + 1] = "quick_slots_rollback_roots_mismatch"
		end
		if postStatus and postStatus.PrimaryContentsMatch ~= true then
			postNoGoReasons[#postNoGoReasons + 1] = "quick_slots_rollback_contents_mismatch"
		end
	end
	if postCompare.BlockingCount ~= 0 then
		postNoGoReasons[#postNoGoReasons + 1] = "blocking_mismatch"
	end
	if postCompare.UnclassifiedCount ~= 0 then
		postNoGoReasons[#postNoGoReasons + 1] = "unclassified_mismatch"
	end
	local passed = #postNoGoReasons == 0
	local result = {
		Passed = passed,
		LoadResult = loadResult,
		Writes = writes,
		PostStatus = postStatus,
		PostCompare = postCompare,
		NoGoReasons = postNoGoReasons,
	}
	result.Summary = string.format(
		"rollbackLatest passed=%s kind=%s writes=%d writeReason=%s postRootsMatch=%s postBlocking=%d postUnclassified=%d postCanProceed=%s",
		tostring(result.Passed),
		tostring(loadResult.RollbackKind or "unknown"),
		#writes,
		tostring(writeReason or "none"),
		tostring(postStatus == nil or postStatus.RootsMatch == true),
		postCompare.BlockingCount or 0,
		postCompare.UnclassifiedCount or 0,
		tostring(postCompare.CanProceed == true)
	)
	return result
end

function CrewMigrationPlanner.PrintSampledMigrationWriteReport(result)
	print("[CrewMigrationPlanner] migration " .. tostring(result and result.Summary or "sampledWrite unavailable"))
	for _, write in ipairs(result and result.Writes or {}) do
		print(string.format(
			"[CrewMigrationPlanner] sampledWriteRoot root=%s path=%s ok=%s reason=%s",
			tostring(write.Root),
			tostring(write.Path),
			tostring(write.Ok),
			tostring(write.Reason or "none")
		))
	end
	return result
end

function CrewMigrationPlanner.PrintMigrationRollbackReport(result)
	print("[CrewMigrationPlanner] migration " .. tostring(result and result.Summary or "rollback unavailable"))
	for _, write in ipairs(result and result.Writes or {}) do
		print(string.format(
			"[CrewMigrationPlanner] rollbackRoot root=%s path=%s ok=%s reason=%s",
			tostring(write.Root),
			tostring(write.Path),
			tostring(write.Ok),
			tostring(write.Reason or "none")
		))
	end
	return result
end

function CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityStatus(status)
	print("[CrewMigrationPlanner] " .. tostring(status and status.Summary or "quickSlotsWriteAuthority status unavailable"))
	return status
end

function CrewMigrationPlanner.PrintQuickSlotsWriteAuthorityResult(result)
	print("[CrewMigrationPlanner] migration " .. tostring(result and result.Summary or "quickSlotsWriteAuthoritySet unavailable"))
	for _, write in ipairs(result and result.Writes or {}) do
		print(string.format(
			"[CrewMigrationPlanner] quickSlotsWriteAuthorityRoot root=%s path=%s ok=%s reason=%s",
			tostring(write.Root),
			tostring(write.Path),
			tostring(write.Ok),
			tostring(write.Reason or "none")
		))
	end
	if result and result.PreStatus then
		print("[CrewMigrationPlanner] quickSlotsWriteAuthorityPre " .. tostring(result.PreStatus.Summary))
	end
	if result and result.PostStatus then
		print("[CrewMigrationPlanner] quickSlotsWriteAuthorityPost " .. tostring(result.PostStatus.Summary))
	end
	return result
end

return CrewMigrationPlanner
