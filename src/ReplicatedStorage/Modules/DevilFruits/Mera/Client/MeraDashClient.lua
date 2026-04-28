local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DiagnosticLogLimiter = require(Modules:WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local DevilFruitLogger = require(DevilFruits:WaitForChild("Shared"):WaitForChild("DevilFruitLogger"))
local MeraFolder = DevilFruits:WaitForChild("Mera")
local MeraShared = MeraFolder:WaitForChild("Shared")
local MeraDashShared = require(MeraShared:WaitForChild("MeraDashShared"))
local MeraConfig = require(MeraShared:WaitForChild("MeraConfig"))

local MeraDashClient = {}
MeraDashClient.__index = MeraDashClient

MeraDashClient.FRUIT_NAME = "Mera Mera no Mi"
MeraDashClient.ABILITY_NAME = "FlameDash"

local CORRECTION_SNAP_DISTANCE = 12
local DIRECTION_TOLERANCE = 8
local DISTANCE_TOLERANCE = 6
local CAMERA_FOV_BOOST = 6
local MAX_CAMERA_FOV = 95
local CAMERA_PUNCH_OUT_TIME = 0.06
local CAMERA_SETTLE_TIME = 0.18
local MIN_PLANAR_DIRECTION_MAGNITUDE = 0.01
local CARRY_RELEASE_DONE_SPEED_SCALE = 0.001
local MIN_DASH_DISTANCE = 0.05
local MIN_DASH_RUNTIME = 0.08
local WALL_LOOKAHEAD_BUFFER = 2

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local DASH_CLIENT_LOG_COOLDOWN = MeraConfig.Logging.DashClientCooldown

local function logDash(scope, enabled, player, message, ...)
	if enabled ~= true then
		return
	end

	local playerKey = player and player:IsA("Player") and tostring(player.UserId) or "local"
	local key = playerKey .. "::" .. DiagnosticLogLimiter.BuildKey(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MeraDashClient:" .. tostring(scope), key, DASH_CLIENT_LOG_COOLDOWN) then
		return
	end

	print(string.format("[MERA DASH][%s] " .. message, tostring(scope), ...))
end

local function logClient(player, message, ...)
	logDash("CLIENT", MeraConfig.Debug.DashClientLogsEnabled, player, message, ...)
end

local function logRecon(player, message, ...)
	logDash("RECON", MeraConfig.Debug.DashClientReconciliationLogsEnabled, player, message, ...)
end

local function logMove(player, message, ...)
	logDash("MOVE", MeraConfig.Debug.DashClientMoveLogsEnabled, player, message, ...)
end

local function logRequest(message, ...)
	if not RunService:IsStudio() then
		return
	end

	DevilFruitLogger.Info("REQUEST", message, ...)
end

local function safeCallNonCriticalCallback(callbackName, callback, ...)
	if typeof(callback) ~= "function" then
		return false, "not_function"
	end

	local ok, result = pcall(callback, ...)
	if not ok then
		logRequest(
			"MeraDashClient noncritical callback failed ability=%s callback=%s detail=%s",
			MeraDashClient.ABILITY_NAME,
			tostring(callbackName),
			tostring(result)
		)
		return false, result
	end

	return true, result
end

local function refreshPredictedTravelDistance(state, rootPart, direction)
	if type(state) ~= "table" then
		return 0
	end

	if not rootPart or not rootPart:IsA("BasePart") then
		return tonumber(state.TraveledDistance) or 0
	end

	local resolvedDirection = typeof(direction) == "Vector3" and direction
		or (state.Plan and state.Plan.Direction)
		or state.Direction
	if typeof(state.StartPosition) ~= "Vector3" or typeof(resolvedDirection) ~= "Vector3" then
		return tonumber(state.TraveledDistance) or 0
	end

	local liveDistance = MeraDashShared.GetTravelDistance(state.StartPosition, rootPart.Position, resolvedDirection)
	state.TraveledDistance = math.max(tonumber(state.TraveledDistance) or 0, liveDistance)
	return state.TraveledDistance
end

function MeraDashClient.new(config)
	config = config or {}

	local self = setmetatable({}, MeraDashClient)
	self.player = config.player or Players.LocalPlayer
	self.PlayOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or function() end
	self.CreateEffectVisual = type(config.CreateEffectVisual) == "function" and config.CreateEffectVisual or function() end
	self.PlayFlameDashStartup = type(config.PlayFlameDashStartup) == "function" and config.PlayFlameDashStartup or function() end
	self.PlayFlameDashComplete = type(config.PlayFlameDashComplete) == "function" and config.PlayFlameDashComplete or function() end
	self.MarkFlameDashTrailPredictedComplete = type(config.MarkFlameDashTrailPredictedComplete) == "function"
		and config.MarkFlameDashTrailPredictedComplete
		or function() end
	self.StopFlameDashTrail = type(config.StopFlameDashTrail) == "function" and config.StopFlameDashTrail or function() end
	self.activeDash = nil
	self.cameraTween = nil
	self.carryConnection = nil
	self.sequence = 0
	return self
end

function MeraDashClient:GetCharacter()
	return self.player.Character
end

function MeraDashClient:GetRootPart()
	local character = self:GetCharacter()
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

function MeraDashClient:GetHumanoid()
	local character = self:GetCharacter()
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

function MeraDashClient:GetCharacterPivotOffset(character, rootPart)
	return character:GetPivot():ToObjectSpace(rootPart.CFrame)
end

function MeraDashClient:PivotCharacterToRootPosition(character, rootPart, targetRootPosition)
	if not character or not rootPart then
		return
	end

	local pivotOffset = self:GetCharacterPivotOffset(character, rootPart)
	local targetRootCFrame = CFrame.new(targetRootPosition, targetRootPosition + rootPart.CFrame.LookVector)
	character:PivotTo(targetRootCFrame * pivotOffset:Inverse())
end

function MeraDashClient:SetHorizontalVelocity(rootPart, horizontalVelocity)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(horizontalVelocity.X, currentVelocity.Y, horizontalVelocity.Z)
end

function MeraDashClient:StopHorizontalVelocity(rootPart)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
end

function MeraDashClient:CancelCarryRelease(stopNow)
	if self.carryConnection then
		self.carryConnection:Disconnect()
		self.carryConnection = nil
	end

	if stopNow ~= true then
		return
	end

	local rootPart = self:GetRootPart()
	if rootPart and rootPart.Parent then
		self:StopHorizontalVelocity(rootPart)
	end
end

function MeraDashClient:StartCarryRelease(rootPart, direction, startSpeed, duration)
	self:CancelCarryRelease(false)

	if not rootPart or not rootPart.Parent then
		return false
	end

	local planarDirection = typeof(direction) == "Vector3" and MeraDashShared.GetPlanarVector(direction) or nil
	local carrySpeed = math.max(0, tonumber(startSpeed) or 0)
	local carryDuration = math.max(0, tonumber(duration) or 0)
	if not planarDirection or planarDirection.Magnitude <= MIN_PLANAR_DIRECTION_MAGNITUDE or carrySpeed <= 0 or carryDuration <= 0 then
		self:StopHorizontalVelocity(rootPart)
		return false
	end

	local carryDirection = planarDirection.Unit
	local carryStartAt = os.clock()
	self:SetHorizontalVelocity(rootPart, carryDirection * carrySpeed)

	self.carryConnection = RunService.Heartbeat:Connect(function()
		if not rootPart.Parent then
			self:CancelCarryRelease(false)
			return
		end

		local elapsed = math.max(0, os.clock() - carryStartAt)
		local alpha = math.clamp(elapsed / carryDuration, 0, 1)
		local speedScale = 1 - MeraDashShared.Smoothstep(alpha)
		if alpha >= 1 or speedScale <= CARRY_RELEASE_DONE_SPEED_SCALE then
			self:CancelCarryRelease(true)
			return
		end

		self:SetHorizontalVelocity(rootPart, carryDirection * (carrySpeed * speedScale))
	end)

	return true
end

function MeraDashClient:GetCarryReleaseSpeed(startSpeed, duration, maxDistance)
	local carrySpeed = math.max(0, tonumber(startSpeed) or 0)
	local carryDuration = math.max(0, tonumber(duration) or 0)
	local carryMaxDistance = math.max(0, tonumber(maxDistance) or 0)
	if carrySpeed <= 0 or carryDuration <= 0 or carryMaxDistance <= 0 then
		return 0
	end

	-- `StartCarryRelease` uses a `1 - Smoothstep(alpha)` decay curve, whose
	-- integral over [0, 1] is 0.5. Clamp the initial carry speed so the total
	-- release distance stays under the configured budget and avoids reconcile
	-- snap-backs near the end of the dash.
	local maxCarrySpeed = (carryMaxDistance * 2) / carryDuration
	return math.min(carrySpeed, maxCarrySpeed)
end

function MeraDashClient:KickCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local baselineFov = camera.FieldOfView
	local boostedFov = math.min(baselineFov + CAMERA_FOV_BOOST, MAX_CAMERA_FOV)

	if self.cameraTween then
		self.cameraTween:Cancel()
		self.cameraTween = nil
	end

	local punchOut = TweenService:Create(camera, TweenInfo.new(CAMERA_PUNCH_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = boostedFov,
	})
	local settle = TweenService:Create(camera, TweenInfo.new(CAMERA_SETTLE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = baselineFov,
	})

	self.cameraTween = settle

	punchOut.Completed:Connect(function()
		settle:Play()
	end)

	settle.Completed:Connect(function()
		if self.cameraTween == settle then
			self.cameraTween = nil
		end
	end)

	punchOut:Play()
end

function MeraDashClient:ClearActiveState(state)
	if self.activeDash == state then
		self.activeDash = nil
	end
end

function MeraDashClient:FinishLocalDash(state, reason, interrupted, options)
	if not state then
		return
	end

	if state.MotionFinished then
		if interrupted == true then
			self:CancelCarryRelease(true)
		end
		return
	end

	state.MotionFinished = true
	state.LocalResolveReason = reason
	state.LocalEndAt = getSharedTimestamp()
	if state.MotionConnection then
		state.MotionConnection:Disconnect()
		state.MotionConnection = nil
	end

	local rootPart = self:GetRootPart()
	if rootPart then
		local carryOut = type(options) == "table" and options.CarryOut == true and interrupted ~= true
		if carryOut then
			self:StartCarryRelease(
				rootPart,
				state.Plan and state.Plan.Direction or state.Direction,
				self:GetCarryReleaseSpeed(
					tonumber(options.CarrySpeed) or (state.Plan and state.Plan.EndCarrySpeed) or 0,
					tonumber(options.CarryDuration) or state.EndCarryDuration or 0,
					tonumber(options.CarryMaxDistance) or state.EndCarryMaxDistance or 0
				),
				tonumber(options.CarryDuration) or state.EndCarryDuration or 0
			)
		else
			self:CancelCarryRelease(true)
		end
	end
	if not state.ServerResolved then
		safeCallNonCriticalCallback(
			"MarkFlameDashTrailPredictedComplete",
			self.MarkFlameDashTrailPredictedComplete,
			self.player,
			reason,
			rootPart and rootPart.Position or nil,
			state.Plan and state.Plan.Direction or state.Direction
		)
	end

	logClient(
		self.player,
		"local_finish ts=%.6f seq=%s reason=%s interrupted=%s traveled=%.2f predictedDistance=%.2f corrected=%s correctionSnap=%s",
		state.LocalEndAt,
		tostring(state.Sequence),
		tostring(reason),
		tostring(interrupted == true),
		tonumber(state.TraveledDistance) or 0,
		tonumber(state.OriginalPredictedDistance) or 0,
		tostring(state.Corrected == true),
		tostring(state.CorrectionSnap == true)
	)
	logMove(
		self.player,
		"move=FlameDash complete player=%s reason=%s interrupted=%s",
		self.player.Name,
		tostring(reason),
		tostring(interrupted == true)
	)

	if state.ServerResolved then
		self:ClearActiveState(state)
	end
end

function MeraDashClient:BeginPredictedRequest()
	local inputReceivedAt = getSharedTimestamp()
	local character = self:GetCharacter()
	local humanoid = self:GetHumanoid()
	local rootPart = self:GetRootPart()
	local abilityConfig = DevilFruitConfig.GetAbility(MeraDashClient.FRUIT_NAME, MeraDashClient.ABILITY_NAME)
	local moveDirection = humanoid and humanoid.MoveDirection or nil

	logClient(
		self.player,
		"request ts=%.6f character=%s humanoid=%s rootPart=%s",
		inputReceivedAt,
		tostring(character ~= nil),
		tostring(humanoid ~= nil),
		tostring(rootPart ~= nil)
	)
	logRequest(
		"predicted begin fruit=%s ability=%s character=%s humanoid=%s root=%s abilityConfig=%s moveDir=%s lookDir=%s",
		MeraDashClient.FRUIT_NAME,
		MeraDashClient.ABILITY_NAME,
		tostring(character ~= nil),
		tostring(humanoid ~= nil),
		tostring(rootPart ~= nil),
		tostring(abilityConfig ~= nil),
		formatVector3(moveDirection),
		formatVector3(rootPart and rootPart.CFrame.LookVector or nil)
	)

	if not character or not humanoid or humanoid.Health <= 0 or not rootPart or not abilityConfig then
		logRequest(
			"predicted blocked fruit=%s ability=%s reason=missing_preconditions health=%s",
			MeraDashClient.FRUIT_NAME,
			MeraDashClient.ABILITY_NAME,
			tostring(humanoid and humanoid.Health or "<nil>")
		)
		return nil
	end

	if self.activeDash and not self.activeDash.MotionFinished then
		self.activeDash.Canceled = true
		self.activeDash.ServerResolved = true
		self:FinishLocalDash(self.activeDash, "superseded_prediction", true)
	end

	local localPlan = MeraDashShared.BuildDashPlan(character, humanoid, rootPart, abilityConfig, nil)
	if not localPlan then
		logRequest(
			"predicted blocked fruit=%s ability=%s reason=build_dash_plan_nil",
			MeraDashClient.FRUIT_NAME,
			MeraDashClient.ABILITY_NAME
		)
		return nil
	end

	local maxRequestHintDistance = MeraDashShared.GetMaxRequestHintDistance(abilityConfig)
	local requestHintDistance = math.min(localPlan.MaxDistance, maxRequestHintDistance)
	if requestHintDistance <= 0 then
		requestHintDistance = localPlan.RequestedDistance
	end

	local requestTargetPosition = rootPart.Position + (localPlan.Direction * requestHintDistance)
	if requestHintDistance + MIN_DASH_DISTANCE < localPlan.RequestedDistance then
		local constrainedPlan = MeraDashShared.BuildDashPlan(character, humanoid, rootPart, abilityConfig, requestTargetPosition)
		if not constrainedPlan then
			logRequest(
				"predicted blocked fruit=%s ability=%s reason=rebuild_dash_plan_nil",
				MeraDashClient.FRUIT_NAME,
				MeraDashClient.ABILITY_NAME
			)
			return nil
		end

		localPlan = constrainedPlan
	end

	local visualDirection = localPlan.Direction
	local completionTolerance = MeraDashShared.GetCompletionTolerance(abilityConfig)
	local runtimeGrace = MeraDashShared.GetRuntimeGrace(abilityConfig)
	local endCarryDuration = MeraDashShared.GetEndCarryDuration(abilityConfig)
	local endCarryMaxDistance = MeraDashShared.GetEndCarryMaxDistance(abilityConfig)
	local correctionSnapDistance = MeraDashShared.GetCorrectionSnapDistance(abilityConfig)
	local distanceTolerance = MeraDashShared.GetDistanceTolerance(abilityConfig)
	local state = {
		Sequence = self.sequence + 1,
		InputReceivedAt = inputReceivedAt,
		LocalStartAt = getSharedTimestamp(),
		StartPosition = rootPart.Position,
		OriginalPredictedDirection = localPlan.Direction,
		OriginalPredictedDistance = localPlan.Distance,
		OriginalRequestedDistance = localPlan.RequestedDistance,
		ConfirmedDirection = nil,
		ConfirmedDistance = nil,
		Direction = localPlan.Direction,
		Plan = {
			Direction = localPlan.Direction,
			Distance = localPlan.Distance,
			Duration = localPlan.Duration,
			InstantDistance = localPlan.InstantDistance,
			StartDashSpeed = localPlan.StartDashSpeed,
			EndDashSpeed = localPlan.EndDashSpeed,
			EndCarrySpeed = localPlan.EndCarrySpeed,
		},
		TraveledDistance = 0,
		WallShortened = localPlan.WallShortened,
		CompletionTolerance = completionTolerance,
		EndCarryDuration = endCarryDuration,
		EndCarryMaxDistance = endCarryMaxDistance,
		CorrectionSnapDistance = correctionSnapDistance,
		DistanceTolerance = distanceTolerance,
		MotionFinished = false,
		Canceled = false,
		CorrectionSnap = false,
		Corrected = false,
		Reconciled = false,
		ServerResolved = false,
	}

	self.sequence = state.Sequence
	self.activeDash = state

	local startupDelayMs = math.max(0, (state.LocalStartAt - inputReceivedAt) * 1000)
	logClient(
		self.player,
		"local_start ts=%.6f seq=%s startupDelayMs=%.2f direction=%s predictedDistance=%.2f requestedDistance=%.2f duration=%.3f wallShortened=%s",
		state.LocalStartAt,
		tostring(state.Sequence),
		startupDelayMs,
		formatVector3(localPlan.Direction),
		localPlan.Distance,
		localPlan.RequestedDistance,
		localPlan.Duration,
		tostring(localPlan.WallShortened)
	)

	if localPlan.Distance <= MIN_DASH_DISTANCE then
		logRequest(
			"predicted local state fruit=%s ability=%s reason=blocked_at_start requestedDistance=%.2f finalDistance=%.2f",
			MeraDashClient.FRUIT_NAME,
			MeraDashClient.ABILITY_NAME,
			localPlan.RequestedDistance,
			localPlan.Distance
		)
		self:FinishLocalDash(state, "blocked_at_start", true)
	else
		task.defer(function()
			safeCallNonCriticalCallback("KickCamera", function()
				self:KickCamera()
			end)
		end)

		if localPlan.InstantDistance > MIN_DASH_DISTANCE and character.Parent and rootPart.Parent then
			local targetRootPosition = state.StartPosition + (localPlan.Direction * localPlan.InstantDistance)
			self:PivotCharacterToRootPosition(character, rootPart, targetRootPosition)
			refreshPredictedTravelDistance(state, rootPart, localPlan.Direction)
		end

		self:SetHorizontalVelocity(rootPart, localPlan.Direction * localPlan.StartDashSpeed)

		local maxRuntime = math.max(localPlan.Duration + runtimeGrace, MIN_DASH_RUNTIME)
		state.MotionConnection = RunService.Heartbeat:Connect(function(dt)
			if self.activeDash ~= state then
				self:FinishLocalDash(state, "replaced_active_state", true)
				return
			end

			if not character.Parent or not rootPart.Parent or humanoid.Health <= 0 then
				self:FinishLocalDash(state, "interrupted_invalid_state", true)
				return
			end

			state.TraveledDistance = MeraDashShared.GetTravelDistance(state.StartPosition, rootPart.Position, state.Plan.Direction)
			local currentRemainingDistance = state.Plan.Distance - state.TraveledDistance
			if currentRemainingDistance <= state.CompletionTolerance then
				self:FinishLocalDash(state, "completed", false, {
					CarryOut = true,
					CarrySpeed = state.Plan.EndCarrySpeed,
					CarryDuration = state.EndCarryDuration,
					CarryMaxDistance = state.EndCarryMaxDistance,
				})
				return
			end

			local elapsed = math.max(0, getSharedTimestamp() - state.LocalStartAt)
			local alpha = math.clamp(elapsed / state.Plan.Duration, 0, 1)
			local dashSpeed = state.Plan.StartDashSpeed
				+ ((state.Plan.EndDashSpeed - state.Plan.StartDashSpeed) * MeraDashShared.Smoothstep(alpha))
			local lookAheadDistance = math.min(
				MeraDashShared.GetLookAheadDistance(dashSpeed, dt),
				currentRemainingDistance + WALL_LOOKAHEAD_BUFFER
			)

			if MeraDashShared.ShouldStopForWall(character, rootPart, state.Plan.Direction, lookAheadDistance) then
				self:FinishLocalDash(state, "wall_blocked_mid_dash", true)
				return
			end

			self:SetHorizontalVelocity(rootPart, state.Plan.Direction * dashSpeed)

			if elapsed >= maxRuntime then
				self:FinishLocalDash(state, "max_runtime_reached", true)
			end
		end)
	end

	logRequest(
		"predicted end fruit=%s ability=%s dashTarget=%s requestHintDistance=%.2f requestedDistance=%.2f finalDistance=%.2f",
		MeraDashClient.FRUIT_NAME,
		MeraDashClient.ABILITY_NAME,
		formatVector3(requestTargetPosition),
		requestHintDistance,
		localPlan.RequestedDistance,
		localPlan.Distance
	)
	return {
		DashTargetPosition = requestTargetPosition,
		VisualDirection = visualDirection,
	}
end

function MeraDashClient:HandleConfirmed(payload)
	if typeof(payload) ~= "table" or payload.Phase ~= "Start" then
		return
	end

	local state = self.activeDash
	if not state then
		logRecon(
			self.player,
			"confirmed_without_prediction ts=%.6f start=%.6f distance=%.2f direction=%s",
			getSharedTimestamp(),
			tonumber(payload.StartedAt) or 0,
			tonumber(payload.Distance) or 0,
			formatVector3(payload.Direction)
		)
		return
	end

	local authoritativeDirection = typeof(payload.Direction) == "Vector3" and payload.Direction or state.Plan.Direction
	local authoritativeDistance = tonumber(payload.Distance) or state.Plan.Distance
	local distanceDelta = authoritativeDistance - state.OriginalPredictedDistance
	local directionDelta = MeraDashShared.GetDirectionDeltaDegrees(state.OriginalPredictedDirection, authoritativeDirection)
	local startDeltaMs = math.max(0, ((tonumber(payload.StartedAt) or getSharedTimestamp()) - state.LocalStartAt) * 1000)

	state.Reconciled = true
	state.ConfirmedDirection = authoritativeDirection
	state.ConfirmedDistance = authoritativeDistance
	state.Plan.Direction = authoritativeDirection
	state.Plan.Distance = authoritativeDistance
	state.Plan.Duration = tonumber(payload.Duration) or state.Plan.Duration
	state.Plan.InstantDistance = tonumber(payload.InstantDistance) or state.Plan.InstantDistance
	state.Plan.StartDashSpeed = tonumber(payload.StartDashSpeed) or state.Plan.StartDashSpeed
	state.Plan.EndDashSpeed = tonumber(payload.EndDashSpeed) or state.Plan.EndDashSpeed
	state.Plan.EndCarrySpeed = tonumber(payload.EndCarrySpeed) or state.Plan.EndCarrySpeed

	local distanceTolerance = state.DistanceTolerance or DISTANCE_TOLERANCE
	local correctionSnapDistance = state.CorrectionSnapDistance or CORRECTION_SNAP_DISTANCE
	local corrected = math.abs(distanceDelta) > distanceTolerance or directionDelta > DIRECTION_TOLERANCE
	local correctionSnap = false
	local rootPart = self:GetRootPart()
	local serverStartPosition = typeof(payload.StartPosition) == "Vector3" and payload.StartPosition or state.StartPosition
	local currentProgress = math.min(tonumber(state.TraveledDistance) or 0, authoritativeDistance)
	if rootPart then
		currentProgress = math.min(refreshPredictedTravelDistance(state, rootPart, authoritativeDirection), authoritativeDistance)
		local correctionTarget = serverStartPosition + (authoritativeDirection * currentProgress)
		local correctionDelta = (rootPart.Position - correctionTarget).Magnitude
		if correctionDelta > correctionSnapDistance or directionDelta > DIRECTION_TOLERANCE then
			local character = self:GetCharacter()
			if character then
				self:PivotCharacterToRootPosition(character, rootPart, correctionTarget)
				correctionSnap = true
			end
		end
	end

	state.Corrected = corrected
	state.CorrectionSnap = state.CorrectionSnap or correctionSnap
	state.StartPosition = serverStartPosition
	state.Direction = authoritativeDirection

	logRecon(
		self.player,
		"confirmed ts=%.6f seq=%s startDeltaMs=%.2f predictedDistance=%.2f actualDistance=%.2f distanceDelta=%.2f predictedDir=%s actualDir=%s directionDelta=%.2f corrected=%s correctionSnap=%s wallShortened=%s validationAdjusted=%s",
		getSharedTimestamp(),
		tostring(state.Sequence),
		startDeltaMs,
		state.OriginalPredictedDistance,
		authoritativeDistance,
		distanceDelta,
		formatVector3(state.OriginalPredictedDirection),
		formatVector3(authoritativeDirection),
		directionDelta,
		tostring(corrected),
		tostring(correctionSnap),
		tostring(payload.WallShortened == true),
		tostring(payload.ValidationAdjusted == true)
	)

	if state.MotionFinished then
		logRecon(
			self.player,
			"confirmed_after_local_finish seq=%s localReason=%s",
			tostring(state.Sequence),
			tostring(state.LocalResolveReason)
		)
	end
end

function MeraDashClient:HandleDenied(reason)
	local state = self.activeDash
	if not state then
		return
	end

	state.Canceled = true
	state.Denied = true
	state.ServerResolved = true

	local rootPart = self:GetRootPart()
	if rootPart then
		self:CancelCarryRelease(true)
	end

	logRecon(
		self.player,
		"denied ts=%.6f seq=%s reason=%s localStarted=%.6f predictedDistance=%.2f",
		getSharedTimestamp(),
		tostring(state.Sequence),
		tostring(reason),
		tonumber(state.LocalStartAt) or 0,
		tonumber(state.OriginalPredictedDistance) or 0
	)

	local finalPosition = rootPart and rootPart.Position or nil
	local finalDirection = state.Plan and state.Plan.Direction or state.Direction
	self:FinishLocalDash(state, "server_denied_" .. tostring(reason), true)
	safeCallNonCriticalCallback(
		"StopFlameDashTrail",
		self.StopFlameDashTrail,
		self.player,
		"server_denied_" .. tostring(reason),
		finalPosition,
		finalDirection
	)
	self:ClearActiveState(state)
end

function MeraDashClient:HandleResolved(payload)
	if typeof(payload) ~= "table" or payload.Phase ~= "Resolve" then
		return
	end

	local state = self.activeDash
	if not state then
		logRecon(
			self.player,
			"resolve_without_prediction ts=%.6f reason=%s traveled=%.2f endedEarly=%s",
			getSharedTimestamp(),
			tostring(payload.ResolveReason),
			tonumber(payload.TraveledDistance) or 0,
			tostring(payload.EndedEarly == true)
		)
		return
	end

	state.ServerResolved = true

	local actualDistance = tonumber(payload.TraveledDistance) or 0
	local distanceDelta = actualDistance - state.OriginalPredictedDistance
	local authoritativeDirection = state.ConfirmedDirection or state.Plan.Direction
	local directionDelta = MeraDashShared.GetDirectionDeltaDegrees(state.OriginalPredictedDirection, authoritativeDirection)
	local correctionSnap = false
	local rootPart = self:GetRootPart()
	local correctionSnapDistance = state.CorrectionSnapDistance or CORRECTION_SNAP_DISTANCE
	if rootPart and typeof(payload.ActualEndPosition) == "Vector3" then
		local correctionDistance = (rootPart.Position - payload.ActualEndPosition).Magnitude
		if correctionDistance > correctionSnapDistance and not state.MotionFinished then
			local character = self:GetCharacter()
			if character then
				self:PivotCharacterToRootPosition(character, rootPart, payload.ActualEndPosition)
				correctionSnap = true
			end
		end
	end

	state.CorrectionSnap = state.CorrectionSnap or correctionSnap

	logRecon(
		self.player,
		"resolved ts=%.6f seq=%s predictedDistance=%.2f actualDistance=%.2f distanceDelta=%.2f directionDelta=%.2f correctionSnap=%s interrupted=%s endedEarly=%s reason=%s",
		getSharedTimestamp(),
		tostring(state.Sequence),
		state.OriginalPredictedDistance,
		actualDistance,
		distanceDelta,
		directionDelta,
		tostring(correctionSnap),
		tostring(payload.Interrupted == true),
		tostring(payload.EndedEarly == true),
		tostring(payload.ResolveReason)
	)

	if not state.MotionFinished or payload.Interrupted == true or payload.EndedEarly == true then
		if rootPart then
			self:CancelCarryRelease(true)
		end
		self:FinishLocalDash(state, "server_resolve_" .. tostring(payload.ResolveReason), payload.Interrupted == true)
	end

	self:ClearActiveState(state)
end

function MeraDashClient:HandleEffect(targetPlayer, payload)
	local resolvedPayload = payload or {}
	local phase = typeof(resolvedPayload.Phase) == "string" and resolvedPayload.Phase or "Start"

	if phase == "Resolve" then
		if targetPlayer == self.player then
			self:HandleResolved(resolvedPayload)
		end

		self.PlayFlameDashComplete(targetPlayer, resolvedPayload)
		return true
	end

	if phase ~= "Start" then
		return true
	end

	local direction = typeof(resolvedPayload.Direction) == "Vector3" and resolvedPayload.Direction or Vector3.new(0, 0, -1)
	local startPosition = typeof(resolvedPayload.StartPosition) == "Vector3" and resolvedPayload.StartPosition or nil
	local endPosition = typeof(resolvedPayload.EndPosition) == "Vector3" and resolvedPayload.EndPosition or nil
	if not startPosition then
		local rootPart = getPlayerRootPart(targetPlayer)
		startPosition = rootPart and rootPart.Position or nil
	end
	if not endPosition and startPosition then
		endPosition = startPosition + (direction * (tonumber(resolvedPayload.Distance) or 14))
	end

	logMove(self.player, "move=FlameDash startup source=replicated target=%s", targetPlayer.Name)
	local presentationCallbackOk, presentationStarted = safeCallNonCriticalCallback(
		"PlayFlameDashStartup",
		self.PlayFlameDashStartup,
		targetPlayer,
		resolvedPayload,
		false
	)
	safeCallNonCriticalCallback(
		"PlayOptionalEffect",
		self.PlayOptionalEffect,
		targetPlayer,
		MeraDashClient.FRUIT_NAME,
		MeraDashClient.ABILITY_NAME
	)
	if not presentationCallbackOk or presentationStarted ~= true then
		safeCallNonCriticalCallback("CreateEffectVisual", self.CreateEffectVisual, startPosition, endPosition, direction, false)
	end

	return true
end

function MeraDashClient:HandleStateEvent(eventName, fruitName, abilityName, value, payload)
	if fruitName ~= MeraDashClient.FRUIT_NAME or abilityName ~= MeraDashClient.ABILITY_NAME then
		return false
	end

	if eventName == "Activated" then
		self:HandleConfirmed(payload or {})
		return true
	end

	if eventName == "Denied" then
		self:HandleDenied(value)
		return true
	end

	return false
end

function MeraDashClient:CleanupCharacterRemoving()
	local state = self.activeDash
	self:CancelCarryRelease(true)
	if not state then
		return
	end

	state.Canceled = true
	state.ServerResolved = true
	self:FinishLocalDash(state, "character_removing", true)
	self:ClearActiveState(state)
end

return MeraDashClient
