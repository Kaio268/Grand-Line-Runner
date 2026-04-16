local tool = script.Parent
local Players = game:GetService("Players")

-- animacja
local anim = Instance.new("Animation")
anim.AnimationId = "rbxassetid://119351181413931"

local player = Players.LocalPlayer

local currentHumanoid = nil
local currentTrack = nil

local function getAnimationTrack()
	local char = player.Character
	if not char then
		return nil, nil
	end

	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then
		return nil, nil
	end

	if currentHumanoid ~= hum or currentTrack == nil then
		local animator = hum:FindFirstChildOfClass("Animator") or hum:WaitForChild("Animator", 1)
		if not animator then
			return nil, nil
		end

		currentHumanoid = hum
		currentTrack = animator:LoadAnimation(anim)
	end

	return currentTrack, char
end

tool.Activated:Connect(function()
	local animTrack, char = getAnimationTrack()
	if not animTrack or not char then return end

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

	animTrack:Play()
end)
