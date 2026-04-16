local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local HazardUtils = require(Modules:WaitForChild("DevilFruits"):WaitForChild("HazardUtils"))
local BrainrotInteraction = require(Modules:WaitForChild("Server"):WaitForChild("Brainrot"):WaitForChild("Interaction"))
local SliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))
local CorridorController = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushCorridorRunController"))

local HoroServer = {}

local FRUIT_NAME = "Horo Horo no Mi"
local ABILITY_NAME = "GhostProjection"
local REMOTE_NAME = "HoroProjectionAction"
local WORLD_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local GHOSTS_FOLDER_NAME = "HoroGhosts"
local BODY_HIGHLIGHT_NAME = "HoroAbandonedBodyHighlight"
local GHOST_ATTRIBUTE = "HoroProjectionGhost"
local BODY_ATTRIBUTE = "HoroProjectionBody"
local PROJECTION_CARRY_ATTRIBUTE = "HoroProjectionCarryProjectionId"
local PROJECTION_SOURCE_SPEED_ATTRIBUTE = "HoroProjectionSourceWalkSpeed"

local DEFAULT_DURATION = 5
local DEFAULT_GHOST_SPEED = 15
local DEFAULT_CARRY_SPEED = 8
local DEFAULT_MAX_DISTANCE_FROM_BODY = 68
local DEFAULT_REWARD_INTERACT_RADIUS = 12
local DEFAULT_HAZARD_PROBE_RADIUS = 3.4
local DEFAULT_SERVER_HAZARD_PROBE_INTERVAL = 0.08
local DEFAULT_PICKUP_THROTTLE = 0.18
local DEFAULT_PICKUP_RANGE_GRACE_DURATION = 0.45
local DEFAULT_PICKUP_RANGE_GRACE_DISTANCE = 10
local DEFAULT_BODY_WALK_SPEED = 0
local DEFAULT_BODY_JUMP_POWER = 0
local DEFAULT_GHOST_TRANSPARENCY = 0.42
local DEFAULT_GHOST_JUMP_POWER = 0
local DEFAULT_GHOST_JUMP_HEIGHT = 0
local PROJECTION_SPEED_MULTIPLIER = 0.5
local MAX_PROJECTION_MOVE_SPEED = 200

local activeProjectionsByPlayer = setmetatable({}, { __mode = "k" })
local actionRemote = nil
local actionConnection = nil
local projectionSequence = 0
local DEBUG_TRACE = RunService:IsStudio()

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

local function getHorizontalDistance(fromPosition, toPosition)
	if typeof(fromPosition) ~= "Vector3" or typeof(toPosition) ~= "Vector3" then
		return math.huge
	end

	local delta = fromPosition - toPosition
	return Vector3.new(delta.X, 0, delta.Z).Magnitude
end

local function horoTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[HORO TRACE] " .. tostring(message), ...))
end

local function beginPickupRangeGrace(state, reason)
	local graceDuration = math.max(0, tonumber(state and state.PickupRangeGraceDuration) or 0)
	local graceDistance = math.max(0, tonumber(state and state.PickupRangeGraceDistance) or 0)
	if graceDuration <= 0 or graceDistance <= 0 then
		return
	end

	state.PickupRangeGraceUntil = getSharedTimestamp() + graceDuration
	horoTrace(
		"pickupRangeGrace begin player=%s projectionId=%s reason=%s duration=%.2f distance=%.2f until=%.3f",
		state.Player and state.Player.Name or "<nil>",
		tostring(state.ProjectionId),
		tostring(reason),
		graceDuration,
		graceDistance,
		state.PickupRangeGraceUntil
	)
end

local function getPlayerCarrySummary(player)
	if not player then
		return "player=<nil>"
	end

	return string.format(
		"attrMajor=%s attrMajorName=%s attrBrainrot=%s projectionCarryMarker=%s horoActive=%s horoProjectionId=%s horoCarrying=%s",
		tostring(player:GetAttribute("CarriedMajorRewardType")),
		tostring(player:GetAttribute("CarriedMajorRewardDisplayName")),
		tostring(player:GetAttribute("CarriedBrainrot")),
		tostring(player:GetAttribute(PROJECTION_CARRY_ATTRIBUTE)),
		tostring(player:GetAttribute("HoroProjectionActive")),
		tostring(player:GetAttribute("HoroProjectionId")),
		tostring(player:GetAttribute("HoroProjectionCarryingReward"))
	)
end

local function getSliceCarrySummary(player)
	if not player then
		return "slicePlayer=<nil>"
	end

	local ok, stateOrError = pcall(function()
		return SliceService.GetState(player)
	end)
	if not ok then
		return string.format("sliceStateError=%s", tostring(stateOrError))
	end

	local state = stateOrError
	local runState = state and state.Run or {}
	local carriedReward = runState.CarriedReward
	local spawnedReward = runState.SpawnedReward
	return string.format(
		"sliceInRun=%s sliceCarried=%s sliceCarriedType=%s sliceSpawned=%s sliceSpawnedType=%s sliceSpawnedDrop=%s",
		tostring(runState.InRun),
		tostring(carriedReward ~= nil),
		tostring(carriedReward and carriedReward.RewardType or nil),
		tostring(spawnedReward ~= nil),
		tostring(spawnedReward and spawnedReward.RewardType or nil),
		formatVector3(spawnedReward and spawnedReward.WorldDropPosition or nil)
	)
end

local function getSharedTimestamp()
	return Workspace:GetServerTimeNow()
end

local function setProjectionCarryMarker(player, projectionId)
	if not player or player.Parent ~= Players then
		return
	end

	player:SetAttribute(PROJECTION_CARRY_ATTRIBUTE, projectionId)
end

local function clearProjectionCarryMarker(player, projectionId)
	if not player or player.Parent ~= Players then
		return
	end

	if projectionId == nil or player:GetAttribute(PROJECTION_CARRY_ATTRIBUTE) == projectionId then
		player:SetAttribute(PROJECTION_CARRY_ATTRIBUTE, nil)
	end
end

local function clampNumber(value, fallback, minValue, maxValue)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return fallback
	end

	return math.clamp(numericValue, minValue, maxValue)
end

local function resolveColor(value, fallback)
	if typeof(value) == "Color3" then
		return value
	end

	return fallback
end

local function getVfxConfig(abilityConfig)
	return type(abilityConfig.Vfx) == "table" and abilityConfig.Vfx or {}
end

local function ensureFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function ensureActionRemote()
	if actionRemote then
		return actionRemote
	end

	local remotesFolder = ensureFolder(ReplicatedStorage, "Remotes")
	local remote = remotesFolder:FindFirstChild(REMOTE_NAME)
	if remote and not remote:IsA("RemoteEvent") then
		remote:Destroy()
		remote = nil
	end

	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = REMOTE_NAME
		remote.Parent = remotesFolder
	end

	actionRemote = remote
	return actionRemote
end

local function getGhostsFolder()
	local effectsFolder = ensureFolder(Workspace, WORLD_EFFECTS_FOLDER_NAME)
	return ensureFolder(effectsFolder, GHOSTS_FOLDER_NAME)
end

local function disconnectAll(connections)
	for _, connection in ipairs(connections or {}) do
		if typeof(connection) == "RBXScriptConnection" then
			connection:Disconnect()
		end
	end
end

local function getRootPart(character)
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local function getGhostCarryPart(state)
	if not state then
		return nil
	end

	local ghostModel = state.GhostModel
	local cachedPart = state.GhostCarryPart
	if cachedPart and cachedPart.Parent and ghostModel and cachedPart:IsDescendantOf(ghostModel) then
		return cachedPart
	end

	if ghostModel then
		for _, partName in ipairs({ "Head", "UpperTorso", "Torso" }) do
			local part = ghostModel:FindFirstChild(partName, true)
			if part and part:IsA("BasePart") then
				state.GhostCarryPart = part
				return part
			end
		end
	end

	state.GhostCarryPart = state.GhostRoot
	return state.GhostCarryPart
end

local function setAssemblyNetworkOwner(rootPart, owner)
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	if not owner or owner.Parent ~= Players then
		return
	end

	local assigned = {}
	local function assignPart(part)
		if not part or not part:IsA("BasePart") or assigned[part] then
			return
		end
		assigned[part] = true
		if part.Anchored then
			return
		end

		pcall(function()
			part:SetNetworkOwner(owner)
		end)
	end

	assignPart(rootPart)

	local ok, connectedParts = pcall(function()
		return rootPart:GetConnectedParts(true)
	end)
	if not ok then
		return
	end

	for _, part in ipairs(connectedParts) do
		assignPart(part)
	end
end

local function refreshGhostNetworkOwnership(state)
	if not state or state.Resolved then
		return
	end
	if not state.Player or state.Player.Parent ~= Players then
		return
	end

	local carrierPart = getGhostCarryPart(state)
	if carrierPart then
		setAssemblyNetworkOwner(carrierPart, state.Player)
	end
	if state.GhostRoot and state.GhostRoot ~= carrierPart then
		setAssemblyNetworkOwner(state.GhostRoot, state.Player)
	end
end

local function scheduleGhostNetworkOwnershipRefresh(state, attempts, interval)
	if not state then
		return
	end

	local totalAttempts = math.max(1, attempts or 1)
	local delayStep = math.max(0, interval or 0)
	for attempt = 1, totalAttempts do
		task.delay((attempt - 1) * delayStep, function()
			if activeProjectionsByPlayer[state.Player] ~= state or state.Resolved then
				return
			end
			refreshGhostNetworkOwnership(state)
		end)
	end
end

local function hasCarriedReward(player)
	return player:GetAttribute("CarriedMajorRewardType") ~= nil
		or player:GetAttribute("CarriedBrainrot") ~= nil
end

local function numbersDiffer(left, right)
	if typeof(left) ~= "number" or typeof(right) ~= "number" then
		return left ~= right
	end

	return math.abs(left - right) > 0.01
end

local function getProjectionSourceSpeed(state)
	if not state then
		return nil
	end

	local player = state.Player
	local attributeSpeed = player and player:GetAttribute(PROJECTION_SOURCE_SPEED_ATTRIBUTE)
	if typeof(attributeSpeed) == "number" and attributeSpeed > 0 then
		return attributeSpeed
	end

	local originalBodySpeed = state.BodyOriginal and state.BodyOriginal.WalkSpeed
	if typeof(originalBodySpeed) == "number" and originalBodySpeed > 0 then
		return originalBodySpeed
	end

	local humanoid = state.Humanoid
	if humanoid and humanoid.Parent and humanoid.Health > 0 and humanoid.WalkSpeed > 0 then
		return humanoid.WalkSpeed
	end

	return nil
end

local function resolveProjectionSpeeds(state)
	local abilityConfig = state and state.AbilityConfig or {}
	local sourceSpeed = getProjectionSourceSpeed(state)
	local fallbackGhostSpeed = clampNumber(abilityConfig.GhostSpeed, DEFAULT_GHOST_SPEED, 2, MAX_PROJECTION_MOVE_SPEED)
	local fallbackCarrySpeed = clampNumber(abilityConfig.CarrySpeed, DEFAULT_CARRY_SPEED, 1, MAX_PROJECTION_MOVE_SPEED)

	if typeof(sourceSpeed) == "number" and sourceSpeed > 0 then
		local halfSpeed = sourceSpeed * PROJECTION_SPEED_MULTIPLIER
		return math.max(2, halfSpeed), math.max(1, halfSpeed), sourceSpeed
	end

	return fallbackGhostSpeed, fallbackCarrySpeed, sourceSpeed
end

local function refreshProjectionSpeeds(state)
	if not state then
		return false
	end

	local ghostSpeed, carrySpeed, sourceSpeed = resolveProjectionSpeeds(state)
	local changed = numbersDiffer(state.GhostSpeed, ghostSpeed)
		or numbersDiffer(state.CarrySpeed, carrySpeed)
		or numbersDiffer(state.SourcePlayerSpeed, sourceSpeed)

	state.GhostSpeed = ghostSpeed
	state.CarrySpeed = carrySpeed
	state.SourcePlayerSpeed = sourceSpeed

	return changed
end

local function getConfiguredGhostSpeed(state)
	local abilityConfig = state and state.AbilityConfig or {}
	return clampNumber(abilityConfig.GhostSpeed, DEFAULT_GHOST_SPEED, 2, MAX_PROJECTION_MOVE_SPEED)
end

local function getEffectiveMaxDistanceFromBody(state, now)
	local maxDistanceFromBody = math.max(0, tonumber(state and state.MaxDistanceFromBody) or 0)
	if maxDistanceFromBody <= 0 then
		return 0
	end

	local effectiveMaxDistance = maxDistanceFromBody + 4
	refreshProjectionSpeeds(state)
	local currentMoveSpeed = math.max(
		0,
		tonumber((state and state.Player and hasCarriedReward(state.Player)) and state.CarrySpeed or state.GhostSpeed) or 0
	)
	local configuredGhostSpeed = getConfiguredGhostSpeed(state)
	if currentMoveSpeed > configuredGhostSpeed and configuredGhostSpeed > 0 then
		effectiveMaxDistance *= currentMoveSpeed / configuredGhostSpeed
	end

	local pickupRangeGraceUntil = tonumber(state and state.PickupRangeGraceUntil) or 0
	if pickupRangeGraceUntil <= 0 then
		return effectiveMaxDistance
	end

	local comparisonTime = tonumber(now) or getSharedTimestamp()
	if comparisonTime <= pickupRangeGraceUntil then
		effectiveMaxDistance += math.max(0, tonumber(state and state.PickupRangeGraceDistance) or 0)
	else
		state.PickupRangeGraceUntil = 0
	end

	return effectiveMaxDistance
end

local function setProjectionAttributes(state, isActive)
	local player = state.Player
	if not player or player.Parent ~= Players then
		return
	end

	if not isActive then
		player:SetAttribute("HoroProjectionActive", nil)
		player:SetAttribute("HoroProjectionId", nil)
		player:SetAttribute("HoroProjectionEndTime", nil)
		player:SetAttribute("HoroProjectionGhostSpeed", nil)
		player:SetAttribute("HoroProjectionCarrySpeed", nil)
		player:SetAttribute("HoroProjectionMaxDistance", nil)
		player:SetAttribute("HoroProjectionCarryingReward", nil)
		player:SetAttribute("HoroProjectionGhostName", nil)
		player:SetAttribute("HoroProjectionBodyName", nil)
		return
	end

	refreshProjectionSpeeds(state)
	player:SetAttribute("HoroProjectionActive", true)
	player:SetAttribute("HoroProjectionId", state.ProjectionId)
	player:SetAttribute("HoroProjectionEndTime", state.EndTime)
	player:SetAttribute("HoroProjectionGhostSpeed", state.GhostSpeed)
	player:SetAttribute("HoroProjectionCarrySpeed", state.CarrySpeed)
	player:SetAttribute("HoroProjectionMaxDistance", getEffectiveMaxDistanceFromBody(state))
	player:SetAttribute("HoroProjectionCarryingReward", hasCarriedReward(player))
	player:SetAttribute("HoroProjectionGhostName", state.GhostModel and state.GhostModel.Name or nil)
	player:SetAttribute("HoroProjectionBodyName", state.Character and state.Character.Name or nil)
end

local function updateGhostMovement(state)
	if not state or not state.GhostHumanoid or not state.GhostHumanoid.Parent then
		return
	end

	local speedsChanged = refreshProjectionSpeeds(state)
	if speedsChanged and state.Player and state.Player.Parent == Players then
		state.Player:SetAttribute("HoroProjectionGhostSpeed", state.GhostSpeed)
		state.Player:SetAttribute("HoroProjectionCarrySpeed", state.CarrySpeed)
		state.Player:SetAttribute("HoroProjectionMaxDistance", getEffectiveMaxDistanceFromBody(state))
	end

	local speed = if hasCarriedReward(state.Player) then state.CarrySpeed else state.GhostSpeed
	state.GhostHumanoid.WalkSpeed = speed
	state.GhostHumanoid.JumpPower = clampNumber(
		state.AbilityConfig.GhostJumpPower,
		DEFAULT_GHOST_JUMP_POWER,
		0,
		200
	)
	state.GhostHumanoid.JumpHeight = clampNumber(
		state.AbilityConfig.GhostJumpHeight,
		DEFAULT_GHOST_JUMP_HEIGHT,
		0,
		50
	)
	state.GhostHumanoid.AutoRotate = true
end

local function updateCarryingAttribute(state)
	if state and state.Player and state.Player.Parent == Players then
		state.Player:SetAttribute("HoroProjectionCarryingReward", hasCarriedReward(state.Player))
	end
	updateGhostMovement(state)
end

local function createBodyHighlight(character, abilityConfig)
	local vfxConfig = getVfxConfig(abilityConfig)
	local highlight = Instance.new("Highlight")
	highlight.Name = BODY_HIGHLIGHT_NAME
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = resolveColor(vfxConfig.BodyHighlightColor, Color3.fromRGB(105, 167, 206))
	highlight.OutlineColor = Color3.fromRGB(242, 250, 255)
	highlight.FillTransparency = clampNumber(abilityConfig.BodyHighlightFillTransparency, 0.82, 0, 1)
	highlight.OutlineTransparency = clampNumber(abilityConfig.BodyHighlightOutlineTransparency, 0.16, 0, 1)
	highlight.Parent = character
	return highlight
end

local function lockBody(state)
	local humanoid = state.Humanoid
	if not humanoid then
		return
	end

	state.BodyOriginal = {
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
		RootAnchored = if state.RootPart then state.RootPart.Anchored else nil,
		RootCFrame = if state.RootPart then state.RootPart.CFrame else nil,
	}

	humanoid.WalkSpeed = clampNumber(state.AbilityConfig.BodyWalkSpeed, DEFAULT_BODY_WALK_SPEED, 0, 100)
	humanoid.JumpPower = clampNumber(state.AbilityConfig.BodyJumpPower, DEFAULT_BODY_JUMP_POWER, 0, 200)
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	if state.RootPart then
		local currentVelocity = state.RootPart.AssemblyLinearVelocity
		state.RootPart.AssemblyLinearVelocity = Vector3.new(0, math.min(currentVelocity.Y, 0), 0)
		state.RootPart.AssemblyAngularVelocity = Vector3.zero
		state.RootPart.Anchored = state.BodyOriginal.RootAnchored == true
	end
	state.BodyHighlight = createBodyHighlight(state.Character, state.AbilityConfig)
end

local function restoreBody(state)
	local humanoid = state.Humanoid
	local original = state.BodyOriginal
	if humanoid and original then
		if humanoid.Parent and humanoid.Health > 0 then
			humanoid.WalkSpeed = original.WalkSpeed or humanoid.WalkSpeed
			humanoid.JumpPower = original.JumpPower or humanoid.JumpPower
			humanoid.JumpHeight = original.JumpHeight or humanoid.JumpHeight
			humanoid.AutoRotate = if original.AutoRotate ~= nil then original.AutoRotate else humanoid.AutoRotate
		end
	end

	if state.RootPart and state.RootPart.Parent and original then
		if original.RootAnchored ~= nil then
			state.RootPart.Anchored = original.RootAnchored
		end
		state.RootPart.AssemblyLinearVelocity = Vector3.zero
		state.RootPart.AssemblyAngularVelocity = Vector3.zero
	end

	if state.BodyHighlight and state.BodyHighlight.Parent then
		state.BodyHighlight:Destroy()
	end
	state.BodyHighlight = nil
end

local function removeScriptsAndTools(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Tool") or descendant:IsA("ForceField") then
			descendant:Destroy()
		elseif descendant:IsA("BaseScript") and descendant.Name ~= "Animate" then
			descendant:Destroy()
		end
	end
end

local function styleGhostModel(ghostModel, state)
	local abilityConfig = state.AbilityConfig
	local vfxConfig = getVfxConfig(abilityConfig)
	local ghostTransparency = clampNumber(abilityConfig.GhostTransparency, DEFAULT_GHOST_TRANSPARENCY, 0, 0.95)
	local ghostColor = resolveColor(vfxConfig.GhostColor, Color3.fromRGB(198, 238, 255))
	local accentColor = resolveColor(vfxConfig.GhostAccentColor, Color3.fromRGB(255, 255, 255))

	for _, descendant in ipairs(ghostModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanTouch = true
			descendant.CanQuery = true
			descendant.CastShadow = false
			descendant.Transparency = math.max(descendant.Transparency, ghostTransparency)
			if descendant.Name ~= "HumanoidRootPart" then
				descendant.Color = descendant.Color:Lerp(ghostColor, 0.55)
				descendant.Material = Enum.Material.ForceField
			else
				descendant.Transparency = 1
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = math.max(descendant.Transparency, 0.68)
		end
	end

	local humanoid = ghostModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.WalkSpeed = state.GhostSpeed
		humanoid.JumpPower = clampNumber(abilityConfig.GhostJumpPower, DEFAULT_GHOST_JUMP_POWER, 0, 200)
		humanoid.JumpHeight = clampNumber(abilityConfig.GhostJumpHeight, DEFAULT_GHOST_JUMP_HEIGHT, 0, 50)
		humanoid.AutoRotate = true
		humanoid.BreakJointsOnDeath = false
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "HoroGhostHighlight"
	highlight.Adornee = ghostModel
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = ghostColor
	highlight.OutlineColor = accentColor
	highlight.FillTransparency = 0.62
	highlight.OutlineTransparency = 0.1
	highlight.Parent = ghostModel

	local ghostRoot = getRootPart(ghostModel)
	if ghostRoot then
		local attachment = Instance.new("Attachment")
		attachment.Name = "HoroGhostWispAttachment"
		attachment.Parent = ghostRoot

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "HoroGhostWisps"
		emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		emitter.Color = ColorSequence.new(ghostColor, accentColor)
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(0.5, 0.68),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.22),
			NumberSequenceKeypoint.new(1, 0.04),
		})
		emitter.Lifetime = NumberRange.new(0.45, clampNumber(vfxConfig.ParticleLifetime, 0.8, 0.2, 2))
		emitter.Rate = clampNumber(vfxConfig.ParticleRate, 18, 0, 100)
		emitter.Speed = NumberRange.new(0.2, 0.9)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.LightEmission = 0.35
		emitter.LightInfluence = 0
		emitter.LockedToPart = true
		emitter.Parent = attachment
	end
end

local function buildFallbackGhost(state)
	local model = Instance.new("Model")
	model.Name = "HoroGhost"

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2.4, 3.2, 2.4)
	root.Shape = Enum.PartType.Ball
	root.Material = Enum.Material.ForceField
	root.Color = Color3.fromRGB(198, 238, 255)
	root.CanCollide = true
	root.CanTouch = true
	root.CanQuery = true
	root.Parent = model

	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = model
	model.PrimaryPart = root

	return model
end

local function createGhostModel(state)
	local character = state.Character
	local rootPart = state.RootPart
	local ghostModel = nil
	if character then
		local previousArchivable = character.Archivable
		character.Archivable = true
		local ok, clone = pcall(function()
			return character:Clone()
		end)
		character.Archivable = previousArchivable
		if ok and clone then
			ghostModel = clone
		end
	end

	if not ghostModel then
		ghostModel = buildFallbackGhost(state)
	end

	removeScriptsAndTools(ghostModel)
	ghostModel:SetAttribute("HoroGhost", true)
	ghostModel:SetAttribute(GHOST_ATTRIBUTE, true)
	ghostModel:SetAttribute("OwnerUserId", state.Player.UserId)
	ghostModel:SetAttribute("ProjectionId", state.ProjectionId)
	if ghostModel:GetAttribute("CurrentModelAsset") == nil then
		ghostModel:SetAttribute("CurrentModelAsset", "R6")
	end

	local ghostRoot = getRootPart(ghostModel) or ghostModel.PrimaryPart or ghostModel:FindFirstChildWhichIsA("BasePart", true)
	if not ghostRoot then
		ghostModel:Destroy()
		return nil, nil
	end

	ghostModel.PrimaryPart = ghostRoot
	styleGhostModel(ghostModel, state)

	local startCFrame = rootPart.CFrame + (rootPart.CFrame.LookVector * 4)
	ghostModel:PivotTo(startCFrame)
	ghostModel.Parent = getGhostsFolder()

	for _, descendant in ipairs(ghostModel:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant.Anchored then
			pcall(function()
				descendant:SetNetworkOwner(state.Player)
			end)
		end
	end

	return ghostModel, ghostRoot
end

local function isDangerousHazardPart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	local hazardRoot = HazardUtils.GetHazardInfo(part)
	return hazardRoot ~= nil
end

local function buildOverlapParams(state)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {
		state.Character,
		state.GhostModel,
	}
	return params
end

local function setBodyProjectionAttributes(state, isActive)
	local character = state and state.Character
	if not character or not character.Parent then
		return
	end

	if isActive then
		character:SetAttribute(BODY_ATTRIBUTE, true)
		character:SetAttribute("HoroProjectionOwnerUserId", state.Player.UserId)
		character:SetAttribute("ProjectionId", state.ProjectionId)
		return
	end

	character:SetAttribute(BODY_ATTRIBUTE, nil)
	character:SetAttribute("HoroProjectionOwnerUserId", nil)
	character:SetAttribute("ProjectionId", nil)
end

local function scheduleRespawnIfBodyDead(state)
	local player = state and state.Player
	local character = state and state.Character
	local humanoid = state and state.Humanoid
	if not player or not character or not humanoid then
		return
	end

	task.delay(0.25, function()
		if player.Parent == Players
			and player.Character == character
			and humanoid.Parent ~= nil
			and humanoid.Health <= 0
		then
			player:LoadCharacter()
		end
	end)
end

local function dropCarriedRewards(state, dropPosition)
	local player = state.Player
	local droppedAny = false
	local markedProjectionId = player:GetAttribute(PROJECTION_CARRY_ATTRIBUTE)
	horoTrace(
		"dropCarriedRewards begin player=%s projectionId=%s markedProjectionId=%s dropPos=%s carryAttrs={%s} sliceState={%s}",
		player and player.Name or "<nil>",
		tostring(state and state.ProjectionId),
		tostring(markedProjectionId),
		formatVector3(dropPosition),
		getPlayerCarrySummary(player),
		getSliceCarrySummary(player)
	)
	if markedProjectionId ~= state.ProjectionId then
		horoTrace(
			"dropCarriedRewards skipped player=%s projectionId=%s reason=projection_marker_mismatch markedProjectionId=%s",
			player and player.Name or "<nil>",
			tostring(state and state.ProjectionId),
			tostring(markedProjectionId)
		)
		updateCarryingAttribute(state)
		return false
	end

	local response = SliceService.DropCarriedReward(player, {
		Reason = "HoroProjection",
		DropPosition = dropPosition,
		IgnoreProtection = true,
	})
	if response and response.ok then
		droppedAny = true
	end
	horoTrace(
		"dropCarriedRewards sliceDrop player=%s projectionId=%s ok=%s error=%s message=%s worldDrop=%s",
		player and player.Name or "<nil>",
		tostring(state and state.ProjectionId),
		tostring(response and response.ok == true),
		tostring(response and response.error),
		tostring(response and response.message),
		formatVector3(dropPosition)
	)

	local brainrotContext = BrainrotInteraction.GetActiveContext()
	local droppedBrainrot = BrainrotInteraction.DropHeldAtPosition(brainrotContext, player, nil, dropPosition)
	if droppedBrainrot then
		droppedAny = true
	end
	horoTrace(
		"dropCarriedRewards brainrotDrop player=%s projectionId=%s dropped=%s",
		player and player.Name or "<nil>",
		tostring(state and state.ProjectionId),
		tostring(droppedBrainrot == true)
	)

	clearProjectionCarryMarker(player, state.ProjectionId)
	updateCarryingAttribute(state)
	horoTrace(
		"dropCarriedRewards end player=%s projectionId=%s droppedAny=%s carryAttrs={%s} sliceState={%s}",
		player and player.Name or "<nil>",
		tostring(state and state.ProjectionId),
		tostring(droppedAny),
		getPlayerCarrySummary(player),
		getSliceCarrySummary(player)
	)
	return droppedAny
end

local finishProjection

local function handleGhostTouched(state, hit)
	if not state or state.Resolved or activeProjectionsByPlayer[state.Player] ~= state then
		return
	end
	if hit:IsDescendantOf(state.GhostModel) or hit:IsDescendantOf(state.Character) then
		return
	end
	if isDangerousHazardPart(hit) then
		finishProjection(state, "hazard_touch", state.GhostRoot and state.GhostRoot.Position or nil, true)
	end
end

local function connectGhostTouch(state, part)
	if not part or not part:IsA("BasePart") then
		return
	end

	state.Connections[#state.Connections + 1] = part.Touched:Connect(function(hit)
		handleGhostTouched(state, hit)
	end)
end

local function attachGhostTouchListeners(state)
	for _, descendant in ipairs(state.GhostModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			connectGhostTouch(state, descendant)
		end
	end

	state.Connections[#state.Connections + 1] = state.GhostModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			connectGhostTouch(state, descendant)
		end
	end)
end

local function buildResolvePayload(state, reason, phase, dropPosition, droppedReward)
	local endedAt = getSharedTimestamp()
	return {
		Phase = phase,
		StartedAt = state.StartedAt,
		EndedAt = endedAt,
		EndTime = state.EndTime,
		Duration = state.Duration,
		ProjectionId = state.ProjectionId,
		GhostName = state.GhostModel and state.GhostModel.Name or "",
		BodyName = state.Character and state.Character.Name or "",
		StartPosition = state.StartPosition,
		EndPosition = dropPosition,
		ResolveReason = reason,
		DroppedReward = droppedReward == true,
		WasCarryingReward = state.WasCarryingReward == true,
	}
end

local function shouldStartCooldownOnProjectionFinish(reason)
	return reason ~= "manual_cleanup" and reason ~= "player_removing"
end

finishProjection = function(state, reason, dropPosition, shouldDropReward)
	if not state or state.Resolved then
		return false
	end
	if activeProjectionsByPlayer[state.Player] ~= state then
		return false
	end

	horoTrace(
		"finishProjection begin player=%s projectionId=%s reason=%s shouldDropReward=%s requestedDrop=%s ghostPos=%s bodyPos=%s carryAttrs={%s} sliceState={%s}",
		state.Player and state.Player.Name or "<nil>",
		tostring(state.ProjectionId),
		tostring(reason),
		tostring(shouldDropReward == true),
		formatVector3(dropPosition),
		formatVector3(state.GhostRoot and state.GhostRoot.Position or nil),
		formatVector3(state.RootPart and state.RootPart.Position or nil),
		getPlayerCarrySummary(state.Player),
		getSliceCarrySummary(state.Player)
	)

	state.Resolved = true
	activeProjectionsByPlayer[state.Player] = nil
	disconnectAll(state.Connections)

	local finalPosition = dropPosition
	if typeof(finalPosition) ~= "Vector3" then
		finalPosition = state.GhostRoot and state.GhostRoot.Position or state.RootPart.Position
	end

	state.WasCarryingReward = hasCarriedReward(state.Player)
	local droppedReward = false
	if shouldDropReward == true and state.WasCarryingReward then
		droppedReward = dropCarriedRewards(state, finalPosition)
	end
	if not hasCarriedReward(state.Player) then
		clearProjectionCarryMarker(state.Player, state.ProjectionId)
	end
	horoTrace(
		"finishProjection postDrop player=%s projectionId=%s reason=%s wasCarrying=%s droppedReward=%s finalDrop=%s carryAttrs={%s} sliceState={%s}",
		state.Player and state.Player.Name or "<nil>",
		tostring(state.ProjectionId),
		tostring(reason),
		tostring(state.WasCarryingReward == true),
		tostring(droppedReward == true),
		formatVector3(finalPosition),
		getPlayerCarrySummary(state.Player),
		getSliceCarrySummary(state.Player)
	)

	restoreBody(state)
	setBodyProjectionAttributes(state, false)
	setProjectionAttributes(state, false)

	local phase = if reason == "duration_elapsed" or reason == "manual_cleanup" then "Resolve" else "Interrupted"
	local payload = buildResolvePayload(state, reason, phase, finalPosition, droppedReward)
	if typeof(state.EmitEffect) == "function" and state.Player.Parent == Players then
		state.EmitEffect(ABILITY_NAME, payload, state.Player)
	end
	if state.Player.Parent == Players
		and shouldStartCooldownOnProjectionFinish(reason)
		and typeof(state.StartAbilityCooldown) == "function"
	then
		local readyAt = state.StartAbilityCooldown(tonumber(state.AbilityConfig and state.AbilityConfig.Cooldown) or 0, payload)
		horoTrace(
			"finishProjection cooldownStarted player=%s projectionId=%s reason=%s readyAt=%s",
			state.Player and state.Player.Name or "<nil>",
			tostring(state.ProjectionId),
			tostring(reason),
			tostring(readyAt)
		)
	end

	if state.GhostModel and state.GhostModel.Parent then
		state.GhostModel:Destroy()
	end

	if reason == "body_defeated" and state.Humanoid and state.Humanoid.Health <= 0 then
		scheduleRespawnIfBodyDead(state)
	end

	horoTrace(
		"finishProjection complete player=%s projectionId=%s phase=%s reason=%s droppedReward=%s playerAttrs={%s} sliceState={%s}",
		state.Player and state.Player.Name or "<nil>",
		tostring(state.ProjectionId),
		tostring(phase),
		tostring(reason),
		tostring(droppedReward == true),
		getPlayerCarrySummary(state.Player),
		getSliceCarrySummary(state.Player)
	)

	return true
end

local function probeHazards(state)
	if not state.GhostRoot or not state.GhostRoot.Parent then
		return false
	end

	local parts = Workspace:GetPartBoundsInRadius(
		state.GhostRoot.Position,
		state.HazardProbeRadius,
		buildOverlapParams(state)
	)
	for _, part in ipairs(parts) do
		if isDangerousHazardPart(part) then
			return true
		end
	end

	return false
end

local function probeBodyHazards(state)
	if not state.RootPart or not state.RootPart.Parent then
		return false
	end

	local parts = Workspace:GetPartBoundsInRadius(
		state.RootPart.Position,
		state.HazardProbeRadius,
		buildOverlapParams(state)
	)
	for _, part in ipairs(parts) do
		if isDangerousHazardPart(part) then
			return true
		end
	end

	return false
end

local function startProjectionMonitor(state)
	task.spawn(function()
		while activeProjectionsByPlayer[state.Player] == state and not state.Resolved do
			local now = getSharedTimestamp()
			local humanoid = state.Humanoid
			local rootPart = state.RootPart
			local ghostRoot = state.GhostRoot
			local ghostHumanoid = state.GhostHumanoid

			if state.Player.Parent ~= Players or not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart.Parent then
				finishProjection(state, "body_defeated", ghostRoot and ghostRoot.Position or nil, true)
				return
			end

			if not ghostRoot or not ghostRoot.Parent then
				finishProjection(state, "ghost_missing", rootPart.Position, true)
				return
			end

			if not ghostHumanoid or not ghostHumanoid.Parent or ghostHumanoid.Health <= 0 then
				finishProjection(state, "ghost_defeated", ghostRoot.Position, true)
				return
			end

			if now >= state.EndTime then
				finishProjection(state, "duration_elapsed", ghostRoot.Position, true)
				return
			end

			local maxDistanceFromBody = getEffectiveMaxDistanceFromBody(state, now)
			local horizontalDistance = getHorizontalDistance(ghostRoot.Position, rootPart.Position)
			if maxDistanceFromBody > 0 and horizontalDistance > maxDistanceFromBody then
				horoTrace(
					"rangeCheck exceeded player=%s projectionId=%s horizontalDistance=%.2f effectiveMaxDistance=%.2f configuredMaxDistance=%.2f ghostSpeed=%.2f carrySpeed=%.2f carrying=%s",
					state.Player and state.Player.Name or "<nil>",
					tostring(state.ProjectionId),
					horizontalDistance,
					maxDistanceFromBody,
					tonumber(state.MaxDistanceFromBody) or 0,
					tonumber(state.GhostSpeed) or 0,
					tonumber(state.CarrySpeed) or 0,
					tostring(state.Player and hasCarriedReward(state.Player))
				)
				finishProjection(state, "range_exceeded", ghostRoot.Position, true)
				return
			end

			if now >= state.NextHazardProbeAt then
				state.NextHazardProbeAt = now + state.ServerHazardProbeInterval
				if probeHazards(state) then
					finishProjection(state, "hazard_overlap", ghostRoot.Position, true)
					return
				end

				if probeBodyHazards(state) then
					finishProjection(state, "body_hazard_overlap", ghostRoot.Position, true)
					if humanoid.Parent and humanoid.Health > 0 then
						humanoid.Health = 0
						scheduleRespawnIfBodyDead(state)
					end
					return
				end
			end

			if hasCarriedReward(state.Player) and now >= state.NextOwnershipRefreshAt then
				state.NextOwnershipRefreshAt = now + 0.25
				refreshGhostNetworkOwnership(state)
			end

			updateGhostMovement(state)

			task.wait(0.05)
		end
	end)
end

local function tryPickupReward(state)
	local now = os.clock()
	if now < state.NextPickupAt then
		horoTrace(
			"tryPickupReward throttled player=%s projectionId=%s nextPickupIn=%.3f carryAttrs={%s}",
			state.Player and state.Player.Name or "<nil>",
			tostring(state.ProjectionId),
			math.max(0, state.NextPickupAt - now),
			getPlayerCarrySummary(state.Player)
		)
		return false, "pickup_throttled"
	end
	state.NextPickupAt = now + state.PickupThrottle

	local carrierPart = getGhostCarryPart(state)
	if not carrierPart or not carrierPart.Parent then
		horoTrace(
			"tryPickupReward failed player=%s projectionId=%s reason=ghost_carry_part_missing ghostModel=%s",
			state.Player and state.Player.Name or "<nil>",
			tostring(state.ProjectionId),
			formatInstancePath(state.GhostModel)
		)
		return false, "ghost_carry_part_missing"
	end
	horoTrace(
		"tryPickupReward begin player=%s projectionId=%s ghostPos=%s carrierPart=%s carrierPos=%s carryAttrs={%s} sliceState={%s}",
		state.Player and state.Player.Name or "<nil>",
		tostring(state.ProjectionId),
		formatVector3(state.GhostRoot and state.GhostRoot.Position or nil),
		formatInstancePath(carrierPart),
		formatVector3(carrierPart.Position),
		getPlayerCarrySummary(state.Player),
		getSliceCarrySummary(state.Player)
	)

	if hasCarriedReward(state.Player) then
		setProjectionCarryMarker(state.Player, state.ProjectionId)
		CorridorController.AttachCarriedRewardToPart(state.Player, carrierPart)
		updateCarryingAttribute(state)
		scheduleGhostNetworkOwnershipRefresh(state, 10, 0.05)
		horoTrace(
			"tryPickupReward reattachExisting player=%s projectionId=%s carrierPart=%s carryAttrs={%s} sliceState={%s}",
			state.Player and state.Player.Name or "<nil>",
			tostring(state.ProjectionId),
			formatInstancePath(carrierPart),
			getPlayerCarrySummary(state.Player),
			getSliceCarrySummary(state.Player)
		)
		return true, "already_carrying"
	end

	local position = state.GhostRoot.Position
	local claimedMajor = CorridorController.TryClaimRewardNearPosition(
		state.Player,
		position,
		carrierPart,
		state.RewardInteractRadius
	)
	if claimedMajor then
		setProjectionCarryMarker(state.Player, state.ProjectionId)
		updateCarryingAttribute(state)
		scheduleGhostNetworkOwnershipRefresh(state, 12, 0.05)
		beginPickupRangeGrace(state, "major_reward")
		horoTrace(
			"tryPickupReward claimedMajor player=%s projectionId=%s result=%s carrierPart=%s carryAttrs={%s} sliceState={%s}",
			state.Player and state.Player.Name or "<nil>",
			tostring(state.ProjectionId),
			typeof(claimedMajor) == "table" and tostring(claimedMajor.Kind or claimedMajor.RewardType or "table") or tostring(claimedMajor),
			formatInstancePath(carrierPart),
			getPlayerCarrySummary(state.Player),
			getSliceCarrySummary(state.Player)
		)
		return true, "major_reward"
	end

	local brainrotContext = BrainrotInteraction.GetActiveContext()
	local claimedBrainrot = BrainrotInteraction.TryCarryNearPosition(
		brainrotContext,
		state.Player,
		nil,
		position,
		carrierPart,
		state.RewardInteractRadius
	)
	if claimedBrainrot then
		setProjectionCarryMarker(state.Player, state.ProjectionId)
		updateCarryingAttribute(state)
		scheduleGhostNetworkOwnershipRefresh(state, 12, 0.05)
		beginPickupRangeGrace(state, "brainrot")
		horoTrace(
			"tryPickupReward claimedBrainrot player=%s projectionId=%s carrierPart=%s carryAttrs={%s}",
			state.Player and state.Player.Name or "<nil>",
			tostring(state.ProjectionId),
			formatInstancePath(carrierPart),
			getPlayerCarrySummary(state.Player)
		)
		return true, "brainrot"
	end

	horoTrace(
		"tryPickupReward miss player=%s projectionId=%s position=%s radius=%s",
		state.Player and state.Player.Name or "<nil>",
		tostring(state.ProjectionId),
		formatVector3(position),
		tostring(state.RewardInteractRadius)
	)

	return false, "no_reward_in_range"
end

local function handleActionRemote(player, actionName, payload)
	local state = activeProjectionsByPlayer[player]
	if not state or state.Resolved then
		return
	end
	local projectionId = payload and payload.ProjectionId
	if typeof(projectionId) == "string" and projectionId ~= "" and projectionId ~= state.ProjectionId then
		return
	end

	if actionName == "TryPickup" then
		tryPickupReward(state)
		return
	end

	if actionName == "Interrupt" then
		local now = os.clock()
		if now < state.NextClientInterruptAt then
			return
		end
		state.NextClientInterruptAt = now + state.ClientHazardReportThrottle
		finishProjection(state, "client_hazard", state.GhostRoot and state.GhostRoot.Position or nil, true)
		return
	end

	if actionName == "BodyHazard" then
		local now = os.clock()
		if now < state.NextClientInterruptAt then
			return
		end
		state.NextClientInterruptAt = now + state.ClientHazardReportThrottle
		finishProjection(state, "body_hazard", state.GhostRoot and state.GhostRoot.Position or nil, true)
		if state.Humanoid and state.Humanoid.Parent and state.Humanoid.Health > 0 then
			state.Humanoid.Health = 0
			scheduleRespawnIfBodyDead(state)
		end
	end
end

local function ensureActionConnection()
	if actionConnection then
		return
	end

	actionConnection = ensureActionRemote().OnServerEvent:Connect(handleActionRemote)
end

local function buildStartPayload(state)
	refreshProjectionSpeeds(state)
	return {
		Phase = "Start",
		StartedAt = state.StartedAt,
		EndTime = state.EndTime,
		Duration = state.Duration,
		ProjectionId = state.ProjectionId,
		GhostName = state.GhostModel.Name,
		BodyName = state.Character and state.Character.Name or "",
		StartPosition = state.StartPosition,
		BodyPosition = state.RootPart and state.RootPart.Position or nil,
		GhostSpeed = state.GhostSpeed,
		CarrySpeed = state.CarrySpeed,
		MaxDistanceFromBody = getEffectiveMaxDistanceFromBody(state),
		RewardInteractRadius = state.RewardInteractRadius,
		HazardProbeRadius = state.HazardProbeRadius,
	}
end

local function buildRejectedPayload(reason)
	local now = getSharedTimestamp()
	return {
		Phase = "Rejected",
		StartedAt = now,
		EndedAt = now,
		Duration = 0,
		ResolveReason = reason,
	}
end

local function resolveAbilityContext(selfOrContext, maybeContext)
	if type(maybeContext) == "table" then
		return maybeContext
	end

	if type(selfOrContext) == "table" and selfOrContext.Player ~= nil then
		return selfOrContext
	end

	return nil
end

local function getManualCancelProjectionState(context)
	if type(context) ~= "table" then
		return nil
	end
	if context.AbilityName ~= ABILITY_NAME then
		return nil
	end
	if not context.Player then
		return nil
	end

	return activeProjectionsByPlayer[context.Player]
end

function HoroServer.ShouldBypassCooldownCheck(selfOrContext, maybeContext)
	local context = resolveAbilityContext(selfOrContext, maybeContext)
	local activeState = getManualCancelProjectionState(context)
	local shouldBypass = context ~= nil
		and context.AbilityName == ABILITY_NAME
		and context.Player ~= nil
		and activeState ~= nil
	horoTrace(
		"cooldownBypassCheck player=%s ability=%s activeProjection=%s projectionId=%s decision=%s carryAttrs={%s}",
		context and context.Player and context.Player.Name or "<nil>",
		tostring(context and context.AbilityName),
		tostring(activeState ~= nil),
		tostring(activeState and activeState.ProjectionId),
		tostring(shouldBypass),
		getPlayerCarrySummary(context and context.Player)
	)
	return shouldBypass
end

function HoroServer.ShouldBypassRequestThrottle(selfOrContext, maybeContext)
	local context = resolveAbilityContext(selfOrContext, maybeContext)
	local activeState = getManualCancelProjectionState(context)
	local shouldBypass = activeState ~= nil
	horoTrace(
		"requestThrottleBypassCheck player=%s ability=%s activeProjection=%s projectionId=%s decision=%s carryAttrs={%s}",
		context and context.Player and context.Player.Name or "<nil>",
		tostring(context and context.AbilityName),
		tostring(activeState ~= nil),
		tostring(activeState and activeState.ProjectionId),
		tostring(shouldBypass),
		getPlayerCarrySummary(context and context.Player)
	)
	return shouldBypass
end

local function rejectProjectionStart(state, reason)
	if state then
		if state.Player and activeProjectionsByPlayer[state.Player] == state then
			activeProjectionsByPlayer[state.Player] = nil
		end

		disconnectAll(state.Connections)
		restoreBody(state)
		setBodyProjectionAttributes(state, false)
		setProjectionAttributes(state, false)

		if state.GhostModel and state.GhostModel.Parent then
			state.GhostModel:Destroy()
		end
	end

	return buildRejectedPayload(reason or "start_failed"), {
		ApplyCooldown = false,
	}
end

function HoroServer.GhostProjection(context)
	ensureActionConnection()

	local player = context.Player
	local abilityConfig = context.AbilityConfig or {}
	local activeState = activeProjectionsByPlayer[player]
	if activeState then
		horoTrace(
			"ghostProjection manualCancelRequested player=%s projectionId=%s route=manual_cancel carryAttrs={%s} sliceState={%s}",
			player and player.Name or "<nil>",
			tostring(activeState.ProjectionId),
			getPlayerCarrySummary(player),
			getSliceCarrySummary(player)
		)
		local accepted = finishProjection(
			activeState,
			"manual_cancel",
			activeState.GhostRoot and activeState.GhostRoot.Position or nil,
			true
		)
		horoTrace(
			"ghostProjection manualCancelHandled player=%s projectionId=%s accepted=%s carryAttrs={%s} sliceState={%s}",
			player and player.Name or "<nil>",
			tostring(activeState.ProjectionId),
			tostring(accepted == true),
			getPlayerCarrySummary(player),
			getSliceCarrySummary(player)
		)
		return {
			Phase = "Ignored",
			ProjectionId = activeState.ProjectionId,
			ResolveReason = "manual_cancel_pending",
		}, {
			PreserveExistingCooldown = true,
			SuppressActivatedEvent = true,
		}
	end

	horoTrace(
		"ghostProjection castRequested player=%s route=start_cast carryAttrs={%s} sliceState={%s}",
		player and player.Name or "<nil>",
		getPlayerCarrySummary(player),
		getSliceCarrySummary(player)
	)

	if hasCarriedReward(player) then
		horoTrace(
			"ghostProjection rejected player=%s reason=already_carrying_reward carryAttrs={%s} sliceState={%s}",
			player and player.Name or "<nil>",
			getPlayerCarrySummary(player),
			getSliceCarrySummary(player)
		)
		return buildRejectedPayload("already_carrying_reward"), {
			ApplyCooldown = false,
		}
	end

	projectionSequence += 1
	local startedAt = getSharedTimestamp()
	local duration = clampNumber(abilityConfig.Duration, DEFAULT_DURATION, 0.5, 12)
	local state = {
		Player = player,
		Character = context.Character,
		Humanoid = context.Humanoid,
		RootPart = context.RootPart,
		FruitName = FRUIT_NAME,
		AbilityConfig = abilityConfig,
		StartedAt = startedAt,
		EndTime = startedAt + duration,
		Duration = duration,
		StartPosition = context.RootPart.Position,
		GhostSpeed = clampNumber(abilityConfig.GhostSpeed, DEFAULT_GHOST_SPEED, 2, MAX_PROJECTION_MOVE_SPEED),
		CarrySpeed = clampNumber(abilityConfig.CarrySpeed, DEFAULT_CARRY_SPEED, 1, MAX_PROJECTION_MOVE_SPEED),
		MaxDistanceFromBody = clampNumber(abilityConfig.MaxDistanceFromBody, DEFAULT_MAX_DISTANCE_FROM_BODY, 8, 180),
		RewardInteractRadius = clampNumber(abilityConfig.RewardInteractRadius, DEFAULT_REWARD_INTERACT_RADIUS, 3, 24),
		HazardProbeRadius = clampNumber(abilityConfig.HazardProbeRadius, DEFAULT_HAZARD_PROBE_RADIUS, 1, 10),
		ServerHazardProbeInterval = clampNumber(
			abilityConfig.ServerHazardProbeInterval,
			DEFAULT_SERVER_HAZARD_PROBE_INTERVAL,
			0.03,
			0.5
		),
		ClientHazardReportThrottle = clampNumber(abilityConfig.ClientHazardReportThrottle, 0.12, 0.05, 1),
		PickupThrottle = clampNumber(abilityConfig.PickupThrottle, DEFAULT_PICKUP_THROTTLE, 0.05, 1),
		PickupRangeGraceDuration = clampNumber(
			abilityConfig.PickupRangeGraceDuration,
			DEFAULT_PICKUP_RANGE_GRACE_DURATION,
			0,
			2
		),
		PickupRangeGraceDistance = clampNumber(
			abilityConfig.PickupRangeGraceDistance,
			DEFAULT_PICKUP_RANGE_GRACE_DISTANCE,
			0,
			40
		),
		NextPickupAt = 0,
		PickupRangeGraceUntil = 0,
		NextClientInterruptAt = 0,
		NextHazardProbeAt = startedAt,
		NextOwnershipRefreshAt = startedAt,
		Sequence = projectionSequence,
		ProjectionId = string.format("%d:%d", player.UserId, projectionSequence),
		Connections = {},
		EmitEffect = context.EmitEffect,
		StartAbilityCooldown = context.StartAbilityCooldown,
	}
	refreshProjectionSpeeds(state)

	local ghostModel, ghostRoot = createGhostModel(state)
	if not ghostModel or not ghostRoot then
		return buildRejectedPayload("ghost_create_failed"), {
			ApplyCooldown = false,
		}
	end

	state.GhostModel = ghostModel
	state.GhostRoot = ghostRoot
	state.GhostHumanoid = ghostModel:FindFirstChildOfClass("Humanoid")
	state.GhostCarryPart = getGhostCarryPart(state)

	local ok = xpcall(function()
		setBodyProjectionAttributes(state, true)
		lockBody(state)
		activeProjectionsByPlayer[player] = state
		setProjectionAttributes(state, true)
		updateGhostMovement(state)
		refreshGhostNetworkOwnership(state)
		attachGhostTouchListeners(state)
		startProjectionMonitor(state)
	end, debug.traceback)
	if not ok then
		return rejectProjectionStart(state, "start_failed")
	end

	return buildStartPayload(state), {
		ApplyCooldown = false,
	}
end

function HoroServer.IsProjecting(player)
	return activeProjectionsByPlayer[player] ~= nil
end

function HoroServer.InterruptActiveProjection(player, reason, dropPosition)
	local state = activeProjectionsByPlayer[player]
	if not state then
		return false
	end

	return finishProjection(
		state,
		tostring(reason or "external_interrupt"),
		if typeof(dropPosition) == "Vector3" then dropPosition else (state.GhostRoot and state.GhostRoot.Position or nil),
		true
	)
end

function HoroServer.ClearRuntimeState(player)
	local state = activeProjectionsByPlayer[player]
	if state then
		finishProjection(state, "manual_cleanup", state.GhostRoot and state.GhostRoot.Position or nil, true)
	end
end

function HoroServer.GetLegacyHandler()
	return HoroServer
end

ensureActionConnection()

Players.PlayerRemoving:Connect(function(player)
	local state = activeProjectionsByPlayer[player]
	if state then
		finishProjection(state, "player_removing", state.GhostRoot and state.GhostRoot.Position or nil, true)
	end
end)

return HoroServer
