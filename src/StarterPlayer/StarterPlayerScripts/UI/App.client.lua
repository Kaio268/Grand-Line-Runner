local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
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
local Titles = require(Modules:WaitForChild("Configs"):WaitForChild("Titles"))
local Economy = require(Modules:WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local PlotUpgradeConfig = require(Modules:WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local RebirthConfig = require(Modules:WaitForChild("Configs"):WaitForChild("Rebirths"))
local MetaClient = require(Modules:WaitForChild("GrandLineRushMetaClient"))
local BountyResolver = require(Modules:WaitForChild("GrandLineRushBountyResolver"))
local UiModalState = require(Modules:WaitForChild("UiModalState"))

local updateRemote = ReplicatedStorage:WaitForChild("InventoryGearRemote")
local equipRemote = ReplicatedStorage:WaitForChild("EquipToggleRemote")
local titleEquipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("TitleEquipRequest")
local shipUpgradeResultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ShipUpgradeResultRemote")

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

local RESOURCE_RARITY = {
	Apple = "Common",
	Rice = "Common",
	Meat = "Rare",
	SeaBeastMeat = "Legendary",
	Timber = "Common",
	Iron = "Rare",
	AncientTimber = "Legendary",
}

local RESOURCE_RARITY_COLORS = {
	Common = Color3.fromRGB(112, 220, 140),
	Rare = Color3.fromRGB(91, 170, 255),
	Legendary = Color3.fromRGB(255, 187, 74),
}

local function getStandLevelMultiplier(level)
	local safeLevel = math.clamp(math.floor(tonumber(level) or 1), 1, 50)
	return 1 + ((safeLevel - 1) * 0.25)
end

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
local cachedLegacyInventoryIcon = nil
local shipUpgradeModal = nil
local MODAL_INPUT_SINK_ACTION = "ReactShipUpgradeModalInputSink"
local MODAL_BLOCKED_INPUTS = {
	Enum.UserInputType.MouseButton1,
	Enum.UserInputType.MouseButton2,
	Enum.UserInputType.MouseWheel,
	Enum.UserInputType.Touch,
	Enum.KeyCode.E,
	Enum.KeyCode.F,
	Enum.KeyCode.Backquote,
	Enum.KeyCode.One,
	Enum.KeyCode.Two,
	Enum.KeyCode.Three,
	Enum.KeyCode.Four,
	Enum.KeyCode.Five,
	Enum.KeyCode.Six,
	Enum.KeyCode.Seven,
	Enum.KeyCode.Eight,
	Enum.KeyCode.Nine,
	Enum.KeyCode.Zero,
	Enum.KeyCode.ButtonA,
	Enum.KeyCode.ButtonB,
	Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY,
}
local modalInputSinkBound = false

local function sinkModalInput()
	return Enum.ContextActionResult.Sink
end

local function updateModalInputCapture()
	local modalOpen = shipUpgradeModal ~= nil
	if modalOpen and not modalInputSinkBound then
		ContextActionService:BindActionAtPriority(
			MODAL_INPUT_SINK_ACTION,
			sinkModalInput,
			false,
			Enum.ContextActionPriority.High.Value,
			table.unpack(MODAL_BLOCKED_INPUTS)
		)
		modalInputSinkBound = true
	elseif (not modalOpen) and modalInputSinkBound then
		ContextActionService:UnbindAction(MODAL_INPUT_SINK_ACTION)
		modalInputSinkBound = false
	end
end

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
local rebirthSummaryConnections = {}
local titleAttributeConnections = {}

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
		tostring(entry.description or ""),
		tostring(entry.requirementText or ""),
		tostring(entry.stateText or ""),
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
	local number = tonumber(value) or 0
	local sign = number < 0 and "-" or ""
	local absValue = math.abs(number)

	local suffixes = {
		{ value = 1e18, suffix = "Qui" },
		{ value = 1e15, suffix = "Qd" },
		{ value = 1e12, suffix = "T" },
		{ value = 1e9, suffix = "B" },
		{ value = 1e6, suffix = "M" },
		{ value = 1e3, suffix = "K" },
	}

	for _, entry in ipairs(suffixes) do
		if absValue >= entry.value then
			local scaled = absValue / entry.value
			local decimals = if scaled >= 100 then 0 elseif scaled >= 10 then 1 else 2
			local text = string.format("%." .. tostring(decimals) .. "f", scaled)
			text = text:gsub("%.?0+$", "")
			return sign .. text .. entry.suffix
		end
	end

	return sign .. tostring(math.floor(absValue + 0.5))
end

local function formatMultiplier(value)
	local rounded = math.floor((tonumber(value) or 1) * 100 + 0.5) / 100
	return string.format("%.2fx", rounded)
end

local function ensureAcquired(key)
	if not acquisition[key] then
		acquisitionCounter += 1
		acquisition[key] = acquisitionCounter
	end
end

local function getResourceInfo(resourceKey)
	local food = Economy.Food[resourceKey]
	local rarity = RESOURCE_RARITY[resourceKey] or "Common"
	if food then
		return {
			displayName = tostring(food.DisplayName or resourceKey),
			subtitle = "Food",
			rarity = rarity,
		}
	end

	return {
		displayName = RESOURCE_DISPLAY[resourceKey] or tostring(resourceKey),
		subtitle = "Material",
		rarity = rarity,
	}
end

local function getRarityLabel(kind, name)
	if kind == "Chest" then
		return tostring(name)
	end

	if kind == "Resource" then
		local info = getResourceInfo(name)
		return tostring(info.rarity or "Common")
	end

	if kind == "DevilFruit" then
		local fruit = DevilFruits.GetFruit(name)
		return fruit and tostring(fruit.Rarity or "") or ""
	end

	if kind == "Brainrot" then
		local brainrot = Brainrots[name]
		return brainrot and tostring(brainrot.Rarity or "") or ""
	end

	if kind == "Gear" then
		local gear = Gears[name]
		return gear and tostring(gear.Type or "Gear") or "Gear"
	end

	return ""
end

local function getItemSortRank(kind, name)
	if kind == "Brainrot" or kind == "DevilFruit" then
		return RARITY_ORDER[getRarityLabel(kind, name)] or 0
	end

	if kind == "Chest" then
		return CHEST_ORDER[tostring(name)] or 0
	end

	if kind == "Resource" then
		local rarityRank = RARITY_ORDER[getRarityLabel(kind, name)] or 0
		local resourceRank = RESOURCE_ORDER[tostring(name)] or 0
		return (rarityRank * 100) + resourceRank
	end

	if kind == "Gear" then
		local gear = Gears[name]
		return math.max(0, tonumber(gear and gear.Price) or 0)
	end

	return 0
end

local function getBrainrotLevelForStand(standName)
	local standsLevels = player:FindFirstChild("StandsLevels")
	local levelValue = standsLevels and standsLevels:FindFirstChild(tostring(standName))
	return math.max(1, math.floor(tonumber(levelValue and levelValue.Value) or 1))
end

local function getClientShipUpgradeLevel()
	local hiddenLeaderstats = player:FindFirstChild("HiddenLeaderstats")
	local plotUpgradeValue = hiddenLeaderstats and hiddenLeaderstats:FindFirstChild("PlotUpgrade")
	local rawLevel = plotUpgradeValue and plotUpgradeValue:IsA("ValueBase") and plotUpgradeValue.Value or 0

	if PlotUpgradeConfig and PlotUpgradeConfig.ClampLevel then
		return PlotUpgradeConfig.ClampLevel(rawLevel)
	end

	return math.max(0, math.floor(tonumber(rawLevel) or 0))
end

local function getBrainrotIncomePerTick(standName, brainrotName)
	local info = Brainrots[brainrotName]
	local baseIncome = tonumber(info and info.Income) or 0
	if baseIncome <= 0 then
		return 0
	end

	local level = getBrainrotLevelForStand(standName)
	local levelMultiplier = getStandLevelMultiplier(level)
	local shipUpgradeLevel = getClientShipUpgradeLevel()
	local slotMultiplier = 1
	if PlotUpgradeConfig and PlotUpgradeConfig.GetSlotBonusMultiplier then
		slotMultiplier = tonumber(PlotUpgradeConfig.GetSlotBonusMultiplier(shipUpgradeLevel, tostring(standName))) or 1
	end

	return math.max(0, baseIncome * levelMultiplier * slotMultiplier)
end

local function getItemDisplayName(kind, name)
	if kind == "Chest" then
		return string.format("%s Chest", tostring(name or "Chest"))
	end

	if kind == "Resource" then
		local info = getResourceInfo(name)
		return tostring(info.displayName or name or "Resource")
	end

	if kind == "DevilFruit" then
		local fruit = DevilFruits.GetFruit(name)
		if fruit and fruit.DisplayName then
			return tostring(fruit.DisplayName)
		end
		return tostring(name or "Devil Fruit")
	end

	if kind == "Brainrot" then
		local brainrot = Brainrots[name]
		if brainrot and brainrot.DisplayName then
			return tostring(brainrot.DisplayName)
		end
		return tostring(name or "Brainrot")
	end

	if kind == "Gear" then
		local gear = Gears[name]
		if gear and gear.DisplayName then
			return tostring(gear.DisplayName)
		end
		return tostring(name or "Gear")
	end

	return tostring(name or kind or "Unknown Item")
end

local function compareInventoryKeys(a, b)
	local stateA = itemState[a]
	local stateB = itemState[b]
	if not stateA or not stateB then
		return tostring(a) < tostring(b)
	end

	local rankA = getItemSortRank(stateA.kind, stateA.name)
	local rankB = getItemSortRank(stateB.kind, stateB.name)
	if rankA ~= rankB then
		return rankA > rankB
	end

	if stateA.kind == stateB.kind and stateA.kind == "Brainrot" then
		local nameA = string.lower(tostring(getItemDisplayName(stateA.kind, stateA.name) or ""))
		local nameB = string.lower(tostring(getItemDisplayName(stateB.kind, stateB.name) or ""))
		if nameA ~= nameB then
			return nameA < nameB
		end
	end

	if stateA.kind == stateB.kind then
		if stateA.kind == "Resource" then
			local resourceOrderA = RESOURCE_ORDER[tostring(stateA.name)] or 0
			local resourceOrderB = RESOURCE_ORDER[tostring(stateB.name)] or 0
			if resourceOrderA ~= resourceOrderB then
				return resourceOrderA > resourceOrderB
			end
		elseif stateA.kind == "Chest" then
			local chestOrderA = CHEST_ORDER[tostring(stateA.name)] or 0
			local chestOrderB = CHEST_ORDER[tostring(stateB.name)] or 0
			if chestOrderA ~= chestOrderB then
				return chestOrderA > chestOrderB
			end
		end
	end

	local quantityA = tonumber(stateA.qty) or (stateA.owned and 1 or 0)
	local quantityB = tonumber(stateB.qty) or (stateB.owned and 1 or 0)
	if quantityA ~= quantityB then
		return quantityA > quantityB
	end

	local displayA = string.lower(tostring(getItemDisplayName(stateA.kind, stateA.name) or ""))
	local displayB = string.lower(tostring(getItemDisplayName(stateB.kind, stateB.name) or ""))
	if displayA ~= displayB then
		return displayA < displayB
	end

	local acquireA = acquisition[a] or math.huge
	local acquireB = acquisition[b] or math.huge
	if acquireA ~= acquireB then
		return acquireA < acquireB
	end

	return tostring(a) < tostring(b)
end

local function countUsableSlotsForFloor(level, floorName, rebirths)
	local floorRange = PlotUpgradeConfig.StandFloorRanges[tostring(floorName)]
	if typeof(floorRange) ~= "table" then
		return 0
	end

	local startStand = tonumber(floorRange[1]) or 0
	local endStand = tonumber(floorRange[2]) or -1
	local total = 0

	for standNumber = startStand, endStand do
		if PlotUpgradeConfig.IsStandUsable(level, tostring(standNumber), rebirths) then
			total += 1
		end
	end

	return total
end

local function formatBonusPercent(multiplier)
	local percent = math.floor(((tonumber(multiplier) or 1) - 1) * 100 + 0.5)
	return string.format("+%d%%", percent)
end

local function buildShipUpgradeGainLines(level, description, isMaxLevel)
	local lines = {}
	local seen = {}
	local previousLevel = math.max(0, PlotUpgradeConfig.ClampLevel(level) - 1)
	local rebirths = 0
	local leaderstats = player:FindFirstChild("leaderstats")
	local rebirthValue = leaderstats and leaderstats:FindFirstChild("Rebirths")
	if rebirthValue and rebirthValue:IsA("ValueBase") then
		rebirths = math.max(0, math.floor(tonumber(rebirthValue.Value) or 0))
	end

	local function pushLine(text, key)
		local value = trim(text)
		local dedupeKey = tostring(key or value)
		if value == "" or seen[dedupeKey] then
			return
		end
		seen[dedupeKey] = true
		lines[#lines + 1] = value
	end

	for _, floorName in ipairs({ "Floor1", "Floor2", "Floor3" }) do
		local wasUnlocked = PlotUpgradeConfig.IsFloorUnlocked(previousLevel, floorName, rebirths)
		local isUnlocked = PlotUpgradeConfig.IsFloorUnlocked(level, floorName, rebirths)
		local previousCount = countUsableSlotsForFloor(previousLevel, floorName, rebirths)
		local currentCount = countUsableSlotsForFloor(level, floorName, rebirths)
		local floorLabel = string.gsub(floorName, "Floor", "Floor ")

		if (not wasUnlocked) and isUnlocked then
			pushLine(string.format("Unlocked %s", floorLabel), floorName .. ":unlock")
		end

		if currentCount > previousCount then
			pushLine(string.format("%s now supports %d usable slots", floorLabel, currentCount), floorName .. ":slots")
		end
	end

	local bonusEntries = {}
	for standName, bonusInfo in pairs(PlotUpgradeConfig.SlotBonuses) do
		bonusEntries[#bonusEntries + 1] = {
			standName = standName,
			info = bonusInfo,
		}
	end

	table.sort(bonusEntries, function(a, b)
		local unlockA = tonumber(a.info.UnlockLevel) or math.huge
		local unlockB = tonumber(b.info.UnlockLevel) or math.huge
		if unlockA == unlockB then
			return tostring(a.standName) < tostring(b.standName)
		end
		return unlockA < unlockB
	end)

	for _, entry in ipairs(bonusEntries) do
		local bonusInfo = entry.info
		if tonumber(bonusInfo.UnlockLevel) == level then
			pushLine(string.format(
				"%s unlocked on Floor %d Slot %d (%s income)",
				tostring(bonusInfo.Label or "Bonus Slot"),
				tonumber(bonusInfo.Floor) or 1,
				tonumber(bonusInfo.Slot) or 1,
				formatBonusPercent(bonusInfo.Multiplier)
			), tostring(entry.standName) .. ":bonus")
		end
	end

	if isMaxLevel then
		pushLine("Ship frame reinforced to maximum level", "max")
	end

	if #lines == 0 then
		pushLine(description ~= "" and description or "Ship upgraded successfully", "fallback")
	end

	return lines
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
		local rarity = getResourceInfo(name).rarity
		return RESOURCE_RARITY_COLORS[rarity] or RESOURCE_RARITY_COLORS.Common
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

local function readPlayerRebirths()
	local leaderstats = player:FindFirstChild("leaderstats")
	local value = readChildValue(leaderstats, "Rebirths")
	if typeof(value) == "number" then
		return math.max(0, math.floor(value))
	end

	return 0
end

local function readPlayerBountySummary()
	local leaderstats = player:FindFirstChild("leaderstats")
	local bountyFolder = player:FindFirstChild("Bounty")
	local metaBounty = metaState and metaState.Bounty or {}

	local crewBounty = math.max(
		0,
		math.floor(
			tonumber(readChildValue(bountyFolder, "Crew"))
				or tonumber(metaBounty.Crew)
				or 0
		)
	)
	local extractionBounty = math.max(
		0,
		math.floor(
			tonumber(readChildValue(bountyFolder, "LifetimeExtraction"))
				or tonumber(metaBounty.LifetimeExtraction)
				or 0
		)
	)
	local totalBounty = math.max(
		0,
		math.floor(
			tonumber(readChildValue(leaderstats, "Bounty"))
				or tonumber(readChildValue(bountyFolder, "Total"))
				or tonumber(metaBounty.Total)
				or (crewBounty + extractionBounty)
		)
	)

	return {
		total = totalBounty,
		crew = crewBounty,
		extraction = extractionBounty,
	}
end

local function readPlayerShipIncomeMultiplier(rebirths)
	local multiplier = RebirthConfig.GetShipIncomeMultiplier(rebirths)
	if typeof(multiplier) == "number" then
		return multiplier
	end

	return 1
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

local function readPersistentTitleUnlocked(titleId)
	local titlesFolder = player:FindFirstChild("Titles")
	local unlockedFolder = titlesFolder and titlesFolder:FindFirstChild("Unlocked")
	local valueObject = unlockedFolder and unlockedFolder:FindFirstChild(titleId)
	return valueObject ~= nil and valueObject:IsA("BoolValue") and valueObject.Value == true
end

local function readEquippedTitleId()
	local titlesFolder = player:FindFirstChild("Titles")
	local equippedValue = titlesFolder and titlesFolder:FindFirstChild("Equipped")
	if equippedValue and equippedValue:IsA("StringValue") then
		local equippedTitleId = trim(equippedValue.Value)
		if equippedTitleId ~= "" then
			return equippedTitleId
		end
	end

	local equippedAttribute = player:GetAttribute("EquippedTitleId")
	if typeof(equippedAttribute) == "string" and trim(equippedAttribute) ~= "" then
		return trim(equippedAttribute)
	end

	return nil
end

local function readDynamicTitleStatus(titleDefinition, trackedValue)
	if typeof(titleDefinition) ~= "table" then
		return {
			unlocked = false,
			currentRank = nil,
			rankLabel = "Unknown",
			statusKey = "Unknown",
			visibleLimit = 0,
		}
	end

	local rankAttribute = titleDefinition.RankAttribute
	if typeof(rankAttribute) ~= "string" or rankAttribute == "" then
		return {
			unlocked = false,
			currentRank = nil,
			rankLabel = "Unknown",
			statusKey = "Unknown",
			visibleLimit = 0,
		}
	end

	local requiredRank = math.max(1, math.floor(tonumber(titleDefinition.RequiredRank) or 1))
	local currentRank = tonumber(player:GetAttribute(rankAttribute))
	local visibleLimit = math.max(1, math.floor(tonumber(player:GetAttribute(rankAttribute .. "_VisibleLimit")) or 100))
	local visibleCount = math.max(0, math.floor(tonumber(player:GetAttribute(rankAttribute .. "_VisibleCount")) or 0))
	local boardReady = player:GetAttribute(rankAttribute .. "_Ready") == true

	if currentRank ~= nil and currentRank >= 1 then
		return {
			unlocked = currentRank <= requiredRank,
			currentRank = currentRank,
			rankLabel = "#" .. tostring(math.floor(currentRank + 0.5)),
			statusKey = "Ranked",
			visibleLimit = visibleLimit,
		}
	end

	if math.max(0, tonumber(trackedValue) or 0) <= 0 then
		return {
			unlocked = false,
			currentRank = nil,
			rankLabel = "No Bounty Yet",
			statusKey = "NoBounty",
			visibleLimit = visibleLimit,
		}
	end

	if boardReady then
		if visibleCount < visibleLimit then
			return {
				unlocked = false,
				currentRank = nil,
				rankLabel = "Board Updating...",
				statusKey = "PendingBoard",
				visibleLimit = visibleLimit,
			}
		end

		return {
			unlocked = false,
			currentRank = nil,
			rankLabel = string.format("Outside Top %d", visibleLimit),
			statusKey = "OutsideTopBoard",
			visibleLimit = visibleLimit,
		}
	end

	return {
		unlocked = false,
		currentRank = nil,
		rankLabel = "Checking Board...",
		statusKey = "PendingBoard",
		visibleLimit = visibleLimit,
	}
end

local function blendColor(a, b, t)
	return Color3.new(
		a.R + (b.R - a.R) * t,
		a.G + (b.G - a.G) * t,
		a.B + (b.B - a.B) * t
	)
end

local function resolveTitleVisualStyle(titleDefinition, unlocked)
	local visualStyle = typeof(titleDefinition.VisualStyle) == "table" and titleDefinition.VisualStyle or {}
	local neutralAccent = Color3.fromRGB(97, 114, 146)
	local neutralSurfaceTop = Color3.fromRGB(16, 22, 35)
	local neutralSurfaceBottom = Color3.fromRGB(10, 15, 25)
	local neutralSeal = Color3.fromRGB(56, 67, 90)
	local accentColor = visualStyle.AccentColor or Color3.fromRGB(112, 214, 255)
	local surfaceColor = visualStyle.SurfaceColor or neutralSurfaceTop
	local surfaceColor2 = visualStyle.SurfaceColor2 or neutralSurfaceBottom
	local sealColor = visualStyle.SealColor or accentColor
	local ledgerColor = visualStyle.LedgerColor or accentColor

	if unlocked then
		return {
			accentColor = accentColor,
			surfaceColor = surfaceColor,
			surfaceColor2 = surfaceColor2,
			sealColor = sealColor,
			ledgerColor = ledgerColor,
		}
	end

	return {
		accentColor = blendColor(accentColor, neutralAccent, 0.55),
		surfaceColor = blendColor(surfaceColor, neutralSurfaceTop, 0.52),
		surfaceColor2 = blendColor(surfaceColor2, neutralSurfaceBottom, 0.4),
		sealColor = blendColor(sealColor, neutralSeal, 0.55),
		ledgerColor = blendColor(ledgerColor, neutralAccent, 0.35),
	}
end

local function buildTitlesData(query)
	local entries = {}
	local totalCount = 0
	local unlockedCount = 0
	local persistentUnlockedCount = 0
	local dynamicUnlockedCount = 0
	local bountySummary = readPlayerBountySummary()
	local equippedTitleId = readEquippedTitleId()
	local equippedTitleLabel = "None"
	local equippedTitleColor = nil
	local bountyRankLabel = "Checking Board..."
	local bountyRankValue = nil
	local bountyRankStatus = "PendingBoard"

	for _, titleDefinition in ipairs(Titles.GetAll()) do
		totalCount += 1

		local persistentUnlocked = titleDefinition.UnlockType == "Persistent"
			and readPersistentTitleUnlocked(titleDefinition.Id)
			or false
		local dynamicUnlocked = false
		local currentRank = nil
		local rankLabel = nil
		local rankStatusKey = nil
		if titleDefinition.UnlockType == "DynamicRank" then
			local dynamicStatus = readDynamicTitleStatus(titleDefinition, bountySummary.total)
			dynamicUnlocked = dynamicStatus.unlocked == true
			currentRank = dynamicStatus.currentRank
			rankLabel = dynamicStatus.rankLabel
			rankStatusKey = dynamicStatus.statusKey
		end

		local unlocked = persistentUnlocked or dynamicUnlocked
		local visualStyle = resolveTitleVisualStyle(titleDefinition, unlocked)
		if persistentUnlocked then
			persistentUnlockedCount += 1
		end
		if dynamicUnlocked then
			dynamicUnlockedCount += 1
		end
		if unlocked then
			unlockedCount += 1
		end

		local isEquipped = equippedTitleId ~= nil and equippedTitleId == titleDefinition.Id
		if isEquipped then
			equippedTitleLabel = tostring(titleDefinition.DisplayName or titleDefinition.Id)
			equippedTitleColor = visualStyle.ledgerColor
		end

		local entry = {
			key = tostring(titleDefinition.Id or totalCount),
			titleId = tostring(titleDefinition.Id or ""),
			displayName = tostring(titleDefinition.DisplayName or titleDefinition.Id or "Title"),
			subtitle = titleDefinition.UnlockType == "DynamicRank" and "Leaderboard Title" or "Persistent Title",
			footer = tostring(titleDefinition.RequirementText or ""),
			description = tostring(titleDefinition.Description or ""),
			requirementText = tostring(titleDefinition.RequirementText or ""),
			stateText = isEquipped and "Equipped" or (unlocked and "Unlocked" or "Locked"),
			unlocked = unlocked,
			persistentUnlocked = persistentUnlocked,
			dynamicUnlocked = dynamicUnlocked,
			isEquipped = isEquipped,
			actionLabel = isEquipped and "Unequip" or (unlocked and "Equip" or nil),
			canToggleEquipped = isEquipped or unlocked,
			currentRank = currentRank,
			rankLabel = rankLabel,
			rankStatusKey = rankStatusKey,
			accentColor = visualStyle.accentColor,
			surfaceColor = visualStyle.surfaceColor,
			surfaceColor2 = visualStyle.surfaceColor2,
			sealColor = visualStyle.sealColor,
			stateColor = visualStyle.accentColor,
		}

		if titleDefinition.Id == "PirateEmperor" then
			bountyRankValue = currentRank
			bountyRankLabel = rankLabel or bountyRankLabel
			bountyRankStatus = rankStatusKey or bountyRankStatus
		end

		if matchesQuery(entry, query) then
			entries[#entries + 1] = entry
		end
	end

	return {
		entries = entries,
		filteredCount = #entries,
		totalCount = totalCount,
		unlockedCount = unlockedCount,
		lockedCount = math.max(0, totalCount - unlockedCount),
		persistentUnlockedCount = persistentUnlockedCount,
		dynamicUnlockedCount = dynamicUnlockedCount,
		equippedTitleId = equippedTitleId,
		equippedTitleLabel = equippedTitleLabel,
		equippedTitleColor = equippedTitleColor,
		bountyRank = bountyRankValue,
		bountyRankLabel = bountyRankLabel,
		bountyRankStatus = bountyRankStatus,
		bountyTotal = bountySummary.total,
	}
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
		local ok, entry, collectable = pcall(function()
			local slotFolder = slotsFolder and slotsFolder:FindFirstChild(standName)
			local standIncomeFolder = incomeFolder and incomeFolder:FindFirstChild(standName)
			local brainrotName = tostring(readChildValue(slotFolder, "BrainrotName") or readChildValue(standIncomeFolder, "BrainrotName") or "")

			if brainrotName == "" then
				return nil, 0
			end

			local standLevel = getBrainrotLevelForStand(standName)
			local incomePerTick = getBrainrotIncomePerTick(standName, brainrotName)
			local incomeToCollect = math.max(0, tonumber(readChildValue(standIncomeFolder, "IncomeToCollect")) or 0)
			local subtitle = getSubtitle("Brainrot", brainrotName)
			local displayName = getDisplayName("Brainrot", brainrotName)
			local bounty = math.max(0, BountyResolver.ResolveBrainrotBounty({
				StorageName = brainrotName,
				Level = standLevel,
			}))

			local nextEntry = {
				key = standName,
				standName = standName,
				brainrotName = brainrotName,
				displayName = displayName,
				subtitle = subtitle,
				footer = string.format("%s  |  %s D ready", standName, formatNumber(incomeToCollect)),
				image = getIcon("Brainrot", brainrotName),
				fallbackText = string.sub(string.upper(displayName), 1, 2),
				accentColor = getAccentColor("Brainrot", brainrotName),
				level = standLevel,
				bounty = bounty,
				incomePerTick = incomePerTick,
				collectable = incomeToCollect,
			}

			return nextEntry, incomeToCollect
		end)

		if ok and entry then
			totalPlaced += 1
			totalCollectable += collectable or 0
			if matchesQuery(entry, query) then
				entries[#entries + 1] = entry
			end
		end
	end

	table.sort(entries, function(a, b)
		local rankA = RARITY_ORDER[tostring(a.subtitle or "")] or 0
		local rankB = RARITY_ORDER[tostring(b.subtitle or "")] or 0
		if rankA ~= rankB then
			return rankA > rankB
		end
		local nameA = string.lower(tostring(a.displayName or ""))
		local nameB = string.lower(tostring(b.displayName or ""))
		if nameA ~= nameB then
			return nameA < nameB
		end
		if (a.level or 0) ~= (b.level or 0) then
			return (a.level or 0) > (b.level or 0)
		end
		if a.collectable ~= b.collectable then
			return (a.collectable or 0) > (b.collectable or 0)
		end
		if a.incomePerTick ~= b.incomePerTick then
			return (a.incomePerTick or 0) > (b.incomePerTick or 0)
		end
		return tostring(a.standName) < tostring(b.standName)
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
		return compareInventoryKeys(a, b)
	end)

	table.sort(chestsList, function(a, b)
		return compareInventoryKeys(a, b)
	end)

	table.sort(brainrotsList, function(a, b)
		return compareInventoryKeys(a, b)
	end)

	table.sort(devilFruitList, function(a, b)
		return compareInventoryKeys(a, b)
	end)

	table.sort(resourceList, function(a, b)
		return compareInventoryKeys(a, b)
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
	local liveRebirths = readPlayerRebirths()
	local liveMultiplier = readPlayerShipIncomeMultiplier(liveRebirths)
	local chestCount = readPlayerChestCount(chestsList)
	local bountySummary = readPlayerBountySummary()

	local totalStacks = 0
	for _, state in pairs(itemState) do
		if state.kind ~= "Resource" or (state.qty or 0) > 0 then
			totalStacks += 1
		end
	end

	local captainLogOk, captainLog = pcall(buildCaptainLogData, query)
	if not captainLogOk or typeof(captainLog) ~= "table" then
		captainLog = {
			entries = {},
			filteredCount = 0,
			placedCount = 0,
			totalCollectable = 0,
			totalCount = 0,
		}
	end

	local titlesOk, titles = pcall(buildTitlesData, query)
	if not titlesOk or typeof(titles) ~= "table" then
		titles = {
			entries = {},
			filteredCount = 0,
			totalCount = 0,
			unlockedCount = 0,
			lockedCount = 0,
			persistentUnlockedCount = 0,
			dynamicUnlockedCount = 0,
			bountyRank = nil,
		}
	end

	return {
		hotbarSlots = hotbarSlots,
		items = items,
		categories = categories,
		captainLog = captainLog,
		titles = titles,
		summary = {
			bounty = bountySummary.total,
			crewBounty = bountySummary.crew,
			extractionBounty = bountySummary.extraction,
			doubloons = readPlayerDoubloons(),
			rebirths = liveRebirths,
			multiplier = formatMultiplier(liveMultiplier),
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
		shipUpgradeModal = shipUpgradeModal,
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
		position = UDim2.fromOffset(0, 20),
		size = UDim2.fromOffset(64, 64),
		compact = true,
		dock = "hotbarLeft",
	}
end

local function getLegacyInventoryIcon()
	local hud = playerGui:FindFirstChild("HUD")
	local inventoryGui = hud and hud:FindFirstChild("Inventory")
	local legacyButton = inventoryGui and inventoryGui:FindFirstChild("InventoryBtn", true)
	if not legacyButton then
		return cachedLegacyInventoryIcon
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
		return cachedLegacyInventoryIcon
	end

	cachedLegacyInventoryIcon = {
		image = bestCandidate.Image,
		imageColor3 = bestCandidate.ImageColor3,
		imageRectOffset = bestCandidate.ImageRectOffset,
		imageRectSize = bestCandidate.ImageRectSize,
		scaleType = bestCandidate.ScaleType,
	}

	return cachedLegacyInventoryIcon
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
		Bounty = true,
		IncomeBrainrots = true,
		Inventory = true,
		StandsLevels = true,
		Ship = true,
		Titles = true,
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

local function bindTitleTracking()
	disconnectAll(titleAttributeConnections)

	local watchedAttributes = {}
	for _, titleDefinition in ipairs(Titles.GetAll()) do
		local rankAttribute = titleDefinition.RankAttribute
		if typeof(rankAttribute) == "string" and rankAttribute ~= "" and not watchedAttributes[rankAttribute] then
			watchedAttributes[rankAttribute] = true
			trackConnection(player:GetAttributeChangedSignal(rankAttribute), scheduleRender, titleAttributeConnections)
			trackConnection(player:GetAttributeChangedSignal(rankAttribute .. "_Ready"), scheduleRender, titleAttributeConnections)
			trackConnection(player:GetAttributeChangedSignal(rankAttribute .. "_VisibleLimit"), scheduleRender, titleAttributeConnections)
			trackConnection(player:GetAttributeChangedSignal(rankAttribute .. "_VisibleCount"), scheduleRender, titleAttributeConnections)
		end
	end

	trackConnection(player:GetAttributeChangedSignal("EquippedTitleId"), scheduleRender, titleAttributeConnections)
end

local function bindRebirthSummaryTracking()
	disconnectAll(rebirthSummaryConnections)

	local leaderstats = player:FindFirstChild("leaderstats")
	if not leaderstats then
		return
	end

	local rebirthsValue = leaderstats:FindFirstChild("Rebirths")
	if rebirthsValue and rebirthsValue:IsA("ValueBase") then
		trackConnection(rebirthsValue.Changed, scheduleRender, rebirthSummaryConnections)
	end

	trackConnection(leaderstats.ChildAdded, function(child)
		if child.Name == "Rebirths" then
			task.defer(bindRebirthSummaryTracking)
			scheduleRender()
		end
	end, rebirthSummaryConnections)

	trackConnection(leaderstats.ChildRemoved, function(child)
		if child.Name == "Rebirths" then
			task.defer(bindRebirthSummaryTracking)
			scheduleRender()
		end
	end, rebirthSummaryConnections)
end

local function render()
	local data = buildRenderData()
	UiModalState.SetOpen("InventoryModal", uiState.isOpen or shipUpgradeModal ~= nil)

	root:render(ReactRoblox.createPortal(React.createElement(App, {
		isOpen = uiState.isOpen,
		activeView = data.activeView,
		activeCategory = uiState.activeCategory,
		activeCategoryLabel = data.activeCategoryLabel,
		categories = data.categories,
		items = data.items,
		captainLog = data.captainLog,
		titles = data.titles,
		hotbarSlots = data.hotbarSlots,
		summary = data.summary,
		filteredCount = data.filteredCount,
		totalCount = data.totalCount,
		query = data.query,
		shipUpgradeModal = data.shipUpgradeModal,
		toggleLayout = getToggleLayout(),
		toggleIcon = getLegacyInventoryIcon(),
		onToggle = function()
			if shipUpgradeModal ~= nil then
				return
			end
			uiState.isOpen = not uiState.isOpen
			render()
		end,
		onSelectView = function(viewKey)
			if shipUpgradeModal ~= nil then
				return
			end
			uiState.activeView = viewKey
			uiState.query = ""
			render()
		end,
		onSelectCategory = function(categoryKey)
			if shipUpgradeModal ~= nil then
				return
			end
			uiState.activeCategory = categoryKey
			render()
		end,
		onQueryChanged = function(nextQuery)
			if shipUpgradeModal ~= nil then
				return
			end
			uiState.query = nextQuery
			render()
		end,
		onToggleTitle = function(entry)
			if shipUpgradeModal ~= nil or typeof(entry) ~= "table" then
				return
			end

			local titleId = tostring(entry.titleId or "")
			if titleId == "" then
				return
			end

			titleEquipRemote:FireServer(entry.isEquipped and "" or titleId)
		end,
		onActivateItem = function(entry)
			if shipUpgradeModal ~= nil then
				return
			end
			if entry and entry.kind ~= "Resource" then
				equipRemote:FireServer(entry.kind, entry.name)
			end
		end,
		onDismissShipUpgradeModal = function()
			shipUpgradeModal = nil
			updateModalInputCapture()
			render()
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

trackConnection(shipUpgradeResultRemote.OnClientEvent, function(payload)
	if typeof(payload) ~= "table" then
		return
	end

	if shipUpgradeModal ~= nil then
		return
	end

	if payload.Success == false then
		local lines = {}
		if typeof(payload.Lines) == "table" then
			for _, line in ipairs(payload.Lines) do
				if typeof(line) == "string" and trim(line) ~= "" then
					lines[#lines + 1] = trim(line)
				end
			end
		end
		if #lines == 0 then
			lines = { trim(payload.Message or "You do not meet the requirements for this ship upgrade.") }
		end

		shipUpgradeModal = {
			Title = tostring(payload.Title or "Ship Upgrade Locked"),
			AccentText = tostring(payload.AccentText or "Requirement Not Met"),
			Lines = lines,
			IsError = payload.IsError ~= false,
		}
		updateModalInputCapture()
		scheduleRender()
		return
	end

	local level = PlotUpgradeConfig.ClampLevel(payload.Level)
	local description = trim(payload.Description or PlotUpgradeConfig.GetLevelUnlockDescription(level))
	local isMaxLevel = payload.IsMaxLevel == true
	local gainLines = buildShipUpgradeGainLines(level, description, isMaxLevel)

	shipUpgradeModal = {
		Title = string.format("Ship upgraded to Lv %d", level),
		AccentText = isMaxLevel and "Ship Max Level" or "Ship Upgrade Complete",
		Lines = gainLines,
		IsMaxLevel = isMaxLevel,
	}
	updateModalInputCapture()
	scheduleRender()
end, cleanupConnections)

stopObservingState = MetaClient.ObserveState(function(state)
	metaState = state
	syncResourcesFromState(state)
	scheduleRender()
end)

trackConnection(UserInputService.InputBegan, function(input, gameProcessed)
	if shipUpgradeModal ~= nil or gameProcessed or UserInputService:GetFocusedTextBox() then
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
trackConnection(player.ChildAdded, function(child)
	if child.Name == "leaderstats" then
		task.defer(bindRebirthSummaryTracking)
		scheduleRender()
	end
end, cleanupConnections)
trackConnection(player.ChildRemoved, function(child)
	if child.Name == "leaderstats" then
		task.defer(bindRebirthSummaryTracking)
		scheduleRender()
	end
end, cleanupConnections)

hideLegacyInventory()
bindHudLayoutTracking()
bindShipDataTracking()
bindTitleTracking()
bindRebirthSummaryTracking()
render()
task.defer(scheduleRender)

script.Destroying:Connect(function()
	destroyed = true
	UiModalState.SetOpen("InventoryModal", false)
	if modalInputSinkBound then
		ContextActionService:UnbindAction(MODAL_INPUT_SINK_ACTION)
		modalInputSinkBound = false
	end
	disconnectAll(cleanupConnections)
	disconnectAll(characterConnections)
	disconnectAll(hudLayoutConnections)
	disconnectAll(shipDataConnections)
	disconnectAll(rebirthSummaryConnections)
	if stopObservingState then
		stopObservingState()
		stopObservingState = nil
	end
	root:unmount()
end)
