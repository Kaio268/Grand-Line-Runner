local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local SharedFolder = Modules:WaitForChild("DevilFruits"):WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local DevilFruitLogger = require(SharedFolder:WaitForChild("DevilFruitLogger"))
local AbilityHitboxVisualizer = require(script.Parent:WaitForChild("AbilityHitboxVisualizer"))

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
	AbilityHitboxVisualizer.Start()
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

	local hitboxOk, hitboxError = pcall(
		AbilityHitboxVisualizer.HandleEffect,
		targetPlayer,
		fruitName,
		abilityName,
		resolvedPayload
	)
	if not hitboxOk then
		warn("[AbilityHitboxVisualizer] " .. tostring(hitboxError))
	end

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

	self.playOptionalEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreateFallbackBurstEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreateBomuDetonationEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreatePhoenixFlightEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreatePhoenixShieldEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreatePhoenixRebirthEffect(targetPlayer, fruitName, abilityName, resolvedPayload)
	self.clientEffectVisuals:CreateRubberLaunchEffect(targetPlayer, fruitName, abilityName, resolvedPayload)

	return true
end

return DevilFruitEffectRouter
