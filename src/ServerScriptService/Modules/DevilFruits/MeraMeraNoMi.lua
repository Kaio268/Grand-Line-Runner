local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local flameDashAnimation = "rbxassetid://93759237368646"
local flameBurstAnimation = "rbxassetid://92151793966516"
local MeraMeraNoMi = {}

local WALL_PADDING = 2
local MIN_END_CARRY_SPEED = 52
local END_CARRY_SPEED_FACTOR = 0.82

local function smoothstep(alpha)
	return alpha * alpha * (3 - (2 * alpha))
end

local function playFlameDashAnimation(humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameDashAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	return track
end

local function playFlameBurstAnimation(humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = flameBurstAnimation
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	return track
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
	playFlameDashAnimation(humanoid)
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
			if
				shouldStopForWall(
					character,
					rootPart,
					direction,
					math.min(lookAheadDistance, currentRemainingDistance + WALL_PADDING)
				)
			then
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
	local abilityConfig = context.AbilityConfig
	playFlameBurstAnimation(context.Humanoid)
	return {
		Radius = abilityConfig.Radius,
		Duration = abilityConfig.Duration,
	}
end

return MeraMeraNoMi
