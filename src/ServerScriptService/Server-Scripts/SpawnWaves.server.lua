local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local function getNamedFolder(parent, childName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName and child:IsA("Folder") then
			return child
		end
	end

	error(string.format("Missing Folder named %s under %s", childName, parent:GetFullName()))
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local StudioAssetResolver = require(Modules:WaitForChild("StudioAssetResolver"))
local WaveHazardVisuals = require(Modules:WaitForChild("WaveHazardVisuals"))
local RuntimeScheduler = require(Modules:WaitForChild("RuntimeScheduler"))
local PerformanceFlags = require(Modules:WaitForChild("Configs"):WaitForChild("PerformanceArchitectureFlags"))
local HazardRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local ServerScriptService = game:GetService("ServerScriptService")
local AffectableRegistry = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))
local HazardProtection = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("HazardProtection")
)
local DamageProtection = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("DamageProtection")
)
local devilFruitModules = ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruits")
local SpiritServer = require(getNamedFolder(devilFruitModules, "Spirit"):WaitForChild("Server"):WaitForChild("SpiritServer"))
local phoenixFolder = getNamedFolder(devilFruitModules, "Phoenix")
local PhoenixServer = require(phoenixFolder:WaitForChild("Server"):WaitForChild("PhoenixServer"))
local PhoenixPassiveService = require(phoenixFolder:WaitForChild("Server"):WaitForChild("PhoenixPassiveService"))

local CONFIG = {
	SpawnDelayMin = 2,
	SpawnDelayMax = 5,
	MaxActiveHazards = 30,
	MinimumForwardSpacing = 80,
	WaveSpeed = 70,
	LateralLaneCount = 3,
	HazardClass = "major",
	FreezeBehavior = "pause",
	-- Used for ability/hazard affectable queries; wave damage ignores this so the kill area matches WaveHitbox.
	AffectablePadding = Vector3.new(2, 1, 4),
	-- Extra damage padding stays at zero: high-speed reliability comes from swept detection, not oversized damage boxes.
	KillValidationPadding = Vector3.zero,
	SweptKillEnabled = true,
	SweptKillPadding = Vector3.zero,
	SweptKillTeleportResetDistance = 512,
	RuntimeWaveName = "WaveTemplate", -- Historical runtime name only; spawning no longer reads this asset.
	-- Scales the canonical ReplicatedStorage.Assets.Hazards.Waves.Regular Wave bounds to gameplay size.
	BaseWaveVisualScale = 35.98836032827221,
	BaseWavePivotOffset = Vector3.zero,
	BaseWaveOrientation = CFrame.Angles(0, math.rad(180), 0),
	-- WaveWidthScale controls left-to-right wave size. Variant WidthScale still applies on top of this.
	WaveWidthScale = 0.65,
	-- WaveHeightScale controls vertical wave size.
	WaveHeightScale = 1,
	-- WaveThicknessScale controls front-to-back wave depth.
	WaveThicknessScale = 1,
	-- Tiny wall contact tolerance. Bounce limits use the actual WaveHitbox edge, not a gameplay safe strip.
	WaveWallContactPadding = 2,
	BounceWallOverlap = 1,
	DiagnosticsInterval = 2,
	Variants = {
		{
			Name = "Normal",
			WidthScale = 1,
			Weight = 75,
		},
		{
			Name = "Wide",
			WidthScale = 1.45,
			Weight = 25,
		},
	},
}

local AIRBORNE_TORI_HAZARD_KNOCKDOWN_DURATION = 1.15
local HAZARD_ACTION_REMOTE_NAME = "SharedHazardAction"
local rng = Random.new()
local traceStateKey = nil
local activeHazardStates = {}
local lastSpawnedLateralLane = nil
local waveMovementTaskHandle = nil
local waveMovementFallbackRunning = false
local ensureWaveMovementTask = nil
local playerWaveSweepStates = {}
local waveSweepTaskHandle = nil
local waveSweepFallbackRunning = false
local sweepScanQueued = false
local diagnosticsHazardsFolder = nil
local warningKeys = {}
local waveDiagnostics = {
	KillRemoteCount = 0,
	ServerSweepHitCount = 0,
	ServerSweepCurrentHitCount = 0,
	ServerSweepSegmentHitCount = 0,
	ServerSweepRemoteRecoveryCount = 0,
	LastSweepPlayerCount = 0,
	LastSweepTimeMs = 0,
	LastSweepPublishedAt = 0,
	CleanupCount = 0,
	LastCleanupServerTime = 0,
	LastUpdateTimeMs = 0,
	UpdateTimeSum = 0,
	UpdateTimeSamples = 0,
	LastPublishedAt = 0,
}
local HAZARD_TRACE = RunService:IsStudio() and game:GetAttribute("HazardDebugTrace") == true
local findCurrentWaveHit = nil
local findSweptWaveHit = nil
local applyConfirmedWaveHit = nil
local isValidActiveHazardState = nil
local publishWaveDiagnostics = nil

StudioAssetResolver.ValidateRequiredAssets({ "Waves" }, "SpawnWaves")
WaveHazardVisuals.ValidateWaveAssets("SpawnWaves")

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

local function hazardTrace(message, ...)
	if not HAZARD_TRACE then
		return
	end

	print(string.format("[HAZARD TRACE] " .. message, ...))
end

local function hazardWarnOnce(key, message, ...)
	if warningKeys[key] then
		return
	end

	warningKeys[key] = true
	warn(string.format("[SpawnWaves] " .. message, ...))
end

local function validateWaveMeasurementConfig()
	local baseWaveVisualScale = tonumber(CONFIG.BaseWaveVisualScale)
	if not baseWaveVisualScale then
		hazardWarnOnce(
			"missing_wave_base_visual_scale",
			"Missing BaseWaveVisualScale; configured wave hitbox creation will fall back to legacy WaveTemplate if available."
		)
		return
	end

	if baseWaveVisualScale <= 0 then
		hazardWarnOnce(
			"invalid_wave_base_visual_scale",
			"Invalid BaseWaveVisualScale=%s; configured wave hitbox creation will fall back to legacy WaveTemplate if available.",
			tostring(CONFIG.BaseWaveVisualScale)
		)
	end

	if typeof(CONFIG.BaseWavePivotOffset) ~= "Vector3" then
		hazardWarnOnce(
			"invalid_wave_pivot_offset",
			"BaseWavePivotOffset is not a Vector3; generated wave hitboxes will use Vector3.zero."
		)
	end

	if typeof(CONFIG.BaseWaveOrientation) ~= "CFrame" then
		hazardWarnOnce(
			"invalid_wave_orientation",
			"BaseWaveOrientation is not a CFrame; generated wave hitboxes will use the default Regular Wave orientation."
		)
	end
end

validateWaveMeasurementConfig()

local function findChildRecursive(parent, childName)
	if not parent then
		return nil
	end

	local direct = parent:FindFirstChild(childName)
	if direct then
		return direct
	end

	return parent:FindFirstChild(childName, true)
end

local function getResolvedWavesFolder()
	local waves = StudioAssetResolver.ResolveAsset("Waves", {
		Context = "SpawnWaves",
		Required = true,
	})
	if waves and waves:IsA("Folder") then
		return waves
	end

	return nil
end

local function getOrCreateRemotesFolder()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if remotes and remotes:IsA("Folder") then
		return remotes
	end

	if remotes then
		remotes:Destroy()
	end

	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = ReplicatedStorage
	return remotes
end

local function getOrCreateRemoteEvent(parent, name)
	local remote = parent:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function isAirbornePhoenixFlight(player, humanoid, rootPart)
	if not PhoenixServer.IsPhoenixFlightActive(player) then
		return false
	end

	if not humanoid or not rootPart then
		return false
	end

	return humanoid.FloorMaterial == Enum.Material.Air
end

local function applyAirbornePhoenixHazardKnockdown(player, humanoid, rootPart)
	if not isAirbornePhoenixFlight(player, humanoid, rootPart) then
		return false
	end

	local applied = HitEffectService.ApplyEffect(player, "Knockdown", {
		Duration = AIRBORNE_TORI_HAZARD_KNOCKDOWN_DURATION,
		DropPosition = rootPart.Position,
		RagdollJoints = true,
		Movement = {
			WalkSpeedMultiplier = 0,
			JumpMultiplier = 0,
			AutoRotate = false,
			PlatformStand = true,
			State = Enum.HumanoidStateType.Physics,
		},
	})
	if not applied then
		return false
	end

	hazardTrace("airborne Phoenix hazard knockdown player=%s pos=%s", player.Name, formatVector3(rootPart.Position))
	return true
end

local remotesFolder = getOrCreateRemotesFolder()
local killMeRemote = getOrCreateRemoteEvent(remotesFolder, "KillMe")
local legacyHazardRemote = remotesFolder:FindFirstChild(HAZARD_ACTION_REMOTE_NAME)
if legacyHazardRemote then
	legacyHazardRemote:Destroy()
end

killMeRemote.OnServerEvent:Connect(function(player)
	waveDiagnostics.KillRemoteCount += 1
	publishWaveDiagnostics()

	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		local rootPart = character:FindFirstChild("HumanoidRootPart")
		local hit = nil
		if rootPart and findCurrentWaveHit then
			hit = findCurrentWaveHit(rootPart)
			local sweepState = playerWaveSweepStates[player]
			if not hit
				and findSweptWaveHit
				and sweepState
				and sweepState.Character == character
				and typeof(sweepState.PreviousPosition or sweepState.LastPosition) == "Vector3"
			then
				hit = findSweptWaveHit(rootPart, sweepState.PreviousPosition or sweepState.LastPosition, rootPart.Position)
				if hit then
					waveDiagnostics.ServerSweepRemoteRecoveryCount += 1
				end
			end
		end

		if not rootPart or not hit then
			hazardTrace("kill remote ignored reason=no_active_wave_overlap player=%s", player.Name)
			return
		end

		if applyConfirmedWaveHit then
			applyConfirmedWaveHit(player, character, humanoid, rootPart, hit, "client_touch")
		end
	end
end)

local function getPivot(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return instance.CFrame
end

local function matchesStringSet(value, allowedValues)
	if type(allowedValues) ~= "table" then
		return true
	end

	local normalizedValue = string.lower(tostring(value or ""))
	return allowedValues[normalizedValue] == true
end

local function setPivot(instance, cframeValue)
	if instance:IsA("Model") then
		instance:PivotTo(cframeValue)
	else
		instance.CFrame = cframeValue
	end
end

local function getBox(instance)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	end

	return instance.CFrame, instance.Size
end

local function getHazardMeasureParts(instance)
	local parts = WaveHazardVisuals.GetHitboxParts(instance)
	if #parts > 0 then
		return parts
	end

	if instance:IsA("BasePart") then
		return { instance }
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end

	return parts
end

local function getFrontExtentFromPivot(instance, pivotCFrame, forwardDirection)
	if typeof(forwardDirection) ~= "Vector3" or forwardDirection.Magnitude <= 1e-4 then
		return 0
	end

	local forwardUnit = forwardDirection.Unit
	local sourcePivot = getPivot(instance)
	local frontExtent = 0

	for _, part in ipairs(getHazardMeasureParts(instance)) do
		if part.Parent then
			local relativeCFrame = sourcePivot:ToObjectSpace(part.CFrame)
			local partCFrame = pivotCFrame * relativeCFrame
			local halfSize = part.Size * 0.5

			for _, xSign in ipairs({ -1, 1 }) do
				for _, ySign in ipairs({ -1, 1 }) do
					for _, zSign in ipairs({ -1, 1 }) do
						local cornerPosition = partCFrame:PointToWorldSpace(Vector3.new(
							halfSize.X * xSign,
							halfSize.Y * ySign,
							halfSize.Z * zSign
						))
						local projection = (cornerPosition - pivotCFrame.Position):Dot(forwardUnit)
						frontExtent = math.max(frontExtent, projection)
					end
				end
			end
		end
	end

	return math.max(0, frontExtent)
end

local function getProjectionExtentsFromPivot(instance, pivotCFrame, direction)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 1e-4 then
		return nil, nil
	end

	local directionUnit = direction.Unit
	local sourcePivot = getPivot(instance)
	local minProjection = math.huge
	local maxProjection = -math.huge
	local hasProjection = false

	for _, part in ipairs(getHazardMeasureParts(instance)) do
		if part.Parent then
			local relativeCFrame = sourcePivot:ToObjectSpace(part.CFrame)
			local partCFrame = pivotCFrame * relativeCFrame
			local halfSize = part.Size * 0.5

			for _, xSign in ipairs({ -1, 1 }) do
				for _, ySign in ipairs({ -1, 1 }) do
					for _, zSign in ipairs({ -1, 1 }) do
						local cornerPosition = partCFrame:PointToWorldSpace(Vector3.new(
							halfSize.X * xSign,
							halfSize.Y * ySign,
							halfSize.Z * zSign
						))
						local projection = (cornerPosition - pivotCFrame.Position):Dot(directionUnit)
						minProjection = math.min(minProjection, projection)
						maxProjection = math.max(maxProjection, projection)
						hasProjection = true
					end
				end
			end
		end
	end

	if not hasProjection then
		return nil, nil
	end

	return minProjection, maxProjection
end

local function getLateralOffsetRangeForPivot(
	instance,
	pivotCFrame,
	lateralDirection,
	minBoundaryProjection,
	maxBoundaryProjection,
	contactPadding
)
	local minRelativeProjection, maxRelativeProjection = getProjectionExtentsFromPivot(instance, pivotCFrame, lateralDirection)
	if not minRelativeProjection or not maxRelativeProjection then
		return nil, nil
	end

	local lateralUnit = lateralDirection.Unit
	local pivotProjection = pivotCFrame.Position:Dot(lateralUnit)
	local minOffset = minBoundaryProjection + contactPadding - pivotProjection - minRelativeProjection
	local maxOffset = maxBoundaryProjection - contactPadding - pivotProjection - maxRelativeProjection
	return minOffset, maxOffset
end

local function getHazardHitboxVolumes(hazardRoot, fallbackCFrame, fallbackSize)
	local volumes = {}

	for _, part in ipairs(WaveHazardVisuals.GetHitboxParts(hazardRoot)) do
		if part.Parent then
			volumes[#volumes + 1] = {
				Type = AffectableRegistry.VolumeType.Box,
				Label = part:GetFullName(),
				CFrame = part.CFrame,
				Size = part.Size,
				Padding = CONFIG.AffectablePadding,
			}
		end
	end

	if #volumes > 0 then
		return volumes
	end

	return {
		{
			Type = AffectableRegistry.VolumeType.Box,
			CFrame = fallbackCFrame,
			Size = fallbackSize,
			Padding = CONFIG.AffectablePadding,
		},
	}
end

local function countActiveProxyParts()
	local activeCount = 0
	local proxyPartCount = 0

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidActiveHazardState(hazardRoot, state) then
			activeCount += 1
			proxyPartCount += #WaveHazardVisuals.GetHitboxParts(hazardRoot)
		end
	end

	return activeCount, proxyPartCount
end

publishWaveDiagnostics = function(hazardsFolder)
	local folder = hazardsFolder or diagnosticsHazardsFolder
	if not folder or not folder.Parent then
		return
	end

	local activeCount, proxyPartCount = countActiveProxyParts()
	folder:SetAttribute("WaveActiveCount", activeCount)
	folder:SetAttribute("WaveServerProxyPartCount", proxyPartCount)
	folder:SetAttribute("WaveServerUpdateTimeMs", waveDiagnostics.LastUpdateTimeMs)
	folder:SetAttribute("WaveKillRemoteCount", waveDiagnostics.KillRemoteCount)
	folder:SetAttribute("WaveServerSweepHitCount", waveDiagnostics.ServerSweepHitCount)
	folder:SetAttribute("WaveServerSweepCurrentHitCount", waveDiagnostics.ServerSweepCurrentHitCount)
	folder:SetAttribute("WaveServerSweepSegmentHitCount", waveDiagnostics.ServerSweepSegmentHitCount)
	folder:SetAttribute("WaveServerSweepRemoteRecoveryCount", waveDiagnostics.ServerSweepRemoteRecoveryCount)
	folder:SetAttribute("WaveServerSweepPlayerCount", waveDiagnostics.LastSweepPlayerCount)
	folder:SetAttribute("WaveServerSweepTimeMs", waveDiagnostics.LastSweepTimeMs)
	folder:SetAttribute("WaveCleanupCount", waveDiagnostics.CleanupCount)
	folder:SetAttribute("WaveLastCleanupServerTime", waveDiagnostics.LastCleanupServerTime)
end

local function recordWaveUpdateTime(elapsedSeconds)
	waveDiagnostics.UpdateTimeSum += math.max(0, tonumber(elapsedSeconds) or 0)
	waveDiagnostics.UpdateTimeSamples += 1

	local now = os.clock()
	if now - waveDiagnostics.LastPublishedAt < CONFIG.DiagnosticsInterval then
		return
	end

	if waveDiagnostics.UpdateTimeSamples > 0 then
		waveDiagnostics.LastUpdateTimeMs =
			(waveDiagnostics.UpdateTimeSum / waveDiagnostics.UpdateTimeSamples) * 1000
	end
	waveDiagnostics.UpdateTimeSum = 0
	waveDiagnostics.UpdateTimeSamples = 0
	waveDiagnostics.LastPublishedAt = now
	publishWaveDiagnostics()
end

local function isPointInsideBox(point, boxCFrame, boxSize, padding)
	if typeof(point) ~= "Vector3" or typeof(boxCFrame) ~= "CFrame" or typeof(boxSize) ~= "Vector3" then
		return false
	end

	local safePadding = if typeof(padding) == "Vector3" then padding else Vector3.zero
	local halfSize = (boxSize + safePadding) * 0.5
	local localPoint = boxCFrame:PointToObjectSpace(point)

	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
end

local function getWaveValidationPadding(rootPart, configuredPadding)
	local basePadding = if typeof(configuredPadding) == "Vector3" then configuredPadding else CONFIG.KillValidationPadding
	if not rootPart or not rootPart:IsA("BasePart") then
		return basePadding
	end

	return basePadding + rootPart.Size
end

findCurrentWaveHit = function(rootPart, validationPaddingOverride)
	if not rootPart or not rootPart.Parent then
		return nil
	end

	local validationPadding = getWaveValidationPadding(rootPart, validationPaddingOverride)
	local rootPosition = rootPart.Position

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidActiveHazardState(hazardRoot, state) and os.clock() >= state.FrozenUntil then
			local volumes = getHazardHitboxVolumes(hazardRoot, state.CurrentCFrame, state.VolumeSize)
			for _, volume in ipairs(volumes) do
				if isPointInsideBox(rootPosition, volume.CFrame, volume.Size, validationPadding) then
					return {
						Source = "current",
						HazardRoot = hazardRoot,
						HazardLabel = formatInstancePath(hazardRoot),
						HitPosition = rootPosition,
					}
				end
			end
		end
	end

	return nil
end

findSweptWaveHit = function(rootPart, previousPosition, currentPosition, validationPaddingOverride)
	if CONFIG.SweptKillEnabled ~= true or not rootPart or not rootPart.Parent then
		return nil
	end

	if typeof(previousPosition) ~= "Vector3" or typeof(currentPosition) ~= "Vector3" then
		return nil
	end

	local delta = currentPosition - previousPosition
	local distance = delta.Magnitude
	if distance <= 0.01 then
		return nil
	end

	local teleportResetDistance = math.max(0, tonumber(CONFIG.SweptKillTeleportResetDistance) or 0)
	if teleportResetDistance > 0 and distance > teleportResetDistance then
		hazardTrace(
			"sweep skipped reason=teleport_delta distance=%.2f pos=%s",
			distance,
			formatVector3(currentPosition)
		)
		return nil
	end

	local validationPadding = getWaveValidationPadding(rootPart, validationPaddingOverride)

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidActiveHazardState(hazardRoot, state) and os.clock() >= state.FrozenUntil then
			local volumes = getHazardHitboxVolumes(hazardRoot, state.CurrentCFrame, state.VolumeSize)
			for _, volume in ipairs(volumes) do
				local intersects, hitPosition, hitAlpha = HazardRuntime.SegmentIntersectsBox(
					previousPosition,
					currentPosition,
					volume.CFrame,
					volume.Size,
					validationPadding
				)
				if intersects then
					return {
						Source = "segment",
						HazardRoot = hazardRoot,
						HazardLabel = formatInstancePath(hazardRoot),
						HitPosition = hitPosition or currentPosition,
						Alpha = hitAlpha,
						Distance = distance,
					}
				end
			end
		end
	end

	return nil
end

applyConfirmedWaveHit = function(player, character, humanoid, rootPart, hit, hitSource)
	if not player or not character or not humanoid or humanoid.Health <= 0 or not rootPart then
		return false
	end

	local isHazardProtected = HazardProtection.IsProtected(player, {
		Position = hit and hit.HitPosition or rootPart.Position,
		HitPosition = hit and hit.HitPosition or rootPart.Position,
		HazardClass = CONFIG.HazardClass,
		HazardType = "wave",
		Source = "SpawnWaves",
	})
	if isHazardProtected then
		return true
	end
	if SpiritServer.IsProjecting(player) and character:GetAttribute("HoroProjectionGhost") == true then
		return true
	end
	if PhoenixServer.IsProtected(player, hit and hit.HitPosition or rootPart.Position) then
		return true
	end
	if applyAirbornePhoenixHazardKnockdown(player, humanoid, rootPart) then
		return true
	end
	if PhoenixPassiveService.TryConsumeRebirth(player, "WaveKill") then
		return true
	end

	hazardTrace(
		"wave hit applied source=%s match=%s player=%s hit=%s hazard=%s",
		tostring(hitSource or "unknown"),
		tostring(hit and hit.Source or "unknown"),
		player.Name,
		formatVector3(hit and hit.HitPosition or rootPart.Position),
		tostring(hit and hit.HazardLabel or "<unknown>")
	)
	DamageProtection.TraceMoguStartupDamage(player, {
		TargetContext = {
			Player = player,
			Character = character,
			Humanoid = humanoid,
			RootPart = rootPart,
		},
		Position = hit and hit.HitPosition or rootPart.Position,
		HitPosition = hit and hit.HitPosition or rootPart.Position,
		Source = "SpawnWaves",
		Path = "SpawnWaves.applyConfirmedWaveHit",
	})
	humanoid.Health = 0
	return true
end

local function anchorHazard(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.AssemblyLinearVelocity = Vector3.zero
		instance.AssemblyAngularVelocity = Vector3.zero
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.AssemblyLinearVelocity = Vector3.zero
			descendant.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function scaleHazardByVector(instance, scaleVector)
	if typeof(scaleVector) ~= "Vector3"
		or (
			math.abs(scaleVector.X - 1) < 1e-3
			and math.abs(scaleVector.Y - 1) < 1e-3
			and math.abs(scaleVector.Z - 1) < 1e-3
		)
	then
		return
	end

	if instance:IsA("BasePart") then
		instance.Size = Vector3.new(
			instance.Size.X * scaleVector.X,
			instance.Size.Y * scaleVector.Y,
			instance.Size.Z * scaleVector.Z
		)
		return
	end

	local rootPivot = instance:GetPivot()
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local relative = rootPivot:ToObjectSpace(descendant.CFrame)
			local relativePosition = relative.Position
			local relativeRotation = relative - relativePosition

			descendant.Size = Vector3.new(
				descendant.Size.X * scaleVector.X,
				descendant.Size.Y * scaleVector.Y,
				descendant.Size.Z * scaleVector.Z
			)
			descendant.CFrame = rootPivot
				* CFrame.new(
					relativePosition.X * scaleVector.X,
					relativePosition.Y * scaleVector.Y,
					relativePosition.Z * scaleVector.Z
				)
				* relativeRotation
		end
	end
end

local function scaleHazardWidth(instance, widthScale)
	local safeWidthScale = math.max(0.05, tonumber(widthScale) or 1)
	scaleHazardByVector(instance, Vector3.new(safeWidthScale, 1, 1))
end

local function scaleHazardDimensions(instance, widthScale, heightScale, thicknessScale)
	scaleHazardByVector(instance, Vector3.new(
		math.max(0.05, tonumber(widthScale) or 1),
		math.max(0.05, tonumber(heightScale) or 1),
		math.max(0.05, tonumber(thicknessScale) or 1)
	))
end

local function computePivotOnTop(instance, referencePart)
	local boxCF, boxSize = getBox(instance)
	local offset = getPivot(instance):ToObjectSpace(boxCF)

	local up = referencePart.CFrame.UpVector
	local surface = referencePart.Position + up * (referencePart.Size.Y / 2)
	local rotation = referencePart.CFrame - referencePart.Position

	local desiredBox = CFrame.new(surface + up * (boxSize.Y / 2)) * rotation * CFrame.Angles(0, math.rad(-90), 0)
	return desiredBox * offset:Inverse()
end

local function translateCFrame(cframeValue, offset)
	local rotation = cframeValue - cframeValue.Position
	return CFrame.new(cframeValue.Position + offset) * rotation
end

local function getWaveSpeed()
	return math.max(1, tonumber(CONFIG.WaveSpeed) or 70)
end

local function applyHazardAttributes(instance, variant, speed)
	instance.Name = tostring(CONFIG.RuntimeWaveName or "Wave")
	instance:SetAttribute("HazardClass", CONFIG.HazardClass)
	instance:SetAttribute("HazardType", "Wave")
	instance:SetAttribute("Variant", variant.Name)
	instance:SetAttribute("Speed", speed)
	instance:SetAttribute("WaveWidthScale", CONFIG.WaveWidthScale)
	instance:SetAttribute("WaveHeightScale", CONFIG.WaveHeightScale)
	instance:SetAttribute("WaveThicknessScale", CONFIG.WaveThicknessScale)
	instance:SetAttribute("WaveVariantWidthScale", variant.WidthScale)
	instance:SetAttribute("CanFreeze", true)
	instance:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)
	instance:SetAttribute("WaveVisualMode", "ClientTimeline")
	instance:SetAttribute("ActiveWaveVisualAssetName", "Regular Wave")
end

local function chooseVariant()
	local totalWeight = 0
	for _, variant in ipairs(CONFIG.Variants) do
		totalWeight += math.max(0, tonumber(variant.Weight) or 0)
	end

	if totalWeight <= 0 then
		return CONFIG.Variants[rng:NextInteger(1, #CONFIG.Variants)]
	end

	local roll = rng:NextNumber(0, totalWeight)
	local cumulativeWeight = 0
	for _, variant in ipairs(CONFIG.Variants) do
		cumulativeWeight += math.max(0, tonumber(variant.Weight) or 0)
		if roll <= cumulativeWeight then
			return variant
		end
	end

	return CONFIG.Variants[#CONFIG.Variants]
end

local function chooseSpawnDelay()
	local minDelay = math.max(0.1, tonumber(CONFIG.SpawnDelayMin) or 2)
	local maxDelay = math.max(minDelay, tonumber(CONFIG.SpawnDelayMax) or minDelay)
	return rng:NextNumber(minDelay, maxDelay)
end

local function chooseWaveLateralOffset(minLateralOffset, maxLateralOffset)
	local minOffset = tonumber(minLateralOffset) or 0
	local maxOffset = tonumber(maxLateralOffset) or minOffset
	if maxOffset < minOffset then
		minOffset, maxOffset = maxOffset, minOffset
	end

	local lateralRange = math.max(0, maxOffset - minOffset)
	if lateralRange <= 1e-4 then
		return minOffset, 1
	end

	local laneCount = math.max(1, math.floor(tonumber(CONFIG.LateralLaneCount) or 3))
	local lane = rng:NextInteger(1, laneCount)
	if laneCount > 1 and lane == lastSpawnedLateralLane then
		lane = (lane % laneCount) + 1
	end

	local laneAlpha = if laneCount == 1 then 0.5 else (lane - 1) / (laneCount - 1)
	local chosenOffset = minOffset + (lateralRange * laneAlpha)
	return chosenOffset, lane
end

isValidActiveHazardState = function(hazardRoot, state)
	return typeof(hazardRoot) == "Instance" and type(state) == "table" and not state.Destroyed and hazardRoot.Parent ~= nil
end

local function cleanupActiveHazardStates()
	local activeCount = 0
	for hazardRoot, state in pairs(activeHazardStates) do
		if not isValidActiveHazardState(hazardRoot, state) then
			activeHazardStates[hazardRoot] = nil
		else
			activeCount += 1
		end
	end

	return activeCount
end

local function findNearestBlockingHazardDistance(candidatePosition, forwardDirection)
	local minimumForwardSpacing = math.max(0, tonumber(CONFIG.MinimumForwardSpacing) or 40)
	local nearestBlockingDistance = nil

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidActiveHazardState(hazardRoot, state) then
			local hazardPosition = typeof(state.Position) == "Vector3" and state.Position or getPivot(hazardRoot).Position
			local delta = hazardPosition - candidatePosition
			local forwardDistance = math.abs(delta:Dot(forwardDirection))

			if forwardDistance < minimumForwardSpacing then
				if nearestBlockingDistance == nil or forwardDistance < nearestBlockingDistance then
					nearestBlockingDistance = forwardDistance
				end
			end
		end
	end

	return nearestBlockingDistance, minimumForwardSpacing
end

local function resolveHazardRefs()
	local refs = MapResolver.WaitForRefs(
		{ "MapRoot", "WaveFolder", "WaveStart", "WaveEnd" },
		nil,
		{
			warn = true,
			context = "SharedHazards",
		}
	)

	local waveFolder = refs.WaveFolder
	local hazardsFolder = waveFolder and (waveFolder:FindFirstChild("Hazards") or waveFolder:WaitForChild("Hazards", 15)) or nil
	local leftBound = waveFolder and (waveFolder:FindFirstChild("LeftBound") or waveFolder:WaitForChild("LeftBound", 15)) or nil
	local rightBound = waveFolder and (waveFolder:FindFirstChild("RightBound") or waveFolder:WaitForChild("RightBound", 15)) or nil
	local stateKey = table.concat({
		tostring(refs.RequestedMapName),
		tostring(refs.ActiveMapName),
		formatInstancePath(refs.MapRoot),
		formatInstancePath(waveFolder),
		formatInstancePath(hazardsFolder),
		formatInstancePath(refs.WaveStart),
		formatInstancePath(refs.WaveEnd),
		formatInstancePath(leftBound),
		formatInstancePath(rightBound),
	}, "|")

	if traceStateKey ~= stateKey then
		traceStateKey = stateKey
		hazardTrace(
			"resolved map requestedMap=%s activeMap=%s mapPath=%s waveFolder=%s hazardsFolder=%s startPath=%s startPos=%s endPath=%s endPos=%s leftBoundPath=%s leftBoundPos=%s rightBoundPath=%s rightBoundPos=%s",
			tostring(refs.RequestedMapName),
			tostring(refs.ActiveMapName),
			formatInstancePath(refs.MapRoot),
			formatInstancePath(waveFolder),
			formatInstancePath(hazardsFolder),
			formatInstancePath(refs.WaveStart),
			formatVector3(refs.WaveStart and refs.WaveStart.Position or nil),
			formatInstancePath(refs.WaveEnd),
			formatVector3(refs.WaveEnd and refs.WaveEnd.Position or nil),
			formatInstancePath(leftBound),
			formatVector3(leftBound and leftBound.Position or nil),
			formatInstancePath(rightBound),
			formatVector3(rightBound and rightBound.Position or nil)
		)
	end

	return refs, waveFolder, hazardsFolder, refs.WaveStart, refs.WaveEnd, leftBound, rightBound
end

local function getLegacyWaveTemplate()
	local wavesFolder = ReplicatedStorage:FindFirstChild("Waves")
	if not wavesFolder then
		return nil
	end

	local template = findChildRecursive(wavesFolder, "WaveTemplate")
	if not template then
		return nil
	end

	if not (template:IsA("Model") or template:IsA("BasePart")) then
		hazardWarnOnce(
			"invalid_legacy_wave_template",
			"Ignoring legacy ReplicatedStorage.Waves.WaveTemplate because class=%s is not a Model/BasePart.",
			tostring(template.ClassName)
		)
		return nil
	end

	return template
end

local function getWaveMeasurementConfig()
	return {
		Name = CONFIG.RuntimeWaveName,
		BaseVisualScale = CONFIG.BaseWaveVisualScale,
		PivotOffset = CONFIG.BaseWavePivotOffset,
		Orientation = CONFIG.BaseWaveOrientation,
	}
end

local function createWaveHazard()
	local resolvedWavesFolder = getResolvedWavesFolder()
	if resolvedWavesFolder then
		hazardTrace("using resolved wave assets folder=%s", formatInstancePath(resolvedWavesFolder))
	end

	local clone, _, reason = WaveHazardVisuals.CreateHazardFromConfig(getWaveMeasurementConfig())
	if clone then
		return clone, "config"
	end

	hazardWarnOnce(
		"invalid_wave_measurement_config",
		"Configured wave hitbox creation failed reason=%s baseWaveVisualScale=%s; checking legacy ReplicatedStorage.Waves.WaveTemplate fallback.",
		tostring(reason),
		tostring(CONFIG.BaseWaveVisualScale)
	)

	local legacyTemplate = getLegacyWaveTemplate()
	if legacyTemplate then
		hazardWarnOnce(
			"legacy_wave_template_fallback",
			"Using legacy ReplicatedStorage.Waves.WaveTemplate only as a temporary fallback. Configure BaseWaveVisualScale/BaseWavePivotOffset/BaseWaveOrientation to remove this fallback."
		)
		return WaveHazardVisuals.CreateHazardFromTemplate(legacyTemplate), "legacy_template"
	end

	hazardTrace("spawn skipped reason=missing_wave_measurement source=config_or_legacy reason=%s", tostring(reason))
	return nil, "missing_measurement"
end

-- Accepts the corridor direction and hitbox-edge-safe lateral center range for straight-moving hazards.
local function createServerHazardController(
	hazardRoot,
	startCF,
	endCF,
	speed,
	lateralDirection,
	lateralMinOffset,
	lateralMaxOffset,
	initialLateralOffset
)
	local distance = (startCF.Position - endCF.Position).Magnitude
	local _, hazardSize = getBox(hazardRoot)
	local minOffset = tonumber(lateralMinOffset) or 0
	local maxOffset = tonumber(lateralMaxOffset) or minOffset
	if maxOffset < minOffset then
		minOffset, maxOffset = maxOffset, minOffset
	end
	local initialOffset = math.clamp(tonumber(initialLateralOffset) or 0, minOffset, maxOffset)
	local lateralVelocity = 0
	local maxDrift = 0

	local initialCF = WaveHazardVisuals.ComputeTimelineCFrame(
		startCF,
		endCF,
		0,
		speed,
		distance,
		lateralDirection,
		initialOffset,
		lateralVelocity,
		maxDrift,
		minOffset,
		maxOffset
	) or startCF

	local controller = {
		HazardRoot = hazardRoot,
		Destroyed = false,
		FrozenUntil = 0,
		FreezeToken = 0,
		Alpha = 0,
		ActiveSeconds = 0,
		CurrentCFrame = initialCF,
		Position = initialCF.Position,
		VolumeSize = hazardSize,
		Width = hazardSize.X,
		StartCFrame = startCF,
		EndCFrame = endCF,
		Distance = distance,
		Speed = speed,
		LateralDirection = lateralDirection,
		InitialLateralOffset = initialOffset,
		LateralVelocity = lateralVelocity,
		MaxDrift = maxDrift,
		LateralMinOffset = minOffset,
		LateralMaxOffset = maxOffset,
	}

	hazardRoot:SetAttribute("WaveStartCFrame", startCF)
	hazardRoot:SetAttribute("WaveEndCFrame", endCF)
	hazardRoot:SetAttribute("WaveDistance", distance)
	hazardRoot:SetAttribute("WaveServerSpeed", speed)
	hazardRoot:SetAttribute("WaveLateralDirection", lateralDirection)
	hazardRoot:SetAttribute("WaveInitialLateralOffset", initialOffset)
	hazardRoot:SetAttribute("WaveLateralVelocity", lateralVelocity)
	hazardRoot:SetAttribute("WaveMaxDrift", maxDrift)
	hazardRoot:SetAttribute("WaveLateralMinOffset", minOffset)
	hazardRoot:SetAttribute("WaveLateralMaxOffset", maxOffset)
	hazardRoot:SetAttribute("WaveMovementMode", "timeline_proxy")
	hazardRoot:SetAttribute("WaveSpawnServerTime", Workspace:GetServerTimeNow())
	setPivot(hazardRoot, initialCF)

	function controller:SyncTimelineState()
		if not self.HazardRoot.Parent then
			return
		end

		self.HazardRoot:SetAttribute("WaveActiveSeconds", self.ActiveSeconds)
		self.HazardRoot:SetAttribute("WaveStateServerTime", Workspace:GetServerTimeNow())
		self.HazardRoot:SetAttribute("WaveUpdateSerial", (self.HazardRoot:GetAttribute("WaveUpdateSerial") or 0) + 1)
	end

	controller:SyncTimelineState()

	controller.AffectableEntityId = AffectableRegistry.RegisterEntity({
		EntityType = AffectableRegistry.EntityType.Hazard,
		RootInstance = hazardRoot,
		Controller = controller,
		Metadata = {
			HazardClass = string.lower(tostring(hazardRoot:GetAttribute("HazardClass") or CONFIG.HazardClass)),
			HazardType = string.lower(tostring(hazardRoot:GetAttribute("HazardType") or "Wave")),
			CanFreeze = hazardRoot:GetAttribute("CanFreeze") == true,
			FreezeBehavior = string.lower(tostring(hazardRoot:GetAttribute("FreezeBehavior") or CONFIG.FreezeBehavior)),
			Padding = CONFIG.AffectablePadding,
		},
		IsActive = function(entity)
			return entity.Controller.Destroyed ~= true and hazardRoot.Parent ~= nil
		end,
		CanBeAffectedBy = function(entity, query)
			local metadata = entity.Metadata or {}
			if query and query.RequireCanFreeze == true and metadata.CanFreeze ~= true then
				return false, "not_freezable"
			end

			if query and not matchesStringSet(metadata.HazardClass, query.AllowedHazardClasses) then
				return false, "disallowed_class"
			end

			if query and not matchesStringSet(metadata.HazardType, query.AllowedHazardTypes) then
				return false, "disallowed_type"
			end

			return true, "ok"
		end,
		GetVolumes = function(entity)
			if entity.Controller.Destroyed == true or not hazardRoot.Parent then
				return {}
			end

			return getHazardHitboxVolumes(
				hazardRoot,
				entity.Controller.CurrentCFrame,
				entity.Controller.VolumeSize
			)
		end,
		ResolveData = function(entity, match)
			local metadata = entity.Metadata or {}
			return {
				Label = formatInstancePath(hazardRoot),
				Root = hazardRoot,
				Controller = entity.Controller,
				HazardClass = metadata.HazardClass,
				HazardType = metadata.HazardType,
				CanFreeze = metadata.CanFreeze == true,
				FreezeBehavior = metadata.FreezeBehavior,
				Position = entity.Controller.Position or getPivot(hazardRoot).Position,
				HitPosition = match and match.HitPosition or nil,
				MatchSource = "volume",
			}
		end,
	})

	function controller:Freeze(duration)
		if self.Destroyed or not self.HazardRoot.Parent then
			return false
		end

		local freezeDuration = math.max(0, tonumber(duration) or 0)
		if freezeDuration <= 0 then
			return false
		end

		self.FrozenUntil = math.max(self.FrozenUntil, os.clock() + freezeDuration)
		self.FreezeToken += 1
		local freezeToken = self.FreezeToken
		self:SyncTimelineState()
		WaveHazardVisuals.SetFrozen(self.HazardRoot, true)
		hazardTrace(
			"freeze applied hazard=%s duration=%.2f",
			formatInstancePath(self.HazardRoot),
			freezeDuration
		)

		task.spawn(function()
			while not self.Destroyed and self.HazardRoot.Parent and os.clock() < self.FrozenUntil do
				task.wait(0.05)
			end

			if self.Destroyed or self.FreezeToken ~= freezeToken then
				return
			end

			if self.HazardRoot.Parent then
				self:SyncTimelineState()
				WaveHazardVisuals.SetFrozen(self.HazardRoot, false)
			end
		end)

		return true
	end

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		activeHazardStates[self.HazardRoot] = nil
		waveDiagnostics.CleanupCount += 1
		waveDiagnostics.LastCleanupServerTime = Workspace:GetServerTimeNow()
		AffectableRegistry.UnregisterEntity(self.AffectableEntityId)
		HazardRuntime.Unregister(self.HazardRoot)
		if self.HazardRoot.Parent then
			self.HazardRoot:Destroy()
		end
		publishWaveDiagnostics()
	end

	HazardRuntime.Register(hazardRoot, controller)
	activeHazardStates[hazardRoot] = controller
	hazardRoot.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			controller:Destroy()
		end
	end)

	ensureWaveMovementTask()
end

local function resetPlayerWaveSweepState(player)
	playerWaveSweepStates[player] = nil
end

local function updatePlayerWaveSweep(player)
	local character = player.Character
	if not character then
		resetPlayerWaveSweepState(player)
		return 0
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart:IsA("BasePart") then
		resetPlayerWaveSweepState(player)
		return 0
	end

	local currentPosition = rootPart.Position
	local state = playerWaveSweepStates[player]
	if not state or state.Character ~= character or state.RootPart ~= rootPart then
		playerWaveSweepStates[player] = {
			Character = character,
			RootPart = rootPart,
			LastPosition = currentPosition,
			PreviousPosition = nil,
			LastUpdateClock = os.clock(),
		}
		return 1
	end

	local previousPosition = state.LastPosition
	state.PreviousPosition = previousPosition
	state.LastPosition = currentPosition
	state.LastUpdateClock = os.clock()

	local hit = findCurrentWaveHit and findCurrentWaveHit(rootPart, CONFIG.SweptKillPadding) or nil
	if hit then
		waveDiagnostics.ServerSweepHitCount += 1
		waveDiagnostics.ServerSweepCurrentHitCount += 1
		applyConfirmedWaveHit(player, character, humanoid, rootPart, hit, "server_sweep_current")
		return 1
	end

	hit = findSweptWaveHit
		and findSweptWaveHit(rootPart, previousPosition, currentPosition, CONFIG.SweptKillPadding)
		or nil
	if hit then
		waveDiagnostics.ServerSweepHitCount += 1
		waveDiagnostics.ServerSweepSegmentHitCount += 1
		applyConfirmedWaveHit(player, character, humanoid, rootPart, hit, "server_sweep_segment")
	end

	return 1
end

local function scanPlayersForWaveHits()
	local startedAt = os.clock()
	local scannedPlayers = 0

	for _, player in ipairs(Players:GetPlayers()) do
		scannedPlayers += updatePlayerWaveSweep(player)
	end

	waveDiagnostics.LastSweepPlayerCount = scannedPlayers
	waveDiagnostics.LastSweepTimeMs = (os.clock() - startedAt) * 1000
	local now = os.clock()
	if now - waveDiagnostics.LastSweepPublishedAt >= CONFIG.DiagnosticsInterval then
		waveDiagnostics.LastSweepPublishedAt = now
		publishWaveDiagnostics()
	end
end

local function ensureWaveSweepTask()
	if waveSweepTaskHandle and waveSweepTaskHandle:IsConnected() then
		return
	end

	if not PerformanceFlags.IsEnabled("RuntimeSchedulerEnabled") or not PerformanceFlags.IsEnabled("HazardSchedulerEnabled") then
		if waveSweepFallbackRunning then
			return
		end
		waveSweepFallbackRunning = true
		task.spawn(function()
			while waveSweepFallbackRunning do
				if not sweepScanQueued then
					sweepScanQueued = true
					task.defer(function()
						sweepScanQueued = false
						scanPlayersForWaveHits()
					end)
				end
				task.wait()
			end
		end)
		return
	end

	waveSweepTaskHandle = RuntimeScheduler.GetDefault():Schedule({
		Id = "SpawnWaves.PlayerSweep",
		Phase = "Heartbeat",
		Priority = 10,
		Callback = function()
			if sweepScanQueued then
				return true
			end

			sweepScanQueued = true
			task.defer(function()
				sweepScanQueued = false
				scanPlayersForWaveHits()
			end)
			return true
		end,
		OnStop = function()
			waveSweepTaskHandle = nil
		end,
	})
end

ensureWaveSweepTask()

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		resetPlayerWaveSweepState(player)
	end)
	player.CharacterRemoving:Connect(function()
		resetPlayerWaveSweepState(player)
	end)
end)

Players.PlayerRemoving:Connect(resetPlayerWaveSweepState)

for _, player in ipairs(Players:GetPlayers()) do
	resetPlayerWaveSweepState(player)
	player.CharacterAdded:Connect(function()
		resetPlayerWaveSweepState(player)
	end)
	player.CharacterRemoving:Connect(function()
		resetPlayerWaveSweepState(player)
	end)
end

local function stepWaveController(controller, dt)
	if not controller or controller.Destroyed or not controller.HazardRoot.Parent then
		return false
	end

	if controller.Distance <= 1e-4 then
		controller.Alpha = 1
		controller.CurrentCFrame = controller.EndCFrame
		controller.Position = controller.EndCFrame.Position
		setPivot(controller.HazardRoot, controller.EndCFrame)
		controller:Destroy()
		return false
	end

	if os.clock() < controller.FrozenUntil then
		return true
	end

	local updateStartedAt = os.clock()
	controller.ActiveSeconds += dt
	local currentCF, alpha = WaveHazardVisuals.ComputeTimelineCFrame(
		controller.StartCFrame,
		controller.EndCFrame,
		controller.ActiveSeconds,
		controller.Speed,
		controller.Distance,
		controller.LateralDirection,
		controller.InitialLateralOffset,
		controller.LateralVelocity,
		controller.MaxDrift,
		controller.LateralMinOffset,
		controller.LateralMaxOffset
	)

	controller.Alpha = alpha
	controller.CurrentCFrame = currentCF
	controller.Position = currentCF.Position
	setPivot(controller.HazardRoot, currentCF)
	recordWaveUpdateTime(os.clock() - updateStartedAt)

	if controller.Alpha >= 1 then
		controller.Alpha = 1
		controller.ActiveSeconds = controller.Distance / math.max(controller.Speed, 1e-3)
		controller.CurrentCFrame = controller.EndCFrame
		controller.Position = controller.EndCFrame.Position
		controller:Destroy()
		return false
	end

	return true
end

ensureWaveMovementTask = function()
	if waveMovementTaskHandle and waveMovementTaskHandle:IsConnected() then
		return
	end

	if not PerformanceFlags.IsEnabled("RuntimeSchedulerEnabled") or not PerformanceFlags.IsEnabled("HazardSchedulerEnabled") then
		if waveMovementFallbackRunning then
			return
		end
		waveMovementFallbackRunning = true
		task.spawn(function()
			while waveMovementFallbackRunning do
				local dt = task.wait()
				local hasActive = false
				for hazardRoot, controller in pairs(activeHazardStates) do
					if not controller or controller.Destroyed or not hazardRoot.Parent then
						activeHazardStates[hazardRoot] = nil
					else
						hasActive = true
						stepWaveController(controller, dt)
					end
				end
				if not hasActive then
					waveMovementFallbackRunning = false
				end
			end
		end)
		return
	end

	waveMovementTaskHandle = RuntimeScheduler.GetDefault():Schedule({
		Id = "SpawnWaves.ActiveMovement",
		Phase = "Heartbeat",
		Priority = 20,
		Callback = function(dt)
			local hasActive = false
			for hazardRoot, controller in pairs(activeHazardStates) do
				if not controller or controller.Destroyed or not hazardRoot.Parent then
					activeHazardStates[hazardRoot] = nil
				else
					hasActive = true
					stepWaveController(controller, dt)
				end
			end

			if not hasActive then
				return false
			end
			return true
		end,
		OnStop = function()
			waveMovementTaskHandle = nil
		end,
	})
end

local noDisastersTimer = Workspace:FindFirstChild("NoDisastersTimer") or Workspace:WaitForChild("NoDisastersTimer", 15)
local spawnPaused = nil

local function spawnSharedHazard(spawnDelay)
	local _, waveFolder, hazardsFolder, startPart, endPart, leftBound, rightBound = resolveHazardRefs()
	if not (waveFolder and hazardsFolder and startPart and endPart and leftBound and rightBound) then
		hazardTrace(
			"spawn skipped reason=missing_refs waveFolder=%s hazardsFolder=%s start=%s end=%s leftBound=%s rightBound=%s",
			formatInstancePath(waveFolder),
			formatInstancePath(hazardsFolder),
			formatInstancePath(startPart),
			formatInstancePath(endPart),
			formatInstancePath(leftBound),
			formatInstancePath(rightBound)
		)
		return false, "missing_refs"
	end
	diagnosticsHazardsFolder = hazardsFolder

	local maxActiveHazards = math.max(1, math.floor(tonumber(CONFIG.MaxActiveHazards) or 12))
	local activeHazardCount = cleanupActiveHazardStates()
	if activeHazardCount >= maxActiveHazards then
		hazardTrace(
			"spawn skipped reason=max_active_hazards activeHazardCount=%s maxActiveHazards=%s spawnDelay=%.2f",
			tostring(activeHazardCount),
			tostring(maxActiveHazards),
			tonumber(spawnDelay) or 0
		)
		return false, "max_active_hazards"
	end

	local clone, waveMeasurementSource = createWaveHazard()
	if not clone then
		return false, "missing_measurement"
	end

	local variant = chooseVariant()
	scaleHazardWidth(clone, variant.WidthScale)
	scaleHazardDimensions(clone, CONFIG.WaveWidthScale, CONFIG.WaveHeightScale, CONFIG.WaveThicknessScale)
	anchorHazard(clone)
	local waveSpeed = getWaveSpeed()
	applyHazardAttributes(clone, variant, waveSpeed)
	clone:SetAttribute("WaveMeasurementSource", waveMeasurementSource)
	clone:SetAttribute("WaveBaseVisualAssetName", "Regular Wave")
	clone:SetAttribute("WaveBaseVisualScale", CONFIG.BaseWaveVisualScale)

	local startCF = computePivotOnTop(clone, startPart)
	local endCF = computePivotOnTop(clone, endPart)
	local _, boxSize = getBox(clone)
	local waveWidth = boxSize.X
	local boundsDelta = rightBound.Position - leftBound.Position
	local horizontalBoundsDelta = Vector3.new(boundsDelta.X, 0, boundsDelta.Z)
	local corridorVector = horizontalBoundsDelta.Magnitude > 1e-4 and horizontalBoundsDelta or boundsDelta
	local corridorWidth = corridorVector.Magnitude
	if corridorWidth <= 1e-4 then
		hazardTrace(
			"spawn skipped reason=invalid_bounds leftBoundPos=%s rightBoundPos=%s",
			formatVector3(leftBound.Position),
			formatVector3(rightBound.Position)
		)
		clone:Destroy()
		return false, "invalid_bounds"
	end

	local lateralDirection = corridorVector.Unit
	local contactPadding = math.max(0, tonumber(CONFIG.WaveWallContactPadding) or 0)
	local bounceWallOverlap = math.max(0, tonumber(CONFIG.BounceWallOverlap) or 0)
	local bounceContactPadding = -bounceWallOverlap
	local availableCorridorWidth = math.max(0, corridorWidth - (contactPadding * 2))
	local corridorWidthScale = 1
	if availableCorridorWidth > 1e-4 and waveWidth > availableCorridorWidth then
		corridorWidthScale = math.max(0.05, availableCorridorWidth / waveWidth)
		scaleHazardWidth(clone, corridorWidthScale)
		clone:SetAttribute("WaveCorridorWidthScale", corridorWidthScale)
		startCF = computePivotOnTop(clone, startPart)
		endCF = computePivotOnTop(clone, endPart)
		_, boxSize = getBox(clone)
		waveWidth = boxSize.X
	end

	if waveWidth > availableCorridorWidth and availableCorridorWidth <= 1e-4 then
		hazardTrace(
			"spawn skipped reason=invalid_lateral_width variant=%s waveWidth=%.2f corridorWidth=%.2f contactPadding=%.2f availableCorridorWidth=%.2f corridorWidthScale=%.3f",
			tostring(variant.Name),
			waveWidth,
			corridorWidth,
			contactPadding,
			availableCorridorWidth,
			corridorWidthScale
		)
		clone:Destroy()
		return false, "invalid_lateral_width"
	end

	local travelDelta = endCF.Position - startCF.Position
	local forwardDirection = travelDelta.Magnitude > 1e-4 and travelDelta.Unit or startPart.CFrame.LookVector
	local endFrontExtent = getFrontExtentFromPivot(clone, endCF, forwardDirection)
	if endFrontExtent > 1e-4 then
		endCF = translateCFrame(endCF, -forwardDirection * endFrontExtent)
		travelDelta = endCF.Position - startCF.Position
	end

	local leftProjection = leftBound.Position:Dot(lateralDirection)
	local rightProjection = rightBound.Position:Dot(lateralDirection)
	local minBoundaryProjection = math.min(leftProjection, rightProjection)
	local maxBoundaryProjection = math.max(leftProjection, rightProjection)
	local startMinOffset, startMaxOffset = getLateralOffsetRangeForPivot(
		clone,
		startCF,
		lateralDirection,
		minBoundaryProjection,
		maxBoundaryProjection,
		bounceContactPadding
	)
	local endMinOffset, endMaxOffset = getLateralOffsetRangeForPivot(
		clone,
		endCF,
		lateralDirection,
		minBoundaryProjection,
		maxBoundaryProjection,
		bounceContactPadding
	)

	if not (startMinOffset and startMaxOffset and endMinOffset and endMaxOffset) then
		hazardTrace(
			"spawn skipped reason=missing_lateral_extents variant=%s waveWidth=%.2f corridorWidth=%.2f contactPadding=%.2f bounceWallOverlap=%.2f",
			tostring(variant.Name),
			waveWidth,
			corridorWidth,
			contactPadding,
			bounceWallOverlap
		)
		clone:Destroy()
		return false, "missing_lateral_extents"
	end

	local minLateralOffset = math.max(startMinOffset, endMinOffset)
	local maxLateralOffset = math.min(startMaxOffset, endMaxOffset)
	if maxLateralOffset < minLateralOffset then
		hazardTrace(
			"spawn skipped reason=invalid_lateral_range variant=%s waveWidth=%.2f corridorWidth=%.2f contactPadding=%.2f bounceWallOverlap=%.2f minLateralOffset=%.2f maxLateralOffset=%.2f",
			tostring(variant.Name),
			waveWidth,
			corridorWidth,
			contactPadding,
			bounceWallOverlap,
			minLateralOffset,
			maxLateralOffset
		)
		clone:Destroy()
		return false, "invalid_lateral_range"
	end

	local chosenOffset, chosenLane = chooseWaveLateralOffset(minLateralOffset, maxLateralOffset)

	local distance = math.max((endCF.Position - startCF.Position).Magnitude, 1e-4)
	local initialCF = WaveHazardVisuals.ComputeTimelineCFrame(
		startCF,
		endCF,
		0,
		waveSpeed,
		distance,
		lateralDirection,
		chosenOffset,
		0,
		0,
		minLateralOffset,
		maxLateralOffset
	) or translateCFrame(startCF, lateralDirection * chosenOffset)

	local nearestBlockingDistance, minimumForwardSpacing = findNearestBlockingHazardDistance(
		initialCF.Position,
		forwardDirection
	)
	if nearestBlockingDistance ~= nil then
		hazardTrace(
			"spawn skipped reason=spacing activeHazardCount=%s maxActiveHazards=%s variant=%s waveWidth=%.2f nearestBlockingHazardDistance=%.2f minimumForwardSpacing=%.2f spawnDelay=%.2f finalSpawnPosition=%s",
			tostring(activeHazardCount),
			tostring(maxActiveHazards),
			tostring(variant.Name),
			waveWidth,
			nearestBlockingDistance,
			minimumForwardSpacing,
			tonumber(spawnDelay) or 0,
			formatVector3(initialCF.Position)
		)
		clone:Destroy()
		return false, "spacing"
	end

	setPivot(clone, initialCF)
	clone.Parent = hazardsFolder
	lastSpawnedLateralLane = chosenLane
	publishWaveDiagnostics(hazardsFolder)

	hazardTrace(
		"spawned waveFolder=%s measurementSource=%s variant=%s speed=%.2f lane=%s activeHazardCount=%s maxActiveHazards=%s spawnDelay=%.2f waveWidth=%.2f leftBoundPos=%s rightBoundPos=%s corridorWidth=%.2f contactPadding=%.2f bounceWallOverlap=%.2f availableCorridorWidth=%.2f corridorWidthScale=%.3f minLateralOffset=%.2f maxLateralOffset=%.2f chosenOffset=%.2f endFrontExtent=%.2f finalSpawnPosition=%s centerlineEndPosition=%s hazard=%s",
		formatInstancePath(waveFolder),
		tostring(waveMeasurementSource),
		tostring(variant.Name),
		waveSpeed,
		tostring(chosenLane),
		tostring(activeHazardCount),
		tostring(maxActiveHazards),
		tonumber(spawnDelay) or 0,
		waveWidth,
		formatVector3(leftBound.Position),
		formatVector3(rightBound.Position),
		corridorWidth,
		contactPadding,
		bounceWallOverlap,
		availableCorridorWidth,
		corridorWidthScale,
		minLateralOffset,
		maxLateralOffset,
		chosenOffset,
		endFrontExtent,
		formatVector3(initialCF.Position),
		formatVector3(endCF.Position),
		formatInstancePath(clone)
	)

	clone:SetAttribute("WaveLateralMinOffset", minLateralOffset)
	clone:SetAttribute("WaveLateralMaxOffset", maxLateralOffset)
	clone:SetAttribute("WaveLateralLane", chosenLane)
	createServerHazardController(
		clone,
		startCF,
		endCF,
		waveSpeed,
		lateralDirection,
		minLateralOffset,
		maxLateralOffset,
		chosenOffset
	)
	publishWaveDiagnostics(hazardsFolder)
	return true, "spawned"
end

while true do
	if noDisastersTimer and noDisastersTimer.Value > 0 then
		if spawnPaused ~= true then
			spawnPaused = true
			hazardTrace(
				"spawn paused reason=no_disasters_timer value=%s",
				tostring(noDisastersTimer.Value)
			)
		end
		task.wait(1)
	else
		if spawnPaused ~= false then
			spawnPaused = false
			hazardTrace(
				"spawn resumed reason=no_disasters_timer value=%s",
				tostring(noDisastersTimer and noDisastersTimer.Value or 0)
			)
		end
		local spawnDelay = chooseSpawnDelay()
		local activeHazardCount = cleanupActiveHazardStates()
		local maxActiveHazards = math.max(1, math.floor(tonumber(CONFIG.MaxActiveHazards) or 12))
		hazardTrace(
			"spawn cycle activeHazardCount=%s maxActiveHazards=%s spawnDelay=%.2f",
			tostring(activeHazardCount),
			tostring(maxActiveHazards),
			spawnDelay
		)
		spawnSharedHazard(spawnDelay)
		task.wait(spawnDelay)
	end
end
