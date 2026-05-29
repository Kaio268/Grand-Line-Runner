local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Monetization"))
local ShopReceiptGrants = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ShopReceiptGrants"))
local TitleService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TitleService"))

local ShopEntitlementService = {}

local started = false
local dataManagerRef = nil
local promptConnection = nil

local VIP_GAMEPASS_ID = tonumber(MonetizationConfig.ActiveChefsGamepasses.VIP and MonetizationConfig.ActiveChefsGamepasses.VIP.Id)
local CAPTAIN_TITLE_ID = "Captain"
local DAILY_STATE_PATH = "DailyClaims.CaptainSupply.LastClaimDate"

local function getOrCreateRemotes()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = ReplicatedStorage
	end

	return remotes
end

local function getOrCreateRemoteFunction(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end

	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

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
		return setVip(player, dataManager, true)
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

function ShopEntitlementService.GetCaptainSupplyState(player, dataManager)
	dataManager = dataManager or dataManagerRef
	if dataManager == nil or typeof(dataManager.TryGetValue) ~= "function" then
		return {
			CanClaim = false,
			Reason = "data_manager_unavailable",
		}
	end

	if hasVip(player) ~= true then
		return {
			CanClaim = false,
			Reason = "captain_pass_required",
		}
	end

	local lastClaimDate = tostring(dataManager:TryGetValue(player, DAILY_STATE_PATH) or "")
	local today = todayUtc()
	return {
		CanClaim = lastClaimDate ~= today,
		LastClaimDate = lastClaimDate,
		CurrentDate = today,
		Reason = if lastClaimDate == today then "already_claimed" else nil,
	}
end

function ShopEntitlementService.ClaimCaptainSupply(player, dataManager)
	dataManager = dataManager or dataManagerRef
	local state = ShopEntitlementService.GetCaptainSupplyState(player, dataManager)
	if state.CanClaim ~= true then
		return {
			Ok = false,
			State = state,
			Reason = state.Reason,
		}
	end

	ShopReceiptGrants.GrantCaptainDailyChest(player, dataManager)
	local ok, reason = dataManager:TrySetValue(player, DAILY_STATE_PATH, todayUtc())
	if ok ~= true then
		return {
			Ok = false,
			State = ShopEntitlementService.GetCaptainSupplyState(player, dataManager),
			Reason = reason or "save_failed",
		}
	end

	return {
		Ok = true,
		State = ShopEntitlementService.GetCaptainSupplyState(player, dataManager),
	}
end

local function setupRemotes(dataManager)
	local remotes = getOrCreateRemotes()
	getOrCreateRemoteFunction(remotes, "CaptainSupplyStateRequest").OnServerInvoke = function(player)
		return ShopEntitlementService.GetCaptainSupplyState(player, dataManager)
	end
	getOrCreateRemoteFunction(remotes, "CaptainSupplyClaimRequest").OnServerInvoke = function(player)
		return ShopEntitlementService.ClaimCaptainSupply(player, dataManager)
	end
end

function ShopEntitlementService.Start(dataManager)
	if started then
		return
	end

	started = true
	dataManagerRef = dataManager
	setupRemotes(dataManager)

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
end

function ShopEntitlementService.Stop()
	if promptConnection then
		promptConnection:Disconnect()
		promptConnection = nil
	end
	started = false
	dataManagerRef = nil
end

return ShopEntitlementService
