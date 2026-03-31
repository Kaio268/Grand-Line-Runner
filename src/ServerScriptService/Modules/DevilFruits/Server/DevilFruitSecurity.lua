local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))

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

local function summarizePayload(payload)
	if typeof(payload) ~= "table" then
		return string.format("type=%s", typeof(payload))
	end

	local keyParts = {}
	local count = 0
	for key in pairs(payload) do
		count += 1
		if #keyParts < 4 then
			keyParts[#keyParts + 1] = tostring(key)
		end
	end

	table.sort(keyParts)
	return string.format("type=table keys=%d fields=%s", count, table.concat(keyParts, ","))
end

function DevilFruitSecurity.LogAbilityRequestReceived(player, fruitName, abilityName, payload)
	DevilFruitLogger.Info(
		"SERVER",
		"ability request received player=%s fruit=%s ability=%s payloadKeys=%d payload=%s",
		player and player.Name or "<nil>",
		tostring(fruitName),
		tostring(abilityName),
		countPayloadKeys(payload),
		summarizePayload(payload)
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

function DevilFruitSecurity.LogValidationStage(player, fruitName, abilityName, stage, outcome, detail, payload)
	local logger = outcome == "reject" and DevilFruitLogger.Warn or DevilFruitLogger.Info
	logger(
		"SERVER",
		"validation stage=%s outcome=%s player=%s fruit=%s ability=%s detail=%s payload=%s",
		tostring(stage),
		tostring(outcome),
		player and player.Name or "<nil>",
		tostring(fruitName),
		tostring(abilityName),
		tostring(detail),
		summarizePayload(payload)
	)
end

function DevilFruitSecurity.LogExecutionStage(player, fruitName, abilityName, stage, detail, payload)
	DevilFruitLogger.Info(
		"MOVE",
		"execution stage=%s player=%s fruit=%s ability=%s detail=%s payload=%s",
		tostring(stage),
		player and player.Name or "<nil>",
		tostring(fruitName),
		tostring(abilityName),
		tostring(detail),
		summarizePayload(payload)
	)
end

return DevilFruitSecurity
