local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local ChestVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestVisuals"))
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

local SUCCESS_COLOR = Color3.fromRGB(98, 255, 124)
local ERROR_COLOR = Color3.fromRGB(255, 104, 104)
local INFO_COLOR = Color3.fromRGB(119, 217, 255)
local STROKE_COLOR = Color3.fromRGB(0, 0, 0)

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

local function getWaveParts()
	local map = Workspace:FindFirstChild("Map")
	local waveFolder = map and map:FindFirstChild("WaveFolder")
	local startPart = waveFolder and waveFolder:FindFirstChild("Start")
	local endPart = waveFolder and waveFolder:FindFirstChild("End")
	if not (startPart and startPart:IsA("BasePart") and endPart and endPart:IsA("BasePart")) then
		return nil
	end

	return waveFolder, startPart, endPart
end

local function getMapHitBox()
	local map = Workspace:FindFirstChild("Map")
	local hitBox = map and map:FindFirstChild("HitBox")
	if hitBox and hitBox:IsA("BasePart") then
		return hitBox
	end

	return nil
end

local function waitForWaveParts(timeoutSeconds)
	local deadline = os.clock() + (timeoutSeconds or 10)
	while os.clock() <= deadline do
		local waveFolder, startPart, endPart = getWaveParts()
		if waveFolder and startPart and endPart then
			return waveFolder, startPart, endPart
		end
		task.wait(0.2)
	end

	return getWaveParts()
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
	local map = Workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("SpawnPart")
end

local function getNearestBrainrotSpawnContext(player)
	local spawnFolder = getSpawnPartsFolder()
	if not spawnFolder then
		return nil
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local referencePosition = hrp and hrp.Position
	if not referencePosition then
		return nil
	end

	local nearestContext = nil
	local nearestDistance = math.huge
	local nearestSpawnPart = nil
	local nearestSpawnPartDistance = math.huge

	for _, spawnPart in ipairs(spawnFolder:GetChildren()) do
		if spawnPart:IsA("BasePart") then
			local spawnDistance = (spawnPart.Position - referencePosition).Magnitude
			if spawnDistance < nearestSpawnPartDistance then
				nearestSpawnPartDistance = spawnDistance
				nearestSpawnPart = spawnPart
			end

			local brainrotsFolder = spawnPart:FindFirstChild("Brainrots")
			if brainrotsFolder then
				for _, candidate in ipairs(brainrotsFolder:GetChildren()) do
					local rootPart = getObjectRootPart(candidate)
					if rootPart then
						local distance = (rootPart.Position - referencePosition).Magnitude
						if distance < nearestDistance then
							nearestDistance = distance
							nearestContext = {
								SpawnPart = spawnPart,
								Brainrot = candidate,
							}
						end
					end
				end
			end
		end
	end

	if nearestContext then
		return nearestContext
	end

	if nearestSpawnPart then
		return {
			SpawnPart = nearestSpawnPart,
			Brainrot = nil,
		}
	end

	return nil
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

	local spawnContext = getNearestBrainrotSpawnContext(player)
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
		Vector2.zero,
	}

	local occupiedOffsets = getOccupiedSpawnOffsets(spawnPart, spawnContext.Brainrot)
	local chosenOffset = clampLocalXZToSpawnPart(spawnPart, rewardObject, candidateOffsets[#candidateOffsets])
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

local function positionRewardObject(player, rewardObject, rewardState, startPart, endPart)
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

local function applyCarriedRewardState(player, rewardObject, rootPart, carriedFolder)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not head or not humanoid or humanoid.Health <= 0 then
		return false
	end

	clearCarryWeld(rootPart)
	rewardObject.Parent = carriedFolder
	setRewardHeldPhysics(rewardObject, true)

	local prompt = rootPart:FindFirstChild("PickUpPrompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = false
	end

	local top = head.Position + Vector3.yAxis * (head.Size.Y / 2)
	local targetPivot = computePivotBottomOnPoint(rewardObject, top, computeHeadRotOnly(head))
	setObjectCFrame(rewardObject, targetPivot)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "RewardCarryWeld"
	weld.Part0 = rootPart
	weld.Part1 = head
	weld.Parent = rootPart

	return true
end

local function getAllSharedChestSpawnContexts()
	local spawnFolder = getSpawnPartsFolder()
	if not spawnFolder then
		return {}
	end

	local contexts = {}
	for _, spawnPart in ipairs(spawnFolder:GetChildren()) do
		if spawnPart:IsA("BasePart") then
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
		Vector2.zero,
	}

	local occupiedOffsets = getOccupiedSpawnOffsets(spawnPart, spawnContext.Brainrot)
	for _, offset in ipairs(getOccupiedSharedChestOffsets(spawnPart)) do
		occupiedOffsets[#occupiedOffsets + 1] = offset
	end

	local chosenOffset = clampLocalXZToSpawnPart(spawnPart, rewardObject, candidateOffsets[#candidateOffsets])
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
		carriedSharedChestByUserId[triggerPlayer.UserId] = {
			ChestId = chestId,
			Object = rewardObject,
			RootPart = rootPart,
		}

		rewardObject:SetAttribute("ClaimedByUserId", triggerPlayer.UserId)
		if not applyCarriedRewardState(triggerPlayer, rewardObject, rootPart, carriedFolder) then
			destroyCarriedSharedChest(triggerPlayer.UserId)
			SliceService.FailRun(triggerPlayer, "Could not carry the chest. The reward was lost.")
			sendPopup(triggerPlayer, "Could not carry chest.", ERROR_COLOR, true)
			return
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
	if runState.InRun == true and spawnedReward ~= nil then
		createRewardObject(player, spawnedReward, rewardFolder, carriedFolder, startPart, endPart, false)
		return
	end

	if runState.InRun == true and carriedReward ~= nil then
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

	local waveFolder, startPart, endPart = waitForWaveParts(15)
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

	local function tryExtractFromTouch(hit)
		local player = findPlayerFromHit(hit)
		if not player or not canTriggerExtraction(player) then
			return
		end

		local state = SliceService.GetState(player)
		local runState = state and state.Run or {}
		if runState.CarriedReward == nil then
			return
		end

		local response = SliceService.ExtractRun(player)
		if response.ok then
			sendPopup(player, buildResponseMessage(response, "Reward extracted."), SUCCESS_COLOR, false)
		else
			sendPopup(player, buildResponseMessage(response, "Could not extract reward."), ERROR_COLOR, true)
		end
	end

	extractionZone.Touched:Connect(tryExtractFromTouch)
	if sharedHitBox then
		sharedHitBox.Touched:Connect(tryExtractFromTouch)
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
		carriedSharedChestByUserId[triggerPlayer.UserId] = {
			ChestId = chestId,
			Object = rewardObject,
			RootPart = rootPart,
		}

		if not applyCarriedRewardState(triggerPlayer, rewardObject, rootPart, carriedFolder) then
			destroyCarriedSharedChest(triggerPlayer.UserId)
			SliceService.FailRun(triggerPlayer, "Could not carry the chest. The reward was lost.")
			sendPopup(triggerPlayer, "Could not carry chest.", ERROR_COLOR, true)
			return
		end
	end)

	return true, rewardObject
end

return Controller
