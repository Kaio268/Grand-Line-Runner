local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer

local ReactModalRegistry = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ReactModalRegistry"))

local backpack = player:WaitForChild("Backpack")

local suffix = "SpeedCoil"
local character
local charConn

local function shouldMove()
	return ReactModalRegistry.IsVisible("SpeedUpgrade") or ReactModalRegistry.IsVisible("Rebirth")
end

local function isSpeedCoilTool(inst)
	return inst:IsA("Tool") and inst.Name:sub(-#suffix) == suffix
end

local function moveExisting()
	if not character or not shouldMove() then return end
	for _, child in ipairs(character:GetChildren()) do
		if isSpeedCoilTool(child) then
			child.Parent = backpack
		end
	end
end

local function bindCharacter(char)
	character = char
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end

	moveExisting()

	charConn = character.ChildAdded:Connect(function(child)
		if shouldMove() and isSpeedCoilTool(child) then
			child.Parent = backpack
		end
	end)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	bindCharacter(player.Character)
end

local function onVisibleChanged()
	moveExisting()
end

ReactModalRegistry.GetChangedSignal():Connect(function(name)
	if name == "SpeedUpgrade" or name == "Rebirth" then
		onVisibleChanged()
	end
end)
