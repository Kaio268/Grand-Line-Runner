local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local MeraDashShared = require(Modules:WaitForChild("DevilFruits"):WaitForChild("MeraDashShared"))

local MeraDashClient = {}
MeraDashClient.__index = MeraDashClient

MeraDashClient.FRUIT_NAME = "Mera Mera no Mi"
MeraDashClient.ABILITY_NAME = "FlameDash"

local MAX_RUNTIME_GRACE = 0.18
local CORRECTION_SNAP_DISTANCE = 8
local DIRECTION_TOLERANCE = 8
local DISTANCE_TOLERANCE = 4
local CAMERA_FOV_BOOST = 6

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

local function logClient(_player, _message, ...)
end

local function logRecon(_player, _message, ...)
end

local function logMove(_player, _message, ...)
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

function MeraDashClient:KickCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	local baselineFov = camera.FieldOfView
	local boostedFov = math.min(baselineFov + CAMERA_FOV_BOOST, 95)

	if self.cameraTween then
		self.cameraTween:Cancel()
		self.cameraTween = nil
	end

	local punchOut = TweenService:Create(camera, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = boostedFov,
	})
	local settle = TweenService:Create(camera, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
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

function MeraDashClient:FinishLocalDash(state, reason, interrupted)
	if not state or state.MotionFinished then
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
		self:StopHorizontalVelocity(rootPart)
	end
	if not state.ServerResolved then
		self.MarkFlameDashTrailPredictedComplete(
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

	logClient(
		self.player,
		"request ts=%.6f character=%s humanoid=%s rootPart=%s",
		inputReceivedAt,
		tostring(character ~= nil),
		tostring(humanoid ~= nil),
		tostring(rootPart ~= nil)
	)

	if not character or not humanoid or humanoid.Health <= 0 or not rootPart or not abilityConfig then
		return nil
	end

	if self.activeDash and not self.activeDash.MotionFinished then
		self.activeDash.Canceled = true
		self.activeDash.ServerResolved = true
		self:FinishLocalDash(self.activeDash, "superseded_prediction", true)
	end

	local localPlan = MeraDashShared.BuildDashPlan(character, humanoid, rootPart, abilityConfig, nil)
	if not localPlan then
		return nil
	end

	local requestTargetPosition = rootPart.Position + (localPlan.Direction * localPlan.Distance)
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
		LocalEffectPlayed = false,
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

	if localPlan.Distance <= 0.05 then
		self:FinishLocalDash(state, "blocked_at_start", true)
	else
		local predictedEndPosition = state.StartPosition + (localPlan.Direction * localPlan.Distance)
		logMove(self.player, "move=FlameDash startup source=predicted player=%s", self.player.Name)
		self.PlayFlameDashStartup(self.player, {
			Direction = localPlan.Direction,
			StartPosition = state.StartPosition,
			EndPosition = predictedEndPosition,
		}, true)
		self.CreateEffectVisual(state.StartPosition, predictedEndPosition, localPlan.Direction, true)
		self.PlayOptionalEffect(self.player, MeraDashClient.FRUIT_NAME, MeraDashClient.ABILITY_NAME)
		self:KickCamera()
		state.LocalEffectPlayed = true

		if localPlan.InstantDistance > 0.05 and character.Parent and rootPart.Parent then
			local targetRootPosition = state.StartPosition + (localPlan.Direction * localPlan.InstantDistance)
			self:PivotCharacterToRootPosition(character, rootPart, targetRootPosition)
		end

		self:SetHorizontalVelocity(rootPart, localPlan.Direction * localPlan.StartDashSpeed)

		local maxRuntime = math.max(localPlan.Duration + MAX_RUNTIME_GRACE, 0.08)
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
			if currentRemainingDistance <= 0.1 then
				self:SetHorizontalVelocity(rootPart, state.Plan.Direction * state.Plan.EndCarrySpeed)
				self:FinishLocalDash(state, "completed", false)
				return
			end

			local elapsed = math.max(0, getSharedTimestamp() - state.LocalStartAt)
			local alpha = math.clamp(elapsed / state.Plan.Duration, 0, 1)
			local dashSpeed = state.Plan.StartDashSpeed
				+ ((state.Plan.EndDashSpeed - state.Plan.StartDashSpeed) * MeraDashShared.Smoothstep(alpha))
			local lookAheadDistance = math.min(
				MeraDashShared.GetLookAheadDistance(dashSpeed, dt),
				currentRemainingDistance + 2
			)

			if MeraDashShared.ShouldStopForWall(character, rootPart, state.Plan.Direction, lookAheadDistance) then
				self:StopHorizontalVelocity(rootPart)
				self:FinishLocalDash(state, "wall_blocked_mid_dash", true)
				return
			end

			self:SetHorizontalVelocity(rootPart, state.Plan.Direction * dashSpeed)

			if elapsed >= maxRuntime then
				self:SetHorizontalVelocity(rootPart, state.Plan.Direction * state.Plan.EndCarrySpeed)
				self:FinishLocalDash(state, "max_runtime_reached", true)
			end
		end)
	end

	return {
		DashTargetPosition = requestTargetPosition,
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

	local corrected = math.abs(distanceDelta) > DISTANCE_TOLERANCE or directionDelta > DIRECTION_TOLERANCE
	local correctionSnap = false
	local rootPart = self:GetRootPart()
	local serverStartPosition = typeof(payload.StartPosition) == "Vector3" and payload.StartPosition or state.StartPosition
	local currentProgress = math.min(state.TraveledDistance, authoritativeDistance)
	if rootPart then
		local correctionTarget = serverStartPosition + (authoritativeDirection * currentProgress)
		local correctionDelta = (rootPart.Position - correctionTarget).Magnitude
		if correctionDelta > CORRECTION_SNAP_DISTANCE or directionDelta > DIRECTION_TOLERANCE then
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
		self:StopHorizontalVelocity(rootPart)
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
	self.StopFlameDashTrail(self.player, "server_denied_" .. tostring(reason), finalPosition, finalDirection)
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
	if rootPart and typeof(payload.ActualEndPosition) == "Vector3" then
		local correctionDistance = (rootPart.Position - payload.ActualEndPosition).Magnitude
		if correctionDistance > CORRECTION_SNAP_DISTANCE and not state.MotionFinished then
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
			self:StopHorizontalVelocity(rootPart)
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

	if not (targetPlayer == self.player and self.activeDash and self.activeDash.LocalEffectPlayed) then
		logMove(self.player, "move=FlameDash startup source=replicated target=%s", targetPlayer.Name)
		self.PlayFlameDashStartup(targetPlayer, resolvedPayload, false)
		self.PlayOptionalEffect(targetPlayer, MeraDashClient.FRUIT_NAME, MeraDashClient.ABILITY_NAME)
		self.CreateEffectVisual(startPosition, endPosition, direction, false)
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
	if not state then
		return
	end

	state.Canceled = true
	state.ServerResolved = true
	self:FinishLocalDash(state, "character_removing", true)
	self:ClearActiveState(state)
end

return MeraDashClient
