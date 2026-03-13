local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local updateRemote = ReplicatedStorage:WaitForChild("InventoryGearRemote")
local equipRemote = ReplicatedStorage:WaitForChild("EquipToggleRemote")

local Brainrots = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local Gears = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Gears"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

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

local equippedName = nil

local hotbarButtons = {}
local invButtons = {}

local itemState = {}
local acquisition = {}
local acquisitionCounter = 0

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
	toolName.Text = displayName or ""
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

local function createButton(template, parent, kind, name)
	local b = template:Clone()
	b.Name = "Tool_" .. kind .. "_" .. name
	b.Visible = true
	b.Parent = parent

	b:SetAttribute("ItemKind", kind)
	b:SetAttribute("ItemName", name)

	b:SetAttribute("IsItemButton", true)

	applySelectedVisual(b, false)

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

		local tn = b:FindFirstChild("toolNumber")
		if tn then
			tn.Text = tostring(keyNum)
		end
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
			setCommon(b, getIcon(st.kind, st.name), getDisplayName(st.kind, st.name))

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
			setCommon(b, getIcon(st.kind, st.name), getDisplayName(st.kind, st.name))
			setAmount(b, st.qty or 0)
		elseif st and st.kind == "DevilFruit" then
			if not invButtons[k] or not invButtons[k].Parent then
				invButtons[k] = createButton(invTemplate, invContainer, st.kind, st.name)
			end
			local b = invButtons[k]
			b.LayoutOrder = i
			setCommon(b, getIcon(st.kind, st.name), getDisplayName(st.kind, st.name))
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

 
