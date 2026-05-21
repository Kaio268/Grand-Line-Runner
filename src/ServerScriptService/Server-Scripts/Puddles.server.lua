local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local BiomePlacementResolver = require(Modules:WaitForChild("BiomePlacementResolver"))
local StudioAssetResolver = require(Modules:WaitForChild("StudioAssetResolver"))
local HazardDebugConstants = require(Modules:WaitForChild("Debug"):WaitForChild("HazardDebugConstants"))
local BiomeAreas = require(Configs:WaitForChild("BiomeAreas"))
local SpawnPartsConfig = require(Configs:WaitForChild("SpawnParts"))
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
	BiomeCount = 8,
	MaxActivePuddles = 50,
	GroundProbeHeight = 120,
	GroundProbeDepth = 260,
	MaxGroundHeightDelta = 4,
	GroundNormalMin = 0.65,
	SpawnAttempts = 24,
	MinPuddleEdgeGap = 4,
	FootprintPadding = 0.5,
	FootprintSupportPadding = 6,
	GeneratedHitboxHeight = 4,
	FootprintMismatchWarnRatio = 1.5,
	VisualFootprintSanityWarnRatio = 1.25,
	PlacementFailureWarningThreshold = 3,
	HazardClass = "minor",
	HazardType = "puddle",
	FreezeBehavior = "pause",
	FreezeDurationFallback = 1.5,
	AffectablePadding = Vector3.new(0.5, 1, 0.5),
	BiomePlacementCandidateAttempts = 12,
	BiomePlacementEdgePadding = 1,
	GlobalScaleMultiplier = 1,
	YawDegrees = 90,

	-- Puddle balance knobs:
	-- Higher ScaleRange values make larger puddles.
	-- Lower SlowMultiplier values make puddles slow players harder.
	-- Higher PuddlesPerSurface values add more puddles per accepted platform.
	-- Larger MinSpacing values reduce close/overlapping puddle placements.
	ProgressionBands = {
		{
			Band = 1,
			BiomeStart = 1,
			BiomeEnd = 2,
			PuddlesPerSurface = 1,
			ScaleRange = { Min = 1.00, Max = 1.25 },
			SlowMultiplier = 0.75,
			MinSpacing = 4,
			MaxPlacementAttempts = 24,
			CandidateAttempts = 12,
		},
		{
			Band = 2,
			BiomeStart = 3,
			BiomeEnd = 4,
			PuddlesPerSurface = 2,
			ScaleRange = { Min = 1.35, Max = 1.70 },
			SlowMultiplier = 0.65,
			MinSpacing = 5,
			MaxPlacementAttempts = 32,
			CandidateAttempts = 16,
		},
		{
			Band = 3,
			BiomeStart = 5,
			BiomeEnd = 6,
			PuddlesPerSurface = 3,
			ScaleRange = { Min = 1.85, Max = 2.35 },
			SlowMultiplier = 0.55,
			MinSpacing = 6,
			MaxPlacementAttempts = 40,
			CandidateAttempts = 20,
		},
		{
			Band = 4,
			BiomeStart = 7,
			BiomeEnd = 8,
			PuddlesPerSurface = 4,
			ScaleRange = { Min = 2.50, Max = 3.25 },
			SlowMultiplier = 0.45,
			MinSpacing = 7,
			MaxPlacementAttempts = 48,
			CandidateAttempts = 24,
		},
	},
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

local PUDDLE_EXPLICIT_SURFACE_ATTRIBUTES = {
	"AllowPuddle",
	"AllowPuddles",
	"BiomeFloor",
	"PuddleFloor",
	"PuddlePlacement",
	"PuddleSpawnFloor",
}

local PUDDLE_EXPLICIT_SURFACE_TAGS = {
	"AllowPuddle",
	"AllowPuddles",
	"BiomeFloor",
	"PuddleFloor",
	"PuddlePlacement",
	"PuddleSpawnFloor",
}

local PUDDLE_DENY_ATTRIBUTES = {
	"BombSafe",
	"DebugHitbox",
	"HazardHitbox",
	"IsSafeZone",
	"NoHazard",
	"NoHazards",
	"NoPuddle",
	"NoPuddles",
	"PuddleBlocked",
	"SafeZone",
}

local PUDDLE_DENY_TAGS = {
	"DebugHitbox",
	"HazardHitbox",
	"NoHazard",
	"NoPuddle",
	"NoPuddles",
	"PuddleBlocked",
	"SafeZone",
}

local rng = Random.new()
local activeControllers = {}
local templateCacheByArea = {}
local templateMetadataByTemplate = setmetatable({}, { __mode = "k" })
local placementFailureCountsByArea = {}
local warnedMessages = {}
local rarityPadSurfaceNames = nil
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

local function copyPlacementDiagnostics(summary, reason)
	local diagnostics = {}
	if type(summary) == "table" then
		for key, value in pairs(summary) do
			diagnostics[key] = value
		end
	end

	diagnostics.Reason = tostring(reason or diagnostics.Reason or "unknown")
	return diagnostics
end

local function formatPlacementDiagnostics(diagnostics)
	if type(diagnostics) ~= "table" then
		return "reason=unknown root=<nil> candidate=<nil> acceptedAs=<nil> surfaces=0 explicit=0 fallback=0 general=0 usedExplicit=false rejections={none} samples={none}"
	end

	local surfaceDiagnostics = diagnostics.Diagnostics
	local rejectionSummary = BiomePlacementResolver.FormatRejectionSummary(surfaceDiagnostics)
	local rejectionSamples = BiomePlacementResolver.FormatRejectionSamples(surfaceDiagnostics)

	return string.format(
		"reason=%s root=%s candidate=%s acceptedAs=%s surfaces=%d explicit=%d fallback=%d general=%d usedExplicit=%s rejections={%s} samples={%s}",
		tostring(diagnostics.Reason or "unknown"),
		tostring(diagnostics.RootPath or "<nil>"),
		tostring(diagnostics.CandidatePartPath or "<nil>"),
		tostring(diagnostics.SurfaceAcceptanceReason or "<nil>"),
		tonumber(diagnostics.SurfaceCount) or 0,
		tonumber(diagnostics.ExplicitSurfaceCount) or 0,
		tonumber(diagnostics.FallbackSurfaceCount) or 0,
		tonumber(diagnostics.GeneralSurfaceCount) or 0,
		tostring(diagnostics.UsedExplicit == true),
		rejectionSummary,
		rejectionSamples
	)
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
		{ "MapRoot", "WaveFolder" },
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
		formatInstancePath(refs.Biomes),
		formatInstancePath(refs.WaveStart),
		formatInstancePath(refs.WaveEnd),
		formatInstancePath(leftBound),
		formatInstancePath(rightBound),
	}, "|")

	if lastTraceStateKey ~= stateKey then
		lastTraceStateKey = stateKey
		trace(
			"resolved waveFolder=%s hazards=%s biomes=%s start=%s end=%s left=%s right=%s",
			formatInstancePath(waveFolder),
			formatInstancePath(hazardsFolder),
			formatInstancePath(refs.Biomes),
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
		corridorWidth = math.max(6, math.abs((rightBound.Position - leftBound.Position):Dot(lateral)))
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

local function isWithinPlacementRoot(instance, placementRoot)
	if not placementRoot then
		return true
	end

	return instance == placementRoot or instance:IsDescendantOf(placementRoot)
end

local function raycastGround(position, refs, raycastParams, placementRoot)
	local height = math.max(10, tonumber(CONFIG.GroundProbeHeight) or 120)
	local depth = math.max(height + 10, tonumber(CONFIG.GroundProbeDepth) or 260)
	local result = Workspace:Raycast(
		position + Vector3.new(0, height, 0),
		Vector3.new(0, -depth, 0),
		raycastParams or buildGroundRaycastParams(refs)
	)

	if not result then
		return nil, "no_support"
	end

	if not (result.Instance and result.Instance:IsA("BasePart")) then
		return nil, "support_not_basepart"
	end

	if not isWithinPlacementRoot(result.Instance, placementRoot) then
		return nil, "outside_biome_root"
	end

	if result.Instance.CanCollide ~= true then
		return nil, "support_not_collidable"
	end

	if result.Normal.Y < math.clamp(tonumber(CONFIG.GroundNormalMin) or 0.65, 0, 1) then
		return nil, "support_bad_normal"
	end

	if isUnsafePuddleSurface(result.Instance) then
		return nil, "unsafe_surface"
	end

	return result.Position, nil, result.Instance
end

local function buildFootprintSupportSamples(forward, lateral, footprintSize)
	local forwardUnit = getPlanarUnit(forward, Vector3.zAxis)
	local lateralUnit = getPlanarUnit(lateral, Vector3.xAxis)
	local size = typeof(footprintSize) == "Vector3" and footprintSize or Vector3.new(8, 1, 8)
	local padding = math.clamp(tonumber(CONFIG.FootprintSupportPadding) or 6, 0, 8)
	local halfX = math.max(1, (size.X * 0.5) + padding)
	local halfZ = math.max(1, (size.Z * 0.5) + padding)

	return {
		{ Label = "center", Offset = Vector3.zero },
		{ Label = "front_left", Offset = (lateralUnit * -halfX) + (forwardUnit * halfZ) },
		{ Label = "front_right", Offset = (lateralUnit * halfX) + (forwardUnit * halfZ) },
		{ Label = "back_left", Offset = (lateralUnit * -halfX) + (forwardUnit * -halfZ) },
		{ Label = "back_right", Offset = (lateralUnit * halfX) + (forwardUnit * -halfZ) },
		{ Label = "front_mid", Offset = forwardUnit * halfZ },
		{ Label = "back_mid", Offset = forwardUnit * -halfZ },
		{ Label = "left_mid", Offset = lateralUnit * -halfX },
		{ Label = "right_mid", Offset = lateralUnit * halfX },
	}
end

local function resolveSafeGroundPosition(position, refs, lateral, forward, footprintSize, placementRoot)
	local raycastParams = buildGroundRaycastParams(refs)
	local centerPosition, centerReason = raycastGround(position, refs, raycastParams, placementRoot)
	if not centerPosition then
		return nil, centerReason or "center_unsupported"
	end

	local maxHeightDelta = math.max(0.5, tonumber(CONFIG.MaxGroundHeightDelta) or 4)

	for _, sample in ipairs(buildFootprintSupportSamples(forward, lateral, footprintSize)) do
		local samplePosition, sampleReason = raycastGround(centerPosition + sample.Offset, refs, raycastParams, placementRoot)
		if not samplePosition or math.abs(samplePosition.Y - centerPosition.Y) > maxHeightDelta then
			return nil, string.format("footprint_%s_%s", sample.Label, sampleReason or "height_delta")
		end
	end

	return centerPosition, nil
end

local function getAreaEntryForBiome(biomeIndex)
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)
	local entry = BiomeAreas.GetBiome and BiomeAreas.GetBiome(normalizedBiome)
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

local function getNormalizedBiomeIndex(biomeIndex)
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	return math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)
end

local function getPuddleTuningForBiome(biomeIndex)
	local normalizedBiome = getNormalizedBiomeIndex(biomeIndex)
	for _, tuning in ipairs(CONFIG.ProgressionBands or {}) do
		local biomeStart = math.floor(tonumber(tuning.BiomeStart) or normalizedBiome)
		local biomeEnd = math.floor(tonumber(tuning.BiomeEnd) or biomeStart)
		if normalizedBiome >= biomeStart and normalizedBiome <= biomeEnd then
			return tuning
		end
	end

	return {
		Band = 1,
		BiomeStart = normalizedBiome,
		BiomeEnd = normalizedBiome,
		PuddlesPerSurface = 1,
		ScaleRange = { Min = 1, Max = 1 },
		SlowMultiplier = CONFIG.FallbackSlowMultiplier,
		MinSpacing = CONFIG.MinPuddleEdgeGap,
		MaxPlacementAttempts = CONFIG.SpawnAttempts,
		CandidateAttempts = CONFIG.BiomePlacementCandidateAttempts,
	}
end

local function getScaleRange(tuning)
	local range = type(tuning) == "table" and tuning.ScaleRange or nil
	local minScale = math.max(0.01, tonumber(range and range.Min) or 1)
	local maxScale = math.max(minScale, tonumber(range and range.Max) or minScale)
	return minScale, maxScale
end

local function rollPuddleScale(tuning)
	local minScale, maxScale = getScaleRange(tuning)
	local relativeScale = if maxScale > minScale then rng:NextNumber(minScale, maxScale) else minScale
	local globalMultiplier = math.max(0.01, tonumber(CONFIG.GlobalScaleMultiplier) or 1)
	return relativeScale * globalMultiplier
end

local function getPuddlesPerSurfaceForBiome(biomeIndex)
	local tuning = getPuddleTuningForBiome(biomeIndex)
	return math.max(0, math.floor(tonumber(tuning.PuddlesPerSurface) or 1))
end

local function getMinSpacingForTuning(tuning)
	if type(tuning) ~= "table" then
		return math.max(0, tonumber(CONFIG.MinPuddleEdgeGap) or 0)
	end

	return math.max(0, tonumber(tuning.MinSpacing) or tonumber(CONFIG.MinPuddleEdgeGap) or 0)
end

local function getPlacementAttemptsForTuning(tuning)
	if type(tuning) ~= "table" then
		return math.max(1, math.floor(tonumber(CONFIG.SpawnAttempts) or 24))
	end

	return math.max(1, math.floor(tonumber(tuning.MaxPlacementAttempts) or tonumber(CONFIG.SpawnAttempts) or 24))
end

local function getCandidateAttemptsForTuning(tuning)
	if type(tuning) ~= "table" then
		return math.max(1, math.floor(tonumber(CONFIG.BiomePlacementCandidateAttempts) or 12))
	end

	return math.max(
		1,
		math.floor(tonumber(tuning.CandidateAttempts) or tonumber(CONFIG.BiomePlacementCandidateAttempts) or 12)
	)
end

local function getSlowMultiplierForTuning(tuning)
	if type(tuning) ~= "table" then
		return math.clamp(tonumber(CONFIG.FallbackSlowMultiplier) or 0.5, 0, 1)
	end

	return math.clamp(tonumber(tuning.SlowMultiplier) or tonumber(CONFIG.FallbackSlowMultiplier) or 0.5, 0, 1)
end

local function getRarityPadSurfaceNames()
	if rarityPadSurfaceNames then
		return rarityPadSurfaceNames
	end

	local names = {}
	for rarityName in pairs(SpawnPartsConfig.RarityTier or {}) do
		names[#names + 1] = tostring(rarityName)
	end
	table.sort(names)

	rarityPadSurfaceNames = names
	return rarityPadSurfaceNames
end

local function buildSurfaceQueryOptions()
	return {
		Context = "Puddles",
		FilterKey = "PuddlesStrictSurfaces",
		AllowAttributes = PUDDLE_EXPLICIT_SURFACE_ATTRIBUTES,
		AllowTags = PUDDLE_EXPLICIT_SURFACE_TAGS,
		DenyAttributes = PUDDLE_DENY_ATTRIBUTES,
		DenyTags = PUDDLE_DENY_TAGS,
		RequireExplicitOrFallbackSurface = true,
		AllowFallbackAfterExplicitFailure = false,
		FallbackSurfaceNames = getRarityPadSurfaceNames(),
		ExplicitSurfaceAcceptanceReason = "explicit_puddle_marker",
		FallbackSurfaceAcceptanceReason = "rarity_pad_fallback",
		UnmarkedSurfaceRejectReason = "unmarked_non_rarity_surface",
		WarnIfMissing = false,
	}
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

local function isAuthoredHitboxPart(part)
	return part and part:IsA("BasePart") and string.lower(part.Name) == "hitbox"
end

local function getVisualBaseParts(template)
	local visualParts = {}
	for _, part in ipairs(getBaseParts(template)) do
		if not isAuthoredHitboxPart(part) then
			visualParts[#visualParts + 1] = part
		end
	end

	if #visualParts > 0 then
		return visualParts
	end

	return getBaseParts(template)
end

local function getBoundsForPartsInFrame(parts, boundsFrame)
	if typeof(parts) ~= "table" or typeof(boundsFrame) ~= "CFrame" then
		return nil, nil
	end

	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local hasBounds = false

	for _, part in ipairs(parts) do
		if part and part:IsA("BasePart") then
			local halfSize = part.Size * 0.5
			for _, xSign in ipairs({ -1, 1 }) do
				for _, ySign in ipairs({ -1, 1 }) do
					for _, zSign in ipairs({ -1, 1 }) do
						local corner = part.CFrame:PointToWorldSpace(Vector3.new(
							halfSize.X * xSign,
							halfSize.Y * ySign,
							halfSize.Z * zSign
						))
						local localCorner = boundsFrame:PointToObjectSpace(corner)
						minX = math.min(minX, localCorner.X)
						minY = math.min(minY, localCorner.Y)
						minZ = math.min(minZ, localCorner.Z)
						maxX = math.max(maxX, localCorner.X)
						maxY = math.max(maxY, localCorner.Y)
						maxZ = math.max(maxZ, localCorner.Z)
						hasBounds = true
					end
				end
			end
		end
	end

	if not hasBounds then
		return nil, nil
	end

	local minVector = Vector3.new(minX, minY, minZ)
	local maxVector = Vector3.new(maxX, maxY, maxZ)
	return (minVector + maxVector) * 0.5, maxVector - minVector
end

local function getAxisMismatchRatio(a, b)
	local first = math.max(0, tonumber(a) or 0)
	local second = math.max(0, tonumber(b) or 0)
	if first <= 1e-3 or second <= 1e-3 then
		return math.huge
	end

	return math.max(first / second, second / first)
end

local function getPuddleTemplateMetadata(template)
	if not template or not template.Parent then
		return nil
	end

	local cachedMetadata = templateMetadataByTemplate[template]
	if cachedMetadata then
		return cachedMetadata
	end

	local pivot = template:GetPivot()
	local visualCenterOffset, visualBoundsSize = getBoundsForPartsInFrame(getVisualBaseParts(template), pivot)
	if not visualCenterOffset or not visualBoundsSize then
		warnOnce(
			"missing_visual_bounds_" .. tostring(template:GetFullName()),
			"Could not compute visual bounds for template=%s.",
			formatInstancePath(template)
		)
		return nil
	end

	local hitbox = findHitbox(template)
	local authoredHitboxSize = nil
	if hitbox then
		_, authoredHitboxSize = getBoundsForPartsInFrame({ hitbox }, pivot)
	end

	local templateScale = 1
	local scaleOk, scaleResult = pcall(function()
		return template:GetScale()
	end)
	if scaleOk and typeof(scaleResult) == "number" and scaleResult > 0 then
		templateScale = scaleResult
	else
		warnOnce(
			"missing_template_scale_" .. tostring(template:GetFullName()),
			"Could not read template scale for template=%s; visual scaling will use scale=1 fallback.",
			formatInstancePath(template)
		)
	end

	if authoredHitboxSize then
		local mismatchRatio = math.max(
			getAxisMismatchRatio(visualBoundsSize.X, authoredHitboxSize.X),
			getAxisMismatchRatio(visualBoundsSize.Z, authoredHitboxSize.Z)
		)
		if mismatchRatio >= math.max(1, tonumber(CONFIG.FootprintMismatchWarnRatio) or 1.5) then
			warnOnce(
				"hitbox_visual_mismatch_" .. tostring(template:GetFullName()),
				"Template=%s authored Hitbox footprint differs from visual bounds; generated PuddleHitbox will use visual bounds. visual=%s authoredHitbox=%s",
				formatInstancePath(template),
				tostring(visualBoundsSize),
				tostring(authoredHitboxSize)
			)
		end
	end

	local hitboxHeight = math.max(0.5, tonumber(CONFIG.GeneratedHitboxHeight) or 4)
	local footprintSize = Vector3.new(
		math.max(1, visualBoundsSize.X),
		hitboxHeight,
		math.max(1, visualBoundsSize.Z)
	)

	local metadata = {
		Template = template,
		VisualBoundsSize = visualBoundsSize,
		AuthoredHitboxSize = authoredHitboxSize,
		TemplateScale = templateScale,
		FootprintSize = footprintSize,
		VisualCenterOffset = visualCenterOffset,
		VisualBottomOffsetY = visualCenterOffset.Y - (visualBoundsSize.Y * 0.5),
	}

	templateMetadataByTemplate[template] = metadata
	return metadata
end

local function getTargetModelScale(metadata, relativeScale)
	local relativeScaleValue = math.max(0.01, tonumber(relativeScale) or 1)
	local templateScale = type(metadata) == "table" and tonumber(metadata.TemplateScale) or nil
	if not templateScale or templateScale <= 0 then
		return relativeScaleValue
	end

	return templateScale * relativeScaleValue
end

local function getRuntimeScaleRatio(metadata, relativeScale)
	local templateScale = type(metadata) == "table" and tonumber(metadata.TemplateScale) or nil
	if not templateScale or templateScale <= 0 then
		return math.max(0.01, tonumber(relativeScale) or 1)
	end

	local targetScale = getTargetModelScale(metadata, relativeScale)
	return targetScale / templateScale
end

local function getScaledFootprintSize(metadata, relativeScale)
	if type(metadata) ~= "table" or typeof(metadata.FootprintSize) ~= "Vector3" then
		return nil
	end

	local scaleRatio = getRuntimeScaleRatio(metadata, relativeScale)
	local baseSize = metadata.FootprintSize
	local padding = math.max(0, tonumber(CONFIG.FootprintPadding) or 0)
	return Vector3.new(
		math.max(1, (baseSize.X * scaleRatio) + (padding * 2)),
		math.max(0.5, tonumber(CONFIG.GeneratedHitboxHeight) or baseSize.Y),
		math.max(1, (baseSize.Z * scaleRatio) + (padding * 2))
	)
end

local function configurePuddleVisualModel(model)
	for _, part in ipairs(getBaseParts(model)) do
		configurePart(part, false, false)
		part:SetAttribute("HazardClass", nil)
		part:SetAttribute("HazardType", nil)
		part:SetAttribute("CanFreeze", nil)
		part:SetAttribute("FreezeBehavior", nil)

		if isAuthoredHitboxPart(part) then
			part.Transparency = 1
		end
	end
end

local function createGeneratedPuddleHitbox(placement, footprintSize)
	local hitbox = Instance.new("Part")
	hitbox.Name = "PuddleHitbox"
	hitbox.Size = Vector3.new(
		math.max(1, footprintSize.X),
		math.max(0.5, footprintSize.Y),
		math.max(1, footprintSize.Z)
	)
	hitbox.CFrame = placement.CFrame + Vector3.new(0, hitbox.Size.Y * 0.5, 0)
	hitbox.Transparency = 1
	configurePart(hitbox, false, false)
	markHazardHitboxPart(hitbox)
	return hitbox
end

local function getVisualPivotForPlacement(placement, metadata, relativeScale)
	local scaleRatio = getRuntimeScaleRatio(metadata, relativeScale)
	local centerOffset = typeof(metadata.VisualCenterOffset) == "Vector3" and metadata.VisualCenterOffset or Vector3.zero
	local bottomOffsetY = tonumber(metadata.VisualBottomOffsetY) or 0

	return placement.CFrame
		* CFrame.new(
			-centerOffset.X * scaleRatio,
			-bottomOffsetY * scaleRatio,
			-centerOffset.Z * scaleRatio
		)
end

local function warnIfVisualFootprintMismatch(template, visualModel, hitbox)
	if not template or not visualModel or not hitbox then
		return
	end

	local _, visualSize = getBoundsForPartsInFrame(getVisualBaseParts(visualModel), hitbox.CFrame)
	if not visualSize then
		return
	end

	local tolerance = math.max(1, tonumber(CONFIG.VisualFootprintSanityWarnRatio) or 1.25)
	if visualSize.X > hitbox.Size.X * tolerance or visualSize.Z > hitbox.Size.Z * tolerance then
		warnOnce(
			"runtime_visual_footprint_mismatch_" .. tostring(template:GetFullName()),
			"Runtime puddle visual exceeds generated PuddleHitbox footprint for template=%s visual=%s hitbox=%s.",
			formatInstancePath(template),
			tostring(visualSize),
			tostring(hitbox.Size)
		)
	end
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

local function createFootprintRecord(position, footprintCFrame, footprintSize, minSpacing, placementPart)
	return {
		Position = position,
		CFrame = footprintCFrame,
		Size = footprintSize,
		Radius = getFootprintRadius(footprintSize),
		MinSpacing = math.max(0, tonumber(minSpacing) or 0),
		PlacementPart = placementPart,
	}
end

local function isTooCloseToFootprint(position, footprintSize, otherFootprint, minSpacing)
	if typeof(position) ~= "Vector3" or type(otherFootprint) ~= "table" then
		return false
	end

	local currentRadius = getFootprintRadius(footprintSize)
	local minEdgeGap = math.max(math.max(0, tonumber(minSpacing) or 0), tonumber(otherFootprint.MinSpacing) or 0)
	local otherPosition = otherFootprint.Position
	local otherRadius = tonumber(otherFootprint.Radius) or getFootprintRadius(otherFootprint.Size)
	local requiredDistance = currentRadius + otherRadius + minEdgeGap

	return getPlanarDistance(position, otherPosition) < requiredDistance
end

local function isTooCloseToActivePuddle(position, footprintSize, reservedFootprints, minSpacing)
	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
			continue
		end

		if controller.Footprint and isTooCloseToFootprint(position, footprintSize, controller.Footprint, minSpacing) then
			return true
		end

		if not controller.Footprint then
			local hitbox = controller.Hitbox
			if hitbox and hitbox.Parent then
				local fallbackFootprint = createFootprintRecord(hitbox.Position, hitbox.CFrame, hitbox.Size, minSpacing)
				if isTooCloseToFootprint(position, footprintSize, fallbackFootprint, minSpacing) then
					return true
				end
			end
		end
	end

	for _, reservedFootprint in ipairs(reservedFootprints or {}) do
		if isTooCloseToFootprint(position, footprintSize, reservedFootprint, minSpacing) then
			return true
		end
	end

	return false
end

local function buildPlacementCFrame(position, forward)
	local forwardUnit = getPlanarUnit(forward, Vector3.new(0, 0, -1))
	local baseCFrame = CFrame.lookAt(position, position + forwardUnit, Vector3.yAxis)
	return baseCFrame * CFrame.Angles(0, math.rad(tonumber(CONFIG.YawDegrees) or 0), 0)
end

local function getPlacementBasis(candidate, startPart, endPart, leftBound, rightBound)
	if startPart and endPart then
		local forward, lateral = getCorridorBasis(startPart, endPart, leftBound, rightBound)
		return forward, lateral
	end

	local forward = getPlanarUnit(candidate and candidate.Forward, Vector3.new(0, 0, -1))
	local lateral = getPlanarUnit(candidate and candidate.Lateral, forward:Cross(Vector3.yAxis))
	return forward, lateral
end

local function choosePuddlePlacementFromBiomeGeometry(
	refs,
	startPart,
	endPart,
	leftBound,
	rightBound,
	biomeIndex,
	footprintSize,
	reservedFootprints,
	tuning,
	surfaceEntry
)
	local normalizedBiome = getNormalizedBiomeIndex(biomeIndex)
	local attempts = getPlacementAttemptsForTuning(tuning)
	local minSpacing = getMinSpacingForTuning(tuning)

	local candidateOptions = {
		Context = "Puddles",
		FilterKey = "Puddles",
		FootprintSize = footprintSize,
		CandidateAttempts = getCandidateAttemptsForTuning(tuning),
		EdgePadding = math.max(0, tonumber(CONFIG.BiomePlacementEdgePadding) or 0),
		WarnIfMissing = false,
	}

	local lastReason = nil
	local lastDiagnostics = nil
	local lastCandidatePart = surfaceEntry and surfaceEntry.Part or nil
	for _ = 1, attempts do
		local candidate, reason, candidateDiagnostics
		if surfaceEntry then
			candidate, reason, candidateDiagnostics = BiomePlacementResolver.GetRandomSurfaceCandidateFromEntry(
				refs,
				normalizedBiome,
				surfaceEntry,
				rng,
				candidateOptions
			)
		else
			candidate, reason, candidateDiagnostics =
				BiomePlacementResolver.GetRandomSurfaceCandidate(refs, normalizedBiome, rng, candidateOptions)
		end

		lastDiagnostics = candidateDiagnostics or lastDiagnostics
		if not candidate then
			lastReason = reason or "no_biome_candidate"
			break
		end

		lastCandidatePart = candidate.Part
		local forward, lateral = getPlacementBasis(candidate, startPart, endPart, leftBound, rightBound)
		local tentativeCFrame = buildPlacementCFrame(candidate.Position, forward)
		local validationForward = getPlanarUnit(tentativeCFrame.LookVector, forward)
		local validationLateral = getPlanarUnit(tentativeCFrame.RightVector, lateral)
		local groundPosition, validationReason = resolveSafeGroundPosition(
			candidate.Position,
			refs,
			validationLateral,
			validationForward,
			footprintSize,
			candidate.Root
		)

		if not groundPosition then
			lastReason = validationReason or "invalid_floor_or_gap"
			continue
		end

		if isTooCloseToActivePuddle(groundPosition, footprintSize, reservedFootprints, minSpacing) then
			lastReason = "overlap_active_or_reserved"
			continue
		end

		local placementDiagnostics = copyPlacementDiagnostics(candidateDiagnostics, "ok")
		placementDiagnostics.CandidatePartPath = formatInstancePath(candidate.Part)
		placementDiagnostics.RootPath = candidate.BiomeRootPath or placementDiagnostics.RootPath
		placementDiagnostics.SurfaceCount = candidate.SurfaceCount or placementDiagnostics.SurfaceCount
		placementDiagnostics.ExplicitSurfaceCount = candidate.ExplicitSurfaceCount
			or placementDiagnostics.ExplicitSurfaceCount
		placementDiagnostics.FallbackSurfaceCount = candidate.FallbackSurfaceCount
			or placementDiagnostics.FallbackSurfaceCount
		placementDiagnostics.GeneralSurfaceCount = candidate.GeneralSurfaceCount
			or placementDiagnostics.GeneralSurfaceCount
		placementDiagnostics.UsedExplicit = candidate.UsedExplicitSurface == true
		placementDiagnostics.SurfaceAcceptanceReason = candidate.SurfaceAcceptanceReason

		return {
			GroundPosition = groundPosition,
			CFrame = buildPlacementCFrame(groundPosition, forward),
			Forward = validationForward,
			Lateral = validationLateral,
			BiomeIndex = normalizedBiome,
			PlacementSource = "BiomeGeometry",
			PlacementPart = candidate.Part,
			PlacementDiagnostics = placementDiagnostics,
			BiomeRootPath = candidate.BiomeRootPath,
			SurfaceCount = candidate.SurfaceCount,
			ExplicitSurfaceCount = candidate.ExplicitSurfaceCount,
			FallbackSurfaceCount = candidate.FallbackSurfaceCount,
			GeneralSurfaceCount = candidate.GeneralSurfaceCount,
			UsedExplicitSurface = candidate.UsedExplicitSurface == true,
			SurfaceAcceptanceReason = candidate.SurfaceAcceptanceReason,
		},
			nil,
			placementDiagnostics
	end

	local failureDiagnostics = copyPlacementDiagnostics(lastDiagnostics, lastReason or "no_biome_candidate")
	if lastCandidatePart then
		failureDiagnostics.CandidatePartPath = formatInstancePath(lastCandidatePart)
	end

	return nil, failureDiagnostics.Reason, failureDiagnostics
end

local function choosePuddlePlacement(
	refs,
	startPart,
	endPart,
	leftBound,
	rightBound,
	biomeIndex,
	footprintSize,
	reservedFootprints,
	tuning,
	surfaceEntry
)
	return choosePuddlePlacementFromBiomeGeometry(
		refs,
		startPart,
		endPart,
		leftBound,
		rightBound,
		biomeIndex,
		footprintSize,
		reservedFootprints,
		tuning or getPuddleTuningForBiome(biomeIndex),
		surfaceEntry
	)
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

local function createController(model, hitbox, visualModel, biomeIndex, footprint, placement)
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
		Footprint = footprint,
		PlacementPart = placement and placement.PlacementPart or nil,
		PuddleBand = tonumber(placement and placement.PuddleBand) or 1,
		RolledScale = tonumber(placement and placement.RolledScale) or 1,
		SlowMultiplier = math.clamp(tonumber(placement and placement.SlowMultiplier) or CONFIG.FallbackSlowMultiplier, 0, 1),
		PuddlesPerSurface = math.max(0, math.floor(tonumber(placement and placement.PuddlesPerSurface) or 1)),
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

	local slowMultiplier = controller.SlowMultiplier or CONFIG.FallbackSlowMultiplier
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

local function setPuddlePlacementAttributes(instance, placement, areaName, template)
	if not instance then
		return
	end

	instance:SetAttribute("BiomeIndex", tonumber(placement and placement.BiomeIndex) or nil)
	instance:SetAttribute("AreaName", tostring(areaName or ""))
	instance:SetAttribute("TemplateName", template and template.Name or "")
	instance:SetAttribute("PlacementSource", tostring((placement and placement.PlacementSource) or "BiomeGeometry"))
	instance:SetAttribute("PlacementPartPath", formatInstancePath(placement and placement.PlacementPart))
	instance:SetAttribute("PlacementSurfaceReason", tostring((placement and placement.SurfaceAcceptanceReason) or ""))
	instance:SetAttribute("BiomeRootPath", tostring((placement and placement.BiomeRootPath) or ""))
	instance:SetAttribute("PlacementSurfaceCount", tonumber(placement and placement.SurfaceCount) or 0)
	instance:SetAttribute("PuddleBand", tonumber(placement and placement.PuddleBand) or 0)
	instance:SetAttribute("RolledScale", tonumber(placement and placement.RolledScale) or 0)
	instance:SetAttribute("SlowMultiplier", tonumber(placement and placement.SlowMultiplier) or 0)
	instance:SetAttribute("PuddlesPerSurface", tonumber(placement and placement.PuddlesPerSurface) or 0)
end

local function createPuddleModel(hazardsFolder, template, metadata, placement, relativeScale, footprintSize, areaName)
	local model = Instance.new("Model")
	model.Name = "Puddle"
	model:SetAttribute("HazardClass", CONFIG.HazardClass)
	model:SetAttribute("HazardType", CONFIG.HazardType)
	model:SetAttribute("CanFreeze", true)
	model:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)
	setPuddlePlacementAttributes(model, placement, areaName, template)

	local hitbox = createGeneratedPuddleHitbox(placement, footprintSize)
	setPuddlePlacementAttributes(hitbox, placement, areaName, template)
	hitbox.Parent = model

	local visualModel = template:Clone()
	visualModel.Name = "PuddleVisual"
	visualModel.Parent = model

	local targetScale = getTargetModelScale(metadata, relativeScale)
	pcall(function()
		visualModel:ScaleTo(targetScale)
	end)

	configurePuddleVisualModel(visualModel)
	visualModel:PivotTo(getVisualPivotForPlacement(placement, metadata, relativeScale))
	warnIfVisualFootprintMismatch(template, visualModel, hitbox)

	model.WorldPivot = placement.CFrame
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

local function getActivePuddleCountsBySurface()
	local countsBySurface = {}
	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
			continue
		end

		local placementPart = controller.PlacementPart
		if placementPart and placementPart.Parent then
			countsBySurface[placementPart] = (countsBySurface[placementPart] or 0) + 1
		end
	end

	return countsBySurface
end

local function getPuddleSurfaceEntries(refs, biomeIndex)
	return BiomePlacementResolver.GetBiomeSurfaceEntries(refs, biomeIndex, buildSurfaceQueryOptions())
end

local function getRandomDelay(minValue, maxValue, fallbackMin)
	local minDelay = math.max(0, tonumber(minValue) or fallbackMin or 0)
	local maxDelay = math.max(minDelay, tonumber(maxValue) or minDelay)

	return rng:NextNumber(minDelay, maxDelay)
end

local function getSpawnStaggerDelay()
	return getRandomDelay(CONFIG.MinSpawnStaggerDelay, CONFIG.MaxSpawnStaggerDelay, 0.03)
end

local function shuffleArray(array)
	for index = #array, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		array[index], array[swapIndex] = array[swapIndex], array[index]
	end
end

local function spawnPuddle(
	refs,
	hazardsFolder,
	startPart,
	endPart,
	leftBound,
	rightBound,
	biomeIndex,
	reservedFootprints,
	tuning,
	surfaceEntry
)
	if cleanupActiveControllers() >= CONFIG.MaxActivePuddles then
		return false
	end

	local areaName = getAreaNameForBiome(biomeIndex)
	local template = findPuddleTemplate(areaName)
	if not template then
		return false
	end

	tuning = tuning or getPuddleTuningForBiome(biomeIndex)
	local relativeScale = rollPuddleScale(tuning)
	local metadata = getPuddleTemplateMetadata(template)
	if not metadata then
		warnOnce(
			"missing_metadata_" .. tostring(areaName),
			"Could not compute puddle footprint metadata for area=%s template=%s.",
			tostring(areaName),
			formatInstancePath(template)
		)
		return false
	end

	local footprintSize = getScaledFootprintSize(metadata, relativeScale)
	if not footprintSize then
		return false
	end

	local placement, placementReason, placementDiagnostics = choosePuddlePlacement(
		refs,
		startPart,
		endPart,
		leftBound,
		rightBound,
		biomeIndex,
		footprintSize,
		reservedFootprints,
		tuning,
		surfaceEntry
	)
	if not placement then
		local failureKey = tostring(areaName)
		local failureCount = (placementFailureCountsByArea[failureKey] or 0) + 1
		placementFailureCountsByArea[failureKey] = failureCount
		warnOnce(
			string.format("placement_failed_%s_%s", failureKey, tostring(placementReason)),
			"Skipping puddle spawn because biome placement failed. biome=%d area=%s template=%s source=BiomeGeometry footprint=%s failures=%d diagnostics={%s}",
			tonumber(biomeIndex) or 0,
			tostring(areaName),
			template.Name,
			tostring(footprintSize),
			failureCount,
			formatPlacementDiagnostics(placementDiagnostics)
		)
		return false
	end

	placementFailureCountsByArea[tostring(areaName)] = 0
	placement.PuddleBand = tonumber(tuning.Band) or 1
	placement.RolledScale = relativeScale
	placement.SlowMultiplier = getSlowMultiplierForTuning(tuning)
	placement.PuddlesPerSurface = getPuddlesPerSurfaceForBiome(biomeIndex)

	local footprint = createFootprintRecord(
		placement.GroundPosition,
		placement.CFrame,
		footprintSize,
		getMinSpacingForTuning(tuning),
		placement.PlacementPart
	)
	if reservedFootprints then
		reservedFootprints[#reservedFootprints + 1] = footprint
	end

	local model, hitbox, visualModel =
		createPuddleModel(hazardsFolder, template, metadata, placement, relativeScale, footprintSize, areaName)
	if not model then
		if reservedFootprints then
			table.remove(reservedFootprints)
		end
		return false
	end

	local controller = createController(model, hitbox, visualModel, placement.BiomeIndex, footprint, placement)
	bindPuddleTouchedSlow(controller)
	task.spawn(function()
		waitActiveLifetime(controller)
		controller:Destroy()
	end)

	trace(
		"spawned biome=%d area=%s band=%d template=%s source=%s surfaceReason=%s part=%s surfaces=%d relativeScale=%.2f slow=%.2f perSurface=%d",
		biomeIndex,
		tostring(areaName),
		tonumber(placement.PuddleBand) or 0,
		template.Name,
		tostring(placement.PlacementSource or "unknown"),
		tostring(placement.SurfaceAcceptanceReason or "unknown"),
		formatInstancePath(placement.PlacementPart),
		tonumber(placement.SurfaceCount) or 0,
		relativeScale,
		tonumber(placement.SlowMultiplier) or 0,
		tonumber(placement.PuddlesPerSurface) or 0
	)
	return true
end

local function spawnPuddleCycle()
	local refs, hazardsFolder, startPart, endPart, leftBound, rightBound = resolveRefs()
	if not hazardsFolder then
		return false
	end
	if not refs.Biomes then
		warnOnce(
			"missing_biome_refs",
			"Missing Workspace biome folders; biome-specific puddles will skip spawning instead of using legacy wave-slice placement."
		)
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

	local activeBySurface = getActivePuddleCountsBySurface()
	local jobs = {}
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	for biomeIndex = 1, biomeCount do
		local tuning = getPuddleTuningForBiome(biomeIndex)
		local surfaceEntries, surfaceSummary = getPuddleSurfaceEntries(refs, biomeIndex)
		if #surfaceEntries <= 0 then
			warnOnce(
				"missing_puddle_surfaces_" .. tostring(biomeIndex),
				"Skipping puddles for biome=%d area=%s because no accepted placement surfaces were found. diagnostics={%s}",
				biomeIndex,
				tostring(getAreaNameForBiome(biomeIndex)),
				formatPlacementDiagnostics(surfaceSummary)
			)
			continue
		end

		local targetPerSurface = getPuddlesPerSurfaceForBiome(biomeIndex)
		for surfaceIndex, surfaceEntry in ipairs(surfaceEntries) do
			local activeOnSurface = activeBySurface[surfaceEntry.Part] or 0
			local spawnCount = math.max(0, targetPerSurface - activeOnSurface)
			for spawnOrdinal = 1, spawnCount do
				jobs[#jobs + 1] = {
					BiomeIndex = biomeIndex,
					Tuning = tuning,
					SurfaceEntry = surfaceEntry,
					SurfaceIndex = surfaceIndex,
					SurfaceCount = #surfaceEntries,
					SpawnOrdinal = spawnOrdinal,
				}
			end
		end
	end

	shuffleArray(jobs)
	local reservedFootprints = {}

	for spawnIndex, job in ipairs(jobs) do
		if activeCount >= targetActive then
			break
		end

		if
			spawnPuddle(
				refs,
				hazardsFolder,
				startPart,
				endPart,
				leftBound,
				rightBound,
				job.BiomeIndex,
				reservedFootprints,
				job.Tuning,
				job.SurfaceEntry
			)
		then
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
