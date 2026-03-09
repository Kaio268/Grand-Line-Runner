local Players = game:GetService("Players")
local player = Players.LocalPlayer

local playerGui = player:WaitForChild("PlayerGui")
local framesFolder = playerGui:WaitForChild("Frames")

local speedUpgradeFrame = framesFolder:WaitForChild("SpeedUpgrade")
local rebirthFrame = framesFolder:WaitForChild("Rebirth")

local backpack = player:WaitForChild("Backpack")

local suffix = "SpeedCoil"
local character
local charConn

local function shouldMove()
	return speedUpgradeFrame.Visible or rebirthFrame.Visible
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

speedUpgradeFrame:GetPropertyChangedSignal("Visible"):Connect(onVisibleChanged)
rebirthFrame:GetPropertyChangedSignal("Visible"):Connect(onVisibleChanged)
