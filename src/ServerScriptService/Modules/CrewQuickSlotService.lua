local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local CrewInventoryStacks = require(Modules:WaitForChild("Crew"):WaitForChild("CrewInventoryStacks"))
local CrewMemberInventoryConfig = require(Modules:WaitForChild("Configs"):WaitForChild("CrewMemberInventory"))
local CrewQuickSlotConfig = require(Modules:WaitForChild("Configs"):WaitForChild("CrewQuickSlots"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local CrewInventoryDerivedCache = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInventoryDerivedCache"))
local CrewProfileSchema = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewProfileSchema"))

local CrewQuickSlotService = {}

local QUICK_SLOT_PATH = "CrewMemberQuickSlots"
local PRODUCT_AUTHORITY_AUDIT_PATH = "CrewQuickSlotProductAuthorityAudit"
local CREW_MEMBER_QUICK_SLOT_REMOTE_NAME = "CrewMemberQuickSlotsRequest"
local PRODUCT_AUTHORITY_TOKEN_TTL_SECONDS = 15 * 60
local DATA_READY_TIMEOUT = 30
local CREW_MEMBER_INVENTORY_STORAGE_SLOTS = CrewMemberInventoryConfig.GetStorageSlots()
local INFO_COLOR = Color3.fromRGB(255, 229, 132)
local SUCCESS_COLOR = Color3.fromRGB(90, 255, 145)
local ERROR_COLOR = Color3.fromRGB(255, 86, 86)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local FULL_MESSAGE = "Crewmate inventory full. Free a slot before carrying more."

local dataManagerModule = nil
local crewStorageModule = nil
local crewMemberShadowWriterModule = nil
local crewMigrationPlannerModule = nil
local initialized = false
local productAuthorityTokensByUserId = {}
local productAuthorityTokenSequence = 0
local QUICK_SLOT_DEBUG = false

local function quickSlotDebug(message, ...)
	if QUICK_SLOT_DEBUG ~= true then
		return
	end

	local ok, formatted = pcall(string.format, "[CrewQuickSlots] " .. tostring(message), ...)
	print(ok and formatted or ("[CrewQuickSlots] " .. tostring(message)))
end

local function getDataManager()
	if dataManagerModule == nil then
		dataManagerModule = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
	end
	return dataManagerModule
end

local function getCrewStorage()
	if crewStorageModule == nil then
		crewStorageModule = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewStorage"))
	end
	return crewStorageModule
end

local function getCrewMemberShadowWriter()
	if crewMemberShadowWriterModule == nil then
		crewMemberShadowWriterModule = require(
			ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewMemberShadowWriter")
		)
	end
	return crewMemberShadowWriterModule
end

local function getCrewMigrationPlanner()
	if crewMigrationPlannerModule == nil then
		crewMigrationPlannerModule = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewMigrationPlanner"))
	end
	return crewMigrationPlannerModule
end

local function refreshCrewMemberShadow(player, reason)
	local flags = getCrewStorage().GetShadowFlags()
	if flags.CrewMemberShadowWriteEnabled ~= true then
		return nil
	end

	local dataManager = getDataManager()
	local profile = dataManager.TryGetProfile and dataManager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return nil
	end

	local ok, result = pcall(function()
		return getCrewMemberShadowWriter().RefreshAfterLegacyMutation(profile.Data, reason, {
			Player = player,
			Flags = flags,
		})
	end)

	if not ok then
		warn(string.format(
			"[CrewQuickSlots] CrewMember shadow refresh failed player=%s reason=%s error=%s",
			player and player.Name or "unknown",
			tostring(reason),
			tostring(result)
		))
	elseif result and result.StrictFailure == true then
		warn(string.format(
			"[CrewQuickSlots] CrewMember shadow refresh strict failure player=%s reason=%s",
			player and player.Name or "unknown",
			tostring(reason)
		))
	end

	return result
end

local function sendPopup(player, text, color, isError)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end
	quickSlotDebug(
		"popup sent player=%s text=%s",
		player.Name,
		tostring(text)
	)
	PopUpModule:Server_SendPopUp(player, text, color or INFO_COLOR, STROKE_COLOR, 3, isError == true)
end

local function waitForReady(player)
	local dataManager = getDataManager()
	if dataManager:IsReady(player) then
		return true
	end
	if dataManager.WaitUntilReady then
		return dataManager:WaitUntilReady(player, DATA_READY_TIMEOUT)
	end
	return false
end

local function copyProductAuthorityToken(token)
	if typeof(token) ~= "table" then
		return nil
	end
	return table.clone(token)
end

local function getProductAuthorityTokenKey(playerOrUserId)
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return playerOrUserId.UserId
	end
	local userId = tonumber(playerOrUserId)
	if userId == nil or userId <= 0 then
		return nil
	end
	return userId
end

local function isProductAuthorityTokenUsable(token, now)
	now = now or os.time()
	if typeof(token) ~= "table" then
		return false, "token_missing"
	end
	if tonumber(token.ExpiresAt) ~= nil and now > token.ExpiresAt then
		token.State = "expired"
		return false, "token_expired"
	end
	local state = tostring(token.State or "")
	if state == "pending" or state == "approved_unknown" or state == "receipt_seen" then
		return true, nil
	end
	return false, "token_" .. state
end

local function getProductAuthorityToken(playerOrUserId, productId)
	local userId = getProductAuthorityTokenKey(playerOrUserId)
	if userId == nil then
		return nil, nil, "invalid_user_id"
	end
	local token = productAuthorityTokensByUserId[userId]
	if typeof(token) ~= "table" then
		return nil, nil, "token_missing"
	end
	if tonumber(token.ProductId) ~= tonumber(productId) then
		return nil, token, "token_product_mismatch"
	end

	local usable, reason = isProductAuthorityTokenUsable(token)
	if usable ~= true then
		return nil, token, reason
	end
	return token, token, nil
end

local function createProductAuthorityToken(player, productId, options)
	options = if typeof(options) == "table" then options else {}
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil, "invalid_player"
	end
	productId = tonumber(productId)
	if not CrewQuickSlotConfig.IsUnlockProduct(productId) then
		return nil, "invalid_product_id"
	end

	productAuthorityTokenSequence += 1
	local now = os.time()
	local ttlSeconds = math.max(1, math.floor(tonumber(options.TtlSeconds) or PRODUCT_AUTHORITY_TOKEN_TTL_SECONDS))
	local token = {
		SchemaVersion = 1,
		TokenId = string.format("quickslot-product:%d:%d:%s", player.UserId, productAuthorityTokenSequence, HttpService:GenerateGUID(false)),
		UserId = player.UserId,
		PlayerName = player.Name,
		ProductId = productId,
		PromptSessionId = tostring(options.PromptSessionId or HttpService:GenerateGUID(false)),
		CreatedAt = now,
		CreatedClock = os.clock(),
		ExpiresAt = now + ttlSeconds,
		ExpiresClock = os.clock() + ttlSeconds,
		State = tostring(options.State or "pending"),
		Source = tostring(options.Source or "live_prompt"),
		IntendedTargetUnlockedSlots = tonumber(options.IntendedTargetUnlockedSlots),
		IntendedTargetMaxSlots = tonumber(options.IntendedTargetMaxSlots),
		PromptRequestedAt = tonumber(options.PromptRequestedAt) or now,
		PromptFinishedAt = nil,
		ReceiptSeenAt = nil,
		GlobalFlagAtReceipt = nil,
		ReceiptId = nil,
		FailureReason = nil,
	}
	productAuthorityTokensByUserId[player.UserId] = token
	return token, nil
end

local function markProductAuthorityToken(token, state, updates)
	if typeof(token) ~= "table" then
		return
	end
	token.State = tostring(state or token.State or "pending")
	if typeof(updates) == "table" then
		for key, value in pairs(updates) do
			token[key] = value
		end
	end
end

local function handleProductAuthorityPromptFinished(playerOrUserId, productId, wasPurchased)
	productId = tonumber(productId)
	if not CrewQuickSlotConfig.IsUnlockProduct(productId) then
		return
	end
	local userId = getProductAuthorityTokenKey(playerOrUserId)
	if userId == nil then
		return
	end
	local token = productAuthorityTokensByUserId[userId]
	if typeof(token) ~= "table" or tonumber(token.ProductId) ~= productId then
		return
	end
	local now = os.time()
	if wasPurchased == true then
		if token.State ~= "receipt_seen" and token.State ~= "granted" then
			markProductAuthorityToken(token, "approved_unknown", {
				PromptFinishedAt = now,
				WasPurchased = true,
			})
		end
	else
		markProductAuthorityToken(token, "cancelled", {
			PromptFinishedAt = now,
			WasPurchased = false,
		})
	end
end

local function normalizeSlotData(_slotData, options)
	options = if typeof(options) == "table" then options else {}
	local maxSlots = math.max(0, math.floor(tonumber(CrewQuickSlotConfig.MaxSlots) or 0))
	local unlockedSlots = maxSlots

	local normalized = {
		UnlockedSlots = unlockedSlots,
		MaxSlots = maxSlots,
	}
	if options.IncludeSchemaVersion == true then
		normalized.SchemaVersion = CrewProfileSchema.SchemaVersion
	end
	return normalized
end

local function readReplicatedQuickSlotData(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end

	local slotsFolder = player:FindFirstChild(QUICK_SLOT_PATH)
	if slotsFolder == nil then
		return nil
	end

	local function readValue(name)
		local child = slotsFolder:FindFirstChild(name)
		if child and child:IsA("ValueBase") then
			return child.Value
		end
		return nil
	end

	return {
		SchemaVersion = readValue("SchemaVersion"),
		UnlockedSlots = readValue("UnlockedSlots"),
		MaxSlots = readValue("MaxSlots"),
	}
end

local function normalizeRetainedSlotData(candidates, options)
	options = if typeof(options) == "table" then options else {}
	local retained = normalizeSlotData(nil)
	for _, candidate in ipairs(candidates or {}) do
		if candidate ~= nil then
			local normalized = normalizeSlotData(candidate)
			retained.MaxSlots = math.min(
				CrewQuickSlotConfig.MaxSlots,
				math.max(retained.MaxSlots, normalized.MaxSlots)
			)
			retained.UnlockedSlots = math.min(
				retained.MaxSlots,
				math.max(retained.UnlockedSlots, normalized.UnlockedSlots)
			)
		end
	end

	if options.IncludeSchemaVersion == true then
		retained.SchemaVersion = CrewProfileSchema.SchemaVersion
	end
	return retained
end

local function toLegacySlotData(slotData)
	return {
		UnlockedSlots = slotData.UnlockedSlots,
		MaxSlots = slotData.MaxSlots,
	}
end

local function quickSlotRootNeedsRewrite(root, includeSchemaVersion)
	if typeof(root) ~= "table" then
		return true
	end
	if root.UnlockedSlots ~= nil and typeof(root.UnlockedSlots) ~= "number" then
		return true
	end
	if root.MaxSlots ~= nil and typeof(root.MaxSlots) ~= "number" then
		return true
	end
	if includeSchemaVersion == true and root.SchemaVersion ~= nil and typeof(root.SchemaVersion) ~= "number" then
		return true
	end
	return false
end

local function quickSlotRootMatches(root, slotData, includeSchemaVersion)
	if typeof(root) ~= "table" then
		return false
	end
	if tonumber(root.UnlockedSlots) ~= slotData.UnlockedSlots then
		return false
	end
	if tonumber(root.MaxSlots) ~= slotData.MaxSlots then
		return false
	end
	if includeSchemaVersion == true and tonumber(root.SchemaVersion) ~= slotData.SchemaVersion then
		return false
	end
	return true
end

local function writeQuickSlotRoot(dataManager, player, path, slotData, includeSchemaVersion)
	local target = if includeSchemaVersion == true then slotData else toLegacySlotData(slotData)
	local current = dataManager:GetValue(player, path)
	local writes = {}
	local didWrite = false

	if quickSlotRootMatches(current, target, includeSchemaVersion) then
		return true, writes, didWrite
	end

	if quickSlotRootNeedsRewrite(current, includeSchemaVersion) then
		local ok, reason = dataManager:SetValue(player, path, target)
		writes[#writes + 1] = {
			Root = path,
			Ok = ok == true,
			Reason = reason,
		}
		return ok == true, writes, ok == true
	end

	local function writeField(fieldName)
		if current[fieldName] == target[fieldName] then
			return true
		end

		local ok, reason = dataManager:SetValue(player, path .. "." .. fieldName, target[fieldName])
		writes[#writes + 1] = {
			Root = path .. "." .. fieldName,
			Ok = ok == true,
			Reason = reason,
		}
		if ok == true then
			didWrite = true
		end
		return ok == true
	end

	local ok = writeField("UnlockedSlots")
		and writeField("MaxSlots")
		and (includeSchemaVersion ~= true or writeField("SchemaVersion"))
	return ok == true, writes, didWrite
end

local function writeQuickSlotRoots(dataManager, player, slotData)
	local canonicalOk, canonicalWrites, canonicalDidWrite = writeQuickSlotRoot(dataManager, player, QUICK_SLOT_PATH, slotData, true)
	local writes = {}
	for _, write in ipairs(canonicalWrites) do
		writes[#writes + 1] = write
	end
	return canonicalOk == true, writes, canonicalDidWrite == true
end

local function getCrewQuickEntries(player)
	return CrewInventoryDerivedCache.GetStacks(player)
end

local function countOccupiedStacks(player)
	return #getCrewQuickEntries(player)
end

local function parseCanGainArguments(crewMemberIdOrAmount, amountOrContext, context)
	if typeof(crewMemberIdOrAmount) == "string" and tonumber(crewMemberIdOrAmount) == nil then
		return crewMemberIdOrAmount, amountOrContext, context
	end
	return nil, crewMemberIdOrAmount, amountOrContext
end

function CrewQuickSlotService.EnsureSlots(player)
	local dataManager = getDataManager()
	local current = dataManager:GetValue(player, QUICK_SLOT_PATH)
	local replicatedCurrent = readReplicatedQuickSlotData(player)
	local normalized = normalizeRetainedSlotData({
		current,
		replicatedCurrent,
	}, {
		IncludeSchemaVersion = true,
	})
	local writeOk, writes, didWrite = writeQuickSlotRoots(dataManager, player, normalized)
	if writeOk ~= true then
		warn(string.format(
			"[CrewQuickSlots] slot root repair failed player=%s writes=%d",
			player and player.Name or "unknown",
			#writes
		))
	end

	if didWrite then
		refreshCrewMemberShadow(player, "quick_slot_update")
	end

	return normalized
end

function CrewQuickSlotService.GetUnlockedSlots(player)
	return CrewQuickSlotService.EnsureSlots(player).UnlockedSlots
end

function CrewQuickSlotService.GetMaxSlots(player)
	return CrewQuickSlotService.EnsureSlots(player).MaxSlots
end

function CrewQuickSlotService.GetInventoryStorageSlots(_player)
	return CREW_MEMBER_INVENTORY_STORAGE_SLOTS
end

function CrewQuickSlotService.CountOccupiedSlots(player)
	return countOccupiedStacks(player)
end

function CrewQuickSlotService.CanGainCrewMembers(player, crewMemberIdOrAmount, amountOrContext, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, 0, 0, 0
	end

	local crewMemberId, amount, resolvedContext = parseCanGainArguments(crewMemberIdOrAmount, amountOrContext, context)
	local requested = math.max(0, math.floor(tonumber(amount) or 0))
	if requested <= 0 then
		return true, CrewQuickSlotService.CountOccupiedSlots(player), CrewQuickSlotService.GetUnlockedSlots(player), CrewQuickSlotService.GetMaxSlots(player)
	end

	local slots = CrewQuickSlotService.EnsureSlots(player)
	local storageSlots = CrewQuickSlotService.GetInventoryStorageSlots(player)
	local stacks = getCrewQuickEntries(player)
	local occupied = 0
	local requiredSlots = 1
	local allowed = false
	local reason = "legacy_capacity_check"
	local targetCrewMemberId = tostring(crewMemberId or "")

	if targetCrewMemberId ~= "" then
		local fit = CrewInventoryStacks.CalculateIncomingFitFromStacks(stacks, targetCrewMemberId, requested, storageSlots)
		occupied = fit.OccupiedStacks
		requiredSlots = fit.RequiredNewStacks
		allowed = fit.Allowed == true
		reason = tostring(fit.Reason or "unknown")
		targetCrewMemberId = tostring(fit.CrewMemberId or targetCrewMemberId)
	else
		occupied = #stacks
		allowed = (occupied + requiredSlots) <= storageSlots
	end

	quickSlotDebug(
		"gain %s player=%s context=%s target=%s occupied=%d quickUnlocked=%d storageSlots=%d amount=%d requiredSlots=%d max=%d reason=%s",
		allowed and "allow" or "block",
		player.Name,
		tostring(resolvedContext or "unknown"),
		targetCrewMemberId,
		occupied,
		slots.UnlockedSlots,
		storageSlots,
		requested,
		requiredSlots,
		slots.MaxSlots,
		reason
	)

	return allowed, occupied, storageSlots, CREW_MEMBER_INVENTORY_STORAGE_SLOTS, reason
end

function CrewQuickSlotService.CanGainCrewMemberBatch(player, grants, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, 0, 0, 0
	end

	local slots = CrewQuickSlotService.EnsureSlots(player)
	local storageSlots = CrewQuickSlotService.GetInventoryStorageSlots(player)
	local fit = CrewInventoryStacks.CalculateBatchFitFromStacks(getCrewQuickEntries(player), grants, storageSlots)
	local allowed = fit.Allowed == true

	quickSlotDebug(
		"batchGain %s player=%s context=%s occupied=%d quickUnlocked=%d storageSlots=%d requested=%d requiredSlots=%d max=%d reason=%s",
		allowed and "allow" or "block",
		player.Name,
		tostring(context or "unknown"),
		tonumber(fit.OccupiedStacks) or 0,
		slots.UnlockedSlots,
		storageSlots,
		tonumber(fit.Requested) or 0,
		tonumber(fit.RequiredNewStacks) or 0,
		slots.MaxSlots,
		tostring(fit.Reason or "unknown")
	)

	return allowed,
		tonumber(fit.OccupiedStacks) or 0,
		storageSlots,
		CREW_MEMBER_INVENTORY_STORAGE_SLOTS,
		tostring(fit.Reason or "unknown")
end

function CrewQuickSlotService.CanInventoryFit(player, crewMemberInventory, context)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, 0, 0, 0, "invalid_player"
	end

	local slots = CrewQuickSlotService.EnsureSlots(player)
	local storageSlots = CrewQuickSlotService.GetInventoryStorageSlots(player)
	local occupiedStacks = #CrewInventoryStacks.BuildAvailableStacks(crewMemberInventory)
	local allowed = occupiedStacks <= storageSlots

	quickSlotDebug(
		"inventoryFit %s player=%s context=%s occupied=%d quickUnlocked=%d storageSlots=%d max=%d",
		allowed and "allow" or "block",
		player.Name,
		tostring(context or "unknown"),
		occupiedStacks,
		slots.UnlockedSlots,
		storageSlots,
		slots.MaxSlots
	)

	return allowed,
		occupiedStacks,
		storageSlots,
		CREW_MEMBER_INVENTORY_STORAGE_SLOTS,
		if allowed then "ok" else "crew_inventory_full"
end

function CrewQuickSlotService.CanInventoryFitOrNotify(player, crewMemberInventory, context)
	local allowed, occupiedStacks, unlockedSlots, maxSlots, reason =
		CrewQuickSlotService.CanInventoryFit(player, crewMemberInventory, context)
	if not allowed then
		CrewQuickSlotService.NotifyFull(player)
	end
	return allowed, occupiedStacks, unlockedSlots, maxSlots, reason
end

function CrewQuickSlotService.NotifyFull(player)
	sendPopup(player, FULL_MESSAGE, ERROR_COLOR, true)
end

function CrewQuickSlotService.CanGainOrNotify(player, crewMemberIdOrAmount, amountOrContext, context)
	local allowed, occupied, unlockedSlots, maxSlots, reason = CrewQuickSlotService.CanGainCrewMembers(
		player,
		crewMemberIdOrAmount,
		amountOrContext,
		context
	)
	if not allowed then
		CrewQuickSlotService.NotifyFull(player)
	end
	return allowed, occupied, unlockedSlots, maxSlots, reason
end

function CrewQuickSlotService.CanGainCrewMemberBatchOrNotify(player, grants, context)
	local allowed, occupied, unlockedSlots, maxSlots, reason = CrewQuickSlotService.CanGainCrewMemberBatch(player, grants, context)
	if not allowed then
		CrewQuickSlotService.NotifyFull(player)
	end
	return allowed, occupied, unlockedSlots, maxSlots, reason
end

function CrewQuickSlotService.GetCrewSlotIndex(player, crewMemberId)
	local canonicalCrewMemberId, info = CrewCatalog.ResolveCanonicalCrewMemberId(crewMemberId)
	if not info then
		return nil
	end

	for index, entry in ipairs(getCrewQuickEntries(player)) do
		if tostring(entry.Name) == canonicalCrewMemberId then
			return index
		end
	end

	return nil
end

function CrewQuickSlotService.CanEquipCrewMember(player, crewMemberId)
	local slotIndex = CrewQuickSlotService.GetCrewSlotIndex(player, crewMemberId)
	if not slotIndex then
		return false, nil, CrewQuickSlotService.GetUnlockedSlots(player)
	end

	local slots = CrewQuickSlotService.EnsureSlots(player)
	return slotIndex <= slots.UnlockedSlots, slotIndex, slots.UnlockedSlots
end

function CrewQuickSlotService.RequestUnlock(player, _requestedSlot)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, {
			Reason = "invalid_player",
		}
	end
	if not waitForReady(player) then
		sendPopup(player, "Player data is still loading. Try again in a moment.", ERROR_COLOR, true)
		return false, {
			Reason = "data_not_ready",
		}
	end

	local slots = CrewQuickSlotService.EnsureSlots(player)
	player:SetAttribute("PendingCrewQuickSlot", nil)
	sendPopup(player, "Crew Quick Slots are already fully unlocked.", INFO_COLOR, false)
	return false, {
		Reason = "already_max",
		AlreadyMax = true,
		PaidUnlocksEnabled = false,
		UnlockedSlots = slots.UnlockedSlots,
		MaxSlots = slots.MaxSlots,
	}
end

function CrewQuickSlotService.PromptUnlockForCrewMember(player, crewMemberId)
	local slotIndex = CrewQuickSlotService.GetCrewSlotIndex(player, crewMemberId)
	local slots = CrewQuickSlotService.EnsureSlots(player)
	if not slotIndex or slotIndex <= slots.UnlockedSlots then
		return false
	end

	sendPopup(player, "Crew Quick Slots are already fully unlocked.", INFO_COLOR, false)
	return false, {
		Reason = "already_max",
		AlreadyMax = true,
		SlotIndex = slotIndex,
		UnlockedSlots = slots.UnlockedSlots,
		MaxSlots = slots.MaxSlots,
	}
end

local function cloneValue(value)
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, child in pairs(value) do
		copy[key] = cloneValue(child)
	end
	return copy
end

local function getProductAudit(dataManager, player)
	local audit = dataManager:GetValue(player, PRODUCT_AUTHORITY_AUDIT_PATH)
	return if typeof(audit) == "table" then audit else {}
end

local function writeProductAudit(dataManager, player, auditRecord)
	local record = cloneValue(auditRecord)
	record.UpdatedAt = os.time()
	local ok, reason = dataManager:TrySetValue(player, PRODUCT_AUTHORITY_AUDIT_PATH .. ".Latest", record)
	return ok == true, reason
end

local function buildProductAuditRecord(status, receiptInfo, phase, extra)
	extra = if typeof(extra) == "table" then extra else {}
	local canonical = status and status.Canonical
	local legacyQuickSlots = status and status.LegacyQuickSlots
	return {
		SchemaVersion = 1,
		Kind = "product_quick_slot_write_authority",
		Phase = tostring(phase or "unknown"),
		ReceiptId = tostring(receiptInfo and receiptInfo.PurchaseId or extra.ReceiptId or ""),
		ProductId = tonumber(receiptInfo and receiptInfo.ProductId or extra.ProductId),
		PlayerId = tonumber(receiptInfo and receiptInfo.PlayerId or extra.PlayerId),
		TokenId = tostring(extra.TokenId or ""),
		TokenState = tostring(extra.TokenState or ""),
		TokenSource = tostring(extra.TokenSource or ""),
		PromptSessionId = tostring(extra.PromptSessionId or ""),
		TokenCreatedAt = tonumber(extra.TokenCreatedAt),
		TokenExpiresAt = tonumber(extra.TokenExpiresAt),
		PromptRequestedAt = tonumber(extra.PromptRequestedAt),
		PromptFinishedAt = tonumber(extra.PromptFinishedAt),
		ReceiptSeenAt = tonumber(extra.ReceiptSeenAt),
		GlobalFlagAtReceipt = extra.GlobalFlagAtReceipt == true,
		TokenUsed = extra.TokenUsed == true,
		RecoveryUsed = extra.RecoveryUsed == true,
		OldUnlockedSlots = tonumber(extra.OldUnlockedSlots),
		OldMaxSlots = tonumber(extra.OldMaxSlots),
		TargetUnlockedSlots = tonumber(extra.TargetUnlockedSlots),
		TargetMaxSlots = tonumber(extra.TargetMaxSlots),
		CanonicalUnlockedSlots = canonical and canonical.UnlockedSlots,
		CanonicalMaxSlots = canonical and canonical.MaxSlots,
		LegacyQuickSlotsUnlockedSlots = legacyQuickSlots and legacyQuickSlots.UnlockedSlots,
		LegacyQuickSlotsMaxSlots = legacyQuickSlots and legacyQuickSlots.MaxSlots,
		RootsMatch = status and status.RootsMatch == true,
		BlockingCount = tonumber(extra.BlockingCount) or 0,
		UnclassifiedCount = tonumber(extra.UnclassifiedCount) or 0,
		RootWrites = cloneValue(extra.RootWrites or {}),
		EntitlementAlreadyGranted = extra.EntitlementAlreadyGranted == true,
		Reason = tostring(extra.Reason or "none"),
	}
end

local function findPurchaseIdInCache(profile, purchaseId)
	if typeof(profile) ~= "table" or typeof(profile.Data) ~= "table" then
		return false
	end

	local purchaseIdCache = profile.Data.PurchaseIdCache
	if typeof(purchaseIdCache) ~= "table" then
		return false
	end
	return table.find(purchaseIdCache, purchaseId) ~= nil
end

local function purchaseIdCacheContains(cache, purchaseId)
	if typeof(cache) ~= "table" then
		return false
	end
	return table.find(cache, purchaseId) ~= nil
end

local function getProductTokenAuditFields(token, extra)
	extra = if typeof(extra) == "table" then extra else {}
	if typeof(token) ~= "table" then
		return {
			GlobalFlagAtReceipt = extra.GlobalFlagAtReceipt == true,
			TokenUsed = extra.TokenUsed == true,
			RecoveryUsed = extra.RecoveryUsed == true,
		}
	end
	return {
		TokenId = token.TokenId,
		TokenState = token.State,
		TokenSource = token.Source,
		PromptSessionId = token.PromptSessionId,
		TokenCreatedAt = token.CreatedAt,
		TokenExpiresAt = token.ExpiresAt,
		PromptRequestedAt = token.PromptRequestedAt,
		PromptFinishedAt = token.PromptFinishedAt,
		ReceiptSeenAt = token.ReceiptSeenAt,
		GlobalFlagAtReceipt = extra.GlobalFlagAtReceipt == true or token.GlobalFlagAtReceipt == true,
		TokenUsed = extra.TokenUsed == true,
		RecoveryUsed = extra.RecoveryUsed == true,
	}
end

local function withProductTokenAuditFields(base, tokenFields)
	base = if typeof(base) == "table" then base else {}
	if typeof(tokenFields) == "table" then
		for key, value in pairs(tokenFields) do
			base[key] = value
		end
	end
	return base
end

local function getProductAuthorityPreflightNoGoReasons(flags, status, compareReport, options)
	local reasons = {}
	options = if typeof(options) == "table" then options else {}
	flags = if typeof(flags) == "table" then flags else getCrewStorage().GetShadowFlags()
	local tokenAuthority = options.TokenAuthority == true

	if flags.CrewMemberProductQuickSlotWriteAuthorityEnabled ~= true and tokenAuthority ~= true then
		reasons[#reasons + 1] = "product_quick_slot_write_authority_disabled"
	end
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

	if compareReport == nil then
		reasons[#reasons + 1] = "compare_missing"
	elseif (compareReport.BlockingCount or 0) > 0 then
		reasons[#reasons + 1] = "blocking_mismatch"
	end
	if compareReport and (compareReport.UnclassifiedCount or 0) > 0 then
		reasons[#reasons + 1] = "unclassified_mismatch"
	end

	return reasons
end

local function processRetiredUnlockReceipt(player, productId, _dataManager)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return true, {
			RetiredProduct = true,
			ProductId = productId,
			Reason = "retired_product_disabled",
		}
	end

	local slots = CrewQuickSlotService.EnsureSlots(player)
	player:SetAttribute("PendingCrewQuickSlot", nil)
	print(string.format(
		"[CrewQuickSlots] retired quick-slot receipt consumed player=%s productId=%s unlockedSlots=%d maxSlots=%d",
		player.Name,
		tostring(productId),
		slots.UnlockedSlots,
		slots.MaxSlots
	))
	return true, {
		RetiredProduct = true,
		AlreadyMax = true,
		ProductId = productId,
		UnlockedSlots = slots.UnlockedSlots,
		MaxSlots = slots.MaxSlots,
		Reason = "retired_product_full_slots",
	}
end

local function processCanonicalUnlockReceipt(player, productId, dataManager)
	dataManager = dataManager or getDataManager()
	if not CrewQuickSlotConfig.IsUnlockProduct(productId) then
		if CrewQuickSlotConfig.IsRetiredUnlockProduct(productId) then
			return processRetiredUnlockReceipt(player, productId, dataManager)
		end
		return false, {
			Reason = "invalid_product_id",
		}
	end

	local slots = CrewQuickSlotService.EnsureSlots(player)
	if slots.UnlockedSlots >= slots.MaxSlots then
		print(string.format(
			"[CrewQuickSlots] purchase processed player=%s productId=%s result=already_max unlocked=%d",
			player.Name,
			tostring(productId),
			slots.UnlockedSlots
		))
		player:SetAttribute("PendingCrewQuickSlot", nil)
		return true, {
			AuthorityEnabled = false,
			AlreadyMax = true,
			UnlockedSlots = slots.UnlockedSlots,
			MaxSlots = slots.MaxSlots,
			Reason = "already_max",
		}
	end

	local grantedSlots = math.min(slots.UnlockedSlots + 1, slots.MaxSlots)
	local targetSlotData = {
		SchemaVersion = CrewProfileSchema.SchemaVersion,
		UnlockedSlots = grantedSlots,
		MaxSlots = slots.MaxSlots,
	}
	local rootsUpdated, writes, didWrite = writeQuickSlotRoots(dataManager, player, targetSlotData)
	player:SetAttribute("PendingCrewQuickSlot", nil)
	if rootsUpdated ~= true then
		return false, {
			AuthorityEnabled = false,
			UnlockedSlots = slots.UnlockedSlots,
			MaxSlots = slots.MaxSlots,
			TargetUnlockedSlots = grantedSlots,
			Reason = "canonical_quick_slot_write_failed",
			Writes = writes,
		}
	end
	if didWrite == true then
		refreshCrewMemberShadow(player, "quick_slot_unlock")
	end

	print(string.format(
		"[CrewQuickSlots] purchase processed player=%s productId=%s unlockedSlots=%d",
		player.Name,
		tostring(productId),
		grantedSlots
	))
	sendPopup(player, string.format("Crew Quick Slot %d unlocked.", grantedSlots), SUCCESS_COLOR, false)
	return true, {
		AuthorityEnabled = false,
		UnlockedSlots = grantedSlots,
		MaxSlots = slots.MaxSlots,
		Reason = "canonical_granted",
		Writes = writes,
	}
end

local function processProductAuthorityUnlockReceipt(player, productId, dataManager, receiptInfo, context)
	context = if typeof(context) == "table" then context else {}
	if not CrewQuickSlotConfig.IsUnlockProduct(productId) then
		return false, {
			Reason = "invalid_product_id",
		}
	end
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, {
			Reason = "invalid_player",
		}
	end
	if not dataManager:IsReady(player) then
		return false, {
			Reason = "profile_or_replica_unavailable",
		}
	end

	receiptInfo = if typeof(receiptInfo) == "table" then receiptInfo else {}
	local receiptId = tostring(receiptInfo.PurchaseId or "")
	local profile = dataManager:TryGetProfile(player)
	if typeof(profile) ~= "table" or typeof(profile.Data) ~= "table" then
		return false, {
			Reason = "profile_or_replica_unavailable",
		}
	end

	local audit = getProductAudit(dataManager, player)
	local latestAudit = if typeof(audit.Latest) == "table" then audit.Latest else nil
	local flags = getCrewStorage().GetShadowFlags()
	local globalFlagAtReceipt = flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true
	local token = if typeof(context.Token) == "table" then context.Token else nil
	if token ~= nil then
		markProductAuthorityToken(token, "receipt_seen", {
			ReceiptSeenAt = os.time(),
			ReceiptId = receiptId,
			GlobalFlagAtReceipt = globalFlagAtReceipt,
		})
	end
	local tokenAuditFields = getProductTokenAuditFields(token, {
		GlobalFlagAtReceipt = globalFlagAtReceipt,
		TokenUsed = context.TokenAuthority == true,
		RecoveryUsed = false,
	})
	local planner = getCrewMigrationPlanner()
	local status = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local compareReport = planner.BuildMigrationCompareReport(player)
	local preflightNoGoReasons = getProductAuthorityPreflightNoGoReasons(flags, status, compareReport, {
		TokenAuthority = context.TokenAuthority == true,
	})
	if #preflightNoGoReasons > 0 then
		return false, {
			AuthorityEnabled = true,
			TokenAuthority = context.TokenAuthority == true,
			Reason = "product_quick_slot_preflight_failed:" .. table.concat(preflightNoGoReasons, ","),
			Status = status,
			Compare = compareReport,
			NoGoReasons = preflightNoGoReasons,
		}
	end

	if receiptId ~= ""
		and latestAudit ~= nil
		and tostring(latestAudit.ReceiptId or "") == receiptId
		and latestAudit.EntitlementAlreadyGranted == true
		and status.RootsMatch == true
	then
		player:SetAttribute("PendingCrewQuickSlot", nil)
		if token ~= nil then
			markProductAuthorityToken(token, "granted", {
				GrantedAt = os.time(),
				ReceiptId = receiptId,
			})
		end
		return true, {
			AuthorityEnabled = true,
			AlreadyGranted = true,
			ReceiptId = receiptId,
			ProductId = productId,
			Status = status,
			Reason = "product_audit_already_granted",
		}
	end
	if receiptId ~= ""
		and latestAudit ~= nil
		and tostring(latestAudit.ReceiptId or "") == receiptId
		and status.RootsMatch == true
		and tonumber(latestAudit.TargetUnlockedSlots) == (status.Canonical and status.Canonical.UnlockedSlots)
		and tonumber(latestAudit.TargetMaxSlots) == (status.Canonical and status.Canonical.MaxSlots)
	then
		local recoveredAudit = buildProductAuditRecord(status, receiptInfo, "recovered_granted", withProductTokenAuditFields({
			ProductId = productId,
			OldUnlockedSlots = latestAudit.OldUnlockedSlots,
			OldMaxSlots = latestAudit.OldMaxSlots,
			TargetUnlockedSlots = latestAudit.TargetUnlockedSlots,
			TargetMaxSlots = latestAudit.TargetMaxSlots,
			RootWrites = latestAudit.RootWrites,
			EntitlementAlreadyGranted = true,
			Reason = "pending_audit_roots_already_at_target",
		}, tokenAuditFields))
		writeProductAudit(dataManager, player, recoveredAudit)
		player:SetAttribute("PendingCrewQuickSlot", nil)
		if token ~= nil then
			markProductAuthorityToken(token, "granted", {
				GrantedAt = os.time(),
				ReceiptId = receiptId,
			})
		end
		return true, {
			AuthorityEnabled = true,
			AlreadyGranted = true,
			RecoveredFromPendingAudit = true,
			ReceiptId = receiptId,
			ProductId = productId,
			Status = status,
			Audit = recoveredAudit,
			Reason = "pending_audit_roots_already_at_target",
		}
	end

	local currentUnlockedSlots = status.Canonical and status.Canonical.UnlockedSlots
	local currentMaxSlots = status.Canonical and status.Canonical.MaxSlots
	if currentUnlockedSlots == nil or currentMaxSlots == nil then
		return false, {
			AuthorityEnabled = true,
			Reason = "quick_slot_status_invalid",
			Status = status,
		}
	end
	if currentUnlockedSlots >= currentMaxSlots then
		local alreadyMaxAudit = buildProductAuditRecord(status, receiptInfo, "already_max", withProductTokenAuditFields({
			ProductId = productId,
			OldUnlockedSlots = currentUnlockedSlots,
			OldMaxSlots = currentMaxSlots,
			TargetUnlockedSlots = currentUnlockedSlots,
			TargetMaxSlots = currentMaxSlots,
			EntitlementAlreadyGranted = true,
			Reason = "already_max",
		}, tokenAuditFields))
		writeProductAudit(dataManager, player, alreadyMaxAudit)
		player:SetAttribute("PendingCrewQuickSlot", nil)
		if token ~= nil then
			markProductAuthorityToken(token, "granted", {
				GrantedAt = os.time(),
				ReceiptId = receiptId,
			})
		end
		return true, {
			AuthorityEnabled = true,
			AlreadyMax = true,
			ReceiptId = receiptId,
			ProductId = productId,
			Status = status,
			Audit = alreadyMaxAudit,
			Reason = "already_max",
		}
	end

	local targetUnlockedSlots = math.min(currentUnlockedSlots + 1, currentMaxSlots)
	local pendingAudit = buildProductAuditRecord(status, receiptInfo, "pending", withProductTokenAuditFields({
		ProductId = productId,
		OldUnlockedSlots = currentUnlockedSlots,
		OldMaxSlots = currentMaxSlots,
		TargetUnlockedSlots = targetUnlockedSlots,
		TargetMaxSlots = currentMaxSlots,
		EntitlementAlreadyGranted = false,
		Reason = "pending_product_write",
	}, tokenAuditFields))
	local auditOk, auditReason = writeProductAudit(dataManager, player, pendingAudit)
	if auditOk ~= true then
		if token ~= nil then
			markProductAuthorityToken(token, "failed", {
				FailureReason = "product_audit_pending_write_failed:" .. tostring(auditReason or "unknown_error"),
			})
		end
		return false, {
			AuthorityEnabled = true,
			Reason = "product_audit_pending_write_failed:" .. tostring(auditReason or "unknown_error"),
			Status = status,
			Audit = pendingAudit,
		}
	end

	local result = planner.ExecuteProductQuickSlotsWriteAuthoritySet(player, targetUnlockedSlots, {
		Flags = flags,
		ProductId = productId,
		PurchaseId = receiptId,
		ReceiptInfo = receiptInfo,
		CommandType = "product.quick_slot_unlock",
		AuthorityMode = "product.write_authority.quick_slots",
		TokenAuthority = context.TokenAuthority == true,
		TokenId = token and token.TokenId,
		TokenState = token and token.State,
		TokenSource = token and token.Source,
		GlobalFlagAtReceipt = globalFlagAtReceipt,
	})
	local postStatus = result and result.PostStatus or planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local postCompare = result and result.PostCompare
	local grantedAudit = buildProductAuditRecord(postStatus, receiptInfo, result and result.Passed == true and "granted" or "failed", withProductTokenAuditFields({
		ProductId = productId,
		OldUnlockedSlots = currentUnlockedSlots,
		OldMaxSlots = currentMaxSlots,
		TargetUnlockedSlots = targetUnlockedSlots,
		TargetMaxSlots = currentMaxSlots,
		RootWrites = result and result.Writes,
		BlockingCount = postCompare and postCompare.BlockingCount or 0,
		UnclassifiedCount = postCompare and postCompare.UnclassifiedCount or 0,
		EntitlementAlreadyGranted = result and result.Passed == true,
		Reason = result and result.Passed == true and "granted" or table.concat(result and result.NoGoReasons or {}, ","),
	}, tokenAuditFields))
	local finalAuditOk, finalAuditReason = writeProductAudit(dataManager, player, grantedAudit)
	if result == nil or result.Passed ~= true then
		if token ~= nil then
			markProductAuthorityToken(token, "failed", {
				FailureReason = "product_quick_slot_write_failed",
			})
		end
		return false, {
			AuthorityEnabled = true,
			Reason = "product_quick_slot_write_failed",
			Result = result,
			Status = postStatus,
			Audit = grantedAudit,
		}
	end
	if finalAuditOk ~= true then
		if token ~= nil then
			markProductAuthorityToken(token, "failed", {
				FailureReason = "product_audit_granted_write_failed:" .. tostring(finalAuditReason or "unknown_error"),
			})
		end
		return false, {
			AuthorityEnabled = true,
			Reason = "product_audit_granted_write_failed:" .. tostring(finalAuditReason or "unknown_error"),
			Result = result,
			Status = postStatus,
			Audit = grantedAudit,
		}
	end

	player:SetAttribute("PendingCrewQuickSlot", nil)
	if token ~= nil then
		markProductAuthorityToken(token, "granted", {
			GrantedAt = os.time(),
			ReceiptId = receiptId,
		})
	end
	print(string.format(
		"[CrewQuickSlots] product authority purchase processed player=%s productId=%s receipt=%s old=%d/%d new=%d/%d writes=%d rootsMatch=%s purchaseCached=%s",
		player.Name,
		tostring(productId),
		receiptId,
		currentUnlockedSlots,
		currentMaxSlots,
		postStatus.Canonical and postStatus.Canonical.UnlockedSlots or -1,
		postStatus.Canonical and postStatus.Canonical.MaxSlots or -1,
		result.Writes and #result.Writes or 0,
		tostring(postStatus.RootsMatch == true),
		tostring(findPurchaseIdInCache(profile, receiptId))
	))
	sendPopup(player, string.format("Crew Quick Slot %d unlocked.", targetUnlockedSlots), SUCCESS_COLOR, false)
	return true, {
		AuthorityEnabled = true,
		ReceiptId = receiptId,
		ProductId = productId,
		Result = result,
		Status = postStatus,
		Audit = grantedAudit,
		TokenUsed = context.TokenAuthority == true,
		Token = copyProductAuthorityToken(token),
		GlobalFlagAtReceipt = globalFlagAtReceipt,
		PurchaseCachedBeforeReturn = findPurchaseIdInCache(profile, receiptId),
		Reason = "product_authority_granted",
	}
end

function CrewQuickSlotService.ProcessUnlockReceipt(player, productId, dataManager, _receiptInfo)
	dataManager = dataManager or getDataManager()
	if not CrewQuickSlotConfig.IsUnlockProduct(productId) then
		if CrewQuickSlotConfig.IsRetiredUnlockProduct(productId) then
			return processRetiredUnlockReceipt(player, productId, dataManager)
		end
		return false, {
			Reason = "invalid_product_id",
		}
	end

	return processCanonicalUnlockReceipt(player, productId, dataManager)
end

function CrewQuickSlotService.CreateProductQuickSlotAuthorityToken(player, options)
	options = if typeof(options) == "table" then options else {}
	local productId = tonumber(options.ProductId or CrewQuickSlotConfig.ProductId)
	return createProductAuthorityToken(player, productId, options)
end

function CrewQuickSlotService.GetProductQuickSlotAuthorityTokenStatus(player)
	local productId = tonumber(CrewQuickSlotConfig.ProductId)
	local token, anyToken, reason = getProductAuthorityToken(player, productId)
	return {
		Token = copyProductAuthorityToken(token or anyToken),
		Usable = token ~= nil,
		Reason = tostring(reason or "none"),
	}
end

function CrewQuickSlotService.BuildProductQuickSlotReceiptStatus(player, receiptId, options)
	options = if typeof(options) == "table" then options else {}
	receiptId = tostring(receiptId or options.ReceiptId or "")
	local dataManager = getDataManager()
	local planner = getCrewMigrationPlanner()
	local flags = getCrewStorage().GetShadowFlags()
	local result = {
		Passed = false,
		ReceiptId = receiptId,
		ProductId = tonumber(options.ProductId or CrewQuickSlotConfig.ProductId),
		NoGoReasons = {},
	}

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		result.NoGoReasons = { "player_required" }
		result.Summary = "productQuickSlotsReceiptStatus passed=false noGo=player_required"
		return result
	end
	if receiptId == "" then
		result.NoGoReasons = { "receipt_id_required" }
		result.Summary = "productQuickSlotsReceiptStatus passed=false noGo=receipt_id_required"
		return result
	end
	if not dataManager:IsReady(player) then
		result.NoGoReasons = { "profile_or_replica_unavailable" }
		result.Summary = "productQuickSlotsReceiptStatus passed=false noGo=profile_or_replica_unavailable"
		return result
	end

	local profile = dataManager:TryGetProfile(player)
	if typeof(profile) ~= "table" or typeof(profile.Data) ~= "table" then
		result.NoGoReasons = { "profile_or_replica_unavailable" }
		result.Summary = "productQuickSlotsReceiptStatus passed=false noGo=profile_or_replica_unavailable"
		return result
	end

	local audit = getProductAudit(dataManager, player)
	local latestAudit = if typeof(audit.Latest) == "table" then audit.Latest else nil
	local status = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local compareReport = planner.BuildMigrationCompareReport(player)
	local purchaseIdCache = profile.Data.PurchaseIdCache
	local lastSavedCache = if typeof(profile.LastSavedData) == "table" then profile.LastSavedData.PurchaseIdCache else nil
	local rootWrites = latestAudit and latestAudit.RootWrites
	local rootWriteCount = if typeof(rootWrites) == "table" then #rootWrites else 0

	result.ProfilePurchaseCached = purchaseIdCacheContains(purchaseIdCache, receiptId)
	result.LastSavedPurchaseCached = purchaseIdCacheContains(lastSavedCache, receiptId)
	result.PurchaseCacheCount = if typeof(purchaseIdCache) == "table" then #purchaseIdCache else 0
	result.LastSavedPurchaseCacheCount = if typeof(lastSavedCache) == "table" then #lastSavedCache else 0
	result.Audit = cloneValue(latestAudit or {})
	result.AuditReceiptMatches = latestAudit ~= nil and tostring(latestAudit.ReceiptId or "") == receiptId
	result.AuditProductId = tonumber(latestAudit and latestAudit.ProductId)
	result.AuditPhase = tostring(latestAudit and latestAudit.Phase or "")
	result.AuditTokenUsed = latestAudit and latestAudit.TokenUsed == true
	result.AuditGlobalFlagAtReceipt = latestAudit and latestAudit.GlobalFlagAtReceipt == true
	result.AuditEntitlementAlreadyGranted = latestAudit and latestAudit.EntitlementAlreadyGranted == true
	result.AuditRootWriteCount = rootWriteCount
	result.Status = status
	result.Compare = compareReport
	result.Flags = cloneValue(flags)

	local passed = result.ProfilePurchaseCached == true
		and result.LastSavedPurchaseCached == true
		and result.AuditReceiptMatches == true
		and result.AuditProductId == result.ProductId
		and result.AuditPhase == "granted"
		and result.AuditTokenUsed == true
		and result.AuditGlobalFlagAtReceipt == false
		and result.AuditEntitlementAlreadyGranted == true
		and result.AuditRootWriteCount >= 1
		and status.RootsMatch == true
		and status.Canonical
		and status.Canonical.UnlockedSlots == CrewQuickSlotConfig.MaxSlots
		and status.LegacyQuickSlots
		and status.LegacyQuickSlots.UnlockedSlots == CrewQuickSlotConfig.MaxSlots
		and (compareReport.BlockingCount or 0) == 0
		and (compareReport.UnclassifiedCount or 0) == 0
		and flags.CrewMemberProductQuickSlotWriteAuthorityEnabled ~= true
		and flags.CrewMemberCanaryWriteAuthorityEnabled ~= true
		and flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled ~= true
		and flags.CrewMemberCanonicalReadEnabled ~= true
		and flags.CrewMemberCanaryGameplayReadsEnabled ~= true
		and flags.CrewMemberCanaryProfileMigrationWriteEnabled ~= true
	result.Passed = passed
	if passed ~= true then
		if result.ProfilePurchaseCached ~= true then
			result.NoGoReasons[#result.NoGoReasons + 1] = "profile_purchase_cache_missing"
		end
		if result.LastSavedPurchaseCached ~= true then
			result.NoGoReasons[#result.NoGoReasons + 1] = "last_saved_purchase_cache_missing"
		end
		if result.AuditReceiptMatches ~= true then
			result.NoGoReasons[#result.NoGoReasons + 1] = "audit_receipt_mismatch"
		end
		if result.AuditProductId ~= result.ProductId then
			result.NoGoReasons[#result.NoGoReasons + 1] = "audit_product_id_mismatch"
		end
		if result.AuditPhase ~= "granted" then
			result.NoGoReasons[#result.NoGoReasons + 1] = "audit_phase_not_granted"
		end
		if result.AuditTokenUsed ~= true then
			result.NoGoReasons[#result.NoGoReasons + 1] = "audit_token_not_used"
		end
		if result.AuditGlobalFlagAtReceipt ~= false then
			result.NoGoReasons[#result.NoGoReasons + 1] = "audit_global_flag_at_receipt_not_false"
		end
		if result.AuditEntitlementAlreadyGranted ~= true then
			result.NoGoReasons[#result.NoGoReasons + 1] = "audit_entitlement_not_granted"
		end
		if result.AuditRootWriteCount < 1 then
			result.NoGoReasons[#result.NoGoReasons + 1] = "audit_root_write_count_less_than_one"
		end
		if status.RootsMatch ~= true then
			result.NoGoReasons[#result.NoGoReasons + 1] = "quick_slot_roots_mismatch"
		end
		if compareReport.BlockingCount ~= 0 then
			result.NoGoReasons[#result.NoGoReasons + 1] = "blocking_mismatch"
		end
		if compareReport.UnclassifiedCount ~= 0 then
			result.NoGoReasons[#result.NoGoReasons + 1] = "unclassified_mismatch"
		end
	end

	result.Summary = string.format(
		"productQuickSlotsReceiptStatus passed=%s receipt=%s productId=%s profileCached=%s lastSavedCached=%s cacheCount=%d lastSavedCacheCount=%d auditReceiptMatches=%s auditPhase=%s tokenUsed=%s globalFlagAtReceipt=%s rootWrites=%d roots=%s/%s,%s/%s rootsMatch=%s blocking=%d unclassified=%d writeAuthority=%s quickSlotsWriteAuthority=%s productQuickSlotWriteAuthority=%s canonicalRead=%s gameplayReads=%s profileMigrationWrite=%s noGo=%s",
		tostring(result.Passed),
		tostring(result.ReceiptId),
		tostring(result.ProductId),
		tostring(result.ProfilePurchaseCached),
		tostring(result.LastSavedPurchaseCached),
		result.PurchaseCacheCount,
		result.LastSavedPurchaseCacheCount,
		tostring(result.AuditReceiptMatches),
		tostring(result.AuditPhase),
		tostring(result.AuditTokenUsed),
		tostring(result.AuditGlobalFlagAtReceipt),
		result.AuditRootWriteCount,
		tostring(status.Canonical and status.Canonical.UnlockedSlots),
		tostring(status.Canonical and status.Canonical.MaxSlots),
		tostring(status.LegacyQuickSlots and status.LegacyQuickSlots.UnlockedSlots),
		tostring(status.LegacyQuickSlots and status.LegacyQuickSlots.MaxSlots),
		tostring(status.RootsMatch == true),
		compareReport.BlockingCount or 0,
		compareReport.UnclassifiedCount or 0,
		tostring(flags.CrewMemberCanaryWriteAuthorityEnabled == true),
		tostring(flags.CrewMemberCanaryQuickSlotsWriteAuthorityEnabled == true),
		tostring(flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true),
		tostring(flags.CrewMemberCanonicalReadEnabled == true),
		tostring(flags.CrewMemberCanaryGameplayReadsEnabled == true),
		tostring(flags.CrewMemberCanaryProfileMigrationWriteEnabled == true),
		if #result.NoGoReasons > 0 then table.concat(result.NoGoReasons, ",") else "none"
	)
	return result
end

function CrewQuickSlotService.RunProductQuickSlotAuthorityCanary(player, options)
	options = if typeof(options) == "table" then options else {}
	local dataManager = getDataManager()
	local productId = tonumber(CrewQuickSlotConfig.ProductId)
	local planner = getCrewMigrationPlanner()
	local flags = getCrewStorage().GetShadowFlags()
	local result = {
		Passed = false,
		ProductId = productId,
		Writes = {},
		NoGoReasons = {},
	}

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		result.NoGoReasons = { "player_required" }
		result.Summary = "productQuickSlotsCanary passed=false noGo=player_required"
		return result
	end
	if not dataManager:IsReady(player) then
		result.NoGoReasons = { "profile_or_replica_unavailable" }
		result.Summary = "productQuickSlotsCanary passed=false noGo=profile_or_replica_unavailable"
		return result
	end
	if flags.CrewMemberProductQuickSlotWriteAuthorityEnabled ~= true then
		result.NoGoReasons = { "product_quick_slot_write_authority_disabled" }
		result.Summary = "productQuickSlotsCanary passed=false noGo=product_quick_slot_write_authority_disabled"
		return result
	end
	if productId == nil or productId <= 0 then
		result.NoGoReasons = { "product_id_missing" }
		result.Summary = "productQuickSlotsCanary passed=false noGo=product_id_missing"
		return result
	end

	local initialStatus = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local initialCompare = planner.BuildMigrationCompareReport(player)
	result.InitialStatus = initialStatus
	result.InitialCompare = initialCompare
	local initialNoGoReasons = getProductAuthorityPreflightNoGoReasons(flags, initialStatus, initialCompare)
	if #initialNoGoReasons > 0 then
		result.NoGoReasons = initialNoGoReasons
		result.Summary = "productQuickSlotsCanary passed=false noGo=" .. table.concat(initialNoGoReasons, ",")
		return result
	end

	local maxSlots = initialStatus.Canonical and initialStatus.Canonical.MaxSlots or CrewQuickSlotConfig.MaxSlots
	local startForReceipt = math.max(CrewQuickSlotConfig.DefaultUnlockedSlots, maxSlots - 1)
	if initialStatus.Canonical and initialStatus.Canonical.UnlockedSlots ~= startForReceipt then
		result.PrepareResult = planner.ExecuteProductQuickSlotsWriteAuthoritySet(player, startForReceipt, {
			Flags = flags,
			ProductId = productId,
			PurchaseId = "canary_prepare:" .. player.UserId .. ":" .. tostring(os.time()),
			CommandType = "product.quick_slot_canary_prepare",
			AuthorityMode = "product.write_authority.quick_slots.canary_prepare",
		})
		if result.PrepareResult.Passed ~= true then
			result.NoGoReasons = { "prepare_failed" }
			result.Summary = "productQuickSlotsCanary passed=false noGo=prepare_failed"
			return result
		end
	end

	local preReceiptStatus = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	result.PreReceiptStatus = preReceiptStatus
	local purchaseId = "crew_quick_slot_product_canary:" .. player.UserId .. ":" .. HttpService:GenerateGUID(false)
	local receiptInfo = {
		PlayerId = player.UserId,
		ProductId = productId,
		PurchaseId = purchaseId,
		CurrencySpent = 0,
		PlaceIdWherePurchased = game.PlaceId,
	}
	result.ReceiptId = purchaseId

	local receiptGrantCount = 0
	local firstOk, firstDecision, firstReason = pcall(function()
		return dataManager:RunProductReceiptIdempotencyCanary(player, receiptInfo, function()
			receiptGrantCount += 1
			local ok, receiptResult = processProductAuthorityUnlockReceipt(player, productId, dataManager, receiptInfo)
			result.FirstReceiptResult = receiptResult
			if ok ~= true then
				error("product_quick_slot_canary_receipt_failed:" .. tostring(receiptResult and receiptResult.Reason or "unknown_error"))
			end
		end)
	end)
	result.FirstReceiptOk = firstOk == true
	result.FirstReceiptDecision = firstDecision
	result.FirstReceiptReason = firstReason
	local postReceiptStatus = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local postReceiptCompare = planner.BuildMigrationCompareReport(player)
	result.PostReceiptStatus = postReceiptStatus
	result.PostReceiptCompare = postReceiptCompare

	local secondOk, secondDecision, secondReason = pcall(function()
		return dataManager:RunProductReceiptIdempotencyCanary(player, receiptInfo, function()
			receiptGrantCount += 1
			local ok, receiptResult = processProductAuthorityUnlockReceipt(player, productId, dataManager, receiptInfo)
			result.SecondReceiptResult = receiptResult
			if ok ~= true then
				error("product_quick_slot_canary_duplicate_failed:" .. tostring(receiptResult and receiptResult.Reason or "unknown_error"))
			end
		end)
	end)
	result.SecondReceiptOk = secondOk == true
	result.SecondReceiptDecision = secondDecision
	result.SecondReceiptReason = secondReason
	local postDuplicateStatus = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local postDuplicateCompare = planner.BuildMigrationCompareReport(player)
	result.PostDuplicateStatus = postDuplicateStatus
	result.PostDuplicateCompare = postDuplicateCompare

	local profile = dataManager:TryGetProfile(player)
	local purchaseCached = findPurchaseIdInCache(profile, purchaseId)
	local expectedUnlocked = math.min((preReceiptStatus.Canonical and preReceiptStatus.Canonical.UnlockedSlots or 0) + 1, maxSlots)
	local passed = firstOk == true
		and firstDecision == Enum.ProductPurchaseDecision.PurchaseGranted
		and firstReason == nil
		and secondOk == true
		and secondDecision == Enum.ProductPurchaseDecision.PurchaseGranted
		and secondReason == nil
		and purchaseCached == true
		and receiptGrantCount == 1
		and postReceiptStatus.RootsMatch == true
		and postDuplicateStatus.RootsMatch == true
		and postReceiptStatus.Canonical
		and postReceiptStatus.Canonical.UnlockedSlots == expectedUnlocked
		and postDuplicateStatus.Canonical
		and postDuplicateStatus.Canonical.UnlockedSlots == expectedUnlocked
		and postReceiptStatus.PrimaryContentsMatch == true
		and postDuplicateStatus.PrimaryContentsMatch == true
		and (postReceiptCompare.BlockingCount or 0) == 0
		and (postReceiptCompare.UnclassifiedCount or 0) == 0
		and (postDuplicateCompare.BlockingCount or 0) == 0
		and (postDuplicateCompare.UnclassifiedCount or 0) == 0
	result.Passed = passed
	if passed ~= true and #result.NoGoReasons == 0 then
		result.NoGoReasons = { "canary_assertion_failed" }
	end
	result.PurchaseCached = purchaseCached
	result.ReceiptGrantCount = receiptGrantCount
	result.ExpectedUnlockedSlots = expectedUnlocked
	result.Summary = string.format(
		"productQuickSlotsCanary passed=%s receipt=%s productId=%s initial=%s/%s preReceipt=%s/%s postReceipt=%s/%s postDuplicate=%s/%s firstDecision=%s secondDecision=%s receiptGrantCount=%d purchaseCached=%s rootsMatch=%s duplicateRootsMatch=%s postBlocking=%d postUnclassified=%d duplicateBlocking=%d duplicateUnclassified=%d noGo=%s",
		tostring(passed),
		tostring(purchaseId),
		tostring(productId),
		tostring(initialStatus.Canonical and initialStatus.Canonical.UnlockedSlots),
		tostring(initialStatus.Canonical and initialStatus.Canonical.MaxSlots),
		tostring(preReceiptStatus.Canonical and preReceiptStatus.Canonical.UnlockedSlots),
		tostring(preReceiptStatus.Canonical and preReceiptStatus.Canonical.MaxSlots),
		tostring(postReceiptStatus.Canonical and postReceiptStatus.Canonical.UnlockedSlots),
		tostring(postReceiptStatus.Canonical and postReceiptStatus.Canonical.MaxSlots),
		tostring(postDuplicateStatus.Canonical and postDuplicateStatus.Canonical.UnlockedSlots),
		tostring(postDuplicateStatus.Canonical and postDuplicateStatus.Canonical.MaxSlots),
		tostring(firstDecision),
		tostring(secondDecision),
		receiptGrantCount,
		tostring(purchaseCached),
		tostring(postReceiptStatus.RootsMatch == true),
		tostring(postDuplicateStatus.RootsMatch == true),
		postReceiptCompare.BlockingCount or 0,
		postReceiptCompare.UnclassifiedCount or 0,
		postDuplicateCompare.BlockingCount or 0,
		postDuplicateCompare.UnclassifiedCount or 0,
		if #result.NoGoReasons > 0 then table.concat(result.NoGoReasons, ",") else "none"
	)
	return result
end

function CrewQuickSlotService.RunDelayedProductQuickSlotAuthorityCanary(player, options)
	options = if typeof(options) == "table" then options else {}
	local dataManager = getDataManager()
	local productId = tonumber(options.ProductId or CrewQuickSlotConfig.ProductId)
	local planner = getCrewMigrationPlanner()
	local flags = getCrewStorage().GetShadowFlags()
	local result = {
		Passed = false,
		ProductId = productId,
		NoGoReasons = {},
	}

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		result.NoGoReasons = { "player_required" }
		result.Summary = "delayedProductQuickSlotsCanary passed=false noGo=player_required"
		return result
	end
	if not dataManager:IsReady(player) then
		result.NoGoReasons = { "profile_or_replica_unavailable" }
		result.Summary = "delayedProductQuickSlotsCanary passed=false noGo=profile_or_replica_unavailable"
		return result
	end
	if productId == nil or productId <= 0 then
		result.NoGoReasons = { "product_id_missing" }
		result.Summary = "delayedProductQuickSlotsCanary passed=false noGo=product_id_missing"
		return result
	end

	local preReceiptStatus = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	result.PreReceiptStatus = preReceiptStatus
	local token = if typeof(options.Token) == "table" then options.Token else nil
	if token == nil then
		token = createProductAuthorityToken(player, productId, {
			Source = "synthetic_delayed_receipt",
			IntendedTargetUnlockedSlots = preReceiptStatus.Canonical and math.min(
				(preReceiptStatus.Canonical.UnlockedSlots or 0) + 1,
				preReceiptStatus.Canonical.MaxSlots or CrewQuickSlotConfig.MaxSlots
			),
			IntendedTargetMaxSlots = preReceiptStatus.Canonical and preReceiptStatus.Canonical.MaxSlots,
		})
	end
	if typeof(token) ~= "table" then
		result.NoGoReasons = { "token_create_failed" }
		result.Summary = "delayedProductQuickSlotsCanary passed=false noGo=token_create_failed"
		return result
	end
	result.Token = copyProductAuthorityToken(token)

	flags = getCrewStorage().GetShadowFlags()
	result.GlobalFlagAtReceipt = flags.CrewMemberProductQuickSlotWriteAuthorityEnabled == true
	local purchaseId = "crew_quick_slot_product_delayed_canary:" .. player.UserId .. ":" .. HttpService:GenerateGUID(false)
	local receiptInfo = {
		PlayerId = player.UserId,
		ProductId = productId,
		PurchaseId = purchaseId,
		CurrencySpent = 0,
		PlaceIdWherePurchased = game.PlaceId,
	}
	result.ReceiptId = purchaseId

	local receiptGrantCount = 0
	local firstOk, firstDecision, firstReason = pcall(function()
		return dataManager:RunProductReceiptIdempotencyCanary(player, receiptInfo, function()
			receiptGrantCount += 1
			local ok, receiptResult = CrewQuickSlotService.ProcessUnlockReceipt(player, productId, dataManager, receiptInfo)
			result.FirstReceiptResult = receiptResult
			if ok ~= true then
				error("delayed_product_quick_slot_receipt_failed:" .. tostring(receiptResult and receiptResult.Reason or "unknown_error"))
			end
		end)
	end)
	result.FirstReceiptOk = firstOk == true
	result.FirstReceiptDecision = firstDecision
	result.FirstReceiptReason = firstReason
	local postReceiptStatus = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local postReceiptCompare = planner.BuildMigrationCompareReport(player)
	result.PostReceiptStatus = postReceiptStatus
	result.PostReceiptCompare = postReceiptCompare

	local secondOk, secondDecision, secondReason = pcall(function()
		return dataManager:RunProductReceiptIdempotencyCanary(player, receiptInfo, function()
			receiptGrantCount += 1
			local ok, receiptResult = CrewQuickSlotService.ProcessUnlockReceipt(player, productId, dataManager, receiptInfo)
			result.SecondReceiptResult = receiptResult
			if ok ~= true then
				error("delayed_product_quick_slot_duplicate_failed:" .. tostring(receiptResult and receiptResult.Reason or "unknown_error"))
			end
		end)
	end)
	result.SecondReceiptOk = secondOk == true
	result.SecondReceiptDecision = secondDecision
	result.SecondReceiptReason = secondReason
	local postDuplicateStatus = planner.BuildQuickSlotsWriteAuthorityStatus(player, {
		Flags = flags,
	})
	local postDuplicateCompare = planner.BuildMigrationCompareReport(player)
	result.PostDuplicateStatus = postDuplicateStatus
	result.PostDuplicateCompare = postDuplicateCompare

	local profile = dataManager:TryGetProfile(player)
	local purchaseCached = findPurchaseIdInCache(profile, purchaseId)
	local expectedUnlocked = preReceiptStatus.Canonical
		and math.min((preReceiptStatus.Canonical.UnlockedSlots or 0) + 1, preReceiptStatus.Canonical.MaxSlots or CrewQuickSlotConfig.MaxSlots)
		or nil
	local firstReceiptResult = result.FirstReceiptResult
	local audit = getProductAudit(dataManager, player)
	local latestAudit = if typeof(audit.Latest) == "table" then audit.Latest else nil
	local passed = firstOk == true
		and firstDecision == Enum.ProductPurchaseDecision.PurchaseGranted
		and firstReason == nil
		and secondOk == true
		and secondDecision == Enum.ProductPurchaseDecision.PurchaseGranted
		and secondReason == nil
		and purchaseCached == true
		and receiptGrantCount == 1
		and firstReceiptResult
		and firstReceiptResult.TokenUsed == true
		and firstReceiptResult.GlobalFlagAtReceipt == false
		and postReceiptStatus.RootsMatch == true
		and postDuplicateStatus.RootsMatch == true
		and postReceiptStatus.Canonical
		and postReceiptStatus.Canonical.UnlockedSlots == expectedUnlocked
		and postDuplicateStatus.Canonical
		and postDuplicateStatus.Canonical.UnlockedSlots == expectedUnlocked
		and (postReceiptCompare.BlockingCount or 0) == 0
		and (postReceiptCompare.UnclassifiedCount or 0) == 0
		and (postDuplicateCompare.BlockingCount or 0) == 0
		and (postDuplicateCompare.UnclassifiedCount or 0) == 0
	result.Passed = passed
	if passed ~= true and #result.NoGoReasons == 0 then
		result.NoGoReasons = { "delayed_canary_assertion_failed" }
	end
	result.PurchaseCached = purchaseCached
	result.ReceiptGrantCount = receiptGrantCount
	result.ExpectedUnlockedSlots = expectedUnlocked
	result.LatestAudit = latestAudit
	result.Summary = string.format(
		"delayedProductQuickSlotsCanary passed=%s receipt=%s productId=%s token=%s tokenUsed=%s globalFlagAtReceipt=%s preReceipt=%s/%s postReceipt=%s/%s postDuplicate=%s/%s firstDecision=%s secondDecision=%s receiptGrantCount=%d purchaseCached=%s postBlocking=%d postUnclassified=%d duplicateBlocking=%d duplicateUnclassified=%d noGo=%s",
		tostring(passed),
		tostring(purchaseId),
		tostring(productId),
		tostring(token.TokenId),
		tostring(firstReceiptResult and firstReceiptResult.TokenUsed == true),
		tostring(firstReceiptResult and firstReceiptResult.GlobalFlagAtReceipt == true),
		tostring(preReceiptStatus.Canonical and preReceiptStatus.Canonical.UnlockedSlots),
		tostring(preReceiptStatus.Canonical and preReceiptStatus.Canonical.MaxSlots),
		tostring(postReceiptStatus.Canonical and postReceiptStatus.Canonical.UnlockedSlots),
		tostring(postReceiptStatus.Canonical and postReceiptStatus.Canonical.MaxSlots),
		tostring(postDuplicateStatus.Canonical and postDuplicateStatus.Canonical.UnlockedSlots),
		tostring(postDuplicateStatus.Canonical and postDuplicateStatus.Canonical.MaxSlots),
		tostring(firstDecision),
		tostring(secondDecision),
		receiptGrantCount,
		tostring(purchaseCached),
		postReceiptCompare.BlockingCount or 0,
		postReceiptCompare.UnclassifiedCount or 0,
		postDuplicateCompare.BlockingCount or 0,
		postDuplicateCompare.UnclassifiedCount or 0,
		if #result.NoGoReasons > 0 then table.concat(result.NoGoReasons, ",") else "none"
	)
	return result
end

function CrewQuickSlotService.Init()
	if initialized then
		return
	end
	initialized = true

	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	local function getOrCreateRequestRemote(remoteName)
		local requestRemote = remotes:FindFirstChild(remoteName)
		if requestRemote and not requestRemote:IsA("RemoteEvent") then
			requestRemote:Destroy()
			requestRemote = nil
		end
		if not requestRemote then
			requestRemote = Instance.new("RemoteEvent")
			requestRemote.Name = remoteName
			requestRemote.Parent = remotes
		end
		return requestRemote
	end

	local crewMemberRequestRemote = getOrCreateRequestRemote(CREW_MEMBER_QUICK_SLOT_REMOTE_NAME)

	local function handleQuickSlotRequest(player, action, slotIndex)
		if action == "UnlockSlot" then
			CrewQuickSlotService.RequestUnlock(player, slotIndex)
		end
	end

	crewMemberRequestRemote.OnServerEvent:Connect(function(player, action, slotIndex)
		handleQuickSlotRequest(player, action, slotIndex)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerOrUserId, productId, wasPurchased)
		handleProductAuthorityPromptFinished(playerOrUserId, productId, wasPurchased)
	end)

	local function onPlayerAdded(player)
		task.spawn(function()
			if waitForReady(player) then
				local slots = CrewQuickSlotService.EnsureSlots(player)
				quickSlotDebug(
					"player=%s unlockedSlots=%d maxSlots=%d",
					player.Name,
					slots.UnlockedSlots,
					slots.MaxSlots
				)
			end
		end)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		productAuthorityTokensByUserId[player.UserId] = nil
	end)
end

return CrewQuickSlotService

