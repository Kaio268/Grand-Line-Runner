local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))

local CONFIG = {
	WarningTime = 1.15,
	RetargetDelay = 0.15,
	DropHeight = 180,
	FallTime = 0.65,
	ImpactRadius = 18,
	Damage = 100,
	BombSize = 6,
	CircleHeight = 0.18,
	GroundRayHeight = 6,
	GroundRayDepth = 14,
	TargetCheckDelay = 0.2,
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

local hazardsFolder = Workspace:FindFirstChild("CannonBarrages")
if not hazardsFolder then
	hazardsFolder = Instance.new("Folder")
	hazardsFolder.Name = "CannonBarrages"
	hazardsFolder.Parent = Workspace
end

local activeLoopsByPlayer = {}

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

local function makeExplosion(position)
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 0
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = Workspace

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

local function damagePlayersAt(position)
	for _, player in ipairs(Players:GetPlayers()) do
		local targetPosition = getPlayerBombTarget(player)
		local _, humanoid, rootPart = getCharacterParts(player)
		if targetPosition and humanoid and rootPart and (rootPart.Position - position).Magnitude <= CONFIG.ImpactRadius then
			humanoid:TakeDamage(CONFIG.Damage)
		end
	end
end

local function dropBombAt(position)
	local startPosition = position + Vector3.new(0, CONFIG.DropHeight, 0)
	local endPosition = position + Vector3.new(0, CONFIG.BombSize / 2, 0)
	local bomb = makeBomb(startPosition)

	local elapsed = 0
	while elapsed < CONFIG.FallTime and bomb.Parent do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt

		local alpha = math.clamp(elapsed / CONFIG.FallTime, 0, 1)
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
