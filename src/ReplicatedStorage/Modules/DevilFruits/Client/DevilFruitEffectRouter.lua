local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SharedFolder = Modules:WaitForChild("DevilFruits"):WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFolder:WaitForChild("DevilFruitLogger"))

local DevilFruitEffectRouter = {}
DevilFruitEffectRouter.__index = DevilFruitEffectRouter

local function getEffectPhase(payload)
	local phase = payload and payload.Phase
	if typeof(phase) == "string" and phase ~= "" then
		return phase
	end

	return "Instant"
end

function DevilFruitEffectRouter.new(config)
	local self = setmetatable({}, DevilFruitEffectRouter)
	self.loader = config.loader
	self.clientEffectVisuals = config.clientEffectVisuals
	self.playOptionalEffect = config.playOptionalEffect
	self.player = config.player
	self.onPhoenixFlight = config.onPhoenixFlight
	self.onPhoenixShield = config.onPhoenixShield
	self.phoenixFruitName = config.phoenixFruitName
	self.phoenixFlightAbility = config.phoenixFlightAbility
	self.phoenixShieldAbility = config.phoenixShieldAbility
	return self
end

function DevilFruitEffectRouter:HandleEffect(targetPlayer, fruitName, abilityName, payload)
	local resolvedPayload = payload or {}
	DevilFruitLogger.Info(
		"EFFECT",
		"routed fruit=%s ability=%s phase=%s",
		tostring(Registry.ResolveFruitName(fruitName) or fruitName),
		tostring(abilityName),
		getEffectPhase(resolvedPayload)
	)

	local methodFound, handled = self.loader:CallControllerMethod(
		fruitName,
		"HandleEffect",
		targetPlayer,
		abilityName,
		resolvedPayload
	)
	if methodFound and handled then
		return true
	end

	self.playOptionalEffect(targetPlayer, fruitName, abilityName)
	self.clientEffectVisuals:CreateFallbackBurstEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreateBomuDetonationEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreatePhoenixFlightEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreatePhoenixShieldEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreateRubberLaunchEffect(targetPlayer, fruitName, abilityName, resolvedPayload)

	if fruitName == self.phoenixFruitName and abilityName == self.phoenixFlightAbility then
		if targetPlayer == self.player and typeof(self.onPhoenixFlight) == "function" then
			self.onPhoenixFlight(resolvedPayload)
		end
		return true
	end

	if fruitName == self.phoenixFruitName and abilityName == self.phoenixShieldAbility then
		if typeof(self.onPhoenixShield) == "function" then
			self.onPhoenixShield(targetPlayer, resolvedPayload)
		end
		return true
	end

	return true
end

return DevilFruitEffectRouter
