local tool = script.Parent
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SafeAnimation = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("SafeAnimation"))

local event = ReplicatedStorage:WaitForChild("Slap")

local player = game.Players.LocalPlayer
local char = player.Character or player.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local animTrack = SafeAnimation.LoadTrack(hum, 119351181413931)

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

	if animTrack then
		animTrack:Play()
	end
end)
