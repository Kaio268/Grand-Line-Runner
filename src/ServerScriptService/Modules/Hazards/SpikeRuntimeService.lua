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
local GameSounds = require(Modules:WaitForChild("GameSounds"))
local RuntimeScheduler = require(Modules:WaitForChild("RuntimeScheduler"))
local PerformanceFlags = require(Modules:WaitForChild("Configs"):WaitForChild("PerformanceArchitectureFlags"))
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

local SpikeRuntimeService = {}

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
	HoldScanInterval = 0.2,
	KnockdownDuration = 0.8,
	HazardClass = "minor",
	HazardType = "deck_spikes",
	UseSpikeTrapTemplates = true,
	IgnoreNoDisastersTimerInStudio = true,
	DormantCrewSpikes = {
		Enabled = true,
		DebugTrace = false,
		Chance = 0.25,
		ChanceByBiome = {},
		ChanceByPlacementRarity = {},

		MaxActive = 16,
		CountsTowardNormalCap = false,
		OnePerCrewmate = true,

		DespawnWhenCrewmateRemoved = true,
		KeepActivatedAfterCrewmateRemoved = true,
		DormantLifetime = nil,

		ActivationDebounce = 1,
		ActivationWarningTime = 0,
		RaiseImmediatelyOnTrigger = true,
		TriggerHeight = 4,
		ShowDormantWarningFlash = false,
		BladeHiddenPadding = 0.15,

		DormantGlowColor = Color3.fromRGB(70, 170, 255),
		AttackGlowColor = Color3.fromRGB(255, 0, 0),
		DormantGlowTransparency = 0.18,
		AttackGlowTransparency = 0.12,
	},

	-- Spike balance knobs:
	-- SpikesPerSurface should stay at 1 so each accepted Platform gets one spike placement.
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
			SpikesPerSurface = 1,
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
			SpikesPerSurface = 1,
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
			SpikesPerSurface = 1,
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
			SpikesPerSurface = 1,
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

if CONFIG.Enabled then
	StudioAssetResolver.ValidateRequiredAssets({ "SpikeTraps" }, "DeckSpikes")
end

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

local SPIKE_BASE_ROLE_ATTRIBUTES = {
	"SpikeBase",
}

local SPIKE_MOVING_ROLE_ATTRIBUTES = {
	"SpikeBlade",
	"SpikeMoving",
}

local SPIKE_HITBOX_ROLE_ATTRIBUTES = {
	"SpikeHitbox",
}

local rng = Random.new()
local activeControllers = {}
local scheduledSpikeHolds = {}
local spikeHoldTaskHandle = nil
local spikeHoldScanElapsed = 0
local dormantByCrewModel = setmetatable({}, { __mode = "k" })
local normalLoopStarted = false
local templateCacheByArea = {}
local templateMetadataCacheByArea = {}
local warnedPlacementFailures = {}
local warnedTemplateRoleFailures = {}

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

local function getPlatformSurfaceNames()
	local getNames = SpawnPartsConfig.GetPlacementSurfaceNames
	return if type(getNames) == "function" then getNames() else { "Platform" }
end

local function getDormantCrewSpikeConfig()
	return if type(CONFIG.DormantCrewSpikes) == "table" then CONFIG.DormantCrewSpikes else {}
end

local function isDormantDebugTraceEnabled()
	local dormantConfig = getDormantCrewSpikeConfig()
	return dormantConfig.DebugTrace == true
		or (RunService:IsStudio() and game:GetAttribute("DormantCrewSpikeDebugTrace") == true)
end

local function traceDormantCrewSpike(context, outcome, reason)
	if not isDormantDebugTraceEnabled() then
		return
	end

	context = if typeof(context) == "table" then context else {}
	print(string.format(
		"[DORMANT SPIKES] %s reason=%s crewModel=%s spawnPart=%s biomeIndex=%s placementRarity=%s",
		tostring(outcome or "unknown"),
		tostring(reason or ""),
		formatInstancePath(context.CrewModel),
		formatInstancePath(context.SpawnPart),
		tostring(context.BiomeIndex),
		tostring(context.PlacementRarity)
	))
end

local function finishDormantCrewSpike(context, success, reason)
	traceDormantCrewSpike(context, if success then "spawned" else "skipped", reason)
	return success, reason
end

local function getAttackGlowColor()
	local dormantConfig = getDormantCrewSpikeConfig()
	return if typeof(dormantConfig.AttackGlowColor) == "Color3"
		then dormantConfig.AttackGlowColor
		else Color3.fromRGB(255, 0, 0)
end

local function getAttackGlowTransparency()
	local dormantConfig = getDormantCrewSpikeConfig()
	return math.clamp(tonumber(dormantConfig.AttackGlowTransparency) or 0.12, 0, 1)
end

local function getDormantGlowColor()
	local dormantConfig = getDormantCrewSpikeConfig()
	return if typeof(dormantConfig.DormantGlowColor) == "Color3"
		then dormantConfig.DormantGlowColor
		else Color3.fromRGB(70, 170, 255)
end

local function getDormantGlowTransparency()
	local dormantConfig = getDormantCrewSpikeConfig()
	return math.clamp(tonumber(dormantConfig.DormantGlowTransparency) or 0.18, 0, 1)
end

local function shouldShowDormantWarningFlash()
	return getDormantCrewSpikeConfig().ShowDormantWarningFlash == true
end

local function getDormantBladeHiddenPadding()
	return math.max(0, tonumber(getDormantCrewSpikeConfig().BladeHiddenPadding) or 0.15)
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
		FallbackSurfaceNames = getPlatformSurfaceNames(),
		ExplicitSurfaceAcceptanceReason = "explicit_spike_marker",
		FallbackSurfaceAcceptanceReason = "platform_surface",
		UnmarkedSurfaceRejectReason = "unmarked_non_platform_surface",
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

local function appendRaycastExclusion(exclusions, exclusion)
	if typeof(exclusion) == "Instance" then
		exclusions[#exclusions + 1] = exclusion
	elseif type(exclusion) == "table" then
		for _, nestedExclusion in ipairs(exclusion) do
			appendRaycastExclusion(exclusions, nestedExclusion)
		end
	end
end

local function buildGroundRaycastParams(hazardsFolder, extraExclusions)
	local exclusions = {}
	if hazardsFolder then
		exclusions[#exclusions + 1] = hazardsFolder
	end
	appendRaycastExclusion(exclusions, extraExclusions)

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

local function isWithinPlacementRoot(instance, placementRoot)
	if not placementRoot then
		return true
	end

	return instance == placementRoot or instance:IsDescendantOf(placementRoot)
end

local function raycastGround(position, hazardsFolder, raycastParams, placementRoot)
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
		and isWithinPlacementRoot(result.Instance, placementRoot)
		and result.Instance.CanCollide == true
		and result.Normal.Y >= math.clamp(tonumber(CONFIG.GroundNormalMin) or 0.65, 0, 1)
		and not isUnsafeSpikeSurface(result.Instance)
	then
		return result.Position
	end

	return nil
end

local function hasSafeGroundForFootprint(
	position,
	hazardsFolder,
	forward,
	lateral,
	size,
	supportPadding,
	placementRoot,
	extraRaycastExclusions
)
	local raycastParams = buildGroundRaycastParams(hazardsFolder, extraRaycastExclusions)
	local centerPosition = raycastGround(position, hazardsFolder, raycastParams, placementRoot)
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
			local samplePosition = raycastGround(position + offset, hazardsFolder, raycastParams, placementRoot)
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

local function hasAnyRoleAttribute(part, attributes)
	for _, attributeName in ipairs(attributes) do
		if part:GetAttribute(attributeName) == true then
			return true
		end
	end

	return false
end

local function appendUniquePart(parts, part)
	if not (part and part:IsA("BasePart")) then
		return
	end

	for _, existing in ipairs(parts) do
		if existing == part then
			return
		end
	end

	parts[#parts + 1] = part
end

local function collectSpikeVisualParts(model)
	local roles = {
		BaseParts = {},
		MovingParts = {},
		Hitbox = nil,
	}
	local exactBaseParts = {}
	local exactMovingParts = {}
	local exactHitbox = nil

	for _, part in ipairs(getBaseParts(model)) do
		local lowerName = string.lower(part.Name)
		if hasAnyRoleAttribute(part, SPIKE_HITBOX_ROLE_ATTRIBUTES) then
			roles.Hitbox = roles.Hitbox or part
		elseif lowerName == "hitbox" then
			exactHitbox = exactHitbox or part
		end

		if hasAnyRoleAttribute(part, SPIKE_BASE_ROLE_ATTRIBUTES) then
			appendUniquePart(roles.BaseParts, part)
		elseif lowerName == "base" then
			appendUniquePart(exactBaseParts, part)
		end

		if hasAnyRoleAttribute(part, SPIKE_MOVING_ROLE_ATTRIBUTES) then
			appendUniquePart(roles.MovingParts, part)
		elseif lowerName == "spikes" then
			appendUniquePart(exactMovingParts, part)
		end
	end

	if not roles.Hitbox then
		roles.Hitbox = exactHitbox or findHitbox(model)
	end
	if #roles.BaseParts == 0 then
		roles.BaseParts = exactBaseParts
	end
	if #roles.MovingParts == 0 then
		roles.MovingParts = exactMovingParts
	end
	appendUniquePart(roles.MovingParts, roles.Hitbox)

	return roles
end

local function getPartsVerticalBounds(parts)
	local minY = math.huge
	local maxY = -math.huge

	for _, part in ipairs(parts or {}) do
		if part and part.Parent then
			local halfSize = part.Size * 0.5
			local cframeValue = part.CFrame
			local verticalHalfExtent = math.abs(cframeValue.RightVector.Y) * halfSize.X
				+ math.abs(cframeValue.UpVector.Y) * halfSize.Y
				+ math.abs(cframeValue.LookVector.Y) * halfSize.Z
			minY = math.min(minY, part.Position.Y - verticalHalfExtent)
			maxY = math.max(maxY, part.Position.Y + verticalHalfExtent)
		end
	end

	if minY == math.huge then
		return nil, nil
	end

	return minY, maxY
end

local function warnDormantTemplateRoleFailure(templateName, reason)
	local key = tostring(templateName or "unknown") .. ":" .. tostring(reason or "unknown")
	if warnedTemplateRoleFailures[key] then
		return
	end

	warnedTemplateRoleFailures[key] = true
	warn(string.format(
		"[DORMANT SPIKES] template_role_failed template=%s reason=%s",
		tostring(templateName or ""),
		tostring(reason or "unknown")
	))
end

local function buildSeparatedSpikeMotion(model, hitbox, extendedCFrame, templateName)
	local roles = collectSpikeVisualParts(model)
	appendUniquePart(roles.MovingParts, hitbox)

	if #roles.BaseParts == 0 then
		warnDormantTemplateRoleFailure(templateName, "missing_base")
		return nil, nil
	end
	if #roles.MovingParts == 0 then
		warnDormantTemplateRoleFailure(templateName, "missing_moving_parts")
		return nil, nil
	end

	local _, baseTopY = getPartsVerticalBounds(roles.BaseParts)
	local _, movingTopY = getPartsVerticalBounds(roles.MovingParts)
	if not baseTopY or not movingTopY then
		warnDormantTemplateRoleFailure(templateName, "invalid_part_bounds")
		return nil, nil
	end

	local hiddenDistance = math.max(0.1, movingTopY - baseTopY + getDormantBladeHiddenPadding())
	local hiddenCFrame = extendedCFrame + Vector3.new(0, -hiddenDistance, 0)
	local motionParts = {}
	for _, part in ipairs(roles.MovingParts) do
		motionParts[#motionParts + 1] = {
			Part = part,
			RelativeCFrame = extendedCFrame:ToObjectSpace(part.CFrame),
		}
	end

	for _, entry in ipairs(motionParts) do
		entry.Part.CFrame = hiddenCFrame * entry.RelativeCFrame
	end

	return motionParts, hiddenCFrame
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

local function shouldCountTowardNormalCap(controller)
	if not controller then
		return false
	end

	if controller.Mode ~= "DormantCrew" then
		return true
	end

	return getDormantCrewSpikeConfig().CountsTowardNormalCap == true
end

local function cleanupActiveControllers()
	local count = 0
	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
		elseif shouldCountTowardNormalCap(controller) then
			count += 1
		end
	end

	return count
end

local function countDormantCrewControllers()
	local count = 0
	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
		elseif controller.Mode == "DormantCrew" then
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
				CONFIG.FootprintSupportPadding,
				candidate.Root
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

local function makeController(model, hitbox, warning, visual, hiddenCFrame, extendedCFrame, placement, motionParts)
	local controller = {
		Model = model,
		Hitbox = hitbox,
		Warning = warning,
		Visual = visual,
		HiddenCFrame = hiddenCFrame,
		ExtendedCFrame = extendedCFrame,
		MotionParts = motionParts,
		MotionCFrame = if motionParts and #motionParts > 0 then hiddenCFrame else nil,
		Footprint = placement and createFootprintRecord(placement, 0) or nil,
		PlacementPart = placement and placement.PlacementPart or nil,
		PlacementPartPath = placement and placement.PlacementPartPath or nil,
		Mode = tostring((placement and placement.SpikeMode) or "Normal"),
		CrewModel = placement and placement.CrewModel or nil,
		Damage = placement and placement.SpikeDamage or CONFIG.FallbackDamage,
		WarningTime = placement and placement.SpikeWarningDuration or CONFIG.FallbackWarningTime,
		HoldTime = placement and placement.SpikeActiveDuration or CONFIG.FallbackHoldTime,
		Active = false,
		Activated = false,
		Connections = {},
		Destroyed = false,
		DamagedPlayers = {},
	}

	activeControllers[model] = controller
	if controller.Mode == "DormantCrew" and controller.CrewModel then
		dormantByCrewModel[controller.CrewModel] = controller
	end

	function controller:Destroy()
		if self.Destroyed then
			return
		end

		self.Destroyed = true
		scheduledSpikeHolds[self] = nil
		activeControllers[self.Model] = nil
		if self.CrewModel and dormantByCrewModel[self.CrewModel] == self then
			dormantByCrewModel[self.CrewModel] = nil
		end
		for _, connection in ipairs(self.Connections or {}) do
			connection:Disconnect()
		end
		table.clear(self.Connections)
		if self.Trigger and self.Trigger.Parent then
			self.Trigger:Destroy()
		end
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

	if placement and placement.SpikeMode == "DormantCrew" then
		visual:PivotTo(extendedPivot)
		local motionParts, dormantHiddenPivot =
			buildSeparatedSpikeMotion(visual, hitbox, extendedPivot, metadata.TemplateName)
		if not motionParts then
			visual:Destroy()
			return nil
		end

		return visual, hitbox, dormantHiddenPivot, extendedPivot, motionParts
	end

	visual:PivotTo(hiddenPivot)

	return visual, hitbox, hiddenPivot, extendedPivot
end

local function createGeneratedSpike(model, placement)
	local hiddenPosition = placement.GroundPosition - Vector3.new(0, (placement.Size.Y * 0.5) - CONFIG.PreviewHeight, 0)
	local extendedPosition = placement.GroundPosition + Vector3.new(0, placement.Size.Y * 0.5, 0)
	local hiddenCFrame = CFrame.fromMatrix(hiddenPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
	local extendedCFrame = CFrame.fromMatrix(extendedPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)

	if placement and placement.SpikeMode == "DormantCrew" then
		local visual = Instance.new("Model")
		visual.Name = "GeneratedSpikeTrapVisual"
		visual.Parent = model

		local baseSize = Vector3.new(math.max(1, placement.Size.X), 0.18, math.max(1, placement.Size.Z))
		local basePosition = placement.GroundPosition + Vector3.new(0, baseSize.Y * 0.5, 0)
		local baseCFrame = CFrame.fromMatrix(basePosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
		local base = createPart(
			visual,
			"Base",
			baseSize,
			baseCFrame,
			Color3.fromRGB(35, 35, 40),
			Enum.Material.Metal,
			0
		)
		base:SetAttribute("SpikeBase", true)

		local spikes = createPart(
			visual,
			"Spikes",
			placement.Size,
			extendedCFrame,
			Color3.fromRGB(45, 45, 50),
			Enum.Material.Metal,
			0.05
		)
		spikes:SetAttribute("SpikeBlade", true)

		local hitbox = createPart(
			visual,
			"Hitbox",
			placement.Size,
			extendedCFrame,
			Color3.fromRGB(45, 45, 50),
			Enum.Material.SmoothPlastic,
			1
		)
		configurePart(hitbox, true, true)
		hitbox:SetAttribute("SpikeHitbox", true)
		hitbox:SetAttribute("HazardClass", CONFIG.HazardClass)
		hitbox:SetAttribute("HazardType", CONFIG.HazardType)
		markHazardHitboxPart(hitbox)

		local motionParts, dormantHiddenCFrame = buildSeparatedSpikeMotion(visual, hitbox, extendedCFrame, "generated_spike")
		return visual, hitbox, dormantHiddenCFrame or hiddenCFrame, extendedCFrame, motionParts
	end

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
		placement.WarningColor or getAttackGlowColor(),
		Enum.Material.Neon,
		if placement.WarningTransparency ~= nil then placement.WarningTransparency else getAttackGlowTransparency()
	)

	local areaName = getAreaNameForBiome(placement.BiomeIndex)
	local visual, hitbox, hiddenCFrame, extendedCFrame, motionParts = createTemplateSpike(model, placement, areaName)
	if not visual then
		visual, hitbox, hiddenCFrame, extendedCFrame, motionParts = createGeneratedSpike(model, placement)
	end

	if hitbox then
		warning.Size = Vector3.new(math.max(1, hitbox.Size.X), 0.12, math.max(1, hitbox.Size.Z))
		warning.CFrame = warningCFrame
		setSpikePlacementAttributes(hitbox, placement)
	end

	model.Parent = hazardsFolder
	return makeController(model, hitbox, warning, visual, hiddenCFrame, extendedCFrame, placement, motionParts)
end

local function applyMotionParts(controller, rootCFrame)
	for _, entry in ipairs(controller.MotionParts or {}) do
		local part = entry.Part
		if part and part.Parent then
			part.CFrame = rootCFrame * entry.RelativeCFrame
		end
	end

	controller.MotionCFrame = rootCFrame
end

local function tweenVisual(controller, targetCFrame, duration, easingDirection)
	if controller.Destroyed or not controller.Model.Parent then
		return
	end

	local tweenInfo = TweenInfo.new(math.max(0, duration), Enum.EasingStyle.Quad, easingDirection)
	if controller.MotionParts and #controller.MotionParts > 0 then
		local cframeValue = Instance.new("CFrameValue")
		cframeValue.Value = controller.MotionCFrame or controller.HiddenCFrame
		local connection = cframeValue:GetPropertyChangedSignal("Value"):Connect(function()
			if not controller.Destroyed and controller.Model.Parent then
				applyMotionParts(controller, cframeValue.Value)
			end
		end)
		local tween = TweenService:Create(cframeValue, tweenInfo, { Value = targetCFrame })
		tween:Play()
		tween.Completed:Wait()
		connection:Disconnect()
		applyMotionParts(controller, targetCFrame)
		cframeValue:Destroy()
		return
	end

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

local function buildSpikePlayerSnapshot()
	local snapshot = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and humanoid.Health > 0 and rootPart then
			snapshot[#snapshot + 1] = {
				Player = player,
				Character = character,
				Humanoid = humanoid,
				RootPart = rootPart,
				Position = rootPart.Position,
			}
		end
	end
	return snapshot
end

local function damagePlayer(controller, player, snapshotEntry)
	if controller.DamagedPlayers[player] then
		return false
	end

	local character = snapshotEntry and snapshotEntry.Character or player.Character
	local humanoid = snapshotEntry and snapshotEntry.Humanoid or character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = snapshotEntry and snapshotEntry.RootPart or character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not rootPart then
		return false
	end

	local rootPosition = snapshotEntry and snapshotEntry.Position or rootPart.Position
	if not isPointInsidePart(controller.Hitbox, rootPosition) then
		return false
	end

	if not raycastGround(rootPosition, controller.Model.Parent) then
		return false
	end

	local isHazardProtected = HazardProtection.IsProtected(player, {
		Position = rootPosition,
		HazardClass = CONFIG.HazardClass,
		HazardType = CONFIG.HazardType,
		Source = "DeckSpikes",
	})
	if isHazardProtected then
		return false
	end

	DamageProtection.TraceMoguStartupDamage(player, {
		TargetContext = {
			Player = player,
			Character = character,
			Humanoid = humanoid,
			RootPart = rootPart,
		},
		Position = rootPosition,
		Source = "DeckSpikes",
		Path = "SpikeRuntimeService.damagePlayer",
	})

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

local function damagePlayersInside(controller, playerSnapshot)
	for _, entry in ipairs(playerSnapshot or buildSpikePlayerSnapshot()) do
		damagePlayer(controller, entry.Player, entry)
	end
end

local function ensureSpikeHoldTask()
	if spikeHoldTaskHandle and spikeHoldTaskHandle:IsConnected() then
		return
	end

	if not PerformanceFlags.IsEnabled("RuntimeSchedulerEnabled") or not PerformanceFlags.IsEnabled("HazardSchedulerEnabled") then
		return
	end

	spikeHoldTaskHandle = RuntimeScheduler.GetDefault():Schedule({
		Id = "SpikeRuntimeService.ActiveHolds",
		Phase = "Heartbeat",
		Priority = 13,
		Callback = function(dt)
			local hasActive = false
			spikeHoldScanElapsed += dt
			for controller in pairs(scheduledSpikeHolds) do
				if controller.Destroyed or not controller.Model.Parent then
					scheduledSpikeHolds[controller] = nil
				else
					hasActive = true
					controller.HoldElapsed = (tonumber(controller.HoldElapsed) or 0) + dt
					if controller.HoldElapsed >= (controller.HoldTime or CONFIG.FallbackHoldTime) then
						scheduledSpikeHolds[controller] = nil
						controller.Active = false
						tweenVisual(controller, controller.HiddenCFrame, CONFIG.RetractTime, Enum.EasingDirection.In)
						controller:Destroy()
					end
				end
			end

			local scanInterval = math.max(0.08, tonumber(CONFIG.HoldScanInterval) or 0.2)
			if spikeHoldScanElapsed >= scanInterval then
				spikeHoldScanElapsed = 0
				local playerSnapshot = buildSpikePlayerSnapshot()
				if #playerSnapshot > 0 then
					for controller in pairs(scheduledSpikeHolds) do
						if not controller.Destroyed and controller.Model.Parent then
							damagePlayersInside(controller, playerSnapshot)
						end
					end
				end
			end

			if not hasActive then
				spikeHoldScanElapsed = 0
				return false
			end
			return true
		end,
		OnStop = function()
			spikeHoldTaskHandle = nil
		end,
	})
end

local function scheduleSpikeHold(controller)
	controller.HoldElapsed = 0
	scheduledSpikeHolds[controller] = true
	if not PerformanceFlags.IsEnabled("RuntimeSchedulerEnabled") or not PerformanceFlags.IsEnabled("HazardSchedulerEnabled") then
		task.spawn(function()
			while controller.HoldElapsed < (controller.HoldTime or CONFIG.FallbackHoldTime) do
				if controller.Destroyed or not controller.Model.Parent then
					scheduledSpikeHolds[controller] = nil
					return
				end
				local dt = task.wait(math.max(0.08, tonumber(CONFIG.HoldScanInterval) or 0.2))
				controller.HoldElapsed += dt
				damagePlayersInside(controller, buildSpikePlayerSnapshot())
			end

			scheduledSpikeHolds[controller] = nil
			controller.Active = false
			tweenVisual(controller, controller.HiddenCFrame, CONFIG.RetractTime, Enum.EasingDirection.In)
			controller:Destroy()
		end)
		return
	end

	ensureSpikeHoldTask()
end

local function getControllerSoundPosition(controller)
	if not controller then
		return nil
	end
	if controller.Hitbox and controller.Hitbox.Parent then
		return controller.Hitbox.Position
	end
	if controller.Visual and controller.Visual.Parent then
		if controller.Visual:IsA("Model") then
			return controller.Visual:GetPivot().Position
		elseif controller.Visual:IsA("BasePart") then
			return controller.Visual.Position
		end
	end
	return nil
end

local function runDeckSpike(controller, options)
	controller.Activated = true
	options = if typeof(options) == "table" then options else nil
	local warningTime = controller.WarningTime or CONFIG.FallbackWarningTime
	if options and options.WarningTime ~= nil then
		warningTime = tonumber(options.WarningTime) or 0
	end
	warningTime = math.max(0, tonumber(warningTime) or 0)
	if warningTime > 0 then
		task.wait(warningTime)
	end
	if controller.Destroyed then
		return
	end

	if controller.Warning.Parent then
		controller.Warning.Transparency = 1
	end

	controller.Active = true
	GameSounds.PlayAtPosition(GameSounds.Ids.Hazards.Trap, getControllerSoundPosition(controller), {
		Name = "SpikeTrapTrigger",
		Volume = 0.9,
		RollOffMaxDistance = 120,
		Lifetime = 5,
	})
	tweenVisual(controller, controller.ExtendedCFrame, CONFIG.ThrustTime, Enum.EasingDirection.Out)
	damagePlayersInside(controller)

	scheduleSpikeHold(controller)
end

local function getActiveSpikeCountsBySurface()
	local counts = {}
	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
			continue
		end

		local placementPart = controller.PlacementPart
		if controller.Mode == "Normal" and placementPart and placementPart.Parent then
			counts[placementPart] = (counts[placementPart] or 0) + 1
		end
	end
	return counts
end

local function getSurfacePart(surfaceEntry)
	local part = surfaceEntry and surfaceEntry.Part
	return if part and part.Parent then part else nil
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

local function getConfiguredChance(chanceMap, key)
	if type(chanceMap) ~= "table" or key == nil then
		return nil
	end

	local direct = chanceMap[key]
	if direct == nil then
		direct = chanceMap[tostring(key)]
	end

	return tonumber(direct)
end

local function resolveDormantCrewSpikeChance(context)
	local dormantConfig = getDormantCrewSpikeConfig()
	local biomeChance = getConfiguredChance(dormantConfig.ChanceByBiome, tonumber(context.BiomeIndex))
	if biomeChance ~= nil then
		return math.clamp(biomeChance, 0, 1)
	end

	local rarity = context.PlacementRarity
	if rarity ~= nil and tostring(rarity) ~= "" then
		local rarityChance = getConfiguredChance(dormantConfig.ChanceByPlacementRarity, tostring(rarity))
		if rarityChance ~= nil then
			return math.clamp(rarityChance, 0, 1)
		end
	end

	return math.clamp(tonumber(dormantConfig.Chance) or 0, 0, 1)
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

local function setWarningGlow(controller, color, transparency)
	local warning = controller and controller.Warning
	if not (warning and warning.Parent) then
		return
	end

	if typeof(color) == "Color3" then
		warning.Color = color
	end
	if transparency ~= nil then
		warning.Transparency = math.clamp(tonumber(transparency) or warning.Transparency, 0, 1)
	end
end

local function activateDormantSpike(controller)
	if not controller or controller.Destroyed or controller.Activated then
		return false
	end

	controller.Activated = true
	if controller.TouchConnection then
		controller.TouchConnection:Disconnect()
		controller.TouchConnection = nil
	end
	if controller.Trigger and controller.Trigger.Parent then
		controller.Trigger:Destroy()
		controller.Trigger = nil
	end

	setWarningGlow(controller, getAttackGlowColor(), getAttackGlowTransparency())
	local dormantConfig = getDormantCrewSpikeConfig()
	local lifecycleOptions = nil
	if dormantConfig.RaiseImmediatelyOnTrigger == true then
		lifecycleOptions = {
			WarningTime = tonumber(dormantConfig.ActivationWarningTime) or 0,
		}
	end
	task.spawn(function()
		runDeckSpike(controller, lifecycleOptions)
	end)
	return true
end

local function createDormantTrigger(model, placement, warning)
	local dormantConfig = getDormantCrewSpikeConfig()
	local triggerHeight = math.max(0.5, tonumber(dormantConfig.TriggerHeight) or 4)
	local triggerPosition = placement.GroundPosition + Vector3.new(0, triggerHeight * 0.5, 0)
	local triggerCFrame = CFrame.fromMatrix(triggerPosition, placement.Lateral, Vector3.yAxis, -placement.Forward)
	local footprintX = placement.Size.X
	local footprintZ = placement.Size.Z
	if warning and warning.Parent then
		footprintX = warning.Size.X
		footprintZ = warning.Size.Z
	end
	local trigger = createPart(
		model,
		"DormantTrigger",
		Vector3.new(math.max(1, footprintX), triggerHeight, math.max(1, footprintZ)),
		triggerCFrame,
		getDormantGlowColor(),
		Enum.Material.SmoothPlastic,
		1
	)
	configurePart(trigger, true, false)
	setSpikePlacementAttributes(trigger, placement)
	return trigger
end

local function bindDormantActivation(controller, placement)
	local trigger = createDormantTrigger(controller.Model, placement, controller.Warning)
	controller.Trigger = trigger
	local lastActivationAttempt = 0
	local dormantConfig = getDormantCrewSpikeConfig()
	local debounce = math.max(0, tonumber(dormantConfig.ActivationDebounce) or 0)

	controller.TouchConnection = trigger.Touched:Connect(function(part)
		if controller.Destroyed or controller.Activated then
			return
		end

		local now = os.clock()
		if now - lastActivationAttempt < debounce then
			return
		end

		local player = getPlayerFromTouchedPart(part)
		if not player then
			return
		end

		lastActivationAttempt = now
		activateDormantSpike(controller)
	end)
	controller.Connections[#controller.Connections + 1] = controller.TouchConnection
end

local function bindDormantCrewCleanup(controller, crewModel, originalParent)
	local dormantConfig = getDormantCrewSpikeConfig()
	if dormantConfig.DespawnWhenCrewmateRemoved ~= true then
		return
	end

	local function maybeDestroyDormant()
		if controller.Destroyed then
			return
		end
		if controller.Activated and dormantConfig.KeepActivatedAfterCrewmateRemoved == true then
			return
		end
		if not crewModel.Parent or crewModel.Parent ~= originalParent then
			controller:Destroy()
		end
	end

	local ancestryConnection = crewModel.AncestryChanged:Connect(function()
		maybeDestroyDormant()
	end)
	controller.Connections[#controller.Connections + 1] = ancestryConnection

	local destroyingConnection = crewModel.Destroying:Connect(function()
		if controller.Destroyed then
			return
		end
		if controller.Activated and dormantConfig.KeepActivatedAfterCrewmateRemoved == true then
			return
		end
		controller:Destroy()
	end)
	controller.Connections[#controller.Connections + 1] = destroyingConnection
end

local function buildDormantCrewPlacement(refs, hazardsFolder, context)
	local crewModel = context.CrewModel
	local spawnPart = context.SpawnPart
	if not (crewModel and crewModel.Parent and crewModel:IsA("Model")) then
		return nil, "invalid_crew_model"
	end
	if not (spawnPart and spawnPart.Parent and spawnPart:IsA("BasePart")) then
		return nil, "invalid_spawn_part"
	end

	local normalizedBiome = math.clamp(math.floor(tonumber(context.BiomeIndex) or 1), 1, CONFIG.BiomeCount)
	local biomeRoot = BiomePlacementResolver.GetBiomeRoot(refs, normalizedBiome)
	if not biomeRoot then
		return nil, "missing_biome_root"
	end

	local areaName = getAreaNameForBiome(normalizedBiome)
	local tuning = getSpikeTuningForBiome(normalizedBiome)
	local relativeScale = rollSpikeScale(tuning)
	local size, metadata = getSpikeFootprintSize(areaName, relativeScale)
	local forward = getPlanarUnit(spawnPart.CFrame.LookVector, Vector3.zAxis)
	local lateral = getPlanarUnit(spawnPart.CFrame.RightVector, Vector3.xAxis)
	local groundPosition = hasSafeGroundForFootprint(
		crewModel:GetPivot().Position,
		hazardsFolder,
		forward,
		lateral,
		size,
		CONFIG.FootprintSupportPadding,
		biomeRoot,
		{ crewModel }
	)
	if not groundPosition then
		return nil, "unsafe_footprint"
	end

	local placement = {
		GroundPosition = groundPosition,
		Forward = forward,
		Lateral = lateral,
		Size = size,
		BiomeIndex = normalizedBiome,
		AreaName = areaName,
		TemplateName = metadata and metadata.TemplateName or "generated_spike",
		PlacementSource = "DormantCrew",
		PlacementPart = spawnPart,
		PlacementPartPath = formatInstancePath(spawnPart),
		PlacementSurfaceReason = "crewmate_spawn",
		BiomeRootPath = formatInstancePath(biomeRoot),
		PlacementSurfaceCount = 0,
		SpikeBand = tuning and tuning.Id or 0,
		RolledScale = relativeScale,
		TargetModelScale = getTargetSpikeModelScale(relativeScale),
		SpikeDamage = rollSpikeDamage(tuning),
		SpikeWarningDuration = tonumber(tuning and tuning.WarningTime) or CONFIG.FallbackWarningTime,
		SpikeActiveDuration = tonumber(tuning and tuning.HoldTime) or CONFIG.FallbackHoldTime,
		SpikesPerSurface = 1,
		SpikeMode = "DormantCrew",
		CrewModel = crewModel,
		WarningColor = getDormantGlowColor(),
		WarningTransparency = if shouldShowDormantWarningFlash() then getDormantGlowTransparency() else 1,
	}

	if isTooCloseToActiveSpike(placement, nil, tuning) then
		return nil, "overlaps_existing_spike"
	end

	return placement, nil
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
				local surfacePart = getSurfacePart(surfaceEntry)
				if not surfacePart then
					continue
				end
				local targetCount = rollSpikesPerSurface(tuning)
				local currentCount = activeCountsBySurface[surfacePart] or 0
				local reservedCount = reservedCountsBySurface[surfacePart] or 0
				local missing = math.max(0, targetCount - currentCount - reservedCount)
				for _ = 1, missing do
					jobs[#jobs + 1] = {
						BiomeIndex = biomeIndex,
						Tuning = tuning,
						SurfaceEntry = surfaceEntry,
						SpikesPerSurface = targetCount,
					}
					reservedCountsBySurface[surfacePart] = (reservedCountsBySurface[surfacePart] or 0) + 1
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

function SpikeRuntimeService.StartNormalPlatformLoop()
	if normalLoopStarted then
		return false, "already_started"
	end
	if CONFIG.Enabled ~= true then
		return false, "disabled"
	end

	normalLoopStarted = true
	task.spawn(function()
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
	end)

	return true, "started"
end

function SpikeRuntimeService.TrySpawnDormantForCrew(context)
	if CONFIG.Enabled ~= true then
		return finishDormantCrewSpike(context, false, "disabled")
	end
	if typeof(context) ~= "table" then
		return finishDormantCrewSpike(context, false, "invalid_context")
	end

	local dormantConfig = getDormantCrewSpikeConfig()
	if dormantConfig.Enabled ~= true then
		return finishDormantCrewSpike(context, false, "dormant_disabled")
	end

	local crewModel = context.CrewModel
	if not (crewModel and crewModel.Parent and crewModel:IsA("Model")) then
		return finishDormantCrewSpike(context, false, "invalid_crew_model")
	end

	if dormantConfig.OnePerCrewmate ~= false then
		local existing = dormantByCrewModel[crewModel]
		if existing and not existing.Destroyed and existing.Model and existing.Model.Parent then
			return finishDormantCrewSpike(context, false, "already_has_dormant_spike")
		end
	end

	local maxActiveDormant = math.max(0, math.floor(tonumber(dormantConfig.MaxActive) or 0))
	if maxActiveDormant <= 0 then
		return finishDormantCrewSpike(context, false, "dormant_cap_zero")
	end
	if countDormantCrewControllers() >= maxActiveDormant then
		return finishDormantCrewSpike(context, false, "dormant_cap_reached")
	end

	local chance = resolveDormantCrewSpikeChance(context)
	if chance <= 0 or rng:NextNumber(0, 1) > chance then
		return finishDormantCrewSpike(context, false, "chance_missed")
	end

	local refs, hazardsFolder = resolveRefs()
	if not (refs and refs.Biomes and hazardsFolder) then
		return finishDormantCrewSpike(context, false, "missing_refs")
	end

	local placement, reason = buildDormantCrewPlacement(refs, hazardsFolder, context)
	if not placement then
		return finishDormantCrewSpike(context, false, reason or "placement_failed")
	end

	local originalParent = crewModel.Parent
	local controller = createDeckSpike(hazardsFolder, placement)
	if not controller then
		return finishDormantCrewSpike(context, false, "create_failed")
	end

	bindDormantActivation(controller, placement)
	bindDormantCrewCleanup(controller, crewModel, originalParent)

	local dormantLifetime = tonumber(dormantConfig.DormantLifetime)
	if dormantLifetime and dormantLifetime > 0 then
		task.delay(dormantLifetime, function()
			if not controller.Destroyed and not controller.Activated then
				controller:Destroy()
			end
		end)
	end

	return finishDormantCrewSpike(context, true, "spawned")
end

function SpikeRuntimeService.DestroyDormantForCrew(crewModel, reason)
	local controller = crewModel and dormantByCrewModel[crewModel] or nil
	if not controller or controller.Destroyed then
		return false, "not_found"
	end

	if controller.Activated and getDormantCrewSpikeConfig().KeepActivatedAfterCrewmateRemoved == true then
		return false, "already_activated"
	end

	controller:Destroy()
	return true, reason or "destroyed"
end

return SpikeRuntimeService
