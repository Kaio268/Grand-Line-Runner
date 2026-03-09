local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local BADGE_ID = 4487485248895611

Players.PlayerAdded:Connect(function(player)
	print("[Badge] Player joined: " .. player.Name)

	local success, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, BADGE_ID)
	end)

	if not success then
		warn("[Badge] Failed to check badge for player: " .. player.Name)
		return
	end

	if hasBadge then
		print("[Badge] Player already has the badge: " .. player.Name)
		return
	end

	local awardSuccess, err = pcall(function()
		BadgeService:AwardBadge(player.UserId, BADGE_ID)
	end)

	if awardSuccess then
		print("[Badge] Badge awarded to player: " .. player.Name)
	else
		warn("[Badge] Failed to award badge to player: " .. player.Name .. " | Error: " .. tostring(err))
	end
end)
