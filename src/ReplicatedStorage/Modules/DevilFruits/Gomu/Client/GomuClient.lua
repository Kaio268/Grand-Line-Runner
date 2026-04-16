local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local DevilFruitConfig = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruits = Modules:WaitForChild("DevilFruits")
local GomuFolder = DevilFruits:WaitForChild("Gomu")
local SharedFolder = GomuFolder:WaitForChild("Shared")
local ClientFolder = GomuFolder:WaitForChild("Client")
local Registry = require(SharedFolder:WaitForChild("Registry"))
local GomuVfxController = require(ClientFolder:WaitForChild("GomuVfxController"))

local GomuClient = {}
GomuClient.__index = GomuClient

local GOMU_AIM_RAY_DISTANCE = 500
local GOMU_HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 176, 120)
local GOMU_HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(255, 243, 231)
local GOMU_AUTO_LATCH_MAX_ALIGNMENT = math.cos(math.rad(18))
local GOMU_AUTO_LATCH_BASE_RADIUS = 4
local GOMU_AUTO_LATCH_RADIUS_FACTOR = 0.14
local MIN_DIRECTION_MAGNITUDE = 0.01

local function getCurrentCamera()
	return Workspace.CurrentCamera
end

local function getPlanarVector(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

local function getPlayerRootPart(targetPlayer)
	if not targetPlayer or not targetPlayer:IsA("Player") then
		return nil
	end

	local character = targetPlayer.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getPlanarDistance(a, b)
	local delta = a - b
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function getPlayerFromDescendant(instance)
	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model") then
			local targetPlayer = Players:GetPlayerFromCharacter(current)
			if targetPlayer then
				return targetPlayer
			end
		end

		current = current.Parent
	end

	return nil
end

local function getEquippedFruit(player)
	local fruitFolder = player:FindFirstChild("DevilFruit")
	if fruitFolder then
		local equipped = fruitFolder:FindFirstChild("Equipped")
		if equipped and equipped:IsA("StringValue") then
			if equipped.Value == DevilFruitConfig.None or equipped.Value == "None" then
				return DevilFruitConfig.None
			end

			return Registry.ResolveFruitName(equipped.Value) or equipped.Value
		end
	end

	local fruitAttribute = player:GetAttribute("EquippedDevilFruit")
	if typeof(fruitAttribute) == "string" then
		if fruitAttribute == DevilFruitConfig.None or fruitAttribute == "None" then
			return DevilFruitConfig.None
		end

		return Registry.ResolveFruitName(fruitAttribute) or fruitAttribute
	end

	return DevilFruitConfig.None
end

local function ensureGomuHighlight(self)
	local highlight = self.highlight
	if highlight and highlight.Parent then
		return highlight
	end

	highlight = Instance.new("Highlight")
	highlight.Name = "GomuAimHighlight"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = GOMU_HIGHLIGHT_FILL_COLOR
	highlight.FillTransparency = 0.45
	highlight.OutlineColor = GOMU_HIGHLIGHT_OUTLINE_COLOR
	highlight.OutlineTransparency = 0.05
	highlight.Enabled = false
	highlight.Parent = Workspace

	self.highlight = highlight
	return highlight
end

local function clearGomuHighlight(self)
	local highlight = self.highlight
	if highlight then
		highlight.Enabled = false
		highlight.Adornee = nil
	end

	self.targetPlayer = nil
end

local function getLookAimRay()
	local camera = getCurrentCamera()
	if not camera then
		return nil
	end

	local viewportSize = camera.ViewportSize
	return camera:ViewportPointToRay(viewportSize.X * 0.5, viewportSize.Y * 0.5)
end

local function getLookAimRaycast(player)
	local unitRay = getLookAimRay()
	if not unitRay then
		return nil, nil, nil, nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = player.Character and { player.Character } or {}
	params.IgnoreWater = true

	local rayVector = unitRay.Direction * GOMU_AIM_RAY_DISTANCE
	local result = Workspace:Raycast(unitRay.Origin, rayVector, params)
	return result, (result and result.Position) or (unitRay.Origin + rayVector), unitRay.Origin, unitRay.Direction.Unit
end

local function getDistanceFromRay(rayOrigin, rayDirection, point)
	local toPoint = point - rayOrigin
	local projectedDistance = math.max(0, toPoint:Dot(rayDirection))
	local closestPoint = rayOrigin + (rayDirection * projectedDistance)
	return (point - closestPoint).Magnitude, projectedDistance
end

local function isTargetInRange(self, targetPlayer, maxDistance)
	local localRootPart = self.getLocalRootPart()
	local targetRootPart = getPlayerRootPart(targetPlayer)
	if not localRootPart or not targetRootPart then
		return false
	end

	return getPlanarDistance(localRootPart.Position, targetRootPart.Position) <= (maxDistance + 0.5)
end

local function findAutoLatchTarget(self, launchDistance, rayOrigin, rayDirection)
	local localRootPart = self.getLocalRootPart()
	if not localRootPart or not rayOrigin or not rayDirection then
		return nil
	end

	local bestTargetPlayer
	local bestScore = -math.huge

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= self.player and isTargetInRange(self, targetPlayer, launchDistance) then
			local targetRootPart = getPlayerRootPart(targetPlayer)
			if targetRootPart then
				local targetPosition = targetRootPart.Position + Vector3.new(0, 1.5, 0)
				local toTarget = targetPosition - rayOrigin
				local toTargetUnit = toTarget.Magnitude > 0.01 and toTarget.Unit or nil
				local alignment = toTargetUnit and rayDirection:Dot(toTargetUnit) or -1
				if alignment >= GOMU_AUTO_LATCH_MAX_ALIGNMENT then
					local lateralDistance, projectedDistance = getDistanceFromRay(rayOrigin, rayDirection, targetPosition)
					local allowedRadius = math.max(GOMU_AUTO_LATCH_BASE_RADIUS, projectedDistance * GOMU_AUTO_LATCH_RADIUS_FACTOR)
					if lateralDistance <= allowedRadius then
						local planarDistance = getPlanarDistance(localRootPart.Position, targetRootPart.Position)
						local score = (alignment * 100) - (lateralDistance * 2) - (planarDistance * 0.1)
						if score > bestScore then
							bestScore = score
							bestTargetPlayer = targetPlayer
						end
					end
				end
			end
		end
	end

	return bestTargetPlayer
end

local function getGomuLaunchTarget(self, abilityConfig)
	local result, fallbackPosition, rayOrigin, rayDirection = getLookAimRaycast(self.player)
	local aimPosition = fallbackPosition
	local launchDistance = math.max(0, tonumber(abilityConfig and abilityConfig.LaunchDistance) or 0)
	local targetPlayer = findAutoLatchTarget(self, launchDistance, rayOrigin, rayDirection)

	if not targetPlayer and result then
		targetPlayer = getPlayerFromDescendant(result.Instance)
		if targetPlayer == self.player or not isTargetInRange(self, targetPlayer, launchDistance) then
			targetPlayer = nil
		end
	end

	if targetPlayer then
		local targetRootPart = getPlayerRootPart(targetPlayer)
		if targetRootPart then
			aimPosition = targetRootPart.Position
		end
	end

	if not aimPosition then
		local rootPart = self.getLocalRootPart()
		if rootPart then
			local fallbackDirection = rayDirection or rootPart.CFrame.LookVector
			aimPosition = rootPart.Position + (fallbackDirection * GOMU_AIM_RAY_DISTANCE)
		end
	end

	return aimPosition, targetPlayer
end

function GomuClient.Create(config)
	config = config or {}
	local self = setmetatable({}, GomuClient)
	self.player = config.player or Players.LocalPlayer
	self.getLocalRootPart = type(config.GetLocalRootPart) == "function" and config.GetLocalRootPart or function()
		local character = self.player.Character
		return character and character:FindFirstChild("HumanoidRootPart") or nil
	end
	self.getEquippedFruit = type(config.GetEquippedFruit) == "function" and config.GetEquippedFruit or function()
		return getEquippedFruit(self.player)
	end
	self.playOptionalEffect = type(config.PlayOptionalEffect) == "function" and config.PlayOptionalEffect or function() end
	self.highlight = nil
	self.targetPlayer = nil
	self.vfxController = GomuVfxController.new()
	return self
end

function GomuClient:BeginPredictedRequest(abilityName, fallbackBuilder)
	if abilityName ~= "RubberLaunch" then
		if typeof(fallbackBuilder) == "function" then
			return fallbackBuilder()
		end

		return nil
	end

	local abilityConfig = DevilFruitConfig.GetAbility("Gomu Gomu no Mi", "RubberLaunch")
	local aimPosition, targetPlayer = getGomuLaunchTarget(self, abilityConfig)
	return {
		AimPosition = aimPosition,
		TargetPlayerUserId = targetPlayer and targetPlayer.UserId or nil,
	}
end

function GomuClient:BuildRequestPayload(abilityName, abilityEntry, fallbackBuilder)
	if abilityName == "RubberLaunch" then
		return self:BeginPredictedRequest(abilityName)
	end

	if typeof(fallbackBuilder) == "function" then
		return fallbackBuilder()
	end

	return nil
end

function GomuClient:Update()
	local fruitName = self.getEquippedFruit()
	if fruitName ~= "Gomu Gomu no Mi" then
		clearGomuHighlight(self)
		return
	end

	local abilityConfig = DevilFruitConfig.GetAbility(fruitName, "RubberLaunch")
	if not abilityConfig then
		clearGomuHighlight(self)
		return
	end

	local _, targetPlayer = getGomuLaunchTarget(self, abilityConfig)
	if not targetPlayer or not targetPlayer.Character then
		clearGomuHighlight(self)
		return
	end

	local highlight = ensureGomuHighlight(self)
	highlight.Adornee = targetPlayer.Character
	highlight.Enabled = true
	self.targetPlayer = targetPlayer
end

function GomuClient:HandleEffect(targetPlayer, abilityName, payload)
	print("[GomuClient] HandleEffect", abilityName, payload)

	if abilityName ~= "RubberLaunch" then
		return false
	end

	payload = payload or {}

	local position = payload.AimPosition or payload.Position
	local direction = nil

	if targetPlayer and targetPlayer.Character then
		local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
		if root then
			direction = root.CFrame.LookVector
		end
	end

	print("[GomuClient] PlayBomb", position, direction)
	return self.vfxController:PlayBomb(position, direction)
end

	return self.vfxController:PlayBomb(position, direction)
end

function GomuClient:HandleStateEvent()
	return false
end

function GomuClient:HandleEquipped()
	return false
end

function GomuClient:HandleUnequipped()
	clearGomuHighlight(self)
	return false
end

function GomuClient:HandleCharacterRemoving()
	clearGomuHighlight(self)
	if self.vfxController then
		self.vfxController:HandleCharacterRemoving()
	end
end

function GomuClient:HandlePlayerRemoving(leavingPlayer)
	if self.vfxController then
		self.vfxController:HandlePlayerRemoving(leavingPlayer)
	end
end

return GomuClient