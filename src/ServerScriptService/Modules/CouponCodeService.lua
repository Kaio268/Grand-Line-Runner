local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Codes = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("Codes"))
local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local SocialGroups = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SocialGroups"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local ShopReceiptGrants = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("ShopReceiptGrants"))

local CouponCodeService = {}

local REMOTE_NAME = "RedeemCodeRequest"
local MAX_CODE_LENGTH = 48
local started = false
local dataManager = nil
local redemptionInFlight = setmetatable({}, { __mode = "k" })

local function trim(value)
	return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function normalizeCode(value)
	return string.upper(trim(value))
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

local function getOrCreateRemoteFunction(parent, remoteName)
	local remote = parent:FindFirstChild(remoteName)
	if remote and not remote:IsA("RemoteFunction") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteFunction")
		remote.Name = remoteName
		remote.Parent = parent
	end

	return remote
end

local function getCodeEntry(normalizedCode)
	local entry = Codes[normalizedCode]
	if typeof(entry) == "table" then
		return normalizedCode, entry
	end

	for rawCode, rawEntry in pairs(Codes) do
		if normalizeCode(rawCode) == normalizedCode and typeof(rawEntry) == "table" then
			return tostring(rawCode), rawEntry
		end
	end

	return nil, nil
end

local function getExpiryUnix(entry)
	local unix = tonumber(entry.ExpiresAtUnix or entry.ExpiresAt)
	if unix ~= nil then
		return math.floor(unix)
	end

	local iso = entry.ExpiresAtIso or entry.ExpiresAtUTC
	if iso == nil and typeof(entry.ExpiresAt) == "string" then
		iso = entry.ExpiresAt
	end
	if typeof(iso) == "string" and iso ~= "" then
		local ok, dateTime = pcall(DateTime.fromIsoDate, iso)
		if ok and dateTime then
			return dateTime.UnixTimestamp
		end
	end

	return nil
end

local function isExpired(entry)
	local expiresAt = getExpiryUnix(entry)
	return expiresAt ~= nil and expiresAt > 0 and os.time() >= expiresAt
end

local function canRedeemGroupCode(player)
	local groupId = tonumber(SocialGroups.GroupRewardGroupId)
	if groupId == nil or groupId <= 0 then
		return true
	end

	local ok, inGroup = pcall(function()
		return player:IsInGroup(groupId)
	end)

	return ok and inGroup == true
end

local function getRedeemedCodes(player)
	local redeemedCodes = dataManager:TryGetValue(player, "RedeemedCodes")
	if typeof(redeemedCodes) ~= "table" then
		redeemedCodes = {}
	end
	return redeemedCodes
end

local function markRedeemed(player, redeemedCodes, normalizedCode)
	local nextRedeemed = table.clone(redeemedCodes)
	nextRedeemed[normalizedCode] = {
		RedeemedAt = os.time(),
	}
	return dataManager:TrySetValue(player, "RedeemedCodes", nextRedeemed)
end

local function buildChestSummary(chestData, amount)
	local displayName = ChestUtils.GetDisplayName(chestData)
	return string.format("%dx %s", math.max(1, math.floor(tonumber(amount) or 1)), displayName)
end

local function grantChestRewards(player, profile, rewards)
	local chests = rewards and rewards.Chests
	if typeof(chests) ~= "table" then
		return false, "missing_chests"
	end

	if chests[1] == nil and (chests.Tier ~= nil or chests.ChestKind ~= nil or chests.FruitRarity ~= nil) then
		chests = { chests }
	end

	local granted = {}
	for _, rawChest in ipairs(chests) do
		if typeof(rawChest) == "table" then
			local amount = math.max(1, math.floor(tonumber(rawChest.Amount) or 1))
			local chestData = ChestUtils.BuildChestData({
				ChestKind = rawChest.ChestKind or ChestRewards.ChestKinds.Standard,
				Tier = rawChest.Tier,
				FruitRarity = rawChest.FruitRarity,
				Source = "Code",
				RewardProfile = rawChest.RewardProfile,
			})

			local ok, reason = ShopReceiptGrants.GrantChest(player, profile, dataManager, chestData, amount)
			if ok ~= true then
				return false, reason
			end
			granted[#granted + 1] = buildChestSummary(chestData, amount)
		end
	end

	if #granted == 0 then
		return false, "missing_chests"
	end
	return true, table.concat(granted, ", ")
end

local function makeResponse(ok, message, errorCode)
	return {
		ok = ok == true,
		message = tostring(message or ""),
		error = errorCode,
	}
end

local function redeemUnlocked(player, rawCode)
	if not RemoteGuard.Check(player, REMOTE_NAME, { rawCode }, {
		Cooldown = 0.75,
		Args = {
			{ Type = "string", MaxLength = MAX_CODE_LENGTH },
		},
	}) then
		return makeResponse(false, "Please wait and try again.", "remote_guard_rejected")
	end

	local normalizedCode = normalizeCode(rawCode)
	if normalizedCode == "" then
		return makeResponse(false, "Enter a code first.", "empty_code")
	end

	local storedCode, entry = getCodeEntry(normalizedCode)
	if entry == nil then
		return makeResponse(false, "That code is not valid.", "invalid_code")
	end

	if entry.Disabled == true then
		return makeResponse(false, "That code is not active.", "disabled")
	end

	if isExpired(entry) then
		return makeResponse(false, "That code has expired.", "expired")
	end

	if not canRedeemGroupCode(player) then
		return makeResponse(false, "Join our Roblox group to claim codes.", "not_in_group")
	end

	if not dataManager:WaitUntilReady(player, 10) then
		return makeResponse(false, "Your data is still loading.", "data_not_ready")
	end

	local redeemedCodes = getRedeemedCodes(player)
	if redeemedCodes[normalizedCode] ~= nil or redeemedCodes[storedCode] ~= nil then
		return makeResponse(false, "You already redeemed that code.", "already_redeemed")
	end

	local profile = dataManager:TryGetProfile(player)
	if profile == nil or typeof(profile.Data) ~= "table" then
		return makeResponse(false, "Your data is still loading.", "profile_not_ready")
	end

	local marked, markReason = markRedeemed(player, redeemedCodes, normalizedCode)
	if marked ~= true then
		return makeResponse(false, "Code redemption could not be saved.", tostring(markReason or "redeem_save_failed"))
	end

	local grantOk, granted, grantSummaryOrReason = pcall(grantChestRewards, player, profile, entry.Rewards)
	if not grantOk then
		local grantError = granted
		granted = false
		grantSummaryOrReason = "grant_error"
		warn("[CouponCodeService] grant failed: " .. tostring(grantError))
	end

	if granted ~= true then
		dataManager:TrySetValue(player, "RedeemedCodes", redeemedCodes)
		return makeResponse(false, "Code reward could not be granted.", tostring(grantSummaryOrReason or "grant_failed"))
	end

	return makeResponse(true, "Redeemed " .. grantSummaryOrReason .. ".", nil)
end

local function redeem(player, rawCode)
	if redemptionInFlight[player] == true then
		return makeResponse(false, "Please wait and try again.", "redemption_in_progress")
	end

	redemptionInFlight[player] = true
	local ok, response = pcall(redeemUnlocked, player, rawCode)
	redemptionInFlight[player] = nil

	if ok and typeof(response) == "table" then
		return response
	end

	warn("[CouponCodeService] redeem failed: " .. tostring(response))
	return makeResponse(false, "Code redeem failed. Try again.", "redeem_error")
end

function CouponCodeService.Start(manager)
	if started then
		return
	end

	started = true
	dataManager = manager

	local remotes = getOrCreateRemotesFolder()
	local remote = getOrCreateRemoteFunction(remotes, REMOTE_NAME)
	remote.OnServerInvoke = redeem
end

return CouponCodeService
