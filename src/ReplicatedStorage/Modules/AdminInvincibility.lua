local Players = game:GetService("Players")

local AdminInvincibility = {}

AdminInvincibility.AttributeName = "AdminInvincible"

local function getPlayerFromModel(model)
	if not model or not model:IsA("Model") then
		return nil
	end

	return Players:GetPlayerFromCharacter(model)
end

function AdminInvincibility.GetPlayer(target)
	if typeof(target) ~= "Instance" then
		return nil
	end

	if target:IsA("Player") then
		return target
	end

	if target:IsA("Model") then
		return getPlayerFromModel(target)
	end

	if target:IsA("Humanoid") then
		return getPlayerFromModel(target.Parent)
	end

	local ancestorModel = target:FindFirstAncestorOfClass("Model")
	return getPlayerFromModel(ancestorModel)
end

function AdminInvincibility.IsEnabled(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player:GetAttribute(AdminInvincibility.AttributeName) == true
end

function AdminInvincibility.IsTargetInvincible(target)
	return AdminInvincibility.IsEnabled(AdminInvincibility.GetPlayer(target))
end

return AdminInvincibility
