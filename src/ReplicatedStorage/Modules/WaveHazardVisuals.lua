local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WaveHazardVisuals = {}

local ASSETS_FOLDER_NAME = "Assets"
local HAZARDS_FOLDER_NAME = "Hazards"
local WAVES_FOLDER_NAME = "Waves"
local REGULAR_WAVE_ASSET_NAME = "Regular Wave"
local FROZEN_WAVE_ASSET_NAME = "Frozen Wave"
local HITBOX_NAME = "WaveHitbox"
local VISUAL_NAME = "WaveVisual"
local FROZEN_VISUAL_NAME = "FrozenWaveVisual"
local USES_ASSET_VISUALS_ATTRIBUTE = "UsesWaveAssetVisuals"
local VISUAL_ASSET_NAME_ATTRIBUTE = "WaveVisualAssetName"
local ACTIVE_VISUAL_ASSET_ATTRIBUTE = "ActiveWaveVisualAssetName"
local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "WaveVisualOriginalTransparency"
local ORIGINAL_ENABLED_ATTRIBUTE = "WaveVisualOriginalEnabled"
local MIN_PART_SIZE = 0.001
local ASSET_TEMPLATE_ROTATION = CFrame.Angles(0, math.rad(180), 0)

local function getChild(parent, name)
	if not parent then
		return nil
	end

	return parent:FindFirstChild(name)
end

local function getWaveAssetsFolder()
	local assetsFolder = getChild(ReplicatedStorage, ASSETS_FOLDER_NAME)
	local hazardsFolder = getChild(assetsFolder, HAZARDS_FOLDER_NAME)
	local wavesFolder = getChild(hazardsFolder, WAVES_FOLDER_NAME)
	if wavesFolder and wavesFolder:IsA("Folder") then
		return wavesFolder
	end

	return nil
end

local function getWaveAsset(assetName)
	local wavesFolder = getWaveAssetsFolder()
	local asset = wavesFolder and wavesFolder:FindFirstChild(assetName)
	if asset and (asset:IsA("Model") or asset:IsA("BasePart")) then
		return asset
	end

	return nil
end

local function forEachBasePart(root, callback)
	if not root then
		return
	end

	if root:IsA("BasePart") then
		callback(root)
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

local function forEachSelfAndDescendant(root, callback)
	if not root then
		return
	end

	callback(root)

	for _, descendant in ipairs(root:GetDescendants()) do
		callback(descendant)
	end
end

local function ensureModelPrimaryPart(model)
	if not model:IsA("Model") then
		return nil
	end

	if model.PrimaryPart and model.PrimaryPart.Parent then
		return model.PrimaryPart
	end

	local primaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	if primaryPart then
		pcall(function()
			model.PrimaryPart = primaryPart
		end)
	end

	return primaryPart
end

local function getPivot(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	return instance.CFrame
end

local function findHitboxRoot(root)
	if not root then
		return nil
	end

	if (root:IsA("Model") or root:IsA("BasePart")) and root.Name == HITBOX_NAME then
		return root
	end

	local directHitbox = root:FindFirstChild(HITBOX_NAME)
	if directHitbox and (directHitbox:IsA("Model") or directHitbox:IsA("BasePart")) then
		return directHitbox
	end

	local descendantHitbox = root:FindFirstChild(HITBOX_NAME, true)
	if descendantHitbox and (descendantHitbox:IsA("Model") or descendantHitbox:IsA("BasePart")) then
		return descendantHitbox
	end

	return nil
end

local function configureHitboxPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = true
	part.CanQuery = true
	part.Transparency = 1
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)

	if part:IsA("MeshPart") then
		pcall(function()
			part.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
		end)
	end
end

local function configureFrozenHitboxPart(part)
	part.Anchored = true
	part.CanCollide = true
	part.CanTouch = false
	part.CanQuery = true
	part.Transparency = 1
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)

	if part:IsA("MeshPart") then
		pcall(function()
			part.CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition
		end)
	end
end

local function configureVisualPart(part)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
	pcall(function()
		part.Massless = true
	end)

	if part:IsA("MeshPart") then
		pcall(function()
			part.DoubleSided = true
		end)
		pcall(function()
			part.RenderFidelity = Enum.RenderFidelity.Precise
		end)
	end
end

local function clampSize(value)
	return math.max(MIN_PART_SIZE, value)
end

local function getBoundsSizeInFrame(root, boundsFrame)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local hasBounds = false

	forEachBasePart(root, function(part)
		local halfSize = part.Size * 0.5

		for _, xSign in ipairs({ -1, 1 }) do
			for _, ySign in ipairs({ -1, 1 }) do
				for _, zSign in ipairs({ -1, 1 }) do
					local worldCorner = part.CFrame:PointToWorldSpace(Vector3.new(
						halfSize.X * xSign,
						halfSize.Y * ySign,
						halfSize.Z * zSign
					))
					local localCorner = boundsFrame:PointToObjectSpace(worldCorner)

					minX = math.min(minX, localCorner.X)
					minY = math.min(minY, localCorner.Y)
					minZ = math.min(minZ, localCorner.Z)
					maxX = math.max(maxX, localCorner.X)
					maxY = math.max(maxY, localCorner.Y)
					maxZ = math.max(maxZ, localCorner.Z)
					hasBounds = true
				end
			end
		end
	end)

	if not hasBounds then
		return nil
	end

	return Vector3.new(
		clampSize(maxX - minX),
		clampSize(maxY - minY),
		clampSize(maxZ - minZ)
	)
end

local function getWaveShapeScale(sourceSize, targetSize)
	-- Match the old hazard's height and long span while letting the wave curl keep its natural depth.
	local scaleY = if sourceSize.Y > MIN_PART_SIZE then targetSize.Y / sourceSize.Y else nil
	local scaleZ = if sourceSize.Z > MIN_PART_SIZE then targetSize.Z / sourceSize.Z else nil

	if scaleY and scaleZ then
		return math.min(scaleY, scaleZ)
	end

	if scaleY then
		return scaleY
	end

	if scaleZ then
		return scaleZ
	end

	if sourceSize.X > MIN_PART_SIZE then
		return targetSize.X / sourceSize.X
	end

	return 1
end

local function scaleBasePartToBox(part, targetCFrame, targetSize, configurePart)
	configurePart(part)
	part.Size = Vector3.new(
		clampSize(targetSize.X),
		clampSize(targetSize.Y),
		clampSize(targetSize.Z)
	)
	part.CFrame = targetCFrame
end

local function scaleModelToBox(model, targetCFrame, targetSize, configurePart)
	local sourceCFrame, sourceSize = model:GetBoundingBox()
	local scaleX = if sourceSize.X > MIN_PART_SIZE then targetSize.X / sourceSize.X else 1
	local scaleY = if sourceSize.Y > MIN_PART_SIZE then targetSize.Y / sourceSize.Y else 1
	local scaleZ = if sourceSize.Z > MIN_PART_SIZE then targetSize.Z / sourceSize.Z else 1

	forEachBasePart(model, function(part)
		local relative = sourceCFrame:ToObjectSpace(part.CFrame)
		local relativePosition = relative.Position
		local relativeRotation = relative - relativePosition

		configurePart(part)
		part.Size = Vector3.new(
			clampSize(part.Size.X * scaleX),
			clampSize(part.Size.Y * scaleY),
			clampSize(part.Size.Z * scaleZ)
		)
		part.CFrame = targetCFrame
			* CFrame.new(
				relativePosition.X * scaleX,
				relativePosition.Y * scaleY,
				relativePosition.Z * scaleZ
			)
			* relativeRotation
	end)

	ensureModelPrimaryPart(model)
end

local function scaleBasePartToWaveShape(part, targetCFrame, targetSize, configurePart)
	local scale = getWaveShapeScale(part.Size, targetSize)

	configurePart(part)
	part.Size = Vector3.new(
		clampSize(part.Size.X * scale),
		clampSize(part.Size.Y * scale),
		clampSize(part.Size.Z * scale)
	)
	part.CFrame = targetCFrame
end

local function scaleModelToWaveShape(model, targetCFrame, targetSize, configurePart)
	local sourceCFrame, sourceSize = model:GetBoundingBox()
	local scale = getWaveShapeScale(sourceSize, targetSize)

	forEachBasePart(model, function(part)
		local relative = sourceCFrame:ToObjectSpace(part.CFrame)
		local relativePosition = relative.Position
		local relativeRotation = relative - relativePosition

		configurePart(part)
		part.Size = Vector3.new(
			clampSize(part.Size.X * scale),
			clampSize(part.Size.Y * scale),
			clampSize(part.Size.Z * scale)
		)
		part.CFrame = targetCFrame
			* CFrame.new(
				relativePosition.X * scale,
				relativePosition.Y * scale,
				relativePosition.Z * scale
			)
			* relativeRotation
	end)

	ensureModelPrimaryPart(model)
end

local function getTargetBox(root)
	local hitbox = findHitboxRoot(root)
	if hitbox then
		if hitbox:IsA("BasePart") then
			return hitbox.CFrame, hitbox.Size, hitbox
		end

		local boxCFrame, boxSize = hitbox:GetBoundingBox()
		return boxCFrame, boxSize, hitbox
	end

	if root:IsA("BasePart") then
		return root.CFrame, root.Size, root
	end

	if root:IsA("Model") then
		local boxCFrame, boxSize = root:GetBoundingBox()
		return boxCFrame, boxSize, nil
	end

	return nil, nil, nil
end

local function getVisualTargetBox(root)
	if root:IsA("Model") and root:GetAttribute(USES_ASSET_VISUALS_ATTRIBUTE) == true then
		local hitbox = findHitboxRoot(root)
		local targetCFrame = root:GetPivot() * ASSET_TEMPLATE_ROTATION
		if hitbox then
			local targetSize = getBoundsSizeInFrame(hitbox, targetCFrame)
			if targetSize then
				return targetCFrame, targetSize
			end
		end

		local targetSize = getBoundsSizeInFrame(root, targetCFrame)
		if targetSize then
			return targetCFrame, targetSize
		end
	end

	return getTargetBox(root)
end

local function getVisualNameForAsset(assetName)
	if assetName == FROZEN_WAVE_ASSET_NAME then
		return FROZEN_VISUAL_NAME
	end

	return VISUAL_NAME
end

local function rememberVisualState(visual)
	forEachSelfAndDescendant(visual, function(item)
		if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
			if item:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE) == nil then
				item:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, item.Transparency)
			end
		elseif item:IsA("ParticleEmitter")
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles") then
			if item:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) == nil then
				item:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, item.Enabled)
			end
		end
	end)
end

local function setVisualVisible(visual, isVisible)
	if not visual then
		return
	end

	rememberVisualState(visual)

	forEachSelfAndDescendant(visual, function(item)
		if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
			if isVisible then
				local originalTransparency = item:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE)
				item.Transparency = if typeof(originalTransparency) == "number" then originalTransparency else 0
			else
				item.Transparency = 1
			end
		elseif item:IsA("ParticleEmitter")
			or item:IsA("Trail")
			or item:IsA("Beam")
			or item:IsA("Smoke")
			or item:IsA("Fire")
			or item:IsA("Sparkles") then
			if isVisible then
				local originalEnabled = item:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE)
				item.Enabled = if typeof(originalEnabled) == "boolean" then originalEnabled else true
			else
				item.Enabled = false
			end
		end
	end)
end

local function createVisual(root, assetName)
	local asset = getWaveAsset(assetName)
	if not asset then
		return nil
	end

	local targetCFrame, targetSize = getVisualTargetBox(root)
	if not targetCFrame or not targetSize then
		return nil
	end

	local visual = asset:Clone()
	visual.Name = getVisualNameForAsset(assetName)
	visual:SetAttribute(VISUAL_ASSET_NAME_ATTRIBUTE, assetName)

	if visual:IsA("BasePart") then
		scaleBasePartToBox(visual, targetCFrame, targetSize, configureVisualPart)
	else
		scaleModelToBox(visual, targetCFrame, targetSize, configureVisualPart)
	end

	visual.Parent = root
	WaveHazardVisuals.ConfigureVisualRoot(visual)
	rememberVisualState(visual)
	return visual
end

local function ensureVisual(root, assetName)
	if not root then
		return nil
	end

	local visualName = getVisualNameForAsset(assetName)
	local visual = root:FindFirstChild(visualName)
	if visual then
		visual:SetAttribute(VISUAL_ASSET_NAME_ATTRIBUTE, assetName)
		WaveHazardVisuals.ConfigureVisualRoot(visual)
		rememberVisualState(visual)
		return visual
	end

	return createVisual(root, assetName)
end

local function findVisual(root, assetName)
	if not root then
		return nil
	end

	return root:FindFirstChild(getVisualNameForAsset(assetName))
end

local function createHitboxFromAsset(asset, targetCFrame, targetSize)
	local hitbox = asset:Clone()
	hitbox.Name = HITBOX_NAME

	if hitbox:IsA("BasePart") then
		scaleBasePartToWaveShape(hitbox, targetCFrame, targetSize, configureHitboxPart)
	else
		scaleModelToWaveShape(hitbox, targetCFrame, targetSize, configureHitboxPart)
	end

	return hitbox
end

function WaveHazardVisuals.GetRegularWaveAsset()
	return getWaveAsset(REGULAR_WAVE_ASSET_NAME)
end

function WaveHazardVisuals.GetFrozenWaveAsset()
	return getWaveAsset(FROZEN_WAVE_ASSET_NAME)
end

function WaveHazardVisuals.GetHitboxParts(root)
	local hitbox = findHitboxRoot(root)
	local parts = {}

	if hitbox then
		forEachBasePart(hitbox, function(part)
			parts[#parts + 1] = part
		end)
		return parts
	end

	if root and root:IsA("BasePart") then
		return { root }
	end

	return parts
end

function WaveHazardVisuals.ConfigureVisualRoot(root)
	local configuredCount = 0

	forEachBasePart(root, function(part)
		configureVisualPart(part)
		configuredCount += 1
	end)

	return configuredCount
end

function WaveHazardVisuals.SetHitboxFrozen(root, isFrozen)
	local configuredCount = 0
	local configurePart = if isFrozen == true then configureFrozenHitboxPart else configureHitboxPart

	for _, part in ipairs(WaveHazardVisuals.GetHitboxParts(root)) do
		configurePart(part)
		configuredCount += 1
	end

	return configuredCount
end

function WaveHazardVisuals.ApplyVisual(root, assetName)
	if not root then
		return false
	end

	local activeVisual = ensureVisual(root, assetName)
	if not activeVisual then
		return false
	end

	local inactiveAssetName = if assetName == FROZEN_WAVE_ASSET_NAME then REGULAR_WAVE_ASSET_NAME else FROZEN_WAVE_ASSET_NAME
	local inactiveVisual = findVisual(root, inactiveAssetName)

	setVisualVisible(activeVisual, true)
	if inactiveVisual and inactiveVisual ~= activeVisual then
		setVisualVisible(inactiveVisual, false)
	end

	root:SetAttribute(ACTIVE_VISUAL_ASSET_ATTRIBUTE, assetName)
	return true
end

function WaveHazardVisuals.CreateHazardFromTemplate(template)
	local regularAsset = getWaveAsset(REGULAR_WAVE_ASSET_NAME)
	if not regularAsset then
		return template:Clone(), false
	end

	local model = Instance.new("Model")
	model.Name = template.Name
	model:SetAttribute(USES_ASSET_VISUALS_ATTRIBUTE, true)

	local targetCFrame, targetSize = getTargetBox(template)
	if not targetCFrame or not targetSize then
		return template:Clone(), false
	end

	local hitbox = createHitboxFromAsset(regularAsset, targetCFrame * ASSET_TEMPLATE_ROTATION, targetSize)
	hitbox.Parent = model
	model.WorldPivot = getPivot(template)

	WaveHazardVisuals.ApplyVisual(model, REGULAR_WAVE_ASSET_NAME)
	return model, true
end

function WaveHazardVisuals.SetFrozen(root, isFrozen)
	if not root then
		return false
	end

	root:SetAttribute("Frozen", isFrozen == true)
	WaveHazardVisuals.SetHitboxFrozen(root, isFrozen == true)
	local assetName = if isFrozen then FROZEN_WAVE_ASSET_NAME else REGULAR_WAVE_ASSET_NAME
	return WaveHazardVisuals.ApplyVisual(root, assetName)
end

return WaveHazardVisuals
