local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local Modules = ReplicatedStorage:WaitForChild("Modules")
local UiFolder = ReplicatedStorage:WaitForChild("UI")

local React = require(Packages:WaitForChild("React"))
local ReactRoblox = require(Packages:WaitForChild("ReactRoblox"))
local App = require(UiFolder:WaitForChild("App"))

local Brainrots = require(Modules:WaitForChild("Configs"):WaitForChild("Brainrots"))
local Gears = require(Modules:WaitForChild("Configs"):WaitForChild("Gears"))
local DevilFruits = require(Modules:WaitForChild("Configs"):WaitForChild("DevilFruits"))
local Economy = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local MetaClient = require(Modules:WaitForChild("GrandLineRushMetaClient"))

local updateRemote = ReplicatedStorage:WaitForChild("InventoryGearRemote")
local equipRemote = ReplicatedStorage:WaitForChild("EquipToggleRemote")

local rootContainer = Instance.new("Folder")
rootContainer.Name = "ReactInventoryRoot"

local root = ReactRoblox.createRoot(rootContainer)

local MAX_BRAINROT_HOTBAR = 9

local CHEST_ORDER = {
	Wooden = 1,
	Iron = 2,
	Gold = 3,
	Legendary = 4,
}

local RESOURCE_ORDER = {
	Apple = 1,
	Rice = 2,
	Meat = 3,
	SeaBeastMeat = 4,
	Timber = 5,
	Iron = 6,
	AncientTimber = 7,
}

local RARITY_ORDER = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Mythical = 6,
	Godly = 7,
	Secret = 8,
	Omega = 9,
}

local CATEGORY_DEFS = {
	Brainrots = {
		label = "Brainrots",
		accentColor = Color3.fromRGB(93, 203, 200),
	},
	DevilFruits = {
		label = "Devil Fruits",
		accentColor = Color3.fromRGB(239, 129, 156),
	},
	Resources = {
		label = "Resources",
		accentColor = Color3.fromRGB(241, 184, 86),
	},
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(188, 197, 211),
	Uncommon = Color3.fromRGB(112, 220, 140),
	Rare = Color3.fromRGB(91, 170, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 187, 74),
	Mythic = Color3.fromRGB(255, 101, 134),
	Mythical = Color3.fromRGB(255, 101, 134),
	Godly = Color3.fromRGB(255, 84, 84),
	Secret = Color3.fromRGB(255, 240, 110),
	Omega = Color3.fromRGB(132, 255, 247),
}

local RESOURCE_DISPLAY = {
	Timber = "Timber",
	Iron = "Iron",
	AncientTimber = "Ancient Timber",
}

local KEY_TO_SLOT = {
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

local HUD_BUTTON_NAMES = {
	Store = true,
	Index = true,
	Claim = true,
	Settings = true,
	Rebirth = true,
}

local itemState = {}
local acquisition = {}
local acquisitionCounter = 0
local metaState = nil
local equippedName = nil
local keyboardHotbar = {}
local renderQueued = false
local destroyed = false
local stopObservingState = nil
local scheduleRender
local syncDevilFruitsFromInventory
local lastToggleLayoutSignature = nil

local uiState = {
	isOpen = false,
	activeView = "Inventory",
	activeCategory = "Brainrots",
	query = "",
}

local cleanupConnections = {}
local characterConnections = {}
local hudLayoutConnections = {}
local shipDataConnections = {}

local function disconnectAll(bucket)
	for _, connection in ipairs(bucket) do
		connection:Disconnect()
	end
	table.clear(bucket)
end

local function trackConnection(signal, callback, bucket)
	local connection = signal:Connect(callback)
	table.insert(bucket, connection)
	return connection
end

local function trim(text)
	return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function matchesQuery(entry, query)
	if query == "" then
		return true
	end

	local haystack = string.lower(table.concat({
		tostring(entry.displayName or ""),
		tostring(entry.subtitle or ""),
		tostring(entry.footer or ""),
	}, " "))

	return string.find(haystack, string.lower(query), 1, true) ~= nil
end

local function shortName(text)
	local value = tostring(text or "")
	if #value <= 12 then
		return value
	end
	return string.sub(value, 1, 11) .. "..."
end

local function formatNumber(value)
	local number = math.floor(tonumber(value) or 0)
	local formatted = tostring(math.abs(number))

	while true do
		local updated, count = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		formatted = updated
		if count == 0 then
			break
		end
	end

	return number < 0 and ("-" .. formatted) or formatted
end

local function ensureAcquired(key)
	if not acquisition[key] then
		acquisitionCounter += 1
		acquisition[key] = acquisitionCounter
	end
end

local function getResourceInfo(resourceKey)
	local food = Economy.Food[resourceKey]
	if food then
		return {
			displayName = tostring(food.DisplayName or resourceKey),
			subtitle = "Food",
		}
	end

	return {
		displayName = RESOURCE_DISPLAY[resourceKey] or tostring(resourceKey),
		subtitle = "Material",
	}
end

local function getDisplayName(kind, name)
	if kind == "Chest" then
		return string.format("%s Chest", tostring(name))
	end

	if kind == "Resource" then
		return getResourceInfo(name).displayName
	end

	if kind == "DevilFruit" then
		local fruit = DevilFruits.GetFruit(name)
		return fruit and fruit.DisplayName or tostring(name)
	end

	return tostring(name)
end

local function getSubtitle(kind, name)
	if kind == "Chest" then
		return tostring(name) .. " Chest"
	end

	if kind == "Resource" then
		return getResourceInfo(name).subtitle
	end

	if kind == "DevilFruit" then
		local fruit = DevilFruits.GetFruit(name)
		return fruit and tostring(fruit.Rarity or "Devil Fruit") or "Devil Fruit"
	end

	if kind == "Brainrot" then
		local brainrot = Brainrots[name]
		return brainrot and tostring(brainrot.Rarity or "Brainrot") or "Brainrot"
	end

	if kind == "Gear" then
		local gear = Gears[name]
		return gear and tostring(gear.Type or "Gear") or "Gear"
	end

	return ""
end

local function getIcon(kind, name)
	if kind == "Brainrot" then
		local brainrot = Brainrots[name]
		return brainrot and brainrot.Render or ""
	end

	if kind == "Gear" then
		local gear = Gears[name]
		return gear and gear.Icon or ""
	end

	return ""
end

local function getAccentColor(kind, name, state)
	if kind == "Brainrot" or kind == "DevilFruit" then
		return RARITY_COLORS[getSubtitle(kind, name)] or Color3.fromRGB(93, 203, 200)
	end

	if kind == "Chest" then
		if name == "Legendary" then
			return Color3.fromRGB(255, 187, 74)
		end
		if name == "Gold" then
			return Color3.fromRGB(222, 189, 74)
		end
		if name == "Iron" then
			return Color3.fromRGB(162, 175, 194)
		end
		return Color3.fromRGB(191, 143, 86)
	end

	if kind == "Gear" then
		local gear = Gears[name]
		if gear and gear.Type == "Speed" then
			return Color3.fromRGB(109, 201, 255)
		end
		return Color3.fromRGB(255, 128, 128)
	end

	if kind == "Resource" then
		if state and state.resourceType == "Food" then
			return Color3.fromRGB(113, 216, 146)
		end

		if name == "Iron" then
			return Color3.fromRGB(156, 172, 196)
		end
		if name == "AncientTimber" then
			return Color3.fromRGB(132, 197, 146)
		end
		return Color3.fromRGB(191, 143, 86)
	end

	return Color3.fromRGB(93, 203, 200)
end

local function readChildValue(parent, childName)
	if not parent then
		return nil
	end

	local child = parent:FindFirstChild(childName)
	if child and child:IsA("ValueBase") then
		return child.Value
	end

	return nil
end

local function readPlayerDoubloons()
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = readChildValue(leaderstats, "Doubloons")
	if typeof(value) == "number" then
		return math.max(0, value)
	end

	return math.max(0, tonumber(metaState and metaState.Doubloons) or 0)
end

local function readPlayerMaterials()
	local materialsFolder = player:FindFirstChild("Materials")
	local metaMaterials = metaState and metaState.Materials or {}

	return {
		Timber = math.max(
			0,
			tonumber(readChildValue(materialsFolder, "Timber"))
				or tonumber(readChildValue(materialsFolder, "CommonShipMaterial"))
				or tonumber(metaMaterials.Timber)
				or tonumber(metaMaterials.CommonShipMaterial)
				or 0
		),
		Iron = math.max(
			0,
			tonumber(readChildValue(materialsFolder, "Iron"))
				or tonumber(readChildValue(materialsFolder, "RareShipMaterial"))
				or tonumber(metaMaterials.Iron)
				or tonumber(metaMaterials.RareShipMaterial)
				or 0
		),
		AncientTimber = math.max(
			0,
			tonumber(readChildValue(materialsFolder, "AncientTimber"))
				or tonumber(metaMaterials.AncientTimber)
				or 0
		),
	}
end

local function readPlayerChestCount(chestsList)
	local unopenedFolder = player:FindFirstChild("UnopenedChests")
	local byIdFolder = unopenedFolder and unopenedFolder:FindFirstChild("ById")

	if byIdFolder then
		return #byIdFolder:GetChildren()
	end

	local chestCount = math.max(0, tonumber(metaState and metaState.UnopenedChestCount) or 0)
	if chestCount > 0 then
		return chestCount
	end

	for _, key in ipairs(chestsList or {}) do
		chestCount += tonumber(itemState[key] and itemState[key].qty) or 0
	end

	return chestCount
end

local function buildCaptainLogData(query)
	local entries = {}
	local totalCollectable = 0
	local totalPlaced = 0
	local standNames = {}

	local shipFolder = player:FindFirstChild("Ship")
	local slotsFolder = shipFolder and shipFolder:FindFirstChild("Slots")
	local incomeFolder = player:FindFirstChild("IncomeBrainrots")

	if slotsFolder then
		for _, child in ipairs(slotsFolder:GetChildren()) do
			standNames[child.Name] = true
		end
	end

	if incomeFolder then
		for _, child in ipairs(incomeFolder:GetChildren()) do
			standNames[child.Name] = true
		end
	end

	for standName in pairs(standNames) do
		local slotFolder = slotsFolder and slotsFolder:FindFirstChild(standName)
		local standIncomeFolder = incomeFolder and incomeFolder:FindFirstChild(standName)
		local brainrotName = tostring(readChildValue(slotFolder, "BrainrotName") or readChildValue(standIncomeFolder, "BrainrotName") or "")

		if brainrotName ~= "" then
			totalPlaced += 1
			local incomePerTick = math.max(0, tonumber(readChildValue(slotFolder, "Income")) or 0)
			local collectable = math.max(0, tonumber(readChildValue(standIncomeFolder, "IncomeToCollect")) or 0)
			local subtitle = getSubtitle("Brainrot", brainrotName)
			local displayName = getDisplayName("Brainrot", brainrotName)

			local entry = {
				key = standName,
				standName = standName,
				brainrotName = brainrotName,
				displayName = displayName,
				subtitle = subtitle,
				footer = "",
				image = getIcon("Brainrot", brainrotName),
				fallbackText = string.sub(string.upper(displayName), 1, 2),
				accentColor = getAccentColor("Brainrot", brainrotName),
				incomePerTick = incomePerTick,
				collectable = collectable,
			}

			entry.footer = string.format("%s  |  %s D ready", standName, formatNumber(collectable))

			if matchesQuery(entry, query) then
				entries[#entries + 1] = entry
			end

			totalCollectable += collectable
		end
	end

	table.sort(entries, function(a, b)
		if a.incomePerTick == b.incomePerTick then
			return tostring(a.standName) < tostring(b.standName)
		end
		return a.incomePerTick > b.incomePerTick
	end)

	return {
		entries = entries,
		filteredCount = #entries,
		placedCount = totalPlaced,
		totalCollectable = totalCollectable,
		totalCount = totalPlaced,
	}
end

local function buildLists()
	local gearsList = {}
	local chestsList = {}
	local brainrotsList = {}
	local devilFruitList = {}
	local resourceList = {}

	for key, state in pairs(itemState) do
		if state.kind == "Gear" and state.owned == true then
			gearsList[#gearsList + 1] = key
		elseif state.kind == "Chest" and (state.qty or 0) > 0 then
			chestsList[#chestsList + 1] = key
		elseif state.kind == "Brainrot" and (state.qty or 0) > 0 then
			brainrotsList[#brainrotsList + 1] = key
		elseif state.kind == "DevilFruit" and (state.qty or 0) > 0 then
			devilFruitList[#devilFruitList + 1] = key
		elseif state.kind == "Resource" and (state.qty or 0) > 0 then
			resourceList[#resourceList + 1] = key
		end
	end

	table.sort(gearsList, function(a, b)
		local gearA = Gears[itemState[a].name]
		local gearB = Gears[itemState[b].name]
		local priorityA = gearA and gearA.Type == "Weapon" and 1 or (gearA and gearA.Type == "Speed" and 2 or 3)
		local priorityB = gearB and gearB.Type == "Weapon" and 1 or (gearB and gearB.Type == "Speed" and 2 or 3)
		if priorityA == priorityB then
			return tostring(itemState[a].name) < tostring(itemState[b].name)
		end
		return priorityA < priorityB
	end)

	table.sort(chestsList, function(a, b)
		local orderA = CHEST_ORDER[tostring(itemState[a].name)] or 99
		local orderB = CHEST_ORDER[tostring(itemState[b].name)] or 99
		if orderA == orderB then
			return tostring(itemState[a].name) < tostring(itemState[b].name)
		end
		return orderA < orderB
	end)

	table.sort(brainrotsList, function(a, b)
		local acquireA = acquisition[a] or math.huge
		local acquireB = acquisition[b] or math.huge
		if acquireA == acquireB then
			return tostring(itemState[a].name) < tostring(itemState[b].name)
		end
		return acquireA < acquireB
	end)

	table.sort(devilFruitList, function(a, b)
		local rankA = RARITY_ORDER[getSubtitle("DevilFruit", itemState[a].name)] or 0
		local rankB = RARITY_ORDER[getSubtitle("DevilFruit", itemState[b].name)] or 0
		if rankA == rankB then
			return getDisplayName("DevilFruit", itemState[a].name) < getDisplayName("DevilFruit", itemState[b].name)
		end
		return rankA > rankB
	end)

	table.sort(resourceList, function(a, b)
		local orderA = RESOURCE_ORDER[tostring(itemState[a].name)] or 99
		local orderB = RESOURCE_ORDER[tostring(itemState[b].name)] or 99
		if orderA == orderB then
			return tostring(itemState[a].name) < tostring(itemState[b].name)
		end
		return orderA < orderB
	end)

	return gearsList, chestsList, brainrotsList, devilFruitList, resourceList
end

local function buildEntry(key, state)
	local displayName = getDisplayName(state.kind, state.name)
	local subtitle = getSubtitle(state.kind, state.name)
	local kindFooter = state.kind == "Resource" and "Display only" or "Click to equip"
	local previewKind = nil
	local previewName = nil

	if state.kind == "DevilFruit" then
		previewKind = "DevilFruit"
		previewName = state.name
	elseif state.kind == "Chest" then
		previewKind = "Chest"
		previewName = state.name
	elseif state.kind == "Resource" then
		previewKind = "Resource"
		previewName = state.name
	end

	return {
		key = key,
		kind = state.kind,
		name = state.name,
		displayName = displayName,
		shortName = shortName(displayName),
		subtitle = subtitle,
		footer = kindFooter,
		image = getIcon(state.kind, state.name),
		fallbackText = string.sub(string.upper(displayName), 1, 2),
		previewKind = previewKind,
		previewName = previewName,
		quantity = state.qty,
		accentColor = getAccentColor(state.kind, state.name, state),
		interactive = state.kind ~= "Resource",
		isEquipped = equippedName ~= nil and tostring(state.name) == tostring(equippedName),
	}
end

local function slotLabelForIndex(index)
	if index > 10 then
		return nil
	end
	return index % 10
end

local function buildRenderData()
	syncDevilFruitsFromInventory()

	local gearsList, chestsList, brainrotsList, devilFruitList, resourceList = buildLists()
	local hotbarKeys = {}
	local query = trim(uiState.query)

	for _, key in ipairs(gearsList) do
		hotbarKeys[#hotbarKeys + 1] = key
	end
	for _, key in ipairs(chestsList) do
		hotbarKeys[#hotbarKeys + 1] = key
	end
	for index, key in ipairs(brainrotsList) do
		if index <= MAX_BRAINROT_HOTBAR then
			hotbarKeys[#hotbarKeys + 1] = key
		end
	end

	local hotbarSlots = {}
	keyboardHotbar = {}
	for index, key in ipairs(hotbarKeys) do
		local state = itemState[key]
		if state then
			local entry = buildEntry(key, state)
			local slotLabel = slotLabelForIndex(index)
			hotbarSlots[#hotbarSlots + 1] = {
				slotLabel = slotLabel,
				item = entry,
			}
			if slotLabel ~= nil and keyboardHotbar[slotLabel] == nil then
				keyboardHotbar[slotLabel] = entry
			end
		end
	end

	local targetHotbarSlots = math.max(10, #hotbarSlots)
	for index = #hotbarSlots + 1, targetHotbarSlots do
		hotbarSlots[#hotbarSlots + 1] = {
			slotLabel = slotLabelForIndex(index),
			item = nil,
		}
	end

	local activeKeys = uiState.activeCategory == "DevilFruits" and devilFruitList
		or (uiState.activeCategory == "Resources" and resourceList or brainrotsList)

	local items = {}
	for _, key in ipairs(activeKeys) do
		local state = itemState[key]
		if state then
			local entry = buildEntry(key, state)
			if matchesQuery(entry, query) then
				items[#items + 1] = entry
			end
		end
	end

	local categories = {
		{
			key = "Brainrots",
			label = CATEGORY_DEFS.Brainrots.label,
			count = #brainrotsList,
			accentColor = CATEGORY_DEFS.Brainrots.accentColor,
		},
		{
			key = "DevilFruits",
			label = CATEGORY_DEFS.DevilFruits.label,
			count = #devilFruitList,
			accentColor = CATEGORY_DEFS.DevilFruits.accentColor,
		},
		{
			key = "Resources",
			label = CATEGORY_DEFS.Resources.label,
			count = #resourceList,
			accentColor = CATEGORY_DEFS.Resources.accentColor,
		},
	}

	local liveMaterials = readPlayerMaterials()
	local chestCount = readPlayerChestCount(chestsList)

	local totalStacks = 0
	for _, state in pairs(itemState) do
		if state.kind ~= "Resource" or (state.qty or 0) > 0 then
			totalStacks += 1
		end
	end

	local captainLog = buildCaptainLogData(query)

	return {
		hotbarSlots = hotbarSlots,
		items = items,
		categories = categories,
		captainLog = captainLog,
		summary = {
			doubloons = readPlayerDoubloons(),
			chests = chestCount,
			timber = liveMaterials.Timber,
			iron = liveMaterials.Iron,
			ancientTimber = liveMaterials.AncientTimber,
			totalStacks = totalStacks,
		},
		activeView = uiState.activeView,
		activeCategoryLabel = CATEGORY_DEFS[uiState.activeCategory].label,
		filteredCount = #items,
		totalCount = #activeKeys,
		query = uiState.query,
	}
end

local function hideLegacyInventory()
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end

	local inventory = hud:FindFirstChild("Inventory")
	if inventory then
		if inventory:IsA("LayerCollector") then
			inventory.Enabled = false
		elseif inventory:IsA("GuiObject") then
			inventory.Visible = false
		end
	end
end

local function getToggleLayout()
	return {
		anchorPoint = Vector2.new(0, 0),
		position = UDim2.fromOffset(0, 18),
		size = UDim2.fromOffset(74, 74),
		compact = true,
		dock = "hotbarLeft",
	}
end

local function getLegacyInventoryIcon()
	local hud = playerGui:FindFirstChild("HUD")
	local inventoryGui = hud and hud:FindFirstChild("Inventory")
	local legacyButton = inventoryGui and inventoryGui:FindFirstChild("InventoryBtn", true)
	if not legacyButton then
		return nil
	end

	local bestCandidate = nil
	local bestArea = -1

	local function consider(candidate)
		if not candidate or not (candidate:IsA("ImageLabel") or candidate:IsA("ImageButton")) then
			return
		end

		if candidate.Image == nil or candidate.Image == "" then
			return
		end

		local area = candidate.AbsoluteSize.X * candidate.AbsoluteSize.Y
		if area <= 0 then
			local size = candidate.Size
			area = math.abs(size.X.Offset) * math.abs(size.Y.Offset)
		end

		if area > bestArea then
			bestArea = area
			bestCandidate = candidate
		end
	end

	consider(legacyButton)
	for _, descendant in ipairs(legacyButton:GetDescendants()) do
		consider(descendant)
	end

	if not bestCandidate then
		return nil
	end

	return {
		image = bestCandidate.Image,
		imageColor3 = bestCandidate.ImageColor3,
		imageRectOffset = bestCandidate.ImageRectOffset,
		imageRectSize = bestCandidate.ImageRectSize,
		scaleType = bestCandidate.ScaleType,
	}
end

local function getToggleLayoutSignature()
	local layout = getToggleLayout()
	if not layout then
		return "none"
	end

	return table.concat({
		tostring(math.floor(layout.position.X.Offset + 0.5)),
		tostring(math.floor(layout.position.Y.Offset + 0.5)),
		tostring(math.floor(layout.size.X.Offset + 0.5)),
		tostring(math.floor(layout.size.Y.Offset + 0.5)),
		layout.compact and "1" or "0",
	}, "|")
end

local function bindHudLayoutTracking()
	disconnectAll(hudLayoutConnections)

	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		return
	end

	for _, descendant in ipairs(hud:GetDescendants()) do
		if descendant:IsA("GuiButton") and HUD_BUTTON_NAMES[descendant.Name] then
			trackConnection(descendant:GetPropertyChangedSignal("Visible"), scheduleRender, hudLayoutConnections)
		end
	end
end

local function bindShipDataTracking()
	disconnectAll(shipDataConnections)

	local function watchRoot(root)
		if not root then
			return
		end

		for _, descendant in ipairs(root:GetDescendants()) do
			if descendant:IsA("ValueBase") then
				trackConnection(descendant:GetPropertyChangedSignal("Value"), scheduleRender, shipDataConnections)
			end
		end

		trackConnection(root.DescendantAdded, function(descendant)
			if descendant:IsA("ValueBase") then
				trackConnection(descendant:GetPropertyChangedSignal("Value"), scheduleRender, shipDataConnections)
			end
			scheduleRender()
		end, shipDataConnections)

		trackConnection(root.DescendantRemoving, function()
			scheduleRender()
		end, shipDataConnections)
	end

	local watchedRoots = {
		IncomeBrainrots = true,
		Inventory = true,
		Ship = true,
		leaderstats = true,
		Materials = true,
		UnopenedChests = true,
	}

	for rootName in pairs(watchedRoots) do
		watchRoot(player:FindFirstChild(rootName))
	end

	trackConnection(player.ChildAdded, function(child)
		if watchedRoots[child.Name] then
			task.defer(bindShipDataTracking)
			scheduleRender()
		end
	end, shipDataConnections)

	trackConnection(player.ChildRemoved, function(child)
		if watchedRoots[child.Name] then
			task.defer(bindShipDataTracking)
			scheduleRender()
		end
	end, shipDataConnections)
end

local function render()
	local data = buildRenderData()

	root:render(ReactRoblox.createPortal(React.createElement(App, {
		isOpen = uiState.isOpen,
		activeView = data.activeView,
		activeCategory = uiState.activeCategory,
		activeCategoryLabel = data.activeCategoryLabel,
		categories = data.categories,
		items = data.items,
		captainLog = data.captainLog,
		hotbarSlots = data.hotbarSlots,
		summary = data.summary,
		filteredCount = data.filteredCount,
		totalCount = data.totalCount,
		query = data.query,
		toggleLayout = getToggleLayout(),
		toggleIcon = getLegacyInventoryIcon(),
		onToggle = function()
			uiState.isOpen = not uiState.isOpen
			render()
		end,
		onSelectView = function(viewKey)
			uiState.activeView = viewKey
			uiState.query = ""
			render()
		end,
		onSelectCategory = function(categoryKey)
			uiState.activeCategory = categoryKey
			render()
		end,
		onQueryChanged = function(nextQuery)
			uiState.query = nextQuery
			render()
		end,
		onActivateItem = function(entry)
			if entry and entry.kind ~= "Resource" then
				equipRemote:FireServer(entry.kind, entry.name)
			end
		end,
	}), playerGui))
end

scheduleRender = function()
	if renderQueued or destroyed then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if not destroyed then
			render()
		end
	end)
end

local function syncResourcesFromState(state)
	local foodInventory = state and state.FoodInventory or {}
	local materials = state and state.Materials or {}

	for foodKey in pairs(Economy.Food) do
		local quantity = math.max(0, tonumber(foodInventory[foodKey]) or 0)
		local key = "Resource|" .. foodKey
		if quantity > 0 then
			itemState[key] = {
				kind = "Resource",
				name = foodKey,
				qty = quantity,
				resourceType = "Food",
			}
		else
			itemState[key] = nil
		end
	end

	local timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0)
	local iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0)
	local ancient = math.max(0, tonumber(materials.AncientTimber) or 0)

	local materialValues = {
		Timber = timber,
		Iron = iron,
		AncientTimber = ancient,
	}

	for materialKey, quantity in pairs(materialValues) do
		local key = "Resource|" .. materialKey
		if quantity > 0 then
			itemState[key] = {
				kind = "Resource",
				name = materialKey,
				qty = quantity,
				resourceType = "Material",
			}
		else
			itemState[key] = nil
		end
	end
end

syncDevilFruitsFromInventory = function()
	local inventoryFolder = player:FindFirstChild("Inventory")
	local devilFruitsFolder = inventoryFolder and inventoryFolder:FindFirstChild("DevilFruits")
	if not devilFruitsFolder then
		return
	end

	local seenFruitKeys = {}

	for _, fruitFolder in ipairs(devilFruitsFolder:GetChildren()) do
		if fruitFolder:IsA("Folder") then
			local fruit = DevilFruits.GetFruit(fruitFolder.Name)
			if fruit then
				local quantity = math.max(0, tonumber(readChildValue(fruitFolder, "Quantity")) or 0)
				local key = "DevilFruit|" .. fruit.FruitKey
				seenFruitKeys[key] = true

				if quantity > 0 then
					ensureAcquired(key)
					itemState[key] = {
						kind = "DevilFruit",
						name = fruit.FruitKey,
						qty = quantity,
					}
				else
					itemState[key] = nil
				end
			end
		end
	end

	for key, state in pairs(itemState) do
		if state.kind == "DevilFruit" and not seenFruitKeys[key] then
			itemState[key] = nil
		end
	end
end

local function activateSlot(slotNumber)
	local entry = keyboardHotbar[slotNumber]
	if entry then
		equipRemote:FireServer(entry.kind, entry.name)
	end
end

local function scanEquipped(character)
	local nextEquipped = nil
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			nextEquipped = child.Name
			break
		end
	end
	equippedName = nextEquipped
	scheduleRender()
end

local function hookCharacter(character)
	disconnectAll(characterConnections)
	scanEquipped(character)

	trackConnection(character.ChildAdded, function(child)
		if child:IsA("Tool") then
			equippedName = child.Name
			scheduleRender()
		end
	end, characterConnections)

	trackConnection(character.ChildRemoved, function(child)
		if child:IsA("Tool") and equippedName == child.Name then
			scanEquipped(character)
		end
	end, characterConnections)
end

trackConnection(updateRemote.OnClientEvent, function(kind, name, value)
	if kind == "Brainrot" then
		local quantity = tonumber(value) or 0
		local key = "Brainrot|" .. tostring(name)
		if quantity > 0 then
			ensureAcquired(key)
			itemState[key] = {
				kind = "Brainrot",
				name = name,
				qty = quantity,
			}
		else
			itemState[key] = nil
		end
	elseif kind == "Gear" then
		local key = "Gear|" .. tostring(name)
		if value == true then
			ensureAcquired(key)
			itemState[key] = {
				kind = "Gear",
				name = name,
				owned = true,
			}
		else
			itemState[key] = nil
		end
	elseif kind == "DevilFruit" then
		local fruit = DevilFruits.GetFruit(name)
		if fruit then
			local quantity = tonumber(value) or 0
			local key = "DevilFruit|" .. fruit.FruitKey
			if quantity > 0 then
				ensureAcquired(key)
				itemState[key] = {
					kind = "DevilFruit",
					name = fruit.FruitKey,
					qty = quantity,
				}
			else
				itemState[key] = nil
			end
		end
	elseif kind == "Chest" then
		local quantity = tonumber(value) or 0
		local key = "Chest|" .. tostring(name)
		if quantity > 0 then
			ensureAcquired(key)
			itemState[key] = {
				kind = "Chest",
				name = name,
				qty = quantity,
			}
		else
			itemState[key] = nil
		end
	end

	scheduleRender()
end, cleanupConnections)

stopObservingState = MetaClient.ObserveState(function(state)
	metaState = state
	syncResourcesFromState(state)
	scheduleRender()
end)

trackConnection(UserInputService.InputBegan, function(input, gameProcessed)
	if gameProcessed or UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.Backquote or input.KeyCode == Enum.KeyCode.F then
		uiState.isOpen = not uiState.isOpen
		scheduleRender()
		return
	end

	local slotNumber = KEY_TO_SLOT[input.KeyCode]
	if slotNumber ~= nil then
		activateSlot(slotNumber)
	end
end, cleanupConnections)

trackConnection(playerGui.DescendantAdded, function()
	task.defer(hideLegacyInventory)
	task.defer(bindHudLayoutTracking)
	scheduleRender()
end, cleanupConnections)

trackConnection(playerGui.DescendantRemoving, function()
	task.defer(bindHudLayoutTracking)
	scheduleRender()
end, cleanupConnections)

local currentCamera = workspace.CurrentCamera
if currentCamera then
	trackConnection(currentCamera:GetPropertyChangedSignal("ViewportSize"), function()
		scheduleRender()
	end, cleanupConnections)
end

trackConnection(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
	scheduleRender()
end, cleanupConnections)

trackConnection(RunService.Heartbeat, function()
	local signature = getToggleLayoutSignature()
	if signature ~= lastToggleLayoutSignature then
		lastToggleLayoutSignature = signature
		scheduleRender()
	end
end, cleanupConnections)

if player.Character then
	hookCharacter(player.Character)
end

trackConnection(player.CharacterAdded, hookCharacter, cleanupConnections)

hideLegacyInventory()
bindHudLayoutTracking()
bindShipDataTracking()
render()
task.defer(scheduleRender)

script.Destroying:Connect(function()
	destroyed = true
	disconnectAll(cleanupConnections)
	disconnectAll(characterConnections)
	disconnectAll(hudLayoutConnections)
	disconnectAll(shipDataConnections)
	if stopObservingState then
		stopObservingState()
		stopObservingState = nil
	end
	root:unmount()
end)
