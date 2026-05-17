local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))
local HazardRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local AffectableRegistry = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))
local HazardProtection = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("HazardProtection")
)

local CONFIG = {
	ActivationCycleDelay = 7,
	ActivationWaveDuration = 2.5,
	SpotLayoutSeed = 7351,
	ActivationShuffleSeed = 9137,
	MaxActiveSpikes = 180,
	LaneCount = 20,
	MinimumForwardAlpha = 0.14,
	MaximumForwardAlpha = 0.94,
	PlayerTargetChance = 0.55,
	PlayerTargetForwardJitter = 22,
	GroundProbeHeight = 120,
	GroundProbeDepth = 260,
	WarningTime = 3,
	ThrustTime = 0.12,
	HoldTime = 2.5,
	RetractTime = 0.16,
	PreviewHeight = 0.45,
	SpikeHeight = 7,
	SpikeLength = 18,
	LaneWidthScale = 0.82,
	WarningGroundOffset = 0.25,
	HazardClass = "minor",
	HazardType = "deck_spikes",
	FreezeBehavior = "pause",
	FreezeDurationFallback = 1.25,
	Damage = 65,
	KnockdownDuration = 0.8,
	AffectablePadding = Vector3.new(0.8, 0.8, 0.8),
	SpikeTrapFolderName = "Spike Traps",
	UseSpikeTrapTemplates = true,
	UseFixedSpikeSpots = true,
	RequireFixedSpikeSpots = true,
	InitialSpawnDelay = 3,
	IgnoreNoDisastersTimerInStudio = true,
	ShowFixedSpikeSpotMarkersInStudio = false,
	FixedSpikeSpotMarkerSize = Vector3.new(1.2, 0.12, 1.2),
	BiomeCount = 8,
	GeneratedFixedSpotsPerBiome = 40,
	ActiveSpotsPerBiome = 20,
	GeneratedFixedSpotBiomePadding = 0.08,
	GeneratedSpotMinDistance = 12,
	GeneratedSpotMaxAttemptsPerSpot = 80,
	FixedSpikeSpotFolderNames = { "DeckSpikeSpots", "SpikeSpots", "SpikeAttackSpots" },
	DefaultFixedSpikeSpotSize = Vector3.new(18, 7, 18),
	FixedSpikePositions = {},
	SafeGapBuffer = 12,
	SafeFloorNameKeywords = {
		"gap",
		"safe",
		"safezone",
		"refuge",
		"hub",
		"lobby",
		"no spike",
		"nospike",
		"no_spike",
	},
}

local rng = Random.new()
local activeControllers = {}
local fixedSpotCursor = 0
local fixedSpotMarkerSignature = nil
local fixedSpotCacheKey = nil
local fixedSpotCache = nil
local lastTraceStateKey = nil
local warnedSpikeTemplateMessages = {}
local DEBUG_TRACE = RunService:IsStudio() and game:GetAttribute("DeckSpikesDebugTrace") == true
local spawnAttemptSerial = 0

local function trace(message, ...)
	if DEBUG_TRACE then
		print(string.format("[DECK SPIKES] " .. message, ...))
	end
end

local function studioInfo(message, ...)
	if RunService:IsStudio() then
		print(string.format("[DECK SPIKES] " .. message, ...))
	end
end

local function warnSpikeTemplateOnce(key, message, ...)
	if warnedSpikeTemplateMessages[key] then
		return
	end

	warnedSpikeTemplateMessages[key] = true
	warn(string.format("[DECK SPIKES] " .. message, ...))
end

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

local function getNoDisastersTimer()
	local timer = Workspace:FindFirstChild("NoDisastersTimer")
	if timer and timer:IsA("ValueBase") then
		return timer
	end

	return nil
end

local function isNoDisastersPaused(timer)
	if RunService:IsStudio() and CONFIG.IgnoreNoDisastersTimerInStudio == true then
		return false
	end

	return timer and timer.Value > 0
end

local function configurePart(part, canTouch, canQuery)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = canTouch == true
	part.CanQuery = canQuery == true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)
end

local function createPart(parent, name, size, cframeValue, color, material, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframeValue
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	configurePart(part, false, false)
	part.Parent = parent
	return part
end

local function createWedgePart(parent, name, size, cframeValue, color, material, transparency)
	local part = Instance.new("WedgePart")
	part.Name = name
	part.Size = size
	part.CFrame = cframeValue
	part.Color = color
	part.Material = material or Enum.Material.Metal
	part.Transparency = transparency or 0
	configurePart(part, false, false)
	part.Parent = parent
	return part
end

local function getBaseParts(instance)
	local parts = {}
	if not instance then
		return parts
	end

	if instance:IsA("BasePart") then
		parts[#parts + 1] = instance
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end

	return parts
end

local function getPlanarUnit(vector, fallback)
	local planar = typeof(vector) == "Vector3" and Vector3.new(vector.X, 0, vector.Z) or Vector3.zero
	if planar.Magnitude > 1e-4 then
		return planar.Unit
	end

	local fallbackPlanar = typeof(fallback) == "Vector3" and Vector3.new(fallback.X, 0, fallback.Z) or Vector3.zero
	if fallbackPlanar.Magnitude > 1e-4 then
		return fallbackPlanar.Unit
	end

	return Vector3.new(0, 0, -1)
end

local function getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
	local lateral = getPlanarUnit(forward:Cross(Vector3.yAxis), Vector3.xAxis)
	local corridorCenter = (startPart.Position + endPart.Position) * 0.5
	local corridorWidth = 36

	if leftBound and rightBound then
		lateral = getPlanarUnit(rightBound.Position - leftBound.Position, lateral)
		corridorCenter = (leftBound.Position + rightBound.Position) * 0.5
		corridorWidth = math.max(6, (rightBound.Position - leftBound.Position).Magnitude)
	end

	return forward, lateral, corridorCenter, corridorWidth
end

local function buildFixedSpotCacheKey(refs, startPart, endPart, leftBound, rightBound)
	return table.concat({
		tostring(refs and refs.ActiveMapName),
		formatInstancePath(refs and refs.MapRoot),
		formatInstancePath(refs and refs.WaveFolder),
		formatVector3(startPart and startPart.Position or nil),
		formatVector3(endPart and endPart.Position or nil),
		formatVector3(leftBound and leftBound.Position or nil),
		formatVector3(rightBound and rightBound.Position or nil),
		tostring(CONFIG.BiomeCount),
		tostring(CONFIG.GeneratedFixedSpotsPerBiome),
		tostring(CONFIG.ActiveSpotsPerBiome),
		tostring(CONFIG.SpotLayoutSeed),
		tostring(CONFIG.GeneratedSpotMinDistance),
		tostring(CONFIG.GeneratedSpotMaxAttemptsPerSpot),
	}, "|")
end

local function planarDistance(a, b)
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return math.huge
	end

	local delta = Vector3.new(a.X - b.X, 0, a.Z - b.Z)
	return delta.Magnitude
end

local function shuffleArray(values, randomSource)
	for index = #values, 2, -1 do
		local swapIndex = randomSource:NextInteger(1, index)
		values[index], values[swapIndex] = values[swapIndex], values[index]
	end
end

local function resolveRefs()
	local refs = MapResolver.WaitForRefs(
		{ "MapRoot", "WaveFolder", "WaveStart", "WaveEnd" },
		nil,
		{
			warn = true,
			context = "DeckSpikes",
		}
	)

	local waveFolder = refs.WaveFolder
	local hazardsFolder = waveFolder and waveFolder:FindFirstChild("Hazards") or nil
	if waveFolder and not hazardsFolder then
		hazardsFolder = Instance.new("Folder")
		hazardsFolder.Name = "Hazards"
		hazardsFolder.Parent = waveFolder
	end

	local leftBound = waveFolder and waveFolder:FindFirstChild("LeftBound") or nil
	local rightBound = waveFolder and waveFolder:FindFirstChild("RightBound") or nil
	local stateKey = table.concat({
		tostring(refs.RequestedMapName),
		tostring(refs.ActiveMapName),
		formatInstancePath(waveFolder),
		formatInstancePath(hazardsFolder),
		formatInstancePath(refs.WaveStart),
		formatInstancePath(refs.WaveEnd),
		formatInstancePath(leftBound),
		formatInstancePath(rightBound),
	}, "|")

	if lastTraceStateKey ~= stateKey then
		lastTraceStateKey = stateKey
		trace(
			"resolved waveFolder=%s hazardsFolder=%s start=%s end=%s left=%s right=%s",
			formatInstancePath(waveFolder),
			formatInstancePath(hazardsFolder),
			formatInstancePath(refs.WaveStart),
			formatInstancePath(refs.WaveEnd),
			formatInstancePath(leftBound),
			formatInstancePath(rightBound)
		)
	end

	return refs, waveFolder, hazardsFolder, refs.WaveStart, refs.WaveEnd, leftBound, rightBound
end

local function buildGroundRaycastParams(refs)
	local exclusions = {}
	if refs and refs.WaveFolder then
		local hazardsFolder = refs.WaveFolder:FindFirstChild("Hazards")
		if hazardsFolder then
			exclusions[#exclusions + 1] = hazardsFolder
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			exclusions[#exclusions + 1] = player.Character
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = exclusions
	raycastParams.IgnoreWater = false
	return raycastParams
end

local function isUnsafeSpikeSurface(instance)
	if not instance then
		return true
	end

	local current = instance
	while current do
		if current:GetAttribute("BombSafe") == true
			or current:GetAttribute("SafeZone") == true
			or current:GetAttribute("IsSafeZone") == true
			or current:GetAttribute("NoSpikes") == true
			or current:GetAttribute("NoSpike") == true
		then
			return true
		end

		local name = string.lower(current.Name)
		for _, keyword in ipairs(CONFIG.SafeFloorNameKeywords or {}) do
			if name:find(keyword, 1, true) then
				return true
			end
		end

		if name:find("spawn", 1, true) or name:find("barrier", 1, true) or name:find("vip", 1, true) then
			return true
		end

		current = current.Parent
	end

	return false
end

local function raycastGround(position, refs)
	local height = math.max(10, tonumber(CONFIG.GroundProbeHeight) or 120)
	local depth = math.max(height + 10, tonumber(CONFIG.GroundProbeDepth) or 260)
	local result = Workspace:Raycast(
		position + Vector3.new(0, height, 0),
		Vector3.new(0, -depth, 0),
		buildGroundRaycastParams(refs)
	)

	if result and not isUnsafeSpikeSurface(result.Instance) then
		return result.Position
	end

	return nil
end

local function isNearSafeSpikeGap(position, refs, forward, lateral, size)
	local forwardUnit = getPlanarUnit(forward, Vector3.zAxis)
	local lateralUnit = getPlanarUnit(lateral, Vector3.xAxis)
	local buffer = math.max(0, tonumber(CONFIG.SafeGapBuffer) or 0)
	if buffer <= 0 then
		return false
	end

	local footprintX = math.max(2, typeof(size) == "Vector3" and size.X or 0)
	local footprintZ = math.max(2, typeof(size) == "Vector3" and size.Z or 0)
	local sampleX = math.max(buffer, (footprintX * 0.5) + buffer)
	local sampleZ = math.max(buffer, (footprintZ * 0.5) + buffer)
	for _, offset in ipairs({
		Vector3.zero,
		forwardUnit * sampleZ,
		-forwardUnit * sampleZ,
		lateralUnit * sampleX,
		-lateralUnit * sampleX,
		lateralUnit * sampleX + forwardUnit * sampleZ,
		lateralUnit * -sampleX + forwardUnit * sampleZ,
		lateralUnit * sampleX + forwardUnit * -sampleZ,
		lateralUnit * -sampleX + forwardUnit * -sampleZ,
	}) do
		if not raycastGround(position + offset, refs) then
			return true
		end
	end

	return false
end

local function resolveSafeSpikeGroundPosition(position, refs, lateral, forward, size)
	local centerPosition = raycastGround(position, refs)
	if not centerPosition then
		return nil
	end

	if isNearSafeSpikeGap(centerPosition, refs, forward, lateral, size) then
		return nil
	end

	local footprintX = math.max(2, typeof(size) == "Vector3" and size.X or 0)
	local footprintZ = math.max(2, typeof(size) == "Vector3" and size.Z or 0)
	local lateralUnit = getPlanarUnit(lateral, Vector3.xAxis)
	local forwardUnit = getPlanarUnit(forward, Vector3.zAxis)
	local sampleX = math.max(1, footprintX * 0.42)
	local sampleZ = math.max(1, footprintZ * 0.42)
	local maxHeightDelta = math.max(2, (typeof(size) == "Vector3" and size.Y or CONFIG.SpikeHeight) * 0.5)
	local sampleOffsets = {
		lateralUnit * sampleX + forwardUnit * sampleZ,
		lateralUnit * -sampleX + forwardUnit * sampleZ,
		lateralUnit * sampleX + forwardUnit * -sampleZ,
		lateralUnit * -sampleX + forwardUnit * -sampleZ,
	}

	for _, offset in ipairs(sampleOffsets) do
		local samplePosition = raycastGround(position + offset, refs)
		if not samplePosition or math.abs(samplePosition.Y - centerPosition.Y) > maxHeightDelta then
			return nil
		end
	end

	return centerPosition
end

local function getCharacterContext(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil
	end

	return character, humanoid, rootPart
end

local function chooseAlivePlayer()
	local candidates = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if getCharacterContext(player) then
			candidates[#candidates + 1] = player
		end
	end

	if #candidates == 0 then
		return nil
	end

	return candidates[rng:NextInteger(1, #candidates)]
end

local function findFixedSpikeSpotFolder(refs)
	if CONFIG.UseFixedSpikeSpots ~= true then
		return nil
	end

	local folderNames = CONFIG.FixedSpikeSpotFolderNames
	if type(folderNames) ~= "table" then
		folderNames = { "DeckSpikeSpots" }
	end

	local roots = {
		refs and refs.WaveFolder,
		refs and refs.ActiveMapRoot,
		refs and refs.MapRoot,
		refs and refs.ActiveMapContainer,
		Workspace,
	}

	for _, root in ipairs(roots) do
		if root then
			for _, folderName in ipairs(folderNames) do
				local folder = root:FindFirstChild(tostring(folderName), true)
				if folder then
					return folder
				end
			end
		end
	end

	return nil
end

local function addConfiguredFixedSpikeSpots(spots)
	for index, spotConfig in ipairs(CONFIG.FixedSpikePositions or {}) do
		local position
		local cframeValue
		local size
		local biomeIndex
		local snapToGround = false

		if typeof(spotConfig) == "Vector3" then
			position = spotConfig
			cframeValue = CFrame.new(spotConfig)
		elseif typeof(spotConfig) == "CFrame" then
			position = spotConfig.Position
			cframeValue = spotConfig
		elseif type(spotConfig) == "table" then
			position = spotConfig.Position
			cframeValue = spotConfig.CFrame or (position and CFrame.new(position))
			size = spotConfig.Size
			biomeIndex = tonumber(spotConfig.BiomeIndex)
			snapToGround = spotConfig.SnapToGround == true
		end

		if typeof(position) == "Vector3" then
			spots[#spots + 1] = {
				Position = position,
				CFrame = cframeValue or CFrame.new(position),
				Size = if typeof(size) == "Vector3" then size else CONFIG.DefaultFixedSpikeSpotSize,
				BiomeIndex = biomeIndex,
				SourceName = string.format("CONFIG.FixedSpikePositions[%d]", index),
				SnapToGround = snapToGround,
			}
		end
	end
end

local function addFolderFixedSpikeSpots(spots, refs)
	local folder = findFixedSpikeSpotFolder(refs)
	if not folder then
		return
	end

	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Disabled") ~= true then
			spots[#spots + 1] = {
				Position = descendant.Position,
				CFrame = descendant.CFrame,
				Size = descendant.Size,
				BiomeIndex = tonumber(descendant:GetAttribute("BiomeIndex")),
				Source = descendant,
				SnapToGround = descendant:GetAttribute("SnapToGround") ~= false,
			}
		end
	end
end

local function addGeneratedBiomeFixedSpikeSpots(spots, refs, startPart, endPart, leftBound, rightBound)
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local spotsPerBiome = math.max(0, math.floor(tonumber(CONFIG.GeneratedFixedSpotsPerBiome) or 10))
	if spotsPerBiome <= 0 then
		return
	end

	local forward, lateral, corridorCenter, corridorWidth = getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local pathDelta = endPart.Position - startPart.Position
	local pathLength = pathDelta:Dot(forward)
	if pathLength < 0 then
		forward = -forward
		pathLength = -pathLength
	end
	pathLength = math.max(1, pathLength)

	local laneCount = math.max(1, math.floor(tonumber(CONFIG.LaneCount) or 5))
	local laneWidth = math.max(4, corridorWidth / laneCount)
	local safeHalfWidth = math.max(0, (corridorWidth * 0.5) - (laneWidth * 0.5))
	local width = laneWidth * math.clamp(tonumber(CONFIG.LaneWidthScale) or 0.82, 0.25, 1)
	local length = math.max(4, tonumber(CONFIG.SpikeLength) or 18)
	local spotSize = Vector3.new(width, CONFIG.SpikeHeight, length)
	local biomePadding = math.clamp(tonumber(CONFIG.GeneratedFixedSpotBiomePadding) or 0.08, 0, 0.35)
	local minDistance = math.max(0, tonumber(CONFIG.GeneratedSpotMinDistance) or 12)
	local maxAttemptsPerSpot = math.max(5, math.floor(tonumber(CONFIG.GeneratedSpotMaxAttemptsPerSpot) or 80))
	local layoutSeed = math.floor(tonumber(CONFIG.SpotLayoutSeed) or 7351)

	for biomeIndex = 1, biomeCount do
		local biomeSpots = {}
		local randomSource = Random.new(layoutSeed + (biomeIndex * 104729))
		local biomeStartAlpha = (biomeIndex - 1) / biomeCount
		local biomeEndAlpha = biomeIndex / biomeCount
		local usableStartAlpha = biomeStartAlpha + ((biomeEndAlpha - biomeStartAlpha) * biomePadding)
		local usableEndAlpha = biomeEndAlpha - ((biomeEndAlpha - biomeStartAlpha) * biomePadding)

		for spotIndex = 1, spotsPerBiome do
			local chosenPosition = nil
			local chosenCFrame = nil

			for attempt = 1, maxAttemptsPerSpot do
				local forwardAlpha = randomSource:NextNumber(usableStartAlpha, usableEndAlpha)
				local laneOffset = randomSource:NextNumber(-safeHalfWidth, safeHalfWidth)
				local centerOnPath = startPart.Position + (forward * pathLength * forwardAlpha)
				local centerProjection = corridorCenter:Dot(lateral)
				local pathProjection = centerOnPath:Dot(lateral)
				local planarPosition = centerOnPath + (lateral * (centerProjection - pathProjection + laneOffset))
				local groundPosition = resolveSafeSpikeGroundPosition(planarPosition, refs, lateral, forward, spotSize)
				if not groundPosition then
					continue
				end
				local tooClose = false

				for _, existingSpot in ipairs(biomeSpots) do
					if planarDistance(existingSpot.Position, groundPosition) < minDistance then
						tooClose = true
						break
					end
				end

				if not tooClose or attempt == maxAttemptsPerSpot then
					chosenPosition = groundPosition
					chosenCFrame = CFrame.fromMatrix(groundPosition, lateral, Vector3.yAxis, -forward)
					break
				end
			end

			if not chosenPosition or not chosenCFrame then
				warnSpikeTemplateOnce(
					string.format("missing_safe_spike_spot_%d_%d", biomeIndex, spotIndex),
					"Could not find safe non-gap spike spot for biome=%d spot=%d; reducing generated spots for this biome.",
					biomeIndex,
					spotIndex
				)
				break
			end

			local spot = {
				Position = chosenPosition,
				CFrame = chosenCFrame,
				Size = spotSize,
				BiomeIndex = biomeIndex,
				SpotInBiome = spotIndex,
				SourceName = string.format("generated biome %d spot %d", biomeIndex, spotIndex),
				SnapToGround = false,
			}
			biomeSpots[#biomeSpots + 1] = spot
		end

		shuffleArray(biomeSpots, randomSource)
		for spotIndex, spot in ipairs(biomeSpots) do
			spot.SpotInBiome = spotIndex
			spot.SourceName = string.format("generated biome %d spot %d", biomeIndex, spotIndex)
			spots[#spots + 1] = spot
		end
	end
end

local function ensureFixedSpikeSpotMarkers(spots)
	if not (RunService:IsStudio() and CONFIG.ShowFixedSpikeSpotMarkersInStudio == true) then
		local existingFolder = Workspace:FindFirstChild("DeckSpikeSpotMarkers")
		if existingFolder then
			existingFolder:Destroy()
		end
		return
	end

	local signature = tostring(#spots)
	for index, spot in ipairs(spots) do
		signature ..= string.format("|%.1f,%.1f,%.1f", spot.Position.X, spot.Position.Y, spot.Position.Z)
		if index >= 8 then
			break
		end
	end

	if fixedSpotMarkerSignature == signature then
		return
	end
	fixedSpotMarkerSignature = signature

	local folder = Workspace:FindFirstChild("DeckSpikeSpotMarkers")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "DeckSpikeSpotMarkers"
		folder.Parent = Workspace
	else
		folder:ClearAllChildren()
	end

	for index, spot in ipairs(spots) do
		local marker = Instance.new("Part")
		marker.Name = string.format("SpikeSpot_%03d_Biome_%s", index, tostring(spot.BiomeIndex or "?"))
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.CastShadow = false
		marker.Material = Enum.Material.Neon
		marker.Transparency = 0.65
		marker.Color = if (spot.BiomeIndex or 1) == 1 then Color3.fromRGB(255, 235, 80) else Color3.fromRGB(60, 190, 255)
		marker.Size = CONFIG.FixedSpikeSpotMarkerSize
		marker.CFrame = CFrame.fromMatrix(
			spot.Position + Vector3.new(0, 0.35, 0),
			getPlanarUnit(spot.CFrame.RightVector, Vector3.xAxis),
			Vector3.yAxis,
			-getPlanarUnit(spot.CFrame.LookVector, Vector3.zAxis)
		)
		marker.Parent = folder
	end

	studioInfo("created %d visible fixed spike spot markers in Workspace.DeckSpikeSpotMarkers", #spots)
end

local function createGeneratedSpikeVisual(placement, hitboxCFrame)
	local visualModel = Instance.new("Model")
	visualModel.Name = "GeneratedSpikeTrapVisual"

	local hitbox = createPart(
		visualModel,
		"Hitbox",
		placement.Size,
		hitboxCFrame,
		Color3.fromRGB(255, 0, 0),
		Enum.Material.SmoothPlastic,
		1
	)
	configurePart(hitbox, true, true)
	hitbox:SetAttribute("HazardClass", CONFIG.HazardClass)
	hitbox:SetAttribute("HazardType", CONFIG.HazardType)
	hitbox:SetAttribute("CanFreeze", true)
	hitbox:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)

	local footprintX = math.max(2, placement.Size.X)
	local footprintZ = math.max(2, placement.Size.Z)
	local spikeHeight = math.max(2, placement.Size.Y)
	local spikeCount = 5
	local step = footprintX / spikeCount

	for index = 1, spikeCount do
		local xOffset = ((index - 0.5) / spikeCount - 0.5) * footprintX
		local spikeWidth = math.max(1.2, step * 0.62)
		local spikeDepth = math.max(2, footprintZ * 0.82)
		local spikeCFrame = hitboxCFrame
			* CFrame.new(xOffset, 0, 0)
			* CFrame.Angles(0, math.rad(90), 0)
		createWedgePart(
			visualModel,
			string.format("Spike_%02d", index),
			Vector3.new(spikeDepth, spikeHeight, spikeWidth),
			spikeCFrame,
			Color3.fromRGB(75, 76, 82),
			Enum.Material.Metal,
			0
		)
	end

	return visualModel, hitbox
end

local function getFixedSpikeSpots(refs, startPart, endPart, leftBound, rightBound)
	local cacheKey = buildFixedSpotCacheKey(refs, startPart, endPart, leftBound, rightBound)
	if fixedSpotCacheKey == cacheKey and fixedSpotCache then
		return fixedSpotCache
	end

	local spots = {}

	addFolderFixedSpikeSpots(spots, refs)
	addConfiguredFixedSpikeSpots(spots)
	addGeneratedBiomeFixedSpikeSpots(spots, refs, startPart, endPart, leftBound, rightBound)
	ensureFixedSpikeSpotMarkers(spots)

	fixedSpotCacheKey = cacheKey
	fixedSpotCache = spots
	return spots
end

local function chooseFixedSpikePlacement(refs, startPart, endPart, leftBound, rightBound, options)
	local spots = getFixedSpikeSpots(refs, startPart, endPart, leftBound, rightBound)
	if #spots == 0 then
		return nil
	end

	local spot
	if options and options.BiomeIndex and options.SpotInBiome then
		local requestedBiomeIndex = tonumber(options.BiomeIndex)
		local requestedSpotInBiome = tonumber(options.SpotInBiome)
		for _, candidate in ipairs(spots) do
			if candidate.BiomeIndex == requestedBiomeIndex and candidate.SpotInBiome == requestedSpotInBiome then
				spot = candidate
				break
			end
		end
		if not spot then
			return nil
		end
	elseif options and options.SpotIndex then
		spot = spots[((options.SpotIndex - 1) % #spots) + 1]
	else
		fixedSpotCursor = (fixedSpotCursor % #spots) + 1
		spot = spots[fixedSpotCursor]
	end
	local forward = getPlanarUnit(spot.CFrame.LookVector, endPart.Position - startPart.Position)
	local lateral = getPlanarUnit(spot.CFrame.RightVector, forward:Cross(Vector3.yAxis))
	local size = spot.Size
	local safeGroundPosition = resolveSafeSpikeGroundPosition(spot.Position, refs, lateral, forward, size)
	if not safeGroundPosition then
		return nil
	end
	local groundPosition = if spot.SnapToGround then safeGroundPosition else spot.Position

	studioInfo(
		"fixed spot selected spot=%s pos=%s",
		spot.Source and formatInstancePath(spot.Source) or tostring(spot.SourceName or "<configured>"),
		formatVector3(groundPosition)
	)

	return {
		GroundPosition = groundPosition,
		Forward = forward,
		Lateral = lateral,
		Size = Vector3.new(math.max(1, size.X), math.max(1, size.Y), math.max(1, size.Z)),
		Spot = spot.Source,
		SourceName = spot.SourceName,
		BiomeIndex = spot.BiomeIndex,
		SpotInBiome = spot.SpotInBiome,
		IsFixedSpot = true,
	}
end

local function chooseSpikePlacement(refs, startPart, endPart, leftBound, rightBound, options)
	local fixedPlacement = chooseFixedSpikePlacement(refs, startPart, endPart, leftBound, rightBound, options)
	if fixedPlacement then
		return fixedPlacement
	end

	if CONFIG.UseFixedSpikeSpots == true and CONFIG.RequireFixedSpikeSpots == true then
		warnSpikeTemplateOnce(
			"missing_fixed_spots",
			"No fixed deck spike spots were found. Add parts under a DeckSpikeSpots/SpikeSpots folder, or add Vector3 entries to CONFIG.FixedSpikePositions."
		)
		return nil
	end

	local forward, lateral, corridorCenter, corridorWidth = getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local pathDelta = endPart.Position - startPart.Position
	local pathLength = math.max(1, pathDelta.Magnitude)
	local laneCount = math.max(1, math.floor(tonumber(CONFIG.LaneCount) or 5))
	local laneWidth = math.max(4, corridorWidth / laneCount)
	local safeHalfWidth = math.max(0, (corridorWidth * 0.5) - (laneWidth * 0.5))
	local targetPlayer = rng:NextNumber() < CONFIG.PlayerTargetChance and chooseAlivePlayer() or nil
	local forwardDistance
	local laneOffset

	if targetPlayer then
		local _, _, rootPart = getCharacterContext(targetPlayer)
		if rootPart then
			local startProjection = startPart.Position:Dot(forward)
			forwardDistance = math.clamp(
				rootPart.Position:Dot(forward) - startProjection + rng:NextNumber(-CONFIG.PlayerTargetForwardJitter, CONFIG.PlayerTargetForwardJitter),
				pathLength * CONFIG.MinimumForwardAlpha,
				pathLength * CONFIG.MaximumForwardAlpha
			)

			local centerProjection = corridorCenter:Dot(lateral)
			local rawOffset = rootPart.Position:Dot(lateral) - centerProjection
			local laneIndex = math.clamp(math.floor((rawOffset + corridorWidth * 0.5) / laneWidth) + 1, 1, laneCount)
			laneOffset = ((laneIndex - 0.5) / laneCount - 0.5) * corridorWidth
			laneOffset = math.clamp(laneOffset, -safeHalfWidth, safeHalfWidth)
		end
	end

	if not forwardDistance then
		forwardDistance = pathLength * rng:NextNumber(CONFIG.MinimumForwardAlpha, CONFIG.MaximumForwardAlpha)
	end

	if not laneOffset then
		local laneIndex = rng:NextInteger(1, laneCount)
		laneOffset = ((laneIndex - 0.5) / laneCount - 0.5) * corridorWidth
		laneOffset = math.clamp(laneOffset, -safeHalfWidth, safeHalfWidth)
	end

	local width = laneWidth * math.clamp(tonumber(CONFIG.LaneWidthScale) or 0.82, 0.25, 1)
	local length = math.max(4, tonumber(CONFIG.SpikeLength) or 18)
	local size = Vector3.new(width, CONFIG.SpikeHeight, length)
	local planarPosition = startPart.Position + (forward * forwardDistance) + (lateral * laneOffset)
	local groundPosition = resolveSafeSpikeGroundPosition(planarPosition, refs, lateral, forward, size)
	if not groundPosition then
		return nil
	end

	return {
		GroundPosition = groundPosition,
		Forward = forward,
		Lateral = lateral,
		Size = size,
	}
end

local SPIKE_TEMPLATE_NAMES_BY_AREA = {
	["foosha village"] = "(FOOSHA) WOODEN SPIKE TRAP",
	["arlong park"] = "(ARLONG PARK) BONE SPIKE TRAP",
	["drum island"] = "(DRUM ISLAND) ICE SPIKE TRAP",
	["alabasta"] = "(ALABASTA) SAND SPIKE TRAP",
	["water 7"] = "(WATER 7) STEEL SPIKE TRAP",
	["thriller bark"] = "(THRILLER BARK) SHADOW SPIKE TRAP",
	["sabaody"] = "(SABAODY) MANGROVE SPIKE TRAP",
	["dressrosa"] = "DRESSROSA SPIKE TRAP",
	["dresserosa"] = "DRESSROSA SPIKE TRAP",
}

local SPIKE_TEMPLATE_TOKENS_BY_AREA = {
	["foosha village"] = { "foosha", "wooden" },
	["arlong park"] = { "arlong", "bone" },
	["drum island"] = { "drum", "ice" },
	["alabasta"] = { "alabasta", "sand" },
	["water 7"] = { "water 7", "steel" },
	["thriller bark"] = { "thriller", "shadow" },
	["sabaody"] = { "sabaody", "mangrove" },
	["dressrosa"] = { "dressrosa", "dresserosa" },
	["dresserosa"] = { "dresserosa", "dressrosa" },
}

local function getAreaNameForPosition(startPart, endPart, position)
	local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
	local total = math.max(1, math.abs((endPart.Position - startPart.Position):Dot(forward)))
	local alpha = math.clamp(math.abs((position - startPart.Position):Dot(forward)) / total, 0, 0.999)
	local biomeIndex = math.clamp(math.floor(alpha * 8) + 1, 1, 8)
	local entry = BiomeAreas.GetBiome and BiomeAreas.GetBiome(biomeIndex)

	return entry and entry.AreaName or nil
end

local function findSpikeTrapFolder()
	local folderNames = {
		CONFIG.SpikeTrapFolderName,
		"SpikeTraps",
		"Spike Traps",
		"SpikeTrapsFolder",
	}

	for _, root in ipairs({ ServerStorage, ReplicatedStorage, Workspace }) do
		for _, folderName in ipairs(folderNames) do
			local folder = root:FindFirstChild(folderName, true)
			if folder then
				studioInfo("template folder found path=%s", formatInstancePath(folder))
				return folder
			end
		end
	end

	warnSpikeTemplateOnce(
		"missing_folder",
		"Could not find a spike template folder named %s in ServerStorage, ReplicatedStorage, or Workspace.",
		tostring(CONFIG.SpikeTrapFolderName)
	)
	return nil
end

local function publishSpawnStatus(hazardsFolder, result, detail, activeCount, spotCount)
	if not hazardsFolder then
		return
	end

	hazardsFolder:SetAttribute("DeckSpikesEnabled", true)
	hazardsFolder:SetAttribute("DeckSpikesLastAttempt", spawnAttemptSerial)
	hazardsFolder:SetAttribute("DeckSpikesLastResult", tostring(result or "unknown"))
	hazardsFolder:SetAttribute("DeckSpikesLastDetail", tostring(detail or ""))
	hazardsFolder:SetAttribute("DeckSpikesActiveCount", tonumber(activeCount) or 0)
	hazardsFolder:SetAttribute("DeckSpikesSpotCount", tonumber(spotCount) or 0)
	hazardsFolder:SetAttribute("DeckSpikesLastServerTime", Workspace:GetServerTimeNow())
end

local function findHitbox(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and string.lower(descendant.Name) == "hitbox" then
			return descendant
		end
	end

	return nil
end

local function hasBasePart(instance)
	if instance:IsA("BasePart") then
		return true
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return true
		end
	end

	return false
end

local function findSpikeTrapTemplate(areaName)
	local folder = findSpikeTrapFolder()
	if not folder then
		return nil
	end

	local key = string.lower(tostring(areaName or ""))
	local modelCandidates = {}
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Model") then
			modelCandidates[#modelCandidates + 1] = descendant
		end
	end

	local templateName = SPIKE_TEMPLATE_NAMES_BY_AREA[key]
	if templateName then
		local template = folder:FindFirstChild(templateName, true)
		if template and template:IsA("Model") then
			studioInfo("template matched exact area=%s template=%s", tostring(areaName), formatInstancePath(template))
			return template
		end
	end

	if key ~= "" then
		for _, candidate in ipairs(modelCandidates) do
			local childName = string.lower(candidate.Name)
			if string.find(childName, key, 1, true) then
				studioInfo("template matched area name area=%s template=%s", tostring(areaName), formatInstancePath(candidate))
				return candidate
			end

			for _, token in ipairs(SPIKE_TEMPLATE_TOKENS_BY_AREA[key] or {}) do
				if string.find(childName, token, 1, true) then
					studioInfo("template matched token=%s area=%s template=%s", token, tostring(areaName), formatInstancePath(candidate))
					return candidate
				end
			end
		end
	end

	for _, candidate in ipairs(modelCandidates) do
		if findHitbox(candidate) then
			studioInfo("template matched fallback hitbox area=%s template=%s", tostring(areaName), formatInstancePath(candidate))
			return candidate
		end
	end

	for _, candidate in ipairs(modelCandidates) do
		if hasBasePart(candidate) then
			studioInfo("template matched fallback model area=%s template=%s", tostring(areaName), formatInstancePath(candidate))
			return candidate
		end
	end

	warnSpikeTemplateOnce(
		"missing_template_" .. key,
		"Could not find a spike template for area=%s inside %s.",
		tostring(areaName),
		formatInstancePath(folder)
	)
	return nil
end

local function getOrCreateTemplateHitbox(model)
	local hitbox = findHitbox(model)
	if hitbox then
		return hitbox, false
	end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(
		math.max(1, boundsSize.X),
		math.max(1, boundsSize.Y),
		math.max(1, boundsSize.Z)
	)
	hitbox.CFrame = boundsCFrame
	hitbox.Parent = model

	return hitbox, true
end

local function configureSpikeTrapModel(model, hitbox)
	for _, part in ipairs(getBaseParts(model)) do
		configurePart(part, part == hitbox, part == hitbox)
		if part == hitbox then
			part.Transparency = 1
			part:SetAttribute("HazardClass", CONFIG.HazardClass)
			part:SetAttribute("HazardType", CONFIG.HazardType)
			part:SetAttribute("CanFreeze", true)
			part:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)
		elseif part.Transparency >= 0.98 then
			part.Transparency = 0
		end
	end
end

local function setSpikeVisualFrozen(controller, isFrozen)
	local color = if isFrozen then Color3.fromRGB(178, 235, 255) else Color3.fromRGB(72, 72, 78)
	local material = if isFrozen then Enum.Material.Ice else Enum.Material.Metal
	if controller.VisualModel and controller.VisualModel.Parent then
		for _, part in ipairs(getBaseParts(controller.VisualModel)) do
			if part ~= controller.Spike then
				local original = controller.VisualDefaults and controller.VisualDefaults[part]
				part.Color = if isFrozen then color else (original and original.Color or part.Color)
				part.Material = if isFrozen then material else (original and original.Material or part.Material)
			end
		end
	elseif controller.Spike and controller.Spike.Parent then
		controller.Spike.Color = color
		controller.Spike.Material = material
	end
	if controller.Warning and controller.Warning.Parent then
		controller.Warning.Color = if isFrozen then Color3.fromRGB(196, 240, 255) else Color3.fromRGB(255, 45, 35)
	end
end

local function unregisterController(controller)
	activeControllers[controller.Model] = nil
	if controller.AffectableEntity then
		AffectableRegistry.UnregisterEntity(controller.AffectableEntity)
		controller.AffectableEntity = nil
	end
	HazardRuntime.Unregister(controller.Model)
end

local function buildHazardVolumes(controller)
	if controller.Destroyed or not controller.Active or not controller.Spike.Parent then
		return {}
	end

	return {
		{
			Type = AffectableRegistry.VolumeType.Box,
			Label = "DeckSpikes",
			CFrame = controller.Spike.CFrame,
			Size = controller.Spike.Size,
			Padding = CONFIG.AffectablePadding,
		},
	}
end

local function createController(model, spike, warning, visualModel)
	local visualDefaults = {}
	if visualModel then
		for _, part in ipairs(getBaseParts(visualModel)) do
			visualDefaults[part] = {
				Color = part.Color,
				Material = part.Material,
			}
		end
	end

	local controller = {
		Model = model,
		Spike = spike,
		Warning = warning,
		VisualModel = visualModel,
		VisualDefaults = visualDefaults,
		Destroyed = false,
		Active = false,
		FrozenUntil = 0,
		FreezeToken = 0,
		DamagedPlayers = {},
	}

	function controller:Freeze(duration)
		if self.Destroyed or not self.Model.Parent then
			return false
		end

		local freezeDuration = math.max(0, tonumber(duration) or CONFIG.FreezeDurationFallback)
		if freezeDuration <= 0 then
			return false
		end

		self.FrozenUntil = math.max(self.FrozenUntil, os.clock() + freezeDuration)
		self.FreezeToken += 1
		local freezeToken = self.FreezeToken
		setSpikeVisualFrozen(self, true)

		task.spawn(function()
			while not self.Destroyed and self.Model.Parent and os.clock() < self.FrozenUntil do
				task.wait(0.05)
			end

			if self.Destroyed or self.FreezeToken ~= freezeToken then
				return
			end

			setSpikeVisualFrozen(self, false)
		end)

		return true
	end

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		unregisterController(self)
		if self.Model.Parent then
			self.Model:Destroy()
		end
	end

	controller.AffectableEntity = AffectableRegistry.RegisterEntity({
		EntityType = AffectableRegistry.EntityType.Hazard,
		RootInstance = model,
		Controller = controller,
		Metadata = {
			HazardClass = CONFIG.HazardClass,
			HazardType = CONFIG.HazardType,
			CanFreeze = true,
			FreezeBehavior = CONFIG.FreezeBehavior,
		},
		IsActive = function(entity)
			return entity.Controller.Destroyed ~= true and model.Parent ~= nil
		end,
		CanBeAffectedBy = function()
			return true, "ok"
		end,
		GetVolumes = function(entity)
			return buildHazardVolumes(entity.Controller)
		end,
		ResolveData = function(entity, match)
			return {
				Label = formatInstancePath(model),
				Root = model,
				Controller = entity.Controller,
				HazardClass = CONFIG.HazardClass,
				HazardType = CONFIG.HazardType,
				CanFreeze = true,
				FreezeBehavior = CONFIG.FreezeBehavior,
				Position = spike.Position,
				HitPosition = match and match.HitPosition or nil,
				MatchSource = "volume",
			}
		end,
	})

	HazardRuntime.Register(model, controller)
	activeControllers[model] = controller
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			controller:Destroy()
		end
	end)

	return controller
end

local function waitWhileFrozen(controller, duration)
	local elapsed = 0
	while elapsed < duration do
		if controller.Destroyed or not controller.Model.Parent then
			return false
		end

		if os.clock() < controller.FrozenUntil then
			task.wait(0.05)
		else
			local dt = math.min(0.05, duration - elapsed)
			task.wait(dt)
			elapsed += dt
		end
	end

	return true
end

local function tweenPart(controller, part, tweenInfo, goals)
	if part:IsA("Model") then
		local cframeValue = Instance.new("CFrameValue")
		cframeValue.Value = part:GetPivot()
		local connection = cframeValue.Changed:Connect(function(value)
			if part.Parent then
				part:PivotTo(value)
			end
		end)
		local tween = TweenService:Create(cframeValue, tweenInfo, goals)
		tween:Play()

		local elapsed = 0
		while elapsed < tweenInfo.Time do
			if controller.Destroyed or not controller.Model.Parent then
				tween:Cancel()
				connection:Disconnect()
				cframeValue:Destroy()
				return false
			end

			if os.clock() < controller.FrozenUntil then
				tween:Pause()
				task.wait(0.05)
			else
				tween:Play()
				local dt = math.min(0.03, tweenInfo.Time - elapsed)
				task.wait(dt)
				elapsed += dt
			end
		end

		if part.Parent and goals.Value then
			part:PivotTo(goals.Value)
		end
		connection:Disconnect()
		cframeValue:Destroy()
		return true
	end

	local tween = TweenService:Create(part, tweenInfo, goals)
	tween:Play()

	local elapsed = 0
	while elapsed < tweenInfo.Time do
		if controller.Destroyed or not controller.Model.Parent then
			tween:Cancel()
			return false
		end

		if os.clock() < controller.FrozenUntil then
			tween:Pause()
			task.wait(0.05)
		else
			tween:Play()
			local dt = math.min(0.03, tweenInfo.Time - elapsed)
			task.wait(dt)
			elapsed += dt
		end
	end

	return true
end

local function isPointInsideSpike(spike, worldPosition)
	local localPosition = spike.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = spike.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y + 2
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function damagePlayer(controller, player)
	if controller.DamagedPlayers[player] then
		return false
	end

	local _, humanoid, rootPart = getCharacterContext(player)
	if not humanoid then
		return false
	end

	if not isPointInsideSpike(controller.Spike, rootPart.Position) then
		return false
	end

	local protected = HazardProtection.IsProtected(player, {
		Position = rootPart.Position,
		Context = "DeckSpikes",
	})
	if protected then
		controller.DamagedPlayers[player] = true
		return true
	end

	local knockback = Vector3.new(0, 34, 0)
		+ (getPlanarUnit(rootPart.Position - controller.Spike.Position, Vector3.zAxis) * 18)
	local applied = HitEffectService.ApplyEffect(player, "Knockdown", {
		Duration = CONFIG.KnockdownDuration,
		DropPosition = rootPart.Position,
		RagdollJoints = true,
		RagdollImpulse = knockback,
		Movement = {
			WalkSpeedMultiplier = 0,
			JumpMultiplier = 0,
			AutoRotate = false,
			PlatformStand = true,
			State = Enum.HumanoidStateType.Ragdoll,
		},
	})

	if applied then
		humanoid:TakeDamage(CONFIG.Damage)
	end

	controller.DamagedPlayers[player] = true
	return true
end

local function damagePlayersInside(controller)
	local affectedCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if damagePlayer(controller, player) then
			affectedCount += 1
		end
	end

	return affectedCount
end

local function createDeckSpikeModel(hazardsFolder, refs, startPart, endPart, placement)
	local model = Instance.new("Model")
	model.Name = "DeckSpikes"
	model:SetAttribute("HazardClass", CONFIG.HazardClass)
	model:SetAttribute("HazardType", CONFIG.HazardType)
	model:SetAttribute("CanFreeze", true)
	model:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)

	local warningPosition = placement.GroundPosition + Vector3.new(0, CONFIG.WarningGroundOffset, 0)
	local warning = createPart(
		model,
		"WarningFlash",
		Vector3.new(placement.Size.X, 0.12, placement.Size.Z),
		CFrame.fromMatrix(warningPosition, placement.Lateral, Vector3.yAxis, -placement.Forward),
		Color3.fromRGB(255, 0, 0),
		Enum.Material.Neon,
		0.12
	)

	local previewHeight = math.max(0, tonumber(CONFIG.PreviewHeight) or 0)
	local hiddenPosition = placement.GroundPosition - Vector3.new(0, (placement.Size.Y * 0.5) - previewHeight, 0)
	local extendedPosition = placement.GroundPosition + Vector3.new(0, placement.Size.Y * 0.5, 0)
	local hiddenCFrame = CFrame.fromMatrix(hiddenPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
	local extendedCFrame = CFrame.fromMatrix(extendedPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)

	local areaName = getAreaNameForPosition(startPart, endPart, placement.GroundPosition)
	local template = if CONFIG.UseSpikeTrapTemplates == true then findSpikeTrapTemplate(areaName or refs.ActiveMapName) else nil
	if template then
		local visualModel = template:Clone()
		visualModel.Name = "SpikeTrapVisual"
		local hitbox, createdHitbox = getOrCreateTemplateHitbox(visualModel)
		if hitbox and hitbox:IsA("BasePart") then
			configureSpikeTrapModel(visualModel, hitbox)
			visualModel.Parent = model

			local warningWidth = if placement.Spot then placement.Spot.Size.X else hitbox.Size.X
			local warningLength = if placement.Spot then placement.Spot.Size.Z else hitbox.Size.Z
			warning.Size = Vector3.new(warningWidth, 0.12, warningLength)
			warning.CFrame = CFrame.fromMatrix(warningPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)

			local orientedPivot = CFrame.fromMatrix(placement.GroundPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
			visualModel:PivotTo(orientedPivot)
			local boundsCFrame, visualSize = visualModel:GetBoundingBox()
			local riseHeight = math.max(0.1, visualSize.Y, hitbox.Size.Y)
			local visualBottomY = boundsCFrame.Position.Y - (visualSize.Y * 0.5)
			local groundDeltaY = placement.GroundPosition.Y - visualBottomY
			local extendedPivot = visualModel:GetPivot() + Vector3.new(0, groundDeltaY, 0)
			local hiddenPivot = extendedPivot + Vector3.new(0, -(riseHeight - previewHeight), 0)
			visualModel:PivotTo(hiddenPivot)

			model.WorldPivot = extendedPivot
			model.Parent = hazardsFolder
			studioInfo(
				"using template=%s area=%s hitbox=%s createdHitbox=%s warningSize=%.2f,%.2f visualHeight=%.2f groundDelta=%.2f",
				formatInstancePath(template),
				tostring(areaName),
				formatInstancePath(hitbox),
				tostring(createdHitbox == true),
				warningWidth,
				warningLength,
				riseHeight,
				groundDeltaY
			)

			return model, hitbox, warning, hiddenPivot, extendedPivot, visualModel
		end

		warnSpikeTemplateOnce(
			"missing_hitbox_" .. template.Name,
			"Template %s has no BasePart named Hitbox; using generated fallback.",
			formatInstancePath(template)
		)
	end

	local visualModel, spike = createGeneratedSpikeVisual(placement, extendedCFrame)
	visualModel:PivotTo(hiddenCFrame)
	visualModel.Parent = model

	model.WorldPivot = extendedCFrame
	model.Parent = hazardsFolder
	studioInfo("using generated fallback area=%s pos=%s", tostring(areaName), formatVector3(placement.GroundPosition))

	return model, spike, warning, hiddenCFrame, extendedCFrame, visualModel
end

local function runDeckSpikes(controller, hiddenCFrame, extendedCFrame)
	if not waitWhileFrozen(controller, CONFIG.WarningTime) then
		return
	end

	if controller.Warning.Parent then
		controller.Warning.Transparency = 1
	end

	controller.Active = true
	local tweenTarget = controller.VisualModel or controller.Spike
	local cframeGoalName = if controller.VisualModel then "Value" else "CFrame"
	tweenPart(
		controller,
		tweenTarget,
		TweenInfo.new(CONFIG.ThrustTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ [cframeGoalName] = extendedCFrame }
	)
	damagePlayersInside(controller)

	local elapsed = 0
	while elapsed < CONFIG.HoldTime do
		if controller.Destroyed or not controller.Model.Parent then
			return
		end

		if os.clock() < controller.FrozenUntil then
			task.wait(0.05)
		else
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			damagePlayersInside(controller)
		end
	end

	controller.Active = false
	tweenPart(
		controller,
		tweenTarget,
		TweenInfo.new(CONFIG.RetractTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ [cframeGoalName] = hiddenCFrame }
	)
	controller:Destroy()
end

local function cleanupActiveControllers()
	local activeCount = 0
	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
		else
			activeCount += 1
		end
	end

	return activeCount
end

local function spawnDeckSpikes(options)
	spawnAttemptSerial += 1
	local refs, _, hazardsFolder, startPart, endPart, leftBound, rightBound = resolveRefs()
	if not (hazardsFolder and startPart and endPart) then
		publishSpawnStatus(hazardsFolder, "skipped", "missing_refs", cleanupActiveControllers(), 0)
		trace(
			"spawn skipped reason=missing_refs hazards=%s start=%s end=%s",
			formatInstancePath(hazardsFolder),
			formatInstancePath(startPart),
			formatInstancePath(endPart)
		)
		return false
	end

	local activeCount = cleanupActiveControllers()
	local maxActive = math.max(1, math.floor(tonumber(CONFIG.MaxActiveSpikes) or 10))
	local spotCount = #getFixedSpikeSpots(refs, startPart, endPart, leftBound, rightBound)
	if activeCount >= maxActive then
		publishSpawnStatus(hazardsFolder, "skipped", "max_active", activeCount, spotCount)
		return false
	end

	local placement = chooseSpikePlacement(refs, startPart, endPart, leftBound, rightBound, options)
	if not placement then
		publishSpawnStatus(hazardsFolder, "skipped", "no_placement", activeCount, spotCount)
		trace("spawn skipped reason=no_ground")
		return false
	end

	local model, spike, warning, hiddenCFrame, extendedCFrame, visualModel = createDeckSpikeModel(
		hazardsFolder,
		refs,
		startPart,
		endPart,
		placement
	)
	local controller = createController(model, spike, warning, visualModel)
	publishSpawnStatus(hazardsFolder, "spawned", placement.SourceName or "ok", activeCount + 1, spotCount)
	trace(
		"spawned pos=%s size=%s",
		formatVector3(placement.GroundPosition),
		formatVector3(placement.Size)
	)

	task.spawn(function()
		runDeckSpikes(controller, hiddenCFrame, extendedCFrame)
	end)

	return true
end

local noDisastersTimer = getNoDisastersTimer()
local didInitialDelay = false
local activePhase = 1
local activationSerial = 0

local function spawnSpikePhase(phaseIndex)
	activationSerial += 1
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local activeSpotsPerBiome = math.max(1, math.floor(tonumber(CONFIG.ActiveSpotsPerBiome) or 20))
	local spotsPerBiome = math.max(activeSpotsPerBiome, math.floor(tonumber(CONFIG.GeneratedFixedSpotsPerBiome) or 40))
	local phaseCount = math.max(1, math.floor(spotsPerBiome / activeSpotsPerBiome))
	local normalizedPhase = ((math.floor(tonumber(phaseIndex) or 1) - 1) % phaseCount) + 1
	local firstSpotInBiome = ((normalizedPhase - 1) * activeSpotsPerBiome) + 1
	local lastSpotInBiome = math.min(firstSpotInBiome + activeSpotsPerBiome - 1, spotsPerBiome)
	local jobs = {}

	for spotInBiome = firstSpotInBiome, lastSpotInBiome do
		for biomeIndex = 1, biomeCount do
			jobs[#jobs + 1] = {
				BiomeIndex = biomeIndex,
				SpotInBiome = spotInBiome,
			}
		end
	end

	shuffleArray(
		jobs,
		Random.new(
			(math.floor(tonumber(CONFIG.ActivationShuffleSeed) or 9137) + (activationSerial * 4099) + (normalizedPhase * 131))
		)
	)

	local waveDuration = math.max(0, tonumber(CONFIG.ActivationWaveDuration) or 0)
	local spawnSpacing = if #jobs > 1 then waveDuration / (#jobs - 1) else 0

	for _, job in ipairs(jobs) do
		local ok, err = xpcall(function()
			spawnDeckSpikes({
				BiomeIndex = job.BiomeIndex,
				SpotInBiome = job.SpotInBiome,
			})
		end, debug.traceback)
		if not ok then
			warn(string.format("[DECK SPIKES] phase spawn error=%s", tostring(err)))
		end
		if spawnSpacing > 0 then
			task.wait(spawnSpacing)
		end
	end

	studioInfo(
		"phase spawned phase=%d spots=%d-%d biomes=%d total=%d",
		normalizedPhase,
		firstSpotInBiome,
		lastSpotInBiome,
		biomeCount,
		(lastSpotInBiome - firstSpotInBiome + 1) * biomeCount
	)

	return normalizedPhase + 1
end

while true do
	if isNoDisastersPaused(noDisastersTimer) then
		task.wait(1)
	else
		if not didInitialDelay then
			didInitialDelay = true
			task.wait(math.max(0, tonumber(CONFIG.InitialSpawnDelay) or 0))
		end

		activePhase = spawnSpikePhase(activePhase)
		task.wait(math.max(0.1, tonumber(CONFIG.ActivationCycleDelay) or 6))
	end
end
