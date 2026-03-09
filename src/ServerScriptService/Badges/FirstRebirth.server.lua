local BadgeService = game:GetService("BadgeService")
local Players = game:GetService("Players")

local BADGE_ID = 2282733907550036
local THRESHOLD = 1

local function tryAwardBadge(player, rebirthsValue)
	if not rebirthsValue then return end

	if rebirthsValue.Value < THRESHOLD then
		return
	end

	print("[RebirthBadge] Player meets requirement: " .. player.Name .. " (Rebirths = " .. rebirthsValue.Value .. ")")

	local success, hasBadge = pcall(function()
		return BadgeService:UserHasBadgeAsync(player.UserId, BADGE_ID)
	end)

	if not success then
		warn("[RebirthBadge] Failed to check badge for player: " .. player.Name)
		return
	end

	if hasBadge then
		print("[RebirthBadge] Player already has the badge: " .. player.Name)
		return
	end

	local awardSuccess, err = pcall(function()
		BadgeService:AwardBadge(player.UserId, BADGE_ID)
	end)

	if awardSuccess then
		print("[RebirthBadge] Badge awarded to player: " .. player.Name)
	else
		warn("[RebirthBadge] Failed to award badge to player: " .. player.Name .. " | Error: " .. tostring(err))
	end
end

Players.PlayerAdded:Connect(function(player)
	print("[RebirthBadge] Player joined: " .. player.Name)

	task.spawn(function()
		local leaderstats = player:WaitForChild("leaderstats", 15)
		if not leaderstats then
			warn("[RebirthBadge] leaderstats not found for player: " .. player.Name)
			return
		end

		local rebirths = leaderstats:WaitForChild("Rebirths", 15)
		if not rebirths or not rebirths:IsA("NumberValue") then
			warn("[RebirthBadge] Rebirths IntValue not found for player: " .. player.Name)
			return
		end

		tryAwardBadge(player, rebirths)

		rebirths.Changed:Connect(function()
			tryAwardBadge(player, rebirths)
		end)
	end)
end)
