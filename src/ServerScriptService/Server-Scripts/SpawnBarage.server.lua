local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

print(string.format("[CANNON BARRAGE] boot path=%s", script:GetFullName()))

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local HazardRuntime = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardRuntime"))
local AffectableRegistry = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AffectableRegistry"))
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))

local devilFruitModules = ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruits")

local function safeRequire(moduleScript, label)
	if not moduleScript or not moduleScript:IsA("ModuleScript") then
		warn(string.format("[CANNON BARRAGE] optional module missing label=%s", tostring(label)))
		return nil
	end

	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(string.format("[CANNON BARRAGE] optional module failed label=%s err=%s", tostring(label), tostring(result)))
		return nil
	end

	return result
end

local HazardProtection = safeRequire(
	ServerScriptService:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Server"):FindFirstChild("HazardProtection"),
	"HazardProtection"
)
local HoroServer = safeRequire(
	devilFruitModules:FindFirstChild("Horo")
		and devilFruitModules.Horo:FindFirstChild("Server")
		and devilFruitModules.Horo.Server:FindFirstChild("HoroServer"),
	"HoroServer"
)
local ToriServer = safeRequire(
	devilFruitModules:FindFirstChild("Tori")
		and devilFruitModules.Tori:FindFirstChild("Server")
		and devilFruitModules.Tori.Server:FindFirstChild("ToriServer"),
	"ToriServer"
)

local CONFIG = {
	SpawnDelayMin = 0.5,
	SpawnDelayMax = 0.9,
	MaxActiveBarrages = 500,
	MaxPendingBarrages = 200,
	PendingPressureWeight = 0.2,
	-- Total number of distance slices between WaveStart and WaveEnd.
	-- Barrages only loop from MinimumZoneIndex through ZoneCount.
	ZoneCount = 8,
	MinimumZoneIndex = 2,
	MinimumForwardAlpha = 0.18,
	-- When true, difficulty tables are read backwards:
	-- actual zone 8 uses table entry [2], actual zone 7 uses [3], etc.
	ReverseZoneDifficulty = true,
	ZoneActiveCaps = {
		-- Max active + pending pressure allowed per difficulty profile.
		-- This controls how crowded a zone can get, not how many spawn per cycle.
		[2] = 20,
		[3] = 20,
		[4] = 20,
		[5] = 25,
		[6] = 40,
		[7] = 40,
		[8] = 50,
	},
	-- Fallback spawn count when ZoneSpawnsPerCycle has no entry for a profile.
	MaxZoneSpawnsPerCycle = 20,
	ZoneSpawnsPerCycle = {
		-- Spawn count per cycle by difficulty profile, not always visual zone.
		-- Because ReverseZoneDifficulty is true: [2] affects actual zone 8,
		-- [3] affects actual zone 7, ... [8] affects actual zone 2.
		-- Set an entry to 0 to completely stop new barrages for that profile.
		[2] = 20,
		[3] = 20,
		[4] = 20,
		[5] = 20,
		[6] = 20,
		[7] = 20,
		[8] = 20,
	},
	-- Chance to add one extra spawn in high-depth profiles. Ignored when
	-- ZoneSpawnsPerCycle for that profile is 0.
	ExtraBackZoneSpawnChance = 1,
	ZoneEdgePaddingAlpha = 0.08,
	ShotStaggerMin = 0.05,
	ShotStaggerMax = 0.12,
	ZoneShotStaggers = {
		[2] = { Min = 0.55, Max = 1 },
		[3] = { Min = 0.42, Max = 0.82 },
		[4] = { Min = 0.32, Max = 0.68 },
		[5] = { Min = 0.24, Max = 0.54 },
		[6] = { Min = 0.18, Max = 0.42 },
		[7] = { Min = 0.13, Max = 0.32 },
		[8] = { Min = 0.1, Max = 0.26 },
	},
	ZoneDropStartDelays = {
		[2] = { Min = 0.6, Max = 3.2 },
		[3] = { Min = 0.45, Max = 2.7 },
		[4] = { Min = 0.32, Max = 2.25 },
		[5] = { Min = 0.22, Max = 1.8 },
		[6] = { Min = 0.15, Max = 1.45 },
		[7] = { Min = 0.1, Max = 1.15 },
		[8] = { Min = 0.05, Max = 0.95 },
	},
	LaunchDelayJitterMin = 0,
	LaunchDelayJitterMax = 0.85,
	PreDropDelay = 0.08,
	FlightTime = 0.48,
	EarlyBiomeFlightTime = 2.0,
	LateBiomeFlightTime = 0.65,
	ZoneFlightTimes = {
		[2] = 2.25,
		[3] = 1.95,
		[4] = 1.6,
		[5] = 1.3,
		[6] = 1.05,
		[7] = 0.85,
		[8] = 0.68,
	},
	ImpactLifetime = 0.35,
	ImpactRadius = 20,
	ExplosionDamage = 100,
	DropHeight = 300,
	SkyWarningHeight = 28,
	CannonballRadius = 3.2,
	HazardClass = "minor",
	HazardType = "cannon_barrage",
	FreezeBehavior = "pause",
	FreezeDurationFallback = 1.5,
	AffectablePadding = Vector3.new(1.5, 1.5, 1.5),
	UseImpactMarkerTemplate = false,
	ImpactMarkerTemplateName = "CANNONBALL IMPACT PART SIZE",
	ImpactWarningStartColor = Color3.fromRGB(95, 0, 0),
	ImpactWarningEndColor = Color3.fromRGB(255, 35, 25),
	ImpactWarningTransparency = 0.28,
	ImpactWarningGroundOffset = 0.22,
	ImpactPositionAttempts = 40,
	GroundProbeHeight = 160,
	GroundProbeDepth = 340,
	GroundSampleRadiusAlpha = 0.45,
	MaxGroundHeightDelta = 5,
	SpawnAttemptMultiplier = 4,
	PreferPlayerTargets = true,
	PlayerTargetChance = 1,
	PlayerTargetJitterRadius = 6,
	PlayerTargetMaxGroundOffset = 12,
}

local rng = Random.new()
local activeControllers = {}
local pendingBarragesByZone = {}
local pendingBarrageCount = 0
local lastTraceStateKey = nil
local impactMarkerTemplate = false
local FLAT_RING_ROTATION = CFrame.Angles(0, 0, math.rad(90))

local BIOME_VARIATIONS = {
	["foosha village"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(172, 172, 172)),
		ParticleName = "SmokeBurst",
		RingColor = Color3.fromRGB(255, 60, 45),
	},
	["arlong park"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(81, 176, 255)),
		ParticleName = "WaterSplash",
		RingColor = Color3.fromRGB(42, 179, 255),
	},
	["drum island"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(238, 248, 255)),
		ParticleName = "FrostSmoke",
		RingColor = Color3.fromRGB(195, 238, 255),
	},
	["alabasta"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(190, 180, 160)),
		ParticleName = "SmokeBurst",
		RingColor = Color3.fromRGB(255, 70, 45),
	},
	["water 7"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(92, 190, 255)),
		ParticleName = "WaterSplash",
		RingColor = Color3.fromRGB(50, 187, 255),
	},
	["thriller bark"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(62, 55, 82)),
		ParticleName = "DarkFog",
		RingColor = Color3.fromRGB(130, 105, 190),
	},
	["sabaody"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(184, 235, 255)),
		ParticleName = "BubbleExplosion",
		RingColor = Color3.fromRGB(170, 242, 255),
	},
	["dressrosa"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(105, 205, 255)),
		ParticleName = "WaterFountain",
		RingColor = Color3.fromRGB(70, 190, 255),
	},
	["dresserosa"] = {
		ParticleColor = ColorSequence.new(Color3.fromRGB(105, 205, 255)),
		ParticleName = "WaterFountain",
		RingColor = Color3.fromRGB(70, 190, 255),
	},
}

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

local function barrageTrace(message, ...)
	print(string.format("[CANNON BARRAGE] " .. message, ...))
end

barrageTrace("script started path=%s", script:GetFullName())

local function getNoDisastersTimer()
	local value = Workspace:FindFirstChild("NoDisastersTimer")
	if value and value:IsA("ValueBase") then
		return value
	end

	return nil
end

local function getRootPart(character)
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getHumanoid(character)
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getCharacterContext(player)
	local character = player.Character
	local humanoid = getHumanoid(character)
	local rootPart = getRootPart(character)
	if not character or not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil
	end

	return character, humanoid, rootPart
end

local function isSukeHardToTarget(player)
	if not player then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	for _, attributeName in ipairs({
		"SukeFadeActive",
		"SukeInvisible",
		"SukeInvisibilityActive",
	}) do
		if player:GetAttribute(attributeName) == true then
			return true
		end
	end

	for _, attributeName in ipairs({
		"SukeFadeEndTime",
		"SukeInvisibleUntil",
		"SukeInvisibilityUntil",
	}) do
		local untilTime = player:GetAttribute(attributeName)
		if typeof(untilTime) == "number" and untilTime > now then
			return true
		end
	end

	return false
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

local function configureVisualPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)
end

local function configureHazardPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = true
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)
end

local function createPart(parent, name, size, cframeValue, color, material, transparency, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframeValue
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Shape = shape or Enum.PartType.Block
	configureVisualPart(part)
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

local function setVisualColor(instance, color)
	for _, part in ipairs(getBaseParts(instance)) do
		part.Color = color
	end
end

local function setVisualTransparency(instance, transparency)
	for _, part in ipairs(getBaseParts(instance)) do
		part.Transparency = transparency
	end
end

local function configureImpactMarker(instance)
	for _, part in ipairs(getBaseParts(instance)) do
		configureHazardPart(part)
		part.Color = CONFIG.ImpactWarningStartColor
		part.Material = Enum.Material.Neon
		part.Transparency = CONFIG.ImpactWarningTransparency
	end
end

local function placeImpactMarker(marker, impactPosition)
	local targetPosition = impactPosition + Vector3.new(0, CONFIG.ImpactWarningGroundOffset, 0)
	local originalRotation = getPivot(marker).Rotation
	setPivot(marker, CFrame.new(targetPosition) * originalRotation)

	if marker:IsA("Model") then
		local boundsCFrame = marker:GetBoundingBox()
		local centerOffset = targetPosition - boundsCFrame.Position
		marker:PivotTo(marker:GetPivot() + centerOffset)
	end
end

local function findImpactMarkerTemplate()
	if CONFIG.UseImpactMarkerTemplate ~= true then
		impactMarkerTemplate = nil
		return nil
	end

	if impactMarkerTemplate ~= false then
		return impactMarkerTemplate
	end

	local templateName = tostring(CONFIG.ImpactMarkerTemplateName or "")
	if templateName == "" then
		impactMarkerTemplate = nil
		return nil
	end

	local templateNames = { templateName }
	if not templateName:match("%.rbxm$") then
		templateNames[#templateNames + 1] = templateName .. ".rbxm"
	end

	for _, root in ipairs({ ReplicatedStorage, ServerStorage, Workspace, ServerScriptService }) do
		for _, name in ipairs(templateNames) do
			local direct = root:FindFirstChild(name, true)
			if direct and (direct:IsA("BasePart") or direct:IsA("Model")) and #getBaseParts(direct) > 0 then
				impactMarkerTemplate = direct
				barrageTrace("using impact marker template path=%s", formatInstancePath(direct))
				return direct
			end
		end
	end

	impactMarkerTemplate = nil
	barrageTrace("impact marker template missing name=%s using generated fallback", templateName)
	return nil
end

local function createImpactMarker(parent, impactPosition)
	local template = findImpactMarkerTemplate()
	if template then
		local marker = template:Clone()
		marker.Name = "ImpactZone"
		configureImpactMarker(marker)
		placeImpactMarker(marker, impactPosition)
		marker.Parent = parent

		return marker
	end

	local impactCircle = createPart(
		parent,
		"ImpactZone",
		Vector3.new(0.12, CONFIG.ImpactRadius * 2, CONFIG.ImpactRadius * 2),
		CFrame.new(impactPosition + Vector3.new(0, CONFIG.ImpactWarningGroundOffset, 0)) * FLAT_RING_ROTATION,
		CONFIG.ImpactWarningStartColor,
		Enum.Material.Neon,
		CONFIG.ImpactWarningTransparency,
		Enum.PartType.Cylinder
	)
	configureHazardPart(impactCircle)

	return impactCircle
end

local function createParticleBurst(parent, variation, rate)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = variation.ParticleName
	emitter.Color = variation.ParticleColor
	emitter.LightEmission = 0.35
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.35, 0.8)
	emitter.Speed = NumberRange.new(22, 40)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.5),
		NumberSequenceKeypoint.new(0.5, 5.5),
		NumberSequenceKeypoint.new(1, 0.5),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(0.75, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Parent = parent
	emitter:Emit(rate or 34)
	return emitter
end

local function resolveRefs()
	local refs = MapResolver.WaitForRefs(
		{ "MapRoot", "WaveFolder", "WaveStart", "WaveEnd" },
		nil,
		{
			warn = true,
			context = "CannonBarrage",
		}
	)

	local waveFolder = refs.WaveFolder
	local hazardsFolder = waveFolder and waveFolder:FindFirstChild("Hazards") or nil
	if waveFolder and not hazardsFolder then
		hazardsFolder = Instance.new("Folder")
		hazardsFolder.Name = "Hazards"
		hazardsFolder.Parent = waveFolder
		barrageTrace("created missing hazards folder path=%s", formatInstancePath(hazardsFolder))
	end

	local leftBound = waveFolder and waveFolder:FindFirstChild("LeftBound") or nil
	local rightBound = waveFolder and waveFolder:FindFirstChild("RightBound") or nil
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

	if lastTraceStateKey ~= stateKey then
		lastTraceStateKey = stateKey
		barrageTrace(
			"resolved map requestedMap=%s activeMap=%s waveFolder=%s hazardsFolder=%s start=%s end=%s leftBound=%s rightBound=%s",
			tostring(refs.RequestedMapName),
			tostring(refs.ActiveMapName),
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
	local lateral
	local halfWidth = 18
	local center = (startPart.Position + endPart.Position) * 0.5

	if leftBound and rightBound then
		lateral = getPlanarUnit(rightBound.Position - leftBound.Position, forward:Cross(Vector3.yAxis))
		halfWidth = math.max(4, (rightBound.Position - leftBound.Position).Magnitude * 0.5)
		center = (leftBound.Position + rightBound.Position) * 0.5
	else
		lateral = getPlanarUnit(forward:Cross(Vector3.yAxis), Vector3.xAxis)
	end

	return forward, lateral, halfWidth, center
end

local function clampImpactToCorridor(position, startPart, endPart, leftBound, rightBound)
	local forward, lateral, halfWidth = getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local corridorPaddingRadius = math.min(CONFIG.ImpactRadius, math.max(0, halfWidth - 1))
	local startProjection = startPart.Position:Dot(forward)
	local endProjection = endPart.Position:Dot(forward)
	local pathDistance = math.abs(endProjection - startProjection)
	local minimumForwardAlpha = math.clamp(tonumber(CONFIG.MinimumForwardAlpha) or 0, 0, 0.95)
	local minForward = math.min(startProjection, endProjection) + pathDistance * minimumForwardAlpha
	local maxForward = math.max(startProjection, endProjection)
	local clampedForward = math.clamp(position:Dot(forward), minForward, maxForward)

	local centerProjection = ((leftBound and rightBound) and ((leftBound.Position + rightBound.Position) * 0.5) or startPart.Position):Dot(lateral)
	local clampedLateral = math.clamp(
		position:Dot(lateral),
		centerProjection - halfWidth + corridorPaddingRadius,
		centerProjection + halfWidth - corridorPaddingRadius
	)

	local base = forward * clampedForward + lateral * clampedLateral
	return Vector3.new(base.X, position.Y, base.Z)
end

local function isUnsafeImpactSurface(instance)
	local current = instance
	while current do
		local name = string.lower(current.Name)
		if name:find("safe", 1, true)
			or name:find("vip", 1, true)
			or name:find("barrier", 1, true)
			or name:find("refuge", 1, true)
			or name:find("spawn", 1, true)
			or name:find("gap", 1, true)
		then
			return true
		end

		current = current.Parent
	end

	return false
end

local function buildGroundRaycastParams(refs)
	local exclusions = {}
	if refs and refs.WaveFolder then
		exclusions[#exclusions + 1] = refs.WaveFolder:FindFirstChild("Hazards")
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

local function raycastGround(position, refs, raycastParams)
	local height = math.max(10, tonumber(CONFIG.GroundProbeHeight) or 160)
	local depth = math.max(height + 10, tonumber(CONFIG.GroundProbeDepth) or 340)
	local result = Workspace:Raycast(position + Vector3.new(0, height, 0), Vector3.new(0, -depth, 0), raycastParams or buildGroundRaycastParams(refs))
	if result and not isUnsafeImpactSurface(result.Instance) then
		return result
	end

	return nil
end

local function resolveSafeGroundPosition(position, refs)
	local raycastParams = buildGroundRaycastParams(refs)
	local centerResult = raycastGround(position, refs, raycastParams)
	if not centerResult then
		return nil
	end

	local sampleRadius = CONFIG.ImpactRadius * math.clamp(tonumber(CONFIG.GroundSampleRadiusAlpha) or 0.75, 0.1, 1)
	local sampleOffsets = {
		Vector3.new(sampleRadius, 0, 0),
		Vector3.new(-sampleRadius, 0, 0),
		Vector3.new(0, 0, sampleRadius),
		Vector3.new(0, 0, -sampleRadius),
		Vector3.new(sampleRadius * 0.7, 0, sampleRadius * 0.7),
		Vector3.new(-sampleRadius * 0.7, 0, sampleRadius * 0.7),
		Vector3.new(sampleRadius * 0.7, 0, -sampleRadius * 0.7),
		Vector3.new(-sampleRadius * 0.7, 0, -sampleRadius * 0.7),
	}
	local maxHeightDelta = math.max(0, tonumber(CONFIG.MaxGroundHeightDelta) or 5)

	for _, offset in ipairs(sampleOffsets) do
		local sampleResult = raycastGround(position + offset, refs, raycastParams)
		if not sampleResult or math.abs(sampleResult.Position.Y - centerResult.Position.Y) > maxHeightDelta then
			return nil
		end
	end

	return centerResult.Position
end

local function getGroundPosition(position, refs)
	return resolveSafeGroundPosition(position, refs) or position
end

local function getBiomeVariation(refs, startPart, endPart, impactPosition)
	local areaName = nil
	local biomeAreas = Modules:FindFirstChild("Configs") and Modules.Configs:FindFirstChild("BiomeAreas")
	if biomeAreas and biomeAreas:IsA("ModuleScript") then
		local ok, config = pcall(require, biomeAreas)
		if ok and type(config) == "table" then
			local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
			local total = math.max(1, math.abs((endPart.Position - startPart.Position):Dot(forward)))
			local alpha = math.clamp(math.abs((impactPosition - startPart.Position):Dot(forward)) / total, 0, 0.999)
			local biomeIndex = math.clamp(math.floor(alpha * 8) + 1, 1, 8)
			local entry = config.GetBiome and config.GetBiome(biomeIndex)
			areaName = entry and entry.AreaName or nil
		end
	end

	local key = string.lower(tostring(areaName or refs.ActiveMapRootName or refs.ActiveMapName or ""))
	return BIOME_VARIATIONS[key] or BIOME_VARIATIONS["foosha village"], areaName or tostring(refs.ActiveMapName or "Map")
end

local function getZoneAlphaRange(zoneIndex)
	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	local minimumZoneIndex = math.clamp(math.floor(tonumber(CONFIG.MinimumZoneIndex) or 1), 1, zoneCount)
	local normalizedIndex = math.clamp(math.floor(tonumber(zoneIndex) or minimumZoneIndex), minimumZoneIndex, zoneCount)
	local zoneStart = (normalizedIndex - 1) / zoneCount
	local zoneEnd = normalizedIndex / zoneCount
	local padding = math.clamp(tonumber(CONFIG.ZoneEdgePaddingAlpha) or 0, 0, 0.45) / zoneCount
	local minimumForwardAlpha = math.clamp(tonumber(CONFIG.MinimumForwardAlpha) or 0, 0, 0.95)
	local paddedStart = if normalizedIndex == minimumZoneIndex then zoneStart else zoneStart + padding
	local paddedEnd = if normalizedIndex == zoneCount then zoneEnd else zoneEnd - padding

	return math.clamp(math.max(paddedStart, minimumForwardAlpha), 0, 1),
		math.clamp(math.max(paddedEnd, minimumForwardAlpha), 0, 1),
		normalizedIndex
end

local function getZoneProfileIndex(zoneIndex)
	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	local minimumZoneIndex = math.clamp(math.floor(tonumber(CONFIG.MinimumZoneIndex) or 1), 1, zoneCount)
	local normalizedZoneIndex = math.clamp(math.floor(tonumber(zoneIndex) or minimumZoneIndex), minimumZoneIndex, zoneCount)
	if CONFIG.ReverseZoneDifficulty == true then
		return minimumZoneIndex + (zoneCount - normalizedZoneIndex)
	end

	return normalizedZoneIndex
end

local function getZoneProfileDepthAlpha(zoneIndex)
	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	local profileZoneIndex = getZoneProfileIndex(zoneIndex)
	return math.clamp(profileZoneIndex / zoneCount, 0, 1)
end

local function getZoneActiveCap(zoneIndex)
	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	local normalizedZoneIndex = math.clamp(math.floor(tonumber(zoneIndex) or 1), 1, zoneCount)
	local profileZoneIndex = getZoneProfileIndex(normalizedZoneIndex)
	local configuredCaps = type(CONFIG.ZoneActiveCaps) == "table" and CONFIG.ZoneActiveCaps or {}
	local configuredCap = tonumber(configuredCaps[profileZoneIndex])
	if configuredCap then
		return math.max(0, math.floor(configuredCap))
	end

	local depthAlpha = math.clamp(profileZoneIndex / zoneCount, 0, 1)
	return math.max(1, math.floor(1 + depthAlpha * 4))
end

local function getForwardAlphaForPosition(position, startPart, endPart)
	local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
	local totalDistance = math.max(1, math.abs((endPart.Position - startPart.Position):Dot(forward)))
	local rawAlpha = (position - startPart.Position):Dot(forward) / totalDistance

	return math.clamp(rawAlpha, 0, 1)
end

local function getZoneIndexForForwardAlpha(forwardAlpha)
	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	local minimumZoneIndex = math.clamp(math.floor(tonumber(CONFIG.MinimumZoneIndex) or 1), 1, zoneCount)
	local zoneIndex = math.floor(math.clamp(forwardAlpha, 0, 0.999) * zoneCount) + 1

	return math.clamp(zoneIndex, minimumZoneIndex, zoneCount)
end

local function isForwardAlphaInZone(forwardAlpha, zoneIndex)
	local zoneStartAlpha, zoneEndAlpha = getZoneAlphaRange(zoneIndex)

	return forwardAlpha >= zoneStartAlpha and forwardAlpha <= math.max(zoneStartAlpha, zoneEndAlpha)
end

local function getTargetJitterOffset()
	local jitterRadius = math.max(0, tonumber(CONFIG.PlayerTargetJitterRadius) or 0)
	if jitterRadius <= 0 then
		return Vector3.zero
	end

	local angle = rng:NextNumber(0, math.pi * 2)
	local distance = math.sqrt(rng:NextNumber()) * jitterRadius

	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

local function choosePlayerTargetPosition(refs, startPart, endPart, leftBound, rightBound, zoneIndex)
	if CONFIG.PreferPlayerTargets ~= true then
		return nil, nil, "player_targeting_disabled"
	end

	local targetChance = math.clamp(tonumber(CONFIG.PlayerTargetChance) or 1, 0, 1)
	if targetChance <= 0 or rng:NextNumber() > targetChance then
		return nil, nil, "player_target_chance"
	end

	local candidates = {}
	local maxGroundOffset = math.max(0, tonumber(CONFIG.PlayerTargetMaxGroundOffset) or 12)
	local zoneStartAlpha = select(1, getZoneAlphaRange(zoneIndex))
	local fallbackZoneIndex = getZoneIndexForForwardAlpha(zoneStartAlpha)

	for _, player in ipairs(Players:GetPlayers()) do
		local _, humanoid, rootPart = getCharacterContext(player)
		if humanoid and rootPart and not isSukeHardToTarget(player) then
			local rootPosition = rootPart.Position
			local forwardAlpha = getForwardAlphaForPosition(rootPosition, startPart, endPart)
			if isForwardAlphaInZone(forwardAlpha, zoneIndex) then
				local rootGroundPosition = resolveSafeGroundPosition(rootPosition, refs)
				local clampedPosition = clampImpactToCorridor(
					rootPosition + getTargetJitterOffset(),
					startPart,
					endPart,
					leftBound,
					rightBound
				)
				local groundPosition = rootGroundPosition and resolveSafeGroundPosition(clampedPosition, refs)
				if rootGroundPosition
					and groundPosition
					and math.abs(rootPosition.Y - rootGroundPosition.Y) <= maxGroundOffset
					and math.abs(rootPosition.Y - groundPosition.Y) <= maxGroundOffset
				then
					candidates[#candidates + 1] = {
						Player = player,
						Position = groundPosition,
						ForwardAlpha = forwardAlpha,
					}
				end
			end
		end
	end

	if #candidates <= 0 then
		return nil, fallbackZoneIndex, "no_valid_player_target"
	end

	local chosen = candidates[rng:NextInteger(1, #candidates)]
	local normalizedZoneIndex = getZoneIndexForForwardAlpha(chosen.ForwardAlpha)

	return chosen.Position,
		normalizedZoneIndex,
		string.format("player:%s:%.2f", chosen.Player.Name, chosen.ForwardAlpha)
end

local function chooseZonePosition(refs, startPart, endPart, leftBound, rightBound, zoneIndex)
	local forward, lateral, halfWidth = getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local zoneStartAlpha, zoneEndAlpha, normalizedZoneIndex = getZoneAlphaRange(zoneIndex)
	local attempts = math.max(1, math.floor(tonumber(CONFIG.ImpactPositionAttempts) or 1))
	for _ = 1, attempts do
		local forwardAlpha = rng:NextNumber(zoneStartAlpha, math.max(zoneStartAlpha, zoneEndAlpha))
		local corridorPaddingRadius = math.min(CONFIG.ImpactRadius, math.max(0, halfWidth - 1))
		local lateralLimit = math.max(0, halfWidth - corridorPaddingRadius)
		local lateralOffset = rng:NextNumber(-lateralLimit, lateralLimit)
		local position = startPart.Position:Lerp(endPart.Position, forwardAlpha) + lateral * lateralOffset

		position = clampImpactToCorridor(position, startPart, endPart, leftBound, rightBound)

		local groundPosition = resolveSafeGroundPosition(position, refs)
		if groundPosition then
			return groundPosition, normalizedZoneIndex, forwardAlpha
		end
	end

	barrageTrace("safe ground skipped zone=%d attempts=%d", normalizedZoneIndex, attempts)
	return nil, normalizedZoneIndex, zoneStartAlpha
end

local function chooseImpactPosition(refs, startPart, endPart, leftBound, rightBound, zoneIndex)
	local targetPosition, targetZoneIndex, targetSource =
		choosePlayerTargetPosition(refs, startPart, endPart, leftBound, rightBound, zoneIndex)
	if targetPosition then
		return targetPosition, targetZoneIndex, targetSource
	end

	local position, normalizedZoneIndex, forwardAlpha = chooseZonePosition(refs, startPart, endPart, leftBound, rightBound, zoneIndex)
	if not position then
		return nil, normalizedZoneIndex, string.format("no_safe_ground:%.2f", forwardAlpha)
	end

	return position, normalizedZoneIndex, string.format("random_ground:%s:%.2f", tostring(targetSource), forwardAlpha)
end

local function createCannonBarrageModel(hazardsFolder, refs, startPart, endPart, leftBound, rightBound, impactPosition)
	local variation = getBiomeVariation(refs, startPart, endPart, impactPosition)
	local startPosition = impactPosition + Vector3.new(0, CONFIG.DropHeight, 0)
	local targetPosition = impactPosition + Vector3.new(0, CONFIG.CannonballRadius, 0)

	local model = Instance.new("Model")
	model.Name = "CannonBarrage"
	model:SetAttribute("HazardClass", CONFIG.HazardClass)
	model:SetAttribute("HazardType", CONFIG.HazardType)
	model:SetAttribute("CanFreeze", true)
	model:SetAttribute("FreezeBehavior", CONFIG.FreezeBehavior)

	local impactCircle = createImpactMarker(model, impactPosition)

	local skyWarning = createPart(
		model,
		"SkyDropWarning",
		Vector3.new(0.3, 0.3, 0.3),
		CFrame.new(impactPosition + Vector3.new(0, CONFIG.SkyWarningHeight, 0)) * FLAT_RING_ROTATION,
		Color3.fromRGB(255, 85, 65),
		Enum.Material.Neon,
		1,
		Enum.PartType.Ball
	)
	skyWarning.CanQuery = false
	skyWarning.CanTouch = false

	local cannonball = createPart(
		model,
		"Cannonball",
		Vector3.new(CONFIG.CannonballRadius * 2, CONFIG.CannonballRadius * 2, CONFIG.CannonballRadius * 2),
		CFrame.new(startPosition),
		Color3.fromRGB(18, 18, 20),
		Enum.Material.Metal,
		0,
		Enum.PartType.Ball
	)
	configureHazardPart(cannonball)
	cannonball:SetAttribute("CanFreeze", true)
	cannonball:SetAttribute("HazardClass", CONFIG.HazardClass)
	cannonball:SetAttribute("HazardType", CONFIG.HazardType)

	model.WorldPivot = CFrame.new(impactPosition)
	model.Parent = hazardsFolder

	return model, {
		ImpactCircle = impactCircle,
		SkyWarning = skyWarning,
		Cannonball = cannonball,
		StartPosition = startPosition,
		ImpactPosition = impactPosition,
		TargetPosition = targetPosition,
		Variation = variation,
	}
end

local function applyFrozenVisual(controller, isFrozen)
	if not controller or not controller.Parts then
		return
	end

	local cannonball = controller.Parts.Cannonball
	if cannonball and cannonball.Parent then
		cannonball.Color = if isFrozen then Color3.fromRGB(178, 235, 255) else Color3.fromRGB(18, 18, 20)
		cannonball.Material = if isFrozen then Enum.Material.Ice else Enum.Material.Metal
	end

	local impactCircle = controller.Parts.ImpactCircle
	if impactCircle and impactCircle.Parent then
		local progress = math.clamp(tonumber(controller.ImpactWarningProgress) or 0, 0, 1)
		local warningColor = CONFIG.ImpactWarningStartColor:Lerp(CONFIG.ImpactWarningEndColor, progress)
		setVisualColor(impactCircle, if isFrozen then Color3.fromRGB(196, 240, 255) else warningColor)
	end

	local skyWarning = controller.Parts.SkyWarning
	if skyWarning and skyWarning.Parent then
		skyWarning.Color = if isFrozen then Color3.fromRGB(196, 240, 255) else Color3.fromRGB(255, 85, 65)
		skyWarning.Transparency = 1
	end
end

local function unregisterController(controller)
	if not controller then
		return
	end

	activeControllers[controller.Model] = nil
	if controller.AffectableEntity then
		AffectableRegistry.UnregisterEntity(controller.AffectableEntity)
		controller.AffectableEntity = nil
	end
	HazardRuntime.Unregister(controller.Model)
end

local function buildHazardVolumes(controller)
	if controller.Destroyed or not controller.Model.Parent then
		return {}
	end

	local volumes = {}
	local cannonball = controller.Parts.Cannonball
	if cannonball and cannonball.Parent and cannonball.Transparency < 1 then
		volumes[#volumes + 1] = {
			Type = AffectableRegistry.VolumeType.Sphere,
			Label = "Cannonball",
			Center = cannonball.Position,
			Radius = CONFIG.CannonballRadius,
			Padding = CONFIG.AffectablePadding,
		}
	end

	local impactCircle = controller.Parts.ImpactCircle
	if impactCircle and impactCircle.Parent then
		volumes[#volumes + 1] = {
			Type = AffectableRegistry.VolumeType.Sphere,
			Label = "ImpactZone",
			Center = controller.Parts.ImpactPosition,
			Radius = CONFIG.ImpactRadius,
			Padding = Vector3.new(1, 0.5, 1),
		}
	end

	return volumes
end

local function createController(model, parts)
	local controller = {
		Model = model,
		Parts = parts,
		Destroyed = false,
		FrozenUntil = 0,
		FreezeToken = 0,
		ImpactWarningProgress = 0,
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
		applyFrozenVisual(self, true)

		task.spawn(function()
			while not self.Destroyed and self.Model.Parent and os.clock() < self.FrozenUntil do
				task.wait(0.05)
			end

			if self.Destroyed or self.FreezeToken ~= freezeToken then
				return
			end

			applyFrozenVisual(self, false)
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
		CanBeAffectedBy = function(_, query)
			if query and query.RequireCanFreeze == true then
				return true, "ok"
			end

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
				Position = parts.Cannonball and parts.Cannonball.Position or parts.ImpactPosition,
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

local function getFlightTimeForZone(zoneIndex)
	local configuredTimes = type(CONFIG.ZoneFlightTimes) == "table" and CONFIG.ZoneFlightTimes or {}
	local profileZoneIndex = getZoneProfileIndex(zoneIndex)
	local configuredTime = tonumber(configuredTimes[profileZoneIndex])
	if configuredTime then
		return math.max(0.05, configuredTime)
	end

	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	local minimumZoneIndex = math.clamp(math.floor(tonumber(CONFIG.MinimumZoneIndex) or 1), 1, zoneCount)
	local normalizedZoneIndex = math.clamp(math.floor(tonumber(zoneIndex) or minimumZoneIndex), minimumZoneIndex, zoneCount)
	local zoneSpan = math.max(1, zoneCount - minimumZoneIndex)
	local depthAlpha = math.clamp((normalizedZoneIndex - minimumZoneIndex) / zoneSpan, 0, 1)
	local earlyFlightTime = math.max(0.05, tonumber(CONFIG.EarlyBiomeFlightTime) or CONFIG.FlightTime)
	local lateFlightTime = math.max(0.05, tonumber(CONFIG.LateBiomeFlightTime) or CONFIG.FlightTime)

	return earlyFlightTime + ((lateFlightTime - earlyFlightTime) * depthAlpha)
end

local function getShotStaggerForZone(zoneIndex)
	local configuredStaggers = type(CONFIG.ZoneShotStaggers) == "table" and CONFIG.ZoneShotStaggers or {}
	local zoneStagger = configuredStaggers[getZoneProfileIndex(zoneIndex)]
	local minStagger = tonumber(zoneStagger and zoneStagger.Min) or tonumber(CONFIG.ShotStaggerMin) or 0.05
	local maxStagger = tonumber(zoneStagger and zoneStagger.Max) or tonumber(CONFIG.ShotStaggerMax) or minStagger

	return rng:NextNumber(math.max(0, minStagger), math.max(minStagger, maxStagger))
end

local function getDropStartDelayForZone(zoneIndex)
	local configuredDelays = type(CONFIG.ZoneDropStartDelays) == "table" and CONFIG.ZoneDropStartDelays or {}
	local zoneDelay = configuredDelays[getZoneProfileIndex(zoneIndex)]
	local minDelay = tonumber(zoneDelay and zoneDelay.Min) or 0
	local maxDelay = tonumber(zoneDelay and zoneDelay.Max) or minDelay

	return rng:NextNumber(math.max(0, minDelay), math.max(minDelay, maxDelay))
end

local function getLaunchDelayJitter()
	local minJitter = tonumber(CONFIG.LaunchDelayJitterMin) or 0
	local maxJitter = tonumber(CONFIG.LaunchDelayJitterMax) or minJitter

	return rng:NextNumber(math.max(0, minJitter), math.max(minJitter, maxJitter))
end

local function getMaxZoneSpawnsForCycle(zoneIndex)
	local configuredSpawns = type(CONFIG.ZoneSpawnsPerCycle) == "table" and CONFIG.ZoneSpawnsPerCycle or {}
	local configuredCount = tonumber(configuredSpawns[getZoneProfileIndex(zoneIndex)])
	if configuredCount then
		return math.max(0, math.floor(configuredCount))
	end

	return math.max(0, math.floor(tonumber(CONFIG.MaxZoneSpawnsPerCycle) or 1))
end

local function updateImpactWarningProgress(controller, progress)
	if not controller or not controller.Parts then
		return
	end

	controller.ImpactWarningProgress = math.clamp(tonumber(progress) or 0, 0, 1)
	local impactCircle = controller.Parts.ImpactCircle
	if impactCircle and impactCircle.Parent and os.clock() >= controller.FrozenUntil then
		setVisualColor(
			impactCircle,
			CONFIG.ImpactWarningStartColor:Lerp(CONFIG.ImpactWarningEndColor, controller.ImpactWarningProgress)
		)
		setVisualTransparency(impactCircle, CONFIG.ImpactWarningTransparency)
	end
end

local function isAirborneToriFlight(player, humanoid)
	return ToriServer
		and typeof(ToriServer.IsPhoenixFlightActive) == "function"
		and ToriServer.IsPhoenixFlightActive(player)
		and humanoid
		and humanoid.FloorMaterial == Enum.Material.Air
end

local function damagePlayer(player, impactPosition)
	local character, humanoid, rootPart = getCharacterContext(player)
	if not character then
		return false, "invalid_character"
	end

	if (rootPart.Position - impactPosition).Magnitude > CONFIG.ImpactRadius then
		return false, "outside_radius"
	end

	if HoroServer
		and typeof(HoroServer.IsProjecting) == "function"
		and HoroServer.IsProjecting(player)
		and character:GetAttribute("HoroProjectionGhost") == true
	then
		HoroServer.InterruptActiveProjection(player, "cannon_barrage", impactPosition)
		return true, "horo_ghost_tanked"
	end

	if isAirborneToriFlight(player, humanoid) then
		return true, "tori_glide_avoided"
	end

	local protected = HazardProtection
		and typeof(HazardProtection.IsProtected) == "function"
		and HazardProtection.IsProtected(player, {
			Position = impactPosition,
			Context = "CannonBarrage",
		})
	if protected then
		return true, "hazard_protected"
	end

	local applied = HitEffectService.ApplyEffect(player, "Knockdown", {
		Duration = 1.1,
		DropPosition = rootPart.Position,
		RagdollJoints = true,
		RagdollImpulse = (getPlanarUnit(rootPart.Position - impactPosition, Vector3.zAxis) * 48) + Vector3.new(0, 28, 0),
		Movement = {
			WalkSpeedMultiplier = 0,
			JumpMultiplier = 0,
			AutoRotate = false,
			PlatformStand = true,
			State = Enum.HumanoidStateType.Ragdoll,
		},
	})

	if applied and CONFIG.ExplosionDamage < humanoid.Health then
		humanoid:TakeDamage(CONFIG.ExplosionDamage)
	else
		humanoid.Health = 0
	end

	return true, "damaged"
end

local function explode(controller)
	if controller.Destroyed or not controller.Model.Parent then
		return
	end

	local impactPosition = controller.Parts.ImpactPosition
	local anchor = createPart(
		controller.Model,
		"ImpactBurstAnchor",
		Vector3.new(0.3, 0.3, 0.3),
		CFrame.new(impactPosition + Vector3.new(0, 1.2, 0)),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		1,
		Enum.PartType.Ball
	)
	createParticleBurst(anchor, controller.Parts.Variation, 46)

	local cannonball = controller.Parts.Cannonball
	if cannonball and cannonball.Parent then
		cannonball.Transparency = 1
		cannonball.CanQuery = false
		cannonball.CanTouch = false
	end

	local damagedCount = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local handled = damagePlayer(player, impactPosition)
		if handled then
			damagedCount += 1
		end
	end

	barrageTrace(
		"impact area=%s pos=%s affected=%d",
		tostring(controller.AreaName),
		formatVector3(impactPosition),
		damagedCount
	)
end

local function runBarrage(controller)
	local parts = controller.Parts
	local flightTime = getFlightTimeForZone(controller.ZoneIndex)
	parts.FlightTime = flightTime
	updateImpactWarningProgress(controller, 0)
	createParticleBurst(parts.SkyWarning, parts.Variation, 14)

	if not waitWhileFrozen(controller, CONFIG.PreDropDelay) then
		return
	end

	local cannonball = parts.Cannonball
	local startPosition = parts.StartPosition
	local targetPosition = parts.TargetPosition
	local elapsed = 0

	while elapsed < flightTime do
		if controller.Destroyed or not controller.Model.Parent then
			return
		end

		if os.clock() < controller.FrozenUntil then
			task.wait(0.05)
		else
			local dt = RunService.Heartbeat:Wait()
			elapsed = math.min(flightTime, elapsed + dt)
			local alpha = elapsed / flightTime
			local easedAlpha = alpha * alpha
			local position = startPosition:Lerp(targetPosition, easedAlpha)
			cannonball.CFrame = CFrame.new(position)
			updateImpactWarningProgress(controller, alpha)
		end
	end

	explode(controller)
	waitWhileFrozen(controller, CONFIG.ImpactLifetime)
	controller:Destroy()
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

local function getActiveCountByZone()
	local countsByZone = {}
	local totalCount = 0

	for model, controller in pairs(activeControllers) do
		if not controller or controller.Destroyed or not model.Parent then
			activeControllers[model] = nil
		else
			totalCount += 1
			local zoneIndex = math.floor(tonumber(controller.ZoneIndex) or 0)
			if zoneIndex > 0 then
				countsByZone[zoneIndex] = (countsByZone[zoneIndex] or 0) + 1
			end
		end
	end

	local pendingPressureWeight = math.clamp(tonumber(CONFIG.PendingPressureWeight) or 0.2, 0, 1)
	for zoneIndex, count in pairs(pendingBarragesByZone) do
		countsByZone[zoneIndex] = (countsByZone[zoneIndex] or 0) + (count * pendingPressureWeight)
	end

	return countsByZone, totalCount
end

local function chooseSpawnDelay()
	return rng:NextNumber(CONFIG.SpawnDelayMin, CONFIG.SpawnDelayMax)
end

local function spawnBarrageCycle()
	local refs, _, hazardsFolder, startPart, endPart, leftBound, rightBound = resolveRefs()
	if not (hazardsFolder and startPart and endPart) then
		barrageTrace(
			"cycle skipped reason=missing_refs hazardsFolder=%s start=%s end=%s",
			formatInstancePath(hazardsFolder),
			formatInstancePath(startPart),
			formatInstancePath(endPart)
		)
		return false
	end

	local spawnedCount = 0
	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	local minimumZoneIndex = math.clamp(math.floor(tonumber(CONFIG.MinimumZoneIndex) or 1), 1, zoneCount)
	local countsByZone, totalActiveCount = getActiveCountByZone()
	barrageTrace("cycle pressure active=%d max=%d", totalActiveCount, CONFIG.MaxActiveBarrages)

	for zoneIndex = minimumZoneIndex, zoneCount do
		if totalActiveCount >= CONFIG.MaxActiveBarrages then
			break
		end

		local activeInZone = countsByZone[zoneIndex] or 0
		local zoneCap = getZoneActiveCap(zoneIndex)
		local deficit = math.max(0, zoneCap - activeInZone)
		if deficit <= 0 then
			continue
		end

		local depthAlpha = getZoneProfileDepthAlpha(zoneIndex)
		local maxZoneSpawns = getMaxZoneSpawnsForCycle(zoneIndex)
		local depthSpawnLimit = if maxZoneSpawns > 0 then math.max(1, math.ceil(maxZoneSpawns * depthAlpha)) else 0
		local spawnsThisZone = math.floor(math.min(deficit, depthSpawnLimit))
		local zoneStartAlpha, zoneEndAlpha = getZoneAlphaRange(zoneIndex)
		if maxZoneSpawns > 0
			and spawnsThisZone < deficit
			and depthAlpha >= 0.75
			and rng:NextNumber() < CONFIG.ExtraBackZoneSpawnChance
		then
			spawnsThisZone = math.floor(math.min(deficit, spawnsThisZone + 1))
		end

		barrageTrace(
			"zone pressure zone=%d alpha=%.3f-%.3f pressure=%.1f cap=%d spawning=%d",
			zoneIndex,
			zoneStartAlpha,
			zoneEndAlpha,
			activeInZone,
			zoneCap,
			spawnsThisZone
		)

		local shotIndex = 0
		local spawnAttempts = 0
		local maxSpawnAttempts = math.max(spawnsThisZone, math.ceil(spawnsThisZone * (tonumber(CONFIG.SpawnAttemptMultiplier) or 4)))
		while shotIndex < spawnsThisZone and spawnAttempts < maxSpawnAttempts do
			if totalActiveCount >= CONFIG.MaxActiveBarrages
				or pendingBarrageCount >= math.max(0, tonumber(CONFIG.MaxPendingBarrages) or 0)
			then
				break
			end

			spawnAttempts += 1
			local impactPosition, normalizedZoneIndex, source = chooseImpactPosition(
				refs,
				startPart,
				endPart,
				leftBound,
				rightBound,
				zoneIndex
			)
			if not impactPosition then
				barrageTrace(
					"spawn skipped zone=%d source=%s reason=no_safe_ground",
					normalizedZoneIndex,
					tostring(source)
				)
				continue
			end

			shotIndex += 1
			local launchDelay = getDropStartDelayForZone(normalizedZoneIndex)
			if shotIndex > 1 then
				launchDelay += getShotStaggerForZone(normalizedZoneIndex) * (shotIndex - 1)
			end
			launchDelay += getLaunchDelayJitter()

			pendingBarragesByZone[normalizedZoneIndex] = (pendingBarragesByZone[normalizedZoneIndex] or 0) + 1
			pendingBarrageCount += 1
			countsByZone[normalizedZoneIndex] = (countsByZone[normalizedZoneIndex] or 0)
				+ math.clamp(tonumber(CONFIG.PendingPressureWeight) or 0.2, 0, 1)
			spawnedCount += 1

			barrageTrace(
				"scheduled zone=%d source=%s impact=%s flightTime=%.2f launchDelay=%.2f",
				normalizedZoneIndex,
				tostring(source),
				formatVector3(impactPosition),
				getFlightTimeForZone(normalizedZoneIndex),
				launchDelay
			)

			task.delay(launchDelay, function()
				pendingBarragesByZone[normalizedZoneIndex] = math.max(0, (pendingBarragesByZone[normalizedZoneIndex] or 0) - 1)
				pendingBarrageCount = math.max(0, pendingBarrageCount - 1)

				if not hazardsFolder.Parent then
					return
				end

				local model, parts = createCannonBarrageModel(
					hazardsFolder,
					refs,
					startPart,
					endPart,
					leftBound,
					rightBound,
					impactPosition
				)
				local _, areaName = getBiomeVariation(refs, startPart, endPart, impactPosition)
				local controller = createController(model, parts)
				controller.AreaName = areaName
				controller.ZoneIndex = normalizedZoneIndex

				runBarrage(controller)
			end)
		end

		if shotIndex < spawnsThisZone then
			barrageTrace(
				"zone underfilled zone=%d spawned=%d wanted=%d attempts=%d",
				zoneIndex,
				shotIndex,
				spawnsThisZone,
				spawnAttempts
			)
		end
	end

	return spawnedCount > 0
end

local noDisastersTimer = getNoDisastersTimer()

while true do
	if noDisastersTimer and noDisastersTimer.Value > 0 then
		task.wait(1)
	else
		local ok, err = xpcall(spawnBarrageCycle, debug.traceback)
		if not ok then
			barrageTrace("spawn error=%s", tostring(err))
		end
		task.wait(chooseSpawnDelay())
	end
end
