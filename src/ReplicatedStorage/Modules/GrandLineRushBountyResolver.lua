local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Configs = Modules:WaitForChild("Configs")
local CrewCatalog = require(Modules:WaitForChild("Crew"):WaitForChild("CrewCatalog"))
local ChestUtils = require(Modules:WaitForChild("GrandLineRushChestUtils"))
local BountyConfig = require(Configs:WaitForChild("GrandLineRushBounty"))

local Resolver = {}

local function round(value)
	return math.floor((tonumber(value) or 0) + 0.5)
end

local function coerceNumber(value, fallback)
	if typeof(value) == "number" then
		return value
	end

	return fallback
end

local function normalizeRarity(rawRarity)
	local rarity = tostring(rawRarity or "Common")
	if BountyConfig.Crew.RarityBaseByRarity[rarity] then
		return rarity
	end

	return "Common"
end

local function resolveCrewConfig(crewMemberId)
	if crewMemberId == "" then
		return nil
	end

	return CrewCatalog.GetInfoById(crewMemberId)
end

local function resolveCrewContext(crewLike)
	local context = typeof(crewLike) == "table" and crewLike or {}
	local fallbackCrewMemberId = if typeof(crewLike) == "string" then crewLike else ""
	local crewMemberId = tostring(context.CrewMemberId or context.StorageName or context.CrewMemberName or fallbackCrewMemberId or "")
	local resolvedCrewMemberId, resolvedConfig = CrewCatalog.ResolveCrewMemberId(crewMemberId)
	if resolvedConfig then
		crewMemberId = resolvedCrewMemberId
	end
	local config = resolvedConfig or resolveCrewConfig(crewMemberId)
	local rarity = normalizeRarity(context.Rarity or (config and config.Rarity) or "Common")
	local level = math.max(1, math.floor(coerceNumber(context.Level, 1)))
	local income = math.max(0, coerceNumber(config and tonumber(config.Income), coerceNumber(context.Income, 0)))

	return {
		CrewMemberId = crewMemberId,
		Rarity = rarity,
		Level = level,
		Income = income,
	}
end

function Resolver.ResolveCrewMemberBaseBounty(crewLike)
	local context = resolveCrewContext(crewLike)
	local override = BountyConfig.Crew.TypeBaseByCrewMemberId[context.CrewMemberId]
	if typeof(override) == "number" then
		return math.max(1, round(override))
	end

	local rarityBase = tonumber(BountyConfig.Crew.RarityBaseByRarity[context.Rarity]) or 0
	local incomeWeight = tonumber(BountyConfig.Crew.IncomeWeightByRarity[context.Rarity]) or 0
	local computed = rarityBase + (context.Income * incomeWeight)
	return math.max(tonumber(BountyConfig.Crew.MinimumBaseBounty) or 1, round(computed))
end

function Resolver.ResolveCrewMemberBounty(crewLike)
	local context = resolveCrewContext(crewLike)
	local baseBounty = Resolver.ResolveCrewMemberBaseBounty(context)
	local levelMultiplier = 1 + ((context.Level - 1) * (tonumber(BountyConfig.Crew.LevelMultiplierPerLevel) or 0))
	return math.max(0, round(baseBounty * levelMultiplier))
end

function Resolver.ResolveCrewBounty(crewInventory)
	if typeof(crewInventory) ~= "table" then
		return 0
	end

	local total = 0
	local byId = typeof(crewInventory.ById) == "table" and crewInventory.ById or {}

	for _, instanceId in ipairs(typeof(crewInventory.Order) == "table" and crewInventory.Order or {}) do
		local instanceData = byId[tostring(instanceId)]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") ~= "" then
			total += Resolver.ResolveCrewMemberBounty(instanceData)
		end
	end

	return math.max(0, total)
end

function Resolver.ResolveExtractionBountyForReward(rewardData)
	if typeof(rewardData) ~= "table" then
		return 0
	end

	if typeof(rewardData.Bounty) == "number" then
		return math.max(0, round(rewardData.Bounty))
	end

	local rewardType = tostring(rewardData.RewardType or "")
	if rewardType == "Chest" then
		local tierName = ChestUtils.ResolveStandardTier(rewardData.Tier)
		if tierName == nil then
			return 0
		end

		return math.max(0, round(BountyConfig.Extraction.ChestBountyByTier[tierName] or 0))
	end

	if rewardType == "Crew" then
		local rarity = normalizeRarity(rewardData.Rarity)
		return math.max(0, round(BountyConfig.Extraction.CrewBountyByRarity[rarity] or 0))
	end

	return 0
end

function Resolver.BuildBreakdown(crewInventory, lifetimeExtractionBounty)
	local crewBounty = Resolver.ResolveCrewBounty(crewInventory)
	local lifetimeExtraction = math.max(0, math.floor(coerceNumber(lifetimeExtractionBounty, 0)))

	return {
		Crew = crewBounty,
		LifetimeExtraction = lifetimeExtraction,
		Total = crewBounty + lifetimeExtraction,
	}
end

return Resolver
