local LIMITED_REWARD_ENABLED = false

if LIMITED_REWARD_ENABLED ~= true then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.Data:WaitForChild("DataManager"))
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))

local rewardRemote = ReplicatedStorage:FindFirstChild("LimitedRewardClaim")
if rewardRemote and not rewardRemote:IsA("RemoteEvent") then
	warn("[LimitedReward] ReplicatedStorage.LimitedRewardClaim exists but is not a RemoteEvent.")
	rewardRemote = nil
end
if not rewardRemote then
	rewardRemote = Instance.new("RemoteEvent")
	rewardRemote.Name = "LimitedRewardClaim"
	rewardRemote.Parent = ReplicatedStorage
end
local PLACE_ID = game.PlaceId
local GROUP_ID = 17179624

local CrewRewardService = require(script.Parent.Parent.Modules.CrewRewardService)

local function sendClaimStatus(player, status)
	rewardRemote:FireClient(player, status)
end

rewardRemote.OnServerEvent:Connect(function(player, placeId)
	-- Security: never trust client-reported like/favorite state; gate on Roblox's server-verifiable group membership instead.
	if not RemoteGuard.Check(player, "LimitedRewardClaim", { placeId }, {
		Cooldown = 2,
		Args = {
			{ Type = "finiteNumber", Integer = true },
		},
	}) then
		return
	end

	if placeId ~= PLACE_ID then
		return
	end

	local already = DataManager:GetValue(player, "HiddenLeaderstats.LimitedReward")
	if already == true then
		sendClaimStatus(player, "AlreadyClaimed")
		return
	end

	if not player:IsInGroup(GROUP_ID) then
		sendClaimStatus(player, "NotInGroup")
		return
	end

	local ok = CrewRewardService.Grant(player, "Tatatata Sahur", 1, {
		Source = "LimitedReward",
		Context = "LimitedReward",
	})
	if not ok then
		sendClaimStatus(player, "Unavailable")
		return
	end

	DataManager:AddValue(player, "Potions.x2MoneyTime", 10 * 60)
	DataManager:AddValue(player, "Potions.x15WalkSpeedTime", 10 * 60)
	if typeof(DataManager.ResumeBoost) == "function" then
		DataManager:ResumeBoost(player, "x15WalkSpeed")
	end
	DataManager:SetValue(player, "HiddenLeaderstats.LimitedReward", true)
	sendClaimStatus(player, "Granted")
end)
