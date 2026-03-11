local DevilFruits = {
	None = "",
	Fruits = {
		["Mera Mera no Mi"] = {
			Id = "MeraMeraNoMi",
			DisplayName = "Mera Mera no Mi",
			Rarity = "Legendary",
			Abilities = {
				FlameDash = {
					KeyCode = Enum.KeyCode.Q,
					Cooldown = 5,
					DashDistance = 42,
					DashDuration = 0.14,
					InstantDashFraction = 0.58,
					DistanceSpeedBonusFactor = 0.06,
					MaxDistanceSpeedBonus = 14,
					BaseDashSpeed = 150,
					DashSpeedMultiplier = 3.1,
					EndDashSpeedMultiplier = 1.35,
					MaxDashSpeed = 260,
				},
				FireBurst = {
					KeyCode = Enum.KeyCode.E,
					Cooldown = 14,
					Radius = 10,
					Duration = 0.6,
				},
			},
		},
	},
}

function DevilFruits.GetFruit(name)
	if typeof(name) ~= "string" or name == "" then
		return nil
	end

	return DevilFruits.Fruits[name]
end

function DevilFruits.GetAbility(fruitName, abilityName)
	local fruit = DevilFruits.GetFruit(fruitName)
	if not fruit or typeof(abilityName) ~= "string" then
		return nil
	end

	return fruit.Abilities and fruit.Abilities[abilityName] or nil
end

return DevilFruits
