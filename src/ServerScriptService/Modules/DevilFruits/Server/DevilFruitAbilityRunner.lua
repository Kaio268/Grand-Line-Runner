local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitLogger = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger")
)

local DevilFruitAbilityRunner = {}
local MERA_AUDIT_MARKER = "MERA_AUDIT_2026_03_30_V4"

local function shouldLogMeraAudit(fruitName, abilityName)
	return fruitName == "Mera Mera no Mi" or abilityName == "FlameDash" or abilityName == "FireBurst"
end

local function logMeraAudit(level, message, ...)
	local formattedMessage = string.format("[%s] " .. message, MERA_AUDIT_MARKER, ...)
	if level == "WARN" then
		DevilFruitLogger.Warn("MOVE", formattedMessage)
		return
	end

	DevilFruitLogger.Info("MOVE", formattedMessage)
end

local function shouldBypassCooldownCheck(context)
	local fruitHandler = context and context.FruitHandler
	local method = fruitHandler and fruitHandler.ShouldBypassCooldownCheck
	if typeof(method) ~= "function" then
		return false
	end

	local ok, result = pcall(method, fruitHandler, context)
	if not ok then
		DevilFruitLogger.Warn(
			"MOVE",
			"cooldown bypass check failed fruit=%s ability=%s err=%s",
			tostring(context and context.FruitName),
			tostring(context and context.AbilityName),
			tostring(result)
		)
		return false
	end

	return result == true
end

function DevilFruitAbilityRunner.Execute(params)
	local player = params.Player
	local fruitName = params.FruitName
	local abilityName = params.AbilityName
	local abilityConfig = params.AbilityConfig
	params.Security.LogExecutionStage(player, fruitName, abilityName, "context_build", "begin", params.RequestPayload)

	local context = params.GetContext(player, fruitName, abilityName, abilityConfig, params.RequestPayload, params.CharacterState, params.RequestMetadata)
	if not context then
		if shouldLogMeraAudit(fruitName, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera ability runner blocked player=%s fruit=%s ability=%s stage=context_build reason=invalid_context",
				player and player.Name or "<nil>",
				tostring(fruitName),
				tostring(abilityName)
			)
		end
		params.Security.LogExecutionStage(player, fruitName, abilityName, "context_build", "invalid_context", params.RequestPayload)
		params.RequestGuard.RecordRejection(player, "InvalidContext", abilityName)
		params.FireDenied(player, fruitName, abilityName, "InvalidContext")
		return false
	end
	params.Security.LogExecutionStage(player, fruitName, abilityName, "context_build", "ok", params.RequestPayload)

	local fireActivatedStateOnly = params.FireActivatedStateOnly or params.FireActivated
	context.StartAbilityCooldown = function(duration, payload)
		local cooldownDuration = tonumber(duration)
		if cooldownDuration == nil then
			cooldownDuration = tonumber(abilityConfig and abilityConfig.Cooldown) or 0
		end

		local readyAtForContext = params.SetAbilityCooldown(player, abilityName, cooldownDuration)
		if typeof(fireActivatedStateOnly) == "function" then
			fireActivatedStateOnly(player, fruitName, abilityName, readyAtForContext, payload or {})
		end
		return readyAtForContext
	end
	context.ClearAbilityCooldown = function(payload)
		params.ClearAbilityCooldown(player, abilityName)
		if typeof(fireActivatedStateOnly) == "function" then
			fireActivatedStateOnly(player, fruitName, abilityName, 0, payload or {})
		end
		return 0
	end

	local abilityHandler = context.FruitHandler[abilityName]
	if typeof(abilityHandler) ~= "function" then
		if shouldLogMeraAudit(fruitName, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera ability runner blocked player=%s fruit=%s ability=%s stage=handler_lookup reason=missing_handler",
				player and player.Name or "<nil>",
				tostring(fruitName),
				tostring(abilityName)
			)
		end
		params.Security.LogExecutionStage(player, fruitName, abilityName, "handler_lookup", "missing_handler", params.RequestPayload)
		params.RequestGuard.RecordRejection(player, "UnknownAbility", abilityName)
		params.FireDenied(player, fruitName, abilityName, "MissingHandler")
		return false
	end
	params.Security.LogExecutionStage(player, fruitName, abilityName, "handler_lookup", "ok", params.RequestPayload)

	local bypassCooldownCheck = shouldBypassCooldownCheck(context)
	local readyAt = 0
	if not bypassCooldownCheck then
		local isReady
		isReady, readyAt = params.IsAbilityReady(player, abilityName)
		if not isReady then
			if shouldLogMeraAudit(fruitName, abilityName) then
				logMeraAudit(
					"WARN",
					"Mera ability runner blocked player=%s fruit=%s ability=%s stage=cooldown_check reason=Cooldown readyAt=%s",
					player and player.Name or "<nil>",
					tostring(fruitName),
					tostring(abilityName),
					tostring(readyAt)
				)
			end
			params.Security.LogExecutionStage(player, fruitName, abilityName, "cooldown_check", string.format("cooldown_until=%s", tostring(readyAt)), params.RequestPayload)
			params.RequestGuard.RecordRejection(player, "Cooldown", abilityName)
			params.FireDenied(player, fruitName, abilityName, "Cooldown", readyAt)
			return false
		end
		params.Security.LogExecutionStage(player, fruitName, abilityName, "cooldown_check", "ready", params.RequestPayload)
	else
		params.Security.LogExecutionStage(player, fruitName, abilityName, "cooldown_check", "bypassed", params.RequestPayload)
	end

	local startsCooldownOnResolve = params.ShouldStartCooldownOnResolve(abilityConfig)
	local nextReadyAt = 0
	local reservedCooldown = false
	if not bypassCooldownCheck and not startsCooldownOnResolve then
		nextReadyAt = params.SetAbilityCooldown(player, abilityName, abilityConfig.Cooldown)
		reservedCooldown = true
	end

	params.Security.LogExecutionStage(player, fruitName, abilityName, "handler_call", "begin", params.RequestPayload)
	if shouldLogMeraAudit(fruitName, abilityName) then
		logMeraAudit(
			"INFO",
			"Mera ability runner enter player=%s fruit=%s ability=%s stage=handler_call",
			player and player.Name or "<nil>",
			tostring(fruitName),
			tostring(abilityName)
		)
	end
	local ok, payload, control = pcall(abilityHandler, context)
	if not ok then
		if shouldLogMeraAudit(fruitName, abilityName) then
			logMeraAudit(
				"WARN",
				"Mera ability runner fail player=%s fruit=%s ability=%s stage=handler_call detail=%s",
				player and player.Name or "<nil>",
				tostring(fruitName),
				tostring(abilityName),
				tostring(payload)
			)
		end
		if reservedCooldown then
			params.ClearAbilityCooldown(player, abilityName)
		end
		params.Security.LogExecutionStage(player, fruitName, abilityName, "handler_call", string.format("failed:%s", tostring(payload)), params.RequestPayload)
		params.Security.LogModuleFailure(fruitName, abilityName, payload)
		params.RequestGuard.RecordRejection(player, "ExecutionFailed", abilityName)
		params.FireDenied(player, fruitName, abilityName, "ExecutionFailed")
		return false
	end
	params.Security.LogExecutionStage(player, fruitName, abilityName, "handler_call", "ok", payload)
	if shouldLogMeraAudit(fruitName, abilityName) then
		logMeraAudit(
			"INFO",
			"Mera ability runner success player=%s fruit=%s ability=%s stage=handler_call",
			player and player.Name or "<nil>",
			tostring(fruitName),
			tostring(abilityName)
		)
	end

	local applyCooldown = true
	local cooldownDuration = abilityConfig.Cooldown
	local preserveExistingCooldown = bypassCooldownCheck
	local suppressActivatedEvent = false
	if typeof(control) == "table" then
		if control.ApplyCooldown == false then
			applyCooldown = false
		end

		local overrideDuration = tonumber(control.CooldownDuration)
		if overrideDuration then
			cooldownDuration = overrideDuration
		end

		if control.PreserveExistingCooldown == true then
			preserveExistingCooldown = true
		end

		if control.SuppressActivatedEvent == true then
			suppressActivatedEvent = true
		end
	end

	if not preserveExistingCooldown then
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
	end

	if not suppressActivatedEvent then
		params.FireActivated(player, fruitName, abilityName, nextReadyAt, payload)
	end
	params.RequestGuard.RecordAccepted(player, fruitName, abilityName)
	params.Security.LogExecutionStage(
		player,
		fruitName,
		abilityName,
		"activated",
		string.format(
			"nextReadyAt=%s applyCooldown=%s preserveCooldown=%s suppressActivated=%s",
			tostring(nextReadyAt),
			tostring(applyCooldown),
			tostring(preserveExistingCooldown),
			tostring(suppressActivatedEvent)
		),
		payload
	)
	if shouldLogMeraAudit(fruitName, abilityName) then
		logMeraAudit(
			"INFO",
			"Mera ability runner activated player=%s fruit=%s ability=%s nextReadyAt=%s applyCooldown=%s preserveCooldown=%s suppressActivated=%s",
			player and player.Name or "<nil>",
			tostring(fruitName),
			tostring(abilityName),
			tostring(nextReadyAt),
			tostring(applyCooldown),
			tostring(preserveExistingCooldown),
			tostring(suppressActivatedEvent)
		)
	end
	return true
end

return DevilFruitAbilityRunner
