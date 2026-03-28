local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitLogger = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DevilFruitLogger"))

local DevilFruitReplication = {}
DevilFruitReplication.__index = DevilFruitReplication

local function getPhase(payload)
	local phase = payload and payload.Phase
	if typeof(phase) == "string" and phase ~= "" then
		return phase
	end

	return "Instant"
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
	DevilFruitLogger.Info(
		"EFFECT",
		"routed fruit=%s ability=%s phase=%s",
		tostring(fruitName),
		tostring(abilityName),
		getPhase(payload)
	)
	self.remotes.Effect:FireAllClients(targetPlayer, fruitName, abilityName, payload or {})
end

return DevilFruitReplication
