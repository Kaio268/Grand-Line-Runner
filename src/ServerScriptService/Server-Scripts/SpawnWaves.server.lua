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
local WaveHazardVisuals = require(Modules:WaitForChild("WaveHazardVisuals"))
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
local devilFruitModules = ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruits")
local HoroServer = require(getNamedFolder(devilFruitModules, "Horo"):WaitForChild("Server"):WaitForChild("HoroServer"))
local toriFolder = getNamedFolder(devilFruitModules, "Tori")
local ToriServer = require(toriFolder:WaitForChild("Server"):WaitForChild("ToriServer"))
local ToriPassiveService = require(toriFolder:WaitForChild("Server"):WaitForChild("ToriPassiveService"))

local CONFIG = {
	SpawnDelayMin = 2,
	SpawnDelayMax = 5,
	MaxActiveHazards = 20,
	MinimumForwardSpacing = 15,
	HazardClass = "major",
	FreezeBehavior = "pause",
	-- Used for ability/hazard affectable queries; wave damage ignores this so the kill area matches WaveHitbox.
	AffectablePadding = Vector3.new(2, 1, 4),
	-- Extra damage padding stays at zero: high-speed reliability comes from swept detection, not oversized damage boxes.
	KillValidationPadding = Vector3.zero,
	SweptKillEnabled = true,
	SweptKillPadding = Vector3.zero,
	SweptKillTeleportResetDistance = 512,
	-- WaveWidthScale controls left-to-right wave size. Variant WidthScale still applies on top of this.
	WaveWidthScale = 0.65,
	-- WaveHeightScale controls vertical wave size.
	WaveHeightScale = 1,
	-- WaveThicknessScale controls front-to-back wave depth.
	WaveThicknessScale = 1,
	DiagnosticsInterval = 2,
	DriftStrengthMultiplier = 1.35,              --DRIFT SPEED MANIPULATOR
	DriftSpeedMinMultiplier = 1.35,
	DriftSpeedMaxMultiplier = 1.85,
	Variants = {
		{
			Name = "Normal",
			Speed = 72,
			WidthScale = 1,
		},
		{
			Name = "Fast",
			Speed = 128,
			WidthScale = 1,
		},
		{
			Name = "Wide",
			Speed = 52,
			WidthScale = 1.6,
		},
	},
}

local AIRBORNE_TORI_HAZARD_KNOCKDOWN_DURATION = 1.15
local HAZARD_ACTION_REMOTE_NAME = "SharedHazardAction"
local rng = Random.new()
local traceStateKey = nil
local activeHazardStates = {}
local playerWaveSweepStates = {}
local diagnosticsHazardsFolder = nil
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
	if not ToriServer.IsPhoenixFlightActive(player) then
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

	hazardTrace("airborne Tori hazard knockdown player=%s pos=%s", player.Name, formatVector3(rootPart.Position))
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

	if HoroServer.IsProjecting(player) and character:GetAttribute("HoroProjectionGhost") == true then
		HoroServer.InterruptActiveProjection(player, "wave_touch")
		return true
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
	if ToriServer.IsProtected(player, hit and hit.HitPosition or rootPart.Position) then
		return true
	end
	if applyAirbornePhoenixHazardKnockdown(player, humanoid, rootPart) then
		return true
	end
	if ToriPassiveService.TryConsumeRebirth(player, "WaveKill") then
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

local function applyHazardAttributes(instance, variant)
	instance.Name = "WaveTemplate"
	instance:SetAttribute("HazardClass", CONFIG.HazardClass)
	instance:SetAttribute("HazardType", "Wave")
	instance:SetAttribute("Variant", variant.Name)
	instance:SetAttribute("Speed", variant.Speed)
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
	return CONFIG.Variants[rng:NextInteger(1, #CONFIG.Variants)]
end

local function chooseSpawnDelay()
	local minDelay = math.max(0.1, tonumber(CONFIG.SpawnDelayMin) or 2)
	local maxDelay = math.max(minDelay, tonumber(CONFIG.SpawnDelayMax) or minDelay)
	return rng:NextNumber(minDelay, maxDelay)
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

local function findNearestBlockingHazardDistance(candidatePosition, candidateWidth, forwardDirection, lateralDirection)
	local minimumForwardSpacing = math.max(0, tonumber(CONFIG.MinimumForwardSpacing) or 20)
	local nearestBlockingDistance = nil

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidActiveHazardState(hazardRoot, state) then
			local hazardPosition = typeof(state.Position) == "Vector3" and state.Position or getPivot(hazardRoot).Position
			local existingWidth = math.max(0, tonumber(state.Width) or 0)
			local delta = hazardPosition - candidatePosition
			local forwardDistance = math.abs(delta:Dot(forwardDirection))
			local lateralDistance = math.abs(delta:Dot(lateralDirection))
			local minimumLateralGap = (candidateWidth + existingWidth) * 0.5

			if forwardDistance < minimumForwardSpacing and lateralDistance < minimumLateralGap then
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

local function getWaveTemplate()
	local wavesFolder = ReplicatedStorage:FindFirstChild("Waves") or ReplicatedStorage:WaitForChild("Waves", 15)
	if not wavesFolder then
		hazardTrace("spawn skipped reason=missing_waves_folder path=ReplicatedStorage.Waves")
		return nil
	end

	local template = wavesFolder:FindFirstChild("WaveTemplate") or wavesFolder:WaitForChild("WaveTemplate", 15)
	if not template then
		hazardTrace("spawn skipped reason=missing_wave_template path=ReplicatedStorage.Waves.WaveTemplate")
		return nil
	end

	if not (template:IsA("Model") or template:IsA("BasePart")) then
		hazardTrace("spawn skipped reason=invalid_wave_template class=%s", template.ClassName)
		return nil
	end

	return template
end

-- Accepts the corridor direction and available sideways room for drifting hazards.
local function createServerHazardController(hazardRoot, startCF, endCF, speed, lateralDirection, lateralDriftLimit)
	local distance = (startCF.Position - endCF.Position).Magnitude
	local _, hazardSize = getBox(hazardRoot)
	local driftStyle = rng:NextNumber() < 0.15 and "straight" or "drift"
	local maxDrift = math.max(0, tonumber(lateralDriftLimit) or 0) * math.max(1, tonumber(CONFIG.DriftStrengthMultiplier) or 1)
	local initialLateralOffset = 0
	local lateralVelocity = 0

	if driftStyle == "drift" and maxDrift > 1e-3 and distance > 1e-4 then
		local travelTime = distance / math.max(speed, 1e-3)
		local bounceCount = rng:NextInteger(3, 6)
		local minLateralSpeed = ((maxDrift * 2) / math.max(travelTime, 1e-3)) * math.max(1, tonumber(CONFIG.DriftSpeedMinMultiplier) or 1)
		local maxLateralSpeed = ((maxDrift * 2 * bounceCount) / math.max(travelTime, 1e-3)) * math.max(1, tonumber(CONFIG.DriftSpeedMaxMultiplier) or 1)

		initialLateralOffset = rng:NextNumber(-maxDrift, maxDrift)
		lateralVelocity = rng:NextNumber(minLateralSpeed, maxLateralSpeed)
		if rng:NextInteger(0, 1) == 0 then
			lateralVelocity = -lateralVelocity
		end
	end

	local controller = {
		HazardRoot = hazardRoot,
		Destroyed = false,
		FrozenUntil = 0,
		FreezeToken = 0,
		Alpha = 0,
		ActiveSeconds = 0,
		CurrentCFrame = startCF,
		Position = startCF.Position,
		VolumeSize = hazardSize,
		Width = hazardSize.X,
		StartCFrame = startCF,
		EndCFrame = endCF,
		Distance = distance,
		Speed = speed,
		LateralDirection = lateralDirection,
		InitialLateralOffset = initialLateralOffset,
		LateralVelocity = lateralVelocity,
		MaxDrift = maxDrift,
	}

	hazardRoot:SetAttribute("WaveStartCFrame", startCF)
	hazardRoot:SetAttribute("WaveEndCFrame", endCF)
	hazardRoot:SetAttribute("WaveDistance", distance)
	hazardRoot:SetAttribute("WaveServerSpeed", speed)
	hazardRoot:SetAttribute("WaveLateralDirection", lateralDirection)
	hazardRoot:SetAttribute("WaveInitialLateralOffset", initialLateralOffset)
	hazardRoot:SetAttribute("WaveLateralVelocity", lateralVelocity)
	hazardRoot:SetAttribute("WaveMaxDrift", maxDrift)
	hazardRoot:SetAttribute("WaveMovementMode", "timeline_proxy")
	hazardRoot:SetAttribute("WaveSpawnServerTime", Workspace:GetServerTimeNow())

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

	task.spawn(function()
		if distance <= 1e-4 then
			controller.Alpha = 1
			controller.CurrentCFrame = endCF
			controller.Position = endCF.Position
			setPivot(hazardRoot, endCF)
			controller:Destroy()
			return
		end

		--ZIG ZAG

		while hazardRoot.Parent and not controller.Destroyed and controller.Alpha < 1 do
			local dt = RunService.Heartbeat:Wait()

			if os.clock() >= controller.FrozenUntil then
				local updateStartedAt = os.clock()
				controller.ActiveSeconds += dt
				local currentCF, alpha = WaveHazardVisuals.ComputeTimelineCFrame(
					startCF,
					endCF,
					controller.ActiveSeconds,
					speed,
					distance,
					lateralDirection,
					initialLateralOffset,
					lateralVelocity,
					maxDrift
				)

				controller.Alpha = alpha

				controller.CurrentCFrame = currentCF
				controller.Position = currentCF.Position
				setPivot(hazardRoot, currentCF)
				recordWaveUpdateTime(os.clock() - updateStartedAt)
			end
		end

		controller.Alpha = 1
		controller.ActiveSeconds = distance / math.max(speed, 1e-3)
		controller.CurrentCFrame = endCF
		controller.Position = endCF.Position
		controller:Destroy()
	end)
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

local sweepScanQueued = false
RunService.Heartbeat:Connect(function()
	if sweepScanQueued then
		return
	end

	sweepScanQueued = true
	task.defer(function()
		sweepScanQueued = false
		scanPlayersForWaveHits()
	end)
end)

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

	local template = getWaveTemplate()
	if not template then
		return false, "missing_template"
	end

	local maxActiveHazards = math.max(1, math.floor(tonumber(CONFIG.MaxActiveHazards) or 20))
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

	local variant = chooseVariant()
	local clone = WaveHazardVisuals.CreateHazardFromTemplate(template)
	scaleHazardWidth(clone, variant.WidthScale)
	scaleHazardDimensions(clone, CONFIG.WaveWidthScale, CONFIG.WaveHeightScale, CONFIG.WaveThicknessScale)
	anchorHazard(clone)
	applyHazardAttributes(clone, variant)

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
	local safeHalfOffset = math.max(corridorWidth - waveWidth, 0) * 0.5
	local chosenOffset = 0
	if safeHalfOffset > 1e-4 then
		chosenOffset = rng:NextNumber(-safeHalfOffset, safeHalfOffset)
	elseif waveWidth > corridorWidth then
		hazardTrace(
			"offset clamped reason=wave_wider_than_corridor variant=%s waveWidth=%.2f corridorWidth=%.2f",
			tostring(variant.Name),
			waveWidth,
			corridorWidth
		)
	end

	local lateralOffset = lateralDirection * chosenOffset
	startCF = translateCFrame(startCF, lateralOffset)
	endCF = translateCFrame(endCF, lateralOffset)
	local travelDelta = endCF.Position - startCF.Position
	local forwardDirection = travelDelta.Magnitude > 1e-4 and travelDelta.Unit or startPart.CFrame.LookVector
	local endFrontExtent = getFrontExtentFromPivot(clone, endCF, forwardDirection)
	if endFrontExtent > 1e-4 then
		endCF = translateCFrame(endCF, -forwardDirection * endFrontExtent)
		travelDelta = endCF.Position - startCF.Position
	end
	local nearestBlockingDistance, minimumForwardSpacing = findNearestBlockingHazardDistance(
		startCF.Position,
		waveWidth,
		forwardDirection,
		lateralDirection
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
			formatVector3(startCF.Position)
		)
		clone:Destroy()
		return false, "spacing"
	end

	setPivot(clone, startCF)
	clone.Parent = hazardsFolder
	publishWaveDiagnostics(hazardsFolder)

	hazardTrace(
		"spawned waveFolder=%s variant=%s speed=%.2f activeHazardCount=%s maxActiveHazards=%s spawnDelay=%.2f waveWidth=%.2f leftBoundPos=%s rightBoundPos=%s corridorWidth=%.2f chosenOffset=%.2f endFrontExtent=%.2f finalSpawnPosition=%s finalEndPosition=%s hazard=%s",
		formatInstancePath(waveFolder),
		tostring(variant.Name),
		tonumber(variant.Speed) or 0,
		tostring(activeHazardCount),
		tostring(maxActiveHazards),
		tonumber(spawnDelay) or 0,
		waveWidth,
		formatVector3(leftBound.Position),
		formatVector3(rightBound.Position),
		corridorWidth,
		chosenOffset,
		endFrontExtent,
		formatVector3(startCF.Position),
		formatVector3(endCF.Position),
		formatInstancePath(clone)
	)

	local lateralDriftLimit = math.max(0, safeHalfOffset - math.abs(chosenOffset))
	createServerHazardController(clone, startCF, endCF, variant.Speed, lateralDirection, lateralDriftLimit)
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
		local maxActiveHazards = math.max(1, math.floor(tonumber(CONFIG.MaxActiveHazards) or 20))
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
