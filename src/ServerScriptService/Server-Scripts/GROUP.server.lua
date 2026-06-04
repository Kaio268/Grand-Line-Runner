local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local RewardIconResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RewardIconResolver"))
local SocialGroups = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SocialGroups"))
local ddata = require(script.Parent.Parent.Data.DataManager)
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))
local GROUP_ID = SocialGroups.GroupRewardGroupId
local REMOTE_NAME = "GroupRewardClaim"

local CrewRewardService = require(script.Parent.Parent.Modules.CrewRewardService)
local remoteEvent = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = REMOTE_NAME
	remoteEvent.Parent = ReplicatedStorage
end


remoteEvent.OnServerEvent:Connect(function(player)
	-- Security: group reward is server-verified with IsInGroup and guarded against spammed claims.
	if not RemoteGuard.Check(player, "GroupRewardClaim", {}, {
		Cooldown = 2,
	}) then
		return
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	if not player:IsInGroup(GROUP_ID) then
		print(player.Name .. " tried to claim the group reward without being in the group.")
		PopUpModule:Server_SendPopUp(player, "Join the group first.", Color3.fromRGB(255, 60, 60), Color3.fromRGB(0, 0, 0), 3, true)
		return
	end

	local groupValue = player.HiddenLeaderstats.Group

	if groupValue.Value == false then
		print("Reward received for " .. player.Name)
		local ok, resolved = CrewRewardService.Grant(player, "Cappuccino Assassino", 1, {
			Source = "GroupReward",
			Context = "GroupReward",
		})
		if not ok then
			PopUpModule:Server_SendPopUp(player, "Crew reward unavailable right now.", Color3.fromRGB(255, 60, 60), Color3.fromRGB(0, 0, 0), 3, true)
			return
		end

		ddata:SetValue(player, "HiddenLeaderstats.Group", true)
		local rewardName = tostring(resolved.DisplayName or "Crewmate")
		PopUpModule:Server_ShowReward(player, {
			{ "1x " .. rewardName, RewardIconResolver.GetIcon({
				Type = "Crew",
				DisplayName = rewardName,
			}) },
		})
		PopUpModule:Server_SendPopUp(player, "Reward received: " .. tostring(resolved.DisplayName) .. "!", Color3.fromRGB(60, 255, 60), Color3.fromRGB(0, 0, 0), 3, false)
	else
		print("Reward already claimed by " .. player.Name .. ". Cannot claim again.")
		PopUpModule:Server_SendPopUp(player, "You already claimed this reward.", Color3.fromRGB(255, 60, 60), Color3.fromRGB(0, 0, 0), 3, true)
	end
end)
