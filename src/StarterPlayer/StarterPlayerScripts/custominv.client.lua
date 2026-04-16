local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local updateRemote = ReplicatedStorage:WaitForChild("InventoryGearRemote")
local equipRemote = ReplicatedStorage:WaitForChild("EquipToggleRemote")

local Brainrots = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local Gears = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local ChestVisuals = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestVisuals"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local MetaClient = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushMetaClient"))
local DevilFruitAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Assets"))

local RESOURCE_ORDER = {
	Apple = 1,
	Rice = 2,
	Meat = 3,
	SeaBeastMeat = 4,
	CommonShipMaterial = 5,
	RareShipMaterial = 6,
}

local RESOURCE_MATERIAL_DISPLAY = {
	CommonShipMaterial = "Common Ship Material",
	RareShipMaterial = "Rare Ship Material",
}

local CATEGORY_ORDER = {
	Brainrots = 1,
	DevilFruits = 2,
	Resources = 3,
}

local CATEGORY_LABELS = {
	Brainrots = "Treasure",
	DevilFruits = "Devil Fruits",
	Resources = "Resources",
}

local CATEGORY_BUTTON_LABELS = {
	Brainrots = "Treasure",
	DevilFruits = "DevFruits",
	Resources = "Resources",
}

local CATEGORY_ALIASES = {
	Brainrots = { "brainrot", "brainrots", "treasure" },
	Resources = { "resources", "resource", "soon" },
}

local hudInv = player:WaitForChild("PlayerGui"):WaitForChild("HUD"):WaitForChild("Inventory")
local hotbarTemplate = hudInv:WaitForChild("toolButton")
local hotbarContainer = hotbarTemplate.Parent
local inventoryBtn = hudInv:WaitForChild("InventoryBtn")
inventoryBtn.Image = "rbxassetid://129583821766521"
inventoryBtn.ImageTransparency = 0
inventoryBtn.ScaleType = Enum.ScaleType.Fit

local inb = hudInv:WaitForChild("Inv")
local inventoryFrame = inb:WaitForChild("InventoryFrame")
local scrollingFrame = inventoryFrame:WaitForChild("ScrollingFrame")
local invTemplate = scrollingFrame:WaitForChild("toolButton")
local invContainer = invTemplate.Parent

local NORMAL = Color3.fromRGB(0, 0, 0)
local SELECT = Color3.fromRGB(255, 255, 255)
local TOOLTIP_BACKGROUND = Color3.fromRGB(20, 24, 32)
local TOOLTIP_TEXT = Color3.fromRGB(245, 247, 250)
local TOOLTIP_SUBTEXT = Color3.fromRGB(180, 188, 200)

local equippedName = nil
local equippedKind = nil
local activeInventoryCategory = "Brainrots"

local hotbarButtons = {}
local invButtons = {}
local categoryButtons = {}
local categoryRow = nil
local createdCategoryRow = false
local rebuildUI

local itemState = {}
local acquisition = {}
local acquisitionCounter = 0
local chestInventoryFolderConnections = {}
local chestInventoryQuantityConnections = {}
local boundChestInventoryFolder = nil
local hoverTooltip = {
	Gui = nil,
	Title = nil,
	Rarity = nil,
	Visible = false,
}
local CHEST_DEBUG = true

local function chestDebug(message, ...)
	if CHEST_DEBUG ~= true then
		return
	end

	warn(string.format("[GLR ChestDebug][HotbarClient] " .. tostring(message), ...))
end

local RARITY_ORDER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Godly = 7,
	Secret = 8,
	Omega = 9,
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(189, 196, 209),
	Uncommon = Color3.fromRGB(112, 220, 140),
	Rare = Color3.fromRGB(91, 170, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 187, 74),
	Mythic = Color3.fromRGB(255, 101, 134),
	Godly = Color3.fromRGB(255, 84, 84),
	Secret = Color3.fromRGB(255, 240, 110),
	Omega = Color3.fromRGB(132, 255, 247),
}

local function setupLayout(parent)
	local listLayout = parent:FindFirstChildOfClass("UIListLayout")
	local gridLayout = parent:FindFirstChildOfClass("UIGridLayout")
	if listLayout then
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	end
	if gridLayout then
		gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	end
end

local searchBox = inventoryFrame:FindFirstChild("Search")  
local currentQuery = ""

local function trim(s)
	return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function startsWithIgnoreCase(text, prefix)
	text = string.lower(text or "")
	prefix = string.lower(prefix or "")
	if prefix == "" then return true end
	return text:sub(1, #prefix) == prefix
end

local function applySearchFilter()
	if not searchBox then return end

	currentQuery = trim(searchBox.Text)

	for _, b in pairs(invButtons) do
		if b and b.Parent then
			local itemName = b:GetAttribute("ItemName") or ""
			b.Visible = startsWithIgnoreCase(itemName, currentQuery)
		end
	end
end

if searchBox then
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		applySearchFilter()
	end)
end

setupLayout(hotbarContainer)
setupLayout(invContainer)

hotbarTemplate.Visible = false
invTemplate.Visible = false
inventoryFrame.Visible = false

local function applySelectedVisual(b, selected)
	b.BackgroundColor3 = selected and SELECT or NORMAL
	local stroke = b:FindFirstChild("UIStroke") or b:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = selected and SELECT or NORMAL
	end
end

local function updateSelection()
	for _, b in pairs(hotbarButtons) do
		if b and b.Parent then
			applySelectedVisual(
				b,
				equippedName ~= nil
					and b:GetAttribute("ItemName") == equippedName
					and (equippedKind == nil or b:GetAttribute("ItemKind") == equippedKind)
			)
		end
	end
	for _, b in pairs(invButtons) do
		if b and b.Parent then
			applySelectedVisual(
				b,
				equippedName ~= nil
					and b:GetAttribute("ItemName") == equippedName
					and (equippedKind == nil or b:GetAttribute("ItemKind") == equippedKind)
			)
		end
	end
end

local function ensureNamedGuiObject(parent, name, className)
	local child = parent:FindFirstChild(name)
	if child and child:IsA(className) then
		return child
	end

	if child then
		child:Destroy()
	end

	child = Instance.new(className)
	child.Name = name
	child.Parent = parent
	return child
end

local function ensureButtonStructure(button)
	local isLargeButton = (button.Size.Y.Offset >= 70) or (button.AbsoluteSize.Y >= 70)

	local toolIcon = ensureNamedGuiObject(button, "ToolIcon", "ImageLabel")
	toolIcon.BackgroundTransparency = 1
	toolIcon.BorderSizePixel = 0
	toolIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	toolIcon.Position = isLargeButton and UDim2.new(0.5, 0, 0.36, 0) or UDim2.new(0.5, 0, 0.5, 0)
	toolIcon.Size = isLargeButton and UDim2.new(0.6, 0, 0.5, 0) or UDim2.new(0.68, 0, 0.68, 0)
	toolIcon.ScaleType = Enum.ScaleType.Fit
	toolIcon.ZIndex = math.max(button.ZIndex + 1, 2)

	local toolName = ensureNamedGuiObject(button, "toolName", "TextLabel")
	toolName.BackgroundTransparency = 1
	toolName.BorderSizePixel = 0
	toolName.AnchorPoint = Vector2.new(0.5, 1)
	toolName.Position = UDim2.new(0.5, 0, 1, -3)
	toolName.Size = UDim2.new(1, -8, 0, 14)
	toolName.Font = Enum.Font.GothamBold
	toolName.TextColor3 = Color3.new(1, 1, 1)
	toolName.TextSize = isLargeButton and 10 or 9
	toolName.TextScaled = false
	toolName.TextTruncate = Enum.TextTruncate.AtEnd
	toolName.TextWrapped = false
	toolName.TextXAlignment = Enum.TextXAlignment.Center
	toolName.TextYAlignment = Enum.TextYAlignment.Center
	toolName.Visible = isLargeButton
	toolName.ZIndex = math.max(button.ZIndex + 2, 3)

	local toolAmount = ensureNamedGuiObject(button, "toolAmount", "TextLabel")
	toolAmount.BackgroundTransparency = 1
	toolAmount.BorderSizePixel = 0
	toolAmount.AnchorPoint = Vector2.new(1, 1)
	toolAmount.Position = UDim2.new(1, -4, 1, -4)
	toolAmount.Size = UDim2.fromOffset(42, 12)
	toolAmount.Font = Enum.Font.GothamBold
	toolAmount.TextColor3 = Color3.new(1, 1, 1)
	toolAmount.TextSize = 10
	toolAmount.TextXAlignment = Enum.TextXAlignment.Right
	toolAmount.TextYAlignment = Enum.TextYAlignment.Center
	toolAmount.Visible = false
	toolAmount.ZIndex = math.max(button.ZIndex + 3, 4)

	local toolNumber = ensureNamedGuiObject(button, "toolNumber", "TextLabel")
	toolNumber.BackgroundTransparency = 1
	toolNumber.BorderSizePixel = 0
	toolNumber.Position = UDim2.fromOffset(4, 3)
	toolNumber.Size = UDim2.fromOffset(18, 12)
	toolNumber.Font = Enum.Font.GothamBold
	toolNumber.TextColor3 = Color3.new(1, 1, 1)
	toolNumber.TextSize = 10
	toolNumber.TextXAlignment = Enum.TextXAlignment.Left
	toolNumber.TextYAlignment = Enum.TextYAlignment.Top
	toolNumber.Visible = false
	toolNumber.ZIndex = math.max(button.ZIndex + 3, 4)

	return {
		ToolIcon = toolIcon,
		ToolName = toolName,
		ToolAmount = toolAmount,
		ToolNumber = toolNumber,
	}
end

local function setCommon(b, icon, displayName)
	local components = ensureButtonStructure(b)
	local toolIcon = components.ToolIcon
	local toolName = components.ToolName
	toolIcon.Image = icon or ""
	toolIcon.ImageTransparency = (icon and icon ~= "") and 0 or 1
	toolName.Text = displayName or ""
end

ensureButtonStructure(hotbarTemplate)
ensureButtonStructure(invTemplate)

local function getResourceInfo(resourceKey)
	local foodConfig = Economy.Food[resourceKey]
	if foodConfig then
		return {
			DisplayName = tostring(foodConfig.DisplayName or resourceKey),
			ResourceType = "Food",
		}
	end

	return {
		DisplayName = RESOURCE_MATERIAL_DISPLAY[resourceKey] or tostring(resourceKey),
		ResourceType = "Material",
	}
end

local function clearDevilFruitPreview(button)
	local viewport = button:FindFirstChild("FruitViewport")
	if viewport then
		viewport:Destroy()
	end
end

local function clearChestPreview(button)
	local viewport = button:FindFirstChild("ChestViewport")
	if viewport then
		viewport:Destroy()
	end

	local icon = button:FindFirstChild("ChestIcon")
	if icon then
		icon:Destroy()
	end
end

local function clearResourcePreview(button)
	local viewport = button:FindFirstChild("ResourceViewport")
	if viewport then
		viewport:Destroy()
	end
end

local function createResourcePreviewPart(parent, size, color, cf, shape, material)
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.CFrame = cf
	part.Shape = shape or Enum.PartType.Block
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function buildResourcePreviewModel(resourceKey)
	local model = Instance.new("Model")
	model.Name = "ResourcePreview"

	if resourceKey == "Apple" then
		createResourcePreviewPart(model, Vector3.new(0.9, 0.9, 0.9), Color3.fromRGB(214, 67, 52), CFrame.new(0, 0, 0), Enum.PartType.Ball, Enum.Material.SmoothPlastic)
		createResourcePreviewPart(model, Vector3.new(0.12, 0.35, 0.12), Color3.fromRGB(86, 53, 31), CFrame.new(0, 0.5, 0), Enum.PartType.Cylinder, Enum.Material.Wood)
		createResourcePreviewPart(model, Vector3.new(0.35, 0.12, 0.2), Color3.fromRGB(80, 170, 72), CFrame.new(0.18, 0.42, 0), Enum.PartType.Block, Enum.Material.Grass)
	elseif resourceKey == "Rice" then
		createResourcePreviewPart(model, Vector3.new(1.0, 0.35, 1.0), Color3.fromRGB(171, 106, 57), CFrame.new(0, -0.18, 0), Enum.PartType.Cylinder, Enum.Material.Wood)
		createResourcePreviewPart(model, Vector3.new(0.82, 0.28, 0.82), Color3.fromRGB(242, 240, 223), CFrame.new(0, 0.08, 0), Enum.PartType.Cylinder, Enum.Material.Sand)
	elseif resourceKey == "Meat" then
		createResourcePreviewPart(model, Vector3.new(1.0, 0.7, 0.7), Color3.fromRGB(160, 64, 56), CFrame.new(0, 0, 0), Enum.PartType.Block, Enum.Material.SmoothPlastic)
		createResourcePreviewPart(model, Vector3.new(0.22, 0.22, 0.9), Color3.fromRGB(231, 220, 208), CFrame.new(-0.6, 0, 0), Enum.PartType.Cylinder, Enum.Material.SmoothPlastic)
	elseif resourceKey == "SeaBeastMeat" then
		createResourcePreviewPart(model, Vector3.new(1.05, 0.78, 0.74), Color3.fromRGB(105, 41, 56), CFrame.new(0, 0, 0), Enum.PartType.Block, Enum.Material.SmoothPlastic)
		createResourcePreviewPart(model, Vector3.new(0.18, 0.82, 0.7), Color3.fromRGB(76, 186, 199), CFrame.new(0.52, 0, 0), Enum.PartType.Block, Enum.Material.Neon)
	elseif resourceKey == "RareShipMaterial" then
		createResourcePreviewPart(model, Vector3.new(0.8, 1.0, 0.8), Color3.fromRGB(82, 171, 255), CFrame.new(0, 0, 0), Enum.PartType.Ball, Enum.Material.Neon)
		createResourcePreviewPart(model, Vector3.new(0.22, 1.18, 0.22), Color3.fromRGB(183, 233, 255), CFrame.new(0, 0, 0), Enum.PartType.Block, Enum.Material.Glass)
	else
		createResourcePreviewPart(model, Vector3.new(0.95, 0.55, 0.7), Color3.fromRGB(149, 154, 163), CFrame.new(0, 0, 0), Enum.PartType.Block, Enum.Material.Metal)
		createResourcePreviewPart(model, Vector3.new(0.95, 0.08, 0.7), Color3.fromRGB(202, 208, 216), CFrame.new(0, 0.18, 0), Enum.PartType.Block, Enum.Material.Metal)
	end

	return model
end

local function ensureResourcePreview(button, resourceKey)
	local toolIcon = ensureButtonStructure(button).ToolIcon

	local viewport = button:FindFirstChild("ResourceViewport")
	if not viewport then
		viewport = Instance.new("ViewportFrame")
		viewport.Name = "ResourceViewport"
		viewport.Active = false
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
		viewport.Ambient = Color3.fromRGB(210, 210, 210)
		viewport.Parent = button
	end

	viewport.AnchorPoint = toolIcon.AnchorPoint
	viewport.Position = toolIcon.Position
	viewport.Size = toolIcon.Size
	viewport.ZIndex = toolIcon.ZIndex + 1
	viewport.Visible = true

	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local model = buildResourcePreviewModel(resourceKey)
	model.Parent = worldModel
	pcall(function()
		model:PivotTo(CFrame.Angles(math.rad(-12), math.rad(30), 0))
	end)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	local boxCF, boxSize = model:GetBoundingBox()
	local maxSize = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(
		boxCF.Position + Vector3.new(maxSize * 0.82, maxSize * 0.3, maxSize * 1.7),
		boxCF.Position
	)
	camera.Parent = viewport

	viewport.CurrentCamera = camera
	toolIcon.ImageTransparency = 1

	return true
end

local function ensureChestPreview(button, tierName)
	local toolIcon = ensureButtonStructure(button).ToolIcon
	local woodColor, metalColor = ChestVisuals.GetTierColors(tierName)
	local legacyViewport = button:FindFirstChild("ChestViewport")
	if legacyViewport then
		legacyViewport:Destroy()
	end

	local icon = button:FindFirstChild("ChestIcon")
	if not icon then
		icon = Instance.new("Frame")
		icon.Name = "ChestIcon"
		icon.BackgroundTransparency = 1
		icon.BorderSizePixel = 0
		icon.Parent = button
	end

	icon.AnchorPoint = toolIcon.AnchorPoint
	icon.Position = toolIcon.Position
	icon.Size = toolIcon.Size
	icon.ZIndex = toolIcon.ZIndex + 1
	icon.Visible = true

	local body = ensureNamedGuiObject(icon, "Body", "Frame")
	body.AnchorPoint = Vector2.new(0.5, 1)
	body.Position = UDim2.new(0.5, 0, 0.84, 0)
	body.Size = UDim2.new(0.72, 0, 0.36, 0)
	body.BackgroundColor3 = woodColor
	body.BorderSizePixel = 0
	body.ZIndex = icon.ZIndex + 1

	local bodyCorner = ensureNamedGuiObject(body, "Corner", "UICorner")
	bodyCorner.CornerRadius = UDim.new(0.14, 0)

	local bodyStroke = ensureNamedGuiObject(body, "Stroke", "UIStroke")
	bodyStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bodyStroke.Color = metalColor:Lerp(Color3.new(0, 0, 0), 0.18)
	bodyStroke.Thickness = 1
	bodyStroke.Transparency = 0.1

	local lid = ensureNamedGuiObject(icon, "Lid", "Frame")
	lid.AnchorPoint = Vector2.new(0.5, 0.5)
	lid.Position = UDim2.new(0.5, 0, 0.34, 0)
	lid.Size = UDim2.new(0.8, 0, 0.26, 0)
	lid.BackgroundColor3 = woodColor:Lerp(Color3.new(1, 1, 1), 0.08)
	lid.BorderSizePixel = 0
	lid.Rotation = -6
	lid.ZIndex = icon.ZIndex + 3

	local lidCorner = ensureNamedGuiObject(lid, "Corner", "UICorner")
	lidCorner.CornerRadius = UDim.new(0.18, 0)

	local lidStroke = ensureNamedGuiObject(lid, "Stroke", "UIStroke")
	lidStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	lidStroke.Color = metalColor:Lerp(Color3.new(0, 0, 0), 0.18)
	lidStroke.Thickness = 1
	lidStroke.Transparency = 0.08

	local centerBand = ensureNamedGuiObject(icon, "CenterBand", "Frame")
	centerBand.AnchorPoint = Vector2.new(0.5, 0.5)
	centerBand.Position = UDim2.new(0.5, 0, 0.5, 0)
	centerBand.Size = UDim2.new(0.12, 0, 0.56, 0)
	centerBand.BackgroundColor3 = metalColor
	centerBand.BorderSizePixel = 0
	centerBand.ZIndex = icon.ZIndex + 4

	local leftBand = ensureNamedGuiObject(icon, "LeftBand", "Frame")
	leftBand.AnchorPoint = Vector2.new(0.5, 0.5)
	leftBand.Position = UDim2.new(0.24, 0, 0.58, 0)
	leftBand.Size = UDim2.new(0.08, 0, 0.42, 0)
	leftBand.BackgroundColor3 = metalColor
	leftBand.BorderSizePixel = 0
	leftBand.ZIndex = icon.ZIndex + 2

	local rightBand = ensureNamedGuiObject(icon, "RightBand", "Frame")
	rightBand.AnchorPoint = Vector2.new(0.5, 0.5)
	rightBand.Position = UDim2.new(0.76, 0, 0.58, 0)
	rightBand.Size = UDim2.new(0.08, 0, 0.42, 0)
	rightBand.BackgroundColor3 = metalColor
	rightBand.BorderSizePixel = 0
	rightBand.ZIndex = icon.ZIndex + 2

	local latch = ensureNamedGuiObject(icon, "Latch", "Frame")
	latch.AnchorPoint = Vector2.new(0.5, 0.5)
	latch.Position = UDim2.new(0.5, 0, 0.58, 0)
	latch.Size = UDim2.new(0.16, 0, 0.14, 0)
	latch.BackgroundColor3 = metalColor:Lerp(Color3.new(1, 1, 1), 0.08)
	latch.BorderSizePixel = 0
	latch.ZIndex = icon.ZIndex + 5

	local latchCorner = ensureNamedGuiObject(latch, "Corner", "UICorner")
	latchCorner.CornerRadius = UDim.new(0.18, 0)

	toolIcon.ImageTransparency = 1

	return true
end

local function ensureDevilFruitPreview(button, fruitKey)
	local toolIcon = ensureButtonStructure(button).ToolIcon

	local modelClone = DevilFruitAssets.ClonePreviewWorldModel(fruitKey)
	if not modelClone then
		clearDevilFruitPreview(button)
		toolIcon.ImageTransparency = 1
		return false
	end

	local viewport = button:FindFirstChild("FruitViewport")
	if not viewport then
		viewport = Instance.new("ViewportFrame")
		viewport.Name = "FruitViewport"
		viewport.Active = false
		viewport.BackgroundTransparency = 1
		viewport.BorderSizePixel = 0
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
		viewport.Ambient = Color3.fromRGB(190, 190, 190)
		viewport.Parent = button
	end

	viewport.AnchorPoint = toolIcon.AnchorPoint
	viewport.Position = toolIcon.Position
	viewport.Size = toolIcon.Size
	viewport.ZIndex = toolIcon.ZIndex + 1
	viewport.Visible = true

	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	modelClone.Parent = worldModel

	if modelClone:IsA("Model") then
		pcall(function()
			modelClone:PivotTo(CFrame.Angles(math.rad(-10), math.rad(35), 0))
		end)
	end

	for _, descendant in ipairs(modelClone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	local boxCF, boxSize = modelClone:GetBoundingBox()
	local maxSize = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)

	local camera = Instance.new("Camera")
	camera.Name = "PreviewCamera"
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(
		boxCF.Position + Vector3.new(maxSize * 0.85, maxSize * 0.3, maxSize * 1.7),
		boxCF.Position
	)
	camera.Parent = viewport

	viewport.CurrentCamera = camera
	toolIcon.ImageTransparency = 1

	return true
end

local function setAmount(b, qty)
	local amount = ensureButtonStructure(b).ToolAmount
	if not amount then return end

	if qty and qty >= 2 then
		amount.Visible = true
		amount.Text = "x" .. tostring(qty)
	else
		amount.Visible = false
		amount.Text = ""
	end
end

local function setSlotVisual(b, slotValue)
	local slotLabel = ensureButtonStructure(b).ToolNumber
	if not slotLabel then
		return
	end

	if slotValue == nil then
		slotLabel.Visible = false
		slotLabel.Text = ""
		return
	end

	slotLabel.Visible = true
	slotLabel.Text = tostring(slotValue)
end

local function ensureAcquired(key)
	if not acquisition[key] then
		acquisitionCounter += 1
		acquisition[key] = acquisitionCounter
	end
end

local function disconnectConnections(connectionList)
	for index = #connectionList, 1, -1 do
		local connection = connectionList[index]
		connectionList[index] = nil
		if connection then
			connection:Disconnect()
		end
	end
end

local function setChestItemState(name, quantity)
	local qty = math.max(0, tonumber(quantity) or 0)
	local key = "Chest|" .. tostring(name)

	if qty <= 0 then
		itemState[key] = nil
	else
		ensureAcquired(key)
		itemState[key] = { kind = "Chest", name = name, qty = qty }
	end
end

local function logChestItemState()
	local chestKeys = {}
	for itemKey, item in pairs(itemState) do
		if item and item.kind == "Chest" then
			chestKeys[#chestKeys + 1] = string.format("%s=%s", itemKey, tostring(item.qty))
		end
	end
	table.sort(chestKeys)
	chestDebug("itemState chest entries after update: %s", #chestKeys > 0 and table.concat(chestKeys, ", ") or "none")
end

local function bindChestInventoryFolder(folder)
	if folder == nil or not folder:IsA("Folder") then
		return
	end

	if boundChestInventoryFolder ~= folder then
		disconnectConnections(chestInventoryFolderConnections)
		for trackedFolder, connections in pairs(chestInventoryQuantityConnections) do
			disconnectConnections(connections)
			chestInventoryQuantityConnections[trackedFolder] = nil
		end
		boundChestInventoryFolder = folder
	end

	local function hookChestFolder(chestFolder)
		if not chestFolder:IsA("Folder") or chestInventoryQuantityConnections[chestFolder] ~= nil then
			return
		end

		local quantityValue = chestFolder:FindFirstChild("Quantity") or chestFolder:WaitForChild("Quantity", 5)
		if not quantityValue or not quantityValue:IsA("NumberValue") then
			return
		end

		local connections = {}
		chestInventoryQuantityConnections[chestFolder] = connections

		local function applyQuantity()
			local quantity = math.max(0, tonumber(quantityValue.Value) or 0)
			chestDebug(
				"ChestInventory local sync chest=%s qty=%s",
				tostring(chestFolder.Name),
				tostring(quantity)
			)
			setChestItemState(chestFolder.Name, quantity)
			logChestItemState()
			rebuildUI()
		end

		applyQuantity()
		connections[#connections + 1] = quantityValue:GetPropertyChangedSignal("Value"):Connect(applyQuantity)
	end

	for _, child in ipairs(folder:GetChildren()) do
		hookChestFolder(child)
	end

	chestInventoryFolderConnections[#chestInventoryFolderConnections + 1] = folder.ChildAdded:Connect(function(child)
		hookChestFolder(child)
	end)

	chestInventoryFolderConnections[#chestInventoryFolderConnections + 1] = folder.ChildRemoved:Connect(function(child)
		local connections = chestInventoryQuantityConnections[child]
		if connections then
			disconnectConnections(connections)
			chestInventoryQuantityConnections[child] = nil
		end

		if child:IsA("Folder") then
			chestDebug("ChestInventory local remove chest=%s", tostring(child.Name))
			setChestItemState(child.Name, 0)
			logChestItemState()
			rebuildUI()
		end
	end)
end

local function getIcon(kind, name)
	if kind == "Brainrot" then
		local cfg = Brainrots[name]
		return cfg and cfg.Render or ""
	end
	if kind == "Chest" then
		return ""
	end
	if kind == "DevilFruit" then
		return ""
	end
	local cfg = Gears[name]
	return cfg and cfg.Icon or ""
end

local function getDisplayName(kind, name)
	if kind == "Chest" then
		return ChestUtils.GetDisplayName(name)
	end
	if kind == "Resource" then
		return getResourceInfo(name).DisplayName
	end
	if kind == "DevilFruit" then
		local fruit = DevilFruitConfig.GetFruit(name)
		return fruit and fruit.DisplayName or name
	end

	return name
end

local function getRarity(kind, name)
	if kind == "Chest" then
		return ChestUtils.GetRarityLabel(name)
	end
	if kind == "Resource" then
		return getResourceInfo(name).ResourceType
	end
	if kind == "DevilFruit" then
		local fruit = DevilFruitConfig.GetFruit(name)
		return fruit and fruit.Rarity or ""
	end

	if kind == "Brainrot" then
		local brainrot = Brainrots[name]
		return brainrot and brainrot.Rarity or ""
	end

	if kind == "Gear" then
		local gear = Gears[name]
		return gear and gear.Type or "Gear"
	end

	return ""
end

local function getRarityRank(rarity)
	return RARITY_ORDER[tostring(rarity or "")] or 0
end

local function getRarityColor(rarity)
	return RARITY_COLORS[tostring(rarity or "")] or TOOLTIP_SUBTEXT
end

local function ensureTooltip()
	if hoverTooltip.Gui and hoverTooltip.Gui.Parent then
		return hoverTooltip
	end

	local tooltip = Instance.new("Frame")
	tooltip.Name = "InventoryTooltip"
	tooltip.AnchorPoint = Vector2.new(0, 0)
	tooltip.AutomaticSize = Enum.AutomaticSize.XY
	tooltip.BackgroundColor3 = TOOLTIP_BACKGROUND
	tooltip.BackgroundTransparency = 0.08
	tooltip.BorderSizePixel = 0
	tooltip.Visible = false
	tooltip.ZIndex = 60
	tooltip.Parent = hudInv.Parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = tooltip

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.82
	stroke.Thickness = 1
	stroke.Parent = tooltip

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 8)
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = tooltip

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 2)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = tooltip

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AutomaticSize = Enum.AutomaticSize.XY
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.LayoutOrder = 1
	title.Text = ""
	title.TextColor3 = TOOLTIP_TEXT
	title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 61
	title.Parent = tooltip

	local rarity = Instance.new("TextLabel")
	rarity.Name = "Rarity"
	rarity.AutomaticSize = Enum.AutomaticSize.XY
	rarity.BackgroundTransparency = 1
	rarity.Font = Enum.Font.GothamMedium
	rarity.LayoutOrder = 2
	rarity.Text = ""
	rarity.TextColor3 = TOOLTIP_SUBTEXT
	rarity.TextSize = 12
	rarity.TextXAlignment = Enum.TextXAlignment.Left
	rarity.ZIndex = 61
	rarity.Parent = tooltip

	hoverTooltip.Gui = tooltip
	hoverTooltip.Title = title
	hoverTooltip.Rarity = rarity

	return hoverTooltip
end

local function updateTooltipPosition()
	local tooltip = ensureTooltip()
	if not tooltip.Visible or not tooltip.Gui then
		return
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	tooltip.Gui.Position = UDim2.fromOffset(mouseLocation.X + 14, mouseLocation.Y + 14)
end

local function hideTooltip()
	local tooltip = ensureTooltip()
	tooltip.Visible = false
	tooltip.Gui.Visible = false
end

local function showTooltip(displayName, rarityLabel)
	local tooltip = ensureTooltip()
	tooltip.Title.Text = tostring(displayName or "")
	tooltip.Rarity.Text = tostring(rarityLabel or "")
	tooltip.Rarity.TextColor3 = getRarityColor(rarityLabel)
	tooltip.Visible = true
	tooltip.Gui.Visible = true
	updateTooltipPosition()
end

local function getAllButtonText(instance)
	local textParts = {}

	if instance:IsA("TextButton") or instance:IsA("TextLabel") then
		textParts[#textParts + 1] = tostring(instance.Text or "")
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
			textParts[#textParts + 1] = tostring(descendant.Text or "")
		end
	end

	return string.lower(table.concat(textParts, " "))
end

local function buttonMatchesAliases(button, aliases)
	local haystack = string.lower(button.Name) .. " " .. getAllButtonText(button)
	for _, alias in ipairs(aliases) do
		if string.find(haystack, alias, 1, true) then
			return true
		end
	end
	return false
end

local function setButtonLabel(button, text)
	local setAny = false

	if button:IsA("TextButton") then
		button.Text = text
		setAny = true
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextButton") or descendant:IsA("TextLabel") then
			descendant.Text = text
			setAny = true
		end
	end

	if not setAny then
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.Text = text
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.TextScaled = true
		label.Parent = button
	end
end

local function cloneSidebarCategoryButton(referenceButton, categoryKey)
	local clone = referenceButton:Clone()
	clone.Name = categoryKey
	clone.Visible = true
	clone.Parent = referenceButton.Parent
	setButtonLabel(clone, CATEGORY_BUTTON_LABELS[categoryKey])
	return clone
end

local function createFallbackSidebarButton(parent, categoryKey, orderIndex)
	local button = Instance.new("TextButton")
	button.Name = categoryKey
	button.BackgroundColor3 = NORMAL
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Size = UDim2.new(1, 0, 0, 58)
	button.Position = UDim2.new(0, 0, 0, (orderIndex - 1) * 62)
	button.Font = Enum.Font.GothamBold
	button.Text = CATEGORY_BUTTON_LABELS[categoryKey]
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = NORMAL
	stroke.Parent = button

	return button
end

local function hideLegacyDevilFruitHeader(sidebarParent)
	for _, descendant in ipairs(inventoryFrame:GetDescendants()) do
		if descendant:IsDescendantOf(sidebarParent) then
			continue
		end

		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			local text = string.lower(tostring(descendant.Text or ""))
			if text == "devil fruits" or text == "devfruits" then
				descendant.Visible = false
			end
		end
	end
end

local function refreshCategoryButtons()
	for categoryKey, button in pairs(categoryButtons) do
		if button and button.Parent then
			applySelectedVisual(button, activeInventoryCategory == categoryKey)
		end
	end
end

local function setActiveCategory(categoryKey)
	if CATEGORY_LABELS[categoryKey] == nil then
		return
	end

	activeInventoryCategory = categoryKey
	refreshCategoryButtons()
	rebuildUI()
end

local function createFallbackCategoryButton(parent, categoryKey, orderIndex)
	local button = Instance.new("TextButton")
	button.Name = categoryKey .. "Tab"
	button.BackgroundColor3 = NORMAL
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	button.Size = UDim2.new(0.32, -6, 1, 0)
	button.Position = UDim2.new((orderIndex - 1) * 0.34, 0, 0, 0)
	button.Font = Enum.Font.GothamBold
	button.Text = CATEGORY_LABELS[categoryKey]
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = NORMAL
	stroke.Parent = button

	return button
end

local function ensureCategoryTabs()
	if next(categoryButtons) ~= nil then
		return
	end

	local brainrotButton = nil
	local resourcesButton = nil
	for _, descendant in ipairs(inventoryFrame:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			if brainrotButton == nil and buttonMatchesAliases(descendant, CATEGORY_ALIASES.Brainrots) then
				brainrotButton = descendant
			elseif resourcesButton == nil and buttonMatchesAliases(descendant, CATEGORY_ALIASES.Resources) then
				resourcesButton = descendant
			end
		end
	end

	local sidebarParent = nil
	if brainrotButton and brainrotButton.Parent then
		sidebarParent = brainrotButton.Parent
	elseif resourcesButton and resourcesButton.Parent then
		sidebarParent = resourcesButton.Parent
	end

	if sidebarParent then
		if brainrotButton then
			categoryButtons.Brainrots = brainrotButton
			setButtonLabel(brainrotButton, CATEGORY_BUTTON_LABELS.Brainrots)
		end
		if resourcesButton then
			categoryButtons.Resources = resourcesButton
			resourcesButton.Name = "Resources"
			setButtonLabel(resourcesButton, CATEGORY_BUTTON_LABELS.Resources)
		end
	end

	if sidebarParent and categoryButtons.DevilFruits == nil then
		local referenceButton = categoryButtons.Brainrots or categoryButtons.Resources
		if referenceButton then
			categoryButtons.DevilFruits = cloneSidebarCategoryButton(referenceButton, "DevilFruits")
			local usesLayoutOrder = referenceButton.Parent
				and (
					referenceButton.Parent:FindFirstChildOfClass("UIListLayout") ~= nil
					or referenceButton.Parent:FindFirstChildOfClass("UIGridLayout") ~= nil
				)
			if usesLayoutOrder and categoryButtons.Brainrots then
				categoryButtons.Brainrots.LayoutOrder = 1
				categoryButtons.DevilFruits.LayoutOrder = 2
				if categoryButtons.Resources then
					categoryButtons.Resources.LayoutOrder = 3
				end
			elseif categoryButtons.Brainrots and categoryButtons.Resources then
				local basePosition = categoryButtons.Brainrots.Position
				local baseSize = categoryButtons.Brainrots.Size
				categoryButtons.DevilFruits.Position = UDim2.new(
					basePosition.X.Scale,
					basePosition.X.Offset,
					basePosition.Y.Scale,
					basePosition.Y.Offset + baseSize.Y.Offset + 6
				)
				categoryButtons.DevilFruits.Size = baseSize
				categoryButtons.Resources.Position = UDim2.new(
					categoryButtons.Resources.Position.X.Scale,
					categoryButtons.Resources.Position.X.Offset,
					categoryButtons.DevilFruits.Position.Y.Scale,
					categoryButtons.DevilFruits.Position.Y.Offset + baseSize.Y.Offset + 6
				)
			end
		end
	end

	if sidebarParent == nil then
		categoryRow = Instance.new("Frame")
		categoryRow.Name = "CategorySidebar"
		categoryRow.BackgroundTransparency = 1
		categoryRow.Size = UDim2.new(0, 76, 1, -20)
		categoryRow.Position = UDim2.new(0, 10, 0, 10)
		categoryRow.Parent = inventoryFrame
		createdCategoryRow = true

		for _, categoryKey in ipairs({ "Brainrots", "DevilFruits", "Resources" }) do
			local orderIndex = CATEGORY_ORDER[categoryKey]
			if categoryButtons[categoryKey] == nil then
				categoryButtons[categoryKey] = createFallbackSidebarButton(categoryRow, categoryKey, orderIndex)
			end
		end

		scrollingFrame.Position = UDim2.new(
			scrollingFrame.Position.X.Scale,
			scrollingFrame.Position.X.Offset + 86,
			scrollingFrame.Position.Y.Scale,
			scrollingFrame.Position.Y.Offset
		)
		scrollingFrame.Size = UDim2.new(
			scrollingFrame.Size.X.Scale,
			scrollingFrame.Size.X.Offset - 86,
			scrollingFrame.Size.Y.Scale,
			scrollingFrame.Size.Y.Offset
		)
		sidebarParent = categoryRow
	end

	if sidebarParent then
		hideLegacyDevilFruitHeader(sidebarParent)
	end

	for categoryKey, button in pairs(categoryButtons) do
		if button and button.Parent then
			setButtonLabel(button, CATEGORY_BUTTON_LABELS[categoryKey] or CATEGORY_LABELS[categoryKey])
			button.MouseButton1Click:Connect(function()
				setActiveCategory(categoryKey)
			end)
		end
	end

	refreshCategoryButtons()
end

local function createButton(template, parent, kind, name)
	local b = template:Clone()
	b.Name = "Tool_" .. kind .. "_" .. name
	b.Visible = true
	b.Parent = parent
	ensureButtonStructure(b)

	b:SetAttribute("ItemKind", kind)
	b:SetAttribute("ItemName", name)

	b:SetAttribute("IsItemButton", true)

	applySelectedVisual(b, false)

	b.MouseEnter:Connect(function()
		local displayName = b:GetAttribute("DisplayName") or name
		local rarityLabel = b:GetAttribute("RarityLabel") or ""
		showTooltip(displayName, rarityLabel)
	end)

	b.MouseLeave:Connect(function()
		hideTooltip()
	end)

	b.MouseMoved:Connect(function()
		if hoverTooltip.Visible then
			updateTooltipPosition()
		end
	end)

	b.MouseButton1Click:Connect(function()
		if b:GetAttribute("ItemKind") == "Resource" then
			return
		end
		if b:GetAttribute("ItemKind") == "Chest" then
			chestDebug(
				"hotbar/inventory click chest itemName=%s visible=%s slot=%s",
				tostring(b:GetAttribute("ItemName")),
				tostring(b.Visible),
				tostring(b:GetAttribute("SlotIndex"))
			)
		end
		equipRemote:FireServer(b:GetAttribute("ItemKind"), b:GetAttribute("ItemName"))
		if b:GetAttribute("ItemKind") == "Chest" then
			chestDebug(
				"EquipToggleRemote fired from click payload={kind=%s,name=%s}",
				tostring(b:GetAttribute("ItemKind")),
				tostring(b:GetAttribute("ItemName"))
			)
		end
	end)

	if kind == "Chest" then
		chestDebug(
			"createButton chest key=%s parent=%s visible=%s active=%s",
			tostring(name),
			parent:GetFullName(),
			tostring(b.Visible),
			tostring(b.Active)
		)
	end

	return b
end

local function slotKeyForIndex(i)
	return i % 10
end

local function refreshHotbarSlots()
	local list = {}
	for _, ch in ipairs(hotbarContainer:GetChildren()) do
		if ch:IsA("GuiButton")
			and ch ~= hotbarTemplate
			and ch.Visible
			and ch:GetAttribute("IsItemButton") == true
			and ch:GetAttribute("ItemKind") ~= nil then

			table.insert(list, ch)
		end
	end

	table.sort(list, function(a, b)
		if a.LayoutOrder == b.LayoutOrder then
			return a.Name < b.Name
		end
		return a.LayoutOrder < b.LayoutOrder
	end)

	for i, b in ipairs(list) do
		local keyNum = slotKeyForIndex(i)
		b:SetAttribute("SlotIndex", keyNum)
		setSlotVisual(b, keyNum)
	end
end

local function getLists()
	local gearsList = {}
	local chestsList = {}
	local brainrotsList = {}
	local devilFruitList = {}
	local resourceList = {}

	for key, st in pairs(itemState) do
		if st.kind == "Gear" and st.owned == true then
			table.insert(gearsList, key)
		elseif st.kind == "Chest" and (st.qty or 0) > 0 then
			table.insert(chestsList, key)
		elseif st.kind == "Brainrot" and (st.qty or 0) > 0 then
			table.insert(brainrotsList, key)
		elseif st.kind == "DevilFruit" and (st.qty or 0) > 0 then
			table.insert(devilFruitList, key)
		elseif st.kind == "Resource" and (st.qty or 0) > 0 then
			table.insert(resourceList, key)
		end
	end

	table.sort(gearsList, function(a, b)
		local sa = itemState[a]
		local sb = itemState[b]
		local ca = Gears[sa.name]
		local cb = Gears[sb.name]

		local pa = 3
		local pb = 3

		if ca and ca.Type == "Weapon" then
			pa = 1
		elseif ca and ca.Type == "Speed" then
			pa = 2
		end

		if cb and cb.Type == "Weapon" then
			pb = 1
		elseif cb and cb.Type == "Speed" then
			pb = 2
		end

		if pa == pb then
			return sa.name < sb.name
		end
		return pa < pb
	end)

	table.sort(brainrotsList, function(a, b)
		local aa = acquisition[a] or 1e18
		local ab = acquisition[b] or 1e18
		if aa == ab then
			return a < b
		end
		return aa < ab
	end)

	table.sort(devilFruitList, function(a, b)
		local sa = itemState[a]
		local sb = itemState[b]
		local ra = getRarityRank(getRarity("DevilFruit", sa.name))
		local rb = getRarityRank(getRarity("DevilFruit", sb.name))
		if ra ~= rb then
			return ra > rb
		end
		local da = getDisplayName("DevilFruit", sa.name)
		local db = getDisplayName("DevilFruit", sb.name)
		return da < db
	end)

	table.sort(chestsList, function(a, b)
		local sa = itemState[a]
		local sb = itemState[b]
		local oa = ChestUtils.GetSortRank(tostring(sa and sa.name or ""))
		local ob = ChestUtils.GetSortRank(tostring(sb and sb.name or ""))
		if oa ~= ob then
			return oa < ob
		end
		return tostring(sa and sa.name or "") < tostring(sb and sb.name or "")
	end)

	table.sort(resourceList, function(a, b)
		local sa = itemState[a]
		local sb = itemState[b]
		local oa = RESOURCE_ORDER[tostring(sa and sa.name or "")] or 999
		local ob = RESOURCE_ORDER[tostring(sb and sb.name or "")] or 999
		if oa ~= ob then
			return oa < ob
		end
		return tostring(sa and sa.name or "") < tostring(sb and sb.name or "")
	end)

	return gearsList, chestsList, brainrotsList, devilFruitList, resourceList
end

rebuildUI = function()
	local gearsList, chestsList, brainrotsList, devilFruitList, resourceList = getLists()
	chestDebug("rebuildUI chestKeys=%s", table.concat(chestsList, ", "))

	local hotbarKeys = {}
	local invKeys = {}

	for _, k in ipairs(gearsList) do
		table.insert(hotbarKeys, k)
	end

	for _, k in ipairs(brainrotsList) do
		table.insert(hotbarKeys, k)
	end

	if activeInventoryCategory == "Resources" then
		for _, k in ipairs(resourceList) do
			table.insert(invKeys, k)
		end
	elseif activeInventoryCategory == "DevilFruits" then
		for _, k in ipairs(devilFruitList) do
			table.insert(invKeys, k)
		end
	else
		for _, k in ipairs(chestsList) do
			table.insert(invKeys, k)
		end
	end

	local hotbarSet = {}
	local invSet = {}

	for _, k in ipairs(hotbarKeys) do
		hotbarSet[k] = true
	end
	for _, k in ipairs(invKeys) do
		invSet[k] = true
	end

	for i, k in ipairs(hotbarKeys) do
		local st = itemState[k]
		if st then
			if not hotbarButtons[k] or not hotbarButtons[k].Parent then
				hotbarButtons[k] = createButton(hotbarTemplate, hotbarContainer, st.kind, st.name)
			end
			local b = hotbarButtons[k]
			b.LayoutOrder = i
			local displayName = getDisplayName(st.kind, st.name)
			local rarityLabel = getRarity(st.kind, st.name)
			b:SetAttribute("DisplayName", displayName)
			b:SetAttribute("RarityLabel", rarityLabel)
			setCommon(b, getIcon(st.kind, st.name), displayName)
			if st.kind == "DevilFruit" then
				ensureDevilFruitPreview(b, st.name)
				clearChestPreview(b)
			elseif st.kind == "Chest" then
				clearDevilFruitPreview(b)
				ensureChestPreview(b, st.name)
			else
				clearDevilFruitPreview(b)
				clearChestPreview(b)
			end
			setSlotVisual(b, slotKeyForIndex(i))

			if st.kind == "Brainrot" or st.kind == "Chest" then
				setAmount(b, st.qty or 0)
			else
				setAmount(b, nil)
			end

			if st.kind == "Chest" then
				chestDebug(
					"hotbar chest slot key=%s slot=%s visible=%s amount=%s layoutOrder=%s",
					k,
					tostring(b:GetAttribute("SlotIndex")),
					tostring(b.Visible),
					tostring(st.qty or 0),
					tostring(b.LayoutOrder)
				)
			end
		end
	end

	for i, k in ipairs(invKeys) do
		local st = itemState[k]
		if st and (st.kind == "Brainrot" or st.kind == "Chest" or st.kind == "Resource") then
			if not invButtons[k] or not invButtons[k].Parent then
				invButtons[k] = createButton(invTemplate, invContainer, st.kind, st.name)
			end
			local b = invButtons[k]
			b.LayoutOrder = i
			local displayName = getDisplayName(st.kind, st.name)
			local rarityLabel = getRarity(st.kind, st.name)
			b:SetAttribute("DisplayName", displayName)
			b:SetAttribute("RarityLabel", rarityLabel)
			setCommon(b, getIcon(st.kind, st.name), displayName)
			if st.kind == "Chest" then
				clearDevilFruitPreview(b)
				clearResourcePreview(b)
				ensureChestPreview(b, st.name)
			elseif st.kind == "Resource" then
				clearDevilFruitPreview(b)
				clearChestPreview(b)
				ensureResourcePreview(b, st.name)
			else
				clearDevilFruitPreview(b)
				clearChestPreview(b)
				clearResourcePreview(b)
			end
			setSlotVisual(b, nil)
			setAmount(b, st.qty or 0)
		elseif st and st.kind == "DevilFruit" then
			if not invButtons[k] or not invButtons[k].Parent then
				invButtons[k] = createButton(invTemplate, invContainer, st.kind, st.name)
			end
			local b = invButtons[k]
			b.LayoutOrder = i
			local displayName = getDisplayName(st.kind, st.name)
			local rarityLabel = getRarity(st.kind, st.name)
			b:SetAttribute("DisplayName", displayName)
			b:SetAttribute("RarityLabel", rarityLabel)
			setCommon(b, getIcon(st.kind, st.name), displayName)
			clearChestPreview(b)
			clearResourcePreview(b)
			ensureDevilFruitPreview(b, st.name)
			setSlotVisual(b, nil)
			setAmount(b, st.qty or 0)
		end
	end

	for k, b in pairs(hotbarButtons) do
		if not hotbarSet[k] then
			if b and b.Parent then b:Destroy() end
			hotbarButtons[k] = nil
		end
	end

	for k, b in pairs(invButtons) do
		if not invSet[k] then
			if b and b.Parent then b:Destroy() end
			invButtons[k] = nil
		end
	end

	refreshHotbarSlots()
	updateSelection()
	applySearchFilter()
end

local function syncResourcesFromState(state)
	local foodInventory = state and state.FoodInventory or {}
	local materials = state and state.Materials or {}

	for foodKey in pairs(Economy.Food) do
		local qty = math.max(0, tonumber(foodInventory[foodKey]) or 0)
		local key = "Resource|" .. foodKey
		if qty > 0 then
			itemState[key] = {
				kind = "Resource",
				name = foodKey,
				qty = qty,
				resourceType = "Food",
			}
		else
			itemState[key] = nil
		end
	end

	for materialKey in pairs(RESOURCE_MATERIAL_DISPLAY) do
		local qty = math.max(0, tonumber(materials[materialKey]) or 0)
		local key = "Resource|" .. materialKey
		if qty > 0 then
			itemState[key] = {
				kind = "Resource",
				name = materialKey,
				qty = qty,
				resourceType = "Material",
			}
		else
			itemState[key] = nil
		end
	end

	rebuildUI()
end

updateRemote.OnClientEvent:Connect(function(kind, name, v)
	if kind == "Chest" then
		chestDebug("InventoryGearRemote received payload={kind=Chest,name=%s,qty=%s}", tostring(name), tostring(v))
	end

	if kind == "Brainrot" then
		local cfg = Brainrots[name]
		if not cfg then return end

		local qty = tonumber(v) or 0
		local key = "Brainrot|" .. name

		if qty <= 0 then
			itemState[key] = nil
		else
			ensureAcquired(key)
			itemState[key] = { kind = "Brainrot", name = name, qty = qty }
		end

	elseif kind == "Gear" then
		local cfg = Gears[name]
		if not cfg then return end

		local key = "Gear|" .. name

		if v == true then
			ensureAcquired(key)
			itemState[key] = { kind = "Gear", name = name, owned = true }
		else
			itemState[key] = nil
		end
	elseif kind == "DevilFruit" then
		local fruit = DevilFruitConfig.GetFruit(name)
		if not fruit then return end

		local qty = tonumber(v) or 0
		local key = "DevilFruit|" .. fruit.FruitKey

		if qty <= 0 then
			itemState[key] = nil
		else
			ensureAcquired(key)
			itemState[key] = { kind = "DevilFruit", name = fruit.FruitKey, qty = qty }
		end
	elseif kind == "Chest" then
		setChestItemState(name, v)
		logChestItemState()
	end

	rebuildUI()
end)

ensureCategoryTabs()
MetaClient.ObserveState(function(state)
	syncResourcesFromState(state)
end)

local keyToSlot = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 0,
}

local function activateSlot(slotKey)
	for _, b in ipairs(hotbarContainer:GetChildren()) do
		if b:IsA("GuiButton")
			and b ~= hotbarTemplate
			and b.Visible
			and b:GetAttribute("IsItemButton") == true
			and b:GetAttribute("ItemKind") ~= nil then

			if b:GetAttribute("SlotIndex") == slotKey then
				if b:GetAttribute("ItemKind") == "Chest" then
					chestDebug(
						"activateSlot chest slot=%s itemName=%s visible=%s",
						tostring(slotKey),
						tostring(b:GetAttribute("ItemName")),
						tostring(b.Visible)
					)
				end
				equipRemote:FireServer(b:GetAttribute("ItemKind"), b:GetAttribute("ItemName"))
				if b:GetAttribute("ItemKind") == "Chest" then
					chestDebug(
						"EquipToggleRemote fired from slot payload={kind=%s,name=%s}",
						tostring(b:GetAttribute("ItemKind")),
						tostring(b:GetAttribute("ItemName"))
					)
				end
				return
			end
		end
	end
end

local function toggleInventory()
	inventoryFrame.Visible = not inventoryFrame.Visible
	if not inventoryFrame.Visible then
		hideTooltip()
	end
end

inventoryBtn.MouseButton1Click:Connect(toggleInventory)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if UserInputService:GetFocusedTextBox() then return end

	if input.KeyCode == Enum.KeyCode.Backquote or input.KeyCode == Enum.KeyCode.F then
		toggleInventory()
		return
	end

	local slot = keyToSlot[input.KeyCode]
	if slot ~= nil then
		activateSlot(slot)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and hoverTooltip.Visible then
		updateTooltipPosition()
	end
end)

local function scanEquipped(char)
	local attributeKind = player:GetAttribute("EquippedInventoryItemKind")
	local attributeName = player:GetAttribute("EquippedInventoryItemName")
	if typeof(attributeName) == "string" and attributeName ~= "" then
		equippedKind = if typeof(attributeKind) == "string" and attributeKind ~= "" then attributeKind else nil
		equippedName = attributeName
		updateSelection()
		return
	end

	equippedKind = nil
	equippedName = nil
	for _, ch in ipairs(char:GetChildren()) do
		if ch:IsA("Tool") then
			local canonicalName = ch:GetAttribute("InvItem") or ch:GetAttribute("InventoryItemName")
			local canonicalKind = ch:GetAttribute("InventoryItemKind")
			if typeof(canonicalName) == "string" and canonicalName ~= "" then
				equippedKind = if typeof(canonicalKind) == "string" and canonicalKind ~= "" then canonicalKind else nil
				equippedName = canonicalName
			else
				equippedKind = if typeof(canonicalKind) == "string" and canonicalKind ~= "" then canonicalKind else nil
				equippedName = ch.Name
			end
			break
		end
	end
	updateSelection()
end

local function hookCharacter(char)
	scanEquipped(char)

	char.ChildAdded:Connect(function(obj)
		if obj:IsA("Tool") then
			if obj:GetAttribute("InventoryItemKind") == "Chest" then
				chestDebug(
					"Character ChildAdded chest tool name=%s parent=%s",
					tostring(obj.Name),
					obj.Parent and obj.Parent:GetFullName() or "nil"
				)
			end
			task.defer(function()
				if char.Parent ~= nil then
					scanEquipped(char)
				end
			end)
		end
	end)

	char.ChildRemoved:Connect(function(obj)
		if obj:IsA("Tool") then
			if obj:GetAttribute("InventoryItemKind") == "Chest" then
				chestDebug(
					"Character ChildRemoved chest tool name=%s",
					tostring(obj.Name)
				)
			end
			task.defer(function()
				if char.Parent ~= nil then
					scanEquipped(char)
				end
			end)
		end
	end)
end

if player.Character then
	hookCharacter(player.Character)
end

player.CharacterAdded:Connect(hookCharacter)

player:GetAttributeChangedSignal("EquippedInventoryItemKind"):Connect(function()
	if player.Character then
		scanEquipped(player.Character)
	else
		equippedKind = nil
		updateSelection()
	end
end)

player:GetAttributeChangedSignal("EquippedInventoryItemName"):Connect(function()
	if player.Character then
		scanEquipped(player.Character)
	else
		equippedName = nil
		updateSelection()
	end
end)

bindChestInventoryFolder(player:FindFirstChild("ChestInventory") or player:WaitForChild("ChestInventory", 10))
player.ChildAdded:Connect(function(child)
	if child.Name == "ChestInventory" and child:IsA("Folder") then
		bindChestInventoryFolder(child)
	end
end)

 
