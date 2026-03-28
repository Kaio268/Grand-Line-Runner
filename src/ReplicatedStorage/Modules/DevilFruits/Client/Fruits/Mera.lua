local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MeraDashClient = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraDashClient"))
local MeraPresentationClient = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraPresentationClient"))
local MeraVfx = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraVfx"))

local MeraFruitClient = {}
MeraFruitClient.__index = MeraFruitClient

function MeraFruitClient.Create(config)
	local self = setmetatable({}, MeraFruitClient)
	self.playOptionalEffect = function(targetPlayer, fruitName, abilityName)
		if abilityName == "FlameDash" then
			return
		end

		if abilityName == "FireBurst" then
			MeraVfx.LogRemovedPlaceholder(abilityName)
			return
		end

		if typeof(config.PlayOptionalEffect) == "function" then
			config.PlayOptionalEffect(targetPlayer, fruitName, abilityName)
		end
	end
	self.presentation = MeraPresentationClient.new({
		player = config.player,
	})
	self.impl = MeraDashClient.new({
		player = config.player,
		PlayOptionalEffect = self.playOptionalEffect,
		CreateEffectVisual = function() end,
		PlayFlameDashStartup = function(targetPlayer, payload, isPredicted)
			return self.presentation:PlayFlameDashStartup(targetPlayer, payload, isPredicted)
		end,
		PlayFlameDashComplete = function(targetPlayer, payload)
			return self.presentation:PlayFlameDashComplete(targetPlayer, payload)
		end,
		MarkFlameDashTrailPredictedComplete = function(targetPlayer, reason, finalPosition, direction)
			return self.presentation:MarkFlameDashTrailPredictedComplete(targetPlayer, reason, finalPosition, direction)
		end,
		StopFlameDashTrail = function(targetPlayer, reason, finalPosition, direction)
			return self.presentation:StopFlameDashTrail(targetPlayer, reason, finalPosition, direction)
		end,
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
	if abilityName == MeraDashClient.ABILITY_NAME then
		return self.impl:HandleEffect(targetPlayer, payload)
	end

	if abilityName == "FireBurst" then
		if typeof(self.playOptionalEffect) == "function" then
			self.playOptionalEffect(targetPlayer, MeraDashClient.FRUIT_NAME, abilityName)
		end
		return self.presentation:PlayFireBurstRelease(targetPlayer, payload or {})
	end

	return false
end

function MeraFruitClient:HandleStateEvent(eventName, abilityName, value, payload)
	return self.impl:HandleStateEvent(eventName, MeraDashClient.FRUIT_NAME, abilityName, value, payload)
end

function MeraFruitClient:HandleCharacterRemoving()
	self.presentation:HandleCharacterRemoving()
	self.impl:CleanupCharacterRemoving()
end

function MeraFruitClient:HandlePlayerRemoving(leavingPlayer)
	self.presentation:HandlePlayerRemoving(leavingPlayer)
end

return MeraFruitClient
