local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevilFruitConfig = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits")
)

local PhoenixShared = {}

PhoenixShared.FruitName = assert(DevilFruitConfig.GetDisplayName("Phoenix"), "Missing Phoenix fruit config")

PhoenixShared.Passives = {
	PhoenixRebirth = {
		RestoreDelay = 0.45,
		ActivationDelay = 2,
		ReviveDelay = 0.85,
		AnimationDuration = 2.4,
		ImmunityDuration = 1,
		StabilizeHealthPercent = 0.08,
		RestoreHealthPercent = 1,
		AnimationKey = "Phoenix.PhoenixRevive",
		ReviveMarkerNames = { "Revive", "Rebirth", "PhoenixRevive", "Restore" },
		Audio = {
			ReviveSoundId = "rbxassetid://137266608991780",
			ReviveSoundOffset = 0,
		},
		PendingUntilAttribute = "PhoenixRebirthPendingUntil",
		ImmuneUntilAttribute = "PhoenixRebirthImmuneUntil",
		TriggeredAtAttribute = "PhoenixRebirthTriggeredAt",
		ReviveAtAttribute = "PhoenixRebirthReviveAt",
		EndsAtAttribute = "PhoenixRebirthEndsAt",
		UsedAttribute = "PhoenixRebirthUsed",
	},
}

return PhoenixShared
