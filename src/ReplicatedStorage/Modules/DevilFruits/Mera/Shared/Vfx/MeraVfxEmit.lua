local MeraVfxEmit = {}

function MeraVfxEmit.Create(deps)
	local Config = deps.Config
	local Debris = deps.Debris
	local TweenService = deps.TweenService
	local Workspace = deps.Workspace

	local createSharedEmitMetrics = deps.CreateSharedEmitMetrics
	local mergeSharedEmitMetrics = deps.MergeSharedEmitMetrics
	local iterateSelfAndDescendants = deps.IterateSelfAndDescendants
	local collectAttachments = deps.CollectAttachments
	local collectBaseParts = deps.CollectBaseParts
	local getPivotCFrame = deps.GetPivotCFrame
	local formatVector3 = deps.FormatVector3
	local logInfo = deps.LogInfo
	local logWarn = deps.LogWarn
	local isFireBurstBurstLabel = deps.IsFireBurstBurstLabel
	local resolveFireBurstBurstMeshEmitSpawnCFrame = deps.ResolveFireBurstBurstMeshEmitSpawnCFrame

	local defaultEmitCount = Config.Shared.DefaultEmitCount
	local flameBurstFadeTime = Config.FlameBurst.FadeTime

	local activateTree

	local function getNumberRangeMax(range)
		if typeof(range) ~= "NumberRange" then
			return 0
		end

		return math.max(range.Min, range.Max)
	end

	local function scaleNumberRange(range, factor)
		if typeof(range) ~= "NumberRange" then
			return range
		end

		return NumberRange.new(range.Min * factor, range.Max * factor)
	end

	local function scaleNumberSequence(sequence, factor)
		if typeof(sequence) ~= "NumberSequence" then
			return sequence
		end

		local keypoints = {}
		for _, keypoint in ipairs(sequence.Keypoints) do
			keypoints[#keypoints + 1] = NumberSequenceKeypoint.new(
				keypoint.Time,
				keypoint.Value * factor,
				keypoint.Envelope * factor
			)
		end

		return NumberSequence.new(keypoints)
	end

	local function ensureFallbackAttachment(state, key)
		state.FallbackAttachments = state.FallbackAttachments or {}
		local anchorPart = state.AnchorPart
		if typeof(key) == "table" then
			anchorPart = key.AnchorPart or anchorPart
			key = key.Key
		end
		if typeof(anchorPart) ~= "Instance" or not anchorPart:IsA("BasePart") then
			anchorPart = state.AnchorPart
		end

		local storageKey = string.format("%s::%s", tostring(key), anchorPart:GetFullName())
		local existing = state.FallbackAttachments[storageKey]
		if existing and existing.Parent then
			return existing
		end

		local attachment = Instance.new("Attachment")
		attachment.Name = string.format("%s_%s", state.Container.Name, key)
		attachment.Parent = anchorPart
		state.FallbackAttachments[storageKey] = attachment
		return attachment
	end

	local function ensureTrailAttachments(trailLike, state, label, anchorPart)
		if trailLike.Attachment0 and trailLike.Attachment1 then
			return true
		end

		local attachments = collectAttachments(trailLike.Parent)
		if #attachments >= 2 then
			trailLike.Attachment0 = attachments[1]
			trailLike.Attachment1 = attachments[2]
			return true
		end

		local attachment0 = ensureFallbackAttachment(state, {
			Key = label .. "_A0",
			AnchorPart = anchorPart,
		})
		local attachment1 = ensureFallbackAttachment(state, {
			Key = label .. "_A1",
			AnchorPart = anchorPart,
		})
		attachment0.Position = Vector3.new(0, 0, -0.6)
		attachment1.Position = Vector3.new(0, 0, 0.6)
		trailLike.Attachment0 = attachment0
		trailLike.Attachment1 = attachment1
		logWarn("missing VFX folder/model/attachment/emitter path=%s detail=trail_attachment_fallback", tostring(label))
		return false
	end

	local function makeBasePartSafe(part, anchorPart)
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.Massless = true

		if part ~= anchorPart then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = anchorPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local function stripScripts(root, label)
		for _, item in ipairs(root:GetDescendants()) do
			if item:IsA("Script") or item:IsA("LocalScript") or item:IsA("ModuleScript") then
				logWarn("missing VFX folder/model/attachment/emitter path=%s detail=stripped_script:%s", tostring(label), item:GetFullName())
				item:Destroy()
			end
		end
	end

	local function normalizeTree(root, state, label, anchorPart)
		local resolvedAnchorPart = typeof(anchorPart) == "Instance" and anchorPart:IsA("BasePart") and anchorPart or state.AnchorPart
		local fallbackAttachment = ensureFallbackAttachment(state, {
			Key = label .. "_Fallback",
			AnchorPart = resolvedAnchorPart,
		})

		for _, item in ipairs(iterateSelfAndDescendants(root)) do
			if item:IsA("BasePart") then
				makeBasePartSafe(item, resolvedAnchorPart)
			elseif item:IsA("Attachment") then
				if not item.Parent:IsA("BasePart") and not item.Parent:IsA("Attachment") then
					logWarn(
						"missing VFX folder/model/attachment/emitter path=%s detail=attachment_parent_invalid parentClass=%s parentName=%s",
						tostring(label),
						item.Parent.ClassName,
						item.Parent.Name
					)
					item.Parent = fallbackAttachment
				end
			elseif item:IsA("ParticleEmitter") then
				if not item.Parent:IsA("Attachment") and not item.Parent:IsA("BasePart") then
					logWarn(
						"missing VFX folder/model/attachment/emitter path=%s detail=emitter_parent_invalid parentClass=%s parentName=%s",
						tostring(label),
						item.Parent.ClassName,
						item.Parent.Name
					)
					item.Parent = fallbackAttachment
				end
			elseif item:IsA("Trail") or item:IsA("Beam") then
				ensureTrailAttachments(item, state, label, resolvedAnchorPart)
			elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
				if not item.Parent:IsA("BasePart") then
					logWarn("missing VFX folder/model/attachment/emitter path=%s detail=legacy_effect_parent_invalid", tostring(label))
					item.Parent = resolvedAnchorPart
				end
			end
		end
	end

	local function safeClone(source, label)
		local ok, result = pcall(function()
			return source:Clone()
		end)
		if not ok then
			logWarn("missing VFX folder/model/attachment/emitter path=%s detail=clone_failed:%s", tostring(label), tostring(result))
			return nil
		end

		return result
	end

	local function applyPivot(clone, targetPivot, sourcePivot)
		if clone:IsA("Model") then
			clone:PivotTo(targetPivot)
			return
		end

		if clone:IsA("BasePart") then
			clone.CFrame = targetPivot
			return
		end

		local baseParts = collectBaseParts(clone)
		if #baseParts == 0 or not sourcePivot then
			return
		end

		local delta = targetPivot * sourcePivot:Inverse()
		for _, part in ipairs(baseParts) do
			part.CFrame = delta * part.CFrame
		end
	end

	local function processMeshEmit(root, meshEmitOptions)
		local effectsFolder = Workspace:FindFirstChild("Effects") or Workspace
		local count = 0
		local metrics = createSharedEmitMetrics()
		local resolvedOptions = type(meshEmitOptions) == "table" and meshEmitOptions or { DefaultSpawnCFrame = meshEmitOptions }
		local defaultSpawnCFrame = typeof(resolvedOptions.DefaultSpawnCFrame) == "CFrame" and resolvedOptions.DefaultSpawnCFrame or nil
		local localDefaultEmitCount = tonumber(resolvedOptions.DefaultEmitCount)
		local emitOnStart = resolvedOptions.EmitOnStart ~= false
		local effectLabel = tostring(resolvedOptions.Label or "")

		local shellsToDestroy = {}

		for _, model in ipairs(root:GetDescendants()) do
			if not model:IsA("Model") then
				continue
			end

			local startPart = model:FindFirstChild("Start")
			local endPart = model:FindFirstChild("End")
			if not startPart or not endPart then
				continue
			end
			if not startPart:IsA("BasePart") or not endPart:IsA("BasePart") then
				continue
			end

			local meshLifetime = math.max(0.05, tonumber(model:GetAttribute("Lifetime")) or 0.5)
			local delay = math.max(0, tonumber(model:GetAttribute("Delay")) or tonumber(model:GetAttribute("EmitDelay")) or 0)
			local easingStyleName = tostring(model:GetAttribute("EasingStyle") or "Quad")
			local easingDirName = tostring(model:GetAttribute("EasingDirection") or "Out")
			local easingStyle = Enum.EasingStyle[easingStyleName] or Enum.EasingStyle.Quad
			local easingDir = Enum.EasingDirection[easingDirName] or Enum.EasingDirection.Out

			local startMesh = startPart:FindFirstChildOfClass("SpecialMesh")
			local endMesh = endPart:FindFirstChildOfClass("SpecialMesh")
			local endSize = (endMesh and endMesh.Scale) or endPart.Size
			local endTransparency = endPart.Transparency
			local relativeOffset = startPart.CFrame:ToObjectSpace(endPart.CFrame)

			local spawnCFrame, corrected, modelLocalOffset, startLocalOffset, endLocalOffset = resolveFireBurstBurstMeshEmitSpawnCFrame(
				model,
				startPart,
				endPart,
				defaultSpawnCFrame,
				effectLabel
			)
			local finalLocalOffset = typeof(defaultSpawnCFrame) == "CFrame" and defaultSpawnCFrame:ToObjectSpace(spawnCFrame) or nil
			if isFireBurstBurstLabel(effectLabel) then
				logInfo(
					"move=FlameBurst burst meshEmit subgroup=%s path=%s corrected=%s worldPos=%s localOffset=%s finalLook=%s finalRight=%s finalUp=%s modelLocalOffset=%s startLocalOffset=%s endLocalOffset=%s",
					tostring(model.Name),
					tostring(model:GetFullName()),
					tostring(corrected),
					formatVector3(spawnCFrame.Position),
					formatVector3(finalLocalOffset and finalLocalOffset.Position or nil),
					formatVector3(spawnCFrame.LookVector),
					formatVector3(spawnCFrame.RightVector),
					formatVector3(spawnCFrame.UpVector),
					formatVector3(modelLocalOffset and modelLocalOffset.Position or nil),
					formatVector3(startLocalOffset and startLocalOffset.Position or nil),
					formatVector3(endLocalOffset and endLocalOffset.Position or nil)
				)
			end

			local clone = startPart:Clone()
			clone.Anchored = true
			clone.CanCollide = false
			clone.CanTouch = false
			clone.CanQuery = false
			clone.CastShadow = false

			if typeof(spawnCFrame) == "CFrame" then
				clone.CFrame = spawnCFrame
			end
			clone.Parent = effectsFolder

			local targetCFrame = clone.CFrame * relativeOffset

			local _, cloneActivationMetrics = activateTree(clone, model:GetFullName(), {
				DefaultEmitCount = localDefaultEmitCount or defaultEmitCount,
				EmitOnStart = emitOnStart,
				SuppressEmptyWarning = true,
			})
			mergeSharedEmitMetrics(metrics, cloneActivationMetrics)
			metrics.MeshEmitModels += 1

			task.delay(delay, function()
				if not clone.Parent then
					return
				end

				local tweenInfo = TweenInfo.new(meshLifetime, easingStyle, easingDir)
				local partGoals = { Transparency = endTransparency, CFrame = targetCFrame }

				local cloneMesh = clone:FindFirstChildOfClass("SpecialMesh")
				if cloneMesh and endMesh then
					TweenService:Create(cloneMesh, tweenInfo, { Scale = endSize }):Play()
				else
					partGoals.Size = endSize
				end

				TweenService:Create(clone, tweenInfo, partGoals):Play()
			end)

			Debris:AddItem(clone, delay + meshLifetime + 0.5)
			count += 1
			table.insert(shellsToDestroy, model)
		end

		for _, shell in ipairs(shellsToDestroy) do
			if shell.Parent then
				shell:Destroy()
			end
		end

		return count, metrics
	end

	activateTree = function(root, label, activationOptions)
		local localDefaultEmitCount = activationOptions
		local emitOnStart = true
		local suppressEmptyWarning = false
		if type(activationOptions) == "table" then
			localDefaultEmitCount = activationOptions.DefaultEmitCount
			emitOnStart = activationOptions.EmitOnStart ~= false
			suppressEmptyWarning = activationOptions.SuppressEmptyWarning == true
		end

		local activatedCount = 0
		local metrics = createSharedEmitMetrics()

		for _, item in ipairs(iterateSelfAndDescendants(root)) do
			if item:IsA("ParticleEmitter") then
				local emitCount = tonumber(item:GetAttribute("EmitCount")) or localDefaultEmitCount or defaultEmitCount
				local emitDelay = math.max(0, tonumber(item:GetAttribute("EmitDelay")) or 0)
				local emitDuration = tonumber(item:GetAttribute("EmitDuration"))
				item.Enabled = true
				if emitOnStart and emitCount > 0 then
					task.delay(emitDelay, function()
						if not item.Parent then
							return
						end

						local ok, err = pcall(function()
							item:Emit(emitCount)
						end)
						if not ok then
							logWarn("missing VFX folder/model/attachment/emitter path=%s detail=emit_failed:%s", tostring(label), tostring(err))
						end
					end)
				end
				if emitDuration then
					task.delay(emitDelay + math.max(0, emitDuration), function()
						if item.Parent then
							item.Enabled = false
						end
					end)
				end
				activatedCount += 1
				metrics.Activated += 1
				metrics.ParticleEmitters += 1
				if emitOnStart and emitCount > 0 then
					metrics.EmittedParticles += emitCount
				end
			elseif item:IsA("Trail") or item:IsA("Beam") then
				if item.Attachment0 and item.Attachment1 then
					item.Enabled = true
					activatedCount += 1
					metrics.Activated += 1
					if item:IsA("Trail") then
						metrics.Trails += 1
					else
						metrics.Beams += 1
					end
				else
					logWarn("missing VFX folder/model/attachment/emitter path=%s detail=trail_missing_attachments", tostring(label))
				end
			elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
				item.Enabled = true
				activatedCount += 1
				metrics.Activated += 1
				metrics.LegacyEffects += 1
			elseif item:IsA("Sound") then
				local ok, err = pcall(function()
					item:Play()
				end)
				if not ok then
					logWarn("missing VFX folder/model/attachment/emitter path=%s detail=sound_play_failed:%s", tostring(label), tostring(err))
				else
					activatedCount += 1
					metrics.Activated += 1
					metrics.Sounds += 1
				end
			elseif item:IsA("PointLight") or item:IsA("SpotLight") or item:IsA("SurfaceLight") then
				item.Enabled = true
				activatedCount += 1
				metrics.Activated += 1
				metrics.Lights += 1
			end
		end

		if activatedCount == 0 and suppressEmptyWarning ~= true then
			logWarn("missing VFX folder/model/attachment/emitter path=%s detail=no_activatable_effects", tostring(label))
		end

		return activatedCount, metrics
	end

	local function sharedEmitTree(root, activationRoot, label, options)
		options = options or {}

		local metrics = createSharedEmitMetrics()
		local processRoot = options.ProcessRoot or root
		local meshEmitCount, meshEmitMetrics = processMeshEmit(processRoot, {
			DefaultSpawnCFrame = options.AnchorCFrame,
			DefaultEmitCount = tonumber(options.DefaultEmitCount),
			EmitOnStart = options.EmitOnStart ~= false,
			Label = label,
		})
		if type(options.NormalizeCallback) == "function" then
			options.NormalizeCallback()
		end
		local _, activationMetrics = activateTree(activationRoot or root, label, {
			DefaultEmitCount = tonumber(options.DefaultEmitCount),
			EmitOnStart = options.EmitOnStart ~= false,
		})
		mergeSharedEmitMetrics(metrics, meshEmitMetrics)
		mergeSharedEmitMetrics(metrics, activationMetrics)
		metrics.MeshEmitModels = math.max(metrics.MeshEmitModels, tonumber(meshEmitCount) or 0)

		local contextLabel = tostring(options.ContextLabel or "")
		if contextLabel ~= "" and tostring(options.MoveName or "") ~= "" then
			logInfo(
				"move=%s sharedEmit context=%s emittedParticles=%d meshEmitModels=%d sounds=%d beams=%d trails=%d lights=%d",
				tostring(options.MoveName),
				contextLabel,
				math.floor(metrics.EmittedParticles or 0),
				math.floor(metrics.MeshEmitModels or 0),
				math.floor(metrics.Sounds or 0),
				math.floor(metrics.Beams or 0),
				math.floor(metrics.Trails or 0),
				math.floor(metrics.Lights or 0)
			)
		end

		return metrics
	end

	local function applyEffectScale(root, anchorCFrame, effectScale)
		local scale = math.max(0.05, tonumber(effectScale) or 1)
		if math.abs(scale - 1) <= 0.001 then
			return
		end

		for _, item in ipairs(iterateSelfAndDescendants(root)) do
			if item:IsA("BasePart") then
				local localCFrame = anchorCFrame:ToObjectSpace(item.CFrame)
				local rotation = localCFrame - localCFrame.Position
				item.Size = item.Size * scale
				item.CFrame = anchorCFrame * CFrame.new(localCFrame.Position * scale) * rotation
			elseif item:IsA("Attachment") then
				item.Position = item.Position * scale
			elseif item:IsA("ParticleEmitter") then
				item.Size = scaleNumberSequence(item.Size, scale)
				item.Speed = scaleNumberRange(item.Speed, scale)
				item.Acceleration = item.Acceleration * scale
			elseif item:IsA("Trail") then
				item.WidthScale = scaleNumberSequence(item.WidthScale, scale)
			elseif item:IsA("Beam") then
				item.Width0 *= scale
				item.Width1 *= scale
				item.CurveSize0 *= scale
				item.CurveSize1 *= scale
			elseif item:IsA("Smoke") then
				item.Size *= scale
				item.RiseVelocity *= math.sqrt(scale)
			elseif item:IsA("Fire") then
				item.Size *= scale
				item.Heat *= scale
			end
		end
	end

	local function disableEffectTree(root)
		if not root then
			return
		end

		for _, item in ipairs(iterateSelfAndDescendants(root)) do
			if item:IsA("ParticleEmitter")
				or item:IsA("Trail")
				or item:IsA("Beam")
				or item:IsA("Smoke")
				or item:IsA("Fire")
				or item:IsA("Sparkles")
			then
				item.Enabled = false
			end
		end
	end

	local function tweenDisperseVisuals(root, fadeTime)
		if not root then
			return
		end

		local resolvedFadeTime = math.max(0.05, tonumber(fadeTime) or flameBurstFadeTime)
		for _, item in ipairs(iterateSelfAndDescendants(root)) do
			if item:IsA("BasePart") and item.Transparency < 1 then
				local tween = TweenService:Create(item, TweenInfo.new(resolvedFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
				})
				tween:Play()
			end
		end
	end

	return {
		GetNumberRangeMax = getNumberRangeMax,
		ScaleNumberRange = scaleNumberRange,
		ScaleNumberSequence = scaleNumberSequence,
		EnsureFallbackAttachment = ensureFallbackAttachment,
		EnsureTrailAttachments = ensureTrailAttachments,
		MakeBasePartSafe = makeBasePartSafe,
		StripScripts = stripScripts,
		NormalizeTree = normalizeTree,
		SafeClone = safeClone,
		ApplyPivot = applyPivot,
		ProcessMeshEmit = processMeshEmit,
		ActivateTree = activateTree,
		SharedEmitTree = sharedEmitTree,
		ApplyEffectScale = applyEffectScale,
		DisableEffectTree = disableEffectTree,
		TweenDisperseVisuals = tweenDisperseVisuals,
	}
end

return MeraVfxEmit
