local Monetization = {}
local PremiumCrewStealConfig = require(script.Parent:WaitForChild("PremiumCrewStealConfig"))

Monetization.Status = {
	Active = "active_chefs",
	Placeholder = "placeholder",
	RetiredLegacy = "retired_legacy",
	Unknown = "unknown",
}

Monetization.UnavailableMessage = "This purchase is not available yet."
Monetization.PaidRandomItemUnavailableMessage = "This paid random item is unavailable for your account."

Monetization.PaidRandomItemPolicy = {
	Remotes = {
		StateRequestName = "PaidRandomItemPolicyStateRequest",
		ProductPromptRequestName = "PaidRandomProductPromptRequest",
	},
	ReceiptFallback = {
		Mode = "SupportMarker",
		DataKey = "PaidRandomItemReceiptFallbacks",
		MaxEntries = 100,
	},
}

Monetization.ActiveChefsGamepasses = {
	VIP = {
		Id = 1827239335,
		Name = "VIP",
	},
}

Monetization.ActiveChefsDeveloperProducts = {}

for _, bucket in ipairs(PremiumCrewStealConfig.GetActiveProductBuckets()) do
	local productId = tonumber(bucket.ProductId)
	if productId and productId > 0 then
		Monetization.ActiveChefsDeveloperProducts["PremiumCrewSteal_" .. tostring(bucket.Key)] = {
			Id = productId,
			Name = "Premium Crew Steal " .. tostring(bucket.PriceRobux) .. " Robux",
			PremiumCrewSteal = true,
		}
	end
end

Monetization.PlaceholderGamepasses = {
	X2Beli = {
		Id = 1667343349,
		Name = "2x Beli",
		Reason = "Not Chefs-owned. Awaiting replacement gamepass.",
	},
}

Monetization.PlaceholderDeveloperProducts = {
	RewardsBoost = {
		Id = 3515417573,
		Name = "2x Rewards Boost",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	RewardsBoostBundle = {
		Id = 3515418047,
		Name = "2x Rewards Boost x3",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	DropRateBoost = {
		Id = 3515409012,
		Name = "Drop Rate Boost",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	SpeedPlusOne = {
		Id = 3516522193,
		Name = "+1 Speed",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	SpeedPlusFive = {
		Id = 3516522992,
		Name = "+5 Speed",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	SpeedPlusTen = {
		Id = 3516522609,
		Name = "+10 Speed",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearSpeedCoil = {
		Id = 3516539588,
		Name = "Speed Coil",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearGoldenSlap = {
		Id = 3516540101,
		Name = "Golden Slap",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearGoldenSpeedCoil = {
		Id = 3516540402,
		Name = "Golden Speed Coil",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearDiamondSlap = {
		Id = 3516540726,
		Name = "Diamond Slap",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearDiamondSpeedCoil = {
		Id = 3516541163,
		Name = "Diamond Speed Coil",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearGalaxySlap = {
		Id = 3516541650,
		Name = "Galaxy Slap",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearGalaxySpeedCoil = {
		Id = 3516542043,
		Name = "Galaxy Speed Coil",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearLavaSlap = {
		Id = 3516542817,
		Name = "Lava Slap",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	GearLavaSpeedCoil = {
		Id = 3516543186,
		Name = "Lava Speed Coil",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
}

Monetization.RetiredLegacyProducts = {
	CrewQuickSlot = {
		Id = 3584712420,
		Name = "+1 Crew Quick Slot",
		Reason = "retired_hotbar_slots_unlocked_by_default",
	},
	StarterPackOne = {
		Id = 3509345784,
		Name = "Starter Pack #1",
		Reason = "retired_template_starter_pack",
	},
	StarterPackTwo = {
		Id = 3509346000,
		Name = "Starter Pack #2",
		Reason = "retired_template_better_starter_pack",
	},
	StarterPackThree = {
		Id = 3509346182,
		Name = "Starter Pack #3",
		Reason = "retired_template_best_starter_pack",
	},
	StarterPackFour = {
		Id = 3509346360,
		Name = "Starter Pack #4",
		Reason = "retired_template_super_op_starter_pack",
	},
	JuiceDuchessGroupReward = {
		Id = 3512059347,
		Name = "Op Brainrot",
		Reason = "retired_template_juice_duchess_group_reward",
	},
	StopDisasters = {
		Id = 3509345591,
		Name = "Stop Disasters",
		Reason = "retired_template_stop_disasters",
	},
	ServerLuckFour = {
		Id = 3515409311,
		Name = "Server Luck x4",
		Reason = "retired_template_server_luck_tier_4x",
	},
	ServerLuckEight = {
		Id = 3515410147,
		Name = "Server Luck x8",
		Reason = "retired_template_server_luck_tier_8x",
	},
	ServerLuckSixteen = {
		Id = 3515410559,
		Name = "Server Luck x16",
		Reason = "retired_template_server_luck_tier_16x",
	},
	WalkSpeedSingle = {
		Id = 3515418772,
		Name = "x1.5 Walk Speed 40min",
		Reason = "retired_template_walkspeed_boost_single",
	},
	WalkSpeedBundle = {
		Id = 3515419300,
		Name = "x1.5 Walk Speed 90min",
		Reason = "retired_template_walkspeed_boost_bundle",
	},
	LegacyCrewStealCommonEpic = {
		Id = 3512126073,
		Name = "Retired Legacy Crew Steal Common - Epic",
		Reason = "retired_legacy_crewmate_steal_product",
	},
	LegacyCrewStealLegendary = {
		Id = 3512126373,
		Name = "Retired Legacy Crew Steal Legendary",
		Reason = "retired_legacy_crewmate_steal_product",
	},
	LegacyCrewStealMythic = {
		Id = 3512127278,
		Name = "Retired Legacy Crew Steal Mythic",
		Reason = "retired_legacy_crewmate_steal_product",
	},
	LegacyCrewStealGodly = {
		Id = 3512127790,
		Name = "Retired Legacy Crew Steal Godly",
		Reason = "retired_legacy_crewmate_steal_product",
	},
	LegacyCrewStealSecret = {
		Id = 3512128038,
		Name = "Retired Legacy Crew Steal Secret",
		Reason = "retired_legacy_crewmate_steal_product",
	},
	LegacyCrewStealOmega = {
		Id = 3512128716,
		Name = "Retired Legacy Crew Steal Omega",
		Reason = "retired_legacy_crewmate_steal_product",
	},
}

local gamepassMetadataById = {}
local gamepassIdsByStatus = {}
local developerProductMetadataById = {}
local developerProductIdsByStatus = {}

local function register(entries, status, metadataById, idsByStatus)
	idsByStatus[status] = idsByStatus[status] or {}

	for key, entry in pairs(entries) do
		local id = tonumber(entry.Id)
		if id and id > 0 then
			local metadata = {
				Key = key,
				Id = id,
				Name = entry.Name,
				Reason = entry.Reason,
				Status = status,
				RequiresPaidRandomItemPolicy = entry.RequiresPaidRandomItemPolicy == true,
				PaidRandomItem = entry.PaidRandomItem == true,
				RobuxFundedRandomCurrency = entry.RobuxFundedRandomCurrency == true,
				RandomRewardGenerator = entry.RandomRewardGenerator == true,
			}
			metadataById[id] = metadata
			table.insert(idsByStatus[status], id)
		end
	end
end

register(Monetization.ActiveChefsGamepasses, Monetization.Status.Active, gamepassMetadataById, gamepassIdsByStatus)
register(Monetization.PlaceholderGamepasses, Monetization.Status.Placeholder, gamepassMetadataById, gamepassIdsByStatus)
register(
	Monetization.ActiveChefsDeveloperProducts,
	Monetization.Status.Active,
	developerProductMetadataById,
	developerProductIdsByStatus
)
register(
	Monetization.PlaceholderDeveloperProducts,
	Monetization.Status.Placeholder,
	developerProductMetadataById,
	developerProductIdsByStatus
)
register(
	Monetization.RetiredLegacyProducts,
	Monetization.Status.RetiredLegacy,
	developerProductMetadataById,
	developerProductIdsByStatus
)

local function copyIds(source)
	local result = table.clone(source or {})
	table.sort(result)
	return result
end

function Monetization.GetGamepassStatus(gamepassId)
	local id = tonumber(gamepassId)
	local metadata = id and gamepassMetadataById[id]
	if metadata then
		return metadata.Status, metadata
	end
	return Monetization.Status.Unknown, nil
end

function Monetization.GetDeveloperProductStatus(productId)
	local id = tonumber(productId)
	local metadata = id and developerProductMetadataById[id]
	if metadata then
		return metadata.Status, metadata
	end
	return Monetization.Status.Unknown, nil
end

function Monetization.IsActiveGamepass(gamepassId)
	return Monetization.GetGamepassStatus(gamepassId) == Monetization.Status.Active
end

function Monetization.IsActiveDeveloperProduct(productId)
	return Monetization.GetDeveloperProductStatus(productId) == Monetization.Status.Active
end

function Monetization.CanPromptGamepass(gamepassId)
	return Monetization.IsActiveGamepass(gamepassId)
end

function Monetization.CanPromptDeveloperProduct(productId)
	return Monetization.IsActiveDeveloperProduct(productId)
end

function Monetization.CanPromptPurchase(kind, id)
	if kind == "gamepass" then
		return Monetization.CanPromptGamepass(id)
	end
	if kind == "product" then
		return Monetization.CanPromptDeveloperProduct(id)
	end
	return false
end

local function metadataRequiresPaidRandomItemPolicy(metadata)
	return typeof(metadata) == "table"
		and (
			metadata.RequiresPaidRandomItemPolicy == true
			or metadata.PaidRandomItem == true
			or metadata.RobuxFundedRandomCurrency == true
			or metadata.RandomRewardGenerator == true
		)
end

local function purchaseTableRequiresPaidRandomItemPolicy(purchase)
	if typeof(purchase) ~= "table" then
		return false
	end

	if purchase.RequiresPaidRandomItemPolicy == true
		or purchase.PaidRandomItem == true
		or purchase.RobuxFundedRandomCurrency == true
		or purchase.RandomRewardGenerator == true
	then
		return true
	end

	local kind = tostring(purchase.kind or purchase.Kind or "")
	local id = purchase.id or purchase.Id
	if kind == "product" then
		return Monetization.DeveloperProductRequiresPaidRandomItemPolicy(id)
	elseif kind == "gamepass" then
		return Monetization.GamepassRequiresPaidRandomItemPolicy(id)
	end

	return false
end

function Monetization.DeveloperProductRequiresPaidRandomItemPolicy(productId)
	local _, metadata = Monetization.GetDeveloperProductStatus(productId)
	return metadataRequiresPaidRandomItemPolicy(metadata)
end

function Monetization.GamepassRequiresPaidRandomItemPolicy(gamepassId)
	local _, metadata = Monetization.GetGamepassStatus(gamepassId)
	return metadataRequiresPaidRandomItemPolicy(metadata)
end

function Monetization.PurchaseRequiresPaidRandomItemPolicy(kindOrPurchase, id)
	if typeof(kindOrPurchase) == "table" then
		return purchaseTableRequiresPaidRandomItemPolicy(kindOrPurchase)
	end

	local kind = tostring(kindOrPurchase or "")
	if kind == "product" then
		return Monetization.DeveloperProductRequiresPaidRandomItemPolicy(id)
	elseif kind == "gamepass" then
		return Monetization.GamepassRequiresPaidRandomItemPolicy(id)
	end

	return false
end

function Monetization.ItemRequiresPaidRandomItemPolicy(item)
	if typeof(item) ~= "table" then
		return false
	end

	if item.RequiresPaidRandomItemPolicy == true
		or item.PaidRandomItem == true
		or item.RobuxFundedRandomCurrency == true
		or item.RandomRewardGenerator == true
	then
		return true
	end

	return purchaseTableRequiresPaidRandomItemPolicy(item.purchase)
end

function Monetization.GetDeveloperProductIdsForStatus(status)
	return copyIds(developerProductIdsByStatus[status])
end

function Monetization.GetGamepassIdsForStatus(status)
	return copyIds(gamepassIdsByStatus[status])
end

function Monetization.GetDisabledDeveloperProductIds()
	local result = Monetization.GetDeveloperProductIdsForStatus(Monetization.Status.Placeholder)
	for _, id in ipairs(Monetization.GetDeveloperProductIdsForStatus(Monetization.Status.RetiredLegacy)) do
		table.insert(result, id)
	end
	table.sort(result)
	return result
end

return Monetization
