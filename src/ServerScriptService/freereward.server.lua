local ReplicatedStorage = game:GetService("ReplicatedStorage")
local add = require(script.Parent.Modules.AddBrainrot)
local data = require(script.Parent.Data.DataManager)

local remote = ReplicatedStorage:FindFirstChild("RewardRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "RewardRemote"
	remote.Parent = ReplicatedStorage
end

remote.OnServerEvent:Connect(function(player)
	local claimed = data:GetValue(player, "HiddenLeaderstats.ClaimedTolilola")
	if claimed == true then
		return
	end

	data:SetValue(player, "HiddenLeaderstats.ClaimedTolilola", true)
	add:AddBrainrot(player, "Fluri Flura", 1)
end)
