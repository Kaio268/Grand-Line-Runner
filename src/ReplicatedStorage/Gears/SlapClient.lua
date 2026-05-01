local Players = game:GetService("Players")

local SlapClient = {}

local LIVE_SAFE_SLAP_ANIMATION_ID = "rbxassetid://129967390"
local LOAD_WARN_COOLDOWN = 10

local player = Players.LocalPlayer
local animation = Instance.new("Animation")
animation.Name = "SlapSwing"
animation.AnimationId = LIVE_SAFE_SLAP_ANIMATION_ID

local lastLoadWarnAt = 0

local function warnLoadFailure(tool, detail)
	local now = os.clock()
	if now - lastLoadWarnAt < LOAD_WARN_COOLDOWN then
		return
	end

	lastLoadWarnAt = now
	warn(string.format(
		"[SLAP CLIENT][WARN] failed to load slap animation tool=%s animationId=%s detail=%s",
		tostring(tool and tool.Name or "<nil>"),
		LIVE_SAFE_SLAP_ANIMATION_ID,
		tostring(detail)
	))
end

local function getCharacterContext()
	local character = player and player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return nil, nil, nil
	end

	return character, humanoid, rootPart
end

local function getAnimator(humanoid)
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	local ok, waitedAnimator = pcall(function()
		return humanoid:WaitForChild("Animator", 1)
	end)
	if ok and waitedAnimator and waitedAnimator:IsA("Animator") then
		return waitedAnimator
	end

	return nil
end

function SlapClient.Bind(tool)
	if not tool or not tool:IsA("Tool") then
		return
	end

	local currentHumanoid = nil
	local currentTrack = nil

	local function getAnimationTrack()
		local character, humanoid = getCharacterContext()
		if not character or not humanoid then
			return nil, nil
		end

		if currentHumanoid ~= humanoid or currentTrack == nil then
			local animator = getAnimator(humanoid)
			if not animator then
				return nil, nil
			end

			local ok, trackOrError = pcall(function()
				return animator:LoadAnimation(animation)
			end)
			if not ok or not trackOrError then
				currentHumanoid = nil
				currentTrack = nil
				warnLoadFailure(tool, trackOrError)
				return nil, nil
			end

			currentHumanoid = humanoid
			currentTrack = trackOrError
			currentTrack.Priority = Enum.AnimationPriority.Action
		end

		return currentTrack, character
	end

	tool.Activated:Connect(function()
		local animationTrack, character = getAnimationTrack()
		if not animationTrack or not character then
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		if not rootPart then
			return
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character, tool }
		params.IgnoreWater = true

		local result = workspace:Raycast(rootPart.Position, rootPart.CFrame.LookVector * 15, params)
		if not result or result.Instance:IsDescendantOf(character) then
			return
		end

		animationTrack:Play()
	end)
end

return SlapClient
