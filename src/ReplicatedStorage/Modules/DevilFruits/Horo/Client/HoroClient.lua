local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))

local HoroClient = {}
HoroClient.__index = HoroClient

local FRUIT_NAME = "Horo Horo no Mi"
local ABILITY_NAME = "GhostProjection"
local REMOTE_NAME = "HoroProjectionAction"
local WORLD_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local GHOSTS_FOLDER_NAME = "HoroGhosts"
local DEFAULT_DURATION = 5
local DEFAULT_GHOST_SPEED = 15
local DEFAULT_CARRY_SPEED = 8
local DEFAULT_MAX_DISTANCE_FROM_BODY = 68
local DEFAULT_REWARD_INTERACT_RADIUS = 12
local DEFAULT_HAZARD_PROBE_RADIUS = 3.4
local DEFAULT_CLIENT_HAZARD_REPORT_THROTTLE = 0.12
local PICKUP_INPUT_THROTTLE = 0.18
local MAX_PROJECTION_MOVE_SPEED = 200
local DEFAULT_FLIGHT_HORIZONTAL_RESPONSE = 10
local DEFAULT_FLIGHT_VERTICAL_HOLD_RESPONSE = 12
local DEFAULT_FLIGHT_DT = 1 / 60
local MIN_FLIGHT_DT = 1 / 240
local MAX_FLIGHT_DT = 1 / 15
local HOVER_HEIGHT_SNAP_TOLERANCE = 0.2
local DEBUG_TRACE = RunService:IsStudio()

local function formatVector3(value)
	if typeof(value) ~= "Vector3" then
		return tostring(value)
	end

	return string.format("(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z)
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function horoClientTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[HORO CLIENT TRACE] " .. tostring(message), ...))
end

local function getPlayerCarrySummary(player)
	if not player then
		return "player=<nil>"
	end

	return string.format(
		"attrMajor=%s attrMajorName=%s attrBrainrot=%s horoActive=%s horoProjectionId=%s horoCarrying=%s",
		tostring(player:GetAttribute("CarriedMajorRewardType")),
		tostring(player:GetAttribute("CarriedMajorRewardDisplayName")),
		tostring(player:GetAttribute("CarriedBrainrot")),
		tostring(player:GetAttribute("HoroProjectionActive")),
		tostring(player:GetAttribute("HoroProjectionId")),
		tostring(player:GetAttribute("HoroProjectionCarryingReward"))
	)
end

local function clampNumber(value, fallback, minValue, maxValue)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return fallback
	end

	return math.clamp(numericValue, minValue, maxValue)
end

local function getAbilityConfig()
	return DevilFruitConfig.GetAbility(FRUIT_NAME, ABILITY_NAME) or {}
end

local function getActionRemote()
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 2)
	if not remotesFolder then
		return nil
	end

	return remotesFolder:FindFirstChild(REMOTE_NAME) or remotesFolder:WaitForChild(REMOTE_NAME, 2)
end

local function getGhostRoot(ghostModel)
	if not ghostModel then
		return nil
	end

	return ghostModel:FindFirstChild("HumanoidRootPart") or ghostModel.PrimaryPart or ghostModel:FindFirstChildWhichIsA("BasePart", true)
end

local function getCharacterHumanoid(player)
	local character = player and player.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function findGhostModel(payload)
	local projectionId = payload and payload.ProjectionId
	local effectsFolder = Workspace:FindFirstChild(WORLD_EFFECTS_FOLDER_NAME) or Workspace:WaitForChild(WORLD_EFFECTS_FOLDER_NAME, 2)
	local ghostsFolder = effectsFolder and (effectsFolder:FindFirstChild(GHOSTS_FOLDER_NAME) or effectsFolder:WaitForChild(GHOSTS_FOLDER_NAME, 2))
	if not ghostsFolder then
		return nil
	end

	if typeof(projectionId) == "string" and projectionId ~= "" then
		local deadline = os.clock() + 2
		while os.clock() <= deadline do
			for _, child in ipairs(ghostsFolder:GetChildren()) do
				if child:IsA("Model") and child:GetAttribute("ProjectionId") == projectionId then
					return child
				end
			end
			task.wait(0.05)
		end
		return nil
	end

	local ghostName = payload and payload.GhostName
	if typeof(ghostName) ~= "string" or ghostName == "" then
		return nil
	end

	return ghostsFolder and (ghostsFolder:FindFirstChild(ghostName) or ghostsFolder:WaitForChild(ghostName, 2)) or nil
end

local function findProjectionBody(payload)
	local projectionId = payload and payload.ProjectionId
	if typeof(projectionId) ~= "string" or projectionId == "" then
		return nil
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("Model")
			and descendant:GetAttribute("HoroProjectionBody") == true
			and descendant:GetAttribute("ProjectionId") == projectionId
		then
			return descendant
		end
	end

	return nil
end

local function buildOverlapParams(exclusions)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions or {}
	return params
end

local function isDangerousHazardPart(part, state)
	if not part or not part:IsA("BasePart") then
		return false
	end
	if state and state.GhostModel and part:IsDescendantOf(state.GhostModel) then
		return false
	end
	if state and state.BodyCharacter and part:IsDescendantOf(state.BodyCharacter) then
		return false
	end

	local hazardRoot = HazardUtils.GetHazardInfo(part)
	if hazardRoot ~= nil then
		return true
	end

	local refs = MapResolver.GetRefs()
	local clientWaves = refs and refs.ClientWaves
	return clientWaves ~= nil and part:IsDescendantOf(clientWaves)
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections or {}) do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
end

local function createGhostHint(rootPart)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HoroGhostHint"
	gui.Size = UDim2.fromOffset(150, 36)
	gui.StudsOffset = Vector3.new(0, 3.4, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 90
	gui.Parent = rootPart

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "E  GRAB"
	label.TextColor3 = Color3.fromRGB(238, 251, 255)
	label.TextStrokeColor3 = Color3.fromRGB(35, 60, 78)
	label.TextStrokeTransparency = 0.15
	label.TextSize = 16
	label.Parent = gui

	return gui, label
end

local function normalizeMoveVector(moveVector)
	if typeof(moveVector) ~= "Vector3" then
		return Vector3.zero
	end

	local flatMove = Vector3.new(moveVector.X, 0, moveVector.Z)
	if flatMove.Magnitude > 1 then
		return flatMove.Unit
	end

	return flatMove
end

local function getPlayerControls(player)
	local playerScripts = player and player:FindFirstChild("PlayerScripts")
	local playerModuleScript = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModuleScript then
		return nil
	end

	local ok, playerModule = pcall(require, playerModuleScript)
	if not ok or type(playerModule) ~= "table" or typeof(playerModule.GetControls) ~= "function" then
		return nil
	end

	local controlsOk, controls = pcall(function()
		return playerModule:GetControls()
	end)
	if controlsOk then
		return controls
	end

	return nil
end

local function getControlMoveVector(controls)
	if type(controls) ~= "table" or typeof(controls.GetMoveVector) ~= "function" then
		return Vector3.zero
	end

	local ok, moveVector = pcall(function()
		return controls:GetMoveVector()
	end)
	if ok then
		return normalizeMoveVector(moveVector)
	end

	return Vector3.zero
end

local function getKeyboardMoveVector()
	if UserInputService:GetFocusedTextBox() then
		return Vector3.zero
	end

	local x = 0
	local z = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		z += 1
	end

	return normalizeMoveVector(Vector3.new(x, 0, z))
end

local function getGamepadMoveVector()
	for _, input in ipairs(UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)) do
		if input.KeyCode == Enum.KeyCode.Thumbstick1 then
			local position = input.Position
			local x = if math.abs(position.X) > 0.12 then position.X else 0
			local z = if math.abs(position.Y) > 0.12 then -position.Y else 0
			return normalizeMoveVector(Vector3.new(x, 0, z))
		end
	end

	return Vector3.zero
end

local function getManualMoveVector()
	return normalizeMoveVector(getKeyboardMoveVector() + getGamepadMoveVector())
end

local function getVerticalInputAxis()
	if UserInputService:GetFocusedTextBox() then
		return 0
	end

	local verticalAxis = 0
	if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
		verticalAxis += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	then
		verticalAxis -= 1
	end

	return verticalAxis
end

local function getPlanarVector(vector)
	if typeof(vector) ~= "Vector3" then
		return Vector3.zero
	end

	return Vector3.new(vector.X, 0, vector.Z)
end

local function getFlightDeltaTime(dt)
	local numericDt = tonumber(dt)
	if numericDt == nil then
		return DEFAULT_FLIGHT_DT
	end

	return math.clamp(numericDt, MIN_FLIGHT_DT, MAX_FLIGHT_DT)
end

local function getWorldMoveVector(localMoveVector, camera)
	local moveVector = normalizeMoveVector(localMoveVector)
	if moveVector.Magnitude <= 0 then
		return Vector3.zero
	end

	local cameraCFrame = camera and camera.CFrame or CFrame.new()
	local lookVector = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
	local rightVector = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z)
	if lookVector.Magnitude <= 0.001 then
		lookVector = Vector3.new(0, 0, -1)
	else
		lookVector = lookVector.Unit
	end
	if rightVector.Magnitude <= 0.001 then
		rightVector = Vector3.new(1, 0, 0)
	else
		rightVector = rightVector.Unit
	end

	return normalizeMoveVector((rightVector * moveVector.X) + (lookVector * -moveVector.Z))
end

function HoroClient.Create(config)
	config = config or {}

	local self = setmetatable({}, HoroClient)
	self.player = config.player or Players.LocalPlayer
	self.activeState = nil
	return self
end

function HoroClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return nil
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function HoroClient:BuildRequestPayload(abilityName, _abilityEntry, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return nil
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function HoroClient:SendAction(actionName, payload)
	local remote = getActionRemote()
	if not remote or not remote:IsA("RemoteEvent") then
		horoClientTrace(
			"sendAction failed action=%s projectionId=%s reason=missing_remote",
			tostring(actionName),
			tostring(self.activeState and self.activeState.ProjectionId)
		)
		return false
	end

	horoClientTrace(
		"sendAction action=%s projectionId=%s carryAttrs={%s}",
		tostring(actionName),
		tostring((payload and payload.ProjectionId) or (self.activeState and self.activeState.ProjectionId)),
		getPlayerCarrySummary(self.player)
	)
	remote:FireServer(actionName, payload or {})
	return true
end

function HoroClient:StyleLocalGhost(ghostModel, localTransparency)
	for _, descendant in ipairs(ghostModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			descendant.LocalTransparencyModifier = math.clamp(localTransparency or 0.2, 0, 0.95)
		end
	end
end

function HoroClient:HookGhostTouches(state)
	local function hookPart(part)
		if not part:IsA("BasePart") then
			return
		end

		state.Connections[#state.Connections + 1] = part.Touched:Connect(function(hit)
			if isDangerousHazardPart(hit, state) then
				self:InterruptProjection("hazard_touch")
			end
		end)
	end

	for _, descendant in ipairs(state.GhostModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hookPart(descendant)
		end
	end

	state.Connections[#state.Connections + 1] = state.GhostModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			hookPart(descendant)
		end
	end)
end

function HoroClient:HookBodyTouches(state)
	if not state.BodyRoot then
		return
	end

	state.Connections[#state.Connections + 1] = state.BodyRoot.Touched:Connect(function(hit)
		if isDangerousHazardPart(hit, state) then
			self:ReportBodyHazard("body_hazard_touch")
		end
	end)
end

function HoroClient:StartLocalProjection(payload)
	self:StopLocalProjection(nil, false)

	local abilityConfig = getAbilityConfig()
	local ghostModel = findGhostModel(payload)
	local ghostRoot = getGhostRoot(ghostModel)
	if not ghostModel or not ghostRoot then
		horoClientTrace(
			"startLocalProjection failed projectionId=%s reason=ghost_missing ghostModel=%s ghostRoot=%s",
			tostring(payload and payload.ProjectionId),
			formatInstancePath(ghostModel),
			formatInstancePath(ghostRoot)
		)
		return false
	end

	local camera = Workspace.CurrentCamera
	local ghostHumanoid = ghostModel:FindFirstChildOfClass("Humanoid")
	local bodyCharacter = findProjectionBody(payload)
	local bodyRoot = bodyCharacter and bodyCharacter:FindFirstChild("HumanoidRootPart") or nil

	local state = {
		GhostModel = ghostModel,
		GhostRoot = ghostRoot,
		GhostHumanoid = ghostHumanoid,
		BodyCharacter = bodyCharacter,
		BodyRoot = bodyRoot,
		ProjectionId = payload and payload.ProjectionId,
		EndTime = tonumber(payload and payload.EndTime) or (Workspace:GetServerTimeNow() + DEFAULT_DURATION),
		Duration = clampNumber(payload and payload.Duration, DEFAULT_DURATION, 0.5, 12),
		GhostSpeed = clampNumber(payload and payload.GhostSpeed, abilityConfig.GhostSpeed or DEFAULT_GHOST_SPEED, 2, MAX_PROJECTION_MOVE_SPEED),
		CarrySpeed = clampNumber(payload and payload.CarrySpeed, abilityConfig.CarrySpeed or DEFAULT_CARRY_SPEED, 1, MAX_PROJECTION_MOVE_SPEED),
		MaxDistanceFromBody = clampNumber(payload and payload.MaxDistanceFromBody, abilityConfig.MaxDistanceFromBody or DEFAULT_MAX_DISTANCE_FROM_BODY, 8, 180),
		RewardInteractRadius = clampNumber(payload and payload.RewardInteractRadius, abilityConfig.RewardInteractRadius or DEFAULT_REWARD_INTERACT_RADIUS, 3, 24),
		HazardProbeRadius = clampNumber(payload and payload.HazardProbeRadius, abilityConfig.HazardProbeRadius or DEFAULT_HAZARD_PROBE_RADIUS, 1, 10),
		ClientHazardReportThrottle = clampNumber(
			abilityConfig.ClientHazardReportThrottle,
			DEFAULT_CLIENT_HAZARD_REPORT_THROTTLE,
			0.05,
			1
		),
		NextHazardProbeAt = 0,
		NextBodyHazardProbeAt = 0,
		NextPickupAt = 0,
		NextInterruptAt = 0,
		NextBodyInterruptAt = 0,
		GhostY = ghostRoot.Position.Y,
		HoverHeight = ghostRoot.Position.Y,
		FlightHorizontalResponse = DEFAULT_FLIGHT_HORIZONTAL_RESPONSE,
		FlightVerticalHoldResponse = DEFAULT_FLIGHT_VERTICAL_HOLD_RESPONSE,
		Connections = {},
		Camera = camera,
		PreviousCameraSubject = camera and camera.CameraSubject or nil,
		PreviousCameraType = camera and camera.CameraType or nil,
		Controls = getPlayerControls(self.player),
	}
	self.activeState = state
	horoClientTrace(
		"startLocalProjection projectionId=%s ghost=%s ghostPos=%s body=%s bodyPos=%s endTime=%s duration=%s carryAttrs={%s}",
		tostring(state.ProjectionId),
		formatInstancePath(ghostModel),
		formatVector3(ghostRoot.Position),
		formatInstancePath(bodyCharacter),
		formatVector3(bodyRoot and bodyRoot.Position or nil),
		tostring(state.EndTime),
		tostring(state.Duration),
		getPlayerCarrySummary(self.player)
	)

	self:StyleLocalGhost(ghostModel, clampNumber(abilityConfig.GhostLocalTransparency, 0.2, 0, 0.95))
	state.HintGui, state.HintLabel = createGhostHint(ghostRoot)

	if camera then
		camera.CameraSubject = ghostHumanoid or ghostRoot
		camera.CameraType = Enum.CameraType.Custom
	end

	self:HookGhostTouches(state)
	self:HookBodyTouches(state)
	state.Connections[#state.Connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or self.activeState ~= state then
			return
		end
		if input.KeyCode == Enum.KeyCode.E then
			self:TryPickup()
		end
	end)

	return true
end

function HoroClient:StopLocalProjection(_payload, keepServerGhost)
	local state = self.activeState
	if not state then
		return
	end
	horoClientTrace(
		"stopLocalProjection projectionId=%s payloadPhase=%s resolveReason=%s keepServerGhost=%s carryAttrs={%s}",
		tostring(state.ProjectionId),
		tostring(_payload and _payload.Phase),
		tostring(_payload and _payload.ResolveReason),
		tostring(keepServerGhost == true),
		getPlayerCarrySummary(self.player)
	)

	self.activeState = nil
	disconnectAll(state.Connections)
	if state.GhostHumanoid and state.GhostHumanoid.Parent then
		state.GhostHumanoid:Move(Vector3.zero, false)
	end

	if state.Camera then
		if state.PreviousCameraType then
			state.Camera.CameraType = state.PreviousCameraType
		end
		local currentHumanoid = getCharacterHumanoid(self.player)
		if currentHumanoid and currentHumanoid ~= state.GhostHumanoid then
			state.Camera.CameraSubject = currentHumanoid
		elseif state.PreviousCameraSubject
			and state.PreviousCameraSubject.Parent
			and state.PreviousCameraSubject ~= state.GhostHumanoid
		then
			state.Camera.CameraSubject = state.PreviousCameraSubject
		else
			if currentHumanoid then
				state.Camera.CameraSubject = currentHumanoid
			end
		end
	end

	if state.HintGui and state.HintGui.Parent then
		state.HintGui:Destroy()
	end

	if not keepServerGhost and state.GhostModel and state.GhostModel.Parent == nil then
		state.GhostModel = nil
	end
end

function HoroClient:IsCarryingReward()
	return self.player:GetAttribute("HoroProjectionCarryingReward") == true
		or self.player:GetAttribute("CarriedMajorRewardType") ~= nil
		or self.player:GetAttribute("CarriedBrainrot") ~= nil
end

function HoroClient:GetCurrentSpeed(state)
	local attributeName = if self:IsCarryingReward() then "HoroProjectionCarrySpeed" else "HoroProjectionGhostSpeed"
	local projectedSpeed = self.player:GetAttribute(attributeName)
	if typeof(projectedSpeed) == "number" and projectedSpeed > 0 then
		return projectedSpeed
	end

	if self:IsCarryingReward() then
		return state.CarrySpeed
	end

	return state.GhostSpeed
end

function HoroClient:GetCurrentVerticalSpeed(state)
	return self:GetCurrentSpeed(state)
end

function HoroClient:GetTargetVerticalVelocity(state, dt)
	local ghostRoot = state and state.GhostRoot
	if not ghostRoot or not ghostRoot.Parent then
		return 0
	end

	local verticalSpeed = self:GetCurrentVerticalSpeed(state)
	local verticalAxis = getVerticalInputAxis()
	if verticalAxis ~= 0 then
		state.HoverHeight = ghostRoot.Position.Y
		return verticalAxis * verticalSpeed
	end

	if typeof(state.HoverHeight) ~= "number" then
		state.HoverHeight = ghostRoot.Position.Y
	end

	local heightDelta = state.HoverHeight - ghostRoot.Position.Y
	if math.abs(heightDelta) <= HOVER_HEIGHT_SNAP_TOLERANCE then
		return 0
	end

	local holdResponse = math.max(1, tonumber(state.FlightVerticalHoldResponse) or DEFAULT_FLIGHT_VERTICAL_HOLD_RESPONSE)
	local correctionVelocity = heightDelta * holdResponse
	local maxCorrectionSpeed = math.max(1, verticalSpeed)
	return math.clamp(correctionVelocity, -maxCorrectionSpeed, maxCorrectionSpeed)
end

function HoroClient:DriveGhostMovement(state, dt)
	if not state.GhostHumanoid or not state.GhostHumanoid.Parent or not state.GhostRoot or not state.GhostRoot.Parent then
		return
	end

	local flightDt = getFlightDeltaTime(dt)
	local currentSpeed = self:GetCurrentSpeed(state)
	local desiredPlanarDirection = Vector3.zero
	local moveVector = Vector3.zero
	if not UserInputService:GetFocusedTextBox() then
		moveVector = getControlMoveVector(state.Controls)
		if moveVector.Magnitude <= 0.01 then
			moveVector = getManualMoveVector()
		end
	end

	desiredPlanarDirection = getWorldMoveVector(moveVector, Workspace.CurrentCamera or state.Camera)
	local desiredPlanarVelocity = desiredPlanarDirection * currentSpeed
	local currentVelocity = state.GhostRoot.AssemblyLinearVelocity
	local currentPlanarVelocity = getPlanarVector(currentVelocity)
	local horizontalResponse = math.max(1, tonumber(state.FlightHorizontalResponse) or DEFAULT_FLIGHT_HORIZONTAL_RESPONSE)
	local blendAlpha = math.clamp(horizontalResponse * flightDt, 0, 1)
	local nextPlanarVelocity = currentPlanarVelocity:Lerp(desiredPlanarVelocity, blendAlpha)
	local nextVerticalVelocity = self:GetTargetVerticalVelocity(state, flightDt)

	state.GhostHumanoid.WalkSpeed = currentSpeed
	state.GhostHumanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	state.GhostHumanoid:Move(desiredPlanarDirection, false)
	state.GhostRoot.AssemblyLinearVelocity = Vector3.new(
		nextPlanarVelocity.X,
		nextVerticalVelocity,
		nextPlanarVelocity.Z
	)
end

function HoroClient:TryPickup()
	local state = self.activeState
	if not state then
		return false
	end

	local now = os.clock()
	if now < state.NextPickupAt then
		horoClientTrace(
			"tryPickup throttled projectionId=%s nextPickupIn=%.3f",
			tostring(state.ProjectionId),
			math.max(0, state.NextPickupAt - now)
		)
		return false
	end
	state.NextPickupAt = now + PICKUP_INPUT_THROTTLE
	horoClientTrace(
		"tryPickup begin projectionId=%s ghostPos=%s carryAttrs={%s}",
		tostring(state.ProjectionId),
		formatVector3(state.GhostRoot and state.GhostRoot.Position or nil),
		getPlayerCarrySummary(self.player)
	)

	return self:SendAction("TryPickup", {
		ProjectionId = state.ProjectionId,
	})
end

function HoroClient:CanActivateOnLocalCooldown(abilityName)
	local canBypass = abilityName == ABILITY_NAME and self.activeState ~= nil
	horoClientTrace(
		"localCooldownRoute ability=%s activeProjection=%s projectionId=%s decision=%s route=%s carryAttrs={%s}",
		tostring(abilityName),
		tostring(self.activeState ~= nil),
		tostring(self.activeState and self.activeState.ProjectionId),
		tostring(canBypass),
		if canBypass then "manual_cancel_request" else "normal_cast_blocked",
		getPlayerCarrySummary(self.player)
	)
	return canBypass
end

function HoroClient:InterruptProjection(reason)
	local state = self.activeState
	if not state then
		return false
	end
	if state.PendingInterrupt then
		return false
	end

	local now = os.clock()
	if now < state.NextInterruptAt then
		return false
	end
	state.NextInterruptAt = now + state.ClientHazardReportThrottle
	state.PendingInterrupt = true

	self:SendAction("Interrupt", {
		ProjectionId = state.ProjectionId,
		Reason = reason or "client_hazard",
	})
	return true
end

function HoroClient:ReportBodyHazard(reason)
	local state = self.activeState
	if not state then
		return false
	end
	if state.PendingBodyHazard then
		return false
	end

	local now = os.clock()
	if now < state.NextBodyInterruptAt then
		return false
	end
	state.NextBodyInterruptAt = now + state.ClientHazardReportThrottle
	state.PendingBodyHazard = true

	self:SendAction("BodyHazard", {
		ProjectionId = state.ProjectionId,
		Reason = reason or "body_hazard",
	})
	return true
end

function HoroClient:ProbeGhostHazards(state, now)
	if now < state.NextHazardProbeAt then
		return
	end
	state.NextHazardProbeAt = now + state.ClientHazardReportThrottle

	local parts = Workspace:GetPartBoundsInRadius(
		state.GhostRoot.Position,
		state.HazardProbeRadius,
		buildOverlapParams({
			state.GhostModel,
			state.BodyCharacter,
		})
	)
	for _, part in ipairs(parts) do
		if isDangerousHazardPart(part, state) then
			self:InterruptProjection("hazard_overlap")
			return
		end
	end
end

function HoroClient:ProbeBodyHazards(state, now)
	if now < state.NextBodyHazardProbeAt then
		return
	end
	state.NextBodyHazardProbeAt = now + state.ClientHazardReportThrottle

	state.BodyRoot = state.BodyRoot and state.BodyRoot.Parent and state.BodyRoot
		or (state.BodyCharacter and state.BodyCharacter:FindFirstChild("HumanoidRootPart"))
	if not state.BodyRoot then
		return
	end

	local parts = Workspace:GetPartsInPart(state.BodyRoot, buildOverlapParams({
		state.BodyCharacter,
		state.GhostModel,
	}))
	for _, part in ipairs(parts) do
		if isDangerousHazardPart(part, state) then
			self:ReportBodyHazard("body_hazard_overlap")
			return
		end
	end
end

function HoroClient:UpdateHint(state)
	if not state.HintLabel then
		return
	end

	local remaining = math.max(0, state.EndTime - Workspace:GetServerTimeNow())
	local carried = self:IsCarryingReward()
	state.HintLabel.Text = string.format("%s  %.1fs", if carried then "CARRYING" else "E  GRAB", remaining)
	state.HintLabel.TextColor3 = if carried then Color3.fromRGB(196, 255, 220) else Color3.fromRGB(238, 251, 255)
end

function HoroClient:Update(dt)
	local state = self.activeState
	if not state then
		return
	end
	if not state.GhostRoot or not state.GhostRoot.Parent then
		self:StopLocalProjection(nil, false)
		return
	end

	local serverNow = Workspace:GetServerTimeNow()
	if serverNow > state.EndTime + 0.45 then
		self:StopLocalProjection(nil, true)
		return
	end

	self:DriveGhostMovement(state, dt)
	local now = os.clock()
	self:ProbeGhostHazards(state, now)
	self:ProbeBodyHazards(state, now)
	self:UpdateHint(state)
end

function HoroClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= ABILITY_NAME then
		return false
	end

	local phase = payload and payload.Phase or "Start"
	horoClientTrace(
		"handleEffect phase=%s projectionId=%s resolveReason=%s targetPlayer=%s localActiveProjection=%s carryAttrs={%s}",
		tostring(phase),
		tostring(payload and payload.ProjectionId),
		tostring(payload and payload.ResolveReason),
		targetPlayer and targetPlayer.Name or "<nil>",
		tostring(self.activeState and self.activeState.ProjectionId),
		getPlayerCarrySummary(self.player)
	)
	if targetPlayer ~= self.player then
		return phase == "Start" or phase == "Resolve" or phase == "Interrupted" or phase == "Rejected" or phase == "Ignored"
	end

	if phase == "Start" then
		return self:StartLocalProjection(payload)
	elseif phase == "Resolve" or phase == "Interrupted" then
		self:StopLocalProjection(payload, false)
		return true
	elseif phase == "Rejected" then
		if self.activeState and payload and payload.ResolveReason == "already_active" then
			return true
		end
		self:StopLocalProjection(payload, false)
		return true
	elseif phase == "Ignored" then
		return true
	end

	return false
end

function HoroClient:HandleStateEvent()
	return false
end

function HoroClient:HandleUnequipped()
	self:StopLocalProjection(nil, true)
	return false
end

function HoroClient:HandleCharacterRemoving()
	self:StopLocalProjection(nil, true)
end

function HoroClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer == self.player then
		self:StopLocalProjection(nil, true)
	end
end

return HoroClient
