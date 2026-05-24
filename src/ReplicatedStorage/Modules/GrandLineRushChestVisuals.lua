local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))

local ChestVisuals = {}

ChestVisuals.Style = "AssetBackedWithProceduralFallback"

local ROOT_SIZE = Vector3.new(1.25, 0.72, 0.9)
local MIN_HITBOX_SIZE = Vector3.new(0.5, 0.5, 0.5)
local CARRY_ROTATION = CFrame.Angles(0, math.rad(180), 0)
local PREVIEW_ROTATION = CFrame.Angles(math.rad(-10), math.rad(28), 0)

local ASSET_ALIAS_BY_KEY = {
	wood = "WoodenChest",
	wooden = "WoodenChest",
	woodenchest = "WoodenChest",
	iron = "IronChest",
	ironchest = "IronChest",
	gold = "GoldenChest",
	golden = "GoldenChest",
	goldchest = "GoldenChest",
	goldenchest = "GoldenChest",
	devilfruit = "GoldenChest",
	commondevilfruit = "GoldenChest",
	raredevilfruit = "GoldenChest",
	legendarydevilfruit = "GoldenChest",
	mythicdevilfruit = "GoldenChest",
}

local PART_DEFS = {
	{
		Name = "ChestLid",
		Size = Vector3.new(1.25, 0.44, 0.92),
		LocalCFrame = CFrame.new(0, 0.58, -0.02),
		Material = Enum.Material.WoodPlanks,
		ColorKind = "Wood",
	},
	{
		Name = "ChestBand",
		Size = Vector3.new(0.12, 1.05, 0.96),
		LocalCFrame = CFrame.new(0, 0.14, 0),
		Material = Enum.Material.Metal,
		ColorKind = "Metal",
	},
	{
		Name = "ChestTrimLeft",
		Size = Vector3.new(0.1, 0.78, 0.96),
		LocalCFrame = CFrame.new(-0.58, 0.02, 0),
		Material = Enum.Material.Metal,
		ColorKind = "Metal",
	},
	{
		Name = "ChestTrimRight",
		Size = Vector3.new(0.1, 0.78, 0.96),
		LocalCFrame = CFrame.new(0.58, 0.02, 0),
		Material = Enum.Material.Metal,
		ColorKind = "Metal",
	},
	{
		Name = "ChestLatch",
		Size = Vector3.new(0.16, 0.2, 0.16),
		LocalCFrame = CFrame.new(0.62, 0.1, 0),
		Material = Enum.Material.Metal,
		ColorKind = "Metal",
	},
}

local function normalizeAssetKey(value)
	local key = tostring(value or "")
	key = key:gsub("%s+", "")
	key = key:gsub("[_%-]", "")
	return string.lower(key)
end

local function setSmoothSurfaces(part)
	if part:IsA("Part") then
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
	end
end

local function setDecorativePartDefaults(part)
	setSmoothSurfaces(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
end

local function setHitboxDefaults(part, tierName, canQuery)
	local _, metalColor = ChestVisuals.GetTierColors(tierName)
	setSmoothSurfaces(part)
	part.Transparency = 1
	part.Color = metalColor
	part.Material = Enum.Material.SmoothPlastic
	part.CastShadow = false
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = canQuery == true
	part.Massless = true
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero
end

local function getExtractionChestFolder()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local chests = assets and assets:FindFirstChild("Chests")
	return chests and chests:FindFirstChild("ExtractionChests") or nil
end

function ChestVisuals.GetAssetModelName(chestDataOrName)
	if typeof(chestDataOrName) == "string" then
		local direct = ASSET_ALIAS_BY_KEY[normalizeAssetKey(chestDataOrName)]
		if direct then
			return direct
		end
	end

	local styleName = ChestUtils.GetVisualStyleName(chestDataOrName)
	return ASSET_ALIAS_BY_KEY[normalizeAssetKey(styleName)] or "WoodenChest"
end

function ChestVisuals.GetAssetTemplate(chestDataOrName)
	local folder = getExtractionChestFolder()
	if not folder then
		return nil
	end

	local assetName = ChestVisuals.GetAssetModelName(chestDataOrName)
	local template = folder:FindFirstChild(assetName)
	if template and (template:IsA("Model") or template:IsA("BasePart")) then
		return template, assetName
	end

	return nil, assetName
end

function ChestVisuals.GetCarryRotation(_chestDataOrName)
	return CARRY_ROTATION
end

function ChestVisuals.GetPreviewRotation(_chestDataOrName)
	return PREVIEW_ROTATION
end

local function formatPreviewCacheCFrame(cframe)
	local components = { cframe:GetComponents() }
	for index, component in ipairs(components) do
		components[index] = string.format("%.6f", component)
	end
	return table.concat(components, ",")
end

function ChestVisuals.GetPreviewCacheKey(chestDataOrName)
	return table.concat({
		ChestVisuals.GetAssetModelName(chestDataOrName),
		formatPreviewCacheCFrame(ChestVisuals.GetPreviewRotation(chestDataOrName)),
	}, "|")
end

function ChestVisuals.GetTierLabel(chestDataOrName)
	local assetKey = normalizeAssetKey(chestDataOrName)
	if assetKey == "gold"
		or assetKey == "golden"
		or assetKey == "goldchest"
		or assetKey == "goldchests"
		or assetKey == "goldenchest"
		or assetKey == "goldenchests"
	then
		return "Gold"
	elseif assetKey == "iron" or assetKey == "ironchest" or assetKey == "ironchests" then
		return "Iron"
	elseif assetKey == "wood" or assetKey == "wooden" or assetKey == "woodenchest" or assetKey == "woodenchests" then
		return "Wooden"
	end

	local styleName = ChestUtils.GetVisualStyleName(chestDataOrName)
	local styleKey = normalizeAssetKey(styleName)
	if styleKey == "gold" or styleKey == "golden" or styleKey == "goldchest" or styleKey == "goldenchest" or styleKey == "goldenchests" then
		return "Gold"
	elseif styleKey == "iron" or styleKey == "ironchest" or styleKey == "ironchests" then
		return "Iron"
	elseif styleKey == "wood" or styleKey == "wooden" or styleKey == "woodenchest" or styleKey == "woodenchests" then
		return "Wooden"
	end

	return tostring(styleName or chestDataOrName or "Wooden")
end

local function forEachBasePart(root, callback)
	if root:IsA("BasePart") then
		callback(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			callback(descendant)
		end
	end
end

local function collectBaseParts(root)
	local parts = {}
	forEachBasePart(root, function(part)
		parts[#parts + 1] = part
	end)
	return parts
end

local function disableScripts(root)
	if root:IsA("BaseScript") then
		root.Enabled = false
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BaseScript") then
			descendant.Enabled = false
		end
	end
end

local function getBoundingInfo(instance)
	if instance:IsA("Model") then
		return instance:GetBoundingBox()
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return CFrame.new(), ROOT_SIZE
end

local function getSafeHitboxSize(size)
	return Vector3.new(
		math.max(MIN_HITBOX_SIZE.X, math.abs(size.X)),
		math.max(MIN_HITBOX_SIZE.Y, math.abs(size.Y)),
		math.max(MIN_HITBOX_SIZE.Z, math.abs(size.Z))
	)
end

local function createHitboxPart(partName, tierName, size, canQuery)
	local part = Instance.new("Part")
	part.Name = partName
	part.Size = getSafeHitboxSize(size or ROOT_SIZE)
	setHitboxDefaults(part, tierName, canQuery)
	return part
end

local function weldToRoot(rootPart, part)
	if part == rootPart then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = part
	weld.Parent = rootPart
end

local function cloneAssetTemplate(chestDataOrName)
	local template, assetName = ChestVisuals.GetAssetTemplate(chestDataOrName)
	if not template then
		return nil, assetName
	end

	local ok, clone = pcall(function()
		return template:Clone()
	end)
	if not ok or typeof(clone) ~= "Instance" then
		return nil, assetName
	end

	return clone, assetName
end

local function buildAssetModel(tierName, modelName)
	local clone, assetName = cloneAssetTemplate(tierName)
	if not clone then
		return nil, assetName
	end

	disableScripts(clone)
	forEachBasePart(clone, setDecorativePartDefaults)

	local boxCF, boxSize = getBoundingInfo(clone)
	local parts = collectBaseParts(clone)
	if #parts <= 0 then
		clone:Destroy()
		return nil, assetName
	end

	local model = Instance.new("Model")
	model.Name = modelName or assetName or "ExtractionChest"
	model:SetAttribute("ChestVisualAssetName", assetName)
	model:SetAttribute("ChestVisualStyle", ChestUtils.GetVisualStyleName(tierName))

	local rootPart = createHitboxPart("ChestHitbox", tierName, boxSize, true)
	rootPart.CFrame = CFrame.new()
	rootPart.Parent = model

	for _, part in ipairs(parts) do
		local relativeCFrame = boxCF:ToObjectSpace(part.CFrame)
		part.CFrame = rootPart.CFrame * relativeCFrame
		part.Parent = model
		weldToRoot(rootPart, part)
	end

	if not clone:IsA("BasePart") then
		clone:Destroy()
	end

	model.PrimaryPart = rootPart
	return model, assetName
end

local function populateToolWithAsset(tool, tierName)
	local clone = cloneAssetTemplate(tierName)
	if not clone then
		return nil
	end

	disableScripts(clone)
	forEachBasePart(clone, setDecorativePartDefaults)

	local boxCF, boxSize = getBoundingInfo(clone)
	local parts = collectBaseParts(clone)
	if #parts <= 0 then
		clone:Destroy()
		return nil
	end

	local handle = createHitboxPart("Handle", tierName, boxSize, false)
	handle.CFrame = CFrame.new()
	handle.Parent = tool
	local carryRotation = ChestVisuals.GetCarryRotation(tierName)

	for _, part in ipairs(parts) do
		local relativeCFrame = boxCF:ToObjectSpace(part.CFrame)
		part.CFrame = handle.CFrame * carryRotation * relativeCFrame
		part.Parent = tool
		weldToRoot(handle, part)
	end

	if not clone:IsA("BasePart") then
		clone:Destroy()
	end

	return handle
end

function ChestVisuals.GetTierColors(tierName)
	local assetKey = normalizeAssetKey(tierName)
	local styleName = ChestUtils.GetVisualStyleName(tierName)
	if assetKey == "gold"
		or assetKey == "golden"
		or assetKey == "goldchest"
		or assetKey == "goldenchest"
		or assetKey == "devilfruit"
	then
		styleName = "Gold"
	elseif assetKey == "iron" or assetKey == "ironchest" then
		styleName = "Iron"
	elseif assetKey == "wood" or assetKey == "wooden" or assetKey == "woodenchest" then
		styleName = "Wooden"
	end

	if styleName == "Mythic Devil Fruit" then
		return Color3.fromRGB(63, 68, 78), Color3.fromRGB(116, 245, 220)
	end

	if styleName == "Legendary Devil Fruit" then
		return Color3.fromRGB(134, 66, 29), Color3.fromRGB(255, 173, 66)
	end

	if styleName == "Rare Devil Fruit" then
		return Color3.fromRGB(82, 74, 45), Color3.fromRGB(96, 176, 255)
	end

	if styleName == "Gold" then
		return Color3.fromRGB(132, 84, 30), Color3.fromRGB(215, 172, 71)
	end

	if styleName == "Iron" then
		return Color3.fromRGB(101, 78, 57), Color3.fromRGB(161, 170, 180)
	end

	return Color3.fromRGB(116, 73, 41), Color3.fromRGB(196, 157, 88)
end

local function createRootPart(rootName, tierName)
	local woodColor = select(1, ChestVisuals.GetTierColors(tierName))
	local part = Instance.new("Part")
	part.Name = rootName
	part.Size = ROOT_SIZE
	part.Material = Enum.Material.WoodPlanks
	part.Color = woodColor
	setDecorativePartDefaults(part)
	part.CanQuery = rootName == "ChestBase"
	return part
end

local function addDecorations(parent, rootPart, tierName, localRotation)
	local woodColor, metalColor = ChestVisuals.GetTierColors(tierName)
	local rotation = localRotation or CFrame.new()

	for _, def in ipairs(PART_DEFS) do
		local part = Instance.new("Part")
		part.Name = def.Name
		part.Size = def.Size
		part.Material = def.Material
		part.Color = if def.ColorKind == "Metal" then metalColor else woodColor
		part.CFrame = rotation * def.LocalCFrame
		setDecorativePartDefaults(part)
		part.Parent = parent

		weldToRoot(rootPart, part)
	end
end

function ChestVisuals.CreateWorldModel(tierName, modelName)
	local assetModel = buildAssetModel(tierName, modelName)
	if assetModel then
		return assetModel
	end

	local model = Instance.new("Model")
	model.Name = modelName or "ExtractionChestFallback"

	local rootPart = createRootPart("ChestBase", tierName)
	rootPart.Parent = model
	addDecorations(model, rootPart, tierName)

	model.PrimaryPart = rootPart
	return model
end

function ChestVisuals.CreatePreviewModel(tierName)
	return ChestVisuals.CreateWorldModel(tierName, "ChestPreview")
end

function ChestVisuals.PopulateTool(tool, tierName)
	local assetHandle = populateToolWithAsset(tool, tierName)
	if assetHandle then
		return assetHandle
	end

	local handle = createRootPart("Handle", tierName)
	handle.CanQuery = false
	handle.Parent = tool
	addDecorations(tool, handle, tierName, ChestVisuals.GetCarryRotation(tierName))
	return handle
end

return ChestVisuals
