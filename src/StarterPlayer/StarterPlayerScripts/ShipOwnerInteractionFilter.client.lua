local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local ShipVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("ShipVisuals"))

local ATTR = ShipVisuals.Attributes
local OWNER_ONLY_ATTRIBUTE = ATTR.OwnerOnlyInteraction or "ShipOwnerOnlyInteraction"
local OWNER_USER_ID_ATTRIBUTE = ATTR.OwnerUserId or "OwnerUserId"
local HIDE_FROM_OWNER_ATTRIBUTE = ATTR.HideFromOwnerInteraction or "ShipHideFromOwnerInteraction"

local trackedShips = {}
local originalStateByInstance = setmetatable({}, { __mode = "k" })

local function resolveWorkspacePath(pathSegments)
	local current = workspace
	for _, segment in ipairs(pathSegments or {}) do
		current = current and current:WaitForChild(segment, 30)
		if not current then
			return nil
		end
	end

	return current
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections) do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end

	table.clear(connections)
end

local function readUserIdAttribute(instance, attributeName)
	local value = instance and instance:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	elseif typeof(value) == "string" then
		return tonumber(value)
	end

	return nil
end

local function isManageableInteraction(instance)
	return instance:IsA("ProximityPrompt")
		or instance:IsA("BillboardGui")
		or instance:IsA("SurfaceGui")
		or instance:IsA("ClickDetector")
end

local function getOwnerOnlySource(instance, ship)
	local current = instance
	while current and current ~= ship.Parent do
		if current:GetAttribute(OWNER_ONLY_ATTRIBUTE) == true then
			return current
		end
		if current == ship then
			break
		end
		current = current.Parent
	end

	return nil
end

local function getHideFromOwnerSource(instance, ship)
	local current = instance
	while current and current ~= ship.Parent do
		if current:GetAttribute(HIDE_FROM_OWNER_ATTRIBUTE) == true then
			return current
		end
		if current == ship then
			break
		end
		current = current.Parent
	end

	return nil
end

local function getOwnerUserId(instance, ship, ownerOnlySource)
	return readUserIdAttribute(instance, OWNER_USER_ID_ATTRIBUTE)
		or readUserIdAttribute(ownerOnlySource, OWNER_USER_ID_ATTRIBUTE)
		or readUserIdAttribute(ship, OWNER_USER_ID_ATTRIBUTE)
end

local function rememberOriginalState(instance)
	local state = originalStateByInstance[instance]
	if state then
		return state
	end

	state = {}
	if instance:IsA("ProximityPrompt") or instance:IsA("LayerCollector") then
		state.Enabled = instance.Enabled
	end
	if instance:IsA("ClickDetector") then
		state.MaxActivationDistance = instance.MaxActivationDistance
	end

	originalStateByInstance[instance] = state
	return state
end

local function hideInteraction(instance)
	rememberOriginalState(instance)

	if instance:IsA("ProximityPrompt") or instance:IsA("LayerCollector") then
		instance.Enabled = false
	elseif instance:IsA("ClickDetector") then
		instance.MaxActivationDistance = 0
	end
end

local function restoreInteraction(instance)
	local state = originalStateByInstance[instance]
	if not state then
		return
	end

	if state.Enabled ~= nil and (instance:IsA("ProximityPrompt") or instance:IsA("LayerCollector")) then
		instance.Enabled = state.Enabled
	end
	if state.MaxActivationDistance ~= nil and instance:IsA("ClickDetector") then
		instance.MaxActivationDistance = state.MaxActivationDistance
	end

	originalStateByInstance[instance] = nil
end

local function applyVisibility(ship, instance)
	if not ship or not ship.Parent or not instance or not instance.Parent or not isManageableInteraction(instance) then
		return
	end

	local hideFromOwnerSource = getHideFromOwnerSource(instance, ship)
	if hideFromOwnerSource then
		local ownerUserId = getOwnerUserId(instance, ship, hideFromOwnerSource)
		if ownerUserId == localPlayer.UserId then
			hideInteraction(instance)
		else
			restoreInteraction(instance)
		end
		return
	end

	local ownerOnlySource = getOwnerOnlySource(instance, ship)
	if not ownerOnlySource then
		restoreInteraction(instance)
		return
	end

	local ownerUserId = getOwnerUserId(instance, ship, ownerOnlySource)
	if ownerUserId == localPlayer.UserId then
		restoreInteraction(instance)
	else
		hideInteraction(instance)
	end
end

local function applyShipVisibility(ship)
	if not ship or not ship.Parent then
		return
	end

	for _, descendant in ipairs(ship:GetDescendants()) do
		applyVisibility(ship, descendant)
	end
end

local function watchDescendant(state, instance)
	if state.Watched[instance] then
		return
	end

	state.Watched[instance] = true

	if isManageableInteraction(instance) then
		table.insert(state.Connections, instance:GetAttributeChangedSignal(OWNER_ONLY_ATTRIBUTE):Connect(function()
			applyVisibility(state.Ship, instance)
		end))
		table.insert(state.Connections, instance:GetAttributeChangedSignal(OWNER_USER_ID_ATTRIBUTE):Connect(function()
			applyVisibility(state.Ship, instance)
		end))

		if instance:IsA("ProximityPrompt") or instance:IsA("LayerCollector") then
			table.insert(state.Connections, instance:GetPropertyChangedSignal("Enabled"):Connect(function()
				applyVisibility(state.Ship, instance)
			end))
		elseif instance:IsA("ClickDetector") then
			table.insert(state.Connections, instance:GetPropertyChangedSignal("MaxActivationDistance"):Connect(function()
				applyVisibility(state.Ship, instance)
			end))
		end
	end

	applyVisibility(state.Ship, instance)
end

local function watchShip(ship)
	if not ship:IsA("Model") or trackedShips[ship] then
		return
	end

	local state = {
		Connections = {},
		Ship = ship,
		Watched = setmetatable({}, { __mode = "k" }),
	}
	trackedShips[ship] = state

	table.insert(state.Connections, ship:GetAttributeChangedSignal(OWNER_USER_ID_ATTRIBUTE):Connect(function()
		applyShipVisibility(ship)
	end))

	table.insert(state.Connections, ship.DescendantAdded:Connect(function(descendant)
		watchDescendant(state, descendant)
		for _, child in ipairs(descendant:GetDescendants()) do
			watchDescendant(state, child)
		end
	end))

	for _, descendant in ipairs(ship:GetDescendants()) do
		watchDescendant(state, descendant)
	end

	applyShipVisibility(ship)
end

local function unwatchShip(ship)
	local state = trackedShips[ship]
	if not state then
		return
	end

	disconnectAll(state.Connections)
	for instance in pairs(state.Watched) do
		originalStateByInstance[instance] = nil
	end
	trackedShips[ship] = nil
end

task.spawn(function()
	local shipSystem = resolveWorkspacePath(ShipVisuals.ShipSystemPath)
	local activeShips = shipSystem and shipSystem:WaitForChild(ShipVisuals.ActiveShipsName, 30)
	if not activeShips then
		warn("[ShipOwnerInteractionFilter] Missing ActiveShips folder; owner-only ship prompts will not be locally filtered.")
		return
	end

	for _, ship in ipairs(activeShips:GetChildren()) do
		watchShip(ship)
	end

	activeShips.ChildAdded:Connect(watchShip)
	activeShips.ChildRemoved:Connect(unwatchShip)
end)
