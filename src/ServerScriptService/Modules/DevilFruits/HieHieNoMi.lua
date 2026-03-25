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

local function playIceBoostAnimation(humanoid, duration)
	local animation = Instance.new("Animation")
	animation.AnimationId = iceBoostAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	
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
	playIceBlastAnimation(context.Humanoid)
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
	local humanoid = context.Humanoid
	local abilityConfig = context.AbilityConfig
	local duration = math.max(0, tonumber(abilityConfig.Duration) or 0)
	local speedMultiplier = math.max(1, tonumber(abilityConfig.SpeedMultiplier) or 2)

	playIceBoostAnimation(humanoid, duration)
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
