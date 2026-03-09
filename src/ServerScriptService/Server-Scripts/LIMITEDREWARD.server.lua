local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DataManager = require(ServerScriptService.Data:WaitForChild("DataManager"))
 
local rewardRemote = ReplicatedStorage:WaitForChild("LimitedRewardClaim")
local PLACE_ID = 129073777843683

local add = require(script.Parent.Parent.Modules.AddBrainrot)

rewardRemote.OnServerEvent:Connect(function(player, placeId, hasLike, hasFavorite)
	if placeId ~= PLACE_ID then
		return
	end
	if not hasLike or not hasFavorite then
		return
	end

	local already = DataManager:GetValue(player, "HiddenLeaderstats.LimitedReward")
	if already == true then
		return
	end

	DataManager:AddValue(player, "Potions.x2MoneyTime", 10 * 60)
	DataManager:AddValue(player, "Potions.x15WalkSpeedTime", 10 * 60)
	DataManager:SetValue(player, "HiddenLeaderstats.LimitedReward", true)

	add:AddBrainrot(player, "Tatatata Sahur", 1)
end)
