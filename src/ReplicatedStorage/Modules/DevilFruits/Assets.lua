local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local DevilFruitAssets = {}

local ASSETS_FOLDER_NAME = "Assets"
local DEVIL_FRUITS_FOLDER_NAME = "DevilFruits"
local WORLD_MODEL_NAME = "WorldModel"
local generatedWorldModelsByFruitKey = {}

local function getDevilFruitAssetsFolder()
	local assetsFolder = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER_NAME)
	if not assetsFolder then
		assetsFolder = ReplicatedStorage:WaitForChild(ASSETS_FOLDER_NAME, 10)
	end

	if not assetsFolder then
		return nil
	end

	local devilFruitsFolder = assetsFolder:FindFirstChild(DEVIL_FRUITS_FOLDER_NAME)
	if not devilFruitsFolder then
		devilFruitsFolder = assetsFolder:WaitForChild(DEVIL_FRUITS_FOLDER_NAME, 10)
	end

	return devilFruitsFolder
end

local function resolveFruit(fruitIdentifier)
	if fruitIdentifier == DevilFruitConfig.None then
		return nil, "no_fruit"
	end

	local fruit = DevilFruitConfig.GetFruit(fruitIdentifier)
	if not fruit then
		return nil, "unknown_fruit"
	end

	return fruit
end

local function getSpawnCFrame(spawnTarget)
	if spawnTarget == nil then
		return nil
	end

	local targetType = typeof(spawnTarget)
	if targetType == "CFrame" then
		return spawnTarget
	end

	if targetType == "Vector3" then
		return CFrame.new(spawnTarget)
	end

	if targetType == "Instance" then
		if spawnTarget:IsA("Attachment") then
			return spawnTarget.WorldCFrame
		end

		if spawnTarget:IsA("PVInstance") then
			return spawnTarget:GetPivot()
		end
	end

	return nil
end

local function applyFruitAttributes(model, fruit)
	model:SetAttribute("FruitKey", fruit.FruitKey)
	model:SetAttribute("FruitName", fruit.DisplayName)
end

local function isSupportedWorldModel(instance)
	return instance and (instance:IsA("Model") or instance:IsA("WorldModel"))
end

local function findPrimaryPartCandidate(worldModel)
	if not isSupportedWorldModel(worldModel) then
		return nil
	end

	local primaryPart = worldModel.PrimaryPart
	if primaryPart and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	local handle = worldModel:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	local namedPart = worldModel:FindFirstChild("Part", true)
	if namedPart and namedPart:IsA("BasePart") then
		return namedPart
	end

	return worldModel:FindFirstChildWhichIsA("BasePart", true)
end

local function getBaseParts(instance)
	if not instance then
		return {}
	end

	if instance:IsA("BasePart") then
		return { instance }
	end

	local parts = {}
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end

	return parts
end

local function isRenderablePart(part)
	if not part or not part:IsA("BasePart") then
		return false
	end

	if part.Transparency < 0.98 then
		return true
	end

	return part:IsA("MeshPart")
		or part:IsA("UnionOperation")
		or part:FindFirstChildWhichIsA("SpecialMesh") ~= nil
end

local function getRenderableParts(instance)
	local renderableParts = {}
	for _, part in ipairs(getBaseParts(instance)) do
		if isRenderablePart(part) then
			renderableParts[#renderableParts + 1] = part
		end
	end

	return renderableParts
end

local function choosePreviewPrimaryPart(parts)
	local bestPart = nil
	local bestScore = -math.huge

	for _, part in ipairs(parts) do
		local transparencyBias = 1 - math.clamp(part.Transparency, 0, 1)
		local sizeScore = part.Size.X + part.Size.Y + part.Size.Z
		local handlePenalty = string.lower(part.Name) == "handle" and 1 or 0
		local score = (transparencyBias * 100) + sizeScore - (handlePenalty * 200)
		if score > bestScore then
			bestScore = score
			bestPart = part
		end
	end

	return bestPart
end

local function buildPreviewCloneFromModel(sourceModel, fruit)
	local sourceParts = getRenderableParts(sourceModel)
	if #sourceParts == 0 then
		sourceParts = getBaseParts(sourceModel)
	end

	if #sourceParts == 0 then
		return nil, "missing_preview_parts"
	end

	local previewModel = Instance.new("Model")
	previewModel.Name = WORLD_MODEL_NAME

	local clonedParts = {}
	for _, sourcePart in ipairs(sourceParts) do
		local clonedPart = sourcePart:Clone()
		for _, descendant in ipairs(clonedPart:GetDescendants()) do
			if descendant:IsA("JointInstance") or descendant:IsA("Constraint") then
				descendant:Destroy()
			end
		end
		clonedPart.Parent = previewModel
		clonedParts[#clonedParts + 1] = clonedPart
	end

	local primaryPart = choosePreviewPrimaryPart(clonedParts) or clonedParts[1]
	if primaryPart then
		previewModel.PrimaryPart = primaryPart
	end

	applyFruitAttributes(previewModel, fruit)
	return previewModel
end

local function setGeneratedPartDefaults(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function createGeneratedPart(parent, name, size, color, localCFrame, shape, material)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.CFrame = localCFrame
	part.Shape = shape or Enum.PartType.Block
	part.Material = material or Enum.Material.SmoothPlastic
	setGeneratedPartDefaults(part)
	part.Parent = parent
	return part
end

local function buildGeneratedBomuWorldModel(fruit)
	local model = Instance.new("Model")
	model.Name = WORLD_MODEL_NAME

	local body = createGeneratedPart(
		model,
		"Body",
		Vector3.new(2.2, 2.2, 2.2),
		Color3.fromRGB(208, 57, 47),
		CFrame.new(0, 0, 0),
		Enum.PartType.Ball,
		Enum.Material.SmoothPlastic
	)
	createGeneratedPart(
		model,
		"Cap",
		Vector3.new(0.95, 0.3, 0.95),
		Color3.fromRGB(38, 34, 32),
		CFrame.new(0, 0.88, 0),
		Enum.PartType.Cylinder,
		Enum.Material.SmoothPlastic
	)
	createGeneratedPart(
		model,
		"FuseBase",
		Vector3.new(0.32, 0.42, 0.32),
		Color3.fromRGB(245, 205, 95),
		CFrame.new(0, 1.18, 0),
		Enum.PartType.Cylinder,
		Enum.Material.Neon
	)
	createGeneratedPart(
		model,
		"Fuse",
		Vector3.new(0.14, 0.7, 0.14),
		Color3.fromRGB(52, 38, 32),
		CFrame.new(0.1, 1.52, 0),
		Enum.PartType.Cylinder,
		Enum.Material.Wood
	)
	createGeneratedPart(
		model,
		"Spark",
		Vector3.new(0.22, 0.22, 0.22),
		Color3.fromRGB(255, 227, 118),
		CFrame.new(0.16, 1.9, 0),
		Enum.PartType.Ball,
		Enum.Material.Neon
	)

	model.PrimaryPart = body
	applyFruitAttributes(model, fruit)
	return model
end

local function buildGeneratedMoguWorldModel(fruit)
	local model = Instance.new("Model")
	model.Name = WORLD_MODEL_NAME

	local body = createGeneratedPart(
		model,
		"Body",
		Vector3.new(2.15, 2.15, 2.15),
		Color3.fromRGB(125, 89, 56),
		CFrame.new(0, 0, 0),
		Enum.PartType.Ball,
		Enum.Material.SmoothPlastic
	)
	createGeneratedPart(
		model,
		"Underside",
		Vector3.new(1.55, 0.7, 1.55),
		Color3.fromRGB(228, 212, 184),
		CFrame.new(0, -0.45, 0),
		Enum.PartType.Ball,
		Enum.Material.SmoothPlastic
	)
	local band = createGeneratedPart(
		model,
		"Band",
		Vector3.new(2.25, 0.26, 2.25),
		Color3.fromRGB(88, 61, 38),
		CFrame.new(0, 0.18, 0),
		Enum.PartType.Cylinder,
		Enum.Material.SmoothPlastic
	)
	band.Orientation = Vector3.new(90, 0, 0)

	for index, offsetX in ipairs({ -0.38, 0, 0.38 }) do
		local claw = createGeneratedPart(
			model,
			string.format("Claw%d", index),
			Vector3.new(0.18, 0.58, 0.52),
			Color3.fromRGB(240, 231, 214),
			CFrame.new(offsetX, 0.92, -0.7) * CFrame.Angles(math.rad(-18), 0, 0),
			Enum.PartType.Block,
			Enum.Material.SmoothPlastic
		)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Parent = claw
	end

	model.PrimaryPart = body
	applyFruitAttributes(model, fruit)
	return model
end

local function buildGeneratedSukeWorldModel(fruit)
	local model = Instance.new("Model")
	model.Name = WORLD_MODEL_NAME

	local body = createGeneratedPart(
		model,
		"Body",
		Vector3.new(2.1, 2.1, 2.1),
		Color3.fromRGB(169, 238, 226),
		CFrame.new(0, 0, 0),
		Enum.PartType.Ball,
		Enum.Material.Glass
	)
	body.Transparency = 0.18

	local core = createGeneratedPart(
		model,
		"ShimmerCore",
		Vector3.new(1.25, 1.25, 1.25),
		Color3.fromRGB(234, 255, 251),
		CFrame.new(0, 0.04, 0),
		Enum.PartType.Ball,
		Enum.Material.Neon
	)
	core.Transparency = 0.58

	local band = createGeneratedPart(
		model,
		"MirageBand",
		Vector3.new(2.28, 0.16, 2.28),
		Color3.fromRGB(225, 255, 250),
		CFrame.new(0, 0.02, 0),
		Enum.PartType.Cylinder,
		Enum.Material.Neon
	)
	band.Orientation = Vector3.new(90, 0, 0)
	band.Transparency = 0.42

	local crossBand = createGeneratedPart(
		model,
		"MirageCrossBand",
		Vector3.new(0.16, 2.18, 2.18),
		Color3.fromRGB(122, 219, 212),
		CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Enum.PartType.Cylinder,
		Enum.Material.Neon
	)
	crossBand.Transparency = 0.54

	createGeneratedPart(
		model,
		"Stem",
		Vector3.new(0.28, 0.58, 0.28),
		Color3.fromRGB(74, 149, 134),
		CFrame.new(0.12, 1.2, 0) * CFrame.Angles(0, 0, math.rad(-15)),
		Enum.PartType.Cylinder,
		Enum.Material.SmoothPlastic
	)

	model.PrimaryPart = body
	applyFruitAttributes(model, fruit)
	return model
end

local function buildGeneratedHoroWorldModel(fruit)
	local model = Instance.new("Model")
	model.Name = WORLD_MODEL_NAME

	local body = createGeneratedPart(
		model,
		"Body",
		Vector3.new(2.05, 2.05, 2.05),
		Color3.fromRGB(188, 226, 255),
		CFrame.new(0, 0, 0),
		Enum.PartType.Ball,
		Enum.Material.Glass
	)
	body.Transparency = 0.16

	local core = createGeneratedPart(
		model,
		"GhostCore",
		Vector3.new(1.16, 1.16, 1.16),
		Color3.fromRGB(247, 253, 255),
		CFrame.new(0, 0.06, 0),
		Enum.PartType.Ball,
		Enum.Material.Neon
	)
	core.Transparency = 0.48

	local face = createGeneratedPart(
		model,
		"GhostFace",
		Vector3.new(1.18, 0.18, 0.16),
		Color3.fromRGB(68, 104, 136),
		CFrame.new(0, 0.16, -1.02),
		Enum.PartType.Block,
		Enum.Material.SmoothPlastic
	)
	face.Transparency = 0.18

	for index, offsetX in ipairs({ -0.32, 0.32 }) do
		createGeneratedPart(
			model,
			string.format("Eye%d", index),
			Vector3.new(0.18, 0.18, 0.18),
			Color3.fromRGB(255, 255, 255),
			CFrame.new(offsetX, 0.22, -1.13),
			Enum.PartType.Ball,
			Enum.Material.Neon
		)
	end

	local wisp = createGeneratedPart(
		model,
		"WispTail",
		Vector3.new(0.72, 1.2, 0.72),
		Color3.fromRGB(170, 214, 255),
		CFrame.new(0, -1.02, 0) * CFrame.Angles(0, 0, math.rad(16)),
		Enum.PartType.Cylinder,
		Enum.Material.Glass
	)
	wisp.Transparency = 0.32

	local halo = createGeneratedPart(
		model,
		"Halo",
		Vector3.new(2.28, 0.12, 2.28),
		Color3.fromRGB(235, 250, 255),
		CFrame.new(0, 0.24, 0),
		Enum.PartType.Cylinder,
		Enum.Material.Neon
	)
	halo.Orientation = Vector3.new(90, 0, 0)
	halo.Transparency = 0.38

	createGeneratedPart(
		model,
		"Stem",
		Vector3.new(0.24, 0.52, 0.24),
		Color3.fromRGB(96, 139, 169),
		CFrame.new(0.1, 1.14, 0) * CFrame.Angles(0, 0, math.rad(-18)),
		Enum.PartType.Cylinder,
		Enum.Material.SmoothPlastic
	)

	model.PrimaryPart = body
	applyFruitAttributes(model, fruit)
	return model
end

local GENERATED_WORLD_MODEL_BUILDERS = {
	Bomu = buildGeneratedBomuWorldModel,
	Horo = buildGeneratedHoroWorldModel,
	Mogu = buildGeneratedMoguWorldModel,
	Suke = buildGeneratedSukeWorldModel,
}

local function getGeneratedWorldModel(fruit)
	if not fruit then
		return nil
	end

	local cachedModel = generatedWorldModelsByFruitKey[fruit.FruitKey]
	if cachedModel then
		return cachedModel
	end

	local builder = GENERATED_WORLD_MODEL_BUILDERS[fruit.FruitKey]
	if typeof(builder) ~= "function" then
		return nil
	end

	local model = builder(fruit)
	if not isSupportedWorldModel(model) then
		return nil
	end

	local primaryPart = findPrimaryPartCandidate(model)
	if primaryPart and model.PrimaryPart ~= primaryPart then
		pcall(function()
			model.PrimaryPart = primaryPart
		end)
	end

	generatedWorldModelsByFruitKey[fruit.FruitKey] = model
	return model
end

function DevilFruitAssets.GetFruitFolder(fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return nil, reason
	end

	local devilFruitsFolder = getDevilFruitAssetsFolder()
	if not devilFruitsFolder then
		return nil, "missing_assets_root"
	end

	local fruitFolder = devilFruitsFolder:FindFirstChild(fruit.AssetFolder)
	if not fruitFolder then
		return nil, "missing_fruit_folder"
	end

	return fruitFolder, fruit
end

function DevilFruitAssets.GetWorldModel(fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return nil, reason
	end

	local fruitFolder, fruitOrReason = DevilFruitAssets.GetFruitFolder(fruit.FruitKey)
	if not fruitFolder then
		local generatedWorldModel = getGeneratedWorldModel(fruit)
		if generatedWorldModel then
			return generatedWorldModel, fruit
		end

		return nil, fruitOrReason
	end

	local worldModel = fruitFolder:FindFirstChild(WORLD_MODEL_NAME)
	if not isSupportedWorldModel(worldModel) then
		local generatedWorldModel = getGeneratedWorldModel(fruit)
		if generatedWorldModel then
			return generatedWorldModel, fruit
		end

		return nil, "missing_world_model"
	end

	return worldModel, fruitOrReason
end

function DevilFruitAssets.GetWorldModelByKey(fruitKey)
	return DevilFruitAssets.GetWorldModel(fruitKey)
end

function DevilFruitAssets.ValidateWorldModel(fruitIdentifier)
	local fruit, reason = resolveFruit(fruitIdentifier)
	if not fruit then
		return false, reason
	end

	local worldModel, reason = DevilFruitAssets.GetWorldModel(fruit.FruitKey)
	if not worldModel then
		return false, reason
	end

	local fruitKeyAttribute = worldModel:GetAttribute("FruitKey")
	if fruitKeyAttribute ~= nil and fruitKeyAttribute ~= fruit.FruitKey then
		return false, "fruit_key_mismatch"
	end

	local fruitNameAttribute = worldModel:GetAttribute("FruitName")
	if fruitNameAttribute ~= nil and fruitNameAttribute ~= fruit.DisplayName then
		return false, "fruit_name_mismatch"
	end

	local primaryPart = findPrimaryPartCandidate(worldModel)
	if not primaryPart then
		return false, "missing_primary_part"
	end

	if worldModel.PrimaryPart ~= primaryPart then
		pcall(function()
			worldModel.PrimaryPart = primaryPart
		end)
	end

	return true, worldModel, fruit
end

function DevilFruitAssets.HasWorldModel(fruitIdentifier)
	local isValid = DevilFruitAssets.ValidateWorldModel(fruitIdentifier)
	return isValid
end

function DevilFruitAssets.CloneWorldModel(fruitIdentifier, parent)
	local isValid, worldModelOrReason, fruit = DevilFruitAssets.ValidateWorldModel(fruitIdentifier)
	if not isValid then
		return nil, worldModelOrReason
	end

	local clone = worldModelOrReason:Clone()
	applyFruitAttributes(clone, fruit)

	if parent then
		clone.Parent = parent
	end

	return clone
end

function DevilFruitAssets.ClonePreviewWorldModel(fruitIdentifier, parent)
	local isValid, worldModelOrReason, fruit = DevilFruitAssets.ValidateWorldModel(fruitIdentifier)
	if not isValid then
		return nil, worldModelOrReason
	end

	local previewClone
	if worldModelOrReason:IsA("BasePart") then
		previewClone = worldModelOrReason:Clone()
		applyFruitAttributes(previewClone, fruit)
	else
		previewClone = select(1, buildPreviewCloneFromModel(worldModelOrReason, fruit))
	end

	if not previewClone then
		return DevilFruitAssets.CloneWorldModel(fruitIdentifier, parent)
	end

	if parent then
		previewClone.Parent = parent
	end

	return previewClone
end

function DevilFruitAssets.SpawnWorldModel(fruitIdentifier, spawnTarget, parent)
	local clone, reason = DevilFruitAssets.CloneWorldModel(fruitIdentifier)
	if not clone then
		return nil, reason
	end

	local spawnCFrame = getSpawnCFrame(spawnTarget)
	if spawnTarget ~= nil and not spawnCFrame then
		clone:Destroy()
		return nil, "invalid_spawn_target"
	end

	clone.Parent = parent or Workspace

	if spawnCFrame then
		clone:PivotTo(spawnCFrame)
	end

	return clone
end

return DevilFruitAssets
