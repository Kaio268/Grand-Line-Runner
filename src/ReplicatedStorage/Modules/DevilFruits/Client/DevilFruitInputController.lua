local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Registry = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("Registry"))
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))

local DevilFruitInputController = {}
DevilFruitInputController.__index = DevilFruitInputController

local DEBUG_REQUEST_LOGS_ENABLED = RunService:IsStudio()

local function countPayloadKeys(payload)
	if typeof(payload) ~= "table" then
		return 0
	end

	local count = 0
	for _ in pairs(payload) do
		count += 1
	end

	return count
end

local function logRequest(message, ...)
	if not DEBUG_REQUEST_LOGS_ENABLED then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
end

local function shouldTraceKeyCode(keyCode)
	return keyCode == Enum.KeyCode.Q or keyCode == Enum.KeyCode.C
end

function DevilFruitInputController.new(config)
	local self = setmetatable({}, DevilFruitInputController)
	self.loader = config.loader
	self.player = config.player
	return self
end

function DevilFruitInputController:GetAbilityForKeyCode(fruitName, keyCode, fallbackResolver)
	local abilityEntry = Registry.GetAbilityByKeyCode(fruitName, keyCode)
	if abilityEntry then
		if shouldTraceKeyCode(keyCode) then
			logRequest(
				"ability lookup key=%s fruit=%s resolvedAbility=%s source=registry",
				tostring(keyCode and keyCode.Name),
				tostring(fruitName),
				tostring(abilityEntry.Name)
			)
		end
		return fruitName, abilityEntry.Name, abilityEntry
	end

	if typeof(fallbackResolver) == "function" then
		if shouldTraceKeyCode(keyCode) then
			logRequest(
				"ability lookup key=%s fruit=%s source=fallback",
				tostring(keyCode and keyCode.Name),
				tostring(fruitName)
			)
		end
		return fallbackResolver(keyCode)
	end

	if shouldTraceKeyCode(keyCode) then
		logRequest(
			"ability lookup key=%s fruit=%s resolvedAbility=<nil> source=none",
			tostring(keyCode and keyCode.Name),
			tostring(fruitName)
		)
	end
	return nil, nil, nil
end

function DevilFruitInputController:BuildRequestPayload(fruitName, abilityName, abilityEntry, fallbackBuilder)
	logRequest(
		"build request begin fruit=%s ability=%s hasAbilityEntry=%s builder=controller",
		tostring(fruitName),
		tostring(abilityName),
		tostring(abilityEntry ~= nil)
	)
	local success, payload = self.loader:CallControllerMethod(
		fruitName,
		"BuildRequestPayload",
		abilityName,
		abilityEntry,
		fallbackBuilder
	)
	if success then
		logRequest(
			"build request end fruit=%s ability=%s source=controller payloadKeys=%d",
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(payload)
		)
		return payload
	end

	if typeof(fallbackBuilder) == "function" then
		local fallbackPayload = fallbackBuilder()
		logRequest(
			"build request end fruit=%s ability=%s source=fallback payloadKeys=%d",
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(fallbackPayload)
		)
		return fallbackPayload
	end

	logRequest(
		"build request end fruit=%s ability=%s source=none payloadKeys=0 reason=no_builder",
		tostring(fruitName),
		tostring(abilityName)
	)
	return nil
end

function DevilFruitInputController:BuildPredictedRequest(fruitName, abilityName, fallbackBuilder)
	logRequest(
		"predicted request begin fruit=%s ability=%s builder=controller",
		tostring(fruitName),
		tostring(abilityName)
	)
	local success, payload = self.loader:CallControllerMethod(
		fruitName,
		"BeginPredictedRequest",
		abilityName,
		fallbackBuilder
	)
	if success then
		logRequest(
			"predicted request end fruit=%s ability=%s source=controller payloadKeys=%d",
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(payload)
		)
		return payload
	end

	if typeof(fallbackBuilder) == "function" then
		local fallbackPayload = fallbackBuilder()
		logRequest(
			"predicted request end fruit=%s ability=%s source=fallback payloadKeys=%d",
			tostring(fruitName),
			tostring(abilityName),
			countPayloadKeys(fallbackPayload)
		)
		return fallbackPayload
	end

	logRequest(
		"predicted request end fruit=%s ability=%s source=none payloadKeys=0 reason=no_builder",
		tostring(fruitName),
		tostring(abilityName)
	)
	return nil
end

return DevilFruitInputController
