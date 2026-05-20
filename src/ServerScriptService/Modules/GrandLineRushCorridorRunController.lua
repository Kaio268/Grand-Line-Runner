local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CarriedRewardVisuals = require(Modules:WaitForChild("CarriedRewardVisuals"))
local Economy = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestVisuals = require(Modules:WaitForChild("GrandLineRushChestVisuals"))
local MapResolver = require(Modules:WaitForChild("MapResolver"))
local SpawnPartsConfig = require(Modules:WaitForChild("Configs"):WaitForChild("SpawnParts"))
local PopUpModule = require(Modules:WaitForChild("PopUpModule"))
local SliceService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("GrandLineRushVerticalSliceService"))

local Controller = {}

local started = false
local rewardObjectsByUserId = {}
local rewardPlacementsByUserId = {}
local sharedChestNodesById = {}
local carriedSharedChestByUserId = {}
local extractionTouchDebounce = {}
local sharedChestSequence = 0
local nextSharedChestRespawnAt = 0
local sharedChestNonGoldStreak = 0
local sharedChestSpawnPartCache = nil
local worldRandom = Random.new()
local DEBUG_TRACE = RunService:IsStudio() and game:GetAttribute("CorridorRunDebugTrace") == true
local loggedExtractionTouchByPlayer = {}
local VALID_SPAWN_RARITY_NAMES = SpawnPartsConfig.RarityTier or {}

local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local INFO_COLOR = Color3.fromRGB(119, 217, 255)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local HORO_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local HORO_GHOSTS_FOLDER_NAME = "HoroGhosts"
local CARRIED_CREW_MEMBER_ATTRIBUTE = "CarriedCrewMember"
local CARRY_VISUAL_SPACING = CarriedRewardVisuals.DefaultSpacing
local REWARD_CARRY_PREVIOUS_CAN_QUERY_ATTRIBUTE = "RewardCarryPreviousCanQuery"
local MOGU_BURROW_RAYCAST_IGNORE_ATTRIBUTE = "MoguBurrowIgnoreRaycast"

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

local function mapTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[MAP TRACE] " .. message, ...))
end

local function waveTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[WAVE TRACE] " .. message, ...))
end

local function zoneTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[ZONE TRACE] " .. message, ...))
end

local function runTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[RUN TRACE] " .. message, ...))
end

local function horoCarryTrace(message, ...)
	if not DEBUG_TRACE then
		return
	end

	print(string.format("[HORO CARRY TRACE] " .. tostring(message), ...))
end

local function getPlayerCarrySummary(player)
	if not player then
		return "player=<nil>"
	end

	return string.format(
		"attrMajor=%s attrMajorName=%s attrCrewMember=%s horoActive=%s horoProjectionId=%s horoCarrying=%s",
		tostring(player:GetAttribute("CarriedMajorRewardType")),
		tostring(player:GetAttribute("CarriedMajorRewardDisplayName")),
		tostring(player:GetAttribute(CARRIED_CREW_MEMBER_ATTRIBUTE)),
		tostring(player:GetAttribute("HoroProjectionActive")),
		tostring(player:GetAttribute("HoroProjectionId")),
		tostring(player:GetAttribute("HoroProjectionCarryingReward"))
	)
end

local function getRunRewardSummary(player)
	if not player then
		return "runtimePlayer=<nil>"
	end

	local state = SliceService.GetState(player)
	local runState = state and state.Run or {}
	local carriedReward = runState.CarriedReward
	local spawnedReward = runState.SpawnedReward
	local carriedCount = 0
	for _, slot in ipairs(runState.CarrySlots or {}) do
		if slot.Occupied == true then
			carriedCount += 1
		end
	end
	return string.format(
		"inRun=%s carried=%s carriedCount=%d carriedType=%s spawned=%s spawnedType=%s spawnedDrop=%s",
		tostring(runState.InRun),
		tostring(carriedCount > 0 or carriedReward ~= nil),
		carriedCount,
		tostring(carriedReward and carriedReward.RewardType or nil),
		tostring(spawnedReward ~= nil),
		tostring(spawnedReward and spawnedReward.RewardType or nil),
		formatVector3(spawnedReward and spawnedReward.WorldDropPosition or nil)
	)
end

local function hasOccupiedCarrySlots(runState)
	for _, slot in ipairs((runState and runState.CarrySlots) or {}) do
		if slot.Occupied == true then
			return true
		end
	end

	return false
end

local function sendPopup(player, text, color, isError)
	if not player or player.Parent ~= Players then
		return
	end

	PopUpModule:Server_SendPopUp(player, text, color or INFO_COLOR, STROKE_COLOR, 3, isError == true)
end

local function buildResponseMessage(response, fallbackMessage)
	if response and type(response.message) == "string" and response.message ~= "" then
		return response.message
	end

	return fallbackMessage
end

local function getMapHitBox()
	local hitBox = MapResolver.GetRefs().HitBox
	if hitBox and hitBox:IsA("BasePart") then
		return hitBox
	end

	return nil
end

local function getOrCreateFolder(parent, name)
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

local function getOrCreatePart(parent, name)
	local part = parent:FindFirstChild(name)
	if part and part:IsA("BasePart") then
		return part
	end

	if part then
		part:Destroy()
	end

	part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = true
	part.Transparency = 1
	part.Parent = parent
	return part
end

local function configurePrompt(prompt, actionText, objectText)
	local worldConfig = Economy.VerticalSlice.WorldRun
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = tonumber(worldConfig.PromptHoldDuration) or 0.25
	prompt.MaxActivationDistance = tonumber(worldConfig.PromptMaxDistance) or 14
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.ClickablePrompt = false
end

local function getOrCreatePrompt(parent, name, actionText, objectText)
	local prompt = parent:FindFirstChild(name)
	if prompt and prompt:IsA("ProximityPrompt") then
		configurePrompt(prompt, actionText, objectText)
		return prompt
	end

	if prompt then
		prompt:Destroy()
	end

	prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	configurePrompt(prompt, actionText, objectText)
	prompt.Parent = parent
	return prompt
end

local function getLaneDirections(startPart, endPart)
	local forward = startPart.Position - endPart.Position
	if forward.Magnitude < 0.001 then
		forward = endPart.CFrame.LookVector
	end
	forward = forward.Unit

	local side = forward:Cross(Vector3.yAxis)
	if side.Magnitude < 0.001 then
		side = endPart.CFrame.RightVector
	end
	side = side.Unit

	return forward, side
end

local function getLaneOffset(userId)
	local worldConfig = Economy.VerticalSlice.WorldRun
	local spacing = tonumber(worldConfig.RewardLaneSpacing) or 5
	local maxOffset = tonumber(worldConfig.RewardMaxLaneOffset) or 10
	local slot = (tonumber(userId) or 0) % 5
	local centered = slot - 2
	return math.clamp(centered * spacing, -maxOffset, maxOffset)
end

local function getRewardCFrame(player, rewardState, startPart, endPart)
	local worldConfig = Economy.VerticalSlice.WorldRun
	local alphaByBand = worldConfig.RewardAlphaByDepthBand or {}
	local depthBand = rewardState and rewardState.DepthBand or Economy.VerticalSlice.DefaultDepthBand
	local alpha = tonumber(alphaByBand[depthBand]) or tonumber(alphaByBand[Economy.VerticalSlice.DefaultDepthBand]) or 0.5
	if rewardState and rewardState.RewardType == "Chest" then
		local debugChestAlphaOverride = tonumber(worldConfig.DebugChestSpawnAlphaOverride)
		if debugChestAlphaOverride ~= nil then
			alpha = debugChestAlphaOverride
		end
	end
	alpha = math.clamp(alpha, 0, 1)

	local basePosition = endPart.Position:Lerp(startPart.Position, alpha)
	local _, side = getLaneDirections(startPart, endPart)
	local heightOffset = tonumber(worldConfig.RewardHeightOffset) or 3.5
	local laneOffset = getLaneOffset(player.UserId)
	local position = basePosition + (side * laneOffset) + Vector3.new(0, heightOffset, 0)

	return CFrame.new(position)
end

local function buildRewardKey(rewardState)
	if not rewardState then
		return "none"
	end

	if rewardState.RewardType == "Chest" then
		return string.format("Chest:%s:%s", tostring(rewardState.Tier), tostring(rewardState.DepthBand))
	end

	return string.format("Crew:%s:%s:%s", tostring(rewardState.Rarity), tostring(rewardState.CrewName), tostring(rewardState.DepthBand))
end

local function getRewardObjectMap(userId)
	local current = rewardObjectsByUserId[userId]
	if typeof(current) == "table" and current.__MultiCarryObjects == true then
		return current
	end

	local map = {
		__MultiCarryObjects = true,
	}
	if typeof(current) == "Instance" then
		map.spawned = current
	end
	rewardObjectsByUserId[userId] = map
	return map
end

local function getRewardObject(userId, objectKey)
	local map = getRewardObjectMap(userId)
	return map[tostring(objectKey or "spawned")]
end

local function setRewardObject(userId, objectKey, object)
	local map = getRewardObjectMap(userId)
	map[tostring(objectKey or "spawned")] = object
end

local function destroyRewardObject(userId, objectKey)
	local map = rewardObjectsByUserId[userId]
	if typeof(map) ~= "table" or map.__MultiCarryObjects ~= true then
		if map and map.Parent then
			map:Destroy()
		end
		rewardObjectsByUserId[userId] = nil
		rewardPlacementsByUserId[userId] = nil
		return
	end

	if objectKey ~= nil then
		local key = tostring(objectKey)
		local object = map[key]
		if object and object.Parent then
			object:Destroy()
		end
		map[key] = nil
		return
	end

	for key, object in pairs(map) do
		if key ~= "__MultiCarryObjects" and object and object.Parent then
			object:Destroy()
		end
	end
	rewardObjectsByUserId[userId] = nil
	rewardPlacementsByUserId[userId] = nil
end

local function destroyCarriedSharedChest(userId)
	local carried = carriedSharedChestByUserId[userId]
	if not carried then
		return
	end

	local object = carried.Object
	if object and object.Parent then
		object:Destroy()
	end

	carriedSharedChestByUserId[userId] = nil
end

local function getObjectRootPart(object)
	if not object then
		return nil
	end

	if object:IsA("BasePart") then
		return object
	end

	if object:IsA("Model") then
		if object.PrimaryPart then
			return object.PrimaryPart
		end

		local part = object:FindFirstChildWhichIsA("BasePart", true)
		if part then
			pcall(function()
				object.PrimaryPart = part
			end)
			return object.PrimaryPart or part
		end
	end

	return nil
end

local function forEachRewardPart(object, callback)
	if not object or typeof(callback) ~= "function" then
		return
	end

	if object:IsA("BasePart") then
		callback(object)
		return
	end

	for _, descendant in ipairs(object:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

local function getObjectBoundingBox(object)
	if object:IsA("Model") then
		return object:GetBoundingBox()
	end

	if object:IsA("BasePart") then
		return object.CFrame, object.Size
	end

	return CFrame.new(), Vector3.new(2, 2, 2)
end

local function getObjectPivot(object)
	if object:IsA("Model") then
		return object:GetPivot()
	end

	if object:IsA("BasePart") then
		return object.CFrame
	end

	return CFrame.new()
end

local function setObjectCFrame(object, cf)
	if not object or not cf then
		return
	end

	if object:IsA("Model") then
		object:PivotTo(cf)
	elseif object:IsA("BasePart") then
		object.CFrame = cf
	end
end

local function getSpawnPartFlatFrame(spawnPart)
	local lookVector = spawnPart.CFrame.LookVector
	local direction = Vector3.new(lookVector.X, 0, lookVector.Z)
	if direction.Magnitude < 1e-4 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end

	return CFrame.lookAt(spawnPart.Position, spawnPart.Position + direction, Vector3.yAxis)
end

local function worldToSpawnLocalXZ(spawnPart, worldPosition)
	local flatFrame = getSpawnPartFlatFrame(spawnPart)
	local relative = flatFrame:PointToObjectSpace(worldPosition)
	return Vector2.new(relative.X, relative.Z)
end

local function clampLocalXZToSpawnPart(spawnPart, object, localXZ)
	local _, boxSize = getObjectBoundingBox(object)
	local effectiveX = spawnPart.Size.X * 0.9
	local effectiveZ = spawnPart.Size.Z * 0.9
	local halfX = math.max(0, (effectiveX / 2) - (boxSize.X / 2))
	local halfZ = math.max(0, (effectiveZ / 2) - (boxSize.Z / 2))

	return Vector2.new(
		math.clamp(localXZ.X, -halfX, halfX),
		math.clamp(localXZ.Y, -halfZ, halfZ)
	)
end

local function computeObjectPivotOnSpawnPart(object, spawnPart, localXZ, yaw)
	local boxCF, boxSize = getObjectBoundingBox(object)
	local offset = getObjectPivot(object):ToObjectSpace(boxCF)
	local flatCF = getSpawnPartFlatFrame(spawnPart)
	local surface = spawnPart.Position
		+ Vector3.yAxis * (spawnPart.Size.Y / 2)
		+ flatCF.RightVector * localXZ.X
		+ flatCF.LookVector * localXZ.Y
	local rotOnly = (flatCF - flatCF.Position) * CFrame.Angles(0, yaw, 0)
	local desiredBoxCF = CFrame.new(surface + Vector3.yAxis * (boxSize.Y / 2)) * rotOnly
	return desiredBoxCF * offset:Inverse()
end

local function getSpawnPartsFolder()
	return MapResolver.GetRefs().SpawnFolder
end

local function isValidSpawnRarityPart(spawnPart)
	return spawnPart
		and spawnPart:IsA("BasePart")
		and VALID_SPAWN_RARITY_NAMES[tostring(spawnPart.Name)] ~= nil
end

local function collectSpawnRarityParts(root, spawnParts)
	if not root then
		return
	end

	if isValidSpawnRarityPart(root) then
		spawnParts[#spawnParts + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isValidSpawnRarityPart(descendant) then
			spawnParts[#spawnParts + 1] = descendant
		end
	end
end

local function getBiomeSpawnParts()
	local refs = MapResolver.GetRefs()
	local mapRoot = refs.MapRoot
	local biomesRoot = refs.Biomes or (mapRoot and mapRoot:FindFirstChild("Biomes"))
	local spawnParts = {}

	if biomesRoot then
		waveTrace(
			"chestSpawnDiscovery mode=Biomes map=%s biomesRoot=%s topLevelBiomeCount=%s",
			formatInstancePath(mapRoot),
			formatInstancePath(biomesRoot),
			tostring(#biomesRoot:GetChildren())
		)
		for _, biomeContainer in ipairs(biomesRoot:GetChildren()) do
			local innerBiome = biomeContainer:FindFirstChild(biomeContainer.Name)
			local scanRoot = innerBiome or biomeContainer
			waveTrace(
				"chestSpawnDiscovery biome=%s scanRoot=%s innerBiome=%s",
				formatInstancePath(biomeContainer),
				formatInstancePath(scanRoot),
				formatInstancePath(innerBiome)
			)
			collectSpawnRarityParts(scanRoot, spawnParts)
		end
	else
		local spawnFolder = getSpawnPartsFolder()
		waveTrace(
			"chestSpawnDiscovery mode=LegacySpawnFolder map=%s spawnFolder=%s",
			formatInstancePath(mapRoot),
			formatInstancePath(spawnFolder)
		)
		if spawnFolder then
			collectSpawnRarityParts(spawnFolder, spawnParts)
		end
	end

	waveTrace("chestSpawnDiscovery resultCount=%s", tostring(#spawnParts))
	return spawnParts
end

local function getAllCrewMemberSpawnContexts()
	local contexts = {}

	for _, spawnPart in ipairs(getBiomeSpawnParts()) do
		local crewMembersFolder = spawnPart:FindFirstChild("CrewMembers")
		local hadCrewMember = false
		if crewMembersFolder then
			for _, candidate in ipairs(crewMembersFolder:GetChildren()) do
				if getObjectRootPart(candidate) then
					hadCrewMember = true
					contexts[#contexts + 1] = {
						SpawnPart = spawnPart,
						CrewMember = candidate,
					}
				end
			end
		end

		if not hadCrewMember then
			contexts[#contexts + 1] = {
				SpawnPart = spawnPart,
				CrewMember = nil,
			}
		end
	end

	return contexts
end

local function chooseRandomCrewMemberSpawnContext()
	local contexts = getAllCrewMemberSpawnContexts()
	if #contexts == 0 then
		return nil
	end

	local chosen = contexts[worldRandom:NextInteger(1, #contexts)]
	local chosenCrewMemberRoot = getObjectRootPart(chosen.CrewMember)
	waveTrace(
		"chestSpawnContext chosenCount=%s chosenSpawnPart=%s chosenSpawnPartPos=%s sourceCrewMember=%s sourceCrewMemberPos=%s",
		tostring(#contexts),
		formatInstancePath(chosen.SpawnPart),
		formatVector3(chosen.SpawnPart and chosen.SpawnPart.Position or nil),
		formatInstancePath(chosen.CrewMember),
		formatVector3(chosenCrewMemberRoot and chosenCrewMemberRoot.Position or nil)
	)
	return chosen
end

local function getOccupiedSpawnOffsets(spawnPart, ignoreInstance)
	local offsets = {}
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return offsets
	end

	local crewMembersFolder = spawnPart:FindFirstChild("CrewMembers")
	if not crewMembersFolder then
		return offsets
	end

	for _, candidate in ipairs(crewMembersFolder:GetChildren()) do
		if candidate ~= ignoreInstance then
			local rootPart = getObjectRootPart(candidate)
			if rootPart then
				offsets[#offsets + 1] = worldToSpawnLocalXZ(spawnPart, rootPart.Position)
			end
		end
	end

	return offsets
end

local function isOffsetClear(candidateOffset, occupiedOffsets, minDistance)
	for _, occupied in ipairs(occupiedOffsets) do
		if (candidateOffset - occupied).Magnitude < minDistance then
			return false
		end
	end

	return true
end

local function getOrCreateChestSpawnPlacement(player, rewardObject)
	local existing = rewardPlacementsByUserId[player.UserId]
	if existing and existing.SpawnPart and existing.SpawnPart.Parent then
		return existing
	end

	local spawnContext = chooseRandomCrewMemberSpawnContext()
	if not spawnContext or not spawnContext.SpawnPart then
		waveTrace("chestPlacement skipped player=%s reason=no_spawn_context", player.Name)
		return nil
	end

	local spawnPart = spawnContext.SpawnPart
	local baseOffset = Vector2.zero
	if spawnContext.CrewMember then
		local crewMemberRoot = getObjectRootPart(spawnContext.CrewMember)
		if crewMemberRoot then
			baseOffset = worldToSpawnLocalXZ(spawnPart, crewMemberRoot.Position)
		end
	end

	local _, boxSize = getObjectBoundingBox(rewardObject)
	local spacing = math.max(4, math.max(boxSize.X, boxSize.Z) * 1.35)
	local candidateOffsets = {
		baseOffset + Vector2.new(spacing, 0),
		baseOffset + Vector2.new(-spacing, 0),
		baseOffset + Vector2.new(0, spacing),
		baseOffset + Vector2.new(0, -spacing),
		baseOffset + Vector2.new(spacing * 0.7, spacing * 0.7),
		baseOffset + Vector2.new(-spacing * 0.7, spacing * 0.7),
		baseOffset + Vector2.new(spacing * 0.7, -spacing * 0.7),
		baseOffset + Vector2.new(-spacing * 0.7, -spacing * 0.7),
	}
	if not spawnContext.CrewMember then
		candidateOffsets[#candidateOffsets + 1] = Vector2.zero
	end

	local occupiedOffsets = getOccupiedSpawnOffsets(spawnPart, spawnContext.CrewMember)
	local chosenOffset = clampLocalXZToSpawnPart(spawnPart, rewardObject, candidateOffsets[#candidateOffsets] or Vector2.zero)
	for _, candidateOffset in ipairs(candidateOffsets) do
		local clamped = clampLocalXZToSpawnPart(spawnPart, rewardObject, candidateOffset)
		if isOffsetClear(clamped, occupiedOffsets, math.max(3.5, spacing * 0.8)) then
			chosenOffset = clamped
			break
		end
	end

	local placement = {
		SpawnPart = spawnPart,
		LocalXZ = chosenOffset,
		Yaw = 0,
		SourceCrewMemberName = spawnContext.CrewMember and spawnContext.CrewMember.Name or nil,
	}
	rewardPlacementsByUserId[player.UserId] = placement
	waveTrace(
		"chestPlacement player=%s spawnPart=%s spawnPartPos=%s sourceCrewMember=%s localXZ=%s",
		player.Name,
		formatInstancePath(spawnPart),
		formatVector3(spawnPart.Position),
		tostring(placement.SourceCrewMemberName),
		formatVector3(Vector3.new(chosenOffset.X, 0, chosenOffset.Y))
	)
	return placement
end

local function buildChestPlacementHint(placement)
	if not placement or not placement.SpawnPart then
		return nil
	end

	if placement.SourceCrewMemberName and placement.SourceCrewMemberName ~= "" then
		return string.format(
			"Chest spawned on %s near %s.",
			tostring(placement.SpawnPart.Name),
			tostring(placement.SourceCrewMemberName)
		)
	end

	return string.format("Chest spawned on %s.", tostring(placement.SpawnPart.Name))
end

local function getDroppedRewardPivot(rewardObject, worldPosition, ignoreInstances)
	local castOrigin = worldPosition + Vector3.new(0, 10, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { rewardObject }
	if typeof(ignoreInstances) == "table" then
		for _, instance in ipairs(ignoreInstances) do
			params.FilterDescendantsInstances[#params.FilterDescendantsInstances + 1] = instance
		end
	end
	params.IgnoreWater = true

	local result = Workspace:Raycast(castOrigin, Vector3.new(0, -30, 0), params)
	local surfacePosition = result and result.Position or worldPosition

	local boxCF, boxSize = getObjectBoundingBox(rewardObject)
	local pivot = getObjectPivot(rewardObject)
	local offset = pivot:ToObjectSpace(boxCF)
	local rotation = pivot - pivot.Position
	local desiredBoxCF = CFrame.new(surfacePosition + Vector3.new(0, boxSize.Y / 2, 0)) * rotation

	return desiredBoxCF * offset:Inverse(), {
		CastOrigin = castOrigin,
		SurfacePosition = surfacePosition,
		HitInstance = result and result.Instance or nil,
		UsedFallback = result == nil,
		SnapMode = if result then "raycast_surface" else "fallback_requested_position",
	}
end

local function positionRewardObject(player, rewardObject, rewardState, startPart, endPart)
	if rewardState and typeof(rewardState.WorldDropPosition) == "Vector3" then
		local character = player.Character
		local ignoreInstances = character and { character } or nil
		local pivot, dropInfo = getDroppedRewardPivot(rewardObject, rewardState.WorldDropPosition, ignoreInstances)
		setObjectCFrame(rewardObject, pivot)
		horoCarryTrace(
			"dropResolve player=%s reward=%s rewardType=%s requestedDrop=%s finalPivot=%s snapMode=%s fallbackGroundPlacement=%s hitInstance=%s carryAttrs={%s} runtime={%s}",
			player and player.Name or "<nil>",
			formatInstancePath(rewardObject),
			tostring(rewardState and rewardState.RewardType),
			formatVector3(rewardState.WorldDropPosition),
			formatVector3(getObjectPivot(rewardObject).Position),
			tostring(dropInfo and dropInfo.SnapMode),
			tostring(dropInfo and dropInfo.UsedFallback == true),
			formatInstancePath(dropInfo and dropInfo.HitInstance or nil),
			getPlayerCarrySummary(player),
			getRunRewardSummary(player)
		)
		return nil
	end

	if rewardState and rewardState.RewardType == "Chest" then
		local chestPlacement = getOrCreateChestSpawnPlacement(player, rewardObject)
		if chestPlacement and chestPlacement.SpawnPart and chestPlacement.SpawnPart.Parent then
			setObjectCFrame(
				rewardObject,
				computeObjectPivotOnSpawnPart(
					rewardObject,
					chestPlacement.SpawnPart,
					chestPlacement.LocalXZ,
					tonumber(chestPlacement.Yaw) or 0
				)
			)
			return buildChestPlacementHint(chestPlacement)
		end
	end

	setObjectCFrame(rewardObject, getRewardCFrame(player, rewardState, startPart, endPart))
	return nil
end

local function setRewardHeldPhysics(object, held)
	local changedQueryCount = 0
	forEachRewardPart(object, function(part)
		part.Anchored = not held
		part.CanCollide = false
		part.CanTouch = false
		if held then
			if part:GetAttribute(REWARD_CARRY_PREVIOUS_CAN_QUERY_ATTRIBUTE) == nil then
				part:SetAttribute(REWARD_CARRY_PREVIOUS_CAN_QUERY_ATTRIBUTE, part.CanQuery)
			end
			if part.CanQuery ~= false then
				changedQueryCount += 1
			end
			part.CanQuery = false
		else
			local previousCanQuery = part:GetAttribute(REWARD_CARRY_PREVIOUS_CAN_QUERY_ATTRIBUTE)
			if previousCanQuery ~= nil then
				part.CanQuery = previousCanQuery == true
				part:SetAttribute(REWARD_CARRY_PREVIOUS_CAN_QUERY_ATTRIBUTE, nil)
				changedQueryCount += 1
			end
		end
		part.Massless = held
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end)
	if object then
		object:SetAttribute(MOGU_BURROW_RAYCAST_IGNORE_ATTRIBUTE, if held then true else nil)
	end
	if changedQueryCount > 0 then
		horoCarryTrace(
			"reward query state updated reward=%s held=%s parts=%d moguIgnore=%s",
			formatInstancePath(object),
			tostring(held == true),
			changedQueryCount,
			tostring(object and object:GetAttribute(MOGU_BURROW_RAYCAST_IGNORE_ATTRIBUTE) == true)
		)
	end
end

local function clearCarryWeld(rootPart)
	if not rootPart then
		return
	end

	local weld = rootPart:FindFirstChild("RewardCarryWeld")
	if weld and weld:IsA("WeldConstraint") then
		weld:Destroy()
	end
end

local function getActiveHoroCarrierPart(player)
	if not player or player.Parent ~= Players then
		return nil
	end
	if player:GetAttribute("HoroProjectionActive") ~= true then
		return nil
	end

	local projectionId = player:GetAttribute("HoroProjectionId")
	if typeof(projectionId) ~= "string" or projectionId == "" then
		return nil
	end

	local effectsFolder = Workspace:FindFirstChild(HORO_EFFECTS_FOLDER_NAME)
	local ghostsFolder = effectsFolder and effectsFolder:FindFirstChild(HORO_GHOSTS_FOLDER_NAME)
	if not ghostsFolder then
		return nil
	end

	for _, ghostModel in ipairs(ghostsFolder:GetChildren()) do
		if ghostModel:IsA("Model")
			and ghostModel:GetAttribute("ProjectionId") == projectionId
			and tonumber(ghostModel:GetAttribute("OwnerUserId")) == player.UserId
		then
			for _, partName in ipairs({ "Head", "UpperTorso", "Torso", "HumanoidRootPart" }) do
				local part = ghostModel:FindFirstChild(partName, true)
				if part and part:IsA("BasePart") and part.Parent then
					return part
				end
			end

			local fallbackPart = ghostModel.PrimaryPart or ghostModel:FindFirstChildWhichIsA("BasePart", true)
			if fallbackPart and fallbackPart:IsA("BasePart") and fallbackPart.Parent then
				return fallbackPart
			end
		end
	end

	return nil
end

local function computeHeadRotOnly(head)
	local lookVector = head.CFrame.LookVector
	local direction = Vector3.new(lookVector.X, 0, lookVector.Z)
	if direction.Magnitude < 1e-4 then
		direction = Vector3.new(0, 0, -1)
	else
		direction = direction.Unit
	end

	local rotation = CFrame.lookAt(Vector3.zero, direction, Vector3.yAxis)
	return rotation - rotation.Position
end

local function computeCarrierRotOnly(carrierPart)
	if not carrierPart or not carrierPart:IsA("BasePart") then
		return CFrame.new()
	end

	return computeHeadRotOnly(carrierPart)
end

local function computePivotBottomOnPoint(object, point, rotOnly)
	local boxCF, boxSize = getObjectBoundingBox(object)
	local offset = getObjectPivot(object):ToObjectSpace(boxCF)
	local desiredBoxCF = CFrame.new(point + Vector3.yAxis * (boxSize.Y / 2)) * rotOnly
	return desiredBoxCF * offset:Inverse()
end

local function prepareTemplateClone(instance)
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant.Enabled = false
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
end

local function createDefaultRewardPart(rewardState)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = true
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Shape = if rewardState.RewardType == "Chest" then Enum.PartType.Block else Enum.PartType.Ball
	part.Size = if rewardState.RewardType == "Chest" then Vector3.new(3, 3, 3) else Vector3.new(3.25, 3.25, 3.25)
	part.Color = if rewardState.RewardType == "Chest" then Color3.fromRGB(214, 155, 74) else Color3.fromRGB(91, 143, 255)
	return part
end

local function createRewardInstance(rewardState)
	if rewardState.RewardType == "Chest" then
		local chestModel = ChestVisuals.CreateWorldModel(rewardState.Tier, "ChestPlaceholder")
		prepareTemplateClone(chestModel)
		return chestModel
	end

	return createDefaultRewardPart(rewardState)
end

local function addRewardBillboard(part, rewardState, player)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RewardBillboard"
	billboard.Size = UDim2.fromOffset(180, 54)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 28)
	title.Text = tostring(rewardState.DisplayName or "Major Reward")
	title.TextScaled = true
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0
	title.Parent = billboard

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Position = UDim2.fromOffset(0, 28)
	subtitle.Size = UDim2.new(1, 0, 0, 22)
	if rewardState and rewardState.RewardType == "Chest" then
		subtitle.Text = "Treasure chest"
	elseif player then
		subtitle.Text = string.format("%s's reward", player.DisplayName)
	else
		subtitle.Text = "Shared corridor reward"
	end
	subtitle.TextScaled = true
	subtitle.Font = Enum.Font.GothamMedium
	subtitle.TextColor3 = Color3.fromRGB(224, 236, 255)
	subtitle.TextStrokeTransparency = 0.15
	subtitle.Parent = billboard
end

local function shouldShowChestDebugBeacon()
	local sharedConfig = ((Economy.VerticalSlice.WorldRun or {}).SharedChests or {})
	return sharedConfig.DebugBeaconEnabled == true
		or (RunService:IsStudio() and game:GetAttribute("ChestDebugBeaconEnabled") == true)
end

local function addChestDebugBeacon(rootPart)
	if not shouldShowChestDebugBeacon() then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "ChestDebugAttachment"
	attachment.Parent = rootPart

	local beacon = Instance.new("BillboardGui")
	beacon.Name = "ChestDebugBeacon"
	beacon.Size = UDim2.fromOffset(180, 36)
	beacon.StudsOffset = Vector3.new(0, 10, 0)
	beacon.AlwaysOnTop = true
	beacon.Parent = rootPart

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Text = "TEST CHEST"
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.fromRGB(255, 239, 138)
	text.TextStrokeTransparency = 0
	text.Parent = beacon

	local pillar = Instance.new("Part")
	pillar.Name = "ChestDebugPillar"
	pillar.Anchored = true
	pillar.CanCollide = false
	pillar.CanTouch = false
	pillar.CanQuery = false
	pillar.Material = Enum.Material.Neon
	pillar.Color = Color3.fromRGB(255, 225, 102)
	pillar.Transparency = 0.2
	pillar.Size = Vector3.new(1.2, 30, 1.2)
	pillar.CFrame = rootPart.CFrame + Vector3.new(0, 15, 0)
	pillar.Parent = rootPart

	local weld = Instance.new("WeldConstraint")
	weld.Name = "ChestDebugPillarWeld"
	weld.Part0 = rootPart
	weld.Part1 = pillar
	weld.Parent = pillar
end

local function configureRewardPickupPrompt(prompt, rewardState)
	configurePrompt(prompt, tostring(rewardState.DisplayName or "Major Reward"), "Hold to Get")
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.HoldDuration = 0.7
	prompt.MaxActivationDistance = 12
end

local function applySpawnedRewardState(player, rewardObject, rootPart, rewardState, rewardFolder, startPart, endPart)
	clearCarryWeld(rootPart)
	rewardObject.Parent = rewardFolder
	setRewardHeldPhysics(rewardObject, false)
	local spawnHint = positionRewardObject(player, rewardObject, rewardState, startPart, endPart)
	if rewardState and rewardState.RewardType == "Chest" and spawnHint and rewardObject:GetAttribute("SpawnHintShown") ~= true then
		rewardObject:SetAttribute("SpawnHintShown", true)
		sendPopup(player, spawnHint, INFO_COLOR, false)
	end

	local prompt = rootPart:FindFirstChild("PickUpPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		configureRewardPickupPrompt(prompt, rewardState)
		prompt.Enabled = true
	end
end

local function applyCarriedRewardState(player, rewardObject, rootPart, carriedFolder, carrierPartOverride, rewardState)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local requestedCarrier = carrierPartOverride
	local carrierPart = carrierPartOverride
	local ghostCarrierPart = nil
	if not carrierPart or not carrierPart:IsA("BasePart") or not carrierPart.Parent then
		ghostCarrierPart = getActiveHoroCarrierPart(player)
		carrierPart = ghostCarrierPart
	end
	if not carrierPart or not carrierPart:IsA("BasePart") then
		carrierPart = head
	end
	if not carrierPart or not humanoid or humanoid.Health <= 0 then
		horoCarryTrace(
			"attachCarry failed player=%s reward=%s reason=carrier_or_humanoid_missing requestedCarrier=%s ghostCarrier=%s head=%s carryAttrs={%s} runtime={%s}",
			player and player.Name or "<nil>",
			formatInstancePath(rewardObject),
			formatInstancePath(requestedCarrier),
			formatInstancePath(ghostCarrierPart),
			formatInstancePath(head),
			getPlayerCarrySummary(player),
			getRunRewardSummary(player)
		)
		return false
	end

	local carrierSource = "resolved_other"
	if requestedCarrier and carrierPart == requestedCarrier then
		carrierSource = "override"
	elseif ghostCarrierPart and carrierPart == ghostCarrierPart then
		carrierSource = "horo_ghost"
	elseif head and carrierPart == head then
		carrierSource = "body_head"
	end

	clearCarryWeld(rootPart)
	rewardObject.Parent = carriedFolder
	setRewardHeldPhysics(rewardObject, true)

	local prompt = rootPart:FindFirstChild("PickUpPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end

	local top = carrierPart.Position + Vector3.yAxis * (carrierPart.Size.Y / 2)
	local carryVisualOffset = tonumber(rewardState and rewardState.CarryVisualOffset) or 0
	if rewardObject then
		rewardObject:SetAttribute("CarryVisualOffset", carryVisualOffset)
	end
	top += carrierPart.CFrame.RightVector * carryVisualOffset
	local targetPivot = computePivotBottomOnPoint(rewardObject, top, computeCarrierRotOnly(carrierPart))
	setObjectCFrame(rewardObject, targetPivot)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "RewardCarryWeld"
	weld.Part0 = rootPart
	weld.Part1 = carrierPart
	weld.Parent = rootPart

	horoCarryTrace(
		"attachCarry applied player=%s reward=%s rewardType=%s carrierSource=%s carrierPart=%s carrierPos=%s rewardPos=%s projectionActive=%s projectionId=%s carryAttrs={%s} runtime={%s}",
		player and player.Name or "<nil>",
		formatInstancePath(rewardObject),
		tostring(rewardObject and rewardObject:GetAttribute("RewardType")),
		tostring(carrierSource),
		formatInstancePath(carrierPart),
		formatVector3(carrierPart.Position),
		formatVector3(getObjectPivot(rewardObject).Position),
		tostring(player:GetAttribute("HoroProjectionActive")),
		tostring(player:GetAttribute("HoroProjectionId")),
		getPlayerCarrySummary(player),
		getRunRewardSummary(player)
	)

	return true
end

local function getSharedChestAttribute(instance, attributeName)
	if not instance or typeof(attributeName) ~= "string" or attributeName == "" then
		return nil
	end

	return instance:GetAttribute(attributeName)
end

local function isTruthySharedChestAttribute(instance, attributeName)
	local value = getSharedChestAttribute(instance, attributeName)
	if value == true or value == 1 then
		return true
	end

	if typeof(value) == "string" then
		local lowered = string.lower(value)
		return lowered == "true" or lowered == "yes" or lowered == "1"
	end

	return false
end

local function isConfiguredSharedChestDepthBand(value)
	local depthBand = tostring(value or "")
	if depthBand == "" then
		return false
	end

	for _, configuredDepthBand in ipairs(Economy.VerticalSlice.DepthBands or {}) do
		if tostring(configuredDepthBand) == depthBand then
			return true
		end
	end

	return false
end

local function getSharedChestDepthBandForSpawnPart(sharedConfig, spawnPart)
	sharedConfig = if typeof(sharedConfig) == "table" then sharedConfig else {}
	local depthBandAttribute = tostring(sharedConfig.SpawnPartDepthBandAttribute or "SharedChestDepthBand")
	local attributeDepthBand = getSharedChestAttribute(spawnPart, depthBandAttribute)
	if isConfiguredSharedChestDepthBand(attributeDepthBand) then
		return tostring(attributeDepthBand)
	end

	local tierMap = SpawnPartsConfig.RarityTier or {}
	local depthBandByTier = sharedConfig.SpawnTierToDepthBand or {}
	local spawnTier = tonumber(tierMap[tostring(spawnPart and spawnPart.Name or "")]) or 1
	return tostring(depthBandByTier[spawnTier] or Economy.VerticalSlice.DefaultDepthBand)
end

local function getSharedChestSpawnPartWeight(sharedConfig, spawnPart, depthBand)
	sharedConfig = if typeof(sharedConfig) == "table" then sharedConfig else {}
	local weightAttribute = tostring(sharedConfig.SpawnPartWeightAttribute or "SharedChestSpawnWeight")
	local attributeWeight = tonumber(getSharedChestAttribute(spawnPart, weightAttribute))
	if attributeWeight ~= nil then
		return math.max(0, attributeWeight)
	end

	local depthWeights = sharedConfig.SpawnWeightByDepthBand
	if typeof(depthWeights) == "table" then
		local depthWeight = tonumber(depthWeights[tostring(depthBand or "")])
		if depthWeight ~= nil then
			return math.max(0, depthWeight)
		end
	end

	return 1
end

local function buildSharedChestSpawnPartRecord(sharedConfig, spawnPart)
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return nil
	end

	sharedConfig = if typeof(sharedConfig) == "table" then sharedConfig else {}
	if isTruthySharedChestAttribute(spawnPart, sharedConfig.SpawnPartDisabledAttribute or "SharedChestSpawnDisabled") then
		return nil
	end

	local explicit = isTruthySharedChestAttribute(
		spawnPart,
		sharedConfig.SpawnPartEligibleAttribute or "SharedChestSpawnEligible"
	)
	if not explicit and not isValidSpawnRarityPart(spawnPart) then
		return nil
	end

	local depthBand = getSharedChestDepthBandForSpawnPart(sharedConfig, spawnPart)
	local weight = getSharedChestSpawnPartWeight(sharedConfig, spawnPart, depthBand)
	if weight <= 0 then
		return nil
	end

	return {
		SpawnPart = spawnPart,
		DepthBand = depthBand,
		Weight = weight,
		Explicit = explicit,
	}
end

local function collectSharedChestSpawnPartRecords(root, sharedConfig, records, seen)
	if not root then
		return
	end

	local rootRecord = buildSharedChestSpawnPartRecord(sharedConfig, root)
	if rootRecord and not seen[rootRecord.SpawnPart] then
		seen[rootRecord.SpawnPart] = true
		records[#records + 1] = rootRecord
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		local record = buildSharedChestSpawnPartRecord(sharedConfig, descendant)
		if record and not seen[record.SpawnPart] then
			seen[record.SpawnPart] = true
			records[#records + 1] = record
		end
	end
end

local function getSharedChestSpawnPartCacheRefreshSeconds(sharedConfig)
	return math.max(5, tonumber(sharedConfig.SpawnPartCacheRefreshSeconds) or 60)
end

local function getSharedChestSpawnPartRecords(sharedConfig)
	sharedConfig = if typeof(sharedConfig) == "table" then sharedConfig else {}
	local refs = MapResolver.GetRefs()
	local mapRoot = refs.MapRoot
	local biomesRoot = refs.Biomes or (mapRoot and mapRoot:FindFirstChild("Biomes"))
	local spawnFolder = refs.SpawnFolder
	local now = os.clock()
	local cacheRefreshSeconds = getSharedChestSpawnPartCacheRefreshSeconds(sharedConfig)

	if
		sharedChestSpawnPartCache
		and sharedChestSpawnPartCache.MapRoot == mapRoot
		and sharedChestSpawnPartCache.BiomesRoot == biomesRoot
		and sharedChestSpawnPartCache.SpawnFolder == spawnFolder
		and now - sharedChestSpawnPartCache.RefreshedAt < cacheRefreshSeconds
	then
		return sharedChestSpawnPartCache.Records
	end

	local records = {}
	local seen = {}
	if biomesRoot then
		for _, biomeContainer in ipairs(biomesRoot:GetChildren()) do
			local innerBiome = biomeContainer:FindFirstChild(biomeContainer.Name)
			collectSharedChestSpawnPartRecords(innerBiome or biomeContainer, sharedConfig, records, seen)
		end
	else
		collectSharedChestSpawnPartRecords(spawnFolder, sharedConfig, records, seen)
	end

	if #records == 0 and spawnFolder and spawnFolder ~= biomesRoot then
		collectSharedChestSpawnPartRecords(spawnFolder, sharedConfig, records, seen)
	end

	sharedChestSpawnPartCache = {
		MapRoot = mapRoot,
		BiomesRoot = biomesRoot,
		SpawnFolder = spawnFolder,
		RefreshedAt = now,
		Records = records,
	}

	waveTrace(
		"sharedChestSpawnPartCache refreshed map=%s biomesRoot=%s spawnFolder=%s records=%d",
		formatInstancePath(mapRoot),
		formatInstancePath(biomesRoot),
		formatInstancePath(spawnFolder),
		#records
	)

	return records
end

local function getSharedChestMaxActivePerSpawnPart(sharedConfig)
	local maxActivePerSpawnPart = tonumber(sharedConfig.MaxActivePerSpawnPart)
	if maxActivePerSpawnPart == nil then
		return 0
	end

	return math.max(0, math.floor(maxActivePerSpawnPart))
end

local function countActiveSharedChestsOnSpawnPart(spawnPart)
	local count = 0
	for _, node in pairs(sharedChestNodesById) do
		if node.SpawnPart == spawnPart and node.Object and node.Object.Parent then
			count += 1
		end
	end

	return count
end

local function isSharedChestSpawnPartBelowCap(spawnPart, sharedConfig)
	local maxActivePerSpawnPart = getSharedChestMaxActivePerSpawnPart(sharedConfig)
	if maxActivePerSpawnPart <= 0 then
		return true
	end

	return countActiveSharedChestsOnSpawnPart(spawnPart) < maxActivePerSpawnPart
end

local function chooseSharedChestPlacementCrewMember(spawnPart)
	local crewMembersFolder = spawnPart and spawnPart:FindFirstChild("CrewMembers")
	if not crewMembersFolder then
		return nil
	end

	local candidates = {}
	for _, candidate in ipairs(crewMembersFolder:GetChildren()) do
		if getObjectRootPart(candidate) then
			candidates[#candidates + 1] = candidate
		end
	end

	if #candidates <= 0 then
		return nil
	end

	return candidates[worldRandom:NextInteger(1, #candidates)]
end

local function chooseSharedChestSpawnRecord(sharedConfig)
	local records = getSharedChestSpawnPartRecords(sharedConfig)
	local weightedRecords = {}
	local totalWeight = 0

	for _, record in ipairs(records) do
		local spawnPart = record.SpawnPart
		if spawnPart and spawnPart.Parent and isSharedChestSpawnPartBelowCap(spawnPart, sharedConfig) then
			local weight = math.max(0, tonumber(record.Weight) or 0)
			if weight > 0 then
				totalWeight += weight
				weightedRecords[#weightedRecords + 1] = record
			end
		end
	end

	if totalWeight <= 0 then
		return nil
	end

	local roll = worldRandom:NextNumber(0, totalWeight)
	local cursor = 0
	for _, record in ipairs(weightedRecords) do
		cursor += math.max(0, tonumber(record.Weight) or 0)
		if roll <= cursor then
			return record
		end
	end

	return weightedRecords[#weightedRecords]
end

local function chooseSharedChestSpawnContext()
	local sharedConfig = Economy.VerticalSlice.WorldRun.SharedChests or {}
	local record = chooseSharedChestSpawnRecord(sharedConfig)
	if not record then
		return nil
	end

	local crewMember = chooseSharedChestPlacementCrewMember(record.SpawnPart)
	waveTrace(
		"sharedChestSpawnContext part=%s partPos=%s depthBand=%s weight=%s nearbyCrew=%s",
		formatInstancePath(record.SpawnPart),
		formatVector3(record.SpawnPart and record.SpawnPart.Position or nil),
		tostring(record.DepthBand),
		tostring(record.Weight),
		formatInstancePath(crewMember)
	)

	return {
		SpawnPart = record.SpawnPart,
		CrewMember = crewMember,
		DepthBand = record.DepthBand,
	}
end

local function getOccupiedSharedChestOffsets(spawnPart)
	local offsets = {}
	for _, node in pairs(sharedChestNodesById) do
		if node.SpawnPart == spawnPart and node.Object and node.Object.Parent then
			local rootPart = getObjectRootPart(node.Object)
			if rootPart then
				offsets[#offsets + 1] = worldToSpawnLocalXZ(spawnPart, rootPart.Position)
			end
		end
	end

	return offsets
end

local function buildSharedChestPlacement(rewardObject, spawnContext)
	if not spawnContext or not spawnContext.SpawnPart then
		return nil
	end

	local spawnPart = spawnContext.SpawnPart
	local baseOffset = Vector2.zero
	if spawnContext.CrewMember then
		local crewMemberRoot = getObjectRootPart(spawnContext.CrewMember)
		if crewMemberRoot then
			baseOffset = worldToSpawnLocalXZ(spawnPart, crewMemberRoot.Position)
		end
	end

	local _, boxSize = getObjectBoundingBox(rewardObject)
	local spacing = math.max(4, math.max(boxSize.X, boxSize.Z) * 1.35)
	local candidateOffsets = {
		baseOffset + Vector2.new(spacing, 0),
		baseOffset + Vector2.new(-spacing, 0),
		baseOffset + Vector2.new(0, spacing),
		baseOffset + Vector2.new(0, -spacing),
		baseOffset + Vector2.new(spacing * 0.7, spacing * 0.7),
		baseOffset + Vector2.new(-spacing * 0.7, spacing * 0.7),
		baseOffset + Vector2.new(spacing * 0.7, -spacing * 0.7),
		baseOffset + Vector2.new(-spacing * 0.7, -spacing * 0.7),
	}
	if not spawnContext.CrewMember then
		candidateOffsets[#candidateOffsets + 1] = Vector2.zero
	end

	local occupiedOffsets = getOccupiedSpawnOffsets(spawnPart, spawnContext.CrewMember)
	for _, offset in ipairs(getOccupiedSharedChestOffsets(spawnPart)) do
		occupiedOffsets[#occupiedOffsets + 1] = offset
	end

	local chosenOffset = clampLocalXZToSpawnPart(spawnPart, rewardObject, candidateOffsets[#candidateOffsets] or Vector2.zero)
	for _, candidateOffset in ipairs(candidateOffsets) do
		local clamped = clampLocalXZToSpawnPart(spawnPart, rewardObject, candidateOffset)
		if isOffsetClear(clamped, occupiedOffsets, math.max(3.5, spacing * 0.8)) then
			chosenOffset = clamped
			break
		end
	end

	return {
		SpawnPart = spawnPart,
		LocalXZ = chosenOffset,
		Yaw = 0,
		SourceCrewMemberName = spawnContext.CrewMember and spawnContext.CrewMember.Name or nil,
	}
end

local function getDepthBandForSharedChestSpawn(spawnPart)
	local sharedConfig = Economy.VerticalSlice.WorldRun.SharedChests or {}
	return getSharedChestDepthBandForSpawnPart(sharedConfig, spawnPart)
end

local function countActiveSharedChests()
	local count = 0
	for _, node in pairs(sharedChestNodesById) do
		if node.Object and node.Object.Parent then
			count += 1
		end
	end
	return count
end

local function getActiveSharedChestPlayerCount()
	return math.max(1, #Players:GetPlayers())
end

local function getSharedChestCheckInterval(sharedConfig)
	return math.max(1, tonumber(sharedConfig.SpawnCheckInterval) or tonumber(sharedConfig.RespawnCheckInterval) or 5)
end

local function getSharedChestSpawnInterval(sharedConfig, activePlayerCount)
	local intervalConfig = sharedConfig.SpawnIntervalSeconds
	if typeof(intervalConfig) == "table" then
		local base = tonumber(intervalConfig.Base) or tonumber(intervalConfig.Max) or tonumber(sharedConfig.RespawnDelay) or 75
		local perExtraDecrease = tonumber(intervalConfig.SecondsRemovedPerExtraPlayer) or 0
		local minInterval = tonumber(intervalConfig.Min) or 1
		local maxInterval = tonumber(intervalConfig.Max) or base
		local extraPlayers = math.max(0, math.floor(tonumber(activePlayerCount) or 1) - 1)
		return math.clamp(base - (extraPlayers * perExtraDecrease), minInterval, maxInterval)
	end

	return math.max(1, tonumber(intervalConfig) or tonumber(sharedConfig.RespawnDelay) or 10)
end

local function getSharedChestMaxActiveFromTable(maxActiveByPlayerCount, activePlayerCount)
	if typeof(maxActiveByPlayerCount) ~= "table" then
		return nil
	end

	local playerCount = math.max(1, math.floor(tonumber(activePlayerCount) or 1))
	local exactValue = tonumber(maxActiveByPlayerCount[playerCount])
	if exactValue ~= nil then
		return math.max(0, math.floor(exactValue))
	end

	local nearestLowerPlayerCount = nil
	local nearestLowerValue = nil
	local nearestHigherPlayerCount = nil
	local nearestHigherValue = nil
	for key, value in pairs(maxActiveByPlayerCount) do
		local configuredPlayerCount = math.floor(tonumber(key) or 0)
		local configuredValue = tonumber(value)
		if configuredPlayerCount >= 1 and configuredValue ~= nil then
			if configuredPlayerCount <= playerCount then
				if nearestLowerPlayerCount == nil or configuredPlayerCount > nearestLowerPlayerCount then
					nearestLowerPlayerCount = configuredPlayerCount
					nearestLowerValue = configuredValue
				end
			elseif nearestHigherPlayerCount == nil or configuredPlayerCount < nearestHigherPlayerCount then
				nearestHigherPlayerCount = configuredPlayerCount
				nearestHigherValue = configuredValue
			end
		end
	end

	local bestValue = nearestLowerValue or nearestHigherValue
	if bestValue == nil then
		return nil
	end

	return math.max(0, math.floor(bestValue))
end

local function getSharedChestMaxActive(sharedConfig, activePlayerCount)
	local tableMaxActive = getSharedChestMaxActiveFromTable(sharedConfig.MaxActiveByPlayerCount, activePlayerCount)
	if tableMaxActive ~= nil then
		return tableMaxActive
	end

	local maxActiveConfig = sharedConfig.MaxActive
	if typeof(maxActiveConfig) == "table" then
		tableMaxActive = getSharedChestMaxActiveFromTable(maxActiveConfig.ByPlayerCount, activePlayerCount)
		if tableMaxActive ~= nil then
			return tableMaxActive
		end

		local base = math.floor(tonumber(maxActiveConfig.Base) or 2)
		local playersPerExtra = math.max(1, math.floor(tonumber(maxActiveConfig.PlayersPerExtra) or 4))
		local minActive = math.floor(tonumber(maxActiveConfig.Min) or base)
		local maxActive = math.floor(tonumber(maxActiveConfig.Max) or base)
		local extraPlayers = math.max(0, math.floor(tonumber(activePlayerCount) or 1) - 1)
		local scaledActive = base + math.floor(extraPlayers / playersPerExtra)
		return math.clamp(scaledActive, minActive, maxActive)
	end

	return math.max(0, math.floor(tonumber(maxActiveConfig) or 0))
end

local function shouldForceSharedGold(sharedConfig)
	local pityThreshold = math.floor(tonumber(sharedConfig.GoldPityAfterNonGoldSpawns) or 0)
	return pityThreshold > 0 and sharedChestNonGoldStreak >= pityThreshold
end

local function recordSharedChestTier(tierName)
	if tostring(tierName or "") == "Gold" then
		sharedChestNonGoldStreak = 0
	else
		sharedChestNonGoldStreak += 1
	end
end

local function destroySharedChestNode(chestId, node)
	sharedChestNodesById[chestId] = nil
	local object = node and node.Object
	if object and object.Parent then
		object:Destroy()
	end
end

local function despawnExpiredSharedChests(now, sharedConfig)
	local despawnSeconds = tonumber(sharedConfig.UnclaimedDespawnSeconds) or 0
	if despawnSeconds <= 0 then
		return
	end

	for chestId, node in pairs(sharedChestNodesById) do
		local object = node and node.Object
		if not object or not object.Parent then
			sharedChestNodesById[chestId] = nil
		elseif node.Claimed ~= true then
			local spawnedAt = tonumber(node.SpawnedAt) or now
			node.SpawnedAt = spawnedAt
			if now - spawnedAt >= despawnSeconds then
				destroySharedChestNode(chestId, node)
			end
		end
	end
end

local function normalizeWorldChestRewardState(rewardState)
	local normalized = {}
	if typeof(rewardState) == "table" then
		for key, value in pairs(rewardState) do
			normalized[key] = value
		end
	end

	normalized.RewardType = "Chest"
	normalized.Tier = tostring(normalized.Tier or "Wooden")
	normalized.DepthBand = tostring(normalized.DepthBand or Economy.VerticalSlice.DefaultDepthBand)
	normalized.DisplayName = tostring(normalized.DisplayName or string.format("%s Chest", normalized.Tier))
	return normalized
end

local function getPlayerDropFallbackPosition(player)
	local character = player and player.Character
	local rootPart = nil
	if character then
		rootPart = character:FindFirstChild("HumanoidRootPart")
			or character.PrimaryPart
			or character:FindFirstChild("Head")
	end
	if not (rootPart and rootPart:IsA("BasePart")) then
		return nil
	end

	local lookVector = rootPart.CFrame.LookVector
	local flatDirection = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatDirection.Magnitude < 1e-4 then
		flatDirection = Vector3.new(0, 0, -1)
	else
		flatDirection = flatDirection.Unit
	end

	return rootPart.Position + (flatDirection * 5)
end

local function positionWorldChestObject(rewardObject, rewardState, options)
	options = if typeof(options) == "table" then options else {}
	local spawnContext = options.SpawnContext
	if spawnContext and spawnContext.SpawnPart then
		local placement = buildSharedChestPlacement(rewardObject, spawnContext)
		if placement then
			waveTrace(
				"sharedChestPlacement chestId=%s spawnPart=%s spawnPartPos=%s sourceCrewMember=%s localXZ=%s",
				tostring(options.ChestId),
				formatInstancePath(placement.SpawnPart),
				formatVector3(placement.SpawnPart and placement.SpawnPart.Position or nil),
				tostring(placement.SourceCrewMemberName),
				formatVector3(Vector3.new(placement.LocalXZ.X, 0, placement.LocalXZ.Y))
			)
			setObjectCFrame(
				rewardObject,
				computeObjectPivotOnSpawnPart(
					rewardObject,
					placement.SpawnPart,
					placement.LocalXZ,
					tonumber(placement.Yaw) or 0
				)
			)
			return placement.SpawnPart
		end
	end

	local dropPosition = options.DropPosition
	if typeof(dropPosition) ~= "Vector3" then
		dropPosition = rewardState.WorldDropPosition
	end
	if typeof(dropPosition) ~= "Vector3" then
		dropPosition = getPlayerDropFallbackPosition(options.Dropper)
	end
	if typeof(dropPosition) == "Vector3" then
		local character = options.Dropper and options.Dropper.Character
		local ignoreInstances = character and { character } or nil
		local pivot = getDroppedRewardPivot(rewardObject, dropPosition, ignoreInstances)
		setObjectCFrame(rewardObject, pivot)
	end

	return nil
end

local function connectSharedChestPrompt(chestId, node, prompt)
	prompt.Triggered:Connect(function(triggerPlayer)
		local currentNode = sharedChestNodesById[chestId]
		if currentNode ~= node or node.Claimed then
			return
		end
		node.Claimed = true
		local response = SliceService.ClaimWorldChest(triggerPlayer, node.RewardState)
		if not response or not response.ok then
			node.Claimed = false
			sendPopup(triggerPlayer, buildResponseMessage(response, "Could not pick up chest."), ERROR_COLOR, true)
			return
		end

		destroySharedChestNode(chestId, node)

		sendPopup(triggerPlayer, buildResponseMessage(response, "Chest picked up. Bring it back to extract."), SUCCESS_COLOR, false)
	end)
end

local function createSharedChestNode(rewardFolder, rewardState, options)
	if not rewardFolder then
		return nil
	end

	options = if typeof(options) == "table" then options else {}
	rewardState = normalizeWorldChestRewardState(rewardState)
	sharedChestSequence += 1
	local chestId = tostring(sharedChestSequence)
	options.ChestId = chestId

	local namePrefix = tostring(options.NamePrefix or "SharedChest")
	local rewardObject = createRewardInstance(rewardState)
	rewardObject.Name = string.format("%s_%s", namePrefix, chestId)
	rewardObject:SetAttribute("RewardType", "Chest")
	rewardObject:SetAttribute("SharedWorldChest", true)
	rewardObject:SetAttribute("SharedChestId", chestId)
	if options.DroppedWorldChest == true then
		rewardObject:SetAttribute("DroppedWorldChest", true)
	end
	rewardObject.Parent = rewardFolder

	local rootPart = getObjectRootPart(rewardObject)
	if not rootPart then
		rewardObject:Destroy()
		rewardObject = createDefaultRewardPart(rewardState)
		rewardObject.Name = string.format("%s_%s", namePrefix, chestId)
		rewardObject:SetAttribute("RewardType", "Chest")
		rewardObject:SetAttribute("SharedWorldChest", true)
		rewardObject:SetAttribute("SharedChestId", chestId)
		if options.DroppedWorldChest == true then
			rewardObject:SetAttribute("DroppedWorldChest", true)
		end
		rewardObject.Parent = rewardFolder
		rootPart = rewardObject
	end

	local spawnPart = positionWorldChestObject(rewardObject, rewardState, options)

	local highlight = Instance.new("Highlight")
	highlight.FillColor = if rootPart and rootPart:IsA("BasePart") then rootPart.Color else Color3.fromRGB(214, 155, 74)
	highlight.FillTransparency = 0.15
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = rewardObject

	addRewardBillboard(rootPart, rewardState, nil)
	addChestDebugBeacon(rootPart)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpPrompt"
	configureRewardPickupPrompt(prompt, rewardState)
	prompt.Parent = rootPart

	local node = {
		Id = chestId,
		Object = rewardObject,
		RootPart = rootPart,
		RewardState = rewardState,
		SpawnPart = spawnPart,
		Claimed = false,
		SpawnedAt = os.clock(),
		DroppedWorldChest = options.DroppedWorldChest == true,
	}
	sharedChestNodesById[chestId] = node
	connectSharedChestPrompt(chestId, node, prompt)

	return node
end

local function spawnSharedChestNode(rewardFolder, _carriedFolder, activePlayerCount, forceGold)
	local spawnContext = chooseSharedChestSpawnContext()
	if not spawnContext or not spawnContext.SpawnPart then
		return nil
	end

	local depthBand = tostring(spawnContext.DepthBand or getDepthBandForSharedChestSpawn(spawnContext.SpawnPart))
	local rewardState = SliceService.CreateChestRewardData(depthBand, {
		ActivePlayerCount = activePlayerCount,
		ForceGold = forceGold == true,
		SharedWorldChest = true,
	})
	rewardState.DisplayName = string.format("%s Chest", tostring(rewardState.Tier or "Wooden"))

	local node = createSharedChestNode(rewardFolder, rewardState, {
		SpawnContext = spawnContext,
	})
	if node then
		recordSharedChestTier(rewardState.Tier)
	end

	return node
end

local function spawnDroppedSharedChestNode(rewardFolder, player, rewardData)
	if typeof(rewardData) ~= "table" or rewardData.RewardType ~= "Chest" then
		return false, "invalid_dropped_chest"
	end

	local dropPosition = rewardData.WorldDropPosition
	if typeof(dropPosition) ~= "Vector3" then
		dropPosition = getPlayerDropFallbackPosition(player)
	end
	if typeof(dropPosition) ~= "Vector3" then
		return false, "drop_position_unavailable"
	end

	local node = createSharedChestNode(rewardFolder, rewardData, {
		NamePrefix = "DroppedSharedChest",
		DroppedWorldChest = true,
		Dropper = player,
		DropPosition = dropPosition,
	})
	if not node then
		return false, "dropped_chest_create_failed"
	end

	return node
end

local function ensureSharedChestNodes(rewardFolder, carriedFolder)
	local sharedConfig = Economy.VerticalSlice.WorldRun.SharedChests or {}
	if sharedConfig.Enabled ~= true then
		return
	end

	local now = os.clock()
	despawnExpiredSharedChests(now, sharedConfig)

	local activePlayerCount = getActiveSharedChestPlayerCount()
	local maxActive = getSharedChestMaxActive(sharedConfig, activePlayerCount)
	if maxActive <= 0 then
		return
	end

	local spawnInterval = getSharedChestSpawnInterval(sharedConfig, activePlayerCount)
	local activeCount = countActiveSharedChests()
	if activeCount >= maxActive then
		nextSharedChestRespawnAt = now + spawnInterval
		return
	end

	if nextSharedChestRespawnAt <= 0 then
		nextSharedChestRespawnAt = now
	end

	if now < nextSharedChestRespawnAt then
		return
	end

	if spawnSharedChestNode(rewardFolder, carriedFolder, activePlayerCount, shouldForceSharedGold(sharedConfig)) then
		nextSharedChestRespawnAt = now + spawnInterval
	else
		nextSharedChestRespawnAt = now + math.min(getSharedChestCheckInterval(sharedConfig), spawnInterval)
	end
end

local function createRewardObject(player, rewardState, rewardFolder, carriedFolder, startPart, endPart, isCarried, objectKey)
	objectKey = tostring(objectKey or "spawned")
	local rewardKey = buildRewardKey(rewardState)
	local existing = getRewardObject(player.UserId, objectKey)
	if existing and existing.Parent and existing:GetAttribute("RewardKey") == rewardKey then
		local existingRoot = getObjectRootPart(existing)
		if existingRoot then
			if isCarried then
				applyCarriedRewardState(player, existing, existingRoot, carriedFolder, nil, rewardState)
			else
				applySpawnedRewardState(player, existing, existingRoot, rewardState, rewardFolder, startPart, endPart)
			end
		end
		return
	end

	destroyRewardObject(player.UserId, objectKey)

	local rewardObject = createRewardInstance(rewardState)
	rewardObject.Name = string.format("RunReward_%d_%s", player.UserId, objectKey)
	rewardObject:SetAttribute("OwnerUserId", player.UserId)
	rewardObject:SetAttribute("RewardKey", rewardKey)
	rewardObject:SetAttribute("RewardType", rewardState.RewardType)
	rewardObject.Parent = rewardFolder

	local rootPart = getObjectRootPart(rewardObject)
	if not rootPart then
		rewardObject:Destroy()
		rewardObject = createDefaultRewardPart(rewardState)
		rewardObject.Name = string.format("RunReward_%d_%s", player.UserId, objectKey)
		rewardObject:SetAttribute("OwnerUserId", player.UserId)
		rewardObject:SetAttribute("RewardKey", rewardKey)
		rewardObject:SetAttribute("RewardType", rewardState.RewardType)
		rewardObject.Parent = rewardFolder
		rootPart = rewardObject
	end

	local highlight = Instance.new("Highlight")
	highlight.FillColor = if rootPart and rootPart:IsA("BasePart") then rootPart.Color else Color3.fromRGB(214, 155, 74)
	highlight.FillTransparency = if rewardState.RewardType == "Chest" then 0.15 else 0.35
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = if rewardState.RewardType == "Chest"
		then Enum.HighlightDepthMode.AlwaysOnTop
		else Enum.HighlightDepthMode.Occluded
	highlight.Parent = rewardObject

	addRewardBillboard(rootPart, rewardState, player)
	if rewardState.RewardType == "Chest" then
		addChestDebugBeacon(rootPart)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpPrompt"
	configureRewardPickupPrompt(prompt, rewardState)
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer ~= player then
			return
		end
		local response = SliceService.ClaimSpawnedReward(player)
		if response.ok then
			sendPopup(player, buildResponseMessage(response, "Reward picked up. Bring it back to extract."), SUCCESS_COLOR, false)
		else
			sendPopup(player, buildResponseMessage(response, "Could not pick up reward."), ERROR_COLOR, true)
		end
	end)

	if isCarried then
		if not applyCarriedRewardState(player, rewardObject, rootPart, carriedFolder, nil, rewardState) then
			applySpawnedRewardState(player, rewardObject, rootPart, rewardState, rewardFolder, startPart, endPart)
		end
	else
		applySpawnedRewardState(player, rewardObject, rootPart, rewardState, rewardFolder, startPart, endPart)
	end

	setRewardObject(player.UserId, objectKey, rewardObject)
end

local function buildRewardStateFromCarrySlot(slot)
	if typeof(slot) ~= "table" or slot.Occupied ~= true then
		return nil
	end

	local data = if typeof(slot.Data) == "table" then table.clone(slot.Data) else {}
	if slot.ItemType == "Chest" then
		data.RewardType = "Chest"
		data.DisplayName = slot.DisplayName
		data.CarryId = slot.CarryId
		data.CarryOrder = slot.CarryOrder
		data.SlotIndex = slot.SlotIndex
		return data
	end

	if data.Physical == true then
		return nil
	end

	data.RewardType = data.RewardType or "Crew"
	data.DisplayName = slot.DisplayName
	data.CarryId = slot.CarryId
	data.CarryOrder = slot.CarryOrder
	data.SlotIndex = slot.SlotIndex
	return data
end

local function getCarryObjectKey(slot)
	return "carry_" .. tostring(slot.CarryId or slot.SlotIndex or "unknown")
end

local function syncPlayerRewardObject(player, state, rewardFolder, carriedFolder, startPart, endPart)
	local runState = state and state.Run or {}
	local spawnedReward = runState.SpawnedReward
	local carrySlots = runState.CarrySlots or {}
	local carryOffsetMap = CarriedRewardVisuals.BuildOffsetMap(carrySlots, CARRY_VISUAL_SPACING)
	local wantedKeys = {}

	if spawnedReward ~= nil then
		wantedKeys.spawned = true
		createRewardObject(player, spawnedReward, rewardFolder, carriedFolder, startPart, endPart, false, "spawned")
	else
		destroyRewardObject(player.UserId, "spawned")
	end

	for _, slot in ipairs(carrySlots) do
		local rewardState = buildRewardStateFromCarrySlot(slot)
		if rewardState then
			local objectKey = getCarryObjectKey(slot)
			rewardState.CarryVisualOffset = carryOffsetMap[tostring(slot.CarryId or "")] or 0
			wantedKeys[objectKey] = true
			createRewardObject(player, rewardState, rewardFolder, carriedFolder, startPart, endPart, true, objectKey)
		end
	end

	local map = rewardObjectsByUserId[player.UserId]
	if typeof(map) == "table" and map.__MultiCarryObjects == true then
		for key, _ in pairs(map) do
			if key ~= "__MultiCarryObjects" and wantedKeys[key] ~= true then
				destroyRewardObject(player.UserId, key)
			end
		end
	elseif not spawnedReward then
		destroyRewardObject(player.UserId)
	end
end

local function findPlayerFromHit(hit)
	local current = hit
	while current and current ~= Workspace do
		local candidate = Players:GetPlayerFromCharacter(current)
		if candidate then
			return candidate
		end
		current = current.Parent
	end

	return nil
end

local function canTriggerExtraction(player)
	local now = os.clock()
	local lastTouch = extractionTouchDebounce[player]
	if lastTouch and (now - lastTouch) < 0.75 then
		return false
	end

	extractionTouchDebounce[player] = now
	return true
end

local function getDebugSpawnFolder()
	local folder = Workspace:FindFirstChild("GrandLineRushDebugSpawns")
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = "GrandLineRushDebugSpawns"
	folder.Parent = Workspace
	return folder
end

local function getDebugCarriedFolder()
	local rootFolder = getDebugSpawnFolder()
	local folder = rootFolder:FindFirstChild("Carried")
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = "Carried"
	folder.Parent = rootFolder
	return folder
end

local function ensureInteractionParts(waveFolder, endPart)
	local controllerFolder = getOrCreateFolder(waveFolder, "GrandLineRush")

	local worldConfig = Economy.VerticalSlice.WorldRun
	local startHub = getOrCreatePart(controllerFolder, "RunHub")
	startHub.Size = worldConfig.StartHubSize
	startHub.CFrame = endPart.CFrame + Vector3.new(0, 4, 0)

	local extractionZone = getOrCreatePart(controllerFolder, "ExtractionZone")
	extractionZone.Size = worldConfig.ExtractionZoneSize
	extractionZone.CFrame = endPart.CFrame + Vector3.new(0, 4, 0)

	local rewardFolder = getOrCreateFolder(controllerFolder, "RunRewards")
	local carriedFolder = getOrCreateFolder(controllerFolder, "CarriedRewards")

	return controllerFolder, startHub, extractionZone, rewardFolder, carriedFolder
end

function Controller.Start()
	if started then
		return
	end

	if Economy.VerticalSlice.Enabled ~= true then
		return
	end

	local worldConfig = Economy.VerticalSlice.WorldRun
	if typeof(worldConfig) ~= "table" or worldConfig.Enabled ~= true then
		return
	end

	SliceService.Start()
	started = true

	local resolvedRefs = MapResolver.WaitForRefs(
		{ "WaveFolder", "WaveStart", "WaveEnd" },
		15,
		{
			warn = true,
			context = "GrandLineRushCorridorRunController",
		}
	)
	local waveFolder = resolvedRefs.WaveFolder
	local startPart = resolvedRefs.WaveStart
	local endPart = resolvedRefs.WaveEnd
	mapTrace(
		"GrandLineRush requestedMap=%s activeMap=%s mapPath=%s waveFolder=%s start=%s startPos=%s end=%s endPos=%s",
		tostring(resolvedRefs.RequestedMapName),
		tostring(resolvedRefs.ActiveMapName),
		formatInstancePath(resolvedRefs.MapRoot),
		formatInstancePath(waveFolder),
		formatInstancePath(startPart),
		formatVector3(startPart and startPart.Position or nil),
		formatInstancePath(endPart),
		formatVector3(endPart and endPart.Position or nil)
	)
	if not (waveFolder and startPart and endPart) then
		started = false
		warn("[GrandLineRushCorridorRunController] WaveFolder.Start/End not found; corridor integration skipped.")
		return
	end

	local _, startHub, extractionZone, rewardFolder, carriedFolder = ensureInteractionParts(waveFolder, endPart)
	local legacyChestPrompt = startHub:FindFirstChild("StartChestRunPrompt")
	if legacyChestPrompt then
		legacyChestPrompt:Destroy()
	end

	local crewPrompt = getOrCreatePrompt(startHub, "StartCrewRunPrompt", "Start Crew Run", "Grand Line Rush Corridor")
	local sharedHitBox = getMapHitBox()
	zoneTrace(
		"corridorZones activeMap=%s mapPath=%s waveFolder=%s extractionZone=%s extractionPos=%s extractionSize=%s sharedHitBox=%s sharedHitBoxPos=%s sharedHitBoxSize=%s",
		tostring(resolvedRefs.ActiveMapName),
		formatInstancePath(resolvedRefs.MapRoot),
		formatInstancePath(waveFolder),
		formatInstancePath(extractionZone),
		formatVector3(extractionZone.Position),
		formatVector3(extractionZone.Size),
		formatInstancePath(sharedHitBox),
		formatVector3(sharedHitBox and sharedHitBox.Position or nil),
		formatVector3(sharedHitBox and sharedHitBox.Size or nil)
	)
	waveTrace(
		"corridorRuntime waveFolder=%s startHub=%s startHubPos=%s extractionZone=%s extractionPos=%s sharedHitBox=%s sharedHitBoxPos=%s rewardFolder=%s carriedFolder=%s",
		formatInstancePath(waveFolder),
		formatInstancePath(startHub),
		formatVector3(startHub.Position),
		formatInstancePath(extractionZone),
		formatVector3(extractionZone.Position),
		formatInstancePath(sharedHitBox),
		formatVector3(sharedHitBox and sharedHitBox.Position or nil),
		formatInstancePath(rewardFolder),
		formatInstancePath(carriedFolder)
	)

	local function startRunForPlayer(player, rewardType)
		local response = SliceService.StartRun(player, rewardType, worldConfig.StartDepthBand or Economy.VerticalSlice.DefaultDepthBand)
		if response.ok then
			local rewardLabel = if rewardType == "Chest" then "Chest" else "Crew"
			sendPopup(player, string.format("%s run started. A %s reward should now be visible in the corridor.", rewardLabel, rewardLabel:lower()), INFO_COLOR, false)
		else
			sendPopup(player, buildResponseMessage(response, "Could not start run."), ERROR_COLOR, true)
		end
	end

	crewPrompt.Triggered:Connect(function(player)
		startRunForPlayer(player, "Crew")
	end)

	local function tryExtractFromTouch(hit, sourceLabel, sourcePart)
		local player = findPlayerFromHit(hit)
		if not player or not canTriggerExtraction(player) then
			if player then
				zoneTrace(
					"corridorBoundaryTouchSkipped player=%s source=%s sourcePath=%s reason=debounced_or_invalid",
					player.Name,
					tostring(sourceLabel),
					formatInstancePath(sourcePart)
				)
			end
			return
		end

		zoneTrace(
			"corridorBoundaryTouched player=%s source=%s sourcePath=%s sourcePos=%s sourceSize=%s activeMap=%s mapPath=%s",
			player.Name,
			tostring(sourceLabel),
			formatInstancePath(sourcePart),
			formatVector3(sourcePart and sourcePart.Position or nil),
			formatVector3(sourcePart and sourcePart.Size or nil),
			tostring(resolvedRefs.ActiveMapName),
			formatInstancePath(resolvedRefs.MapRoot)
		)

		if not loggedExtractionTouchByPlayer[player.UserId] then
			loggedExtractionTouchByPlayer[player.UserId] = true
			waveTrace(
				"tryExtractFromTouch player=%s extractionZone=%s extractionPos=%s sharedHitBox=%s sharedHitBoxPos=%s",
				player.Name,
				formatInstancePath(extractionZone),
				formatVector3(extractionZone.Position),
				formatInstancePath(sharedHitBox),
				formatVector3(sharedHitBox and sharedHitBox.Position or nil)
			)
		end

		local state = SliceService.GetState(player)
		local runState = state and state.Run or {}
		horoCarryTrace(
			"extractTouchInspect player=%s source=%s sourcePath=%s projectionActive=%s projectionId=%s carryAttrs={%s} runtime={%s}",
			player.Name,
			tostring(sourceLabel),
			formatInstancePath(sourcePart),
			tostring(player:GetAttribute("HoroProjectionActive")),
			tostring(player:GetAttribute("HoroProjectionId")),
			getPlayerCarrySummary(player),
			getRunRewardSummary(player)
		)
		local hasCarrySlots = false
		for _, slot in ipairs(runState.CarrySlots or {}) do
			if slot.Occupied == true then
				hasCarrySlots = true
				break
			end
		end
		if not hasCarrySlots then
			runTrace(
				"extractTouchSkipped player=%s source=%s sourcePath=%s reason=no_carried_reward inRun=%s",
				player.Name,
				tostring(sourceLabel),
				formatInstancePath(sourcePart),
				tostring(runState.InRun)
			)
			return
		end

		runTrace(
			"extractTouchBegin player=%s source=%s sourcePath=%s carriedType=%s activeMap=%s",
			player.Name,
			tostring(sourceLabel),
			formatInstancePath(sourcePart),
			tostring(runState.CarriedReward and runState.CarriedReward.RewardType),
			tostring(resolvedRefs.ActiveMapName)
		)
		local response = SliceService.ExtractRun(player)
		local stateAfter = SliceService.GetState(player)
		local runAfter = stateAfter and stateAfter.Run or {}
		if response.ok then
			runTrace(
				"extractTouchSuccess player=%s source=%s sourcePath=%s message=%s carriedAfter=%s unopenedChestCount=%s",
				player.Name,
				tostring(sourceLabel),
				formatInstancePath(sourcePart),
				tostring(response.message),
				tostring(runAfter.CarriedReward ~= nil),
				tostring(stateAfter and stateAfter.UnopenedChestCount or "nil")
			)
			sendPopup(player, buildResponseMessage(response, "Reward extracted."), SUCCESS_COLOR, false)
		else
			runTrace(
				"extractTouchFailed player=%s source=%s sourcePath=%s error=%s message=%s",
				player.Name,
				tostring(sourceLabel),
				formatInstancePath(sourcePart),
				tostring(response and response.error),
				tostring(response and response.message)
			)
			sendPopup(player, buildResponseMessage(response, "Could not extract reward."), ERROR_COLOR, true)
		end
	end

	extractionZone.Touched:Connect(function(hit)
		tryExtractFromTouch(hit, "ExtractionZone", extractionZone)
	end)
	if sharedHitBox then
		sharedHitBox.Touched:Connect(function(hit)
			tryExtractFromTouch(hit, "SharedHitBox", sharedHitBox)
		end)
	end

	SliceService.StateChanged:Connect(function(player, state)
		if player and player.Parent == Players then
			syncPlayerRewardObject(player, state, rewardFolder, carriedFolder, startPart, endPart)
			if carriedSharedChestByUserId[player.UserId] and not hasOccupiedCarrySlots(state and state.Run) then
				destroyCarriedSharedChest(player.UserId)
				nextSharedChestRespawnAt = math.min(nextSharedChestRespawnAt, os.clock())
			end
		end
	end)

	SliceService.SetDroppedChestWorldHandler(function(player, rewardData)
		return spawnDroppedSharedChestNode(rewardFolder, player, rewardData)
	end)

	Players.PlayerRemoving:Connect(function(player)
		destroyRewardObject(player.UserId)
		destroyCarriedSharedChest(player.UserId)
		extractionTouchDebounce[player] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			syncPlayerRewardObject(player, SliceService.GetState(player), rewardFolder, carriedFolder, startPart, endPart)
		end)
	end

	task.spawn(function()
		while started do
			ensureSharedChestNodes(rewardFolder, carriedFolder)
			task.wait(getSharedChestCheckInterval(Economy.VerticalSlice.WorldRun.SharedChests or {}))
		end
	end)
end

function Controller.SpawnDebugRewardInFrontOfPlayer(player, rewardType)
	if not player or player.Parent ~= Players then
		return false, "player_not_ready"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "character_not_ready"
	end

	local normalizedRewardType = if tostring(rewardType or ""):lower() == "crew" then "Crew" else "Chest"
	if normalizedRewardType == "Chest" then
		return Controller.SpawnSharedChestInFrontOfPlayer(player)
	end
	local rewardState
	if normalizedRewardType == "Crew" then
		rewardState = {
			RewardType = "Crew",
			DisplayName = "Debug Crew Reward",
			Rarity = "Rare",
			CrewName = "Debug Recruit",
			DepthBand = "Debug",
		}
	else
		rewardState = {
			RewardType = "Chest",
			DisplayName = "Debug Chest Reward",
			Tier = "Wooden",
			DepthBand = "Debug",
		}
	end

	local rewardObject = createRewardInstance(rewardState)
	rewardObject.Name = string.format("Debug%s_%s", normalizedRewardType, player.Name)
	rewardObject.Parent = getDebugSpawnFolder()

	local rootPart = getObjectRootPart(rewardObject)
	if not rootPart then
		rewardObject:Destroy()
		rewardObject = createDefaultRewardPart(rewardState)
		rewardObject.Name = string.format("Debug%s_%s", normalizedRewardType, player.Name)
		rewardObject.Parent = getDebugSpawnFolder()
		rootPart = rewardObject
	end

	setObjectCFrame(rewardObject, root.CFrame * CFrame.new(0, 1.5, -10))

	local highlight = Instance.new("Highlight")
	highlight.FillColor = if rootPart and rootPart:IsA("BasePart") then rootPart.Color else Color3.fromRGB(214, 155, 74)
	highlight.FillTransparency = if normalizedRewardType == "Chest" then 0.15 else 0.35
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = rewardObject

	addRewardBillboard(rootPart, rewardState, player)
	if normalizedRewardType == "Chest" then
		addChestDebugBeacon(rootPart)
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpPrompt"
	configureRewardPickupPrompt(prompt, rewardState)
	prompt.Parent = rootPart

	prompt.Triggered:Connect(function(triggerPlayer)
		if triggerPlayer ~= player then
			return
		end

		applyCarriedRewardState(player, rewardObject, rootPart, getDebugCarriedFolder())
	end)

	return true, rewardObject
end

function Controller.SpawnSharedChestInFrontOfPlayer(player)
	if not player or player.Parent ~= Players then
		return false, "player_not_ready"
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false, "character_not_ready"
	end

	local rewardFolder = getDebugSpawnFolder()
	local _carriedFolder = getDebugCarriedFolder()
	local rewardState = SliceService.CreateChestRewardData(Economy.VerticalSlice.WorldRun.StartDepthBand or Economy.VerticalSlice.DefaultDepthBand)
	rewardState.DisplayName = string.format("%s Chest", tostring(rewardState.Tier or "Wooden"))

	local rewardObject = createRewardInstance(rewardState)
	sharedChestSequence += 1
	local chestId = tostring(sharedChestSequence)
	rewardObject.Name = string.format("SharedChestDebug_%s", chestId)
	rewardObject:SetAttribute("RewardType", "Chest")
	rewardObject:SetAttribute("SharedWorldChest", true)
	rewardObject:SetAttribute("SharedChestId", chestId)
	rewardObject.Parent = rewardFolder

	local rootPart = getObjectRootPart(rewardObject)
	if not rootPart then
		rewardObject:Destroy()
		return false, "missing_root_part"
	end

	setObjectCFrame(rewardObject, root.CFrame * CFrame.new(0, 1.5, -10))

	local highlight = Instance.new("Highlight")
	highlight.FillColor = if rootPart and rootPart:IsA("BasePart") then rootPart.Color else Color3.fromRGB(214, 155, 74)
	highlight.FillTransparency = 0.15
	highlight.OutlineColor = Color3.new(1, 1, 1)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = rewardObject

	addRewardBillboard(rootPart, rewardState, nil)
	addChestDebugBeacon(rootPart)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickUpPrompt"
	configureRewardPickupPrompt(prompt, rewardState)
	prompt.Parent = rootPart

	local node = {
		Id = chestId,
		Object = rewardObject,
		RootPart = rootPart,
		RewardState = rewardState,
		SpawnPart = nil,
		Claimed = false,
	}
	sharedChestNodesById[chestId] = node

	prompt.Triggered:Connect(function(triggerPlayer)
		local currentNode = sharedChestNodesById[chestId]
		if currentNode ~= node or node.Claimed then
			return
		end

		node.Claimed = true
		local response = SliceService.ClaimWorldChest(triggerPlayer, node.RewardState)
		if not response or not response.ok then
			node.Claimed = false
			sendPopup(triggerPlayer, buildResponseMessage(response, "Could not pick up chest."), ERROR_COLOR, true)
			return
		end

		sharedChestNodesById[chestId] = nil
		if rewardObject.Parent then
			rewardObject:Destroy()
		end
	end)

	return true, rewardObject
end

function Controller.AttachCarriedRewardToPart(player, carrierPart)
	if not player or player.Parent ~= Players then
		return false, "player_not_ready"
	end
	local requestedCarrier = carrierPart
	if not carrierPart or not carrierPart:IsA("BasePart") or not carrierPart.Parent then
		carrierPart = getActiveHoroCarrierPart(player)
	end
	if not carrierPart or not carrierPart:IsA("BasePart") or not carrierPart.Parent then
		horoCarryTrace(
			"reattachRequest failed player=%s requestedCarrier=%s reason=carrier_not_ready carryAttrs={%s} runtime={%s}",
			player and player.Name or "<nil>",
			formatInstancePath(requestedCarrier),
			getPlayerCarrySummary(player),
			getRunRewardSummary(player)
		)
		return false, "carrier_not_ready"
	end
	horoCarryTrace(
		"reattachRequest begin player=%s requestedCarrier=%s resolvedCarrier=%s carryAttrs={%s} runtime={%s}",
		player and player.Name or "<nil>",
		formatInstancePath(requestedCarrier),
		formatInstancePath(carrierPart),
		getPlayerCarrySummary(player),
		getRunRewardSummary(player)
	)

	local state = SliceService.GetState(player)
	local runState = state and state.Run or {}
	local carrySlots = runState.CarrySlots or {}
	local hasCarriedSlot = false
	for _, slot in ipairs(carrySlots) do
		if slot.Occupied == true then
			hasCarriedSlot = true
			break
		end
	end
	if not hasCarriedSlot then
		horoCarryTrace(
			"reattachRequest failed player=%s resolvedCarrier=%s reason=no_carried_reward runtime={%s}",
			player and player.Name or "<nil>",
			formatInstancePath(carrierPart),
			getRunRewardSummary(player)
		)
		return false, "no_carried_reward"
	end

	local attachedAny = false
	local carryOffsetMap = CarriedRewardVisuals.BuildOffsetMap(carrySlots, CARRY_VISUAL_SPACING)
	for _, slot in ipairs(carrySlots) do
		local rewardState = buildRewardStateFromCarrySlot(slot)
		if rewardState then
			rewardState.CarryVisualOffset = carryOffsetMap[tostring(slot.CarryId or "")] or 0
			local rewardObject = getRewardObject(player.UserId, getCarryObjectKey(slot))
			local rootPart = getObjectRootPart(rewardObject)
			if rewardObject and rewardObject.Parent and rootPart then
				if applyCarriedRewardState(player, rewardObject, rootPart, rewardObject.Parent, carrierPart, rewardState) then
					attachedAny = true
				end
			end
		end
	end

	if attachedAny then
		horoCarryTrace(
			"reattachRequest complete player=%s resolvedCarrier=%s success=true",
			player and player.Name or "<nil>",
			formatInstancePath(carrierPart)
		)
		return true
	end

	return false, "reward_object_not_ready"
end

local function attachCarriedRewardToPartSoon(player, carrierPart)
	task.spawn(function()
		for _ = 1, 8 do
			local attached = Controller.AttachCarriedRewardToPart(player, carrierPart)
			if attached then
				return
			end
			task.wait(0.05)
		end
	end)
end

local function getRewardObjectDistance(rewardObject, worldPosition)
	local rootPart = getObjectRootPart(rewardObject)
	if not rootPart or typeof(worldPosition) ~= "Vector3" then
		return math.huge, nil
	end

	return (rootPart.Position - worldPosition).Magnitude, rootPart
end

function Controller.TryClaimRewardNearPosition(player, worldPosition, carrierPart, maxDistance)
	if not player or player.Parent ~= Players then
		return false, "player_not_ready"
	end
	if typeof(worldPosition) ~= "Vector3" then
		return false, "invalid_position"
	end
	local requestedCarrier = carrierPart
	if not carrierPart or not carrierPart:IsA("BasePart") or not carrierPart.Parent then
		carrierPart = getActiveHoroCarrierPart(player)
	end
	if not carrierPart or not carrierPart:IsA("BasePart") or not carrierPart.Parent then
		horoCarryTrace(
			"pickupBegin failed player=%s worldPos=%s requestedCarrier=%s reason=carrier_not_ready carryAttrs={%s} runtime={%s}",
			player and player.Name or "<nil>",
			formatVector3(worldPosition),
			formatInstancePath(requestedCarrier),
			getPlayerCarrySummary(player),
			getRunRewardSummary(player)
		)
		return false, "carrier_not_ready"
	end

	local searchRadius = math.max(0, tonumber(maxDistance) or 0)
	if searchRadius <= 0 then
		return false, "invalid_radius"
	end

	local state = SliceService.GetState(player)
	local runState = state and state.Run or {}
	horoCarryTrace(
		"pickupBegin player=%s worldPos=%s requestedCarrier=%s resolvedCarrier=%s radius=%s carryAttrs={%s} runtime={%s}",
		player and player.Name or "<nil>",
		formatVector3(worldPosition),
		formatInstancePath(requestedCarrier),
		formatInstancePath(carrierPart),
		tostring(searchRadius),
		getPlayerCarrySummary(player),
		getRunRewardSummary(player)
	)
	if SliceService.HasCarryItems and SliceService.HasCarryItems(player) then
		Controller.AttachCarriedRewardToPart(player, carrierPart)
		if not (SliceService.CanCarryMore and SliceService.CanCarryMore(player)) then
			horoCarryTrace(
				"pickupResult player=%s outcome=carry_slots_full resolvedCarrier=%s runtime={%s}",
				player and player.Name or "<nil>",
				formatInstancePath(carrierPart),
				getRunRewardSummary(player)
			)
			return true, {
				Kind = "MajorReward",
				AlreadyCarried = true,
			}
		end
	end

	if runState.SpawnedReward ~= nil then
		local rewardObject = getRewardObject(player.UserId, "spawned")
		local distance = getRewardObjectDistance(rewardObject, worldPosition)
		if distance <= searchRadius then
			local response = SliceService.ClaimSpawnedReward(player)
			if response and response.ok then
				horoCarryTrace(
					"pickupResult player=%s outcome=claim_spawned_reward reward=%s distance=%.2f carryAttrs={%s} runtimeBeforeAttach={%s}",
					player and player.Name or "<nil>",
					formatInstancePath(rewardObject),
					distance,
					getPlayerCarrySummary(player),
					getRunRewardSummary(player)
				)
				attachCarriedRewardToPartSoon(player, carrierPart)
				return true, {
					Kind = "MajorReward",
					RewardType = tostring(runState.SpawnedReward.RewardType or ""),
					Distance = distance,
				}
			end

			horoCarryTrace(
				"pickupResult player=%s outcome=claim_spawned_reward_failed error=%s reward=%s distance=%.2f",
				player and player.Name or "<nil>",
				tostring(response and response.error),
				formatInstancePath(rewardObject),
				distance
			)
			return false, response and response.error or "claim_failed"
		end
	end

	local bestNode = nil
	local bestDistance = searchRadius
	for _, node in pairs(sharedChestNodesById) do
		if node and node.Object and node.Object.Parent and not node.Claimed then
			local distance = getRewardObjectDistance(node.Object, worldPosition)
			if distance <= bestDistance then
				bestDistance = distance
				bestNode = node
			end
		end
	end

	if not bestNode then
		horoCarryTrace(
			"pickupResult player=%s outcome=no_reward_in_range worldPos=%s radius=%s",
			player and player.Name or "<nil>",
			formatVector3(worldPosition),
			tostring(searchRadius)
		)
		return false, "no_reward_in_range"
	end

	bestNode.Claimed = true
	local response = SliceService.ClaimWorldChest(player, bestNode.RewardState)
	if not response or not response.ok then
		bestNode.Claimed = false
		horoCarryTrace(
			"pickupResult player=%s outcome=claim_shared_chest_failed chestId=%s error=%s",
			player and player.Name or "<nil>",
			tostring(bestNode.Id),
			tostring(response and response.error)
		)
		return false, response and response.error or "claim_failed"
	end

	sharedChestNodesById[bestNode.Id] = nil
	if bestNode.Object and bestNode.Object.Parent then
		bestNode.Object:Destroy()
	end

	horoCarryTrace(
		"pickupResult player=%s outcome=claim_shared_chest chestId=%s distance=%.2f carryAttrs={%s} runtimeBeforeAttach={%s}",
		player and player.Name or "<nil>",
		tostring(bestNode.Id),
		bestDistance,
		getPlayerCarrySummary(player),
		getRunRewardSummary(player)
	)
	attachCarriedRewardToPartSoon(player, carrierPart)
	return true, {
		Kind = "MajorReward",
		RewardType = "Chest",
		SharedChestId = tostring(bestNode.Id or ""),
		Distance = bestDistance,
	}
end

return Controller
