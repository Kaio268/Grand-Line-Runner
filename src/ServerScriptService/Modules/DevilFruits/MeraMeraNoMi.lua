local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local flameDashAnimation = "rbxassetid://93759237368646"
local flameBurstAnimation = "rbxassetid://92151793966516"
local MeraMeraNoMi = {}

local WALL_PADDING = 2
local MIN_END_CARRY_SPEED = 52
local END_CARRY_SPEED_FACTOR = 0.82

local function cloneFlame(character, rootPart, flame)
	print("Marker Reached!")

	local flameClone = flame:Clone()
	if not flameClone then return end

	flameClone.Parent = character 

	-- Calculate the CFrame: Start with RootPart, then rotate 90 degrees on the Y axis
	-- Use * CFrame.Angles instead of modifying .Orientation separately
	local rotationOffset = CFrame.Angles(0, math.rad(90), 0)
	local spawnCFrame = rootPart.CFrame * rotationOffset

	if flameClone:IsA("Model") then
		-- PivotTo is the most reliable way to move models and their children
		flameClone:PivotTo(spawnCFrame)

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = flameClone.PrimaryPart or flameClone:FindFirstChildWhichIsA("BasePart")
		weld.Parent = flameClone
	else
		flameClone.CFrame = spawnCFrame

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = flameClone
		weld.Parent = flameClone
	end

	task.wait(0.5)
	if flameClone then
		flameClone:Destroy()
	end
end

local function cloneTrail(character, rootPart, foot, baseplate, trail)
	print("Marker Reached!")

	local trailClone = trail:Clone()
	if not trailClone then return end

	trailClone.Parent = character 

	-- COMBINE: Position of the Foot + Rotation of the RootPart
	-- Then apply your 90-degree Y-axis offset
	local rotationOffset = CFrame.Angles(0, math.rad(90), 0)
	local spawnCFrame = CFrame.new(foot.Position) * (rootPart.CFrame.Rotation * rotationOffset)

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

	task.wait(0.5)
	if trailClone then
		trailClone:Destroy()
	end
end

local function playFlameDashAnimation(humanoid, character, rootPart, foot, baseplate, flame, trail)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameDashAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	
	if flame then
		track:GetMarkerReachedSignal("Flame"):Connect(function()
			cloneFlame(character, rootPart, flame)
		end)
	end
	
	if trail then
		track:GetMarkerReachedSignal("Trail"):Connect(function()
			cloneTrail(character, rootPart, foot, baseplate, trail)
		end)
	end

	track:Play()
	return track
end

local function cloneFlameBurst(character, foot, flameBurst)
	print("Marker Reached!")

	local flameBurstClone = flameBurst:Clone()
	if not flameBurstClone then return end

	-- Parent it to the character so it moves with you
	flameBurstClone.Parent = character 

	-- Position it at the character and match their orientation (X/Z axis)
	local spawnCFrame = foot.CFrame * CFrame.new(0, 0, 0)

	if flameBurstClone:IsA("Model") then
		if not flameBurstClone.PrimaryPart then
			flameBurstClone.PrimaryPart = flameBurstClone:FindFirstChildWhichIsA("BasePart")
		end
		
		if flameBurstClone.PrimaryPart then
			flameBurstClone:SetPrimaryPartCFrame(spawnCFrame)

			-- Optional: Weld it to the player so it follows them as they move
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = foot
			weld.Part1 = flameBurstClone.PrimaryPart
			weld.Parent = flameBurstClone
		end
	elseif flameBurstClone:IsA("BasePart") then
		flameBurstClone.CFrame = spawnCFrame

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = foot
		weld.Part1 = flameBurstClone
		weld.Parent = flameBurstClone
	end

	task.wait(1.5)
	if flameBurstClone then
		flameBurstClone:Destroy()
	end
end

local function playFlameBurstAnimation(humanoid, character, foot, flameBurst)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameBurstAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	
	if flameBurst then
		track:GetMarkerReachedSignal("FlameBurst"):Connect(function()
			cloneFlameBurst(character, foot, flameBurst)
		end)
	end
	
	track:Play()
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
	local baseplate = Workspace:FindFirstChild("Baseplate") or Workspace.Terrain
	local flame = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Particles") and ReplicatedStorage.Assets.Particles:FindFirstChild("Flame")
	local trail = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Particles") and ReplicatedStorage.Assets.Particles:FindFirstChild("FlameTrail")

	playFlameDashAnimation(humanoid, character, rootPart, foot, baseplate, flame, trail)

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
	local abilityConfig = context.AbilityConfig
	
	-- Fallback chain for foot, depending on Rig type
	local foot = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg") or context.RootPart
	local flameBurst = ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("Particles") and ReplicatedStorage.Assets.Particles:FindFirstChild("FlameBurst")

	local flameburstTrack = playFlameBurstAnimation(humanoid, character, foot, flameBurst)

	return {
		Radius = abilityConfig.Radius,
		Duration = abilityConfig.Duration,
	}
end

return MeraMeraNoMi
