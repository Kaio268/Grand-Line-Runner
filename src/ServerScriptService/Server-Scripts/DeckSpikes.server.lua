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
	SpikesPerPop = 2,

	WarningTime = 3,
	ThrustTime = 0.12,
	HoldTime = 2.5,
	RetractTime = 0.16,

	BiomeCount = 8,
	MaxActiveSpikes = 180,
	SpawnAttempts = 30,
	MinimumForwardAlpha = 0.14,
	MaximumForwardAlpha = 0.94,
	BiomePaddingAlpha = 0.08,

	GroundProbeHeight = 120,
	GroundProbeDepth = 260,
	MaxGroundHeightDelta = 3,
	SafeGapBuffer = 24,
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

	LaneCount = 20,
	LaneWidthScale = 0.82,
	SpikeHeight = 7,
	SpikeLength = 18,
	SpikeVisualScale = 3.2,
	PreviewHeight = 0.45,
	WarningGroundOffset = 0.25,

	Damage = 65,
	KnockdownDuration = 0.8,
	HazardClass = "minor",
	HazardType = "deck_spikes",
	SpikeTrapFolderName = "Spike Traps",
	UseSpikeTrapTemplates = true,
	ReverseBiomeTemplates = true,
	IgnoreNoDisastersTimerInStudio = true,
}

if not CONFIG.Enabled then
	return
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

local rng = Random.new()
local activeControllers = {}
local warnedMessages = {}

local function warnOnce(key, message, ...)
	if warnedMessages[key] then
		return
	end

	warnedMessages[key] = true
	warn(string.format("[DECK SPIKES] " .. message, ...))
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
		{ "MapRoot", "WaveFolder", "WaveStart", "WaveEnd" },
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

	local leftBound = waveFolder and waveFolder:FindFirstChild("LeftBound")
	local rightBound = waveFolder and waveFolder:FindFirstChild("RightBound")
	return refs, hazardsFolder, refs.WaveStart, refs.WaveEnd, leftBound, rightBound
end

local function getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
	local lateral = getPlanarUnit(forward:Cross(Vector3.yAxis), startPart.CFrame.RightVector)
	local center = (startPart.Position + endPart.Position) * 0.5
	local width = 36

	if leftBound and rightBound then
		lateral = getPlanarUnit(rightBound.Position - leftBound.Position, lateral)
		center = (leftBound.Position + rightBound.Position) * 0.5
		width = math.max(6, math.abs((rightBound.Position - leftBound.Position):Dot(lateral)))
	end

	return forward, lateral, center, width
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

local function raycastGround(position, hazardsFolder)
	local height = math.max(10, tonumber(CONFIG.GroundProbeHeight) or 120)
	local depth = math.max(height + 10, tonumber(CONFIG.GroundProbeDepth) or 260)
	local result = Workspace:Raycast(
		position + Vector3.new(0, height, 0),
		Vector3.new(0, -depth, 0),
		buildGroundRaycastParams(hazardsFolder)
	)

	if result and result.Instance and result.Instance:IsA("BasePart") and not isUnsafeSpikeSurface(result.Instance) then
		return result.Position
	end

	return nil
end

local function getSpikeSize(corridorWidth)
	local laneCount = math.max(1, math.floor(tonumber(CONFIG.LaneCount) or 5))
	local laneWidth = math.max(4, corridorWidth / laneCount)
	local width = laneWidth * math.clamp(tonumber(CONFIG.LaneWidthScale) or 0.82, 0.25, 1)
	local length = math.max(4, tonumber(CONFIG.SpikeLength) or 18)
	local visualScale = math.max(0.01, tonumber(CONFIG.SpikeVisualScale) or 1)
	return Vector3.new(width * visualScale, CONFIG.SpikeHeight * visualScale, length * visualScale)
end

local function hasSafeGroundForFootprint(position, hazardsFolder, forward, lateral, size)
	local centerPosition = raycastGround(position, hazardsFolder)
	if not centerPosition then
		return nil
	end

	local forwardUnit = getPlanarUnit(forward, Vector3.zAxis)
	local lateralUnit = getPlanarUnit(lateral, Vector3.xAxis)
	local buffer = math.max(0, tonumber(CONFIG.SafeGapBuffer) or 0)
	local sampleX = math.max(1, (size.X * 0.5) + buffer)
	local sampleZ = math.max(1, (size.Z * 0.5) + buffer)
	local innerSampleX = math.max(1, size.X * 0.35)
	local innerSampleZ = math.max(1, size.Z * 0.35)
	local maxHeightDelta = math.max(0.5, tonumber(CONFIG.MaxGroundHeightDelta) or 3)
	local sampleOffsets = {
		Vector3.zero,
		forwardUnit * innerSampleZ,
		-forwardUnit * innerSampleZ,
		lateralUnit * innerSampleX,
		-lateralUnit * innerSampleX,
		forwardUnit * sampleZ,
		-forwardUnit * sampleZ,
		lateralUnit * sampleX,
		-lateralUnit * sampleX,
		lateralUnit * sampleX + forwardUnit * sampleZ,
		lateralUnit * -sampleX + forwardUnit * sampleZ,
		lateralUnit * sampleX + forwardUnit * -sampleZ,
		lateralUnit * -sampleX + forwardUnit * -sampleZ,
	}

	for _, offset in ipairs(sampleOffsets) do
		local samplePosition = raycastGround(position + offset, hazardsFolder)
		if not samplePosition or math.abs(samplePosition.Y - centerPosition.Y) > maxHeightDelta then
			return nil
		end
	end

	return centerPosition
end

local function getAreaNameForBiome(biomeIndex)
	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)
	local templateBiomeIndex = if CONFIG.ReverseBiomeTemplates == true
		then (biomeCount - normalizedBiome + 1)
		else normalizedBiome
	local entry = BiomeAreas.GetBiome and BiomeAreas.GetBiome(templateBiomeIndex)
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
				return folder
			end
		end
	end

	warnOnce("missing_spike_folder", "Could not find spike trap template folder.")
	return nil
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
	local folder = findSpikeTrapFolder()
	if not folder then
		return nil
	end

	local key = string.lower(tostring(areaName or ""))
	local namedTemplate = SPIKE_TEMPLATE_NAMES_BY_AREA[key]
	if namedTemplate then
		local template = folder:FindFirstChild(namedTemplate, true)
		if template and template:IsA("Model") then
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
				return candidate
			end
		end
	end

	for _, candidate in ipairs(candidates) do
		if findHitbox(candidate) or #getBaseParts(candidate) > 0 then
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

local function configureSpikeVisual(model, hitbox)
	for _, part in ipairs(getBaseParts(model)) do
		configurePart(part, part == hitbox, part == hitbox)
		if part == hitbox then
			part.Transparency = 1
			part:SetAttribute("HazardClass", CONFIG.HazardClass)
			part:SetAttribute("HazardType", CONFIG.HazardType)
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

local function chooseSpikePlacement(hazardsFolder, startPart, endPart, leftBound, rightBound, biomeIndex)
	local forward, lateral, corridorCenter, corridorWidth = getCorridorBasis(startPart, endPart, leftBound, rightBound)
	local pathLength = math.max(1, math.abs((endPart.Position - startPart.Position):Dot(forward)))
	local size = getSpikeSize(corridorWidth)
	local edgeBuffer = math.max(0, tonumber(CONFIG.SafeGapBuffer) or 0)
	local safeHalfWidth = math.max(0, (corridorWidth * 0.5) - (size.X * 0.5) - edgeBuffer)

	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local normalizedBiome = math.clamp(math.floor(tonumber(biomeIndex) or 1), 1, biomeCount)
	local biomeStartAlpha = (normalizedBiome - 1) / biomeCount
	local biomeEndAlpha = normalizedBiome / biomeCount
	local padding = math.clamp(tonumber(CONFIG.BiomePaddingAlpha) or 0.08, 0, 0.35)
	local startAlpha = math.max(CONFIG.MinimumForwardAlpha, biomeStartAlpha + ((biomeEndAlpha - biomeStartAlpha) * padding))
	local endAlpha = math.min(CONFIG.MaximumForwardAlpha, biomeEndAlpha - ((biomeEndAlpha - biomeStartAlpha) * padding))
	local attempts = math.max(1, math.floor(tonumber(CONFIG.SpawnAttempts) or 30))

	for _ = 1, attempts do
		local forwardAlpha = rng:NextNumber(startAlpha, math.max(startAlpha, endAlpha))
		local laneOffset = if safeHalfWidth > 0 then rng:NextNumber(-safeHalfWidth, safeHalfWidth) else 0

		local centerOnPath = startPart.Position + (forward * pathLength * forwardAlpha)
		local centerProjection = corridorCenter:Dot(lateral)
		local pathProjection = centerOnPath:Dot(lateral)
		local planarPosition = centerOnPath + (lateral * (centerProjection - pathProjection + laneOffset))
		local groundPosition = hasSafeGroundForFootprint(planarPosition, hazardsFolder, forward, lateral, size)
		if groundPosition then
			return {
				GroundPosition = groundPosition,
				Forward = forward,
				Lateral = lateral,
				Size = size,
				BiomeIndex = normalizedBiome,
			}
		end
	end

	return nil
end

local function makeController(model, hitbox, warning, visual, hiddenCFrame, extendedCFrame)
	local controller = {
		Model = model,
		Hitbox = hitbox,
		Warning = warning,
		Visual = visual,
		HiddenCFrame = hiddenCFrame,
		ExtendedCFrame = extendedCFrame,
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
	local template = CONFIG.UseSpikeTrapTemplates and findSpikeTrapTemplate(areaName) or nil
	if not template then
		return nil
	end

	local visual = template:Clone()
	visual.Name = "SpikeTrapVisual"
	visual.Parent = model
	visual:ScaleTo(math.max(0.01, tonumber(CONFIG.SpikeVisualScale) or 1))

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

	return spike, spike, hiddenCFrame, extendedCFrame
end

local function createDeckSpike(hazardsFolder, placement)
	local model = Instance.new("Model")
	model.Name = "DeckSpikes"
	model:SetAttribute("HazardClass", CONFIG.HazardClass)
	model:SetAttribute("HazardType", CONFIG.HazardType)

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
	end

	model.Parent = hazardsFolder
	return makeController(model, hitbox, warning, visual, hiddenCFrame, extendedCFrame)
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

	humanoid:TakeDamage(CONFIG.Damage)
	controller.DamagedPlayers[player] = true
	return true
end

local function damagePlayersInside(controller)
	for _, player in ipairs(Players:GetPlayers()) do
		damagePlayer(controller, player)
	end
end

local function runDeckSpike(controller)
	task.wait(CONFIG.WarningTime)
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
	while elapsed < CONFIG.HoldTime do
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

local function spawnDeckSpike(hazardsFolder, startPart, endPart, leftBound, rightBound, biomeIndex)
	if cleanupActiveControllers() >= CONFIG.MaxActiveSpikes then
		return false
	end

	local placement = chooseSpikePlacement(hazardsFolder, startPart, endPart, leftBound, rightBound, biomeIndex)
	if not placement then
		return false
	end

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
	local _, hazardsFolder, startPart, endPart, leftBound, rightBound = resolveRefs()
	if not hazardsFolder or not startPart or not endPart then
		return
	end

	local biomeCount = math.max(1, math.floor(tonumber(CONFIG.BiomeCount) or 8))
	local spikesPerPop = math.max(1, math.floor(tonumber(CONFIG.SpikesPerPop) or 1))
	for _ = 1, spikesPerPop do
		local biomeIndex = rng:NextInteger(1, biomeCount)
		local ok, err = xpcall(function()
			spawnDeckSpike(hazardsFolder, startPart, endPart, leftBound, rightBound, biomeIndex)
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
