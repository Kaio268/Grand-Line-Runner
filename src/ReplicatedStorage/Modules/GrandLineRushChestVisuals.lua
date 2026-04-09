local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))

local ChestVisuals = {}

ChestVisuals.Style = "ProceduralPlaceholder"

local ROOT_SIZE = Vector3.new(1.25, 0.72, 0.9)

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

local function setBasePartDefaults(part)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

function ChestVisuals.GetTierColors(tierName)
	local styleName = ChestUtils.GetVisualStyleName(tierName)

	if styleName == "Mythic Devil Fruit" then
		return Color3.fromRGB(63, 68, 78), Color3.fromRGB(116, 245, 220)
	end

	if styleName == "Legendary Devil Fruit" then
		return Color3.fromRGB(134, 66, 29), Color3.fromRGB(255, 173, 66)
	end

	if styleName == "Rare Devil Fruit" then
		return Color3.fromRGB(82, 74, 45), Color3.fromRGB(96, 176, 255)
	end

	if styleName == "Legendary" then
		return Color3.fromRGB(143, 90, 28), Color3.fromRGB(228, 180, 74)
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
	setBasePartDefaults(part)
	return part
end

local function addDecorations(parent, rootPart, tierName)
	local woodColor, metalColor = ChestVisuals.GetTierColors(tierName)

	for _, def in ipairs(PART_DEFS) do
		local part = Instance.new("Part")
		part.Name = def.Name
		part.Size = def.Size
		part.Material = def.Material
		part.Color = if def.ColorKind == "Metal" then metalColor else woodColor
		part.CFrame = def.LocalCFrame
		setBasePartDefaults(part)
		part.Parent = parent

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = part
		weld.Parent = rootPart
	end
end

function ChestVisuals.CreateWorldModel(tierName, modelName)
	local model = Instance.new("Model")
	model.Name = modelName or "ChestPlaceholder"

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
	local handle = createRootPart("Handle", tierName)
	handle.Parent = tool
	addDecorations(tool, handle, tierName)
	return handle
end

return ChestVisuals
