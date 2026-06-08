local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local ChestService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local RewardIconResolver = require(Modules:WaitForChild("RewardIconResolver"))
local SocialGroups = require(Modules:WaitForChild("Configs"):WaitForChild("SocialGroups"))

local GroupLikeRewardService = {}

local REMOTE_NAME = "GroupLikeRewardRequest"
local REMOTES_FOLDER_NAME = "Remotes"
local CLAIM_PATH = "SocialRewards.GroupLikeLuffy.Claimed"
local CLAIMED_AT_PATH = "SocialRewards.GroupLikeLuffy.ClaimedAtUnix"
local REWARD_CONFIG = SocialGroups.GroupLikeReward or {}
local GROUP_ID = tonumber(REWARD_CONFIG.GroupId) or tonumber(SocialGroups.GroupLikeRewardGroupId) or 0
local REWARD_TIER = tostring(REWARD_CONFIG.RewardTier or "Gold")
local REWARD_AMOUNT = math.max(1, math.floor(tonumber(REWARD_CONFIG.RewardAmount) or 100))
local REWARD_SOURCE = tostring(REWARD_CONFIG.Source or "GroupLikeLuffy")
local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

local started = false
local requestRemote
local claimLocks = {}
local REQUEST_ACTION_ALLOWLIST = {
	GetState = true,
	Claim = true,
}

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = REMOTES_FOLDER_NAME
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemote(parent, className, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote.ClassName == className then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function ensureRemotes()
	local remotes = getOrCreateRemotesFolder()
	requestRemote = getOrCreateRemote(remotes, "RemoteFunction", REMOTE_NAME)
end

local function checkGroupMembership(player)
	if GROUP_ID <= 0 then
		return false, "missing_group_id"
	end

	local ok, inGroup = pcall(function()
		return player:IsInGroup(GROUP_ID)
	end)
	if not ok then
		warn(string.format("[GroupLikeRewardService] Group membership check failed for %s: %s", player.Name, tostring(inGroup)))
		return false, "group_check_failed"
	end

	return inGroup == true, nil
end

local function buildClientState(player)
	local dataReady = DataManager:IsReady(player)
	local claimed = false
	local claimedAtUnix = 0
	if dataReady then
		local claimedValue = DataManager:TryGetValue(player, CLAIM_PATH)
		local claimedAtValue = DataManager:TryGetValue(player, CLAIMED_AT_PATH)
		claimed = claimedValue == true
		claimedAtUnix = math.max(0, math.floor(tonumber(claimedAtValue) or 0))
	end

	local inGroup, groupReason = checkGroupMembership(player)
	return {
		dataReady = dataReady,
		claimed = claimed,
		claimedAtUnix = claimedAtUnix,
		inGroup = inGroup == true,
		groupCheckReason = groupReason,
		groupId = GROUP_ID,
		rewardTier = REWARD_TIER,
		rewardAmount = REWARD_AMOUNT,
		rewardDisplayName = string.format("%d Gold Chests", REWARD_AMOUNT),
		likeVerification = "instruction_only",
	}
end

local function makeResponse(player, ok, message, errorCode)
	return {
		ok = ok == true,
		message = message,
		error = errorCode,
		state = buildClientState(player),
	}
end

local function sendPopup(player, text, isError)
	if player.Parent ~= Players then
		return
	end

	PopUpModule:Server_SendPopUp(
		player,
		text,
		if isError then ERROR_COLOR else SUCCESS_COLOR,
		STROKE_COLOR,
		3,
		isError == true
	)
end

local function claimInternal(player)
	if not DataManager:WaitUntilReady(player, 10) then
		sendPopup(player, "Data is still loading. Try again soon.", true)
		return makeResponse(player, false, "Data is still loading.", "profile_not_ready")
	end

	local state = buildClientState(player)
	if state.claimed == true then
		sendPopup(player, "You already claimed this reward.", true)
		return makeResponse(player, false, "You already claimed this reward.", "already_claimed")
	end

	if state.inGroup ~= true then
		sendPopup(player, "Join the Roblox group first. If you just joined, retry soon.", true)
		return makeResponse(player, false, "Join the Roblox group first.", state.groupCheckReason or "not_in_group")
	end

	local grantResponse = ChestService.GrantChestOnce(player, REWARD_TIER, REWARD_AMOUNT, nil, {
		Source = REWARD_SOURCE,
		ClaimPath = CLAIM_PATH,
		ClaimedAtPath = CLAIMED_AT_PATH,
		AlreadyClaimedMessage = "You already claimed this reward.",
	})

	if typeof(grantResponse) ~= "table" then
		sendPopup(player, "Reward claim failed. Try again soon.", true)
		return makeResponse(player, false, "Reward claim failed.", "grant_failed")
	end

	if grantResponse.ok ~= true then
		local message = tostring(grantResponse.message or "Reward claim failed.")
		sendPopup(player, message, true)
		return makeResponse(player, false, message, tostring(grantResponse.error or "grant_failed"))
	end

	local rewardText = string.format("%dx Gold Chests", REWARD_AMOUNT)
	PopUpModule:Server_ShowReward(player, {
		{ rewardText, RewardIconResolver.GetIcon("Gold Chest") },
	})
	sendPopup(player, "Reward received: 100 Gold Chests!", false)
	return makeResponse(player, true, "Reward received: 100 Gold Chests.", nil)
end

local function claim(player)
	if claimLocks[player] == true then
		return makeResponse(player, false, "Claim is already processing.", "busy")
	end

	claimLocks[player] = true
	local ok, response = pcall(claimInternal, player)
	claimLocks[player] = nil

	if ok then
		return response
	end

	warn(string.format("[GroupLikeRewardService] Claim failed for %s: %s", player.Name, tostring(response)))
	sendPopup(player, "Reward claim failed. Try again soon.", true)
	return makeResponse(player, false, "Reward claim failed.", "server_error")
end

local function handleRequest(player, actionName)
	if not RemoteGuard.Check(player, REMOTE_NAME, { actionName }, {
		Cooldown = 0.1,
		ActionIndex = 1,
		ActionAllowlist = REQUEST_ACTION_ALLOWLIST,
		Args = {
			{ Type = "string", MaxLength = 32 },
		},
	}) then
		return makeResponse(player, false, "Invalid reward request.", "remote_guard_rejected")
	end

	if actionName == "GetState" then
		return makeResponse(player, true, nil, nil)
	elseif actionName == "Claim" then
		return claim(player)
	end

	return makeResponse(player, false, "Unknown reward request.", "unknown_action")
end

function GroupLikeRewardService.Start()
	if started then
		return
	end
	started = true

	ensureRemotes()
	requestRemote.OnServerInvoke = function(player, actionName)
		return handleRequest(player, actionName)
	end

	Players.PlayerRemoving:Connect(function(player)
		claimLocks[player] = nil
	end)
end

function GroupLikeRewardService.Stop()
	if requestRemote then
		requestRemote.OnServerInvoke = nil
	end
	started = false
end

return GroupLikeRewardService
