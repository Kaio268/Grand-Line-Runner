local DevilFruitValidation = {}

function DevilFruitValidation.ValidateRequest(params)
	local player = params.Player
	local abilityName = params.AbilityName
	local requestPayload = params.RequestPayload

	params.Security.LogAbilityRequestReceived(player, params.GetEquippedFruit(player), abilityName, requestPayload)

	local preflightOk, preflightReason, preflightReadyAt = params.RequestGuard.Preflight(player, abilityName, requestPayload)
	if not preflightOk then
		params.Security.LogInvalidAbilityRequest(player, params.GetEquippedFruit(player), abilityName, preflightReason, "preflight")
		params.FireDenied(player, params.GetEquippedFruit(player), abilityName, preflightReason, preflightReadyAt)
		return false
	end

	local characterState, characterReason = params.GetAliveCharacterState(player)
	local equippedFruit = params.GetEquippedFruit(player)
	if not characterState then
		params.RequestGuard.RecordRejection(player, "InvalidContext", characterReason)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, characterReason, "context")
		params.FireDenied(player, equippedFruit, abilityName, "InvalidContext")
		return false
	end

	if equippedFruit == params.NoneFruitName then
		params.RequestGuard.RecordRejection(player, "NoFruit", abilityName)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, "NoFruit", "equipped")
		params.FireDenied(player, equippedFruit, abilityName, "NoFruit")
		return false
	end

	local abilityConfig = params.GetAbilityConfig(equippedFruit, abilityName)
	if not abilityConfig then
		params.RequestGuard.RecordRejection(player, "UnknownAbility", abilityName)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, "UnknownAbility", "config")
		params.FireDenied(player, equippedFruit, abilityName, "UnknownAbility")
		return false
	end

	local requestAllowed, sanitizedPayload, rejectionReason, rejectionReadyAt = params.RequestGuard.ValidateAndReserve(
		player,
		equippedFruit,
		abilityName,
		abilityConfig,
		requestPayload,
		characterState
	)
	if not requestAllowed then
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, rejectionReason, "validate")
		params.FireDenied(player, equippedFruit, abilityName, rejectionReason, rejectionReadyAt)
		return false
	end

	return true, {
		CharacterState = characterState,
		EquippedFruit = equippedFruit,
		AbilityConfig = abilityConfig,
		SanitizedPayload = sanitizedPayload,
	}
end

return DevilFruitValidation
