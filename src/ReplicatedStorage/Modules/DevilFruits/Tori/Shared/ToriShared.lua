local ToriShared = {}

ToriShared.FruitName = "Tori Tori no Mi"

ToriShared.Passives = {
	PhoenixRebirth = {
		RestoreDelay = 0.45,
		ImmunityDuration = 1,
		RestoreHealthPercent = 1,
		PendingUntilAttribute = "ToriPhoenixRebirthPendingUntil",
		ImmuneUntilAttribute = "ToriPhoenixRebirthImmuneUntil",
		TriggeredAtAttribute = "ToriPhoenixRebirthTriggeredAt",
		UsedAttribute = "ToriPhoenixRebirthUsed",
	},
}

return ToriShared
