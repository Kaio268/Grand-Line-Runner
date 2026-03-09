local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local event = ReplicatedStorage:WaitForChild("Slap")
local slapSoundTemplate = ReplicatedStorage:FindFirstChild("SlapSound")

local HIT_RANGE = 15
local RAGDOLL_TIME = 1.2

local PUSH_SPEED = 20
local UP_PUSH = 5       

local cooldown = {}

local function playSlapSound(parentPart)
	if not slapSoundTemplate or not parentPart then return end
	local s = slapSoundTemplate:Clone()
	s.Parent = parentPart
	s:Play()
	Debris:AddItem(s, 2)
end

local function ragdollAndPush(attackerRoot, targetHum, targetRoot)
	targetHum:ChangeState(Enum.HumanoidStateType.Ragdoll)
	targetHum.PlatformStand = true
	targetHum.AutoRotate = false

	pcall(function()
		targetRoot:SetNetworkOwner(nil)
	end)

	local forward = attackerRoot.CFrame.LookVector
	local mass = targetRoot.AssemblyMass

	local impulse = (forward * (mass * PUSH_SPEED)) + Vector3.new(0, mass * UP_PUSH, 0)
	targetRoot:ApplyImpulse(impulse)

	playSlapSound(targetRoot)

	task.delay(RAGDOLL_TIME, function()
		if targetHum and targetHum.Parent then
			targetHum.PlatformStand = false
			targetHum.AutoRotate = true
			targetHum:ChangeState(Enum.HumanoidStateType.GettingUp)

			local targetPlayer = Players:GetPlayerFromCharacter(targetHum.Parent)
			if targetPlayer then
				pcall(function()
					targetRoot:SetNetworkOwner(targetPlayer)
				end)
			end
		end
	end)
end

event.OnServerEvent:Connect(function(player, hitPart)
	if cooldown[player] then return end
	cooldown[player] = true
	task.delay(0.25, function()
		cooldown[player] = nil
	end)

	if not player.Character then return end
	if typeof(hitPart) ~= "Instance" or not hitPart:IsA("BasePart") then return end

	local attackerChar = player.Character
	local attackerRoot = attackerChar:FindFirstChild("HumanoidRootPart")
	if not attackerRoot then return end

	local targetModel = hitPart:FindFirstAncestorOfClass("Model")
	if not targetModel then return end

	if targetModel == attackerChar then return end

	local targetPlayer = Players:GetPlayerFromCharacter(targetModel)
	if not targetPlayer then return end

	local targetHum = targetModel:FindFirstChildOfClass("Humanoid")
	local targetRoot = targetModel:FindFirstChild("HumanoidRootPart")
	if not targetHum or not targetRoot then return end
	if targetHum.Health <= 0 then return end

	local dist = (attackerRoot.Position - targetRoot.Position).Magnitude
	if dist > HIT_RANGE then return end

	ragdollAndPush(attackerRoot, targetHum, targetRoot)
end)
