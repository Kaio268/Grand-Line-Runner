local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local GomuAnimationController = require(script.Parent:WaitForChild("GomuAnimationController"))
local RubberLaunchMath = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Gomu")
		:WaitForChild("Shared")
		:WaitForChild("RubberLaunchMath")
)

local GomuServer = {}
local activeLaunchCleanupByPlayer = {}

local WALL_PADDING = 1.5
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_FALLBACK_DIRECTION = Vector3.new(0, 0, -1)
local DEFAULT_LAUNCH_DISTANCE = 20
local DEFAULT_LAUNCH_DURATION = 0.35
local DEFAULT_ARM_RESTORE_FALLBACK_TIME = 0.85
local MIN_LAUNCH_DURATION = 0.05
local MIN_EFFECTIVE_LAUNCH_DISTANCE = 0.05
local MIN_HORIZONTAL_LAUNCH_SPEED = 145
local MIN_VERTICAL_LAUNCH_SPEED = 60
local HORIZONTAL_SPEED_MULTIPLIER = 2.15
local VERTICAL_SPEED_RATIO = 0.32
local MIN_DISTANCE_ALPHA = 0.25
local NETWORK_OWNER_RELEASE_DELAY = 0.65
local MOMENTUM_SUSTAIN_SPEED_FACTOR = 1
local MOMENTUM_SUSTAIN_GROUND_GRACE = 0.12
local MOMENTUM_SUSTAIN_COMPLETION_TOLERANCE = 1.25
local MOMENTUM_SUSTAIN_TIMEOUT_BUFFER = 1.75
local MIN_MOMENTUM_SUSTAIN_DURATION = 1
local MAX_MOMENTUM_SUSTAIN_DURATION = 4
local MIN_MOMENTUM_SUSTAIN_FORCE = 50000
local MOMENTUM_SUSTAIN_FORCE_PER_MASS = 9000
local TAKEOFF_CONSTRAINT_DURATION = 0.14
local NETWORK_OWNER_RETURN_AFTER_CONSTRAINT_DELAY = 0.14
local MOMENTUM_ATTACHMENT_NAME = "GomuLaunchMomentumAttachment"
local MOMENTUM_CONSTRAINT_NAME = "GomuLaunchMomentumSustain"
local TAKEOFF_ATTACHMENT_NAME = "GomuLaunchTakeoffAttachment"
local TAKEOFF_CONSTRAINT_NAME = "GomuLaunchTakeoff"
local LAUNCH_DISTANCE_OPTIONS = {
	BaseDistanceFallback = DEFAULT_LAUNCH_DISTANCE,
}
local WORLD_UP = Vector3.new(0, 1, 0)

local function getPlanarUnitOrNil(vector)
	local planarVector = RubberLaunchMath.GetPlanarVector(vector)
	if planarVector.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarVector.Unit
	end

	return nil
end

local function getFallbackDirection(rootPart)
	return getPlanarUnitOrNil(rootPart.CFrame.LookVector) or DEFAULT_FALLBACK_DIRECTION
end

local function getRequestedLookDirection(requestPayload)
	local payloadDirection = type(requestPayload) == "table" and requestPayload.LookDirection or nil
	return typeof(payloadDirection) == "Vector3" and getPlanarUnitOrNil(payloadDirection) or nil
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

	return nil, nil
end

local function getRequestedAimPosition(context)
	local payload = context.RequestPayload
	if typeof(payload) ~= "table" then
		return nil
	end

	local aimPosition = payload.AimPosition
	if typeof(aimPosition) == "Vector3" then
		return aimPosition
	end

	return nil
end

local function getLaunchDirectionAndTarget(context, maxDistance, lookDirection)
	local rootPart = context.RootPart
	local rootPosition = rootPart.Position
	local targetPosition, targetPlayer = getRequestedTargetPosition(context)

	if targetPosition then
		local direction = getPlanarUnitOrNil(targetPosition - rootPosition)
		if direction then
			if targetPlayer then
				return direction, Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z), targetPlayer
			end

			return direction, rootPosition + (direction * maxDistance), nil
		end
	end

	if lookDirection then
		return lookDirection, rootPosition + (lookDirection * maxDistance), nil
	end

	local aimPosition = getRequestedAimPosition(context)
	if aimPosition then
		local direction = getPlanarUnitOrNil(aimPosition - rootPosition)
		if direction then
			return direction, rootPosition + (direction * maxDistance), nil
		end
	end

	local fallbackDirection = getFallbackDirection(rootPart)
	return fallbackDirection, rootPosition + (fallbackDirection * maxDistance), nil
end

local function setRootFacing(rootPart, direction)
	if not rootPart or not rootPart.Parent or not direction then
		return
	end

	local planarDirection = getPlanarUnitOrNil(direction)
	if not planarDirection then
		return
	end

	local linearVelocity = rootPart.AssemblyLinearVelocity
	local position = rootPart.Position
	rootPart.CFrame = CFrame.lookAt(position, position + planarDirection, WORLD_UP)
	rootPart.AssemblyLinearVelocity = linearVelocity
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

local function startFacingLock(humanoid, rootPart, direction, duration)
	local lockDirection = getPlanarUnitOrNil(direction)
	if not rootPart or not lockDirection then
		return function() end
	end

	local lockDuration = math.max(0, tonumber(duration) or 0)
	local originalAutoRotate = humanoid and humanoid.AutoRotate or nil
	local released = false

	if humanoid then
		humanoid.AutoRotate = false
	end

	local function release()
		if released then
			return
		end

		released = true

		if humanoid and humanoid.Parent and originalAutoRotate ~= nil then
			humanoid.AutoRotate = originalAutoRotate
		end
	end

	setRootFacing(rootPart, lockDirection)
	if lockDuration <= 0 then
		release()
		return release
	end

	task.delay(lockDuration, release)
	return release
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
	local distanceAlpha = math.clamp(maxDistance > 0 and (launchDistance / maxDistance) or 1, MIN_DISTANCE_ALPHA, 1)
	local horizontalLaunchSpeed = math.max(
		averageSpeed * HORIZONTAL_SPEED_MULTIPLIER,
		MIN_HORIZONTAL_LAUNCH_SPEED * distanceAlpha
	)
	local verticalLaunchSpeed = math.max(
		horizontalLaunchSpeed * VERTICAL_SPEED_RATIO,
		MIN_VERTICAL_LAUNCH_SPEED
	)

	return Vector3.new(
		direction.X * horizontalLaunchSpeed,
		verticalLaunchSpeed,
		direction.Z * horizontalLaunchSpeed
	)
end

local function getTravelDistance(startPosition, currentPosition, direction)
	local delta = RubberLaunchMath.GetPlanarVector(currentPosition - startPosition)
	return math.max(delta:Dot(direction), 0)
end

local function applyLaunchVelocity(rootPart, launchVelocity)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = launchVelocity

	local velocityDelta = launchVelocity - currentVelocity
	local impulse = velocityDelta * rootPart.AssemblyMass
	rootPart:ApplyImpulse(impulse)
end

local function forceLaunchHumanoidState(humanoid)
	if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
		return
	end

	humanoid.Jump = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
end

local function stopPlanarVelocity(rootPart)
	if not rootPart or not rootPart.Parent then
		return
	end

	local velocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
end

local function startWindupMovementLock(humanoid, rootPart)
	local released = false
	local connection
	local original

	if humanoid and humanoid.Parent then
		original = {
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
		}
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end

	stopPlanarVelocity(rootPart)

	local function release()
		if released then
			return
		end

		released = true
		if connection then
			connection:Disconnect()
			connection = nil
		end

		if humanoid and humanoid.Parent and original then
			humanoid.WalkSpeed = original.WalkSpeed
			humanoid.JumpPower = original.JumpPower
			humanoid.JumpHeight = original.JumpHeight
		end
	end

	connection = RunService.Heartbeat:Connect(function()
		if not rootPart or not rootPart.Parent or (humanoid and (not humanoid.Parent or humanoid.Health <= 0)) then
			release()
			return
		end

		stopPlanarVelocity(rootPart)
	end)

	return release
end

local function getReleaseFallbackTime(animationConfig)
	if type(animationConfig) ~= "table" then
		return 0
	end

	return math.max(0, tonumber(animationConfig.ReleaseFallbackTime) or 0)
end

local function getArmRestoreFallbackTime(animationConfig)
	if type(animationConfig) ~= "table" then
		return DEFAULT_ARM_RESTORE_FALLBACK_TIME
	end

	return math.max(0, tonumber(animationConfig.ArmRestoreFallbackTime) or DEFAULT_ARM_RESTORE_FALLBACK_TIME)
end

local function restoreNetworkOwner(rootPart, owner)
	if not rootPart or not rootPart.Parent or not owner or not owner.Parent then
		return
	end

	pcall(function()
		rootPart:SetNetworkOwner(owner)
	end)
end

local function isGroundedAfterLaunch(humanoid, elapsed)
	if elapsed < MOMENTUM_SUSTAIN_GROUND_GRACE then
		return false
	end

	return humanoid.FloorMaterial ~= Enum.Material.Air
end

local isLaunchContextActive

local function getMomentumSustainDuration(launchDuration)
	return math.clamp(
		(tonumber(launchDuration) or DEFAULT_LAUNCH_DURATION) + MOMENTUM_SUSTAIN_TIMEOUT_BUFFER,
		MIN_MOMENTUM_SUSTAIN_DURATION,
		MAX_MOMENTUM_SUSTAIN_DURATION
	)
end

local function createLaunchMomentumConstraint(rootPart, direction, launchVelocity)
	local lineDirection = getPlanarUnitOrNil(direction)
	if not rootPart or not rootPart.Parent or not lineDirection then
		return nil
	end

	local lineSpeed = RubberLaunchMath.GetPlanarVector(launchVelocity):Dot(lineDirection)
	if lineSpeed <= MIN_DIRECTION_MAGNITUDE then
		return nil
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = MOMENTUM_ATTACHMENT_NAME
	attachment.Parent = rootPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = MOMENTUM_CONSTRAINT_NAME

	local ok = pcall(function()
		linearVelocity.Attachment0 = attachment
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Line
		linearVelocity.LineDirection = lineDirection
		linearVelocity.LineVelocity = lineSpeed * MOMENTUM_SUSTAIN_SPEED_FACTOR
		linearVelocity.MaxForce = math.max(MIN_MOMENTUM_SUSTAIN_FORCE, rootPart.AssemblyMass * MOMENTUM_SUSTAIN_FORCE_PER_MASS)
		linearVelocity.Parent = rootPart
	end)

	if not ok then
		linearVelocity:Destroy()
		attachment:Destroy()
		return nil
	end

	return function()
		if linearVelocity.Parent then
			linearVelocity:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
	end
end

local function createLaunchTakeoffConstraint(rootPart, launchVelocity)
	if not rootPart or not rootPart.Parent or typeof(launchVelocity) ~= "Vector3" or launchVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return nil
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = TAKEOFF_ATTACHMENT_NAME
	attachment.Parent = rootPart

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = TAKEOFF_CONSTRAINT_NAME

	local ok = pcall(function()
		linearVelocity.Attachment0 = attachment
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
		linearVelocity.VectorVelocity = launchVelocity
		linearVelocity.MaxForce = math.max(MIN_MOMENTUM_SUSTAIN_FORCE, rootPart.AssemblyMass * MOMENTUM_SUSTAIN_FORCE_PER_MASS)
		linearVelocity.Parent = rootPart
	end)

	if not ok then
		linearVelocity:Destroy()
		attachment:Destroy()
		return nil
	end

	local cleanedUp = false
	local function cleanup()
		if cleanedUp then
			return
		end

		cleanedUp = true
		if linearVelocity.Parent then
			linearVelocity:Destroy()
		end
		if attachment.Parent then
			attachment:Destroy()
		end
	end

	task.delay(TAKEOFF_CONSTRAINT_DURATION, cleanup)
	return cleanup
end

local function startLaunchMomentumSustain(
	context,
	startPosition,
	direction,
	launchDistance,
	maxDistance,
	launchVelocity,
	launchDuration,
	onRelease
)
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local owner = context.Player
	local sustainDuration = getMomentumSustainDuration(launchDuration)
	local wallShortened = launchDistance + MOMENTUM_SUSTAIN_COMPLETION_TOLERANCE < maxDistance
	local cleanupTakeoffConstraint = createLaunchTakeoffConstraint(rootPart, launchVelocity)
	local cleanupMomentumConstraint = createLaunchMomentumConstraint(rootPart, direction, launchVelocity)
	local startedAt = os.clock()
	local released = false
	local connection

	local function release()
		if released then
			return
		end

		released = true
		if connection then
			connection:Disconnect()
			connection = nil
		end

		if cleanupMomentumConstraint then
			cleanupMomentumConstraint()
			cleanupMomentumConstraint = nil
		end
		if cleanupTakeoffConstraint then
			cleanupTakeoffConstraint()
			cleanupTakeoffConstraint = nil
		end

		restoreNetworkOwner(rootPart, owner)
		if type(onRelease) == "function" then
			onRelease()
		end
	end

	task.delay(NETWORK_OWNER_RETURN_AFTER_CONSTRAINT_DELAY, function()
		if released or not isLaunchContextActive(character, humanoid, rootPart) then
			return
		end

		restoreNetworkOwner(rootPart, owner)
	end)

	connection = RunService.Heartbeat:Connect(function()
		if not isLaunchContextActive(character, humanoid, rootPart) then
			release()
			return
		end

		local elapsed = os.clock() - startedAt
		if elapsed >= sustainDuration then
			release()
			return
		end

		if isGroundedAfterLaunch(humanoid, elapsed) then
			release()
			return
		end

		if wallShortened then
			local traveledDistance = getTravelDistance(startPosition, rootPart.Position, direction)
			if traveledDistance >= math.max(0, launchDistance - MOMENTUM_SUSTAIN_COMPLETION_TOLERANCE) then
				release()
				return
			end
		end
	end)

	task.delay(sustainDuration, release)
	return release
end

isLaunchContextActive = function(character, humanoid, rootPart)
	return character
		and character.Parent
		and humanoid
		and humanoid.Parent
		and humanoid.Health > 0
		and rootPart
		and rootPart.Parent
end

function GomuServer.RubberLaunch(context)
	local character = context.Character
	local humanoid = context.Humanoid
	local rootPart = context.RootPart
	local abilityConfig = context.AbilityConfig
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil

	local maxDistance = RubberLaunchMath.GetSpeedScaledLaunchDistance(abilityConfig, rootPart, LAUNCH_DISTANCE_OPTIONS)
	local lookDirection = getRequestedLookDirection(context.RequestPayload)
	local direction, targetPosition, targetPlayer = getLaunchDirectionAndTarget(context, maxDistance, lookDirection)
	local facingDirection = lookDirection or direction or getFallbackDirection(rootPart)
	local launchDuration = math.max(MIN_LAUNCH_DURATION, tonumber(abilityConfig.LaunchDuration) or DEFAULT_LAUNCH_DURATION)
	local launchOwner = context.Player
	local launchToken = HttpService:GenerateGUID(false)
	if launchOwner and activeLaunchCleanupByPlayer[launchOwner] then
		activeLaunchCleanupByPlayer[launchOwner]()
		activeLaunchCleanupByPlayer[launchOwner] = nil
	end

	local facingLockDuration = getReleaseFallbackTime(animationConfig)
		+ math.max(getMomentumSustainDuration(launchDuration), NETWORK_OWNER_RELEASE_DELAY)
	local releaseFacingLock = startFacingLock(humanoid, rootPart, facingDirection, facingLockDuration)
	local armRestoreEmitted = false
	local function emitArmRestore(reason, markerName)
		if armRestoreEmitted then
			return
		end

		armRestoreEmitted = true
		context.EmitEffect("RubberLaunch", {
			Phase = "RestoreArms",
			Token = launchToken,
			MarkerName = markerName,
			RestoreReason = reason or "unknown",
			LookDirection = facingDirection,
			Direction = facingDirection,
		})
	end

	context.EmitEffect("RubberLaunch", {
		Phase = "Start",
		Token = launchToken,
		ArmRestoreFallbackTime = getArmRestoreFallbackTime(animationConfig),
		LookDirection = facingDirection,
		Direction = facingDirection,
	})
	local animationState = GomuAnimationController.PlayRubberLaunchAnimation(character, animationConfig)
	GomuAnimationController.BindRubberLaunchArmEvents(animationState, {
		OnStretch = function(markerInfo)
			context.EmitEffect("RubberLaunch", {
				Phase = "StretchArms",
				Token = launchToken,
				MarkerName = markerInfo and markerInfo.MarkerName or nil,
				ArmSize = markerInfo and markerInfo.ArmStretchSize or nil,
				ArmRestoreFallbackTime = markerInfo and markerInfo.ArmRestoreFallbackTime or getArmRestoreFallbackTime(animationConfig),
				LookDirection = facingDirection,
				Direction = facingDirection,
			})
		end,
		OnRestore = function(markerInfo)
			emitArmRestore(markerInfo and markerInfo.Reason or "unknown", markerInfo and markerInfo.MarkerName or nil)
		end,
	})

	pcall(function()
		rootPart:SetNetworkOwner(nil)
	end)

	local releaseWindupMovementLock = startWindupMovementLock(humanoid, rootPart)
	GomuAnimationController.WaitForRubberLaunchRelease(animationState)
	releaseWindupMovementLock()
	emitArmRestore("before_launch")

	local startPosition = rootPart.Position
	if not isLaunchContextActive(character, humanoid, rootPart) then
		if animationState then
			GomuAnimationController.StopAnimation(animationState, "interrupted_before_launch")
		end
		releaseFacingLock()
		restoreNetworkOwner(rootPart, launchOwner)

		return {
			Direction = direction,
			LookDirection = facingDirection,
			Distance = 0,
			Duration = launchDuration,
			StartPosition = startPosition,
			EndPosition = startPosition,
			TargetPosition = targetPosition,
			TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
			Token = launchToken,
			Interrupted = true,
		}
	end

	local launchDistance = getLaunchDistance(character, rootPart, direction, maxDistance)
	local launchVelocity = getLaunchVelocity(direction, launchDistance, maxDistance, launchDuration)

	if launchDistance <= MIN_EFFECTIVE_LAUNCH_DISTANCE then
		if animationState then
			GomuAnimationController.StopAnimation(animationState, "blocked_at_start")
		end
		releaseFacingLock()
		restoreNetworkOwner(rootPart, launchOwner)

		return {
			Direction = direction,
			LookDirection = facingDirection,
			Distance = 0,
			Duration = launchDuration,
			StartPosition = startPosition,
			EndPosition = startPosition,
			TargetPosition = targetPosition,
			TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
			Token = launchToken,
		}
	end

	forceLaunchHumanoidState(humanoid)
	applyLaunchVelocity(rootPart, launchVelocity)
	local momentumRelease
	momentumRelease = startLaunchMomentumSustain(
		context,
		startPosition,
		direction,
		launchDistance,
		maxDistance,
		launchVelocity,
		launchDuration,
		function()
			releaseFacingLock()
			if activeLaunchCleanupByPlayer[launchOwner] == momentumRelease then
				activeLaunchCleanupByPlayer[launchOwner] = nil
			end
		end
	)
	if launchOwner then
		activeLaunchCleanupByPlayer[launchOwner] = momentumRelease
	end

	if animationState then
		task.delay(launchDuration, function()
			GomuAnimationController.StopAnimation(animationState, "launch_complete")
		end)
	end

	return {
		Direction = direction,
		LookDirection = facingDirection,
		Distance = launchDistance,
		Duration = launchDuration,
		LaunchVelocity = launchVelocity,
		StartPosition = startPosition,
		EndPosition = startPosition + (direction * launchDistance),
		TargetPosition = targetPosition,
		TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
		Token = launchToken,
	}
end

function GomuServer.ClearRuntimeState(player)
	local cleanup = activeLaunchCleanupByPlayer[player]
	activeLaunchCleanupByPlayer[player] = nil
	if cleanup then
		cleanup()
	end
end

return GomuServer
