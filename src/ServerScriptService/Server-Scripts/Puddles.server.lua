local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local StudioAssetResolver = require(Modules:WaitForChild("StudioAssetResolver"))
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))
local HazardRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local AffectableRegistry = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))

local CONFIG = {
	Enabled = true,
	CycleDelay = 3,
	InitialSpawnDelay = 1,
	ActiveLifetime = 35,
	FadeInDuration = 2.25,
	FadeOutDuration = 1,
	TargetActivePuddles = 50,
	MinSpawnStaggerDelay = 0.25,
	MaxSpawnStaggerDelay = 0.9,
	SlowRefreshDelay = 0.35,
	SlowDuration = 3,
	FallbackSlowMultiplier = 0.50,
	SlowMultiplierByBiome = {
		[1] = 0.10,
		[2] = 0.20,
		[3] = 0.30,
		[4] = 0.40,
		[5] = 0.60,
		[6] = 0.65,
		[7] = 0.70,
		[8] = 0.75,
	},
	BiomeCount = 8,
	MaxActivePuddles = 50,
	MinimumForwardAlpha = 0.04,
	MaximumForwardAlpha = 0.98,
	BiomePaddingAlpha = 0.08,
	GroundProbeHeight = 120,
	GroundProbeDepth = 260,
	MaxGroundHeightDelta = 4,
	GroundNormalMin = 0.65,
	FootprintSampleSpacing = 5,
	MaxFootprintSampleSteps = 14,
	SpawnAttempts = 24,
	MinPuddleEdgeGap = 4,
	HazardClass = "minor",
	HazardType = "puddle",
	FreezeBehavior = "pause",
	FreezeDurationFallback = 1.5,
	AffectablePadding = Vector3.new(0.5, 1, 0.5),
	ReverseBiomeTemplates = true,
	SpawnCountsByBiome = {
		[1] = 10,
		[2] = 9,
		[3] = 8,
		[4] = 8,
		[5] = 7,
		[6] = 7,
		[7] = 6,
		[8] = 6,
	},
	GlobalScaleMultiplier = .5,
	YawDegrees = 90,
	ScaleByBiome = {
		[1] = 0.25,
		[2] = 0.20,
		[3] = 0.18,
		[4] = 0.16,
		[5] = 0.14,
		[6] = 0.12,
		[7] = 0.10,
		[8] = 0.08,
	},
	SafeGapBuffer = 32,
	SafeGapBufferByBiome = {
		[1] = 38,
		[2] = 35,
		[3] = 30,
		[4] = 28,
		[5] = 25,
		[6] = 15,
		[7] = 10,
		[8] = 2,
	},
	LargePuddleGapBufferScale = 1.85,
	SafeFloorNameKeywords = {
		"gap",
		"safe",
		"safezone",
		"refuge",
		"hub",
		"lobby",
		"nopuddle",
		"no puddle",
	},
}

if not CONFIG.Enabled then
	return
end

StudioAssetResolver.ValidateRequiredAssets({ "Puddles" }, "Puddles")

local PUDDLE_TEMPLATE_NAMES_BY_AREA = {
	["foosha village"] = "Foosha Puddle",
	["arlong park"] = "Arlong Puddle",
	["drum island"] = "Drum Island Puddle",
	["alabasta"] = "Alabasta Puddle",
	["water 7"] = "Water 7 Puddle",
	["thriller bark"] = "Thriller Bark Puddle",
	["sabaody"] = "Sabaody Puddle",
	["dressrosa"] = "Dressrosa Puddle",
	["dresserosa"] = "Dressrosa Puddle",
}

local PUDDLE_TEMPLATE_TOKENS_BY_AREA = {
	["foosha village"] = { "foosha" },
	["arlong park"] = { "arlong" },
	["drum island"] = { "drum" },
	["alabasta"] = { "alabasta" },
	["water 7"] = { "water 7", "water" },
	["thriller bark"] = { "thriller" },
	["sabaody"] = { "sabaody" },
	["dressrosa"] = { "dressrosa", "dresserosa" },
	["dresserosa"] = { "dresserosa", "dressrosa" },
}

local rng = Random.new()
local activeControllers = {}
local templateCacheByArea = {}
local warnedMessages = {}
local lastTraceStateKey = nil
local DEBUG_TRACE = RunService:IsStudio() and game:GetAttribute("PuddlesDebugTrace") == true

local function trace(message, ...)
	if DEBUG_TRACE then
		print(string.format("[PUDDLES] " .. message, ...))
	end
end

local function warnOnce(key, message, ...)
	if warnedMessages[key] then
		return
	end

	warnedMessages[key] = true
	warn(string.format("[PUDDLES] " .. message, ...))
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

local function resolveRefs()
	local refs = MapResolver.WaitForRefs(
		{ "MapRoot", "WaveFolder", "WaveStart", "WaveEnd" },
		nil,
		{
			warn = true,
			context = "Puddles",
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
			"resolved waveFolder=%s hazards=%s start=%s end=%s left=%s right=%s",
			formatInstancePath(waveFolder),
			formatInstancePath(hazardsFolder),
			formatInstancePath(refs.WaveStart),
			formatInstancePath(refs.WaveEnd),
			formatInstancePath(leftBound),
			formatInstancePath(rightBound)
		)
	end

	return refs, hazardsFolder, refs.WaveStart, refs.WaveEnd, leftBound, rightBound
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
	raycastParams.IgnoreWater = true
	return raycastParams
end

local function isUnsafePuddleSurface(instance)
	if not instance then
		return true
	end

	local current = instance
	while current do
		if current:GetAttribute("BombSafe") == true
			or current:GetAttribute("SafeZone") == true
			or current:GetAttribute("IsSafeZone") == true
			or current:GetAttribute("NoPuddles") == true
			or current:GetAttribute("NoPuddle") == true
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

local function raycastGround(position, refs, raycastParams)
	local height = math.max(10, tonumber(CONFIG.GroundProbeHeight) or 120)
	local depth = math.max(height + 10, tonumber(CONFIG.GroundProbeDepth) or 260)
	local result = Workspace:Raycast(
		position + Vector3.new(0, height, 0),
		Vector3.new(0, -depth, 0),
		raycastParams or buildGroundRaycastParams(refs)
	)

	if result
		and result.Instance
		and result.Instance:IsA("BasePart")
		and result.Instance.CanCollide == true
		and result.Normal.Y >= math.clamp(tonumber(CONFIG.GroundNormalMin) or 0.65, 0, 1)
		and not isUnsafePuddleSurface(result.Instance)
	then
		return result.Position
	end

	return nil
end

local function buildFootprintSampleOffsets(forward, lateral, footprintSize, buffer)
	local forwardUnit = getPlanarUnit(forward, Vector3.zAxis)
	local lateralUnit = getPlanarUnit(lateral, Vector3.xAxis)
	local size = typeof(footprintSize) == "Vector3" and footprintSize or Vector3.new(8, 1, 8)
	local footprintDiameter = math.max(size.X, size.Z)
	local sampleX = math.max(1, (footprintDiameter * 0.5) + buffer)
	local sampleZ = math.max(1, (footprintDiameter * 0.5) + buffer)
	local spacing = math.max(2, tonumber(CONFIG.FootprintSampleSpacing) or 8)
	local maxSteps = math.max(2, math.floor(tonumber(CONFIG.MaxFootprintSampleSteps) or 8))
	local xSteps = math.clamp(math.ceil((sampleX * 2) / spacing), 2, maxSteps)
	local zSteps = math.clamp(math.ceil((sampleZ * 2) / spacing), 2, maxSteps)
	local offsets = { Vector3.zero }

	for xIndex = 0, xSteps do
		local xAlpha = if xSteps > 0 then xIndex / xSteps else 0.5
		local x = -sampleX + (sampleX * 2 * xAlpha)
		for zIndex = 0, zSteps do
			local zAlpha = if zSteps > 0 then zIndex / zSteps else 0.5
			local z = -sampleZ + (sampleZ * 2 * zAlpha)
			if math.abs(x) > 1e-3 or math.abs(z) > 1e-3 then
				offsets[#offsets + 1] = (lateralUnit * x) + (forwardUnit * z)
			end
		end
	end

	return offsets
end

local function getSafeGapBufferForBiome(biomeIndex)
	local fallback = math.max(0, tonumber(CONFIG.SafeGapBuffer) or 0)
	local byBiome = CONFIG.SafeGapBufferByBiome
	if type(byBiome) ~= "table" then
		return fallback
	end

	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)
	return math.max(0, tonumber(byBiome[normalizedBiome]) or fallback)
end

local function isNearSafePuddleGap(position, refs, forward, lateral, footprintSize, raycastParams, biomeIndex)
	local buffer = getSafeGapBufferForBiome(biomeIndex)
	if buffer <= 0 then
		return false
	end

	local size = typeof(footprintSize) == "Vector3" and footprintSize or Vector3.new(8, 1, 8)
	local largePuddleBuffer = math.max(size.X, size.Z) * math.max(0, tonumber(CONFIG.LargePuddleGapBufferScale) or 0)
	local sampleBuffer = math.max(buffer, largePuddleBuffer)
	local maxHeightDelta = math.max(0.5, tonumber(CONFIG.MaxGroundHeightDelta) or 4)

	for _, offset in ipairs(buildFootprintSampleOffsets(forward, lateral, footprintSize, sampleBuffer)) do
		local samplePosition = raycastGround(position + offset, refs, raycastParams)
		if not samplePosition or math.abs(samplePosition.Y - position.Y) > maxHeightDelta then
			return true
		end
	end

	return false
end

local function resolveSafeGroundPosition(position, refs, lateral, forward, footprintSize, biomeIndex)
	local raycastParams = buildGroundRaycastParams(refs)
	local centerPosition = raycastGround(position, refs, raycastParams)
	if not centerPosition then
		return nil
	end

	if isNearSafePuddleGap(centerPosition, refs, forward, lateral, footprintSize, raycastParams, biomeIndex) then
		return nil
	end

	local size = typeof(footprintSize) == "Vector3" and footprintSize or Vector3.new(8, 1, 8)
	local maxHeightDelta = math.max(0.5, tonumber(CONFIG.MaxGroundHeightDelta) or 4)

	for _, offset in ipairs(buildFootprintSampleOffsets(forward, lateral, size, 0)) do
		local samplePosition = raycastGround(position + offset, refs, raycastParams)
		if not samplePosition or math.abs(samplePosition.Y - centerPosition.Y) > maxHeightDelta then
			return nil
		end
	end

	return centerPosition
end

local function getTemplateBiomeIndex(biomeIndex)
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)

	return if CONFIG.ReverseBiomeTemplates == true
		then (biomeCount - normalizedBiome + 1)
		else normalizedBiome
end

local function getAreaEntryForBiome(biomeIndex)
	local templateBiomeIndex = getTemplateBiomeIndex(biomeIndex)
	local entry = BiomeAreas.GetBiome and BiomeAreas.GetBiome(templateBiomeIndex)
	if entry then
		return entry
	end

	return {
		AreaName = "Foosha Village",
	}
end

local function getAreaNameForBiome(biomeIndex)
	local entry = getAreaEntryForBiome(biomeIndex)
	return entry and entry.AreaName or "Foosha Village"
end

local function findPuddleFolder()
	return StudioAssetResolver.ResolveAsset("Puddles", {
		Context = "Puddles",
		Required = true,
	})
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

local function findPuddleTemplate(areaName)
	local key = string.lower(tostring(areaName or ""))
	local cachedTemplate = templateCacheByArea[key]
	if cachedTemplate and cachedTemplate.Parent then
		return cachedTemplate
	elseif cachedTemplate then
		templateCacheByArea[key] = nil
	end

	local folder = findPuddleFolder()
	if not folder then
		return nil
	end

	local modelCandidates = {}
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Model") then
			modelCandidates[#modelCandidates + 1] = descendant
		end
	end

	local templateName = PUDDLE_TEMPLATE_NAMES_BY_AREA[key]
	if templateName then
		local template = folder:FindFirstChild(templateName, true)
		if template and template:IsA("Model") then
			templateCacheByArea[key] = template
			return template
		end
	end

	for _, candidate in ipairs(modelCandidates) do
		local candidateName = string.lower(candidate.Name)
		if key ~= "" and candidateName:find(key, 1, true) then
			templateCacheByArea[key] = candidate
			return candidate
		end

		for _, token in ipairs(PUDDLE_TEMPLATE_TOKENS_BY_AREA[key] or {}) do
			if candidateName:find(token, 1, true) then
				templateCacheByArea[key] = candidate
				return candidate
			end
		end
	end

	for _, candidate in ipairs(modelCandidates) do
		if findHitbox(candidate) or hasBasePart(candidate) then
			templateCacheByArea[key] = candidate
			return candidate
		end
	end

	warnOnce("missing_template_" .. key, "Could not find a puddle template for area=%s.", tostring(areaName))
	return nil
end

local function getOrCreateHitbox(model)
	local hitbox = findHitbox(model)
	if hitbox then
		return hitbox
	end

	local boundsCFrame, boundsSize = model:GetBoundingBox()
	hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = Vector3.new(math.max(1, boundsSize.X), math.max(1, boundsSize.Y), math.max(1, boundsSize.Z))
	hitbox.CFrame = boundsCFrame
	hitbox.Transparency = 1
	hitbox.Parent = model

	return hitbox
end

local function configurePuddleModel(model, hitbox)
	for _, part in ipairs(getBaseParts(model)) do
		configurePart(part, part == hitbox, part == hitbox)
		if part == hitbox then
			part.Transparency = 1
			part:SetAttribute("HazardClass", CONFIG.HazardClass)
			part:SetAttribute("HazardType", CONFIG.HazardType)
			part:SetAttribute("CanFreeze", true)
			part:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)
		end
	end
end

local function getFootprintSizeFromTemplate(template, scale)
	local clone = template:Clone()
	local hitbox = getOrCreateHitbox(clone)
	local size = hitbox.Size * math.max(0.01, tonumber(scale) or 1)
	clone:Destroy()

	return size
end

local function getPlanarDistance(a, b)
	if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return math.huge
	end

	local delta = Vector3.new(a.X - b.X, 0, a.Z - b.Z)
	return delta.Magnitude
end

local function getFootprintRadius(size)
	if typeof(size) ~= "Vector3" then
		return 0
	end

	return math.max(size.X, size.Z) * 0.5
end

local function isTooCloseToActivePuddle(position, footprintSize)
	local currentRadius = getFootprintRadius(footprintSize)
	local minEdgeGap = math.max(0, tonumber(CONFIG.MinPuddleEdgeGap) or 0)

	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
			continue
		end

		local hitbox = controller.Hitbox
		if hitbox and hitbox.Parent then
			local otherRadius = getFootprintRadius(hitbox.Size)
			local requiredDistance = currentRadius + otherRadius + minEdgeGap
			if getPlanarDistance(position, hitbox.Position) < requiredDistance then
				return true
			end
		end
	end

	return false
end

local function choosePuddlePlacement(refs, startPart, endPart, leftBound, rightBound, biomeIndex, footprintSize)
	local forward, lateral, corridorCenter, corridorWidth = getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local pathDelta = endPart.Position - startPart.Position
	local pathLength = pathDelta:Dot(forward)
	if pathLength < 0 then
		forward = -forward
		pathLength = -pathLength
	end
	pathLength = math.max(1, pathLength)

	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)
	local minimumAlpha = math.clamp(tonumber(CONFIG.MinimumForwardAlpha) or 0, 0, 1)
	local maximumAlpha = math.clamp(tonumber(CONFIG.MaximumForwardAlpha) or 1, minimumAlpha, 1)
	local usableAlphaRange = math.max(0.001, maximumAlpha - minimumAlpha)
	local biomeStartAlpha = minimumAlpha + (usableAlphaRange * ((normalizedBiome - 1) / biomeCount))
	local biomeEndAlpha = minimumAlpha + (usableAlphaRange * (normalizedBiome / biomeCount))
	local padding = math.clamp(tonumber(CONFIG.BiomePaddingAlpha) or 0.08, 0, 0.35)
	local startAlpha = biomeStartAlpha + ((biomeEndAlpha - biomeStartAlpha) * padding)
	local endAlpha = biomeEndAlpha - ((biomeEndAlpha - biomeStartAlpha) * padding)
	local attempts = math.max(1, math.floor(tonumber(CONFIG.SpawnAttempts) or 24))
	local halfWidth = corridorWidth * 0.5
	local footprintWidth = math.max(2, typeof(footprintSize) == "Vector3" and footprintSize.X or 2)
	local lateralLimit = math.max(0, halfWidth - (footprintWidth * 0.5))

	for _ = 1, attempts do
		local forwardAlpha = rng:NextNumber(startAlpha, math.max(startAlpha, endAlpha))
		local laneOffset = rng:NextNumber(-lateralLimit, lateralLimit)
		local centerOnPath = startPart.Position + (forward * pathLength * forwardAlpha)
		local centerProjection = corridorCenter:Dot(lateral)
		local pathProjection = centerOnPath:Dot(lateral)
		local planarPosition = centerOnPath + (lateral * (centerProjection - pathProjection + laneOffset))
		local groundPosition = resolveSafeGroundPosition(planarPosition, refs, lateral, forward, footprintSize, normalizedBiome)
		if groundPosition and not isTooCloseToActivePuddle(groundPosition, footprintSize) then
			local yaw = CFrame.Angles(0, math.rad(tonumber(CONFIG.YawDegrees) or 0), 0)
			return {
				GroundPosition = groundPosition,
				CFrame = CFrame.new(groundPosition) * yaw,
				Forward = forward,
				Lateral = lateral,
				BiomeIndex = normalizedBiome,
			}
		end
	end

	return nil
end

local function setFrozenVisual(controller, isFrozen)
	if not controller.VisualModel or not controller.VisualModel.Parent then
		return
	end

	for _, part in ipairs(getBaseParts(controller.VisualModel)) do
		if part ~= controller.Hitbox then
			local defaults = controller.VisualDefaults[part]
			if isFrozen then
				part.Color = Color3.fromRGB(178, 235, 255)
				part.Material = Enum.Material.Ice
			elseif defaults then
				part.Color = defaults.Color
				part.Material = defaults.Material
			end
		end
	end
end

local function setPuddleVisualFade(controller, fadeAlpha)
	if not controller.VisualModel or not controller.VisualModel.Parent then
		return
	end

	local clampedAlpha = math.clamp(tonumber(fadeAlpha) or 0, 0, 1)
	for _, part in ipairs(getBaseParts(controller.VisualModel)) do
		if part ~= controller.Hitbox then
			local defaults = controller.VisualDefaults[part]
			local defaultTransparency = defaults and defaults.Transparency or part.Transparency
			part.Transparency = defaultTransparency + ((1 - defaultTransparency) * clampedAlpha)
		end
	end
end

local function tweenPuddleVisualFade(controller, fadeAlpha, duration)
	if not controller.VisualModel or not controller.VisualModel.Parent then
		return
	end

	local clampedAlpha = math.clamp(tonumber(fadeAlpha) or 0, 0, 1)
	local tweenDuration = math.max(0, tonumber(duration) or 0)
	if tweenDuration <= 0 then
		setPuddleVisualFade(controller, clampedAlpha)
		return
	end

	local tweenInfo = TweenInfo.new(tweenDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in ipairs(getBaseParts(controller.VisualModel)) do
		if part ~= controller.Hitbox then
			local defaults = controller.VisualDefaults[part]
			local defaultTransparency = defaults and defaults.Transparency or part.Transparency
			local targetTransparency = defaultTransparency + ((1 - defaultTransparency) * clampedAlpha)
			TweenService:Create(part, tweenInfo, {
				Transparency = targetTransparency,
			}):Play()
		end
	end

	task.wait(tweenDuration)
end

local function setPuddleHitboxActive(controller, isActive)
	if controller.Hitbox and controller.Hitbox.Parent then
		controller.Hitbox.CanTouch = isActive == true
		controller.Hitbox.CanQuery = isActive == true
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
	if controller.Destroyed or not controller.Model.Parent or not controller.Hitbox.Parent then
		return {}
	end

	return {
		{
			Type = AffectableRegistry.VolumeType.Box,
			Label = "Puddle",
			CFrame = controller.Hitbox.CFrame,
			Size = controller.Hitbox.Size,
			Padding = CONFIG.AffectablePadding,
		},
	}
end

local function createController(model, hitbox, visualModel, biomeIndex)
	local visualDefaults = {}
	for _, part in ipairs(getBaseParts(visualModel)) do
		visualDefaults[part] = {
			Color = part.Color,
			Material = part.Material,
			Transparency = part.Transparency,
		}
	end

	local controller = {
		Model = model,
		Hitbox = hitbox,
		VisualModel = visualModel,
		VisualDefaults = visualDefaults,
		Destroyed = false,
		FadingIn = true,
		FadingOut = false,
		FrozenUntil = 0,
		FreezeToken = 0,
		LastSlowByPlayer = {},
		BiomeIndex = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, math.max(1, CONFIG.BiomeCount)),
	}

	setPuddleVisualFade(controller, 1)
	setPuddleHitboxActive(controller, false)

	task.spawn(function()
		tweenPuddleVisualFade(controller, 0, CONFIG.FadeInDuration)
		if controller.Destroyed or not controller.Model.Parent then
			return
		end

		controller.FadingIn = false
		setPuddleHitboxActive(controller, true)
	end)

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
		setFrozenVisual(self, true)

		task.spawn(function()
			while not self.Destroyed and self.Model.Parent and os.clock() < self.FrozenUntil do
				task.wait(0.05)
			end

			if self.Destroyed or self.FreezeToken ~= freezeToken then
				return
			end

			setFrozenVisual(self, false)
		end)

		return true
	end

	function controller:Destroy(options)
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		self.FadingOut = true
		if self.TouchConnection then
			self.TouchConnection:Disconnect()
			self.TouchConnection = nil
		end
		setPuddleHitboxActive(self, false)
		unregisterController(self)
		local immediate = typeof(options) == "table" and options.Immediate == true
		if not immediate and self.Model.Parent then
			tweenPuddleVisualFade(self, 1, CONFIG.FadeOutDuration)
		end

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
			return entity.Controller.Destroyed ~= true
				and entity.Controller.FadingIn ~= true
				and entity.Controller.FadingOut ~= true
				and model.Parent ~= nil
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
				Position = hitbox.Position,
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

local function isPointInsidePart(part, worldPosition)
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y + 4
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function canApplyPuddleSlow(controller)
	if controller.FadingIn or controller.FadingOut then
		return false
	end

	if os.clock() < controller.FrozenUntil then
		return false
	end

	return true
end

local function applyPuddleSlow(controller, player)
	if not canApplyPuddleSlow(controller) then
		return
	end

	local slowMultiplier = CONFIG.SlowMultiplierByBiome[controller.BiomeIndex] or CONFIG.FallbackSlowMultiplier
	HitEffectService.ApplyEffect(player, "Slow", {
		Duration = CONFIG.SlowDuration,
		Priority = 10,
		HazardClass = CONFIG.HazardClass,
		HazardType = CONFIG.HazardType,
		Source = "Puddles",
		Movement = {
			WalkSpeedMultiplier = slowMultiplier,
			JumpMultiplier = 1,
		},
	})
end

local function getPlayerFromTouchedPart(part)
	local character = part and part:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function bindPuddleTouchedSlow(controller)
	if not controller.Hitbox then
		return
	end

	controller.TouchConnection = controller.Hitbox.Touched:Connect(function(part)
		local player = getPlayerFromTouchedPart(part)
		if not player then
			return
		end

		applyPuddleSlow(controller, player)
	end)
end

local function applySlowToPlayersInside(controller)
	if not canApplyPuddleSlow(controller) then
		return
	end

	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and rootPart and isPointInsidePart(controller.Hitbox, rootPart.Position) then
			local lastSlow = controller.LastSlowByPlayer[player] or 0
			if now - lastSlow >= CONFIG.SlowRefreshDelay then
				controller.LastSlowByPlayer[player] = now
				applyPuddleSlow(controller, player)
			end
		end
	end
end

local function waitActiveLifetime(controller)
	local elapsed = 0
	while elapsed < CONFIG.ActiveLifetime do
		if controller.Destroyed or not controller.Model.Parent then
			return false
		end

		if controller.FadingIn or os.clock() < controller.FrozenUntil then
			task.wait(0.05)
		else
			local dt = RunService.Heartbeat:Wait()
			elapsed += dt
			applySlowToPlayersInside(controller)
		end
	end

	return true
end

local function createPuddleModel(hazardsFolder, areaName, placement, scale)
	local template = findPuddleTemplate(areaName)
	if not template then
		return nil
	end

	local model = Instance.new("Model")
	model.Name = "Puddle"
	model:SetAttribute("HazardClass", CONFIG.HazardClass)
	model:SetAttribute("HazardType", CONFIG.HazardType)
	model:SetAttribute("CanFreeze", true)
	model:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)

	local visualModel = template:Clone()
	visualModel.Name = "PuddleVisual"
	visualModel.Parent = model

	local scaleValue = math.max(0.01, tonumber(scale) or 1)
	pcall(function()
		visualModel:ScaleTo(scaleValue)
	end)

	local hitbox = getOrCreateHitbox(visualModel)
	configurePuddleModel(visualModel, hitbox)

	visualModel:PivotTo(placement.CFrame)
	local boundsCFrame, boundsSize = visualModel:GetBoundingBox()
	local bottomY = boundsCFrame.Position.Y - (boundsSize.Y * 0.5)
	local groundDeltaY = placement.GroundPosition.Y - bottomY
	visualModel:PivotTo(visualModel:GetPivot() + Vector3.new(0, groundDeltaY, 0))

	model.WorldPivot = visualModel:GetPivot()
	model.Parent = hazardsFolder

	return model, hitbox, visualModel
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

local function getScaleForBiome(biomeIndex)
	local biomeScale = CONFIG.ScaleByBiome[biomeIndex] or 1
	local globalMultiplier = math.max(0.01, tonumber(CONFIG.GlobalScaleMultiplier) or 1)

	return biomeScale * globalMultiplier
end

local function getRandomDelay(minValue, maxValue, fallbackMin)
	local minDelay = math.max(0, tonumber(minValue) or fallbackMin or 0)
	local maxDelay = math.max(minDelay, tonumber(maxValue) or minDelay)

	return rng:NextNumber(minDelay, maxDelay)
end

local function getSpawnStaggerDelay()
	return getRandomDelay(CONFIG.MinSpawnStaggerDelay, CONFIG.MaxSpawnStaggerDelay, 0.03)
end

local function chooseRandomBiomeIndex()
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local totalWeight = 0
	for biomeIndex = 1, biomeCount do
		totalWeight += math.max(0, tonumber(CONFIG.SpawnCountsByBiome[biomeIndex]) or 1)
	end

	if totalWeight <= 0 then
		return rng:NextInteger(1, biomeCount)
	end

	local roll = rng:NextNumber(0, totalWeight)
	local cursor = 0
	for biomeIndex = 1, biomeCount do
		cursor += math.max(0, tonumber(CONFIG.SpawnCountsByBiome[biomeIndex]) or 1)
		if roll <= cursor then
			return biomeIndex
		end
	end

	return biomeCount
end

local function shuffleArray(array)
	for index = #array, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		array[index], array[swapIndex] = array[swapIndex], array[index]
	end
end

local function spawnPuddle(refs, hazardsFolder, startPart, endPart, leftBound, rightBound, biomeIndex)
	if cleanupActiveControllers() >= CONFIG.MaxActivePuddles then
		return false
	end

	local areaName = getAreaNameForBiome(biomeIndex)
	local template = findPuddleTemplate(areaName)
	if not template then
		return false
	end

	local scale = getScaleForBiome(biomeIndex)
	local footprintSize = getFootprintSizeFromTemplate(template, scale)
	local placement = choosePuddlePlacement(refs, startPart, endPart, leftBound, rightBound, biomeIndex, footprintSize)
	if not placement then
		return false
	end

	local model, hitbox, visualModel = createPuddleModel(hazardsFolder, areaName, placement, scale)
	if not model then
		return false
	end

	local controller = createController(model, hitbox, visualModel, placement.BiomeIndex)
	bindPuddleTouchedSlow(controller)
	task.spawn(function()
		waitActiveLifetime(controller)
		controller:Destroy()
	end)

	trace("spawned biome=%d area=%s scale=%.2f", biomeIndex, tostring(areaName), scale)
	return true
end

local function spawnPuddleCycle()
	local refs, hazardsFolder, startPart, endPart, leftBound, rightBound = resolveRefs()
	if not (hazardsFolder and startPart and endPart) then
		return false
	end

	local spawnedAny = false
	local activeCount = cleanupActiveControllers()
	local targetActive = math.clamp(
		math.floor(tonumber(CONFIG.TargetActivePuddles) or CONFIG.MaxActivePuddles),
		1,
		math.max(1, math.floor(tonumber(CONFIG.MaxActivePuddles) or 1))
	)
	if activeCount >= targetActive then
		return false
	end

	local jobs = {}
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	for biomeIndex = 1, biomeCount do
		local spawnCount = math.max(0, math.floor(tonumber(CONFIG.SpawnCountsByBiome[biomeIndex]) or 1))
		for _ = 1, spawnCount do
			jobs[#jobs + 1] = biomeIndex
		end
	end

	if #jobs <= 0 then
		jobs[#jobs + 1] = chooseRandomBiomeIndex()
	end

	shuffleArray(jobs)

	for spawnIndex, biomeIndex in ipairs(jobs) do
		if activeCount >= targetActive then
			break
		end

		if spawnPuddle(refs, hazardsFolder, startPart, endPart, leftBound, rightBound, biomeIndex) then
			spawnedAny = true
			activeCount += 1
		end

		if spawnIndex < #jobs and activeCount < targetActive then
			task.wait(getSpawnStaggerDelay())
		end
	end

	return spawnedAny
end

local noDisastersTimer = getNoDisastersTimer()
task.wait(math.max(0, tonumber(CONFIG.InitialSpawnDelay) or 0))

while true do
	if noDisastersTimer and noDisastersTimer.Value > 0 then
		task.wait(1)
	else
		local ok, err = xpcall(spawnPuddleCycle, debug.traceback)
		if not ok then
			warn(string.format("[PUDDLES] spawn error=%s", tostring(err)))
		end
		task.wait(math.max(0.1, tonumber(CONFIG.CycleDelay) or 6))
	end
end
