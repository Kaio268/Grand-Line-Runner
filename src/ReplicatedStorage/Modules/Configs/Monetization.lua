local Monetization = {}

Monetization.Status = {
	Active = "active_chefs",
	Placeholder = "placeholder",
	RetiredLegacy = "retired_legacy",
	Unknown = "unknown",
}

Monetization.UnavailableMessage = "This purchase is not available yet."

Monetization.ActiveChefsGamepasses = {
	VIP = {
		Id = 1827239335,
		Name = "VIP",
	},
}

Monetization.ActiveChefsDeveloperProducts = {
	CrewQuickSlot = {
		Id = 3584712420,
		Name = "+1 Crew Quick Slot",
	},
}

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
	StealCommonEpic = {
		Id = 3512126073,
		Name = "Steal Common - Epic",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	StealLegendary = {
		Id = 3512126373,
		Name = "Steal Legendary",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	StealMythic = {
		Id = 3512127278,
		Name = "Steal Mythic",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	StealGodly = {
		Id = 3512127790,
		Name = "Steal Godly",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	StealSecret = {
		Id = 3512128038,
		Name = "Steal Secret",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
	StealOmega = {
		Id = 3512128716,
		Name = "Steal Omega",
		Reason = "Not Chefs-owned. Awaiting replacement product.",
	},
}

Monetization.RetiredLegacyProducts = {
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
