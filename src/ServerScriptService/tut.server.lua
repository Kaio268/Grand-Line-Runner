-- Temporary server-side disable for the legacy tutorial completion handler.
-- The tutorial client flow is currently turned off, so this listener is kept
-- dormant to avoid mutating tutorial completion state while the system is
-- intentionally out of service.
local TEMPORARILY_DISABLE_TUTORIAL = true

if TEMPORARILY_DISABLE_TUTORIAL then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local data = require(script.Parent.Data.DataManager)
local remote = ReplicatedStorage:FindFirstChild("TutorialrrrrFinished")

if not remote then
	return
end

remote.OnServerEvent:Connect(function(player)
	local hls = player:FindFirstChild("HiddenLeaderstats")
	if not hls then
		return
	end

	data:SetValue(player, "HiddenLeaderstats.Tutorial", true)
end)
