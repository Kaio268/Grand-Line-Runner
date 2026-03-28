local DevilFruitAbilityRunner = {}

function DevilFruitAbilityRunner.Execute(params)
	local player = params.Player
	local fruitName = params.FruitName
	local abilityName = params.AbilityName
	local abilityConfig = params.AbilityConfig

	local context = params.GetContext(player, fruitName, abilityName, abilityConfig, params.RequestPayload, params.CharacterState, params.RequestMetadata)
	if not context then
		params.RequestGuard.RecordRejection(player, "InvalidContext", abilityName)
		params.FireDenied(player, fruitName, abilityName, "InvalidContext")
		return false
	end

	local abilityHandler = context.FruitHandler[abilityName]
	if typeof(abilityHandler) ~= "function" then
		params.RequestGuard.RecordRejection(player, "UnknownAbility", abilityName)
		params.FireDenied(player, fruitName, abilityName, "MissingHandler")
		return false
	end

	local isReady, readyAt = params.IsAbilityReady(player, abilityName)
	if not isReady then
		params.RequestGuard.RecordRejection(player, "Cooldown", abilityName)
		params.FireDenied(player, fruitName, abilityName, "Cooldown", readyAt)
		return false
	end

	local startsCooldownOnResolve = params.ShouldStartCooldownOnResolve(abilityConfig)
	local nextReadyAt = 0
	local reservedCooldown = false
	if not startsCooldownOnResolve then
		nextReadyAt = params.SetAbilityCooldown(player, abilityName, abilityConfig.Cooldown)
		reservedCooldown = true
	end

	local ok, payload, control = pcall(abilityHandler, context)
	if not ok then
		if reservedCooldown then
			params.ClearAbilityCooldown(player, abilityName)
		end
		params.Security.LogModuleFailure(fruitName, abilityName, payload)
		params.RequestGuard.RecordRejection(player, "ExecutionFailed", abilityName)
		params.FireDenied(player, fruitName, abilityName, "ExecutionFailed")
		return false
	end

	local applyCooldown = true
	local cooldownDuration = abilityConfig.Cooldown
	if typeof(control) == "table" then
		if control.ApplyCooldown == false then
			applyCooldown = false
		end

		local overrideDuration = tonumber(control.CooldownDuration)
		if overrideDuration then
			cooldownDuration = overrideDuration
		end
	end

	if startsCooldownOnResolve then
		if applyCooldown then
			nextReadyAt = params.SetAbilityCooldown(player, abilityName, cooldownDuration)
		else
			params.ClearAbilityCooldown(player, abilityName)
			nextReadyAt = 0
		end
	else
		if not applyCooldown then
			params.ClearAbilityCooldown(player, abilityName)
			nextReadyAt = 0
		elseif tonumber(cooldownDuration) and cooldownDuration ~= abilityConfig.Cooldown then
			nextReadyAt = params.SetAbilityCooldown(player, abilityName, cooldownDuration)
		end
	end

	params.FireActivated(player, fruitName, abilityName, nextReadyAt, payload)
	params.RequestGuard.RecordAccepted(player, fruitName, abilityName)
	return true
end

return DevilFruitAbilityRunner
