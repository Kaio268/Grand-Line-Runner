local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CrewRewardService = require(script.Parent.Modules.CrewRewardService)
local data = require(script.Parent.Data.DataManager)
local RemoteGuard = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("RemoteGuard"))

local remote = ReplicatedStorage:FindFirstChild("RewardRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "RewardRemote"
	remote.Parent = ReplicatedStorage
end

remote.OnServerEvent:Connect(function(player)
	-- Security: free reward is server-calculated and guarded against spammed claims.
	if not RemoteGuard.Check(player, "RewardRemote", {}, {
		Cooldown = 2,
	}) then
		return
	end

	local claimed = data:GetValue(player, "HiddenLeaderstats.ClaimedTolilola")
	if claimed == true then
		return
	end

	local ok = CrewRewardService.Grant(player, "Fluri Flura", 1, {
		Source = "FreeReward",
		Context = "FreeReward",
	})
	if not ok then
		return
	end

	data:SetValue(player, "HiddenLeaderstats.ClaimedTolilola", true)
end)
