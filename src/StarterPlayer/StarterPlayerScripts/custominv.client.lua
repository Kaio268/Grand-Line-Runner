local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local updateRemote = ReplicatedStorage:WaitForChild("InventoryGearRemote")
local equipRemote = ReplicatedStorage:WaitForChild("EquipToggleRemote")

local Brainrots = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local Gears = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DevilFruitAssets = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("Assets"))

local hudInv = player:WaitForChild("PlayerGui"):WaitForChild("HUD"):WaitForChild("Inventory")
local hotbarTemplate = hudInv:WaitForChild("toolButton")
local hotbarContainer = hotbarTemplate.Parent
local inventoryBtn = hudInv:WaitForChild("InventoryBtn")

local inb = hudInv:WaitForChild("Inv")
local inventoryFrame = inb:WaitForChild("InventoryFrame")
local scrollingFrame = inventoryFrame:WaitForChild("ScrollingFrame")
local invTemplate = scrollingFrame:WaitForChild("toolButton")
local invContainer = invTemplate.Parent

local MAX_HOTBAR = 9

local NORMAL = Color3.fromRGB(0, 0, 0)
local SELECT = Color3.fromRGB(255, 255, 255)
local TOOLTIP_BACKGROUND = Color3.fromRGB(20, 24, 32)
local TOOLTIP_TEXT = Color3.fromRGB(245, 247, 250)
local TOOLTIP_SUBTEXT = Color3.fromRGB(180, 188, 200)

local equippedName = nil

local hotbarButtons = {}
local invButtons = {}

local itemState = {}
local acquisition = {}
local acquisitionCounter = 0
local hoverTooltip = {
	Gui = nil,
	Title = nil,
	Rarity = nil,
	Visible = false,
}

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
			applySelectedVisual(b, equippedName ~= nil and b:GetAttribute("ItemName") == equippedName)
		end
	end
	for _, b in pairs(invButtons) do
		if b and b.Parent then
			applySelectedVisual(b, equippedName ~= nil and b:GetAttribute("ItemName") == equippedName)
		end
	end
end

local function setCommon(b, icon, displayName)
	local toolIcon = b:WaitForChild("ToolIcon")
	local toolName = b:WaitForChild("toolName")
	toolIcon.Image = icon or ""
	toolIcon.ImageTransparency = (icon and icon ~= "") and 0 or 1
	toolName.Text = displayName or ""
end

local function clearDevilFruitPreview(button)
	local viewport = button:FindFirstChild("FruitViewport")
	if viewport then
		viewport:Destroy()
	end
end

local function ensureDevilFruitPreview(button, fruitKey)
	local toolIcon = button:FindFirstChild("ToolIcon")
	if not toolIcon or not toolIcon:IsA("GuiObject") then
		return false
	end

	local sourceModel = DevilFruitAssets.GetWorldModelByKey(fruitKey)
	if not sourceModel then
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

	local modelClone = sourceModel:Clone()
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
	local amount = b:FindFirstChild("toolAmount")
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
	local slotLabel = b:FindFirstChild("toolNumber")
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

local function getIcon(kind, name)
	if kind == "Brainrot" then
		local cfg = Brainrots[name]
		return cfg and cfg.Render or ""
	end
	if kind == "DevilFruit" then
		return ""
	end
	local cfg = Gears[name]
	return cfg and cfg.Icon or ""
end

local function getDisplayName(kind, name)
	if kind == "DevilFruit" then
		local fruit = DevilFruitConfig.GetFruit(name)
		return fruit and fruit.DisplayName or name
	end

	return name
end

local function getRarity(kind, name)
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

local function createButton(template, parent, kind, name)
	local b = template:Clone()
	b.Name = "Tool_" .. kind .. "_" .. name
	b.Visible = true
	b.Parent = parent

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
		equipRemote:FireServer(b:GetAttribute("ItemKind"), b:GetAttribute("ItemName"))
	end)

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
	local brainrotsList = {}
	local devilFruitList = {}

	for key, st in pairs(itemState) do
		if st.kind == "Gear" and st.owned == true then
			table.insert(gearsList, key)
		elseif st.kind == "Brainrot" and (st.qty or 0) > 0 then
			table.insert(brainrotsList, key)
		elseif st.kind == "DevilFruit" and (st.qty or 0) > 0 then
			table.insert(devilFruitList, key)
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

	return gearsList, brainrotsList, devilFruitList
end

local function rebuildUI()
	local gearsList, brainrotsList, devilFruitList = getLists()

	local hotbarKeys = {}
	local invKeys = {}

	for _, k in ipairs(gearsList) do
		table.insert(hotbarKeys, k)
	end

	local remaining = MAX_HOTBAR - #hotbarKeys
	if remaining < 0 then
		remaining = 0
	end

	for i = 1, #brainrotsList do
		local k = brainrotsList[i]
		if i <= remaining then
			table.insert(hotbarKeys, k)
		else
			table.insert(invKeys, k)
		end
	end

	for _, k in ipairs(devilFruitList) do
		table.insert(invKeys, k)
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
			else
				clearDevilFruitPreview(b)
			end
			setSlotVisual(b, slotKeyForIndex(i))

			if st.kind == "Brainrot" then
				setAmount(b, st.qty or 0)
			else
				setAmount(b, nil)
			end
		end
	end

	for i, k in ipairs(invKeys) do
		local st = itemState[k]
		if st and st.kind == "Brainrot" then
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
			clearDevilFruitPreview(b)
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

updateRemote.OnClientEvent:Connect(function(kind, name, v)
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
	end

	rebuildUI()
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
				equipRemote:FireServer(b:GetAttribute("ItemKind"), b:GetAttribute("ItemName"))
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
	equippedName = nil
	for _, ch in ipairs(char:GetChildren()) do
		if ch:IsA("Tool") then
			equippedName = ch.Name
			break
		end
	end
	updateSelection()
end

local function hookCharacter(char)
	scanEquipped(char)

	char.ChildAdded:Connect(function(obj)
		if obj:IsA("Tool") then
			equippedName = obj.Name
			updateSelection()
		end
	end)

	char.ChildRemoved:Connect(function(obj)
		if obj:IsA("Tool") and equippedName == obj.Name then
			equippedName = nil
			updateSelection()
		end
	end)
end

if player.Character then
	hookCharacter(player.Character)
end

player.CharacterAdded:Connect(hookCharacter)

 
