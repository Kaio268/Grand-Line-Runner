local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruits = Modules:WaitForChild("DevilFruits")
local DevilFruitLogger = require(DevilFruits:WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local HieFolder = DevilFruits:WaitForChild("Hie")
local ClientFolder = HieFolder:WaitForChild("Client")
local HieRuntime = require(ClientFolder:WaitForChild("HieRuntime"))

local HieFruitClient = {}
HieFruitClient.__index = HieFruitClient

local function logRequest(message, ...)
	if not game:GetService("RunService"):IsStudio() then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
end

function HieFruitClient.Create(config)
	local self = setmetatable({}, HieFruitClient)
	self.impl = HieRuntime.new({
		player = config.player,
	})
	return self
end

function HieFruitClient:BuildRequestPayload(abilityName, abilityConfig, fallbackBuilder)
	logRequest(
		"fruit module build begin fruit=Hie Hie no Mi ability=%s hasConfig=%s",
		tostring(abilityName),
		tostring(abilityConfig ~= nil)
	)
	if abilityName == HieRuntime.FREEZE_SHOT_ABILITY then
		local payload = self.impl:BuildFreezeShotRequestPayload(abilityConfig and abilityConfig.Config or abilityConfig)
		logRequest(
			"fruit module build end fruit=Hie Hie no Mi ability=%s source=hie_runtime payload=%s",
			tostring(abilityName),
			tostring(typeof(payload))
		)
		return payload
	end

	if typeof(fallbackBuilder) == "function" then
		local payload = fallbackBuilder()
		logRequest(
			"fruit module build end fruit=Hie Hie no Mi ability=%s source=fallback payload=%s",
			tostring(abilityName),
			tostring(typeof(payload))
		)
		return payload
	end

	logRequest("fruit module build end fruit=Hie Hie no Mi ability=%s source=none payload=nil", tostring(abilityName))
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
