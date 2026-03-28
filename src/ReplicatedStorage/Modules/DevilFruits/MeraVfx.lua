local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local DevilFruitConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Configs"):WaitForChild("DevilFruits"))
local DiagnosticLogLimiter = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("DevilFruits"):WaitForChild("DiagnosticLogLimiter"))

local MeraVfx = {}

local DEBUG_INFO = RunService:IsStudio()
local ROOT_SEGMENTS = { "Assets", "VFX", "Mera" }
local DEFAULT_EMIT_COUNT = 20
local INFO_COOLDOWN = 0.2
local WARN_COOLDOWN = 3
local LEGACY_FIRE_BURST_RADIUS = 10
local PREVIOUS_FIRE_BURST_RADIUS = 50
local DEFAULT_FIRE_BURST_DISPERSE_BUFFER = 0.15
local DEFAULT_FIRE_BURST_DISPERSE_MIN_LIFETIME = 0.35
local DEFAULT_FIRE_BURST_FADE_TIME = 0.22
local DEFAULT_FLAME_DASH_STAGE_LIFETIME = 0.4
local FLAME_DASH_EFFECT_NAME = "Flame Dash"

local function logInfo(message, ...)
	if not DEBUG_INFO then
		return
	end

	if not DiagnosticLogLimiter.ShouldEmit("MeraVfx:INFO", DiagnosticLogLimiter.BuildKey(message, ...), INFO_COOLDOWN) then
		return
	end

	print(string.format("[MERA VFX] " .. message, ...))
end

local function logWarn(message, ...)
	if not DiagnosticLogLimiter.ShouldEmit("MeraVfx:WARN", DiagnosticLogLimiter.BuildKey(message, ...), WARN_COOLDOWN) then
		return
	end

	warn(string.format("[MERA VFX][WARN] " .. message, ...))
end

local function buildPathLabel(effectName, childName)
	local segments = { "ReplicatedStorage" }
	for _, segment in ipairs(ROOT_SEGMENTS) do
		segments[#segments + 1] = segment
	end
	if typeof(effectName) == "string" and effectName ~= "" then
		segments[#segments + 1] = effectName
	end
	if typeof(childName) == "string" and childName ~= "" then
		segments[#segments + 1] = childName
	end

	return table.concat(segments, "/")
end

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

local function iterateSelfAndDescendants(root)
	local items = { root }

	for _, descendant in ipairs(root:GetDescendants()) do
		items[#items + 1] = descendant
	end

	return items
end

local function isActivatableEffect(item)
	return item:IsA("ParticleEmitter")
		or item:IsA("Trail")
		or item:IsA("Beam")
		or item:IsA("Smoke")
		or item:IsA("Fire")
		or item:IsA("Sparkles")
end

local function collectBaseParts(root)
	local baseParts = {}
	if root:IsA("BasePart") then
		baseParts[#baseParts + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			baseParts[#baseParts + 1] = descendant
		end
	end

	return baseParts
end

local function collectAttachments(root)
	local attachments = {}
	if root:IsA("Attachment") then
		attachments[#attachments + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") then
			attachments[#attachments + 1] = descendant
		end
	end

	return attachments
end

local function getPivotCFrame(instance)
	if instance:IsA("Model") then
		return instance:GetPivot()
	end

	if instance:IsA("BasePart") then
		return instance.CFrame
	end

	local baseParts = collectBaseParts(instance)
	if #baseParts > 0 then
		return baseParts[1].CFrame
	end

	return nil
end

local function createAnchorPart(name, cframe)
	local anchorPart = Instance.new("Part")
	anchorPart.Name = name
	anchorPart.Anchored = true
	anchorPart.Transparency = 1
	anchorPart.CanCollide = false
	anchorPart.CanTouch = false
	anchorPart.CanQuery = false
	anchorPart.CastShadow = false
	anchorPart.Size = Vector3.new(0.5, 0.5, 0.5)
	anchorPart.CFrame = cframe
	anchorPart.Parent = Workspace
	return anchorPart
end

local function findRootFolder()
	local current = ReplicatedStorage
	local pathParts = { "ReplicatedStorage" }

	for _, segment in ipairs(ROOT_SEGMENTS) do
		current = current:FindFirstChild(segment)
		pathParts[#pathParts + 1] = segment
		if not current then
			logWarn("missing VFX folder/model/attachment/emitter path=%s detail=missing_folder", table.concat(pathParts, "/"))
			return nil
		end
	end

	return current
end

local function getEffectChild(moveName, effectName, childName)
	local rootFolder = findRootFolder()
	local effectPath = buildPathLabel(effectName)
	local childPath = buildPathLabel(effectName, childName)
	if not rootFolder then
		return nil, childPath
	end

	local effectFolder = rootFolder:FindFirstChild(effectName)
	if not effectFolder then
		logWarn("missing VFX folder/model/attachment/emitter move=%s path=%s detail=missing_effect_folder", tostring(moveName), effectPath)
		return nil, childPath
	end

	local source = effectFolder:FindFirstChild(childName)
	if not source then
		logWarn("missing VFX folder/model/attachment/emitter move=%s path=%s detail=missing_effect_child", tostring(moveName), childPath)
		return nil, childPath
	end

	logInfo("move=%s vfx path selected=%s", tostring(moveName), childPath)
	return source, childPath
end

local function destroyState(state)
	if not state or state.Destroyed then
		return
	end

	state.Destroyed = true
	if typeof(state.Connection) == "RBXScriptConnection" then
		state.Connection:Disconnect()
		state.Connection = nil
	end
	if state.Container and state.Container.Parent then
		state.Container:Destroy()
	end
end

local function computeEffectDisperseLifetime(root)
	if not root then
		return DEFAULT_FIRE_BURST_DISPERSE_MIN_LIFETIME
	end

	local maxLifetime = 0
	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("ParticleEmitter") then
			maxLifetime = math.max(maxLifetime, getNumberRangeMax(item.Lifetime))
		elseif item:IsA("Trail") then
			maxLifetime = math.max(maxLifetime, tonumber(item.Lifetime) or 0)
		elseif item:IsA("Smoke") then
			maxLifetime = math.max(maxLifetime, 0.6)
		elseif item:IsA("Fire") then
			maxLifetime = math.max(maxLifetime, 0.4)
		elseif item:IsA("Sparkles") then
			maxLifetime = math.max(maxLifetime, 0.25)
		end
	end

	return math.max(maxLifetime, DEFAULT_FIRE_BURST_DISPERSE_MIN_LIFETIME)
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

	local resolvedFadeTime = math.max(0.05, tonumber(fadeTime) or DEFAULT_FIRE_BURST_FADE_TIME)
	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("BasePart") and item.Transparency < 1 then
			local tween = TweenService:Create(item, TweenInfo.new(resolvedFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
			})
			tween:Play()
		end
	end
end

local function scheduleFireBurstDisperse(state, duration)
	if not state or state.Destroyed then
		return
	end

	local effectRoot = state.EffectRoot
	if not effectRoot then
		return
	end

	local disperseLifetime = computeEffectDisperseLifetime(effectRoot)
	local cleanupDelay = math.max(
		disperseLifetime + DEFAULT_FIRE_BURST_DISPERSE_BUFFER,
		DEFAULT_FIRE_BURST_FADE_TIME + 0.05
	)

	task.delay(math.max(0, tonumber(duration) or 0), function()
		if state.Destroyed or not state.Container or not state.Container.Parent then
			return
		end

		logInfo("move=FireBurst disperse start")
		disableEffectTree(effectRoot)
		tweenDisperseVisuals(effectRoot, math.min(DEFAULT_FIRE_BURST_FADE_TIME, cleanupDelay))

		task.delay(cleanupDelay, function()
			if state.Destroyed then
				return
			end

			logInfo("move=FireBurst cleanup after disperse")
			destroyState(state)
		end)
	end)
end

local function ensureFallbackAttachment(state, key)
	state.FallbackAttachments = state.FallbackAttachments or {}
	local existing = state.FallbackAttachments[key]
	if existing and existing.Parent then
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = string.format("%s_%s", state.Container.Name, key)
	attachment.Parent = state.AnchorPart
	state.FallbackAttachments[key] = attachment
	return attachment
end

local function ensureTrailAttachments(trailLike, state, label)
	if trailLike.Attachment0 and trailLike.Attachment1 then
		return true
	end

	local attachments = collectAttachments(trailLike.Parent)
	if #attachments >= 2 then
		trailLike.Attachment0 = attachments[1]
		trailLike.Attachment1 = attachments[2]
		return true
	end

	local attachment0 = ensureFallbackAttachment(state, label .. "_A0")
	local attachment1 = ensureFallbackAttachment(state, label .. "_A1")
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

local function normalizeTree(root, state, label)
	local fallbackAttachment = ensureFallbackAttachment(state, label .. "_Fallback")

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("BasePart") then
			makeBasePartSafe(item, state.AnchorPart)
		elseif item:IsA("Attachment") then
			if not item.Parent:IsA("BasePart") and not item.Parent:IsA("Attachment") then
				logWarn("missing VFX folder/model/attachment/emitter path=%s detail=attachment_parent_invalid", tostring(label))
				item.Parent = fallbackAttachment
			end
		elseif item:IsA("ParticleEmitter") then
			if not item.Parent:IsA("Attachment") and not item.Parent:IsA("BasePart") then
				logWarn("missing VFX folder/model/attachment/emitter path=%s detail=emitter_parent_invalid", tostring(label))
				item.Parent = fallbackAttachment
			end
		elseif item:IsA("Trail") or item:IsA("Beam") then
			ensureTrailAttachments(item, state, label)
		elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
			if not item.Parent:IsA("BasePart") then
				logWarn("missing VFX folder/model/attachment/emitter path=%s detail=legacy_effect_parent_invalid", tostring(label))
				item.Parent = state.AnchorPart
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

local function activateTree(root, label, activationOptions)
	local defaultEmitCount = activationOptions
	local emitOnStart = true
	if type(activationOptions) == "table" then
		defaultEmitCount = activationOptions.DefaultEmitCount
		emitOnStart = activationOptions.EmitOnStart ~= false
	end

	local activatedCount = 0

	for _, item in ipairs(iterateSelfAndDescendants(root)) do
		if item:IsA("ParticleEmitter") then
			local emitCount = tonumber(item:GetAttribute("EmitCount")) or defaultEmitCount or DEFAULT_EMIT_COUNT
			item.Enabled = true
			if emitOnStart and emitCount > 0 then
				local ok, err = pcall(function()
					item:Emit(emitCount)
				end)
				if not ok then
					logWarn("missing VFX folder/model/attachment/emitter path=%s detail=emit_failed:%s", tostring(label), tostring(err))
				end
			end
			activatedCount += 1
		elseif item:IsA("Trail") or item:IsA("Beam") then
			if item.Attachment0 and item.Attachment1 then
				item.Enabled = true
				activatedCount += 1
			else
				logWarn("missing VFX folder/model/attachment/emitter path=%s detail=trail_missing_attachments", tostring(label))
			end
		elseif item:IsA("Smoke") or item:IsA("Fire") or item:IsA("Sparkles") then
			item.Enabled = true
			activatedCount += 1
		end
	end

	if activatedCount == 0 then
		logWarn("missing VFX folder/model/attachment/emitter path=%s detail=no_activatable_effects", tostring(label))
	end

	return activatedCount
end

local function computeFacingCFrame(position, direction, fallbackDirection)
	local facing = typeof(direction) == "Vector3" and direction or fallbackDirection
	if typeof(facing) ~= "Vector3" or facing.Magnitude <= 0.01 then
		facing = Vector3.new(0, 0, -1)
	end

	return CFrame.lookAt(position, position + facing.Unit)
end

local function computeAnchorCFrame(options)
	local rotationCorrection = typeof(options.RotationCorrection) == "CFrame" and options.RotationCorrection or CFrame.new()
	local rootPart = options.RootPart
	if rootPart and rootPart.Parent then
		local offset = typeof(options.LocalOffset) == "CFrame" and options.LocalOffset or CFrame.new()
		return rootPart.CFrame * offset * rotationCorrection
	end

	local position = typeof(options.Position) == "Vector3" and options.Position or nil
	if position then
		local positionOffset = typeof(options.PositionOffset) == "Vector3" and options.PositionOffset or Vector3.zero
		position += positionOffset
		return computeFacingCFrame(position, options.Direction, options.FallbackDirection) * rotationCorrection
	end

	return nil
end

local function createState(label, cframe)
	local container = Instance.new("Folder")
	container.Name = string.format("MeraVfx_%s", tostring(label):gsub("%s+", ""))
	container.Parent = Workspace

	local anchorPart = createAnchorPart(container.Name .. "_Anchor", cframe)
	anchorPart.Parent = container

	return {
		Container = container,
		AnchorPart = anchorPart,
		Destroyed = false,
		FallbackAttachments = {},
	}
end

local function startFollowLoop(state, rootPart, localOffset, followDuration)
	if not state or not rootPart or followDuration <= 0 then
		return
	end

	task.spawn(function()
		local endAt = os.clock() + followDuration
		while not state.Destroyed and state.AnchorPart and state.AnchorPart.Parent and rootPart.Parent and os.clock() < endAt do
			state.AnchorPart.CFrame = rootPart.CFrame * localOffset
			RunService.Heartbeat:Wait()
		end
	end)
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

local function playEffect(moveName, effectName, childName, options)
	options = options or {}
	local requestedPath = buildPathLabel(effectName, childName)

	local anchorCFrame = computeAnchorCFrame(options)
	if not anchorCFrame then
		logWarn("missing VFX folder/model/attachment/emitter move=%s path=%s detail=missing_anchor", tostring(moveName), requestedPath)
		return nil, "missing_anchor", requestedPath
	end

	local source, sourcePath = getEffectChild(moveName, effectName, childName)
	if not source then
		return nil, "missing_source", requestedPath
	end

	local state = createState(effectName .. "_" .. childName, anchorCFrame)
	local clone = safeClone(source, sourcePath)
	if not clone then
		destroyState(state)
		return nil, "clone_failed", sourcePath
	end

	local sourcePivot = getPivotCFrame(source)
	if clone:IsA("Attachment") or clone:IsA("ParticleEmitter") or clone:IsA("Trail") or clone:IsA("Beam") then
		clone.Parent = state.AnchorPart
	else
		clone.Parent = state.Container
	end

	if type(options.PrepareClone) == "function" then
		local ok, err = pcall(options.PrepareClone, clone, sourcePath)
		if not ok then
			logWarn("missing VFX folder/model/attachment/emitter path=%s detail=prepare_clone_failed:%s", tostring(sourcePath), tostring(err))
		end
	end

	stripScripts(clone, sourcePath)
	applyPivot(clone, anchorCFrame, sourcePivot)
	applyEffectScale(clone, anchorCFrame, options.Scale)
	normalizeTree(clone, state, sourcePath)
	activateTree(clone, sourcePath, {
		DefaultEmitCount = tonumber(options.DefaultEmitCount) or DEFAULT_EMIT_COUNT,
		EmitOnStart = options.EmitOnStart ~= false,
	})
	state.EffectRoot = clone
	state.SourcePath = sourcePath

	local lifetime = math.max(0.25, tonumber(options.Lifetime) or 1.5)
	if options.AutoCleanup ~= false then
		Debris:AddItem(state.Container, lifetime)
	end

	local rootPart = options.RootPart
	local localOffset = typeof(options.LocalOffset) == "CFrame" and options.LocalOffset or CFrame.new()
	startFollowLoop(state, options.FollowPart or rootPart, localOffset, math.min(lifetime, math.max(0, tonumber(options.FollowDuration) or 0)))

	return state, nil, sourcePath
end

function MeraVfx.LogRemovedPlaceholder(moveName)
	logInfo("removed placeholder VFX move=%s", tostring(moveName))
end

function MeraVfx.PlayFireBurst(options)
	options = options or {}
	local duration = math.max(0, tonumber(options.Duration) or 0)
	local radius = math.max(0, tonumber(options.Radius) or 0)
	local abilityConfig = DevilFruitConfig.GetAbility("Mera Mera no Mi", "FireBurst")
	local baseRadius = math.max(1, tonumber(abilityConfig and abilityConfig.VisualBaseRadius) or LEGACY_FIRE_BURST_RADIUS)
	local previousVisualScale = math.max(0.25, PREVIOUS_FIRE_BURST_RADIUS / baseRadius)
	local visualScale = math.max(0.25, radius / baseRadius)
	logInfo("move=FireBurst visualScale old=%.2f new=%.2f", previousVisualScale, visualScale)

	local state = playEffect("FireBurst", "Fire Burst", "FX", {
		RootPart = options.RootPart,
		Direction = options.Direction,
		LocalOffset = options.LocalOffset,
		Lifetime = math.max(duration + 1.5, 1.8),
		DefaultEmitCount = tonumber(options.DefaultEmitCount) or 30,
		Scale = visualScale,
		AutoCleanup = false,
	})

	if state then
		scheduleFireBurstDisperse(state, duration)
	end

	return state
end

function MeraVfx.PlayFlameDashEffect(options)
	options = options or {}

	local stageName = options.StageName or options.FolderName
	if typeof(stageName) ~= "string" or stageName == "" then
		logWarn("missing VFX folder/model/attachment/emitter move=FlameDash path=%s detail=invalid_stage", buildPathLabel(FLAME_DASH_EFFECT_NAME))
		return nil
	end

	local rootPart = options.RootPart
	local direction = options.Direction
	if not direction and rootPart and rootPart.Parent then
		direction = rootPart.CFrame.LookVector
	end

	return playEffect("FlameDash", FLAME_DASH_EFFECT_NAME, stageName, {
		RootPart = rootPart,
		Direction = direction,
		LocalOffset = options.LocalOffset,
		Lifetime = math.max(0.1, tonumber(options.Lifetime) or DEFAULT_FLAME_DASH_STAGE_LIFETIME),
		DefaultEmitCount = tonumber(options.DefaultEmitCount),
		Scale = tonumber(options.Scale),
		FollowDuration = math.max(0, tonumber(options.FollowDuration) or 0),
		AutoCleanup = options.AutoCleanup ~= false,
	})
end

function MeraVfx.PlayFlameDashBurst(options)
	options = options or {}
	return MeraVfx.PlayFlameDashEffect({
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

return MeraVfx
