local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local BiomeAreas = require(Configs:WaitForChild("BiomeAreas"))
local StudioAssetResolver = require(Modules:WaitForChild("StudioAssetResolver"))
local HazardDebugConstants = require(Modules:WaitForChild("Debug"):WaitForChild("HazardDebugConstants"))
local GameSounds = require(Modules:WaitForChild("GameSounds"))
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
local HitEffectService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("HitEffectService"))

local CONFIG = {
	Enabled = true,
	InterShotDelay = 0.15,
	DropHeight = 180,
	FallTime = 0.65,
	ImpactDebugLinger = 0.2,
	MaxActiveBombs = 12,
	MaxActiveBombsPerPlayer = 3,
	HazardClass = "major",
	HazardType = "CannonBarrage",
	BombSize = 6,
	CircleHeight = 0.18,
	GroundRayHeight = 6,
	GroundRayDepth = 14,
	VerticalDamageTolerance = 12,
	BountyCheckDelay = 1,
	TargetCheckDelay = 0.2,
	MinCannonInterval = 1,
	IntervalJitterMin = -0.35,
	IntervalJitterMax = 0.65,
	KnockdownDuration = 0.8,
	KnockdownPriority = 30,
	RagdollImpulseHorizontal = 55,
	RagdollImpulseVertical = 18,
	ImpactVfxLifetime = 3,
	ImpactVfxScale = 3,
	DefaultVfxEmitCount = 30,
	DefaultImpactRadius = 18,
	DefaultDamage = 65,
	DefaultWarningTime = 0.75,
	DefaultVfxName = "canon explosion",

	-- Bounty balance knobs:
	-- Interval = nil means this bounty tier is not targeted by cannon barrage.
	-- Lower Interval values make cannons attack more often.
	-- Bounty controls cannon frequency only, not damage.
	-- Biome bands below still control cannon severity.
	CannonBountyTiers = {
		{ Tier = 0, MinBounty = 0, Interval = nil },
		{ Tier = 1, MinBounty = 1, Interval = 10 },
		{ Tier = 2, MinBounty = 10000, Interval = 7 },
		{ Tier = 3, MinBounty = 75000, Interval = 5 },
		{ Tier = 4, MinBounty = 500000, Interval = 3 },
	},

	-- Cannon balance knobs:
	-- Higher ShotsPerCycle values add more drops per targeting cycle.
	-- Lower WarningTime values make cannon impacts harder to dodge.
	-- Higher ImpactRadius values make the damage circle larger.
	-- Higher DamageRange values make cannon impacts hit harder.
	CannonBarrageBands = {
		{
			Band = 1,
			BiomeStart = 1,
			BiomeEnd = 2,
			ShotsPerCycle = { Min = 1, Max = 1 },
			WarningTime = 0.9,
			ImpactRadius = 16,
			DamageRange = { Min = 45, Max = 55 },
		},
		{
			Band = 2,
			BiomeStart = 3,
			BiomeEnd = 4,
			ShotsPerCycle = { Min = 1, Max = 2 },
			WarningTime = 0.8,
			ImpactRadius = 17,
			DamageRange = { Min = 55, Max = 65 },
		},
		{
			Band = 3,
			BiomeStart = 5,
			BiomeEnd = 6,
			ShotsPerCycle = { Min = 2, Max = 2 },
			WarningTime = 0.7,
			ImpactRadius = 18,
			DamageRange = { Min = 65, Max = 75 },
		},
		{
			Band = 4,
			BiomeStart = 7,
			BiomeEnd = 8,
			ShotsPerCycle = { Min = 2, Max = 3 },
			WarningTime = 0.6,
			ImpactRadius = 20,
			DamageRange = { Min = 75, Max = 85 },
		},
	},
	VfxNameByBiome = {
		[1] = "canon explosion",
		[2] = "water explosion",
		[3] = "ice  explosion",
		[4] = "canon explosion",
		[5] = "water explosion",
		[6] = "ice  explosion",
		[7] = "water explosion",
		[8] = "canon explosion",
	},
	SafeGapBuffer = 12,
	SafeFloorNameKeywords = {
		"gap",
		"safe",
		"safezone",
		"refuge",
		"hub",
		"lobby",
	},
}

if not CONFIG.Enabled then
	return
end

local BIOME_FOLDER_PATTERN = "^Biome%s*(%d+)$"
local biomeBoundsCacheRoot = nil
local biomeBoundsCache = nil
local carriedGroundFilterCacheRoot = nil
local carriedGroundFilterCacheWaveFolder = nil
local carriedGroundFilterCache = nil
local carriedGroundFilterCacheComplete = false
local warningKeys = {}
local activeBombCount = 0
local activeBombCountByUserId = {}
local rng = Random.new()

local VFX_NAME_ALIASES = {
	["cannon"] = "canon explosion",
	["cannon explosion"] = "canon explosion",
	["canon"] = "canon explosion",
	["ice"] = "ice  explosion",
	["ice explosion"] = "ice  explosion",
}

local function warnOnce(key, message, ...)
	if warningKeys[key] then
		return
	end

	warningKeys[key] = true
	warn(string.format(message, ...))
end

local function readNumberValue(instance)
	if instance and (instance:IsA("NumberValue") or instance:IsA("IntValue")) then
		return tonumber(instance.Value)
	end

	return nil
end

local function readChildNumber(parent, childName)
	local child = parent and parent:FindFirstChild(childName)
	return readNumberValue(child)
end

local function getPlayerBounty(player)
	if not player then
		return 0
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local leaderstatBounty = readChildNumber(leaderstats, "Bounty")
	if leaderstatBounty ~= nil then
		return math.max(0, math.floor(leaderstatBounty + 0.5))
	end

	local bountyFolder = player:FindFirstChild("Bounty")
	local totalBounty = readChildNumber(bountyFolder, "Total")
	if totalBounty ~= nil then
		return math.max(0, math.floor(totalBounty + 0.5))
	end

	return math.max(0, math.floor((tonumber(player:GetAttribute("Bounty")) or 0) + 0.5))
end

local function getCannonBountyTier(bounty)
	local normalizedBounty = math.max(0, math.floor((tonumber(bounty) or 0) + 0.5))
	local selectedTier = nil
	local selectedIndex = 0

	for index, tier in ipairs(CONFIG.CannonBountyTiers) do
		local minBounty = math.max(0, math.floor(tonumber(tier.MinBounty) or 0))
		if normalizedBounty >= minBounty then
			selectedTier = tier
			selectedIndex = index
		end
	end

	if selectedTier == nil then
		selectedTier = CONFIG.CannonBountyTiers[1]
		selectedIndex = 1
	end

	return selectedTier, math.floor(tonumber(selectedTier and selectedTier.Tier) or math.max(0, selectedIndex - 1))
end

local function getCannonIntervalForBounty(bounty)
	local tier, tierId = getCannonBountyTier(bounty)
	local interval = tier and tonumber(tier.Interval) or nil
	if not interval or interval <= 0 then
		return nil, tier, tierId
	end

	return math.max(tonumber(CONFIG.MinCannonInterval) or 1, interval), tier, tierId
end

local function getCannonIntervalJitter()
	local minJitter = tonumber(CONFIG.IntervalJitterMin) or 0
	local maxJitter = tonumber(CONFIG.IntervalJitterMax) or minJitter
	if maxJitter < minJitter then
		minJitter, maxJitter = maxJitter, minJitter
	end

	if math.abs(maxJitter - minJitter) <= 1e-4 then
		return minJitter
	end

	return rng:NextNumber(minJitter, maxJitter)
end

local function normalizeBiomeIndex(biomeIndex)
	local index = math.floor(tonumber(biomeIndex) or 0)
	if index < 1 then
		return nil
	end

	return index
end

local function getAreaNameForBiome(biomeIndex)
	local entry = BiomeAreas.GetBiome and BiomeAreas.GetBiome(normalizeBiomeIndex(biomeIndex))
	return entry and entry.AreaName or string.format("Biome %s", tostring(biomeIndex or "?"))
end

local function rollIntegerRange(range, fallback)
	if type(range) ~= "table" then
		return math.max(0, math.floor(tonumber(fallback) or 0))
	end

	local minValue = math.floor(tonumber(range.Min) or tonumber(range[1]) or tonumber(fallback) or 0)
	local maxValue = math.floor(tonumber(range.Max) or tonumber(range[2]) or minValue)
	if maxValue < minValue then
		minValue, maxValue = maxValue, minValue
	end

	return rng:NextInteger(minValue, maxValue)
end

local function rollNumberRange(range, fallback)
	if type(range) ~= "table" then
		return tonumber(fallback) or 0
	end

	local minValue = tonumber(range.Min) or tonumber(range[1]) or tonumber(fallback) or 0
	local maxValue = tonumber(range.Max) or tonumber(range[2]) or minValue
	if maxValue < minValue then
		minValue, maxValue = maxValue, minValue
	end

	if math.abs(maxValue - minValue) <= 1e-4 then
		return minValue
	end

	return rng:NextNumber(minValue, maxValue)
end

local function getCannonTuningForBiome(biomeIndex)
	local normalizedBiome = normalizeBiomeIndex(biomeIndex) or 1
	for _, tuning in ipairs(CONFIG.CannonBarrageBands) do
		local biomeStart = math.floor(tonumber(tuning.BiomeStart) or 1)
		local biomeEnd = math.floor(tonumber(tuning.BiomeEnd) or biomeStart)
		if normalizedBiome >= biomeStart and normalizedBiome <= biomeEnd then
			return tuning
		end
	end

	return CONFIG.CannonBarrageBands[1]
end

local function rollShotsPerCycle(tuning)
	return math.max(0, rollIntegerRange(tuning and tuning.ShotsPerCycle, 1))
end

local function rollCannonDamage(tuning)
	return math.max(0, rollNumberRange(tuning and tuning.DamageRange, CONFIG.DefaultDamage))
end

local function resolveCannonVfxName(tuning, biomeIndex)
	local configuredName = CONFIG.VfxNameByBiome[normalizeBiomeIndex(biomeIndex) or 0]
		or (tuning and tuning.VfxName)
		or CONFIG.DefaultVfxName
	local lowerName = string.lower(tostring(configuredName or ""))
	return VFX_NAME_ALIASES[lowerName] or configuredName
end

local function markHazardHitboxPart(part, radius)
	if not part or not part:IsA("BasePart") then
		return
	end

	CollectionService:AddTag(part, HazardDebugConstants.HitboxTag)
	part:SetAttribute(HazardDebugConstants.DebugHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardClassAttribute, CONFIG.HazardClass)
	part:SetAttribute(HazardDebugConstants.HazardTypeAttribute, CONFIG.HazardType)
	part:SetAttribute("HazardHitboxShape", "Cylinder")
	part:SetAttribute("HazardHitboxRadius", math.max(0, tonumber(radius) or CONFIG.DefaultImpactRadius))
end

local hazardsFolder = Workspace:FindFirstChild("CannonBarrages")
if not hazardsFolder then
	hazardsFolder = Instance.new("Folder")
	hazardsFolder.Name = "CannonBarrages"
	hazardsFolder.Parent = Workspace
end

local activeLoopsByPlayer = {}
local cachedCannonVfxRoot = false

StudioAssetResolver.ResolveAsset("CannonVfx", {
	Context = "CannonBarrage",
	WarnIfMissing = true,
})

local function getCharacterParts(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not character or not humanoid or humanoid.Health <= 0 or not rootPart then
		return nil
	end

	return character, humanoid, rootPart
end

local function addUniqueInstance(instances, seen, instance)
	if not instance or seen[instance] then
		return
	end

	seen[instance] = true
	instances[#instances + 1] = instance
end

local function getCarriedGroundRaycastContainers(refs)
	refs = refs or MapResolver.GetRefs()
	local mapRoot = refs and refs.MapRoot
	local waveFolder = refs and refs.WaveFolder

	if
		carriedGroundFilterCache
		and carriedGroundFilterCacheRoot == mapRoot
		and carriedGroundFilterCacheWaveFolder == waveFolder
		and carriedGroundFilterCacheComplete
	then
		local allCachedContainersStillExist = true
		for _, container in ipairs(carriedGroundFilterCache) do
			if not container.Parent then
				allCachedContainersStillExist = false
				break
			end
		end

		if allCachedContainersStillExist then
			return carriedGroundFilterCache
		end
	end

	local containers = {}
	local seen = {}
	local complete = true

	local grandLineRushFolder = refs and refs.GrandLineRushFolder
	if not grandLineRushFolder and waveFolder then
		grandLineRushFolder = waveFolder:FindFirstChild("GrandLineRush")
	end

	local carriedRewardsFolder = grandLineRushFolder and grandLineRushFolder:FindFirstChild("CarriedRewards")
	if carriedRewardsFolder then
		addUniqueInstance(containers, seen, carriedRewardsFolder)
	else
		complete = false
	end

	local crewMembersWorld = mapRoot and mapRoot:FindFirstChild("CrewMembersWorld")
	local carriedCrewFolder = crewMembersWorld and crewMembersWorld:FindFirstChild("Carried")
	if carriedCrewFolder then
		addUniqueInstance(containers, seen, carriedCrewFolder)
	else
		complete = false
	end

	carriedGroundFilterCacheRoot = mapRoot
	carriedGroundFilterCacheWaveFolder = waveFolder
	carriedGroundFilterCache = containers
	carriedGroundFilterCacheComplete = complete
	return containers
end

local function buildGroundRaycastFilter(character, refs)
	local filter = { hazardsFolder }
	if character then
		filter[#filter + 1] = character
	end

	-- Held rewards are parented outside the character, so exclude their containers explicitly.
	for _, container in ipairs(getCarriedGroundRaycastContainers(refs)) do
		filter[#filter + 1] = container
	end

	return filter
end

local function getPlanarUnit(vector, fallback)
	local planar = Vector3.new(vector.X, 0, vector.Z)
	if planar.Magnitude > 0.001 then
		return planar.Unit
	end

	local fallbackPlanar = Vector3.new(fallback.X, 0, fallback.Z)
	if fallbackPlanar.Magnitude > 0.001 then
		return fallbackPlanar.Unit
	end

	return Vector3.zAxis
end

local function isInsideRunZone(position, refs)
	refs = refs or MapResolver.GetRefs()
	local waveFolder = refs.WaveFolder
	local startPart = refs.WaveStart
	local endPart = refs.WaveEnd

	if not waveFolder or not startPart or not endPart then
		return false
	end

	local leftBound = waveFolder:FindFirstChild("LeftBound")
	local rightBound = waveFolder:FindFirstChild("RightBound")
	local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
	local runLength = math.max(1, math.abs((endPart.Position - startPart.Position):Dot(forward)))
	local forwardDistance = (position - startPart.Position):Dot(forward)

	if forwardDistance < 0 or forwardDistance > runLength then
		return false
	end

	if leftBound and rightBound then
		local lateral = getPlanarUnit(rightBound.Position - leftBound.Position, startPart.CFrame.RightVector)
		local center = (leftBound.Position + rightBound.Position) * 0.5
		local halfWidth = math.max(1, math.abs((rightBound.Position - leftBound.Position):Dot(lateral)) * 0.5)
		local lateralDistance = math.abs((position - center):Dot(lateral))

		if lateralDistance > halfWidth then
			return false
		end
	end

	return true
end

local function getBiomeIndexFromName(name)
	local indexText = tostring(name or ""):match(BIOME_FOLDER_PATTERN)
	return indexText and tonumber(indexText) or nil
end

local function getBiomeIndexFromInstance(instance)
	local current = instance
	while current and current ~= Workspace do
		local biomeIndex = getBiomeIndexFromName(current.Name)
		if biomeIndex then
			return biomeIndex, current
		end

		current = current.Parent
	end

	return nil, nil
end

local function buildBiomeBoundsCache(refs)
	local biomesRoot = refs and refs.Biomes
	if not biomesRoot then
		return {}
	end

	if biomeBoundsCacheRoot == biomesRoot and biomeBoundsCache then
		return biomeBoundsCache
	end

	local entries = {}
	for _, biomeFolder in ipairs(biomesRoot:GetChildren()) do
		local biomeIndex = getBiomeIndexFromName(biomeFolder.Name)
		if biomeIndex then
			local root = biomeFolder:FindFirstChild(biomeFolder.Name) or biomeFolder
			for _, descendant in ipairs(root:GetDescendants()) do
				if descendant:IsA("BasePart") and descendant.CanQuery ~= false then
					entries[#entries + 1] = {
						BiomeIndex = biomeIndex,
						Root = root,
						Part = descendant,
					}
				end
			end
		end
	end

	biomeBoundsCacheRoot = biomesRoot
	biomeBoundsCache = entries
	return entries
end

local function isPositionInsidePartFootprint(part, position)
	if not (part and part:IsA("BasePart") and typeof(position) == "Vector3") then
		return false
	end

	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5
	local heightTolerance = math.max(8, CONFIG.GroundRayHeight + CONFIG.GroundRayDepth)
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Z) <= halfSize.Z
		and math.abs(localPosition.Y) <= halfSize.Y + heightTolerance
end

local function resolveBiomeIndexFromPosition(position, refs)
	refs = refs or MapResolver.GetRefs()
	for _, entry in ipairs(buildBiomeBoundsCache(refs)) do
		if isPositionInsidePartFootprint(entry.Part, position) then
			return entry.BiomeIndex, entry.Root
		end
	end

	return nil, nil
end

local function hasKeywordInAncestry(instance, keywords)
	local current = instance
	while current and current ~= Workspace do
		local loweredName = string.lower(current.Name)
		for _, keyword in ipairs(keywords) do
			if loweredName:find(keyword, 1, true) then
				return true
			end
		end

		current = current.Parent
	end

	return false
end

local function isSafeGapFloor(part)
	if not part then
		return true
	end

	if part:GetAttribute("BombSafe") == true or part:GetAttribute("SafeZone") == true or part:GetAttribute("IsSafeZone") == true then
		return true
	end

	return hasKeywordInAncestry(part, CONFIG.SafeFloorNameKeywords)
end

local function getGroundHit(position, character, refs)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = buildGroundRaycastFilter(character, refs)

	local origin = position + Vector3.new(0, CONFIG.GroundRayHeight, 0)
	local direction = Vector3.new(0, -(CONFIG.GroundRayHeight + CONFIG.GroundRayDepth), 0)
	local result = Workspace:Raycast(origin, direction, raycastParams)

	if not result or not result.Instance or not result.Instance:IsA("BasePart") then
		return nil
	end

	if result.Instance.CanCollide ~= true or result.Normal.Y < 0.65 then
		return nil
	end

	if isSafeGapFloor(result.Instance) then
		return nil
	end

	return result
end

local function isNearSafeGap(position, character, refs)
	refs = refs or MapResolver.GetRefs()
	local startPart = refs.WaveStart
	local endPart = refs.WaveEnd
	if not startPart or not endPart then
		return true
	end

	local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
	for _, offset in ipairs({
		forward * CONFIG.SafeGapBuffer,
		-forward * CONFIG.SafeGapBuffer,
		Vector3.zero,
	}) do
		if not getGroundHit(position + offset, character, refs) then
			return true
		end
	end

	return false
end

local function getPlayerBombTarget(player)
	local character, humanoid, rootPart = getCharacterParts(player)
	if not character then
		return nil
	end
	local refs = MapResolver.GetRefs()

	if humanoid.FloorMaterial == Enum.Material.Air then
		return nil
	end

	if not isInsideRunZone(rootPart.Position, refs) then
		return nil
	end

	if isNearSafeGap(rootPart.Position, character, refs) then
		return nil
	end

	local groundHit = getGroundHit(rootPart.Position, character, refs)
	local groundPosition = groundHit and groundHit.Position
	if not groundPosition or not isInsideRunZone(groundPosition, refs) then
		return nil
	end

	local biomeIndex, biomeRoot = getBiomeIndexFromInstance(groundHit.Instance)
	if not biomeIndex then
		biomeIndex, biomeRoot = resolveBiomeIndexFromPosition(groundPosition, refs)
	end

	if not biomeIndex then
		warnOnce(
			string.format("missing_biome:%s", tostring(groundHit.Instance and groundHit.Instance:GetFullName())),
			"[CannonBarrage] skipped target player=%s reason=missing_biome ground=%s position=%s",
			player.Name,
			groundHit.Instance and groundHit.Instance:GetFullName() or "<nil>",
			tostring(groundPosition)
		)
		return nil
	end

	return {
		Position = groundPosition,
		GroundPart = groundHit.Instance,
		BiomeIndex = biomeIndex,
		BiomeRoot = biomeRoot,
		AreaName = getAreaNameForBiome(biomeIndex),
		TargetSource = "PlayerGroundBiome",
		TargetPlayer = player,
	}
end

local function setCannonDebugAttributes(instance, shot)
	if not instance or type(shot) ~= "table" then
		return
	end

	instance:SetAttribute("HazardClass", CONFIG.HazardClass)
	instance:SetAttribute("HazardType", CONFIG.HazardType)
	instance:SetAttribute("BiomeIndex", shot.BiomeIndex)
	instance:SetAttribute("AreaName", tostring(shot.AreaName or ""))
	instance:SetAttribute("CannonBand", shot.Band)
	instance:SetAttribute("WarningTime", shot.WarningTime)
	instance:SetAttribute("ImpactRadius", shot.ImpactRadius)
	instance:SetAttribute("Damage", shot.Damage)
	instance:SetAttribute("VfxName", tostring(shot.VfxName or ""))
	instance:SetAttribute("TargetPlayer", tostring(shot.TargetPlayerName or ""))
	instance:SetAttribute("TargetUserId", shot.TargetUserId)
	instance:SetAttribute("TargetSource", tostring(shot.TargetSource or ""))
	instance:SetAttribute("ShotIndex", shot.ShotIndex)
	instance:SetAttribute("ShotsPerCycle", shot.ShotsPerCycle)
	instance:SetAttribute("Bounty", shot.Bounty)
	instance:SetAttribute("CannonBountyTier", shot.CannonBountyTier)
	instance:SetAttribute("CannonInterval", shot.CannonInterval)
	instance:SetAttribute("CannonIntervalBase", shot.CannonIntervalBase)
	instance:SetAttribute("CannonIntervalJitter", shot.CannonIntervalJitter)
	instance:SetAttribute("RagdollImpulseHorizontal", shot.RagdollImpulseHorizontal)
	instance:SetAttribute("RagdollImpulseVertical", shot.RagdollImpulseVertical)
	if shot.GroundPart then
		instance:SetAttribute("GroundPartPath", shot.GroundPart:GetFullName())
	end
	if shot.BiomeRoot then
		instance:SetAttribute("BiomeRootPath", shot.BiomeRoot:GetFullName())
	end
end

local function makeImpactCircle(position, shot)
	local radius = math.max(0.1, tonumber(shot and shot.ImpactRadius) or CONFIG.DefaultImpactRadius)
	local circle = Instance.new("Part")
	circle.Name = "BombTargetCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(CONFIG.CircleHeight, radius * 2, radius * 2)
	circle.CFrame = CFrame.new(position + Vector3.new(0, CONFIG.CircleHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	circle.Anchored = true
	circle.CanCollide = false
	circle.CanTouch = false
	circle.CanQuery = false
	circle.Material = Enum.Material.Neon
	circle.Color = Color3.fromRGB(255, 35, 25)
	circle.Transparency = 0.35
	markHazardHitboxPart(circle, radius)
	setCannonDebugAttributes(circle, shot)
	circle.Parent = hazardsFolder

	return circle
end

local function makeBomb(position, shot)
	local bomb = Instance.new("Part")
	bomb.Name = "SkyBomb"
	bomb.Shape = Enum.PartType.Ball
	bomb.Size = Vector3.new(CONFIG.BombSize, CONFIG.BombSize, CONFIG.BombSize)
	bomb.CFrame = CFrame.new(position)
	bomb.Anchored = true
	bomb.CanCollide = false
	bomb.CanTouch = false
	bomb.CanQuery = false
	bomb.Material = Enum.Material.Metal
	bomb.Color = Color3.fromRGB(18, 18, 20)
	setCannonDebugAttributes(bomb, shot)
	bomb.Parent = hazardsFolder

	return bomb
end

local function getCannonVfxRoot()
	if cachedCannonVfxRoot ~= false then
		return cachedCannonVfxRoot
	end

	cachedCannonVfxRoot = StudioAssetResolver.ResolveAsset("CannonVfx", {
		Context = "CannonBarrage",
		WarnIfMissing = false,
	})
	return cachedCannonVfxRoot
end

local function findDescendantByLowerName(root, lowerName)
	if not root then
		return nil
	end

	if string.lower(root.Name) == lowerName then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if string.lower(descendant.Name) == lowerName then
			return descendant
		end
	end

	return nil
end

local function normalizeAssetName(name)
	return string.lower(tostring(name or "")):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function findDescendantByNormalizedName(root, name)
	if not root then
		return nil
	end

	local normalizedName = normalizeAssetName(name)
	if normalizeAssetName(root.Name) == normalizedName then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if normalizeAssetName(descendant.Name) == normalizedName then
			return descendant
		end
	end

	return nil
end

local function getImpactVfxTemplate(vfxName)
	local root = getCannonVfxRoot()
	if not root then
		return nil
	end

	local configuredName = tostring(vfxName or CONFIG.DefaultVfxName)
	local aliasName = VFX_NAME_ALIASES[normalizeAssetName(configuredName)] or configuredName
	for _, candidateName in ipairs({ configuredName, aliasName }) do
		local template = findDescendantByLowerName(root, string.lower(candidateName))
			or findDescendantByNormalizedName(root, candidateName)
		if template then
			return template
		end
	end

	warnOnce(
		string.format("missing_vfx:%s", normalizeAssetName(configuredName)),
		"[CannonBarrage] VFX template missing name=%s resolved=%s; falling back to canon explosion.",
		configuredName,
		tostring(aliasName)
	)

	return findDescendantByLowerName(root, "canon explosion")
		or findDescendantByNormalizedName(root, "canon explosion")
		or root
end

local function configureVfxInstance(instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		instance.CanTouch = false
		instance.CanQuery = false
		instance.AssemblyLinearVelocity = Vector3.zero
		instance.AssemblyAngularVelocity = Vector3.zero
	end
end

local function scaleNumberSequence(sequence, scale)
	local keypoints = {}
	for _, keypoint in ipairs(sequence.Keypoints) do
		table.insert(keypoints, NumberSequenceKeypoint.new(keypoint.Time, keypoint.Value * scale, keypoint.Envelope * scale))
	end

	return NumberSequence.new(keypoints)
end

local function scaleVfxItem(item, scale)
	if scale == 1 then
		return
	end

	if item:IsA("ParticleEmitter") then
		item.Size = scaleNumberSequence(item.Size, scale)
	elseif item:IsA("Beam") then
		item.Width0 *= scale
		item.Width1 *= scale
	elseif item:IsA("Trail") then
		item.WidthScale = scaleNumberSequence(item.WidthScale, scale)
	end
end

local function scaleVfxClone(clone, scale)
	if scale == 1 then
		return
	end

	if clone:IsA("Model") then
		clone:ScaleTo(scale)
	elseif clone:IsA("BasePart") then
		clone.Size *= scale
	end

	scaleVfxItem(clone, scale)
	for _, item in ipairs(clone:GetDescendants()) do
		if not clone:IsA("Model") and item:IsA("BasePart") then
			item.Size *= scale
		end
		scaleVfxItem(item, scale)
	end
end

local function placeVfxClone(clone, position)
	if clone:IsA("Model") then
		clone:PivotTo(CFrame.new(position))
	elseif clone:IsA("BasePart") then
		clone.CFrame = CFrame.new(position)
	elseif clone:IsA("Attachment") then
		local anchor = Instance.new("Part")
		anchor.Name = "CannonImpactVfxAnchor"
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(position)
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		clone.Parent = anchor
		anchor.Parent = hazardsFolder
		return anchor
	elseif clone:IsA("ParticleEmitter") or clone:IsA("Beam") or clone:IsA("Trail") or clone:IsA("Sound") then
		local anchor = Instance.new("Part")
		anchor.Name = "CannonImpactVfxAnchor"
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.CFrame = CFrame.new(position)
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanTouch = false
		anchor.CanQuery = false
		anchor.Transparency = 1

		local attachment = Instance.new("Attachment")
		attachment.Name = "CannonImpactVfxAttachment"
		attachment.Parent = anchor

		clone.Parent = attachment
		anchor.Parent = hazardsFolder
		return anchor
	end

	return clone
end

local function getVfxItems(root)
	local items = { root }
	for _, item in ipairs(root:GetDescendants()) do
		table.insert(items, item)
	end

	return items
end

local function emitVfx(root)
	for _, item in ipairs(getVfxItems(root)) do
		configureVfxInstance(item)

		if item:IsA("ParticleEmitter") then
			local emitCount = tonumber(item:GetAttribute("EmitCount")) or tonumber(item:GetAttribute("BurstCount"))
			if not emitCount then
				emitCount = math.floor((tonumber(item.Rate) or 0) * math.max(item.Lifetime.Max, 0.25))
			end
			item:Emit(math.max(1, math.floor(emitCount > 0 and emitCount or CONFIG.DefaultVfxEmitCount)))
		elseif item:IsA("Beam") or item:IsA("Trail") then
			item.Enabled = true
		elseif item:IsA("Sound") then
			item:Play()
		end
	end
end

local function makeFallbackImpactFlash(position, radius)
	local impactRadius = math.max(0.1, tonumber(radius) or CONFIG.DefaultImpactRadius)
	local flash = Instance.new("Part")
	flash.Name = "BombImpactFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(impactRadius * 1.4, impactRadius * 1.4, impactRadius * 1.4)
	flash.CFrame = CFrame.new(position + Vector3.new(0, impactRadius * 0.25, 0))
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 90, 35)
	flash.Transparency = 0.45
	flash.Parent = hazardsFolder

	task.delay(0.18, function()
		if flash.Parent then
			flash:Destroy()
		end
	end)
end

local function playImpactVfx(position, shot)
	local template = getImpactVfxTemplate(shot and shot.VfxName)
	if not template then
		makeFallbackImpactFlash(position, shot and shot.ImpactRadius)
		return
	end

	local clone = template:Clone()
	clone.Name = "CannonImpactVfx"
	setCannonDebugAttributes(clone, shot)
	scaleVfxClone(clone, CONFIG.ImpactVfxScale)
	for _, item in ipairs(clone:GetDescendants()) do
		configureVfxInstance(item)
	end
	configureVfxInstance(clone)

	local root = placeVfxClone(clone, position)
	if not root.Parent then
		root.Parent = hazardsFolder
	end
	emitVfx(root)

	task.delay(CONFIG.ImpactVfxLifetime, function()
		if root.Parent then
			root:Destroy()
		end
	end)
end

local function makeExplosion(position, shot)
	GameSounds.PlayAtPosition(GameSounds.Ids.Hazards.CannonExplosion, position, {
		Name = "CannonExplosion",
		Volume = 1,
		RollOffMaxDistance = 220,
		RollOffMinDistance = 20,
		Lifetime = 6,
		Parent = hazardsFolder,
	})
	playImpactVfx(position, shot)
end

local function isInsidePlanarImpactRadius(position, impactPosition, radius)
	if typeof(position) ~= "Vector3" or typeof(impactPosition) ~= "Vector3" then
		return false
	end

	local offset = position - impactPosition
	local planarDistanceSquared = (offset.X * offset.X) + (offset.Z * offset.Z)
	return planarDistanceSquared <= radius * radius
end

local function canTakeCannonImpactDamage(player, rootPart, impactPosition)
	if not (player and rootPart and typeof(impactPosition) == "Vector3") then
		return false
	end
	local refs = MapResolver.GetRefs()

	if not isInsideRunZone(rootPart.Position, refs) then
		return false
	end

	local verticalTolerance = math.max(0, tonumber(CONFIG.VerticalDamageTolerance) or 0)
	if math.abs(rootPart.Position.Y - impactPosition.Y) > verticalTolerance then
		return false
	end

	local character = player.Character
	local groundHit = getGroundHit(rootPart.Position, character, refs)
	if not groundHit then
		return false
	end

	return true
end

local function getCannonRagdollImpulse(impactPosition, rootPart)
	if typeof(impactPosition) ~= "Vector3" or typeof(rootPart) ~= "Instance" or not rootPart:IsA("BasePart") then
		return nil
	end

	local offset = rootPart.Position - impactPosition
	local fallbackDirection = rootPart.CFrame.LookVector
	local direction = getPlanarUnit(offset, fallbackDirection)
	local horizontalStrength = math.max(0, tonumber(CONFIG.RagdollImpulseHorizontal) or 0)
	local verticalStrength = math.max(0, tonumber(CONFIG.RagdollImpulseVertical) or 0)

	return (direction * horizontalStrength) + Vector3.new(0, verticalStrength, 0)
end

local function applyCannonKnockdown(player, impactPosition, rootPart)
	HitEffectService.ApplyEffect(player, "Knockdown", {
		Duration = CONFIG.KnockdownDuration,
		Priority = CONFIG.KnockdownPriority,
		HazardClass = CONFIG.HazardClass,
		HazardType = CONFIG.HazardType,
		Source = "CannonBarrage",
		DropPosition = rootPart.Position,
		RagdollJoints = true,
		RagdollImpulse = getCannonRagdollImpulse(impactPosition, rootPart),
		Movement = {
			WalkSpeedMultiplier = 0,
			JumpMultiplier = 0,
			AutoRotate = false,
			PlatformStand = true,
			State = Enum.HumanoidStateType.Ragdoll,
		},
	})
end

local function damagePlayersAt(position, shot)
	local impactRadius = math.max(0.1, tonumber(shot and shot.ImpactRadius) or CONFIG.DefaultImpactRadius)
	local damage = math.max(0, tonumber(shot and shot.Damage) or CONFIG.DefaultDamage)
	for _, player in ipairs(Players:GetPlayers()) do
		local _, humanoid, rootPart = getCharacterParts(player)
		if humanoid
			and rootPart
			and isInsidePlanarImpactRadius(rootPart.Position, position, impactRadius)
			and canTakeCannonImpactDamage(player, rootPart, position)
		then
			local isHazardProtected = HazardProtection.IsProtected(player, {
				Position = position,
				HitPosition = position,
				HazardClass = CONFIG.HazardClass,
				HazardType = CONFIG.HazardType,
				Source = "CannonBarrage",
			})
			if not isHazardProtected then
				DamageProtection.TraceMoguStartupDamage(player, {
					TargetContext = {
						Player = player,
						Character = player.Character,
						Humanoid = humanoid,
						RootPart = rootPart,
					},
					Position = position,
					HitPosition = position,
					Source = "CannonBarrage",
					Path = "CannonBarrage.damagePlayersAt",
				})
				applyCannonKnockdown(player, position, rootPart)
				humanoid:TakeDamage(damage)
			end
		end
	end
end

local function destroyImpactCircle(circle)
	if circle and circle.Parent then
		circle:Destroy()
	end
end

local function hideWarningCircle(circle)
	if circle and circle.Parent then
		circle.Transparency = 1
	end
end

local function getActiveBombCountForUserId(userId)
	local normalizedUserId = tonumber(userId)
	if not normalizedUserId or normalizedUserId <= 0 then
		return 0
	end

	return math.max(0, tonumber(activeBombCountByUserId[normalizedUserId]) or 0)
end

local function releaseActiveBombSlot(userId)
	activeBombCount = math.max(0, activeBombCount - 1)

	local normalizedUserId = tonumber(userId)
	if normalizedUserId and normalizedUserId > 0 then
		local current = math.max(0, tonumber(activeBombCountByUserId[normalizedUserId]) or 0)
		if current <= 1 then
			activeBombCountByUserId[normalizedUserId] = nil
		else
			activeBombCountByUserId[normalizedUserId] = current - 1
		end
	end
end

local function tryReserveActiveBombSlot(shot, circle)
	local globalLimit = math.max(1, tonumber(CONFIG.MaxActiveBombs) or 12)
	if activeBombCount >= globalLimit then
		warnOnce(
			"max_active_bombs",
			"[CannonBarrage] skipped drop reason=max_active_bombs limit=%d",
			globalLimit
		)
		destroyImpactCircle(circle)
		return false
	end

	local userId = tonumber(shot and shot.TargetUserId)
	local perPlayerLimit = math.max(1, tonumber(CONFIG.MaxActiveBombsPerPlayer) or 1)
	if userId and userId > 0 and getActiveBombCountForUserId(userId) >= perPlayerLimit then
		warnOnce(
			string.format("max_active_bombs_player:%d", userId),
			"[CannonBarrage] skipped drop player=%s reason=max_active_bombs_per_player limit=%d",
			tostring(shot and shot.TargetPlayerName or userId),
			perPlayerLimit
		)
		destroyImpactCircle(circle)
		return false
	end

	activeBombCount += 1
	if userId and userId > 0 then
		activeBombCountByUserId[userId] = getActiveBombCountForUserId(userId) + 1
	end

	return true
end

local function dropBombAt(position, shot, circle)
	if not tryReserveActiveBombSlot(shot, circle) then
		return
	end

	local startPosition = position + Vector3.new(0, CONFIG.DropHeight, 0)
	local endPosition = position + Vector3.new(0, CONFIG.BombSize / 2, 0)
	local fallTime = math.max(0.05, tonumber(shot and shot.FallTime) or CONFIG.FallTime)
	local bomb = makeBomb(startPosition, shot)

	local elapsed = 0
	while elapsed < fallTime and bomb.Parent do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt

		local alpha = math.clamp(elapsed / fallTime, 0, 1)
		local easedAlpha = alpha * alpha
		bomb.CFrame = CFrame.new(startPosition:Lerp(endPosition, easedAlpha))
	end

	if bomb.Parent then
		bomb:Destroy()
	end

	makeExplosion(position, shot)
	damagePlayersAt(position, shot)
	task.delay(math.max(0, tonumber(CONFIG.ImpactDebugLinger) or 0), function()
		destroyImpactCircle(circle)
	end)
	releaseActiveBombSlot(shot and shot.TargetUserId)
end

local function buildShotContext(player, targetData, tuning, shotIndex, shotsPerCycle, bountyContext)
	local biomeIndex = normalizeBiomeIndex(targetData and targetData.BiomeIndex) or 1
	local resolvedTuning = tuning or getCannonTuningForBiome(biomeIndex)
	bountyContext = if typeof(bountyContext) == "table" then bountyContext else {}
	return {
		Band = math.floor(tonumber(resolvedTuning and resolvedTuning.Band) or 1),
		BiomeIndex = biomeIndex,
		AreaName = targetData and targetData.AreaName or getAreaNameForBiome(biomeIndex),
		BiomeRoot = targetData and targetData.BiomeRoot,
		GroundPart = targetData and targetData.GroundPart,
		TargetSource = targetData and targetData.TargetSource or "PlayerGroundBiome",
		TargetPlayerName = player and player.Name or "",
		TargetUserId = player and player.UserId or 0,
		ShotIndex = math.floor(tonumber(shotIndex) or 1),
		ShotsPerCycle = math.floor(tonumber(shotsPerCycle) or 1),
		WarningTime = math.max(0.05, tonumber(resolvedTuning and resolvedTuning.WarningTime) or CONFIG.DefaultWarningTime),
		ImpactRadius = math.max(
			0.1,
			tonumber(resolvedTuning and resolvedTuning.ImpactRadius) or CONFIG.DefaultImpactRadius
		),
		Damage = rollCannonDamage(resolvedTuning),
		FallTime = math.max(0.05, tonumber(resolvedTuning and resolvedTuning.FallTime) or CONFIG.FallTime),
		VfxName = resolveCannonVfxName(resolvedTuning, biomeIndex),
		Bounty = math.max(0, math.floor((tonumber(bountyContext.Bounty) or 0) + 0.5)),
		CannonBountyTier = math.max(0, math.floor(tonumber(bountyContext.TierId) or 0)),
		CannonInterval = tonumber(bountyContext.Interval) or 0,
		CannonIntervalBase = tonumber(bountyContext.IntervalBase) or 0,
		CannonIntervalJitter = tonumber(bountyContext.IntervalJitter) or 0,
		RagdollImpulseHorizontal = math.max(0, tonumber(CONFIG.RagdollImpulseHorizontal) or 0),
		RagdollImpulseVertical = math.max(0, tonumber(CONFIG.RagdollImpulseVertical) or 0),
	}
end

local function runPlayerLoop(player)
	if activeLoopsByPlayer[player] then
		return
	end

	activeLoopsByPlayer[player] = true

	task.spawn(function()
		while player.Parent == Players do
			local bounty = getPlayerBounty(player)
			local intervalBase, _, bountyTierId = getCannonIntervalForBounty(bounty)
			if not intervalBase then
				task.wait(CONFIG.BountyCheckDelay)
				continue
			end

			local initialTargetData = getPlayerBombTarget(player)
			if not initialTargetData then
				task.wait(CONFIG.TargetCheckDelay)
				continue
			end

			local intervalJitter = getCannonIntervalJitter()
			local cannonInterval = math.max(
				tonumber(CONFIG.MinCannonInterval) or 1,
				intervalBase + intervalJitter
			)
			local bountyContext = {
				Bounty = bounty,
				TierId = bountyTierId,
				Interval = cannonInterval,
				IntervalBase = intervalBase,
				IntervalJitter = intervalJitter,
			}
			local cycleTuning = getCannonTuningForBiome(initialTargetData.BiomeIndex)
			local shotsPerCycle = rollShotsPerCycle(cycleTuning)
			local firedAnyShot = false
			for shotIndex = 1, shotsPerCycle do
				local targetData = getPlayerBombTarget(player)
				if not targetData then
					break
				end

				local tuning = getCannonTuningForBiome(targetData.BiomeIndex)
				local shot = buildShotContext(player, targetData, tuning, shotIndex, shotsPerCycle, bountyContext)
				local circle = makeImpactCircle(targetData.Position, shot)
				firedAnyShot = true

				task.wait(shot.WarningTime)

				hideWarningCircle(circle)
				dropBombAt(targetData.Position, shot, circle)
				if shotIndex < shotsPerCycle then
					task.wait(CONFIG.InterShotDelay)
				end
			end

			task.wait(if firedAnyShot then cannonInterval else CONFIG.TargetCheckDelay)
		end

		activeLoopsByPlayer[player] = nil
	end)
end

Players.PlayerAdded:Connect(runPlayerLoop)
Players.PlayerRemoving:Connect(function(player)
	activeLoopsByPlayer[player] = nil
	activeBombCountByUserId[player.UserId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	runPlayerLoop(player)
end
