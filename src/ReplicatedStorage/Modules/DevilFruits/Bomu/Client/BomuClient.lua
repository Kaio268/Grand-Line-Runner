local BomuClient = {}
BomuClient.__index = BomuClient

function BomuClient.Create(config)
	local self = setmetatable({}, BomuClient)
	self.player = config and config.player or nil
	self.playOptionalEffect = type(config and config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or nil
	return self
end

function BomuClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:BuildRequestPayload(abilityName, abilityConfig, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function BomuClient:HandleEffect(targetPlayer, abilityName, payload)
	return false
end

function BomuClient:HandleStateEvent(eventName, abilityName, value, payload)
	return false
end

function BomuClient:Update()
end

function BomuClient:HandleCharacterRemoving()
end

function BomuClient:HandlePlayerRemoving(leavingPlayer)
end

return BomuClient
