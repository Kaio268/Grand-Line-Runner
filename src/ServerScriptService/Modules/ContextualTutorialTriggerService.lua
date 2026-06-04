local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local DataManager = require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
local TutorialService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TutorialService"))
local Economy = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushEconomy"))
local MapResolver = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("MapResolver"))
local PlotUpgradeConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("PlotUpgrade"))
local SpawnParts = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("SpawnParts"))

local ContextualTutorialTriggerService = {}

local ACTIVE_MAP_ATTRIBUTE = "ActiveMapName"
local FOREIGN_SHIP_TOUCH_DEBOUNCE_SECONDS = 3
local RARE_CREW_MIN_TIER = tonumber(SpawnParts.RarityTier.Rare) or 3

local started = false
local activeShipsFolder = nil
local activeShipsFolderConnection = nil
local serviceConnections = {}
local shipConnectionsByShip = setmetatable({}, { __mode = "k" })
local foreignShipTouchDebounce = setmetatable({}, { __mode = "k" })
local verticalSliceService = nil
local verticalStateConnection = nil
local crewInstanceService = nil
local warnedRequires = {}

local RARITY_ALIASES = {
	Celestial = "Godly",
	Mythical = "Mythic",
}

local function warnOnce(key, message)
	if warnedRequires[key] then
		return
	end
	warnedRequires[key] = true
	warn(message)
end

local function lazyRequire(moduleName, cacheName)
	local cached
	if cacheName == "verticalSlice" then
		cached = verticalSliceService
	elseif cacheName == "crewInstance" then
		cached = crewInstanceService
	end
	if cached ~= nil then
		return cached
	end

	local modules = ServerScriptService:FindFirstChild("Modules")
	local module = modules and modules:FindFirstChild(moduleName)
	if not module then
		warnOnce(cacheName .. "_missing", string.format("[ContextualTutorialTriggerService] %s is unavailable.", moduleName))
		return nil
	end

	local ok, service = pcall(require, module)
	if not ok then
		warnOnce(
			cacheName .. "_require_failed",
			string.format("[ContextualTutorialTriggerService] Failed to require %s: %s", moduleName, tostring(service))
		)
		return nil
	end

	if cacheName == "verticalSlice" then
		verticalSliceService = service
	elseif cacheName == "crewInstance" then
		crewInstanceService = service
	end

	return service
end

local function getVerticalSliceService()
	return lazyRequire("GrandLineRushVerticalSliceService", "verticalSlice")
end

local function getCrewInstanceService()
	return lazyRequire("CrewInstanceService", "crewInstance")
end

local function dmGet(player, path)
	local value, reason = DataManager:TryGetValue(player, path)
	if reason ~= nil then
		return nil, reason
	end
	return value, nil
end

local function getNumber(player, path)
	local value = dmGet(player, path)
	return math.max(0, tonumber(value) or 0)
end

local function getMaterials(player)
	local materials = dmGet(player, "Materials")
	materials = if typeof(materials) == "table" then materials else {}
	return {
		Timber = math.max(0, tonumber(materials.Timber) or tonumber(materials.CommonShipMaterial) or 0),
		Iron = math.max(0, tonumber(materials.Iron) or tonumber(materials.RareShipMaterial) or 0),
		AncientTimber = math.max(0, tonumber(materials.AncientTimber) or 0),
	}
end

local function hasPositiveGrant(granted)
	if typeof(granted) ~= "table" then
		return false
	end

	for _, amount in pairs(granted) do
		if math.max(0, tonumber(amount) or 0) > 0 then
			return true
		end
	end
	return false
end

local function totalFood(player)
	local foodInventory = dmGet(player, "FoodInventory")
	if typeof(foodInventory) ~= "table" then
		return 0
	end

	local total = 0
	for _, amount in pairs(foodInventory) do
		total += math.max(0, tonumber(amount) or 0)
	end
	return total
end

local function normalizeRarity(rarity)
	local rarityText = tostring(rarity or "")
	return RARITY_ALIASES[rarityText] or rarityText
end

local function getRarityTier(rarity)
	return tonumber(SpawnParts.RarityTier[normalizeRarity(rarity)]) or 1
end

local function enqueue(player, tutorialId, context, options)
	local ok, reason = TutorialService.Enqueue(player, tutorialId, context, options)
	if ok ~= true and reason ~= "already_completed" and reason ~= "already_queued" and reason ~= "already_active" then
		warn(string.format(
			"[ContextualTutorialTriggerService] Failed to enqueue %s for %s: %s",
			tostring(tutorialId),
			player and player.Name or "unknown",
			tostring(reason)
		))
	end
	return ok, reason
end

local function isFirstShipUpgradeAffordable(player)
	if not DataManager:IsReady(player) then
		return false
	end

	local currentLevel = math.max(0, math.floor(getNumber(player, "HiddenLeaderstats.PlotUpgrade")))
	if currentLevel ~= 0 then
		return false
	end

	local requirement = PlotUpgradeConfig.GetRequirementForLevel(currentLevel)
	if typeof(requirement) ~= "table" then
		return false
	end

	local rebirths = math.max(0, math.floor(getNumber(player, "leaderstats.Rebirths")))
	if rebirths < math.max(0, tonumber(requirement.Rebirths) or 0) then
		return false
	end

	local primaryCurrency = Economy.Currency.Primary
	local beli = getNumber(player, "leaderstats." .. tostring(primaryCurrency.Key or "Beli"))
	if beli < math.max(0, tonumber(requirement.Beli) or 0) then
		return false
	end

	local materials = getMaterials(player)
	for materialKey, requiredAmount in pairs(requirement.Materials or {}) do
		if math.max(0, tonumber(materials[materialKey]) or 0) < math.max(0, tonumber(requiredAmount) or 0) then
			return false
		end
	end

	return true
end

local function getPlayerFromHit(hit)
	if typeof(hit) ~= "Instance" then
		return nil
	end

	local character = hit:FindFirstAncestorOfClass("Model")
	if not character then
		return nil
	end

	return Players:GetPlayerFromCharacter(character)
end

local function clearShipConnections(ship)
	local connections = shipConnectionsByShip[ship]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end
	shipConnectionsByShip[ship] = nil
end

local function onForeignShipTouched(ship, hit)
	local player = getPlayerFromHit(hit)
	if not player then
		return
	end

	local ownerUserId = tonumber(ship:GetAttribute("OwnerUserId"))
	if ownerUserId == nil or ownerUserId == player.UserId then
		return
	end

	local now = os.clock()
	local lastTouchAt = foreignShipTouchDebounce[player]
	if lastTouchAt and now - lastTouchAt < FOREIGN_SHIP_TOUCH_DEBOUNCE_SECONDS then
		return
	end
	foreignShipTouchDebounce[player] = now

	enqueue(player, "Raiding", {
		Source = "ForeignShipTouch",
		OwnerUserId = ownerUserId,
	}, nil)
end

local function bindShip(ship)
	if typeof(ship) ~= "Instance" or not ship:IsA("Model") or shipConnectionsByShip[ship] ~= nil then
		return
	end

	local connections = {}
	shipConnectionsByShip[ship] = connections

	local function bindPart(part)
		if not part:IsA("BasePart") then
			return
		end
		connections[#connections + 1] = part.Touched:Connect(function(hit)
			onForeignShipTouched(ship, hit)
		end)
	end

	for _, descendant in ipairs(ship:GetDescendants()) do
		bindPart(descendant)
	end
	connections[#connections + 1] = ship.DescendantAdded:Connect(bindPart)
	connections[#connections + 1] = ship.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			clearShipConnections(ship)
		end
	end)
end

local function bindActiveShipsFolder(folder)
	if activeShipsFolderConnection then
		activeShipsFolderConnection:Disconnect()
		activeShipsFolderConnection = nil
	end

	activeShipsFolder = folder
	if not activeShipsFolder then
		return
	end

	for _, child in ipairs(activeShipsFolder:GetChildren()) do
		bindShip(child)
	end
	activeShipsFolderConnection = activeShipsFolder.ChildAdded:Connect(function(child)
		task.defer(function()
			bindShip(child)
		end)
	end)
end

local function refreshActiveShipsBinding()
	local refs = MapResolver.GetRefs({ context = "ContextualTutorialTriggerService" })
	if refs.ActiveShips ~= activeShipsFolder then
		bindActiveShipsFolder(refs.ActiveShips)
	end
end

local function bindVerticalStateChanged()
	if verticalStateConnection then
		return
	end

	local service = getVerticalSliceService()
	if typeof(service) ~= "table" or typeof(service.StateChanged) ~= "RBXScriptSignal" then
		return
	end

	verticalStateConnection = service.StateChanged:Connect(function(player)
		TutorialService.TryProcessQueue(player, "vertical_state_changed")
	end)
end

function ContextualTutorialTriggerService.EnqueueResources(player, reason)
	return enqueue(player, "Resources", {
		Source = tostring(reason or "first_time_tutorial_complete"),
	}, nil)
end

function ContextualTutorialTriggerService.OnFoodGranted(player, source, grantedFood)
	if hasPositiveGrant(grantedFood) ~= true and totalFood(player) <= 0 then
		return false, "no_food"
	end

	return enqueue(player, "FeedCrewmates", {
		Source = tostring(source or "food_grant"),
		TargetLabel = "Your ship",
	}, nil)
end

function ContextualTutorialTriggerService.OnQuestDevilFruitChestGranted(player, source)
	return enqueue(player, "QuestReward", {
		Source = tostring(source or "quest_reward"),
	}, nil)
end

function ContextualTutorialTriggerService.CheckShipUpgradeAffordable(player, source)
	if isFirstShipUpgradeAffordable(player) ~= true then
		return false, "not_affordable"
	end

	return enqueue(player, "ShipUpgrade", {
		Source = tostring(source or "resource_grant"),
		TargetLabel = "Ship upgrade",
	}, nil)
end

function ContextualTutorialTriggerService.OnCrewPlaced(player, instanceId, source)
	local service = getCrewInstanceService()
	if typeof(service) ~= "table" or typeof(service.GetInstance) ~= "function" then
		return false, "crew_instance_service_unavailable"
	end

	local resolvedInstanceId, instanceData = service.GetInstance(player, tostring(instanceId or ""))
	if typeof(instanceData) ~= "table" then
		return false, "missing_instance"
	end

	local rarity = normalizeRarity(instanceData.Rarity)
	if getRarityTier(rarity) < RARE_CREW_MIN_TIER then
		return false, "rarity_too_low"
	end

	return enqueue(player, "CrewProtection", {
		Source = tostring(source or "crew_placement"),
		CrewMemberInstanceId = tostring(resolvedInstanceId or instanceId or ""),
		Rarity = rarity,
		TargetLabel = "Protected crew",
	}, nil)
end

function ContextualTutorialTriggerService.Start()
	if started then
		return
	end
	started = true

	refreshActiveShipsBinding()
	serviceConnections[#serviceConnections + 1] =
		Workspace:GetAttributeChangedSignal(ACTIVE_MAP_ATTRIBUTE):Connect(refreshActiveShipsBinding)
	bindVerticalStateChanged()

	serviceConnections[#serviceConnections + 1] = Players.PlayerRemoving:Connect(function(player)
		foreignShipTouchDebounce[player] = nil
	end)
end

return ContextualTutorialTriggerService
