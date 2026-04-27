local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local HazardUtils = require(DevilFruits:WaitForChild("HazardUtils"))
local ProtectionRuntime = require(DevilFruits:WaitForChild("ProtectionRuntime"))
local ToriShared = require(DevilFruits:WaitForChild("Tori"):WaitForChild("Shared"):WaitForChild("ToriShared"))

local ToriClient = {}
ToriClient.__index = ToriClient

local DEFAULT_PHOENIX_FRUIT_NAME = ToriShared.FruitName
local DEFAULT_PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local DEFAULT_PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local DEFAULT_PHOENIX_REBIRTH_ABILITY = "PhoenixRebirth"
local DEFAULT_PHOENIX_SHIELD_ANIMATION_LOCK_DURATION = 1.6666667
local PHOENIX_REBIRTH = ToriShared.Passives.PhoenixRebirth
local DEBUG_FLIGHT = true
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_PHOENIX_FLIGHT_STARTUP_DURATION = 0.85
local PHOENIX_HOVER_HEIGHT_TOLERANCE = 0.75
local PHOENIX_HOVER_CORRECTION_GAIN = 4
local PHOENIX_TURN_MIN_RESPONSE_SCALE = 0.55
local PHOENIX_FLIGHT_ROTATION_RESPONSIVENESS = 12
local FLIGHT_UPDATE_LOG_INTERVAL = 0.25
local FLIGHT_MOVE_LOG_INTERVAL = 0.2
local FLIGHT_CORRECTION_LOG_INTERVAL = 0.2
local FLIGHT_DRIFT_WARN_INTERVAL = 0.5
local HAZARD_SUPPRESSION_INTERVAL = 0.05
local HAZARD_SUPPRESSION_GRACE = 0.15
local HAZARD_OVERLAP_MAX_PARTS = 128
local PHOENIX_SHIELD_HIT_EFFECT_THROTTLE = 0.18

local function flightLog(...)
	if not DEBUG_FLIGHT then
		return
	end

	print("[FLIGHT DEBUG]", ...)
end

local function formatFlightNumber(value)
	if typeof(value) ~= "number" then
		return tostring(value)
	end

	return string.format("%.2f", value)
end

local function formatFlightVector(vector)
	if typeof(vector) ~= "Vector3" then
		return tostring(vector)
	end

	return string.format("(%.2f, %.2f, %.2f)", vector.X, vector.Y, vector.Z)
end

local function clampPositiveNumber(value, fallback)
	local numericValue = tonumber(value)
	if not numericValue or numericValue <= 0 then
		return fallback
	end

	return numericValue
end

local function getCharacter(self)
	local player = self.player
	if not player then
		return nil
	end

	return player.Character
end

local function getHumanoid(self)
	local character = getCharacter(self)
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function getRootPart(self)
	local character = getCharacter(self)
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
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

local function getInstancePosition(instance, fallbackPart)
	if instance and instance:IsA("Model") then
		return instance:GetPivot().Position
	end

	if instance and instance:IsA("BasePart") then
		return instance.Position
	end

	if fallbackPart and fallbackPart:IsA("BasePart") then
		return fallbackPart.Position
	end

	return nil
end

local function isDescendantOfClientWave(instance, clientWavesFolder)
	return clientWavesFolder ~= nil and instance:IsDescendantOf(clientWavesFolder)
end

local function getWaveTemplate(instance)
	local current = instance
	while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
		current = current.Parent
	end

	if not current then
		return nil
	end

	local wavesFolder = ReplicatedStorage:FindFirstChild("Waves")
	if not wavesFolder then
		return nil
	end

	return wavesFolder:FindFirstChild(current.Name)
end

local function getHazardContainer(instance, clientWavesFolder)
	local root, hazardClass, hazardType, canFreeze, freezeBehavior = HazardUtils.GetHazardInfo(instance)
	if root then
		return root, hazardClass, hazardType, canFreeze, freezeBehavior
	end

	if isDescendantOfClientWave(instance, clientWavesFolder) then
		local template = getWaveTemplate(instance)
		if template then
			local _, templateClass, templateType, templateCanFreeze, templateFreezeBehavior =
				HazardUtils.GetHazardInfo(template)
			if templateClass or templateType or templateCanFreeze or templateFreezeBehavior then
				local current = instance
				while current and current.Parent and current.Parent.Name ~= "ClientWaves" do
					current = current.Parent
				end

				return current or instance, templateClass, templateType, templateCanFreeze, templateFreezeBehavior
			end
		end
	end

	return nil, nil, nil, false, nil
end

local function getCurrentCamera()
	return Workspace.CurrentCamera
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getPlanarUnitOrFallback(vector, fallback)
	local planarVector = getPlanarVector(vector)
	if planarVector.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarVector.Unit
	end

	if typeof(fallback) == "Vector3" then
		local planarFallback = getPlanarVector(fallback)
		if planarFallback.Magnitude > MIN_DIRECTION_MAGNITUDE then
			return planarFallback.Unit
		end
	end

	return Vector3.new(0, 0, -1)
end

local function getPerpendicularPlanarRightVector(forwardVector)
	return Vector3.new(-forwardVector.Z, 0, forwardVector.X)
end

local function getExponentialResponse(responsiveness, dt)
	return math.clamp(1 - math.exp(-math.max(0, responsiveness) * math.max(0, dt or 0)), 0, 1)
end

local function getTurnAdjustedResponse(currentPlanarVelocity, desiredPlanarVelocity, responsiveness, dt)
	local baseResponse = getExponentialResponse(responsiveness, dt)
	if
		currentPlanarVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE
		or desiredPlanarVelocity.Magnitude <= MIN_DIRECTION_MAGNITUDE
	then
		return baseResponse
	end

	local turnDot = math.clamp(currentPlanarVelocity.Unit:Dot(desiredPlanarVelocity.Unit), -1, 1)
	local turnAmount = math.acos(turnDot) / math.pi
	local responseScale = 1 - ((1 - PHOENIX_TURN_MIN_RESPONSE_SCALE) * turnAmount)
	return baseResponse * responseScale
end

local function getCurrentLookVector(rootPart)
	local camera = getCurrentCamera()
	local lookVector = camera and camera.CFrame.LookVector or (rootPart and rootPart.CFrame.LookVector)
	if typeof(lookVector) ~= "Vector3" or lookVector.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector3.new(0, 0, -1)
	end

	return lookVector.Unit
end

local function getInitialLiftVelocity(initialLift)
	local gravity = math.max(Workspace.Gravity, 0.01)
	return math.sqrt(2 * gravity * math.max(initialLift, 0))
end

local function pivotCharacterToRootCFrame(character, rootPart, targetRootCFrame)
	if not character or not rootPart or typeof(targetRootCFrame) ~= "CFrame" then
		return
	end

	local pivotToRoot = character:GetPivot():ToObjectSpace(rootPart.CFrame)
	character:PivotTo(targetRootCFrame * pivotToRoot:Inverse())
end

local function getPlanarDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

function ToriClient.new(config)
	local self = setmetatable({}, ToriClient)
	self.player = config and config.player or Players.LocalPlayer
	self.clientEffectVisuals = config and config.clientEffectVisuals or nil
	self.phoenixFruitName = (config and config.phoenixFruitName) or DEFAULT_PHOENIX_FRUIT_NAME
	self.phoenixFlightAbility = (config and config.phoenixFlightAbility) or DEFAULT_PHOENIX_FLIGHT_ABILITY
	self.phoenixShieldAbility = (config and config.phoenixShieldAbility) or DEFAULT_PHOENIX_SHIELD_ABILITY
	self.phoenixRebirthAbility = (config and config.phoenixRebirthAbility) or DEFAULT_PHOENIX_REBIRTH_ABILITY
	self.flightInputState = {
		Forward = false,
		Backward = false,
		Left = false,
		Right = false,
	}
	self.activePhoenixShields = {}
	self.suppressedHazardParts = {}
	self.shieldHitEffectTimes = setmetatable({}, { __mode = "k" })
	self.hazardSuppressionLoopRunning = false
	self.phoenixShieldAnimationLock = nil
	self.lastPhoenixRebirthVisualTriggeredAt = nil
	self.phoenixRebirthVisualTimes = setmetatable({}, { __mode = "k" })
	self.phoenixFlightState = {
		Active = false,
		EndTime = 0,
		FlightStartTime = 0,
		FlightDuration = 0,
		FlightStarted = false,
		TakeoffStarted = false,
		StartupDuration = 0,
		TakeoffEndTime = 0,
		TakeoffDuration = 0,
		TakeoffVelocity = 0,
		ActivationHeight = 0,
		InitialLiftTarget = 0,
		InitialLift = 0,
		MaxHeight = 0,
		MaxRiseHeight = 0,
		BaseFlightSpeed = 0,
		FlightSpeedScaleReference = 0,
		FlightSpeedScaleStrength = 0,
		FlightSpeed = 0,
		VerticalSpeed = 0,
		MaxDescendSpeed = 0,
		HorizontalResponsiveness = 0,
	}
	self._protectionRegistered = false
	self._rebirthHookRegistered = false
	self.flightDebugTimers = {}
	self:EnsureProtectionRegistration()
	self:EnsurePhoenixRebirthPlaceholderHook()
	return self
end

function ToriClient.Create(config)
	return ToriClient.new(config)
end

function ToriClient:EnsureProtectionRegistration()
	if self._protectionRegistered then
		return
	end

	self._protectionRegistered = true
	ProtectionRuntime.Register("PhoenixProtection", function(targetPlayer, position)
		if targetPlayer ~= self.player then
			return false
		end

		return self:IsLocalPlayerInsidePhoenixShield(position) or self:IsPhoenixRebirthProtected()
	end)
end

function ToriClient:EnsurePhoenixRebirthPlaceholderHook()
	if self._rebirthHookRegistered then
		return
	end

	local player = self.player
	if not player then
		return
	end

	self._rebirthHookRegistered = true
	player:GetAttributeChangedSignal(PHOENIX_REBIRTH.TriggeredAtAttribute):Connect(function()
		local triggeredAt = player:GetAttribute(PHOENIX_REBIRTH.TriggeredAtAttribute)
		if typeof(triggeredAt) ~= "number" then
			return
		end

		self:HandlePhoenixRebirthTriggered(triggeredAt)
	end)
end

function ToriClient:IsPhoenixRebirthProtected()
	local player = self.player
	if not player then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	local pendingUntil = player:GetAttribute(PHOENIX_REBIRTH.PendingUntilAttribute)
	if typeof(pendingUntil) == "number" and pendingUntil > now then
		return true
	end

	local immuneUntil = player:GetAttribute(PHOENIX_REBIRTH.ImmuneUntilAttribute)
	return typeof(immuneUntil) == "number" and immuneUntil > now
end

function ToriClient:HandlePhoenixRebirthTriggered(triggeredAt)
	if self:ResolveEquippedFruitName() ~= self.phoenixFruitName then
		return false
	end

	self.lastPhoenixRebirthVisualTriggeredAt = tonumber(triggeredAt) or self.lastPhoenixRebirthVisualTriggeredAt
	return true
end

function ToriClient:PlayPhoenixRebirthVisual(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return false
	end

	payload = payload or {}
	local triggeredAt = tonumber(payload.TriggeredAt) or Workspace:GetServerTimeNow()
	self.phoenixRebirthVisualTimes = self.phoenixRebirthVisualTimes or setmetatable({}, { __mode = "k" })
	local lastTriggeredAt = self.phoenixRebirthVisualTimes[targetPlayer]
	if lastTriggeredAt and math.abs(lastTriggeredAt - triggeredAt) <= 0.05 then
		return true
	end

	self.lastPhoenixRebirthVisualTriggeredAt = triggeredAt
	self.phoenixRebirthVisualTimes[targetPlayer] = triggeredAt
	if self.clientEffectVisuals and typeof(self.clientEffectVisuals.CreatePhoenixRebirthEffect) == "function" then
		self.clientEffectVisuals:CreatePhoenixRebirthEffect(
			targetPlayer,
			self.phoenixFruitName,
			self.phoenixRebirthAbility,
			payload
		)
	end

	return true
end

function ToriClient:ResolveEquippedFruitName()
	local player = self.player
	if not player then
		return DevilFruitConfig.None
	end

	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		return DevilFruitConfig.ResolveFruitName(fruitAttribute) or fruitAttribute
	end

	local fruitFolder = player:FindFirstChild("DevilFruit")
	if fruitFolder then
		local equipped = fruitFolder:FindFirstChild("Equipped")
		if equipped and equipped:IsA("StringValue") then
			return DevilFruitConfig.ResolveFruitName(equipped.Value) or equipped.Value
		end
	end

	return DevilFruitConfig.None
end

function ToriClient:GetPhoenixFlightKeyCode()
	local abilityConfig = DevilFruitConfig.GetAbility(self.phoenixFruitName, self.phoenixFlightAbility)
	if abilityConfig and abilityConfig.KeyCode then
		return abilityConfig.KeyCode
	end

	return Enum.KeyCode.Q
end

function ToriClient:ShouldLogFlightDebug(timerKey, now, interval)
	if not DEBUG_FLIGHT then
		return false
	end

	now = now or os.clock()
	self.flightDebugTimers = self.flightDebugTimers or {}

	local nextLogAt = self.flightDebugTimers[timerKey] or 0
	if now < nextLogAt then
		return false
	end

	self.flightDebugTimers[timerKey] = now + interval
	return true
end

function ToriClient:IsPhoenixFlightActive(now)
	now = now or os.clock()
	return self.phoenixFlightState.Active
		and (not self.phoenixFlightState.FlightStarted or now < self.phoenixFlightState.EndTime)
end

function ToriClient:StopPhoenixFlight()
	if not self.phoenixFlightState.Active then
		return
	end

	local rootPart = getRootPart(self)
	self.phoenixFlightState.Active = false
	self.phoenixFlightState.EndTime = 0
	self.phoenixFlightState.FlightStartTime = 0
	self.phoenixFlightState.FlightDuration = 0
	self.phoenixFlightState.FlightStarted = false
	self.phoenixFlightState.TakeoffStarted = false
	self.phoenixFlightState.StartupDuration = 0
	self.phoenixFlightState.TakeoffEndTime = 0
	self.phoenixFlightState.TakeoffDuration = 0
	self.phoenixFlightState.TakeoffVelocity = 0
	self.phoenixFlightState.ActivationHeight = 0
	self.phoenixFlightState.InitialLiftTarget = 0
	self.phoenixFlightState.InitialLift = 0
	self.phoenixFlightState.MaxHeight = 0
	self.phoenixFlightState.MaxRiseHeight = 0
	self.phoenixFlightState.BaseFlightSpeed = 0
	self.phoenixFlightState.FlightSpeedScaleReference = 0
	self.phoenixFlightState.FlightSpeedScaleStrength = 0
	self.phoenixFlightState.FlightSpeed = 0
	self.phoenixFlightState.VerticalSpeed = 0
	self.phoenixFlightState.MaxDescendSpeed = 0
	self.phoenixFlightState.HorizontalResponsiveness = 0

	if rootPart then
		flightLog("END", "Final Y:", formatFlightNumber(rootPart.Position.Y))
	end

	local humanoid = getHumanoid(self)
	if humanoid then
		humanoid.AutoRotate = true
	end

	if self.clientEffectVisuals and typeof(self.clientEffectVisuals.StopPhoenixFlightEffect) == "function" then
		self.clientEffectVisuals:StopPhoenixFlightEffect(self.player)
	end
end

function ToriClient:BeginPhoenixFlightTakeoff(rootPart, now)
	if not rootPart or self.phoenixFlightState.TakeoffStarted then
		return
	end

	now = now or os.clock()
	self.phoenixFlightState.TakeoffStarted = true
	self.phoenixFlightState.FlightStartTime = now
	self.phoenixFlightState.TakeoffEndTime = now + self.phoenixFlightState.TakeoffDuration

	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X,
		math.max(currentVelocity.Y, self.phoenixFlightState.TakeoffVelocity),
		currentVelocity.Z
	)

	flightLog(
		"TAKEOFF BEGIN",
		"Y:",
		formatFlightNumber(rootPart.Position.Y),
		"TargetY:",
		formatFlightNumber(self.phoenixFlightState.MaxHeight)
	)
end

function ToriClient:BeginPhoenixFlightControl(rootPart, now)
	if not rootPart or self.phoenixFlightState.FlightStarted then
		return
	end

	now = now or os.clock()
	self.phoenixFlightState.FlightStarted = true
	self.phoenixFlightState.FlightStartTime = now
	self.phoenixFlightState.EndTime = now + math.max(0.1, self.phoenixFlightState.FlightDuration)

	flightLog(
		"FLIGHT BEGIN",
		"Duration:",
		formatFlightNumber(self.phoenixFlightState.FlightDuration),
		"EndIn:",
		formatFlightNumber(self.phoenixFlightState.EndTime - now),
		"Y:",
		formatFlightNumber(rootPart.Position.Y),
		"TargetY:",
		formatFlightNumber(self.phoenixFlightState.MaxHeight)
	)
end

function ToriClient:UpdatePhoenixFlightStartup(rootPart, humanoid, dt, now)
	if self:TryBeginPhoenixFlightControlAtHeight(rootPart, now) then
		return true
	end

	local flightStartTime = self.phoenixFlightState.FlightStartTime
	if now >= flightStartTime then
		self:BeginPhoenixFlightTakeoff(rootPart, now)
		return true
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local currentVelocity = rootPart.AssemblyLinearVelocity
	local response = math.clamp(self.phoenixFlightState.HorizontalResponsiveness * dt, 0, 1)
	local nextPlanarVelocity = getPlanarVector(currentVelocity):Lerp(Vector3.zero, response)
	rootPart.AssemblyLinearVelocity = Vector3.new(nextPlanarVelocity.X, 0, nextPlanarVelocity.Z)

	if self:ShouldLogFlightDebug("Startup", now, FLIGHT_UPDATE_LOG_INTERVAL) then
		flightLog(
			"STARTUP",
			"CanFlyIn:",
			formatFlightNumber(math.max(0, flightStartTime - now)),
			"Timer:",
			"waiting"
		)
	end

	return false
end

function ToriClient:HasReachedPhoenixFlightHeight(rootPart)
	if not rootPart then
		return false
	end

	return rootPart.Position.Y >= self.phoenixFlightState.MaxHeight - PHOENIX_HOVER_HEIGHT_TOLERANCE
end

function ToriClient:TryBeginPhoenixFlightControlAtHeight(rootPart, now)
	if self.phoenixFlightState.FlightStarted or not self:HasReachedPhoenixFlightHeight(rootPart) then
		return false
	end

	now = now or os.clock()
	if not self.phoenixFlightState.TakeoffStarted then
		self.phoenixFlightState.TakeoffStarted = true
		self.phoenixFlightState.TakeoffEndTime = now
		self.phoenixFlightState.FlightStartTime = now
	end

	self:SnapPhoenixHoverHeight(rootPart)
	rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
	self:BeginPhoenixFlightControl(rootPart, now)
	return true
end

function ToriClient:UpdatePhoenixFlightTakeoff(rootPart, humanoid, dt, now)
	if not self.phoenixFlightState.TakeoffStarted then
		return false
	end

	if self:TryBeginPhoenixFlightControlAtHeight(rootPart, now) then
		return true
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local currentHeight = rootPart.Position.Y
	local targetVerticalVelocity = self:GetTargetHoverVerticalVelocity(currentHeight, now)
	local currentVelocity = rootPart.AssemblyLinearVelocity
	local response = math.clamp(self.phoenixFlightState.HorizontalResponsiveness * dt, 0, 1)
	local nextPlanarVelocity = getPlanarVector(currentVelocity):Lerp(Vector3.zero, response)
	rootPart.AssemblyLinearVelocity = Vector3.new(nextPlanarVelocity.X, targetVerticalVelocity, nextPlanarVelocity.Z)

	if self:ShouldLogFlightDebug("Takeoff", now, FLIGHT_UPDATE_LOG_INTERVAL) then
		flightLog(
			"TAKEOFF",
			"Y:",
			formatFlightNumber(rootPart.Position.Y),
			"TargetY:",
			formatFlightNumber(self.phoenixFlightState.MaxHeight),
			"VelY:",
			formatFlightNumber(rootPart.AssemblyLinearVelocity.Y)
		)
	end

	if not self:TryBeginPhoenixFlightControlAtHeight(rootPart, now) then
		return false
	end

	return true
end

function ToriClient:StartPhoenixFlight(payload)
	local rootPart = getRootPart(self)
	local humanoid = getHumanoid(self)
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	self:StopPhoenixFlight()

	local now = os.clock()
	local duration = math.max(0.1, tonumber(payload and payload.Duration) or 0)
	local startupDuration = math.max(
		0,
		tonumber(payload and payload.StartupDuration) or DEFAULT_PHOENIX_FLIGHT_STARTUP_DURATION
	)
	local takeoffDuration = math.max(0.1, tonumber(payload and payload.TakeoffDuration) or 0.4)
	local initialLift = math.max(0, tonumber(payload and payload.InitialLift) or 10)
	local maxRiseHeight = math.max(initialLift, tonumber(payload and payload.MaxRiseHeight) or initialLift)
	local liftVelocity = getInitialLiftVelocity(initialLift)
	local flightStartTime = now + startupDuration

	self.phoenixFlightState.Active = true
	self.phoenixFlightState.EndTime = 0
	self.phoenixFlightState.FlightStartTime = flightStartTime
	self.phoenixFlightState.FlightDuration = duration
	self.phoenixFlightState.FlightStarted = false
	self.phoenixFlightState.TakeoffStarted = false
	self.phoenixFlightState.StartupDuration = startupDuration
	self.phoenixFlightState.TakeoffEndTime = flightStartTime + takeoffDuration
	self.phoenixFlightState.TakeoffDuration = takeoffDuration
	self.phoenixFlightState.TakeoffVelocity = liftVelocity
	self.phoenixFlightState.ActivationHeight = rootPart.Position.Y
	self.phoenixFlightState.InitialLiftTarget = rootPart.Position.Y + initialLift
	self.phoenixFlightState.InitialLift = initialLift
	self.phoenixFlightState.MaxHeight = rootPart.Position.Y + maxRiseHeight
	self.phoenixFlightState.MaxRiseHeight = maxRiseHeight
	self.phoenixFlightState.BaseFlightSpeed = math.max(0, tonumber(payload and payload.FlightSpeed) or 78)
	self.phoenixFlightState.FlightSpeedScaleReference = math.max(
		1,
		tonumber(payload and payload.FlightSpeedScaleReference) or 17
	)
	self.phoenixFlightState.FlightSpeedScaleStrength = math.max(
		0,
		tonumber(payload and payload.FlightSpeedScaleStrength) or 0.5
	)
	self.phoenixFlightState.FlightSpeed = self:GetScaledPhoenixFlightSpeed(humanoid)
	self.phoenixFlightState.VerticalSpeed = math.max(0, tonumber(payload and payload.VerticalSpeed) or 52)
	self.phoenixFlightState.MaxDescendSpeed = math.max(0, tonumber(payload and payload.MaxDescendSpeed) or 58)
	self.phoenixFlightState.HorizontalResponsiveness = math.max(1, tonumber(payload and payload.HorizontalResponsiveness) or 10)
	self.flightDebugTimers = {}

	humanoid.AutoRotate = false
	humanoid.Jump = true
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local currentVelocity = rootPart.AssemblyLinearVelocity
	rootPart.AssemblyLinearVelocity = Vector3.new(
		currentVelocity.X * 0.15,
		0,
		currentVelocity.Z * 0.15
	)
	if startupDuration <= 0 then
		self:BeginPhoenixFlightTakeoff(rootPart, now)
	end

	flightLog(
		"START",
		"Y:",
		formatFlightNumber(rootPart.Position.Y),
		"Startup:",
		formatFlightNumber(startupDuration),
		"FlightDuration:",
		formatFlightNumber(duration),
		"TimerStartsIn:",
		formatFlightNumber(math.max(0, self.phoenixFlightState.FlightStartTime - now))
	)
end

function ToriClient:SetFlightInputKeyState(keyCode, isPressed)
	if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
		self.flightInputState.Forward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
		self.flightInputState.Backward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
		self.flightInputState.Left = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
		self.flightInputState.Right = isPressed
		return true
	end

	return false
end

function ToriClient:GetFlightInputAxes()
	local forwardAxis = 0
	local rightAxis = 0

	if self.flightInputState.Forward then
		forwardAxis += 1
	end
	if self.flightInputState.Backward then
		forwardAxis -= 1
	end
	if self.flightInputState.Right then
		rightAxis += 1
	end
	if self.flightInputState.Left then
		rightAxis -= 1
	end

	return forwardAxis, rightAxis
end

function ToriClient:GetCameraRelativeFlightDirection(rootPart)
	local forwardAxis, rightAxis = self:GetFlightInputAxes()
	if forwardAxis == 0 and rightAxis == 0 then
		return Vector3.zero
	end

	local camera = getCurrentCamera()
	local forwardVector = getPlanarUnitOrFallback(
		camera and camera.CFrame.LookVector or getCurrentLookVector(rootPart),
		rootPart and rootPart.CFrame.LookVector or nil
	)
	local rawRightVector = camera and camera.CFrame.RightVector or (rootPart and rootPart.CFrame.RightVector) or nil
	local rightVector = getPlanarVector(rawRightVector)
	if rightVector.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		rightVector = getPerpendicularPlanarRightVector(forwardVector)
	else
		rightVector = rightVector.Unit
	end

	local direction = (forwardVector * forwardAxis) + (rightVector * rightAxis)
	local magnitude = direction.Magnitude
	if magnitude <= MIN_DIRECTION_MAGNITUDE then
		return Vector3.zero
	end

	return direction.Unit * math.min(math.sqrt((forwardAxis * forwardAxis) + (rightAxis * rightAxis)), 1)
end

function ToriClient:GetScaledPhoenixFlightSpeed(humanoid)
	local baseFlightSpeed = math.max(0, tonumber(self.phoenixFlightState.BaseFlightSpeed) or 0)
	local referenceWalkSpeed = math.max(1, tonumber(self.phoenixFlightState.FlightSpeedScaleReference) or 17)
	local currentWalkSpeed = (humanoid and tonumber(humanoid.WalkSpeed)) or referenceWalkSpeed
	local rawScale = math.max(0, currentWalkSpeed) / referenceWalkSpeed
	local scaleStrength = math.max(0, tonumber(self.phoenixFlightState.FlightSpeedScaleStrength) or 0.5)
	local speedScale = math.max(0, 1 + ((rawScale - 1) * scaleStrength))
	return baseFlightSpeed * speedScale
end

function ToriClient:GetTargetHoverVerticalVelocity(currentHeight, now)
	local hoverHeight = self.phoenixFlightState.MaxHeight
	local heightError = hoverHeight - currentHeight
	local inTakeoffPhase = now < self.phoenixFlightState.TakeoffEndTime and currentHeight < self.phoenixFlightState.InitialLiftTarget

	if inTakeoffPhase then
		return math.max(
			self.phoenixFlightState.TakeoffVelocity,
			math.min(
				self.phoenixFlightState.VerticalSpeed,
				math.max(8, heightError * PHOENIX_HOVER_CORRECTION_GAIN)
			)
		)
	end

	if math.abs(heightError) <= PHOENIX_HOVER_HEIGHT_TOLERANCE then
		return 0
	end

	if heightError > 0 then
		local correctionVelocity = math.min(
			self.phoenixFlightState.VerticalSpeed,
			math.max(8, heightError * PHOENIX_HOVER_CORRECTION_GAIN)
		)
		if self:ShouldLogFlightDebug("Correction", now, FLIGHT_CORRECTION_LOG_INTERVAL) then
			flightLog("CORRECTION", "Direction:", "UP", "Amount:", formatFlightNumber(correctionVelocity))
		end
		return correctionVelocity
	end

	local correctionVelocity = math.min(
		self.phoenixFlightState.MaxDescendSpeed,
		math.max(8, math.abs(heightError) * PHOENIX_HOVER_CORRECTION_GAIN)
	)
	if self:ShouldLogFlightDebug("Correction", now, FLIGHT_CORRECTION_LOG_INTERVAL) then
		flightLog("CORRECTION", "Direction:", "DOWN", "Amount:", formatFlightNumber(correctionVelocity))
	end
	return -correctionVelocity
end

function ToriClient:FaceCharacterTowards(direction, dt)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return
	end

	local character = getCharacter(self)
	local rootPart = getRootPart(self)
	if not character or not rootPart then
		return
	end

	local planarDirection = getPlanarVector(direction)
	if planarDirection.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		return
	end

	local rootPosition = rootPart.Position
	local currentDirection = getPlanarUnitOrFallback(rootPart.CFrame.LookVector, planarDirection)
	local turnAlpha = getExponentialResponse(PHOENIX_FLIGHT_ROTATION_RESPONSIVENESS, dt)
	local currentCFrame = CFrame.lookAt(rootPosition, rootPosition + currentDirection, Vector3.yAxis)
	local targetCFrame = CFrame.lookAt(rootPosition, rootPosition + planarDirection.Unit, Vector3.yAxis)
	pivotCharacterToRootCFrame(character, rootPart, currentCFrame:Lerp(targetCFrame, turnAlpha))
end

function ToriClient:SnapPhoenixHoverHeight(rootPart)
	local character = getCharacter(self)
	if not character or not rootPart then
		return
	end

	local targetHeight = self.phoenixFlightState.MaxHeight
	local currentPosition = rootPart.Position
	if math.abs(currentPosition.Y - targetHeight) > PHOENIX_HOVER_HEIGHT_TOLERANCE then
		return
	end

	if math.abs(currentPosition.Y - targetHeight) <= 0.01 then
		return
	end

	local currentRotation = rootPart.CFrame - rootPart.Position
	local targetRootCFrame = CFrame.new(currentPosition.X, targetHeight, currentPosition.Z) * currentRotation
	pivotCharacterToRootCFrame(character, rootPart, targetRootCFrame)
end

function ToriClient:UpdatePhoenixFlight(dt)
	local now = os.clock()
	if self:ResolveEquippedFruitName() ~= self.phoenixFruitName then
		self:StopPhoenixFlight()
		return
	end

	if not self:IsPhoenixFlightActive(now) then
		if self.phoenixFlightState.Active then
			self:StopPhoenixFlight()
		end
		return
	end

	local rootPart = getRootPart(self)
	local humanoid = getHumanoid(self)
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		self:StopPhoenixFlight()
		return
	end

	if not self.phoenixFlightState.TakeoffStarted then
		if not self:UpdatePhoenixFlightStartup(rootPart, humanoid, dt, now) then
			return
		end
	end

	if not self.phoenixFlightState.FlightStarted then
		if not self:UpdatePhoenixFlightTakeoff(rootPart, humanoid, dt, now) then
			return
		end
	end

	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local desiredFlightDirection = self:GetCameraRelativeFlightDirection(rootPart)
	local scaledFlightSpeed = self:GetScaledPhoenixFlightSpeed(humanoid)
	self.phoenixFlightState.FlightSpeed = scaledFlightSpeed
	local desiredPlanarVelocity = desiredFlightDirection * scaledFlightSpeed
	local currentHeight = rootPart.Position.Y
	local targetVerticalVelocity = self:GetTargetHoverVerticalVelocity(currentHeight, now)

	local currentVelocity = rootPart.AssemblyLinearVelocity
	local currentPlanarVelocity = getPlanarVector(currentVelocity)
	local response = getTurnAdjustedResponse(
		currentPlanarVelocity,
		desiredPlanarVelocity,
		self.phoenixFlightState.HorizontalResponsiveness,
		dt
	)
	local nextPlanarVelocity = currentPlanarVelocity:Lerp(desiredPlanarVelocity, response)
	local nextVelocity = Vector3.new(nextPlanarVelocity.X, targetVerticalVelocity, nextPlanarVelocity.Z)
	local positionYBeforeWrites = rootPart.Position.Y

	rootPart.AssemblyLinearVelocity = nextVelocity

	local hoverDiff = rootPart.Position.Y - self.phoenixFlightState.MaxHeight
	local verticalVelocity = rootPart.AssemblyLinearVelocity.Y
	if self:ShouldLogFlightDebug("Update", now, FLIGHT_UPDATE_LOG_INTERVAL) then
		flightLog(
			"UPDATE",
			"Y:",
			formatFlightNumber(rootPart.Position.Y),
			"VelY:",
			formatFlightNumber(verticalVelocity),
			"Diff:",
			formatFlightNumber(hoverDiff)
		)
	end

	local forwardAxis, rightAxis = self:GetFlightInputAxes()
	if (forwardAxis ~= 0 or rightAxis ~= 0) and self:ShouldLogFlightDebug("Move", now, FLIGHT_MOVE_LOG_INTERVAL) then
		flightLog(
			"MOVE",
			"Horizontal:",
			formatFlightVector(Vector3.new(nextVelocity.X, 0, nextVelocity.Z)),
			"FlightSpeed:",
			formatFlightNumber(scaledFlightSpeed),
			"VelY:",
			formatFlightNumber(verticalVelocity)
		)
	end

	local desiredPlanarDirection = desiredPlanarVelocity
	local nextPlanarDirection = getPlanarVector(nextVelocity)
	if desiredPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE or nextPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		local facingDirection = nextPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE and nextPlanarDirection or desiredPlanarDirection
		self:FaceCharacterTowards(facingDirection, dt)
	end

	if math.abs(rootPart.Position.Y - self.phoenixFlightState.MaxHeight) <= PHOENIX_HOVER_HEIGHT_TOLERANCE then
		self:SnapPhoenixHoverHeight(rootPart)
		rootPart.AssemblyLinearVelocity = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
	end

	local finalVerticalVelocity = rootPart.AssemblyLinearVelocity.Y
	local finalHoverDiff = rootPart.Position.Y - self.phoenixFlightState.MaxHeight
	if math.abs(finalHoverDiff) <= PHOENIX_HOVER_HEIGHT_TOLERANCE
		and math.abs(finalVerticalVelocity) > 0.5
		and self:ShouldLogFlightDebug("DriftWarn", now, FLIGHT_DRIFT_WARN_INTERVAL)
	then
		warn("[FLIGHT ISSUE] Vertical drift detected:", finalVerticalVelocity)
	end

	if self:ShouldLogFlightDebug("Final", now, FLIGHT_MOVE_LOG_INTERVAL) then
		flightLog(
			"FINAL",
			"BeforeY:",
			formatFlightNumber(positionYBeforeWrites),
			"CorrectionVelY:",
			formatFlightNumber(targetVerticalVelocity),
			"AfterY:",
			formatFlightNumber(rootPart.Position.Y),
			"FinalVel:",
			formatFlightVector(rootPart.AssemblyLinearVelocity)
		)
	end
end

function ToriClient:BuildHazardOverlapParams()
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = self.player and self.player.Character and { self.player.Character } or {}
	overlapParams.MaxParts = HAZARD_OVERLAP_MAX_PARTS
	return overlapParams
end

function ToriClient:SuppressHazardPart(part, untilTime)
	if not part or not part:IsA("BasePart") then
		return
	end

	local state = self.suppressedHazardParts[part]
	if state then
		if untilTime > state.UntilTime then
			state.UntilTime = untilTime
		end
		return
	end

	self.suppressedHazardParts[part] = {
		OriginalCanTouch = part.CanTouch,
		OriginalCanCollide = part.CanCollide,
		UntilTime = untilTime,
	}

	part.CanTouch = false
	part.CanCollide = false
end

function ToriClient:SuppressHazardContainer(container, untilTime)
	if not container then
		return
	end

	if container:IsA("BasePart") then
		self:SuppressHazardPart(container, untilTime)
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			self:SuppressHazardPart(descendant, untilTime)
		end
	end
end

function ToriClient:RestoreSuppressedHazardParts(now)
	for part, state in pairs(self.suppressedHazardParts) do
		if not part or not part.Parent then
			self.suppressedHazardParts[part] = nil
		elseif now >= state.UntilTime then
			part.CanTouch = state.OriginalCanTouch
			part.CanCollide = state.OriginalCanCollide
			self.suppressedHazardParts[part] = nil
		end
	end
end

function ToriClient:HasActivePhoenixShield(now)
	for shieldOwner, shield in pairs(self.activePhoenixShields) do
		if now < shield.EndTime then
			return true
		end

		self.activePhoenixShields[shieldOwner] = nil
	end

	return false
end

function ToriClient:CreatePhoenixShieldHitPlaceholder(shieldOwner, shield, hazardContainer, hitPart, now)
	if not self.clientEffectVisuals or typeof(self.clientEffectVisuals.CreatePhoenixShieldHitEffect) ~= "function" then
		return
	end

	local nextEffectAt = self.shieldHitEffectTimes[hazardContainer] or 0
	if now < nextEffectAt then
		return
	end

	local hitPosition = getInstancePosition(hitPart, hitPart) or getInstancePosition(hazardContainer, hitPart)
	if not hitPosition then
		return
	end

	self.shieldHitEffectTimes[hazardContainer] = now + PHOENIX_SHIELD_HIT_EFFECT_THROTTLE
	self.clientEffectVisuals:CreatePhoenixShieldHitEffect(shieldOwner, self.phoenixFruitName, self.phoenixShieldAbility, {
		HitPosition = hitPosition,
		Radius = shield.Radius,
	})
end

function ToriClient:SuppressHazardsNearPhoenixShield(shieldOwner, shield, ownerRootPart, localRootPart, now)
	local shieldRadius = math.max(0, tonumber(shield and shield.Radius) or 0)
	if shieldRadius <= 0 then
		return
	end

	if getPlanarDistance(ownerRootPart.Position, localRootPart.Position) > shieldRadius then
		return
	end

	local suppressUntil = math.min(shield.EndTime, now + HAZARD_SUPPRESSION_GRACE)
	local nearbyParts = Workspace:GetPartBoundsInRadius(
		ownerRootPart.Position,
		shieldRadius,
		self:BuildHazardOverlapParams()
	)
	local seenContainers = {}
	local refs = MapResolver.GetRefs()
	local clientWavesFolder = refs and refs.ClientWaves

	for _, part in ipairs(nearbyParts) do
		local hazardContainer = getHazardContainer(part, clientWavesFolder)
		if hazardContainer and not seenContainers[hazardContainer] then
			seenContainers[hazardContainer] = true
			self:SuppressHazardContainer(hazardContainer, suppressUntil)
			self:CreatePhoenixShieldHitPlaceholder(shieldOwner, shield, hazardContainer, part, now)
		end
	end
end

function ToriClient:UpdatePhoenixShieldHazardSuppression()
	local now = os.clock()
	local localRootPart = getRootPart(self)

	for shieldOwner, shield in pairs(self.activePhoenixShields) do
		if now >= shield.EndTime then
			self.activePhoenixShields[shieldOwner] = nil
		else
			local ownerRootPart = getPlayerRootPart(shieldOwner)
			if not ownerRootPart then
				if shieldOwner.Parent == nil then
					self.activePhoenixShields[shieldOwner] = nil
				end
			elseif localRootPart then
				self:SuppressHazardsNearPhoenixShield(shieldOwner, shield, ownerRootPart, localRootPart, now)
			end
		end
	end

	self:RestoreSuppressedHazardParts(now)

	if self:HasActivePhoenixShield(now) then
		task.delay(HAZARD_SUPPRESSION_INTERVAL, function()
			if self.hazardSuppressionLoopRunning then
				self:UpdatePhoenixShieldHazardSuppression()
			end
		end)
	else
		self:RestoreSuppressedHazardParts(math.huge)
		self.hazardSuppressionLoopRunning = false
	end
end

function ToriClient:EnsurePhoenixShieldHazardSuppressionLoop()
	if self.hazardSuppressionLoopRunning then
		return
	end

	self.hazardSuppressionLoopRunning = true
	self:UpdatePhoenixShieldHazardSuppression()
end

function ToriClient:IsLocalPlayerInsidePhoenixShield(position)
	local checkPosition = position
	if typeof(checkPosition) ~= "Vector3" then
		local rootPart = getRootPart(self)
		checkPosition = rootPart and rootPart.Position or nil
	end
	if not checkPosition then
		return false
	end

	local now = os.clock()
	for shieldOwner, shield in pairs(self.activePhoenixShields) do
		if now >= shield.EndTime then
			self.activePhoenixShields[shieldOwner] = nil
		else
			local ownerRootPart = getPlayerRootPart(shieldOwner)
			local shieldRadius = math.max(0, tonumber(shield.Radius) or 0)
			if ownerRootPart and shieldRadius > 0 and getPlanarDistance(ownerRootPart.Position, checkPosition) <= shieldRadius then
				return true
			end
		end
	end

	return false
end

function ToriClient:ReleasePhoenixShieldAnimationLock(lock)
	if self.phoenixShieldAnimationLock ~= lock then
		return
	end

	self.phoenixShieldAnimationLock = nil
	if lock.Connection then
		lock.Connection:Disconnect()
	end

	local humanoid = lock.Humanoid
	if humanoid and humanoid.Parent then
		if lock.WalkSpeed ~= nil then
			humanoid.WalkSpeed = lock.WalkSpeed
		end
		if lock.JumpPower ~= nil then
			humanoid.JumpPower = lock.JumpPower
		end
		if lock.JumpHeight ~= nil then
			humanoid.JumpHeight = lock.JumpHeight
		end
		if lock.AutoRotate ~= nil then
			humanoid.AutoRotate = lock.AutoRotate
		end
	end
end

function ToriClient:SchedulePhoenixShieldAnimationUnlock(lock)
	if lock.UnlockScheduled then
		return
	end

	lock.UnlockScheduled = true
	local function schedule()
		local delayTime = math.max(0, (lock.EndTime or os.clock()) - os.clock())
		task.delay(delayTime, function()
			if self.phoenixShieldAnimationLock ~= lock then
				return
			end

			local remaining = (lock.EndTime or 0) - os.clock()
			if remaining > 0.02 then
				schedule()
				return
			end

			self:ReleasePhoenixShieldAnimationLock(lock)
		end)
	end

	schedule()
end

function ToriClient:StartPhoenixShieldAnimationLock(payload)
	local lockDuration = math.max(
		0,
		tonumber(payload and payload.AnimationLockDuration) or DEFAULT_PHOENIX_SHIELD_ANIMATION_LOCK_DURATION
	)
	if lockDuration <= 0 then
		return
	end

	local humanoid = getHumanoid(self)
	local rootPart = getRootPart(self)
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local now = os.clock()
	local lock = self.phoenixShieldAnimationLock
	if lock and lock.Humanoid ~= humanoid then
		self:ReleasePhoenixShieldAnimationLock(lock)
		lock = nil
	end

	if not lock then
		lock = {
			Humanoid = humanoid,
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			JumpHeight = humanoid.JumpHeight,
			AutoRotate = humanoid.AutoRotate,
		}
		self.phoenixShieldAnimationLock = lock
		lock.Connection = RunService.Heartbeat:Connect(function()
			if self.phoenixShieldAnimationLock ~= lock then
				return
			end

			local currentHumanoid = lock.Humanoid
			if currentHumanoid and currentHumanoid.Parent and currentHumanoid.Health > 0 then
				currentHumanoid.WalkSpeed = 0
				currentHumanoid.JumpPower = 0
				currentHumanoid.JumpHeight = 0
				currentHumanoid.AutoRotate = false
				currentHumanoid:Move(Vector3.zero, true)
			end

			local currentRootPart = getRootPart(self)
			if currentRootPart then
				local currentVelocity = currentRootPart.AssemblyLinearVelocity
				currentRootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
			end
		end)
	end

	lock.EndTime = math.max(lock.EndTime or 0, now + lockDuration)
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero, true)
	if rootPart then
		local currentVelocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
	end

	self:SchedulePhoenixShieldAnimationUnlock(lock)
end

function ToriClient:StartPhoenixShield(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	local duration = tonumber(payload and payload.Duration) or 0
	local radius = tonumber(payload and payload.Radius) or 0
	if duration <= 0 or radius <= 0 then
		return
	end

	local shieldState = self.activePhoenixShields[targetPlayer]
	local shieldEndTime = os.clock() + duration
	if shieldState then
		shieldState.EndTime = shieldEndTime
		shieldState.Radius = radius
	else
		self.activePhoenixShields[targetPlayer] = {
			EndTime = shieldEndTime,
			Radius = radius,
		}
	end

	if targetPlayer == self.player then
		self:StartPhoenixShieldAnimationLock(payload)
	end

	self:EnsurePhoenixShieldHazardSuppressionLoop()
end

function ToriClient:HandleInputBegan(input, gameProcessed)
	if gameProcessed then
		return false
	end

	if input and input.KeyCode == self:GetPhoenixFlightKeyCode() and self:IsPhoenixFlightActive() then
		self:StopPhoenixFlight()
		return true
	end

	return self:SetFlightInputKeyState(input and input.KeyCode, true)
end

function ToriClient:HandleInputEnded(input)
	return self:SetFlightInputKeyState(input and input.KeyCode, false)
end

function ToriClient:BuildRequestPayload(_abilityName, _abilityConfig, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function ToriClient:BeginPredictedRequest(_abilityName, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function ToriClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName == self.phoenixFlightAbility then
		if self.clientEffectVisuals and typeof(self.clientEffectVisuals.CreatePhoenixFlightEffect) == "function" then
			self.clientEffectVisuals:CreatePhoenixFlightEffect(
				targetPlayer,
				self.phoenixFruitName,
				abilityName,
				payload or {}
			)
		end
		if targetPlayer == self.player then
			self:StartPhoenixFlight(payload or {})
		end
		return true
	end

	if abilityName == self.phoenixShieldAbility then
		if self.clientEffectVisuals and typeof(self.clientEffectVisuals.CreatePhoenixShieldEffect) == "function" then
			self.clientEffectVisuals:CreatePhoenixShieldEffect(
				targetPlayer,
				self.phoenixFruitName,
				abilityName,
				payload or {}
			)
		end
		self:StartPhoenixShield(targetPlayer, payload or {})
		return true
	end

	if abilityName == self.phoenixRebirthAbility then
		return self:PlayPhoenixRebirthVisual(targetPlayer, payload or {})
	end

	return false
end

function ToriClient:HandleStateEvent()
	return false
end

function ToriClient:HandleEquipped()
	return false
end

function ToriClient:HandleUnequipped()
	self:HandleCharacterRemoving()
	return false
end

function ToriClient:Update(dt)
	self:UpdatePhoenixFlight(dt or 0)
end

function ToriClient:HandleCharacterRemoving()
	if self.phoenixShieldAnimationLock then
		self:ReleasePhoenixShieldAnimationLock(self.phoenixShieldAnimationLock)
	end
	self:StopPhoenixFlight()
	self.phoenixRebirthVisualTimes = setmetatable({}, { __mode = "k" })
	self.flightInputState.Forward = false
	self.flightInputState.Backward = false
	self.flightInputState.Left = false
	self.flightInputState.Right = false
	self.hazardSuppressionLoopRunning = false
	self:RestoreSuppressedHazardParts(math.huge)
end

function ToriClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer == self.player then
		self:HandleCharacterRemoving()
	end

	self.activePhoenixShields[leavingPlayer] = nil
end

return ToriClient
