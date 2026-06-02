local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ChestRushWorldVfx = {}

local LOCAL_FOLDER_NAME = "ChestRushLocalVfx"
local GOLD_TINT_NAME = "ChestRushGoldTint"
local BIOME_LIGHTING_GLOBAL_ATTRIBUTE = "BiomeLightingGlobal"
local POOL_SIZE = 10
local PLACEMENT_REFRESH_SECONDS = 1.35
local PLATFORM_SEARCH_RADIUS = 520
local PLAYER_FALLBACK_FORWARD_MIN = 80
local PLAYER_FALLBACK_FORWARD_MAX = 320
local PLAYER_FALLBACK_SIDE_MIN = 140
local PLAYER_FALLBACK_SIDE_MAX = 240
local ANCHOR_HEIGHT_MIN = 14
local ANCHOR_HEIGHT_MAX = 38
local PLATFORM_SIDE_INNER_RATIO = 0.8
local PLATFORM_SIDE_OUTER_RATIO = 0.97
local TINT_TWEEN_INFO = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TINT_TARGETS = {
	TintColor = Color3.fromRGB(255, 244, 214),
	Brightness = 0.01,
	Contrast = 0.02,
	Saturation = 0.03,
}
local TINT_REST = {
	TintColor = Color3.fromRGB(255, 255, 255),
	Brightness = 0,
	Contrast = 0,
	Saturation = 0,
}

local PARTICLE_TEXTURES = {
	Chest = "rbxassetid://132924303186890",
	Sparkle = "rbxassetid://95629190896984",
	Beli = "rbxassetid://110532904361640",
}

local active = false
local placementLoopRunning = false
local placementToken = 0
local localFolder = nil
local goldTint = nil
local tintTween = nil
local anchors = {}
local platformCache = nil
local platformCacheTime = 0

local function getLocalPlayerRootPart()
	local player = Players.LocalPlayer
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function getOrCreateFolder()
	if localFolder and localFolder.Parent then
		return localFolder
	end

	localFolder = Workspace:FindFirstChild(LOCAL_FOLDER_NAME)
	if localFolder and localFolder:IsA("Folder") then
		return localFolder
	end

	if localFolder then
		localFolder:Destroy()
	end

	localFolder = Instance.new("Folder")
	localFolder.Name = LOCAL_FOLDER_NAME
	localFolder.Parent = Workspace
	return localFolder
end

local function configureEmitter(emitter, texture, rate, size, lifetime, speed)
	emitter.Texture = texture
	emitter.Rate = rate
	emitter.Lifetime = lifetime
	emitter.Speed = speed
	emitter.SpreadAngle = Vector2.new(18, 18)
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Acceleration = Vector3.new(0, 2.5, 0)
	emitter.Drag = 0.8
	emitter.LightEmission = 0.35
	emitter.LightInfluence = 0.35
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.Rotation = NumberRange.new(-18, 18)
	emitter.RotSpeed = NumberRange.new(-24, 24)
	emitter.Size = size
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.12, 0.22),
		NumberSequenceKeypoint.new(0.72, 0.42),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Enabled = false
end

local function createAnchor(index)
	local folder = getOrCreateFolder()

	local part = Instance.new("Part")
	part.Name = string.format("ChestRushVfxAnchor_%02d", index)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Transparency = 1
	part.Parent = folder

	local attachment = Instance.new("Attachment")
	attachment.Name = "ChestRushVfxAttachment"
	attachment.Parent = part

	local chestEmitter = Instance.new("ParticleEmitter")
	chestEmitter.Name = "ChestParticles"
	configureEmitter(
		chestEmitter,
		PARTICLE_TEXTURES.Chest,
		4.2,
		NumberSequence.new(2.8, 4),
		NumberRange.new(1.6, 2.4),
		NumberRange.new(7, 11)
	)
	chestEmitter.Parent = attachment

	local sparkleEmitter = Instance.new("ParticleEmitter")
	sparkleEmitter.Name = "SparkleParticles"
	configureEmitter(
		sparkleEmitter,
		PARTICLE_TEXTURES.Sparkle,
		1.1,
		NumberSequence.new(1.4, 2.4),
		NumberRange.new(1.3, 2),
		NumberRange.new(8, 13)
	)
	sparkleEmitter.Parent = attachment

	local beliEmitter = Instance.new("ParticleEmitter")
	beliEmitter.Name = "BeliParticles"
	configureEmitter(
		beliEmitter,
		PARTICLE_TEXTURES.Beli,
		0.7,
		NumberSequence.new(1.2, 2),
		NumberRange.new(1.4, 2.2),
		NumberRange.new(7, 11)
	)
	beliEmitter.Parent = attachment

	return {
		Part = part,
		Emitters = {
			chestEmitter,
			sparkleEmitter,
			beliEmitter,
		},
	}
end

local function ensureAnchors()
	for index = #anchors + 1, POOL_SIZE do
		anchors[index] = createAnchor(index)
	end
end

local function setEmittersEnabled(enabled)
	for _, anchor in ipairs(anchors) do
		for _, emitter in ipairs(anchor.Emitters) do
			emitter.Enabled = enabled
		end
	end
end

local function findBiomesRoot()
	local map = Workspace:FindFirstChild("Map")
	local mainMap = map and map:FindFirstChild("Main Map")
	return mainMap and mainMap:FindFirstChild("Biomes")
end

local function refreshPlatformCache()
	local now = os.clock()
	if platformCache and now - platformCacheTime < 5 then
		return platformCache
	end

	local platforms = {}
	local biomesRoot = findBiomesRoot()
	if biomesRoot then
		for _, descendant in ipairs(biomesRoot:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name == "Platform" then
				platforms[#platforms + 1] = descendant
			end
		end
	end

	platformCache = platforms
	platformCacheTime = now
	return platformCache
end

local function getNearbyPlatforms(rootPart)
	local platforms = refreshPlatformCache()
	local nearby = {}
	local rootPosition = rootPart.Position

	for _, platform in ipairs(platforms) do
		if platform.Parent and (platform.Position - rootPosition).Magnitude <= PLATFORM_SEARCH_RADIUS then
			nearby[#nearby + 1] = platform
		end
	end

	return nearby
end

local function getPlatformPosition(platform, rootPart)
	local halfX = math.max(8, platform.Size.X * 0.5 - 12)
	local halfZ = math.max(8, platform.Size.Z * 0.5 - 12)
	local rootLocalPosition = platform.CFrame:PointToObjectSpace(rootPart.Position)
	local localXCenter = math.clamp(rootLocalPosition.X, -halfX, halfX)
	local localXSpread = math.min(halfX, 90)
	local localX = math.clamp(
		localXCenter + math.random(-math.floor(localXSpread), math.floor(localXSpread)),
		-halfX,
		halfX
	)
	local side = if math.random(1, 2) == 1 then -1 else 1
	local innerZ = math.max(8, math.floor(halfZ * PLATFORM_SIDE_INNER_RATIO))
	local outerZ = math.max(innerZ, math.floor(halfZ * PLATFORM_SIDE_OUTER_RATIO))
	local localZ = side * math.random(innerZ, outerZ)
	local localY = platform.Size.Y * 0.5 + math.random(ANCHOR_HEIGHT_MIN, ANCHOR_HEIGHT_MAX)
	return platform.CFrame:PointToWorldSpace(Vector3.new(localX, localY, localZ))
end

local function getFallbackPosition(rootPart)
	local forwardDistance = math.random(PLAYER_FALLBACK_FORWARD_MIN, PLAYER_FALLBACK_FORWARD_MAX)
	local side = if math.random(1, 2) == 1 then -1 else 1
	local sideOffset = side * math.random(PLAYER_FALLBACK_SIDE_MIN, PLAYER_FALLBACK_SIDE_MAX)
	local height = math.random(ANCHOR_HEIGHT_MIN, ANCHOR_HEIGHT_MAX)
	local rootCFrame = rootPart.CFrame
	return rootPart.Position
		+ rootCFrame.LookVector * forwardDistance
		+ rootCFrame.RightVector * sideOffset
		+ Vector3.new(0, height, 0)
end

local function repositionAnchors()
	local rootPart = getLocalPlayerRootPart()
	if not rootPart then
		return
	end

	local nearbyPlatforms = getNearbyPlatforms(rootPart)
	for _, anchor in ipairs(anchors) do
		local position
		if #nearbyPlatforms > 0 then
			position = getPlatformPosition(nearbyPlatforms[math.random(1, #nearbyPlatforms)], rootPart)
		else
			position = getFallbackPosition(rootPart)
		end
		anchor.Part.CFrame = CFrame.new(position)
	end
end

local function startPlacementLoop()
	if placementLoopRunning then
		return
	end

	placementToken += 1
	local thisToken = placementToken
	placementLoopRunning = true

	task.spawn(function()
		while active and thisToken == placementToken do
			repositionAnchors()
			task.wait(PLACEMENT_REFRESH_SECONDS)
		end

		if thisToken == placementToken then
			placementLoopRunning = false
		end
	end)
end

local function getOrCreateGoldTint()
	if goldTint and goldTint.Parent then
		return goldTint
	end

	goldTint = Lighting:FindFirstChild(GOLD_TINT_NAME)
	if goldTint and goldTint:IsA("ColorCorrectionEffect") then
		return goldTint
	end

	if goldTint then
		goldTint:Destroy()
	end

	goldTint = Instance.new("ColorCorrectionEffect")
	goldTint.Name = GOLD_TINT_NAME
	goldTint.Enabled = false
	goldTint:SetAttribute(BIOME_LIGHTING_GLOBAL_ATTRIBUTE, true)
	goldTint.Parent = Lighting
	return goldTint
end

local function playTintTween(targets)
	local tint = getOrCreateGoldTint()
	tint:SetAttribute(BIOME_LIGHTING_GLOBAL_ATTRIBUTE, true)

	if tintTween then
		tintTween:Cancel()
		tintTween = nil
	end

	tint.Enabled = true
	tintTween = TweenService:Create(tint, TINT_TWEEN_INFO, targets)
	local thisTween = tintTween
	tintTween.Completed:Connect(function()
		if tintTween == thisTween and targets == TINT_REST then
			tint.Enabled = false
		end
	end)
	tintTween:Play()
end

local function applyGoldTint()
	local tint = getOrCreateGoldTint()
	tint.TintColor = TINT_REST.TintColor
	tint.Brightness = TINT_REST.Brightness
	tint.Contrast = TINT_REST.Contrast
	tint.Saturation = TINT_REST.Saturation
	playTintTween(TINT_TARGETS)
end

local function removeGoldTint()
	if not goldTint or not goldTint.Parent then
		return
	end

	playTintTween(TINT_REST)
end

function ChestRushWorldVfx.Start()
	if active then
		return
	end

	active = true
	getOrCreateFolder()
	ensureAnchors()
	repositionAnchors()
	setEmittersEnabled(true)
	startPlacementLoop()
	applyGoldTint()
end

function ChestRushWorldVfx.Stop()
	if not active then
		removeGoldTint()
		return
	end

	active = false
	placementToken += 1
	placementLoopRunning = false
	setEmittersEnabled(false)
	removeGoldTint()
end

function ChestRushWorldVfx.Destroy()
	ChestRushWorldVfx.Stop()

	if tintTween then
		tintTween:Cancel()
		tintTween = nil
	end

	if goldTint and goldTint.Parent then
		goldTint:Destroy()
	end
	goldTint = nil

	if localFolder and localFolder.Parent then
		localFolder:Destroy()
	end
	localFolder = nil
	table.clear(anchors)
	platformCache = nil
end

return ChestRushWorldVfx
