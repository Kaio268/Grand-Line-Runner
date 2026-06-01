local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Config = require(Modules:WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig"))
local MonetizationConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Monetization"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))

local CrewInstanceService = require(ServerScriptService.Modules:WaitForChild("CrewInstanceService"))
local CrewQuickSlotService = require(ServerScriptService.Modules:WaitForChild("CrewQuickSlotService"))
local PremiumCrewStealCooldowns = require(ServerScriptService.Modules:WaitForChild("PremiumCrewStealCooldowns"))
local PremiumCrewStealPricing = require(ServerScriptService.Modules:WaitForChild("PremiumCrewStealPricing"))
local RaidShieldService = require(ServerScriptService.Modules:WaitForChild("RaidShieldService"))
local CrewProtectionService = require(ServerScriptService.Modules:WaitForChild("CrewProtectionService"))
local RemoteGuard = require(ServerScriptService.Modules:WaitForChild("RemoteGuard"))
local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))

local PremiumCrewStealService = {}

local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local SUCCESS_COLOR = Color3.fromRGB(111, 255, 136)
local INFO_COLOR = Color3.fromRGB(255, 237, 50)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local warningRemote = nil
local confirmRemote = nil
local resultRemote = nil
local started = false
local configuredDataManager = nil

local pendingByBuyerUserId = {}
local pendingByToken = {}
local reservationsByStandKey = {}
local lastPromptAtByBuyer = {}
local receiptLocksByPurchaseId = {}
local successfulReceiptsByPurchaseId = {}

local RECEIPT_OUTCOME_SUCCESS = "success"
local RECEIPT_OUTCOME_RETRYABLE_FAILURE = "retryable_failure"

local OFFER_STATE_CREATED = "Created"
local OFFER_STATE_PROMPTING = "Prompting"
local OFFER_STATE_PROMPT_CANCELLED = "PromptCancelled"
local OFFER_STATE_PROMPT_PURCHASED = "PromptPurchased"
local OFFER_STATE_RECEIPT_PROCESSING = "ReceiptProcessing"
local OFFER_STATE_RETRYABLE_FAILURE = "RetryableFailure"
local OFFER_STATE_GRANTED = "Granted"

local RETRYABLE_RECEIPT_REASONS = {
	invalid_buyer = true,
	invalid_victim = true,
	reservation_expired = true,
	transfer_failed = true,
	no_pending_offer = true,
	offer_expired = true,
	reservation_missing = true,
	reservation_owner_mismatch = true,
	reservation_product_mismatch = true,
	reservation_target_mismatch = true,
	reservation_token_mismatch = true,
	target_changed = true,
	inactive_product = true,
	unsupported_rarity = true,
	quick_slots_full = true,
	victim_protected = true,
	target_protected = true,
	buyer_victim_cooldown = true,
	cooldown_persistence_unavailable = true,
	protection_persistence_unavailable = true,
	receipt_persistence_unavailable = true,
	receipt_success_marker_failed = true,
	hotbar_verification_failed = true,
	victim_stand_not_cleared = true,
	victim_runtime_refresh_failed = true,
	buyer_runtime_refresh_failed = true,
	invalid_success_marker = true,
	missing_success_marker = true,
	receipt_in_progress = true,
}

local function audit(eventName, payload)
	payload = if typeof(payload) == "table" then table.clone(payload) else {}
	payload.Event = tostring(eventName or "unknown")
	payload.At = os.time()

	local ok, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if ok then
		print("[PremiumCrewStealAudit] " .. encoded)
	else
		print("[PremiumCrewStealAudit] " .. tostring(payload.Event))
	end
end

local function getOfferAuditPayload(offer, extra)
	local payload = if typeof(extra) == "table" then table.clone(extra) else {}
	if typeof(offer) ~= "table" then
		return payload
	end

	payload.OfferToken = offer.Token
	payload.ReservationToken = offer.ReservationToken
	payload.BuyerUserId = offer.BuyerUserId
	payload.VictimUserId = offer.VictimUserId
	payload.StandName = offer.StandName
	payload.ProductId = offer.ProductId
	payload.BucketKey = offer.BucketKey
	payload.InstanceId = offer.InstanceId
	payload.State = offer.State
	return payload
end

local function setOfferState(offer, state, reason, extra)
	if typeof(offer) ~= "table" then
		return
	end

	local previousState = offer.State
	offer.State = tostring(state or OFFER_STATE_CREATED)
	offer.StateReason = reason
	offer.StateUpdatedAtClock = os.clock()
	offer.StateUpdatedAtUnix = os.time()

	audit("offer_state_changed", getOfferAuditPayload(offer, {
		PreviousState = previousState,
		NewState = offer.State,
		Reason = reason,
		Extra = extra,
	}))
end

local function getReceiptOutcomeForReason(reason)
	reason = tostring(reason or "unknown")
	if RETRYABLE_RECEIPT_REASONS[reason] then
		return RECEIPT_OUTCOME_RETRYABLE_FAILURE
	end
	return RECEIPT_OUTCOME_RETRYABLE_FAILURE
end

local function getFailureAuditKind(reason)
	reason = tostring(reason or "unknown")
	if string.find(reason, "reservation_", 1, true) == 1 then
		return "reservation_mismatch"
	elseif reason == "target_changed" then
		return "stale_target_mismatch"
	elseif reason == "quick_slots_full" then
		return "inventory_full_failure"
	elseif reason == "buyer_victim_cooldown" or reason == "cooldown_persistence_unavailable" then
		return "cooldown_failure"
	end
	return nil
end

local function auditReceiptFailure(reason, outcome, payload)
	payload = if typeof(payload) == "table" then table.clone(payload) else {}
	payload.Reason = tostring(reason or "unknown")
	payload.Outcome = tostring(outcome or RECEIPT_OUTCOME_RETRYABLE_FAILURE)

	audit("receipt_retryable_failure", payload)

	local failureKind = getFailureAuditKind(reason)
	if failureKind then
		audit(failureKind, payload)
	end
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemoteEvent(parent, remoteName)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = remoteName
		remote.Parent = parent
	end
	return remote
end

local function ensureRemotes()
	if warningRemote and confirmRemote and resultRemote then
		return warningRemote, confirmRemote, resultRemote
	end

	local remotes = getOrCreateRemotesFolder()
	warningRemote = getOrCreateRemoteEvent(remotes, Config.Remotes.WarningName)
	confirmRemote = getOrCreateRemoteEvent(remotes, Config.Remotes.ConfirmName)
	resultRemote = getOrCreateRemoteEvent(remotes, Config.Remotes.ResultName)
	return warningRemote, confirmRemote, resultRemote
end

local function sendPopup(player, message, color, isError)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
		return
	end

	pcall(function()
		PopUpModule:Server_SendPopUp(player, tostring(message or ""), color or INFO_COLOR, STROKE_COLOR, 3, isError == true)
	end)
end

local function sendResult(player, payload)
	ensureRemotes()
	if typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players then
		resultRemote:FireClient(player, payload)
	end
end

local function standKey(victimUserId, standName)
	return tostring(victimUserId or "") .. ":" .. tostring(standName or "")
end

local function getOfferTtl()
	return math.max(15, math.floor(tonumber(Config.Prompt.OfferTtlSeconds) or 90))
end

local function getReservationTtl()
	local reservationConfig = if typeof(Config.Reservations) == "table" then Config.Reservations else {}
	return math.max(15, math.floor(tonumber(reservationConfig.TimeoutSeconds) or getOfferTtl()))
end

local function isOfferExpired(offer)
	return typeof(offer) ~= "table" or (tonumber(offer.ExpiresAtClock) or 0) <= os.clock()
end

local function releaseReservationForOffer(offer)
	if typeof(offer) ~= "table" then
		return {
			Cleared = false,
			Reason = "invalid_offer",
		}
	end

	local result = {
		Cleared = false,
		Reason = "no_matching_reservation",
		ReservationKey = offer.ReservationKey,
		ReservationToken = offer.ReservationToken,
	}
	local key = offer.ReservationKey
	local reservation = key and reservationsByStandKey[key]
	if reservation and reservation.ReservationToken == offer.ReservationToken then
		reservationsByStandKey[key] = nil
		result.Cleared = true
		result.Reason = "cleared"
	elseif reservation then
		result.Reason = "token_mismatch"
	elseif not key then
		result.Reason = "no_reservation_key"
	end
	offer.ReservationKey = nil
	offer.ReservedByUserId = nil
	offer.ReservationToken = nil
	offer.ReservationExpiresAt = nil
	return result
end

local function clearOffer(offer)
	if typeof(offer) ~= "table" then
		return {
			Cleared = false,
			Reason = "invalid_offer",
		}
	end

	local cleanup = releaseReservationForOffer(offer)
	cleanup.RemovedBuyerPending = false
	cleanup.RemovedTokenPending = false
	if pendingByBuyerUserId[offer.BuyerUserId] == offer then
		pendingByBuyerUserId[offer.BuyerUserId] = nil
		cleanup.RemovedBuyerPending = true
	end
	if pendingByToken[offer.Token] == offer then
		pendingByToken[offer.Token] = nil
		cleanup.RemovedTokenPending = true
	end
	return cleanup
end

local function clearOfferWithAudit(offer, reason, extra)
	local payload = getOfferAuditPayload(offer, {
		Reason = tostring(reason or "unknown"),
		Extra = extra,
	})
	local cleanup = clearOffer(offer)
	payload.Cleanup = cleanup
	audit("offer_cleared", payload)
	return cleanup
end

local function clearOffersForPlayer(player)
	local userId = tonumber(player and player.UserId)
	if not userId then
		return
	end

	local toClear = {}
	for _, offer in pairs(pendingByToken) do
		if tonumber(offer.BuyerUserId) == userId or tonumber(offer.VictimUserId) == userId then
			table.insert(toClear, offer)
		end
	end
	for _, offer in ipairs(toClear) do
		clearOfferWithAudit(offer, "player_left")
	end
end

local function cleanupExpired()
	local nowClock = os.clock()
	for token, offer in pairs(pendingByToken) do
		if (tonumber(offer.ExpiresAtClock) or 0) <= nowClock then
			clearOfferWithAudit(offer, "offer_expired")
			pendingByToken[token] = nil
		end
	end
	for key, reservation in pairs(reservationsByStandKey) do
		if (tonumber(reservation.ReservationExpiresAt) or 0) <= nowClock then
			reservationsByStandKey[key] = nil
		end
	end
end

local function scheduleOfferExpiry(offer)
	task.delay(getOfferTtl() + 1, function()
		if pendingByToken[offer.Token] == offer and isOfferExpired(offer) then
			clearOfferWithAudit(offer, "offer_expired")
		end
	end)
end

local function getCrewDisplayName(storageName, instanceData)
	local displayInfo = CrewCatalog.GetDisplayInfo(storageName, instanceData)
	local displayName = tostring(displayInfo.DisplayName or "")
	if displayName ~= "" then
		return displayName
	end

	local info = CrewCatalog.GetInfoById(storageName)
	return tostring((info and (info.DisplayName or info.Name)) or storageName or "Crewmate")
end

local function isCaptainStandName(standName)
	local text = tostring(standName or "")
	return text == tostring(ShipSlotService.CaptainSlotKey or "Captain")
		or ShipSlotService.IsCaptainSlotName(text)
end

local function hasNormalSlot(activeShip, standName)
	for _, slotNumber in ipairs(ShipSlotService.GetAvailableSlotNumbers(activeShip)) do
		if tostring(slotNumber) == tostring(standName) then
			return true
		end
	end
	return false
end

local function getBuyerVictimCooldownMessage(remaining)
	local seconds = math.max(1, math.ceil(tonumber(remaining) or 1))
	if seconds >= 60 then
		return string.format("You already stole from this player recently. Try again in %d min.", math.ceil(seconds / 60))
	end
	return string.format("You already stole from this player recently. Try again in %d sec.", seconds)
end

local function reasonToMessage(reason, detail)
	if reason == "self_target" then
		return "You cannot steal from your own ship."
	elseif reason == "captain_slot" then
		return "Captain Slots cannot be stolen from."
	elseif reason == "empty_stand" or reason == "target_changed" or reason == "instance_mismatch" then
		return "That crewmate is no longer available to steal."
	elseif reason == "quick_slots_full" then
		return "Your crew hotbar is full."
	elseif reason == "hotbar_verification_failed" then
		return "Premium steal purchase is still processing your crew hotbar. Try again soon."
	elseif reason == "victim_stand_not_cleared"
		or reason == "victim_runtime_refresh_failed"
		or reason == "buyer_runtime_refresh_failed"
	then
		return "Premium steal purchase is still clearing the ship stand. Try again soon."
	elseif reason == "victim_protected" then
		return "This player is protected from premium steals."
	elseif reason == "target_protected" then
		return "That crewmate is protected from premium steals."
	elseif reason == "buyer_victim_cooldown" then
		return getBuyerVictimCooldownMessage(detail and detail.Remaining)
	elseif reason == "cooldown_persistence_unavailable"
		or reason == "protection_persistence_unavailable"
		or reason == "shield_persistence_unavailable"
	then
		return "Premium stealing is temporarily unavailable. Try again soon."
	elseif reason == "stand_reserved" or reason == "stand_locked" then
		return "That crewmate is already reserved for another premium steal purchase. Try again in a moment."
	elseif reason == "purchase_processing" then
		return "Your premium steal purchase is still processing. Try again in a moment."
	elseif reason == "product_not_available" or reason == "inactive_product" then
		return "Premium stealing is not available yet."
	elseif reason == "unsupported_rarity" then
		return "That crewmate rarity is not supported for premium stealing."
	elseif reason == "target_ship_missing" then
		return "That player's ship is not available right now."
	elseif reason == "invalid_stand" then
		return "That stand cannot be stolen from."
	end

	return "Premium steal could not be started."
end

local function buildSnapshot(buyer, victim, standName, options)
	options = if typeof(options) == "table" then options else {}

	if Config.Enabled ~= true then
		return nil, "feature_disabled"
	end
	if typeof(buyer) ~= "Instance" or not buyer:IsA("Player") or buyer.Parent ~= Players then
		return nil, "invalid_buyer"
	end
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") or victim.Parent ~= Players then
		return nil, "invalid_victim"
	end
	if buyer.UserId == victim.UserId then
		return nil, "self_target"
	end
	if isCaptainStandName(standName) then
		return nil, "captain_slot"
	end

	local normalizedStandName = ShipSlotService.NormalizeSlotNumber(standName)
	if not normalizedStandName then
		return nil, "invalid_stand"
	end

	local activeShip = ShipRuntimeService.GetActiveShip(victim)
	if not activeShip or not ShipRuntimeService.IsActiveShip(activeShip) then
		return nil, "target_ship_missing"
	end

	local ownerUserId = tonumber(activeShip:GetAttribute("OwnerUserId"))
	if ownerUserId ~= victim.UserId then
		return nil, "target_ship_owner_mismatch"
	end
	if not hasNormalSlot(activeShip, normalizedStandName) then
		return nil, "invalid_stand"
	end

	local standModel = ShipSlotService.GetSlot(activeShip, normalizedStandName)
	if not standModel or ShipSlotService.IsCaptainSlot(standModel) then
		return nil, "captain_slot"
	end

	local reservationKey = standKey(victim.UserId, normalizedStandName)
	local existingReservation = reservationsByStandKey[reservationKey]
	local nowClock = os.clock()
	if existingReservation and (tonumber(existingReservation.ReservationExpiresAt) or 0) > nowClock then
		local sameBuyer = tonumber(existingReservation.ReservedByUserId) == buyer.UserId
		local sameReservationToken = tostring(existingReservation.ReservationToken or "") == tostring(options.ReservationToken or "")
		if options.AllowOwnReservation ~= true or not sameBuyer or not sameReservationToken then
			return nil, "stand_reserved", {
				Remaining = math.max(0, (tonumber(existingReservation.ReservationExpiresAt) or nowClock) - nowClock),
			}
		end
	else
		reservationsByStandKey[reservationKey] = nil
	end

	local protected, protectedRemaining, protectionReason = RaidShieldService.IsPlayerProtected(victim)
	if protected == nil then
		return nil, "protection_persistence_unavailable", {
			Reason = protectionReason,
		}
	end
	if protected then
		return nil, "victim_protected", {
			Remaining = protectedRemaining,
		}
	end

	local fleetProtected, fleetRemaining, fleetReason = CrewProtectionService.IsFleetProtected(victim)
	if fleetProtected == nil then
		return nil, "protection_persistence_unavailable", {
			Reason = fleetReason,
		}
	end
	if fleetProtected then
		return nil, "victim_protected", {
			Remaining = fleetRemaining,
		}
	end

	local cooldownAllowed, cooldownReason, cooldownRemaining =
		PremiumCrewStealCooldowns.CanSteal(buyer.UserId, victim.UserId)
	if cooldownAllowed ~= true then
		return nil, cooldownReason, {
			Remaining = cooldownRemaining,
		}
	end

	local instanceId, instanceData = CrewInstanceService.EnsureStandInstance(victim, normalizedStandName)
	if typeof(instanceData) ~= "table" then
		return nil, "empty_stand"
	end
	local instanceProtected, instanceProtectedRemaining, instanceProtectionReason =
		CrewProtectionService.IsInstanceProtected(victim, instanceId)
	if instanceProtected == nil then
		return nil, "protection_persistence_unavailable", {
			Reason = instanceProtectionReason,
		}
	end
	if instanceProtected then
		return nil, "target_protected", {
			Remaining = instanceProtectedRemaining,
		}
	end
	if CrewInstanceService.IsTutorialRewardProtected(victim, instanceData) then
		return nil, "target_protected_tutorial_reward"
	end
	if tostring(instanceData.AssignedStand or "") ~= normalizedStandName then
		return nil, "target_changed"
	end

	local storageName = tostring(instanceData.CrewMemberId or instanceData.StorageName or "")
	if storageName == "" then
		return nil, "target_changed"
	end

	if options.CheckCapacity ~= false then
		local canGain = CrewQuickSlotService.CanGainOrNotify(
			buyer,
			storageName,
			1,
			"PremiumCrewSteal:" .. tostring(normalizedStandName)
		)
		if canGain ~= true then
			return nil, "quick_slots_full"
		end
	end

	local rarity, rarityReason = PremiumCrewStealPricing.NormalizeRarity(instanceData.Rarity)
	if not rarity then
		return nil, rarityReason or "unsupported_rarity", {
			RawRarity = instanceData.Rarity,
		}
	end

	local variant = PremiumCrewStealPricing.NormalizeVariant(instanceData.Variant)
	local level = math.max(1, math.floor(tonumber(instanceData.Level) or 1))
	local bucket, desiredPrice, pricingDetail = PremiumCrewStealPricing.GetBucket({
		Rarity = rarity,
		Variant = variant,
		Level = level,
	})
	if desiredPrice == nil then
		return nil, tostring(pricingDetail and pricingDetail.Reason or "unsupported_rarity"), pricingDetail
	end

	return {
		VictimUserId = victim.UserId,
		VictimName = victim.Name,
		StandName = normalizedStandName,
		StandModel = standModel,
		InstanceId = tostring(instanceId or ""),
		StorageName = storageName,
		DisplayName = getCrewDisplayName(storageName, instanceData),
		Rarity = rarity,
		Variant = variant,
		Level = level,
		BucketKey = tostring(bucket and bucket.Key or ""),
		PriceRobux = tonumber(bucket and bucket.PriceRobux) or desiredPrice,
		DesiredPriceRobux = desiredPrice,
		ProductId = tonumber(bucket and bucket.ProductId) or 0,
		Pricing = pricingDetail,
	}, nil, nil
end

local function validateOfferAgainstLiveTarget(offer, buyer)
	local victim = Players:GetPlayerByUserId(tonumber(offer.VictimUserId) or 0)
	if not victim then
		return nil, "invalid_victim"
	end

	local snapshot, reason, detail = buildSnapshot(buyer, victim, offer.StandName, {
		AllowOwnReservation = true,
		ReservationToken = offer.ReservationToken,
		CheckCapacity = true,
	})
	if not snapshot then
		return nil, reason, detail
	end

	local expectedFields = {
		"InstanceId",
		"StorageName",
		"Rarity",
		"Variant",
		"Level",
		"BucketKey",
		"PriceRobux",
		"ProductId",
	}

	for _, field in ipairs(expectedFields) do
		if tostring(snapshot[field]) ~= tostring(offer[field]) then
			return nil, "target_changed", {
				Field = field,
				Expected = offer[field],
				Actual = snapshot[field],
			}
		end
	end

	local configuredBucket = Config.GetBucketForProductId(offer.ProductId)
	if not Config.IsProductBucketActive(configuredBucket) then
		return nil, "inactive_product"
	end
	if not MonetizationConfig.CanPromptDeveloperProduct(offer.ProductId) then
		return nil, "inactive_product"
	end

	return snapshot, nil, nil
end

local function reserveOfferForPurchase(offer)
	local key = standKey(offer.VictimUserId, offer.StandName)
	local nowClock = os.clock()
	local existingReservation = reservationsByStandKey[key]
	if existingReservation
		and (tonumber(existingReservation.ReservationExpiresAt) or 0) > nowClock
		and existingReservation.ReservationToken ~= offer.ReservationToken
	then
		return false, "stand_reserved", {
			Remaining = math.max(0, (tonumber(existingReservation.ReservationExpiresAt) or nowClock) - nowClock),
		}
	end

	local reservationToken = tostring(offer.ReservationToken or "")
	if reservationToken == "" then
		reservationToken = HttpService:GenerateGUID(false)
	end

	local reservationExpiresAt = nowClock + getReservationTtl()
	offer.ReservedByUserId = offer.BuyerUserId
	offer.ReservationToken = reservationToken
	offer.ReservationExpiresAt = reservationExpiresAt
	offer.ReservationKey = key
	offer.ExpiresAtClock = reservationExpiresAt
	offer.ExpiresAtUnix = os.time() + math.max(1, math.ceil(reservationExpiresAt - nowClock))

	reservationsByStandKey[key] = {
		ReservedByUserId = offer.BuyerUserId,
		ReservationToken = reservationToken,
		ReservationExpiresAt = reservationExpiresAt,
		VictimUserId = offer.VictimUserId,
		StandName = offer.StandName,
		InstanceId = offer.InstanceId,
		ProductId = offer.ProductId,
		BucketKey = offer.BucketKey,
	}
	scheduleOfferExpiry(offer)
	return true, nil
end

local function validateReservationForReceipt(offer, buyer)
	if typeof(offer) ~= "table" then
		return false, "no_pending_offer"
	end
	if typeof(buyer) ~= "Instance" or not buyer:IsA("Player") or buyer.Parent ~= Players then
		return false, "invalid_buyer"
	end
	if tonumber(offer.ReservedByUserId) ~= buyer.UserId then
		return false, "reservation_owner_mismatch"
	end

	local reservationToken = tostring(offer.ReservationToken or "")
	if reservationToken == "" then
		return false, "reservation_missing"
	end

	local key = offer.ReservationKey or standKey(offer.VictimUserId, offer.StandName)
	local reservation = reservationsByStandKey[key]
	if not reservation then
		return false, "reservation_missing"
	end
	if reservation.ReservationToken ~= reservationToken then
		return false, "reservation_token_mismatch"
	end
	if tonumber(reservation.ReservedByUserId) ~= buyer.UserId then
		return false, "reservation_owner_mismatch"
	end
	if tonumber(reservation.ProductId) ~= tonumber(offer.ProductId) then
		return false, "reservation_product_mismatch"
	end
	if tostring(reservation.InstanceId or "") ~= tostring(offer.InstanceId or "") then
		return false, "reservation_target_mismatch"
	end
	if (tonumber(reservation.ReservationExpiresAt) or 0) <= os.clock() then
		return false, "reservation_expired"
	end

	return true, nil
end

local function verifyBuyerHotbarGrant(buyer, buyerInstanceId, expectedStorageName)
	local normalizedInstanceId = tostring(buyerInstanceId or "")
	if normalizedInstanceId == "" then
		return false, "hotbar_verification_failed", {
			Stage = "missing_instance_id",
		}
	end

	local resolvedInstanceId, instanceData, inventory = CrewInstanceService.GetInstance(buyer, normalizedInstanceId)
	if not resolvedInstanceId or typeof(instanceData) ~= "table" or typeof(inventory) ~= "table" then
		return false, "hotbar_verification_failed", {
			Stage = "missing_inventory_instance",
			BuyerInstanceId = normalizedInstanceId,
		}
	end

	local assignedStand = tostring(instanceData.AssignedStand or "")
	if assignedStand ~= "" then
		return false, "hotbar_verification_failed", {
			Stage = "assigned_stand",
			BuyerInstanceId = normalizedInstanceId,
			AssignedStand = assignedStand,
		}
	end

	local expected = tostring(expectedStorageName or "")
	if expected ~= "" then
		local actualStorage = tostring(instanceData.StorageName or "")
		local actualCrewMemberId = tostring(instanceData.CrewMemberId or "")
		local actualLegacyStorage = tostring(instanceData.LegacyStorageName or "")
		if actualStorage ~= expected and actualCrewMemberId ~= expected and actualLegacyStorage ~= expected then
			return false, "hotbar_verification_failed", {
				Stage = "storage_mismatch",
				BuyerInstanceId = normalizedInstanceId,
				ExpectedStorageName = expected,
				ActualStorageName = actualStorage,
				ActualCrewMemberId = actualCrewMemberId,
				ActualLegacyStorageName = actualLegacyStorage,
			}
		end
	end

	local unlockedSlots = CrewQuickSlotService.GetUnlockedSlots(buyer)
	local assignedSlotIndex = CrewQuickSlotService.GetInstanceSlot(buyer, resolvedInstanceId)
	if assignedSlotIndex == nil then
		return false, "hotbar_verification_failed", {
			Stage = "missing_quick_slot_assignment",
			BuyerInstanceId = normalizedInstanceId,
			UnlockedSlots = unlockedSlots,
		}
	end

	if assignedSlotIndex > unlockedSlots then
		return false, "hotbar_verification_failed", {
			Stage = "outside_unlocked_hotbar",
			BuyerInstanceId = normalizedInstanceId,
			SlotIndex = assignedSlotIndex,
			UnlockedSlots = unlockedSlots,
		}
	end

	return true, nil, {
		BuyerInstanceId = tostring(resolvedInstanceId),
		SlotIndex = assignedSlotIndex,
		UnlockedSlots = unlockedSlots,
	}
end

local function promptProductPurchase(player, productId)
	local dataManager = configuredDataManager
	if dataManager and typeof(dataManager.PromptProductPurchase) == "function" then
		return dataManager:PromptProductPurchase(player, productId)
	end

	return false, "data_manager_unavailable"
end

local function recordReceiptFallback(profile, player, receiptInfo, offer, reason, details)
	if typeof(profile) ~= "table" or typeof(profile.Data) ~= "table" then
		return nil, false
	end

	local dataKey = tostring(Config.ReceiptFallback.DataKey or "PremiumCrewStealReceiptFallbacks")
	local maxEntries = math.max(1, math.floor(tonumber(Config.ReceiptFallback.MaxEntries) or 100))
	local fallbacks = profile.Data[dataKey]
	if typeof(fallbacks) ~= "table" then
		fallbacks = {}
		profile.Data[dataKey] = fallbacks
	end

	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
	for _, marker in ipairs(fallbacks) do
		if typeof(marker) == "table" and tostring(marker.PurchaseId or "") == purchaseId and purchaseId ~= "" then
			marker.LastSeenAt = os.time()
			marker.Reason = tostring(reason or marker.Reason or "unknown")
			marker.Outcome = getReceiptOutcomeForReason(marker.Reason)
			marker.Details = details
			return marker, false
		end
	end

	local marker = {
		Type = "PremiumCrewStealFailedReceipt",
		UserId = player and player.UserId or tonumber(receiptInfo and receiptInfo.PlayerId),
		Username = player and player.Name or nil,
		ProductId = tonumber(receiptInfo and receiptInfo.ProductId),
		PurchaseId = purchaseId,
		Reason = tostring(reason or "unknown"),
		Outcome = getReceiptOutcomeForReason(reason),
		Details = details,
		CreatedAt = os.time(),
		LastSeenAt = os.time(),
		Resolved = false,
		Offer = if typeof(offer) == "table" then {
			Token = offer.Token,
			VictimUserId = offer.VictimUserId,
			VictimName = offer.VictimName,
			StandName = offer.StandName,
			InstanceId = offer.InstanceId,
			StorageName = offer.StorageName,
			DisplayName = offer.DisplayName,
			Rarity = offer.Rarity,
			Variant = offer.Variant,
			Level = offer.Level,
			PriceRobux = offer.PriceRobux,
			BucketKey = offer.BucketKey,
		} else nil,
	}

	table.insert(fallbacks, marker)
	while #fallbacks > maxEntries do
		table.remove(fallbacks, 1)
	end

	return marker, true
end

local function saveReceiptFailureMarker(profile)
	if typeof(profile) ~= "table" or typeof(profile.Save) ~= "function" then
		return
	end
	if typeof(profile.IsActive) == "function" and profile:IsActive() ~= true then
		return
	end

	local ok, err = pcall(function()
		profile:Save()
	end)
	if not ok then
		warn("[PremiumCrewStealReceipt] Failed to save failure marker: " .. tostring(err))
	end
end

local function getReceiptSuccessStore(profile)
	if typeof(profile) ~= "table" or typeof(profile.Data) ~= "table" then
		return nil
	end

	local dataKey = tostring(Config.ReceiptFallback.SuccessDataKey or "PremiumCrewStealSuccessfulReceipts")
	local successes = profile.Data[dataKey]
	if typeof(successes) ~= "table" then
		successes = {}
		profile.Data[dataKey] = successes
	end
	return successes
end

local function getSuccessfulReceiptMarker(profile, purchaseId)
	purchaseId = tostring(purchaseId or "")
	if purchaseId == "" then
		return nil
	end

	if successfulReceiptsByPurchaseId[purchaseId] then
		return successfulReceiptsByPurchaseId[purchaseId]
	end

	local successes = getReceiptSuccessStore(profile)
	local marker = successes and successes[purchaseId]
	if typeof(marker) == "table" then
		successfulReceiptsByPurchaseId[purchaseId] = marker
		return marker
	end

	return nil
end

local clearVictimStandVisual

local function refreshCrewIncomeRuntime(player, source)
	local ok, runtime = pcall(function()
		return require(ServerScriptService.Modules:WaitForChild("CrewIncomeRuntime"))
	end)
	if not ok or typeof(runtime) ~= "table" or typeof(runtime.RefreshPlayer) ~= "function" then
		return false, tostring(runtime or "crew_income_runtime_unavailable")
	end

	return runtime.RefreshPlayer(player, source)
end

local function verifyVictimStandCleared(victim, standName, sourceInstanceId)
	if typeof(victim) ~= "Instance" or not victim:IsA("Player") or victim.Parent ~= Players then
		return false, "invalid_victim", {
			StandName = tostring(standName or ""),
			SourceInstanceId = tostring(sourceInstanceId or ""),
		}
	end

	if clearVictimStandVisual then
		clearVictimStandVisual(victim, standName)
	end

	local dataOk, dataReason, dataDetail = CrewInstanceService.VerifyStandEmpty(victim, standName, {
		SourceInstanceId = sourceInstanceId,
	})
	local activeShip = ShipRuntimeService.GetActiveShip(victim)
	local standModel = activeShip and ShipSlotService.GetSlot(activeShip, standName)
	local placed = standModel and standModel:FindFirstChild("PlacedCrewMember")
	local visualClear = placed == nil
	local detail = {
		Data = dataDetail,
		VisualClear = visualClear,
		PlacedModel = placed and placed:GetFullName() or nil,
	}

	if dataOk ~= true or visualClear ~= true then
		return false, dataReason or "victim_stand_not_cleared", detail
	end

	return true, nil, detail
end

local function finalizePostTransferRuntime(marker, buyer)
	if marker.RuntimeRefreshed == true then
		return true, nil
	end

	local victim = Players:GetPlayerByUserId(tonumber(marker.VictimUserId) or 0)
	if not victim then
		return false, "invalid_victim"
	end

	local victimRefreshOk, victimRefreshReason = refreshCrewIncomeRuntime(victim, "premium_crew_steal_transfer_out")
	if victimRefreshOk ~= true then
		marker.RuntimeRefresh = {
			VictimOk = false,
			VictimReason = tostring(victimRefreshReason or ""),
		}
		return false, "victim_runtime_refresh_failed"
	end

	local buyerRefreshOk, buyerRefreshReason = refreshCrewIncomeRuntime(buyer, "premium_crew_steal_transfer_in")
	if buyerRefreshOk ~= true then
		marker.RuntimeRefresh = {
			VictimOk = true,
			BuyerOk = false,
			BuyerReason = tostring(buyerRefreshReason or ""),
		}
		return false, "buyer_runtime_refresh_failed"
	end

	marker.RuntimeRefreshed = true
	marker.RuntimeRefreshedAt = os.time()
	marker.RuntimeRefresh = {
		VictimOk = true,
		BuyerOk = true,
	}
	return true, nil
end

local function recordSuccessfulReceipt(profile, receiptInfo, buyer, victim, offer, buyerInstanceId, persistenceFinalized)
	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
	if purchaseId == "" then
		return nil
	end

	local finalized = persistenceFinalized == true
	local marker = {
		Type = "PremiumCrewStealSuccessfulReceipt",
		PurchaseId = purchaseId,
		ProductId = tonumber(receiptInfo and receiptInfo.ProductId),
		BuyerUserId = buyer and buyer.UserId or tonumber(receiptInfo and receiptInfo.PlayerId),
		BuyerName = buyer and buyer.Name or nil,
		VictimUserId = victim and victim.UserId or tonumber(offer and offer.VictimUserId),
		VictimName = victim and victim.Name or tostring(offer and offer.VictimName or ""),
		StandName = offer and offer.StandName or nil,
		SourceInstanceId = offer and offer.InstanceId or nil,
		BuyerInstanceId = buyerInstanceId,
		StorageName = offer and offer.StorageName or nil,
		Rarity = offer and offer.Rarity or nil,
		Variant = offer and offer.Variant or nil,
		Level = offer and offer.Level or nil,
		PriceRobux = offer and offer.PriceRobux or nil,
		BucketKey = offer and offer.BucketKey or nil,
		CompletedAt = os.time(),
		HotbarVerified = finalized,
		HotbarVerification = nil,
		HotbarVerifiedAt = if finalized then os.time() else nil,
		RuntimeRefreshed = finalized,
		RuntimeRefresh = nil,
		RuntimeRefreshedAt = if finalized then os.time() else nil,
		VictimStandCleared = finalized,
		VictimStandVerification = nil,
		VictimStandClearedAt = if finalized then os.time() else nil,
		CooldownPersisted = finalized,
		ProtectionRemovalPersisted = if Config.Protection.RemoveOnSuccessfulSteal == true then finalized else nil,
		RaidShieldPenaltyApplied = finalized,
		RaidShieldSuppressionUntil = nil,
		RaidShieldPenaltyReason = nil,
		PersistenceFinalized = finalized,
		GrantReady = finalized,
		FinalizedAt = if finalized then os.time() else nil,
	}

	local successes = getReceiptSuccessStore(profile)
	if successes then
		successes[purchaseId] = marker
	end
	successfulReceiptsByPurchaseId[purchaseId] = marker
	return marker
end

local function finalizeSuccessfulReceiptPersistence(marker, buyer)
	if typeof(marker) ~= "table" then
		return false, "missing_success_marker"
	end
	if marker.GrantReady == true and marker.PersistenceFinalized == true then
		return true, nil
	end

	local buyerUserId = tonumber(marker.BuyerUserId)
	local victimUserId = tonumber(marker.VictimUserId)
	if not buyerUserId or not victimUserId then
		return false, "invalid_success_marker"
	end

	if marker.HotbarVerified ~= true then
		local hotbarOk, hotbarReason, hotbarDetail =
			verifyBuyerHotbarGrant(buyer, marker.BuyerInstanceId, marker.StorageName)
		marker.HotbarVerification = hotbarDetail
		if hotbarOk ~= true then
			marker.HotbarVerified = false
			audit("hotbar_verification_failed", {
				PurchaseId = marker.PurchaseId,
				BuyerUserId = marker.BuyerUserId,
				VictimUserId = marker.VictimUserId,
				StandName = marker.StandName,
				BuyerInstanceId = marker.BuyerInstanceId,
				Reason = hotbarReason or "hotbar_verification_failed",
				Detail = hotbarDetail,
			})
			return false, hotbarReason or "hotbar_verification_failed"
		end

		marker.HotbarVerified = true
		marker.HotbarVerifiedAt = os.time()
		audit("hotbar_verification_succeeded", {
			PurchaseId = marker.PurchaseId,
			BuyerUserId = marker.BuyerUserId,
			VictimUserId = marker.VictimUserId,
			StandName = marker.StandName,
			BuyerInstanceId = marker.BuyerInstanceId,
			Detail = hotbarDetail,
		})
	end

	if marker.RuntimeRefreshed ~= true then
		local runtimeOk, runtimeReason = finalizePostTransferRuntime(marker, buyer)
		if runtimeOk ~= true then
			audit("post_transfer_runtime_refresh_failed", {
				PurchaseId = marker.PurchaseId,
				BuyerUserId = marker.BuyerUserId,
				VictimUserId = marker.VictimUserId,
				StandName = marker.StandName,
				Reason = runtimeReason or "runtime_refresh_failed",
				Detail = marker.RuntimeRefresh,
			})
			return false, runtimeReason or "runtime_refresh_failed"
		end

		audit("post_transfer_runtime_refresh_succeeded", {
			PurchaseId = marker.PurchaseId,
			BuyerUserId = marker.BuyerUserId,
			VictimUserId = marker.VictimUserId,
			StandName = marker.StandName,
			Detail = marker.RuntimeRefresh,
		})
	end

	if marker.VictimStandCleared ~= true then
		local victim = Players:GetPlayerByUserId(victimUserId)
		local victimClearOk, victimClearReason, victimClearDetail =
			verifyVictimStandCleared(victim, marker.StandName, marker.SourceInstanceId)
		marker.VictimStandVerification = victimClearDetail
		if victimClearOk ~= true then
			marker.VictimStandCleared = false
			audit("victim_stand_clear_verification_failed", {
				PurchaseId = marker.PurchaseId,
				BuyerUserId = marker.BuyerUserId,
				VictimUserId = marker.VictimUserId,
				StandName = marker.StandName,
				SourceInstanceId = marker.SourceInstanceId,
				Reason = victimClearReason or "victim_stand_not_cleared",
				Detail = victimClearDetail,
			})
			return false, victimClearReason or "victim_stand_not_cleared"
		end

		marker.VictimStandCleared = true
		marker.VictimStandClearedAt = os.time()
		audit("victim_stand_clear_verification_succeeded", {
			PurchaseId = marker.PurchaseId,
			BuyerUserId = marker.BuyerUserId,
			VictimUserId = marker.VictimUserId,
			StandName = marker.StandName,
			SourceInstanceId = marker.SourceInstanceId,
			Detail = victimClearDetail,
		})
	end

	local cooldownOk, cooldownReason = PremiumCrewStealCooldowns.MarkSteal(buyerUserId, victimUserId)
	if cooldownOk ~= true then
		return false, cooldownReason or "cooldown_persistence_unavailable"
	end
	marker.CooldownPersisted = true

	if Config.Protection.RemoveOnSuccessfulSteal == true and marker.RaidShieldPenaltyApplied ~= true then
		local protectionTarget = if typeof(buyer) == "Instance" and buyer:IsA("Player") then buyer else nil
		if not protectionTarget then
			return false, "protection_persistence_unavailable"
		end
		local protectionOk, protectionStateOrReason = RaidShieldService.ApplyRaidCompletedPenalty(protectionTarget, {
			ReceiptId = marker.PurchaseId,
			Reason = "successful_premium_steal",
			VictimUserId = victimUserId,
			StandName = marker.StandName,
			SourceInstanceId = marker.SourceInstanceId,
			BuyerInstanceId = marker.BuyerInstanceId,
			CompletedAt = marker.CompletedAt,
		})
		if protectionOk ~= true then
			return false, protectionStateOrReason or "protection_persistence_unavailable"
		end
		marker.ProtectionRemovalPersisted = true
		marker.RaidShieldPenaltyApplied = true
		marker.RaidShieldSuppressionUntil = protectionStateOrReason and protectionStateOrReason.SuppressionUntil or nil
		marker.RaidShieldPenaltyReason = "successful_premium_steal"
	end

	marker.PersistenceFinalized = true
	marker.GrantReady = true
	marker.FinalizedAt = os.time()
	return true, nil
end

clearVictimStandVisual = function(victim, standName)
	local activeShip = ShipRuntimeService.GetActiveShip(victim)
	local standModel = activeShip and ShipSlotService.GetSlot(activeShip, standName)
	if not standModel then
		return false, "stand_model_missing"
	end

	local placed = standModel:FindFirstChild("PlacedCrewMember")
	if placed then
		placed:Destroy()
	end

	local prompt = standModel:FindFirstChild(Config.Prompt.Name, true)
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end
	return true, nil
end

local function buildOfferPayload(offer, includeToken)
	local payload = {
		VictimUserId = offer.VictimUserId,
		VictimName = offer.VictimName,
		StandName = offer.StandName,
		CrewDisplayName = offer.DisplayName,
		StorageName = offer.StorageName,
		Rarity = offer.Rarity,
		Variant = offer.Variant,
		Level = offer.Level,
		PriceRobux = offer.PriceRobux,
		ProductId = offer.ProductId,
		ExpiresAtUnix = offer.ExpiresAtUnix,
	}
	if includeToken == true then
		payload.Token = offer.Token
	end
	return payload
end

local function sendWarningForOffer(player, offer)
	ensureRemotes()
	local shieldPrompt = RaidShieldService.BuildRaidAttemptPromptState(player)
	local payload = buildOfferPayload(offer, true)
	payload.Shield = shieldPrompt
	warningRemote:FireClient(player, payload)
	sendResult(player, {
		Ok = true,
		Reason = "awaiting_confirmation",
		Offer = buildOfferPayload(offer, false),
		Shield = shieldPrompt,
	})
	return true, nil
end

local function promptPurchaseForOffer(player, offer, phase)
	phase = tostring(phase or "prompt")

	if isOfferExpired(offer) then
		setOfferState(offer, OFFER_STATE_RETRYABLE_FAILURE, "offer_expired", {
			Phase = phase,
		})
		clearOfferWithAudit(offer, "offer_expired", {
			Phase = phase,
		})
		sendPopup(player, "That steal offer expired.", ERROR_COLOR, true)
		sendResult(player, {
			Ok = false,
			Reason = "offer_expired",
		})
		return false, "offer_expired"
	end

	if offer.PurchasePromptedAtClock ~= nil then
		if offer.State == OFFER_STATE_PROMPT_PURCHASED or offer.State == OFFER_STATE_RECEIPT_PROCESSING then
			sendPopup(player, reasonToMessage("purchase_processing"), INFO_COLOR, false)
			sendResult(player, {
				Ok = false,
				Reason = "purchase_processing",
				PriceRobux = offer.PriceRobux,
				BucketKey = offer.BucketKey,
				ProductId = offer.ProductId,
			})
			return false, "purchase_processing"
		end

		sendResult(player, {
			Ok = true,
			Reason = "purchase_prompted",
			PriceRobux = offer.PriceRobux,
			BucketKey = offer.BucketKey,
			ProductId = offer.ProductId,
		})
		return true, nil
	end

	local snapshot, reason, detail = validateOfferAgainstLiveTarget(offer, player)
	if not snapshot then
		local failureKind = getFailureAuditKind(reason)
		if failureKind then
			audit(failureKind, {
				Phase = phase,
				Reason = reason,
				BuyerUserId = player.UserId,
				VictimUserId = offer.VictimUserId,
				StandName = offer.StandName,
				InstanceId = offer.InstanceId,
				Details = detail,
			})
		end
		setOfferState(offer, OFFER_STATE_RETRYABLE_FAILURE, reason, {
			Phase = phase,
			Detail = detail,
		})
		clearOfferWithAudit(offer, "live_validation_failed", {
			Phase = phase,
			Reason = reason,
			Detail = detail,
		})
		sendPopup(player, reasonToMessage(reason, detail), ERROR_COLOR, true)
		sendResult(player, {
			Ok = false,
			Reason = reason,
			Detail = detail,
		})
		return false, reason
	end

	local reserved, reservationReason, reservationDetail = reserveOfferForPurchase(offer)
	if reserved ~= true then
		audit("reservation_mismatch", {
			Phase = phase,
			Reason = reservationReason,
			BuyerUserId = player.UserId,
			VictimUserId = offer.VictimUserId,
			StandName = offer.StandName,
			InstanceId = offer.InstanceId,
			Details = reservationDetail,
		})
		setOfferState(offer, OFFER_STATE_RETRYABLE_FAILURE, reservationReason, {
			Phase = phase,
			Detail = reservationDetail,
		})
		clearOfferWithAudit(offer, "reservation_failed", {
			Phase = phase,
			Reason = reservationReason,
			Detail = reservationDetail,
		})
		sendPopup(player, reasonToMessage(reservationReason, reservationDetail), ERROR_COLOR, true)
		sendResult(player, {
			Ok = false,
			Reason = reservationReason,
			Detail = reservationDetail,
		})
		return false, reservationReason
	end

	audit("reservation_created", getOfferAuditPayload(offer, {
		Phase = phase,
		ReservationExpiresAt = offer.ReservationExpiresAt,
	}))
	offer.ConfirmedAtClock = os.clock()
	setOfferState(offer, OFFER_STATE_PROMPTING, "prompt_product_purchase", {
		Phase = phase,
	})
	local prompted, promptReason = promptProductPurchase(player, offer.ProductId)
	if prompted ~= true then
		setOfferState(offer, OFFER_STATE_RETRYABLE_FAILURE, promptReason or "product_prompt_failed", {
			Phase = phase,
		})
		clearOfferWithAudit(offer, "prompt_product_purchase_failed", {
			Phase = phase,
			Reason = promptReason or "product_prompt_failed",
		})
		sendPopup(player, reasonToMessage(promptReason or "product_not_available"), ERROR_COLOR, true)
		sendResult(player, {
			Ok = false,
			Reason = promptReason or "product_prompt_failed",
		})
		return false, promptReason or "product_prompt_failed"
	end

	offer.PurchasePromptedAtClock = os.clock()
	audit("prompt_opened", getOfferAuditPayload(offer, {
		Phase = phase,
		ProductId = offer.ProductId,
	}))
	sendResult(player, {
		Ok = true,
		Reason = "purchase_prompted",
		Offer = buildOfferPayload(offer, false),
	})
	return true, nil
end

function PremiumCrewStealService.Configure(options)
	options = if typeof(options) == "table" then options else {}
	if options.DataManager ~= nil then
		configuredDataManager = options.DataManager
	end
end

function PremiumCrewStealService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()
	RaidShieldService.Start()

	confirmRemote.OnServerEvent:Connect(function(player, token, accepted)
		PremiumCrewStealService.HandleClientConfirmation(player, token, accepted)
	end)

	MarketplaceService.PromptProductPurchaseFinished:Connect(function(playerOrUserId, productId, wasPurchased)
		local player = if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then playerOrUserId else nil
		local userId = if player then player.UserId else tonumber(playerOrUserId)
		local offer = userId and pendingByBuyerUserId[userId]
		if not offer then
			audit("prompt_finished_no_offer", {
				BuyerUserId = userId,
				ProductId = tonumber(productId),
				WasPurchased = wasPurchased == true,
			})
			return
		end

		if tonumber(offer.ProductId) ~= tonumber(productId) then
			setOfferState(offer, OFFER_STATE_PROMPT_CANCELLED, "prompt_product_mismatch", {
				ActualProductId = tonumber(productId),
				ExpectedProductId = tonumber(offer.ProductId),
				WasPurchased = wasPurchased == true,
			})
			clearOfferWithAudit(offer, "prompt_product_mismatch", {
				ActualProductId = tonumber(productId),
				ExpectedProductId = tonumber(offer.ProductId),
				WasPurchased = wasPurchased == true,
			})
			audit("prompt_finished_product_mismatch", getOfferAuditPayload(offer, {
				ActualProductId = tonumber(productId),
				ExpectedProductId = tonumber(offer.ProductId),
				WasPurchased = wasPurchased == true,
			}))
			return
		end

		if wasPurchased ~= true then
			setOfferState(offer, OFFER_STATE_PROMPT_CANCELLED, "prompt_cancelled", {
				ProductId = tonumber(productId),
			})
			clearOfferWithAudit(offer, "prompt_cancelled", {
				ProductId = tonumber(productId),
			})
			if player then
				sendResult(player, {
					Ok = false,
					Reason = "prompt_cancelled",
				})
			end
			return
		end

		offer.PromptPurchasedAtClock = os.clock()
		offer.PromptPurchasedAtUnix = os.time()
		setOfferState(offer, OFFER_STATE_PROMPT_PURCHASED, "prompt_purchase_confirmed", {
			ProductId = tonumber(productId),
		})
		audit("prompt_finished_purchased", getOfferAuditPayload(offer, {
			ProductId = tonumber(productId),
		}))
		if player then
			sendResult(player, {
				Ok = true,
				Reason = "purchase_processing",
				ProductId = tonumber(productId),
			})
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		clearOffersForPlayer(player)
		lastPromptAtByBuyer[player.UserId] = nil
	end)
end

function PremiumCrewStealService.IsStandLocked(victim, standName)
	cleanupExpired()
	local victimUserId = if typeof(victim) == "Instance" then victim.UserId else tonumber(victim)
	local key = standKey(victimUserId, ShipSlotService.NormalizeSlotNumber(standName) or standName)
	local reservation = reservationsByStandKey[key]
	if not reservation then
		return false, 0
	end

	local remaining = (tonumber(reservation.ReservationExpiresAt) or 0) - os.clock()
	if remaining <= 0 then
		reservationsByStandKey[key] = nil
		return false, 0
	end

	return true, remaining, reservation.ReservedByUserId
end

function PremiumCrewStealService.RequestPromptFromStand(buyer, victim, _activeShip, standModel)
	PremiumCrewStealService.Start()
	cleanupExpired()

	if typeof(standModel) ~= "Instance" then
		sendPopup(buyer, "That stand cannot be stolen from.", ERROR_COLOR, true)
		return false, "invalid_stand"
	end
	if typeof(buyer) ~= "Instance" or not buyer:IsA("Player") or buyer.Parent ~= Players then
		return false, "invalid_buyer"
	end

	local nowClock = os.clock()
	local lastPromptAt = tonumber(lastPromptAtByBuyer[buyer.UserId]) or 0
	if (nowClock - lastPromptAt) < (tonumber(Config.Cooldowns.PromptDebounceSeconds) or 2) then
		return false, "prompt_debounce"
	end
	lastPromptAtByBuyer[buyer.UserId] = nowClock

	local requestedStandName = ShipSlotService.NormalizeSlotNumber(standModel.Name) or tostring(standModel.Name)
	local existingOffer = pendingByBuyerUserId[buyer.UserId]
	if existingOffer then
		if isOfferExpired(existingOffer) then
			setOfferState(existingOffer, OFFER_STATE_RETRYABLE_FAILURE, "offer_expired", {
				Phase = "prompt_retry",
			})
			clearOfferWithAudit(existingOffer, "same_buyer_expired_offer")
		else
			local targetVictimUserId = if typeof(victim) == "Instance" and victim:IsA("Player") then victim.UserId else nil
			local sameTarget = targetVictimUserId ~= nil
				and tonumber(existingOffer.VictimUserId) == targetVictimUserId
				and tostring(existingOffer.StandName) == tostring(requestedStandName)
			if sameTarget
				and (existingOffer.State == OFFER_STATE_PROMPT_PURCHASED
					or existingOffer.State == OFFER_STATE_RECEIPT_PROCESSING)
			then
				sendPopup(buyer, reasonToMessage("purchase_processing"), INFO_COLOR, false)
				sendResult(buyer, {
					Ok = false,
					Reason = "purchase_processing",
					Offer = buildOfferPayload(existingOffer, false),
				})
				audit("same_buyer_retry_blocked_processing", getOfferAuditPayload(existingOffer, {
					RequestedStandName = requestedStandName,
				}))
				return false, "purchase_processing"
			end

			local clearReason = if sameTarget then "same_buyer_retry_refresh" else "buyer_changed_target"
			setOfferState(existingOffer, OFFER_STATE_PROMPT_CANCELLED, clearReason, {
				RequestedStandName = requestedStandName,
			})
			clearOfferWithAudit(existingOffer, clearReason, {
				RequestedStandName = requestedStandName,
			})
		end
	end

	local snapshot, reason, detail = buildSnapshot(buyer, victim, requestedStandName, {
		CheckCapacity = true,
	})
	if not snapshot then
		local failureKind = getFailureAuditKind(reason)
		if failureKind then
			audit(failureKind, {
				Phase = "prompt",
				Reason = reason,
				BuyerUserId = buyer.UserId,
				VictimUserId = victim and victim.UserId or nil,
				StandName = standModel.Name,
				Details = detail,
			})
		end
		sendPopup(buyer, reasonToMessage(reason, detail), ERROR_COLOR, true)
		sendResult(buyer, {
			Ok = false,
			Reason = reason,
			Detail = detail,
		})
		return false, reason
	end

	local configuredBucket = Config.GetBucketForProductId(snapshot.ProductId)
	if not Config.IsProductBucketActive(configuredBucket) or not MonetizationConfig.CanPromptDeveloperProduct(snapshot.ProductId) then
		sendPopup(buyer, reasonToMessage("product_not_available"), ERROR_COLOR, true)
		sendResult(buyer, {
			Ok = false,
			Reason = "product_not_available",
			PriceRobux = snapshot.PriceRobux,
			BucketKey = snapshot.BucketKey,
		})
		return false, "product_not_available"
	end

	local token = HttpService:GenerateGUID(false)
	local ttl = getOfferTtl()
	local offer = {
		Token = token,
		BuyerUserId = buyer.UserId,
		BuyerName = buyer.Name,
		VictimUserId = snapshot.VictimUserId,
		VictimName = snapshot.VictimName,
		StandName = snapshot.StandName,
		InstanceId = snapshot.InstanceId,
		StorageName = snapshot.StorageName,
		DisplayName = snapshot.DisplayName,
		Rarity = snapshot.Rarity,
		Variant = snapshot.Variant,
		Level = snapshot.Level,
		BucketKey = snapshot.BucketKey,
		PriceRobux = snapshot.PriceRobux,
		DesiredPriceRobux = snapshot.DesiredPriceRobux,
		ProductId = snapshot.ProductId,
		CreatedAtClock = nowClock,
		ExpiresAtClock = nowClock + ttl,
		ExpiresAtUnix = os.time() + ttl,
	}

	pendingByBuyerUserId[buyer.UserId] = offer
	pendingByToken[token] = offer
	setOfferState(offer, OFFER_STATE_CREATED, "offer_created", {
		PriceRobux = offer.PriceRobux,
		ProductId = offer.ProductId,
		BucketKey = offer.BucketKey,
	})
	scheduleOfferExpiry(offer)

	return sendWarningForOffer(buyer, offer)
end

function PremiumCrewStealService.HandleClientConfirmation(player, token, accepted)
	PremiumCrewStealService.Start()
	if not RemoteGuard.Check(player, Config.Remotes.ConfirmName, { token, accepted }, {
		Cooldown = 0.25,
		Args = {
			{ Type = "string", MaxLength = 80 },
			{ Type = "boolean" },
		},
	}) then
		return
	end

	cleanupExpired()

	local offer = pendingByToken[tostring(token or "")]
	if not offer or offer.BuyerUserId ~= player.UserId then
		sendResult(player, {
			Ok = false,
			Reason = "offer_not_found",
		})
		return
	end

	if accepted ~= true then
		setOfferState(offer, OFFER_STATE_PROMPT_CANCELLED, "client_declined")
		clearOfferWithAudit(offer, "client_declined")
		sendResult(player, {
			Ok = false,
			Reason = "declined",
		})
		return
	end

	if isOfferExpired(offer) then
		setOfferState(offer, OFFER_STATE_RETRYABLE_FAILURE, "offer_expired", {
			Phase = "confirm",
		})
		clearOfferWithAudit(offer, "offer_expired", {
			Phase = "confirm",
		})
		sendPopup(player, "That steal offer expired.", ERROR_COLOR, true)
		return
	end

	promptPurchaseForOffer(player, offer, "confirm")
end

function PremiumCrewStealService.ProcessReceipt(receiptInfo, buyer, profile, dataManager)
	PremiumCrewStealService.Start()
	if dataManager ~= nil then
		configuredDataManager = dataManager
	end

	local productId = tonumber(receiptInfo and receiptInfo.ProductId)
	local purchaseId = tostring(receiptInfo and receiptInfo.PurchaseId or "")
	audit("receipt_entered", {
		PurchaseId = purchaseId,
		ProductId = productId,
		BuyerUserId = buyer and buyer.UserId or tonumber(receiptInfo and receiptInfo.PlayerId),
	})

	local existingSuccess = getSuccessfulReceiptMarker(profile, purchaseId)
	if existingSuccess then
		local buyerUserId = buyer and buyer.UserId or tonumber(receiptInfo and receiptInfo.PlayerId)
		local pendingOffer = buyer and pendingByBuyerUserId[buyer.UserId]
		if existingSuccess.GrantReady == true and existingSuccess.PersistenceFinalized == true then
			if pendingOffer then
				setOfferState(pendingOffer, OFFER_STATE_GRANTED, "duplicate_receipt_already_granted", {
					PurchaseId = purchaseId,
				})
				clearOfferWithAudit(pendingOffer, "duplicate_receipt_already_granted", {
					PurchaseId = purchaseId,
				})
			end
			audit("successful_steal_duplicate_receipt", {
				PurchaseId = purchaseId,
				ProductId = productId,
				BuyerUserId = buyerUserId,
				BuyerInstanceId = existingSuccess.BuyerInstanceId,
				VictimUserId = existingSuccess.VictimUserId,
				StandName = existingSuccess.StandName,
			})
			return true, {
				Outcome = RECEIPT_OUTCOME_SUCCESS,
				Reason = "already_granted",
				Duplicate = true,
				BuyerInstanceId = existingSuccess.BuyerInstanceId,
			}
		end

		local finalized, finalizeReason = finalizeSuccessfulReceiptPersistence(existingSuccess, buyer)
		if finalized == true then
			if pendingOffer then
				setOfferState(pendingOffer, OFFER_STATE_GRANTED, "receipt_retry_finalized", {
					PurchaseId = purchaseId,
				})
				clearOfferWithAudit(pendingOffer, "receipt_retry_finalized", {
					PurchaseId = purchaseId,
				})
			end
			audit("successful_steal_finalized_after_retry", {
				PurchaseId = purchaseId,
				ProductId = productId,
				BuyerUserId = buyerUserId,
				BuyerInstanceId = existingSuccess.BuyerInstanceId,
				VictimUserId = existingSuccess.VictimUserId,
				StandName = existingSuccess.StandName,
			})
			return true, {
				Outcome = RECEIPT_OUTCOME_SUCCESS,
				Reason = "already_granted",
				Duplicate = true,
				BuyerInstanceId = existingSuccess.BuyerInstanceId,
			}
		end

		local details = {
			PendingSuccessfulTransfer = true,
			BuyerInstanceId = existingSuccess.BuyerInstanceId,
			HotbarVerification = existingSuccess.HotbarVerification,
			RuntimeRefresh = existingSuccess.RuntimeRefresh,
			VictimStandVerification = existingSuccess.VictimStandVerification,
		}
		local outcome = getReceiptOutcomeForReason(finalizeReason)
		recordReceiptFallback(profile, buyer, receiptInfo, nil, finalizeReason, details)
		saveReceiptFailureMarker(profile)
		auditReceiptFailure(finalizeReason, outcome, {
			PurchaseId = purchaseId,
			ProductId = productId,
			BuyerUserId = buyerUserId,
			VictimUserId = existingSuccess.VictimUserId,
			StandName = existingSuccess.StandName,
			InstanceId = existingSuccess.SourceInstanceId,
			BucketKey = existingSuccess.BucketKey,
			PriceRobux = existingSuccess.PriceRobux,
			Details = details,
		})
		if pendingOffer then
			setOfferState(pendingOffer, OFFER_STATE_RETRYABLE_FAILURE, finalizeReason or "receipt_persistence_unavailable", {
				PurchaseId = purchaseId,
				Details = details,
			})
			clearOfferWithAudit(pendingOffer, "pending_success_retryable_failure", {
				PurchaseId = purchaseId,
				Reason = finalizeReason or "receipt_persistence_unavailable",
			})
		end
		sendPopup(buyer, reasonToMessage(finalizeReason), ERROR_COLOR, true)
		return false, {
			Outcome = outcome,
			Reason = tostring(finalizeReason or "unknown"),
			Details = details,
		}
	end

	if purchaseId ~= "" then
		if receiptLocksByPurchaseId[purchaseId] then
			auditReceiptFailure("receipt_in_progress", RECEIPT_OUTCOME_RETRYABLE_FAILURE, {
				PurchaseId = purchaseId,
				ProductId = productId,
				BuyerUserId = buyer and buyer.UserId or tonumber(receiptInfo and receiptInfo.PlayerId),
			})
			return false, {
				Outcome = RECEIPT_OUTCOME_RETRYABLE_FAILURE,
				Reason = "receipt_in_progress",
			}
		end
		receiptLocksByPurchaseId[purchaseId] = true
	end

	local function finishFailure(reason, offer, details, message)
		local outcome = getReceiptOutcomeForReason(reason)
		recordReceiptFallback(profile, buyer, receiptInfo, offer, reason, details)
		saveReceiptFailureMarker(profile)
		local cleanup = nil
		if offer then
			setOfferState(offer, OFFER_STATE_RETRYABLE_FAILURE, reason, {
				PurchaseId = purchaseId,
				Details = details,
			})
			cleanup = clearOfferWithAudit(offer, "receipt_failure", {
				PurchaseId = purchaseId,
				Reason = reason,
			})
		end
		auditReceiptFailure(reason, outcome, {
			PurchaseId = purchaseId,
			ProductId = productId,
			BuyerUserId = buyer and buyer.UserId or tonumber(receiptInfo and receiptInfo.PlayerId),
			VictimUserId = offer and offer.VictimUserId or nil,
			StandName = offer and offer.StandName or nil,
			InstanceId = offer and offer.InstanceId or nil,
			BucketKey = offer and offer.BucketKey or nil,
			PriceRobux = offer and offer.PriceRobux or nil,
			Details = details,
			Cleanup = cleanup,
		})
		if message then
			sendPopup(buyer, message, ERROR_COLOR, true)
		end
		if purchaseId ~= "" then
			receiptLocksByPurchaseId[purchaseId] = nil
		end
		return false, {
			Outcome = outcome,
			Reason = tostring(reason or "unknown"),
			Details = details,
		}
	end

	local offer = buyer and pendingByBuyerUserId[buyer.UserId]
	if not offer or tonumber(offer.ProductId) ~= productId then
		return finishFailure(
			"no_pending_offer",
			offer,
			nil,
			"Premium steal purchase could not find an active target. Support marker recorded."
		)
	end
	setOfferState(offer, OFFER_STATE_RECEIPT_PROCESSING, "receipt_entered", {
		PurchaseId = purchaseId,
		ProductId = productId,
	})

	if isOfferExpired(offer) then
		return finishFailure(
			"offer_expired",
			offer,
			nil,
			"Premium steal offer expired before the receipt arrived. Support marker recorded."
		)
	end

	local reservationOk, reservationReason = validateReservationForReceipt(offer, buyer)
	if reservationOk ~= true then
		return finishFailure(
			reservationReason,
			offer,
			nil,
			"Premium steal reservation expired before purchase completed. Support marker recorded."
		)
	end

	local snapshot, reason, detail = validateOfferAgainstLiveTarget(offer, buyer)
	if not snapshot then
		return finishFailure(
			reason,
			offer,
			detail,
			"Premium steal target changed before purchase completed. Support marker recorded."
		)
	end

	local victim = Players:GetPlayerByUserId(offer.VictimUserId)
	if not victim then
		return finishFailure(
			"invalid_victim",
			offer,
			nil,
			"Premium steal victim left before transfer. Support marker recorded."
		)
	end
	local transferOk, buyerInstanceId, buyerInstance, transferReason, transferDebug = pcall(function()
		return CrewInstanceService.TransferStandInstance(victim, buyer, offer.StandName, {
			ExpectedInstanceId = offer.InstanceId,
			Source = "premium_crew_steal",
		})
	end)
	if not transferOk then
		audit("transfer_result", getOfferAuditPayload(offer, {
			PurchaseId = purchaseId,
			Ok = false,
			Error = tostring(buyerInstanceId),
		}))
		return finishFailure(
			"transfer_failed",
			offer,
			{
				Error = tostring(buyerInstanceId),
			},
			"Premium steal transfer failed. Support marker recorded."
		)
	end
	if not buyerInstance then
		audit("transfer_result", getOfferAuditPayload(offer, {
			PurchaseId = purchaseId,
			Ok = false,
			Reason = transferReason or "missing_buyer_instance",
			Detail = transferDebug,
		}))
		return finishFailure(
			"transfer_failed",
			offer,
			{
				Reason = transferReason or "missing_buyer_instance",
				Debug = transferDebug,
			},
			"Premium steal transfer failed. Support marker recorded."
		)
	end
	audit("transfer_result", getOfferAuditPayload(offer, {
		PurchaseId = purchaseId,
		Ok = true,
		BuyerInstanceId = buyerInstanceId,
		StorageName = buyerInstance.StorageName,
		Detail = transferDebug,
	}))

	local successMarker = recordSuccessfulReceipt(profile, receiptInfo, buyer, victim, offer, buyerInstanceId, false)
	if not successMarker then
		return finishFailure(
			"receipt_success_marker_failed",
			offer,
			{
				Transferred = true,
				BuyerInstanceId = buyerInstanceId,
			},
			"Premium steal transfer completed but receipt tracking failed. Support marker recorded."
		)
	end

	local finalized, finalizeReason = finalizeSuccessfulReceiptPersistence(successMarker, buyer)
	if finalized ~= true then
		clearVictimStandVisual(victim, offer.StandName)
		return finishFailure(
			finalizeReason or "receipt_persistence_unavailable",
			offer,
			{
				Transferred = true,
				BuyerInstanceId = buyerInstanceId,
				HotbarVerification = successMarker and successMarker.HotbarVerification or nil,
				RuntimeRefresh = successMarker and successMarker.RuntimeRefresh or nil,
				VictimStandVerification = successMarker and successMarker.VictimStandVerification or nil,
			},
			"Premium steal transfer completed but final receipt persistence is temporarily unavailable. Support marker recorded."
		)
	end

	audit("successful_steal", {
		PurchaseId = purchaseId,
		ProductId = productId,
		BuyerUserId = buyer.UserId,
		BuyerName = buyer.Name,
		VictimUserId = victim.UserId,
		VictimName = victim.Name,
		StandName = offer.StandName,
		SourceInstanceId = offer.InstanceId,
		BuyerInstanceId = buyerInstanceId,
		StorageName = offer.StorageName,
		Rarity = offer.Rarity,
		Variant = offer.Variant,
		Level = offer.Level,
		BucketKey = offer.BucketKey,
		PriceRobux = offer.PriceRobux,
		HotbarVerification = successMarker.HotbarVerification,
		RuntimeRefresh = successMarker.RuntimeRefresh,
		VictimStandVerification = successMarker.VictimStandVerification,
	})

	clearVictimStandVisual(victim, offer.StandName)
	setOfferState(offer, OFFER_STATE_GRANTED, "receipt_success", {
		PurchaseId = purchaseId,
		BuyerInstanceId = buyerInstanceId,
	})
	local cleanup = clearOfferWithAudit(offer, "receipt_success", {
		PurchaseId = purchaseId,
		BuyerInstanceId = buyerInstanceId,
	})
	audit("receipt_success_cleanup", {
		PurchaseId = purchaseId,
		ProductId = productId,
		BuyerUserId = buyer.UserId,
		VictimUserId = victim.UserId,
		StandName = offer.StandName,
		BuyerInstanceId = buyerInstanceId,
		Cleanup = cleanup,
	})
	if purchaseId ~= "" then
		receiptLocksByPurchaseId[purchaseId] = nil
	end

	sendPopup(
		buyer,
		string.format("Stole %s. It was added to your crew hotbar.", tostring(snapshot.DisplayName)),
		SUCCESS_COLOR,
		false
	)
	sendPopup(
		victim,
		string.format("%s stole %s from your ship.", buyer.Name, tostring(snapshot.DisplayName)),
		ERROR_COLOR,
		true
	)
	sendResult(buyer, {
		Ok = true,
		Reason = "steal_granted",
		BuyerInstanceId = buyerInstanceId,
		CrewDisplayName = snapshot.DisplayName,
	})

	return true, {
		Outcome = RECEIPT_OUTCOME_SUCCESS,
		Reason = "steal_granted",
		BuyerInstanceId = buyerInstanceId,
	}
end

return PremiumCrewStealService
