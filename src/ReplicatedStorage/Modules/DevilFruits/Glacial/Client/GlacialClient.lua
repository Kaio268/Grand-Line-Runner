local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruits = Modules:WaitForChild("DevilFruits")
local DevilFruitLogger = require(DevilFruits:WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local GlacialFolder = DevilFruits:WaitForChild("Glacial")
local ClientFolder = GlacialFolder:WaitForChild("Client")
local HieRuntime = require(ClientFolder:WaitForChild("HieRuntime"))

local GlacialClient = {}
GlacialClient.__index = GlacialClient

local function logRequest(message, ...)
	if not game:GetService("RunService"):IsStudio() then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
end

function GlacialClient.Create(config)
	local self = setmetatable({}, GlacialClient)
	self.impl = HieRuntime.new({
		player = config.player,
	})
	return self
end

function GlacialClient:BuildRequestPayload(abilityName, abilityConfig, fallbackBuilder)
	logRequest(
		"fruit module build begin fruit=Glacial Fruit ability=%s hasConfig=%s",
		tostring(abilityName),
		tostring(abilityConfig ~= nil)
	)
	if abilityName == HieRuntime.FREEZE_SHOT_ABILITY then
		local payload = self.impl:BuildFreezeShotRequestPayload(abilityConfig and abilityConfig.Config or abilityConfig)
		logRequest(
			"fruit module build end fruit=Glacial Fruit ability=%s source=hie_runtime payload=%s",
			tostring(abilityName),
			tostring(typeof(payload))
		)
		return payload
	end

	if typeof(fallbackBuilder) == "function" then
		local payload = fallbackBuilder()
		logRequest(
			"fruit module build end fruit=Glacial Fruit ability=%s source=fallback payload=%s",
			tostring(abilityName),
			tostring(typeof(payload))
		)
		return payload
	end

	logRequest("fruit module build end fruit=Glacial Fruit ability=%s source=none payload=nil", tostring(abilityName))
	return nil
end

function GlacialClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName == HieRuntime.FREEZE_SHOT_ABILITY then
		return self.impl:BeginPredictedFreezeShotRequest()
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function GlacialClient:HandleEffect(targetPlayer, abilityName, payload)
	return self.impl:HandleEffect(targetPlayer, abilityName, payload)
end

function GlacialClient:HandleStateEvent(eventName, abilityName, value, payload)
	return self.impl:HandleStateEvent(eventName, abilityName, value, payload)
end

function GlacialClient:Update()
	self.impl:Update()
end

function GlacialClient:HandleCharacterRemoving()
	self.impl:CleanupCharacterRemoving()
end

function GlacialClient:HandleUnequipped()
	self.impl:CleanupUnequipped()
	return false
end

function GlacialClient:HandlePlayerRemoving(leavingPlayer)
	self.impl:CleanupPlayerRemoving(leavingPlayer)
end

return GlacialClient
