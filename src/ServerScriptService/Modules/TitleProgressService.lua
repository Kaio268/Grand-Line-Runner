local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TitleService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("TitleService"))
local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))

local TitleProgressService = {}

local CREW_COLLECTOR_REQUIRED = 5
local CREW_LEVELS_REQUIRED = 15
local ABYSSAL_EXTRACTIONS_REQUIRED = 10
local MAX_DECK_LEVEL = 8

local rarityRank = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
	Mythic = 6,
	Mythical = 6,
	Godly = 7,
	Secret = 8,
}

local dataManagerModule = nil
local crewInstanceServiceModule = nil

local function getDataManager()
	if dataManagerModule == nil then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("Data"):WaitForChild("DataManager"))
		end)
		dataManagerModule = if ok then result else false
	end

	return if dataManagerModule ~= false then dataManagerModule else nil
end

local function getCrewInstanceService()
	if crewInstanceServiceModule == nil then
		local ok, result = pcall(function()
			return require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewInstanceService"))
		end)
		crewInstanceServiceModule = if ok then result else false
	end

	return if crewInstanceServiceModule ~= false then crewInstanceServiceModule else nil
end

local function isPlayer(player)
	return typeof(player) == "Instance" and player:IsA("Player")
end

local function unlock(player, titleId)
	if not isPlayer(player) then
		return false
	end

	local ok, result = pcall(TitleService.UnlockTitle, player, titleId)
	if not ok then
		warn(string.format(
			"[TitleProgressService] Unlock failed player=%s title=%s reason=%s",
			player.Name,
			tostring(titleId),
			tostring(result)
		))
		return false
	end

	return result == true
end

local function getProgress(player, key)
	local dataManager = getDataManager()
	if dataManager then
		local value = dataManager:TryGetValue(player, "Titles.Progress." .. key)
		if typeof(value) == "number" then
			return value
		end
	end

	return tonumber(player:GetAttribute("TitleProgress_" .. key)) or 0
end

local function setProgress(player, key, value)
	local normalizedValue = math.max(0, math.floor(tonumber(value) or 0))
	player:SetAttribute("TitleProgress_" .. key, normalizedValue)

	local dataManager = getDataManager()
	if dataManager then
		pcall(function()
			dataManager:TrySetValue(player, "Titles.Progress." .. key, normalizedValue)
		end)
	end

	return normalizedValue
end

local function addProgress(player, key, amount)
	return setProgress(player, key, getProgress(player, key) + math.max(0, math.floor(tonumber(amount) or 0)))
end

local function normalizeRarity(value)
	local rarity = tostring(value or "")
	if rarity == "Mythical" then
		return "Mythic"
	end
	return rarity
end

local function isRarityAtLeast(value, minimum)
	return (rarityRank[normalizeRarity(value)] or 0) >= (rarityRank[minimum] or math.huge)
end

local function getCrewCount(player)
	local crewInstanceService = getCrewInstanceService()
	if not crewInstanceService then
		return 0
	end

	local inventory = crewInstanceService.GetCrewInventory(player)
	if typeof(inventory) ~= "table" or typeof(inventory.Order) ~= "table" then
		return 0
	end

	local count = 0
	for _, instanceId in ipairs(inventory.Order) do
		local entry = inventory.ById and inventory.ById[tostring(instanceId)]
		if typeof(entry) == "table" then
			count += 1
		end
	end
	return count
end

local function getPlayerSpeed(player)
	local hidden = player:FindFirstChild("HiddenLeaderstats")
	local speedValue = hidden and hidden:FindFirstChild("Speed")
	if speedValue and typeof(speedValue.Value) == "number" then
		return speedValue.Value
	end

	local dataManager = getDataManager()
	if dataManager then
		local value = dataManager:TryGetValue(player, "HiddenLeaderstats.Speed")
		if typeof(value) == "number" then
			return value
		end
	end

	return tonumber(player:GetAttribute("Speed")) or tonumber(player:GetAttribute("TotalSpeed")) or math.huge
end

local function isFruitKey(fruitName, expectedKey)
	local fruit = DevilFruitConfig.GetFruit(fruitName)
	return fruit ~= nil and tostring(fruit.FruitKey or "") == expectedKey
end

local function looksLikeWaveHazard(hitInfo)
	local hazard = hitInfo and hitInfo.Hazard
	local root = hazard and hazard.Root
	local values = {
		hitInfo and hitInfo.Label,
		hitInfo and hitInfo.MatchSource,
		hazard and hazard.MatchSource,
		root and root.Name,
		root and root:GetAttribute("HazardType"),
		root and root:GetAttribute("HazardClass"),
	}

	for _, value in ipairs(values) do
		local text = string.lower(tostring(value or ""))
		if text:find("wave", 1, true) then
			return true
		end
	end

	return false
end

function TitleProgressService.Unlock(player, titleId)
	return unlock(player, titleId)
end

function TitleProgressService.RecordStarterCrew(player)
	unlock(player, "Deckhand")
end

function TitleProgressService.RecordCrewGained(player, context)
	context = if typeof(context) == "table" then context else {}
	unlock(player, "FirstMate")

	if normalizeRarity(context.Rarity or context.CanonicalRarity) == "Secret" then
		unlock(player, "DressrosaSecret")
	end

	if getCrewCount(player) >= CREW_COLLECTOR_REQUIRED then
		unlock(player, "CrewCollector")
	end
end

function TitleProgressService.RecordCrewLevelsGained(player, levels)
	local gained = math.max(0, math.floor(tonumber(levels) or 0))
	if gained <= 0 then
		return
	end

	if addProgress(player, "CrewLevelsFed", gained) >= CREW_LEVELS_REQUIRED then
		unlock(player, "CaptainTrainer")
	end
end

function TitleProgressService.RecordShipUpgrade(player, newLevel)
	local level = math.max(0, math.floor(tonumber(newLevel) or 0))
	if level <= 0 then
		return
	end

	unlock(player, "Shiphand")
	if level >= MAX_DECK_LEVEL then
		unlock(player, "MaxDeck")
	end
end

function TitleProgressService.RecordRewardExtracted(player, reward)
	reward = if typeof(reward) == "table" then reward else {}
	local rewardType = tostring(reward.RewardType or "")
	local depthBand = tostring(reward.DepthBand or "")

	if rewardType == "Crew" then
		TitleProgressService.RecordCrewGained(player, reward)
	end

	if depthBand == "Deep" then
		unlock(player, "DeepSeaCourier")
	elseif depthBand == "Abyssal" then
		if addProgress(player, "AbyssalExtractions", 1) >= ABYSSAL_EXTRACTIONS_REQUIRED then
			unlock(player, "AbyssTaxCollector")
		end
		if getPlayerSpeed(player) < 10 then
			unlock(player, "SuperRookie")
		end
	end

	if rewardType == "Chest" and tostring(reward.Tier or "") == "Gold" then
		unlock(player, "GoldFever")
	end

	if rewardType == "Chest" and tostring(reward.Source or "") == "DroppedWorld" then
		unlock(player, "DespawnDenier")
	end
end

function TitleProgressService.RecordMaxCarryExtraction(player)
	unlock(player, "GreedOverSpeed")
end

function TitleProgressService.RecordChestOpened(player, chestData, openResult)
	chestData = if typeof(chestData) == "table" then chestData else {}
	openResult = if typeof(openResult) == "table" then openResult else {}

	unlock(player, "ChestCracker")

	local chestTier = tostring(chestData.Tier or "")
	local rewardRarity = openResult.GrantedFruitRarity or openResult.ConversionRewardRarity
	if chestTier == "Wooden" and isRarityAtLeast(rewardRarity, "Legendary") then
		unlock(player, "WoodenMiracle")
	end
end

function TitleProgressService.RecordFruitEaten(player, fruitName)
	if tostring(fruitName or "") == tostring(DevilFruitConfig.None or "None") then
		return
	end

	unlock(player, "EnemyOfTheSea")
	if isFruitKey(fruitName, "Gomu") then
		unlock(player, "RubberRookie")
	elseif isFruitKey(fruitName, "Phoenix") then
		unlock(player, "ThePhoenix")
	end
end

function TitleProgressService.RecordPlayerFrozen(player)
	unlock(player, "ColdHearted")
end

function TitleProgressService.RecordHazardFrozen(player, hitInfo)
	if looksLikeWaveHazard(hitInfo) then
		unlock(player, "WaveFreezer")
	end
end

function TitleProgressService.RecordPhoenixRebirth(player)
	unlock(player, "RebornFlame")

	if tostring(player:GetAttribute("CarriedMajorRewardType") or "") ~= ""
		or tostring(player:GetAttribute("CarriedMajorRewardDisplayName") or "") ~= ""
		or tostring(player:GetAttribute("CarriedCrewMember") or "") ~= ""
	then
		unlock(player, "InsuranceFraud")
	end
end

return TitleProgressService
