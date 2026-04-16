local HitEffects = {
	Attributes = {
		Type = "GrandLineRushHitEffectType",
		Until = "GrandLineRushHitEffectUntil",
		WalkSpeedMultiplier = "GrandLineRushHitEffectWalkSpeedMultiplier",
		JumpMultiplier = "GrandLineRushHitEffectJumpMultiplier",
	},
	EffectsByName = {
		Knockdown = {
			DisplayName = "Knockdown",
			Duration = 0.75,
			Priority = 30,
			ForcesCarryDrop = true,
			Movement = {
				WalkSpeedMultiplier = 0,
				JumpMultiplier = 0,
				AutoRotate = false,
				PlatformStand = true,
				State = Enum.HumanoidStateType.Physics,
			},
		},
		Stun = {
			DisplayName = "Stun",
			Duration = 1,
			Priority = 20,
			ForcesCarryDrop = false,
			Movement = {
				WalkSpeedMultiplier = 0,
				JumpMultiplier = 0,
				AutoRotate = false,
			},
		},
		Freeze = {
			DisplayName = "Freeze",
			Duration = 3,
			Priority = 25,
			ForcesCarryDrop = false,
			Movement = {
				WalkSpeedMultiplier = 0,
				JumpMultiplier = 0,
				AutoRotate = false,
			},
		},
		Slow = {
			DisplayName = "Slow",
			Duration = 1.5,
			Priority = 10,
			ForcesCarryDrop = false,
			Movement = {
				WalkSpeedMultiplier = 0.65,
				JumpMultiplier = 1,
			},
		},
		LightHit = {
			DisplayName = "LightHit",
			Duration = 0.2,
			Priority = 5,
			ForcesCarryDrop = false,
			Movement = {
				WalkSpeedMultiplier = 0.9,
				JumpMultiplier = 1,
			},
		},
	},
}

function HitEffects.GetEffect(effectName)
	if typeof(effectName) ~= "string" or effectName == "" then
		return nil
	end

	return HitEffects.EffectsByName[effectName]
end

return HitEffects
