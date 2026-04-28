local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitLogger = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger")
)

local DevilFruitValidation = {}

local function shouldBypassRequestThrottle(params, player, fruitName, abilityName, abilityConfig, requestPayload, characterState)
	local getContext = params.GetContext
	if typeof(getContext) ~= "function" then
		return false
	end

	local context = getContext(player, fruitName, abilityName, abilityConfig, requestPayload, characterState, nil)
	if type(context) ~= "table" then
		return false
	end

	local fruitHandler = context.FruitHandler
	local method = fruitHandler and fruitHandler.ShouldBypassRequestThrottle
	if typeof(method) ~= "function" then
		return false
	end

	local ok, result = pcall(method, fruitHandler, context)
	if not ok then
		DevilFruitLogger.Warn(
			"SERVER",
			"request throttle bypass check failed fruit=%s ability=%s err=%s",
			tostring(fruitName),
			tostring(abilityName),
			tostring(result)
		)
		return false
	end

	return result == true
end

function DevilFruitValidation.ValidateRequest(params)
	local player = params.Player
	local abilityName = params.AbilityName
	local requestPayload = params.RequestPayload
	local equippedFruitAtEntry = params.GetEquippedFruit(player)

	params.Security.LogAbilityRequestReceived(player, equippedFruitAtEntry, abilityName, requestPayload)
	params.Security.LogValidationStage(player, equippedFruitAtEntry, abilityName, "request_received", "continue", "received", requestPayload)

	local preflightOk, preflightReason, preflightReadyAt = params.RequestGuard.Preflight(player, abilityName, requestPayload)
	if not preflightOk then
		params.Security.LogValidationStage(player, equippedFruitAtEntry, abilityName, "preflight", "reject", preflightReason, requestPayload)
		params.Security.LogInvalidAbilityRequest(player, params.GetEquippedFruit(player), abilityName, preflightReason, "preflight")
		params.FireDenied(player, params.GetEquippedFruit(player), abilityName, preflightReason, preflightReadyAt)
		return false
	end
	params.Security.LogValidationStage(player, equippedFruitAtEntry, abilityName, "preflight", "continue", "ok", requestPayload)

	local characterState, characterReason = params.GetAliveCharacterState(player)
	local equippedFruit = params.GetEquippedFruit(player)
	if not characterState then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "character_state", "reject", characterReason, requestPayload)
		params.RequestGuard.RecordRejection(player, "InvalidContext", characterReason)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, characterReason, "context")
		params.FireDenied(player, equippedFruit, abilityName, "InvalidContext")
		return false
	end
	params.Security.LogValidationStage(player, equippedFruit, abilityName, "character_state", "continue", "ok", requestPayload)

	if equippedFruit == params.NoneFruitName then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "equipped_fruit", "reject", "NoFruit", requestPayload)
		params.RequestGuard.RecordRejection(player, "NoFruit", abilityName)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, "NoFruit", "equipped")
		params.FireDenied(player, equippedFruit, abilityName, "NoFruit")
		return false
	end

	local abilityConfig = params.GetAbilityConfig(equippedFruit, abilityName)
	if not abilityConfig then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "ability_config", "reject", "UnknownAbility", requestPayload)
		params.RequestGuard.RecordRejection(player, "UnknownAbility", abilityName)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, "UnknownAbility", "config")
		params.FireDenied(player, equippedFruit, abilityName, "UnknownAbility")
		return false
	end
	params.Security.LogValidationStage(player, equippedFruit, abilityName, "ability_config", "continue", "ok", requestPayload)

	local bypassRequestThrottle = shouldBypassRequestThrottle(
		params,
		player,
		equippedFruit,
		abilityName,
		abilityConfig,
		requestPayload,
		characterState
	)
	local requestAllowed, sanitizedPayload, rejectionReason, rejectionReadyAt = params.RequestGuard.ValidateAndReserve(
		player,
		equippedFruit,
		abilityName,
		abilityConfig,
		requestPayload,
		characterState,
		{
			BypassRequestThrottle = bypassRequestThrottle,
		}
	)
	if not requestAllowed then
		params.Security.LogValidationStage(player, equippedFruit, abilityName, "guard_validate", "reject", rejectionReason, requestPayload)
		params.Security.LogInvalidAbilityRequest(player, equippedFruit, abilityName, rejectionReason, "validate")
		params.FireDenied(player, equippedFruit, abilityName, rejectionReason, rejectionReadyAt)
		return false
	end
	params.Security.LogValidationStage(player, equippedFruit, abilityName, "guard_validate", "continue", "ok", sanitizedPayload)

	return true, {
		CharacterState = characterState,
		EquippedFruit = equippedFruit,
		AbilityConfig = abilityConfig,
		SanitizedPayload = sanitizedPayload,
	}
end

return DevilFruitValidation
