local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ChestRewards = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushChestRewards"))
local ChestUtils = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GrandLineRushChestUtils"))
local AddCrewMember = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("AddCrewMember"))
local CrewProtectionService = require(ServerScriptService:WaitForChild("Modules"):WaitForChild("CrewProtectionService"))

local ShopReceiptGrants = {}

local STARTER_PACK_FLAG = "Packs.StarterPack"
local contextualTutorialTriggerService = nil

local function fail(reason)
	return false, tostring(reason or "grant_failed")
end

local function assertOk(ok, reason)
	if ok == true then
		return true
	end
	error("shop_grant_failed:" .. tostring(reason or "unknown"))
end

local function addValue(dataManager, player, path, amount)
	local ok, reason = dataManager:TryAddValue(player, path, amount)
	return assertOk(ok, reason)
end

local function setValue(dataManager, player, path, value)
	local ok, reason = dataManager:TrySetValue(player, path, value)
	return assertOk(ok, reason)
end

local function addBeli(dataManager, player, amount)
	addValue(dataManager, player, "leaderstats.Beli", amount)
	addValue(dataManager, player, "TotalStats.TotalBeli", amount)
end

local function getContextualTutorialTriggerService()
	if contextualTutorialTriggerService ~= nil then
		return contextualTutorialTriggerService
	end

	local module = ServerScriptService.Modules:FindFirstChild("ContextualTutorialTriggerService")
	if not module then
		return nil
	end

	local ok, service = pcall(require, module)
	if ok then
		contextualTutorialTriggerService = service
	end
	return contextualTutorialTriggerService
end

local function triggerFoodAndShipTutorials(player, source, grantedFood)
	local service = getContextualTutorialTriggerService()
	if typeof(service) ~= "table" then
		return
	end
	if typeof(service.OnFoodGranted) == "function" then
		service.OnFoodGranted(player, source, grantedFood)
	end
	if typeof(service.CheckShipUpgradeAffordable) == "function" then
		service.CheckShipUpgradeAffordable(player, source)
	end
end

local function ensureUnopenedChests(dataRoot)
	if typeof(dataRoot.UnopenedChests) ~= "table" then
		dataRoot.UnopenedChests = {}
	end

	local unopened = dataRoot.UnopenedChests
	if typeof(unopened.ById) ~= "table" then
		unopened.ById = {}
	end
	if typeof(unopened.Order) ~= "table" then
		unopened.Order = {}
	end
	if typeof(unopened.Stacks) ~= "table" then
		unopened.Stacks = {}
	end
	unopened.NextChestId = math.max(1, math.floor(tonumber(unopened.NextChestId) or 1))
	unopened.StackSchemaVersion = 1
	return unopened
end

local function addUnopenedChest(dataRoot, chestData)
	local unopened = ensureUnopenedChests(dataRoot)
	local chestId = tostring(unopened.NextChestId)
	while unopened.ById[chestId] ~= nil do
		unopened.NextChestId += 1
		chestId = tostring(unopened.NextChestId)
	end

	local normalized = ChestUtils.BuildChestData(chestData)
	local storedChest = {
		ChestId = chestId,
		ChestKind = normalized.ChestKind,
		Tier = normalized.Tier,
		FruitRarity = normalized.FruitRarity,
		DepthBand = tostring(normalized.DepthBand or ""),
		Source = tostring(normalized.Source or ChestRewards.DefaultChestSource),
		RewardProfile = tostring(normalized.RewardProfile or ChestRewards.DefaultRewardProfile),
		CreatedAt = math.max(0, tonumber(normalized.CreatedAt) or os.time()),
	}

	if normalized.PaidRandomItem == true then
		storedChest.PaidRandomItem = true
		storedChest.PaidRandomProductId = tonumber(normalized.PaidRandomProductId)
		storedChest.PaidRandomPurchaseId = normalized.PaidRandomPurchaseId
	end

	unopened.ById[chestId] = storedChest
	table.insert(unopened.Order, chestId)
	unopened.NextChestId += 1
	return unopened, chestId
end

function ShopReceiptGrants.GrantBoost(player, dataManager, boostKey, durationSeconds)
	local duration = math.max(1, math.floor(tonumber(durationSeconds) or 0))
	if boostKey == "MoneyBoost" then
		addValue(dataManager, player, "Potions.x2MoneyTime", duration)
		dataManager:ResumeBoost(player, "x2Money")
		return true
	elseif boostKey == "SpeedBoost" then
		addValue(dataManager, player, "Potions.x15WalkSpeedTime", duration)
		dataManager:ResumeBoost(player, "x15WalkSpeed")
		return true
	elseif boostKey == "LuckBoost" then
		addValue(dataManager, player, "Potions.xLuckTime", duration)
		dataManager:ResumeBoost(player, "xLuck")
		return true
	end

	return fail("unknown_boost")
end

function ShopReceiptGrants.GrantMythicFruitChest(receiptInfo, player, profile, dataManager)
	local unopened = addUnopenedChest(profile.Data, {
		ChestKind = ChestRewards.ChestKinds.DevilFruit,
		FruitRarity = "Mythic",
		Source = "Purchase",
		PaidRandomItem = true,
		ProductId = receiptInfo and receiptInfo.ProductId,
		PurchaseId = receiptInfo and receiptInfo.PurchaseId,
	})
	setValue(dataManager, player, "UnopenedChests", unopened)
	return true
end

function ShopReceiptGrants.GrantStarterPack(player, profile, dataManager)
	if profile.Data.Packs and profile.Data.Packs.StarterPack == true then
		return true, "already_granted"
	end

	local ok, reason = AddCrewMember:AddCrewMember(player, "Golden Bloom Scholar", 1, {
		Source = "starter_pack",
		GrandLineRushStarter = true,
		_QuickSlotCapacityReserved = true,
	})
	if ok ~= true then
		return fail(reason)
	end

	addBeli(dataManager, player, 250000)
	addValue(dataManager, player, "Materials.Timber", 250)
	addValue(dataManager, player, "Materials.Iron", 40)
	addValue(dataManager, player, "FoodInventory.Apple", 20)
	addValue(dataManager, player, "FoodInventory.Rice", 15)
	addValue(dataManager, player, "FoodInventory.Meat", 10)
	addValue(dataManager, player, "FoodInventory.SeaBeastMeat", 3)
	ShopReceiptGrants.GrantBoost(player, dataManager, "MoneyBoost", 60 * 60)
	ShopReceiptGrants.GrantBoost(player, dataManager, "SpeedBoost", 60 * 60)
	ShopReceiptGrants.GrantBoost(player, dataManager, "LuckBoost", 60 * 60)
	assertOk(CrewProtectionService.GrantCrewShieldTokens(player, 3, dataManager))
	setValue(dataManager, player, STARTER_PACK_FLAG, true)
	triggerFoodAndShipTutorials(player, "shop_starter_pack", {
		Apple = 20,
		Rice = 15,
		Meat = 10,
		SeaBeastMeat = 3,
	})

	return true, "granted"
end

function ShopReceiptGrants.GrantCaptainDailyChest(player, dataManager)
	addBeli(dataManager, player, 10000)
	addValue(dataManager, player, "FoodInventory.Apple", 10)
	addValue(dataManager, player, "FoodInventory.Rice", 5)
	addValue(dataManager, player, "FoodInventory.Meat", 3)
	addValue(dataManager, player, "FoodInventory.SeaBeastMeat", 1)
	addValue(dataManager, player, "Materials.Timber", 75)
	addValue(dataManager, player, "Materials.Iron", 20)
	addValue(dataManager, player, "Materials.AncientTimber", 1)
	triggerFoodAndShipTutorials(player, "shop_captain_daily_chest", {
		Apple = 10,
		Rice = 5,
		Meat = 3,
		SeaBeastMeat = 1,
	})
	return true
end

function ShopReceiptGrants.GrantPermanentShieldSlot(player, dataManager)
	return CrewProtectionService.GrantPermanentSlots(player, 1, dataManager)
end

function ShopReceiptGrants.ProcessShopDeveloperProduct(metadata, receiptInfo, player, profile, dataManager)
	if typeof(metadata) ~= "table" then
		return fail("missing_metadata")
	end

	local grantKey = tostring(metadata.GrantKey or "")
	if grantKey == "StarterPack" then
		return ShopReceiptGrants.GrantStarterPack(player, profile, dataManager)
	elseif grantKey == "MythicFruitChest" then
		return ShopReceiptGrants.GrantMythicFruitChest(receiptInfo, player, profile, dataManager)
	elseif grantKey == "MoneyBoost" or grantKey == "LuckBoost" or grantKey == "SpeedBoost" then
		return ShopReceiptGrants.GrantBoost(player, dataManager, grantKey, metadata.DurationSeconds)
	elseif grantKey == "CrewShield" then
		return CrewProtectionService.GrantCrewShieldTokens(player, 1, dataManager)
	elseif grantKey == "FleetShield" then
		return CrewProtectionService.GrantFleetShieldTokens(player, 1, dataManager)
	elseif grantKey == "PermanentShieldSlot" then
		return ShopReceiptGrants.GrantPermanentShieldSlot(player, dataManager)
	end

	return fail("unknown_grant_key")
end

return ShopReceiptGrants
