local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local ProtectionRuntime = require(DevilFruits:WaitForChild("ProtectionRuntime"))
local ToriShared = require(DevilFruits:WaitForChild("Tori"):WaitForChild("Shared"):WaitForChild("ToriShared"))

local ToriClient = {}
ToriClient.__index = ToriClient

local DEFAULT_PHOENIX_FRUIT_NAME = ToriShared.FruitName
local DEFAULT_PHOENIX_FLIGHT_ABILITY = "PhoenixFlight"
local DEFAULT_PHOENIX_SHIELD_ABILITY = "PhoenixFlameShield"
local PHOENIX_REBIRTH = ToriShared.Passives.PhoenixRebirth
local DEBUG_FLIGHT = true
local MIN_DIRECTION_MAGNITUDE = 0.01
local PHOENIX_SHIELD_PADDING = 2.5
local PHOENIX_HOVER_HEIGHT_TOLERANCE = 0.75
local PHOENIX_HOVER_CORRECTION_GAIN = 4
local FLIGHT_UPDATE_LOG_INTERVAL = 0.25
local FLIGHT_MOVE_LOG_INTERVAL = 0.2
local FLIGHT_CORRECTION_LOG_INTERVAL = 0.2
local FLIGHT_DRIFT_WARN_INTERVAL = 0.5

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
	self.shieldPadding = clampPositiveNumber(config and config.phoenixShieldPadding, PHOENIX_SHIELD_PADDING)
	self.flightInputState = {
		Forward = false,
		Backward = false,
		Left = false,
		Right = false,
	}
	self.activePhoenixShields = {}
	self.phoenixFlightState = {
		Active = false,
		EndTime = 0,
		TakeoffEndTime = 0,
		TakeoffVelocity = 0,
		ActivationHeight = 0,
		InitialLiftTarget = 0,
		MaxHeight = 0,
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

	-- Placeholder hook for future phoenix rebirth animation and VFX.
	print("[ToriClient] Phoenix Rebirth triggered at", formatFlightNumber(triggeredAt))
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
	return self.phoenixFlightState.Active and now < self.phoenixFlightState.EndTime
end

function ToriClient:StopPhoenixFlight()
	if not self.phoenixFlightState.Active then
		return
	end

	local rootPart = getRootPart(self)
	self.phoenixFlightState.Active = false
	self.phoenixFlightState.EndTime = 0
	self.phoenixFlightState.TakeoffEndTime = 0
	self.phoenixFlightState.TakeoffVelocity = 0
	self.phoenixFlightState.ActivationHeight = 0
	self.phoenixFlightState.InitialLiftTarget = 0
	self.phoenixFlightState.MaxHeight = 0
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
end

function ToriClient:StartPhoenixFlight(payload)
	local rootPart = getRootPart(self)
	local humanoid = getHumanoid(self)
	if not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	self:StopPhoenixFlight()

	local duration = math.max(0.1, tonumber(payload and payload.Duration) or 0)
	local takeoffDuration = math.max(0.1, tonumber(payload and payload.TakeoffDuration) or 0.4)
	local initialLift = math.max(0, tonumber(payload and payload.InitialLift) or 10)
	local maxRiseHeight = math.max(initialLift, tonumber(payload and payload.MaxRiseHeight) or initialLift)
	local liftVelocity = getInitialLiftVelocity(initialLift)

	self.phoenixFlightState.Active = true
	self.phoenixFlightState.EndTime = os.clock() + duration
	self.phoenixFlightState.TakeoffEndTime = os.clock() + takeoffDuration
	self.phoenixFlightState.TakeoffVelocity = liftVelocity
	self.phoenixFlightState.ActivationHeight = rootPart.Position.Y
	self.phoenixFlightState.InitialLiftTarget = rootPart.Position.Y + initialLift
	self.phoenixFlightState.MaxHeight = rootPart.Position.Y + maxRiseHeight
	self.phoenixFlightState.FlightSpeed = math.max(0, tonumber(payload and payload.FlightSpeed) or 78)
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
		currentVelocity.X,
		math.max(currentVelocity.Y, liftVelocity),
		currentVelocity.Z
	)

	flightLog(
		"START",
		"Y:",
		formatFlightNumber(rootPart.Position.Y),
		"TargetY:",
		formatFlightNumber(self.phoenixFlightState.MaxHeight),
		"VelY:",
		formatFlightNumber(rootPart.AssemblyLinearVelocity.Y)
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

function ToriClient:FaceCharacterTowards(direction)
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
	local targetCFrame = CFrame.lookAt(rootPosition, rootPosition + planarDirection.Unit, Vector3.yAxis)
	pivotCharacterToRootCFrame(character, rootPart, targetCFrame)
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

	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

	local desiredFlightDirection = self:GetCameraRelativeFlightDirection(rootPart)
	local desiredPlanarVelocity = desiredFlightDirection * self.phoenixFlightState.FlightSpeed
	local currentHeight = rootPart.Position.Y
	local targetVerticalVelocity = self:GetTargetHoverVerticalVelocity(currentHeight, now)

	local currentVelocity = rootPart.AssemblyLinearVelocity
	local response = math.clamp(self.phoenixFlightState.HorizontalResponsiveness * dt, 0, 1)
	local currentPlanarVelocity = getPlanarVector(currentVelocity)
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
			"VelY:",
			formatFlightNumber(verticalVelocity)
		)
	end

	local desiredPlanarDirection = desiredPlanarVelocity
	local nextPlanarDirection = getPlanarVector(nextVelocity)
	if desiredPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE or nextPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		local facingDirection = desiredPlanarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE and desiredPlanarDirection or nextPlanarDirection
		self:FaceCharacterTowards(facingDirection)
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
			if ownerRootPart and getPlanarDistance(ownerRootPart.Position, checkPosition) <= (shield.Radius + self.shieldPadding) then
				return true
			end
		end
	end

	return false
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
		shieldState.EndTime = math.max(shieldState.EndTime, shieldEndTime)
		shieldState.Radius = math.max(shieldState.Radius, radius)
	else
		self.activePhoenixShields[targetPlayer] = {
			EndTime = shieldEndTime,
			Radius = radius,
		}
	end
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

function ToriClient:BuildRequestPayload(abilityName, abilityConfig, fallbackBuilder)
	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function ToriClient:BeginPredictedRequest(abilityName, fallbackBuilder)
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
	self:StopPhoenixFlight()
	self.flightInputState.Forward = false
	self.flightInputState.Backward = false
	self.flightInputState.Left = false
	self.flightInputState.Right = false
end

function ToriClient:HandlePlayerRemoving(leavingPlayer)
	if leavingPlayer == self.player then
		self:HandleCharacterRemoving()
	end

	self.activePhoenixShields[leavingPlayer] = nil
end

return ToriClient
