local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local animations = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Animations")
local Debris = game:GetService("Debris")
local flameDashAnimation = animations.Mera:WaitForChild("FlameDash")
local flameBurstAnimation = animations.Mera:WaitForChild("FlameBurst")
local MeraMeraNoMi = {}

local WALL_PADDING = 2
local MIN_END_CARRY_SPEED = 52
local END_CARRY_SPEED_FACTOR = 0.82

local function spawnStationaryGroundParticles(character, target, folder, emitCountMultiplier)
	local meraParticles = ReplicatedStorage:FindFirstChild("MeraParticles") or (ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("MeraParticles"))
	local targetFolder = meraParticles and meraParticles:FindFirstChild(folder)
	
	if not targetFolder then return end

	local targetCFrame = typeof(target) == "CFrame" and target or CFrame.new(target)
	local position = targetCFrame.Position

	-- Ground detection
	local rayOrigin = position + Vector3.new(0, 2, 0)
	local rayDirection = Vector3.new(0, -10, 0)
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local result = Workspace:Raycast(rayOrigin, rayDirection, params)
	local spawnPos = result and result.Position or (position - Vector3.new(0, 3, 0))

	-- Create a temporary part to hold the particles
	local effectPart = Instance.new("Part")
	effectPart.Name = "MeraEffect"
	effectPart.Size = Vector3.new(1, 1, 1)
	effectPart.Transparency = 1
	effectPart.CanCollide = false
	effectPart.Anchored = true
	-- Use ground position but keep original rotation
	effectPart.CFrame = CFrame.new(spawnPos) * targetCFrame.Rotation
	effectPart.Parent = Workspace
	
	for _, particle in ipairs(targetFolder:GetChildren()) do
		if particle:IsA("ParticleEmitter") then
			local clone = particle:Clone()
			clone.LockedToPart = false
			clone.Parent = effectPart
			clone:Emit((clone:GetAttribute("EmitCount") or 100) * (emitCountMultiplier or 1))
		end
	end
	
	Debris:AddItem(effectPart, 3)
end

local function playFlameDashAnimation(humanoid, character, rootPart)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameDashAnimation.AnimationId
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action

	local flameConnection
	local dashConnection

	-- Cleanup function for all connections
	local function cleanup()
		if flameConnection then
			flameConnection:Disconnect()
			flameConnection = nil
		end
		if dashConnection then
			dashConnection:Disconnect()
			dashConnection = nil
		end
	end

	-- Start event: Start Flame (fixed) until End
	track:GetMarkerReachedSignal("Start"):Connect(function()
		local startPos = rootPart.Position
		if flameConnection then flameConnection:Disconnect() end
		
		-- Flame loop at fixed position
		flameConnection = RunService.Heartbeat:Connect(function()
			if not rootPart.Parent or not character.Parent then return end
			spawnStationaryGroundParticles(character, startPos, "Flame", 0.5)
		end)
	end)

	-- Trail event: Start Dash emission (moving trail)
	track:GetMarkerReachedSignal("Trail"):Connect(function()
		if dashConnection then dashConnection:Disconnect() end

		-- Dash loop following player with rotation
		dashConnection = RunService.Heartbeat:Connect(function()
			if not rootPart.Parent or not character.Parent then return end
			local rotationOffset = CFrame.Angles(0, math.rad(90), 0)
			local spawnCFrame = rootPart.CFrame * rotationOffset
			spawnStationaryGroundParticles(character, spawnCFrame, "Dash", 0.5)
		end)
	end)

	-- TrailEnd event: Stop Dash emission and spawn Trail particles
	track:GetMarkerReachedSignal("TrailEnd"):Connect(function()
		if dashConnection then
			dashConnection:Disconnect()
			dashConnection = nil
		end

		local rotationOffset = CFrame.Angles(0, math.rad(90), 0)
		local spawnCFrame = rootPart.CFrame * rotationOffset
		spawnStationaryGroundParticles(character, spawnCFrame, "Trail")
	end)

	-- End event: Stop all effects
	track:GetMarkerReachedSignal("End"):Connect(function()
		cleanup()
	end)

	track:Play()

	track.Stopped:Connect(function()
		cleanup()
	end)

	return track
end


local function playFlameBurstAnimation(humanoid, character, rootPart)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameBurstAnimation.AnimationId
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action

	local ringConnection

	-- Start event: Sustained Ring effect at feet
	track:GetMarkerReachedSignal("Start"):Connect(function()
		if ringConnection then ringConnection:Disconnect() end
		ringConnection = RunService.Heartbeat:Connect(function()
			if not rootPart.Parent or not character.Parent then return end
			spawnStationaryGroundParticles(character, rootPart.Position, "Ring", 0.5)
		end)
	end)

	-- FlameBurst event: Big burst at feet
	track:GetMarkerReachedSignal("FlameBurst"):Connect(function()
		-- Clean up Ring emission if active first
		if ringConnection then
			ringConnection:Disconnect()
			ringConnection = nil
		end
		
		spawnStationaryGroundParticles(character, rootPart.Position, "Burst", 1.5)
	end)

	-- End event: Stop Ring effect
	track:GetMarkerReachedSignal("End"):Connect(function()
		if ringConnection then
			ringConnection:Disconnect()
			ringConnection = nil
		end
	end)

	track:Play()

	track.Stopped:Connect(function()
		if ringConnection then
			ringConnection:Disconnect()
			ringConnection = nil
		end
	end)

	return track
end


local function smoothstep(alpha)
	return alpha * alpha * (3 - (2 * alpha))
end

local function getDashDirection(humanoid, rootPart)
	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude > 0.01 then
		return Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit
	end

	local look = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude > 0.01 then
		return flatLook.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getDashDistance(character, rootPart, direction, maxDistance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(rootPart.Position, direction * maxDistance, params)
	if not result then
		return maxDistance
	end

	local distance = math.max(result.Distance - WALL_PADDING, 0)
	return math.min(distance, maxDistance)
end

local function getCharacterPivotOffset(character, rootPart)
	local pivot = character:GetPivot()
	return pivot.Position - rootPart.Position
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getPlanarMagnitude(vector)
	return getPlanarVector(vector).Magnitude
end

local function getTravelDistance(startPosition, currentPosition, direction)
	local delta = getPlanarVector(currentPosition - startPosition)
	return math.max(delta:Dot(direction), 0)
end

local function getCurrentPlanarSpeed(humanoid, rootPart)
	return math.max(humanoid.WalkSpeed, getPlanarMagnitude(rootPart.AssemblyLinearVelocity))
end

local function getMaxDashDistance(humanoid, rootPart, abilityConfig)
	local baseDashDistance = tonumber(abilityConfig.DashDistance) or 42
	local distanceSpeedBonusFactor = tonumber(abilityConfig.DistanceSpeedBonusFactor) or 0
	local maxDistanceSpeedBonus = tonumber(abilityConfig.MaxDistanceSpeedBonus) or 0
	local currentPlanarSpeed = getCurrentPlanarSpeed(humanoid, rootPart)
	local bonusDistance = math.min(currentPlanarSpeed * distanceSpeedBonusFactor, maxDistanceSpeedBonus)

	return baseDashDistance + bonusDistance
end

local function getDashSpeeds(humanoid, rootPart, abilityConfig)
	local currentPlanarSpeed = getCurrentPlanarSpeed(humanoid, rootPart)
	local baseDashSpeed = tonumber(abilityConfig.BaseDashSpeed) or 120
	local dashSpeedMultiplier = tonumber(abilityConfig.DashSpeedMultiplier) or 2.8
	local endDashSpeedMultiplier = tonumber(abilityConfig.EndDashSpeedMultiplier) or 1.1
	local maxDashSpeed = tonumber(abilityConfig.MaxDashSpeed)

	local startDashSpeed = math.max(baseDashSpeed, currentPlanarSpeed * dashSpeedMultiplier)
	if maxDashSpeed then
		startDashSpeed = math.min(startDashSpeed, maxDashSpeed)
	end

	local endDashSpeed = math.max(humanoid.WalkSpeed, currentPlanarSpeed * endDashSpeedMultiplier)
	endDashSpeed = math.min(endDashSpeed, startDashSpeed)

	return currentPlanarSpeed, startDashSpeed, endDashSpeed
end

local function setHorizontalVelocity(rootPart, horizontalVelocity)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, currentVelocity.Y, horizontalVelocity.Z)
end

local function stopDashVelocity(rootPart)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
end

local function shouldStopForWall(character, rootPart, direction, lookAheadDistance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(rootPart.Position, direction * lookAheadDistance, params)
	return result ~= nil
end

local function pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
	local offset = getCharacterPivotOffset(character, rootPart)
	local pivot = character:GetPivot()
	local rotation = pivot - pivot.Position
	local targetPivot = CFrame.new(targetRootPosition + offset) * rotation
	character:PivotTo(targetPivot)
end

function MeraMeraNoMi.FlameDash(context)
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local abilityConfig = context.AbilityConfig
	
	local foot = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg") or rootPart
	
	local track = playFlameDashAnimation(humanoid, character, rootPart)

	local direction = getDashDirection(humanoid, rootPart)
	local maxDashDistance = getMaxDashDistance(humanoid, rootPart, abilityConfig)
	local dashDistance = getDashDistance(character, rootPart, direction, maxDashDistance)
	local dashDuration = tonumber(abilityConfig.DashDuration) or 0.18
	local _, startDashSpeed, endDashSpeed = getDashSpeeds(humanoid, rootPart, abilityConfig)
	local instantDashFraction = math.clamp(tonumber(abilityConfig.InstantDashFraction) or 0.58, 0, 1)

	if dashDistance <= 0.05 then
		return {
			Direction = direction,
			Distance = 0,
			Duration = dashDuration,
		}
	end

	local startPosition = rootPart.Position
	local instantDistance = dashDistance * instantDashFraction
	local remainingDistance = math.max(dashDistance - instantDistance, 0)
	local dashOwner = context.Player
	local endCarrySpeed = math.max(humanoid.WalkSpeed, endDashSpeed * END_CARRY_SPEED_FACTOR, MIN_END_CARRY_SPEED)

	task.spawn(function()
		local elapsed = 0
		local connection

		pcall(function()
			rootPart:SetNetworkOwner(nil)
		end)

		-- Wait for "Trail" marker with a 1.0s timeout safety
		local startTime = os.clock()
		local markerReached = false
		local markerConnection
		markerConnection = track:GetMarkerReachedSignal("Trail"):Connect(function()
			markerReached = true
		end)

		while not markerReached and (os.clock() - startTime) < 1.0 do
			task.wait()
		end

		if markerConnection then
			markerConnection:Disconnect()
		end

		if not character.Parent or not rootPart.Parent then return end

		if instantDistance > 0.05 and character.Parent and rootPart.Parent then
			local targetRootPosition = startPosition + direction * instantDistance
			pivotCharacterToRootPosition(character, rootPart, targetRootPosition)
			setHorizontalVelocity(rootPart, direction * startDashSpeed)
		end

		if remainingDistance <= 0.1 then
			setHorizontalVelocity(rootPart, direction * endCarrySpeed)
			if dashOwner and dashOwner.Parent then
				pcall(function()
					rootPart:SetNetworkOwner(dashOwner)
				end)
			end
			return
		end

		local burstStartPosition = rootPart.Position

		connection = RunService.Heartbeat:Connect(function(dt)
			if not character.Parent or humanoid.Health <= 0 or not rootPart.Parent then
				if connection then
					connection:Disconnect()
				end
				return
			end

			elapsed += dt

			local traveledDistance = getTravelDistance(burstStartPosition, rootPart.Position, direction)
			local currentRemainingDistance = remainingDistance - traveledDistance
			if currentRemainingDistance <= 0.1 then
				setHorizontalVelocity(rootPart, direction * endCarrySpeed)
				connection:Disconnect()
				return
			end

			local alpha = math.clamp(elapsed / dashDuration, 0, 1)
			local dashSpeed = startDashSpeed + ((endDashSpeed - startDashSpeed) * smoothstep(alpha))
			local lookAheadDistance = math.max((dashSpeed * dt) + WALL_PADDING, WALL_PADDING + 1)
			if shouldStopForWall(character, rootPart, direction, math.min(lookAheadDistance, currentRemainingDistance + WALL_PADDING)) then
				stopDashVelocity(rootPart)
				connection:Disconnect()
				return
			end

			setHorizontalVelocity(rootPart, direction * dashSpeed)

			if alpha >= 1 then
				setHorizontalVelocity(rootPart, direction * endCarrySpeed)
				connection:Disconnect()
			end
		end)

		task.wait(dashDuration + 0.05)

		if connection and connection.Connected then
			connection:Disconnect()
		end

		if dashOwner and dashOwner.Parent then
			pcall(function()
				rootPart:SetNetworkOwner(dashOwner)
			end)
		end
	end)

	return {
		Direction = direction,
		Distance = dashDistance,
		Duration = dashDuration,
	}
end

function MeraMeraNoMi.FireBurst(context)
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local abilityConfig = context.AbilityConfig
	
	playFlameBurstAnimation(humanoid, character, rootPart)

	return {
		Radius = abilityConfig.Radius,
		Duration = abilityConfig.Duration,
	}
end

return MeraMeraNoMi
