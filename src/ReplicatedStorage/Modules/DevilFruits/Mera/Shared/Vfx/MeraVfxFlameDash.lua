local MeraVfxFlameDash = {}

function MeraVfxFlameDash.Create(deps)
	local Config = deps.Config
	local buildPathLabel = deps.BuildPathLabel
	local createRootLockedState = deps.CreateRootLockedState
	local createProceduralHeadEffect = deps.CreateProceduralHeadEffect
	local createProceduralTrailStamp = deps.CreateProceduralTrailStamp
	local createState = deps.CreateState
	local destroyState = deps.DestroyState
	local getPlanarDirection = deps.GetPlanarDirection
	local installRoleCloneOnState = deps.InstallRoleCloneOnState
	local logInfo = deps.LogInfo
	local logWarn = deps.LogWarn
	local playEffect = deps.PlayEffect
	local refreshFlameDashHeadOffset = deps.RefreshFlameDashHeadOffset
	local resolveFlameDashMountTarget = deps.ResolveFlameDashMountTarget
	local resolveFlameDashRoleSpec = deps.ResolveFlameDashRoleSpec
	local stopEffectState = deps.StopEffectState
	local updateFlameDashDashMount = deps.UpdateFlameDashDashMount
	local buildFlameDashMimicDashLocalOffset = deps.BuildFlameDashMimicDashLocalOffset
	local buildFlameDashMimicPartLocalOffset = deps.BuildFlameDashMimicPartLocalOffset
	local buildTrailStampCFrame = deps.BuildTrailStampCFrame

	local function resolveFlameDashStageCandidates(stageName)
		local normalizedStage = string.lower(tostring(stageName or ""))
		if normalizedStage == "startup" or normalizedStage == "start up" then
			return Config.FlameDash.StartupChildCandidates
		end

		if normalizedStage == "dash" or normalizedStage == "fx" or normalizedStage == "body" then
			return Config.FlameDash.HeadAssetCandidates
		end

		if normalizedStage == "part" or normalizedStage == "fx2" or normalizedStage == "trail" then
			return Config.FlameDash.PartAssetCandidates
		end

		return nil
	end

	local function startAttachedFlameDashRole(label, rootPart, spec, roleName, localOffset, options)
		options = options or {}
		local mountPart = options.MountPart or rootPart
		if not mountPart or not mountPart.Parent or not spec or spec.Kind ~= "asset" then
			return nil
		end

		local state = createRootLockedState(label, mountPart, localOffset)
		if not state then
			return nil
		end

		state.Spec = spec
		state.RequestedPath = spec.Path
		state.SelectedPath = spec.Path
		state.AttachmentStyle = "mimic"
		state.Scale = tonumber(options.Scale) and tonumber(options.Scale) > 0 and tonumber(options.Scale) or 1
		state.MountPart = mountPart
		state.MountTargetName = mountPart.Name
		state.CharacterRootPart = rootPart

		if roleName == Config.FlameDash.HeadRole and not updateFlameDashDashMount(state, options.Direction, "start") then
			destroyState(state)
			return nil
		end

		local created = installRoleCloneOnState(state, spec, roleName, {
			DefaultEmitCount = tonumber(options.DefaultEmitCount),
			EmitOnStart = options.EmitOnStart ~= false,
			Scale = state.Scale,
			SharedEmitContext = options.SharedEmitContext,
		})
		if not created then
			destroyState(state)
			return nil
		end

		return state
	end

	local function emitFlameDashTrailStamp(state, position, direction)
		if not state or state.Destroyed then
			return nil
		end

		local stampCFrame = buildTrailStampCFrame(position, direction)
		local stampState = createState("FlameDash_TrailStamp", stampCFrame)
		stampState.SelectedPath = state.SelectedPath
		local created = false
		if state.Spec and state.Spec.Kind == "asset" then
			created = installRoleCloneOnState(stampState, state.Spec, Config.FlameDash.TrailRole, {
				DefaultEmitCount = 8,
				EmitOnStart = true,
				Scale = state.Scale,
			})
		end

		if not created then
			if state.Spec and state.Spec.Kind == "asset" and state.SelectedPath ~= Config.FlameDash.TrailProceduralPath then
				logWarn(
					"move=FlameDash role=trail path=%s detail=asset_inactive_using_procedural",
					tostring(state.Spec.Path)
				)
				logInfo("move=FlameDash selected fx2 path=%s", Config.FlameDash.TrailProceduralPath)
			end
			createProceduralTrailStamp(stampState)
			stampState.SourcePath = Config.FlameDash.TrailProceduralPath
			stampState.SelectedPath = Config.FlameDash.TrailProceduralPath
			state.SelectedPath = Config.FlameDash.TrailProceduralPath
		end

		state.Stamps = state.Stamps or {}
		state.Stamps[#state.Stamps + 1] = stampState
		state.StampCount = (state.StampCount or 0) + 1
		return stampState
	end

	local function cleanupTrailStampsImmediately(state)
		for _, stampState in ipairs(state.Stamps or {}) do
			destroyState(stampState)
		end

		state.Stamps = {}
	end

	local function fadeTrailStamp(stampState, fadeDuration)
		if not stampState or stampState.Destroyed then
			return
		end

		deps.DisableEffectTree(stampState.Container)
		deps.TweenDisperseVisuals(stampState.Container, fadeDuration)
		task.delay(math.max(0.05, fadeDuration) + 0.03, function()
			destroyState(stampState)
		end)
	end

	local function beginOrderedTrailFade(state, options)
		local validStamps = {}
		for _, stampState in ipairs(state.Stamps or {}) do
			if stampState and not stampState.Destroyed and stampState.Container and stampState.Container.Parent then
				validStamps[#validStamps + 1] = stampState
			end
		end

		local holdDuration = math.max(0, tonumber(options.HoldDuration) or Config.FlameDash.Trail.PostStopHoldDuration)
		local fadeDuration = math.max(0.05, tonumber(options.OrderedFadeDuration) or Config.FlameDash.Trail.OrderedFadeDuration)
		local stepInterval = math.max(0.02, tonumber(options.OrderedFadeStepInterval) or Config.FlameDash.Trail.OrderedFadeStepInterval)

		state.Stamps = {}

		task.spawn(function()
			task.wait(holdDuration)

			if type(options.OnOrderedFadeStart) == "function" then
				pcall(options.OnOrderedFadeStart, #validStamps)
			end

			for index, stampState in ipairs(validStamps) do
				if type(options.OnOrderedFadeStep) == "function" then
					pcall(options.OnOrderedFadeStep, index, #validStamps)
				end

				fadeTrailStamp(stampState, fadeDuration)
				task.wait(stepInterval)
			end

			task.wait(fadeDuration + 0.05)
			if type(options.OnOrderedFadeComplete) == "function" then
				pcall(options.OnOrderedFadeComplete)
			end
		end)
	end

	local function playFlameDashStartup(options)
		options = options or {}
		local state, failure, sourcePath = playEffect("FlameDash", Config.FlameDash.EffectCandidates, Config.FlameDash.StartupChildCandidates, {
			RootPart = options.RootPart,
			Direction = options.Direction,
			LocalOffset = options.LocalOffset,
			RotationCorrection = Config.FlameDash.StartupRotationCorrection,
			Lifetime = math.max(1.5, tonumber(options.Lifetime) or 1.5),
			DefaultEmitCount = tonumber(options.DefaultEmitCount) or 16,
			Scale = tonumber(options.Scale),
			FollowDuration = math.max(0, tonumber(options.FollowDuration) or 0.12),
			AutoCleanup = options.AutoCleanup ~= false,
			SharedEmitContext = "startup",
		})
		if state and sourcePath then
			logInfo("move=FlameDash startup source=%s", tostring(sourcePath))
		end
		return state, failure, sourcePath
	end

	local api = {}

	function api.PlayFlameDashEffect(options)
		options = options or {}

		local stageName = options.StageName or options.FolderName or Config.FlameDash.PrimaryChildName
		local stageCandidates = resolveFlameDashStageCandidates(stageName)
		if not stageCandidates then
			logWarn("missing VFX folder/model/attachment/emitter move=FlameDash path=%s detail=invalid_stage", buildPathLabel(Config.FlameDash.EffectName))
			return nil
		end

		local rootPart = options.RootPart
		local direction = options.Direction
		if not direction and rootPart and rootPart.Parent then
			direction = rootPart.CFrame.LookVector
		end

		return playEffect("FlameDash", Config.FlameDash.EffectCandidates, stageCandidates, {
			RootPart = rootPart,
			Direction = direction,
			LocalOffset = options.LocalOffset,
			Lifetime = math.max(0.1, tonumber(options.Lifetime) or Config.FlameDash.DefaultStageLifetime),
			DefaultEmitCount = tonumber(options.DefaultEmitCount),
			Scale = tonumber(options.Scale),
			FollowDuration = math.max(0, tonumber(options.FollowDuration) or 0),
			AutoCleanup = options.AutoCleanup ~= false,
		})
	end

	function api.PlayFlameDashBurst(options)
		options = options or {}
		return api.PlayFlameDashEffect({
			StageName = options.StageName or options.FolderName,
			RootPart = options.RootPart,
			Direction = options.Direction,
			LocalOffset = options.LocalOffset,
			Lifetime = options.Lifetime,
			DefaultEmitCount = options.DefaultEmitCount,
			Scale = options.Scale,
			FollowDuration = options.FollowDuration,
			AutoCleanup = options.AutoCleanup,
		})
	end

	function api.StartFlameDashHead(options)
		options = options or {}
		local rootPart = options.RootPart
		if not rootPart or not rootPart.Parent then
			logWarn("move=FlameDash role=head path=%s detail=missing_root_part", Config.FlameDash.HeadProceduralPath)
			return nil
		end

		local spec = resolveFlameDashRoleSpec(Config.FlameDash.HeadRole)
		if spec.Kind == "asset" then
			local mountPart, mountTargetName = resolveFlameDashMountTarget(rootPart, Config.FlameDash.HeadRole)
			local attachedState = startAttachedFlameDashRole(
				"FlameDash_Dash",
				rootPart,
				spec,
				Config.FlameDash.HeadRole,
				buildFlameDashMimicDashLocalOffset(),
				{
					MountPart = mountPart,
					Direction = options.Direction,
					DefaultEmitCount = tonumber(options.DefaultEmitCount) or 12,
					EmitOnStart = options.EmitOnStart ~= false,
					Scale = options.Scale,
					SharedEmitContext = "mounted_dash",
				}
			)
			if attachedState then
				logInfo("move=FlameDash dash mounted target=%s", tostring(mountTargetName))
				return attachedState
			end

			logWarn(
				"move=FlameDash role=head path=%s detail=attached_dash_install_failed_using_procedural",
				tostring(spec.Path)
			)
			logInfo("move=FlameDash selected path=%s", Config.FlameDash.HeadProceduralPath)
		end

		local state = createRootLockedState("FlameDash_Head", rootPart)
		if not state then
			return nil
		end

		if not refreshFlameDashHeadOffset(state) then
			destroyState(state)
			return nil
		end

		state.Spec = spec
		state.RequestedPath = spec.Path
		state.SelectedPath = spec.Path
		state.LastMetricsRefreshAt = os.clock()
		state.Scale = tonumber(options.Scale)
			or math.clamp((state.BodyMetrics and state.BodyMetrics.WidthScale) or 1, 0.75, 1.35)

		if spec.Kind == "asset" and state.SelectedPath ~= Config.FlameDash.HeadProceduralPath then
			logWarn(
				"move=FlameDash role=head path=%s detail=asset_inactive_using_procedural",
				tostring(spec.Path)
			)
			logInfo("move=FlameDash selected path=%s", Config.FlameDash.HeadProceduralPath)
		end

		createProceduralHeadEffect(state)
		return state
	end

	function api.StartFlameDashPart(options)
		options = options or {}
		local rootPart = options.RootPart
		if not rootPart or not rootPart.Parent then
			logWarn("move=FlameDash role=part path=%s detail=missing_root_part", Config.FlameDash.PartProceduralPath)
			return nil
		end

		local spec = resolveFlameDashRoleSpec(Config.FlameDash.PartRole)
		if spec.Kind ~= "asset" then
			logWarn("move=FlameDash role=part path=%s detail=missing_part_asset", tostring(spec.Path))
			return nil
		end

		local mountPart, mountTargetName = resolveFlameDashMountTarget(rootPart, Config.FlameDash.PartRole)
		local state = startAttachedFlameDashRole(
			"FlameDash_Part",
			rootPart,
			spec,
			Config.FlameDash.PartRole,
			buildFlameDashMimicPartLocalOffset(),
			{
				MountPart = mountPart,
				DefaultEmitCount = tonumber(options.DefaultEmitCount) or 12,
				EmitOnStart = options.EmitOnStart ~= false,
				Scale = options.Scale,
				SharedEmitContext = "mounted_part",
			}
		)
		if state then
			logInfo("move=FlameDash part mounted target=%s", tostring(mountTargetName))
		end

		return state
	end

	function api.UpdateFlameDashHead(state, options)
		options = options or {}
		local activeRootPart = state and (state.CharacterRootPart or state.RootPart) or nil
		if not state or state.Destroyed or not activeRootPart or not activeRootPart.Parent then
			return false
		end

		if state.AttachmentStyle == "mimic" then
			return updateFlameDashDashMount(state, options.Direction, "update")
		end

		local refreshInterval = math.max(0.05, tonumber(options.RefreshInterval) or 0.15)
		local now = os.clock()
		if now - (tonumber(state.LastMetricsRefreshAt) or 0) >= refreshInterval then
			if not refreshFlameDashHeadOffset(state) then
				return false
			end
			state.LastMetricsRefreshAt = now
		end

		return true
	end

	function api.UpdateFlameDashPart(state, _options)
		return state ~= nil and state.Destroyed ~= true and state.RootPart ~= nil and state.RootPart.Parent ~= nil
	end

	function api.StopFlameDashHead(state, options)
		local resolvedOptions = {}
		for key, value in pairs(options or {}) do
			resolvedOptions[key] = value
		end

		if resolvedOptions.ImmediateCleanup ~= true and Config.Debug.FlameDashLingerEnabled then
			resolvedOptions.FreezeInPlace = true
			resolvedOptions.HoldDuration = math.max(0, tonumber(resolvedOptions.HoldDuration) or Config.Debug.FlameDashLingerTime)
		end

		return stopEffectState(state, resolvedOptions)
	end

	function api.StopFlameDashPart(state, options)
		local resolvedOptions = {}
		for key, value in pairs(options or {}) do
			resolvedOptions[key] = value
		end

		if resolvedOptions.ImmediateCleanup ~= true and Config.Debug.FlameDashLingerEnabled then
			resolvedOptions.FreezeInPlace = true
			resolvedOptions.HoldDuration = math.max(0, tonumber(resolvedOptions.HoldDuration) or Config.Debug.FlameDashLingerTime)
		end

		return stopEffectState(state, resolvedOptions)
	end

	function api.LogFlameDashCleanup(options)
		options = type(options) == "table" and options or {}
		logInfo(
			"move=FlameDash cleanup startup=%s part=%s dash=%s",
			tostring(options.Startup == true),
			tostring(options.Part == true),
			tostring(options.Dash == true)
		)
	end

	function api.StartFlameDashTrail(options)
		options = options or {}
		local rootPart = options.RootPart
		if not rootPart or not rootPart.Parent then
			logWarn("move=FlameDash role=trail path=%s detail=missing_root_part", Config.FlameDash.TrailProceduralPath)
			return nil
		end

		local spec = resolveFlameDashRoleSpec(Config.FlameDash.TrailRole)
		local selectedPath = spec and spec.Path or Config.FlameDash.TrailProceduralPath
		if not spec then
			logWarn("move=FlameDash role=trail path=%s detail=missing_role_spec_using_procedural", selectedPath)
		end

		return {
			RootPart = rootPart,
			Spec = spec,
			RequestedPath = selectedPath,
			SelectedPath = selectedPath,
			Lifetime = math.max(Config.FlameDash.Trail.StampLifetime, tonumber(options.Lifetime) or Config.FlameDash.Trail.StampLifetime),
			Scale = tonumber(options.Scale),
			StampCount = 0,
			Stamps = {},
			Destroyed = false,
		}
	end

	function api.UpdateFlameDashTrail(state, options)
		options = options or {}
		if not state or state.Destroyed then
			return nil
		end

		local position = typeof(options.Position) == "Vector3" and options.Position or nil
		if typeof(position) ~= "Vector3" then
			return nil
		end

		local direction = getPlanarDirection(options.Direction, state.RootPart and state.RootPart.CFrame.LookVector or Vector3.new(0, 0, -1))
		return emitFlameDashTrailStamp(state, position, direction)
	end

	function api.StopFlameDashTrail(state, options)
		options = options or {}
		if not state or state.Destroyed then
			return false
		end

		if options.ImmediateCleanup == true then
			state.Destroyed = true
			cleanupTrailStampsImmediately(state)
			return true
		end

		local finalPosition = typeof(options.FinalPosition) == "Vector3" and options.FinalPosition or nil
		if finalPosition then
			api.UpdateFlameDashTrail(state, {
				Position = finalPosition,
				Direction = options.Direction,
			})
		end

		state.Destroyed = true
		beginOrderedTrailFade(state, options)
		return true
	end

	api.ResolveFlameDashStageCandidates = resolveFlameDashStageCandidates
	api.StartAttachedFlameDashRole = startAttachedFlameDashRole
	api.EmitFlameDashTrailStamp = emitFlameDashTrailStamp
	api.CleanupTrailStampsImmediately = cleanupTrailStampsImmediately
	api.FadeTrailStamp = fadeTrailStamp
	api.BeginOrderedTrailFade = beginOrderedTrailFade
	api.PlayFlameDashStartup = playFlameDashStartup

	return api
end

return MeraVfxFlameDash
