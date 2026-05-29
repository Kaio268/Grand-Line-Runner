local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local Config = require(
	Configs:WaitForChild("PremiumCrewStealConfig")
)
local CrewOverhead = require(Modules:WaitForChild("Crew"):WaitForChild("CrewOverhead"))
local ShipVisuals = require(Configs:WaitForChild("ShipVisuals"))
local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))

local Visuals = {}

local BUBBLE_NAME = "PremiumCrewStealProtectionBubble"
local OWNER_USER_ID_ATTRIBUTE = ShipVisuals.Attributes.OwnerUserId or "OwnerUserId"
local OVERHEAD_ATTRIBUTES = CrewOverhead.Attribute
local FLEET_BUBBLE_STYLE = {
	Color = Color3.fromRGB(85, 205, 255),
	Padding = 1.2,
	Transparency = 0.58,
}
local CREW_BUBBLE_STYLE = {
	Color = Color3.fromRGB(111, 230, 124),
	Padding = FLEET_BUBBLE_STYLE.Padding,
	Transparency = FLEET_BUBBLE_STYLE.Transparency,
}
local started = false
local playerConnections = {}
local modelConnections = {}

local function isProtected(player)
	return typeof(player) == "Instance"
		and player:IsA("Player")
		and player:GetAttribute(Config.Attributes.ProtectionActive) == true
end

local function destroyBubble(placedModel)
	local existing = placedModel and placedModel:FindFirstChild(BUBBLE_NAME)
	if existing then
		existing:Destroy()
	end
end

local function findActiveShipAncestor(instance)
	local current = instance
	while current do
		if ShipRuntimeService.IsActiveShip(current) then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function resolveOwnerPlayer(placedModel)
	local activeShip = findActiveShipAncestor(placedModel)
	local ownerUserId = activeShip and tonumber(activeShip:GetAttribute(OWNER_USER_ID_ATTRIBUTE))
	if ownerUserId == nil then
		return nil
	end

	return Players:GetPlayerByUserId(ownerUserId)
end

local function resolveBubbleStyle(player, placedModel)
	local protectionType = tostring(placedModel:GetAttribute(OVERHEAD_ATTRIBUTES.ProtectionType) or "")
	if protectionType == "permanent" then
		return nil
	elseif protectionType == "crew" then
		return CREW_BUBBLE_STYLE
	elseif protectionType == "fleet" then
		return FLEET_BUBBLE_STYLE
	end

	local ownerPlayer = player
	if not (ownerPlayer and ownerPlayer:IsA("Player")) then
		ownerPlayer = resolveOwnerPlayer(placedModel)
	end

	if isProtected(ownerPlayer) then
		return FLEET_BUBBLE_STYLE
	end

	return nil
end

local function getBoundsExcludingBubble(placedModel)
	local bubble = placedModel:FindFirstChild(BUBBLE_NAME)
	local minimum = nil
	local maximum = nil

	for _, descendant in ipairs(placedModel:GetDescendants()) do
		local isBubble = bubble ~= nil and (descendant == bubble or descendant:IsDescendantOf(bubble))
		if descendant:IsA("BasePart") and not isBubble then
			local halfSize = descendant.Size * 0.5
			local partCFrame = descendant.CFrame

			for xSign = -1, 1, 2 do
				for ySign = -1, 1, 2 do
					for zSign = -1, 1, 2 do
						local offset = Vector3.new(halfSize.X * xSign, halfSize.Y * ySign, halfSize.Z * zSign)
						local corner = partCFrame * offset

						if minimum == nil or maximum == nil then
							minimum = corner
							maximum = corner
						else
							minimum = Vector3.new(
								math.min(minimum.X, corner.X),
								math.min(minimum.Y, corner.Y),
								math.min(minimum.Z, corner.Z)
							)
							maximum = Vector3.new(
								math.max(maximum.X, corner.X),
								math.max(maximum.Y, corner.Y),
								math.max(maximum.Z, corner.Z)
							)
						end
					end
				end
			end
		end
	end

	if minimum == nil or maximum == nil then
		return placedModel:GetPivot(), Vector3.new(3, 3, 3)
	end

	local center = (minimum + maximum) * 0.5
	return CFrame.new(center), maximum - minimum
end

local function applyBubbleStyle(placedModel, style)
	if not (placedModel and placedModel:IsA("Model")) then
		return
	end
	if style == nil then
		destroyBubble(placedModel)
		return
	end

	local existing = placedModel:FindFirstChild(BUBBLE_NAME)
	local bubble = nil
	if existing and existing:IsA("Part") then
		bubble = existing
	elseif existing then
		existing:Destroy()
	end

	local boxCFrame, boxSize = getBoundsExcludingBubble(placedModel)
	local diameter = math.max(boxSize.X, boxSize.Y, boxSize.Z, 3) + math.max(0, tonumber(style.Padding) or 0)

	if bubble == nil then
		bubble = Instance.new("Part")
		bubble.Name = BUBBLE_NAME
		bubble.Parent = placedModel
	end

	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.ForceField
	bubble.Color = style.Color
	bubble.Transparency = math.clamp(tonumber(style.Transparency) or 0.58, 0, 1)
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanTouch = false
	bubble.CanQuery = false
	bubble.CastShadow = false
	bubble.Size = Vector3.new(diameter, diameter, diameter)
	bubble.CFrame = boxCFrame
	if bubble.Parent ~= placedModel then
		bubble.Parent = placedModel
	end
end

local function updatePlacedModel(player, placedModel)
	if not (placedModel and placedModel:IsA("Model")) then
		return
	end

	applyBubbleStyle(placedModel, resolveBubbleStyle(player, placedModel))
end

function Visuals.UpdateStand(player, standModel)
	if typeof(standModel) ~= "Instance" then
		return
	end

	local placedModel = standModel:FindFirstChild("PlacedCrewMember")
	if not placedModel then
		return
	end

	updatePlacedModel(player, placedModel)
end

function Visuals.ClearStand(standModel)
	if typeof(standModel) ~= "Instance" then
		return
	end

	local placedModel = standModel:FindFirstChild("PlacedCrewMember")
	if placedModel then
		destroyBubble(placedModel)
	end
end

function Visuals.UpdatePlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if not activeShip or not ShipRuntimeService.IsActiveShip(activeShip) then
		return
	end

	for _, slotNumber in ipairs(ShipSlotService.GetAvailableSlotNumbers(activeShip)) do
		local standModel = ShipSlotService.GetSlot(activeShip, tostring(slotNumber))
		if standModel then
			Visuals.UpdateStand(player, standModel)
		end
	end
end

function Visuals.ClearPlayer(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return
	end

	local activeShip = ShipRuntimeService.GetActiveShip(player)
	if not activeShip or not ShipRuntimeService.IsActiveShip(activeShip) then
		return
	end

	for _, slotNumber in ipairs(ShipSlotService.GetAvailableSlotNumbers(activeShip)) do
		local standModel = ShipSlotService.GetSlot(activeShip, tostring(slotNumber))
		if standModel then
			Visuals.ClearStand(standModel)
		end
	end
end

local function disconnectModel(model)
	local connections = modelConnections[model]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	modelConnections[model] = nil
end

local function trackModel(model)
	if modelConnections[model] or not (model and model:IsA("Model")) then
		return
	end

	local connections = {}
	modelConnections[model] = connections
	table.insert(connections, model:GetAttributeChangedSignal(OVERHEAD_ATTRIBUTES.ProtectionType):Connect(function()
		updatePlacedModel(nil, model)
	end))
	table.insert(connections, model:GetAttributeChangedSignal(OVERHEAD_ATTRIBUTES.Kind):Connect(function()
		updatePlacedModel(nil, model)
	end))
	table.insert(connections, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			disconnectModel(model)
		else
			updatePlacedModel(nil, model)
		end
	end))

	task.defer(function()
		if model.Parent ~= nil then
			updatePlacedModel(nil, model)
		end
	end)
end

local function disconnectPlayer(player)
	local connections = playerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
	end
	playerConnections[player] = nil
	Visuals.ClearPlayer(player)
end

local function bindPlayer(player)
	disconnectPlayer(player)
	local connections = {}
	playerConnections[player] = connections

	table.insert(connections, player:GetAttributeChangedSignal(Config.Attributes.ProtectionActive):Connect(function()
		Visuals.UpdatePlayer(player)
	end))
	table.insert(connections, player:GetAttributeChangedSignal(Config.Attributes.ProtectionSource):Connect(function()
		Visuals.UpdatePlayer(player)
	end))

	task.defer(function()
		if player.Parent == Players then
			Visuals.UpdatePlayer(player)
		end
	end)
end

function Visuals.Start()
	if started then
		return
	end
	started = true

	CollectionService:GetInstanceAddedSignal(CrewOverhead.Tag):Connect(trackModel)
	CollectionService:GetInstanceRemovedSignal(CrewOverhead.Tag):Connect(function(model)
		disconnectModel(model)
		destroyBubble(model)
	end)
	for _, model in ipairs(CollectionService:GetTagged(CrewOverhead.Tag)) do
		trackModel(model)
	end

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(disconnectPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

return Visuals
