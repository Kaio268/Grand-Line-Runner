local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MeraDashClient = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraDashClient"))

local MeraFruitClient = {}
MeraFruitClient.__index = MeraFruitClient

function MeraFruitClient.Create(config)
	local self = setmetatable({}, MeraFruitClient)
	self.impl = MeraDashClient.new({
		player = config.player,
		PlayOptionalEffect = config.PlayOptionalEffect,
		CreateEffectVisual = config.CreateEffectVisual,
	})
	return self
end

function MeraFruitClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName == MeraDashClient.ABILITY_NAME then
		return self.impl:BeginPredictedRequest()
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function MeraFruitClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= MeraDashClient.ABILITY_NAME then
		return false
	end

	return self.impl:HandleEffect(targetPlayer, payload)
end

function MeraFruitClient:HandleStateEvent(eventName, abilityName, value, payload)
	return self.impl:HandleStateEvent(eventName, MeraDashClient.FRUIT_NAME, abilityName, value, payload)
end

function MeraFruitClient:HandleCharacterRemoving()
	self.impl:CleanupCharacterRemoving()
end

return MeraFruitClient
