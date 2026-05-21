local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local BiomePlacementResolver = require(Modules:WaitForChild("BiomePlacementResolver"))
local StudioAssetResolver = require(Modules:WaitForChild("StudioAssetResolver"))
local HazardDebugConstants = require(Modules:WaitForChild("Debug"):WaitForChild("HazardDebugConstants"))
local BiomeAreas = require(Modules:WaitForChild("Configs"):WaitForChild("BiomeAreas"))
local SpawnPartsConfig = require(Modules:WaitForChild("Configs"):WaitForChild("SpawnParts"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))
local HazardProtection = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("HazardProtection")
)

local CONFIG = {
	Enabled = true,
	InitialSpawnDelay = 3,
	SpawnDelayMin = 0.08,
	SpawnDelayMax = 0.18,
	MaxSpawnOperationsPerCycle = 4,

	ThrustTime = 0.12,
	RetractTime = 0.16,

	BiomeCount = 8,
	MaxActiveSpikes = 180,

	GroundProbeHeight = 120,
	GroundProbeDepth = 260,
	MaxGroundHeightDelta = 3,
	GroundNormalMin = 0.65,
	FootprintSupportPadding = 4,
	FootprintSampleSpacing = 5,
	MaxFootprintSampleSteps = 8,
	SurfaceEdgePadding = 1,
	SafeFloorNameKeywords = {
		"barrier",
		"bound",
		"boundary",
		"decor",
		"decoration",
		"gap",
		"marker",
		"safe",
		"safezone",
		"refuge",
		"hub",
		"lobby",
		"no spike",
		"nospike",
		"no_spike",
	},

	GeneratedSpikeBaseSize = Vector3.new(7.5, 5.86, 5.77),
	SpikeVisualScale = 3.2,
	PreviewHeight = 0.45,
	WarningGroundOffset = 0.25,

	FallbackWarningTime = 3,
	FallbackHoldTime = 2.5,
	FallbackDamage = 65,
	KnockdownDuration = 0.8,
	HazardClass = "minor",
	HazardType = "deck_spikes",
	UseSpikeTrapTemplates = true,
	IgnoreNoDisastersTimerInStudio = true,

	-- Spike balance knobs:
	-- Higher SpikesPerSurface values add more traps per accepted platform.
	-- Higher ScaleRange values make larger spike traps.
	-- WarningTime is the telegraph/windup before spikes rise.
	-- HoldTime is how long raised spikes stay dangerous.
	-- Higher DamageRange values make spikes hit harder.
	-- Larger MinSpacing values reduce close/overlapping spike placements.
	SpikeTuningBands = {
		{
			Id = 1,
			MinBiome = 1,
			MaxBiome = 2,
			SpikesPerSurface = { Min = 2, Max = 2 },
			ScaleRange = { Min = 0.95, Max = 1.05 },
			DamageRange = { Min = 45, Max = 55 },
			WarningTime = 3.2,
			HoldTime = 2.5,
			MinSpacing = 8,
			MaxPlacementAttempts = 24,
			CandidateAttempts = 12,
		},
		{
			Id = 2,
			MinBiome = 3,
			MaxBiome = 4,
			SpikesPerSurface = { Min = 4, Max = 4 },
			ScaleRange = { Min = 1.0, Max = 1.1 },
			DamageRange = { Min = 55, Max = 65 },
			WarningTime = 3.0,
			HoldTime = 2.5,
			MinSpacing = 10,
			MaxPlacementAttempts = 26,
			CandidateAttempts = 12,
		},
		{
			Id = 3,
			MinBiome = 5,
			MaxBiome = 6,
			SpikesPerSurface = { Min = 6, Max = 6 },
			ScaleRange = { Min = 1.05, Max = 1.18 },
			DamageRange = { Min = 65, Max = 65 },
			WarningTime = 2.7,
			HoldTime = 2.5,
			MinSpacing = 12,
			MaxPlacementAttempts = 28,
			CandidateAttempts = 14,
		},
		{
			Id = 4,
			MinBiome = 7,
			MaxBiome = 8,
			SpikesPerSurface = { Min = 8, Max = 8 },
			ScaleRange = { Min = 1.1, Max = 1.25 },
			DamageRange = { Min = 70, Max = 75 },
			WarningTime = 2.5,
			HoldTime = 2.5,
			MinSpacing = 14,
			MaxPlacementAttempts = 30,
			CandidateAttempts = 14,
		},
	},
}

if not CONFIG.Enabled then
	return
end

StudioAssetResolver.ValidateRequiredAssets({ "SpikeTraps" }, "DeckSpikes")

local function markHazardHitboxPart(part)
	if not part or not part:IsA("BasePart") then
		return
	end

	CollectionService:AddTag(part, HazardDebugConstants.HitboxTag)
	part:SetAttribute(HazardDebugConstants.DebugHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardClassAttribute, CONFIG.HazardClass)
	part:SetAttribute(HazardDebugConstants.HazardTypeAttribute, CONFIG.HazardType)
end

local SPIKE_TEMPLATE_NAMES_BY_AREA = {
	["foosha village"] = "(FOOSHA) WOODEN SPIKE TRAPS",
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

local SPIKE_SURFACE_ALLOW_ATTRIBUTES = {
	"SpikeFloor",
	"SpikePlacement",
	"SpikeSpawnFloor",
	"SpikeTrapFloor",
	"HazardFloor",
}

local SPIKE_SURFACE_ALLOW_TAGS = {
	"SpikeFloor",
	"SpikePlacement",
	"SpikeSpawnFloor",
	"SpikeTrapFloor",
	"HazardFloor",
}

local SPIKE_SURFACE_DENY_ATTRIBUTES = {
	"BombSafe",
	"DebugHitbox",
	"HazardHitbox",
	"IsSafeZone",
	"NoHazard",
	"NoHazards",
	"NoSpike",
	"NoSpikes",
	"SafeZone",
	"SpikeBlocked",
}

local SPIKE_SURFACE_DENY_TAGS = {
	"DebugHitbox",
	"HazardHitbox",
	"NoHazard",
	"NoHazards",
	"NoSpike",
	"NoSpikes",
	"SafeZone",
	"SpikeBlocked",
}

local rng = Random.new()
local activeControllers = {}
local templateCacheByArea = {}
local templateMetadataCacheByArea = {}
local warnedPlacementFailures = {}

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

local function formatInstancePath(instance)
	return if instance then instance:GetFullName() else "<nil>"
end

local function warnPlacementFailure(key, message, ...)
	local textKey = tostring(key or message)
	if warnedPlacementFailures[textKey] then
		return
	end

	warnedPlacementFailures[textKey] = true
	warn(string.format(message, ...))
end

local function getRarityPadSurfaceNames()
	local names = {}
	for name in pairs(SpawnPartsConfig.RarityTier or {}) do
		names[#names + 1] = tostring(name)
	end
	table.sort(names)
	return names
end

local function rollNumberRange(range, fallback)
	if type(range) ~= "table" then
		return tonumber(range) or fallback
	end

	local minValue = tonumber(range.Min) or tonumber(range[1]) or fallback
	local maxValue = tonumber(range.Max) or tonumber(range[2]) or minValue
	if maxValue < minValue then
		minValue, maxValue = maxValue, minValue
	end

	if math.abs(maxValue - minValue) <= 0.0001 then
		return minValue
	end

	return rng:NextNumber(minValue, maxValue)
end

local function rollIntegerRange(range, fallback)
	local value = rollNumberRange(range, fallback)
	return math.max(0, math.floor(value + 0.5))
end

local function getSpikeTuningForBiome(biomeIndex)
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, CONFIG.BiomeCount)
	for _, tuning in ipairs(CONFIG.SpikeTuningBands or {}) do
		local minBiome = math.floor(tonumber(tuning.MinBiome) or normalizedBiome)
		local maxBiome = math.floor(tonumber(tuning.MaxBiome) or minBiome)
		if normalizedBiome >= minBiome and normalizedBiome <= maxBiome then
			return tuning
		end
	end

	return {
		Id = 0,
		SpikesPerSurface = 1,
		ScaleRange = 1,
		DamageRange = CONFIG.FallbackDamage,
		WarningTime = CONFIG.FallbackWarningTime,
		HoldTime = CONFIG.FallbackHoldTime,
		MinSpacing = 8,
		MaxPlacementAttempts = 24,
		CandidateAttempts = 12,
	}
end

local function rollSpikeScale(tuning)
	return math.max(0.1, rollNumberRange(tuning and tuning.ScaleRange, 1))
end

local function getMaxSpikeScale(tuning)
	local range = tuning and tuning.ScaleRange
	if type(range) == "table" then
		local minValue = tonumber(range.Min) or tonumber(range[1]) or 1
		local maxValue = tonumber(range.Max) or tonumber(range[2]) or minValue
		return math.max(minValue, maxValue)
	end

	return tonumber(range) or 1
end

local function rollSpikeDamage(tuning)
	return math.max(0, rollIntegerRange(tuning and tuning.DamageRange, CONFIG.FallbackDamage))
end

local function rollSpikesPerSurface(tuning)
	return math.max(0, rollIntegerRange(tuning and tuning.SpikesPerSurface, 1))
end

local function getTargetSpikeModelScale(relativeScale)
	return math.max(0.01, (tonumber(CONFIG.SpikeVisualScale) or 1) * math.max(0.1, tonumber(relativeScale) or 1))
end

local function getPlacementAttemptsForTuning(tuning)
	return math.max(1, math.floor(tonumber(tuning and tuning.MaxPlacementAttempts) or 24))
end

local function getCandidateAttemptsForTuning(tuning)
	return math.max(1, math.floor(tonumber(tuning and tuning.CandidateAttempts) or 12))
end

local function buildSurfaceQueryOptions(footprintSize, tuning)
	return {
		Context = "DeckSpikes",
		FilterKey = "DeckSpikesStrictSurfaces",
		AllowAttributes = SPIKE_SURFACE_ALLOW_ATTRIBUTES,
		AllowTags = SPIKE_SURFACE_ALLOW_TAGS,
		DenyAttributes = SPIKE_SURFACE_DENY_ATTRIBUTES,
		DenyTags = SPIKE_SURFACE_DENY_TAGS,
		RequireExplicitOrFallbackSurface = true,
		FallbackSurfaceNames = getRarityPadSurfaceNames(),
		ExplicitSurfaceAcceptanceReason = "explicit_spike_marker",
		FallbackSurfaceAcceptanceReason = "rarity_pad_fallback",
		UnmarkedSurfaceRejectReason = "unmarked_non_rarity_surface",
		FootprintSize = footprintSize,
		EdgePadding = math.max(0, tonumber(CONFIG.SurfaceEdgePadding) or 0),
		CandidateAttempts = getCandidateAttemptsForTuning(tuning),
		MinSurfaceSize = 4,
	}
end

local function getPlanarUnit(vector, fallback)
	local planar = typeof(vector) == "Vector3" and Vector3.new(vector.X, 0, vector.Z) or Vector3.zero
	if planar.Magnitude > 0.001 then
		return planar.Unit
	end

	local fallbackPlanar = typeof(fallback) == "Vector3" and Vector3.new(fallback.X, 0, fallback.Z) or Vector3.zero
	if fallbackPlanar.Magnitude > 0.001 then
		return fallbackPlanar.Unit
	end

	return Vector3.zAxis
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
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
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

local function resolveRefs()
	local refs = MapResolver.WaitForRefs(
		{ "MapRoot", "WaveFolder", "Biomes" },
		nil,
		{
			warn = true,
			context = "DeckSpikes",
		}
	)

	local waveFolder = refs.WaveFolder
	local hazardsFolder = waveFolder and waveFolder:FindFirstChild("Hazards")
	if waveFolder and not hazardsFolder then
		hazardsFolder = Instance.new("Folder")
		hazardsFolder.Name = "Hazards"
		hazardsFolder.Parent = waveFolder
	end

	return refs, hazardsFolder
end

local function buildGroundRaycastParams(hazardsFolder)
	local exclusions = {}
	if hazardsFolder then
		exclusions[#exclusions + 1] = hazardsFolder
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
		for _, keyword in ipairs(CONFIG.SafeFloorNameKeywords) do
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

local function raycastGround(position, hazardsFolder, raycastParams)
	local height = math.max(10, tonumber(CONFIG.GroundProbeHeight) or 120)
	local depth = math.max(height + 10, tonumber(CONFIG.GroundProbeDepth) or 260)
	local result = Workspace:Raycast(
		position + Vector3.new(0, height, 0),
		Vector3.new(0, -depth, 0),
		raycastParams or buildGroundRaycastParams(hazardsFolder)
	)

	if result
		and result.Instance
		and result.Instance:IsA("BasePart")
		and result.Instance.CanCollide == true
		and result.Normal.Y >= math.clamp(tonumber(CONFIG.GroundNormalMin) or 0.65, 0, 1)
		and not isUnsafeSpikeSurface(result.Instance)
	then
		return result.Position
	end

	return nil
end

local function hasSafeGroundForFootprint(position, hazardsFolder, forward, lateral, size, supportPadding)
	local raycastParams = buildGroundRaycastParams(hazardsFolder)
	local centerPosition = raycastGround(position, hazardsFolder, raycastParams)
	if not centerPosition then
		return nil
	end

	local forwardUnit = getPlanarUnit(forward, Vector3.zAxis)
	local lateralUnit = getPlanarUnit(lateral, Vector3.xAxis)
	local buffer = math.clamp(tonumber(supportPadding) or tonumber(CONFIG.FootprintSupportPadding) or 0, 0, 8)
	local sampleX = math.max(1, (size.X * 0.5) + buffer)
	local sampleZ = math.max(1, (size.Z * 0.5) + buffer)
	local maxHeightDelta = math.max(0.5, tonumber(CONFIG.MaxGroundHeightDelta) or 3)
	local spacing = math.max(2, tonumber(CONFIG.FootprintSampleSpacing) or 8)
	local maxSteps = math.max(2, math.floor(tonumber(CONFIG.MaxFootprintSampleSteps) or 8))
	local xSteps = math.clamp(math.ceil((sampleX * 2) / spacing), 2, maxSteps)
	local zSteps = math.clamp(math.ceil((sampleZ * 2) / spacing), 2, maxSteps)

	for xIndex = 0, xSteps do
		local xAlpha = if xSteps > 0 then xIndex / xSteps else 0.5
		local x = -sampleX + (sampleX * 2 * xAlpha)
		for zIndex = 0, zSteps do
			local zAlpha = if zSteps > 0 then zIndex / zSteps else 0.5
			local z = -sampleZ + (sampleZ * 2 * zAlpha)
			local offset = (lateralUnit * x) + (forwardUnit * z)
			local samplePosition = raycastGround(position + offset, hazardsFolder, raycastParams)
			if not samplePosition or math.abs(samplePosition.Y - centerPosition.Y) > maxHeightDelta then
				return nil
			end
		end
	end

	return centerPosition
end

local function getAreaNameForBiome(biomeIndex)
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)
	local entry = BiomeAreas.GetBiome and BiomeAreas.GetBiome(normalizedBiome)
	return entry and entry.AreaName or nil
end

local function findSpikeTrapFolder()
	return StudioAssetResolver.ResolveAsset("SpikeTraps", {
		Context = "DeckSpikes",
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

local function findSpikeTrapTemplate(areaName)
	local key = string.lower(tostring(areaName or ""))
	local cachedTemplate = templateCacheByArea[key]
	if cachedTemplate and cachedTemplate.Parent then
		return cachedTemplate
	elseif cachedTemplate then
		templateCacheByArea[key] = nil
	end

	local folder = findSpikeTrapFolder()
	if not folder then
		return nil
	end

	local namedTemplate = SPIKE_TEMPLATE_NAMES_BY_AREA[key]
	if namedTemplate then
		local template = folder:FindFirstChild(namedTemplate, true)
		if template and template:IsA("Model") then
			templateCacheByArea[key] = template
			return template
		end
	end

	local candidates = {}
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Model") then
			candidates[#candidates + 1] = descendant
		end
	end

	for _, candidate in ipairs(candidates) do
		local candidateName = string.lower(candidate.Name)
		for _, token in ipairs(SPIKE_TEMPLATE_TOKENS_BY_AREA[key] or {}) do
			if candidateName:find(token, 1, true) then
				templateCacheByArea[key] = candidate
				return candidate
			end
		end
	end

	for _, candidate in ipairs(candidates) do
		if findHitbox(candidate) or #getBaseParts(candidate) > 0 then
			templateCacheByArea[key] = candidate
			return candidate
		end
	end

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

local function getSpikeTemplateMetadata(areaName)
	local key = string.lower(tostring(areaName or ""))
	local cached = templateMetadataCacheByArea[key]
	if cached and cached.Template and cached.Template.Parent then
		return cached
	elseif cached then
		templateMetadataCacheByArea[key] = nil
	end

	local template = CONFIG.UseSpikeTrapTemplates and findSpikeTrapTemplate(areaName) or nil
	if not template then
		return nil
	end

	local boundsCFrame, boundsSize = template:GetBoundingBox()
	local hitbox = findHitbox(template)
	local sourceSize = hitbox and hitbox.Size or boundsSize
	local metadata = {
		Template = template,
		TemplateName = template.Name,
		TemplateScale = math.max(0.001, template:GetScale()),
		SourceHitboxSize = Vector3.new(
			math.max(1, sourceSize.X),
			math.max(1, sourceSize.Y),
			math.max(1, sourceSize.Z)
		),
		SourceBoundsSize = boundsSize,
		SourceBoundsCFrame = boundsCFrame,
	}

	templateMetadataCacheByArea[key] = metadata
	return metadata
end

local function getSpikeFootprintSize(areaName, relativeScale)
	local targetScale = getTargetSpikeModelScale(relativeScale)
	local metadata = getSpikeTemplateMetadata(areaName)
	local size = CONFIG.GeneratedSpikeBaseSize * targetScale
	if metadata then
		local scaleRatio = targetScale / metadata.TemplateScale
		size = metadata.SourceHitboxSize * scaleRatio
	end

	size = Vector3.new(math.max(1, size.X), math.max(1, size.Y), math.max(1, size.Z))

	return size, metadata
end

local function configureSpikeVisual(model, hitbox)
	for _, part in ipairs(getBaseParts(model)) do
		configurePart(part, part == hitbox, part == hitbox)
		if part == hitbox then
			part.Transparency = 1
			part:SetAttribute("HazardClass", CONFIG.HazardClass)
			part:SetAttribute("HazardType", CONFIG.HazardType)
			markHazardHitboxPart(part)
		end
	end
end

local function isPointInsidePart(part, worldPosition)
	local localPosition = part.CFrame:PointToObjectSpace(worldPosition)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y + 4
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function cleanupActiveControllers()
	local count = 0
	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
		else
			count += 1
		end
	end

	return count
end

local function createFootprintRecord(placement, spacing)
	local margin = math.max(0, tonumber(spacing) or 0)
	return {
		Center = placement.GroundPosition,
		Forward = getPlanarUnit(placement.Forward, Vector3.zAxis),
		Lateral = getPlanarUnit(placement.Lateral, Vector3.xAxis),
		HalfX = (placement.Size.X * 0.5) + margin,
		HalfZ = (placement.Size.Z * 0.5) + margin,
	}
end

local function footprintsOverlap(a, b)
	if not (a and b) then
		return false
	end

	local delta = b.Center - a.Center
	local aX = math.abs(delta:Dot(a.Lateral))
	local aZ = math.abs(delta:Dot(a.Forward))
	if aX <= (a.HalfX + b.HalfX) and aZ <= (a.HalfZ + b.HalfZ) then
		return true
	end

	local bX = math.abs(delta:Dot(b.Lateral))
	local bZ = math.abs(delta:Dot(b.Forward))
	return bX <= (a.HalfX + b.HalfX) and bZ <= (a.HalfZ + b.HalfZ)
end

local function isTooCloseToActiveSpike(placement, reservedFootprints, tuning)
	local candidate = createFootprintRecord(placement, tuning and tuning.MinSpacing)

	for _, reserved in ipairs(reservedFootprints or {}) do
		if footprintsOverlap(candidate, reserved) then
			return true
		end
	end

	for model, controller in pairs(activeControllers) do
		if controller and not controller.Destroyed and model.Parent and controller.Footprint then
			if footprintsOverlap(candidate, controller.Footprint) then
				return true
			end
		end
	end

	return false
end

local function getSpikeSurfaceEntries(refs, biomeIndex, tuning, footprintSize)
	local options = buildSurfaceQueryOptions(footprintSize, tuning)
	return BiomePlacementResolver.GetBiomeSurfaceEntries(refs, biomeIndex, options)
end

local function warnSpikePlacementFailure(biomeIndex, areaName, templateName, reason, diagnostics)
	local summary = diagnostics or {}
	local rootPath = tostring(summary.RootPath or "<nil>")
	local surfaceCount = tonumber(summary.SurfaceCount) or 0
	local explicitCount = tonumber(summary.ExplicitSurfaceCount) or 0
	local fallbackCount = tonumber(summary.FallbackSurfaceCount) or 0
	local rejectionSource = summary.Diagnostics or summary
	local rejectionSummary = BiomePlacementResolver.FormatRejectionSummary(rejectionSource)
	local rejectionSamples = BiomePlacementResolver.FormatRejectionSamples(rejectionSource)
	local key = string.format("%s:%s:%s", tostring(biomeIndex), tostring(reason), rootPath)

	warnPlacementFailure(
		key,
		"[DECK SPIKES] placement_failed biome=%s area=%s template=%s reason=%s root=%s surfaceCount=%s explicitSurfaces=%s fallbackSurfaces=%s rejections={%s} samples={%s}",
		tostring(biomeIndex),
		tostring(areaName or ""),
		tostring(templateName or ""),
		tostring(reason or "unknown"),
		rootPath,
		tostring(surfaceCount),
		tostring(explicitCount),
		tostring(fallbackCount),
		rejectionSummary,
		rejectionSamples
	)
end

local function chooseSpikePlacement(refs, hazardsFolder, biomeIndex, tuning, surfaceEntry, reservedFootprints, targetCount)
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, CONFIG.BiomeCount)
	local areaName = getAreaNameForBiome(normalizedBiome)
	local relativeScale = rollSpikeScale(tuning)
	local size, metadata = getSpikeFootprintSize(areaName, relativeScale)
	local options = buildSurfaceQueryOptions(size, tuning)
	local attempts = getPlacementAttemptsForTuning(tuning)
	local lastReason = "no_candidate"
	local lastDiagnostics = nil

	for _ = 1, attempts do
		local candidate, reason, diagnostics
		if surfaceEntry then
			candidate, reason, diagnostics = BiomePlacementResolver.GetRandomSurfaceCandidateFromEntry(
				refs,
				normalizedBiome,
				surfaceEntry,
				rng,
				options
			)
		else
			candidate, reason, diagnostics =
				BiomePlacementResolver.GetRandomSurfaceCandidate(refs, normalizedBiome, rng, options)
		end

		lastReason = reason or lastReason
		lastDiagnostics = diagnostics or lastDiagnostics
		if candidate then
			local groundPosition = hasSafeGroundForFootprint(
				candidate.Position,
				hazardsFolder,
				candidate.Forward,
				candidate.Lateral,
				size,
				CONFIG.FootprintSupportPadding
			)
			if groundPosition then
				local placement = {
					GroundPosition = groundPosition,
					Forward = candidate.Forward,
					Lateral = candidate.Lateral,
					Size = size,
					BiomeIndex = normalizedBiome,
					AreaName = areaName,
					TemplateName = metadata and metadata.TemplateName or "generated_spike",
					PlacementSource = "BiomeSurface",
					PlacementPart = candidate.Part,
					PlacementPartPath = formatInstancePath(candidate.Part),
					PlacementSurfaceReason = candidate.SurfaceAcceptanceReason,
					BiomeRootPath = candidate.BiomeRootPath,
					PlacementSurfaceCount = candidate.SurfaceCount,
					SpikeBand = tuning and tuning.Id or 0,
					RolledScale = relativeScale,
					TargetModelScale = getTargetSpikeModelScale(relativeScale),
					SpikeDamage = rollSpikeDamage(tuning),
					SpikeWarningDuration = tonumber(tuning and tuning.WarningTime) or CONFIG.FallbackWarningTime,
					SpikeActiveDuration = tonumber(tuning and tuning.HoldTime) or CONFIG.FallbackHoldTime,
					SpikesPerSurface = tonumber(targetCount) or rollSpikesPerSurface(tuning),
				}

				if not isTooCloseToActiveSpike(placement, reservedFootprints, tuning) then
					return placement
				end

				lastReason = "overlaps_existing_spike"
			else
				lastReason = "unsafe_footprint"
			end
		elseif reason == "missing_biome_root" or reason == "no_biome_surfaces" then
			break
		end
	end

	warnSpikePlacementFailure(
		normalizedBiome,
		areaName,
		metadata and metadata.TemplateName or "",
		lastReason,
		lastDiagnostics
	)
	return nil
end

local function makeController(model, hitbox, warning, visual, hiddenCFrame, extendedCFrame, placement)
	local controller = {
		Model = model,
		Hitbox = hitbox,
		Warning = warning,
		Visual = visual,
		HiddenCFrame = hiddenCFrame,
		ExtendedCFrame = extendedCFrame,
		Footprint = placement and createFootprintRecord(placement, 0) or nil,
		SurfaceKey = placement and placement.PlacementPartPath or nil,
		Damage = placement and placement.SpikeDamage or CONFIG.FallbackDamage,
		WarningTime = placement and placement.SpikeWarningDuration or CONFIG.FallbackWarningTime,
		HoldTime = placement and placement.SpikeActiveDuration or CONFIG.FallbackHoldTime,
		Active = false,
		Destroyed = false,
		DamagedPlayers = {},
	}

	activeControllers[model] = controller

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		activeControllers[self.Model] = nil
		if self.Model.Parent then
			self.Model:Destroy()
		end
	end

	return controller
end

local function createTemplateSpike(model, placement, areaName)
	local metadata = getSpikeTemplateMetadata(areaName)
	local template = metadata and metadata.Template or nil
	if not template then
		return nil
	end

	local visual = template:Clone()
	visual.Name = "SpikeTrapVisual"
	visual.Parent = model
	visual:ScaleTo(math.max(0.01, tonumber(placement.TargetModelScale) or getTargetSpikeModelScale(1)))

	local hitbox = getOrCreateHitbox(visual)
	configureSpikeVisual(visual, hitbox)

	local orientedPivot = CFrame.fromMatrix(placement.GroundPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
	visual:PivotTo(orientedPivot)

	local hitboxCenterDelta = Vector3.new(
		placement.GroundPosition.X - hitbox.Position.X,
		0,
		placement.GroundPosition.Z - hitbox.Position.Z
	)
	visual:PivotTo(visual:GetPivot() + hitboxCenterDelta)

	local boundsCFrame, boundsSize = visual:GetBoundingBox()
	local visualBottomY = boundsCFrame.Position.Y - (boundsSize.Y * 0.5)
	local groundDeltaY = placement.GroundPosition.Y - visualBottomY
	local extendedPivot = visual:GetPivot() + Vector3.new(0, groundDeltaY, 0)
	local riseHeight = math.max(0.1, boundsSize.Y, hitbox.Size.Y)
	local hiddenPivot = extendedPivot + Vector3.new(0, -(riseHeight - CONFIG.PreviewHeight), 0)
	visual:PivotTo(hiddenPivot)

	return visual, hitbox, hiddenPivot, extendedPivot
end

local function createGeneratedSpike(model, placement)
	local hiddenPosition = placement.GroundPosition - Vector3.new(0, (placement.Size.Y * 0.5) - CONFIG.PreviewHeight, 0)
	local extendedPosition = placement.GroundPosition + Vector3.new(0, placement.Size.Y * 0.5, 0)
	local hiddenCFrame = CFrame.fromMatrix(hiddenPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
	local extendedCFrame = CFrame.fromMatrix(extendedPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)

	local spike = createPart(
		model,
		"SpikeHitbox",
		placement.Size,
		hiddenCFrame,
		Color3.fromRGB(45, 45, 50),
		Enum.Material.Metal,
		0.05
	)
	configurePart(spike, true, true)
	spike:SetAttribute("HazardClass", CONFIG.HazardClass)
	spike:SetAttribute("HazardType", CONFIG.HazardType)
	markHazardHitboxPart(spike)

	return spike, spike, hiddenCFrame, extendedCFrame
end

local function setSpikePlacementAttributes(instance, placement)
	if not (instance and placement) then
		return
	end

	instance:SetAttribute("BiomeIndex", placement.BiomeIndex)
	instance:SetAttribute("AreaName", tostring(placement.AreaName or ""))
	instance:SetAttribute("TemplateName", tostring(placement.TemplateName or ""))
	instance:SetAttribute("PlacementSource", tostring(placement.PlacementSource or ""))
	instance:SetAttribute("PlacementPartPath", tostring(placement.PlacementPartPath or ""))
	instance:SetAttribute("PlacementSurfaceReason", tostring(placement.PlacementSurfaceReason or ""))
	instance:SetAttribute("BiomeRootPath", tostring(placement.BiomeRootPath or ""))
	instance:SetAttribute("PlacementSurfaceCount", tonumber(placement.PlacementSurfaceCount) or 0)
	instance:SetAttribute("SpikeBand", tonumber(placement.SpikeBand) or 0)
	instance:SetAttribute("RolledScale", tonumber(placement.RolledScale) or 1)
	instance:SetAttribute("SpikeDamage", tonumber(placement.SpikeDamage) or CONFIG.FallbackDamage)
	instance:SetAttribute("SpikeWarningDuration", tonumber(placement.SpikeWarningDuration) or CONFIG.FallbackWarningTime)
	instance:SetAttribute("SpikeActiveDuration", tonumber(placement.SpikeActiveDuration) or CONFIG.FallbackHoldTime)
	instance:SetAttribute("SpikesPerSurface", tonumber(placement.SpikesPerSurface) or 1)
end

local function createDeckSpike(hazardsFolder, placement)
	local model = Instance.new("Model")
	model.Name = "DeckSpikes"
	model:SetAttribute("HazardClass", CONFIG.HazardClass)
	model:SetAttribute("HazardType", CONFIG.HazardType)
	setSpikePlacementAttributes(model, placement)

	local warningPosition = placement.GroundPosition + Vector3.new(0, CONFIG.WarningGroundOffset, 0)
	local warningCFrame = CFrame.fromMatrix(warningPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
	local warning = createPart(
		model,
		"WarningFlash",
		Vector3.new(placement.Size.X, 0.12, placement.Size.Z),
		warningCFrame,
		Color3.fromRGB(255, 0, 0),
		Enum.Material.Neon,
		0.12
	)

	local areaName = getAreaNameForBiome(placement.BiomeIndex)
	local visual, hitbox, hiddenCFrame, extendedCFrame = createTemplateSpike(model, placement, areaName)
	if not visual then
		visual, hitbox, hiddenCFrame, extendedCFrame = createGeneratedSpike(model, placement)
	end

	if hitbox then
		warning.Size = Vector3.new(math.max(1, hitbox.Size.X), 0.12, math.max(1, hitbox.Size.Z))
		warning.CFrame = warningCFrame
		setSpikePlacementAttributes(hitbox, placement)
	end

	model.Parent = hazardsFolder
	return makeController(model, hitbox, warning, visual, hiddenCFrame, extendedCFrame, placement)
end

local function tweenVisual(controller, targetCFrame, duration, easingDirection)
	if controller.Destroyed or not controller.Model.Parent then
		return
	end

	local tweenInfo = TweenInfo.new(math.max(0, duration), Enum.EasingStyle.Quad, easingDirection)
	if controller.Visual:IsA("Model") then
		local cframeValue = Instance.new("CFrameValue")
		cframeValue.Value = controller.Visual:GetPivot()
		local connection = cframeValue:GetPropertyChangedSignal("Value"):Connect(function()
			if controller.Visual.Parent then
				controller.Visual:PivotTo(cframeValue.Value)
			end
		end)
		local tween = TweenService:Create(cframeValue, tweenInfo, { Value = targetCFrame })
		tween:Play()
		tween.Completed:Wait()
		connection:Disconnect()
		cframeValue:Destroy()
	else
		local tween = TweenService:Create(controller.Visual, tweenInfo, { CFrame = targetCFrame })
		tween:Play()
		tween.Completed:Wait()
	end
end

local function damagePlayer(controller, player)
	if controller.DamagedPlayers[player] then
		return false
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return false
	end

	if not isPointInsidePart(controller.Hitbox, rootPart.Position) then
		return false
	end

	if not raycastGround(rootPart.Position, controller.Model.Parent) then
		return false
	end

	local isHazardProtected = HazardProtection.IsProtected(player, {
		Position = rootPart.Position,
		HazardClass = CONFIG.HazardClass,
		HazardType = CONFIG.HazardType,
		Source = "DeckSpikes",
	})
	if isHazardProtected then
		return false
	end

	HitEffectService.ApplyEffect(player, "Knockdown", {
		Duration = CONFIG.KnockdownDuration,
		Priority = 30,
		HazardClass = CONFIG.HazardClass,
		HazardType = CONFIG.HazardType,
		Source = "DeckSpikes",
		Movement = {
			WalkSpeedMultiplier = 0,
			JumpMultiplier = 0,
			AutoRotate = false,
			PlatformStand = true,
			State = Enum.HumanoidStateType.Physics,
		},
	})

	humanoid:TakeDamage(controller.Damage or CONFIG.FallbackDamage)
	controller.DamagedPlayers[player] = true
	return true
end

local function damagePlayersInside(controller)
	for _, player in ipairs(Players:GetPlayers()) do
		damagePlayer(controller, player)
	end
end

local function runDeckSpike(controller)
	task.wait(controller.WarningTime or CONFIG.FallbackWarningTime)
	if controller.Destroyed then
		return
	end

	if controller.Warning.Parent then
		controller.Warning.Transparency = 1
	end

	controller.Active = true
	tweenVisual(controller, controller.ExtendedCFrame, CONFIG.ThrustTime, Enum.EasingDirection.Out)
	damagePlayersInside(controller)

	local elapsed = 0
	while elapsed < (controller.HoldTime or CONFIG.FallbackHoldTime) do
		if controller.Destroyed or not controller.Model.Parent then
			return
		end

		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		damagePlayersInside(controller)
	end

	controller.Active = false
	tweenVisual(controller, controller.HiddenCFrame, CONFIG.RetractTime, Enum.EasingDirection.In)
	controller:Destroy()
end

local function getActiveSpikeCountsBySurface()
	local counts = {}
	for model, controller in pairs(activeControllers) do
		if controller and not controller.Destroyed and model.Parent and controller.SurfaceKey then
			counts[controller.SurfaceKey] = (counts[controller.SurfaceKey] or 0) + 1
		end
	end
	return counts
end

local function getSurfaceKey(surfaceEntry)
	return formatInstancePath(surfaceEntry and surfaceEntry.Part)
end

local function shuffleJobs(jobs)
	for index = #jobs, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		jobs[index], jobs[swapIndex] = jobs[swapIndex], jobs[index]
	end
end

local function spawnDeckSpike(refs, hazardsFolder, biomeIndex, tuning, surfaceEntry, reservedFootprints, targetCount)
	if cleanupActiveControllers() >= CONFIG.MaxActiveSpikes then
		return false
	end

	local placement =
		chooseSpikePlacement(refs, hazardsFolder, biomeIndex, tuning, surfaceEntry, reservedFootprints, targetCount)
	if not placement then
		return false
	end

	reservedFootprints[#reservedFootprints + 1] = createFootprintRecord(placement, tuning and tuning.MinSpacing)

	local controller = createDeckSpike(hazardsFolder, placement)
	if not controller then
		return false
	end

	task.spawn(function()
		runDeckSpike(controller)
	end)

	return true
end

local function spawnSpikePop()
	local refs, hazardsFolder = resolveRefs()
	if not hazardsFolder or not refs or not refs.Biomes then
		return
	end

	local activeCountsBySurface = getActiveSpikeCountsBySurface()
	local reservedCountsBySurface = {}
	local reservedFootprints = {}
	local jobs = {}
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))

	for biomeIndex = 1, biomeCount do
		local tuning = getSpikeTuningForBiome(biomeIndex)
		local areaName = getAreaNameForBiome(biomeIndex)
		local maxScale = getMaxSpikeScale(tuning)
		local footprintSize = getSpikeFootprintSize(areaName, maxScale)
		local surfaceEntries, surfaceSummary = getSpikeSurfaceEntries(refs, biomeIndex, tuning, footprintSize)

		if #surfaceEntries == 0 then
			warnSpikePlacementFailure(
				biomeIndex,
				areaName,
				"",
				"no_spike_surfaces",
				surfaceSummary
			)
		else
			for _, surfaceEntry in ipairs(surfaceEntries) do
				local surfaceKey = getSurfaceKey(surfaceEntry)
				local targetCount = rollSpikesPerSurface(tuning)
				local currentCount = activeCountsBySurface[surfaceKey] or 0
				local reservedCount = reservedCountsBySurface[surfaceKey] or 0
				local missing = math.max(0, targetCount - currentCount - reservedCount)
				for _ = 1, missing do
					jobs[#jobs + 1] = {
						BiomeIndex = biomeIndex,
						Tuning = tuning,
						SurfaceEntry = surfaceEntry,
						SpikesPerSurface = targetCount,
					}
					reservedCountsBySurface[surfaceKey] = (reservedCountsBySurface[surfaceKey] or 0) + 1
				end
			end
		end
	end

	shuffleJobs(jobs)

	local maxOperations = math.max(1, math.floor(tonumber(CONFIG.MaxSpawnOperationsPerCycle) or 1))
	for index = 1, math.min(maxOperations, #jobs) do
		local job = jobs[index]
		local ok, err = xpcall(function()
			spawnDeckSpike(
				refs,
				hazardsFolder,
				job.BiomeIndex,
				job.Tuning,
				job.SurfaceEntry,
				reservedFootprints,
				job.SpikesPerSurface
			)
		end, debug.traceback)
		if not ok then
			warn(string.format("[DECK SPIKES] spawn error=%s", tostring(err)))
		end
	end
end

local function getSpawnDelay()
	local minDelay = math.max(0.03, tonumber(CONFIG.SpawnDelayMin) or 0.1)
	local maxDelay = math.max(minDelay, tonumber(CONFIG.SpawnDelayMax) or minDelay)
	return rng:NextNumber(minDelay, maxDelay)
end

local noDisastersTimer = getNoDisastersTimer()
task.wait(math.max(0, tonumber(CONFIG.InitialSpawnDelay) or 0))

while true do
	if isNoDisastersPaused(noDisastersTimer) then
		task.wait(1)
	else
		spawnSpikePop()
		task.wait(getSpawnDelay())
	end
end
