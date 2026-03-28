local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local HieClient = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HieClient"))

local HieFruitClient = {}
HieFruitClient.__index = HieFruitClient

function HieFruitClient.Create(config)
	local self = setmetatable({}, HieFruitClient)
	self.impl = HieClient.new({
		player = config.player,
	})
	return self
end

function HieFruitClient:BuildRequestPayload(abilityName, abilityConfig, fallbackBuilder)
	if abilityName == HieClient.FREEZE_SHOT_ABILITY then
		return self.impl:BuildFreezeShotRequestPayload(abilityConfig and abilityConfig.Config or abilityConfig)
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function HieFruitClient:HandleEffect(targetPlayer, abilityName, payload)
	return self.impl:HandleEffect(targetPlayer, abilityName, payload)
end

function HieFruitClient:Update()
	self.impl:Update()
end

function HieFruitClient:HandleCharacterRemoving()
	self.impl:CleanupCharacterRemoving()
end

function HieFruitClient:HandlePlayerRemoving(leavingPlayer)
	self.impl:CleanupPlayerRemoving(leavingPlayer)
end

return HieFruitClient
