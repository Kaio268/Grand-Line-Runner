local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestVisuals"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local SpawnPartsConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SpawnParts"))
local PopUpModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("PopUpModule"))
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
local worldRandom = Random.new()
local DEBUG_TRACE = RunService:IsStudio()
local loggedExtractionTouchByPlayer = {}
local VALID_SPAWN_RARITY_NAMES = SpawnPartsConfig.RarityTier or {}

local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local INFO_COLOR = Color3.fromRGB(119, 217, 255)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local HORO_EFFECTS_FOLDER_NAME = "DevilFruitWorldEffects"
local HORO_GHOSTS_FOLDER_NAME = "HoroGhosts"

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
		"attrMajor=%s attrMajorName=%s attrBrainrot=%s horoActive=%s horoProjectionId=%s horoCarrying=%s",
		tostring(player:GetAttribute("CarriedMajorRewardType")),
		tostring(player:GetAttribute("CarriedMajorRewardDisplayName")),
		tostring(player:GetAttribute("CarriedBrainrot")),
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
	return string.format(
		"inRun=%s carried=%s carriedType=%s spawned=%s spawnedType=%s spawnedDrop=%s",
		tostring(runState.InRun),
		tostring(carriedReward ~= nil),
		tostring(carriedReward and carriedReward.RewardType or nil),
		tostring(spawnedReward ~= nil),
		tostring(spawnedReward and spawnedReward.RewardType or nil),
		formatVector3(spawnedReward and spawnedReward.WorldDropPosition or nil)
	)
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

local function destroyRewardObject(userId)
	local object = rewardObjectsByUserId[userId]
	if object and object.Parent then
		object:Destroy()
	end
	rewardObjectsByUserId[userId] = nil
	rewardPlacementsByUserId[userId] = nil
end

local function destroySharedChestNode(chestId)
	local node = sharedChestNodesById[chestId]
	if not node then
		return
	end

	local object = node.Object
	if object and object.Parent then
		object:Destroy()
	end

	sharedChestNodesById[chestId] = nil
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

local function getBiomeSpawnParts()
	local refs = MapResolver.GetRefs()
	local mapRoot = refs.MapRoot
	local biomesRoot = mapRoot and mapRoot:FindFirstChild("Biomes")
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
			if innerBiome then
				waveTrace(
					"chestSpawnDiscovery biome=%s innerBiome=%s",
					formatInstancePath(biomeContainer),
					formatInstancePath(innerBiome)
				)
				for _, descendant in ipairs(innerBiome:GetDescendants()) do
					if isValidSpawnRarityPart(descendant) then
						spawnParts[#spawnParts + 1] = descendant
					end
				end
			else
				waveTrace(
					"chestSpawnDiscovery skippedBiome=%s reason=missing_inner_biome expected=%s",
					formatInstancePath(biomeContainer),
					tostring(biomeContainer.Name)
				)
			end
		end
	else
		local spawnFolder = getSpawnPartsFolder()
		waveTrace(
			"chestSpawnDiscovery mode=LegacySpawnFolder map=%s spawnFolder=%s",
			formatInstancePath(mapRoot),
			formatInstancePath(spawnFolder)
		)
		if spawnFolder then
			for _, spawnPart in ipairs(spawnFolder:GetChildren()) do
				if isValidSpawnRarityPart(spawnPart) then
					spawnParts[#spawnParts + 1] = spawnPart
				end
			end
		end
	end

	waveTrace("chestSpawnDiscovery resultCount=%s", tostring(#spawnParts))
	return spawnParts
end

local function getAllBrainrotSpawnContexts()
	local contexts = {}

	for _, spawnPart in ipairs(getBiomeSpawnParts()) do
		local brainrotsFolder = spawnPart:FindFirstChild("Brainrots")
		local hadBrainrot = false
		if brainrotsFolder then
			for _, candidate in ipairs(brainrotsFolder:GetChildren()) do
				if getObjectRootPart(candidate) then
					hadBrainrot = true
					contexts[#contexts + 1] = {
						SpawnPart = spawnPart,
						Brainrot = candidate,
					}
				end
			end
		end

		if not hadBrainrot then
			contexts[#contexts + 1] = {
				SpawnPart = spawnPart,
				Brainrot = nil,
			}
		end
	end

	return contexts
end

local function chooseRandomBrainrotSpawnContext()
	local contexts = getAllBrainrotSpawnContexts()
	if #contexts == 0 then
		return nil
	end

	local chosen = contexts[worldRandom:NextInteger(1, #contexts)]
	local chosenBrainrotRoot = getObjectRootPart(chosen.Brainrot)
	waveTrace(
		"chestSpawnContext chosenCount=%s chosenSpawnPart=%s chosenSpawnPartPos=%s sourceBrainrot=%s sourceBrainrotPos=%s",
		tostring(#contexts),
		formatInstancePath(chosen.SpawnPart),
		formatVector3(chosen.SpawnPart and chosen.SpawnPart.Position or nil),
		formatInstancePath(chosen.Brainrot),
		formatVector3(chosenBrainrotRoot and chosenBrainrotRoot.Position or nil)
	)
	return chosen
end

local function getOccupiedSpawnOffsets(spawnPart, ignoreInstance)
	local offsets = {}
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return offsets
	end

	local brainrotsFolder = spawnPart:FindFirstChild("Brainrots")
	if not brainrotsFolder then
		return offsets
	end

	for _, candidate in ipairs(brainrotsFolder:GetChildren()) do
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

	local spawnContext = chooseRandomBrainrotSpawnContext()
	if not spawnContext or not spawnContext.SpawnPart then
		waveTrace("chestPlacement skipped player=%s reason=no_spawn_context", player.Name)
		return nil
	end

	local spawnPart = spawnContext.SpawnPart
	local baseOffset = Vector2.zero
	if spawnContext.Brainrot then
		local brainrotRoot = getObjectRootPart(spawnContext.Brainrot)
		if brainrotRoot then
			baseOffset = worldToSpawnLocalXZ(spawnPart, brainrotRoot.Position)
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
	if not spawnContext.Brainrot then
		candidateOffsets[#candidateOffsets + 1] = Vector2.zero
	end

	local occupiedOffsets = getOccupiedSpawnOffsets(spawnPart, spawnContext.Brainrot)
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
		SourceBrainrotName = spawnContext.Brainrot and spawnContext.Brainrot.Name or nil,
	}
	rewardPlacementsByUserId[player.UserId] = placement
	waveTrace(
		"chestPlacement player=%s spawnPart=%s spawnPartPos=%s sourceBrainrot=%s localXZ=%s",
		player.Name,
		formatInstancePath(spawnPart),
		formatVector3(spawnPart.Position),
		tostring(placement.SourceBrainrotName),
		formatVector3(Vector3.new(chosenOffset.X, 0, chosenOffset.Y))
	)
	return placement
end

local function buildChestPlacementHint(placement)
	if not placement or not placement.SpawnPart then
		return nil
	end

	if placement.SourceBrainrotName and placement.SourceBrainrotName ~= "" then
		return string.format(
			"Chest spawned on %s near %s.",
			tostring(placement.SpawnPart.Name),
			tostring(placement.SourceBrainrotName)
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
	forEachRewardPart(object, function(part)
		part.Anchored = not held
		part.CanCollide = false
		part.CanTouch = false
		part.Massless = held
		part.AssemblyLinearVelocity = Vector3.zero
		part.AssemblyAngularVelocity = Vector3.zero
	end)
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
	if player then
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

local function addChestDebugBeacon(rootPart)
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

local function applyCarriedRewardState(player, rewardObject, rootPart, carriedFolder, carrierPartOverride)
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

local function getAllSharedChestSpawnContexts()
	local contexts = {}
	for _, context in ipairs(getAllBrainrotSpawnContexts()) do
		contexts[#contexts + 1] = context
	end

	return contexts
end

local function chooseSharedChestSpawnContext()
	local contexts = getAllSharedChestSpawnContexts()
	if #contexts == 0 then
		return nil
	end

	return contexts[worldRandom:NextInteger(1, #contexts)]
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
	if spawnContext.Brainrot then
		local brainrotRoot = getObjectRootPart(spawnContext.Brainrot)
		if brainrotRoot then
			baseOffset = worldToSpawnLocalXZ(spawnPart, brainrotRoot.Position)
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
	if not spawnContext.Brainrot then
		candidateOffsets[#candidateOffsets + 1] = Vector2.zero
	end

	local occupiedOffsets = getOccupiedSpawnOffsets(spawnPart, spawnContext.Brainrot)
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
		SourceBrainrotName = spawnContext.Brainrot and spawnContext.Brainrot.Name or nil,
	}
end

local function getDepthBandForSharedChestSpawn(spawnPart)
	local sharedConfig = Economy.VerticalSlice.WorldRun.SharedChests or {}
	local tierMap = SpawnPartsConfig.RarityTier or {}
	local depthBandByTier = sharedConfig.SpawnTierToDepthBand or {}
	local spawnTier = tonumber(tierMap[tostring(spawnPart and spawnPart.Name or "")]) or 1
	return tostring(depthBandByTier[spawnTier] or Economy.VerticalSlice.DefaultDepthBand)
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

local function spawnSharedChestNode(rewardFolder, carriedFolder)
	local spawnContext = chooseSharedChestSpawnContext()
	if not spawnContext or not spawnContext.SpawnPart then
		return nil
	end

	local depthBand = getDepthBandForSharedChestSpawn(spawnContext.SpawnPart)
	local rewardState = SliceService.CreateChestRewardData(depthBand)
	rewardState.DisplayName = string.format("%s Chest", tostring(rewardState.Tier or "Wooden"))

	local rewardObject = createRewardInstance(rewardState)
	sharedChestSequence += 1
	local chestId = tostring(sharedChestSequence)
	rewardObject.Name = string.format("SharedChest_%s", chestId)
	rewardObject:SetAttribute("RewardType", "Chest")
	rewardObject:SetAttribute("SharedWorldChest", true)
	rewardObject:SetAttribute("SharedChestId", chestId)
	rewardObject.Parent = rewardFolder

	local rootPart = getObjectRootPart(rewardObject)
	if not rootPart then
		rewardObject:Destroy()
		rewardObject = createDefaultRewardPart(rewardState)
		rewardObject.Name = string.format("SharedChest_%s", chestId)
		rewardObject:SetAttribute("RewardType", "Chest")
		rewardObject:SetAttribute("SharedWorldChest", true)
		rewardObject:SetAttribute("SharedChestId", chestId)
		rewardObject.Parent = rewardFolder
		rootPart = rewardObject
	end

	local placement = buildSharedChestPlacement(rewardObject, spawnContext)
	if placement then
		waveTrace(
			"sharedChestPlacement chestId=%s spawnPart=%s spawnPartPos=%s sourceBrainrot=%s localXZ=%s",
			tostring(chestId),
			formatInstancePath(placement.SpawnPart),
			formatVector3(placement.SpawnPart and placement.SpawnPart.Position or nil),
			tostring(placement.SourceBrainrotName),
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
	end

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
		SpawnPart = spawnContext.SpawnPart,
		Claimed = false,
	}
	sharedChestNodesById[chestId] = node

	prompt.Triggered:Connect(function(triggerPlayer)
		local currentNode = sharedChestNodesById[chestId]
		if currentNode ~= node or node.Claimed then
			return
		end
		if triggerPlayer:GetAttribute("CarriedBrainrot") ~= nil then
			sendPopup(triggerPlayer, "You cannot pick up a chest while carrying a brainrot.", ERROR_COLOR, true)
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

		sendPopup(triggerPlayer, buildResponseMessage(response, "Chest picked up. Bring it back to extract."), SUCCESS_COLOR, false)
	end)

	return node
end

local function ensureSharedChestNodes(rewardFolder, carriedFolder)
	local sharedConfig = Economy.VerticalSlice.WorldRun.SharedChests or {}
	if sharedConfig.Enabled ~= true then
		return
	end

	local maxActive = math.max(0, tonumber(sharedConfig.MaxActive) or 0)
	if maxActive <= 0 then
		return
	end

	local activeCount = countActiveSharedChests()
	if activeCount == 0 then
		while activeCount < maxActive do
			if not spawnSharedChestNode(rewardFolder, carriedFolder) then
				break
			end
			activeCount += 1
		end
		nextSharedChestRespawnAt = os.clock() + (tonumber(sharedConfig.RespawnDelay) or 10)
		return
	end

	if activeCount < maxActive and os.clock() >= nextSharedChestRespawnAt then
		if spawnSharedChestNode(rewardFolder, carriedFolder) then
			nextSharedChestRespawnAt = os.clock() + (tonumber(sharedConfig.RespawnDelay) or 10)
		end
	end
end

local function createRewardObject(player, rewardState, rewardFolder, carriedFolder, startPart, endPart, isCarried)
	local rewardKey = buildRewardKey(rewardState)
	local existing = rewardObjectsByUserId[player.UserId]
	if existing and existing.Parent and existing:GetAttribute("RewardKey") == rewardKey then
		local existingRoot = getObjectRootPart(existing)
		if existingRoot then
			if isCarried then
				applyCarriedRewardState(player, existing, existingRoot, carriedFolder)
			else
				applySpawnedRewardState(player, existing, existingRoot, rewardState, rewardFolder, startPart, endPart)
			end
		end
		return
	end

	destroyRewardObject(player.UserId)

	local rewardObject = createRewardInstance(rewardState)
	rewardObject.Name = string.format("RunReward_%d", player.UserId)
	rewardObject:SetAttribute("OwnerUserId", player.UserId)
	rewardObject:SetAttribute("RewardKey", rewardKey)
	rewardObject:SetAttribute("RewardType", rewardState.RewardType)
	rewardObject.Parent = rewardFolder

	local rootPart = getObjectRootPart(rewardObject)
	if not rootPart then
		rewardObject:Destroy()
		rewardObject = createDefaultRewardPart(rewardState)
		rewardObject.Name = string.format("RunReward_%d", player.UserId)
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
		if triggerPlayer:GetAttribute("CarriedBrainrot") ~= nil then
			sendPopup(triggerPlayer, "You cannot pick up a chest or crew reward while carrying a brainrot.", ERROR_COLOR, true)
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
		if not applyCarriedRewardState(player, rewardObject, rootPart, carriedFolder) then
			applySpawnedRewardState(player, rewardObject, rootPart, rewardState, rewardFolder, startPart, endPart)
		end
	else
		applySpawnedRewardState(player, rewardObject, rootPart, rewardState, rewardFolder, startPart, endPart)
	end

	rewardObjectsByUserId[player.UserId] = rewardObject
end

local function syncPlayerRewardObject(player, state, rewardFolder, carriedFolder, startPart, endPart)
	local runState = state and state.Run or {}
	local spawnedReward = runState.SpawnedReward
	local carriedReward = runState.CarriedReward
	if spawnedReward ~= nil then
		createRewardObject(player, spawnedReward, rewardFolder, carriedFolder, startPart, endPart, false)
		return
	end

	if carriedReward ~= nil then
		createRewardObject(player, carriedReward, rewardFolder, carriedFolder, startPart, endPart, true)
		return
	end

	destroyRewardObject(player.UserId)
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
		if runState.CarriedReward == nil then
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
			if carriedSharedChestByUserId[player.UserId] and not (state and state.Run and state.Run.CarriedReward) then
				destroyCarriedSharedChest(player.UserId)
				nextSharedChestRespawnAt = math.min(nextSharedChestRespawnAt, os.clock())
			end
		end
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
		local interval = math.max(1, tonumber((Economy.VerticalSlice.WorldRun.SharedChests or {}).RespawnCheckInterval) or 5)
		while started do
			ensureSharedChestNodes(rewardFolder, carriedFolder)
			task.wait(interval)
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
	local carriedFolder = getDebugCarriedFolder()
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
	if runState.CarriedReward == nil then
		horoCarryTrace(
			"reattachRequest failed player=%s resolvedCarrier=%s reason=no_carried_reward runtime={%s}",
			player and player.Name or "<nil>",
			formatInstancePath(carrierPart),
			getRunRewardSummary(player)
		)
		return false, "no_carried_reward"
	end

	local rewardObject = rewardObjectsByUserId[player.UserId]
	local rootPart = getObjectRootPart(rewardObject)
	if not rewardObject or not rewardObject.Parent or not rootPart then
		horoCarryTrace(
			"reattachRequest failed player=%s resolvedCarrier=%s reason=reward_object_not_ready reward=%s",
			player and player.Name or "<nil>",
			formatInstancePath(carrierPart),
			formatInstancePath(rewardObject)
		)
		return false, "reward_object_not_ready"
	end

	if applyCarriedRewardState(player, rewardObject, rootPart, rewardObject.Parent, carrierPart) then
		horoCarryTrace(
			"reattachRequest complete player=%s resolvedCarrier=%s success=true reward=%s",
			player and player.Name or "<nil>",
			formatInstancePath(carrierPart),
			formatInstancePath(rewardObject)
		)
		return true, rewardObject
	end

	horoCarryTrace(
		"reattachRequest failed player=%s resolvedCarrier=%s reason=attach_failed reward=%s",
		player and player.Name or "<nil>",
		formatInstancePath(carrierPart),
		formatInstancePath(rewardObject)
	)
	return false, "attach_failed"
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
	if runState.CarriedReward ~= nil then
		if Controller.AttachCarriedRewardToPart(player, carrierPart) then
			horoCarryTrace(
				"pickupResult player=%s outcome=already_carried_reattached resolvedCarrier=%s runtime={%s}",
				player and player.Name or "<nil>",
				formatInstancePath(carrierPart),
				getRunRewardSummary(player)
			)
			return true, {
				Kind = "MajorReward",
				AlreadyCarried = true,
			}
		end

		horoCarryTrace(
			"pickupResult player=%s outcome=already_carrying_reward_attach_failed resolvedCarrier=%s runtime={%s}",
			player and player.Name or "<nil>",
			formatInstancePath(carrierPart),
			getRunRewardSummary(player)
		)
		return false, "already_carrying_reward"
	end

	if runState.SpawnedReward ~= nil then
		local rewardObject = rewardObjectsByUserId[player.UserId]
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
