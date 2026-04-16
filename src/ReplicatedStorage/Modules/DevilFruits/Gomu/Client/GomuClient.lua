local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local SharedFolder = DevilFruits:WaitForChild("Shared")
local Registry = require(SharedFolder:WaitForChild("Registry"))

local GomuClient = {}
GomuClient.__index = GomuClient

local GOMU_AIM_RAY_DISTANCE = 500
local GOMU_HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 176, 120)
local GOMU_HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 243, 231)
local GOMU_AUTO_LATCH_MAX_ALIGNMENT = math.cos(math.rad(18))
local GOMU_AUTO_LATCH_BASE_RADIUS = 4
local GOMU_AUTO_LATCH_RADIUS_FACTOR = 0.14
local GOMU_LAUNCH_FX_NAME = "FX"
local GOMU_LAUNCH_VFX_DEFAULT_DURATION = 0.35
local GOMU_LAUNCH_VFX_AIRBORNE_START_GRACE = 0.65
local GOMU_LAUNCH_VFX_GROUND_CONFIRM_TIME = 0.08
local GOMU_LAUNCH_VFX_CLEANUP_GRACE = 0.35
local GOMU_LAUNCH_VFX_MAX_DURATION = 6
local GOMU_LAUNCH_FX_PART_FALLBACK_SIZE = Vector3.new(5, 5, 5)
local GOMU_DEFAULT_SPEED_SCALE_REFERENCE = 70
local MIN_DIRECTION_MAGNITUDE = 0.01

local AIRBORNE_HUMANOID_STATES = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Flying] = true,
	[Enum.HumanoidStateType.Jumping] = true,
}

local function getCurrentCamera()
	return Workspace.CurrentCamera
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
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

local function getPlayerHumanoid(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getPlanarDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function getPlanarSpeed(rootPart)
	if not rootPart then
		return 0
	end

	return getPlanarVector(rootPart.AssemblyLinearVelocity).Magnitude
end

local function getSpeedScaledLaunchDistance(abilityConfig, rootPart)
	local baseDistance = math.max(0, tonumber(abilityConfig and abilityConfig.LaunchDistance) or 0)
	local speedDistanceBonus = math.max(0, tonumber(abilityConfig and abilityConfig.SpeedLaunchDistanceBonus) or 0)
	if speedDistanceBonus <= 0 then
		return baseDistance
	end

	local referenceSpeed = math.max(
		1,
		tonumber(abilityConfig and abilityConfig.SpeedScaleReference) or GOMU_DEFAULT_SPEED_SCALE_REFERENCE
	)
	local speedAlpha = math.clamp(getPlanarSpeed(rootPart) / referenceSpeed, 0, 1)
	return baseDistance + (speedDistanceBonus * speedAlpha)
end

local function getRubberLaunchFxAsset()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local vfxFolder = assetsFolder and assetsFolder:FindFirstChild("VFX")
	local gomuFolder = vfxFolder and vfxFolder:FindFirstChild("Gomu")
	return gomuFolder and gomuFolder:FindFirstChild(GOMU_LAUNCH_FX_NAME) or nil
end

local function getLaunchVfxDuration(payload)
	local duration = typeof(payload) == "table" and tonumber(payload.Duration) or nil
	if not duration then
		local abilityConfig = DevilFruitConfig.GetAbility("Gomu Gomu no Mi", "RubberLaunch")
		duration = abilityConfig and tonumber(abilityConfig.LaunchDuration) or nil
	end

	return math.clamp(duration or GOMU_LAUNCH_VFX_DEFAULT_DURATION, 0.05, 3)
end

local function isHumanoidAirborne(humanoid)
	if typeof(humanoid) ~= "Instance" or not humanoid:IsA("Humanoid") or humanoid.Health <= 0 then
		return false
	end

	if AIRBORNE_HUMANOID_STATES[humanoid:GetState()] then
		return true
	end

	return humanoid.FloorMaterial == Enum.Material.Air
end

local function getMaxParticleLifetime(container)
	local maxLifetime = 0
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			maxLifetime = math.max(maxLifetime, descendant.Lifetime.Max)
		end
	end

	return maxLifetime
end

local function getRotationOnly(cframe)
	return cframe - cframe.Position
end

local function configureLaunchFxPart(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

local function configureLaunchFxParts(container)
	if container:IsA("BasePart") then
		configureLaunchFxPart(container)
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			configureLaunchFxPart(descendant)
		end
	end
end

local function weldLaunchPartToRoot(part, rootPart)
	part.CFrame = rootPart.CFrame * getRotationOnly(part.CFrame)
	part.Parent = rootPart.Parent or Workspace

	local weld = Instance.new("WeldConstraint")
	weld.Name = "GomuLaunchFxWeld"
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part
end

local function createLaunchFxPartFromChildren(sourceFx, rootPart)
	local part = Instance.new("Part")
	part.Name = "GomuRubberLaunchFX"
	part.Size = GOMU_LAUNCH_FX_PART_FALLBACK_SIZE
	part.Transparency = 1
	configureLaunchFxPart(part)

	if sourceFx:IsA("ParticleEmitter") or sourceFx:IsA("Beam") or sourceFx:IsA("Trail") then
		sourceFx:Clone().Parent = part
	else
		for _, child in ipairs(sourceFx:GetChildren()) do
			child:Clone().Parent = part
		end
	end

	part.CFrame = rootPart.CFrame
	part.Parent = rootPart.Parent or Workspace

	local weld = Instance.new("WeldConstraint")
	weld.Name = "GomuLaunchFxWeld"
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = part

	return part
end

local function cloneLaunchFxToRoot(sourceFx, rootPart)
	if sourceFx:IsA("BasePart") then
		local part = sourceFx:Clone()
		part.Name = "GomuRubberLaunchFX"
		configureLaunchFxParts(part)
		weldLaunchPartToRoot(part, rootPart)
		return part
	end

	local attachment
	if sourceFx:IsA("Attachment") then
		attachment = sourceFx:Clone()
		attachment.Name = "GomuRubberLaunchFX"
	else
		return createLaunchFxPartFromChildren(sourceFx, rootPart)
	end

	attachment.Parent = rootPart
	return attachment
end

local function setLaunchFxEnabled(container, enabled)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") or descendant:IsA("Beam") or descendant:IsA("Trail") then
			descendant.Enabled = enabled
		end
	end
end

local function activateLaunchFx(container)
	local activated = false

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") then
			activated = true
			descendant.Enabled = false

			local emitDelay = math.max(0, tonumber(descendant:GetAttribute("EmitDelay")) or 0)
			local emitCount = tonumber(descendant:GetAttribute("EmitCount"))

			task.delay(emitDelay, function()
				if not descendant.Parent then
					return
				end

				if emitCount and emitCount > 0 then
					pcall(function()
						descendant:Emit(emitCount)
					end)
				end

				descendant.Enabled = true
			end)
		elseif descendant:IsA("Beam") or descendant:IsA("Trail") then
			activated = true
			descendant.Enabled = true
		end
	end

	return activated
end

local function cleanupLaunchVfxState(state, destroyDelay)
	if type(state) ~= "table" then
		return
	end

	if state.Connection then
		state.Connection:Disconnect()
		state.Connection = nil
	end

	local container = state.Container
	if not container or not container.Parent then
		return
	end

	destroyDelay = math.max(0, tonumber(destroyDelay) or 0)
	if destroyDelay > 0 then
		setLaunchFxEnabled(container, false)
		task.delay(destroyDelay, function()
			if container.Parent then
				container:Destroy()
			end
		end)
		return
	end

	if state.Container and state.Container.Parent then
		state.Container:Destroy()
	end
end

local function clearLaunchVfxForPlayer(self, targetPlayer)
	if not self.activeLaunchVfxByPlayer then
		return
	end

	local state = self.activeLaunchVfxByPlayer[targetPlayer]
	if not state then
		return
	end

	self.activeLaunchVfxByPlayer[targetPlayer] = nil
	cleanupLaunchVfxState(state)
end

local function playRubberLaunchVfx(self, targetPlayer, payload)
	local rootPart = getPlayerRootPart(targetPlayer)
	if not rootPart then
		return false
	end

	local humanoid = getPlayerHumanoid(targetPlayer)
	if not humanoid then
		return false
	end

	local sourceFx = getRubberLaunchFxAsset()
	if not sourceFx then
		return false
	end

	clearLaunchVfxForPlayer(self, targetPlayer)

	local duration = getLaunchVfxDuration(payload)
	local container = cloneLaunchFxToRoot(sourceFx, rootPart)

	local startedAt = os.clock()
	local state = {
		Container = container,
		Humanoid = humanoid,
		StartedAt = startedAt,
		LastAirborneAt = startedAt,
		SeenAirborne = false,
	}

	local fadeCleanupDelay = getMaxParticleLifetime(container) + GOMU_LAUNCH_VFX_CLEANUP_GRACE
	local function finish(destroyDelay)
		if self.activeLaunchVfxByPlayer[targetPlayer] == state then
			self.activeLaunchVfxByPlayer[targetPlayer] = nil
		end

		cleanupLaunchVfxState(state, destroyDelay)
	end

	state.Connection = RunService.Heartbeat:Connect(function()
		if not container.Parent or not rootPart.Parent then
			finish()
			return
		end

		local now = os.clock()
		local airborne = isHumanoidAirborne(humanoid)
		if airborne then
			state.SeenAirborne = true
			state.LastAirborneAt = now
		elseif state.SeenAirborne and (now - state.LastAirborneAt) >= GOMU_LAUNCH_VFX_GROUND_CONFIRM_TIME then
			finish(fadeCleanupDelay)
		elseif not state.SeenAirborne and (now - startedAt) >= math.max(GOMU_LAUNCH_VFX_AIRBORNE_START_GRACE, duration) then
			finish(fadeCleanupDelay)
		elseif (now - startedAt) >= GOMU_LAUNCH_VFX_MAX_DURATION then
			finish(fadeCleanupDelay)
		end
	end)

	local activated = activateLaunchFx(container)
	if not activated then
		cleanupLaunchVfxState(state)
		return false
	end

	self.activeLaunchVfxByPlayer[targetPlayer] = state

	task.delay(GOMU_LAUNCH_VFX_MAX_DURATION + fadeCleanupDelay, function()
		if self.activeLaunchVfxByPlayer[targetPlayer] == state then
			self.activeLaunchVfxByPlayer[targetPlayer] = nil
			cleanupLaunchVfxState(state)
		end
	end)

	return true
end

local function getPlayerFromDescendant(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local targetPlayer = Players:GetPlayerFromCharacter(current)
			if targetPlayer then
				return targetPlayer
			end
		end

		current = current.Parent
	end

	return nil
end

local function getEquippedFruit(player)
	local fruitFolder = player:FindFirstChild("DevilFruit")
	if fruitFolder then
		local equipped = fruitFolder:FindFirstChild("Equipped")
		if equipped and equipped:IsA("StringValue") then
			if equipped.Value == DevilFruitConfig.None or equipped.Value == "None" then
				return DevilFruitConfig.None
			end

			return Registry.ResolveFruitName(equipped.Value) or equipped.Value
		end
	end

	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		if fruitAttribute == DevilFruitConfig.None or fruitAttribute == "None" then
			return DevilFruitConfig.None
		end

		return Registry.ResolveFruitName(fruitAttribute) or fruitAttribute
	end

	return DevilFruitConfig.None
end

local function ensureGomuHighlight(self)
	local highlight = self.highlight
	if highlight and highlight.Parent then
		return highlight
	end

	highlight = Instance.new("Highlight")
	highlight.Name = "GomuAimHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = GOMU_HIGHLIGHT_FILL_COLOR
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = GOMU_HIGHLIGHT_OUTLINE_COLOR
	highlight.OutlineTransparency = 0.05
	highlight.Enabled = false
	highlight.Parent = Workspace

	self.highlight = highlight
	return highlight
end

local function clearGomuHighlight(self)
	local highlight = self.highlight
	if highlight then
		highlight.Enabled = false
		highlight.Adornee = nil
	end

	self.targetPlayer = nil
end

local function getLookAimRay()
	local camera = getCurrentCamera()
	if not camera then
		return nil
	end

	local viewportSize = camera.ViewportSize
	return camera:ViewportPointToRay(viewportSize.X * 0.5, viewportSize.Y * 0.5)
end

local function getLookAimRaycast(player)
	local unitRay = getLookAimRay()
	if not unitRay then
		return nil, nil, nil, nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}
	params.IgnoreWater = true

	local rayVector = unitRay.Direction * GOMU_AIM_RAY_DISTANCE
	local result = Workspace:Raycast(unitRay.Origin, rayVector, params)
	return result, (result and result.Position) or (unitRay.Origin + rayVector), unitRay.Origin, unitRay.Direction.Unit
end

local function getDistanceFromRay(rayOrigin, rayDirection, point)
	local toPoint = point - rayOrigin
	local projectedDistance = math.max(0, toPoint:Dot(rayDirection))
	local closestPoint = rayOrigin + (rayDirection * projectedDistance)
	return (point - closestPoint).Magnitude, projectedDistance
end

local function isTargetInRange(self, targetPlayer, maxDistance)
	local localRootPart = self.getLocalRootPart()
	local targetRootPart = getPlayerRootPart(targetPlayer)
	if not localRootPart or not targetRootPart then
		return false
	end

	return getPlanarDistance(localRootPart.Position, targetRootPart.Position) <= (maxDistance + 0.5)
end

local function findAutoLatchTarget(self, launchDistance, rayOrigin, rayDirection)
	local localRootPart = self.getLocalRootPart()
	if not localRootPart or not rayOrigin or not rayDirection then
		return nil
	end

	local bestTargetPlayer
	local bestScore = -math.huge

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= self.player and isTargetInRange(self, targetPlayer, launchDistance) then
			local targetRootPart = getPlayerRootPart(targetPlayer)
			if targetRootPart then
				local targetPosition = targetRootPart.Position + Vector3.new(0, 1.5, 0)
				local toTarget = targetPosition - rayOrigin
				local toTargetUnit = toTarget.Magnitude > 0.01 and toTarget.Unit or nil
				local alignment = toTargetUnit and rayDirection:Dot(toTargetUnit) or -1
				if alignment >= GOMU_AUTO_LATCH_MAX_ALIGNMENT then
					local lateralDistance, projectedDistance = getDistanceFromRay(rayOrigin, rayDirection, targetPosition)
					local allowedRadius = math.max(GOMU_AUTO_LATCH_BASE_RADIUS, projectedDistance * GOMU_AUTO_LATCH_RADIUS_FACTOR)
					if lateralDistance <= allowedRadius then
						local planarDistance = getPlanarDistance(localRootPart.Position, targetRootPart.Position)
						local score = (alignment * 100) - (lateralDistance * 2) - (planarDistance * 0.1)
						if score > bestScore then
							bestScore = score
							bestTargetPlayer = targetPlayer
						end
					end
				end
			end
		end
	end

	return bestTargetPlayer
end

local function getGomuLaunchTarget(self, abilityConfig)
	local result, fallbackPosition, rayOrigin, rayDirection = getLookAimRaycast(self.player)
	local aimPosition = fallbackPosition
	local launchDistance = getSpeedScaledLaunchDistance(abilityConfig, self.getLocalRootPart())
	local targetPlayer = findAutoLatchTarget(self, launchDistance, rayOrigin, rayDirection)

	if not targetPlayer and result then
		targetPlayer = getPlayerFromDescendant(result.Instance)
		if targetPlayer == self.player or not isTargetInRange(self, targetPlayer, launchDistance) then
			targetPlayer = nil
		end
	end

	if targetPlayer then
		local targetRootPart = getPlayerRootPart(targetPlayer)
		if targetRootPart then
			aimPosition = targetRootPart.Position
		end
	end

	if not aimPosition then
		local rootPart = self.getLocalRootPart()
		if rootPart then
			local fallbackDirection = rayDirection or rootPart.CFrame.LookVector
			aimPosition = rootPart.Position + (fallbackDirection * GOMU_AIM_RAY_DISTANCE)
		end
	end

	return aimPosition, targetPlayer
end

function GomuClient.Create(config)
	config = config or {}
	local self = setmetatable({}, GomuClient)
	self.player = config.player or Players.LocalPlayer
	self.getLocalRootPart = type(config.GetLocalRootPart) == "function" and config.GetLocalRootPart or function()
		local character = self.player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end
	self.getEquippedFruit = type(config.GetEquippedFruit) == "function" and config.GetEquippedFruit or function()
		return getEquippedFruit(self.player)
	end
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or function() end
	self.highlight = nil
	self.targetPlayer = nil
	self.activeLaunchVfxByPlayer = {}
	return self
end

function GomuClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName ~= "RubberLaunch" then
		if typeof(fallbackBuilder) == "function" then
			return fallbackBuilder()
		end

		return nil
	end

	local abilityConfig = DevilFruitConfig.GetAbility("Gomu Gomu no Mi", "RubberLaunch")
	local aimPosition, targetPlayer = getGomuLaunchTarget(self, abilityConfig)
	return {
		AimPosition = aimPosition,
		TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
	}
end

function GomuClient:BuildRequestPayload(abilityName, abilityEntry, fallbackBuilder)
	if abilityName == "RubberLaunch" then
		return self:BeginPredictedRequest(abilityName)
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function GomuClient:Update()
	local fruitName = self.getEquippedFruit()
	if fruitName ~= "Gomu Gomu no Mi" then
		clearGomuHighlight(self)
		return
	end

	local abilityConfig = DevilFruitConfig.GetAbility(fruitName, "RubberLaunch")
	if not abilityConfig then
		clearGomuHighlight(self)
		return
	end

	local _, targetPlayer = getGomuLaunchTarget(self, abilityConfig)
	if not targetPlayer or not targetPlayer.Character then
		clearGomuHighlight(self)
		return
	end

	local highlight = ensureGomuHighlight(self)
	highlight.Adornee = targetPlayer.Character
	highlight.Enabled = true
	self.targetPlayer = targetPlayer
end

function GomuClient:HandleEffect(targetPlayer, abilityName, payload)
	if abilityName ~= "RubberLaunch" then
		return false
	end

	return playRubberLaunchVfx(self, targetPlayer, payload)
end

function GomuClient:HandleStateEvent()
	return false
end

function GomuClient:HandleEquipped()
	return false
end

function GomuClient:HandleUnequipped()
	clearGomuHighlight(self)
	return false
end

function GomuClient:HandleCharacterRemoving()
	clearGomuHighlight(self)
	clearLaunchVfxForPlayer(self, self.player)
end

function GomuClient:HandlePlayerRemoving(leavingPlayer)
	clearLaunchVfxForPlayer(self, leavingPlayer)
	return
end

return GomuClient
