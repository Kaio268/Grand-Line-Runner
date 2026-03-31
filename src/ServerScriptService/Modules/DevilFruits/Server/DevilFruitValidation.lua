local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitLogger = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger")
)

local DevilFruitValidation = {}
local MERA_AUDIT_MARKER = "MERA_AUDIT_2026_03_30_V4"

local function shouldLogMeraAudit(fruitName, abilityName)
	return fruitName == "Mera Mera no Mi" or abilityName == "FlameDash" or abilityName == "FireBurst"
end

local function logMeraAudit(level, message, ...)
	local formattedMessage = string.format("[%s] " .. message, MERA_AUDIT_MARKER, ...)
	if level == "WARN" then
		DevilFruitLogger.Warn("SERVER", formattedMessage)
		return
	end

	DevilFruitLogger.Info("SERVER", formattedMessage)
end

function DevilFruitValidation.ValidateRequest(params)
	local player = params.Player
	local abilityName = params.AbilityName
	local requestPayload = params.RequestPayload
	local equippedFruitAtEntry = params.GetEquippedFruit(player)

	params.Security.LogAbilityRequestReceived(player, equippedFruitAtEntry, abilityName, requestPayload)
	params.Security.LogValidationStage(player, equippedFruitAtEntry, abilityName, "request_received", "continue", "received", requestPayload)
	if shouldLogMeraAudit(equippedFruitAtEntry, abilityName) then
		logMeraAudit(
			"INFO",
			"Mera validation entered player=%s fruit=%s ability=%s stage=request_received",
			player and player.Name or "<nil>",
			tostring(equippedFruitAtEntry),
			tostring(abilityName)
		)
	end

	local preflightOk, preflightReason, preflightReadyAt = params.RequestGuard.Preflight(player, abilityName, requestPayload)
	if not preflightOk then
		params.Security.LogValidationStage(player, equippedFruitAtEntry, abilityName, "preflight", "reject", preflightReason, requestPayload)
		if shouldLogMeraAudit(equippedFruitAtEntry, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera validation blocked player=%s fruit=%s ability=%s stage=preflight reason=%s",
				player and player.Name or "<nil>",
				tostring(equippedFruitAtEntry),
				tostring(abilityName),
				tostring(preflightReason)
			)
		end
		params.Security.LogInvalidAbilityRequest(player, params.GetEquippedFruit(player), abilityName, preflightReason, "preflight")
		params.FireDenied(player, params.GetEquippedFruit(player), abilityName, preflightReason, preflightReadyAt)
		return false
	end
	params.Security.LogValidationStage(player, equippedFruitAtEntry, abilityName, "preflight", "continue", "ok", requestPayload)

	local characterState, characterReason = params.GetAliveCharacterState(player)
	local equippedFruit = params.GetEquippedFruit(player)
	if not characterState then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "character_state", "reject", characterReason, requestPayload)
		if shouldLogMeraAudit(equippedFruit, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera validation blocked player=%s fruit=%s ability=%s stage=character_state reason=%s",
				player and player.Name or "<nil>",
				tostring(equippedFruit),
				tostring(abilityName),
				tostring(characterReason)
			)
		end
		params.RequestGuard.RecordRejection(player, "InvalidContext", characterReason)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, characterReason, "context")
		params.FireDenied(player, equippedFruit, abilityName, "InvalidContext")
		return false
	end
	params.Security.LogValidationStage(player, equippedFruit, abilityName, "character_state", "continue", "ok", requestPayload)

	if equippedFruit == params.NoneFruitName then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "equipped_fruit", "reject", "NoFruit", requestPayload)
		if shouldLogMeraAudit(equippedFruit, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera validation blocked player=%s fruit=%s ability=%s stage=equipped_fruit reason=NoFruit",
				player and player.Name or "<nil>",
				tostring(equippedFruit),
				tostring(abilityName)
			)
		end
		params.RequestGuard.RecordRejection(player, "NoFruit", abilityName)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, "NoFruit", "equipped")
		params.FireDenied(player, equippedFruit, abilityName, "NoFruit")
		return false
	end

	local abilityConfig = params.GetAbilityConfig(equippedFruit, abilityName)
	if not abilityConfig then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "ability_config", "reject", "UnknownAbility", requestPayload)
		if shouldLogMeraAudit(equippedFruit, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera validation blocked player=%s fruit=%s ability=%s stage=ability_config reason=UnknownAbility",
				player and player.Name or "<nil>",
				tostring(equippedFruit),
				tostring(abilityName)
			)
		end
		params.RequestGuard.RecordRejection(player, "UnknownAbility", abilityName)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, "UnknownAbility", "config")
		params.FireDenied(player, equippedFruit, abilityName, "UnknownAbility")
		return false
	end
	params.Security.LogValidationStage(player, equippedFruit, abilityName, "ability_config", "continue", "ok", requestPayload)

	local requestAllowed, sanitizedPayload, rejectionReason, rejectionReadyAt = params.RequestGuard.ValidateAndReserve(
		player,
		equippedFruit,
		abilityName,
		abilityConfig,
		requestPayload,
		characterState
	)
	if not requestAllowed then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "guard_validate", "reject", rejectionReason, requestPayload)
		if shouldLogMeraAudit(equippedFruit, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera validation blocked player=%s fruit=%s ability=%s stage=guard_validate reason=%s",
				player and player.Name or "<nil>",
				tostring(equippedFruit),
				tostring(abilityName),
				tostring(rejectionReason)
			)
		end
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, rejectionReason, "validate")
		params.FireDenied(player, equippedFruit, abilityName, rejectionReason, rejectionReadyAt)
		return false
	end
	params.Security.LogValidationStage(player, equippedFruit, abilityName, "guard_validate", "continue", "ok", sanitizedPayload)
	if shouldLogMeraAudit(equippedFruit, abilityName) then
		logMeraAudit(
			"INFO",
			"Mera validation success player=%s fruit=%s ability=%s stage=guard_validate",
			player and player.Name or "<nil>",
			tostring(equippedFruit),
			tostring(abilityName)
		)
	end

	return true, {
		CharacterState = characterState,
		EquippedFruit = equippedFruit,
		AbilityConfig = abilityConfig,
		SanitizedPayload = sanitizedPayload,
	}
end

return DevilFruitValidation
