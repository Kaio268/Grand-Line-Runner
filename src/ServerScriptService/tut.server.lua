local ReplicatedStorage = game:GetService("ReplicatedStorage")
local data = require(script.Parent.Data.DataManager)
local remote = ReplicatedStorage:FindFirstChild("TutorialrrrrFinished")
 
remote.OnServerEvent:Connect(function(player)
	local hls = player:FindFirstChild("HiddenLeaderstats")
	if not hls then return end

	data:SetValue(player, "HiddenLeaderstats.Tutorial", true)
end)
