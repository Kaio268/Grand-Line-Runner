local ToriShared = {}

ToriShared.FruitName = "Tori Tori no Mi"

ToriShared.Passives = {
	PhoenixRebirth = {
		RestoreDelay = 0.45,
		ActivationDelay = 2,
		ReviveDelay = 0.85,
		AnimationDuration = 2.4,
		ImmunityDuration = 1,
		StabilizeHealthPercent = 0.08,
		RestoreHealthPercent = 1,
		AnimationKey = "Tori.PhoenixRevive",
		ReviveMarkerNames = { "Revive", "Rebirth", "PhoenixRevive", "Restore" },
		PendingUntilAttribute = "ToriPhoenixRebirthPendingUntil",
		ImmuneUntilAttribute = "ToriPhoenixRebirthImmuneUntil",
		TriggeredAtAttribute = "ToriPhoenixRebirthTriggeredAt",
		ReviveAtAttribute = "ToriPhoenixRebirthReviveAt",
		EndsAtAttribute = "ToriPhoenixRebirthEndsAt",
		UsedAttribute = "ToriPhoenixRebirthUsed",
	},
}

return ToriShared
