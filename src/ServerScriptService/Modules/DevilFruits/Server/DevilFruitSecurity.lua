local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DevilFruitLogger"))

local DevilFruitSecurity = {}

local function countPayloadKeys(payload)
	if typeof(payload) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(payload) do
		count += 1
	end

	return count
end

function DevilFruitSecurity.LogAbilityRequestReceived(player, fruitName, abilityName, payload)
	DevilFruitLogger.Info(
		"SERVER",
		"ability request received player=%s fruit=%s ability=%s payloadKeys=%d",
		player and player.Name or "<nil>",
		tostring(fruitName),
		tostring(abilityName),
		countPayloadKeys(payload)
	)
end

function DevilFruitSecurity.LogInvalidAbilityRequest(player, fruitName, abilityName, reason, stage)
	DevilFruitLogger.Warn(
		"SERVER",
		"invalid ability request player=%s fruit=%s ability=%s reason=%s stage=%s",
		player and player.Name or "<nil>",
		tostring(fruitName),
		tostring(abilityName),
		tostring(reason),
		tostring(stage)
	)

	if reason == "RateLimited" or reason == "TemporarilyIgnored" or reason == "BurstLimited" then
		DevilFruitLogger.Warn(
			"SECURITY",
			"rate limit hit player=%s fruit=%s ability=%s reason=%s stage=%s",
			player and player.Name or "<nil>",
			tostring(fruitName),
			tostring(abilityName),
			tostring(reason),
			tostring(stage)
		)
	end
end

function DevilFruitSecurity.LogModuleFailure(fruitName, abilityName, err)
	DevilFruitLogger.Error(
		"SERVER",
		"fruit module failure fruit=%s ability=%s err=%s",
		tostring(fruitName),
		tostring(abilityName),
		tostring(err)
	)
end

return DevilFruitSecurity
