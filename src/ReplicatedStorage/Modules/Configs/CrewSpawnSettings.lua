return {
	MaxPerPart = 7,
	PlayerSpawnRadius = 500,
	DespawnWhenNoPlayers = true,

	TickInterval = 0.5,
	MaxSpawnOperationsPerTick = 6,

	InitialScale = 0.05,
	TweenTime = 0.6,

	-- Spawn pads use controlled nearby-rarity bleed only:
	-- same tier = full weight, one tier below = small bleed, one tier above = rarer bleed.
	-- Keep these values aligned with the intended balance pass: 1 / 0.02 / 0.01.
	ReconcileInterval = 2,
	RarityDistanceWeights = {
		SameTier = 1,
		OneTierBelow = 0.02,
		OneTierAbove = 0.01,
	},
}
