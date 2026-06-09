local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))

local DevilFruitReplication = {}
DevilFruitReplication.__index = DevilFruitReplication

local DEFAULT_EFFECT_REPLICATION_RADIUS = 700
local MAX_EFFECT_REPLICATION_RADIUS = 1800
local FLAME_DASH_MEDIUM_RADIUS = 450
local FLAME_DASH_CHEAP_RADIUS = 700
local FLAME_DASH_FRUIT_NAMES = {
	["Inferno Fruit"] = true,
	["Mera"] = true,
	["Mera Mera no Mi"] = true,
	["MeraMeraNoMi"] = true,
}
local POSITION_KEYS = {
	"OriginPosition",
	"StartPosition",
	"Position",
	"RootPosition",
	"TargetPosition",
	"ImpactPosition",
	"HitPosition",
	"SpawnPosition",
}
local CFRAME_KEYS = {
	"OriginCFrame",
	"StartCFrame",
	"CFrame",
}

local function getPhase(payload)
	local phase = payload and payload.Phase
	if typeof(phase) == "string" and phase ~= "" then
		return phase
	end

	return "Instant"
end

local function copyPayload(payload)
	local result = {}
	if typeof(payload) == "table" then
		for key, value in pairs(payload) do
			result[key] = value
		end
	end
	return result
end

local function isFlameDashEffect(fruitName, abilityName)
	return tostring(abilityName) == "FlameDash" and FLAME_DASH_FRUIT_NAMES[tostring(fruitName)] == true
end

local function readVector3(value)
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) == "CFrame" then
		return value.Position
	end
	return nil
end

local function getPayloadOrigin(payload)
	if typeof(payload) ~= "table" then
		return nil
	end

	for _, key in ipairs(POSITION_KEYS) do
		local position = readVector3(payload[key])
		if position then
			return position
		end
	end

	for _, key in ipairs(CFRAME_KEYS) do
		local position = readVector3(payload[key])
		if position then
			return position
		end
	end

	return nil
end

local function getPlayerRootPosition(player)
	if not player or not player:IsA("Player") then
		return nil
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart.Position
	end
	return nil
end

local function getReplicationRadius(payload)
	if typeof(payload) ~= "table" then
		return DEFAULT_EFFECT_REPLICATION_RADIUS
	end

	local configured = tonumber(payload.ReplicationRadius)
		or tonumber(payload.VisualRadius)
		or tonumber(payload.EffectRadius)
		or tonumber(payload.ClientMaxDistance)
	local range = tonumber(payload.MaxDistance) or tonumber(payload.Range) or tonumber(payload.Distance)
	local radius = configured or DEFAULT_EFFECT_REPLICATION_RADIUS
	if range then
		radius = math.max(radius, range)
	end

	return math.clamp(radius, 1, MAX_EFFECT_REPLICATION_RADIUS)
end

function DevilFruitReplication.FireScoped(remoteBundle, targetPlayer, fruitName, abilityName, payload)
	local effectRemote = remoteBundle and remoteBundle.Effect
	if not effectRemote then
		return 0, "missing_remote"
	end

	local resolvedPayload = if typeof(payload) == "table" then payload else {}
	local origin = getPayloadOrigin(resolvedPayload) or getPlayerRootPosition(targetPlayer)
	if isFlameDashEffect(fruitName, abilityName) then
		local sent = 0
		if not origin then
			if targetPlayer and targetPlayer.Parent == Players then
				local targetPayload = copyPayload(resolvedPayload)
				targetPayload.VfxQuality = "Full"
				targetPayload.ClientMaxDistance = math.max(
					tonumber(targetPayload.ClientMaxDistance) or 0,
					FLAME_DASH_CHEAP_RADIUS
				)
				effectRemote:FireClient(targetPlayer, targetPlayer, fruitName, abilityName, targetPayload)
				return 1, "flame_dash_target_only_no_origin"
			end
			return 0, "flame_dash_no_origin"
		end

		for _, recipient in ipairs(Players:GetPlayers()) do
			local recipientPayload = nil
			if recipient == targetPlayer then
				recipientPayload = copyPayload(resolvedPayload)
				recipientPayload.VfxQuality = "Full"
			else
				local recipientPosition = getPlayerRootPosition(recipient)
				if recipientPosition then
					local distance = (recipientPosition - origin).Magnitude
					if distance <= FLAME_DASH_MEDIUM_RADIUS then
						recipientPayload = copyPayload(resolvedPayload)
						recipientPayload.VfxQuality = "Medium"
						recipientPayload.DistanceFromEffect = distance
					elseif distance <= FLAME_DASH_CHEAP_RADIUS then
						recipientPayload = copyPayload(resolvedPayload)
						recipientPayload.VfxQuality = "Cheap"
						recipientPayload.DistanceFromEffect = distance
					end
				end
			end

			if recipientPayload then
				sent += 1
				recipientPayload.OriginPosition = recipientPayload.OriginPosition or origin
				recipientPayload.ReplicationRadius = FLAME_DASH_CHEAP_RADIUS
				recipientPayload.ClientMaxDistance = FLAME_DASH_CHEAP_RADIUS
				effectRemote:FireClient(recipient, targetPlayer, fruitName, abilityName, recipientPayload)
			end
		end

		return sent, "flame_dash_scoped"
	end

	if not origin then
		effectRemote:FireAllClients(targetPlayer, fruitName, abilityName, resolvedPayload)
		return #Players:GetPlayers(), "fallback_all"
	end

	local radius = getReplicationRadius(resolvedPayload)
	local sent = 0
	for _, recipient in ipairs(Players:GetPlayers()) do
		local shouldSend = recipient == targetPlayer
		if not shouldSend then
			local recipientPosition = getPlayerRootPosition(recipient)
			shouldSend = recipientPosition == nil or (recipientPosition - origin).Magnitude <= radius
		end

		if shouldSend then
			sent += 1
			effectRemote:FireClient(recipient, targetPlayer, fruitName, abilityName, resolvedPayload)
		end
	end

	return sent, "scoped"
end

function DevilFruitReplication.new(remoteBundle)
	local self = setmetatable({}, DevilFruitReplication)
	self.remotes = remoteBundle
	return self
end

function DevilFruitReplication:FireDenied(player, fruitName, abilityName, reason, readyAt)
	self.remotes.State:FireClient(player, "Denied", fruitName, abilityName, reason, readyAt or 0)
end

function DevilFruitReplication:FireActivated(player, fruitName, abilityName, readyAt, payload)
	self.remotes.State:FireClient(player, "Activated", fruitName, abilityName, readyAt, payload or {})
end

function DevilFruitReplication:BroadcastEffect(targetPlayer, fruitName, abilityName, payload)
	local sentCount, route = DevilFruitReplication.FireScoped(self.remotes, targetPlayer, fruitName, abilityName, payload or {})
	DevilFruitLogger.Info(
		"EFFECT",
		"routed fruit=%s ability=%s phase=%s route=%s recipients=%d",
		tostring(fruitName),
		tostring(abilityName),
		getPhase(payload),
		tostring(route),
		tonumber(sentCount) or 0
	)
end

return DevilFruitReplication
