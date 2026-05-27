local PremiumCrewStealConfig = {}

PremiumCrewStealConfig.Enabled = true

PremiumCrewStealConfig.Remotes = {
	WarningName = "PremiumCrewStealWarning",
	ConfirmName = "PremiumCrewStealConfirm",
	ResultName = "PremiumCrewStealResult",
}

PremiumCrewStealConfig.Prompt = {
	Name = "PremiumCrewStealPrompt",
	ActionText = "Steal",
	ObjectText = "Premium Steal",
	HoldDuration = 0.45,
	MaxActivationDistance = 12,
	OfferTtlSeconds = 90,
}

PremiumCrewStealConfig.Reservations = {
	TimeoutSeconds = 90,
}

PremiumCrewStealConfig.Attributes = {
	HideFromOwnerInteraction = "ShipHideFromOwnerInteraction",
	PromptKind = "PremiumCrewStealPrompt",
	ProtectedUntil = "PremiumCrewStealProtectedUntil",
	ProtectionActive = "PremiumCrewStealProtected",
	ProtectionSource = "PremiumCrewStealProtectionSource",
	ProtectionRemainingSeconds = "PremiumCrewStealProtectionRemainingSeconds",
	ProtectionPlaytimeSeconds = "PremiumCrewStealProtectionPlaytimeSeconds",
	ProtectionRemovedReason = "PremiumCrewStealProtectionRemovedReason",
}

PremiumCrewStealConfig.Cooldowns = {
	PromptDebounceSeconds = 2,
	BuyerVictimSeconds = 300,
	MemoryStoreName = "PremiumCrewStealCooldowns_v1",
	MemoryStoreExpiryBufferSeconds = 60,
}

PremiumCrewStealConfig.Protection = {
	Enabled = true,
	DurationSeconds = 600,
	RemoveOnSuccessfulSteal = true,
	RemovalMemoryStoreName = "PremiumCrewStealProtectionRemoved_v1",
	RemovalMemoryStoreTtlSeconds = 86400,
}

PremiumCrewStealConfig.NewPlayerProtection = {
	Enabled = true,
	PlaytimeThresholdSeconds = 28800,
	PlaytimePath = "TotalStats.TimePlayed",
	ManualEnabledPath = "Settings.PremiumStealProtectionEnabled",
	StatePath = "PremiumCrewStealProtection",
	RemovedPath = "PremiumCrewStealProtection.NewPlayerRemoved",
	RemovedAtPath = "PremiumCrewStealProtection.RemovedAt",
	RemovedReasonPath = "PremiumCrewStealProtection.RemovedReason",
}

PremiumCrewStealConfig.ReceiptFallback = {
	DataKey = "PremiumCrewStealReceiptFallbacks",
	SuccessDataKey = "PremiumCrewStealSuccessfulReceipts",
	MaxEntries = 100,
}

PremiumCrewStealConfig.RarityBasePrices = {
	Common = 19,
	Uncommon = 29,
	Rare = 49,
	Epic = 99,
	Legendary = 199,
	Mythic = 399,
	Godly = 699,
	Secret = 1099,
}

PremiumCrewStealConfig.RarityPriority = {
	"Secret",
	"Godly",
	"Mythic",
	"Legendary",
	"Epic",
	"Rare",
	"Uncommon",
	"Common",
}

PremiumCrewStealConfig.RarityAliases = {
	Mythical = "Mythic",
	Celestial = "Godly",
}

PremiumCrewStealConfig.UnsupportedRarities = {
	Omega = true,
}

PremiumCrewStealConfig.LevelMultipliers = {
	{ MinLevel = 1, MaxLevel = 4, Multiplier = 1 },
	{ MinLevel = 5, MaxLevel = 9, Multiplier = 1.08 },
	{ MinLevel = 10, MaxLevel = 19, Multiplier = 1.15 },
	{ MinLevel = 20, MaxLevel = 34, Multiplier = 1.25 },
	{ MinLevel = 35, MaxLevel = 44, Multiplier = 1.35 },
	{ MinLevel = 45, MaxLevel = 49, Multiplier = 1.45 },
	{ MinLevel = 50, MaxLevel = math.huge, Multiplier = 1.65 },
}

PremiumCrewStealConfig.VariantMultipliers = {
	Normal = 1,
	Golden = 1.3,
	Diamond = 1.55,
}

PremiumCrewStealConfig.MaxPriceRobux = 2999

PremiumCrewStealConfig.ProductBuckets = {
	{ Key = "Steal_19", PriceRobux = 19, ProductId = 3599208654, Enabled = true },
	{ Key = "Steal_29", PriceRobux = 29, ProductId = 0, Enabled = false },
	{ Key = "Steal_49", PriceRobux = 49, ProductId = 3599215515, Enabled = true },
	{ Key = "Steal_79", PriceRobux = 79, ProductId = 0, Enabled = false },
	{ Key = "Steal_99", PriceRobux = 99, ProductId = 3599215578, Enabled = true },
	{ Key = "Steal_149", PriceRobux = 149, ProductId = 0, Enabled = false },
	{ Key = "Steal_199", PriceRobux = 199, ProductId = 3599215651, Enabled = true },
	{ Key = "Steal_299", PriceRobux = 299, ProductId = 0, Enabled = false },
	{ Key = "Steal_399", PriceRobux = 399, ProductId = 3599215703, Enabled = true },
	{ Key = "Steal_499", PriceRobux = 499, ProductId = 0, Enabled = false },
	{ Key = "Steal_799", PriceRobux = 799, ProductId = 3599215757, Enabled = true },
	{ Key = "Steal_999", PriceRobux = 999, ProductId = 0, Enabled = false },
	{ Key = "Steal_1299", PriceRobux = 1299, ProductId = 0, Enabled = false },
	{ Key = "Steal_1499", PriceRobux = 1499, ProductId = 3599215832, Enabled = true },
	{ Key = "Steal_1999", PriceRobux = 1999, ProductId = 3599466903, Enabled = true },
	{ Key = "Steal_2499", PriceRobux = 2499, ProductId = 3599467166, Enabled = true },
	{ Key = "Steal_2999", PriceRobux = 2999, ProductId = 3599215920, Enabled = true },
}

local bucketsByProductId = {}
local activeBuckets = {}

for _, bucket in ipairs(PremiumCrewStealConfig.ProductBuckets) do
	local productId = tonumber(bucket.ProductId)
	if bucket.Enabled == true and productId and productId > 0 then
		bucketsByProductId[productId] = bucket
		table.insert(activeBuckets, bucket)
	end
end

function PremiumCrewStealConfig.GetBucketForPrice(priceRobux)
	local price = math.max(0, math.floor(tonumber(priceRobux) or 0))

	for _, bucket in ipairs(activeBuckets) do
		if price <= bucket.PriceRobux then
			return bucket
		end
	end

	return nil
end

function PremiumCrewStealConfig.GetBucketForProductId(productId)
	return bucketsByProductId[tonumber(productId)]
end

function PremiumCrewStealConfig.GetActiveProductBuckets()
	return table.clone(activeBuckets)
end

function PremiumCrewStealConfig.IsProductBucketActive(bucket)
	local productId = tonumber(bucket and bucket.ProductId)
	return bucket ~= nil and bucket.Enabled == true and productId ~= nil and productId > 0
end

return PremiumCrewStealConfig
