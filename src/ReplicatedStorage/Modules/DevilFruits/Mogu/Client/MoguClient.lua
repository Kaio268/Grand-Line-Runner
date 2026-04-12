local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local MoguAnimationController = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Client"):WaitForChild("MoguAnimationController")
)
local MoguVfxController = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Client"):WaitForChild("MoguVfxController")
)
local MoguBurrowShared = require(
	Modules:WaitForChild("DevilFruits"):WaitForChild("Mogu"):WaitForChild("Shared"):WaitForChild("MoguBurrowShared")
)

local MoguClient = {}
MoguClient.__index = MoguClient

local FRUIT_NAME = "Mogu Mogu no Mi"
local ABILITY_NAME = "Burrow"
local MIN_DIRECTION_MAGNITUDE = 0.01
local DEFAULT_DIRECTION = Vector3.new(0, 0, -1)
local TRAIL_COLOR = Color3.fromRGB(122, 95, 63)
local TRAIL_ACCENT_COLOR = Color3.fromRGB(166, 136, 97)
local BURST_COLOR = Color3.fromRGB(214, 194, 159)
local FLAT_RING_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local function getAbilityConfig()
	return DevilFruitConfig.GetAbility(FRUIT_NAME, ABILITY_NAME) or {}
end

local function getAnimationStageConfig(stageKey, abilityConfig)
	local animationConfig = type(abilityConfig) == "table" and abilityConfig.Animation or nil
	return type(animationConfig) == "table" and animationConfig[stageKey] or {}
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getPerpendicularPlanarRightVector(forwardVector)
	return Vector3.new(-forwardVector.Z, 0, forwardVector.X)
end

local function resolvePlanarDirection(direction, fallback)
	local planarDirection = typeof(direction) == "Vector3" and getPlanarVector(direction) or nil
	if planarDirection and planarDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarDirection.Unit
	end

	local planarFallback = typeof(fallback) == "Vector3" and getPlanarVector(fallback) or nil
	if planarFallback and planarFallback.Magnitude > MIN_DIRECTION_MAGNITUDE then
		return planarFallback.Unit
	end

	return DEFAULT_DIRECTION
end

local function getCharacter(player)
	return player and player.Character or nil
end

local function getHumanoid(player)
	local character = getCharacter(player)
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRootPart(player)
	local character = getCharacter(player)
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getGroundEffectPosition(position)
	if typeof(position) ~= "Vector3" then
		return nil
	end

	return position - Vector3.new(0, math.max(1.5, tonumber(getAbilityConfig().RootGroundClearance) or 3.2) - 0.15, 0)
end

local function tweenAndDestroy(instance, duration, tweenGoals)
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		tweenGoals
	)
	tween:Play()
	tween.Completed:Connect(function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

local function createEffectPart(name, size, color, cframe, material, transparency, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = material or Enum.Material.Ground
	part.Transparency = transparency or 0
	part.Color = color
	part.Size = size
	part.CFrame = cframe
	part.Shape = shape or Enum.PartType.Block
	part.Parent = Workspace
	return part
end

local function createBurst(position, radius, isResolve)
	local groundPosition = getGroundEffectPosition(position)
	if not groundPosition then
		return
	end

	local burstRadius = math.max(1, tonumber(radius) or 3)
	local ring = createEffectPart(
		isResolve and "MoguResolveRing" or "MoguEntryRing",
		Vector3.new(0.16, burstRadius * 1.5, burstRadius * 1.5),
		TRAIL_ACCENT_COLOR,
		CFrame.new(groundPosition) * FLAT_RING_ROTATION,
		Enum.Material.SmoothPlastic,
		0.18,
		Enum.PartType.Cylinder
	)
	tweenAndDestroy(ring, isResolve and 0.28 or 0.22, {
		Transparency = 1,
		Size = Vector3.new(0.16, burstRadius * 2.35, burstRadius * 2.35),
	})

	local pulse = createEffectPart(
		isResolve and "MoguResolveBurst" or "MoguEntryBurst",
		Vector3.new(burstRadius, burstRadius * 0.65, burstRadius),
		isResolve and BURST_COLOR or TRAIL_COLOR,
		CFrame.new(groundPosition + Vector3.new(0, burstRadius * 0.08, 0)),
		Enum.Material.Ground,
		0.12,
		Enum.PartType.Ball
	)
	tweenAndDestroy(pulse, isResolve and 0.24 or 0.2, {
		Transparency = 1,
		Size = pulse.Size * 1.7,
	})
end

local function createTrailPulse(position, radius)
	local groundPosition = getGroundEffectPosition(position)
	if not groundPosition then
		return
	end

	local pulseRadius = math.max(0.7, tonumber(radius) or 1.3)
	local pulse = createEffectPart(
		"MoguBurrowPulse",
		Vector3.new(pulseRadius, pulseRadius * 0.42, pulseRadius),
		TRAIL_COLOR,
		CFrame.new(groundPosition + Vector3.new(0, pulseRadius * 0.04, 0)),
		Enum.Material.Ground,
		0.26,
		Enum.PartType.Ball
	)
	tweenAndDestroy(pulse, 0.18, {
		Transparency = 1,
		Size = pulse.Size * 1.35,
	})

	local accent = createEffectPart(
		"MoguBurrowPulseAccent",
		Vector3.new(0.12, pulseRadius * 1.15, pulseRadius * 1.15),
		TRAIL_ACCENT_COLOR,
		CFrame.new(groundPosition) * FLAT_RING_ROTATION,
		Enum.Material.SmoothPlastic,
		0.36,
		Enum.PartType.Cylinder
	)
	tweenAndDestroy(accent, 0.16, {
		Transparency = 1,
		Size = Vector3.new(0.12, pulseRadius * 1.65, pulseRadius * 1.65),
	})
end

local function pivotCharacterToRootPosition(character, rootPart, targetRootPosition, direction)
	if not character or not rootPart or typeof(targetRootPosition) ~= "Vector3" then
		return
	end

	local facingDirection = resolvePlanarDirection(direction, rootPart.CFrame.LookVector)
	local targetRootCFrame = CFrame.lookAt(targetRootPosition, targetRootPosition + facingDirection, Vector3.yAxis)
	local pivotToRoot = character:GetPivot():ToObjectSpace(rootPart.CFrame)
	character:PivotTo(targetRootCFrame * pivotToRoot:Inverse())
end

function MoguClient.Create(config)
	config = config or {}

	local self = setmetatable({}, MoguClient)
	self.player = config.player or Players.LocalPlayer
	self.getCurrentCamera = type(config.GetCurrentCamera) == "function" and config.GetCurrentCamera or function()
		return Workspace.CurrentCamera
	end
	self.getHumanoid = type(config.GetHumanoid) == "function" and config.GetHumanoid or function()
		return getHumanoid(self.player)
	end
	self.getLocalRootPart = type(config.GetLocalRootPart) == "function" and config.GetLocalRootPart or function()
		return getRootPart(self.player)
	end
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or function() end
	self.requestAbility = type(config.RequestAbility) == "function" and config.RequestAbility or nil
	self.animationController = MoguAnimationController.new()
	self.vfxController = MoguVfxController.new()
	self.burrowInputState = {
		Forward = false,
		Backward = false,
		Left = false,
		Right = false,
	}
	self.burrowStates = {}
	self.concealStates = {}
	return self
end

function MoguClient:SetBurrowInputKeyState(keyCode, isPressed)
	if keyCode == Enum.KeyCode.W or keyCode == Enum.KeyCode.Up then
		self.burrowInputState.Forward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.S or keyCode == Enum.KeyCode.Down then
		self.burrowInputState.Backward = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.A or keyCode == Enum.KeyCode.Left then
		self.burrowInputState.Left = isPressed
		return true
	end

	if keyCode == Enum.KeyCode.D or keyCode == Enum.KeyCode.Right then
		self.burrowInputState.Right = isPressed
		return true
	end

	return false
end

function MoguClient:GetBurrowInputAxes()
	local forwardAxis = 0
	local rightAxis = 0

	if self.burrowInputState.Forward then
		forwardAxis += 1
	end
	if self.burrowInputState.Backward then
		forwardAxis -= 1
	end
	if self.burrowInputState.Right then
		rightAxis += 1
	end
	if self.burrowInputState.Left then
		rightAxis -= 1
	end

	return forwardAxis, rightAxis
end

function MoguClient:GetCameraRelativeBurrowDirection(rootPart)
	local forwardAxis, rightAxis = self:GetBurrowInputAxes()
	if forwardAxis == 0 and rightAxis == 0 then
		return Vector3.zero
	end

	local camera = self.getCurrentCamera()
	local forwardVector = resolvePlanarDirection(
		camera and camera.CFrame.LookVector or (rootPart and rootPart.CFrame.LookVector),
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

function MoguClient:ApplyConceal(targetPlayer, transparency)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	self:ClearConceal(targetPlayer)

	local character = getCharacter(targetPlayer)
	if not character then
		return
	end

	local previousByPart = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= "HumanoidRootPart" then
			previousByPart[descendant] = descendant.LocalTransparencyModifier
			descendant.LocalTransparencyModifier = math.max(descendant.LocalTransparencyModifier, transparency)
		end
	end

	self.concealStates[targetPlayer] = {
		PreviousByPart = previousByPart,
	}
end

function MoguClient:ApplyConcealWhenReady(targetPlayer, burrowState)
	if not targetPlayer or not burrowState then
		return
	end

	local concealDelay = math.max(
		0,
		tonumber(burrowState.ConcealDelay) or tonumber(getAnimationStageConfig("Start", getAbilityConfig()).ConcealDelay) or 0
	)
	if concealDelay <= 0 then
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		burrowState.ConcealApplied = true
		return
	end

	local concealToken = {}
	burrowState.PendingConcealToken = concealToken
	task.delay(math.min(concealDelay, burrowState.Duration), function()
		local activeBurrowState = self.burrowStates[targetPlayer]
		if activeBurrowState ~= burrowState or activeBurrowState.PendingConcealToken ~= concealToken then
			return
		end

		activeBurrowState.PendingConcealToken = nil
		self:ApplyConceal(targetPlayer, burrowState.ConcealTransparency)
		activeBurrowState.ConcealApplied = true
	end)
end

function MoguClient:ClearConceal(targetPlayer)
	local concealState = self.concealStates[targetPlayer]
	if not concealState then
		return
	end

	self.concealStates[targetPlayer] = nil
	for part, previousTransparency in pairs(concealState.PreviousByPart) do
		if part and part.Parent then
			part.LocalTransparencyModifier = previousTransparency
		end
	end
end

function MoguClient:GetLocalBurrowState()
	return self.burrowStates[self.player]
end

function MoguClient:RequestSurface(reason)
	local burrowState = self:GetLocalBurrowState()
	if not burrowState or burrowState.SurfaceRequested or typeof(self.requestAbility) ~= "function" then
		return false
	end

	burrowState.SurfaceRequested = true
	self.requestAbility(ABILITY_NAME, nil)
	return true
end

function MoguClient:StartBurrow(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	local abilityConfig = getAbilityConfig()
	local duration = math.max(0.5, tonumber(payload.Duration) or MoguBurrowShared.GetBurrowDuration(abilityConfig))
	local startedAt = tonumber(payload.StartedAt) or Workspace:GetServerTimeNow()
	local burrowState = {
		StartedAt = startedAt,
		EndTime = tonumber(payload.EndTime) or (startedAt + duration),
		Duration = duration,
		MoveSpeed = math.max(0, tonumber(payload.MoveSpeed) or MoguBurrowShared.GetMoveSpeed(abilityConfig)),
		TrailInterval = math.max(0.05, tonumber(payload.TrailInterval) or MoguBurrowShared.GetTrailInterval(abilityConfig)),
		LastTrailAt = 0,
		Direction = resolvePlanarDirection(payload.Direction, getRootPart(targetPlayer) and getRootPart(targetPlayer).CFrame.LookVector or nil),
		SurfaceRequested = false,
		EntryBurstRadius = math.max(0.5, tonumber(payload.EntryBurstRadius) or MoguBurrowShared.GetEntryBurstRadius(abilityConfig)),
		ResolveBurstRadius = math.max(0.5, tonumber(payload.ResolveBurstRadius) or MoguBurrowShared.GetResolveBurstRadius(abilityConfig)),
		ConcealTransparency = math.clamp(
			tonumber(payload.ConcealTransparency) or MoguBurrowShared.GetConcealTransparency(abilityConfig),
			0,
			1
		),
		ConcealDelay = math.max(0, tonumber(getAnimationStageConfig("Start", abilityConfig).ConcealDelay) or 0),
		IsLocal = targetPlayer == self.player,
	}

	if burrowState.IsLocal then
		local humanoid = self.getHumanoid()
		if humanoid then
			burrowState.OriginalAutoRotate = humanoid.AutoRotate
			burrowState.OriginalWalkSpeed = humanoid.WalkSpeed
			humanoid.AutoRotate = false
			humanoid.WalkSpeed = 0
		end
	end

	self.burrowStates[targetPlayer] = burrowState
	burrowState.AnimationState = self.animationController:PlayStart(targetPlayer, abilityConfig)
	self:ApplyConcealWhenReady(targetPlayer, burrowState)

	local startPosition = payload.StartPosition or (getRootPart(targetPlayer) and getRootPart(targetPlayer).Position)
	if not self.vfxController:PlayEntry(startPosition, burrowState.Direction, abilityConfig) then
		createBurst(startPosition, burrowState.EntryBurstRadius, false)
	end
end

function MoguClient:StopBurrow(targetPlayer, payload)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return
	end

	local burrowState = self.burrowStates[targetPlayer]
	local abilityConfig = getAbilityConfig()
	self.burrowStates[targetPlayer] = nil
	self.animationController:StopAnimation(burrowState and burrowState.AnimationState, "resolve_transition")
	self.animationController:PlayResolve(targetPlayer, abilityConfig)

	if targetPlayer == self.player then
		local humanoid = self.getHumanoid()
		if humanoid and burrowState then
			humanoid.AutoRotate = burrowState.OriginalAutoRotate ~= false
			humanoid.WalkSpeed = burrowState.OriginalWalkSpeed or humanoid.WalkSpeed
		end

		local character = getCharacter(self.player)
		local rootPart = self.getLocalRootPart()
		if character and rootPart then
			local surfacePosition = typeof(payload.ActualEndPosition) == "Vector3" and payload.ActualEndPosition or rootPart.Position
			local resolvedSurfacePosition = select(
				1,
				MoguBurrowShared.ResolveSurfaceRootPosition(character, rootPart, surfacePosition, abilityConfig)
			)
			pivotCharacterToRootPosition(
				character,
				rootPart,
				resolvedSurfacePosition,
				burrowState and burrowState.Direction or payload.Direction
			)
			rootPart.AssemblyLinearVelocity = Vector3.zero
		end
	end

	self:ClearConceal(targetPlayer)

	local resolvePosition = typeof(payload.ActualEndPosition) == "Vector3"
			and payload.ActualEndPosition
		or (getRootPart(targetPlayer) and getRootPart(targetPlayer).Position)
	local resolveDirection = (burrowState and burrowState.Direction) or payload.Direction
	if not self.vfxController:PlayResolve(resolvePosition, resolveDirection, abilityConfig) then
		createBurst(
			resolvePosition,
			(burrowState and burrowState.ResolveBurstRadius) or payload.ResolveBurstRadius or MoguBurrowShared.GetResolveBurstRadius(abilityConfig),
			true
		)
	end
end

function MoguClient:HandleInputBegan(input, gameProcessed)
	local burrowState = self:GetLocalBurrowState()
	if burrowState and input and input.KeyCode == Enum.KeyCode.Q and not gameProcessed then
		self:RequestSurface("manual_toggle")
		return true
	end

	return self:SetBurrowInputKeyState(input and input.KeyCode, true)
end

function MoguClient:HandleInputEnded(input)
	return self:SetBurrowInputKeyState(input and input.KeyCode, false)
end

function MoguClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName ~= ABILITY_NAME then
		if typeof(fallbackBuilder) == "function" then
			return fallbackBuilder()
		end
		return nil
	end

	local rootPart = self.getLocalRootPart()
	if not rootPart then
		return nil
	end

	local burrowState = self:GetLocalBurrowState()
	if burrowState then
		return nil
	end

	local direction = self:GetCameraRelativeBurrowDirection(rootPart)
	if direction.Magnitude <= MIN_DIRECTION_MAGNITUDE then
		direction = resolvePlanarDirection(rootPart.CFrame.LookVector, nil)
	end

	return {
		Direction = direction,
	}
end

function MoguClient:BuildRequestPayload(abilityName, abilityEntry, fallbackBuilder)
	if abilityName == ABILITY_NAME then
		return self:BeginPredictedRequest(abilityName)
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function MoguClient:UpdateLocalBurrowState(burrowState, dt, now)
	local character = getCharacter(self.player)
	local rootPart = self.getLocalRootPart()
	local humanoid = self.getHumanoid()
	if not character or not rootPart or not humanoid or humanoid.Health <= 0 then
		return
	end

	humanoid.AutoRotate = false
	humanoid.WalkSpeed = 0
	humanoid.Jump = false

	if now >= burrowState.EndTime and not burrowState.SurfaceRequested then
		self:RequestSurface("duration_elapsed")
	end

	if burrowState.SurfaceRequested then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		return
	end

	local desiredDirection = self:GetCameraRelativeBurrowDirection(rootPart)
	local currentSurfacePosition = select(
		1,
		MoguBurrowShared.ResolveSurfaceRootPosition(character, rootPart, rootPart.Position, getAbilityConfig())
	)
	local targetPlanarPosition = currentSurfacePosition
	if desiredDirection.Magnitude > MIN_DIRECTION_MAGNITUDE then
		targetPlanarPosition = currentSurfacePosition + (desiredDirection.Unit * burrowState.MoveSpeed * dt)
		burrowState.Direction = desiredDirection.Unit
	end

	local resolvedSurfacePosition = select(
		1,
		MoguBurrowShared.ResolveSurfaceRootPosition(character, rootPart, targetPlanarPosition, getAbilityConfig())
	)
	pivotCharacterToRootPosition(character, rootPart, resolvedSurfacePosition, burrowState.Direction)
	rootPart.AssemblyLinearVelocity = Vector3.zero
end

function MoguClient:UpdateTrailState(targetPlayer, burrowState, now)
	if not burrowState or now < burrowState.LastTrailAt + burrowState.TrailInterval then
		return
	end

	local rootPart = getRootPart(targetPlayer)
	if not rootPart then
		return
	end

	burrowState.LastTrailAt = now
	if not self.vfxController:PlayTrail(rootPart.Position, burrowState.Direction, getAbilityConfig()) then
		createTrailPulse(rootPart.Position, tonumber(getAbilityConfig().TrailWidth) or 2.6)
	end
end

function MoguClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= ABILITY_NAME then
		return false
	end

	payload = payload or {}
	local phase = typeof(payload.Phase) == "string" and payload.Phase or "Start"
	if phase == "Start" then
		self.playOptionalEffect(targetPlayer, FRUIT_NAME, abilityName)
		self:StartBurrow(targetPlayer, payload)
		return true
	end

	if phase == "Resolve" then
		self.playOptionalEffect(targetPlayer, FRUIT_NAME, abilityName)
		self:StopBurrow(targetPlayer, payload)
		return true
	end

	return false
end

function MoguClient:HandleStateEvent()
	return false
end

function MoguClient:Update(dt)
	local now = Workspace:GetServerTimeNow()
	for targetPlayer, burrowState in pairs(self.burrowStates) do
		if now > (burrowState.EndTime + MoguBurrowShared.GetSurfaceResolveGrace(getAbilityConfig())) and not burrowState.IsLocal then
			self:StopBurrow(targetPlayer, {
				ActualEndPosition = getRootPart(targetPlayer) and getRootPart(targetPlayer).Position or nil,
				ResolveBurstRadius = burrowState.ResolveBurstRadius,
			})
		else
			self:UpdateTrailState(targetPlayer, burrowState, now)
			if burrowState.IsLocal then
				self:UpdateLocalBurrowState(burrowState, dt or 0, now)
			end
		end
	end
end

function MoguClient:HandleEquipped()
	return false
end

function MoguClient:HandleUnequipped()
	self:HandleCharacterRemoving()
	return false
end

function MoguClient:HandleCharacterRemoving()
	local localBurrowState = self.burrowStates[self.player]
	if localBurrowState then
		local humanoid = self.getHumanoid()
		if humanoid then
			humanoid.AutoRotate = localBurrowState.OriginalAutoRotate ~= false
			humanoid.WalkSpeed = localBurrowState.OriginalWalkSpeed or humanoid.WalkSpeed
		end
	end

	for targetPlayer in pairs(self.burrowStates) do
		self.animationController:StopAnimation(self.burrowStates[targetPlayer].AnimationState, "character_removing")
		self.burrowStates[targetPlayer] = nil
		self:ClearConceal(targetPlayer)
	end
	self.vfxController:HandleCharacterRemoving()

	self.burrowInputState.Forward = false
	self.burrowInputState.Backward = false
	self.burrowInputState.Left = false
	self.burrowInputState.Right = false
end

function MoguClient:HandlePlayerRemoving(leavingPlayer)
	self.animationController:StopAnimation(self.burrowStates[leavingPlayer] and self.burrowStates[leavingPlayer].AnimationState, "player_removing")
	self.burrowStates[leavingPlayer] = nil
	self:ClearConceal(leavingPlayer)
	self.vfxController:HandlePlayerRemoving(leavingPlayer)
end

return MoguClient
