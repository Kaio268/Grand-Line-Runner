local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PremiumCrewStealConfig")
)
local ShipRuntimeService = require(ServerScriptService.Modules:WaitForChild("ShipRuntimeService"))
local ShipSlotService = require(ServerScriptService.Modules:WaitForChild("ShipSlotService"))

local Visuals = {}

local BUBBLE_NAME = "PremiumCrewStealProtectionBubble"
local started = false
local playerConnections = {}

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

local function ensureBubble(placedModel)
	if not (placedModel and placedModel:IsA("Model")) then
		return
	end

	local existing = placedModel:FindFirstChild(BUBBLE_NAME)
	if existing and existing:IsA("BasePart") then
		return
	elseif existing then
		existing:Destroy()
	end

	local boxCFrame, boxSize = placedModel:GetBoundingBox()
	local diameter = math.max(boxSize.X, boxSize.Y, boxSize.Z, 3) + 1.2

	local bubble = Instance.new("Part")
	bubble.Name = BUBBLE_NAME
	bubble.Shape = Enum.PartType.Ball
	bubble.Material = Enum.Material.ForceField
	bubble.Color = Color3.fromRGB(85, 205, 255)
	bubble.Transparency = 0.58
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanTouch = false
	bubble.CanQuery = false
	bubble.CastShadow = false
	bubble.Size = Vector3.new(diameter, diameter, diameter)
	bubble.CFrame = boxCFrame
	bubble.Parent = placedModel
end

function Visuals.UpdateStand(player, standModel)
	if typeof(standModel) ~= "Instance" then
		return
	end

	local placedModel = standModel:FindFirstChild("PlacedCrewMember")
	if not placedModel then
		return
	end

	if isProtected(player) then
		ensureBubble(placedModel)
	else
		destroyBubble(placedModel)
	end
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

	Players.PlayerAdded:Connect(bindPlayer)
	Players.PlayerRemoving:Connect(disconnectPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		bindPlayer(player)
	end
end

return Visuals
