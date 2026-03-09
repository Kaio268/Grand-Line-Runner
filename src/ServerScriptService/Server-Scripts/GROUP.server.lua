local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
local ddata = require(script.Parent.Parent.Data.DataManager)
local GROUP_ID = 17179624
local REMOTE_NAME = "GroupRewardClaim"

local brot = require(script.Parent.Parent.Modules.AddBrainrot)
local remoteEvent = ReplicatedStorage:FindFirstChild(REMOTE_NAME)
if not remoteEvent then
	remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = REMOTE_NAME
	remoteEvent.Parent = ReplicatedStorage
end


remoteEvent.OnServerEvent:Connect(function(player)
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
		ddata:SetValue(player, "HiddenLeaderstats.Group", true)
		brot:AddBrainrot(player, "Cappuccino Assassino", 1)
		PopUpModule:Server_SendPopUp(player, "Reward received!", Color3.fromRGB(60, 255, 60), Color3.fromRGB(0, 0, 0), 3, false)
	else
		print("Reward already claimed by " .. player.Name .. ". Cannot claim again.")
		PopUpModule:Server_SendPopUp(player, "You already claimed this reward.", Color3.fromRGB(255, 60, 60), Color3.fromRGB(0, 0, 0), 3, true)
	end
end)
