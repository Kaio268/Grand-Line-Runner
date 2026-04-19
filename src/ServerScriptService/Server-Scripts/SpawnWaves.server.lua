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
local HazardRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local AffectableRegistry = require(game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local devilFruitModules = game:GetService("ServerScriptService"):WaitForChild("Modules"):WaitForChild("DevilFruits")
local MoguServer = require(getNamedFolder(devilFruitModules, "Mogu"):WaitForChild("Server"):WaitForChild("MoguServer"))
local HoroServer = require(getNamedFolder(devilFruitModules, "Horo"):WaitForChild("Server"):WaitForChild("HoroServer"))
local ToriPassiveService = require(getNamedFolder(devilFruitModules, "Tori"):WaitForChild("Server"):WaitForChild("ToriPassiveService"))

local CONFIG = {
	SpawnDelayMin = 2,
	SpawnDelayMax = 5,
	MaxActiveHazards = 20,
	MinimumForwardSpacing = 15,
	HazardClass = "major",
	FreezeBehavior = "pause",
	AffectablePadding = Vector3.new(2, 1, 4),
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

local HAZARD_ACTION_REMOTE_NAME = "SharedHazardAction"
local rng = Random.new()
local traceStateKey = nil
local activeHazardStates = {}

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

local remotesFolder = getOrCreateRemotesFolder()
local killMeRemote = getOrCreateRemoteEvent(remotesFolder, "KillMe")
local legacyHazardRemote = remotesFolder:FindFirstChild(HAZARD_ACTION_REMOTE_NAME)
if legacyHazardRemote then
	legacyHazardRemote:Destroy()
end

killMeRemote.OnServerEvent:Connect(function(player)
	local character = player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		if HoroServer.IsProjecting(player) and character:GetAttribute("HoroProjectionGhost") == true then
			HoroServer.InterruptActiveProjection(player, "wave_touch")
			return
		end
		if MoguServer.IsProtected(player) then
			return
		end
		if ToriPassiveService.TryConsumeRebirth(player, "WaveKill") then
			return
		end
		humanoid.Health = 0
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

local function scaleHazardWidth(instance, widthScale)
	if math.abs(widthScale - 1) < 1e-3 then
		return
	end

	if instance:IsA("BasePart") then
		instance.Size = Vector3.new(instance.Size.X * widthScale, instance.Size.Y, instance.Size.Z)
		return
	end

	local rootPivot = instance:GetPivot()
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local relative = rootPivot:ToObjectSpace(descendant.CFrame)
			local relativePosition = relative.Position
			local relativeRotation = relative - relativePosition

			descendant.Size = Vector3.new(descendant.Size.X * widthScale, descendant.Size.Y, descendant.Size.Z)
			descendant.CFrame = rootPivot * CFrame.new(relativePosition.X * widthScale, relativePosition.Y, relativePosition.Z) * relativeRotation
		end
	end
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
	instance:SetAttribute("CanFreeze", true)
	instance:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)
end

local function chooseVariant()
	return CONFIG.Variants[rng:NextInteger(1, #CONFIG.Variants)]
end

local function chooseSpawnDelay()
	local minDelay = math.max(0.1, tonumber(CONFIG.SpawnDelayMin) or 2)
	local maxDelay = math.max(minDelay, tonumber(CONFIG.SpawnDelayMax) or minDelay)
	return rng:NextNumber(minDelay, maxDelay)
end

local function isValidActiveHazardState(hazardRoot, state)
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
	local controller = {
		HazardRoot = hazardRoot,
		Destroyed = false,
		FrozenUntil = 0,
		Alpha = 0,
		CurrentCFrame = startCF,
		Position = startCF.Position,
		VolumeSize = hazardSize,
		Width = hazardSize.X,
	}

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

			return {
				{
					Type = AffectableRegistry.VolumeType.Box,
					CFrame = entity.Controller.CurrentCFrame,
					Size = entity.Controller.VolumeSize,
					Padding = entity.Metadata and entity.Metadata.Padding or CONFIG.AffectablePadding,
				},
			}
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
		hazardTrace(
			"freeze applied hazard=%s duration=%.2f",
			formatInstancePath(self.HazardRoot),
			freezeDuration
		)
		return true
	end

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		activeHazardStates[self.HazardRoot] = nil
		AffectableRegistry.UnregisterEntity(self.AffectableEntityId)
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

	task.spawn(function()
		local alpha = 0

		if distance <= 1e-4 then
			controller.Alpha = 1
			controller.CurrentCFrame = endCF
			controller.Position = endCF.Position
			setPivot(hazardRoot, endCF)
			controller:Destroy()
			return
		end
		
		-- WAVE DRIFT CONFIG

		local driftStyle = rng:NextNumber() < 0.15 and "straight" or "drift"
		local maxDrift = math.max(0, tonumber(lateralDriftLimit) or 0) * math.max(1, tonumber(CONFIG.DriftStrengthMultiplier) or 1)
		local lateralOffset = 0
		local lateralVelocity = 0

		if driftStyle == "drift" and maxDrift > 1e-3 then
			local travelTime = distance / math.max(speed, 1e-3)
			local bounceCount = rng:NextInteger(3, 6)
			local minLateralSpeed = ((maxDrift * 2) / math.max(travelTime, 1e-3)) * math.max(1, tonumber(CONFIG.DriftSpeedMinMultiplier) or 1)
			local maxLateralSpeed = ((maxDrift * 2 * bounceCount) / math.max(travelTime, 1e-3)) * math.max(1, tonumber(CONFIG.DriftSpeedMaxMultiplier) or 1)

			lateralOffset = rng:NextNumber(-maxDrift, maxDrift)
			lateralVelocity = rng:NextNumber(minLateralSpeed, maxLateralSpeed)
			if rng:NextInteger(0, 1) == 0 then
				lateralVelocity = -lateralVelocity
			end
		end

		--ZIG ZAG

		while hazardRoot.Parent and not controller.Destroyed and alpha < 1 do
			local dt = RunService.Heartbeat:Wait()

			if os.clock() >= controller.FrozenUntil then
				alpha = math.min(alpha + (speed * dt) / distance, 1)
				controller.Alpha = alpha

				-- ✅ ZIGZAG: offset the wave 
				local currentCF = startCF:Lerp(endCF, alpha)
				if math.abs(lateralVelocity) > 1e-3 and maxDrift > 1e-3 then
					lateralOffset += lateralVelocity * dt

					while lateralOffset > maxDrift or lateralOffset < -maxDrift do
						if lateralOffset > maxDrift then
							lateralOffset = maxDrift - (lateralOffset - maxDrift)
							lateralVelocity = -math.abs(lateralVelocity)
						else
							lateralOffset = -maxDrift + (-maxDrift - lateralOffset)
							lateralVelocity = math.abs(lateralVelocity)
						end
					end

					currentCF = translateCFrame(currentCF, lateralDirection * lateralOffset)
				end

				controller.CurrentCFrame = currentCF
				controller.Position = currentCF.Position
				setPivot(hazardRoot, currentCF)
			end
		end

		controller.Alpha = 1
		controller.CurrentCFrame = endCF
		controller.Position = endCF.Position
		controller:Destroy()
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
	local clone = template:Clone()
	scaleHazardWidth(clone, variant.WidthScale)
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

	hazardTrace(
		"spawned waveFolder=%s variant=%s speed=%.2f activeHazardCount=%s maxActiveHazards=%s spawnDelay=%.2f waveWidth=%.2f leftBoundPos=%s rightBoundPos=%s corridorWidth=%.2f chosenOffset=%.2f finalSpawnPosition=%s finalEndPosition=%s hazard=%s",
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
		formatVector3(startCF.Position),
		formatVector3(endCF.Position),
		formatInstancePath(clone)
	)

	local lateralDriftLimit = math.max(0, safeHalfOffset - math.abs(chosenOffset))
	createServerHazardController(clone, startCF, endCF, variant.Speed, lateralDirection, lateralDriftLimit)
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
