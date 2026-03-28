local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Registry = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Registry"))

local DevilFruitInputController = {}
DevilFruitInputController.__index = DevilFruitInputController

function DevilFruitInputController.new(config)
	local self = setmetatable({}, DevilFruitInputController)
	self.loader = config.loader
	self.player = config.player
	return self
end

function DevilFruitInputController:GetAbilityForKeyCode(fruitName, keyCode, fallbackResolver)
	local abilityEntry = Registry.GetAbilityByKeyCode(fruitName, keyCode)
	if abilityEntry then
		return fruitName, abilityEntry.Name, abilityEntry
	end

	if typeof(fallbackResolver) == "function" then
		return fallbackResolver(keyCode)
	end

	return nil, nil, nil
end

function DevilFruitInputController:BuildRequestPayload(fruitName, abilityName, abilityEntry, fallbackBuilder)
	local success, payload = self.loader:CallControllerMethod(
		fruitName,
		"BuildRequestPayload",
		abilityName,
		abilityEntry,
		fallbackBuilder
	)
	if success then
		return payload
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function DevilFruitInputController:BuildPredictedRequest(fruitName, abilityName, fallbackBuilder)
	local success, payload = self.loader:CallControllerMethod(
		fruitName,
		"BeginPredictedRequest",
		abilityName,
		fallbackBuilder
	)
	if success then
		return payload
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

return DevilFruitInputController
