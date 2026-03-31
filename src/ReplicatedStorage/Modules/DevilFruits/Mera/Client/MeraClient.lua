local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruits = Modules:WaitForChild("DevilFruits")
local DevilFruitLogger = require(DevilFruits:WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local MeraFolder = DevilFruits:WaitForChild("Mera")
local ClientFolder = MeraFolder:WaitForChild("Client")
local MeraDashClient = require(ClientFolder:WaitForChild("MeraDashClient"))

local MeraFruitClient = {}
MeraFruitClient.__index = MeraFruitClient

local cachedPresentationModule
local MERA_AUDIT_MARKER = "MERA_AUDIT_2026_03_30_V4"

local function formatAuditValue(value)
	if typeof(value) == "Vector3" then
		return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
	end

	return tostring(value)
end

local function describePayload(payload)
	if typeof(payload) ~= "table" then
		return string.format("type=%s value=%s", typeof(payload), formatAuditValue(payload))
	end

	local keys = {}
	for key in pairs(payload) do
		keys[#keys + 1] = key
	end

	table.sort(keys, function(left, right)
		return tostring(left) < tostring(right)
	end)

	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = string.format("%s=%s", tostring(key), formatAuditValue(payload[key]))
	end

	return string.format("type=table keys=%d payload={%s}", #keys, table.concat(parts, ", "))
end

local function logMeraAudit(level, message, ...)
	if not game:GetService("RunService"):IsStudio() then
		return
	end

	local formattedMessage = string.format("[%s] " .. message, MERA_AUDIT_MARKER, ...)
	if level == "WARN" then
		DevilFruitLogger.Warn("REQUEST", formattedMessage)
		return
	end

	DevilFruitLogger.Info("REQUEST", formattedMessage)
end

local function buildNoopPresentationClient()
	return {
		PlayFlameDashStartup = function()
			return false
		end,
		PlayFlameDashComplete = function()
			return false
		end,
		MarkFlameDashTrailPredictedComplete = function()
			return false
		end,
		StopFlameDashTrail = function()
			return false
		end,
		HandleFireBurstEffect = function()
			return false
		end,
		HandleStateEvent = function()
			return false
		end,
		HandleCharacterRemoving = function() end,
		HandlePlayerRemoving = function() end,
		StopFireBurstStartup = function()
			return false
		end,
	}
end

local function requirePresentationModule()
	if cachedPresentationModule ~= nil then
		return cachedPresentationModule or nil
	end

	local ok, result = pcall(function()
		return require(ClientFolder:WaitForChild("MeraPresentationClient"))
	end)
	if not ok then
		DevilFruitLogger.Warn(
			"CLIENT",
			"presentation module load failed fruit=Mera Mera no Mi detail=%s fallback=noop",
			tostring(result)
		)
		cachedPresentationModule = false
		return nil
	end

	cachedPresentationModule = result
	DevilFruitLogger.Info("CLIENT", "presentation module ready fruit=Mera Mera no Mi source=%s", ClientFolder:GetFullName())
	return result
end

local function logRequest(message, ...)
	if not game:GetService("RunService"):IsStudio() then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
end

function MeraFruitClient:GetPresentation()
	if self.presentation ~= nil then
		return self.presentation
	end

	local presentationModule = requirePresentationModule()
	if presentationModule and typeof(presentationModule.new) == "function" then
		local ok, result = pcall(function()
			return presentationModule.new({
				player = self.player,
			})
		end)
		if ok and result then
			self.presentation = result
			DevilFruitLogger.Info(
				"CLIENT",
				"presentation client ready fruit=Mera Mera no Mi player=%s",
				tostring(self.player and self.player.Name or "<nil>")
			)
			return self.presentation
		end

		DevilFruitLogger.Warn(
			"CLIENT",
			"presentation client init failed fruit=Mera Mera no Mi player=%s detail=%s fallback=noop",
			tostring(self.player and self.player.Name or "<nil>"),
			tostring(result)
		)
	end

	self.presentation = buildNoopPresentationClient()
	return self.presentation
end

function MeraFruitClient.Create(config)
	config = config or {}
	local self = setmetatable({}, MeraFruitClient)
	self.player = config.player
	self.playOptionalEffect = function(targetPlayer, fruitName, abilityName)
		if abilityName == "FlameDash" or abilityName == "FireBurst" then
			return
		end

		if typeof(config.PlayOptionalEffect) == "function" then
			config.PlayOptionalEffect(targetPlayer, fruitName, abilityName)
		end
	end
	self.impl = MeraDashClient.new({
		player = config.player,
		PlayOptionalEffect = self.playOptionalEffect,
		CreateEffectVisual = function() end,
		PlayFlameDashStartup = function(targetPlayer, payload, isPredicted)
			return self:GetPresentation():PlayFlameDashStartup(targetPlayer, payload, isPredicted)
		end,
		PlayFlameDashComplete = function(targetPlayer, payload)
			return self:GetPresentation():PlayFlameDashComplete(targetPlayer, payload)
		end,
		MarkFlameDashTrailPredictedComplete = function(targetPlayer, reason, finalPosition, direction)
			return self:GetPresentation():MarkFlameDashTrailPredictedComplete(
				targetPlayer,
				reason,
				finalPosition,
				direction
			)
		end,
		StopFlameDashTrail = function(targetPlayer, reason, finalPosition, direction)
			return self:GetPresentation():StopFlameDashTrail(targetPlayer, reason, finalPosition, direction)
		end,
	})
	return self
end

function MeraFruitClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	logRequest("fruit module request begin fruit=Mera Mera no Mi ability=%s", tostring(abilityName))
	logMeraAudit(
		"INFO",
		"MeraClient BeginPredictedRequest enter ability=%s player=%s",
		tostring(abilityName),
		tostring(self.player and self.player.Name or "<nil>")
	)
	if abilityName == MeraDashClient.ABILITY_NAME then
		local ok, payloadOrError = pcall(function()
			return self.impl:BeginPredictedRequest()
		end)
		if not ok then
			logMeraAudit(
				"WARN",
				"MeraClient BeginPredictedRequest fail ability=%s source=mera_dash detail=%s",
				tostring(abilityName),
				tostring(payloadOrError)
			)
			logRequest(
				"fruit module request end fruit=Mera Mera no Mi ability=%s source=mera_dash_error payload=nil detail=%s",
				tostring(abilityName),
				tostring(payloadOrError)
			)
			return nil
		end

		local payload = payloadOrError
		logRequest(
			"fruit module request end fruit=Mera Mera no Mi ability=%s source=mera_dash payload=%s",
			tostring(abilityName),
			tostring(typeof(payload))
		)
		logMeraAudit(
			"INFO",
			"MeraClient BeginPredictedRequest success ability=%s source=mera_dash payload=%s",
			tostring(abilityName),
			describePayload(payload)
		)
		return payload
	end

	if typeof(fallbackBuilder) == "function" then
		local ok, payloadOrError = pcall(fallbackBuilder)
		if not ok then
			logMeraAudit(
				"WARN",
				"MeraClient BeginPredictedRequest fail ability=%s source=fallback detail=%s",
				tostring(abilityName),
				tostring(payloadOrError)
			)
			logRequest(
				"fruit module request end fruit=Mera Mera no Mi ability=%s source=fallback_error payload=nil detail=%s",
				tostring(abilityName),
				tostring(payloadOrError)
			)
			return nil
		end

		local payload = payloadOrError
		logRequest(
			"fruit module request end fruit=Mera Mera no Mi ability=%s source=fallback payload=%s",
			tostring(abilityName),
			tostring(typeof(payload))
		)
		logMeraAudit(
			"INFO",
			"MeraClient BeginPredictedRequest success ability=%s source=fallback payload=%s",
			tostring(abilityName),
			describePayload(payload)
		)
		return payload
	end

	logRequest("fruit module request end fruit=Mera Mera no Mi ability=%s source=none payload=nil", tostring(abilityName))
	logMeraAudit(
		"WARN",
		"MeraClient BeginPredictedRequest fail ability=%s source=none detail=no_builder",
		tostring(abilityName)
	)
	return nil
end

function MeraFruitClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName == MeraDashClient.ABILITY_NAME then
		return self.impl:HandleEffect(targetPlayer, payload)
	end

	if abilityName == "FireBurst" then
		return self:GetPresentation():HandleFireBurstEffect(targetPlayer, payload or {})
	end

	return false
end

function MeraFruitClient:HandleStateEvent(eventName, abilityName, value, payload)
	if abilityName == "FireBurst" and eventName == "Denied" then
		self:GetPresentation():StopFireBurstStartup(self.player, value)
	end

	return self.impl:HandleStateEvent(eventName, MeraDashClient.FRUIT_NAME, abilityName, value, payload)
end

function MeraFruitClient:HandleCharacterRemoving()
	if self.presentation then
		self.presentation:HandleCharacterRemoving()
	end
	self.impl:CleanupCharacterRemoving()
end

function MeraFruitClient:HandlePlayerRemoving(leavingPlayer)
	if self.presentation then
		self.presentation:HandlePlayerRemoving(leavingPlayer)
	end
end

return MeraFruitClient
