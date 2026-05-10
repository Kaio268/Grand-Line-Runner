local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local DataManager = require(ServerScriptService.Data:WaitForChild("DataManager"))
local IndexCollectionService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("IndexCollectionService"))
local CrewMemberCanonicalReadGate = require(
	ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewMemberCanonicalReadGate")
)
local CrewInstanceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local Shorten = require(Modules:WaitForChild("Shorten"))

local Brainrots = CrewCatalog.GetLegacyConfig()
local VariantCfg = CrewCatalog.GetVariantConfig()
local IndexConfig = require(Configs:WaitForChild("Index"))

local DEVIL_FRUIT_BACKFILL_TIMEOUT = 30
local DEVIL_FRUIT_LEGACY_BACKFILL_DELAY = 5
local INDEX_DISPLAY_METADATA_REMOTE_NAME = "IndexDisplayMetadataRequest"
local INDEX_DISPLAY_METADATA_MAX_IDS = 300
local INDEX_DISPLAY_METADATA_CACHE_SECONDS = 30
local INDEX_DISPLAY_CANARY_LOG_THROTTLE_SECONDS = 60

local function findRemoteEventByName(parent, remoteName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == remoteName and child:IsA("RemoteEvent") then
			return child
		end
	end

	return nil
end

local function findRemoteFunctionByName(parent, remoteName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == remoteName and child:IsA("RemoteFunction") then
			return child
		end
	end

	return nil
end

local claimRemote = findRemoteEventByName(ReplicatedStorage, "ClaimIndexReward")
if not claimRemote then
	claimRemote = Instance.new("RemoteEvent")
	claimRemote.Name = "ClaimIndexReward"
	claimRemote.Parent = ReplicatedStorage
end

local indexDisplayMetadataRequest = findRemoteFunctionByName(ReplicatedStorage, INDEX_DISPLAY_METADATA_REMOTE_NAME)
if not indexDisplayMetadataRequest then
	indexDisplayMetadataRequest = Instance.new("RemoteFunction")
	indexDisplayMetadataRequest.Name = INDEX_DISPLAY_METADATA_REMOTE_NAME
	indexDisplayMetadataRequest.Parent = ReplicatedStorage
end

local VALID_BRAINROT_ITEM_IDS = {}
local SORTED_BRAINROT_ITEM_IDS = {}

for itemId, info in pairs(Brainrots) do
	if type(info) == "table" then
		local safeItemId = tostring(itemId)
		VALID_BRAINROT_ITEM_IDS[safeItemId] = true
		SORTED_BRAINROT_ITEM_IDS[#SORTED_BRAINROT_ITEM_IDS + 1] = safeItemId
	end
end

table.sort(SORTED_BRAINROT_ITEM_IDS)

local lastIndexDisplayMetadataLogByPlayer = setmetatable({}, { __mode = "k" })

local function getVariantInfo(variantKey)
	if variantKey == "Normal" or not variantKey then
		return (VariantCfg.Versions or {}).Normal or { Prefix = "", IncomeMult = 1 }
	end

	return (VariantCfg.Versions or {})[variantKey]
end

local function getVariantItemId(variantKey, baseName)
	if typeof(baseName) ~= "string" or baseName == "" then
		return nil
	end

	if variantKey == "Normal" or not variantKey then
		return baseName
	end

	local variantInfo = getVariantInfo(variantKey)
	local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
	return prefix .. baseName
end

local function normalizeVariantKey(variantKey)
	local candidate = tostring(variantKey or "")
	for _, supportedVariant in ipairs(VariantCfg.Order or { "Normal", "Golden", "Diamond" }) do
		if candidate == supportedVariant then
			return supportedVariant
		end
	end

	return "Normal"
end

local function parseVariantAndBaseName(fullName)
	local value = tostring(fullName or "")
	if value == "" then
		return "Normal", ""
	end

	for _, variantKey in ipairs(VariantCfg.Order or { "Normal", "Golden", "Diamond" }) do
		if variantKey ~= "Normal" then
			local variantInfo = getVariantInfo(variantKey)
			local prefix = tostring((variantInfo and variantInfo.Prefix) or (variantKey .. " "))
			if value:sub(1, #prefix) == prefix then
				return variantKey, value:sub(#prefix + 1)
			end
		end
	end

	return "Normal", value
end

local function resolveBrainrotItemId(storageName, baseName, variantKey)
	local storageNameValue = tostring(storageName or "")
	local baseNameValue = tostring(baseName or "")
	local normalizedVariant = normalizeVariantKey(variantKey)
	if baseNameValue == "" and storageNameValue ~= "" then
		local parsedVariant, parsedBaseName = parseVariantAndBaseName(storageNameValue)
		normalizedVariant = normalizeVariantKey(parsedVariant)
		baseNameValue = parsedBaseName
	end

	if baseNameValue == "" then
		return nil
	end

	local itemId = getVariantItemId(normalizedVariant, baseNameValue)
	if itemId and VALID_BRAINROT_ITEM_IDS[itemId] then
		return itemId
	end

	if storageNameValue ~= "" and VALID_BRAINROT_ITEM_IDS[storageNameValue] then
		return storageNameValue
	end

	return nil
end

local function markDiscoveredBrainrot(discovered, storageName, baseName, variantKey)
	local itemId = resolveBrainrotItemId(storageName, baseName, variantKey)
	if itemId then
		discovered[itemId] = true
	end
end

local function getRequestedBrainrotItemIds(requestedItemIds)
	local itemIds = {}
	local seen = {}

	if typeof(requestedItemIds) == "table" then
		for _, rawItemId in pairs(requestedItemIds) do
			if #itemIds >= INDEX_DISPLAY_METADATA_MAX_IDS then
				break
			end

			local itemId = tostring(rawItemId or "")
			if VALID_BRAINROT_ITEM_IDS[itemId] == true and seen[itemId] ~= true then
				seen[itemId] = true
				itemIds[#itemIds + 1] = itemId
			end
		end
	end

	if #itemIds > 0 then
		table.sort(itemIds)
		return itemIds
	end

	for _, itemId in ipairs(SORTED_BRAINROT_ITEM_IDS) do
		if #itemIds >= INDEX_DISPLAY_METADATA_MAX_IDS then
			break
		end

		itemIds[#itemIds + 1] = itemId
	end

	return itemIds
end

local function summarizeIndexDisplayValidation(result)
	local counts = result and result.BlockingCounts or {}
	return {
		valid = result ~= nil and result.ComparisonValid == true,
		validationValid = result ~= nil and result.ValidationValid == true,
		validationReason = result and result.ValidationReason or nil,
		validationAge = result and result.ValidationAgeSeconds or nil,
		blocking = counts.Total or 0,
		mismatch = counts.Mismatch or 0,
		stand = counts.Stand or 0,
		duplicate = counts.Duplicate or 0,
		unknown = counts.Unknown or 0,
		income = counts.BlockingIncomeMismatch or 0,
		compatibilityOnly = counts.CompatibilityOnly or 0,
		brookFallback = counts.BrookFallback or 0,
	}
end

local function summarizeModelPreviewValidation(result)
	local counts = result and result.BlockingCounts or {}
	return {
		valid = result ~= nil and result.ValidationValid == true,
		validationReason = result and result.ValidationReason or nil,
		validationAge = result and result.ValidationAgeSeconds or nil,
		blocking = counts.Total or 0,
		mismatch = counts.Mismatch or 0,
		stand = counts.Stand or 0,
		duplicate = counts.Duplicate or 0,
		unknown = counts.Unknown or 0,
		income = counts.BlockingIncomeMismatch or 0,
		compatibilityOnly = counts.CompatibilityOnly or 0,
		brookFallback = counts.BrookFallback or 0,
	}
end

local function buildIndexModelPreviewDescriptor(result)
	if typeof(result) ~= "table" then
		return nil
	end

	return {
		ModelName = tostring(result.ModelName or ""),
		ModelPath = tostring(result.ModelPath or ""),
		UsedCanonical = result.UsedCanonical == true,
		FallbackReason = result.FallbackReason,
		IsPreviewOnly = result.IsPreviewOnly == true,
		LegacyIdentity = tostring(result.LegacyIdentity or ""),
		Path = tostring(result.Path or ""),
		Source = tostring(result.Source or ""),
		CanonicalUnavailableReason = result.CanonicalUnavailableReason,
		LegacyUnavailableReason = result.LegacyUnavailableReason,
		Validation = summarizeModelPreviewValidation(result),
	}
end

local function addFallbackReason(reasonCounts, reason)
	local key = tostring(reason or "unknown")
	if key == "" or key == "none" then
		return
	end

	reasonCounts[key] = (reasonCounts[key] or 0) + 1
end

local function formatReasonCounts(reasonCounts)
	local parts = {}
	for reason, count in pairs(reasonCounts) do
		parts[#parts + 1] = tostring(reason) .. ":" .. tostring(count)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

local function logIndexDisplayMetadataSummary(player, result)
	if not player or not player:IsA("Player") or typeof(result) ~= "table" then
		return
	end

	local flags = result.Flags or {}
	if flags.CrewMemberCanaryDiagnosticsEnabled ~= true then
		return
	end

	local reasonSummary = formatReasonCounts(result.FallbackReasonCounts or {})
	local signature = table.concat({
		tostring(result.RequestedCount or 0),
		tostring(result.CanonicalDisplayUsedCount or 0),
		tostring(result.CanonicalModelPreviewUsedCount or 0),
		reasonSummary,
		formatReasonCounts(result.ModelPreviewFallbackReasonCounts or {}),
		tostring(flags.CrewMemberCanonicalReadEnabled),
		tostring(flags.CrewMemberCanaryIndexDisplayReadEnabled),
		tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
	}, "|")
	local now = os.clock()
	local last = lastIndexDisplayMetadataLogByPlayer[player]
	if typeof(last) == "table"
		and last.Signature == signature
		and (now - (tonumber(last.At) or 0)) < INDEX_DISPLAY_CANARY_LOG_THROTTLE_SECONDS
	then
		return
	end

	lastIndexDisplayMetadataLogByPlayer[player] = {
		At = now,
		Signature = signature,
	}

	print(string.format(
		"[IndexDisplayCanary] player=%s requested=%d canonicalDisplay=%d canonicalModelPreview=%d fallbackReasons={%s} modelPreviewFallbackReasons={%s} canonicalRead=%s indexDisplayRead=%s indexModelPreviewRead=%s inventoryModelPreviewRead=%s gameplayReads=%s",
		player.Name,
		result.RequestedCount or 0,
		result.CanonicalDisplayUsedCount or 0,
		result.CanonicalModelPreviewUsedCount or 0,
		reasonSummary,
		formatReasonCounts(result.ModelPreviewFallbackReasonCounts or {}),
		tostring(flags.CrewMemberCanonicalReadEnabled),
		tostring(flags.CrewMemberCanaryIndexDisplayReadEnabled),
		tostring(flags.CrewMemberCanaryIndexModelPreviewReadEnabled),
		tostring(flags.CrewMemberCanaryInventoryModelPreviewReadEnabled),
		tostring(flags.CrewMemberCanaryGameplayReadsEnabled)
	))
end

local function buildIndexDisplayMetadataResponse(player, requestedItemIds)
	if player.Parent ~= Players then
		return {
			Ready = false,
			Reason = "player_unavailable",
			Metadata = {},
		}
	end

	local itemIds = getRequestedBrainrotItemIds(requestedItemIds)
	local metadataById = {}
	local fallbackReasonCounts = {}
	local modelPreviewFallbackReasonCounts = {}
	local canonicalDisplayUsedCount = 0
	local canonicalModelPreviewUsedCount = 0
	local responseFlags = nil

	for _, itemId in ipairs(itemIds) do
		local metadata, result = CrewMemberCanonicalReadGate.ResolveIndexDisplayMetadata(player, itemId, {
			LogThrottleSeconds = 60,
			SkipSelectionLog = true,
		})
		responseFlags = responseFlags or result.Flags
		local modelPreviewResult = CrewMemberCanonicalReadGate.ResolveIndexModelPreviewDescriptor(player, itemId, {
			LogThrottleSeconds = 60,
			SkipLog = true,
		})
		responseFlags = responseFlags or modelPreviewResult.Flags

		local fallbackReason = result.DisplayReadFallbackReason or result.FallbackReason
		if result.DisplayReadUseCanonical == true then
			canonicalDisplayUsedCount += 1
		else
			addFallbackReason(fallbackReasonCounts, fallbackReason)
		end
		if modelPreviewResult.UsedCanonical == true then
			canonicalModelPreviewUsedCount += 1
		else
			addFallbackReason(modelPreviewFallbackReasonCounts, modelPreviewResult.FallbackReason)
		end

		metadataById[itemId] = {
			DisplayName = metadata and metadata.DisplayName or itemId,
			Rarity = metadata and metadata.Rarity or "",
			Render = metadata and metadata.Render or "",
			ModelPreview = buildIndexModelPreviewDescriptor(modelPreviewResult),
			Source = metadata and metadata.Source or "LegacyFallbackMissing",
			CanonicalDisplayUsed = result.DisplayReadUseCanonical == true,
			FallbackReason = fallbackReason,
			Validation = summarizeIndexDisplayValidation(result),
			CanonicalReadGlobal = result.Flags and result.Flags.CrewMemberCanonicalReadEnabled == true,
		}
	end

	local response = {
		Ready = true,
		Metadata = metadataById,
		RequestedCount = #itemIds,
		CanonicalDisplayUsedCount = canonicalDisplayUsedCount,
		CanonicalModelPreviewUsedCount = canonicalModelPreviewUsedCount,
		FallbackReasonCounts = fallbackReasonCounts,
		ModelPreviewFallbackReasonCounts = modelPreviewFallbackReasonCounts,
		ExpiresAfterSeconds = INDEX_DISPLAY_METADATA_CACHE_SECONDS,
		Flags = responseFlags or {},
	}

	logIndexDisplayMetadataSummary(player, response)
	return response
end

indexDisplayMetadataRequest.OnServerInvoke = buildIndexDisplayMetadataResponse

local function countUnlockedBrainrots(player)
	local discovered = {}
	local history = IndexCollectionService.GetDiscoveredCrewMemberHistory(player)

	if history then
		for itemId, isDiscovered in pairs(history) do
			if isDiscovered == true then
				discovered[tostring(itemId)] = true
			end
		end
	end

	local crewInventory = CrewInstanceService.GetCrewInventory(player)
	for _, instanceData in pairs(if typeof(crewInventory) == "table" and typeof(crewInventory.ById) == "table" then crewInventory.ById else {}) do
		if typeof(instanceData) == "table" then
			markDiscoveredBrainrot(
				discovered,
				tostring(instanceData.StorageName or ""),
				tostring(instanceData.BaseName or ""),
				tostring(instanceData.Variant or "")
			)
		end
	end

	local count = 0
	for _ in pairs(discovered) do
		count += 1
	end

	return count
end

local function humanizeToken(token)
	local value = tostring(token or "")
	value = value:gsub("(%l)(%u)", "%1 %2")
	value = value:gsub("(%a)(%d)", "%1 %2")
	value = value:gsub("(%d)(%a)", "%1 %2")
	value = value:gsub("_", " ")
	return value
end

local function formatRewardLabel(path)
	local pathValue = tostring(path or "")
	if pathValue:find("MoneyMult", 1, true) then
		return "Ship Income"
	end
	if pathValue:find("x2MoneyTime", 1, true) then
		return "x2 Money"
	end
	if pathValue:find("WalkSpeed", 1, true) then
		return "Speed Boost"
	end

	local parts = string.split(pathValue, ".")
	return humanizeToken(parts[#parts] or pathValue)
end

local function formatRewardAmount(path, amount)
	local numeric = tonumber(amount)
	if numeric == nil then
		return tostring(amount or "")
	end

	if tostring(path or ""):find("Mult", 1, true) then
		return ("+%d%%"):format(math.floor((numeric * 100) + 0.5))
	end

	if tostring(path or ""):find("Time", 1, true) then
		return Shorten.timeSuffix3(math.floor(numeric + 0.5))
	end

	return Shorten.withCommas(math.floor(numeric + 0.5))
end

local function buildRewardPopupTable(config)
	local rewardPopupTable = {}

	for path, reward in pairs((config and config.Rewards) or {}) do
		rewardPopupTable[#rewardPopupTable + 1] = {
			string.format("%s %s", formatRewardLabel(path), formatRewardAmount(path, reward and reward.Amount)),
			reward and reward.Icon or "",
		}
	end

	table.sort(rewardPopupTable, function(a, b)
		return tostring(a[1]) < tostring(b[1])
	end)

	return rewardPopupTable
end

local function sendClaimPopup(player, text, isError)
	local textColor = isError and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 255, 60)
	local strokeColor = Color3.fromRGB(0, 0, 0)
	PopUpModule:Server_SendPopUp(player, text, textColor, strokeColor, 3, isError == true)
end

local processing = {}

local function backfillDevilFruitIndex(player)
	task.spawn(function()
		if not DataManager:WaitUntilReady(player, DEVIL_FRUIT_BACKFILL_TIMEOUT) then
			warn(string.format("[Index] Failed to backfill Devil Fruit Index for %s: data not ready.", player.Name))
			return
		end

		local ok, result = pcall(IndexCollectionService.BackfillDevilFruitDiscoveries, player)
		if not ok then
			warn(string.format("[Index] Failed to backfill Devil Fruit Index for %s: %s", player.Name, tostring(result)))
		end
	end)
end

local function scheduleDevilFruitIndexBackfill(player)
	backfillDevilFruitIndex(player)

	-- Legacy safety pass: old sessions may briefly expose fruit tools before their
	-- saved Inventory.DevilFruits shape is repaired. Do not treat tools as a
	-- normal source of truth after this migration pass.
	task.delay(DEVIL_FRUIT_LEGACY_BACKFILL_DELAY, function()
		if player.Parent == Players then
			backfillDevilFruitIndex(player)
		end
	end)
end

claimRemote.OnServerEvent:Connect(function(player, questId)
	if processing[player] then
		return
	end

	processing[player] = true
	local q = tonumber(questId)

	local function finish()
		processing[player] = nil
	end

	local function sendClientClaimResult(success)
		claimRemote:FireClient(player, "ClaimResult", success == true, q)
	end

	if not q then
		sendClaimPopup(player, "That reward claim is invalid.", true)
		sendClientClaimResult(false)
		finish()
		return
	end

	local ok, err = pcall(function()
		local cfg = IndexConfig[q]
		if type(cfg) ~= "table" then
			sendClaimPopup(player, "That reward milestone doesn't exist.", true)
			sendClientClaimResult(false)
			return
		end

		local claimed = DataManager:GetValue(player, "IndexRewards." .. tostring(q))
		if claimed == true then
			sendClaimPopup(player, "You already claimed this milestone.", true)
			sendClientClaimResult(false)
			return
		end

		local unlocked = countUnlockedBrainrots(player)
		if unlocked < q then
			sendClaimPopup(player, "Discover more entries before claiming this reward.", true)
			sendClientClaimResult(false)
			return
		end

		for path, reward in pairs(cfg.Rewards or {}) do
			if typeof(path) == "string" and type(reward) == "table" then
				local amount = reward.Amount
				if typeof(amount) == "number" then
					local success, reason = DataManager:AddValue(player, path, amount)
					if success == false then
						error(string.format("failed to grant '%s' for quest %d: %s", path, q, tostring(reason)))
					end
				end
			end
		end

		local markedClaimed, reason = DataManager:SetValue(player, "IndexRewards." .. tostring(q), true)
		if markedClaimed == false then
			error(string.format("failed to mark quest %d claimed: %s", q, tostring(reason)))
		end

		sendClientClaimResult(true)
		sendClaimPopup(player, "Milestone reward claimed!", false)

		local rewardPopupTable = buildRewardPopupTable(cfg)
		if #rewardPopupTable > 0 then
			PopUpModule:Server_ShowReward(player, rewardPopupTable)
		end
	end)

	if not ok then
		warn(string.format("[IndexRewards] Failed to process claim %s for %s: %s", tostring(q), player.Name, tostring(err)))
		sendClaimPopup(player, "Couldn't claim that reward right now.", true)
		sendClientClaimResult(false)
	end

	finish()
end)

Players.PlayerAdded:Connect(function(player)
	scheduleDevilFruitIndexBackfill(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	scheduleDevilFruitIndexBackfill(player)
end

Players.PlayerRemoving:Connect(function(player)
	processing[player] = nil
end)
