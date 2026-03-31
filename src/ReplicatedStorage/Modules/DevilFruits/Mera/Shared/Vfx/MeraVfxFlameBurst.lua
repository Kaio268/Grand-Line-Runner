local MeraVfxFlameBurst = {}

function MeraVfxFlameBurst.Create(deps)
	local Config = deps.Config
	local DevilFruitConfig = deps.DevilFruitConfig
	local buildPathLabel = deps.BuildPathLabel
	local logInfo = deps.LogInfo
	local playEffect = deps.PlayEffect
	local scheduleFireBurstDisperse = deps.ScheduleFireBurstDisperse

	local function playFireBurstStartup(options)
		options = options or {}
		return playEffect("FireBurst", Config.FlameBurst.EffectCandidates, Config.FlameBurst.StartupChildCandidates, {
			RootPart = options.RootPart,
			Direction = options.Direction,
			LocalOffset = options.LocalOffset,
			Lifetime = math.max(1.5, tonumber(options.Lifetime) or 1.5),
			DefaultEmitCount = tonumber(options.DefaultEmitCount) or 16,
			Scale = tonumber(options.Scale),
			FollowDuration = math.max(0, tonumber(options.FollowDuration) or 0.18),
			AutoCleanup = options.AutoCleanup ~= false,
		})
	end

	local function playFlameBurst(options)
		options = options or {}
		local duration = math.max(0, tonumber(options.Duration) or 0)
		local radius = math.max(0, tonumber(options.Radius) or 0)
		local abilityConfig = DevilFruitConfig.GetAbility("Mera Mera no Mi", "FireBurst")
		local baseRadius = math.max(1, tonumber(abilityConfig and abilityConfig.VisualBaseRadius) or Config.FlameBurst.LegacyRadius)
		local previousVisualScale = math.max(0.25, Config.FlameBurst.PreviousVisualRadius / baseRadius)
		local visualScale = math.max(0.25, radius / baseRadius)
		local selectedPath = buildPathLabel(Config.FlameBurst.EffectCandidates, Config.FlameBurst.BurstChildCandidates)
		logInfo("move=FlameBurst visualScale old=%.2f new=%.2f", previousVisualScale, visualScale)
		logInfo("move=FlameBurst selected path=%s", selectedPath)

		local state = playEffect("FlameBurst", Config.FlameBurst.EffectCandidates, Config.FlameBurst.BurstChildCandidates, {
			RootPart = options.RootPart,
			Direction = options.Direction,
			LocalOffset = options.LocalOffset,
			Lifetime = math.max(duration + 2.5, 3.0),
			DefaultEmitCount = tonumber(options.DefaultEmitCount) or 30,
			Scale = visualScale,
			AutoCleanup = false,
		})

		if state then
			scheduleFireBurstDisperse(state, duration)
		end

		return state
	end

	return {
		PlayFireBurstStartup = playFireBurstStartup,
		PlayFlameBurst = playFlameBurst,
	}
end

return MeraVfxFlameBurst
