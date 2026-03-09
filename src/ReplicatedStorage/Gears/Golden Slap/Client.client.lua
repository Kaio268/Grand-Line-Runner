local tool = script.Parent
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local event = ReplicatedStorage:WaitForChild("Slap")

local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://119351181413931"

local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local animator = hum:WaitForChild("Animator")

local animTrack = animator:LoadAnimation(anim)

tool.Activated:Connect(function()
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	local origin = hrp.Position
	local direction = hrp.CFrame.LookVector * 15

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {char, tool}
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, direction, params)
	if not result then return end

	local hitPart = result.Instance
	if hitPart:IsDescendantOf(char) then return end

	event:FireServer(hitPart)

	animTrack:Play()
end)
