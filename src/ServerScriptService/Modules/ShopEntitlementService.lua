local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local RewardIconResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RewardIconResolver"))
local ShopReceiptGrants = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ShopReceiptGrants"))
local TitleService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TitleService"))

local ShopEntitlementService = {}

local started = false
local dataManagerRef = nil
local promptConnection = nil
local playerRemovingConnection = nil
local captainSupplyGrantInFlight = {}

local VIP_GAMEPASS_ID = tonumber(MonetizationConfig.ActiveChefsGamepasses.VIP and MonetizationConfig.ActiveChefsGamepasses.VIP.Id)
local CAPTAIN_TITLE_ID = "Captain"
local DAILY_STATE_PATH = "DailyClaims.CaptainSupply.LastClaimDate"

local function todayUtc()
	return os.date("!%Y-%m-%d")
end

local function hasVip(player)
	local passes = player:FindFirstChild("Passes")
	local vip = passes and passes:FindFirstChild("VIP")
	return vip and vip:IsA("BoolValue") and vip.Value == true
end

local function setVip(player, dataManager, enabled)
	local ok, reason = dataManager:TrySetValue(player, "Passes.VIP", enabled == true)
	if ok ~= true then
		return false, reason
	end
	TitleService.UnlockTitle(player, CAPTAIN_TITLE_ID)
	return true
end

local function userOwnsPass(player, gamepassId)
	local id = tonumber(gamepassId)
	if id == nil or id <= 0 then
		return false
	end

	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	return ok == true and owns == true
end

local function getShopGamepassKey(gamepassId)
	local id = tonumber(gamepassId)
	if id == nil or id <= 0 then
		return nil
	end

	for key, entry in pairs(MonetizationConfig.ShopGamepasses or {}) do
		if entry.Active == true and tonumber(entry.Id) == id then
			return key, entry
		end
	end

	if VIP_GAMEPASS_ID and id == VIP_GAMEPASS_ID then
		return "VIP", MonetizationConfig.ActiveChefsGamepasses.VIP
	end

	return nil
end

function ShopEntitlementService.ApplyGamepassEntitlement(player, gamepassKey, dataManager)
	dataManager = dataManager or dataManagerRef
	if dataManager == nil or typeof(dataManager.TryGetProfile) ~= "function" then
		return false, "data_manager_unavailable"
	end

	local profile = dataManager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return false, "profile_not_ready"
	end

	if gamepassKey == "VIP" then
		local ok, reason = setVip(player, dataManager, true)
		if ok == true then
			ShopEntitlementService.TryGrantDailySupplyChest(player, dataManager)
		end
		return ok, reason
	elseif gamepassKey == "StarterPack" then
		return ShopReceiptGrants.GrantStarterPack(player, profile, dataManager)
	elseif gamepassKey == "PermanentShieldSlot" then
		return ShopReceiptGrants.GrantPermanentShieldSlot(player, dataManager)
	end

	return false, "unknown_gamepass"
end

function ShopEntitlementService.ApplyOwnedEntitlements(player, dataManager)
	dataManager = dataManager or dataManagerRef
	if dataManager == nil then
		return
	end

	task.spawn(function()
		if VIP_GAMEPASS_ID and userOwnsPass(player, VIP_GAMEPASS_ID) then
			local ok, reason = ShopEntitlementService.ApplyGamepassEntitlement(player, "VIP", dataManager)
			if ok ~= true then
				warn(string.format(
					"[ShopEntitlementService] VIP entitlement failed player=%s reason=%s",
					player and player.Name or "<unknown>",
					tostring(reason)
				))
			end
		end

		for key, entry in pairs(MonetizationConfig.ShopGamepasses or {}) do
			local id = tonumber(entry.Id)
			if entry.Active == true and id and id > 0 and userOwnsPass(player, id) then
				local ok, reason = ShopEntitlementService.ApplyGamepassEntitlement(player, key, dataManager)
				if ok ~= true then
					warn(string.format(
						"[ShopEntitlementService] Gamepass entitlement failed player=%s key=%s reason=%s",
						player and player.Name or "<unknown>",
						tostring(key),
						tostring(reason)
					))
				end
			end
		end
	end)
end

function ShopEntitlementService.TryGrantDailySupplyChest(player, dataManager)
	dataManager = dataManager or dataManagerRef
	if player == nil or player.Parent ~= Players then
		return false, "player_unavailable"
	end
	if captainSupplyGrantInFlight[player] == true then
		return false, "grant_in_flight"
	end
	if dataManager == nil
		or typeof(dataManager.TryGetProfile) ~= "function"
		or typeof(dataManager.TryGetValue) ~= "function"
		or typeof(dataManager.TrySetValue) ~= "function"
	then
		return false, "data_manager_unavailable"
	end

	if hasVip(player) ~= true then
		return false, "captain_pass_required"
	end

	local lastClaimDate = tostring(dataManager:TryGetValue(player, DAILY_STATE_PATH) or "")
	local today = todayUtc()
	if lastClaimDate == today then
		return false, "already_claimed"
	end

	local profile = dataManager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return false, "profile_not_ready"
	end

	captainSupplyGrantInFlight[player] = true
	local ok, grantOk, grantReason = pcall(ShopReceiptGrants.GrantCaptainDailyChest, player, profile, dataManager)
	if ok ~= true or grantOk ~= true then
		captainSupplyGrantInFlight[player] = nil
		local reason = if ok == true then grantReason else grantOk
		warn(string.format(
			"[ShopEntitlementService] Supply Chest grant failed player=%s reason=%s",
			player.Name,
			tostring(reason)
		))
		return false, tostring(reason or "grant_failed")
	end

	local saved, saveReason = dataManager:TrySetValue(player, DAILY_STATE_PATH, today)
	captainSupplyGrantInFlight[player] = nil
	if saved ~= true then
		warn(string.format(
			"[ShopEntitlementService] Supply Chest date save failed player=%s reason=%s",
			player.Name,
			tostring(saveReason)
		))
		return false, tostring(saveReason or "save_failed")
	end

	PopUpModule:Server_ShowReward(player, {
		{ "1x Supply Chest", RewardIconResolver.GetIcon("Supply Chest") },
	})
	PopUpModule:Server_SendPopUp(
		player,
		"Supply Chest added to your inventory!",
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(28, 170, 96),
		3,
		false
	)
	return true, "granted"
end

function ShopEntitlementService.Start(dataManager)
	if started then
		return
	end

	started = true
	dataManagerRef = dataManager

	promptConnection = MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamepassId, wasPurchased)
		if wasPurchased ~= true or player == nil or player.Parent ~= Players then
			return
		end

		local key = getShopGamepassKey(gamepassId)
		if key == nil then
			return
		end

		local ok, reason = ShopEntitlementService.ApplyGamepassEntitlement(player, key, dataManager)
		if ok ~= true then
			warn(string.format(
				"[ShopEntitlementService] Prompt entitlement failed player=%s gamepass=%s reason=%s",
				player.Name,
				tostring(gamepassId),
				tostring(reason)
			))
		end
	end)

	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		captainSupplyGrantInFlight[player] = nil
	end)
end

function ShopEntitlementService.Stop()
	if promptConnection then
		promptConnection:Disconnect()
		promptConnection = nil
	end
	if playerRemovingConnection then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end
	started = false
	dataManagerRef = nil
	table.clear(captainSupplyGrantInFlight)
end

return ShopEntitlementService
