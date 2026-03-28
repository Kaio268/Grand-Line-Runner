local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local animations = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")
local HieHieNoMi = {}
local iceBlastAnimation = animations.Hie:WaitForChild("IceBlast")
local iceBoostAnimation = animations.Hie:WaitForChild("IceBoost")

local lastSpawnInfo = {}
local TRAIL_DISTANCE_THRESHOLD = 2.2
local TRAIL_TIME_THRESHOLD = 0.1

local function playIceBlastAnimation(humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = iceBlastAnimation.AnimationId
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	return track
end

local function playIceBoostAnimation(humanoid, duration)
	local animation = Instance.new("Animation")
	animation.AnimationId = iceBoostAnimation.AnimationId
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
	local humanoid = context.Humanoid
	local track = playIceBlastAnimation(humanoid)
	local abilityConfig = context.AbilityConfig
	local direction = getForwardDirection(context.RootPart)

	-- Wait for "IceBlast" marker with a 1.0s timeout safety
	local startTime = os.clock()
	local markerReached = false
	local markerConnection
	markerConnection = track:GetMarkerReachedSignal("IceBlast"):Connect(function()
		markerReached = true
	end)

	while not markerReached and (os.clock() - startTime) < 1.0 do
		task.wait()
	end

	if markerConnection then
		markerConnection:Disconnect()
	end

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
	
	playIceBoostAnimation(humanoid, duration)
	
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

local function spawnIceTrail(player, rootCFrame, duration)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local hieParticles = assets and assets:FindFirstChild("HieParticles")
	local iceTrail = hieParticles and hieParticles:FindFirstChild("IceTrail")

	if not iceTrail then return end

	local character = player.Character
	if not character then return end

	local rayOrigin = rootCFrame.Position
	local rayDirection = Vector3.new(0, -10, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local spawnPos = rayResult and rayResult.Position or (rootCFrame.Position - Vector3.new(0, 3, 0))
	local spawnCFrame = CFrame.new(spawnPos) * rootCFrame.Rotation

	local trailClone = iceTrail:Clone()
	trailClone.Parent = Workspace

	local baseplate = Workspace:FindFirstChild("Baseplate") or Workspace.Terrain

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

	Debris:AddItem(trailClone, duration)
end

local remotes = ReplicatedStorage:FindFirstChild("Remotes")
local effectTrigger = remotes and remotes:FindFirstChild("DevilFruitEffectTrigger")

if effectTrigger then
	effectTrigger.OnServerEvent:Connect(function(player, effectName, rootCFrame, duration)
		if effectName == "IceTrail" then
			local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
			if fruitAttribute == "Hie Hie no Mi" and typeof(rootCFrame) == "CFrame" then
				local now = os.clock()
				local info = lastSpawnInfo[player]
				
				if info then
					local distance = (rootCFrame.Position - info.Position).Magnitude
					if distance < TRAIL_DISTANCE_THRESHOLD or (now - info.Time) < TRAIL_TIME_THRESHOLD then
						return
					end
				end
				
				lastSpawnInfo[player] = {
					Position = rootCFrame.Position,
					Time = now
				}
				
				spawnIceTrail(player, rootCFrame, duration)
			end
		end
	end)
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	lastSpawnInfo[player] = nil
end)

return HieHieNoMi
