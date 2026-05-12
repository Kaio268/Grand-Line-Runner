local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if not RunService:IsStudio() then
	return
end

-- Temporary Studio-only verifier for the CarriedCrewMember/CarriedBrainrot bridge.
-- Remove this once the alias is retired.
local DISABLE_ATTRIBUTE = "CarriedCrewMemberDebugProbeDisabled"
if game:GetAttribute(DISABLE_ATTRIBUTE) == true then
	return
end

local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE = "CarriedCrewMemberImage"
local LEGACY_CARRIED_BRAINROT_ATTRIBUTE = "CarriedBrainrot"
local LEGACY_CARRIED_BRAINROT_IMAGE_ATTRIBUTE = "CarriedBrainrotImage"

local WATCHED_ATTRIBUTES = {
	CARRIED_CREW_MEMBER_ATTRIBUTE,
	LEGACY_CARRIED_BRAINROT_ATTRIBUTE,
	CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE,
	LEGACY_CARRIED_BRAINROT_IMAGE_ATTRIBUTE,
}

local connectionsByPlayer = {}
local lastStateByPlayer = {}
local pendingByPlayer = {}
local changedByPlayer = {}

local function readState(player)
	return {
		CrewMember = player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE),
		LegacyBrainrot = player:GetAttribute(LEGACY_CARRIED_BRAINROT_ATTRIBUTE),
		CrewMemberImage = player:GetAttribute(CARRIED_CREW_MEMBER_IMAGE_ATTRIBUTE),
		LegacyBrainrotImage = player:GetAttribute(LEGACY_CARRIED_BRAINROT_IMAGE_ATTRIBUTE),
	}
end

local function isPresent(value)
	return typeof(value) == "string" and value ~= ""
end

local function hasCarriedName(state)
	return isPresent(state.CrewMember) or isPresent(state.LegacyBrainrot)
end

local function valuesMatch(left, right)
	if left == nil and right == nil then
		return true
	end
	return tostring(left or "") == tostring(right or "")
end

local function formatValue(value)
	if value == nil then
		return "<nil>"
	end
	if typeof(value) == "string" and value == "" then
		return "\"\""
	end
	return tostring(value)
end

local function formatChanged(changed)
	local names = {}
	for attributeName in pairs(changed or {}) do
		table.insert(names, attributeName)
	end
	table.sort(names)
	return table.concat(names, ",")
end

local function classifyTransition(previousState, currentState)
	local wasCarrying = previousState ~= nil and hasCarriedName(previousState)
	local isCarrying = hasCarriedName(currentState)

	if isCarrying and not wasCarrying then
		return "set_or_pickup"
	elseif not isCarrying and wasCarrying then
		return "clear_or_drop_extract_death"
	elseif isCarrying then
		return "update_while_carried"
	end

	return "idle_or_respawn_clear"
end

local function logState(player, reason, changed)
	local previousState = lastStateByPlayer[player]
	local currentState = readState(player)
	lastStateByPlayer[player] = currentState

	local nameMatch = valuesMatch(currentState.CrewMember, currentState.LegacyBrainrot)
	local imageMatch = valuesMatch(currentState.CrewMemberImage, currentState.LegacyBrainrotImage)
	local transition = classifyTransition(previousState, currentState)
	local message = string.format(
		"[CarriedCrewMemberProbe] player=%s reason=%s transition=%s changed=%s crew=%s legacy=%s crewImage=%s legacyImage=%s nameMatch=%s imageMatch=%s",
		player.Name,
		tostring(reason),
		transition,
		formatChanged(changed),
		formatValue(currentState.CrewMember),
		formatValue(currentState.LegacyBrainrot),
		formatValue(currentState.CrewMemberImage),
		formatValue(currentState.LegacyBrainrotImage),
		tostring(nameMatch),
		tostring(imageMatch)
	)

	if not nameMatch or not imageMatch then
		warn(message)
	else
		print(message)
	end
end

local function scheduleLog(player, reason, attributeName)
	if not player.Parent then
		return
	end

	local changed = changedByPlayer[player]
	if not changed then
		changed = {}
		changedByPlayer[player] = changed
	end
	changed[attributeName] = true

	if pendingByPlayer[player] == true then
		return
	end

	pendingByPlayer[player] = true
	task.defer(function()
		pendingByPlayer[player] = nil
		local changedNow = changedByPlayer[player]
		changedByPlayer[player] = nil
		if player.Parent then
			logState(player, reason, changedNow)
		end
	end)
end

local function disconnectPlayer(player)
	local connections = connectionsByPlayer[player]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	connectionsByPlayer[player] = nil
	lastStateByPlayer[player] = nil
	pendingByPlayer[player] = nil
	changedByPlayer[player] = nil
end

local function hookPlayer(player)
	disconnectPlayer(player)

	local connections = {}
	connectionsByPlayer[player] = connections

	logState(player, "player_added", nil)

	for _, attributeName in ipairs(WATCHED_ATTRIBUTES) do
		table.insert(connections, player:GetAttributeChangedSignal(attributeName):Connect(function()
			scheduleLog(player, "attribute_changed", attributeName)
		end))
	end

	table.insert(connections, player.CharacterAdded:Connect(function()
		scheduleLog(player, "character_added", "CharacterAdded")
	end))
end

Players.PlayerAdded:Connect(hookPlayer)
Players.PlayerRemoving:Connect(disconnectPlayer)

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayer(player)
end
