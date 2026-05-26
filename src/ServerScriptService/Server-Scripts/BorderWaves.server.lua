local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local StudioAssetResolver = require(Modules:WaitForChild("StudioAssetResolver"))
local WaveHazardVisuals = require(Modules:WaitForChild("WaveHazardVisuals"))
local HazardRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local HazardProtection = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("HazardProtection")
)

local function getNamedFolder(parent, childName)
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName and child:IsA("Folder") then
			return child
		end
	end

	error(string.format("Missing Folder named %s under %s", childName, parent:GetFullName()))
end

local devilFruitModules = ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruits")
local HoroServer = require(getNamedFolder(devilFruitModules, "Horo"):WaitForChild("Server"):WaitForChild("HoroServer"))
local toriFolder = getNamedFolder(devilFruitModules, "Tori")
local ToriPassiveService = require(toriFolder:WaitForChild("Server"):WaitForChild("ToriPassiveService"))

local CONFIG = {
	SpawnInterval = 3.5,
	MaxActiveHazards = 28,
	MinimumForwardSpacing = 16,
	HazardClass = "major",
	FreezeBehavior = "pause",
	Speed = 288,
	RuntimeWaveName = "BorderWave",
	BaseWaveVisualScale = 35.98836032827221,
	BaseWavePivotOffset = Vector3.zero,
	BaseWaveOrientation = CFrame.Angles(0, math.rad(180), 0),
	-- Smaller than the main wave system's WaveWidthScale so these behave like side-lane pressure.
	WaveWidthScale = 0.24,
	WaveHeightScale = 1,
	WaveThicknessScale = .4,
	WallContactPadding = 2,
	KillValidationPadding = Vector3.zero,
	SweptKillPadding = Vector3.zero,
	SweptKillTeleportResetDistance = 512,
	FlashEnabled = true,
	FlashBaseColor = Color3.fromRGB(0, 170, 255),
	FlashPeakColor = Color3.fromRGB(255, 255, 255),
	FlashPeriod = 0.6,
}

local activeHazardStates = {}
local playerSweepStates = {}
local warningKeys = {}
local BORDER_TRACE = RunService:IsStudio() and game:GetAttribute("BorderWaveDebugTrace") == true

StudioAssetResolver.ValidateRequiredAssets({ "Waves" }, "BorderWaves")
WaveHazardVisuals.ValidateWaveAssets("BorderWaves")

local function trace(message, ...)
	if BORDER_TRACE then
		print(string.format("[BorderWaves] " .. message, ...))
	end
end

local function warnOnce(key, message, ...)
	if warningKeys[key] then
		return
	end

	warningKeys[key] = true
	warn(string.format("[BorderWaves] " .. message, ...))
end

local function formatInstancePath(instance)
	if not instance then
		return "<nil>"
	end

	return instance:GetFullName()
end

local function getPivot(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return instance.CFrame
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

local function translateCFrame(cframeValue, offset)
	local rotation = cframeValue - cframeValue.Position
	return CFrame.new(cframeValue.Position + offset) * rotation
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
	if typeof(scaleVector) ~= "Vector3" then
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

local function computePivotOnTop(instance, referencePart)
	local boxCF, boxSize = getBox(instance)
	local offset = getPivot(instance):ToObjectSpace(boxCF)

	local up = referencePart.CFrame.UpVector
	local surface = referencePart.Position + up * (referencePart.Size.Y / 2)
	local rotation = referencePart.CFrame - referencePart.Position

	local desiredBox = CFrame.new(surface + up * (boxSize.Y / 2)) * rotation * CFrame.Angles(0, math.rad(-90), 0)
	return desiredBox * offset:Inverse()
end

local function createWaveHazard()
	local clone, _, reason = WaveHazardVisuals.CreateHazardFromConfig({
		Name = CONFIG.RuntimeWaveName,
		BaseVisualScale = CONFIG.BaseWaveVisualScale,
		PivotOffset = CONFIG.BaseWavePivotOffset,
		Orientation = CONFIG.BaseWaveOrientation,
	})
	if clone then
		return clone
	end

	warnOnce("missing_wave_config", "Could not create border wave hazard from config: %s", tostring(reason))
	return nil
end

local function applyHazardAttributes(hazardRoot, side)
	hazardRoot.Name = CONFIG.RuntimeWaveName
	hazardRoot:SetAttribute("HazardClass", CONFIG.HazardClass)
	hazardRoot:SetAttribute("HazardType", "Wave")
	hazardRoot:SetAttribute("CanFreeze", true)
	hazardRoot:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)
	hazardRoot:SetAttribute("Variant", "Border")
	hazardRoot:SetAttribute("Speed", CONFIG.Speed)
	hazardRoot:SetAttribute("WaveSpawnerSystem", "BorderWaves")
	hazardRoot:SetAttribute("WaveSpawnerRole", "border")
	hazardRoot:SetAttribute("WaveBorderSide", side)
	hazardRoot:SetAttribute("WaveWidthScale", CONFIG.WaveWidthScale)
	hazardRoot:SetAttribute("WaveHeightScale", CONFIG.WaveHeightScale)
	hazardRoot:SetAttribute("WaveThicknessScale", CONFIG.WaveThicknessScale)
	hazardRoot:SetAttribute("WaveVisualMode", "ClientTimeline")
	hazardRoot:SetAttribute("ActiveWaveVisualAssetName", "Regular Wave")
	hazardRoot:SetAttribute("WaveFixedLateralOffset", true)
	hazardRoot:SetAttribute("WaveMovementMode", "timeline_proxy")
	hazardRoot:SetAttribute("WaveFlashEnabled", CONFIG.FlashEnabled)
	hazardRoot:SetAttribute("WaveFlashBaseColor", CONFIG.FlashBaseColor)
	hazardRoot:SetAttribute("WaveFlashPeakColor", CONFIG.FlashPeakColor)
	hazardRoot:SetAttribute("WaveFlashPeriod", CONFIG.FlashPeriod)
end

local function resolveRefs()
	local refs = MapResolver.WaitForRefs(
		{ "MapRoot", "WaveFolder", "WaveStart", "WaveEnd" },
		nil,
		{
			warn = true,
			context = "BorderWaves",
		}
	)

	local waveFolder = refs.WaveFolder
	local hazardsFolder = waveFolder and (waveFolder:FindFirstChild("Hazards") or waveFolder:WaitForChild("Hazards", 15)) or nil
	local leftBound = waveFolder and (waveFolder:FindFirstChild("LeftBound") or waveFolder:WaitForChild("LeftBound", 15)) or nil
	local rightBound = waveFolder and (waveFolder:FindFirstChild("RightBound") or waveFolder:WaitForChild("RightBound", 15)) or nil

	return waveFolder, hazardsFolder, refs.WaveStart, refs.WaveEnd, leftBound, rightBound
end

local function isValidState(hazardRoot, state)
	return typeof(hazardRoot) == "Instance" and type(state) == "table" and not state.Destroyed and hazardRoot.Parent ~= nil
end

local function cleanupStates()
	local activeCount = 0
	for hazardRoot, state in pairs(activeHazardStates) do
		if not isValidState(hazardRoot, state) then
			activeHazardStates[hazardRoot] = nil
		else
			activeCount += 1
		end
	end

	return activeCount
end

local function findNearestSameSideDistance(candidatePosition, side, forwardDirection)
	local nearestDistance = nil
	local minimumSpacing = math.max(0, tonumber(CONFIG.MinimumForwardSpacing) or 0)

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidState(hazardRoot, state) and state.Side == side then
			local hazardPosition = typeof(state.Position) == "Vector3" and state.Position or getPivot(hazardRoot).Position
			local forwardDistance = math.abs((hazardPosition - candidatePosition):Dot(forwardDirection))
			if forwardDistance < minimumSpacing then
				nearestDistance = if nearestDistance == nil then forwardDistance else math.min(nearestDistance, forwardDistance)
			end
		end
	end

	return nearestDistance
end

local function getHazardHitboxVolumes(hazardRoot, fallbackCFrame, fallbackSize)
	local volumes = {}

	for _, part in ipairs(WaveHazardVisuals.GetHitboxParts(hazardRoot)) do
		if part.Parent then
			volumes[#volumes + 1] = {
				CFrame = part.CFrame,
				Size = part.Size,
			}
		end
	end

	if #volumes > 0 then
		return volumes
	end

	return {
		{
			CFrame = fallbackCFrame,
			Size = fallbackSize,
		},
	}
end

local function createController(hazardRoot, side, startCF, endCF, speed, lateralDirection, lateralOffset)
	local distance = math.max((endCF.Position - startCF.Position).Magnitude, 1e-4)
	local _, hazardSize = getBox(hazardRoot)
	local initialCF = WaveHazardVisuals.ComputeTimelineCFrame(
		startCF,
		endCF,
		0,
		speed,
		distance,
		lateralDirection,
		lateralOffset,
		0,
		0,
		lateralOffset,
		lateralOffset
	) or translateCFrame(startCF, lateralDirection * lateralOffset)

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
		Side = side,
		StartCFrame = startCF,
		EndCFrame = endCF,
		Distance = distance,
		Speed = speed,
	}

	hazardRoot:SetAttribute("WaveStartCFrame", startCF)
	hazardRoot:SetAttribute("WaveEndCFrame", endCF)
	hazardRoot:SetAttribute("WaveDistance", distance)
	hazardRoot:SetAttribute("WaveServerSpeed", speed)
	hazardRoot:SetAttribute("WaveLateralDirection", lateralDirection)
	hazardRoot:SetAttribute("WaveInitialLateralOffset", lateralOffset)
	hazardRoot:SetAttribute("WaveLateralVelocity", 0)
	hazardRoot:SetAttribute("WaveMaxDrift", 0)
	hazardRoot:SetAttribute("WaveLateralMinOffset", lateralOffset)
	hazardRoot:SetAttribute("WaveLateralMaxOffset", lateralOffset)
	hazardRoot:SetAttribute("WaveLateralStartOffset", lateralOffset)
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

	function controller:GetVolumes()
		if self.Destroyed or not self.HazardRoot.Parent then
			return {}
		end

		return getHazardHitboxVolumes(self.HazardRoot, self.CurrentCFrame, self.VolumeSize)
	end

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
		HazardRuntime.Unregister(self.HazardRoot)
		if self.HazardRoot.Parent then
			self.HazardRoot:Destroy()
		end
	end

	HazardRuntime.Register(hazardRoot, controller)
	activeHazardStates[hazardRoot] = controller
	hazardRoot.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			controller:Destroy()
		end
	end)
	controller:SyncTimelineState()

	task.spawn(function()
		while hazardRoot.Parent and not controller.Destroyed and controller.Alpha < 1 do
			local dt = RunService.Heartbeat:Wait()

			if os.clock() >= controller.FrozenUntil then
				controller.ActiveSeconds += dt
				local currentCF, alpha = WaveHazardVisuals.ComputeTimelineCFrame(
					startCF,
					endCF,
					controller.ActiveSeconds,
					speed,
					distance,
					lateralDirection,
					lateralOffset,
					0,
					0,
					lateralOffset,
					lateralOffset
				)

				controller.Alpha = alpha
				controller.CurrentCFrame = currentCF
				controller.Position = currentCF.Position
				setPivot(hazardRoot, currentCF)
			end
		end

		controller:Destroy()
	end)

	return controller
end

local function spawnBorderWave(side)
	local _, hazardsFolder, startPart, endPart, leftBound, rightBound = resolveRefs()
	if not (hazardsFolder and startPart and endPart and leftBound and rightBound) then
		trace(
			"spawn skipped side=%s hazards=%s start=%s end=%s left=%s right=%s",
			tostring(side),
			formatInstancePath(hazardsFolder),
			formatInstancePath(startPart),
			formatInstancePath(endPart),
			formatInstancePath(leftBound),
			formatInstancePath(rightBound)
		)
		return false
	end

	if cleanupStates() >= CONFIG.MaxActiveHazards then
		return false
	end

	local hazardRoot = createWaveHazard()
	if not hazardRoot then
		return false
	end

	scaleHazardByVector(hazardRoot, Vector3.new(CONFIG.WaveWidthScale, CONFIG.WaveHeightScale, CONFIG.WaveThicknessScale))
	anchorHazard(hazardRoot)
	applyHazardAttributes(hazardRoot, side)

	local startCF = computePivotOnTop(hazardRoot, startPart)
	local endCF = computePivotOnTop(hazardRoot, endPart)
	local boundsDelta = rightBound.Position - leftBound.Position
	local horizontalBoundsDelta = Vector3.new(boundsDelta.X, 0, boundsDelta.Z)
	local corridorVector = horizontalBoundsDelta.Magnitude > 1e-4 and horizontalBoundsDelta or boundsDelta
	if corridorVector.Magnitude <= 1e-4 then
		hazardRoot:Destroy()
		return false
	end

	local lateralDirection = corridorVector.Unit
	local travelDelta = endCF.Position - startCF.Position
	local forwardDirection = travelDelta.Magnitude > 1e-4 and travelDelta.Unit or startPart.CFrame.LookVector
	local endFrontExtent = getFrontExtentFromPivot(hazardRoot, endCF, forwardDirection)
	if endFrontExtent > 1e-4 then
		endCF = translateCFrame(endCF, -forwardDirection * endFrontExtent)
	end

	local leftProjection = leftBound.Position:Dot(lateralDirection)
	local rightProjection = rightBound.Position:Dot(lateralDirection)
	local minBoundaryProjection = math.min(leftProjection, rightProjection)
	local maxBoundaryProjection = math.max(leftProjection, rightProjection)
	local startMinOffset, startMaxOffset = getLateralOffsetRangeForPivot(
		hazardRoot,
		startCF,
		lateralDirection,
		minBoundaryProjection,
		maxBoundaryProjection,
		CONFIG.WallContactPadding
	)
	local endMinOffset, endMaxOffset = getLateralOffsetRangeForPivot(
		hazardRoot,
		endCF,
		lateralDirection,
		minBoundaryProjection,
		maxBoundaryProjection,
		CONFIG.WallContactPadding
	)
	if not (startMinOffset and startMaxOffset and endMinOffset and endMaxOffset) then
		hazardRoot:Destroy()
		return false
	end

	local minLateralOffset = math.max(startMinOffset, endMinOffset)
	local maxLateralOffset = math.min(startMaxOffset, endMaxOffset)
	if maxLateralOffset < minLateralOffset then
		hazardRoot:Destroy()
		return false
	end

	local lateralOffset = if side == "right" then maxLateralOffset else minLateralOffset
	local initialCF = WaveHazardVisuals.ComputeTimelineCFrame(
		startCF,
		endCF,
		0,
		CONFIG.Speed,
		math.max((endCF.Position - startCF.Position).Magnitude, 1e-4),
		lateralDirection,
		lateralOffset,
		0,
		0,
		lateralOffset,
		lateralOffset
	) or translateCFrame(startCF, lateralDirection * lateralOffset)

	if findNearestSameSideDistance(initialCF.Position, side, forwardDirection) ~= nil then
		hazardRoot:Destroy()
		return false
	end

	setPivot(hazardRoot, initialCF)
	hazardRoot.Parent = hazardsFolder
	createController(hazardRoot, side, startCF, endCF, CONFIG.Speed, lateralDirection, lateralOffset)
	trace("spawned side=%s hazard=%s", tostring(side), formatInstancePath(hazardRoot))
	return true
end

local function getValidationPadding(rootPart, configuredPadding)
	local basePadding = if typeof(configuredPadding) == "Vector3" then configuredPadding else Vector3.zero
	if not rootPart or not rootPart:IsA("BasePart") then
		return basePadding
	end

	return basePadding + rootPart.Size
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

local function findCurrentHit(rootPart, validationPaddingOverride)
	if not rootPart or not rootPart.Parent then
		return nil
	end

	local validationPadding = getValidationPadding(rootPart, validationPaddingOverride or CONFIG.KillValidationPadding)
	local rootPosition = rootPart.Position

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidState(hazardRoot, state) and os.clock() >= state.FrozenUntil then
			for _, volume in ipairs(state:GetVolumes()) do
				if isPointInsideBox(rootPosition, volume.CFrame, volume.Size, validationPadding) then
					return {
						Source = "current",
						HazardRoot = hazardRoot,
						HitPosition = rootPosition,
					}
				end
			end
		end
	end

	return nil
end

local function findSweptHit(rootPart, previousPosition, currentPosition, validationPaddingOverride)
	if not rootPart or not rootPart.Parent then
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
		return nil
	end

	local validationPadding = getValidationPadding(rootPart, validationPaddingOverride or CONFIG.SweptKillPadding)

	for hazardRoot, state in pairs(activeHazardStates) do
		if isValidState(hazardRoot, state) and os.clock() >= state.FrozenUntil then
			for _, volume in ipairs(state:GetVolumes()) do
				local intersects, hitPosition = HazardRuntime.SegmentIntersectsBox(
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
						HitPosition = hitPosition or currentPosition,
					}
				end
			end
		end
	end

	return nil
end

local function applyConfirmedHit(player, character, humanoid, rootPart, hit)
	if not player or not character or not humanoid or humanoid.Health <= 0 or not rootPart then
		return false
	end

	if HazardProtection.IsProtected(player, {
		Position = hit and hit.HitPosition or rootPart.Position,
		HitPosition = hit and hit.HitPosition or rootPart.Position,
		HazardClass = CONFIG.HazardClass,
		HazardType = "wave",
		Source = "BorderWaves",
	}) then
		return true
	end

	if HoroServer.IsProjecting(player) and character:GetAttribute("HoroProjectionGhost") == true then
		HoroServer.InterruptActiveProjection(player, "border_wave_touch")
		return true
	end

	if ToriPassiveService.TryConsumeRebirth(player, "WaveKill") then
		return true
	end

	humanoid.Health = 0
	return true
end

local function resetPlayerSweepState(player)
	playerSweepStates[player] = nil
end

local function updatePlayerSweep(player)
	local character = player.Character
	if not character then
		resetPlayerSweepState(player)
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart:IsA("BasePart") then
		resetPlayerSweepState(player)
		return
	end

	local currentPosition = rootPart.Position
	local state = playerSweepStates[player]
	if not state or state.Character ~= character or state.RootPart ~= rootPart then
		playerSweepStates[player] = {
			Character = character,
			RootPart = rootPart,
			LastPosition = currentPosition,
		}
		return
	end

	local previousPosition = state.LastPosition
	state.LastPosition = currentPosition

	local hit = findCurrentHit(rootPart, CONFIG.SweptKillPadding)
		or findSweptHit(rootPart, previousPosition, currentPosition, CONFIG.SweptKillPadding)
	if hit then
		applyConfirmedHit(player, character, humanoid, rootPart, hit)
	end
end

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		updatePlayerSweep(player)
	end
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		resetPlayerSweepState(player)
	end)
	player.CharacterRemoving:Connect(function()
		resetPlayerSweepState(player)
	end)
end)

Players.PlayerRemoving:Connect(resetPlayerSweepState)

for _, player in ipairs(Players:GetPlayers()) do
	resetPlayerSweepState(player)
	player.CharacterAdded:Connect(function()
		resetPlayerSweepState(player)
	end)
	player.CharacterRemoving:Connect(function()
		resetPlayerSweepState(player)
	end)
end

local noDisastersTimer = Workspace:FindFirstChild("NoDisastersTimer") or Workspace:WaitForChild("NoDisastersTimer", 15)

while true do
	if noDisastersTimer and noDisastersTimer.Value > 0 then
		task.wait(1)
	else
		spawnBorderWave("left")
		spawnBorderWave("right")
		task.wait(CONFIG.SpawnInterval)
	end
end
