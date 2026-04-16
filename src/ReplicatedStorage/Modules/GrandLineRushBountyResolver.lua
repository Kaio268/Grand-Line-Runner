local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Brainrots = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("Brainrots"))
local BountyConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("GrandLineRushBounty"))

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

local function resolveBrainrotConfig(storageName)
	if storageName == "" then
		return nil
	end

	return Brainrots[storageName]
end

local function resolveBrainrotContext(brainrotLike)
	local context = typeof(brainrotLike) == "table" and brainrotLike or {}
	local fallbackStorageName = if typeof(brainrotLike) == "string" then brainrotLike else ""
	local storageName = tostring(context.StorageName or context.BrainrotName or fallbackStorageName or "")
	local config = resolveBrainrotConfig(storageName)
	local rarity = normalizeRarity(context.Rarity or (config and config.Rarity) or "Common")
	local level = math.max(1, math.floor(coerceNumber(context.Level, 1)))
	local income = math.max(0, coerceNumber(config and tonumber(config.Income), coerceNumber(context.Income, 0)))

	return {
		StorageName = storageName,
		Rarity = rarity,
		Level = level,
		Income = income,
	}
end

function Resolver.ResolveBrainrotBaseBounty(brainrotLike)
	local context = resolveBrainrotContext(brainrotLike)
	local override = BountyConfig.Crew.TypeBaseByStorageName[context.StorageName]
	if typeof(override) == "number" then
		return math.max(1, round(override))
	end

	local rarityBase = tonumber(BountyConfig.Crew.RarityBaseByRarity[context.Rarity]) or 0
	local incomeWeight = tonumber(BountyConfig.Crew.IncomeWeightByRarity[context.Rarity]) or 0
	local computed = rarityBase + (context.Income * incomeWeight)
	return math.max(tonumber(BountyConfig.Crew.MinimumBaseBounty) or 1, round(computed))
end

function Resolver.ResolveBrainrotBounty(brainrotLike)
	local context = resolveBrainrotContext(brainrotLike)
	local baseBounty = Resolver.ResolveBrainrotBaseBounty(context)
	local levelMultiplier = 1 + ((context.Level - 1) * (tonumber(BountyConfig.Crew.LevelMultiplierPerLevel) or 0))
	return math.max(0, round(baseBounty * levelMultiplier))
end

function Resolver.ResolveCrewBounty(brainrotInventory)
	if typeof(brainrotInventory) ~= "table" then
		return 0
	end

	local total = 0
	local byId = typeof(brainrotInventory.ById) == "table" and brainrotInventory.ById or {}

	for _, instanceId in ipairs(typeof(brainrotInventory.Order) == "table" and brainrotInventory.Order or {}) do
		local instanceData = byId[tostring(instanceId)]
		if typeof(instanceData) == "table" and tostring(instanceData.AssignedStand or "") ~= "" then
			total += Resolver.ResolveBrainrotBounty(instanceData)
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
		return math.max(0, round(BountyConfig.Extraction.ChestBountyByTier[tostring(rewardData.Tier or "")] or 0))
	end

	if rewardType == "Crew" then
		local rarity = normalizeRarity(rewardData.Rarity)
		return math.max(0, round(BountyConfig.Extraction.CrewBountyByRarity[rarity] or 0))
	end

	return 0
end

function Resolver.BuildBreakdown(brainrotInventory, lifetimeExtractionBounty)
	local crewBounty = Resolver.ResolveCrewBounty(brainrotInventory)
	local lifetimeExtraction = math.max(0, math.floor(coerceNumber(lifetimeExtractionBounty, 0)))

	return {
		Crew = crewBounty,
		LifetimeExtraction = lifetimeExtraction,
		Total = crewBounty + lifetimeExtraction,
	}
end

return Resolver
