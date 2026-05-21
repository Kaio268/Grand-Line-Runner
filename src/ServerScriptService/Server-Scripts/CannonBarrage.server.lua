local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local StudioAssetResolver = require(Modules:WaitForChild("StudioAssetResolver"))
local HazardDebugConstants = require(Modules:WaitForChild("Debug"):WaitForChild("HazardDebugConstants"))
local HazardProtection = require(
	ServerScriptService:WaitForChild("Modules")
		:WaitForChild("DevilFruits")
		:WaitForChild("Server")
		:WaitForChild("HazardProtection")
)

local CONFIG = {
	Enabled = true,
	WarningTime = 0.65,
	RetargetDelay = 0.1,
	DropHeight = 180,
	FallTime = 0.65,
	FallTimeByZone = {
		[1] = 0.25,
		[2] = 0.30,
		[3] = 0.35,
		[4] = 0.40,
		[5] = 0.45,
		[6] = 0.50,
		[7] = 0.55,
		[8] = 0.60,
	},
	ImpactRadius = 18,
	Damage = 100,
	HazardClass = "major",
	HazardType = "cannon_barrage",
	BombSize = 6,
	CircleHeight = 0.18,
	ZoneCount = 8,
	GroundRayHeight = 6,
	GroundRayDepth = 14,
	TargetCheckDelay = 0.2,
	ImpactVfxLifetime = 3,
	ImpactVfxScale = 3,
	DefaultVfxEmitCount = 30,
	ZoneVfxNames = {
		[1] = "canon explosion",
		[2] = "water explosion",
		[3] = "ice",
		[4] = "water explosion",
		[5] = "canon explosion",
		[6] = "ice",
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

local function markHazardHitboxPart(part)
	if not part or not part:IsA("BasePart") then
		return
	end

	CollectionService:AddTag(part, HazardDebugConstants.HitboxTag)
	part:SetAttribute(HazardDebugConstants.DebugHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardHitboxAttribute, true)
	part:SetAttribute(HazardDebugConstants.HazardClassAttribute, CONFIG.HazardClass)
	part:SetAttribute(HazardDebugConstants.HazardTypeAttribute, CONFIG.HazardType)
	part:SetAttribute("HazardHitboxShape", "Cylinder")
	part:SetAttribute("HazardHitboxRadius", CONFIG.ImpactRadius)
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

local function isInsideRunZone(position)
	local refs = MapResolver.GetRefs()
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

local function getRunAlpha(position)
	local refs = MapResolver.GetRefs()
	local startPart = refs.WaveStart
	local endPart = refs.WaveEnd
	if not startPart or not endPart then
		return 0
	end

	local forward = getPlanarUnit(endPart.Position - startPart.Position, startPart.CFrame.LookVector)
	local runLength = math.max(1, math.abs((endPart.Position - startPart.Position):Dot(forward)))
	local forwardDistance = (position - startPart.Position):Dot(forward)

	return math.clamp(forwardDistance / runLength, 0, 0.999)
end

local function getZoneIndex(position)
	local zoneCount = math.max(1, math.floor(tonumber(CONFIG.ZoneCount) or 8))
	return math.clamp(math.floor(getRunAlpha(position) * zoneCount) + 1, 1, zoneCount)
end

local function getZoneFallTime(position)
	local zoneIndex = getZoneIndex(position)
	return CONFIG.FallTimeByZone[zoneIndex] or CONFIG.FallTime
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

local function getGroundHit(position, character)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { hazardsFolder, character }

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

local function getGroundPosition(position, character)
	local result = getGroundHit(position, character)
	return result and result.Position or nil
end

local function isNearSafeGap(position, character)
	local refs = MapResolver.GetRefs()
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
		if not getGroundHit(position + offset, character) then
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

	if humanoid.FloorMaterial == Enum.Material.Air then
		return nil
	end

	if not isInsideRunZone(rootPart.Position) then
		return nil
	end

	if isNearSafeGap(rootPart.Position, character) then
		return nil
	end

	local groundPosition = getGroundPosition(rootPart.Position, character)
	if not groundPosition or not isInsideRunZone(groundPosition) then
		return nil
	end

	return groundPosition
end

local function makeImpactCircle(position)
	local circle = Instance.new("Part")
	circle.Name = "BombTargetCircle"
	circle.Shape = Enum.PartType.Cylinder
	circle.Size = Vector3.new(CONFIG.CircleHeight, CONFIG.ImpactRadius * 2, CONFIG.ImpactRadius * 2)
	circle.CFrame = CFrame.new(position + Vector3.new(0, CONFIG.CircleHeight / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	circle.Anchored = true
	circle.CanCollide = false
	circle.CanTouch = false
	circle.CanQuery = false
	circle.Material = Enum.Material.Neon
	circle.Color = Color3.fromRGB(255, 35, 25)
	circle.Transparency = 0.35
	markHazardHitboxPart(circle)
	circle.Parent = hazardsFolder

	return circle
end

local function makeBomb(position)
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

local function getImpactVfxTemplate(position)
	local root = getCannonVfxRoot()
	if not root then
		return nil
	end

	local zoneIndex = getZoneIndex(position)
	local configuredName = CONFIG.ZoneVfxNames[zoneIndex] or CONFIG.ZoneVfxNames[1]
	local template = configuredName and findDescendantByLowerName(root, string.lower(configuredName))
	if template then
		return template
	end

	return findDescendantByLowerName(root, "canon explosion")
		or findDescendantByLowerName(root, "water explosion")
		or findDescendantByLowerName(root, "ice")
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

local function makeFallbackImpactFlash(position)
	local flash = Instance.new("Part")
	flash.Name = "BombImpactFlash"
	flash.Shape = Enum.PartType.Ball
	flash.Size = Vector3.new(CONFIG.ImpactRadius * 1.4, CONFIG.ImpactRadius * 1.4, CONFIG.ImpactRadius * 1.4)
	flash.CFrame = CFrame.new(position + Vector3.new(0, CONFIG.ImpactRadius * 0.25, 0))
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

local function playImpactVfx(position)
	local template = getImpactVfxTemplate(position)
	if not template then
		makeFallbackImpactFlash(position)
		return
	end

	local clone = template:Clone()
	clone.Name = "CannonImpactVfx"
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

local function makeExplosion(position)
	playImpactVfx(position)
end

local function damagePlayersAt(position)
	for _, player in ipairs(Players:GetPlayers()) do
		local targetPosition = getPlayerBombTarget(player)
		local _, humanoid, rootPart = getCharacterParts(player)
		if targetPosition and humanoid and rootPart and (rootPart.Position - position).Magnitude <= CONFIG.ImpactRadius then
			local isHazardProtected = HazardProtection.IsProtected(player, {
				Position = position,
				HitPosition = position,
				HazardClass = CONFIG.HazardClass,
				HazardType = CONFIG.HazardType,
				Source = "CannonBarrage",
			})
			if not isHazardProtected then
				humanoid:TakeDamage(CONFIG.Damage)
			end
		end
	end
end

local function dropBombAt(position)
	local startPosition = position + Vector3.new(0, CONFIG.DropHeight, 0)
	local endPosition = position + Vector3.new(0, CONFIG.BombSize / 2, 0)
	local fallTime = getZoneFallTime(position)
	local bomb = makeBomb(startPosition)

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

	makeExplosion(position)
	damagePlayersAt(position)
end

local function runPlayerLoop(player)
	if activeLoopsByPlayer[player] then
		return
	end

	activeLoopsByPlayer[player] = true

	task.spawn(function()
		while player.Parent == Players do
			local targetPosition = getPlayerBombTarget(player)
			if not targetPosition then
				task.wait(CONFIG.TargetCheckDelay)
				continue
			end

			local circle = makeImpactCircle(targetPosition)

			task.wait(CONFIG.WarningTime)

			if circle.Parent then
				circle:Destroy()
			end

			dropBombAt(targetPosition)
			task.wait(CONFIG.RetargetDelay)
		end

		activeLoopsByPlayer[player] = nil
	end)
end

Players.PlayerAdded:Connect(runPlayerLoop)
Players.PlayerRemoving:Connect(function(player)
	activeLoopsByPlayer[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	runPlayerLoop(player)
end
