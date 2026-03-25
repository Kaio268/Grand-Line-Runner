local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local gomuRocketAnim = "rbxassetid://106521727746519"
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GomuGomuNoMi = {}

local WALL_PADDING = 1.5
local MIN_DIRECTION_MAGNITUDE = 0.01
local MIN_HORIZONTAL_LAUNCH_SPEED = 110
local MIN_VERTICAL_LAUNCH_SPEED = 52
local HORIZONTAL_SPEED_MULTIPLIER = 1.9
local VERTICAL_SPEED_RATIO = 0.58
local NETWORK_OWNER_RELEASE_DELAY = 0.45

local function playGomuRocketAnim(humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = gomuRocketAnim
	local track = humanoid:LoadAnimation(animation)
	track.Priority = Enum.AnimationPriority.Action
	track:Play()
	return track
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getPlanarUnitOrNil(vector)
	local planarVector = getPlanarVector(vector)
	if planarVector.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarVector.Unit
	end

	return nil
end

local function getFallbackDirection(rootPart)
	return getPlanarUnitOrNil(rootPart.CFrame.LookVector) or Vector3.new(0, 0, -1)
end

local function getRequestedTargetPosition(context)
	local payload = context.RequestPayload
	if typeof(payload) ~= "table" then
		return nil, nil
	end

	local targetPlayerUserId = payload.TargetPlayerUserId
	if typeof(targetPlayerUserId) == "number" then
		local targetPlayer = Players:GetPlayerByUserId(targetPlayerUserId)
		if targetPlayer and targetPlayer ~= context.Player then
			local targetCharacter = targetPlayer.Character
			local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
			local targetRootPart = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
			if targetHumanoid and targetRootPart and targetHumanoid.Health > 0 then
				return targetRootPart.Position, targetPlayer
			end
		end
	end

	local aimPosition = payload.AimPosition
	if typeof(aimPosition) == "Vector3" then
		return aimPosition, nil
	end

	return nil, nil
end

local function getLaunchDirectionAndTarget(context)
	local rootPart = context.RootPart
	local rootPosition = rootPart.Position
	local targetPosition, targetPlayer = getRequestedTargetPosition(context)

	if targetPosition then
		local direction = getPlanarUnitOrNil(targetPosition - rootPosition)
		if direction then
			return direction, Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z), targetPlayer
		end
	end

	local fallbackDirection = getFallbackDirection(rootPart)
	local maxDistance = math.max(0, tonumber(context.AbilityConfig.LaunchDistance) or 20)
	return fallbackDirection, rootPosition + (fallbackDirection * maxDistance), nil
end

local function getLaunchDistance(character, rootPart, direction, maxDistance)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	params.IgnoreWater = true

	local result = Workspace:Raycast(rootPart.Position, direction * maxDistance, params)
	if not result then
		return maxDistance
	end

	return math.min(math.max(result.Distance - WALL_PADDING, 0), maxDistance)
end

local function getLaunchVelocity(direction, launchDistance, maxDistance, launchDuration)
	local averageSpeed = launchDistance / launchDuration
	local distanceAlpha = math.clamp(maxDistance > 0 and (launchDistance / maxDistance) or 1, 0.25, 1)
	local horizontalLaunchSpeed =
		math.max(averageSpeed * HORIZONTAL_SPEED_MULTIPLIER, MIN_HORIZONTAL_LAUNCH_SPEED * distanceAlpha)
	local verticalLaunchSpeed =
		math.max(horizontalLaunchSpeed * VERTICAL_SPEED_RATIO, MIN_VERTICAL_LAUNCH_SPEED * distanceAlpha)

	return Vector3.new(direction.X * horizontalLaunchSpeed, verticalLaunchSpeed, direction.Z * horizontalLaunchSpeed)
end

local function applyLaunchVelocity(rootPart, launchVelocity)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = launchVelocity

	local velocityDelta = launchVelocity - currentVelocity
	local impulse = velocityDelta * rootPart.AssemblyMass
	rootPart:ApplyImpulse(impulse)
end

function GomuGomuNoMi.RubberLaunch(context)
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local abilityConfig = context.AbilityConfig
	playGomuRocketAnim(humanoid)
	local direction, targetPosition, targetPlayer = getLaunchDirectionAndTarget(context)
	local startPosition = rootPart.Position
	local maxDistance = math.max(0, tonumber(abilityConfig.LaunchDistance) or 20)
	local launchDistance = getLaunchDistance(character, rootPart, direction, maxDistance)
	local launchDuration = math.max(0.05, tonumber(abilityConfig.LaunchDuration) or 0.35)
	local launchVelocity = getLaunchVelocity(direction, launchDistance, maxDistance, launchDuration)
	local launchOwner = context.Player

	if launchDistance <= 0.05 then
		return {
			Direction = direction,
			Distance = 0,
			Duration = launchDuration,
			StartPosition = startPosition,
			EndPosition = startPosition,
			TargetPosition = targetPosition,
			TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
		}
	end

	task.spawn(function()
		pcall(function()
			rootPart:SetNetworkOwner(nil)
		end)

		humanoid.Jump = true
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		applyLaunchVelocity(rootPart, launchVelocity)

		task.delay(NETWORK_OWNER_RELEASE_DELAY, function()
			if not character.Parent or humanoid.Health <= 0 or not rootPart.Parent then
				return
			end

			if launchOwner and launchOwner.Parent then
				pcall(function()
					rootPart:SetNetworkOwner(launchOwner)
				end)
			end
		end)
	end)

	return {
		Direction = direction,
		Distance = launchDistance,
		Duration = launchDuration,
		LaunchVelocity = launchVelocity,
		StartPosition = startPosition,
		EndPosition = startPosition + (direction * launchDistance),
		TargetPosition = targetPosition,
		TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
	}
end

return GomuGomuNoMi
