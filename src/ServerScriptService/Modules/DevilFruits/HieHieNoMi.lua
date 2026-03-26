local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HieHieNoMi = {}
local iceBlastAnimation = "rbxassetid://112900668980719"
local iceBoostAnimation = "rbxassetid://84130968608346"

local function playIceBlastAnimation(humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = iceBlastAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	return track
end

local function cloneIceTrail(character, rootPart, foot, baseplate, iceTrail, duration)
	local trailClone = iceTrail:Clone()
	if not trailClone then return end

	trailClone.Parent = Workspace 

	local spawnCFrame = CFrame.new(foot.Position) * rootPart.CFrame.Rotation

	if trailClone:IsA("Model") then
		trailClone:PivotTo(spawnCFrame)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = baseplate
		weld.Part1 = trailClone.PrimaryPart or trailClone:FindFirstChildWhichIsA("BasePart")
		weld.Parent = trailClone
	else
		trailClone.CFrame = spawnCFrame

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = baseplate
		weld.Part1 = trailClone
		weld.Parent = trailClone
	end

	task.delay(duration, function()
		if trailClone then
			trailClone:Destroy()
		end
	end)
end

local function playIceBoostAnimation(humanoid, character, rootPart, foot, baseplate, iceTrail, duration)
	local animation = Instance.new("Animation")
	animation.AnimationId = iceBoostAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	
	if iceTrail then
		track:GetMarkerReachedSignal("Skate"):Connect(function()
			cloneIceTrail(character, rootPart, foot, baseplate, iceTrail, duration)
		end)
	end

	local moveConnection
	moveConnection = humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		if humanoid.MoveDirection.Magnitude > 0 then
			if not track.IsPlaying then
				track:Play()
			end
		else
			if track.IsPlaying then
				track:Stop()
			end
		end
	end)

	if humanoid.MoveDirection.Magnitude > 0 then
		track:Play()
	end

	task.delay(duration, function()
		if moveConnection then
			moveConnection:Disconnect()
		end
		if track then
			track:Stop()
			track:Destroy()
		end
	end)

	return track
end



local function getForwardDirection(rootPart)
	local look = rootPart.CFrame.LookVector
	local planarLook = Vector3.new(look.X, 0, look.Z)
	if planarLook.Magnitude > 0.01 then
		return planarLook.Unit
	end

	if look.Magnitude > 0.01 then
		return look.Unit
	end

	return Vector3.new(0, 0, -1)
end

function HieHieNoMi.FreezeShot(context)
	local humanoid = context.Humanoid
	playIceBlastAnimation(humanoid)
	local abilityConfig = context.AbilityConfig
	local direction = getForwardDirection(context.RootPart)

	return {
		Direction = direction,
		Range = abilityConfig.Range,
		ProjectileSpeed = abilityConfig.ProjectileSpeed,
		ProjectileRadius = abilityConfig.ProjectileRadius,
		FreezeDuration = abilityConfig.FreezeDuration,
	}
end

function HieHieNoMi.IceBoost(context)
	local player = context.Player
	local character = context.Character
	local rootPart = context.RootPart
	local abilityConfig = context.AbilityConfig
	local duration = math.max(0, tonumber(abilityConfig.Duration) or 0)
	local humanoid = context.Humanoid
	
	local foot = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg") or rootPart
	local baseplate = Workspace:FindFirstChild("Baseplate") or Workspace.Terrain
	local iceTrail = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Particles") and ReplicatedStorage.Assets.Particles:FindFirstChild("IceTrail")

	playIceBoostAnimation(humanoid, character, rootPart, foot, baseplate, iceTrail, duration)
	
	local speedMultiplier = math.max(1, tonumber(abilityConfig.SpeedMultiplier) or 2)
	local untilTime = os.clock() + duration

	player:SetAttribute("HieIceBoostUntil", untilTime)
	player:SetAttribute("HieIceBoostSpeedMultiplier", speedMultiplier)
	player:SetAttribute("HieIceBoostSpeedBonus", nil)

	task.delay(duration + 0.05, function()
		if player.Parent == nil then
			return
		end

		local currentUntil = player:GetAttribute("HieIceBoostUntil")
		if currentUntil == untilTime then
			player:SetAttribute("HieIceBoostUntil", nil)
			player:SetAttribute("HieIceBoostSpeedMultiplier", nil)
			player:SetAttribute("HieIceBoostSpeedBonus", nil)
		end
	end)

	return {
		Duration = duration,
		SpeedMultiplier = speedMultiplier,
	}
end

return HieHieNoMi
